# 敵のクリーチャー（骨つき）を組んで assets/models/creature_<種>.glb へ書き出す。
#   cd modeling && devbox run -- blender -b --factory-startup --python creature.py -- melee|ranged [--nobake]
# 座標は Blender の Z が上・正面は -Y・.L は +X・原点は足元の真ん中（engine では +Z が前・+Y が上）。
# クリップ: idle・walk（ループ）・attack・hit・die（最後のコマで止める）。足は場所の上で動く（原点は進まない）。
import bpy, os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mathutils import Vector, Matrix
import vmlib as V
import creaturelib as C
from creaturelib import sweep, blob, spike, mix

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
KIND = next((a for a in args if a in ("melee", "ranged")), "melee")
NOBAKE = "--nobake" in args
F = V.FPS


def mirror(spec):
    """左右を入れ替えた姿勢（.L と .R を入れ替え・X の向きの移動と Y・Z まわりの回しを反転）。"""
    out = {}
    for name, s in spec.items():
        n = name[:-2] + (".R" if name.endswith(".L") else ".L") if name[-2:] in (".L", ".R") else name
        o = {}
        if "r" in s:
            o["r"] = (s["r"][0], -s["r"][1], -s["r"][2])
        if "t" in s:
            o["t"] = (-s["t"][0], s["t"][1], s["t"][2])
        if "s" in s:
            o["s"] = s["s"]
        out[n] = o
    return out


def both(base, spec):
    """.L に spec・.R にその鏡。"""
    m = mirror({base + ".L": spec})
    return {base + ".L": spec, **m}


def merge(*specs):
    out = {}
    for s in specs:
        out.update(s)
    return out


def side_bones(rig, sx, L, sh, el, wr, hd, hp, kn, an, to, parent_arm, parent_leg):
    """片側の腕と脚の骨。sx = +1 で .L。座標は .L の側で書く。"""
    m = lambda p: (p[0] * sx, p[1], p[2])
    rig.bone("upperarm" + L, m(sh), m(el), parent_arm)
    rig.bone("forearm" + L, m(el), m(wr), "upperarm" + L)
    rig.bone("hand" + L, m(wr), m(hd), "forearm" + L)
    rig.bone("thigh" + L, m(hp), m(kn), parent_leg)
    rig.bone("shin" + L, m(kn), m(an), "thigh" + L)
    rig.bone("foot" + L, m(an), m(to), "shin" + L)


def mx(sx, p):
    return (p[0] * sx, p[1], p[2])


# ════════════════ melee: 痩せた前かがみの二足・膝まで届く長い腕の先に 3 本の鉤爪 ════════════════
def build_melee():
    rig = V.Rig("creature_melee")
    rig.bone("hips", (0, 0.02, 1.02), (0, 0.0, 1.20))
    rig.bone("spine", (0, 0.0, 1.20), (0, -0.07, 1.48), "hips")
    rig.bone("chest", (0, -0.07, 1.48), (0, -0.18, 1.72), "spine")
    rig.bone("neck", (0, -0.20, 1.72), (0, -0.30, 1.83), "chest")
    rig.bone("head", (0, -0.30, 1.83), (0, -0.50, 1.86), "neck")
    rig.bone("jaw", (0, -0.33, 1.80), (0, -0.50, 1.74), "head")
    for sx, L in ((1, ".L"), (-1, ".R")):
        side_bones(rig, sx, L, (0.22, -0.15, 1.66), (0.335, -0.10, 1.26), (0.38, -0.235, 0.84), (0.39, -0.29, 0.70),
                   (0.12, 0.02, 1.02), (0.16, -0.12, 0.57), (0.16, 0.07, 0.13), (0.16, -0.15, 0.02), "chest", "hips")

    parts = []
    H, S, CH, N, HD, J = "hips", "spine", "chest", "neck", "head", "jaw"
    # 胴: 細くくびれた腰から、前へ突き出した肩の塊へ。背の筋が光る
    parts.append((sweep([((0, 0.03, 0.90), 0.09, 0.07, {H: 1}, 0.0), ((0, 0.02, 1.01), 0.145, 0.105, {H: 1}, 0.1),
                         ((0, 0.01, 1.13), 0.135, 0.10, {H: 1}, 0.4), ((0, -0.01, 1.26), 0.105, 0.085, mix(H, S, 0.6), 0.6),
                         ((0, -0.05, 1.40), 0.14, 0.10, {S: 1}, 0.8), ((0, -0.10, 1.53), 0.19, 0.13, mix(S, CH, 0.6), 0.9),
                         ((0, -0.15, 1.64), 0.215, 0.14, {CH: 1}, 1.0), ((0, -0.20, 1.73), 0.165, 0.12, {CH: 1}, 0.8),
                         ((0, -0.25, 1.79), 0.08, 0.075, mix(CH, N, 0.5), 0.5), ((0, -0.30, 1.845), 0.062, 0.06, {N: 1}, 0.3)],
                        "flesh", sides=10), None))
    # 頭: 前へ伸びた楔。顔は無く、横に裂けた光る目が 2 対・下顎の内が光る
    parts.append((sweep([((0, -0.25, 1.86), 0.055, 0.055, {HD: 1}, 0.0), ((0, -0.32, 1.90), 0.085, 0.08, {HD: 1}, 0.4),
                         ((0, -0.41, 1.90), 0.078, 0.065, {HD: 1}, 0.6), ((0, -0.50, 1.865), 0.052, 0.045, {HD: 1}, 0.3),
                         ((0, -0.575, 1.83), 0.018, 0.016, {HD: 1}, 0.0)], "hide", sides=8, front=(0, 0, 1)), None))
    parts.append((sweep([((0, -0.30, 1.795), 0.055, 0.03, {J: 1}, 0.0), ((0, -0.42, 1.775), 0.055, 0.028, {J: 1}, 0.2),
                         ((0, -0.53, 1.765), 0.022, 0.016, {J: 1}, 0.0)], "hide", sides=6, front=(0, 0, 1)), None))
    parts.append((blob((0, -0.42, 1.812), (0.042, 0.085, 0.022), "glow", seg=8, rings=4), {HD: 1}))
    for sx in (1, -1):
        for (y, z, ln) in ((-0.37, 1.915, 0.034), (-0.455, 1.895, 0.026)):
            parts.append((blob((0.072 * sx * (1.0 if y > -0.4 else 0.85), y, z), (0.011, ln, 0.009), "glow", seg=6, rings=4), {HD: 1}))
    # 背の棘: 肩の塊から後ろ上へ
    for (y, z, bone, ln) in ((0.06, 1.40, S, 0.08), (0.03, 1.53, CH, 0.12), (-0.01, 1.64, CH, 0.13), (-0.08, 1.75, CH, 0.09)):
        parts.append((spike((0, y - 0.02, z), (0, y + ln, z + ln * 0.6), 0.03, "claw", sides=5, steps=2), {bone: 1}))
    for sx, L in ((1, ".L"), (-1, ".R")):
        UA, FA, HN, TH, SH, FT = "upperarm" + L, "forearm" + L, "hand" + L, "thigh" + L, "shin" + L, "foot" + L
        m = lambda p: mx(sx, p)
        # 腕: 細い上腕・光る筋の浮いた太い前腕
        parts.append((sweep([(m((0.19, -0.15, 1.69)), 0.07, 0.07, mix(CH, UA, 0.5), 0.2), (m((0.25, -0.15, 1.62)), 0.075, 0.07, {UA: 1}, 0.3),
                             (m((0.30, -0.12, 1.44)), 0.052, 0.048, {UA: 1}, 0.6), (m((0.335, -0.10, 1.26)), 0.044, 0.044, mix(UA, FA, 0.5), 0.3),
                             (m((0.35, -0.14, 1.12)), 0.058, 0.052, {FA: 1}, 0.9), (m((0.37, -0.19, 0.98)), 0.052, 0.046, {FA: 1}, 1.0),
                             (m((0.38, -0.235, 0.845)), 0.032, 0.03, mix(FA, HN, 0.5), 0.4)], "flesh", sides=8), None))
        parts.append((spike(m((0.335, -0.08, 1.26)), m((0.35, 0.10, 1.31)), 0.028, "claw", sides=5, steps=2), {FA: 1}))
        # 手: 平たい掌と、下へ伸びて前へ曲がる 3 本の鉤爪・内の短い爪
        parts.append((sweep([(m((0.38, -0.235, 0.86)), 0.034, 0.03, {HN: 1}, 0.2), (m((0.385, -0.265, 0.77)), 0.055, 0.028, {HN: 1}, 0.0),
                             (m((0.39, -0.29, 0.70)), 0.048, 0.022, {HN: 1}, 0.0)], "hide", sides=6, front=(1, 0, 0)), None))
        for dy, ln in ((0.035, 0.27), (0.0, 0.31), (-0.035, 0.27)):
            b = Vector(m((0.39, -0.29 + dy, 0.71)))
            parts.append((spike(b, b + Vector((0.004 * sx, -0.10 + dy * 0.6, -ln)), 0.02, "claw", sides=5, bend=(0, 0.05, 0), steps=4), {HN: 1}))
        parts.append((spike(m((0.36, -0.25, 0.77)), m((0.31, -0.33, 0.63)), 0.016, "claw", sides=5, bend=(0, 0.02, 0), steps=3), {HN: 1}))
        # 脚: 後ろへ折れたすね（つま先立ち）
        parts.append((sweep([(m((0.10, 0.02, 1.05)), 0.08, 0.08, mix(H, TH, 0.5), 0.2), (m((0.135, 0.0, 0.92)), 0.085, 0.085, {TH: 1}, 0.4),
                             (m((0.15, -0.06, 0.74)), 0.064, 0.064, {TH: 1}, 0.7), (m((0.16, -0.12, 0.57)), 0.05, 0.055, mix(TH, SH, 0.5), 0.3),
                             (m((0.16, -0.065, 0.40)), 0.048, 0.05, {SH: 1}, 0.8), (m((0.16, 0.02, 0.24)), 0.038, 0.04, {SH: 1}, 0.5),
                             (m((0.16, 0.07, 0.13)), 0.034, 0.034, mix(SH, FT, 0.5), 0.1)], "flesh", sides=8), None))
        parts.append((sweep([(m((0.16, 0.10, 0.075)), 0.034, 0.04, {FT: 1}, 0.0), (m((0.16, 0.04, 0.05)), 0.05, 0.045, {FT: 1}, 0.0),
                             (m((0.16, -0.08, 0.036)), 0.054, 0.034, {FT: 1}, 0.0), (m((0.16, -0.16, 0.022)), 0.03, 0.02, {FT: 1}, 0.0)],
                            "hide", sides=6, front=(0, 0, 1)), None))
        for dx in (-0.025, 0.025):
            parts.append((spike(m((0.16 + dx, -0.15, 0.03)), m((0.16 + dx * 1.6, -0.23, 0.004)), 0.014, "claw", sides=4, steps=2), {FT: 1}))
    return rig, parts


def clips_melee():
    lean = {"spine": {"r": (14, 0, 0)}, "chest": {"r": (6, 0, 0)}, "neck": {"r": (-10, 0, 0)}, "head": {"r": (-10, 0, 0)}}
    idle = [(0, {}),
            (30, {"chest": {"r": (3, 0, 1.5)}, "head": {"r": (-4, 0, 4)}, "jaw": {"r": (5, 0, 0)}, "hips": {"t": (0, 0, -0.012)},
                  **both("upperarm", {"r": (-3, 0, 2)}), **both("forearm", {"r": (-4, 0, 0)})}),
            (60, {"chest": {"r": (-1, 0, 0)}, "head": {"r": (2, 0, -2)}, "spine": {"r": (2, 0, 0)}}),
            (90, {"chest": {"r": (3, 0, -1.5)}, "head": {"r": (-3, 0, -5)}, "jaw": {"r": (3, 0, 0)}, "hips": {"t": (0, 0, -0.01)},
                  **both("upperarm", {"r": (-2, 0, -1)})}),
            (120, {})]
    # 走り: 0.6 秒で左右 1 歩ずつ。f0 が左足の着地
    contact = merge(lean, {"hips": {"t": (0, 0, -0.07), "r": (0, 0, 7)}, "chest": {"r": (6, 0, -9)},
                           "thigh.L": {"r": (-32, 0, 0)}, "shin.L": {"r": (20, 0, 0)}, "foot.L": {"r": (12, 0, 0)},
                           "thigh.R": {"r": (26, 0, 0)}, "shin.R": {"r": (32, 0, 0)}, "foot.R": {"r": (-25, 0, 0)},
                           "upperarm.L": {"r": (22, 0, 6)}, "forearm.L": {"r": (-14, 0, 0)},
                           "upperarm.R": {"r": (-26, 0, -6)}, "forearm.R": {"r": (-30, 0, 0)}})
    passing = merge(lean, {"hips": {"t": (0, 0, 0.02)}, "chest": {"r": (8, 0, 0)},
                           "thigh.L": {"r": (6, 0, 0)}, "shin.L": {"r": (6, 0, 0)},
                           "thigh.R": {"r": (-30, 0, 0)}, "shin.R": {"r": (95, 0, 0)}, "foot.R": {"r": (-20, 0, 0)},
                           "upperarm.L": {"r": (4, 0, 4)}, "upperarm.R": {"r": (-6, 0, -4)}, **both("forearm", {"r": (-18, 0, 0)})})
    walk = [(0, contact), (9, passing), (18, mirror(contact)), (27, mirror(passing)), (36, contact)]
    # 振り下ろし: 両腕を頭の上へ溜めて、f30 で前の地面へ叩きつける
    wind = {"spine": {"r": (-10, 0, 0)}, "chest": {"r": (-12, 0, 0)}, "neck": {"r": (-6, 0, 0)}, "head": {"r": (-8, 0, 0)}, "jaw": {"r": (22, 0, 0)},
            "hips": {"t": (0, 0.03, -0.05)}, **both("thigh", {"r": (-14, 0, 0)}), **both("shin", {"r": (24, 0, 0)}), **both("foot", {"r": (-6, 0, 0)}),
            **both("upperarm", {"r": (-150, 0, -14)}), **both("forearm", {"r": (-45, 0, 0)}), **both("hand", {"r": (-20, 0, 0)})}
    slam = {"spine": {"r": (30, 0, 0)}, "chest": {"r": (16, 0, 0)}, "neck": {"r": (-18, 0, 0)}, "head": {"r": (-16, 0, 0)}, "jaw": {"r": (26, 0, 0)},
            "hips": {"t": (0, -0.06, -0.13)}, "thigh.L": {"r": (-40, 0, 0)}, "shin.L": {"r": (40, 0, 0)}, "foot.L": {"r": (2, 0, 0)},
            "thigh.R": {"r": (8, 0, 0)}, "shin.R": {"r": (40, 0, 0)}, "foot.R": {"r": (-30, 0, 0)},
            **both("upperarm", {"r": (-62, 0, 6)}), **both("forearm", {"r": (-8, 0, 0)}), **both("hand", {"r": (12, 0, 0)})}
    attack = [(0, {}), (16, V.lerp_spec(wind, {}, 0.15)), (24, wind), (30, slam), (36, V.lerp_spec(slam, {}, 0.1)), (54, {})]
    hit = [(0, {}), (4, {"spine": {"r": (-14, 0, 4)}, "chest": {"r": (-10, 0, 0)}, "head": {"r": (-18, 0, 8)}, "jaw": {"r": (18, 0, 0)},
                         "hips": {"t": (0, 0.04, -0.02)}, "upperarm.L": {"r": (22, 0, 18)}, "upperarm.R": {"r": (14, 0, -24)},
                         **both("forearm", {"r": (-25, 0, 0)})}), (15, {})]
    # 死ぬ: 膝が床へ落ち、膝を軸に前へ倒れ込んで、うつ伏せで止まる。
    # 腕は倒れる間ずっと胴より上に置く（手が先に床へ着くと、一番低い所をそろえる時に体が持ち上がって跳ねる）
    recoil = {"spine": {"r": (-14, 0, 0)}, "head": {"r": (-22, 0, 0)}, **both("upperarm", {"r": (20, 0, 14)}), "jaw": {"r": (22, 0, 0)}}
    kneel = {"hips": {"t": (0, 0.02, -0.5), "r": (10, 0, 0)}, "thigh.L": {"r": (-4, 0, 4)}, "thigh.R": {"r": (2, 0, -4)},
             **both("shin", {"r": (74, 0, 0)}), **both("foot", {"r": (80, 0, 0)}), "spine": {"r": (16, 0, 0)}, "chest": {"r": (6, 0, 0)},
             "head": {"r": (16, 0, 6)}, "jaw": {"r": (22, 0, 0)}, **both("upperarm", {"r": (-40, 0, 16)}), **both("forearm", {"r": (-75, 0, 0)}), **both("hand", {"r": (-20, 0, 0)})}
    tip = {"hips": {"t": (0, -0.1, -0.7), "r": (40, 0, -3)}, "thigh.L": {"r": (8, 0, 5)}, "thigh.R": {"r": (12, 0, -6)},
           **both("shin", {"r": (34, 0, 0)}), **both("foot", {"r": (80, 0, 0)}), "spine": {"r": (10, 0, 0)}, "chest": {"r": (2, 0, 0)},
           "neck": {"r": (-12, 0, 0)}, "head": {"r": (-6, 0, 20)}, "jaw": {"r": (24, 0, 0)},
           "upperarm.L": {"r": (-105, 0, 20)}, "forearm.L": {"r": (-30, 0, 0)}, "upperarm.R": {"r": (40, 0, -40)}, "forearm.R": {"r": (-40, 0, 0)}}
    down = {"hips": {"t": (0, -0.22, -0.86), "r": (88, 0, -6)}, "thigh.L": {"r": (16, 0, 8)}, "thigh.R": {"r": (12, 0, -10)},
            "shin.L": {"r": (-12, 0, 0)}, "shin.R": {"r": (-6, 0, 0)}, **both("foot", {"r": (10, 0, 0)}), "spine": {"r": (-20, 0, 0)}, "chest": {"r": (-12, 0, 0)},
            "neck": {"r": (-14, 0, 0)}, "head": {"r": (-14, 0, 40)}, "jaw": {"r": (24, 0, 0)},
            "upperarm.L": {"r": (-150, 0, 22)}, "forearm.L": {"r": (10, 0, 0)}, "upperarm.R": {"r": (34, 0, -40)}, "forearm.R": {"r": (16, 0, 0)}}
    die = [(0, {}), (8, recoil), (14, V.lerp_spec(recoil, kneel, 0.4)), (19, V.lerp_spec(recoil, kneel, 0.8)), (24, kneel), (32, V.lerp_spec(kneel, tip, 0.25)), (40, tip),
           (44, V.lerp_spec(tip, down, 0.55)), (48, V.lerp_spec(down, tip, -0.04)), (56, V.lerp_spec(down, tip, 0.05)), (72, down)]
    return {"idle": idle, "walk": walk, "attack": attack, "hit": hit, "die": die}


# ════════════════ ranged: 背の低い太った二足・前へ垂れた光る喉の袋と、背の大きな袋 ════════════════
def build_ranged():
    rig = V.Rig("creature_ranged")
    rig.bone("hips", (0, 0.0, 0.84), (0, 0.0, 1.00))
    rig.bone("spine", (0, 0.0, 1.00), (0, -0.02, 1.24), "hips")
    rig.bone("chest", (0, -0.02, 1.24), (0, -0.05, 1.46), "spine")
    rig.bone("neck", (0, -0.06, 1.46), (0, -0.12, 1.55), "chest")
    rig.bone("head", (0, -0.12, 1.55), (0, -0.32, 1.57), "neck")
    rig.bone("jaw", (0, -0.14, 1.51), (0, -0.32, 1.47), "head")
    rig.bone("throat", (0, -0.10, 1.40), (0, -0.24, 1.32), "chest")
    for sx, L in ((1, ".L"), (-1, ".R")):
        side_bones(rig, sx, L, (0.25, -0.06, 1.40), (0.31, -0.13, 1.17), (0.27, -0.25, 1.04), (0.25, -0.31, 0.98),
                   (0.15, 0.0, 0.86), (0.22, -0.13, 0.48), (0.22, 0.07, 0.11), (0.22, -0.15, 0.02), "chest", "hips")
    parts = []
    H, S, CH, N, HD, J, T = "hips", "spine", "chest", "neck", "head", "jaw", "throat"
    parts.append((sweep([((0, 0.01, 0.76), 0.12, 0.10, {H: 1}, 0.0), ((0, 0.0, 0.86), 0.20, 0.16, {H: 1}, 0.2),
                         ((0, 0.0, 1.00), 0.235, 0.19, mix(H, S, 0.5), 0.3), ((0, -0.01, 1.14), 0.25, 0.205, {S: 1}, 0.4),
                         ((0, -0.02, 1.28), 0.245, 0.20, mix(S, CH, 0.6), 0.5), ((0, -0.03, 1.40), 0.21, 0.17, {CH: 1}, 0.5),
                         ((0, -0.05, 1.48), 0.14, 0.12, mix(CH, N, 0.5), 0.3), ((0, -0.09, 1.545), 0.10, 0.09, {N: 1}, 0.1)],
                        "hide", sides=12), None))
    # 頭: 平たく幅の広い頭。目は前の左右に 3 つずつの点
    parts.append((sweep([((0, -0.06, 1.57), 0.09, 0.07, {HD: 1}, 0.0), ((0, -0.14, 1.60), 0.125, 0.075, {HD: 1}, 0.3),
                         ((0, -0.24, 1.595), 0.115, 0.06, {HD: 1}, 0.4), ((0, -0.31, 1.57), 0.075, 0.04, {HD: 1}, 0.0),
                         ((0, -0.335, 1.555), 0.03, 0.02, {HD: 1}, 0.0)], "hide", sides=8, front=(0, 0, 1)), None))
    parts.append((sweep([((0, -0.11, 1.51), 0.10, 0.04, {J: 1}, 0.0), ((0, -0.23, 1.505), 0.10, 0.035, {J: 1}, 0.2),
                         ((0, -0.315, 1.51), 0.055, 0.022, {J: 1}, 0.0)], "hide", sides=8, front=(0, 0, 1)), None))
    parts.append((blob((0, -0.235, 1.535), (0.075, 0.075, 0.02), "glow", seg=8, rings=4), {HD: 1}))
    for sx in (1, -1):
        for k, (x, y, z) in enumerate(((0.085, -0.24, 1.625), (0.105, -0.205, 1.615), (0.115, -0.165, 1.625))):
            r = 0.016 - k * 0.002
            parts.append((blob((x * sx, y, z), (r, r, r), "glow", seg=6, rings=4), {HD: 1}))
    # 喉の袋: 吐く元。薄い膜ごと光る
    parts.append((blob((0, -0.19, 1.37), (0.135, 0.12, 0.13), "glow", seg=10, rings=6), {T: 1}))
    # 背の袋: 大きな膨らみ。筋が光る
    parts.append((blob((0, 0.17, 1.27), (0.19, 0.14, 0.23), "flesh", seg=10, rings=6, glow=1.0), mix(S, CH, 0.6)))
    parts.append((blob((0, 0.13, 1.52), (0.08, 0.07, 0.07), "flesh", seg=8, rings=5, glow=0.8), {CH: 1}))
    for (y, z, ln) in ((0.30, 1.38, 0.08), (0.28, 1.20, 0.07), (0.20, 1.50, 0.07)):
        parts.append((spike((0, y - 0.03, z), (0, y + ln, z + ln * 0.5), 0.025, "claw", sides=5, steps=2), mix(S, CH, 0.6)))
    for sx, L in ((1, ".L"), (-1, ".R")):
        UA, FA, HN, TH, SH, FT = "upperarm" + L, "forearm" + L, "hand" + L, "thigh" + L, "shin" + L, "foot" + L
        m = lambda p: mx(sx, p)
        # 腕: 胸の前に縮めた細い腕
        parts.append((sweep([(m((0.22, -0.05, 1.42)), 0.06, 0.06, mix(CH, UA, 0.5), 0.1), (m((0.27, -0.08, 1.32)), 0.05, 0.045, {UA: 1}, 0.4),
                             (m((0.31, -0.13, 1.17)), 0.036, 0.036, mix(UA, FA, 0.5), 0.2), (m((0.295, -0.20, 1.10)), 0.034, 0.032, {FA: 1}, 0.6),
                             (m((0.27, -0.25, 1.04)), 0.025, 0.024, mix(FA, HN, 0.5), 0.2)], "flesh", sides=6), None))
        for dx, ln in ((-0.018, 0.09), (0.018, 0.08)):
            b = Vector(m((0.27 + dx, -0.25, 1.04)))
            parts.append((spike(b, b + Vector((dx * sx, -0.06, -ln)), 0.013, "claw", sides=4, bend=(0, 0.015, 0), steps=2), {HN: 1}))
        # 脚: 太い腿・後ろへ折れたすね・幅の広い足
        parts.append((sweep([(m((0.12, 0.0, 0.92)), 0.11, 0.11, mix(H, TH, 0.5), 0.1), (m((0.17, -0.03, 0.80)), 0.12, 0.115, {TH: 1}, 0.3),
                             (m((0.20, -0.08, 0.64)), 0.09, 0.09, {TH: 1}, 0.5), (m((0.22, -0.13, 0.48)), 0.065, 0.068, mix(TH, SH, 0.5), 0.2),
                             (m((0.22, -0.06, 0.32)), 0.06, 0.06, {SH: 1}, 0.6), (m((0.22, 0.03, 0.18)), 0.05, 0.05, {SH: 1}, 0.4),
                             (m((0.22, 0.07, 0.115)), 0.045, 0.045, mix(SH, FT, 0.5), 0.0)], "flesh", sides=8), None))
        parts.append((sweep([(m((0.22, 0.10, 0.07)), 0.045, 0.05, {FT: 1}, 0.0), (m((0.22, 0.03, 0.055)), 0.07, 0.05, {FT: 1}, 0.0),
                             (m((0.22, -0.09, 0.04)), 0.075, 0.038, {FT: 1}, 0.0), (m((0.22, -0.16, 0.024)), 0.04, 0.022, {FT: 1}, 0.0)],
                            "hide", sides=6, front=(0, 0, 1)), None))
        for dx in (-0.04, 0.0, 0.04):
            parts.append((spike(m((0.22 + dx, -0.15, 0.03)), m((0.22 + dx * 1.4, -0.22, 0.004)), 0.014, "claw", sides=4, steps=2), {FT: 1}))
    return rig, parts


def clips_ranged():
    puff = lambda k: {"throat": {"s": (k, k, k)}}
    idle = [(0, {}),
            (30, merge(puff(1.08), {"chest": {"r": (-2, 0, 1)}, "head": {"r": (-3, 0, 3)}, "hips": {"t": (0, 0, -0.01)},
                                    **both("upperarm", {"r": (-4, 0, 0)})})),
            (60, merge(puff(0.97), {"chest": {"r": (1, 0, 0)}, "head": {"r": (2, 0, -1)}})),
            (90, merge(puff(1.1), {"chest": {"r": (-2, 0, -1)}, "head": {"r": (-2, 0, -4)}, "jaw": {"r": (5, 0, 0)}})),
            (120, {})]
    # 歩き: 1 秒で左右 1 歩ずつの重いよたよた歩き。f0 が左足の着地
    contact = {"hips": {"t": (0, 0, -0.04), "r": (0, -5, 6)}, "spine": {"r": (4, 6, -4)}, "chest": {"r": (0, -3, -4)},
               "head": {"r": (-4, 0, 0)}, "thigh.L": {"r": (-28, 0, 0)}, "shin.L": {"r": (14, 0, 0)}, "foot.L": {"r": (10, 0, 0)},
               "thigh.R": {"r": (22, 0, 0)}, "shin.R": {"r": (30, 0, 0)}, "foot.R": {"r": (-18, 0, 0)},
               "upperarm.L": {"r": (10, 0, 0)}, "upperarm.R": {"r": (-10, 0, 0)}, **puff(1.03)}
    passing = {"hips": {"t": (0, 0, 0.015), "r": (0, 0, 0)}, "spine": {"r": (4, 0, 0)},
               "thigh.L": {"r": (4, 0, 0)}, "shin.L": {"r": (4, 0, 0)},
               "thigh.R": {"r": (-22, 0, 0)}, "shin.R": {"r": (70, 0, 0)}, "foot.R": {"r": (-12, 0, 0)}, **puff(0.98)}
    walk = [(0, contact), (15, passing), (30, mirror(contact)), (45, mirror(passing)), (60, contact)]
    # 吐く: 後ろへ反って袋を膨らませ、f36 で首を突き出して吐く
    rear = merge(puff(1.35), {"spine": {"r": (-10, 0, 0)}, "chest": {"r": (-12, 0, 0)}, "neck": {"r": (-10, 0, 0)}, "head": {"r": (-14, 0, 0)},
                              "hips": {"t": (0, 0.03, -0.03)}, **both("thigh", {"r": (-10, 0, 0)}), **both("shin", {"r": (18, 0, 0)}),
                              **both("upperarm", {"r": (12, 0, 10)}), "jaw": {"r": (6, 0, 0)}})
    spit = merge(puff(0.82), {"spine": {"r": (12, 0, 0)}, "chest": {"r": (8, 0, 0)}, "neck": {"r": (12, 0, 0)}, "head": {"r": (-8, 0, 0)},
                              "jaw": {"r": (38, 0, 0)}, "hips": {"t": (0, -0.03, -0.05)}, "thigh.L": {"r": (-22, 0, 0)}, "shin.L": {"r": (24, 0, 0)},
                              "thigh.R": {"r": (6, 0, 0)}, "shin.R": {"r": (20, 0, 0)}, "foot.R": {"r": (-14, 0, 0)},
                              **both("upperarm", {"r": (20, 0, 18)}), **both("forearm", {"r": (10, 0, 0)})})
    attack = [(0, {}), (26, rear), (32, V.lerp_spec(rear, spit, 0.35)), (36, spit), (44, V.lerp_spec(spit, {}, 0.3)), (60, {})]
    hit = [(0, {}), (4, merge(puff(1.15), {"spine": {"r": (-12, 0, -5)}, "chest": {"r": (-8, 0, 0)}, "head": {"r": (-16, 0, -10)},
                                         "jaw": {"r": (20, 0, 0)}, "hips": {"t": (0, 0.04, -0.02)}, **both("upperarm", {"r": (20, 0, 20)})})),
           (15, {})]
    # 死ぬ: 膝から崩れ、後ろへ尻もちをついて仰向けに倒れる。袋はしぼむ
    sit = merge(puff(0.9), {"hips": {"t": (0, 0.10, -0.55), "r": (-14, 0, 0)}, **both("thigh", {"r": (-70, 0, 6)}),
                            **both("shin", {"r": (100, 0, 0)}), **both("foot", {"r": (-30, 0, 0)}), "spine": {"r": (10, 0, 0)},
                            "head": {"r": (14, 0, 0)}, "jaw": {"r": (24, 0, 0)}, **both("upperarm", {"r": (-20, 0, 24)})})
    flat = merge(puff(0.62), {"hips": {"t": (0, 0.12, -0.62), "r": (-72, 0, 8)}, "thigh.L": {"r": (-30, 0, 14)}, "thigh.R": {"r": (-44, 0, -4)},
                              "shin.L": {"r": (34, 0, 0)}, "shin.R": {"r": (52, 0, 0)}, **both("foot", {"r": (-10, 0, 0)}), "spine": {"r": (-4, 0, 0)},
                              "chest": {"r": (-4, 0, 0)}, "neck": {"r": (-10, 0, 0)}, "head": {"r": (-14, 0, -30)}, "jaw": {"r": (30, 0, 0)},
                              **both("upperarm", {"r": (-30, 0, 50)}), **both("forearm", {"r": (-20, 0, 0)})})
    # 転がる途中も膝を曲げたままにする（脚が伸びると足が先に床へ着き、尻が浮いて跳ねる）
    roll = merge(V.lerp_spec(sit, flat, 0.5), {**both("shin", {"r": (96, 0, 0)}), **both("foot", {"r": (-26, 0, 0)})})
    die = [(0, {}), (8, merge(puff(1.2), {"spine": {"r": (-14, 0, 0)}, "head": {"r": (-22, 0, 0)}, "jaw": {"r": (26, 0, 0)}})),
           (30, sit), (42, roll), (52, flat), (60, V.lerp_spec(flat, sit, 0.05)), (84, flat)]
    return {"idle": idle, "walk": walk, "attack": attack, "hit": hit, "die": die}


# 構え: どのクリップのどのコマにも重ねる（休みの形は骨を置きやすい立ち姿・遊ぶ時の姿はこちら）
STANCE = {
    "melee": {"spine": {"r": (8, 0, 0)}, "chest": {"r": (4, 0, 0)}, "neck": {"r": (-6, 0, 0)}, "head": {"r": (-6, 0, 0)},
              **both("thigh", {"r": (-12, 0, 0)}), **both("shin", {"r": (16, 0, 0)}), **both("foot", {"r": (-4, 0, 0)}),
              **both("upperarm", {"r": (-6, 0, 3)}), **both("forearm", {"r": (-6, 0, 0)})},
    "ranged": {"spine": {"r": (3, 0, 0)}, **both("thigh", {"r": (-6, 0, 0)}), **both("shin", {"r": (10, 0, 0)}),
               **both("foot", {"r": (-4, 0, 0)})},
}
# 形は足元の原点のまわりで拡げて背丈をそろえる（構えの背丈: melee ≈ 2.0 m・ranged ≈ 1.7 m）
SCALE = {"melee": 1.07, "ranged": 1.05}
BUILD = {"melee": (build_melee, clips_melee), "ranged": (build_ranged, clips_ranged)}

C.reset()
build, make_clips = BUILD[KIND]
rig, parts = build()
name = "creature_" + KIND
body, arm = C.assemble(rig, parts, name, SCALE[KIND])
tris = V.tri_count([body])
if not NOBAKE:
    C.bake_single_material(body, 512, name)

mouth = None
if KIND == "ranged":
    mouth = bpy.data.objects.new("MOUTH", None)
    mouth.empty_display_size = 0.03
    bpy.context.scene.collection.objects.link(mouth)
    mouth.parent = arm
    mouth.parent_type = "BONE"
    mouth.parent_bone = "head"
    bpy.context.view_layer.update()
    # 局所の -Y（Blender の前）が吐く向き = glTF の局所 +Z
    mouth.matrix_world = Matrix.Translation(Vector((0, -0.33, 1.515)) * SCALE[KIND])

clips = {nm: C.grounded(arm, body, [(f, C.add_spec(STANCE[KIND], sp)) for f, sp in frames]) for nm, frames in make_clips().items()}
for nm, frames in clips.items():
    V.key(arm, nm, frames)
bpy.context.scene.frame_set(0)
out = os.path.join(V.OUT, name + ".glb")
V.export_glb(out, animations=True)
print("%s tris=%d bones=%d clips=%s" % (name, tris, len(rig.bones), {k: round(v[-1][0] / F, 3) for k, v in clips.items()}))
IMPACT = {"melee": 30, "ranged": 36}   # 攻撃が当たる・吐くコマ（preview.py の IMPACT と合わせる）
print("%s attack impact f%d = %.3f s" % (name, IMPACT[KIND], IMPACT[KIND] / F))
C.ground_report(arm, body, clips, {"attack": [0, IMPACT[KIND] - 6, IMPACT[KIND], clips["attack"][-1][0]]})
if mouth is not None:
    arm.animation_data.action = bpy.data.actions["attack"]
    for t in arm.animation_data.nla_tracks:
        t.mute = True
    for f in (0, 26, 36):
        bpy.context.scene.frame_set(f)
        bpy.context.view_layer.update()
        print("MOUTH attack f%d (%.3f, %.3f, %.3f)" % (f, *mouth.matrix_world.to_translation()))
