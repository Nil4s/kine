# LOOK4D design: pre-registered format comparison for scene reading

Status: DESIGN ONLY, nothing built, nothing run. Bars below are fixed before any run; changing one after seeing a number needs a dated amendment at the bottom. Background and sources: `docs/LOOK4D_RESEARCH.md`.

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
Same camera, same size for all images: 768x432 (≈442 image tokens by w*h/750).
- A: one screenshot at time t0.
- B: 4 screenshots at t0-3h, t0-2h, t0-h, t0 (h = 0.1 s unless the scene's fps makes it 3 frames), each 384x216 tiled 2x2 into ONE 768x432 image so image cost matches A (tests encoding, not pixel budget). A second variant B-big = four separate 768x432 images, reported but not in the bars.
- C: one annotated image at t0: per-object id label + view depth in m as text, 3D velocity arrow projected to screen with speed in m/s as text on the arrow, white ghost dots at the 3 previous positions, occluded objects drawn as dashed outline with their label. No colour-coded numbers (pilot lesson).
- D: text only, one row per object: id, pos (m), vel (m/s, 3-vector), ang vel (rad/s), momentum (kg m/s, mass from the BOM or body table), contacts (ids), penetration (mm3, per pair), occluded (bool + occluder id), view depth (m), camera pose and fov once at top.
- C+D: C and D together.
- Z (control): question text only, no scene.
- D-scr (control): D with rows shuffled across objects (values stay attached to wrong ids; the table is still well-formed).

## 3. Scenes (5 motion + 1 null), all from existing content
1. S1 engine mid-stroke: `scripts/build/ch13_scene.gd` (build `:8`, `pose :43`), keyed 0 to 720 deg over 2 s as in `tests/g7time_test.gd:16` (parts: piston, rod, crank). t0 = 0.6 s.
2. S2 syringe arm moving a can: `scripts/build/ch14_scene.gd` (build `:28`, `pose(sc,t) :119`) with `ch14_anim.gd`; t0 chosen mid-carry, with the arm occluding a placed can from the camera.
3. S3 character walk with foot contacts: `scenes/walk_bat.json` through `EventQuery`/`explain_motion` (`explain_motion.gd:383`). t0 at a heel strike +- 2 frames.
4. S4 falling rod bounce: `RigidDrop.simulate` (`scripts/rigid_drop.gd:60`) with a floor; t0 just after first impact. Substitute for "falling stack", which does not exist; if a stack is wanted, that is a new lane.
5. S5 camera assembly with interpenetration: `scripts/build/ch16_parts.gd` with the planted 2 mm main-PCB shift from `tests/ch16_test.gd` bar 4; static, with inner parts occluded by the shell. Motion questions on S5 are not asked.
6. S6 NULL: S1 with every drive held at the t0 value (same geometry, same camera, zero motion). Used only for the planted motion-advantage control.
Camera per scene: fixed, off-axis, chosen BEFORE seeing any format output, saved to the run folder; one camera per scene, not tuned per format.

## 4. Questions and ground truth
8 per scene (S5: 8 non-motion), 48 in all; written and frozen with truth before any reader runs. Truth is computed from the scene, never from a reader or a format.
Types and truth sources:
- fastest: argmax of |v| over parts, from pose at t0+-dt. 4-way pick among named parts. Chance 25%.
- toward/away: sign of d(depth)/dt of part X (camera-space z). Yes/no, chance 50%. Include only pairs where |d depth/dt| exceeds 5% of |v| so the sign is not a rounding artefact.
- hidden: is X hidden behind Y at t0 (solo-pass visible share under 25%, from look_facts)? Yes/no.
- touch/penetrate: which pairs have KCad.distance <= 0.1 mm or overlap_volume > 1 mm3 at t0? Multiple choice with 4 sets (one true).
- predict: position of X at t0+0.5 s, only on segments keyed "linear" or constant-speed so a constant-velocity guess is the right answer; answer = nearest of 4 positions in a named region, or a number within +-15%. Truth = `pose_at(t0+0.5)`. Where the true motion is eased, the question is excluded (documented), not kept.
- ordering: which of two parts is nearer the camera (depth). Yes/no.
Numeric answers use stated tolerance; free-text is not allowed (grading by exact match to option letter or tolerance). Per scene: 2 fastest/ordering, 2 toward/away, 1 hidden, 1 touch/penetrate, 1 predict, 1 angular (which rotates fastest).
Chance is not assumed: arm Z and D-scr measure it.

## 5. Protocol
- Reader = a fresh subagent per (scene, arm, repetition), same model for all arms (pin the model id in the run log), same system text, temperature default. It receives only the format artefact and that scene's 8 questions in a fixed order. It never gets truth, scene file paths, tool access, or the other arms. Images supplied by file read through the image path with a NEW filename per run (known reader cache by path, API doc line 50 of `docs/API_FOR_AGENTS.md`).
- Arms: A, B, C, D, C+D, Z, D-scr = 7. Repetitions: 3. Scenes 6. Readers = 6 x 7 x 3 = 126 (S5 and S6 shorter). Answers = 48 questions x 3 reps = 144 per arm.
- Grader is a script on option letters/tolerance; no model grades.
- Order of arm runs randomised; seed logged. Digest and annotated image are produced once per scene and reused across reps (rep variance = reader variance only).
- Cost measured per artefact: image tokens = sum(w*h/750); text tokens = utf-8 bytes/4 (estimate; confirm one sample against the API usage field); wall time = median of 5 producer runs per format, producer cold-start excluded and reported separately. Also report tokens per correct answer.
- Analysis: per-question accuracy averaged over reps; paired comparison over the 48 (or 40) questions with a cluster bootstrap over questions, 10,000 resamples, seed fixed. Report per-type and per-scene breakdowns as exploratory only.
- Power note: with 40 motion questions as the unit, a 20-point difference has a bootstrap standard error of roughly 8-10 points. The bar uses the lower CI bound, so a real 20-point gain passes about half the time at best; a real 30-point gain passes mostly. This is deliberately conservative; a pass at this size is meaningful, a fail at 20 is not proof of absence. If A already scores above 85% on motion questions the experiment is ceiling-limited and I will say so rather than claim equivalence.

## 6. Pre-registered predictions (if the "encoding, not a new sense" account is right)
Ordering of motion-question accuracy: D ~ C+D > C > B > A ~ Z. Image adds little on top of D. If instead C+D > D by over 10 points, the image carries information the digest lacks (probably occlusion/overlap layout) and the account is incomplete.

## 7. Bars (fixed)
Motion questions = S1-S4 (32 questions), unless stated.
1. ACCURACY: accuracy(C+D) - accuracy(A) >= +20 points AND 95% cluster-bootstrap lower bound > +5 points.
2. TOKENS: tokens(D) < tokens(A) = 442 at 768x432, in the median scene. Also reported at 640x360 (307): fail there is reported, not a bar failure. tokens(C+D) reported against A; no bar.
3. NULL CONTROL (S6, motion questions): |accuracy(C+D) - accuracy(A)| <= 10 points. A larger gap means the advantage is a question/text artefact, and bar 1 is void.
4. SCRAMBLED CONTROL (D-scr, motion and touch questions on S1-S5): accuracy within 10 points of arm Z (the chance level). If D-scr beats Z by more than 10 points, the questions leak through text or priors and bar 1 is void. Arm D must also beat D-scr by >= +20 points or D carries no information (D is the reader's source of truth).
5. PRODUCTION TIME: reported; soft ceiling 5 s per scene per format on the dev machine; exceeding it is a finding, not a failure.
6. NO-HARM: accuracy(C+D) - accuracy(D) >= -5 points; otherwise the image distracts and C+D should not ship.

## 8. What falsifies it
- Bar 1 fails with A below 85% (not ceiling): the encodings do not help this reader on these scenes, and the pilot was luck.
- D >= C+D within 5 points and C <= A + 5: the value is all in the digest and image annotation is wasted work; ship D, drop C. This does NOT falsify the "encoding" hypothesis, it sharpens it.
- C >= C+D - 5 and D low: the digest was unusable (format problem); fix the table and rerun with an amendment.
- Bar 3 or 4 fails: the instrument is broken; no conclusion about formats.
- B > C by 10 or more: the filmstrip beats annotation, and annotation work should stop.
- Anything that only holds on one scene is reported as that scene's result, not as the effect.

## 9. Known limitations, stated now
- One model family, one reader prompt, synthetic clean scenes, 5 scenes: the result is about this reader on these scenes, not VLMs in general.
- Grader sees option letters; question wording was written by the same person as the formats (battery inherits my blind spot): freeze questions before building C/D and have a second agent sanity-check each for answerability from truth alone.
- Truth for "toward camera" and "hidden" depends on thresholds set here; sensitivity is checked by re-scoring with thresholds +-50%.
- The ghost-trail and arrow conventions are one design among many; a null on C is a null on this C.
- Costs: 126 readers; image readers dominate. Run S1 with all 7 arms first (18 readers) as a smoke test of the harness and the planted controls; fix harness bugs with an amendment, not the bars.

## Amendments
(none)
