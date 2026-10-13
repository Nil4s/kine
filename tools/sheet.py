"""python tools/sheet.py <scene name> [yaw ...]  ->  moves/cooked/<name>.gif and <name>_sheet.jpg
Records the scene windowed (godot --record) from each yaw, lays the views side by side; the sheet = 8 moments per view."""
import sys, os, glob, subprocess, shutil, tempfile
from PIL import Image, ImageDraw

G = r"C:/Users/Nick/Tools/Godot/4.7.2/Godot_v4.7.2-stable_win64_console.exe"
name = sys.argv[1]
yaws = [float(a) for a in sys.argv[2:]] or [-40.0, -90.0]
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
tmp = os.path.join(os.environ.get("CLAUDE_JOB_DIR", tempfile.gettempdir()), "tmp", "rec_" + name)
views = []
for y in yaws:
    d = f"{tmp}_{int(y)}"
    shutil.rmtree(d, ignore_errors=True)
    subprocess.run([G, "--path", root, "--", "--scene", f"scenes/{name}.json", "--yaw", str(y), "--record", d, "--fps", "20"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)
    views.append(sorted(glob.glob(d + "/*.png")))
n = max(len(v) for v in views)
W = 360


def crop(p, w=W):
    return Image.open(p).convert("RGB").crop((350, 0, 1250, 900)).resize((w, w))


frames = []
for i in range(n):
    o = Image.new("RGB", (W * len(views), W + 22), (18, 19, 22))
    for k, v in enumerate(views):
        o.paste(crop(v[min(i, len(v) - 1)]), (k * W, 22))
    ImageDraw.Draw(o).text((8, 5), f"{name}   {i / 20:.2f} s", fill=(255, 230, 120))
    frames.append(o.quantize(64))
out = os.path.join(root, "moves", "cooked")
os.makedirs(out, exist_ok=True)
frames[0].save(f"{out}/{name}.gif", save_all=True, append_images=frames[1:], duration=50, loop=0)
ks = [round(i * (n - 1) / 7) for i in range(8)]
S = 240
sh = Image.new("RGB", (S * 8, S * len(views)), (18, 19, 22))
for r, v in enumerate(views):
    for c, k in enumerate(ks):
        im = crop(v[min(k, len(v) - 1)], S)
        ImageDraw.Draw(im).text((5, 5), f"{k / 20:.2f}s", fill=(255, 230, 120))
        sh.paste(im, (c * S, r * S))
sh.save(f"{out}/{name}_sheet.jpg", quality=85)
print("sheet", f"{out}/{name}_sheet.jpg", n, "frames")
