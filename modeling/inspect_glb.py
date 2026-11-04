# glb の中身を出す（Blender は要らない）: ノード・骨の数・クリップと長さ・三角形の数・材質・絵の大きさ。
#   DEVELOPER_DIR=/Library/Developer/CommandLineTools python3 modeling/inspect_glb.py assets/models/*.glb
import json, struct, sys, os


def read_glb(path):
    data = open(path, "rb").read()
    jlen = struct.unpack("<I", data[12:16])[0]
    doc = json.loads(data[20:20 + jlen])
    rest = data[20 + jlen:]
    blen = struct.unpack("<I", rest[:4])[0]
    return doc, rest[8:8 + blen]


def png_size(b):
    return struct.unpack(">II", b[16:24]) if b[:8] == b"\x89PNG\r\n\x1a\n" else None


for path in sys.argv[1:]:
    doc, bin_ = read_glb(path)
    acc = doc.get("accessors", [])
    tris = 0
    for m in doc.get("meshes", []):
        for p in m["primitives"]:
            tris += acc[p["indices"]]["count"] // 3 if "indices" in p else acc[p["attributes"]["POSITION"]]["count"] // 3
    joints = {n for s in doc.get("skins", []) for n in s["joints"]}
    names = [n.get("name", "?") for n in doc["nodes"]]
    print("== %s  (%d KB)" % (os.path.basename(path), os.path.getsize(path) // 1024))
    print("  tris=%d  joints=%d  meshes=%d" % (tris, len(joints), len(doc.get("meshes", []))))
    print("  nodes:", ", ".join(n + ("*" if i in joints else "") for i, n in enumerate(names)))
    for a in doc.get("animations", []):
        t = max(acc[s["input"]]["max"][0] for s in a["samplers"])
        targets = {doc["nodes"][c["target"]["node"]].get("name") for c in a["channels"]}
        print("  clip %-7s %.3f s  channels=%d  nodes=%d" % (a["name"], t, len(a["channels"]), len(targets)))
    for m in doc.get("materials", []):
        pbr = m.get("pbrMetallicRoughness", {})
        print("  material %s: baseTex=%s factor=%s emissive=%s strength=%s" % (
            m.get("name"), "baseColorTexture" in pbr, [round(x, 3) for x in pbr.get("baseColorFactor", [1, 1, 1, 1])],
            m.get("emissiveFactor"), m.get("extensions", {}).get("KHR_materials_emissive_strength", {}).get("emissiveStrength")))
    for im in doc.get("images", []):
        bv = doc["bufferViews"][im["bufferView"]]
        b = bin_[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]
        print("  image %s %s %s" % (im.get("name"), im.get("mimeType"), png_size(b)))
    # engine の Gltf が Err にする・捨てる物（Gltf.flix の頭の doc）
    problems = []
    for m in doc.get("meshes", []):
        for p in m["primitives"]:
            if p.get("mode", 4) != 4:
                problems.append("三角形でない primitive")
            if "JOINTS_1" in p["attributes"] or "WEIGHTS_1" in p["attributes"]:
                problems.append("JOINTS_1 / WEIGHTS_1")
    if any("sparse" in a for a in acc):
        problems.append("sparse accessor")
    if any("uri" in b for b in doc.get("buffers", [])) or any("uri" in im for im in doc.get("images", [])):
        problems.append("外の uri")
    if len(joints) > 64:
        problems.append("ジョイント 64 本超え")
    for a in doc.get("animations", []):
        for c in a["channels"]:
            if c["target"]["node"] not in joints:
                problems.append("ジョイントでないノードを動かす欄: %s" % doc["nodes"][c["target"]["node"]].get("name"))
        if any(s.get("interpolation") == "CUBICSPLINE" for s in a["samplers"]):
            problems.append("CUBICSPLINE")
    if "KHR_texture_transform" in doc.get("extensionsUsed", []):
        problems.append("KHR_texture_transform")
    print("  extensionsUsed:", doc.get("extensionsUsed", []), " engine で引っかかる物:", sorted(set(problems)) or "なし")
    for i, n in enumerate(doc["nodes"]):
        if n.get("name") == "MUZZLE":
            par = next((names[j] for j, p in enumerate(doc["nodes"]) if i in p.get("children", [])), None)
            print("  MUZZLE parent=%s translation=%s rotation=%s" % (par, [round(x, 4) for x in n.get("translation", [0, 0, 0])],
                                                                   [round(x, 4) for x in n.get("rotation", [0, 0, 0, 1])]))
