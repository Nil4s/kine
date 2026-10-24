# Frame data: how the fighting-game community defines the terms

Source for the Kine implementation in `scripts/frame_data.gd`. The definitions below are the community convention as used on
SuperCombo and Dustloop (the two main frame-data wikis). Those pages could not be fetched while writing this (HTTP 403 / 404
and a certificate mismatch), so the wording is from the convention itself, not quoted from the live pages. Re-check the
wiki glossaries before quoting them publicly.

## The terms

- **Frame**: one tick of the game's clock. Fighting games run at 60 fps, so a frame is 1/60 s. Kine's `fps` setting (24, 30, 60, 120)
  picks the clock the counts use.
- **Startup**: the frames from the input (the first frame the move can be seen) until the first **active** frame. A move with
  startup 10 is first dangerous on frame 11 counting from the press.
- **Active**: the frames in which the move's hitbox is out and can hit. Multi-hit moves list each hit's frames; the common
  convention counts **first active frame to last active frame** as the active length, so a gap between two hits is inside
  "active". Kine follows that convention and reports the gap count separately.
- **Recovery**: the frames after the last active frame until the character can act again (back to a neutral state where a
  new input can start). Kine's recovery runs from the last active frame to the scene's end.
- **Total**: startup + active + recovery, the whole duration of the move. Kine checks `startup + active + recovery = frames`.
- **Hitbox**: the volume that deals damage on an active frame (the striking part). **Hurtbox**: the volume that takes damage (the
  body). Kine's hitboxes are the bat's two capsules, or the striking limb's two capsules when no weapon is held; its hurtboxes are
  the body capsules.
- **Hitstun / blockstun**: frames the target cannot act after being hit or blocked. Measured from the defender's reaction clip
  since N080 (below).
- **Frame advantage (on hit / on block)**: the difference between the attacker's and the defender's recovery frames after a
  connect. Measured since N080 (below).

## How Kine measures it

- The frame is **active** when the striking tip (the bat's knob-to-tip end, or the striking hand or foot when no weapon is
  held) moves faster than `FrameData.TIP_SPEED` (8 m/s) toward the target (+Z, the hero's facing; toward the dummy when one is
  placed), OR the weapon is inside the dummy (`Dummy.touch`).
- Startup, active and recovery come from the active frames as above; frame 0 is the scene's first card.
- Frame data is in the body's own units: metres, +Y up.

## Caveats

- Kine's startup counts from the scene's first card, so a wind-up in the card before the strike counts as startup. Real
  frame data counts from the input, which the scene does not have.
- Kine's active frames are a speed threshold, not a hitbox that the game authors. The threshold is a choice, and the bat's
  real strike speed is 10-20 m/s or more.

## Hit and hurt boxes per frame (ROADMAP 36)

The user draws boxes over frame ranges; the export carries them next to the automatic frame data. The maths is
`scripts/hit_boxes.gd`, the commands and dialog `scripts/hit_boxes_ui.gd`. Frames are the frame data's fps (`f / fps` seconds).

- **Attack box (hit)**: a capsule riding on a part (any body capsule, the bat's `bat_handle` / `bat_barrel`, or the off-hand
  `wep2_*`). Its ends are the part's capsule ends moved by optional offsets `da` and `db`, in the part's own frame, so it
  moves with the part. `r` overrides the radius. `damage` and `hitstun` (frames) ride with it.
- **Vulnerable edit (hurt)**: a body capsule's radius times `scale` (shrink below 1, grow above 1) over a frame range.
- **Off (hurt, `off: true`)**: that capsule has no hurtbox for those frames. Part `*` with off is **invincible**.
- Ranges are inclusive (`f0` to `f1`). Without any edit the hurtboxes are one capsule per body segment, as before.

**Scene file**: the key `boxes`, a list of these entries, written only when there is one (a scene without it saves as before).
Mirror swaps the twin part and negates the x of the attack box offsets.

**Export** (the frame data JSON, same file, extra fields only when boxes exist):
- top level `boxes`: the scene's entries as the file keeps them.
- each frame's `hitboxes`: the automatic hitboxes on active frames, plus the user's attack boxes on the frames they cover.
  An attack box has `"src": "box"`, `"part"`, `"damage"` and `"hitstun"`; the automatic ones have only `a`, `b`, `r`.
- each frame's `hurtboxes`: the body's capsules with the edits applied (an invincible frame has none).
- `a` and `b` are in metres, Y up, in the body's own space.

**Limits**: attack and vulnerable volumes are capsules only, not boxes. Attack boxes do not change which frames are active:
startup, active and recovery stay the automatic measure.

## Hitstun, blockstun and frame advantage (INNOVATIONS N080)

Code: `scripts/frame_advantage.gd` (FrameAdvantage). Test: `tests/frameadv_test.gd` (`frameadv:h`).

**Where the conventions come from.** The community formula is "advantage = hitstun (or blockstun) - (active frames remaining +
recovery)", positive = the attacker acts first, as written in fan frame-data glossaries (Smashboards frame data threads for
Smash 4, e.g. https://smashboards.com/threads/sheik-frame-data-thread-3-6.384275/; the Hisouten wiki's "Frame advantage" page,
https://hisouten.koumakan.jp/wiki/Frame_advantage, whose worked example is blockstun 20 - (2 remaining active + 14 recovery) = +4).
Those pages were seen only as search-result excerpts while writing this (the wiki served a bot-check page, SuperCombo / Dustloop
were not reachable, as above): UNVERIFIED wording, re-check before quoting. 60 fps is the genre's clock (as above).

**Kine's counts** (frame f = the pose at f / fps, the attacker's FrameData frames):
- **Contact frame c**: the first frame whose pose has the attacker's part in the defender (Dummy.fighter_hits onset, rounded up),
  inside the active span; with a reaction CLIP and no second fighter, the first active frame (a chart assumes the first active
  frame connects).
- **Recovery end R** = the first frame the attacker can act = last active + recovery + 1 = the frame count.
- **Stun end E** = the first frame the defender can act: the first frame after his reaction's peak at which every joint and end
  point (relative to his pelvis, in his own space, so knockback travel is not stun) is back within **2 cm** of the pose he was hit
  in, and stays so for 3 frames (or to the clip's end).
- **Hitstun / blockstun** = E - c - 1 (the frames after the contact frame). With it the formula above holds exactly:
  E - R = stun - ((last - c) + recovery), last - c being the active frames left after the contact frame.
- **Advantage** = E - R on hit and on block. **Punishable** (on block): the defender's fastest move input on E is first active
  on E + startup (Kine's startup = frames before the first active frame); it lands before the attacker can act when
  E + startup < R, i.e. -advantage > startup.

**The tolerance (HEURISTIC).** 2 cm: wider than what a played blend leaves (the card maker's 1 deg replay tolerance is about
1 cm at a hand), the same size as human_limits.gd's TOUCH ("there"); 3 settle frames so a spring crossing the guard once is not
"back". No paper sets either. It matters for small reactions: combo3's first contact (a 3.4 cm head reaction baked by
HitReaction) gives hitstun 11 at 1 cm, 6 at 2 cm and 0 at 5 cm (the reaction never leaves a 5 cm guard).

**Where it shows.** The frame strip (two fighters on the stage: "on hit +N (hitstun N), on block ..." after the strip), the frame
data export (an `exchange` object, only when there is one: a one-fighter export is as before), and serve's `frame_data`
method (default: the frame data without per-frame boxes; `{"exchange": true}` or `{"hit_clip", "block_clip"}` opt in;
`{"moves": [paths]}` gives the defender's moves for punishable; `{"frames": true}` adds the boxes).

**Limits.** The whole scene is one move (combo3's 280 frames are one startup / active / recovery, so its advantage is the
combo's, -222 on hit); the reference is the pose he was hit in, so a defender who walks on after the hit is never "back"; the
block reaction is a clip the user gives (Kine has no block-reaction model); no hitstop, no game state machine: what the
animation shows.
