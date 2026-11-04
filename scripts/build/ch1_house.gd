class_name Ch1House
extends RefCounted
## CH1c: the bridge between the CH1a house (member list in mm) and the CH1b check (HouseCheck, a record in ft / in).
##   from_members(mj)    out/ch1/members.json (parsed) -> a HouseCheck house record; every number comes from the members, the assumptions are in mj["meta"]
##   run(mj)             HouseCheck.check on that record plus the extra lines this bridge owns (interior bearing-wall headers); Array of line Dictionaries
##   overlaps(members)   volume of intersection of every pair of FRAMING members (data/challenges/ch1_house.json members: box + optional poly), mm3
##   rafter_axes(members) per rafter: its axis (longest edge of its sketch polygon, as a 3D vector) and the ridge axis, to test they are perpendicular
## Nothing here changes the house: it only reads it.

const MM_FT := 304.8
const MM_IN := 25.4
const T := 38.0
const FRAMING := ["rafter_pair", "bottom_plate", "top_plate1", "top_plate2", "stud", "king", "jack", "cripple", "corner", "end", "nailer", "gable_stud", "header", "joist", "rafter", "gable_rafter", "ridge", "sill"]
const EXTERIOR := {"F": "front", "B": "rear", "L": "left gable", "R": "right gable"}


static func wall_of(name: String) -> String:
	var p := name.split(".")
	return p[1] if p.size() > 1 else ""


## the wall's extent along its own axis from the top plates (mm): [a0, a1]
static func _extent(members: Array, w: String) -> Array:
	var lo := 1e9
	var hi := -1e9
	var along := 0 if w in ["F", "B", "H"] else 2
	for m in members:
		if m["kind"] in ["top_plate1", "top_plate2"] and wall_of(m["name"]) == w:
			var b: Array = m["box_mm"]
			lo = minf(lo, float(b[along]))
			hi = maxf(hi, float(b[along + 3]))
	return [lo, hi]


static func from_members(mj: Dictionary) -> Dictionary:
	var members: Array = mj["members"]
	var meta: Dictionary = mj.get("meta", {})
	var xs := 0.0
	var zs := 0.0
	var wall_top := 0.0
	for m in members:
		var b: Array = m["box_mm"]
		if m["kind"] == "slab":
			xs = float(b[3]) - float(b[0])
			zs = float(b[5]) - float(b[2])
		if m["kind"] == "top_plate2":
			wall_top = maxf(wall_top, float(b[4]))
	# rafters run front to back (across z): the building "width" the tables use is the depth, z
	var walls := []
	var bear := {"F": true, "B": true, "H": true, "L": false, "R": false, "V1": false, "V2": false}
	var names := {"F": "front", "B": "rear", "L": "left gable", "R": "right gable", "H": "hall wall (interior, bearing)", "V1": "partition 1", "V2": "partition 2"}
	for w in ["F", "B", "L", "R", "H", "V1", "V2"]:
		var ext := _extent(members, w)
		var len_mm: float = ext[1] - ext[0]
		var sp := 0.0
		var ops := []
		var cuts := []
		for m in members:
			if wall_of(m["name"]) != w:
				continue
			if m["kind"] == "stud" and m["spacing_mm"] != null:
				sp = float(m["spacing_mm"])
			if m["kind"] == "header":
				var b: Array = m["box_mm"]
				var along := 0 if w in ["F", "B", "H"] else 2
				var a0: float = float(b[along]) - float(ext[0])
				var a1: float = float(b[along + 3]) - float(ext[0])
				var nominal: String = m["nominal"]
				if bear[w]:
					ops.append({"width_ft": float(m["span_mm"]) / MM_FT, "header": nominal, "name": m["name"]})
				cuts.append([a0 - T, a1 + T])      # the header runs between the kings; a braced panel ends at the king's outer face
		cuts.sort_custom(func(p, q): return p[0] < q[0])
		var panels := []
		var s := 0.0
		for c in cuts + [[len_mm, len_mm]]:
			var seg: float = c[0] - s
			if seg / MM_FT >= 4.0 - 1e-6:
				panels.append({"pos_ft": s / MM_FT, "len_ft": seg / MM_FT})
			s = c[1]
		var line_sp := (zs if w in ["F", "B"] else xs) / MM_FT
		var wl := {"name": names[w], "key": w, "length_ft": len_mm / MM_FT, "line_spacing_ft": line_sp, "stud": "2x4", "spacing_in": int(round(sp / MM_IN)) if sp > 0 else 16,
			"bearing": bear[w], "openings": ops}
		if w in EXTERIOR:
			wl["bracing"] = panels
		else:
			wl["braced"] = false      # an interior wall is not a braced wall line here: studs, and headers if bearing
		walls.append(wl)
	var joist_sp := 0.0
	var rafter_sp := 0.0
	var jn := ""
	var rn := ""
	var ridge := ""
	for m in members:
		if m["kind"] == "joist" and m["spacing_mm"] != null:
			joist_sp = float(m["spacing_mm"])
			jn = m["nominal"]
		if m["kind"] == "rafter" and m["spacing_mm"] != null:
			rafter_sp = float(m["spacing_mm"])
			rn = m["nominal"]
		if m["kind"] == "ridge":
			ridge = m["nominal"]
	var bolts: Dictionary = meta.get("anchor_bolts", {})
	var foot: Dictionary = meta.get("footing", {})
	return {
		"species": meta.get("species", "DF-L#2"), "width_ft": zs / MM_FT, "length_ft": xs / MM_FT, "wall_h_ft": wall_top / MM_FT,
		"loads": {"roof": "live", "psf": 20.0}, "wind_mph": int(meta.get("wind_mph", 115)), "exposure": meta.get("exposure", "B"), "seismic": meta.get("seismic", "A-B"),
		"walls": walls,
		"ceiling_joists": {"size": jn.replace(" PT", ""), "spacing_in": int(round(joist_sp / MM_IN)), "interior_bearing_wall": true},
		"rafters": {"size": rn, "spacing_in": int(round(rafter_sp / MM_IN)), "rise_per_12": float(meta.get("rise_per_12", 4.0)), "ridge": ridge, "tie": meta.get("tie", "none")},
		"sill": {"on": "slab", "lumber": "2x4", "bolt_dia_in": float(bolts.get("dia_in", 0.0)), "bolt_spacing_in": float(bolts.get("max_spacing_in", 999.0)),
			"bolt_from_end_in": float(bolts.get("max_end_in", 999.0))},
		"footing": {"type": "slab", "width_in": float(foot.get("width_in", 0.0)), "thickness_in": float(foot.get("thickness_in", 0.0)), "wall_in": 3.5, "soil_psf": int(meta.get("soil_psf", 1500))},
	}


## HouseCheck lines for the record, in report order. Walls marked braced=false skip the bracing line (HouseCheck.check is given a copy without them).
static func run(mj: Dictionary) -> Array:
	var h := from_members(mj)
	return HouseCheck.check(h)


## every line of the report: the check lines, then what is UNVERIFIED and what is not checked at all
static func report(mj: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var lines := run(mj)
	var nfail := 0
	var unv := 0
	for l in lines:
		out.append(l["text"])
		if not l["pass"]:
			nfail += 1
		if String(l["text"]).contains("UNVERIFIED"):
			unv += 1
	out.append("RESULT %d lines, %d FAIL, %d PASS, %d carry UNVERIFIED" % [lines.size(), nfail, lines.size() - nfail, unv])
	out.append("tables: " + HouseCheck.TABLES_SOURCE)
	out.append("not checked by Kine: " + "; ".join(PackedStringArray(HouseCheck.NOT_CHECKED)))
	return out


static func failing(mj: Dictionary) -> Array:
	var f := []
	for l in run(mj):
		if not l["pass"]:
			f.append(l["text"])
	return f


# ------------------------------------------------------------------ geometry: overlap of framing members

static func _poly_of(m: Dictionary) -> Array:
	var out := []
	if m.has("poly") and m["poly"] != null:
		for p in m["poly"]:
			out.append(Vector2(float(p[0]), float(p[1])))
	else:
		var b: Array = m["box"] if m.has("box") else m["box_mm"]
		out = [Vector2(b[2], b[1]), Vector2(b[5], b[1]), Vector2(b[5], b[4]), Vector2(b[2], b[4])]
	return out


static func _area(p: Array) -> float:
	var a := 0.0
	for i in p.size():
		var q: Vector2 = p[i]
		var r: Vector2 = p[(i + 1) % p.size()]
		a += q.x * r.y - r.x * q.y
	return a * 0.5


static func _inside(a: Vector2, b: Vector2, c: Vector2, p: Vector2) -> bool:
	var d1 := (b - a).cross(p - a)
	var d2 := (c - b).cross(p - b)
	var d3 := (a - c).cross(p - c)
	return d1 >= -1e-9 and d2 >= -1e-9 and d3 >= -1e-9


## ear clipping: triangles (counter-clockwise) of a simple polygon
static func triangulate(poly: Array) -> Array:
	var p := poly.duplicate()
	if _area(p) < 0.0:
		p.reverse()
	var tris := []
	var guard := 0
	while p.size() > 3 and guard < 500:
		guard += 1
		var cut := false
		for i in p.size():
			var a: Vector2 = p[(i + p.size() - 1) % p.size()]
			var b: Vector2 = p[i]
			var c: Vector2 = p[(i + 1) % p.size()]
			if (b - a).cross(c - b) <= 1e-9:
				continue
			var empty := true
			for q in p:
				if q != a and q != b and q != c and _inside(a, b, c, q):
					empty = false
					break
			if empty:
				tris.append([a, b, c])
				p.remove_at(i)
				cut = true
				break
		if not cut:
			p.remove_at(0)      # a collinear vertex: drop it
	if p.size() == 3 and absf(_area(p)) > 1e-9:
		tris.append([p[0], p[1], p[2]])
	return tris


## Sutherland-Hodgman: polygon `s` clipped by the convex counter-clockwise polygon `c`
static func clip(s: Array, c: Array) -> Array:
	var out := s
	for i in c.size():
		var a: Vector2 = c[i]
		var b: Vector2 = c[(i + 1) % c.size()]
		var inp := out
		out = []
		if inp.is_empty():
			break
		var prev: Vector2 = inp[inp.size() - 1]
		for cur in inp:
			var cs := (b - a).cross(cur - a)
			var ps := (b - a).cross(prev - a)
			if cs >= 0.0:
				if ps < 0.0:
					out.append(prev + (cur - prev) * (ps / (ps - cs)))
				out.append(cur)
			elif ps >= 0.0:
				out.append(prev + (cur - prev) * (ps / (ps - cs)))
			prev = cur
	return out


static func _prep(m: Dictionary) -> Dictionary:
	var b: Array = m["box"] if m.has("box") else m["box_mm"]
	return {"m": m, "b": b, "tris": triangulate(_poly_of(m))}


## volume (mm3) of the intersection of two prepared members
static func volume(a: Dictionary, b: Dictionary) -> float:
	var ba: Array = a["b"]
	var bb: Array = b["b"]
	var dx := minf(float(ba[3]), float(bb[3])) - maxf(float(ba[0]), float(bb[0]))
	var dy := minf(float(ba[4]), float(bb[4])) - maxf(float(ba[1]), float(bb[1]))
	var dz := minf(float(ba[5]), float(bb[5])) - maxf(float(ba[2]), float(bb[2]))
	if dx <= 1e-6 or dy <= 1e-6 or dz <= 1e-6:
		return 0.0
	var area := 0.0
	for ta in a["tris"]:
		for tb in b["tris"]:
			var r := clip(ta, tb)
			if r.size() >= 3:
				area += absf(_area(r))
	return dx * area


## [[name a, name b, mm3], ...] for every pair of framing members whose intersection exceeds `eps` (mm3)
static func overlaps(members: Array, eps := 1.0) -> Array:
	var P := []
	for m in members:
		if m["kind"] in FRAMING:
			P.append(_prep(m))
	var out := []
	for i in P.size():
		var a: Dictionary = P[i]
		var ba: Array = a["b"]
		for j in range(i + 1, P.size()):
			var b: Dictionary = P[j]
			var bb: Array = b["b"]
			if float(ba[3]) <= float(bb[0]) or float(bb[3]) <= float(ba[0]) or float(ba[4]) <= float(bb[1]) or float(bb[4]) <= float(ba[1]) or float(ba[5]) <= float(bb[2]) or float(bb[5]) <= float(ba[2]):
				continue
			var v := volume(a, b)
			if v > eps:
				out.append([a["m"]["name"], b["m"]["name"], v])
	return out


## a rafter's axis: the longest edge of its sketch polygon (z, y) in the plane normal to x, as a unit Vector3 (x, y, z); the ridge's axis: the long side of its box
static func rafter_axes(members: Array) -> Dictionary:
	var ridge := Vector3.ZERO
	var rafters := {}
	for m in members:
		var k: String = m["kind"]
		if k == "ridge":
			var b: Array = m["box"]
			var e := Vector3(float(b[3]) - float(b[0]), float(b[4]) - float(b[1]), float(b[5]) - float(b[2]))
			var ax := 0
			if e.y > e[ax]:
				ax = 1
			if e.z > e[ax]:
				ax = 2
			ridge = Vector3.ZERO
			ridge[ax] = 1.0
		elif k in ["rafter", "rafter_pair", "gable_rafter"] and m.has("poly") and m["poly"] != null:
			var p: Array = m["poly"]
			var best := 0.0
			var d := Vector2.ZERO
			for i in p.size():
				var q := Vector2(float(p[i][0]), float(p[i][1]))
				var r := Vector2(float(p[(i + 1) % p.size()][0]), float(p[(i + 1) % p.size()][1]))
				if (r - q).length() > best:
					best = (r - q).length()
					d = r - q
			d = d.normalized()
			rafters[m["name"]] = Vector3(0.0, d.y, d.x)
	return {"ridge": ridge, "rafters": rafters}
