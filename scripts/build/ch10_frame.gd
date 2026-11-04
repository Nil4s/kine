class_name Ch10Frame
extends RefCounted
## CH10: 3D Euler-Bernoulli frame solver. C++ twin: native/src/kine_frame_native.cpp (KineFrameNative), same element matrices, same Newmark.
## This GDScript path is DENSE and meant for small frames (the equality bar uses 10 members); the house runs through the native class.
## Units are the caller's (the house: N, m, kg, s). 6 DOF per node (ux uy uz rx ry rz), global dof = node * 6 + d.
## model: xyz (PackedFloat64Array, 3/node), beams (12/elem: n1 n2 A Iz Iy J E G rho e2x e2y e2z), springs (3/spring: n1 n2 k), fixed (PackedInt32Array dofs), mass (per node, added to ux uy uz)
## job: {type: "static", loads} | {type: "modal", start, iters} | {type: "newmark", dt, nsteps, ag, dir, alpha, beta, u0, v0, record, snap_every}

static var _door = null
static var _tried := false


## the native door (scripts/build/ch10_frame_native.gd) or null: no DLL, or KINE_NO_NATIVE=1
static func door():
	if OS.get_environment("KINE_NO_NATIVE") == "1":
		return null
	if not _tried:
		_tried = true
		if NativeExt.ensure("kine_native", "KineFrameNative"):
			_door = load("res://scripts/build/ch10_frame_native.gd")
	return _door


static func native_ok() -> bool:
	return door() != null


static func solve(model: Dictionary, job: Dictionary, force_gd := false) -> Dictionary:
	var d = door()
	if d != null and not force_gd:
		return d.solve(model, job)
	return solve_gd(model, job)


# ---------------------------------------------------------------------------------------------------------------- GDScript twin
static func _elem(xyz: PackedFloat64Array, e: PackedFloat64Array) -> Array:
	## returns [K(144), M(144), n1, n2]
	var n1 := int(e[0])
	var n2 := int(e[1])
	var d := [xyz[n2 * 3] - xyz[n1 * 3], xyz[n2 * 3 + 1] - xyz[n1 * 3 + 1], xyz[n2 * 3 + 2] - xyz[n1 * 3 + 2]]
	var L := sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2])
	var e1 := [d[0] / L, d[1] / L, d[2] / L]
	var dp: float = e[9] * e1[0] + e[10] * e1[1] + e[11] * e1[2]
	var e2 := [e[9] - dp * e1[0], e[10] - dp * e1[1], e[11] - dp * e1[2]]
	var l2 := sqrt(e2[0] * e2[0] + e2[1] * e2[1] + e2[2] * e2[2])
	for i in 3:
		e2[i] = e2[i] / l2
	var e3 := [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]]
	var A: float = e[2]
	var Iz: float = e[3]
	var Iy: float = e[4]
	var J: float = e[5]
	var E: float = e[6]
	var G: float = e[7]
	var rho: float = e[8]
	var kl := PackedFloat64Array()
	kl.resize(144)
	var ml := PackedFloat64Array()
	ml.resize(144)
	var L2 := L * L
	var L3 := L2 * L
	var ea := E * A / L
	kl[0] += ea
	kl[6 * 12 + 6] += ea
	kl[6] -= ea
	kl[6 * 12] -= ea
	var ma := rho * A * L / 6.0
	ml[0] += 2 * ma
	ml[6 * 12 + 6] += 2 * ma
	ml[6] += ma
	ml[6 * 12] += ma
	var gj := G * J / L
	kl[3 * 12 + 3] += gj
	kl[9 * 12 + 9] += gj
	kl[3 * 12 + 9] -= gj
	kl[9 * 12 + 3] -= gj
	var mt := rho * (Iz + Iy) * L / 6.0
	ml[3 * 12 + 3] += 2 * mt
	ml[9 * 12 + 9] += 2 * mt
	ml[3 * 12 + 9] += mt
	ml[9 * 12 + 3] += mt
	var ix1 := [1, 5, 7, 11]
	var c1 := E * Iz / L3
	var kb1 := [[12, 6 * L, -12, 6 * L], [6 * L, 4 * L2, -6 * L, 2 * L2], [-12, -6 * L, 12, -6 * L], [6 * L, 2 * L2, -6 * L, 4 * L2]]
	var cm := rho * A * L / 420.0
	var mb1 := [[156, 22 * L, 54, -13 * L], [22 * L, 4 * L2, 13 * L, -3 * L2], [54, 13 * L, 156, -22 * L], [-13 * L, -3 * L2, -22 * L, 4 * L2]]
	for i in 4:
		for j in 4:
			kl[ix1[i] * 12 + ix1[j]] += c1 * kb1[i][j]
			ml[ix1[i] * 12 + ix1[j]] += cm * mb1[i][j]
	var ix2 := [2, 4, 8, 10]
	var c2 := E * Iy / L3
	var kb2 := [[12, -6 * L, -12, -6 * L], [-6 * L, 4 * L2, 6 * L, 2 * L2], [-12, 6 * L, 12, 6 * L], [-6 * L, 2 * L2, 6 * L, 4 * L2]]
	var mb2 := [[156, -22 * L, 54, 13 * L], [-22 * L, 4 * L2, -13 * L, -3 * L2], [54, -13 * L, 156, 22 * L], [13 * L, -3 * L2, 22 * L, 4 * L2]]
	for i in 4:
		for j in 4:
			kl[ix2[i] * 12 + ix2[j]] += c2 * kb2[i][j]
			ml[ix2[i] * 12 + ix2[j]] += cm * mb2[i][j]
	var R := [e1[0], e1[1], e1[2], e2[0], e2[1], e2[2], e3[0], e3[1], e3[2]]
	var T := PackedFloat64Array()
	T.resize(144)
	for b in 4:
		for i in 3:
			for j in 3:
				T[(b * 3 + i) * 12 + b * 3 + j] = R[i * 3 + j]
	var outs := []
	for src in [kl, ml]:
		var tmp := PackedFloat64Array()
		tmp.resize(144)
		for i in 12:
			for j in 12:
				var s := 0.0
				for k in 12:
					s += src[i * 12 + k] * T[k * 12 + j]
				tmp[i * 12 + j] = s
		var dst := PackedFloat64Array()
		dst.resize(144)
		for i in 12:
			for j in 12:
				var s := 0.0
				for k in 12:
					s += T[k * 12 + i] * tmp[k * 12 + j]
				dst[i * 12 + j] = s
		outs.append(dst)
	return [outs[0], outs[1], n1, n2]


static func solve_gd(model: Dictionary, job: Dictionary) -> Dictionary:
	var out := {}
	var xyz: PackedFloat64Array = model["xyz"]
	var nn := xyz.size() / 3
	var nd6 := nn * 6
	var fixed := {}
	for d in model.get("fixed", PackedInt32Array()):
		fixed[d] = true
	var map := PackedInt32Array()
	map.resize(nd6)
	var nf := 0
	for i in nd6:
		if fixed.has(i):
			map[i] = -1
		else:
			map[i] = nf
			nf += 1
	var K := PackedFloat64Array()
	K.resize(nf * nf)
	var M := PackedFloat64Array()
	M.resize(nf * nf)
	var bm: PackedFloat64Array = model["beams"]
	var elems: Array = []
	for b in range(0, bm.size(), 12):
		var e := bm.slice(b, b + 12)
		var r := _elem(xyz, e)
		elems.append(r)
		var gd := PackedInt32Array()
		for i in 6:
			gd.append(int(r[2]) * 6 + i)
		for i in 6:
			gd.append(int(r[3]) * 6 + i)
		for i in 12:
			var fi := map[gd[i]]
			if fi < 0:
				continue
			for j in 12:
				var fj := map[gd[j]]
				if fj < 0:
					continue
				K[fi * nf + fj] += r[0][i * 12 + j]
				M[fi * nf + fj] += r[1][i * 12 + j]
	var sp: PackedFloat64Array = model.get("springs", PackedFloat64Array())
	var sprs: Array = []
	for s in range(0, sp.size(), 3):
		var a := int(sp[s])
		var b2 := int(sp[s + 1])
		var k := sp[s + 2]
		var d := [xyz[b2 * 3] - xyz[a * 3], xyz[b2 * 3 + 1] - xyz[a * 3 + 1], xyz[b2 * 3 + 2] - xyz[a * 3 + 2]]
		var L := sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2])
		var n := [d[0] / L, d[1] / L, d[2] / L]
		sprs.append([a, b2, k, n])
		var gd := [a * 6, a * 6 + 1, a * 6 + 2, b2 * 6, b2 * 6 + 1, b2 * 6 + 2]
		var sg := [-n[0], -n[1], -n[2], n[0], n[1], n[2]]
		for i in 6:
			var fi := map[gd[i]]
			if fi < 0:
				continue
			for j in 6:
				var fj := map[gd[j]]
				if fj < 0:
					continue
				K[fi * nf + fj] += k * sg[i] * sg[j]
	var am: PackedFloat64Array = model.get("mass", PackedFloat64Array())
	if am.size() == nn:
		for nd in nn:
			if am[nd] == 0.0:
				continue
			for d in 3:
				var f := map[nd * 6 + d]
				if f >= 0:
					M[f * nf + f] += am[nd]
	out["nfree"] = nf
	var typ: String = job["type"]

	var gather := func(g: PackedFloat64Array) -> PackedFloat64Array:
		var f := PackedFloat64Array()
		f.resize(nf)
		for i in nd6:
			if map[i] >= 0:
				f[map[i]] = g[i]
		return f
	var scatter := func(f: PackedFloat64Array) -> PackedFloat64Array:
		var g := PackedFloat64Array()
		g.resize(nd6)
		for i in nd6:
			if map[i] >= 0:
				g[i] = f[map[i]]
		return g
	var mul := func(A: PackedFloat64Array, x: PackedFloat64Array) -> PackedFloat64Array:
		var y := PackedFloat64Array()
		y.resize(nf)
		for i in nf:
			var s := 0.0
			var o := i * nf
			for j in nf:
				s += A[o + j] * x[j]
			y[i] = s
		return y
	var chol := func(A: PackedFloat64Array) -> PackedFloat64Array:
		var Lm := A.duplicate()
		for j in nf:
			var s := Lm[j * nf + j]
			for k in j:
				s -= Lm[j * nf + k] * Lm[j * nf + k]
			if not (s > 1e-300):
				return PackedFloat64Array()
			var dd := sqrt(s)
			Lm[j * nf + j] = dd
			for i in range(j + 1, nf):
				var t := Lm[i * nf + j]
				for k in j:
					t -= Lm[i * nf + k] * Lm[j * nf + k]
				Lm[i * nf + j] = t / dd
		return Lm
	var csolve := func(Lm: PackedFloat64Array, rhs: PackedFloat64Array) -> PackedFloat64Array:
		var x := rhs.duplicate()
		for i in nf:
			var s := x[i]
			for k in i:
				s -= Lm[i * nf + k] * x[k]
			x[i] = s / Lm[i * nf + i]
		for i in range(nf - 1, -1, -1):
			var s := x[i]
			for k in range(i + 1, nf):
				s -= Lm[k * nf + i] * x[k]
			x[i] = s / Lm[i * nf + i]
		return x
	var internal := func(ug: PackedFloat64Array) -> PackedFloat64Array:
		var f := PackedFloat64Array()
		f.resize(nd6)
		for r in elems:
			var gd := PackedInt32Array()
			for i in 6:
				gd.append(int(r[2]) * 6 + i)
			for i in 6:
				gd.append(int(r[3]) * 6 + i)
			for i in 12:
				var s := 0.0
				for j in 12:
					s += r[0][i * 12 + j] * ug[gd[j]]
				f[gd[i]] += s
		for s2 in sprs:
			var a: int = s2[0]
			var b3: int = s2[1]
			var n: Array = s2[3]
			var ext := 0.0
			for i in 3:
				ext += n[i] * (ug[b3 * 6 + i] - ug[a * 6 + i])
			for i in 3:
				f[a * 6 + i] -= s2[2] * ext * n[i]
				f[b3 * 6 + i] += s2[2] * ext * n[i]
		return f

	if typ == "static":
		var Lk: PackedFloat64Array = chol.call(K)
		if Lk.is_empty():
			out["error"] = "stiffness not positive definite (a floating member or a mechanism)"
			return out
		var u: PackedFloat64Array = csolve.call(Lk, gather.call(job["loads"]))
		var ug: PackedFloat64Array = scatter.call(u)
		out["u"] = ug
		out["f"] = internal.call(ug)
		return out
	if typ == "modal":
		var Lk2: PackedFloat64Array = chol.call(K)
		if Lk2.is_empty():
			out["error"] = "stiffness not positive definite"
			return out
		var x: PackedFloat64Array = gather.call(job["start"])
		var rq := PackedFloat64Array()
		var ray := func(v: PackedFloat64Array) -> float:
			var a: PackedFloat64Array = mul.call(K, v)
			var b: PackedFloat64Array = mul.call(M, v)
			var nu := 0.0
			var de := 0.0
			for i in nf:
				nu += v[i] * a[i]
				de += v[i] * b[i]
			return nu / de
		rq.append(ray.call(x))
		for it in int(job.get("iters", 3)):
			var y: PackedFloat64Array = csolve.call(Lk2, mul.call(M, x))
			var nrm := 0.0
			for i in nf:
				nrm = maxf(nrm, absf(y[i]))
			for i in nf:
				y[i] = y[i] / nrm
			x = y
			rq.append(ray.call(x))
		out["rq"] = rq
		out["omega"] = sqrt(rq[rq.size() - 1])
		out["phi"] = scatter.call(x)
		return out
	if typ == "newmark":
		var dt: float = job["dt"]
		var ns: int = job["nsteps"]
		var beta := 0.25
		var gam := 0.5
		var ag: PackedFloat64Array = job.get("ag", PackedFloat64Array())
		var dir: int = job.get("dir", 0)
		var alpha: float = job.get("alpha", 0.0)
		var bet: float = job.get("beta", 0.0)
		var u := PackedFloat64Array()
		u.resize(nf)
		var v := PackedFloat64Array()
		v.resize(nf)
		var a := PackedFloat64Array()
		a.resize(nf)
		var u0: PackedFloat64Array = job.get("u0", PackedFloat64Array())
		var v0: PackedFloat64Array = job.get("v0", PackedFloat64Array())
		if u0.size() == nd6:
			u = gather.call(u0)
		if v0.size() == nd6:
			v = gather.call(v0)
		var r := PackedFloat64Array()
		r.resize(nf)
		for nd in nn:
			var f := map[nd * 6 + dir]
			if f >= 0:
				r[f] = 1.0
		var Mr: PackedFloat64Array = mul.call(M, r)
		var force := func(step: int) -> PackedFloat64Array:
			var P := PackedFloat64Array()
			P.resize(nf)
			if ag.size() > step:
				for i in nf:
					P[i] = -Mr[i] * ag[step]
			return P
		var cmul := func(x: PackedFloat64Array) -> PackedFloat64Array:
			var a1: PackedFloat64Array = mul.call(M, x)
			var a2: PackedFloat64Array = mul.call(K, x)
			var y := PackedFloat64Array()
			y.resize(nf)
			for i in nf:
				y[i] = alpha * a1[i] + bet * a2[i]
			return y
		var P0: PackedFloat64Array = force.call(0)
		var Cv: PackedFloat64Array = cmul.call(v)
		var dash: PackedFloat64Array = model.get("dashpots", PackedFloat64Array())   # CH12: (global dof, c) pairs on the damping diagonal
		for k in range(0, dash.size(), 2):
			var fd := map[int(dash[k])]
			if fd >= 0:
				Cv[fd] += dash[k + 1] * v[fd]
		var Ku: PackedFloat64Array = mul.call(K, u)
		var rhs0 := PackedFloat64Array()
		rhs0.resize(nf)
		for i in nf:
			rhs0[i] = P0[i] - Cv[i] - Ku[i]
		var Lm: PackedFloat64Array = chol.call(M)
		a = csolve.call(Lm, rhs0)
		var c1 := 1.0 / (beta * dt * dt)
		var c2 := gam / (beta * dt)
		var Ke := PackedFloat64Array()
		Ke.resize(nf * nf)
		for i in nf * nf:
			Ke[i] = K[i] * (1.0 + c2 * bet) + M[i] * (c1 + c2 * alpha)
		for k in range(0, dash.size(), 2):
			var fd2 := map[int(dash[k])]
			if fd2 >= 0:
				Ke[fd2 * nf + fd2] += c2 * dash[k + 1]
		var Lke: PackedFloat64Array = chol.call(Ke)
		# CH12 crowd: F0 sin(theta) per pedestrian, theta' = omega + cp v cos(theta), v the local deck velocity (cp 0 = free-running control)
		var crowd: Dictionary = job.get("crowd", {})
		var cn1: PackedInt32Array = crowd.get("n1", PackedInt32Array())
		var cn2: PackedInt32Array = crowd.get("n2", PackedInt32Array())
		var cw: PackedFloat64Array = crowd.get("w", PackedFloat64Array())
		var com: PackedFloat64Array = crowd.get("omega", PackedFloat64Array())
		var th: PackedFloat64Array = crowd.get("theta0", PackedFloat64Array()).duplicate()
		var cF0: float = crowd.get("F0", 0.0)
		var ccp: float = crowd.get("cp", 0.0)
		var cdir: int = crowd.get("dir", 2)
		var cpow := PackedFloat64Array()
		cpow.resize(ns + 1)
		if Lke.is_empty():
			out["error"] = "effective stiffness not positive definite"
			return out
		var rec: PackedInt32Array = job.get("record", PackedInt32Array())
		var nr := rec.size()
		var ru := PackedFloat64Array()
		ru.resize(nr * (ns + 1))
		var rv := ru.duplicate()
		var ra := ru.duplicate()
		var snaps := []
		var snap_every: int = job.get("snap_every", 0)
		for step in ns + 1:
			if step > 0:
				var P: PackedFloat64Array = force.call(step)
				for i in cn1.size():
					var f1 := map[cn1[i] * 6 + cdir]
					var f2 := map[cn2[i] * 6 + cdir]
					var wq: float = cw[i]
					var vi: float = (1.0 - wq) * (v[f1] if f1 >= 0 else 0.0) + wq * (v[f2] if f2 >= 0 else 0.0)
					var g1: float = com[i] + ccp * vi * cos(th[i])
					var tm: float = th[i] + 0.5 * dt * g1
					th[i] += dt * (com[i] + ccp * vi * cos(tm))
					var F: float = cF0 * sin(th[i])
					if f1 >= 0:
						P[f1] += (1.0 - wq) * F
					if f2 >= 0:
						P[f2] += wq * F
					cpow[step] += F * vi
				var t1 := PackedFloat64Array()
				t1.resize(nf)
				var t2 := PackedFloat64Array()
				t2.resize(nf)
				for i in nf:
					t1[i] = c1 * u[i] + (1.0 / (beta * dt)) * v[i] + (1.0 / (2 * beta) - 1.0) * a[i]
					t2[i] = c2 * u[i] + (gam / beta - 1.0) * v[i] + dt * (gam / (2 * beta) - 1.0) * a[i]
				var Mt: PackedFloat64Array = mul.call(M, t1)
				var Ct: PackedFloat64Array = cmul.call(t2)
				for k in range(0, dash.size(), 2):
					var fd3 := map[int(dash[k])]
					if fd3 >= 0:
						Ct[fd3] += dash[k + 1] * t2[fd3]
				var rhs := PackedFloat64Array()
				rhs.resize(nf)
				for i in nf:
					rhs[i] = P[i] + Mt[i] + Ct[i]
				var un: PackedFloat64Array = csolve.call(Lke, rhs)
				for i in nf:
					var an := c1 * (un[i] - u[i]) - (1.0 / (beta * dt)) * v[i] - (1.0 / (2 * beta) - 1.0) * a[i]
					v[i] += dt * ((1.0 - gam) * a[i] + gam * an)
					a[i] = an
					u[i] = un[i]
			for k in nr:
				var f := map[rec[k]]
				var ix := k * (ns + 1) + step
				ru[ix] = u[f] if f >= 0 else 0.0
				rv[ix] = v[f] if f >= 0 else 0.0
				ra[ix] = a[f] if f >= 0 else 0.0
			if snap_every > 0 and step % snap_every == 0:
				snaps.append(scatter.call(u))
		out["rec_u"] = ru
		out["rec_v"] = rv
		out["rec_a"] = ra
		out["snaps"] = snaps
		out["crowd_power"] = cpow
		out["crowd_theta"] = th
		var Mv: PackedFloat64Array = mul.call(M, v)
		var Ku2: PackedFloat64Array = mul.call(K, u)
		var ke := 0.0
		var se := 0.0
		for i in nf:
			ke += 0.5 * v[i] * Mv[i]
			se += 0.5 * u[i] * Ku2[i]
		out["ke_end"] = ke
		out["se_end"] = se
		return out
	out["error"] = "unknown job type"
	return out
