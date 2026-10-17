# "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe" -b --factory-startup --python tools/blender_check.py
# (GATES OO3, step 2 of 2, after tools/blender_expect.gd). Blender's OWN glTF importer reads each .glb: one armature, our
# bone names, one key per frame, every bone head within 1 cm of check.json at 4 frames (Y-up -> Z-up). Then the FBX route:
# Blender writes .fbx (every frame baked over the scene range, no simplifying) and reads it back: same bones, same frames.
# Writes blender_report.txt. OO3_SHIFT=1 reads every frame one late (the anti-vacuity stub: it must fail).
import bpy, json, os, math
D = os.environ.get("OO3_DIR", "C:/Temp/oo3")
SHIFT = int(os.environ.get("OO3_SHIFT", "0"))   # the anti-vacuity stub: read every frame one late
chk = json.load(open(D + "/check.json"))
UE5 = None
worst = 0.0
where = ""
lines = []
bad = 0

def empty():
    bpy.ops.wm.read_factory_settings(use_empty=True)

for sn in sorted(chk):
    c = chk[sn]
    empty()
    bpy.context.scene.render.fps = int(c["fps"])
    bpy.ops.import_scene.gltf(filepath="%s/%s.glb" % (D, sn))
    arms = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
    if len(arms) != 1:
        lines.append("FAIL %s: %d armatures" % (sn, len(arms))); bad += 1; continue
    arm = arms[0]
    names = [b.name for b in arm.data.bones]
    act = arm.animation_data.action if arm.animation_data else None
    if act is None:
        lines.append("FAIL %s: no action on the armature" % sn); bad += 1; continue
    f0, f1 = act.frame_range
    # frames = the keys on the hips' rotation (a scene's length need not be whole frames: combo3's last key is 140.1)
    fc = [f for f in act.fcurves if 'pelvis' in f.data_path and 'rotation' in f.data_path]
    nfr = len(fc[0].keyframe_points) if fc else -1
    want_names = set(c["check"]["0"].keys())
    missing = sorted(want_names - set(names))
    w = 0.0
    at = ""
    for i, js in c["check"].items():
        bpy.context.scene.frame_set(int(round(f0)) + int(i) + SHIFT)
        bpy.context.view_layer.update()
        for j, p in js.items():
            pb = arm.pose.bones.get(j)
            if pb is None:
                continue
            h = arm.matrix_world @ pb.head
            e = (p[0], -p[2], p[1])   # glTF Y-up -> Blender Z-up
            d = math.dist((h.x, h.y, h.z), e)
            if d > w:
                w, at = d, "frame %s %s" % (i, j)
    ok = (not missing) and nfr == c["frames"] and w <= 0.01
    bad += 0 if ok else 1
    if w > worst:
        worst, where = w, "%s %s" % (sn, at)
    lines.append("%s %s: %d bones (ours missing: %s), action %d frames (scene %d), bone heads worst %.4f m (%s)" % (
        "ok  " if ok else "FAIL", sn, len(names), missing, nfr, c["frames"], w, at))
    # the FBX route: Blender writes it, Blender reads it back
    fbx = "%s/%s.fbx" % (D, sn)
    # FBX bakes whole frames over the scene's range: round the end UP so a last key between frames is kept (held)
    bpy.context.scene.frame_start = int(math.floor(f0))
    bpy.context.scene.frame_end = int(math.ceil(f1 - 1e-6))
    bpy.ops.export_scene.fbx(filepath=fbx, bake_anim=True, bake_anim_simplify_factor=0.0, bake_anim_use_all_actions=False, bake_anim_use_nla_strips=False, add_leaf_bones=False)
    empty()
    bpy.context.scene.render.fps = int(c["fps"])
    bpy.ops.import_scene.fbx(filepath=fbx)
    arms2 = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"]
    a2 = arms2[0].animation_data.action if arms2 and arms2[0].animation_data else None
    fc2 = [f for f in a2.fcurves if 'pelvis' in f.data_path and 'rotation' in f.data_path] if a2 else []
    n2 = len(fc2[0].keyframe_points) if fc2 else -1
    okf = os.path.getsize(fbx) > 0 and n2 == c["frames"] and len(arms2[0].data.bones) == len(names)
    bad += 0 if okf else 1
    lines.append("%s %s.fbx: %d bytes, re-imported: %d bones, %d frames" % ("ok  " if okf else "FAIL", sn, os.path.getsize(fbx), len(arms2[0].data.bones) if arms2 else -1, n2))

lines.append("OO3 BLENDER %s: %d failed; bone heads worst %.4f m (%s)" % (bpy.app.version_string, bad, worst, where))
open(D + "/blender_report.txt", "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
