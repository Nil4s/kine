extends RefCounted
## FRIDAY 33, TEXT ON A FACE: the outlines of typed words, as plain closed polygons (mm) that Easy Part sketches on a face of the solid and
## then cuts in (engrave) or pulls out (emboss). Pure: no scene, no kernel. The outlines come from Godot's own font (TextServer glyph
## contours: lines and Bezier curves, flattened here), so a letter is real geometry, not a picture.
## A letter with a hole (A, B, D, O, P, Q, R) is ONE polygon: the hole is joined to the outside by a slit SLIT_MM wide (the kernel takes one
## closed loop per letter; a loop inside another loop is refused). The slit is 0.03 mm: far below anything a print or a cutter can show.

const FONT_SIZE := 100        # the size the glyph contours are read at (font units are then scaled, so this only sets the curve detail)
const CURVE_STEPS := 8        # straight pieces per Bezier curve
const SLIT_MM := 0.03         # the width of the slit that joins a hole to its letter
const MIN_EDGE_MM := 0.02     # two outline points closer than this are one point
const MAX_CHARS := 24


## the font's contours of the text, in font units, y up, pen moving right: {"ok", "why", "glyphs": [[ring, ...] per letter], "bb": Rect2}
static func raw(text: String) -> Dictionary:
	var t := text.strip_edges()
	var out := {"ok": false, "why": "", "glyphs": [], "bb": Rect2()}
	if t == "":
		out["why"] = "Type the words first, like KINE"
		return out
	if t.length() > MAX_CHARS:
		out["why"] = "That is too long: use %d letters or fewer" % MAX_CHARS
		return out
	var f: Font = ThemeDB.fallback_font
	if f == null or f.get_rids().is_empty():
		out["why"] = "No font is available to draw the letters"
		return out
	var ts := TextServerManager.get_primary_interface()
	var rid: RID = f.get_rids()[0]
	var pen := 0.0
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var glyphs: Array = []
	for i in t.length():
		var cp := t.unicode_at(i)
		var gi := ts.font_get_glyph_index(rid, FONT_SIZE, cp, 0)
		if cp != 32 and gi == 0:
			out["why"] = "The letter \"%s\" is not in the font: use letters, numbers and simple marks" % t[i]
			return out
		var adv := ts.font_get_glyph_advance(rid, FONT_SIZE, gi).x
		if cp != 32:
			var d: Dictionary = ts.font_get_glyph_contours(rid, FONT_SIZE, gi)
			var rings: Array = _rings(d.get("points", PackedVector3Array()), d.get("contours", PackedInt32Array()))
			var moved: Array = []
			for r in rings:
				var ring := PackedVector2Array()
				for p in (r as PackedVector2Array):
					var q := p + Vector2(pen, 0.0)
					ring.append(q)
					lo = lo.min(q)
					hi = hi.max(q)
				moved.append(ring)
			if not moved.is_empty():
				glyphs.append(moved)
		pen += adv
	if glyphs.is_empty():
		out["why"] = "There is nothing to draw in those words"
		return out
	out["ok"] = true
	out["glyphs"] = glyphs
	out["bb"] = Rect2(lo, hi - lo)
	return out


## the glyph's points -> one flattened ring per contour (font y is down: flipped to y up)
static func _rings(pts: PackedVector3Array, ends: PackedInt32Array) -> Array:
	var rings: Array = []
	var start := 0
	for e in ends:
		var seg: Array = []
		for k in range(start, int(e) + 1):
			seg.append(pts[k])
		start = int(e) + 1
		if seg.size() >= 3:
			var r := _flatten(seg)
			if r.size() >= 3:
				rings.append(r)
	return rings


static func _flatten(seg: Array) -> PackedVector2Array:
	# start on an on-curve point
	var first := -1
	for k in seg.size():
		if (seg[k] as Vector3).z > 0.5:
			first = k
			break
	var s: Array = []
	if first < 0:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		s.append(Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, 1.0))
		for k in range(1, seg.size()):
			s.append(seg[k])
		s.append(seg[0])
	else:
		for k in seg.size():
			s.append(seg[(first + k) % seg.size()])
	s.append(s[0])
	var out := PackedVector2Array()
	var cur := _v(s[0])
	out.append(cur)
	var i := 1
	while i < s.size():
		var pi: Vector3 = s[i]
		if pi.z > 0.5:
			cur = _v(pi)
			out.append(cur)
			i += 1
			continue
		var run: Array = []
		while i < s.size() and (s[i] as Vector3).z <= 0.5:
			run.append(_v(s[i]))
			i += 1
		var end: Vector2 = _v(s[i])
		if run.size() == 2:
			for st in range(1, CURVE_STEPS + 1):
				out.append(_cubic(cur, run[0], run[1], end, float(st) / CURVE_STEPS))
		else:
			for q in run.size():
				var tgt: Vector2 = end if q == run.size() - 1 else ((run[q] as Vector2) + (run[q + 1] as Vector2)) * 0.5
				for st in range(1, CURVE_STEPS + 1):
					out.append(_quad(cur, run[q], tgt, float(st) / CURVE_STEPS))
				cur = tgt
		cur = end
		i += 1
	out.remove_at(out.size() - 1)   # the closing point is the first one again
	return out


static func _v(p: Vector3) -> Vector2:
	return Vector2(p.x, -p.y)


static func _quad(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	return a.lerp(c, t).lerp(c.lerp(b, t), t)


static func _cubic(a: Vector2, c1: Vector2, c2: Vector2, b: Vector2, t: float) -> Vector2:
	var ab := a.lerp(c1, t)
	var bc := c1.lerp(c2, t)
	var cd := c2.lerp(b, t)
	return ab.lerp(bc, t).lerp(bc.lerp(cd, t), t)


## signed area (positive = counter-clockwise, y up)
static func signed_area(r: PackedVector2Array) -> float:
	var a := 0.0
	for i in r.size():
		var p := r[i]
		var q := r[(i + 1) % r.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## the raw outlines scaled by `scale` (mm per font unit) about `center` (font units), moved by `shift` (mm), mirrored left-right when
## `mirror` (a face seen from behind), cleaned, and merged into ONE polygon per outer outline (holes joined by a slit). Counter-clockwise
static func polygons(rw: Dictionary, scale: float, center: Vector2, shift: Vector2, mirror: bool) -> Array:
	var polys: Array = []
	for g in rw["glyphs"]:
		var rings: Array = []
		for r in (g as Array):
			var ring := PackedVector2Array()
			for p in (r as PackedVector2Array):
				var q := (p - center) * scale
				if mirror:
					q.x = -q.x
				q += shift
				if ring.is_empty() or ring[ring.size() - 1].distance_to(q) >= MIN_EDGE_MM:
					ring.append(q)
			while ring.size() > 1 and ring[0].distance_to(ring[ring.size() - 1]) < MIN_EDGE_MM:
				ring.remove_at(ring.size() - 1)
			if ring.size() >= 3 and absf(signed_area(ring)) > 1e-4:
				rings.append(ring)
		polys.append_array(_merge_glyph(rings))
	return polys


## one letter's rings -> polygons: the rings turning the way of the biggest are outlines, the others holes (each joined into the outline
## that holds it)
static func _merge_glyph(rings: Array) -> Array:
	if rings.is_empty():
		return []
	var big := 0.0
	for r in rings:
		if absf(signed_area(r)) > absf(big):
			big = signed_area(r)
	var outers: Array = []
	var holes: Array = []
	for r in rings:
		var rr: PackedVector2Array = r
		var ccw := signed_area(rr) > 0.0
		if (signed_area(rr) > 0.0) == (big > 0.0):
			if not ccw:
				rr.reverse()
			outers.append(rr)
		else:
			if ccw:
				rr.reverse()
			holes.append(rr)   # clockwise
	var mine: Array = []
	for o in outers:
		mine.append([])
	for h in holes:
		var best := -1
		var best_a := INF
		for k in outers.size():
			if Geometry2D.is_point_in_polygon((h as PackedVector2Array)[0], outers[k]) and absf(signed_area(outers[k])) < best_a:
				best = k
				best_a = absf(signed_area(outers[k]))
		if best >= 0:
			(mine[best] as Array).append(h)
	var out: Array = []
	for k in outers.size():
		var ring: PackedVector2Array = outers[k]
		var hs: Array = mine[k]
		for hi in hs.size():
			var others: Array = []
			for hj in range(hi + 1, hs.size()):
				others.append(hs[hj])
			ring = _join(ring, hs[hi], others)
		out.append(ring)
	return out


## the hole joined to the outline by the shortest bridge that crosses no edge (and the slit SLIT_MM wide)
static func _join(ring: PackedVector2Array, hole: PackedVector2Array, others: Array) -> PackedVector2Array:
	var cands: Array = []
	for i in ring.size():
		for j in hole.size():
			cands.append([ring[i].distance_squared_to(hole[j]), i, j])
	cands.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var edges: Array = []   # [a, b] pairs of every edge that can block a bridge
	for k in ring.size():
		edges.append([ring[k], ring[(k + 1) % ring.size()]])
	for k in hole.size():
		edges.append([hole[k], hole[(k + 1) % hole.size()]])
	for oh in others:
		for k in (oh as PackedVector2Array).size():
			edges.append([oh[k], oh[(k + 1) % (oh as PackedVector2Array).size()]])
	var pick := [-1, -1]
	var tries := 0
	for c in cands:
		tries += 1
		if tries > 4000:
			break
		var a: Vector2 = ring[int(c[1])]
		var b: Vector2 = hole[int(c[2])]
		if _clear(a, b, edges) and Geometry2D.is_point_in_polygon((a + b) * 0.5, ring) and not Geometry2D.is_point_in_polygon((a + b) * 0.5, hole):
			pick = [int(c[1]), int(c[2])]
			break
	if int(pick[0]) < 0:
		return ring   # no bridge found: the hole is left out (the letter fills in), never an invalid polygon
	var o: Vector2 = ring[int(pick[0])]
	var h: Vector2 = hole[int(pick[1])]
	var dir := (h - o).normalized()
	var shift := Vector2(dir.y, -dir.x) * SLIT_MM   # to the right of the bridge: the slit lies outside the letter
	var res := PackedVector2Array()
	for k in range(0, int(pick[0]) + 1):
		res.append(ring[k])
	for k in hole.size():
		res.append(hole[(int(pick[1]) + k) % hole.size()])
	res.append(h + shift)
	res.append(o + shift)
	for k in range(int(pick[0]) + 1, ring.size()):
		res.append(ring[k])
	return res


## true when the segment a-b properly crosses none of the edges (an edge that touches a or b is not a crossing)
static func _clear(a: Vector2, b: Vector2, edges: Array) -> bool:
	for e in edges:
		var p: Vector2 = e[0]
		var q: Vector2 = e[1]
		if p.distance_to(a) < 1e-6 or p.distance_to(b) < 1e-6 or q.distance_to(a) < 1e-6 or q.distance_to(b) < 1e-6:
			continue
		var x: Variant = Geometry2D.segment_intersects_segment(a, b, p, q)
		if x != null:
			return false
	return true


## the polygons as sketch line entities (mm), each closed
static func ents_of(polys: Array) -> Array:
	var ents: Array = []
	for p in polys:
		var pp: PackedVector2Array = p
		for i in pp.size():
			var a := pp[i]
			var b := pp[(i + 1) % pp.size()]
			ents.append({"k": "line", "a": [snappedf(a.x, 0.0001), snappedf(a.y, 0.0001)], "b": [snappedf(b.x, 0.0001), snappedf(b.y, 0.0001)]})
	return ents


## the area of the polygons (mm2)
static func area_of(polys: Array) -> float:
	var s := 0.0
	for p in polys:
		s += absf(signed_area(p))
	return s
