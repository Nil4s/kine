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
##     {"t": "chamfer", ... "dist": 1.0 ...},  {"t": "mirror", "id": ..., "plane": "front"|"top"|"right", "op": "join"}]}
## Sketch entities (plane coordinates in mm): {"k": "line", "a", "b"}, {"k": "rect", "a", "b"} (two corners), {"k": "circle", "c", "r"},
## {"k": "arc", "a", "m", "b"} (from a to b through m). A dimension: {"id", "ent": index, "kind": "w" | "h" | "len" | "r", "mm", "name"}; the
## entities always hold the dimension's result (apply_dim writes it), so a rebuild needs nothing else.
## An EDGE IS PICKED BY ITS CENTRE: a fillet stores where the edge was (mm), where it was inside its body's bounding box (0..1 per axis) and its
## direction; a rebuild picks the edge that best matches the box position and direction, so the fillet follows when a sketch is dimensioned
## bigger and the ids of the new shape are different. No match = that step fails (its message in the result), the later steps carry on.
## No DLL: available() is false, replay() answers with an empty result and every tool says why.

const KCad := preload("res://scripts/kcad.gd")
const MM := 0.001
const VERSION := 1
const KINDS := ["sketch", "extrude", "revolve", "fillet", "chamfer", "mirror"]
const PLANES := ["front", "top", "right"]
const OPS := ["join", "new", "cut"]
const MATCH_MAX := 0.25   # an edge matches when (box-position distance + 0.5 x direction mismatch) is below this

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


## sets (or adds) the dimension of entity `ent` and kind, and writes its result into the entity
static func set_dim(sk: Dictionary, ent: int, kind: String, mm: float) -> void:
	if not sk.has("dims"):
		sk["dims"] = []
	var dims: Array = sk["dims"]
	for d in dims:
		if int(d["ent"]) == ent and d["kind"] == kind:
			d["mm"] = mm
			apply_dim(sk["ents"], d)
			return
	var d := {"id": "d%d" % (dims.size() + 1), "ent": ent, "kind": kind, "mm": mm}
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
	return out


# ---------------------------------------------------------------- replay: features -> solids -> mesh

## Replays features 0..upto (-1 = all). want: {"edges": true} also lists every edge of the result for picking. Answers
## {"mesh": ArrayMesh or null, "volume": m3 (all bodies), "bodies": n, "volumes": [m3 each], "errors": {feature id: message}, "edges": [...], "aabb": AABB}.
## Every shape made here is released before it returns.
static func replay(rec: Dictionary, upto := -1, want := {}) -> Dictionary:
	var res := {"mesh": null, "volume": 0.0, "bodies": 0, "volumes": [], "errors": {}, "edges": [], "aabb": AABB()}
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
				sketches[id] = f
			"extrude", "revolve":
				var sk: Dictionary = sketches.get(String(f.get("sketch", "")), {})
				if sk.is_empty():
					errs[id] = "its sketch is gone"
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
	var mesh := ArrayMesh.new()
	for b in bodies:
		var v := KCad.volume(b)
		res["volumes"].append(v)
		res["volume"] = float(res["volume"]) + v
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
