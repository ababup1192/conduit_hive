# 蹴りの間に手前へ出る脚（腿と、脛から下の装甲ブーツ）を assets/models/boot.glb へ書き出す。骨なし・材質 1 つ（色の絵と emissive の絵）。
#   cd modeling && devbox run -- blender -b --factory-startup --python boot.py
# ノードは 2 つ: leg_thigh（原点 = 股関節・膝は -Z に THIGH）と leg_shin（原点 = 膝・足首は -Z に SHIN・つま先は -Y）。
# engine では Blender の -Z が下（-Y）・-Y が前（+Z）。膝の曲げと腿の振りはゲームの側（Boot.flix）が 2 つの行列で付ける。
import bpy, bmesh, os, sys, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mathutils import Vector
import vmlib as V

THIGH = 0.44
SHIN = 0.42
FWD = (0, -1, 0)


def tagged(objs, k):
    """部品に「腿 = 0・脛 = 1」の面のマーカーを付ける（まとめてベイクした後に 2 つへ分ける）。"""
    for o in objs:
        a = o.data.attributes.new("seg", "INT", "FACE")
        a.data.foreach_set("value", [k] * len(o.data.polygons))
    return objs


def thigh():
    """股関節（原点）から膝（-Z に THIGH）: 布の腿・前を覆う装甲の板・横の留め具・板のふちの光る筋。"""
    k = Vector((0, 0, -THIGH))
    top = Vector((0, 0, 0.02))
    parts = [V.tube(top, k + Vector((0, 0, 0.03)), [(0, 0.09), (0.5, 0.08), (1, 0.062)], "graphite", sides=12, squash=0.9)]
    parts.append(V.shell(Vector((0, 0, -0.04)), k + Vector((0, 0, 0.07)), [(0, 0.084), (1, 0.066)], 15, 165, 0.012, "steel", steps=6, up=FWD, squash=0.92))
    parts.append(V.shell(Vector((0, 0, -0.06)), k + Vector((0, 0, 0.12)), [(0, 0.097), (1, 0.08)], 70, 110, 0.006, "steel_dark", steps=2, up=FWD, squash=0.92))
    for z in (-0.12, -0.27):
        p = Vector((0, 0, z))
        parts.append(V.tube(p, p + Vector((0, 0, -0.03)), [(0, 0.085), (1, 0.083)], "steel_dark", sides=10, squash=0.9))
    for x in (-1, 1):
        parts.append(V.box((0.088 * x, 0.0, -0.2), (0.02, 0.05, 0.08), "steel_dark", bevel=0.004))
        parts.append(V.box((0.064 * x, -0.06, -0.21), (0.004, 0.006, 0.22), "glow"))
    return parts


def shin():
    """膝（原点）から足首と足: 膝の当て・ふくらはぎの膨らむ布・前を覆うすね当て・靴の口の輪・甲と踵とつま先・溝のある厚い靴底・光る筋。"""
    a = Vector((0, 0, -SHIN))
    parts = [V.tube(Vector((0, 0, 0.03)), a, [(0, 0.062), (0.18, 0.071), (0.45, 0.067), (0.85, 0.05), (1, 0.048)], "graphite", sides=12, squash=0.92)]
    # 膝の当て: 丸い鋼の殻と、真ん中の暗い板と光る点
    parts.append(V.shell(Vector((0, 0, 0.08)), Vector((0, 0, -0.09)), [(0, 0.072), (1, 0.077)], 20, 160, 0.024, "steel", steps=7, up=FWD, squash=0.95, bevel=0.007))
    parts.append(V.box((0, -0.104, -0.005), (0.062, 0.012, 0.075), "steel_dark", bevel=0.004))
    parts.append(V.box((0, -0.111, -0.005), (0.028, 0.004, 0.016), "glow"))
    # すね当て: 前の厚い板（上が広く足首へ細る）と、ふくらはぎの側の薄い板
    parts.append(V.shell(Vector((0, 0, -0.1)), a + Vector((0, 0, 0.1)), [(0, 0.08), (1, 0.06)], 10, 170, 0.016, "steel", steps=7, up=FWD, squash=0.95))
    parts.append(V.shell(Vector((0, 0, -0.12)), a + Vector((0, 0, 0.14)), [(0, 0.078), (1, 0.062)], 185, 355, 0.008, "steel_dark", steps=6, up=FWD, squash=0.95))
    # すね当ての両のふちの光る筋（銃の光る筋と同じ色）
    for x in (-1, 1):
        parts.append(V.seg((0.056 * x, -0.07, -0.12), (0.042 * x, -0.058, -SHIN + 0.12), 0.006, 0.005, "glow", up=FWD, bevel=0.0))
    # 靴: 横から見た形（y, z）を幅で押し出す。踵は +Y・つま先は -Y。口は脛の下の 1/5 まで上がる
    sole = -SHIN - 0.12
    upper = [(0.07, -SHIN + 0.075), (0.082, sole + 0.05), (0.066, sole), (-0.18, sole), (-0.216, sole + 0.025), (-0.21, sole + 0.062),
             (-0.16, sole + 0.092), (-0.085, -SHIN - 0.03), (-0.064, -SHIN + 0.075)]
    parts.append(V.prism(upper, 0.13, "steel_dark", bevel=0.01))
    # 靴の口の鋼の輪と、その上の光るライン
    top = Vector((0, -0.002, -SHIN + 0.07))
    parts.append(V.tube(top, top + Vector((0, 0, 0.026)), [(0, 0.077), (1, 0.075)], "steel", sides=12, squash=0.92))
    parts.append(V.tube(top + Vector((0, 0, 0.026)), top + Vector((0, 0, 0.034)), [(0, 0.071), (1, 0.071)], "glow", sides=12, squash=0.92))
    # つま先の鋼の当てと甲の板
    parts.append(V.prism([(-0.12, sole + 0.004), (-0.222, sole + 0.004), (-0.226, sole + 0.035), (-0.212, sole + 0.07), (-0.16, sole + 0.098), (-0.12, sole + 0.098)],
                         0.138, "steel", bevel=0.008))
    parts.append(V.box((0, -0.115, sole + 0.098), (0.104, 0.08, 0.016), "steel", bevel=0.004, rot=(-30, 0, 0)))
    # 甲の留め帯 2 本
    for y, z in ((-0.07, -SHIN - 0.045), (-0.01, -SHIN - 0.01)):
        parts.append(V.box((0, y, z), (0.14, 0.024, 0.016), "graphite", bevel=0.003, rot=(-35, 0, 0)))
    # 踵の当て
    parts.append(V.box((0, 0.08, sole + 0.05), (0.12, 0.016, 0.08), "steel", bevel=0.005))
    # 靴底: 厚い黒鉛と、横に走る溝
    parts.append(V.box((0, -0.072, sole - 0.016), (0.142, 0.32, 0.034), "graphite", bevel=0.006))
    for i in range(7):
        y = -0.215 + 0.045 * i
        parts.append(V.box((0, y, sole - 0.036), (0.13, 0.016, 0.012), "steel_dark", bevel=0.002))
    # 靴の横の光る筋（踵から甲へ）
    for x in (-1, 1):
        parts.append(V.seg((0.067 * x, 0.06, sole + 0.045), (0.067 * x, -0.14, sole + 0.045), 0.004, 0.007, "glow", up=(0, 0, 1), bevel=0.0))
    return parts


def separate(o):
    """面のマーカー seg が 1 の面（脛）を別の物へ分ける。返す: (腿, 脛)。"""
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_mode(type="FACE")
    bpy.ops.mesh.select_all(action="DESELECT")
    bm = bmesh.from_edit_mesh(o.data)
    layer = bm.faces.layers.int["seg"]
    for f in bm.faces:
        f.select_set(f[layer] == 1)
    bmesh.update_edit_mesh(o.data)
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    rest = [x for x in bpy.context.scene.objects if x.type == "MESH" and x is not o]
    return o, rest[0]


V.reset()
# 伸ばした脚で一緒にベイクする（膝の継ぎ目に影が入る）。脛は膝を原点へ戻してから書き出す
lower = shin()
V.transform(lower, V.xf((0, 0, -THIGH)))
body = V.join(tagged(thigh(), 0) + tagged(lower, 1), "leg")
tris = V.tri_count([body])
V.harden_normals(body, sharp_deg=40.0)
V.bake_one_material(body, 1024, "boot")
th, sh = separate(body)
th.name, th.data.name = "leg_thigh", "leg_thigh"
sh.name, sh.data.name = "leg_shin", "leg_shin"
sh.data.transform(V.xf((0, 0, THIGH)))
for o in (th, sh):
    o.data.attributes.remove(o.data.attributes["seg"])
V.export_glb(os.path.join(V.OUT, "boot.glb"), animations=False)
print("boot tris=%d thigh=%d shin=%d" % (tris, V.tri_count([th]), V.tri_count([sh])))
