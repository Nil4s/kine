# Style transfer: heavier, older, tired, angrier (ROADMAP 25, top-25 #12)

Code: `scripts/style_transfer.gd` (`StyleTransfer.make(file_dict, style, intensity)` returns a new scene file;
`StyleTransfer.measure(scene)` gives the walk's speed, trunk lean, peak hand speed and peak hand acceleration).
Command: `Style: make it <older | tired | heavy | angry>...` asks for an intensity (0-100 %) and saves a copy in
`scenes/_wip/<name>_<style>.json`. Test: `tests/style_transfer_test.gd` (reads `scenes/walk_bat.json`, writes only to user://).

No learned model. Each style is three operations on the scene file: (1) TIMING: each card's move and hold scaled;
(2) EASE: a card's ease preset (`linear` has the lowest peak speed for a given move time, `in` accelerates into the card
and stops hard); (3) POSTURE: one additive layer over the cards (Scene.layers, NA1), joint offsets in degrees.
Intensity scales every number linearly; 0 % returns the input unchanged.

## Status key
- **read**: the number was read in the source's text (abstract, table or a summary that quotes it).
- **excerpt**: from a search-engine excerpt; the full paper was not opened.
- **MINE**: a choice of this code, not a published value. The direction (not the size) is what the source supports.

## OLDER (slower, shorter steps, more trunk flexion, less arm swing)

| change | value at 100 % | source | status |
|---|---|---|---|
| walk speed, 70+ | 0.9-1.1 m/s; the style slows a walk FASTER than 1.0 m/s only | Bohannon & Andrews 2011, "Normal walking speed: a descriptive meta-analysis", Physiotherapy 97(3). Women 80-99: 94.3 cm/s; men 40-49: 143.4 cm/s (abstract) | read (abstract; the 70+ band is read off the decade strata, not quoted as one number) |
| walk speed, young | 1.3-1.4 m/s (for contrast only) | the gait test's own list (tests/gait_test.gd: Gait Posture 2009 PMID 19502061, 1.33 m/s) | read in the repo |
| trunk flexion | +5 deg commanded over spine_01..03 (2 + 2 + 1); measured as the spine's own flexion relative to the pelvis, +5.00 deg over the walk (4.91 -> 9.91) | direction: greater forward trunk flexion in older adults (obstacle crossing: a 13 vs 13 study, dual-task stepping: 12 young vs 10 older; search excerpts, [revistas.usp.br](https://revistas.usp.br/fpusp/en/article/view/234673)). NO level-walking number was read | size MINE; direction excerpt |
| arm swing, toe clearance | NOT DONE | an additive layer cannot shrink a cyclic swing; toe clearance is not a layer joint yet | open |

Walk_bat walks at 0.95 m/s by the measure (pelvis path over the walking cards), already inside the band, so the speed step
changes nothing on it. The style would only bite on a faster walk, which the repo has no file for.

## TIRED (lower peak speeds, longer holds, drooped head and shoulders, more trunk flexion)

| change | value at 100 % | source | status |
|---|---|---|---|
| moves and holds | x 1.5 (uniform) and ease `linear` | the peak speed of a `linear` move is its mean; smootherstep (`smooth`) peaks at 1.875 x its mean (Scene._ease) | the ease maths read in the code; x 1.5 MINE |
| head | neck_01 +6 deg forward (drops the head) | MINE | size MINE |
| shoulders | clavicle -3 deg each side (drop) | MINE | size MINE |
| trunk | spine_01..02 +3 deg each | direction as OLDER | size MINE |

Measured on walk_bat: peak hand speed 4.12 -> 1.90 m/s (see the test).

## HEAVY (a load on the body: wider base, slower acceleration, longer contacts, more knee flexion in stance)

| change | value at 100 % | source | status |
|---|---|---|---|
| moves | x 1.3 (slower acceleration) | MINE | MINE |
| holds (contacts) | x 1.5 | MINE | MINE |
| stance knee | calf_l and calf_r +6 deg (flexion, + = bent) | MINE; the direction is the knee's own rule (Fukuchi 2018 band, scripts/gait_band.gd) | MINE |
| base | thigh_r -4 deg, thigh_l +4 deg about z (outward; sign measured: thigh_r +z moves the foot inward) | MINE | MINE |

## ANGRY (faster accelerations, sharp stops, raised shoulders, forward lean)

| change | value at 100 % | source | status |
|---|---|---|---|
| moves | x 0.6 (faster) and ease `in` (accelerate, then a hard stop) | MINE on size; the direction: Montepare, Goldstein & Clausen 1987, J. Nonverbal Behavior 11(1):33-42, anger walkers read as "heavy-footed", with longer strides in some summaries | direction read in a summary; size MINE |
| shoulders | clavicle +5 deg each side (raise; sign measured: clavicle +x lifts upperarm_l) | MINE | MINE |
| trunk | spine_01 +3 deg (forward lean) | Roether, Omlor, Christensen & Giese 2009, J. Vision 9(6): posture and speed features separate emotions (paper not opened) | direction excerpt; size MINE |

Measured on walk_bat: peak hand acceleration 25.5 -> 273 m/s2 (the test; a second difference at 60 fps, so a noisy number).
At the full request (moves x 0.6, ease in) the Check flagged 4 FAILs (HEAD QUIET, SEQUENCE). The cap (StyleTransfer._angry_cap)
keeps the move at the shortest factor the Check passes: about x 0.63 here, the ease kept at in.

## Results of the test (walk_bat, 100 %)

Run on the final code: all seven bars pass (`tests/style_transfer_test.gd`). Bar 3 measures the spine's own flexion
relative to the pelvis (StyleTransfer "flex"), which is the commanded angle; the pelvis-to-head vector ("lean") reads
less (3.2 deg) because the spine's hinge sits above the pelvis, so a head-based number is not the commanded one.
Bar 7: ANGRY's cap keeps the Check at the source's FAIL count (0 new).

## Not done
- The cited level-walking trunk-flexion number (a number was not read, so the +5 deg is MINE).
- Arm swing and toe clearance (no layer can scale a cycle yet).
- A faster walk file to show the older speed step working (walk_bat is already in band).
- The ANGRY cap is global (one move factor for all moves), not per move; a per-move cap would let the quick moves go further.
