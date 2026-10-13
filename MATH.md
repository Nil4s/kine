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

## Collision (step 2)
Every part is a capsule: two end points carried by its joint (`cap = P[j] + G[j] * (cap0 - P0[j])`) and a radius. The
radii come from the mannequin's own mesh (`tools/export_skeleton.py`): a limb = the 80th percentile distance of its
vertices from the bone; the trunk (pelvis, spine 1-3) = a LEFT-RIGHT capsule fitted to a horizontal slice of the mesh
(radius = half the chest's depth), because a chest is wide, not deep. Clavicles are clamped to 6 cm.
- Depth of two capsules: `rA + rB - (shortest distance between their segments)` (Ericson 5.1.9); > 0 = inside.
- Some parts already overlap in the body's NEUTRAL poses (T-pose, arms down): the shoulder sits in the chest, a hanging
  arm rests on the thigh. Each pair's **allowance** = its deepest overlap in those poses + 2 mm (0 if it never touches).
  A **contact** = sinking deeper than the allowance.
- `set_ang_safe`: a new angle that makes the total contact depth grow is cut back to where it touches (10 halvings
  along the way from the old angles to the new). Sliders, drags, snaps and reaches all go through it: a part can
  never be pushed into the body. Red = stopped against another part.

## Reach (drag a hand or foot)
Two joints in turns, 6 rounds: the elbow/knee bend is found by halving (the shoulder->wrist distance falls as the bend
grows) to match the shoulder->target distance; then the shoulder/hip turns the wrist onto the target (turn_world).
Limits and contacts apply at every step, so a hand dragged into the chest stops on it.

## Moves (animations, transitions) - scripts/moves.gd
Keys = poses at times. Between key i (t0) and i+1 (t1): `u = (t - t0)/(t1 - t0)`, `e = u*u*(3 - 2u)` (ease in and
out), every ANGLE = lerp(key i, key i+1, e), the hips' offset too. Angles blend inside their ranges, so every
in-between is a legal pose by construction; contacts in between are listed per frame in the saved move's
`bad_frames` (never hidden).

## Fingers
15 joints per hand (thumb/index/middle/ring/pinky x base/middle/tip), same three-angle math as every joint. Limits in
data/body_limits.json as `finger_01..03` (all four fingers) and `thumb_01..03`. Shapes (`Body.hand_shape`): open / grip
(round a 3.2 cm bat handle) / fist; the thumb values were found by search (thumb tip 4-5 mm from its target).
Fingers don't collide (they wrap round things); their capsules exist for clicking.

## The weapon (metal bat, 0.84 m)
A rigid object with its own frame: knob at the origin, the bat along +Y. Two capsules: handle (r 1.6 cm, knob to 48%)
and barrel (r 3.3 cm).
- FREE: world knob position `pos` + rotation `rot`. Drags move/turn it and stop at the body (same bisection as joints).
- LOCK to hand h, where it is now:  `lrot = G[h]^-1 * rot`,  `lpos = G[h]^-1 * (pos - P[h])`.
  From then on:  `rot = G[h] * lrot`,  `pos = P[h] + G[h] * lpos`  -> it rides the hand through every pose and move.
- In a move, two keys with the bat in the same hand blend its place in the hand: lerp(lpos), slerp(lrot), same ease.
- The other hand (2-hand grip) = reach() of its wrist to a point `grip_m` metres up the bat.
Pose files store it under "weapon": knob, tip, rot, hand, local_pos, local_rot.
