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
Known failures on the base too (not caused by this work): `units` (unitless numbers). `command_search` and
`search_forgive` were fixed on w4-integ (they ignore the user's own saved files: `CommandSearch.user_files_off`);
command_search takes ~10-20 min, so give it `TIMEOUT=1800`; undo_audit_s3 (~9 min, it waits for async commands) and explain need `TIMEOUT=1500`. undo_audit_s3 still fails 3 `new_from_template_*` lines (they open a new scene: not an in-place edit) and s0 `help_show_the_tour`.
Agents: never kill Godot by image name (`taskkill /IM`); other runs on this machine die with it (exit 1, no error).

ROADMAP 22 (type a move, get blocking) is done and merged as `wt-textmove2`. Ignore the old `wt-textmove`.

## How to work here
- Work on your own branch and open a PR into `poser-ui-rounds`. Don't push straight to it.
- To continue a WIP branch above, branch off it, finish it, and PR it.
- Don't commit generated `.uid` files, `exports/`, `.playwright-mcp/`, or `__pycache__/`.

## Building or editing a part with AI: the cheap way (docs/AI_COST.md)
To make a part, write ONE JSON record (copy `data/part_examples/*.json`) and run
`python tools/kine_call.py part_build @file.json` (add `"facts": true`). That cost $0.36 for a 28-body arm; a lane that
wrote a GDScript generator for the same arm cost $7.88. Use `commands {"find": ...}`, never the whole list.
Lost a session to a usage limit? `python tools/where_were_we.py` shows where it stopped.
