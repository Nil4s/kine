# People: the real-world numbers behind Poser's Check (round 41, #332)

One entry per rule in `scripts/rulebook.gd` (`Rulebook.SRC`). Each says: the source and its link, the numbers taken from
it, the constant or rule that uses them, and the test that checks them. The one-line bars and links are also in
`docs/MOTION_RULES.md`; this page is the longer "who measured it" record. `tests/people_doc_test.gd` fails if a rule has
no entry here, or if a link here is neither a rulebook source link, a `MOTION_RULES.md` link, nor marked `[background]`.
Where a bar is ours and not a paper's, the entry says so. A figure that could not be read at its source is marked
"unverified".

## SEQUENCE
- Source: ISBS 2015 conference paper on the hitting sequence, 3 hitters: https://ojs.ub.uni-konstanz.de/cpa/article/view/6368/5737
- Numbers: pelvis 389, trunk 601, bat 1953 deg/s peak speeds, in that order (hips, then chest, then the weapon).
- Used by: `Rulebook.rule_sequence` (hips, chest, weapon peaks in the 0.5 s before the tip's peak, `SWING_LEAD`).
- Tested by: `tests/rules_test.gd`, `tests/fix_test.gd`.

## HIPS TURN
- Source: the same ISBS study: https://ojs.ub.uni-konstanz.de/cpa/article/view/6368/5737
- Numbers: the hitters' pelvis peak 389 deg/s. The bar is a quarter of it (`HIPS_MIN` = 97 deg/s), deliberately loose
  because the study is 3 recreational hitters.
- Used by: `Rulebook.rule_sequence` (the HIPS TURN part), const `HIPS_MIN`.
- Tested by: `tests/rules_test.gd`, `tests/fix_test.gd`.

## HEAD QUIET
- Source: Inkster et al., as reported in the SABR review: https://sabr.org/journal/article/baseball-swing-stride-and-head-movement-relationships/
  The primary Inkster paper was not found (unverified); the figure is the review's.
- Numbers: hitters' heads drop about 9 cm over the whole swing; skilled hitters are steadier (Nakata, same review).
- Used by: `Rulebook.rule_head`, consts `HEAD_WARN` 0.15 m (9 cm + 6 cm grace), `HEAD_FAIL` 0.30 m, `HEAD_WIN`.
- Tested by: `tests/rules_test.gd`, `tests/fix_test.gd`, `tests/fix_window_test.gd`.

## TIP SPEED
- Source: our own table, `docs/ATTACK_RULES.md` (pro bat about 36.8 m/s in the ISBS-cited study).
- Numbers: caps bat 40, staff 30, knife 15, hammer 30, spear 20 m/s.
- Used by: `Rulebook.rule_weapon`, `tools/attack_timing.gd` `TIP_MAX`.
- Tested by: `tests/rules_test.gd`, `tests/fix_test.gd`, `tests/fix_window_test.gd`.

## STRIKE FRAMES
- Source: Aztez, "Anatomy of a Successful Attack" ("rarely more than 6 frames"), via `docs/ATTACK_RULES.md` (no link).
- Numbers: the swing itself at most 6 frames at 30 fps (bat 6, knife 4, spear 4).
- Used by: `Rulebook.rule_weapon`, `tools/attack_timing.gd` `RULES`.
- Tested by: `tests/rules_test.gd`.

## FIST SPEED
- Sources: Stanley et al. 2018, lead hook: https://chesterrep.openrepository.com/entities/publication/0acdae9d-e8be-48cf-816e-ed9c667981b3
  and Piorkowski et al. 2011, straight punch: https://clok.uclan.ac.uk/3757/1/piorkowski-et-al-2011-punch-kinematics.pdf
- Numbers: lead hook 11.95 +- 1.84 m/s; straight 9.26 +- 2.09 m/s.
- Used by: `Rulebook.rule_fist`, consts `FIST_WARN` 11.95, `FIST_FAIL` 11.95 + 2 x 1.84 = 15.6 m/s.
- Tested by: `tests/rules_test.gd`.

## HITCH
- Source: Flash & Hogan 1985, J. Neurosci. 5(7):1688-1703 (a journal citation; no free link).
- Numbers: a point-to-point movement has one bell-shaped speed peak.
- Used by: `Rulebook.rule_hitch`, consts `HITCH_DIP` 0.3, `HITCH_SPAN` 3 frames, `HITCH_FAST` 1 m/s (the thresholds are ours).
- Tested by: `tests/rules_test.gd`, `tests/fix_test.gd`, `tests/fix_window_test.gd`.

## BALANCE
- Source: de Leva 1996, J. Biomech. 29(9):1223-1230: https://doi.org/10.1016/0021-9290(95)00178-6
- Numbers: each body part's share of body mass (head 6.94, pelvis 11.17, spine parts 8.165 each ...; `scripts/balance.gd`,
  `docs/AGENT_MATH.md`).
- Used by: `Balance.read`, `Rulebook.rule_balance`, consts `BAL_OUT` 3 cm and `BAL_RUN` 6 frames (the bar is ours: a flicker is momentum).
- Tested by: `tests/balance_test.gd`, `tests/fix_test.gd`.

## LOOP SEAM
- Source: none outside Poser. Our own bars (3 deg, 2 cm, 0.5 m/s), set from what reads as a pop at a normal camera
  distance; 0.5 m/s is HITCH's scale. See `docs/MOTION_RULES.md`.
- Numbers: 3 deg, 2 cm, 0.5 m/s.
- Used by: `Rulebook.rule_loop`, consts `LOOP_DEG`, `LOOP_GAP`, `LOOP_JUMP`.
- Tested by: `tests/loop_test.gd`.

## FOOT SLIDE
- Source: Karunratanakul et al. 2023 (the foot-skating metric, as used by OmniControl): https://arxiv.org/pdf/2310.08580
- Numbers: a foot is down under 5 cm and skates when it slides over 2.5 cm. The "settled" gate (5 mm a frame) and the
  per-stretch measure are ours.
- Used by: `Rulebook.rule_feet`, consts `FOOT_DOWN` 0.05, `FOOT_SKATE` 0.025, `FOOT_STILL` 0.005.
- Tested by: `tests/rules_test.gd`, `tests/plant_test.gd`, `tests/fix_test.gd`.

## THROUGH A PROP
- Source: none outside Poser. Our own bars.
- Numbers: 5 mm is the resting allowance (a cushion gives that much), 2 cm reads as passing through.
- Used by: `Rulebook.rule_props`, `Props.depth`, consts `PROP_WARN`, `PROP_FAIL`, `SOLE_SINK`.
- Tested by: `tests/prop_check_test.gd`, `tests/carry_test.gd`, `tests/carry_form_test.gd`.

## FLOATS
- Source: none outside Poser. Our own bars.
- Numbers: under 2 cm is resting, over 15 cm is not "meant to sit", 0.1 s as BALANCE.
- Used by: `Rulebook.rule_floats`, consts `FLOAT_MIN`, `FLOAT_MAX`, `FLOAT_RUN`.
- Tested by: `tests/prop_check_test.gd`.

## JUMP
- Sources: Bosco (flight time to height) and Asmussen & Bonde-Petersen (journal citations, no free link); DeVita & Skelly 1992,
  landing knee flexion: https://pubmed.ncbi.nlm.nih.gov/1548984/
- Numbers: height h = g T^2 / 8 from the flight time T; a recreational adult's countermovement jump 0.40 +- 0.11 m (0.57 s);
  dip to about 90 deg of knee bend before take-off; soft landing about 117 deg, stiff about 77 (59 cm drop).
- Used by: `Rulebook.jumps`, `Rulebook.rule_jump`, consts `JUMP_HIGH` 0.70 m, `JUMP_DIP` 30 deg, `JUMP_LAND` 45 deg
  (all three set below the people numbers); `Scene.flights`.
- Tested by: `tests/jump_test.gd`, `tests/jump_ui_test.gd`.

## CARRY FORM
- Sources: Anderson et al. 2007, anterior load carriage: https://stacks.cdc.gov/view/cdc/189155 ; Snook 1978 (journal
  citation: 26% more load is accepted at knuckle than at elbow height); the NIOSH lifting equation, Applications Manual
  https://www.cdc.gov/niosh/docs/94-110/ [background] (the page loads; the 25 cm and 25/H figures are the equation's).
- Numbers: the load rides at knuckle-to-elbow height on bent elbows (about 90 deg) with the upper arms down; hands 25 cm
  in front of the ankles is the NIOSH ideal, and the multiplier 25/H is 0.63 at 40 cm.
- Used by: `Rulebook.carry_form`, `Rulebook.rule_carry_form`, consts `CARRY_UP` 35 deg, `CARRY_FLEX` 50-130 deg, `CARRY_H` 0.40 m
  (the bars are ours, set around those postures).
- Tested by: `tests/carry_form_test.gd`.

## LIFT FORM
- Sources (all read on PubMed this round): Saraceni et al. 2021, PLoS ONE (PMID 34288926) https://pubmed.ncbi.nlm.nih.gov/34288926/ ;
  Int J Sports Med 2025 (PMID 40368419) https://pubmed.ncbi.nlm.nih.gov/40368419/ ; Shu et al. 2007, J Appl Biomech
  (PMID 18089925) https://pubmed.ncbi.nlm.nih.gov/18089925/ ; Bazrgari et al. 2007, Eur Spine J (PMID 17103232)
  https://pubmed.ncbi.nlm.nih.gov/17103232/ ; Burgess-Limerick & Abernethy 1997, Hum Factors (PMID 9302886)
  https://pubmed.ncbi.nlm.nih.gov/9302886/ [background] (the postural index: stoop near 0, full squat near 1).
- Numbers: peak knee flexion in floor lifts 91.5 / 115.1 deg (without / with low back pain, lift 1) and 85.9 / 95.5 deg
  (lift 95); a stoop is knees 0-30 deg and a squat 0-60 / 0-90 / free in the 2025 study; the multifidus quiets as torso
  flexion goes from 45 to 60 deg; stoop lifts give larger thorax, lumbar and pelvis rotation and larger spinal loads than squat.
- Used by: `Rulebook.lift_form`, `Rulebook.rule_lift_form`, consts `LIFT_TRUNK` 60 deg and `LIFT_KNEE` 30 deg
  (the two bars are ours, set from those papers).
- Tested by: `tests/lift_form_test.gd`.

## GAIT
- Sources (abstracts and full texts read this round): step length over height: Gait Posture 2009, effect of age on centre-of-mass
  motion, 21 young adults, PMID 19502061 https://pubmed.ncbi.nlm.nih.gov/19502061/ (full text PMC3199953); cadence: PMID 29775941
  https://pubmed.ncbi.nlm.nih.gov/29775941/ and PMID 41879248 https://pubmed.ncbi.nlm.nih.gov/41879248/ (controls); arm swing:
  Yamaguchi et al. 2025, Cureus, PMID 40291287 https://pubmed.ncbi.nlm.nih.gov/40291287/ and PLoS One 2012, PMID 23236504
  https://pubmed.ncbi.nlm.nih.gov/23236504/ ; arm-leg phase: Kubo et al. 2004, Biol Cybern, PMID 15351887
  https://pubmed.ncbi.nlm.nih.gov/15351887/ (abstract: with speed the arm-to-leg frequency goes 2:1 to 1:1 and the two arms in-phase to out-of-phase).
- Numbers: step length / height 0.415 +- 0.038 and 1.326 +- 0.133 m/s (height 1.73 +- 0.11 m, n 21); cadence 105.5 +- 5.2
  steps/min (speed 1.21 +- 0.08 m/s, n 22) and 108 +- 7 (1.4 +- 0.1 m/s, n 27); arm swing peak to peak 28.6 +- 11.5 (right) /
  33.1 +- 11.0 (left) deg at 4 km/h, n 21 men, sagittal rotation of the upper arm; a median 25.27 (2.3-31.8) right and 25.71
  (5.2-38.2) left deg, n 10 healthy adults, at a median 3.82 km/h. The arm-leg counter-phase is read from the Kubo abstract
  only (no r value in any source): a sign test, mine. Not found: a single paper giving step/height AND cadence AND shoulder
  angle for one group, so the three come from three groups.
- Used by: `Rulebook.gait`, `Rulebook.rule_gait`, consts `GAIT_STEP` 0.30-0.55, `GAIT_CAD` 75-135, `GAIT_ARM` 10-60 deg,
  `GAIT_PHASE` 0.3 (all bars are ours, about 3 SD around the means; `GAIT_CROWN` 0.14 m head joint to crown is also ours).
- Tested by: `tests/gait_test.gd`.

### BREATH
- Quiet breathing moves the chest wall surface 1-8 mm at 0.17-0.33 Hz (10-20 breaths a minute): Massaroni et al. 2015,
  IEEE EMBC 1291-4, https://doi.org/10.1109/EMBC.2015.7318604 (round 43 YY6: the chest front moves 4.9 mm at 15/min). [background]
- The inhale/exhale shape (a raised cosine, in = out) and the 1 deg clavicle lift: MINE, no number.

### HANDS (round 43, YY3: not a Check rule; the numbers Body.hand_curl is built on)
- Source: active finger flexion in 390 hands, Indian J Plast Surg 2024 [background] https://pmc.ncbi.nlm.nih.gov/articles/PMC11436331 ;
  the tip joint following the middle one, theta_DIP = 0.76 theta_PIP closing a fist (Hahn et al. 1995, index finger,
  in the review table of [background] https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9541616/ ; other fingers' fitted slopes 0.41-0.76).
- Numbers: knuckle (MCP) 84-87 deg -> CURL_MCP 85; middle joint (PIP) 97.2 (index) -> CURL_PIP 97.2; DIP = 0.76 PIP
  -> 73.9 at curl 1. SPREAD (fan at the knuckles) is MINE, not data.
- RELAXED: the resting finger cascade, Varghese et al., J Clin Diagn Res 2020;14(5):YC01-07, Table 13 (250 non-power-grip
  workers, dominant hand, goniometer) [background] https://jcdr.net/articles/PDF/13677/ ; knuckle / middle / tip:
  index 27.1 / 38.7 / 13.8, middle 33.2 / 40.7 / 14.2, ring 29.3 / 44.8 / 14.3, little 26.2 / 43.1 / 16.1. Thumb's rest MINE.
- Used by: Body.hand_curl / hand_point / hand_curl_of; the HANDS curl and spread sliders.
- Tested by: tests/hand_curl_test.gd.

### WALK LEGS (round 43, YY0: what scene.gd's WALK playback is measured against)
- Source: Perry, Gait Analysis (knee ~5-10 at mid-stance, 60-65 swing peak, ~35-40 at toe-off; ankle ~20 plantarflexed
  at toe-off); foot-ground angle at toe-off 60.3 +- 5.1 at 4.5 km/h (49.4 at 3, 68.5 at 6), Eckelt et al. 2026, PMID
  41583941; step length 0.415 of height, PMID 19502061.
- Numbers: see tests/walk_legs_test.gd's header (bars and walk_bat's measured values).
- Used by: Scene TOE-OFF / STANCE / SWING (cards with "walk").
- Tested by: tests/walk_legs_test.gd, tests/gait_test.gd.

## JOINT SPEED
- What it checks: each frame, how fast a joint turns (its rotation relative to the part it hangs from: shoulder, knee, hip,
  trunk) against the fastest turn recorded in a person. Opt-in with "Check: could a human do this?".
- Source: `docs/research/HUMAN_LIMITS.md`. Shoulder internal rotation 4766 +- 772 deg/s (Campbell, ISBS); knee in a kick
  1874 deg/s (Manolopoulos 2006) and hip 745 deg/s (Nunome 2002), both via a kick review's table; trunk 601 deg/s (ISBS 2015).
- Numbers: WARN over the recorded peak (shoulder 4766, knee 1874, hip 745, trunk 601 deg/s); FAIL over 6310, 2184, 1117,
  901. The shoulder and knee FAIL bars come from the sources' spread; the hip and trunk FAIL bars are MINE (1.5x). Elbow and
  neck are not graded (no verified number).
- What to do: give the turn more time (move the cards apart), or shorten the swing; a snap that fast reads as a cut, not a body.
- Used by: `HumanLimits.rule_speed`, consts `SPEED`, `TURN`; `Rulebook.check` when the human-limits check is on.
- Tested by: `tests/human_limits_test.gd`.

## JOINT TORQUE
- What it checks: the net moment at the knee and the shoulder from inverse dynamics (point masses, de Leva 1996 shares;
  rotation left out, so a lower bound) against recorded strength. OFF in the default Check (it read 508 Nm at the shoulder
  for a two-handed bat swing, because the model hangs the whole bat on each arm), on when asked for.
- Source: `docs/research/HUMAN_LIMITS.md`. Men's isokinetic knee extension at 60 deg/s 184.7 +- 44.1 Nm (healthy adults,
  mixed-age excerpt); shoulder internal rotation 0.70 +- 0.15 Nm/kg at 60 deg/s (handball study excerpt).
- Numbers: WARN over the mean (knee 184.7 Nm for 75 kg, scaled by (mass/75)^(2/3); shoulder 0.70 Nm/kg x mass); FAIL over
  mean + 2 SD (273 Nm; 1.00 Nm/kg). The mass scaling is MINE. A fast motion is compared with a slow strength test.
- What to do: lighten what is held, share it between two hands, or give the move more time; a torque flagged on a heavy
  two-hand swing may be the model's lack of load sharing, not the pose.
- Used by: `HumanLimits.rule_torque`, `knee_limit`, `shoulder_limit`, consts `KNEE_NM`, `SHOULDER_NM_KG`.
- Tested by: `tests/human_limits_test.gd`.

## TIPPING
- What it checks: the centre of mass past the support polygon, with a foot down and no hand or weapon holding on, for
  longer than a fall takes.
- Source: the free-fall time of the centre of mass from its height, t = sqrt(2h/g): MINE, as a bar (generous: a stumble
  that is caught is allowed). Context in `docs/research/HUMAN_LIMITS.md`.
- Numbers: FAIL when the run lasts longer than t = sqrt(2h/g), about 0.43 s at h 0.9 m. A hand or the weapon within 2 cm of
  a surface (or the floor) counts as holding on.
- What to do: bring a foot under the weight, put a hand on something, or shorten the lean.
- Used by: `HumanLimits.rule_tipping`, consts `GRAV`, `TOUCH`.
- Tested by: `tests/human_limits_test.gd`.
