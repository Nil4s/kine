# Boot time: source launch vs exported build

Measured on w4-boot2 (Godot 4.7.2, Windows 11), with `--position 3000,3000 -- --easy --boot-profile --boot-quit`.
The number is `BOOT usable_at_ms`: engine start to the first usable frame (body and Easy home on screen).

## Numbers

| Launch | Runs (ms) | Median | "engine start -> _ready" |
|---|---|---|---|
| Source (`godot --path`), baseline | 11834, 11584, 11959 | ~11.8 s | 8612 (one run logged) |
| Export, Text (`Kine_text.exe`), baseline, warm | 9862, 8736, 6848, 6608, 7147 | ~7.1 s | 4942-5908 |
| Export, Text, first run after the build | 18956 | (cold) | |
| Export, Binary tokens compressed, baseline | 6431, 6294, 6127, 5988, 6217 | 6217 | ~6050 |
| Export, Binary tokens, baseline, first 3 runs after the build | 9856, 8891, 12086 | (cold) | |
| Export, Binary tokens, lazy prototype (not committed) | 6203, 5858, 5758, 5904, 5807 | 5858 | 5.9 s |
| Source, lazy prototype | 10009, 9746, 9396, 9685, 10179 | ~9.7 s | 8.1-8.4 s |

Reading the table:

- The first runs of a freshly written exe were 1-3 s slower (cold file cache and antivirus scan). Medians use warm runs only.
- In every build, the time before `_ready` is most of the total. In the binary-tokens export it is about 6.0 of 6.2 s. The block after `_ready` (body split, skin, UI, Easy build, cards) is about 2.5 s from source and less in the export.
- The source numbers are not symmetric: the baseline source runs were the first after import, and the prototype source runs came later. Only the exported comparison is like-for-like.

## What the export is

Two presets were added to `export_presets.cfg` (Windows Desktop, `embed_pck=true`, console wrapper on so the exe prints the BOOT rows):

- `Windows Text`: `script_export_mode=0` (GDScript as text). Output `C:/Temp/claude/kine_export/Kine_text.exe`, 146 MB.
- `Windows Binary Tokens`: `script_export_mode=2` (compressed binary tokens). Output `C:/Temp/claude/kine_export/Kine_tokens.exe`, 142 MB.

Binaries are not committed. The export templates for 4.7.2 were already installed.

Compressed tokens are about 6 s to the first usable frame, against about 7 s for text (warm medians 6.2 vs 7.1 s). Both are about half the source time, because an export does not parse `res://` sources that are not in the pck, and the `.gd` files are already compiled at export time.

## Why script loading is the big block

The earlier finding said "961 scripts, 166k lines". That is the count of `.gd` files in the project. The count that loads at boot is smaller:

- Reached from `scripts/main.gd` through `preload()`, `extends`, and `class_name` identifiers used in code (comments and strings excluded): **428 scripts, 166,640 lines**.
- `main.gd` alone is 22,199 lines and has 259 direct edges. Almost all come from typed members (`var kmed: KMeshEditUI`) and static calls on `class_name` classes, not from `preload()`. There are only two `preload()` calls in `main.gd` (`DetailTool`, `Importer`).
- GDScript loads and analyzes every script that a typed reference names, transitively, before `_ready`. Parse-and-analyze cost is roughly proportional to lines: 166k lines in about 6 s.

Heaviest subtrees pulled in at boot (lines of the whole subtree, scripts in it). Subtree = what would stop loading if this script were lazy:

| # | Script | Subtree lines / scripts | Needed for Easy's first frame? |
|---|---|---|---|
| 1 | `tools/mesh_tools.gd` (MeshTools; `ui_cmd.tools = MeshTools.rows(self)` runs at boot) | 9,796 / 21 | no (Model page tools), but built at boot for the command box |
| 2 | `scripts/scene.gd` | 2,598 / 2 | yes |
| 3 | `scripts/body.gd` | 2,593 / 1 | yes |
| 4 | `scripts/kmesh_sculpt_ui.gd` | 1,836 / 7 | no (Expert sculpt) |
| 5 | `scripts/video_iq.gd` | 1,692 / 2 | no (video import) |
| 6 | `scripts/text_blocking.gd` | 1,642 / 2 | no for the first frame (spec blocking) |
| 7 | `scripts/timeline.gd` | 1,500 / 1 | yes (the strip) |
| 8 | `scripts/kmesh_boolean.gd` | 1,431 / 1 | no |
| 9 | `scripts/kmesh_curves_ui.gd` | 1,307 / 3 | no |
| 10 | `scripts/rom_clash_ui.gd` | 1,260 / 2 | no |

Two more were not in the top ten by lines but are the biggest safe candidates: `scripts/agent_tools.gd` (6,268 lines, 14 scripts: the local API, AI box, macros, all user- or API-triggered) and `scripts/kmesh_edit_ui.gd` (4,183 lines, 11 scripts: the Model page's test cube, created on first use in `base_body.gd` and `_kmesh_edit_start`).

## Prototype: lazy `agent_tools` and `kmesh_edit_ui`

What changed (not committed; patch kept at `C:\Temp\claude\scratch\lazy_proto.patch`):

- `AgentTools` references in 11 importers became `load("res://scripts/agent_tools.gd")` at the use site, and typed parameters (`T: AgentTools`) became untyped. Three `:=` inferences that depended on the type were changed to `=`.
- `KMeshEditUI` references in `main.gd`, `base_body.gd` and `sculpt_pose_ui.gd` became `load(...)` at the creation site, and the typed members became untyped.

Result of the import graph (preload-only, the same method as above):

- Boot closure: 428 scripts / 166,640 lines before; 403 scripts / 156,189 lines after (-25 scripts, -6.3% lines).
- Exported binary-tokens build: median 6,217 ms before, 5,858 ms after (-0.36 s, -6%). This matches the line reduction.

Tests:

- `ai_box`: PASS.
- `agent_tools`: 2 checks fail ("transcript is byte-identical": `"id":1.0` vs `"id":1`). The same 2 checks fail on the committed HEAD, so this is not caused by the change. It is a pre-existing failure in this build.
- The other suites that use the changed classes were not run (about 78 touch them). Per the rule, the prototype is **not committed**.

Next steps if pursued:

1. Run the remaining users' suites (headless first), and fix the `:=` sites they expose.
2. `mesh_tools`: 21 scripts / 9.8k lines, the biggest. It is built at boot for the command box (`ui_cmd.tools`). Making it lazy needs the command box to build its tool rows on first open.
3. The savings are linear in lines. Lazy loading alone will not reach the "few seconds" target. The next step is to make `main.gd`'s 22k lines (13% of the graph) and its typed `class_name` members cheaper, or to split the Easy first frame from the Expert classes.

## Setup notes

- `w4-boot2` = `w4-boot` plus `w4-integ`. The one conflict was `tools/run_all.sh` (the EXTRA list); resolved by keeping `boot:w` and adding `readpose:w`.
- Import ran once (`--headless --import`, about 110 s).
- `tools/run_all.sh` was not run. Suites were run one at a time with `-s tests/<name>_test.gd`, off-screen.
