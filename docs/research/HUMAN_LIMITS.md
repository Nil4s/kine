# Human limits: the numbers "Check: could a human do this?" grades a move against

Code: `scripts/human_limits.gd` (called from `Rulebook.check` when `HumanLimits.on`). Rules: JOINT SPEED, JOINT TORQUE,
TIPPING. Round 2 (wt-limits2): the speed bars are now the PEAKS recorded in sport, not the fastest of a mixed list; the
torque model was rebuilt (segment rotational inertia, the bat shared between the hands); the knee torque bar is gone.

Status key: **read** = the number was read in the paper's abstract or full text; **excerpt** = it came from a search
engine's excerpt, the full paper was not opened; **secondary** = quoted by a review, the primary was not read;
**not read** = the paper could not be opened (paywall), so the number is not used.

FAIL bar rule (MINE, applies to every speed bar): FAIL = 1.32 x WARN. 1.32 = 1 + 2 x (SD / mean) with the SD / mean of
Campbell's shoulder table (771.9 / 4765.7 = 0.162). No source here gives an SD for the other joints, so the same factor
is used for all of them.

## 1. Joint angular speed (deg/s): WARN = the in-sport peak, FAIL = 1.32 x

| joint | old WARN / FAIL | new WARN / FAIL | source for the new WARN | status |
|---|---|---|---|---|
| shoulder (internal rotation) | 4766 / 6310 | **6520 / 8632** | collegiate fastball shoulder internal rotation velocity, 6520 deg/s, quoted by Fortenbaugh, Fleisig & Andrews 2009, Sports Health 1(4):314-320 ([DOI](https://doi.org/10.1177/1941738109338546), [PMC3445126](https://pmc.ncbi.nlm.nih.gov/articles/PMC3445126)) | full text of the REVIEW read; the collegiate study it cites was not read. The review also gives the youth-to-pro range: the professional mean in Pappas et al. 1985 is 6180 deg/s (abstract read, [PMID 4025673](https://pubmed.ncbi.nlm.nih.gov/4025673/)). The "~7000 deg/s" in the brief was NOT found in any source I could open |
| upper trunk (chest turn, pitching) | 601 / 901 (hitting, ISBS 2015) | **1120 / 1478** | fastball upper trunk rotation velocity, collegiate pitchers, 1120 deg/s, Fortenbaugh 2009 (same review) | review read; primary not read. The brief's 900-1300 range is consistent with it |
| trunk (chest turn, hitting) | (same bar as above) | covered by the 1120 bar | adult hitters' peak upper torso angular velocity 857 deg/s (Escamilla et al. 2009, J Appl Biomech 25:210, [PMID 19827470](https://pubmed.ncbi.nlm.nih.gov/19827470/)): abstract read, the lower sport figure | the Welch et al. 1995 hitting paper (JOSPT 22(5):193-201) is the source the brief names for 900-1300 deg/s; it is **not read** (paywalled, no full text found), so its number is NOT used |
| knee (extension in a kick) | 1874 / 2184 | **1874 / 2481** | Manolopoulos et al. 2006, amateur males, 1874 deg/s, the fastest GROUP MEAN in Table 4 of a kick review ([PMC3786235](https://pmc.ncbi.nlm.nih.gov/articles/PMC3786235)) | table read; the 2006 paper not read. This is a mean of amateurs, not an individual's peak: a real peak is higher. Nick's scenes reach 2200-3000 deg/s in three scenes (section 4) |
| hip | 745 / 1117 | **not graded** | Nunome et al. 2002 (a kick mean of high-school players, via the same review) | secondary only, and a mean rather than a sport peak. Removed from the rule rather than tuned to a scene |
| elbow | not graded | not graded | Fortenbaugh 2009: fastball elbow extension 2210 deg/s (collegiate), curveball 2160 | the elbow is not in the rule's joint list (its turn is not measured in `TURN`); a bar would need that change too |
| neck | not graded | not graded | none found | none |

Joint turn = the joint's rotation relative to the part it hangs from (shoulder to clavicle, knee to thigh, trunk to pelvis).
A turn is measured per 60 fps frame; a run of frames over the bar is one finding.

## 2. Joint torque (the shoulder's net moment from inverse dynamics)

Model (rebuilt in round 2):
- The shoulder's distal load = the forearm and the hand (point masses at de Leva's centres, male or female shares,
  `Proportions.DE_LEVA`), each with its rotational inertia **I alpha** about its centre: I = m (k L)^2, with the
  transverse radius of gyration k from de Leva 1996 Table 4 (sagittal and transverse radii averaged, male forearm 0.2705 L,
  male hand 0.2585 L, female 0.2590 and 0.2235). The spin about the segment's own axis is not seen from its ends: left out.
- **The bat**: when the bat is held, its mass is 0.9 kg (MINE: a typical 33-inch adult bat; not read), its centre 0.6 of its
  length from the knob (MINE), a uniform rod about its own centre (I = m L^2 / 12, MINE). The bat's load is shared: **one
  hand** takes all of it; **both hands** (the second grip) take half each, each about its own shoulder (MINE: an equal
  split; a split by hand position would need the grip geometry, not done). The off-hand dagger is not in the model.
- Each load gives (centre - shoulder) x m (a - g) + I alpha; the sum is the joint moment. Accelerations are central second
  differences at 60 fps. Upper arm and clavicle are not in the sum (their moment about the shoulder is not added: a lower
  bound, stated).

| joint | bar (WARN = the in-sport peak; FAIL = 1.32 x) | source | status |
|---|---|---|---|
| shoulder (internal rotation, dynamic) | **67 Nm / 88.7 Nm** for a 75 kg body, scaled linearly with body mass (MINE) | Fleisig, Andrews, Dillman & Escamilla 1995, AJSM 23(2):233-239, "67 N-m of shoulder internal rotation torque" in 26 highly skilled adult pitchers, shortly before maximum external rotation ([PMID 7778711](https://pubmed.ncbi.nlm.nih.gov/7778711/), [DOI](https://doi.org/10.1177/036354659502300218)) | abstract read. The paper's mean body mass was not read, so the mass scaling is MINE. Fleisig's model includes the upper arm; ours does not (see above). Youth pitchers: 32-35 Nm (Dun et al., via Fortenbaugh 2009, secondary) |
| knee (isokinetic, OLD bar 184.7 / 273 Nm) | removed | — | the old bar was an isokinetic strength test at 60 deg/s. The brief asks for in-sport moments. I found no in-sport knee extension MOMENT with a number in an abstract I could read: Lyle et al. 2011 (MSSE, [PMID 21448083](https://pubmed.ncbi.nlm.nih.gov/21448083/)) gives the swing hip flexor moment (1.22 vs 1.07 N m kg-1 m-1) and no knee moment number; the full text was not opened. Aagaard et al. 1996 is isokinetic and was excluded |
| hip, elbow, trunk, neck | not graded | — | none verified in sport |

## 3. Tipping (centre of mass past the support)

The support is the same polygon Balance uses (both feet, or one, on the floor), which is the shadow of the foot capsules
(balance.gd says this is lenient: a wider footprint than a real foot). A run of frames with the centre of mass past it, a
foot down, and no hand or weapon touching a surface (a hand or the weapon's tip within 2 cm of a surface or the floor), is
a finding when it lasts longer than **t = sqrt(2 h / g)**, h the centre of mass's height at the run's start (the
free-fall time of the centre of mass: our bar, not a tipping-dynamics result).

Round 2 finding: the rule flags 4 of Nick's 11 scenes (section 4). A hand holding a bat in the air does not count as
support (it is not touching a surface), so these are leans of 4-15 cm past the shadow of the feet for 0.7-2.5 s with a
foot down. The support polygon's own error (the shadow is not the real foot) is of the same order as those margins.
**Tipping stays off by default.**

## 4. Nick's scenes (read only), round 2 bars, default body (75 kg), `HumanLimits.sample` + `findings`

Peak turn (deg/s) against the WARN bars; FAIL is the next bar. Torque is the shoulder moment, opt-in.

| scene | shoulder_r / _l | knee_r / _l | trunk | speed FAIL | speed WARN | tipping FAIL | shoulder moment peak (Nm, bar 67 / 88.7) |
|---|---|---|---|---|---|---|---|
| combo3 (bat swing) | 1558 / 658 | 1373 / 2204 | 1087 | — | knee_l 2204 (+18%) | 1 (1.00-1.65 s, 15 cm, 0.67 s) | 1269 r / 513 l |
| swing_fore | 1012 / 658 | 587 / 1966 | 1087 | — | knee_l 1966 | 1 (1.00-2.30 s) | 312 / 513 |
| swing_back | 1049 / 502 | 387 / 297 | 692 | — | — | — | 745 / 335 |
| strike_legs | 1276 / 262 | 653 / 1140 | 903 | — | — | — | 1179 / 114 |
| thrust | 1260 / 1237 | 868 / 2757 | 704 | knee_l 2758 (+47%) | — | — | 998 / 529 |
| dodge_side | 793 / 275 | 2904 / 1361 | 158 | knee_r 2904 (+55%) | — | — | 113 / 151 |
| bo_spin | 1016 / 635 | 719 / 3027 | 81 | knee_l 3027 (+62%, 2 runs) | 1 more (not printed) | 1 (0-2.43 s, 4 cm) | 1146 / 1291 |
| bo_sweep | 1370 / 329 | 0 / 0 | 0 | — | — | 1 (0-1.83 s, 12 cm) | 90 / 184 |
| hit_react | 954 / 494 | 1179 / 661 | 658 | — | — | — | 174 / 258 |
| idle_bat | 22 / 7 | 209 / 186 | 17 | — | — | — | 7 / 5 |
| walk_bat | 46 / 223 | 1000 / 730 | 56 | — | — | — | 11 / 18 |

Reading: the trunk now passes everywhere (combo3 peaks at 1087, under the 1120 bar). The shoulder turn passes except the
0.05 s test swing. The knee is the one that fails (3 scenes), and the knee bar is a mean of amateurs (section 1). The
shoulder moment is far above 67 Nm in the dynamic scenes, so it stays opt-in. Two explanations, neither verified: the
moment is dominated by the bat's inertial load with accelerations taken from 60 fps second differences (combo3's bat tip
moves about 0.3 m between frames at the peak, so the accelerations are large and spiky), and the bat mass and centre are
assumed (section 2). Idle and walk give 5-18 Nm, consistent with the static load of a 0.9 kg bat at 0.6 m (about 5 Nm), so the
static part is plausible; the dynamic part is what is unverified.

## 5. What is NOT graded yet, and why
- Hip speed, elbow speed and every torque except the shoulder: no verified in-sport peak in hand (section 1-2).
- Knee torque: no in-sport knee moment number from an abstract I could read.
- The Welch et al. 1995 hitting numbers: not read (paywall). The 900-1300 deg/s range in the brief is therefore unverified.
- Mass: the sport papers' body masses were not read, so the torque and the knee bar scale with mass by MY choice.
- The shoulder moment leaves out the upper arm; the bat's mass, centre and the hand split are MINE.
- Tipping: the support polygon's error is as large as the margins it grades (section 3).
