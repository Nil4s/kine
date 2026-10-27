class_name PartTemplates
extends RefCounted
## EASY PART: templates = parametric feature lists in scripts/build/part.gd's terms (sword, axe, shield, chair, crate).
## A template makes the SAME record Expert edits, from a few named numbers (mm): rec["easy"] = {"t": "sword", "p": {"blade_length": 760, ...}, "n": features it owns}.
## The template owns the first n features (ids f1..fn, always the same ids); retemplate() rewrites exactly those when a number changes, and
## whatever the user added after them (Draw shape, Pull it up ...) stays. Expert sees plain features: "Exact sizes? Use Expert" needs no conversion.
## params: k (the name), label, lo / hi / def / step (mm), words (the two ends of its slider). dot_of() says which number an amber dot drags.

const MM := 0.001
const ARCH_R := 330.0   # mm: a car's wheel arch (the default wheel's 300 mm radius + 30 mm clearance), centred on the axle
const AXLE_Y := 150.0   # mm: the axle height in the car body's own frame (the wheel's 300 mm less the 150 mm clearance)
const ARCH_D := 120.0   # mm: how deep the arches go into the car's sides (the middle of the chassis is kept whole)
const ORDER :=["sword", "axe", "shield", "chair", "crate"]
const T := {
	"sword": {"title": "Sword", "params": [
		{"k": "blade_length", "label": "Blade length", "lo": 300.0, "hi": 1200.0, "def": 760.0, "step": 10.0, "words": ["Shorter", "Longer"]},
		{"k": "width", "label": "Width", "lo": 30.0, "hi": 120.0, "def": 68.0, "step": 2.0, "words": ["Thinner", "Wider"]},
		{"k": "guard_size", "label": "Guard size", "lo": 80.0, "hi": 240.0, "def": 130.0, "step": 10.0, "words": ["Smaller", "Bigger"]},
		{"k": "thickness", "label": "Thickness", "lo": 4.0, "hi": 16.0, "def": 7.0, "step": 1.0, "words": ["Thinner", "Thicker"]}]},
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
		{"k": "body_height", "label": "Height", "lo": 300.0, "hi": 1000.0, "def": 500.0, "step": 10.0, "words": ["Lower", "Taller"]},
		{"k": "wheelbase", "label": "Wheelbase", "lo": 1000.0, "hi": 3000.0, "def": 1584.0, "step": 20.0, "words": ["Shorter", "Longer"]}]},
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


## a closed outline given in the Right plane's (Y, Z) as Vector2(y, z): the plane's sketch x runs along -Z, its y is Y
static func _yz(pts: Array) -> Array:
	var sk := []
	for p in pts:
		sk.append(Vector2(-(p as Vector2).y, (p as Vector2).x))
	return _poly(sk)


## a closed outline given as Vector2(y, z) points (the car's side profile) with each corner rounded to its radius (mm, 0 = sharp):
## lines and arcs in the Right plane's sketch (x = -Z, y = Y). A corner's arc runs between the two tangent points.
static func _rounded(yz: Array, radii: Array) -> Array:
	var n := yz.size()
	var pts := []
	for p in yz:
		pts.append(Vector2(-(p as Vector2).y, (p as Vector2).x))
	var tp := []   # per corner: [tangent 1, arc middle, tangent 2] (a sharp corner: the corner three times)
	for i in n:
		var P: Vector2 = pts[i]
		var r: float = radii[i]
		if r <= 0.0:
			tp.append([P, P, P])
			continue
		var u1: Vector2 = (pts[(i - 1 + n) % n] - P).normalized()
		var u2: Vector2 = (pts[(i + 1) % n] - P).normalized()
		var th := acos(clampf(u1.dot(u2), -1.0, 1.0)) * 0.5   # half the corner's angle
		var bis := (u1 + u2).normalized()
		var c := P + bis * (r / sin(th))
		tp.append([P + u1 * (r / tan(th)), c - bis * r, P + u2 * (r / tan(th))])
	var out := []
	for i in n:
		var cur: Array = tp[i]
		if float(radii[i]) > 0.0:
			out.append({"k": "arc", "a": Part.arr2(cur[0]), "m": Part.arr2(cur[1]), "b": Part.arr2(cur[2])})
		var nx: Vector2 = tp[(i + 1) % n][0]
		if (cur[2] as Vector2).distance_to(nx) > 1e-3:
			out.append({"k": "line", "a": Part.arr2(cur[2]), "b": Part.arr2(nx)})
	return out


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
			var hw := w * 0.5
			# the blade tapers from the guard to 40 % of its width at the shoulder, then comes to a point
			_ex(fs, _sk(fs, "front", _poly([Vector2(0, -hw), Vector2(L - tip, -hw * 0.4), Vector2(L, 0), Vector2(L - tip, hw * 0.4), Vector2(0, hw)])), "extrude", th, "new", true)
			# a diamond section: the spine is th, the edges 6 % of it: the two shoulders come off each face, cut along the whole blade
			var e := th * 0.06
			for sg in [1.0, -1.0]:
				var m := 2.0
				var cut := [Vector2(-hw - m, sg * e), Vector2(-hw, sg * e), Vector2(0, sg * th * 0.5), Vector2(hw, sg * e), Vector2(hw + m, sg * e),
					Vector2(hw + m, sg * (th * 0.5 + m)), Vector2(-hw - m, sg * (th * 0.5 + m))]
				_ex(fs, _sk(fs, "right", _yz(cut)), "extrude", 2.0 * L + 20.0, "cut", true)
			_ex(fs, _sk(fs, "front", [_rect(Vector2(-6, -g * 0.5), Vector2(4, g * 0.5))]), "extrude", 8.0, "join", true)
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
			# a car in side profile (the Right plane: sketch x = -Z, the car drives along +Z; sketch y = Y), extruded across the width.
			# Order matters: the chassis, the two wheel arches cut through it, the chassis again across the middle (so the arches keep
			# only their sides), then the cabin (set back, narrower, sloped glass) on top. Corners are rounded with arcs in the sketch.
			var L: float = p["body_length"]
			var W: float = p["body_width"]
			var H: float = float(p["body_height"])
			var wb: float = p["wheelbase"]
			var h1 := H * 0.5           # the chassis top: the cabin's floor
			var zf := 0.08 * L          # the cabin's front foot (the bonnet runs from here to the nose)
			var zr := -0.18 * L         # the cabin's rear foot (the boot runs from here to the tail)
			var chassis := [Vector2(0, -L * 0.5), Vector2(0, L * 0.5), Vector2(H * 0.36, L * 0.5), Vector2(h1, zf), Vector2(h1, zr), Vector2(H * 0.42, -L * 0.5)]
			var cabin := [Vector2(h1, zf), Vector2(H, 0.02 * L), Vector2(H, -0.14 * L), Vector2(h1, zr)]
			_ex(fs, _sk(fs, "right", _rounded(chassis, [40.0, 40.0, 40.0, 0.0, 0.0, 40.0])), "extrude", W, "new", true)
			for zc in [wb * 0.5, -wb * 0.5]:
				_ex(fs, _sk(fs, "right", [{"k": "circle", "c": [-zc, AXLE_Y], "r": ARCH_R}]), "extrude", 2.0 * W, "cut", true)
			_ex(fs, _sk(fs, "right", _rounded(chassis, [40.0, 40.0, 40.0, 0.0, 0.0, 40.0])), "extrude", W - 2.0 * ARCH_D, "join", true)
			_ex(fs, _sk(fs, "right", _rounded(cabin, [0.0, 40.0, 40.0, 0.0])), "extrude", W * 0.84, "join", true)
		"wheel":
			# a tyre: the profile (width x radius) turned about the sketch's x axis = world X, the axle (side to side)
			var R: float = p["radius"]
			var w: float = p["width"]
			_ex(fs, _sk(fs, "front", [_rect(Vector2(-w * 0.5, 0.0), Vector2(w * 0.5, R))]), "revolve", 0.0, "new")
	return fs


## a handle in another material than the Part's: [material, last steel feature], or [] when all of it is one material. The sword's
## pommel and grip (the features after its guard, index 7) are wood; its blade and guard are steel
static func handle_mat(rec: Dictionary) -> Array:
	if String(rec.get("easy", {}).get("t", "")) == "sword":
		return ["wood", 7]
	return []


## the handle's centre in the Part's own frame (m): the grip a hand holds (PartWeapon). A sword's grip is the revolve x -106..-2 mm; an axe's
## haft runs 0..H+10 mm. Other templates, and a Part with no template, hold at its origin.
static func handle_of(rec: Dictionary) -> Vector3:
	var e: Dictionary = rec.get("easy", {})
	match String(e.get("t", "")):
		"sword":
			return Vector3(-54.0 * MM, 0.0, 0.0)
		"axe":
			return Vector3(0.5 * (float(e["p"]["handle_length"]) + 10.0) * MM, 0.0, 0.0)
	return Vector3.ZERO


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
