# Who could do this? (N027)

`scripts/who_could.gd` reads a clip and reports the minimum body that could do it, one capacity at a time. Where an
opened source gives a population distribution (a mean and an SD), the capacity is a percentile of that population.
Where none was opened, it gets a tier only (any adult / trained / elite / beyond), labelled HEURISTIC. If any capacity
is beyond a record or a physiological limit, the answer is "no human". Each constant has a `Trust.REG` row in
`scripts/trust.gd` (`WhoCould.*`). Serve: `who_could {card?} | {t0?, t1?}`. CLI: `whocould <scene.json> [card=N] [t0=S] [t1=S]`.

Sources were opened on 2026-10-23 (PubMed Central full text, Europe PMC abstracts, or the page named). Numbers are
copied from the paper's own table or text. The facts that were already in Kine (`human_facts.gd`, `coupled_limits.gd`,
`docs/physics_constants_i47.md`) are reused rather than copied again. The table below says where each one lives.

## Percentile and tier

- **Percentile** is the share of the stated population at or below the value, from a normal model with the paper's mean
  and SD. "Top X %" means 100 minus the percentile.
- **Tier** for a healthy-adult population: below the 75th percentile it is any adult; from the 75th to the 97.7th it is
  trained; from the 97.7th up it is elite. (The 97.7th percentile is mean + 2 SD.) HEURISTIC: both cuts are ours.
- **Tier** for a trained-fighter population (hand and foot speed): fixed speed cuts, listed below.
- **Overall** is the highest tier of any capacity. It is "no human" when any capacity is beyond.

## Flexibility: two-joint muscles

The hamstring demand is the hip's flexion, minus the slack the knee's bend buys on CoupledLimits' hamstring curve. A
straight knee buys no slack, so the demand equals the straight-leg raise. Hip extension (rectus femoris) and ankle
dorsiflexion (gastrocnemius) are worked out the same way from their own curves. See `docs/research/COUPLED_LIMITS.md`
for the curves.

| capacity | population | mean +- SD | source | trust |
|---|---|---|---|---|
| hip flexibility (straight-leg raise) | 32 healthy, moderately active students (13 F / 19 M, 25 y); passive SLR, Gyko inertial sensor, other leg strapped | 90 (CoupledLimits.HAM_STRAIGHT) +- 22 (`HAM_SD`). Table 1 T0: R 87.1 +- 22.6, 90.1 +- 22.9, 89.7 +- 21.7, 91.1 +- 21.7; L 86.7 +- 22.4, 89.7 +- 21.1, 90.8 +- 21.1, 90.1 +- 22.9 | Thomas E et al. 2022, BMC Sports Sci Med Rehabil 14:202, [doi:10.1186/s13102-022-00599-8](https://doi.org/10.1186/s13102-022-00599-8), PMC9714235 | MEASURED |
| (elite reference) gymnasts' SLR | 14 artistic and rhythmic gymnasts, camera | 140.9 +- 20.4 and 141.8 +- 20.3 (`CoupledLimits.HAM_TRAINED`, `GYM_SD`) | Donti O et al. 2020, Sports 8(3):28, [doi:10.3390/sports8030028](https://doi.org/10.3390/sports8030028), PMC7183084 (abstract) | MEASURED |
| hip extension (modified Thomas test) | 300 recreational athletes | 10.6 +- 9.61 deg extension with the knee hanging at 50 | Ferber et al. 2010, [doi:10.4085/1062-6050-45.4.344](https://doi.org/10.4085/1062-6050-45.4.344) (in COUPLED_LIMITS.md) | MEASURED |
| ankle dorsiflexion (weight-bearing, knee straight) | 20 healthy adults | 25 +- 6 (`ANKLE_SD`) | Baumbach et al. 2014, [doi:10.1186/1471-2474-15-246](https://doi.org/10.1186/1471-2474-15-246), Table 2 (in COUPLED_LIMITS.md) | MEASURED |
| beyond, any joint range | - | past mean + 4 SD of healthy adults (`BEYOND_SD`). For the straight-leg raise: past the gymnasts' mean + 2 SD | ours | HEURISTIC |

Check: a straight-leg kick at 110 deg gives z = (110 - 90) / 22 = 0.909, which is the 81.8th percentile ("top 18 %").
That is the trained tier. `tests/whocould_test.gd` holds the served percentile to within 5 points of this.

## Spine and shoulder: tier only (HEURISTIC)

No spine or shoulder range-of-motion distribution was opened. (AAOS and Soucie 2011 are quoted in
`data/body_limits.json`, but not opened.)

- Spine flexion: the bend of spine_01..03 summed, as a share of the table's sum (3 x 20 = 60 deg). Up to 0.75 of it is
  any adult, up to 0.95 is trained, more is elite.
- Shoulder: the upper arm's elevation from the trunk's down axis. Up to 170 deg is any adult. Past that, the arm is
  overhead and in line with the trunk, which is trained.

## Hand and foot speed

This is the peak world speed of either hand (`B.E hand_*`) or either ball of the foot (`B.E ball_*`), as a one-step
difference at 240 Hz. These are the same points and the same rate that I47 (`speed_env.gd`) uses.

| capacity | population (percentile among) | mean +- SD | tier cuts | sources | trust |
|---|---|---|---|---|---|
| hand speed | 15 male amateur boxers, lead hook, 3D mocap | 11.95 +- 1.84 m/s | any adult <= 6.317, trained <= 13.79 (I47's mean + 1 SD), elite <= 20.1, beyond > 20.1 | Stanley, Thomson, Smith, Lamb 2018, Int J Perf Anal Sport 18:835 (in physics_constants_i47.md). Junior boxers' lead straight peak velocity 6.317 +- 0.415 m/s (elite 7.162 +- 0.475; 16 boxers, Vicon 200 Hz): Chen et al. 2022, Front Physiol 13:1015154, [doi:10.3389/fphys.2022.1015154](https://doi.org/10.3389/fphys.2022.1015154), PMC9798280. Fastest punch: Guinness World Records, Keith Liddell, "registered at 45 miles per hour" (= 20.1 m/s), [Wikipedia](https://en.wikipedia.org/wiki/Keith_Liddell) citing guinnessworldrecords.com 2013 | distribution MEASURED; the any-adult cut HEURISTIC (an untrained adult's punch speed was not found, so the junior boxers' mean stands in); the record UNVERIFIED (the Guinness page was not opened, and a speed-puck reading is not a mocap peak) |
| foot speed | 8 taekwondo black belts, roundhouse | 14.66 +- 1.18 m/s | any adult <= 8.64 (Muay Thai 13.24 - 2 x 2.30), trained <= 15.84 (I47), elite <= 19.38 (mean + 4 SD), beyond above | Gavagan & Sayers 2017, PLoS ONE 12(8):e0182645, [doi:10.1371/journal.pone.0182645](https://doi.org/10.1371/journal.pone.0182645), Table 2 | distribution MEASURED; the cuts HEURISTIC (no record kick speed was found) |

## Jump power

A flight is a stretch where neither foot is within `Balance.TOUCH` of the floor for `FLIGHT_MIN` (0.05 s, HEURISTIC)
or longer. Its height is the centre of mass's rise from take-off (the last frame with a foot down) to the apex. This
is what flight-time countermovement-jump (CMJ) height measures. The take-off speed is sqrt(2 g h).

| reference | value | source | trust |
|---|---|---|---|
| men 26-30, CMJ, contact-mat flight time | 34.9 (8.5) cm, n = 54 (21-25: 34.6 (10.3); 31-35: 32.4 (7.8); women 26-30: 23.5 (6.4)) | Koivunen K, Laakkonen EK, Ahtiainen JP, Walker S 2026, Scand J Med Sci Sports 36(6):e70322, [doi:10.1111/sms.70322](https://doi.org/10.1111/sms.70322), PMC13280190, Tables 1-2. The authors say the young groups are athlete-heavy | MEASURED |
| elite: national-team sprinters (men) | 62.7 (4.8) cm, the highest of 989 national-team men | Haugen TA, Breitschädel F, Wiig H, Seiler S 2021, IJSPP 16(2):184, [doi:10.1123/ijspp.2019-0964](https://doi.org/10.1123/ijspp.2019-0964) (abstract) | MEASURED |
| no human: the NFL Combine's best vertical jump | 46.0 in = 1.168 m (Gerald Sensabaugh, 2005) | [Wikipedia](https://en.wikipedia.org/wiki/Gerald_Sensabaugh) citing DraftScout. A jump-and-reach with an arm swing, so it is generous against a centre-of-mass rise | UNVERIFIED |

The `human_facts.gd` fact `jump_height` (0.40 +- 0.11 m, UNVERIFIED there) is not used. Koivunen 2026 replaces it here.

## Not read

- **Strength** (for example, holding a lever: the centre of mass's moment about the support). This needs a detector
  for a held lever and an opened strength norm. Neither exists yet, so the output lists it under `not_read` and does
  not guess.
- **Reaction / contact timing**. This needs an opponent's cue. `scripts/counter.gd` judges it in a fight
  (Liu 2018, reaction 0.292 +- 0.045 s, in `human_facts.gd`).
