class_name PartPipe3D
extends RefCounted
## s215 SWEEP ALONG A 3D PATH (Friday plan 215): a round tube along a path of points placed in 3D (typed X Y Z, or picked on a face / snapped to a corner),
## with smooth tangent bends. The record step: {"t": "pipe3d", "id", "name", "pts": [[x, y, z] mm, world], "r": outside radius mm, "wall": mm (0 = solid rod),
## "bend": centre-line bend radius mm (0 = 3 x r), "op": join|new|cut}.
## The path goes through the first and the last point; each point in between is a CORNER that is rounded with a tangent arc of the bend radius (the
## tube leaves the corner point on the inside of the bend, as every real bent pipe does). The kernel call is KineCAD.sweep (BRepOffsetAPI_MakePipe) on
## each straight leg (a 2-point wire from path_wire) and each bend (a planar arc from sketch_wire): the kernel's pipe along ONE wire with a kink leaves
## the second leg open, so the smooth pieces are swept one by one and fused (they meet face to face, end to end). A wall is the same path swept with the
## inner radius, cut out (the bore runs 1 mm past each end so the cut leaves clean open ends). The volume of the result must equal pi r^2 L (2 percent),
## L being the centre line (legs + bends), else nothing is made.

const KCad := preload("res://scripts/kcad.gd")
const MM := 0.001
const MIN_TURN := 0.01      # radians: a turn smaller than this is not a corner
const BEND_X := 3.0         # the default bend radius, in tube radii
const MIN_BEND_X := 1.2     # a bend tighter than this folds the inside of the tube


## the centre line: {"err", "legs": [[a, b]], "bends": [{"a", "m", "b", "rb", "th"}], "len": mm, "poly": mm (the corner-to-corner length)}. Points in mm.
static func plan(pts: Array, r: float, bend: float) -> Dictionary:
	var P: Array = []
	for q in pts:
		P.append(Vector3(float(q[0]), float(q[1]), float(q[2])))
	if P.size() < 2:
		return {"err": "a 3D pipe needs at least two points"}
	var poly := 0.0
	for i in range(1, P.size()):
		var d: float = P[i - 1].distance_to(P[i])
		if d < 0.05:
			return {"err": "points %d and %d are on the same spot" % [i, i + 1]}
		poly += d
	var rb0 := bend if bend > 0.0 else BEND_X * r
	# the corners: the turn, and how much of each leg the arc takes
	var t_at: Array = []
	var rb_at: Array = []
	var th_at: Array = []
	t_at.resize(P.size())
	rb_at.resize(P.size())
	th_at.resize(P.size())
	for i in range(1, P.size() - 1):
		var u: Vector3 = (P[i] - P[i - 1]).normalized()
		var w: Vector3 = (P[i + 1] - P[i]).normalized()
		var th := acos(clampf(u.dot(w), -1.0, 1.0))
		th_at[i] = th
		if th < MIN_TURN:
			t_at[i] = 0.0
			rb_at[i] = 0.0
			continue
		if th > PI - 0.02:
			return {"err": "the pipe turns back on itself at point %d" % (i + 1)}
		var lp: float = P[i - 1].distance_to(P[i])
		var ln: float = P[i].distance_to(P[i + 1])
		var room_p := lp * (0.5 if i - 1 > 0 else 0.98)   # a leg between two corners is shared half and half
		var room_n := ln * (0.5 if i + 1 < P.size() - 1 else 0.98)
		var tmax := minf(room_p, room_n)
		var tan_h := tan(th * 0.5)
		var rb := minf(rb0, tmax / tan_h)
		if rb < MIN_BEND_X * r:
			return {"err": "the legs at point %d are too short for a %.1f mm pipe to bend there (they need %.1f mm each; move the points apart or use a smaller pipe)" % [i + 1, 2.0 * r, MIN_BEND_X * r * tan_h * 2.0]}
		rb_at[i] = rb
		t_at[i] = rb * tan_h
	var legs: Array = []
	var bends: Array = []
	var total := 0.0
	var cur: Vector3 = P[0]
	for i in range(1, P.size()):
		var u2: Vector3 = (P[i] - P[i - 1]).normalized()
		var tt: float = float(t_at[i]) if i < P.size() - 1 else 0.0
		var end_leg: Vector3 = P[i] - u2 * tt
		legs.append([cur, end_leg])
		total += cur.distance_to(end_leg)
		if i < P.size() - 1 and tt > 0.0:
			var w2: Vector3 = (P[i + 1] - P[i]).normalized()
			var th2: float = th_at[i]
			var rb2: float = rb_at[i]
			var bis: Vector3 = (w2 - u2).normalized()
			var cen: Vector3 = P[i] + bis * (rb2 / cos(th2 * 0.5))
			var b_pt: Vector3 = P[i] + w2 * tt
			bends.append({"a": end_leg, "m": cen - bis * rb2, "b": b_pt, "rb": rb2, "th": th2, "u": u2, "w": w2})
			total += rb2 * th2
			cur = b_pt
		else:
			cur = end_leg
	return {"err": "", "legs": legs, "bends": bends, "len": total, "poly": poly}


## a unit vector square to d
static func _across(d: Vector3) -> Vector3:
	var a := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	return (a - d * a.dot(d)).normalized()


## the tube of radius ro (mm) along a plan: one fused solid (kernel id) or 0. ext: mm the first and last leg are lengthened by (the bore)
static func _tube(pl: Dictionary, ro: float, ext: float) -> int:
	var acc := 0
	var legs: Array = pl["legs"]
	var bends: Array = pl["bends"]
	var items: Array = []   # in path order: leg, bend, leg, ...
	for i in legs.size():
		var lg: Array = (legs[i] as Array).duplicate()
		var a: Vector3 = lg[0]
		var b: Vector3 = lg[1]
		var dd := (b - a).normalized()
		if i == 0:
			a -= dd * ext
		if i == legs.size() - 1:
			b += dd * ext
		items.append({"k": "leg", "a": a, "b": b})
		if i < bends.size():
			items.append({"k": "bend", "bd": bends[i]})
	for it in items:
		var s := 0
		if String(it["k"]) == "leg":
			s = _sweep_leg(it["a"] * MM, it["b"] * MM, ro * MM)
		else:
			s = _sweep_bend(it["bd"], ro * MM)
		if s == 0:
			if acc != 0:
				KCad.release(acc)
			return 0
		if acc == 0:
			acc = s
			continue
		var u := KCad.union(acc, s)
		KCad.release(acc)
		KCad.release(s)
		if u == 0:
			return 0
		acc = u
	return acc


static func _sweep_leg(a: Vector3, b: Vector3, r: float) -> int:
	var d := (b - a).normalized()
	var face := KCad.sketch_face([KCad.circle(Vector2.ZERO, r)], a, _across(d), d)
	var wire := KCad.path_wire(PackedVector3Array([a, b]))
	if face == 0 or wire == 0:
		KCad.release(face)
		KCad.release(wire)
		return 0
	var s := KCad.sweep(face, wire)
	KCad.release(face)
	KCad.release(wire)
	return s


static func _sweep_bend(bd: Dictionary, r: float) -> int:
	var a: Vector3 = (bd["a"] as Vector3) * MM
	var m: Vector3 = (bd["m"] as Vector3) * MM
	var b: Vector3 = (bd["b"] as Vector3) * MM
	var u: Vector3 = bd["u"]
	var w: Vector3 = bd["w"]
	var n := u.cross(w).normalized()
	var y := n.cross(u)
	var to2 := func(p: Vector3) -> Vector2: return Vector2((p - a).dot(u), (p - a).dot(y))
	var wire := KCad.sketch_wire([KCad.arc(to2.call(a), to2.call(m), to2.call(b))], a, u, n)
	var face := KCad.sketch_face([KCad.circle(Vector2.ZERO, r)], a, _across(u), u)
	if wire == 0 or face == 0:
		KCad.release(wire)
		KCad.release(face)
		return 0
	var s := KCad.sweep(face, wire)
	KCad.release(wire)
	KCad.release(face)
	return s


## the whole tube as a kernel solid. Returns {"err", "solid", "len": mm centre line}
static func build(f: Dictionary) -> Dictionary:
	var r := float(f.get("r", 0.0))
	var wall := float(f.get("wall", 0.0))
	if r <= 0.0:
		return {"err": "the pipe needs a width"}
	if wall < 0.0 or (wall > 0.0 and wall > r - 0.2):
		return {"err": "the wall is as thick as the pipe: use a thinner wall"}
	var pl := plan(f.get("pts", []), r, float(f.get("bend", 0.0)))
	if String(pl["err"]) != "":
		return {"err": String(pl["err"])}
	var outer := _tube(pl, r, 0.0)
	if outer == 0:
		return {"err": "the kernel could not sweep the pipe: " + KCad.last_error()}
	var want := PI * r * r * float(pl["len"]) * MM * MM * MM
	if absf(KCad.volume(outer) - want) > 0.02 * want:
		KCad.release(outer)
		return {"err": "the pipe folds on itself: bend it less sharply or use a thinner pipe"}
	if wall > 0.0:
		var bore := _tube(pl, r - wall, 1.0)
		if bore == 0:
			KCad.release(outer)
			return {"err": "the kernel could not sweep the bore: " + KCad.last_error()}
		var c := KCad.cut(outer, bore)
		KCad.release(outer)
		KCad.release(bore)
		if c == 0:
			return {"err": "the kernel could not hollow the pipe: " + KCad.last_error()}
		outer = c
	return {"err": "", "solid": outer, "len": float(pl["len"])}


## replay: the step adds its tube to the bodies. "" or the message.
static func add(bodies: Array, f: Dictionary) -> String:
	var got := build(f)
	if String(got["err"]) != "":
		return String(got["err"])
	return Part._combine(bodies, int(got["solid"]), String(f.get("op", "join")))
