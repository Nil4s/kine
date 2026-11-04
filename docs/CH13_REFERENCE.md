# CH13 reference: a single-cylinder engine, tolerances, thermal fit, torque, print compensation

Written 2026-11-04 BEFORE any number was run. Sources were fetched online in this lane; anything recalled from memory is marked RECALLED.

## 1. The cited engine

Honda C50 Super Cub (2007), 4-stroke single cylinder, air cooled:
- bore x stroke 39 x 41.4 mm, 49.5 cc, compression ratio 10.0:1, max power 2.5 kW (3.4 hp) at 7000 rpm, max torque 3.8 N m at 5000 rpm.
  Source: https://www.motorcyclespecs.co.za/model/Honda/Honda_C50_Cub_07.html and https://www.moto-data.net/honda/c50-super-cub-2007 (the two agree).
  (Older C50 listings give 37 mm bore and 8.8:1; this lane uses the 2007 figures.)
- NOT in any source found, ASSUMED by me (design inputs, not Honda data): rod centre distance L = 80 mm, piston pin O.D. 13 mm,
  crank main journal O.D. 20 mm, crank pin O.D. 18 mm, piston height 40 mm, piston mass from the CAD volume (aluminium 2700 kg/m3).

## 2. Limits and fits (ISO 286-1:2010 / ISO 286-2)

- IT grades: i = 0.45 D^(1/3) + 0.001 D (um, D the geometric mean of the size range, mm); IT5 = 7i, IT6 = 10i, IT7 = 16i, IT8 = 25i, IT9 = 40i, IT10 = 64i. The standard's rounded table values are the data in code;
  the formula is the independent check (<= 1 um apart; the standard rounds to its own preferred series, e.g. IT7 10-18 mm: 17.3 -> 18).
- Fundamental deviations (shaft, um): g = -2.5 D^0.34, f = -5.5 D^0.41, e = -11 D^0.41, d = -16 D^0.44, k = +0.6 D^(1/3) (IT4..IT7), m = IT7 - IT6, p = IT7 + (0..5), h = 0. Hole letters mirror the shaft (F = -f, G = -g, E = -e, D = -d, H = 0).
- Table values used (um; ISO 286-2 as printed by roymech.org/Useful_Tables/ISO_Tolerances and engineersedge.com):
  range 6-10 / 10-18 / 18-30 / 30-50 / 50-80 (the code also holds 80-120 and 120-180): IT5 6/8/9/11/13, IT6 9/11/13/16/19, IT7 15/18/21/25/30, IT8 22/27/33/39/46, IT9 36/43/52/62/74, IT10 58/70/84/100/120.
  IT6, IT7, IT8 for 10-18, 18-30, 30-50 were re-read on the web (Xometry table); IT5, IT9, IT10 and the fundamental deviations are RECALLED and checked against the formulas above.
  Cross-check against a published example: Grgic et al. 2023 Table 4, 35 mm: H9 +62/0, h9 0/-62, g9 -9/-71, f9 -25/-87 (bar a3).
- Fits chosen (one pin diameter serves two holes, so the pin is the shaft-basis part, h5; the rest are hole basis):
  1. piston pin in rod small end bush: 13 G6/h5 (running; clearance 6..25 um).
  2. pin in piston boss: 13 JS6/h5, a TRANSITION fit (-5.5..+13.5 um; piston warmed to assemble; the aluminium boss opens more than the steel pin when hot). JS: +-IT/2 (ISO 286-1 rounds odd IT to +-(IT-1)/2 only for grades 7-11).
  3. crank main journal in plain bearing: 20 H7/f7 (20..62 um; the real C50 uses ball bearings, a plain bearing is a modelling choice and is said so).
  4. piston skirt in bore: 39 H7/e7, chosen by code as the tightest standard fit whose HOT clearance stays above 5 um (section 3). The "textbook" 39 H7/f7 is the planted control: it seizes hot.
  5. crank pin in rod big end: 18 H7/f7 (16..52 um).

## 3. Thermal expansion

delta_D = alpha D (T - 20 C) per part. Clearance hot = clearance cold + delta_D(hole part) - delta_D(shaft part).
- piston alloy 4032-T6: alpha = 19.4e-6 /K (20-100 C). Sources: aviationaluminum.com 4032 overview and amesweb.info CTE table (both 19.4). The range is 20-100 C; used up to 120 C (slightly low, i.e. optimistic; said in the report).
- grey cast iron liner: alpha = 10.5e-6 /K (amesweb.info; EN-GJL-200 datasheet 10.5; makeitfrom.com says 11).
- carbon steel pin: 11.7e-6 /K (RECALLED, common handbook value).
- Operating temperatures are ASSUMED design inputs: piston skirt 120 C, liner bore wall 100 C, pin boss 150 C, pin 130 C (small SI engines run skirts at roughly 100-200 C: RECALLED, Heywood, unverified).
- Required hot clearance minimum 5 um (oil film, an assumed criterion).

## 4. Stack-up

1-D chain gap = sum(sign_i x nominal_i); each link has a symmetric +/- tolerance from its ISO IT grade (+/- IT/2).
Worst case: sum |t_i|. RSS: sqrt(sum t_i^2). The code also enumerates all 2^n corners (must equal the worst case). Chains: crank end-float; piston deck clearance.

## 5. Slider-crank torque

x(th) = r cos th + sqrt(L^2 - r^2 sin^2 th); piston force F = (p - p_crankcase) A - m_rec r w^2 (cos th + lambda cos 2th) (inertia; m_rec = m_piston + pin + rings + 1/3 rod, the 1/3 split RECALLED from Heywood engine dynamics);
torque T = -F dx/dth = F r sin th (1 + r cos th / sqrt(L^2 - r^2 sin^2 th)) (virtual work). Mean torque over the 720 deg cycle = work / (4 pi); closed form for the Otto cycle: W = p1 Vc (tau-1)(rc^n - rc)/(n-1).
The pressure curve is an INPUT (not a combustion simulation): polytropic compression/expansion n = 1.30 (Heywood: 1.25-1.35), intake 0.85 bar, exhaust 1.05 bar, crankcase 1.013 bar, heat-release shape a Wiebe fraction (a = 5, m = 2, 50 deg burn from 20 deg BTDC) scaling the pressure by (1 + (tau - 1) x_b), tau = 4.0 chosen BEFORE running from the 30-50 bar typical peak for small SI engines (RECALLED, unverified) and not tuned to the spec.
Friction: Chen-Flynn FMEP = 0.4 + 0.005 p_max + 0.09 Cm + 0.0009 Cm^2 bar (Cm mean piston speed m/s) (Chen and Flynn 1965, SAE 650733 via Heywood; coefficients RECALLED, unverified).
Sanity band against the spec: brake power at 7000 rpm and brake torque at 5000 rpm each within 0.5x to 1.5x of 2.5 kW and 3.8 N m. A sanity check with many assumed inputs, not a validation.

## 6. 3D-print compensation (printed prototype parts)

Grgic M., et al. (2023) "Accuracy of FDM PLA Polymer 3D Printing Technology Based on Tolerance Fields", Processes 11(10), 2810 (https://www.mdpi.com/2227-9717/11/10/2810). Creality Ender-3 Pro, 0.4 mm nozzle, 0.2 mm layer, PLA:
- the CAD model of BOTH hole and shaft is drawn at the arithmetic mean of the zone's max and min diameter (Table 4: 35 H9 -> 35.031, 35 h9 -> 34.969);
- slicer Horizontal Expansion 0.0 mm (outer sizes) and Hole Horizontal Expansion 0.13 mm per side (first print: a 45 mm hole printed 44.80, a 0.2 mm shortfall; HHE 0.1 then 0.13 landed on 45.00). The paper's discussion once writes -0.13; Table 2 and the abstract say 0.13. I use +0.13 per side, positive enlarges the hole.
- the paper demonstrated zones of IT9 and wider only; finer zones are flagged "not demonstrated" and the prototype uses the same fundamental-deviation letters at IT9.
The code emits mid-zone CAD diameters and, for a slicer with HHE = 0, hole diameters baked up by 2 x 0.13 = 0.26 mm. Printer model for the bar: an uncompensated hole prints 0.26 mm (diameter) small; a shaft prints true.

## 7. Parts, animation, section

Seven Kine Parts (OCCT): crankcase, crankshaft, connecting rod, piston, piston pin, cylinder, head. Fit-critical diameters come from the mid-zone dims in code. Assembly view: crank axis along z, cylinder axis y; 2 crank revolutions posed by the kinematics; section view with SectionLook's cut material; the contact sheet is looked at.
GDScript, not C++: the maths is ~3000 samples of closed-form trig (microseconds); no native twin is warranted.
