"""Compose the layered USD root and the flat export with Pixar's own USD (pip: usd-core), and compare with the app.

Run:  <venv>/Scripts/python.exe -I tests/py/usd_pxr_check.py <dir>
<dir> is the output of:  godot --headless --path . -s tests/usd_pxr_ref.gd -- <dir>
Checks (ROADMAP 79, the pxr numbers):
 (1) the layered root opens, composes (6 sublayers, Kine/Anim and Kine/Skel found), and the skeleton binds its animation
     (UsdSkel: BindingAPI animationSource targets a SkelAnimation; UsdSkel.Cache AnimQuery valid);
 (2) composed rotations (the SkelAnimation at each frame) = the app's pose, all joints, all frames, within 0.01 deg, and the
     3 joints at 3 frames (spine_01, upperarm_r, head at frames 0, 71, 141) within 0.01 deg;
 (3) mute the top layer through the stage's session muting (Usd.Stage.MuteLayer): composed = the app's pose with the fix only;
 (4) mute every layer: composed = the app's pose with no layer;
 (5) the flat export: its skeleton binds its animation (the path that was </Kine/Skel/Anim>, a missing prim, before this fix),
     and its rotations = the app's full pose.
Bars are the same as in tests/usd_layers_test.gd. Exit 0 when every check passes.
"""
import json
import math
import os
import sys

from pxr import Gf, Sdf, Usd, UsdSkel

BAR_DEG = 0.01
FRAMES3 = [0, 71, 141]
JOINTS3 = ["spine_01", "upperarm_r", "head"]
fails = 0


def check(ok, what):
    global fails
    print(("ok   " if ok else "FAIL ") + what)
    if not ok:
        fails += 1


def angle_deg(q, w, x, y, z):
    """rotation angle between quaternion q (Gf.Quatf) and (w, x, y, z), in degrees. The difference quaternion's
    2 * atan2(|vector|, |real|) form: acos(dot) amplifies float32 rounding near identity (1e-7 becomes 0.03 deg)"""
    dq = q * Gf.Quatf(w, Gf.Vec3f(x, y, z)).GetConjugate()
    v = dq.GetImaginary()
    return math.degrees(2.0 * math.atan2(v.GetLength(), abs(dq.GetReal())))


def composed_rot(stage, anim_path, frame):
    """the SkelAnimation's rotations at frame, through the stage's composition (one Gf.Quatf per joint)"""
    anim = UsdSkel.Animation(stage.GetPrimAtPath(anim_path))
    return list(anim.GetRotationsAttr().Get(Usd.TimeCode(frame)))


def joint_index(stage, anim_path, name):
    anim = UsdSkel.Animation(stage.GetPrimAtPath(anim_path))
    for k, j in enumerate(anim.GetJointsAttr().Get()):
        if str(j).split("/")[-1] == name:
            return k
    raise KeyError(name)


def compare(stage, anim_path, ref_frames, joints, label):
    """worst error over all joints and all frames, and over the 3 joints at the 3 frames; both in degrees"""
    worst_all = 0.0
    at_all = ""
    worst3 = 0.0
    at3 = ""
    names = joints
    for f in range(len(ref_frames)):
        rot = composed_rot(stage, anim_path, f)
        for k, jn in enumerate(names):
            w, x, y, z = ref_frames[f][k]
            e = angle_deg(rot[k], w, x, y, z)
            if e > worst_all:
                worst_all, at_all = e, "frame %d %s" % (f, jn)
            if f in FRAMES3 and jn in JOINTS3 and e > worst3:
                worst3, at3 = e, "frame %d %s" % (f, jn)
    check(worst_all <= BAR_DEG, "%s: every joint (%d) every frame (%d): worst %.6f deg (bar %.2f; at %s)" % (label, len(names), len(ref_frames), worst_all, BAR_DEG, at_all))
    check(worst3 <= BAR_DEG, "%s: 3 joints %s at frames %s: worst %.6f deg (bar %.2f; at %s)" % (label, JOINTS3, FRAMES3, worst3, BAR_DEG, at3))


def bind_check(stage, label):
    skel = UsdSkel.Skeleton(stage.GetPrimAtPath("/Kine/Skel"))
    check(skel.GetPrim().IsValid(), "%s: /Kine/Skel is a Skeleton" % label)
    api = UsdSkel.BindingAPI(skel.GetPrim())
    targets = api.GetAnimationSourceRel().GetTargets()
    check(len(targets) == 1, "%s: skel:animationSource lists one target: %s" % (label, [str(t) for t in targets]))
    if targets:
        tgt = stage.GetPrimAtPath(targets[0])
        check(tgt.IsValid() and tgt.IsA(UsdSkel.Animation), "%s: the target %s is a SkelAnimation prim (it exists)" % (label, targets[0]))
    cache = UsdSkel.Cache()
    q = cache.GetSkelQuery(skel)
    aq = q.GetAnimQuery()
    check(aq.GetPrim().IsValid(), "%s: UsdSkel.Cache binds the animation (AnimQuery prim valid: %s)" % (label, aq.GetPrim().GetPath()))
    check(len(aq.GetJointOrder()) == 52, "%s: the bound animation's joint order has %d joints" % (label, len(aq.GetJointOrder())))
    check(len(q.GetJointOrder()) == 52, "%s: the skeleton has %d joints in the bound order" % (label, len(q.GetJointOrder())))


def main():
    d = sys.argv[1]
    ref = json.load(open(os.path.join(d, "ref.json")))
    n = ref["n"]
    cfg = ref["configs"]
    joints = ref["joints"]
    root = os.path.join(d, "usdl_test_usd", "usdl_test.usda")
    stage = Usd.Stage.Open(root)
    check(stage is not None, "layered root opens with pxr: %s" % os.path.basename(root))
    if stage is None:
        return 1
    layers = stage.GetLayerStack(includeSessionLayers=False)
    names = [os.path.basename(l.identifier) for l in layers]
    check(len(layers) == 7, "(1) the stack composes: the root and its 6 sublayers (%d layers): %s" % (len(layers), names))
    check(stage.GetPrimAtPath("/Kine/Anim").IsValid() and stage.GetPrimAtPath("/Kine/Skel").IsValid(), "(1) /Kine/Anim and /Kine/Skel resolve through composition")
    bind_check(stage, "(1) layered root")
    compare(stage, "/Kine/Anim", cfg["full"], joints, "(2) base + top layer = app pose")
    top = [l for l in layers if os.path.basename(l.identifier) == "usdl_test_layer_01_lean.usda"][0]
    fix = [l for l in layers if os.path.basename(l.identifier) == "usdl_test_layer_00_fix.usda"][0]
    top_id = str(top.identifier)   # a plain path string: the mute API takes the layer's identifier as text
    fix_id = str(fix.identifier)
    stage.MuteLayer(top_id)
    check(stage.IsLayerMuted(top_id), "(3) the top layer is muted in the session: %s" % os.path.basename(top_id))
    compare(stage, "/Kine/Anim", cfg["lower"], joints, "(3) top layer muted = app pose with the fix only")
    stage.MuteLayer(fix_id)
    compare(stage, "/Kine/Anim", cfg["none"], joints, "(4) every layer muted = app pose with no layer")
    stage.UnmuteLayer(fix_id)
    stage.UnmuteLayer(top_id)
    compare(stage, "/Kine/Anim", cfg["full"], joints, "(2b) unmuted again = app pose (session mute undone)")
    # (5) the flat export: the same bind, and its rotations = the app's full pose
    flat = Usd.Stage.Open(os.path.join(d, "flat", "combo3.usda"))
    check(flat is not None, "(5) the flat export opens with pxr")
    if flat is not None:
        bind_check(flat, "(5) flat export")
        compare(flat, "/Kine/Anim", cfg["full"], joints, "(5) flat export rotations = app pose")
    print("PXR CHECK %s %d" % ("PASS" if fails == 0 else "FAIL", fails))
    return 0 if fails == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
