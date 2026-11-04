# CH7 reference: what real parkour footage says (measurement only)

Footage is used to measure, nothing from it is shipped or committed (no frames, no clips). All six are YouTube clips under
"Creative Commons Attribution license (reuse allowed)" as listed by YouTube; attribution is given here. Tracked with
see-video (MediaPipe pose, world and image landmarks); the numbers come from `an.json` per clip (image-plane metres, scale from
the median torso length, so +-15 % at best; the camera is not fixed in every clip).

| move | clip | uploader | URL |
|---|---|---|---|
| speed vault | Fast Speed Vault (11 s, 2013) | Ahmed Inuyasha | https://www.youtube.com/watch?v=zEnQk618Q1k |
| kong | FreeG Kong Vault (36 s, 2016) | Gymnastics Australia | https://www.youtube.com/watch?v=33wT6TecWWg |
| wall run | Rafa wall run (6 s, 2012) | cravencottager | https://www.youtube.com/watch?v=22hQ0bSwM5E |
| cat leap | How to Cat Leap #09 (46 s, 2019) | London Parkour | https://www.youtube.com/watch?v=UeVtDdIKEFM |
| roll | Parkour Safety Roll Practice (55 s, 2014) | My Outcast State | https://www.youtube.com/watch?v=xtU-Py2iDms |
| slide vault | Vaulting - Slide Vault - Side View - SlowMo (178 s, 2020) | London Parkour | https://www.youtube.com/watch?v=qQ3jpaoe_g0 |

Confidence key: M = measured from the tracked skeleton, E = read by eye on contact sheets, G = guess (no footage support).

## Traced numbers

| quantity | value | conf | note |
|---|---|---|---|
| horizontal hip speed, speed vault approach | median 1.4 m/s, peak 4.1 m/s | M, low | peak is a tracker jump as much as a speed; real approach reads about 4 m/s by eye |
| horizontal hip speed, kong | peak 2.5 m/s | M, low | clip is a coached demo, short run-up |
| horizontal hip speed, wall run | peak 2.5 m/s | M, low | |
| horizontal hip speed, roll | peak 1.95 m/s | M, low | |
| horizontal hip speed, slide vault | peak 1.3 m/s | M, low | slow motion clip, time base not trustworthy |
| hand plant duration (vault, kong) | about 0.15 to 0.25 s | E | a plant is brief; the tracker's wrist noise is larger than the plant |
| hip height over the obstacle | hip about 0.2 to 0.4 m above a 1 m top at the highest point | E | not measurable from the image-plane hip (hy range 0.5 to 1.6 m is mostly camera pan) |
| cat leap | none | unmeasured | the clip is a talking-head tutorial; no usable run of the move was tracked |
| landing knee flex vs drop height | NO RELATION FOUND | M | see below |

## Landing knee flex vs drop height: the footage does not give a slope

Eight landing events were found in the tracked clips (ankle apex to touchdown drop over 0.15 m; peak knee flexion in the next
8 frames). Drop (m) and flex (deg): 0.39/136, 0.42/122, 0.46/52, 0.54/144, 0.84/45, 0.90/118, 1.02/101, 1.58/101.
The least-squares line is -15 deg/m with correlation -0.16 (-39 deg/m, r -0.26 without the 1.58 m point). That is noise, not a
slope: pose tracking at 30 fps through an impact, with arm-and-leg occlusion and unequal landings (rolls absorb the drop in
the trunk, not the knee), cannot resolve it.

Consequences, stated plainly:
- The 35 deg per m used as REF_SLOPE in `tests/ch7_test.gd` (committed before this doc) has no support from the six clips. It is a guess (G).
- Bar 3 ("within 20 % of the reference slope") therefore has no measured reference. What the footage does support: flexion is
  large (45 to 145 deg peak) on every landing and varies a lot between landings.
- Needed to close it: a purpose-shot clip (drop landings off a 0.4, 0.8 and 1.2 m box, side view, fixed camera, planted feet), or a
  published drop-landing biomechanics table. Until then the monotonicity half of bar 3 is the only part that is a bar; the slope
  half is reported, not claimed as met against a reference.
