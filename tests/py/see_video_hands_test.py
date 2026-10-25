"""Bar for tools/see_video.py's hands on a small person (the crop pass finds each hand on a crop round its wrist).

Run with plain python:  python tests/py/see_video_hands_test.py
Prints PASS / FAIL / SKIP lines and exits 1 on any FAIL. SEE_VIDEO_TOOL=<path> runs another copy of the tool (used to show
the bar fails on the code before the wrist crops).

The clip is tests/data/see_video_crop_small.mp4 (the person at about 30% of the picture height, 81 frames). The bar: a
hand is found on at least HANDS_BAR of the frames where a wrist is visible (visibility >= 0.5). Measured: the tool before
the wrist crops found 2 of 81 frames; with them 77 of 81 (the right hand on 77, the left hand on none: the left fist is
too small for the hand model at this resolution, which the INFO line shows).
"""
import json
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TOOL = os.environ.get("SEE_VIDEO_TOOL") or os.path.join(ROOT, "tools", "see_video.py")
FIXTURE = os.path.join(ROOT, "tests", "data", "see_video_crop_small.mp4")
MODEL = "D:/pose_models/pose_landmarker_heavy.task"
HAND_MODEL = "D:/hand_models_handcap/hand_landmarker.task"
HANDS_BAR = 0.9       # the share of wrist-visible frames that need a hand (measured 77 of 81 = 95%)
FAILS = []


def say(tag, msg):
    print("%s %s" % (tag, msg), flush=True)


def skip(msg):
    say("SKIP", msg)
    sys.exit(0)


def check(name, ok, detail):
    say("PASS" if ok else "FAIL", "%s: %s" % (name, detail))
    if not ok:
        FAILS.append(name)


def main():
    if not os.path.exists(TOOL):
        skip("no tool at %s" % TOOL)
    try:
        import cv2  # noqa: F401
        import mediapipe  # noqa: F401
    except ImportError as e:
        skip("mediapipe / opencv not importable here (%s)" % e)
    if not os.path.exists(MODEL):
        skip("no pose model at %s" % MODEL)
    if not os.path.exists(HAND_MODEL):
        skip("no hand model at %s" % HAND_MODEL)
    if not os.path.exists(FIXTURE):
        skip("the small fixture is missing (%s)" % FIXTURE)
    out = os.path.join(tempfile.mkdtemp(prefix="see_video_hands_"), "small.json")
    t = time.time()
    r = subprocess.run([sys.executable, TOOL, FIXTURE, out], capture_output=True, text=True)
    secs = time.time() - t
    notes = [ln for ln in (r.stdout + r.stderr).splitlines() if ln.startswith(("POSE", "NO"))]
    if r.returncode != 0 or not os.path.exists(out):
        check("small clip tracks", False, "rc %d, %s" % (r.returncode, notes))
        return finish()
    with open(out, encoding="utf-8") as f:
        data = json.load(f)
    frames = data["frames"]
    wrist_vis = [f for f in frames if f["image"][15][2] >= 0.5 or f["image"][16][2] >= 0.5]
    with_hands = [f for f in wrist_vis if f.get("hands")]
    share = len(with_hands) / float(len(wrist_vis)) if wrist_vis else 0.0
    say("INFO", "%d frames, %d with a wrist visible, %d with a hand (%.1fs): %s"
        % (len(frames), len(wrist_vis), len(with_hands), secs, notes[-1] if notes else ""))
    check("hands on the small person", share >= HANDS_BAR,
          "%d of %d wrist-visible frames have a hand (%.0f%%, need >= %d%%)"
          % (len(with_hands), len(wrist_vis), 100 * share, round(100 * HANDS_BAR)))
    say("INFO", "per side: left %d frames, right %d frames"
        % (sum(1 for f in frames if "l" in (f.get("hands") or {})), sum(1 for f in frames if "r" in (f.get("hands") or {}))))
    inside = all(0.0 <= x <= 1.0 and 0.0 <= y <= 1.0
                 for f in frames for side in (f.get("hands") or {}).values() for x, y in side["image"])
    check("hand points stay in the picture", inside, "all hand image points in [0,1]" if inside else "a point is outside")
    return finish()


def finish():
    if FAILS:
        say("RESULT", "FAIL (%d): %s" % (len(FAILS), ", ".join(FAILS)))
        sys.exit(1)
    say("RESULT", "PASS")
    sys.exit(0)


if __name__ == "__main__":
    main()
