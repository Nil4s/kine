# G30DRAW feedback: Assembly drawings and rated schematics (G30 / G31)

Lane `w4-g30draw`. Bars were committed before the first run in `737751f5`; the first implementation was `0d94fcbd`. The final regression/documentation commit follows this document.

## 1. Result

Final blocking command:

`WT_MAX=8 bash /c/Users/Nick/tools/kine_workers/wtest.sh g30draw ch16 ch15 g7time g33stage easypart peasy3 freestart`

**8/8 suites PASS, 264 checks, 0 failures, 0 script errors.** g30draw **23/0**; ch16 32/0; ch15 44/0; g7time 27/0; g33stage 28/0; easypart 73/0; peasy3 23/0; freestart 14/0. Logs: `C:/Temp/claude/w4-g30draw/w8`.

| bar | result | planted control |
|---|---|---|
| a model dimensions + labels | **ok (3):** hand 70 x 60 x 30 mm; sheet **70.000000969 x 60.000000969 x 30.000000000 mm**, relative error < 1e-6. Plan/front/section and all three part names present | **ok:** Tower moved +10 mm prints **80.000 mm**, not 70.000 mm |
| b solid section | **ok (2):** enclosed core at the SectionLook plane gives **16** cut-edge SVG entities; closed front gives **0** | **ok:** closed view has no section-cut evidence |
| c CH16 / CH15 reproduction | **ok (7):** CH16 **126.900008 x 94.400009 x 54.799998 mm** vs 126.9 x 94.4 x 54.8; BOM mass **448.288 g**; CH15 all **15 bus voltages + 8 transformer MVA**; CH16 drawing, CH16 electronics and CH15 one-line all SVG+PNG | **ok:** removing MT's MVA prints `MISSING RATING: MT` on the sheet |
| d connectivity | **ok (4):** generic power/signal and every adapted CH16 IC/regulator connected; every wire endpoint exists | **ok (2 controls):** unknown endpoint reported; disconnected CPU reports `NO POWER: CPU` on the sheet |
| e file validity | **ok (3):** both SVGs re-parse with element-stack validation; both PNGs written | **ok:** mismatched XML tags rejected |
| f UI + compatibility | **ok (4):** real Drawing and Schematic buttons export SVG+PNG; all **5 old Assembly records** save back unchanged | **ok:** adding optional `wires` does not compare equal |

What the user can do: in an Assembly choose **Export → Sheets → Drawing** for a titled plan/front/section SVG+PNG, or **Schematic** for a rated power/signal SVG+PNG. Drawing dimensions and mass come from the model. Schematic parts optionally carry `v`/`kv`, `mva`, `w`, `rail`, `kind`, `unit`, `powered` on `rec`; Assembly `wires` is `[{a,b,kind,label}]`. Old records need no new fields.

## 2. Engineering level reached

| discipline | level | evidence | next level needs |
|---|---|---|---|
| engineering drawing | **L2** | posed OCCT B-rep edge projection; exact-solid double bounds; model-following dimensions and BOM mass; real section cut | hidden-line removal, true tangent/ellipse projection for every curve type, hatch assemblies, tolerances/GD&T, detail views and fabrication title-block metadata |
| electrical / schematic | **L2** | rated records, IEC-ish bus/transformer/breaker/generator symbols, power/signal topology, source-BFS layers and on-sheet connectivity/rating diagnostics | actual pin/terminal model, net directions and bidirectional semantics, wire-number editing, electromechanical symbols, design-rule and load-flow checks |

This closes the hand-written-SVG gap; it does not claim a professional CAD drafting or pin-level schematic editor.

## 3. What Kine lacked

| # | needed | exists now | old workaround / cost | result |
|---|---|---|---|---|
| G30 | dimensioned drawing and section of any Assembly | `assembly_draw.gd`; Assembly Export > Sheets > Drawing | CH15 site/section and CH16 `ch16_draw.gd` (about 105 lines), able to drift | shared exact-solid projection + dimensions; no Easy Part row added |
| G31 | electrical one-line / schematic from records | `AssemblyDraw.schematic_sheet`, `validate_schematic`; Assembly Export > Sheets > Schematic | CH15 private SVG helpers; CH16 about 75 drawing lines | shared rated blocks, IEC-ish symbols, layered wires and diagnostics |

## 4. What looks wrong after LOOKING

Fresh copies were inspected (the image reader caches paths): `g30draw_drawing_look01.png`, `g30draw_schematic_look01.png`, `ui_drawing_look03.png`, `ch16_assembly_drawing_look02.png`, `ch15_assembly_oneline_look04.png`, `ch16_assembly_electronics_look04.png`, all under `C:/Temp/claude/g30draw`.

- The fixture's views, labels, dimensions and title block are legible; the UI exposes both actions and confirms the export.
- CH16 is recognisably the camera and its dimensions/mass agree, but all B-rep edges are drawn, including hidden/internal edges. It is intentionally dense, not hidden-line-removal drafting.
- CH15's final thin orthogonal wiring is substantially clearer than the first cyclic-layout result. Ratings are present and readable with SVG zoom; ties still make a busy sheet.
- CH16 electronics reads as a power tree plus signal fan. At 2 px/mm some signal labels are crowded; use the SVG or a higher `ppm`. It remains a block diagram, not a pin-level schematic.

## 5. What was changed after seeing results

No bar was loosened and no planted control was removed. Harness fixes were a type annotation, moving the Lug so its actual hand-computed height was the declared 60 mm, and strengthening XML validation with an explicit element stack. Three reproduction PNG checks were added.

Implementation fixes after failures/pictures: Godot-compatible cut-box rotation; string conversion of numeric SVG data/rating values; per-field units so MVA cannot inherit kV; source-based BFS instead of cyclic longest-path relaxation; wrapped block rows; thin orthogonal wires; correct mm title-block wording; a shorter parts list to keep the export actions/status visible. The 1e-6 dimension bar, all model comparisons and all connectivity requirements stayed unchanged.
