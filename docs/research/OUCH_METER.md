# Ouch meter: comfortable vs maximum range (N064)

Code: `scripts/ouch_meter.gd`. Test: `tests/ouch_test.gd`. Trust rows: `scripts/trust.gd` (`OuchMeter.*`).

While a joint is dragged on the POSE page, the dragged part glows:

| zone | token | meaning |
|---|---|---|
| green | `ok` | inside the comfortable range |
| yellow | `warn` | past comfortable, inside the max |
| red | `fail` | at or past the max: the one-joint table (`data/body_limits.json`) or, for the legs, the two-joint muscle bar (N028, `scripts/coupled_limits.gd`, at its healthy-adult level) |

## What was opened

| source | what it gives | how it was read |
|---|---|---|
| Kee D, Karwowski W (2001). LUBA: an assessment technique for postural loading on the upper body based on joint motion discomfort and maximum holding time. *Applied Ergonomics* 32(4):357-366. doi:[10.1016/S0003-6870(01)00006-0](https://doi.org/10.1016/S0003-6870(01)00006-0) | Perceived-discomfort scores for joint motion classes (sitting S, standing P). **Elbow flexion: 0-45 deg score 1 / 1; 45-120 deg score 2 / 3; > 120 deg score 5 / 5.** Pronation 0-70: 2, > 70: 7. Supination 0-90: 2, > 90: 7 | The paper itself is paywalled. Its class table is reproduced in INSST **NTP 674** (*Evaluación de la carga postural: método de la Universidad de Lovaina / método LUBA*, 2004), Table 2, which was opened ([insst.es](https://www.insst.es/documentacion/colecciones-tecnicas/ntp-notas-tecnicas-de-prevencion/19-serie-ntp-numeros-646-a-680-ano-2004/ntp-674.-evaluacion-de-la-carga-postural-metodo-de-la-universidad-de-lovaina-metodo-luba.-)). The elbow row reads cleanly. The neck, trunk, shoulder and wrist rows came out interleaved in the page's HTML and could not be matched to their joints without guessing, so **they are not used** |
| McAtamney L, Corlett EN (1993). RULA: a survey method for the investigation of work-related upper limb disorders. *Applied Ergonomics* 24(2):91-99. doi:[10.1016/0003-6870(93)90080-S](https://doi.org/10.1016/0003-6870(93)90080-S) | **Lower arm: 60-100 deg score 1; 0-60 deg or > 100 deg score 2.** Upper arm: -20..+20 score 1, > 20 extension or 20-45 score 2, 45-90 score 3, > 90 score 4. Wrist: up to 15 deg score 2, more than 15 deg score 3 | The DGUV/IFA RULA worksheet (an extract from BGIA-Report 2/2007), opened as a PDF ([dguv.de](https://presse.dguv.de/medien/ifa/de/pub/rep/pdf/rep07/biar0207/rula.pdf)). RULA scores **load and risk at work**, not end-range pain. It also penalises a straight elbow (0-60), which is not a strain when nothing is held |

Looked for but **not opened** (paywalled; only their abstracts or search snippets were seen, so no number from them is used):

- Kee D, Karwowski W (2001). The boundaries for joint angles of isocomfort for sitting and standing males based on perceived comfort of static joint postures. *Ergonomics* 44(6):614-648. doi:10.1080/00140130110038044. Per-joint "joint angles of isocomfort" as % of the maximum ROM. A search snippet says the hip had the smallest comfortable share of all joints and the elbow the largest. That would make one fraction for every joint lenient at the hip. This is not verified.
- Naddeo A, Cappetti N, Vallone M (2019). Assessment of ranges of rest postures of human lower limbs. *Work* 63(2):219-229. doi:10.3233/WOR-192916. Comfort ROM and rest-posture ranges for the hip, knee and ankle (114 adults). No numbers were reachable.
- REBA (Hignett & McAtamney 2000, *Applied Ergonomics* 31(2):201-205). Its leg score (knee flexion 30-60 / > 60) is load while weight-bearing, not a comfort range. It is not used.

## The numbers Kine uses

| constant | value | trust | from |
|---|---|---|---|
| `OuchMeter.ELBOW_COMFORT` | 120 deg | MEASURED (the class boundary). Taking the score jump from 3 to 5 as "past comfortable" is our reading | LUBA elbow flexion, via NTP 674 Table 2 |
| `OuchMeter.ELBOW_COMFORT_RULA` | 100 deg | MEASURED (the RULA band edge). It is the fraction's anchor, not a drawn bar | RULA lower arm, DGUV worksheet |
| `OuchMeter.COMFORT_FRAC` | 0.7 | **HEURISTIC** | Ours. Every joint without its own row is comfortable up to neutral + 0.7 x (the table's stop - neutral) on each side. It is anchored on RULA's elbow 100 / 145 = 0.69. Using one fraction for every joint is our choice |
| `OuchMeter.TOL` | 0.5 deg | HEURISTIC | "At the max" means within `Body.at_limit`'s 0.5 deg rounding |
| max (table) | per joint | UNVERIFIED there | `data/body_limits.json` (AAOS / Soucie quoted, not opened). The elbow's 145 and the hip's 120 come from here |
| max (coupled, legs) | a curve | as N028 | `docs/research/COUPLED_LIMITS.md`. Hip flexion with the knee straight: 90 (straight-leg raise, Thomas et al. 2022, doi:10.1186/s13102-022-00599-8) |

Worked bars, read from the code (the test checks them to within 1 deg):

| joint | green | yellow | red |
|---|---|---|---|
| elbow (lowerarm bend) | 0 .. 120 | > 120 | >= 144.5 (the table's 145) |
| hip flexion, knee straight | 0 .. 84 (0.7 x 120) | > 84 | >= 89.5 (the hamstring bar 90, not the table's 120) |
| hip flexion, knee bent 60 | 0 .. 84 | > 84 | >= 119.5 (the table: the hamstrings slacken) |
| knee with the hip at 110 | the knee must stay bent >= 40 (N028 read backwards): <= 40.5 is red |

## Rules that are ours (HEURISTIC, stated)

- **Neutral** is 0, Kine's rest, on every axis except the upper arm's side axis. That axis's rest is the arm down at the side (-90; `data/body_limits.json` "say").
- **A stop at neutral is not judged.** An elbow or knee that is straight (bend 0) is at the bone's own stop and at rest, not under strain, so a one-way joint is green there. A coupled floor (a knee that must stay bent because the hip is high) is still judged.
- **Red uses the coupled bar at its healthy-adult level** (CoupledLimits' WARN curve: "most people cannot"), not the trained-body FAIL curve. The meter is about where an ordinary body starts to hurt.
- **Comfortable never lies past the effective max.** If a coupled bar falls below the comfortable bar, the comfortable bar drops to it.
- **The pelvis is not judged.** Its angles are the whole body's orientation, not a joint.
- **Hand or foot drags on IK** light the worst joint of the chain (elbow, then shoulder; knee, then hip).
- **All three axes are judged.** The worst one is shown, and on a tie the one furthest toward its stop.

## Open

Per-joint comfortable bars for the hip, knee, ankle, shoulder, wrist, neck and spine need the Kee & Karwowski 2001 *Ergonomics* JAI tables or Naddeo 2019 to be opened. Until then those joints use `COMFORT_FRAC` and say HEURISTIC.
