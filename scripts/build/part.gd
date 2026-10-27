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
##     {"t": "hinge", "id": ..., "name": "Hinge1", "body": 0, "o": [x, y, z] (mm), "axis": [x, y, z], "track": [[t_s, deg], ...]}]}
## A HINGE (C3) turns body N (its index when the hinge comes) about the axis through o. Its angle is a Curves channel (seconds, degrees), the
## same as a Kine curve sampled to a list. The timeline shows the rest pose (the hinge adds no solid); hinge_sweep() walks the curve and reports the
## first frame the moving body meets another body (a door against its stop).
## Sketch entities (plane coordinates in mm): {"k": "line", "a", "b"}, {"k": "rect", "a", "b"} (two corners), {"k": "circle", "c", "r"},
## {"k": "arc", "a", "m", "b"} (from a to b through m), {"k": "bspline", "pts": [[x, y], ...], "closed"} (a smooth curve through the points; a
## closed one joins the last point to the first). A dimension: {"id", "ent": index, "kind": "w" | "h" | "len" | "r", "mm", "name"}; the
## entities always hold the dimension's result (apply_dim writes it), so a rebuild needs nothing else.
## An EDGE IS PICKED BY ITS CENTRE: a fillet stores where the edge was (mm), where it was inside its body's bounding box (0..1 per axis) and its
## direction; a rebuild picks the edge that best matches the box position and direction, so the fillet follows when a sketch is dimensioned
## bigger and the ids of the new shape are different. No match = that step fails (its message in the result), the later steps carry on.
## No DLL: available() is false, replay() answers with an empty result and every tool says why.

const KCad := preload("res://scripts/kcad.gd")
const MM := 0.001
const VERSION := 1
const KINDS := ["sketch", "extrude", "revolve", "fillet", "chamfer", "mirror", "hinge"]
const PLANES := ["front", "top", "right"]
const OPS := ["join", "new", "cut"]
const MATCH_MAX := 0.25   # an edge matches when (box-position distance + 0.5 x direction mismatch) is below this
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
		if String(f.get("sketch", "")) == id:
			return true
	return false


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
	var res := {"mesh": null, "volume": 0.0, "bodies": 0, "volumes": [], "errors": {}, "edges": [], "aabb": AABB(), "props": []}
	if not available():
		return res
	var feats: Array = rec.get("features", [])
	var n := feats.size() if upto < 0 else mini(upto + 1, feats.size())
	var bodies: Array = []
	var errs: Dictionary = res["errors"]
	var sketches := {}
	for i in n:
		var f: Dictionary = feats[i]
		var id := String(f["id"])
		match String(f["t"]):
			"sketch":
				var rs := resolved_sketch(f, want.get("body", null))   # C2: bound dimensions read the body given (none = an error)
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
			"fillet", "chamfer":
				var e := _edge_op(bodies, f)
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
		if want.get("edges", false):
			var es := KCad.edges(b)
			var bb := _bbox(es)
			for ed in es:
				res["edges"].append({"c": ed["center"], "a": ed["a"], "b": ed["b"], "d": ed["dir"], "len": ed["length"], "body": bodies.find(b), "q": _norm(ed["center"], bb)})
	res["bodies"] = bodies.size()
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
	var pl := plane(String(sk.get("plane", "front")))
	var face := KCad.sketch_face(items_of(sk["ents"]), pl["o"], pl["x"], pl["n"])
	if face == 0:
		return 0
	var s := 0
	if f["t"] == "extrude":
		s = KCad.extrude(face, float(f["dist"]) * MM, bool(f.get("both", false)))
	else:
		var axis: Vector3 = pl["x"] if String(f.get("axis", "x")) == "x" else pl["y"]
		s = KCad.revolve(face, pl["o"], axis, deg_to_rad(float(f.get("deg", 360.0))))
	KCad.release(face)
	return s


## puts a new solid into the body list as the op says; "" or the failure message
static func _combine(bodies: Array, solid: int, op: String) -> String:
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
