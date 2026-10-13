# Night 10-12 -> 10-13: Nick asleep, "cook some and we go from there"

Started 22:31 (date). Everything is cooked with `tools/cook.gd` from a plan in `plans/` -> `scenes/<name>.json`, then
`python tools/sheet.py <name>` -> `moves/cooked/<name>.gif` + `_sheet.jpg`. Open any scene in the poser's scene list.

## The list
- [x] cook tool + sheet tool (plans = clips as changes; hand targets in the chest's frame; bat aim; feet planted)
- [x] idle_bat: weight shift + breathing, 4.6 s loop, 0 bad frames
- [ ] swing_level (two hands): PARKED. The arm search finds body-legal but unnatural arms (elbows to the face in
      the load). Next try: pose the two-hand clips by angles like Nick does, search only the second hand.
- [ ] swing_fore: one-hand forehand, right to left
- [ ] swing_back: one-hand backhand return, left to right
- [ ] thrust: one-hand jab with the bat end
- [ ] combo3: forehand -> backhand -> Nick's overhead strike
- [ ] hit_react: flinch back from a hit to the chest, recover
- [ ] walk_bat: walk cycle with the bat (steps), loop
- [ ] side-step dodge
- [ ] each one: sheet, contacts, compare with a real reference

## Log
- 22:31 start. Tools built; idle cooked clean.
- swing_level x3 (reach -> two-arm search -> two starts): hands miss 12-33 cm in the stance/load; parked.
