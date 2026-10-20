## drag_balance.gd - DRAG THE BALANCE (ROADMAP I24). The centre of mass is a marker you can drag: the body rebalances to put
## its COM (Balance.com, de Leva masses) over the point you drag it to, FEET PLANTED.
## UNKNOWNS: the hips' translation (x, z), the hips' height, and the trunk's lean (spine_01 bend and side). Each trial pose
## re-solves both legs onto their planted soles (LimbIK.solve for the ankle point, then the foot and the toe joint take their
## start world turns), so hip, knee and ankle flexion follow from the hips; nothing else is free.
## SOLVE: damped least squares (Gauss-Newton with a numeric Jacobian) on [COM x, COM z, head tilt x, head tilt z]; the pelvis
## columns are cheap, the lean columns are damped hard and the head-tilt rows push the lean back, so the trunk leans only when
## the hips cannot do it alone (the head stays upright). The HEIGHT is a fixed-point (hips follow the COM's y), capped by the
## longest the legs reach (a straight leg stretches the sole off the floor), so a sideways shift lowers the hips a little, as
## it does in people.
## STOPS: the point is clamped to the support polygon's edge (Balance.read poly) and the drag says so; a request the legs or
## an ankle limit cannot hold within SOLE_TOL is cut back along the line from the start (bisection) and says so.
## REAL HUMANS: a lateral weight shift onto one foot moves the pelvis ~ 8-12 cm with little trunk lean (heuristic from stance
## width and the COM-in-pelvis geometry; standing-balance and gait texts, e.g. Winter 1995, "Human balance and posture
## control during standing and walking", Gait & Posture 3:193, give the COP/COM excursion of a single-support weight transfer
## of this order). The test reports the numbers against that band; it is a heuristic comparison, not a fit.
class_name DragBalance
extends RefCounted

const SOLE_TOL := 0.002      # m: a planted sole may move this much (bar: < 2 mm)
const COM_TOL := 0.002       # m: the iteration stops when the COM is this close in x, z
const HEAD_K := 0.03         # m per rad of head tilt: how much a tilted head weighs against a metre of COM miss
const LEAN_DAMP := 2e-4    # m^2/rad^2: the damping on the trunk-lean columns (the hips are free)
const ITERS := 7
const EPS_M := 0.004
const EPS_RAD := 0.02
const LEG_FRAC := 0.999      # of the straight leg: the longest the hips may be above the planted ankle
const FEET := ["foot_l", "foot_r"]


## the start: every joint, the pelvis, the planted soles (the feet on the floor), the support polygon, the head's up
static func begin(B: Body) -> Dictionary:
	var r := Balance.read(B)
	var st := {"ang": B.ang.duplicate(), "offset": B.offset, "com0": r["com"], "poly": r["poly"], "refs": {},
		"head_up0": (B.G["head"] as Quaternion) * Vector3.UP, "down": r["down"]}
	for sd in r["down"]:
		var foot := "foot" + String(sd)
		var ch := LimbIK.chain(B, foot)
		var u0: Vector3 = B.p0[ch[1]] - B.p0[ch[0]]
		var f0: Vector3 = B.p0[foot] - B.p0[ch[1]]
		st["refs"][foot] = {"P": B.P[foot], "pole": LimbIK.pole_from_pose(B, foot), "G": B.G[foot], "Gb": B.G["ball" + String(sd)],
			"ball": "ball" + String(sd), "Pb": B.P["ball" + String(sd)], "Eb": B.E["ball" + String(sd)], "hip": B.P[ch[0]],
			"len": (u0.length() + f0.length()) * LEG_FRAC}
	return st


static func restore(B: Body, st: Dictionary) -> void:
	for j in st["ang"]:
		B.ang[j] = st["ang"][j]
	B.offset = st["offset"]
	B.fk()


## the longest the hips' rise (m, from the start) can be so that both planted legs still reach, at a horizontal shift (dx, dz)
static func _rise_cap(st: Dictionary, dx: float, dz: float) -> float:
	var cap := 0.6
	for foot in st["refs"]:
		var rf: Dictionary = st["refs"][foot]
		var hip: Vector3 = (rf["hip"] as Vector3) + Vector3(dx, 0, dz)
		var a: Vector3 = rf["P"]
		var h2 := (hip.x - a.x) * (hip.x - a.x) + (hip.z - a.z) * (hip.z - a.z)
		var ymax := a.y + sqrt(maxf(float(rf["len"]) * float(rf["len"]) - h2, 0.0))
		cap = minf(cap, ymax - (rf["hip"] as Vector3).y)
	return cap


const SWINGS := [0.0, 4.0, -4.0, 8.0, -8.0, 12.0, -12.0, 16.0, -16.0, 24.0]   # deg


## one leg onto its sole with the knee swung `sw` deg; the sole error (ankle, ball joint, toe tip) and the angles a limit cut
static func _leg(B: Body, st: Dictionary, foot: String, sw: float) -> Dictionary:
	var rf: Dictionary = st["refs"][foot]
	var pole: Vector3 = rf["pole"]
	var ch := LimbIK.chain(B, foot)
	if sw != 0.0:
		var hip: Vector3 = B.P[ch[0]]
		var ax: Vector3 = (rf["P"] as Vector3) - hip
		pole = hip + (pole - hip).rotated(ax.normalized(), deg_to_rad(sw))
	var clamped := []
	var r := LimbIK.solve(B, foot, rf["P"], pole)
	clamped.append_array(r["clamped"])
	B.fk()
	var mid: String = ch[1]
	var vf := B.decompose(foot, ((B.G[mid] as Quaternion).inverse() * (rf["G"] as Quaternion)).normalized())
	var of: Vector3 = B.ang[foot]
	while vf.z - of.z > 180.0:
		vf.z -= 360.0
	while vf.z - of.z < -180.0:
		vf.z += 360.0
	var cf := B.clamp_ang(foot, vf)
	if (cf - vf).length() > 1e-3:
		clamped.append(foot)
	B.ang[foot] = cf
	B.fk()
	var ball: String = rf["ball"]
	var vb := B.decompose(ball, ((B.G[foot] as Quaternion).inverse() * (rf["Gb"] as Quaternion)).normalized())
	var cb := B.clamp_ang(ball, vb)
	if (cb - vb).length() > 1e-3:
		clamped.append(ball)
	B.ang[ball] = cb
	B.fk()
	var err := maxf(((B.P[foot] as Vector3) - (rf["P"] as Vector3)).length(),
		maxf(((B.P[ball] as Vector3) - (rf["Pb"] as Vector3)).length(), ((B.E[ball] as Vector3) - (rf["Eb"] as Vector3)).length()))
	return {"err": err, "clamped": clamped, "sw": sw}



## the pose for u = [dx, dz, rise, lean_bend (rad), lean_side (rad)]: restored, hips moved, trunk leaned, legs on their soles.
## Returns the largest sole error (ankle, ball, toe tip) in metres, and the foot/ball angles the clamps cut in "clamped".
static func pose(B: Body, st: Dictionary, u: Array) -> Dictionary:
	restore(B, st)
	B.offset = (st["offset"] as Vector3) + Vector3(u[0], u[2], u[1])
	for sp in ["spine_01", "spine_02", "spine_03"]:   # the lean is shared by the three back joints (each has only a few degrees)
		var a: Vector3 = st["ang"][sp]
		B.ang[sp] = B.clamp_ang(sp, a + Vector3(rad_to_deg(u[3]), rad_to_deg(u[4]), 0.0) / 3.0)
	B.fk()
	var worst := 0.0
	var clamped := []
	for foot in st["refs"]:
		# the KNEE SWING: the knee turned about the hip-ankle line (where the knee points). Tried from 0 outward, the first that
		# puts the sole back within 0.3 mm with no ankle clamp wins: a far hip over a planted foot needs the knee turned out, as in people
		var best := {}
		for sw in SWINGS:
			var lr := _leg(B, st, foot, sw)
			if best.is_empty() or float(lr["err"]) < float(best["err"]) - 1e-9:
				best = lr
			if float(lr["err"]) <= 0.0003 and (lr["clamped"] as Array).is_empty():
				best = lr
				break
		best = _leg(B, st, foot, best["sw"])   # leave the winner's angles in the body
		clamped.append_array(best["clamped"])
		worst = maxf(worst, float(best["err"]))
	return {"sole": worst, "clamped": clamped}


## how far the hips may travel along `dir` (unit, x,z) with both soles still flat and fixed: the ankles' roll limit (subtalar eversion
## 8 deg here) is what stops a body whose feet stay planted; people let the unloaded foot roll onto its edge, this model's soles do not
static func pelvis_reach(B: Body, st: Dictionary, dir: Vector2, want: float) -> float:
	var lo := 0.0
	var hi := maxf(want, 0.01)
	var top: Dictionary = pose(B, st, [dir.x * hi, dir.y * hi, minf(0.0, _rise_cap(st, dir.x * hi, dir.y * hi)), 0.0, 0.0, 0.0, 0.0])
	if float(top["sole"]) <= SOLE_TOL * 0.75:
		return hi
	for i in 9:
		var f := (lo + hi) * 0.5
		var r: Dictionary = pose(B, st, [dir.x * f, dir.y * f, minf(0.0, _rise_cap(st, dir.x * f, dir.y * f)), 0.0, 0.0, 0.0, 0.0])
		if float(r["sole"]) <= SOLE_TOL * 0.75:
			lo = f
		else:
			hi = f
	return lo


static func _resid(B: Body, st: Dictionary, tx: float, tz: float) -> Array:
	var c := Balance.com(B)
	var hu: Vector3 = (B.G["head"] as Quaternion) * Vector3.UP
	var h0: Vector3 = st["head_up0"]
	return [tx - c.x, tz - c.z, -HEAD_K * (hu.x - h0.x), -HEAD_K * (hu.z - h0.z), c.y]


## solve for the COM at (tx, ty, tz); ty = NAN keeps the COM's start height (lowered only as far as the legs need).
## u0: a warm start. Returns {"u", "sole", "err" (COM x,z miss, m), "clamped"}; the pose is left in B.
static func _solve(B: Body, st: Dictionary, tx: float, tz: float, ty: float, u0: Array, reach := INF) -> Dictionary:
	var u := u0.duplicate() if u0.size() == 7 else [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var want_y: float = (st["com0"] as Vector3).y if is_nan(ty) else ty
	var info := {}
	for it in ITERS:
		u[2] = minf(u[2], _rise_cap(st, u[0], u[1]))
		info = pose(B, st, u)
		var e := _resid(B, st, tx, tz)
		u[2] = clampf(u[2] + (want_y - float(e[4])), -0.6, _rise_cap(st, u[0], u[1]))
		info = pose(B, st, u)
		e = _resid(B, st, tx, tz)
		if absf(e[0]) < COM_TOL and absf(e[1]) < COM_TOL and absf(e[2]) + absf(e[3]) < 0.02:
			break
		# numeric Jacobian over [dx, dz, lean_b, lean_s] (the height is the fixed point above)
		var idx := [0, 1, 3, 4]
		var J := []
		for k in 4:
			var v := u.duplicate()
			var eps := EPS_M if k < 2 else EPS_RAD
			v[idx[k]] += eps
			v[2] = minf(v[2], _rise_cap(st, v[0], v[1]))
			pose(B, st, v)
			var e2 := _resid(B, st, tx, tz)
			J.append([(float(e[0]) - float(e2[0])) / eps, (float(e[1]) - float(e2[1])) / eps, (float(e[2]) - float(e2[2])) / eps, (float(e[3]) - float(e2[3])) / eps])
		# (JtJ + L) du = Jt e   (J is d(residual)/du with the sign of e = target - now, so e - J du = 0)
		var at_reach := Vector2(u[0], u[1]).length() >= reach - 2e-4   # the hips can go no further: the trunk does the rest
		var A := []
		var bvec := []
		for i in 4:
			var row := []
			for j in 4:
				var s := 0.0
				for r in 4:
					s += float(J[i][r]) * float(J[j][r])
				row.append(s + (((1e3 if at_reach else 1e-6) if i < 2 else LEAN_DAMP) if i == j else 0.0))
			A.append(row)
			var sb := 0.0
			for r in 4:
				sb += float(J[i][r]) * float(e[r])
			bvec.append(sb)
		var du := _gauss(A, bvec)
		for k in 4:
			u[idx[k]] += du[k]
		u[3] = clampf(u[3], -0.5, 0.5)
		u[4] = clampf(u[4], -0.5, 0.5)
		var hm := Vector2(u[0], u[1]).length()
		if hm > reach:
			u[0] *= reach / hm
			u[1] *= reach / hm
	u[2] = minf(u[2], _rise_cap(st, u[0], u[1]))
	info = pose(B, st, u)
	var e3 := _resid(B, st, tx, tz)
	info["u"] = u
	info["err"] = Vector2(e3[0], e3[1]).length()
	return info


static func _gauss(A: Array, b: Array) -> Array:
	var n := b.size()
	var M := []
	for i in n:
		var row: Array = (A[i] as Array).duplicate()
		row.append(b[i])
		M.append(row)
	for c in n:
		var p := c
		for r in range(c + 1, n):
			if absf(M[r][c]) > absf(M[p][c]):
				p = r
		var t = M[c]
		M[c] = M[p]
		M[p] = t
		if absf(M[c][c]) < 1e-14:
			continue
		for r in range(c + 1, n):
			var f: float = M[r][c] / M[c][c]
			for k in range(c, n + 1):
				M[r][k] -= f * M[c][k]
	var x := []
	x.resize(n)
	for i in range(n - 1, -1, -1):
		var s: float = M[i][n]
		for k in range(i + 1, n):
			s -= M[i][k] * x[k]
		x[i] = s / M[i][i] if absf(M[i][i]) > 1e-14 else 0.0
	return x


## the point of the polygon's boundary nearest q
static func edge_point(poly: PackedVector2Array, q: Vector2) -> Vector2:
	var best := q
	var bd := INF
	for i in poly.size():
		var c := Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()])
		if c.distance_to(q) < bd:
			bd = c.distance_to(q)
			best = c
	return best


## the marker's state for a request: "inside" / "edge" (within BalanceView.EDGE of it) / "outside" / "air"
static func state_of(st: Dictionary, q: Vector2) -> String:
	if (st["down"] as Array).is_empty():
		return "air"
	var d := Balance.signed_dist(st["poly"], q)
	if d < 0.0:
		return "outside"
	return "edge" if d < BalanceView.EDGE else "inside"


## THE DRAG: the COM asked for at `req` (world point; its y is the height asked for, NAN = leave it). Restores the start, then
## solves. Returns {"state" (of the REQUEST), "stopped" ("" / "edge" / "reach" / "ankle" / "air"), "why" (words), "com", "err",
## "sole" (m), "pelvis" (m moved, Vector3), "lean" (deg, trunk), "head" (deg tilt change), "clamped": [joints a limit cut]}
static func drag(B: Body, st: Dictionary, req: Vector3, warm := []) -> Dictionary:
	if (st["down"] as Array).is_empty():
		restore(B, st)
		return {"state": "air", "stopped": "air", "why": "no foot is on the floor: there is nothing to balance on; put a foot down first", "com": Balance.com(B)}
	var q := Vector2(req.x, req.z)
	var state := state_of(st, q)
	var stopped := ""
	var why := ""
	var tgt := q
	if state == "outside":
		tgt = edge_point(st["poly"], q)
		stopped = "edge"
		why = "stopped at the edge of the feet's support, %.1f cm short of where you dragged; move a foot or drag back inside" % (tgt.distance_to(q) * 100.0)
	var c0: Vector3 = st["com0"]
	var u0 := warm if warm.size() == 7 else [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var want := tgt - Vector2(c0.x, c0.z)
	var reach := INF
	var limited := false
	if want.length() > 0.005:
		reach = pelvis_reach(B, st, want.normalized(), want.length() * 1.3)
		limited = reach < want.length() * 1.3 - 1e-4
	var r := _solve(B, st, tgt.x, tgt.y, req.y, u0, reach)
	r["reach"] = reach if limited else -1.0
	if float(r["sole"]) > SOLE_TOL or float(r["err"]) > 0.01:
		# cut back along the line from the start: the largest fraction whose soles hold and whose COM is where the line says
		var lo := 0.0
		var hi := 1.0
		var best: Dictionary = {}
		for i in 8:
			var f := (lo + hi) * 0.5
			var p := Vector2(c0.x, c0.z).lerp(tgt, f)
			var ty := NAN if is_nan(req.y) else lerpf(c0.y, req.y, f)
			var rr := _solve(B, st, p.x, p.y, ty, [], reach)
			if float(rr["sole"]) <= SOLE_TOL and float(rr["err"]) <= 0.01:
				lo = f
				best = rr
			else:
				hi = f
		if best.is_empty():
			restore(B, st)
			r = _solve(B, st, c0.x, c0.z, NAN, [], reach)
		else:
			var p := Vector2(c0.x, c0.z).lerp(tgt, lo)
			r = _solve(B, st, p.x, p.y, NAN if is_nan(req.y) else lerpf(c0.y, req.y, lo), [], reach)
		var cl: Array = r["clamped"]
		if stopped == "":
			stopped = "ankle" if (cl.has("foot_l") or cl.has("foot_r")) else "reach"
			why = ("stopped: an ankle is at its limit" if stopped == "ankle" else "stopped: the legs cannot reach further with the feet planted") + " (%.1f cm short); widen the stance or drag less" % (float(Vector2(c0.x, c0.z).lerp(tgt, lo).distance_to(q)) * 100.0)
	var c := Balance.com(B)
	var hu: Vector3 = (B.G["head"] as Quaternion) * Vector3.UP
	r["reach"] = reach if limited else -1.0
	r["state"] = state
	r["stopped"] = stopped
	r["why"] = why
	r["com"] = c
	r["pelvis"] = B.offset - (st["offset"] as Vector3)
	r["lean"] = rad_to_deg(sqrt(float(r["u"][3]) * float(r["u"][3]) + float(r["u"][4]) * float(r["u"][4])))
	r["head"] = rad_to_deg(hu.angle_to(st["head_up0"]))
	return r


## the words for the status line
static func words(r: Dictionary) -> String:
	if r.is_empty():
		return ""
	var p: Vector3 = r.get("pelvis", Vector3.ZERO)
	var s := "BALANCE: hips %.1f cm sideways, %.1f cm forward, %.1f cm %s; trunk lean %.1f deg; head tilt %.1f deg" % [
		p.x * 100.0, p.z * 100.0, absf(p.y) * 100.0, "up" if p.y >= 0.0 else "down", float(r.get("lean", 0.0)), float(r.get("head", 0.0))]
	if float(r.get("reach", -1.0)) >= 0.0:
		s += "   (the ankles' roll limit holds the hips to %.1f cm; the trunk leans the rest)" % (float(r["reach"]) * 100.0)
	if String(r.get("stopped", "")) != "":
		s += "   " + String(r["why"])
	return s
