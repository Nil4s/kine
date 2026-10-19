# Graph editor depth: what Blender's Graph Editor does, written as the formulas Kine implements (round 51, GE)

Source: the Blender manual's own text (projects.blender.org/blender/blender-manual, `manual/editors/graph_editor/`
`introduction.rst`, `channels/introduction.rst`, `fcurves/properties.rst`, `fcurves/modifiers.rst`; read 2026-10-18).
Only the manual was read. No Blender source code was read or copied (it is GPL). Where the manual does not pin a
number down, the choice below is ours and says so.

## Channels (GE1)
Manual: the Channels region "shows a tree of items (objects, bones...) and their animated properties ... also being
called channels"; each has a Hide toggle ("Hides the keyframes and curve associated with the channel. Use Ctrl-LMB to
solo"). Curve colour, `Display Color`: "Auto Rainbow: assigns a unique color to each curve"; "Auto XYZ to RGB".

Kine: a channel = (part, angle), with angle 0 bend, 1 side, 2 twist. With Channels on, every part that has part keys is
listed (the picked part first, then the others by name), with three channels each. Colour, Auto Rainbow: channel k of
N gets `hue = k / N` (saturation 0.75 and value 1.0 on the dark theme, 0.9 and 0.72 on the light one: our choice). A
click on a row hides or shows the channel, and Ctrl+click shows only that channel. With Channels off, the single-part
editor uses X/Y/Z in red, green and blue, as before.

## Selecting and transforming keys (GE2)
Manual: "Box Select: lets you drag a box and selects the keyframes ... inside it". Pivot Point: "Bounding Box Center:
center of the smallest possible box around the selected keyframes; 2D Cursor: the intersection between the Playhead
and the horizontal Cursor line". "Cursor Value to Selection: places the 2D Cursor at the average value of the selected
keyframes".

Kine:
- A box selects every dot `(t_i, v_ic)` of a VISIBLE channel whose drawn position lies inside the rectangle.
  Shift+click adds or removes one dot.
- A key's time is shared by its three angles, so a selected dot moves its key's time, and only that dot's angle.
- Scale about a pivot `(p_t, p_v)`: `t' = p_t + f_t (t - p_t)` and `v' = p_v + f_v (v - p_v)`. Nothing is snapped,
  so a factor of 1 leaves a value bit for bit as it was. If any key would go below 0 s or meet or pass a neighbour
  (gap < 2 ms), the whole scale is refused: our choice, where Blender lets keys cross. The joint limits clamp the result
  and report how many values they clamped.
- The pivot is the 2D cursor `(playhead, cursor_v)` (a right click sets `cursor_v`) or the box centre
  `((min t + max t) / 2, (min v + max v) / 2)` of the selected dots.
- Every move or scale is one undo step.

## Normalize (GE3)
Manual: "Scales the display of each curve so that they all (appear to) occupy the same value range, going from -1 to
1 ... the area outside the normalized value range is darkened."

Kine: for each channel, `lo` and `hi` are the min and max of the drawn line. That line is `value_at` sampled every 2 px
across the view plus at every key time, with modifiers included. The drawn point is
`y = y_-1 - (v - lo) / (hi - lo) * (y_-1 - y_+1)`, where the +1 and -1 rows sit 8 px inside the plot's top and bottom
(our choice) and the strips outside them are darkened. A channel that moves less than 0.01 deg is shown as
`mid +- 0.5` so its float dust is not blown up. This is display only: the scene's data is never touched, and a drag in
this view converts the mouse movement back to degrees with that channel's own scale.

## F-curve modifiers (GE4), the stack on a joint's first key (scripts/part_keys.gd)
Manual, Cycles: "Makes the curve repeat itself. ... has to be the first modifier in the list. Before/After Mode: No
Cycles / Repeat Motion / Repeat with Offset ('offsetting each copy vertically so that its first keyframe matches the
previous last keyframe') / Repeat Mirrored ('flipping every other copy horizontally'). Count: the number of copies to
create. A value of 0 means infinite."

Kine `{"type": "cycles", "before", "after": none|repeat|offset|mirror, "before_n", "after_n"}`. The keyed span is
`tf..tl` with period `P = tl - tf`, and `E` is the stack below the modifier. Outside the span, on a side whose mode is
not none:
- `L = floor((t - tf) / P)` and `u = tf + (t - tf) - L P`.
- If the count `n > 0` and `|L| > n`, then `L = +-n` and `u = tl` (after) or `tf` (before): the end of the last copy
  is held.
- mirror: when `|L|` is odd, `u = tf + tl - u`.
- The value is `E(u)`, and offset adds `L (E(tl) - E(tf))`.

Inside the span the modifier changes nothing. `add_mod` puts Cycles first and refuses a second one, following
Blender's rule. Not implemented: Blender's cycle-aware automatic handles at the wrap (our auto handles see only the
keys).

Manual, Noise: "Replace: adds noise in the range [-0.5, 0.5]. Scale: the horizontal scale ... Strength: the vertical
scale. Offset: offsets the noise in time. Phase: adjusts the random seed. Depth: how detailed the noise function is."

Kine (DD2's noise plus offset and depth), per angle c:
- `x = (t - offset) / scale + phase`.
- `n(x) = sum_{o=0..depth} 0.5^o N(2^o x, seed 3 + c + 7919 o) / sum_{o=0..depth} 0.5^o`, where N is a smooth value
  noise in [-0.5, 0.5] (hashed lattice values with smoothstep between them).
- The result is `value + strength * n(x)`, so `|offset| <= strength / 2`, and the same seed gives the same curve.
- With no `offset` and depth 0, the expression is DD2's own, so older files play bit for bit as before.
- Influence ("mix") is DD2's: `keys + (modified - keys) * mix`.
- Limits (DD2) and Stepped (DD2) are unchanged.

## Restrict Frame Range (GE5), any modifier
Manual, Restrict Frame Range: the modifier applies only inside a frame range, with Blend In / Out "to fade the influence
in and out" over a number of frames from the range's start and end.

Kine: optional fields on a modifier, `range_start` and `range_end` (seconds; both present = a range, end clamped to at
least the start) and `blend_in` / `blend_out` (seconds, written only when above 0). With w(t) = 0 outside the range,
ramping linearly 0 -> 1 over blend_in from the start and 1 -> 0 over blend_out before the end (where the two ramps meet
the smaller one holds: our choice), the modifier's influence is `mix * w(t)`. A modifier with no range has w = 1 and
keeps its old expression, so old scenes play bit for bit. The curve drawn is value_at, so the ramp shows on it; the plot
is shaded outside the range and the start and end are marked. The Mods menu sets it on the picked part's last modifier
(start / end at the playhead, 0.25 s blends, clear). Not done: a per-modifier numeric panel, and Blender's own rule for
blends longer than the range (ours is the minimum of the two ramps).

Shape (GE5): with Channels on, the Shape menu (KeyBlend's tools) acts on the selected dots of every channel, each part's
dots as its own keys, one undo step. The interpolation and handle-type commands (palette: "Part key: ... interpolation /
handle") still act on the one key at the playhead.
