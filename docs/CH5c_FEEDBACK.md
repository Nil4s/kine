# CH5c feedback: wet cobbled lane at night on Godot PBR + SSR, matched to ref2.jpg

Branch w4-ch5c. Status: **PARKED after the fix pass for lead verdict RED 1 (11-04 12:40).** Files: scripts/wet_street.gd, tests/ch5c_test.gd,
tools/ch5c_photo_estimates.py (every scene number from the photo), tools/ch5c_prep_tiles.py, tools/ch5c_side.py (side-by-side), assets/ch5c/.
Renders: C:/Users/Nick/tools/kine_workers/out/ch5c/ch5c_night.png; side-by-side ch5c_side_by_side.png = [render's photo frame | ref2.jpg | full render].
Logs of the final run: C:/Temp/claude/w4-ch5c/w13.

## 1. Result (final run, from the commit before this doc; ch5 / ch5b bars unchanged)

| bar | result | number | vs RED 1 |
|---|---|---|---|
| A water + control | ok / ok | 0 wrong of 1000; painted control 256 wrong | = |
| C rough + control | ok / ok | n 55, 0 bad | = |
| E scene (x3) | ok | sigma 2.29 mm; joint 46 mm below the stone | = |
| B mirror | **FAIL 1 of 21 lines** | poses 0, 1 at 1.7 / 2.3 px; pose 2 13.5 px (its puddle is at the plinth, x 0.90; the plinth hides most of it) | was 4 fails |
| B controls, B count | ok | 3 pairs contain the lamp | = |
| D streak | **FAIL** | aspect 0.78 vs 2.32 (the lamp image in the B puddle is the brightest blob) | was 1.21 |
| G pool | **FAIL** | 0.42 vs 0.62 (-32 %); it passed (0.64, then 0.53) before the puddles shrank | was ok |
| F glint (grid points) + control | **FAIL** / ok | 2.2x (n 932) | was 2.4x |
| F2 sheen (per-stone highlight) | **ok** | 3.3x, n 233 stones | was 1.6x |
| F2c control (wet scene, DRY stone roughness), new | ok (fails the bar) | 1.1x | new |
| H veil (photo's tarmac patch) + control | **FAIL** / ok | wet 0.389 vs band 0.227-0.378 (photo 0.302, +29 %); dry 0.118 | was 0.061 |
| S1 / S1B dark street / frame | **FAIL** / **FAIL** | 40.2 % / 40.5 % (need < 15 %). THE PHOTO ITSELF: 49.6 % of its lane pixels and 31.9 % of its frame are < 0.02 | was ok |
| S1B control | ok | 76.2 % | = |
| S2 penumbra / S2 control | **FAIL** / **FAIL** | 2.8 px / 3.1 px: both at the shadow-filter floor | control was 16.5 px |
| S3 lamps | ok | 4 | = |
| easypart / peasy3 / freestart | PASS 73 / 23 / 14 | | |

## 2. Engineering level: rendering / optics physics **L2-L3**
L2 reached: the scene is the photo's place and camera, every dimension derived and printed (tools/ch5c_photo_estimates.py): f = 1630 px from the
Wikimedia EXIF (Nokia Lumia 920, 26 mm-equivalent, 1.4 um pixels), camera height 1.03 m from the left wall's brick courses, wall -1.30 m, plinth
1.02 m / 0.47 m, fence 1.83 m, lamp 21.1 m away and 5.24 m up, gate 22.5 m, the tarmac patch, sett rows 90 mm. L3 in parts: GGX/Fresnel
through Godot's StandardMaterial3D, a water film modelled as water roughness (Lagarde 2013), planted controls that can fail (F2c), the exposure
calibrated on a surface no bar reads (the fence). Not L3 overall: lamp intensity, wet roughness of tarmac (0.30) and AMBIENT_WET 0.9 have no
measured source, the sett relief amplitude is a guess, and the engine's shadows and specular aliasing are not physically resolved (below).
L4 would need a measured luminaire (photometric file), a radiometrically calibrated camera (the photo is auto-exposed, 0.18 s, ISO 800) and a
path-traced reference of the same scene to check Godot against.

## 3. What Kine lacked

| needed | exists today | workaround | cost | proposed feature |
|---|---|---|---|---|
| camera match from a photo (f, height, horizon) | nothing (searched: vanishing, focal, exif, camera_match) | hand-picked points + EXIF lookup in a Python script | ~2 h, 50 lines | "Match photo camera": click two lane edges and one known length, read EXIF, set the Camera3D |
| specular anti-aliasing of baked normal maps (Toksvig / LEAN) | only Godot's screen-space roughness limiter (project default) | tried Toksvig mips in GDScript (commit a923ca93), reverted: isotropic widening turned the streak into a grey wash | 100 lines, 1 run | per-mip roughness from normal variance, ANISOTROPIC (along / across the view) |
| a "wet" material state (darkening, roughness, puddles from height) | nothing; PhotoMaterial (scripts/photo_material.gd) makes dry PBR from a picture | scripts/wet_street.gd bake | ~900 lines over 3 lanes | material "wetness" slider + puddle level on any displaced surface |
| sett / brick outlines segmented from a CC0 PBR set | PhotoMaterial derives height from luminance only (DISCOVERABILITY: found late; it would not give stone ids) | tools/ch5c_prep_tiles.py (scikit-image) | 120 lines Python | "segment tiles" step in the material maker |
| resolvable soft shadows at 20 m | Godot PCSS with a shadow atlas | atlas 8192, lamp-0 slot 4096 | S2 still unresolvable: both edges ~3 px | ray-traced or higher-res cascaded omni shadows for a chosen light |
| side-by-side render vs reference | each lane writes its own (hall_compare/*.py outside the repo) | tools/ch5c_side.py | 25 lines | shared compare tool (crop to the reference's frame, label, diff) |
| photometric lights | Godot physical light units exist as a project setting, not used by Kine scenes | lamp energy calibrated by eye-free ratio on the fence | 1 run | light presets in lumens / cd with an exposure |

## 4. What looks wrong (looked at ch5c_side_by_side.png after every run)
- The glitter streak is still weak: the photo's stone tops along the lamp line are saturated white from the bottom of the frame to the lamp base;
  ours glint on a few stones and the brightest thing on the ground is the B puddle's lamp image (a round blob, D 0.78).
- At 1280x720 with the photo's own field of view the photo frame is only 480 px wide, so mid-distance setts are 1-2 px: their glints alias to
  sparkles. The photo, downscaled the same way, integrates them into a streak. Toksvig (isotropic) went too far the other way.
- A bollard (bar S2) and three puddles (bar B) stand in the lane; the photo has neither. The puddle of pose 2 sits against the plinth.
- The tarmac patch reads as a clean grey ellipse; the photo's is darker, irregular and soft-edged.
- Walls and fence are close in tone (fence calibrated to the photo) but flat: no ivy/graffiti, no gutter, no roofline; the white house front
  beyond the gate is a flat lit box; the sky is a flat olive (no lamp-lit haze gradient); no lens star on the lamp (the photo has one).
- Near setts: rectangular rows now (Cobblestone Floor 09), but their tops are lumpier than the photo's smooth loaf-shaped setts.

## 5. What changed after results (git has the diffs)
- Pre-run amendments, committed before their first run: F2's control (SSR/probe off) is retired to a printed line: it cannot fail for direct
  glints (lead RED 1); new F2c control (wet scene with dry stone roughness). H's sample region moved from the old asphalt strip (now under the
  fence) to the scene's copy of the same photo patch; band, statistic and control unchanged; every pixel sampled instead of every 2nd.
- Scene (all sources in scripts/wet_street.gd comments): layout and camera from the photo; Cobblestone Floor 09 (CC0, rectangular setts) at the
  photo's 90 mm rows; displacement prefiltered to the bake's 6 mm sampling; wet tops at water-film roughness; per-stone tilt 0.045 from the
  photo's streak half-width; sky colours in sRGB (pass 1 passed linear values: black sky); wall/fence albedo maps at tint 1; lamp energy 26 from
  the fence calibration; house lamps 6 from the photo's house tone; B puddles 0.3 m (0.62 m merged into a lane-wide pool); bollard moved off the
  B mirror paths; lamp-0 shadow slot 4096.
- Bars that now conflict with the photo, reported, NOT edited: S1/S1B (< 15 % dark; the photo is 49.6 % / 31.9 %), B poses +-1.2 m (they stand
  at the walls of a 2.3 m lane), S2 (the photo has no bollard; the edge is at the engine's filter floor whether the light has a size or not),
  F (grid points, reported in pass 1). Toksvig mips were tried and reverted (F2 fell to 3.0x, G to +40 %, the look became a grey wash).
