# Whole-body speed caps (N031): how hard the body as a whole can start, stop, cut, rise and fall

Code: `scripts/body_caps.gd` (rule **BODY ACCEL**, in the human-limits set: `HumanLimits.findings`, on with "Check: could a
human do this?"). Test: `tests/bodycaps_test.gd`. Trust rows: `scripts/trust.gd` (`BodyCaps.*`). Facts: `scripts/human_facts.gd`
(`body_accel`, `body_decel`, `body_cut`, `jump_push`, `fall_rate`). I47 (`scripts/speed_env.gd`) caps the limbs; this caps the
centre of mass (COM).

Status words as in `HUMAN_LIMITS.md`: **read** = the number was in text opened on 2026-10-23; **derived** = arithmetic on read
numbers, shown; **ours** = a choice of this code.

## The caps (m/s^2)

| channel | WARN (trained) | FAIL (elite) | source | status |
|---|---|---|---|---|
| START (speeding up along the way it goes) | **10** | **11** | Haugen, Breitschaedel & Seiler 2019, "Sprint mechanical variables in elite athletes: are force-velocity profiles sport specific or individual?", PLoS ONE 14(7):e0215551, doi [10.1371/journal.pone.0215551](https://doi.org/10.1371/journal.pone.0215551). 666 athletes, 23 sports, 128 world / Olympic medallists. "F0 in the present sample was in the range 7-10 N/kg for men and 6-9 N/kg for women"; world-class male / female sprinters ~11 / ~10 N/kg as the paper cites them | read (the discussion text; the per-sport table is an image and the S1 file was not opened). The ~11 is the paper's citation of other work, its primary not opened |
| STOP (slowing down) | **8.48** | **11.02** | Harper, Mcburnie, Santos, Eriksrud, Evans, Cohen, Rhodes, Carling & Kiely 2022, "Biomechanical and neuromuscular performance requirements of horizontal deceleration: a review with implications for random intermittent multi-directional sports", Sports Med 52(10):2321-2354, doi [10.1007/s40279-022-01693-0](https://doi.org/10.1007/s40279-022-01693-0) (PMC9474351). Table 1: Harper et al., 20 m sprint to stop, "Peak DEC (m/s^2) = -8.48" (average -4.44). Table 2: Kaneko et al., youth soccer 505 test, "Peak DEC: fast COD = -11.02, slow = -9.60" | read (the review's tables; the primaries not opened) |
| CUT (across the way it goes) | **11.5** | **13.1** | Yamashita, Inaba, Asakura & Ito 2025, "Center of mass direction and speed during a 45-degree change of direction task performed with maximal effort", Front Sports Act Living 7:1576614, doi [10.3389/fspor.2025.1576614](https://doi.org/10.3389/fspor.2025.1576614). 10 male American football skill players (7 highly trained / national, 3 elite / international), approach 6.66 +- 0.29 m/s. Table 2: execution-step medial impulse 1.75 +- 0.12 Ns/kg, stance 0.152 +- 0.008 s | read; the m/s^2 are **derived**: 1.75 / 0.152 = 11.5 (the mean medial acceleration over the plant step), (1.75 + 2 x 0.12) / 0.152 = 13.1 (mean + 2 SD, the 2 SD **ours**). The following step: 1.02 / 0.149 = 6.8 |
| RISE (pushing up while going up: a take-off) | **14.7** net | **19.0** net | Lin, Goldstein & Schroeder 2025, "Sex- and sport-specific differences in jump strategies: key qualities for jump performance", Sports 13(9):292, doi [10.3390/sports13090292](https://doi.org/10.3390/sports13090292) (PMC12473443). Table 2, countermovement jump on a force plate, 38 NCAA D1 men: relative concentric peak force 24.51 +- 2.17 N/kg (30 women 22.07 +- 1.3) | read; **derived** net of g: 24.51 - 9.81 = 14.7; (24.51 + 2 x 2.17) - 9.81 = 19.0 (the 2 SD **ours**) |
| FALL (dropping faster than g) | - | **1.1 g** = 10.8 | physics: the feet only push, so with no hand holding on (`HumanLimits.supported`: a hand or the weapon within 2 cm of a surface) nothing pulls the COM down faster than free fall | g exact; the 10 % grace (`FALL_K`) **ours**, for the floor pass and the card blend |

Why these and not others:
- **START** uses F0, the horizontal force per kg at zero speed of the sprint force-velocity profile: the hardest push a
  runner makes, at the first steps. The force falls with speed (linear F-V, the paper's model), so holding the cap flat at
  every speed is lenient for a body already moving. The brief's "elite first step ~6-10 m/s^2" agrees with the 7-10 range.
- **STOP** is a peak deceleration (laser / radar speed curves, smoothed): people brake harder than they speed up (soccer
  match play, the same review: decelerations -5.7 to -6.3 vs accelerations 4.4-4.7 m/s^2).
- **CUT** is an impulse over a stance, so its acceleration is the stance average. That matches the signal below, which is
  also averaged over about one contact. A 45 deg cut is spread over three steps (15 deg on the plant step, 38 deg by two
  flights later), so a whole-body turn in one step at running speed is past what these athletes do.
- **RISE** is the force-plate PEAK of the push, instantaneous. Ours is averaged over 0.2 s, so it reads lower than a force
  plate would: lenient. The braking of a landing or of a countermovement (upward acceleration while still going down) is
  NOT graded here: landing loads are `scripts/stunt_load.gd`'s LANDING LOAD (docs/research/STUNT_LOAD.md), and real drop
  landings brake at several g.

## The signal

- The COM is `Balance.com` (de Leva 1996 segment masses at the middle of each capsule; a proportioned body uses
  `Proportions.com`), from the same 60 Hz frames `HumanLimits.sample` plays for Check (no second pass).
- Velocity v[i] = (c[i+3] - c[i-3]) / 0.1 s; acceleration a[i] = (v[i+3] - v[i-3]) / 0.1 s, which is the closed form
  (c[i+6] - 2 c[i] + c[i-6]) / 0.1^2 (the test recomputes it that way from a fresh sample). Clamped one-sided at the ends.
- Why not frame to frame: I47 (speed_env.gd `ANG_STEPS`) does not take one-step differences of joint angles either,
  because its papers are low-pass data and a keyed kink differenced over one step is a spike no body makes. The lurch
  survey (docs/MOTION_RULES.md) measured raw 60 fps accelerations of 336-377 m/s^2 in real landings and get-ups. The
  caps here are contact averages (F0 fitted to a smoothed speed curve; a 0.152 s stance), so the signal is averaged over
  about one contact too (0.1 s per difference, a 0.2 s triangle in all). A constant acceleration reads exactly; a step
  in velocity reads as dv / 0.1 s.
- Direction: the reference is the faster of the horizontal velocities 3 frames before and 3 after, so a body coming to
  rest is STOPPING to the end and one leaving rest STARTS from the first frame; under 0.05 m/s both ways (`STILL`) all
  horizontal acceleration counts as START.

## What it flags in Kine's scenes (measured 2026-10-23, `tests/bodycaps_test.gd` part 5 and a one-off survey)

- **Quiet**: walk_bat, every plain walk (`_wip/walk*.json`, peak start 4.1, stop 3.7-4.0), idle_bat, hit_react, the swings,
  the sword swings, the punches (`_wip/punch*`: 3.6 / 4.4), agent_fight, the ragdoll mirrors.
- **combo3**: two FAILs at the move into card 10 "Nick STRIKE (step)" (2.93-3.13 s): start 29.5, then stop 29.0 m/s^2. Checked by hand:
  the COM travels 30.5 cm forward over frames 170-187 and reaches 3.0 m/s, inside a 0.16 s card move: 0 to 3 m/s in about
  0.1 s. A real step-in does not do that; the fix gives the move more time (part 6 of the test).
- **_wip/walk_bat_phone***: 12 findings (start up to 22.4, a cut of 13.4): the phone-captured walk's keyed root jerks.
- **_wip/run**: start 11.2 in the first 0.12 s (from a standing first card straight to running pace) and a stop of 24.5
  at the end (the clip ends at full speed onto a held card).
- **axe_strike_pose** (a traced sequence of linear 0.2 s cards): 33 findings, 11-24 m/s^2, each a velocity kink at a card.
- **bo_spin**: up to 43.8 (the spin's body throw); **jump**: one WARN rise 17.4 (over the D1 mean, under mean + 2 SD);
  **get-ups / leap_slam / scene_mirrored**: rises of 22-50 and falls of 15-51 m/s^2 with no hand down (the floor pass
  dropping the hips faster than gravity).

## Fix

`BodyCaps.retime` (the Check panel's "Fix: give the body more time for this move", through `Fixer`): the moves of the cards
whose move lies within 0.2 s of the peak are lengthened, x sqrt(peak / (0.97 x cap)) per round (at least x1.05, at most x2),
re-measured each round, until that channel peaks under its WARN cap; only the cards' "move" changes, the later cards shift
later. Like every Fixer fix it is kept only if the finding is gone and the scene has no more FAILs.
