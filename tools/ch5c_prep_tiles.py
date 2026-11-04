"""CH5c: turn the Poly Haven CC0 photo texture 'Cobblestone Floor 04' (Rob Tuytel, https://polyhaven.com/a/cobblestone_floor_04, CC0)
into the runtime assets: a sett LABEL raster (one id per stone, from a watershed on the photo's displacement map), the distance to the
nearest joint, the displacement and the albedo, all 1024 px for the 1.5 m tile (the scene uses 0.75 m per tile: setts about 11 cm).
usage: python tools/ch5c_prep_tiles.py SRC_DIR OUT_DIR   (SRC_DIR holds cf04_diff.jpg and cf04_disp.jpg, the 2k downloads)"""
import sys, os, numpy as np
from PIL import Image
from scipy import ndimage as ndi
from skimage import filters, measure, morphology, segmentation, feature

src, out = sys.argv[1], sys.argv[2]
N = 1024
disp = np.asarray(Image.open(os.path.join(src, "cf04_disp.jpg")).convert("L").resize((N, N), Image.LANCZOS)).astype(np.float32)
diff = Image.open(os.path.join(src, "cf04_diff.jpg")).convert("RGB").resize((N, N), Image.LANCZOS)
# 3x3 periodic padding so stones across the tile edge are whole. The stone mask comes from the DIFFUSE photo: stone is lighter and less
# green than the mossy, dark joint fill (the displacement map has too much grain inside a stone to segment on).
D = np.asarray(diff).astype(np.float32) / 255.0
lum = 0.3 * D[..., 0] + 0.59 * D[..., 1] + 0.11 * D[..., 2]
green = D[..., 1] - 0.5 * (D[..., 0] + D[..., 2])
score = ndi.gaussian_filter(lum - 1.2 * np.clip(green, 0, None), 1.5)
score = np.tile(score, (3, 3))
thr = filters.threshold_otsu(score[N:2 * N, N:2 * N])
mask = score > thr * 0.95
mask = ndi.binary_opening(mask, iterations=2)
mask = ndi.binary_fill_holes(mask)
mask = morphology.remove_small_objects(mask, max_size=200)
dist = ndi.distance_transform_edt(mask)
dsm = ndi.gaussian_filter(dist, 3.0)
pk = feature.peak_local_max(dsm, min_distance=22, threshold_abs=5, labels=measure.label(mask), exclude_border=False)
mk = np.zeros(mask.shape, np.int32)
for i, (y, x) in enumerate(pk):
    mk[y, x] = i + 1
lab = segmentation.watershed(-dsm, mk, mask=mask)
# union labels of the same texel in neighbouring tile copies
par = {}
def find(a):
    while par.get(a, a) != a:
        par[a] = par.get(par[a], par[a])
        a = par[a]
    return a
for dy in (-1, 0, 1):
    for dx in (-1, 0, 1):
        if dy == 0 and dx == 0:
            continue
        a = lab[N:2 * N, N:2 * N]
        b = lab[N + dy * N:2 * N + dy * N, N + dx * N:2 * N + dx * N]
        m = (a > 0) & (b > 0)
        for u, v in set(zip(a[m].tolist(), b[m].tolist())):
            ru, rv = find(u), find(v)
            if ru != rv:
                par[max(ru, rv)] = min(ru, rv)
c = lab[N:2 * N, N:2 * N].copy()
ids = {}
res = np.zeros(c.shape, np.int32)
for v in np.unique(c):
    if v == 0:
        continue
    r = find(int(v))
    ids.setdefault(r, len(ids) + 1)
    res[c == v] = ids[r]
# drop tiny regions (specks of grit), keep real setts
areas = np.bincount(res.ravel())
for k in range(1, len(areas)):
    if areas[k] < 400:
        res[res == k] = 0
uniq = [k for k in np.unique(res) if k > 0]
remap = {k: i + 1 for i, k in enumerate(uniq)}
lut = np.zeros(res.max() + 1, np.int32)
for k, v in remap.items():
    lut[k] = v
res = lut[res]
n = len(uniq)
# edge distance: inside a stone, pixels to the nearest non-stone / other-stone pixel
bound = np.zeros(res.shape, bool)
bound[:, :-1] |= res[:, :-1] != res[:, 1:]
bound[:-1, :] |= res[:-1, :] != res[1:, :]
bound |= res == 0
bound = np.roll(bound, 0)
d = ndi.distance_transform_edt(~bound | (res == 0) & False)
d = ndi.distance_transform_edt(res > 0) if False else ndi.distance_transform_edt(~(bound))
edge = np.where(res > 0, d, 0.0)
# per stone unwrapped bbox (pixels), centred on the stone's circular mean so a stone across the seam has a contiguous box
rows = []
for k in range(1, n + 1):
    ys, xs = np.nonzero(res == k)
    cx0, cy0 = xs[0], ys[0]
    dx = ((xs - cx0 + N // 2) % N) - N // 2
    dy = ((ys - cy0 + N // 2) % N) - N // 2
    rows.append((k, cx0 + dx.min(), cx0 + dx.max() + 1, cy0 + dy.min(), cy0 + dy.max() + 1, float(disp[ys, xs].mean())))
os.makedirs(out, exist_ok=True)
rgb = np.zeros((N, N, 3), np.uint8)
rgb[..., 0] = res & 255
rgb[..., 1] = res >> 8
Image.fromarray(rgb).save(os.path.join(out, "cobble_label.png"))
Image.fromarray(np.clip(edge * 4.0, 0, 255).astype(np.uint8)).save(os.path.join(out, "cobble_edge.png"))
Image.fromarray(disp.astype(np.uint8)).save(os.path.join(out, "cobble_disp.png"))
diff.save(os.path.join(out, "cobble_albedo.jpg"), quality=92)
with open(os.path.join(out, "cobble_stones.csv"), "w") as f:
    f.write("id,l,r,t,b,disp\n")
    for r in rows:
        f.write("%d,%d,%d,%d,%d,%.1f\n" % r)
# preview
prev = np.asarray(diff).copy()
bd = segmentation.find_boundaries(res, mode="inner")
prev[bd] = (255, 0, 0)
Image.fromarray(prev).save(os.path.join(src, "labels_preview.png"))
print("stones", n, "mortar fraction %.2f" % float((res == 0).mean()), "median stone area px %d" % int(np.median(np.bincount(res.ravel())[1:])))
