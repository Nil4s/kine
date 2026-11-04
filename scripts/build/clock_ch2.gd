class_name ClockCH2
extends RefCounted
## CH2 THE REGULATOR CLOCK (model, no scene): a seconds-beating longcase movement from docs/CH2_REFERENCE.md.
##   TEETH     involute_outline(): real involute spur teeth (module, pressure angle, addendum, dedendum, tooth thinning for backlash)
##   TRAIN     shafts + gears + mesh edges; set ONE shaft's angle and every other shaft follows by tooth ratio (the gear-train driver)
##   ESCAPE    a 30-tooth escape wheel and an anchor with two pallet blades: the wheel drops only until a tooth meets a blade
##             (contact-driven: wheel_drop()), the anchor swings with the pendulum
##   PENDULUM  a 994 mm simple pendulum integrated with RK4; its period is measured from the zero crossings
##   CLEAR     pair_overlaps(): the overlap area of flat parts, C++ (KineClockNative) or GDScript (same result, the fallback)
## Units: mm and radians. x right, y up, z towards the viewer; a clockwise hand turns by a NEGATIVE angle.

const G := 9806.65            # mm/s2
const L_PEND := 994.0         # mm, pivot to the bob's centre
const AMP := 0.0436332313     # 2.5 deg
const ESC_TEETH := 30
const ESC_R := 40.0
const ESC_ROOT := 33.0
const PA := 30.0              # pressure angle, deg (8-leaf pinions need it: 20 deg undercuts below 17 teeth)
const LASH_FRAC := 0.015      # each tooth is thinned by this x module on the pitch circle: lash = 2 x 0.015 = 3 % of the module
const DOOR := "res://scripts/build/clock_native_door.gd"
const SHAFTS := {   # name: [x, y] mm
	"C": [0.0, 0.0], "T": [0.0, 36.0], "E": [0.0, 70.0], "M": [24.0, 0.0], "H": [0.0, 0.0]}
# id, shaft, teeth, module, z0, thickness
const GEARS := [
	["C64", "C", 64, 1.0, 6.0, 3.0], ["T8", "T", 8, 1.0, 6.0, 3.0],
	["T60", "T", 60, 1.0, 12.0, 3.0], ["E8", "E", 8, 1.0, 12.0, 3.0],
	["CAN12", "C", 12, 1.0, 32.0, 3.0], ["M36", "M", 36, 1.0, 32.0, 3.0],
	["M10", "M", 10, 0.96, 36.0, 3.0], ["H40", "H", 40, 0.96, 36.0, 3.0]]
const EDGES := [["C64", "T8"], ["T60", "E8"], ["CAN12", "M36"], ["M10", "H40"]]
const ESC_Z0 := 18.0
const ESC_TH := 3.0

static var _cache := {}
static var _force_gd := false
static var _door = null
var shaft_ang := {}           # shaft name -> angle rad
var base := {}                # shaft angles at the start (set by capture_base)


func capture_base(wheel0: float) -> void:
	drive("E", wheel0)
	base = shaft_ang.duplicate()


func start_angle(shaft: String) -> float:
	return base.get(shaft, 0.0)


static func ref() -> Dictionary:
	return {"train": [[64, 8], [60, 8]], "esc_teeth": ESC_TEETH, "motion": [[12, 36], [10, 40]], "pendulum_mm": L_PEND}


static func inv(a: float) -> float:
	return tan(a) - a


## the closed outline (CCW, mm, tooth 0 centred on +x) of an involute spur gear of n teeth
static func involute_outline(n: int, m: float, pa_deg := PA, add := 0.8, ded := 1.1, lash := LASH_FRAC) -> PackedVector2Array:
	var key := "%d_%s_%s_%s_%s_%s" % [n, m, pa_deg, add, ded, lash]
	if _cache.has(key):
		return _cache[key]
	var rp := m * n * 0.5
	var ap := deg_to_rad(pa_deg)
	var rb := rp * cos(ap)
	var ra := rp + add * m
	var rf := rp - ded * m
	var ht := (PI * m * 0.5 - lash * m) / (2.0 * rp)    # half tooth angle at the pitch circle
	var r0 := maxf(rb, rf)
	var pts := PackedVector2Array()
	var k_steps := 7
	var rs: Array = []
	for i in k_steps + 1:
		rs.append(r0 + (ra - r0) * float(i) / k_steps)
	var hs: Array = []
	for r in rs:
		hs.append(ht + inv(ap) - inv(acos(minf(rb / r, 1.0))))
	for k in n:
		var c := TAU * k / n
		if rf < rb:
			pts.append(Vector2.from_angle(c - hs[0]) * rf)
		for i in k_steps + 1:
			pts.append(Vector2.from_angle(c - hs[i]) * rs[i])
		pts.append(Vector2.from_angle(c) * ra)
		for i in range(k_steps, -1, -1):
			pts.append(Vector2.from_angle(c + hs[i]) * rs[i])
		if rf < rb:
			pts.append(Vector2.from_angle(c + hs[0]) * rf)
		var cur: float = c + hs[0]
		var nx: float = c + TAU / n - hs[0]
		for i in range(1, 3):
			pts.append(Vector2.from_angle(cur + (nx - cur) * i / 3.0) * rf)
	_cache[key] = pts
	return pts


## the escape wheel: sawtooth teeth leaning back. The leading face (the one a pallet meets) runs from the tip (R, c) to a root 0.16 pitch BEHIND it, a 9 deg
## lean: the tip is the foremost point of the tooth, so a pallet's arc face (about the anchor pivot) touches the tip alone and never the face behind it.
static func escape_outline() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var p := TAU / ESC_TEETH
	for k in ESC_TEETH:
		var c := p * k
		pts.append(Vector2.from_angle(c + 0.16 * p) * ESC_ROOT)
		pts.append(Vector2.from_angle(c) * ESC_R)
		pts.append(Vector2.from_angle(c + 0.55 * p) * (ESC_ROOT + 0.3))
	return pts


# ---------------------------------------------------------------- the train driver

static func gear(id: String) -> Array:
	for g in GEARS:
		if g[0] == id:
			return g
	return []


static func pos_of(shaft: String) -> Vector2:
	var a: Array = SHAFTS[shaft]
	return Vector2(a[0], a[1])


## driven angle = x - y x driver angle, with the mesh phase chosen so a tooth of A faces a gap of B
static func edge_consts(ea: String, eb: String) -> Vector2:
	var ga := gear(ea)
	var gb := gear(eb)
	var d := pos_of(gb[1]) - pos_of(ga[1])
	var u := d.angle()
	var na: float = ga[2]
	var nb: float = gb[2]
	var r := na / nb
	return Vector2(u + PI - PI / nb + u * r, r)


## every shaft's angle when shaft `known` stands at `ang` (over the mesh edges, either direction)
func drive(known: String, ang: float) -> void:
	shaft_ang = {known: ang}
	var open := [known]
	while not open.is_empty():
		var s: String = open.pop_front()
		for e in EDGES:
			var sa: String = gear(e[0])[1]
			var sb: String = gear(e[1])[1]
			var k := edge_consts(e[0], e[1])
			if sa == s and not shaft_ang.has(sb):
				shaft_ang[sb] = k.x - k.y * shaft_ang[sa]
				open.append(sb)
			elif sb == s and not shaft_ang.has(sa):
				shaft_ang[sa] = (k.x - shaft_ang[sb]) / k.y
				open.append(sa)


# ---------------------------------------------------------------- escapement

## the anchor: pivot at (0, D) above the wheel centre, D = R x sqrt(2), so the lines pivot-pallet are tangent to the wheel (the pallets span 90 deg = 7.5
## teeth). Each pallet is a sector of a ring about the PIVOT whose face toward the wheel is an arc of radius rho about the pivot (dead face): a tooth
## resting on it is never pushed into when the anchor swings, and it drops off the sector's end when the anchor swings back. Offsets are polar angles
## about the pivot (radians, from the pivot-to-pallet direction): the tooth tip sits at offset -alpha in the anchor's frame.
static var dims := {"D": ESC_R * sqrt(2.0), "rho": 40.0, "thick": 6.0,
	"l_lo": -0.0959931, "l_hi": -0.0087266, "r_lo": -0.0087266, "r_hi": 0.0959931, "k": 1.6}   # found by tools/ch2_escape_search.gd: 6 deg per beat, 0 overlap


static func anchor_dims() -> Dictionary:
	return dims


static func _sector(r_in: float, r_out: float, a0: float, a1: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := 24
	for i in n + 1:
		pts.append(Vector2.from_angle(a0 + (a1 - a0) * i / n) * r_out)
	for i in range(n, -1, -1):
		pts.append(Vector2.from_angle(a0 + (a1 - a0) * i / n) * r_in)
	return pts


## the two pallets in the ANCHOR frame (pivot at the origin; the wheel centre is at (0, -D)): [entry (left, outside), exit (right, inside)]
static var _blade_cache := {}


static func blade_polys(grown := false) -> Array:
	var key := "%s_%s" % [grown, str(dims)]
	if _blade_cache.has(key):
		return _blade_cache[key]
	var res := _blade_polys(grown)
	_blade_cache[key] = res
	return res


static func _blade_polys(grown: bool) -> Array:
	var d := anchor_dims()
	var rho: float = d["rho"]
	var th: float = d["thick"]
	var m := 0.002 if grown else 0.0   # the stop test sees pallets 2 um bigger than the drawn ones, so a stopped tooth sits clear of the real faces
	var dl := deg_to_rad(-135.0)
	var dr := deg_to_rad(-45.0)
	var left := _sector(rho - th, rho - 0.01 + m, dl + float(d["l_lo"]), dl + float(d["l_hi"]))
	var right := _sector(rho + 0.01 - m, rho + th, dr + float(d["r_lo"]), dr + float(d["r_hi"]))
	if Geometry2D.is_polygon_clockwise(left):
		left.reverse()
	if Geometry2D.is_polygon_clockwise(right):
		right.reverse()
	return [left, right]


## wheel at the origin with angle theta; the anchor pivots about (0, D) at angle alpha
func contact_set(theta: float, alpha: float, grown := false) -> Dictionary:
	var polys: Array = [escape_outline()]
	var pose := PackedFloat64Array([0.0, 0.0, theta])
	var D: float = anchor_dims()["D"]
	for b in blade_polys(grown):
		polys.append(b)
		pose.append_array(PackedFloat64Array([0.0, D, alpha]))
	return {"polys": polys, "pose": pose, "pairs": PackedInt32Array([0, 1, 0, 2])}


func esc_overlap(theta: float, alpha: float, grown := false) -> float:
	var c := contact_set(theta, alpha, grown)
	var r := pair_overlaps(c["polys"], c["pose"], c["pairs"])
	return r[0] + r[1]


## contact-driven drop: the wheel turns clockwise (theta falls) by at most max_step, stopping where a tooth meets a blade
func wheel_drop(theta: float, alpha: float, max_step: float) -> float:
	# a pallet face that has moved into a tooth pushes it on (impulse): the first clear angle within 0.1 deg clockwise, found by a scan, not a bisection
	if esc_overlap(theta, alpha, true) > 1e-9:
		for i in range(1, 101):
			if esc_overlap(theta - 0.0000175 * i, alpha, true) <= 1e-9:
				theta -= 0.0000175 * i
				break
	if esc_overlap(theta - max_step, alpha, true) <= 1e-9:
		return theta - max_step
	if esc_overlap(theta - 0.00002, alpha, true) > 1e-9:
		return theta   # blocked at once (the common case: the wheel rests on a pallet)
	var lo := 0.0
	var hi := max_step
	for i in 14:
		var mid := (lo + hi) * 0.5
		if esc_overlap(theta - mid, alpha, true) <= 1e-9:
			lo = mid
		else:
			hi = mid
	return theta - lo


# ---------------------------------------------------------------- pendulum

## RK4 of theta'' = -(g/L) sin theta from the amplitude at rest. Returns {"cross": zero crossing times, "period": s}
static func pendulum_run(secs: float, dt := 0.001, length := L_PEND, amp := AMP) -> Dictionary:
	var th := amp
	var om := 0.0
	var t := 0.0
	var cross := []
	var w2 := G / length
	while t < secs:
		var k1t := om
		var k1o := -w2 * sin(th)
		var k2t := om + 0.5 * dt * k1o
		var k2o := -w2 * sin(th + 0.5 * dt * k1t)
		var k3t := om + 0.5 * dt * k2o
		var k3o := -w2 * sin(th + 0.5 * dt * k2t)
		var k4t := om + dt * k3o
		var k4o := -w2 * sin(th + dt * k3t)
		var nth := th + dt / 6.0 * (k1t + 2.0 * k2t + 2.0 * k3t + k4t)
		var nom := om + dt / 6.0 * (k1o + 2.0 * k2o + 2.0 * k3o + k4o)
		if (th > 0.0) != (nth > 0.0):
			cross.append(t + dt * th / (th - nth))
		th = nth
		om = nom
		t += dt
	var per := 0.0
	if cross.size() >= 3:
		per = (cross[cross.size() - 1] - cross[0]) / float(cross.size() - 1) * 2.0
	return {"cross": cross, "period": per}


# ---------------------------------------------------------------- clearance

static func area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


static func _cross(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)


## area of (convex ccw triangle s) clipped by (convex ccw triangle c): Sutherland-Hodgman, the same arithmetic as KineClockNative
static func _clip_area(s: Array, c: Array) -> float:
	var poly: Array = s.duplicate()
	for e in 3:
		if poly.is_empty():
			return 0.0
		var a: Vector2 = c[e]
		var b: Vector2 = c[(e + 1) % 3]
		var inp: Array = poly
		poly = []
		for i in inp.size():
			var p: Vector2 = inp[i]
			var q: Vector2 = inp[(i + 1) % inp.size()]
			var dp := _cross(a, b, p)
			var dq := _cross(a, b, q)
			if dp >= 0.0:
				poly.append(p)
			if (dp > 0.0 and dq < 0.0) or (dp < 0.0 and dq > 0.0):
				var t := dp / (dp - dq)
				poly.append(p + (q - p) * t)
	var ar := 0.0
	for i in poly.size():
		var p2: Vector2 = poly[i]
		var q2: Vector2 = poly[(i + 1) % poly.size()]
		ar += p2.x * q2.y - q2.x * p2.y
	return absf(ar) * 0.5


static func _tris(poly: PackedVector2Array, x: float, y: float, ang: float) -> Array:
	var pts := Transform2D(ang, Vector2(x, y)) * poly
	var idx := Geometry2D.triangulate_polygon(pts)
	var out: Array = []
	for i in range(0, idx.size(), 3):
		var t: Array = [pts[idx[i]], pts[idx[i + 1]], pts[idx[i + 2]]]
		if _cross(t[0], t[1], t[2]) < 0.0:
			t = [t[0], t[2], t[1]]
		out.append([t, minf(t[0].x, minf(t[1].x, t[2].x)), maxf(t[0].x, maxf(t[1].x, t[2].x)), minf(t[0].y, minf(t[1].y, t[2].y)), maxf(t[0].y, maxf(t[1].y, t[2].y))])
	return out


## the GDScript twin of KineClockNative.pair_overlaps (same triangle-pair clip; the fallback when the DLL is missing)
static func pair_overlaps_gd(polys: Array, pose: PackedFloat64Array, pairs: PackedInt32Array) -> PackedFloat64Array:
	var res := PackedFloat64Array()
	var posed := {}
	for k in range(0, pairs.size(), 2):
		var s := 0.0
		for w in [pairs[k], pairs[k + 1]]:
			if not posed.has(w):
				posed[w] = _tris(polys[w], pose[3 * w], pose[3 * w + 1], pose[3 * w + 2])
		for ta in posed[pairs[k]]:
			for tb in posed[pairs[k + 1]]:
				if ta[2] <= tb[1] or tb[2] <= ta[1] or ta[4] <= tb[3] or tb[4] <= ta[3]:
					continue
				s += _clip_area(ta[0], tb[0])
		res.append(s)
	return res


static func has_native() -> bool:
	return (ClassDB.class_exists("KineClockNative") or NativeExt.ensure("kine_native", "KineClockNative")) and not _force_gd


## test switch: true = never use the DLL
static func force_gd(on: bool) -> void:
	_force_gd = on


static func pair_overlaps(polys: Array, pose: PackedFloat64Array, pairs: PackedInt32Array) -> PackedFloat64Array:
	if has_native():
		if _door == null:
			_door = load(DOOR)
		return _door.pair_overlaps(polys, pose, pairs)
	return pair_overlaps_gd(polys, pose, pairs)


# ---------------------------------------------------------------- the whole movement

## every flat part at a state: {"names", "polys", "pose" (x, y, angle per part, mm / rad), "z0", "z1"}; the model must have been driven to `theta`
func bodies(theta: float, alpha: float, shift := {}) -> Dictionary:
	drive("E", theta)
	var names: Array = []
	var polys: Array = []
	var pose := PackedFloat64Array()
	var z0: Array = []
	var z1: Array = []
	for g in GEARS:
		var p := pos_of(g[1]) + (shift.get(g[0], Vector2.ZERO) as Vector2)
		names.append(g[0])
		polys.append(involute_outline(g[2], g[3]))
		pose.append_array(PackedFloat64Array([p.x, p.y, shaft_ang[g[1]]]))
		z0.append(g[4])
		z1.append(g[4] + g[5])
	names.append("ESC")
	polys.append(escape_outline())
	var ep := pos_of("E")
	pose.append_array(PackedFloat64Array([ep.x, ep.y, theta]))
	z0.append(ESC_Z0)
	z1.append(ESC_Z0 + ESC_TH)
	var D: float = anchor_dims()["D"]
	var k := 0
	for b in blade_polys():
		names.append("BLADE%d" % k)
		k += 1
		polys.append(b)
		pose.append_array(PackedFloat64Array([ep.x, ep.y + D, alpha]))
		z0.append(ESC_Z0)
		z1.append(ESC_Z0 + ESC_TH)
	return {"names": names, "polys": polys, "pose": pose, "z0": z0, "z1": z1}


## the part pairs that share a z range (the only pairs that can touch)
static func z_pairs(b: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	var n: int = b["names"].size()
	for i in n:
		for j in range(i + 1, n):
			if minf(b["z1"][i], b["z1"][j]) - maxf(b["z0"][i], b["z0"][j]) > 1e-6:
				out.append(i)
				out.append(j)
	return out


## overlap VOLUME (mm3) of every z-sharing pair: area x shared thickness. Returns {"worst": mm3, "sum": mm3, "pairs": n, "who": name of the worst pair}
func clearance(theta: float, alpha: float, shift := {}) -> Dictionary:
	var b := bodies(theta, alpha, shift)
	var prs := z_pairs(b)
	var ar := pair_overlaps(b["polys"], b["pose"], prs)
	var worst := 0.0
	var sum := 0.0
	var who := ""
	for k in ar.size():
		var i := prs[2 * k]
		var j := prs[2 * k + 1]
		var v: float = ar[k] * (minf(b["z1"][i], b["z1"][j]) - maxf(b["z0"][i], b["z0"][j]))
		sum += v
		if v > worst:
			worst = v
			who = "%s-%s" % [b["names"][i], b["names"][j]]
	return {"worst": worst, "sum": sum, "pairs": ar.size(), "who": who}


## circumferential backlash (mm) of a mesh edge at the driven gear's pitch circle: turn the driven gear both ways from its meshed angle until its
## outline meets the driver's, and take the free arc.
func lash(edge: Array, lash_frac := LASH_FRAC) -> float:
	var ga := gear(edge[0])
	var gb := gear(edge[1])
	var pa := involute_outline(ga[2], ga[3], PA, 0.8, 1.1, lash_frac)
	var pb := involute_outline(gb[2], gb[3], PA, 0.8, 1.1, lash_frac)
	var da := pos_of(ga[1])
	var db := pos_of(gb[1])
	drive(ga[1], 0.3)
	var aa: float = shaft_ang[ga[1]]
	var ab: float = shaft_ang[gb[1]]
	var half: float = PI / float(gb[2])
	var arcs := []
	for sgn in [1.0, -1.0]:
		var lo := 0.0
		var hi: float = half
		for i in 30:
			var mid := (lo + hi) * 0.5
			var ar := pair_overlaps([pa, pb], PackedFloat64Array([da.x, da.y, aa, db.x, db.y, ab + sgn * mid]), PackedInt32Array([0, 1]))
			if ar[0] <= 1e-9:
				lo = mid
			else:
				hi = mid
		arcs.append(lo)
	return (arcs[0] + arcs[1]) * float(gb[2]) * float(gb[3]) * 0.5


## the run: pendulum (RK4) swings the anchor; the escape wheel drops against the blades. Returns per-step arrays at dt:
## {"phi", "theta", "ovl" (escapement overlap area per step), "dt"}
func simulate(secs: float, dt := 1.0 / 240.0, amp := AMP, max_drop := 0.035) -> Dictionary:
	var th := 0.0
	var found := false
	var k: float = dims["k"]
	for i in 480:
		var t := -TAU / ESC_TEETH * i / 480.0
		if esc_overlap(t, amp * k) < 1e-9:
			th = t
			found = true
			break
	var phis := PackedFloat64Array()
	var ths := PackedFloat64Array()
	var ovl := PackedFloat64Array()
	var ph := amp
	var om := 0.0
	var w2 := G / L_PEND
	var n := int(secs / dt)
	for i in n:
		var k1t := om
		var k1o := -w2 * sin(ph)
		var k2t := om + 0.5 * dt * k1o
		var k2o := -w2 * sin(ph + 0.5 * dt * k1t)
		var k3t := om + 0.5 * dt * k2o
		var k3o := -w2 * sin(ph + 0.5 * dt * k2t)
		var k4t := om + dt * k3o
		var k4o := -w2 * sin(ph + dt * k3t)
		ph += dt / 6.0 * (k1t + 2.0 * k2t + 2.0 * k3t + k4t)
		om += dt / 6.0 * (k1o + 2.0 * k2o + 2.0 * k3o + k4o)
		th = wheel_drop(th, ph * k, max_drop)
		ovl.append(esc_overlap(th, ph * k))
		phis.append(ph)
		ths.append(th)
	return {"phi": phis, "theta": ths, "ovl": ovl, "dt": dt, "found": found}
