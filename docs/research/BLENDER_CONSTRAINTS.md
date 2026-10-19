# Blender constraints: how they work (learned from source, for Kine)

Source: sparse clone at `C:\Users\Nick\Tools\ref\blender_cons`, git HEAD `b1d561a` (Blender main, Oct 2026). Read only, never built.
Blender is GPL: everything below is paraphrase. Do not paste its code into Kine.

Paths are relative to `source/blender/`. `constraint.cc` = `blenkernel/intern/constraint.cc`.

---

## 1. The constraint stack

### How Blender does it
- A constraint stack is a plain linked list on an Object or a PoseBone. It runs top to bottom, and each constraint sees the result of the one above it. (`BKE_constraints_solve`, constraint.cc:6760-6836.)
- The state being carried is one 4x4 matrix in WORLD space: `cob->matrix`. `cob` is a throw-away "constraint object", built per evaluation.
  - Object: starts as the object's world matrix (constraint.cc:137-190).
  - Bone: starts as `armature_world * pchan->pose_mat` (constraint.cc ~172).
  - `pose_mat` for a bone is already "parent pose * rest offset * the bone's own loc/rot/scale (and animation)" BEFORE any constraint runs (armature.cc:3183-3185, `BKE_pose_where_is_bone`).
  - So a constraint modifies the finished animated pose; it is a post-process, not an input.
- Per constraint, in order (constraint.cc:6769-6835):
  1. Skip if it has no type info, has no influence (`BKE_constraint_has_influence`, constraint.cc:6431: off flag, `enforce == 0`, or invalid/DISABLE flag), or has no evaluate function.
  2. `enf = con.enforce` (the influence; it was already written by the animation system for this frame).
  3. Save `oldmat = cob->matrix` (world).
  4. Convert owner matrix from WORLD into the constraint's `ownspace`.
  5. For each target, compute the target matrix in the constraint's `tarspace` (`get_target_matrix`; most use `default_get_tarmat`, constraint.cc:841-860, which calls `constraint_target_to_mat4`, constraint.cc:699).
  6. Call the constraint's `evaluate` function. It edits `cob->matrix` in place (in ownspace).
  7. Convert `cob->matrix` back to WORLD (skipped only when flag `CONSTRAINT_SPACEONCE` is set; only Child Of sets it, see section 2).
  8. If `enf < 1`: `cob->matrix = interp_m4_m4m4(oldmat, solution, enf)`. The blend is done in WORLD space on purpose (comment at constraint.cc:6823-6830 cites bugs #26014 and #25725).
- After the whole stack: `BKE_constraints_clear_evalob` (constraint.cc:215-260) writes the matrix back.
  - Object: `object_to_world = cob->matrix`.
  - Bone: `pose_mat = inverse(object_world) * cob->matrix`.
  - It also stores `constinv = inverse(delta)` where delta is end matrix vs start matrix, so the system can later "undo" the constraint stack (used by Apply Constraint and by transform tools).
- For bones, if the bone is CONNECTED, the constraint result's translation is thrown away and the original head position restored (armature.cc:3219-3222). Connected bones cannot be moved by constraints, only rotated/scaled.

### The influence blend, exactly
`interp_m4_m4m4(R, A, B, t)` (blenlib/intern/math_matrix_c.cc:2271-2289):
- Location: plain linear lerp of the 4th column.
- The 3x3 part goes through `interp_m3_m3m3` (math_matrix_c.cc:2226-2269): polar decomposition of each 3x3 into U (closest pure rotation) and P (symmetric stretch/scale-with-shear).
  - U_A, U_B are turned into quaternions and interpolated with `interp_qt_qtqt` (spherical interpolation; I did not read the quaternion function body, so "slerp" is from the name and general knowledge).
  - P_A, P_B are lerped component by component.
  - Result = U * P.
  - If a U has negative determinant (a mirrored axis), both U and P are negated first so the quaternion path never sees a flip (fix for #77154).
- So it is a DECOMPOSED blend: lerp position, slerp rotation, lerp scale. It is NOT a straight matrix lerp (that would shrink the matrix mid-way through a large rotation).
- Influence is per constraint and multiplies against the running result, not against a global base. Two constraints at 0.5 each are not "half and half"; the second blends from what the first produced.

### Spaces (owner and target, chosen per constraint)
Enum `eBConstraint_SpaceTypes` (makesdna/DNA_constraint_types.h:171-187): WORLD=0, LOCAL=1, POSE=2, PARLOCAL (Local With Parent)=3, CUSTOM=5, OWNLOCAL (Local Space owner-aligned)=6.
- Defaults: both `ownspace` and `tarspace` are WORLD (DNA_constraint_types.h:679-681).
- Every conversion goes through a hub-and-spoke function: `BKE_constraint_mat_convertspace` (constraint.cc:264+). It routes through POSE or WORLD as "stepping stones" by calling itself recursively.
- Bones (the useful case for Kine):
  - World to Pose: multiply by inverse(armature object world). Pose to World: multiply by it.
  - Pose to Local: `BKE_armature_mat_pose_to_bone` (strip the parent's pose and the bone's rest orientation, leaving "what the animator's loc/rot/scale channels would have to be"). Local to Pose is the inverse (`BKE_armature_mat_bone_to_pose`).
  - Pose to Local-With-Parent: multiply by inverse of the bone's REST armature-space matrix (`bone->arm_mat`). So it is the bone's matrix relative to its own rest pose but still including the parent's posed motion.
  - Owner-Local (OWNLOCAL, #6): converts a target's Local matrix into the owner's rest-frame axes so that "X" of the target lines up with "X" of the owner (rotates by the rest-orientation difference; location zeroed in that rotation).
  - Custom: world to custom = multiply by the inverse world matrix of a chosen object/bone; custom to world is the reverse (constraint.cc ~264+, uses `cob->space_obj_world_matrix`).
- Objects: LOCAL means "relative to parent and parentinv" (undo the parent contribution); with no parent it is a hack (still world-aligned plus the object's own rotation).
- A target bone's matrix is taken at its head (default) or interpolated along the bone via `headtail` 0..1 (constraint.cc:732-775; for a straight bone it lerps `pose_head` to `pose_tail` and keeps the bone's rotation; B-Bone variants not needed for Kine).
- If the target is missing/invalid, the target matrix is set to identity and the constraint's evaluate does nothing (`VALID_CONS_TARGET`, e.g. childof_evaluate early-out, constraint.cc:1037-1060).

### Numbers / defaults
- `enforce` (UI "Influence") default 1.0, range 0..1 (bConstraint, DNA_constraint_types.h:~690; RNA name "influence", rna_constraint.cc:3938).
- Default spaces: WORLD / WORLD.
- `headtail` default 0 (head).

### Source
constraint.cc:137-260 (make/clear evalob), 264-690 (space conversion), 699-860 (target matrix), 6431 (has_influence), 6703-6836 (targets + solve loop). armature.cc:3167-3230 (bone pose + constraints). blenlib math_matrix_c.cc:2226-2289 (blend). object_update.cc:98-111 (object stack entry point).

### What this means for Kine
- Model a constraint as a pure function: `(owner_world_matrix, target_matrix, params) -> new_owner_world_matrix`, run in a list in order after the bone's animated pose is known. That is a clean design and cheap.
- Blend by influence with decompose-lerp-slerp-lerp, in WORLD space, per constraint. In Godot terms: `Transform3D` -> origin lerp, `basis.get_rotation_quaternion().slerp()`, scale lerp (`Basis.get_scale()`). Do NOT `lerp` raw bases. Handle a mirrored (negative determinant) basis by sign flip as Blender does, or simply forbid negative scale.
- Spaces: for v1 offer only WORLD, and "bone pose-local with parent" (= relative to the bone's rest). Add LOCAL only if you need it; it is the hardest to explain to users. A target space is worth having per constraint: "hand follows a door" is World target.
- Connected-bone rule: if Kine bones are rigidly connected (humanoid), discard translation from a constraint result on a non-root bone, as Blender does, or the skeleton stretches.
- Where it runs: after animation sampling, after the bone's own pose, in parent-before-child order, and a bone's constraint target must be evaluated first (Blender has the dependency graph do this; Kine needs a topological order or "targets must be earlier in evaluation order" rule, with a cycle check).

---

## 2. Child Of (the inverse matrix, "Set Inverse")

### How Blender does it
`childof_evaluate` (constraint.cc:1037-1160):
- Result = `target_matrix * invmat * owner_matrix` (all 4x4). `invmat` is the stored "parent inverse" correction. With `invmat` = inverse of the parent at some earlier moment, the owner gets placed relative to where the parent was then and follows the parent's motion after.
- With the all-ones flags the target and inverse are used as full matrices. If some of LOC/ROT/SCALE X/Y/Z are switched off, both target and inverse are decomposed into location, Euler and scale, the disabled channels reset to neutral (0 or 1) in BOTH, and rebuilt. After multiplying, any disabled location axes are restored from the owner's original matrix (constraint.cc:1139-1150). (Decomposition into Euler means partial channel masks are fragile; Kine can start with "all" or "location only" and "location+rotation".)
- Child Of is the only constraint that flags SPACEONCE: owner is converted INTO ownspace before evaluate but is NOT converted back (constraint.cc:1037-1055; comment in the code describes why). In practice the result is already in the right space for the next step.
- Set Inverse is a one-shot request flag (`CHILDOF_SET_INVERSE`), not a stored matrix by itself:
  - The operator `CONSTRAINT_OT_childof_set_inverse` (editors/object/object_constraint.cc:870-893) only sets the flag, then forces a re-evaluation. If the constraint is disabled/off it temporarily enables it so the flag is processed (object_constraint.cc:849-867).
  - Next evaluation: `invmat = inverse(parent_matrix)`; for a bone owner, additionally `invmat = invmat * object_world` (constraint.cc:1105-1112). The flag is cleared and the matrix is written back to the ORIGINAL (non-evaluated) constraint so it persists (constraint.cc:1114-1125).
  - New Child Of constraints are created with the Set Inverse flag already on and `invmat` = identity (`childof_new_data`, constraint.cc:1000-1010). That is why a freshly added Child Of does not make the owner jump.
- Clear Inverse just resets `invmat` to identity (object_constraint.cc:926-944).
- `invmat` is NOT animatable; it is one static 4x4 stored on the constraint.

### Why animators key influence 0 -> 1 together with Set Inverse
- At the instant of Set Inverse, `parent * inverse(parent) * owner = owner`: the owner's evaluated transform is unchanged. That is the no-pop property, and it is only true at the parent pose that existed when the inverse was captured.
- Therefore the grab recipe is: go to the grab frame; Set Inverse (captures hand pose at that frame); influence = 1 from that frame. Before it influence = 0 (prop is just on its own keyframed pose, e.g. lying on a table). At the grab frame both worlds agree, so there is no pop.
- If influence is blended across several frames (0 at frame N-2, 1 at frame N), the blend interpolates (decomposed lerp/slerp) between the prop's own pose and the constrained pose; at the end both are identical only if the inverse was set at the end frame's hand pose.
- Setting the inverse at a different frame than the grab frame gives a pop equal to how far the parent has moved since. Blender does NOT automatically fix this; the animator has to pick the frame. (Inference from the algorithm; there is no code that recomputes the inverse as influence changes.)
- Because `invmat` is static, you cannot have a second grab with a different offset on the same constraint; animators add a second Child Of (or a second target) for the next hold. A constraint list with several Child Of entries at influence 0 or 1 is the normal pattern; or Armature-style "switch parent" setups.

### Numbers / defaults
- Flags default: all 9 channel bits set (LOC/ROT/SIZE x XYZ) plus SET_INVERSE (constraint.cc:1000-1010). `CHILDOF_ALL = 511` (DNA_constraint_types.h:594).
- `invmat` default identity.
- RNA: `set_inverse_pending` bit; writing the matrix by hand clears the pending flag so it is not overwritten (rna_constraint.cc:545-552, 1157).

### Source
constraint.cc:1000-1165; object_constraint.cc:849-1000; DNA_constraint_types.h:583-600, 995-1004; rna_constraint.cc:545-552.

### What this means for Kine
- The weapon lock is exactly a Child Of with Set Inverse taken at the authored grip pose. A user-addable version needs: (a) a stored per-constraint `inverse` transform, (b) "Set Inverse" = capture, (c) "Clear Inverse".
- Kine should go one step further than Blender and CAPTURE THE INVERSE AUTOMATICALLY when the user enables the constraint on a frame (or when influence is keyed from 0 to a nonzero value at a given key). The inverse lives on the KEY, not on the constraint: each influence-up key stores the offset it was grabbed with. That removes Blender's most common user error (wrong frame for Set Inverse) and allows several grabs without several constraints. This is a design suggestion, not something Blender does.
- Keep it as one static matrix in the data model v1 (matches Blender, simple to serialize); expose it in the UI as "Hold offset".

---

## 3. The individual constraints

### Copy Transforms (`translike_evaluate`, constraint.cc:2366-2420)
- Optionally strips shear from the target (orthogonalize around Y).
- Mix modes (enum `TRANSLIKE_MIX_*`, DNA:267-279): Replace (default, owner matrix := target matrix); Before/After Original in three flavours: Full (plain matrix product), Aligned (scale-aligned product, emulates "Aligned Inherit Scale"), Split (rotation, location, scale combined separately).
- Target space default WORLD, owner WORLD. Replace in world = owner snaps onto target exactly, at influence 1.
- Kine: the single most useful constraint (hand onto a prop's grip socket, foot onto a plant marker). Implement Replace plus "offset" (After/Before full product) at minimum.

### Copy Location (`loclike_evaluate`, constraint.cc:1961-2005)
- Per axis X/Y/Z (default all on): owner translation component := target's. Optional invert per axis (multiply by -1 before adding offset). "Offset" option adds the owner's original translation.
- Pure translation write into the 4th column; rotation and scale untouched.

### Copy Rotation (`rotlike_evaluate`, constraint.cc:2060-2180)
- Splits owner into location, rotation, scale. Converts owner and (shear-cleaned) target rotation to Euler in the OWNER's order (or an explicit order), choosing a "compatible" Euler near the owner's current one to avoid 360 degree flips.
- Per-axis on/off (default all on) and per-axis invert; an off axis keeps the owner's Euler value in Replace/Offset modes, else 0.
- Mix modes: Replace (default), Offset (legacy), Add (Euler sum), Before/After (multiply rotation matrices).
- Kine: Euler per axis is what makes Blender's version fragile (gimbal/compat hacks). For Kine prefer quaternion "copy rotation, optional swing/twist per axis" or just Replace/Before/After with whole-rotation matrices; only add per-axis if animators ask.

### Track To (`trackto_evaluate`, constraint.cc:1310-1345; `vectomat`, constraint.cc:1235-1304)
- Throws away the owner's rotation (keeps scale), builds a fresh orthonormal basis: the chosen TRACK axis points at the target; the chosen UP axis is the projection of the world Z (or the target's Z if "Target Z" is on) onto the plane perpendicular to the track direction; third axis by cross product. If the projection is degenerate (looking straight along up) it falls back to Y; if the vector is zero it uses Z. Rebuilt basis is multiplied onto owner scale. Location unchanged.
- Defaults: track axis = -Z, up axis = Y (`trackto_new_data`, constraint.cc:1300ish; DNA enum TRACK_nZ=5, UP_Y=1).
- Gotcha: the "up" reference is global Z, so it flips at the zenith.

### Damped Track (`damptrack_evaluate` / `damptrack_do_transform`, constraint.cc ~4486-4545)
- Computes the current direction of the owner's chosen axis in world, and the unit vector to the target. Rotates the owner by the SHORTEST rotation (axis = cross, angle = acos(dot), clamped) taking the first onto the second. No up-vector, so no roll is imposed; the existing roll is preserved. This is why it never "snaps".
- Near-parallel/anti-parallel handled: tiny cross uses asin for precision; exactly opposite picks the perpendicular owner axis `(track_axis + 1) % 6` to rotate around.
- Default track axis = Y (`damptrack_new_data`).
- Kine: best choice for "head/eyes/hand points at X" because it is stable and roll-free. Cheap: a few dozen flops.

### Limit Rotation (`rotlimit_evaluate`, constraint.cc:1771-1850)
- Removes shear (orthogonalize), decomposes the owner into location, Euler (order from owner or explicit) and scale, clamps selected axes between min/max, and rebuilds. No target.
- Non-legacy mode clamps angles as points on a circle (`clamp_angle`) so crossing +-180 degrees does not flip; legacy mode is naive number clamp (explicitly kept for old files). All of min/max default 0; flags (LIMIT_XROT etc.) default off, so a new Limit Rotation does nothing until axes are ticked (DNA:1090-1098).
- Works in the owner space you pick. On bones it is normally set to LOCAL (the Euler axes then match the bone's own channels). In world space it fights the pose a lot.
- Kine already has joint limits; the difference to note is Blender's is a constraint that sits in the stack, at an influence, and in a chosen space. If Kine's limits are applied BEFORE user constraints, a "hand reaches door handle" Copy Transforms can drag a joint past its limit; Blender solves that by letting the user put Limit Rotation AFTER the other constraints in the stack. Keeping that order choice in Kine is the point.

### Floor (`minmax_evaluate`, constraint.cc:3748-3820; defaults constraint.cc:3705-3711)
- Treats the target's position along one axis as a plane. Default floor direction = target +Z (`TRACK_Z`), offset 0. If the owner is on the wrong side of the plane (owner coordinate minus offset is less than the target's coordinate for +axis), it moves the owner onto `target + offset` along that single axis; nothing else changes. Only location is written.
- Option "Use Rotation" (`MINMAX_USEROT`): perform the same test in the target's local space (invert target, test, transform back), so a tilted target is a tilted plane.
- The plane is infinite; the "sticky" option is deprecated (DNA:527-529).
- Kine: this is a ready-made foot-on-ground / hand-rests-on-surface: only pushes out, never pulls toward. Combine with Copy Location at a target when contact is intended. It is also a cheap alternative to ray casts for planted feet on flat ground (but it will not follow stairs).

### Numbers / defaults summary
| Constraint | Default |
|---|---|
| Copy Location | X,Y,Z on, no invert, no offset |
| Copy Rotation | X,Y,Z on, mix = Replace, order = owner's |
| Copy Transforms | mix = Replace, shear removal off |
| Track To | track -Z, up Y, use target Z off |
| Damped Track | track Y |
| Limit Rotation | all axes off, limits 0, order = owner's |
| Floor | direction +Z, offset 0, use rotation off |

### Source
constraint.cc: loclike 1920-2020, rotlike 2060-2180, translike 2366-2420, trackto 1235-1345, rotlimit 1771-1850, minmax 3705-3820, damptrack 4478-4545. DNA_constraint_types.h: 221-279 (mix enums), 371-382 (axes), 411, 527-529, 835, 846, 879, 1090.

---

## 4. Keying constraints and "pick up / put down"

### How Blender does it
- Influence is an ordinary animatable float property (`influence`, `enforce` in DNA; RNA at rna_constraint.cc:3938). The animation system writes it before the stack evaluates ("value should have been set from animation data already", constraint.cc:6791). Because it is a plain curve, an animator keys influence like any channel and may use Constant, Linear or Bezier interpolation. Constant (a 1-frame step) is common for hard attach; two keys one frame apart is the "snap" case.
- Typical hold (hand picks a prop, carries it, puts it down):
  1. Prop has its own keyed pose on the table.
  2. On the grab frame: set Child Of target = hand bone, Set Inverse on that frame, key influence 1 (and influence 0 one frame before, constant or short linear).
  3. During the hold the prop's own channels are not animated (the hand moves it).
  4. At the release frame the Child Of influence goes 1 -> 0. If the prop's OWN transform channels are static at the table position, the prop would jump back to the table when influence hits 0. To avoid that, the animator first sets the prop's transform keys to its visual (constrained) pose at the release frame, then drops influence. This is what visual keying does.
- Built-in visual keying:
  - Pref/scene flag "Visual Keying" (`KEYING_FLAG_VISUALKEY`, animrig/intern/keyframing.cc:287-288; used at keyframing.cc:399-403). When on, inserting a keyframe on location/rotation/scale reads the object/bone's FINAL world/pose matrix (after constraints) instead of the raw property values.
  - `visualkey_can_use` (animrig/intern/visualkey.cc:~35-190) decides if it is needed: true if the owner has a parent or an active rigid body, or any enabled constraint with non-zero influence that can touch the channel type (Child Of, Copy Transforms, Transformation, Follow Path, IK always; others only for the channel they affect: Track To/Damped Track/Limit Rotation/Copy Rotation/Locked Track for rotation, Copy/Limit Location/Distance/Floor for location, size for scale). Otherwise it falls back to the plain value.
  - `visualkey_get_values` (visualkey.cc:~196-260): for objects takes the world matrix; for bones converts `pose_mat` to the bone's local frame with `BKE_armature_mat_pose_to_bone`, then decomposes into location, Euler/quaternion/axis-angle (using the bone's rotation mode) or scale. Bone location is only used when the bone is not connected.
- "Apply Visual Transform":
  - Object (editors/object/object_transform.cc:1103-1125): evaluates the object, decomposes the evaluated world matrix back into the object's loc/rot/scale properties (`BKE_object_apply_mat4`), tags children dirty. Properties now equal what you see; constraints still exist.
  - Pose (editors/armature/pose_transform.cc:525-590): for selected bones, stores pose-to-bone matrices for ALL first, then applies them (the two-pass avoids parent edits feeding children). Code comment states it matches how visual keying works and that using `chan_mat` gave wrong results (#38251). `BKE_pchan_apply_mat4` writes loc/rot/scale from the matrix (armature.cc:2513-2518).
- "Apply Constraint" (constraint.cc:6046-6140): `BKE_constraint_apply_for_object/pose`; takes the current matrix, undoes the constraint stack effect via `constinv`, runs just ONE constraint, writes the result into loc/rot/scale, then removes it. Bone version restores the head position for connected bones first (constraint.cc ~6120).
- Bake Action (Object > Animation > Bake Action) with the "Visual Keying" option bakes every frame of a range this way. I did not have its source in the clone (it is in Python, `scripts/modules/bpy_extras/anim_utils.py`); known from usage only.

### Numbers / defaults
- Visual keying is OFF by default (user preference); per-key option.
- No smoothing or fix-up is done: the key is exactly the evaluated pose at that frame.
- Limit of visual keying (code comment at visualkey.cc:60-64): Spline IK needs non-uniform scale that creates shear in child bones and cannot be represented by loc/rot/scale, so visual keys are not exact there.

### Source
constraint.cc:6791 (influence from animation), 6040-6140 (apply); animrig/intern/visualkey.cc; animrig/intern/keyframing.cc:287, 399-403, 450, 780; object_transform.cc:1103-1140; pose_transform.cc:520-600; armature.cc:2513.

### What this means for Kine
- The pop at release is a data problem, not a solver problem: when a constraint turns off, the owner returns to its UNCONSTRAINED pose, which is whatever the prop's own keys say. Kine can make "Release" a button/behaviour that, at the release frame, writes the visual transform (constraint result) into the prop's own transform keys (Apply Visual Transform into a key) and then drops influence. Offer it as one action: "Release here".
- Same for "Grab here": one action that sets the hold offset and keys influence 0 on the previous frame and 1 on this frame.
- Visual keying is essentially "evaluate the full stack at frame N, convert the result back into bone-local channels (pose_to_bone), key them". Kine already has a per-frame pose evaluation, so the cost is one extra evaluation and a matrix-to-local conversion per bone. Do it for all affected bones in one pass (read all, then write all), as Blender's pose version does, or parents will feed children.
- Provide a "Bake range" action that does visual-key for a frame range for bones touched by constraints. This is also the export path for engines that cannot run constraints (bake before export).
- Influence curve: Constant/step interpolation by default for grab/release, Bezier optional. A blended influence between 0 and 1 gives the decomposed lerp from section 1; with a hand grab this reads as the prop sliding into the hand over a few frames, which animators use for soft pickups.

---

## 5. Performance: what is cached

### How Blender does it
- Constraints are evaluated by the dependency graph (depsgraph) which orders bone evaluation (`BKE_pose_eval_bone` / `BKE_pose_constraints_evaluate` / `BKE_pose_bone_done`, armature_update.cc:864-960) so targets are ready first. Nothing in the constraint code itself memoizes across frames. A pose channel with constraints is computed once per update in `BKE_pose_where_is_bone`.
- Per update, per owner: one `bConstraintObject` (a stack-sized struct with a matrix, start matrix, rotation order) is made and freed (constraint.cc:137, 215-260).
- Persistent data stored on the constraint: only `invmat` (Child Of), flags, and a few IK runtime fields. The result of the previous frame is not reused.
- Persistent data stored on the owner: `constinv` (the inverse of the stack's total delta) so tools can "undo" the constraints without re-solving (constraint.cc:229-241, armature_update.cc:942). Also written back to the original pose channel from the evaluated copy so the UI and tools can read it (armature_update.cc:935-945).
- Dependency graph skips unchanged objects/bones between frames; static scenes do no constraint work. Animation of influence marks the owner dirty.
- Cost of one constraint: a few 4x4 multiplies plus, when influence is below 1, two polar decompositions (3x3) and a quaternion slerp. Child Of with disabled channels additionally does two Euler decompositions per evaluation (constraint.cc:1070-1090).
- Target matrices are recomputed every time `get_target_matrix` runs (once per constraint per frame), not cached. For bone targets the reads are already-computed `pose_mat`s, so cheap.

### What this means for Kine
- No heavy cache is needed. Kine needs: (1) a stable evaluation order (topological over bones/props with constraints), (2) skip constraints with influence 0 or an invalid target (`has_influence` pattern) before doing anything, (3) a per-frame "dirty" flag so a paused viewport does no re-solve, (4) no history across frames, which keeps scrubbing deterministic (important for playback of backward scrubbing and for baking).
- Store the computed pre-constraint matrix (Blender's `startmat`) so "undo this stack for editing handles" (gizmo, Apply Visual Transform, IK handles) is a matrix multiply by `inverse(delta)`, not a re-solve.
- Fast fail on influence 0 is the main saver for animator-heavy rigs where most constraints are off most of the time.

---

## Source index (file : what)
- `blenkernel/intern/constraint.cc` (6966 lines): all per-type math, space conversion, stack solve, apply.
- `makesdna/DNA_constraint_types.h`: flags, enums, struct layouts and defaults.
- `makesrna/intern/rna_constraint.cc`: property names (`influence`, `set_inverse_pending`, `use_*`).
- `editors/object/object_constraint.cc`: Set/Clear Inverse operators, enabling logic.
- `blenkernel/intern/armature.cc` (3167-3230): bone pose evaluation with constraints; `BKE_pchan_apply_mat4`.
- `blenkernel/intern/armature_update.cc`: depsgraph hooks, constinv flush.
- `blenkernel/intern/object_update.cc` (98-111): object stack entry.
- `blenlib/intern/math_matrix_c.cc` (2226-2289): `interp_m3_m3m3`, `interp_m4_m4m4`.
- `animrig/intern/visualkey.cc`, `animrig/intern/keyframing.cc`: visual keying.
- `editors/object/object_transform.cc`, `editors/armature/pose_transform.cc`: Apply Visual Transform.

## Not found / not verified
- Body of `interp_qt_qtqt`, `mat3_polar_decompose`, `mat4_to_eulO` (math_rotation.cc, not read). I treat quaternion interpolation as spherical.
- Bake Action's Python implementation (not in the sparse set; Blender's Python is in another folder). Described from usage only.
- B-Bone shape variants of target matrices, Armature/IK/Spline-IK/Action/Shrinkwrap constraints: not relevant, not summarised.
- Whether a "snap inverse on influence change" exists anywhere: searched `constraint.cc` and `object_constraint.cc`; it does not. The pop-avoidance is entirely the animator's workflow (Set Inverse on the grab frame, visual key on release).
- Exact line numbers marked "~" were read from sed ranges, accurate to a few lines.
