"""Builds assets/fonts/KineHanSubset.otf: Source Han Sans JP (Adobe, SIL OFL 1.1) cut down to ASCII + Latin-1 + kana + CJK/full-width punctuation + GB2312 level 1 (3755 common hanzi).
The OFL reserves the name 'Source', so the subset is renamed 'Kine Han Subset' (a modified version). Usage: python tools/make_han_font.py SourceHanSansJP-Normal.otf"""
import sys
from fontTools import subset
from fontTools.ttLib import TTFont

src = sys.argv[1]
out = "assets/fonts/KineHanSubset.otf"
cps = set(range(0x20, 0x7F)) | set(range(0xA0, 0x100)) | set(range(0x3000, 0x3040)) | set(range(0x3041, 0x30FF)) | set(range(0xFF01, 0xFF61))
cps |= {0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2026, 0x2022, 0x00B7}
for hi in range(0xB0, 0xD8):   # GB2312 level 1: rows 16-55
    for lo in range(0xA1, 0xFF):
        try:
            cps.add(ord(bytes([hi, lo]).decode("gb2312")))
        except Exception:
            pass
opt = subset.Options()
opt.layout_features = []
opt.hinting = False
opt.name_IDs = ["*"]
opt.notdef_outline = True
opt.glyph_names = False
opt.legacy_kern = False
f = TTFont(src)
sub = subset.Subsetter(opt)
sub.populate(unicodes=sorted(cps))
sub.subset(f)
for n in f["name"].names:
    s = n.toUnicode()
    if n.nameID in (1, 16):
        n.string = "Kine Han Subset"
    elif n.nameID == 4:
        n.string = "Kine Han Subset"
    elif n.nameID == 6:
        n.string = "KineHanSubset-Regular"
    elif n.nameID == 3:
        n.string = "KineHanSubset-Regular;modified"
    elif n.nameID in (2, 17):
        n.string = "Regular"
f.save(out)
print(len(cps), "code points ->", out)
