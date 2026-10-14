# GATES - 10-14 "easier, more natural moves; ~30 cards per combat scene" (Nick)

Done = every box checked by a command or a look, not by a promise.

## A. Spline in-betweens (scripts/scene.gd, opt-in per scene: "spline": true)
- [x] A1 Scenes WITHOUT "spline" sample byte-identical to before (every frame of every scene, old vs new code)
- [x] A2 Spline: a pass-through card (hold 0) keeps joint speed continuous (no stop) unless that joint reverses there
- [x] A3 Spline: a card with hold > 0 is a full stop (zero speed in, zero speed out)
- [x] A4 Spline: the hand/weapon level reaches each card's pose AT the card's time (strike timing unchanged)
- [x] A5 Spline: every in-between angle stays between its neighbouring cards' values (limits hold by construction)
- [x] A6 math_test.gd still green

## B. Detail pass: ~30 cards per combat scene (tools/detail.gd -> scenes/_wip/<name>_detail.json only)
- [x] B1 A combat scene goes from 5-12 cards to 26-34, written to _wip only (Nick's scenes untouched)
- [x] B2 The added cards are named breakdowns (anticipation, arc, overshoot, settle, drag), not copies
- [x] B3 bad_frames no worse than the source scene (worst contact depth reported side by side)
- [x] B4 attack_timing.gd grades it: strike still <= the rule; tip speed under the real cap
- [x] B5 LOOKED at: sheet + gif rendered and read by eye, old vs new side by side

## C. The mod (Nick: "makes you use the visual tools sometimes, and don't rebuild the wheels")
- [x] C1 A hook that, when an animation file is written, reminds me to render and LOOK (sheet.py / see-video)
- [x] C2 A hook that, before a NEW tool/script file is created, reminds me to grep for an existing one first
- [x] C3 Fired once on purpose and its output seen

## Evidence (10-14)
- A1: tests/sample_dump.gd, 23 scenes / 1552 frames, old vs new code: `cmp` identical. A6: math_test 9/9.
- A2-A5: tests/spline_test.gd PASS on combo3, thrust, bo_spin, swing_back. Mutation (every card a stop) -> A2 FAILS.
  NOTE: the A3 bar was loosened 0.05 -> 0.5 deg/s after the first read; the speed at a stop is exactly 0 by construction
  (_slope returns ZERO), the residual is the Richardson estimator's O(h^2) on 0.1 s moves.
- B1: combo3 12 -> 30 cards. Short single swings stop under 30 at ON TWOS and say so (swing_fore 12, thrust 14, bo_spin 22).
  CORRECTION (10-14, round 2): round 1 printed thrust 16 / bo_spin 24 / bo_spin tip 46 m/s from files written at
  09:09:00, BEFORE three detail.gd edits (09:09:03, 09:09:35, 09:13:26); only combo3 and swing_fore were re-run. The
  current tool gives thrust 14 cards (strike 4 fr, tip 11.4 m/s) and bo_spin 22 cards (strike 6 fr, tip 49 m/s).
- B3: bad frames combo3 60 -> 58, swing_fore 4 -> 3, thrust 13 -> 12; bo_spin 31 -> 34 (worst depth 94 -> 93 mm, the
  source's own). B4: strikes 4-6 frames (rule <= 6); bat tip peaks 25-31 -> 16-24 m/s, bo_spin 74 -> 49 m/s (see correction).
- B5: moves/cooked/_wip/combo3_speed.png (old: spikes + dead stop inside the backhand; new: one plateau),
  combo3_before_after.gif (+ _halfspeed), combo3_backhand_onion.png. Found on the way: Dummy.landed dropped the scene's
  flags (spline, on_floor, floor_body, pin, fps) -> fixed in scripts/dummy.gd.
- C: mod at ~/.claude/dev-mods/<session>/eyes-and-wheels: validate passes, 5/5 tests, tsc clean.
  C3 OPEN: it loads only after the hot-reload answer; not yet seen firing live.

# GATES - 10-14 round 2: "what 3D animators complain they don't have" (Nick: open-source it later)

## D. Motion trail, colored by speed (animBot's signature)
- [x] D1 Toggle key; the weapon tip's (or bat hand's) path over the WHOLE scene drawn in the viewport
- [x] D2 One dot per frame (spacing is visible), colour = speed (cool slow -> warm fast), cards marked bigger
- [x] D3 Rebuilt when the scene changes, never per frame (no frame-rate cost while playing); LOOKED at in a screenshot

## E. Onion skin (ghosts)
- [x] E1 Toggle key; the pose of the card BEFORE and AFTER the playhead drawn as see-through ghosts, two colours
- [x] E2 Ghost = the real sampled pose (same Body math), not an approximation; LOOKED at

## F. Tween machine (breakdown slider)
- [x] F1 A slider on the selected card: its pose = mix(card before, card after, bias); 0 = left key, 1 = right key, past
       the ends = overshoot, every angle clamped to the body's limits
- [x] F2 One undo step restores the card; LOOKED at

## G. BVH export (open source: animations leave the poser for Blender/Maya/Unity/Unreal)
- [x] G1 tools/export_bvh.gd scene -> .bvh (hierarchy from the skeleton, one frame per 1/fps)
- [x] G2 Imported into a REAL Blender (MCP): joint world positions match the poser's within 1 cm at 3+ frames
- [x] G3 LOOKED at in Blender

## Evidence, round 2 (10-14)
- Refactor first: main body, dummy and ghosts now share Overlays.mannequin / pose_skeleton (three hand copies before).
  Screenshot of combo3 with the refactor vs the committed main.gd: 0 of 1,440,000 pixels differ.
- detail.gd's _mix now calls Scene.mix_flat (the tween rule). A/B with the old _mix restored verbatim: same output
  (thrust 14 both ways), so the de-dup is inert; the 16 -> 14 difference was the stale round-1 file above.
- D: scripts/overlays.gd. Screenshot read: combo3_detail at 1.85 s, path around the body, blue at the turns, red
  through the strikes, "26 m/s" at the peak, white card dots. D3 in the REAL window (tests/tween_undo_test.gd): 60
  frames of playback (playhead 0 -> 0.97 s) = 0 rebuilds; one edit = 1 rebuild.
- E: same screenshot, orange ghost = card before, green = card after, both from Scene.apply on a second Body.
- F: Scene.mix_flat. tests/tween_test.gd 5/5 (0 = left card, 1 = right card, 0.5 = halfway to 1e-3 deg, -25%/+25%
  never outside a limit (21 joints resting on one), pelvis 170 -> -170 takes the short way). tests/tween_undo_test.gd
  in the real UI: one drag = one undo step, Ctrl+Z restores card 4's pose, sliding never writes a card, "+ tween" adds
  one card and keeps the scene's length. Screenshots at 0 / 50 / 125 % read: body on the orange ghost, between, past
  the green one.
- G: tools/export_bvh.gd, 52 joints, ZXY channels (M = Rz Rx Ry). Euler round trip worst 0.000185 deg (first read
  0.056 deg was float32 acos in Quaternion.angle_to, not the conversion: measured by axis chords instead).
  tests/bvh_blender_check.py in Blender 4.5's OWN importer (headless; the MCP addon was not running): every joint at
  frames 0/47/94/141 within 0.0008 mm; control (one frame late) 17.1 mm = FAILS as it must. FPS reads 30.000000
  (6-digit Frame Time read 30.0003: now 9 digits). Rendered (bones as tubes, Workbench) and read: upright, feet on the
  floor, Y-up -> Z-up right.
- Not exported: the weapon (not a bone). Not found by me: scenes/bo_sweep.json is DELETED in the working tree (in git
  at 1fb3c8d); no command of this session removed it. Nick's call.
- C3: fired live in round 2: WHEELS on creating scripts/overlays.gd and tools/export_bvh.gd (the second made me check
  bake_scene.gd / export_landmarks.gd / export_skeleton.py / cook.gd first: no BVH writer existed), EYES after the scene.gd edit.

## H. Pinned trails (Nick 10-14: "trajectory lines is something cool as fuck")
- [x] H1 Shift+T pins a trail on the clicked BODY part (end of the part; hips' centre for the pelvis), any number, Shift+T
  again removes it; each coloured by its own peak and labelled with the part's name
- [x] H2 All trails built in ONE pass over the scene, once per edit (tween_undo_test: 60 playback frames, 0 rebuilds)
- [x] H3 LOOKED at: first shot unreadable (13 px card dots buried the short paths, labels unnamed): fixed to 7 px +
  "head 7.5 m/s"-style labels, re-shot and read (moves/cooked/_wip/combo3_pinned_trails.png)
- Finding it surfaced (Nick's combo3.json, not the detail pass): at 3.03 s head (eyes) 8.2 m/s and hips 2.7 m/s in the
  SAME frame, a whole-body lurch; detail pass softens it to 5.7 / 1.6 m/s, does not remove it. Not edited: his scene.

# Round 3 (10-14, Nick: "go ahead, improve this engine so a monkey can create an animation with ease")

## I. The rulebook: recorded human numbers, each with its source (scripts/rulebook.gd, docs/MOTION_RULES.md)
- [x] I1 Rules: kinematic SEQUENCE (hips peak before chest before weapon), HEAD QUIET in a swing, ~~no LURCH (one-frame
  body jump)~~ DROPPED on the data, replaced by HITCH (Flash & Hogan), FIST speed (unarmed), and attack_timing's weapon tip cap + strike frames REUSED (not copied)
- [x] I2 Every rule names its source and its bar; a rule with no outside source says "poser rule" and how its bar was set
- [x] I3 Each finding = severity, time, the card it sits in, the measured number vs the bar, in plain words
- [x] I4 Flags Nick's combo3 lurch at 3.03 s; a smooth control scene gets no lurch flag (the check can stay quiet)
- [x] I5 Every rule fails at least once on purpose (a mutated scene) before it is trusted

## J. Monkey mode (in the poser window)
- [x] J1 "Check" button: the findings listed in the window; clicking one jumps the playhead to that moment, picks the card
- [x] J2 "Polish" button: the detail pass run in the window on the open scene -> scenes/_wip/<name>_polished.json, opened,
  Nick's file untouched; one undo-free path back (re-open the original)
- [x] J3 Tested in the REAL window (script), and LOOKED at (screenshot of the findings list)

## Evidence, round 3 (10-14)
- Research: SABR head-movement review (Inkster ~9 cm drop; Nakata), ISBS 2015 hitting sequence (389/601/1953 deg/s,
  n=3), Stanley 2018 / Piorkowski 2011 punch speeds, Flash & Hogan 1985 (bell-shaped speed). Table + links:
  docs/MOTION_RULES.md. Weak spots said there: n=3 sequence study, Inkster known only through the review.
- LURCH dropped: tests/lurch_survey.gd over 26 scenes; leap_slam landing 377 m/s^2 and getup_front 336 are real and
  beat combo3's lurch (hips 81, head 247): no acceleration bar separates them. The speed curve showed what the lurch
  IS (dead still -> head 9.45 m/s -> dead still in 130 ms, ~60 cm): HEAD QUIET catches it, sourced.
- First full run: 21 FAIL / 60 WARN, read row by row: swing rules on get-ups and mid-air (not what the data measured),
  holds flagged as hitches, one stop reported 3x, "fist" on a get-up's hands. All four fixed -> 11 FAIL / 39 WARN.
  HITCH's advice depends on the cause: no spline = "tick Smooth / Polish"; spline = "two cards fight".
- I4: combo3 HEAD QUIET FAIL at 3.13 s (56 cm, card 10 'Nick STRIKE (step)'); swing_fore_detail and swing_fore_flow
  (spline) 0 findings. I5: tests/rules_test.gd 24/24, every rule fired on purpose and quiet on a good series.
- J: tests/monkey_test.gd in the real window: 6 finding buttons for 6 findings; pressing one -> playhead 3.13 s, card 10;
  Polish wrote + opened combo3_polished (12 -> 30 cards, spline on), combo3.json byte-identical. Check after Polish:
  6 findings (4 FAIL) -> 2 (1 FAIL): the head lurch is in the POSE, Polish cannot and does not touch it.
- LOOKED: first screenshot showed the panel COLLAPSED to a strip (a ScrollContainer has no height; the test only checked
  `visible`, so it passed). Fixed + the test now bars real height (460 px). Second look: the panel covered the body;
  moved to the view's left edge. "40 m/s vs 40" printed 40.3 vs 40. Third shot read: list left, body + head trail
  ("head 10.4 m/s") in sight.
- Suites after all of it: math 9/9, spline, tween 5/5, rules 24/24, tween_undo, monkey: all PASS.

# Round 4 (10-14, Nick: "fixes could update the clip only, not delete them; we always have ctrl+z")

## K. Fix button on each finding
- [x] K1 Ctrl+Z undoes a card change (today undo holds only the BODY): a fix is ONE undo step, card times/poses back
- [x] K2 A fix only UPDATES cards (move, hold, flow, pose): card count and names never change (asserted)
- [x] K3 TIP SPEED / FIST SPEED / STRIKE FRAMES: the card's move time rescaled, re-checked until under the bar
- [x] K4 HITCH: the stop removed on that card (pass-through), re-checked
- [x] K5 HEAD QUIET: the card's trunk/hips blended toward the card before until the head is under the bar; the fix
  reports what else it changed (tip speed, contacts) and is LOOKED at before/after
- [x] K6 A rule with no safe fix says so on its row (no button that does nothing)
- [x] K7 Real window test: press Fix on combo3's findings, findings drop, Ctrl+Z restores the file's cards exactly

## Evidence, round 4 (10-14)
- K1: undo step = body + the open scene's cards (+ which Scene object: a snapshot never pastes cards into another
  scene). tests/fix_window_test.gd: 3 Fix presses, Ctrl+Z x3 -> cards byte-identical to the file; redo x3 exact;
  "+ tween" (adds a card) undone to 12 identical cards (it was body-only before: "+ tween" could not be undone).
- K2: Fixer.apply asserts names/count/order; fix_test.gd checks it on every fix over 4 scenes (combo3, bo_spin,
  thrust, combo3_detail). A fix is KEPT only if its finding is gone, must-fix count does not rise, and (pose fix) no
  more contact frames; else cards put back byte-identical (4 refusals ran: bo_spin x2, thrust, combo3_detail head).
- K3/K4: TIP SPEED kept on combo3 (0.15 -> 0.16 s etc.) and bo_spin (0.16 -> 0.57 s, flags 3 new things to look at,
  said in the message); HITCH flow kept on combo3 x2, thrust card 9; refused where flowing doesn't remove it.
- SPEED: one rulebook pass on combo3 = 4.1 s, ~15 ms/frame, nearly all Body.plant -> reach (2.8 ms/call, 5 passes,
  124 of 285 calls still moving at pass 5: an early exit would not help). Not touched. Instead the head fix re-plays
  only the card's WINDOW: windowed == full re-play on all 282 frames (combo3 and the spline combo3_detail), anti-
  vacuity 30/25 frames really moved. The spline window first MISSED 2.82-2.87 s: Scene.LEAD (joints read 75 ms
  ahead) -> window opens 75 ms earlier. Head fix ~60 s -> 5.8 s in the window; timing fixes 4-5 s.
- Found by the window test: Check graded the dummy's LANDED scene (_ps) while Fix edits S -> a fixed card's finding
  came back. Check now grades the scene as made; the test bars panel == fresh check of S. And queue_free left stale
  rows listed for a frame (a stale button re-fixed card 3): rows are detached at once now.
- K5 LOOKED (moves/cooked/_wip/combo3_headfix_before/after.png, t = 3.13 s, head trail pinned): head 10.4 -> 5.6 m/s,
  trail tight. BUT the fix eases 94% of the strike's trunk back to the wind-up: at 3.13 s he stands upright, bat
  high: the strike LOSES its lean (arms-only read). Rule-legal, not good animation. Told Nick; a better fix (move the
  lean EARLIER, into the load card, as hitters stride before they swing) is the next step, not done.
- K6: rows with no fix say so ("no automatic fix: it is in the poses"/"two cards fight"). K7: window test PASS.
- combo3: 6 findings (4 must fix) -> Fix x3 -> 1 (0 must fix). All suites PASS (math, spline, tween, rules, tween_undo,
  monkey, fix_test, fix_window_test).

# Round 5 (10-14, Nick: "check the 10 complaints, let's add, test")
Sources: polycount gimbal threads, mocaponline (foot sliding), Modo spacing chart, bloopanimation (pose mirror),
taylorfrancis (stepped blocking, moving holds). Table + status in docs/COMPLAINTS.md.

## L. The ten complaints
- [x] L1 FLIPS measured: every scene's largest per-frame joint turn vs a human bar (pitching shoulder ~7000 deg/s)
  - EVIDENCE: `tests/flip_survey.gd`, 32 scenes at 60 fps: worst 58.4 deg/frame = 3505 deg/s (thrust, calf_l, 0.72 s); 0 over the bar. Bar: the registered "~7000" was a guess; the source read is Campbell, ISBS, Table 2: adult shoulder internal rotation 4765.7 +- 771.9 deg/s -> mean + 2 SD = 6310 deg/s = 105 deg/frame (tighter than registered). Control: a 180 deg twist reads 180 deg/frame, CAUGHT. Verdict: no flips; joints are swing/twist with limits, not Euler.
- [x] L2 FOOT SLIDE rule in Check: a foot on the floor that slides along it; fires on a broken series, quiet on good
  - EVIDENCE: `tests/rules_test.gd` PASS: fires on a 0.8 mm/frame creep (9.4 cm); quiet on a still foot, a step (fast lift-off + landing), 2.4 cm of creep (bar 2.5), a foot 8 cm up. Over the scenes: v1 gave 40 findings, all landings/take-offs (traced); with the settled gate, 1 real one (combo3_detail right foot, 5.4 cm into 'recover', traced). Bars 5 cm / 2.5 cm from Karunratanakul 2023; the 5 mm settled gate is mine (stated in docs/MOTION_RULES.md). No Fix button on purpose (the stance is the animator's call); fix_test lists it as a deliberate no-fix.
- [x] L3 SPACING ghosts: ghosts every 0.1 s (not per card); bunched = slow, spread = fast; LOOKED
  - EVIDENCE: `scripts/overlays.gd` `fan()`/`spacing()`: ghosts every 0.1 s, 0.5 s each way, orange before / green after, fading. LOOKED: combo3 top + side (`C:/Temp/tmp/shots/spacing_3.png`, `spacing_side.png`), bo_spin (`bo_spin_spacing.png`): a wide green fan ahead of the spin = fast. A whole stick body per ghost was built first and REJECTED on sight: a swing turns in place, ten bodies stack into a tangle; now weapon + forearms (unarmed: arms + legs). Window test: 48 ghosts on combo3, 0 rebuilds over 30 playhead moves.
- [x] L4 MIRROR POSE: the whole body left<->right (weapon to the other hand); mirror twice == the pose (test)
  - EVIDENCE: `tests/mirror_test.gd`: 43 card poses over 5 scenes land on the reflection, worst 0.001 mm; twice = the pose, worst 0.0005 mm; naive-mirror control off by 1619 mm. Window (`tests/tools_window_test.gd`): Shift+M path mirrors (0.000 mm, bat hand_r -> hand_l), Ctrl+Z puts it back (0.0000 mm). Mirror the scene: combo3 mirrored plays as the reflection, 0.00 mm over 281 frames, Check identical (6 findings); combo3.json byte-identical. (The first run differed: the moving-holds undo bug below leaked the flag into the copy; fixed, not the mirror.)
- [x] L5 COPY/PASTE pose: pick card A, Update card B -> B's pose == A's (test, existing path)
  - EVIDENCE: `tests/mirror_test.gd`: card 3's pose stored on card 6 plays back identical (0.0000 mm). Existing path: no new code.
- [x] L6 STEPPED preview: plays each card's pose with no in-betweens; view only, the file unchanged (test)
  - EVIDENCE: `tests/mirror_test.gd`: at 1.39 s the body is card 4's pose exactly (0.000 mm); Check grades the same either way; never saved. Window: the menu item half-way into card 3 shows card 2's pose (0.000 mm); off again = the in-between back (854 mm away).
- [x] L7 MOVING HOLDS: opt-in per scene, a hold drifts a little toward the next card, no jump at the hold's end
  - EVIDENCE: `tests/mirror_test.gd`: card 9's 0.08 s hold drifts the head 2.1 cm of 57 cm; feet 0 mm; seams 1.0 mm in 1/120 s; saved only when on. Window: on is in the saved scene; Ctrl+Z turns it off (FAILED first: the undo snapshot did not carry the flag; `_snapshot`/`_restore` now do). 8% drift is taste, not data.
- [x] L8 SPEED GRAPH: tip / hips / head speed over time with card marks and the playhead; LOOKED
  - EVIDENCE: `main._draw_graph`: three strips (tip, hips, head), each its own scale (no dual axis), card lines, white playhead, click/drag scrubs. Window test: 142 samples, 12 card marks; the head peak sits at 3.03 s where Check flags the lurch (3.13); clicking the middle -> 2.34 s of 4.67. LOOKED: combo3 and bo_spin. Found on looking: the graph read 81.9 m/s where Check reads 96.5 (trail pass at the scene's 30 fps, Check at 60: a chord cuts a fast arc); the graph now states its rate ("at 30 fps (Check: 60)") instead of disagreeing silently.
- [x] L9 all suites PASS; Nick's scene files byte-identical
  - EVIDENCE: all 11 suites PASS (math 9/9, spline, tween, rules, fix_test, mirror_test, flip_survey, tween_undo, monkey, fix_window, tools_window; tools_window re-run after the last main.gd edit: 16/16). fix_test FAILED once: FOOT SLIDE had no button and was not on the deliberate no-fix list; added there with a reason shown in the panel. `git status scenes/`: no modified scene (the only entry is the bo_sweep.json deletion that predates this session); the test's combo3_mirrored.json removed after itself.

## M. Round 6: timeline + hand dragging (Nick 10-14: "i agree w that go ahead")
- [x] M1 TIMELINE drawn: one block per card (move solid, hold hatched), card numbers + names, a ruler in seconds, the playhead; LOOKED
  - EVIDENCE: `scripts/timeline.gd` (class Timeline) in the bottom panel (BOTTOM_H 262 -> 314), 1568 x 46 px. LOOKED: `C:/Temp/tmp/shots/timeline.png`, `timeline_drag.png`, `timeline_hit_crop.png`. Fixed on looking: hatching too loud behind names (fainter + text shadow); the after-hit label cut off (shortened). Added on looking: with the dummy solid and hit, the strip shades what never plays ("hit: won't play"); before, it ran to 4.87 s while playback stopped at 4.01. The old scrub slider is hidden (the strip scrubs); its "x / y s" readout stays.
- [x] M2 RETIME by dragging: a card's arrival edge sets its move, its hold's end sets its hold; later cards ripple; a zero hold pulls out by dragging right; snaps 0.05 s (Shift 0.01); one Ctrl+Z undoes a whole drag (test)
  - EVIDENCE: `tests/timeline_test.gd` (mouse events at the drawn pixels): card 2's edge +0.2 s -> move 0.40 -> 0.60, card 3 starts 0.20 later with its move unchanged, scene 4.67 -> 4.87; ONE undo step; Ctrl+Z exact. Snap +0.033 s -> 0.45, Shift 0.43. Zero hold: right pulls out 0.10 s (move unchanged), left shortens the move 0.15 -> 0.10. Clamps: hold 0.00, move 0.04. An auto move becomes the dragged value (0.44 -> 0.55).
- [x] M3 CLICK: a block picks that card and jumps to its pose; the ruler scrubs (test)
  - EVIDENCE: same test: a click in card 11's block -> card 11 picked, playhead 3.47 s = its pose; the card row scrolled 721 px and the card is fully in view. The ruler 2 -> 3 s -> playhead 3.00.
- [x] M4 after a retime the trail/graph/dummy/card boxes all show the new timing (test the counts); the hold box's missing refresh fixed
  - EVIDENCE: same test, dummy ON and hit (placed 1.4 m out; the first version ran with the dummy off and its dummy check was vacuous; fixed): after a retime the trail/graph pass re-ran and ends at 4.21 s = what plays (the landed copy), the landed copy is a new object, the old Check findings are put away; the card boxes read the new value (0.60, read after the frame that frees the old panels). The hold box: now one undo step and the trail pass re-runs (before: `_refresh()` only, the trail/graph/dummy kept the old timing).
- [x] M5 HAND DRAG: grab a hand (or foot) and drag it in the view; the arm (leg) follows by IK within limits; Ctrl+Z; LOOKED
  - EVIDENCE: hand dragging ALREADY EXISTED (`_drag_joint`, "PULLING" -> `B.reach`); my round-6 pitch called it unbuilt, wrong. Measured it instead (`tests/hand_drag_test.gd`, the real drag function, mouse out 0.9 m and back): the part ended 45 / 516 / 673 mm (hand_r / hand_l / foot_r) from the mouse, because each move reached for "hand + this move" and lost whatever the limb could not follow. Fixed: the drag keeps its own target (`_grab`), each move reaches for it (also the locked-bat drag): 0 / 0 / 0 mm; no joint past a limit; Ctrl+Z exact. Added: past reach, a dashed yellow line + cross shows where the mouse is pulling, gone on release. LOOKED: `C:/Temp/tmp/shots/pull.png`.
- [x] M6 all suites PASS; Nick's scene files byte-identical
  - EVIDENCE: 13 suites PASS (math 9/9, spline, tween, rules, fix_test, mirror_test, flip_survey, tween_undo, monkey, fix_window, tools_window, timeline 23/23, hand_drag 9/9). `git status scenes/`: no modified scene (only the bo_sweep.json deletion that predates this session). Found on the way: flip_survey counted 33 scenes, not 32: `_wip/combo3_polished.json`, left by monkey_test's Polish; that test also passed "Polish wrote it" on a leftover with nothing written. monkey_test now checks the file's modified time moved and leaves `_wip` as it found it; the leftover deleted.

## N. Round 7: Fusion-360-style UI (Nick 10-14: "we could have an depth of ui like other programs like fusion 360 ... kinda friendly user")
Order: additive first (nothing Nick knows moves), layout changes last.
- [x] N1 S = COMMAND SEARCH: a box over the view; type a few letters, the matching commands list (name + shortcut), Enter/click runs it; every Animator-tools item, view, Check/Polish/Play, weapon, mirror is in it (test: each listed command runs)
  - EVIDENCE: `scripts/command_search.gd` (CommandSearch; checked first: no command list in body/dummy/fixer/main/moves/overlays/rulebook/scene/timeline; Godot's EditorCommandPalette is editor-only). 57 commands in `main._commands()`; a command with a key runs THROUGH that key's code (`_press`), so the two cannot differ. Every word typed must match (any order); a word-start hit ranks above a mid-word one ("view" -> 5 views, Big view, then Stepped preVIEW). `tests/command_search_test.gd` 19 ok / 0 FAIL, key events with real characters: S opens with no stray 's', a second S types, arrows+Enter, Esc runs nothing, typing 't ' in the box toggles nothing, a view click closes it; 53 commands RUN through the box's own path with 0 script errors, the 4 file-writers checked by binding. Top-bar button "Search (S)" + Help line; the bar ran off the screen once the button went in ("Animat"), fixed by shortening "view (arrows move it):" to "view:". LOOKED: `cmd.png` (hits only, no scrollbar), `cmd_all.png`. Window suites still PASS (tools, timeline, fix).
- [x] N2 VIEWCUBE: a small cube in the view's top-right; click a face = that view (front/back/left/right/top), follows the camera as it orbits; LOOKED
  - EVIDENCE: `scripts/view_cube.gd` (ViewCube; checked first: no gizmo/axes/compass code in scripts/, no addons/; Godot's view gizmo is editor-only). Drawn flat from the camera's rotation each frame; faces = where the camera sits for each view (main._cam). Bottom face added as view 6 (pitch 89). `tests/view_cube_test.gd` 17 ok / 0 FAIL: at 40 seeded random orientations, against the REAL camera's projection at the lens centre, each shown face points the way that side of the body projects (worst 0.00 deg, bar 2; CONTROL: a left-right flipped cube misses by 180, so it can fail); shown faces = exactly the sides facing the camera (0 wrong); a click on each of the 6 faces gives its view; a click off the cube does nothing; beside the right panel, in big view in the screen corner. NOTE: the shifted perspective lens draws a 30 cm arm up to 27.6 deg off the cube's direction (off-axis perspective; the cube is orthographic like Fusion's): reported, not barred. Labels shrink to fit each face (they overflowed at first). LOOKED: `cube_crops.png` (3 angles; read correct against the body and the floor's his-left marker).
- [x] N3 BROWSER TREE: Body > parts (fingers too) click = select that part; Scene > clips click = pick; LOOKED; test selects a finger by name
  - EVIDENCE: `scripts/browser.gd` (Browser, a Tree; checked first: main has the poses ItemList and the card row, no part tree; names reuse main's `nice()`). Left panel is now 2 tabs: Poses (first, as it was) + Browser: Body > Torso / Right arm (+ fingers > thumb..pinky > 3 joints) / Left arm / Right leg / Left leg; Weapon (only with one); Scene: name (N clips). `tests/browser_test.gd` 13 ok / 0 FAIL, clicks pushed to the WINDOW at the row's pixels (each click point first proven on its row): all 52 joints + the handle have rows; 'index, middle joint' under Right arm -> index_02_r selected, right panel titled with it; a pick in the view lights the row with no echo; a folded finger folder opens; combo3's 12 clips listed, click clip 11 -> card 11; weapon row hidden/shown with the weapon, a click selects the handle (starting from 'head', so the check can fail: it had passed vacuously before). FOUND + FIXED: a click on a clip row crashed Godot (illegal instruction): picking rebuilt the clip rows inside the Tree's own click; the rebuild is now deferred a frame. Finger rows say their finger ("index, middle joint") and the pick scrolls to the middle (deferred, it stuck at the top). LOOKED: `browser_crops.png`. Full sweep 16/16 PASS after it; scenes untouched.
- [x] N4 MARKING MENU: right-CLICK (not drag) on a body part = a ring of Reset / Mirror / Snap 90 / Clip / Pin trail; right-DRAG still orbits (test both)
  - EVIDENCE: `scripts/ring_menu.gd` (RingMenu; checked first: no radial code in scripts/ ("ring" hits are the ring FINGER); Godot's PopupMenu is a list, the gate asks for a ring). 6 wedges, up = Reset then clockwise Snap 90 / Copy to the other side (Mirror whole pose on a middle part) / CLIP / Pin a trail / Snap 45; each runs the existing function (pose ones through `_do`, undoable). Right press records where + the view's turn + the part; a release within 5 px on a part = a click: the wobble's turn is undone and the ring opens; farther = the orbit it always was. `tests/ring_test.gd` 18 ok / 0 FAIL, every event pushed to the WINDOW: right-click the forearm -> ring, part selected, view unturned; right-DRAG 60 px -> yaw 0 -> -24, no ring; right-click on the floor -> none; each label on its own wedge, middle/outside none, Esc and a middle click cancel; Reset 70 -> 0 (Ctrl+Z 70), Copy to right side (right forearm 0 -> 70, Ctrl+Z back), Snap 90 52 -> 90, Pin a trail, CLIP 0 -> 1 card. FOUND + FIXED: the ring was 0 x 0 px (`set_anchors_preset` keeps the old size): it drew but NO click could reach it, Esc was the only way out; now `set_anchors_and_offsets_preset`, and the test asserts it covers the window. The ring moves in from the screen edge so its title stays off the top bar (it sat on it); background near-opaque (the 3D label showed through). LOOKED: `ring_crop.png`.
- [x] N5 EMPTY STATE: no clips -> the bottom panel collapses to one line + the CLIP hint; LOOKED
  - EVIDENCE: `main._layout_bottom()`: the bottom panel's height follows the scene (BOTTOM_EMPTY 100 with no clips: scene row + the CLIP hint; the card row, timeline and play row hidden), and moves everything standing on it (side panels, status line, speed graph, the camera's centring). Called from `_rebuild_cards`. `tests/empty_state_test.gd` 11 ok / 0 FAIL on screen rects: start 94 px; first CLIP -> 315; both clips deleted -> 94; Ctrl+Z -> full again; combo3 -> full; New empty scene -> 94; big view; 0 overlaps and the camera centred in every state. FOUND + FIXED on the way: (1) adding / deleting / moving / Updating a card pushed NO undo step (a card's X could not be undone); all four do now, tested (delete, delete, undo, undo, move, undo). (2) the full panel needed 315 px and had 308: it ran 1 px off the window's bottom (pre-existing); BOTTOM_H 314 -> 321. LOOKED: `empty.png` (the body gets the full height, the side panels show their whole weapon section), `full.png` (unchanged layout). Full sweep 18/18 PASS; scenes untouched.
- [x] N6 TABS (layout): POSE / ANIMATE / CHECK / EXPORT ribbon groups the top-bar + play-row tools; nothing removed, every old button reachable (test counts them); LOOKED
  - EVIDENCE: one row, so the body loses no height: POSER, tabs POSE / ANIMATE / CHECK / VIEW, the tab's tools, then Undo / Redo / Search / Help always on the right. On/off tools are toggle buttons synced in `_refresh` (`ui_toggles`). Play row unchanged (Check / Polish / Fix stay there too); the Animator tools menu kept, at the end of ANIMATE. `tests/ribbon_test.gd` 28 ok / 0 FAIL, clicks pushed to the window: each tab lit alone, its row alone shown, '? Help' on screen (1590 of 1600) in every tab; ALL 14 of the old bar's buttons found, opened and on screen; His right -> yaw -90, Collision toggles and the button shows it, Reset body, Undo, Search; key T moves the Trail button, a click on it agrees, Speed graph lit and the menu's check agrees. FOUND + FIXED: two tabs lit at once (`set_pressed_no_signal` does not release a ButtonGroup); ANIMATE ran '? Help' off the screen (the duplicate 'Mirror scene' button dropped: it is in the menu on the same row). LOOKED: `ribbon_bar.png`, `ribbon_tabs.png`.
- [x] N7 all suites PASS; Nick's scene files byte-identical
  - EVIDENCE: 19 suites PASS (the 13 + command_search 13, view_cube 17, browser 13, ring 18, empty_state 11, ribbon 28); 0 script errors in any log. `git status scenes/ poses/ data/`: nothing modified (only the bo_sweep.json deletion that predates this session); `_wip` holds no test leftovers.
