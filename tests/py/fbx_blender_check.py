"""Blender 4.5 check of the FBX export (ROADMAP 78). Run by hand, headless:

  "C:/Program Files/Blender Foundation/Blender 4.5/blender.exe" -b -P tests/py/fbx_blender_check.py -- <file.fbx> <file.glb> <expected.json>

Imports the same clip twice: once with Blender's FBX importer, once with its glTF importer (the .glb). Both armatures are
read at the sampled frames (the expected.json frames of tests/fbx_export_test.gd): every bone's head position in world
space, and the direction of its head-to-tail line. Both are roll-free, so the two importers' bone rolls do not matter.
Bars, stated before the numbers: head within 1 mm, bone direction within 0.5 degrees, same bone names and count.
Prints "ok" / "FAIL" lines; exits 1 on any FAIL. Blender's own importers are the reference here, not the poser's code.
"""
import json
import math
import sys

import bpy
from mathutils import Vector

HEAD_BAR_M = 0.001
DIR_BAR_DEG = 0.5

fails = 0


def check(cond, what):
    global fails
    print(("ok   " if cond else "FAIL ") + what)
    if not cond:
        fails += 1


def first_frame(arm):
    ad = arm.animation_data
    if ad is None or ad.action is None:
        return None
    return int(min(kp.co.x for fc in ad.action.fcurves for kp in fc.keyframe_points))


def import_into(fn, before):
    new = [o for o in bpy.data.objects if o not in before]
    return [o for o in new if o.type == "ARMATURE"]


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    fbx_path, glb_path, exp_path = argv
    exp = json.load(open(exp_path, encoding="utf-8"))
    fps = int(round(float(exp["fps"])))
    frames = int(exp["frames"])

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = fps
    bpy.context.scene.render.fps_base = 1.0

    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=fbx_path)
    arm_f = import_into("fbx", before)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=glb_path)
    arm_g = import_into("glb", before)
    check(len(arm_f) == 1 and len(arm_g) == 1, "each import makes one armature (FBX %d, glb %d)" % (len(arm_f), len(arm_g)))
    if len(arm_f) != 1 or len(arm_g) != 1:
        print("FBX CHECK (Blender): %d failed" % fails)
        sys.exit(1)
    af, ag = arm_f[0], arm_g[0]
    nf = [b.name for b in af.data.bones]
    ng = [b.name for b in ag.data.bones]
    check(nf == ng and len(nf) == 65, "Blender reads the same %d bones from both files (names and order)" % len(nf))
    ff, fg = first_frame(af), first_frame(ag)
    check(ff is not None and fg is not None, "both imports carry an action (FBX first key %s, glb first key %s)" % (ff, fg))
    if ff is None or fg is None:
        print("FBX CHECK (Blender): %d failed" % fails)
        sys.exit(1)
    kf = len(set(round(kp.co.x, 3) for fc in af.animation_data.action.fcurves for kp in fc.keyframe_points))
    check(kf == frames, "the FBX action has %d key times (%d frames expected)" % (kf, frames))

    worst_h = 0.0
    worst_d = 0.0
    bad = []
    moved = 0.0   # the largest head travel of a sampled bone between its first and last sample: not a rest pose
    first_head = {}
    for s in exp["samples"]:
        k = int(s["frame"])
        bone = s["bone"]
        bpy.context.scene.frame_set(ff + k)
        bpy.context.view_layer.update()
        pf = af.pose.bones[bone]
        hf = af.matrix_world @ pf.head
        tf = af.matrix_world @ pf.tail
        bpy.context.scene.frame_set(fg + k)
        bpy.context.view_layer.update()
        pg = ag.pose.bones[bone]
        hg = ag.matrix_world @ pg.head
        tg = ag.matrix_world @ pg.tail
        dh = (hf - hg).length
        dd = 0.0
        if (tf - hf).length > 1e-6 and (tg - hg).length > 1e-6:
            dd = math.degrees((tf - hf).normalized().angle((tg - hg).normalized()))
        worst_h = max(worst_h, dh)
        worst_d = max(worst_d, dd)
        if dh > HEAD_BAR_M or dd > DIR_BAR_DEG:
            bad.append("%s@%d head %.4f m dir %.3f deg" % (bone, k, dh, dd))
        if bone in first_head:
            moved = max(moved, (hf - first_head[bone]).length)
        else:
            first_head[bone] = hf.copy()
    check(not bad and worst_h <= HEAD_BAR_M, "bone heads at the %d sampled frames agree between the two imports: worst %.5f m (bar %.3f m) %s"
          % (len(exp["samples"]), worst_h, HEAD_BAR_M, bad[:3]))
    check(worst_d <= DIR_BAR_DEG, "bone directions agree at those frames: worst %.4f deg (bar %.2f deg)" % (worst_d, DIR_BAR_DEG))
    check(moved > 0.05, "the sampled bones move (largest head travel between their first and last sample %.3f m, bar 0.050 m): the check is not on a rest pose" % moved)
    print("FBX CHECK (Blender): %d failed" % fails)
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
