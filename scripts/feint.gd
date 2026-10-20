## feint.gd - FEINT MAKER (ROADMAP Innovations I20). Static, no UI (feint_ui.gd draws it; main.gd owns undo). NOTHING is written to the scene it reads.
## "Make this a feint" turns one strike card (the move into it) into THREE moves:
##   FEINT        starts on the strike's own line (the wind-up card is untouched, so the first part reads identically): the pose the
##                original reaches at the time its tip has gone FRAC (50 %, measured: chord from the move's start to the card's
##                arrival) of the strike's reach. Its move time is that time; its ease_bias is FITTED (search over -1..1) so the tip
##                follows the original's path for the first 40 % of the feint's time (the card's own ease is slower to start than
##                a shorter move would be).
##   RE-CHAMBER   the wind-up pose of the real strike (the same or another side / level), a short move (>= TR_MIN, and twice the
##                real strike so the coach's wind-up : action ratio holds).
##   REAL STRIKE  one of up to three variants, each moved so its arrival tip lands where the original's did (or its mirror / lowered
##                point): OTHER SIDE (the whole pose mirrored, tip aimed at the mirror point across the defender), LOW (the hips
##                dropped LOW_DROP), LIBRARY (another strike card of the same scene, moved to land on the target).
## TIMING. The defender cannot move before the wind-up is readable + REACT (counter.gd; Woodworth & Schlosberg 1954): the feint's stop
## must come at least REACT after the wind-up becomes readable (the move into the wind-up begins), else the stop is HELD until then.
## The real strike and the move after it take the Timing coach's times (TimingCoach.compute, run on the result until it has nothing
## to say about those cards: the fist-speed range 7.1-11.95 m/s peak, Sensors 2025 / Stanley 2018).
## A defender's "counter ..." card (I3) near the original strike is moved so it arrives when the feint stops (it bites on the feint).
class_name Feint
extends RefCounted

const FRAC := 0.5          # the feint stops at this share of the strike's reach
const FRAC_LO := 0.4
const FRAC_HI := 0.6
const MATCH_PART := 0.4    # the feint's tip follows the original for this share of its time
const MATCH_TOL := 0.02    # m
const HIT_TOL := 0.02      # m: the real strike's tip comes this close to the defender's surface
const TR_MIN := 0.12       # s: the shortest re-chamber
const LOW_DROP := 0.25     # m: the LOW variant's hips drop
const REACT := Counter.REACT
const MV := Counter.MV
const NAMES := {"side": "OTHER SIDE", "low": "LOW", "lib": "LIBRARY"}


static func _tip(B: Body, pose: Dictionary, axf: Transform3D, DB: Body, dxf: Transform3D) -> Vector3:
	B.from_dict(pose)
	B.fk()
	return Choreo.tip(B, axf, DB, dxf)["p"]


## the pose dict, mirrored (optional) and the hips moved by d (body space)
static func moved(B: Body, pose: Dictionary, mirror: bool, d: Vector3) -> Dictionary:
	B.from_dict(pose)
	B.fk()
	if mirror:
		B.mirror_pose()
	B.offset += d
	B.fk()
	return B.to_dict()


## the tip at the chord distance from the start: the first path sample that has gone `frac` of the chord to the arrival
static func _chord(P: Dictionary, t_arr: float, frac: float) -> Dictionary:
	var ts: Array = P["ts"]
	var ps: Array = P["p"]
	var p0: Vector3 = ps[0]
	var pa := Counter.path_at(P, t_arr)
	var R := p0.distance_to(pa)
	var tf := t_arr
	for i in ts.size():
		if float(ts[i]) > t_arr + 1e-6:
			break
		if p0.distance_to(ps[i]) >= frac * R:
			tf = float(ts[i])
			break
	return {"R": R, "tf": tf, "frac": p0.distance_to(Counter.path_at(P, tf)) / maxf(R, 1e-6)}


## the largest distance between the new scene's tip and the original's over the first MATCH_PART of the feint (m)
static func match_dev(N: Scene, B: Body, DB: Body, axf: Transform3D, dxf: Transform3D, P: Dictionary, t0: float, Tf: float) -> float:
	var worst := 0.0
	for k in range(0, 9):
		var t := t0 + Tf * MATCH_PART * float(k) / 8.0
		N.apply(B, t)
		worst = maxf(worst, (Choreo.tip(B, axf, DB, dxf)["p"] as Vector3).distance_to(Counter.path_at(P, t)))
	return worst


static func _flags_card(c: Dictionary, mirror: bool, M: Body) -> Dictionary:
	return Scene.mirror_card(c, M) if mirror else c.duplicate(true)


## the whole result for card ci. DS may be null for no counter handling. Returns
## {"ok", "why", "ci", "t0", "t_read", "R", "tf", "frac", "Tf", "bias", "dev", "F" (pose), "path", "options": [...]}
## option: {"kind", "label", "scene" (the attacker's new scene), "def" (the defender's new scene or null), "k_feint", "k_re", "k_real",
##  "real_pose", "move": the real strike's move, "gap" (closest approach of the real strike's tip to the defender, m), "t_stop", "hold"...}
static func make(S: Scene, axf: Transform3D, DS: Scene, dxf: Transform3D, ci: int) -> Dictionary:
	var out := {"ok": false, "why": "", "ci": ci}
	if ci < 2 or ci >= S.cards.size():
		out["why"] = "pick a strike card that has a wind-up card before it (card 3 or later), then try again"
		return out
	var P := Counter.strike(S, axf, DS, dxf, ci)
	if not bool(P["ok"]):
		out["why"] = String(P["why"])
		return out
	var ts := S.times()
	var t0 := float(ts[ci][0])
	var t_arr := float(ts[ci][1])
	var ch := _chord(P, t_arr, FRAC)
	var tf: float = ch["tf"]
	if tf - t0 < TimingCoach.MIN_MOVE:
		out["why"] = "this strike is too short to stop part-way: pick a card with a longer move"
		return out
	var B := Counter.scratch(S)
	var DB := Counter.scratch(DS)
	var M := Counter.scratch(S)
	# the feint pose: the original's own pose at tf
	S.apply(B, tf)   # the body as the scene plays it at tf (feet planted, grounded), not the bare card blend
	B.fk()
	var F := B.to_dict()
	var Tf := snappedf(tf - t0, 0.001)
	var t_read := float(P["t_read"])
	var hold_f := snappedf(maxf(0.0, t_read + REACT - (t0 + Tf)), 0.001)
	var fc := {"name": "feint", "pose": F, "move": Tf, "hold": hold_f}
	# fit the ease so the tip follows the original's path for the first 40 % of the feint
	var T := S.clone()
	T.cards = S.cards.slice(0, ci)
	T.cards.append(fc)
	var best_b := 0.0
	var best_d := INF
	for k in range(-20, 21):
		var b := float(k) / 20.0
		Scene.set_ease_bias(T.cards[ci], b)
		var d := match_dev(T, B, DB, axf, dxf, P, t0, Tf)
		if d < best_d - 1e-9:
			best_d = d
			best_b = b
	Scene.set_ease_bias(fc, best_b)
	out.merge({"ok": true, "t0": t0, "t_arr": t_arr, "t_read": t_read, "R": ch["R"], "tf": tf, "frac": ch["frac"], "Tf": Tf, "bias": best_b, "dev": best_d,
		"F": F, "path": P, "options": []}, true)
	# the real strike's variants
	var qa := Counter.path_at(P, t_arr)
	var qd: Vector3 = dxf.affine_inverse() * qa
	var specs := []
	specs.append({"kind": "side", "mirror": true, "target": dxf * Vector3(-qd.x, qd.y, qd.z), "keep_y": true, "w": ci - 1, "c": ci})
	specs.append({"kind": "low", "mirror": false, "target": qa + Vector3(0, -LOW_DROP, 0), "keep_y": false, "w": ci - 1, "c": ci})
	var near := -1
	for j in range(2, S.cards.size()):
		if j != ci and j != ci + 1 and TimingCoach.is_strike(S, j) and not String(S.cards[j - 1]["name"]).to_lower().contains("feint"):
			if near < 0 or absi(j - ci) < absi(near - ci):
				near = j
	if near >= 0:
		specs.append({"kind": "lib", "mirror": false, "target": qa, "keep_y": true, "w": near - 1, "c": near})
	for sp in specs:
		var o := _option(S, axf, DS, dxf, ci, P, out, fc, sp, B, DB, M)
		if not o.is_empty():
			out["options"].append(o)
	if (out["options"] as Array).is_empty():
		out["ok"] = false
		out["why"] = "no variant of the real strike reaches the defender from here: move the fighters closer or pick another strike"
	return out


static func _option(S: Scene, axf: Transform3D, DS: Scene, dxf: Transform3D, ci: int, P: Dictionary, f: Dictionary, fc: Dictionary, sp: Dictionary, B: Body, DB: Body, M: Body) -> Dictionary:
	var kind := String(sp["kind"])
	var mirror: bool = sp["mirror"]
	var cw: Dictionary = S.cards[int(sp["w"])]
	var cc: Dictionary = S.cards[int(sp["c"])]
	var tip_c := _tip(B, moved(B, cc["pose"], mirror, Vector3.ZERO), axf, DB, dxf)
	var d_h: Vector3 = (sp["target"] as Vector3) - tip_c
	if bool(sp["keep_y"]):
		d_h.y = 0.0
	var d_b: Vector3 = axf.basis.inverse() * d_h
	var C2 := moved(B, cc["pose"], mirror, d_b)
	var R2 := moved(B, cw["pose"], mirror, d_b)
	var nxt: Dictionary = {}
	var cn := int(sp["c"]) + 1
	var has_next := cn < S.cards.size()
	if has_next:
		nxt = _flags_card(S.cards[cn], mirror, M)
		nxt["pose"] = moved(B, S.cards[cn]["pose"], mirror, d_b)
	var re := _flags_card(cw, mirror, M)
	re["pose"] = R2
	re["name"] = "re-chamber"
	re["move"] = TR_MIN
	re["hold"] = 0.0
	var rl := _flags_card(cc, mirror, M)
	rl["pose"] = C2
	rl["name"] = "%s (real, %s)" % [String(S.cards[ci]["name"]), String(NAMES[kind]).to_lower()] if kind != "lib" else "%s (real, library)" % String(cc["name"])
	rl["move"] = float(S.cards[ci]["move"]) if float(S.cards[ci]["move"]) > 0.0 else S.move_time(ci)
	rl["hold"] = float(S.cards[ci]["hold"])
	var N := S.clone()
	var cards := S.cards.slice(0, ci)
	cards.append(fc.duplicate(true))
	cards.append(re)
	cards.append(rl)
	if has_next:
		cards.append(nxt)
	for k in range(ci + 2, S.cards.size()):
		cards.append(S.cards[k].duplicate(true))
	N.cards = cards
	var k_f := ci
	var k_re := ci + 1
	var k_real := ci + 2
	var k_next := ci + 3 if has_next else -1
	# the coach's times for the real strike and the move after it; the re-chamber keeps the 2 : 1 ratio
	N.cards[k_re]["move"] = maxf(TR_MIN, snappedf(TimingCoach.ANTIC_RATIO * float(N.cards[k_real]["move"]), 0.001))
	for it in 3:
		var sugs := TimingCoach.compute(N, B, {})
		var changed := false
		for s in sugs:
			var c := int(s["card"])
			if c == k_real or c == k_next:
				TimingCoach.accept(N, s)
				changed = true
		if not changed:
			break
		N.cards[k_re]["move"] = maxf(TR_MIN, snappedf(TimingCoach.ANTIC_RATIO * float(N.cards[k_real]["move"]), 0.001))
	# where the real strike lands
	var ts2 := N.times()
	var gap := INF
	var n := int(ceil((float(ts2[k_real][1]) - float(ts2[k_real][0])) * 120.0))
	for i in n + 1:
		var t := float(ts2[k_real][0]) + float(i) / 120.0
		t = minf(t, float(ts2[k_real][1]))
		N.apply(B, t)
		DS.apply(DB, t)
		var tp := Choreo.tip(B, axf, DB, dxf)
		gap = minf(gap, float(Choreo.surface_gap(tp["p"], DB, dxf)["gap"]))
	var o := {"kind": kind, "label": String(NAMES[kind]), "scene": N, "k_feint": k_f, "k_re": k_re, "k_real": k_real, "real_pose": C2, "re_pose": R2,
		"gap": gap, "move": float(N.cards[k_real]["move"]), "t_stop": float(ts2[k_f][1]), "t_real": float(ts2[k_real][1]), "shift": d_h}
	# the defender: a counter card near the original strike bites on the feint
	o["def"] = null
	o["counter_from"] = NAN
	o["counter_to"] = NAN
	if DS != null:
		var cv := move_counter(DS, f, float(o["t_stop"]))
		if cv["ok"]:
			o["def"] = cv["scene"]
			o["counter_from"] = cv["from"]
			o["counter_to"] = cv["to"]
	if gap > HIT_TOL:
		o["why"] = "misses the defender by %.0f cm" % (gap * 100.0)
		return {}
	return o


## a "counter ..." card (I3) of the defender, near the original strike, to arrive at t_stop (the feint's stop) instead.
## The card before it holds longer (or shorter), the card itself holds the rest, so every later card keeps its time.
static func move_counter(DS: Scene, f: Dictionary, t_stop: float) -> Dictionary:
	var ts := DS.times()
	var lo := float(f["t_read"])
	var hi := float(f["t_arr"]) + 0.3
	for k in range(1, DS.cards.size()):
		if not String(DS.cards[k]["name"]).to_lower().begins_with("counter "):
			continue
		var arr := float(ts[k][1])
		if arr < lo or arr > hi:
			continue
		var t_new := maxf(t_stop, float(f["t_read"]) + REACT + MV)
		var delta := t_new - arr
		var C := DS.clone()
		var hp := float(C.cards[k - 1]["hold"])
		var hk := float(C.cards[k]["hold"])
		if hp + delta < 0.0 or hk - delta < 0.0:
			continue
		C.cards[k - 1]["hold"] = snappedf(hp + delta, 0.001)
		C.cards[k]["hold"] = snappedf(hk - delta, 0.001)
		return {"ok": true, "scene": C, "card": k, "from": arr, "to": float(C.times()[k][1])}
	return {"ok": false}


## Check on the result: the rulebook's findings on the new scene (red = "FAIL"), and the findings it adds over the original
static func check(N: Scene) -> Array:
	var G := DistanceKeeper.new_body()
	return Rulebook.check(N, G, Rulebook.sample(N, G))


## the red (FAIL) findings of `fl` that the original scene's findings `base` do not already have (by rule and count): what the feint ADDED
static func red_new(fl: Array, base: Array) -> Array:
	var have := {}
	for f in base:
		if f["sev"] == "FAIL":
			have[f["rule"]] = int(have.get(f["rule"], 0)) + 1
	var out := []
	for f in fl:
		if f["sev"] != "FAIL":
			continue
		if int(have.get(f["rule"], 0)) > 0:
			have[f["rule"]] = int(have[f["rule"]]) - 1
		else:
			out.append(f)
	return out
