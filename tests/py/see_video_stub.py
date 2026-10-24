"""Stand-in for tools/see_video.py in tests (no MediaPipe): same arguments: <video> <out> --progress <file>.
TRK_STUB_PLAN = "good,bad,lost": the verdict of each call in turn (1-based; the last one repeats):
  good: the world landmarks of tests/fixtures/gen_hammer_pose.json, every landmark visible at 0.95, all 81 frames
  bad:  the first 20 of 81 frames (a person in about a quarter of the clip: "Couldn't find a person")
  lost: all 81 frames, the left hand (15, 17, 19, 21) at 0.1 in every frame (a score under 0.5)
The pose file has "seen" (the frames the tracker looked at), as the real tracker writes it.
TRK_STUB_LOG: each call appends "<video>\t<out>\t<progress>" to it (the call number is the line count)."""
import json
import os
import sys

FIXTURE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "fixtures", "gen_hammer_pose.json")
LEFT_HAND = (15, 17, 19, 21)
SEEN = 81

args = sys.argv[1:]
video, out = args[0], args[1]
prog = args[args.index("--progress") + 1] if "--progress" in args else ""
plan = [p.strip() for p in os.environ.get("TRK_STUB_PLAN", "good").split(",") if p.strip()]
log = os.environ.get("TRK_STUB_LOG", "")
n = 1
if log:
    n = (open(log).read().count("\n") if os.path.exists(log) else 0) + 1
    with open(log, "a") as f:
        f.write("%s\t%s\t%s\n" % (video, out, prog))
verdict = plan[min(n, len(plan)) - 1] if plan else "good"

src = json.load(open(FIXTURE))
frames = []
for f in src["frames"][:SEEN]:
    vis = [[0.5, 0.5, 0.95] for _ in range(33)]
    if verdict == "lost":
        for k in LEFT_HAND:
            vis[k][2] = 0.1
    fr = {"t": f["t"], "world": f["world"], "image": vis}
    if "hands" in f:
        fr["hands"] = f["hands"]
    frames.append(fr)
if verdict == "bad":
    frames = frames[:20]
os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
json.dump({"fps": src["fps"], "video": os.path.basename(video), "size": src["size"], "frames": frames, "seen": SEEN,
           "note": "stand-in (tests/py/see_video_stub.py): verdict %s" % verdict}, open(out, "w"))
if prog:
    with open(prog, "w") as pf:
        pf.write("1.000")
print("POSE %d frames, %d without a body, 0 with a hand -> %s" % (len(frames), SEEN - len(frames), out))
