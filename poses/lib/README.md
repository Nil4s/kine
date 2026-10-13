# Standard poses (Nick 10-13)

Positions that repeat across animations (guard, wind-up, contact, carry, ...). Every file here passed
`tools/pose_check.gd`; a pose that fails does not go in.

    godot --headless --path . -s tools/pose_check.gd -- poses/lib/<name>.json     # judge one (or no args: all of poses/)
    godot --headless --path . -s tools/pose_check.gd -- --settle poses/lib/<name>.json   # fix what is fixable, re-judge

The checks: no joint on the end of its range (finger curl excepted: a fist is full curl), no part inside another,
both feet on the floor (heels down unless listed in `heel_up`), knees within 25 deg of their feet, hips over the
line between the ankles, the bat wrist straight (bend +-15, side +-20). `tests/bad_poses/` must always FAIL.

Use one in a plan clip: `{"name": "guard", "pose": "guard_bat", "move": 0.4}` (then `set` / `add` / `hand` on top).

| pose | what | look |
|---|---|---|
| guard_bat | bat up in front, ready for any one-hand move | ok |
| idle_bat_carry | bat resting on the right shoulder | elbow rides high behind (Nick to judge) |
| windup_high | forehand load, bat cocked over the right shoulder | ok |
| forehand_contact | hips + chest turned in, bat level out front, right heel up | ok |
| backhand_contact | chest still closed, back of the hand leads | ok |
| overhead_load | Nick's overhead load | ok |
| strike_lunge | Nick's strike: long lunge, hips hinged, head down, right heel up | ok |
| walk_step | walking with the bat, left foot landing | ok |
| hit_flinch | hit in the chest, snapped back | ok |
| dodge_low | sunk for a side step | knees a little in from the front (Nick to judge) |

## Paths between poses (not solved yet)
Two clean poses can still have a bad path between them: straight-line angle blending can sweep the bat through the
body. Found with plans/lib_demo.json: guard -> idle_bat_carry puts the bat 10 cm into the chest; going via
windup_high still puts the knob 11 cm into the belly on the way down. Next: a transition table (each pair: "direct"
or "via <pose>"), every path checked frame by frame like the poses.
