# blender -b --factory-startup --python tests/c48_blender.py -- <file.glb> <out.json>
# C48: import the joints .glb, read the stated axis from the node's extras, rotate THAT node about it around its origin, measure.
import bpy, sys, json, math
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:]
glb, outp = argv[0], argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)


def conv(v):   # glTF Y-up -> Blender Z-up, what the importer applies
    return Vector((v[0], -v[2], v[1]))


def wverts(o):
    return [o.matrix_world @ v.co for v in o.data.vertices]


hinge = None
for o in bpy.data.objects:
    if "kine_joint" in o.keys():
        hinge = o
res = {"found": hinge is not None}
if hinge is not None:
    kj = hinge["kine_joint"]
    axis_file = [float(x) for x in kj["axis"]]
    res["axis_file"] = axis_file
    res["type"] = str(kj["type"])
    res["upper_deg"] = float(kj["upper_deg"])
    p = hinge.matrix_world.translation.copy()
    res["pivot_world"] = [p.x, p.y, p.z]
    kids = set()

    def walk(o):
        for c in o.children:
            kids.add(c.name)
            walk(c)
    walk(hinge)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    before = {o.name: wverts(o) for o in meshes}
    ax = conv(axis_file).normalized()
    th = math.radians(30.0)
    R = Matrix.Rotation(th, 4, ax)
    hinge.matrix_world = Matrix.Translation(p) @ R @ Matrix.Translation(-p) @ hinge.matrix_world
    bpy.context.view_layer.update()
    after = {o.name: wverts(o) for o in meshes}
    wrong = Matrix.Rotation(th, 4, conv([1, 0, 0]).normalized())
    err_ok = 0.0
    err_wrong = 0.0
    moved = 0.0
    other = 0.0
    n_moving = 0
    for o in meshes:
        for b, a in zip(before[o.name], after[o.name]):
            if o.name in kids:
                n_moving += 1
                err_ok = max(err_ok, (a - (p + R.to_3x3() @ (b - p))).length)
                err_wrong = max(err_wrong, (a - (p + wrong.to_3x3() @ (b - p))).length)
                moved = max(moved, (a - b).length)
            else:
                other = max(other, (a - b).length)
    res.update({"err_ok": err_ok, "err_wrong": err_wrong, "moved": moved, "other_delta": other, "n_moving": n_moving,
                "n_meshes": len(meshes), "n_static": len(meshes) - len([o for o in meshes if o.name in kids]),
                "pivot_after": [hinge.matrix_world.translation.x, hinge.matrix_world.translation.y, hinge.matrix_world.translation.z]})
json.dump(res, open(outp, "w"))
