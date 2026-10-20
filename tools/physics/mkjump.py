"""python tools/physics/mkjump.py walk_clip.json out.json : the IMPOSSIBLE JUMP of the I1 test and shots. Frame 0 of a clip held for 2 s,
but between 0.5 s and 1.5 s the pelvis (and so the feet) is lifted 0.4 m with the legs unchanged: both feet off the floor
for a second with no fall = a hover, which no body can do."""
import copy
import json
import sys

c = json.load(open(sys.argv[1]))
f0 = c["frames"][0]
fps = c["fps"]
fr = []
for k in range(int(2 * fps)):
    t = k / fps
    f = copy.deepcopy(f0)
    f["t"] = t
    up = 0.0
    if 0.5 <= t <= 1.5:
        up = 0.4 * min(1, (t - 0.5) / 0.1, (1.5 - t) / 0.1)
    f["pelvis"][1] += up
    fr.append(f)
c["frames"] = fr
json.dump(c, open(sys.argv[2], "w"))
