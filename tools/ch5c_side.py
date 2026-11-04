"""CH5c side-by-side: the render's central 480 x 720 px is the photo's own frame (same f, same horizon; scripts/wet_street.gd FOV note),
so it is cropped and put beside ref2.jpg scaled to 480 x 720, then the full 1280 x 720 render. python tools/ch5c_side.py [render.png]"""
import sys
from PIL import Image, ImageDraw

OUT = "C:/Users/Nick/tools/kine_workers/out/ch5c/"
ren = Image.open(sys.argv[1] if len(sys.argv) > 1 else OUT + "ch5c_night.png").convert("RGB")
ref = Image.open("C:/Users/Nick/tools/kine_workers/out/ch5/ref/ref2.jpg").convert("RGB").resize((480, 720), Image.LANCZOS)
crop = ren.crop((400, 0, 880, 720))
sheet = Image.new("RGB", (480 + 480 + 1280 + 20, 720))
sheet.paste(crop, (0, 0))
sheet.paste(ref, (480, 0))
sheet.paste(ren, (980, 0))
d = ImageDraw.Draw(sheet)
d.text((8, 6), "Kine (photo frame)", fill=(255, 255, 0))
d.text((488, 6), "ref2.jpg", fill=(255, 255, 0))
d.text((988, 6), "Kine full 1280x720 (photo frame = x 400-880)", fill=(255, 255, 0))
d.rectangle((980 + 400, 0, 980 + 880, 719), outline=(255, 255, 0))
sheet.save(OUT + "ch5c_side_by_side.png")
print("wrote", OUT + "ch5c_side_by_side.png")
