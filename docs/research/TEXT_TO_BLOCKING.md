# Type a move, get blocking (ROADMAP 22, top-25 #8)

"overhead axe strike, step in" becomes a scene of key poses: ready, ANTICIPATION, STRIKE, FOLLOW-THROUGH, RECOVERY,
as a NEW file under `scenes/_wip` (a taken name gets `_2`, `_3`...). Command: **Block out a move from words...**
(command search) opens the box. No outside model. `scripts/text_blocking.gd`.

## Retrieve and adapt (round 2)
Round 1 (branch wt-textmove, cfef60e) posed every card from scratch with IK and the hands missed their targets by
7-57 cm three times running. Round 2 poses NOTHING from scratch. Nick's saved scenes are real, already-good motion;
the blocking is one of his attacks, retrieved and adapted by the app's own operations:

| adaptation | the app's op | where |
|---|---|---|
| the other side | `Scene.mirror_card` (Mirror the scene), card by card | `_card` |
| another weapon | `Body.set_kind` + `Body.weapon_to_hand` (the user picking a kind), the hands made fists for a punch | `_arm` |
| both hands on a haft | `Body.apply_grip` with the top hand's place on the haft (`grip_m`) searched over the handle; the free palm fitted onto the shaft's axis (`Body.fit_hand`, `_fit_second`'s op); still off, both arms searched together (`Body.hold_bat`, the drag's solver); then the hold LOCKED (`Body.capture_second`, the Lock both hands button: the card carries the hand's place and turn on the shaft, and the plant and the play re-fit to it) | `_hold_two`, `_palm_fit` |
| footwork | the strike card's `steps` entry (what Nick's own step cards carry) + `Scene.pin_cards` (the leg re-planted by `Body.plant`); the hips follow the step by 0.45 of it, the share combo3's STRIKE shows (17 cm for a 38 cm step) | `_footwork` |
| balance | a card whose re-planted feet leave the centre of mass past them (the source's did not): the hips moved over the feet (the card's offset, the BALANCE rule's own advice), the feet re-pinned | `build` |
| timing | `Scene.retime` (Faster / Slower) to the weapon's row of `docs/ATTACK_RULES.md`, the speed words scaling the anticipation and recovery; then the same op on whichever part holds the trouble (below) | `build` |
| intensity | "heavy": the strike card's ease "in" | `build` |

Where no saved segment fits the status says so ("no saved uppercut to start from: blocked from the closest, Nick's
metal bat thrust ... with the weapon taken away"). A word the lexicon does not know is listed back, not guessed at.

## The index (`index()`, scenes/*.json read only)
Per scene not in `attack_timing.NOT_ATTACKS`: the Check's own strike finder (`Rulebook.sample` + `Rulebook.strikes`)
gives each contact; the card at the peak is the strike; the windup walks back while the cards hold under 0.2 s,
skipping the `fix (skin)` / `pass-by` clearance cards Fix added; the follow-through runs to the first rest; the
recovery is the return card after it (a card named recover / ready / guard / rest). A contact whose card is a
clearance card, a return, or has the weapon out of the hand is not an attack; a follow-through card that moves the
weapon to the other hand is dropped (bo_sweep's "catch: guard", a jump mid-move). The direction comes from the tip's
path at the peak: a thrust when the tip moves along the weapon (|wd . v| > 0.6), else the swing plane's normal:
|x| >= 0.6 is an overhead (an uppercut if the tip rises), else a sweep, its side from the tip's x change.

| scene | weapon | shape | strike card | windup / follow-through / recovery | step | peak (m/s) |
|---|---|---|---|---|---|---|
| bo_spin | staff | sweep left | 7 | [2-6] / [] / 8 | yes | 96.5 |
| bo_sweep | staff | sweep left | 2 | [1] / [3] / none (catch dropped) | no | 37.4 |
| combo3 | metal bat | sweep left | 2 | [1] / [3] / none | yes | 41.0 |
| combo3 | metal bat | sweep right | 5 | [4] / [6] / none | no | 40.3 |
| combo3 | metal bat | overhead | 9 | [7, 8] / [10] / 11 | yes | 44.7 |
| strike_legs | metal bat | overhead | 4 | [1, 2, 3] / [5] / none | yes | 38.5 |
| swing_back | metal bat | sweep right | 4 | [3] / [5] / 6 | no | 39.5 |
| swing_fore | metal bat | sweep left | 2 | [1] / [3] / 4 | yes | 33.2 |
| thrust | metal bat | thrust | 9 | [6] / [] / 10 | yes | 24.8 |

`pick()`: cost 0 for the same weapon, 2 for another of the same handedness, 3 across; +1 to mirror; +0.1 per windup
card; -0.5 for a saved recovery; +2 x the share the source's peak is over its own row's cap (bo_spin's 96.5 loses to
bo_sweep). A shape nobody saved starts from the closest that exists (uppercut -> thrust -> overhead -> sweep).

## The grammar (`parse()`)
- weapon: axe / hatchet (`long_axe`), bat, staff / bo, hammer / sledge (`long_hammer`), dagger / knife, sword (no
  sword kind: a bat, said in the status), fist / hand (no weapon).
- attack: overhead / downward / down / chop; sweep / horizontal / swing / cut / slash / arc / forehand / backhand;
  thrust / stab / poke; jab / punch / straight (a thrust); uppercut; hook (a sweep, to his left unless said).
- side: left / forehand (the swing ends on his left, +x), right / backhand.
- footwork: "step in" / "step forward" (+25 cm), "step back" (-20 cm), "lunge" (+40 cm), "stand" / "stand still"
  (the saved step taken out), "pivot" (listed as not built).
- speed: fast / quick (anticipation x0.7, recovery x0.8), light (x0.8), heavy (x1.3, strike ease "in"), slow (x1.6).

## Timing (the numbers, and where they come from)
The weapon's row of `docs/ATTACK_RULES.md`, the table `tools/attack_timing.gd` grades against (`AT.RULES`):
anticipation = the row's middle x the speed factor; the strike move at most the row's budget (30 fps frames); the
cards after the strike = the row's recovery middle x the factor. Thrusts take the spear row; the tip cap is the lower
of the row's and the kind's (`AT.TIP_MAX`); a fist's cap is `Rulebook.FIST_WARN` (11.95 m/s, the recorded mean punch).

| row | anticipation | strike budget | after | cap (m/s) |
|---|---|---|---|---|
| hammer (axe, hammer) | 0.4-0.6 s | 6 fr | 0.5-0.8 s | 30 |
| metal bat | 0.25-0.35 s | 6 fr | 0.25-0.4 s | 40 |
| staff | 0.25-0.4 s | 6 fr | 0.3-0.5 s | 30 |
| knife (dagger) | 0.1-0.2 s | 4 fr | 0.15-0.25 s | 15 |
| spear (every thrust) | 0.2-0.3 s | 4 fr | 0.25-0.4 s | 20 |

Then the loop (at most 10 retimes): the tip over 95% of its cap -> the part holding the peak slowed by the overshoot;
the peak outside the strike -> that part slowed 25%; a joint turning faster than in the source (`HumanLimits`
JOINT SPEED) -> its part slowed by the excess; a new HEAD QUIET -> the anticipation; a new SEQUENCE only when the
timing made it (the wind-up sped to the row until the weapon turned fastest in it; a second strike in the recovery).
A SEQUENCE inside the strike's own move is the pose order, reported as it is.

## Results (`tests/text_blocking_test.gd`, `text_blocking:h` in tools/run_all.sh; 291 s for the 10 phrases)
Every phrase: 4+ cards with the strike among them, the words' weapon (or no weapon) in hand on every card, on a
two-hander both hands on the haft on every card (the free palm within 2 cm of the shaft's axis, Lock both hands' own
test, and its wrist within 2 cm of its locked spot, `Body.grip_miss`, both read after a reload + apply_grip the way
the app plays the card), the tip's peak inside the strike's move and under the cap, NO must-fix the source segment
did not have (default Check), NO human-limit finding the source did not have (`HumanLimits.findings`), unknown words
listed back, saved to user:// and read back. PASS, 0 failures. Grip = worst palm / worst wrist over the cards.

| phrase | source (scene, cards) | adapted | grip (cm) | peak / cap (m/s) | peak in the strike's move | slowed again (anticipation / strike / after) |
|---|---|---|---|---|---|---|
| overhead axe strike, step in | combo3 [0, 7, 8, 9, 10, 11], bat overhead | axe swapped in; the saved 38 cm step kept | 0.8 / 0.0 | 25.3 / 30 | 1.02 s in 0.93-1.17 | 1 (SEQUENCE: the weapon fastest in the wind-up) / 2 (knee 1880 deg/s) / 1 (hip 891) |
| fast jab | thrust [0, 6, 9, 10], bat thrust | weapon taken away (no saved punch) | - | 9.5 / 11.95 | 0.78 s in 0.67-1.12 | 5 (SEQUENCE) / 3 (hip 783) / 0 |
| bat swing left | swing_fore [0-4], bat sweep | as saved | - | 33.4 / 40 | 0.68 s in 0.60-0.75 | 0 / 0 / 5 (knee 1987) |
| dagger thrust lunge | thrust [0, 6, 9, 10] | dagger swapped in; the lead foot lunges 40 cm, the hips 9 cm with it, back on the recovery | - | 12.3 / 15 | 0.70 s in 0.61-0.95 | 1 (SEQUENCE) / 2 (hip 798) / 3 (hip 967) |
| heavy hammer overhead, step back | combo3 [0, 7, 8, 9, 10, 11] | hammer swapped in; the foot 20 cm back (the hips -26 cm with it), the recovery's hips moved 5.2 cm over the re-planted feet; strike ease "in" | 0.8 / 0.0 | 25.3 / 30 | 1.08 s in 0.95-1.15 | 0 / 0 / 0 |
| staff sweep right, pivot | bo_sweep [0, 1, 2, 3], staff sweep, MIRRORED | the catch card left out (the staff leaves the hand); pivot not built | 0.6 / 0.0 | 28.4 / 30 | 0.77 s in 0.63-0.85 | 0 / 1 (tip 34.0 over 95% of the cap) / 0 |
| uppercut | thrust [0, 6, 9, 10] (CLOSEST: no saved uppercut) | weapon taken away | - | 9.8 / 11.95 | 0.78 s in 0.67-1.10 | 4 (SEQUENCE) / 2 (hip 802) / 0 |
| hook, step in | swing_fore [0-4], bat sweep | weapon taken away (no saved punch); the saved 14 cm step kept | - | 10.5 / 11.95 | 0.75 s in 0.59-0.92 | 3 (SEQUENCE) / 2 (fist 11.6 over 95% of the cap) / 5 (a second strike in the recovery) |
| overhead axe strike, spinning | combo3 [0, 7, 8, 9, 10, 11] | as the first; "Didn't understand: spinning" | 0.8 / 0.0 | 25.3 / 30 | 1.02 s in 0.93-1.17 | 1 / 2 / 1 |
| slow staff thrust, step in | thrust [0, 6, 9, 10] | staff swapped in, held a spear's way (the top hand 0.6 m up); the saved 20 cm step kept | 0.9 / 0.0 | 18.8 / 20 | 0.77 s in 0.70-1.02 | 0 / 1 (tip 23.0) / 0 |

The two-hand hold on the bat poses: on the axe / hammer cards `hold_bat` was needed on 4 of 6 and turned the weapon's
line up to 42 deg from the bat's and moved the bat hand up to 14 cm; on the staff thrust 28 deg, 1 cm; on the mirrored
staff sweep 3 deg, 0 cm (Nick's own two-hand cards). The first version of the hold (apply_grip's reach alone, then
hold_bat by wrist miss) left the palm 3.5-3.9 cm off the axis on the worst card of every two-hander; the palm fit +
lock closed that to under 1 cm with the wrist at its locked spot on every card.

Screenshot of the axe strike card: `C:\Users\Nick\.claude\jobs\9afc22db\tmp\text_blocking.png` (the same view of
combo3's own STRIKE card beside it in `combo3_strike.png`: the axe sits where Nick's bat was).

## What is not done
- **No saved uppercut, punch, dagger thrust or staff thrust exists.** Those phrases are blocked from the bat thrust
  (thrust.json) and the bat sweep (swing_fore.json) with the weapon taken away or swapped: a bat chamber with a fist in
  it is not a boxer's jab (the status says so). They get better the day Nick saves one; the index picks it up by itself.
- The knife row's 0.1-0.2 s anticipation does not hold on a bat chamber: the jab's wind-up had to be slowed back five
  times (x3.05) before the weapon's fastest turn was the strike's (SEQUENCE), the uppercut's four. The row's number is
  for a knife already up; the retrieved pose carries the bat's load.
- "pivot" is listed as not built (the stance is kept); "sword" is a bat (no sword kind); "spinning" and any other word
  outside the lexicon is listed back, not guessed at.
- The adaptation never changes the source's own findings: bat swing left keeps swing_fore's TIPPING and 1105 deg/s
  trunk, the axe overhead keeps combo3's 56 cm HEAD QUIET. The bar is "nothing NEW", not "clean".
- A SEQUENCE inside the strike's own move (the hips' fastest moment after the weapon's within one card) is the pose
  order; no retime changes it, so it is reported as it is. None of the 10 phrases ended with one.
- The balance adaptation moves the hips only (the card's offset); it fired once (the hammer's recovery, 5.2 cm).
- Cost: 20-60 s a phrase (hold_bat ~2-4 s a call, a whole-arm fit ~0.4 s, each retime loop a 60 fps replay of the
  scene; the index of scenes/ is built once per run, ~10 s).
- The `_wip` file carries the status as its "plan"; nothing is written to scenes/, poses/ or data/, and the live body
  is not touched until the new scene opens.
