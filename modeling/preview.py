# 書き出した glb を読み直して確かめの絵を描く（debug/modeling/ へ・git 管理外）。
#   cd modeling && devbox run -- blender -b --factory-startup --python preview.py -- viewmodel_pistol [fovY 度]
#   ビューモデル: <名前>_cam.png（目の位置からの構図・16:9）・<名前>_poses.png（各クリップの何コマか）・<名前>_orbit.png（斜めから全体）
#   ピックアップ: <名前>_orbit.png（床に置いた形を 2 方向から）
#   クリーチャー（名前が creature_ で始まる）: <名前>_orbit.png（斜め 3 方向）・<名前>_poses.png（各クリップの何コマか・横から）・
#     <名前>_dark.png（灯りをほぼ消した通路で発光だけ見る）。名前を 2 つ以上渡すと lineup.png（並べたシルエットと暗がり）
import bpy, os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from mathutils import Vector, Euler

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.join(HERE, "..", "assets", "models")
DEBUG = os.path.join(HERE, "..", "debug", "modeling")
args = sys.argv[sys.argv.index("--") + 1:]
NAME = args[0]
CREATURES = [a for a in args if a.startswith("creature_")]
FOVY = float(args[1]) if len(args) > 1 and not CREATURES else 55.0
W, H = 640, 360

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 24
sc.cycles.use_denoising = True
sc.render.fps = 60
sc.view_settings.view_transform = "Standard"
arm, meshes = None, []
if not CREATURES:
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, NAME + ".glb"))
    arm = next((o for o in sc.objects if o.type == "ARMATURE"), None)
    meshes = [o for o in sc.objects if o.type == "MESH" and not o.hide_render and not o.hide_get() and len(o.data.vertices) > 64]
    print("meshes:", [(o.name, o.hide_render, len(o.data.vertices)) for o in sc.objects if o.type == "MESH"])

# 光: 薄暗い通路。上の前から冷たい灯り・後ろの左から弱い縁の光・ほのかな地の光
w = bpy.data.worlds.new("w")
sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.012, 0.016, 0.022, 1)
w.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0


def light(name, kind, loc, rot, energy, color, size=0.3):
    ld = bpy.data.lights.new(name, kind)
    ld.energy = energy
    ld.color = color
    if kind == "AREA":
        ld.size = size
    o = bpy.data.objects.new(name, ld)
    o.location = loc
    o.rotation_euler = [math.radians(a) for a in rot]
    sc.collection.objects.link(o)
    return o


def camera(loc, rot, fovy=None, ortho=None):
    cd = bpy.data.cameras.new("cam")
    if ortho:
        cd.type = "ORTHO"
        cd.ortho_scale = ortho
    else:
        cd.sensor_fit = "VERTICAL"
        cd.angle_y = math.radians(fovy)
    cd.clip_start = 0.01
    c = bpy.data.objects.new("cam", cd)
    c.location = loc
    c.rotation_euler = [math.radians(a) for a in rot]
    sc.collection.objects.link(c)
    sc.camera = c
    return c


def render(path, w, h):
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.resolution_percentage = 100
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def load_px(path):
    img = bpy.data.images.load(path)
    px = np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4)
    bpy.data.images.remove(img)
    return px


def save_px(px, path):
    im = bpy.data.images.new("sheet", px.shape[1], px.shape[0], alpha=True)
    im.pixels[:] = px.ravel()
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)


def set_pose(action, frame, arm=None):
    arm = arm or globals()["arm"]
    if arm is None:
        return
    arm.animation_data_create()
    act = bpy.data.actions[action]
    arm.animation_data.action = act
    if act.slots:
        arm.animation_data.action_slot = act.slots[0]
    for t in arm.animation_data.nla_tracks:
        t.mute = True
    sc.frame_set(frame)
    bpy.context.view_layer.update()


def bounds():
    deps = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in meshes:
        e = o.evaluated_get(deps)
        pts += [e.matrix_world @ v.co for v in e.data.vertices]
    a = np.array([tuple(p) for p in pts])
    return Vector(a.min(0)), Vector(a.max(0))


def floor_and_lights(dark):
    """通路の床と灯り。dark = 灯りをほぼ消し、発光だけで形が分かるかを見る。"""
    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
    fm = bpy.data.materials.new("floor")
    fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.03, 0.034, 0.04, 1)
    fm.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.5
    bpy.context.active_object.data.materials.append(fm)
    k = 0.06 if dark else 1.0
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.4 if dark else 1.0
    light("key", "AREA", (1.6, -2.2, 3.4), (40, 0, 35), 260 * k, (0.75, 0.9, 1.0), 1.5)
    light("rim", "AREA", (-1.8, 2.2, 2.6), (-50, 0, 215), 160 * k, (0.55, 0.8, 1.0), 1.0)


def import_creature(name, x):
    before = set(sc.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(MODELS, name + ".glb"))
    new = [o for o in sc.objects if o not in before]
    a = next(o for o in new if o.type == "ARMATURE")
    a.location.x += x
    return a, [o for o in new if o.type == "MESH"]


def creature_bounds(ms):
    deps = bpy.context.evaluated_depsgraph_get()
    pts = np.array([tuple(o.evaluated_get(deps).matrix_world @ v.co) for o in ms for v in o.evaluated_get(deps).data.vertices])
    return Vector(pts.min(0)), Vector(pts.max(0))


def view(ctr, yaw, pitch, ortho, dist=12.0):
    a, p = math.radians(yaw), math.radians(pitch)
    d = Vector((math.sin(a) * math.cos(p), -math.cos(a) * math.cos(p), math.sin(p)))
    return camera(ctr + d * dist, (90 - pitch, 0, yaw), None, ortho)


# 攻撃が当たる・吐くコマ（creature.py のクリップと合わせる）
IMPACT = {"creature_melee": 30, "creature_ranged": 36}


def creature_sheets(names):
    tmp = os.path.join(DEBUG, "_tmp.png")
    if len(names) > 1:
        rigs = []
        for i, n in enumerate(names):
            a, ms = import_creature(n, (i - (len(names) - 1) / 2) * 1.6)
            set_pose("idle", 0, a)
            rigs.append(ms)
        allm = [m for ms in rigs for m in ms]
        lo, hi = creature_bounds(allm)
        ctr = (lo + hi) / 2
        floor_and_lights(False)
        tiles = []
        for yaw in (-25, -60):
            c = view(ctr, yaw, 8, max(hi.z - lo.z, hi.x - lo.x) * 1.25)
            render(tmp, 560, 420)
            tiles.append(load_px(tmp))
            bpy.data.objects.remove(c, do_unlink=True)
        for o in list(sc.objects):
            if o.type == "LIGHT":
                bpy.data.objects.remove(o, do_unlink=True)
        floor_and_lights(True)
        c = view(ctr, -25, 8, max(hi.z - lo.z, hi.x - lo.x) * 1.25)
        render(tmp, 560, 420)
        tiles.append(load_px(tmp))
        save_px(np.concatenate(tiles, axis=1), os.path.join(DEBUG, "lineup.png"))
        os.remove(tmp)
        return
    name = names[0]
    a, ms = import_creature(name, 0.0)
    print("actions:", [(x.name, tuple(x.frame_range)) for x in bpy.data.actions])
    floor_and_lights(False)
    set_pose("idle", 0, a)
    lo, hi = creature_bounds(ms)
    ctr = Vector((0, 0, (hi.z) / 2))
    tiles = []
    for yaw in (-35, -90, 150):
        c = view(ctr, yaw, 12, hi.z * 1.25)
        render(tmp, 420, 560)
        tiles.append(load_px(tmp))
        bpy.data.objects.remove(c, do_unlink=True)
    save_px(np.concatenate(tiles, axis=1), os.path.join(DEBUG, name + "_orbit.png"))
    acts = {x.name: x for x in bpy.data.actions}
    rows = []
    for clip in ("idle", "walk", "attack", "hit", "die"):
        if clip not in acts:
            continue
        end = int(acts[clip].frame_range[1])
        hit = IMPACT.get(name, end // 2)
        picks = {"attack": [0, hit - 12, hit - 5, hit, hit + 8, end]}.get(clip, [round(end * k / 5) for k in range(6)])
        tl = []
        for f in picks:
            set_pose(clip, f, a)
            c = view(Vector((0, -0.55, 1.2)), -90, 6, 3.6)
            render(tmp, 260, 300)
            tl.append(load_px(tmp))
            bpy.data.objects.remove(c, do_unlink=True)
        rows.append(np.concatenate(tl, axis=1))
        print("poses", clip, picks)
    save_px(np.concatenate(rows[::-1], axis=0), os.path.join(DEBUG, name + "_poses.png"))
    for o in list(sc.objects):
        if o.type == "LIGHT":
            bpy.data.objects.remove(o, do_unlink=True)
    for o in list(sc.objects):
        if o.type == "MESH" and o.name.startswith("Plane"):
            bpy.data.objects.remove(o, do_unlink=True)
    floor_and_lights(True)
    tiles = []
    for clip, f, yaw in (("idle", 0, -35), ("walk", 0, 160)):
        set_pose(clip, f, a)
        c = view(ctr, yaw, 12, hi.z * 1.25)
        render(tmp, 420, 560)
        tiles.append(load_px(tmp))
        bpy.data.objects.remove(c, do_unlink=True)
    save_px(np.concatenate(tiles, axis=1), os.path.join(DEBUG, name + "_dark.png"))
    os.remove(tmp)


if CREATURES:
    creature_sheets(CREATURES)
    print("preview written:", CREATURES)
    sys.exit(0)

print("actions:", [(a.name, tuple(a.frame_range)) for a in bpy.data.actions])
tmp = os.path.join(DEBUG, "_tmp.png")
if arm is not None:
    light("key", "AREA", (0.25, -0.55, 0.55), (55, 0, 155), 18, (0.80, 0.90, 1.0), 0.6)
    light("rim", "AREA", (-0.5, 0.2, 0.15), (80, 0, -110), 6, (0.6, 0.75, 1.0), 0.4)
    light("fill", "AREA", (0.3, 0.1, -0.4), (-120, 0, 30), 2.5, (1.0, 0.85, 0.7), 0.5)
    set_pose(bpy.data.actions[0].name if "idle" not in bpy.data.actions else "idle", 0)
    camera((0, 0, 0), (90, 0, 180), FOVY)
    # 照準の目印（画面の真ん中）を確かめるための小さな点は描かない: 構図は画像の真ん中を基準に見る
    render(os.path.join(DEBUG, NAME + "_cam.png"), W, H)
    # 右下の 4 分の 1 を同じ目の位置から拡大（遠近は同じ・切り抜きと同じ絵）
    cz = sc.objects["cam"].data
    cz.angle_y = 2 * math.atan(math.tan(math.radians(FOVY) / 2) / 2)
    cz.shift_x, cz.shift_y = 0.5, -0.5 * H / W
    render(os.path.join(DEBUG, NAME + "_camzoom.png"), W, H)
    cz.angle_y, cz.shift_x, cz.shift_y = math.radians(FOVY), 0.0, 0.0
    tiles = []
    acts = {a.name: a for a in bpy.data.actions}
    picks = []
    for nm, fr in (("fire", 2), ("fire", 6), ("draw", 0), ("draw", 10), ("reload", 18), ("reload", 32), ("reload", 52), ("reload", 66)):
        k = next((a for a in acts if a == nm or a.startswith(nm + "_") or a.startswith(nm)), None)
        if k:
            picks.append((k, fr))
    mz = sc.objects.get("MUZZLE")
    for k, fr in picks:
        set_pose(k, fr)
        if mz:
            print("pose %s f%d muzzle (%.3f, %.3f, %.3f)" % (k, fr, *mz.matrix_world.to_translation()))
        render(tmp, W // 2, H // 2)
        tiles.append(load_px(tmp))
    while len(tiles) % 2:
        tiles.append(np.zeros_like(tiles[0]))
    rows = [np.concatenate(tiles[i:i + 2], axis=1) for i in range(0, len(tiles), 2)]
    save_px(np.concatenate(rows[::-1], axis=0), os.path.join(DEBUG, NAME + "_poses.png"))
    print("poses:", picks)
    set_pose("idle" if "idle" in acts else list(acts)[0], 0)
    sc.objects["cam"].hide_render = True
    lo, hi = bounds()
    ctr, rad = (lo + hi) / 2, (hi - lo).length / 2
    print("bounds", lo, hi)
    views = [(-120, 18), (-35, 25)]
else:
    lo, hi = bounds()
    ctr, rad = (lo + hi) / 2, (hi - lo).length / 2
    light("key", "AREA", (0.6, -0.8, 1.2), (40, 0, 30), 60, (0.85, 0.92, 1.0), 1.0)
    light("rim", "AREA", (-0.8, 0.6, 0.5), (70, 0, -130), 20, (0.6, 0.75, 1.0), 0.6)
    bpy.ops.mesh.primitive_plane_add(size=4, location=(0, 0, lo.z))
    floor = bpy.context.active_object
    fm = bpy.data.materials.new("floor")
    fm.use_nodes = True
    fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.04, 0.045, 0.05, 1)
    floor.data.materials.append(fm)
    views = [(-30, 30), (-110, 55)]
    W = H = 420
tiles = []
for yaw, pitch in views:
    a, p = math.radians(yaw), math.radians(pitch)
    d = Vector((math.sin(a) * math.cos(p), -math.cos(a) * math.cos(p), math.sin(p)))
    c = camera(ctr + d * rad * 6, (90 - pitch, 0, yaw), None, rad * (2.2 if arm is None else 2.5))
    render(tmp, H if arm is None else W // 1, H)
    tiles.append(load_px(tmp))
    bpy.data.objects.remove(c, do_unlink=True)
save_px(np.concatenate(tiles, axis=1), os.path.join(DEBUG, NAME + "_orbit.png"))
os.remove(tmp)
print("preview written:", NAME)
