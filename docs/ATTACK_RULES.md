# Attack animation rules (studied 10-13, Nick: "fast animations, impactful moves, other weapons")

What game animators teach about attacks, made into numbers our tools can check. Nick's own standing rules win where
they differ (marked NICK).

## The three phases
Every attack is **anticipation -> strike -> follow-through/recovery** (Schlitter, Pixelblog 9; Gnomon "startup /
active / recovery"; Aztez "Anatomy of a Successful Attack").

| phase | what it does | our rule |
|---|---|---|
| anticipation (wind-up) | tells the player it is coming, loads the body | **light 0.15-0.30 s, heavy 0.35-0.6 s**. Too long = input lag (player side) |
| strike (the swing itself) | the weapon crosses the target | **<= 6 frames at 30 fps (0.2 s)** for any weapon (Aztez: "rarely more than 6 frames") |
| follow-through + recovery | weight, then back to guard | **light 0.2-0.35 s, heavy 0.4-0.8 s**. Too long = "sticky, vulnerable" |

- The swing is short; the WEIGHT comes from the poses either side of it (the wind-up and the hold after), not from a
  slow swing.
- Heavy weapons (hammer, two-hand axe, the 1.8 m staff swung wide) = longer anticipation + longer follow-through, NOT a
  slower swing. Light (knife, kunai, pistol whip) = short everything.
- Hold a key pose a few frames to sell weight: the top of the wind-up, or the end of the follow-through.
- **Real speed cap**: the weapon tip never beats a real one (bat ~40 m/s, staff end ~30, knife ~15: the hands top out
  ~15-20 m/s). Faster than that reads as a pop, not power. With smootherstep in-betweens the PEAK is ~1.9x the average,
  so a wide arc needs ~0.2 s, not 0.15 (bo_spin's STRIKE: 0.16 s -> tip 96 m/s, 10-13).
- Overshoot: a stopping weapon passes its final place a little and settles back.
- Arcs: the weapon tip travels on a smooth arc from stance to follow-through (no kinks); the body leads, the hands follow
  (our `natural` in-betweens already do this).
- Stance first: every attack starts from a guard that suits the weapon's weight; the motion flows from it.

## Impact (what sells a hit)
- Reach: at full extension the arm/weapon reads long (the strike pose is the most open silhouette).
- The struck body reacts FAST and exaggerated (our hit_react / ragdoll / knockdown).
- Swing trail: big, fast, smooth arc, never hiding the action (we have the trail; Nick liked trail + mocap swings).
- Hit effect: bright, very fast; dust only for heavy blows; sound bassy (layered thump).
- **NICK: no hit-stop, ever** (no world or attacker freeze on contact, 10-02). The sources use a few-frame freeze; we
  replace it with a held POSE in the animation itself (the follow-through key held 2-4 frames) and the target's fast
  reaction.
- **NICK: camera is hard-locked**; shake only as the snap-back jolt with its pause-menu toggle, used sparingly.

## Weapons
| weapon | stance | anticipation | strike | recovery | note |
|---|---|---|---|---|---|
| knife / kunai | low guard, blade forward | 0.1-0.2 s | 3-4 fr | 0.15-0.25 s | short arcs, wrist straight (no forearm twist bones) |
| bat / pipe | shoulder or two-hand guard | 0.25-0.35 s | 4-6 fr | 0.25-0.4 s | hips lead the arms |
| hammer / sledge | high or shoulder carry | 0.4-0.6 s | 4-6 fr | 0.5-0.8 s | lift from the shoulder, drop the hips into the hit |
| staff / bo (1.8 m) | two-hand middle guard | 0.25-0.4 s | 4-6 fr | 0.3-0.5 s | hand slides to the end for wide sweeps; the free hand catches (Nick 10-13) |
| spear thrust | side-on, back hand at the butt | 0.2-0.3 s | 2-4 fr | 0.25-0.4 s | straight line, the back foot pushes |

## Checked by
`tools/attack_timing.gd` (poser): per scene, the weapon tip's speed each frame -> the strike = frames above 50% of the
peak speed; anticipation = before it, recovery = after it; compared with the table for the scene's weapon.

Sources: Raymond Schlitter, Pixelblog 9 "Melee Attacks" (slynyrd.com); The Gnomon Workshop, "Animating Stylized Attacks
in Maya"; Aztez, "Anatomy of a Successful Attack" (aztez.com).
