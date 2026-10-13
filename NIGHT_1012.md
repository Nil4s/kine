# Night 10-12 -> 10-13: Nick asleep, "cook some and we go from there"

Started 22:31 (date). Everything is cooked with `tools/cook.gd` from a plan in `plans/` -> `scenes/<name>.json`, then
`python tools/sheet.py <name>` -> `moves/cooked/<name>.gif` + `_sheet.jpg`. Open any scene in the poser's scene list.

## The list
- [x] cook tool + sheet tool (plans = clips as changes; hand targets in the chest's frame; bat aim; feet planted)
- [x] idle_bat: weight shift + breathing, 4.6 s loop, 0 bad frames
- [ ] swing_level (two hands): PARKED. The arm search finds body-legal but unnatural arms (elbows to the face in
      the load). Next try: pose the two-hand clips by angles like Nick does, search only the second hand.
- [x] swing_fore: one-hand forehand, right to left
- [x] swing_back: one-hand backhand return, left to right
- [x] thrust: one-hand jab with the bat end
- [x] combo3: forehand -> backhand -> Nick's overhead strike
- [x] hit_react: flinch back from a hit to the chest, recover
- [x] walk_bat: walk start -> stop with the bat (steps) (a loop version later)
- [x] side-step dodge (dodge_side)
- [ ] each one: sheet, contacts, compare with a real reference

## Log
- 22:31 start. Tools built; idle cooked clean.
- swing_level x3 (reach -> two-arm search -> two starts): hands miss 12-33 cm in the stance/load; parked.
- ~23:00 Nick (awake): "check legs position ... the bat goes inside shoulder chest head ... keep hand straight w forearm".
  Fixes, all in scripts/body.gd + scene.gd + tools/cook.gd:
  - legs: knee_over_toes (the knee turns over the toes); a heel-up back foot's knee follows the hips' facing.
  - bat in the body: chest/hips are wider than the spine capsules -> WIDE capsules (chest_wide, hips_wide) tested
    against bat + forearms + hands; upper-arm capsule starts 8 cm down the arm (the shoulder ball is part of the chest).
  - straight wrist: the bat arm is found by a SWEEP over upper arm x elbow x forearm turn (hand twist +-60) with the
    wrist straight, scored on hand spot + bat direction + contacts, then refined with the wrist held to bend +-15,
    side +-20. The bat's direction now comes from the arm and the forearm turn, never a folded wrist.
  - in-betweens: pass-by repair = search the arm out of the body staying closest to the in-between pose.
  - combat ready = bat up in front (guard); the shoulder carry is the idle only (going carry -> front swept the
    bat through the chest).
- 00:15 all six recooked: worst contact anywhere 1-4 mm, hands on target (one key 12 cm: forehand CONTACT), wrists
  straight. Sheets re-recorded.
- 00:25 combo3 cooked: 12 keys, 4.7 s, my forehand + backhand then Nick's four strike cards at his exact angles; worst contact 2 mm.
- 00:4x walk_bat: half step + 4 strides of 0.6 m + feet together, 3.15 s, 0 bad frames. First cut was a stiff march (no knee bend -> ground() stood the hips tall); soft knees in the plan + per-clip "lift" (0.13 m) fixed it.
- 01:2x swing_level try 4 (the one-hand sweep + "grip spot within the left arm's reach"): right hand on target, left hand misses
  3-53 cm (crossing to the knob the left shoulder hits its limits; distance can't see that); solving the left arm inside
  the search made one cook take 25+ min. PARKED for good on this route: the two-hand swing needs Nick's posed keys (his
  poser), then the cook only plants the legs and checks contacts, like combo3's overhead.
