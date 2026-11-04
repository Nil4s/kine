# CH5 reference: wet pavement at night

STATUS OF THE SOURCES: the worker brief for this wave says "Nothing online", so NO photo was downloaded or viewed. The numbers
below are from the literature and from street practice, written from memory and NOT re-fetched. They are cited so a reader can
check them. The side-by-side with a real photo is still OWED (see CH5_FEEDBACK.md). Candidate photos for later (Wikimedia Commons,
search "wet cobblestones night street lamp"; record URL and licence per file when fetched).

| Quantity | Value used | Source |
|---|---|---|
| Granite sett (cobble) size | 100-120 mm square top; pitch 110 mm | EN 1342 natural stone setts, common 100/100 and 120/120 |
| Joint width | 8-15 mm; 12 mm, joint bottom 12 mm below the tops | paving practice (sand or mortar joints) |
| Per-stone top height variation | sigma 4 mm, tilt up to 6 mm across a stone | worn historic paving, typical 3-6 mm |
| Settled low spots | bowls 40-50 mm deep, radius 0.5-0.7 m | local settlement; puddle depth 5-30 mm after rain |
| Puddle coverage | about 5-15 % of a worn street after rain | highway drainage literature (ponding in ruts) |
| Dry granite albedo | 0.30 | Akbari et al. 1992, urban materials (stone 0.2-0.4) |
| Dry aged asphalt albedo | 0.10 | Akbari et al.; new 0.05, aged 0.10-0.15 |
| Wet / dry albedo ratio | 0.55 (range 0.5-0.7) | Lekner and Dorf 1988, "Why some things are darker when wet", Appl. Opt. 27:1278 |
| Dry roughness | cobble 0.85, asphalt 0.92 | renderer convention for dry rough stone |
| Wet roughness | cobble 0.35, asphalt 0.30; water 0.04 | a water film fills micro-relief (Jensen et al. 2001, "Rendering of wet materials") |
| Water Fresnel | F0 = 0.02 (n = 1.33), Schlick | physics |
| Reflection streak elongation | vertical : horizontal = 1 / sin(grazing angle) | derivation below |

## Streak elongation (the number bar D uses)
A point source seen in a surface with isotropic slope noise. A normal tilt d in the plane of incidence moves the reflected ray's
elevation by 2d, so vertically on screen by f * 2d. A tilt d' across the plane rotates the reflected azimuth by about
2 d' sin(alpha), alpha being the angle between the view ray and the surface, so horizontally by f * 2 d' sin(alpha) for a narrow
streak. Ratio vertical : horizontal = 1 / sin(alpha).
For our camera (eye 1.6 m, bulb 6 m high, 12.6 m away on the ground) alpha is about 29 degrees, so the reference aspect is about 2.1.
Real photos of long lamp streaks on wet asphalt show larger ratios (rain ripples, ruts); this reference is the smooth slope-noise
floor, and is stated as such. The shader blurs the mirror image with exactly this ellipse, so bar D checks that the rendered
pipeline (mirror, projection, blur, tonemap) delivers it, not that the number was independently discovered.

# MEASURED FROM PHOTOS (added 11-04, lead fix pass; this lane may fetch Wikimedia Commons for measurement only)
Downloaded to C:/Users/Nick/tools/kine_workers/out/ch5/ref/ (not committed). Script: C:/Users/Nick/tools/kine_workers/ch5_measure.py (fetch: ch5_fetch.py).

| id | Photo | Licence | What it is |
|---|---|---|---|
| ref2 | File:Project 366 ^327, 221116 On Cobbled Lanes (Explored) - Flickr - comedy nose.jpg, https://commons.wikimedia.org/wiki/File:Project_366_%5E327,_221116_On_Cobbled_Lanes_(Explored)_-_Flickr_-_comedy_nose.jpg | CC BY 2.0 | one lamp at the end of a wet cobbled lane: THE reference for streak and pool |
| ref3 | File:Church of St. Charles Borromeo in Warsaw at night 2024.jpg, https://commons.wikimedia.org/wiki/File:Church_of_St._Charles_Borromeo_in_Warsaw_at_night_2024.jpg (Oleslawlama) | CC BY-SA 4.0 | wet setts + tram rails, lamp at the side of the frame: qualitative (glitter on stone tops, dark joints), no isolated streak |
| ref5 | File:A Magia da Noite.jpg, https://commons.wikimedia.org/wiki/File:A_Magia_da_Noite.jpg | CC BY-SA 4.0 | a CALM flooded square: lamp images are discs, aspect about 1 (the mirror regime) |
| ref0 | File:Funfair Lights On Wet Cobblestones (132570555).jpeg, https://commons.wikimedia.org/wiki/File:Funfair_Lights_On_Wet_Cobblestones_(132570555).jpeg | CC BY-SA 3.0 | many coloured lights, vertical streaks across every stone top; not usable for a single-lamp number |

What the photos show (looked at, not assumed): in ref2 and ref3 the wet stone TOPS glitter and the joints are nearly black; ref2 has a bright
vertical band of glitter running from the lamp's base straight down to the viewer, brighter than the flanks, fading out toward the camera;
the sky and the walls are dark. In ref5 (still water) reflections are sharp discs.

Measured numbers (estimator: luminance of the sRGB values, 3 px blur, region >= 0.5 x the 99.5th percentile of the ground ROI, the
connected component holding most light, aspect = sqrt(var y / var x)):
- Streak aspect, ref2, ground below the lamp's base, x 380..1000: **2.32** (2.28 to 2.33 for thresholds 0.5; 1.8 to 2.6 at 0.35). It is a lower bound: the streak runs off the bottom of the frame.
- Streak aspect, ref5 (still puddle) lamp disc: 0.86 (about 1).
- Streak aspect, ref3: component 0.99, not a streak measurement (reported, not used).
- Light pool, ref2 (horizon row 940 from the lane edges, lamp base row 1045, central 40 % of the lane, distance from the camera d/D = 105/(y-940)):
  mean luminance at 0.20-0.30 of the lamp distance from the lamp 0.35 (only 18 rows), 0.45-0.55: **0.651**, 0.75-0.85: **0.403**, beyond 0.85 it falls to
  0.08 at 0.88 and 0.02 at 0.89 (the lamp's cone and the dark foreground). **Pool ratio L(0.75-0.85)/L(0.45-0.55) = 0.62.**
  For comparison a Lambert inverse-square pool for a 5.6 m lamp, 12 m away, gives about 0.40; the photo is flatter because wet stone adds glint.
- Lamp height from the photo: (1045-655)/(1045-940) = 3.7 camera heights, about 5.6 m for a 1.5 m eye.
