# CH1f feedback: soil springs, P-delta, confined masonry and light steel frame on the CH1 house

**Label: physics model with cited typical values, NOT an NBR code check.** Sources and every UNVERIFIED flag: docs/CH1f_REFERENCE.md. Written 2026-11-04.

## What was built

- Soil: Gazetas (1991) static springs for a rigid rectangular raft on a homogeneous half-space (x, y, z, two rocking, torsion) plus Lysmer/Wolf cone dashpots, on one footing node tied to every wall base. Four sites, ASCE letters as labels only: rock B (Vs 1100), dense C (560), stiff clay D (270), soft clay E (120 m/s). Small-strain G = rho Vs^2.
- P-delta: consistent geometric stiffness per beam from the gravity axial forces, in both the C++ solver (`native/src/kine_frame_native.cpp`) and its GDScript twin (`scripts/build/ch10_frame.gd`).
- Wall systems on the same 9.754 x 7.620 m plan (`scripts/build/ch1f_systems.gd`): wood (the CH10 house), confined masonry (14 cm ceramic block, 14x14 RC tie columns at 26 pier ends, tie beam and baldrame), light steel frame (Ue 90x40x12x0.95 studs at 400 mm, 114 studs, OSB). All three on a 0.10 m RC raft (18.6 t) and a rigid roof diaphragm.
- Expansive clay heave (ps 100 kPa, 1.5 m active depth, 2 pct free swell, centre-lift mound) and NBR 6123-form wind (V0 35 m/s Cuiaba, UNVERIFIED), compared against the zone 0 seismic bound.

## Bars (run 2026-11-04, logs C:/Temp/claude/w4-ch1f/w10/ch1f.log): 33 ok / 0 fail

| bar | number | limit |
|---|---|---|
| a fixed-base limit (Vs 5000) | wood 0.000, masonry 0.033, lsf 0.002 pct | < 1 pct |
| a2 planted units slip (m/s read as ft/s) | masonry 1.170 pct, so it FAILS the 1 pct bar as it must | > 1 pct for one system |
| b SDOF on footing vs Veletsos-Meek | 1.2097 vs 1.2093 (0.04 pct) | < 5 pct |
| c periods rise with softer soil | masonry 0.0644 fixed, 0.0645 B, 0.0650 C, 0.0671 D, 0.0819 E s; wood and lsf likewise | strictly rising |
| d masonry shifts more than wood, soft clay | 27.14 pct vs 0.198 pct, ratio 136.9 vs predicted 88.1 | > 1 and within x3 |
| e Euler buckling via K + Kg singular | cantilever 0.000, pinned 0.000 pct; control without Kg never buckles below 3 Pe | < 2 pct |
| f mass vs hand takeoff | masonry 38421 (0.00), lsf 7820 (0.00), wood 8852 vs 8816 kg (0.40 pct) | < 5 pct |
| g P-delta lengthens fixed-base period | wood +0.041, masonry +0.021, lsf +0.127 pct | > 0 |
| h C++ == GDScript | static 3.3e-13, modal 1.6e-13, Newmark 1.3e-12 | < 1e-9 |
| i heave | free heave equals H eps (1 - q/ps) to 1e-12; masonry 27.74 <= wood 28.91 mm; doubling eps gives x2.0000 | as stated |
| j wind | q 521.2 Pa = hand; force 15049 N = p_net x area | 0.5 pct |
| j2 S2 5 m floor (added before its run) | 573.6 Pa = hand; no effect at 8 m; control: floored exceeds unfloored by > 5 pct | as stated |

The fact the c and d bars report is that the soil matters for the heavy, stiff masonry house (period +27 pct on soft clay) and hardly at all for the light, flexible wood and steel houses (+0.2 and +1 pct). That is the Veletsos result: the shift goes with the structure stiffness, not with its mass.

## Table (El Centro NS unscaled as a known test input, NOT a Mato Grosso motion; P-delta on)

| system | soil | T s | V base kN | roof drift | heave dh mm | heave shear kN/m | of capacity |
|---|---|---|---|---|---|---|---|
| wood | B / E | 0.2902 / 0.2907 | 93.3 / 93.3 | 0.0147 / 0.0148 | 28.9 | 0.34 / 0.31 | 5.8 / 5.3 pct |
| masonry | B / E | 0.0645 / 0.0819 | 195.8 / 193.7 | 0.0002 / 0.0002 | 27.7 | 8.75 / 3.77 | 41.7 / 18.0 pct |
| lsf | B / E | 0.1540 / 0.1555 | 96.4 / 97.2 | 0.0013 / 0.0013 | 29.0 | 0.47 / 0.36 | 8.0 / 6.1 pct |

Wind on dense soil: 15.05 kN on every system against zone 0 bounds of 20.2 (wood), 41.9 (masonry) and 19.4 kN (lsf). For Mato Grosso, expansive-clay heave is the governing check for masonry: up to 42 pct of the assumed block shear strength from heave alone, rising on stiffer soil because the raft then follows the mound. Wind is of the same order as the zone 0 bound for the light systems.

## Picture

`C:/Users/Nick/tools/kine_workers/out/ch1f/ch1f_render.png` (tools/ch1f_render.gd), looked at. On the first render the cutaway was wrong: the camera sat on the +z side, so the z < 0.5 wall it removed was the far one and the near wall hid the inside. It also drew stiff clay over a dense layer, although the springs assume one half-space. Fixed: the camera now looks from -z with the light on that side, the order is mirrored so wood stays on the left, and the soil is one Vs 270 colour with the 1.5 m swelling band marked. Still schematic: masonry and lsf show only frame lines (the infill is not drawn as solid block), their roof is lumped mass so only a translucent plate floats above the walls, and the three ground blocks run together.

## Unresolved / to look at

- Wood roof drift 1.47 pct against lsf 0.13 pct. The wood house has a period only 1.9 times longer and about the same mass, so this ratio of about 11 is larger than an SDOF estimate (about 3 to 5). The drift is the maximum over all top nodes. The likely cause is an out-of-plane or local mode of a CH10 wood wall top, not storey sway. This was not investigated. Read the wood drift as an upper bound until it is.
- Base shear V is the soil spring force, so it includes the 18.6 t raft inertia (roughly 60 kN at El Centro's PGA). That is why V barely changes between systems.
- The heave dh is the same on every soil row because swelling is a parameter. Rock and dense rows are hypothetical: they show foundation stiffness alone.
- Every material value of masonry and lsf (fpk 3 MPa, E = 600 fpk, fvk 0.15 MPa, 255 kg/m2, OSB Ga 11 kips/in standing in for AISI S400), V0 35 m/s, zone 0 ag 0.025 g and ps 100 kPa is UNVERIFIED (see the reference). No Cuiaba swelling measurement was found.
- ch1 suite was not re-run in this session (ch1f, ch10, ch12, easypart, peasy3, freestart were).

## Merge note

origin/poser-ui-rounds (CH12 lateral dashpots and crowd) conflicted in the Newmark step of both solvers. Resolved by keeping the CH1f form (Rayleigh on the structural stiffness Kd, soil dashpots on the diagonal) and adding the CH12 dashpots on top in both twins. Kd equals K for CH12's models, so its numbers are unchanged. ch12 21 ok, and bar h still gives 1e-12.

## Engineering level reached (docs/CHALLENGE_FEEDBACK.md scale)
- **Structural dynamics: L3.** Gazetas springs, P-delta and modal analysis are checked against closed forms (footing 0.04 pct, buckling exact), the C++ and GDScript solvers agree to about 1e-12, and there are planted controls. Not L4: El Centro is a stand-in record, not a Mato Grosso design spectrum, and there is no load-combination check against NBR 6118 / 15421 / 16055 / 15961.
- **Geotechnical: L2-L3.** The soil classes and the swelling pressure are typical values, not a site investigation (no SPT, no Cuiaba swelling test found).
- **Masonry and light steel frame: L2-L3.** The member and material values are unverified, and the masonry walls are frame lines, not shell elements.
- **Next level would need:** a Brazilian code load path (NBR 6123 wind, NBR 15421 seismic zone 0), the design combinations, shell or panel walls, and a real soil report.

## What Kine lacked
| needed | exists today | workaround | proposed feature |
|---|---|---|---|
| soil under a structure (springs, dashpots per soil class) | nothing in the app | ch1f_soil.gd (Gazetas closed forms) | a "Foundation" property on a building: soil class -> springs, used by the CH10 solver |
| wall systems as materials (confined masonry, LSF, wood) on one plan | wood framing only (CH1 house) | ch1f_systems.gd builds each system's members by hand | a wall-system picker on the house plan that regenerates members, masses and stiffness |
| Brazilian code loads (NBR 6123 wind, NBR 15421 seismic) | nothing | constants from memory (35 m/s, 0.025 g) | load generators per code and region, with the source printed |
| masonry and shear walls as panels | 3D frame (beam) solver only | walls drawn as lines; stiffness approximated | a shell or equivalent-strut wall element in the frame solver |
| a section/cutaway render of a building | SectionLook (CH13 used it) | a custom cutaway in tools/ch1f_render.gd, first drawn on the wrong side: a DISCOVERABILITY gap | one render helper: building + cut plane -> picture (G11 in the ledger) |
