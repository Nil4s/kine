# Human limits: the numbers "Check: could a human do this?" grades a move against

Code: `scripts/human_limits.gd` (called from `Rulebook.check`). Rules: JOINT SPEED, JOINT TORQUE, TIPPING.
Status key: **read** = the number was read in the source's own text or table; **excerpt** = it came from a search
engine's excerpt, the full paper was not opened; **secondary** = quoted by a review, the primary was not read.

## 1. Joint angular speed (deg/s)

| joint | bar (WARN = the published peak; FAIL) | source | status |
|---|---|---|---|
| shoulder (internal rotation) | 4766 / 6310 | Campbell, pitchers, ISBS, Table 2: 4765.7 +- 771.9 deg/s; FAIL = mean + 2 SD | read (already in `docs/COMPLAINTS.md`) |
| knee (extension in a kick) | 1874 / 2184 | Manolopoulos et al. 2006, amateur males: 1874 (155) deg/s; FAIL = + 2 SD. The fastest recorded group mean in the table below | read, in Table 4 of a kick review ([PMC3786235](https://pmc.ncbi.nlm.nih.gov/articles/PMC3786235)) |
| knee, other kick groups | 1134-1805 | Elliott 1980, Rodano & Tavana 1993, Barfield 2002, Lees & Nolan 2002, Levanon & Dapena 1998 (1805, 289), Nunome 2002 (1364, 298), Barfield 1995, Kellis 2006 | read, same table |
| hip (flexion in the forward swing) | 745 / 1117 | Nunome et al. 2002, high-school players, quoted by the kick review | secondary. The FAIL bar is 1.5 x the peak: MY choice, no SD was found |
| trunk (chest turn, hitting) | 601 / 901 | ISBS 2015, the hitters' chest peak (already in the repo's SEQUENCE rule) | read, in the repo. FAIL = 1.5 x, MY choice |
| elbow | not graded | a pitching review gives elbow extension 2030 +- 220 deg/s, and Werner 1993 gives 2300 deg/s (40 rad/s) | excerpt only; no paper with the numbers was opened, so no bar |
| neck | not graded | none found | none |

Joint turn = the joint's rotation relative to the part it hangs from (shoulder to clavicle, knee to thigh, hip to pelvis,
trunk to pelvis). A turn is measured per 60 fps frame; a run of frames over the bar is one finding.

## 2. Joint torque (net moment from inverse dynamics)

Point masses at the segment centres (de Leva 1996 shares and centre fractions, `Proportions.DE_LEVA`), accelerations by
the second difference of each centre at 60 fps. Rotational inertia is LEFT OUT, so the moments are lower bounds: a
finding can only be missed, not invented, by that choice. Distal segments: knee = shank + foot; shoulder = forearm + hand.
The weapon is not included.

| joint | bar (WARN = the mean; FAIL = mean + 2 SD) | source | status |
|---|---|---|---|
| knee (extension, isokinetic) | 184.7 / 273.1 Nm for a 75 kg man, scaled by (mass / 75)^(2/3) | a healthy-adult table (men 184.7 +- 44.1 Nm, 60 deg/s, all ages): [Springer, SpringerPlus 2015, table 2](https://springerplus.springeropen.com/articles/10.1186/s40064-015-1357-0/tables/2) | excerpt. The mixed-age mean is LOWER than the 250-300 Nm that trained young men reach. The FAIL bar lands at the 250-300 range, which is why it is used. The 75 kg reference and the 2/3 exponent are MY choices (muscle size scales with mass^(2/3)) |
| shoulder (internal rotation, concentric) | 0.70 / 1.00 Nm/kg x body mass | handball study, 108 players: dominant 0.70 +- 0.15 Nm/kg at 60 deg/s | excerpt; the paper's title was not identified. The moment is the whole shoulder's net moment, compared with the rotators' strength: an approximation, stated |
| hip, elbow, trunk, neck | not graded | a trunk review (Isokinetics & Exercise Science 2012) and a South African elbow study (438 males) hold Nm tables; not read | none verified, so no bar |

## 3. Tipping (centre of mass past the support)

The support is the same polygon Balance uses (both feet, or one, on the floor). A run of frames with the centre of
mass past it, a foot down, and no hand or weapon holding (a hand or the weapon's tip within 2 cm of a surface or the
floor) is a finding when it lasts longer than **t = sqrt(2 h / g)**, h the centre of mass's height at the run's start.
Standing (h about 0.9-1.0 m) the bar is about 0.43 s. A real body outside its base starts to fall at once, so this bar
is GENEROUS: it allows a stumble that is caught in time. The bar is the free-fall time of the centre of mass, as asked;
it is not a tipping-dynamics result.

## What is NOT graded yet
- Elbow, hip (torque), trunk and neck torque: no verified strength number.
- Elbow speed: a number exists (2030 +- 220 deg/s, pitching) but not from a paper that was opened.
- Weapon inertia and the weapon's load on the hand: not in the moments.
- Strength by sex and age: the knee bar uses the mixed-age male mean.
