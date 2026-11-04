#!/usr/bin/env python3
"""CH1a: writes data/challenges/ch1_house.json (a Kine Part record + the Building record + the member list) and out/ch1/members.json.
The house is the 1949 Levitt Ranch envelope (32 x 25 ft, see docs/CH1_REFERENCE.md), 2x4 platform framing, mm, Y up, x along the long side,
z = 0 is the street (front) wall. Run: python tools/ch1_build_house.py [outdir]. Nothing here is read by the app; the json is the data."""
import json, math, os, sys

T = 38.0      # actual thickness of a 2x
D = 89.0      # actual depth of a 2x4
G16 = 406.4
G24 = 609.6
W = 9754.0    # 32 ft
DP = 7620.0   # 25 ft
STUD = 2353.0  # 92 5/8 in precut
Y_B1 = T                      # top of bottom plate
Y_T1 = T + STUD               # 2391 top of studs / bottom of top plate 1
Y_T2 = Y_T1 + T               # 2429
HW = Y_T2 + T                 # 2467 top of the double top plate
JOIST_D = 184.0               # 2x8
RAFT_V = 235.0 / math.cos(math.atan(4 / 12.0))   # vertical depth of a 2x10 rafter at 4:12
TAN = 4 / 12.0
COS = math.cos(math.atan(TAN))
SIN = math.sin(math.atan(TAN))
OVER = 406.0                  # eave overhang, horizontal
RIDGE_Z = DP / 2.0
RFT = T                       # rafter thickness
KITCHEN_DOOR_X = 3300.0

COL = {"ground": (0.32, 0.46, 0.26), "slab": (0.62, 0.62, 0.60), "plate": (0.55, 0.62, 0.46), "stud": (0.80, 0.65, 0.42),
       "header": (0.70, 0.52, 0.32), "joist": (0.86, 0.72, 0.48), "rafter": (0.82, 0.66, 0.42), "ridge": (0.68, 0.52, 0.34),
       "osb": (0.76, 0.63, 0.40), "shingle": (0.23, 0.24, 0.27), "siding": (0.90, 0.84, 0.66), "window": (0.55, 0.72, 0.85),
       "door": (0.45, 0.17, 0.12), "idoor": (0.72, 0.62, 0.48), "sill": (0.70, 0.55, 0.35)}


class R:
    def __init__(self):
        self.f = []
        self.seq = 0
        self.nb = 0
        self.members = []
        self.planes = {}
        self.stage_marks = []

    def feat(self, t, name, **kw):
        self.seq += 1
        d = {"t": t, "id": "f%d" % self.seq, "name": name}
        d.update(kw)
        self.f.append(d)
        return d

    def look(self, body, kind, name):
        kind0 = kind
        c = COL[kind]
        kw = {"body": float(body), "color": list(c), "metal": 0.0, "rough": 0.9, "preset": "Custom"}
        if kind == "window":
            kw.update({"alpha": 0.35, "rough": 0.05})
        self.feat("appear", "Paint " + gname(kind), **kw)

    def member(self, name, kind, nominal, box, **extra):
        m = {"name": name, "kind": kind, "nominal": nominal, "box": [round(v, 3) for v in box]}
        m.update(extra)
        self.members.append(m)

    def box(self, name, kind, nominal, x0, y0, z0, x1, y1, z1, look=None, **extra):
        self.feat("prim", gname(kind), kind="box", op="new", x=x0, y=y0, z=z0, w=x1 - x0, h=y1 - y0, d=z1 - z0)
        b = self.nb
        self.nb += 1
        self.look(b, look or kind_look(kind), name)
        self.member(name, kind, nominal, [x0, y0, z0, x1, y1, z1], **extra)
        return b

    def row(self, name, kind, nominal, x0, y0, z0, x1, y1, z1, count, step, axis, look=None, namefmt=None, **extra):
        """one box and a linear pattern: count boxes step apart along axis ('x'|'z'); a single box when count == 1"""
        if count == 1:
            return self.box(namefmt(0) if namefmt else name, kind, nominal, x0, y0, z0, x1, y1, z1, look, **extra)
        self.feat("prim", gname(kind), kind="box", op="new", x=x0, y=y0, z=z0, w=x1 - x0, h=y1 - y0, d=z1 - z0)
        b = self.nb
        self.nb += 1
        self.look(b, look or kind_look(kind), name)
        self.feat("pattern", name + " x%d" % count, body=float(b), kind="linear", dir=axis, count=float(count), mm=step, op="new")
        self.nb += count - 1
        for i in range(count):
            o = i * step
            bx = [x0 + (o if axis == "x" else 0), y0, z0 + (o if axis == "z" else 0), x1 + (o if axis == "x" else 0), y1, z1 + (o if axis == "z" else 0)]
            self.member(namefmt(i) if namefmt else "%s.%d" % (name, i), kind, nominal, bx, **extra)
        return b

    def plane(self, x):
        k = round(x, 3)
        if k not in self.planes:
            self.planes[k] = self.feat("plane", "right @%s" % k, **{"from": "right", "mm": k})["id"]
        return self.planes[k]

    def poly(self, name, kind, nominal, pts_zy, x0, thick, look=None, count=1, step=0.0, **extra):
        """a polygon in the Z-Y plane extruded along +X from x0 by thick; pts are (z, y) mm; count > 1 repeats it along X every step"""
        pid = self.plane(x0)
        ents = []
        n = len(pts_zy)
        for i in range(n):
            a = pts_zy[i]
            b = pts_zy[(i + 1) % n]
            ents.append({"a": [-a[0], a[1]], "b": [-b[0], b[1]], "k": "line"})
        sk = self.feat("sketch", name + " section", plane=pid, dims=[], ents=ents)
        self.feat("extrude", gname(kind), sketch=sk["id"], dist=thick, both=False, op="new")
        b = self.nb
        self.nb += 1
        self.look(b, look or kind_look(kind), name)
        zs = [p[0] for p in pts_zy]
        ys = [p[1] for p in pts_zy]
        if count > 1:
            self.feat("pattern", name + " x%d" % count, body=float(b), kind="linear", dir="x", count=float(count), mm=step, op="new")
            self.nb += count - 1
        for i in range(count):
            o = i * step
            self.member(extra.pop("namefmt")(i) if "namefmt" in extra and i == 0 and False else (name if count == 1 else "%s.%d" % (name, i)), kind, nominal,
                        [x0 + o, min(ys), min(zs), x0 + o + thick, max(ys), max(zs)], poly=[[round(p[0], 3), round(p[1], 3)] for p in pts_zy], **{k: v for k, v in extra.items() if k != "namefmt"})
        return b

    def mark(self, name):
        self.stage_marks.append({"name": name, "upto": len(self.f)})


def gname(kind):
    return kind.replace("_", " ").capitalize()


def kind_look(kind):
    if kind in ("bottom_plate", "top_plate1", "top_plate2"):
        return "plate"
    if kind in ("stud", "king", "jack", "cripple", "corner", "end", "nailer", "gable_stud"):
        return "stud"
    if kind == "header":
        return "header"
    if kind in ("joist",):
        return "joist"
    if kind in ("rafter", "gable_rafter"):
        return "rafter"
    if kind == "ridge":
        return "ridge"
    if kind in ("wall_sheathing", "roof_sheathing", "gable_sheathing"):
        return "osb"
    if kind == "sill":
        return "sill"
    return kind


def lower(z):
    """rafter underside height over z (front slope; mirrored for the back)"""
    if z > RIDGE_Z:
        z = DP - z
    return HW + (z - D) * TAN


def subtract(x0, x1, y0, y1, holes):
    """rectangle minus rectangles -> list of rectangles (x0, y0, x1, y1)"""
    xs = sorted(set([x0, x1] + [min(max(h[0], x0), x1) for h in holes] + [min(max(h[2], x0), x1) for h in holes]))
    out = []
    for a, b in zip(xs[:-1], xs[1:]):
        if b - a < 1e-6:
            continue
        mid = 0.5 * (a + b)
        cov = sorted([(max(h[1], y0), min(h[3], y1)) for h in holes if h[0] < mid < h[2] and h[3] > y0 and h[1] < y1])
        y = y0
        for lo, hi in cov:
            if lo - y > 1e-6:
                out.append((a, y, b, lo))
            y = max(y, hi)
        if y1 - y > 1e-6:
            out.append((a, y, b, y1))
    return out


# ------------------------------------------------------------------ the plan
DOOR_W, DOOR_H = 914.0, 2032.0
IDOOR_W = 762.0
WIN_W, WIN_H, WIN_SILL = 914.0, 1219.0, 914.0
BATH_W, BATH_H, BATH_SILL = 610.0, 914.0, 1219.0
RO = 25.0     # rough opening is the unit + 25 mm

# openings per wall: along = centre along the wall's axis; kind door|window|cased; bearing: header 2-2x8 (else a 2x4 flat)
OPEN = {
    "F": [("door", 3300.0, DOOR_W, DOOR_H, 0.0, True, "Entry door (through the kitchen)"), ("window", 1100.0, WIN_W, WIN_H, WIN_SILL, True, "Kitchen window"),
          ("window", 8200.0, WIN_W, WIN_H, WIN_SILL, True, "Bedroom 2 window front")],
    "B": [("window", 1300.0, WIN_W, WIN_H, WIN_SILL, True, "Living window 1"), ("window", 3300.0, WIN_W, WIN_H, WIN_SILL, True, "Living window 2"),
          ("window", 5500.0, BATH_W, BATH_H, BATH_SILL, True, "Bath window"), ("window", 8000.0, WIN_W, WIN_H, WIN_SILL, True, "Bedroom 1 window rear")],
    "L": [("window", 1800.0, WIN_W, WIN_H, WIN_SILL, True, "Kitchen window side"), ("window", 5500.0, WIN_W, WIN_H, WIN_SILL, True, "Living window side")],
    "R": [("window", 1800.0, WIN_W, WIN_H, WIN_SILL, True, "Bedroom 2 window side"), ("window", 5500.0, WIN_W, WIN_H, WIN_SILL, True, "Bedroom 1 window side")],
    "H": [("cased", 2222.0, 914.0, 2032.0, 0.0, True, "Kitchen to living opening"), ("cased", 5500.0, 914.0, 2032.0, 0.0, True, "Hall to rear hall opening")],
    "V1": [("idoor", 1900.0, IDOOR_W, 2032.0, 0.0, False, "Door kitchen to hall"), ("idoor", 5700.0, IDOOR_W, 2032.0, 0.0, False, "Door living to rear hall")],
    "V2": [("idoor", 1900.0, IDOOR_W, 2032.0, 0.0, False, "Door hall to bedroom 2"), ("idoor", 5700.0, IDOOR_W, 2032.0, 0.0, False, "Door rear hall to bedroom 1")],
}

V1X = 4400.5   # centre lines
V2X = 6623.5
HZ = 3486.5
# wall: axis along which it runs, the cross-axis position of its footprint, the runs [a0, a1] of its plates (None = whole)
WALLS = {
    "F": {"axis": "x", "c0": 0.0, "plates1": [(0.0, W)], "plates2": [(D, W - D)], "field": (0.0, W), "ends": "corner"},
    "B": {"axis": "x", "c0": DP - D, "plates1": [(0.0, W)], "plates2": [(D, W - D)], "field": (0.0, W), "ends": "corner"},
    "L": {"axis": "z", "c0": 0.0, "plates1": [(D, DP - D)], "plates2": [(0.0, DP)], "field": (D, DP - D), "ends": "corner"},
    "R": {"axis": "z", "c0": W - D, "plates1": [(D, DP - D)], "plates2": [(0.0, DP)], "field": (D, DP - D), "ends": "corner"},
    "H": {"axis": "x", "c0": HZ - D / 2, "plates1": [(D, W - D)], "plates2": [(D, V1X - D / 2), (V1X + D / 2, V2X - D / 2), (V2X + D / 2, W - D)], "field": (D, W - D), "ends": "end"},
    "V1": {"axis": "z", "c0": V1X - D / 2, "plates1": [(D, HZ - D / 2), (HZ + D / 2, DP - D)], "plates2": [(D, DP - D)], "field": None, "ends": "end"},
    "V2": {"axis": "z", "c0": V2X - D / 2, "plates1": [(D, HZ - D / 2), (HZ + D / 2, DP - D)], "plates2": [(D, DP - D)], "field": None, "ends": "end"},
}
NAILERS = {"F": [V1X, V2X], "B": [V1X, V2X], "H": [V1X, V2X], "L": [], "R": [], "V1": [], "V2": []}
V_SEGS = [(D, HZ - D / 2), (HZ + D / 2, DP - D)]


def bx(w, a0, a1, y0, y1, c0=None):
    """a box on wall w from a0 to a1 along its axis, y0..y1, across its full depth (x/z order fixed by the axis)"""
    ww = WALLS[w]
    c = ww["c0"] if c0 is None else c0
    if ww["axis"] == "x":
        return (a0, y0, c, a1, y1, c + D)
    return (c, y0, a0, c + D, y1, a1)


def opening_geom(w, o):
    kind, c, wd, ht, sill, bearing, label = o
    ro0 = c - (wd + RO) / 2
    ro1 = c + (wd + RO) / 2
    yb = 0.0 if kind in ("door", "idoor", "cased") else sill
    yt = (ht + RO) if kind in ("door", "idoor", "cased") else sill + ht + RO
    return ro0, ro1, yb, yt


def build():
    r = R()
    # ---- ground and slab
    r.box("Ground", "ground", "grade", -6000, -700, -6000, W + 6000, -102, DP + 6000)
    r.box("Slab on grade", "slab", "4 in concrete", 0, -102, 0, W, 0, DP)
    r.mark("Slab")
    # ---- bottom plates (cut at door openings)
    for w, ww in WALLS.items():
        doors = [opening_geom(w, o)[:2] for o in OPEN[w] if o[0] in ("door", "idoor", "cased")]
        i = 0
        for a0, a1 in ww["plates1"]:
            cuts = sorted([d for d in doors if d[0] > a0 and d[1] < a1])
            s = a0
            for d0, d1 in cuts + [(a1, a1)]:
                if d0 - s > 1:
                    b = bx(w, s, d0, 0.0, T)
                    r.box("plate_b.%s.%d" % (w, i), "bottom_plate", "2x4 PT", *b, span=d0 - s)
                    i += 1
                s = d1
    r.mark("Sill plates")
    # ---- studs and openings
    for w, ww in WALLS.items():
        axis = ww["axis"]
        segs = [ww["field"]] if ww["field"] else V_SEGS
        blocked = []
        # corner and end studs
        for si, (a0, a1) in enumerate(segs):
            kinds = ww["ends"]
            for k, (s0, s1) in enumerate([(a0, a0 + T), (a1 - T, a1)]):
                b = bx(w, s0, s1, T, Y_T1)
                r.box("%s.%s.%d.%d" % (kinds, w, si, k), kinds, "2x4", *b, span=STUD)
                blocked.append((s0, s1))
        # nailers where a partition meets this wall
        for ni, nc in enumerate(NAILERS[w]):
            b = bx(w, nc - T / 2, nc + T / 2, T, Y_T1)
            r.box("nailer.%s.%d" % (w, ni), "nailer", "2x4", *b, span=STUD)
            blocked.append((nc - T / 2, nc + T / 2))
        # openings
        ops = []
        for oi, o in enumerate(OPEN[w]):
            kind, c, wd, ht, sill, bearing, label = o
            ro0, ro1, yb, yt = opening_geom(w, o)
            ops.append((ro0, ro1, yb, yt, o))
            blocked.append((ro0 - 2 * T, ro1 + 2 * T))
            # kings and jacks
            for side, (k0, j0) in (("a", (ro0 - 2 * T, ro0 - T)), ("b", (ro1 + T, ro1))):
                kx0, kx1 = (ro0 - 2 * T, ro0 - T) if side == "a" else (ro1 + T, ro1 + 2 * T)
                jx0, jx1 = (ro0 - T, ro0) if side == "a" else (ro1, ro1 + T)
                r.box("king.%s.%d%s" % (w, oi, side), "king", "2x4", *bx(w, kx0, kx1, T, Y_T1), span=STUD)
                r.box("jack.%s.%d%s" % (w, oi, side), "jack", "2x4", *bx(w, jx0, jx1, T, yt), span=yt - T)
            # header
            if bearing:
                hy0, hy1, nom = yt, yt + JOIST_D, "2-2x8"
            else:
                hy0, hy1, nom = yt, yt + T, "2x4 flat"
            assert hy1 <= Y_T1 + 0.01, (w, oi, hy1)
            r.box("header.%s.%d" % (w, oi), "header", nom, *bx(w, ro0 - 2 * T, ro1 + 2 * T, hy0, hy1), span=ro1 - ro0, label=label)
            # window sill and cripples under
            if kind == "window":
                r.box("sill.%s.%d" % (w, oi), "sill", "2x4", *bx(w, ro0, ro1, yb - T, yb), span=ro1 - ro0)
        # grid studs and cripples
        s0f = min(s[0] for s in segs)
        s1f = max(s[1] for s in segs)
        k = 1
        runs = []
        cur = []
        cripples_above = []
        cripples_below = []
        while k * G16 < s1f:
            c = k * G16
            k += 1
            if c - T / 2 < s0f:
                continue
            ins = [(a0, a1) for a0, a1 in segs if c - T / 2 >= a0 + T - 1e-6 and c + T / 2 <= a1 - T + 1e-6]
            if not ins:
                continue
            if any(c + T / 2 > b0 + 1e-6 and c - T / 2 < b1 - 1e-6 for b0, b1 in blocked):
                # inside an opening zone: a cripple over the header / under the sill when the grid line is inside the rough opening
                for ro0, ro1, yb, yt, o in ops:
                    if c - T / 2 >= ro0 - 1e-6 and c + T / 2 <= ro1 + 1e-6:
                        hy1 = yt + (JOIST_D if o[5] else T)
                        cripples_above.append((c, hy1))
                        if o[0] == "window":
                            cripples_below.append((c, yb - T))
                cur = []
                continue
            runs.append(c)
        # contiguous grid runs (a gap = a missing grid line)
        groups = []
        for c in runs:
            if groups and abs(c - groups[-1][-1] - G16) < 0.01:
                groups[-1].append(c)
            else:
                groups.append([c])
        for gi, g in enumerate(groups):
            c0 = g[0] - T / 2
            b = bx(w, c0, c0 + T, T, Y_T1)
            ax = "x" if axis == "x" else "z"
            r.row("stud.%s.%d" % (w, gi), "stud", "2x4", *b, len(g), G16, ax, namefmt=lambda i, w=w, gi=gi: "stud.%s.%d.%d" % (w, gi, i), span=STUD, spacing=G16)
        for ci, (c, y0) in enumerate(cripples_above):
            r.box("cripple.%s.a%d" % (w, ci), "cripple", "2x4", *bx(w, c - T / 2, c + T / 2, y0, Y_T1), span=Y_T1 - y0)
        for ci, (c, y1) in enumerate(cripples_below):
            r.box("cripple.%s.b%d" % (w, ci), "cripple", "2x4", *bx(w, c - T / 2, c + T / 2, T, y1), span=y1 - T)
    r.mark("Wall framing")
    # ---- top plates
    for w, ww in WALLS.items():
        for i, (a0, a1) in enumerate(ww["plates1"]):
            r.box("plate_t1.%s.%d" % (w, i), "top_plate1", "2x4", *bx(w, a0, a1, Y_T1, Y_T2), span=a1 - a0)
        for i, (a0, a1) in enumerate(ww["plates2"]):
            r.box("plate_t2.%s.%d" % (w, i), "top_plate2", "2x4", *bx(w, a0, a1, Y_T2, HW), span=a1 - a0)
    r.mark("Top plates")
    # ---- ceiling joists 2x8 @ 16 in, running front to back, spliced over the hall wall
    j_step = G16
    n_j = int((W - 2 * T) // G16)   # centres k*G16 for k = 1..23
    n_j = 23
    for si, (z0, z1) in enumerate([(0.0, HZ), (HZ, DP)]):
        r.row("joist.%d" % si, "joist", "2x8", G16 - T / 2, HW, z0, G16 + T / 2, HW + JOIST_D, z1, n_j, G16, "x",
              namefmt=lambda i, si=si: "joist.%d.%d" % (si, i), span=(HZ - D / 2) - (D / 2) if si == 0 else (DP - D / 2) - HZ, spacing=G16)
    r.mark("Ceiling joists")
    # ---- gable end studs (bevelled at the rafter underside)
    for ei, x0 in enumerate([0.0, W - D]):
        for k in range(1, 19):
            c = k * G16
            if abs(c - RIDGE_Z) < T / 2 + RFT / 2 + 1:
                continue
            za, zb = c - T / 2, c + T / 2
            if za < D or zb > DP - D:
                continue
            pts = [(za, HW), (zb, HW), (zb, lower(zb)), (za, lower(za))]
            r.poly("gable_stud.%d.%d" % (ei, k), "gable_stud", "2x4", pts, x0, D, span=lower(c) - HW)
    r.mark("Gable studs")
    # ---- ridge and rafters
    ry0 = lower(RIDGE_Z - RFT / 2) - 21.0
    r.box("ridge", "ridge", "2x12", 0, ry0, RIDGE_Z - T / 2, W, ry0 + 286.0, RIDGE_Z + T / 2, span=W)
    for face in ("front", "back"):
        def zz(z):
            return z if face == "front" else DP - z
        zr = RIDGE_Z - T / 2
        tail_low = HW + (-OVER - D) * TAN
        pts = [(-OVER, tail_low), (0.0, HW + (0 - D) * TAN), (0.0, HW), (D, HW), (zr, lower(zr)), (zr, lower(zr) + RAFT_V), (-OVER, tail_low + RAFT_V)]
        if face == "back":
            pts = [(DP - z, y) for z, y in pts]
        # rafters at 24 in o.c.: centres k*G24, k = 1..15, and a rafter flush with each gable end
        r.poly("rafter.%s" % face, "rafter", "2x10", pts, G24 - T / 2, RFT, count=15, step=G24, spacing=G24, span=(RIDGE_Z - D / 2), slope="4:12")
        r.poly("gable_rafter.%s.0" % face, "gable_rafter", "2x10", pts, 0.0, RFT, span=(RIDGE_Z - D / 2))
        r.poly("gable_rafter.%s.1" % face, "gable_rafter", "2x10", pts, W - RFT, RFT, span=(RIDGE_Z - D / 2))
    r.mark("Rafters and ridge")
    # ---- wall sheathing (7/16 OSB, 4 x 8 sheets, minus the openings), outside the studs
    OSB = 11.1
    faces = {"F": ("x", -OSB, 0.0), "B": ("x", DP, DP + OSB), "L": ("z", -OSB, 0.0), "R": ("z", W, W + OSB)}
    length = {"F": W, "B": W, "L": DP, "R": DP}
    for w in "FBLR":
        axis, c0, c1 = faces[w]
        holes = []
        for o in OPEN[w]:
            ro0, ro1, yb, yt = opening_geom(w, o)
            holes.append((ro0, yb, ro1, yt))
        sheet = 1219.2
        n = int(math.ceil(length[w] / sheet - 1e-9))
        pi = 0
        for s in range(n):
            a0, a1 = s * sheet, min((s + 1) * sheet, length[w])
            for (xa, ya, xb, yb2) in subtract(a0, a1, 0.0, HW, holes):
                if axis == "x":
                    r.box("sheathing.%s.%d" % (w, pi), "wall_sheathing", "7/16 OSB", xa, ya, c0, xb, yb2, c1)
                else:
                    r.box("sheathing.%s.%d" % (w, pi), "wall_sheathing", "7/16 OSB", c0, ya, xa, c1, yb2, xb)
                pi += 1
    # gable end sheathing (a pentagon on each end)
    for ei, x0 in enumerate([-OSB, W]):
        pts = [(0.0, HW), (DP, HW), (DP, lower(0.0) + RAFT_V), (RIDGE_Z, lower(RIDGE_Z - RFT / 2) + RAFT_V), (0.0, lower(0.0) + RAFT_V)]
        r.poly("sheathing.gable.%d" % ei, "gable_sheathing", "7/16 OSB", pts, x0, OSB)
    r.mark("Wall sheathing")
    # ---- roof sheathing: two rows of 4 x 8 sheets per slope, 8 columns of 1219.2
    for face in ("front", "back"):
        # P(s): along the top edge of the rafters from the tail
        z_t, y_t = -OVER, HW + (-OVER - D) * TAN + RAFT_V
        slope_len = (lower(RIDGE_Z - RFT / 2) + RAFT_V - y_t) / SIN
        rows = [(0.0, 2438.4), (2438.4, slope_len)]
        for ri, (s0, s1) in enumerate(rows):
            a = (z_t + s0 * COS, y_t + s0 * SIN)
            b = (z_t + s1 * COS, y_t + s1 * SIN)
            nrm = (-SIN * OSB, COS * OSB)
            pts = [a, b, (b[0] + nrm[0], b[1] + nrm[1]), (a[0] + nrm[0], a[1] + nrm[1])]
            if face == "back":
                pts = [(DP - z, y) for z, y in pts]
            r.poly("roof_sheathing.%s.%d" % (face, ri), "roof_sheathing", "7/16 OSB", pts, 0.0, 1219.2, count=8, step=1219.2)
    r.mark("Roof sheathing")
    # ---- shingles
    for face in ("front", "back"):
        z_t, y_t = -OVER, HW + (-OVER - D) * TAN + RAFT_V
        slope_len = (lower(RIDGE_Z - RFT / 2) + RAFT_V - y_t) / SIN
        a = (z_t, y_t)
        b = (z_t + slope_len * COS, y_t + slope_len * SIN)
        o1 = (-SIN * OSB, COS * OSB)
        o2 = (-SIN * (OSB + 9.5), COS * (OSB + 9.5))
        pts = [(a[0] + o1[0], a[1] + o1[1]), (b[0] + o1[0], b[1] + o1[1]), (b[0] + o2[0], b[1] + o2[1]), (a[0] + o2[0], a[1] + o2[1])]
        if face == "back":
            pts = [(DP - z, y) for z, y in pts]
        r.poly("shingles.%s" % face, "shingle", "asphalt shingles", pts, 0.0, W)
    r.mark("Shingles")
    # ---- siding (19 mm) over the wall sheathing, minus the openings
    SID = 19.0
    sfaces = {"F": ("x", -OSB - SID, -OSB), "B": ("x", DP + OSB, DP + OSB + SID), "L": ("z", -OSB - SID, -OSB), "R": ("z", W + OSB, W + OSB + SID)}
    for w in "FBLR":
        axis, c0, c1 = sfaces[w]
        holes = []
        for o in OPEN[w]:
            ro0, ro1, yb, yt = opening_geom(w, o)
            holes.append((ro0, yb, ro1, yt))
        pi = 0
        for (xa, ya, xb, yb2) in subtract(0.0, length[w], 0.0, HW, holes):
            if axis == "x":
                r.box("siding.%s.%d" % (w, pi), "siding", "19 mm lap siding", xa, ya, c0, xb, yb2, c1)
            else:
                r.box("siding.%s.%d" % (w, pi), "siding", "19 mm lap siding", c0, ya, xa, c1, yb2, xb)
            pi += 1
    r.mark("Siding")
    # ---- windows and doors (units sit in the rough openings)
    for w in "FBLR":
        for oi, o in enumerate(OPEN[w]):
            ro0, ro1, yb, yt = opening_geom(w, o)
            c0 = WALLS[w]["c0"]
            if o[0] == "window":
                b = bx(w, ro0, ro1, yb, yt, c0)
                r.box("window.%s.%d" % (w, oi), "window", "%d x %d unit" % (o[2] / 25.4, o[3] / 25.4), b[0], b[1], b[2], b[3] if WALLS[w]["axis"] == "z" else b[3], b[4], b[5], label=o[6])
            else:
                b = bx(w, ro0, ro1, 0.0, DOOR_H, c0)
                r.box("door.%s.%d" % (w, oi), "door", "36 x 80 in", *b, label=o[6])
    for w in ("H", "V1", "V2"):
        for oi, o in enumerate(OPEN[w]):
            if o[0] != "idoor":
                continue
            ro0, ro1, yb, yt = opening_geom(w, o)
            c0 = WALLS[w]["c0"]
            b = bx(w, ro0, ro1, 0.0, 2032.0, c0)
            r.box("door.%s.%d" % (w, oi), "idoor", "30 x 80 in", *b, label=o[6])
    r.mark("Windows and doors")
    return r


def window_fix(r):
    """windows were made with the wall's depth axis taken from bx(); a unit is 60 mm thick, centred in the stud depth: bx() already gives c0..c0+D,
    so shrink the unit's cross size to 60 mm (the box call above passed the full depth)."""
    return r


def supports(members):
    """for each member: the members whose top face it rests on (gap < 1 mm, footprints overlap) and the ones it touches sideways"""
    out = {}
    for m in members:
        b = m["box"]
        below = []
        touch = []
        for n in members:
            if n is m:
                continue
            c = n["box"]
            if c[0] > b[3] + 1 or c[3] < b[0] - 1 or c[2] > b[5] + 1 or c[5] < b[2] - 1 or c[1] > b[4] + 1 or c[4] < b[1] - 1:
                continue
            touch.append(n["name"])
            ox = min(b[3], c[3]) - max(b[0], c[0])
            oz = min(b[5], c[5]) - max(b[2], c[2])
            if ox > 0.5 and oz > 0.5 and abs(c[4] - b[1]) < 1.0:
                below.append(n["name"])
        out[m["name"]] = (below, touch)
    return out


def building():
    p = {"wall_height": HW / 1000.0, "wall_thickness": D / 1000.0, "floor_thickness": 0.102, "door_width": 0.914, "door_height": 2.057, "window_width": 0.939,
         "window_height": 1.244, "window_sill": 0.914, "grid": 0.05, "floor_height": 2.8, "roof_overhang": OVER / 1000.0, "inner_wall_thickness": D / 1000.0}
    b = {"version": 1, "name": "Levitt Ranch 1949 (CH1)", "params": p, "nature": [],
         "rooms": [{"id": "r1", "x": 0.0, "z": 0.0, "w": W / 1000.0, "d": DP / 1000.0, "yaw": 0.0, "height": "wall_height", "thickness": "wall_thickness", "floor": True}],
         "walls": [{"id": "i1", "room": "r1", "axis": "x", "pos": HZ / 1000.0, "thickness": "inner_wall_thickness"},
                   {"id": "i2", "room": "r1", "axis": "z", "pos": V1X / 1000.0, "thickness": "inner_wall_thickness"},
                   {"id": "i3", "room": "r1", "axis": "z", "pos": V2X / 1000.0, "thickness": "inner_wall_thickness"}],
         "openings": [], "roof": {"kind": "gable", "pitch": round(math.degrees(math.atan(TAN)), 2), "overhang": "roof_overhang"}}
    mid_x = W / 2000.0
    mid_z = DP / 2000.0
    n = 0
    for w, wid in (("F", "front"), ("B", "back"), ("L", "left"), ("R", "right"), ("H", "i1"), ("V1", "i2"), ("V2", "i3")):
        for o in OPEN[w]:
            kind, c, wd, ht, sill, bearing, label = o
            if wid in ("front", "back", "i1"):
                at = c / 1000.0 - mid_x
            elif wid in ("left", "right"):
                at = c / 1000.0 - mid_z
            else:
                at = c / 1000.0 - (DP / 2000.0)
            n += 1
            bk = "door" if kind in ("door", "idoor") else "window" if kind == "window" else "arch"
            b["openings"].append({"id": "o%d" % n, "room": "r1", "wall": wid, "kind": bk, "at": round(at, 4), "w": wd / 1000.0, "h": ht / 1000.0, "sill": sill / 1000.0, "label": label})
    return b


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    r = build()
    sup = supports(r.members)
    for m in r.members:
        below, touch = sup[m["name"]]
        m["supports"] = below
        m["touches"] = touch
    rec = {"name": "Levitt Ranch 1949 (CH1)", "seq": r.seq, "version": 1, "features": r.f}
    data = {"kind": "ch1_house", "reference": "docs/CH1_REFERENCE.md", "part": rec, "building": building(), "stages": r.stage_marks, "members": r.members,
            "grid_mm": {"stud": G16, "joist": G16, "rafter": G24}}
    os.makedirs(os.path.join(out_dir, "data", "challenges"), exist_ok=True)
    with open(os.path.join(out_dir, "data", "challenges", "ch1_house.json"), "w") as fh:
        json.dump(data, fh, indent=1)
    mem = [{"name": m["name"], "kind": m["kind"], "nominal": m["nominal"], "span_mm": m.get("span"), "spacing_mm": m.get("spacing"), "supports": m["supports"],
            "box_mm": m["box"]} for m in r.members]
    od = os.path.join(out_dir, "out", "ch1")
    os.makedirs(od, exist_ok=True)
    with open(os.path.join(od, "members.json"), "w") as fh:
        json.dump({"house": "Levitt Ranch 1949", "units": "mm", "members": mem}, fh, indent=1)
    print("features", len(r.f), "bodies", r.nb, "members", len(r.members))


if __name__ == "__main__":
    main()
