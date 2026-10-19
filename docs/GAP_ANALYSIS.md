# Kine vs Blender / Maya: what we have, what we lack (2026-10-18)

How this was made, so it is not a guess:
- **Kine side:** every command in `main.gd:_commands()` (136, listed by `grep add.call`), plus a grep of `scripts/` for what is not a command (audio, render, import, camera, constraints).
- **Blender side:** the table of contents of the Blender manual's *Animation & Rigging* chapter and its animation editors (docs.blender.org/manual/en/latest/animation/, read 2026-10-18).
- **Maya side:** its animation basics (Graph Editor, Time Editor, HumanIK, constraints, playblast), named only where they have no Blender equivalent.

Each row is HAVE (works and is tested), PART (exists but short of the reference), or LACK (absent).

## The table

| # | Feature (Blender name) | Kine | Evidence / what is missing |
|---|---|---|---|
| 1 | Keyframes, insert / delete | HAVE | cards + "Key the part here" (K) |
| 2 | Interpolation, handles, extrapolation | HAVE | Part key interp / handle / infinity (XX1) |
| 3 | Graph Editor (F-curves) | PART | "Curve editor" shows one part's keys; no multi-channel view, box-select, scale-keys, normalize, F-curve modifiers (noise, cycles, limits) |
| 4 | Dope Sheet | HAVE | dope sheet, copy / move keys (NA0) |
| 5 | Timeline, preview range, fps, markers | HAVE | preview range, 24/30/60, markers |
| 6 | Keying Sets | HAVE (part level) | named keying sets of parts, one active, K keys them all at the playhead in one undo step (scripts/part_sets.gd, tests/sets_test.gd, docs/research/SETS.md); no per-channel paths |
| 7 | Pose: copy / paste / flipped, propagate | HAVE | Copy / Paste / Paste flipped; "keep this change through the whole scene" |
| 8 | Pose Library | PART | Save pose plus a Poses list; no thumbnails, no blend-in-a-pose slider |
| 9 | Selection Sets / bone collections | HAVE | user-named selection sets in the browser's Sets list: new from selection, select, add / remove, rename, delete, mirror; saved in the scene (scripts/part_sets.gd, tests/sets_test.gd) |
| 8 | Pose Library | HAVE | "Pose library": a thumbnail per pose (off screen, cached as <pose>.png, remade on change), apply / flipped / drag-to-blend 0-100 % / slider, selected parts only (tests/pose_library_test.gd; docs/research/POSE_LIBRARY.md). No subtract / extrapolate blend, no folders |
| 9 | Selection Sets / bone collections | LACK | "Select:" presets only; no user-named sets |
| 10 | In-betweens (push, relax, breakdown) | HAVE | Breakdowner, Push, Relax, Blend to … |
| 11 | Motion Paths | HAVE | Motion trail, pin a trail |
| 12 | NLA (actions, strips, blending) | PART | Layers: add / override / weight / mute / solo / merge (NA1-NA3); **no reusable actions / clips placed as strips** (a walk cycle reused across scenes) |
| 13 | **IK / FK switch per limb, pole targets** | **PARTIAL** (IK pin / release / snaps, keyable target, pole, weight: scripts/limb_ik.gd, tests/ik_pin_test.gd; in-view target / pole handles dragged in the view: main.gd _ikh_*, tests/ik_handles_test.gd; the pin wins over foot plant and grip) | Was: `reach` is IK used internally; the animator cannot set a limb to IK with a pole and key the IK target. This is the core of Maya / Blender character animation |
| 14 | **Constraints** (Child Of, Copy Transforms, Track To, Limit Rotation, Floor) | **PART** | weapon lock = a hard-wired Child Of; joint limits = Limit Rotation; foot plant = Floor-like. **No general constraint the user can add, key on / off, or blend** (e.g. a hand holding a door, a hand on a hip) |
| 15 | Drivers | LACK | "shoulders follow the arm" is one hard-wired driver; no user drivers |
| 16 | Armatures: own rig / bones | LACK | one fixed skeleton (UE5 Manny names) |
| 17 | **Character proportions** (height, limb lengths) | **LACK** | one body; a short or tall character cannot be animated with its own reach |
| 18 | **Skinning / own character mesh** | **LACK** | the mannequin only; known next project (char mesh engine) |
| 19 | Shape keys / face | LACK | no face; fingers have preset shapes only |
| 20 | **Multiple characters in one scene** | **LACK** | one Body; the dummy is a static target. No two-person fight |
| 21 | **Camera animation / shot camera** | **HAVE** (round 51 SC) | keyed shot camera (position, aim, focal length mm on 36 mm), look through with a 16:9 passepartout, playblast through it (scripts/shot_camera.gd, tests/shot_camera_test.gd); was: a viewport camera only |
| 22 | Props beyond weapons | PART | 4 weapons; no generic prop (box, door, ball) |
| 23 | **Audio track, scrub with sound** | **LACK** | 0 hits for AudioStream; lip-sync and timing to music are impossible |
| 24 | **Render / playblast to video or images** | **LACK** | video only as input (import); no .mp4 or PNG-sequence output to show a client |
| 25 | Export glb / usd / bvh / game | HAVE | 4 exporters with round-trip tests |
| 26 | Import other animation (bvh, fbx) | HAVE | "Import animation (fbx / glb / gltf / bvh)...": Mixamo / UE / Godot / Blender / DAZ / Biped names, rest-pose difference and leg-length scaling (scripts/anim_import.gd, docs/research/RETARGET.md, tests/anim_import_test.gd). Tested on a Blender-made Mixamo-named rig, not yet on a real Mixamo or UE download. Not done: root motion on a parent node, morphs, several clips at once |
| 27 | Mocap / video to animation | HAVE (beyond Blender) | Animation from video, Clean up mocap |
| 28 | Physics plausibility checks | HAVE (beyond both) | Check / Polish / rulebook with sources, balance, collisions |
| 29 | Undo history | HAVE | Undo history panel |
| 30 | Scripting / API | HAVE | agent tools, CLI `serve` (JSON-RPC) |

## What this says

Kine is **ahead** of both on checking motion against real bodies (28), video to animation (27) and getting started fast.
It is **level** on keyframing, dope sheet, in-betweens, trails and export.
It is **behind** on the things that make a scene, not a single move:

1. **IK/FK with pole targets** (13): every pro animator expects a hand or foot keyed in IK space. Without it, a hand on a table slides as the body moves.
2. **User constraints** (14), with IK: hand-on-object, look-at, keyed on and off.
3. **Two characters** (20): a fight app with one fighter.
4. **Playblast to video** (24): there is no way to show the work outside the app.
5. **Audio track** (23): timing to sound.
6. **Shot camera** (21).
7. **Graph editor depth** (3): multi-channel, F-curve modifiers (noise, cycles).
8. **Proportions** (17), then the own mesh (18) as the known next project.
9. Reusable actions as NLA strips (12), keying sets (6), selection sets (9), pose library thumbnails (8).

## Order (proposed round 50+)

1. Playblast (.mp4 / PNG sequence): smallest, and Nick can share results the same day.
2. IK/FK per limb with a pole, keyed IK targets: studied from Blender `source/blender/ikplugin` + `intern/iksolver` before writing a line.
3. Constraints: Child Of / Copy Transforms / Track To, keyable influence (from Blender `blenkernel/intern/constraint.cc`).
4. Two characters.
5. Audio track with scrub.
6. Shot camera.
7. Graph editor depth.
8. Proportions.

Each one becomes a gate with a measured comparison to Blender doing the same thing, not a feature that only looks done.
