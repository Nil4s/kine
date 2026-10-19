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
- **Hitstun / blockstun**: frames the target cannot act after being hit or blocked. Not measured by Kine (it has no second fighter
  reaction model yet).
- **Frame advantage (on hit / on block)**: the difference between the attacker's and the defender's recovery frames after a
  connect. Not measured by Kine.

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
