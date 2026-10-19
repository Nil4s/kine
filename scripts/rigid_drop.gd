## rigid_drop.gd - RIGID PROP PHYSICS (ROADMAP 85). A rod-like held prop (a sword: a capsule of length L and radius R)
## let go at a card falls as a RIGID BODY. At the let-go it keeps the hand's linear and angular velocity, falls under
## g = 9.81 m/s^2, collides with the floor (y = 0) with restitution E and Coulomb friction MU, and comes to rest lying on
## it. Simulated on a FIXED 240 Hz step (DT = 1/240 s; semi-implicit Euler; sequential impulses for the two end contacts),
## so the same inputs give the same numbers on every run. The result is BAKED: a pose per step (centre + quaternion)
## that Scene keeps on the drop card ("drop_rig") and plays back by interpolating those steps, so scrubbing forwards and
## backwards and export read the same bytes.
## MATERIAL (cited; neither value measured by us for a blade):
##   MU = 0.47  kinetic friction, concrete on steel: ASCE J. Struct. Eng. 1990 (concrete against steel, average over
##              normal stress) 0.47, https://ascelibrary.com/doi/10.1061/(ASCE)0899-1561(1990)2:1(46). Rabbat & Russell
##              1985 give 0.57 dry, 0.65 wet for static friction of steel on concrete, the upper end of the range.
##   E = 0.5    restitution, steel on concrete: a materials guide (samaterials.com) gives 0.50-0.60 for a steel ball on
##              concrete; no measured value for a sword on concrete was found. UNVERIFIED for a blade.
## THE SWORD BODY (Props.KINDS "sword"): L = 0.90 m between the two end centres, R = 0.015 m, M = 1.1 kg (a steel sword
## of about 1 kg, a sword-shaped rod: inertia of a thin rod M L^2/12 about the axes across it, M R^2/2 about its own axis).
## Contacts: each END is a sphere of radius R on the floor; the rod's lowest surface point is min(end y) - R, so a rod lying
## flat has both ends touching at height R. REST_V: an impact slower than this does not bounce (a bounce under 0.5 m/s
## would be a rebound under 1.3 cm: it settles). A rod at rest for SETTLE_T with speed under SETTLE_V is at rest.
class_name RigidDrop
extends RefCounted

const G := 9.81
const DT := 1.0 / 240.0     # the fixed step (s)
const E := 0.5              # restitution, steel on concrete (see above)
const MU := 0.47            # kinetic friction, concrete on steel (see above)
const REST_V := 0.5         # m/s: below this an impact does not bounce
const SETTLE_V := 0.001     # m/s: at rest when the speed (and the spin's end speed) is under this
const SETTLE_T := 0.25      # s: ...for this long
const MAX_T := 10.0         # s: the bake ends here at the latest
const ITER := 24            # sequential impulse sweeps per step


## the sword's body: L, R, m (kg), I (kg m^2, body frame: the rod lies along local X)
static func sword_body() -> Dictionary:
	var L := 0.9
	var R := 0.015
	var m := 1.1
	return {"L": L, "R": R, "m": m, "I": Vector3(m * R * R / 2.0, m * L * L / 12.0, m * L * L / 12.0)}


## the angular velocity (world, rad/s) that turns basis b0 into b1 in dt seconds
static func spin(b0: Basis, b1: Basis, dt: float) -> Vector3:
	if dt <= 0.0:
		return Vector3.ZERO
	var q0 := b0.orthonormalized().get_rotation_quaternion()
	var q1 := b1.orthonormalized().get_rotation_quaternion()
	var dq := q1 * q0.inverse()
	if dq.w < 0.0:
		dq = Quaternion(-dq.x, -dq.y, -dq.z, -dq.w)
	var ang := dq.get_angle()
	if absf(ang) < 1e-12:
		return Vector3.ZERO
	return dq.get_axis() * ang / dt


## the drop: x0 the centre (the prop origin), q0 the orientation, v0 and w0 the velocities at the let-go, body from
## sword_body(). Returns {"poses": PackedFloat64Array (7 per step: x y z qx qy qz qw; step k is at k DT), "steps": n,
## "t_rest": s (when it came to rest; the poses hold after it), "hits": [[t, vn_in]...] (contacts, t = the step they
## were found), "v0": Vector3, "rest_xf": Transform3D}
static func simulate(x0: Vector3, q0: Quaternion, v0: Vector3, w0: Vector3, body: Dictionary, e := E, mu := MU) -> Dictionary:
	var L: float = body["L"]
	var R: float = body["R"]
	var m: float = body["m"]
	var I: Vector3 = body["I"]
	var x := x0
	var q := q0.normalized()
	var v := v0
	var w := w0
	var poses := PackedFloat64Array()
	var hits := []
	var still := 0.0
	var t_rest := -1.0
	_put(poses, x, q)
	var k := 0
	while k * DT < MAX_T:
		var t := float(k) * DT
		var basis := Basis(q)
		var ax := basis.x * (L * 0.5)
		var ends := [x + ax, x - ax]
		# 1. gravity
		v.y -= G * DT
		# 2. the end contacts at this step's start
		var Dinv := Basis(Vector3(1.0 / I.x, 0, 0), Vector3(0, 1.0 / I.y, 0), Vector3(0, 0, 1.0 / I.z))
		var Iw := basis * Dinv * basis.transposed()
		var cons := []
		var vn_in := 0.0
		for en in ends:
			var en_y: float = en.y
			if en_y - R <= 0.0:
				var r: Vector3 = (en - Vector3.UP * R) - x
				var vn := (v + w.cross(r)).y
				vn_in = minf(vn_in, vn)
				var kt1 := 1.0 / m + Vector3.RIGHT.dot((Iw * r.cross(Vector3.RIGHT)).cross(r))
				var kt2 := 1.0 / m + Vector3.BACK.dot((Iw * r.cross(Vector3.BACK)).cross(r))
				var target := (-e * vn) if vn < -REST_V else 0.0
				cons.append({"r": r, "vn": vn, "target": target, "kt1": kt1, "kt2": kt2, "acc": 0.0, "t1": 0.0, "t2": 0.0})
		if not cons.is_empty():
			hits.append([t, vn_in])
			# 3a. the normal impulses of ALL contacts at once (a linear complementarity problem: lam >= 0, the contact speed
			# after the impulse >= its target, and lam is zero where that speed is above it). Solved together, not one
			# end after the other: a rod dropped flat stays flat (sequential sweeps tipped it on its first bounce)
			var n := cons.size()
			var K := []
			var b := []
			for i in n:
				var ri: Vector3 = cons[i]["r"]
				var row := []
				for j in n:
					var rj: Vector3 = cons[j]["r"]
					row.append(1.0 / m + Vector3.UP.dot((Iw * rj.cross(Vector3.UP)).cross(ri)))
				K.append(row)
				b.append(float(cons[i]["target"]) - float(cons[i]["vn"]))
			var lam := _normal_impulses(K, b)
			for i in n:
				var c: Dictionary = cons[i]
				c["acc"] = float(lam[i])
				var P := Vector3.UP * float(lam[i])
				v += P / m
				w += Iw * (c["r"] as Vector3).cross(P)
			# 3b. friction: each end's slip, sweep by sweep, capped at MU times its normal impulse
			for it in ITER:
				for c in cons:
					var r: Vector3 = c["r"]
					var lim := mu * float(c["acc"])
					for j in 2:
						var tdir := Vector3.RIGHT if j == 0 else Vector3.BACK
						var kk: float = float(c["kt1"]) if j == 0 else float(c["kt2"])
						var key := "t1" if j == 0 else "t2"
						var vt := (v + w.cross(r)).dot(tdir)
						var lt := -vt / kk
						var tn := clampf(float(c[key]) + lt, -lim, lim)
						lt = tn - float(c[key])
						c[key] = tn
						var Pt := tdir * lt
						v += Pt / m
						w += Iw * r.cross(Pt)
		# 4. motion
		x += v * DT
		var ang := w.length() * DT
		if ang > 0.0:
			q = (Quaternion(w.normalized(), ang) * q).normalized()
		# (no position projection: the end contacts' impulses already leave a resting end at zero speed. A projection that
		# lifted the centre by the deepest end's penetration rocked a tilted rod: it did not settle, 0.1 rad of rocking)
		k += 1
		_put(poses, x, q)
		# 6. at rest: on the floor, slow for SETTLE_T
		var spin_end := w.length() * L * 0.5
		if not cons.is_empty() and v.length() < SETTLE_V and spin_end < SETTLE_V:
			still += DT
		else:
			still = 0.0
		if still >= SETTLE_T:
			t_rest = float(k) * DT
			break
	var basis_end := Basis(q)
	return {"poses": poses, "steps": poses.size() / 7, "t_rest": t_rest, "hits": hits, "v0": v0,
		"rest_xf": Transform3D(basis_end, x)}


## the normal impulses of up to two contacts: K (n x n) the contact speed per unit impulse, b the speed to add (target
## minus the speed now). lam >= 0 with K lam >= b and lam . (K lam - b) = 0. Tried as: both in contact, only one of them;
## none needs b <= 0. Exact for two ends (a 2 x 2 solve), so symmetric input gives symmetric output
static func _normal_impulses(K: Array, b: Array) -> Array:
	var n := b.size()
	if n == 1:
		return [maxf(float(b[0]) / float(K[0][0]), 0.0)]
	var k00: float = K[0][0]
	var k01: float = K[0][1]
	var k10: float = K[1][0]
	var k11: float = K[1][1]
	var b0: float = b[0]
	var b1: float = b[1]
	var det := k00 * k11 - k01 * k10
	if absf(det) > 1e-12:
		var l0 := (b0 * k11 - k01 * b1) / det
		var l1 := (k00 * b1 - k10 * b0) / det
		if l0 >= 0.0 and l1 >= 0.0:
			return [l0, l1]
	var a0 := b0 / k00
	if a0 >= 0.0 and k10 * a0 - b1 >= 0.0:
		return [a0, 0.0]
	var a1 := b1 / k11
	if a1 >= 0.0 and k01 * a1 - b0 >= 0.0:
		return [0.0, a1]
	return [0.0, 0.0]


static func _put(poses: PackedFloat64Array, x: Vector3, q: Quaternion) -> void:
	poses.append_array([x.x, x.y, x.z, q.x, q.y, q.z, q.w])


## the pose at time t (s) from the let-go: the steps either side of t interpolated (lerp the centre, slerp the turn).
## Pure: the same t gives the same numbers whatever was asked before. Past the last step it holds
static func pose_at(poses: PackedFloat64Array, t: float) -> Transform3D:
	var n := poses.size() / 7
	var f := t / DT
	if f <= 0.0:
		return _xf(poses, 0, 0, 0.0)
	var k := int(floor(f))
	if k >= n - 1:
		return _xf(poses, n - 1, n - 1, 0.0)
	return _xf(poses, k, k + 1, f - float(k))


static func _xf(poses: PackedFloat64Array, a: int, b: int, s: float) -> Transform3D:
	var pa := Vector3(poses[7 * a], poses[7 * a + 1], poses[7 * a + 2])
	var pb := Vector3(poses[7 * b], poses[7 * b + 1], poses[7 * b + 2])
	var qa := Quaternion(poses[7 * a + 3], poses[7 * a + 4], poses[7 * a + 5], poses[7 * a + 6])
	var qb := Quaternion(poses[7 * b + 3], poses[7 * b + 4], poses[7 * b + 5], poses[7 * b + 6])
	return Transform3D(Basis(qa.slerp(qb, s).normalized()), pa.lerp(pb, s))


## the poses as a JSON-safe array, rounded to 1 micrometre (the file holds these; playback reads them back)
static func to_array(poses: PackedFloat64Array) -> Array:
	var out := []
	for v in poses:
		out.append(snappedf(v, 0.000001))
	return out


static func from_array(a: Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for v in a:
		out.append(float(v))
	return out


## a prop kind that drops as a rigid body (Props.KINDS "rod")
static func rod(p: Dictionary) -> bool:
	return Props.has_kind(String(p["kind"])) and bool(Props.kind_of(String(p["kind"])).get("rod", false))


## the last pose of a bake (the rest pose once it has come to rest)
static func last_xf(poses: PackedFloat64Array) -> Transform3D:
	var n := poses.size() / 7
	return _xf(poses, n - 1, n - 1, 0.0)


## a bake mirrored across the x = 0 plane (the scene's mirror): x negated, and the turn (w, x, -y, -z) (a reflection
## turns the other way about Y and Z; the spin is an axial vector, so its y and z flip too). Twice = the original
static func mirror_rig(st: Dictionary) -> Dictionary:
	var out := st.duplicate(true)
	var a: Array = st["poses"]
	var m := []
	for i in a.size():
		var k := i % 7
		var v := float(a[i])
		if k == 0 or k == 4 or k == 5:
			v = -v
		m.append(v)
	out["poses"] = m
	var inn: Array = st.get("in", [])
	if inn.size() == 13:
		# the velocity is a vector (x negated); the spin is an axial vector (y and z negated)
		out["in"] = [-float(inn[0]), inn[1], inn[2], inn[3], -float(inn[4]), -float(inn[5]), inn[6], -float(inn[7]), inn[8], inn[9], inn[10], -float(inn[11]), -float(inn[12])]
	return out


## a prop's transform (its origin is on the floor under its footprint, the Props convention) from the sword's centre of
## mass transform: the origin is R below the centre along the prop's own up axis (flat on the floor: y = 0)
static func prop_xf(com: Transform3D, r: float) -> Transform3D:
	return Transform3D(com.basis, com.origin - com.basis.orthonormalized().y * r)


## the inverse: the centre of mass of a prop whose origin is at prop_xf's origin
static func com_xf(prop: Transform3D, r: float) -> Transform3D:
	return Transform3D(prop.basis, prop.origin + prop.basis.orthonormalized().y * r)
