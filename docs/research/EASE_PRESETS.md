# Ease presets from real motion (ROADMAP item 17)

A card's `ease` shapes the move INTO that card. Presets added here: `reach`, `strike`, `throw`, `settle`. The old
presets (`smooth`, `linear`, `in`, `out`, `snap`) are unchanged. Code: `scripts/ease_presets.gd`; call site
`scripts/scene.gd` `_ease()`; test `tests/ease_presets_test.gd`.

Each preset is a progress curve e(x) on x in [0, 1], with e(0) = 0 and e(1) = 1. x is the joint's own progress
(scene.gd NATURAL overlap, LAG = 0.3, joint level L/6 delay), exactly as the existing presets use it.

## The formulas

**REACH (point-to-point arm move): minimum-jerk.**
e(x) = 10x^3 - 15x^4 + 6x^5. Speed e'(x) = 30x^2(1-x)^2, peak at x = 0.5, peak/mean = 1.875.
Source: Flash & Hogan (1985), "The coordination of arm movements: an experimentally confirmed mathematical model",
J. Neurosci. 5(7):1688-1703.
Note: under NATURAL this is the same polynomial the default `smooth` already uses (smootherstep). So `reach` adds a
name and a dropdown entry, not a new curve for the arm. The measured difference is with `linear` / `out` etc.

**STRIKE (punch, late peak): skewed bell.**
Speed v(s) = s^a (1-s)^b with a = K p, b = K (1-p), K = 4, and the peak at s = p.
e(x) = integral_0^x v / integral_0^1 v. With p = 0.5 this is exactly minimum-jerk, so REACH is the p = 0.5 member
of the family.
Used value: p = STRIKE_PEAK = **0.60**.
Status: **ours, not measured.** The literature check did not give a time-to-peak fraction for jab or cross. Xu, Mao &
Xi (2024), Front. Sports Act. Living 6:1441470, reports peak hand speed (cross 8.48 m/s SA) and no timing.
Piorkowski et al. (2011), Sports Biomechanics, reports delivery times (jab and cross shorter than hook) and no
time-to-peak. Replace 0.60 when a study gives the fraction; the test checks the constant, so it will need updating.

**THROW / SWING (proximal-to-distal): skewed bell with a peak per joint level.**
p(L) = THROW_P0 + THROW_STEP * L, THROW_P0 = 0.30, THROW_STEP = 0.08. Levels: pelvis 0 (0.30), spine 1 (0.38),
clavicle 2 (0.46), upper arm 3 (0.54), forearm 4 (0.62), hand 5 (0.70), fingers 6 (0.78). On top of the NATURAL
overlap, the peak time of level L is u_peak(L) = 0.3 L/6 + 0.7 p(L): 0.42, 0.53, 0.63, 0.74 for clavicle, upper arm,
forearm, hand (the test checks these within 0.02).
Source for the ORDER: Putnam (1993), as cited by later reviews (not fetched: secondhand); Leenen et al. (2022),
Front. Sports Act. Living 4:1044616, reports a proximal-to-distal sequence and a pelvis-to-trunk peak separation of
32.7 ms (95 % CI 21.1-44.4) in fastball pitching. Fleisig-group pitch data (Front. Sports Act. Living 2021,
doi 10.3389/fspor.2021.699251) found most pitches do not follow the ideal order: 14 patterns in 22 pitchers. So the
ORDER is sourced; the per-level FRACTIONS are **ours, not measured**.

**SETTLE (landing, sway): damped spring.**
Step response of x'' + 2 zeta wn x' + wn^2 x = wn^2, normalised so e(1) = 1:
s(x) = 1 - exp(-zeta wn x) (cos(wd x) + zeta/sqrt(1-zeta^2) sin(wd x)), wd = wn sqrt(1-zeta^2), e = s(x)/s(1).
Used values: zeta = SETTLE_ZETA = **0.7**, wn = SETTLE_WN = **8** rad per move length.
Result: overshoot about 4.7 %, peak e = 1.047 (test: 1.01 to 1.10).
Status: **ours.** Two searches (landing, postural sway) found no measured damping ratio: landing studies fit a
spring-damper (Gambelli et al. 2015 two-stage model, secondhand) and sway studies report stiffness, and the values
depend strongly on the fit method. The overshoot means a joint passes its card by about 5 % of the move and comes
back; it is then clamped to the body's limits by Body.clamp_ang, as every angle is.

## Behaviour and saving

- Only a card with `ease` set reads these; a scene without them plays bit-identically. The test hashes all 11
  scenes in `scenes/` at 60 Hz (sha256 recorded before the change): all match.
- Saved per card only when set (`"ease": "throw"`); `smooth` erases the key, as before.
- Not used inside a spline scene or a flow run (they have their own curves), as before.
- Dropdown: the card panel's `ease` list is `Scene.ALL_EASES`; the first five keep their indices.
- Commands: "Ease: <preset>" and "Card: ease like a real <preset>" (reach, strike, throw, settle).

## Test numbers (tests/ease_presets_test.gd)

| check | result |
|---|---|
| reach = 10x^3-15x^4+6x^5 | exact |
| reach speed peak | at 0.500 of the move; peak/mean 1.8750 (bar 2 %) |
| strike speed peak | at 0.599 (cited 0.60, bar 0.03) |
| throw, combo3 card 2 to 3, joints | peaks 0.421 / 0.529 / 0.633 / 0.739 for clavicle / upper arm / forearm / hand; predicted 0.422 / 0.528 / 0.634 / 0.740 |
| settle | e(0)=0, e(1)=1, overshoot 1.047 |
| old scenes (11) | sha256 of sampled angles unchanged |

## Not done

- The strike fraction (0.60) and the throw fractions (0.30 + 0.08 L) are not from a measured study. Only the throw
  ORDER is sourced. A measured time-to-peak per segment (a pitching or punching kinematics paper with the numbers in
  a table) should replace them.
- The settle damping ratio is not from a measurement.
- No "measured against a real clip" comparison yet (the see-video tool could take a real punch and fit the strike
  fraction; that is the next step).
