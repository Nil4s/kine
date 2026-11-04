# Gears: what the tool does and does not do (C52, complaints #336 and #343)

Parts > Moving parts > Gears > Gear pair. One template, a Mode slider: Gear pair or Rack and pinion.

## Does
- Straight spur teeth with flat sides, sized to mesh. Teeth 8 to 30, Teeth size (module) 1 to 3, Thickness 3 to 30 mm.
- Gear pair: a small and a big gear (Ratio 1 to 3), centre distance = module x (small + big teeth) / 2, the pitch circles touch. Output is unchanged from before Mode existed.
- Rack and pinion: the pinion (Small teeth, Teeth size) sits on a rack of the typed Rack length (40 to 300 mm, rounded to whole teeth).
  - Rack pitch = pi x module = the pinion's circular pitch (measured on the built solids, within 0.5 %).
  - Pinion centre to the rack's pitch line = module x teeth / 2 (the pitch radius).
  - On the pitch line the two teeth leave a gap of 0.10 x module (stated backlash); the rack tooth is straight-sided below the pitch line and 30 deg above it.
  - Rolled over two pitches the outlines overlap by at most 0.1 mm2 at the default size (0.014 measured).
- Two solids, a centre hole in each gear, a mounting hole in the rack body.

## Does not
- No involute profile: the flanks are straight, so very small pinions (8 teeth at module 3) can still touch a neighbouring tooth by about 0.15 mm2 while rolling.
- No helical, bevel, worm or internal gears; no pressure-angle or backlash setting; no strength, load or wear check.
- Mode 1 ignores Ratio. The Turn it panel only drives the Gear pair.
