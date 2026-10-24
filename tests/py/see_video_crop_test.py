"""Bars for tools/see_video.py's crop pass (a small person in the picture is tracked on a crop round them).

Run with plain python:  python tests/py/see_video_crop_test.py
Prints PASS / FAIL / SKIP lines and exits 1 on any FAIL.

The controlled bar: tests/data/see_video_crop_small.mp4 is the big clip cmb01_jab (the person at 74% of the picture height)
scaled to 260x150 and padded into a 640x368 frame at x 190, y 109, so the person is about 30% of the height. Its track is
mapped back into the big clip's own picture and compared with the big clip's track. The error is in person-box units (the
big clip's median box height, in pixels) per joint, median over the joints and frames both tracked with visibility >= 0.5.
The visible share is the share of the 81 frames with all of hips, knees, ankles and wrists visible >= 0.5.
"""
import json
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TOOL = os.path.join(ROOT, "tools", "see_video.py")
FIXTURE = os.path.join(ROOT, "tests", "data", "see_video_crop_small.mp4")
BIG = "C:/Temp/claude/kine_batch_v2test/combat/cmb01_jab/video.mp4"
MODEL = "D:/pose_models/pose_landmarker_heavy.task"
W, H = 640, 368
KX, KY, OX, OY = 260 / 640.0, 150 / 368.0, 190, 109   # the shrink: scale, then the pad offset in the small picture
KEY = (23, 24, 25, 26, 27, 28, 15, 16)                 # hips, knees, ankles, wrists
REL_GAIN = 0.30                                        # crop must cut the median error by this share vs no-crop
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


def try_imports():
    try:
        import cv2  # noqa: F401
        import mediapipe  # noqa: F401
    except ImportError as e:
        skip("mediapipe / opencv not importable here (%s)" % e)


def run_tool(video, out, extra=()):
    t = time.time()
    r = subprocess.run([sys.executable, TOOL, video, out] + list(extra), capture_output=True, text=True)
    el = time.time() - t
    log = (r.stdout + r.stderr).splitlines()
    notes = [ln for ln in log if ln.startswith(("POSE", "NO", "crop"))]
    data = None
    if r.returncode == 0 and os.path.exists(out):
        with open(out, encoding="utf-8") as f:
            data = json.load(f)
    return {"secs": el, "rc": r.returncode, "notes": notes, "data": data, "out": out}


def median(v):
    v = sorted(v)
    n = len(v)
    if n == 0:
        return float("nan")
    return v[n // 2] if n % 2 else 0.5 * (v[n // 2 - 1] + v[n // 2])


def big_unit(big):
    """the big clip's median person box height in pixels (joints with visibility >= 0.5)"""
    hs = []
    for f in big["frames"]:
        ys = [q[1] for q in f["image"] if q[2] >= 0.5]
        if len(ys) >= 5:
            hs.append((max(ys) - min(ys)) * H)
    return median(hs)


def to_big(x, y):
    """a point of the small picture (normalized) -> the big clip's picture (normalized)"""
    return (((x * W) - OX) / KX) / W, (((y * H) - OY) / KY) / H


def metrics(run, big, unit):
    """(median per-joint error in person-box units, visible share over the big clip's frames, frames tracked)"""
    by_t = {round(f["t"], 3): f for f in big["frames"]}
    errs = []
    vis_ok = 0
    n_total = len(big["frames"])
    tracked = 0
    for f in run["data"]["frames"]:
        tracked += 1
        if all(f["image"][k][2] >= 0.5 for k in KEY):
            vis_ok += 1
        ref = by_t.get(round(f["t"], 3))
        if ref is None:
            continue
        for j in range(33):
            x, y, v = f["image"][j]
            xb, yb, vb = ref["image"][j]
            if v < 0.5 or vb < 0.5:
                continue
            bx, by = to_big(x, y)
            errs.append(((bx - xb) ** 2 * W * W + (by - yb) ** 2 * H * H) ** 0.5 / unit)
    return median(errs), vis_ok / float(n_total), tracked


def points_inside(data):
    """every image point (body and hands) of a run is inside the picture"""
    for f in data["frames"]:
        for x, y, _ in f["image"]:
            if not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0):
                return False, f["t"]
        for side in (f.get("hands") or {}).values():
            for x, y in side["image"]:
                if not (0.0 <= x <= 1.0 and 0.0 <= y <= 1.0):
                    return False, f["t"]
    return True, None


def main():
    if not os.path.exists(TOOL):
        skip("no tools/see_video.py")
    try_imports()
    if not os.path.exists(MODEL):
        skip("no pose model at %s" % MODEL)
    if not os.path.exists(BIG):
        skip("the big reference clip is missing (%s)" % BIG)
    if not os.path.exists(FIXTURE):
        skip("the shrunk fixture is missing (%s)" % FIXTURE)
    tmp = tempfile.mkdtemp(prefix="see_video_crop_")

    big_run = run_tool(BIG, os.path.join(tmp, "big.json"))
    if big_run["rc"] != 0:
        check("big reference tracks", False, "tracker said %s" % big_run["notes"])
        return finish()
    unit = big_unit(big_run["data"])
    say("INFO", "big reference: %d frames, %.1fs, person box %.0f px (%.0f%% of the height)"
        % (len(big_run["data"]["frames"]), big_run["secs"], unit, 100.0 * unit / H))

    nc_def = run_tool(FIXTURE, os.path.join(tmp, "small_nocrop_default.json"), ["--no-crop"])
    nc = run_tool(FIXTURE, os.path.join(tmp, "small_nocrop.json"), ["--no-crop", "--detect-conf", "0.2"])
    cr = run_tool(FIXTURE, os.path.join(tmp, "small_crop.json"))
    say("INFO", "small no-crop at MediaPipe's default 0.5: rc %d, %s, %.1fs"
        % (nc_def["rc"], nc_def["notes"], nc_def["secs"]))
    say("INFO", "small no-crop at detection 0.2: rc %d, %s, %.1fs" % (nc["rc"], nc["notes"], nc["secs"]))
    say("INFO", "small crop (default): rc %d, %s, %.1fs" % (cr["rc"], cr["notes"], cr["secs"]))

    if nc["rc"] != 0 or cr["rc"] != 0:
        check("small clip tracks", False, "no-crop rc %d, crop rc %d" % (nc["rc"], cr["rc"]))
        return finish()

    e_nc, vis_nc, n_nc = metrics(nc, big_run["data"], unit)
    e_cr, vis_cr, n_cr = metrics(cr, big_run["data"], unit)
    say("INFO", "median joint error (person-box units): no-crop %.3f, crop %.3f" % (e_nc, e_cr))
    say("INFO", "visible share (hips, knees, ankles, wrists >= 0.5): no-crop %.2f, crop %.2f, big reference %.2f"
        % (vis_nc, vis_cr, metrics(big_run, big_run["data"], unit)[1]))
    say("INFO", "frames with a body: no-crop %d, crop %d of %d" % (n_nc, n_cr, len(big_run["data"]["frames"])))

    rel = (e_nc - e_cr) / e_nc if e_nc > 0 else 0.0
    check("crop cuts the median error", rel >= REL_GAIN,
          "no-crop %.3f -> crop %.3f (%.0f%% lower, need >= %d%%)" % (e_nc, e_cr, 100 * rel, 100 * REL_GAIN))
    check("crop keeps the visible share", vis_cr >= vis_nc,
          "crop %.2f vs no-crop %.2f" % (vis_cr, vis_nc))
    inside, bad_t = points_inside(cr["data"])
    check("mapped points stay in the picture", inside,
          "all body and hand points in [0,1]" if inside else "a point is outside at t=%s" % bad_t)
    check("crop was triggered on the small clip", any("tracked on a crop" in n for n in cr["notes"]),
          cr["notes"][-1] if cr["notes"] else "no note")

    # the big person: the crop must not trigger, and the output is the same with the crop code as without
    big_nc = run_tool(BIG, os.path.join(tmp, "big_nocrop.json"), ["--no-crop"])
    same = big_nc["rc"] == 0 and open(big_run["out"], "rb").read() == open(big_nc["out"], "rb").read()
    not_triggered = not any("tracked on a crop" in n for n in big_run["notes"])
    check("big person: no crop, identical output with and without the crop code",
          same and not_triggered,
          "identical bytes: %s; crop not triggered: %s" % (same, not_triggered))
    return finish()


def finish():
    if FAILS:
        say("RESULT", "FAIL (%d): %s" % (len(FAILS), ", ".join(FAILS)))
        sys.exit(1)
    say("RESULT", "PASS")
    sys.exit(0)


if __name__ == "__main__":
    main()
