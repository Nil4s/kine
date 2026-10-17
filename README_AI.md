# Poser for agents: one page

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
