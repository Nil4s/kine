# Poser: 100 upgrades (round 8+ backlog)

Written 2026-10-15 while usage was nearly out. **Cook this when the limits reset.**
Rules: for each item, write a test or screenshot first, then mark it done here with the evidence (same as GATES.md).
Never touch scenes/, poses/ or data/ unless an item says so. Run all suites after every 10 items.
Tags: [BUG] [UI] [FN] function · [STY] style · [UX] user-friendly · [AI] easy for an AI to use

## A. Bug hunt (1–15)
1. DONE (round 8: undo_audit_test: 31 edit commands, 3 had no undo (fixed)) ~~[BUG] Audit every action for undo coverage, not just cards: scene settings, clip rename, browser reorder, ring actions.~~
2. DONE (round 8: undo_fuzz_test: 4 seeds x 40, exact after Body.state()) ~~[BUG] Fuzz test: 500 random commands, then undo all of them, then compare the scene against the start. It must be byte-identical.~~
3. DONE (round 19: Scene.MIRROR_SCENE / MIRROR_CARD, mirror_list_test; plant and bad_frames fixed) ~~[BUG] Mirror: keep checking that flags (moving_holds etc.) are not copied by mistake. Write the list of flags that mirror must NOT copy.~~
4. DONE (round 21: small_window_test; compact labels + More at 1280, the window's minimum 1280 x 720) ~~[BUG] Ribbon overflow at small window sizes (1280x720, 1024x768). Take a screenshot of each tab.~~
5. DONE (round 21: ring_edges_test, 8 spots x 3 sizes; no change needed) ~~[BUG] Ring menu near screen corners at every DPI scale (100/125/150%).~~
6. DONE (round 20: browser_place_test; the scroll jump and the theme rebuild fixed) ~~[BUG] Browser tree: do the selection and scroll position survive a refresh and a scene load?~~
7. DONE (round 20: search_one_list_test: 84 commands, each once, through tabs/theme/scale/scene) ~~[BUG] Command search: duplicate or stale entries after a tab switch. Index count must stay 57+ and never repeat.~~
8. DONE (round 18: scrub_bounds_test, real drags: it already clamped; now held to it) ~~[BUG] Speed graph scrub past the last frame or before 0.~~
9. DONE (round 19: ghosts_follow_test; stale ghosts at 0-1 cards fixed) ~~[BUG] Spacing ghosts left visible after a clip change or delete.~~
10. DONE (round 20: empty_back_test, to the pixel; New empty scene left the speed graph up: fixed) ~~[BUG] Empty state → load scene → empty again: layout must restore exactly (the round 7 test found this).~~
11. DONE (round 18: edge_counts_test; fixed the spline's first frame) ~~[BUG] Interpolation at card boundaries with 1, 2 or 30 cards (edge counts).~~
12. DONE (round 21: flip_survey over scenes, _wip, _archive and every mirror: 62 runs, 0 over) ~~[BUG] Gimbal survey: also run it on mirrored and user-made scenes, not only the 32 shipped ones.~~
13. DONE (round 17: names_disk_test: any name as typed, a safe file name, nothing escapes scenes/) ~~[BUG] Saving with an unsaved, renamed clip. Check what happens to unicode and space characters in names.~~
14. DONE (round 8: run_all.sh fails on any SCRIPT ERROR) ~~[BUG] Godot errors and warnings during a full test run must be 0. Gate on the log, not on a visual check.~~
15. DONE (round 19: popup_leak_test, 5 pop-ups x 200: none leaks) ~~[BUG] Memory/node leak: open and close the tools window 100 times, then count the nodes.~~

## B. Fusion-style UI (16–35)
16. [UI] Timeline at the bottom like Fusion: the cards become feature icons on a strip, with drag to reorder.
17. [UI] Rollback marker: drag a bar on the timeline to see the pose "as of" card N.
18. [UI] Right-hand properties panel that is context sensitive: it shows whatever is selected (part, card, clip).
19. [UI] Each ribbon tab gets grouped sections with labels under them (POSE: Select | Transform | Constrain).
20. [UI] Dropdown arrow under the big ribbon buttons for related sub-commands.
21. [UI] Marking menu v2: 8 wedges plus an overflow list, gesture-flick support (flick without waiting for the menu).
22. DONE (round 22: edges/corners, house mark, 0.3 s tween the short way; cube_views_test) ~~[UI] ViewCube: click edges and corners for 3/4 views, a home button, and smooth tweened camera moves.~~
23. [UI] Navigation bar at the bottom center: orbit/pan/zoom/fit/grid toggle.
24. [UI] Browser: eye (visibility) and lock icons per part, plus a folder per limb chain.
25. [UI] Browser: a "Clips" and a "Scenes" folder, so the whole document lives in one tree.
26. [UI] Data panel: a scene/clip file browser with thumbnails, toggled like Fusion's data panel.
27. DONE (round 9: part + angles or weapon, card n/N, playhead, Check count with "changed since"; status_bar_test. No fps: the scene plays in real time, so frame/fps would only repeat the playhead) ~~[UI] Status bar: selected part, joint angle readout, frame, fps and rule warnings count.~~
28. [UI] Floating mini toolbar near the selection (like Fusion's in-canvas manipulator values).
29. [UI] In-canvas numeric entry: type an angle while dragging, Tab to switch axis.
30. DONE (round 23: diamonds in the timeline ruler, merged with counts, click = the finding; timeline_marks_test) ~~[UI] Rule warnings shown as icons on the timeline cards (foot slide, gimbal), clickable to jump.~~
31. [UI] Split view: front and side at the same time.
32. [UI] Tool tips with a short GIF/preview of what the tool does.
33. [UI] Resizable, dockable panels that remember their layout per user.
34. DONE (round 17: keys_overlay_test: ? opens every keyed command, from the registry) ~~[UI] Keyboard shortcut overlay (? key) generated from the command registry.~~
35. [UI] Selection highlight: hover pre-highlight in the viewport and browser in sync.

## C. Style (36–48)
36. DONE (round 9: scripts/tok.gd; theme_test audits every Color( literal left, each with its reason) ~~[STY] A single theme token file (colors, spacing, radius, font sizes). No hardcoded colors in scripts.~~
37. DONE (round 9: VIEW > Light, remembered; contrast >= 4.5:1 measured from the tokens in both palettes) ~~[STY] Dark theme close to Fusion's charcoal plus one accent color; and a light theme.~~
38. DONE (round 9: scripts/icons.gd, 26 icons drawn in code, tinted by the theme; icons_test) ~~[STY] Icon set: consistent 24px line icons for every ribbon command (no text-only buttons).~~
39. [STY] 4/8px spacing grid audit across all panels.
40. [STY] Typography: 2 sizes and 2 weights max. A label and value style for the properties panel.
41. DONE (round 24: undo/redo toast, Fix flashes the changed cards; feedback_test) ~~[STY] Animated micro-feedback: button press, apply-fix flash, undo toast.~~
42. DONE (round 24: joint dots and the part name red = his left, blue = his right; side_colours_test; bones not thickened) ~~[STY] Skeleton rendering: thicker bones, joint dots, and a left/right color convention (e.g. blue/red).~~
43. DONE (round 23: two ghosts a side, fading, orange->red / green->cyan; onion_fade_test) ~~[STY] Ghost/onion skins: fading alpha plus a hue shift for past and future.~~
44. DONE (round 23: time axis, hover line + readout; graph_read_test) ~~[STY] Speed graph: a proper axis, a gridline legend, and hover readout.~~
45. DONE (round 24: grid fades 1 m -> 2 m, XYZ gizmo with arrowheads and letters; floor_fade_test) ~~[STY] Ground grid with fade-out and an origin axis gizmo.~~
46. DONE (round 22: main._grey + NOT NOW reasons; greyed_why_test audits 7 states x 4 tabs) ~~[STY] Consistent disabled states (greyed out plus a tooltip that says why it is disabled).~~
47. [STY] Splash/empty state art: "Create a pose / open a scene / try an example".
48. [STY] Screenshot gallery test: render every panel and store it in shots/ for visual diffs.

## D. Functions (49–70)
49. DONE (round 10: Ctrl+drag a hand/foot swings the elbow/knee about the root-to-end line, end held <1 mm; panel 'elbow/knee' row; pole_test) ~~[FN] IK handles for hands and feet (drag the end effector; the chain solves). Include a pole vector.~~
50. DONE (round 10: a card's 'plant' holds a foot where it stood in the card before; registry toggles; plant_test) ~~[FN] Pin a foot or hand to the ground or world (fixes foot slide at the source).~~
51. DONE (round 10: 'Fix: plant this foot' on FOOT SLIDE: combo3 spline 4.5 cm -> 0.03 mm, no pose changed; plant_test) ~~[FN] Auto-fix foot slide option (currently no-fix): IK-lock the contact frames.~~
52. [FN] Curve editor per joint (bezier tangents), next to the speed graph.
53. DONE (round 10: ease dropdown smooth/linear/in/out/snap per card ('hold' = the card's hold time, already there); ease_test) ~~[FN] Easing presets per card: linear, ease in/out, snap, hold.~~
54. DONE (round 10: Ctrl+C / Ctrl+V / Ctrl+Shift+V mirrored / 'Paste to this part'; paste_test) ~~[FN] Copy/paste pose, paste mirrored, and paste to the selected parts only.~~
55. [FN] Pose library with thumbnails, plus drag a pose onto the timeline.
56. [FN] Clip blend/crossfade between two clips.
57. DONE (round 17: retime_test: Shift+click a range, Faster / Slower on it, retime=A-B:pct) ~~[FN] Retime tool: stretch a range of cards by a percentage.~~
58. DONE (round 16: loop_test: LOOP SEAM pose + speed, a Loop box, Loop: close the seam) ~~[FN] Loop check: the first and last pose match, with a velocity continuity warning.~~
59. [FN] Weapon/prop attach to a hand with an offset, kept through mirror.
60. [FN] Export: JSON plus a sprite sheet and GIF preview straight from the app.
61. [FN] Import reference video frames as a background plate (connect to the see-video skill output).
62. [FN] Overlay a tracked skeleton from video, and snap cards to it.
63. DONE (round 16: balance_test: de Leva COM, the feet's floor shadow, BALANCE in CHECK, measure com / balance) ~~[FN] Physics sanity checks: center of mass over the support polygon, and a balance warning.~~
64. [FN] Joint limits per part (anatomical ranges), with a soft warn and a hard clamp option.
65. DONE (round 22: Symmetry toggle, only the changed joints mirror; symmetry_test) ~~[FN] Symmetry mode: edit the left and the right updates live.~~
66. [FN] Multi-select parts and rotate them as a group.
67. [FN] Selection sets ("whole arm", "upper body").
68. DONE (round 16: autosave_test: every 15 s, atomic, Recover / Discard on start) ~~[FN] Autosave plus crash recovery.~~
69. [FN] Version history/snapshots per scene (Fusion-like "versions").
70. DONE (round 18: poser_cli check_all --html; check_all_test) ~~[FN] Batch run of all CHECK rules over every scene with one HTML report.~~

## E. User-friendly check (71–85)
71. DONE (round 12: 5 steps that move on when you DO them, Skip, shown until done once; tour_test) ~~[UX] First-run tour (5 steps: select, rotate, add card, play, check).~~
72. DONE (round 11: 75 commands all described, all 37 shortcuts listed (the weapon keys were missing); search_forgive_test) ~~[UX] Every command in search has a one-line description and shows its shortcut.~~
73. DONE (round 11: one SYNONYMS table + one-letter typos; search_forgive_test) ~~[UX] Fuzzy search with synonyms ("keyframe" → card, "flip" → mirror).~~
74. DONE (round 11: the last 5 run head the empty search, marked 'recent'; search_forgive_test) ~~[UX] Recent commands at the top of search.~~
75. DONE (round 11: top-bar History: named steps, click = go there exactly; history_test) ~~[UX] Undo history panel (list of named steps, click to jump).~~
76. DONE (round 11: one dialog for file deletes/overwrites, an audit of every file-writing function; edits never ask; confirm_test) ~~[UX] Confirm only destructive actions (delete clip/scene). Everything else is undoable, without a prompt.~~
77. DONE (round 12: every refusal names the next step, 12 rewritten; say_next_test scans them all) ~~[UX] Error messages say what to do next, not just what failed.~~
78. DONE (round 12: a plain 'why' line under each finding + a source button to the research; why_test) ~~[UX] Rule warnings explain the "why" plus a link to the research note (Campbell ISBS etc.).~~
79. DONE (round 10: hovering a Fix shows a blue ghost of the result, worked out off the main thread, the scene untouched; fix_preview_test) ~~[UX] Fix button preview: show the before and after ghost before applying.~~
80. DONE (round 12: Example: walk / swing / dodge on the empty state, opened as a copy; examples_test) ~~[UX] Example scenes bundled (walk, swing, block) and opened from the empty state.~~
81. PARTIAL (round 15: clicks_test measures 10 tasks in the real window, docs/CLICKS.md; 21 -> 16 on the 9 possible before (24%), card naming added; short of 30%, why per task) ~~[UX] Clicks-to-task audit: count clicks for 10 common tasks and cut each by at least 30%.~~
82. [UX] A non-animator test script: a novice completes "make a punch clip" in under 5 minutes. Record the steps.
83. DONE (round 14: F6 = the panels by keyboard; Tab walks 198 stops with no trap, Enter/Space press, Esc back; focus ring measured 11.5:1 dark / 4.6:1 light; keyboard_test) ~~[UX] Accessibility: keyboard-only operation of all panels and visible focus rings.~~
84. DONE (round 11: VIEW > UI size 90/100/125/150, offered when the window leaves 1280x720 (150 needs 1920x1080); ui_scale_test) ~~[UX] UI scale setting (90–150%).~~
85. DONE (round 11: all 30 ribbon/top-bar buttons put their hint in the status bar on hover; hover_hint_test) ~~[UX] Hints in the status bar that update with the hovered tool.~~

## F. AI easy-use check (86–100)
86. DONE (round 8: main._commands(): id, desc, edits) ~~[AI] A command registry as the single source of truth: id, args, description, undoable. The UI, search and CLI all read it.~~
87. DONE (round 8: tools/poser_cli.gd) ~~[AI] Headless CLI: `poser run <command> --args` for every registry command.~~
88. DONE (round 13: poser_cli serve, JSON-RPC 2.0 on stdin, one live session, 12 methods; serve_test drives a real subprocess) ~~[AI] JSON-RPC/stdin mode so an agent can drive a live session.~~
89. DONE (round 8: poser_cli describe) ~~[AI] `poser describe`: dump the scene as compact text (parts, angles, cards, warnings).~~
90. DONE (round 8: --shot already existed; in README_AI) ~~[AI] `poser shot --tab X --view Y`: a deterministic screenshot for agent visual checks (extend the existing flags).~~
91. DONE (round 13: docs/scene.schema.json + tools/validate.gd, agreeing with python jsonschema on 39 files; schema_test) ~~[AI] A stable, documented scene schema (JSON Schema file) with a validator.~~
92. DONE (round 8: run steps report ok/changed/undo_steps) ~~[AI] Every command returns structured results (ok, changed ids, warnings), never just prints.~~
93. DONE (round 13: pose="raise the right arm 90, bend the left elbow 45", also in the S search; reports reached vs asked; pose_words_test) ~~[AI] A natural-language pose macro layer: "raise right arm 90, bend elbow 45" maps to commands.~~
94. DONE (round 8: poser_cli check --json) ~~[AI] A `poser check --json` report that agents can gate on.~~
95. DONE (round 13: poser_cli diff, cards matched by name, joints > 0.5 deg largest first; diff_test) ~~[AI] A diff tool: `poser diff a.json b.json`, per-joint angle deltas.~~
96. DONE (round 8: README_AI.md) ~~[AI] AGENTS.md / README_AI.md: how to launch, test, screenshot and edit, in one page.~~
97. DONE (round 8: tools/run_all.sh) ~~[AI] The test runner prints one summary line per suite plus a final PASS/FAIL count (machine-parseable).~~
98. DONE (round 14: shots byte-identical run to run, --frame N --fps F, serve state at a moment identical across processes and question order; determinism_test) ~~[AI] Deterministic seeds and frame stepping for reproducible renders.~~
99. DONE (round 14: all ~200 controls named from what they say (scripts/names.gd), found by address like card_2/b_update; names_test) ~~[AI] Name every node and widget so tests and agents can find them by path, not by coordinates.~~
100. DONE (round 13: tests/agent_e2e.py builds a named 30-card bat fight via serve only, 0 MUST FIX, valid, 53 s; it found 3 real bugs (no card names, 8 s card adds, the tour on shots)) ~~[AI] An end-to-end agent test: from an empty scene, a script builds a 30-card combat clip via the CLI only, then passes CHECK.~~

## Found while cooking (not in the 100)
- [BUG] The scene dropdown shows another scene's name when a scene is opened with `--scene` (seen in round 8's README shot).
- [BUG] Save scene during Stepped preview wrote the stepped playback's bad_frames: FIXED round 8.

## Suggested order
Round 8: 1, 2, 14, 86, 87, 92, 97, 99 (foundation: undo safety plus the registry/CLI make the rest cheap)
Round 9: 16, 17, 18, 27, 36, 37, 38 (the Fusion look)
Round 10: 49, 50, 51, 53, 54, 79 (animator power)
Round 11: 71–85 sweep, then 100 as the final exam.
- (round 9) Delete scene trashed the DROPDOWN's pick, which did not follow the open scene: it could trash a scene you were not looking at. The dropdown now follows the open scene, and Delete refuses when the two differ.
- (round 9) The right panel read METAL BAT for every weapon. Fixed, and the panel's instructions and slider names now say the weapon held (scene_list_test checks all three; it failed 3 of 3 on the old text).
- (round 9) Test suites read the user's saved theme at boot and wrote it when toggling; run in parallel they raced (a layout test booted light). Under a test script the poser now boots dark and saves to a per-process file.
- (round 9) The light theme's fields made each card 4 px taller and overflowed the bottom panel; empty_state_test now checks the light layout too.

## Beyond the 100 (Nick 2026-10-15: "go deeper ... until we are cinematic level, w monkey brain needed to operate")
Three directions, each worked as a GATES section with tests, like rounds 8-9:
- CINEMATIC: shots, not just poses: camera keys and lenses, depth of field, lighting presets, motion blur in renders,
  secondary motion (cloth/hair proxies), contact shadows, a render-to-video path. Judged by LOOKING at frames.
- MONKEY BRAIN: nothing to remember. One obvious next step on screen at all times, drag-to-do over menus, undo
  everything, no dead ends. Judged by a cold-start test: a script with no knowledge of the UI reaches a goal.
- AI EASY: (a) an MCP server over the command registry (poser_cli verbs as tools: describe, run, check, shot);
  (b) a local API (the same verbs over HTTP/JSON); (c) for BLIND agents (no images): the maths in words and numbers,
  i.e. every joint's frame, limits, the reach of each hand, collision distances and "what would this angle do",
  so a text-only model can pose and verify without a screenshot.
