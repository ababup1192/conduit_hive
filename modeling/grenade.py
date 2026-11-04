# 投げる手榴弾（grenade.glb）と床に置くピックアップ（pickup_grenade.glb）を書き出す。どちらも骨なし・材質 1 つ（色の絵と emissive の絵）。
#   cd modeling && devbox run -- blender -b --factory-startup --python grenade.py [-- grenade pickup]
# 手榴弾: 八角の筒・軸は Blender の Z（engine の +Y）・原点は重心。起爆の輪は +X の側。
# ピックアップ: 3 つを立てて並べた台・長い向きは Blender の Y（engine の Z）・原点は床の上の真ん中（engine の y = 0 が床）。
import bpy, bmesh, os, sys, math, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from mathutils import Vector, Matrix
import vmlib as V

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
KINDS = [a for a in args if a in ("grenade", "pickup")] or ["grenade", "pickup"]
SEG = 8
R = 0.038          # 八角の角までの半径（面から面で ≈ 7.0 cm・角から角で 7.6 cm）
GROOVE = 0.033


def torus(c, major, minor, material, m3, nu=8, nv=4):
    bm = bmesh.new()
    rows = []
    for i in range(nu):
        a = 2 * math.pi * i / nu
        ring = []
        for j in range(nv):
            b = 2 * math.pi * (j + 0.5) / nv
            r = major + minor * math.cos(b)
            ring.append(bm.verts.new(Vector((r * math.cos(a), minor * math.sin(b), r * math.sin(a)))))
        rows.append(ring)
    for i in range(nu):
        for j in range(nv):
            a, b = rows[i], rows[(i + 1) % nu]
            bm.faces.new([a[j], a[(j + 1) % nv], b[(j + 1) % nv], b[j]])
    return V.emit(bm, material, Matrix.Translation(c) @ m3.to_4x4(), "ring")


def build_grenade(m4):
    """手榴弾 1 つの部品（m4 で置く）。返す: 部品の並び。"""
    body = V.lathe([(0.026, -0.046), (0.035, -0.041), (R, -0.035), (R, -0.010), (GROOVE, -0.007), (GROOVE, -0.001),
                    (R, 0.002), (R, 0.026), (0.034, 0.033), (0.021, 0.037)], "steel_dark", SEG)
    # 溝の帯は黒鉛の色に（絵の上で帯が分かれ、転がる時に回りが読める）
    body.data.materials.append(V.mat("graphite"))
    for p in body.data.polygons:
        if -0.0085 < p.center.z < 0.0005:
            p.material_index = 1
    fuse = V.lathe([(0.017, 0.035), (0.017, 0.049), (0.013, 0.054)], "steel", SEG)
    lever = V.box((-0.004, -0.0375, 0.028), (0.011, 0.004, 0.036), "steel", rot=(-14, 0, 0))
    ring = torus(Vector((0.028, 0, 0.046)), 0.010, 0.0022, "steel", Matrix.Identity(3))
    lens = V.lathe([(0.0065, 0.0535), (0.0045, 0.0565)], "glow", 6)
    dots = []
    for k in range(3):
        a = math.radians(22.5 + 120 * k)
        c = Vector((math.cos(a) * (GROOVE + 0.001), math.sin(a) * (GROOVE + 0.001), -0.004))
        dots.append(V.box(c, (0.004, 0.004, 0.004), "glow", rot=(0, 0, math.degrees(a))))
    parts = [body, fuse, lever, ring, lens] + dots
    V.transform(parts, m4)
    return parts


def _flat_tree(m, img, col):
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*col, 1.0)
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = img
    for n in nt.nodes:
        n.select = False
    t.select = True
    nt.nodes.active = t


def _bake_pass(o, size, name, setup, fill_mean):
    img = bpy.data.images.new(name + "_raw", size, size, alpha=True, float_buffer=True)
    img.colorspace_settings.name = "Linear Rec.709"
    for m in [s.material for s in o.material_slots]:
        setup(m, img)
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.bake(type="EMIT")
    a = np.empty(size * size * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    a = a.reshape(size, size, 4)
    hit = a[..., 3:] > 0.5
    rgb = a[..., :3]
    fill = rgb[hit[..., 0]].mean(axis=0) if fill_mean else np.zeros(3, dtype=np.float32)
    rgb = np.where(hit, rgb, fill)
    px = np.concatenate([V.to_srgb(rgb), np.ones((size, size, 1), dtype=np.float32)], axis=-1)
    tex = bpy.data.images.new(name, size, size, alpha=False)
    tex.colorspace_settings.name = "sRGB"
    tex.pixels.foreach_set(px.astype(np.float32).ravel())
    tex.file_format = "PNG"
    tex.pack()
    bpy.data.images.remove(img)
    return tex


def bake_one_material(o, size, name):
    """鋼の部品は vmlib の色の作り（AO・角の擦れ）、glow は emissive の絵へ。材質を 1 つにまとめる。"""
    t0 = time.time()
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24
    sc.render.bake.margin = max(4, size // 128)
    sc.render.bake.use_clear = True
    if sc.world is None:
        sc.world = bpy.data.worlds.new("w")
    V.unwrap(o, margin=0.008)
    is_glow = lambda m: m.name.split(".")[0] == "glow"

    def color(m, img):
        if is_glow(m):
            _flat_tree(m, img, tuple(c * 0.3 for c in V.GLOW_COLOR))
        else:
            V._bake_tree(m, img)

    col = _bake_pass(o, size, name + "_color", color, True)
    emit = _bake_pass(o, size, name + "_emit", lambda m, img: _flat_tree(m, img, V.GLOW_COLOR if is_glow(m) else (0, 0, 0)), False)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = col
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    te = nt.nodes.new("ShaderNodeTexImage")
    te.image = emit
    nt.links.new(te.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = V.GLOW_STRENGTH
    bsdf.inputs["Metallic"].default_value = 0.4
    bsdf.inputs["Roughness"].default_value = 0.45
    me = o.data
    for p in me.polygons:
        p.material_index = 0
    me.materials.clear()
    me.materials.append(m)
    print("bake %s %dpx %.1fs" % (name, size, time.time() - t0))


def bounds(o):
    vs = [v.co for v in o.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


def make_grenade():
    V.reset()
    body = V.join(build_grenade(Matrix.Identity(4)), "grenade")
    c = V.volume_centroid(body)
    body.data.transform(Matrix.Translation(-c))
    tris = V.tri_count([body])
    V.harden_normals(body, sharp_deg=40.0)
    bake_one_material(body, 512, "grenade")
    V.export_glb(os.path.join(V.OUT, "grenade.glb"), animations=False)
    lo, hi = bounds(body)
    print("grenade tris=%d size(Blender x,y,z)=%.3f %.3f %.3f centroid_offset=%s" % (tris, *(hi - lo), tuple(round(x, 4) for x in c)))


def make_pickup():
    V.reset()
    parts = []
    # 台: 黒鉛の板・前後の低い鋼の縁・両端の止め金・冷たい光の目印 1 本
    parts.append(V.box((0, 0, 0.007), (0.115, 0.27, 0.014), "graphite", bevel=0.003))
    for x in (-0.05, 0.05):
        parts.append(V.box((x, 0, 0.024), (0.008, 0.25, 0.022), "steel_dark", bevel=0.002))
    for y in (-0.128, 0.128):
        parts.append(V.box((0, y, 0.022), (0.105, 0.010, 0.030), "steel", bevel=0.002))
    parts.append(V.box((0.0545, 0, 0.012), (0.002, 0.16, 0.004), "glow"))
    for k, y in enumerate((-0.082, 0.0, 0.082)):
        parts += build_grenade(V.xf((0, y, 0.014 + 0.046), (0, 0, 35 + 50 * k)))
    body = V.join(parts, "pickup_grenade")
    lo, hi = bounds(body)
    body.data.transform(Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)))
    tris = V.tri_count([body])
    V.harden_normals(body, sharp_deg=40.0)
    # 床の板と一緒にベイクする: 床に触れる所が暗くなる。板は書き出さない
    bpy.ops.mesh.primitive_plane_add(size=3, location=(0, 0, -0.0005))
    floor = bpy.context.active_object
    bake_one_material(body, 512, "pk_grenade")
    bpy.data.objects.remove(floor, do_unlink=True)
    V.export_glb(os.path.join(V.OUT, "pickup_grenade.glb"), animations=False)
    lo, hi = bounds(body)
    print("pickup_grenade tris=%d size(Blender x,y,z)=%.3f %.3f %.3f" % (tris, *(hi - lo)))


for kind in KINDS:
    {"grenade": make_grenade, "pickup": make_pickup}[kind]()
