# ビューモデルとピックアップの共通の道具: 形の部品・骨と重み・クリップの打ち方・法線の整え・AO のベイクし込み・glb の書き出し。
# 寸法はメートル。Blender の Z が上・正面は -Y。ビューモデルの座標はカメラが原点で -Y を向く（右 = -X・下 = -Z）。
# glb の座標は engine では (x, y, z) → (−x, z, −y) の向きになる: Blender の -Y（前）が engine の +Z、Blender の -X（右）が engine の +X。
import bpy, bmesh, os, math, time
import numpy as np
from mathutils import Vector, Matrix, Euler, Quaternion

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "models")
DEBUG = os.path.join(HERE, "..", "debug", "modeling")
os.makedirs(OUT, exist_ok=True)
os.makedirs(DEBUG, exist_ok=True)

FPS = 60

# ── 材質（形を組む間の色分け。ベイクした後は body と glow の 2 つになる） ──
# 色は linear。sRGB にすると steel ≈ 0.46・steel_dark ≈ 0.31・graphite ≈ 0.21。
PALETTE = {
    "steel":      ((0.17, 0.18, 0.195), 0.55, 0.42),   # (色, 金属らしさ, 粗さ)
    "steel_dark": ((0.075, 0.08, 0.09), 0.6, 0.5),
    "graphite":   ((0.034, 0.037, 0.044), 0.2, 0.6),
    "glove":      ((0.045, 0.045, 0.05), 0.0, 0.85),
    "bore":       ((0.008, 0.008, 0.01), 0.3, 0.7),
    "marking":    ((0.42, 0.44, 0.46), 0.1, 0.6),
}
GLOW_COLOR = (0.30, 0.88, 1.0)
GLOW_STRENGTH = 4.0
_mats = {}


def mat(name):
    if name in _mats and _mats[name].name in bpy.data.materials:
        return _mats[name]
    m = bpy.data.materials.new(name)
    col = GLOW_COLOR if name == "glow" else PALETTE[name][0]
    m.diffuse_color = (*col, 1.0)
    m.use_nodes = True
    bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*col, 1.0)
        if name == "glow":
            bsdf.inputs["Emission Color"].default_value = (*GLOW_COLOR, 1.0)
            bsdf.inputs["Emission Strength"].default_value = GLOW_STRENGTH
    _mats[name] = m
    return m


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mats.clear()
    sc = bpy.context.scene
    sc.render.fps = FPS
    sc.unit_settings.system = "METRIC"


# ── 形の部品（どれも閉じた形・法線は外向き） ──
def emit(bm, material, m4=None, name="part", recalc=True):
    if m4 is not None:
        bmesh.ops.transform(bm, matrix=m4, verts=bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat(material) if isinstance(material, str) else material)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    return o


def _bevel(bm, w, segments=1):
    if w > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges) + list(bm.verts), offset=w, offset_type="OFFSET",
                        segments=segments, profile=0.5, affect="EDGES", clamp_overlap=True)


def xf(loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    s = Matrix.Diagonal((*scale, 1.0))
    r = Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
    return Matrix.Translation(loc) @ r @ s


def box(c, size, material, bevel=0.0, rot=(0, 0, 0), taper=None, m4=None):
    """中心 c・大きさ size の箱。taper=(tx, tz) で前（-Y）の面を縮める。rot は中心まわり（度）。"""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        if taper and v.co.y < 0:
            v.co.x *= taper[0]
            v.co.z *= taper[1]
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
    _bevel(bm, min(bevel, *(s * 0.45 for s in size)))
    m = xf(c, rot)
    return emit(bm, material, (m4 @ m) if m4 is not None else m, "box")


def prism(poly, width, material, bevel=0.0, m4=None, axis="X"):
    """YZ 平面の多角形 poly（(y, z) の並び）を X へ幅 width で押し出す（中心は x = 0）。銃の横から見た形をそのまま書く。"""
    bm = bmesh.new()
    a = [bm.verts.new((-width / 2, y, z)) for y, z in poly]
    b = [bm.verts.new((width / 2, y, z)) for y, z in poly]
    bm.faces.new(a)
    bm.faces.new(b)
    n = len(poly)
    for i in range(n):
        k = (i + 1) % n
        bm.faces.new([a[i], a[k], b[k], b[i]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _bevel(bm, bevel)
    return emit(bm, material, m4, "prism")


def lathe(profile, material, seg=12, m4=None, phase=None):
    """回転体（Z が軸）。profile = [(半径, 高さ)]。両端の半径が 0 でなければふたを付ける。"""
    phase = math.pi / seg if phase is None else phase
    prof = list(profile)
    bm = bmesh.new()
    rings = []
    for r, z in prof:
        rings.append([bm.verts.new((r * math.cos(phase + 2 * math.pi * i / seg), r * math.sin(phase + 2 * math.pi * i / seg), z))
                      for i in range(seg)])
    for j in range(len(rings) - 1):
        a, b = rings[j], rings[j + 1]
        for i in range(seg):
            k = (i + 1) % seg
            bm.faces.new([a[i], a[k], b[k], b[i]])
    bm.faces.new(rings[0])
    bm.faces.new(rings[-1])
    return emit(bm, material, m4, "lathe")


def basis_to(d, up_hint=Vector((0, 0, 1))):
    """Z を d へ向け、X を up_hint に垂直に置く行列（3x3）。"""
    z = Vector(d).normalized()
    u = Vector(up_hint)
    if abs(z.dot(u.normalized())) > 0.97:
        u = Vector((1, 0, 0))
    x = u.cross(z).normalized()
    y = z.cross(x)
    return Matrix((x, y, z)).transposed()


def cyl_between(p0, p1, r, material, seg=10, r1=None, up=(0, 0, 1)):
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    m4 = Matrix.Translation(p0) @ basis_to(d, Vector(up)).to_4x4()
    return lathe([(r, 0), (r if r1 is None else r1, d.length)], material, seg, m4)


def seg(p0, p1, width, thick, material, up=(0, 0, 1), bevel=0.003, taper=1.0):
    """p0 から p1 へ伸びる角材（指の節・親指）。width は up に垂直な向き・thick は up の向き。taper で先を細く。"""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    z = d.normalized()
    u = Vector(up) - z * Vector(up).dot(z)
    if u.length < 1e-6:
        u = Vector((1, 0, 0)) - z * z.x
    u.normalize()
    x = u.cross(z)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        k = taper if v.co.z > 0 else 1.0
        v.co = Vector((v.co.x * width * k, v.co.y * thick * k, (v.co.z + 0.5) * d.length))
    _bevel(bm, min(bevel, width * 0.4, thick * 0.4))
    m3 = Matrix((x, u, z)).transposed()
    return emit(bm, material, Matrix.Translation(p0) @ m3.to_4x4(), "seg")


class Wrap:
    """楕円の柱（握る所の断面）のまわりの座標: p(角度 度, 軸に沿う距離 h, 面からの浮き o)。
    角度 0 が e0・90 が e90 の向き。軸 ax は h が増える向き。"""
    def __init__(self, origin, e0, e90, ax, a, b):
        self.o, self.e0, self.e90, self.ax = Vector(origin), Vector(e0).normalized(), Vector(e90).normalized(), Vector(ax).normalized()
        self.a, self.b = a, b

    def p(self, th, h, off=0.0):
        t = math.radians(th)
        return self.o + (self.a + off) * math.cos(t) * self.e0 + (self.b + off) * math.sin(t) * self.e90 + h * self.ax

    def band(self, th0, th1, h0, h1, o0, o1, material, steps=3, bevel=0.003):
        """楕円に沿って曲がった角材（指の節・掌・掌の装甲板）。"""
        bm = bmesh.new()
        cols = []
        for k in range(steps + 1):
            th = th0 + (th1 - th0) * k / steps
            cols.append([bm.verts.new(self.p(th, h, o)) for (h, o) in ((h0, o0), (h0, o1), (h1, o1), (h1, o0))])
        for k in range(steps):
            a, b = cols[k], cols[k + 1]
            for i in range(4):
                j = (i + 1) % 4
                bm.faces.new([a[i], a[j], b[j], b[i]])
        bm.faces.new(cols[0])
        bm.faces.new(cols[-1])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        _bevel(bm, min(bevel, abs(h1 - h0) * 0.35, abs(o1 - o0) * 0.35))
        return emit(bm, material, None, "band")


def tube(p0, p1, radii, material, sides=8, up=(0, 0, 1), squash=1.0, roll=0.0):
    """p0 から p1 への角の数 sides の柱。radii = [(t, 半径)]（t は 0..1）。squash で up の向きを潰す。"""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    m3 = basis_to(d, Vector(up))
    x, y = m3.col[0], m3.col[1]
    bm = bmesh.new()
    rings = []
    for t, r in radii:
        c = p0 + d * t
        ring = []
        for i in range(sides):
            a = 2 * math.pi * (i + 0.5) / sides + math.radians(roll)
            ring.append(bm.verts.new(c + x * (r * math.cos(a)) + y * (r * squash * math.sin(a))))
        rings.append(ring)
    for j in range(len(rings) - 1):
        for i in range(sides):
            k = (i + 1) % sides
            bm.faces.new([rings[j][i], rings[j][k], rings[j + 1][k], rings[j + 1][i]])
    bm.faces.new(rings[0])
    bm.faces.new(rings[-1])
    return emit(bm, material, None, "tube")


def shell(p0, p1, radii, a0, a1, thick, material, steps=4, up=(0, 0, 1), squash=1.0, bevel=0.003):
    """tube のまわりを角度 a0..a1（度・0 が up に垂直な x・90 が up 側）だけ覆う装甲の殻。radii は tube と同じ並び。"""
    p0, p1 = Vector(p0), Vector(p1)
    d = p1 - p0
    m3 = basis_to(d, Vector(up))
    x, y = m3.col[0], m3.col[1]
    bm = bmesh.new()
    cols = []
    for k in range(steps + 1):
        a = math.radians(a0 + (a1 - a0) * k / steps)
        quad = []
        for (t, r), o in ((radii[0], 0.0), (radii[0], thick), (radii[-1], thick), (radii[-1], 0.0)):
            c = p0 + d * t
            quad.append(bm.verts.new(c + x * ((r + o) * math.cos(a)) + y * ((r + o) * squash * math.sin(a))))
        cols.append(quad)
    for k in range(steps):
        a, b = cols[k], cols[k + 1]
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new([a[i], a[j], b[j], b[i]])
    bm.faces.new(cols[0])
    bm.faces.new(cols[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    _bevel(bm, min(bevel, thick * 0.4))
    return emit(bm, material, None, "shell")


def transform(objs, m4):
    for o in objs:
        o.data.transform(m4)


def tri_count(objs):
    return sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)


def volume_centroid(o):
    """閉じた形の重心（三角形ごとの四面体の符号つき体積で重みをつける）。体積がほぼ 0 なら頂点の平均。"""
    me = o.data
    me.calc_loop_triangles()
    vs = me.vertices
    vol, acc = 0.0, Vector((0, 0, 0))
    for t in me.loop_triangles:
        a, b, c = (vs[i].co for i in t.vertices)
        v = a.dot(b.cross(c)) / 6.0
        vol += v
        acc += v * (a + b + c) / 4.0
    if abs(vol) < 1e-12:
        return sum((v.co for v in vs), Vector()) / len(vs)
    return acc / vol


# ── 骨と重み ──
class Rig:
    def __init__(self, name):
        self.name = name
        self.bones = []          # (name, head, tail, parent)
        self.pieces = []         # (object, {骨: 重み} か 座標 → {骨: 重み})

    def bone(self, name, head, tail, parent=None):
        self.bones.append((name, Vector(head), Vector(tail), parent))

    def add(self, objs, weights):
        for o in (objs if isinstance(objs, (list, tuple)) else [objs]):
            self.pieces.append((o, weights))
        return objs

    def build_armature(self):
        bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
        arm = bpy.context.active_object
        arm.name = self.name + "_rig"
        arm.data.name = self.name + "_rig"
        eb = arm.data.edit_bones
        eb.remove(eb[0])
        for name, head, tail, parent in self.bones:
            b = eb.new(name)
            b.head, b.tail, b.roll = head, tail, 0.0
            if parent:
                b.parent = eb[parent]
                b.use_connect = False
        bpy.ops.object.mode_set(mode="OBJECT")
        self.arm = arm
        return arm

    def apply_weights(self):
        for o, w in self.pieces:
            fn = w if callable(w) else (lambda co, w=w: w)
            groups = {}
            for v in o.data.vertices:
                for bone, wt in fn(v.co).items():
                    if bone not in groups:
                        groups[bone] = o.vertex_groups.get(bone) or o.vertex_groups.new(name=bone)
                    groups[bone].add([v.index], wt, "REPLACE")


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    o.data.name = name
    return o


def harden_normals(o, sharp_deg=50.0):
    """大きな平らな面は平らに・面取りの細い面は両隣の面の向きの間をなめらかにつなぐ（Weighted Normal の面積の重み）。
    sharp_deg を超える角（筒のふた・刻みの壁）は切る。"""
    me = o.data
    bm = bmesh.new()
    bm.from_mesh(me)
    lim = math.radians(sharp_deg)
    for e in bm.edges:
        e.smooth = not (len(e.link_faces) == 2 and e.calc_face_angle(0.0) > lim)
    for f in bm.faces:
        f.smooth = True
    bm.to_mesh(me)
    bm.free()
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    m = o.modifiers.new("wn", "WEIGHTED_NORMAL")
    m.mode = "FACE_AREA"
    m.weight = 100
    m.keep_sharp = True
    bpy.ops.object.modifier_apply(modifier=m.name)


# ── 動き: 骨ごとの「休みの形からのずれ」を armature の軸で書く ──
# {"r": (rx, ry, rz) 度（骨の頭のまわり・armature の軸・XYZ の順）, "t": (x, y, z) m, "s": (sx, sy, sz) 骨の頭のまわりの倍率（省くと 1）}。
# 子の骨のずれは、親が動いた後の座標で（休みの形の軸で書いた物を親ごと運ぶ）。名前の無い骨は休みの形。
def delta_matrix(head, spec):
    r = spec.get("r", (0, 0, 0))
    t = Vector(spec.get("t", (0, 0, 0)))
    R = Euler([math.radians(a) for a in r], "XYZ").to_matrix().to_4x4()
    S = Matrix.Diagonal((*spec.get("s", (1, 1, 1)), 1.0))
    return Matrix.Translation(head + t) @ R @ S @ Matrix.Translation(-head)


def set_pose(arm, spec):
    """姿勢 spec を骨へ置く（キーは打たない）。"""
    for pb in arm.pose.bones:
        B = pb.bone.matrix_local
        D = delta_matrix(B.to_translation(), spec.get(pb.name, {}))
        loc, rot, scl = (B.inverted() @ D @ B).decompose()
        pb.rotation_mode = "QUATERNION"
        pb.location = loc
        pb.rotation_quaternion = rot
        pb.scale = scl if "s" in spec.get(pb.name, {}) else (1, 1, 1)


def key(arm, action_name, frames):
    """frames = [(コマ, {骨: spec})]。コマは 0 から（FPS コマで 1 秒）。"""
    act = bpy.data.actions.new(action_name)
    arm.animation_data_create()
    arm.animation_data.action = act
    for frame, spec in frames:
        set_pose(arm, spec)
        for pb in arm.pose.bones:
            pb.keyframe_insert("location", frame=frame)
            pb.keyframe_insert("rotation_quaternion", frame=frame)
            pb.keyframe_insert("scale", frame=frame)
    track = arm.animation_data.nla_tracks.new()
    track.name = action_name
    track.strips.new(action_name, int(frames[0][0]), act)
    arm.animation_data.action = None
    set_pose(arm, {})
    return act


def lerp_spec(a, b, t):
    """2 つの姿勢の間（t = 0 で a）。"""
    out = {}
    for name in set(a) | set(b):
        sa, sb = a.get(name, {}), b.get(name, {})
        out[name] = {k: tuple(x + (y - x) * t for x, y in zip(sa.get(k, z), sb.get(k, z)))
                     for k, z in (("r", (0, 0, 0)), ("t", (0, 0, 0)), ("s", (1, 1, 1))) if k in sa or k in sb or k != "s"}
    return out


# ── ベイクし込み: 形の陰（AO）と角の擦れを、色ごと 1 枚の絵へ ──
AO_DISTANCE = 0.035
EDGE_RADIUS = 0.0035


def _bake_tree(m, img):
    """材質を「ベイクするための発光」に組み直す: 色 × ムラ × AO ＋ 角の擦れ。Cycles の AO と Bevel のノードで作る。"""
    name = m.name.split(".")[0]
    col, _, _ = PALETTE[name]
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    N = nt.nodes.new
    L = nt.links.new
    out = N("ShaderNodeOutputMaterial")
    em = N("ShaderNodeEmission")
    L(em.outputs["Emission"], out.inputs["Surface"])
    tc = N("ShaderNodeTexCoord")
    noise = N("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 55.0
    noise.inputs["Detail"].default_value = 6.0
    L(tc.outputs["Object"], noise.inputs["Vector"])
    big = N("ShaderNodeTexNoise")
    big.inputs["Scale"].default_value = 9.0
    L(tc.outputs["Object"], big.inputs["Vector"])
    ao = N("ShaderNodeAmbientOcclusion")
    ao.samples = 32
    ao.inputs["Distance"].default_value = AO_DISTANCE
    bev = N("ShaderNodeBevel")
    bev.samples = 16
    bev.inputs["Radius"].default_value = EDGE_RADIUS
    geo = N("ShaderNodeNewGeometry")
    dot = N("ShaderNodeVectorMath")
    dot.operation = "DOT_PRODUCT"
    L(bev.outputs["Normal"], dot.inputs[0])
    L(geo.outputs["True Normal"], dot.inputs[1])

    def math_node(op, a=None, b=None, clamp=False):
        n = N("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[i].default_value = v
            else:
                L(v, n.inputs[i])
        return n.outputs[0]

    # 角: 1 − dot(丸めた法線, 本当の面の向き) を強めて 0..1
    edge = math_node("MULTIPLY", math_node("SUBTRACT", 1.0, dot.outputs["Value"]), 9.0, clamp=True)
    # 陰: AO を 0.35..1 へ
    shade = math_node("ADD", 0.35, math_node("MULTIPLY", ao.outputs["AO"], 0.65))
    # ムラ: 細かい粒 ±6% と大きなくすみ ±8%
    mott = math_node("ADD", math_node("ADD", 0.86, math_node("MULTIPLY", noise.outputs["Fac"], 0.12)),
                     math_node("MULTIPLY", big.outputs["Fac"], 0.16))
    lum = math_node("MULTIPLY", shade, mott)
    wear = {"steel": 0.55, "steel_dark": 0.35, "graphite": 0.18, "glove": 0.05, "bore": 0.0, "marking": 0.15}[name]
    rgb = N("ShaderNodeCombineColor")
    sep_mix = []
    for i, ch in enumerate(("Red", "Green", "Blue")):
        base = math_node("MULTIPLY", lum, col[i])
        # 擦れた角は地の色から明るい鋼へ寄る（陰の中では弱く）
        lift = math_node("MULTIPLY", math_node("MULTIPLY", edge, wear), math_node("MULTIPLY", shade, 0.55 + 0.1 * i / 2))
        L(math_node("ADD", base, lift), rgb.inputs[ch])
    L(rgb.outputs["Color"], em.inputs["Color"])
    t = N("ShaderNodeTexImage")
    t.image = img
    for n in nt.nodes:
        n.select = False
    t.select = True
    nt.nodes.active = t


def unwrap(o, margin=0.004):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    if not o.data.uv_layers:
        o.data.uv_layers.new(name="UVMap")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(50), island_margin=margin, area_weight=0.0, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(margin=margin, rotate=True)
    bpy.ops.object.mode_set(mode="OBJECT")


def to_srgb(lin):
    lin = np.clip(lin, 0, 1)
    return np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1 / 2.4) - 0.055)


def bake_atlas(o, size, name, extra_occluders=(), surfaces=False):
    """o（glow 以外の材質）を 1 枚の絵へベイク、材質を body（絵）と glow（光る色）にまとめる（surfaces なら body を色分けごとに分ける）。"""
    t0 = time.time()
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24
    sc.render.bake.margin = max(4, size // 128)
    sc.render.bake.use_clear = True
    if sc.world is None:
        sc.world = bpy.data.worlds.new("w")
    img = bpy.data.images.new(name + "_bake", size, size, alpha=True, float_buffer=True)
    img.colorspace_settings.name = "Linear Rec.709"
    mats = [s.material for s in o.material_slots]
    for m in mats:
        if m.name.split(".")[0] != "glow":
            _bake_tree(m, img)
        else:
            m.use_nodes = True
            nt = m.node_tree
            for n in nt.nodes:
                n.select = False
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.bake(type="EMIT")
    a = np.empty(size * size * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    a = a.reshape(size, size, 4)
    hit = a[..., 3:] > 0.5
    rgb = a[..., :3]
    fill = rgb[hit[..., 0]].mean(axis=0)
    rgb = np.where(hit, rgb, fill)
    px = np.concatenate([to_srgb(rgb), np.ones((size, size, 1), dtype=np.float32)], axis=-1)
    tex = bpy.data.images.new(name + "_c", size, size, alpha=False)
    tex.colorspace_settings.name = "sRGB"
    tex.pixels.foreach_set(px.astype(np.float32).ravel())
    tex.file_format = "PNG"
    tex.pack()
    bpy.data.images.remove(img)

    def body_material(suffix, metallic, roughness):
        body = bpy.data.materials.new(name + "_" + suffix)
        body.use_nodes = True
        nt = body.node_tree
        nt.nodes.clear()
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = tex
        nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Metallic"].default_value = metallic
        bsdf.inputs["Roughness"].default_value = roughness
        return body

    glow = bpy.data.materials.new(name + "_glow")
    glow.use_nodes = True
    nt = glow.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*(c * 0.25 for c in GLOW_COLOR), 1.0)
    bsdf.inputs["Emission Color"].default_value = (*GLOW_COLOR, 1.0)
    bsdf.inputs["Emission Strength"].default_value = GLOW_STRENGTH
    bsdf.inputs["Roughness"].default_value = 0.3

    # 面の新しい材質: surfaces なら形を組んだ時の色分け（steel・glove…）ごとに、同じ絵を読む材質を 1 つずつ（名前 <name>_<色分け>）。
    # ゲームは材質の名前の末尾で金属っぽさと粗さを Doc から付ける。surfaces でなければ body 1 つ。
    classes = [m.name.split(".")[0] for m in mats]
    if surfaces:
        order = [c for i, c in enumerate(classes) if c != "glow" and c not in classes[:i]]
        bodies = [body_material(c, PALETTE[c][1], PALETTE[c][2]) for c in order]
        slot_of = {c: j for j, c in enumerate(order)}
    else:
        bodies = [body_material("body", 0.2, 0.55)]
        slot_of = {c: 0 for c in classes if c != "glow"}
    new_mats = bodies + ([glow] if "glow" in classes else [])
    remap = [len(bodies) if c == "glow" else slot_of[c] for c in classes]
    me = o.data
    # WhyNot: materials.clear() で付け替えない — 面の材質の番号が全部 0 へ戻り、光る面が消える。
    while len(me.materials) < len(new_mats):
        me.materials.append(new_mats[0])
    for p in me.polygons:
        p.material_index = remap[p.material_index]
    for j, m in enumerate(new_mats):
        me.materials[j] = m
    while len(me.materials) > len(new_mats):
        me.materials.pop(index=len(me.materials) - 1)
    print("bake %s %dpx %.1fs" % (name, size, time.time() - t0))
    return tex


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
    px = np.concatenate([to_srgb(rgb), np.ones((size, size, 1), dtype=np.float32)], axis=-1)
    tex = bpy.data.images.new(name, size, size, alpha=False)
    tex.colorspace_settings.name = "sRGB"
    tex.pixels.foreach_set(px.astype(np.float32).ravel())
    tex.file_format = "PNG"
    tex.pack()
    bpy.data.images.remove(img)
    return tex


def bake_one_material(o, size, name):
    """鋼の部品は _bake_tree の色の作り（AO・角の擦れ）、glow は emissive の絵へ。材質を 1 つ（色の絵と emissive の絵）にまとめる。"""
    t0 = time.time()
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24
    sc.render.bake.margin = max(4, size // 128)
    sc.render.bake.use_clear = True
    if sc.world is None:
        sc.world = bpy.data.worlds.new("w")
    unwrap(o, margin=0.008)
    is_glow = lambda m: m.name.split(".")[0] == "glow"

    def color(m, img):
        if is_glow(m):
            _flat_tree(m, img, tuple(c * 0.3 for c in GLOW_COLOR))
        else:
            _bake_tree(m, img)

    col = _bake_pass(o, size, name + "_color", color, True)
    emit = _bake_pass(o, size, name + "_emit", lambda m, img: _flat_tree(m, img, GLOW_COLOR if is_glow(m) else (0, 0, 0)), False)
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
    bsdf.inputs["Emission Strength"].default_value = GLOW_STRENGTH
    bsdf.inputs["Metallic"].default_value = 0.4
    bsdf.inputs["Roughness"].default_value = 0.45
    me = o.data
    for p in me.polygons:
        p.material_index = 0
    me.materials.clear()
    me.materials.append(m)
    print("bake %s %dpx %.1fs" % (name, size, time.time() - t0))


def export_glb(path, animations):
    kw = dict(filepath=path, export_format="GLB", export_yup=True, export_apply=False,
              export_texcoords=True, export_normals=True, export_tangents=False,
              export_materials="EXPORT", export_image_format="AUTO", export_animations=animations)
    if animations:
        kw.update(export_animation_mode="NLA_TRACKS", export_skins=True, export_force_sampling=True,
                  export_optimize_animation_size=False)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(**kw)
    print("exported:", path, os.path.getsize(path))
