# Kine (formerly Poser) — read this before starting work

Godot animation app. Work branch: `poser-ui-rounds` (default). `master` is older.
Roadmaps: `docs/ROADMAP.md`, `docs/ROADMAP_400.md`, `docs/GAP_ANALYSIS.md`. Tests: `python tools/run_par.py` (parallel, windows off-screen, `--changed`, `--retry`); `tools/run_all.sh` is the old one-at-a-time runner.
Run your item's own test + `--changed`; the full suite only once per 25 merged items (Nick: Godot windows must not flood his screen).

## Don't redo work that already exists

Over 70 feature branches (`wt-*`) live on Nick's machine. Almost all are **already merged**
into `poser-ui-rounds`, so before starting a roadmap item, search the code and
`git log --oneline | grep -i <item id or keyword>`. If it's in the log, it's done.

All earlier `wt-*` branches, PR #1 (`claude/inspiring-clarke-xnl0aa`) and waves 2 + 3 (50 items, `w2-integ`) are
merged into `poser-ui-rounds`: ROADMAP_400 is at 106 / 400. Branch off `poser-ui-rounds`.
Plans: `docs/APP_ROADMAP.md` (milestones, the launch gate), `docs/INNOVATIONS.md` (100 new body-aware items, N001-N100).
Licence: source-available, PolyForm Noncommercial or Small Business + commercial licence (PR #3); never MIT.
Model-preview keys are crowded now (see the header of `scripts/kmesh_edit_ui.gd`): M = merge, T = measure,
E/I extrude/inset, Ctrl+T triangulate, H heat map, U UV shading, K shape key. New mesh ops: add a line to
`scripts/mesh_tools.gd` (P02 search registry) and fill its "do" field.
Known failures on the base too (not caused by this work): `units` (unitless numbers), `command_search`
(frame_data.gd `_tip`/`_hitboxes` script errors, 'mirr', lambda-bound file commands), `search_forgive` ('chekc').

ROADMAP 22 (type a move, get blocking) is done and merged as `wt-textmove2`. Ignore the old `wt-textmove`.

## How to work here
- Work on your own branch and open a PR into `poser-ui-rounds`. Don't push straight to it.
- To continue a WIP branch above, branch off it, finish it, and PR it.
- Don't commit generated `.uid` files, `exports/`, `.playwright-mcp/`, or `__pycache__/`.
