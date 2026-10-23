# Coupled limits: two-joint muscles (N028)

`data/body_limits.json` limits one joint at a time. Three leg muscles cross two joints, so the range of one joint
depends on the other. `scripts/coupled_limits.gd` holds each coupling as a curve: the bar on one joint's bend as a
piecewise-linear function of the knee's bend. The cited points below are joined by straight lines and held flat past
the last point. Each curve is continuous by construction and rises with knee bend (`tests/coupled_test.gd` checks both).

Every source below was opened on 2026-10-23 (PubMed Central full text or the publisher's page). Numbers are copied from
the paper's own text or table.

## Angles in Kine

- thigh bend + = hip flexion, - = hip extension, measured against the PELVIS (the thigh's parent).
- calf bend = knee flexion, 0 = straight.
- foot bend + = toes up (dorsiflexion), 0 = the rest (T-pose) foot.

The clinical straight-leg raise is measured against the table, so it includes some pelvic tilt. We read the same
number against the pelvis, which is lenient. (The size of the pelvic share was not looked up.)

## Hamstrings: hip flexion vs knee flexion

| point | value | source |
|---|---|---|
| knee 0 (straight-leg raise), healthy adults | 90 deg (the four baselines are 86.7, 89.7, 90.1 and 91.1, SD about 22) | Thomas E, Ficarra S, Scardina A, et al. 2022. *Positional transversal release is effective as stretching on range of movement, performance and balance.* BMC Sports Sci Med Rehabil 14:202. [doi:10.1186/s13102-022-00599-8](https://doi.org/10.1186/s13102-022-00599-8). 32 healthy, moderately active students (13 F / 19 M, 25 y). Passive SLR with an inertial sensor; the other leg strapped. |
| knee 0, female team-sport athletes | 91.0 +- 7.2 and 92.4 +- 6.9 | Donti O, Gaspari V, Papia K, Panidi I, Donti A, Bogdanis GC. 2020. *Acute Effects of Intermittent and Continuous Static Stretching on Hip Flexion Angle in Athletes with Varying Flexibility Training Background.* Sports 8(3):28. [doi:10.3390/sports8030028](https://doi.org/10.3390/sports8030028). Supine SLR to discomfort, pelvis and the other thigh strapped, camera markers at hip, knee and ankle. |
| knee 0, gymnasts (FAIL bar) | 140.9 +- 20.4 and 141.8 +- 20.3 | Donti 2020, the same test: 14 artistic and rhythmic gymnasts. |
| slope | 0.5 deg of hip per deg of knee bend | HEURISTIC (ours). A two-joint muscle lengthens by r_hip dHip - r_knee dKnee, and we take the knee/hip moment-arm ratio as about one half. No moment-arm paper was opened. |
| top | 120 deg, reached at knee 60 | the one-joint table's thigh bend max (UNVERIFIED there: AAOS / Soucie are quoted, not opened). |
| cross-check | at hip 90, the knee stays 24.9 +- 9.3 deg short of straight (active knee extension test) | Hamid MSA, Ali MRM, Yusof A. 2013. *Interrater and Intrarater Reliability of the Active Knee Extension (AKE) Test among Healthy Adults.* J Phys Ther Sci 25(8):957. [doi:10.1589/jpts.25.957](https://doi.org/10.1589/jpts.25.957). 14 healthy adults (28-39 y), no warm-up, active test. Our curve lets any knee bend reach hip 90, so it is about 12 deg LENIENT here. We say so and do not fit to it. |

Curve: `[[0, 90], [60, 120], [145, 120]]`.
- WARN: past the curve (past most adults).
- FAIL: the curve + 51 (the gymnasts' mean). FAIL is past the table's 120, so it cannot fire while the table clamp holds: a
  straight-leg kick tops out at a WARN. That is the honest answer: a trained kicker can do an axe kick.

## Gastrocnemius: ankle dorsiflexion vs knee flexion

Source: Baumbach SF, Brumann M, Binder J, et al. 2014. *The influence of knee position on ankle dorsiflexion - a
biometric study.* BMC Musculoskelet Disord 15:246. [doi:10.1186/1471-2474-15-246](https://doi.org/10.1186/1471-2474-15-246),
PMC4118219. 20 healthy adults (27 y, 50 % female), goniometer, knee braced at 0 / 20 / 30 / 45 / 60 / 75 deg. Table 2:

| knee | weight-bearing (R / L) | non-weight-bearing (R / L) |
|---|---|---|
| straight | 25 +- 7 / 24 +- 6 | 4 +- 8 / 4 +- 7 |
| 20 deg | 39 +- 7 / 37 +- 6 | 20 +- 9 / 18 +- 7 |
| 75 deg | 39 +- 7 / 38 +- 7 | 21 +- 9 / 20 +- 9 |

The paper also says: "knee flexion beyond 20 deg could not further increase ADF".
- Curve: `[[0, 25], [20, 39], [145, 39]]`. We use the weight-bearing row, the case of a standing body; it is lenient for a
  foot in the air. The line between 0 and 20 deg is ours, because the paper has no point in between.
- FAIL: mean + 2 SD (+14).
- Kine's one-joint table already stops dorsiflexion at 25 for every knee angle. So this coupling never binds today, and
  with the knee bent Kine is about 14 deg STRICTER than a real ankle. `limits` says "the table is tighter". Raising the
  table is a separate decision, because it would change saved poses.

## Rectus femoris: hip extension vs knee flexion (the Thomas test)

| point | value | source |
|---|---|---|
| knee about 50 deg (hanging) | hip -10.60 +- 9.61 deg (the thigh below the table's line) | Ferber R, Kendall KD, McElroy L. 2010. *Normative and Critical Criteria for Iliotibial Band and Iliopsoas Muscle Flexibility.* J Athl Train 45(4):344. [doi:10.4085/1062-6050-45.4.344](https://doi.org/10.4085/1062-6050-45.4.344), PMC2902027. 300 recreational athletes, digital inclinometer. |
| the knee's angle in that test | 50 +- 12 deg | Peeler JD, Anderson JE. 2008. *Reliability limits of the modified Thomas test for assessing rectus femoris muscle flexibility about the knee joint.* J Athl Train 43(5):470. [doi:10.4085/1062-6050-43.5.470](https://doi.org/10.4085/1062-6050-43.5.470), PMC2547866. 54 adults, 18-45 y. |
| knee 90 | hip 0 (the thigh flat) | Kendall's pass criterion as Peeler 2008 quotes it. A clinical cut-off, not a mean: HEURISTIC. |
| knee past 90 | held at 0 | no source opened: lenient. |
| knee 0 | -25 | the one-joint table's thigh bend min (UNVERIFIED). |

Curve: `[[0, -25], [50, -10.6], [90, 0], [145, 0]]`.
- The Thomas points come from a gravity hang, not an end range pushed by a tester, so they are on the strict side.
- FAIL: the curve - 2 SD (-19.2).
- Also opened: Eimiller et al. 2024, Int J Sports Phys Ther 19(8):997,
  [doi:10.26603/001c.120899](https://doi.org/10.26603/001c.120899). Modified Thomas test with a neutral pelvis enforced:
  hip extension 5.43 +- 9.73 deg in 64 healthy adults. Not used: it sits within one SD of Ferber, and the knee angle is
  not given.

## Not built: shoulder/elbow (biceps), wrist/finger (finger flexors)

The biceps (shoulder extension with the elbow straight) and the finger flexors and extensors (tenodesis: fingers curl
when the wrist extends) are two-joint too. No opened source gave numbers for the coupled range, so Kine does not
invent a curve for them.

## Where it is used

- Check: `HumanLimits.findings` (on with "could a human do this?"), rule `COUPLED LIMIT`. WARN past the healthy-adult
  curve, FAIL past the trained one. Every finding names the muscle, the bar, the source and both ways out ("bend the
  knee to 40 deg, or lower the leg to 90 deg").
- `Feasible.check`: FAIL findings only. A WARN is a range a trained person has, so it does not make a clip infeasible.
  `Rulebook.check` lists a coupled finding once (HumanLimits'), not twice.
- `Body.coupled_clamp`: opt-in, 0 by default. 1 keeps the legs inside the healthy-adult curves while posing; 2 uses the
  trained curves. It is off by default because Nick's saved poses would silently change under a default-on clamp.
  `set_ang_safe` reports a coupled stop as `last_stop.kind = "coupled"` with the reason.
- serve `limits {joint, other_angles?}`: the effective bend range (table, healthy adult, trained), with the why and the
  source of each coupling.
- Nick's scenes (`scenes/*.json`): none is flagged. Their highest straight-ish hip is 85 deg with the knee at 59
  (`axe_strike_pose`, inside its 120 bar). The `bo_spin` back leg (hip -17, knee 25) sits 1 deg inside its -18 bar, and
  `swing_fore`'s recover (hip -25, knee 0) is exactly at the table.
