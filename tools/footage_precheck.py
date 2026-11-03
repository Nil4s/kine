"""C14 (#560): look at the first seconds of a VIDEO FILE before it is tracked. Never opens a camera: cv2.VideoCapture gets a path only.
usage: python footage_precheck.py <video file> [seconds]      prints one JSON line:
  {"ok", "why", "fps", "frames", "brightness" (0..255 mean grey), "subject" (height of what moves, share of the frame 0..1),
   "shake" (camera jitter, percent of the frame width per frame)}"""
import json, os, sys


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else ""
    secs = float(sys.argv[2]) if len(sys.argv) > 2 else 3.0
    if not os.path.isfile(path):
        print(json.dumps({"ok": False, "why": "no such file"}))
        return
    try:
        import cv2
        import numpy as np
    except Exception as e:
        print(json.dumps({"ok": False, "why": "opencv is missing (%s)" % e}))
        return
    cap = cv2.VideoCapture(path)
    if not cap.isOpened():
        print(json.dumps({"ok": False, "why": "the video could not be opened"}))
        return
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    n = max(2, int(fps * secs))
    gray = []
    while len(gray) < n:
        ok, fr = cap.read()
        if not ok:
            break
        g = cv2.cvtColor(fr, cv2.COLOR_BGR2GRAY)
        h, w = g.shape
        s = 160.0 / max(w, 1)
        gray.append(cv2.resize(g, (160, max(1, int(h * s)))).astype(np.float32))
    cap.release()
    if len(gray) < 2:
        print(json.dumps({"ok": False, "why": "fewer than 2 frames could be read"}))
        return
    st = np.stack(gray)
    bright = float(st.mean())
    # camera shift per frame from the outer strips (the person is mostly in the middle): phase correlation
    H, W = st.shape[1], st.shape[2]
    strip = max(8, W // 5)
    win = cv2.createHanningWindow((strip, H), cv2.CV_32F)
    shifts = []
    for i in range(1, len(st)):
        sx = []
        for a in (slice(0, strip), slice(W - strip, W)):
            (dx, dy), _ = cv2.phaseCorrelate(np.ascontiguousarray(st[i - 1][:, a]), np.ascontiguousarray(st[i][:, a]), win)
            sx.append((dx, dy))
        shifts.append((np.mean([q[0] for q in sx]), np.mean([q[1] for q in sx])))
    sh = np.array(shifts)
    if len(sh) >= 5:
        k = 5
        pad = np.pad(sh, ((k // 2, k // 2), (0, 0)), mode="edge")
        smooth = np.stack([np.convolve(pad[:, c], np.ones(k) / k, mode="valid") for c in range(2)], 1)
        jit = np.abs(sh - smooth).mean(axis=0)
    else:
        jit = np.abs(sh - sh.mean(axis=0)).mean(axis=0)
    shake = float(np.hypot(jit[0], jit[1]) / W * 100.0)
    # subject: the rows that differ from the median background
    bg = np.median(st, axis=0)
    diff = np.abs(st - bg).max(axis=0)
    rows = np.where((diff > 25.0).sum(axis=1) > 2)[0]
    subject = float((rows.max() - rows.min() + 1) / H) if len(rows) else 0.0
    print(json.dumps({"ok": True, "why": "", "fps": float(fps), "frames": len(st), "brightness": round(bright, 2), "subject": round(subject, 3), "shake": round(shake, 3)}))


main()
