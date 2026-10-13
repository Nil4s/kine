# Poser math - how every number in a pose file is made

All of it is in `scripts/body.gd` (about 150 lines, no engine magic: Godot is only used to draw and to read the mouse).
`tests/math_test.gd` proves it (round trip, rest = skeleton, elbow/knee direction, limits, mirror).

## Space
Character space, metres: **+Y up, +Z forward (the hero faces +Z), +X = the hero's LEFT**. The same axes as the hero glb
after its root turn (`tools/export_skeleton.py` bakes the root's -90 deg X turn and the 1.12 scale into the rest data).

## The rest body (data/skeleton.json)
For every joint j: `P0[j]` its rest position, `W0[j]` its rest rotation (the glTF node's world rotation), its parent.
The rest pose is the hero's T-pose. A bone runs from its joint to its "end": the next joint down the limb (upper arm
-> elbow), or for hand/ball/head an end point (middle finger base, toe tip, a point above the head).

## Each joint's three axes (data/body_limits.json, fixed at rest)
- `t` = along the bone at rest, joint -> end (unit vector).
- `f` (from the file) squared to the bone: `fo = normalize(f - t (f.t))`; `so = t x fo`, flipped to the file's `s` side.
  (t, fo, so) is an exact right-angle frame.
- **bend axis** `b = t x fo`: a + bend swings the end toward `f`.
- **side axis** `a = t x so`: a + side swings the end toward `s`.
- **twist** turns about `t` itself, right-hand rule (thumb along the bone, fingers curl = +).
Left joints: the right's `f`, `s` with x flipped; their twist range negated (a mirror flips the twist's sign).

## A pose = three angles per joint (bend, side, twist) in degrees, + the hips' offset
The angles become one rotation **A** (a quaternion, in rest axes):

    v      = bend * b + side * a              (radians; v is a rotation vector: direction = axis, length = angle)
    swing  = rotation by |v| about v/|v|
    twist  = rotation by twist about t
    A      = swing * twist                    (twist first, about the bone; then the swing)

Back from A to the angles (`decompose`): the swing-twist split. `twist = normalize(A.w, (A.xyz . t) t)`,
`swing = A * twist^-1`, then bend = rotvec(swing) . b, side = rotvec(swing) . a. Exact both ways (test: 0.00005 deg).
Why a rotation vector and not Euler angles: no gimbal lock (an arm straight up or straight forward is fine), and a pure
bend reads exactly its angle.

## Limits
Each angle is clamped to its [min, max] in body_limits.json (`clamp_ang`). Ranges are a real body's: elbow and knee
0..145 one way only, no forearm twist (our rig has no twist bones: the skin folds), shoulder raise to 90 over the
T-pose (= 180 from the arm down), spine split over 3 bones (60 forward, 21 back, 21 to a side, 51 turn in total).
A part turns yellow at a non-zero end of a range.

## Forward kinematics (FK), root first

    G[pelvis] = A[pelvis]                 P[pelvis] = P0[pelvis] + offset
    G[j]      = G[parent] * A[j]          P[j]      = P[parent] + G[parent] * (P0[j] - P0[parent])
    end[j]    = P[j] + G[j] * (end0[j] - P0[j])

`G[j]` = how far joint j's frame has turned from rest, in the world, now. Because A is written in REST axes, a child's
axes ride on its parent: bend the elbow after raising the arm and it still bends "the elbow way".

## A mouse drag (turn_world)
Dragging a part by `dw` (the mouse move in metres on the camera's plane, `2*dist*tan(fov/2)/screen_height` per pixel):
`R` = the rotation turning (end - joint) onto (end + dw - joint). In the joint's own terms:
`A_new = G[parent]^-1 * R * G[parent] * A_old`, then split back into (bend, side, twist) and clamped. So a drag can
never leave the body's range.

## Back into the game (step 4)
The glTF node's local rotation for a pose: `W[j] = G[j] * W0[j]`, so
`L[j] = W[parent]^-1 * W[j] = W0[parent]^-1 * A[j] * W0[j]` (`gltf_local`). Written as rotation keys into the hero glb
byte-safe (the game repo's tools), the clip plays exactly the pose.

## A saved pose (moves/pose_*.json)
Per joint: `bend, side, twist` (degrees), `A` and `G` (quaternions x,y,z,w), `pos` and `end` (metres), `at_limit`.
Enough to rebuild the pose (angles) AND to check it without running anything (positions).
