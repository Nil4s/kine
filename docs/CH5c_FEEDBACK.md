# CH5c feedback: wet cobbled lane at night on Godot PBR + SSR, matched to ref2.jpg

Branch w4-ch5c. Status: **PARKED after the fix pass for lead verdict RED 1 (11-04 12:40).** Files: scripts/wet_street.gd, tests/ch5c_test.gd,
tools/ch5c_photo_estimates.py (every scene number from the photo), tools/ch5c_prep_tiles.py, tools/ch5c_side.py (side-by-side), assets/ch5c/.
Renders: C:/Users/Nick/tools/kine_workers/out/ch5c/ch5c_night.png; side-by-side ch5c_side_by_side.png = [render's photo frame | ref2.jpg | full render].
Logs of the final run: C:/Temp/claude/w4-ch5c/w13.

## 1. Result (round 2, after Nick's 11-04 bar decisions and two fix passes; final run C:/Temp/claude/w4-ch5c/w16)

Status: **PARKED** (8 of the bar lines red in ch5/ch5b/ch5c; easypart 73/0, peasy3 23/0, freestart 14/0 PASS).

| bar | result | number |
|---|---|---|
| A water, C rough, E scene (+ controls) | ok | 153 water samples; C n 55, 0 bad; sigma 2.29 mm |
| B mirror (pose 2 now x 0.7, AMENDED) | **ok, all 21 lines** | 3 pairs contain the lamp |
| G pool | ok | 0.49 vs 0.62 (-22 %) |
| F2 sheen + F2c control | ok / ok | 3.2x (225 stones) / 1.2x |
| S1B control, S2 control, S3, D/F/H controls | ok | legacy 70.8 % dark; point light 4.8 px |
| D streak | **FAIL** | 0.92 vs 2.32: the B puddle's lamp image is still the brightest blob |
| F glint (grid points) | **FAIL** | 2.3x (need 3) |
| H veil | **FAIL** | 0.387 vs 0.227-0.378 (photo 0.302) |
| S1 dark lane (AMENDED: photo's own 49.6 % +-25 %) | **FAIL** | 35.1 % vs band 37.2-62.0 % (was 21.3 % before the micro-shadows) |
| S1B dark frame (AMENDED: photo's 31.9 % +-25 %) | **FAIL** | 18.8 % vs band 24.0-39.9 % |
| S2 penumbra (AMENDED: 2.5 m behind the bollard, >= 0.5 x geometric) | **FAIL** | 5.6 px vs need 6.7 (geometric 13.5 px); the point light gives 4.8 px |

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

### Round 2 (Nick 11-04: "re-derive from the photo")
- AMENDED per Nick 11-04, each committed before its first run (76174903), no other bar touched:
  - S1 / S1B: the band is ref2's own dark fraction (lane 49.6 %, frame 31.9 %, measured inside tests/ch5b_test.gd photo_dark() with the same
    luminance and 0.02 threshold) +-25 % relative (the lane's photo tolerance, as bar H). Both are measured in the render's photo frame (columns
    400-880) with the photo's lane definition (x -1.30..1.02, nearer than 19.75 m). Control: the legacy look (70.8 %) is outside the band.
  - B: pose 2 moved from x 1.2 (over the plinth) to x 0.7 in tests/ch5_test.gd (and the same pose list in ch5b, ch5c, ch5clook so the scene's
    puddles match). 3 poses, 3 px tolerance and counts unchanged. The S2 bollard moved to (0.2, -6) where the mirror paths pass above it.
  - S2: the scanline moved 2.5 m behind the bollard; bar = mean 10-90 % edge >= 0.5 x the geometric penumbra 2 r (d_rcv - d_occ) / d_occ
    projected to px (13.5 px); control: the point light must be below that (it is: 4.8 px).
- Fix pass 1: OmniLight3D.shadow_blur back to Godot's default 1.0. Godot's source (light_storage.cpp, scene_forward_lights_inc.glsl) sets
  the omni PCSS disk radius = light_size x shadow_blur, so pass 1's 0.5 halved the 0.3 m emitter. S2 rose 4.6 -> 5.6 px.
- Fix pass 2: lamp-0 micro-shadows baked over the height field into an occlusion map (ao_light_affect 1). The joints are 10-15 mm wide and
  30-46 mm deep but exist only in the normal map, which casts no shadow; lit joint floors made the lane too bright. S1 21 % -> 35 %, S1B
  14 % -> 19 %, G back inside its band.
- Why still red (not tuned): S2: Godot's PCSS produces 5.6 px where the geometry gives 13.5 px, and only 0.8 px more than a point light: an
  engine gap (Godot 4.7 has AreaLight3D, not tried). S1/S1B: the photo is bimodal (25 % of its lane is exactly 0: phone JPEG black clipping)
  while the render has no camera response curve; the remaining gap is mostly the camera, which the photo alone cannot calibrate. D/F/H: as in
  round 1 (the puddle blob, sub-pixel setts, the patch 2 % over its band).
