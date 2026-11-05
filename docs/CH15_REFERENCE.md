# CH15 reference: an Angra 2 class PWR plant (KWU 1300 MWe, 4 loops)

Written 2026-11-04 BEFORE any number was run (the bars are in the header of tests/ch15_test.gd). Every number carries a status, as in CH14:
**SEEN** = a page or document I read in this lane showed it (the source is named), **MEMORY** = a handbook or literature value as I remember it, not re-read, **ASSUMED** = my engineering choice, flagged so it can be replaced. Nothing MEMORY or ASSUMED is presented as a measurement. Plant-level public engineering only: no fuel-cycle or enrichment numbers are used.

Sources read:
- [E] Eletronuclear, "Informacoes de Angra 2" (eletronuclear.gov.br/Nossas-Atividades/Paginas/Informacoes-de-Angra-2.aspx), the operator's data sheet.
- [U] J. Gonzalez-Mantecon, UFMG MSc dissertation (repositorio.ufmg.br BUBD-A3PNUZ), Table 3.1 and section 3.3, data taken from the Angra 2 FSAR rev. 13.
- [I] Gonzalez-Mantecon et al., INAC 2015 (INIS 46135092), Table 1.
- [P] WNA reactor database / IAEA PRIS (search result): 3764 MWt, 1350 MWe gross, 1275 MWe net.
- [N] B. Noack (NUCLEN), "Envoltorio de contencao para a usina de Angra 3 em aco de fabricacao nacional", I CGEN 1986 (INIS 17069070).
- [A] AMHYCO D2.1 "Data for the generic containment analysis (PWR-KWU)" (Konvoi, Framatome-reviewed 3D model).
- [O] OSTI 5903482, Braun et al., Nucl. Technol. 72:3 (1986), abstract: KWU 1300 containment.
- [B] PreussenElektra Brokdorf site brochure (search-result snippet only; the PDF is behind a bot wall).
- [F] IAPWS R7-97(2012), IF97-Rev.pdf (iapws.org), coefficient tables and verification tables 5, 15, 35, 36.
- [S] Esri World Imagery tile, zoom 17 (1.0993 m per pixel at -23.008 deg), around -23.0080, -44.4585: measured in this lane (C:/Temp/opencode/sat17.png, crops crop_a2.png, crop_th.png, crop_sw.png).

## 1. Power and primary circuit (bar 1)
| quantity | value | status |
|---|---|---|
| thermal power (nominal, current) | 3771 MWt | SEEN [E]; FSAR steady state 3771.4 [I]; PRIS 3764 [P] |
| gross electrical | 1350 MWe | SEEN [E][P] |
| net electrical | 1280 MWe | SEEN [E] (PRIS lists 1275 [P]) |
| thermal yield (gross / thermal) | 35.8 pct at seawater 27 C | SEEN [E] |
| loops, pumps | 4, 4 | SEEN [E] |
| primary pressure | 157.0 kg/cm2 = 15.40 MPa [E]; 15.8 MPa [U]; 15.7 MPa [I] | SEEN |
| core inlet / outlet | 291.3 / 326.1 C (rise 34.8 K) | SEEN [U] Table 3.1 |
| average coolant temperature | 308.6 C | SEEN [E][I] |
| flow per loop (pump) | 4700 kg/s | SEEN [U] |
| flow through the vessel | 18800 kg/s = 4 x 4700 | SEEN [U] (FSAR column of the RELAP comparison) |
| flow through the core | 17672 kg/s [U]; 67680 t/h = 18800 kg/s [E] | SEEN (the core value excludes the bypass) |
| SG duty | 945.5 MW each (x 4 = 3782) | SEEN [U] |
| pump speed | 1190 rpm | SEEN [U] |

Bar 1 uses Q = m cp dT with m = 18800 kg/s (the vessel flow: the bypass mixes back before the outlet nozzle, so the vessel dT applies to it), dT = 34.8 K, cp from IF97 region 1 at the mean 308.6 C (581.75 K) and 15.5 MPa (the brief's pressure; the plant's is 15.4 to 15.8, reported alongside). Target 3771 MWt +- 3 pct. The enthalpy route m (h_out - h_in) is reported, not barred.

## 2. Steam cycle (bar 2)
| quantity | value | status |
|---|---|---|
| steam at the turbine inlet | 280 C, 64.2 kg/cm2 = 6.2959 MPa, moisture 0.25 pct | SEEN [E] |
| steam flow | 7398 t/h = 2055 kg/s [E]; 2068.4 kg/s FSAR [U]; 513.9 kg/s per SG at 280.3 C [U] | SEEN |
| SG outlet pressure | 6.29 MPa | SEEN [U] |
| turbines | 1 HP + 3 LP, 1800 rpm (60 Hz) | SEEN [E] |
| condenser cooling | seawater once-through, 74.4 m3/s, titanium tubes | SEEN [E] |
| seawater temperature (rating point) | 27 C | SEEN [E] |
| seawater density, cp | 1023 kg/m3, 3.99 kJ/kg K | MEMORY |
| condenser terminal temperature difference | 3 K | ASSUMED (typical 2 to 5 K) |

The condenser pressure is NOT public. It is derived: the rejected heat Q_th - P_gross = 2421 MW warms 74.4 m3/s of seawater by 2421 / (74.4 x 1023 x 3.99e-3) = 7.97 K; condensing temperature = 27 + 7.97 + 3 = 37.97 C; p_c = p_sat(T_c) from IF97 region 4.
Cycle (an ideal Rankine cycle, the brief's "Rankine cycle at the cited conditions"): 1 saturated liquid at p_c; 2 isentropic pump to 6.2959 MPa (h2 = h1 + v1 dp); 3 the SG outlet: wet steam x = 0.9975 at 6.2959 MPa (the saturated states from IF97 regions 1 and 2 at T_sat(p) from region 4); 4 isentropic expansion to p_c. eta = (h3 - h4 - (h2 - h1)) / (h3 - h2). Carnot between T_sat(6.2959 MPa) and T_c. Target band 35.80 +- 3 points (gross 1350 / 3771). The real plant has turbine losses (about -5 points) that are paid back by feedwater preheating and the moisture separator reheater (about +3 to +5 points); an ideal simple cycle at the same end states lands near the real number for that reason, and the feedback says so.
PLANTED: steam as an ideal gas (cp 1.872 kJ/kg K, R 0.4615 kJ/kg K, no latent heat - MEMORY): turbine work cp T3 (1 - (p_c/p3)^(R/cp)), heat in cp (T3 - T_c).

IF97 [F] (regions 1, 2 and 4 are the only ones the cycle touches: compressed liquid at 15.5 MPa / 290-330 C is region 1 because T < 623.15 K and p > p_sat; the steam side is wet or saturated):
| check | value [F] |
|---|---|
| R1 300 K 3 MPa | v 0.100215168e-2, h 115.331273, s 0.392294792, cp 4.17301218 |
| R1 300 K 80 MPa | v 0.971180894e-3, h 184.142828, s 0.368563852, cp 4.01008987 |
| R1 500 K 3 MPa | v 0.120241800e-2, h 975.542239, s 2.58041912, cp 4.65580682 |
| R2 300 K 0.0035 MPa | v 39.4913866, h 2549.91145, s 8.52238967, cp 1.91300162 |
| R2 700 K 0.0035 MPa | v 92.3015898, h 3335.68375, s 10.1749996, cp 2.08141274 |
| R2 700 K 30 MPa | v 0.542946619e-2, h 2631.49474, s 5.17540298, cp 10.3505092 |
| R4 p_s(300, 500, 600 K) | 0.353658941e-2, 2.63889776, 12.3443146 MPa |
| R4 T_s(0.1, 1, 10 MPa) | 372.755919, 453.035632, 584.149488 K |
R = 0.461526 kJ/kg K. The tables print 9 significant digits; "to 1e-6" is read as relative 1e-6 (the printed digits are 1e-9 relative), at least 5 points (the test checks 30 numbers: v, h, s, cp of the six states and the six saturation values).
Implementation: GDScript only (scripts/build/ch15_if97.gd). The cycle needs about 20 property calls and the tests about 40: under a millisecond in GDScript doubles, so a C++ twin would add a build and an equality bar for no speed that anyone would see.

## 3. Electrical (bar 3)
| quantity | value | status |
|---|---|---|
| generator | Siemens THFF 180/64-18, H2 cooled, 1458 MVA (at 75 psig H2), 25 kV (+7.5 / -10 pct), 3 phase 60 Hz, cos phi 0.9, 1800 rpm | SEEN [E] |
| excitation | main exciter 480 V 12 200 A, pilot exciter 220 V | SEEN [E] |
| grid | 500 kV | brief; MEMORY (Furnas 500 kV at Angra) |
| house load | gross - net = 1350 - 1280 = 70 MW | SEEN [E] (difference) |
| house load power factor | 0.85 | ASSUMED |
| emergency diesels, system 1 | 4 units, 5400 kW / 6600 kVA, 60 Hz, 900 rpm (KHD / Siemens) | SEEN [E] |
| emergency diesels, system 2 (bunkered emergency feed) | 4 units, 860 kW / 1050 kVA, 1800 rpm | SEEN [E] |
| "two independent sets of four diesel generators" | | SEEN [U] |
| redundancy of the safety trains | 4 x 50 pct: any 2 of 4 carry the safety load (N+2: one single failure + one in maintenance) | MEMORY (the KWU 4-train concept) |
| safety load of the plant (100 pct of the safety functions) | 9.2 MW = 2 trains x 4.6 MW (85 pct of one diesel) | ASSUMED |
| main step-up transformer | 3 single-phase units 25 / 500/sqrt3 kV, 3 x 520 = 1560 MVA | ASSUMED (not public) |
| generator circuit breaker | 25 kV, 40 kA continuous | ASSUMED |
| unit auxiliary transformers | 2 x 50 MVA, 25 / 10.5 kV | ASSUMED |
| standby (start-up) transformer | 1 x 90 MVA, 138 / 10.5 kV | ASSUMED (a 138 kV line exists at the site, MEMORY) |
| house buses | 4 normal 10 kV buses BA..BD, 4 emergency 10 kV buses BU..BX (one per train), 0.4 kV load centres | ASSUMED (KWU naming MEMORY) |
| D2 buses | 4 x 0.4 kV emergency feed buses | ASSUMED |
Hand: S = P / pf = 1350 / 0.9 = 1500 MVA (the nameplate is 1458 MVA: at 1350 MW it runs at cos phi = 0.926, the feedback notes it). I = S / (sqrt3 V) = 1500e6 / (sqrt3 x 25e3) = 34 641.016 A (nameplate: 33 671.068 A). Main transformer 1560 >= max(1500, 1458). Aux: 70 / 0.85 = 82.353 MVA <= 2 x 50 = 100 MVA (and <= the 90 MVA standby). Diesels: (4 - 2) x 5.4 = 10.8 MW >= 9.2 MW; PLANTED 3 diesels: (3 - 2) x 5.4 = 5.4 MW < 9.2.

## 4. Decay heat (bar 4)
- Way-Wigner: P/P0 = 0.0622 [t^-0.2 - (t + T)^-0.2], t and T in seconds, valid about 10 s to 100 days - MEMORY (Glasstone and Sesonske; Todreas and Kazimi). ANS-5.1 gives about 1.2 to 1.4 pct at 1 h for a long-irradiated core - MEMORY.
- Operating time T = one cycle of about 13 months [E: "frequencia de carregamento aprox. 13 meses"] = 13 x 30.44 d = 3.4190208e7 s - SEEN (13 months) / ASSUMED (the whole core taken at that age; a real core holds 3 batches, which raises the 1-day number).
- Hand: t = 10 s: 0.037309080; 1 h: 0.010156458; 1 day: 0.0044690460 (python, exact formula).
- Emergency feedwater: 36 kg/s injected in the FSAR-based SBLOCA model [U] - SEEN; taken as the capacity available (the per-pump split is not public - ASSUMED reading). Feed water 30 C - ASSUMED; steam at the SG pressure 6.2959 MPa, saturated: m = P(1 h) / (h_g(6.2959 MPa) - h_l(6.2959 MPa, 303.15 K)).
- Sanity band for the planted control: 0.5 pct <= P/P0(1 h) <= 2 pct (ASSUMED band round the ANS value). PLANTED T = 0 gives 0.

## 5. Containment (bar 5)
| quantity | value | status |
|---|---|---|
| steel sphere diameter | 56 m (Angra 2 and 3) | SEEN [N]; KWU 1300 56 m [O][A] |
| Angra 2 sphere steel | WStE 51, imported; minimum yield 500 N/mm2 | SEEN [E][N] |
| Angra 2 sphere wall | 30 mm | ASSUMED (de.wikipedia "3 to 4 cm"; WStE 51 is stronger than the 38 mm WStE 370 / 15MnNi63 spheres) |
| Angra 3 sphere (cross-check case) | WStE 370, 38 mm plates; Rp at 145 C 320 N/mm2; allowable Pm = 0.67 Rp = 214 N/mm2 (KTA 3401.2 criteria) | SEEN [N] Table and quadro |
| allowable criterion | Pm <= 0.67 Rp(145 C) (same form as ASME III class MC / VIII-1: 2/3 of yield) | SEEN [N] |
| WStE 51 at 145 C | 500 x 320/370 = 432.4 N/mm2 (the WStE 370 temperature ratio applied) | ASSUMED |
| design pressure | 5.3 bar gauge (0.53 MPa), 145 C | MEMORY (KWU 1300); [B] shows "6,3 bar" for Brokdorf (read here as absolute); [N] uses 145 C |
| Konvoi sphere wall | 38 mm | SEEN [A] |
| concrete shield | 2 m | SEEN [O] ("2-m-thick concrete shielding"); Konvoi cylinder wall 1.15 m (a different structure, the inner shrapnel cylinder) [A] |
Hand: sphere sigma = p R / (2t): Angra 2 0.53 x 28000 / 60 = 247.333 MPa <= 289.730 MPa; Angra 3 0.53 x 28000 / 76 = 195.263 MPa <= 214 MPa. The cylinder formula p R / t at 38 mm = 390.526 MPa (twice, and over the allowable) is the PLANTED wrong formula. Consistency: at 6.3 bar gauge the cited Angra 3 design (38 mm, 214) would be over-stressed (232 MPa), so the cited plates support 5.3 bar gauge.

## 6. Layout (bar 6)
Measured on [S] (1.0993 m/px; the view is slightly oblique, so the edges are good to about +-3 px = +-3 m). The site grid used in the model is the PLANT grid: +X along the turbine hall axis (47 deg clockwise from image east, i.e. about N43E rotated; the image is north up), origin the reactor centre, +Z to plant south, Y up from grade (+0 m).
| building | measured footprint | height | position (plant grid, centre) | status |
|---|---|---|---|---|
| reactor building (concrete shield) | diameter 71.5 m (65 px across the dome) | 60 m above grade | 0, 0 | footprint SEEN [S]; height ASSUMED |
| turbine hall | 93 x 50 m (85 x 45 px incl. the side bay) | 45 m | 82.4, 30.4 (offset 34, 81 m in the image) | footprint SEEN [S]; height ASSUMED |
| 500 kV switchyard (shared with Angra 1) | 280 x 190 m | 30 m (gantries) | 173, -208 | footprint SEEN [S] (gravel field outline); height ASSUMED |
| seawater intake structure | 70 x 35 m | 15 m | -90, 188 | footprint SEEN [S] (pier at the shore SW of the dome); identification ASSUMED |
| reactor auxiliary building | 60 x 45 m | 30 m | -24, 62 | position SEEN [S] (block W/SW of the dome); size and role ASSUMED |
| switchgear building | 50 x 30 m | 25 m | 40, -60 | ASSUMED |
| fuel building (new fuel store; KWU keeps the spent-fuel pool inside the containment) | 30 x 25 m | 20 m | -60, -60 | ASSUMED |
| emergency diesel buildings 1 and 2 (2 diesels each) | 40 x 20 m each | 15 m | -85, -15 and -85, 20 | ASSUMED |
| emergency feedwater building (D2 diesels) | 30 x 30 m | 20 m | 40, -110 | ASSUMED |
| outfall structure | 30 x 20 m | 8 m | 60, 150 | ASSUMED |
OpenStreetMap (Overpass, way 1068372646, Angra 3 reactor building outline under construction) gives an equivalent diameter of 57.6 m, which cannot hold a 56 m sphere plus the annulus: not used. Only the four SEEN footprints are measurements; the 5 pct bar on the ASSUMED ones checks the model against its own reference table, and the feedback says so.

## 7. Reactor building interior (block level)
| item | value | status |
|---|---|---|
| sphere centre | +22 m above grade (sphere -6 to +50 m) | ASSUMED |
| base mat | 3 m thick, top at -6 m, excavation to -9 m | ASSUMED |
| shield | cylinder wall 2 m (outer R 35.75) to +24.25 m, hemispherical dome on it (top +60 m) | thickness SEEN [O]; heights ASSUMED |
| service floor | +21.5 m above the vessel bottom reference | SEEN [A] (in this model: the operating deck at +15.5 m above grade) |
| reactor pressure vessel | inner diameter 5.0 m, OD 5.5 m, 12 m high incl. head, 20 MnMoNi 5 5 | material SEEN [E]; size MEMORY |
| steam generators (4) | 21 m high, 5 m upper shell, vertical U-tube, Incoloy 800 tubes | type and tube SEEN [E]; size MEMORY (same class) |
| reactor coolant pumps (4) | 3 m x 9 m | ASSUMED |
| pressurizer | 3 m x 14 m | ASSUMED |
| main coolant line | 0.75 m bore, 0.9 m OD | MEMORY (KWU 750 mm) |
| polar crane | bridge 52 m span on a ring runway at +40 m | ASSUMED |

## 8. Construction (bar 7)
Order [E]: start of construction = reactor building base plate concrete 14.09.81; start of steel containment erection 18.10.82; electromechanical erection 06.96; commissioning 03.98; first criticality 14.07.00; grid 21.07.00. The sequence modelled: 1 excavation + base mat; 2 lower cup + sphere lower half; 3 sphere upper half; 4 internal concrete (cavity, deck); 5 polar crane runway + crane; 6 vessel, SGs, pumps, pressurizer, loops (lifted in by the crane through the open shield); 7 shield wall; 8 shield dome; 9 turbine hall mat, table, turbines, generator, condensers, hall; 10 auxiliary, switchgear, fuel, diesel, feedwater buildings, switchyard, intake, outfall. Stage order within the reactor building ASSUMED from KWU practice (the shield is closed after the big lifts).
