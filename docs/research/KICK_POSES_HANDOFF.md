# Kick poses for BODY ACCEL (N031): handoff, 2026-10-23 (WIP, stopped on budget)

Task: make text_blocking's 3 kick fails pass by fixing StrikeBlocking's kick POSES, not timing or bars. Not done.
No suite was run (only dev harnesses). Bars still to check: text_blocking (0 fails), recognize, bodycaps, weightxfer, templates.

## Numbers (built through TextBlocking.build, after its fix loop)
| kick | before (e84bf9a) | WIP state committed (flat back foot, LOAD_SHARE 0.5) |
|---|---|---|
| roundhouse | foot 7.07 m/s; COM start 6.3 / stop 7.9 / rise 10.8; TIPPING 2.37-3.02 s; recognized roundhouse | foot 14.63 m/s; start 7.8 / stop 7.8 / rise 13.7; no TIPPING; **recognized "knee"** (foot peak lands in the chamber); HITCH warn |
| side kick | foot 10.29; stop 10.5 WARN at 1.65 s | foot 10.28; pin miss 0.097 m on the back foot in the load; BALANCE warn, FOOT SLIDE warn, knee JOINT SPEED warn 1914 deg/s |
| front kick | foot 15.73; start 7.1 / stop 7.8 | foot 14.67; start 7.5 / stop 8.2; nothing slowed, no findings |

Raw poses (base timing, no fix loop), guard -> chamber before: roundhouse start 17.0 / stop 17.4 m/s^2, side kick 12.5 / 14.7, front kick 14.2 / 14.8.

## What changed (scripts/strike_blocking.gd)
- New `_load()`: a two-feet-down card where the hips move until the COM is LOAD_SHARE of the way from the guard's COM to the
  chamber's (the chamber is built first, then its COM is the goal); hips sink up to LOAD_SINK (0.04) if the back foot can't reach.
  It also bends the back toes so the toe tip sits on the floor (needed only for a heel-up back foot).
- Every kick now runs: guard -> **anticipation: load** -> chamber -> strike -> re-chamber -> **recovery: foot down** (the load
  pose again) -> guard. Constants KICK_LOAD 0.20 s, KICK_LAND 0.15 s (inside the existing anticipation and recovery retimes).
- The load's pelvis turn and support-foot heading per kick: front (-3,0,-15) / head 0; roundhouse -20+30sg / 0.5sg; side -20+40sg / 0.75sg.

## What I learned (each one measured)
1. The roundhouse's chamber is a FLOW card, so `first_of_strike` folds it into the strike: a COM lurch there made the fix
   loop slow the STRIKE (that is why the foot fell to 7.1). Putting the weight shift in a non-flow load card moves it into the anticipation.
2. A HEEL-UP back foot is not pinned (`Scene._pinned` needs both cards flat), so between the guard and the load it slides
   about 10 cm (FOOT SLIDE) and the foot moves at 6.4 m/s while it should stand. Its unbent toes also dug 5.6 cm under the
   floor, and `Body.ground()` lifted the whole body that much in playback (RISE 20.9). The toe bend fixes the dig, not the slide.
3. A FLAT back foot only reaches with LOAD_SHARE <= 0.4-0.5 and the pelvis turned <= -10 deg (probe: share 0.6 misses by
   0.06-0.13 m). At that point the back knee is straight (calf ~0), so the chamber folds it further: knee JOINT SPEED.
4. With the load in front, the flowing chamber carries the foot further, so the roundhouse foot peaks in the chamber and
   MoveRecognizer reads the bent knee at "contact" as a KNEE strike.
5. A support-foot heading of 1.0+ rad in the load, with the hips turned only 10-30 deg, can't be planted (misses 4-7 cm, hips sink).

## Next steps
1. Per kick, use the load's pelvis turn and share from the probe table: flat back foot, pelvis <= -10 deg, share 0.4-0.5.
   The side kick's 20 deg pelvis is why its back foot misses.
2. Roundhouse recognizer: make the strike's foot speed beat the chamber's. Either start the flow run at the chamber (the
   load ends with the knee already moving forward), or drop `flow` on the chamber now that the load does the wind-up. Check that HITCH and SEQUENCE stay clean.
3. Side kick: after step 1, re-read its stop peak in the recovery. "foot down" should take the deceleration, as it does for the roundhouse.
4. Then run, each alone with -j 1 and timeout 1200: text_blocking, recognize, bodycaps, weightxfer, templates.
5. Dev harnesses (not in the repo): `scratchpad/kp/dev.gd` (build + COM peaks per channel), `raw.gd` (poses at base timing),
   `spd.gd` (foot max per card), `ld.gd` (probe _load reach). The strip renderer is `scratchpad/tb/render.py` + `render.gd`:
   point HERE at this worktree and pass the scene JSONs that dev.gd saves.
