# 装甲の手袋の手と前腕（3 丁で共有）。座標は銃の座標（guns.py の頭）。
# 右手は握り（楕円の柱）を包み、人差し指は引き金に・親指は銃の左の面に沿う。左手は先台・覆いを下から支える。
# 返す値: 骨の名前 → 物の並び・手首と肘の位置（骨を置くため）。
import math
from mathutils import Vector
import vmlib as V
from vmlib import seg

FINGER = 0.0165          # 指の太さ（握る面から外への厚み）


def finger(W, h0, h1, th, parts, caps=True):
    """3 節の指。th = (付け根, 第 2 関節, 第 1 関節, 先) の角度。"""
    a, b, c, d = th
    step = 1 if b > a else -1
    gap = 2.5 * step
    parts.append(W.band(a, b - gap / 2, h0, h1, 0.0, FINGER, "glove", steps=3))
    parts.append(W.band(b + gap / 2, c - gap / 2, h0 + 0.0005, h1 - 0.0005, 0.0005, FINGER - 0.001, "glove", steps=2))
    parts.append(W.band(c + gap / 2, d, h0 + 0.001, h1 - 0.001, 0.001, FINGER - 0.0025, "glove", steps=2))
    if caps:
        parts.append(W.band(a + 4 * step, b - 8 * step, h0 + 0.0015, h1 - 0.0015, FINGER, FINGER + 0.0035, "steel_dark", steps=2, bevel=0.0012))


def forearm(W, d, length, parts):
    """手首 W から向き d へ伸びる前腕: 手袋の口・布の袖・上と外を覆う装甲・2 本の帯。"""
    W, d = Vector(W), Vector(d).normalized()
    E = W + d * length
    parts.append(V.tube(W - d * 0.006, W + d * 0.032, [(0, 0.031), (0.5, 0.034), (1, 0.033)], "steel_dark", sides=8, squash=0.88))
    parts.append(V.tube(W + d * 0.03, E, [(0, 0.030), (0.5, 0.037), (1, 0.043)], "graphite", sides=8, squash=0.86))
    parts.append(V.shell(W + d * 0.045, W + d * (length * 0.92), [(0, 0.032), (1, 0.043)], -30, 150, 0.0045, "steel", steps=5, squash=0.88))
    for t in (0.40, 0.72):
        p = W + d * (length * t)
        r = 0.032 + 0.011 * t + 0.0062
        parts.append(V.tube(p, p + d * 0.014, [(0, r), (1, r)], "steel_dark", sides=8, squash=0.88))
    return E


def right_hand(gun):
    """銃の grip を握る右手。返す: {骨: [物]}・手首・肘・人差し指の付け根。"""
    W = gun["grip"]
    hand, index, arm = [], [], []
    # 掌（背の側から右の面）・親指の付け根のふくらみ（後ろから左の面へ）
    hand.append(W.band(92, 206, -0.002, 0.090, 0.0, 0.021, "glove", steps=5))
    hand.append(W.band(28, 94, -0.006, 0.048, 0.0, 0.019, "glove", steps=3))
    # 手の甲の装甲（右の面）
    hand.append(W.band(150, 212, 0.004, 0.062, 0.021, 0.026, "steel", steps=3, bevel=0.0018))
    # 中指・薬指・小指（用心金の下）
    for h0, h1 in ((0.033, 0.051), (0.0535, 0.0705), (0.073, 0.087)):
        finger(W, h0, h1, (206, 262, 302, 336), hand)
    # 人差し指: 右の面を前へ出て引き金へ曲がる
    K = W.p(236, 0.016, 0.008)
    p1 = Vector((-0.020, -0.046, -0.014))
    p2 = Vector((-0.004, -0.046, -0.016))
    p3 = Vector((0.003, -0.039, -0.019))
    index.append(seg(K, p1, 0.017, 0.016, "glove", up=(0, 0, 1)))
    index.append(seg(p1, p2, 0.015, 0.015, "glove", up=(0, 0, 1)))
    index.append(seg(p2, p3, 0.0135, 0.014, "glove", up=(0, 0, 1)))
    index.append(seg(K + (p1 - K) * 0.15, K + (p1 - K) * 0.8, 0.014, 0.004, "steel_dark", up=(-1, 0, 0), bevel=0.0012))
    # 親指: 銃の左の面に沿って前へ
    T0 = Vector((0.020, 0.016, -0.006))
    T1 = Vector((0.023, -0.016, -0.001))
    T2 = Vector((0.022, -0.043, 0.001))
    hand.append(seg(T0, T1, 0.019, 0.018, "glove", up=(1, 0, 0)))
    hand.append(seg(T1, T2, 0.0165, 0.016, "glove", up=(1, 0, 0), taper=0.92))
    hand.append(seg(T0 + (T1 - T0) * 0.2 + Vector((0.0095, 0, 0)), T1 + Vector((0.0095, 0, 0)), 0.012, 0.003, "steel_dark", up=(1, 0, 0), bevel=0.001))
    # 掌から手首へ（手の付け根）
    wrist = W.o + W.ax * 0.070 + W.e90 * 0.046 + Vector((-0.010, 0, 0))
    hand.append(seg(W.p(140, 0.040, 0.008), wrist, 0.050, 0.040, "glove", up=(1, 0, 0), bevel=0.006))
    d = Vector((-0.40, 0.55, -0.73)).normalized()
    elbow = forearm(wrist, d, 0.30, arm)
    return {"hand.R": hand, "index.R": index, "forearm.R": arm}, wrist, elbow, K, p3


def left_hand(gun):
    """先台・覆い（gun["support"]）を下から支える左手。"""
    W = gun["support"]
    hand, arm = [], []
    hand.append(W.band(16, 140, -0.004, 0.084, 0.0, 0.021, "glove", steps=5))
    hand.append(W.band(92, 140, 0.004, 0.070, 0.021, 0.026, "steel", steps=2, bevel=0.0018))
    for h0, h1 in ((0.004, 0.0215), (0.0235, 0.041), (0.043, 0.060), (0.062, 0.077)):
        finger(W, h0, h1, (140, 198, 236, 266), hand)
    T0 = W.p(4, -0.004, 0.010)
    T1 = W.p(-12, 0.030, 0.011)
    T2 = W.p(-20, 0.058, 0.010)
    hand.append(seg(T0, T1, 0.019, 0.018, "glove", up=W.e0))
    hand.append(seg(T1, T2, 0.0165, 0.016, "glove", up=W.e0, taper=0.92))
    hand.append(seg(T0 + (T1 - T0) * 0.25 + W.e0 * 0.0095, T1 + W.e0 * 0.0095, 0.012, 0.003, "steel_dark", up=W.e0, bevel=0.001))
    wrist = W.o - W.ax * 0.026 + W.e90 * 0.044 + W.e0 * 0.022
    hand.append(seg(W.p(70, 0.020, 0.008), wrist, 0.050, 0.040, "glove", up=W.e90, bevel=0.006))
    d = Vector((0.55, 0.75, -0.55)).normalized()
    elbow = forearm(wrist, d, 0.36, arm)
    return {"hand.L": hand, "forearm.L": arm}, wrist, elbow
