## weapon_torque.gd - WEAPON WEIGHT (ROADMAP I30). For each swing of a held weapon: the torque the arm must supply at the WRIST and the
## SHOULDER, from the clip's own motion, against what a human arm can give; and whether the swing "feels weightless".
##
## THE WEAPON  Body.KINDS gives mass m, length L, "com" (centre of mass, fraction of L from the butt) and "k" (radius of gyration about the centre
##   of mass, fraction of L; a uniform rod is 0.289). So this uses the PROFILE'S numbers, not a uniform rod (the staff's profile IS the uniform
##   rod: com 0.5, k 0.289). About the grip (WeightFeel.GRIP_U from the butt): I_grip = m d^2 + m (k L)^2, d = com L - grip. A test or the
##   caller may pass its own profile ({"mass", "len", "com", "k"}) to ask "what if this were 5 kg".
## THE TORQUE  Newton-Euler for a rigid rod about a point P (P may itself be moving; the equation holds with the absolute acceleration of the
##   centre of mass):   M_P = I_perp (u x u'') + m (c - P) x c''      u the rod's unit axis, c its centre of mass.
##   u x u'' is the angular acceleration perpendicular to the axis (the spin about the rod's own axis is ignored). c'' and u'' are central finite
##   differences of the clip sampled at 60 Hz. GRAVITY IS LEFT OUT: this is the torque the SWING needs (I alpha), as the roadmap asks, not the
##   static load of holding the weapon, so the comparison with the isometric maximum is generous by that static part.
##   Wrist = hand + weapon about the wrist; shoulder = upper arm + forearm + hand + weapon about the shoulder.
## ARM SEGMENTS  Winter, Biomechanics and Motor Control of Human Movement (4th ed. 2009), table 4.1: upper arm 2.8 %, forearm 1.6 %, hand 0.6 %
##   of body mass; centre of mass 43.6 / 43.0 / 50.6 % from the proximal end; radius of gyration about it 0.322 / 0.303 / 0.297 of the length.
##   Body mass BODY_KG = 75 (a typical adult; ours).
## HUMAN MAXIMA  HEURISTICS, rounded, not measured here: isometric wrist torque is of the order of 10-15 N m (flexion about 12, extension about
##   8; Delp, Grierson & Buchanan 1996, J Biomech 29:1371) and isometric shoulder torque 60-100 N m (flexion/abduction, adult men; Otis et
##   al. 1990, J Bone Joint Surg 72-A:1052; Kumar 1996). WRIST_MAX = 12 and SHOULDER_MAX = 75 are ours, from those orders of magnitude. An
##   isometric maximum is the CEILING: a moving muscle gives less (force-velocity), so a swing at the ceiling is already too much.
## WEIGHTLESS  (a) no wind-up: the tip moved back opposite the strike less than WINDUP_MIN of the strike's travel before the strike;
##   (b) no follow-through: after contact the tip carries on along the strike less than FOLLOW_MIN of its travel; (c) an instant stop: the
##   torque in the last quarter of the strike move and the STOP_WIN s after contact is over the maximum AND over 1.5x the swing's earlier peak
##   (a heavy thing does not stop in a frame; when the whole swing is too much that is (a)'s finding, not this one). The fractions are ours
##   (Thomas & Johnston, The Illusion of Life 1981, "Anticipation" and "Follow through" give the order, not the numbers).
class_name WeaponTorque
extends RefCounted

const HZ := 60.0            # sampling of the swing (second differences of a smooth ease need no more; 120 Hz cost 2x for the same peaks to ~2 %)
const BODY_KG := 75.0
const WRIST_MAX := 12.0     # N m, heuristic (see above)
const SHOULDER_MAX := 75.0  # N m, heuristic
const WINDUP_MIN := 0.15
const FOLLOW_MIN := 0.10
const STOP_WIN := 0.25
const LOOK_BACK := 0.8      # s before the strike move in which the wind-up is looked for
const LOOK_FWD := 0.35      # s after contact in which the follow-through is looked for
const WINDUP_K := 0.30      # an added anticipation pose goes this far (of the strike's travel) back past the pre-strike pose
const FOLLOW_K := 0.25      # an added overshoot pose goes this far past the strike pose
const ANTIC_BASE := 0.20    # s: the added anticipation card's move for the reference bat (scaled by (I / I_bat)^0.27, Cross & Bower 2006)
const SEG := {   # mass fraction, com fraction from the proximal end, radius of gyration / length (Winter 2009)
	"upperarm": [0.028, 0.436, 0.322], "lowerarm": [0.016, 0.430, 0.303], "hand": [0.006, 0.506, 0.297]}


## the weapon's numbers: {"mass", "len", "com", "k", "grip", "d", "i_grip", "kind", "src"}; {} for an unknown kind
static func profile(kind: String, override := {}) -> Dictionary:
	if not Body.KINDS.has(kind):
		return {}
	var k: Dictionary = Body.KINDS[kind]
	var p := {"mass": float(k["mass"]), "len": float(k["len"]), "com": float(k["com"]), "k": float(k["k"]), "kind": kind,
		"src": "the %s profile (Body.KINDS mass, centre of mass, radius of gyration)" % kind}
	for key in override:
		p[key] = override[key]
	if override.size() > 0 and not override.has("src"):
		p["src"] = "a %.1f kg weapon with the %s's shape numbers" % [float(p["mass"]), kind]
	var hh: float = k["handle"]
	var hl := hh if hh >= 0.0 else float(k["len"]) + hh
	p["grip"] = minf(WeightFeel.GRIP_U, 0.5 * hl)
	p["d"] = float(p["com"]) * float(p["len"]) - float(p["grip"])
	p["i_grip"] = float(p["mass"]) * (float(p["d"]) * float(p["d"]) + pow(float(p["k"]) * float(p["len"]), 2.0))
	return p


## which swings the scene has: the strike cards that hold a weapon. [{"card", "kind"}]
static func swings(S: Scene, B: Body) -> Array:
	var out := []
	for i in range(1, S.cards.size()):
		if not TimingCoach.is_strike(S, i):
			continue
		var kind := WeightFeel.kind_at(S, i, B)
		if kind == "" or not Body.KINDS.has(kind):
			continue
		out.append({"card": i, "kind": kind})
	return out


## one sample of the arm and the weapon at time t: {"sh", "el", "wr", "gr" (grip), "kn" (knob), "u" (weapon axis), "side"}
static func _pose(S: Scene, B: Body, t: float) -> Dictionary:
	S.apply_true(B, t)
	B.fk()
	var hand := B.wep_hand if B.wep_hand != "" else "hand_r"
	var sfx := hand.substr(4)   # "_r" / "_l"
	return {"sh": B.P["upperarm" + sfx], "el": B.P["lowerarm" + sfx], "wr": B.P["hand" + sfx], "kn": B.wep_point(0.0), "u": B.wep_axis(),
		"gr": B.wep_point(WeightFeel.GRIP_U), "tip": B.wep_point(B.wep_len)}


## the rods of a sample: [{"m", "ip" (inertia about the centre of mass, perpendicular), "c", "u"}] in order upperarm, forearm, hand, weapon
static func _rods(s: Dictionary, prof: Dictionary) -> Array:
	var out := []
	var segs := [["upperarm", s["sh"], s["el"]], ["lowerarm", s["el"], s["wr"]], ["hand", s["wr"], s["gr"]]]
	for sg in segs:
		var f: Array = SEG[sg[0]]
		var a: Vector3 = sg[1]
		var b: Vector3 = sg[2]
		var ln := a.distance_to(b)
		var m: float = f[0] * BODY_KG
		out.append({"m": m, "ip": m * pow(float(f[2]) * ln, 2.0), "c": a.lerp(b, f[1]), "u": (b - a).normalized() if ln > 1e-6 else Vector3.UP})
	var L: float = prof["len"]
	var m: float = prof["mass"]
	out.append({"m": m, "ip": m * pow(float(prof["k"]) * L, 2.0), "c": (s["kn"] as Vector3) + (s["u"] as Vector3) * (float(prof["com"]) * L), "u": s["u"]})
	return out


## the torque curve of the swing between t0 and t1: {"t": [...], "wrist": [...], "shoulder": [...]} (N m, magnitudes, gravity left out)
static func curve(S: Scene, B: Body, prof: Dictionary, t0: float, t1: float) -> Dictionary:
	var h := 1.0 / HZ
	var n := maxi(2, int(ceil((t1 - t0) * HZ)))
	var smp := []
	for k in range(-1, n + 2):
		smp.append(_pose(S, B, maxf(0.0, t0 + k * h)))   # (a sample before t=0 repeats t=0: the clip has no motion before it)
	var ts := []
	var wr := []
	var sh := []
	var rods := smp.map(func(s): return _rods(s, prof))
	for k in range(1, n + 2):
		var r0: Array = rods[k - 1]
		var r1: Array = rods[k]
		var r2: Array = rods[k + 1]
		var tw := Vector3.ZERO
		var tsh := Vector3.ZERO
		for q in r1.size():
			var cdd: Vector3 = ((r2[q]["c"] as Vector3) - 2.0 * (r1[q]["c"] as Vector3) + (r0[q]["c"] as Vector3)) / (h * h)
			var udd: Vector3 = ((r2[q]["u"] as Vector3) - 2.0 * (r1[q]["u"] as Vector3) + (r0[q]["u"] as Vector3)) / (h * h)
			var spin: Vector3 = (r1[q]["u"] as Vector3).cross(udd) * float(r1[q]["ip"])
			var lin: Vector3 = ((r1[q]["c"] as Vector3) - (smp[k]["sh"] as Vector3)).cross(cdd) * float(r1[q]["m"])
			tsh += spin + lin
			if q >= 2:   # the hand and the weapon: about the wrist
				tw += spin + ((r1[q]["c"] as Vector3) - (smp[k]["wr"] as Vector3)).cross(cdd) * float(r1[q]["m"])
		ts.append(t0 + (k - 1) * h)
		wr.append(tw.length())
		sh.append(tsh.length())
	return {"t": ts, "wrist": wr, "shoulder": sh, "tip": smp.slice(1, n + 2).map(func(q): return q["tip"])}   # (tip: one per t)


static func _peak(c: Dictionary, key: String, a: float, b: float) -> Array:   # [peak, t]
	var best := 0.0
	var tb := a
	for k in (c["t"] as Array).size():
		var t: float = c["t"][k]
		if t >= a - 1e-9 and t < b - 1e-9 and float(c[key][k]) > best:
			best = c[key][k]
			tb = t
	return [best, tb]


## the tip at time t from a curve's samples (the nearest one: 1/60 s)
static func _tip_at(c: Dictionary, t: float) -> Vector3:
	var ts: Array = c["t"]
	var k := clampi(roundi((t - float(ts[0])) * HZ), 0, ts.size() - 1)
	return c["tip"][k]


## analyse the swing on strike card `i` of S with weapon profile `prof` ({} = the card's own kind).
## Returns {"card", "kind", "prof", "t0", "arrive", "wrist", "shoulder" (the peak in the swing: [N m, t]), "stop_wrist", "stop_shoulder",
## "ratio" (the larger of wrist/WRIST_MAX and shoulder/SHOULDER_MAX over the swing), "stop_ratio", "windup", "follow" (fractions of the strike's
## travel), "windup_s", "over", "no_windup", "no_follow", "instant_stop", "weightless", "ok"}
static func analyze(S: Scene, B: Body, i: int, prof := {}) -> Dictionary:
	var ts := S.times()
	var kind := WeightFeel.kind_at(S, i, B)
	var p := prof if not prof.is_empty() else profile(kind)
	var arrive: float = ts[i][1]
	var t_start: float = ts[i][0]
	var t0: float = ts[i - 1][0] if i >= 2 else t_start   # the wind-up move is part of the swing
	var t_end := minf(S.length(), arrive + STOP_WIN)
	# ONE pass over the swing's window (the wind-up move, the strike, the follow-through look): the torque curve AND the tip path come from the
	# same posed samples (posing a frame is the cost: ~10 ms)
	var c := curve(S, B, p, maxf(0.0, minf(t0, t_start - LOOK_BACK)), minf(S.length(), arrive + LOOK_FWD))
	var w := _peak(c, "wrist", t0, arrive)
	var sh := _peak(c, "shoulder", t0, arrive)
	# the STOP: the last quarter of the strike move and STOP_WIN after contact (a joint that reaches its target early stops a little before the
	# card's arrival, so the stop is not only after it); the ACCELERATION: everything before that
	var t_late := arrive - 0.25 * (arrive - t_start)
	var sw := _peak(c, "wrist", t_late, t_end + 1e-6)
	var ss := _peak(c, "shoulder", t_late, t_end + 1e-6)
	var ew := _peak(c, "wrist", t0, t_late)
	var es := _peak(c, "shoulder", t0, t_late)
	var ratio := maxf(float(w[0]) / WRIST_MAX, float(sh[0]) / SHOULDER_MAX)
	var stop_ratio := maxf(float(sw[0]) / WRIST_MAX, float(ss[0]) / SHOULDER_MAX)
	var early_ratio := maxf(float(ew[0]) / WRIST_MAX, float(es[0]) / SHOULDER_MAX)
	# wind-up / follow-through, from the weapon tip's path. The swing is an ARC: the chord start->contact is not the direction the tip is MOVING
	# at contact, and follow-through is motion that goes ON the way the tip was heading (measured against the chord it read 0 % with an overshoot card)
	var tip0 := _tip_at(c, t_start)
	var tip1 := _tip_at(c, arrive)
	var d := tip1 - tip0
	var travel := d.length()
	var windup := 0.0
	var follow := 0.0
	if travel > 1e-4:
		var u := d / travel                                   # the strike's opening direction (the wind-up goes against it)
		var vend := tip1 - _tip_at(c, maxf(t_start, arrive - 0.1))
		var uf := vend.normalized() if vend.length() > 1e-5 else u   # its heading at contact
		for k in (c["t"] as Array).size():
			var t: float = c["t"][k]
			if t < t_start - 1e-9:
				windup = maxf(windup, ((c["tip"][k] as Vector3) - tip0).dot(u))
			elif t > arrive + 1e-9:
				follow = maxf(follow, ((c["tip"][k] as Vector3) - tip1).dot(uf))
		windup /= travel
		follow /= travel
	var r := {"card": i, "kind": kind, "prof": p, "t0": t0, "arrive": arrive, "wrist": w, "shoulder": sh, "stop_wrist": sw, "stop_shoulder": ss,
		"ratio": ratio, "stop_ratio": stop_ratio, "early_ratio": early_ratio, "windup": windup, "follow": follow, "windup_s": arrive - t0,
		"travel": travel}
	r["over"] = ratio > 1.0
	r["no_windup"] = windup < WINDUP_MIN
	r["no_follow"] = follow < FOLLOW_MIN
	r["instant_stop"] = stop_ratio > 1.0 and stop_ratio > 1.5 * early_ratio   # the stop is what is too much, not the whole swing
	r["weightless"] = r["no_windup"] or r["no_follow"] or r["instant_stop"]
	r["ok"] = not r["over"] and not r["weightless"]
	return r


## the torque the panel shows for each joint: the larger of the swing's peak and the stop's peak (the same number the bar draws), so the
## bar label and the verdict text can never read two values for one effect (I30: bar 178 N m, text 160 N m = swing-only peak)
static func shown_wrist(r: Dictionary) -> float:
	return maxf(float(r["wrist"][0]), float(r["stop_wrist"][0]))


static func shown_shoulder(r: Dictionary) -> float:
	return maxf(float(r["shoulder"][0]), float(r["stop_shoulder"][0]))


## one-line reading for the panel
static func describe(r: Dictionary) -> String:
	var bits := []
	if r["over"]:
		bits.append("TOO FAST FOR THIS WEAPON: needs %.0f N m at the wrist (max %.0f N m) and %.0f N m at the shoulder (max %.0f N m)" % [
			shown_wrist(r), WRIST_MAX, shown_shoulder(r), SHOULDER_MAX])
	if r["no_windup"]:
		bits.append("no wind-up (the tip goes back %.0f%% of the strike; at least %.0f%%)" % [100.0 * float(r["windup"]), 100.0 * WINDUP_MIN])
	if r["no_follow"]:
		bits.append("no follow-through (the tip goes on %.0f%% past contact; at least %.0f%%)" % [100.0 * float(r["follow"]), 100.0 * FOLLOW_MIN])
	if r["instant_stop"]:
		bits.append("instant stop: stopping needs %.0f N m at the wrist, %.0f N m at the shoulder in the %.2f s after contact" % [
			float(r["stop_wrist"][0]), float(r["stop_shoulder"][0]), STOP_WIN])
	if bits.is_empty():
		return "OK: %.0f N m wrist (max %.0f), %.0f N m shoulder (max %.0f)" % [shown_wrist(r), WRIST_MAX, shown_shoulder(r), SHOULDER_MAX]
	return "; ".join(bits)


## a pose dictionary extrapolated from `anchor` away from `other` by k times their difference (joint angles and the hips offset; the
## weapon dictionary stays the anchor's: it is locked to the hand)
static func _extrapolate(B: Body, anchor: Dictionary, other: Dictionary, k: float) -> Dictionary:
	var out: Dictionary = anchor.duplicate(true)
	var ja: Dictionary = anchor["joints"]
	var jo: Dictionary = other["joints"]
	for j in ja:
		if not jo.has(j) or not B.lim.has(j):
			continue
		var a: Dictionary = ja[j]
		var o: Dictionary = jo[j]
		var v := Vector3(float(a["bend"]) + (float(a["bend"]) - float(o["bend"])) * k, float(a["side"]) + (float(a["side"]) - float(o["side"])) * k,
			float(a["twist"]) + (float(a["twist"]) - float(o["twist"])) * k)
		v = B.clamp_ang(j, v)
		out["joints"][j] = {"bend": snappedf(v.x, 0.01), "side": snappedf(v.y, 0.01), "twist": snappedf(v.z, 0.01)}
	return out


## the repair for swing `r` (an analyze result) of S: a CLONE with it applied (S is not touched).
## {"ok", "scene", "card" (the strike card's index in the clone), "steps": [text], "msg", "after": analyze of the clone, "factor"}
static func fix(S: Scene, B: Body, r: Dictionary) -> Dictionary:
	var res := {"ok": false, "steps": [], "msg": ""}
	if bool(r.get("ok", false)):
		res["msg"] = "this swing is fine: nothing to fix"
		return res
	var C := S.clone()
	var i: int = r["card"]
	var prof: Dictionary = r["prof"]
	var i_bat := float(profile(WeightFeel.REF_KIND)["i_grip"])
	var scale := clampf(pow(float(prof["i_grip"]) / i_bat, WeightFeel.N), 0.7, 2.0)
	var steps: Array = res["steps"]
	var mv_strike := C.move_time(i)
	if bool(r["no_windup"]) and i >= 1:
		var pre: Dictionary = (C.cards[i - 1]["pose"] as Dictionary)
		var back := _extrapolate(B, pre, C.cards[i]["pose"], WINDUP_K)
		var t_a := snappedf(ANTIC_BASE * scale, 0.001)
		C.cards.insert(i, {"name": "anticipation", "pose": back, "move": t_a, "hold": 0.04})
		i += 1
		C.cards[i]["move"] = snappedf(mv_strike * (1.0 + WINDUP_K), 0.001)   # the strike now has further to go: the same speed
		steps.append("add an anticipation card %.2f s (the weapon's inertia scales it x%.2f)" % [t_a, scale])
	if bool(r["no_follow"]):
		var cur: Dictionary = (C.cards[i]["pose"] as Dictionary)
		var over := _extrapolate(B, cur, C.cards[i - 1]["pose"], FOLLOW_K)
		var t_f := snappedf(maxf(0.1, C.move_time(i) * 0.6), 0.001)
		C.cards.insert(i + 1, {"name": "overshoot", "pose": over, "move": t_f, "hold": 0.0})
		steps.append("add an overshoot past contact (%.0f%% further, %.2f s)" % [100.0 * FOLLOW_K, t_f])
	if bool(r["instant_stop"]) or String(C.cards[i].get("ease", "smooth")) in ["in", "linear", "snap"]:
		if C.cards[i].has("ease"):
			C.cards[i].erase("ease")
		steps.append("ease the stop (the strike arrives on the smooth ease, not at full speed)")
	# slow the swing until the arm can do it. Torque goes as 1/T^2 for the same path, so the scale is SOLVED: sqrt(worst ratio) from the swing as it
	# now stands (the original reading when the structure is unchanged, else one reading of the repaired structure), then one verify pass; a second
	# correction only if the verify is still over (holds do not scale, so the law is a little optimistic)
	var after: Dictionary = r
	if not steps.is_empty():   # the structure changed (a card added, the ease changed): read it once
		after = analyze(C, B, i, prof)
	var f_total := 1.0
	for round_ in 2:
		var worst := maxf(float(after["ratio"]), float(after["stop_ratio"]))
		if worst <= 0.98:
			break
		var f := minf(4.0, maxf(1.05, sqrt(worst) * 1.02))
		f_total *= f
		var lo := maxi(1, i - 2)
		var hi := mini(C.cards.size() - 1, i + 1)
		var mvs := {}
		for q in range(lo, hi + 1):
			mvs[q] = C.move_time(q)
		for q in range(lo, hi + 1):
			C.cards[q]["move"] = snappedf(float(mvs[q]) * f, 0.001)
		after = analyze(C, B, i, prof)
	if f_total > 1.0:
		steps.append("slow the swing x%.2f (the torque goes as 1/T^2)" % f_total)
	res["scene"] = C
	res["card"] = i
	res["after"] = after
	res["factor"] = f_total
	res["ok"] = true
	res["msg"] = "%s -> %.0f N m wrist, %.0f N m shoulder (max %.0f / %.0f N m), wind-up %.2f s" % ["; ".join(steps), float(after["wrist"][0]), float(after["shoulder"][0]),
		WRIST_MAX, SHOULDER_MAX, float(after["windup_s"])]
	return res
