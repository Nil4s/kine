# CH16 feedback: Sony a7 / ILCE-7 class camera, separate Parts, electronics and assembly movie

Lane `w4-ch16`. Specification: `docs/CH16_BRIEF.md`; every source/status: `docs/CH16_REFERENCE.md`; bars committed before the first run in `tests/ch16_test.gd` (`c036f050`). Model/test/artefact commit: **`b88ca340`**. The feedback/tool-log commit follows this document.

## 1. Result

Final command, run with `CH16_PUBLISH=1` for the committed pictures:

`WT_MAX=8 bash /c/Users/Nick/tools/kine_workers/wtest.sh ch16 easypart peasy3 freestart`

**ch16 32 ok / 0 fail / 0 script errors; easypart 73/0; peasy3 23/0; freestart 14/0.** Logs: `C:/Temp/claude/w4-ch16/w6`.

| bar | result | planted control |
|---|---|---|
| 1 dimensions and mass | **ok**: actual CAD envelope 126.9 x 94.4 x 54.8 mm maximum, shell depth 48.2 mm (Sony: 126.9 x 94.4 x 48.2, 54.8 maximum). Exact-solid loaded mass **448.288 g**, 5.425% below Sony's 474 g; 58 Parts, 29 priced screws. BOM USD 718.79; cheapest alternatives USD 647.33 | **ok**: scaling every feature and pose 2x gives 253.8 x 188.8 x 109.6 mm and is caught |
| 2 mount | **ok**: 18.000000 mm datum; sensor 35.8 x 23.9 mm; 46.1 mm throat, minimum radial cone margin 1.527628 mm; sensor and curtains inside | **ok**: 25 mm flange is caught |
| 3 electronics | **ok**: 7.2 x 1.020 = 7.344 Wh; 340 CIPA shots -> 0.0216 Wh = 77.76 J/shot; loads 4.60 W, input 5.111111 W <= 8 W, 12 s duty = 61.333333 J < 77.76 J; every IC has power and signal | **ok**: omitting the core regulator leaves its 1.10 W load in the sum and fails supply/connectivity |
| 4 fit | **ok**: all 58 Parts build; 857 exact solid pairs after the box prefilter, no overlap over 0.001 mm3; no press-fit exception | **ok**: PCB moved 2 mm rearward hits the rear shell (419.20 mm3; also the grip in the final closed shell) |
| 5 build order/movie | **ok**: AssemblyStage supports 58/58 with no collisions; 12 changing frames in six ordered stages; MP4 written; section 7967 cap pixels vs closed 0 | **ok**: shells before sensor is rejected by the explicit order check |
| 6 hand arithmetic | **ok**: nominal envelope, flange, sensor, corner/throat radii, energy, CIPA energy, rails and BOM sum all agree to 1e-9 relative | **ok**: 25 mm flange and a dropped rail differ |

Design versus the a7: published envelope matched by construction; loaded mass 448.288 g versus 474 g; mount 18.0 mm and sensor 35.8 x 23.9 mm matched; NP-FW50 solid is about 42 g, 7.2 V and 1020 mAh, 7.344 Wh by hand versus Sony's rounded 7.3 Wh label; CIPA comparison is 340 shots and 77.76 J/shot. This is a block-level assembly, not a claim that the hidden Sony envelopes or rail loads have been measured.

Pictures, all LOOKED at from fresh filenames (the reader caches paths):

- `docs/ch16/build/sheet.png`: all 12 frames; each individual frame was also inspected.
- `docs/ch16/build/CH16_Sony_a7_ILCE-7_class_camera.mp4`: staged movie.
- `docs/ch16/section_cut/frame_0000.png` and `section_closed/frame_0000.png`.
- `docs/ch16/ch16_sheet_blueprint.png` / `ch16_blueprint.svg` and `ch16_sheet_electronics.png` / `ch16_electronics.svg`.
- `docs/ch16/ch16_bom.csv` and `docs/ch16/tool_calls.csv`.

## 2. Engineering level reached

| discipline | level | evidence | next level needs |
|---|---|---|---|
| mechanical / packaging | **L2-L3** | SEEN envelope, mount, sensor and teardown layout; separate exact solids; real-scale fit checks; planted PCB clash; assumed hidden envelopes clearly flagged | real service drawings and measured component envelopes, bayonet geometry, screw-head/thread geometry, GD&T and a mount/sensor shim stack-up; no ISO fit claim is made |
| optical / sensor alignment | **L2** | 18 mm datum and full-frame corner-cone clearance by closed form; section drawing | lens prescription and ray tracing, mount tolerances, filter-stack optical path and focus calibration; the simple cone is not a lens simulation |
| electrical / power | **L3 for arithmetic, L2 for circuit design** | battery/CIPA hand energy, five rail budgets, connectivity controls and a generated power/signal sheet | measured Sony rail voltages, transient/load profiles, regulator efficiency curves, battery discharge/CIPA duty measurement, pin-level schematic, EMC and thermal verification; all rails/loads here are ASSUMED |
| electronics / signal integrity | **L1-L2** | named image/data/control paths and block ICs | actual BIONZ X pinout, MIPI/LVDS lane rates, impedances, timing, DDR layout and USB/HDMI/RF validation |
| thermal | **L1-L2** | teardown-informed copper spreader and exact mass, no thermal calculation | measured power map, contact resistances, transient FEA and shell temperatures |
| manufacturing / BOM | **L2-L3** | exact-solid mass by material, 29 counted fasteners, sourced/dated prices, cheapest alternatives | supplier quotations, real replacement-part numbers, process costs and interchangeability checks; module prices and alternatives are estimates only |
| engineering drawings | **L2** | titled 1:2 front/top/section and NTS electrical sheet generated from model constants | solid-projected Assembly section geometry, toleranced detail drawings and connector/flex pin tables |

## 3. What Kine lacked

The CH15/CH14 tools and section 5's list were read first. AssemblyStage, AssemblyRender, SectionLook, AssemblyBom, KCad and Blueprint were reused; no new grab loop or BOM was written.

| # | needed | exists today | workaround | cost | proposed feature |
|---|---|---|---|---|---|
| 1 | dimensioned front/top/section Blueprint of an arbitrary Assembly | `blueprint.gd` draws Building records; CH15 has private entity helpers | `ch16_draw.gd` lays out model-derived orthographic blocks and dimensions | about 105 lines | Assembly -> Blueprint front/top/section projection with public dimension/title-block calls |
| 2 | electronic power/signal schematic and budget | no schematic editor; CH15's SVG pattern only | `ch16_electronics.gd` plus drawing code | about 65 model lines + 75 drawing lines | a schematic layer with rails, loads, signals and connectivity/budget checks |
| 3 | optical mount datum and full-frame cone check | Part measure/SectionLook, no camera-mount tool | exact datum fields and closed-form GDScript | about 25 lines | mount/sensor datums, register-distance stack-up and cone-clearance measurement |
| 4 | scripted assembly clash report without copying setup code | KCad.overlap_volume/distance and AssemblyStage.check exist | `ch16_parts.gd clashes()` adds an all-pairs AABB prefilter and named report | about 45 lines | one Assembly `check_fit()` call returning every pair and volume |
| 5 | double-precision numeric vectors for exact hand bars | GDScript scalars are doubles; Vector2/Vector3 are float32 (known G4) | exact sensor/nominal values returned as Dictionaries; vectors used only for 2% envelope checks | two failed checks, small code change | PackedFloat64Array/double vector value types or scalar measurement APIs |
| 6 | material colour selection that cannot alias SectionLook cap colours | SectionLook chooses cap colours without knowing other views | copper was darkened after the closed view produced 39 false cap-like pixels | one run | shared semantic cap-colour detection rather than pixel RGB matching |
| 7 | discoverable scripted-render host requirement | AssemblyRender correctly requires `host.is_inside_tree()` | two `await process_frame` calls at test startup | one failed movie run | document this in AssemblyRender's header/example, or return a startup-specific hint |

## 4. What looks wrong after LOOKING

- The camera is recognisably a7-class but very blocky: the prism is rectangular, the grip has no sculpted finger contour, the mount has no bayonet lugs, and buttons/ports are simple blocks. The final closed view is much better after closing the grip/top seam; an early version exposed a red internal heat spreader there.
- The contact sheet's drop-in animation is clear, but stage 4 is visually crowded and the large LCD/EVF blocks obscure the board stack until they land. The small screw shower in the last stage is legible as a sequence device, not as a realistic screwdriver operation.
- The section shows the interior and cap faces, but similarly sized coloured slabs do not visually distinguish the two curtain leaves well; the main PCB/spreader dominates. The cut is at Z=-26 mm and is a render section, not a solid-projected drawing.
- Blueprint: the optical section is necessarily narrow at a uniform 1:2. The sensor width label still touches the mount outline and leader fans cross the stack; all values are readable, but this is not fabrication-drawing quality. Front and top views carry large empty sheet areas.
- Electronics: power and signal are readable, but the repeated destination blocks are wide and the tiny notes are not suitable for print without zooming. It is a block diagram, not a pin-level schematic.

## 5. What was changed after seeing results

No bar was loosened and no planted control was removed. The test was committed before the first model run. Harness fixes only preserved/strengthened the original checks: exact scalar Dictionaries replaced float32 Vectors for the already-declared 1e-9 hand bar; the render host awaited scene-tree entry; cut and closed PNGs were given separate directories so the closed frame no longer overwrote the cut; and the render failure reason was printed.

Model changes after failed checks/pictures: closed real clashes around the sensor flex/carrier, chassis, heat spreader, PCB/grip and screw holes; increased realistic chassis/spreader volume to bring mass from 327.749 g to 448.288 g; closed the grip's upper shell seam; darkened copper so the uncut view has zero cap-colour false positives; shortened the electronics title and moved notes out of its title block; separated blueprint leaders and the flange/note labels. The section criterion remained `cp > 20 and wp == 0`.

## A. The five hardest steps

1. **Hidden packaging without overlaps.** A real-scale 126.9 mm body with 58 separate Parts made small wall/flex/screw interactions dominate the work. Exact pair reports were essential. Cheaper: an Assembly fit checker plus named clearance/pocket constraints linked to the Part that creates the opening.
2. **Honest mass from solids.** The first plausible shell/chassis was 30.9% light; a hidden correction line would have been dishonest. Chassis and heat-spreader geometry had to carry the missing material. Cheaper: live mass-by-part and target-mass decomposition while editing dimensions.
3. **Exact arithmetic across Godot's float32 Vectors.** Scalar doubles passed while the same sensor values in Vector2 failed 1e-9. Cheaper: double-precision measurement values from Part/Assembly, documented once at the API boundary.
4. **Useful drawings without an Assembly blueprint/schematic tool.** Reusing CH15's private entities was faster than inventing SVG, but leader placement and title-block collisions still took iterations. Cheaper: public sheet layout helpers, automatic label placement and solid-projected Assembly sections.
5. **Rendering reliable evidence.** Scene-tree startup, same-path image overwrites and cap-colour aliasing each produced a misleading result before the bars went green. Cheaper: a test-host helper, unique render output names by default and semantic interior masks in AssemblyRender.

## B. Tool-call cost log

`docs/ch16/tool_calls.csv` has one row per tool call, including failed shell invocations, research, commits, test runs and image reads. `output_bytes` is the returned text/tool-result size (image rows record the short acknowledgement, not the visual token cost; the lead's real token join is authoritative). Four file re-reads were needed after the first read: `assembly_stage.gd`, `ch15_test.gd`, `g33stage_test.gd`, and `tools/run_all.sh`; later log/picture reads were new files or fresh image names. The largest avoidable cost was the unfiltered `git status --short` after Godot generated `.uid` files; none was staged.

## C. App usage

| Kine feature | use in the final model/test | where GDScript filled a gap |
|---|---|---|
| Part prim/appear/cut steps | 30 distinct record types, 58 placed instances; boxes, cylinders, tubes and cuts | `ch16_parts.gd` parametric record factories and camera-specific pocket layout |
| Assembly | one Assembly, six-stage record, exact datums and hidden hanger declarations | assembly/stage construction and planted pose/scale controls |
| joints / AssemblyMotion drives | **0**: this is a static build sequence, not a mechanism animation | none; no fake hinge motion was needed |
| AssemblyStage | one `check`, six stages, 2 fps, 40 mm drop, three `video` calls | explicit semantic stage-order check (shells cannot precede sensor) |
| AssemblyRender + SectionLook | 12 movie frames + contact sheet + MP4; one cut and one closed frame; no custom grab loop | pixel-difference/cap-pixel assertions only |
| AssemblyBom | two mass evaluations, one CSV, one cheapest view; 29 screws priced | camera material/item entries and reference comparison, not a replacement BOM |
| KCad | 857 exact overlap pairs after AABB prefilter in the final fit check; stage tool makes its own calls | all-pairs report and analytic throat/datum helpers |
| Blueprint / SVG / BlueprintView | two A3 sheets, two SVGs, two PNGs, title blocks and dimensions | Assembly orthographic layout and electronics schematic because no matching app tool exists |
| automated tests | 32 final checks including every planted control and an end-of-bars guard | camera-specific engineering assertions |
