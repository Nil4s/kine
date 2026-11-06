# UIEXP audit (lane L2)

Screens: **Part** (Part workspace, a sketch open, Extrude dialog), **Assembly** (two library parts placed), **Engineering** (Assembly with the Fits panel
open: tolerances and stack-up). Sizes 1920x1080, 1600x900, 1366x768, 1280x720. Tool: `tools/uiexp_audit.sh <tag>` (uses `scripts/uiexp_probe.gd`);
raw numbers in `docs/uiexp/audit_before.json` and `audit_after.json`; screenshots in `C:/Temp/claude/uiexp/`; sheet `docs/uiexp/before_after.png`.
(Engineering is not a separate screen in the app; it is the Assembly screen plus its engineering panels: Fits, BOM, Stages, Check motion.)

## Before (base 6254e061)
| screen | size | interactive | outside window | panel overlaps | fonts < 12 | view share |
|---|---|---|---|---|---|---|
| part | 1920x1080 | 59 | 0 | 4 | 10 | 72 % |
| part | 1600x900 | 59 | 0 | 4 | 10 | 65 % |
| part | 1366x768 | 58 | 0 | 4 | 10 | 56 % |
| part | 1280x720 | 56 | 0 | 4 | 9 | 52 % |
| assembly | 1920x1080 | 60 | 0 | 1 | 1 | 80 % |
| assembly | 1280x720 | 60 | 0 | 2 | 1 | 64 % |
| engineering | 1920x1080 | 70 | 0 | 2 | 1 | 73 % |
| engineering | 1280x720 | 70 | 0 | 3 | 1 | 47 % |

Findings: the app was already inside the window everywhere (0 controls outside, 0 clipped texts). What was wrong:
- every side panel started at y = 74..80 while the ribbon bar is 81 px tall: 3 to 7 px overlap (4 panels on Part, 1 on Assembly, 2 to 3 on Engineering);
- at 1280x720 the Assembly panel ran under the page bar (612 px tall, 604 available);
- Part: 9 to 10 labels under 12 px (TIMELINE, Suppress, Delete step, the warning strip, the ribbon captions at 10 px);
- 20 + tools in a single ribbon row, with the rarer ones under captions; no icon-per-function, no grouping by task on a wide screen;
- the first window was 1600x900 whatever the screen (project.godot), unclamped.

## After
See the table in `docs/UIEXP_DESIGN.md`. Overlaps 0 at all 12 screen-sizes, outside 0, Part fonts < 12 px: 1 at >= 1600 (the ribbon caption, shared with every page), 5 to 6 at 1366 / 1280.
