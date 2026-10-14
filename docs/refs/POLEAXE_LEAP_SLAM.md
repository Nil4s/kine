# Poleaxe leap slam: a traced reference (Nick 10-13: "trace its moves, will work for long warhammer and glaives")

Source: a YouTube short Nick sent (https://youtube.com/shorts/Gp5Y1Wj25fo): a game animation of a big armoured warrior
with a two-hand poleaxe vs a standing target, 30 fps. Study only: no frames from it are kept in a repo. Traced by
reading every frame (tools/see/see.py --fps 30); the skeleton tracker (tools/see/pose.py) could NOT follow the armoured
body (it locked onto the human target), so the angles here are read by eye, the TIMES are frame-exact.

Two attacks in the clip. Times are clip seconds; "fr" = frames at 30 fps.

## Attack B: leap windmill slam (3.10-4.90 s)  <- the long-weapon one
| phase | frames | length | the body | the weapon |
|---|---|---|---|---|
| drop | 3.10-3.17 | 3 fr | snaps from walking into a deep wide crouch | snaps vertical |
| LOAD (held) | 3.20-3.43 | 0.23 s | very wide stance, knees deep, chest up, turned so the weapon side is back | vertical at his right side, both hands high on the shaft (near head height), head of the weapon up |
| windmill back | 3.47-3.60 | 0.13 s | still crouched, shoulders start to turn | shaft tips from vertical to HORIZONTAL BEHIND THE HEAD (head of the weapon goes back and round) |
| rise + take-off | 3.63-3.73 | 0.10 s | legs straighten, trunk turns toward the target, back foot leaves the floor | behind the body (hidden), still circling |
| airborne | 3.77-3.87 | 0.13 s (4 fr) | knees tucked, leaning forward over the target | comes up from behind and OVER the top (the circle's high point) |
| STRIKE | 3.90-3.97 | 3 fr | lands as the weapon lands | crashes down in front, full arm extension |
| contact | 4.00 | 1 fr | | flash; target launched |
| LANDING HOLD | 4.00-4.50 | 0.5 s | very wide low lunge, front knee deep, back leg long, trunk forward | head of the weapon at/near the floor in front |
| recovery | 4.60-4.90 | 0.3 s | rises | swept up from low on the right back to the high guard |

Graded on docs/ATTACK_RULES.md (hammer row): wind-up 3.10->3.87 = 0.77 s (long, but it is a jump attack: a telegraph the
player reads), strike 3 fr (OK), recovery 4.00->4.90 = 0.9 s of which 0.5 s is the held landing (the weight, no hit-stop).

What sells it (for any long heavy weapon: warhammer, glaive, poleaxe):
1. The weapon travels a FULL CIRCLE (up, back behind the head, over, down): a long path = a heavy, fast head without a
   slow swing. The circle is the anticipation; only the last quarter is the strike.
2. The body goes DOWN before it goes UP (crouch load, then the jump): the drop telegraphs, the jump adds the body's
   weight to the fall of the weapon.
3. The strike lands WITH the feet: the landing and the hit are one beat.
4. The landing pose is held 0.5 s, very wide and low: that is where the weight shows.

## Attack A: overhead hold, dash slam (0.30-2.60 s)
| phase | frames (10 fps reading) | the body | the weapon |
|---|---|---|---|
| overhead load | 0.30-1.10 (0.8 s held) | upright, slight lean back | straight up overhead, both hands high |
| drop | 1.20-1.40 | drops into a wide crouch BEFORE the arms swing | starts down |
| dash strike | 1.50-1.60 | long low step forward (~1/3 of the screen) | comes down level, near the floor |
| contact | 1.70 | | flash, target staggers back |
| follow-through | 1.80-2.20 | rises upright | carries round to HORIZONTAL ACROSS THE SHOULDERS behind the head |
| back to guard | 2.30-2.60 | | up to vertical overhead |

## For our poser
Card plan for a long weapon (times from attack B; poses are Nick's): guard -> drop (0.10) -> LOAD (0.10, hold 0.23) ->
windmill back (0.13) -> take-off (0.10) -> airborne top (0.13) -> STRIKE/land (0.10) -> landing (hold 0.5) -> recover (0.3).
Needs: a long weapon kind (poleaxe/warhammer/glaive, ~1.8-2.0 m, head at the end), and the jump's hip height (the
offset) keyed on take-off / airborne / land.
