"""bvh_blender_check.py (GATES G2): import a poser BVH with Blender's OWN importer and compare every joint's world position
with what the poser computed (tools/export_bvh.gd --check), at the check frames.

    blender -b --factory-startup --python tests/bvh_blender_check.py -- <file.bvh> <check.json> [shot.png]

Blender is Z up; the importer's defaults (forward -Z, up Y) take the poser's Y-up point (x, y, z) to (x, -z, y).
The importer puts BVH frame 0 on Blender frame 1. PASS = every joint within 1 cm on every check frame.
A mutation control: the same comparison one frame off must FAIL (the check can see a wrong frame).
"""
import bpy, json, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
bvh, chk = argv[0], argv[1]
shot = argv[2] if len(argv) > 2 else ""
check = json.load(open(chk))
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_anim.bvh(filepath=bvh, global_scale=1.0, frame_start=1, use_fps_scale=False,
                        update_scene_fps=True, update_scene_duration=True, rotate_mode="NATIVE")
arm = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
sc = bpy.context.scene


def worst_at(bvh_frame, want):
    sc.frame_set(bvh_frame + 1)
    w, wj = 0.0, ""
    for j, p in want.items():
        pb = arm.pose.bones.get(j)
        if pb is None:
            return float("inf"), "missing bone " + j
        got = arm.matrix_world @ pb.head
        d = (got - Vector((p[0], -p[2], p[1]))).length
        if d > w:
            w, wj = d, j
    return w, wj


fails = 0
frames = sorted(check["frames"], key=int)
print("bones %d, scene fps %d, frames %d-%d" % (len(arm.pose.bones), sc.render.fps, sc.frame_start, sc.frame_end))
for f in frames:
    w, wj = worst_at(int(f), check["frames"][f])
    ok = w < 0.01
    fails += 0 if ok else 1
    print("%s frame %4s: worst %.4f mm (%s)" % ("ok  " if ok else "FAIL", f, w * 1000, wj))
f = frames[2]
w, wj = worst_at(int(f) + 1, check["frames"][f])
print("%s control: frame %s read one frame late: worst %.1f mm (must be > 10)" % ("ok  " if w > 0.01 else "FAIL", f, w * 1000))
fails += 0 if w > 0.01 else 1
if shot:
    # background Blender cannot draw an armature, so each bone becomes a tube (head -> tail) and Workbench renders it
    sc.frame_set(int(frames[2]) + 1)
    for pb in arm.pose.bones:
        cu = bpy.data.curves.new(pb.name, "CURVE")
        cu.dimensions = "3D"
        cu.bevel_depth = 0.006 if any(k in pb.name for k in ("thumb", "index", "middle", "ring", "pinky")) else 0.018
        sp = cu.splines.new("POLY")
        sp.points.add(1)
        for k, v in enumerate((arm.matrix_world @ pb.head, arm.matrix_world @ pb.tail)):
            sp.points[k].co = (v.x, v.y, v.z, 1.0)
        sc.collection.objects.link(bpy.data.objects.new(pb.name + "_tube", cu))
    bpy.ops.mesh.primitive_plane_add(size=4)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.location = (2.6, -3.4, 1.7)
    cam.rotation_euler = (1.3, 0, 0.65)
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.show_shadows = True
    sc.render.resolution_x, sc.render.resolution_y = 700, 700
    sc.render.filepath = shot
    bpy.ops.render.render(write_still=True)
print("BVH BLENDER %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
sys.exit(1 if fails else 0)
