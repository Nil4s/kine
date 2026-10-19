# How Blender implements character IK (learned from source, for Kine)

Source snapshot: Blender `main`, commit b1d561a (sparse clone at `C:\Users\Nick\Tools\ref\blender`). Rigify reference: GitHub mirror `blender/blender-addons` `rigify/` (4.1-era, saved under `C:\Users\Nick\Tools\ref\rigify`; Rigify itself now lives in the extensions repo, whose clone hung, so this is the older copy of the same snap code).
Blender is GPL. This file describes algorithms in my own words. Nothing here is copied code. Re-implement from the math, do not paste.

Paths below are relative to the clone root. Abbreviations: `QJS` = `intern/iksolver/intern/IK_QJacobianSolver.cpp`, `QJ` = `IK_QJacobian.cpp`, `QT` = `IK_QTask.cpp`, `QS` = `IK_QSegment.cpp`, `PLUG` = `source/blender/ikplugin/intern/iksolver_plugin.cc`.

---------------------------------------------------------------------

## a. The default "Standard" solver (intern/iksolver)

### How Blender does it
- It is an iterative Jacobian method with a pseudo-inverse computed by SVD, using **SDLS (selectively damped least squares)** by default (`m_sdls(true)`, QJ:13; DLS also exists as `InvertDLS` but is not selected unless the flag is cleared). Not Jacobian transpose, not CCD, not FABRIK.
- Each outer iteration:
  1. Update forward kinematics for the whole chain (QJS:313).
  2. Each task fills its block of the Jacobian J (3 rows per position task, 3 per orientation task) and the error vector beta (QT:38-71, 89-121).
     - Position task: beta = goal - tip, **clamped in length to a "clamp length" = (sum of every segment's max extension) / (2 * segment count)** (QT:23-36, 43-48). So a far target is approached in bounded steps, never one huge jump.
     - Position Jacobian column for a rotational DoF with world axis a at joint position p: `(p - tip) x a`  (QT:57-67). Orientation column = the axis itself.
     - Orientation error = the axial vector of the rotation difference, `-0.5*(R32-R23, R13-R31, R21-R12)` of (goal * current^T)^T (QT:94-99), i.e. small-angle rotation error.
  3. Invert J with a Jacobi SVD (Eigen) of the small matrix. If rows < DoFs, it decomposes the transpose instead so matrices stay small (QJ:44-67, 86-112).
  4. SDLS (QJ:190-310): for every singular value w_i above 1e-10 compute the projected error alpha_i = (u_i . beta)/w_i, the candidate step v_i*alpha_i, and a per-singular-vector damping so that no joint's candidate step exceeds a gamma. gamma starts at pi/4 (max_angle_change) and is reduced when the singular direction is "expensive" (N<M test, QJ:272-274). The accepted contribution is scaled by **0.80** ("so oscillation can still converge for joint limits", QJ:279-286). The summed dTheta is multiplied by the per-DoF weight (stiffness), and if any |dTheta| still exceeds pi/4 the whole vector is scaled by `pi/4 / (pi/4 + max)` (QJ:303-309).
  5. Joint limits (inner loop, below).
  6. Convergence test.
- There is a secondary-task mechanism (null-space projection of the primary solution) used for lower-priority tasks (QJ:114-188). The plugin only adds primary tasks (pos, rot) so you can ignore it.

### Joint limits, locks, stiffness (how they enter)
- Segment type is chosen from the bone's un-locked DoF mask (`CreateSegment`, IK_Solver.cpp ~L40-100): 1 DoF = revolute about X/Y/Z; 2 DoF = "swing" (X+Z) or "elbow" (X or Z plus Y twist); 3 DoF = spherical; 0 DoF = null segment. A bone with ik-stretch gets an extra translation-along-Y DoF.
- **Locks** (`lock_ik_x/y/z`) just remove that DoF from the segment (PLUG:318-328). They are not a limit, the column simply does not exist.
- **Limits** (`use_ik_limit_*`, `ik_min/max_*`, radians, ranges -pi..0 and 0..pi, defaults -pi/+pi, rna_pose.cc:1128-1170) are applied **after** each unconstrained step, not inside the linear solve:
  - Compute the proposed new angle(s). If out of range, record the violation delta = limit - current.
  - Violations whose clamp delta is ~0 (already on the limit) are **locked immediately**; of the remaining violators only the **most violating one** (it picks the smallest |delta|, QJS:250-281) is locked per pass.
  - Locking = subtract that DoF's contribution from beta (`beta -= J_col*delta`), zero its Jacobian column, and re-invert (QJ:389-400). Repeat the inner `do { Invert; UpdateAngles } while (locked)` loop (QJS:329-343) until a pass locks nothing, then apply the angles. Locks are released at the end of the outer iteration (QJS:346-349). This is an active-set method: clamp one joint at a time, re-solve for the rest.
  - Spherical joints: X and Z swing limits are an **ellipse** in (sin(angle/2)) parameter space (`EllipseClamp`, QS:295, SetLimit QS:172-206), Y (twist) is a plain interval.
- **Stiffness** (`ik_stiffness_*`, 0..0.99): weight = 1 - stiffness (IK_Solver.cpp:216-250, stiffness capped at 0.99). The weight scales that joint's column going in (sqrt) and its dTheta coming out (QJ:77-84, 296). A stiff joint moves less, others take up the slack. Not a hard lock.

### Chain length / chain selection
- `chain_count` (rna "Chain Length", 0..255; 0 = all the way to the root, rna_constraint.cc:1315-1323). The plugin walks from the tip bone up through `parent` until it has `chain_count` bones or reaches the top (PLUG:87-98).
- `use_tail` (default True): if off, the chain starts at the tip bone's **parent**, i.e. the IK end effector is the bone's **head** not its tail (PLUG:83-85). If on, the effector is the **tail** of the owning bone.
- The IK constraint sits on the **tip bone**. Several constraints sharing a root form one "tree" (multi-effector), bones in common are shared (PLUG:103-210). Only one active IK constraint per bone is honoured (PLUG:217-221).

### Numbers / defaults
| item | value | where |
|---|---|---|
| iterations (max) | **500** default, range 0..10000 | constraint.cc `kinematic_new_data` L1367-1376; rna_constraint.cc:1277-1280 |
| convergence | stop when max normalised angle update < **1e-3**, but only after more than **10** iterations | QJS:356-359 |
| tolerance arg | the `tolerance` passed to `IK_Solve` (0.0) is **ignored** (commented out in the signature) | QJS:297 |
| SDLS max angle step | pi/4 per joint per iteration | QJ:208 |
| SDLS step scale | 0.80 | QJ:286 |
| singular value cutoff | 1e-10 | QJ:209 |
| position clamp length | sum(max extension)/(2*N) | QT:23-36 |
| normalisation | whole problem scaled so total chain extension = 1, un-scaled afterwards | QJS:22-53, 300-366 |
| weight (position) | default 1.0, range 0.01..1 | constraint.cc L1371; rna_constraint.cc:1301 |
| orient_weight | default 1.0, range 0.01..1 | constraint.cc L1372; rna_constraint.cc:1307 |
| pole_angle | default 0, range -pi..pi | rna_constraint.cc:1294 |
| default flags | tip + stretch + position-goal on; rotation goal off | constraint.cc L1375 |
| stretch stiffness | `1 - ik_stretch^2` (ik_stretch 0..1 per bone; default 0) | PLUG:403-408 |

"How it stops early": only the norm test above (after iteration 11). Otherwise it runs all 500 iterations and returns "not solved" without error. It silently settles at the closest reachable pose for unreachable targets (the clamp length plus SDLS damping make it creep toward the target and stop at full extension). There is no explicit reach test.

### Source (file:line)
`QJS:295-371` Solve loop; `QJS:240-293` limit/lock pass; `QJ:86-112, 190-310` SVD+SDLS; `QJ:389-418` Lock and update norm; `QT:38-121` Jacobian rows; `QS:172-343` spherical segment limits; `QS:389-460` revolute; `IK_Solver.cpp:40-100, 188-250, 426-446` segment creation, limit, stiffness, entry; `PLUG:67-223` chain discovery; `PLUG:288-577` execute.

### What this means for Kine
- Our CCD-like `reach(tip, target)` with 6 iterations is a cheap approximation. Blender converges because it is *damped Newton on the full chain* with a per-step cap, not because it iterates a lot. A 2-bone limb does not need SVD: for exactly two segments (+ pole) a closed-form law-of-cosines solve is exact and branch-free, and is the right primary solver for arm/leg. Keep a general iterative solver (damped least squares, see below) only for spines, tails, fingers and 3+ bone chains.
- If we implement the general solver: use **damped least squares with a per-step angle cap (pi/4) and a step scale around 0.8**, clamp the error vector to ~(chain length / (2*N)) per iteration, stop at norm < 1e-3 rad after a minimum number of iterations, and make the max iteration count small (10-30) for interactive dragging since we warm-start from the current pose (Blender also warm-starts, see f).
- Joint limits: mimic the active-set trick (clamp the worst violator, freeze it, re-solve the rest) rather than clamping after the fact; clamping every joint independently each iteration is what makes CCD/Jacobian solvers jitter at limits.
- Our "collision-safe joint setting" fits naturally as a post-clamp stage in the same place Blender puts limits (after proposing a step, before applying it): treat a collision-rejected joint like a joint on its limit, lock its DoF and re-solve the rest.
- Expose per-bone: lock X/Y/Z, min/max per axis, and stiffness 0..0.99 (weight = 1 - stiffness). Those are exactly the controls animators expect.
- "Not reachable" should not be an error: the target just stretches out fully.

---------------------------------------------------------------------

## b. Pole target (the math)

### How Blender does it
Pole handling is a **pre-rotation of the whole chain about the root**, done before the Jacobian iterations, not part of the iteration. The solver does not otherwise know about the pole.
1. Disabled if there are >= 2 position tasks (QJS:171-184).
2. Forward-kinematics the chain at its starting pose. `rootpos` = start of the root segment, `endpos` = current tip (end of the tip segment), `rootbasis` = the root segment's current world orientation (QJS:187-191).
3. Current chain plane, as a look-at frame:
   - `dir` = normalise(endpos - rootpos).
   - `up` = root bone's local X axis * cos(pole_angle) + root bone's local Z axis * sin(pole_angle) (QJS:197-199). This is how the pole angle enters: it spins the "which side the knee/elbow bends toward" direction around the bone's own Y axis. pole_angle = 0 means local +X is the bend-side reference.
   - Frame M: row0 = normalise(dir x up); row1 = row0 x dir; row2 = -dir (QJS:207-209).
4. Desired plane frame, from the goal and pole target positions:
   - `poledir` = normalise(goal - rootpos) (this is the direction the chain is about to point; the plugin uses the *goal*, not the current tip, so the whole chain is pre-turned toward the target) (QJS:202).
   - `poleup` = normalise(polegoal - rootpos).
   - Frame P built exactly like M with (poledir, poleup) (QJS:211-213).
5. Correction rotation R = P^T * M (transpose used instead of inverse because both are orthonormal; safe at singularities) is prepended to the root matrix (QJS:229-236). Solver iterations then run with this as the chain's base frame, and at the end the root segment's basis gets the same rotation prepended (QJS:306, 362-364).
6. Net effect: the chain is first rigidly rotated about the root so that (a) it points at the goal and (b) its "up" direction (local X/Z mix chosen by pole_angle) lies in the plane containing root, goal and pole target. The iterative solver then bends the joints (elbow/knee) into that plane, because starting from a bent state in that plane the minimum-change Jacobian steps keep it there.
- There is also a "get angle" mode (`CONSTRAINT_IK_GETANGLE`, QJS:215-227) that computes the pole angle needed so that the current pose points at the pole; it is the "Pole angle: auto" helper. It takes the angle between the two `row1` vectors and fixes the sign by testing against the root Z axis.

### Pole + influence
When a pole target exists Blender blends **the result** (each joint's basis change slerped from identity by influence) instead of blending the target, because target blending is not smooth through a pole flip (PLUG:467-471, 565-568).

### Numbers / defaults
pole_angle: radians, default 0, range [-pi, pi]. Pole target is any bone/object. No distance parameter: only direction from the root matters, so pole target distance does not change the solution.

### Source
`QJS:150-159` (SetPoleVectorConstraint), `QJS:161-238` (ConstrainPoleVector), `QJS:306, 362-364` (call + final application), `PLUG:454-477, 506-512`, `rna_constraint.cc:1285-1299`.

### What this means for Kine
- For a closed-form two-bone limb the Blender math collapses to: bend plane = plane through (root, target, pole). Compute `axis = normalize(target - root)`, `side = normalize(pole - root)` projected perpendicular to axis; the knee/elbow goes in the direction `side` rotated about `axis` by pole_angle. Do not just copy Blender's frame-product form; the plane is the entire idea.
- pole_angle is needed because bone rolls differ per rig: it is the rotation about the bone's long axis that makes "forward bend" line up with the rig's hinge axis. For Kine, we can auto-compute it at rig-setup time (Blender's GETANGLE; Rigify's `compute_pole_angle` does a similar one-off, see e). Store it per limb, default 0 plus auto-calibrate.
- Pole is a new key-able object: a 3D position (in the same space as the IK target, ideally parented to the body or "world") with a "pole on/off" toggle. Default pole position when enabled: root + (elbow offset) i.e. the current knee/elbow position projected out from the chain (Rigify: `compute_elbow_vector` = component of the lower-bone vector perpendicular to the root->tip line, scaled by chain length, ref e).
- Beware: when the target passes through the line root->pole the plane flips. Blender does not hide this; it just says the pole target should not be in line with the chain. Offer a visible warning or clamp.

---------------------------------------------------------------------

## c. IK constraint parameters (bKinematicConstraint) and influence blending

### How Blender does it / meaning
Struct: `source/blender/makesdna/DNA_constraint_types.h:744-775`, flags L444-465, defaults `constraint.cc:1367-1376`, RNA names `rna_constraint.cc:1277-1390`.
| RNA name | DNA field | meaning |
|---|---|---|
| target / subtarget | tar, subtarget | bone/object the tip chases |
| `use_tail` | flag TIP, default True | effector at tail of owner bone; off = head (chain starts at parent) |
| `chain_count` | rootbone, 0..255 | bones in chain; 0 = up to root. Not animatable (changes dependency graph) |
| `use_stretch` | flag STRETCH, default True | allow bones to scale along Y during IK, per bone via `ik_stretch` (0..1, default 0, so on by default but inert unless a bone has ik_stretch>0) |
| `iterations` | iterations, default 500 | max solver iterations |
| `weight` | weight, 0.01..1, default 1 | position-goal weight; matters only when several effectors share a tree |
| `orient_weight` / `use_rotation` | orientweight, flag ROT | also match target orientation (adds a 3-row orientation task) |
| `use_location` | flag POS | enable position goal (default on) |
| `pole_target`, `pole_subtarget`, `pole_angle` | poletar, polesubtarget, poleangle | see b |
| `influence` | `bConstraint.enforce` (generic constraint slider, 0..1) | blend IK vs the pose before IK |
| lock axis / reference_axis options (NO_POS_*, NO_ROT_*, TARGETAXIS) | flags | restrict which target axes count (little used) |

### Influence: how IK blends with the pre-IK (FK/animated) pose
It is **not** a blend of final matrices. Two cases (PLUG:479-502 and 565-568):
- **No pole target:** the *target* is blended. The IK goal becomes `lerp(current tip position, target position, influence)` and goal rotation = quaternion slerp between the current tip orientation and target orientation by (1 - influence from the target side). Then the solver reaches this blended goal. At influence 0 the goal equals where the tip already is, so nothing moves. The current tip is computed from the FK/animated pose (the "end_pose" = pose_mat with tail position).
- **With pole target:** the goal is not blended; instead after solving, each bone's IK basis change is interpolated from identity toward the solved change by influence (`blend_m3_m3m3`).
- If a constraint has influence ~0 (or is muted/off) the whole tree is skipped and the bones keep their FK pose (PLUG:622-629, 641-644).
- Starting state of each iteration is the pose **after** animation/FK/other constraints (the bone's current transform is the "basis" the solver starts from, PLUG:347-387). So IK is "FK pose + correction", which is why animated FK values in an IK chain still matter (and why Blender users set ik chains to "rest/zero" FK values).

### Source
`DNA_constraint_types.h:444-465, 744-775`; `constraint.cc:1367-1376`; `rna_constraint.cc:1277-1390`; `PLUG:479-502, 521, 565-568, 506-517`.

### What this means for Kine
- Minimal viable parameter set: `target` (key-able), `pole` (key-able, optional), `pole_angle` (calibrated), `chain_count` (2 for limbs), `use_stretch` (+ per-bone stretch factor if we want squash-stretch), `influence` 0..1 (key-able), `orient_weight` (match hand/foot orientation, default on for foot/hand, off for spine tips). Iterations default can be 20-30, not 500, for an interactive app.
- Influence: implement the cheap and smooth form Blender uses without pole: blend the *goal* between the current FK tip pose and the target by influence, then solve. That gives a continuous IK-to-FK fade of any key-able IK weight without a separate switch. If a pole is present, blend the resulting per-joint rotation deltas (quaternion nlerp from identity) instead, to avoid the flip.
- The solver must read the FK/keyed pose as its starting point. Our existing "animator keys joints (FK)" data is then the base layer and IK adds on top.

---------------------------------------------------------------------

## d. iTaSC (brief)

### How Blender does it
- Selected per armature (`pose.ik_solver` = "Standard" vs "iTaSC", `rna_pose.cc:765-766`). Code: `intern/itasc` (about 25 files), glue `source/blender/ikplugin/intern/itasc_plugin.cc` (2023 lines).
- iTaSC = "instantaneous task-specification using constraints". It is a velocity-resolved, **stateful** solver: it keeps a persistent scene, joint velocities and a cache, and solves multiple constraint sets (CopyPose, Distance) with weights and priorities; the result is a timestep integration with feedback (error correction), not a stateless pose solve. Standard IK is stateless, solved from the current pose each evaluation, one constraint tree.
- Modes: **Animation** (stateless: starts from pose after action/constraints each frame, reiterates until precision; `itasc_plugin.cc:1770-1795`) and **Simulation** (stateful, real-time, ignores actions, can cache, e.g. for physical "follow the target with lag" behaviour; L1186, 1721).
- Distinctive features: per-bone ik_rotation_weight and ik_linear_weight (rna_pose.cc:1204-1215), "Distance" IK type (clamps to a sphere around a target), multiple end-effectors with real priorities, damping/velocity limits, auto-step (substepping).
- Solver choices inside iTaSC: weighted SDLS (default; `WSDLSSolver`) or weighted DLS.
- Defaults (`action.cc:1154-1170`): precision 0.005, 100 iterations, 4 steps, min/max step 0.01/0.06 s, flags auto-step + initial reiteration, feedback 20, max velocity 50 rad/s, damping max 0.5, damping epsilon 0.15 (rna ranges `rna_pose.cc:1416-1500`; feedback range 0..100, default animation feedback constant 0.8, itasc_plugin.cc:63).
- Do animators use it? Generally no: character rigs (Rigify, most studio rigs) use the **Standard** solver with pole targets. iTaSC is used for mechanical/robotic or "follow with inertia" rigs. Standard is the default and is what docs/tutorials assume.

### Source
`rna_pose.cc:765-766, 1380-1520`, `DNA_action_types.h:329-349, 958-975`, `action.cc:1154-1170`, `itasc_plugin.cc:63, 1186-1193, 1721-1800, 1982-1996`.

### What this means for Kine
Ignore it. Nothing in a posing/animating app needs a stateful velocity solver. The only idea worth stealing is "reiterate on the first frame / on drag, otherwise do one cheap pass", which we get for free by warm-starting.

---------------------------------------------------------------------

## e. IK/FK switching (Blender has none built in; Rigify builds it)

### How Blender does it
Blender has no IK/FK switch. A rig implements it with **two (or three) parallel chains plus a blended output** and a custom property:
- Rigify limb (`rigs/limbs/limb_rigs.py`): FK control chain, IK mechanism chain (with `IK` constraint, chain_count 2, pole target, stretch limit), and an ORG (output) chain. Each ORG bone gets `COPY_TRANSFORMS` from FK at full influence, then a second `COPY_TRANSFORMS` from the IK bone with a driver whose polynomial `[1.0, -1.0]` on property `IK_FK` gives influence = 1 - IK_FK (limb_rigs.py:727-737). So the IK copy's influence is 1 - IK_FK: **IK_FK = 0 means pure IK, 1 means pure FK** (the slider is FK-ness despite the name; the FK constraint is always at full influence underneath). Intermediate values blend the two world-space bone transforms (copy-transforms influence).
- Stretch: IK target is clamped to `LIMIT_DISTANCE` of length (bone sum * 1.035) with influence driven by `IK_Stretch` (limb_rigs.py:~670-695), so the IK target cannot pull the chain past full extension unless stretch is wanted.
- Pole on/off: property `pole_vector` mutes the plain IK or the pole IK constraint (limb_rigs.py:~686-706).

### Snapping (the part that makes switching usable): `rig_ui_template.py` / `limb_rigs.py:1016-1135`
Both operators evaluate **visual transforms** (the final matrices after constraints), then write control values so the *other* mode lands on the same pose, at the current frame (or baked over keyframed frames with an "Apply to keyframes" variant).
- **FK -> IK snap** (generic, `animation.py:870-1000`): read the world/pose matrices of the IK result bones (what the character visually looks like), and for each FK control compute the local transform that reproduces that matrix, `set_transform_from_matrix(...)` which converts pose-space matrix to the bone's local-space (using Blender's `convert_space POSE -> LOCAL`) and writes loc/rot/scale. Done bone by bone from the root outward, updating the depsgraph between bones so children see the new parent. This is plain "copy the visual pose into the FK controls".
- **IK -> FK snap** (`limb_rigs.py:1016-1135`): saves the FK chain's matrices, then:
  1. Put the IK **end control** at the FK tip: take FK last-bone matrix, convert via "pose delta" (preserving the current offset between IK mechanism bone and control) and set it (limb_rigs.py:~1087-1097).
  2. Put the IK base control at the FK base matrix (no rotation if a pole is used).
  3. Settle the **bend plane**:
     - With a pole target: `match_pole_target(...)` (rig_ui_template.py:244-280). Take a = IK base position, b = IK tip position (a + last bone vector). `ikv = b - a`. Make a vector `pv` perpendicular to ikv with magnitude = total limb length (`ik_bones[0].length + ik_bones[1].length`). Put the pole at `a + ikv/2 + pv`. Measure the rotation difference between the IK base bone and the FK base bone (its roll error). Try rotating `pv` about `ikv` by +angle and by -angle, put the pole at each, re-measure, and **keep the candidate with the smaller residual angle** (rig_ui_template.py:262-278). So the pole is found by "start anywhere perpendicular, twist about the chord until the IK base bone matches the FK base bone's orientation". The pole distance is arbitrary (limb length), only direction matters.
     - Without a pole: `correct_rotation` (rig_ui_template.py:200-224): one-dimensional search on the IK control's Y-euler rotation: a bracket search (`find_min_range`) then a ternary search to 1 degree, minimizing the angle between the IK bone's current direction vector and the FK bone's axis (it re-evaluates the depsgraph each probe).
  4. Fix base scale (`correct_scale`, <= 3 fixed-point iterations, tolerance 1 percent).
  5. Set any intermediate (middle) controls the same way as FK->IK, lock/unlock their rotation inheritance around it, then set tail controls (foot roll, heel).
  6. Optionally keyframe the controls.
- A separate keyframe "bake" operator walks all keyed frames in a range and performs the snap on each, then rewrites the IK_FK property curve to constant, so a switch mid-animation does not pop.
- Blender never sets `IK_FK` itself from a snap; the user presses Snap, then moves the slider (the UI exposes both "IK->FK" and "FK->IK" buttons and the slider).

### Numbers
Pole distance = limb length; twist search tries +angle and -angle (2 candidates); rotation search precision 1 degree (pi/180); scale correction max 3 passes, 1 percent tolerance; stretch bias 1.035 on `LIMIT_DISTANCE`.

### Source
`rigs/limbs/limb_rigs.py:127-148 (compute_elbow_vector/pole angle), 362-372, 560-735 (IK mechanism, IK_FK, pole_vector, stretch), 727-737 (ORG blend), 1016-1135 (IK->FK), 1152-1185, 1186- (toggle pole)`; `rig_ui_template.py:108-280`; `utils/animation.py:870-1000`. Paths relative to `rigify/` in the blender-addons mirror (`C:\Users\Nick\Tools\ref\rigify` holds copies).

### What this means for Kine
This is the one we must design ourselves; Blender gives us the model:
- **Per limb, store both representations**: FK joint rotations (what exists now) and an IK handle set (`target` transform, `pole` position, `pole_angle`, `ik_weight`). One scalar `ik_weight`/mode per limb, key-able.
- **Evaluation**: pose = FK joint rotations as the base layer; if `ik_weight > 0` run IK to the target and blend (rotation-delta nlerp per joint, or goal blending as in c). Pure FK is `ik_weight = 0`, pure IK is `1`. Switching is then just changing a key-able number, no hard mode.
- **Snap, FK -> IK (author wants to pose in FK after having IK)**: evaluate the IK pose, then write the resulting joint rotations into the FK keys for that frame. Trivial because IK output *is* joint rotations.
- **Snap, IK -> FK (author wants to grab the foot/hand handle after FK)**: compute FK tip transform and set `target = tip transform` (position and rotation). Set `pole` = limb-plane-based position: take chord `ikv = tip - root`, the existing elbow/knee offset perpendicular to chord (component of the lower-bone vector perpendicular to the chord), place pole at `root + ikv/2 + perp_unit * limb_length` (Rigify does exactly this up to the roll-matching twist). Because our solver computes the plane from (root, target, pole), choosing `pole` along the real bend direction reproduces the FK pose exactly with **no search needed**: compute `perp = normalize(lowerBoneVec - proj(lowerBoneVec, chord))`, pole = `mid + perp*L`. Blender needs the 1D searches because its roll/pole_angle can differ per rig; if we calibrate `pole_angle` at setup, we do not.
- **Key at the switch**: whenever the user flips, write keys on both sets (FK rotations and IK handles) on that frame and key `ik_weight`. Interpolating `ik_weight` between keys gives a smooth IK<->FK fade; Rigify's bake-through-range option has the same purpose (no pop when blending).
- The animator "cannot key an IK target" today: the target and pole must become first-class animated properties (position + rotation per limb in a chosen space: world, root-local or parent-bone-local; Blender's constraint-space approach is why Rigify has "parent switch" for IK targets, a feature to defer).

---------------------------------------------------------------------

## f. Cost and why dragging is fast

### How Blender does it
- Problem size is tiny. A leg or arm is 2-3 bones. DoF per bone <= 3 (+1 stretch). The Jacobian is 3 x (3N) for position-only (6 rows with orientation). The SVD is of a matrix at most about 6x9, solved by Eigen's JacobiSVD (QJ:86-112; transposed so the SVD is on the smaller dimension, QJ:44-67). Cost per iteration is roughly microseconds. Even a 500-iteration worst case is a few ms for a limb.
- The IK solver and its segment objects are **rebuilt on every evaluation**: `execute_posetree` allocates a segment per bone, fills them from the current pose, solves, reads back the basis changes, then frees everything (PLUG:288-577, 597-668). The chain *topology* (which bones, trees, root/tip indexes) is computed once on depsgraph rebuild and stored as the `iktree` on the root bone (`initialize_posetree`, PLUG:67-223); trees are consumed after execution and rebuilt when needed. There is **no cross-frame solver state** in Standard IK.
- Warm start: the solver always starts from the current (post-FK/post-animation) pose (PLUG:347-387). While dragging, the previous frame's result is the new starting pose so the solve is near the answer and the convergence test (norm < 1e-3 after iteration 10) is reached in ~11-25 iterations in practice. Early exit also works because beta is clamped (small bounded steps).
- Only chains with IK constraints with nonzero influence run (PLUG:622-629). Other bones are evaluated in the normal depsgraph order.
- Scale normalisation (QJS:22-53, 300-366) keeps the numerical conditioning the same regardless of rig size.
- What is cached across evaluations: chain topology/tree structure; the rest pose bone matrices (`bone_mat`, `chan_mat` from `make_dmats`) are recomputed per evaluation. In iTaSC (not Standard) a cache of joint velocities/timestamps exists for simulation.

### Source
`PLUG:67-223, 288-577, 597-668`; `QJ:17-68, 86-112`; `QJS:300-366`.

### What this means for Kine
- A 2-bone limb with a closed-form solve is O(1). Even a general 4-5 bone chain with a 15 DoF DLS iteration is a few microseconds per iteration in GDScript-sized loops; keep iterations to ~15-20 and warm-start from the previous frame/drag pose.
- Do not allocate a solver object per evaluation in GDScript; allocate chain buffers once at rig load and rewrite their contents per evaluation. Cache: chain bone indices, bone lengths, rest orientations, joint limit tables. Recompute per eval: current joint angles, FK positions.
- Evaluate only limbs that have `ik_weight > 0` and whose target/pole or parent chain changed (dirty flag).

---------------------------------------------------------------------

## Appendix: Recommended Kine design in one paragraph (derived from the above)
Two-bone limbs: closed-form law-of-cosines solve in the plane (root, target, pole), pole_angle calibrated once per limb, clamp reach to 0.999 * chain length (or stretch). Longer chains (spine, tail, fingers): damped-least-squares Jacobian with SDLS-like cap (pi/4 per joint per iteration, 0.8 step scale), per-iteration error clamp to chain_len/(2N), at most 15-30 iterations, warm-start, stop when max joint delta < 1e-3 rad after a few iterations, active-set limit handling (lock the worst violator and re-solve), per-bone lock/limits/stiffness. Per-limb key-able `ik_weight`, `target` (pos + rot), `pole` (pos), with goal-blending (no pole) or joint-delta blending (pole) for partial weights. FK<->IK snap by pure transform copy plus the perpendicular-offset pole construction; no searches needed.
