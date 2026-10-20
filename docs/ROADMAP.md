# Kine roadmap: toward Maya / Blender, and past them (2026-10-18)

Three lists feed this: what Maya / Blender have that Kine lacks (`GAP_ANALYSIS.md`, 32 rows), what animators
complain about in every tool (`COMPLAINTS.md` has the first 10), and what no tool does yet. The 400 upgrades are
planned as 16 areas; each area becomes a numbered list of gates before agents take it.

## The 400, by area

| area | count | examples |
|---|---|---|
| Rigging and IK | 30 | spline IK spine, IK/FK snap per frame, stretch, reverse foot, space switching |
| Graph editor and keys | 30 | tangent weights, euler filter, breakdowns, retime tool, key reduction slider |
| Dope sheet and timeline | 25 | summary rows, scale around playhead, markers, sub-frame keys, ripple edit |
| Layers / clips (NLA) | 20 | strip blending curves, clip warping, pose-matching on transitions |
| Viewport and display | 30 | motion trails editable, ghosts per part, isolate, xray, silhouette, safe frames |
| Deformation and mesh | 30 | skin weights paint, corrective shapes, muscle bulge, own characters (mesh engine) |
| Physics and secondary | 25 | cloth, hair, follow-through on props, ragdoll to keys, rigid props |
| Mocap and video | 25 | multi-camera video, hand capture, contact cleanup, live webcam puppet |
| Import / export / pipeline | 25 | fbx out, alembic, usd layers, per-engine presets, batch export |
| Camera and shot | 20 | rack focus, shake, multi-shot sequencer, storyboard panels |
| Audio | 15 | lip-sync visemes, beat markers, multi-track, scrub-to-hear |
| Faces and hands | 25 | face rig, viseme sets, finger poses library, grip auto-wrap for any prop |
| Combat-specific | 30 | frame data, hitboxes, choreography exchanges, hit reactions, weapon trails |
| Biomechanics truth | 25 | torque limits, balance, injury load, fatigue, real-human speed bars |
| Workflow and UX | 25 | undo tree, version branches, hotkey editor, command search, crash-proof saves |
| Collaboration and cloud | 20 | shared review links, frame comments, live co-editing, asset store |
| **total** | **400** | |

## What animators complain about (beyond the first 10 in COMPLAINTS.md)

Crashes and lost work; rigs that break on retarget; export scale / axis mix-ups between engines; viewport too slow to
play in real time; hotkey overload and a steep first week; Maya's price; Blender's NLA being clumsy; mocap that needs
hours of cleanup; no way to tell if a motion is physically possible; reviewing with a director by sending videos back
and forth.

## The top 25 (what nobody ships)

1. **"Could a human do this?"** Every frame graded against real joint torques, balance and speed from biomechanics papers, with the frame and the reason.
2. **Frame data for fighting games:** startup / active / recovery frames and hitboxes drawn from the animation itself, exported to the engine.
3. **Choreography for two or more fighters:** an exchange (attack, parry, counter) laid out as one timeline, spacing and reach kept honest between them.
4. **Automatic hit reactions:** a hit's momentum drives the victim's reaction, then it's baked as editable cards.
5. **Phone video to clean animation:** one video in, foot contacts locked, jitter removed, cards out.
6. **Live webcam puppeteering:** pose the mannequin with your own body in real time and record it.
7. **Critique that points at frames:** "floaty at 1.2 s", "no anticipation before the swing", "foot slides 3 cm", using the 12 principles plus the rulebook.
8. **Type a move, get blocking:** "overhead axe strike, step in" becomes the key poses from the motion rules, ready to polish.
9. **Sketch to pose:** draw a line of action or a stick figure and the body follows it.
10. **Grips for any prop:** the hand wraps any imported mesh, not only the 4 weapons.
11. **Injury and load check for stunt teams:** joint loads per frame, flagged above published limits.
12. **Style transfer:** make this walk heavier, older, tired, or angrier, with the timing and spacing changing as real data shows.
13. **Secondary motion baked to keys:** hair, cloth and weapon wobble, computed and then editable like your own keys.
14. **Ragdoll to keys:** drop the body, pin a hand, let physics pose it, keep the result.
15. **Undo as a tree:** go back and branch without losing the other version.
16. **Versions like git, visual:** compare two versions of a scene side by side or overlaid, pose by pose.
17. **Review links:** send a link, the director comments on frame 42, and the comment shows on your timeline.
18. **Live co-editing:** two animators in one scene, each on a fighter.
19. **One-click engine delivery:** UE5, Unity and Godot presets with scale, axes and root motion checked before writing.
20. **Spacing from real motion:** ease presets measured from mocap ("a punch accelerates like this"), not generic curves.
21. **Lip-sync from audio:** visemes keyed from the sound file.
22. **Beat-synced timing:** the music's beats as timeline markers; snap hits to them.
23. **Motion-matching preview:** see how your clips will blend in a game's locomotion system before exporting.
24. **Character mesh engine:** build your own characters with any proportions, and the rig follows.
25. **Crash-proof by design:** every edit journaled, so no work is ever lost.

## THE 100, in order (Nick 10-18: all 25 + 75 from complaints; easy for beginners, deep for experts)

Status: `[ ]` open, `[~]` an agent is on it, `[x]` merged. **Full suite after every 20 merged** (count below).
Merged since the last full run: 0 / 20. Full run 5 (2026-10-19): 287/307 under load, fixes 5bed95c + f38bb89. Full run 6 (2026-10-19, after 99, 92, 10 sources, feasibility check, page bar, card strip, video IQ in the app, plant-all crash fix): 261/323; ~40 suites pass every check but crash at quit (0xC0000005, threads not stopped), ~20 real fails (UI layout after the page bar and strip, units wording, undo/baker), known: pathwalk knee 70.7/facing 10.5, videoiq 8 KNOWN FAIL, proportions waits on Nick. Fixes in progress (fxexit, fxui, fxcore).

**The milestone suite** (every 20): `python tools/run_par.py -j 20` (the GPU carries the windowed tests, so 20 Godot
sessions run where the CPU alone allowed 10), then only the failures re-run alone to split load flakes from real breaks.

### Wave A: what hurts now
2. [x] Crash-proof: every edit journaled; reopen after a crash at the last action (top-25 #25)
3. [x] Easy mode: a simple panel of 12 big actions (pose, key, play, undo, export) with the rest hidden; Expert mode shows all
4. [x] First-run tour: 60 s of guided steps on the mannequin (pose a hand, key, play)
5. [x] Hotkey cheat sheet overlay (hold ?) and a hotkey editor
6. [x] Better foot: heel / ball / toe-tip pivots as handles in the view (reverse foot you can grab), foot roll keyable
1. [x] Kill the toes curling up in walks: toe bend capped at real push-off (MTP ~44 deg walking) and only during push-off (wt-toes: scene.gd TOE_MTP_MAX / _toe_guard; tests/toes_walk_test.gd; docs/research/TOES.md)
7. [x] Better skeleton: split toes (big toe vs the other four), a real ankle subtalar axis (inversion / eversion)
8. [x] Foot planting that just works: mark a foot planted over a time range, it stays put to 1 mm, the leg solves
9. [x] One-click engine delivery: UE5 / Unity / Godot presets, scale + axes + root motion checked (top-25 #19)
10. [~] (in, experimental: behind its command until its bars are checked against the papers) "Could a human do this?": per-frame torque, balance and speed vs real-human data, with the reason (top-25 #1)
11. [x] Critique that points at frames: floaty, no anticipation, foot slide, twinning (top-25 #7)
12. [x] Fighting-game frame data: startup / active / recovery + hitboxes, exported (top-25 #2)
13. [x] Choreography timeline for 2+ fighters: exchanges, reach kept honest (top-25 #3)
14. [x] Automatic hit reactions from momentum, baked to cards (top-25 #4)
15. [x] Undo as a tree (top-25 #15)
16. [x] Phone video to clean animation: contacts locked, jitter off (top-25 #5)
17. [x] Ease presets measured from real motion (top-25 #20)
18. [x] Grips for any prop mesh (top-25 #10)
19. [x] Twinning check: left and right moving in perfect sync flagged (wt-twinning: scripts/twinning.gd, "Check: twinning" and "Fix: offset the picked side by 3 frames"; docs/research/TWINNING.md)
20. [x] Viewport playback at real time on heavy scenes (measure, then cache poses per frame)

### Wave B: the innovations
21. [x] Live webcam puppeteering (top-25 #6): helper + socket + fit + record built; no camera here, the test is camera-free (see the commit)
22. [x] Type a move, get blocking (top-25 #8) (restarted 10-18 night: retrieve-and-adapt from saved moves; the IK-from-scratch try missed by up to 52 cm)
23. [x] Sketch a line of action -> pose (top-25 #9)
24. [x] Injury / load check for stunt teams (top-25 #11)
25. [x] Style transfer: heavier, older, tired, angry (top-25 #12)
26. [x] Secondary motion baked to keys: hair, cloth, weapon wobble (top-25 #13)
27. [x] Ragdoll to keys with pins (top-25 #14)
28. [x] Scene versions with a visual diff (top-25 #16): "Versions: compare with" lays an older version over the open scene (magenta ghost at the playhead), lists the changes per card, and marks the timeline where a joint differs over 2 deg; "Versions: restore this one" is one undo step (scripts/version_diff.gd, tests/version_diff_test.gd)
29. [x] Review links with frame comments (top-25 #17)
30. [x] Live co-editing, one animator per fighter (top-25 #18)
31. [x] Lip-sync from audio (top-25 #21)
32. [x] Music beats as timeline markers, snap hits to them (top-25 #22)
33. [x] Motion-matching preview (top-25 #23)
34. [ ] Character mesh engine (top-25 #24) (held: Nick plans this as its own engine after Kine is done; same UE5 skeleton names)
35. [x] Weapon trails drawn and exported (smear frames)
36. [x] Hitbox / hurtbox editor per frame
37. [x] Parry / clash detection between two weapons
38. [x] Distance-to-opponent guide (range rings)
39. [x] Fatigue: a long fight slows the moves per measured data
40. [x] Weight feel: heavy weapons slow the wind-up per mass

### Wave C: complaints, beginners ("make it easy")
41. [x] Pose by dragging any part with sensible defaults (no axis picking)
42. [x] Auto-key toggle that is obvious (red frame)
43. [x] "What went wrong?" button: explains the last error in plain words
44. [x] Templates: walk, run, jump, punch, sword swing as starting scenes
45. [x] Undo that never surprises: names each step in the menu
46. [x] Snap a pose to the floor in one click
47. [x] Big timeline handles, retime by dragging a card's edge
48. [x] Preview at real speed vs every frame toggle, clearly labelled
49. [x] Tooltips with a 2-second video of the tool
50. [x] Save prompts: never lose a scene by closing the window
51. [x] Scene thumbnails in the browser
52. [x] Search everything (commands, poses, scenes) from one box
53. [x] Copy a pose between fighters
54. [x] One-click mirror of the whole animation
55. [x] Simple ease slider per card (no graph editor needed)
56. [x] Clear units everywhere (cm, deg, s, frames)
57. [x] Export dialog that says what each engine needs
58. [x] Dark / light theme and UI scale for laptops
59. [x] Recent files and autosave restore list
60. [x] Gentle errors: never a crash dialog, always a next step

### Wave D: complaints, experts ("give me depth")
61. [x] Spline IK spine
62. [x] IK/FK snap per frame with no pop
63. [x] Space switching (hand in world / chest / weapon space) with no pop
64. [x] Euler filter / unroll for exported curves
65. [x] Tangent weights in the graph editor
66. [x] Breakdown keys and key types (key / breakdown / in-between) like Blender's
67. [x] Retime tool: scale a range around the playhead
68. [x] Key reduction slider with an error readout
69. [x] Editable motion trails (drag the arc)
70. [x] Per-part onion skin
71. [x] Corrective shapes on the mesh (elbow, knee)
72. [x] Skin weight paint for imported characters
73. [x] Finger pose library + per-finger curl sliders
74. [x] Face rig: brows, jaw, eyes, visemes
75. [x] Multi-shot camera sequencer
76. [x] Camera shake and rack focus
77. [x] Multi-track audio
78. [x] FBX export
79. [x] Alembic / USD layered export
80. [x] Batch export of many scenes
81. [x] Python-free scripting: macros recorded from commands
82. [x] Custom attributes on parts (keyable)
83. [x] Clip warping (time-warp a strip)
84. [x] Pose matching on clip transitions
85. [x] Rigid prop physics (a dropped sword falls)
86. [x] Cloth on a cape
87. [x] Hair strands follow-through
88. [x] Contact-aware IK: hand slides along a wall / table
89. [x] Multi-camera video mocap
90. [x] Hand capture from video
91. [x] Root motion editor (path curve on the floor)
92. [x] Walk / run generator along a path, real gait data
93. [x] Stairs and slopes: feet plant on uneven ground
94. [x] Sit / stand / get-up from the floor helpers
95. [x] Crowd: copy a fighter with variations
96. [x] Asset store of poses / moves (share and import)
97. [x] Timeline markers with notes
98. [x] Scene diff report (what changed, in words)
99. [x] Performance: 4 fighters at 60 fps playback
100. [x] Plugin API for new tools

## How to run it

Waves of 10 agents (one machine runs about 10 Godot tests at once; main.gd merges are the other bottleneck), one
area or a few top-25 items per wave, merged and tested in CI at the end of each day.

## Round 2: 25 upgrades (2026-10-19)

The first 100 are done except 10 (human check, experimental) and 34 (mesh engine: the MODEL page in docs/PAGES_PLAN.md).
Round 2 takes from "Beyond the 100" (UPGRADES_100.md: cinematic, monkey brain, AI easy), the pages plan and today's
open threads. **Full suite once after all 25 are merged** (Nick 2026-10-19: tests only once per 25 for faster development).
Merged in round 2: 25 / 25 (full suite 2026-10-20 01:35: 323/360 before fixes; fixes merged for units, icons, search_one_list, say_next, toolbar, symmetry, undo_audit x4, pages, cardstrip, r3, text_blocking, video_cleanup, retarget, vroot, videoiq 1b, proportions capsules). Round 3 count: 23 / 25.

- [ ] R1. Lighting presets on the shot camera: three-point, rim, noir, daylight (one click, undo, saved with the scene).
  Step 3 merged: key at 52 deg / noir 90 deg side / sun 60 deg (Brown), noir 4.79 and rim 1.56 pass; three-point 1.48 (bar 1.8) and daylight 1.39 (bar 1.4) still short: fill capped by the key:fill bar lights the far half.
- [x] R2. Depth of field on the shot camera (focus on the picked part, f-stop), visible in the viewport and the playblast.
- [x] R3. Motion blur in the playblast (sub-frame accumulation), off by default.
- [x] R4. Contact shadows under feet and props (soft blob that darkens as the foot nears the floor).
- [x] R5. Render the shot sequence to an mp4 (ffmpeg), camera cuts from the camera sequencer.
- [x] R6. One obvious next step on every page (a single line, never empty, clickable).
- [x] R7. Cold-start test: a script with no knowledge of the UI reaches "a punch that lands" through the command registry only.
- [x] R8. Drag a pose from the library onto the card strip to insert it there.
- [x] R9. Local HTTP API: the command registry verbs over JSON (describe, run, check, shot), localhost only.
- [x] R10. Blind-agent maths: "what would this angle do" (reach, collisions, balance) as a text answer over CLI/MCP.
- [x] R11. BODY page: body mass changes girth (per-segment radial scale of the skin), not just the readout.
- [x] R12. BODY page: save / load named characters (user://characters), the man/woman blend saved in the scene schema.
- [x] R13. Video import off the main thread (retarget/IQ in a worker; progress bar; the window never freezes).
- [ ] R14. Video import fit accuracy: foot plants cover >= 70% of stance (vroot bar 26% now). Step 1 merged: 59% (slide 0.8 cm, false plants 1.4%); Step 2 merged: heel pivot + stance detection fixed (vroot x0.85 passes), coverage 57%/50%; the remaining loss is the video fit holding the heel 3-6 cm up at heel strike.
  Step 3 merged: sole snap by leg IK + toe-off contact; coverage 57 -> 61% (x1.00), 50 -> 51% (x0.85), sole height now passes (1.7 cm). Open: whole stances the leg can't reach under the 2 cm hip-drop cap; next is a horizontal pelvis shift toward held feet (design change, not tuning).
  Step 4 merged: horizontal pelvis shift toward held feet (cap 5 cm, eased by plant weight) + 98% leg reach: coverage 55 -> 57% (x1.00), 50 -> 54% (x0.85). Raising the cap to 50 cm only reaches 59%: both feet are pinned ~1.02x leg reach apart, so the cause is the root fit following the tracker's foot (next). x1.00 slide reads 1.28 cm (red) since the TRIM=2 revert.
  Step 5 merged: 'strides too long' REFUTED (fit strides are short); the fitted hip RISES in stance (0.937->0.963 m vs true 0.919), so stance legs sit at 98-99% reach. REACH_DROP 2->2.9 cm, TRIM 2->1: coverage 65% / 62% (bar 70). Next: re-solve stance legs by IK in the fit so the pelvis keeps its true height; x1.00 slide 1.28 cm at heel-off (th) still red.
- [x] R15. Import a physics reaction: one command loads a MuJoCo/Isaac BVH (tools/physics) as a new scene of cards.
- [x] R16. Hit reaction picker in STAGE: thumbnails of the physics hits, drop one onto the struck fighter.
- [x] R17. Timeline playhead overlay redraws with the playhead (status 2.90 s while the line drew at 1.69 s).
- [x] R18. Drag to reorder cards in the strip (thumbnail follows the mouse, one undo step).
- [x] R19. Multi-select cards in the strip, batch retime / delete / copy.
- [x] R20. Timed version snapshots (every N minutes while edited) with the scene diff report.
- [x] R21. Pose library search by words ("guard", "crouch", "low kick") over names and auto tags.
- [x] R22. Face expressions for the painted face (pain, effort, anger, surprise) keyable on cards; hit reactions use pain.
- [x] R23. Weapon trail in the playblast and the mp4 render.
  Step 1 merged: grip-to-tip ribbon over 8 frames in playblast and mp4, off is byte-identical. Open: the ribbon renders as a solid opaque blue wall (the alpha fade does not show), and it runs out of frame on overhead swings.
  Step 2: additive translucent ribbon on the last 30% of the bat; newest/oldest quad pixel change 137/23 (ratio 6), bodies show through. Looks big at 38 m/s because each frame's quad spans ~1.3 m of arc.
- [x] R24. Hand-written balance in the app reads the MuJoCo numbers: push-recovery limits shown in CHECK (step / fall thresholds).
  Measured: in 11 of 32 body/direction cells the humanoid has no 'steps' band (chest forward absorbs 26 N s, at 27 it steps then falls), so the table bar is absorb <= step < fall; the empty cells are listed in no_step_band.
- [x] R25. Onboarding: first launch opens BODY then POSE with a 3-step guide (skippable, never again after done).
- [x] R26. Share with friends by QR code (Nick): a pose or short clip packed (compressed) into a QR image; Kine reads a QR from an image file or the webcam and opens it. No server, no account.
- [x] R27. Next-pose suggestions while animating (Nick): after the current card, 3 ghost poses of the likely next move, learned from your own scenes (what you usually clip after a pose like this), the motion database (what follows this pose in real clips) and move phases (wind-up -> contact -> follow-through -> recover). Tab or click takes one as a new card.

## Innovations (Nick 2026-10-19: "innovations is the part I want you to work harder on")

Things other animation tools don't do, in the spirit of R27 (next-pose suggestions). These go FIRST into free agent
slots; the remaining R items fill in behind them. Each one is judged by: does it save Nick a step he takes every day,
or show him something he couldn't see before? Numbers and a screenshot, like every item.

- [x] I1. Make it physical: one button sends the clip through the MuJoCo humanoid (tracking controller) and shows where
  the motion is physically impossible (feet slide, balance lost, joint torque above human limits) as red spans on the
  timeline, with "physical version" ghosted next to yours; accept per span.
- [x] I2. Reaction from the hit: when the attacker's weapon or fist touches the other fighter, Kine measures the impulse
  (the swing.py contact model) and generates the struck fighter's reaction (MuJoCo now, the Isaac policy later), placed
  at the contact frame. No picking clips: the hit decides.
  Step 1 merged: command + MuJoCo reaction + impulse label work (J rises with speed, fist 26.1 vs Walilko 26 N s, attacker untouched, one undo). Open: bat J/v is constant 0.71 kg while swing.py's rises 0.80-1.10 kg with speed (0.65x at 32.6 m/s); the sim starts upright (root yaw/lean at contact not carried).
  Step 2: bat effective mass from the striker's arm pose at contact (Khatib operational-space mass; Cross 1999 free bat), J=(1+e)·mu·v; swing.py agreement 1.26/1.03/0.91/0.76 at 21-33 m/s (bar 0.7-1.3, thin at both ends: J/v doesn't rise with speed). Root lean/yaw and 3D impulse now carried into react.py (20 deg lean starts at 20.0).
- [x] I3. Counter suggestion: for the attacker's current card, suggest the defender's block / slip / parry pose that
  intercepts the weapon path (geometry of the swing arc against the defender's reach) - choreography help.
  Done: on combo3's bat strike Kine proposes BLOCK and PARRY on fighter 2 (forearm 0.1 / 2.2 cm from the path, meeting it ~30 cm in front of the body, starting 0.42 s after the wind-up), Tab/Enter/one undo; a miss says 'nothing to counter'. Open: no slip/step-back answer clears this swing; labels overlap the name tag.
  Step 2: STEP-BACK (15 cm step, pinned foot slides 0.70 cm, tip misses by 6.5 cm) and DUCK (head-height swing, clears by 6.5 cm); 3 counter kinds on combo3; labels stacked clear of the name tag. Placing a duck is untested.
- [x] I4. Timing coach: compare each move's timing to real-motion references (move database) and to the 12 principles
  (anticipation 2-3x shorter than action for fast hits, overshoot on follow-through); suggest exact holds/moves with a
  "sounds right" preview; accept one by one.
- [x] I5. Say it, see it: type "low guard, weight on back foot, bat cocked over right shoulder" and get the pose,
  locally (blind-agent maths + pose search + IK, no cloud); the parts it couldn't place are named.
- [x] I6. Style dial: "heavier / tired / angry / sneaky" sliders that change a whole clip, learned as deltas from Nick's
  own clips (spacing, posture, amplitude), not hand-written rules; undo as one step.
  Step 1 merged: 4 sliders, spreads measured on Nick's 11 clips (move 1.19 log, amplitude 0.78 log, spine 13.7 deg, head 3.6 cm), cited directions, 0 = byte-identical, one undo. Open: angry +1 takes peak hand speed to 89 m/s and moves to 0.06 s (no human speed cap), strike contact drifts 140 mm for angry.
  Step 2 done: speed cap (cited 11.95 m/s or the move's own neutral peak, whichever is higher): angry +1 peak 89.4 -> 31.3 m/s; contacts re-solved by IK, drift 140 -> 0 mm (all styles <= 7.2 mm). Open: applying a slider takes 4.4 s; combo3's strikes are already 23-31 m/s in neutral (non-human, Check's job).
- [x] I7. Auto camera: for each beat (wind-up, contact, recover) suggest a shot camera from film grammar (180-degree
  rule, lead room, closer on contact), as ghost frames you click to keep.
- [ ] I8. Force view: per card, the joint torques and ground forces from inverse dynamics, coloured on the body (green
  easy, red beyond a strong human); "where does the power come from" for a strike (hip -> shoulder -> elbow sequence).
  Step 1 merged: torque colours + power chain (hip 3.025 > trunk 3.033 > shoulder/elbow 3.042 s on combo3), static squat knee matches by hand, 34 ms per clip. Open: at 3.05 s lumbar reads 4122 N m while the knees read 31 N m; a bottom-up Newton-Euler can't give that pair (the lumbar load must pass through the legs), so the chain likely runs top-down from a kinematic pelvis; final test not re-run after a bar edit.
  Step 2: ground force from whole-body momentum (push-only, friction 1.0), CoP from angular momentum, residual shown as a red NEEDS OUTSIDE FORCE badge (combo3 at 3.05 s needs 11804 N = 16 body weights: card 9 throws the head 0.65 m in 0.16 s). Open: bar 8c (hips 0.53 of lumbar on a slow trunk flexion, bar 0.8), so i8 is red.
  Step 4: bar 8c (hips >= 0.8 x lumbar) replaced after the result: the pelvis balance shows the hip/lumbar ratio is not invariant (hips = lumbar + lever + CoP shortfall; a 0.4 s bend needs 871 Nm the feet can't give). New 8c/8d/8e bars: identity to 1%, flagged as needing outside force, slow bend feasible. Nick to judge the bar change.
- [ ] I9. Sketch to pose: draw a stick figure over the viewport with the mouse; Kine fits the body to it (2D lines ->
  3D pose with limits and balance).
  Step 1 merged: strokes recognised, fit lands on the strokes in screen space (<= 2 px), missing limbs untouched, one undo, 48 ms. Open: 3D recovery, 29 of 42 library fits have a bone > 10 deg off (trunk twist not in a stick figure, depth-axis bones mirror-ambiguous, an 8.7 deg error even with no tremor).
  Step 2 merged: library-pose depth prior + per-limb depth refinement; bad fits 29 -> 19 of 42, missing-arm 8.6 deg (passes). Open: a single view can't settle bones near the picture plane (~8 deg per px of stroke error) or toward the camera (mirror pair); next is a click-to-flip limb depth in the UI and shoulder/hip-line strokes for trunk twist.
  Step 3 merged: flip handles on ambiguous elbows/knees (one undo), shoulder/hip-line strokes read +-30 deg twist within 1 deg. Open: the oracle with <= 2 flips fixes only 23 of 42 (bar 36): most failing fits aren't a mirror pair, the right answer isn't among the 4 ray-sphere candidates.
- [x] I10. Your moves learn you: the R27 habits index also learns your timing and favourite in-betweens, so new
  cards come pre-timed the way you usually time them (shown as "your usual 0.18 s", one key to accept).
- [x] I11. Fight phrase builder: give it the attacker's combo and it builds the defender's whole answer chain (I3 per
  beat: block, slip, parry, counter) and keeps the pair at fighting range (each strike's tip reaches the target, nobody
  overlaps), flagging beats where the distance makes the move impossible.
- [x] I12. Smart drag: dragging one joint moves the rest of the body the way YOUR poses move together (the
  co-variation learned from Nick's library and scenes, principal directions), so pulling a fist back also turns the
  hips and shifts the weight like he would; hold Alt for the old one-joint drag.

- [x] I13. Impact frames from the hit: at each contact Kine adds hit-stop (a hold of 2-6 frames), a camera shake and a
  squash on the struck part, all scaled by the measured impulse (I2), so a light jab barely pauses and a bat to the head
  freezes; one undo step, previewed first.
  Step 1 merged: hit-stop 2/4/6 frames for J 5/15/27 N s, shake 1.0/2.6/4.2 cm, squash 0.97-0.90, later keys shift exactly, one undo. Open: the impact tags aren't saved (Remove fails after reload), the squash is too subtle to see, the preview has no shake.
  Step 2 merged: impact tags saved in the scene ('impact' record, Remove works after reload), squash 0.92->0.85 along the blow with volume kept, camera shake in Preview; i13 PASS.
- [x] I14. Rehearse against yourself: record a short phone video of Nick doing the move, and Kine lays his real timing
  and joint curves over the animated clip, card by card, with "you were 0.08 s faster on the strike, your hip turned
  20 deg more" lines.
  Done on a synthetic take: DTW on 36 joint angles finds the strike 0.06 s faster (bar 0.08 +-1 f) and hip +20.0 deg on the right cards; Use my timing within 0.024 s; one undo each. Open: not yet run on a real phone video.
- [x] I15. Fight to the beat: with music loaded, Kine moves each contact onto the nearest beat (or off-beat on
  request) while keeping every move inside the timing coach's human range (I4); moves that can't reach a beat are
  flagged, never forced.
  Done: 3 of 3 combo3 contacts land 0 ms from a 120 bpm beat, off-beat and every-2nd/downbeat grids work, unreachable contact flagged with its reason, one undo. Own numbers (not sourced): wind-up 0.5x-2x, 0.10 s floor.
- [ ] I16. Realism score: one number per clip, "how real is this", from the judges Kine already has (physics judge I1,
  torques I8, push limits R24, timing coach I4, Check's human limits), with the 3 biggest reasons and a one-click fix
  for each (accept span, timing coach, Check fix); the score is shown on the scene card and re-scored after each fix.
  Step 1 merged: score = 100 - sum(weight x share flagged) over Check red/yellow, timing coach, push limits, force view, physics (when cached); combo3 21, calm walk 85, no findings 100, each fix one undo and raises the score. Open: a cold score takes 4.2 s (bar 200 ms holds only when cached); the fix button reads 'Fix: Fix:'; the timing coach and Check can disagree on a fix.
  Step 2 merged (partial): FrameMemo samples each frame once for all judges, window narrowed for pose-only edits, predicted gains on fix buttons; repeat score < 200 ms, empty scene 2.6 ms. Open: re-score after a timing fix 945 ms (bar 400) - Rulebook.check and force analysis over all frames still ~450 ms; one timing fix 0.15 off cold.
  Step 3 merged: incremental == cold to 0.000 on all fixes (reuse only within 0.5 ms or inside holds), holds played once. Profile REFUTED the 'rules + force' premise: rules ~1 ms, dynamics ~45 ms; the cost is Body.apply_true at ~2.8 ms/frame. Re-score 644-982 ms (bar 400). Next: cheaper apply_true / Body.plant, or worker threads with cloned Scene+Body checked bit-identical.
- [x] I17. Learn my style: Kine reads every clip Nick made (scenes/, his poses) and builds a style fingerprint (his
  usual timing per move kind, holds, guard height, stance width, favourite transitions); new clips and Next poses
  default to it, and a "like Nick" / "neutral" toggle shows the difference. Learns locally, nothing leaves the PC.
  Done: fingerprint from 11 of Nick's clips (strike 0.15 s move, wind-up 0.33 s, usual wind-up > strike); new cards take his median; Use my style stays in the human range; one undo. Open: guard height/stance read the same shared 'ready' pose on every clip, so they say little yet.
- [x] I18. Fight distance keeper: choreography help that keeps two fighters at a real fighting range (measured
  reach of each strike + weapon), flags spans that are too close (jammed) or too far (the strike can't land), and
  offers a one-click root slide of the defender (feet planted, no skating) to fix each span.

  Done: combo3 strikes 0.5 m too far flagged, slide 46.9 cm puts the tip within 0.3 cm, plant slide 0.71 cm; jammed fixed by sliding back; correct spacing changes nothing; one undo. Open: the full combo3 has no single spacing where all 3 strikes land (third strike steps another way).
- [x] I19. Fight rhythm: a tempo map of the exchange (who attacks, who defends, beats between), flags monotony
  (same interval three times, same side four times) and dead air, and suggests a pause, a feint or a change of side
  at each flag, one click each. Choreography help read from the clip itself.
  Merged: tempo map, monotony/dead air/rush flags, timeline strip, pause/change side/feint stub; i19 PASS.
- [x] I20. Feint maker: turn a strike card into a feint + real strike (the feint sells the same line, stops at 40-60%
  of the reach, the real one comes from the other side), timed so the defender's reaction (I3's counters) bites on
  the feint; physically checked by the timing coach and Check.
  Merged: feint stops at 50.3% of reach, tip within 1.87 cm of the original line, real strike OTHER SIDE / LOW lands, counter moved onto the feint, recover card after a mirrored strike; i20 PASS. Ghosts overlap on the attacker.
- [x] I21. Sell the hit: for the shot camera, check each strike as the camera sees it. A miss that should read as a
  hit must overlap the target on screen (the stunt "cheat angle"); a real contact gets a SAFETY flag. Suggest the
  camera move or strike offset that sells it, one click each.
  Merged: SOLD/NOT SOLD/UNSAFE through the shot camera, camera turn and aim offset fixes; i21 PASS. Camera turn moves the whole shot.
- [x] I22. Choreograph to the song: from a loaded track's beats and loudness, lay out a fight skeleton (exchange
  density follows the music's energy, pauses on quiet bars, the biggest hit on the loudest downbeat), built from
  Nick's own cards/moves (I17 style, Next poses) and checked by the timing coach and Check; a plan to edit, not a
  finished fight.
  Step 1 merged: RMS energy per beat -> strikes per bar, biggest on loudest downbeat, contacts on beats, new scene on Accept; i22 test OK. Open: Check finds 13 must-fix on the result (bat tip 40-45 m/s: the coach's fist range used for a bat), fighters overlap (ARMS hit 6.7 cm), quiet bars have no circling step, planning 18 s.
  Step 2 merged: tip speed timed per weapon (Check 0 must-fix), defender placed by the distance keeper (no overlap), circling steps on quiet bars, plan 1.4 s; i22 OK. Open: screenshot doesn't frame both fighters.
  Screenshot fixed (both fighters framed, placement bar 7a); clean mode now hides panels.
- [x] I23. My combos: mine Nick's own scenes for card sequences he repeats (same strike kinds in the same order, timing
  within his style spread), name them ("jab-cross-hook, your 0.15/0.2 rhythm") and offer them as one-click phrases.
  Merged: 5 combos mined from Nick's 11 clips, one-click insert with his poses and mean timing, cache by mtime; i23 PASS. Sub-phrases listed beside their longer combo; style-spread filter not applied.
- [x] I24. Drag the balance: drag the centre-of-mass marker and the body rebalances to put it there (hips, knees,
  ankles, trunk lean solved within limits, feet planted); red when it leaves the support.
  Merged: COM drag with feet planted (8 cm shift: pelvis 9.6 cm, no lean), edge clamp red/amber, drag down bends knees; i24 PASS. Open: screenshot camera clips the body; ankle-limited case (lean-heavy) untested.
  Screenshot fixed (whole body + support polygon, placement bar 5b).
- [ ] I25. Breakfall check: on a fall or knockdown, judge the landing like a stunt coach (chin tucked, head clear
  of the floor, impact spread over arm slap/shoulder/hip, no straight-arm catch) with one-click fixes.
  Step 1 merged (partial): fall finder, 4 verdicts, tuck/slap/roll fixes, panel + badge; i25 2 FAIL: on a FORWARD fall a chin tuck drives the face into the floor (forward falls need the head turned aside, as in mae ukemi; tuck is for backward falls), and the slap lands harder (6.3 m/s).
- [ ] I26. Learn from my edits: record which suggestions Nick accepts, undoes or edits after (Next poses, Check
  fixes, timing coach, counters) and how he changes them; rank future suggestions by what he keeps, and say why
  ("you usually shorten this wind-up by 0.05 s").
  Step 1 merged: journal (accept / undo 30 s / edit 2 min), kept-rate sort and learned delta on timing coach + next pose ('you usually shorten this by 0.05 s - applied'), counters sorted, lessons panel + reset; i26 OK. Open: Check and realism fixes not hooked; counter/rhythm edits not watched.
- [x] I27. Throw and catch: release a prop from one hand and the app solves the ballistic arc (gravity, spin from
  the release angular velocity), the flight time, and places the catching hand on the arc at the catch frame;
  red if the catch needs an impossible reach or a hand speed outside human range.
  Merged: ballistic arc from the release hand (0.0001 mm vs analytic), catch by IK within reach and 12 m/s (heuristic), red out-of-reach / too-fast; i27 PASS. Spin flown about vertical only; another fighter's hand only via the API.
- [ ] I28. Safety sheet: one pre-shoot report for the stunt crew over the whole scene: every real contact and its
  speed, weapon tips passing within 15 cm of a face, falls and their breakfall verdicts, unsold/unsafe strikes, with
  time, fighters and a thumbnail per item; exported as a printable HTML page next to the scene.
- [x] I29. Match the reference's timing: from a reference video (video import), find its beats of motion (peaks of
  limb speed: wind-up, strike, settle) and retime the clip's matching cards to them, keeping the poses; shows both
  speed curves overlaid.
  Merged: limb-speed events, offset-aware alignment that skips extra actions, retime of cards + keys; worst event 16.7 ms (one 60 Hz sample); i29 PASS. Reference must be a scene made from a video (picked by hand).
- [ ] I30. Weapon weight: from the prop's mass and length (inertia about the grip), compute the wrist/shoulder torque
  each swing needs vs human strength, and flag swings that feel weightless (no wind-up, no follow-through, instant
  stops) with fixes that scale anticipation and overshoot to the weapon's inertia.
- [x] I31. Precog check: every defender reaction (block, slip, step-back, flinch) must start at least a human
  reaction time after the attacker's move becomes readable; flag "precog" answers (too early: reads as rehearsed) and
  "late" answers (the hit should have landed), with one-click retimes.
  Merged: PRECOG (< 0.2 s after the wind-up is readable, Woodworth & Schlosberg) and LATE flags with retimes; i31 PASS. Onset read from card times, not limb speed; step-backs/flinches not matched.
- [ ] I32. My camera: learn Nick's shot habits from his own shot cameras (lens, height, distance in body heights,
  angle to the line of action, cut timing relative to contacts) and frame new shots his way; say which habit it used.
- [ ] I33. Reaction direction: a struck body must move away along the blow's impulse (and turn about the right
  axis given where it was hit); flag reactions that go the wrong way or start before contact, with a fix from
  the hit physics.
- [ ] I34. Fatigue: track each fighter's mechanical work over the fight (joint power from the force view, summed);
  as it builds, real fighters slow, drop their guard and breathe; flag a fighter still at full speed late in a long
  exchange and offer a "tire him" pass (slower moves, lower guard, longer recovers, scaled to work done).
