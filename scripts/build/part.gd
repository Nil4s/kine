class_name Part
extends RefCounted
## THE PART RECORD (EXPERT PART workspace, phase 1, Fusion 360 style): a Part is a TIMELINE, a list of FEATURES that are replayed through
## the CAD kernel (scripts/kcad.gd, KineCAD on Open CASCADE) into solids and a preview mesh. Plain JSON-able data, never a stored mesh:
## the scene file ("part", only when there is one), the undo snapshot and the tests hold the same dictionary. Sizes are MILLIMETRES in the record
## (what the user types); the kernel gets metres.
##   {"version": 1, "name": "Longsword", "seq": 3, "features": [
##     {"t": "sketch",  "id": "f1", "name": "Sketch1", "plane": "front", "ents": [...], "dims": [...]},
##     {"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 5.0, "both": false, "op": "new"|"join"|"cut"},
##     {"t": "revolve", "id": "f3", "name": "Revolve1", "sketch": "f4", "axis": "x"|"y", "deg": 360.0, "op": "join"},
##     {"t": "fillet",  "id": "f5", "name": "Fillet1", "body": 0, "r": 2.0, "edges": [{"p": [x, y, z], "q": [..], "d": [..]}]},
##     {"t": "chamfer", ... "dist": 1.0 ...},  {"t": "mirror", "id": ..., "plane": "front"|"top"|"right", "op": "join"},
##     extrude also has "taper": degrees (>0 narrows as it goes) and op "intersect" (keeps only the part inside the new solid);
##     {"t": "split", "id": ..., "plane": "front"|"top"|"right", "at": mm (offset along the plane's normal)} cuts EVERY body the plane crosses in two;
##     {"t": "shell", "id": ..., "body": N, "thick": mm, "open": "" | "+x" | "-x" | "+y" | "-y" | "+z" | "-z"} hollows body N with walls thick mm,
##     the planar face that points that way open ("" = no face open: a closed cavity),
##     {"t": "hinge", "id": ..., "name": "Hinge1", "body": 0, "o": [x, y, z] (mm), "axis": [x, y, z], "track": [[t_s, deg], ...]}]}
## A HINGE (C3) turns body N (its index when the hinge comes) about the axis through o. Its angle is a Curves channel (seconds, degrees), the
## same as a Kine curve sampled to a list. The timeline shows the rest pose (the hinge adds no solid); hinge_sweep() walks the curve and reports the
## first frame the moving body meets another body (a door against its stop).
## LOFT (E): {"t": "loft", "id", "name", "sketches": ["f1", "f4", ...] (2 or more, in order), "ruled": bool, "op": join|new|cut}: the kernel joins
## the profiles of those sketches into one solid (ruled = straight between them, else smooth). OFFSET PLANE (E): {"t": "plane", "id", "name",
## "from": "front"|"top"|"right", "mm": distance along its normal}. A sketch whose "plane" is a plane's id sits on that offset plane.
## SWEEP (GAP 6): {"t": "sweep", "id", "name", "profile": "f1" (a closed sketch), "path": "f4" (an OPEN chain sketch: lines, arcs and splines,
## each piece starting where the last one ended), "op": join|new|cut}: the profile is swept along the path. The path must start in the middle of the
## profile and leave it square to the profile's plane. Corners of the path are rounded (radius 1.5 x the profile's size, see sweep_path): the kernel's
## pipe along a path with a corner leaves its second leg open (volume = the first leg only), so the kernel gets ONE smooth curve.

## CANVAS (GAP 3, Fusion's Canvas): {"t": "canvas", "id", "name", "plane": "front"|"top"|"right" or an offset plane's id, "path" (the picture file),
## "w", "h" (picture pixels), "pts": [[px, py], [px, py]] (the two calibration points on the picture, y down), "dist" (mm between them), "at": [x, y]
## (mm, plane coordinates of the picture's top-left corner), "opacity" 0..1, "show" bool}. A picture is never a solid: replay() skips it.
## Sketch entities (plane coordinates in mm): {"k": "line", "a", "b"}, {"k": "rect", "a", "b"} (two corners), {"k": "circle", "c", "r"},
## {"k": "arc", "a", "m", "b"} (from a to b through m), {"k": "bspline", "pts": [[x, y], ...], "closed"} (a smooth curve through the points; a
## closed one joins the last point to the first). A dimension: {"id", "ent": index, "kind": "w" | "h" | "len" | "r", "mm", "name"}; the
## entities always hold the dimension's result (apply_dim writes it), so a rebuild needs nothing else.
## An EDGE IS PICKED BY ITS CENTRE: a fillet stores where the edge was (mm), where it was inside its body's bounding box (0..1 per axis) and its
## direction; a rebuild picks the edge that best matches the box position and direction, so the fillet follows when a sketch is dimensioned
## bigger and the ids of the new shape are different. No match = that step fails (its message in the result), the later steps carry on.
## APPEARANCE (GAP 5): {"t": "appear", "id", "name", "body": N, "preset": "Paint"|"Metal"|"Glass"|"Rubber"|"Plastic"|"Custom", "color": [r, g, b] (0..1),
## "rough": 0..1, "metal": 0..1, "alpha": 0..1 (below 1 = see-through)} paints body N from that step on (the record holds the numbers, a preset
## only names them). A body with no appear step gets its palette colour by index (LOOK_CHIPS), so the bodies of a split read as two.
## A split gives both halves the look of the body it cut. No DLL: available() is false, replay() answers with an empty result and every tool says why.
## PATTERN (GAP 30, Fusion's Pattern): {"t": "pattern", "id", "name", "body": N, "kind": "linear"|"circular", "count": copies INCLUDING the original (2..64),
## "mm" (linear: the spacing), "dir": "x"|"y"|"z" (linear: the direction), "axis": "x"|"y"|"z" (circular: the axis through the origin), "deg" (circular:
## the total angle; a full turn spreads the copies evenly, a smaller angle runs from the first copy to the last), "op": "join" (the copies fuse into body N)
## | "new" (each copy is a body of its own, with body N's look). Built from the kernel's translate / rotate (one shape per copy, not one fused shape).
## COMBINE (Fusion Combine): {"t": "combine", "id", "name", "target": N, "tools": [M, ...], "op": "join"|"cut"|"intersect", "keep": bool}: the target
## body joins, cuts or shares volume with each tool body in turn (the tools in order). The result takes the target's place in the body list; the tool
## bodies go (keep = true leaves them where they are, unchanged). Every other body keeps its place and its look, the target keeps its look.

const KCad := preload("res://scripts/kcad.gd")
const MM := 0.001
const VERSION := 1
const KINDS := ["sketch", "extrude", "revolve", "fillet", "chamfer", "mirror", "hinge", "split", "shell", "loft", "sweep", "plane", "canvas", "appear", "pattern", "combine"]
const PLANES := ["front", "top", "right"]
const OPS := ["join", "new", "cut", "intersect"]
const COMBINE_OPS := ["join", "cut", "intersect"]   # a combine step's op (the dialog's order: Join, Cut, Intersect)
const MATCH_MAX := 0.25   # an edge matches when (box-position distance + 0.5 x direction mismatch) is below this
const LOOK_CHIPS := [["Grey", Color("#bdc4d0")], ["Red", Color("#c0392b")], ["Blue", Color("#3a7bd5")], ["Yellow", Color("#f2c94c")], ["Green", Color("#4caf50")]]   # the colour chips; a body with no look takes chip (its index mod 5)
const LOOK_PRESETS := {"Paint": {"rough": 0.35, "metal": 0.0, "alpha": 1.0}, "Metal": {"rough": 0.25, "metal": 1.0, "alpha": 1.0}, "Glass": {"rough": 0.05, "metal": 0.0, "alpha": 0.4}, "Rubber": {"rough": 0.95, "metal": 0.0, "alpha": 1.0}, "Plastic": {"rough": 0.45, "metal": 0.0, "alpha": 1.0}}
const LOOK_DEFAULT := {"rough": 0.5, "metal": 0.15, "alpha": 1.0}   # the look a body has before any appear step (the old fixed grey)
const HIT_VOL := 1e-9     # m3 (1 mm3): an overlap this small is contact, not interference (the kernel's boolean noise is far below it)

static var force_off := false   # a test's "no DLL"


static func available() -> bool:
	return not force_off and KCad.available()


static func why_not() -> String:
	return "Part tools need the KineCAD kernel (the CAD DLL is missing: see native/CAD_BUILD.md)"


static func make(name := "Part") -> Dictionary:
	return {"version": VERSION, "name": name, "seq": 0, "features": []}


## a sketch plane: o (origin), x (right), n (normal), y = n x x (up on the sketch). Front = XY facing +Z, Top = XZ facing up (+v is -Z), Right = YZ facing +X
static func plane(name: String) -> Dictionary:
	var pl := {"o": Vector3.ZERO, "x": Vector3.RIGHT, "n": Vector3.BACK}
	if name == "top":
		pl = {"o": Vector3.ZERO, "x": Vector3.RIGHT, "n": Vector3.UP}
	elif name == "right":
		pl = {"o": Vector3.ZERO, "x": Vector3(0, 0, -1), "n": Vector3.RIGHT}
	pl["y"] = (pl["n"] as Vector3).cross(pl["x"] as Vector3)
	return pl


static func to_world(pl: Dictionary, p: Vector2) -> Vector3:
	return (pl["o"] as Vector3) + (pl["x"] as Vector3) * p.x * MM + (pl["y"] as Vector3) * p.y * MM


static func to_plane(pl: Dictionary, w: Vector3) -> Vector2:
	var d := w - (pl["o"] as Vector3)
	return Vector2(d.dot(pl["x"] as Vector3), d.dot(pl["y"] as Vector3)) / MM


static func v2(a: Variant) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func arr2(v: Vector2) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001)]


# ---------------------------------------------------------------- the record

static func index_of(rec: Dictionary, id: String) -> int:
	var fs: Array = rec.get("features", [])
	for i in fs.size():
		if String(fs[i].get("id", "")) == id:
			return i
	return -1


static func feature(rec: Dictionary, id: String) -> Dictionary:
	var i := index_of(rec, id)
	return rec["features"][i] if i >= 0 else {}


static func count_of(rec: Dictionary, t: String) -> int:
	var n := 0
	for f in rec.get("features", []):
		if f["t"] == t:
			n += 1
	return n


## a new feature with its id and its name ("Extrude2"), NOT yet in the list
static func new_feature(rec: Dictionary, t: String, fields := {}) -> Dictionary:
	rec["seq"] = int(rec.get("seq", 0)) + 1
	var f := {"t": t, "id": "f%d" % int(rec["seq"]), "name": "%s%d" % [t.capitalize(), count_of(rec, t) + 1]}
	f.merge(fields, true)
	return f


static func sketch_used(rec: Dictionary, id: String) -> bool:
	for f in rec.get("features", []):
		if String(f.get("sketch", "")) == id or (f.get("sketches", []) as Array).has(id) or String(f.get("profile", "")) == id or String(f.get("path", "")) == id:
			return true
	return false


## the plane a sketch sits on: a base plane's name, or an offset plane's id (its base plane moved along the normal by its mm)
static func resolve_plane(rec: Dictionary, name: String) -> Dictionary:
	if PLANES.has(name):
		return plane(name)
	var f := feature(rec, name)
	if String(f.get("t", "")) != "plane":
		return plane("front")
	var pl := plane(String(f.get("from", "front")))
	pl["o"] = (pl["o"] as Vector3) + (pl["n"] as Vector3) * float(f.get("mm", 0.0)) * MM
	return pl


## the plane's name in plain words ("Front plane", "Plane1 (20 mm from the Front plane)")
static func plane_words(rec: Dictionary, name: String) -> String:
	if PLANES.has(name):
		return "%s plane" % name.capitalize()
	var f := feature(rec, name)
	if String(f.get("t", "")) != "plane":
		return "plane"
	return "%s (%s mm from the %s plane)" % [f["name"], _short(float(f.get("mm", 0.0))), String(f.get("from", "front")).capitalize()]


## the sketch a new Extrude / Revolve takes: the newest one nothing has used yet, else the newest
static func profile_sketch(rec: Dictionary) -> String:
	var last := ""
	var fresh := ""
	for f in rec.get("features", []):
		if f["t"] == "sketch":
			last = String(f["id"])
			if not sketch_used(rec, last):
				fresh = last
	return fresh if fresh != "" else last


static func to_file(rec: Dictionary) -> Dictionary:
	return rec.duplicate(true)


## a file's record, or {} when it is not one; unknown feature kinds are dropped, numbers made finite
static func from_file(d: Variant) -> Dictionary:
	if not (d is Dictionary) or not (d as Dictionary).get("features") is Array:
		return {}
	var out := make(String((d as Dictionary).get("name", "Part")))
	out["seq"] = int((d as Dictionary).get("seq", 0))
	for f in (d as Dictionary)["features"]:
		if f is Dictionary and KINDS.has(String(f.get("t", ""))) and String(f.get("id", "")) != "":
			out["features"].append((f as Dictionary).duplicate(true))
			out["seq"] = maxi(int(out["seq"]), int(String(f["id"]).trim_prefix("f")))
	if (d as Dictionary).get("easy") is Dictionary and (d as Dictionary)["easy"].has("t"):
		out["easy"] = (d as Dictionary)["easy"].duplicate(true)   # EASY PART: the template's numbers (scripts/build/part_templates.gd)
	return out if not out["features"].is_empty() else {}


# ---------------------------------------------------------------- sketch entities and dimensions

static func apply_dim(ents: Array, d: Dictionary) -> void:
	var i := int(d.get("ent", -1))
	if i < 0 or i >= ents.size():
		return
	var e: Dictionary = ents[i]
	var mm := float(d["mm"])
	match String(d["kind"]):
		"w":
			if e["k"] == "rect":
				var a := v2(e["a"])
				var b := v2(e["b"])
				e["b"] = arr2(Vector2(a.x + (1.0 if b.x >= a.x else -1.0) * mm, b.y))
		"h":
			if e["k"] == "rect":
				var a := v2(e["a"])
				var b := v2(e["b"])
				e["b"] = arr2(Vector2(b.x, a.y + (1.0 if b.y >= a.y else -1.0) * mm))
		"len":
			if e["k"] == "line":
				var a := v2(e["a"])
				var dir := (v2(e["b"]) - a)
				dir = dir.normalized() if dir.length() > 1e-9 else Vector2.RIGHT
				e["b"] = arr2(a + dir * mm)
		"r":
			if e["k"] == "circle":
				e["r"] = mm


## what a dimension measures now (mm)
static func measure(e: Dictionary, kind: String) -> float:
	match kind:
		"w":
			return absf(v2(e["b"]).x - v2(e["a"]).x)
		"h":
			return absf(v2(e["b"]).y - v2(e["a"]).y)
		"len":
			return v2(e["a"]).distance_to(v2(e["b"]))
		"r":
			return float(e["r"])
	return 0.0


## C2: "=forearm+4", "=thigh*0.6", "=forearm*1.2-2 mm" -> {"m": segment, "k": factor, "add": mm}; {} when the text is not a bind
static func parse_bind(t: String) -> Dictionary:
	var rx := RegEx.new()
	rx.compile("^=\\s*([a-z_]+)\\s*(\\*\\s*([0-9]*\\.?[0-9]+))?\\s*(([+-])\\s*([0-9]*\\.?[0-9]+))?\\s*(mm)?$")
	var mt := rx.search(t.strip_edges().to_lower())
	if mt == null:
		return {}
	var k := float(mt.get_string(3)) if mt.get_string(3) != "" else 1.0
	var add := float(mt.get_string(6)) if mt.get_string(6) != "" else 0.0
	if mt.get_string(5) == "-":
		add = -add
	return {"m": mt.get_string(1), "k": k, "add": add}


## C2: the text a bind is typed as (the dimension's field and label show it)
static func bind_text(bind: Dictionary) -> String:
	var k := float(bind.get("k", 1.0))
	var add := float(bind.get("add", 0.0))
	var s := "=%s" % String(bind.get("m", ""))
	if k != 1.0:
		s += "*%s" % _short(k)
	if add != 0.0:
		s += "%s%s" % ["+" if add > 0.0 else "-", _short(absf(add))]
	return s


static func _short(x: float) -> String:   # 4.0 -> "4", 0.6 -> "0.6"
	return ("%.3f" % x).rstrip("0").rstrip(".")


## C2: a bound dimension's value in mm from the body's measures (m, Proportions.measures_of). {"mm", "err"}:
## no body, or no such measure, is an ERROR (never a default)
static func bound_mm(bind: Dictionary, measures: Variant) -> Dictionary:
	if not (measures is Dictionary):
		return {"mm": 0.0, "err": "it reads the body, and there is no body to read"}
	var m := String(bind.get("m", ""))
	if not (measures as Dictionary).has(m):
		return {"mm": 0.0, "err": "the body has no measure called %s" % m}
	var mm := float((measures as Dictionary)[m]) / MM * float(bind.get("k", 1.0)) + float(bind.get("add", 0.0))
	if mm <= 0.0:
		return {"mm": 0.0, "err": "%s gives %s mm, which is not a size" % [bind_text(bind), snappedf(mm, 0.1)]}
	return {"mm": mm, "err": ""}


## C2: a copy of the sketch with its bound dimensions set from the body; err = the first one that cannot be read
static func resolved_sketch(sk: Dictionary, measures: Variant) -> Dictionary:
	var out := sk.duplicate(true)
	for d in out.get("dims", []):
		if not (d as Dictionary).has("bind"):
			continue
		var r := bound_mm((d as Dictionary)["bind"], measures)
		if r["err"] != "":
			return {"sk": out, "err": "%s: %s" % [d.get("name", "dimension"), r["err"]]}
		d["mm"] = r["mm"]
		apply_dim(out["ents"], d)
	return {"sk": out, "err": ""}


## C2: the record's bound sketches take the body's sizes now (the sketch on screen shows what the solid is made of).
## A sketch that cannot be read keeps its last numbers here: its error is the replay's (never a default)
static func refresh_bound(rec: Dictionary, measures: Variant) -> void:
	for f in rec.get("features", []):
		if String(f.get("t", "")) != "sketch" or not f.has("dims"):
			continue
		var bound := false
		for d in f["dims"]:
			bound = bound or (d as Dictionary).has("bind")
		if not bound:
			continue
		var rs := resolved_sketch(f, measures)
		if rs["err"] == "":
			f["ents"] = rs["sk"]["ents"]
			f["dims"] = rs["sk"]["dims"]


## sets (or adds) the dimension of entity `ent` and kind, and writes its result into the entity. bind {} = a plain size
static func set_dim(sk: Dictionary, ent: int, kind: String, mm: float, bind := {}) -> void:
	if not sk.has("dims"):
		sk["dims"] = []
	var dims: Array = sk["dims"]
	for d in dims:
		if int(d["ent"]) == ent and d["kind"] == kind:
			d["mm"] = mm
			if bind.is_empty():
				d.erase("bind")
			else:
				d["bind"] = bind.duplicate()
			apply_dim(sk["ents"], d)
			return
	var d := {"id": "d%d" % (dims.size() + 1), "ent": ent, "kind": kind, "mm": mm}
	if not bind.is_empty():
		d["bind"] = bind.duplicate()
	var word: String = {"w": "width", "h": "height", "len": "length", "r": "radius"}[kind]
	var same := 0
	for o in dims:
		if String(o["name"]).begins_with(word):
			same += 1
	d["name"] = word if same == 0 else "%s%d" % [word, same + 1]
	dims.append(d)
	apply_dim(sk["ents"], d)


## the kernel items of the entities (metres)
static func items_of(ents: Array) -> Array:
	var out := []
	for e in ents:
		match String(e["k"]):
			"line":
				out.append(KCad.line(v2(e["a"]) * MM, v2(e["b"]) * MM))
			"rect":
				var a := v2(e["a"]) * MM
				var b := v2(e["b"]) * MM
				out.append_array(KCad.polygon(PackedVector2Array([a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)])))
			"circle":
				out.append(KCad.circle(v2(e["c"]) * MM, float(e["r"]) * MM))
			"arc":
				out.append(KCad.arc(v2(e["a"]) * MM, v2(e["m"]) * MM, v2(e["b"]) * MM))
			"bspline":
				if (e.get("pts", []) as Array).size() >= 3:
					out.append(spline_item(e))
	return out


## a spline entity as a kernel item (metres); items_of leaves out one with fewer than 3 points (no curve)
## the kernel gets the curve the user SEES: the kernel's own interpolating B-spline through the clicked points alone bulged
## away from the drawn curve (+13 percent area on a 5-point ring), so it interpolates SPLINE_KERNEL_STEPS samples per span of it
const SPLINE_KERNEL_STEPS := 4

static func spline_item(e: Dictionary) -> Dictionary:
	var closed := bool(e.get("closed", false))
	var c := spline_curve(e.get("pts", []), closed, SPLINE_KERNEL_STEPS)
	if closed and c.size() > 1:
		c.resize(c.size() - 1)   # a periodic curve: the first point is not repeated
	var pts := PackedVector2Array()
	for q in c:
		pts.append(q * MM)
	return KCad.bspline(pts, closed)


## a smooth curve (mm) through the points (Catmull-Rom: it passes through each point); steps samples per span; closed repeats the
## first point at the end. The sketch draws this curve and the kernel is given it (spline_item)
static func spline_curve(pts: Array, closed: bool, steps := 16) -> PackedVector2Array:
	var P: Array = []
	for q in pts:
		P.append(v2(q))
	var n := P.size()
	var out := PackedVector2Array()
	if n < 2:
		return out
	for i in (n if closed else n - 1):
		var p0: Vector2 = P[(i - 1 + n) % n] if closed else P[maxi(i - 1, 0)]
		var p1: Vector2 = P[i]
		var p2: Vector2 = P[(i + 1) % n] if closed else P[i + 1]
		var p3: Vector2 = P[(i + 2) % n] if closed else P[mini(i + 2, n - 1)]
		for k in steps:
			var t := float(k) / float(steps)
			out.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	out.append(P[0] if closed else P[n - 1])
	return out


# ---------------------------------------------------------------- replay: features -> solids -> mesh

## Replays features 0..upto (-1 = all). want: {"edges": true} also lists every edge of the result for picking; {"props": true} the
## mass properties of each body (PartWeapon). Answers
## {"mesh": ArrayMesh or null, "volume": m3 (all bodies), "bodies": n, "volumes": [m3 each], "errors": {feature id: message}, "edges": [...], "aabb": AABB, "props": [...]}.
## Every shape made here is released before it returns.
static func replay(rec: Dictionary, upto := -1, want := {}) -> Dictionary:
	var res := {"mesh": null, "volume": 0.0, "bodies": 0, "volumes": [], "errors": {}, "edges": [], "aabb": AABB(), "props": [], "looks": [], "body_looks": []}
	if not available():
		return res
	var feats: Array = rec.get("features", [])
	var n := feats.size() if upto < 0 else mini(upto + 1, feats.size())
	var bodies: Array = []
	var looks: Array = []   # APPEARANCE: one look per body (null = the default for its index), kept beside bodies
	var errs: Dictionary = res["errors"]
	var sketches := {}
	for i in n:
		var f: Dictionary = feats[i]
		var id := String(f["id"])
		look_fit(looks, bodies.size())
		match String(f["t"]):
			"sketch":
				var rs := resolved_sketch(f, want.get("body", null))   # C2: bound dimensions read the body given (none = an error)
				rs["sk"]["_pl"] = resolve_plane(rec, String(f.get("plane", "front")))   # transient: the replay's own copy of the sketch's plane
				sketches[id] = rs["sk"]
				if rs["err"] != "":
					errs[id] = rs["err"]
					sketches[id] = {}   # a sketch that cannot be read makes no solid (never its stored numbers)
			"extrude", "revolve":
				var sk: Dictionary = sketches.get(String(f.get("sketch", "")), {})
				if sk.is_empty():
					errs[id] = String(errs.get(String(f.get("sketch", "")), "its sketch is gone"))
					continue
				var solid := _solid(f, sk)
				if solid == 0:
					errs[id] = KCad.last_error()
					continue
				var e := _combine(bodies, solid, String(f.get("op", "join")))
				if e != "":
					errs[id] = e
			"loft":   # E: the picked profiles, in order, through the kernel's loft
				var le := _loft(bodies, f, sketches)
				if le != "":
					errs[id] = le
			"sweep":   # GAP 6: a closed profile along an open path (its own functions: _sweep, sweep_path)
				var swe := _sweep(bodies, f, sketches)
				if swe != "":
					errs[id] = swe
			"pattern":   # GAP 30: copies of body N (its own function: _pattern)
				var pe := _pattern(bodies, looks, f)
				if pe != "":
					errs[id] = pe
			"fillet", "chamfer":
				var e := _edge_op(bodies, f)
				if e != "":
					errs[id] = e
			"split", "shell":   # the record's split / shell steps (their own functions: _split, _shell)
				var e := _split(bodies, f, looks) if String(f["t"]) == "split" else _shell(bodies, f)
				if e != "":
					errs[id] = e
			"mirror":
				if bodies.is_empty():
					errs[id] = "there is nothing to mirror"
					continue
				var pl := plane(String(f.get("plane", "right")))
				var u: int = KCad.mirror_join(bodies[-1], Vector3.ZERO, pl["n"])
				if u == 0:
					errs[id] = KCad.last_error()
				else:
					KCad.release(bodies[-1])
					bodies[-1] = u
			"appear":   # APPEARANCE: the body's look from this step on (its own numbers; no kernel)
				var ai := int(f.get("body", -1))
				if ai < 0 or ai >= bodies.size():
					errs[id] = "there is no body %d to paint" % ai
				else:
					looks[ai] = look_of(f)
			"combine":   # COMBINE: its own function (_combine_step): the target and the tools become one body list again
				var ce := _combine_step(bodies, looks, f)
				if ce != "":
					errs[id] = ce
			"hinge":   # C3: the rest pose is the timeline's; the swing is hinge_sweep's
				var hb := int(f.get("body", -1))
				if hb < 0 or hb >= bodies.size():
					errs[id] = "there is no body %d to hinge" % hb
	if want.has("pose"):   # the view of a hinge mid-swing (PartUI's Play): that body turned, the rest as it is
		var pz: Dictionary = want["pose"]
		for k in n:
			var hf: Dictionary = feats[k]
			var hbi := int(hf.get("body", -1))
			if String(hf["id"]) == String(pz.get("f", "")) and String(hf["t"]) == "hinge" and hbi >= 0 and hbi < bodies.size():
				var sw := _swing(int(bodies[hbi]), _pivot(hf), _axis(hf), deg_to_rad(float(pz.get("deg", 0.0))))
				if sw != 0:
					KCad.release(bodies[hbi])
					bodies[hbi] = sw
	look_fit(looks, bodies.size())
	var mesh := ArrayMesh.new()
	for b in bodies:
		var v := KCad.volume(b)
		res["volumes"].append(v)
		res["volume"] = float(res["volume"]) + v
		if want.get("props", false):
			res["props"].append(KCad.mass_properties(b))   # {volume, area, center, inertia} per body, density 1 (PartWeapon)
		var tm := KCad.tessellate(b, 0.0003, 0.25)
		if tm != null and tm.get_surface_count() > 0:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tm.surface_get_arrays(0))
			res["looks"].append(look_at(looks, bodies.find(b)))   # one surface, one look (the view paints each surface)
		if want.get("edges", false):
			var es := KCad.edges(b)
			var bb := _bbox(es)
			for ed in es:
				res["edges"].append({"c": ed["center"], "a": ed["a"], "b": ed["b"], "d": ed["dir"], "len": ed["length"], "body": bodies.find(b), "q": _norm(ed["center"], bb)})
	res["bodies"] = bodies.size()
	for bi in bodies.size():
		res["body_looks"].append(look_at(looks, bi))
	if mesh.get_surface_count() > 0:
		res["mesh"] = mesh
		res["aabb"] = mesh.get_aabb()
	if want.get("keep", false):   # the caller owns the solids (vehicle.gd: intersect tests); release them with KCad.release
		res["ids"] = bodies
	else:
		for b in bodies:
			KCad.release(b)
	return res


## C3: the hinge's swing, sampled at fps. Replays the features before the hinge, turns its body about the hinge axis by the curve at each
## frame and intersects it with every other body. Answers {"ok": true, "frames", "first" (the first frame that overlaps, -1 = never),
## "first_s", "deg_first", "hit_frames" (how many frames overlap), "secs" (the run, replay included), "pairs", "red", "red_text"}, or {"ok": false, "why"}.
## MUST NOT TOUCH (C3 collision): the hinge's "clear" list holds body pairs [a, b] (indices as the hinge finds them). Per frame each pair gets a
## distance in mm: the smallest gap between the two solids' triangles, or -1 when the kernel says they overlap (touching; the depth is not
## measured). "pairs" = [{"a", "b", "dist" (mm per frame), "min" (mm, -1 if any frame overlaps), "touch" (frames with dist < 0)}], "red" = the
## frames where any pair touches (the timeline's red frames), "red_text" = the same in plain words. No pair chosen: "red" is empty.
static func hinge_sweep(rec: Dictionary, hinge_id: String, fps := 25.0) -> Dictionary:
	if not available():
		return {"ok": false, "why": why_not()}
	var feats: Array = rec.get("features", [])
	var hi := -1
	for i in feats.size():
		if String(feats[i]["id"]) == hinge_id and String(feats[i]["t"]) == "hinge":
			hi = i
	if hi < 0:
		return {"ok": false, "why": "there is no hinge %s" % hinge_id}
	var f: Dictionary = feats[hi]
	var track: Array = f.get("track", [])
	if track.is_empty() or hi == 0:
		return {"ok": false, "why": "the hinge has no body or no curve"}
	var t0 := Time.get_ticks_usec()
	var ids: Array = replay(rec, hi - 1, {"keep": true}).get("ids", [])
	var bi := int(f.get("body", -1))
	if bi < 0 or bi >= ids.size():
		for b in ids:
			KCad.release(b)
		return {"ok": false, "why": "there is no body %d to hinge" % bi}
	for p in f.get("clear", []):
		var pa := int(p[0])
		var pb := int(p[1])
		if pa < 0 or pb < 0 or pa >= ids.size() or pb >= ids.size() or pa == pb:
			for b in ids:
				KCad.release(b)
			return {"ok": false, "why": "the must-not-touch pair %d and %d: there is no such body" % [pa, pb]}
	var pivot := _pivot(f)
	var axis := _axis(f)
	var rest: Array = []
	for j in ids.size():
		if j != bi:
			rest.append(ids[j])
	var pairs: Array = []
	for p in f.get("clear", []):
		pairs.append({"a": int(p[0]), "b": int(p[1]), "dist": PackedFloat32Array(), "min": -1.0, "touch": []})
	var static_tris := {}   # body index -> triangles (metres), tessellated once for the bodies that do not move
	for j in ids.size():
		if j != bi:
			static_tris[j] = _tris_of(int(ids[j]))
	var n := int(floor(float(track[-1][0]) * fps + 1e-6)) + 1
	var out := {"ok": true, "frames": n, "first": -1, "first_s": -1.0, "deg_first": 0.0, "hit_frames": 0, "secs": 0.0}
	var red := {}
	for i in n:
		var t := float(i) / fps
		var deg := float(Curves.eval(track, t))
		var m := _swing(int(ids[bi]), pivot, axis, deg_to_rad(deg))
		var hit := false
		var bad := KCad.last_error() if m == 0 else ""
		for r in rest:
			var c := KCad.intersect(m, int(r)) if m != 0 else 0
			if m != 0 and c == 0:
				bad = KCad.last_error()   # a kernel failure is an error, never a clear frame
			elif c != 0 and KCad.volume(c) > HIT_VOL:
				hit = true
			if c != 0:
				KCad.release(c)
		var moving_tris := PackedVector3Array()
		if m != 0:
			moving_tris = _tris_of(m)
			if moving_tris.is_empty() and bad == "":
				bad = "could not tessellate the moving body"
		for pr in pairs:
			if bad != "":
				break
			var sa: int = m if int(pr["a"]) == bi else int(ids[int(pr["a"])])
			var sb: int = m if int(pr["b"]) == bi else int(ids[int(pr["b"])])
			var ta: PackedVector3Array = moving_tris if int(pr["a"]) == bi else static_tris[int(pr["a"])]
			var tb: PackedVector3Array = moving_tris if int(pr["b"]) == bi else static_tris[int(pr["b"])]
			var c2 := KCad.intersect(sa, sb) if m != 0 else 0
			var d := 0.0
			if m != 0 and c2 == 0:
				bad = KCad.last_error()
			elif c2 != 0 and KCad.volume(c2) > HIT_VOL:
				d = -1.0   # overlap: touching, the depth is not measured
			else:
				d = _tri_dist(ta, tb) * 1000.0
			if c2 != 0:
				KCad.release(c2)
			var dl: PackedFloat32Array = pr["dist"]
			dl.append(d)
			pr["dist"] = dl
			if d < 0.0:
				var tl: Array = pr["touch"]
				tl.append(i)
				pr["touch"] = tl
				red[i] = true
			if float(pr["min"]) < 0.0 or (d >= 0.0 and d < float(pr["min"])):
				pr["min"] = d
		KCad.release(m)
		if bad != "":
			for b in ids:
				KCad.release(b)
			return {"ok": false, "why": "frame %d: %s" % [i, bad]}
		if hit:
			out["hit_frames"] = int(out["hit_frames"]) + 1
			if int(out["first"]) < 0:
				out["first"] = i
				out["first_s"] = t
				out["deg_first"] = deg
	for b in ids:
		KCad.release(b)
	var reds: Array = red.keys()
	reds.sort()
	out["pairs"] = pairs
	out["red"] = reds
	out["red_text"] = _runs_text(reds, fps)
	out["secs"] = float(Time.get_ticks_usec() - t0) * 1e-6
	return out


## C3: a hinge's pivot (metres) and unit axis
static func _pivot(f: Dictionary) -> Vector3:
	return Vector3(float(f["o"][0]), float(f["o"][1]), float(f["o"][2])) * MM


static func _axis(f: Dictionary) -> Vector3:
	return Vector3(float(f["axis"][0]), float(f["axis"][1]), float(f["axis"][2])).normalized()


## C3: the triangles (metres) of every body at upto, in body order (the picking of PartUI's hinge); the solids are released
static func body_faces(rec: Dictionary, upto := -1) -> Array:
	var out: Array = []
	if not available():
		return out
	for b in replay(rec, upto, {"keep": true}).get("ids", []):
		out.append(_tris_of(int(b)))
		KCad.release(int(b))
	return out


## C3 MUST NOT TOUCH: the body pair [a, b] goes on the hinge's "clear" list (on = true) or off it. Stored with a < b, once.
## Answers "" or why not. One call is one undo step for the caller.
static func clear_pair_set(rec: Dictionary, hinge_id: String, a: int, b: int, on := true) -> String:
	var fi := index_of(rec, hinge_id)
	if fi < 0 or String(rec["features"][fi]["t"]) != "hinge":
		return "there is no hinge %s" % hinge_id
	if a < 0 or b < 0 or a == b:
		return "a pair needs two different bodies"
	var lo := mini(a, b)
	var hi := maxi(a, b)
	var f: Dictionary = rec["features"][fi]
	var kept: Array = []
	for p in f.get("clear", []):
		if not (int(p[0]) == lo and int(p[1]) == hi):
			kept.append(p)
	if on:
		kept.append([lo, hi])
	f["clear"] = kept
	return ""


## the pairs on a hinge's list, as [a, b] body indices
static func clear_pairs(rec: Dictionary, hinge_id: String) -> Array:
	var fi := index_of(rec, hinge_id)
	if fi < 0:
		return []
	return (rec["features"][fi] as Dictionary).get("clear", []).duplicate(true)


## "frames 6-75" / "frames 3, 5-7" from a sorted frame list at fps: the plain words for the timeline's red frames ("" = none)
static func _runs_text(frames: Array, fps: float) -> String:
	if frames.is_empty():
		return ""
	var parts: Array = []
	var s := int(frames[0])
	var p := s
	for k in range(1, frames.size() + 1):
		var cur := int(frames[k]) if k < frames.size() else -99
		if cur == p + 1:
			p = cur
			continue
		parts.append(str(s) if s == p else "%d-%d" % [s, p])
		if k < frames.size():
			s = cur
			p = cur
	var word := "frame" if frames.size() == 1 else "frames"
	return "%s %s (%.2f s to %.2f s)" % [word, ", ".join(parts), float(frames[0]) / fps, float(frames[-1]) / fps]


## a body's triangles in metres (flat triples), from its tessellation at the sweep's deflection
static func _tris_of(id: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var tm := KCad.tessellate(id, 0.0003, 0.25)
	if tm == null:
		return out
	for s in tm.get_surface_count():
		var arr := tm.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx == null:
			out.append_array(verts)
		else:
			for k in (idx as PackedInt32Array):
				out.append(verts[k])
	return out


## the smallest distance (metres) between two triangle soups; a triangle pair is skipped when its boxes are farther apart than the best so far
static func _tri_dist(A: PackedVector3Array, B: PackedVector3Array) -> float:
	var best := INF
	if A.is_empty() or B.is_empty():
		return best
	for i in range(0, A.size(), 3):
		var ta := AABB(A[i], Vector3.ZERO).expand(A[i + 1]).expand(A[i + 2])
		for j in range(0, B.size(), 3):
			var tb := AABB(B[j], Vector3.ZERO).expand(B[j + 1]).expand(B[j + 2])
			if best < INF and not ta.grow(best).intersects(tb):
				continue
			best = minf(best, _tri_tri(A[i], A[i + 1], A[i + 2], B[j], B[j + 1], B[j + 2]))
	return best


static func _tri_tri(a0: Vector3, a1: Vector3, a2: Vector3, b0: Vector3, b1: Vector3, b2: Vector3) -> float:
	var d := INF
	for p in [a0, a1, a2]:
		d = minf(d, p.distance_to(_closest_on_tri(p, b0, b1, b2)))
	for q in [b0, b1, b2]:
		d = minf(d, q.distance_to(_closest_on_tri(q, a0, a1, a2)))
	var ea := [[a0, a1], [a1, a2], [a2, a0]]
	var eb := [[b0, b1], [b1, b2], [b2, b0]]
	for x in ea:
		for y in eb:
			d = minf(d, _seg_seg(x[0], x[1], y[0], y[1]))
	return d


## the point of triangle abc nearest p (Ericson, Real-Time Collision Detection 5.1.5)
static func _closest_on_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var denom := 1.0 / (va + vb + vc)
	return a + ab * (vb * denom) + ac * (vc * denom)


## the distance between two segments (Ericson 5.1.9)
static func _seg_seg(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	var eps := 1e-12
	if a <= eps and e <= eps:
		pass
	elif a <= eps:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= eps:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			s = clampf((b * f - c * e) / denom, 0.0, 1.0) if denom > eps else 0.0
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)


## a body turned about a hinge: the kernel rotates about the origin only, so the body goes to the origin, turns and comes back
static func _swing(id: int, pivot: Vector3, axis: Vector3, radians: float) -> int:
	var a := KCad.translate(id, -pivot)
	var b := KCad.rotate(a, axis, radians)
	KCad.release(a)
	var c := KCad.translate(b, pivot)
	KCad.release(b)
	return c


static func _solid(f: Dictionary, sk: Dictionary) -> int:
	var pl: Dictionary = sk["_pl"] if sk.has("_pl") else plane(String(sk.get("plane", "front")))
	var face := KCad.sketch_face(items_of(sk["ents"]), pl["o"], pl["x"], pl["n"])
	if face == 0:
		return 0
	var s := 0
	if f["t"] == "extrude":
		s = KCad.extrude(face, float(f["dist"]) * MM, bool(f.get("both", false)), deg_to_rad(float(f.get("taper", 0.0))))
	else:
		var axis: Vector3 = pl["x"] if String(f.get("axis", "x")) == "x" else pl["y"]
		s = KCad.revolve(face, pl["o"], axis, deg_to_rad(float(f.get("deg", 360.0))))
	KCad.release(face)
	return s


## E LOFT: every picked sketch becomes a profile face (on its own plane), the kernel lofts them in order; the solid goes in as the op says.
## "" or the failure message
static func _loft(bodies: Array, f: Dictionary, sketches: Dictionary) -> String:
	var ids: Array = f.get("sketches", [])
	if ids.size() < 2:
		return "a loft needs two or more sketches"
	var faces := PackedInt32Array()
	for sid in ids:
		var sk: Dictionary = sketches.get(String(sid), {})
		if sk.is_empty():
			for fc in faces:
				KCad.release(fc)
			return "its sketch %s is gone or cannot be read" % String(sid)
		var pl: Dictionary = sk.get("_pl", plane(String(sk.get("plane", "front"))))
		var face := KCad.sketch_face(items_of(sk["ents"]), pl["o"], pl["x"], pl["n"])
		if face == 0:
			for fc in faces:
				KCad.release(fc)
			return "%s is not a closed profile" % String(sk.get("name", sid))
		faces.append(face)
	var solid := KCad.loft(faces, bool(f.get("ruled", true)), true)
	for fc in faces:
		KCad.release(fc)
	if solid == 0:
		return KCad.last_error()
	return _combine(bodies, solid, String(f.get("op", "join")))

## GAP 6 SWEEP: the path sketch as kernel items (lines, arcs, splines) in its sketch plane, one connected chain. A corner between two lines or
## arcs (a kink) is rounded with a fillet arc of radius rc, tangent to both pieces: the kernel's pipe along a path with a kink leaves its second
## leg open (volume = the first leg only), a smooth path is exact. A corner next to a spline is an error (make it smooth).
const SWEEP_CORNER := 0.01    # radians: a turn smaller than this is not a corner
const SWEEP_TOL := 0.01       # mm: pieces that must join end to end

## Answers {"err": "" or the message, "items": kernel items (metres), "len": mm, "start": mm, "dir": 2D travel direction at the start}.
static func sweep_path(ents: Array, rc: float) -> Dictionary:
	var P: Array = []
	for e in ents:
		match String(e["k"]):
			"line":
				var la := v2(e["a"])
				var lb := v2(e["b"])
				if la.distance_to(lb) < SWEEP_TOL:
					return {"err": "a line in the path has no length"}
				P.append({"k": "line", "a": la, "b": lb})
			"arc":
				var g := _arc_geom(v2(e["a"]), v2(e["m"]), v2(e["b"]))
				if g.is_empty():
					return {"err": "an arc in the path has no curve (its three points lie on a line)"}
				P.append(g)
			"bspline":
				if (e.get("pts", []) as Array).size() < 2:
					return {"err": "a spline in the path needs two or more points"}
				P.append({"k": "spline", "curve": spline_curve(e.get("pts", []), false, 16), "item": spline_item(e)})
			_:
				return {"err": "the path takes lines, arcs and splines only (not %s)" % String(e["k"])}
	for p in P:
		_fill_ends(p)
	for i in range(1, P.size()):
		var gap: float = (P[i - 1]["b"] as Vector2).distance_to(P[i]["a"])
		if gap > SWEEP_TOL:
			return {"err": "the path pieces do not join end to end (a gap of %.2f mm)" % gap}
	var i := 0
	while i < P.size() - 1:
		var u: Vector2 = P[i]["t1"]
		var w: Vector2 = P[i + 1]["t0"]
		var th := acos(clampf(u.dot(w), -1.0, 1.0))
		if th >= SWEEP_CORNER:
			if P[i]["k"] == "spline" or P[i + 1]["k"] == "spline":
				return {"err": "a corner next to a spline: make the spline join its neighbour smoothly"}
			var t := rc * tan(th / 2.0)
			if float(P[i]["len"]) < t * 1.001 or float(P[i + 1]["len"]) < t * 1.001:
				return {"err": "a corner of the path needs a piece of %.1f mm or more beside it" % t}
			_trim(P[i], false, t)
			_trim(P[i + 1], true, t)
			var left := u.x * w.y - u.y * w.x > 0.0
			var nl := Vector2(-u.y, u.x) if left else Vector2(u.y, -u.x)
			var cen: Vector2 = (P[i]["b"] as Vector2) + nl * rc
			var s0 := ((P[i]["b"] as Vector2) - cen).angle()
			var dl := fposmod(((P[i + 1]["a"] as Vector2) - cen).angle() - s0, TAU)
			if not left:
				dl -= TAU
			var fil := {"k": "arc", "c": cen, "R": rc, "s": s0, "ds": dl}
			_fill_ends(fil)
			P.insert(i + 1, fil)
		i += 1
	var items := []
	var total := 0.0
	for p in P:
		total += float(p["len"])
		match String(p["k"]):
			"line":
				items.append(KCad.line((p["a"] as Vector2) * MM, (p["b"] as Vector2) * MM))
			"arc":
				items.append(KCad.arc((p["a"] as Vector2) * MM, _arc_mid(p) * MM, (p["b"] as Vector2) * MM))
			"spline":
				items.append(p["item"])
	return {"err": "", "items": items, "len": total, "start": P[0]["a"], "dir": P[0]["t0"]}


## a three-point arc (mm) as a piece: centre c, radius R, start angle s, signed sweep ds; empty when the points lie on a line
static func _arc_geom(a: Vector2, m: Vector2, b: Vector2) -> Dictionary:
	var d := 2.0 * (a.x * (m.y - b.y) + m.x * (b.y - a.y) + b.x * (a.y - m.y))
	if absf(d) < 1e-9:
		return {}
	var a2 := a.length_squared()
	var m2 := m.length_squared()
	var b2 := b.length_squared()
	var c := Vector2((a2 * (m.y - b.y) + m2 * (b.y - a.y) + b2 * (a.y - m.y)) / d, (a2 * (b.x - m.x) + m2 * (a.x - b.x) + b2 * (m.x - a.x)) / d)
	var sa := (a - c).angle()
	var sm := fposmod((m - c).angle() - sa, TAU)
	var sb := fposmod((b - c).angle() - sa, TAU)
	return {"k": "arc", "c": c, "R": a.distance_to(c), "s": sa, "ds": sb if sm < sb else sb - TAU}


## the piece's ends (a, b), its travel direction at each end (t0, t1) and its length (mm)
static func _fill_ends(p: Dictionary) -> void:
	match String(p["k"]):
		"line":
			var d := ((p["b"] as Vector2) - (p["a"] as Vector2)).normalized()
			p["t0"] = d
			p["t1"] = d
			p["len"] = (p["a"] as Vector2).distance_to(p["b"])
		"arc":
			var c: Vector2 = p["c"]
			var R := float(p["R"])
			var s := float(p["s"])
			var ds := float(p["ds"])
			var sg := 1.0 if ds >= 0.0 else -1.0
			p["a"] = c + Vector2.from_angle(s) * R
			p["b"] = c + Vector2.from_angle(s + ds) * R
			p["t0"] = Vector2(-sin(s), cos(s)) * sg
			p["t1"] = Vector2(-sin(s + ds), cos(s + ds)) * sg
			p["len"] = R * absf(ds)
		"spline":
			var cv: PackedVector2Array = p["curve"]
			var n := cv.size()
			var len_s := 0.0
			for i in range(n - 1):
				len_s += cv[i].distance_to(cv[i + 1])
			p["a"] = cv[0]
			p["b"] = cv[n - 1]
			p["t0"] = (cv[1] - cv[0]).normalized()
			p["t1"] = (cv[n - 1] - cv[n - 2]).normalized()
			p["len"] = len_s


## the arc's middle point (mm)
static func _arc_mid(p: Dictionary) -> Vector2:
	return (p["c"] as Vector2) + Vector2.from_angle(float(p["s"]) + float(p["ds"]) * 0.5) * float(p["R"])


## takes length t (mm) off one end of a line or arc piece (at_start: the start, else the end)
static func _trim(p: Dictionary, at_start: bool, t: float) -> void:
	if String(p["k"]) == "line":
		var d := ((p["b"] as Vector2) - (p["a"] as Vector2)).normalized()
		if at_start:
			p["a"] = (p["a"] as Vector2) + d * t
		else:
			p["b"] = (p["b"] as Vector2) - d * t
	else:
		var sg := 1.0 if float(p["ds"]) >= 0.0 else -1.0
		var dth := sg * t / float(p["R"])
		if at_start:
			p["s"] = float(p["s"]) + dth
		p["ds"] = float(p["ds"]) - dth
	_fill_ends(p)


## the profile's reach (mm) from the path's start point: the furthest its outline is from it
static func _profile_reach(ents: Array, from: Vector2) -> float:
	var reach := 0.0
	for e in ents:
		var pts: Array = []
		match String(e["k"]):
			"line", "rect": pts = [e["a"], e["b"]]
			"circle": reach = maxf(reach, v2(e["c"]).distance_to(from) + float(e["r"]))
			"arc": pts = [e["a"], e["m"], e["b"]]
			"bspline": pts = e.get("pts", [])
		for q in pts:
			reach = maxf(reach, v2(q).distance_to(from))
	return reach


## the profile's centre (mm, plane 2D): the middle of its bounding box
static func _profile_centre(ents: Array) -> Vector2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for e in ents:
		var pts: Array = []
		match String(e["k"]):
			"line", "rect": pts = [e["a"], e["b"]]
			"circle":
				var c := v2(e["c"])
				var r := float(e["r"])
				pts = [c - Vector2(r, r), c + Vector2(r, r)]
			"arc": pts = [e["a"], e["m"], e["b"]]
			"bspline": pts = e.get("pts", [])
		for q in pts:
			lo = lo.min(v2(q))
			hi = hi.max(v2(q))
	return (lo + hi) * 0.5


## SWEEP: the profile face (on its sketch's plane) along the path's kernel chain; the solid goes in as the op says.
## Checks: the path starts in the middle of the profile, square to its plane; the kernel volume must equal profile area x path length (2 percent),
## else the sweep folded on itself and nothing is made. "" or the failure message.
static func _sweep(bodies: Array, f: Dictionary, sketches: Dictionary) -> String:
	var ps: Dictionary = sketches.get(String(f.get("profile", "")), {})
	var pk: Dictionary = sketches.get(String(f.get("path", "")), {})
	if ps.is_empty() or pk.is_empty():
		return "the profile or the path sketch is gone or cannot be read"
	if (pk["ents"] as Array).is_empty():
		return "the path sketch has no lines, arcs or splines"
	var pl: Dictionary = ps.get("_pl", plane(String(ps.get("plane", "front"))))
	var pa: Dictionary = pk.get("_pl", plane(String(pk.get("plane", "front"))))
	var centre := _profile_centre(ps["ents"])
	var rc := maxf(2.0, 1.5 * _profile_reach(ps["ents"], centre))
	var sp := sweep_path(pk["ents"], rc)
	if String(sp["err"]) != "":
		return String(sp["err"])
	var start: Vector2 = sp["start"]
	var dir: Vector2 = sp["dir"]
	var p0 := to_world(pa, start)
	var tan := ((pa["x"] as Vector3) * dir.x + (pa["y"] as Vector3) * dir.y).normalized()
	if absf(tan.dot(pl["n"])) < 0.999 or absf((p0 - pl["o"]).dot(pl["n"])) > 1e-6:
		return "the path must leave the profile square to it (its first piece runs along the profile's normal)"
	if (to_plane(pl, p0) - centre).length() > 0.5:
		return "the path must start in the middle of the profile"
	var wire := KCad.sketch_wire(sp["items"], pa["o"], pa["x"], pa["n"])
	if wire == 0:
		return KCad.last_error()
	var face := KCad.sketch_face(items_of(ps["ents"]), pl["o"], pl["x"], pl["n"])
	if face == 0:
		KCad.release(wire)
		return "%s is not a closed profile" % String(ps.get("name", "the profile"))
	var solid := KCad.sweep(face, wire)
	var want := KCad.area(face) * float(sp["len"]) * MM
	KCad.release(face)
	KCad.release(wire)
	if solid == 0:
		return KCad.last_error()
	if absf(KCad.volume(solid) - want) > 0.02 * want:
		KCad.release(solid)
		return "the sweep folds on itself: the path bends too sharply for this profile"
	return _combine(bodies, solid, String(f.get("op", "join")))


## puts a new solid into the body list as the op says; "" or the failure message
static func _combine(bodies: Array, solid: int, op: String) -> String:
	if op == "intersect":
		return _intersect_into(bodies, solid)
	if op == "new" or bodies.is_empty():
		bodies.append(solid)
		return ""
	if op == "cut":
		for i in bodies.size():
			var c := KCad.cut(bodies[i], solid)
			if c != 0:
				KCad.release(bodies[i])
				bodies[i] = c
		KCad.release(solid)
		return ""
	var u := KCad.union(bodies[-1], solid)
	KCad.release(solid)
	if u == 0:
		return KCad.last_error()
	KCad.release(bodies[-1])
	bodies[-1] = u
	return ""


## COMBINE: the target body takes each tool body in turn (join = union, cut = minus, intersect = shared volume). The result sits where the
## target was; the tools are removed unless keep. Every body keeps its look; the target keeps its own. "" or the failure message (nothing changes then)
static func _combine_step(bodies: Array, looks: Array, f: Dictionary) -> String:
	var tg := int(f.get("target", -1))
	var tl: Array = []
	for t in f.get("tools", []):
		tl.append(int(t))
	var op := String(f.get("op", "join"))
	if tg < 0 or tg >= bodies.size():
		return "there is no Body%d to combine into" % (tg + 1)
	if tl.is_empty():
		return "pick at least one tool body (Body2, Body3...)"
	if not COMBINE_OPS.has(op):
		return "combine: %s is not Join, Cut or Intersect" % op
	for t in tl:
		if t < 0 or t >= bodies.size():
			return "there is no Body%d to combine" % (t + 1)
		if t == tg or tl.count(t) > 1:
			return "a tool body is the target itself or is picked twice"
	var cur: int = bodies[tg]
	for t in tl:
		var nx := 0
		match op:
			"join":
				nx = KCad.union(cur, bodies[t])
			"cut":
				nx = KCad.cut(cur, bodies[t])
			_:
				nx = KCad.intersect(cur, bodies[t])
		if nx == 0:
			var why := KCad.last_error()
			if cur != bodies[tg]:
				KCad.release(cur)
			return why
		if cur != bodies[tg]:
			KCad.release(cur)
		cur = nx
		if op != "join" and _vol(cur) <= HIT_VOL:
			KCad.release(cur)
			return "nothing is left: " + ("Body%d takes all of the target" % (t + 1) if op == "cut" else "the target shares no volume with Body%d" % (t + 1))
	var keep := bool(f.get("keep", false))
	var nb: Array = []
	var nl: Array = []
	for i in bodies.size():
		if i == tg:
			nb.append(cur)
			nl.append(look_at(looks, i))
		elif tl.has(i) and not keep:
			KCad.release(bodies[i])
		else:
			nb.append(bodies[i])
			nl.append(look_at(looks, i))
	if cur != bodies[tg]:
		KCad.release(bodies[tg])
	bodies.clear()
	bodies.append_array(nb)
	looks.clear()
	looks.append_array(nl)
	return ""


## op intersect: every body keeps only what it shares with the solid; a body with nothing in common goes (none in common at all = an error, nothing changes)
static func _intersect_into(bodies: Array, solid: int) -> String:
	if bodies.is_empty():
		KCad.release(solid)
		return "there is no body to intersect with"
	var parts := []
	for b in bodies:
		var c := KCad.intersect(b, solid)
		if _vol(c) > HIT_VOL:
			parts.append(c)
		else:
			KCad.release(c)
	KCad.release(solid)
	if parts.is_empty():
		return "nothing is shared: the solid misses every body"
	for b in bodies:
		KCad.release(b)
	bodies.clear()
	bodies.append_array(parts)
	return ""


## volume in m3 of a shape id (0 for no shape)
static func _vol(id: int) -> float:
	return KCad.volume(id) if id != 0 else 0.0


## a box 20 m on a side with one face on the plane at offset o, lying on the side n points to
static func _half(o: Vector3, n: Vector3) -> int:
	var id := KCad.box(20.0, 20.0, 20.0)
	var t := KCad.translate(id, o + n * 10.0)
	KCad.release(id)
	return t


## split: every body the plane crosses becomes two bodies (the side it points to first); a plane that crosses none is an error
static func _split(bodies: Array, f: Dictionary, looks: Array = []) -> String:
	if bodies.is_empty():
		return "there is no body to split"
	var pl := plane(String(f.get("plane", "right")))
	var n: Vector3 = pl["n"]
	var o: Vector3 = (pl["o"] as Vector3) + n * float(f.get("at", 0.0)) * MM
	var pos := _half(o, n)
	var neg := _half(o, -n)
	var pieces := []   # [index, the piece on n's side, the piece on the other side]
	for i in bodies.size():
		var a := KCad.intersect(bodies[i], pos)
		var c := KCad.intersect(bodies[i], neg)
		if _vol(a) > HIT_VOL and _vol(c) > HIT_VOL:
			pieces.append([i, a, c])
		else:
			KCad.release(a)
			KCad.release(c)
	KCad.release(pos)
	KCad.release(neg)
	if pieces.is_empty():
		return "the plane does not cut the body"
	var out := []
	var k := 0
	for i in bodies.size():
		if k < pieces.size() and int(pieces[k][0]) == i:
			out.append(pieces[k][1])
			out.append(pieces[k][2])
			KCad.release(bodies[i])
			k += 1
		else:
			out.append(bodies[i])
	_split_looks(looks, bodies.size(), pieces)
	bodies.clear()
	bodies.append_array(out)
	return ""


const SHELL_DIRS := {"+x": Vector3.RIGHT, "-x": Vector3.LEFT, "+y": Vector3.UP, "-y": Vector3.DOWN, "+z": Vector3.BACK, "-z": Vector3.FORWARD}


## shell: body N hollowed with walls `thick` mm; the planar face in direction "open" is left open (the kernel: one face)
static func _shell(bodies: Array, f: Dictionary) -> String:
	if bodies.is_empty():
		return "there is no body to shell"
	var bi := clampi(int(f.get("body", bodies.size() - 1)), 0, bodies.size() - 1)
	var dir: Vector3 = SHELL_DIRS.get(String(f.get("open", "")), Vector3.ZERO)
	var s := KCad.shell(bodies[bi], float(f.get("thick", 1.0)) * MM, dir)
	if s == 0:
		return KCad.last_error()
	KCad.release(bodies[bi])
	bodies[bi] = s
	return ""


static func _edge_op(bodies: Array, f: Dictionary) -> String:
	if bodies.is_empty():
		return "there is no body to round"
	var bi := clampi(int(f.get("body", 0)), 0, bodies.size() - 1)
	var es := KCad.edges(bodies[bi])
	var bb := _bbox(es)
	var ids := PackedInt32Array()
	for want in f.get("edges", []):
		var j := match_edge(es, bb, want)
		if j < 0:
			return "an edge it rounded is not there any more"
		if not ids.has(int(es[j]["id"])):
			ids.append(int(es[j]["id"]))
	if ids.is_empty():
		return "no edge picked"
	var r := 0
	if f["t"] == "fillet":
		r = KCad.fillet_edges(bodies[bi], ids, float(f["r"]) * MM)
	else:
		r = KCad.chamfer_edges(bodies[bi], ids, float(f["dist"]) * MM)
	if r == 0:
		return KCad.last_error()
	KCad.release(bodies[bi])
	bodies[bi] = r
	return ""


static func _bbox(es: Array) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for e in es:
		for k in ["center", "a", "b"]:
			var v: Vector3 = e[k]
			lo = lo.min(v)
			hi = hi.max(v)
	return AABB(lo, hi - lo) if lo.x != INF else AABB()


## a point as 0..1 inside the box (an axis with no thickness reads 0.5)
static func _norm(p: Vector3, bb: AABB) -> Vector3:
	var s := bb.size
	return Vector3(0.5 if s.x < 1e-7 else (p.x - bb.position.x) / s.x, 0.5 if s.y < 1e-7 else (p.y - bb.position.y) / s.y, 0.5 if s.z < 1e-7 else (p.z - bb.position.z) / s.z)


## the index in es of the edge that best matches a stored descriptor, or -1
static func match_edge(es: Array, bb: AABB, want: Dictionary) -> int:
	var q := Vector3(float(want["q"][0]), float(want["q"][1]), float(want["q"][2]))
	var d := Vector3(float(want["d"][0]), float(want["d"][1]), float(want["d"][2]))
	var best := -1
	var best_s := MATCH_MAX
	for i in es.size():
		var s := _norm(es[i]["center"], bb).distance_to(q) + 0.5 * (1.0 - absf((es[i]["dir"] as Vector3).dot(d)))
		if s < best_s:
			best_s = s
			best = i
	return best


## the descriptor to store for an edge of the replay result (see replay's "edges"); mm
static func describe(edge: Dictionary) -> Dictionary:
	var c: Vector3 = edge["c"]
	var q: Vector3 = edge["q"]
	var d: Vector3 = edge["d"]
	return {"p": [snappedf(c.x / MM, 0.001), snappedf(c.y / MM, 0.001), snappedf(c.z / MM, 0.001)], "q": [q.x, q.y, q.z], "d": [d.x, d.y, d.z], "body": int(edge["body"])}


# ---------------------------------------------------------------- canvas (GAP 3): a picture on a plane, calibrated by two points

## mm per picture pixel: the two points' real distance over their distance in pixels (1 until it is calibrated)
static func canvas_scale(f: Dictionary) -> float:
	var pts: Array = f.get("pts", [])
	if pts.size() < 2 or float(f.get("dist", 0.0)) <= 0.0:
		return 1.0
	var d := v2(pts[1]).distance_to(v2(pts[0]))
	return float(f["dist"]) / d if d > 1e-6 else 1.0


## the picture's corners on its plane (mm): top-left, top-right, bottom-right, bottom-left (the picture hangs down from "at")
static func canvas_corners(f: Dictionary) -> Array:
	var s := canvas_scale(f)
	var at := v2(f.get("at", [0, 0]))
	var w := float(f.get("w", 1.0))
	var h := float(f.get("h", 1.0))
	return [at, at + Vector2(w * s, 0.0), at + Vector2(w * s, -h * s), at + Vector2(0.0, -h * s)]


## a picture pixel -> plane mm
static func canvas_px_to_mm(f: Dictionary, px: Vector2) -> Vector2:
	var s := canvas_scale(f)
	return v2(f.get("at", [0, 0])) + Vector2(px.x * s, -px.y * s)


## plane mm -> picture pixel
static func canvas_mm_to_px(f: Dictionary, mm: Vector2) -> Vector2:
	var s := canvas_scale(f)
	var at := v2(f.get("at", [0, 0]))
	return Vector2((mm.x - at.x) / s, (at.y - mm.y) / s)


## APPEARANCE helpers (GAP 5): the look of each body, kept beside the bodies in replay()
static func look_of(f: Dictionary) -> Dictionary:
	var c: Array = f.get("color", [0.74, 0.77, 0.82])
	return {"c": Color(float(c[0]), float(c[1]), float(c[2])), "rough": float(f.get("rough", 0.5)), "metal": float(f.get("metal", 0.15)),
		"alpha": clampf(float(f.get("alpha", 1.0)), 0.0, 1.0), "preset": String(f.get("preset", "Custom"))}


## the look of body i: its last appear step, else its chip (by index) with the default numbers
static func look_at(looks: Array, i: int) -> Dictionary:
	if i >= 0 and i < looks.size() and looks[i] != null:
		return looks[i]
	var c: Color = (LOOK_CHIPS[maxi(i, 0) % LOOK_CHIPS.size()][1] as Color)
	return {"c": c, "rough": float(LOOK_DEFAULT["rough"]), "metal": float(LOOK_DEFAULT["metal"]), "alpha": 1.0, "preset": "Default"}


static func look_fit(looks: Array, n: int) -> void:
	while looks.size() < n:
		looks.append(null)
	while looks.size() > n:
		looks.pop_back()


## a split: the piece pair of each cut body takes the look of the body it came from (a default look stays a default: by index)
static func _split_looks(looks: Array, n: int, pieces: Array) -> void:
	if looks.size() != n:
		return
	var nl := []
	var k := 0
	for i in n:
		nl.append(looks[i])
		if k < pieces.size() and int(pieces[k][0]) == i:
			nl.append(looks[i])
			k += 1
	looks.clear()
	looks.append_array(nl)


## PATTERN (GAP 30): the copies of body N, one kernel move each (translate for a row, rotate about the origin for a circle). "join" unions them into
## body N; "new" keeps each copy as a body of its own (with body N's look). "" or the failure message; a failure changes nothing.
const AXIS_VEC := {"x": Vector3.RIGHT, "y": Vector3.UP, "z": Vector3.BACK}
const PATTERN_MAX := 64

static func _pattern(bodies: Array, looks: Array, f: Dictionary) -> String:
	if bodies.is_empty():
		return "there is no body to pattern"
	var bi := int(f.get("body", -1))
	if bi < 0 or bi >= bodies.size():
		return "there is no body %d to pattern" % bi
	var n := int(f.get("count", 0))
	if n < 2 or n > PATTERN_MAX:
		return "a pattern needs 2 to %d copies (the original counts as one)" % PATTERN_MAX
	var copies := []
	if String(f.get("kind", "linear")) == "circular":
		var ax: Vector3 = AXIS_VEC.get(String(f.get("axis", "y")), Vector3.UP)
		var total := deg_to_rad(float(f.get("deg", 360.0)))
		if absf(total) < 1e-6:
			return "the angle must not be zero"
		var step := total / n if absf(total) >= TAU - 1e-9 else total / (n - 1)
		for i in range(1, n):
			copies.append(KCad.rotate(bodies[bi], ax, step * i))
	else:
		var d: Vector3 = AXIS_VEC.get(String(f.get("dir", "x")), Vector3.RIGHT) * float(f.get("mm", 0.0)) * MM
		if d.length() < 1e-9:
			return "the spacing must not be zero"
		for i in range(1, n):
			copies.append(KCad.translate(bodies[bi], d * i))
	for k in copies.size():
		if int(copies[k]) == 0:
			var why := KCad.last_error()
			for c in copies:
				if int(c) != 0:
					KCad.release(c)
			return why if why != "" else "a copy could not be made"
	if String(f.get("op", "join")) == "new":
		var src: Variant = looks[bi] if bi < looks.size() else null
		for c in copies:
			bodies.append(c)
			looks.append(src)
		return ""
	for k in copies.size():
		var u := KCad.union(bodies[bi], copies[k])
		KCad.release(copies[k])
		if u == 0:
			for j in range(k + 1, copies.size()):
				KCad.release(copies[j])
			return KCad.last_error()
		KCad.release(bodies[bi])
		bodies[bi] = u
	return ""
