extends RefCounted
## C70 INVOLUTE GEAR (CH2 gap 1): a spur gear profile from module, teeth, pressure angle, profile shift and root fillet, as ONE closed sketch loop.
## The flank is the exact involute of the base circle, sampled so that the chord is within TOL mm of the curve everywhere (the number of points follows the
## gear: a 64-tooth wheel gets about 15 per flank, an 8-leaf pinion about 8). Closed form (the test restates it with its own Cartesian formula):
##   rp = m z / 2, rb = rp cos(pa), ra = rp + m (1 + x), rf = rp - m (1.25 - x)       x = the profile shift (in modules)
##   half tooth angle at the pitch circle ht = (pi/2 + 2 x tan pa) / z                   (tooth thickness there = m (pi/2 + 2 x tan pa))
##   a flank point at radius r >= rb sits at polar angle  c +- ( ht + inv(pa) - inv(acos(rb / r)) ),  inv(a) = tan a - a
## Tooth 0 is centred on +x. The root fillet is a circular arc of radius rho, tangent to the root circle and (as near as the sampled flank allows) to the flank.
## The loop comes out as plain line entities tagged "shape": "gear" (the first one carries the numbers in "gear"), the way C37's shapes do, so the kernel,
## dimensions, the file format and every old test read it as they read any sketch.

const TOL := 0.0015   # mm: the chord-to-curve distance the sampling keeps (a bar allows 0.005)
const MAX_FLANK := 40
const GAP_ARC_TOL := 0.003

static func inv(a: float) -> float:
	return tan(a) - a


static func geom(m: float, z: int, pa_deg: float, x: float) -> Dictionary:
	var rp := m * z * 0.5
	var pa := deg_to_rad(pa_deg)
	var rb := rp * cos(pa)
	return {"m": m, "z": z, "pa": pa, "x": x, "rp": rp, "rb": rb, "ra": rp + m * (1.0 + x), "rf": rp - m * (1.25 - x),
		"ht": (PI * 0.5 + 2.0 * x * tan(pa)) / float(z), "inv_pa": inv(pa)}


## "" when the numbers make a gear, else the reason in words
static func check(m: float, z: int, pa_deg: float, x: float, rho := -1.0) -> String:
	if m <= 0.0:
		return "The module must be above 0"
	if z < 6 or z > 400:
		return "The teeth must be between 6 and 400"
	if pa_deg < 5.0 or pa_deg > 35.0:
		return "The pressure angle must be between 5 and 35 degrees"
	if absf(x) > 1.5:
		return "The profile shift must be between -1.5 and 1.5"
	var g := geom(m, z, pa_deg, x)
	if g["rf"] <= 0.0:
		return "The root circle would be below zero: more teeth or less negative shift"
	if g["ra"] <= g["rb"] + 1e-6:
		return "The tip circle is inside the base circle: raise the profile shift or the teeth"
	var ta := theta(g, g["ra"])
	if ta <= 0.0:
		return "The teeth come to a point (too much shift for this pressure angle): lower the shift"
	var step := TAU / float(z)
	if 2.0 * (g["ht"] + g["inv_pa"]) >= step - 1e-4 and g["rf"] >= g["rb"]:
		return "The teeth are too crowded: lower the shift"
	return ""


## the polar half-angle (rad) of a flank at radius r (>= rb)
static func theta(g: Dictionary, r: float) -> float:
	return g["ht"] + g["inv_pa"] - inv(acos(minf(g["rb"] / r, 1.0)))


## the left flank (angle +theta) from radius r0 up to the tip as [radius, angle] pairs, spaced so the chord stays within TOL of the curve
static func flank(g: Dictionary, r0: float) -> Array:
	var rb: float = g["rb"]
	var t0 := sqrt(maxf((r0 / rb) * (r0 / rb) - 1.0, 0.0))
	var t1 := sqrt(maxf((g["ra"] / rb) * (g["ra"] / rb) - 1.0, 0.0))
	var n := clampi(int(ceil((t1 - t0) * sqrt(maxf(rb * t1, 1e-6) / (8.0 * TOL)))), 3, MAX_FLANK)
	var out := []
	for i in n + 1:
		var t := t0 + (t1 - t0) * float(i) / n
		var r := rb * sqrt(1.0 + t * t)
		out.append([r, theta(g, r)])
	return out


static func _pt(r: float, a: float) -> Vector2:
	return Vector2.from_angle(a) * r


## the left half of a tooth, seen from tooth 0 (centre +x), ordered from the root tangent point up to the tip: Vector2 points; also answers the root angle
## [points, angle of the root tangent point from the tooth centre]
static func _left_side(g: Dictionary, rho: float) -> Array:
	var rf: float = g["rf"]
	var r_start := maxf(g["rb"], rf)
	var fl := flank(g, r_start)
	var P := PackedVector2Array()
	for p in fl:
		P.append(_pt(p[0], p[1]))
	var th0: float = fl[0][1]
	var step := TAU / float(g["z"])
	var gap_half := step * 0.5 - th0   # the gap's half width, from the flank start to the middle of the gap
	var pts := PackedVector2Array()
	if rho > 1e-6 and gap_half > 1e-4:
		var rr := minf(rho, 0.9 * g["m"])
		for attempt in 6:
			var lo := 0.0
			var hi := gap_half * 0.98
			if _dmin(P, rf + rr, th0 + hi) < rr - 1e-9:
				rr *= 0.6   # the gap is too narrow for this fillet: a smaller one
				continue
			for it in 48:
				var mid := 0.5 * (lo + hi)
				if _dmin(P, rf + rr, th0 + mid) < rr:
					lo = mid
				else:
					hi = mid
			var cang := th0 + 0.5 * (lo + hi)
			var C := _pt(rf + rr, cang)
			var qi := 0
			var best := INF
			for i in P.size():
				var d := C.distance_to(P[i])
				if d < best:
					best = d
					qi = i
			var T := _pt(rf, cang)
			var a0 := (P[qi] - C).angle()
			var a1 := (T - C).angle()
			var sw := wrapf(a1 - a0, -PI, PI)   # the short way round
			var k := maxi(3, int(ceil(absf(sw) / 0.35)))
			var r0 := C.distance_to(P[qi])
			for j in k + 1:
				var f := float(j) / k
				pts.append(C + Vector2.from_angle(a0 + sw * f) * lerpf(r0, rr, f))   # from the flank end down to the root
			# the flank from the contact point up: P[qi + 1 ..]; reverse so the whole side runs root -> tip
			pts.reverse()
			for i in range(qi + 1, P.size()):
				pts.append(P[i])
			return [pts, cang]
	# no fillet: the flank from its start (a radial drop to the root first when the root is below the base circle)
	if rf < g["rb"] - 1e-9:
		pts.append(_pt(rf, th0))
	for i in P.size():
		pts.append(P[i])
	return [pts, th0]


## the shortest distance from the point of radius r and angle a to the sampled flank
static func _dmin(P: PackedVector2Array, r: float, a: float) -> float:
	var C := _pt(r, a)
	var best := INF
	for q in P:
		best = minf(best, C.distance_to(q))
	return best


## the closed outline (CCW, mm) of the whole gear about the origin, tooth 0 centred on +x. fillet: root fillet radius in mm (< 0: 0.38 module, 0: none)
static func outline(m: float, z: int, pa_deg := 20.0, x := 0.0, rho := -1.0) -> PackedVector2Array:
	if check(m, z, pa_deg, x, rho) != "":
		return PackedVector2Array()
	var g := geom(m, z, pa_deg, x)
	var rr: float = 0.38 * m if rho < 0.0 else rho
	var side := _left_side(g, rr)
	var L: PackedVector2Array = side[0]   # root -> tip, left (+angle) side
	var th_root: float = side[1]
	var step := TAU / float(z)
	var ra: float = g["ra"]
	var rf: float = g["rf"]
	var ta := theta(g, ra)
	var out := PackedVector2Array()
	for k in z:
		var c := step * k
		# right side (mirror of the left, tip -> root reversed to run root -> tip), CCW: gap, right side up, tip, left side down
		var rside := PackedVector2Array()
		for i in L.size():
			rside.append(Vector2(L[i].x, -L[i].y))
		for p in rside:
			out.append(p.rotated(c))
		# tip land
		var nt := maxi(2, int(ceil(2.0 * ta / sqrt(8.0 * GAP_ARC_TOL / ra))))
		for j in range(1, nt):
			out.append(_pt(ra, c - ta + 2.0 * ta * float(j) / nt))
		# left side from the tip down to the root
		for i in range(L.size() - 1, -1, -1):
			out.append(L[i].rotated(c))
		# the root arc to the next tooth's right root point
		var a_from := c + th_root
		var a_to := c + step - th_root
		var ng := maxi(1, int(ceil((a_to - a_from) / sqrt(8.0 * GAP_ARC_TOL / rf))))
		for j in range(1, ng):
			out.append(_pt(rf, a_from + (a_to - a_from) * float(j) / ng))
	return out


## one tooth (centre +x) as a closed polygon whose foot sinks into the root disc (to sink * rf): for the pattern recipe (disc + ONE tooth + circular pattern)
static func tooth_poly(m: float, z: int, pa_deg := 20.0, x := 0.0, sink := 0.9) -> PackedVector2Array:
	var g := geom(m, z, pa_deg, x)
	var side := _left_side(g, 0.0)
	var L: PackedVector2Array = side[0]
	var pts := PackedVector2Array()
	var rs: float = sink * g["rf"]
	pts.append(_pt(rs, -(side[1] as float)))
	for i in L.size():
		pts.append(Vector2(L[i].x, -L[i].y))
	var ra: float = g["ra"]
	var ta := theta(g, ra)
	for j in range(1, 4):
		pts.append(_pt(ra, -ta + 2.0 * ta * float(j) / 4.0))
	for i in range(L.size() - 1, -1, -1):
		pts.append(L[i])
	pts.append(_pt(rs, side[1] as float))
	return pts


## the sketch entities of a gear centred at c (mm) turned by rot_deg: closed line loop, tagged "gear"; bore_mm > 0 adds a concentric hole circle
static func ents(m: float, z: int, pa_deg: float, x: float, rho: float, c := Vector2.ZERO, rot_deg := 0.0, bore_mm := 0.0) -> Array:
	var ol := outline(m, z, pa_deg, x, rho)
	var out := []
	if ol.is_empty():
		return out
	var rr := deg_to_rad(rot_deg)
	var n := ol.size()
	for i in n:
		var a := ol[i].rotated(rr) + c
		var b := ol[(i + 1) % n].rotated(rr) + c
		var e := {"k": "line", "a": [a.x, a.y], "b": [b.x, b.y], "shape": "gear"}
		if i == 0:
			e["gear"] = {"m": m, "z": z, "pa": pa_deg, "x": x, "rho": rho, "c": [c.x, c.y], "rot": rot_deg, "bore": bore_mm}
		out.append(e)
	if bore_mm > 0.0:
		out.append({"k": "circle", "c": [c.x, c.y], "r": bore_mm * 0.5, "shape": "gear"})
	return out


## C70: a wheel built the CH2 way (root disc, ONE tooth, circular pattern of the tooth, join, bore): the recipe whose replay was slow
static func wheel_feats(m: float, z: int, pa_deg := 20.0, x := 0.0, th := 5.0, bore := 4.0) -> Array:
	var g := geom(m, z, pa_deg, x)
	var fs := []
	var ln := []
	var tp := tooth_poly(m, z, pa_deg, x)
	for i in tp.size():
		ln.append({"k": "line", "a": Part.arr2(tp[i]), "b": Part.arr2(tp[(i + 1) % tp.size()])})
	PartTemplates._ex(fs, PartTemplates._sk(fs, "front", [{"k": "circle", "c": [0.0, 0.0], "r": g["rf"] - 0.002}]), "extrude", th, "new")
	PartTemplates._ex(fs, PartTemplates._sk(fs, "front", ln), "extrude", th, "new")
	fs.append({"t": "pattern", "id": "f%d" % (fs.size() + 1), "name": "Pattern1", "body": 1, "kind": "circular", "count": z, "axis": "z", "deg": 360.0, "op": "join"})
	fs.append({"t": "combine", "id": "f%d" % (fs.size() + 1), "name": "Combine1", "target": 0, "tools": [1], "op": "join", "keep": false})
	if bore > 0.0:
		PartTemplates._ex(fs, PartTemplates._sk(fs, "front", [{"k": "circle", "c": [0.0, 0.0], "r": bore * 0.5}]), "extrude", th + 2.0, "cut")
	return fs
