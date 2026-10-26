class_name PartTemplates
extends RefCounted
## EASY PART: templates = parametric feature lists in scripts/build/part.gd's terms (sword, axe, shield, chair, crate).
## A template makes the SAME record Expert edits, from a few named numbers (mm): rec["easy"] = {"t": "sword", "p": {"blade_length": 760, ...}, "n": features it owns}.
## The template owns the first n features (ids f1..fn, always the same ids); retemplate() rewrites exactly those when a number changes, and
## whatever the user added after them (Draw shape, Pull it up ...) stays. Expert sees plain features: "Exact sizes? Use Expert" needs no conversion.
## params: k (the name), label, lo / hi / def / step (mm), words (the two ends of its slider). dot_of() says which number an amber dot drags.

const MM := 0.001
const ORDER := ["sword", "axe", "shield", "chair", "crate"]
const T := {
	"sword": {"title": "Sword", "params": [
		{"k": "blade_length", "label": "Blade length", "lo": 300.0, "hi": 1200.0, "def": 760.0, "step": 10.0, "words": ["Shorter", "Longer"]},
		{"k": "width", "label": "Width", "lo": 30.0, "hi": 120.0, "def": 68.0, "step": 2.0, "words": ["Thinner", "Wider"]},
		{"k": "guard_size", "label": "Guard size", "lo": 80.0, "hi": 240.0, "def": 130.0, "step": 10.0, "words": ["Smaller", "Bigger"]},
		{"k": "thickness", "label": "Thickness", "lo": 4.0, "hi": 16.0, "def": 8.0, "step": 1.0, "words": ["Thinner", "Thicker"]}]},
	"axe": {"title": "Axe", "params": [
		{"k": "handle_length", "label": "Handle length", "lo": 300.0, "hi": 1000.0, "def": 700.0, "step": 10.0, "words": ["Shorter", "Longer"]},
		{"k": "head_width", "label": "Blade width", "lo": 80.0, "hi": 300.0, "def": 160.0, "step": 10.0, "words": ["Narrower", "Wider"]},
		{"k": "head_thickness", "label": "Head thickness", "lo": 10.0, "hi": 50.0, "def": 24.0, "step": 2.0, "words": ["Thinner", "Thicker"]},
		{"k": "handle_thickness", "label": "Handle thickness", "lo": 20.0, "hi": 50.0, "def": 30.0, "step": 2.0, "words": ["Thinner", "Thicker"]}]},
	"shield": {"title": "Shield", "params": [
		{"k": "radius", "label": "Size", "lo": 150.0, "hi": 450.0, "def": 300.0, "step": 10.0, "words": ["Smaller", "Bigger"]},
		{"k": "thickness", "label": "Thickness", "lo": 6.0, "hi": 30.0, "def": 14.0, "step": 1.0, "words": ["Thinner", "Thicker"]},
		{"k": "boss", "label": "Middle bump", "lo": 20.0, "hi": 120.0, "def": 60.0, "step": 5.0, "words": ["Smaller", "Bigger"]}]},
	"chair": {"title": "Chair", "params": [
		{"k": "seat_height", "label": "Seat height", "lo": 300.0, "hi": 700.0, "def": 450.0, "step": 10.0, "words": ["Lower", "Higher"]},
		{"k": "seat_width", "label": "Seat width", "lo": 300.0, "hi": 600.0, "def": 420.0, "step": 10.0, "words": ["Narrower", "Wider"]},
		{"k": "seat_depth", "label": "Seat depth", "lo": 300.0, "hi": 600.0, "def": 420.0, "step": 10.0, "words": ["Shallower", "Deeper"]},
		{"k": "back_height", "label": "Back height", "lo": 200.0, "hi": 800.0, "def": 450.0, "step": 10.0, "words": ["Lower", "Taller"]}]},
	"crate": {"title": "Crate", "params": [
		{"k": "width", "label": "Width", "lo": 200.0, "hi": 900.0, "def": 500.0, "step": 10.0, "words": ["Narrower", "Wider"]},
		{"k": "height", "label": "Height", "lo": 200.0, "hi": 800.0, "def": 400.0, "step": 10.0, "words": ["Lower", "Taller"]},
		{"k": "depth", "label": "Depth", "lo": 200.0, "hi": 800.0, "def": 400.0, "step": 10.0, "words": ["Shallower", "Deeper"]},
		{"k": "lid", "label": "Lid overhang", "lo": 0.0, "hi": 60.0, "def": 20.0, "step": 5.0, "words": ["None", "More"]}]},
	# VEHICLE PARTS (B3, scripts/vehicle.gd): not in ORDER, so no Easy chip: a car body and one wheel
	"car": {"title": "Car body", "params": [
		{"k": "body_length", "label": "Length", "lo": 1500.0, "hi": 5000.0, "def": 2400.0, "step": 50.0, "words": ["Shorter", "Longer"]},
		{"k": "body_width", "label": "Width", "lo": 1000.0, "hi": 2200.0, "def": 1200.0, "step": 20.0, "words": ["Narrower", "Wider"]},
		{"k": "body_height", "label": "Height", "lo": 300.0, "hi": 1000.0, "def": 500.0, "step": 10.0, "words": ["Lower", "Taller"]}]},
	"wheel": {"title": "Wheel", "params": [
		{"k": "radius", "label": "Radius", "lo": 100.0, "hi": 600.0, "def": 300.0, "step": 10.0, "words": ["Smaller", "Bigger"]},
		{"k": "width", "label": "Width", "lo": 50.0, "hi": 400.0, "def": 200.0, "step": 10.0, "words": ["Thinner", "Wider"]}]},
}


## the default camera of a template: [yaw, pitch] degrees, a 3/4 view in which its main shape reads (the axe turns further so its blade face shows)
const VIEW := {"sword": [30.0, -22.0], "axe": [42.0, -20.0], "shield": [30.0, -18.0], "chair": [38.0, -22.0], "crate": [34.0, -24.0]}


static func view_of(t: String) -> Array:
	return VIEW.get(t, [30.0, -22.0])


static func defaults(t: String) -> Dictionary:
	var p := {}
	for d in T[t]["params"]:
		p[d["k"]] = d["def"]
	return p


static func param(t: String, k: String) -> Dictionary:
	for d in T[t]["params"]:
		if d["k"] == k:
			return d
	return {}


## a new record of template t (numbers p: missing ones are the defaults, all clamped to their range)
static func make(t: String, p := {}) -> Dictionary:
	var rec := Part.make(String(T[t]["title"]))
	var pp := defaults(t)
	for k in p:
		if pp.has(k):
			pp[k] = clampf(float(p[k]), float(param(t, k)["lo"]), float(param(t, k)["hi"]))
	var fs := features_of(t, pp)
	rec["features"] = fs
	rec["seq"] = fs.size()
	rec["easy"] = {"t": t, "p": pp, "n": fs.size()}
	return rec


## writes numbers into the record's template and rewrites the features it owns (the user's own later features stay)
static func retemplate(rec: Dictionary, p: Dictionary) -> void:
	var e: Dictionary = rec.get("easy", {})
	if e.is_empty():
		return
	var t := String(e["t"])
	for k in p:
		if (e["p"] as Dictionary).has(k):
			e["p"][k] = clampf(float(p[k]), float(param(t, k)["lo"]), float(param(t, k)["hi"]))
	var fs := features_of(t, e["p"])
	var feats: Array = rec["features"]
	for i in mini(fs.size(), feats.size()):
		feats[i] = fs[i]


static func _sk(fs: Array, plane_name: String, ents: Array) -> String:
	var id := "f%d" % (fs.size() + 1)
	var n := fs.filter(func(f): return f["t"] == "sketch").size() + 1
	fs.append({"t": "sketch", "id": id, "name": "Sketch%d" % n, "plane": plane_name, "ents": ents, "dims": []})
	return id


static func _ex(fs: Array, sketch_id: String, t: String, dist: float, op: String, both := false) -> void:
	var id := "f%d" % (fs.size() + 1)
	var n := fs.filter(func(g): return g["t"] == t).size() + 1
	var f := {"t": t, "id": id, "name": "%s%d" % [t.capitalize(), n], "sketch": sketch_id, "op": op}
	if t == "extrude":
		f["dist"] = dist
		f["both"] = both
	else:
		f["axis"] = "x"
		f["deg"] = 360.0
	fs.append(f)


static func _rect(a: Vector2, b: Vector2) -> Dictionary:
	return {"k": "rect", "a": Part.arr2(a), "b": Part.arr2(b)}


static func _poly(pts: Array) -> Array:
	var out := []
	for i in pts.size():
		out.append({"k": "line", "a": Part.arr2(pts[i]), "b": Part.arr2(pts[(i + 1) % pts.size()])})
	return out


static func features_of(t: String, p: Dictionary) -> Array:
	var fs: Array = []
	match t:
		"sword":
			var L: float = p["blade_length"]
			var w: float = p["width"]
			var g: float = p["guard_size"]
			var th: float = p["thickness"]
			var tip := minf(w * 1.6, L * 0.3)
			_ex(fs, _sk(fs, "front", _poly([Vector2(0, -w * 0.5), Vector2(L - tip, -w * 0.5), Vector2(L, 0), Vector2(L - tip, w * 0.5), Vector2(0, w * 0.5)])), "extrude", th, "new", true)
			_ex(fs, _sk(fs, "front", [_rect(Vector2(-6, -g * 0.5), Vector2(4, g * 0.5))]), "extrude", 14.0, "join", true)
			_ex(fs, _sk(fs, "front", [_rect(Vector2(-106, 0), Vector2(-2, 11))]), "revolve", 0.0, "join")
			_ex(fs, _sk(fs, "front", [_rect(Vector2(-124, 0), Vector2(-104, 15))]), "revolve", 0.0, "join")
		"axe":
			var H: float = p["handle_length"]
			var hw: float = p["head_width"]
			var ht: float = p["head_thickness"]
			var r: float = float(p["handle_thickness"]) * 0.5
			_ex(fs, _sk(fs, "front", [_rect(Vector2(0, 0), Vector2(H + 10, r))]), "revolve", 0.0, "new")
			var ey := maxf(r + 4.0, 18.0)
			# a bearded wedge: the poll and eye round the handle, then the blade flares to the edge (its lower corner hangs a little back: the beard)
			_ex(fs, _sk(fs, "front", _poly([Vector2(H - 40, -ey), Vector2(H + 10, -ey), Vector2(H + 85, -hw * 0.5), Vector2(H + 110, hw * 0.5), Vector2(H + 10, ey), Vector2(H - 40, ey)])), "extrude", ht, "join", true)
			# the edge is thinner than the eye: two thin wedges come off the faces, side-on (Top plane: sketch y runs along -Z)
			var edge := minf(4.0, ht * 0.3)
			var x0 := H + 10.0
			var x1 := H + 112.0
			var hz := ht * 0.5
			for sg in [1.0, -1.0]:   # one closed wire per sketch: one wedge off each face
				_ex(fs, _sk(fs, "top", _poly([Vector2(x0, sg * hz), Vector2(x1, sg * edge * 0.5), Vector2(x1, sg * (hz + 1.0)), Vector2(x0, sg * (hz + 1.0))])), "extrude", hw + 80.0, "cut", true)
		"shield":
			var R: float = p["radius"]
			var th: float = p["thickness"]
			var bo: float = p["boss"]
			_ex(fs, _sk(fs, "front", [{"k": "circle", "c": [0.0, 0.0], "r": R}]), "extrude", th, "new")
			_ex(fs, _sk(fs, "front", [{"k": "circle", "c": [0.0, 0.0], "r": bo}]), "extrude", th + bo * 0.4, "join")
		"crate":
			var w: float = p["width"]
			var h: float = p["height"]
			var d: float = p["depth"]
			var o: float = p["lid"]
			_ex(fs, _sk(fs, "front", [_rect(Vector2(0, 0), Vector2(w, h))]), "extrude", d, "new")
			_ex(fs, _sk(fs, "front", [_rect(Vector2(-o, h - 20), Vector2(w + o, h + 30))]), "extrude", d, "join")
		"chair":
			var sh: float = p["seat_height"]
			var w: float = p["seat_width"]
			var d: float = p["seat_depth"]
			var bh: float = p["back_height"]
			var st := 30.0
			var lt := 40.0
			_ex(fs, _sk(fs, "front", _poly([Vector2(0, sh), Vector2(w, sh), Vector2(w, 0), Vector2(w - lt, 0), Vector2(w - lt, sh - st), Vector2(lt, sh - st), Vector2(lt, 0), Vector2(0, 0)])), "extrude", d, "new")
			_ex(fs, _sk(fs, "front", [_rect(Vector2(0, sh - st), Vector2(w, sh + bh))]), "extrude", 30.0, "join")
			_ex(fs, _sk(fs, "right", [_rect(Vector2(-(d - lt), 0), Vector2(-lt, sh - st))]), "extrude", w, "cut")
		"car":
			# a box on the ground: length along the Top plane's sketch y (= -Z, the car drives along +Z), width along X, height up
			var L: float = p["body_length"]
			var W: float = p["body_width"]
			_ex(fs, _sk(fs, "top", [_rect(Vector2(-W * 0.5, -L * 0.5), Vector2(W * 0.5, L * 0.5))]), "extrude", float(p["body_height"]), "new")
		"wheel":
			# a tyre: the profile (width x radius) turned about the sketch's x axis = world X, the axle (side to side)
			var R: float = p["radius"]
			var w: float = p["width"]
			_ex(fs, _sk(fs, "front", [_rect(Vector2(-w * 0.5, 0.0), Vector2(w * 0.5, R))]), "revolve", 0.0, "new")
	return fs


## the amber drag dot of a template number: {"at": Vector3 (m), "axis": Vector3 (the way the number grows), "gain": mm of number per mm the dot moves}, or {}
static func dot_of(t: String, k: String, p: Dictionary) -> Dictionary:
	var s := MM
	match t + "." + k:
		"sword.blade_length":
			return {"at": Vector3(float(p["blade_length"]) * s, 0, 0), "axis": Vector3.RIGHT, "gain": 1.0}
		"sword.width":
			return {"at": Vector3(float(p["blade_length"]) * 0.45 * s, float(p["width"]) * 0.5 * s, 0), "axis": Vector3.UP, "gain": 2.0}
		"sword.guard_size":
			return {"at": Vector3(-1.0 * s, float(p["guard_size"]) * 0.5 * s, 0), "axis": Vector3.UP, "gain": 2.0}
		"axe.handle_length":
			return {"at": Vector3((float(p["handle_length"]) + 110.0) * s, 0, 0), "axis": Vector3.RIGHT, "gain": 1.0}
		"axe.head_width":
			return {"at": Vector3((float(p["handle_length"]) + 110.0) * s, float(p["head_width"]) * 0.5 * s, 0), "axis": Vector3.UP, "gain": 2.0}
		"shield.radius":
			return {"at": Vector3(float(p["radius"]) * s, 0, 0), "axis": Vector3.RIGHT, "gain": 1.0}
		"shield.boss":
			return {"at": Vector3(0, float(p["boss"]) * s, (float(p["thickness"]) + float(p["boss"]) * 0.4) * s), "axis": Vector3.UP, "gain": 1.0}
		"crate.width":
			return {"at": Vector3(float(p["width"]) * s, float(p["height"]) * 0.5 * s, 0), "axis": Vector3.RIGHT, "gain": 1.0}
		"crate.height":
			return {"at": Vector3(float(p["width"]) * 0.5 * s, float(p["height"]) * s, 0), "axis": Vector3.UP, "gain": 1.0}
		"chair.seat_height":
			return {"at": Vector3(float(p["seat_width"]) * s, float(p["seat_height"]) * s, float(p["seat_depth"]) * s), "axis": Vector3.UP, "gain": 1.0}
		"chair.back_height":
			return {"at": Vector3(float(p["seat_width"]) * 0.5 * s, (float(p["seat_height"]) + float(p["back_height"])) * s, 0), "axis": Vector3.UP, "gain": 1.0}
	return {}
