# Clips placed as strips: what Kine matches from Blender's NLA and Maya's Time Editor

GAP_ANALYSIS row 12. Kine already had layers (NA1-NA3). It did not have reusable actions: a walk cycle made once and placed in many scenes. This is what we learned and what `scripts/clips.gd` matches. Nothing here was copied from Blender or Maya code: the formulas are written from the manuals' descriptions and from how the tools behave.

Sources (read 2026-10-18):
- Blender manual, *Nonlinear Animation*: Tracks, Strips, the Sidebar's strip properties (docs.blender.org/manual/en/latest/editors/nla/). Its words: Frame Start/End "will move the strip while keeping its duration constant"; Extrapolation "whether the action will influence the frames before/after its boundaries" (Hold, Hold Forward, Nothing); Blending "how to combine the action's property values with those of the tracks below" (Replace, Combine, Add, Subtract, Multiply); Blend In/Out "how many frames it takes for the strip's influence to ramp up at the start and wind down at the end"; Playback Scale "makes the animation play more quickly (scale < 1) or slowly (scale > 1)"; Repeat "makes the action play multiple times"; Animated Influence, Animated Strip Time.
- Blender's F-Curve **Cycles** modifier, mode *Repeat with Offset*: each cycle starts where the last one ended. This is how Blender carries a walk's root forward.
- Maya Help, *Time Editor*: clips on tracks, with Speed / Scale, Loop (before and after), Hold, clip Weight, and **Relocate** / root offset (a clip's root moved so it continues from the clip before). These were not fetched this session. The Autodesk help page came back empty, so this is from my memory of the docs, and the names may differ slightly by version.

## The terms in Kine

| Blender / Maya | Kine | Notes |
|---|---|---|
| Action (by reference) / Time Editor source | a scene file (`scenes/*.json`) or a pose / move (`moves/`, `poses/`) | **By reference**: the clip stores the path (`"src"`), never a copy. Edit the walk once and every scene that places it plays the new walk. A pose is one card held 1 s. A keyed move (`"keys"`) becomes cards at its key times, with Moves' own smoothstep. |
| Strip / clip | `S.clips[k]`, a bar under the cards on the timeline | file key `"clips"`, written only when there are any |
| Frame Start | `"start"` (s) | dragged on the timeline (one undo step) |
| Repeat | `"repeat"` (whole number of times, 1 or more) | Blender also allows fractional repeats. We don't. |
| Playback Scale | `"speed"` = 1 / scale | 2 means twice as fast and half as long |
| Blend In / Out | `"bin"`, `"bout"` (s) | linear ramps, as Blender's |
| Influence | `"w"` 0..1 | not keyable yet (Blender: Animated Influence) |
| Extrapolation: Nothing / Hold / Hold Forward | `"extra"`: nothing / hold / hold_forward | |
| Blending: Replace / Add | `"type"`: replace / add | Combine, Subtract and Multiply are not done |
| (Maya: a character set or a mask on the clip; Blender: the action only has some bones' channels) | `"mask"`: all / legs / upper / arms / arm_l / arm_r | how a walk goes under an attack: a walk on `legs` |
| Cycles modifier *Repeat with Offset* / Maya Relocate | each repeat's hips moved by the cycle's step | always on for repeats |
| Mute | `"mute"` | |

## The formulas (scripts/clips.gd)

Let the source last `L` s (`Scene.length()` of the source; a pose is 1 s). Take a strip with start `s`, repeat `r`, speed `v`, blend in `bi`, blend out `bo` and influence `w0`.

- **Length** `D = L r / v`, and the strip ends at `E = s + D`. (Blender: (action end - action start) x scale x repeat.)
- **Strip time to source time**: inside `[s, E]`, `u = (t - s) v`, the cycle is `k = min(floor(u / L), r - 1)` and the source time is `lt = u - k L`. The `min` makes `t = E` read `lt = L` of the last cycle, the source's last frame. Blender does the same at a strip's end, so that the last frame is not wrapped back to the first.
- **Weight**: `w(t) = w0 x ramp_in x ramp_out`, with `ramp_in = clamp((t - s) / bi, 0, 1)` (1 when `bi = 0`) and `ramp_out = clamp((E - t) / bo, 0, 1)`. These are linear, as Blender's strip influence over the blend in / out frames.
- **Extrapolation**: *nothing* means no effect outside `[s, E]`. *Hold* holds `lt = 0` before the strip and `lt = L` (of the last cycle) after it. *Hold forward* holds only after. In a held region the weight is the strip edge's: 0 if that side has a blend, so a held pose never pops on at the edge. This is our choice, so that the weight stays continuous.
- **Replace**: for each masked joint, `a = a_below + w (a_clip - a_below)`. The pelvis's whole-body turn goes the short way round, as the cards' blend does. The hips' position (root) follows the same lerp when the mask has the root (all, legs).
- **Add**: `a = a_below + w a_clip`. Kine's angles are measured from rest, so this is Blender's Add on rotation channels. The root adds `w (o_clip(t) - o_clip(0))`, the travel since the strip began, not the absolute hip height.
- **Root motion across repeats** (cycle with offset / relocate): `step = o(L) - o(0)` with the height dropped (x and z only). Cycle `k`'s hips are `o(lt) + k step`. A walk repeated 3 times travels three cycles' distance; it does not jump back to its start each cycle. The height is not accumulated, because a cycle's height returns, and accumulating it would sink a walk that ends a millimetre lower.
- Every angle a clip writes goes through `Body.clamp_ang`, so a clip cannot push a joint past its limits.

## The evaluation order, and why

`Scene.apply`: **cards** (part keys, planting and the floor included) -> **clips**, in list order -> the layers (YY9, NA1) -> breathing -> **IK** -> **constraints** -> the limits.

- A clip is **base motion**. In Blender, NLA strips are the actions under the one being tweaked. Kine's cards are the scene's own action, and they fill the whole timeline. So a strip has to be evaluated over them where it plays, or a Replace strip could never show. Outside its strip (with extrapolation *nothing*), the cards play as they are.
- Later clips sit over earlier ones (Blender: upper tracks over lower ones).
- **Layers come after clips.** Maya's animation layers are adjustments over the base animation, clips included. A head-turn layer should turn the head of the walking body, not be replaced by the walk.
- **IK and constraints come after everything.** In Blender the constraint stack runs on the finished animated pose (NLA included), and our IK pass is that kind of correction. A hand pinned to a table stays pinned while a clip moves the body.
- A **source** is played by its own `Scene.apply`, on a scratch body: its floor, its pins, its own layers, IK and clips (at most 3 deep, so a loop stops). A clip at weight 1 with mask *all* is the source as opening its file would play it.

## What is not done

- Combine, Subtract and Multiply blending; keyed influence; keyed strip time; fractional repeat; reversed strips.
- Auto blend from neighbouring strips; transitions between strips; a strip's own action range (it always plays the whole source).
- The weapon stays the cards'. A clip moves the body, not the weapon in it. With a two-hand grip, the off hand is put back on the weapon after a clip that moves the arms.
- Root motion turning: a walk that curves accumulates its step in the source's own frame, not rotated by the cycle's turn (Maya's relocate handles orientation too).
- A clip does not lengthen the scene: the timeline and playback stay the cards' length, and a strip past the last card is drawn clipped.
