## exertion.gd - FATIGUE OF A FIGHTER (ROADMAP I34). How much mechanical work a fighter does over the clip, how tired that makes him,
## and whether he moves like it. Read only: analyze() changes no scene; tire() works on a CLONE and returns it.
##
## WORK: the clip is sampled with the Force view's own inverse dynamics (ForceView.capture / dynamics: Newton-Euler torques at 120 Hz).
## Joint power p_j = M_j . (w_j - w_parent) (the torque the joint must give, times the joint's relative angular velocity; the owner
## pieces' world angular velocities, ForceView._omega). The work a fighter DOES is the integral of the POSITIVE part, per joint, summed over
## the spine, neck, head, arms and legs (negative power is the muscle braking = eccentric work, not counted as spent here: stated).
##
## FATIGUE F in 0..1, a work budget with recovery (the critical-power "W prime balance" idea: Monod & Scherrer 1965; Skiba et al. 2012,
## Med Sci Sports Exerc 44:1526): power above CP drains a budget W' (joules); below CP it refills exponentially. F = 1 - W'bal / W'.
## THE CONSTANTS ARE A HEURISTIC OF MINE: CP, W' are in "sum of joint positive mechanical power", a number no study reports for a
## fighter, tuned so a hard 20-strike exchange (0.55 s a strike, ~14 s, 4.3 kJ of positive work, fists at 10.8 m/s = inside the recorded 7.1-11.95 m/s) ends clearly tired and a 3-strike clip does not (printed by the
## test). TAU_REC = 30 s matches Fatigue.REST_TAU (phosphocreatine resynthesis half-time ~20-30 s; Skiba's own tau is 5-15 min, too slow for a
## clip). The measured size of a tired fighter's loss, -10.3 % punch speed (Sensors 2025, 25(11):3270), is Fatigue.DECLINE_REF;
## TIRE_K below is a stylised push on that (mine) because an animation has to READ.
##
## FLAG (still fresh): strikes = the Timing coach's classifier (TimingCoach.is_strike) with a hand that travels >= MIN_TRAVEL. The peak
## fist speed of each (the faster hand, 3-sample mean). When the last third of the strikes is >= FRESH_RATIO (95 %) of the first third's
## speed while F > TIRED, he is flagged; so is a guard (both hands' height over the shoulders when a non-strike card lands) that has not
## dropped GUARD_DROP (1 cm) between the first and last third. Fewer than MIN_STRIKES strikes: no verdict.
##
## TIRE HIM (tire()): for the cards that START after F > TIRE_FROM (0.5): strike moves x (1 + TIRE_K F), the card after a strike (the
## recover) x (1 + REC_K F), the high guard hands of the other cards lowered GUARD_CM F centimetres (LimbIK on the card's pose).
class_name Exertion
extends RefCounted

const CP := 60.0          # W: sum of joint positive power below which he recovers (heuristic, mine)
const WPRIME := 4000.0     # J above CP he can spend before F = 1 (heuristic, mine)
const TAU_REC := 30.0     # s, refill time constant (Fatigue.REST_TAU)
const SMOOTH_S := 0.25    # s, moving mean of the power before it meets CP
const TIRED := 0.6
const FRESH_RATIO := 0.95
const MIN_STRIKES := 6
const GUARD_DROP := 0.01  # m
const TIRE_FROM := 0.5
const TIRE_K := 0.30      # strike move time x (1 + K F)   (stylised, mine; measured: 10.3 % at full fatigue)
const REC_K := 0.30
const GUARD_CM := 4.0     # cm of guard drop at F = 1 ("a few")
const HIGH_HAND := 0.25   # m above the shoulder line minus this: a hand this far below the shoulders is not a guard
const SOURCE := "work budget with recovery (critical power W' balance: Monod & Scherrer 1965, Skiba 2012); constants are a heuristic"


static func constants_text() -> String:
	return "CP %.0f W, W' %.0f J, recovery tau %.0f s, strikes slow x(1+%.2f F), recovers x(1+%.2f F), guard down %.0f cm F (heuristic constants; speed loss measured 10.3 %%, Sensors 2025)" % [CP, WPRIME, TAU_REC, TIRE_K, REC_K, GUARD_CM]


static func color(f: float) -> Color:
	f = clampf(f, 0.0, 1.0)
	return Tok.c("fv_ok").lerp(Tok.c("fv_mid"), f * 2.0) if f < 0.5 else Tok.c("fv_mid").lerp(Tok.c("fv_hot"), (f - 0.5) * 2.0)


## the fatigue at time t (s) from a report
static func at(rep: Dictionary, t: float) -> float:
	var F: Array = rep.get("F", [])
	if F.is_empty():
		return 0.0
	var i := clampi(int(round(t * ForceView.HZ)), 0, F.size() - 1)
	return float(F[i])


## {"ok", "n", "hz", "P" (W, per sample), "Pw" (J per sample, positive work), "work" (J total), "F" (per sample), "fmax", "strikes": [{card, t, v, F}],
##  "guard": [{card, t, h}], "flag": bool, "fresh": bool, "high": bool, "early", "late" (m/s), "f_late", "msg"}
static func analyze(S: Scene, B: Body) -> Dictionary:
	var out := {"ok": false, "work": 0.0, "fmax": 0.0, "strikes": [], "guard": [], "flag": false, "fresh": false, "high": false, "F": [], "P": [], "Pw": [], "msg": ""}
	if S.cards.size() < 2:
		out["msg"] = "needs two cards or more"
		return out
	var keep: Dictionary = B.state()
	var cap := ForceView.capture(S, B)
	var dyn := ForceView.dynamics(cap)
	var n: int = cap["n"]
	var hz := ForceView.HZ
	var pcs0: Array = cap["pcs0"]
	var idx := {}
	var om := []
	for k in pcs0.size():
		idx[String(pcs0[k]["j"])] = k
		var q := []
		for i in n:
			q.append(cap["gs"][i][k])
		om.append(ForceView._omega(q, n))
	var P := PackedFloat32Array()
	P.resize(n)
	var Pw := PackedFloat32Array()
	Pw.resize(n)
	for j in ForceView.joints():
		if not idx.has(j):
			continue
		var par := String(B.parent[j])
		while par != "" and not idx.has(par):
			par = String(B.parent[par])
		var tv: Array = dyn["tauv"][j]
		for i in n:
			var w: Vector3 = om[idx[j]][i]
			if par != "":
				w -= om[idx[par]][i] as Vector3
			var p := (tv[i] as Vector3).dot(w)
			if p > 0.0:
				P[i] += p
	for i in n:
		Pw[i] = P[i] / hz
	# the budget
	var half := int(SMOOTH_S * hz * 0.5)
	var F := PackedFloat32Array()
	F.resize(n)
	var W := WPRIME
	var dt := 1.0 / hz
	var work := 0.0
	for i in n:
		var s := 0.0
		var c := 0
		for k in range(maxi(0, i - half), mini(n, i + half + 1)):
			s += P[k]
			c += 1
		var ps := s / maxf(c, 1)
		work += Pw[i]
		if ps > CP:
			W = maxf(0.0, W - (ps - CP) * dt)
		else:
			W += (WPRIME - W) * (1.0 - exp(-dt / TAU_REC))
		F[i] = 1.0 - W / WPRIME
	out["ok"] = true
	out["n"] = n
	out["hz"] = hz
	out["P"] = P
	out["Pw"] = Pw
	out["work"] = work
	out["F"] = F
	var fm := 0.0
	for i in n:
		fm = maxf(fm, F[i])
	out["fmax"] = fm
	# strikes and guards
	var ts := S.times()
	var tips: Array = cap["tips"]
	var strikes := []
	var guard := []
	for i in range(1, S.cards.size()):
		var t0 := float(ts[i - 1][2])
		var t1 := float(ts[i][1])
		var a := clampi(int(round(t0 * hz)), 0, n - 1)
		var b := clampi(int(round(t1 * hz)), 0, n - 1)
		if TimingCoach.is_strike(S, i) and b > a:
			var best := 0.0
			var trav := 0.0
			for sd in ["_l", "_r"]:
				trav = maxf(trav, ((tips[b][sd] as Vector3) - (tips[a][sd] as Vector3)).length())
				var sp := []
				for k in range(a, b):
					sp.append(((tips[k + 1][sd] as Vector3) - (tips[k][sd] as Vector3)).length() * hz)
				for k in sp.size():
					var m3 := (float(sp[maxi(k - 1, 0)]) + float(sp[k]) + float(sp[mini(k + 1, sp.size() - 1)])) / 3.0
					best = maxf(best, m3)
			if trav >= TimingCoach.MIN_TRAVEL:
				strikes.append({"card": i, "t": t1, "v": best, "F": float(F[b])})
		elif not TimingCoach.is_strike(S, i):
			guard.append({"card": i, "t": t1, "h": 0.0})
	out["strikes"] = strikes
	_guard_heights(S, B, ts, guard)
	out["guard"] = guard
	var ns := strikes.size()
	if ns < MIN_STRIKES:
		out["msg"] = "%d strikes: too few for a verdict (needs %d)" % [ns, MIN_STRIKES]
		B.set_state(keep)
		B.fk()
		return out
	var third := maxi(ns / 3, 1)
	var e := 0.0
	var l := 0.0
	var fl := 0.0
	for k in third:
		e += float(strikes[k]["v"]) / third
		l += float(strikes[ns - 1 - k]["v"]) / third
		fl += float(strikes[ns - 1 - k]["F"]) / third
	out["early"] = e
	out["late"] = l
	out["f_late"] = fl
	out["fresh"] = fl > TIRED and l >= FRESH_RATIO * e
	# guard: the first and last third of the landing heights
	var ng := guard.size()
	if ng >= 4:
		var g3 := maxi(ng / 3, 1)
		var ge := 0.0
		var gl := 0.0
		for k in g3:
			ge += float(guard[k]["h"]) / g3
			gl += float(guard[ng - 1 - k]["h"]) / g3
		out["guard_drop"] = ge - gl
		out["high"] = fl > TIRED and (ge - gl) < GUARD_DROP
	out["flag"] = bool(out["fresh"]) or bool(out["high"])
	var parts := []
	if out["fresh"]:
		parts.append("late strikes at %.0f %% of the early speed (%.1f vs %.1f m/s) while fatigue is %.2f" % [100.0 * l / e, l, e, fl])
	if out["high"]:
		parts.append("the guard has not dropped (%.1f cm) at fatigue %.2f" % [100.0 * float(out["guard_drop"]), fl])
	out["msg"] = ("STILL FRESH: " + "; ".join(parts)) if out["flag"] else "%d strikes, late %.0f %% of early speed at fatigue %.2f: tires believably" % [ns, 100.0 * l / e, fl]
	B.set_state(keep)
	B.fk()
	return out


## the guards' height: mean of both hands' height above the shoulder line when the card lands (m, negative = below)
static func _guard_heights(S: Scene, B: Body, ts: Array, guard: Array) -> void:
	for g in guard:
		S.apply(B, float(g["t"]))
		B.fk()
		var h := 0.0
		for sd in ["_l", "_r"]:
			h += ((B.P["hand" + sd] as Vector3).y - (B.P["upperarm" + sd] as Vector3).y) * 0.5
		g["h"] = h


## the tire-him plan on a CLONE of S: {"scene", "slowed", "recovers", "guards", "msg", "k": changes[]}; the clone equals S when F never passes TIRE_FROM
static func tire(S: Scene, B: Body, rep: Dictionary) -> Dictionary:
	var C := S.clone()
	var ts := S.times()
	var slowed := 0
	var rec := 0
	var guards := 0
	var worst := 0.0
	var drop_cm := 0.0
	var slow_max := 1.0
	var keep: Dictionary = B.state()
	for i in range(1, S.cards.size()):
		var f := at(rep, float(ts[i - 1][2]))
		if f <= TIRE_FROM:
			continue
		worst = maxf(worst, f)
		if TimingCoach.is_strike(S, i):
			var k := 1.0 + TIRE_K * f
			C.cards[i]["move"] = snappedf(S.move_time(i) * k, 0.001)
			slow_max = maxf(slow_max, k)
			slowed += 1
		else:
			if i >= 2 and TimingCoach.is_strike(S, i - 1):
				C.cards[i]["move"] = snappedf(S.move_time(i) * (1.0 + REC_K * f), 0.001)
				rec += 1
			var d := _lower_guard(C.cards[i], B, GUARD_CM * f * 0.01)
			if d > 0.0:
				guards += 1
				drop_cm = maxf(drop_cm, d * 100.0)
	B.set_state(keep)
	B.fk()
	var msg := "nothing to do: he never gets past fatigue %.1f" % TIRE_FROM
	if slowed + rec + guards > 0:
		msg = "from fatigue %.1f on (worst %.2f): %d strikes slowed up to x%.2f, %d recovers lengthened, %d guards lowered up to %.1f cm; the clip grows %.2f s to %.2f s" % [
			TIRE_FROM, worst, slowed, slow_max, rec, guards, drop_cm, C.length() - S.length(), C.length()]
	return {"scene": C, "slowed": slowed, "recovers": rec, "guards": guards, "drop_cm": drop_cm, "msg": msg}


## lower both hands of a card's pose by d metres when they are guard-high (IK, the body's own limits); returns the largest drop made (m)
static func _lower_guard(card: Dictionary, B: Body, d: float) -> float:
	B.from_dict(card["pose"])
	B.fk()
	var hands := []
	for sd in ["_l", "_r"]:
		var up: float = (B.P["upperarm" + sd] as Vector3).y
		if (B.P["hand" + sd] as Vector3).y > up - HIGH_HAND:
			hands.append(sd)
	if hands.is_empty() or d <= 0.0:
		return 0.0
	var made := 0.0
	for sd in hands:
		var tip: String = "hand" + String(sd)
		var p0: Vector3 = B.P[tip]
		var r := LimbIK.solve(B, tip, p0 - Vector3(0.0, d, 0.0), LimbIK.pole_from_pose(B, tip), B.G[tip])
		made = maxf(made, p0.y - (B.P[tip] as Vector3).y)
		if float(r["miss"]) > d:
			made = 0.0
	card["pose"] = B.to_dict()
	return made
