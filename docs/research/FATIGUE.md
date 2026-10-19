# Fatigue: strikes slow as a fight goes (ROADMAP 39)

Code: `scripts/fatigue.gd`; command "Fatigue: slow the fight as it goes..." (main.gd `fatigue()`); test `tests/fatigue_test.gd`.

## Measured data

| Source | Subjects, protocol | Result |
|---|---|---|
| Sensors 2025, 25(11):3270, doi 10.3390/s25113270 (Evaluation of the Impact of External Conditions on Arm Positioning During Punches in MMA Fighters) | 21 elite male MMA fighters, maximal punches normal vs fatigued, 3 trials each | straight punch 8.4 +- 0.6 -> 7.5 +- 0.7 m/s (-10.7 %); swing punch 7.1 +- 0.5 -> 6.4 +- 0.6 m/s (-9.9 %); p < 0.01. Impact force -10.6 % / -10.7 %. |
| Bioengineering 2025, 12(12):1355, doi 10.3390/bioengineering12121355 (Stewart et al.) | 10 amateur boxers, 9.5 min lower-body circuit, six punch types | punch force -4.26 % on average (p = 0.027); -9.84 % for the weakest punches, -4.63 % for the strongest |
| Sensors 2020, 20(20):5749, doi 10.3390/s20205749 | 6 elite boxers, 11 sets of 5 s maximal punching, 5 s rest | glove acceleration fell significantly over the protocol (no single percentage extracted); dominant side fatigued more |

The velocity anchor is the first row: mean decline **10.3 %** (`DECLINE_REF`). The force study brackets it (4 to 10 %).
Not verified: the abstracts were read, the first row's numbers come from its full text; the fatigue protocol of the
first row is not described in the text I could fetch, so "a fatigued fighter" is its only definition. The Sci 2024 paper
(Penna et al., doi 10.3390/sci8060141) reports a progressive decline of punch intensity across rounds, no percentage found.

## The fit

- State F in 0..1. Work: F -> 1 - (1 - F) exp(-dt / 25 s). Rest (a hold of 1.5 s or more): F -> F exp(-dt / 30 s).
- A strike at state F runs at speed 1 - decline x F; its move (and hold) is retimed by 1 / speed with `Scene.retime`.
- decline = 0.103 x (1 - fitness) / (1 - 0.5), so fitness 0.5 (default, the elite fighters measured) gives the cited
  10.3 % at F = 1, fitness 1 gives none, fitness 0 gives 20.6 % (an extrapolation, no data).
- TAU_UP 25 s is a modelling choice: it makes a 60 s fight without rest reach F = 0.91 (test: last strike 9.1 % slower vs
  cited 10.3 %, bar +-2 points). The 11 x 5 s protocol (55 s of work) is of the same order. TAU_REC 30 s: phosphocreatine
  resynthesis half-time is about 20-30 s in textbooks; not checked against a paper here.
- Strikes are the cards a `hit` marker lands on (within 0.1 s of the arrival); markers follow the retime so contact
  still lands on the target pose.

## Limits

Only strikes slow (the wind-up and footwork keep their time); one decline for every strike type; no per-round reset;
the time constants are not fitted to a time series (none found), only to the end-of-protocol size.
