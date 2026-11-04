# 3 丁の銃の形（拳銃・散弾銃・連射銃）。ビューモデルとピックアップの両方がここから組む。
# 銃の座標: 原点 = 握りの軸が機関部の底に当たる所・+X = 銃の左・-Y = 銃口の向き・+Z = 上。
# 返す dict: parts = [(物, 骨の名前)]・muzzle（銃口の真ん中）・grip（右手が握る楕円）・support（左手が支える楕円・拳銃は None）・
#            trigger（引き金の付け根）・mag / pump の真ん中。
# lod=0 はピックアップ用（刻み・溝・小さな部品を省く）。
import math
from mathutils import Vector, Matrix
import vmlib as V
from vmlib import box, prism, lathe, cyl_between, Wrap

GRIP_TILT = 16.0   # 握りの後ろへの傾き（度）


def grip_axis():
    t = math.radians(GRIP_TILT)
    return Vector((0, math.sin(t), -math.cos(t)))


def grip_wrap(a, b):
    g = grip_axis()
    back = Vector((0, 1, 0))
    e90 = (back - g * back.dot(g)).normalized()
    return Wrap((0, 0, 0), (1, 0, 0), e90, g, a, b)


def build_grip(parts, length, width, depth, lod, guard_front=-0.062, guard_low=-0.032):
    """握り（後ろへ傾いた角柱・横に滑り止めの板・底板）と用心金と引き金。"""
    rot = Matrix.Rotation(math.radians(GRIP_TILT), 4, "X")
    d = depth / 2
    side = [(d + 0.004, 0.004), (-d, 0.004), (-d - 0.003, -0.022), (-d + 0.001, -0.034), (-d - 0.002, -0.050),
            (-d + 0.002, -length), (d, -length), (d + 0.003, -0.02)]
    parts.append((prism(side, width, "graphite", bevel=0.003, m4=rot), "gun"))
    if lod:
        for s in (1, -1):
            plate = box((s * (width / 2 + 0.0008), 0.002, -length * 0.55), (0.003, depth * 0.62, length * 0.62), "glove", bevel=0.0012)
            plate.data.transform(rot)
            parts.append((plate, "gun"))
    base = box((0, 0.0, -length - 0.004), (width + 0.004, depth + 0.006, 0.009), "steel_dark", bevel=0.002)
    base.data.transform(rot)
    parts.append((base, "gun"))
    # 用心金: 下の棒と前の柱
    parts.append((prism([(guard_front, guard_low), (-0.004, guard_low + 0.004), (-0.004, guard_low + 0.010),
                         (guard_front + 0.006, guard_low + 0.006)], 0.012, "graphite", bevel=0.0015), "gun"))
    parts.append((prism([(guard_front, guard_low), (guard_front + 0.007, guard_low + 0.003), (guard_front + 0.012, -0.001),
                         (guard_front + 0.004, -0.001)], 0.012, "graphite", bevel=0.0015), "gun"))
    trig = prism([(-0.030, -0.002), (-0.036, -0.010), (-0.037, -0.022), (-0.032, -0.022), (-0.031, -0.012), (-0.025, -0.002)],
                 0.007, "steel", bevel=0.0012)
    parts.append((trig, "trigger"))
    return Vector((0, -0.028, -0.002))


def stock(parts, y0, top):
    """機関部の後ろから肩へ下がる骨組みの銃床。
    WhyNot: 銃の軸のまま後ろへ伸ばさない — 目のすぐ横を通る太い筒になり、切り口が画面の右下を塞ぐ。"""
    arm = [(y0 - 0.004, top), (y0 + 0.040, top - 0.006), (y0 + 0.150, -0.060), (y0 + 0.150, -0.098), (y0 + 0.118, -0.082),
           (y0 + 0.030, 0.004), (y0 - 0.004, 0.004)]
    parts.append((prism(arm, 0.024, "graphite", bevel=0.003), "gun"))
    parts.append((prism([(y0 + 0.146, -0.052), (y0 + 0.162, -0.056), (y0 + 0.166, -0.112), (y0 + 0.150, -0.110)], 0.034,
                        "steel_dark", bevel=0.003), "gun"))


def pistol(lod=1):
    P = []
    # 遊底: 前の下を斜めに落とした角の箱・上に照準の背・横に刻みと光る筋
    slide = [(0.036, 0.012), (0.036, 0.039), (0.030, 0.046), (-0.148, 0.046), (-0.166, 0.037), (-0.166, 0.021), (-0.156, 0.012)]
    P.append((prism(slide, 0.030, "steel", bevel=0.0028), "slide"))
    P.append((box((0, -0.060, 0.0475), (0.012, 0.150, 0.004), "steel_dark", bevel=0.0012), "slide"))
    P.append((box((0, 0.028, 0.051), (0.022, 0.010, 0.008), "steel_dark", bevel=0.0015), "slide"))     # 後ろの照準
    P.append((box((0, -0.150, 0.0505), (0.006, 0.008, 0.007), "steel_dark", bevel=0.0012), "slide"))  # 前の照準
    for s in (1, -1):
        # 横の一段低い板（黒鉛）とその中の光る筋
        P.append((box((s * 0.0152, -0.075, 0.028), (0.0016, 0.110, 0.012), "graphite", bevel=0.0006), "slide"))
        P.append((box((s * 0.0161, -0.078, 0.028), (0.0012, 0.090, 0.0026), "glow"), "slide"))
        if lod:
            for k in range(4):
                P.append((box((s * 0.0152, 0.006 + k * 0.007, 0.030), (0.002, 0.0028, 0.020), "steel_dark", rot=(12, 0, 0)), "slide"))
    # 後ろの面: 一段高い板と、引く時に指を掛ける左右の耳
    P.append((box((0, 0.0372, 0.029), (0.022, 0.0026, 0.022), "steel_dark", bevel=0.0009), "slide"))
    for s in (1, -1):
        P.append((box((s * 0.0128, 0.030, 0.040), (0.0065, 0.012, 0.007), "steel_dark", bevel=0.0012), "slide"))
    # 後ろの照準の光る点（構えると目の前に来る）
    P.append((box((0, 0.0335, 0.051), (0.010, 0.0012, 0.0022), "glow"), "slide"))
    # 銃身の先と銃口
    P.append((cyl_between((0, -0.160, 0.029), (0, -0.171, 0.029), 0.0072, "steel_dark", seg=10), "slide"))
    P.append((cyl_between((0, -0.170, 0.029), (0, -0.1716, 0.029), 0.0042, "bore", seg=10), "slide"))
    # 下の機関部（前に付属品の段）
    frame = [(0.032, 0.012), (-0.150, 0.012), (-0.150, -0.003), (-0.108, -0.010), (-0.066, -0.010), (-0.056, -0.002), (0.032, -0.002)]
    P.append((prism(frame, 0.026, "graphite", bevel=0.0022), "gun"))
    P.append((prism([(0.032, 0.012), (0.046, 0.010), (0.044, 0.004), (0.030, -0.002)], 0.022, "graphite", bevel=0.002), "gun"))  # 握りの上の張り出し
    trig = build_grip(P, 0.104, 0.029, 0.046, lod, guard_front=-0.066, guard_low=-0.030)
    return {"parts": P, "muzzle": Vector((0, -0.172, 0.029)), "grip": grip_wrap(0.0155, 0.024), "support": None,
            "trigger": trig, "slide_len": 0.024}


def shotgun(lod=1):
    P = []
    # 機関部: 角を落とした箱・下に装填口の黒い窓・横に光る筋
    rec = [(0.070, -0.004), (0.070, 0.052), (0.056, 0.068), (-0.140, 0.068), (-0.152, 0.058), (-0.152, -0.004)]
    P.append((prism(rec, 0.050, "steel_dark", bevel=0.004), "gun"))
    P.append((box((0, -0.040, -0.009), (0.040, 0.150, 0.012), "graphite", bevel=0.003), "gun"))
    P.append((box((0, -0.050, 0.0705), (0.018, 0.150, 0.006), "graphite", bevel=0.0015), "gun"))     # 上の背
    for s in (1, -1):
        P.append((box((s * 0.0255, -0.045, 0.032), (0.0018, 0.150, 0.016), "graphite", bevel=0.0007), "gun"))
        P.append((box((s * 0.0266, -0.050, 0.032), (0.0012, 0.120, 0.0032), "glow"), "gun"))
        if lod:
            P.append((box((s * 0.0255, 0.030, 0.012), (0.002, 0.046, 0.010), "bore", bevel=0.0008), "gun"))  # 排莢口
    # 後ろの面の弾の数の窓（構えると目に入る）
    P.append((box((0, 0.0712, 0.044), (0.020, 0.0014, 0.0035), "glow"), "gun"))
    P.append((box((0, 0.0705, 0.040), (0.034, 0.002, 0.018), "graphite", bevel=0.0008), "gun"))
    stock(P, 0.068, 0.058)
    # 銃身と熱よけ・下の弾倉の管
    P.append((cyl_between((0, -0.150, 0.042), (0, -0.590, 0.042), 0.0135, "steel", seg=12), "gun"))
    P.append((cyl_between((0, -0.588, 0.042), (0, -0.5915, 0.042), 0.0085, "bore", seg=12), "gun"))
    for k in range(3 if lod else 1):
        y0 = -0.165 - k * 0.105
        ln = 0.095 if lod else 0.30
        P.append((box((0, y0 - ln / 2, 0.054), (0.022, ln, 0.012), "graphite", bevel=0.0025), "gun"))
    P.append((cyl_between((0, -0.150, 0.014), (0, -0.520, 0.014), 0.0115, "steel_dark", seg=10), "gun"))
    P.append((cyl_between((0, -0.515, 0.014), (0, -0.528, 0.014), 0.0135, "steel", seg=10), "gun"))
    P.append((box((0, -0.540, 0.028), (0.014, 0.030, 0.036), "steel_dark", bevel=0.003), "gun"))      # 先の留め具
    # 先台（引くと動く）: 八角の筒と溝
    pump_c = Vector((0, -0.285, 0.016))
    P.append((V.tube((0, -0.210, 0.016), (0, -0.360, 0.016), [(0, 0.024), (0.06, 0.028), (0.94, 0.028), (1, 0.025)],
                     "graphite", sides=8, squash=0.95), "pump"))
    if lod:
        for k in range(4):
            y = -0.245 - k * 0.026
            P.append((V.tube((0, y, 0.016), (0, y - 0.006, 0.016), [(0, 0.0292), (1, 0.0292)], "steel_dark", sides=8, squash=0.95), "pump"))
    trig = build_grip(P, 0.110, 0.032, 0.050, lod, guard_front=-0.070, guard_low=-0.036)
    sup = Wrap((0, -0.232, 0.016), (1, 0, 0), (0, 0, -1), (0, -1, 0), 0.029, 0.028)
    return {"parts": P, "muzzle": Vector((0, -0.592, 0.042)), "grip": grip_wrap(0.0165, 0.026), "support": sup,
            "trigger": trig, "pump": pump_c, "pump_len": 0.075}


def rifle(lod=1):
    P = []
    # 上の機関部（背に照準の箱）・下の機関部・弾倉の口
    upper = [(0.085, 0.020), (0.085, 0.050), (0.075, 0.060), (-0.125, 0.060), (-0.125, 0.020)]
    P.append((prism(upper, 0.040, "steel_dark", bevel=0.0035), "gun"))
    lower = [(0.080, 0.021), (0.080, -0.004), (0.010, -0.006), (-0.040, -0.016), (-0.108, -0.016), (-0.120, 0.000), (-0.120, 0.021)]
    P.append((prism(lower, 0.038, "graphite", bevel=0.003), "gun"))
    if lod:
        for k in range(7):
            P.append((box((0, 0.060 - k * 0.026, 0.0625), (0.024, 0.008, 0.005), "graphite", bevel=0.0012), "gun"))
    # 照準: 角の箱と後ろの面の弾の数の窓
    P.append((box((0, 0.020, 0.074), (0.030, 0.050, 0.026), "graphite", bevel=0.004), "gun"))
    P.append((box((0, 0.0455, 0.079), (0.016, 0.0014, 0.0035), "glow"), "gun"))
    P.append((box((0, -0.006, 0.083), (0.022, 0.004, 0.012), "steel_dark", bevel=0.001), "gun"))
    stock(P, 0.083, 0.054)
    # 前の覆い: 横に通気の溝と光る筋
    hg = [(-0.120, 0.058), (-0.405, 0.054), (-0.412, 0.044), (-0.412, 0.004), (-0.400, -0.006), (-0.120, -0.006)]
    P.append((prism(hg, 0.048, "graphite", bevel=0.004), "gun"))
    for s in (1, -1):
        P.append((box((s * 0.0245, -0.262, 0.010), (0.0013, 0.250, 0.0030), "glow"), "gun"))
        if lod:
            for k in range(5):
                P.append((box((s * 0.0242, -0.180 - k * 0.042, 0.034), (0.002, 0.026, 0.010), "bore", bevel=0.0008), "gun"))
    P.append((box((0, -0.262, 0.059), (0.020, 0.270, 0.004), "steel_dark", bevel=0.0012), "gun"))
    # 銃身・銃口の先の部品
    P.append((cyl_between((0, -0.410, 0.030), (0, -0.475, 0.030), 0.0095, "steel", seg=10), "gun"))
    P.append((V.tube((0, -0.470, 0.030), (0, -0.528, 0.030), [(0, 0.0135), (1, 0.0135)], "steel_dark", sides=6), "gun"))
    P.append((cyl_between((0, -0.527, 0.030), (0, -0.5295, 0.030), 0.0075, "bore", seg=10), "gun"))
    # 弾倉（前へ反る）
    mag = [(-0.052, 0.000), (-0.092, 0.000), (-0.112, -0.090), (-0.126, -0.150), (-0.088, -0.160), (-0.074, -0.095)]
    P.append((prism(mag, 0.024, "steel_dark", bevel=0.0025), "mag"))
    P.append((prism([(-0.124, -0.150), (-0.128, -0.166), (-0.084, -0.176), (-0.086, -0.160)], 0.028, "graphite", bevel=0.002), "mag"))
    trig = build_grip(P, 0.105, 0.030, 0.048, lod, guard_front=-0.044, guard_low=-0.034)
    sup = Wrap((0, -0.240, 0.026), (1, 0, 0), (0, 0, -1), (0, -1, 0), 0.026, 0.034)
    return {"parts": P, "muzzle": Vector((0, -0.530, 0.030)), "grip": grip_wrap(0.0155, 0.025), "support": sup,
            "trigger": trig, "mag": Vector((0, -0.090, -0.080))}


BUILD = {"pistol": pistol, "shotgun": shotgun, "rifle": rifle}
