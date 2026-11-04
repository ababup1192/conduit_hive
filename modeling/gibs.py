# クリーチャーが弾けた時に飛び散る肉片（骨なし・8 種）を assets/models/gibs.glb へ書き出す。
#   cd modeling && devbox run -- blender -b --factory-startup --python gibs.py
# 塊ごとに別のノード GIB_0..GIB_7。どれも原点は塊の重心・ノードの移動と回しは 0（ゲームが回して飛ばす）。
# 色の作りはクリーチャーと同じ（creaturelib の TONES と発光の筋）。8 つを 1 つの絵へまとめてベイクしてから分ける。
import bpy, bmesh, os, sys, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mathutils import Vector, Matrix, noise
import vmlib as V
import creaturelib as C
from creaturelib import sweep, blob, spike

# 裂けた所の生の肉。筋も通す（crack）ので、断面が暗がりで赤く読める
C.TONES["wound"] = {"front": (0.30, 0.035, 0.028), "back": (0.11, 0.012, 0.016), "crack": 1.0, "rough": 0.3}
# 骨は爪（claw）より白っぽい象牙。暗い肉の中で小さくても形が拾える
C.TONES["bone"] = {"front": (0.30, 0.24, 0.17), "back": (0.10, 0.075, 0.06), "crack": 0.0, "rough": 0.4}

random.seed(7)
SPACING = 0.8   # ベイクの間だけ塊を離して置く（AO が隣の塊を拾わないように）


def lumpy(o, amp, freq=18.0, seed=0.0):
    """頂点を中心から外へ／内へずらしてでこぼこにする（同じ式で毎回同じ形）。"""
    for v in o.data.vertices:
        n = noise.noise(v.co * freq + Vector((seed, seed * 1.7, seed * 0.3)))
        v.co += v.normal * (n * amp)
    return o


def plate(w, d, thick, bend, material, nu=5, nv=4, glow=0.3, seed=1.0):
    """反った甲殻の板。外の縁はぎざぎざ・下の面は wound（剥がれた裏の肉）。"""
    bm = bmesh.new()
    top, bot = [], []
    for j in range(nv):
        rt, rb = [], []
        for i in range(nu):
            u, v = -1 + 2 * i / (nu - 1), -1 + 2 * j / (nv - 1)
            edge = i in (0, nu - 1) or j in (0, nv - 1)
            jag = 1.0 + (noise.noise(Vector((u * 3 + seed, v * 3, seed))) * 0.45 if edge else 0.0)
            x, y = u * w / 2 * jag, v * d / 2 * jag
            z = -bend * (0.6 * u * u + 0.4 * v * v)
            t = thick * (0.55 if edge else 1.0)
            rt.append(bm.verts.new((x, y, z + t / 2)))
            rb.append(bm.verts.new((x * 0.96, y * 0.96, z - t / 2)))
        top.append(rt)
        bot.append(rb)
    under = []
    for j in range(nv - 1):
        for i in range(nu - 1):
            bm.faces.new([top[j][i], top[j][i + 1], top[j + 1][i + 1], top[j + 1][i]])
            under.append(bm.faces.new([bot[j][i], bot[j + 1][i], bot[j + 1][i + 1], bot[j][i + 1]]))
    ring = [(0, i) for i in range(nu)] + [(j, nu - 1) for j in range(1, nv)] + \
           [(nv - 1, i) for i in range(nu - 2, -1, -1)] + [(j, 0) for j in range(nv - 2, 0, -1)]
    for k in range(len(ring)):
        (j0, i0), (j1, i1) = ring[k], ring[(k + 1) % len(ring)]
        bm.faces.new([top[j0][i0], bot[j0][i0], bot[j1][i1], top[j1][i1]])
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    o = V.emit(bm, C.mat(material), None, "plate")
    o.data.materials.append(C.mat("wound"))
    zmid = sum(v.co.z for v in o.data.vertices) / len(o.data.vertices)
    for p in o.data.polygons:
        if p.normal.z < -0.5 and p.center.z < zmid + thick:
            p.material_index = 1
    return C._tag(o, lambda co: glow)


def gib_arm():
    """腕の切れ端: 前腕の一節。片方は裂けて骨が出ている。"""
    a = sweep([((-0.15, 0, 0.000), 0.030, 0.028, {}, 0.5),
               ((-0.10, 0, 0.006), 0.044, 0.040, {}, 0.8),
               ((-0.03, 0, 0.012), 0.052, 0.046, {}, 1.0),
               ((0.05, 0, 0.002), 0.041, 0.038, {}, 0.9),
               ((0.12, 0, -0.004), 0.044, 0.041, {}, 0.7)], "flesh", sides=8)
    lumpy(a, 0.006, 22.0, 1.0)
    w = blob((0.124, 0, -0.004), (0.016, 0.042, 0.040), "wound", seg=8, rings=4, glow=0.8)
    lumpy(w, 0.007, 40.0, 2.0)
    b = spike((0.11, 0.004, 0.0), (0.18, 0.010, 0.006), 0.014, "bone", sides=5, steps=2)
    w2 = blob((-0.152, 0, 0), (0.008, 0.026, 0.024), "wound", seg=6, rings=3, glow=0.6)
    return [a, w, b, w2]


def gib_finger():
    """爪のついた指: 節 3 つと曲がった鉤爪・付け根は裂けている。"""
    f = sweep([((0.00, 0, 0.000), 0.019, 0.017, {}, 1.0),
               ((0.04, 0, 0.010), 0.021, 0.019, {}, 1.0),
               ((0.08, 0, 0.012), 0.017, 0.015, {}, 0.8),
               ((0.11, 0, 0.006), 0.014, 0.012, {}, 0.6)], "hide", sides=6)
    lumpy(f, 0.003, 30.0, 3.0)
    c = spike((0.105, 0, 0.006), (0.175, 0, -0.035), 0.013, "claw", sides=5, steps=4, bend=(0.012, 0, 0.018))
    w = blob((-0.004, 0, 0), (0.008, 0.020, 0.018), "wound", seg=6, rings=4, glow=0.7)
    lumpy(w, 0.004, 50.0, 4.0)
    return [f, c, w]


def gib_shell():
    """甲殻の破片: 反った板と短い棘。裏は剥がれた肉。"""
    p = plate(0.22, 0.15, 0.022, 0.035, "hide", glow=1.0, seed=5.0)
    s = spike((0.02, 0.0, 0.0), (0.05, -0.01, 0.06), 0.014, "claw", sides=5, steps=2)
    return [p, s]


def gib_lump():
    """ぶよぶよの肉塊: 大きなでこぼこの塊に裂けた赤い面が食い込む。"""
    a = blob((0, 0, 0), (0.085, 0.068, 0.056), "flesh", seg=10, rings=7, glow=0.5)
    lumpy(a, 0.016, 14.0, 6.0)
    w = blob((0.045, -0.02, 0.02), (0.045, 0.040, 0.035), "wound", seg=8, rings=4, glow=0.8)
    lumpy(w, 0.008, 30.0, 7.0)
    return [a, w]


def gib_vein():
    """光る筋の通った肉片: 皮の筋に加えて、表を這う光る管と光る袋。"""
    a = blob((0, 0, 0), (0.072, 0.056, 0.050), "hide", seg=8, rings=6, glow=1.0)
    lumpy(a, 0.010, 16.0, 8.0)
    parts = [a]
    for k, (th0, th1, ph) in enumerate(((-0.4, 2.4, 0.5), (2.6, 5.0, -0.2))):
        rings = []
        for s in range(4):
            th = th0 + (th1 - th0) * s / 3
            p = Vector((0.074 * math.cos(th) * math.cos(ph + 0.3 * s), 0.058 * math.sin(th) * math.cos(ph), 0.052 * math.sin(ph + 0.25 * s)))
            rings.append((p * 1.02, 0.0065, 0.0055, {}, 0.0))
        parts.append(sweep(rings, "glow", sides=4))
    parts.append(blob((-0.03, -0.035, 0.03), (0.022, 0.018, 0.018), "glow", seg=6, rings=4))
    w = blob((0.06, 0.02, -0.02), (0.022, 0.035, 0.032), "wound", seg=6, rings=3, glow=0.8)
    parts.append(w)
    return parts


def gib_bone():
    """小さな骨の欠片: 関節の頭と折れた先。肉の切れが少し残る。"""
    b = sweep([((-0.050, 0, 0.000), 0.010, 0.010, {}, 0.0),
               ((-0.044, 0, 0.000), 0.020, 0.018, {}, 0.0),
               ((-0.030, 0, 0.000), 0.016, 0.015, {}, 0.0),
               ((0.020, 0, 0.002), 0.010, 0.009, {}, 0.0),
               ((0.048, 0, 0.004), 0.013, 0.011, {}, 0.0)], "bone", sides=6)
    lumpy(b, 0.0025, 40.0, 9.0)
    w = blob((0.0, 0.004, -0.004), (0.026, 0.012, 0.010), "wound", seg=6, rings=3, glow=0.4)
    return [b, w]


def gib_spine():
    """背の一片: 黒紫の皮に棘が 2 本・下は裂けた肉。"""
    a = blob((0, 0, 0), (0.062, 0.046, 0.034), "hide", seg=8, rings=5, glow=0.6)
    lumpy(a, 0.008, 18.0, 10.0)
    s1 = spike((-0.02, 0, 0.022), (-0.045, 0.01, 0.085), 0.016, "claw", sides=5, steps=3, bend=(-0.01, 0, 0))
    s2 = spike((0.025, 0, 0.020), (0.035, -0.005, 0.065), 0.013, "claw", sides=5, steps=2)
    w = blob((0, 0, -0.022), (0.048, 0.036, 0.016), "wound", seg=8, rings=4, glow=0.8)
    lumpy(w, 0.005, 30.0, 11.0)
    return [a, s1, s2, w]


def gib_scrap():
    """小さな肉の切れ端（数を増やす埋め草）。"""
    a = blob((0, 0, 0), (0.042, 0.032, 0.024), "wound", seg=7, rings=5, glow=0.7)
    lumpy(a, 0.008, 26.0, 12.0)
    return [a]


GIBS = [gib_arm, gib_finger, gib_shell, gib_lump, gib_vein, gib_bone, gib_spine, gib_scrap]

C.reset()
objs = []
for i, build in enumerate(GIBS):
    parts = build()
    V.transform(parts, Matrix.Translation((i * SPACING, 0, 0)))
    for o in parts:
        a = o.data.attributes.new("gid", "INT", "FACE")
        for p in o.data.polygons:
            a.data[p.index].value = i
    objs += parts
body = V.join(objs, "gibs_bake")
C.bake_single_material(body, 512, "gibs")

me = body.data
gid = [d.value for d in me.attributes["gid"].data]
out_objs = []
for i in range(len(GIBS)):
    o = body.copy()
    o.data = me.copy()
    bpy.context.scene.collection.objects.link(o)
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if gid[f.index] != i], context="FACES")
    bm.to_mesh(o.data)
    bm.free()
    o.data.attributes.remove(o.data.attributes["gid"])
    c = V.volume_centroid(o)
    o.data.transform(Matrix.Translation(-c))
    o.location = (0, 0, 0)
    o.name = o.data.name = "GIB_%d" % i
    out_objs.append(o)
bpy.data.objects.remove(body, do_unlink=True)

total = 0
for o in out_objs:
    vs = [v.co for v in o.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    t = V.tri_count([o])
    total += t
    print("%s tris=%d size=%.3f %.3f %.3f longest=%.3f" % (o.name, t, *(hi - lo), max(hi - lo)))
print("gibs total tris=%d" % total)
V.export_glb(os.path.join(V.OUT, "gibs.glb"), animations=False)
