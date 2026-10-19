# Foot joints: the subtalar roll (ROADMAP 7)

## What the rig had

- `foot_l/r` (the ankle, talocrural) bends up and down about the lateral axis: correct.
- `foot_l/r` twist was a roll about the foot's BONE (ankle to ball joint). That bone runs 31 deg below the sole plane at
  rest (ankle 10 cm up, ball base 1.5 cm up), so the old "sole roll" turned about an axis below the floor. Range -20..20.
- `ball_l/r`: the toe base. There are no separate big-toe bones: the mannequin (assets/mannequin.glb) has
  `ball_l`, `ball_r` and `ball_leaf_l/r` (the tip marker), and nothing named hallux or toe_01. No bones were added.

## What it has now

- The foot twist turns the sole about the SUBTALAR axis (`Body.w_ax`, computed in `Body.load_files`):
  42 deg up from the sole plane and 23 deg medial to the foot's long axis (long axis made horizontal).
  Right foot: medial = +X. Left foot: the mirror.
- Positive roll = inversion (the sole turns medial) on the right foot; the left foot takes the mirror.
- Ranges: inversion +25, eversion -8 on the right foot (written in code, `Body.SUB_TWIST`, not in data/body_limits.json);
  the left is -25..8 through the loader's usual negation.
- Decomposition: a roll about an axis that is not perpendicular to the swing axes is solved numerically
  (`Body.decompose`); zero roll uses the old bone-axis split unchanged, so untwisted poses are bit for bit the same.

## Sources for the numbers

- Subtalar axis 42 deg up and 23 deg medial to the long axis: Inman 1969 (Isman and Inman) and Inman 1976, as quoted in
  a PMC review (https://pmc.ncbi.nlm.nih.gov/articles/PMC5549175) and Ortho Oracle
  (https://www.wheelessonline.com/joints/sub-talar-joint/, which gives 16-23 deg medial). Found by search; the papers
  themselves were not read here.
- Spread in the literature: Leardini et al. 53 deg up and 39 deg medial; van den Bogert et al. 35 and 18; the
  Inman-era ex vivo study 41 and 23 (n = 46). The axis varies between people, so 42 / 23 is a mean, not a fact about one foot.
- Inversion 25-30 deg and eversion 5-10 deg (the PMC review above). The ranges used here (25 and 8) are inside those.
  The review says the ankle position changes subtalar motion; the rig does not model that coupling.

## Test

`tests/foot_joints_test.gd` (run as `foot_joints:h` in tools/run_all.sh): the roll turns about the subtalar axis within
0.5 deg, the limits hold, the heel moves medially on inversion, compose and decompose round-trip, and the 10 scenes that
never twist the foot give the same sha256 over 60 frames as before. bo_spin twists the foot (-12 deg on one side) and
changes; it is reported, not held to the old result.

## Not done

- The sole roll is not yet used by the ground contact: the heel and toe points still come from the ankle and ball joints,
  so a foot on a slope or a cut step rolls only through foot_roll / plant, not through a subtalar contact solve.
- No big-toe split: the mannequin has no separate toe bones.
- The ankle-subtalar coupling of the review above is not modelled.
