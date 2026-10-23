# Kine brand

**The mark:** a stencil K. A solid stem, a gap, and a 45° chevron whose two limbs pivot on a gold diamond. The diamond
is the centre of mass, the point every pose is checked around; the blue lower limb is the one in motion. The ends are
cut flat, and every edge is 90° or 45°. The wordmark "Kine" uses the same geometry: square terminals, a 45° K, and
angled shoulders on the n and e. The square dot on the i is the same gold.

## Files

| File | Use |
|---|---|
| `kine_mark.svg` | Primary mark (dark tile). Same as `kine_mark_dark.svg`. |
| `kine_mark_dark.svg` / `kine_mark_light.svg` | Mark on a dark / light tile. |
| `kine_logo.svg` | Primary lock-up, mark + wordmark, for dark backgrounds. Same as `kine_logo_dark.svg`. |
| `kine_logo_dark.svg` / `kine_logo_light.svg` | Lock-up for dark / light backgrounds (transparent; the tile belongs to the mark). |
| `icon.svg`, `icon.png` (256) | Godot app icon (`application/config/icon`). |
| `kine.ico` | Windows icon: 16, 24, 32, 48, 64, 128, 256. For the Windows export preset. |
| `concepts/` | Explored concepts: v1 (round joint chain) and `v2/` (four squared Ks; the stencil, no. 4, won). Not for use. |

All artwork is plain SVG geometry (rects and paths). No fonts.

## Colours

From `scripts/tok.gd`, so the brand and the app share one palette. Dark is primary.

| Role | Dark (primary) | Light | Tok token |
|---|---|---|---|
| Tile | `#16171B` | `#F4F4F6` | `panel` |
| Stem, upper limb, wordmark | `#ECEFF4` | `#1A1C21` | `text` (light) |
| Limb in motion | `#73BFFF` | `#2966CC` | `s_hips` (dark) / `accent` (light) |
| Centre of mass (diamond, i dot) | `#FFC733` | `#F2AD00` | `focus` (dark) / `pick_limit` (light) |

## Geometry (64-unit grid)

Tile 64 with a corner radius of 10. Stem 9 wide, x 10 to 19, y 12 to 52. Chevron limbs 9.5 wide at 45°, apex at (31, 32),
cut flat at y 12 and 52. The diamond is centred on the apex with a half-diagonal of 8.

## Clear space

Keep at least **the stem width (9/64 of the tile)** clear around the mark. Around the lock-up, keep **1/4 of the
tile height** on every side.

## Minimum size

- Mark: **16 px**. It was checked pixel by pixel at 16 and 32; the stem, the gap and the chevron stay separate.
- Lock-up: **32 px tall**. Below that, use the mark alone.

## Do

- Use the files as they are; scale them uniformly.
- Use dark files on dark backgrounds and light files on light backgrounds; dark is the default.
- Keep the gap between stem and chevron: the stencil split is the mark.

## Don't

- Don't round the corners or ends, close the gap, or add outlines, gradients, glows or shadows.
- Don't swap the colours: the upper limb is bone, the lower limb is blue, the diamond is gold.
- Don't rotate, mirror or re-angle the chevron.
- Don't set "Kine" in a typeface; the wordmark is drawn geometry.
- Don't use anything in `concepts/`.

Kine by Teschima Studios.
