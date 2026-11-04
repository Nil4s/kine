# CH4 reference: wood that obeys its grain (a dovetailed oak box)

Nick's challenge (11-03): a solid (3D) wood material, so a cut face shows the grain the tree put there, not a picture wrapped around the outside. Reference first, numbers below, then the build.

## Photos (Wikimedia Commons; copies for the side-by-side shots are in docs/ch4/)

| use | file | licence | copy |
|---|---|---|---|
| end grain, rings + rays, whole disc | https://commons.wikimedia.org/wiki/File:Quercus_robur_crosssection.jpg (Quercus robur, fresh cut) | Public domain | docs/ch4/ref_end_grain_quercus_robur.jpg |
| end grain at known scale (1200 dpi scan of a Quercus robur plank end, 113 rings 1585-1698, Oland, Sweden) | https://commons.wikimedia.org/wiki/File:QURO-anual_rings_1585-1698_%C3%96land,Sweden,smen1a-1200dpi.JPG | Public domain | docs/ch4/ref_end_grain_rings_1200dpi_crop.png (800 px crop = 16.9 mm) |
| flat-sawn face (cathedral arches, pores, tight knots), old oak floor | https://commons.wikimedia.org/wiki/File:Ephraim_Hawley_House_circa_1670_original_oak_flooring.JPG | CC BY-SA 3.0 | docs/ch4/ref_flat_sawn_oak_floor.jpg |
| quarter-sawn face (fine parallel lines, ray flecks), riven clapboards | https://commons.wikimedia.org/wiki/File:Close-up_of_original_quarter_sawn_riven_oak_clapboards_in_leanto_attic.JPG | Public domain | docs/ch4/ref_quarter_sawn_clapboards.jpg |

Honest limits: the floor and the clapboards are 18th-century and weathered (grey, dirty); their grain geometry is the reference, their colour is not. The Commons search found no clean studio photo of quarter-sawn ray fleck; the fleck in the clapboard shot is faint. Ray width and height for large rays are therefore from the standard wood-anatomy values (marked "text") not from a photo I measured.

## Measured numbers (script: C:/Temp/claude/ch4scripts/meas.py, meas2.py; the 1200 dpi scan is the only scaled photo, 1 px = 0.02117 mm)

| quantity | value | how |
|---|---|---|
| mean ring spacing | 2.0 mm (113 rings in the ~228 mm of the scan); in the clean part rings run 1.0 to 4.0 mm, p10 1.7, p90 about 4 mm in the auto-detected peaks (41 of 113 rings found: the peak picker was fooled by pores, so the 2.0 mm comes from the ring count, not the picker) | scan height 10784 px at 1200 dpi / 113 |
| ring profile | sharp ring boundary: a band of large pores (earlywood, ring-porous oak, about 0.5-0.7 mm wide, pores about 0.15-0.25 mm) then a dense darker latewood fading out slowly over the rest of the ring; latewood about 43 % of the ring | scan, visual + threshold at mid-grey of each ring |
| earlywood colour (scan, aged lighting) | RGB (162, 132, 103) | p90 brightness rows |
| latewood colour (scan) | RGB (125, 99, 77): 0.77 of the earlywood | p10 brightness rows |
| fresh end grain colour (disc photo) | light zone (205, 162, 124), p10 (193,149,109), p90 (219,176,140); heartwood zone (184, 142, 108) | mean of boxes on end_grain_quercus_robur |
| aged flat-sawn face colour | (162, 122, 97), p10 (139,100,74), p90 (184,145,123) | box on the floor photo |
| fine rays on the end face | thin lines about 0.15-0.25 mm wide, spaced about 3 mm apart tangentially (the auto count 0.42 mm wide / 1.45 mm apart was contaminated by dark pore blotches; I trust the visual 150 px / 3.2 mm) | scan, visual |
| large rays (text, not measured) | up to about 1 mm wide, tens of mm tall along the grain; on a quarter-sawn face they are the silver flecks | standard oak anatomy |
| flat-sawn cathedral | arches nest along the board, apex pointing along the grain; the stack of arches spans one board width, 60-200 mm long | floor photo |

## Dovetail proportions (the numbers the geometry is held to)

- Slope: 1:8 in hardwood (atan(1/8) = 7.125 deg), 1:6 in softwood (9.46 deg). The box is oak, so 1:8.
- Layout across a board 70 mm high: half-pin at each end, three tails, two full pins. Pin width on the outside 6 mm, tail width on the outside 14 mm, half-pin 8 mm: 2 x 8 + 3 x 14 + 2 x 6 = 70. A through dovetail has the tails wide at the board end and the pins narrow on the outside (the tail cannot pull out).
- Board thickness 12 mm, so the tail depth is 12 mm and each flank moves 12/8 = 1.5 mm sideways over the depth.
- A hand-cut fit leaves a hairline: the sockets are cut 0.05 mm bigger each side, so the joint gap is 0.05 mm, under the 0.1 mm bar.

## The box

Outer 160 x 100 x 70 mm, four 12 mm boards (front/back carry the tails, left/right carry the pins), a 168 x 108 x 10 mm lid with a 3 mm chamfer on its top edge. Grain: front/back/lid run along X (flat-sawn, pith 45-90 mm below the face, trunk taper tilt about 2 deg gives the cathedrals), sides run along Z.
