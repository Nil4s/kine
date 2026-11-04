## rope_sim.gd - CH6 rope: a particle chain with self contact and Coulomb friction (position-based dynamics).
## The solver is C++ (native/src/kine_rope_core.h, class KineRopeNative); this file is the same arithmetic in GDScript, used
## when the DLL does not have the class (or RopeSim.force_gdscript) and for the C++-vs-GDScript bar of tests/ch6_test.gd.
## Same API either way: setup, set_colliders, drive, undrive, set_force, step, positions, max_self_pen, max_col_pen.
## Capsule contacts: rope segment vs rope segment (skip |i-j| < skip) and rope segment vs collider capsule (pegs, a capstan
## cylinder, finger capsules). Friction is accumulated per contact and capped by mu x the normal correction accumulated in the
## substep, so a rope on a fixed cylinder holds T2/T1 = exp(mu theta) (tests/ch6_test.gd, capstan bar).
class_name RopeSim
extends RefCounted

static var force_gdscript := false

var nat: RefCounted = null
# GDScript state (used when nat == null)
var n := 0
var ds := 0.008
var r := 0.004
var mu := 0.4
var kb := 0.01
var grav := 0.0
var damp := 0.995
var alpha := 0.0
var iters := 12
var subs := 8
var skip := 3
var kin := false   # CH6b: a driven particle has inverse mass 0 in every constraint
var selfcol := true   # false: rope-on-rope contact off (planted control)
var adapt := 0.0   # >0: substeps grow until nothing moves more than adapt * r per substep
var max_subs := 96
var used_subs := 0
var wb := PackedFloat32Array()
var mass := 0.0004
var x := PackedVector3Array()
var xo := PackedVector3Array()
var v := PackedVector3Array()
var p := PackedVector3Array()
var tg0 := PackedVector3Array()
var tg1 := PackedVector3Array()
var ext := PackedVector3Array()
var w := PackedFloat32Array()
var drv := PackedByteArray()
var lam_s := PackedFloat32Array()
var cols: Array = []   # [a0, b0, a1, b1, r, mu]
var pairs: Array = []   # [i, j, s, t, lam, fric]
var cpairs: Array = []   # [i, k, s, u, lam, fric]


static func native_ok() -> bool:
	return not force_gdscript and OS.get_environment("KINE_NO_NATIVE") != "1" and NativeExt.ensure("kine_native", "KineRopeNative")


func is_native() -> bool:
	return nat != null


func setup(pts: PackedVector3Array, ds_: float, r_: float, params: Dictionary = {}) -> void:
	if native_ok():
		nat = ClassDB.instantiate("KineRopeNative")
		nat.call("setup", pts, ds_, r_, params)
		n = pts.size()
		return
	nat = null
	n = pts.size()
	ds = ds_
	r = r_
	if params.has("mass"):
		mass = float(params["mass"])
	x = pts.duplicate()
	xo = pts.duplicate()
	p = pts.duplicate()
	tg0 = pts.duplicate()
	tg1 = pts.duplicate()
	v.resize(n)
	ext.resize(n)
	w.resize(n)
	drv.resize(n)
	lam_s.resize(n)
	for i in n:
		w[i] = 1.0 / mass
	wb = w.duplicate()
	for k in params:
		set_param(k, float(params[k]))


func set_param(key: String, val: float) -> void:
	if nat != null:
		nat.call("set_param", key, val)
		return
	match key:
		"mu": mu = val
		"kb": kb = val
		"grav": grav = val
		"damp": damp = val
		"iters": iters = int(val)
		"subs": subs = int(val)
		"skip": skip = int(val)
		"alpha": alpha = val
		"kin": kin = val != 0.0
		"selfcol": selfcol = val != 0.0
		"adapt": adapt = val
		"max_subs": max_subs = int(val)


func set_colliders(a0: PackedVector3Array, b0: PackedVector3Array, a1: PackedVector3Array, b1: PackedVector3Array, radii: PackedFloat32Array, mus: PackedFloat32Array) -> void:
	if nat != null:
		nat.call("set_colliders", a0, b0, a1, b1, radii, mus)
		return
	cols.clear()
	for i in a0.size():
		cols.append([a0[i], b0[i], a1[i], b1[i], radii[i], mus[i] if i < mus.size() else 0.4])


func drive(i: int, from: Vector3, to: Vector3) -> void:
	if nat != null:
		nat.call("drive", i, from, to)
		return
	drv[i] = 1
	tg0[i] = from
	tg1[i] = to


func undrive(i: int) -> void:
	if nat != null:
		nat.call("undrive", i)
		return
	drv[i] = 0


func set_force(i: int, f: Vector3) -> void:
	if nat != null:
		nat.call("set_force", i, f)
		return
	ext[i] = f


func positions() -> PackedVector3Array:
	if nat != null:
		return nat.call("get_x")
	return x


func max_self_pen() -> float:
	if nat != null:
		return nat.call("max_self_pen")
	var m := 0.0
	for i in n - 1:
		for j in range(i + skip, n - 1):
			var st := _closest(x[i], x[i + 1], x[j], x[j + 1])
			var a: Vector3 = x[i] + (x[i + 1] - x[i]) * st[0]
			var b: Vector3 = x[j] + (x[j + 1] - x[j]) * st[1]
			m = maxf(m, 2.0 * r - a.distance_to(b))
	return m


func max_col_pen(skip_driven: bool) -> float:
	if nat != null:
		return nat.call("max_col_pen", skip_driven)
	var m := 0.0
	for c in cols:
		for i in n - 1:
			if skip_driven and (drv[i] != 0 or drv[i + 1] != 0):
				continue
			var st := _closest(x[i], x[i + 1], c[2], c[3])
			var a: Vector3 = x[i] + (x[i + 1] - x[i]) * st[0]
			var b: Vector3 = (c[2] as Vector3) + ((c[3] as Vector3) - (c[2] as Vector3)) * st[1]
			m = maxf(m, r + float(c[4]) - a.distance_to(b))
	return m


func get_used_subs() -> int:
	if nat != null:
		return nat.call("get_used_subs")
	return used_subs


func _frame_subs(dt: float) -> int:
	if adapt <= 0.0:
		return subs
	var md := 0.0
	for i in n:
		var d: float = (tg1[i] - tg0[i]).length() if drv[i] != 0 else v[i].length() * dt
		md = maxf(md, d)
	for c in cols:
		md = maxf(md, maxf(((c[2] as Vector3) - (c[0] as Vector3)).length(), ((c[3] as Vector3) - (c[1] as Vector3)).length()))
	var need := int(ceil(md / (adapt * r)))
	return mini(maxi(need, subs), maxi(max_subs, subs))


func tension() -> float:
	if nat != null:
		return nat.call("get_tension")
	var m := 0.0
	var hh := 1.0 / 30.0 / maxi(used_subs, 1)
	for i in n - 1:
		m = maxf(m, absf(lam_s[i]) / (hh * hh))
	return m


static func _closest(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Array:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var rr := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(rr)
	var s := 0.0
	var t := 0.0
	if a <= 1e-14 and e <= 1e-14:
		return [s, t]
	if a <= 1e-14:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(rr)
		if e <= 1e-14:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var den := a * e - b * b
			if den > 1e-14:
				s = clampf((b * f - c * e) / den, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return [s, t]


func step(dt: float) -> void:
	if nat != null:
		nat.call("step", dt)
		return
	var ns := _frame_subs(dt)
	used_subs = ns
	var h := dt / float(ns)
	var al := alpha / (h * h)
	var save := cols.duplicate(true)
	for sb in ns:
		var f0 := float(sb) / float(ns)
		var f1 := float(sb + 1) / float(ns)
		for i in n:
			w[i] = 0.0 if (kin and drv[i] != 0) else wb[i]
		for i in n:
			xo[i] = x[i]
			if drv[i] != 0:
				p[i] = tg0[i] + (tg1[i] - tg0[i]) * f1
				v[i] = Vector3.ZERO
				continue
			var a: Vector3 = ext[i] * w[i]
			a.y -= grav
			v[i] = (v[i] + a * h) * damp
			p[i] = x[i] + v[i] * h
		for i in n:
			lam_s[i] = 0.0
		if not save.is_empty():
			cols = save.duplicate(true)
			for k in cols.size():
				var c: Array = cols[k]
				var s0: Array = save[k]
				var da: Vector3 = (s0[2] as Vector3) - (s0[0] as Vector3)
				var db: Vector3 = (s0[3] as Vector3) - (s0[1] as Vector3)
				c[0] = (s0[0] as Vector3) + da * f0
				c[1] = (s0[1] as Vector3) + db * f0
				c[2] = (s0[0] as Vector3) + da * f1
				c[3] = (s0[1] as Vector3) + db * f1
		_collect(0.004)
		for it in iters:
			for q in n - 1:
				var i := (n - 2 - q) if (it & 1) == 1 else q
				var d: Vector3 = p[i + 1] - p[i]
				var l := d.length()
				if l < 1e-9:
					continue
				var wsum: float = w[i] + w[i + 1]
				if wsum == 0.0:
					continue
				var C := l - ds
				var dl := (-C - al * lam_s[i]) / (wsum + al)
				lam_s[i] += dl
				var g := d * (1.0 / l)
				p[i] = p[i] - g * (dl * w[i])
				p[i + 1] = p[i + 1] + g * (dl * w[i + 1])
			if kb > 0.0:
				for i in n - 2:
					var d: Vector3 = p[i + 2] - p[i]
					var l := d.length()
					if l < 1e-9:
						continue
					var wsum: float = w[i] + w[i + 2]
					if wsum == 0.0:
						continue
					var C := l - 2.0 * ds
					var cc := -C * kb / wsum
					var g := d * (1.0 / l)
					p[i] = p[i] - g * (cc * w[i])
					p[i + 2] = p[i + 2] + g * (cc * w[i + 2])
			_solve_self()
			_solve_cols()
		for i in n:
			if drv[i] != 0:
				x[i] = p[i]
				continue
			v[i] = (p[i] - xo[i]) * (1.0 / h)
			x[i] = p[i]
		cols = save.duplicate(true)


func _collect(margin: float) -> void:
	pairs.clear()
	var lim := ds + 2.0 * r + margin
	var lim2 := lim * lim
	for i in (n - 1 if selfcol else 0):
		var mi: Vector3 = (p[i] + p[i + 1]) * 0.5
		for j in range(i + skip, n - 1):
			var d: Vector3 = mi - (p[j] + p[j + 1]) * 0.5
			if d.dot(d) > lim2:
				continue
			var st := _closest(p[i], p[i + 1], p[j], p[j + 1])
			pairs.append([i, j, st[0], st[1], 0.0, Vector3.ZERO])
	cpairs.clear()
	for k in cols.size():
		var c: Array = cols[k]
		for i in n - 1:
			var st := _closest(p[i], p[i + 1], c[2], c[3])
			var cs: Vector3 = p[i] + (p[i + 1] - p[i]) * st[0]
			var cc: Vector3 = (c[2] as Vector3) + ((c[3] as Vector3) - (c[2] as Vector3)) * st[1]
			if cs.distance_to(cc) > r + float(c[4]) + margin:
				continue
			cpairs.append([i, k, st[0], st[1], 0.0, Vector3.ZERO])


func _apply(i: int, j: int, s: float, t: float, c: Vector3) -> void:
	p[i] = p[i] + c * (w[i] * (1.0 - s))
	p[i + 1] = p[i + 1] + c * (w[i + 1] * s)
	p[j] = p[j] - c * (w[j] * (1.0 - t))
	p[j + 1] = p[j + 1] - c * (w[j + 1] * t)


func _solve_self() -> void:
	for q in pairs:
		var i: int = q[0]
		var j: int = q[1]
		var st := _closest(p[i], p[i + 1], p[j], p[j + 1])
		var s: float = st[0]
		var t: float = st[1]
		var ca: Vector3 = p[i] + (p[i + 1] - p[i]) * s
		var cb: Vector3 = p[j] + (p[j + 1] - p[j]) * t
		var d := ca - cb
		var dl := d.length()
		var W: float = w[i] * (1.0 - s) * (1.0 - s) + w[i + 1] * s * s + w[j] * (1.0 - t) * (1.0 - t) + w[j + 1] * t * t
		if W == 0.0:
			continue
		var nrm: Vector3
		if dl < 1e-9:
			var ax: Vector3 = p[i + 1] - p[i]
			nrm = Vector3(-ax.y, ax.x, 0.0)
			var nl := nrm.length()
			nrm = nrm * (1.0 / nl) if nl > 1e-9 else Vector3(0, 0, 1)
		else:
			nrm = d * (1.0 / dl)
		var pen := 2.0 * r - dl
		if pen > 0.0:
			q[4] += pen
			_apply(i, j, s, t, nrm * (pen / W))
		if q[4] > 0.0 and mu > 0.0:
			var qs: float = q[2]
			var qt: float = q[3]
			var dA: Vector3 = (p[i] - xo[i]) * (1.0 - qs) + (p[i + 1] - xo[i + 1]) * qs
			var dB: Vector3 = (p[j] - xo[j]) * (1.0 - qt) + (p[j + 1] - xo[j + 1]) * qt
			var rel := dA - dB
			var ut := rel - nrm * rel.dot(nrm)
			var want: Vector3 = (q[5] as Vector3) - ut
			var wl := want.length()
			var cap: float = mu * float(q[4])
			if wl > cap:
				want = want * (cap / wl)
			var dF: Vector3 = want - (q[5] as Vector3)
			q[5] = want
			var Wf: float = w[i] * (1.0 - qs) * (1.0 - qs) + w[i + 1] * qs * qs + w[j] * (1.0 - qt) * (1.0 - qt) + w[j + 1] * qt * qt
			if Wf > 0.0:
				_apply(i, j, qs, qt, dF * (1.0 / Wf))


func _solve_cols() -> void:
	for q in cpairs:
		var c: Array = cols[q[1]]
		var i: int = q[0]
		var st := _closest(p[i], p[i + 1], c[2], c[3])
		var s: float = st[0]
		var u: float = st[1]
		var ca: Vector3 = p[i] + (p[i + 1] - p[i]) * s
		var cc: Vector3 = (c[2] as Vector3) + ((c[3] as Vector3) - (c[2] as Vector3)) * u
		var d := ca - cc
		var dl := d.length()
		var W: float = w[i] * (1.0 - s) * (1.0 - s) + w[i + 1] * s * s
		if W == 0.0:
			continue
		var R: float = r + float(c[4])
		var nrm := Vector3(0, 0, 1) if dl < 1e-9 else d * (1.0 / dl)
		var pen := R - dl
		if pen > 0.0:
			q[4] += pen
			var corr := nrm * (pen / W)
			p[i] = p[i] + corr * (w[i] * (1.0 - s))
			p[i + 1] = p[i + 1] + corr * (w[i + 1] * s)
		var mu_c := minf(mu, float(c[5]))
		if q[4] > 0.0 and mu_c > 0.0:
			var qs: float = q[2]
			var qu: float = q[3]
			var dA: Vector3 = (p[i] - xo[i]) * (1.0 - qs) + (p[i + 1] - xo[i + 1]) * qs
			var colmove: Vector3 = ((c[2] as Vector3) - (c[0] as Vector3)) * (1.0 - qu) + ((c[3] as Vector3) - (c[1] as Vector3)) * qu
			var rel := dA - colmove
			var ut := rel - nrm * rel.dot(nrm)
			var want: Vector3 = (q[5] as Vector3) - ut
			var wl := want.length()
			var cap: float = mu_c * float(q[4])
			if wl > cap:
				want = want * (cap / wl)
			var dF: Vector3 = want - (q[5] as Vector3)
			q[5] = want
			var Wf: float = w[i] * (1.0 - qs) * (1.0 - qs) + w[i + 1] * qs * qs
			if Wf > 0.0:
				var corr2 := dF * (1.0 / Wf)
				p[i] = p[i] + corr2 * (w[i] * (1.0 - qs))
				p[i + 1] = p[i + 1] + corr2 * (w[i + 1] * qs)
