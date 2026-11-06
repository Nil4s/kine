class_name SoftBody
extends RefCounted
## SOFT-BODY FLESH (L17, GAP_AUDIT_1106 #9): an XPBD tetrahedral volume under the skinned body, opt-in (Scene.soft; default off).
##
## WHY TETS. The bars (tests/soft_test.gd) quote Young's modulus and Poisson's ratio and compare with linear elasticity: a sag, a
## ring-down frequency sqrt(k/m), a volume kept at 30 % compression. A spring lattice has no Poisson ratio and cannot keep volume;
## a tet has Lame's mu and lambda, so E and nu go in and the physics comes out. XPBD (Macklin, Mueller, Chentanez 2016) with
## COROTATED linear elasticity as two constraints that are BOTH zero at rest: deviatoric C = |F - R| (R the polar rotation of F,
## per tet, stiffness 2 mu so the energy is mu |F - R|^2) and hydrostatic C = mean det F - 1 over the six tets of a cell (stiffness
## lambda; the cell mean is the cure for volumetric locking). I tried the Neo-Hookean pair first (C = |F| against det F - gamma):
## those two disagree at rest, and solved one after the other they pulled a free block to a point (measured 11-06); the coupled
## solve of that paper was not worth it when the corotated pair needs none. Written from the equations; no library code is copied.
##
## WOBBLING MASS. A region is a slab of tets lying on a host body part's skin side. Its inner layer is DRIVEN (it rides the host bone
## with the skinned body, pinned), the other layers are free flesh. What the region reports is the free flesh's displacement from
## the place the bone carries it (the jiggle), with the standing sag taken out, so it can be added to the skin.
##
## Two implementations of one step: the C++ one (native/src/kine_soft_native.cpp, KineSoftNative) and _step_gd below. Same
## arithmetic in the same order, so they agree to rounding (bar 5). KINE_NO_NATIVE=1 or SoftBody.force_gdscript forces GDScript.

static var force_gdscript := false
## the default step of a region at 60 Hz: 8 substeps of 1 iteration (small steps beat iterations; 2 iterations cost 2.7 ms for the six
## regions, 1 cost about half: tests/soft_test.gd bar 4)
const DEFAULT_ITERS := 1
static var _door = null
static var _door_tried := false

## the opt-in regions. host: the body part whose frame carries it. dir: the outward side in the REST pose (the mannequin faces +z,
## its left is +x). Sizes in metres at the 183 cm mannequin: width across, height along the part; the box runs from inner x radius (inside the
## part) out to the radius + outer (the skin; the trunk skin sits 3-4 cm outside its capsules, a limb about 1 cm).
## mat: E in Pa. Relaxed muscle reads E ~ 10-25 kPa and fat 1-10 kPa on shear-wave elastography (from memory); the thigh and the
## arm are BRACED in a landing and a braced muscle is several times stiffer (Wakeling and Nigg 2001: activation raises the
## vibration frequency), so they take 100 and 50 kPa: calibrated until the ring-down of bar 2b sits in its window, a stated knob.
## damp (1/s): zeta = damp / 2 omega, about 0.2 at 20 Hz for 45.
## L32: the arm (landing swing peaked at 84 mm with E 50 kPa, damp 45) takes the thigh's braced E 100 kPa and damp 150: peak 4 .. 30 mm window
## (tests/soft2_test.gd bar A, Blache et al. 2017 arm-marker artefact 3.9 .. 25.6 mm average, second-hand). Sweep in the L32 report.
const REGIONS := {
	"belly": {"host": "spine_01", "dir": Vector3(0, 0, 1), "t": 0.5, "width": 0.26, "height": 0.16, "outer": 0.035, "inner": 0.55,
		"E": 8.0e3, "nu": 0.45, "rho": 1000.0, "damp": 35.0, "n": Vector3i(4, 3, 2)},
	"chest": {"host": "spine_03", "dir": Vector3(0, 0, 1), "t": 0.5, "width": 0.28, "height": 0.16, "outer": 0.035, "inner": 0.62,
		"E": 1.2e4, "nu": 0.45, "rho": 1000.0, "damp": 35.0, "n": Vector3i(4, 3, 2)},
	"thigh_l": {"host": "thigh_l", "dir": Vector3(0.35, 0, 0.94), "t": 0.45, "width": 0.14, "height": 0.26, "outer": 0.012, "inner": 0.45,
		"E": 1.0e5, "nu": 0.45, "rho": 1050.0, "damp": 45.0, "n": Vector3i(3, 4, 2)},
	"thigh_r": {"host": "thigh_r", "dir": Vector3(-0.35, 0, 0.94), "t": 0.45, "width": 0.14, "height": 0.26, "outer": 0.012, "inner": 0.45,
		"E": 1.0e5, "nu": 0.45, "rho": 1050.0, "damp": 45.0, "n": Vector3i(3, 4, 2)},
	"arm_l": {"host": "upperarm_l", "dir": Vector3(0, -0.5, -0.87), "t": 0.5, "width": 0.09, "height": 0.16, "outer": 0.01, "inner": 0.5,
		"E": 1.0e5, "nu": 0.45, "rho": 1050.0, "damp": 150.0, "n": Vector3i(2, 3, 2)},
	"arm_r": {"host": "upperarm_r", "dir": Vector3(0, -0.5, -0.87), "t": 0.5, "width": 0.09, "height": 0.16, "outer": 0.01, "inner": 0.5,
		"E": 1.0e5, "nu": 0.45, "rho": 1050.0, "damp": 150.0, "n": Vector3i(2, 3, 2)},
}


## true when the step will run in C++
static func native_on() -> bool:
	return native_door() != null


static func native_door():
	if force_gdscript or OS.get_environment("KINE_NO_NATIVE") == "1":
		return null
	if not _door_tried:
		_door_tried = true
		if NativeExt.ensure("kine_native", "KineSoftNative"):
			_door = load("res://scripts/soft_native.gd")
	return _door


## Lame's parameters (mu, lambda) from E and nu
static func lame(E: float, nu: float) -> Vector2:
	return Vector2(E / (2.0 * (1.0 + nu)), E * nu / ((1.0 + nu) * (1.0 - 2.0 * nu)))


## the damping rate (1/s) that gives a damping ratio zeta at angular frequency omega
static func damp_for_zeta(zeta: float, omega: float) -> float:
	return 2.0 * zeta * omega


# ============================================================ the tet block

## A block of n cells (Kuhn: 6 tets a cell, one shared diagonal so neighbours agree), size metres, from origin (local), carried
## by xf at rest. Node (ix, iy, iz) is (iz * (ny + 1) + iy) * (nx + 1) + ix. mat: {E, nu, rho}.
static func block(n: Vector3i, size: Vector3, mat: Dictionary, origin := Vector3.ZERO, xf := Transform3D.IDENTITY) -> Dictionary:
	var E := float(mat.get("E", 2.0e4))
	var nu := float(mat.get("nu", 0.45))
	var rho := float(mat.get("rho", 1000.0))
	var nx := n.x + 1
	var ny := n.y + 1
	var np := nx * ny * (n.z + 1)
	var x := PackedFloat64Array()
	x.resize(3 * np)
	var cs := Vector3(size.x / float(n.x), size.y / float(n.y), size.z / float(n.z))
	for iz in n.z + 1:
		for iy in n.y + 1:
			for ix in n.x + 1:
				var i := (iz * ny + iy) * nx + ix
				var p := xf * (origin + Vector3(float(ix) * cs.x, float(iy) * cs.y, float(iz) * cs.z))
				x[3 * i] = p.x
				x[3 * i + 1] = p.y
				x[3 * i + 2] = p.z
	var perms := [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
	var tets := PackedInt32Array()
	for iz in n.z:
		for iy in n.y:
			for ix in n.x:
				for pm in perms:
					var c := [ix, iy, iz]
					var ids := []
					ids.append((iz * ny + iy) * nx + ix)
					for q in 2:
						c[pm[q]] += 1
						ids.append((c[2] * ny + c[1]) * nx + c[0])
					ids.append(((iz + 1) * ny + (iy + 1)) * nx + (ix + 1))
					tets.append_array(PackedInt32Array(ids))
	var T := tets.size() / 4
	var dm := PackedFloat64Array()
	dm.resize(9 * T)
	var v0 := PackedFloat64Array()
	v0.resize(T)
	var mass := PackedFloat64Array()
	mass.resize(np)
	for t in T:
		var i0 := tets[4 * t] * 3
		# Dm = [x1-x0 | x2-x0 | x3-x0] in doubles (a Basis would round to float32), its inverse by cofactors
		var m := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]   # row-major: m[3 r + c], column c = edge c
		for k in 3:
			var ik := tets[4 * t + 1 + k] * 3
			for r in 3:
				m[3 * r + k] = x[ik + r] - x[i0 + r]
		var det: float = m[0] * (m[4] * m[8] - m[5] * m[7]) - m[1] * (m[3] * m[8] - m[5] * m[6]) + m[2] * (m[3] * m[7] - m[4] * m[6])
		if det < 0.0:   # swap two corners: positive orientation
			var sw := tets[4 * t + 2]
			tets[4 * t + 2] = tets[4 * t + 3]
			tets[4 * t + 3] = sw
			for r in 3:
				var tmp: float = m[3 * r + 1]
				m[3 * r + 1] = m[3 * r + 2]
				m[3 * r + 2] = tmp
			det = -det
		var id := 1.0 / det
		dm[9 * t + 0] = (m[4] * m[8] - m[5] * m[7]) * id
		dm[9 * t + 1] = (m[2] * m[7] - m[1] * m[8]) * id
		dm[9 * t + 2] = (m[1] * m[5] - m[2] * m[4]) * id
		dm[9 * t + 3] = (m[5] * m[6] - m[3] * m[8]) * id
		dm[9 * t + 4] = (m[0] * m[8] - m[2] * m[6]) * id
		dm[9 * t + 5] = (m[2] * m[3] - m[0] * m[5]) * id
		dm[9 * t + 6] = (m[3] * m[7] - m[4] * m[6]) * id
		dm[9 * t + 7] = (m[1] * m[6] - m[0] * m[7]) * id
		dm[9 * t + 8] = (m[0] * m[4] - m[1] * m[3]) * id
		v0[t] = det / 6.0
		for k in 4:
			mass[tets[4 * t + k]] += rho * v0[t] / 4.0
	var w := PackedFloat64Array()
	w.resize(np)
	for i in np:
		w[i] = 1.0 / mass[i]
	var lm := lame(E, nu)
	var lam_c := lm.y
	var vel := PackedFloat64Array()
	vel.resize(3 * np)
	var st := {"n": np, "x": x, "v": vel, "mass": mass, "w": w, "tets": tets, "dm": dm, "v0": v0,
		"mu": lm.x, "lam": lam_c, "gamma": 1.0, "pin_idx": PackedInt32Array(), "pin_to": PackedFloat64Array(),
		"fext": PackedFloat64Array(), "mat": mat.duplicate()}
	return st


## fix these nodes (driven): inverse mass 0, held where they are
static func pin(st: Dictionary, idx: PackedInt32Array) -> void:
	var w: PackedFloat64Array = st["w"]
	var x: PackedFloat64Array = st["x"]
	var pi: PackedInt32Array = st["pin_idx"]
	var pt: PackedFloat64Array = st["pin_to"]
	for i in idx:
		w[i] = 0.0
		pi.append(i)
		pt.append(x[3 * i])
		pt.append(x[3 * i + 1])
		pt.append(x[3 * i + 2])
	st["w"] = w
	st["pin_idx"] = pi
	st["pin_to"] = pt


static func set_node_mass(st: Dictionary, i: int, m: float) -> void:
	var mass: PackedFloat64Array = st["mass"]
	var w: PackedFloat64Array = st["w"]
	mass[i] = m
	if w[i] > 0.0:
		w[i] = 1.0 / m
	st["mass"] = mass
	st["w"] = w


static func node(st: Dictionary, i: int) -> Vector3:
	var x: PackedFloat64Array = st["x"]
	return Vector3(x[3 * i], x[3 * i + 1], x[3 * i + 2])


# ============================================================ measures

## F of tet t as 9 doubles (row-major)
static func _f_of(st: Dictionary, t: int) -> PackedFloat64Array:
	var x: PackedFloat64Array = st["x"]
	var tets: PackedInt32Array = st["tets"]
	var dm: PackedFloat64Array = st["dm"]
	var i0 := tets[4 * t] * 3
	var F := PackedFloat64Array()
	F.resize(9)
	for r in 3:
		var c1 := x[tets[4 * t + 1] * 3 + r] - x[i0 + r]
		var c2 := x[tets[4 * t + 2] * 3 + r] - x[i0 + r]
		var c3 := x[tets[4 * t + 3] * 3 + r] - x[i0 + r]
		for q in 3:
			F[3 * r + q] = c1 * dm[9 * t + q] + c2 * dm[9 * t + 3 + q] + c3 * dm[9 * t + 6 + q]
	return F


static func _det3(F: PackedFloat64Array) -> float:
	return F[0] * (F[4] * F[8] - F[5] * F[7]) - F[1] * (F[3] * F[8] - F[5] * F[6]) + F[2] * (F[3] * F[7] - F[4] * F[6])


## the summed volume of the tets (signed: an inverted tet takes volume off)
static func volume(st: Dictionary) -> float:
	var v0: PackedFloat64Array = st["v0"]
	var s := 0.0
	for t in v0.size():
		s += v0[t] * _det3(_f_of(st, t))
	return s


## tets whose det F <= 0
static func inverted(st: Dictionary) -> int:
	var c := 0
	for t in (st["v0"] as PackedFloat64Array).size():
		if _det3(_f_of(st, t)) <= 0.0:
			c += 1
	return c


static func finite(st: Dictionary) -> bool:
	for a in (st["x"] as PackedFloat64Array):
		if is_nan(a) or is_inf(a):
			return false
	for a in (st["v"] as PackedFloat64Array):
		if is_nan(a) or is_inf(a):
			return false
	return true


## {ke: kinetic J, el: Neo-Hookean strain energy J (zero at rest)}
static func energy(st: Dictionary, _g := Vector3.ZERO) -> Dictionary:
	var v: PackedFloat64Array = st["v"]
	var mass: PackedFloat64Array = st["mass"]
	var w: PackedFloat64Array = st["w"]
	var ke := 0.0
	for i in mass.size():
		if w[i] > 0.0:
			ke += 0.5 * mass[i] * (v[3 * i] * v[3 * i] + v[3 * i + 1] * v[3 * i + 1] + v[3 * i + 2] * v[3 * i + 2])
	var mu: float = st["mu"]
	var lam: float = st["lam"]
	var gam: float = st["gamma"]
	var v0: PackedFloat64Array = st["v0"]
	var tets: PackedInt32Array = st["tets"]
	var dm: PackedFloat64Array = st["dm"]
	var x: PackedFloat64Array = st["x"]
	var el := 0.0
	var jsum := 0.0
	var vcell := 0.0
	for t in v0.size():
		var F := _f_gd(x, tets, dm, t)
		var R := _polar_gd(F)
		var d2 := 0.0
		for q in 9:
			d2 += (F[q] - R[q]) * (F[q] - R[q])
		el += mu * v0[t] * d2
		jsum += v0[t] * (F[0] * (F[4] * F[8] - F[5] * F[7]) - F[1] * (F[3] * F[8] - F[5] * F[6]) + F[2] * (F[3] * F[7] - F[4] * F[6]))
		vcell += v0[t]
		if t % 6 == 5:
			el += 0.5 * lam * vcell * (jsum / vcell - gam) * (jsum / vcell - gam)
			jsum = 0.0
			vcell = 0.0
	return {"ke": ke, "el": el}


# ============================================================ the step

## One frame: o {dt (the frame, s), nsub, iters, g (Vector3), damp (1/s)}. Pinned nodes go to st.pin_to through the substeps.
static func step(st: Dictionary, o: Dictionary) -> void:
	var dt := float(o.get("dt", 1.0 / 60.0))
	var nsub := int(o.get("nsub", 8))
	var iters := int(o.get("iters", 2))
	var g: Vector3 = o.get("g", Vector3(0.0, -9.81, 0.0))
	var damp := float(o.get("damp", 0.0))
	var fext: PackedFloat64Array = st["fext"]
	if fext.size() != 3 * int(st["n"]):
		fext = PackedFloat64Array()
		fext.resize(3 * int(st["n"]))
	var vref: PackedFloat64Array = st.get("vref", PackedFloat64Array())
	if vref.size() != 3 * int(st["n"]):
		vref = PackedFloat64Array()
	var door = native_door()
	var r: Array
	if door != null:
		r = door.run(st["x"], st["v"], st["w"], st["tets"], st["dm"], st["v0"], st["pin_idx"], st["pin_to"], fext, vref, nsub, iters, dt,
				st["mu"], st["lam"], st["gamma"], g.x, g.y, g.z, damp)
	else:
		r = _step_gd(st, fext, vref, nsub, iters, dt, g, damp)
	st["x"] = r[0]
	st["v"] = r[1]


## THE FALLBACK: the arithmetic of kine_soft_native.cpp, line for line.
static func _step_gd(st: Dictionary, fext: PackedFloat64Array, vref_in: PackedFloat64Array, nsub: int, iters: int, dt_frame: float, g: Vector3, damp_rate: float) -> Array:
	var x: PackedFloat64Array = (st["x"] as PackedFloat64Array).duplicate()
	var v: PackedFloat64Array = (st["v"] as PackedFloat64Array).duplicate()
	var w: PackedFloat64Array = st["w"]
	var tets: PackedInt32Array = st["tets"]
	var dm: PackedFloat64Array = st["dm"]
	var v0: PackedFloat64Array = st["v0"]
	var pin: PackedInt32Array = st["pin_idx"]
	var pto: PackedFloat64Array = st["pin_to"]
	var mu: float = st["mu"]
	var lam: float = st["lam"]
	var gamma: float = st["gamma"]
	var n3 := x.size()
	var N := n3 / 3
	var T := v0.size()
	var vref := vref_in
	if vref.size() != n3:
		vref = PackedFloat64Array()
		vref.resize(n3)
	var x0 := x.duplicate()
	var lamD := PackedFloat64Array()
	lamD.resize(T)
	var NC := T / 6   # the hydrostatic constraint is per cell (six tets)
	var lamH := PackedFloat64Array()
	lamH.resize(NC)
	var dt := dt_frame / float(nsub)
	var damp := exp(-damp_rate * dt)
	var gg := [g.x, g.y, g.z]
	for s in range(1, nsub + 1):
		var u := float(s) / float(nsub)
		var xp := x.duplicate()
		for i in N:
			if w[i] > 0.0:
				for r in 3:
					v[i * 3 + r] += dt * (gg[r] + w[i] * fext[i * 3 + r])
					x[i * 3 + r] += dt * v[i * 3 + r]
		for j in pin.size():
			var i := pin[j]
			for r in 3:
				x[i * 3 + r] = x0[i * 3 + r] + u * (pto[j * 3 + r] - x0[i * 3 + r])
		lamD.fill(0.0)
		lamH.fill(0.0)
		for it in iters:
			for t in T:
				lamD[t] = _dev_gd(x, w, tets, dm, t, v0[t], 2.0 * mu, dt, lamD[t])
			for c in NC:
				lamH[c] = _cell_gd(x, w, tets, dm, v0, c, lam, gamma, dt, lamH[c])
		for i in n3:
			v[i] = vref[i] + (((x[i] - xp[i]) / dt) - vref[i]) * damp
	return [x, v]


## F = Ds Dm^-1 of tet t, row-major 9 values
static func _f_gd(x: PackedFloat64Array, tets: PackedInt32Array, dm: PackedFloat64Array, t: int) -> Array:
	var i0 := tets[4 * t] * 3
	var i1 := tets[4 * t + 1] * 3
	var i2 := tets[4 * t + 2] * 3
	var i3 := tets[4 * t + 3] * 3
	var b := 9 * t
	var F := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for r in 3:
		var c1 := x[i1 + r] - x[i0 + r]
		var c2 := x[i2 + r] - x[i0 + r]
		var c3 := x[i3 + r] - x[i0 + r]
		for q in 3:
			F[r * 3 + q] = c1 * dm[b + q] + c2 * dm[b + 3 + q] + c3 * dm[b + 6 + q]
	return F


## the gradient of C w.r.t. the four nodes from G = dC/dF (row-major): g[k+1][r] = sum_c G[r][c] Dm^-1[k][c]; g[0] = -(g1 + g2 + g3)
static func _grads_gd(G: Array, dm: PackedFloat64Array, b: int) -> Array:
	var gk := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for kk in 3:
		for r in 3:
			gk[kk + 1][r] = G[r * 3] * dm[b + kk * 3] + G[r * 3 + 1] * dm[b + kk * 3 + 1] + G[r * 3 + 2] * dm[b + kk * 3 + 2]
	for r in 3:
		gk[0][r] = -(gk[1][r] + gk[2][r] + gk[3][r])
	return gk


## Polar rotation R of F (row-major 9) by Higham's Newton iteration R <- (R + R^-T) / 2, up to 12 rounds, stopping when no entry moves by 1e-13; the operation order is
## the one of polar() in kine_soft_native.cpp.
static func _polar_gd(F: Array) -> Array:
	var R: Array = F.duplicate()
	for it in 12:
		var c00: float = R[4] * R[8] - R[5] * R[7]
		var c01: float = R[5] * R[6] - R[3] * R[8]
		var c02: float = R[3] * R[7] - R[4] * R[6]
		var c10: float = R[2] * R[7] - R[1] * R[8]
		var c11: float = R[0] * R[8] - R[2] * R[6]
		var c12: float = R[1] * R[6] - R[0] * R[7]
		var c20: float = R[1] * R[5] - R[2] * R[4]
		var c21: float = R[2] * R[3] - R[0] * R[5]
		var c22: float = R[0] * R[4] - R[1] * R[3]
		var det: float = R[0] * c00 + R[1] * c01 + R[2] * c02
		if absf(det) < 1e-18:
			break
		var idet := 1.0 / det
		var n: Array = [0.5 * (R[0] + c00 * idet), 0.5 * (R[1] + c01 * idet), 0.5 * (R[2] + c02 * idet),
				0.5 * (R[3] + c10 * idet), 0.5 * (R[4] + c11 * idet), 0.5 * (R[5] + c12 * idet),
				0.5 * (R[6] + c20 * idet), 0.5 * (R[7] + c21 * idet), 0.5 * (R[8] + c22 * idet)]
		var dmax := 0.0
		for q in 9:
			dmax = maxf(dmax, absf(n[q] - R[q]))
		R = n
		if dmax < 1e-13:
			break
	return R


## The deviatoric (corotated) constraint of one tet: C = |F - R|, stiffness k = 2 mu. x changed in place; the new multiplier returned.
static func _dev_gd(x: PackedFloat64Array, w: PackedFloat64Array, tets: PackedInt32Array, dm: PackedFloat64Array, t: int, v0: float,
		k: float, dt: float, lam_in: float) -> float:
	var F := _f_gd(x, tets, dm, t)
	var R := _polar_gd(F)
	var s2 := 0.0
	for r in 3:
		for q in 3:
			s2 += (F[r * 3 + q] - R[r * 3 + q]) * (F[r * 3 + q] - R[r * 3 + q])
	var C := sqrt(s2)
	if C < 1e-12:
		return lam_in
	var G := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for r in 3:
		for q in 3:
			G[r * 3 + q] = (F[r * 3 + q] - R[r * 3 + q]) / C
	var gk := _grads_gd(G, dm, 9 * t)
	var ids := [tets[4 * t], tets[4 * t + 1], tets[4 * t + 2], tets[4 * t + 3]]
	var s := 0.0
	for a in 4:
		var wa: float = w[ids[a]]
		s += wa * (gk[a][0] * gk[a][0] + gk[a][1] * gk[a][1] + gk[a][2] * gk[a][2])
	var at := (1.0 / (k * v0)) / (dt * dt)
	var den := s + at
	if den < 1e-30:
		return lam_in
	var dl := (-C - at * lam_in) / den
	for a in 4:
		var f: float = w[ids[a]] * dl
		var ia: int = ids[a] * 3
		x[ia] += f * gk[a][0]
		x[ia + 1] += f * gk[a][1]
		x[ia + 2] += f * gk[a][2]
	return lam_in + dl


## The hydrostatic constraint of one CELL (its six tets): C = sum(V0 det F) / sum(V0) - gamma, compliance 1 / (lambda V0cell).
## One det F = const per tet over-constrains a tet mesh (volumetric locking; bar 1c measured 2.6 % volume lost at nu 0.495 that
## way, against 0.4 % from the continuum); the cell's mean dilatation is the cure.
static func _cell_gd(x: PackedFloat64Array, w: PackedFloat64Array, tets: PackedInt32Array, dm: PackedFloat64Array, v0: PackedFloat64Array,
		cell: int, k: float, gamma: float, dt: float, lam_in: float) -> float:
	if k <= 0.0:
		return lam_in   # lambda = 0 (nu = 0): no volume term
	var ids := []
	var gs := []
	var jsum := 0.0
	var vc := 0.0
	for tt in 6:
		var t := cell * 6 + tt
		var F := _f_gd(x, tets, dm, t)
		var f0x: float = F[0]
		var f0y: float = F[3]
		var f0z: float = F[6]
		var f1x: float = F[1]
		var f1y: float = F[4]
		var f1z: float = F[7]
		var f2x: float = F[2]
		var f2y: float = F[5]
		var f2z: float = F[8]
		var a0 := f1y * f2z - f1z * f2y
		var a1 := f1z * f2x - f1x * f2z
		var a2 := f1x * f2y - f1y * f2x
		var b0 := f2y * f0z - f2z * f0y
		var b1 := f2z * f0x - f2x * f0z
		var b2 := f2x * f0y - f2y * f0x
		var d0 := f0y * f1z - f0z * f1y
		var d1 := f0z * f1x - f0x * f1z
		var d2 := f0x * f1y - f0y * f1x
		var G := [a0, b0, d0, a1, b1, d1, a2, b2, d2]
		var J := f0x * a0 + f0y * a1 + f0z * a2
		jsum += v0[t] * J
		vc += v0[t]
		var gk := _grads_gd(G, dm, 9 * t)
		for a in 4:
			var nid := tets[4 * t + a]
			var li := ids.find(nid)
			if li < 0:
				li = ids.size()
				ids.append(nid)
				gs.append([0.0, 0.0, 0.0])
			gs[li][0] += v0[t] * gk[a][0]
			gs[li][1] += v0[t] * gk[a][1]
			gs[li][2] += v0[t] * gk[a][2]
	var C := jsum / vc - gamma
	var s := 0.0
	for q in ids.size():
		for r in 3:
			gs[q][r] = gs[q][r] / vc
		var wq: float = w[ids[q]]
		s += wq * (gs[q][0] * gs[q][0] + gs[q][1] * gs[q][1] + gs[q][2] * gs[q][2])
	var at := (1.0 / (k * vc)) / (dt * dt)
	var den := s + at
	if den < 1e-30:
		return lam_in
	var dl := (-C - at * lam_in) / den
	for q in ids.size():
		var f: float = w[ids[q]] * dl
		var ia: int = ids[q] * 3
		x[ia] += f * gs[q][0]
		x[ia + 1] += f * gs[q][1]
		x[ia + 2] += f * gs[q][2]
	return lam_in + dl


# ============================================================ regions on the body

## L22: the BODY panel's toggles, each a group of regions (the order the scene key keeps them in)
const GROUPS := {"belly": ["belly"], "chest": ["chest"], "thighs": ["thigh_l", "thigh_r"], "arms": ["arm_l", "arm_r"]}
const STRENGTH_MAX := 4.0


## the strength multiplier of the live flesh (the scene key "strength", 1 when absent)
static func strength_of(S: Scene) -> float:
	return clampf(float(S.soft.get("strength", 1.0)), 0.0, STRENGTH_MAX)


## true when the scene asks for any region
static func active(S: Scene) -> bool:
	return not regions_of(S).is_empty()


static func regions_of(S: Scene) -> Array:
	var out := []
	for n in (S.soft.get("regions", []) as Array):
		if REGIONS.has(String(n)):
			out.append(String(n))
	return out


## A region on the rest body B. ov: E, nu, rho, damp overrides, shift (Vector3, a test's wrong placement).
static func region_new(B: Body, name: String, ov := {}) -> Dictionary:
	var d: Dictionary = REGIONS[name]
	var host: String = d["host"]
	var c: Array = B.cap0[host]
	var r := float(B.rad[host])
	var ca: Vector3 = c[0]
	var cb: Vector3 = c[1]
	var ax := (cb - ca)
	var n_dir := (d["dir"] as Vector3).normalized()
	var a_dir := (ax - n_dir * ax.dot(n_dir)).normalized()
	var c_dir := a_dir.cross(n_dir)
	var inner := r * float(d["inner"])
	var size := Vector3(float(d["width"]), float(d["height"]), r + float(d["outer"]) - inner)
	var origin_c: Vector3 = ca.lerp(cb, float(d["t"])) + n_dir * (inner + size.z * 0.5) + (ov.get("shift", Vector3.ZERO) as Vector3)
	var xf := Transform3D(Basis(c_dir, a_dir, n_dir), origin_c)
	var mat := {"E": float(ov.get("E", d["E"])), "nu": float(ov.get("nu", d["nu"])), "rho": float(ov.get("rho", d["rho"]))}
	var nn: Vector3i = d["n"]
	var st := block(nn, size, mat, -size * 0.5, xf)
	var inner_layer := PackedInt32Array()
	for iy in nn.y + 1:
		for ix in nn.x + 1:
			inner_layer.append(iy * (nn.x + 1) + ix)   # iz = 0
	pin(st, inner_layer)
	var rest := PackedVector3Array()
	for i in int(st["n"]):
		rest.append(node(st, i))
	return {"name": name, "host": host, "st": st, "rest": rest, "xf": xf, "size": size, "n": nn, "damp": float(ov.get("damp", d["damp"])),
		"static": PackedVector3Array(), "dir": n_dir}


## the world place of every node as the host bone carries it (rigid): the rest place through the host's joint now
static func region_pose(reg: Dictionary, B: Body) -> PackedVector3Array:
	var host: String = reg["host"]
	var g: Quaternion = B.G[host]
	var pj: Vector3 = B.P[host]
	var rj: Vector3 = B.p0[host]
	var out := PackedVector3Array()
	for q in (reg["rest"] as PackedVector3Array):
		out.append(pj + g * (q - rj))
	return out


## Sets the driven nodes from B and runs one frame. o: dt, nsub, iters, g, damp (default the region's x damp_scale)
static func region_step(reg: Dictionary, B: Body, o: Dictionary) -> void:
	var st: Dictionary = reg["st"]
	var pose := region_pose(reg, B)
	var pin_idx: PackedInt32Array = st["pin_idx"]
	var pt := PackedFloat64Array()
	pt.resize(3 * pin_idx.size())
	for j in pin_idx.size():
		pt[3 * j] = pose[pin_idx[j]].x
		pt[3 * j + 1] = pose[pin_idx[j]].y
		pt[3 * j + 2] = pose[pin_idx[j]].z
	st["pin_to"] = pt
	# damping is relative to the bone: the velocity the host carries each node at, over this frame
	var prev: PackedVector3Array = reg.get("pose_prev", pose)
	var dtf := float(o.get("dt", 1.0 / 60.0))
	var vr := PackedFloat64Array()
	vr.resize(3 * pose.size())
	for i in pose.size():
		var d := (pose[i] - prev[i]) / dtf
		vr[3 * i] = d.x
		vr[3 * i + 1] = d.y
		vr[3 * i + 2] = d.z
	st["vref"] = vr
	reg["pose_prev"] = pose
	var oo := o.duplicate()
	if not oo.has("damp"):
		oo["damp"] = float(reg["damp"]) * float(o.get("damp_scale", 1.0))
	step(st, oo)


## the free flesh's displacement from the bone-carried place (world metres), the standing sag removed once taken
static func region_disp(reg: Dictionary, B: Body) -> PackedVector3Array:
	var pose := region_pose(reg, B)
	var st: Dictionary = reg["st"]
	var stat: PackedVector3Array = reg["static"]
	var out := PackedVector3Array()
	# L22: the standing sag is a displacement in the HOST's frame (the skinned mesh carries it with the bone). With sag_body the
	# stored world sag is turned by the host's rotation since it was taken; the old default subtracts it unturned (soft_test.gd).
	var rot := Quaternion.IDENTITY
	if reg.get("sag_body", false) and reg.has("g0"):
		rot = (B.G[reg["host"]] as Quaternion) * (reg["g0"] as Quaternion).inverse()
	for i in pose.size():
		var d := node(st, i) - pose[i]
		if not stat.is_empty():
			d -= rot * stat[i]
		out.append(d)
	return out


## Bakes regions over a Scene: {hz, frames, regions: {name: {disp: [PackedVector3Array per frame]}}}. B is put back as it was.
## o: damp_scale (a test's over-damped control), preroll (s, default 1.0), plus region_new's overrides.
## L22: sag_frame "body" turns the standing sag with the host bone (default "world": the L17 behaviour); cancel: an Array whose [0]
## true ends the bake early ({} returned). The result also carries "static" {name: sag} and "geom" {name: host, xf, size, n} (all
## the live deform needs of a region, so the app never builds a region of its own).
static func bake_scene(S: Scene, B: Body, names: Array, hz: float, o := {}) -> Dictionary:
	var out := {"hz": hz, "frames": 0, "regions": {}}
	var cancel: Array = o.get("cancel", [false])
	var body_sag: bool = String(o.get("sag_frame", "world")) == "body"
	if names.is_empty():
		return out
	var keep := B.state()
	var L := S.length()
	var nf := maxi(int(ceil(L * hz - 1e-6)), 1) + 1
	var nsub := maxi(1, int(round(480.0 / hz)))
	var step_o := {"dt": 1.0 / hz, "nsub": nsub, "iters": DEFAULT_ITERS, "g": Vector3(0.0, -9.81, 0.0), "damp_scale": float(o.get("damp_scale", 1.0))}
	S.apply(B, 0.0)
	var regs := []
	for n in names:
		regs.append(region_new(B, String(n), o))
	for k in int(float(o.get("preroll", 1.0)) * hz):
		if cancel[0]:
			return {}
		for reg in regs:
			region_step(reg, B, step_o)
	out["static"] = {}
	out["geom"] = {}
	for reg in regs:
		reg["static"] = region_disp(reg, B)
		if body_sag:
			reg["sag_body"] = true
			reg["g0"] = B.G[reg["host"]]
		(out["regions"] as Dictionary)[reg["name"]] = {"disp": []}
		out["static"][reg["name"]] = reg["static"]
		out["geom"][reg["name"]] = {"name": reg["name"], "host": reg["host"], "xf": reg["xf"], "size": reg["size"], "n": reg["n"]}
	for k in nf:
		if cancel[0]:
			B.set_state(keep)
			B.fk()
			return {}
		S.apply(B, minf(float(k) / hz, L))
		for reg in regs:
			region_step(reg, B, step_o)
			((out["regions"][reg["name"]] as Dictionary)["disp"] as Array).append(region_disp(reg, B))
	out["frames"] = nf
	B.set_state(keep)
	B.fk()
	return out


# ============================================================ onto the skin

## a world point in the region's box coordinates (metres from the box's min corner), through the host's pose now
static func _box_coord(reg: Dictionary, B: Body, p: Vector3) -> Vector3:
	var host: String = reg["host"]
	var g: Quaternion = B.G[host]
	var q: Vector3 = (B.p0[host] as Vector3) + g.inverse() * (p - (B.P[host] as Vector3))
	return (reg["xf"] as Transform3D).affine_inverse() * q + (reg["size"] as Vector3) * 0.5


## is the point inside the region's box (grown by margin m on every side)?
static func in_box(reg: Dictionary, B: Body, p: Vector3, m: float) -> bool:
	var u := _box_coord(reg, B, p)
	var s: Vector3 = reg["size"]
	return u.x >= -m and u.y >= -m and u.z >= -m and u.x <= s.x + m and u.y <= s.y + m and u.z <= s.z + m


static func _smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## The world offset of each skin vertex (verts: posed world points) from the region's displacement `disp` (region_disp at that
## frame): trilinear in the cell, faded to zero toward the lateral edges of the box so no seam opens. Zero outside the box.
static func vertex_offsets(reg: Dictionary, B: Body, disp: PackedVector3Array, verts: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(verts.size())
	var s: Vector3 = reg["size"]
	var nn: Vector3i = reg["n"]
	var nx := nn.x + 1
	var ny := nn.y + 1
	for i in verts.size():
		var u := _box_coord(reg, B, verts[i])
		if u.x < 0.0 or u.y < 0.0 or u.z < 0.0 or u.x > s.x or u.y > s.y or u.z > s.z:
			continue
		var fx := u.x / s.x * float(nn.x)
		var fy := u.y / s.y * float(nn.y)
		var fz := u.z / s.z * float(nn.z)
		var cx := mini(int(floor(fx)), nn.x - 1)
		var cy := mini(int(floor(fy)), nn.y - 1)
		var cz := mini(int(floor(fz)), nn.z - 1)
		var tx := fx - float(cx)
		var ty := fy - float(cy)
		var tz := fz - float(cz)
		var d := Vector3.ZERO
		for dz in 2:
			for dy in 2:
				for dx in 2:
					var wgt := (tx if dx == 1 else 1.0 - tx) * (ty if dy == 1 else 1.0 - ty) * (tz if dz == 1 else 1.0 - tz)
					d += disp[((cz + dz) * ny + (cy + dy)) * nx + (cx + dx)] * wgt
		var fade := _smooth(0.0, 0.25, minf(u.x / s.x, 1.0 - u.x / s.x)) * _smooth(0.0, 0.25, minf(u.y / s.y, 1.0 - u.y / s.y))
		out[i] = d * fade
	return out


## the scene key mirrored: a region to its twin side
static func mirror_file(d: Dictionary) -> Dictionary:
	var out := []
	for n in (d.get("regions", []) as Array):
		var m := String(n)
		if m.ends_with("_l"):
			m = m.trim_suffix("_l") + "_r"
		elif m.ends_with("_r"):
			m = m.trim_suffix("_r") + "_l"
		out.append(m)
	var res := {"regions": out}
	if d.has("strength"):
		res["strength"] = d["strength"]
	return res


## The skinned piece of the mannequin with the region jiggle added to its vertices, or null when none of its vertices moves.
## regs / disps: the regions and their region_disp at this frame; B posed at the same frame. The offset is a WORLD displacement; the
## mesh is skinned on the GPU, so it goes into the bind-pose vertex through the inverse of the vertex's blended skinning matrix.
static func skin_deform(piece: MeshInstance3D, regs: Array, B: Body, disps: Array) -> ArrayMesh:
	var mesh := piece.mesh as ArrayMesh
	var sk := piece.get_node_or_null(piece.skeleton) as Skeleton3D
	var skin := piece.skin
	if mesh == null or sk == null or skin == null:
		return null
	var nb := skin.get_bind_count()
	var mb := []
	for b in nb:
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = sk.find_bone(skin.get_bind_name(b))
		mb.append(sk.get_bone_global_pose(bone) * skin.get_bind_pose(b))
	var gt := sk.global_transform
	var gi := gt.basis.inverse()
	var out := ArrayMesh.new()
	var any := false
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(verts.size(), 1)
		var mats := []   # per vertex: the blended skinning matrix as [x, y, z, origin]
		var world := PackedVector3Array()
		world.resize(verts.size())
		for i in verts.size():
			var bx := Vector3.ZERO
			var by := Vector3.ZERO
			var bz := Vector3.ZERO
			var bo := Vector3.ZERO
			for q in per:
				var wq := weights[i * per + q]
				if wq <= 0.0:
					continue
				var m: Transform3D = mb[bones[i * per + q]]
				bx += m.basis.x * wq
				by += m.basis.y * wq
				bz += m.basis.z * wq
				bo += m.origin * wq
			mats.append([bx, by, bz])
			world[i] = gt * (bx * verts[i].x + by * verts[i].y + bz * verts[i].z + bo)
		var off := PackedVector3Array()
		off.resize(verts.size())
		for ri in regs.size():
			var o := vertex_offsets(regs[ri], B, disps[ri], world)
			for i in verts.size():
				off[i] += o[i]
		var nv := verts.duplicate()
		for i in verts.size():
			if off[i].length() > 1e-9:
				var m3: Array = mats[i]
				var bas := Basis(m3[0], m3[1], m3[2])
				if absf(bas.determinant()) > 1e-12:
					nv[i] = verts[i] + bas.inverse() * (gi * off[i])
					any = true
		arr[Mesh.ARRAY_VERTEX] = nv
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, mesh.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	return out if any else null
