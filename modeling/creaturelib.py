# クリーチャー（melee・ranged）の共通の道具: 輪を重ねた有機的な形・重み・1 つの材質へのベイク（色の絵と emissive の絵）・地面との当たりの確かめ。
# 骨・クリップ・書き出しは vmlib を使う。寸法はメートル・Blender の Z が上・正面は -Y・.L は +X。
import bpy, bmesh, math, time
import numpy as np
from mathutils import Vector, Matrix
import vmlib as V

# 色は linear。sRGB にすると flesh ≈ (0.39, 0.27, 0.27)・dark ≈ (0.17, 0.10, 0.19)。
TONES = {
    "flesh": {"front": (0.150, 0.072, 0.066), "back": (0.032, 0.015, 0.040), "crack": 1.0, "rough": 0.42},
    "hide":  {"front": (0.080, 0.045, 0.058), "back": (0.020, 0.011, 0.026), "crack": 0.6, "rough": 0.55},
    "claw":  {"front": (0.150, 0.110, 0.078), "back": (0.040, 0.028, 0.026), "crack": 0.0, "rough": 0.35},
    "glow":  {"front": (0.500, 0.150, 0.030), "back": (0.300, 0.070, 0.015), "crack": 0.0, "rough": 0.3},
}
GLOW = (1.0, 0.30, 0.045)          # linear の橙。sRGB で ≈ (1.0, 0.58, 0.24)
GLOW_DEEP = (0.85, 0.07, 0.01)     # 筋の芯から外れた所の赤
EMISSION_STRENGTH = 3.0
_mats = {}


def mat(name):
    if name in _mats and _mats[name].name in bpy.data.materials:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*TONES[name]["front"], 1.0)
    _mats[name] = m
    return m


def reset():
    V.reset()
    _mats.clear()


def _tag(o, glow_of):
    """頂点ごとの「筋が光る度合い」（0..1）を属性 glow に入れる。ベイクで読む。"""
    a = o.data.attributes.new("glow", "FLOAT", "POINT")
    for v in o.data.vertices:
        a.data[v.index].value = glow_of(v.co)
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def sweep(rings, material, sides=8, front=(0, -1, 0), roll=0.0):
    """輪を並べた柱。rings = [(中心, 横の半径, 奥の半径, {骨: 重み}, 光る度合い)]。
    輪の面は前後の中心を結ぶ向きに垂直。front は輪の「奥の半径」の向きの目安（腕・脚・胴は -Y、前へ伸びる頭は +Z）。
    両端はふさぐ。輪の頂点はその輪の重みと光る度合いを持つ（重みのある輪の物は assemble へ重み None で渡す）。"""
    cs = [Vector(r[0]) for r in rings]
    bm = bmesh.new()
    rows = []
    for i, (c, rx, ry, _, _) in enumerate(rings):
        t = (cs[min(i + 1, len(cs) - 1)] - cs[max(i - 1, 0)]).normalized()
        f = Vector(front) - t * Vector(front).dot(t)
        f.normalize()
        s = t.cross(f)
        row = []
        for k in range(sides):
            a = 2 * math.pi * (k + 0.5) / sides + math.radians(roll)
            row.append(bm.verts.new(cs[i] + s * (rx * math.cos(a)) + f * (ry * math.sin(a))))
        rows.append(row)
    for j in range(len(rows) - 1):
        for k in range(sides):
            n = (k + 1) % sides
            bm.faces.new([rows[j][k], rows[j][n], rows[j + 1][n], rows[j + 1][k]])
    bm.faces.new(rows[0])
    bm.faces.new(rows[-1])
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    o = V.emit(bm, mat(material), None, "sweep")
    # 頂点の並びは輪の順（remove_doubles は輪の半径が 0 でない限り何も merge しない）
    ring_of = lambda i: min(i // sides, len(rings) - 1)
    a = o.data.attributes.new("glow", "FLOAT", "POINT")
    groups = {}
    for v in o.data.vertices:
        r = rings[ring_of(v.index)]
        a.data[v.index].value = r[4]
        for bone, w in r[3].items():
            if bone not in groups:
                groups[bone] = o.vertex_groups.new(name=bone)
            groups[bone].add([v.index], w, "REPLACE")
    for p in o.data.polygons:
        p.use_smooth = True
    return o


def blob(c, r, material, seg=8, rings=5, glow=0.0, m3=None):
    """低い多角形の楕円体。r = (x, y, z) の半径。m3 で向きを変える。"""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=rings, radius=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * r[0], v.co.y * r[1], v.co.z * r[2]))
        if m3 is not None:
            v.co = m3 @ v.co
        v.co += Vector(c)
    o = V.emit(bm, mat(material), None, "blob")
    return _tag(o, lambda co: glow)


def spike(base, tip, r0, material, sides=5, bend=(0, 0, 0), steps=3, glow=0.0):
    """根元 base から先 tip へ細る角（鉤爪・背の棘）。bend は真ん中を押し出す向き（曲がった爪）。"""
    base, tip, bend = Vector(base), Vector(tip), Vector(bend)
    rings = []
    for k in range(steps + 1):
        t = k / steps
        c = base.lerp(tip, t) + bend * (4 * t * (1 - t))
        r = r0 * (1 - t) ** 0.8 + 0.002
        rings.append((c, r, r * 0.8, {}, glow))
    return sweep(rings, material, sides, front=(bend if bend.length > 1e-6 else Vector((0, -1, 0.3))))


def mix(a, b, t):
    if t <= 0:
        return {a: 1.0}
    if t >= 1:
        return {b: 1.0}
    return {a: 1 - t, b: t}


# ── ベイク: 色の絵（地の色 × 陰 × 皺 ＋ 筋のまわりの赤み）と emissive の絵（筋・目・袋） ──
AO_DISTANCE = 0.12


def _tree(m, img, pass_name):
    name = m.name.split(".")[0]
    tone = TONES[name]
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    N, L = nt.nodes.new, nt.links.new
    out = N("ShaderNodeOutputMaterial")
    em = N("ShaderNodeEmission")
    L(em.outputs["Emission"], out.inputs["Surface"])
    tc = N("ShaderNodeTexCoord")
    geo = N("ShaderNodeNewGeometry")
    attr = N("ShaderNodeAttribute")
    attr.attribute_name = "glow"

    def mnode(op, a=None, b=None, clamp=False):
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

    def noise(scale, detail=4.0):
        n = N("ShaderNodeTexNoise")
        n.inputs["Scale"].default_value = scale
        n.inputs["Detail"].default_value = detail
        L(tc.outputs["Object"], n.inputs["Vector"])
        return n.outputs["Fac"]

    # 筋: うねる模様の等高線（|ノイズ − 0.5| が小さい所）を細い線にし、大きなノイズで所々だけ残す × 頂点の glow
    vein_n = N("ShaderNodeTexNoise")
    vein_n.inputs["Scale"].default_value = 3.4
    vein_n.inputs["Detail"].default_value = 2.0
    vein_n.inputs["Distortion"].default_value = 0.6
    L(tc.outputs["Object"], vein_n.inputs["Vector"])
    line = mnode("SUBTRACT", 1.0, mnode("MULTIPLY", mnode("ABSOLUTE", mnode("SUBTRACT", vein_n.outputs["Fac"], 0.5)), 32.0, clamp=True))
    patch = mnode("MULTIPLY", mnode("SUBTRACT", noise(1.4, 2.0), 0.40), 5.0, clamp=True)
    crack = mnode("MULTIPLY", mnode("MULTIPLY", line, line), patch)
    crack = mnode("MULTIPLY", crack, mnode("MULTIPLY", attr.outputs["Fac"], tone["crack"]))
    rgb = N("ShaderNodeCombineColor")
    if pass_name == "emit":
        if name == "glow":
            # 袋と目は芯だけ橙・まわりは赤へ落とす（一面の黄色にすると、ブルームで白く飛ぶ）
            hot = mnode("MULTIPLY", mnode("SUBTRACT", noise(6.0), 0.3), 1.6, clamp=True)
            for i, ch in enumerate(("Red", "Green", "Blue")):
                c = mnode("ADD", mnode("MULTIPLY", hot, GLOW[i]), mnode("MULTIPLY", mnode("SUBTRACT", 1.0, hot), GLOW_DEEP[i]))
                L(mnode("MULTIPLY", c, 0.85), rgb.inputs[ch])
        else:
            core = mnode("POWER", crack, 3.0)
            for i, ch in enumerate(("Red", "Green", "Blue")):
                L(mnode("ADD", mnode("MULTIPLY", core, GLOW[i]), mnode("MULTIPLY", mnode("SUBTRACT", crack, core), GLOW_DEEP[i] * 0.8)), rgb.inputs[ch])
    else:
        ao = N("ShaderNodeAmbientOcclusion")
        ao.samples = 32
        ao.inputs["Distance"].default_value = AO_DISTANCE
        sep = N("ShaderNodeSeparateXYZ")
        L(geo.outputs["Normal"], sep.inputs["Vector"])
        # 腹（-Y）と下は肉の色、背と上は黒ずんだ紫。大きなくすみで境をぼかす
        front = mnode("ADD", mnode("MULTIPLY", sep.outputs["Y"], -0.55), 0.45)
        front = mnode("ADD", front, mnode("MULTIPLY", sep.outputs["Z"], -0.25))
        front = mnode("ADD", front, mnode("MULTIPLY", mnode("SUBTRACT", noise(2.5), 0.5), 0.7), clamp=True)
        shade = mnode("ADD", 0.25, mnode("MULTIPLY", ao.outputs["AO"], 0.75))
        wr = N("ShaderNodeTexVoronoi")
        wr.feature = "DISTANCE_TO_EDGE"
        wr.inputs["Scale"].default_value = 26.0
        L(tc.outputs["Object"], wr.inputs["Vector"])
        wrinkle = mnode("ADD", 0.72, mnode("MULTIPLY", wr.outputs["Distance"], 3.0, clamp=True))
        wrinkle = mnode("MINIMUM", wrinkle, 1.0)
        mott = mnode("ADD", 0.85, mnode("MULTIPLY", noise(18.0), 0.3))
        lum = mnode("MULTIPLY", mnode("MULTIPLY", shade, wrinkle), mott)
        for i, ch in enumerate(("Red", "Green", "Blue")):
            base = mnode("ADD", mnode("MULTIPLY", front, tone["front"][i] - tone["back"][i]), tone["back"][i])
            # 光る筋のまわりは皮が薄く赤い（灯りが無くても形が暖かく読める）
            warm = mnode("MULTIPLY", crack, GLOW_DEEP[i] * 0.35)
            L(mnode("ADD", mnode("MULTIPLY", base, lum), warm), rgb.inputs[ch])
    L(rgb.outputs["Color"], em.inputs["Color"])
    t = N("ShaderNodeTexImage")
    t.image = img
    for n in nt.nodes:
        n.select = False
    t.select = True
    nt.nodes.active = t


def _bake(o, size, name, pass_name, mats):
    img = bpy.data.images.new(name + "_" + pass_name + "_raw", size, size, alpha=True, float_buffer=True)
    img.colorspace_settings.name = "Linear Rec.709"
    for m in mats:
        _tree(m, img, pass_name)
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.bake(type="EMIT")
    a = np.empty(size * size * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    a = a.reshape(size, size, 4)
    hit = a[..., 3:] > 0.5
    rgb = a[..., :3]
    fill = rgb[hit[..., 0]].mean(axis=0) if pass_name == "color" else np.zeros(3, dtype=np.float32)
    rgb = np.where(hit, rgb, fill)
    px = np.concatenate([V.to_srgb(rgb), np.ones((size, size, 1), dtype=np.float32)], axis=-1)
    tex = bpy.data.images.new(name + "_" + pass_name, size, size, alpha=False)
    tex.colorspace_settings.name = "sRGB"
    tex.pixels.foreach_set(px.astype(np.float32).ravel())
    tex.file_format = "PNG"
    tex.pack()
    bpy.data.images.remove(img)
    return tex


def bake_single_material(o, size, name):
    """形を組む間の材質（flesh・hide・claw・glow）を、色の絵と emissive の絵を持つ 1 つの材質へまとめる。"""
    t0 = time.time()
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 32
    sc.render.bake.margin = 6
    sc.render.bake.use_clear = True
    if sc.world is None:
        sc.world = bpy.data.worlds.new("w")
    V.unwrap(o, margin=0.006)
    mats = [s.material for s in o.material_slots]
    color = _bake(o, size, name, "color", mats)
    emit = _bake(o, size, name, "emit", mats)

    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    tc = nt.nodes.new("ShaderNodeTexImage")
    tc.image = color
    nt.links.new(tc.outputs["Color"], bsdf.inputs["Base Color"])
    te = nt.nodes.new("ShaderNodeTexImage")
    te.image = emit
    nt.links.new(te.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = EMISSION_STRENGTH
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 0.45
    me = o.data
    for p in me.polygons:
        p.material_index = 0
    me.materials.clear()
    me.materials.append(m)
    # WhyNot: 属性 glow を残さない — 書き出しが頂点の色や _GLOW として載せると、engine が色を掛ける・知らない欄として捨てる。
    if "glow" in me.attributes:
        me.attributes.remove(me.attributes["glow"])
    print("bake %s %dpx %.1fs" % (name, size, time.time() - t0))
    return color, emit


def assemble(rig, parts, name, scale=1.0):
    """parts = [(物, 重み)] を重みつきで 1 つの形へまとめ、骨へつなぐ。重みが None の物は sweep が輪ごとに付けた重みのまま。
    scale は足元の原点のまわりで形と骨をまとめて拡げる（背丈をそろえる）。返す: (形, armature)。"""
    S = Matrix.Scale(scale, 4)
    V.transform([o for o, _ in parts], S)
    rig.bones = [(n, h * scale, t * scale, p) for n, h, t, p in rig.bones]
    for o, w in parts:
        if w is not None:
            rig.add(o, w)
    rig.apply_weights()
    body = V.join([o for o, _ in parts], name)
    arm = rig.build_armature()
    body.parent = arm
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = arm
    return body, arm


def ground_report(arm, body, clips, picks=None):
    """クリップの何コマかで、形の一番低い所（地面へめり込まないか）と高さを出す。"""
    deps = bpy.context.evaluated_depsgraph_get()
    for nm, frames in clips.items():
        arm.animation_data.action = bpy.data.actions[nm]
        act = arm.animation_data.action
        if act.slots:
            arm.animation_data.action_slot = act.slots[0]
        for t in arm.animation_data.nla_tracks:
            t.mute = True
        last = frames[-1][0]
        row = []
        for f in (picks or {}).get(nm, sorted({0, last // 4, last // 2, 3 * last // 4, last})):
            bpy.context.scene.frame_set(f)
            deps.update()
            e = body.evaluated_get(deps)
            zs = np.array([(e.matrix_world @ v.co).z for v in e.data.vertices])
            ys = np.array([(e.matrix_world @ v.co).y for v in e.data.vertices])
            row.append("f%d z[%.2f..%.2f] y[%.2f..%.2f]" % (f, zs.min(), zs.max(), ys.min(), ys.max()))
        print("ground", nm, " ".join(row))
    arm.animation_data.action = None
    for t in arm.animation_data.nla_tracks:
        t.mute = False


def lowest_z(arm, body, spec):
    """姿勢 spec で形の一番低い所の高さ。"""
    if arm.animation_data:
        arm.animation_data.action = None
    V.set_pose(arm, spec)
    deps = bpy.context.evaluated_depsgraph_get()
    deps.update()
    e = body.evaluated_get(deps)
    z = min((e.matrix_world @ v.co).z for v in e.data.vertices)
    V.set_pose(arm, {})
    return z


def grounded(arm, body, frames, root="hips"):
    """各キーの姿勢の root を上下に動かし、形の一番低い所を地面（z = 0）にそろえる（足が浮く・沈むのを消す）。"""
    out = []
    for f, spec in frames:
        dz = lowest_z(arm, body, spec)
        s = dict(spec)
        r = dict(s.get(root, {}))
        t = r.get("t", (0, 0, 0))
        r["t"] = (t[0], t[1], t[2] - dz)
        s[root] = r
        out.append((f, s))
    return out


def add_spec(base, spec):
    """base の回しと移動に spec を足す（構えの上に動きを重ねる。r は角度の足し算なので小さな角どうしに使う）。"""
    out = {k: dict(v) for k, v in base.items()}
    for name, s in spec.items():
        o = out.setdefault(name, {})
        for k in ("r", "t"):
            if k in s:
                o[k] = tuple(a + b for a, b in zip(o.get(k, (0, 0, 0)), s[k]))
        if "s" in s:
            o["s"] = s["s"]
    return out
