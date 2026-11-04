# 骨なしの小物（肉片・手榴弾・手榴弾のピックアップ）の確かめの絵を debug/modeling/ へ描く（git 管理外）。
#   cd modeling && devbox run -- blender -b --factory-startup --python preview_props.py [-- gibs grenade pickup_grenade]
#   gibs_lineup.png（8 種を並べて 灯り / 暗がり）・gibs_scatter.png（床に散らした様子 灯り / 暗がり）・
#   grenade_orbit.png（立てた物と寝かせた物を斜めから 灯り 2 方向 / 暗がり）・pickup_grenade_orbit.png（同じ並び）
import bpy, os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from mathutils import Vector, Euler, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.join(HERE, "..", "assets", "models")
DEBUG = os.path.join(HERE, "..", "debug", "modeling")
args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
NAMES = args or ["gibs", "grenade", "pickup_grenade"]
TMP = os.path.join(DEBUG, "_tmp_props.png")


def fresh():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 32
    sc.cycles.use_denoising = True
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.012, 0.016, 0.022, 1)
    bpy.ops.mesh.primitive_plane_add(size=20, location=(0, 0, 0))
    fm = bpy.data.materials.new("floor")
    fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.03, 0.034, 0.04, 1)
    fm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.5
    bpy.context.active_object.data.materials.append(fm)
    return sc


def lights(dark, scale):
    sc = bpy.context.scene
    for o in [o for o in sc.objects if o.type == "LIGHT"]:
        bpy.data.objects.remove(o, do_unlink=True)
    k = (0.05 if dark else 1.0) * scale * scale
    sc.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.4 if dark else 1.0
    for name, loc, rot, e, col, size in (("key", (1.6, -2.2, 3.4), (40, 0, 35), 260, (0.75, 0.9, 1.0), 1.5),
                                         ("rim", (-1.8, 2.2, 2.6), (-50, 0, 215), 160, (0.55, 0.8, 1.0), 1.0)):
        ld = bpy.data.lights.new(name, "AREA")
        ld.energy, ld.color, ld.size = e * k, col, size * scale
        o = bpy.data.objects.new(name, ld)
        o.location = Vector(loc) * scale
        o.rotation_euler = [math.radians(a) for a in rot]
        sc.collection.objects.link(o)


def shot(ctr, yaw, pitch, ortho, w, h):
    sc = bpy.context.scene
    a, p = math.radians(yaw), math.radians(pitch)
    d = Vector((math.sin(a) * math.cos(p), -math.cos(a) * math.cos(p), math.sin(p)))
    cd = bpy.data.cameras.new("cam")
    cd.type = "ORTHO"
    cd.ortho_scale = ortho
    cd.clip_start = 0.001
    c = bpy.data.objects.new("cam", cd)
    c.location = ctr + d * 5
    c.rotation_euler = [math.radians(90 - pitch), 0, a]
    sc.collection.objects.link(c)
    sc.camera = c
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.filepath = TMP
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(c, do_unlink=True)
    img = bpy.data.images.load(TMP)
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    return px


def save(tiles, name):
    px = np.concatenate(tiles, axis=1)
    im = bpy.data.images.new("sheet", px.shape[1], px.shape[0], alpha=True)
    im.pixels[:] = px.ravel()
    im.filepath_raw = os.path.join(DEBUG, name)
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)
    print("wrote", name)


def import_glb(name):
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, name + ".glb"))
    return [o for o in bpy.context.scene.objects if o not in before and o.type == "MESH"]


def rest_on_floor(o, loc, rot):
    o.location = (0, 0, 0)
    o.rotation_mode = "XYZ"
    o.rotation_euler = rot
    bpy.context.view_layer.update()
    z = min((o.matrix_world @ v.co).z for v in o.data.vertices)
    o.location = (loc[0], loc[1], -z)


def gibs():
    fresh()
    ms = sorted(import_glb("gibs"), key=lambda o: o.name)
    print("gib nodes:", [(o.name, tuple(round(x, 3) for x in o.location)) for o in ms])
    for i, o in enumerate(ms):
        rest_on_floor(o, ((i % 4 - 1.5) * 0.38, (i // 4 - 0.5) * 0.36), (0, 0, 0))
    tiles = []
    for dark in (False, True):
        lights(dark, 0.5)
        tiles.append(shot(Vector((0, 0, 0.05)), -12, 32, 1.75, 900, 560))
    save([np.concatenate(tiles[::-1], axis=0)], "gibs_lineup.png")
    random.seed(3)
    copies = []
    for k in range(3):
        for o in ms:
            c = o.copy()
            bpy.context.scene.collection.objects.link(c)
            copies.append(c)
    for o in copies + ms:
        r = random.uniform(0.15, 1.1)
        a = random.uniform(0, 2 * math.pi)
        rest_on_floor(o, (math.cos(a) * r, math.sin(a) * r * 0.8), Euler([random.uniform(0, 6.3) for _ in range(3)]))
    tiles = []
    for dark in (False, True):
        lights(dark, 0.8)
        tiles.append(shot(Vector((0, 0, 0)), -30, 40, 2.6, 560, 420))
    save(tiles, "gibs_scatter.png")


def prop(name, lying):
    fresh()
    ms = import_glb(name)
    o = ms[0]
    print(name, "nodes:", [(m.name, tuple(round(x, 3) for x in m.location)) for m in ms])
    if lying:
        rest_on_floor(o, (-0.06, 0), (0, 0, 0))
        c = o.copy()
        bpy.context.scene.collection.objects.link(c)
        rest_on_floor(c, (0.07, 0.02), (math.radians(90), 0, math.radians(30)))
        ctr, ortho = Vector((0, 0, 0.04)), 0.26
    else:
        bpy.context.view_layer.update()
        ctr, ortho = Vector((0, 0, 0.05)), 0.42
    tiles = []
    lights(False, 0.3)
    for yaw, pitch in ((-35, 28), (-120, 50)):
        tiles.append(shot(ctr, yaw, pitch, ortho, 420, 420))
    lights(True, 0.3)
    tiles.append(shot(ctr, -35, 28, ortho, 420, 420))
    save(tiles, name + "_orbit.png")


for n in NAMES:
    {"gibs": gibs, "grenade": lambda: prop("grenade", True), "pickup_grenade": lambda: prop("pickup_grenade", False)}[n]()
if os.path.exists(TMP):
    os.remove(TMP)
