# CH1e feedback: real fasteners on the CH1 house (tests/ch1e_test.gd 27 ok, ch10 26 ok)

Sources and every replaced value: docs/CH1e_REFERENCE.md. The house is now held together by 7772 modelled fasteners per the IRC nailing schedule and Simpson catalogue values, not glued members. The placement checks run in C++ (KineFastenerNative) with a GDScript twin.

## What is placed
- **Nails by schedule row:**
  - stud to plate 524
  - joist to plate 92
  - stud to stud 46
  - header built-up 26, header to stud 34
  - rafter to plate 34, rafter to ridge 34, rafter bearing 14, rafter sister 7
  - plate to plate 11, plate laps 6
  - wall L toenails 256 (8 x 32 vertical members)
  - sheathing edge/field nails on every full-height piece
- **Connectors:**
  - 34 H2.5A hurricane ties, one per rafter
  - 33 anchor bolts (1/2 in, embed >= 7 in, plate washers, max gap 68.75 in <= 72, ends 9 in, R403.1.6)
  - 20 HDU2 hold-downs at the shear-wall ends (h/b <= 3.5, doubled king + jack)

## Bars (all pass; planted controls fail)
- **S1-S5:** schedule counts, spacing (worst excess 0.00 mm), both ends of all 244 vertical members, bolts, ties, hold-downs.
- **F1:** no fastener floats, 0 of 7772. Worst head gap 0.00 mm, max tail 12.9 mm. CONTROL: a nail moved 20 mm is caught.
- **K:** capacities against hand arithmetic:
  - 4-8d toenail 112 / 240 lb
  - H2.5A 390.6 / 68.75 lb
  - 5 x 16d 295.6 / 704.8 lb
  - sheathing piece 2843.7 / 4125 lb
  - HDU2 1921.9 lb
  - anchor bolt 2369.8 / 1040 lb
- **P1:** half the sheathing nails gives 0.504 of the sheathing shear capacity.
- **P2:** the schedule bar passes the house and fails the planted one (13 failures, e.g. a 300 mm sheathing edge gap against the 158.75 mm limit).
- **R1, R2:** house_check's toenail value 134.4 lb is now sourced (UNVERIFIED flag gone); the reference names every replaced value.

## CH10 (the lead's red 1)
- **The fault:** a layout rafter sat 87 mm off its ceiling-joist node and never joined the frame, so CH10's sway period read a local mode (mass fraction 0.03, T 0.73 s).
- **Fix:** the rafter now snaps onto the joist axis.
- **New bar h:** every sway_period / damping mode must carry >= 0.5 effective mass. Code house: z 0.852, x 0.614. CONTROL: the unjoined house puts sway on a local mode (0.034, T 0.767 s), and bar h catches it.
- **e3 period:** 0.525 s against the 0.516 s before the rafters were added, 1.7 pct off.

## Fixes after the first fastener run
- F1 failed with 593 of 7809 floating: the fastener module read the pre-snap member file. It now uses one geometry source.
- Placement fixes:
  - the stand-off before the wood
  - corner 16d from the thin member
  - the gable-rafter seat range
  - layout heel toenails
  - front sheet slivers
  - the H2.5A flange on gable rafters
- No bar was edited.

## Suites
ch1e 27/0, ch10 26/0, ch1a 26/0, ch1b 49/0, easypart 73/0, peasy3 23/0, freestart 14/0. The native DLL was rebuilt for KineFastenerNative (its N0 bar).
