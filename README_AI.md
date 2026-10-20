# Kine by Teschima Studios (formerly Poser) for agents: one page

The poser is a Godot 4.7.2 app (`main.tscn`, logic in `scripts/main.gd`) for posing a mannequin and animating it card by card.
Nick's files: `scenes/*.json`, `poses/`, `data/`. **Never write them.** Put experiments in `scenes/_wip/`.

```sh
G=/c/Users/Nick/Tools/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe   # the _console exe prints to stdout
cd C:/Users/Nick/Desktop/poser
```

## Drive it without a window: `tools/poser_cli.gd`
It builds the real poser headless, so every command runs the same code as its button, key or search entry.
The **last output line is JSON** with `"ok"`. Add `--json` to get only that line.

| verb | what it does |
|---|---|
| `$G --headless --path . -s tools/poser_cli.gd -- commands` | the registry: every command's `id`, `keys`, `edits`, `desc` |
| `... -- describe scenes/combo3.json` | cards (name, arrive/move/hold seconds, weapon), settings, finding counts, joint names |
| `... -- check scenes/combo3.json --json` | the rulebook's findings: `n, sev (MUST FIX/look), rule, t, card, card_name, msg, fix` |
| `... -- run <scene> <step> ... [--out scenes/_wip/x.json]` | edit, then write only if `--out` is given |

Steps for `run`, in order (it stops at the first that fails and says why):
`<id>` from `commands` (e.g. `mirror_the_whole_pose`, `faster_10`, `weapon_bo_staff`) ·
`card=N` (1 = first) · `sel=<joint>` · `set=<joint>:bend,side,twist` (degrees, clamped to limits) ·
`update` · `add` · `delete` · `fix=K` (Check, then the K-th finding's Fix) · `undo` · `redo`.
Each step reports `body_changed`, `cards_changed`, `undo_steps` and what the poser said.

```sh
$G --headless --path . -s tools/poser_cli.gd -- run scenes/combo3.json card=3 sel=lowerarm_r set=lowerarm_r:90,0,0 update --out scenes/_wip/try.json
$G --headless --path . -s tools/poser_cli.gd -- check scenes/_wip/try.json --json
```
Refused, with nothing written: `--out` into `scenes/` (outside `_wip`), `poses/` or `data/`; `save_scene` and `save_pose`; unknown steps.

## Test
`sh tools/run_all.sh` runs every suite and prints one line each, then `SUITES n/n PASS`. The exit code is the number of failures.
`sh tools/run_all.sh cli ring` runs only those suites. Logs go to `$TMP/poser_suites/<name>.log`.
A suite fails on a non-zero exit, on a `FAIL` line, or on any `SCRIPT ERROR`. A hung suite is stopped (5 s after a script error, or 400 s total).
Window suites open a real window, so that's normal.
Before claiming anything works: run the suites you touched, then all of them, and check that `git status scenes/ poses/ data/` is clean.
Under a test script the poser boots in the dark theme and saves its settings to its own `user://poser_test_<pid>.cfg`, never the user's `user://poser.cfg`. Suites run in parallel, so no test may depend on the user's saved theme.

## See it
```sh
$G --path . -- --scene res://scenes/combo3.json --t 3.1 --view 2 --shot C:/Temp/shot.png   # one frame, then quit
$G --path . -- --scene res://scenes/combo3.json --record C:/Temp/frames --fps 30           # every frame, then quit
```
Other flags (they're useful with `--shot`): `--trail --onion --spacing --graph --stepped --check --caps --clean`,
`--pin foot_l,head`, `--yaw/--pitch/--dist`, `--sel <part>`, `--ribbon ANIMATE`, `--cmd <typed text>`, `--ring <part>`, `--tab 1`.
`--light` / `--dark` pick the theme for that run (they override the saved setting). Shoot UI changes in BOTH themes.
The status bar's text is `main.bar_text()`: the same words the user reads (part and angles, card, playhead, Check count).
Colours come from `scripts/tok.gd` (`Tok.c("heading")`). A new `Color(` literal in UI code fails `theme_test` unless it is listed there with a reason.
Look at the PNG with the Read tool. A screenshot you haven't looked at is not evidence.

## Round 10: animator functions (all registry commands, so `poser_cli` / command search reach them)
- Pose clipboard: `Body.pose_copy()`, `pose_paste(p, mirrored, only)`; main `_copy_pose`, `_paste_pose(how)`.
- Ease per card: `card["ease"]` in `Scene.EASES` (smooth, linear, in, out, snap); saved only when not smooth.
- Planted feet: `card["plant"] = ["_l"/"_r"]`; `Scene._planted` holds the foot where it stood in the card before the run, no pose changed. The FOOT SLIDE finding carries `foot` and `t1`; `Fixer._plant` is its Fix.
- IK pole: `Body.swing_pole(tip, deg)` returns the angle actually swung (a contact or limit can stop it short; it says so).
- Fix preview: `Fixer.propose(f, S, B)` returns the cards a fix would write and leaves the scene untouched; `Scene.clone()`; main runs it on a worker thread; `Overlays.fix_preview` is the blue ghost. Shots: `--spline`, `--hover-fix n`.

## Round 11: friendliness
- Command search (`scripts/command_search.gd`): `SYNONYMS` (add a row, every search knows it), `typo1()`, `recent`, and a `running(name)` signal sent just before a command runs.
- Undo steps carry names: the first `_say` after the push, else `_step_hint` (the button text, search command or shortcut). The History panel (`_history_rows`, `_history_go(n)`) moves one undo/redo step at a time.
- `_confirm(msg, ok, f)` is the only dialog. It is for file deletes and overwrites only. `tests/confirm_test.gd` reads `main.gd` and fails on any file-writing function without a policy, so a new writer must be added there.
- `_hover_hint`: `bar_text()` returns it first.
- UI size: `SCALES`, `MIN_ROOM` (1280x720), `scale_fits()`, `_fit_rows()` (the play row's extra buttons hide when the row is short of room). CLI flags: `--scale N`, `--history`.

## Rules of the house
- **REAL HUMANS FIRST (Nick, 2026-10-17).** Every pose, grip or interaction (carry, sit, step, lift, jump, later the face)
  is compared with REAL people before it is shown or ticked: find a reference (a biomechanics paper, an ergonomics
  standard such as NIOSH or Snook, motion-capture data, photos), write its numbers down (angles, heights, distances),
  measure the same numbers on our body, and put both in the gate and the test. "The prop moved with the hand" is not
  a pass: round 39's first screenshot held a box on straight arms at shoulder height, which no human does.
- `GATES.md` is the ledger: a box gets ticked only with evidence (test name, numbers, what failed first).
- `UPGRADES_100.md` is the backlog. Each round takes items from it.
- Every edit is ONE undo step (`tests/undo_audit_test.gd` enforces this for each command, `tests/undo_fuzz_test.gd` for chains of commands).
  A new command goes in `main._commands()` with `id`, `desc` and `edits`. If it edits, wrap it in `_do(...)` or call `_push_undo()` first.
- Undo snapshots use `Body.state()` (lossless). `to_dict()` rounds for files: never use it to put the live body back.

## Round 12 (GATES.md section S): say why, say what next, show how
- **Why + source** (`scripts/rulebook.gd` `WHY`, `URL`): one plain sentence and one link per rule. The CHECK panel shows
  a `why:` line and a `source` button under each finding (main `_open_source`, which stores `last_source`). Web links
  must be docs/MOTION_RULES.md's own (`tests/why_test.gd`).
- **What next**: every `_say` right before a `return` in main.gd names a step the user can take
  (`tests/say_next_test.gd`, headless; successes are listed in its `DONE` table). A new refusal must say what to do.
- **Examples** (main `EXAMPLES`, `_open_example`): walk_bat / swing_fore / dodge_side open from the empty state as a COPY
  (`scene_path = ""`, name `<x>_mine`). The example files are never written (`tests/examples_test.gd`).
- **Tour** (`TOUR`, `_tour_start/_tour_go/_tour_poll/_tour_end/_tour_due`, settings `look/tour_done`): 5 steps, each
  watched every frame and advanced by doing it; registry "First steps tour"; CLI `--tour` (`tests/tour_test.gd`).

## Round 13 (GATES.md section T): a scene an agent can trust
- **Schema**: `docs/scene.schema.json` (JSON Schema 2020-12) describes a scene file (`cards`) or a pose file (`joints`)
  exactly as the loaders read them. Unknown keys are errors, since the loader would silently ignore a typo.
  `poser_cli validate <file>` (tools/validate.gd reads the schema). tests/schema_test.gd holds its enums equal to
  Body.ORDER / Body.KINDS / Scene.EASES and checks against python jsonschema.
- **Diff**: `poser_cli diff a.json b.json`: settings, cards added / removed / renamed (matched by name), timing, and
  per joint bend/side/twist over 0.5 deg, largest first (tools/scene_diff.gd).
- **Words to a pose**: step `pose="raise the right arm 90, bend the left elbow 45"` (scripts/pose_words.gd; also the S
  search). A number turns BY that much; `to N` sets the raw angle. The answer says what each joint REACHED, and a
  limit or contact is reported as "stopped short", never hidden. `name=<text>` names the picked card.
- **Live session**: `$G --headless --path . -s tools/poser_cli.gd -- serve`. JSON-RPC 2.0, one request per line, one
  live scene (methods and errors at the head of tools/poser_cli.gd). Start with `new` or `open`; build with
  `run {"steps": [...]}`; read with `state` (every joint's angles, in degrees, plus positions: what a blind agent
  needs), `describe`, `check`, `diff {path}`; write with `save {"out": "scenes/_wip/x.json"}`.
- **The proof**: tests/agent_e2e.py builds a named 30-card bat fight from empty through serve only, CHECK -> fix ->
  CHECK to 0 MUST FIX, saves and validates (about 50 s). `--keep` leaves scenes/_wip/agent_fight.json to look at.
  0 MUST FIX means no real human limit is broken. It is a floor, not a quality bar: the agent's swing is stiff.
- **Speed** (found by the agent test): Scene.times() is memoized (frames byte-identical) and IK stops at 0.01 mm
  (Body.IK_EPS). A 30-card card add went from 8.6 s to 1.4 s and check from 20.9 s to 2.5 s.

## Round 14 (GATES.md section U): find it, trust it twice
- **Every widget has a name** (scripts/names.gd): made from what it says, with a kind prefix: `b_trail`, `b_mirror_pose`,
  `spin_hold`, `slider_swing`, `opt_scene`. Repeated rows are scopes: `card_3/b_update`, `card_3/spin_move`,
  `check_panel/finding_2`, `check_panel/fix_2`, `history_panel/step_4`, `fingers_r/b_fist`, `tab_check` (the tab)
  vs `ribbon_check/b_check` (its button). Find with `find_child(part, true, false)` per part. tests/names_test.gd
  holds all ~200 to this rule.
- **The same frame twice**: shots are byte-identical run to run. `--frame N --fps F` lands exactly on t = N / F.
  serve `state {"t": 1.25}` or `state {"frame": 37, "fps": 30}` gives that moment. The answer does not depend on what
  was asked before, and it includes `points` (17 parts' positions, m: y up, +z his front) and the weapon's knob and tip.
- **The dummy measures off the main thread**: after an edit the dummy text says "measuring..." for about 1-3 s on a big
  scene. `state {t}` and `--shot` wait for it, so what they show is what plays.
- **Keyboard only**: F6 enters the panels (Tab / Shift+Tab, Enter / Space, Esc back to the view). An agent driving
  the real window with keys can use it. The focus owner's address is what has focus.

## Round 15 (GATES.md section V): MCP, and the maths for a blind agent
- **MCP server**: `python tools/mcp/poser_mcp.py` (standard library only; set POSER_GODOT or pass `--godot`). It offers
  12 tools, one per serve method. Claude Code: `claude mcp add poser -- python <path>/tools/mcp/poser_mcp.py`.
- **measure** (serve and MCP): `{"t": 3.0, "what": ["distance hand_r head", "angle upperarm_r lowerarm_r hand_r",
  "height head", "speed weapon_tip", "clearance"]}`, each answer with its unit. The frames, conventions and formulas,
  plus every joint's limits and what + means, are in **docs/AGENT_MATH.md** (generated from data/body_limits.json).
- **Fewer clicks** (docs/CLICKS.md, measured by tests/clicks_test.gd): picking a scene in the list opens it (it asks
  first over unsaved changes); double-click a card's title to rename it; B puts the bat in the right hand from either
  hand; Enter in the scene-name box or Ctrl+Shift+S saves the scene.

## Round 16 (GATES.md section W): never lose work, and a motion that reads right
- **Autosave**: an unsaved scene is written every 15 s to user://autosave.json (never scenes/); the next start offers
  Recover / Discard. Tests use their own file (POSER_AUTOSAVE, or one per process).
- **Loops**: tick "Loop" in the scene bar (by Save scene), or set `"loop": true` in the scene; CHECK's LOOP SEAM grades the last
  frame against the first (pose and speed). "Loop: close the seam" (S search) copies the first card onto the last.
- **Balance**: `measure` "com" and "balance" (docs/AGENT_MATH.md); CHECK's BALANCE warns when, with both feet down, the
  centre of mass is past the feet by 3 cm for 0.1 s or more.

## Round 17 (GATES.md section X): timing by the handful, every key on one screen, names that survive the disk
- **Retime a range**: click a card, Shift+click another: Faster / Slower retime every card between. Agents: the step
  `retime=A-B:pct` (e.g. `retime=3-6:150`, cards 3 to 6 at 150 %, slower).
- **?** shows every key the poser has, made from the command registry.
- **Names**: a scene keeps its name as typed (any script, emoji); its file name is made safe (`safe_file`), and
  nothing can save outside scenes/ (only a leading `_wip/` picks a folder).

## Round 18 (GATES.md section Y): one report for every scene, the edges of the timeline
- **Check every scene**: `poser_cli check_all [folder] --html C:/Temp/check.html` runs Check over every scene in the
  folder (scenes/ by default): one HTML report (rule totals, then each scene's findings) and one JSON line.
- **The --out guard** now simplifies the path first: `scenes/_wip/../x.json` is refused (before, it wrote scenes/).
- **Spline scenes**: the first frame is the first card even when that card has no hold (the overlap's lead now ramps
  in from t = 0; scenes whose first hold is 75 ms or more play byte-identically).

## Round 19 (GATES.md section Z): what mirror must swap, nothing left behind
- **Mirror's list**: `Scene.MIRROR_SCENE` / `Scene.MIRROR_CARD` name every key a scene file holds and whether it has a
  side. Mirror the scene now swaps a card's planted foot, recomputes bad_frames from the mirrored motion, and writes a
  safe file name. A new key must be added to the list (tests/mirror_list_test.gd fails otherwise).
- **Pop-ups**: opened and closed 200 times each, none leaks (tests/popup_leak_test.gd).
- **Spacing ghosts** go away when the scene has fewer than two cards (they used to keep the old scene's).

## Round 20 (GATES.md section AA): the lists keep their place
- **Search** lists each of its 84 commands once, through tab switches, theme, scale and scene changes.
- **Browser**: it scrolls to the picked row only when that row is out of sight, and a theme switch recolours it in
  place (the folds and scroll stay).
- **New empty scene** is one function (`_new_scene`) for its button and its search entry; it hides the speed graph.

## Round 21 (GATES.md section BB): small windows, the ring at the edges, flips on mirrors
- **The top bar on a small window** (`main._fit_top`): if it does not fit, the labels drop their "(key)" (the key stays
  in the tooltip), then the tab's last tools go into a **More** menu. The window cannot be made smaller than 1280 x 720.
- **The right-click ring** stays whole and below the top bar at every corner of the view, at 100, 125 and 150 %.
- **`tests/flip_survey.gd`** covers every scene in scenes/, _wip and _archive, and each one's mirror; it fails on a flip.

## Round 22 (GATES.md section CC): symmetry, 3/4 views, greyed controls say why
- **Symmetry** (POSE tab, or the search "Symmetry on / off"): drag one side and its twin follows, reflected; only the
  joints you changed are copied, and one Ctrl+Z undoes both sides.
- **ViewCube**: click near an edge or a corner of a face for the view between the faces; the house mark goes home; cube
  moves ease over 0.3 s the short way round. Keys 1-5 stay instant.
- **A greyed control says why**: `main._grey(control, why)` puts "NOT NOW: why" in its tooltip.

## Round 23 (GATES.md section DD): onion skins that fade, a speed graph you can read, findings on the timeline
- **Onion** shows two cards each side; the farther ghost is fainter, past orange -> red, future green -> cyan.
- **Speed graph**: a time axis, and the mouse over it shows the three speeds at that time.
- **After Check**, each finding is a diamond in the timeline's ruler (red must fix, amber look); click one to jump there.
  An edit clears them until Check runs again (`main.findings_live()`).

## Round 24 (GATES.md section EE): a floor that fades, sides you can tell apart, feedback you can see
- **Floor grid** fades from 1 m to its 2 m edge; the origin has X (red, his left), Y (green, up), Z (blue, he faces).
- **Joint dots** red on his left, blue on his right (`main.side_col`); the selected part's name takes its side's colour.
- **Ctrl+Z / Ctrl+Y** show a toast naming the step; a **Fix** flashes only the cards it changed.
- `_fix` refuses a finding with no automatic fix (it used to crash in Fixer.apply and wedge every later Fix).

## Round 25 (GATES.md section FF): one weapon picker, fewer clicks, one type scale
- **Weapon**: one dropdown per panel (`opt_weapon` in Poses, `opt_weapon_panel` on the right), synced in `_refresh`.
- **Clicks** (docs/CLICKS.md, generated): 21 -> 14 on the 9 tasks. A drag on a part picks it; each Fix sits under its finding.
- **Properties panel**: two sizes (`PROP_BIG` 22, `PROP_TXT` 15), value rows built by `_prop_row` (name dim, value
  bright, hint under). Sliders are named by axis: `slider_bend/side/twist`, `slider_hip_0..2`.

## Round 26 (GATES.md section GG): three ways in, hover, part locks
- **Empty scene**: the strip offers `start_clip` (Clip this pose), `start_open` (the scene list) and the examples.
- **Hover**: button-less motion over the view sets `hover_part` (drawn `HOVER`, named on the bar as "pointing at");
  a press, a drag or a panel under the mouse clears it. It shows what a click there would pick (`_pick`).
- **Locks**: `locked_parts` (view state, never saved). `_do` and every joint-drag motion put locked angles back
  (`_lock_snap`/`_lock_keep`), so Reset, Mirror, Snap and a hand's IK reach all respect it. Lock from the ring (7th
  wedge), the panel (`btn_lock_part`) or the search. Not done from #24: browser eye icons, limb folders.

## Round 27 (GATES.md section HH): type the angle, a navigation block
- **Typed angles**: during a joint drag, `_num_key` (in `_input`, ahead of the GUI's Tab) takes digits - . Backspace
  Tab Enter Esc; `_num_apply` sets the axis through `set_ang_safe` (the limit OR the body stops it). Esc = `_num_start`
  back and the drag's undo step popped. `_num_text` resets at every press.
- **Nav block** (`ui_nav`, `nav_*`): a 2 x 3 grid under the ViewCube (NOT the bottom centre: it covered the feet).
  `nav_tool` "orbit"/"pan" turns a left press into that drag; Esc off. `_nav_fit` projects `fit_points()` and corrects
  distance and pivot into `nav_clear_rect()` over 4 passes. `grid_node` is the floor grid's MeshInstance3D.

## Round 28 (GATES.md section II): several parts at once, selection sets
- **Group** = `group()` = `[sel] + sel_more`. `sel` stays the shown / dragged part everywhere; `_group_sel` ties the
  group to it, and `_refresh` drops `sel_more` once anything else moves `sel`. Ctrl+click (no motion, judged on the
  release in `_group_release`, its undo step popped) adds / removes; `_group_follow` gives every member the change of
  `sel`'s angles through `set_ang_safe` (a hinge or the body can stop a member short: by design).
- **Sets**: `SEL_SETS` + `_select_set`, as "Select: ..." search commands. No "both arms" (opposite sides turn opposite).

## Round 29 (GATES.md section JJ): scene versions, the grip through a mirror
- **Versions** = `ui_versions` (a MenuButton in the scene row) + the search's "Save a version". `_save_version` writes
  `scenes/_versions/<safe_file(name)>/vNNN.json` (next number; never the scene's own file). `_open_version` puts the
  version's CARDS in as one `_do` step (not Natural / Spline / Loop: an undo step holds only the cards); the scene is
  then unsaved. `_lists()` reads `scenes/` without recursion, so versions never show as scenes.
- **A new file-writing command must be listed in THREE tests**: `confirm_test` (the policy table), `undo_audit_test`
  (SKIP) and `command_search_test` (writers). Each runs or audits every command; missing one left real versions of
  combo3 and an unnamed scene on disk in the first full run.
- **Grip through Mirror (#59)**: already right in `body.mirror_pose` (the hand offset x and the turn reflected);
  `grip_mirror_test` proves it, twice = back, save/load (the load path is `scene.gd` applying a card). Paste mirrored
  keeps the weapon in its hand (round 10 Q1); whether it should cross hands is Nick's call.

## Round 30 (GATES.md section KK): the Browser's eye and lock, hover in sync
- **Pieces**: `Overlays.split_parts` splits the hero's single skinned mesh at load into one MeshInstance per part
  (`main.pieces`; each triangle to the part whose bones weigh most; all vertex data kept, same skin/skeleton/material;
  the original hidden, not freed). The dummy is NOT split. Renders the same but for ~7 outline pixels in 125k.
- **Hide** = `hidden_parts` (view state, like `locked_parts`): `_refresh` hides the piece, capsule and dot; `_pick`
  skips it. `_set_hidden` / `_set_locked` take a list (a folder's buttons). Never in a pose or scene file.
- **Browser buttons**: eye (id 0) and lock (id 1) on part rows and limb / finger folders (`folders`), 16 px
  `Icons.small`. The press is handled in the Browser's `gui_input` (`_motion`) from the EVENT's position and
  accepted: Tree's own `button_clicked` re-checks the OS mouse and drops pushed clicks. `_show_state` re-sets a
  button only when its state changed (re-setting mid-click lost clicks).
- **Hover sync**: `follow()` lights `rows[hover_part]` (btn_hover bg); a row's motion sets `m.hover_part`;
  `_left` (mouse_exited) clears it, needed for a move straight onto the right panel, which main's `_process`
  clean-up does not see; `_process` skips the Browser as the hovered control.
- Test note: a cleared TreeItem bg colour reads back as `Color()` (opaque black), not transparent.

## Round 31 (GATES.md section LL): export to the game (UPGRADES_200 #101-105)
- **Target**: the ARPG (D:/arpg, Unity 6) has no Animator and no clips. Moves are `PoseTable` data in C#
  (`unity/Assets/Scripts/View/PoseTable.cs`): per slot (`LimbRig.Bone`, 13; 11 on a human), keys `(t 0..1, pitch,
  yaw, roll)` in degrees from the GAME's rest, character frame, composed pitch*yaw*roll*rest, smoothstep per segment.
- **`scripts/game_export.gd` (`GameExport`)**: `slot_angles(B)` = the fold. A slot's angles are its world delta
  relative to its parent slot's, `D = Dp^-1 * Dg`, with `Dg = B.G[end joint]` (so spine_01..03, clavicle and neck
  fold in; hands, feet, fingers and the weapon do not reach the game). Arms only: `Dg = G * C`, C = the turn from
  straight down (the game's rest) to Poser's T-pose rest direction. Axes: right = -x, up = +y, forward = +z;
  `SIGN` flips an axis if the in-game capture (UPGRADES_200 #105, OPEN) says so.
- **`table(S, B, refine, tol)`**: 60 fps frames (Euler unwrapped), keys at the start, end and every card's arrive and
  leave, then the worst frame added per slot until the game's sampler is within 1° everywhere. `to_json`,
  `from_json`, `to_csharp` (paste into `Skills`), `write(S, B, dir)`.
- **Command** "Export to game" (`main._export_game`): exports/<scene>.json + .cs; keeps the body's pose
  (`B.state()`); listed in confirm / undo_audit / command_search as a file writer.
- **Known**: 188-817 keys per scene at 1°. Foot planting makes legs jump up to 39° in one frame (UPGRADES_200 #132),
  which the export copies; that is round 32.

## Round 32 (GATES.md section MM): the weapon goes with a paste; no leg snaps at card edges
- **Paste carries the weapon** (Nick 2026-10-16, overriding round 10's Q1): `Body.pose_copy` keeps `"wep"` (hand,
  grip in it, free place); `pose_paste` applies it when the body has a weapon on and the paste is whole; mirrored =
  the other hand, grip mirrored as `mirror_pose`. A part paste or a weaponless copy leaves the weapon alone.
- **Planting** (`Scene._apply`, pin on): `_anchors(B)` gives each foot per card [ball, heading, flat, how] with how
  pin / step / free; a pin carries the place from the card before. A HOLD (`_held(t)`) plants as its move ended. A
  move into card i cross-fades each leg from the old rule's solution (as the hold before was planted, or, after a free
  hold into a pin, the foot on its mark with the raw knee's direction) to the new rule's, over the leg's ease e; if
  that leaves the ball >5 mm off, it re-plants keeping the blended knee (`Body.knee_heading`, `plant(..., knee)`).
- Why: holds used the cards' raw legs and moves the planted ones, so legs jumped up to 42° in one frame at every
  move <-> hold edge, and the two knee rules (flat: foot heading; heel up: hips facing) switched at move starts.
- `tests/plant_edges_test.gd` measures a POP (a frame turning more than both neighbours, planting on beyond off) at
  card edges, and pinned-ball drift; steps' own speed inside moves is printed, not barred.
- **Consequence for the Fixer** (found by the first MM3 run, fix_test 3 FAIL): a pinned foot now carries forward, so
  a pose edit on card c moves frames after its window. `Fixer.window(S, c, B)` follows each foot: it stays LIVE while
  cards pin it, and the card after it is in the window too (a step leaves from the pinned place; a free leg blends out
  of it). combo3 card 10: window 2.95-3.49 -> 2.95-4.69 s, windowed == full on all 282 frames.
- `tests/plant_test.gd`: its fixture slide (combo3 in spline, 4.9 cm) is gone with pinning on (recorded as a check);
  the card "plant" Fix is tested with `S.pin = false`, where the slide is real.

## Round 33 (GATES.md section NN): dual wield
- Nick 10-16: "weapons like double dagger, so mirrored would help in making the scenes easier, like for combos".
- `Body.KINDS["dagger"]`: 0.30 m, one hand. `set_weapon_len` now floors at 0.2 m (was 0.4).
- THE OFF-HAND WEAPON (`wep2_*`): always held, locked in `wep2_hand` (pos = P[h] + G[h] * wep2_lpos, rot = G[h] *
  wep2_lrot); `wep2_to_hand(h)` = the grip file mirrored to h. Its capsules `Body.WEAPON2` = wep2_handle, wep2_blade:
  in the contact pairs, the wide-part and skin tests, skipped when off, never in the allowances; weapon-on-weapon and
  weapon-on-hand pairs are not contacts. It is NOT pickable: it rides its hand (turn the hand to turn it).
- Cards: the pose's "weapon2" (`wep2_dict`); samplers carry it as `"weapon2"` beside `"weapon"` on every path
  (`Body.wep2_flat`, `Body.wep2_mix`: same hand -> lerp/slerp of its place in the hand, else the nearer card's;
  `B.put_wep2`). A scene without it plays bit for bit as before (300 frames hashed, identical).
- Mirror pose, paste mirrored and Mirror the scene send it to the other hand, grip mirrored: with a dagger in each
  hand the hands swap what they hold.
- main: picker rows "Dagger" and "Two daggers" (`_two_daggers`); picking one weapon puts the off-hand one away.
- `tests/dual_wield_test.gd` (dual_wield:w): 8 checks.
- NOT YET: the game export (`GameExport`) has no weapon slot for either hand; a dagger fitted grip file
  (data/grips/dagger.json) does not exist, so the bat's standard grip is used, mirrored for the off hand.
- Found by the full run: a picker row's TEXT WIDTH sets the side panel's width; "Two daggers (one in each hand)"
  covered the view's left edge (ring_edges). Keep picker rows no longer than "Long hammer   (1.1 m)".
- KNOWN FLAKE (pre-existing): popup_leak's objects count sometimes rises (3915 -> 3956) with nodes and orphans flat;
  1 in 9 on round 32, 2 in 9 on round 33. To be looked at on its own.
  2026-10-17 (after round 35): NOT REPRODUCED in 10 of 10 (8 runs on their own, counts identical every run:
  search 3811 -> 3807 -> 3807, keys/help/tools 4006 flat, ring 4020 flat; + both full runs). Cause NOT found, so
  NOT fixed: round 35a changed start-up timing (the tour waits for the recover offer), which may only have hidden
  it. If it fails again: log Performance.OBJECT_COUNT per cycle and diff ClassDB instance counts at b and c.

## Round 34: universal export (GATES OO; Nick 10-16: "universal files to use in all engines")
- `scripts/gltf_export.gd` GltfExport.write(S, B, path): .glb via Godot's GLTFDocument; the app mannequin, one clip
  named after the file, a key per frame (Body.gltf_local + gltf_pelvis_pos), weapons as root nodes "weapon"/"weapon2"
  (a put-away weapon is scaled to 0). Command "Export animation (.glb)" -> main._export_glb.
  - GOTCHAS: renaming a bone in a Skeleton3D before export DROPS it (65 in, 64 out): rename on the GLTFState node.
    The root node must not share the clip's name (importer renames the clip "<name>2"). In a test's _init the tree
    is not running: get_bone_global_pose and global_transform are stale/errors; build from local poses.
- `scripts/bvh_export.gd` BvhExport.text/write; tools/export_bvh.gd is its CLI. Weapons: 6-channel joints, OFFSET 0,
  under their hand (the grip slides/turns within a scene). Command "Export animation (.bvh)".
- Frame count everywhere: ceil(length * fps - 1e-6) + 1 (4.6 x 30 = 138.0000x in floats doubled a BVH frame).
- Body.fk_sub(j): while `fast` (playback) only j's subtree is recomputed; bit-identical (814-frame hash); playback
  18.8 -> 6.7 ms/frame. Outside playback fk() as before (edits may write ang directly).
- Blender check: tools/blender_expect.gd then `blender -b --factory-startup --python tools/blender_check.py`
  (Blender 4.5 at C:/Program Files/Blender Foundation). FBX needs simplify 0, bake over the scene range, end rounded up.
- docs/EXPORT.md: per-engine guide (UE5, Unity, Godot, Blender) + NOT TESTED list. tests: glb_export, bvh_export,
  engine_names.

## Round 36: Fusion-style layout (GATES RR; Nick 10-17: "still far from minimalist or organized as fusion 360")
- Rule of the round: nothing removed, only moved; long words go to tooltips. `label_of(b)` = meta "label" or text;
  `_icon_only(b, icon, sz)` keeps the label (tooltip leads with it); `_short(b, words)`; tests find buttons by
  `label_of`, never by `.text`.
- Inspector (RR2): `ui_insp` box at the top right, height `_insp_fit()` (content, capped); header = title (how-to in
  its tooltip), lock, x. One row per angle (`_row_slider`), one action row, folded `_section()`s (`ui_secs`,
  `_sec_open`). Right panel type sizes: PROP_BIG 15 (title) / PROP_TXT 13 only.
- Browser (RR3): the left panel is ONE tree (scripts/browser.gd): Scene, Poses (Library / Mine), Body, Weapon,
  Target dummy. Right-click a row -> `_row_menu` (PopupMenu `browser_menu`). `ui_poses` (hidden ItemList) is still
  the pose model; names via `pose_name_dialog`. RR6: Scene and the body's groups start folded (a pick unfolds its
  group); the box fits its rows (`content_h()`, `_browser_fit()`); tests that click deep rows call `open_all()`.
- Bottom (RR4): one strip (`play_row`): First / Prev / Play / Next / Last, track, time, speed, Loop, Natural, gear
  (`ui_gear` PanelContainer `play_options`: Smooth, tween, ease; a PopupPanel never got pushed clicks), Clips.
  Check / Polish / Fix live in the CHECK ribbon only. BOTTOM_H 256, BOTTOM_FOLDED 48, timeline RULER 12.
- Status line (RR4/RR5): messages left (13 px grey, amber when "STOPPED"; `_status_look`), readout `ui_bar` (12 px,
  no box) right-aligned against the camera bar `ui_nav` (6 icons) at the line's right end (`_place_nav`,
  `_line_fit`; LINE_H 32). Not bottom-centre: it covered the feet (nav_bar_test). `_cam` centres above the line.
- First start (RR5): WELCOME (yellow box above the line) only until the first pick or message (`_end_teach`,
  `_taught` -> settings look/taught). Part tag 16 px, hit tag 18.
- Measured: tests/view_share_test.gd 72.3 % (browser + inspector + strip shown, combo3, 1600 x 900); all open 49.5 %
  (ceiling 53.8, GATES RR6 amendment). layout_measure --m-taught skips the first-start strip.

## Round 35a: first start, quiet and roomy (GATES QQ; Nick 10-16: intros "keep blinking", "no option to close or skip", "not like fusion")
- tools/startup_record.gd: the first 6 s recorded (events per frame + a PNG every 100 ms; --tour, --no-autosave,
  --press recover|discard|esc, --sweep moves the mouse). Own settings/autosave files, never the user's.
- One intro at a time: `_tour_after_recover` starts the tour once the recover offer is answered. A tour step moves on
  only if `_tour_inputs` (presses: mouse, key, any `_button`) grew since the step began: never on a load or recovery.
  The card has an (x); Esc ends the tour.
- Status bar: the hover words go through `_bar_hover`, which takes `hover_part` after it RESTS (BAR_REST 0.15 s on a
  part, BAR_LEAVE 0.3 s off). The light on the body is still instant. Tests read the bar after BAR_LEAVE + 0.05 s.
- Recover dialog: ONLY the Discard button discards (`_recover_discard`, set by its pressed; canceled is handled
  deferred). Esc / the window's x = LATER: the file moves to `<autosave>_later.json`, offered on the next start
  (the main slot is dropped by a quit with nothing unsaved, and overwritten by the next autosave).
- Hints: `hints_on` (settings look/hints): off hides WELCOME on the say strip, ui_how, the Poses and Scene captions
  (`ui_hint_labels`; a label with meta hint_text is emptied, not hidden, so its row keeps its width). Messages still
  show. The strip's own (x) turns hints off; VIEW > Hints.
- Folding (QQ4): `fold` {left,right,bottom}, `_fold(which, on, save)`, saved under settings layout/fold_*. A user's
  first start: FOLD_DEFAULT (all folded); a test starts open (as for theme and scale). lw()/rw() = what the sides take
  now (RAIL_W folded, 0 in big view): every reader of LEFT_W/RIGHT_W for placement uses them (`_sides_apply`). Rails:
  `ui_rails`, open buttons "open_left"/"open_right"; fold buttons `ui_fold_btn`. The bottom folds only with clips:
  the header row (`ui_bh`) and the card row go, BOTTOM_FOLDED; "Clips" in the play row opens it.
- The say strip is as wide as its text (`_strip_fit`, anchor_right 0), up to the view's width.
- EXPORT ribbon tab: Export .glb, Export .bvh, To game, Save version (icons in scripts/icons.gd).
- tools/layout_measure.gd: the view's share of the window (4 px samples of what no chrome covers); flags are --m-*
  because main.gd reads --scene and --shot itself. 1600x900: startup 46.5 -> 73.1 %, combo3 open 31.5 -> 71.3 %.
- tests: tour (QQ2/QQ3 checks), hints (new), fold (new), autosave 11b/11c, hover / hover_sync wait for the rest.

## Round 35: a stranger can start it and knows why it stops (GATES PP)
- pose.bat finds Godot 4.7: POSER_GODOT, godot\ beside it, PATH (Godot_v4.7*win64.exe / godot.exe), godot.path beside
  it (one line; LOCAL, git-ignored: Nick's own holds his path). Not found: words + godotengine.org + the three ways, a
  pause. POSER_DRY=1 prints "LAUNCH ..." and starts nothing. pose.sh: the same for Linux / macOS. tests/launcher_test.
- Body.last_stop {kind limit|contact, ...}: set by set_ang_safe (locked axes ignored); clear it before an edit, read it
  after. main.stop_words(st) turns it into "STOPPED: ..." on the drag's status line. tests/drag_stop_test.gd.

## Round 37: the set, part 1, and a faster bench (GATES SS; UPGRADES_200 section I: #202, #213, #214)
- Bench: `LOGS=C:/Temp/x python tools/run_par.py -j 8 [names]` runs the suites of tools/run_all.sh line 11 in 8
  BELOW_NORMAL workers, then the SERIAL set (suites sharing moves/, trash/, exports, autosave, cli) one at a time.
  About 2.5x the serial runner; `sh tools/run_all.sh` still works. New suites go on line 11 (EXTRA).
- Props (scripts/props.gd, `class_name Props`, static): `KINDS` built-in kinds at real sizes (box, crate, table,
  chair, stool, bench, step, stairs, ramp, wall, door_frame, railing, bed); a prop = {"kind", "xf"}; file form
  `to_dict` {"kind", "pos", "yaw"}. `solids` (boxes), `supports` (tops), `snap_y(p, others)` (onto what it stands
  over), `depth`/`rests_on` for later contact work. Imported models: `register(kind, aabb, glb, factor)` into
  `EXTRA`; `has_kind`, `kind_of`, `catalogue()`.
- Scene: `S.props` (saved as "props" only when non-empty, so old scenes write byte-for-byte as before);
  `S.props_skipped` = kinds a file names that this library lacks (said on load). MIRROR_SCENE "props": x, yaw negated.
- App (main.gd, "THE SET"): SET ribbon tab (Add prop MenuButton, Import model, Turn left/right 15 deg, Delete prop);
  `sel_prop`; `_pick_prop` (ray vs oriented boxes) wins over the body only when nearer than `_pick` (`_pick_t`);
  `dragging = "prop"` moves on the plane at the press height then `snap_y`; a still mouse is a click, not a step.
  Undo snapshots carry "props"; `_doc_key()` (cards + props) is what "unsaved" compares. Browser "Set" folder.
- Import (scripts/importer.gd, preloaded as `Importer`): `inspect` -> rigged / object / refused with `why`;
  `accept` copies into the library (+ .licence.txt, never overwrites). main: `_on_drop` (window files_dropped) and
  `_import_ask` (native picker) -> `_import_file`. Library `user://library`; tests get `user://zz_lib_<pid>`
  (removed on exit). Rigged files are kept, not yet played (#209).
- docs/JOBS.md: six Blender-vs-Poser jobs scored (routes checked against Blender 4.5.3 installed here).

## Round 38: the set is solid (GATES TT; UPGRADES_200 #203, #204, #205; also #228-#237 added, section L the FACE)
- Rule of the round: a scene with NO props runs the old code paths (every new branch is `if not props.is_empty()`).
- Grounding (body.gd): `B.props` (Scene._ground and main's `_props_show` set it). `sole_low()` -> `_sole_low_set()` on
  the set: each sole point (foot P, ball E, ball P) is measured from `surface_at(pt, up)` = the floor or the LOWEST
  support top at which the point is not inside a prop (over a box: its top; under a table or a chair: the floor).
  `seat_lift()`: the part of the hips / thighs OVER a support (axis sampled every 2 cm) sinking under its top by less
  than SEAT_CATCH (15 cm) lifts the body onto it. `foot_state`'s "on" is measured from the surface under the foot, so
  pins hold on a step. balance.gd's footprint uses the same surface.
- Check (rulebook.gd): sample() adds "prop_hits", "seat_gap", "feet_on" ONLY when the scene has props.
  `prop_hits(props, B)`: parts (fingers aside, weapons when out) deeper than PROP_WARN 5 mm into a prop; feet use
  `sole_rad()` (capsules thinned to the sole line: the foot capsule reaches 6 cm under the floor at rest) and a 1 cm
  allowance (SOLE_SINK: the floor itself lets the soles dip 6.75 mm mid-move). Rules THROUGH A PROP (FAIL from 2 cm)
  and FLOATS (hips 2-15 cm over a seat, no foot down, 0.1 s). Rows in docs/MOTION_RULES.md; `part_words()` names parts.
- SET tab, USE group: Sit here (chair / stool / bench: faces away from the back, hips behind the seat's middle, thighs
  level, ground, hanging feet planted) and Step up (box / crate / step / stairs: the nearer foot IK-planted 12 cm in
  from the near edge of the lowest top; out of reach -> refused in words). Both through `_use_card()`, which says
  what still goes into a prop.
- Test drivers that talk to a Godot child (tests/py/determinism.py, measure_check.py) WAIT for it after "quit": a
  killed child skips main's `_exit_tree` and leaks user://poser_test_<pid>.cfg.
- Known, not fixed: the soles dip up to 6.75 mm into the floor mid-move (Scene._apply plants after grounding); every
  scene has it; fixing it changes every scene's numbers, so it is its own item.

## Round 39: carry, put down, gravity (GATES UU; UPGRADES_200 #206)
- Nick asked "do we have gravity?": no physics engine; gravity as exact formulas (g = 9.81), the motion still cards.
- Settling (props.gd `settle`, called by main's `_props_show` on every set change, and after a drag): each prop, lowest
  first, rests on the highest top under its origin that is not above it, else the floor.
- Carry marks live ON THE CARDS (inserting / deleting cards keeps them right): card["take"] = {"prop", "hands"},
  card["drop"] = prop. Scene.carries() pairs them. NO grip is stored: it is the prop relative to the hand frame
  (`hand_frame`: one hand's joint and rotation, or between both hands) on the take card, read by posing the body
  there (`_carry_data`, memoised on times() identity + carries + props; the body is restored exactly).
  `props_at(t, B)` = the set at t (held: in the hand frame; dropped: y0 - g dt^2 / 2 down to the top / floor under
  it, keeping only its yaw; landed: stays). `solid_props()` = what the body may stand on (never a carried prop).
  `holding(t, B)` = hand + forearm of the holding side(s), not "through" the prop from the take until RELEASE (0.1 s)
  after the drop (on release the hand is still inside the grip; measured: 2 findings for 2 frames without it).
- Check samples `S.props_at(t, B)` with `S.holding(t, B)` skipped. Mirror swaps the take hands (MIRROR_CARD).
  _prop_del renumbers / drops the marks. Main `_props_pose()` moves the prop nodes to `props_at(playhead)` every frame
  while any card carries.
- SET > USE: Pick up (a hand within REACH 12 cm of the prop on the selected card; box / crate in both hands when both
  are near; else refused with the distance), Put down (on a card where it is held; says how far it falls and how long).
- CARRY FORM (after Nick's correction; the REAL HUMANS FIRST rule): `Rulebook.carry_form(S, t, B)` measures a two-
  handed carry (upper arm from hanging, elbow bend, NIOSH H); `rule_carry_form` WARNs outside 35 deg / 50-130 deg /
  40 cm for 0.1 s. Reference carry on our body: upperarm (0, -80, 0) + lowerarm (90, 0, 0) per side = arms down,
  forearms forward, hands 48.5 cm apart (a 40 cm box between the forearms) at elbow height.
- Found by that screenshot: a toe TIP 2 cm into a 1 m crate stack lifted the whole body onto it (_sole_low_set took
  each sole point's own surface). The toe tip now stands on what the ball of its foot stands on.

## Round 40: jumps (GATES VV; UPGRADES_200 #230 airborne, #228 jump rule). The plan for 238-337 is UPGRADES_300.md
- A card can be marked "air" (card["air"] = true, saved only when on; MIRROR_CARD "free"). Scene.flights(): each run of
  air cards with a card before (k, take-off) and after (l, landing) is a flight from k's LEAVE to l's ARRIVAL
  (times() rows are [move start, arrive, leave]). Memoised on times() identity + the air flags.
- In a flight `_apply` skips the floor and the pins and calls `_fly`: the cards' blend as ever, the hips moved onto
  y = lerp(y0, y1, u) + G/2 (t - T0)(T1 - t), y0 / y1 = the pelvis height when B is posed normally at T0 / T1 (cached
  in the flight dict). Apex over level take-off/landing = G T^2 / 8. A scene with no air card never enters this path.
- ANIMATE > JUMP > Airborne (toggle, icon "air", registry "Airborne: this card is in the air", one undo step): refused
  on the first and last card; says the flight time and the height it means.
- JUMP rule (rulebook `jumps` / `rule_jump`, not from the frame sample: it poses the scene itself): WARN when
  G T^2 / 8 > 0.70 m, the deeper knee's most bend in the 0.5 s before take-off < 30 deg (no dip), or in the 0.25 s
  after touchdown < 45 deg (stiff). Knee bend = angle between thigh (thigh->calf) and shin (calf->foot).
- REAL PEOPLE: flight -> height h = g T^2/8 (Bosco; Asmussen & Bonde-Petersen); recreational CMJ 0.40 +- 0.11 m;
  landing knee flexion soft 117 / stiff 77 deg (DeVita & Skelly 1992, PMID 1548984 - verified on PubMed; the link
  first typed from memory was wrong). Our test jump: 0.40 m, dip 94, landing 94; Check finds nothing on it.
- UPGRADES_300.md: 100 items (238-337) to match Maya/Blender by what an animator does (curves and part keys first),
  from a docs survey of both apps; sources per section.
- Found by small_window (the new JUMP group made the ANIMATE row 5 px too wide at 1280): `_top_fits` read the top
  panel's right margin from `ui_tb.get_parent() as PanelContainer`, but since round 36 that parent is a VBox, so the
  cast was null and the margin 0: the bar could run up to 10 px off the window. It now walks up to the nearest
  PanelContainer. The test now prints WHAT is off the window (it failed naming nothing).

## IK / FK with pole targets (docs/GAP_ANALYSIS.md row 13; how Blender / Rigify do it: docs/research/BLENDER_IK.md)
- `scripts/limb_ik.gd` (`LimbIK`, static): limbs named by their tip `hand_l/r`, `foot_l/r` (chain = upperarm/lowerarm/hand,
  thigh/calf/foot). `solve(B, tip, target, pole, rot)`: closed form. The hinge's bend from the root-tip distance (law of
  cosines about the hinge's own bend axis, limits as candidates), then the root turned rigidly so the tip points at the
  target and the elbow lies in the root-target-pole plane (Blender's pole pre-rotation). Clamped by `clamp_ang`; it
  REPORTS the miss and the clamped joints. Out of reach: straightens toward the target. `pole_from_pose` = Rigify's snap.
- `Scene.ik` = {tip: [{t, target, pole, w, rot?}]}: target/pole on PartKeys' monotone curve, weight linear between keys,
  rot slerped. Played LAST in `Scene.apply` (after cards, part keys, layers, breathing); per joint FK -> IK angles mixed by
  w. No keys or w = 0: the body is not touched (every scene in scenes/ plays byte-identical, 880 frames). `S.ik_last` =
  what the pass did. File key "ik" only when keyed (schema, MIRROR_SCENE, clone, bake clears it, undo snapshots "ik").
- Commands: "IK: pin the picked hand/foot here" (keys from the body as it is now; a key one frame earlier holds the old
  curve), "IK: release the picked limb here" (needs the playhead on a card: the IK pose is written into that card, a
  fixed point so spline lead / layers are met, then weight 0 at t), "IK: snap FK to IK", "IK: snap IK to FK". A snap pins
  the card's own and next card's AUTO move time to its current value, so the timeline does not shift.
- IN-VIEW HANDLES (GATES IK2, `main.gd` `_ikh_*`, tests/ik_handles_test.gd): a limb pinned at the playhead shows a cube at
  its target, a sphere at its pole and a dashed elbow/knee-to-pole line, drawn on top; a press inside one takes it
  (`_ikh_press`, before `_pick`), the drag moves it in the view plane (a foot's target on the horizontal plane through
  it), the limb is solved each mouse move (`_ikh_pose`), release keys it at the playhead (one undo step, none without a
  move). Handles hide when nothing is pinned there and in clean views.
- WHICH WINS (GATES IK3), Blender's order (constraints, then the IK pass last): THE PIN WINS over foot planting and over
  the two-hand grip (both are solved in Scene._apply, the IK pass runs after). A pinned weapon hand: the other hand
  follows the weapon (apply_grip after the pass) unless it is pinned too. Live FK edits on B do not run the IK pass
  (it plays on scrub / play); `_after_edit`'s apply_grip can pull a pinned grip hand onto the weapon until the next scrub.
- Known: release / snap FK refuse off a card (part keys would change the whole joint's curve before the pin).
- tests/ik_pin_test.gd (ik_pin:h).

## User constraints (round 51, GATES CN; docs/research/BLENDER_CONSTRAINTS.md, learned from, no Blender code)
- `scripts/constraints.gd` (`Constraints`, static). `Scene.cons` = a STACK (list) of {type, owner, target, offset?, w,
  wk, mute?, height?}. Types: `child_of` (a hand / foot via LimbIK.solve, or the pelvis: owner = target x offset, the
  offset stored when made = Blender's Set Inverse), `track_to` (the head: LookAt.solve + a pattern search on neck + head,
  inside the limits), `floor` (a foot: Body.foot_sole_low, lifted by LimbIK with the foot's turn kept; pushes, never
  pulls). Targets: a part of this body, the weapon, a world point, a prop, another fighter's part (`{"kind": "actor"}`:
  that fighter's scene posed at t at its placement; `Constraints.link(hero)` gives each fighter's scene a weakref to
  the hero; main._actors_build calls it). Influence = a layer's weight (Scene.layer_weight: "wk" keys x "w").
- EVALUATION ORDER in `Scene.apply`: cards -> part keys -> layers -> breathing -> IK -> constraints in list order ->
  joint limits. Why: Blender runs the constraint stack on the finished animated pose, top to bottom, each one seeing the
  one above; a constraint corrects what was keyed (IK included), it is not an input to it. Limits last: every angle a
  constraint writes goes through Body.clamp_ang, so no constraint drags a joint past its range.
- Influence blend: per joint angles animated -> constrained by w (continuous: a keyed fade has no pop); hips: position
  lerp + rotation slerp in world space. w 0 / muted / none: the body is not touched (byte for byte).
- Commands ("Constraint: ..."): use the picked part as the target / target the other fighter's head (choices, no undo),
  child of the target (default target: the other hand; on from the playhead, 0 one frame before), head looks at the
  target (default: the other fighter's head, else the weapon; fades in over 6 frames), keep the picked foot above the
  floor, fade out / fade in over 6 frames, release here keeping the pose (Constraints.release_keep: LimbIK.snap_fk with
  that constraint off writes the pose into the card, then influence 0), remove. Each edit one undo step ("cons").
- File key "constraints" only when present (schema, MIRROR_SCENE via Constraints.mirror_file, clone, bake clears it).
- Known: no chest / eyes share for Track To; release keeping the pose is hands / feet only (hips: fade instead); a
  prop target is the prop's own place (a carried prop's moving place is not read); no viewport drawing of constraints.
- tests/constraints_test.gd (constraints:h).
## Shot camera (GATES SC; docs/GAP_ANALYSIS.md row 21; docs/research/SHOT_CAMERA.md)
- `Scene.camera` = [{t, pos, aim, f mm}], in the hero's world. Between keys, pos, aim and f follow `PartKeys.at`
  (PCHIP). The lens is 36 mm wide and the frame 16:9, so fov_v = 2 atan(20.25 / 2 / f) (`scripts/shot_camera.gd`).
  The file key "camera" is written only when a camera exists. It is in the schema, is mirrored (x negated) and cloned,
  and the undo snapshot "camera" holds it.
- Commands: "Camera: key the shot camera from the view" (the view's origin, aimed at its pivot, a lens that frames
  the same height), "Camera: look through the shot camera" (a view toggle: `main.shot_through`; orbit does nothing
  while it is on), "Camera: remove the key here", and "Camera: lens 18/24/35/50/85/135 mm".
- Look-through: `ShotCam.apply_to` gives the view camera a shifted frustum, so the shot lands in `main.shot_rect()`
  (the largest 16:9 in the free view). `ShotFrame` draws the passepartout. Export playblast renders through the
  camera when one exists, cropped to the frame (16:9). Scenes without a camera render as before.
- tests/shot_camera_test.gd (shot_camera:w).

## Round 43: animator tools, kept light (GATES YY; docs/ANIM_RESEARCH.md) - one instance, gate by gate
- YY0 WALK LEGS + YY1 LIVE BALANCE (Shift+B: COM on the floor, support hull, green/amber/red/grey). YY2 "Plant every
  sliding foot" (Check's slides planted at once, one undo step).
- YY3 HANDS: curl / spread sliders, Point, Relaxed (Varghese 2020 resting cascade; DIP = 0.76 PIP, Hahn 1995).
- YY4 BACK: one forward / side / twist slider over spine_01..head, shared by each joint's own range (thoracic share
  UNVERIFIED). BACK shows for trunk parts, HANDS for limbs (one more header broke the 300 px inspector bar).
- YY5 SHOULDERS FOLLOW (default on): an upper arm turned by hand past 30 deg lifts / draws back the clavicle to 10 / 15
  (McClure 2001 bone pins: 10 / 21; 15 is the body's limit). NO SCAPULA in this body, so the GH:ST ratio is not
  measurable: restated. The clavicle capsule sits 3.2 cm inside the neck at rest: contact allowance now calibrated at
  people's girdle extreme for clavicle pairs only.
- YY6 BREATH (Scene.breath, off by default): chest front 4.9 mm at 15/min (Massaroni 2015: 1-8 mm). JAW DEFERRED: the
  mannequin has no jaw bone or mouth (numbers kept in GATES).
- YY7 REAL WALKERS' BAND: refs/gait_band.json from Fukuchi 2018 open data (42 adults; tools/make_gait_band.py rebuilds
  it from the 42 *walkOCang.txt files) drawn in the curve editor behind the body's hip / knee / ankle over one step
  (scripts/gait_band.gd); "Compare the walk to real walkers" names joints > 2 SD for > 10 % of the step. FINDING, NOT
  FIXED: walk_bat's knees read ~25-31 deg at 40-50 % of the cycle (people 4-8) and ankles ~40 % out; the body's cycle
  starts at BALL landing, people's at heel strike (a few % lag, uncorrected), which explains part of the peak shift
  (66 at 80 % vs 63 at 74 %) but not the late-stance bend. YY0's mid-stance bar (4.8-9.4) measures a different instant.
- YY8 "Block: stepped keys" -> "Spline and check" (stepped is a view: never edits the scene). YY9 ONE LAYER: Scene.layer
  (joint -> deg) x layer_w on top of the cards, before breath, then the grip; saved only when present; mirrored.
- FIXED: Ctrl+Z did not restore breath or the layer; the undo audit's fingerprint lacked both (now in it). The audit
  also resets the stepped VIEW per start (a Block trial left it on) and has LAYER / STEPPED starts.
- Load flakes (pass alone): popup_leak, hover, small_window, weapon_picker, and NEW carry (clicks under load).
- No git remote: every commit is local.

## Round 42: ten agents again (GATES XX; UPGRADES_300 #240-#333) + Nick's walk arm
- NICK'S BUG (10-17, "the arm literally rotate to inside body pointing backwards"): walk_bat's bat arm was raised
  72-81 deg with the elbow 21-27 cm ABOVE the wrist, forearm pointing back into the chest (idle_bat the same, 89 deg).
  Body.sweep_bat_arm scored only wrist, aim, roll, contacts: the elbow was free. Body.elbow_low (plan "elbow_low", 0 =
  off, every other plan cooks as before) keeps the elbow under the wrist; now raised 1-10, elbow 9 cm under, forearm
  forward. tests/walk_arm_test.gd. Fingerprint now e74213bb9e6917b9d997704d62203396 (only those two scenes changed).
- Body.decompose: 2 atan2(|v|, w), not 2 acos(w) (WW7's finding): tiny swings no longer read 0. tests/decompose_test.gd.
- XX1 KEY INTERPOLATION (part_keys.gd): per-key constant/linear/bezier, handles auto_clamped (PCHIP, the default; old
  keys bit-identical) / auto / vector / aligned / free, per-joint infinity hold/linear/cycle/cycle_offset (stored on
  the joint's first key). Registry "Part key: ..." commands, picked part's key within 0.05 s of the playhead.
- XX2 CURVE EDITOR (curve_editor.gd): "Curve editor" draws the picked part's keys as X/Y/Z curves; drag = one undo step,
  whole frames, clamped to limits and neighbours. Overlaps the speed graph when both are open.
- DD0-DD2 CURVE EDITOR, MANY KEYS (round 48): Shift+click / box select key dots; drag moves all selected (whole frames,
  Ctrl = snap to a card, never past an unselected neighbour); Alt+drag scales (time about the playhead, angle about the
  mean). "Shape" menu = Blender Key > Blend (scripts/key_blend.gd: breakdown, blend to neighbour, push/pull, ease, match
  slope, scale from neighbour, blend offset) by the factor box. "Mods" = curve modifiers noise / stepped / limits with a
  mix, on the joint's FIRST key as "mods" (PartKeys.value_at = keys + stack; at() = the keys alone; Scene.sample plays it).
- DD3 views: "View" button cycles degrees / -1..1 (each angle fitted) / lanes; drags edit the real angle per its scale.
- DD4 BAKE (bake.gd, "Bake to cards"): one card a frame = what Scene.apply plays (visual keying); floor, pins, layer,
  breathing, natural, spline, stepped switched off because they are inside the cards; one undo step.
- DD5 WHY (why.gd): red, named spans on the curve where HITCH (+-3 frames) or TIP SPEED (frames over the cap) fire for
  a part this joint moves (tip: spine/arms/hands; hips: pelvis/legs; head: neck/head/spine).
- NA0 DOPE SHEET COPY: Shift-drag a card diamond = a copy dropped inside a move (the move is split, later cards keep
  their arrivals); drag a part-key diamond = its keys by whole frames (stops a frame short of a neighbour), Shift = copy;
  stepped view hides breakdowns and moving holds.
- NA1 LAYERS (Scene.layers): each {name, mode add|over, w, wk [[t, w]] (keyed: curve x w), mute, solo, lock, v {joint:
  deg, "offset": hips metres}}; played after the YY9 first layer, in order; any solo silences the rest. Commands
  "Layer: new additive / new override / next / mute / solo / lock / key the weight here"; edits go to the active layer.
- NA2 FIX ON A LAYER (layer_fix.gd): a HEAD QUIET fix as an additive layer (played difference at the card, weight fitted
  per frame); exact at the card, close between cards (Check may still find it there: the plain Fix is the full one).
- NA3 MERGE DOWN (layer_merge.gd, "Layer: merge down (into the cards)"): cards re-posed by a fixed-point pass so the
  unlayered scene plays the layered one at every arrival; the every-frame miss is measured and said.
- XX3 DOPE SHEET (dope_sheet.gd): cards row + 8 part-group rows of diamonds; card["ktype"] key/breakdown/moving_hold/
  extreme (a mark only, saved only when not "key"); drag a card diamond to retime. Timeline + sheet share _retime_*.
- XX4 BREAKDOWNER (breakdowner.gd): true per-joint slerp between neighbour cards, Shift+E slider -50..150 %, 25/50/75 %;
  paste flipped on selected parts / at 50 %.
- XX5 FOOT ROLL (foot_roll.gd): heel / ball / toe pivots, drift <= 0.018 mm. Push-off ankle -15..-20 is UNVERIFIED.
- XX6 LOOK-AT (look_at.gd): neck + head aim the gaze (the body has no eyes); head/eye split from Freedman & Sparks 1997,
  RHESUS data. Chin-to-chest targets stop short at contacts.
- XX7 MOCAP CLEAN (mocap_clean.gd): foot lock in contacts (creep 3.8 -> 0.71 cm), pop / 360 flip finder.
- XX8 GAIT (Check rule): step/height, cadence, arm swing, arm-leg phase vs real walkers (PEOPLE.md). FINDING:
  walk_bat steps 0.30 m = 0.176 of height against 0.415 for real walkers -> WARN. Nick then asked ("make them real"):
  re-cooked with a 0.36 m first step, steady steps 0.69 / 0.71 / 0.69 m (0.40 of the 1.74 m read height), 104
  steps/min (0.57 s each), double support as people (lead hip 28 flexed / knee 5; trail hip 15 extended / knee 15,
  heel up 15 via the new plan "heel_deg", cook default 25 unchanged), stop on standing legs. GAIT: no findings.
  The real walk travels 2.45 m: it now starts 1.85 m back and stops with the hips 0.6 m out (the OLD walk ended
  inside the default dummy at 1.5 m: a 0.02 m chest hit at 3.3 s); now 0.9 m short of it, the whole 3.51 s plays.
- WALK LEGS (scene.gd TOE-OFF / STANCE / SWING, card flag "walk"; tests/walk_legs_test.gd): at real length the old
  playback snapped the swing knee 1743 deg/s and folded the stance knee to 37-51 deg. Now: the hips' height follows
  the stance leg (vault, knee 8), stance feet BUILT on their marks (_construct: reach the ankle, then pitch), toe-off
  plantarflexes 20 deg with the knee floored at 38, swing on a delayed path. Measured vs people: mid-stance knee
  4.8-9.4 (5-10 Perry), swing knee peak 65.9 (60-65), toe-off foot-ground 43-47 (49-68 by speed, PMID 41583941: still
  low), swing foot 4.33 m/s (~4.4), pelvis rise 6 cm (people ~4-5: high), fastest knee 671 deg/s (first step from the
  half step; steady steps 470), stance foot slide 3.1 mm (was 51). CONTROL in the test: walk flags off -> knee 50.9.
  Gotchas: Body.plant iterates from the leg it is given and near a straight knee jumps branches (0 -> 21 deg in one
  frame): seed it bent, or use reach (bisects on distance). A joint-angle blend between two legs on one mark is off
  the mark (16 mm): re-put the ankle with reach.
- XX9 USD (usd_export.gd, tools/export_usd.gd): exports/<scene>.usda as UsdSkel; read back by our own parser only (no
  pxr here). XX10 SHADING: "Shading: next" solid/matcap/silhouette/x-ray; playback shows real fps and dropped frames.
- Lead fixes at merge: --shot forces the strip's line (a throttled 400 ms header made determinism flaky: 3.15 vs 3.45
  s); "inbetween" search exact keywords; undo_audit skips the .usda export (it wrote exports/combo3.usda into the repo).
- Lessons: an agent must run undo_audit + command_search even with "no new command" (two missed it); confirm_test needs
  scenes/_wip, absent in fresh worktrees (agents reported "hangs"); killed test processes leave poser_test_<pid>.cfg in
  app_userdata - clean them at the end of a round.

## Round 41: ten agents in parallel worktrees (GATES WW; UPGRADES_300 sections M-V first items)
- Built in .claude/worktrees/<key> on branches r41-<key>, merged --no-ff by the lead; .claude/.gdignore keeps Godot
  out of them. Lessons: an agent must never taskkill every Godot (one did; the others' runs died); a test must not open
  scenes/bo_sweep.json (deleted in Nick's working copy); after a merge that adds a class_name run --import first.
- WW1 PART KEYS (scripts/part_keys.gd): K keys the picked joint at the playhead; that joint follows its own monotone
  PCHIP curve over the cards' blend, ends held. S.part_keys saved only when used, mirrored to the twin, in undo ("pk").
- WW2 CURVES (scripts/curves.gd): UI-free Euler unwrap, Gaussian, zero-phase Butterworth, Decimate, Clean over
  [t, value] tracks; each returns {track, report}. Curves.sample_scene_channel(S, B, joint, fps).
- WW3 INBETWEEN (scripts/inbetween.gd): breakdowner push / relax toward the neighbouring cards.
- WW4 FRAMES: click the time readout for frames; "Frame rate: next" steps 24/30/60 keeping card seconds (fps in undo);
  Shift/Alt+click on the ruler set a preview range that Play and Loop stay inside. View only, never saved.
- WW5 MARKERS (scripts/markers.gd): named cues on the ruler, Ctrl+] / Ctrl+[ jump, remapped by retime, saved only when
  used, exported as game "events" {t_frac, name, kind}. No rename/kind UI yet (always "note").
- WW6 PLAYBLAST: --playblast out.avi [--fps N] [--burn] writes an MJPEG AVI with a burn-in box; --record shares _record.
- WW7 BVH IMPORT (scripts/bvh_import.gd): round trip 0.00004 deg; drop a .bvh to open it. Carries its own atan2
  decompose because Body.decompose loses swings under ~0.05 deg (acos of a float32 w) - not fixed there yet.
- WW8 THROW (scripts/throw.gd): a prop let go by a moving hand flies with the hand's 1/60 s velocity, bounces e = 0.3
  (UNVERIFIED, mine), stops under a 2 cm rebound. A still hand keeps round 39's fall.
- WW9 PEOPLE + LIFT FORM: docs/PEOPLE.md holds every real-human number the rules use with its link; LIFT FORM warns a
  held stoop (hands below the knees, trunk > 60, knee < 30; Storari 2025, Shu 2007).
- WW10 JUMP PHYSICS: the CoM, not the pelvis, rides the parabola; Rulebook.land_bar(h).
- Open: Scene.loop not in undo; schema scene properties lack loop/props; carry memo ignores card poses; pelvis twist
  in part keys not wrapped the short way; .cs export ignores events.

## Round 51 (GATES PR): proportions
- A scene may carry `"body": {"stature": m, "scale": {segment: k}, "sex", "mass", "preset"}` (scripts/proportions.gd; only
  written when not the mannequin as shipped). `Body.set_proportions(d)` rebuilds the rest skeleton from data/skeleton.json
  (never edited); `Scene.apply` puts the scene's body on whatever plays it. Commands: "Body: proportions..." (dialog),
  "Body: 5th percentile woman" ... "Body: 95th percentile man" (ANSUR II), "Body: the mannequin's own proportions".
  `Proportions.retarget(S, B, body)` keeps every angle and moves the hips so the soles stand where they stood.

## ANIMATION IMPORT FROM OTHER SKELETONS (GAP_ANALYSIS row 26; method + sources docs/research/RETARGET.md)
- `scripts/anim_import.gd` (`AnimImport`): `load_source` (FBXDocument / GLTFDocument / BvhImport.parse -> global transforms per frame),
  `map_bones` (Mixamo / UE / Godot / Blender / DAZ / Biped names via `classify`; the spine by STRUCTURE), `retarget` (world
  deltas, rest-pose difference by bone direction, root motion x leg-length ratio, hips about the file's origin), `cards`
  (MocapClean only on a FOOT SLIDE, `VideoImport.thin` + `refine` to 1 deg / 5 mm), `import_file` (all of it).
- main: command "Import animation (fbx / glb / gltf / bvh)..." (`_anim_import_ask`) -> `_import_anim` writes a NEW scene in
  scenes/_wip; a dropped .fbx, a non-Kine .bvh, or a rigged + animated .glb goes there too.
- GOTCHA: Godot's FBX reader takes the root bone's rest TRANSLATION from the pose the file was saved in (rotations from the bind
  pose); an armature with no skinned mesh has no rest at all but its saved pose. Root motion is therefore measured from the origin.
- Test: tests/anim_import_test.gd; fixture tests/fixtures/mixamo_rig.fbx (+ _ref.json) made by make_mixamo_fbx.py in Blender
  (regenerated into user:// on each run when Blender is installed; the committed one is used on CI). tests/fixtures has .gdignore.
## Generic props (GAP_ANALYSIS row 22; docs/research/PROPS.md has every size with its source)
- **Kinds** (scripts/props.gd `KINDS`): `ball` (size 5 football, a true sphere: a solid with `"r"`), `moving_box`
  (U-Haul Small), `door` (a leaf hinged at its origin, `"swing"` deg, + toward +Z), plus the round-37 set and imports.
- **Keys over time**: a prop's `"keys"` [{t, pos, yaw, swing}] play through `PartKeys.at` (`Props.posed(p, t)`);
  `Scene.props_at(t, B)` returns the set as it is at t (keyed, carried, falling). An unkeyed prop is returned itself and
  saves as before (kind, pos, yaw only). Search: "Prop: key its place here", "Prop: delete its keys", "Door: open /
  close 15 deg (key here)". A keyed prop dragged or turned is keyed at the playhead; Shift+drag turns a prop.
- **A prop as a target**: "Constraint: target the picked prop"; `Constraints.target_xf` reads `Scene.prop_xf_at`, so a
  hand's Child Of on a CARRIED box follows the box (it used to follow its stored place).
- **Mirror**: `Props.mirror_dict` (a door: yaw -> 180 - yaw, swing -> -swing, the hinge reflected).
## Clips placed as strips (GAP_ANALYSIS row 12; docs/research/NLA.md: Blender NLA / Maya Time Editor, formulas)
- `Scene.clips` = [{src, start, repeat, speed, bin, bout, type replace|add, mask all|legs|upper|arms|arm_l|arm_r, extra
  nothing|hold|hold_forward, w, mirror, mute}] (scripts/clips.gd, `Clips`, static). The source (a scene, or a pose / keyed
  move from moves/ or poses/) is READ BY REFERENCE (cached by path + modified time) and played by its own Scene.apply on a
  scratch body, so a clip at weight 1, mask all = opening that file. Strip = L x repeat / speed; cycle k's hips moved by
  k x the cycle's floor step (cycle with offset). Weight = w x linear ramps in / out.
- ORDER in Scene.apply: cards -> CLIPS (list order) -> layers -> breathing -> IK -> constraints. No clip: nothing touched
  (combo3 + walk_bat 247 frames hash the same as before). A legs clip never calls apply_grip, so the arms stay bit for bit.
- File key "clips" only when present (schema, MIRROR_SCENE: the source plays mirrored, arm_l <-> arm_r; clone; bake clears
  it; undo snapshot "clips"). App: scripts/clips_ui.gd (`main.clips_ui`, `.sel` = picked clip): "Clip: place a scene
  here..." / "place a move here..." / "edit the picked clip..." (one dialog) and "remove the picked clip"; the timeline
  draws one bar per clip under the cards (Timeline.CLIP_H rows, blend ramps shaded, repeat seams), click picks, drag moves
  it (one undo step, pushed on the first move). tests/clips_test.gd (clips:w).

## Round 2 R9: the local HTTP API (scripts/local_api.gd)
- Off by default. View > Display > Local API turns it on (settings file `[api] port`, default 8765); it binds 127.0.0.1 only and the
  status line prints a per-session token (also copied). Every request needs `X-Poser-Token: <token>`; a browser's Origin without it gets 401.
- `GET /describe` (commands + state), `POST /run {"command": "<id or name>", "args": ["card=2", ...]}`, `GET /check`, `GET /shot` (PNG).
  It runs the same AgentTools code as `serve` and the MCP server: one undo step per edit. tests/r9_test.gd.
