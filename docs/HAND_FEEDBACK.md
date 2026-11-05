# HAND feedback: a palm that lies flat, fingers that hook and close (gaps G23, G38)

Lane HAND (branch `w4-hand`, off `origin/poser-ui-rounds`). The hand used to collide as ONE capsule from the wrist to the knuckles, radius 4.7 cm (9.4 cm thick). It could not lie flat on a box (CH7b: 13-54 mm palm penetrations) or close round a rope (CH6b swapped in 4 slim capsules of its own).

What was built:
- **`scripts/hand_shape.gd` (HandShape)** is the one place the hand's collision shape comes from:
  - the palm: a row of 6 parallel capsules, together a slab of the cited size;
  - the fingers: a capsule per phalanx on the posed finger joints, so the curl is followed;
  - `forearm_caps`: a slim wrist capsule for the forearm's last 45 %;
  - `HandShape.legacy = true` gives back the old capsule, bit for bit.
- **`palm_flat(B, h, point, normal, opts)`** lays the palm on a surface. The fingers either lie along it (each knuckle bends -20..25 deg until the finger rests on the surface) or hook over an edge (`opts.hook`). The thumb is laid on the surface.
  - The arm goes through `LimbIK.solve`, so every joint stays inside its limits.
  - If the wrist limits stop the asked finger heading, the heading is turned about the normal (5-deg steps, up to 90) until no limit stops the wrist.
- **`close_on(B, h, capsules)`** curls each finger and the thumb toward the fist until it touches, never into the obstacle. A finger that starts inside is opened first.
- **`Rulebook.prop_hits`** (the app's THROUGH A PROP check) now uses the palm slab for the hands. The fingers stay out, as before.
- **`tools/hand_mesh.gd`** measures the drawn hand in the hand's frame.

## 1. Result

`WT_MAX=8 wtest.sh hand ...`: **hand 15 ok / 0 fail.** The bars were committed in `9663fb0a` before the first run.

| bar | reads | bar | control (must fail its bar) |
|---|---|---|---|
| a size (palm capsules as built vs ANSUR II) | 11.60 x 8.80 x 3.15 cm, perimeter 21.20 cm: 0.0 % off | 5 % | old capsule 9.4 cm thick, 198 % off: flagged |
| b flat, horizontal box | deepest hand capsule 0.00 mm, palm contact 74 % | 2 mm, 50 % | old capsule at the same pose 11.5 mm in |
| b flat, box turned 45 deg | 0.00 mm, 74 % | 2 mm, 50 % | old capsule 11.5 mm in |
| c hook over a 0.6 m wall top | palm gap 0.50 mm; 4/4 tips 5.9-7.5 cm below the top, 1.1 cm past the face; deepest finger 0.00 mm; 4/4 within 5 mm of the face | 0..2 mm, 2 cm, 1 mm, 3/4 | fingers straight: 0/4 tips below the top |
| d closed on a 10 mm rope (r 5 mm, particles every 4 mm) | least rope-hand gap +0.50 mm; 4/4 fingers touch, 4/4 on the rope's outer half | >= -0.1 mm, 3/4 | old capsule: a particle 11.5 mm inside |
| e twin (no native code changed) | exact `cap_gap` = `Props.depth` sampling on 63 capsules within 0.000 mm | 1 mm | a capsule 5 mm too fat reads 4.50 mm apart |
| f old | legacy = Body.cap/Body.rad bit for bit; `prop_hits`: flat palm 0 hits | | legacy capsule at the same pose: 1 hit, 11.5 mm |

**Suites on the last commit.** Each fail was checked again with `HandShape.legacy = true` (the old capsule everywhere). Those runs fail the same bars, so the fails come from the base branch, not this lane.

| suite | result |
|---|---|
| hand | 15/0 |
| easypart | 73/0 |
| peasy3 | 23/0 |
| freestart | 14/0 |
| carry_form | 5/0 |
| carry | 19/0 |
| contactik | 19/0 |
| prop_check | 8/0 |
| throw | 19/0 |
| stand_set | 10/0 |
| c13 | 28/0 |
| asserts | 25/0 |
| hand_pose | 12/0 |
| props_generic | 26/1, from the base: the round-37 digest |
| use_set | 17/3, from the base: Step up |
| templates | 74/1, from the base: roundhouse |

The suites that read the hand capsule or `prop_hits` (grep `cap("hand`, `rad["hand`, `prop_hits`, `ContactIK.`) are carry_form, carry, contactik, prop_check, props_generic, use_set, templates, throw, stand_set, c13 and asserts.

### Payoff, measured in scratch copies of the parked branches (not committed, not merged)

**CH7b** (`w4-ch7b` + hand_shape.gd and a probe `tests/handpay_test.gd`; the same played poses, the hand measured both ways):

| | old capsule | HandShape palm | HandShape palm + fingers |
|---|---|---|---|
| speed vault, hand_r f33-37 | 24.0 / 24.4 / 29.9 / 35.6 / 53.9 mm | 4.9 / 2.8 / 4.8 / 7.4 / 20.7 mm | 44-63 mm (thumb_03, index_03) |
| kong palms f74-76 | 5.3 / 8.9 / 13.3 mm | 0 / 0 / 1.5 mm | 21-26 mm (thumb_02) |
| mantle f174-175 | 3.6 / 17.5 mm | 0 / 0 mm | 46-48 mm (thumb_03) |

- **Bar 5 overall: 80.0 mm before and after.** It is set by thigh_l in the kong box, which is not the hand.
- The palm alone removes most of the palm penetration.
- The fingers make the totals worse, because CH7b never posed them. They are straight, and the rig's rest thumb hangs 8 cm palm-side, so it goes into every box.
- **`palm_flat` at the plant frames** (hand re-posed, arm re-solved):

  | move | hand depth after | why |
  |---|---|---|
  | kong f76 | 0.0 mm | |
  | mantle f175 | 0.0 mm | |
  | speed vault f33-37 | 0.0 / 0.3 / 5.1 / 16.6 / 28.4 mm | the wrist's 60-deg extension stop leaves the palm tilted 26-39 deg |

  The wrist moved 21-46 mm. The vault needs the plan to change (the shoulder over the hand), not only a different hand shape.

**CH6b T2** (`w4-ch6b` + hand_shape.gd):

- **Swapping the colliders inside the tie is not a clean measurement.** The tie's own wrist-clearance search uses the colliders, so the whole tie changed: T0 went from 7.22 to 0.95 mm and the knot was lost. T2 went from 0.129 r to 1.233 r.
- **A static probe on the same poses** (the parked tie, non-driven rope only) reproduces T2 = 0.129 r for CH6b's slim hand:

  | hand shape | worst rope penetration |
  |---|---|
  | legacy capsule | 8.50 r (34 mm) |
  | HandShape | 4.53 r (18.1 mm), **all of it the palm slab** |
  | HandShape fingers alone | 0.00 r (CH6b's were 0.129 r) |
  | CH6b slim palm | 0.009 r |

- Why the palm slab: CH6b posed the hand round its own palm, whose face is 1.3 cm off the bone line. HandShape's face sits on the drawn skin, 3.5 cm off. **So no payoff for CH6b without re-planning the tie.** The thinner fingers are the part that helps.

## 2. Engineering level reached

| discipline | level | evidence | why not higher |
|---|---|---|---|
| anthropometry of the shape | L2-L3 | palm length, breadth and knuckle circumference are cited ANSUR II 50th-percentile men; thickness is derived by a closed form (stadium section); finger radius from the FAA HFDS; planted control | thickness is derived, not measured (no ANSUR hand-thickness value could be extracted: the 1988 report is a scan); one percentile only; the slab's place in the hand follows the drawn mitten mesh, not anatomy |
| contact geometry | L3 | exact capsule-box depth (golden-section on a convex signed distance), checked against the app's sampled Props.depth (0.000 mm); contact area by sphere tracing onto the real capsule row | no friction or contact forces; no soft-tissue compression model (a palm flattens about 5-10 mm under load) |
| posing | L2 | palm_flat inside every joint limit (LimbIK + limit-aware heading search), measured flat on two boxes; hook and grip measured | the heading is turned, not asked; no elbow-swivel or shoulder search; the thumb is a 5-deg grid |

## 3. What Kine lacked (searched before claiming)

| needed | exists today | workaround | cost | proposed feature |
|---|---|---|---|---|
| the hand's shape as a palm and fingers | Body: one capsule per bone; finger capsules exist but every contact test skipped them | HandShape (palm row + finger capsules, posing, distances), legacy flag | 536 lines | done here; next: move Body.contacts / cross_contacts / skin tests to it (they still use the old capsule: their allowances were tuned to it) |
| a wrist that is not 10.8 cm thick | the forearm capsule (r 5.4 cm) ends in a 5.4 cm ball at the wrist joint | `HandShape.forearm_caps` (wrist r 2.8 cm from ANSUR wrist circumference) | 10 lines | a tapered forearm in Body (two capsules), used by every contact test |
| palm-flat placement that respects the wrist limits | ContactIK.reach turns the palm by the shortest arc and keeps the wrist one forearm radius up | palm_flat with a heading search | 120 lines | an elbow-swivel and shoulder search in the same solve, so the asked heading can be kept |
| the drawn hand matching anatomy | the mannequin hand is a mitten: 5.4 cm thick, 10.3 cm across, hand length 23.3 cm (ANSUR 3.15 / 8.8 / 19.3) | the slab's palm face is put on the drawn skin (3.5 cm off the bone line) | none | a hand mesh and skeleton at real proportions; until then the visible and the anatomical palm disagree by 2 cm |
| a rest thumb outside the palm | the rig's rest thumb hangs 8 cm palm-side | close_on opens it; palm_flat lays it on the surface; ContactIK still leaves it in a wall (prop_hits skips fingers, so Check does not see it) | | a rest pose with the thumb beside the index |

## 4. What looks wrong

From C:/Temp/claude/hand/flat45.png, hook.png and rope.png. Each picture shows the mannequin translucent, the palm green, the fingers yellow, the forearm blue.

- **Heading.** In every case the heading had to turn 40 deg from the one asked: the wrist's -20 deg ulnar stop binds. The hand lies flat, but it does not point where the plan wanted.
- **Fingers too long.** The fingers are the rig's, 11 cm against a cited 8. They reach well past where a real hand's would, both on the 45-deg face and over the hook edge.
- **Thumb on the flat palm.** It now lies parallel to the index, touching it. After the angle penalty it is no longer stuck out at a right angle, but a real flat hand splays it 20-40 deg.
- **Rope grip.**
  - The four fingers wrap the rope and press it toward the palm, as a power grip does.
  - The thumb does not oppose: it opens off the rope and lies along the palm.
  - The rope is visibly thin against 2.1 cm fingers. That is right for 10 mm rope.
- **Wrist on the 45-deg box.** The wrist capsule is 3.3 mm into the box: the forearm leans on the face above the ridge.
- **Hook.**
  - The fingers bend 90 deg at the knuckle and run straight down the end face.
  - The middle and tip joints stay straight: bending them would push the fingers into the face.
  - It reads as a stiff hook, not a curled one.
- **The drawn hand.** It is wider than the green palm (10.3 against 8.8 cm), so its edges show through a surface the collision palm only touches.

## 5. What was changed after seeing results

No bar was edited after the first run. The changes after it were to the code:

- **palm_flat.** In the first run the wrist hit its -20 deg side stop. The palm tilted, contact was 4-6 % and a finger went 9.8 mm in. Added the limit-aware heading search.
- **close_on.** The rig's rest thumb started inside the rope (-0.103 mm). Added the open-first step.
- **prop_hits.** Including the fingers made contactik fail: ContactIK leaves the rest thumb 3 cm into the wall. prop_hits went back to its old rule of no fingers, and the palm slab is used for the hands.
- **Thumb angle penalty** (0.05 mm per degree), after looking at flat45.png, where the thumb stuck out at 90 deg.
- **Knuckle range** for flat fingers: -20..25 deg, was 0..25.
- **Print lines** in hand_test.gd now show the heading turn and the tilt. No bar text or threshold changed.

Last commit: see `git log -1 w4-hand`.
