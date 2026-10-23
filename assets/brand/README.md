# Kine brand

**The mark:** a K drawn as a joint chain. The stem is the spine, the two arms are limbs ending in joints (blue), and the
gold dot where they meet is the centre of mass. It is the app in one shape: a body, its joints, and its balance.
The wordmark "Kine" is drawn from the same round-capped strokes, and the dot on the i is the same gold centre of mass.

## Files

| File | Use |
|---|---|
| `kine_mark.svg` | Primary mark (dark tile). Same as `kine_mark_dark.svg`. |
| `kine_mark_dark.svg` / `kine_mark_light.svg` | Mark on a dark tile / a light tile. |
| `kine_logo.svg` | Primary lock-up, mark + wordmark, for dark backgrounds. Same as `kine_logo_dark.svg`. |
| `kine_logo_dark.svg` / `kine_logo_light.svg` | Lock-up for dark / light backgrounds (background is transparent; the tile is part of the mark). |
| `icon.svg`, `icon.png` (256) | Godot app icon, set as `application/config/icon`. |
| `kine.ico` | Windows icon: 16, 24, 32, 48, 64, 128, 256. For the Windows export preset when one exists. |
| `concepts/` | The three explored concepts and `contact_sheet.png`. Not for use. |

All artwork is plain SVG geometry (paths and circles). No fonts.

## Colours

Taken from `scripts/tok.gd` so the brand and the app are one palette.

| Role | Dark (default) | Light | Tok token |
|---|---|---|---|
| Tile | `#16171B` | `#F4F4F6` | `panel` |
| Bone / wordmark | `#ECEFF4` | `#1A1C21` | `text` (light) |
| Joint | `#73BFFF` | `#2966CC` | `s_hips` (dark) / `accent` (light) |
| Centre of mass | `#FFC733` | `#F2AD00` | `focus` (dark) / `pick_limit` (light) |

The dark version is primary: Kine is a dark-first app.

## Clear space

Keep empty space around the mark of at least **1/8 of the tile width** (8 units on the 64-unit grid; the gold dot's
radius). Around the lock-up, keep **1/4 of the tile height** on every side.

## Minimum size

- Mark: **16 px**. It was checked pixel by pixel at 16 and 32; the K still reads.
- Lock-up: **32 px tall**. Below that, use the mark alone.

## Do

- Use the files as they are; scale them uniformly.
- Use the dark files on dark backgrounds and the light files on light backgrounds.
- Keep the gold dot gold: it is the centre of mass, the one idea the whole app is checking.

## Don't

- Don't recolour the joints or the dot, add gradients, glows, outlines or shadows.
- Don't stretch, rotate or re-angle the limbs; the K is a pose, and the pose is fixed.
- Don't set "Kine" in a typeface; the wordmark is drawn geometry.
- Don't put the mark without its tile on a busy image.
- Don't use the concepts in `concepts/`.

Kine by Teschima Studios.
