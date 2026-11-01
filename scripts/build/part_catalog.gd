class_name PartCatalog
extends RefCounted
## FRIDAY 166 SEARCH PARTS BY SKETCH: the Parts library as a list of parts that can be built and seen from three sides. The silhouette of
## each (top, front, side) is computed once from the built solid and cached (outline_tools.gd); a drawn outline is compared with all of them
## by its scale- and rotation-free descriptor, and the best parts come back with a score (0 = the same shape, higher = less alike).

## [id, words, library category, template, params]; template "" = one of the builders below (nut / washer, which the library only
## makes beside a screw)
const ENTRIES := [
	["screw_m4", "Screw M4 x 16", "Screws", "screw", {"d": 4, "L": 16, "h": 0}],
	["screw_m6", "Screw M6 x 30", "Screws", "screw", {"d": 6, "L": 30, "h": 0}],
	["screw_flat", "Flat-head screw M5 x 20", "Screws", "screw", {"d": 5, "L": 20, "h": 2}],
	["rod_m8", "Threaded rod M8", "Screws", "rod", {"d": 8}],
	["nut_m5", "Hex nut M5", "Nuts", "", {"d": 5, "what": "nut"}],
	["nut_m6", "Hex nut M6", "Nuts", "", {"d": 6, "what": "nut"}],
	["washer_m5", "Washer M5", "Washers", "", {"d": 5, "what": "washer"}],
	["gear", "Gear", "Gears", "gear", {}],
	["rack", "Gear rack", "Gears", "rack", {}],
	["cam", "Cam and follower", "Gears", "cam", {}],
	["hinge", "Hinge", "Hinges", "hinge", {}],
	["bearing_608", "Bearing 608", "Bearings", "bearing", {"kind": 0}],
	["bearing_625", "Bearing 625", "Bearings", "bearing", {"kind": 1}],
	["spring", "Spring", "Springs", "spring", {}],
	["knob", "Knob", "Handles", "knob", {}],
	["drawer_pull", "Drawer pull", "Handles", "drawer_pull", {}],
	["d_handle", "D-handle", "Handles", "d_handle", {}],
	["grip", "Knurled grip", "Handles", "grip", {}],
	["wheel", "Wheel", "Wheels", "axwheel", {}],
	["castor", "Castor", "Wheels", "castor", {}],
	["bracket_l", "L-bracket", "Brackets", "bracket", {"kind": 1}],
	["bracket_t", "T-bracket", "Brackets", "bracket", {"kind": 2}],
	["bracket_corner", "Corner brace", "Brackets", "bracket", {"kind": 3}],
	["foot", "Rubber foot", "Clips and feet", "foot", {}],
	["clip", "Cable clip", "Clips and feet", "clip", {}],
	["snap", "Snap-fit clip", "Clips and feet", "snap", {}],
	["slot", "Zip-tie slot", "Clips and feet", "slot", {}],
]
const VIEWS := ["top", "front", "side"]
const LEVELS := [0.0, 0.05, 0.10, 0.17]   # the silhouette as it is, then fattened (a thin L-bracket meets a fat drawn L)
const VIEW_COST := 0.03                   # a view with half the biggest view's area costs half this
const LEVEL_COST := 0.012                 # each fattening step makes a match a little less sure

static var _cache := {}   # id -> Array of 3 descriptors (PackedFloat32Array; empty when that view has no outline)
static var _pen := {}     # id -> the cost of each view (a view that shows little of the part is a weak way to find it)
static var builds := 0    # how many parts were built to fill the cache (tests read it: a second search builds none)


static func ids() -> Array:
	var out: Array = []
	for e in ENTRIES:
		out.append(String(e[0]))
	return out


static func entry(id: String) -> Array:
	for e in ENTRIES:
		if String(e[0]) == id:
			return e
	return []


## the record of a catalog part (a fresh one each call)
static func make(id: String) -> Dictionary:
	var e := entry(id)
	if e.is_empty():
		return {}
	var t := String(e[3])
	var p: Dictionary = e[4]
	if t != "":
		return PartTemplates.make(t, p)
	return _builder(String(e[1]), p)


## a hex nut / a washer lying on the floor (ISO tables of part_templates.gd), as plain steps
static func _builder(title: String, p: Dictionary) -> Dictionary:
	var rec := Part.make(title)
	var fs: Array = []
	var d := clampi(int(p["d"]), 3, 6)
	if String(p["what"]) == "washer":
		var w: Array = PartTemplates.WASH_ISO[d]
		PartTemplates._ex(fs, PartTemplates._sk(fs, "top", [{"k": "circle", "c": [0.0, 0.0], "r": float(w[1]) * 0.5}]), "extrude", float(w[2]), "new")
		PartTemplates._ex(fs, PartTemplates._sk(fs, "top", [{"k": "circle", "c": [0.0, 0.0], "r": float(w[0]) * 0.5}]), "extrude", float(w[2]) + 2.0, "cut")
	else:
		var n: Array = PartTemplates.NUT_ISO[d]
		var R: float = float(n[0]) / sqrt(3.0)
		var hex := []
		for k in 6:
			hex.append(Vector2(R * cos(float(k) * PI / 3.0), R * sin(float(k) * PI / 3.0)))
		PartTemplates._ex(fs, PartTemplates._sk(fs, "top", PartTemplates._poly(hex)), "extrude", float(n[1]), "new")
		PartTemplates._ex(fs, PartTemplates._sk(fs, "top", [{"k": "circle", "c": [0.0, 0.0], "r": float(d) * 0.5}]), "extrude", float(n[1]) + 2.0, "cut")
	rec["features"] = fs
	rec["seq"] = fs.size()
	return rec


## the three descriptors (top, front, side) of one catalog part, built once
static func descriptors(id: String) -> Array:
	if _cache.has(id):
		return _cache[id]
	var out: Array = []
	var rec := make(id)
	if not rec.is_empty() and Part.available():
		builds += 1
		var areas: Array = []
		var faces: Array = Part.body_faces(rec, -1)
		for v in 3:
			var got := OutlineTools.silhouette_contours(faces, v, LEVELS)
			var cs: Array = got["contours"]
			var per: Array = []
			for i in LEVELS.size():
				var contour: PackedVector2Array = cs[i] if i < cs.size() else PackedVector2Array()
				per.append(OutlineTools.descriptor(contour) if contour.size() >= 3 else PackedFloat32Array())
			out.append(per)
			areas.append(float(got["area"]))
		var amax := 0.0
		for a in areas:
			amax = maxf(amax, float(a))
		var pen: Array = []
		for a in areas:
			pen.append(VIEW_COST * (1.0 - float(a) / amax) if amax > 0.0 else 0.0)
		_pen[id] = pen
	_cache[id] = out
	return out


## true when every part's silhouettes are cached (a search is then instant)
static func ready() -> bool:
	return _cache.size() >= ENTRIES.size()


static func clear_cache() -> void:
	_cache = {}
	_pen = {}


## the best n parts for a drawn outline (any size, any turn): [{"id", "name", "cat", "score", "view"}], best first.
## A part's score is its best view's distance.
static func search(drawn: PackedVector2Array, n := 6) -> Array:
	var q := OutlineTools.descriptor(OutlineTools.stroke_outline(drawn))
	var out: Array = []
	if q.is_empty():
		return out
	for e in ENTRIES:
		var best := INF
		var bv := -1
		var ds: Array = descriptors(String(e[0]))
		for v in ds.size():
			var per: Array = ds[v]
			for lv in per.size():
				var dd: PackedFloat32Array = per[lv]
				if dd.is_empty():
					continue
				var s := OutlineTools.distance(q, dd) + LEVEL_COST * float(lv) + float((_pen.get(String(e[0]), [0.0, 0.0, 0.0]) as Array)[v])
				if s < best:
					best = s
					bv = v
		if bv >= 0:
			out.append({"id": String(e[0]), "name": String(e[1]), "cat": String(e[2]), "score": best, "view": VIEWS[bv]})
	out.sort_custom(func(a, b): return float(a["score"]) < float(b["score"]))
	return out.slice(0, n)
