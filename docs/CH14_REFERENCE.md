# CH14 reference: a hydraulic arm of water-filled syringes that builds a 3-2-1 pyramid of cola cans

Written 2026-11-04 BEFORE any number was run (the bars are in the header of tests/ch14_test.gd). Online access in this lane was thin (web search returned snippets, no datasheets), so every source carries a status: **SEEN** = a search result or page showed it, **MEMORY** = the standard handbook or catalogue value as I remember it, not re-read, **ASSUMED** = my engineering choice, flagged so Nick can replace it. Nothing marked MEMORY or ASSUMED is presented as a measurement.

## 1. The can (12 fl oz, 355 mL; the brief says 330/350 mL)
- 66.2 mm diameter (2.6 in), 122 mm tall (4.8 in): dimensions.com "Beverage Can - 12 oz" and a TricorBraun/Ardagh listing (2.60 in body, 4.81 in total, neck "202") - SEEN. A "sleek" 330 mL can is shorter (about 115 mm); 122 mm is the 12 fl oz can.
- Empty 14 to 16 g (low-quality weight pages, 14.9 g typical) - SEEN; used 15 g. Full: 355 mL x about 1.04 g/mL + 15 g = about 385 g.
- Lid: "202" end = 2 2/16 in = 54.0 mm - MEMORY. Lid contact radius 27 mm. Standing ring of the bottom, radius 24 mm (48 mm diameter) - ASSUMED (a measurement of Nick's own can replaces it; tau_x moves 1 mm per mm).

## 2. The pyramid and its tolerance (geometry, derived)
Row 1: three cans on the table at centre pitch s = 68.2 mm (66.2 + 2 mm to place into). Row 2: two cans, each centred over the gap of two below, standing on their lids. Row 3: one can over the gap of the two in row 2. Height 3 x 122 = 366 mm.
The contact patch of an upper can with a lid is the lens where its standing ring (radius r_b = 24 at u) meets the lid (R_l = 27 at v); the support polygon is the convex hull of the two lenses. Two statements:
- STABLE (bar 7): the can's centre of mass (on its axis) is inside that hull.
- STRADDLING (the placement tolerance, bar 6): it still touches BOTH lids, so the load is shared and it cannot roll into the gap. Contact needs the distance between centres <= r_b + R_l, so along the row tau_x = r_b + R_l - s/2 = 24 + 27 - 34.1 = **16.9 mm**; across the row tau_y = sqrt((r_b + R_l)^2 - (s/2)^2) = **37.92 mm**. (The bare centre-in-hull limit is much larger, about 60 mm, a can perched on one lid; not used as the tolerance.)
- An upper can's position relative to its gap = its own error + half of each support's error, at most 2 e if every can is off by e: the bar is 2 e <= tau.

## 3. Syringes and Pascal
- Bores of BD plastic syringes: 5 mL 12.06 mm, 10 mL 14.5 mm, 20 mL 19.13 mm - SEEN (Karpova lab "syringe diameters" table, a copy of the Harvard Apparatus style table; it lists 20 mL as 19.13, not 19.05). Stroke = V / A: 5 mL 43.8 mm, 10 mL 60.6 mm, 20 mL 69.6 mm (graduated volume only). BD catalogue graduations (0.2 mL for 5 and 10 mL, 1 mL for 20 mL) - SEEN on Fisher/McKesson listings.
- Masses 7 / 12 / 23 g, PP barrel wall 1.0 mm, E_PP 1.3 GPa - ASSUMED / MEMORY.
- Pascal: p = F_master / A_master everywhere in the closed line, F_slave = p A_slave = F_master (d_slave / d_master)^2. The AREA ratio, not the diameter ratio.
- Thumb force: maximal thenar pinch force on a 30 mL syringe plunger about 100 to 111 N (20 female hospital workers; Human Factors 2017, PMID 28704067) - SEEN as a search snippet. Design force 30 N = 27 percent of that maximum, repeatable; 50 N (45 percent) only in the full-can stretch bar. The 30 to 50 N range is the brief's; the percentage argument is mine.
- Plunger seal friction 3 N per syringe - ASSUMED (it sets the hysteresis band). Suction limit of a closed water line 0.08 MPa - ASSUMED.

## 4. Water, hoses, bubble (compliance, the real failure)
- Water bulk modulus 2.2 GPa (20 C) - MEMORY.
- Hose: polyurethane tube ID 4 mm, OD 6 mm, Shore 98A, 1 mm wall (distributor listings, burst 540 to 600 psi, working 180 psi) - SEEN. The tube's Young's modulus is NOT on those pages: 50 MPa is ASSUMED (TPU 98A reports 30 to 100 MPa). Soft clear PVC 10 MPa and nylon-12 1.2 GPa are the alternatives; the planted control uses PVC. Poisson 0.45.
- Thick-wall (Lame) hose, plane stress, free ends: u/a = (p/E)((b^2 + a^2)/(b^2 - a^2) + nu), dV/V = 2u/a, with a = 2, b = 3.
- Barrel hoop strain on the water the barrels hold: dV/V = 2 p r / (t E).
- Bubble: isothermal ideal gas, (P0 + p)(V_a - dV) = P0 V_a, dV = V_a p / (P0 + p), P0 = 0.101325 MPa.
- Backlash at one axis = the volume difference between the highest and the lowest pressure the work cycle (plus the +/- seal-friction band) puts on the circuit, divided by the slave area = lost slave stroke; divided by the moment arm = joint angle; times the distance from the joint to the can = millimetres at the gripper. A worst-case spread over the poses; it assumes each pose is set by an index mark on the master (a detent), not by eye.

## 5. Mechanism (my design, justified)
- Axes and syringe pairs (master | slave), 10 syringes: base yaw 20|20, shoulder 20|20, elbow 20|20, wrist 5|5, gripper 5|5.
- Base: a rack on the 20 mL slave plunger, a 20-tooth module-2 pinion (pitch radius 20 mm) on the turntable. 180 deg needs pi x 20 = 62.83 mm of a 69.6 mm stroke (90 percent). Constant lever, no dead point, one monotone stroke. A lever-crank swept +/-90 deg about its pivot line has a stroke minimum in the middle where the arm is zero: it cannot be pushed through.
- Shoulder, elbow, wrist: lever horns (push pin at radius r, slave pivot at distance d from the axis): L = sqrt(d^2 + r^2 - 2 d r cos phi), arm = d r sin(phi)/L, the horn angle centred on 90 deg over the joint limits so the arm stays far from a dead point. The wrist keeps the gripper level (psi = -(theta1 + theta2)) so the can stays vertical.
- Work argument: a thumb stroke is about 30 N x 0.07 m = 2 J whatever the syringe ratio, so the arm is light (hollow PLA+ boom, 25 mm square, 1.6 mm wall) and the slaves ride on the arm.
- Gripper: two parallel jaws on racks with an idler pinion between them; the 5 mL slave drives one rack, the pinion the other, so the can centres itself. Pads TPU or silicone on the aluminium can; mu 0.4 used - ASSUMED conservative (rubber on aluminium dry is quoted 0.5 to 0.9 in friction tables; MEMORY). Friction force 2 mu N >= 1.5 m g.
- Joint pins: 4 mm steel dowels in printed lugs 40 mm apart; slop = diametral clearance / lug span.

## 6. Materials (boom 25 mm square; E MPa, density kg/m3, strength MPa)
- Corrugated cardboard (C flute, 4 mm wall box): E 1000 (effective bending), 150, 5 - ASSUMED order of magnitude (single-wall edge-crush 4 to 7 kN/m).
- Pine: eastern white pine 12 percent MC, SG 0.35, E about 8.5 GPa, modulus of rupture about 59 MPa - USDA FPL Wood Handbook FPL-GTR-190 Table 5-3 - MEMORY (a transcription showed SG 0.34 green; its E cell was cut off).
- Plywood (3 mm wall tube): 9000, 650, 45 - MEMORY, birch plywood class.
- PLA+: E 2300 (FDM, along the filament; injection-moulded PLA about 3500), 1240, 45 - vendor datasheet class, MEMORY.
- Cantilever: delta = F L^3/(3 E I) + w L^4/(8 E I) + M L^2/(2 E I); checked by the unit-load integral.

## 7. FDM hole compensation
Printed holes come out small. Zhu et al., Advances in Intelligent Systems Research vol. 154 (2017), p. 551 ff. (Atlantis Press 25883323): orthogonal experiments on PLA hole shrinkage, line-width compensation about 0.36 for a 10 mm sample - SEEN as a search snippet (the PDF text could not be extracted). Panico et al., FFF PLA vs drilled holes: more than 1 mm deviation on a 6.35 mm nominal - SEEN snippet. Prusa forum / Makerworld measurements: 2 to 4 mm holes 0.1 to 0.3 mm small - SEEN, anecdotal. Used: design the hole 0.30 mm over nominal plus 0.15 mm running clearance; process scatter +/-0.10 gives a worst diametral clearance of 0.25 mm in the slop model (PIN_CLEAR).

## 8. Deliverables
Parts in an Assembly; the animated build (tools/ch14_render3d.gd); the syringe-pair section; the BOM (docs/CH14_BOM.md); printable PLA+ parts as STL with the hole compensation; a contact sheet and what looks wrong (docs/CH14_FEEDBACK.md).
