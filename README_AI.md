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
