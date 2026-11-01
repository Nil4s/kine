extends RefCounted
## s228 PATTERNS ALONG PATHS AND GRIDS: the two Part pattern kinds that a Blender Array + Curve modifier does. Part._pattern_copies hands these kinds here
## and gets back the kernel copies; the group pattern (s214) hands the group's centre in "gref", so a whole group moves and turns as one.
##
## kind "grid"   : cols x rows x layers copies in ONE step. count = columns along dir (spacing mm), rows along dir2 (spacing mm2), layers along dir3 (spacing mm3).
##                 The original is column 1, row 1, layer 1. dir/dir2/dir3 are "x" | "y" | "z" (the three should differ).
## kind "route"  : copies along a path. The path is ONE of: path = a sketch id (lines, arcs, splines, rects, circles, joined end to end),
##                 pts = [[x, y, z], ...] world mm (+ closed), (footprint_pts() makes the rectangle round a body or a roof eave).
##                 count (copies on the path, the original counts when it sits on a copy's place) or mm (spacing); fit = the spacing adjusts so the first copy is on the
##                 start and the last on the end (a closed path: the copies split it evenly); corners = a copy exactly at every corner, each straight run split evenly
##                 by mm; follow = the copy turns with the path (at a corner: to the bisector); hold (default on) = a piece beside the path keeps its offset from it.
##                 The piece's heading is the path's heading at the place it stands on; a copy is turned by the difference.
## Variation (both): seed + jit (mm, position) + jit_turn (deg) + jit_scale (fraction, needs src) are seeded, so the same seed gives the same copies;
##                 skip = every Nth place is left empty (the original's place never).
const KCad := preload("res://scripts/kcad.gd")
const MM := 0.001
const KINDS := ["grid", "route"]
const MAX_COPIES := 400
const CORNER_DEG := 5.0
const AX := {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}


## the copies of srcb for a grid / route step: kernel ids appended to out (0 where one failed: the caller releases the others). "" or the reason
static func copies(rec: Dictionary, f: Dictionary, srcb: int, out: Array) -> String:
	var c: Vector3 = (KCad.mass_properties(srcb).get("center", Vector3.ZERO) as Vector3)
	if f.has("gref"):
		var g: Array = f["gref"]
		c = Vector3(float(g[0]), float(g[1]), float(g[2]))
	var slots: Array = []
	var why := _grid_slots(f, slots) if String(f.get("kind", "")) == "grid" else _route_slots(rec, f, c, slots)
	if why != "":
		return why
	why = _vary(f, slots)
	if why != "":
		return why
	if slots.size() > MAX_COPIES:
		return "%d copies is more than %d: use fewer" % [slots.size(), MAX_COPIES]
	for sl in slots:
		out.append(_place(rec, f, srcb, c, sl))
	return ""


## the centre (m) of a set of bodies: the mean of their centres of mass (the reference a group moves about)
static func group_center(bodies: Array, idx: Array) -> Array:
	var s := Vector3.ZERO
	for bi in idx:
		s += (KCad.mass_properties(int(bodies[int(bi)])).get("center", Vector3.ZERO) as Vector3)
	s /= maxf(float(idx.size()), 1.0)
	return [s.x, s.y, s.z]


# ---------------------------------------------------------------- grid

## slots: {"i": place number (0 = the original), "d": move of the centre (m), "ax": turn axis, "ang": turn (rad), "sc": scale}
static func _grid_slots(f: Dictionary, slots: Array) -> String:
	var nc := int(f.get("count", 1))
	var nr := int(f.get("rows", 1))
	var nl := int(f.get("layers", 1))
	if nc < 1 or nr < 1 or nl < 1:
		return "a grid needs 1 or more columns, rows and layers"
	if nc * nr * nl < 2:
		return "a grid needs at least 2 places"
	if nc * nr * nl > MAX_COPIES:
		return "%d x %d x %d places is more than %d: use fewer" % [nc, nr, nl, MAX_COPIES]
	var d1: Vector3 = AX.get(String(f.get("dir", "x")), Vector3.RIGHT)
	var d2: Vector3 = AX.get(String(f.get("dir2", "z")), Vector3.BACK)
	var d3: Vector3 = AX.get(String(f.get("dir3", "y")), Vector3.UP)
	var m1 := float(f.get("mm", 0.0)) * MM
	var m2 := float(f.get("mm2", 0.0)) * MM
	var m3 := float(f.get("mm3", 0.0)) * MM
	if (nc > 1 and absf(m1) < 1e-9) or (nr > 1 and absf(m2) < 1e-9) or (nl > 1 and absf(m3) < 1e-9):
		return "the spacing must not be zero"
	var i := 0
	for l in nl:
		for r in nr:
			for k in nc:
				if i > 0:
					slots.append({"i": i, "d": d1 * m1 * k + d2 * m2 * r + d3 * m3 * l, "ax": Vector3.UP, "ang": 0.0, "sc": 1.0})
				i += 1
	return ""


# ---------------------------------------------------------------- variation: skip every Nth, seeded jitter

## drops the skipped places and adds the jitter (the same draws for every place, so a skip does not shift the others)
static func _vary(f: Dictionary, slots: Array) -> String:
	var jp := float(f.get("jit", 0.0)) * MM
	var jt := deg_to_rad(float(f.get("jit_turn", 0.0)))
	var js := float(f.get("jit_scale", 0.0))
	var skip := int(f.get("skip", 0))
	if skip == 1:
		return "skip every 2nd or more (1 would skip every copy)"
	if js < 0.0 or js >= 0.9:
		return "the size variation must be between 0 and 0.9"
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f.get("seed", 1))
	var keep: Array = []
	for sl in slots:
		var dx := rng.randf_range(-1.0, 1.0)
		var dy := rng.randf_range(-1.0, 1.0)
		var dz := rng.randf_range(-1.0, 1.0)
		var dt := rng.randf_range(-1.0, 1.0)
		var ds := rng.randf_range(-1.0, 1.0)
		if skip >= 2 and (int(sl["i"]) + 1) % skip == 0:
			continue
		if jp > 0.0:
			var jv := Vector3(dx, dy, dz) * jp
			if sl.has("t"):   # a route: jitter along and across the path (and not up), in its own frame
				var t: Vector3 = sl["t"]
				var n: Vector3 = sl["ax"]
				var side := n.cross(t)
				jv = t * dx * jp + side * dy * jp
			sl["d"] = (sl["d"] as Vector3) + jv
		sl["ang"] = float(sl["ang"]) + dt * jt
		sl["sc"] = 1.0 + ds * js
		keep.append(sl)
	slots.clear()
	slots.append_array(keep)
	return ""


# ---------------------------------------------------------------- placing one copy

## one copy: the piece about its centre c scaled (needs src) and turned about the axis through c, then c moved by d. 0 on failure
static func _place(rec: Dictionary, f: Dictionary, srcb: int, c: Vector3, sl: Dictionary) -> int:
	var ang := float(sl["ang"])
	var sc := float(sl["sc"])
	var d: Vector3 = sl["d"]
	var base := srcb
	var own := false
	var cc := c
	if absf(sc - 1.0) > 1e-9:
		base = _scaled(rec, String(f.get("src", "")), sc)
		if base == 0:
			return 0
		own = true
		cc = (KCad.mass_properties(base).get("center", Vector3.ZERO) as Vector3)   # a scaled piece is moved by its own centre
		d = d + (c - cc)
	var out := 0
	if absf(ang) < 1e-12:
		out = KCad.translate(base, d)
	else:
		var t0 := KCad.translate(base, -cc)
		if t0 != 0:
			var t1 := KCad.rotate(t0, sl["ax"], ang)
			KCad.release(t0)
			if t1 != 0:
				out = KCad.translate(t1, cc + d)
				KCad.release(t1)
	if own:
		KCad.release(base)
	return out


## the newest piece (the extrude step sid) made sc times bigger or smaller, about the middle of its drawn shape: a kernel solid (0 on failure). Like Grow
static func _scaled(rec: Dictionary, sid: String, sc: float) -> int:
	if sid == "":
		return 0
	var sub0 := Part.pattern_src_rec(rec, sid)
	var ex0 := Part.feature(sub0, sid)
	var sk0 := Part.feature(sub0, String(ex0.get("sketch", "")))
	if sub0.is_empty() or String(ex0.get("t", "")) != "extrude" or sk0.is_empty():
		return 0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for e in sk0["ents"]:
		for key in ["a", "b", "c", "m"]:
			if e.has(key):
				lo = lo.min(Part.v2(e[key]))
				hi = hi.max(Part.v2(e[key]))
		for q in e.get("pts", []):
			lo = lo.min(Part.v2(q))
			hi = hi.max(Part.v2(q))
		if e.has("c") and e.has("r"):
			lo = lo.min(Part.v2(e["c"]) - Vector2.ONE * float(e["r"]))
			hi = hi.max(Part.v2(e["c"]) + Vector2.ONE * float(e["r"]))
	var mid := (lo + hi) * 0.5
	var sub := sub0.duplicate(false)
	sub["features"] = (sub0["features"] as Array).duplicate(true)
	var exk := Part.feature(sub, sid)
	var skk := Part.feature(sub, String(exk["sketch"]))
	skk.erase("cons")
	for e in skk["ents"]:
		for key in ["a", "b", "c", "m"]:
			if e.has(key):
				e[key] = Part.arr2(mid + (Part.v2(e[key]) - mid) * sc)
		if e.has("r"):
			e["r"] = float(e["r"]) * sc
		if e.has("pts"):
			var np := []
			for q in e["pts"]:
				np.append(Part.arr2(mid + (Part.v2(q) - mid) * sc))
			e["pts"] = np
	exk["dist"] = float(exk["dist"]) * sc
	var made := Part.replay(sub, -1, {"keep": true})
	var ids: Array = made.get("ids", [])
	if not (made["errors"] as Dictionary).is_empty() or ids.is_empty():
		for b in ids:
			KCad.release(int(b))
		return 0
	for j in ids.size() - 1:
		KCad.release(int(ids[j]))
	return int(ids[-1])


# ---------------------------------------------------------------- route: the path

## the path as {"pieces", "len", "closed", "pl", "err"}. Piece = {"k": line|arc|poly, "pa", "pb" (2D mm), "len", + the shape}; "start" = its distance along the path
static func path_of(rec: Dictionary, f: Dictionary, c: Vector3) -> Dictionary:
	var pl: Dictionary
	var ents: Array = []
	var closed_hint := false
	if String(f.get("path", "")) != "":
		var pk := Part.feature(rec, String(f["path"]))
		if pk.is_empty() or String(pk.get("t", "")) != "sketch":
			return {"err": "the path sketch is gone: draw it again, then pick it"}
		ents = pk.get("ents", [])
		pl = pk.get("_pl", Part.resolve_plane(rec, String(pk.get("plane", "front"))))
		if ents.is_empty():
			return {"err": "the path sketch has no lines or curves"}
	else:
		pl = {"o": Vector3.ZERO, "x": Vector3.RIGHT, "n": Vector3.UP}
		pl["y"] = (pl["n"] as Vector3).cross(pl["x"] as Vector3)
		var P3: Array = []
		for q in f.get("pts", []):
			P3.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
		closed_hint = bool(f.get("closed", false))
		if P3.size() < 2:
			return {"err": "the path needs 2 or more points"}
		pl["o"] = Vector3(0.0, (P3[0] as Vector3).y * MM, 0.0)
		for i in P3.size():
			var q3: Vector3 = P3[i]
			ents.append({"k": "line", "a": [q3.x, -q3.z], "b": [(P3[(i + 1) % P3.size()] as Vector3).x, -(P3[(i + 1) % P3.size()] as Vector3).z]})
			if i == P3.size() - 2 and not closed_hint:
				break
	var pcs: Array = []
	for e in ents:
		var why := _pieces_of(e, pcs)
		if why != "":
			return {"err": why}
	var ord := _chain(pcs)
	if ord.is_empty():
		return {"err": "the path pieces do not join end to end"}
	var L := 0.0
	for p in ord:
		p["start"] = L
		L += float(p["len"])
	if L < 1e-6:
		return {"err": "the path has no length"}
	var closed: bool = ((ord[-1]["pb"] as Vector2).distance_to(ord[0]["pa"]) < 1e-3)
	return {"pieces": ord, "len": L, "closed": closed, "pl": pl, "err": ""}


## the plan rectangle (corners, world mm, anticlockwise seen from above) of body bi of the record rec as it stands, grown by grow mm, at height fy mm
## (default the body's lowest face): the "pts" of a route round a slab or a roof eave. {"err", "pts"}
static func footprint_pts(rec: Dictionary, bi: int, grow := 0.0, fy := NAN) -> Dictionary:
	var res := Part.replay(rec, -1, {"keep": true})
	var ids: Array = res.get("ids", [])
	if bi < 0 or bi >= ids.size():
		for b in ids:
			KCad.release(int(b))
		return {"err": "there is no body %d to go round" % (bi + 1), "pts": []}
	var bb := Part._piece_box(int(ids[bi]))
	for b in ids:
		KCad.release(int(b))
	var x0 := bb.position.x / MM - grow
	var x1 := bb.end.x / MM + grow
	var z0 := bb.position.z / MM - grow
	var z1 := bb.end.z / MM + grow
	var y := bb.position.y / MM if is_nan(fy) else fy
	return {"err": "", "pts": [[x0, y, z1], [x1, y, z1], [x1, y, z0], [x0, y, z0]]}


static func _pieces_of(e: Dictionary, pcs: Array) -> String:
	match String(e.get("k", "")):
		"line":
			var a := Part.v2(e["a"])
			var b := Part.v2(e["b"])
			if a.distance_to(b) < 1e-6:
				return "a line of the path has no length"
			pcs.append({"k": "line", "a": a, "b": b, "pa": a, "pb": b, "len": a.distance_to(b)})
		"rect":
			var a := Part.v2(e["a"])
			var b := Part.v2(e["b"])
			var cs := [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]
			for i in 4:
				var p: Vector2 = cs[i]
				var q: Vector2 = cs[(i + 1) % 4]
				if p.distance_to(q) < 1e-6:
					return "a rectangle of the path has no size"
				pcs.append({"k": "line", "a": p, "b": q, "pa": p, "pb": q, "len": p.distance_to(q)})
		"arc":
			var g := Part._arc_geom(Part.v2(e["a"]), Part.v2(e["m"]), Part.v2(e["b"]))
			if g.is_empty():
				return "an arc of the path has no curve (its three points lie on a line)"
			pcs.append(_arc_piece(g["c"], float(g["R"]), float(g["s"]), float(g["ds"])))
		"circle":
			pcs.append(_arc_piece(Part.v2(e["c"]), float(e["r"]), 0.0, TAU))
		"bspline":
			var cur := Part.spline_curve(e.get("pts", []), bool(e.get("closed", false)), 64)
			if cur.size() < 2:
				return "a spline of the path needs two or more points"
			pcs.append(_poly_piece(cur))
		_:
			return "the path takes lines, arcs, splines, rectangles and circles (not %s)" % String(e.get("k", ""))
	return ""


static func _arc_piece(c: Vector2, R: float, s: float, ds: float) -> Dictionary:
	return {"k": "arc", "c": c, "R": R, "s": s, "ds": ds, "pa": c + Vector2(cos(s), sin(s)) * R, "pb": c + Vector2(cos(s + ds), sin(s + ds)) * R, "len": R * absf(ds)}


static func _poly_piece(pts: PackedVector2Array) -> Dictionary:
	var cum := PackedFloat64Array([0.0])
	for i in range(1, pts.size()):
		cum.append(cum[i - 1] + pts[i - 1].distance_to(pts[i]))
	return {"k": "poly", "pts": pts, "cum": cum, "pa": pts[0], "pb": pts[pts.size() - 1], "len": cum[cum.size() - 1]}


static func _flip(p: Dictionary) -> Dictionary:
	var q := p.duplicate()
	q["pa"] = p["pb"]
	q["pb"] = p["pa"]
	match String(p["k"]):
		"line":
			q["a"] = p["b"]
			q["b"] = p["a"]
		"arc":
			return _arc_piece(p["c"], float(p["R"]), float(p["s"]) + float(p["ds"]), -float(p["ds"]))
		"poly":
			var r := PackedVector2Array()
			var src: PackedVector2Array = p["pts"]
			for i in range(src.size() - 1, -1, -1):
				r.append(src[i])
			return _poly_piece(r)
	return q


## the pieces in order, end to end (a piece is turned round when its far end joins). [] when they do not join
static func _chain(pcs: Array) -> Array:
	if pcs.is_empty():
		return []
	var left := pcs.duplicate()
	var ord: Array = [left.pop_front()]
	while not left.is_empty():
		var end: Vector2 = ord[-1]["pb"]
		var hit := -1
		var flip := false
		for i in left.size():
			if (left[i]["pa"] as Vector2).distance_to(end) < 1e-3:
				hit = i
				break
			if (left[i]["pb"] as Vector2).distance_to(end) < 1e-3:
				hit = i
				flip = true
				break
		if hit < 0:
			return []
		var p: Dictionary = left.pop_at(hit)
		ord.append(_flip(p) if flip else p)
	return ord


## the point and the unit travel direction (2D mm) a distance t along piece p
static func _eval(p: Dictionary, t: float) -> Array:
	t = clampf(t, 0.0, float(p["len"]))
	match String(p["k"]):
		"line":
			var d := ((p["b"] as Vector2) - (p["a"] as Vector2)).normalized()
			return [(p["a"] as Vector2) + d * t, d]
		"arc":
			var ds := float(p["ds"])
			var ang := float(p["s"]) + ds * (t / maxf(float(p["len"]), 1e-12))
			var R := float(p["R"])
			var tg := Vector2(-sin(ang), cos(ang)) * signf(ds)
			return [(p["c"] as Vector2) + Vector2(cos(ang), sin(ang)) * R, tg]
		_:
			var cum: PackedFloat64Array = p["cum"]
			var pts: PackedVector2Array = p["pts"]
			var i := 1
			while i < cum.size() - 1 and cum[i] < t:
				i += 1
			var seg := maxf(cum[i] - cum[i - 1], 1e-12)
			var u := clampf((t - cum[i - 1]) / seg, 0.0, 1.0)
			return [pts[i - 1].lerp(pts[i], u), (pts[i] - pts[i - 1]).normalized()]


## the point and the heading at s (mm along the path, wrapped when closed). At a piece boundary where the path turns: the heading is the bisector of the two
static func at(path: Dictionary, s: float) -> Dictionary:
	var pcs: Array = path["pieces"]
	var L := float(path["len"])
	var closed: bool = path["closed"]
	if closed:
		s = fposmod(s, L)
	s = clampf(s, 0.0, L)
	var k := pcs.size() - 1
	for i in pcs.size():
		if s < float(pcs[i]["start"]) + float(pcs[i]["len"]) - 1e-9:
			k = i
			break
	var p: Dictionary = pcs[k]
	var t := s - float(p["start"])
	var e := _eval(p, t)
	var h: Vector2 = e[1]
	var corner := false
	var at_start := t < 1e-7
	var at_end := t > float(p["len"]) - 1e-7
	if at_start or at_end:
		var prev_i := k - 1 if at_start else k
		var next_i := k if at_start else k + 1
		if closed:
			prev_i = (prev_i + pcs.size()) % pcs.size()
			next_i = next_i % pcs.size()
		if prev_i >= 0 and next_i < pcs.size():
			var tin: Vector2 = _eval(pcs[prev_i], float(pcs[prev_i]["len"]))[1]
			var tout: Vector2 = _eval(pcs[next_i], 0.0)[1]
			if tin.dot(tout) < cos(deg_to_rad(0.01)):
				var sum := tin + tout
				h = sum.normalized() if sum.length() > 1e-6 else tout
				corner = tin.dot(tout) < cos(deg_to_rad(CORNER_DEG))
		elif at_start and not closed:
			h = _eval(pcs[0], 0.0)[1]
	return {"p": e[0], "h": h, "corner": corner}


## the distances (mm along the path) of its corners: where two pieces meet at more than CORNER_DEG
static func corner_s(path: Dictionary) -> Array:
	var pcs: Array = path["pieces"]
	var out: Array = []
	var n := pcs.size()
	for i in n:
		var j := i + 1
		if j >= n:
			if not path["closed"]:
				break
			j = 0
		var tin: Vector2 = _eval(pcs[i], float(pcs[i]["len"]))[1]
		var tout: Vector2 = _eval(pcs[j], 0.0)[1]
		if tin.dot(tout) < cos(deg_to_rad(CORNER_DEG)):
			out.append(float(pcs[i]["start"]) + float(pcs[i]["len"]) if j != 0 else 0.0)
	out.sort()
	return out


## the distance along the path of the point nearest to the 2D point q (mm)
static func nearest_s(path: Dictionary, q: Vector2) -> float:
	var L := float(path["len"])
	var n := clampi(int(L / 0.5), 400, 20000)
	var best := 0.0
	var bd := INF
	for i in n + 1:
		var s := L * i / n
		var d: float = (at(path, s)["p"] as Vector2).distance_squared_to(q)
		if d < bd:
			bd = d
			best = s
	var lo := best - L / n
	var hi := best + L / n
	for _it in 60:   # golden-section search for the exact foot of the perpendicular
		var m1 := lo + (hi - lo) * 0.381966
		var m2 := lo + (hi - lo) * 0.618034
		if (at(path, m1)["p"] as Vector2).distance_squared_to(q) < (at(path, m2)["p"] as Vector2).distance_squared_to(q):
			hi = m2
		else:
			lo = m1
	var s_f := (lo + hi) * 0.5
	if (at(path, s_f)["p"] as Vector2).distance_squared_to(q) > bd:
		return best
	return fposmod(s_f, L) if path["closed"] else clampf(s_f, 0.0, L)


# ---------------------------------------------------------------- route: the places

static func _route_slots(rec: Dictionary, f: Dictionary, c: Vector3, slots: Array) -> String:
	var path := path_of(rec, f, c)
	if String(path.get("err", "")) != "":
		return String(path["err"])
	var L := float(path["len"])
	var closed: bool = path["closed"]
	var pl: Dictionary = path["pl"]
	var n3: Vector3 = pl["n"]
	var mm := float(f.get("mm", 0.0))
	var want := int(f.get("count", 0))
	var ss: Array = []   # the distances along the path of the places
	if bool(f.get("corners", false)):
		if mm < 1e-6:
			return "the spacing must not be zero"
		var br: Array = corner_s(path)
		var pts: Array = []
		if closed:
			pts = br.duplicate()
			if pts.is_empty():
				pts = [0.0]
		else:
			pts = [0.0] + br + [L]
		var nruns := pts.size() if closed else pts.size() - 1
		for r in nruns:
			var s0: float = pts[r]
			var s1: float = pts[r + 1] if (r + 1 < pts.size()) else float(pts[0]) + L
			var m := maxi(1, int(roundf((s1 - s0) / mm)))
			for k in m:
				ss.append(s0 + (s1 - s0) * k / m)
		if not closed:
			ss.append(L)
	else:
		var n := 0
		var step := 0.0
		if bool(f.get("fit", false)):
			if want >= 2:
				n = want
			elif mm > 1e-6:
				n = int(roundf(L / mm)) + (0 if closed else 1)
			if n < 2:
				return "fit needs 2 or more copies or a spacing"
			step = L / (n if closed else n - 1)
		else:
			if mm < 1e-6:
				return "the spacing must not be zero"
			step = mm
			n = int(floorf(L / mm + 1e-9)) + (0 if closed else 1)
			if want >= 2:
				n = mini(n, want)
		if n < 2:
			return "the path is shorter than the spacing: lower the spacing, or use a longer path"
		for k in n:
			ss.append(step * k)
	if ss.size() > MAX_COPIES:
		return "%d copies along the path is more than %d: raise the spacing" % [ss.size(), MAX_COPIES]
	# the piece: where it stands on the path, its heading there, and its offset from the path point
	var o3: Vector3 = pl["o"]
	var cl := c - o3
	var q2 := Vector2(cl.dot(pl["x"] as Vector3), cl.dot(pl["y"] as Vector3)) / MM
	var s0 := nearest_s(path, q2)
	var a0 := at(path, s0)
	var h0: Vector2 = a0["h"]
	if bool(a0["corner"]):   # a piece standing on a corner: its heading is the first straight's
		var pcs: Array = path["pieces"]
		var kk := 0
		for i in pcs.size():
			if s0 >= float(pcs[i]["start"]) - 1e-9:
				kk = i
		h0 = _eval(pcs[kk], 0.0)[1] if s0 < L - 1e-9 else _eval(pcs[kk], float(pcs[kk]["len"]))[1]
	var hold := bool(f.get("hold", true))
	var follow := bool(f.get("follow", false)) or bool(f.get("corners", false))
	var off2: Vector2 = (q2 - (a0["p"] as Vector2)) if hold else Vector2.ZERO
	var up_h := cl.dot(n3)   # the piece keeps its own height above the path's plane
	var th0 := h0.angle()
	var off_local := off2.rotated(-th0)   # the offset in the heading's own frame
	var want_hold_h := true
	var first_i := 0
	for i in ss.size():
		var a := at(path, float(ss[i]))
		var hv: Vector2 = a["h"]
		var dth := wrapf(hv.angle() - th0, -PI, PI) if follow else 0.0
		var pos2: Vector2 = a["p"]
		var cen2 := pos2 + (off_local.rotated(th0 + dth) if hold else Vector2.ZERO)
		if not hold:
			cen2 = pos2
		var cw := o3 + (pl["x"] as Vector3) * cen2.x * MM + (pl["y"] as Vector3) * cen2.y * MM + n3 * up_h
		var d := cw - c
		var tw := (pl["x"] as Vector3) * hv.x + (pl["y"] as Vector3) * hv.y
		if d.length() < 1e-6 and absf(dth) < 1e-6:   # within a micron and a micro-radian
			continue   # the original's own place
		slots.append({"i": i, "d": d, "ax": n3, "ang": dth, "sc": 1.0, "t": tw, "corner": bool(a["corner"]), "s": float(ss[i])})
	if want_hold_h and slots.is_empty():
		return "the copies would all sit on the piece itself: move the piece off the path's first place, or change the spacing"
	return ""


# ---------------------------------------------------------------- building the steps from code (a driver, an agent, a test)

## the fields of a Part pattern step "grid": columns (count, mm along dir), rows (mm2 along dir2), layers (mm3 along dir3). Add it with Part.new_feature(rec, "pattern", grid_fields(...))
static func grid_fields(body: int, cols: int, rows: int, mm: float, mm2: float, layers := 1, mm3 := 0.0, extra := {}) -> Dictionary:
	var f := {"kind": "grid", "body": body, "op": "new", "count": cols, "mm": mm, "dir": "x", "rows": rows, "mm2": mm2, "dir2": "z", "layers": layers, "mm3": mm3, "dir3": "y"}
	f.merge(extra, true)
	return f


## the fields of a "route" step along a path sketch (id), a copy every mm (corners: exactly at each corner, each straight run divided evenly; follow: turned with the path)
static func route_fields(body: int, path_sketch: String, mm: float, corners := false, follow := true, extra := {}) -> Dictionary:
	var f := {"kind": "route", "body": body, "op": "new", "path": path_sketch, "mm": mm, "corners": corners, "follow": follow, "hold": true, "fit": false, "count": 0}
	f.merge(extra, true)
	return f


## the fields of a "route" step round the plan outline of body outline_body of the record rec as it stands (a slab, a band, a roof eave), grown by grow mm
## ({} + the reason in "err" when there is no such body). The first copy / piece keeps its distance from the edge
static func round_body_fields(rec: Dictionary, body: int, outline_body: int, mm: float, grow := 0.0, extra := {}) -> Dictionary:
	var fp := footprint_pts(rec, outline_body, grow)
	if String(fp["err"]) != "":
		return {"err": fp["err"]}
	var f := {"kind": "route", "body": body, "op": "new", "pts": fp["pts"], "closed": true, "mm": mm, "corners": true, "follow": true, "hold": true, "fit": false, "count": 0, "fgrow": grow, "fbody": outline_body}
	f.merge(extra, true)
	return f
