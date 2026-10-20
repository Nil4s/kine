## spin_check.gd - AIRBORNE SPIN CHECK (ROADMAP I43). In flight (both feet off the floor, nothing held) nothing pushes on the body but
## gravity, so (1) the centre of mass follows a parabola, y'' = -g, and (2) the angular momentum H about the COM is conserved. Read
## only: analyze() poses the body and restores it exactly (B.state() before, B.set_state() after); fix() works on a CLONE.
##
## FLIGHT: a run of >= MIN_FLIGHT frames (60 Hz) with no foot down (Balance.read) and no hand/weapon on a surface (HumanLimits.supported),
## the same test Feasible uses. A marked jump ("air" cards) and an unmarked hover are both found.
## VERTICAL: y(t) of the COM (Balance.com) is fitted with c0 + c1 t + c2 t^2 over the flight; a = 2 c2 against -g (9.81). Bar: a/(-g)
## in [0.85, 1.15] (mine; Feasible's own 8 cm parabola band says the same thing in metres). Below = a FLOAT / hang, above = a dive.
## MOMENTUM: the spin the trunk carries at take-off, H0 = I w, w = the pelvis's angular velocity on the first two airborne frames (central
## difference of its rotation at 60 Hz), I = the whole body's inertia about that axis through the COM (HitReaction.pieces: de Leva 1996 masses,
## radii of gyration, parallel axis; isotropic piece inertia, as the Force view). The limbs' own momenta are left out on purpose: an animation
## swings legs and arms freely (a leg extension alone reads ~15 kg m^2/s about the COM), which a real jumper balances with the trunk.
## In flight |I(t) w(t)| is read the same way ("the momentum in flight"); it should stay at H0.
## ROTATION: the trunk (pelvis) turns phi = sum |w_pelvis| dt in flight (twist = its part about the long axis pelvis -> head, the rest
## is somersault / tilt). A rigid body turns at |H0| / I(t), I = the whole body's inertia about the H axis (pieces + parallel axis), so a
## tuck (small I) spins faster for the same H: PHI_ALLOWED = sum |H0| / I(t) dt. Free reorientation without momentum is small: a twist from
## asymmetric arm action (the cat-twist, Kane & Scher 1969; Yeadon 1993, J Biomech 26:1073 "The simulation of aerial movement" parts I-III:
## twisting somersaults are made by tilt plus asymmetric arm/hip action, an athlete with zero twist momentum reorients by tens of degrees,
## not by a half turn) so FREE_DEG is added. FLAG: phi > BAND * PHI_ALLOWED + FREE_DEG. BAND, FREE_DEG are MINE (a heuristic, not a table).
## For scale, a take-off somersault of a gymnast carries H of the order of 50-100 kg m^2/s (Hay 1993; the tables were not opened here).
## CONSERVATION: |I w| in flight must stay near H0: it may reach GROW_K x H0 + GROW_ADD (mine), else the spin is flagged too (when the body turns more
## than FREE_DEG). A spin that starts from rest at take-off and builds up in the air (a smooth ease from 0) fails here; a constant rate passes.
## NOTE the body model's isotropic piece inertia makes I about the twist axis ~4 kg m^2 (a real longitudinal inertia is ~1-1.5), so the H values are
## in the model's units and 2-3x a real twist; the turn allowed (H0 / I integrated) and the growth ratio do not depend on that scale.
## FIX (spin): the needed turn moves into the take-off: the take-off card is pivoted by PIVOT of the turn (the body already turns on the
## floor), the air cards and the landing keep a constant rate (ease "linear") so H exists at take-off and stays. FIX (float): the air
## cards' hips are moved so the COM sits on y = lerp(y0, y1, u) + g/2 (t - T0)(T1 - t) at each card (ease "linear", hold 0).
class_name SpinCheck
extends RefCounted

const FPS := 60.0
const G := 9.81
const MIN_FLIGHT := 6        # frames (0.1 s)
const A_LO := 0.85           # |a| / g bar (mine)
const A_HI := 1.15
const BAND := 1.5            # the turn may be this many times what H0 gives (mine)
const FREE_DEG := 25.0       # degrees of arm / hip reorientation without momentum (mine; Yeadon 1993, Kane & Scher 1969)
const GROW_K := 1.6          # the spin momentum in flight may reach this x the take-off value ... (mine)
const GROW_ADD := 3.0        # ... plus this many kg m^2/s (mine)
const PIVOT := 0.3           # share of the turn moved into the take-off card
const SOURCE := "g = 9.81 m/s^2, H conserved about the COM; reorientation bar from Yeadon 1993 / Kane & Scher 1969 (heuristic constants)"


static func constants_text() -> String:
	return "a/g in %.2f-%.2f, turn <= %.1f x (H0 / I) integrated + %.0f deg free (arm action), take-off pivot %.0f %% of the turn (heuristic constants)" % [A_LO, A_HI, BAND, FREE_DEG, 100.0 * PIVOT]


## world angular velocity (rad/s) track of quaternions at FPS, central difference
static func _omega(q: Array) -> Array:
	var n := q.size()
	var w := []
	for i in n:
		var a: int = maxi(i - 1, 0)
		var b: int = mini(i + 1, n - 1)
		var dt := maxf(float(b - a) / FPS, 1e-9)
		var dq: Quaternion = (q[b] as Quaternion) * (q[a] as Quaternion).inverse()
		if dq.w < 0.0:
			dq = Quaternion(-dq.x, -dq.y, -dq.z, -dq.w)
		var v := Vector3(dq.x, dq.y, dq.z)
		var s := v.length()
		w.append(Vector3.ZERO if s < 1e-9 else v / s * (2.0 * atan2(s, dq.w)) / dt)
	return w


## least squares c0 + c1 t + c2 t^2 -> c2
static func _curv(ts: Array, ys: Array) -> float:
	var n := ts.size()
	var s := [0.0, 0.0, 0.0, 0.0, 0.0]
	var r := [0.0, 0.0, 0.0]
	for i in n:
		var t: float = ts[i]
		var y: float = ys[i]
		var p := 1.0
		for k in 5:
			s[k] += p
			if k < 3:
				r[k] += p * y
			p *= t
	var A := [[s[0], s[1], s[2]], [s[1], s[2], s[3]], [s[2], s[3], s[4]]]
	# Cramer
	var det3 := func(M: Array) -> float:
		return M[0][0] * (M[1][1] * M[2][2] - M[1][2] * M[2][1]) - M[0][1] * (M[1][0] * M[2][2] - M[1][2] * M[2][0]) + M[0][2] * (M[1][0] * M[2][1] - M[1][1] * M[2][0])
	var d: float = det3.call(A)
	if absf(d) < 1e-18:
		return 0.0
	var A2 := [[s[0], s[1], r[0]], [s[1], s[2], r[1]], [s[2], s[3], r[2]]]
	return float(det3.call(A2)) / d


## the sampled clip: per frame the COM (Balance), the pieces' centres, masses, radii of gyration, the pelvis and head positions
static func _sample(S: Scene, B: Body) -> Dictionary:
	var n := int(ceil(S.length() * FPS)) + 1
	var was := S.stepped
	S.stepped = false
	var out := {"n": n, "t": [], "com": [], "air": [], "c": [], "gp": [], "up": [], "m": [], "kl": [], "owner": []}
	var gown := []   # per piece: the owner bone's G per frame
	for i in n:
		var t := minf(float(i) / FPS, S.length())
		S.apply_true(B, t)
		var bal := Balance.read(B)
		var pcs := HitReaction.pieces(B)
		out["t"].append(t)
		out["com"].append(Balance.com(B))
		out["air"].append((bal["down"] as Array).is_empty() and not HumanLimits.supported(B))
		var cs := []
		var gs := []
		for p in pcs:
			cs.append(p["c"])
			gs.append(B.G[p["j"]])
		out["c"].append(cs)
		out["gp"].append(B.G["pelvis"])
		out["up"].append(((B.P["head"] as Vector3) - (B.P["pelvis"] as Vector3)).normalized())
		out["owner"].append(gs)
		if i == 0:
			for p in pcs:
				out["m"].append(float(p["m"]))
				out["kl"].append(float(p["kl"]))
	S.stepped = was
	return out


## per flight: {"t0","t1","i0","i1","T","a","a_ratio","apex","H0","Hmax","drift","phi","twist","tilt","phi_allowed","limit","float","spin","flag","msg","ts","ys","ps"}
## the report: {"ok","flights":[...],"flag","msg","n"}
static func analyze(S: Scene, B: Body) -> Dictionary:
	var out := {"ok": false, "flights": [], "flag": false, "msg": "", "n": 0}
	if S.cards.size() < 2:
		out["msg"] = "needs two cards or more"
		return out
	var keep: Dictionary = B.state()
	var sm := _sample(S, B)
	B.set_state(keep)
	B.fk()
	var n: int = sm["n"]
	var np: int = (sm["m"] as Array).size()
	var mtot := 0.0
	for k in np:
		mtot += float(sm["m"][k])
	var wpel := _omega(sm["gp"])
	var i := 0
	var flights := []
	while i < n:
		if not bool(sm["air"][i]):
			i += 1
			continue
		var a := i
		while i < n and bool(sm["air"][i]):
			i += 1
		var b := i - 1
		if b - a + 1 < MIN_FLIGHT:
			continue
		flights.append(_judge(sm, wpel, a, b, np))
	out["ok"] = true
	out["n"] = n
	out["flights"] = flights
	var bad := flights.filter(func(f): return f["flag"])
	out["flag"] = not bad.is_empty()
	if flights.is_empty():
		out["msg"] = "no flight found: both feet never leave the floor with nothing held"
	elif bad.is_empty():
		out["msg"] = "flights found, count: %d: arc and spin are possible" % flights.size()
	else:
		out["msg"] = " | ".join(bad.map(func(f): return String(f["msg"])))
	return out


static func _judge(sm: Dictionary, wpel: Array, a: int, b: int, np: int) -> Dictionary:
	var f := {"i0": a, "i1": b, "t0": float(sm["t"][a]), "t1": float(sm["t"][b])}
	f["T"] = float(b - a + 1) / FPS
	var ts := []
	var ys := []
	for k in range(a, b + 1):
		ts.append(float(k - a) / FPS)
		ys.append((sm["com"][k] as Vector3).y)
	var c2 := _curv(ts, ys)
	f["a"] = 2.0 * c2
	f["a_ratio"] = -2.0 * c2 / G
	var y_lo := minf(float(ys[0]), float(ys[-1]))
	var y_hi := -INF
	for y in ys:
		y_hi = maxf(y_hi, y)
	f["apex"] = y_hi - y_lo
	f["float"] = float(f["a_ratio"]) < A_LO
	f["dive"] = float(f["a_ratio"]) > A_HI
	# the arc: actual vs the free-fall parabola through the same ends
	var ps := []
	var y0: float = ys[0]
	var y1: float = ys[-1]
	var Tt: float = float(ts[-1])
	for k in ts.size():
		var u: float = float(ts[k]) / maxf(Tt, 1e-6)
		ps.append(lerpf(y0, y1, u) + G / 2.0 * float(ts[k]) * (Tt - float(ts[k])))
	f["ts"] = ts
	f["ys"] = ys
	f["ps"] = ps
	# momentum: the spin the TRUNK carries at take-off, H = I w (I = the whole body's inertia about the spin axis). The limbs' own momenta are
	# left out on purpose: a kinematic animation swings legs and arms freely (a leg extension alone reads 15 kg m^2/s about the COM), which a real
	# jumper balances with the trunk, so the sum of every piece is not the take-off spin a viewer reads.
	var w0: Vector3 = ((wpel[a] as Vector3) + (wpel[mini(a + 1, b)] as Vector3)) * 0.5
	var hd: Vector3 = w0.normalized() if w0.length() > 1e-6 else Vector3.UP
	var H0: Vector3 = w0 * _inertia(sm, a, hd, np)
	var hmax := 0.0
	var drift := 0.0
	for k in range(a, b + 1):
		var wk: Vector3 = wpel[k]
		var hk: Vector3 = wk * _inertia(sm, k, wk.normalized() if wk.length() > 1e-6 else hd, np)
		hmax = maxf(hmax, hk.length())
		drift = maxf(drift, (hk - H0).length())
	f["H0"] = H0.length()
	f["Hmax"] = hmax
	f["drift"] = drift
	var phi := 0.0
	var tw := 0.0
	var allowed := 0.0
	var dt := 1.0 / FPS
	for k in range(a, b + 1):
		var w: Vector3 = wpel[k]
		phi += w.length() * dt
		tw += w.dot(sm["up"][k]) * dt
		allowed += H0.length() / maxf(_inertia(sm, k, hd, np), 1e-6) * dt
	f["phi"] = rad_to_deg(phi)
	f["twist"] = rad_to_deg(tw)
	f["tilt"] = rad_to_deg(sqrt(maxf(phi * phi - tw * tw, 0.0)))
	f["phi_allowed"] = rad_to_deg(allowed)
	f["limit"] = BAND * rad_to_deg(allowed) + FREE_DEG
	# conservation: nothing torques the body, so |I w| may not grow past what the take-off gave (arm and leg action moves it a little: GROW_K, GROW_ADD)
	f["grow"] = hmax > GROW_K * float(f["H0"]) + GROW_ADD
	f["spin"] = float(f["phi"]) > float(f["limit"]) or (bool(f["grow"]) and float(f["phi"]) > FREE_DEG)
	f["flag"] = bool(f["float"]) or bool(f["dive"]) or bool(f["spin"])
	var parts := []
	var when := "flight %.2f-%.2f s (%.2f s)" % [f["t0"], f["t1"], f["T"]]
	if f["float"] or f["dive"]:
		parts.append("%s the COM accelerates at %.1f m/s^2 where gravity gives %.2f m/s^2 (%.0f %% of gravity, bar %.0f to %.0f %%)" % ["floats:" if f["float"] else "dives:", -float(f["a"]), G, 100.0 * float(f["a_ratio"]), 100.0 * A_LO, 100.0 * A_HI])
	if f["spin"]:
		parts.append("turns %.0f deg in the air (%.0f deg of twist, %.0f deg of somersault/tilt); the spin momentum is %.1f kg m^2/s at take-off (allows %.0f deg, + %.0f deg free arm action) and grows to %.1f kg m^2/s in flight, but nothing can add momentum in the air" % [
			f["phi"], absf(float(f["twist"])), f["tilt"], f["H0"], f["phi_allowed"], FREE_DEG, f["Hmax"]])
	f["msg"] = ("%s: %s" % [when, "; ".join(parts)]) if not parts.is_empty() else "%s: a = %.1f m/s^2, H0 %.1f kg m^2/s, turns %.0f deg (allows %.0f deg): possible" % [when, -float(f["a"]), f["H0"], f["phi"], f["limit"]]
	return f


## which cards carry the flight: {"k" take-off card, "l" landing card, "T0", "T1"} from the card times and the flight's frames
static func cards_of(S: Scene, f: Dictionary) -> Dictionary:
	var ts := S.times()
	var k := 0
	for c in S.cards.size():
		if float(ts[c][2]) <= float(f["t0"]) + 1e-4:
			k = c
	var l := S.cards.size() - 1
	for c in range(k + 1, S.cards.size()):
		if float(ts[c][1]) >= float(f["t1"]) - 1e-4:
			l = c
			break
	return {"k": k, "l": l, "T0": float(ts[k][2]), "T1": float(ts[l][1])}


## the fix on a CLONE: {"scene","msg","spin","float","k": changes}. Spin: the take-off pivot + a constant rate. Float: the COM on the parabola.
static func fix(S: Scene, B: Body, rep: Dictionary) -> Dictionary:
	var C := S.clone()
	var keep: Dictionary = B.state()
	var ts := S.times()
	var n_spin := 0
	var n_float := 0
	var notes := []
	for f in rep.get("flights", []):
		if not bool(f["flag"]):
			continue
		var cc := cards_of(S, f)
		var k: int = cc["k"]
		var l: int = cc["l"]
		if l <= k:
			continue
		if bool(f["spin"]):
			B.from_dict(C.cards[k]["pose"])
			B.fk()
			var Rk: Quaternion = B.G["pelvis"]
			B.from_dict(C.cards[l]["pose"])
			B.fk()
			var Rl: Quaternion = B.G["pelvis"]
			var dq := Rl * Rk.inverse()
			if dq.w < 0.0:
				dq = Quaternion(-dq.x, -dq.y, -dq.z, -dq.w)
			var ang := 2.0 * atan2(Vector3(dq.x, dq.y, dq.z).length(), dq.w)
			var ax := Vector3(dq.x, dq.y, dq.z).normalized() if Vector3(dq.x, dq.y, dq.z).length() > 1e-9 else Vector3.UP
			var T0: float = cc["T0"]
			var T1: float = cc["T1"]
			var done := []
			for c in range(k, l):   # k (pivot) and the air cards; the landing card is the target as it stands
				var fr := PIVOT
				if c > k:
					fr = PIVOT + (1.0 - PIVOT) * (float(ts[c][1]) - T0) / maxf(T1 - T0, 1e-6)
				B.from_dict(C.cards[c]["pose"])
				B.fk()
				var want := Quaternion(ax, ang * fr) * Rk
				B.turn_world("pelvis", want * (B.G["pelvis"] as Quaternion).inverse())
				B.fk()
				C.cards[c]["pose"] = B.to_dict()
				if c > k:
					C.cards[c]["ease"] = "linear"
				done.append(c)
			C.cards[l]["ease"] = "linear"
			n_spin += 1
			notes.append("spin %.0f deg: %.0f deg moved into the take-off card %d, then a constant %.0f deg/s through the air" % [rad_to_deg(ang), rad_to_deg(ang) * PIVOT, k + 1, rad_to_deg(ang) * (1.0 - PIVOT) / maxf(T1 - T0, 1e-6)])
		if bool(f["float"]) or bool(f["dive"]):
			var T0b: float = cc["T0"]
			var T1b: float = cc["T1"]
			C.apply_true(B, T0b)
			var y0 := Balance.com(B).y
			C.apply_true(B, T1b)
			var y1 := Balance.com(B).y
			for c in range(k + 1, l):
				var tc := float(ts[c][1])
				var u := (tc - T0b) / maxf(T1b - T0b, 1e-6)
				var want_y := lerpf(y0, y1, u) + G / 2.0 * (tc - T0b) * (T1b - tc)
				B.from_dict(C.cards[c]["pose"])
				B.fk()
				var d := want_y - Balance.com(B).y
				B.offset.y += d
				B.fk()
				C.cards[c]["pose"] = B.to_dict()
				C.cards[c]["ease"] = "linear"
				C.cards[c]["hold"] = 0.0
			C.cards[l]["ease"] = "linear"
			n_float += 1
			notes.append("arc: the COM put on the free-fall parabola at %d cards, apex %s over %.2f s (was %s)" % [l - k - 1, Units.len(G * (T1b - T0b) * (T1b - T0b) / 8.0), T1b - T0b, Units.len(float(f["apex"]))])
	B.set_state(keep)
	B.fk()
	var msg := "nothing to fix: every flight is possible"
	if n_spin + n_float > 0:
		msg = "; ".join(notes)
	return {"scene": C, "spin": n_spin, "float": n_float, "msg": msg}


## the whole body's moment of inertia (kg m^2) about an axis through the COM at frame k: pieces (own k^2 + parallel axis)
static func _inertia(sm: Dictionary, k: int, axis: Vector3, np: int) -> float:
	var I := 0.0
	var com: Vector3 = sm["com"][k]
	for p in np:
		var r: Vector3 = (sm["c"][k][p] as Vector3) - com
		var rp := r - axis * r.dot(axis)
		I += float(sm["m"][p]) * (float(sm["kl"][p]) * float(sm["kl"][p]) + rp.length_squared())
	return I
