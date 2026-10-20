"""qr_tool.py - Kine's QR helper (ROADMAP R26: share a pose or a short scene as a QR image, no server, no account).

  python tools/qr_tool.py encode <text_file> <out.png> [--ecc L|M|Q|H] [--px 1200]
  python tools/qr_tool.py decode <image>
  python tools/qr_tool.py camera <index> <result.json> [--seconds 25]

Every call prints ONE json line on stdout: {"ok": true, ...} or {"ok": false, "why": "..."} (a reason that names the next step).
Licences: segno (BSD-3-Clause) draws the code; zxing-cpp (Apache-2.0) reads it; Pillow (HPND) and OpenCV (Apache-2.0)
open the picture / the camera. No GPL anywhere.   pip install segno zxing-cpp pillow opencv-python
"""
import json
import sys
import time

# QR version 40 capacity (ISO 18004), characters of ALPHANUMERIC mode per error-correction level
CAP_ALNUM = {"L": 4296, "M": 3391, "Q": 2420, "H": 1852}


def out(d):
    sys.stdout.write(json.dumps(d) + "\n")
    sys.stdout.flush()


def encode(argv):
    try:
        import segno
    except ImportError:
        return out({"ok": False, "why": "the QR drawer is missing: run  pip install segno  and try again"})
    src, dst = argv[0], argv[1]
    ecc = argv[argv.index("--ecc") + 1] if "--ecc" in argv else "auto"
    px = int(argv[argv.index("--px") + 1]) if "--px" in argv else 1200
    text = open(src, encoding="utf-8").read()
    tried = [ecc] if ecc != "auto" else ["M", "L"]   # M survives a phone photo better; L only when M does not fit
    qr = None
    for e in tried:
        try:
            qr = segno.make(text, error=e, micro=False, boost_error=False)
            break
        except Exception as ex:   # segno.DataOverflowError
            last = str(ex)
    if qr is None:
        return out({"ok": False, "why": "too long for one QR (%d characters; the most is %d at level L)" % (len(text), CAP_ALNUM["L"]), "chars": len(text)})
    modules = qr.symbol_size(border=0)[0]
    scale = max(3, px // (modules + 8))
    qr.save(dst, kind="png", scale=scale, border=4, dark="#000000", light="#ffffff")
    out({"ok": True, "version": qr.version, "ecc": qr.error, "modules": modules, "scale": scale, "mode": qr.mode, "chars": len(text),
         "side_px": (modules + 8) * scale})


def _read(img):
    import zxingcpp
    res = zxingcpp.read_barcodes(img, formats=zxingcpp.BarcodeFormat.QRCode, try_rotate=True, try_downscale=True, try_invert=True)
    return res[0].text if res else None


def decode_image(path):
    from PIL import Image, ImageFilter, ImageOps
    im = Image.open(path)
    im = ImageOps.exif_transpose(im).convert("L")
    tries = [im]
    w, h = im.size
    tries.append(ImageOps.autocontrast(im))
    tries.append(im.filter(ImageFilter.UnsharpMask(radius=2, percent=150)))
    if max(w, h) < 1400:   # a small / half-size photo: the modules are only a couple of pixels, so enlarge first
        tries.append(im.resize((w * 2, h * 2), Image.BICUBIC))
        tries.append(ImageOps.autocontrast(im.resize((w * 3, h * 3), Image.BICUBIC)))
    tries.append(im.point(lambda v: 255 if v > 128 else 0))
    for t in tries:
        txt = _read(t)
        if txt:
            return txt
    return None


def decode(argv):
    try:
        import zxingcpp  # noqa: F401
        from PIL import Image  # noqa: F401
    except ImportError:
        return out({"ok": False, "why": "the QR reader is missing: run  pip install zxing-cpp pillow  and try again"})
    try:
        txt = decode_image(argv[0])
    except Exception as ex:
        return out({"ok": False, "why": "could not open %s as a picture (%s): pick a PNG or JPG of the QR" % (argv[0], ex)})
    if not txt:
        return out({"ok": False, "why": "no QR found in that picture: take it straight on, fill the frame with the code, and keep it sharp"})
    out({"ok": True, "text": txt})


def camera(argv):
    try:
        import cv2
        import zxingcpp
    except ImportError:
        return out({"ok": False, "why": "the webcam reader needs  pip install opencv-python zxing-cpp  : run it, or open the QR from an image file instead"})
    idx, dst = int(argv[0]), argv[1]
    secs = float(argv[argv.index("--seconds") + 1]) if "--seconds" in argv else 25.0
    cap = cv2.VideoCapture(idx)
    if not cap.isOpened():
        res = {"ok": False, "why": "camera %d did not open: close the program using it, or open the QR from an image file instead" % idx}
    else:
        res = {"ok": False, "why": "no QR seen in %d s: hold the code still, fill the frame, and try again" % secs}
        t0 = time.time()
        while time.time() - t0 < secs:
            okf, frame = cap.read()
            if not okf:
                continue
            txt = _read(frame)
            if txt:
                res = {"ok": True, "text": txt}
                break
        cap.release()
    with open(dst, "w", encoding="utf-8") as f:
        json.dump(res, f)
    out(res)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "encode" and len(sys.argv) >= 4:
        encode(sys.argv[2:])
    elif cmd == "decode" and len(sys.argv) >= 3:
        decode(sys.argv[2:])
    elif cmd == "camera" and len(sys.argv) >= 4:
        camera(sys.argv[2:])
    else:
        out({"ok": False, "why": "usage: qr_tool.py encode <text> <png> | decode <image> | camera <index> <result.json>"})
