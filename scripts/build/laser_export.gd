## LASER-CUT OUTLINE EXPORT (SVG, DXF) of a flat face of a built Part (plan item 116). The maker picks a side (or "largest flat face"); the face's
## outer loop and its holes are written in millimetres:
##   .svg  width/height in mm, viewBox in mm, y down (the SVG way); one <path> per loop (polyline), the outer one first, id="outer", "hole1" ...
##   .dxf  R12 ASCII ($ACADVER AC1009, $INSUNITS 4 = mm), y up, origin at the face's lower-left; LINE for straight runs, CIRCLE for a round hole
## Curves are cut finely (chord error <= 0.02 mm) before the loops are read, so a polyline never strays 0.05 mm from the true curve.
## The face is found from the kernel's own mesh: triangles on one plane with one normal make a flat face; its loops are the edges only one of its
## triangles uses. A face that is curved or sloped has no outline: the words say so.
class_name LaserExport
extends RefCounted

const KCad := preload("res://scripts/kcad.gd")
const DEFLECT_M := 0.00002   # 0.02 mm off the true curve at most
const ANGLE := 0.1
const FLAT_COS := 0.999   # a face "faces" a side when its normal is within 2.6 degrees of it
const MIN_AREA := 1.0   # mm2: a flat face smaller than this is a tessellation scrap, not a face to cut
## the pick list: label, the side's direction in printer axes (x right, y back, z up); zero = the biggest flat face of any side
const FACES := [
	{"label": "Largest flat face", "dir": Vector3.ZERO, "word": "largest flat face"},
	{"label": "Top", "dir": Vector3(0, 0, 1), "word": "top"},
	{"label": "Bottom", "dir": Vector3(0, 0, -1), "word": "bottom"},
	{"label": "Front", "dir": Vector3(0, -1, 0), "word": "front"},
	{"label": "Back", "dir": Vector3(0, 1, 0), "word": "back"},
	{"label": "Left", "dir": Vector3(-1, 0, 0), "word": "left side"},
	{"label": "Right", "dir": Vector3(1, 0, 0), "word": "right side"},
]


static func face_labels() -> Array:
	return FACES.map(func(f): return String(f["label"]))


## the part's bodies tessellated fine: [{"v": mm Z-up welded, "t": indices}], and why when empty
static func _bodies(rec: Dictionary) -> Dictionary:
	if rec.is_empty() or not Part.available():
		return {"bodies": [], "why": "Nothing to cut: " + ("make a part first" if Part.available() else Part.why_not())}
	var res := Part.replay(rec, -1, {"keep": true})
	var out := []
	for id in res.get("ids", []):
		var soup := PackedVector3Array()
		var tm := KCad.tessellate(int(id), DEFLECT_M, ANGLE)
		if tm != null:
			for s in tm.get_surface_count():
				var arr := tm.surface_get_arrays(s)
				var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var idx = arr[Mesh.ARRAY_INDEX]
				if idx == null:
					soup.append_array(vs)
				else:
					for k in (idx as PackedInt32Array):
						soup.append(vs[k])
		KCad.release(int(id))
		var b := MeshExport.weld(soup)
		if (b["t"] as PackedInt32Array).size() > 0:
			out.append(b)
	if out.is_empty():
		return {"bodies": [], "why": "Nothing to cut: this part has no solid yet"}
	return {"bodies": out, "why": ""}


## flat faces of one body: [{"n": unit normal, "d": plane offset, "tris": [triangle index], "area": mm2, "body": i}]
static func _groups(b: Dictionary, bi: int) -> Array:
	var v: PackedVector3Array = b["v"]
	var t: PackedInt32Array = b["t"]
	var by := {}
	for i in range(0, t.size(), 3):
		var a := v[t[i]]
		var cr := (v[t[i + 1]] - a).cross(v[t[i + 2]] - a)
		var ar := cr.length() * 0.5
		if ar < 1e-9:
			continue
		var n := cr.normalized()
		var d := n.dot(a)
		var key := Vector4i(roundi(n.x * 1000.0), roundi(n.y * 1000.0), roundi(n.z * 1000.0), roundi(d * 100.0))
		if not by.has(key):
			by[key] = {"n": n, "d": d, "tris": [], "area": 0.0, "body": bi}
		(by[key]["tris"] as Array).append(i)
		by[key]["area"] = float(by[key]["area"]) + ar
	return by.values()


## the 2D frame of a face seen from outside: u right, v up, u x v = n
static func _frame(n: Vector3) -> Array:
	var up := Vector3(0, 1, 0) if absf(n.z) > 0.99 else Vector3(0, 0, 1)
	var u := up.cross(n).normalized()
	var w := n.cross(u).normalized()
	return [u, w]


## the outline of the chosen face of a part record.
## {"ok", "why" (plain words when not ok), "loops": [{"pts": PackedVector2Array (mm, lower-left of the outer box = 0,0), "hole": bool,
##  "circle": {} or {"c": Vector2, "r": float}}], "w", "h" (mm), "face": the word, "n": Vector3, "area": mm2 of the flat face}
static func outline(rec: Dictionary, face := 0) -> Dictionary:
	var fi := clampi(face, 0, FACES.size() - 1)
	var word := String(FACES[fi]["word"])
	var dir: Vector3 = FACES[fi]["dir"]
	var bo := _bodies(rec)
	if (bo["bodies"] as Array).is_empty():
		return {"ok": false, "why": String(bo["why"]), "loops": []}
	var bodies: Array = bo["bodies"]
	var groups := []
	for bi in bodies.size():
		groups.append_array(_groups(bodies[bi], bi))
	var best: Dictionary = {}
	var facing := 0.0   # the area on that side of the part, flat or not
	for g in groups:
		var n: Vector3 = g["n"]
		if dir == Vector3.ZERO:
			facing += float(g["area"])
			if best.is_empty() or float(g["area"]) > float(best["area"]):
				best = g
		elif n.dot(dir) > 0.5:
			facing += float(g["area"])
			if n.dot(dir) > FLAT_COS and (best.is_empty() or float(g["area"]) > float(best["area"])):
				best = g
	if best.is_empty() or float(best["area"]) < MIN_AREA or (dir != Vector3.ZERO and float(best["area"]) < 0.1 * facing):
		var why: String
		if dir == Vector3.ZERO:
			why = "NOT DONE: this part has no flat face to cut (every side is curved). Make a flat side first, for example with a Cut or by standing the shape on a plane"
		else:
			why = "NOT DONE: the %s of this part is not flat (it is curved or sloped), so it has no outline to cut. Pick a side that is flat, or choose Largest flat face" % word
		return {"ok": false, "why": why, "loops": [], "face": word}
	var n: Vector3 = best["n"]
	var fr := _frame(n)
	var u: Vector3 = fr[0]
	var w: Vector3 = fr[1]
	var b: Dictionary = bodies[int(best["body"])]
	var v: PackedVector3Array = b["v"]
	var t: PackedInt32Array = b["t"]
	# boundary: directed edges whose reverse is not in the face
	var edges := {}
	var nv := v.size()
	for i in best["tris"]:
		for k in 3:
			var a := t[i + k]
			var c := t[i + (k + 1) % 3]
			edges[a * nv + c] = true
	var out_of := {}
	for key in edges:
		var a: int = key / nv
		var c: int = key % nv
		if edges.has(c * nv + a):
			continue
		if not out_of.has(a):
			out_of[a] = []
		(out_of[a] as Array).append(c)
	var loops := []
	var guard := 0
	while not out_of.is_empty() and guard < 100000:
		guard += 1
		var start: int = out_of.keys()[0]
		var ring := [start]
		var cur: int = start
		var closed := false
		while true:
			if not out_of.has(cur):
				break
			var nxt: int = (out_of[cur] as Array).pop_back()
			if (out_of[cur] as Array).is_empty():
				out_of.erase(cur)
			if nxt == start:
				closed = true
				break
			ring.append(nxt)
			cur = nxt
		if closed and ring.size() >= 3:
			var pts := PackedVector2Array()
			for vi in ring:
				pts.append(Vector2(v[vi].dot(u), v[vi].dot(w)))
			loops.append(_tidy(pts))
	if loops.is_empty():
		return {"ok": false, "why": "NOT DONE: the %s has no closed edge to cut" % word, "loops": [], "face": word}
	# origin: the lower-left of the outer loops' box
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for lp in loops:
		if _area(lp) > 0.0:
			for p in (lp as PackedVector2Array):
				lo = lo.min(p)
				hi = hi.max(p)
	if lo.x == INF:
		return {"ok": false, "why": "NOT DONE: the %s has no outer edge to cut" % word, "loops": [], "face": word}
	var res := []
	for lp in loops:
		var pts: PackedVector2Array = lp
		for i in pts.size():
			pts[i] -= lo
		var hole := _area(pts) < 0.0
		res.append({"pts": pts, "hole": hole, "circle": _fit_circle(pts)})
	# outer loops first (largest first), then holes
	res.sort_custom(func(p, q):
		if bool(p["hole"]) != bool(q["hole"]):
			return not bool(p["hole"])
		return absf(_area(p["pts"])) > absf(_area(q["pts"])))
	return {"ok": true, "why": "", "loops": res, "w": hi.x - lo.x, "h": hi.y - lo.y, "face": word, "n": n, "area": float(best["area"])}


## signed area (mm2) of a loop: positive counter-clockwise (an outer loop), negative for a hole
static func _area(pts: PackedVector2Array) -> float:
	var s := 0.0
	for i in pts.size():
		var a := pts[i]
		var c := pts[(i + 1) % pts.size()]
		s += a.x * c.y - c.x * a.y
	return s * 0.5


## drop points that lie on the straight line between their neighbours (within 0.001 mm)
static func _tidy(pts: PackedVector2Array) -> PackedVector2Array:
	var n := pts.size()
	var out := PackedVector2Array()
	for i in n:
		var a := pts[(i + n - 1) % n]
		var b := pts[i]
		var c := pts[(i + 1) % n]
		var ac := c - a
		var dist := 0.0 if ac.length() < 1e-9 else absf(ac.cross(b - a)) / ac.length()
		if dist < 0.001 and (b - a).dot(c - b) > 0.0:
			continue
		out.append(b)
	return out if out.size() >= 3 else pts


## {"c", "r"} when every point of the loop lies on one circle (within 0.01 mm) all the way round, else {}
static func _fit_circle(pts: PackedVector2Array) -> Dictionary:
	if pts.size() < 8:
		return {}
	var lo := pts[0]
	var hi := pts[0]
	var mean := Vector2.ZERO
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
		mean += p
	mean /= pts.size()
	for c in [(lo + hi) * 0.5, mean]:
		var rs := 0.0
		for p in pts:
			rs += (p - c).length()
		var r := rs / pts.size()
		var dev := 0.0
		for p in pts:
			dev = maxf(dev, absf((p - c).length() - r))
		if dev <= 0.01 and r > 0.0:
			var angs := []
			for p in pts:
				angs.append(atan2(p.y - c.y, p.x - c.x))
			angs.sort()
			var gap: float = TAU - (float(angs[angs.size() - 1]) - float(angs[0]))
			for i in range(1, angs.size()):
				gap = maxf(gap, float(angs[i]) - float(angs[i - 1]))
			if gap < TAU / 3.0:
				return {"c": c, "r": r}
	return {}


static func _f(x: float) -> String:
	return "%.4f" % x


## the SVG text of an outline (millimetres, y down)
static func svg_text(ol: Dictionary, title: String) -> String:
	var w := float(ol["w"])
	var h := float(ol["h"])
	var s := "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
	s += "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%smm\" height=\"%smm\" viewBox=\"0 0 %s %s\">\n" % [_f(w), _f(h), _f(w), _f(h)]
	s += "<title>%s</title>\n<g fill=\"none\" stroke=\"#ff0000\" stroke-width=\"0.1\">\n" % title.xml_escape()
	var hn := 0
	var on := 0
	for lp in ol["loops"]:
		var pts: PackedVector2Array = lp["pts"]
		var d := ""
		for i in pts.size():
			d += ("M" if i == 0 else " L") + "%s %s" % [_f(pts[i].x), _f(h - pts[i].y)]
		d += " Z"
		var id := "outer"
		if bool(lp["hole"]):
			hn += 1
			id = "hole%d" % hn
		else:
			on += 1
			if on > 1:
				id = "outer%d" % on
		s += "<path id=\"%s\" d=\"%s\"/>\n" % [id, d]
	return s + "</g>\n</svg>\n"


## the DXF text (R12 ASCII, mm): LINE and CIRCLE on layer CUT
static func dxf_text(ol: Dictionary) -> String:
	var w := float(ol["w"])
	var h := float(ol["h"])
	var s := "0\nSECTION\n2\nHEADER\n9\n$ACADVER\n1\nAC1009\n9\n$INSUNITS\n70\n4\n9\n$EXTMIN\n10\n0.0\n20\n0.0\n30\n0.0\n9\n$EXTMAX\n10\n%s\n20\n%s\n30\n0.0\n0\nENDSEC\n" % [_f(w), _f(h)]
	s += "0\nSECTION\n2\nTABLES\n0\nTABLE\n2\nLTYPE\n70\n1\n0\nLTYPE\n2\nCONTINUOUS\n70\n0\n3\nSolid line\n72\n65\n73\n0\n40\n0.0\n0\nENDTAB\n"
	s += "0\nTABLE\n2\nLAYER\n70\n1\n0\nLAYER\n2\nCUT\n70\n0\n62\n1\n6\nCONTINUOUS\n0\nENDTAB\n0\nENDSEC\n"
	s += "0\nSECTION\n2\nENTITIES\n"
	for lp in ol["loops"]:
		var cc: Dictionary = lp["circle"]
		if not cc.is_empty():
			var c: Vector2 = cc["c"]
			s += "0\nCIRCLE\n8\nCUT\n10\n%s\n20\n%s\n30\n0.0\n40\n%s\n" % [_f(c.x), _f(c.y), _f(float(cc["r"]))]
			continue
		var pts: PackedVector2Array = lp["pts"]
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			s += "0\nLINE\n8\nCUT\n10\n%s\n20\n%s\n30\n0.0\n11\n%s\n21\n%s\n31\n0.0\n" % [_f(a.x), _f(a.y), _f(b.x), _f(b.y)]
	return s + "0\nENDSEC\n0\nEOF\n"


## the Export dialog's road: the part record -> dir/<name>_<face>.svg or .dxf. fmt "svg" | "dxf". Answers {"ok", "path", "why", "text"}
static func export_part(rec: Dictionary, fmt: String, dir: String, face := 0) -> Dictionary:
	var ol := outline(rec, face)
	if not bool(ol["ok"]):
		return {"ok": false, "path": "", "why": String(ol["why"]), "text": String(ol["why"]), "outline": ol}
	var gdir := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(gdir)
	var name := String(rec.get("name", "Part"))
	var path := "%s/%s_%s.%s" % [gdir, MeshExport.stem(name), String(ol["face"]).replace(" ", "_"), fmt]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		var e := FileAccess.get_open_error()
		return {"ok": false, "path": path, "why": error_string(e), "text": "NOT DONE: the file could not be written (%s). Check that the folder is writable, then export again" % error_string(e), "outline": ol}
	f.store_string(svg_text(ol, name) if fmt == "svg" else dxf_text(ol))
	f.close()
	var holes := 0
	for lp in ol["loops"]:
		holes += 1 if bool(lp["hole"]) else 0
	var msg := "exported %s: the %s, %.2f x %.2f mm, %d hole%s, millimetres" % [path.get_file(), String(ol["face"]), float(ol["w"]), float(ol["h"]), holes, "" if holes == 1 else "s"]
	return {"ok": true, "path": path, "why": "", "text": msg, "outline": ol}


## the dialog's checklist (lines start OK or WARN)
static func check_lines(rec: Dictionary, face := 0) -> Array:
	var ol := outline(rec, face)
	if not bool(ol["ok"]):
		return ["WARN  " + String(ol["why"]).trim_prefix("NOT DONE: ")]
	var holes := 0
	for lp in ol["loops"]:
		holes += 1 if bool(lp["hole"]) else 0
	return ["OK    face: the %s is flat, %.2f x %.2f mm" % [String(ol["face"]), float(ol["w"]), float(ol["h"])],
		"OK    cuts: %d outer edge%s and %d hole%s, in millimetres" % [(ol["loops"] as Array).size() - holes, "" if (ol["loops"] as Array).size() - holes == 1 else "s", holes, "" if holes == 1 else "s"]]
