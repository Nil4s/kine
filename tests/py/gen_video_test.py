"""tools/gen_video.py: the prompt builder and the ComfyUI graph (no ComfyUI needed). Run: python tests/py/gen_video_test.py"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools"))
import gen_video as g  # noqa: E402

fails = 0


def ok(c, what):
    global fails
    print(("ok   " if c else "FAIL ") + what)
    if not c:
        fails += 1


text, neg = g.build_prompt("walks forward at a steady pace", "v1m")
ok(text.startswith("walks forward at a steady pace, ") and text.endswith(g.FRAME_V1) and g.MOTION in text, "the move's words lead the prompt (v1m: v1 + the motion words)")
ok("frozen" in neg and neg.endswith(g.NEGATIVE_V1), "v1m says no to a frozen take (negative: %s...)" % neg[:40])
text3, neg3 = g.build_prompt("walks forward at a steady pace")
ok(g.DEFAULT_STYLE == "v3" and text3.endswith(g.FRAME_V3) and "frozen" in neg3 and "motion blur" in neg3 and "hands out of frame" in neg3,
   "the default is v3 (comfy4: hands and feet in frame and sharp; it says no to a frozen take and to motion blur)")
text2, neg2 = g.build_prompt("walks forward at a steady pace", "v2")
ok(text2.startswith("walks forward at a steady pace, ") and "whole body" in text2 and "wide shot" in text2, "v2 asks for the whole body and a wide shot")
ok("cropped" in neg2 and "out of frame" in neg2 and "close-up" in neg2, "v2 negative names cropped, out of frame and close-up")
t1, n1 = g.build_prompt("walks forward", "v1")
ok(t1 == "walks forward, " + g.FRAME_V1 and n1 == g.NEGATIVE_V1, "v1 is the first batch's prompt, unchanged")
try:
    g.build_prompt("x", "v9")
    ok(False, "an unknown style is refused")
except ValueError:
    ok(True, "an unknown style is refused")
gr, n = g.graph("walks", 5.0, 1, 20, 640, 384, "v2")
ok(n == 81, "5 s is 81 frames (Wan's 4k+1)")
ok(gr["8"]["inputs"]["steps"] == 20 and gr["6"]["inputs"]["width"] == 640 and gr["6"]["inputs"]["height"] == 384,
   "steps and size reach the graph")
gt, gn = g.build_prompt("walks", "v2")
gr = g.graph("walks", 5.0, 1, 20, 640, 384, "v2")[0]
ok(gr["4"]["inputs"]["text"] == gt and gr["5"]["inputs"]["text"] == gn, "the graph carries the built prompt and negative")
ok(g.QUALITY == {"style": "v1", "steps": 30, "width": 832, "height": 480}, "--quality is the old settings")
print("GEN_VIDEO %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
sys.exit(1 if fails else 0)
