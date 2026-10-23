# Kine (formerly Poser) — read this before starting work

Godot animation app. Work branch: `poser-ui-rounds` (default). `master` is older.
Roadmaps: `docs/ROADMAP.md`, `docs/ROADMAP_400.md`, `docs/GAP_ANALYSIS.md`. Tests: `tools/run_all.sh`.

## Don't redo work that already exists

Over 70 feature branches (`wt-*`) live on Nick's machine. Almost all are **already merged**
into `poser-ui-rounds`, so before starting a roadmap item, search the code and
`git log --oneline | grep -i <item id or keyword>`. If it's in the log, it's done.

All 8 `wt-*` branches above (B16, I20, A09, P05, E15, J24, H24, F14) and P01 page tours are finished and merged
on `claude/inspiring-clarke-xnl0aa` (PR into `poser-ui-rounds`), together with new items A12 A13 A14 B02 B05 B09 B20
C01 C02 D03 D05 F06 F08 P02 and the inset + bridge half of B03 (bevel still open). Don't redo them: until that PR
merges, branch off `claude/inspiring-clarke-xnl0aa`, not `poser-ui-rounds`.
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
