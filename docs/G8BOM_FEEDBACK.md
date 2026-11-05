# G8BOM: a bill of materials for an Assembly (gap G8)

Branch `w4-g8bom`. Code: `scripts/build/assembly_bom.gd` (AssemblyBom, the engine), `scripts/build/assembly_bom_ui.gd` (the panel), `data/prices.json` (the price table), `scripts/build/ch14_bom.gd` `assembly()` / `design_of()` / `check_asm()` (the CH14 arm as an Assembly). Test: `tests/g8bom_test.gd` (bars written and committed in 5a531774 before the first run).

**What you can do.** Open an Assembly (BUILD > New assembly, or Open) and press **BOM** beside Check motion. The panel on the left shows one line per group of identical parts and one per bought extra. Each line has the part, the qty, the material or item, the mass (the part's exact solid x density x fill), the cost and a **Cheaper** button. Below the lines are the totals (mass, cost, part count), the cheapest whole design that still passes the assembly's named check with **Use the cheapest design**, then **CSV**, **Copy** and **Close**.

- The Part, Qty, Mass and Cost headers sort the table. Press a header again to reverse the order.
- A made part's material is picked in its own line.
- Every change is ONE undo step, and Ctrl+Z takes it back.
- Opening, sorting and closing the panel never write to the record.

**The record.** Everything is optional:
- A Part can carry `"bom": {material | buy (+ qty), fill, alt, need {sigma_MPa, E_MPa, max_mass_kg}, role, included, name}`.
- The Assembly can carry `bom_extra` (bought things with no solid, like a hose or glue) and `bom_check` (a named whole-design check; `ch14_works` is the only one so far).

Prices are in `data/prices.json`. Each entry has a `source` and a `date`, and an entry nobody quoted says ASSUMED.

## 1. Result

`WT_MAX=8 wtest.sh g8bom ch14 g7time g2loop g1motion easypart peasy3 freestart s213 c15` (logs C:/Temp/claude/w4-g8bom/w4):
- PASS: ch14 60/0, g7time 27/0, g2loop 24/0, g1motion 22/0, easypart 73/0, peasy3 23/0, freestart 14/0, s213 27/0, c15 28/0.
- **g8bom 18 ok / 1 FAIL** (bar a, below).

| bar | result | numbers |
|---|---|---|
| a MASS (1e-9 rel) | **FAIL** | steel box 8.000002 cm3 (hand 8), Al rod 2.356194 (hand 2.356194), PLA tube 5.654865 (hand 5.654867): worst 2.78e-7. Mass = the solid's volume x density holds exactly; the solid itself is not the drawn size, see below |
| a CONTROL density 1.24 "kg/m3" | caught | validate names `materials pla: density 1.24 kg/m3 ... (a g/cm3 number?)`; the mass is 1000x low |
| b GROUP | ok | 4 identical M4 bolts = 1 line, qty 4, 9.697 g (4 x 0.3088 cm3 x 7850), 0.32 USD |
| b CONTROL one bolt 1 mm longer | caught | 2 lines, counts [1, 3] |
| c CH14 reproduced | ok | every group except the boom equals CH14's own line to 1e-9 USD. New total 30.6132 = CH14 29.3749 (29.37) + 1.2383, the boom difference |
| c cheaper design | ok | 26.2695 USD (saves 4.34) <= CH14's own search 26.4909; CH14's working bars pass on the applied copy; every line's need is met |
| c CONTROL all tube soft PVC | caught | CH14 bars fail (6 place 51.2 mm); the runs line's need refuses it (E 10 < 50 MPa) |
| d CSV | ok | 18 rows + TOTAL re-read by the test's own parser: rows 30.613207, TOTAL 30.613208, bom() 30.613208 (inside (n+1) x 0.5e-6); mass 2.860191959 vs 2.860191958 kg |
| d CONTROL one line +0.01 | caught | rows 30.623207 vs TOTAL 30.613208 |
| e SOURCES | ok | 19 entries, all with a source and a date (19 ASSUMED, 0 cited); validate is clean |
| e CONTROL source erased + date gone | caught | exactly those two problems |
| f UI | ok | 18 rows for 18 lines; Cost sorts up, then down; Part sorts by name. The upper arm's Cheaper button puts in pine: 1 undo step, total 30.6132 -> 28.9977, which is the 1.6155 shown (off by 7e-16). Copy puts bom()'s CSV on the clipboard. Ctrl+Z gives back the identical record |
| f CONTROL | caught | after the change the record differs |
| g OLD | ok | old_assembly, drive_199 (#199), joint_204 (#204) and anim_205 (#205, written by the #205 code before this branch) open, the BOM opens, sorts and closes, and each saves back equal. They have no "bom" fields, so every line says "no material: not priced" |
| g CONTROL | caught | the #205 record with one material applied is not equal |

**Bar a is red, and the bar was not changed.** The BOM reports the solid exactly: `KCad.volume` is Gauss-Kronrod at 1e-9. The solid is the wrong size because `part_prim.gd` builds every primitive from float32 numbers:
- the box uses `Vector3(w, h, d) * MM`;
- the cylinder and tube profiles are `PackedVector2Array`.

So the 40 x 20 x 10 mm box the kernel holds is 8.0000017 cm3. A probe gave the same 8.000001698732 cm3 from `KCad.box(0.04, 0.02, 0.01)` fed from a float32 Vector3, while doubles give exactly 8.0. This is gap **G4** again, now seen in mass. For a BOM, 3e-7 is nothing (a millionth of a cent), but the bar measures it, and it stays red until prims are built in doubles. The box can use `KCad.box(float, float, float)`. Cylinders and tubes need a float64 profile in the kernel, or `KCad.cylinder` plus booleans, and that changes their topology. Neither was done here: it touches every Part.

**How CH14 reproduces, line by line** (USD; CH14 = `ch14_bom.bom(d, vols)`, new = `AssemblyBom.bom(ch14_bom.assembly(d))`):

| group | CH14 | new | why |
|---|---|---|---|
| syringes (2 x 5, 2 x 10, 6 x 20 mL) | 3.80 | 3.80 | bought items; the shoulder and elbow masters are their own line (they may be 10 mL) |
| tubes (3.25 m nylon-12 + 1.35 m PU) | 7.47 | 7.47 | bought extras, metres from `hose_m(d)` |
| printed parts (6, 45 pct of the solid) | 7.0240 | 7.0240 | the same records and volumes, fill 0.45 |
| base set + console | 7.00 | 7.00 | the set is bought; the console is "included" |
| dowels 6, pads, sundries | 1.80 | 1.80 | bought |
| **boom links** | **2.2809** | **3.5192** | CH14 priced a 30 mm square PLA+ section x (240 + 220) mm = 0.1037 kg. The CAD links (25 mm tube 1.6 wall + cheeks, lugs, trunnions) are 0.1600 kg: +0.0563 kg x 22 = **+1.2383** |
| total | 29.3749 | 30.6132 | = 29.3749 + 1.2383 |

**The cheaper design.** It is the same as CH14's own pick: 10 mL masters on the shoulder and elbow, plywood links, PU tube on the runs. It costs 26.27 against CH14's 26.49, because the new BOM weighs the plywood links from the CAD solid (0.084 kg, 1.43 USD) instead of CH14's 3 mm-wall section (0.097 kg, 1.65 USD).

The search tried 7 of the 36 combinations, cheapest first:
- 3 boom choices per link (cardboard fails the link's `sigma_MPa >= 45`);
- 2 tubes (PVC fails `E_MPa >= 50`);
- 2 master sizes.

Each one was put through CH14's `works()` (bars 2b, 4, 5, 6). "Cheaper line by line" (5.41 saved) is the sum of each line's own best with only its own needs. It is not a design that works: pine links with PU tube and 20 mL masters fail CH14 bar 6 (17.1 mm against 16.9). That is why the whole-design line is the one with a Use button.

## 2. Engineering level reached

- **Cost and mass estimating: L3.**
  - The masses come from the exact solids, and the density units are checked.
  - Prices are cited per entry, but all 19 are ASSUMED: nobody fetched a quote.
  - Identical parts are grouped by record.
  - The cheaper search is exhaustive over the allowed choices and checked against a first-principles whole-design model (CH14's).
- **For L4:** real supplier quotes with dates; quantity breaks (a 10-pack, not 0.25 per syringe); filament mass from a slicer, not 45 pct of the solid; per-body materials (below); scrap and offcut rules for sheet and bar stock, the CH4 cut list's job; and labour and machine time.

## 3. What Kine lacked

| needed | exists today | workaround | cost | proposed feature |
|---|---|---|---|---|
| a BOM of an Assembly (G8) | CH14's ch14_bom.gd (one design, hard-coded lines), CH4's CutList (wood boards, BRL), the p057 weight chips (one Part, 3 densities) | none: this branch is the feature | 1 engine (401 lines), 1 panel (268), 1 data file, 108 lines in ch14_bom.gd | done |
| solids at the size drawn (G4) | primitives are built from float32 Vector3 / Vector2 | none: bar a reports it | the bar is red at 2.8e-7 | build box / cylinder / tube from doubles in part_prim.gd (box: KCad.box with floats; round ones: a float64 profile in KineCAD) |
| a material per BODY, not per part (new, G44) | one "bom" per Part record | CH14's jaw prices its TPU pad as PLA+; the turntable's steel shaft and the gripper's steel idler are printed PLA+ in both BOMs (CH14 did the same, so the reproduction keeps it) | about 1 cm3 mispriced per part; it could not be done | "material" on the appear step (per body), and the BOM sums bodies |
| a whole-design check written as data | the check is a GDScript function named in CHECKS | ch14_bom.check_asm maps "role" tags back to a ch14_arm design | about 75 of those 108 lines | a "requirements" list on the Assembly (min torque margin, max error) that the CH10/CH14 solvers evaluate |
| one place for prices | CutList's user://kine_prices.json (BRL, 3 numbers), CH14's PRICE, now data/prices.json (USD) | the new file holds the CH14 prices | 3 price tables | CutList reads data/prices.json (+ the user's own overrides) and a currency setting |
| a bought part's real shape | the CH14 syringe masters may be 10 mL, but the record still draws a 20 mL barrel | the line's name says "drawn as 20 mL" | the picture lies after Use | a "buy" alternative that names its own Part record, so Use swaps the shape too |

## 4. What looks wrong (after looking at bom_open.png and bom_cheaper.png, C:/Temp/claude/g8bom)

- The table reads well at 1280 x 720, but long part names are cut ("Turntable, shaft, tower and s..."). The full name and the price source are in the line's hover text. A narrower name column or a two-line row would show more.
- The rows with a material picker are taller than the plain rows, so the table's rhythm is uneven.
- The Assembly panel on the right ends level with the bottom bar when the status text runs to three lines. That was already so before this branch, made worse by one line by the BOM status. The "Parts" row is now one line (the double-click hint moved to each row's hover text), which gave that line back.
- "Mass -" on the pads and sundries is honest (no mass in the price table), but the total mass leaves them out without saying so.
- The overlay's part names show through to the right of the BOM panel, over the 3D view. This is the same as with Check motion.

## 5. What was changed after seeing results

No bar was changed. These were fixed in the test's mechanics:
- the a print used `%.2e`, which Godot's format does not support (now `sci()`);
- f's Cheaper button was below the scroll fold, so the test now scrolls to it, as a user would;
- f read the button after the click had freed it (`had_btn` is now taken before the click);
- the Windows clipboard returns CRLF (normalised before the compare).

In the code:
- the master-syringe line got its own name;
- a line with no known mass shows "-";
- the Parts label is shorter, so the BOM button fits.

Last commit: see `git log -1` on w4-g8bom.
