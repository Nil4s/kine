# blender -b --factory-startup --python tools/c42_uvcheck.py -- <file.glb|fbx> <out.json>
import bpy, sys, json
a = sys.argv[sys.argv.index("--")+1:]
p, outp = a[0], a[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
if p.lower().endswith(".fbx"):
    bpy.ops.import_scene.fbx(filepath=p)
else:
    bpy.ops.import_scene.gltf(filepath=p)
res = []
for o in bpy.data.objects:
    if o.type != "MESH":
        continue
    me = o.data
    layers = [l.name for l in me.uv_layers]
    d = {"obj": o.name, "layers": layers, "loops": len(me.loops)}
    if len(me.uv_layers) >= 2:
        u = me.uv_layers[1].data
        xs = [l.uv[0] for l in u]
        ys = [l.uv[1] for l in u]
        d["uv1_min"] = [min(xs), min(ys)]
        d["uv1_max"] = [max(xs), max(ys)]
        u0 = me.uv_layers[0].data
        d["differs"] = sum(1 for i in range(len(u)) if abs(u[i].uv[0]-u0[i].uv[0]) > 1e-4 or abs(u[i].uv[1]-u0[i].uv[1]) > 1e-4)
    res.append(d)
json.dump(res, open(outp, "w"))
print("C42RESULT", json.dumps(res))
