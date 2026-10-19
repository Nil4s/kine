# Proportions: the real numbers (round 51, GATES PR)

Every number Kine's proportions use, where it came from, and how it was checked. Code: `scripts/proportions.gd`.
Test: `tests/proportions_test.gd`. Read 2026-10-18.

## 1. Stature and mass: ANSUR II (2012 Anthropometric Survey of U.S. Army Personnel)

Gordon, C.C. et al. (2014). *2012 Anthropometric Survey of U.S. Army Personnel: Methods and Summary Statistics.*
NATICK/TR-15/007. The public data files (`ANSUR II MALE Public.csv`, `ANSUR II FEMALE Public.csv`) from
https://www.openlab.psu.edu/ansur2/ (files at https://tools.openlab.psu.edu/publicData/). N = 4,082 men, 1,986 women,
no blanks in the columns used. Lengths in mm; `weightkg` is in tenths of a kg (male mean 855.2 = 85.5 kg).
Percentiles computed with `numpy.percentile` (linear), each sex separately, and **checked against the report's own
tables** (pp. 192-193 stature, pp. 224-225 weight): identical.

| | men P5 | men P50 | men P95 | women P5 | women P50 | women P95 |
|---|---|---|---|---|---|---|
| stature (mm) | 1648 | 1755 | 1870 | 1525 | 1626 | 1740 |
| weight (kg) | 64.4 | 84.6 | 110.7 | 51.3 | 66.8 | 87.1 |
| cervicale height (mm) | 1416 | 1517 | 1622.9 | 1300.2 | 1393 | 1498 |
| acromion-radiale (upper arm) | 307 | 335 | 365 | 283.2 | 311 | 340 |
| radiale-stylion (forearm) | 244 | 267 | 295 | 218 | 240.5 | 268 |
| hand length | 177 | 193 | 210 | 165 | 180 | 199 |
| foot length | 250 | 271 | 293 | 226 | 246 | 267.8 |
| trochanterion height | 824 | 899 | 985 | 774.2 | 844 | 919 |
| lateral malleolus height | 64 | 73 | 83 | 54 | 63 | 71 |

The report (p. 192): men stature "5TH 164.80 ... 50TH 175.50 ... 95TH 187.00" cm, mean 175.62, SD 6.86, N 4082;
women 152.50 / 162.60 / 174.00 cm, mean 162.85, SD 6.42, N 1986.

**Used:** the six presets' stature and mass (`Proportions.PRESETS`); the cervicale-height fraction (men 1517 / 1755,
women 1393 / 1626) places C7 on the neck for the centre of mass.

## 2. Segment lengths as a fraction of stature: Drillis & Contini 1966

Drillis, R. & Contini, R. (1966), *Body segment parameters*, Report 1166-03, NYU School of Engineering; as drawn in
Winter, D.A., *Biomechanics and Motor Control of Human Movement*, Fig. 4.1, p. 83 ("Body segment lengths expressed as
a fraction of body height H"). Read from https://courses.grainger.illinois.edu/me481/sp2021/Anthro-Winter.pdf, the
figure rendered at 400 dpi. Three decimals (the table's precision). No male / female split.

| item | fraction of H |
|---|---|
| upper arm | 0.186 |
| forearm | 0.146 |
| hand (wrist -> fingertip) | 0.108 |
| foot length | 0.152 |
| shoulder height | 0.818 |
| hip joint (greater trochanter) height | 0.530 |
| knee height | 0.285 |
| ankle height | 0.039 |
| thigh = 0.530 - 0.285 | 0.245 |
| shank = 0.285 - 0.039 | 0.246 |
| trunk (hip -> shoulder) = 0.818 - 0.530 | 0.288 |
| head + neck (shoulder -> vertex) = 1 - 0.818 | 0.182 |

Winter: "These segment proportions serve as a good approximation in the absence of better data, preferably measured
directly from the individual."

**Used:** a preset's segment scales make upper arm, forearm, hand, thigh, shank and foot exactly these fractions of
its stature. **This mannequin's ankle joint stands 0.1037 m up a 1.829 m body (0.057 H, the table says 0.039)**, and a
uniform foot scale cannot shorten the ankle height and keep the foot length, so one segment must give: the trunk takes
the difference. Measured at the 50th-percentile man: trunk 0.273 (table 0.288), head + neck 0.185 (0.182), shoulder
height 0.815 (0.818), hip joint 0.542 (0.530; ANSUR trochanterion 899 / 1755 = 0.512).

## 3. Segment masses and centres of mass: de Leva 1996

de Leva, P. (1996). Adjustments to Zatsiorsky-Seluyanov's segment inertia parameters. *J. Biomech.* 29(9):1223-1230,
Table 4, p. 1228 (read from the page image, https://ebm.ufabc.edu.br/wp-content/uploads/2013/12/Leva-1996.pdf).
Caption: "Adjusted parameters for females (F; body mass = 61.9 kg, stature = 173.5 m [sic: 1.735]) and males (M;
73.0 kg, 1.741 m)". CM = % of the segment's length from its first endpoint.

| segment | endpoints | mass % F / M | CM % F / M |
|---|---|---|---|
| head | VERT -> CERV (alternative endpoints) | 6.68 / 6.94 | 48.41 / 50.02 |
| trunk | CERV -> MIDH (alternative endpoints) | 42.57 / 43.46 | 49.64 / 51.38 |
| upper arm | SJC -> EJC | 2.55 / 2.71 | 57.54 / 57.72 |
| forearm | EJC -> WJC | 1.38 / 1.62 | 45.59 / 45.74 |
| hand | WJC -> MET3 | 0.56 / 0.61 | 74.74 / 79.00 |
| thigh | HJC -> KJC | 14.78 / 14.16 | 36.12 / 40.95 |
| shank | KJC -> LMAL | 4.81 / 4.33 | 44.16 / 44.59 |
| foot | HEEL -> TTIP | 1.29 / 1.37 | 40.14 / 44.15 |

(The main rows use VERT -> MIDG for the head, 58.94 / 59.76, and SUPR -> MIDH for the trunk, 41.51 / 44.86; the
skeleton has a point for cervicale, none for the gonions or suprasternale, so the CERV rows are used.)

**Used:** `Proportions.com` (a body with proportions): each segment's mass at its CM fraction between its endpoints in
the pose (cervicale = a point on the neck bone at ANSUR's cervicale height, the hand's MET3 = the hand bone's end, the
heel and toe tip = the mesh's). A limb segment longer than Drillis' for its stature is heavier by (length ratio)^3;
the presets' limbs are Drillis' exactly, so their masses are de Leva's table. The default body (no "body" key) keeps
the old `Balance.MASS` model (male, capsule middles) byte for byte.

## 4. Height of the whole-body centre of mass

Croskey, M.I., Dawson, P.M., Luessen, A.C., Marohn, I.E. & Wright, H.E. (1922). The height of the center of gravity in
man. *Am. J. Physiol.* 61:171-185, Table 3, p. 181 (scanned issue on the Internet Archive,
`sim_american-journal-of-physiology_1922-06-01_61_1`). 50 men, 50 women: **56.18 % (men), 55.44 % (women)** of body
length from the soles. Measured SUPINE on a balance plank, arms pressed to the sides, as a percentage of the lying
length.

Hellebrandt, F.A., Tepper, R.H., Braun, G.L. & Elliott, M.C. (1938), *Am. J. Physiol.* 121:465ff, Table 1 p. 467:
women 55.174 % (357, SD 0.835) and 55.195 % (88); also measured in recumbency.

**Not found:** a reaction-board COM height measured in quiet STANDING as a fraction of standing stature.

**Measured on Kine** (tests/proportions_test.gd bar 3, standing, arms at the sides, de Leva on the preset bodies):
man 50th 0.5717 (+1.76 % vs 0.5618), woman 50th 0.5692 (+2.68 % vs 0.5544). The bar (1 %) FAILS. Known contributors:
the hip joint stands at 0.542 H (section 2; real ~0.51-0.53), which lifts the trunk's and thighs' centres; and the
reference is supine, as a fraction of lying length.

## 5. The mannequin as shipped (measured, assets/mannequin.glb)

Highest vertex at rest y = 1.82918 m, lowest 0.00046 m: stature 1.82872 m. Left foot's heel z = -0.09771, toe tip
z = 0.20544 (foot length 0.3032 m = 0.166 H). Upper arm 0.27444 m (0.150 H), forearm 0.27264 (0.149 H), wrist to middle
fingertip 0.2322 (0.127 H), thigh 0.40031 (0.219 H), shank 0.42948 (0.235 H). So the shipped body is a long-headed,
short-upper-armed figure; the presets correct it to the table.
