# TRUNK LEAN: sources, numbers, and which limits are HEURISTIC

The trunk is the line pelvis -> neck_01, read per frame at 60 fps in the hips' frame (pitch + forward, roll + his left).
Standing tall reads 0 once the skeleton's own 4.0 deg rest offset is taken off (`TrunkLean.rest_pitch`).
Code: `scripts/trunk_lean.gd` (TRUNK LEAN, WARN), `scripts/smart_drag.gd` (TRUNK_FOLLOW). Test: `tests/trunk_test.gd`.

## Why it moved
Smart drag (`main.gd:488`, on by default) let a limb drag follow the library's co-variation. Kicks lean back in the
library, so a right foot drag to kick height leaned the trunk 13.5 deg (pitch) with smart drag on and 0 with it off.
Fix: a limb drag keeps the pelvis's tilt, lets the pelvis twist, and lets the spine follow at most 4 deg of bend and
of side bend in all (spread over spine_01..03).

## Sources
- **Kim, Yenuga & Kwon 2008**, ISBS, roundhouse, n=12 black belts. https://ojs.ub.uni-konstanz.de/cpa/article/view/2005
  Ranges (ROM, not absolute lean): pelvis-to-global mediolateral 60.2 +- 7.6, AP 30.5 +- 8.1; trunk-to-pelvis flex/ext
  21.7 +- 7.4, lateral 16.8 +- 4.2, axial 52.8 +- 11.0.
- **Gavagan & Sayers 2017**, PLoS ONE, doi:10.1371/journal.pone.0182645. Pelvis posterior tilt ROM: Muay Thai 71 +- 9,
  Karate 77 +- 9, Taekwondo 75 +- 8. No trunk angles.
- **Blaszczyszyn et al. 2019**, IJERPH, doi:10.3390/ijerph16173155. Mae-geri torso flexion (Plug-in Gait, probably
  relative to the pelvis): advanced 14.8-21.6, beginners 25-29.6; frontal toward the kicking leg 7.7-18.7; no SD.
  Taken from a summary: the tables still need checking against the paper.
- **Chung et al. 2010**, J NeuroEng Rehabil, doi:10.1186/1743-0003-7-9. Walking trunk vs ground: tilt range 4.0 +- 1.8,
  obliquity range 3.3 +- 1.4, mean tilt -0.2 +- 3.6. Source of TRUNK_FOLLOW = 4 and of the 5 deg drag bar.
- **Krebs et al. 1992**, Phys Ther, doi:10.1093/ptj/72.7.505. Trunk ROM during gait <= 12 deg (abstract only).
- Side kick and punches: no measured trunk angle found. Hidayat 2026 (doi:10.3389/fphys.2025.1708748) defines the angle
  but reports no values; Dinu & Louis 2020 (doi:10.3389/fspor.2020.598861) was checked too.

## The ranges in trunk_lean.gd (deg: back, forward, lateral)
| move | back | fwd | lateral | status |
|---|---|---|---|---|
| roundhouse | 40 | 25 | 45 | HEURISTIC |
| side kick | 40 | 25 | 55 | HEURISTIC |
| front kick | 30 | 25 | 25 | HEURISTIC |
| knee | 30 | 30 | 25 | HEURISTIC |
| jab | 10 | 25 | 20 | HEURISTIC |
| cross | 10 | 30 | 25 | HEURISTIC |
| hook | 10 | 30 | 30 | HEURISTIC |
| uppercut | 15 | 30 | 25 | HEURISTIC |
| general (no move named) | 25 | 60 | 30 | HEURISTIC |
| TRUNK_FOLLOW (limb drag) | 4 | | | HEURISTIC, from Chung 2010 walking range |
| FIX_MARGIN | 3 | | | HEURISTIC |

No row is a direct reading of one source: the sources give ROM, flexion on another reference, or walking angles, and
none measures a side kick or a punch. Every row is a HEURISTIC working norm, not a measured limit.
Lateral norms on kicks are tight in the windows just after the kick: the typed roundhouse and side kick read roll
33-35 deg there and are flagged by 3-9 deg. Undecided: widen the knee/general lateral norm, or give the window after a
kick the kick's norm.

## The fix (Fixer, one Ctrl+Z)
1. Spine first (spine_01..03, a third each, limits kept). The spine turns the trunk line about 0.4 deg per deg
   (its joints sit low), and its limits (bend -7..20 each) stop it near 19 deg of trunk.
2. Then the pelvis for the rest. The trunk line starts at the pelvis, so a pelvis tilt turns it 1 deg per deg. The
   pelvis moves the legs, so the kicking foot is reached back onto its contact point and each planted foot is put
   back on its ball (`Body.plant`); a punching fist is re-reached (`Body.reach`).
Only pitch is fixed this way; a sideways finding gets the spine only.

## Measured
- Limb drag (test bar 1, smart drag and keep balance on, 24 mouse moves): foot_r dragged 78 cm: trunk pitch 1.9,
  roll 1.3, spine bend 3.8, side 1.4, pelvis tilt 0.00. Hand_r dragged 52 cm: pitch 0.4, roll 1.9, spine bend 0.8,
  side 0.5. Before the fix the same foot drag leaned the trunk 13.5 deg (handoff's measurement, a separate tool).
- Fix (bar 2, 3): the 50 deg back roundhouse kick is flagged (20 deg past the front kick's range of 30); at 20 deg
  back it is not. After the fix every window is inside its range; the planted ankles stay within 0.00 cm of their
  marks. The kicking contact moved 3.9 cm (bar 3 is 3 cm): NOT YET MET.

## Sign note
The first run's bisection looked sign-wrong (pelvis bend -100 gave +81 deg forward). The cause was the test's kick
pose, not the angle maths: pelvis twist 110 and side 35 turned the bend's axis, so bend tipped the trunk sideways and
the bisection ran away. With the pelvis bent alone, pelvis bend + tips the trunk forward (+30 -> +30.0; -30 -> -30.0,
printed by the test's sign check) and the bisection direction is the original one.
