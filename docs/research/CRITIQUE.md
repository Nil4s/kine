# Critique that points at frames (ROADMAP 11): where each number comes from

Code: `scripts/critique.gd`, opened by **Check: critique the animation** (the default Check never runs it). Every finding is a
**NOTE** with a time and a plain-words fix. Notes are never MUST FIX.

Status key: **ours** = a number set in this repo (no recorded human number was found for it); **brief** = set by Nick's
brief for this item; **physics** = a constant of nature; **book** = a principle from an animation book (the book was not
opened in this session: the principle is cited by name, and no number is taken from it).

| rule | principle | reads | bar | number from |
|---|---|---|---|---|
| ANTICIPATION | Anticipation (Williams, *The Animator's Survival Kit*; Thomas & Johnston, *The Illusion of Life*): a small move the other way before a big one | a fast move (the weapon tip, or the right hand unarmed, over `FAST` = 3 m/s) and, in the 0.1-0.4 s before its start, the tip, the hips and the left hand | one of them goes at least 3 cm the other way, against the swing's own way (the chord from the window's start to the peak) | the window: **brief** (0.1-0.4 s). FAST 3 m/s: **ours** (the same bar as `Rulebook.STRIKE_MIN`). 3 cm: **ours**. Part skipped when its own move is under 3 cm: **ours** |
| FLOATY | Weight / timing: a body in the air has nothing to push against, so it falls at g | both feet off the floor for 6 frames (0.1 s) or more; the centre of mass's vertical acceleration over the run, and over its first 9 frames (0.15 s) | the fall is at least half of g (4.9 m/s^2 down) | g = 9.81 m/s^2: **physics** (`Scene.G`). Half of g, the 6-frame air time and the 0.15 s ease window: **ours** |
| FOLLOW-THROUGH | Follow-through and overlapping action (Williams; Thomas & Johnston): the hit carries on and slows, it does not stop | after each strike, the frames from the speed's half-peak to under a tenth of the peak | under 2 frames (33 ms at 60 fps) = a dead stop | 2 frames: **ours**. A real arm's slowdown is not measured here; the 0.2 s in the message is a rough **ours** guide |
| EVEN TIMING | Timing (Williams; Thomas & Johnston): the spacing of the moves gives the weight and the rhythm | the card lengths (move + hold) of cards 2 and on, with at least 4 cards | the spread (std / mean) under 10% | 10%: **ours**. Four cards minimum: **ours** |

## What is not claimed

- No recorded human data was found for these four rules. The rulebook's other rules (HUMAN LIMITS, GAIT, JUMP) have real
  numbers behind them (docs/research/HUMAN_LIMITS.md, docs/MOTION_RULES.md); these do not. Their bars are a starting point
  to be checked against real footage (the see-video skill can take a real move frame by frame), not a verdict.
- SETTLING (the centre of mass after a landing) is not graded: only the air and the start of a fall.
- TWINNING is item 19 of the roadmap and is not here.
- The 12 principles are not all covered: these four are the ones whose timing and motion the rulebook already reads.
