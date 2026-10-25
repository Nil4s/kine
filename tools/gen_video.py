"""GENERATED REFERENCE VIDEO (Nick 2026-10-20: "we can gen infinity animations on comfyui, then use them as videos to track,
hit w hammers, sprint, other stuff will be more natural than hand made"). A move in words -> a short clip from a local
ComfyUI (Wan 2.1 text-to-video, Apache 2.0) -> the same clip goes through tools/see_video.py and the video import like any
other footage.
ComfyUI is a separate program on this machine (D:/ComfyUI, GPL-3.0): this script only talks to its HTTP API on 127.0.0.1,
nothing of it is linked into Kine or shipped with it.
The prompt is wrapped in what the tracker needs (the Mixkit / kata lessons): ONE person, the WHOLE body head to feet in
frame, light plain clothes, a plain dark background, a static camera, side-on or three-quarter view.
Framing v2 (--style v2, NOT yet the default: its feet-out was not measured, see D:/kine_refs/v2/REPORT_V2.md): a wide shot
from far away, feet on a plain floor, and a negative prompt against close-ups and camera moves. The default is still the
first batch's settings (v1 prompt, 30 steps, 832x480); --quality names them explicitly.
    python tools/gen_video.py "swings a sledgehammer down onto the ground" out.webm [--seconds 5] [--seed 1] [--steps 20]
Prints one line "VIDEO <path> <frames> frames <fps> fps <seconds> s" or "ERROR <why>"."""
import argparse
import json
import sys
import time
import urllib.parse
import urllib.request

HOST = "http://127.0.0.1:8188"
# v1: the prompt of the first batch (REPORT.md). Kept for --quality and for the comparison runs.
FRAME_V1 = ("one athletic adult, the whole body from head to feet always in frame with space around it, wearing plain "
            "light grey fitted clothes and dark shoes, plain dark grey studio background, empty floor, static locked-off "
            "camera, three-quarter side view, even soft light, realistic motion, real-time speed")
NEGATIVE_V1 = ("cropped, out of frame, close-up, cut off feet, cut off head, camera movement, zoom, pan, shaky, two people, "
               "crowd, extra limbs, extra arms, extra legs, deformed hands, fused limbs, blurry, slow motion, text, watermark")
# v2: the whole figure, far away, feet on the floor; the negative prompt names the framings that cut the feet off.
FRAME_V2 = ("one athletic adult standing in a wide shot, the camera far away, the whole body from the top of the head to "
            "both feet visible in the middle of the frame with a lot of empty space above and below, feet flat on a plain "
            "floor, plain light grey fitted clothes and dark shoes, plain dark grey studio background, static locked-off "
            "camera, side view, even soft light, realistic motion, real-time speed")
NEGATIVE_V2 = ("close-up, medium shot, cropped, out of frame, cut off feet, cut off legs, cut off head, feet out of frame, "
               "zoom, camera movement, pan, tilt, tracking shot, handheld, shaky, two people, crowd, extra limbs, extra arms, "
               "extra legs, deformed hands, fused limbs, blurry, slow motion, text, watermark")
# v1m: v1 plus words against the FROZEN take. Wan 1.3B often holds one pose for most of the clip (a jab frozen 4.69 of 5 s by
# ffmpeg freezedetect); the take tracks perfectly and imports as a statue. A/B, 4 prompts, same seeds, FAST (20 steps 640x368):
# with these words the walk / jab / cheer / squat froze 0 / 0.45 / 0.37 / 0 of the clip, against 0.68 / 0.94 / 0.28+ / - without;
# the old quality setting (30 steps 832x480, ~490 s) with them froze 0.22 / 0.63 / 0.68 (C:/Temp/claude/kine_batch_ab, batch 1766061)
MOTION = ("one continuous action, the same action the whole time, no other moves, brisk and clearly visible movement, "
          "continuous motion, never pauses, the body moves the whole time")
NEGATIVE_MOTION = "still, frozen, static pose, slow motion, freeze frame, holding a pose"
STYLES = {"v1": (FRAME_V1, NEGATIVE_V1), "v2": (FRAME_V2, NEGATIVE_V2),
          "v1m": (MOTION + ", " + FRAME_V1, NEGATIVE_MOTION + ", " + NEGATIVE_V1)}
DEFAULT_STYLE = "v1m"   # v2 becomes the default only after its feet-out is measured to pass
# the old settings (--quality)
QUALITY = {"style": "v1", "steps": 30, "width": 832, "height": 480}
# the defaults: unchanged until a speed setting and the v2 framing both pass REPORT_V2.md
DEFAULTS = {"style": "v1m", "steps": 30, "width": 832, "height": 480}
FPS = 16   # Wan 2.1's own rate


def build_prompt(words, style=DEFAULT_STYLE):
    """the positive and negative prompt for a move in a few words; style is a key of STYLES"""
    if style not in STYLES:
        raise ValueError("unknown style %r (one of %s)" % (style, ", ".join(STYLES)))
    frame, negative = STYLES[style]
    return "%s, %s" % (words.strip(), frame), negative


def graph(prompt, seconds, seed, steps, w, h, style=DEFAULT_STYLE):
    n = int(round(seconds * FPS / 4.0)) * 4 + 1   # Wan wants 4k + 1 frames
    text, negative = build_prompt(prompt, style)
    return {
        "1": {"class_type": "UNETLoader", "inputs": {"unet_name": "wan2.1_t2v_1.3B_fp16.safetensors", "weight_dtype": "default"}},
        "2": {"class_type": "CLIPLoader", "inputs": {"clip_name": "umt5_xxl_fp8_e4m3fn_scaled.safetensors", "type": "wan"}},
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": "wan_2.1_vae.safetensors"}},
        "4": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": text}},
        "5": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["2", 0], "text": negative}},
        "6": {"class_type": "EmptyHunyuanLatentVideo", "inputs": {"width": w, "height": h, "length": n, "batch_size": 1}},
        "7": {"class_type": "ModelSamplingSD3", "inputs": {"model": ["1", 0], "shift": 8.0}},
        "8": {"class_type": "KSampler", "inputs": {"model": ["7", 0], "positive": ["4", 0], "negative": ["5", 0],
              "latent_image": ["6", 0], "seed": seed, "steps": steps, "cfg": 6.0, "sampler_name": "uni_pc",
              "scheduler": "simple", "denoise": 1.0}},
        "9": {"class_type": "VAEDecode", "inputs": {"samples": ["8", 0], "vae": ["3", 0]}},
        "10": {"class_type": "SaveWEBM", "inputs": {"images": ["9", 0], "filename_prefix": "kine/gen", "codec": "vp9",
               "fps": float(FPS), "crf": 16.0}},
    }, n


def call(path, data=None):
    req = urllib.request.Request(HOST + path, data=json.dumps(data).encode() if data is not None else None,
                                 headers={"Content-Type": "application/json"} if data is not None else {})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prompt")
    ap.add_argument("out")
    ap.add_argument("--seconds", type=float, default=5.0)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--style", choices=sorted(STYLES), default=None,
                    help="prompt template (default %s; v1 = the first batch)" % DEFAULT_STYLE)
    ap.add_argument("--steps", type=int, default=None, help="sampling steps (default %d)" % DEFAULTS["steps"])
    ap.add_argument("--width", type=int, default=None, help="picture width (default %d)" % DEFAULTS["width"])
    ap.add_argument("--height", type=int, default=None, help="picture height (default %d)" % DEFAULTS["height"])
    ap.add_argument("--quality", action="store_true",
                    help="the old settings: v1 prompt, 30 steps, 832x480 (what the first batch used)")
    ap.add_argument("--timeout", type=float, default=1800.0)
    a = ap.parse_args()
    base = QUALITY if a.quality else DEFAULTS
    style = a.style or base["style"]
    steps = a.steps if a.steps is not None else base["steps"]
    width = a.width if a.width is not None else base["width"]
    height = a.height if a.height is not None else base["height"]
    g, n = graph(a.prompt, a.seconds, a.seed, steps, width, height, style)
    try:
        pid = json.loads(call("/prompt", {"prompt": g}))["prompt_id"]
    except Exception as e:
        print("ERROR ComfyUI is not answering on %s (start it: D:/ComfyUI/venv/Scripts/python D:/ComfyUI/main.py): %s" % (HOST, e))
        return 1
    t0 = time.time()
    while time.time() - t0 < a.timeout:
        time.sleep(3)
        h = json.loads(call("/history/" + pid))
        if pid not in h:
            continue
        st = h[pid].get("status", {})
        if st.get("status_str") == "error":
            msgs = [m for m in st.get("messages", []) if m[0] == "execution_error"]
            print("ERROR the generation failed: %s" % (msgs[0][1].get("exception_message", "").strip() if msgs else st))
            return 1
        for node in h[pid].get("outputs", {}).values():
            for f in node.get("images", []) + node.get("videos", []) + node.get("gifs", []):
                q = urllib.parse.urlencode({"filename": f["filename"], "subfolder": f.get("subfolder", ""), "type": f.get("type", "output")})
                with open(a.out, "wb") as o:
                    o.write(call("/view?" + q))
                print("VIDEO %s %d frames %d fps %.1f s (%.0f s to make)" % (a.out, n, FPS, (n - 1) / FPS, time.time() - t0))
                return 0
    print("ERROR no video after %.0f s" % a.timeout)
    return 1


if __name__ == "__main__":
    sys.exit(main())
