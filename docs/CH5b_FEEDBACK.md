# CH5b feedback: the wet street without the black void

Branch w4-ch5b (w4-ch5 merged in). Files: scripts/wet_street.gd, scripts/wet_street.gdshader, tests/ch5b_test.gd (extends tests/ch5_test.gd).
Screenshots (1280x720, pose x = 0): C:/Users/Nick/tools/kine_workers/out/ch5b/ch5b_night_final.png, side by side with the CC BY 2.0 photo
(docs/CH5_REFERENCE.md ref2): out/ch5b/ch5b_side_by_side.png. Control look: ch5b_night_legacy.png.

## What changed (Nick: "the shadows are killing the vibe")
- Diagnosis: the old scene was one lamp, near-zero ambient and a black sky; 42 % of the frame was below luminance 0.02 (the ground itself was lit).
- Five lamps in a row (lamp 0 unchanged, four more on the alley walls), each with its own warm colour and pool, overlapping.
- Soft shadows: analytic penumbra from a bulb of radius 0.3 m past vertical cylinders (posts, four bollards), in the ground shader. Not engine PCSS.
- Alley walls (lit by omni lights, warm windows, half of them on), a sodium sky haze, a warm wall bounce on the ground, a lit far field.
- Wet look: wide anisotropic lobe on cobble tops (lamp 0), stone mirror weight 0.5, extra lamps' glints weighted 0.15, extra bulbs not drawn in the mirror.

## Bars (tests/ch5b_test.gd, committed before any number)
| bar | result |
|---|---|
| S1 ground pixels < 0.02 under 15 % | 2.3 % of 81521 PASS |
| S1B whole frame < 0.02 under 15 % (added after run 1, see below) | 6.4 % PASS; control (legacy look) 42.3 % |
| S2 penumbra > 3 px at 4.5-5.5 m | 3.6 / 5.7 px, mean 4.7 px at 4.7 m PASS; control (radius 0) 0.6 px |
| S3 lamps >= 4 | 5 PASS |
| G pool falloff (photo 0.62 +-30 %) | 0.48 PASS |
| D streak aspect vs photo 2.32 +-30 % | FAIL 0.54 (it passed at 1.71 in one intermediate tune, by luck of a different glint mix; not kept) |
| F wet >= 3x dry | FAIL 2.2x (best 2.7x with a stronger lobe, which broke B) |
| ch5 A water, C, E | PASS |
| ch5 B mirror | FAIL: 3 puddle/pose pairs without the lamp point show a white peak (1.00, 0.88, 0.60). B passed in the parked scene. NOT FIXED. |

easypart 73 ok, peasy3 23 ok, freestart 14 ok (PASS*, exit stall only), run on an intermediate commit (wet_street is not used by them).

## Disclosed revisions
1. S1 ground-only control cannot fail (old ground was lit, 0.1 % dark; the void was the sky and far field), so S1B (whole frame) was added with the same 15 % bar.
2. edge_width() in the S2 reader had an off-by-one that returned -1 for a hard edge; fixed in the reader, the bar (3 px) unchanged.
3. Extra bulbs are hidden from the mirror camera (visual layer 2): their mirror images fell in the puddles and broke B. A physical shortcut.

## Looking at it
The alley reads as a night street now: five pools, soft bollard shadows, warm windows, no void. Against the photo it is still too clean and too bright on
the cobbles (silver, evenly glittering tops instead of one bright band with dark flanks), and the asphalt is a flat pale beige. The photo has a
single vertical glitter band from the lamp's base; ours glitters everywhere, which is why D (0.54) is wide and F saturates.

## Left
B regression (find the white source in puddle 0 / 1: not the extra bulbs, not the extra lamps' glints, not stone mirror weight; walls, sky haze or the
cobble wide lobe remain), D band (needs the glitter confined laterally: walls occluding the flank reflections), F (dry/wet ratio needs dimmer dry stones
or a narrower brighter lobe), asphalt too pale.

# Pass 2 (lead 11-04: "aluminium diamond-plate, not stone"; first red; a second red parks CH5b)

Done: irregular setts (rows 80-140 mm, stones 80-140 mm wide from hashes, per-stone dome height and random tilt up to ~16 deg, 14 mm mortar gaps 30 mm deep,
water level -34 mm), stone albedo 0.09 dry, wet = x0.7, wet roughness 0.15 (asphalt 0.25, see below), F0 0.03, the wide lobe removed (wide_gain 0),
asphalt albedo 0.07 dry / 0.05 wet, diffuse lamp light x0.4 (night exposure), end lamp 300, mirror weight on stones 0.15 and asphalt 0.05, engine
specular off on the omni and spot lights, glare sprites on the bulbs (additive billboards on layer 2, not mirrored). side by side:
out/ch5b/ch5b_side_by_side_pass2.png.

Bars (no bar changed): ch5b: S1 2.4 %, S1B 6.9 %, S2 3.6/5.7 px (control 0.6), S3 5 lamps, **D 2.58 vs 2.32 (+11 %) PASS** (first time), G FAIL 1.78 (needs 0.43-0.81),
F FAIL 0.9x. ch5: A, C, E pass; B FAIL on pose 2 (3 puddle/pose cases: the right-hand puddle lies on the asphalt strip, a flat wet surface whose smooth
specular makes a continuous lamp streak and a white peak 1.0 / 0.71 in the neighbouring puddle masks, and the lamp centroid is 22 px off); D passes.
B was 7 failures after pass 1; the engine specular and the glare were NOT the cause; the asphalt strip is the remaining suspect (raising its roughness to 0.25
did not fix it).

Why F and G fail: the F stones are sampled at stone centres, where the dome normal is the stone's own tilt, so only the few stones tilted toward the camera glint;
the mean is dominated by the diffuse term, which is equal wet and dry (wet x0.7 albedo, the same lamps), so the ratio stays ~1. G's near band holds only 11 non-water samples
(the rest are puddle), dominated by rims. A dimmer diffuse (dry stone nearer black) would raise F but not by 3x without the wide lobe the lead asked removed.

Looking at it: the setts now read as irregular stones with dark mortar, sparse glints and a lamp reflection band; much less diamond-plate. Still wrong against the
photo: the asphalt strip is a flat pale grey (an unexplained veil: dry mode shows it too, so it is lit diffuse light, not the mirror), the glare sprites show a
hard edge (gradient setup), and the cobbles are brighter and greyer than near-black wet granite.
