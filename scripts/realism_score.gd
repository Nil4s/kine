## realism_score.gd - REALISM SCORE (ROADMAP I16). ONE number per clip, 0..100, made only from judges the app already has
## (nothing is re-implemented here; the caller hands in what each judge said):
##   LIMITS   Check's findings (Rulebook.check; human-limit rules included): red = MUST FIX (FAIL), yellow = look. A finding flags the
##            WINDOW seconds around its time (0.5 s: ours, about a human reaction time, so one finding is never a single frame).
##   TIMING   the timing coach (TimingCoach.compute): each suggestion flags the card's whole move (a strike outside the recorded range).
##   PUSH     a hit the push-limit table (PushLimits) says should make the struck fighter step or fall, and it did not move: flags
##            PUSH_SPAN s from the hit.
##   FORCE    Force view (ForceView.sample): the runs of frames where some joint's torque is at or past its limit (ratio >= 1).
##   PHYSICS  the physics judge's red spans (MakePhysical.spans) IF a result is cached; otherwise "not judged" and no penalty.
## Each judge's penalty = WEIGHT x (share of the clip it flags), share = seconds flagged (overlaps counted once) / clip seconds.
##   score = max(0, 100 - sum of the penalties), rounded to a whole number for display.
## I45: with 14 judges a bad clip can lose more than 100 points in all, and the displayed score stops at 0. "raw" = 100 - total WITHOUT that floor
## (it can be negative): gains of a fix are read on raw, so a fix on a clip that scores 0 still shows what it removes.
## The displayed score is shown(raw) = 100 x exp(-total / 100): about 100 - total while the total is small (20 -> 82), and it never
## floors, so a clip losing 136 points still reads 26 and every fix still moves it. A gain is shown(after) - shown(before).
## MONOTONE: a penalty is a non-decreasing function of the flagged seconds, and a fix only removes or shrinks flagged items, so a fix
## that removes a flag never lowers the score. WEIGHTS are ours (the points lost if the whole clip were flagged by that judge):
## a red joint-limit break or a physically impossible span is worth the most because no human can do it; a yellow look, a timing
## outside the range or a missing reaction is worth less because a human could do it on a bad day.
class_name RealismScore
extends RefCounted

const W_RED := 100.0
const W_YELLOW := 40.0
const W_TIMING := 60.0
const W_PUSH := 70.0
const W_FORCE := 60.0
const W_PHYS := 100.0
const WINDOW := 0.5
const PUSH_SPAN := 0.6
const JUDGES := ["LIMITS red", "LIMITS yellow", "TIMING", "PUSH", "FORCE", "PHYSICS"]
## I45: the newer physics judges (scripts/judge_suite.gd). Each has a 0..1 sub-score from its own verdicts (1 - share of the things it looked
## at that it flagged); penalty = WEIGHT x (1 - sub); a judge with nothing to judge ABSTAINS (penalty 0, "abstains" in the panel).
## WEIGHTS are ours, the points lost if every item that judge looked at were flagged: physically impossible things weigh most (a flight that
## breaks conservation of momentum, 50), then a body hurt or a human limit broken (breakfall, reaction before it could be seen, a reaction
## in the wrong direction, a stop no body can brace: 40 each), a swing a human arm cannot give or a missing recovery step (30), tiredness that
## does not show (20: it reads as a style choice, not an impossibility).
const W_WEAPON := 30.0
const W_REACTION := 40.0
const W_FATIGUE := 20.0
const W_MOMENTUM := 40.0
const W_RECOVERY := 30.0
const W_SPIN := 50.0
const W_BREAKFALL := 40.0
const W_PRECOG := 40.0
const NEW := ["WEAPON", "REACTION", "FATIGUE", "MOMENTUM", "RECOVERY", "SPIN", "BREAKFALL", "PRECOG"]


static func weight_of(judge: String) -> float:
	return {"LIMITS red": W_RED, "LIMITS yellow": W_YELLOW, "TIMING": W_TIMING, "PUSH": W_PUSH, "FORCE": W_FORCE, "PHYSICS": W_PHYS, "WEAPON": W_WEAPON,
		"REACTION": W_REACTION, "FATIGUE": W_FATIGUE, "MOMENTUM": W_MOMENTUM, "RECOVERY": W_RECOVERY, "SPIN": W_SPIN, "BREAKFALL": W_BREAKFALL, "PRECOG": W_PRECOG}[judge]


## seconds covered by a set of [t0, t1] intervals (overlaps once)
static func union_len(iv: Array) -> float:
	var a := iv.duplicate()
	a.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var tot := 0.0
	var end := -INF
	for p in a:
		var s := maxf(float(p[0]), end)
		if float(p[1]) > s:
			tot += float(p[1]) - s
		end = maxf(end, float(p[1]))
	return tot


## inp: {"findings": [rule findings], "tc": [timing suggestions], "force": ForceView.sample result or {}, "push": [{"t0","t1","text"}],
##       "phys": null (not judged) or [{"t0","t1","reason"}], "cards_fix": {finding index: bool}}.  Returns
## {"score": float, "pen": {judge: penalty}, "share": {judge: share}, "items": [..all..], "reasons": top 3, "phys": bool judged}
static func compute(S: Scene, inp: Dictionary) -> Dictionary:
	var L := maxf(0.05, S.length())
	var items := []
	var ts := S.times()
	var findings: Array = inp.get("findings", [])
	for k in findings.size():
		var f: Dictionary = findings[k]
		var t := float(f["t"])
		var red := String(f["sev"]) == "FAIL"
		items.append({"judge": "LIMITS red" if red else "LIMITS yellow", "t0": maxf(0.0, t - WINDOW * 0.5), "t1": minf(L, t + WINDOW * 0.5),
			"text": "%s: %s" % [f["rule"], String(f["msg"]).get_slice("\n", 0)], "fix": {"kind": "check", "i": k}})
	var tc: Array = inp.get("tc", [])
	for k in tc.size():
		var s: Dictionary = tc[k]
		var c := int(s["card"])
		items.append({"judge": "TIMING", "t0": float(ts[c][0]), "t1": float(ts[c][1]),
			"text": "card %d %s: move %.2f s -> %.2f s" % [c + 1, String(s["kind"]).to_lower(), float(s["from"]), float(s["to"])], "fix": {"kind": "timing", "i": k}})
	for k in (inp.get("push", []) as Array).size():
		var p: Dictionary = inp["push"][k]
		items.append({"judge": "PUSH", "t0": float(p["t0"]), "t1": minf(L, float(p["t1"])), "text": String(p["text"]), "fix": {"kind": "none"}})
	var sm: Dictionary = inp.get("force", {})
	if not sm.is_empty():
		var n := int(sm["n"])
		var hz := float(sm["hz"])
		var red_f := PackedByteArray()
		red_f.resize(n)
		var who := {}
		for j in sm["ratio"]:
			var r: Array = sm["ratio"][j]
			for i in n:
				if float(r[i]) >= ForceView.YELLOW_BELOW:
					red_f[i] = 1
					if not who.has(i) or float(who[i][1]) < float(r[i]):
						who[i] = [j, float(r[i])]
		var i := 0
		while i < n:
			if red_f[i] == 0:
				i += 1
				continue
			var a := i
			var worst: Array = who[i]
			while i < n and red_f[i] == 1:
				if float(who[i][1]) > float(worst[1]):
					worst = who[i]
				i += 1
			items.append({"judge": "FORCE", "t0": float(a) / hz, "t1": minf(L, float(i) / hz),
				"text": "a joint at its torque limit: %s at %.0f %% of it" % [String(worst[0]).replace("_", " "), float(worst[1]) * 100.0], "fix": {"kind": "none"}})
	var judged = inp.get("phys", null) != null
	if judged:
		var ph: Array = inp["phys"]
		for k in ph.size():
			items.append({"judge": "PHYSICS", "t0": float(ph[k]["t0"]), "t1": minf(L, float(ph[k]["t1"])), "text": String(ph[k]["reason"]), "fix": {"kind": "phys", "i": k}})
	var jr: Dictionary = inp.get("judges", {})
	var abstain := {}
	var new_n := {}
	for jd in NEW:
		var r = jr.get(jd)
		if r == null or bool(r["abstain"]):
			abstain[jd] = "nothing to judge" if r == null else String(r["why"])
			continue
		var its: Array = r["items"]
		new_n[jd] = its.size()
		for k in its.size():
			var q: Dictionary = its[k]
			items.append({"judge": jd, "t0": float(q["t0"]), "t1": minf(L, float(q["t1"])), "text": String(q["text"]), "fix": {"kind": "judge", "judge": jd, "i": k}, "ctx": q["ctx"]})
	var pen := {}
	var share := {}
	var total := 0.0
	for jd in NEW:
		var r = jr.get(jd)
		share[jd] = 0.0 if abstain.has(jd) else clampf(1.0 - float(r["sub"]), 0.0, 1.0)
		pen[jd] = weight_of(jd) * float(share[jd])
		total += float(pen[jd])
	for jd in JUDGES:
		var iv := []
		for it in items:
			if it["judge"] == jd:
				iv.append([it["t0"], it["t1"]])
		share[jd] = clampf(union_len(iv) / L, 0.0, 1.0)
		pen[jd] = weight_of(jd) * float(share[jd])
		total += float(pen[jd])
	for it in items:
		it["share"] = (float(it["t1"]) - float(it["t0"])) / L
		it["pen"] = weight_of(it["judge"]) * float(it["share"])
		if new_n.has(it["judge"]):   # a newer judge's penalty is split over its flagged items
			it["pen"] = float(pen[it["judge"]]) / float(maxi(1, int(new_n[it["judge"]])))
	var sorted := items.duplicate()
	sorted.sort_custom(func(x, y): return float(x["pen"]) > float(y["pen"]))
	return {"score": shown(100.0 - total), "raw": 100.0 - total, "pen": pen, "share": share, "items": items, "reasons": sorted.slice(0, 3), "judged": judged, "length": L, "abstain": abstain}


## the displayed 0..100 score of a raw score (100 - total penalty): 100 x exp(-total / 100)
static func shown(raw: float) -> float:
	return 100.0 * exp((raw - 100.0) / 100.0)
