extends RefCounted
## s210 LABEL MAKER (Friday plan 210): a flat tag with a word on it, from the Parts library (Type it page). The tag's size comes from the word.
## The letters are the font's own outlines (TextServer.font_get_glyph_contours), flattened to straight lines, so any word works, not a dot font.
## Raised: the letters stand 1 mm proud of a 2 mm tag. Cut in: the letters are cut 1.2 mm into a 3 mm tag. Either way ONE solid, in 6 steps
## (the tag's sketch + pull, the letters' sketch + pull, the holes of B, O, A... sketch + pull) however long the word is.
## Sketch coordinates are mm on the floor plane: u = x, v = -z (glyph up is +v), the word centred on the origin.

const CAP_MM := 8.0      # capital letter height
const MARGIN := 3.0      # mm of tag round the letters
const TAG_T := 2.0       # raised: tag thickness
const RAISE := 1.0       # raised: how far the letters stand proud
const CUT_T := 3.0       # cut in: tag thickness
const CUT_D := 1.2       # cut in: how deep the letters go
const SEG := 5           # straight pieces per curve piece of a letter
const FONT_PX := 64
const MAX_CHARS := 24
const MIN_W := 12.0
const DEDUP := 0.03      # mm: points closer than this are one point


## the tag's width and height (mm) for a word, plus the letters' polygons: {"ok", "why", "outers": [PackedVector2Array], "holes": [...], "w", "h"}
static func layout(text: String) -> Dictionary:
	var out := {"ok": false, "why": "", "outers": [], "holes": [], "w": 0.0, "h": 0.0}
	if text.strip_edges() == "":
		out["why"] = "Type a word for the label first, like BOLTS"
		return out
	if text.length() > MAX_CHARS:
		out["why"] = "That word is too long for a label: %d letters at most" % MAX_CHARS
		return out
	var font: Font = ThemeDB.fallback_font
	var ts := TextServerManager.get_primary_interface()
	if font == null or ts == null or font.get_rids().is_empty():
		out["why"] = "No font to draw the letters with"
		return out
	var rid: RID = font.get_rids()[0]
	var cap_px := 0.0
	var hc: Dictionary = ts.font_get_glyph_contours(rid, FONT_PX, ts.font_get_glyph_index(rid, FONT_PX, ord("H"), 0))
	for p in hc.get("points", PackedVector3Array()):
		cap_px = maxf(cap_px, -p.y)
	if cap_px < 1.0:
		cap_px = FONT_PX * 0.7
	var sc := CAP_MM / cap_px
	var polys: Array = []   # [PackedVector2Array, signed area]
	var pen := 0.0
	for ch in text:
		var gi := ts.font_get_glyph_index(rid, FONT_PX, ord(ch), 0)
		var c: Dictionary = ts.font_get_glyph_contours(rid, FONT_PX, gi)
		var pts: PackedVector3Array = c.get("points", PackedVector3Array())
		var ends: PackedInt32Array = c.get("contours", PackedInt32Array())
		var a := 0
		for e in ends:
			var poly := _flatten(pts.slice(a, e + 1), pen, sc)
			a = e + 1
			if poly.size() >= 3:
				polys.append([poly, _area(poly)])
		pen += ts.font_get_glyph_advance(rid, FONT_PX, gi).x
	if polys.is_empty():
		out["why"] = "Those letters have no outline to make a label from: type letters or numbers"
		return out
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var big := 0.0
	var big_sign := 1.0
	for q in polys:
		for v in (q[0] as PackedVector2Array):
			lo = lo.min(v)
			hi = hi.max(v)
		if absf(float(q[1])) > big:
			big = absf(float(q[1]))
			big_sign = signf(float(q[1]))
	var mid := (lo + hi) * 0.5
	for q in polys:
		var poly: PackedVector2Array = q[0]
		for i in poly.size():
			poly[i] -= mid
		if signf(float(q[1])) == big_sign:
			(out["outers"] as Array).append(poly)
		else:
			(out["holes"] as Array).append(poly)
	out["w"] = maxf(hi.x - lo.x + 2.0 * MARGIN, MIN_W)
	out["h"] = maxf(hi.y - lo.y, CAP_MM) + 2.0 * MARGIN
	out["ok"] = true
	return out


## one glyph contour (font pixels, y down, z = 1 on the curve / 0 quadratic control / 3 cubic control) as a closed polygon in mm, y up
static func _flatten(src: PackedVector3Array, pen: float, sc: float) -> PackedVector2Array:
	var n := src.size()
	var res := PackedVector2Array()
	if n < 3:
		return res
	var P: Array = []
	var T: Array = []
	for v in src:
		P.append(Vector2(v.x, v.y))
		T.append(int(v.z))
	var k := T.find(1)
	if k < 0:   # every point is a control: start at the middle of the first two
		P.insert(0, (P[0] + P[-1]) * 0.5)
		T.insert(0, 1)
	elif k > 0:
		P = P.slice(k) + P.slice(0, k)
		T = T.slice(k) + T.slice(0, k)
	P.append(P[0])
	T.append(1)
	var pts: Array = [P[0]]
	var cur: Vector2 = P[0]
	var i := 1
	while i < P.size():
		if int(T[i]) == 1:
			pts.append(P[i])
			cur = P[i]
			i += 1
		elif int(T[i]) == 0:
			var ctrl: Vector2 = P[i]
			var nxt: Vector2 = P[i + 1]
			var end: Vector2 = nxt
			if int(T[i + 1]) == 1:
				i += 2
			else:
				end = (ctrl + nxt) * 0.5
				i += 1
			for s in range(1, SEG + 1):
				var t := float(s) / SEG
				pts.append(cur * (1.0 - t) * (1.0 - t) + ctrl * 2.0 * (1.0 - t) * t + end * t * t)
			cur = end
		else:
			if i + 2 >= P.size():
				break
			var c1: Vector2 = P[i]
			var c2: Vector2 = P[i + 1]
			var end3: Vector2 = P[i + 2]
			for s in range(1, SEG + 1):
				var t := float(s) / SEG
				var u := 1.0 - t
				pts.append(cur * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + end3 * t * t * t)
			cur = end3
			i += 3
	pts.pop_back()   # the closing point is the first one again
	var last := Vector2(INF, INF)
	for p in pts:
		var m := Vector2((pen + p.x) * sc, -p.y * sc)
		if m.distance_to(last) >= DEDUP:
			res.append(m)
			last = m
	while res.size() > 1 and res[0].distance_to(res[-1]) < DEDUP:
		res.remove_at(res.size() - 1)
	return res


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


static func _lines(polys: Array) -> Array:
	var ents: Array = []
	for poly in polys:
		var pp: PackedVector2Array = poly
		for i in pp.size():
			ents.append({"k": "line", "a": Part.arr2(pp[i]), "b": Part.arr2(pp[(i + 1) % pp.size()])})
	return ents


## the label as a part record, or {"ok": false, "why"}. cut: the letters are cut into the tag; else they stand proud of it
static func build(text: String, cut: bool) -> Dictionary:
	var lay := layout(text)
	if not bool(lay["ok"]):
		return lay
	var w: float = lay["w"]
	var h: float = lay["h"]
	var T := CUT_T if cut else TAG_T
	var rec := Part.make("Label")
	var s0 := Part.new_feature(rec, "sketch", {"plane": "top", "ents": [{"k": "rect", "a": Part.arr2(Vector2(-w * 0.5, -h * 0.5)), "b": Part.arr2(Vector2(w * 0.5, h * 0.5))}], "dims": []})
	rec["features"].append(s0)
	var e0 := Part.new_feature(rec, "extrude", {"sketch": s0["id"], "dist": T, "both": false, "op": "new"})
	rec["features"].append(e0)
	var outers: Array = lay["outers"]
	var holes: Array = lay["holes"]
	if not cut:
		var p1 := Part.new_feature(rec, "plane", {"from": "top", "mm": T - 0.2})
		rec["features"].append(p1)
		var sa := Part.new_feature(rec, "sketch", {"plane": String(p1["id"]), "ents": _lines(outers), "dims": []})
		rec["features"].append(sa)
		var ea := Part.new_feature(rec, "extrude", {"sketch": sa["id"], "dist": RAISE + 0.2, "both": false, "op": "join", "into": 0})
		rec["features"].append(ea)
		if not holes.is_empty():
			var p2 := Part.new_feature(rec, "plane", {"from": "top", "mm": T})
			rec["features"].append(p2)
			var sb := Part.new_feature(rec, "sketch", {"plane": String(p2["id"]), "ents": _lines(holes), "dims": []})
			rec["features"].append(sb)
			var eb := Part.new_feature(rec, "extrude", {"sketch": sb["id"], "dist": RAISE + 0.2, "both": false, "op": "cut"})
			rec["features"].append(eb)
	else:
		var p1 := Part.new_feature(rec, "plane", {"from": "top", "mm": T - CUT_D})
		rec["features"].append(p1)
		var sa := Part.new_feature(rec, "sketch", {"plane": String(p1["id"]), "ents": _lines(outers), "dims": []})
		rec["features"].append(sa)
		var ea := Part.new_feature(rec, "extrude", {"sketch": sa["id"], "dist": CUT_D + 0.5, "both": false, "op": "cut"})
		rec["features"].append(ea)
		if not holes.is_empty():   # the middle of an O or a B stays: it is joined back, from the cut's floor
			var p2 := Part.new_feature(rec, "plane", {"from": "top", "mm": T - CUT_D - 0.2})
			rec["features"].append(p2)
			var sb := Part.new_feature(rec, "sketch", {"plane": String(p2["id"]), "ents": _lines(holes), "dims": []})
			rec["features"].append(sb)
			var eb := Part.new_feature(rec, "extrude", {"sketch": sb["id"], "dist": CUT_D + 0.2, "both": false, "op": "join", "into": 0})
			rec["features"].append(eb)
	rec["label"] = {"text": text, "cut": cut, "w": w, "h": h}
	return {"ok": true, "why": "", "rec": rec, "w": w, "h": h}
