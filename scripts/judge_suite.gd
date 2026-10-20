## judge_suite.gd - THE NEWER PHYSICS JUDGES AS REALISM-SCORE COMPONENTS (ROADMAP I45; the score itself: scripts/realism_score.gd).
## Each judge is run through its OWN module (nothing is re-implemented here) and reduced to
##   {"abstain": bool, "why": str, "sub": 0..1, "n": things judged, "bad": things flagged, "items": [{t0, t1, text, ctx}]}.
## SUB-SCORE = 1 - (share of the things that judge looked at that it flagged), so a judge's penalty is WEIGHT x (1 - sub) (RealismScore):
##   WEAPON    I30 weapon_torque.gd   swings of a held weapon; flagged = too much torque for a human arm, or weightless
##   REACTION  I33 reaction_dir.gd    hits on a body part; flagged = wrong direction / rotation / pre-flinch / magnitude
##   FATIGUE   I34 exertion.gd        fighters with >= MIN_STRIKES strikes; flagged = still fresh (0.5 each for speed and guard)
##   MOMENTUM  I36 momentum.gd        card transitions; flagged = a stop no body can brace
##   RECOVERY  I39 recovery.gd        hits; the shove J/M puts the capture point outside the feet and the struck fighter does not step
##                                    (neither foot travels REACT_M = RealismUI.REACT_M in 0.6 s)
##   SPIN      I43 spin_check.gd      flights; flagged = the COM leaves the parabola or the spin breaks conservation
##   BREAKFALL I25 breakfall.gd       falls; a failing landing counts 1, a warning 0.5
##   PRECOG    I31 precog.gd          answered strikes; flagged = the reaction starts before it could be seen, or lands late
## ABSTAIN: a judge with nothing to judge (no weapon swing, no second fighter, no hit, no flight, no fall, too few strikes) says so and
## the score does not move. WEAPON, MOMENTUM, SPIN, BREAKFALL read the hero (the scene on the stage); REACTION, RECOVERY, PRECOG read the
## fighters; FATIGUE reads every fighter.
## CACHE: a judge's answer is kept per scene revision (every fighter's cards, placement and the hero's body); the same cards cost nothing.
## FIX: fix(m, item) rebuilds the judge's own fix on a CLONE and returns {"changes": [{"S": Scene, "cards": Array}], "msg"} (nothing is written).
class_name JudgeSuite
extends RefCounted

const LABEL := {"WEAPON": "Fix the swing", "REACTION": "Fix the reaction", "FATIGUE": "Tire him", "MOMENTUM": "Ease the stop", "RECOVERY": "Add the recovery step",
	"SPIN": "Fix the flight", "BREAKFALL": "Fix the landing", "PRECOG": "Retime the reaction"}
const UNIT := {"WEAPON": "swings", "REACTION": "hits", "FATIGUE": "fighters", "MOMENTUM": "transitions", "RECOVERY": "hits", "SPIN": "flights",
	"BREAKFALL": "falls", "PRECOG": "reactions"}
const SHOVE_MIN_S := 0.6   # s after the hit in which a step must show


static func _fighters(m: Node) -> Array:
	m._actors_sync()
	if m.actors_rt.is_empty():
		return [{"S": m.S, "B": m.B, "name": "fighter 1", "xf": Transform3D.IDENTITY}]
	return m.actors_rt


static func _key(m: Node) -> String:
	var fs := _fighters(m)
	var parts := []
	for f in fs:
		parts.append([(f["S"] as Scene).cards, str(f.get("xf", ""))])
	return var_to_str([parts, m.S.body, m.S.name])


static func _abstain(why: String) -> Dictionary:
	return {"abstain": true, "why": why, "sub": 1.0, "n": 0, "bad": 0, "items": []}


static func _done(n: int, bad_w: float, items: Array, why_none: String) -> Dictionary:
	if n == 0:
		return _abstain(why_none)
	return {"abstain": false, "why": "", "sub": clampf(1.0 - bad_w / float(n), 0.0, 1.0), "n": n, "bad": items.size(), "items": items}


## all judges: {name: result}; cache {name: {"key", "res"}} is filled; lap {name: ms}
static func run(m: Node, cache: Dictionary, lap: Dictionary) -> Dictionary:
	var out := {}
	var key := _key(m)
	var fs := _fighters(m)
	var keeps := fs.map(func(f): return (f["B"] as Body).state())
	var rows_done := false
	var hr := []
	for jd in RealismScore.NEW:
		var c = cache.get(jd)
		if c != null and String(c["key"]) == key:
			out[jd] = c["res"]
			lap[jd] = 0.0
			continue
		var t0 := Time.get_ticks_usec()
		if (jd == "REACTION" or jd == "RECOVERY") and not rows_done:
			hr = _hit_rows(m)
			rows_done = true
		var r: Dictionary
		match jd:
			"WEAPON": r = _weapon(m)
			"REACTION": r = _reaction(hr)
			"FATIGUE": r = _fatigue(m, fs)
			"MOMENTUM": r = _momentum(m)
			"RECOVERY": r = _recovery(m, hr)
			"SPIN": r = _spin(m)
			"BREAKFALL": r = _breakfall(m)
			_: r = _precog(m)
		cache[jd] = {"key": key, "res": r}
		out[jd] = r
		lap[jd] = float(Time.get_ticks_usec() - t0) / 1000.0
	for k in fs.size():
		(fs[k]["B"] as Body).set_state(keeps[k])
		(fs[k]["B"] as Body).fk()
	return out


# ------------------------------------------------------------------------------------------------ the judges

static func _weapon(m: Node) -> Dictionary:
	var S: Scene = m.S
	var sw := WeaponTorque.swings(S, m.B)
	var items := []
	for s in sw:
		var r := WeaponTorque.analyze(S, m.B, int(s["card"]))
		if not bool(r["ok"]):
			items.append({"t0": maxf(0.0, float(r["t0"])), "t1": minf(S.length(), float(r["arrive"]) + 0.2), "text": "swing %d: %s" % [int(s["card"]) + 1, WeaponTorque.describe(r).get_slice("\n", 0)], "ctx": {"r": r}})
	return _done(sw.size(), float(items.size()), items, "no weapon swing")


static func _momentum(m: Node) -> Dictionary:
	var rep := Momentum.analyze(m.S, m.B)
	var rows: Array = rep.get("rows", [])
	var items := []
	for r in rep.get("flags", []):
		items.append({"t0": maxf(0.0, float(r["t"]) - 0.3), "t1": minf(m.S.length(), float(r["t"])), "text": "card %d: %s" % [int(r["card"]) + 1, String(r["msg"])], "ctx": {"card": int(r["card"])}})
	return _done(rows.size(), float(items.size()), items, "fewer than two cards")


static func _spin(m: Node) -> Dictionary:
	var rep := SpinCheck.analyze(m.S, m.B)
	var fl: Array = rep.get("flights", [])
	var items := []
	for f in fl:
		if bool(f["flag"]):
			items.append({"t0": float(f["t0"]), "t1": float(f["t1"]), "text": String(f["msg"]), "ctx": {"rep": rep}})
	return _done(fl.size(), float(items.size()), items, "no flight")


static func _breakfall(m: Node) -> Dictionary:
	var rep := Breakfall.analyze(m.S)
	var falls: Array = rep.get("falls", [])
	var items := []
	var w := 0.0
	for k in falls.size():
		var f: Dictionary = falls[k]
		if String(f["cls"]) == "ok":
			continue
		w += 1.0 if String(f["cls"]) == "fail" else 0.5
		var why := ""
		for ln in BreakfallUI.lines(f):
			if String(ln[0]) != "ok":
				why = String(ln[1])
				break
		items.append({"t0": float(f["t0"]), "t1": minf(m.S.length(), float(f["t1"])), "text": "fall at %.2f s: %s" % [float(f["t_c"]), why], "ctx": {"f": f}})
	return _done(falls.size(), w, items, "no fall")


static func _fatigue(m: Node, fs: Array) -> Dictionary:
	var n := 0
	var w := 0.0
	var items := []
	for k in fs.size():
		var S: Scene = fs[k]["S"]
		var ns := 0
		for c in range(1, S.cards.size()):
			ns += int(TimingCoach.is_strike(S, c))
		if ns < Exertion.MIN_STRIKES:   # too few strikes for a verdict (the dynamics pass is the expensive part): abstain without it
			continue
		var rep := Exertion.analyze(S, fs[k]["B"])
		if not rep.has("early"):
			continue
		n += 1
		var bad := 0.5 * float(bool(rep["fresh"])) + 0.5 * float(bool(rep["high"]))
		if bad > 0.0:
			w += bad
			var st: Array = rep["strikes"]
			var third := maxi(st.size() / 3, 1)
			items.append({"t0": maxf(0.0, float(st[st.size() - third]["t"]) - 0.5), "t1": minf(S.length(), float(st[-1]["t"])),
				"text": "%s: %s" % [String(fs[k].get("name", "fighter")), String(rep["msg"])], "ctx": {"who": k, "rep": rep}})
	return _done(n, w, items, "fewer than %d strikes" % Exertion.MIN_STRIKES)


## ReactionDir.judge for every hit that lands on a body part (the same rows the Reaction direction panel shows)
static func _hit_rows(m: Node) -> Array:
	var rows := []
	if not m._fighters_on():
		return rows
	for h in m.fighter_hits:
		if (h["kind"] != "hit" and h["kind"] != "struck") or Body.is_wep(String(h["on"])):
			continue
		var vk: int = 0 if h["by"] == "other" else int(h["vs"])
		var sk: int = int(h["vs"]) if h["by"] == "other" else 0
		if vk >= m.actors_rt.size() or sk >= m.actors_rt.size():
			continue
		var res := ReactionDir.judge(m.actors_rt[vk]["S"], m.actors_rt[vk]["B"], m.actors_rt[vk]["xf"], h, m.actors_rt[sk]["B"], m.actors_rt[sk]["S"])
		rows.append({"hit": h, "vk": vk, "sk": sk, "res": res})
	return rows


static func _reaction(rows: Array) -> Dictionary:
	var n := 0
	var items := []
	for r in rows:
		var res: Dictionary = r["res"]
		if not bool(res["ok"]):
			continue
		n += 1
		if bool(res["bad"]):
			var t := float(res["t"])
			items.append({"t0": maxf(0.0, t - 0.1), "t1": t + 0.3, "text": "%s  [%s]" % [ReactionDir.line(res), ", ".join(res["flags"])], "ctx": {"row": r}})
	return _done(n, float(items.size()), items, "no hit lands on a body part")


static func _card_at(S: Scene, t: float) -> int:
	var ts := S.times()
	var best := 0
	var bd := INF
	for c in ts.size():
		var d := absf(float(ts[c][1]) - t)
		if d < bd:
			bd = d
			best = c
	return best


static func _recovery(m: Node, rows: Array) -> Dictionary:
	var n := 0
	var items := []
	for r in rows:
		var res: Dictionary = r["res"]
		if not bool(res["ok"]):
			continue
		var Ss: Scene = m.actors_rt[r["sk"]]["S"]
		var Bs: Body = m.actors_rt[r["sk"]]["B"]
		var t := float(res["t"])
		Ss.apply(Bs, t)
		Bs.fk()
		var J: Vector3 = res["J"]
		var dir := rad_to_deg(atan2(J.x, J.z) - Recovery.heading(Bs))
		var speed := float(res["Jn"]) / maxf(float(res["M"]), 1e-9)   # the shove the blow gives (m/s)
		var rd := Recovery.read(Bs, dir, speed)
		if not bool(rd["ok"]):
			continue
		n += 1
		if String(rd["verdict"]) == "hold":
			continue
		var f0 := {"_l": (Bs.P["foot_l"] as Vector3), "_r": (Bs.P["foot_r"] as Vector3)}
		Ss.apply(Bs, minf(Ss.length(), t + SHOVE_MIN_S))
		Bs.fk()
		var tr := 0.0
		for sd in ["_l", "_r"]:
			var d3: Vector3 = (Bs.P["foot" + sd] as Vector3) - (f0[sd] as Vector3)
			tr = maxf(tr, Vector2(d3.x, d3.z).length())
		if tr < RealismUI.REACT_M:
			items.append({"t0": t, "t1": minf(Ss.length(), t + SHOVE_MIN_S), "text": "hit at %.2f s shoves the struck body at %.2f m/s: the capture point is %.1f cm outside the feet (%s needed, %.0f cm) but no foot moves more than %.0f cm" % [
				t, speed, -float(rd["margin"]) * 100.0, String(rd["verdict"]), float(rd["step"]) * 100.0, tr * 100.0], "ctx": {"sk": int(r["sk"]), "t": t, "dir": dir, "speed": speed}})
	return _done(n, float(items.size()), items, "no hit to answer with a step")


static func _precog(m: Node) -> Dictionary:
	if not m._fighters_on():
		return _abstain("needs a second fighter")
	var rep := Precog.analyze(m.actors_rt.map(func(a): return a["S"]), m.actors_rt.map(func(a): return String(a["name"])))
	var its: Array = rep.get("items", [])
	var items := []
	for it in its:
		if String(it["status"]) != "ok":
			items.append({"t0": float(it["t0"]), "t1": float(it["t1"]), "text": String(it["text"]), "ctx": {"it": it}})
	return _done(its.size(), float(items.size()), items, "no strike is answered")


# ------------------------------------------------------------------------------------------------ the fixes

static func _chg(S: Scene, nS: Scene) -> Dictionary:
	return {"S": S, "cards": nS.cards.duplicate(true)}


## the judge's own fix for one item, on clones: {"changes": [{"S", "cards"}], "msg"} or {} when it has none
static func fix(m: Node, it: Dictionary) -> Dictionary:
	var jd := String(it["fix"]["judge"])
	var ctx: Dictionary = it["ctx"]
	var S: Scene = m.S
	var B: Body = m.B
	var keep := B.state()
	var out := {}
	match jd:
		"MOMENTUM":
			var p := Momentum.fix(S, B, int(ctx["card"]))
			if bool(p["ok"]):
				out = {"changes": [_chg(S, p["scene"])], "msg": String(p["msg"])}
		"WEAPON":
			var p := WeaponTorque.fix(S, B, ctx["r"])
			if bool(p["ok"]):
				out = {"changes": [_chg(S, p["scene"])], "msg": String(p["msg"])}
		"SPIN":
			var p := SpinCheck.fix(S, B, ctx["rep"])
			if int(p["spin"]) + int(p["float"]) > 0:
				out = {"changes": [_chg(S, p["scene"])], "msg": String(p["msg"])}
		"BREAKFALL":
			var f: Dictionary = ctx["f"]
			var p: Dictionary
			if String(f["a"]) != "ok":
				p = Breakfall.tuck(S, f)
			elif String(f["b"]) != "ok":
				p = Breakfall.slap(S, f)
			else:
				p = Breakfall.roll(S, f)
			if bool(p["ok"]):
				out = {"changes": [_chg(S, p["scene"])], "msg": String(p["msg"])}
		"FATIGUE":
			var fs := _fighters(m)
			var w := int(ctx["who"])
			var p := Exertion.tire(fs[w]["S"], fs[w]["B"], ctx["rep"])
			if p.has("scene") and p["scene"] != null:
				out = {"changes": [_chg(fs[w]["S"], p["scene"])], "msg": String(p["msg"])}
		"REACTION":
			var r: Dictionary = ctx["row"]
			var a: Dictionary = m.actors_rt[r["vk"]]
			var p := ReactionDir.fix(a["S"], a["B"], a["xf"], r["hit"], m.actors_rt[r["sk"]]["B"], r["res"], m.actors_rt[r["sk"]]["S"])
			if bool(p["ok"]):
				out = {"changes": [_chg(a["S"], p["scene"])], "msg": String(p["msg"])}
		"RECOVERY":
			var Ss: Scene = m.actors_rt[int(ctx["sk"])]["S"]
			var p := Recovery.plan(Ss, _card_at(Ss, float(ctx["t"])), float(ctx["dir"]), float(ctx["speed"]))
			if bool(p.get("ok", false)):
				out = {"changes": [_chg(Ss, p["scene"])], "msg": String(p["msg"])}
		"PRECOG":
			var p := Precog.fix(m.actors_rt.map(func(a): return a["S"]), m.actors_rt.map(func(a): return String(a["name"])), ctx["it"])
			if bool(p.get("ok", false)):
				var ch := []
				for w in p["scenes"]:
					ch.append(_chg(m.actors_rt[w]["S"], p["scenes"][w]))
				out = {"changes": ch, "msg": String(p["msg"])}
	B.set_state(keep)
	B.fk()
	return out
