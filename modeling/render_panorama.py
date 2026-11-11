# ベイクしたステージ（stage.glb と区画ごとの lightmap）を、施設の中の 1 点から全方向の正距円筒のパノラマに描く。
# ゲームの環境マップ（金属っぽさと粗さを持つ材質の映り込みの景色。Scene3d.environmentMap）。
#   cd modeling && blender -b --factory-startup --python render_panorama.py -- [名前 ...]
#   名前を省くと CAPTURES の全部。書き出しは assets/models/stage_env/<名前>.png（2048×1024・8bit sRGB）。
#   --zones を付けると、区画ごとに区画のマスを囲む箱の真ん中（目の高さ）から撮り、stage_env/zone_<文字>.png・小文字の区画は zone_lc_<文字>.png（1024×512。大文字と小文字を区別しないファイルの場所でも別のファイルにする）へ書く
#   （ゲームの look の envPerZone。点はゲームの StageModel.zoneBox の center と同じ計算: 部屋はマスの角へ寄せる）。
# 光は足さない: ゲームと同じく、壁は trim sheet × lightmap × look の lightmapIntensity、光る筋と灯具は glb の emissive の強さ。
# 霧もゲームと同じ距離の式で混ぜる（look の fogColor・fogNear・fogFar）。混ぜないと奥の明るい壁が映り込み、ゲームの霧の中の景色と合わない。
# 向きは engine の約束（絵の真ん中 = −Z・u = 0.75 が +X・上が真上）。engine と Blender は左右が鏡なので、描いてから左右を反転して書く。
# 点（engine の座標）は CAPTURES。ゲームの look の envMaps の center と同じ値にする（箱の補正の基点）。
import bpy, math, os, sys, json
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
MODELS = os.path.join(ROOT, "assets", "models")
GLB = os.path.join(MODELS, "stage.glb")
MANIFEST = os.path.join(MODELS, "stage.manifest.json")
LOOK = os.path.join(ROOT, "assets", "conduit_hive.look.json")
OUT_DIR = os.path.join(MODELS, "stage_env")
WIDTH, HEIGHT = int(os.environ.get("PANO_W", "2048")), int(os.environ.get("PANO_H", "1024"))
SAMPLES = int(os.environ.get("PANO_SAMPLES", "32"))
# 絵に書く明るさの倍率（線形）。8bit は 1 で頭打ちになるので、強めた灯具と光る筋が白く潰れないよう 1/4 で書き、ゲームの look の envIntensity 4.0 で戻す。
# WhyNot: トーンマップの露出を掛けない — 映り込みは場面の HDR の光と同じ量で足され、露出は後処理でまとめて掛かる。
PANO_SCALE = 0.25
# 光る筋と灯具の映り込みの強さの倍率（パノラマの中だけ）。金属のパイプと床に、灯りが細いハイライトとして乗るようにする。
# WhyNot: 1（ゲームの絵のまま）にしない — 本物の灯具は画面の値の 1 より何倍も明るいが、ゲームの灯具は画面で白く飛ばない明るさに抑えてあり、
#   そのまま映すと照り返しが壁と見分けにくい。強めるのは映り込みだけで、灯具の見た目は変えない。
GLOW_BOOST = float(os.environ.get("PANO_GLOW_BOOST", "3.0"))

# 名前 → engine の座標の点（目の高さ 1.65 m）。room = 最初の部屋の真ん中・hive = 最後の広い部屋の真ん中・corridor = 東の長い通路の途中。
CAPTURES = {
    "room":     (20.0, 1.65, 22.0),
    "hive":     (104.0, 1.65, 132.0),
    "corridor": (154.0, 1.65, 78.0),
}


def ep(x, y, z):
    return Vector((-x, -z, y))


def srgb_to_lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_lin(h):
    h = h.lstrip("#")
    return tuple(srgb_to_lin(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


def hull_material(name, trim, lightmap, intensity, uv_names):
    """壁・床・天井の材質: trim sheet（1 本目の uv）× lightmap（2 本目の uv）× intensity を光らせる（光の計算はしない）。"""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    uv0 = nt.nodes.new("ShaderNodeUVMap"); uv0.uv_map = uv_names[0]
    uv1 = nt.nodes.new("ShaderNodeUVMap"); uv1.uv_map = uv_names[1]
    tb = nt.nodes.new("ShaderNodeTexImage"); tb.image = trim
    nt.links.new(uv0.outputs[0], tb.inputs[0])
    tl = nt.nodes.new("ShaderNodeTexImage"); tl.image = lightmap
    tl.image.colorspace_settings.name = "sRGB"
    nt.links.new(uv1.outputs[0], tl.inputs[0])
    mul = nt.nodes.new("ShaderNodeMix"); mul.data_type = "RGBA"; mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    nt.links.new(tb.outputs["Color"], mul.inputs[6])
    nt.links.new(tl.outputs["Color"], mul.inputs[7])
    nt.links.new(mul.outputs[2], em.inputs["Color"])
    em.inputs["Strength"].default_value = intensity
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


def glow_material(src):
    """光る筋と灯具: glb の emissive の色 × 強さをそのまま光らせる。"""
    p = next(n for n in src.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    m = bpy.data.materials.new(src.name + "_pano")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = p.inputs["Emission Color"].default_value
    em.inputs["Strength"].default_value = p.inputs["Emission Strength"].default_value * GLOW_BOOST
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


def zone_captures(eye):
    """区画ごとの撮る点: 区画のマスを囲む箱の真ん中（x・z）と目の高さ（StageModel.zoneBox の center と同じ）。"""
    d = json.load(open(os.path.join(ROOT, "assets", "maze.stage.json")))
    rows, cs = d["rows"], float(d["cellSize"])
    out = {}
    for z in d["zones"]:
        cells = [(c, r) for r, line in enumerate(rows) for c, ch in enumerate(line) if ch == z["id"]]
        if not cells:
            continue
        xs = [c * cs for c, _ in cells]
        zs = [(len(rows) - 1 - r) * cs for _, r in cells]
        cx, cz = (min(xs) + max(xs) + cs) / 2.0, (min(zs) + max(zs) + cs) / 2.0
        # 部屋はマスの角へ寄せる（灯具はマスの真ん中の真上にあり、真下から撮ると絵の上が白く潰れ、粗い面の映り込みが白っぽくなる）。
        if z["kind"] == "room":
            cx, cz = math.floor(cx / cs) * cs, math.floor(cz / cs) * cs
        out["zone_" + ("lc_" if z["id"].islower() else "") + z["id"]] = (cx, eye, cz)
    return out


def distance_material():
    """目からの距離を明るさにする材質（霧の混ぜ具合を描く 2 回目の描き出しで、全部の物に掛ける）。"""
    m = bpy.data.materials.new("PANO_DISTANCE")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    cam = nt.nodes.new("ShaderNodeCameraData")
    scale = nt.nodes.new("ShaderNodeMath"); scale.operation = "MULTIPLY"; scale.inputs[1].default_value = 0.01
    nt.links.new(cam.outputs["View Distance"], scale.inputs[0])
    nt.links.new(scale.outputs[0], em.inputs["Strength"])
    em.inputs["Color"].default_value = (1, 1, 1, 1)
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


def render_to_array(path):
    sc = bpy.context.scene
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(path)
    px = np.array(img.pixels[:], dtype=np.float32).reshape(HEIGHT, WIDTH, 4)[:, :, :3]
    bpy.data.images.remove(img)
    os.remove(path)
    return px


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    global WIDTH, HEIGHT
    captures = dict(CAPTURES)
    if "--zones" in argv:
        captures = zone_captures(1.65)
        WIDTH, HEIGHT = int(os.environ.get("PANO_W", "1024")), int(os.environ.get("PANO_H", "512"))
    names = [a for a in argv if a in captures] or list(captures)
    look = json.load(open(LOOK))
    manifest = json.load(open(MANIFEST))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=GLB)
    sc = bpy.context.scene
    # trim sheet は M_hull の材質が読む絵（床の標示の絵も glb に入っているので、絵の並びの頭では選ばない）
    hull = next(m for m in bpy.data.materials if m.name.split(".")[0] == "M_hull")
    trim = next(n.image for n in hull.node_tree.nodes if n.type == "TEX_IMAGE" and n.image is not None)
    glow = {}
    # WhyNot: 床の標示と水たまりを描かない — 映り込みの景色の中では数 px の模様で見分けられず、光らせない材質のままだと黒い板に写る。
    transparent = bpy.data.materials.new("PANO_TRANSPARENT")
    transparent.use_nodes = True
    tnt = transparent.node_tree
    tnt.nodes.clear()
    tnt.links.new(tnt.nodes.new("ShaderNodeBsdfTransparent").outputs[0], tnt.nodes.new("ShaderNodeOutputMaterial").inputs[0])
    for ob in [o for o in bpy.data.objects if o.type == "MESH" and o.name.startswith("ZONE_")]:
        zid = ob.name[len("ZONE_"):].split(".")[0]
        lm_rel = manifest["zones"].get(zid, {}).get("lightmap_png")
        lm = bpy.data.images.load(os.path.join(MODELS, lm_rel))
        for slot in ob.material_slots:
            base = slot.material.name.split(".")[0]
            if base in ("M_decal", "M_puddle"):
                slot.material = transparent
            elif base == "M_hull":
                slot.material = hull_material("PANO_" + zid, trim, lm, float(look["lightmapIntensity"]), [u.name for u in ob.data.uv_layers])
            else:
                glow.setdefault(base, glow_material(slot.material))
                slot.material = glow[base]
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = SAMPLES
    sc.cycles.max_bounces = 0
    sc.cycles.use_denoising = False
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.render.resolution_x, sc.render.resolution_y = WIDTH, HEIGHT
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "OPEN_EXR"
    sc.render.image_settings.color_depth = "32"
    world = bpy.data.worlds.new("w"); sc.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[1].default_value = 0.0
    cam_d = bpy.data.cameras.new("pano")
    cam_d.type = "PANO"
    cam_d.panorama_type = "EQUIRECTANGULAR"
    cam_d.clip_start = 0.01
    cam_d.clip_end = 500.0
    cam = bpy.data.objects.new("pano", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    fog = np.array(hex_lin(look["fogColor"]), dtype=np.float32)
    near, far = float(look["fogNear"]), float(look["fogFar"])
    os.makedirs(OUT_DIR, exist_ok=True)
    dist_mat = distance_material()
    for name in names:
        cam.location = ep(*captures[name])
        sc.view_layers[0].material_override = None
        sc.view_settings.view_transform = "Raw"
        sc.view_settings.exposure = 0.0
        lit = render_to_array(os.path.join(HERE, "_pano_lit.exr"))
        sc.view_layers[0].material_override = dist_mat
        sc.cycles.samples = 4
        dist = render_to_array(os.path.join(HERE, "_pano_dist.exr"))[:, :, :1] * 100.0
        sc.cycles.samples = SAMPLES
        dist = np.where(dist <= 0.0, far, dist)
        k = np.clip((dist - near) / max(0.01, far - near), 0.0, 1.0)
        lin = lit * (1.0 - k) + fog * k
        lin = lin * PANO_SCALE
        v = np.clip(lin, 0.0, 1.0)
        srgb = np.where(v <= 0.0031308, v * 12.92, 1.055 * np.power(v, 1 / 2.4) - 0.055)[:, ::-1, :]
        out = bpy.data.images.new("pano_" + name, WIDTH, HEIGHT, alpha=False)
        out.colorspace_settings.name = "Non-Color"
        out.pixels[:] = np.concatenate([srgb, np.ones((HEIGHT, WIDTH, 1), dtype=np.float32)], axis=-1).astype(np.float32).ravel()
        path = os.path.join(OUT_DIR, name + ".png")
        out.filepath_raw = path
        out.file_format = "PNG"
        out.save()
        bpy.data.images.remove(out)
        print("wrote", path, "mean=%.3f clipped=%.2f%%" % (float(srgb.mean()), float((lin.max(-1) > 1.0).mean() * 100)))


main()
