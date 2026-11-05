# CH16 brief: a full-frame mirrorless camera (Sony a7 / ILCE-7 class), every part separate, its electronics, and an assembly movie

Nick (11-05): build a camera like an Alpha 7 inside Kine, all parts separated, with the assembly movie and the needed electronics. Then give feedback on what was hard, the token cost per tool call and overall app usage, so we can make the app cheaper for AI.

**Reference:** the original Sony a7 (ILCE-7, 2013): 24.3 MP full-frame CMOS (35.8 x 23.9 mm), E-mount (18 mm flange focal distance), BIONZ X, 2.36 M-dot OLED EVF, 3.0 in 921 k-dot tilting LCD, NP-FW50 battery, no IBIS (that is the a7 II). Use public sources (Sony spec sheets, the E-mount specification, teardowns such as iFixit, DPReview). Mark every number SEEN / MEMORY / ASSUMED as in CH14/CH15. Where the a7's own value is not public, use a cited same-class value and say so.

## Deliverables
1. **Every part separate**, as Kine Parts in one Assembly, at real scale:
   - front and rear body shells, top plate, grip, bottom plate
   - E-mount ring + flange, sensor assembly (sensor + cover glass + carrier), sensor flex
   - shutter mechanism (frame + two curtains, block level)
   - main PCB (BIONZ X, DRAM, power ICs as block components), EVF module, LCD + hinge, rear control cluster, top dials and shutter button, hot shoe
   - battery NP-FW50 + battery door, SD card + slot, USB/HDMI port block, Wi-Fi/NFC antenna
   - fasteners as counted items (the BOM must price them)
2. **Assembly movie:** the camera builds up in stages (chassis -> sensor/shutter -> boards -> EVF/LCD -> shells -> doors), using AssemblyStage + AssemblyRender (#205/#208). Include a section-cut view that shows the sensor, shutter and board stack. Contact sheet + LOOK.
3. **Electronics:** a power/signal block diagram (SVG + sheet with a title block, as CH15 did): battery 7.2 V -> protection -> regulators (rails with their voltages and estimated loads) -> BIONZ X / sensor / EVF / LCD / shutter drivers / SD / USB / Wi-Fi. Include the signal paths (sensor -> BIONZ X -> DRAM/SD/EVF/LCD/HDMI).
4. **Blueprint:** dimensioned front, top and section views with flange focal distance and sensor size called out.
5. **BOM:** via AssemblyBom (#206), mass from the CAD solids, priced bought items, total mass vs the cited 474 g with battery, and the cheapest-alternatives view.
6. **Feedback** per docs/CHALLENGE_FEEDBACK.md, PLUS the two extra sections below.

## Bars (committed BEFORE their first run; each with a planted control)
1. **Dimensions:** body W/H/D within 2% of the cited 126.9 x 94.4 x 48.2 mm (or the measured value you cite); total modelled mass within 10% of 474 g with battery. PLANTED: a 2x scale model is caught.
2. **Mount:** flange focal distance 18.0 mm (mount face to sensor plane) to 1e-6 mm; sensor 35.8 x 23.9 mm; mount throat clears the sensor's full-frame cone. PLANTED: 25 mm flange distance is caught.
3. **Electronics:** battery energy E = V x Ah by hand; CIPA shot count -> energy per shot; the sum of the estimated rail loads is inside the battery/regulator budget; every IC in the diagram has at least one power and one signal connection. PLANTED: one regulator missing from the budget is caught.
4. **Fit:** no two parts overlap beyond contact (KCad.overlap_volume over the Assembly; distance prefilter allowed) except declared press fits; sensor and shutter sit inside the mount's throat. PLANTED: a PCB moved 2 mm into the shell is caught.
5. **Build order:** every stage's parts supported (AssemblyStage.check), the video's frames show the stages in order, and the section frame shows the interior. PLANTED: the shells before the sensor is caught.
6. **Hand arithmetic:** every number in bars 1-3 equals its hand value to 1e-9 relative.

## Extra feedback required (Nick's measurement request)
A. **What was hard:** the 5 hardest steps, why, and what in Kine would have made each one cheaper.
B. **Tool-call cost log:** keep `docs/ch16/tool_calls.csv` with one row per tool call you make: `n, tool, target, purpose, output_bytes, needed_in_hindsight (y/n), note`. The lead will join this with the real token cost of the session and report cost per tool call. Also log how many times you re-read a file you had already read.
C. **App usage:** which Kine features you used (Part steps, Assembly, joints, stages, render, BOM, blueprint/SVG, KCad calls), how many times each, and every place you wrote GDScript because the app had no tool (that goes in the gap ledger too).

## Rules
- Reuse the app's new tools: AssemblyStage/AssemblyRender for the movie, AssemblyBom for cost, SectionLook for the cut, ch15_draw.gd for the SVG sheets. Do NOT write another grab loop or BOM.
- Test with `WT_MAX=8 bash /c/Users/Nick/tools/kine_workers/wtest.sh ch16 easypart peasy3 freestart` (one blocking command per run, no polling).
- `git add` by name only; never push/merge/PR (the lead does). No MIT or AGPL code. Never end your turn waiting.
- Stop and report honestly when a bar can't be met; never loosen one.
