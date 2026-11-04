# CH10 reference: the CH1 house under wind and the El Centro record

Read 2026-11-03. Every number the model uses, where it came from, and how well it was read. "UNVERIFIED" = could not be read from a primary or printed source.

## 1. El Centro 1940 NS accelerogram

- Record: Imperial Valley earthquake 1940-05-18, El Centro Array #9 (USGS station 117), north-south component.
- File used: `data/ch10/elcentro_NS.dat`, two columns (time s, acceleration g), 2688 samples at 0.02 s, 53.74 s long, **peak 0.3487 g** (the published PGA of this component is 0.348 g, so the file is the corrected record, not a rescaled one).
- Downloaded from: http://www.vibrationdata.com/elcentro_NS.dat (page https://mail.vibrationdata.com/elcentro.htm). The page cites the PEER ground motion database (http://peer.berkeley.edu/research/motions/), original source CIT-SMARTS, "Type of Digital Strong-Motion Data: Corrected".
- Licence: the page states none. The record is a US public strong-motion record (California Institute of Technology / USGS / CSMIP data are released for research). Used here as a public research data file; if Kine ever ships it, check CSMIP/PEER terms. The page itself warns that several versions of El Centro circulate (raw, corrected, different sampling); this is the 0.02 s corrected version. An NPTEL (IIT) appendix lists the NS record at 0.02 s with 1559 points (that is a shorter 31 s cut); a different cut, same record.
- The record is applied unscaled, base acceleration in the model direction, x or z (one component at a time).

## 2. Wood-frame shear wall stiffness (SDPWS)

Source: AWC *Special Design Provisions for Wind and Seismic* 2015 edition (ANSI/AWC SDPWS-2015), Table 4.3A, read from the AWC-hosted copy mirrored at https://bayarearetrofit.com/wp-content/uploads/2015-Wind-and-Seismic.pdf (page 41 of the PDF; the AWC 2021 download is table-of-contents only). The cell was read from the PDF text, not from memory.

Row used: "Wood Structural Panels - Sheathing", 3/8 in, 1-1/4 in penetration, **6d** common nail, 6 in panel edge spacing, blocked:
- seismic nominal unit shear vs = 400 plf, apparent stiffness **Ga = 11 kips/in (OSB)** (8.5 for plywood);
- the Structural I 7/16 in row with 8d reads vs = 510 plf, Ga = 16 kips/in (OSB). CH1's nail is 6d common (house_check fastener schedule), and 7/16 has no 6d row, so the 3/8 in 6d row is used: it is also the conservative one (lower Ga).
- Cross-check: ASD allowable = vs / 2.0 = 200 plf, and the 2018/2021 IBC wood-structural-panel table (a Santa Clarita CA copy of IBC 2306.3(4)) lists 200 plf for that row, so the cell and its ASD conversion agree.

Deflection equation (SDPWS 4.3-1, three term, anchorage slip term dropped because the model anchors the plates rigidly):
 delta = 8 v h^3 / (E A b) + v h / (1000 Ga) with v in plf, h and b in ft, E psi, A in^2, Ga kips/in, delta in inches.
Shear stiffness of a full-height segment of width b: k = 1000 Ga b / h (lb/in), the shear term alone. A 1.219 m x 2.467 m sheet gives 5430 lb/in = 0.95 kN/mm. The model puts that horizontal stiffness into two crossed diagonal springs per sheet; the chord term emerges from the studs in the frame.
- Aspect limit: SDPWS 4.3.4, h/b <= 3.5 for a segment to count (2015 relaxed from 2:1 to 3.5:1 with a strength reduction beyond 2:1; the stiffness is not reduced here). Contiguous full-height sheets form one segment.
- Not modelled: gypsum on the inside of the walls adds stiffness (and the partitions have no sheathing in CH1), hold-down and anchor-bolt slip, nail-slip hysteresis. The model is linear.
- Roof diaphragm: SDPWS Table 4.2A (blocked WSP diaphragm) 6d nails on 3/8 in OSB reads Ga = 15 kips/in for the first row of that table; CH1's roof is unblocked, and Table 4.2C was not read, so the model halves it: **Ga = 7.5 kips/in, UNVERIFIED** (the roof diaphragm is stiff against the walls whatever it is: the run reports the roof's own share of the drift).

## 3. Period and drift (ASCE 7-16)

- Approximate period Ta = Ct hn^x, Table 12.8-2, "all other structural systems" Ct = 0.02, x = 0.75, hn in ft. hn = ridge height above the base = 3.95 m = 12.96 ft: **Ta = 0.02 x 12.96^0.75 = 0.137 s**. (The values Ct and x are from memory of the table; the structuremag.org and ideCAD pages found list the other rows (0.028/0.8 steel moment frame, 0.03/0.75 braced steel) and not this row: UNVERIFIED but the standard values.)
- Upper limit on a computed period: Cu Ta, Table 12.8-1; Cu = 1.7 when SD1 <= 0.1 g (SD1 of Levittown is not looked up: UNVERIFIED). The bar band is [0.5 Ta, 1.7 Ta] = 0.069 to 0.233 s. 0.5 Ta is a floor taken from the observation that measured one-story house periods run longer than Ta, not shorter.
- Allowable story drift, Table 12.12-1: 0.020 hsx for "all other structures" in Risk Category I/II; 0.025 hsx only for structures four stories or less whose partitions, ceilings and exterior walls are designed to accommodate the drift. The model uses the stricter **0.020**. (A structuremag.org snippet confirms 0.020 / 0.015 / 0.010 for the "other" row.) The ASCE 7 check is made on design-level forces amplified by Cd/Ie (Cd = 4 for wood shear walls, R = 6.5); the model applies the unreduced record at 0.35 g and compares the elastic drift directly, which is a different (and for a 0.35 g record, much larger) demand than a design-level check. Both numbers are stated in the report.
- Damping 5 percent, Rayleigh, matched at the first sway period and at five times its frequency.

## 4. Wind (ASCE 7-16 chapters 26 and 27, directional procedure, enclosed rigid building)

- Site: house_check's stored record `levittown_ny`: Vult 130 mph, exposure B, risk II (wind value itself "from memory (UNVERIFIED SITE)" in house_check).
- q_z = 0.00256 Kz Kzt Kd Ke V^2 psf with Kzt = 1, Kd = 0.85, Ke = 1. Kz = 2.01 (z/zg)^(2/alpha), z not less than 15 ft, exposure B alpha = 7, zg = 1200 ft -> 0.575 (the table value is 0.57; exposure C gives 0.849, table 0.85). q = 0.00256 x 0.575 x 0.85 x 16900 = 21.1 psf.
- p = q G Cp, gust factor G = 0.85 (rigid), windward wall Cp = +0.8, leeward wall Cp = -0.5 for L/B <= 1, -0.3 at L/B = 2 (Fig. 27.3-1, values from memory: UNVERIFIED). Internal pressure cancels in the net lateral load.
- Roof pressure horizontal components are omitted (an 18 degree roof carries suction on both slopes; the horizontal parts nearly cancel). The load is applied at the top-plate level over half the wall height (the lower half goes straight into the base), plus the gable triangle for wind on the gable end.
- Strength-level pressure (Vult). The ASD level is 0.6 of it.

## 5. Frame model constants

- DF-L #2: E = 1.6e6 psi = 11.03 GPa (NDS Supplement Table 4A, the species house_check assumes), G = E/16, density 530 kg/m3.
- Finishes added as mass only (no stiffness): 1/2 in gypsum 2.2 psf (ASCE 7 Table C3.1-1) on the ceiling and the inside face of exterior walls (both faces of partitions); asphalt shingles 2 psf; 7/16 OSB 7.1 kg/m2; lap siding 9.5 kg/m2; windows and doors 30 kg/m2.

## 6. Model summary

3D Euler-Bernoulli frame, 6 DOF per node, rigid joints, consistent mass, built from out/ch1/members.json: studs, kings, jacks, cripples, corner posts, nailers, plates, headers, sills, joists, ridge, rafters (tail to ridge), gable studs. A member end that sits on or frames into another member is joined to that member's axis (offsets of up to 0.12 m collapsed; the rafter and ridge axes are the rafter underside line). The double top plate is two beams tied by stiff links. Shear walls and the roof diaphragm are crossed diagonal springs (section 2). Base: bottom-plate nodes fixed in translation. Solver: `native/src/kine_frame_native.cpp` (KineFrameNative: assembly, reverse Cuthill-McKee, banded Cholesky, Newmark average acceleration beta 1/4 gamma 1/2, inverse iteration); GDScript twin `scripts/build/ch10_frame.gd` (dense, small frames).

## 7. Second reading of bar (c): ASCE 7-16 12.8.2 analytical upper limit Cu Ta (added after the run; bar c is unchanged)

- Table 12.8-1 (read 2026-11-03 at https://help.idecad.com/ideCAD/12-8-2-determination-of-the-building-s-fundamental): SD1 >= 0.4 -> Cu 1.4; 0.3 -> 1.4; 0.2 -> 1.5; 0.15 -> 1.6; <= 0.1 -> 1.7.
- The site (levittown_ny) record carries SDC B only; SD1 is not looked up (UNVERIFIED SITE). SDC B for Risk II means SD1 < 0.133 g, so Cu is 1.6 (at 0.133 g, interpolated between the 0.1 and 0.15 rows) to 1.7 (SD1 <= 0.1).
- Ta = 0.02 x 12.96^0.75 = 0.1366 s; Cu Ta = 0.219 s (Cu 1.6) to 0.232 s (Cu 1.7).
- Model first sway periods: z 0.252 s (1.85 Ta), x 0.290 s (2.12 Ta). Both EXCEED Cu Ta by 9 to 33 percent. Section 12.8.2 caps the period used for base shear at Cu Ta; for drift, 12.8.6.2 permits the analytical period to exceed it, so the exceedance is not a code violation, but it is a signal.
- Direction of the error: a period too long means the model is too soft or too heavy. Candidates, in order of likely size: (1) Ga = 11 kips/in is the low OSB/6d row, and the model counts only sheathed full-height segments (gypsum, partition walls and the garage-free plan's corner returns add real stiffness and are ignored); (2) mass 6958 kg (19.2 psf) includes all finishes and may be heavy; (3) the hold-down assumption goes the other way: plates are anchored rigidly, so real hold-down/anchor slip would make the house SOFTER and the period longer still; (4) the 0.12 m axis offsets and rigid links are idealisations of unknown sign. Ta itself is a generic all-systems formula; measured one-story wood houses commonly run 0.2 to 0.3 s, so the model is plausible, but the bar as registered fails.
