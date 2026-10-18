"""VIDEO -> pose.json for Poser's "Animation from video..." (round 45, GATES AA2). Nick 10-18: "all good to use the model
for the pose". MediaPipe PoseLandmarker (a pretrained pose model) finds the person in every frame; this writes the same
pose.json as the game repo's tools/see/pose.py (33 world landmarks per frame: metres, the hips at 0, y down; and the image
points with their visibility), plus the picture's size. Poser's scripts/video_import.gd reads it; no model is in the app.
    python tools/see_video.py <video> <out pose.json> [--fps 30] [--pick 0.5,0.6] [--people 2]
         [--model D:/pose_models/pose_landmarker_heavy.task]
With --people N it finds up to N bodies and follows ONE: the nearest --pick (x, y 0-1 of the picture) in the first frame
it finds anyone, then the one whose hips are nearest the last frame's.
Prints one line: "POSE <frames> frames, <lost> without a body -> <out>", or "NO <why>" and exits 1."""
import argparse
import json
import os
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("out")
    ap.add_argument("--fps", type=float, default=30.0)
    ap.add_argument("--pick", default="0.5,0.6")
    ap.add_argument("--people", type=int, default=2)
    ap.add_argument("--model", default="D:/pose_models/pose_landmarker_heavy.task")
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
    px, py = (float(v) for v in a.pick.split(","))
    last = None
    frames = []
    lost = 0
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
        res = det.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(img, cv2.COLOR_BGR2RGB)),
                                   int(t * 1000))
        if not res.pose_world_landmarks:
            lost += 1
            continue
        want = (px, py) if last is None else last
        hips = [((p[23].x + p[24].x) / 2, (p[23].y + p[24].y) / 2) for p in res.pose_landmarks]
        k = min(range(len(hips)), key=lambda n: (hips[n][0] - want[0]) ** 2 + (hips[n][1] - want[1]) ** 2)
        last = hips[k]
        frames.append({"t": round(t, 3),
                       "world": [[round(q.x, 4), round(q.y, 4), round(q.z, 4)] for q in res.pose_world_landmarks[k]],
                       "image": [[round(q.x, 4), round(q.y, 4), round(q.visibility, 3)] for q in res.pose_landmarks[k]]})
    if len(frames) < 2:
        print("NO the tracker found a person in %d frames" % len(frames))
        sys.exit(1)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    json.dump({"fps": a.fps, "video": os.path.basename(a.video), "size": [W, H], "frames": frames,
               "note": "MediaPipe world landmarks (m, hips at 0, y down), 33 per frame; image = (x, y, visibility) 0-1"},
              open(a.out, "w"))
    print("POSE %d frames, %d without a body -> %s" % (len(frames), lost, a.out))


if __name__ == "__main__":
    main()
