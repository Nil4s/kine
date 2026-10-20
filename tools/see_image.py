"""ONE PICTURE -> landmarks, for Kine's "View: match the body to the reference" (ROADMAP C25). The same MediaPipe
PoseLandmarker as tools/see_video.py (same default model), run in IMAGE mode on a single PNG / JPG, so a still needs no
two-frame video. Run it as a separate process with python -I (nothing from the picture's folder is imported):
    python -I tools/see_image.py <image> <out.json> [--model D:/pose_models/pose_landmarker_heavy.task] [--pick 0.5,0.6]
Writes {"size": [W, H], "image": [[x, y, visibility] x 33]} (x, y 0-1 of the picture, MediaPipe's numbering) for the person
nearest --pick (their hips), and prints "POSE 1 person -> out", or "NO <why>" and exits 1."""
import argparse
import json
import os
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("out")
    ap.add_argument("--model", default="D:/pose_models/pose_landmarker_heavy.task")
    ap.add_argument("--pick", default="0.5,0.6")
    ap.add_argument("--people", type=int, default=4)
    a = ap.parse_args()
    try:
        import cv2
        import numpy as np
        import mediapipe as mp
        from mediapipe.tasks import python as mpt
        from mediapipe.tasks.python import vision
    except ImportError as e:
        print("NO the detector needs opencv-python and mediapipe (pip install mediapipe opencv-python): %s" % e)
        sys.exit(1)
    if not os.path.exists(a.image):
        print("NO no picture at %s" % a.image)
        sys.exit(1)
    if not os.path.exists(a.model):
        print("NO no pose model at %s (MediaPipe pose_landmarker_heavy.task)" % a.model)
        sys.exit(1)
    img = cv2.imdecode(np.fromfile(a.image, dtype=np.uint8), cv2.IMREAD_COLOR)   # fromfile: a path with accents works
    if img is None:
        print("NO cannot read %s as a picture" % a.image)
        sys.exit(1)
    H, W = img.shape[:2]
    det = vision.PoseLandmarker.create_from_options(vision.PoseLandmarkerOptions(
        base_options=mpt.BaseOptions(model_asset_path=a.model), running_mode=vision.RunningMode.IMAGE, num_poses=a.people))
    res = det.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(img, cv2.COLOR_BGR2RGB)))
    if not res.pose_landmarks:
        print("NO no person found in the picture")
        sys.exit(1)
    px, py = (float(v) for v in a.pick.split(","))
    hips = [((p[23].x + p[24].x) / 2, (p[23].y + p[24].y) / 2) for p in res.pose_landmarks]
    k = min(range(len(hips)), key=lambda n: (hips[n][0] - px) ** 2 + (hips[n][1] - py) ** 2)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    json.dump({"size": [W, H], "image": [[round(q.x, 5), round(q.y, 5), round(q.visibility, 3)] for q in res.pose_landmarks[k]]},
              open(a.out, "w"))
    print("POSE 1 person -> %s" % a.out)


if __name__ == "__main__":
    main()
