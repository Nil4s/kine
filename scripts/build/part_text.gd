extends RefCounted
## FRIDAY 33, TEXT ON A FACE: the outlines of typed words, as plain closed polygons (mm) that Easy Part sketches on a face of the solid and
## then cuts in (engrave) or pulls out (emboss). Pure: no scene, no kernel. The outlines come from Godot's own font (TextServer glyph
## contours: lines and Bezier curves, flattened here), so a letter is real geometry, not a picture.
## A letter with a hole (A, B, D, O, P, Q, R) is ONE polygon: the hole is joined to the outside by a slit SLIT_MM wide (the kernel takes one
## closed loop per letter; a loop inside another loop is refused). The slit is 0.03 mm: far below anything a print or a cutter can show.

const PLabel := preload("res://scripts/build/part_label.gd")   # the Label maker's font-outline code (Friday 210): not duplicated here
const SLIT_MM := 0.03         # the width of the slit that joins a hole to its letter
const MIN_EDGE_MM := 0.02     # two outline points closer than this are one point
const MAX_CHARS := PLabel.MAX_CHARS


## the font's outlines of the text (PartLabel.layout), mm, y up, centred on 0,0: {"ok", "why", "outers", "holes", "bb": Rect2 of the letters}
static func raw(text: String) -> Dictionary:
	var lay: Dictionary = PLabel.layout(text)
	var out := {"ok": false, "why": String(lay["why"]), "outers": [], "holes": [], "bb": Rect2()}
	if not bool(lay["ok"]):
		if text.strip_edges() == "":
			out["why"] = "Type the words first, like KINE"
		return out
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for r in lay["outers"]:
		for p in (r as PackedVector2Array):
			lo = lo.min(p)
			hi = hi.max(p)
	out["ok"] = true
	out["outers"] = lay["outers"]
	out["holes"] = lay["holes"]
	out["bb"] = Rect2(lo, hi - lo)
	return out


## signed area (positive = counter-clockwise, y up)
static func signed_area(r: PackedVector2Array) -> float:
	var a := 0.0
	for i in r.size():
		var p := r[i]
		var q := r[(i + 1) % r.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## the raw outlines scaled by `scale` about `center`, moved by `shift` (mm), mirrored left-right when `mirror` (a face seen from behind),
## cleaned, and merged into ONE polygon per outer outline (holes joined by a slit). Counter-clockwise
static func polygons(rw: Dictionary, scale: float, center: Vector2, shift: Vector2, mirror: bool, turn := false) -> Array:
	var r := rings(rw, scale, center, shift, mirror, turn)
	return _attach(r[0], r[1])


## s234: the same cleaned outlines, NOT joined: [outers (counter-clockwise), holes (clockwise)]. A sketch may hold a hole inside its outline now.
static func rings(rw: Dictionary, scale: float, center: Vector2, shift: Vector2, mirror: bool, turn := false) -> Array:
	var outers: Array = []
	var holes: Array = []
	for kind in ["outers", "holes"]:
		for r in rw[kind]:
			var ring := PackedVector2Array()
			for p in (r as PackedVector2Array):
				var q := (p - center) * scale
				if turn:
					q = Vector2(-q.y, q.x)   # a quarter turn: the words run along the face's long side when that is the plane's v
				if mirror:
					q.x = -q.x
				q += shift
				if ring.is_empty() or ring[ring.size() - 1].distance_to(q) >= MIN_EDGE_MM:
					ring.append(q)
			while ring.size() > 1 and ring[0].distance_to(ring[ring.size() - 1]) < MIN_EDGE_MM:
				ring.remove_at(ring.size() - 1)
			if ring.size() < 3 or absf(signed_area(ring)) < 1e-4:
				continue
			if kind == "outers":
				if signed_area(ring) < 0.0:
					ring.reverse()
				outers.append(ring)
			else:
				if signed_area(ring) > 0.0:
					ring.reverse()
				holes.append(ring)   # clockwise
	return [outers, holes]


## s234: text as a PART: ONE sketch of every outline (outer loops and the holes inside them, e.g. the counters of 殿) and ONE extrude, a real solid.
## The letters are `height` mm tall (the line's height, glyph box), `depth` mm thick, centred on the floor origin. {"ok", "why", "rec", "holes", "outers"}
static func part_record(text: String, height: float, depth: float) -> Dictionary:
	var rw := raw(text)
	if not bool(rw["ok"]):
		return {"ok": false, "why": String(rw["why"])}
	var bb: Rect2 = rw["bb"]
	var r := rings(rw, height / maxf(bb.size.y, 0.001), bb.get_center(), Vector2.ZERO, false)
	var all: Array = (r[0] as Array) + (r[1] as Array)
	var rec := Part.make("Text")
	var sk := Part.new_feature(rec, "sketch", {"plane": "top", "ents": ents_of(all), "dims": []})
	rec["features"].append(sk)
	var ex := Part.new_feature(rec, "extrude", {"sketch": sk["id"], "dist": depth, "both": false, "op": "new"})
	rec["features"].append(ex)
	rec["text"] = {"text": text, "height": height, "depth": depth}
	return {"ok": true, "why": "", "rec": rec, "holes": (r[1] as Array).size(), "outers": (r[0] as Array).size()}


## each hole joined into the smallest outline that holds it
static func _attach(outers: Array, holes: Array) -> Array:
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
