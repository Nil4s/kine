# LOOK4D design: pre-registered format comparison for scene reading

Status: v2 (coordinator review 2026-11-05). Bars below are fixed before any reader runs; changing one after seeing a number needs a dated amendment at the bottom. Background and sources: `docs/LOOK4D_RESEARCH.md`.

## 1. What Kine can produce cheaply (file:line, worktree w4-look4d @ origin/poser-ui-rounds 268414bd)

Pixel buffers
| Buffer | How | Where | Cost / status |
|---|---|---|---|
| Plain screenshot | viewport texture to image | `tests/abody2_test.gd:42`; `AssemblyRender.render` (PNG frames + sheet) `scripts/build/assembly_render.gd:151`, camera/size opts documented there and `docs/API_FOR_AGENTS.md:27` | exists |
| Camera model | pinhole, fov, keep_aspect, near | `scripts/build/frame_facts.gd:180` | exists |
| Object-id image | flat unlit colour per piece, 4096 ids, no AA, black = nothing | `scripts/build/look_facts.gd:155` (id_color), `:199` (id_pass, own SubViewport), `:265` (id per pixel) | exists, one small render |
| Visible vs hidden, and who hides it | solo pass per target vs full id pass | `scripts/build/look_facts.gd:8` (header), `serve` `:416` | exists; this IS the occlusion flag |
| Silhouette box / share / cut per piece, no render | triangle corners projected | `scripts/build/frame_facts.gd:35` (gather), `:216` (project), `:328` (serve) | exists, analytic |
| Depth | no depth readback exists in the repo (grep found none). Cheap routes: (a) analytic per-piece nearest/centre depth from `frame_facts` projection (view-space z of the corners already computed in `project()` `:216`); (b) per-pixel: unshaded material writing view depth in an id-style SubViewport (same pattern as `look_facts._flat` `:158`) | not built | (a) ~free; (b) one extra small render. Needed: confirm Godot 4.7 readback in the SubViewport |
| Normals | `Viewport.debug_draw` normal-buffer mode or a normal-writing unshaded material | not in repo | UNTESTED here; not needed for the experiment, skip |

Per-object state (no pixels)
| Quantity | Source | Where |
|---|---|---|
| Pose of every part at any time t | `AssemblyAnim.pose_at` / `frames` / `values_at` (drives, links, loop solver) | `scripts/build/assembly_anim.gd:196`, `:215`, `:118`; time grid `:62-:71` |
| Velocity | central difference of pose at t-dt, t+dt (dt = 1/(2 fps)); the drives are keyed curves so this is exact up to the difference step. Not a stored field today. | built from `assembly_anim.gd:196` |
| Angular velocity | same, from rotation difference | same |
| Body (character) speed series, momentum, contacts of feet | `EventQuery.sample` / `speed_series` / `Momentum.sample`; foot plants and lifts | `scripts/event_query.gd:161`, `:675`; `scripts/momentum.gd:61`; `scripts/explain_motion.gd:71` (_sample), `:383` (_foot_events) |
| Rigid prop falling and bouncing (floor contact) | `RigidDrop.simulate`, 240 Hz baked poses | `scripts/rigid_drop.gd:60`, `pose_at :194` |
| Contact / distance between solids | `KCad.distance` | `scripts/kcad.gd:90` (G45 touch test used by `AssemblyStage.check`, `scripts/build/assembly_stage.gd:241`) |
| Penetration volume | `KCad.overlap_volume` (mm3; Part.HIT_VOL = 1 mm3 is contact not clash) | `scripts/kcad.gd:81`; in motion: `AssemblyMotion.check_motion` `scripts/build/assembly_motion.gd:163`; along the timeline: `AssemblyAnim.check` `assembly_anim.gd:265` |
| "check_fit" | no function by that name exists (grep). The FIT bar in `tests/ch16_test.gd` (header, bar 4: AABB prefilter then `KCad.overlap_volume`, planted 2 mm PCB shift) is the nearest thing. I treat "penetration from check_fit" as `overlap_volume` and say so. | `tests/ch16_test.gd:7-8` |

Not in the app today: any "falling stack" (rigid_drop is a single rod; hit_physics uses an external MuJoCo humanoid, `scripts/hit_physics.gd:222`). Scene 4 below uses what exists.

The digest (D) needs no new physics: it is a join of the rows above. The annotated image (C) needs: id render (exists) + projected centre/velocity (frame_facts projection) + ghost positions (pose_at at past times) + outline for occluded ids (from the id/solo passes). Estimated new code is a renderer-side overlay and a join script, not a new buffer. This lane does not write it.

## 2. Formats (fixed)
Same camera, same size for all images: 768x432 (about 442 image tokens by w*h/750).
- A: one screenshot at time t0.
- B: 4 screenshots at t0-3h, t0-2h, t0-h, t0 (h = the scene's ghost step, 0.05-0.1 s), each 384x216, tiled 2x2 into ONE 768x432 image, so B has the same pixel budget as A and C (the P1 comparison is at equal pixel budget). B-big (four 768x432 images) is NOT built.
- C: one annotated image at t0 (768x432): id label + view depth (m) per visible part; yellow arrow = the part's 3D velocity projected to the screen (tail at the part centre, tip at centre + v*0.25 s), with a text label "speed m/s" and "toward"/"away" when the depth rate is over 10% of speed; 3 white ghost dots at t0-h, -2h, -3h; hidden parts (visible share under 25%) drawn as a dashed outline of their solo silhouette box with "(hidden)". No colour encodes a quantity.
- D: text only, JSON rounded to 3 significant figures, one row per object: id, pos (m, world, y up), vel (m/s), speed, angvel (rad/s), mass_kg (NOMINAL, see scenes), momentum (kg m/s), view depth (m), visible_frac, occluded (bool, visible_frac < 0.25 with a non-empty silhouette) and occluded_by, contacts (ids), penetration_mm3 (per pair). Camera pose, fov and image size once. D has NO screen pixel positions and NO out-of-view flag: left/right/above/below on screen, 0.5 s collision and out-of-view must be worked out from world pose + camera + velocity.
- C+D: C and D together.
- Z (control): question text only.
- D-scr (control): D with each object's value block moved to a different object's id (still well formed).
All arms get the same object list (ids and plain names) in the header, and the same question text.

## 3. Scenes (5 motion + 1 null), all from existing content or built from it
1. S1 engine: `ch13_parts.loop_assembly()` keyed Crank 0 to 720 deg over 2 s, linear (as `tests/g7time_test.gd:engine_keyed`), poses from `AssemblyAnim.pose_at`. t0 = 0.6 s. Contacts and penetration from the kernel (`AssemblyMotion.place`, `KCad.distance`, `KCad.overlap_volume`).
2. S2 syringe arm moving a can: `ch14_scene.build/pose(sc,t)`. t0 chosen mid-carry. Contacts: world-box gap only (no kernel solids at the node level); touch questions are not asked on S2.
3. S3 walk with foot contacts: `scenes/walk_bat.json` through `Scene.from_dict` + `Scene.apply(Body, t)`; every Body part drawn as its capsule (`Body.cap`, `Body.rad`). Mass nominal (capsule volume x 1000 kg/m3). Contact = capsule within 1 cm of the floor.
4. S4 falling rod: `RigidDrop.simulate` (sword body, bounces on the floor), plus two scripted ballistic balls and a wall box (a ball partly behind the wall) so there is more than one mover and real occlusion. Substitute for the "falling stack", which does not exist in the repo. Analytic contacts.
5. S5 camera assembly with planted interpenetration: `ch16_parts.assembly({"pcb_into_shell": true})`; static, penetration from `ch16_parts.clashes`. Motion questions are not asked.
6. S6 NULL: S1 with the pose frozen at t0 (identical geometry, camera, labels, zero motion; ghosts coincide). Asked the S1 motion questions with a "none" option.
Cameras are chosen per scene by hand BEFORE any reader runs, saved with the stimuli, identical across formats. A camera may crop the scene so that some parts are fully out of view (needed for the out-of-view type).

## 4. Questions, types and ground truth
Generated by `tools/look4d_truth.py` from `truth_data.json` written by the Godot module (poses sampled every 1/30 s from t0-0.3 to t0+0.5, projections, silhouette and visibility counts, contact table). Truth comes from the scene, not from any rendered format. Frozen (questions.json + truth.json) before any packet is built.
Lookup types (answer is a field or a comparison of fields in D):
- fastest (4-way, top speed >= 1.25x the second), toward (yes/no on depth rate, |vz| >= 0.3 |v|), hidden (yes/no), ordering (nearer to camera, depth gap >= 15%), touch (which pair touches/overlaps; 4 pairs, one true).
Non-lookup types (need reasoning beyond reading a field of D):
- collide: will A and B come within 0 mm (box/analytic gap) in the next 0.5 s (needs extrapolation; gap at t0 >= 30 mm, min gap either <= 0 or >= 30 mm).
- screen_lr / screen_ud: is A left of / above B in the picture (needs projection; margin >= 40 / 30 px).
- out_of_view: which of 4 parts is fully out of the picture (silhouette empty in the frame; D shows only world pose).
- predict: in which 3x3 screen cell will A be at t0+0.5 s (4 options; true position >= 25 px from a cell edge; the constant-velocity prediction must agree with truth or the target is skipped).
Target: at least 40% of questions non-lookup; the generator reports the share and refuses to emit a set under 40%.
Answers are an option letter (yes/no questions have options A=yes, B=no); scripted grading only. Chance is measured by Z and D-scr, not assumed. S6 uses the S1 motion templates with a fifth option "none/not moving"; truth there is "none" or "no".

## 5. Protocol (v2)
- One fresh reader per (arm, rep): 7 arms x 3 reps = 21 readers. Each reader gets all 6 scenes in that arm's format, in a fixed per-reader shuffled scene order (seeded). It sees only its packet (`out/look4d/packets/<arm>_r<k>/`): instructions, object lists, images under fresh filenames, D text inline, the questions. Never truth, scene paths or other arms. It answers in a JSON object `{"<scene>.<qid>": "<letter>"}`.
- The launcher (not the author of this lane) starts the readers.
- Grader: `tools/look4d_truth.py grade` on option letters. No model grades.
- Cost per artefact: image tokens w*h/750; text tokens utf-8 bytes/4; production time recorded per format per scene in `timing.json` (render awaits included, process start excluded).
- Analysis: per-question accuracy averaged over reps; paired comparisons use a cluster bootstrap over questions (10,000 resamples, fixed seed). Per-type and per-scene numbers are exploratory.
- Power: about 45 motion questions give a standard error near 6-8 points on a 10-point contrast. The bars use point estimate AND the lower bound. A fail is not proof of absence; if A scores above 85% the experiment is ceiling-limited and I say so.

## 6. Predictions (if "encoding, not a new sense" holds)
Motion-question accuracy: D ~ C+D > C > B > A ~ Z. Spatial-reasoning types (projection, out of view) are where an image could still help D.

## 7. Bars (fixed)
Motion questions = S1-S4 (not S5, not S6).
- P1 (primary): acc(C) - acc(B) >= +10 points on motion questions, with the 95% bootstrap lower bound > 0. C and B have equal pixel budget.
- P2 (primary): acc(C+D) is not below acc(D) by more than 5 points on any question type (my operationalisation of "at least D on every type", with a 5-point noise allowance; stated so the coordinator can veto it), AND acc(C+D) - acc(D) >= +5 points on the spatial-reasoning types (screen_lr, screen_ud, out_of_view pooled). If the second part fails: report "ship D-only".
- Reported only: acc(C+D) - acc(A) (a single frame cannot show motion, so this is trivially passed), acc(D) - acc(A), token cost of every arm against A.
- TOKENS: tokens(D) < tokens(A) = 442 (768x432), median scene. Also reported at 640x360 (307), where a fail is reported, not a bar failure.
- NULL control (S6, motion templates): |acc(C+D) - acc(A)| <= 10 points, else any motion advantage is a text/question artefact and P1/P2 are void.
- SCRAMBLED control: acc(D-scr) within 10 points of acc(Z) on motion and touch questions, else the questions leak and P1/P2 are void. acc(D) - acc(D-scr) >= +20 points, else D carries no information.
- NO-HARM: acc(C+D) - acc(D) >= -5 points overall.
- PRODUCTION TIME: reported; soft ceiling 5 s per format per scene (also a bar in `tests/look4d_test.gd`).
- INSTRUMENT bars (`tests/look4d_test.gd`, committed before the first reader): D velocities equal finite differences of the posed transforms (planted wrong dt must fail); occluded flags equal an independent id-pass count built on LookFacts primitives (and hand truth on a planted fixture); C's arrows project from the true velocity, read by pixel position (planted reversed arrow must fail); every format renders 768x432 inside 5 s.

## 8. What falsifies it
- P1 fails: annotation (arrows/labels/ghosts) in one frame is not better than the same pixels spent on four frames; stop annotation work, B is the cheap format.
- P2 second part fails: the image adds nothing over D on projection questions; ship D-only.
- acc(D) - acc(D-scr) < 20: the digest is not what readers use; the experiment says nothing about D until the format is fixed.
- NULL or SCRAMBLED fails: the instrument is broken; no conclusion.
- A above 85% on motion questions: ceiling-limited.
- Anything that holds on one scene only is reported as that scene's result.

## 9. Known limitations
- One model family, one reader prompt, 5 synthetic/CAD scenes. S3 is capsules, not the skinned mesh; S4 is built for this test.
- Questions and formats share an author (battery blind spot). The generator is deterministic and its truth tables are saved; each type's threshold is a stated constant.
- Contact/penetration truth uses different machinery per scene (kernel, capsule, box); S2 has none.
- D's nominal masses are a rule, not a BOM.
- The module hands D to the experiment as JSON; no MCP tool is added (see `docs/LOOK4D_WIRING.md`).

## Amendments
- v2 2026-11-05: readers per (arm, rep) over all scenes (21 readers); bars P1/P2; reasoning types; D without screen pixels.
- v2.1 2026-11-05 (format fixes made before any reader ran; no bar changed): C is a Set-of-Mark layout: the picture at 552 x 311 (scale 0.71875) top-left, a legend strip at the right (mark, name, depth, speed, toward/away), a key under the picture; the pixel count stays 768 x 432. One numbered mark per listed part, greedy placement with no overlap, leader line when moved, marks never cover a part centre or its arrow; arrows and ghost dots only for parts over 1 mm/s; hidden parts keep the dashed box. D is compact: a header row of field names, moving rows with motion columns, static rows without, contacts only for touching or overlapping pairs. Scenes list a named subset (S2 16, S3 19, S5 16 parts; S1, S4, S6 all) so C and D describe the same parts. New instrument bar 7: no two mark boxes intersect in any of the six scenes (planted: the old layout must intersect). Question generator: "fastest" needs a 1.12x top speed (not 1.25x, which almost never held); up to 2 toward, 2 hidden, 2 ordering, 2+2 collide, 3 predict per scene.


## Amendment v2.2 (lead, before any reader run)
- In the yes/no truth, 16 of 52 answers are "yes" (30.8%), so always answering "no" scores 69% on them.
- Balanced accuracy will be reported alongside raw accuracy for every arm and question type: the mean of yes-recall and no-recall on yes/no questions, and per-option recall on the others.
- The primary bars P1 and P2, and the controls, are judged on raw accuracy as registered. If balanced accuracy reverses any verdict, that is reported as a caveat. The bars do not change.
- Readers are fresh Sonnet subagents. Each gets only its packet, copied outside the repo. Answers are graded by `tools/look4d_truth.py grade`.
