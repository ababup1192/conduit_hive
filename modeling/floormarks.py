# 床の標示（工場や地下駐車場の床のペイント）と水たまりを、区画の床の 1 cm 上に重ねる薄い面として作る（stage.py が呼ぶ）。
#   標示: 通路の真ん中の黄色い誘導の線・進む向きの白い矢印・部屋の入口の黄色と黒の警告の縞・部屋の区画の文字と番号・横断歩道のような白い帯。
#   水たまり: 色の灯りの前（fixtures）・配管の下（壁沿い）・通路の角に、形のばらついた暗い面（ゲームで粗さを下げて灯りを映す）。
# 絵は 1 枚（atlas）: 標示は塗った所が α 1・擦れた所が α 0（ゲームで α 0.5 で抜く）、水たまりは縁へなだらかに薄くなる α（ゲームで半透明に重ねる）。
# lightmap はベイクの後で足す: 面はベイクに入れず（床に影を落とさない）、2 本目の uv は下の床の面の uv を同じ点で引く（床と同じ明るさになる）。
# 1 つの面は 1 マスの中に収める（マスごとに床の lightmap の島が違うので、マスをまたぐと uv が飛ぶ）。
import bpy, bmesh, math
import numpy as np
from mathutils import Vector

ATLAS = 1024
DECAL_Y = 0.012   # 標示の高さ（m）。遠くでも床とちらつかない高さ
PUDDLE_Y = 0.006  # 水たまりの高さ（標示より下）

# 名前 → 絵の上の矩形（px・左上が原点）
REGIONS = {
    "hazard": (0, 0, 512, 128),
    "line": (0, 128, 512, 192),
    "bar": (0, 192, 512, 256),
    "arrow": (512, 0, 768, 256),
    "puddle0": (0, 768, 256, 1024),
    "puddle1": (256, 768, 512, 1024),
    "puddle2": (512, 768, 768, 1024),
    "puddle3": (768, 768, 1024, 1024),
}
GLYPHS = "ABCDEFGH0123456789"
FONT = {  # 5 × 7 の字（上の行から・1 = 塗る）
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01111", "10000", "10000", "10011", "10001", "10001", "01111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "0": ["01110", "10011", "10101", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00110", "01000", "10000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
}
for i, g in enumerate(GLYPHS):
    gx, gy = (i % 8) * 128, 256 + (i // 8) * 128
    REGIONS["glyph_" + g] = (gx, gy, gx + 128, gy + 128)


def _noise(h, w, cell, rng):
    gy, gx = h // cell + 2, w // cell + 2
    g = rng.random((gy, gx))
    ys = np.arange(h) / cell
    xs = np.arange(w) / cell
    y0 = np.floor(ys).astype(int); fy = (ys - y0)[:, None]
    x0 = np.floor(xs).astype(int); fx = (xs - x0)[None, :]
    fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
    a = g[y0][:, x0]; b = g[y0][:, x0 + 1]; c = g[y0 + 1][:, x0]; d = g[y0 + 1][:, x0 + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def make_atlas(path):
    """標示と水たまりの絵（RGBA・sRGB の値）を書いて読み直す。"""
    rng = np.random.default_rng(23)
    img = np.zeros((ATLAS, ATLAS, 4))
    yellow = np.array([0.80, 0.62, 0.10]); black = np.array([0.05, 0.05, 0.055]); white = np.array([0.80, 0.80, 0.76])
    wear_big = _noise(ATLAS, ATLAS, 48, rng)
    wear_fine = _noise(ATLAS, ATLAS, 6, rng)
    grime = _noise(ATLAS, ATLAS, 24, rng)
    worn = (0.62 * wear_big + 0.38 * wear_fine) < 0.34          # 擦れて地が見える所
    dirt = (0.75 + 0.25 * grime)[..., None]

    def paint(region, mask, color):
        x0, y0, x1, y1 = REGIONS[region]
        sub = mask & ~worn[y0:y1, x0:x1]
        col = img[y0:y1, x0:x1]
        col[sub, :3] = (color * dirt[y0:y1, x0:x1])[sub]
        col[sub, 3] = 1.0

    # 警告の縞: 斜めの黄色と黒（全面を塗る・黒も塗料）
    x0, y0, x1, y1 = REGIONS["hazard"]
    yy, xx = np.mgrid[0:y1 - y0, 0:x1 - x0]
    band = np.mod(xx + yy, 96) < 48
    full = np.ones_like(band)
    paint("hazard", full & band, yellow)
    paint("hazard", full & ~band, black)
    # 誘導の線・帯: 全面
    for name, col in (("line", yellow), ("bar", white)):
        x0, y0, x1, y1 = REGIONS[name]
        paint(name, np.ones((y1 - y0, x1 - x0), bool), col)
    # 矢印（上 = 進む向き）
    x0, y0, x1, y1 = REGIONS["arrow"]
    s = x1 - x0
    yy, xx = np.mgrid[0:s, 0:s]
    u = (xx + 0.5) / s - 0.5; v = (yy + 0.5) / s
    head = (v < 0.45) & (np.abs(u) < (0.45 - v) * 1.0 + 0.0) & (v > 0.04)
    shaft = (v >= 0.42) & (v < 0.96) & (np.abs(u) < 0.12)
    paint("arrow", head | shaft, white)
    # 字
    for g in GLYPHS:
        x0, y0, x1, y1 = REGIONS["glyph_" + g]
        m = np.zeros((128, 128), bool)
        for r, rowbits in enumerate(FONT[g]):
            for c, bit in enumerate(rowbits):
                if bit == "1":
                    m[8 + r * 16: 8 + (r + 1) * 16, 24 + c * 16: 24 + (c + 1) * 16] = True
        paint("glyph_" + g, m, white)
    # 水たまり: 縁がちぎれた丸。色は暗い水・α は縁へなだらかに
    for k in range(4):
        x0, y0, x1, y1 = REGIONS["puddle%d" % k]
        s = x1 - x0
        yy, xx = np.mgrid[0:s, 0:s]
        u = (xx + 0.5) / s * 2 - 1; v = (yy + 0.5) / s * 2 - 1
        n = _noise(s, s, 40, rng) * 0.6 + _noise(s, s, 14, rng) * 0.4
        stretch = 1.0 + 0.5 * rng.random()
        d = np.sqrt((u * stretch) ** 2 + v ** 2) - 0.35 * (n - 0.5)
        a = np.clip((0.82 - d) / 0.22, 0, 1)
        a = a * a * (3 - 2 * a)
        img[y0:y1, x0:x1, :3] = np.array([0.035, 0.04, 0.045]) * (0.8 + 0.4 * n[..., None])
        img[y0:y1, x0:x1, 3] = 0.78 * a
    rgba = img[::-1].astype(np.float32)
    im = bpy.data.images.new("T_floor_marks", ATLAS, ATLAS, alpha=True)
    im.pixels.foreach_set(rgba.ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)
    return bpy.data.images.load(path)


def make_materials(atlas):
    """M_decal（塗料・α で抜く）と M_puddle（水・半透明）。どちらも同じ絵の色と α を読む。"""
    out = {}
    for key, rough in (("decal", 0.55), ("puddle", 0.05)):
        m = bpy.data.materials.new("M_" + key)
        nt = m.node_tree
        p = nt.nodes.get("Principled BSDF")
        uv = nt.nodes.new("ShaderNodeUVMap"); uv.uv_map = "UVMap"
        tx = nt.nodes.new("ShaderNodeTexImage"); tx.image = atlas
        nt.links.new(uv.outputs[0], tx.inputs[0])
        nt.links.new(tx.outputs["Color"], p.inputs["Base Color"])
        nt.links.new(tx.outputs["Alpha"], p.inputs["Alpha"])
        p.inputs["Roughness"].default_value = rough
        p.inputs["Metallic"].default_value = 0.0
        out[key] = m
    return out


def region_uvs(name):
    """矩形の 4 隅の uv（Blender の uv・下が 0）: 左下（矢印の尻・左）・右下・右上（矢印の先）・左上。"""
    x0, y0, x1, y1 = REGIONS[name]
    inset = 1.5
    u0, u1 = (x0 + inset) / ATLAS, (x1 - inset) / ATLAS
    vb, vt = 1 - (y1 - inset) / ATLAS, 1 - (y0 + inset) / ATLAS
    return [(u0, vb), (u1, vb), (u1, vt), (u0, vt)]


def quad(center, along, length, width, y):
    """engine の座標の床の上の矩形（along = 長さの向き（x・z）。左下・右下・右上・左上 = 尻の左・尻の右・先の右・先の左）。"""
    ax, az = along
    L = math.hypot(ax, az); ax, az = ax / L, az / L
    sx, sz = az, -ax   # 右（上から見て時計回り）
    cx, cz = center
    hl, hw = length / 2, width / 2
    P = lambda a, s: (cx + ax * a + sx * s, y, cz + az * a + sz * s)
    return [P(-hl, -hw), P(-hl, hw), P(hl, hw), P(hl, -hw)]


def plan(doc, zone, zone_index, spots, E, corner_fn, center_fn, rng):
    """区画の標示と水たまりの並び: [(マス, 材質, 4 隅の点, 4 隅の uv)]。spots = 色の灯りの前の床（fixtures.puddle_spots。必ず水たまりを置く）。"""
    cs = doc["cs"]
    out = []
    cells = zone["cells"]
    cellset = set(cells)
    room = zone["kind"] == "room"

    def add(cell, mat, pts, region):
        out.append((cell, mat, pts, region_uvs(region)))

    for cell, x, z in spots:
        a = rng.random() * 6.28
        size = cs * (0.42 + 0.15 * rng.random())
        add(cell, "puddle", quad((x, z), (math.cos(a), math.sin(a)), size, size * (0.65 + 0.25 * rng.random()), PUDDLE_Y), "puddle%d" % rng.integers(4))

    if not room:
        straight = []
        for (c, r) in cells:
            ns = (c, r - 1) in cellset or (c, r + 1) in cellset
            ew = (c - 1, r) in cellset or (c + 1, r) in cellset
            cx, cz = center_fn(doc, c, r)
            if ns and ew:
                # 角: 水たまり
                size = cs * (0.4 + 0.15 * rng.random())
                add((c, r), "puddle", quad((cx + (rng.random() - 0.5), cz + (rng.random() - 0.5)), (math.cos(rng.random() * 6.28), math.sin(rng.random() * 6.28)), size, size * 0.8, PUDDLE_Y), "puddle%d" % rng.integers(4))
                continue
            along = (0.0, 1.0) if ns else (1.0, 0.0)
            straight.append(((c, r), along))
            add((c, r), "decal", quad((cx, cz), along, cs, 0.12, DECAL_Y), "line")
        for i, ((c, r), along) in enumerate(straight):
            cx, cz = center_fn(doc, c, r)
            if i % 3 == 1:
                sx, sz = along[1], -along[0]
                add((c, r), "decal", quad((cx + sx * 0.75, cz + sz * 0.75), along, 1.3, 0.75, DECAL_Y), "arrow")
            if i % 4 == 2:
                # 配管の下（壁沿い）の水たまり
                side = 1.0 if rng.random() < 0.5 else -1.0
                sx, sz = along[1] * side, -along[0] * side
                add((c, r), "puddle", quad((cx + sx * 1.0, cz + sz * 1.0), along, cs * (0.45 + 0.2 * rng.random()), 1.3, PUDDLE_Y), "puddle%d" % rng.integers(4))
        return out

    # 部屋: 入口の警告の縞（向こうが通路の境目の、部屋の側のマスに）
    for p, q, n, info in E["open"]:
        if info["other"] in cellset or not str(info["other"]).islower():
            continue
        c, r = info["cell"]
        mx, mz = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
        cx, cz = mx + n[0] * 0.45, mz + n[1] * 0.45
        along = (q[0] - p[0], q[1] - p[1])
        add((c, r), "decal", quad((cx, cz), along, cs - 0.7, 0.5, DECAL_Y), "hazard")
    # 区画の文字と番号（真ん中のマス）と、隣のマスに横断歩道のような帯
    cols = sorted(c for c, _ in cells); rows = sorted(r for _, r in cells)
    mid = (cols[len(cols) // 2], rows[len(rows) // 2])
    if mid in cellset:
        cx, cz = center_fn(doc, *mid)
        add(mid, "decal", quad((cx - 0.75, cz), (0.0, 1.0), 1.5, 1.5, DECAL_Y), "glyph_" + zone["id"])
        num = "%02d" % (zone_index + 1)
        for k, ch in enumerate(num):
            add(mid, "decal", quad((cx + 0.55 + k * 0.62, cz - 0.2), (0.0, 1.0), 0.7, 0.7, DECAL_Y), "glyph_" + ch)
    side = (mid[0], mid[1] + 1)
    if side in cellset:
        cx, cz = center_fn(doc, *side)
        for k in range(5):
            add(side, "decal", quad((cx - 1.4 + k * 0.7, cz), (0.0, 1.0), cs - 0.8, 0.36, DECAL_Y), "bar")
    # 水たまり: 壁際のマス（配管の下）に何か所か・非常灯の区画は多め
    edge = sorted({info["cell"] for _, _, _, info in E["wall"]})
    count = 2
    for k in range(min(count, len(edge))):
        c, r = edge[int(rng.integers(len(edge)))]
        if (c, r) in (mid, side):
            continue
        cx, cz = center_fn(doc, c, r)
        size = cs * (0.45 + 0.2 * rng.random())
        a = rng.random() * 6.28
        add((c, r), "puddle", quad((cx + (rng.random() - 0.5) * 0.8, cz + (rng.random() - 0.5) * 0.8), (math.cos(a), math.sin(a)), size, size * (0.6 + 0.3 * rng.random()), PUDDLE_Y), "puddle%d" % rng.integers(4))
    return out


def append(ob, decals, mats, doc, corner_fn, B):
    """ベイクの済んだ区画の物 ob に標示と水たまりの面を足す。2 本目の uv（Lightmap）は下の床の面の uv を同じ点で引く。"""
    me = ob.data
    cs = doc["cs"]
    lm = me.uv_layers["Lightmap"]
    # 床の面（上向き・高さ 0）: マス → (点の x・z, lightmap の uv) の 3 点
    floors = {}
    for poly in me.polygons:
        if poly.normal.z < 0.99:
            continue
        vs = [me.vertices[i].co for i in poly.vertices]
        if any(abs(v.z) > 1e-3 for v in vs):
            continue
        cxz = sum((Vector((-v.x, -v.y)) for v in vs), Vector((0.0, 0.0))) / len(vs)
        col = int(math.floor(cxz.x / cs)); row = doc["rows"] - 1 - int(math.floor(cxz.y / cs))
        pts = [(-me.vertices[me.loops[li].vertex_index].co.x, -me.vertices[me.loops[li].vertex_index].co.y, tuple(lm.data[li].uv)) for li in poly.loop_indices]
        floors[(col, row)] = pts[:3]
    for key in ("decal", "puddle"):
        me.materials.append(mats[key])
    index = {"decal": len(me.materials) - 2, "puddle": len(me.materials) - 1}
    bm = bmesh.new()
    bm.from_mesh(me)
    uv0 = bm.loops.layers.uv["UVMap"]
    uv1 = bm.loops.layers.uv["Lightmap"]
    added = 0
    for cell, mat, pts, uvs in decals:
        f3 = floors.get(cell)
        if f3 is None:
            continue
        (xa, za, ua), (xb, zb, ub), (xc, zc, uc) = f3
        M = np.array([[xa, za, 1], [xb, zb, 1], [xc, zc, 1]])
        try:
            inv = np.linalg.inv(M)
        except np.linalg.LinAlgError:
            continue
        cu = inv @ np.array([ua[0], ub[0], uc[0]]); cv = inv @ np.array([ua[1], ub[1], uc[1]])
        x0, z0 = corner_fn(doc, *cell)
        clamp = lambda v, lo, hi: max(lo + 0.02, min(hi - 0.02, v))
        pts = [(clamp(p[0], x0, x0 + cs), p[1], clamp(p[2], z0, z0 + cs)) for p in pts]
        vs = [bm.verts.new(B(p)) for p in pts]
        try:
            f = bm.faces.new(vs)
        except ValueError:
            continue
        f.material_index = index[mat]
        f.smooth = False
        for loop, p, uv in zip(f.loops, pts, uvs):
            loop[uv0].uv = uv
            loop[uv1].uv = (float(cu @ np.array([p[0], p[2], 1.0])), float(cv @ np.array([p[0], p[2], 1.0])))
        f.normal_update()
        if f.normal.z < 0:
            f.normal_flip()
        added += 1
    bm.to_mesh(me)
    bm.free()
    return added
