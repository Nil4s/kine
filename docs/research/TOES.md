# Toes in a walk (ball_l / ball_r)

The toe joint ("ball", the toe base; the tip is its end point) bends + = toes up. body_limits.json allows -30..60.

## What went wrong

Walk playback (scripts/scene.gd, `_toe_off` and `_construct`) bent the toes to keep the tips on the floor at push-off.
The trailing ankle's plantarflexion gave the toe joint the rest of the foot's pitch, so the toe bent 59.8 deg at
push-off (walk_bat). Early swing then kept the toes bent: 20-59 deg with the foot 2-6 cm in the air, because the
toe bend only eased to level by mid-swing (TOE_LEVEL 0.5 of the move).

The code comment cited people's MTP at "50-60 deg at toe-off". The 60.3 +- 5.1 deg figure (Eckelt et al. 2026) is the
foot-ground angle at toe-off, not the MTP joint; the two were conflated.

## Real walkers (the bars)

- First MTP (big toe) dorsiflexion peaks at about 40-45 deg at toe-off in walking: Miana et al. 2021 (as cited in the
  brief; the paper itself not re-read here).
- About 42 deg at push-off: Nawoczenski et al. 1999 (as cited in the brief; full title and paper not checked here).
- Near 0 (+-10 deg) in swing and mid-stance: Perry J. and Burnfield J., Gait Analysis (1992) (as cited in the brief;
  not re-read here).
- Foot-ground angle at toe-off 60.3 +- 5.1 deg at 4.5 km/h: Eckelt et al. 2026, PMID 41583941 (already in the
  walk tests; a different quantity, kept as is).

## The fix (scripts/scene.gd)

- `TOE_MTP_MAX := 45.0`: `_toe_off` caps the toe bend after `toes_flat`.
- `TOE_UNBEND := 0.15`: the toes go back to level within 0.15 of the move after they leave the floor (was: by mid-swing).
- `_toe_guard(B, t)`, run after `_apply` on walk cards only: on the floor (lift < 1 cm) the toe bend is held to
  [-30, 45]; in the air (lift > 2 cm) to |bend| <= 10; smooth between. The ball's height does not depend on the toe
  angle, so the guard does not feed back into the lift it reads.

## Numbers (walk_bat, 120 Hz, both feet)

| | max bend (deg) | max abs bend with foot > 2 cm up (deg) | tip rise when bent on the floor (mm) |
|---|---|---|---|
| before | 59.8 | 59.2 | 18.4 |
| after | 45.0 | 10.0 | 5.3 |

tests/toes_walk_test.gd checks walk_bat, a 0.8x and a 1.25x re-timed walk (generated from the walk_bat cards).

## Not done

- The toe guard is a playback limit. The writers themselves (`_construct`'s heel roll, the card blend, the knee floor)
  still produce the large angles; the guard clamps them. A cleaner fix would make each writer stay in range.
- Not measured: foot-ground angle at toe-off after the cap (walk_legs_test checks it at >= 40 deg), not run.
- Sources marked "as cited in the brief" were not checked against the papers.
