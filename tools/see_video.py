"""VIDEO -> pose.json for Poser's "Animation from video..." (round 45, GATES AA2). Nick 10-18: "all good to use the model
for the pose". MediaPipe PoseLandmarker (a pretrained pose model) finds the person in every frame; this writes the same
pose.json as the game repo's tools/see/pose.py (33 world landmarks per frame: metres, the hips at 0, y down; and the image
points with their visibility), plus the picture's size. Poser's scripts/video_import.gd reads it; no model is in the app.
HANDS (ROADMAP 90): MediaPipe HandLandmarker (21 points per hand; the hand's world landmarks in metres) runs on the same
frames. Each hand is matched to the body's wrist it sits on: the nearest of the pose's wrists 15 (the person's left) and
16 (right) in the picture, within --hand-reach picture widths; each wrist takes at most one hand, nearest pair first.
MediaPipe's handedness label is NOT used. A matched frame gets "hands": {"l": {"world", "image"}, "r": {...}}; a frame
with no hand, or a clip with no hand model, has no "hands" key, so the body import is exactly as before.
CROP (two passes, when the person is small in the picture): pass 1 tracks every 4th frame to find the person's box over
the clip. When the median box is under 60% of the picture height, pass 2 tracks EVERY frame on a square crop around the
person (the box's longer side + 25%, smoothed over time, clamped to the picture, upscaled to >= 512 px). The body and hand
image points are mapped back to the whole picture (x, y 0-1 of the original picture, the same convention as a full-frame
run); world landmarks need no mapping. --no-crop turns the second pass off. A person at 60% or more of the picture height
is tracked exactly as before (one pass, the same output).
    python tools/see_video.py <video> <out pose.json> [--fps 30] [--pick 0.5,0.6] [--people 2]
         [--model D:/pose_models/pose_landmarker_heavy.task] [--hand-model D:/hand_models_handcap/hand_landmarker.task]
         [--no-hands] [--hand-reach 0.12] [--no-crop]
The hand model is MediaPipe's official release, downloaded (ROADMAP 90) into the new folder D:/hand_models_handcap/:
    https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task
    sha256 fbc2a30080c3c557093b5ddfc334698132eb341044ccee322ccf8bcf3607cde1 (7,819,105 bytes, fetched 2026-10-19)
With --people N it finds up to N bodies and follows ONE: the nearest --pick (x, y 0-1 of the picture) in the first frame
it finds anyone, then the one whose hips are nearest the last frame's. In the crop pass the followed person is the one
nearest the crop's centre.
Prints one line: "POSE <frames> frames, <lost> without a body, <hands> with a hand -> <out>", or "NO <why>" and exits 1.
A crop run also says "crop: ..." on stderr."""
import argparse
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor
from types import SimpleNamespace

CROP_BELOW = 0.60     # crop only when the person's median box is under this share of the picture height
CROP_PAD = 1.25       # the square crop's side = the box's longer side x this (about 25% padding)
CROP_MIN_PX = 512     # the crop is upscaled to at least this many pixels a side
CROP_MIN_SIDE = 64    # a box smaller than this (picture pixels) is widened to it
PASS1_EVERY = 4       # pass 1 tracks every 4th sampled frame
LOCATE_CONF = 0.2     # pass 1 finds the person at this detection confidence (a 30% person misses at MediaPipe's 0.5)


def match_hands(body, hres, reach):
    """the hands of one frame, each on the body wrist it sits on. body = the pose's 33 image landmarks (x, y, visibility),
    hres = HandLandmarker's result. A hand takes the nearest body wrist (15 = l, 16 = r) if it is within reach of it, and
    each wrist takes at most one hand (nearest pair first). Returns {"l": {...}} / {"r": {...}} or {}"""
    if not hres or not hres.hand_landmarks:
        return {}
    wrists = {"l": body[15], "r": body[16]}
    pairs = []
    for h, lm in enumerate(hres.hand_landmarks):
        w = lm[0]
        for side, bw in wrists.items():
            d = ((w.x - bw.x) ** 2 + (w.y - bw.y) ** 2) ** 0.5
            if d <= reach:
                pairs.append((d, h, side))
    out = {}
    used = set()
    for d, h, side in sorted(pairs):
        if h in used or side in out:
            continue
        used.add(h)
        lm = hres.hand_landmarks[h]
        wl = hres.hand_world_landmarks[h]
        out[side] = {"world": [[round(q.x, 4), round(q.y, 4), round(q.z, 4)] for q in wl],
                     "image": [[round(q.x, 4), round(q.y, 4)] for q in lm]}
    return out


def box_of(image, eps=0.5):
    """the person's box in picture fractions from the points with visibility >= eps: (x0, y0, x1, y1), or None"""
    pts = [(min(max(q[0], 0.0), 1.0), min(max(q[1], 0.0), 1.0)) for q in image if q[2] >= eps]
    if len(pts) < 5:
        return None
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def crop_plan(boxes, W, H, np):
    """boxes: [(sampled index, cx, cy, side)] in picture pixels from pass 1. Returns crop(s) -> (x0, y0, side, T): the
    square window of sampled frame s in picture pixels and the size T it is run at. The centre and side are interpolated
    between the pass-1 boxes and smoothed with a 3-box moving average, so the window does not jump."""
    ss = np.array([b[0] for b in boxes], float)
    cx = np.array([b[1] for b in boxes], float)
    cy = np.array([b[2] for b in boxes], float)
    sd = np.array([b[3] for b in boxes], float)

    def smooth(v):
        if len(v) < 3:
            return v
        p = np.concatenate([[v[0]], v, [v[-1]]])
        return (p[:-2] + p[1:-1] + p[2:]) / 3.0

    cx, cy, sd = smooth(cx), smooth(cy), smooth(sd)
    top = min(W, H)

    def crop(s):
        x = float(np.interp(s, ss, cx))
        y = float(np.interp(s, ss, cy))
        side = min(max(float(np.interp(s, ss, sd)), CROP_MIN_SIDE), top)
        si = int(round(side))
        x0 = int(round(min(max(x - si / 2.0, 0), W - si)))
        y0 = int(round(min(max(y - si / 2.0, 0), H - si)))
        return x0, y0, si, max(CROP_MIN_PX, si)

    return crop


def run_track(a, env, step, every=1, crop=None, hands=True, progress="", pbase=(0.0, 1.0), conf=0.5):
    """one tracking pass over the clip. every: track every Nth sampled frame (pass 1 uses PASS1_EVERY). crop: None (the
    whole picture) or crop_plan's crop(s): the pose and hand models see the square crop and the points are mapped back to
    the whole picture. Returns (frames, lost, seen, with_hand, W, H), frames = [(sampled index, frame dict)]."""
    cv2, mp, mpt, vision = env
    cap = cv2.VideoCapture(a.video)
    src_fps = cap.get(cv2.CAP_PROP_FPS) or a.fps
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
    W = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    H = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    det = vision.PoseLandmarker.create_from_options(vision.PoseLandmarkerOptions(
        base_options=mpt.BaseOptions(model_asset_path=a.model), running_mode=vision.RunningMode.VIDEO,
        num_poses=a.people, min_pose_detection_confidence=conf, min_pose_presence_confidence=conf,
        min_tracking_confidence=conf))
    hdet = None
    if hands and not a.no_hands:
        if os.path.exists(a.hand_model):
            hdet = vision.HandLandmarker.create_from_options(vision.HandLandmarkerOptions(
                base_options=mpt.BaseOptions(model_asset_path=a.hand_model), running_mode=vision.RunningMode.VIDEO,
                num_hands=2))
        else:
            print("note: no hand model at %s, the body is tracked without hands" % a.hand_model)
    pool = ThreadPoolExecutor(max_workers=1)
    px, py = (float(v) for v in a.pick.split(","))
    last = None
    frames = []
    lost = 0
    seen = 0
    with_hand = 0
    i = 0
    while True:
        ok, img = cap.read()
        if not ok:
            break
        if i % step:
            i += 1
            continue
        s_idx = i // step
        t = i / src_fps
        i += 1
        if s_idx % every:
            continue
        seen += 1   # every sampled frame the tracker looked at, the ones with no body too (EasyTake's score needs the clip's count)
        if progress and total > 0 and i % 10 == 0:
            with open(progress, "w") as pf:
                pf.write("%.3f" % (pbase[0] + (pbase[1] - pbase[0]) * min(1.0, i / total)))
        if crop is None:
            src = img
            x0 = y0 = 0
            si = None
        else:
            x0, y0, si, T = crop(s_idx)
            src = cv2.resize(img[y0:y0 + si, x0:x0 + si], (T, T), interpolation=cv2.INTER_CUBIC)
        mpimg = mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(src, cv2.COLOR_BGR2RGB))
        # SPEED: the hand model runs on its own thread while the pose model runs here. Each detector still sees every frame in
        # the same order with the same timestamp, so its output is the same; only the wall clock overlaps (hand ~1/4 of pose)
        hfut = pool.submit(hdet.detect_for_video, mpimg, int(t * 1000)) if hdet is not None else None
        res = det.detect_for_video(mpimg, int(t * 1000))
        hres = hfut.result() if hfut is not None else None
        if not res.pose_world_landmarks:
            lost += 1
            continue
        if crop is None:
            want = (px, py) if last is None else last
            hips = [((p[23].x + p[24].x) / 2, (p[23].y + p[24].y) / 2) for p in res.pose_landmarks]
            k = min(range(len(hips)), key=lambda n: (hips[n][0] - want[0]) ** 2 + (hips[n][1] - want[1]) ** 2)
            last = hips[k]
            body = res.pose_landmarks[k]
            image = [[round(q.x, 4), round(q.y, 4), round(q.visibility, 3)] for q in body]
            pose_xy = body
        else:
            # the crop is centred on the person, so the followed one is the pose nearest the crop's middle
            hips = [((p[23].x + p[24].x) / 2, (p[23].y + p[24].y) / 2) for p in res.pose_landmarks]
            k = min(range(len(hips)), key=lambda n: (hips[n][0] - 0.5) ** 2 + (hips[n][1] - 0.5) ** 2)
            pose_xy = [_map_point(q, x0, y0, si, W, H) for q in res.pose_landmarks[k]]
            image = [[round(q.x, 4), round(q.y, 4), round(q.visibility, 3)] for q in pose_xy]
            if hres is not None:
                hres = _map_hands(hres, x0, y0, si, W, H)
        fr = {"t": round(t, 3),
              "world": [[round(q.x, 4), round(q.y, 4), round(q.z, 4)] for q in res.pose_world_landmarks[k]],
              "image": image}
        hands_out = match_hands(pose_xy, hres, a.hand_reach) if hres is not None else {}
        if hands_out:
            fr["hands"] = hands_out
            with_hand += 1
        frames.append((s_idx, fr))
    return frames, lost, seen, with_hand, W, H


def _map_point(q, x0, y0, si, W, H):
    """a crop's normalized point (x, y, visibility) -> the whole picture's normalized point, clamped to the picture"""
    x = min(max((x0 + q.x * si) / W, 0.0), 1.0)
    y = min(max((y0 + q.y * si) / H, 0.0), 1.0)
    return SimpleNamespace(x=x, y=y, z=q.z, visibility=q.visibility)


def _map_hands(hres, x0, y0, si, W, H):
    """HandLandmarker's result with its image points mapped from the crop to the whole picture (world points are metres
    and unchanged)"""
    hl = [[_map_point(q, x0, y0, si, W, H) for q in lm] for lm in hres.hand_landmarks]
    return SimpleNamespace(hand_landmarks=hl, hand_world_landmarks=hres.hand_world_landmarks)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("out")
    ap.add_argument("--fps", type=float, default=30.0)
    ap.add_argument("--pick", default="0.5,0.6")
    ap.add_argument("--people", type=int, default=2)
    ap.add_argument("--model", default="D:/pose_models/pose_landmarker_heavy.task")
    ap.add_argument("--hand-model", default="D:/hand_models_handcap/hand_landmarker.task")
    ap.add_argument("--no-hands", action="store_true")
    ap.add_argument("--detect-conf", type=float, default=0.5,
                    help="the pose model's detection, presence and tracking confidence (MediaPipe's default 0.5)")
    ap.add_argument("--no-crop", action="store_true",
                    help="track the whole picture only (no second pass on a crop round a small person)")
    ap.add_argument("--progress", default="",
                    help="a file rewritten as the tracker goes: the fraction of the video read (0-1), for the app's progress line")
    ap.add_argument("--hand-reach", type=float, default=0.12,
                    help="a hand's wrist within this many picture widths of a body wrist is that hand")
    a = ap.parse_args()
    try:
        import cv2
        import mediapipe as mp
        import numpy as np
        from mediapipe.tasks import python as mpt
        from mediapipe.tasks.python import vision
    except ImportError as e:
        print("NO the tracker needs opencv-python and mediapipe (pip install mediapipe opencv-python): %s" % e)
        sys.exit(1)
    if not os.path.exists(a.video):
        print("NO no video at %s" % a.video)
        sys.exit(1)
    if not os.path.exists(a.model):
        print("NO no pose model at %s (MediaPipe pose_landmarker_heavy.task)" % a.model)
        sys.exit(1)
    cap = cv2.VideoCapture(a.video)
    src_fps = cap.get(cv2.CAP_PROP_FPS) or a.fps
    W = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    H = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    cap.release()
    step = max(1, int(round(src_fps / a.fps)))
    env = (cv2, mp, mpt, vision)
    crop = None
    pbase = (0.0, 1.0)
    if not a.no_crop:
        # pass 1: the person's box over the clip, every 4th frame, body only
        p1, _, _, _, _, _ = run_track(a, env, step, every=PASS1_EVERY, crop=None, hands=False,
                                      progress=a.progress, pbase=(0.0, 0.25), conf=LOCATE_CONF)
        boxes = []
        shares = []
        for s, fr in p1:
            b = box_of(fr["image"])
            if b is None:
                continue
            x0, y0, x1, y1 = b
            shares.append(y1 - y0)
            cxp = (x0 + x1) / 2.0 * W
            cyp = (y0 + y1) / 2.0 * H
            side = CROP_PAD * max((x1 - x0) * W, (y1 - y0) * H)
            boxes.append((s, cxp, cyp, side))
        if len(boxes) >= 2:
            share = sorted(shares)[len(shares) // 2]
            if share < CROP_BELOW:
                import numpy as np
                crop = crop_plan(boxes, W, H, np)
                pbase = (0.25, 1.0)
                print("crop: the person is %.0f%% of the picture height (median of %d boxes): tracked on a crop, every frame"
                      % (share * 100, len(boxes)), file=sys.stderr)
            else:
                print("crop: the person is %.0f%% of the picture height: tracked whole, no crop" % (share * 100),
                      file=sys.stderr)
    frames_s, lost, seen, with_hand, W, H = run_track(a, env, step, every=1, crop=crop, hands=True,
                                                      progress=a.progress, pbase=pbase, conf=a.detect_conf)
    frames = [fr for _, fr in frames_s]
    if len(frames) < 2:
        print("NO the tracker found a person in %d frames" % len(frames))
        sys.exit(1)
    out_fps = src_fps / step
    # the rate the KEPT frames really come at: a 16 fps clip sampled "at 30" keeps every frame, so 16, not 30 (the importer
    # reads this field for its filters and gap fill; each frame's own t is src frame index / src_fps either way)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    json.dump({"fps": round(out_fps, 4), "video": os.path.basename(a.video), "size": [W, H], "frames": frames, "seen": seen,
               "note": "MediaPipe world landmarks (m, hips at 0, y down), 33 per frame; image = (x, y, visibility) 0-1; "
                       "hands (optional per frame): MediaPipe hand world landmarks (m) and image (x, y) 0-1, 21 each; "
                       "l = the person's left"},
              open(a.out, "w"))
    print("POSE %d frames, %d without a body, %d with a hand -> %s" % (len(frames), lost, with_hand, a.out))


if __name__ == "__main__":
    main()
