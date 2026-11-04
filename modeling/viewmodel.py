# ビューモデル（腕と銃・骨つき）を組んで assets/models/viewmodel_<銃>.glb へ書き出す。
#   cd modeling && devbox run -- blender -b --factory-startup --python viewmodel.py -- pistol [--nobake]
# 座標はカメラの座標: 原点 = 目・-Y = 前・-X = 画面の右・-Z = 下（engine では +Z = 前・+X = 右・-Y = 下）。
# 骨: root（握りの所。揺れ・反動・構えはここ）→ forearm.R → hand.R → {index.R, gun → {trigger, slide|pump|mag, forearm.L → hand.L}}。
# 左腕を gun の子に置く: 反動で銃が跳ねても左手が先台から離れない（肘は画面の外なので、腕の付け根がずれても見えない）。
# MUZZLE は gun の骨の子の empty（休みの形の銃口・局所の -Y が撃つ向き = glTF の局所 +Z）。
import bpy, os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mathutils import Vector, Matrix, Euler
import vmlib as V
import guns, arms

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
KIND = next((a for a in args if a in guns.BUILD), "pistol")
NOBAKE = "--nobake" in args

# 銃の置き場所（カメラの座標）。少し内へ向けて、銃口の線が画面の真ん中の先で照準と交わる
PLACE = {
    "pistol":  ((-0.082, -0.232, -0.066), (2.0, 5.0, 14.0)),
    "shotgun": ((-0.100, -0.300, -0.100), (1.0, 4.0, 9.0)),
    "rifle":   ((-0.098, -0.295, -0.096), (1.0, 4.0, 9.0)),
}
loc, rot = PLACE[KIND]
G = V.xf(loc, rot)
G3 = G.to_3x3()


def gp(v):
    return G @ Vector(v)


def gl(v):
    """銃の座標の向き → カメラの座標の向き（平行移動を書く時）。"""
    return tuple(G3 @ Vector(v))


def gr(r):
    """銃の座標の軸まわりの回し（度）→ カメラの座標の軸の Euler（度）。"""
    R = G3 @ Euler([math.radians(a) for a in r], "XYZ").to_matrix() @ G3.inverted()
    return tuple(math.degrees(a) for a in R.to_euler("XYZ"))


V.reset()
gun = guns.BUILD[KIND](lod=1)
rh, wristR, elbowR, knuckle, index_tip = arms.right_hand(gun)
lh = None
if gun["support"] is not None:
    lh, wristL, elbowL = arms.left_hand(gun)

rig = V.Rig("viewmodel_" + KIND)
groups = {}
for o, bone in gun["parts"]:
    groups.setdefault(bone, []).append(o)
for d in (rh, lh or {}):
    for bone, objs in d.items():
        groups.setdefault(bone, []).extend(objs)
allobjs = [o for objs in groups.values() for o in objs]
V.transform(allobjs, G)

O = gp((0, 0, 0))
rig.bone("root", O, O + Vector((0, 0, 0.05)))
rig.bone("forearm.R", gp(elbowR), gp(wristR), "root")
rig.bone("hand.R", gp(wristR), O, "forearm.R")
rig.bone("index.R", gp(knuckle), gp(index_tip), "hand.R")
rig.bone("gun", O, gp((0, -0.1, 0)), "hand.R")
trig = gun["trigger"]
rig.bone("trigger", gp(trig), gp(trig + Vector((0, 0, -0.02))), "gun")
if KIND == "pistol":
    rig.bone("slide", gp((0, 0, 0.03)), gp((0, -0.1, 0.03)), "gun")
if "pump" in gun:
    rig.bone("pump", gp(gun["pump"]), gp(gun["pump"] + Vector((0, -0.1, 0))), "gun")
if "mag" in gun:
    rig.bone("mag", gp(gun["mag"]), gp(gun["mag"] + Vector((0, 0, -0.05))), "gun")
if lh:
    rig.bone("forearm.L", gp(elbowL), gp(wristL), "gun")
    rig.bone("hand.L", gp(wristL), gp(gun["support"].o), "forearm.L")
for bone, objs in groups.items():
    rig.add(objs, {bone: 1.0})
rig.apply_weights()

body = V.join(allobjs, "viewmodel_" + KIND)
tris = V.tri_count([body])
V.harden_normals(body)
if not NOBAKE:
    V.unwrap(body)
    V.bake_atlas(body, 1024, "vm_" + KIND)

arm = rig.build_armature()
body.parent = arm
mod = body.modifiers.new("Armature", "ARMATURE")
mod.object = arm

muzzle = bpy.data.objects.new("MUZZLE", None)
muzzle.empty_display_size = 0.02
bpy.context.scene.collection.objects.link(muzzle)
muzzle.parent = arm
muzzle.parent_type = "BONE"
muzzle.parent_bone = "gun"
bpy.context.view_layer.update()
muzzle.matrix_world = G @ Matrix.Translation(gun["muzzle"])

# ── クリップ ──
F = V.FPS


def idle():
    sway = [(0, (0, 0, 0), (0, 0, 0)), (30, (0.0018, 0.0006, -0.0035), (0.5, 0.25, -0.3)),
            (60, (0.0, 0.0015, -0.0055), (0.9, 0, 0)), (90, (-0.0018, 0.0006, -0.003), (0.4, -0.25, 0.3)), (120, (0, 0, 0), (0, 0, 0))]
    return [(f, {"root": {"t": t, "r": r}}) for f, t, r in sway]


def draw():
    low = {"root": {"t": (0.03, 0.03, -0.20), "r": (34, -18, -14)}}
    over = {"root": {"t": (0, -0.004, 0.004), "r": (-2.5, 1, 0.5)}}
    return [(0, low), (5, V.lerp_spec(low, over, 0.6)), (13, over), (21, {})]


def kick(back, up, pitch, roll, yaw):
    return {"t": tuple(a + b for a, b in zip(gl((0, back, 0)), (0, 0, up))), "r": (-pitch, roll, -yaw)}


TRIG = {"trigger": {"r": gr((22, 0, 0))}, "index.R": {"r": gr((10, 0, 0))}}


def with_trig(d, pulled=True):
    out = dict(TRIG) if pulled else {}
    out.update(d)
    return out


clips = {"idle": idle(), "draw": draw()}
if KIND == "pistol":
    sl = {"slide": {"t": gl((0, gun["slide_len"], 0))}}
    clips["fire"] = [(0, {}), (1, with_trig({"root": kick(0.012, 0.002, 3, 0, 0.5)})),
                     (2, with_trig(dict(sl, root=kick(0.034, 0.006, 8.5, -1.2, 1.5)))),
                     (4, with_trig(dict(sl, root=kick(0.026, 0.006, 7, -1.0, 1.2)))),
                     (6, with_trig({"root": kick(0.010, 0.002, 2.6, -0.3, 0.4)}, False)), (11, {})]
elif KIND == "shotgun":
    pull = gl((0, gun["pump_len"], 0))
    rack = {"pump": {"t": pull}, "forearm.L": {"t": pull}}
    clips["fire"] = [(0, {}), (1, with_trig({"root": kick(0.02, 0.004, 4, 0, 0.6)})),
                     (3, with_trig({"root": kick(0.058, 0.013, 12, -2, 2)})),
                     (8, {"root": kick(0.020, 0.004, 4, -0.5, 0.6)}), (12, {"root": kick(0.004, 0, 0.6, 0, 0)}),
                     (17, dict(rack, root={"r": (0, -3, 0.5)})), (20, dict(rack, root={"r": (0, -3, 0.5)})),
                     (25, {"root": {"r": (-0.6, -1, 0)}}), (30, {})]
    # 下の装填口と左手が画面に入るよう、銃を持ち上げて内へ転がす
    tilt = {"t": (0.032, 0, 0.055), "r": (10, -28, 8)}
    tiltb = {"t": (0.012, 0, 0.02), "r": (4, -10, 3)}
    under = lambda dz: {"t": gl((0, 0.17, dz))}
    clips["reload"] = [(0, {}), (10, {"root": tilt}),
                       (16, {"root": tilt, "forearm.L": {"t": gl((0.02, 0.10, -0.08))}}),
                       (26, {"root": tilt, "forearm.L": under(-0.062)}), (32, {"root": tilt, "forearm.L": under(-0.038)}),
                       (38, {"root": tilt, "forearm.L": {"t": gl((0.02, 0.13, -0.08))}}),
                       (46, {"root": tilt, "forearm.L": under(-0.062)}), (52, {"root": tilt, "forearm.L": under(-0.038)}),
                       (60, {"root": tiltb}), (66, dict(rack, root=tiltb)), (72, {"root": {"r": (1, -3, 0.5)}}), (78, {})]
else:
    clips["fire"] = [(0, {}), (1, with_trig({"root": kick(0.016, 0.003, 2.2, -0.4, 0.4)})),
                     (3, with_trig({"root": kick(0.006, 0.001, 0.8, 0, 0.1)})), (6, {})]
    to_mag = Vector((0, 0.150, -0.112))
    tilt = {"t": (0.026, 0, 0.035), "r": (7, -18, 7)}
    hold = lambda extra: {"t": gl(to_mag + Vector(extra))}
    clips["reload"] = [(0, {}), (10, {"root": tilt}),
                       (18, {"root": tilt, "forearm.L": hold((0, 0, 0))}),
                       (22, {"root": tilt, "forearm.L": hold((0, 0, 0))}),
                       (32, {"root": tilt, "forearm.L": hold((0, 0.03, -0.20)), "mag": {"t": gl((0, 0.03, -0.20))}}),
                       (42, {"root": tilt, "forearm.L": hold((0.05, 0.12, -0.30)), "mag": {"t": gl((0, 0.03, -0.42))}}),
                       (50, {"root": tilt, "forearm.L": hold((0, 0.02, -0.12)), "mag": {"t": gl((0, 0.02, -0.12))}}),
                       (58, {"root": tilt, "forearm.L": hold((0, 0, 0.006)), "mag": {"t": gl((0, 0, 0.006))}}),
                       (62, {"root": {"t": (0.020, 0, 0.026), "r": (5, -13, 5)}, "forearm.L": hold((0, 0, 0))}),
                       (76, {"root": {"r": (1, -2, 1)}}), (96, {})]

for name, frames in clips.items():
    V.key(arm, name, frames)

bpy.context.scene.frame_set(0)
out = os.path.join(V.OUT, "viewmodel_%s.glb" % KIND)
V.export_glb(out, animations=True)
print("viewmodel %s tris=%d bones=%d clips=%s" % (KIND, tris, len(rig.bones), {k: v[-1][0] / F for k, v in clips.items()}))

# 確かめ: 各クリップの何コマかで銃口がどこへ動くか（カメラの座標）
for name in clips:
    arm.animation_data.action = bpy.data.actions[name]
    for t in arm.animation_data.nla_tracks:
        t.mute = True
    pts = []
    for f in (0, 2, 6, 10, 30):
        bpy.context.scene.frame_set(f)
        bpy.context.view_layer.update()
        pts.append("f%d(%.3f,%.3f,%.3f)" % (f, *muzzle.matrix_world.to_translation()))
    print("muzzle", name, " ".join(pts))
arm.animation_data.action = None
