# stage.glb の中身を出して、マス目と合っているか確かめる（Blender は要らない）:
#   cd modeling && devbox run -- blender -b --factory-startup --python stage_check.py   （numpy を Blender の python から借りる）
# 出す物: 区画ごとのノード・三角形・材質（= draw call）・lightmap の絵の大きさ・場面の絵の予算・DOCHASH と今の Doc の一致。
# 確かめる物: 区画の頂点が全部その区画の床のマスの上（壁のマス・ほかの区画へはみ出さない）・高さが 0〜天井。
import json, struct, os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import stagehash
ROOT = os.path.normpath(os.path.join(HERE, ".."))
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
GLB = os.path.join(ROOT, "assets", "models", ARGS[0] if ARGS else "stage.glb")
MANIFEST = GLB.replace(".glb", ".manifest.json")
DOC = os.path.join(ROOT, "assets", "maze.stage.json")


def read_glb(path):
    data = open(path, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + jlen])
    rest = data[20 + jlen:]
    blen = struct.unpack("<I", rest[:4])[0]
    return doc, rest[8:8 + blen]


def accessor(doc, bin_, k):
    a = doc["accessors"][k]
    bv = doc["bufferViews"][a["bufferView"]]
    comps = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
    dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[a["componentType"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    return np.frombuffer(bin_, dt, a["count"] * comps, off).reshape(a["count"], comps)


def png_size(b):
    return struct.unpack(">II", b[16:24]) if b[:8] == b"\x89PNG\r\n\x1a\n" else None


raw = open(DOC, "rb").read()
d = json.loads(raw)
stagehash.check_shape(d)
rows = d["rows"]; cols = max(map(len, rows)); nrows = len(rows); cs = d["cellSize"]
grid = [r.ljust(cols, "#") for r in rows]
heights = {z["id"]: z["height"] for z in d["zones"]}
want_hash = stagehash.doc_hash(d)

doc, bin_ = read_glb(GLB)
man = json.load(open(MANIFEST)) if os.path.exists(MANIFEST) else {"zones": {}}
print("== %s  %.1f MB" % (os.path.basename(GLB), os.path.getsize(GLB) / 1e6))
hash_nodes = [n["name"] for n in doc["nodes"] if n.get("name", "").startswith("DOCHASH_")]
print("DOCHASH ノード:", hash_nodes, " 今の Doc:", want_hash, " 一致" if hash_nodes == ["DOCHASH_" + want_hash] else " 不一致")
for im in doc.get("images", []):
    bv = doc["bufferViews"][im["bufferView"]]
    b = bin_[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
    print("埋めた絵:", im.get("name"), png_size(b))
mats = [m.get("name") for m in doc.get("materials", [])]
print("材質:", mats)

total_tris = 0; total_calls = 0; bad = []
gpu_mb = 0.0
print("%-8s %-8s %8s %5s  %-28s %s" % ("node", "name", "tris", "calls", "materials", "lightmap"))
for n in doc["nodes"]:
    if "mesh" not in n or not n["name"].startswith("ZONE_"):
        continue
    for k in ("translation", "rotation", "scale", "matrix"):
        if k in n:
            bad.append("%s に %s がある（形は原点のまま置く前提）" % (n["name"], k))
    zid = n["name"][5:]
    tris = 0; used = []
    pts = []
    for p in doc["meshes"][n["mesh"]]["primitives"]:
        tris += doc["accessors"][p["indices"]]["count"] // 3
        used.append(mats[p["material"]] if "material" in p else "-")
        if "TEXCOORD_1" not in p["attributes"]:
            bad.append("%s/%s に TEXCOORD_1 が無い" % (n["name"], used[-1]))
        pts.append(accessor(doc, bin_, p["attributes"]["POSITION"]))
    P = np.concatenate(pts).astype(np.float64)
    ex, ey, ez = -P[:, 0], P[:, 1], P[:, 2]   # glb → engine の座標
    def on_floor(eps):
        ok = np.zeros(len(P), bool)
        for dx in (-eps, eps):
            for dz in (-eps, eps):
                c = np.floor((ex + dx) / cs).astype(int)
                r = nrows - 1 - np.floor((ez + dz) / cs).astype(int)
                inside = (c >= 0) & (c < cols) & (r >= 0) & (r < nrows)
                ch = np.array([grid[rr][cc] if ii else "#" for rr, cc, ii in zip(r, c, inside)])
                ok |= ch == zid
        return ok
    h = heights.get(zid, d["wallHeight"])
    # WhyNot: 2 mm の許しだけにしない — 腰の継ぎ目の溝は、わざと壁の面の 4 cm 奥にある（当たり判定の箱の中で、歩いて届かない）
    strict = on_floor(2e-3)
    ok = on_floor(0.045) & (ey > -2e-3) & (ey < h + 2e-3)
    behind = int((~strict & ok).sum())
    if not ok.all():
        q = np.stack([ex, ey, ez], 1)[~ok]
        bad.append("%s: 頂点 %d 個が区画の床のマスの外か高さの外（例 x,y,z = %s）" % (n["name"], (~ok).sum(), np.round(q[:2], 2).tolist()))
    z = man["zones"].get(zid, {})
    s = z.get("lightmap_size", 0)
    gpu_mb += s * s * 4 * 4 / 3 / 1e6
    total_tris += tris; total_calls += len(used)
    print("%-8s %-8s %8d %5d  %-28s %-34s 溝で壁の奥 %d 頂点" % (n["name"], z.get("name", ""), tris, len(used), ",".join(used),
                                          "%s %d²" % (z.get("lightmap_png"), s) if s else "-", behind))
gpu_mb += 2048 * 2048 * 4 * 4 / 3 / 1e6
print("合計: 三角形 %d・draw call %d（全区画）・場面の絵 %.0f MB（lightmap %d 枚 + trim 1 枚・mip 込み・RGBA8）"
      % (total_tris, total_calls, gpu_mb, len([1 for z in man["zones"].values() if z.get("lightmap_size")]), ))
print("はみ出し・欠け:", bad or "なし")
