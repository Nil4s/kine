# Weight transfer: which foot each strike starts from (N029)

The Check rule **WEIGHT TRANSFER** (`scripts/weight_xfer.gd`) asks one question per strike: is the weight on the foot
this strike needs, at the moment it needs it? This page is where its directions and bars come from. Every source below
was opened on 2026-10-23; what each one does and does not say is written next to it. **The bars are ours** (HEURISTIC in
`scripts/trust.gd`): the sources give the direction of the shift and a coaching split, not a measured distribution of
weight between the feet at the start of a strike. No source found gives that number from force plates.

## How the weight is measured

- The centre of mass: de Leva 1996 segment masses (`scripts/balance.gd`).
- The share per foot: the static lever rule along the line joining the two footprints' centres, the COM's floor point
  projected on it (`TextView.left_share`, the N001 text view's "weight 81 % on the left foot"). One foot down = all of it
  on that foot. Static: it ignores the push of an accelerating body (a force plate would read the dynamic share).
- The strikes: the N016 move recognizer over each card's window, its class, hand or leg, and lead / rear.

## Cross (rear straight punch): start on the back foot

- Evolve MMA, "How to throw a stronger and more powerful cross":
  https://evolve-mma.com/blog/how-to-throw-a-stronger-and-more-powerful-cross/
  "Before you throw a hard cross, you want to ensure that you have more than half of your weight on your rear leg";
  the stance "with sixty percent of your weight on your rear leg and forty percent on your front leg".
- Evolve MMA, "Mastering the cross": https://evolve-mma.com/blog/mastering-the-cross-small-adjustments-that-make-a-huge-impact/
  "about 60% of your weight on your front foot at the moment of impact" (the END of the shift, not its start).
- Peloton, "How to throw a cross": https://www.onepeloton.com/en-GB/blog/cross-boxing
  "Push off your back foot to pivot onto your toes"; "transfer your weight from your back foot to your front foot".
- Background, not used for a number: Lenetsky, Harris & Brughelli 2013, "Assessment and contributors of punching forces
  in combat sports athletes", Strength Cond J 35(2):1-7, doi 10.1519/SSC.0b013e31828b6c12 (the abstract only was seen:
  a review of ground reaction forces as a contributor). A force-plate study of the lead straight punch (Liu et al. 2022,
  Front Physiol 13:1015154, https://doi.org/10.3389/fphys.2022.1015154, 16 boxers) reports peak force per leg, rear
  17.0 +- 2.2 and lead 19.7 +- 4.1 N/kg in the elite group, but no split at the punch's start and no cross.
- **Bar: CROSS_MIN = 0.45 on the rear foot at the delivery's start.** "More than half" minus 5 points for the lever
  rule's footprint resolution. Fix aims at 0.60 (Evolve's own split) and stops when the strike starts at 0.57.

## Lead hook: over a loaded lead side

- Boxing News, "Fight school: the hook": https://boxingnewsonline.net/features/fight-school-the-hook
  "The weight shifts slightly to the front foot as the hip and shoulders pivot violently, using the front-facing side of
  the body as a hinge."
- Against it, a style difference: Evolve University, "How to throw a stronger and more powerful lead hook":
  https://evolve-university.com/blog/how-to-throw-a-stronger-and-more-powerful-lead-hook/ describes the American-style
  hook "which in theory will shift your weight to your back foot while turning your hip over". That is the weight at the
  END of the turn; the hook still starts from a loaded lead side.
- **Bar: HOOK_MIN = 0.40 on the lead foot at the delivery's start**, lenient because the styles differ. Not graded: a
  rear hook, a jab, an uppercut, an elbow (no source opened says where their weight must start).

## Kicks (roundhouse, front kick, side kick, knee): the support foot loaded before the kicking leg leaves

- Statics: once the kicking foot is off the floor the support foot carries all of the weight, so the COM has to be over
  the support by then; at lift-off the leaving leg should not still carry most of it.
- Kinoshita & Fujii 2014, "Biomechanical analysis of taekwondo roundhouse kick focused on phase before toe off", ISBS
  2014: https://ojs.ub.uni-konstanz.de/cpa/article/view/6038 (13 male taekwondo athletes, force plates under BOTH the
  kicking and the support leg). The kick is split at the kicking leg's toe-off (TOF, 50 % of the normalised time); in the
  READY phase before it, the support leg's hip "generated the largest energy of all joints", "extension of hip joint in
  support leg produced the translational velocity of pelvis", and they conclude "coaches should pay greater attention to
  support leg and READY phase". The paper gives no weight split at toe-off.
- Background: Riansoi et al. 2019, "Mechanical analysis of supporting leg during roundhouse kick in Muay Thai
  beginners", J Sports Sci Technol 19(2):72-81, https://he01.tci-thaijo.org/index.php/JSST/article/view/215734 (the
  abstract: the support leg's antero-posterior GRF and joint moments differ between dominant and non-dominant legs).
- **Bar: KICK_MIN = 0.50 on the support foot at LIFT-OFF** (the last frame the kicking foot is down before its peak):
  under half = more weight on the leaving leg than on the one that must hold him. Fix aims at 0.65.

## The fix

The card the strike leaves from (the last card arrived at by the measured moment) gets a pelvis offset along the feet's
line toward the needed foot, the feet re-planted where they stood (heel let up if a flat foot cannot reach, hips sunk up
to 8 cm if a leg cannot), measured again as the clip plays, the aim raised by the shortfall up to 4 times. DragBalance (I24)
was tried first: with both soles held flat its ankle limits stop the hips after about 10 points of share (measured on the
recognizer test's guard stance: 47 % lead could reach only 37-55 %), too little to turn a front-foot cross around.
Measured in `tests/weightxfer_test.gd`: a cross from 70 % on the lead foot -> the hips 13 cm back, the cross starts at
60 % rear; a roundhouse lifting off at 41 % support -> the hips 22 cm over, 67 % at lift-off. One Ctrl+Z.

## What the shipped scenes show

Every file in `scenes/` holds a weapon (bat, staff, axe, sword): the recognizer names their strikes weapon swings, which
this rule does not grade, so none of them is flagged (combo3 included). On the recognizer test's text-blocked unarmed
clips, "right hook" is flagged: its strike is a LEFT (lead) hook thrown with 13 % on the lead foot, whose ball sits
7.8 cm off the floor. The numbers bear the finding out; the deeper cause is upstream: text-to-blocking's "right hook"
throws the left hand (the recognizer reads it as a left hook too).
