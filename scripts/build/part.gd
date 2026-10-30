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
##     extrude may carry "twist": degrees (P024, Easy's Twist slider): a one-way extrude of one closed shape turns about its middle as it rises (no taper with it);
##     extrude and revolve may carry "tilt": degrees (Easy's Tilt it): the piece leans about X through its centre before it joins the body;
##     {"t": "split", "id": ..., "plane": "front"|"top"|"right", "at": mm (offset along the plane's normal), "keep": 0 | 1 | -1} cuts EVERY body the plane crosses in two (keep 1 / -1: only the half on the normal's side / the other half stays);
##     {"t": "shell", "id": ..., "body": N, "thick": mm, "open": "" | "+x" | "-x" | "+y" | "-y" | "+z" | "-z"} hollows body N with walls thick mm,
##     the planar face that points that way open ("" = no face open: a closed cavity),
##     {"t": "hinge", "id": ..., "name": "Hinge1", "body": 0, "o": [x, y, z] (mm), "axis": [x, y, z], "track": [[t_s, deg], ...]}]}
## A HINGE (C3) turns body N (its index when the hinge comes) about the axis through o. Its angle is a Curves channel (seconds, degrees), the
## same as a Kine curve sampled to a list. The timeline shows the rest pose (the hinge adds no solid); hinge_sweep() walks the curve and reports the
## first frame the moving body meets another body (a door against its stop).
## OFFSET FACE (GAP 10, Fusion's Offset Face): {"t": "offset_face", "id", "name", "body": N, "face": {"p": [x, y, z] (mm, the face's centre), "n": [..] (outward normal), "q": [..] (the centre inside the body's box, 0..1), "body": N}, "mm": d}:
## the face moves along its outward normal by d mm (d > 0 adds material, d < 0 removes it). DRAFT (GAP 10): {"t": "draft", "id", "name", "body": N, "faces": [face, ...] (same descriptors),
## "deg": angle, "dir": "x"|"y"|"z"}: the faces lean by deg about the body's bottom (the box's low end on the pull axis), pulled along +dir.
## Faces are re-found like fillet edges (match_face: box position + normal), so the step follows a sketch that is made bigger.
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
## "beside": true (circular, Easy's Ring): the axis runs through a point beside the body, not the origin, so the original stays and the ring
## is just wide enough that neighbours sit "w" + "gap" mm apart.
## COMBINE (Fusion Combine): {"t": "combine", "id", "name", "target": N, "tools": [M, ...], "op": "join"|"cut"|"intersect", "keep": bool}: the target
## body joins, cuts or shares volume with each tool body in turn (the tools in order). The result takes the target's place in the body list; the tool
## bodies go (keep = true leaves them where they are, unchanged).
## FSTAIRS: "kind": "stairs" (Easy's Up and Forward): "count" steps, "rise" and "run" mm: step i is the body moved i rises up and i runs forward; the
## space under each step is filled (a solid staircase, n(n+1)/2 blocks of the body), so the stair is one body. Every other body keeps its place and its look, the target keeps its look.

const KCad := preload("res://scripts/kcad.gd")
const MM := 0.001
const SKIN_MM := 0.3   # NROUNDFILTER: a face centre this close (mm) to the box's outside counts as on the skin
const VERSION := 1
const RING_MIDDLE := 100.0   # mm: a Ring piece whose centre is closer than this to the middle (not on it) goes round the middle
const KINDS := ["sketch", "extrude", "revolve", "fillet", "chamfer", "mirror", "hinge", "split", "shell", "loft", "sweep", "plane", "canvas", "appear", "pattern", "combine", "offset_face", "draft", "lay"]
const OVERHANG_COS := 0.7071   # p113: a face pointing down more than 45 degrees needs support when printed
const BED_MM := 0.1            # p113: a face this close (mm) to the lowest point of the part is on the floor, not an overhang
const DRAFT_DIRS := {"x": Vector3(1, 0, 0), "y": Vector3(0, 1, 0), "z": Vector3(0, 0, 1)}
const PLANES := ["front", "top", "right"]
const OPS := ["join", "new", "cut", "intersect"]
const COMBINE_OPS := ["join", "cut", "intersect"]   # a combine step's op (the dialog's order: Join, Cut, Intersect)
const COARSE_DEFL := 0.002   # NSLIDELOD: the slider preview tessellates at this deflection (m); full detail is 0.0003
const COARSE_ANGLE := 0.5    # NSLIDELOD: and this angle (rad); full detail is 0.25
const MATCH_MAX := 0.25   # an edge matches when (box-position distance + 0.5 x direction mismatch) is below this
const LOOK_CHIPS := [["Grey", Color("#bdc4d0")], ["Red", Color("#c0392b")], ["Blue", Color("#3a7bd5")], ["Yellow", Color("#f2c94c")], ["Green", Color("#4caf50")]]   # the colour chips; a body with no look takes chip (its index mod 5)
const LOOK_PRESETS := {"Paint": {"rough": 0.35, "metal": 0.0, "alpha": 1.0}, "Metal": {"rough": 0.25, "metal": 1.0, "alpha": 1.0}, "Glass": {"rough": 0.05, "metal": 0.0, "alpha": 0.4}, "Rubber": {"rough": 0.95, "metal": 0.0, "alpha": 1.0}, "Plastic": {"rough": 0.45, "metal": 0.0, "alpha": 1.0}}
const LOOK_DEFAULT := {"rough": 0.5, "metal": 0.15, "alpha": 1.0}   # the look a body has before any appear step (the old fixed grey)
const HIT_VOL := 1e-9     # m3 (1 mm3): an overlap this small is contact, not interference (the kernel's boolean noise is far below it)

static var force_off := false   # a test's "no DLL"


static func available() -> bool:
	return not force_off and KCad.available()


static func why_not() -> String:
	return "Restart Kine first; if this stays, reinstall KineCAD: the part tools did not load"   # NWHYCANT: plain next step, no engine words


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
	if bool((d as Dictionary).get("kept", false)):
		out["kept"] = true   # an EMPTY part the user chose (Easy's Empty): a part with no steps that undo and redo bring back as it was
	return out if not out["features"].is_empty() or out.has("kept") else {}


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
	solve(out)   # GAP 9: the constraints hold in the replay too (a set that cannot hold is the sketch's error)
	var bad := con_fail(out)
	if bad != "":
		return {"sk": out, "err": "its constraints cannot all hold (%s would break)" % bad}
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
static func items_of(ents: Array, clamp_x := false) -> Array:   # clamp_x: a SPIN's profile (its splines become polygons on the middle line)
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
					if clamp_x:
						out.append_array(spin_poly(e))
					else:
						out.append(spline_item(e))
	return out


## a spline of a SPIN's profile as a closed polygon of its curve (lines: a spline that runs along the middle line gives a
## degenerate revolve, a hole or no solid). The curve is sampled, cut back onto the middle line where it dips past it or comes near it (within 15 pct of its width, 2..8 mm),
## a run of samples on the line keeps its two ends, and repeated samples go.
static func spin_poly(e: Dictionary) -> Array:
	var closed := bool(e.get("closed", false))
	var c := spline_curve(e.get("pts", []), closed, SPLINE_KERNEL_STEPS)
	if closed and c.size() > 1:
		c.resize(c.size() - 1)
	var wx := 0.0
	for q in c:
		wx = maxf(wx, q.x)
	var snap := clampf(0.15 * wx, 2.0, 8.0)   # near the line IS on the line: the curve rounds a drawn corner at the axis (a bowl's flat bottom) into a
	var d := PackedVector2Array()            # diagonal that pinches to a point, a pinhole in the bottom; a hand-drawn side stops 2-3 mm short (a ring hole)
	if closed:   # start OFF the line: a run on the line that wraps round the loop's start is then one run (two ends), not two that zig-zag
		for i in c.size():
			if c[i].x >= snap:
				c = c.slice(i) + c.slice(0, i)
				break
	for q in c:
		var v := Vector2(0.0 if q.x < snap else q.x, q.y)
		if d.size() > 0 and d[d.size() - 1].distance_to(v) < 0.0005:
			continue
		if v.x == 0.0 and d.size() >= 2 and d[d.size() - 1].x == 0.0 and d[d.size() - 2].x == 0.0:
			d[d.size() - 1] = v
		else:
			d.append(v)
	while closed and d.size() > 2 and d[d.size() - 1].distance_to(d[0]) < 0.0005:
		d.resize(d.size() - 1)
	var mm := PackedVector2Array()
	for q in d:
		mm.append(q * MM)
	return KCad.polygon(mm)


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
## REPLAYGAP probe: while calls_log is an Array, each replay appends [record hash, step, want keys, caller, line] (tests/replaygap2_test.gd); null = off
static var calls_log = null
static func replay(rec: Dictionary, upto := -1, want := {}) -> Dictionary:
	if calls_log != null:
		var st := get_stack()
		calls_log.append([str(hash(JSON.stringify(rec))), str(upto), str(want.keys()), str(st[1]["function"]), str(st[1]["line"])])
	var res := {"mesh": null, "volume": 0.0, "bodies": 0, "volumes": [], "errors": {}, "edges": [], "faces": [], "aabb": AABB(), "props": [], "looks": [], "body_looks": []}
	if not available():
		return res
	var feats: Array = rec.get("features", [])
	var n := feats.size() if upto < 0 else mini(upto + 1, feats.size())
	var bodies: Array = []
	var looks: Array = []   # APPEARANCE: one look per body (null = the default for its index), kept beside bodies
	var errs: Dictionary = res["errors"]
	var sketches := {}
	var off_ids := {}   # XTIME: the sketches the timeline suppressed
	for i in n:
		var f: Dictionary = feats[i]
		var id := String(f["id"])
		look_fit(looks, bodies.size())
		if bool(f.get("off", false)):   # XTIME: a suppressed step is skipped (no solid, no error); a later step that needs it says so
			if String(f["t"]) == "sketch":
				off_ids[id] = true
			continue
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
					errs[id] = _no_sketch_words(rec, f, String(f.get("sketch", "")), errs, off_ids)
					continue
				var sols := _solids(f, sk)
				if String(sols["err"]) != "":
					errs[id] = String(sols["err"])
					continue
				var sids: PackedInt32Array = sols["solids"]
				var tilt_deg := float(f.get("tilt", 0.0))   # TILT (Easy's Tilt it): the piece leans about its middle, before it joins the body
				for si in sids.size():   # XFIX: one solid per separate loop of the sketch (one feature, one undo step)
					if absf(tilt_deg) > 1e-9:
						sids[si] = _tilt_solid(sids[si], tilt_deg)
					var e := _combine(bodies, sids[si], String(f.get("op", "join")), int(f.get("into", -1)))
					if e != "":
						errs[id] = e
						for sj in range(si + 1, sids.size()):
							KCad.release(sids[sj])
						break
			"loft":   # E: the picked profiles, in order, through the kernel's loft
				var le := _loft(bodies, f, sketches)
				if le != "":
					errs[id] = le
			"sweep":   # GAP 6: a closed profile along an open path (its own functions: _sweep, sweep_path)
				var swe := _sweep(bodies, f, sketches)
				if swe != "":
					errs[id] = swe
			"pattern":   # GAP 30: copies of body N (its own function: _pattern); FRULER: a row of copies of a cut (a sketch with "sketch", _cut_row)
				var pe := _cut_row(bodies, f, rec) if f.has("sketch") else _pattern(bodies, looks, f, rec)
				if pe != "":
					errs[id] = pe
			"fillet", "chamfer":
				var e := _edge_op(bodies, f)
				if e != "":
					errs[id] = e
			"offset_face", "draft":   # GAP 10: a face moved along its normal, or leaned about the body's bottom (its own function: _face_op)
				var fe := _face_op(bodies, f)
				if fe != "":
					errs[id] = fe
			"split", "shell":   # the record's split / shell steps (their own functions: _split, _shell)
				var e := _split(bodies, f, looks) if String(f["t"]) == "split" else _shell(bodies, f)
				if e != "":
					errs[id] = e
			"mirror":
				if bodies.is_empty():
					errs[id] = "there is nothing to mirror"
					continue
				var pl := plane(String(f.get("plane", "right")))
				var mo := Vector3.ZERO   # EMIRROR: a piece off the middle line is mirrored across the middle of the PART (its box centre), not the world line
				if bool(f.get("mid", false)):
					var pbb := AABB()
					for pb in bodies:
						pbb = pbb.merge(_piece_box(int(pb))) if pbb.size != Vector3.ZERO else _piece_box(int(pb))
					mo = Vector3(pbb.get_center().x, 0.0, 0.0)
				var u: int = KCad.mirror_join(bodies[-1], mo, pl["n"])
				if u == 0:
					errs[id] = KCad.last_error()
				else:
					KCad.release(bodies[-1])
					bodies[-1] = u
			"lay":   # p113 LAY IT FLAT: every body turns about the origin (the axis and degrees the press chose), then the part drops onto the floor (its lowest point at 0)
				if bodies.is_empty():
					errs[id] = "there is nothing to lay flat"
					continue
				var lax := Vector3(float(f["axis"][0]), float(f["axis"][1]), float(f["axis"][2]))
				var turned: Array = []
				for b in bodies:
					turned.append(KCad.rotate(int(b), lax, deg_to_rad(float(f.get("deg", 0.0)))))
				if turned.has(0):
					errs[id] = KCad.last_error() if KCad.last_error() != "" else "the part could not turn"
					for t in turned:
						if int(t) != 0:
							KCad.release(int(t))
					continue
				var low := INF
				for t in turned:
					low = minf(low, _piece_box(int(t)).position.y)
				for k in turned.size():
					var lifted := KCad.translate(int(turned[k]), Vector3(0.0, -low, 0.0))
					KCad.release(int(turned[k]))
					turned[k] = lifted
				for k in bodies.size():
					KCad.release(int(bodies[k]))
					bodies[k] = turned[k]
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
		var tm := KCad.tessellate(b, COARSE_DEFL, COARSE_ANGLE) if want.get("coarse", false) else KCad.tessellate(b, 0.0003, 0.25)   # NSLIDELOD: a coarse preview while a slider is dragged
		if tm != null and tm.get_surface_count() > 0:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tm.surface_get_arrays(0))
			res["looks"].append(look_at(looks, bodies.find(b)))   # one surface, one look (the view paints each surface)
		if want.get("faces", false):   # GAP 10: the faces to pick (centre, outward normal, box position, body)
			var fs := KCad.faces(b)
			var fb := _bbox_of_points(fs)
			for fc in fs:
				res["faces"].append({"c": fc["center"], "n": fc["normal"], "q": _norm(fc["center"], fb), "body": bodies.find(b), "area": fc["area"]})
		if want.get("edges", false):
			var es := KCad.edges(b)
			var bb := _bbox(es)
			var fnorm := {}   # FBRACKET: face id -> outward normal, to tell a flat seam (two coplanar faces joined) from a real bend
			var fcen := {}   # NROUNDFILTER: face id -> its centre (the outside test: every face of an edge lies on the box's skin)
			for fc in KCad.faces(b):
				fnorm[int(fc["id"])] = fc["normal"]
				fcen[int(fc["id"])] = fc["center"]
			for ed in es:
				var ef: Array = ed.get("faces", [])
				var seam := false
				var concave := false   # a bend that goes INTO the solid (an inner corner): rounding it adds material, so it is skipped
				var inner := false   # P035: an inside corner by the other face: its centre lies on the outside of this face's plane (the test concave uses fails on a T joint)
				if ef.size() == 2 and fnorm.has(int(ef[0])) and fnorm.has(int(ef[1])):
					var n1: Vector3 = fnorm[int(ef[0])]
					var n2: Vector3 = fnorm[int(ef[1])]
					seam = n1.dot(n2) > 0.99
					concave = not seam and (ed["center"] - bb.get_center()).dot(n1 + n2) < 0.0
					inner = not seam and (fcen[int(ef[1])] - ed["center"]).dot(n1) > 0.0
				# NROUNDFILTER: "outside" = every face the edge touches lies on the outside of the solid's box (a hole's or a cup's inside does not);
				# "top" = both ends at the top of the box. Round's filters (Easy Part: All edges, Only the outside, Only the top) read these
				var outside := not ef.is_empty()
				for fi in ef:
					if not fcen.has(int(fi)) or not _on_skin(fcen[int(fi)], bb):
						outside = false
				var top := float(ed["a"].y) >= bb.end.y - SKIN_MM * MM and float(ed["b"].y) >= bb.end.y - SKIN_MM * MM
				res["edges"].append({"c": ed["center"], "a": ed["a"], "b": ed["b"], "d": ed["dir"], "len": ed["length"], "body": bodies.find(b), "q": _norm(ed["center"], bb), "seam": seam or concave, "concave": concave, "inner": inner, "outside": outside, "top": top})
	res["bodies"] = bodies.size()
	for bi in bodies.size():
		res["body_looks"].append(look_at(looks, bi))
	if mesh.get_surface_count() > 0:
		res["mesh"] = mesh
		res["aabb"] = mesh.get_aabb()
	if want.has("probe"):   # XFIX: how full the bodies make a thin slab on a sketch's face (see extrude_default)
		res["probe"] = _probe_fill(bodies, int(want["probe"]))
	if want.get("keep", false):   # the caller owns the solids (vehicle.gd: intersect tests); release them with KCad.release
		res["ids"] = bodies
	else:
		for b in bodies:
			KCad.release(b)
	return res


## XTIME: why an extrude / revolve has no sketch to read, in plain words: its sketch was deleted (the name it had: sketch_was, set when the
## step was deleted), suppressed, or it cannot be read (its own error)
static func _no_sketch_words(rec: Dictionary, f: Dictionary, sid: String, errs: Dictionary, off_ids: Dictionary) -> String:
	var nm := String(f.get("name", "This step"))
	if sid != "" and errs.has(sid):
		return String(errs[sid])
	if sid != "" and off_ids.has(sid):
		var sn := String(feature(rec, sid).get("name", "its sketch"))
		return "%s needs %s, which is suppressed: click Suppress on %s to bring it back, or delete %s" % [nm, sn, sn, nm]
	var was := String(f.get("sketch_was", "its sketch"))
	return "%s needs %s, which was deleted: Undo brings it back, or delete %s" % [nm, was, nm]


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


## p113 OVERHANG PAINTER: the faces of a replay result (rotated by R) that need support when printed: they point down more than 45 degrees
## and are not on the floor (the lowest vertex of the part, turned by R: verts = the shown mesh's vertices). Each is {"n", "c", "area"} in metres / m2, after the turn
static func _overhang_faces(faces: Array, R: Basis, verts: PackedVector3Array) -> Array:
	var low := INF
	for v in verts:
		low = minf(low, (R * v).y)
	var out: Array = []
	if low == INF:
		return out
	for fc in faces:
		var n: Vector3 = R * (fc["n"] as Vector3)
		var c: Vector3 = R * (fc["c"] as Vector3)
		if n.y < -OVERHANG_COS and c.y - low > BED_MM * MM:
			out.append({"n": n, "c": c, "area": float(fc.get("area", 0.0))})
	return out


## every vertex of a replay's shown mesh (metres; empty when there is no mesh)
static func _mesh_verts(mesh: Variant) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not (mesh is ArrayMesh):
		return out
	var am := mesh as ArrayMesh
	for s in am.get_surface_count():
		out.append_array(am.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	return out


## p113: the red faces of the record as it is now (the painter reads these; metres)
static func overhang_faces_of(rec: Dictionary) -> Array:
	if not available():
		return []
	var res := replay(rec, -1, {"faces": true})
	return _overhang_faces(res.get("faces", []), Basis.IDENTITY, _mesh_verts(res.get("mesh")))


static func _overhang_area(faces: Array, R: Basis, verts: PackedVector3Array) -> float:
	var sum := 0.0
	for fo in _overhang_faces(faces, R, verts):
		sum += float(fo["area"])
	return sum


## p113: the turn that puts face normal n on the floor: {"axis", "rad"} (an axis and the radians; a face already down gives rad 0)
static func _turn_to_down(n: Vector3) -> Dictionary:
	var down := Vector3.DOWN
	var ax := n.cross(down)
	if ax.length() < 1e-9:
		return {"axis": Vector3.RIGHT, "rad": 0.0} if n.dot(down) > 0.0 else {"axis": Vector3.RIGHT, "rad": PI}
	return {"axis": ax.normalized(), "rad": acos(clampf(n.dot(down), -1.0, 1.0))}


## p113 LAY IT FLAT: the face that leaves the least overhang when it is put on the floor (ties: the bigger face). Answers
## {"ok": true, "axis": [x, y, z], "deg", "was" (mm2 of overhang now), "now" (mm2 after)} or {"ok": false, "why": the words to say}
static func lay_plan(rec: Dictionary) -> Dictionary:
	if not available():
		return {"ok": false, "why": why_not()}
	var res := replay(rec, -1, {"faces": true})
	var faces: Array = res.get("faces", [])
	if faces.is_empty():
		return {"ok": false, "why": "Make a solid first: draw a shape and Pull it up, then Lay it flat"}
	var verts := _mesh_verts(res.get("mesh"))
	var was := _overhang_area(faces, Basis.IDENTITY, verts)
	var best_area := INF
	var best_face := 0.0
	var best_n := Vector3.DOWN
	for fc in faces:
		var fa := float(fc.get("area", 0.0))
		var n: Vector3 = fc["n"]
		if fa <= 0.0 or n.length_squared() < 1e-12:
			continue
		var t := _turn_to_down(n.normalized())
		var now := _overhang_area(faces, Basis(t["axis"], float(t["rad"])), verts)
		if now < best_area - 1e-9 or (absf(now - best_area) <= 1e-9 and fa > best_face):
			best_area = now
			best_face = fa
			best_n = n.normalized()
	var was_mm := was / (MM * MM)
	var now_mm := best_area / (MM * MM)
	if best_area >= was - 1e-9:
		if was <= 1e-9:
			return {"ok": false, "why": "No face needs support now: it prints as it is"}
		return {"ok": false, "why": "No turn helps: the part already sits on its best face (%.1f cm2 of overhang)" % (was_mm / 100.0)}
	var bt := _turn_to_down(best_n)
	var ax: Vector3 = bt["axis"]
	return {"ok": true, "axis": [ax.x, ax.y, ax.z], "deg": rad_to_deg(float(bt["rad"])), "was": was_mm, "now": now_mm}


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


## true when some triangle of A is within eps of some triangle of B (the same answer as _tri_dist(A, B) <= eps, found without the full
## pair scan: the boxes of the two solids, then each triangle's box grown by eps, go first; a far pair of pieces costs one box test)
static func tris_touch(A: PackedVector3Array, B: PackedVector3Array, eps: float) -> bool:
	if A.is_empty() or B.is_empty():
		return false
	var ba := AABB(A[0], Vector3.ZERO)
	for v in A:
		ba = ba.expand(v)
	var bb := AABB(B[0], Vector3.ZERO)
	for v in B:
		bb = bb.expand(v)
	if not ba.grow(eps).intersects(bb):
		return false
	# the per-triangle boxes are built once (a Join of two dense pieces made ~10^7 box builds in the pair loop: the app froze)
	var tb: Array = []
	var qb: Array = []
	for j in range(0, B.size(), 3):
		var q := AABB(B[j], Vector3.ZERO).expand(B[j + 1]).expand(B[j + 2])
		if q.grow(eps).intersects(ba):
			tb.append(j)
			qb.append(q)
	for i in range(0, A.size(), 3):
		var ta := AABB(A[i], Vector3.ZERO).expand(A[i + 1]).expand(A[i + 2]).grow(eps)
		if not ta.intersects(bb):
			continue
		for k in tb.size():
			if not ta.intersects(qb[k]):
				continue
			var j: int = tb[k]
			if _tri_tri(A[i], A[i + 1], A[i + 2], B[j], B[j + 1], B[j + 2]) <= eps:
				return true
	return false


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


## TILT (Easy's Tilt it): a solid leans about X through its centre of mass by deg degrees (the kernel's centre, metres)
static func _tilt_solid(id: int, deg: float) -> int:
	var mp := KCad.mass_properties(id)
	if mp.is_empty():
		return id
	var t := _swing(id, mp.get("center", Vector3.ZERO) as Vector3, Vector3.RIGHT, deg_to_rad(deg))
	if t == 0:
		return id
	KCad.release(id)
	return t


## a body turned about a hinge: the kernel rotates about the origin only, so the body goes to the origin, turns and comes back
static func _swing(id: int, pivot: Vector3, axis: Vector3, radians: float) -> int:
	var a := KCad.translate(id, -pivot)
	var b := KCad.rotate(a, axis, radians)
	KCad.release(a)
	var c := KCad.translate(b, pivot)
	KCad.release(b)
	return c


## XFIX: the separate loops of a sketch's entities. A line or arc joins a line or arc whose end it meets (0.01 mm); a circle, a rectangle or a
## closed curve is a loop by itself. Answers one Array of entity dictionaries per loop, in the sketch's order.
static func loops_of(ents: Array) -> Array:
	var n := ents.size()
	var par: Array = []
	var ends: Array = []
	for i in n:
		par.append(i)
		var e: Dictionary = ents[i]
		var k := String(e["k"])
		if k == "line" or k == "arc":
			ends.append([v2(e["a"]), v2(e["b"])])
		elif k == "bspline" and not bool(e.get("closed", false)) and (e.get("pts", []) as Array).size() >= 2:
			ends.append([v2(e["pts"][0]), v2(e["pts"][-1])])
		else:
			ends.append([])
	for i in n:
		for j in range(i + 1, n):
			if (ends[i] as Array).is_empty() or (ends[j] as Array).is_empty():
				continue
			var near := false
			for p in ends[i]:
				for q in ends[j]:
					near = near or (p as Vector2).distance_to(q as Vector2) < 0.01
			if near:
				par[_uf_root(par, i)] = _uf_root(par, j)
	var order: Array = []
	var groups := {}
	for i in n:
		var r := _uf_root(par, i)
		if not groups.has(r):
			groups[r] = []
			order.append(r)
		(groups[r] as Array).append(ents[i])
	var out: Array = []
	for r in order:
		out.append(groups[r])
	return out


static func _uf_root(par: Array, i: int) -> int:
	while int(par[i]) != i:
		i = int(par[i])
	return i


## XFIX: the box (mm) a loop's entities reach
static func _loop_box(g: Array) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for e in g:
		var pts: Array = []
		match String(e["k"]):
			"circle":
				var c := v2(e["c"])
				var r := float(e["r"])
				pts = [c - Vector2(r, r), c + Vector2(r, r)]
			"bspline":
				for q in e.get("pts", []):
					pts.append(v2(q))
			"arc":
				pts = [v2(e["a"]), v2(e["m"]), v2(e["b"])]
			_:
				pts = [v2(e["a"]), v2(e["b"])]
		for q in pts:
			lo = lo.min(q)
			hi = hi.max(q)
	return Rect2(lo, hi - lo)


## XFIX: the solids of an Extrude / Revolve of a sketch. A sketch with separate loops gives one solid per loop (each its own profile); a loop
## inside another loop is refused (a ring needs the whole sketch as one face). Answers {"solids": PackedInt32Array, "err": "" or the words}.
static func _solids(f: Dictionary, sk: Dictionary) -> Dictionary:
	var groups := loops_of(sk["ents"])
	if f["t"] != "extrude" or groups.size() <= 1:
		var s := _solid(f, sk)
		if s == 0:
			return {"solids": PackedInt32Array(), "err": _plain_err(KCad.last_error())}
		return {"solids": PackedInt32Array([s]), "err": ""}
	for i in groups.size():
		for j in groups.size():
			if i != j and _loop_box(groups[j]).encloses(_loop_box(groups[i])):
				return {"solids": PackedInt32Array(), "err": "a closed shape sits inside another one in this sketch: Extrude them one at a time"}
	var pl: Dictionary = sk["_pl"] if sk.has("_pl") else plane(String(sk.get("plane", "front")))
	var out := PackedInt32Array()
	for g in groups:
		var face := KCad.sketch_face(items_of(g), pl["o"], pl["x"], pl["n"])
		if face == 0:
			for s in out:
				KCad.release(s)
			return {"solids": PackedInt32Array(), "err": _plain_err(KCad.last_error())}
		var sd := KCad.extrude(face, float(f["dist"]) * MM, bool(f.get("both", false)), deg_to_rad(float(f.get("taper", 0.0))))
		KCad.release(face)
		if sd == 0:
			for s in out:
				KCad.release(s)
			return {"solids": PackedInt32Array(), "err": _plain_err(KCad.last_error())}
		out.append(sd)
	return {"solids": out, "err": ""}


## XFIX: the words a user reads for a kernel failure (no kernel jargon)
static func _plain_err(e: String) -> String:
	if e.find("do not join into one connected wire") >= 0:
		return "the lines do not close into one shape: drag the last end onto the first"
	return e


## XFIX: how full the bodies make a thin slab (0.2 mm, both sides) on the probe face: 0.5 = the face is a body's face and the shape lies inside it,
## 1 = the plane cuts through the body, 0 = no body there. -1 when the kernel cannot tell.
static func _probe_fill(bodies: Array, face: int) -> float:
	var slab := KCad.extrude(face, 0.2 * MM, true, 0.0)
	if slab == 0:
		return -1.0
	var tot := KCad.volume(slab)
	var got := 0.0
	for b in bodies:
		var x := KCad.intersect(b, slab)
		if x != 0:
			got += KCad.volume(x)
			KCad.release(x)
	KCad.release(slab)
	return got / tot if tot > 0.0 else -1.0


## XFIX: the operation a NEW Extrude opens on, and the words why. Cut when its sketch lies on a body's face with its shape inside that face
## (a hole); otherwise Join (New body while there is no body). Answers {"op": join|new|cut, "why": words}.
static func extrude_default(rec: Dictionary) -> Dictionary:
	var sid := profile_sketch(rec)
	var sk := feature(rec, sid)
	if not available() or sk.is_empty() or String(sk.get("t", "")) != "sketch":
		return {"op": "new", "why": ""}
	var pl := resolve_plane(rec, String(sk.get("plane", "front")))
	var face := KCad.sketch_face(items_of(sk["ents"]), pl["o"], pl["x"], pl["n"])
	var fill := -1.0
	var nb := 0
	if face != 0:
		var r := replay(rec, -1, {"probe": face})
		KCad.release(face)
		fill = float(r.get("probe", -1.0))
		nb = int(r.get("bodies", 0))
	if nb > 0 and absf(fill - 0.5) < 0.03:
		return {"op": "cut", "why": "Cut a hole: the sketch lies on a face of the body and its shape is inside that face"}
	if nb > 0:
		return {"op": "join", "why": "Join: the shape joins the body (Cut needs the shape inside a face of a body)"}
	return {"op": "new", "why": "New body: there is no body yet"}


static func _solid(f: Dictionary, sk: Dictionary) -> int:
	var pl: Dictionary = sk["_pl"] if sk.has("_pl") else plane(String(sk.get("plane", "front")))
	if f["t"] == "extrude" and absf(float(f.get("twist", 0.0))) > 0.01 and not bool(f.get("both", false)):
		return _twisted(f, sk, pl)
	var face := KCad.sketch_face(items_of(sk["ents"], f["t"] == "revolve" and bool(f.get("onside", false))), pl["o"], pl["x"], pl["n"])
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


## P024 TWIST (Easy's Twist slider): a one-way pull of a single closed shape turns as it rises. The profile is turned about the middle of its
## own box (the twist axis is the pull's direction), in steps of about 15 degrees; the kernel lofts those sections into one smooth solid.
## Taper is not used with a twist. "" or the kernel's words are left in KCad.last_error
static func _twisted(f: Dictionary, sk: Dictionary, pl: Dictionary) -> int:
	var groups := loops_of(sk["ents"])
	if groups.size() != 1:
		return 0
	var mid := _loop_box(groups[0]).get_center()
	var o: Vector3 = pl["o"]
	var x: Vector3 = pl["x"]
	var n: Vector3 = pl["n"]
	var c: Vector3 = o + x * (mid.x * MM) + (pl["y"] as Vector3) * (mid.y * MM)   # the twist axis: through the middle of the shape
	var h := float(f["dist"]) * MM
	var total := deg_to_rad(float(f["twist"]))
	var steps := clampi(int(ceili(absf(float(f["twist"])) / 15.0)) + 4, 6, 12)
	var faces := PackedInt32Array()
	for i in steps + 1:
		var t := float(i) / steps
		var q := Quaternion(n, total * t)
		var face := KCad.sketch_face(items_of(sk["ents"]), c + q * (o - c) + n * (h * t), q * x, n)
		if face == 0:
			for fc in faces:
				KCad.release(fc)
			return 0
		faces.append(face)
	var s := KCad.loft(faces, false, true)
	for fc in faces:
		KCad.release(fc)
	return s


## E LOFT: every picked sketch becomes a profile face (on its own plane), the kernel lofts them in order; the solid goes in as the op says.
## "" or the failure message
static func _loft(bodies: Array, f: Dictionary, sketches: Dictionary) -> String:
	var ids: Array = f.get("sketches", [])
	if ids.size() < 2:
		return "a loft needs two or more sketches"
	var faces := PackedInt32Array()
	var tw := deg_to_rad(float(f.get("twist", 0.0)))   # TWIST: the last (top) shape turns about its own middle by this much
	for i in ids.size():
		var sid = ids[i]
		var sk: Dictionary = sketches.get(String(sid), {})
		if sk.is_empty():
			for fc in faces:
				KCad.release(fc)
			return "its sketch %s is gone or cannot be read" % String(sid)
		var pl: Dictionary = sk.get("_pl", plane(String(sk.get("plane", "front"))))
		if i == ids.size() - 1 and absf(tw) > 0.0001:
			pl = twist_plane(pl, sk["ents"], tw)
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

## TWIST (Friday 27): the plane turned by tw (radians) about its normal, through the middle of the shape on it. The shape turns where it
## stands (it does not move), so a loft from the shape under it twists by tw. The middle is the centre of the shape's box (mm, in its plane)
static func twist_plane(pl: Dictionary, ents: Array, tw: float) -> Dictionary:
	var c := sketch_centre(ents) * MM
	var o: Vector3 = pl["o"]
	var x: Vector3 = pl["x"]
	var n: Vector3 = pl["n"]
	var mid := o + x * c.x + n.cross(x) * c.y
	var q := Quaternion(n, tw)
	var out := pl.duplicate()
	out["o"] = mid + q * (o - mid)
	out["x"] = q * x
	out["y"] = q * n.cross(x)
	return out


## TWIST: the centre of a sketch's box (mm, in its own plane); a circle counts its whole radius
static func sketch_centre(ents: Array) -> Vector2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for e in ents:
		var pts: Array = []
		match String(e["k"]):
			"line", "rect":
				pts = [v2(e["a"]), v2(e["b"])]
			"circle":
				var cc := v2(e["c"])
				var r := float(e["r"])
				pts = [cc - Vector2(r, r), cc + Vector2(r, r)]
			"arc":
				pts = [v2(e["a"]), v2(e["m"]), v2(e["b"])]
			"bspline":
				for p in e.get("pts", []):
					pts.append(v2(p))
		for p in pts:
			lo = lo.min(p)
			hi = hi.max(p)
	return (lo + hi) * 0.5 if lo.x < INF else Vector2.ZERO


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
	var ents: Array = ps["ents"]
	var wire := KCad.sketch_wire(sp["items"], pa["o"], pa["x"], pa["n"])
	if wire == 0:
		return KCad.last_error()
	var face := 0
	if absf(tan.dot(pl["n"])) >= 0.999 and absf((p0 - pl["o"]).dot(pl["n"])) <= 1e-6 and (to_plane(pl, p0) - centre).length() <= 0.5:
		face = KCad.sketch_face(items_of(ents), pl["o"], pl["x"], pl["n"])
	else:
		# FPIPE: the shape is not at the line's start: it is moved there, centred and square to the line (the shape faces along the line)
		face = KCad.sketch_face(items_of(_shift_ents(ents, centre)), p0, _across(pl, tan), tan)
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
	if bool(f.get("flange", false)):
		solid = _flange_ring(solid, p0, tan, _across(pl, tan), _shift_ents(ents, centre), _profile_reach(ents, centre))
		if solid == 0:
			return KCad.last_error()
	return _combine(bodies, solid, String(f.get("op", "join")))


## a unit direction square to the line's direction, from the shape's own x axis (or its y axis when x lies along the line)
static func _across(pl: Dictionary, tan: Vector3) -> Vector3:
	var px: Vector3 = (pl["x"] as Vector3) - tan * (pl["x"] as Vector3).dot(tan)
	if px.length() < 1e-3:
		px = (pl["y"] as Vector3) - tan * (pl["y"] as Vector3).dot(tan)
	return px.normalized()


## the sweep's shape with its centre moved to the origin of the plane (ents in mm)
static func _shift_ents(ents: Array, c: Vector2) -> Array:
	var out := []
	for e in ents:
		var d: Dictionary = (e as Dictionary).duplicate(true)
		for k in ["a", "b", "c", "m"]:
			if d.has(k):
				d[k] = arr2(v2(d[k]) - c)
		if d.has("pts"):
			var q := []
			for p in d["pts"]:
				q.append(arr2(v2(p) - c))
			d["pts"] = q
		out.append(d)
	return out


## FPIPE FLANGE: a washer ring at the line's start end, standing square to the line and lying behind the start: outer width 2 x the shape's reach + 12 mm, 4 mm thick, the pipe's own shape cut out of its middle. Joined to the swept solid; 0 with the kernel's error.
static func _flange_ring(pipe: int, p0: Vector3, tan: Vector3, x: Vector3, ents: Array, reach: float) -> int:
	var t := 4.0 * MM
	var back := p0 - tan * t
	var od := (2.0 * reach + 12.0) * MM
	var outer_face := KCad.sketch_face([KCad.circle(Vector2.ZERO, od * 0.5)], back, x, tan)
	if outer_face == 0:
		KCad.release(pipe)
		return 0
	var outer := KCad.extrude(outer_face, t, false, 0.0)
	KCad.release(outer_face)
	var bore_face := KCad.sketch_face(items_of(ents), back, x, tan)
	if bore_face == 0:
		KCad.release(outer)
		KCad.release(pipe)
		return 0
	var bore := KCad.extrude(bore_face, t, false, 0.0)
	KCad.release(bore_face)
	var ring := KCad.cut(outer, bore)
	KCad.release(outer)
	KCad.release(bore)
	if ring == 0:
		KCad.release(pipe)
		return 0
	var joined := KCad.union(pipe, ring)
	KCad.release(pipe)
	KCad.release(ring)
	return joined




## puts a new solid into the body list as the op says; "" or the failure message
static func _combine(bodies: Array, solid: int, op: String, into := -1) -> String:
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
	var t := into if into >= 0 and into < bodies.size() else bodies.size() - 1   # FLAMP5: a pull joins the body it sits on (see touching_body); else the last
	var u := KCad.union(bodies[t], solid)
	KCad.release(solid)
	if u == 0:
		return KCad.last_error()
	KCad.release(bodies[t])
	bodies[t] = u
	return ""


## FIXIT: the first thing wrong with a part, for Easy Part's Fix it: {} when all is well. kind "failed": a step that does not build (id);
## "wall": a shell with no thickness (id); "loose": a separate piece that touches nothing joined to the main piece (id: the first pull that leaves it loose)
static func find_problem(rec: Dictionary) -> Dictionary:
	var full := replay(rec)
	var errs: Dictionary = full["errors"]
	var fs: Array = rec.get("features", [])
	for f in fs:
		if bool(f.get("off", false)):
			continue
		var id := String(f["id"])
		if errs.has(id):
			return {"kind": "failed", "id": id}
		if String(f["t"]) == "shell" and float(f.get("thick", 1.0)) <= 0.0:
			return {"kind": "wall", "id": id}
	if _loose_count(full.get("mesh")) == 0:
		return {}
	for k in fs.size():
		var f: Dictionary = fs[k]
		if bool(f.get("off", false)) or not (String(f["t"]) in ["extrude", "revolve"]):
			continue
		if _loose_count(replay(rec, k).get("mesh")) > 0:
			return {"kind": "loose", "id": String(f["id"])}
	return {}


## FIXIT: how many pieces of a built mesh touch nothing joined to the main piece (the one with the biggest box)
static func _loose_count(mesh: Variant) -> int:
	if not (mesh is ArrayMesh) or (mesh as ArrayMesh).get_surface_count() < 2:
		return 0
	var sm: ArrayMesh = mesh
	var n := sm.get_surface_count()
	var main := 0
	var best := -1.0
	for s in n:
		var v: PackedVector3Array = sm.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		var bb := AABB(v[0], Vector3.ZERO)
		for p in v:
			bb = bb.expand(p)
		if bb.get_volume() > best:
			best = bb.get_volume()
			main = s
	var linked := {main: true}
	var grew := true
	while grew:
		grew = false
		for j in n:
			if linked.has(j):
				continue
			for i in linked.keys():
				if touch_surfaces(sm, int(i), j):
					linked[j] = true
					grew = true
					break
	return n - linked.size()


## FIXIT: the fix for a problem from find_problem, on the record in place. "" when done; else the words why not (the record is then left as it was)
static func apply_fix(rec: Dictionary, p: Dictionary) -> String:
	var k := index_of(rec, String(p.get("id", "")))
	if k < 0:
		return "That step is gone: press Fix it again"
	var fs: Array = rec["features"]
	if String(p.get("kind", "")) == "wall":
		fs[k]["thick"] = 2.0   # a wall must have some thickness: 2 mm, the thinnest a beginner can see
		return ""
	var test: Dictionary = rec.duplicate(true)
	var tfs: Array = test["features"]
	var gone: Dictionary = tfs[k]
	tfs.remove_at(k)
	for key in ["sketch", "plane"]:
		if gone.has(key):
			var sid := String(gone[key])
			if sid == "" or JSON.stringify(tfs).contains("\"%s\"" % sid):
				continue
			for i in tfs.size():
				if String(tfs[i].get("id", "")) == sid:
					tfs.remove_at(i)
					break
	if String(p.get("kind", "")) == "loose":
		if not replay(test)["errors"].is_empty() or _loose_count(replay(test).get("mesh")) > 0:
			return "A step after it needs this piece, so it stays. Take those steps out first"
	rec["features"] = tfs
	return ""


## FIXIT: the line Easy Part says after a fix, in plain words
static func fix_words(p: Dictionary) -> String:
	match String(p.get("kind", "")):
		"wall":
			return "Gave the wall 2 mm of thickness: it had none. Undo puts it back"
		"loose":
			return "Took out the loose piece that touched nothing. Undo puts it back"
	return "Took out the step that cannot be made. Undo puts it back"


## FLAMP5: the body an Extrude (op join) sits on: its solid is replayed alone as a new body, and the body whose mesh touches it is the one.
## -1 when it touches none. Saved on the step as "into" (set once, when the step is made), so every replay joins that body, not the last one.
static func touching_body(rec: Dictionary, f: Dictionary) -> int:
	var op := String(f.get("op", "join"))
	f["op"] = "new"
	var m: ArrayMesh = replay(rec).get("mesh")
	f["op"] = op
	if m == null or m.get_surface_count() < 2:
		return -1
	var n := m.get_surface_count() - 1   # the new solid is the last body
	for i in n:
		if touch_surfaces(m, i, n):
			return i
	return -1


## FLAMP5: two surfaces touch when a corner of one lies on a triangle of the other (a shape standing on a face: no vertex is shared)
static func touch_surfaces(m: ArrayMesh, i: int, j: int) -> bool:
	var pi := _surf_pts(m, i)
	var pj := _surf_pts(m, j)
	return touch_patch(pi[0], pj[1], _box_of(pj[1])) or touch_patch(pj[0], pi[1], _box_of(pi[1]))


## the vertices of a surface, and its triangles as three points each (flat)
static func _surf_pts(m: ArrayMesh, s: int) -> Array:
	var arr := m.surface_get_arrays(s)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var tp := PackedVector3Array()
	var n := idx.size() if idx.size() > 0 else vs.size()
	for t in range(0, n - 2, 3):
		for k in 3:
			tp.append(vs[idx[t + k] if idx.size() > 0 else t + k])
	return [vs, tp]


static func _box_of(pts: PackedVector3Array) -> AABB:
	var bb := AABB()
	for k in pts.size():
		bb = AABB(pts[k], Vector3.ZERO) if k == 0 else bb.expand(pts[k])
	return bb


## does any point of pts lie on a triangle of tri_pts (flat, three per triangle) inside the box bb (grown a little)?
static func touch_patch(pts: PackedVector3Array, tri_pts: PackedVector3Array, bb: AABB) -> bool:
	var gbb := bb.grow(1e-4)
	for p in pts:
		if not gbb.has_point(p):
			continue
		for t in range(0, tri_pts.size() - 2, 3):
			var a: Vector3 = tri_pts[t]
			var b: Vector3 = tri_pts[t + 1]
			var c: Vector3 = tri_pts[t + 2]
			var nrm := (b - a).cross(c - a)
			var ln := nrm.length()
			if ln < 1e-12:
				continue
			nrm /= ln
			if absf((p - a).dot(nrm)) > 2e-5:
				continue
			var c1 := (b - a).cross(p - a).dot(nrm)
			var c2 := (c - b).cross(p - b).dot(nrm)
			var c3 := (a - c).cross(p - c).dot(nrm)
			if c1 >= -1e-9 and c2 >= -1e-9 and c3 >= -1e-9:
				return true
	return false


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
	var keep := int(f.get("keep", 0))   # ECUT2: 0 both halves, 1 only the half on n's side (upper), -1 only the other (lower)
	for i in bodies.size():
		if k < pieces.size() and int(pieces[k][0]) == i:
			if keep > 0:
				KCad.release(pieces[k][2])
				out.append(pieces[k][1])
			elif keep < 0:
				KCad.release(pieces[k][1])
				out.append(pieces[k][2])
			else:
				out.append(pieces[k][1])
				out.append(pieces[k][2])
			KCad.release(bodies[i])
			k += 1
		else:
			out.append(bodies[i])
	_split_looks(looks, bodies.size(), pieces if keep == 0 else [])   # a kept half is one body: its look is the cut body's, not two
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
	var thick := float(f.get("thick", 1.0)) * MM
	var before := KCad.volume(bodies[bi])
	var s := KCad.shell(bodies[bi], thick, dir)
	if s == 0:
		return KCad.last_error()
	if dir != Vector3.ZERO and KCad.volume(s) >= before - 1e-12:
		# NSLIDELOD: the kernel's shell of a rounded solid can hand back the solid unchanged (no error): cut the cavity by hand
		KCad.release(s)
		s = _cavity(bodies[bi], thick, dir)
		if s == 0:
			return "the wall is too thick for this solid: make the wall thinner"
	KCad.release(bodies[bi])
	bodies[bi] = s
	return ""


## NSLIDELOD: the box-shaped hollow of body `b` (wall `thick` m, open on the side `dir`): the body's box minus a smaller box, open on that side
static func _cavity(b: int, thick: float, dir: Vector3) -> int:
	var bb := _bbox(KCad.edges(b))
	var lo := bb.position + Vector3.ONE * thick
	var hi := bb.end - Vector3.ONE * thick
	for i in 3:
		if dir[i] > 0.0:
			hi[i] = bb.end[i] + thick
		elif dir[i] < 0.0:
			lo[i] = bb.position[i] - thick
	var size := hi - lo
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return 0
	var box := KCad.box(size.x, size.y, size.z)
	var at := _bbox(KCad.edges(box)).position
	var moved := KCad.translate(box, lo - at)
	KCad.release(box)
	if moved == 0:
		return 0
	var c := KCad.cut(b, moved)
	KCad.release(moved)
	return c


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


## EROUND: the kept solids of a replay (replay(rec, -1, {"keep": true}).ids) are the caller's: this releases them
static func release_kept(ids: Array) -> void:
	for b in ids:
		KCad.release(int(b))


## EROUND: the error (or "") of a fillet of these edges on body (one of the kept solids: it is not changed, the trial result is released).
## The same picking and kernel call as _edge_op; r_mm is the radius in mm as the step stores it (snapped)
static func fillet_trial(body: int, r_mm: float, edges: Array) -> String:
	var es := KCad.edges(body)
	var bb := _bbox(es)
	var ids := PackedInt32Array()
	for want in edges:
		var j := match_edge(es, bb, want)
		if j < 0:
			return "an edge it rounded is not there any more"
		# FKEY: an edge where three or more faces meet (a tooth joined level with a blade leaves one) crashed the kernel's fillet
		var ef: Array = es[j].get("faces", [])
		if ef.size() > 2:
			return "an edge where three faces meet: no clean bend to round"
		if not ids.has(int(es[j]["id"])):
			ids.append(int(es[j]["id"]))
	if ids.is_empty():
		return "no edge picked"
	var r := KCad.fillet_edges(body, ids, r_mm * MM)
	if r == 0:
		return KCad.last_error()
	KCad.release(r)
	return ""

## GAP 10: an offset or a draft. The faces are found on the body as it is at this step (match_face), then the kernel moves them
static func _face_op(bodies: Array, f: Dictionary) -> String:
	var what := "offset" if String(f["t"]) == "offset_face" else "draft"
	if bodies.is_empty():
		return "there is no body to %s" % what
	var bi := clampi(int(f.get("body", 0)), 0, bodies.size() - 1)
	var fs := KCad.faces(bodies[bi])
	var fb := _bbox_of_points(fs)
	if String(f["t"]) == "offset_face":
		var j := match_face(fs, fb, f.get("face", {}))
		if j < 0:
			return "a face it offsets is not there any more"
		var r := KCad.offset_face(bodies[bi], int(fs[j]["id"]), float(f.get("mm", 0.0)) * MM)
		if r == 0:
			return KCad.last_error()
		KCad.release(bodies[bi])
		bodies[bi] = r
		return ""
	var ids := PackedInt32Array()
	for want in f.get("faces", []):
		var j := match_face(fs, fb, want)
		if j < 0:
			return "a face it drafts is not there any more"
		if not ids.has(int(fs[j]["id"])):
			ids.append(int(fs[j]["id"]))
	if ids.is_empty():
		return "no face picked"
	var pull: Vector3 = DRAFT_DIRS.get(String(f.get("dir", "z")), Vector3(0, 0, 1))
	var r2 := KCad.draft_faces(bodies[bi], ids, deg_to_rad(float(f.get("deg", 0.0))), pull, fb.position)
	if r2 == 0:
		return KCad.last_error()
	KCad.release(bodies[bi])
	bodies[bi] = r2
	return ""


## the box of a list of faces (their centres): the frame the box position "q" is taken in
static func _bbox_of_points(fs: Array) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for fc in fs:
		lo = lo.min(fc["center"])
		hi = hi.max(fc["center"])
	return AABB(lo, hi - lo) if lo.x != INF else AABB()


## the index in fs of the face that best matches a stored descriptor (box position + normal), or -1
static func match_face(fs: Array, bb: AABB, want: Dictionary) -> int:
	if not (want.get("q") is Array) or not (want.get("n") is Array) or (want["q"] as Array).size() < 3 or (want["n"] as Array).size() < 3:
		return -1
	var q := Vector3(float(want["q"][0]), float(want["q"][1]), float(want["q"][2]))
	var n := Vector3(float(want["n"][0]), float(want["n"][1]), float(want["n"][2]))
	var best := -1
	var best_s := MATCH_MAX
	for i in fs.size():
		var s := _norm(fs[i]["center"], bb).distance_to(q) + 0.5 * (1.0 - (fs[i]["normal"] as Vector3).dot(n))
		if s < best_s:
			best_s = s
			best = i
	return best


## the descriptor to store for a face of the replay result (see replay's "faces"); mm
static func describe_face(face: Dictionary) -> Dictionary:
	var c: Vector3 = face["c"]
	var n: Vector3 = face["n"]
	var q: Vector3 = face["q"]
	return {"p": [snappedf(c.x / MM, 0.001), snappedf(c.y / MM, 0.001), snappedf(c.z / MM, 0.001)], "n": [n.x, n.y, n.z], "q": [q.x, q.y, q.z], "body": int(face["body"])}


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


## NROUNDFILTER: a point lies on the skin of the box bb (one of its six faces, within SKIN_MM)
static func _on_skin(p: Vector3, bb: AABB) -> bool:
	for ax in 3:
		if absf(p[ax] - bb.position[ax]) < SKIN_MM * MM or absf(p[ax] - bb.end[ax]) < SKIN_MM * MM:
			return true
	return false


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
## COLOUR KEPT (Use in a scene, My parts picture): each surface of a replayed mesh gets its body's look as its own material, so a
## prop or a picture drawn from the bare mesh keeps the colour (the view's override would paint them all one grey)
static func paint(mesh: ArrayMesh, looks: Array) -> void:
	for s in mini(looks.size(), mesh.get_surface_count()):
		var l: Dictionary = looks[s]
		var c: Color = l["c"]
		var a := float(l["alpha"])
		var mt := StandardMaterial3D.new()
		mt.albedo_color = Color(c.r, c.g, c.b, a)
		mt.roughness = float(l["rough"])
		mt.metallic = float(l["metal"])
		mt.cull_mode = BaseMaterial3D.CULL_DISABLED
		if a < 1.0:
			mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.surface_set_material(s, mt)


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

static func _pattern(bodies: Array, looks: Array, f: Dictionary, rec: Dictionary = {}) -> String:
	if bodies.is_empty():
		return "there is no body to pattern"
	var bi := int(f.get("body", -1))
	if bi < 0 or bi >= bodies.size():
		return "there is no body %d to pattern" % bi
	if String(f.get("kind", "linear")) == "corners":   # EREPEAT (Easy's Corners): the piece goes to the four corners of the body it touches
		return _corners(bodies, looks, bi)
	if String(f.get("kind", "linear")) == "rail":   # FRAIL (Easy's Rail): a bar of 50 mm laid along the nosings of a stair
		return _rail(bodies, f, bi)
	var srcb := int(bodies[bi])   # the solid the copies are made of: the body itself, or (src) the piece its step made on its own
	var owned := false
	if String(f.get("src", "")) != "":   # REPEAT THE PIECE: the newest piece copied, not the whole body it has joined (Easy's Repeat)
		var sid := _piece_solid(rec, String(f["src"]))
		if sid == 0:
			return KCad.last_error() if KCad.last_error() != "" else "the piece to copy could not be made"
		srcb = sid
		owned = true
	var why := _pattern_copies(bodies, looks, f, bi, srcb)
	if owned:
		KCad.release(srcb)
	return why


## REPEAT THE PIECE: the solid of the step fid made alone (its own body, the body list before it as it was): 0 when it cannot be made
static func _piece_solid(rec: Dictionary, fid: String) -> int:
	var sub := pattern_src_rec(rec, fid)
	if sub.is_empty():
		return 0
	var res := replay(sub, -1, {"keep": true})
	var ids: Array = res.get("ids", [])
	if not (res["errors"] as Dictionary).is_empty() or ids.is_empty():
		for b in ids:
			KCad.release(int(b))
		return 0
	for k in ids.size() - 1:
		KCad.release(int(ids[k]))
	return int(ids[-1])


## REPEAT THE PIECE: the record the piece is replayed from: the steps up to fid, with fid's own solid as a body of its own ("new")
static func pattern_src_rec(rec: Dictionary, fid: String) -> Dictionary:
	var feats: Array = rec.get("features", [])
	var k := -1
	for i in feats.size():
		if String(feats[i]["id"]) == fid:
			k = i
	if k < 0:
		return {}
	var sub_feats: Array = feats.slice(0, k + 1).duplicate(true)
	(sub_feats[k] as Dictionary)["op"] = "new"
	var sub := rec.duplicate(false)
	sub["features"] = sub_feats
	return sub


## REPEAT THE PIECE: the newest piece's step id (the last extrude or revolve that is not a cut) when only Appearance steps came after it; "" otherwise
static func pattern_piece(rec: Dictionary) -> String:
	var feats: Array = rec.get("features", [])
	for i in range(feats.size() - 1, -1, -1):
		var f: Dictionary = feats[i]
		if bool(f.get("off", false)) or String(f.get("t", "")) == "appear":
			continue
		if String(f.get("t", "")) in ["extrude", "revolve"] and String(f.get("op", "join")) != "cut":
			# FSHELF: the piece is the newest step only when it stands UP off a face (dist > 0, a slat on a frame) and makes ONE solid;
			# a step pulled DOWN (a bracket hung under a plate) or several solids is part of the body: Repeat copies the whole body
			if float(f.get("dist", 0.0)) <= 0.0:
				return ""
			var before := 0 if i == 0 else int(replay(_upto_rec(rec, i - 1), -1).get("bodies", 0))
			var made := int(replay(pattern_src_rec(rec, String(f["id"])), -1).get("bodies", 0)) - before
			return String(f["id"]) if made == 1 else ""
		return ""
	return ""


## FSHELF: the record with the steps 0..k only (the first k + 1 steps; no steps when k < 0)
static func _upto_rec(rec: Dictionary, k: int) -> Dictionary:
	var sub := rec.duplicate(false)
	sub["features"] = (rec.get("features", []) as Array).slice(0, k + 1).duplicate(true)
	return sub


static func _pattern_copies(bodies: Array, looks: Array, f: Dictionary, bi: int, srcb: int) -> String:
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
		var pivot := Vector3.ZERO   # the axis runs through the origin (Expert), or through a point BESIDE the body ("beside": Easy's Ring)
		var mc: Vector3 = (KCad.mass_properties(bodies[bi]).get("center", Vector3.ZERO) as Vector3)
		var off_mid := Vector2(mc.x, mc.z).length()
		# FWHEEL: a piece that sits near the middle but not on it (a spoke from the hub) goes round the middle: its copies fan out round the
		# origin. A beside-ring for it would put the circle ~0.5 m away and fling the copies out. A piece AT the origin keeps the beside ring
		var spoke := off_mid > 0.5 * MM and off_mid < RING_MIDDLE * MM
		if bool(f.get("beside", false)) and not spoke:
			var mp := KCad.mass_properties(srcb)   # the copies are made of srcb (the newest piece for Repeat it), so the ring centres on it
			var side: Vector3 = Vector3.RIGHT if absf(ax.dot(Vector3.RIGHT)) < 0.9 else Vector3.BACK
			var chord := (float(f.get("w", 10.0)) + float(f.get("gap", 10.0))) * MM   # neighbours sit a piece width plus the gap apart
			var r := chord / (2.0 * sin(absf(step) * 0.5))
			pivot = (mp.get("center", Vector3.ZERO) as Vector3) - side * r
		for i in range(1, n):
			if pivot.length() < 1e-12:
				copies.append(KCad.rotate(srcb, ax, step * i))
				continue
			var t0 := KCad.translate(srcb, -pivot)
			var t1 := KCad.rotate(t0, ax, step * i)
			KCad.release(t0)
			copies.append(KCad.translate(t1, pivot) if t1 != 0 else 0)
			if t1 != 0:
				KCad.release(t1)
	elif String(f.get("kind", "linear")) == "stairs":   # FSTAIRS (Easy's Up and Forward): copy i sits i steps up and i steps forward; each step is filled down to the floor (a solid stair)
		var rise := float(f.get("rise", 0.0)) * MM
		var run_d := float(f.get("run", 0.0)) * MM
		if rise < 1e-9 or run_d < 1e-9:
			return "the steps need a height and a depth"
		for i in range(0, n):
			for j in range(0, i + 1):
				if i == 0 and j == 0:
					continue   # the original piece is step 0
				copies.append(KCad.translate(bodies[bi], Vector3(0.0, float(j) * rise, float(i) * run_d)))
	else:
		var d: Vector3 = AXIS_VEC.get(String(f.get("dir", "x")), Vector3.RIGHT) * float(f.get("mm", 0.0)) * MM
		if d.length() < 1e-9:
			return "the spacing must not be zero"
		for i in range(1, n):
			copies.append(KCad.translate(srcb, d * i))
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


## FRAIL: a handrail along a stair made by Up and Forward (count steps, rise and run in mm): a 50 mm square bar laid on the
## nosings (the line from step 1 to step n), joined into body bi. The bar is made along Z, tilted by the slope, then moved to its place
static func _rail(bodies: Array, f: Dictionary, bi: int) -> String:
	var n := int(f.get("count", 0))
	var rise := float(f.get("rise", 0.0)) * MM
	var run_d := float(f.get("run", 0.0)) * MM
	if n < 2 or rise < 1e-9 or run_d < 1e-9:
		return "the rail needs a stair of 2 steps or more"
	var t := 50.0 * MM
	var mc: Vector3 = KCad.mass_properties(bodies[bi]).get("center", Vector3.ZERO)
	var span := (n - 1) * sqrt(rise * rise + run_d * run_d)
	var bar := KCad.box(t, t, span)
	if bar == 0:
		return KCad.last_error() if KCad.last_error() != "" else "the rail could not be made"
	var tilted := KCad.rotate(bar, Vector3.RIGHT, -atan2(rise, run_d))
	KCad.release(bar)
	if tilted == 0:
		return "the rail could not be made"
	var at := Vector3(mc.x, (n + 1) * 0.5 * rise + t * 0.5, (n + 1) * 0.5 * run_d)
	var c_t: Vector3 = KCad.mass_properties(tilted).get("center", Vector3.ZERO)
	var placed := KCad.translate(tilted, at - c_t)
	KCad.release(tilted)
	if placed == 0:
		return "the rail could not be made"
	var u := KCad.union(bodies[bi], placed)
	KCad.release(placed)
	if u == 0:
		return KCad.last_error() if KCad.last_error() != "" else "the rail could not be joined"
	KCad.release(bodies[bi])
	bodies[bi] = u
	return ""



## FRULER: a Row of copies of a CUT (Easy's Repeat it on a slot or hole): the cut's sketch is moved along X by "mm" (the spacing) for each copy
## and cut into the body again, one copy after the other. The copies are made at replay, so the How many and Gap sliders just rebuild them
static func _cut_row(bodies: Array, f: Dictionary, rec: Dictionary) -> String:
	if bodies.is_empty():
		return "there is no body to cut"
	var n := int(f.get("count", 0))
	if n < 2 or n > PATTERN_MAX:
		return "a pattern needs 2 to %d copies (the original counts as one)" % PATTERN_MAX
	if String(f.get("kind", "linear")) != "linear":
		return "a ring of cuts is not made yet: use Row"
	var sk0 := feature(rec, String(f.get("sketch", "")))
	if sk0.is_empty():
		return "the cut's shape is gone"
	var step := float(f.get("mm", 0.0))
	if absf(step) < 1e-6:
		return "the spacing must not be zero"
	for i in range(1, n):
		var sk: Dictionary = sk0.duplicate(true)
		sk["_pl"] = resolve_plane(rec, String(sk0.get("plane", "front")))
		for e in sk["ents"]:
			for k in ["a", "b", "c"]:
				if e.has(k):
					e[k] = [float(e[k][0]) + step * i, float(e[k][1])]
		var sols := _solids({"t": "extrude", "sketch": sk0.get("id", ""), "dist": f.get("dist", -10.0), "both": bool(f.get("both", false)), "op": "cut"}, sk)
		if String(sols["err"]) != "":
			return String(sols["err"])
		for sid in sols["solids"]:
			var e2 := _combine(bodies, sid, "cut")
			if e2 != "":
				return e2
	return ""


## EREPEAT: the body's bounding box (metres), from its triangles
static func _piece_box(id: int) -> AABB:
	var pts := _tris_of(id)
	if pts.is_empty():
		return AABB()
	var bb := AABB(pts[0], Vector3.ZERO)
	for q in pts:
		bb = bb.expand(q)
	return bb


## EREPEAT Corners: the body is mirrored across its middle in X and in Z, and the four (the body and its three mirrors) join into one body.
## A seat with a leg drawn at one corner gets a leg at each corner: the leg a beginner drew is the one that is copied.
## (A leg pulled into its seat is one body with it, so the copy is of the whole body: fine for a symmetric seat and its legs.)
static func _corners(bodies: Array, looks: Array, bi: int) -> String:
	var bb := _piece_box(int(bodies[bi]))
	if bb.size == Vector3.ZERO:
		return "the piece has no size to copy"
	var o := Vector3(bb.get_center().x, 0.0, bb.get_center().z)
	var src := int(bodies[bi])
	var mx := KCad.mirror(src, o, Vector3.RIGHT)
	if mx == 0:
		var why := KCad.last_error()
		return why if why != "" else "the copy at the corners could not be made"
	var acc := KCad.union(src, mx)
	KCad.release(mx)
	if acc == 0:
		var why_u := KCad.last_error()
		return why_u if why_u != "" else "the corner copies would not join"
	var mz := KCad.mirror(acc, o, Vector3.BACK)
	if mz == 0:
		KCad.release(acc)
		return "the copy at the corners could not be made"
	var acc2 := KCad.union(acc, mz)
	KCad.release(mz)
	KCad.release(acc)
	if acc2 == 0:
		return KCad.last_error() if KCad.last_error() != "" else "the corner copies would not join"
	KCad.release(src)
	bodies[bi] = acc2
	return ""



# ---------------------------------------------------------------- sketch constraints (GAP 9)
## A sketch's "cons": [{"k": "h" | "v", "a": ent} (a line horizontal / vertical), {"k": "coin", "a", "ap", "b", "bp"} (end ap of line a is end bp of line b),
## {"k": "par" | "perp" | "eq", "a", "b"} (two lines parallel / perpendicular / equal length), {"k": "ang", "a", "b", "deg"} (the angle between the two
## lines, 0..180). Only LINE entities take them (a rectangle is always square to the sketch). The solver moves the line ends (Levenberg-
## Marquardt on the sketch points) so every constraint and every typed LENGTH dimension of a line holds; a set that cannot hold is refused
## (con_put), or its sketch makes an error in the replay (resolved_sketch). Residuals: mm, or unit-vector terms.
const CON_TOL := 1e-6
const CON_WORDS := {"h": "Horizontal", "v": "Vertical", "coin": "Coincident", "par": "Parallel", "perp": "Perpendicular", "eq": "Equal", "ang": "Angle"}


## plain words for one constraint: "Angle 30 deg"
static func con_name(c: Dictionary) -> String:
	var w := String(CON_WORDS.get(String(c.get("k", "")), "constraint"))
	if String(c.get("k", "")) == "ang":
		w += " %s deg" % _short(float(c.get("deg", 0.0)))
	return w


## the sketch's points as one flat array of 64-bit numbers (Vector2 is 32-bit: at 100 mm it cannot hold 1e-6 mm, so the solver never uses it):
## entity i has a = [4i, 4i+1] and b = [4i+2, 4i+3] (non-line entities keep zeros, unused)
static func _pts_of(sk: Dictionary) -> PackedFloat64Array:
	var X := PackedFloat64Array()
	for e in sk.get("ents", []):
		if String(e.get("k", "")) == "line":
			X.append_array([float(e["a"][0]), float(e["a"][1]), float(e["b"][0]), float(e["b"][1])])
		else:
			X.append_array([0.0, 0.0, 0.0, 0.0])
	return X


static func _line_ok(sk: Dictionary, i: int) -> bool:
	var ents: Array = sk.get("ents", [])
	return i >= 0 and i < ents.size() and String((ents[i] as Dictionary).get("k", "")) == "line"


## every residual, one entry per constraint or length dimension: [{"name", "r": PackedFloat64Array}] (all in doubles)
static func _res_all(sk: Dictionary, X: PackedFloat64Array) -> Array:
	var out: Array = []
	for c in sk.get("cons", []):
		var a := int(c.get("a", -1))
		var b := int(c.get("b", -1))
		var k := String(c.get("k", ""))
		var two := k in ["coin", "par", "perp", "eq", "ang"]
		if not _line_ok(sk, a) or (two and not _line_ok(sk, b)):
			out.append({"name": con_name(c), "r": PackedFloat64Array([1.0])})   # a reference to nothing: never holds
			continue
		var ax: float = X[4 * a + 2] - X[4 * a]
		var ay: float = X[4 * a + 3] - X[4 * a + 1]
		var la := maxf(sqrt(ax * ax + ay * ay), 1e-12)
		var bx := 0.0
		var by := 0.0
		var lb := 1.0
		if two:
			bx = X[4 * b + 2] - X[4 * b]
			by = X[4 * b + 3] - X[4 * b + 1]
			lb = maxf(sqrt(bx * bx + by * by), 1e-12)
		var r := PackedFloat64Array()
		match k:
			"h":
				r.append(ay)
			"v":
				r.append(ax)
			"coin":
				var pa := 4 * a + 2 * int(c.get("ap", 0))
				var pb := 4 * b + 2 * int(c.get("bp", 0))
				r.append(X[pa] - X[pb])
				r.append(X[pa + 1] - X[pb + 1])
			"par":
				r.append((ax * by - ay * bx) / (la * lb))
			"perp":
				r.append((ax * bx + ay * by) / (la * lb))
			"eq":
				r.append(la - lb)
			"ang":
				r.append((ax * bx + ay * by) / (la * lb) - cos(deg_to_rad(float(c.get("deg", 90.0)))))
		out.append({"name": con_name(c), "r": r})
	for d in sk.get("dims", []):
		if String(d.get("kind", "")) == "len" and _line_ok(sk, int(d.get("ent", -1))):
			var i := int(d["ent"])
			var dx: float = X[4 * i + 2] - X[4 * i]
			var dy: float = X[4 * i + 3] - X[4 * i + 1]
			out.append({"name": "length %s mm" % _short(float(d["mm"])), "r": PackedFloat64Array([sqrt(dx * dx + dy * dy) - float(d["mm"])])})
	return out


static func _flat(all: Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for e in all:
		out.append_array(e["r"])
	return out


## the name of the first constraint (or length) that does not hold now, "" when all hold
static func con_fail(sk: Dictionary) -> String:
	for e in _res_all(sk, _pts_of(sk)):
		for v in e["r"]:
			if absf(v) > CON_TOL:
				return String(e["name"])
	return ""


## moves the line ends so every constraint and length holds; pinned = {"ent:pt": true} ends that stay put. Writes the sketch's ents at full
## precision. Returns the largest residual left (0 = all hold; above CON_TOL = some constraint cannot hold)
static func solve(sk: Dictionary, pinned := {}) -> float:
	var X := _pts_of(sk)
	var free := PackedInt32Array()   # indices into X (one coordinate each)
	var ents: Array = sk.get("ents", [])
	for i in ents.size():
		if String(ents[i].get("k", "")) != "line":
			continue
		for j in 2:
			if not pinned.has("%d:%d" % [i, j]):
				free.append(4 * i + 2 * j)
				free.append(4 * i + 2 * j + 1)
	var r := _flat(_res_all(sk, X))
	var lam := 1e-3
	const H := 1e-6   # central differences in doubles: the error is ~1e-12, far under CON_TOL
	for it in 200:
		var cost := 0.0
		var mx := 0.0
		for v in r:
			cost += v * v
			mx = maxf(mx, absf(v))
		if mx < 1e-10 or free.is_empty() or r.is_empty():
			break
		var nf := free.size()
		var J: Array = []   # one column per free coordinate
		for k in nf:
			var Xp := X.duplicate()
			var Xm := X.duplicate()
			Xp[free[k]] += H
			Xm[free[k]] -= H
			var rp := _flat(_res_all(sk, Xp))
			var rm := _flat(_res_all(sk, Xm))
			var col := PackedFloat64Array()
			for q in r.size():
				col.append((rp[q] - rm[q]) / (2.0 * H))
			J.append(col)
		var A: Array = []
		var g := PackedFloat64Array()
		for k in nf:
			var row := PackedFloat64Array()
			for l in nf:
				var s := 0.0
				for q in r.size():
					s += float(J[k][q]) * float(J[l][q])
				row.append(s)
			A.append(row)
			var gk := 0.0
			for q in r.size():
				gk += float(J[k][q]) * r[q]
			g.append(gk)
		var stepped := false
		for tries in 16:
			var M: Array = []
			for k in nf:
				var row := PackedFloat64Array(A[k])
				row[k] += lam * (1.0 + float(A[k][k]))   # damping +lam on the diagonal: a free point no rule touches does not move
				M.append(row)
			var rhs := PackedFloat64Array()
			for k in nf:
				rhs.append(-g[k])
			var dx := _lin(M, rhs)
			var Xn := X.duplicate()
			for k in nf:
				Xn[free[k]] += dx[k]
			var rn := _flat(_res_all(sk, Xn))
			var cn := 0.0
			for v in rn:
				cn += v * v
			if cn < cost:
				X = Xn
				r = rn
				lam = maxf(lam / 3.0, 1e-12)
				stepped = true
				break
			lam *= 4.0
		if not stepped:
			break
	for i in ents.size():
		if String(ents[i].get("k", "")) == "line":
			ents[i]["a"] = [X[4 * i], X[4 * i + 1]]
			ents[i]["b"] = [X[4 * i + 2], X[4 * i + 3]]
	var worst := 0.0
	for v in _flat(_res_all(sk, _pts_of(sk))):
		worst = maxf(worst, absf(v))
	return worst


## Gaussian elimination with partial pivoting (M is n rows of n floats)
static func _lin(M: Array, rhs: PackedFloat64Array) -> PackedFloat64Array:
	var n := rhs.size()
	var A: Array = []
	for k in n:
		A.append(PackedFloat64Array(M[k]))
	var b := rhs.duplicate()
	for c in n:
		var piv := c
		for rr in range(c + 1, n):
			if absf(A[rr][c]) > absf(A[piv][c]):
				piv = rr
		var tmp = A[c]
		A[c] = A[piv]
		A[piv] = tmp
		var tb: float = b[c]
		b[c] = b[piv]
		b[piv] = tb
		if absf(A[c][c]) < 1e-18:
			continue
		for rr in range(c + 1, n):
			var f: float = A[rr][c] / A[c][c]
			for cc in range(c, n):
				A[rr][cc] -= f * A[c][cc]
			b[rr] -= f * b[c]
	var x := PackedFloat64Array()
	x.resize(n)
	for c in range(n - 1, -1, -1):
		var s: float = b[c]
		for cc in range(c + 1, n):
			s -= A[c][cc] * x[cc]
		x[c] = s / A[c][c] if absf(A[c][c]) >= 1e-18 else 0.0
	return x


## adds a constraint to the sketch. Returns "" when it is added, else the plain words why not; a refused one changes NOTHING. An angle
## between the same two lines replaces the old angle.
static func con_put(sk: Dictionary, c: Dictionary) -> String:
	var k := String(c["k"])
	var a := int(c["a"])
	var b := int(c.get("b", -1))
	var word := String(CON_WORDS[k])
	var one := k == "h" or k == "v"
	if not _line_ok(sk, a) or (not one and not _line_ok(sk, b)):
		return ("%s needs a line (draw it with Line first)" % word) if one else ("%s needs two lines (draw them with Line first)" % word)
	if k == "coin" and a == b:
		return "Coincident needs two different lines"
	var kept: Array = []
	for o in sk.get("cons", []):
		var same_pair := int(o.get("a", -1)) == a and int(o.get("b", -1)) == b
		var swap_pair := int(o.get("a", -1)) == b and int(o.get("b", -1)) == a
		var same_kind := String(o.get("k", "")) == k
		if same_kind and k == "ang" and (same_pair or swap_pair):
			continue   # the new angle replaces the old one
		if same_kind and one and int(o.get("a", -1)) == a:
			return "%s already holds for that line" % word
		if same_kind and not one and k != "ang" and (same_pair or swap_pair):
			return "%s already holds for those two lines" % word
		kept.append(o)
	kept.append(c.duplicate())
	var trial: Dictionary = sk.duplicate(true)
	trial["cons"] = kept
	solve(trial)
	var bad := con_fail(trial)
	if bad != "":
		if bad == con_name(c):
			return "Cannot add %s: the lines cannot take that rule together with the others here. Nothing changed." % con_name(c)
		return "Cannot add %s: it would break %s. Nothing changed." % [con_name(c), bad]
	sk["cons"] = kept
	sk["ents"] = trial["ents"]
	return ""


## a dimension typed on a sketch (its size, mm): applied only when every constraint still holds (else nothing changes, and the words why)
static func set_dim_held(sk: Dictionary, ent: int, kind: String, mm: float, bind := {}) -> String:
	var ents0: Array = (sk["ents"] as Array).duplicate(true)
	var dims0: Array = (sk.get("dims", []) as Array).duplicate(true)
	set_dim(sk, ent, kind, mm, bind)
	solve(sk)
	var bad := con_fail(sk)
	if bad != "":
		sk["ents"] = ents0
		sk["dims"] = dims0
		return "Cannot set that size: it would break %s. Nothing changed." % bad
	return ""


## the constraints that point at a line no longer in the sketch are dropped (a deleted line takes its constraints with it)
static func prune_cons(sk: Dictionary) -> void:
	if not sk.has("cons"):
		return
	var keep: Array = []
	for c in sk["cons"]:
		var ok := _line_ok(sk, int(c.get("a", -1)))
		if String(c.get("k", "")) not in ["h", "v"]:
			ok = ok and _line_ok(sk, int(c.get("b", -1)))
		if ok:
			keep.append(c)
	sk["cons"] = keep
