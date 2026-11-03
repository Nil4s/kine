## SVG IMPORT WITH A SCALE CHECK (C15, complaint #414: "free SVG templates vary; scale must be checked"). Engine only: SVG text in, a sketch's lines
## (millimetres, y up, the drawing's lower-left corner at 0,0) and a plain-words scale report out.
## The reported size comes from width / height (mm, cm, in, pt, pc, px; a bare number is CSS px = 1/96 in) or, when they are missing, from the viewBox in px.
## The report WARNS when: the file names no unit, there is no width / height, the width:height ratio disagrees with the viewBox's, the drawing
## runs outside its viewBox or fills a tenth of it, or a transform / unsupported element was skipped. {"width_mm": W} rescales the drawing to a real width.
class_name SvgImport
extends RefCounted

const MM_PER := {"mm": 1.0, "cm": 10.0, "in": 25.4, "pt": 25.4 / 72.0, "pc": 25.4 / 6.0, "px": 25.4 / 96.0, "": 25.4 / 96.0}
const FLAT := 12   # segments per curve


## "120mm" -> {"v": 120.0, "unit": "mm"}; "" -> {"v": NAN}
static func len_of(s: String) -> Dictionary:
	s = s.strip_edges()
	if s == "" or s.ends_with("%"):
		return {"v": NAN, "unit": "", "pct": s.ends_with("%")}
	var re := RegEx.new()
	re.compile("^([-+]?[0-9]*\\.?[0-9]+(?:[eE][-+]?[0-9]+)?)\\s*([a-zA-Z]*)$")
	var r := re.search(s)
	if r == null:
		return {"v": NAN, "unit": ""}
	var u := r.get_string(2).to_lower()
	if not MM_PER.has(u):
		return {"v": NAN, "unit": u}
	return {"v": float(r.get_string(1)), "unit": u}


static func _attrs(tag: String) -> Dictionary:
	var out := {}
	var re := RegEx.new()
	re.compile("([a-zA-Z_:][-a-zA-Z0-9_:.]*)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')")
	for r in re.search_all(tag):
		out[r.get_string(1)] = r.get_string(2) if r.get_string(2) != "" or r.get_string(3) == "" else r.get_string(3)
	return out


static func _nums(s: String) -> PackedFloat64Array:
	var re := RegEx.new()
	re.compile("[-+]?(?:[0-9]*\\.[0-9]+|[0-9]+\\.?)(?:[eE][-+]?[0-9]+)?")
	var out := PackedFloat64Array()
	for r in re.search_all(s):
		out.append(float(r.get_string()))
	return out


## a path's "d" -> polylines (each {"pts": [Vector2], "closed": bool}) in user units, y down; arcs become their chord (counted in arcs)
static func path_polys(d: String, stat: Dictionary) -> Array:
	var polys := []
	var cur := []
	var cp := Vector2.ZERO
	var start := Vector2.ZERO
	var re := RegEx.new()
	re.compile("([MmLlHhVvZzCcQqSsTtAa])([^MmLlHhVvZzCcQqSsTtAa]*)")
	for r in re.search_all(d):
		var cmd := r.get_string(1)
		var n := _nums(r.get_string(2))
		var rel := cmd == cmd.to_lower()
		var up := cmd.to_upper()
		var i := 0
		if up == "Z":
			if cur.size() > 1:
				polys.append({"pts": cur, "closed": true})
			cur = []
			cp = start
			continue
		var first := true
		while i < n.size() or (first and up == "Z"):
			first = false
			match up:
				"M":
					if i + 1 >= n.size(): break
					var p := Vector2(n[i], n[i + 1]) + (cp if rel else Vector2.ZERO)
					i += 2
					if cur.size() > 1:
						polys.append({"pts": cur, "closed": false})
					cur = [p]
					cp = p
					start = p
					up = "L"   # later pairs are lineto
				"L":
					if i + 1 >= n.size(): break
					cp = Vector2(n[i], n[i + 1]) + (cp if rel else Vector2.ZERO)
					i += 2
					cur.append(cp)
				"H":
					cp = Vector2(n[i] + (cp.x if rel else 0.0), cp.y)
					i += 1
					cur.append(cp)
				"V":
					cp = Vector2(cp.x, n[i] + (cp.y if rel else 0.0))
					i += 1
					cur.append(cp)
				"C":
					if i + 5 >= n.size(): break
					var o := cp if rel else Vector2.ZERO
					var c1 := Vector2(n[i], n[i + 1]) + o
					var c2 := Vector2(n[i + 2], n[i + 3]) + o
					var e := Vector2(n[i + 4], n[i + 5]) + o
					i += 6
					for k in range(1, FLAT + 1):
						var t := float(k) / FLAT
						var u := 1.0 - t
						cur.append(cp * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + e * t * t * t)
					cp = e
				"Q":
					if i + 3 >= n.size(): break
					var o := cp if rel else Vector2.ZERO
					var c1 := Vector2(n[i], n[i + 1]) + o
					var e := Vector2(n[i + 2], n[i + 3]) + o
					i += 4
					for k in range(1, FLAT + 1):
						var t := float(k) / FLAT
						var u := 1.0 - t
						cur.append(cp * u * u + c1 * 2.0 * u * t + e * t * t)
					cp = e
				"A":
					if i + 6 >= n.size(): break
					cp = Vector2(n[i + 5], n[i + 6]) + (cp if rel else Vector2.ZERO)
					i += 7
					cur.append(cp)
					stat["arcs"] = int(stat.get("arcs", 0)) + 1
				_:
					stat["skipped"] = int(stat.get("skipped", 0)) + 1
					i = n.size()
	if cur.size() > 1:
		polys.append({"pts": cur, "closed": false})
	return polys


## the whole import. opts: {"width_mm": real width to scale the drawing to}
## answers {"ok", "why", "size_mm": Vector2 (the file's reported size), "content_mm": Vector2, "mm_per_unit", "warnings": [String], "words", "ents": [line entities], "lines": n}
static func parse(text: String, opts := {}) -> Dictionary:
	var out := {"ok": false, "why": "", "size_mm": Vector2.ZERO, "content_mm": Vector2.ZERO, "mm_per_unit": 1.0, "warnings": [], "words": "", "ents": [], "lines": 0}
	var warn: Array = out["warnings"]
	var rs := RegEx.new()
	rs.compile("<svg\\b([^>]*)>")
	var sm := rs.search(text)
	if sm == null:
		out["why"] = "This is not an SVG file (no <svg> tag)."
		return out
	var sa := _attrs(sm.get_string(1))
	var vb := _nums(String(sa.get("viewBox", "")))
	var has_vb := vb.size() == 4 and vb[2] > 0.0 and vb[3] > 0.0
	var wl := len_of(String(sa.get("width", "")))
	var hl := len_of(String(sa.get("height", "")))
	var has_w := not is_nan(wl["v"])
	var has_h := not is_nan(hl["v"])
	# user unit -> mm
	var upu := MM_PER["px"]
	var size := Vector2.ZERO
	if has_w and has_h:
		size = Vector2(float(wl["v"]) * MM_PER[wl["unit"]], float(hl["v"]) * MM_PER[hl["unit"]])
		if wl["unit"] == "" or hl["unit"] == "":
			warn.append("The file gives its size with no unit; it is read as pixels (96 to the inch). Check the real size below.")
		if has_vb:
			upu = size.x / vb[2]
			var ar_vb: float = vb[2] / vb[3]
			var ar_sz: float = size.x / maxf(size.y, 1e-9)
			if absf(ar_vb / ar_sz - 1.0) > 0.01:
				warn.append("Scale mismatch: the width and height are %.1f x %.1f mm (ratio %.3f) but the viewBox is %.0f x %.0f (ratio %.3f). The drawing may be stretched." % [size.x, size.y, ar_sz, vb[2], vb[3], ar_vb])
		else:
			upu = MM_PER[wl["unit"]]
	elif has_vb:
		size = Vector2(vb[2], vb[3]) * upu
		warn.append("The file gives no width and height; its size is taken from the viewBox in pixels (96 to the inch). Check the real size below.")
	else:
		warn.append("The file gives no width, height or viewBox; its size cannot be known. Type the real width below.")
	out["size_mm"] = size
	# collect the shapes
	var polys := []
	var stat := {}
	var re := RegEx.new()
	re.compile("<(path|rect|circle|ellipse|line|polyline|polygon)\\b([^>]*?)/?>")
	for r in re.search_all(text):
		var tag := r.get_string(1)
		var a := _attrs(r.get_string(2))
		if a.has("transform"):
			stat["transform"] = int(stat.get("transform", 0)) + 1
		match tag:
			"path":
				polys.append_array(path_polys(String(a.get("d", "")), stat))
			"rect":
				var x := float(a.get("x", 0)); var y := float(a.get("y", 0)); var w := float(a.get("width", 0)); var h := float(a.get("height", 0))
				if w > 0.0 and h > 0.0:
					polys.append({"pts": [Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)], "closed": true})
			"circle", "ellipse":
				var cx := float(a.get("cx", 0)); var cy := float(a.get("cy", 0))
				var rx := float(a.get("r", a.get("rx", 0))); var ry := float(a.get("r", a.get("ry", 0)))
				if rx > 0.0 and ry > 0.0:
					var pts := []
					for k in 48:
						var t := TAU * k / 48.0
						pts.append(Vector2(cx + rx * cos(t), cy + ry * sin(t)))
					polys.append({"pts": pts, "closed": true})
			"line":
				polys.append({"pts": [Vector2(float(a.get("x1", 0)), float(a.get("y1", 0))), Vector2(float(a.get("x2", 0)), float(a.get("y2", 0)))], "closed": false})
			"polyline", "polygon":
				var n := _nums(String(a.get("points", "")))
				var pts := []
				for k in range(0, n.size() - 1, 2):
					pts.append(Vector2(n[k], n[k + 1]))
				if pts.size() > 1:
					polys.append({"pts": pts, "closed": tag == "polygon"})
	if polys.is_empty():
		out["why"] = "No lines, shapes or paths were found in this SVG."
		return out
	if int(stat.get("transform", 0)) > 0:
		warn.append("%d shape(s) carry a transform; transforms are NOT applied, so their size or place may be off." % int(stat["transform"]))
	if int(stat.get("arcs", 0)) > 0:
		warn.append("%d curved arc(s) were drawn as straight chords." % int(stat["arcs"]))
	if int(stat.get("skipped", 0)) > 0:
		warn.append("%d path command(s) were skipped (smooth curves)." % int(stat["skipped"]))
	# the drawing's box in user units
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for pl in polys:
		for p in pl["pts"]:
			lo = lo.min(p)
			hi = hi.max(p)
	var content := (hi - lo) * upu
	if has_vb:
		var vlo := Vector2(vb[0], vb[1])
		var vhi := vlo + Vector2(vb[2], vb[3])
		var pad := Vector2(vb[2], vb[3]) * 0.02
		if lo.x < vlo.x - pad.x or lo.y < vlo.y - pad.y or hi.x > vhi.x + pad.x or hi.y > vhi.y + pad.y:
			warn.append("The drawing runs outside its viewBox, so the reported size does not hold for all of it.")
		elif (hi - lo).x < vb[2] * 0.1 and (hi - lo).y < vb[3] * 0.1:
			warn.append("The drawing fills under a tenth of its viewBox; the page size is not the size of the part.")
	var k_fix := 1.0
	if float(opts.get("width_mm", 0.0)) > 0.0 and content.x > 1e-9:
		k_fix = float(opts["width_mm"]) / content.x
		upu *= k_fix
		content *= k_fix
		out["size_mm"] = size * k_fix
		warn.append("Scaled so the drawing is %.1f mm wide, as you typed." % float(opts["width_mm"]))
	out["mm_per_unit"] = upu
	out["content_mm"] = content
	var ents := []
	for pl in polys:
		var pts: Array = pl["pts"]
		var cnt: int = pts.size() + (1 if pl["closed"] else 0)
		for k in range(cnt - 1):
			var p0: Vector2 = pts[k]
			var p1: Vector2 = pts[(k + 1) % pts.size()]
			var a0 := Vector2((p0.x - lo.x) * upu, (hi.y - p0.y) * upu)   # y flips: SVG is y down
			var a1 := Vector2((p1.x - lo.x) * upu, (hi.y - p1.y) * upu)
			if a0.distance_to(a1) < 1e-4:
				continue
			ents.append({"k": "line", "a": [snappedf(a0.x, 0.0001), snappedf(a0.y, 0.0001)], "b": [snappedf(a1.x, 0.0001), snappedf(a1.y, 0.0001)]})
	out["ents"] = ents
	out["lines"] = ents.size()
	out["ok"] = not ents.is_empty()
	out["words"] = words(out)
	return out


static func words(rep: Dictionary) -> String:
	var sz: Vector2 = rep["size_mm"]
	var c: Vector2 = rep["content_mm"]
	var s := "File says %.1f x %.1f mm. The drawing itself is %.1f x %.1f mm (%d lines)." % [sz.x, sz.y, c.x, c.y, int(rep["lines"])]
	var w: Array = rep["warnings"]
	if w.is_empty():
		return s + " Scale looks consistent."
	return s + " CHECK: " + " ".join(PackedStringArray(w))


## put the import in the part as a new sketch on `plane`: answers the new sketch's id ("" if nothing was imported)
static func add_to(rec: Dictionary, rep: Dictionary, plane_name := "front") -> String:
	if not bool(rep.get("ok", false)):
		return ""
	var f := Part.new_feature(rec, "sketch", {"plane": plane_name, "ents": (rep["ents"] as Array).duplicate(true), "dims": []})
	rec["features"].append(f)
	return String(f["id"])
