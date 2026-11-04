"""CH5c: scene numbers estimated from ref2.jpg (Wikimedia CC BY 2.0, 1280x1922) and printed. Hand-picked image points are stated here.
Vanishing point: left lane edge (590,1055)->(330,1260), right lane edge (770,1055)->(1130,1420); they meet at the VP.
Camera: principal point (640,961); horizon row = VP row. Ground metric from the sett rows: row pitch p = 0.10 m (sett 100 x 200 mm), measured 20 px
at image row 1400. With a level camera of height h, row pitch px = p (y-yh)^2 / (f h)  ->  f h.  h is chosen so the lane edges 2.25 h apart fit the test poses (+-1.2 m)."""
import numpy as np, math
from PIL import Image
im = np.asarray(Image.open('C:/Users/Nick/tools/kine_workers/out/ch5/ref/ref2.jpg').convert('RGB')).astype(float)
def line(p, q):
    a = (q[1] - p[1]); b = (p[0] - q[0]); return a, b, a * p[0] + b * p[1]
l1 = line((590, 1055), (330, 1260)); l2 = line((770, 1055), (1130, 1420))
A = np.array([[l1[0], l1[1]], [l2[0], l2[1]]]); vp = np.linalg.solve(A, [l1[2], l2[2]])
print("vanishing point px (%.0f, %.0f); horizon row %.0f; pitch of the camera above level %.2f deg (f below)" % (vp[0], vp[1], vp[1], 0.0))
yh = vp[1]; y = 1400.0; rowpx = 20.0; p = 0.10
fh = p * (y - yh) ** 2 / rowpx
for h in (0.85, 1.1, 1.5):
    f = fh / h
    print("camera height %.2f m -> f %.0f px, horizontal FOV %.1f deg, lane width %.2f m (edges %.0f px apart at row 1420, 2.25 h)" % (h, f, 2 * math.degrees(math.atan(640 / f)), 2.25 * h, 1003))
h = 1.1; f = fh / h
print("CHOSEN camera height %.2f m, f %.0f px, horizontal FOV %.1f deg = vertical %.1f deg at 16:9" % (h, f, 2 * math.degrees(math.atan(640 / f)), 2 * math.degrees(math.atan(math.tan(math.atan(640 / f)) * 720 / 1280))))
print("pitch up %.2f deg" % math.degrees(math.atan((yh - 961) / f) * -1))
lb = 1055.0; Z = f * h / (lb - yh)
lamp_top = 635.0
print("lamp base row 1055 -> %.1f m away; lamp row %.0f -> height %.1f m" % (Z, lamp_top, h + (yh - lamp_top) / (lb - yh) * h))
halo = im[600:700, 600:700].reshape(-1, 3); r = np.hypot(*np.meshgrid(np.arange(100) - 40, np.arange(100) - 30)).ravel()
ring = halo[(r > 22) & (r < 40)]; m = ring.mean(0)
print("lamp halo ring rgb %s  b/r %.2f" % (m.round(0), m[2] / m[0]))
print("sky rgb", im[100:300, 700:1100].reshape(-1, 3).mean(0).round(0), " left wall rgb", im[500:900, 100:300].reshape(-1, 3).mean(0).round(0), " fence rgb", im[900:1000, 900:1100].reshape(-1, 3).mean(0).round(0))
