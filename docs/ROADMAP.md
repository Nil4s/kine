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
Merged since the last full run: 25 / 20 (4 fighters at 60 fps (pose table bake); sit, stand, get up from the floor; plugin API; timeline markers with notes; stairs, wedge ramps, feet on uneven ground; crowd copies with variations; pose and scene packs (share/import); scene diff report; root motion path editor; multi-track audio (premix); multi-camera mocap; Euler unroll for exports; hand capture from video; dropped sword rigid physics; cape cloth (background bake); contact IK (hand on wall/table); hair ponytail; pose matching on transitions; clip warp; custom attributes; macros; batch export; camera sequencer (per-shot shake/focus); USD layers (pxr-checked; Alembic not written); FBX export (binary, Blender-checked)). Full run 4 (2026-10-19): 237/271 under load; re-run of 34 alone: 7 load or time-outs, 27 real (UI layout, units wording, duplicate keys, trail rebuilds, a pick drag), fixes in progress; proportions waits on Nick (skeleton.json hip height). Merged after run 4: corrective seam weld, face on the head, precise pick on the skin.

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
92. [ ] Walk / run generator along a path, real gait data
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
