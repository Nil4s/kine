# CH1f reference: soil, foundation and building system on the CH1 house

**Label: physics model with cited typical values, NOT an NBR code check.** No compliance with any NBR (or ASCE) provision is claimed anywhere in CH1f, in its test output, its table or its render captions. The ABNT texts are paid and not owned (Nick, 2026-11-04). NBR numbers appear only if a citable secondary source gave them; everything else is marked UNVERIFIED. Read 2026-11-04.

Reading status key: READ = text seen this session; MEMORY = recalled from the standard textbook/paper, not re-opened (so UNVERIFIED in the strict sense); UNVERIFIED = a typical value chosen by the author, no source read.

## 1. Soil-structure interaction

- Gazetas, G. (1991), "Formulas and Charts for Impedances of Surface and Embedded Foundations", J. Geotech. Eng. ASCE 117(9):1363-1381, doi 10.1061/(ASCE)0733-9410(1991)117:9(1363). The paper is behind a paywall: only the abstract page was read (confirms: closed-form dynamic stiffness K and damping C of rigid foundations on a homogeneous half-space, surface and embedded). **The coefficients below are MEMORY (as reproduced in NIST GCR 12-917-21, not opened)**, so UNVERIFIED as text. Sanity check done in code review: for a square footing they reproduce the circular-footing limits (vertical 4GR/(1-nu), horizontal 8GR/(2-nu), rocking 8GR^3/(3(1-nu)), torsion 16GR^3/3) within 6 percent, which is the check that the remembered coefficients are the right ones.
  - L, B = half length, half width (L >= B), chi = Ab/(4 L^2), Ab = 4 L B.
  - Vertical: Kz = 2 G L/(1-nu) (0.73 + 1.54 chi^0.75)
  - Horizontal, short direction: Ky = 2 G L/(2-nu) (2 + 2.50 chi^0.85); long direction: Kx = Ky - 0.2/(0.75-nu) G L (1 - B/L)
  - Rocking about the long axis: Krx = G/(1-nu) Ibx^0.75 (L/B)^0.25 (2.4 + 0.5 B/L); about the short axis: Kry = G/(1-nu) Iby^0.75 (3 (L/B)^0.15)
  - Torsion: Kt = G Jb^0.75 (4 + 11 (1 - B/L)^10), Jb = Ibx + Iby
  - These are static stiffnesses (frequency independent). A house at 3 to 20 Hz on soil of Vs >= 120 m/s has a/o = omega B/Vs below about 1, where the frequency dependence of Gazetas' charts is modest; not modelled, stated.
  - Dashpots: Lysmer/Wolf cone analogue, c = rho Vs A (horizontal, torsion with J), c = rho Vla A (vertical, rocking with I), Vla = 3.4 Vs/(pi (1-nu)). Textbook form (Wolf 1994, Foundation Vibration Analysis; Kramer 1996 ch. 11), MEMORY. These are the radiation damping only; no material damping in the soil.
- Period lengthening of a single-DOF structure on a rigid footing: T~/T = sqrt(1 + k/Kx + k h^2/Ktheta). Veletsos and Meek (1974), "Dynamic behaviour of building-foundation systems", Earthquake Eng. Struct. Dyn. 3:121-138. MEMORY (this is also the NEHRP/ASCE 7 ch. 19 form). Used as bar b.
- Geometric stiffness (P-delta): consistent matrix N/(30 L) [[36, 3L, -36, 3L], [3L, 4L^2, -3L, -L^2], [-36, -3L, 36, -3L], [3L, -L^2, -3L, 4L^2]] per bending plane, plus N (Iy+Iz)/(A L) on torsion (Przemieniecki 1968, Theory of Matrix Structural Analysis; Cook et al., Concepts and Applications of FEA). MEMORY. Check: cantilever and pinned Euler buckling loads, bar e.
- The soil is treated at small strain (G = rho Vs^2). Real strong shaking reduces G; the cerrado sites in question see weak shaking, so this is the right end of the range. Stated, not modelled.

## 2. Site classes

- ASCE 7-16 Table 20.3-1 (average shear-wave velocity of the top 30 m): A hard rock > 5000 ft/s (1500 m/s); B rock 2500 to 5000 ft/s (760 to 1500 m/s); C very dense soil and soft rock 1200 to 2500 ft/s (360 to 760 m/s); D stiff soil 600 to 1200 ft/s (180 to 360 m/s); E soft clay < 600 ft/s (< 180 m/s). MEMORY of the widely reproduced table, not re-opened.
- NBR 15421:2006: the lead's brief states it follows the same A to E scheme. A search on 2026-11-04 found no page quoting its table; I remember the D/C boundary there as 370 m/s instead of 360 (UNVERIFIED). No NBR class claim is made; the code uses the ASCE letters as labels.
- The four classes used (Vs inside the range, rho and nu typical textbook values, all UNVERIFIED for any real site):

| id | letter | Vs m/s | rho kg/m3 | nu |
|---|---|---|---|---|
| rock | B | 1100 | 2600 | 0.25 |
| dense | C | 560 | 2000 | 0.30 |
| stiff_clay | D | 270 | 1900 | 0.40 |
| soft_clay | E | 120 | 1700 | 0.45 |

## 3. Mato Grosso

- Seismicity: the ledger and the lead state that NBR 15421 places Mato Grosso in seismic zone 0 (design ground acceleration 0.025 g). **UNVERIFIED by me**: a search on 2026-11-04 returned theses mentioning the zoning table and a UFMS study of the Pantanal basin suggesting the zone-based map may understate hazard there, but no page stating the zone for Mato Grosso or ag. Used only to size an upper-bound comparison (V = 2.5 ag Ca W with R = 1; Ca by class 0.8, 1.0, 1.2, 1.6, 2.5 from MEMORY, UNVERIFIED).
- Wind: NBR 6123:1988 basic wind speed V0 for Cuiaba read from the isopleth map is **35 m/s, UNVERIFIED** (the map was not found as text; search 2026-11-04 returned only the definition: 3 s gust, 50 year return period, 10 m, open flat ground, and a note that a 2023 replacement map exists, Loredo-Souza et al.). Vk = V0 S1 S2 S3, q = 0.613 Vk^2 (N/m2), S2 = b Fr (z/10)^p with category III class A b 0.94, p 0.105 (MEMORY, UNVERIFIED), S1 = S3 = 1. External pressure coefficients windward +0.7, leeward -0.5 (MEMORY of Table 4 for a/b 1 to 1.5, h/b <= 1/2, UNVERIFIED). Walls only, as in CH10.
- Expansive clay: Brazilian literature quotes widely scattered swelling pressures: single studies near 28 kPa and 125 to 150 kPa, and a systematic review of Brazilian soils with a mean of 162 kPa (values from search-result summaries of Brazilian theses and papers on 2026-11-04; the papers themselves were not opened; test standards cited there: ASTM D4546, DNIT 172/2016). **No Cuiaba measurement was found.** The model uses ps = 100 kPa (inside 28 to 162) as an explicit parameter. Also parameters, UNVERIFIED: active depth 1.5 m, free swell strain 2 percent, the linear relief dh = H eps max(0, 1 - q/ps) (a simplification of the pressure-that-stops-swell idea), and a sin x sin z "centre lift" mound. Mato Grosso is listed among the Brazilian states with expansive soil occurrences in the literature (Vilar and Ferreira 2015 as quoted), not as a statement about Cuiaba specifically.
- Durability notes (text only, not simulated, no source read): subterranean termites and high humidity are the standard concerns for untreated timber in the humid tropics, which is the reason the lead gives for wood not being viable there; masonry and galvanised steel avoid the termite problem; steel needs coating class matched to humidity and masonry needs damp-proofing of the baldrame. UNVERIFIED as stated; nothing in the numbers depends on it.

## 4. Building systems (same floor plan, 9.754 x 7.620 m, eave 2.448 m)

All new-system masses are lumped from the takeoff; members carry rho = 0 so nothing is counted twice. Shear panels exist only for full-height piers with h/b <= 3.5 (the CH10 rule); spandrels, partitions and the strips above and below windows add mass only. This is a lower bound on stiffness for all three systems. Roof diaphragm: the CH10 plan stiffness (Ga 7.5 kips/in, UNVERIFIED there) on every system; for a tiled timber roof without sheathing that is generous, stated.

- Wood: the CH10 house unchanged (docs/CH10_REFERENCE.md). SDPWS 2015 Table 4.3A, Ga 11 kips/in; capacity for the heave ratio is the table's nominal 400 plf.
- Confined masonry, 14 cm hollow ceramic block, RC tie columns (14x14 cm) at every pier end, RC tie beam 14x19 and baldrame 14x30:
  - Prism strength fpk 3 MPa = block fbk 6 MPa x prism efficiency 0.5: **UNVERIFIED**. E = 600 fpk, G = 0.4 E: recalled from NBR 15812-1, **UNVERIFIED** (not read; the old brief's "NBR 15961/15812" are the concrete-block and ceramic-block structural masonry design parts). Shear strength fvk 0.15 MPa: **UNVERIFIED**.
  - Wall mass 255 kg/m2 = 0.14 m x 1250 kg/m3 hollow block + 2 x 20 mm render x 2000: **UNVERIFIED** typical values (NBR 6120 lists such unit weights; not read).
  - RC: fck 25 MPa, Ecs = 0.8625 x 5600 sqrt(fck) = 24.15 GPa, G = 0.4 Ecs, 2500 kg/m3: formulas from NBR 6118 as remembered, **UNVERIFIED**; the standard 25 kN/m3 is common textbook value.
  - Roof mass: timber roof 15 + ceramic tile 45 kg/m2 of slope: **UNVERIFIED**.
  - Pier stiffness (shear plus flexure, fixed-fixed): kh = 1/(h^3/(12 E I) + 1.2 h/(G A)).
- Light steel frame: Ue 90x40x12 x 0.95 mm studs at 400 mm, U tracks, 11.1 mm OSB on the outside, cement-board cladding, gypsum inside. Section properties computed in code from the rectangles of the channel; E 200 GPa, G 77 GPa, 7850 kg/m3 (textbook steel). The steel grade and NBR 15253 details were not read: UNVERIFIED. Panel shear stiffness: the SDPWS OSB row Ga 11 kips/in used as a stand-in for screwed OSB, **UNVERIFIED** (AISI S400 table not read); capacity for the heave ratio likewise 400 plf UNVERIFIED. Cement-board 11 kg/m2: UNVERIFIED.
- Foundation: RC raft 0.10 m thick over the whole footprint (mass 18.6 t), contact area = footprint, rigid. Partitions: 30 kg/m2 mass only.

## 5. Quantities in the table

- Period: first x-sway mode by inverse iteration from the static shape, with P-delta from the gravity axial loads.
- Base shear: peak of kx uF + cx vF (soil spring plus dashpot force) under El Centro 1940 NS unscaled, 30 s, dt 0.01, Rayleigh 5 percent at T and T/5, Newmark average acceleration. El Centro is NOT a Mato Grosso motion; it is used as a unit test input of known shape, not as a hazard.
- Roof drift: peak over time and over the top nodes of (u_top - uF + theta_z H)/H (structure only, rigid-body footing motion removed).
- Heave stress: the peak pier unit shear (kN/m) from the change in panel angular distortion when the ground is lifted by the mound, and its ratio to the panel capacity. Rock and dense rows are hypothetical (such soils do not heave); they show the effect of foundation stiffness alone.
