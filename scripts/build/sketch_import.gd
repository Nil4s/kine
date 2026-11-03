extends RefCounted
## C53 (M #220): an SVG or DXF (R12 ASCII and later) read into Part sketch entities, in mm. Own parser, no outside code.
## parse(ext, text) -> {"ents": [sketch entities], "unsupported": ["text x1", ...], "notes": [...], "units": "words", "source_count": N}
##  - SVG: rect, circle, line, polyline, polygon, path (M L H V C S Q T A Z, upper and lower case), nested transforms.
##    Size: width/height with units + viewBox -> the viewBox is scaled to that width; otherwise a user unit is a px at 96 dpi (25.4/96 mm).
##    The y axis is flipped so the sketch is the right way up. Curves (C S Q T) and elliptical arcs become short lines (in "notes").
##    Listed as unsupported, never dropped silently: text, image, ellipse, use, foreignObject, and any DXF entity this does not read.
##  - DXF: LINE, ARC, CIRCLE, LWPOLYLINE (with bulges), POLYLINE/VERTEX. Units from $INSUNITS (none = mm, said in "units").
## Sketch entities are {"k": "line"|"rect"|"circle"|"arc", ...} exactly as Part draws them.

const FLAT := 16   # lines per flattened curve
const SVG_NOT_DRAWN := ["defs", "clipPath", "mask", "symbol", "pattern", "marker", "metadata", "title", "desc", "style", "script"]
const SVG_UNSUPPORTED := ["text", "image", "ellipse", "use", "foreignObject", "switch"]


static func parse(ext: String, text: String) -> Dictionary:
	var out := {"ents": [], "unsupported": [], "notes": [], "units": "", "source_count": 0}
	match ext.to_lower().trim_prefix("."):
		"svg":
			_svg(text, out)
		"dxf":
			_dxf(text, out)
		_:
			out["unsupported"].append("file type .%s (only .svg and .dxf)" % ext)
	return out


static func _count_words(counts: Dictionary) -> Array:
	var w := []
	for k in counts:
		w.append("%s x%d" % [k, counts[k]])
	return w


static func _line(ents: Array, a: Vector2, b: Vector2) -> void:
	if a.distance_to(b) > 1e-6:
		ents.append({"k": "line", "a": [a.x, a.y], "b": [b.x, b.y]})


static func _arc_mid_ents(ents: Array, a: Vector2, m: Vector2, b: Vector2) -> void:
	ents.append({"k": "arc", "a": [a.x, a.y], "m": [m.x, m.y], "b": [b.x, b.y]})


# ---------------------------------------------------------------- SVG

static func _length(s: String) -> Vector2:   # (mm, 1 if it had a real unit else 0); (-1, 0) = none
	s = s.strip_edges()
	if s == "" or s.ends_with("%"):
		return Vector2(-1.0, 0.0)
	var rx := RegEx.new()
	rx.compile("^([-+]?[0-9]*\\.?[0-9]+(?:[eE][-+]?[0-9]+)?)\\s*([a-zA-Z]*)$")
	var mt := rx.search(s)
	if mt == null:
		return Vector2(-1.0, 0.0)
	var v := float(mt.get_string(1))
	match mt.get_string(2).to_lower():
		"mm":
			return Vector2(v, 1.0)
		"cm":
			return Vector2(v * 10.0, 1.0)
		"in":
			return Vector2(v * 25.4, 1.0)
		"pt":
			return Vector2(v * 25.4 / 72.0, 1.0)
		"pc":
			return Vector2(v * 25.4 / 6.0, 1.0)
		"q":
			return Vector2(v * 0.25, 1.0)
		_:
			return Vector2(v * 25.4 / 96.0, 1.0)   # px or none


static func _nums(s: String) -> PackedFloat64Array:
	var rx := RegEx.new()
	rx.compile("[-+]?(?:[0-9]*\\.[0-9]+|[0-9]+\\.?)(?:[eE][-+]?[0-9]+)?")
	var r := PackedFloat64Array()
	for mt in rx.search_all(s):
		r.append(float(mt.get_string()))
	return r


static func _transform(s: String) -> Transform2D:
	var t := Transform2D.IDENTITY
	var rx := RegEx.new()
	rx.compile("([a-zA-Z]+)\\s*\\(([^)]*)\\)")
	for mt in rx.search_all(s):
		var n := _nums(mt.get_string(2))
		var o := Transform2D.IDENTITY
		match mt.get_string(1):
			"translate":
				if n.size() >= 1:
					o = Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(n[0], n[1] if n.size() > 1 else 0.0))
			"scale":
				if n.size() >= 1:
					o = Transform2D(Vector2(n[0], 0), Vector2(0, n[1] if n.size() > 1 else n[0]), Vector2.ZERO)
			"rotate":
				if n.size() >= 1:
					var a := deg_to_rad(n[0])
					var c := Vector2(n[1], n[2]) if n.size() >= 3 else Vector2.ZERO
					var r := Transform2D(Vector2(cos(a), sin(a)), Vector2(-sin(a), cos(a)), Vector2.ZERO)
					o = Transform2D(Vector2(1, 0), Vector2(0, 1), c) * r * Transform2D(Vector2(1, 0), Vector2(0, 1), -c)
			"matrix":
				if n.size() >= 6:
					o = Transform2D(Vector2(n[0], n[1]), Vector2(n[2], n[3]), Vector2(n[4], n[5]))
			"skewX":
				if n.size() >= 1:
					o = Transform2D(Vector2(1, 0), Vector2(tan(deg_to_rad(n[0])), 1), Vector2.ZERO)
			"skewY":
				if n.size() >= 1:
					o = Transform2D(Vector2(1, tan(deg_to_rad(n[0]))), Vector2(0, 1), Vector2.ZERO)
		t = t * o
	return t


static func _svg(text: String, out: Dictionary) -> void:
	var xp := XMLParser.new()
	if xp.open_buffer(text.to_utf8_buffer()) != OK:
		out["unsupported"].append("file (not readable as XML)")
		return
	var ents: Array = out["ents"]
	var unsup := {}
	var stack: Array = [Transform2D.IDENTITY]
	var skip_depth := 0   # inside a <defs> etc. or a <text>: nothing is drawn
	var depth_stack: Array = []   # per open element: true when it started a skip
	var scale := 25.4 / 96.0
	var vb := Rect2()
	var has_vb := false
	var H := 0.0
	var have_root := false
	while xp.read() == OK:
		var nt := xp.get_node_type()
		if nt == XMLParser.NODE_ELEMENT:
			var nm := xp.get_node_name().get_slice(":", xp.get_node_name().get_slice_count(":") - 1)
			var empty := xp.is_empty()
			var tr: Transform2D = stack[-1]
			if xp.has_attribute("transform"):
				tr = tr * _transform(xp.get_named_attribute_value("transform"))
			if nm == "svg" and not have_root:
				have_root = true
				var w := _length(xp.get_named_attribute_value_safe("width"))
				var h := _length(xp.get_named_attribute_value_safe("height"))
				if xp.has_attribute("viewBox"):
					var v := _nums(xp.get_named_attribute_value("viewBox"))
					if v.size() == 4 and v[2] > 0.0 and v[3] > 0.0:
						vb = Rect2(v[0], v[1], v[2], v[3])
						has_vb = true
				if has_vb and w.x > 0.0:
					scale = w.x / vb.size.x
					out["units"] = "SVG viewBox scaled to its width of %s mm (1 unit = %s mm)" % [snappedf(w.x, 0.001), snappedf(scale, 0.0001)]
				elif has_vb:
					out["units"] = "SVG viewBox units taken as px at 96 dpi (1 unit = 0.2646 mm)"
				else:
					out["units"] = "SVG user units are px at 96 dpi (1 px = 0.2646 mm)"
				if has_vb:
					H = vb.size.y * scale
				elif h.x > 0.0:
					H = h.x
				stack.append(Transform2D.IDENTITY)   # the root's own transform is not used; the stack entry keeps depth in step
				depth_stack.append(false)
				if empty:
					stack.pop_back()
					depth_stack.pop_back()
				continue
			var starts_skip := false
			if skip_depth == 0:
				if nm in SVG_NOT_DRAWN:
					starts_skip = true
				elif nm in SVG_UNSUPPORTED:
					unsup[nm] = int(unsup.get(nm, 0)) + 1
					starts_skip = true   # a <text>'s children (tspan) are the same unsupported thing
				else:
					_svg_shape(xp, nm, tr, scale, vb if has_vb else Rect2(), H, ents, unsup, out)
			if empty:
				continue
			stack.append(tr)
			depth_stack.append(starts_skip)
			if starts_skip:
				skip_depth += 1
		elif nt == XMLParser.NODE_ELEMENT_END:
			if stack.size() > 1:
				stack.pop_back()
			if depth_stack.size() > 0 and depth_stack.pop_back():
				skip_depth -= 1
	out["unsupported"] = _count_words(unsup)


# a point in the file -> mm on the sketch (y up)
static func _pt(p: Vector2, tr: Transform2D, scale: float, vb: Rect2, H: float) -> Vector2:
	var q := tr * p
	q -= vb.position
	return Vector2(q.x * scale, H - q.y * scale)


static func _svg_shape(xp: XMLParser, nm: String, tr: Transform2D, scale: float, vb: Rect2, H: float, ents: Array, unsup: Dictionary, out: Dictionary) -> void:
	var f := func(a: String, d := 0.0) -> float:
		return float(xp.get_named_attribute_value_safe(a)) if xp.has_attribute(a) else d
	var P := func(p: Vector2) -> Vector2:
		return _pt(p, tr, scale, vb, H)
	match nm:
		"rect":
			var x: float = f.call("x")
			var y: float = f.call("y")
			var w: float = f.call("width")
			var h: float = f.call("height")
			if w <= 0.0 or h <= 0.0:
				return
			out["source_count"] += 1
			if f.call("rx") > 0.0 or f.call("ry") > 0.0:
				unsup["rect corner radius (imported with square corners)"] = int(unsup.get("rect corner radius (imported with square corners)", 0)) + 1
			if absf(tr.x.y) < 1e-9 and absf(tr.y.x) < 1e-9:
				var a: Vector2 = P.call(Vector2(x, y))
				var b: Vector2 = P.call(Vector2(x + w, y + h))
				ents.append({"k": "rect", "a": [a.x, a.y], "b": [b.x, b.y]})
			else:
				var c := [Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]
				for i in 4:
					_line(ents, P.call(c[i]), P.call(c[(i + 1) % 4]))
		"circle":
			var r: float = f.call("r")
			if r <= 0.0:
				return
			out["source_count"] += 1
			var lx := tr.x.length()
			var ly := tr.y.length()
			if absf(lx - ly) > 1e-6 * maxf(lx, ly) or absf(tr.x.dot(tr.y)) > 1e-6 * lx * ly:
				unsup["circle under a non-uniform scale (an ellipse)"] = int(unsup.get("circle under a non-uniform scale (an ellipse)", 0)) + 1
				return
			var c: Vector2 = P.call(Vector2(f.call("cx"), f.call("cy")))
			ents.append({"k": "circle", "c": [c.x, c.y], "r": r * lx * scale})
		"line":
			out["source_count"] += 1
			_line(ents, P.call(Vector2(f.call("x1"), f.call("y1"))), P.call(Vector2(f.call("x2"), f.call("y2"))))
		"polyline", "polygon":
			var n := _nums(xp.get_named_attribute_value_safe("points"))
			var pts := []
			for i in range(0, n.size() - 1, 2):
				pts.append(P.call(Vector2(n[i], n[i + 1])))
			if pts.size() < 2:
				return
			out["source_count"] += 1
			for i in pts.size() - 1:
				_line(ents, pts[i], pts[i + 1])
			if nm == "polygon":
				_line(ents, pts[-1], pts[0])
		"path":
			out["source_count"] += 1
			_svg_path(xp.get_named_attribute_value_safe("d"), P, ents, out)


static func _svg_path(d: String, P: Callable, ents: Array, out: Dictionary) -> void:
	var rx := RegEx.new()
	rx.compile("[A-Za-z]|[-+]?(?:[0-9]*\\.[0-9]+|[0-9]+\\.?)(?:[eE][-+]?[0-9]+)?")
	var tok := []
	for mt in rx.search_all(d):
		tok.append(mt.get_string())
	var i := 0
	var cmd := ""
	var cur := Vector2.ZERO
	var start := Vector2.ZERO
	var last_c := Vector2.ZERO   # last cubic / quadratic control point
	var last_cmd := ""
	var flat_note := false
	var ell_note := false
	var guard := 0
	while i < tok.size() and guard < 1000000:
		guard += 1
		if (tok[i] as String).length() == 1 and (tok[i] as String).to_upper() != (tok[i] as String).to_lower():
			cmd = tok[i]
			i += 1
			if cmd == "z" or cmd == "Z":
				_line(ents, P.call(cur), P.call(start))
				cur = start
				last_cmd = "Z"
				continue
		if cmd == "":
			break
		var rel := cmd == cmd.to_lower()
		var up := cmd.to_upper()
		var need := {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "A": 7}.get(up, 0) as int
		if need == 0 or i + need > tok.size():
			break
		var a := []
		for k in need:
			a.append(float(tok[i + k]))
		i += need
		var o := cur if rel else Vector2.ZERO
		var np := cur
		match up:
			"M":
				np = o + Vector2(a[0], a[1])
				start = np
				cmd = "l" if rel else "L"   # extra pairs after a moveto are lineto
			"L":
				np = o + Vector2(a[0], a[1])
				_line(ents, P.call(cur), P.call(np))
			"H":
				np = Vector2((cur.x if rel else 0.0) + a[0], cur.y)
				_line(ents, P.call(cur), P.call(np))
			"V":
				np = Vector2(cur.x, (cur.y if rel else 0.0) + a[0])
				_line(ents, P.call(cur), P.call(np))
			"C", "S", "Q", "T":
				var c1: Vector2
				var c2: Vector2
				var quad := up == "Q" or up == "T"
				if up == "C":
					c1 = o + Vector2(a[0], a[1])
					c2 = o + Vector2(a[2], a[3])
					np = o + Vector2(a[4], a[5])
				elif up == "S":
					c1 = cur + (cur - last_c) if last_cmd in ["C", "S"] else cur
					c2 = o + Vector2(a[0], a[1])
					np = o + Vector2(a[2], a[3])
				elif up == "Q":
					c1 = o + Vector2(a[0], a[1])
					np = o + Vector2(a[2], a[3])
				else:
					c1 = cur + (cur - last_c) if last_cmd in ["Q", "T"] else cur
					np = o + Vector2(a[0], a[1])
				var prev := cur
				for s in range(1, FLAT + 1):
					var t := float(s) / FLAT
					var u := 1.0 - t
					var pt: Vector2
					if quad:
						pt = u * u * cur + 2.0 * u * t * c1 + t * t * np
					else:
						pt = u * u * u * cur + 3.0 * u * u * t * c1 + 3.0 * u * t * t * c2 + t * t * t * np
					_line(ents, P.call(prev), P.call(pt))
					prev = pt
				last_c = c2 if up in ["C", "S"] else c1
				flat_note = true
			"A":
				np = o + Vector2(a[5], a[6])
				if _svg_arc(cur, np, absf(a[0]), absf(a[1]), deg_to_rad(a[2]), a[3] != 0.0, a[4] != 0.0, P, ents):
					ell_note = true
		cur = np
		last_cmd = up
	if flat_note:
		out["notes"].append("curves (C S Q T) were cut into %d short lines each" % FLAT)
	if ell_note:
		out["notes"].append("elliptical arcs were cut into %d short lines each" % FLAT)


# SVG arc (endpoint form) -> an arc entity (circle) or short lines (ellipse). Returns true when flattened.
static func _svg_arc(p1: Vector2, p2: Vector2, rx: float, ry: float, phi: float, fa: bool, fs: bool, P: Callable, ents: Array) -> bool:
	if p1.distance_to(p2) < 1e-9:
		return false
	if rx < 1e-9 or ry < 1e-9:
		_line(ents, P.call(p1), P.call(p2))
		return false
	var cp := cos(phi)
	var sp := sin(phi)
	var dx := (p1.x - p2.x) / 2.0
	var dy := (p1.y - p2.y) / 2.0
	var x1p := cp * dx + sp * dy
	var y1p := -sp * dx + cp * dy
	var lam := x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry)
	if lam > 1.0:
		rx *= sqrt(lam)
		ry *= sqrt(lam)
	var num := rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
	var den := rx * rx * y1p * y1p + ry * ry * x1p * x1p
	var co := sqrt(maxf(0.0, num / den)) * (-1.0 if fa == fs else 1.0)
	var cxp := co * rx * y1p / ry
	var cyp := -co * ry * x1p / rx
	var c := Vector2(cp * cxp - sp * cyp + (p1.x + p2.x) / 2.0, sp * cxp + cp * cyp + (p1.y + p2.y) / 2.0)
	var u := Vector2((x1p - cxp) / rx, (y1p - cyp) / ry)
	var v := Vector2((-x1p - cxp) / rx, (-y1p - cyp) / ry)
	var th1 := Vector2(1, 0).angle_to(u)
	var dth := fposmod(u.angle_to(v), TAU)
	if not fs and dth > 0.0:
		dth -= TAU
	if fs and dth < 0.0:
		dth += TAU
	var at := func(t: float) -> Vector2:
		return c + Vector2(cp * rx * cos(t) - sp * ry * sin(t), sp * rx * cos(t) + cp * ry * sin(t))
	if absf(rx - ry) < 1e-6 * maxf(rx, ry):
		_arc_mid_ents(ents, P.call(p1), P.call(at.call(th1 + dth / 2.0)), P.call(p2))
		return false
	var prev := p1
	for s in range(1, FLAT + 1):
		var q: Vector2 = at.call(th1 + dth * float(s) / FLAT) if s < FLAT else p2
		_line(ents, P.call(prev), P.call(q))
		prev = q
	return true


# ---------------------------------------------------------------- DXF

static func _dxf(text: String, out: Dictionary) -> void:
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var pairs := []   # [code:int, value:String]
	var i := 0
	while i + 1 < lines.size():
		var cs := (lines[i] as String).strip_edges()
		if cs.is_valid_int():
			pairs.append([int(cs), (lines[i + 1] as String).strip_edges()])
			i += 2
		else:
			i += 1   # a stray line: look for the next code
	var units_code := 0
	var in_entities := false
	var recs := []   # entity records {"t": type, "p": pairs}
	var k := 0
	while k < pairs.size():
		var c: int = pairs[k][0]
		var v: String = pairs[k][1]
		if c == 9 and v == "$INSUNITS" and k + 1 < pairs.size():
			units_code = int(pairs[k + 1][1])
		if c == 0:
			if v == "SECTION" and k + 1 < pairs.size():
				in_entities = String(pairs[k + 1][1]) == "ENTITIES"
			elif v == "ENDSEC":
				in_entities = false
			elif in_entities:
				var r := {"t": v, "p": []}
				k += 1
				while k < pairs.size() and int(pairs[k][0]) != 0:
					r["p"].append(pairs[k])
					k += 1
				recs.append(r)
				continue
		k += 1
	var fac := 1.0
	var uname := "mm"
	match units_code:
		0:
			uname = "mm (the file names no unit)"
		1:
			fac = 25.4
			uname = "inches"
		2:
			fac = 304.8
			uname = "feet"
		4:
			uname = "mm"
		5:
			fac = 10.0
			uname = "cm"
		6:
			fac = 1000.0
			uname = "m"
		_:
			uname = "mm (unit code %d not known, taken as mm)" % units_code
	out["units"] = "DXF units: %s ($INSUNITS %d), 1 unit = %s mm" % [uname, units_code, snappedf(fac, 0.001)]
	var ents: Array = out["ents"]
	var unsup := {}
	var n := 0
	while n < recs.size():
		var r: Dictionary = recs[n]
		var t: String = r["t"]
		var g := func(code: int, d := 0.0) -> float:
			for p in r["p"]:
				if int(p[0]) == code:
					return float(p[1]) * fac
			return d
		match t:
			"LINE":
				out["source_count"] += 1
				_line(ents, Vector2(g.call(10), g.call(20)), Vector2(g.call(11), g.call(21)))
			"CIRCLE":
				out["source_count"] += 1
				var rr: float = g.call(40)
				if rr > 0.0:
					ents.append({"k": "circle", "c": [g.call(10), g.call(20)], "r": rr})
			"ARC":
				out["source_count"] += 1
				var cen := Vector2(g.call(10), g.call(20))
				var rad: float = g.call(40)
				var s0 := deg_to_rad(float(_first(r["p"], 50)))
				var e0 := deg_to_rad(float(_first(r["p"], 51)))
				while e0 <= s0:
					e0 += TAU
				if rad > 0.0:
					_arc_mid_ents(ents, cen + Vector2(cos(s0), sin(s0)) * rad, cen + Vector2(cos((s0 + e0) / 2.0), sin((s0 + e0) / 2.0)) * rad, cen + Vector2(cos(e0), sin(e0)) * rad)
			"LWPOLYLINE":
				out["source_count"] += 1
				var vs := []   # [Vector2, bulge]
				for p in r["p"]:
					var cd: int = p[0]
					if cd == 10:
						vs.append([Vector2(float(p[1]) * fac, 0.0), 0.0])
					elif cd == 20 and vs.size() > 0:
						vs[-1][0] = Vector2((vs[-1][0] as Vector2).x, float(p[1]) * fac)
					elif cd == 42 and vs.size() > 0:
						vs[-1][1] = float(p[1])
				_poly(ents, vs, (int(_first(r["p"], 70)) & 1) == 1)
			"POLYLINE":
				out["source_count"] += 1
				var vs := []
				var closed := (int(_first(r["p"], 70)) & 1) == 1
				while n + 1 < recs.size() and String(recs[n + 1]["t"]) == "VERTEX":
					n += 1
					var vr: Dictionary = recs[n]
					if (int(_first(vr["p"], 70)) & 16) == 0:   # 16 = a spline frame control point, not on the curve
						vs.append([Vector2(float(_first(vr["p"], 10)) * fac, float(_first(vr["p"], 20)) * fac), float(_first(vr["p"], 42))])
				if n + 1 < recs.size() and String(recs[n + 1]["t"]) == "SEQEND":
					n += 1
				_poly(ents, vs, closed)
			"VERTEX", "SEQEND":
				pass
			_:
				unsup[t] = int(unsup.get(t, 0)) + 1
		n += 1
	out["unsupported"] = _count_words(unsup)


static func _first(pairs: Array, code: int) -> Variant:
	for p in pairs:
		if int(p[0]) == code:
			return p[1]
	return 0


static func _poly(ents: Array, vs: Array, closed: bool) -> void:
	var cnt := vs.size()
	for i in (cnt if closed else cnt - 1):
		var p0: Vector2 = vs[i][0]
		var p1: Vector2 = vs[(i + 1) % cnt][0]
		var bu := float(vs[i][1])
		if absf(bu) < 1e-9:
			_line(ents, p0, p1)
		elif p0.distance_to(p1) > 1e-9:
			var d := p1 - p0
			var mid := (p0 + p1) / 2.0 + Vector2(d.y, -d.x) * bu / 2.0   # a bulge is tan(angle/4): the arc's middle is bu/2 of the chord off to the right
			_arc_mid_ents(ents, p0, mid, p1)
