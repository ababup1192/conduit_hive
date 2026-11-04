# 床に落ちているピックアップの銃（骨なし・刻みを省いた形）を assets/models/pickup_<銃>.glb へ書き出す。
#   cd modeling && devbox run -- blender -b --factory-startup --python pickups.py [-- shotgun rifle]
# 左の面を上にして寝かせ、原点は床の上の真ん中（engine の y = 0 が床）。長い向きは Blender の Y（engine の Z）。
import bpy, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mathutils import Vector
import vmlib as V
import guns

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
KINDS = [a for a in args if a in ("shotgun", "rifle")] or ["shotgun", "rifle"]

for kind in KINDS:
    V.reset()
    gun = guns.BUILD[kind](lod=0)
    objs = [o for o, _ in gun["parts"]]
    V.transform(objs, V.xf((0, 0, 0), (0, -90, 0)))
    pts = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    V.transform(objs, V.xf((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)))
    body = V.join(objs, "pickup_" + kind)
    tris = V.tri_count([body])
    V.harden_normals(body)
    V.unwrap(body, margin=0.008)
    # 床の板と一緒にベイクする: 床に触れる所が暗くなる。板は書き出さない
    bpy.ops.mesh.primitive_plane_add(size=3, location=(0, 0, -0.0005))
    floor = bpy.context.active_object
    V.bake_atlas(body, 512, "pk_" + kind)
    bpy.data.objects.remove(floor, do_unlink=True)
    out = os.path.join(V.OUT, "pickup_%s.glb" % kind)
    V.export_glb(out, animations=False)
    size = hi - lo
    print("pickup %s tris=%d size(Blender x,y,z)=%.3f %.3f %.3f" % (kind, tris, size.x, size.y, size.z))
