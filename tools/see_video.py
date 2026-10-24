"""VIDEO -> pose.json for Poser's "Animation from video..." (round 45, GATES AA2). Nick 10-18: "all good to use the model
for the pose". MediaPipe PoseLandmarker (a pretrained pose model) finds the person in every frame; this writes the same
pose.json as the game repo's tools/see/pose.py (33 world landmarks per frame: metres, the hips at 0, y down; and the image
points with their visibility), plus the picture's size. Poser's scripts/video_import.gd reads it; no model is in the app.
HANDS (ROADMAP 90): MediaPipe HandLandmarker (21 points per hand; the hand's world landmarks in metres) runs on the same
frames. Each hand is matched to the body's wrist it sits on: the nearest of the pose's wrists 15 (the person's left) and
16 (right) in the picture, within --hand-reach picture widths; each wrist takes at most one hand, nearest pair first.
MediaPipe's handedness label is NOT used. A matched frame gets "hands": {"l": {"world", "image"}, "r": {...}}; a frame
with no hand, or a clip with no hand model, has no "hands" key, so the body import is exactly as before.
    python -I tools/see_video.py <video> <out pose.json> [--fps 30] [--pick 0.5,0.6] [--people 2]
         [--model D:/pose_models/pose_landmarker_heavy.task] [--hand-model D:/hand_models_handcap/hand_landmarker.task]
         [--no-hands] [--hand-reach 0.12]
The hand model is MediaPipe's official release, downloaded (ROADMAP 90) into the new folder D:/hand_models_handcap/:
    https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task
    sha256 fbc2a30080c3c557093b5ddfc334698132eb341044ccee322ccf8bcf3607cde1 (7,819,105 bytes, fetched 2026-10-19)
With --people N it finds up to N bodies and follows ONE: the nearest --pick (x, y 0-1 of the picture) in the first frame
it finds anyone, then the one whose hips are nearest the last frame's.
Prints one line: "POSE <frames> frames, <lost> without a body, <hands> with a hand -> <out>", or "NO <why>" and exits 1."""
import argparse
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor


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
    ap.add_argument("--hand-reach", type=float, default=0.12,
                    help="a hand's wrist within this many picture widths of a body wrist is that hand")
    a = ap.parse_args()
    try:
        import cv2
        import mediapipe as mp
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
    det = vision.PoseLandmarker.create_from_options(vision.PoseLandmarkerOptions(
        base_options=mpt.BaseOptions(model_asset_path=a.model), running_mode=vision.RunningMode.VIDEO,
        num_poses=a.people))
    hdet = None
    if not a.no_hands:
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
    with_hand = 0
    i = 0
    step = max(1, int(round(src_fps / a.fps)))
    while True:
        ok, img = cap.read()
        if not ok:
            break
        if i % step:
            i += 1
            continue
        t = i / src_fps
        i += 1
        mpimg = mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
        # SPEED: the hand model runs on its own thread while the pose model runs here. Each detector still sees every frame in
        # the same order with the same timestamp, so its output is the same; only the wall clock overlaps (hand ~1/4 of pose)
        hfut = pool.submit(hdet.detect_for_video, mpimg, int(t * 1000)) if hdet is not None else None
        res = det.detect_for_video(mpimg, int(t * 1000))
        hres = hfut.result() if hfut is not None else None
        if not res.pose_world_landmarks:
            lost += 1
            continue
        want = (px, py) if last is None else last
        hips = [((p[23].x + p[24].x) / 2, (p[23].y + p[24].y) / 2) for p in res.pose_landmarks]
        k = min(range(len(hips)), key=lambda n: (hips[n][0] - want[0]) ** 2 + (hips[n][1] - want[1]) ** 2)
        last = hips[k]
        fr = {"t": round(t, 3),
              "world": [[round(q.x, 4), round(q.y, 4), round(q.z, 4)] for q in res.pose_world_landmarks[k]],
              "image": [[round(q.x, 4), round(q.y, 4), round(q.visibility, 3)] for q in res.pose_landmarks[k]]}
        hands = match_hands(res.pose_landmarks[k], hres, a.hand_reach) if hres is not None else {}
        if hands:
            fr["hands"] = hands
            with_hand += 1
        frames.append(fr)
    if len(frames) < 2:
        print("NO the tracker found a person in %d frames" % len(frames))
        sys.exit(1)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    json.dump({"fps": a.fps, "video": os.path.basename(a.video), "size": [W, H], "frames": frames,
               "note": "MediaPipe world landmarks (m, hips at 0, y down), 33 per frame; image = (x, y, visibility) 0-1; "
                       "hands (optional per frame): MediaPipe hand world landmarks (m) and image (x, y) 0-1, 21 each; "
                       "l = the person's left"},
              open(a.out, "w"))
    print("POSE %d frames, %d without a body, %d with a hand -> %s" % (len(frames), lost, with_hand, a.out))


if __name__ == "__main__":
    main()
