## WEAPON CLASH (ROADMAP 37): where two fighters' weapons meet over the timeline. Static, no UI (main.gd's "Check: weapon
## clashes" runs it, prints the report and puts a spark at each contact). Fighters are Choreo's: [{"name", "S": Scene,
## "xf": Transform3D}], the hero first (xf IDENTITY). Each weapon is its axis (knob -> tip) with a radius: the bat's barrel,
## the off-hand weapon's blade.
## SAMPLING: every fighter is posed every 1/240 s (SUB_HZ), so a swing that crosses a whole weapon between two frames is
## still seen. For each pair of weapons, at each sample:
##   dist = the closest distance between the two axes minus the two radii (<= 0: the weapons touch)
##   V    = the triple product (cB - cA) . (dA x dB): zero when the axes cross, and its sign flips when one weapon passes
##          through the other. A flip between two samples is refined by bisection (BISECT steps); if the weapons touch at the
##          instant of the flip it is a PASS-THROUGH: the weapons went through each other between two samples (MUST FIX).
## EVENTS (a run of touching samples with no pass-through inside it), at its first touch (the impact):
##   CLASH   both contact points move (each >= STATIC) and their relative speed >= CLASH_MIN
##   PARRY   one contact point is nearly static (< STATIC): the guard; the other one strikes
##   (a touch with relative speed under CLASH_MIN is a brush and is not reported)
## The contact point is the midpoint of the two closest points of the axes (hero's space). Each event:
## {"kind", "t", "frame", "a", "b" (fighter numbers), "wa", "wb" (weapon names), "point", "rel", "va", "vb" (m/s),
##  "text"}; for a PARRY "guard" is the fighter whose contact point is the slower one.
class_name WeaponClash

const STATIC := 0.5      # m/s: a contact point this slow is a guard
const CLASH_MIN := 2.0   # m/s: relative speed of the two contact points for a CLASH (below: a brush, not reported)
const SUB_HZ := 240.0    # the samples a second (the rate Dummy uses for fighter hits)
const BISECT := 8        # bisection steps that place a pass-through inside one sample step
const SPARK := 0.06      # m: a spark's spoke length
const SPOKES := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1),
	Vector3(0, 0, -1), Vector3(1, 1, 1), Vector3(-1, 1, -1), Vector3(1, -1, -1), Vector3(-1, -1, 1)]


## the weapons a body holds, in the fighter's space: [{"name" ("weapon" / "offhand"), "a", "b" (the axis), "r"}]
static func weapons(B: Body, xf: Transform3D) -> Array:
	var out := []
	if B.wep_on:
		var a: Vector3 = xf * B.wep_point(0.0)
		var b: Vector3 = xf * B.wep_point(B.wep_len)
		out.append({"name": "weapon", "a": a, "b": b, "r": float(B.rad["bat_barrel"])})
	if B.wep2_on:
		var c: Vector3 = xf * B.wep2_point(0.0)
		var d: Vector3 = xf * B.wep2_point(B.wep2_len())
		out.append({"name": "offhand", "a": c, "b": d, "r": float(B.rad.get("wep2_blade", 0.01))})
	return out


## the closest points of segments p1-q1 and p2-q2: [the point on the first, the point on the second]
static func closest(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Array:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-12 and e <= 1e-12:
		pass
	elif a <= 1e-12:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-12:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var den := a * e - b * b
			if den > 1e-12:
				s = clampf((b * f - c * e) / den, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return [p1 + d1 * s, p2 + d2 * t]


## the line triple product of two weapons' axes: zero when they cross; its sign flips when one passes through the other
static func tri(wa: Dictionary, wb: Dictionary) -> float:
	var ca: Vector3 = wa["a"]
	var cb: Vector3 = wb["a"]
	var da: Vector3 = (wa["b"] as Vector3) - ca
	var db: Vector3 = (wb["b"] as Vector3) - cb
	return (cb - ca).dot(da.cross(db))


static func named(list: Array, name: String) -> Dictionary:
	for w in list:
		if w["name"] == name:
			return w
	return {}


## the weapons of every fighter at t, each fighter posed by its own scene: [[weapon dicts], ...]
static func _poses(fighters: Array, bodies: Array, t: float) -> Array:
	var out := []
	for k in fighters.size():
		var f: Dictionary = fighters[k]
		(f["S"] as Scene).apply(bodies[k], t)
		out.append(weapons(bodies[k], f["xf"]))
	return out


## two fighters' named weapons at t (both posed at t): {"ok", "d" (surface gap, m), "pa", "pb" (the closest points)}
static func _contact(fighters: Array, bodies: Array, i: int, j: int, na: String, nb: String, t: float) -> Dictionary:
	var pw := _poses_pair(fighters, bodies, i, j, t)
	var wa := named(pw[0], na)
	var wb := named(pw[1], nb)
	if wa.is_empty() or wb.is_empty():
		return {"ok": false, "d": INF, "pa": Vector3.ZERO, "pb": Vector3.ZERO}
	var cp := closest(wa["a"], wa["b"], wb["a"], wb["b"])
	var pa: Vector3 = cp[0]
	var pb: Vector3 = cp[1]
	return {"ok": true, "d": pa.distance_to(pb) - float(wa["r"]) - float(wb["r"]), "pa": pa, "pb": pb,
		"tri": tri(wa, wb)}


## the weapons of fighters i and j at t
static func _poses_pair(fighters: Array, bodies: Array, i: int, j: int, t: float) -> Array:
	var fi: Dictionary = fighters[i]
	var fj: Dictionary = fighters[j]
	(fi["S"] as Scene).apply(bodies[i], t)
	(fj["S"] as Scene).apply(bodies[j], t)
	return [weapons(bodies[i], fi["xf"]), weapons(bodies[j], fj["xf"])]


## the first sample step's flip, refined: the instant (between t_lo and t_hi) where V changes sign
static func _flip_instant(fighters: Array, bodies: Array, i: int, j: int, na: String, nb: String, t_lo: float, t_hi: float, v_lo: float) -> float:
	var lo := t_lo
	var hi := t_hi
	for s in BISECT:
		var mid := 0.5 * (lo + hi)
		var c := _contact(fighters, bodies, i, j, na, nb, mid)
		var v: float = float(c["tri"]) if bool(c["ok"]) else 0.0
		if signf(v) == signf(v_lo):
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


## every clash of the fighters' weapons over the timeline (up to the longest fighter's length, or t_end when given):
## the events sorted by t. fps: the frames a second (the frame number of each event)
static func scan(fighters: Array, fps := 30.0, t_end := -1.0) -> Array:
	var out := []
	if fighters.size() < 2:
		return out
	var T := t_end
	if T < 0.0:
		T = 0.0
		for f in fighters:
			T = maxf(T, (f["S"] as Scene).length())
	var bodies := []
	for f in fighters:
		bodies.append(Choreo._body())
	var h := 1.0 / SUB_HZ
	var n := int(ceil(T * SUB_HZ))
	var W := []
	for k in n + 1:
		W.append(_poses(fighters, bodies, k * h))
	for i in fighters.size():
		for j in range(i + 1, fighters.size()):
			out.append_array(_pair(fighters, bodies, W, i, j, fps))
	out.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))
	return out


## the events of fighters i and j from their samples W (W[k][fighter] = its weapons at k / SUB_HZ)
static func _pair(fighters: Array, bodies: Array, W: Array, i: int, j: int, fps: float) -> Array:
	var h := 1.0 / SUB_HZ
	var runs := {}     # "wa|wb" -> {"k0", "k1", "wa", "wb"}: a run of touching samples
	var closed := []   # finished runs
	var prev := {}     # "wa|wb" -> the triple product at the last sample
	var passes := []   # [{"key", "t", "ev"}]
	for k in W.size():
		var t := k * h
		var seen := {}
		for wa in W[k][i]:
			for wb in W[k][j]:
				var key := "%s|%s" % [wa["name"], wb["name"]]
				seen[key] = true
				var cp := closest(wa["a"], wa["b"], wb["a"], wb["b"])
				var d := (cp[0] as Vector3).distance_to(cp[1]) - float(wa["r"]) - float(wb["r"])
				var v := tri(wa, wb)
				if prev.has(key):
					var pv: float = prev[key]
					if pv != 0.0 and v != 0.0 and signf(pv) != signf(v):
						var tp := _flip_instant(fighters, bodies, i, j, wa["name"], wb["name"], t - h, t, pv)
						var at := _contact(fighters, bodies, i, j, wa["name"], wb["name"], tp)
						if at["ok"] and float(at["d"]) <= 0.0:
							passes.append({"key": key, "t": tp, "ev": _event(fighters, bodies, i, j, wa["name"], wb["name"], tp, fps, "PASS-THROUGH")})
				prev[key] = v
				if d <= 0.0:
					if not runs.has(key):
						runs[key] = {"k0": k, "k1": k, "wa": wa["name"], "wb": wb["name"]}
					runs[key]["k1"] = k
				elif runs.has(key):
					closed.append(runs[key])
					runs.erase(key)
		for key in runs.keys():
			if not seen.has(key):
				closed.append(runs[key])
				runs.erase(key)
	closed.append_array(runs.values())
	var out := []
	for p in passes:
		out.append(p["ev"])
	for r in closed:
		var key := "%s|%s" % [r["wa"], r["wb"]]
		var swallowed := false
		for p in passes:
			if p["key"] == key and float(p["t"]) >= (int(r["k0"]) - 2) * h and float(p["t"]) <= (int(r["k1"]) + 2) * h:
				swallowed = true
		if swallowed:
			continue
		var ev := _run_event(fighters, bodies, i, j, r, fps)
		if not ev.is_empty():
			out.append(ev)
	return out


## a run of touching samples -> its CLASH or PARRY at the first touch ({} when it is only a brush)
static func _run_event(fighters: Array, bodies: Array, i: int, j: int, r: Dictionary, fps: float) -> Dictionary:
	var h := 1.0 / SUB_HZ
	var kind := _kind(fighters, bodies, i, j, r["wa"], r["wb"], float(r["k0"]) * h)
	if kind == "":
		return {}
	return _event(fighters, bodies, i, j, r["wa"], r["wb"], float(r["k0"]) * h, fps, kind)


## the classification at t: "CLASH", "PARRY", or "" (a brush)
static func _kind(fighters: Array, bodies: Array, i: int, j: int, na: String, nb: String, t: float) -> String:
	var v := _speeds(fighters, bodies, i, j, na, nb, t)
	if float(v["rel"]) < CLASH_MIN:
		return ""
	if minf(float(v["va"]), float(v["vb"])) < STATIC:
		return "PARRY"
	return "CLASH"


## the two contact points' speeds at t (central difference over one sample) and their relative speed
static func _speeds(fighters: Array, bodies: Array, i: int, j: int, na: String, nb: String, t: float) -> Dictionary:
	var h := 1.0 / SUB_HZ
	var before := _contact(fighters, bodies, i, j, na, nb, t - 0.5 * h)
	var after := _contact(fighters, bodies, i, j, na, nb, t + 0.5 * h)
	if not before["ok"] or not after["ok"]:
		return {"va": 0.0, "vb": 0.0, "rel": 0.0}
	var va: Vector3 = ((after["pa"] as Vector3) - (before["pa"] as Vector3)) / h
	var vb: Vector3 = ((after["pb"] as Vector3) - (before["pb"] as Vector3)) / h
	return {"va": va.length(), "vb": vb.length(), "rel": (va - vb).length(), "vav": va, "vbv": vb}


## one event at t (kind given by the caller; a PASS-THROUGH is reported whatever the speeds)
static func _event(fighters: Array, bodies: Array, i: int, j: int, na: String, nb: String, t: float, fps: float, kind: String) -> Dictionary:
	var c := _contact(fighters, bodies, i, j, na, nb, t)
	var v := _speeds(fighters, bodies, i, j, na, nb, t)
	var p: Vector3 = ((c["pa"] as Vector3) + (c["pb"] as Vector3)) * 0.5 if bool(c["ok"]) else Vector3.ZERO
	var guard := i if float(v["va"]) <= float(v["vb"]) else j
	var ev := {"kind": kind, "t": t, "frame": roundi(t * fps), "a": i, "b": j, "wa": na, "wb": nb,
		"point": p, "rel": float(v["rel"]), "va": float(v["va"]), "vb": float(v["vb"]), "guard": guard}
	ev["text"] = _text(ev, fighters)
	return ev


static func _text(ev: Dictionary, fighters: Array) -> String:
	var fa: String = fighters[int(ev["a"])]["name"]
	var fb: String = fighters[int(ev["b"])]["name"]
	var p: Vector3 = ev["point"]
	var where := "at (%.2f, %.2f, %.2f) m" % [p.x, p.y, p.z]
	var when := "%.3f s (frame %d)" % [float(ev["t"]), int(ev["frame"])]
	match String(ev["kind"]):
		"PASS-THROUGH":
			return "PASS-THROUGH %s: %s's %s goes through %s's %s %s, speed %.1f m/s: MUST FIX" % [when, fa, ev["wa"], fb, ev["wb"], where, float(ev["rel"])]
		"PARRY":
			var g := int(ev["guard"])
			var guard_is_a := g == int(ev["a"])
			var guard_name := fa if guard_is_a else fb
			var guard_weapon: String = ev["wa"] if guard_is_a else ev["wb"]
			var striker_name := fb if guard_is_a else fa
			var striker_weapon: String = ev["wb"] if guard_is_a else ev["wa"]
			return "PARRY %s: %s's %s holds the guard, %s's %s strikes it %s, relative speed %.1f m/s" % [when, guard_name,
				guard_weapon, striker_name, striker_weapon, where, float(ev["rel"])]
		_:
			return "CLASH %s: %s's %s and %s's %s meet %s, relative speed %.1f m/s (%.1f and %.1f m/s)" % [when, fa, ev["wa"], fb, ev["wb"], where, float(ev["rel"]), float(ev["va"]), float(ev["vb"])]


## a spark at a contact point: spokes in ten directions, yellow, drawn over the geometry (a child of the given node)
static func spark(point: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "spark"
	mi.position = point
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for d in SPOKES:
		im.surface_add_vertex(Vector3.ZERO)
		im.surface_add_vertex((d as Vector3).normalized() * SPARK)
	im.surface_end()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.85, 0.2)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	mi.material_override = m
	return mi
