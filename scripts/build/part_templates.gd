class_name PartTemplates
extends RefCounted
## EASY PART: templates = parametric feature lists in scripts/build/part.gd's terms (sword, axe, shield, chair, crate).
## A template makes the SAME record Expert edits, from a few named numbers (mm): rec["easy"] = {"t": "sword", "p": {"blade_length": 760, ...}, "n": features it owns}.
## The template owns the first n features (ids f1..fn, always the same ids); retemplate() rewrites exactly those when a number changes, and
## whatever the user added after them (Draw shape, Pull it up ...) stays. Expert sees plain features: "Exact sizes? Use Expert" needs no conversion.
## params: k (the name), label, lo / hi / def / step (mm), words (the two ends of its slider). dot_of() says which number an amber dot drags.

const MM := 0.001
const ARCH_GAP := 40.0   # mm: a car's wheel arch top sits this far above the tyre's top (the arch is the wheel radius + 40 mm)
const CAB_W := 0.88     # the glasshouse is this share of the body's width (narrower than the lower body, so the cabin reads as a cabin)
const ORDER :=["sword", "axe", "shield", "chair", "gear", "crate"]   # NGEAR: Gear sits before Crate (Crate stays the last chip); its numbers are not cm: "raw"
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
	# NGEAR: a spur gear with a centre hole. Real pitch diameter = teeth x module: tip = module x (teeth + 2), root = module x (teeth - 2.5). Default 30 teeth: a 64 mm gear reads in the 3/4 view.
	# raw: the slider's own numbers (a tooth count, a size step 1 = Small / Medium / Big teeth = module 1 / 2 / 3, a thickness in mm), not cm
	"gear": {"title": "Gear", "params": [
		{"k": "teeth", "label": "Teeth", "lo": 8.0, "hi": 60.0, "def": 30.0, "step": 1.0, "words": ["Fewer", "More"], "raw": true, "unit": "teeth"},
		{"k": "module", "label": "Teeth size", "lo": 1.0, "hi": 3.0, "def": 2.0, "step": 1.0, "words": ["Small teeth", "Big teeth"], "raw": true, "unit": "size"},
		{"k": "thickness", "label": "Thickness", "lo": 3.0, "hi": 30.0, "def": 10.0, "step": 1.0, "words": ["Thinner", "Thicker"], "raw": true, "unit": "mm"}]},
	# p067hinges: a hinge from the Hinge chip (not in ORDER: its own button beside Parts). Sized to the door: the door's height (mm) sets the
	# leaves (butt and living: door / 21 rounded to 5 mm, so 100 mm at 2100) or the strip (piano: the full door height). kind: 1 Butt, 2 Piano, 3 Living.
	"hinge": {"title": "Hinge", "params": [
		{"k": "door", "label": "Door height", "lo": 1800.0, "hi": 2400.0, "def": 2100.0, "step": 100.0, "words": ["Shorter door", "Taller door"], "raw": true, "unit": "mm"},
		{"k": "kind", "label": "Kind", "lo": 1.0, "hi": 3.0, "def": 1.0, "step": 1.0, "words": ["Butt", "Living"], "raw": true, "unit": "kind"}]},
	# VEHICLE PARTS (B3, scripts/vehicle.gd): not in ORDER, so no Easy chip: a car body and one wheel
	"car": {"title": "Car body", "params": [
		{"k": "body_length", "label": "Length", "lo": 1500.0, "hi": 5000.0, "def": 4000.0, "step": 50.0, "words": ["Shorter", "Longer"]},
		{"k": "body_width", "label": "Width", "lo": 1000.0, "hi": 2200.0, "def": 1750.0, "step": 20.0, "words": ["Narrower", "Wider"]},
		{"k": "body_height", "label": "Height", "lo": 900.0, "hi": 1800.0, "def": 1450.0, "step": 10.0, "words": ["Lower", "Taller"]},
		{"k": "wheelbase", "label": "Wheelbase", "lo": 1000.0, "hi": 3000.0, "def": 2500.0, "step": 20.0, "words": ["Shorter", "Longer"]},
		# the wheel's radius, copied in by Vehicle.make_set and the Easy screen (the arches follow it); no slider of its own on the car
		{"k": "wheel_r", "label": "Wheel size", "lo": 100.0, "hi": 600.0, "def": 320.0, "step": 10.0, "words": ["Smaller", "Bigger"]}]},
	"wheel": {"title": "Wheel", "params": [
		{"k": "radius", "label": "Radius", "lo": 100.0, "hi": 600.0, "def": 320.0, "step": 10.0, "words": ["Smaller", "Bigger"]},
		{"k": "width", "label": "Width", "lo": 50.0, "hi": 400.0, "def": 200.0, "step": 10.0, "words": ["Thinner", "Wider"]}]},
	# NSCREW2: a screw from the Parts category (not in ORDER: no template chip). d = the nominal size (M3..M6, mm), L = the length under the head (mm).
	# Its numbers are picked by the Parts chips (easy_part.gd), so its sliders are hidden there ("parts": true).
	"screw": {"title": "Screw", "parts": true, "params": [
		{"k": "d", "label": "Size", "lo": 3.0, "hi": 6.0, "def": 4.0, "step": 1.0, "words": ["Smaller", "Bigger"]},
		{"k": "L", "label": "Length", "lo": 10.0, "hi": 30.0, "def": 16.0, "step": 1.0, "words": ["Shorter", "Longer"]}]},
}

## NSCREW2: ISO 4762 socket head screws: nominal size -> [head diameter, head height] (mm). The shank is the nominal size, plain (no thread).
const SCREW_HEAD := {3: [5.5, 3.0], 4: [7.0, 4.0], 5: [8.5, 5.0], 6: [10.0, 6.0]}
## NNUTWASHER: ISO 4032 nut [across flats, thickness] and ISO 7089 washer [inside, outside, thickness] (mm), by the nominal size M3..M6.
## They stand on the floor beside the screw: the washer's centre at X 18 mm, the nut's at X 40 mm (the screw's head is under 6 mm wide).
const NUT_ISO := {3: [5.5, 2.4], 4: [7.0, 3.2], 5: [8.0, 4.7], 6: [10.0, 5.2]}
const WASH_ISO := {3: [3.2, 7.0, 0.5], 4: [4.3, 9.0, 0.8], 5: [5.3, 10.0, 1.0], 6: [6.4, 12.0, 1.6]}
const NW_WASHER_X := 18.0
const NW_NUT_X := 40.0
const NW_N := 8   # the features the nut and washer take: a washer (a disc, a bore cut) and a nut (a hex, a bore cut)


## NNUTWASHER: the nut and washer features for size d, appended to fs (the screw's features, so the ids go on from them). Returns only the new ones.
## Both are sketched on the Top plane (sketch x = X, the normal is up Y), so they stand on the floor with their holes along Y.
static func nw_features(fs: Array, d: int) -> Array:
	var base := fs.size()
	var sd := clampi(int(roundf(float(d))), 3, 6)
	var w: Array = WASH_ISO[sd]
	var wc := [NW_WASHER_X, 0.0]
	_ex(fs, _sk(fs, "top", [{"k": "circle", "c": wc, "r": float(w[1]) * 0.5}]), "extrude", float(w[2]), "new")
	_ex(fs, _sk(fs, "top", [{"k": "circle", "c": wc, "r": float(w[0]) * 0.5}]), "extrude", float(w[2]) + 2.0, "cut")
	var n: Array = NUT_ISO[sd]
	var R: float = float(n[0]) / sqrt(3.0)   # a corner's radius: the corners point along X, the flats face Z
	var hex := []
	for k in 6:
		hex.append(Vector2(NW_NUT_X + R * cos(float(k) * PI / 3.0), R * sin(float(k) * PI / 3.0)))
	_ex(fs, _sk(fs, "top", _poly(hex)), "extrude", float(n[1]), "new")
	_ex(fs, _sk(fs, "top", [{"k": "circle", "c": [NW_NUT_X, 0.0], "r": float(sd) * 0.5}]), "extrude", float(n[1]) + 2.0, "cut")
	return fs.slice(base)


## NNUTWASHER: a screw on the floor takes its nut and washer: they go on the END of the record and the easy record remembers where ("nw" = their first index)
static func nw_add(rec: Dictionary, d: int) -> void:
	var feats: Array = rec["features"]
	var start := feats.size()
	feats.append_array(nw_features(feats.duplicate(), d))
	rec["seq"] = maxi(int(rec.get("seq", 0)), feats.size())
	(rec["easy"] as Dictionary)["nw"] = start


## NNUTWASHER: a size change rewrites the nut and washer too (same count for every size, so the features after them keep their ids). Does nothing without them.
static func nw_set(rec: Dictionary, d: int) -> void:
	var e: Dictionary = rec.get("easy", {})
	if e.is_empty() or int(e.get("nw", -1)) < 0:
		return
	var start := int(e["nw"])
	var feats: Array = rec["features"]
	var head: Array = feats.slice(0, start)
	var rest: Array = feats.slice(mini(start + NW_N, feats.size()))
	rec["features"] = head + nw_features(head.duplicate(), d) + rest


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


## a round (fillet) that no longer replays after a size changed: its radius shrinks to the biggest of 0.5 / 0.3 / 0.2 / 0.1 mm (or 1 mm and
## less than the old one) that works; when none does, the edges that still take 0.1 mm are kept and the rest left out; a round with no edge
## left is taken off. Returns the words for the user ("" when every round replays). Only fillets with an error are touched.
static func fit_rounds(rec: Dictionary) -> String:
	if not rec.has("features"):   # no part at all (the {} record: Expert took its empty sketch out): no round to fit
		return ""
	var note := ""
	var i := 0
	while i < (rec["features"] as Array).size():
		var f: Dictionary = rec["features"][i]
		if String(f["t"]) != "fillet" or String(Part.replay(rec)["errors"].get(String(f["id"]), "")) == "":
			i += 1
			continue
		var r0 := float(f["r"])
		var cands := []
		for c in [r0 * 0.5, 1.0, 0.5, 0.3, 0.2, 0.1]:
			var cc := snappedf(float(c), 0.1)
			if cc < r0 - 1e-6 and cc >= 0.1 - 1e-6 and not cands.has(cc):
				cands.append(cc)
		cands.sort()
		cands.reverse()
		var done := false
		for c in cands:
			f["r"] = c
			if String(Part.replay(rec)["errors"].get(String(f["id"]), "")) == "":
				note = "The round is now %s mm: the part is too small for %s mm" % [str(c), str(r0)]
				done = true
				break
		if not done:
			var all_edges: Array = (f["edges"] as Array).duplicate(true)
			var good := []
			f["r"] = 0.1
			f["edges"] = []
			for e in all_edges:
				var trial := good.duplicate(true)
				trial.append(e)
				f["edges"] = trial
				if String(Part.replay(rec)["errors"].get(String(f["id"]), "")) == "":
					good = trial
			f["edges"] = good
			if good.is_empty():
				(rec["features"] as Array).remove_at(i)
				note = "Too thin to round now: the round was taken off"
				continue
			note = "Some edges are too small to round now: the others are rounded"
		i += 1
	return note


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
		"screw":
			# NSCREW2: one lathe profile (x = radius, y = height, mm) spun round the up axis (Y), from the floor: the shank, then the head on top
			var sd := clampi(int(roundf(float(p["d"]))), 3, 6)
			var hd: Array = SCREW_HEAD[sd]
			var sl: float = float(p["L"])
			var r := float(sd) * 0.5
			var R: float = float(hd[0]) * 0.5
			var hk: float = float(hd[1])
			var prof := [Vector2(0, 0), Vector2(r, 0), Vector2(r, sl), Vector2(R, sl), Vector2(R, sl + hk), Vector2(0, sl + hk)]
			var sid := _sk(fs, "front", _poly(prof))
			_ex(fs, sid, "revolve", 0.0, "new")
			fs[fs.size() - 1]["axis"] = "y"
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
			# The lower body (sills at the wheel centre's height, the belt at 55 % of the height, nose and tail rounded) is one extrusion
			# across the full width; each wheel arch is a circle of the wheel radius + 40 mm cut through it at its axle; the glasshouse
			# (windscreen 30 deg from horizontal, roof, rear hatch) is a narrower extrusion on the belt.
			var g := car_geom(p)
			var S: float = g["S"]
			var yb: float = g["yb"]
			var zn: float = g["zn"]
			var zt: float = g["zt"]
			var lower := [Vector2(S, zt), Vector2(yb, zt), Vector2(yb, g["zwb"]), Vector2(g["yn"], zn), Vector2(S, zn)]
			_ex(fs, _sk(fs, "right", _rounded(lower, [60.0, 80.0, 0.0, 120.0, 60.0])), "extrude", g["W"], "new", true)
			for zc in [float(p["wheelbase"]) * 0.5, -float(p["wheelbase"]) * 0.5]:
				_ex(fs, _sk(fs, "right", [{"k": "circle", "c": [-zc, S], "r": g["A"]}]), "extrude", 2.0 * g["W"], "cut", true)
			var cabin := [Vector2(yb, g["zwb"]), Vector2(g["H"], g["zrf"]), Vector2(g["H"], g["zrr"]), Vector2(yb, g["zrh"])]
			_ex(fs, _sk(fs, "right", _rounded(cabin, [0.0, 150.0, 150.0, 0.0])), "extrude", g["wc"], "join", true)
		"gear":
			# NGEAR: a spur gear in the front plane: a tooth outline of N teeth (the flanks cross the pitch circle at half a tooth pitch, so
			# the tooth is as wide as the space there), extruded 5 mm x module, with the centre hole (0.12 x pitch diameter) cut through
			var N := int(roundf(float(p["teeth"])))
			var md := float(int(roundf(float(p["module"]))))
			var th: float = p["thickness"]
			_ex(fs, _sk(fs, "front", gear_outline(N, md)), "extrude", th, "new")
			_ex(fs, _sk(fs, "front", [{"k": "circle", "c": [0.0, 0.0], "r": 0.12 * N * md}]), "extrude", th, "cut", true)
		"hinge":
			# p067hinges: in the front plane (x across, y up the door). Butt: a 60 mm plate, 2.5 mm thick, leaf length L. Piano: a 30 mm strip
			# the full door height, 1.5 mm. Living: the whole 60 mm strip 0.8 mm thick (a thin flexible strip; a web with thicker leaves did not build on the kernel).
			var door: float = p["door"]
			var L := clampf(roundf(door / 21.0 / 5.0) * 5.0, 60.0, 150.0)
			var kd := int(roundf(float(p["kind"])))
			if kd == 2:
				_ex(fs, _sk(fs, "front", [_rect(Vector2(-15.0, 0.0), Vector2(15.0, door))]), "extrude", 1.5, "new")
			elif kd == 3:
				_ex(fs, _sk(fs, "front", [_rect(Vector2(-30.0, 0.0), Vector2(30.0, L))]), "extrude", 0.8, "new")
			else:
				_ex(fs, _sk(fs, "front", [_rect(Vector2(-30.0, 0.0), Vector2(30.0, L))]), "extrude", 2.5, "new")
		"wheel":
			# a tyre: the profile (width x radius) turned about the sketch's x axis = world X, the axle (side to side)
			var R: float = p["radius"]
			var w: float = p["width"]
			_ex(fs, _sk(fs, "front", [_rect(Vector2(-w * 0.5, 0.0), Vector2(w * 0.5, R))]), "revolve", 0.0, "new")
	return fs


## NGEAR: the closed tooth outline of a spur gear with n teeth of module m (mm), as lines. Angles in units of q = pi / (2 n): a tooth is
## 4 q wide at its pitch circle; its tip spans 0.6 q each side of its middle, its root 1.5 q each side (the flank is straight, and it
## is 1.0 q each side where it crosses the pitch circle r = m n / 2). Tips at m (n + 2) / 2, roots at m (n - 2.5) / 2.
static func gear_outline(n: int, m: float) -> Array:
	var ra := m * (n + 2) * 0.5
	var rf := m * (n - 2.5) * 0.5
	var q := PI / (2.0 * n)
	var pts := []
	for k in n:
		var t := TAU * k / n
		pts.append(Vector2.from_angle(t - 0.6 * q) * ra)
		pts.append(Vector2.from_angle(t + 0.6 * q) * ra)
		pts.append(Vector2.from_angle(t + 1.5 * q) * rf)
		pts.append(Vector2.from_angle(t + 4.0 * q - 1.5 * q) * rf)
	return _poly(pts)


## the car body's side-profile numbers (mm, the body's own frame: Y up from the ground, Z forward; the car's wheel radius is p.wheel_r):
## S the sill (the wheel centre's height), A the arch radius (the wheel + ARCH_GAP), yb the belt (55 % of H), yn the nose top, zn / zt the nose
## and tail, zrf / zrr the roof's front and rear edges, zrh the hatch's foot on the belt, zwb the windscreen's foot (30 deg from horizontal)
static func car_geom(p: Dictionary) -> Dictionary:
	var L: float = p["body_length"]
	var W: float = p["body_width"]
	var H: float = p["body_height"]
	var R: float = p.get("wheel_r", 320.0)
	var yb := H * 0.55
	var zrr := -0.375 * L
	return {"L": L, "W": W, "H": H, "S": R, "A": R + ARCH_GAP, "yb": yb, "yn": 0.48 * H, "zn": L * 0.5, "zt": -L * 0.5,
		"zrf": 0.0, "zrr": zrr, "zrh": zrr - 0.075 * L, "zwb": (H - yb) * sqrt(3.0), "wc": W * CAB_W}


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
