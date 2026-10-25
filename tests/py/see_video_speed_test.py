"""Bars for tools/see_video.py's speed (the crop pass runs in chunks, one thread each).

Run with plain python:  python tests/py/see_video_speed_test.py
    SEE_VIDEO_SELF_CHECK=1 python tests/py/see_video_speed_test.py   (the old code in the new code's place: the timing bar must FAIL)
Prints PASS / FAIL / SKIP lines and exits 1 on any FAIL.

Both tools run on tests/data/see_video_crop_small.mp4 (a 5 s clip, the person about 30% of the picture height, so the crop
pass runs). The old tool is the base commit's (OLD_REV below) read with git into a temp folder. Runs alternate old, new, 3 each,
and the bars use the medians of the wall-clock times (the machine is shared: one run is noise).

TIMING: median(new) <= TARGET x median(old).
EQUALITY: the same frames are tracked, and the joints agree: the mean world-joint difference over all frames and joints is
under 1 cm. The hand matching is reported (frames whose hand set differs); it is not part of the joint bar, because the
hand tracker starts afresh at each chunk, which can move a hand match by a frame.
"""
import json
import math
import os
import statistics
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TOOL = os.path.join(ROOT, "tools", "see_video.py")
FIXTURE = os.path.join(ROOT, "tests", "data", "see_video_crop_small.mp4")
OLD_REV = "0dffa8c"          # the base commit: the pass as it was before the chunked crop pass
TARGET = 0.70                # new median wall time <= this share of the old median
RUNS = 3
JOINT_BAR_M = 0.01           # mean world-joint difference, metres (1 cm)
HAND_FRAC_BAR = 0.10         # frames whose hand set differs, share of the frames with a hand in either run
FAILS = []


def say(tag, msg):
    print("%s %s" % (tag, msg), flush=True)


def check(name, ok, msg):
    say("PASS" if ok else "FAIL", "%s: %s" % (name, msg))
    if not ok:
        FAILS.append(name)


def git_old(dest):
    out = subprocess.run(["git", "-C", ROOT, "show", "%s:tools/see_video.py" % OLD_REV], capture_output=True)
    if out.returncode != 0:
        say("SKIP", "cannot read %s:tools/see_video.py (%s)" % (OLD_REV, out.stderr.decode(errors="replace").strip()))
        sys.exit(0)
    with open(dest, "wb") as f:
        f.write(out.stdout)
    return dest


def run_tool(tool, out):
    t = time.perf_counter()
    p = subprocess.run([sys.executable, tool, FIXTURE, out, "--fps", "30"], capture_output=True, text=True)
    dt = time.perf_counter() - t
    last = (p.stdout.strip().splitlines() or ["?"])[-1]
    if p.returncode != 0 or not last.startswith("POSE"):
        say("FAIL", "%s exited %d: %s" % (tool, p.returncode, last))
        FAILS.append("run")
        sys.exit(1)
    return dt, last


def joints(path):
    d = json.load(open(path))
    return {round(f["t"], 3): f for f in d["frames"]}


def compare(a_path, b_path):
    A, B = joints(a_path), joints(b_path)
    same = set(A) == set(B)
    dists = []
    hand_frames = hand_diff = 0
    for t in set(A) & set(B):
        for p, q in zip(A[t]["world"], B[t]["world"]):
            dists.append(math.dist(p, q))
        ha, hb = set(A[t].get("hands", {})), set(B[t].get("hands", {}))
        if ha or hb:
            hand_frames += 1
            if ha != hb:
                hand_diff += 1
    mean = sum(dists) / len(dists) if dists else float("inf")
    return same, mean, hand_frames, hand_diff


def main():
    self_check = os.environ.get("SEE_VIDEO_SELF_CHECK", "") == "1"
    if not os.path.exists(FIXTURE):
        say("SKIP", "no fixture %s" % FIXTURE)
        sys.exit(0)
    tmp = tempfile.mkdtemp(prefix="see_video_speed_")
    old_tool = git_old(os.path.join(tmp, "see_video_old.py"))
    new_tool = old_tool if self_check else TOOL
    times = {"old": [], "new": []}
    last = {}
    for r in range(RUNS):
        for name, tool in (("old", old_tool), ("new", new_tool)):
            out = os.path.join(tmp, "%s_%d.json" % (name, r))
            dt, msg = run_tool(tool, out)
            times[name].append(dt)
            last[name] = out
            say("INFO", "run %d %s: %.2f s (%s)" % (r + 1, name, dt, msg))
    mo, mn = statistics.median(times["old"]), statistics.median(times["new"])
    ratio = mn / mo
    check("timing", ratio <= TARGET,
          "median old %.2f s, new %.2f s, ratio %.2f (bar <= %.2f)%s"
          % (mo, mn, ratio, TARGET, " [self-check: old in the new's place, must fail]" if self_check else ""))
    if self_check:
        if FAILS:
            say("RESULT", "self-check OK: the timing bar fails on the old code")
            sys.exit(0)
        say("RESULT", "self-check FAILED: the timing bar passed on the old code")
        sys.exit(1)
    same, mean, hf, hd = compare(last["old"], last["new"])
    check("equality_frames", same, "the same frames tracked: %s" % same)
    check("equality_joints", mean < JOINT_BAR_M, "mean world-joint difference %.5f m (bar < %.2f m)" % (mean, JOINT_BAR_M))
    frac = hd / hf if hf else 0.0
    check("equality_hands", frac <= HAND_FRAC_BAR,
          "hand sets differ in %d of %d frames with a hand (%.1f%%, bar <= %.0f%%)" % (hd, hf, frac * 100, HAND_FRAC_BAR * 100))
    if FAILS:
        say("RESULT", "FAIL (%d): %s" % (len(FAILS), ", ".join(FAILS)))
        sys.exit(1)
    say("RESULT", "PASS")
    sys.exit(0)


if __name__ == "__main__":
    main()
