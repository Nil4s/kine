"""CH5c: scene numbers estimated from ref2.jpg (Wikimedia CC BY 2.0, 1280x1922 copy of a 1994x2994 original) and printed.
Fix pass 2 (replaces the first estimate, which fixed the camera height at 1.1 m to fit the test poses and read a 20 px sett row at row 1400).
Sources:
- focal length: Wikimedia EXIF (Make Nokia, Model Lumia 920). Lumia 920: 26 mm-equivalent lens on a 1/3" multi-aspect sensor with 1.4 um
  pixels; the equal-diagonal 4:3 / 16:9 frame is 5.71 mm -> f = 26 / (43.27 / 5.71) = 3.43 mm = 2450 px native (3.7 mm is also quoted: 2643 px).
  The original is 1994 px wide ~ the 2000 px short side of the 16:9 mode, i.e. a crop, not a rescale -> f = 2450..2643 x 1280/1994 = 1573..1697 px.
- camera height: brick courses on the left wall (hand-read vertical autocorrelation peaks): 15 px at x 440, 8 px at x 560; the wall base on
  the lane edge line (590,1055)-(330,1260) at those columns: rows 1173, 1079. h = (y_base - y_horizon) * course / course_px. Course 79 mm
  (Victorian imperial brick, 4 courses ~ 12.5 in; GPS 53.4166 N 2.9497 W is a Liverpool terrace entry), 75-86 mm range.
- hand-picked points: lamp post base (660,1055), lamp head (645,650), right lane edge (770,1055)-(1130,1420), fence top at x 1000 row 735,
  plinth top at x 1000 row ~1145, tarmac patch px 430-610 rows 1235-1290, cyan light (790,875), gate row 1050,
  sett joints counted in x 480-700: 16 rows between rows 1495 and 1910, sett lengths 67-115 px at rows 1600-1850."""
import math

W, H = 1280, 1922
F = 1630.0                      # px (mid of 1573..1697)
YH, XV = 975.0, 691.0           # horizon row and the lane's vanishing column (from the two lane edges)
course = 0.079
hs = [(1173 - YH) * course / 15.0, (1079 - YH) * course / 8.0]
h = sum(hs) / 2
print("f %.0f px (1573..1697); vertical FOV of the photo %.1f deg; pitch up %.2f deg" % (F, 2 * math.degrees(math.atan(H / 2 / F)), math.degrees(math.atan((YH - H / 2) / F))))
print("camera height from bricks: %.3f / %.3f m -> %.2f m (75 mm courses: %.2f, 86 mm: %.2f)" % (hs[0], hs[1], h, h * 75 / 79, h * 86 / 79))
gz = lambda y: F * h / (y - YH)                       # ground distance of a row
gx = lambda x, y: (x - XV) * h / (y - YH)             # lateral offset of a ground point
print("left wall x %.2f / %.2f m (x 440 at row 1173, x 560 at row 1079)" % (gx(440, 1173), gx(560, 1079)))
print("right lane edge (plinth face) x %.2f m (1130, 1420)" % gx(1130, 1420))
zb = gz(1055)
print("lamp: base %.1f m away; head height %.2f m; head x %.2f m, post x %.2f m" % (zb, h + (YH - 650) / (1055 - YH) * h, (645 - XV) * zb / F, (660 - XV) * zb / F))
zf = gz(1288)                                         # the right lane edge passes row 1288 at x 1000
print("fence at x 1000: base row 1288 (%.1f m): top %.2f m, plinth top %.2f m" % (zf, (1288 - 735) * zf / F, (1288 - 1145) * zf / F))
print("tarmac patch: x %.2f..%.2f m, distance %.2f..%.2f m" % (gx(430, 1262), gx(610, 1262), gz(1290), gz(1235)))
print("gate: %.1f m; cyan light x %.2f m, height %.2f m" % (gz(1050), (790 - XV) * gz(1050) / F, h + (YH - 875) * gz(1050) / F))
pitch = (gz(1495) - gz(1910)) / 16
print("sett rows: %.3f m pitch along the lane; lengths across: %.3f, %.3f, %.3f m" % (pitch, 67 * h / (1600 - YH), 110 * h / (1700 - YH), 115 * h / (1850 - YH)))
fr = 720 / H * F
print("render: 1280x720 with the photo's camera: f %.0f px -> vertical FOV %.1f deg; the photo frame is the central %.0f x 720 px" % (fr, 2 * math.degrees(math.atan(360 / fr)), W * 720 / H))
