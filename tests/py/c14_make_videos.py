"""C14 test helper: writes four small clips into the folder given: good, dark, small, shaky (cv2.VideoWriter, files only)."""
import sys, math
import numpy as np, cv2

out = sys.argv[1]
W, H, N = 640, 480, 120
rng = np.random.RandomState(3)
bg = (100 + rng.randint(-20, 21, (H, W))).astype(np.float32)


def frame(i, person_h, shift=(0, 0), gain=1.0):
    f = bg.copy()
    cx = int(W / 2 + 40 * math.sin(i / 6.0))
    top = int(H * (1 - person_h) / 2)
    hh = int(H * person_h)
    f[top:top + hh, cx - 40:cx + 40] = 220
    f = np.roll(f, shift, axis=(0, 1))
    f = np.clip(f * gain, 0, 255).astype(np.uint8)
    return cv2.cvtColor(f, cv2.COLOR_GRAY2BGR)


def write(name, person_h, gain=1.0, shake=0):
    vw = cv2.VideoWriter("%s/%s.avi" % (out, name), cv2.VideoWriter_fourcc(*"MJPG"), 30, (W, H))
    r = np.random.RandomState(9)
    for i in range(N):
        sh = (int(r.randint(-shake, shake + 1)), int(r.randint(-shake, shake + 1))) if shake else (0, 0)
        vw.write(frame(i, person_h, sh, gain))
    vw.release()


write("good", 0.8)
write("dark", 0.8, gain=0.3)
write("small", 0.15)
write("shaky", 0.8, shake=7)
