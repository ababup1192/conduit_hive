# 色の光を出す物（look の fixtures）の形と、動かない物の光（stage.py が呼ぶ）。
#   exit    = 非常口の扉の上の灯り（扉の上の壁に光る板・扉と床の手前だけを赤く照らす点光源をベイク）
#   panel   = 制御盤・端末（床に立つ箱と光る画面・盤の前をほんのり色づける点光源をベイク）
#   tank    = 薬品のタンク（鋼の筒と光る帯の窓・まわりを色づける点光源をベイク）
#   hydrant = 消火栓・非常ボタン（壁の小さな箱と小さな灯り・弱い点光源をベイク）
#   beacon  = 警告の回転灯の腕（光る灯と回る光はゲームの FixtureLights が毎コマ足す）
#   flicker = 壊れた蛍光灯の枠（管と明滅する光はゲームの FixtureLights が毎コマ足す）
# 置き場所: マス（x = 列・y = 行）の、side の壁（n = 北 = engine の +z・e = 東 = +x）の真ん中から内へ寄せた点。
# ゲームの src/FixtureLights.flix と同じ決め方（回転灯の灯は高さ 2.5 m・壁から 0.24 m、蛍光灯の管は天井から 0.14 m 下・壁から 1.0 m）。
DIRS = {"n": (0.0, 1.0), "s": (0.0, -1.0), "e": (1.0, 0.0), "w": (-1.0, 0.0)}

# 動かない物の光（Blender の点光源の W・光の大きさ m・高さ m）
BAKE = {"exit": (420.0, 0.3, 4.4), "panel": (70.0, 0.5, 1.15), "tank": (140.0, 0.6, 1.2), "hydrant": (25.0, 0.2, 1.25)}


def color_key(hexcol):
    return "fx_" + hexcol.lstrip("#").lower()


def frame(doc, f, center_fn):
    """物の取り付けの点: 壁の真ん中（x・z）・内へ向く向き・壁に沿う向き。"""
    cx, cz = center_fn(doc, f["x"], f["y"])
    dx, dz = DIRS[f["side"]]
    cs = doc["cs"]
    wall = (cx + dx * cs / 2, cz + dz * cs / 2)
    inward = (-dx, -dz)
    along = (dz, -dx)
    return wall, inward, along


def at(wall, inward, out, y):
    return (wall[0] + inward[0] * out, y, wall[1] + inward[1] * out)


def build(bld, doc, zone, fixtures, center_fn):
    """区画 zone の物の形を bld へ組み、ベイクする光の並び [{"pos", "color", "energy", "radius"}] を返す。"""
    lights = []
    cellset = set(zone["cells"])
    for f in fixtures:
        if (f["x"], f["y"]) not in cellset:
            continue
        wall, n, t = frame(doc, f, center_fn)
        ax, az = (t[0], 0.0, t[1]), (n[0], 0.0, n[1])
        up = (0.0, 1.0, 0.0)
        key = color_key(f["color"])
        kind = f["kind"]
        if kind == "exit":
            # 扉の枠の上の梁（高さ 4.5 m ほどまで・手前へ出る）に隠れないよう、梁の上へ出して手前へ張り出す
            c = at(wall, n, 0.2, 4.95)
            bld.box(c, ax, up, az, 0.55, 0.2, 0.2, strip="trim", detail=2)
            front = at(wall, n, 0.405, 4.95)
            face(bld, front, t, 0.40, 0.12, n, key)
        elif kind == "panel":
            c = at(wall, n, 0.2, 0.8)
            bld.box(c, ax, up, az, 0.7, 0.8, 0.2, strip="trim", detail=2)
            face(bld, at(wall, n, 0.405, 1.2), t, 0.45, 0.24, n, key)
            face(bld, at(wall, n, 0.405, 0.75), t, 0.3, 0.05, n, key)
        elif kind == "tank":
            c = at(wall, n, 0.85, 0.0)
            bld.tube([((c[0], 0.0, c[2]), 0.0), ((c[0], 2.4, c[2]), 2.4)], 0.55, 14, "pipe_steel", detail=1)
            bld.tube([((c[0], 0.95, c[2]), 0.0), ((c[0], 1.45, c[2]), 0.5)], 0.565, 14, "trim", detail=1, caps=False, mat=key)
            bld.box((c[0], 2.45, c[2]), (1, 0, 0), up, (0, 0, 1), 0.3, 0.06, 0.3, strip="trim", detail=2)
        elif kind == "hydrant":
            c = at(wall, n, 0.1, 1.0)
            bld.box(c, ax, up, az, 0.25, 0.35, 0.1, strip="hazard", detail=2)
            face(bld, at(wall, n, 0.205, 1.25), t, 0.06, 0.06, n, key)
        elif kind == "beacon":
            bld.box(at(wall, n, 0.06, 2.5), ax, up, az, 0.1, 0.1, 0.06, strip="trim", detail=2)
            bld.box(at(wall, n, 0.14, 2.32), ax, up, az, 0.03, 0.08, 0.1, strip="trim", detail=2)
        elif kind == "flicker":
            h = zone["height"]
            c = at(wall, n, 1.0, h - 0.06)
            hx, hz = (0.65, 0.1) if abs(t[0]) > 0.5 else (0.1, 0.65)
            bld.box(c, (1, 0, 0), up, (0, 0, 1), hx, 0.05, hz, strip="trim", detail=2, skip=("+y",))
        if kind in BAKE:
            energy, radius, y = BAKE[kind]
            out = {"exit": 0.8, "panel": 0.7, "tank": 1.55, "hydrant": 0.35}[kind]
            lights.append({"pos": at(wall, n, out, y), "color": f["color"], "energy": energy, "radius": radius})
    return lights


def face(bld, center, t, hw, hh, n, key):
    """壁に沿った光る矩形（真ん中 center・幅の半分 hw・高さの半分 hh・内向き n）。"""
    x, y, z = center
    p = lambda a, b: (x + t[0] * a, y + b, z + t[1] * a)
    pts = [p(-hw, -hh), p(hw, -hh), p(hw, hh), p(-hw, hh)]
    bld.quad_strip(pts, "trim", 0.0, 1.0, normal=(n[0], 0.0, n[1]), mat=key, detail=2)


def puddle_spots(doc, zone, fixtures, center_fn):
    """色の灯りの前の床（水たまりを置くと映える所）: [(マス, x, z)]。"""
    out = []
    cellset = set(zone["cells"])
    for f in fixtures:
        if (f["x"], f["y"]) not in cellset or f["kind"] in ("flicker",):
            continue
        wall, n, _ = frame(doc, f, center_fn)
        d = 1.5 if f["kind"] != "tank" else 2.0
        out.append(((f["x"], f["y"]), wall[0] + n[0] * d, wall[1] + n[1] * d))
    return out
