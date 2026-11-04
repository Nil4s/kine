# CH13 feedback: single-cylinder engine (tests/ch13_test.gd, 84 ok, 0 fail)

Reference, sources, assumptions: docs/CH13_REFERENCE.md. Code: scripts/build/ch13_engine.gd (maths), ch13_parts.gd (seven Part records + posed assembly), ch13_scene.gd (3D scene + section). All GDScript (about 3000 closed-form samples; no native twin warranted).

## Fits (hole/shaft limits from the ISO tables in code, checked by hand in the test)
| fit | zones (um) | clearance min..max (um) | kind | hot (um) |
|---|---|---|---|---|
| pin in rod small end, 13 G6/h5 | +17/+6, 0/-8 | 6..25 | clearance | n/a |
| pin in piston boss, 13 JS6/h5 | +5.5/-5.5, 0/-8 | -5.5..+13.5 | transition | +10.6..+29.6 (Al boss 150 C, steel pin 130 C) |
| crank journal in bearing, 20 H7/f7 | +21/0, -20/-41 | 20..62 | clearance | not computed |
| piston in bore, 39 H7/e7 | +25/0, -50/-75 | 50..100 | clearance | +7.1..+57.1 (Al 4032 skirt 120 C, iron bore 100 C; closure 42.9) |
| crank pin in big end, 18 H7/f7 | +18/0, -16/-34 | 16..52 | clearance | not computed |

The code chose H7/e7 for the piston: the tightest candidate with hot minimum >= 5 um. The textbook H7/f7 goes to -17.9 um hot (planted control, flagged as seizing).

## Stack-up
- crank end-float 0.300 mm nominal: worst +-103.5 um (0.1965..0.4035 mm), RSS +-65.09 um; the 16 corners equal the worst case.
- deck clearance 0.500 mm nominal: worst +-119.5 um, RSS +-75.64 um.

## Torque against the cited engine (Honda C50 2007: 49.5 cc, 10:1, 2.5 kW at 7000 rpm, 3.8 N m at 5000 rpm)
Pressure curve (an input): n = 1.30, intake 0.85 bar, tau = 4.0 chosen before running, Wiebe burn from 20 deg BTDC over 50 deg: peak 47.0 bar at 374 deg; IMEP 8.70 bar (torque integral = pdV integral to 0.5 pct), Chen-Flynn FMEP 1.59 bar at 7000 rpm, BMEP 7.11 bar.
- 7000 rpm: 2.80 N m, 2.05 kW (82 pct of the 2.5 kW spec).
- 5000 rpm: 2.91 N m (77 pct of 3.8 N m).
Inside the 0.5x..1.5x sanity band; both are below the spec, and tau was not tuned. The spec's own BMEP at 5000 rpm is 9.6 bar, high for a 4-stroke 50 cc; the manufacturer's numbers may be generous. Reciprocating mass from the CAD volumes: 189.5 g (heavier than a real C50 piston set, because the piston is a simplified solid-crown design).

## 3D-print compensation (Grgic et al. 2023)
CAD at the mid-zone of the limits; 13 G6/h5 is finer than the IT9 the study demonstrated, so the prototype uses G9/h9: hole 13.0275, shaft 12.9785; with slicer HHE 0 the hole is drawn 13.2875 (+0.26). The printer model (hole prints 0.26 mm small without HHE) puts the compensated hole on 13.0275 (inside 13.006..13.049) and the uncompensated one on 12.7675 (outside; planted control).

## What the bars caught and what I changed after seeing results (all documented in git)
- before the first run: formula tolerance 1 -> 1.5 um (ISO rounds: d 18-30 formula 63.8 vs table 65, IT10 50-80 118.8 vs 120).
- after the first run: pose bars 1e-6 -> 1e-4 mm (Godot's Transform3D is single precision; the measured stroke error was 2e-6 mm); the frame-difference bar failed because the engine was too small in the picture: camera moved closer and the grab cropped (the 0.002 threshold itself unchanged).

## Looking at the pictures (docs/ch13/sheet_animation.png, docs/ch13/section.png; also C:/Temp/claude/ch13/)
Sheet: 12 frames, 60 deg apart, over two revolutions; row 2 is identical to row 1 (the periodicity bar, and visible). The crank pin swings round, the rod swings and the piston travels in the cylinder. Weaknesses seen: the piston at TDC hides behind the head and the see-through cylinder; the case and cylinder are drawn 30 pct opaque so the moving parts show. Section: every part has its own cap colour (case orange, liner green, piston pink, pin blue, rod teal, crank orange, journal purple, head brown); the head's plug bore and the rod's two eyes read clearly. The pin in its boss shows a hatch pattern: the cut faces of pin and boss are 4 um apart (z-fighting, not a defect of the geometry).

## Not done
- no CAD interference check between the mating parts (the clearances are checked as dimensions, the volumes as closed forms); no crank balance; Chen-Flynn coefficients, the 1/3 rod split, the 5 um hot criterion and the part temperatures are recalled or assumed (marked in the reference).
