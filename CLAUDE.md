# Kine (formerly Poser) — read this before starting work

Godot animation app. Work branch: `poser-ui-rounds` (default). `master` is older.
Roadmaps: `docs/ROADMAP.md`, `docs/ROADMAP_400.md`, `docs/GAP_ANALYSIS.md`. Tests: `tools/run_all.sh`.

## Don't redo work that already exists

Over 70 feature branches (`wt-*`) live on Nick's machine. Almost all are **already merged**
into `poser-ui-rounds`, so before starting a roadmap item, search the code and
`git log --oneline | grep -i <item id or keyword>`. If it's in the log, it's done.

These branches are **not merged yet**. They're pushed to GitHub, so check them out instead of
starting over:

| Branch | What | State |
|---|---|---|
| `wt-blkeys` | B16: optional Blender-style G/R/S modal keys on pose + model preview | finished, not merged |
| `wt-faceword` | I20: face from words (FACS AU mix through the words box) | finished, not merged |
| `wt-mattr` | A09: KMesh attributes (vert/corner/edge/face) through save/load, undo, repair | finished, not merged |
| `wt-mousehint` | mouse hints (`scripts/mouse_hint.gd` + test) | WIP, interrupted |
| `wt-photomat` | photo materials for props (`scripts/photo_material*.gd` + test) | WIP, interrupted |
| `wt-rigword` | rig from words (`scripts/rig_words.gd` + test) | WIP, interrupted |
| `wt-wbroke` | weight-break check (`scripts/weight_break.gd` + test) | WIP, interrupted |
| `wt-deform` | deformation check (`scripts/deform_check.gd`), no test yet | WIP, interrupted |

ROADMAP 22 (type a move, get blocking) is done and merged as `wt-textmove2`. Ignore the old `wt-textmove`.
`wt-pagetour` (page tour) was started but has no code yet, only `.uid` files.

## How to work here
- Work on your own branch and open a PR into `poser-ui-rounds`. Don't push straight to it.
- To continue a WIP branch above, branch off it, finish it, and PR it.
- Don't commit generated `.uid` files, `exports/`, `.playwright-mcp/`, or `__pycache__/`.
