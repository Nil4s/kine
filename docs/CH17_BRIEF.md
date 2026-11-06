# CH17 brief: a 1 MGD conventional water treatment plant, layout and process, built through the MCP `--cad` route

Lane w4-eng2, 2026-11-05. Nick asked for the open engineering challenges to move forward on the cheap MCP route. This challenge is a process/industrial LAYOUT: the plant is modelled at block level as Kine Parts (concrete basins, pumps, steel pipe, a chemical building, an MCC), laid out to real clearance rules and a hydraulic design, and checked for overlaps, flow continuity, clearances and a BOM.

## Honesty about sources (read first)
No single plant's drawing set was read in this lane. The task asked for "public reference drawings"; that is NOT met. The plant is a criteria-derived layout (like CH16's block-level a7), sized by hand from the design rules below. Status words as in CH14/15: **SEEN** = the page was read in this lane (OSHA pages, fetched 2026-11-05), **MEMORY** = a handbook value as remembered, **ASSUMED** = my choice. The treatment design ranges are weak: the only search hits were a course handout (`https://people.sunypoly.edu/~barans/classes/ctc450/pdf/CTC%20450%20W_WW%20Standards.docx.pdf`, itself marked "not to be used for design") and study guides (`https://open-exam-prep.com/study-guides/fe-environmental/groundwater-water-treatment/water-treatment-sedimentation-filtration`); the Ten States Standards text could not be opened (utah justia page returned 403). So the process bars are consistency checks against typical ranges, and say so.

## Clearance standards (SEEN, osha.gov, 2026-11-05)
| rule | text | used for |
|---|---|---|
| 29 CFR 1910.36(g)(2) | "An exit access must be at least 28 inches (71.1 cm) wide at all points." https://www.osha.gov/laws-regs/regulations/standardnumber/1910/1910.36 | every walkway and the exit route: width >= 711.2 mm |
| 1910.36(g)(1) | ceiling of an exit route >= 7 ft 6 in (2.3 m); projections not below 6 ft 8 in (2.0 m) | headroom envelopes >= 2300 mm |
| 1910.303(g)(1)(i)(B) | working space width = the width of the equipment or 762 mm (30 in), whichever is greater. https://www.osha.gov/laws-regs/regulations/standardnumber/1910/1910.303 | MCC working space width |
| 1910.303(g)(1) Table S-1 | depth 600 V or less, 151-600 V: 3.5 ft (1.07 m) for condition B (the table text was garbled in the fetch; 3.5 ft is the value it gave and the one I remember) | MCC working space depth >= 1066.8 mm |
| 1910.303(g)(1)(vi)(B) | headroom 1.98 m (6.5 ft), or the equipment height if taller | MCC working space height >= max(1980, equipment) |
| 1910.28(b)(1)(i) | protection where an unprotected edge is >= 4 ft (1.2 m) above a lower level | no walking surface >= 1.2 m above grade in this plant (all walkways are at grade) |
| 1910.25(c) | stairs 30-50 deg, width >= 22 in, riser <= 9.5 in, tread >= 9.5 in | NOT used: no stairs modelled (gap) |
Maintenance envelope round a pump: 900 mm each side in plan, motor top + 1000 mm above (ASSUMED; vendor manuals not read).

## The plant (all ASSUMED sizing unless a source is named)
Design flow Q = 1 MGD = 1e6 US gal/day x 0.003785411784 m3/gal = 3785.411784 m3/d = 0.043813 m3/s. Two raw-water pumps (duty + standby, staggered so each pump's maintenance envelope clears the other's line), a rapid-mix tank, a flocculation basin, a sedimentation basin, three rapid gravity filters, a clearwell, two high-service pumps to the site boundary, a chemical building (alum tank, MCC). Trains run along x (west to east), y up, z across. Walls 0.3 m, floors 0.4 m, steel pipe on grade at 0.8 m centre height.

| unit | inner size (m) | check |
|---|---|---|
| rapid mix | 1.0 (x) x 2.0 (z) x 1.2 water | detention V/Q <= 60 s (ASSUMED) |
| flocculation | 5.1 x 4.5 x 3.5 | detention 20-45 min (MEMORY) |
| sedimentation | 16 x 12 x 3.7 | surface overflow rate Q/A <= 25 m/d (ASSUMED, typical 20-40); detention >= 4 h (handout: > 4 h, or 2 h with approval) |
| filters (3) | 4.0 x 3.5 each | rate <= 8 gpm/ft2 (handout 2-8) with all in service; <= 6 gpm/ft2 with one out (study guide 2-6) |
| clearwell | 8 x 14 x 3.5 = 392 m3 | volume >= 300 m3 (ASSUMED) |
| pipes | DN250 (273.0 x 6.0 mm) raw, treated, distribution; DN200 (219.0 x 6.0 mm) sed-to-filter and filter-to-clearwell | velocity 0.3-2.5 m/s at the design flow of the line (ASSUMED) |
| pumps | box 1.0 (x) x 0.6 (z) x 0.8 (y) + motor cylinder r 0.25 x 0.6 | ports at x faces on the pipe axis |
| chemical building | outer 12 x 6.5 x 4.2, walls 0.3, hollow; alum tank r 1.5 x 3.0; MCC 2.0 x 0.6 x 2.3 | exit route 0.9 wide to the west door; MCC working space |

## Bars (committed in tests/ch17_test.gd BEFORE its first run; each has a PLANTED control that must fail)
1. **BUILD**: every Part record builds exactly one body, and its exact-solid volume equals the volume computed by hand from its prims (box, cylinder, tube; relative 1e-9). PLANTED: a record whose hand volume is off by one cut is caught.
2. **OVERLAP = 0**: every pair of plant parts (equipment, pipes, building) through KCad.overlap_volume in the test's own kernel (not the MCP's), < Part.HIT_VOL; the MCP `check_fit` result stored in the plant data agrees (0 overlapping pairs). PLANTED: a pipe pushed 100 mm into a filter wall is caught.
3. **FLOW CONTINUITY**: every connection joins two ports whose world positions agree within 0.5 mm, with opposite directions and equal bores; every pipe end is connected; a graph walk from the INTAKE reaches both distribution stubs, through each of the three filters. PLANTED: one pipe lifted 50 mm breaks the walk.
4. **PROCESS by hand**: the detentions, overflow rate, filter rates, velocities and clearwell volume of the table, from the plant's own geometry (read from the solids' bounds), within their ranges. PLANTED: a 12 m sedimentation basin and a DN80 raw line fail.
5. **CLEARANCES**: walkways >= 711.2 mm wide and >= 2300 mm high; the exit route likewise; the MCC working space >= 1066.8 mm deep, >= max(equipment width, 762) wide, >= max(1980, equipment height) high and in front of the MCC; each pump envelope >= 900 mm round it and motor top + 1000 above; every envelope free of solids other than the parts it names (exact kernel overlap). PLANTED: the alum tank moved into the exit route, a 600 mm walkway, a 800 mm working space.
6. **BOM**: mass = sum of (hand volume x density), cost = sum of mass x price, per line, to 1e-9 against the MCP `bom` stored in the plant data; line count = distinct parts. PLANTED: a dropped pipe line changes the total.
7. **SHEETS**: a plan drawing (AssemblyDraw) and a 3D frame (AssemblyRender) are written and LOOKED at (needs a window). PLANTED: none (pictures are read by eye and described in docs/CH17_FEEDBACK.md).

## Route
The plant data (records, assembly, ports, envelopes) is generated and driven by `tools/ch17_mcp.py` through `poser_mcp.py --cad`: one batch of `cad_part`, one `cad_asm`, `check_fit` (detail), envelope parts added/removed for the clearance check, `bom`. It writes `docs/ch17/plant.json` and `docs/ch17/mcp_log.json` (per call ms and bytes). `tests/ch17_test.gd` re-derives everything independently from that file in one Godot boot. Every fallback to GDScript is logged as an MCP gap in docs/CH17_FEEDBACK.md.
