## momentum.gd - MOMENTUM LEDGER (ROADMAP I36). For every card transition the whole body's linear momentum P and its angular momentum H
## about the centre of mass going IN (the frames before the card's arrival) against coming OUT (the frames after it), at 60 Hz, and a flag
## when the momentum drops faster than a body can brace without a step, a pivot or a new contact. Read only: analyze() changes no scene
## (it saves and restores the body's state); fix() works on a CLONE and returns it.
##
## THE MASS MODEL is the app's own: HitReaction.pieces (de Leva 1996 segment masses and COM fractions, radii of gyration; the body's own
## mass from the Proportions page), the same pieces the Force view and the hit physics use. P = sum m_k v_k = M dCOM/dt.
## H about the COM = sum m_k (c_k - COM) x (v_k - V) + sum I_k w_k, I_k = m_k (kl_k)^2 isotropic (the Force view's own simplification;
## the gyroscopic term is dropped; stated). Velocities are backward differences of the 60 Hz samples, so a stop that happens in one frame
## reads as one frame.
##
## THE JUDGE is Newton: the net outside force on the body is dP/dt, and a standing person gets it from the floor only: horizontal ground
## force F_h = dP_h/dt, outside torque about the COM tau = dH/dt. The floor can give a bounded amount:
##   BRACE_BW  = 1.5 body weights of horizontal force with the feet where they are (no step). HEURISTIC OF MINE, from the range the
##               braking literature gives for decelerations of sport movements: peak horizontal braking forces of about 1 to 2 body
##               weights in a planted stop or cut (Hewit, Cronin, Button & Hume 2011, Strength Cond J 33(1):47-52 "Understanding
##               deceleration in sport"; Harper & Kiely 2018 review, both cited from memory, not opened here); the friction cone itself
##               allows MU = 1 times the normal force (ForceView.MU), which is ~1 BW standing, more on a loaded plant.
##   STEP_BW   = 3.0 body weights when a foot LANDED in the 0.5 s before the arrival (it lifted >= STEP_LIFT and travelled >= STEP_M): a
##               braking step loads the leg to several body weights (running braking peaks are 2-3 BW horizontal-plus-vertical; mine).
##   The force is read over BRACE_WIN = 0.05 s (3 frames): muscle force cannot build faster than the electromechanical delay of 30-100 ms
##               (Cavanagh & Komi 1979), so a one-frame (17 ms) change is not a thing a body does by bracing; the passive impact peak
##               of a landing is a different mechanism and is not asked of a card that did not land.
##   Torque: the floor gives at most BW x lever: YAW_ARM = 0.25 m (the friction couple of two planted feet), TILT_ARM = 0.15 m (the
##               centre of pressure inside the feet). Doubled with a step (the same reasoning).
## A transition is flagged when the force (or torque) over any 0.05 s window around the arrival EXCEEDS the bar AND the momentum falls
## (the change opposes the incoming momentum). Starts (accelerations) are not flagged: the bar is for stops.
class_name Momentum
extends RefCounted

const HZ := 60.0
const BRACE_BW := 1.5
const STEP_BW := 3.0
const BRACE_WIN := 3          # frames (0.05 s)
const YAW_ARM := 0.25         # m
const TILT_ARM := 0.15        # m
const STEP_LIFT := 0.04       # m, the foot rises at least this
const STEP_M := 0.12          # m (Scene.STEP), the foot travels at least this
const STEP_LOOK := 0.5        # s before the arrival in which a step must have landed
const MIN_P := 5.0            # kg m/s: smaller momenta are not worth a sentence
const GRAV := 9.81
const SOURCE := "Newton: outside force = dP/dt; bar 1.5 BW without a step, 3 BW with one, read over 0.05 s (heuristic from sport deceleration literature)"


static func bar_text() -> String:
	return "bar: %.1f BW of horizontal ground force over %.2f s (%.1f BW if a foot just landed); torque %.2f m x BW yaw, %.2f m x BW tilt (heuristic from braking-force literature: Hewit 2011, Harper & Kiely 2018)" % [BRACE_BW, BRACE_WIN / HZ, STEP_BW, YAW_ARM, TILT_ARM]


## the height of the lowest point of a foot (m)
static func _foot_low(B: Body, sd: String) -> float:
	var y := 1e9
	for part in Balance.FEET[sd]:
		var c: Array = B.cap(part)
		y = minf(y, minf((c[0] as Vector3).y, (c[1] as Vector3).y) - float(B.rad[part]))
	return maxf(y, 0.0)


## the samples of the clip: {"n", "mass", "com": [Vector3], "P": [Vector3] (kg m/s), "H": [Vector3] (kg m^2/s), "foot": [{"_l": Vector3 (x,low,z), "_r": ...}], "fwd": [Vector3 facing]}
static func sample(S: Scene, B: Body) -> Dictionary:
	if S.cards.size() < 2:
		return {}
	var n := int(ceil(S.length() * HZ)) + 1
	var was := S.stepped
	S.stepped = false
	var mk := func(_i: int, t: float) -> Dictionary:
		FrameMemo.pose(S, B, t)
		var pcs := HitReaction.pieces(B)
		var c := []
		var g := []
		for p in pcs:
			c.append(p["c"])
			g.append(B.G[p["j"]])
		var ft := {}
		for sd in ["_l", "_r"]:
			var fp: Vector3 = B.P["foot" + sd]
			ft[sd] = Vector3(fp.x, _foot_low(B, sd), fp.z)
		return {"pcs": pcs, "c": c, "g": g, "ft": ft, "fwd": (B.G["pelvis"] as Quaternion) * Vector3.FORWARD}
	var recs: Array = FrameMemo.frames("ml", S, B, n, HZ, mk)
	S.stepped = was
	var pcs0: Array = recs[0]["pcs"]
	var np := pcs0.size()
	var mass := 0.0
	for p in pcs0:
		mass += float(p["m"])
	var com := []
	for i in n:
		var s := Vector3.ZERO
		for k in np:
			s += float(pcs0[k]["m"]) * (recs[i]["c"][k] as Vector3)
		com.append(s / mass)
	# angular velocity of each piece (backward difference of its orientation)
	var P := []
	var H := []
	var foot := []
	var fwd := []
	for i in n:
		var i0 := maxi(i - 1, 0)
		var dt := maxf(float(i - i0) / HZ, 1e-9)
		var V: Vector3 = ((com[i] as Vector3) - (com[i0] as Vector3)) / dt
		P.append(V * mass)
		var h := Vector3.ZERO
		for k in np:
			var m: float = pcs0[k]["m"]
			var kl: float = pcs0[k]["kl"]
			var v: Vector3 = ((recs[i]["c"][k] as Vector3) - (recs[i0]["c"][k] as Vector3)) / dt
			h += m * ((recs[i]["c"][k] as Vector3) - (com[i] as Vector3)).cross(v - V)
			var dq: Quaternion = (recs[i]["g"][k] as Quaternion) * (recs[i0]["g"][k] as Quaternion).inverse()
			if dq.w < 0.0:
				dq = Quaternion(-dq.x, -dq.y, -dq.z, -dq.w)
			var ax := Vector3(dq.x, dq.y, dq.z)
			var sn := ax.length()
			if sn > 1e-9:
				h += (ax / sn) * (2.0 * atan2(sn, dq.w) / dt) * (m * kl * kl)
		H.append(h)
		foot.append(recs[i]["ft"])
		fwd.append(recs[i]["fwd"])
	return {"n": n, "mass": mass, "com": com, "P": P, "H": H, "foot": foot, "fwd": fwd}


## did a foot land in the STEP_LOOK s before frame ia? (it rose STEP_LIFT above its own lowest and ended STEP_M from where it started)
static func stepped_in(sm: Dictionary, ia: int) -> bool:
	var a := maxi(ia - int(STEP_LOOK * HZ), 0)
	for sd in ["_l", "_r"]:
		var lo := 1e9
		var hi := 0.0
		for k in range(a, ia + 1):
			var y: float = (sm["foot"][k][sd] as Vector3).y
			lo = minf(lo, y)
			hi = maxf(hi, y)
		var p0: Vector3 = sm["foot"][a][sd]
		var p1: Vector3 = sm["foot"][ia][sd]
		if hi - lo >= STEP_LIFT and Vector2(p1.x - p0.x, p1.z - p0.z).length() >= STEP_M:
			return true
	return false


static func _dir_word(sm: Dictionary, ia: int, u: Vector3) -> String:
	var f: Vector3 = sm["fwd"][ia]
	f.y = 0.0
	f = f.normalized()
	var r := f.cross(Vector3.UP)   # to his right-hand side seen from behind: f x up
	var a := u.dot(f)
	var s := u.dot(r)
	if absf(a) >= absf(s):
		return "forward" if a > 0.0 else "backward"
	return "to his right" if s > 0.0 else "to his left"


## the ledger of one clip: {"ok", "n", "mass", "bw" (N), "rows": [{card, t, ia, p_in, p_out (kg m/s, along the incoming horizontal direction), f_bw, bar_bw,
##  frames, stepped, flag, kind: linear / spin, h_in, h_out, tau_ratio, msg}], "flags": [rows flagged], "msg"}
static func analyze(S: Scene, B: Body) -> Dictionary:
	var out := {"ok": false, "rows": [], "flags": [], "msg": "", "n": 0}
	if S.cards.size() < 2:
		out["msg"] = "needs two cards or more"
		return out
	var keep: Dictionary = B.state()
	var sm := sample(S, B)
	B.set_state(keep)
	B.fk()
	var n: int = sm["n"]
	var mass: float = sm["mass"]
	var bw := mass * GRAV
	var ts := S.times()
	var rows := []
	var flags := []
	for i in range(1, S.cards.size()):
		var ta := float(ts[i][1])
		var ia := clampi(int(round(ta * HZ)), 0, n - 1)
		var stepped := false
		var bar := BRACE_BW
		var row := {"card": i, "t": ta, "ia": ia, "stepped": false, "bar_bw": bar, "flag": false, "f_bw": 0.0, "tau_ratio": 0.0, "p_in": 0.0, "p_out": 0.0, "frames": 0, "kind": "", "msg": "", "h_in": 0.0, "h_out": 0.0}
		# every 3-frame window from the start of the move into the card to 2 frames after its arrival (the root finishes its move before the arrival:
		# Scene.LAG staggers the joint levels, so the body stops a little before the card's time). The best window is the one furthest over its bar.
		var best_f := 0.0
		var best_r := 0.0
		var best_s := -1
		var best_t := 0.0
		var best_ts := -1
		var s0 := clampi(int(round(float(ts[i][0]) * HZ)), 0, n - 1)
		for s in range(s0, mini(ia + 3, n - 1 - BRACE_WIN) + 1):
			var st := stepped_in(sm, s + BRACE_WIN)
			var barw := STEP_BW if st else BRACE_BW
			var p0: Vector3 = sm["P"][s]
			var p1: Vector3 = sm["P"][s + BRACE_WIN]
			p0.y = 0.0
			p1.y = 0.0
			var dp := p1 - p0
			if p0.length() >= MIN_P and dp.dot(p0) < 0.0:
				var f := dp.length() * HZ / BRACE_WIN / bw
				if f / barw > best_r:
					best_r = f / barw
					best_f = f
					best_s = s
					stepped = st
					bar = barw
			var h0: Vector3 = sm["H"][s]
			var h1: Vector3 = sm["H"][s + BRACE_WIN]
			var dh := (h1 - h0) * HZ / BRACE_WIN
			if h0.length() >= MIN_P * 0.1 and dh.dot(h0) < 0.0:
				var rt := maxf(absf(dh.y) / (bw * YAW_ARM), Vector2(dh.x, dh.z).length() / (bw * TILT_ARM)) / (2.0 if st else 1.0)
				if rt > best_t:
					best_t = rt
					best_ts = s
					stepped = stepped or st
		row["stepped"] = stepped
		row["bar_bw"] = bar
		row["f_bw"] = best_f
		row["tau_ratio"] = best_t
		var lin := best_f > bar
		var spin := best_t > 1.0
		if best_s >= 0:
			# the window may start a few frames before the drop: move it up to the last frame before momentum starts to fall
			var u0 := Vector3((sm["P"][best_s] as Vector3).x, 0.0, (sm["P"][best_s] as Vector3).z).normalized()
			var pin0 := Vector3((sm["P"][best_s] as Vector3).x, 0.0, (sm["P"][best_s] as Vector3).z).length()
			while best_s + 1 < n - BRACE_WIN and best_s < ia + 2:
				var pn := Vector3((sm["P"][best_s + 1] as Vector3).x, 0.0, (sm["P"][best_s + 1] as Vector3).z).dot(u0)
				if pin0 - pn < 0.05 * pin0:
					best_s += 1
				else:
					break
			var p0: Vector3 = sm["P"][best_s]
			p0.y = 0.0
			var u := p0.normalized()
			var p_in := p0.dot(u)
			var p_out := Vector3((sm["P"][best_s + BRACE_WIN] as Vector3).x, 0.0, (sm["P"][best_s + BRACE_WIN] as Vector3).z).dot(u)
			row["p_in"] = p_in
			row["p_out"] = p_out
			var lost := p_in - p_out
			var fr := BRACE_WIN
			for k in range(1, BRACE_WIN + 1):
				var pk := Vector3((sm["P"][best_s + k] as Vector3).x, 0.0, (sm["P"][best_s + k] as Vector3).z).dot(u)
				if p_in - pk >= 0.8 * lost:
					fr = k
					break
			row["frames"] = fr
			row["dir"] = _dir_word(sm, best_s, u)
			row["t_drop"] = float(best_s) / HZ
		if best_ts >= 0:
			row["h_in"] = (sm["H"][best_ts] as Vector3).length()
			row["h_out"] = (sm["H"][best_ts + BRACE_WIN] as Vector3).length()
			row["t_spin"] = float(best_ts) / HZ
		if lin or spin:
			row["flag"] = true
			row["kind"] = "linear" if lin and (not spin or best_f / bar >= best_t) else "spin"
			var foot_txt := "a foot has just landed, still over the bar" if stepped else "no foot moves"
			if row["kind"] == "linear":
				row["msg"] = "%.2f s: %.0f kg m/s %s drops to %.0f kg m/s in %d frame%s (%.1f BW of ground force over %.2f s, the bar is %.1f BW), %s" % [
					float(row["t_drop"]), row["p_in"], row["dir"], row["p_out"], row["frames"], "" if int(row["frames"]) == 1 else "s", best_f, BRACE_WIN / HZ, bar, foot_txt]
			else:
				row["msg"] = "%.2f s: spin of %.1f kg m^2/s about the centre of mass drops to %.1f kg m^2/s in %.2f s (%.1fx the torque the feet can give), %s" % [
					float(row["t_spin"]), row["h_in"], row["h_out"], BRACE_WIN / HZ, best_t, foot_txt]
			flags.append(row)
		rows.append(row)
	out["ok"] = true
	out["n"] = n
	out["mass"] = mass
	out["bw"] = bw
	out["rows"] = rows
	out["flags"] = flags
	out["msg"] = ("%d of %d transitions drop momentum faster than a body can brace" % [flags.size(), rows.size()]) if not flags.is_empty() else "%d transitions: every stop is one a body can brace" % rows.size()
	return out


## the fix for transition (card) i on a CLONE: a hard ease becomes the smooth one, then the move into the card is stretched until the
## bar passes (at most STRETCH_MAX x). Returns {"scene", "ok", "k", "move0", "move1", "ease0", "msg"}.
const STRETCH := [1.0, 1.15, 1.3, 1.5, 1.75, 2.0, 2.5, 3.0]


static func fix(S: Scene, B: Body, i: int) -> Dictionary:
	var C := S.clone()
	var card: Dictionary = C.cards[i]
	var move0 := S.move_time(i)
	var ease0 := String(card.get("ease", "smooth"))
	var base := analyze(S, B)
	var other: int = base["flags"].filter(func(r): return int(r["card"]) != i).size()
	card.erase("ease")
	card.erase("ease_bias")
	for k in STRETCH:
		card["move"] = snappedf(move0 * float(k), 0.001)
		var rep := analyze(C, B)
		var still: int = rep["flags"].filter(func(r): return int(r["card"]) == i).size()
		var now: int = rep["flags"].size() - still
		if still == 0 and now <= other:
			return {"scene": C, "ok": true, "k": k, "move0": move0, "move1": float(card["move"]), "ease0": ease0, "msg": "card %d: %s, move %.2f s to %.2f s (x%.2f): the stop now takes the time the %.1f BW bar needs; the clip grows %.2f s" % [
				i + 1, ("ease %s becomes the smooth ease" % ease0) if ease0 != "smooth" else "the ease stays smooth", move0, float(card["move"]), float(k), BRACE_BW, C.length() - S.length()]}
	return {"scene": S.clone(), "ok": false, "k": 0.0, "move0": move0, "move1": move0, "ease0": ease0,
		"msg": "card %d: stretching the move up to x%.0f does not clear it; add a step or a pivot card before it by hand" % [i + 1, STRETCH[-1]]}
