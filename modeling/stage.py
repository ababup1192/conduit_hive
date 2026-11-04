# ステージの絵: assets/maze.stage.json のマス目から、区画（zone）ごとに 1 つのノード ZONE_<文字> の形を組み、
# lightmap を区画ごとにベイクして assets/models/stage.glb と assets/models/stage_lightmaps/*.png に書き出す。
#
#   cd modeling && devbox run -- blender -b --factory-startup --python stage.py -- [引数]
#     --zones A,a,H   その区画だけ組む（試し。書き出しの名前は stage_try.glb）
#     --samples N     ベイクの sample 数（既定 192）
#     --skip-bake     ベイクしない（形と UV だけ・lightmap の絵は書かない）
#     --no-preview    プレビューの PNG を描かない
#
# 座標は engine の Scene3d と同じ（X 東・Y 上・Z 北・床の上面 y = 0。src/Maze.flix と同じマスの置き方）で組み、
# Blender へは (x, y, z) → (−x, −z, y) で置く（glb を engine が読むと元の engine の座標に戻る。vmlib.py の頭）。
#
# 区画ごとの材質は 3 つ（= draw call 3）: M_hull（壁・床・天井・パイプ・留め具。trim sheet の絵 1 枚 + lightmap）・
# M_strip（シアンの光る筋）・M_lamp（天井の灯具）。lightmap は TEXCOORD_1。PNG = sRGB(0.25 × 線形)・ゲームでは intensity 4.0。
import bpy, bmesh, os, sys, json, math, time, random, argparse
import numpy as np
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stagehash

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
DOC_PATH = os.path.join(ROOT, "assets", "maze.stage.json")
LOOK_PATH = os.path.join(ROOT, "assets", "conduit_hive.look.json")
WALK_PATH = os.path.join(ROOT, "assets", "conduit_hive.walk.json")
OUT = os.path.join(ROOT, "assets", "models")
LM_DIR = os.path.join(OUT, "stage_lightmaps")
DEBUG = os.path.join(ROOT, "debug", "modeling")
TRIM_PATH = os.path.join(DEBUG, "stage_trim.png")

BEVEL = 0.3          # 足元と天井際の面取り（MazeMesh と同じ）
SEAM_LO, SEAM_HI = 1.1, 1.2
VENT = 0.5           # 天井際の換気のストリップ
RIB_DEPTH = 0.12
WALL_GAP = RIB_DEPTH + 0.04
LM_GAP_PX = 8        # lightmap の島の間（px）。engine の mip は 2^(レベル+1) ≦ 間 で 2 レベルまで
LM_PX_PER_M = 14.0
PNG_SCALE = 0.25     # PNG = sRGB(0.25 × 線形)。ゲームの intensity は 1 / PNG_SCALE
AMBIENT = (0.035, 0.040, 0.046)

TIERS = {"XL": 0.26, "L": 0.16, "M": 0.085, "S": 0.045}
SIDES = {"XL": 14, "L": 12, "M": 8, "S": 6}
PIPE_STRIP = {"XL": "pipe_steel", "L": "pipe_steel", "M": "pipe_paint", "S": "pipe_graphite"}


# ───────────────────────── Doc ─────────────────────────
def load_doc():
    raw = open(DOC_PATH, "rb").read()
    d = json.loads(raw.decode("utf-8"))
    # WhyNot: 形の崩れた Doc で組み始めない — ゲームは既定へ落として別の迷路を読むので、ベイクの後でハッシュが食い違う。
    stagehash.check_shape(d)
    rows = d["rows"]
    cols = max(len(r) for r in rows)
    grid = [r.ljust(cols, "#") for r in rows]
    specs = {z["id"]: z for z in d.get("zones", [])}
    cells = {}
    for row, line in enumerate(grid):
        for col, ch in enumerate(line):
            if ch not in ("#", " "):
                cells.setdefault(ch, []).append((col, row))
    zones = {}
    for zid, cs in cells.items():
        s = specs.get(zid, {})
        zones[zid] = {"id": zid, "name": s.get("name", ""), "kind": s.get("kind", "corridor"),
                      "height": float(s.get("height", d.get("wallHeight", 4.0))), "cells": cs}
    return {"json": d, "cs": float(d.get("cellSize", 4.0)), "rows": len(grid), "cols": cols, "grid": grid,
            "zones": zones, "final": d.get("finalZone", "H"), "marks": d.get("marks", [])}


def char_at(doc, col, row):
    if col < 0 or row < 0 or col >= doc["cols"] or row >= doc["rows"]:
        return "#"
    return doc["grid"][row][col]


def is_floor(ch):
    return ch not in ("#", " ")


def height_of(doc, ch):
    z = doc["zones"].get(ch)
    return z["height"] if z else 0.0


def corner(doc, col, row):
    cs = doc["cs"]
    return col * cs, (doc["rows"] - 1 - row) * cs


def center(doc, col, row):
    x0, z0 = corner(doc, col, row)
    return x0 + doc["cs"] / 2, z0 + doc["cs"] / 2


def edges_of(doc, col, row):
    """マスの 4 辺: (p, q, 内向き, 向こうのマス)。p→q は内から壁を見て左→右（MazeMesh.edgesOf と同じ）。"""
    x0, z0 = corner(doc, col, row)
    x1, z1 = x0 + doc["cs"], z0 + doc["cs"]
    return [((x0, z1), (x1, z1), (0.0, -1.0), (col, row - 1)),
            ((x1, z1), (x1, z0), (-1.0, 0.0), (col + 1, row)),
            ((x1, z0), (x0, z0), (0.0, 1.0), (col, row + 1)),
            ((x0, z0), (x0, z1), (1.0, 0.0), (col - 1, row))]


def chash(col, row, salt):
    h = (row * 131 + col) * 2654435761 + salt * 40503 + 12345
    h ^= (h >> 13)
    h = (h * 1274126177) & 0xFFFFFFFF
    return (h % 100003) / 100003.0


def lamp_cells(zone, spacing):
    n = max(1, spacing)
    if zone["kind"] == "room":
        picked = [c for c in zone["cells"] if c[0] % n == n // 2 and c[1] % n == n // 2]
    else:
        picked = [c for i, c in enumerate(zone["cells"]) if i % n == n // 2]
    return picked or zone["cells"][:1]


# ───────────────────────── trim sheet ─────────────────────────
TRIM_W = TRIM_H = 2048
# 名前 → (上の行, 下の行)。行は絵の上から。U の周期は period_m（m）。
STRIPS = {
    "floor":         (0, 512, None),
    "ceiling":       (512, 768, None),
    "panel":         (768, 1280, 8.0),
    "kick":          (1280, 1488, 8.0),
    "groove":        (1488, 1504, 8.0),
    "trim":          (1504, 1632, 4.0),
    "pipe_steel":    (1632, 1696, 4.0),
    "pipe_paint":    (1696, 1760, 4.0),
    "pipe_graphite": (1760, 1824, 4.0),
    "hazard":        (1824, 1888, 4.0),
    "vent":          (1888, 2048, 8.0),
}


def strip_v(name, f):
    """ストリップの下（f = 0）から上（f = 1）への v（Blender の UV・下が 0）。端の 1.5 px は使わない。"""
    r0, r1, _ = STRIPS[name]
    top = 1.0 - (r0 + 1.5) / TRIM_H
    bot = 1.0 - (r1 - 1.5) / TRIM_H
    return bot + (top - bot) * max(0.0, min(1.0, f))


def strip_u(name, meters):
    return meters / STRIPS[name][2]


def vnoise(h, w, gy, gx, rng):
    g = rng.random((gy + 1, gx))
    ys = np.linspace(0, gy, h, endpoint=False)
    xs = np.arange(w) * gx / w
    y0 = np.floor(ys).astype(int); fy = ys - y0
    x0 = np.floor(xs).astype(int) % gx; fx = xs - np.floor(xs)
    x1 = (x0 + 1) % gx
    fy = (fy * fy * (3 - 2 * fy))[:, None]; fx = (fx * fx * (3 - 2 * fx))[None, :]
    a = g[y0][:, x0]; b = g[y0][:, x1]; c = g[y0 + 1][:, x0]; d = g[y0 + 1][:, x1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def fbm(h, w, gy, gx, rng, octaves=4):
    out = np.zeros((h, w)); amp = 1.0; tot = 0.0
    for o in range(octaves):
        out += amp * vnoise(h, w, gy * 2 ** o, gx * 2 ** o, rng); tot += amp; amp *= 0.5
    return out / tot


def rgb(c, k):
    return np.stack([np.full(k.shape, c[0]) * k, np.full(k.shape, c[1]) * k, np.full(k.shape, c[2]) * k], -1)


def plate_lines(t, w, period, groove=3):
    """周期 period の継ぎ目: 暗い溝と、その片側の明るい縁（1 = 何も無い）。"""
    m = np.mod(np.arange(w), period)
    k = np.ones(w)
    k[m < groove] = 0.35
    k[m == groove] = 1.25
    k[m == period - 1] = 0.8
    return k


def make_trim(path):
    rng = np.random.default_rng(11)
    img = np.zeros((TRIM_H, TRIM_W, 3))
    steel = np.array([0.357, 0.388, 0.420])
    dark = np.array([0.18, 0.19, 0.21])
    graphite = np.array([0.141, 0.153, 0.169])
    floorc = np.array([0.204, 0.220, 0.239])

    # 床: 4 種（0, 1 = 部屋の板・2 = 通路の真ん中に格子・3 = 全面の格子）。1 マス = 512 px。
    yy, xx = np.mgrid[0:512, 0:512]
    grime = fbm(512, 512, 4, 4, rng)
    tread = 1.0 + 0.05 * np.sign(np.sin((xx + yy) * 0.9) * np.sin((xx - yy) * 0.9))
    def plates(sz):
        k = np.ones((512, 512))
        mx = np.mod(xx, sz); my = np.mod(yy, sz)
        k[(mx < 3) | (my < 3)] = 0.3
        k[(mx == 3) | (my == 3)] = 1.3
        for cx in range(0, 512, sz):
            for cy in range(0, 512, sz):
                for bx, by in ((14, 14), (sz - 14, 14), (14, sz - 14), (sz - 14, sz - 14)):
                    d = np.hypot(xx - (cx + bx), yy - (cy + by))
                    k[d < 5] = 0.55; k[d < 3] = 1.35
        return k
    def grate(x0, x1, y0, y1):
        k = np.ones((512, 512))
        sub = (xx >= x0) & (xx < x1) & (yy >= y0) & (yy < y1)
        bars = (np.mod(xx, 10) < 3) | (np.mod(yy, 10) < 3)
        k[sub & ~bars] = 0.18
        k[sub & bars] = 1.15
        edge = sub & ((xx < x0 + 6) | (xx >= x1 - 6) | (yy < y0 + 6) | (yy >= y1 - 6))
        k[edge] = 0.75
        return k
    shade = (0.85 + 0.3 * grime)
    t0 = plates(256) * tread * shade
    t1 = plates(256) * tread * shade * grate(256, 512, 256, 512)
    t2 = plates(512) * shade * np.where((xx >= 102) & (xx < 410), grate(102, 410, 0, 512), tread)
    t3 = grate(0, 512, 0, 512) * shade * plates(512)
    for i, t in enumerate((t0, t1, t2, t3)):
        img[0:512, i * 512:(i + 1) * 512] = rgb(floorc, t)

    # 天井: 8 種。1 マス = 256 px（1 m のマス・ところどころに換気の溝）。
    for i in range(8):
        y2, x2 = np.mgrid[0:256, 0:256]
        k = 0.9 + 0.2 * fbm(256, 256, 4, 4, rng)
        k[(np.mod(x2, 64) < 2) | (np.mod(y2, 64) < 2)] *= 0.45
        for cx in range(4):
            for cy in range(4):
                if rng.random() < 0.18:
                    sub = (x2 >= cx * 64 + 10) & (x2 < cx * 64 + 54) & (y2 >= cy * 64 + 10) & (y2 < cy * 64 + 54)
                    k[sub & (np.mod(y2, 6) < 3)] *= 0.35
        img[512:768, i * 256:(i + 1) * 256] = rgb(graphite * 1.15, k)

    # 壁の板: 2 m × 8 m（256 px/m）。2 m ごとの縦の継ぎ目・板の凹み・鋲・下ほど汚れる。
    h, w = 512, TRIM_W
    y2, x2 = np.mgrid[0:h, 0:w]
    k = 0.92 + 0.16 * fbm(h, w, 4, 16, rng)
    streak = vnoise(h, w, 2, 256, rng)
    k *= 1.0 - 0.18 * streak * (y2 / h) ** 1.5
    px = np.mod(x2, 512)
    k[px < 4] *= 0.3
    k[px == 4] *= 1.3
    inset = (px > 28) & (px < 484) & (y2 > 28) & (y2 < 484)
    k[inset] *= 0.93
    k[(px == 28) & (y2 > 28) & (y2 < 484)] *= 1.35
    k[(y2 == 28) & (px > 28) & (px < 484)] *= 1.35
    k[(px == 484) & (y2 > 28) & (y2 < 484)] *= 0.55
    k[(y2 == 484) & (px > 28) & (px < 484)] *= 0.55
    rivet = (np.mod(y2, 40) < 4) & ((np.abs(px - 12) < 2) | (np.abs(px - 500) < 2))
    k[rivet] *= 1.4
    for p in range(4):
        if p % 2 == 0:
            lx, ly = p * 512 + 300, 330
            sub = (x2 >= lx) & (x2 < lx + 140) & (y2 >= ly) & (y2 < ly + 56)
            k[sub] = 0.35
            bars = sub & (np.mod(y2 - ly, 14) < 5) & (y2 - ly > 6) & (y2 - ly < 50) & (np.mod(x2 - lx, 23) < 17)
            k[bars] = 0.9
    img[768:1280] = rgb(steel, k)

    # 腰板: 0.8 m。横の鎧板と足元の擦り傷。
    h = 208
    y2, x2 = np.mgrid[0:h, 0:w]
    k = 0.9 + 0.2 * fbm(h, w, 2, 16, rng)
    my = np.mod(y2, 26)
    k[my < 3] *= 0.4
    k[my == 3] *= 1.3
    k[np.mod(x2, 512) < 3] *= 0.4
    k *= 1.0 - 0.25 * vnoise(h, w, 2, 64, rng) * (y2 / h) ** 2
    img[1280:1488] = rgb(dark * 1.25, k)

    img[1488:1504] = rgb(np.array([0.05, 0.055, 0.06]), np.ones((16, w)))

    # 暗い金物（面取り・柱・梁・留め具・フランジ・灯具の枠）: 端ほど擦れて明るい。
    h = 128
    y2, x2 = np.mgrid[0:h, 0:w]
    edge = np.minimum(y2, h - 1 - y2) / h
    k = 0.85 + 0.25 * vnoise(h, w, 2, 512, rng)
    k *= 1.0 + 0.6 * np.clip(0.08 - edge, 0, 1) / 0.08 * (vnoise(h, w, 4, 128, rng) > 0.5)
    img[1504:1632] = rgb(graphite * 1.2, k)

    # パイプ 3 種: 長さの向きに筋。
    for r0, base, chip in ((1632, np.array([0.42, 0.45, 0.48]), 0.0),
                           (1696, np.array([0.21, 0.245, 0.255]), 0.12),
                           (1760, graphite, 0.0)):
        h = 64
        k = 0.88 + 0.18 * vnoise(h, w, 4, 512, rng) + 0.06 * vnoise(h, w, 16, 2048, rng)
        col = rgb(base, k)
        if chip > 0:
            n = fbm(h, w, 4, 64, rng)
            mask = n > (1 - chip)
            col[mask] = rgb(np.array([0.40, 0.42, 0.45]), np.ones(h * w).reshape(h, w))[mask]
        img[r0:r0 + 64] = col

    # 警告の縞: 0.25 m 周期の斜めのストライプ（くすんだ黄と黒）・擦れ。
    h = 64
    y2, x2 = np.mgrid[0:h, 0:w]
    band = np.mod(x2 + y2, 128) < 64
    wear = fbm(h, w, 4, 64, rng)
    amber = np.array([0.52, 0.40, 0.12]); blk = np.array([0.055, 0.055, 0.06])
    col = np.where(band[..., None], amber, blk) * (0.85 + 0.2 * wear[..., None])
    worn = wear > 0.72
    col[worn] = col[worn] * 0.4 + np.array([0.3, 0.31, 0.33]) * 0.6
    img[1824:1888] = col

    # 換気のストリップ: 横の羽根・2 m ごとの仕切り。
    h = 160
    y2, x2 = np.mgrid[0:h, 0:w]
    k = np.ones((h, w))
    my = np.mod(y2, 12)
    k[my < 5] = 0.25
    k[my == 5] = 1.2
    k[(y2 < 10) | (y2 >= h - 10)] = 0.95
    k[np.mod(x2, 512) < 14] = 0.9
    k *= 0.9 + 0.2 * fbm(h, w, 2, 16, rng)
    img[1888:2048] = rgb(dark, k)

    img = np.clip(img, 0, 1)
    rgba = np.concatenate([img[::-1], np.ones((TRIM_H, TRIM_W, 1))], -1).astype(np.float32)
    im = bpy.data.images.new("T_stage_trim", TRIM_W, TRIM_H, alpha=False)
    im.pixels.foreach_set(rgba.ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)
    return bpy.data.images.load(path)


# ───────────────────────── 材質 ─────────────────────────
def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_lin(h):
    h = h.lstrip("#")
    return tuple(srgb_to_lin(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


def make_materials(trim, look):
    mats = {}
    m = bpy.data.materials.new("M_hull")
    nt = m.node_tree
    p = nt.nodes.get("Principled BSDF")
    uv = nt.nodes.new("ShaderNodeUVMap"); uv.uv_map = "UVMap"
    tx = nt.nodes.new("ShaderNodeTexImage"); tx.image = trim; tx.name = "TRIM"
    nt.links.new(uv.outputs[0], tx.inputs[0])
    nt.links.new(tx.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = 0.6
    p.inputs["Metallic"].default_value = 0.0
    mats["hull"] = m
    for key, col, strength in (("strip", hex_lin(look["stripColor"]), 6.0),
                               ("lamp", hex_lin(look["roomLightColor"]), 3.0)):
        m = bpy.data.materials.new("M_" + key)
        p = m.node_tree.nodes.get("Principled BSDF")
        p.inputs["Base Color"].default_value = (*[c * 0.3 for c in col], 1.0)
        p.inputs["Emission Color"].default_value = (*col, 1.0)
        p.inputs["Emission Strength"].default_value = strength
        p.inputs["Roughness"].default_value = 0.4
        mats[key] = m
    return mats


MAT_INDEX = {"hull": 0, "strip": 1, "lamp": 2}


# ───────────────────────── 形を組む道具 ─────────────────────────
def B(p):
    return Vector((-p[0], -p[2], p[1]))


def Bdir(d):
    return Vector((-d[0], -d[2], d[1]))


class Builder:
    """1 区画の bmesh。点は engine の座標で受け取る。detail = lightmap の島の大きさの重みの組（0 = 1.0・1 = パイプ・2 = 小物）。"""
    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.detail = self.bm.faces.layers.int.new("detail")

    def face(self, pts, uvs, normal, mat="hull", detail=0, smooth=False, verts=None):
        bp = [B(p) for p in pts] if verts is None else [v.co.copy() for v in verts]
        n = Vector((0, 0, 0))
        for i in range(len(bp)):
            a, b = bp[i], bp[(i + 1) % len(bp)]
            n += Vector(((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y)))
        order = list(range(len(bp)))
        if normal is not None and n.dot(Bdir(normal)) < 0:
            order.reverse()
        vs = [verts[i] for i in order] if verts is not None else [self.bm.verts.new(bp[i]) for i in order]
        try:
            f = self.bm.faces.new(vs)
        except ValueError:
            return None
        for loop, i in zip(f.loops, order):
            loop[self.uv].uv = uvs[i]
        f.material_index = MAT_INDEX[mat]
        f[self.detail] = detail
        f.smooth = smooth
        return f

    def quad_strip(self, pts, strip, u0, u1, f0=0.0, f1=1.0, normal=None, mat="hull", detail=0):
        """pts = 左下・右下・右上・左上。U は u0→u1（m）・V はストリップの f0→f1。"""
        uvs = [(strip_u(strip, u0), strip_v(strip, f0)), (strip_u(strip, u1), strip_v(strip, f0)),
               (strip_u(strip, u1), strip_v(strip, f1)), (strip_u(strip, u0), strip_v(strip, f1))]
        return self.face(pts, uvs, normal, mat, detail)

    def box(self, c, ax, ay, az, hx, hy, hz, strip="trim", detail=2, skip=()):
        """向き ax・ay・az（engine の単位ベクトル）の箱。skip = 描かない面（"-x" など）。"""
        c = Vector(c); ax = Vector(ax); ay = Vector(ay); az = Vector(az)
        def P(sx, sy, sz):
            return c + ax * (sx * hx) + ay * (sy * hy) + az * (sz * hz)
        faces = {
            "+x": ([P(1, -1, -1), P(1, -1, 1), P(1, 1, 1), P(1, 1, -1)], ax, 2 * hz, 2 * hy),
            "-x": ([P(-1, -1, 1), P(-1, -1, -1), P(-1, 1, -1), P(-1, 1, 1)], -ax, 2 * hz, 2 * hy),
            "+y": ([P(-1, 1, -1), P(1, 1, -1), P(1, 1, 1), P(-1, 1, 1)], ay, 2 * hx, 2 * hz),
            "-y": ([P(-1, -1, 1), P(1, -1, 1), P(1, -1, -1), P(-1, -1, -1)], -ay, 2 * hx, 2 * hz),
            "+z": ([P(1, -1, 1), P(-1, -1, 1), P(-1, 1, 1), P(1, 1, 1)], az, 2 * hx, 2 * hy),
            "-z": ([P(-1, -1, -1), P(1, -1, -1), P(1, 1, -1), P(-1, 1, -1)], -az, 2 * hx, 2 * hy),
        }
        for key, (pts, n, wu, wv) in faces.items():
            if key in skip:
                continue
            self.quad_strip([tuple(p) for p in pts], strip, 0.0, wu, 0.0, min(1.0, wv / 0.5), normal=tuple(n), detail=detail)

    def tube(self, samples, r, sides, strip, detail=1, closed=False, caps=True, mat="hull"):
        """samples = [(点, 長さ s)]。外向きの面・なめらかな陰。"""
        n = len(samples)
        if n < 2:
            return
        pts = [Vector(p) for p, _ in samples]
        tans = []
        for i in range(n):
            if closed:
                t = pts[(i + 1) % n] - pts[i - 1]
            else:
                t = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
            tans.append(t.normalized())
        up = Vector((0, 1, 0))
        nrm = up - tans[0] * up.dot(tans[0])
        if nrm.length < 1e-3:
            nrm = Vector((1, 0, 0)) - tans[0] * tans[0].x
        nrm.normalize()
        rings = []
        for i in range(n):
            t = tans[i]
            nrm = (nrm - t * nrm.dot(t)).normalized()
            bi = t.cross(nrm)
            ring = []
            for j in range(sides):
                a = 2 * math.pi * j / sides
                ring.append(self.bm.verts.new(B(pts[i] + (nrm * math.cos(a) + bi * math.sin(a)) * r)))
            rings.append(ring)
        segs = n if closed else n - 1
        for i in range(segs):
            i2 = (i + 1) % n
            s0, s1 = samples[i][1], samples[i2][1]
            if closed and i2 == 0:
                s1 = s0 + (pts[0] - pts[i]).length
            for j in range(sides):
                j2 = (j + 1) % sides
                vs = [rings[i][j], rings[i][j2], rings[i2][j2], rings[i2][j]]
                uvs = [(strip_u(strip, s0), strip_v(strip, j / sides)), (strip_u(strip, s0), strip_v(strip, (j + 1) / sides)),
                       (strip_u(strip, s1), strip_v(strip, (j + 1) / sides)), (strip_u(strip, s1), strip_v(strip, j / sides))]
                c4 = sum((v.co for v in vs), Vector()) / 4
                d = c4 - (B(pts[i]) + B(pts[i2])) / 2
                vs, uvs = self._orient(vs, uvs, d)
                self.face(None, uvs, None, mat, detail, True, verts=vs)
        if caps and not closed:
            for i, sign in ((0, -1), (n - 1, 1)):
                vs = rings[i]
                uvs = [(strip_u("trim", 0.5 + 0.5 * math.cos(2 * math.pi * j / sides) * r),
                        strip_v("trim", 0.5 + 0.5 * math.sin(2 * math.pi * j / sides))) for j in range(sides)]
                vs, uvs = self._orient(vs, uvs, Bdir(tans[i] * sign))
                self.face(None, uvs, None, mat, detail, False, verts=vs)

    def _orient(self, vs, uvs, d):
        bp = [v.co for v in vs]
        n = (bp[1] - bp[0]).cross(bp[2] - bp[0])
        if n.length < 1e-12 and len(bp) > 3:
            n = (bp[2] - bp[0]).cross(bp[3] - bp[0])
        return (vs, uvs) if n.dot(d) >= 0 else (list(reversed(vs)), list(reversed(uvs)))

    def collar(self, c, t, r, length, sides, strip="trim", detail=2):
        t = Vector(t).normalized()
        c = Vector(c)
        self.tube([(c - t * length / 2, 0.0), (c + t * length / 2, length)], r, sides, strip, detail)


# ───────────────────────── 道（鎖） ─────────────────────────
def chains(edge_list):
    """辺の並び [(p, q, 内向き, 付けたい物)] を p→q でつないだ鎖。閉じた輪は (鎖, True)。"""
    key = lambda p: (round(p[0], 4), round(p[1], 4))
    by_p = {}
    for e in edge_list:
        by_p.setdefault(key(e[0]), []).append(e)
    q_keys = {key(e[1]) for e in edge_list}
    used = set()
    out = []
    def walk(e0):
        ch = [e0]; used.add(id(e0))
        cur = e0
        while True:
            nxt = [e for e in by_p.get(key(cur[1]), []) if id(e) not in used]
            if not nxt:
                break
            cur = nxt[0]; ch.append(cur); used.add(id(cur))
        return ch
    for e in edge_list:
        if id(e) not in used and key(e[0]) not in q_keys:
            out.append((walk(e), False))
    for e in edge_list:
        if id(e) not in used:
            ch = walk(e)
            out.append((ch, key(ch[-1][1]) == key(ch[0][0])))
    return out


def offset_points(ch, closed, d, y):
    """鎖の頂点を内へ d・高さ y にずらした点（角は 2 本の内向きの和で留め継ぎ）。"""
    m = len(ch)
    pts = []
    for i in range(m + (0 if closed else 1)):
        if closed:
            n0 = ch[i - 1][2]; n1 = ch[i % m][2]; v = ch[i % m][0]
        else:
            n0 = ch[i - 1][2] if i > 0 else None
            n1 = ch[i][2] if i < m else None
            v = ch[i][0] if i < m else ch[m - 1][1]
        if n0 is None:
            nx, nz = n1
        elif n1 is None:
            nx, nz = n0
        elif abs(n0[0] - n1[0]) < 1e-6 and abs(n0[1] - n1[1]) < 1e-6:
            nx, nz = n0
        else:
            nx, nz = n0[0] + n1[0], n0[1] + n1[1]
        pts.append(Vector((v[0] + nx * d, y, v[1] + nz * d)))
    return pts


def rounded(pts, R, closed, steps=4):
    """折れ線の角を丸めた点の並びと、頭からの長さ。"""
    n = len(pts)
    clean = []
    for i in range(n):
        if not closed and (i == 0 or i == n - 1):
            clean.append(pts[i]); continue
        a, p, b = pts[i - 1], pts[i], pts[(i + 1) % n]
        if (p - a).length < 1e-6:
            continue
        if (b - p).length > 1e-6 and (p - a).normalized().dot((b - p).normalized()) > 0.9999:
            continue
        clean.append(p)
    pts = clean
    n = len(pts)
    out = []
    for i in range(n):
        p = pts[i]
        if not closed and (i == 0 or i == n - 1):
            out.append(p); continue
        a, b = pts[i - 1], pts[(i + 1) % n]
        d1 = (p - a); d2 = (b - p)
        L1, L2 = d1.length, d2.length
        d1.normalize(); d2.normalize()
        th = math.acos(max(-1.0, min(1.0, d1.dot(d2))))
        t = min(R * math.tan(th / 2), 0.45 * L1, 0.45 * L2)
        A = p - d1 * t; Bp = p + d2 * t
        for k in range(steps + 1):
            u = k / steps
            out.append(A * (1 - u) ** 2 + p * 2 * u * (1 - u) + Bp * u * u)
    s = 0.0
    res = []
    for i, p in enumerate(out):
        if i > 0:
            s += (p - out[i - 1]).length
        res.append((p, s))
    return res


# ───────────────────────── 区画の形 ─────────────────────────
def zone_edges(doc, zone):
    """区画の辺を種類で分ける: wall（向こうが壁）・step（向こうが低い床 = 高さの違う境目の壁）・open（向こうが同じ高さか高い床）。"""
    zid = zone["id"]
    out = {"wall": [], "step": [], "open": []}
    for (col, row) in zone["cells"]:
        for p, q, n, (oc, orow) in edges_of(doc, col, row):
            ch = char_at(doc, oc, orow)
            if ch == zid:
                continue
            if not is_floor(ch):
                out["wall"].append((p, q, n, {"cell": (col, row)}))
            elif height_of(doc, ch) < zone["height"] - 1e-6:
                out["step"].append((p, q, n, {"cell": (col, row), "other": ch, "oh": height_of(doc, ch)}))
            else:
                out["open"].append((p, q, n, {"cell": (col, row), "other": ch, "oh": height_of(doc, ch)}))
    return out


def wall_bands(h, kind):
    """壁のストリップ (下, 上, ストリップの名前, 下の内への量, 上の内への量, V の範囲)。"""
    k = BEVEL
    b = [(0.0, k, "trim", k, 0.0, (0.0, 1.0)),
         (k, SEAM_LO, "kick", 0.0, 0.0, (0.0, 1.0))]
    top = h - k - VENT
    y = SEAM_HI
    while top - y > 0.05:
        hh = min(2.0, top - y)
        b.append((y, y + hh, "panel", 0.0, 0.0, (0.0, hh / 2.0)))
        y += hh
    b.append((top, h - k, "vent", 0.0, 0.0, (0.0, 1.0)))
    b.append((h - k, h, "trim", 0.0, k, (0.0, 1.0)))
    return b


def build_zone(doc, zone, look, rng):
    bld = Builder()
    h = zone["height"]
    room = zone["kind"] == "room"
    cs = doc["cs"]
    zid = zone["id"]
    E = zone_edges(doc, zone)
    cellset = set(zone["cells"])

    # 床と天井
    for (col, row) in zone["cells"]:
        x0, z0 = corner(doc, col, row)
        x1, z1 = x0 + cs, z0 + cs
        if room:
            var = 0 if chash(col, row, 1) < 0.7 else 1
            rot = chash(col, row, 2) < 0.5
        else:
            ns = (col, row - 1) in cellset or (col, row + 1) in cellset
            ew = (col - 1, row) in cellset or (col + 1, row) in cellset
            var = 3 if (ns and ew) else 2
            rot = ew and not ns
        def fuv(a, b, var=var, rot=rot):
            if rot:
                a, b = b, a
            return ((var + a) / 4.0, strip_v("floor", b))
        pts = [(x0, 0.0, z0), (x1, 0.0, z0), (x1, 0.0, z1), (x0, 0.0, z1)]
        bld.face(pts, [fuv(0, 0), fuv(1, 0), fuv(1, 1), fuv(0, 1)], (0, 1, 0))
        cv = int(chash(col, row, 3) * 8)
        cuv = lambda a, b: ((cv + a) / 8.0, strip_v("ceiling", b))
        pts = [(x0, h, z0), (x1, h, z0), (x1, h, z1), (x0, h, z1)]
        bld.face(pts, [cuv(0, 0), cuv(1, 0), cuv(1, 1), cuv(0, 1)], (0, -1, 0))

    # 壁: 鎖ごとにストリップを通す（角は留め継ぎ）
    wall_lamps = []
    wall_chains = chains(E["wall"])
    bands = wall_bands(h, zone["kind"])
    for ch, closed in wall_chains:
        m = len(ch)
        for (y0, y1, strip, i0, i1, (f0, f1)) in bands:
            lo = offset_points(ch, closed, i0, y0)
            hi = offset_points(ch, closed, i1, y1)
            uoff = 2.37 * int(y0 / 2.0) if strip == "panel" else 0.0
            for k in range(m):
                e = ch[k]
                a0, a1 = lo[k], lo[(k + 1) % len(lo)]
                b0, b1 = hi[k], hi[(k + 1) % len(hi)]
                ax = 0 if abs(e[0][1] - e[1][1]) < 1e-6 else 2
                bld.quad_strip([tuple(a0), tuple(a1), tuple(b1), tuple(b0)], strip,
                               a0[ax] + uoff, a1[ax] + uoff, f0, f1, normal=(e[2][0], 0, e[2][1]))
            # 継ぎ目の溝（壁の面より奥へ 4 cm）
        lo_g = offset_points(ch, closed, 0.0, SEAM_LO)
        lo_b = offset_points(ch, closed, -0.04, SEAM_LO)
        hi_b = offset_points(ch, closed, -0.04, SEAM_HI)
        hi_g = offset_points(ch, closed, 0.0, SEAM_HI)
        for k in range(m):
            e = ch[k]; k2 = (k + 1) % len(lo_g)
            ax = 0 if abs(e[0][1] - e[1][1]) < 1e-6 else 2
            u0, u1 = lo_g[k][ax], lo_g[k2][ax]
            bld.quad_strip([tuple(lo_b[k]), tuple(lo_b[k2]), tuple(lo_g[k2]), tuple(lo_g[k])], "groove", u0, u1, normal=(0, 1, 0))
            bld.quad_strip([tuple(lo_b[k]), tuple(lo_b[k2]), tuple(hi_b[k2]), tuple(hi_b[k])], "groove", u0, u1, normal=(e[2][0], 0, e[2][1]))
            bld.quad_strip([tuple(hi_g[k]), tuple(hi_g[k2]), tuple(hi_b[k2]), tuple(hi_b[k])], "groove", u0, u1, normal=(0, -1, 0))
        if not closed:
            # 鎖の端（区画の境目）で、面取りと溝の切り口をふさぐ
            for idx, e, sgn in ((0, ch[0], -1), (m, ch[-1], 1)):
                ex, ez = e[1][0] - e[0][0], e[1][1] - e[0][1]
                L = math.hypot(ex, ez); dn = (sgn * ex / L, 0.0, sgn * ez / L)
                v = ch[0][0] if idx == 0 else ch[-1][1]
                nx, nz = e[2]
                P = lambda d, y: (v[0] + nx * d, y, v[1] + nz * d)
                tri_uv = [(0.0, strip_v("trim", 0)), (0.1, strip_v("trim", 1)), (0.0, strip_v("trim", 1))]
                bld.face([P(0, BEVEL), P(BEVEL, 0), P(0, 0)], tri_uv, dn)
                bld.face([P(0, h - BEVEL), P(BEVEL, h), P(0, h)], tri_uv, dn)
                bld.face([P(0, SEAM_LO), P(-0.04, SEAM_LO), P(-0.04, SEAM_HI), P(0, SEAM_HI)], tri_uv + [(0.1, strip_v("trim", 0))], dn)

        # 柱（まっすぐ続く壁の、マスの境目ごと）
        for i in range(1, m + (1 if closed else 0)):
            e0, e1 = ch[i - 1], ch[i % m]
            if e0[2] != e1[2]:
                continue
            v = e1[0]
            n = Vector((e1[2][0], 0, e1[2][1]))
            t = Vector((e1[1][0] - e1[0][0], 0, e1[1][1] - e1[0][1])).normalized()
            rib(bld, Vector((v[0], 0, v[1])), t, n, h)
            if room and chash(int(v[0]), int(v[1]), 31) < 0.5:
                wall_lamps.append(wall_lamp(bld, Vector((v[0], 0, v[1])), t, n, 4.2 if h >= 9 else 3.5))

    # 光る筋
    for ch, closed in wall_chains:
        m = len(ch)
        if room:
            y0 = BEVEL + 0.12
        else:
            y0 = h - BEVEL - 0.25
        lo = offset_points(ch, closed, 0.02, y0)
        hi = offset_points(ch, closed, 0.02, y0 + 0.08)
        for k in range(m):
            e = ch[k]
            if room and chash(e[3]["cell"][0], e[3]["cell"][1], 20 + int(e[2][0] * 2 + e[2][1] * 3 + 5)) >= 0.55:
                continue
            k2 = (k + 1) % len(lo)
            ax = 0 if abs(e[0][1] - e[1][1]) < 1e-6 else 2
            bld.quad_strip([tuple(lo[k]), tuple(lo[k2]), tuple(hi[k2]), tuple(hi[k])], "trim", lo[k][ax], lo[k2][ax],
                           normal=(e[2][0], 0, e[2][1]), mat="strip", detail=2)

    # 高さの違う境目の壁（低い区画との境目の上）と、扉の枠
    for p, q, n, info in E["step"]:
        oh = info["oh"]
        ax = 0 if abs(p[1] - q[1]) < 1e-6 else 2
        y = oh
        while h - y > 0.02:
            hh = min(2.0, h - y)
            pts = [(p[0], y, p[1]), (q[0], y, q[1]), (q[0], y + hh, q[1]), (p[0], y + hh, p[1])]
            ua, ub = (p[0], q[0]) if ax == 0 else (p[1], q[1])
            bld.quad_strip(pts, "panel", ua, ub, 0.0, hh / 2.0, normal=(n[0], 0, n[1]))
            y += hh
    for run in merge_runs(E["step"]):
        door_frame(bld, run, h, doc, zid)

    # 天井の梁と、通路の枠
    beams(bld, doc, zone, cellset)

    # 灯具
    lamps = []
    for (col, row) in lamp_cells(zone, int(look["lampSpacing"])):
        cx, cz = center(doc, col, row)
        half = 0.9 if room else 0.35
        hs = half + 0.12
        dep = 0.16 if room else 0.12
        bld.box((cx, h - dep / 2, cz), (1, 0, 0), (0, 1, 0), (0, 0, 1), hs, dep / 2, hs, skip=("+y",), detail=2)
        yp = h - dep - 0.004
        bld.quad_strip([(cx - half, yp, cz - half), (cx + half, yp, cz - half), (cx + half, yp, cz + half), (cx - half, yp, cz + half)],
                       "trim", 0, 1, normal=(0, -1, 0), mat="lamp", detail=2)
        lamps.append({"pos": (cx, yp - 0.01, cz), "size": 2 * half, "room": room, "kind": "ceiling"})
    lamps += wall_lamps

    # パイプ
    pipes(bld, doc, zone, E, rng)

    return bld, lamps


def rib(bld, base, t, n, h, half=0.16, depth=RIB_DEPTH):
    prof = [(-half, 0.0), (-half, depth * 0.6), (-half + 0.05, depth), (half - 0.05, depth), (half, depth * 0.6), (half, 0.0)]
    for i in range(len(prof) - 1):
        (t0, n0), (t1, n1) = prof[i], prof[i + 1]
        a = base + t * t0 + n * n0
        b = base + t * t1 + n * n1
        mid_n = (n * ((t1 - t0)) - t * ((n1 - n0))).normalized()
        pts = [(a.x, 0.0, a.z), (b.x, 0.0, b.z), (b.x, h, b.z), (a.x, h, a.z)]
        f0, f1 = i / 5.0, (i + 1) / 5.0
        uvs = [(strip_u("trim", 0), strip_v("trim", f0)), (strip_u("trim", 0), strip_v("trim", f1)),
               (strip_u("trim", h), strip_v("trim", f1)), (strip_u("trim", h), strip_v("trim", f0))]
        bld.face(pts, uvs, tuple(mid_n), detail=0)


def wall_lamp(bld, base, t, n, y):
    """柱の面の小さな灯り（部屋の壁の上半分と束を照らす）。"""
    c = base + n * (RIB_DEPTH + 0.05) + Vector((0, y, 0))
    bld.box(c, tuple(t), (0, 1, 0), tuple(n), 0.1, 0.32, 0.05, skip=("-z",), detail=2)
    f = c + n * 0.052
    pts = [f - t * 0.07 - Vector((0, 0.27, 0)), f + t * 0.07 - Vector((0, 0.27, 0)),
           f + t * 0.07 + Vector((0, 0.27, 0)), f - t * 0.07 + Vector((0, 0.27, 0))]
    bld.quad_strip([tuple(p) for p in pts], "trim", 0, 1, normal=tuple(n), mat="lamp", detail=2)
    p = c + n * 0.4
    return {"pos": (p.x, p.y, p.z), "size": 0.3, "room": True, "kind": "wall"}


def merge_runs(edges):
    """同じ線の上で続く辺をまとめる: [(始め, 終わり, 内向き, 向こうの高さ)]。"""
    key = lambda p: (round(p[0], 4), round(p[1], 4))
    out = []
    for ch, _ in chains([(p, q, n, info) for p, q, n, info in edges]):
        cur = None
        for p, q, n, info in ch:
            if cur and cur[2] == n:
                cur[1] = q
            else:
                if cur:
                    out.append(tuple(cur))
                cur = [p, q, n, info["oh"]]
        if cur:
            out.append(tuple(cur))
    return out


def door_frame(bld, run, h, doc, zid):
    p, q, n, oh = run
    t = Vector((q[0] - p[0], 0, q[1] - p[1]))
    L = t.length; t.normalize()
    nv = Vector((n[0], 0, n[1]))
    P = Vector((p[0], 0, p[1]))
    jw, jd = 0.45, 0.32
    top = min(h, oh + 0.4)
    def inside(p):
        col = int(math.floor(p.x / doc["cs"])); row = doc["rows"] - 1 - int(math.floor(p.z / doc["cs"]))
        return char_at(doc, col, row) == zid
    # WhyNot: 枠の柱をいつも開口の外の壁へ置かない — 開口が部屋の隅で終わると、柱が隣の壁のマスの中へ出る
    a = P - t * (jw / 2) if inside(P - t * (jw / 2) + nv * 0.5) else P + t * (jw / 2)
    b = P + t * (L + jw / 2) if inside(P + t * (L + jw / 2) + nv * 0.5) else P + t * (L - jw / 2)
    for s, c in ((-1, a), (1, b)):
        bld.box(c + nv * (jd / 2) + Vector((0, top / 2, 0)), tuple(t), (0, 1, 0), tuple(nv), jw / 2, top / 2, jd / 2,
                skip=("-z",), detail=0)
    mid = P + t * (L / 2) + nv * (jd / 2) + Vector((0, oh + (top - oh) / 2, 0))
    bld.box(mid, tuple(t), (0, 1, 0), tuple(nv), L / 2, (top - oh) / 2, jd / 2, strip="hazard", skip=("-z", "+x", "-x"), detail=0)


def beams(bld, doc, zone, cellset):
    cs = doc["cs"]; h = zone["height"]
    if zone["kind"] == "room":
        cols = [c for c, _ in zone["cells"]]; rows = [r for _, r in zone["cells"]]
        along_z = (max(cols) - min(cols)) >= (max(rows) - min(rows))
        dep, wid = 0.5, 0.4
        for (col, row) in zone["cells"]:
            if along_z and (col + 1, row) in cellset and (col + 1) % 2 == 0:
                x0, z0 = corner(doc, col + 1, row)
                bld.box((x0, h - dep / 2, z0 + cs / 2), (1, 0, 0), (0, 1, 0), (0, 0, 1), wid / 2, dep / 2, cs / 2,
                        skip=("+y", "+z", "-z"), detail=0)
            if not along_z and (col, row + 1) in cellset and (row + 1) % 2 == 0:
                x0, z0 = corner(doc, col, row)
                bld.box((x0 + cs / 2, h - dep / 2, z0), (1, 0, 0), (0, 1, 0), (0, 0, 1), cs / 2, dep / 2, wid / 2,
                        skip=("+y", "+x", "-x"), detail=0)
    else:
        dep, wid = 0.35, 0.3
        wall = lambda c, r: not is_floor(char_at(doc, c, r))
        for (col, row) in zone["cells"]:
            if (col + 1, row) in cellset and wall(col, row - 1) and wall(col, row + 1) and wall(col + 1, row - 1) and wall(col + 1, row + 1):
                x0, z0 = corner(doc, col + 1, row)
                bld.box((x0, h - dep / 2, z0 + cs / 2), (1, 0, 0), (0, 1, 0), (0, 0, 1), wid / 2, dep / 2, cs / 2,
                        skip=("+y", "+z", "-z"), detail=0)
            if (col, row + 1) in cellset and wall(col - 1, row) and wall(col + 1, row) and wall(col - 1, row + 1) and wall(col + 1, row + 1):
                x0, z0 = corner(doc, col, row)
                bld.box((x0 + cs / 2, h - dep / 2, z0), (1, 0, 0), (0, 1, 0), (0, 0, 1), cs / 2, dep / 2, wid / 2,
                        skip=("+y", "+x", "-x"), detail=0)


# ───────────────────────── パイプ ─────────────────────────
def bundles_for(zone, rng):
    """区画の壁を這う束: [(太さのレベル, 高さ)]。"""
    h = zone["height"]
    if zone["kind"] != "room":
        return [[("L", 2.95), ("M", 2.6), ("S", 3.28)]]
    out = []
    def stack(top, tiers):
        y = top; lst = []
        for i, t in enumerate(tiers):
            r = TIERS[t]
            if i > 0:
                y -= r + 0.08
            lst.append((t, round(y, 3)))
            y -= r
        return lst
    if h >= 9:
        out.append(stack(h - 1.3, ["XL", "L", "M", "L"]))
        out.append(stack(5.6, ["L", "M", "S"]))
        out.append(stack(2.9, ["M", "S"]))
    else:
        tiers = rng.choice([["L", "M", "S"], ["L", "M", "M", "S"], ["L", "S"], ["M", "L", "S"]])
        out.append(stack(h - 0.95, tiers))
        if rng.random() < 0.85:
            out.append(stack(2.85, rng.choice([["M", "S"], ["L"], ["M", "M"]])))
    return out


def pipes(bld, doc, zone, E, rng):
    h = zone["height"]
    room = zone["kind"] == "room"
    cs = doc["cs"]
    for bundle in bundles_for(zone, rng):
        ys = [y for _, y in bundle]
        per_chain = {}
        for tier, y in bundle:
            r = TIERS[tier]
            # 高さの違う境目の壁の上を越えられる高さなら、その辺も壁として這わせる
            solid = list(E["wall"]) + [e for e in E["step"] if y - r - 0.15 > e[3]["oh"]]
            for ch, closed in chains(solid):
                off = WALL_GAP + r
                pts = offset_points(ch, closed, off, y)
                path = rounded(pts, max(0.35, 2.5 * r), closed)
                bld.tube(path, r, SIDES[tier], PIPE_STRIP[tier], detail=1, closed=closed, caps=not closed)
                pipe_details(bld, path, r, tier, closed, rng, room, cs)
                per_chain.setdefault(tuple(map(lambda e: (e[0], e[1]), ch)), (ch, closed, []))[2].append((tier, y, off, r))
        for (ch, closed, items) in per_chain.values():
            clamps(bld, ch, closed, items)
    if room:
        drops(bld, E, zone, rng)
        ceiling_runs(bld, doc, zone, rng)
    else:
        if rng.random() < 0.5:
            for ch, closed in chains(E["wall"]):
                if len(ch) < 2:
                    continue
                pts = offset_points(ch, closed, 1.15, h - 0.42)
                path = rounded(pts, 0.4, closed)
                bld.tube(path, TIERS["S"], SIDES["S"], "pipe_graphite", detail=1, closed=closed, caps=not closed)
                break


def pipe_details(bld, path, r, tier, closed, rng, room, cs):
    """フランジ（マスの真ん中の線を越える所）・弁・警告の縞・端の板。"""
    pts = [p for p, _ in path]
    total = path[-1][1]
    fr = r * 1.38
    fl = max(0.05, r * 0.45)
    sides = max(8, SIDES[tier])
    seg_ok = []
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        d = b - a
        if d.length < 0.5:
            continue
        dn = d.normalized()
        ax = 0 if abs(dn.x) > 0.99 else 2 if abs(dn.z) > 0.99 else None
        if ax is None:
            continue
        seg_ok.append((a, b, dn, ax))
        lo, hi = sorted((a[ax], b[ax]))
        k0 = math.ceil((lo - cs / 2) / cs)
        while k0 * cs + cs / 2 < hi:
            v = k0 * cs + cs / 2
            if v - lo > 0.3 and hi - v > 0.3:
                c = a + dn * abs(v - a[ax])
                bld.collar(c, dn, fr, fl, sides)
            k0 += 1
    if not closed and len(pts) >= 2:
        for i, j in ((0, 1), (-1, -2)):
            dn = (pts[i] - pts[j]).normalized()
            bld.collar(pts[i] - dn * (fl / 2 + 0.01), dn, fr, fl, sides)
            bld.collar(pts[i] - dn * 0.012, dn, r * 2.0, 0.024, sides)
            if tier in ("L", "XL") and (pts[i] - pts[j]).length > 1.6:
                bld.collar(pts[i] - dn * 0.7, dn, r * 1.06, 0.32, SIDES[tier], strip="hazard")
    if tier in ("L", "XL", "M"):
        every = 9.0 if tier != "M" else 15.0
        s_next = rng.uniform(2.5, every)
        for a, b, dn, ax in seg_ok:
            L = (b - a).length
            s = 1.2
            while s < L - 1.2:
                if s_next <= 0:
                    c = a + dn * s
                    if abs(((c[ax] - cs / 2) / cs) - round((c[ax] - cs / 2) / cs)) * cs > 0.5 and abs((c[ax] / cs) - round(c[ax] / cs)) * cs > 0.5:
                        valve(bld, c, dn, r, room)
                        s_next = rng.uniform(every * 0.7, every * 1.4)
                s += 0.5
                s_next -= 0.5


def valve(bld, c, dn, r, room):
    sides = 12
    bld.collar(c, dn, r * 1.55, 0.34, sides)
    bld.collar(c - dn * 0.32, dn, r * 1.07, 0.2, sides, strip="hazard")
    bld.collar(c + dn * 0.32, dn, r * 1.07, 0.2, sides, strip="hazard")
    up = Vector((0, 1, 0))
    side = dn.cross(up).normalized()
    # 弁の軸は通路の真ん中の向き（壁から離れる向き）へ。どちらが内かは手がかりが無いので上へ立てる。
    stem_dir = up
    top = c + stem_dir * (r * 1.55 + 0.16)
    bld.tube([(c + stem_dir * r, 0.0), (top, 0.16 + r * 0.55)], 0.022, 6, "trim", detail=2)
    wheel(bld, top, stem_dir, 0.13 + r * 0.4)


def wheel(bld, c, axis, R):
    axis = Vector(axis).normalized()
    a = Vector((1, 0, 0)) if abs(axis.x) < 0.9 else Vector((0, 0, 1))
    u = (a - axis * a.dot(axis)).normalized(); v = axis.cross(u)
    seg = 10
    ring = []
    for i in range(seg + 1):
        th = 2 * math.pi * i / seg
        ring.append((c + (u * math.cos(th) + v * math.sin(th)) * R, R * th))
    bld.tube(ring[:-1], 0.018, 5, "pipe_paint", detail=2, closed=True, caps=False)
    for th in (0.0, math.pi / 2):
        d = u * math.cos(th) + v * math.sin(th)
        bld.box(c, tuple(d), tuple(axis), tuple(d.cross(axis)), R, 0.012, 0.012, detail=2)


def clamps(bld, ch, closed, items):
    """柱の位置の留め具: 柱の面の縦の板と、パイプごとの腕。"""
    if not items:
        return
    ylo = min(y - r for _, y, _, r in items) - 0.12
    yhi = max(y + r for _, y, _, r in items) + 0.12
    m = len(ch)
    for i in range(1, m + (1 if closed else 0)):
        e0, e1 = ch[i - 1], ch[i % m]
        if e0[2] != e1[2] or "oh" in e0[3] or "oh" in e1[3]:
            continue
        v = e1[0]
        n = Vector((e1[2][0], 0, e1[2][1]))
        t = Vector((e1[1][0] - e1[0][0], 0, e1[1][1] - e1[0][1])).normalized()
        base = Vector((v[0], 0, v[1]))
        bld.box(base + n * (RIB_DEPTH + 0.015) + Vector((0, (ylo + yhi) / 2, 0)), tuple(t), (0, 1, 0), tuple(n),
                0.07, (yhi - ylo) / 2, 0.015, skip=("-z",), detail=2)
        for _, y, off, r in items:
            reach = off - RIB_DEPTH
            bld.box(base + n * (RIB_DEPTH + reach / 2) + Vector((0, y - r - 0.03, 0)), tuple(t), (0, 1, 0), tuple(n),
                    0.045, 0.03, reach / 2, skip=("-z",), detail=2)


def drops(bld, E, zone, rng):
    """部屋の壁を床から天井際まで縦に走るパイプ。"""
    h = zone["height"]
    p_drop = 0.3 if h < 9 else 0.35
    for p, q, n, info in E["wall"]:
        if rng.random() > p_drop:
            continue
        mx, mz = (p[0] + q[0]) / 2, (p[1] + q[1]) / 2
        tx, tz = q[0] - p[0], q[1] - p[1]
        L = math.hypot(tx, tz)
        shift = rng.uniform(-0.9, 0.9)
        r = 0.06
        off = 0.095
        cx, cz = mx + tx / L * shift + n[0] * off, mz + tz / L * shift + n[1] * off
        top = h - BEVEL * 0.5
        path = [(Vector((cx, 0.0, cz)), 0.0), (Vector((cx, top, cz)), top)]
        bld.tube(path, r, 8, "pipe_paint", detail=1, caps=False)
        for y in (0.35, 2.0, 4.0, 6.0, 8.0):
            if y < top - 0.4:
                bld.collar(Vector((cx, y, cz)), (0, 1, 0), r * 1.4, 0.05, 8)
        bld.box((cx, 0.02, cz), (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.09, 0.02, 0.09, detail=2)


def ceiling_runs(bld, doc, zone, rng):
    h = zone["height"]; cs = doc["cs"]
    cellset = set(zone["cells"])
    cols = [c for c, _ in zone["cells"]]; rows = [r for _, r in zone["cells"]]
    along_x = (max(cols) - min(cols)) >= (max(rows) - min(rows))
    count = 3 if h >= 9 else rng.choice([0, 1, 1, 2])
    if count == 0:
        return
    lines = []
    if along_x:
        for row in range(min(rows), max(rows)):
            span = [c for c in range(min(cols), max(cols) + 1) if (c, row) in cellset and (c, row + 1) in cellset]
            if len(span) >= 3:
                x0, _ = corner(doc, min(span), row); x1 = corner(doc, max(span), row)[0] + cs
                z = corner(doc, min(span), row)[1]
                lines.append(("x", z, x0, x1))
    else:
        for col in range(min(cols), max(cols)):
            span = [r for r in range(min(rows), max(rows) + 1) if (col, r) in cellset and (col + 1, r) in cellset]
            if len(span) >= 3:
                x = corner(doc, col + 1, min(span))[0]
                zs = [corner(doc, col, r)[1] for r in span]
                lines.append(("z", x, min(zs), max(zs) + cs))
    rng.shuffle(lines)
    for i, (axis, c, a0, a1) in enumerate(lines[:count]):
        tier = "XL" if h >= 9 and i < 2 else rng.choice(["L", "M"])
        r = TIERS[tier]
        y = h - 0.62 - r - (0.5 if h >= 9 else 0.0) - 0.15 * i
        inset = 1.0 + 0.3 * i
        P = (lambda s, yy: Vector((s, yy, c))) if axis == "x" else (lambda s, yy: Vector((c, yy, s)))
        pts = [P(a0 + inset, h), P(a0 + inset, y), P(a1 - inset, y), P(a1 - inset, h)]
        path = rounded(pts, max(0.4, 2.5 * r), False)
        bld.tube(path, r, SIDES[tier], PIPE_STRIP[tier], detail=1, caps=False)
        pipe_details(bld, path, r, tier, True, rng, True, cs)
        s = a0 + inset + 2.0
        while s < a1 - inset - 1.0:
            q = P(s, y)
            top = h - 0.5
            bld.box(Vector((q.x, (y + r + top) / 2, q.z)), (1, 0, 0), (0, 1, 0), (0, 0, 1), 0.02, (top - y - r) / 2, 0.02, detail=2)
            bld.collar(q, (1, 0, 0) if axis == "x" else (0, 0, 1), r * 1.12, 0.07, SIDES[tier])
            s += cs


# ───────────────────────── Blender の物へ ─────────────────────────
def to_object(bld, name, mats):
    bm = bld.bm
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    for e in bm.edges:
        if any(not f.smooth for f in e.link_faces) or len(e.link_faces) != 2:
            e.smooth = False
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for key in ("hull", "strip", "lamp"):
        me.materials.append(mats[key])
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def select_only(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]


def lightmap_area(ob):
    me = ob.data
    det = me.attributes.get("detail")
    w = {0: 1.0, 1: 0.6, 2: 0.4}
    a = 0.0
    for poly in me.polygons:
        k = w.get(det.data[poly.index].value, 1.0) if det else 1.0
        a += poly.area * k * k
    return a


def unwrap_lightmap(ob, size):
    me = ob.data
    if "Lightmap" not in me.uv_layers:
        me.uv_layers.new(name="Lightmap")
    det = me.attributes.get("detail")
    scale = {0: 1.0, 1: 0.6, 2: 0.4}
    vscale = {}
    for poly in me.polygons:
        k = scale.get(det.data[poly.index].value, 1.0) if det else 1.0
        for vi in poly.vertices:
            vscale[vi] = max(vscale.get(vi, 0.0), k)
    orig = [v.co.copy() for v in me.vertices]
    for v in me.vertices:
        v.co = v.co * vscale.get(v.index, 1.0)
    me.uv_layers.active = me.uv_layers["Lightmap"]
    select_only([ob])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(50), island_margin=0.0, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    margin = LM_GAP_PX / (2.0 * size)
    try:
        bpy.ops.uv.pack_islands(rotate=True, rotate_method="CARDINAL", margin=margin, margin_method="FRACTION", shape_method="AABB")
    except TypeError:
        bpy.ops.uv.pack_islands(rotate=True, margin=margin, margin_method="FRACTION")
    bpy.ops.object.mode_set(mode="OBJECT")
    for v, co in zip(me.vertices, orig):
        v.co = co
    me.uv_layers.active = me.uv_layers["UVMap"]
    me.uv_layers["UVMap"].active_render = True
    uvs = np.empty(len(me.loops) * 2, np.float32)
    me.uv_layers["Lightmap"].data.foreach_get("uv", uvs)
    uvs = uvs.reshape(-1, 2)
    return float(uvs.min()), float(uvs.max())


def lm_size_for(area):
    for s in (512, 1024, 2048):
        if s * s * 0.55 / max(area, 1.0) >= LM_PX_PER_M ** 2:
            return s
    return 2048


# ───────────────────────── ベイク ─────────────────────────
def setup_cycles(samples):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        prefs.compute_device_type = "METAL"
        prefs.get_devices()
        for d in prefs.devices:
            d.use = True
        sc.cycles.device = "GPU"
    except Exception as ex:
        print("GPU が使えないので CPU:", ex)
    sc.cycles.samples = samples
    sc.cycles.use_denoising = False
    sc.cycles.max_bounces = 4
    sc.cycles.diffuse_bounces = 3
    sc.cycles.glossy_bounces = 0
    sc.cycles.transmission_bounces = 0
    sc.cycles.transparent_max_bounces = 0
    sc.cycles.sample_clamp_indirect = 4.0
    w = bpy.data.worlds.new("W") if not sc.world else sc.world
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.0


def add_bake_lights(lamps, look):
    col_room = hex_lin(look["roomLightColor"])
    col_strip = hex_lin(look["stripColor"])
    col_corr = tuple(0.75 * a + 0.25 * b for a, b in zip(col_room, col_strip))
    objs = []
    for lp in lamps:
        if lp["kind"] == "wall":
            pd = bpy.data.lights.new("W", "POINT")
            pd.energy = 120.0
            pd.shadow_soft_size = 0.15
            pd.color = col_room
            po = bpy.data.objects.new("BAKE_LIGHT", pd)
            po.location = B(lp["pos"])
            bpy.context.scene.collection.objects.link(po)
            objs.append(po)
            continue
        ld = bpy.data.lights.new("L", "AREA")
        ld.shape = "SQUARE"
        ld.size = lp["size"]
        ld.energy = 3600.0 if lp["room"] else 300.0
        ld.color = col_room if lp["room"] else col_corr
        ob = bpy.data.objects.new("BAKE_LIGHT", ld)
        ob.location = B(lp["pos"])
        bpy.context.scene.collection.objects.link(ob)
        objs.append(ob)
        # WhyNot: 下向きの面の光だけにしない — 壁の上半分と天井際のパイプが真っ暗になる（灯具の横へ漏れる光の代わり）
        pd = bpy.data.lights.new("P", "POINT")
        pd.energy = 1000.0 if lp["room"] else 90.0
        pd.shadow_soft_size = 0.4
        pd.color = ld.color
        po = bpy.data.objects.new("BAKE_LIGHT", pd)
        x, y, z = lp["pos"]
        po.location = B((x, y - (0.7 if lp["room"] else 0.35), z))
        bpy.context.scene.collection.objects.link(po)
        objs.append(po)
    return objs


def set_bake_image(mats, img):
    for m in mats.values():
        nt = m.node_tree
        nd = nt.nodes.get("BAKE_TARGET") or nt.nodes.new("ShaderNodeTexImage")
        nd.name = "BAKE_TARGET"
        nd.image = img
        for n in nt.nodes:
            n.select = False
        nd.select = True
        nt.nodes.active = nd


def bake_zone(ob, mats, size, samples):
    img = bpy.data.images.new("LM_" + ob.name, size, size, alpha=False, float_buffer=True)
    set_bake_image(mats, img)
    ob.data.uv_layers.active = ob.data.uv_layers["Lightmap"]
    select_only([ob])
    sc = bpy.context.scene
    sc.cycles.samples = samples
    bk = sc.render.bake
    bk.margin = max(8, size // 64)
    bk.margin_type = "EXTEND"
    bk.use_clear = True
    bk.target = "IMAGE_TEXTURES"
    bk.use_pass_direct = True
    bk.use_pass_indirect = True
    bk.use_pass_color = False
    t0 = time.time()
    res = bpy.ops.object.bake(type="DIFFUSE", pass_filter={"DIRECT", "INDIRECT"}, margin=bk.margin, margin_type="EXTEND",
                              use_clear=True, target="IMAGE_TEXTURES")
    print("  bake %s %d spp=%d %.1fs %s" % (ob.name, size, samples, time.time() - t0, res))
    ob.data.uv_layers.active = ob.data.uv_layers["UVMap"]
    return img


def save_lightmap(img, path):
    w, h = img.size
    a = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(a)
    a = a.reshape(h, w, 4)[:, :, :3].astype(np.float64)
    blur = a.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx or dy:
                blur += np.roll(np.roll(a, dy, 0), dx, 1)
    lin = blur / 9.0 + np.array(AMBIENT)
    stats = {"p50": float(np.median(lin.mean(-1))), "p95": float(np.percentile(lin.mean(-1), 95)),
             "clipped_pct": float((lin.max(-1) * PNG_SCALE > 1.0).mean() * 100)}
    v = np.clip(lin * PNG_SCALE, 0, 1)
    srgb = np.where(v <= 0.0031308, v * 12.92, 1.055 * np.power(v, 1 / 2.4) - 0.055)
    out = np.concatenate([srgb, np.ones((h, w, 1))], -1).astype(np.float32)
    im = bpy.data.images.new(os.path.basename(path), w, h, alpha=False)
    im.colorspace_settings.name = "Non-Color"
    im.pixels.foreach_set(out.ravel())
    im.filepath_raw = path
    im.file_format = "PNG"
    im.save()
    bpy.data.images.remove(im)
    return stats


# ───────────────────────── プレビュー ─────────────────────────
def preview_material(name, trim, lm_path):
    m = bpy.data.materials.new(name)
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    uv0 = nt.nodes.new("ShaderNodeUVMap"); uv0.uv_map = "UVMap"
    uv1 = nt.nodes.new("ShaderNodeUVMap"); uv1.uv_map = "Lightmap"
    tb = nt.nodes.new("ShaderNodeTexImage"); tb.image = trim
    nt.links.new(uv0.outputs[0], tb.inputs[0])
    mul = nt.nodes.new("ShaderNodeMix"); mul.data_type = "RGBA"; mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    nt.links.new(tb.outputs["Color"], mul.inputs[6])
    if lm_path and os.path.exists(lm_path):
        tl = nt.nodes.new("ShaderNodeTexImage"); tl.image = bpy.data.images.load(lm_path)
        tl.image.colorspace_settings.name = "sRGB"
        nt.links.new(uv1.outputs[0], tl.inputs[0])
        nt.links.new(tl.outputs["Color"], mul.inputs[7])
        em.inputs["Strength"].default_value = 1.0 / PNG_SCALE
    else:
        mul.inputs[7].default_value = (0.6, 0.6, 0.6, 1)
    nt.links.new(mul.outputs[2], em.inputs["Color"])
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


def glow_preview(src):
    p = src.node_tree.nodes.get("Principled BSDF")
    col = p.inputs["Emission Color"].default_value
    s = p.inputs["Emission Strength"].default_value
    m = bpy.data.materials.new(src.name + "_pv")
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = col
    em.inputs["Strength"].default_value = s * 0.5
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


def render_previews(doc, eye, fov, shots, zones_built):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.samples = 24
    sc.cycles.max_bounces = 0
    sc.cycles.use_denoising = False
    sc.render.resolution_x, sc.render.resolution_y = 960, 540
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0.0
    try:
        sc.view_settings.view_transform = "AgX"
        sc.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        pass
    cam_d = bpy.data.cameras.new("CAM")
    cam_d.sensor_fit = "VERTICAL"
    cam_d.angle_y = math.radians(fov)
    cam_d.clip_start = 0.05
    cam_d.clip_end = 200
    cam = bpy.data.objects.new("CAM", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    paths = []
    for name, (col, row), yaw, pitch in shots:
        x, z = center(doc, col, row)
        if not any(char_at(doc, col, row) == zid for zid in zones_built):
            continue
        cam.location = B((x, eye, z))
        d = Vector((math.sin(math.radians(yaw)), 0, math.cos(math.radians(yaw))))
        bd = Bdir(d)
        theta = math.atan2(-bd.x, bd.y)
        cam.rotation_euler = (math.radians(90 + pitch), 0, theta)
        p = os.path.join(DEBUG, "stage_%s.png" % name)
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        paths.append(p)
    return paths


# ───────────────────────── 書き出し ─────────────────────────
def export(objs, path):
    select_only(objs)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=False, export_texcoords=True, export_normals=True, export_tangents=False,
                              export_materials="EXPORT", export_image_format="AUTO", export_cameras=False,
                              export_lights=False, export_extras=False)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--zones", default="")
    ap.add_argument("--samples", type=int, default=192)
    ap.add_argument("--skip-bake", action="store_true")
    ap.add_argument("--no-preview", action="store_true")
    a = ap.parse_args(argv)
    t_all = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(LM_DIR, exist_ok=True)
    os.makedirs(DEBUG, exist_ok=True)
    doc = load_doc()
    look = json.load(open(LOOK_PATH))
    walk = json.load(open(WALK_PATH))
    h16 = stagehash.doc_hash(doc["json"])
    only = [z for z in a.zones.split(",") if z] or sorted(doc["zones"].keys())
    trim = make_trim(TRIM_PATH)
    mats = make_materials(trim, look)

    built = {}
    all_lamps = []
    for zid in sorted(doc["zones"].keys()):
        zone = doc["zones"][zid]
        rng = random.Random("zone-" + zid)
        bld, lamps = build_zone(doc, zone, look, rng)
        ob = to_object(bld, "ZONE_" + zid, mats)
        all_lamps += lamps
        built[zid] = ob
    targets = {z: built[z] for z in only}
    info = {}
    for zid, ob in targets.items():
        area = lightmap_area(ob)
        size = lm_size_for(area)
        lo, hi = unwrap_lightmap(ob, size)
        info[zid] = {"size": size, "area": area, "uv_range": (lo, hi)}
        print("zone %s: tris=%d area=%.0f lm=%d uv=[%.3f, %.3f]" % (zid, sum(len(p.vertices) - 2 for p in ob.data.polygons), area, size, lo, hi))

    lm_files = {}
    stats = {}
    if not a.skip_bake:
        setup_cycles(a.samples)
        lights = add_bake_lights(all_lamps, look)
        strip_p = mats["strip"].node_tree.nodes.get("Principled BSDF")
        lamp_p = mats["lamp"].node_tree.nodes.get("Principled BSDF")
        keep = (strip_p.inputs["Emission Strength"].default_value, lamp_p.inputs["Emission Strength"].default_value)
        strip_p.inputs["Emission Strength"].default_value = 14.0
        lamp_p.inputs["Emission Strength"].default_value = 0.0
        for zid, ob in targets.items():
            img = bake_zone(ob, mats, info[zid]["size"], a.samples)
            fn = "zone_%02x_%s.png" % (ord(zid), zid)
            p = os.path.join(LM_DIR, fn)
            stats[zid] = save_lightmap(img, p)
            lm_files[zid] = os.path.relpath(p, OUT)
            print("  lightmap %s %s" % (fn, stats[zid]))
        strip_p.inputs["Emission Strength"].default_value, lamp_p.inputs["Emission Strength"].default_value = keep
        for m in mats.values():
            nd = m.node_tree.nodes.get("BAKE_TARGET")
            if nd:
                m.node_tree.nodes.remove(nd)
        for l in lights:
            bpy.data.objects.remove(l, do_unlink=True)

    empty = bpy.data.objects.new("DOCHASH_" + h16, None)
    bpy.context.scene.collection.objects.link(empty)
    full = len(only) == len(doc["zones"])
    glb = os.path.join(OUT, "stage.glb" if full else "stage_try.glb")
    export(list(targets.values()) + [empty], glb)
    print("exported", glb, os.path.getsize(glb))

    manifest_path = os.path.join(OUT, "stage.manifest.json" if full else "stage_try.manifest.json")
    zones_out = {}
    for zid, ob in targets.items():
        mats_used = sorted({ob.data.materials[p.material_index].name for p in ob.data.polygons})
        zones_out[zid] = {"node": ob.name, "name": doc["zones"][zid]["name"], "kind": doc["zones"][zid]["kind"],
                          "triangles": sum(len(p.vertices) - 2 for p in ob.data.polygons), "materials": mats_used,
                          "lightmap_png": lm_files.get(zid), "lightmap_size": info[zid]["size"],
                          "uv_gap_px": LM_GAP_PX, "lightmap_stats": stats.get(zid)}
    manifest = {
        "version": 1,
        "title": "ステージの絵の書き出し",
        "note": "modeling/stage.py の生成物（手で直さない・直すなら stage.py を流し直す）。区画ごとのノード名・lightmap の絵と大きさ・三角形・材質と、lightmap の読み方（intensity・mip のレベル）をゲームへ渡す。doc_hash が今の maze.stage.json と違えば絵が古い。",
        "glb": os.path.basename(glb),
        "doc": "assets/maze.stage.json",
        "doc_hash": h16,
        "doc_hash_rule": stagehash.RULE,
        "coords": "engine Scene3d coords (X east, Y up, Z north, floor top y = 0) after the engine reads the glb; cell (col,row) spans x [col*cs,(col+1)*cs), z [(rows-1-row)*cs,(rows-row)*cs) like src/Maze.flix",
        "uv0": "M_hull: trim sheet (embedded PNG, REPEAT in U)",
        "uv1": "lightmap (TEXCOORD_1), one PNG per zone",
        "lightmap_encoding": "png = srgb_encode(clamp(%.2f * linear, 0, 1)) + ambient %s already added; use Scene3d.lightmap intensity %.1f (x exposure if wanted)" % (PNG_SCALE, list(AMBIENT), 1.0 / PNG_SCALE),
        "lightmap_mip_levels": "island gap %d px -> Scene3d.lightmapLevelsForGap(%d)" % (LM_GAP_PX, LM_GAP_PX),
        "baked_lights": "ceiling lamps (area lights) + cyan strips (M_strip emission). Do not add these as pointLights in the game.",
        "emission": {"M_strip": 6.0, "M_lamp": 3.0},
        "zones": zones_out,
    }
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)

    if not a.no_preview:
        for zid, ob in built.items():
            lm = os.path.join(OUT, lm_files[zid]) if zid in lm_files else None
            ob.data.materials[0] = preview_material("PV_" + zid, trim, lm)
            ob.data.materials[1] = glow_preview(mats["strip"])
            ob.data.materials[2] = glow_preview(mats["lamp"])
        shots = [
            ("corridor_long", (38, 23), 0.0, 0.0),
            ("corner", (35, 34), 90.0, 0.0),
            ("corner_turn", (37, 34), 35.0, 6.0),
            ("start_room", (3, 34), 90.0, 0.0),
            ("corridor_a", (9, 34), 90.0, 0.0),
            ("hive_entry", (18, 11), 20.0, 4.0),
            ("hive_center", (24, 6), 80.0, 6.0),
            ("hive_back", (36, 9), -100.0, 3.0),
        ]
        paths = render_previews(doc, float(walk["eyeHeight"]), float(walk["fovY"]), shots, list(targets.keys()))
        print("previews", paths)
    print("DONE %.0fs hash=%s" % (time.time() - t_all, h16))


main()
