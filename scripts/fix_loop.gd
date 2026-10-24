## fix_loop.gd - FIX UNTIL IT PASSES (docs/INNOVATIONS.md N005). One call runs the fixes Kine already has, in order of their
## predicted gain, until every saved assertion passes and the realism score is at or over a bar, or no fix helps any more,
## or a hard cap on steps is reached; then it reports each step, what still fails and why it stopped.
## NOTHING IS JUDGED HERE THAT THE APP DOES NOT ALREADY JUDGE; this file only orders, applies and guards:
##   the score      the I16 realism score exactly as the "Realism score" command makes it (RealismUI.refresh: Check with the
##                  human limits, the timing coach, push limits, Force view, the I45 judges). The bar is on the displayed
##                  0..100 score (RealismScore.shown); the guard compares "raw" (100 - the total penalty), the same order.
##   the fixes      the fixable reasons RealismUI.biggest_gain walks (a Check finding with a Fixer label, a timing-coach
##                  suggestion, an I45 judge's own fix), the MAX_CAND largest by penalty, each with its PREDICTED gain from
##                  RealismUI.gain_of (the fix played on a copy and scored). Applied exactly as gain_of predicted it:
##                  Check -> Fixer.propose (the edit serve's `fix=K` makes through Fixer.apply), timing -> TimingCoach.accept
##                  (the Accept button), judge -> JudgeSuite.fix's cards (the panel's Fix).
##   the step words SceneBrief._reasons (N011): the serve step that makes the same edit (`fix=K` / `retime=N-N:pct`) or why
##                  there is none, so an agent can redo or skip a step by hand.
##   assertions     BodyAssert.run (N002) on the scene's saved lines (Scene.asserts), the same call Check re-runs.
## THE GUARD (the item's rule: never keep a fix that lowers the score or breaks a passing assertion): after a fix is applied the
## score and the saved assertions are measured again; the fix is KEPT only if raw did not drop (1e-6 slack for float noise), no
## line that passed before fails now, and it helped (raw up by more than 1e-6, or fewer lines failing). Else its cards go back
## (the same arrays) and that fix is not tried again on those cards.
## ONE UNDO STEP: the loop works on copies of the cards; the scene's own card arrays are put back at the end and, unless dry, the
## final cards are written in ONE step ("Fix until it passes", the I45 panel's commit: push the undo, markers follow, retimed).
## Dry: the same loop, nothing committed: the plan of what it would do, every card array, the body and the undo list as they were.
## STOPS: "bar_reached" (all saved lines pass and score >= bar) | "cap" (max_steps fixes tried, kept or reverted) | "no_fix_left"
## (no fixable reason predicts a gain over RealismUI.GAIN_MIN) | "fix_made_it_worse" (as no_fix_left, but the last fix tried was
## reverted by the guard). Every turn of the loop either stops or tries one fix, so it ends within max_steps tries.
class_name FixLoop
extends RefCounted

const DEFAULT_BAR := 70.0     # the item's default bar (INNOVATIONS N005 / the task): a scene scoring 70+ reads as "mostly real"
const DEFAULT_STEPS := 10     # the item's hard cap
const MAX_STEPS := 50
const EPS := 1e-6
const HINT := "Fix until it passes"


## the Scene objects a fix may write: the hero's and every fighter's (JudgeSuite.fix can change another fighter's cards)
static func _scenes(m: Node) -> Array:
	var out: Array = [m.S]
	for a in m.actors_rt:
		var s: Scene = a["S"]
		if not out.any(func(x): return is_same(x, s)):
			out.append(s)
	return out


## the score and the saved assertions on the cards as they are now
static func _measure(m: Node, rs: RealismUI) -> Dictionary:
	rs.refresh()
	var ar := BodyAssert.run(m.S, m.B, m.S.asserts)
	var failing := []
	var passing := []
	var says := {}
	for x in ar["results"]:
		var ln := String(x["line"]).strip_edges()
		if bool(x.get("pass", false)):
			passing.append(ln)
		else:
			failing.append(ln)
			says[ln] = String(x.get("say", "UNREAD  %s:  %s" % [ln, x.get("error", "")]))
	return {"score": float(rs.res["score"]), "raw": float(rs.res["raw"]), "passing": passing, "failing": failing, "says": says,
		"state": {"res": rs.res, "inp": rs.inp, "key": rs.key, "memo": rs._memo, "sm": m._sm, "force": m.force_cache}}


## the realism UI's answers put back as they were for these cards (a reverted fix leaves the cards as they were)
static func _back(m: Node, rs: RealismUI, st: Dictionary) -> void:
	rs.res = st["res"]
	rs.inp = st["inp"]
	rs.key = st["key"]
	rs._memo = st["memo"]
	m._sm = st["sm"]
	m.force_cache = st["force"]


static func _ban_key(rs: RealismUI, it: Dictionary) -> String:
	return "%s|%s|%s" % [rs.key, it["judge"], it["text"]]


## the fixable reasons, each with its predicted gain, the best first; only gains over GAIN_MIN (biggest_gain's filter, all of them)
static func _candidates(m: Node, rs: RealismUI, banned: Dictionary, low: Array = []) -> Array:
	var sorted: Array = (rs.res["items"] as Array).duplicate()
	sorted.sort_custom(func(x, y): return float(x["pen"]) > float(y["pen"]))
	var seen := {}
	var cand := []
	for it in sorted:
		var kd := String(it["fix"]["kind"])
		if kd == "none" or kd == "phys" or (kd == "check" and Fixer.label(rs.inp["findings"][int(it["fix"]["i"])], m.S) == ""):
			continue
		var sk := String(it["judge"]) + String(it["text"])
		if seen.has(sk) or banned.has(_ban_key(rs, it)):
			continue
		seen[sk] = true
		cand.append(it)
		if cand.size() >= RealismUI.MAX_CAND:
			break
	var out := []
	for it in cand:
		var g := rs.gain_of(it)
		if g > RealismUI.GAIN_MIN:
			out.append({"item": it, "gain": g})
		else:
			low.append({"judge": String(it["judge"]), "text": String(it["text"]), "predicted_gain": _r2(g) if g > -90.0 else null})
	out.sort_custom(func(a, b): return float(a["gain"]) > float(b["gain"]))
	return out


## the reason in the brief's words: its rule, card, the serve step that makes the same edit (SceneBrief._reasons on this one item)
static func _words(m: Node, T: AgentTools, rs: RealismUI, it: Dictionary) -> Dictionary:
	var keep: Array = rs.res["reasons"]
	rs.res["reasons"] = [it]
	var row: Dictionary = SceneBrief._reasons(m, T, rs)[0]
	rs.res["reasons"] = keep
	return row


## apply one reason's own fix to the live cards (as gain_of predicted it). "" = applied, else why not
static func _apply(m: Node, rs: RealismUI, it: Dictionary) -> String:
	var S: Scene = m.S
	var fx: Dictionary = it["fix"]
	match String(fx["kind"]):
		"check":
			var cards: Array = Fixer.propose(rs.inp["findings"][int(fx["i"])], S, m.ov.GB, m._sm)
			if cards.is_empty():
				return "Check's fix proposed no cards"
			S.cards = cards
		"timing":
			if TimingCoach.accept(S, rs.inp["tc"][int(fx["i"])]) < 0:
				return "the timing suggestion's card is not in the scene"
		"judge":
			var fz := JudgeSuite.fix(m, it)
			if fz.is_empty():
				return "the %s judge has no fix here" % String(it["judge"]).to_lower()
			for c in fz["changes"]:
				(c["S"] as Scene).cards = (c["cards"] as Array).duplicate(true)
		_:
			return "no automatic fix"
	return ""


static func _r2(x: float) -> float:
	return snappedf(x, 0.01)


static func _view(ms: Dictionary) -> Dictionary:
	return {"score": _r2(ms["score"]), "raw": _r2(ms["raw"]), "failing": ms["failing"].duplicate()}


## the loop. Coroutine (the dummy's measurement lands first). Returns the report (see the header; `ok` false only on bad input)
static func run(m: Node, T: AgentTools, bar := DEFAULT_BAR, max_steps := DEFAULT_STEPS, dry := false) -> Dictionary:
	var S: Scene = m.S
	if S.cards.size() < 2:
		return {"ok": false, "error": "fix_until needs a scene of 2+ cards: open one first ({\"path\": \"scenes/combo3.json\"})"}
	await m.dummy_settle()
	if int(m.tc_ui.db.get("n", 0)) == 0:
		m.tc_ui.db = MotionMatch.build()   # the timing coach's move database (read once; the score needs it)
	var t0 := Time.get_ticks_msec()
	m._actors_sync()
	var rs: RealismUI = m.rs_ui
	var scenes := _scenes(m)
	var orig := scenes.map(func(s): return (s as Scene).cards)   # the very arrays: put back at the end
	for s in scenes:
		(s as Scene).cards = (s as Scene).cards.duplicate(true)
	var body0: Dictionary = m.B.state()
	var cur := _measure(m, rs)
	var first := cur
	var steps := []
	var banned := {}
	var stop := ""
	var tried := 0
	var last_reverted := false
	var no_gain := []   # at the stop: the fixable reasons whose fix predicts no gain (null: it could not be scored)
	while true:
		if cur["failing"].is_empty() and float(cur["score"]) >= bar:
			stop = "bar_reached"
			break
		if tried >= max_steps:
			stop = "cap"
			break
		no_gain = []
		var cands := _candidates(m, rs, banned, no_gain)
		if cands.is_empty():
			stop = "fix_made_it_worse" if last_reverted else "no_fix_left"
			break
		var c: Dictionary = cands[0]
		var it: Dictionary = c["item"]
		tried += 1
		var w := _words(m, T, rs, it)
		var row := {"n": tried, "judge": String(it["judge"]), "rule": String(w.get("rule", it["judge"])), "card": int(w["card"]), "card_name": String(w["card_name"]),
			"reason": String(it["text"]), "fix": String(w["fix"]), "same_as": w["steps"], "predicted_gain": _r2(c["gain"]),
			"others": cands.slice(1).map(func(o): return {"judge": String(o["item"]["judge"]), "text": String(o["item"]["text"]), "predicted_gain": _r2(o["gain"])}),
			"before": _view(cur)}
		var saved := scenes.map(func(s): return (s as Scene).cards)
		var why_not := _apply(m, rs, it)
		var aft := cur
		if why_not == "":
			aft = _measure(m, rs)
			var broke: Array = cur["passing"].filter(func(l): return l in aft["failing"])
			var bad := PackedStringArray()
			if float(aft["raw"]) < float(cur["raw"]) - EPS:
				bad.append("it lowered the score (%.2f -> %.2f)" % [cur["score"], aft["score"]])
			if not broke.is_empty():
				bad.append("it broke a passing assertion: %s" % "; ".join(broke))
			if not bad.is_empty():
				why_not = "; ".join(bad)
			elif float(aft["raw"]) <= float(cur["raw"]) + EPS and aft["failing"].size() >= cur["failing"].size():
				why_not = "it changed nothing the score or the assertions measure"
		row["after"] = _view(aft)
		if why_not == "":
			row["kept"] = true
			row["gain"] = _r2(float(aft["score"]) - float(cur["score"]))
			cur = aft
			last_reverted = false
		else:
			for k in scenes.size():
				(scenes[k] as Scene).cards = saved[k]
			_back(m, rs, cur["state"])
			row["kept"] = false
			row["reverted"] = why_not
			row["after"] = _view(cur)
			banned[_ban_key(rs, it)] = why_not
			last_reverted = true
		steps.append(row)
	m.B.set_state(body0)
	m.B.fk()
	# what is left: every failing line with its miss and why the loop could not make it hold; the score's top reasons with their step
	var left := []
	for ln in cur["failing"]:
		left.append({"what": "assertion", "line": ln, "say": cur["says"][ln],
			"why": "no fix Kine has targets an assertion itself (Check lists a failing line as ASSERT, which has no automatic fix), and %s" % (
				"no fix tried made it hold" if not steps.is_empty() else "no fixable reason was left to try")})
	var reasons := []
	for r in rs.res["reasons"]:
		var wr := _words(m, T, rs, r)
		reasons.append({"judge": String(r["judge"]), "rule": String(wr.get("rule", "")), "card": int(wr["card"]), "text": String(r["text"]), "points": _r2(r["pen"]),
			"fix": String(wr["fix"]), "same_as": wr["steps"], "how": String(wr["how"]), "tried": banned.get(_ban_key(rs, r), "")})
	if float(cur["score"]) < bar:
		left.append({"what": "score", "score": _r2(cur["score"]), "bar": bar,
			"why": "realism %.2f is under the bar %.0f; the biggest reasons left are in `reasons` (each with its serve step, or why it has none)" % [cur["score"], bar]})
	var kept := steps.filter(func(r): return bool(r["kept"]))
	var finals := scenes.map(func(s): return (s as Scene).cards)
	for k in scenes.size():
		(scenes[k] as Scene).cards = orig[k]   # the scene exactly as it came in (dry ends here)
	_back(m, rs, first["state"])
	var changed := not kept.is_empty()
	var undo_s := ""
	if changed and not dry:
		m._step_hint = HINT
		m._push_undo()
		m._markers_hold()
		for k in scenes.size():
			(scenes[k] as Scene).cards = (finals[k] as Array).duplicate(true)
		m._markers_follow()
		m._retimed()
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		rs.refresh()
		undo_s = "one undo step '%s': run {\"steps\": [\"undo\"]} to take the whole loop back" % HINT
	var why: String = {"bar_reached": "every saved assertion passes and the score %.2f is at or over the bar %.0f" % [cur["score"], bar],
		"cap": "the cap of %d fixes tried was reached" % max_steps,
		"no_fix_left": "no fix left: no fixable reason predicts a gain over %.2f points" % RealismUI.GAIN_MIN,
		"fix_made_it_worse": "the last fix tried made it worse, so it was reverted, and no other fix predicts a gain"}[stop]
	return {"ok": true, "scene": S.name, "dry": dry, "bar": bar, "max_steps": max_steps, "stopped": stop, "why": why,
		"start": _view(first), "end": _view(cur), "passed": cur["failing"].is_empty() and float(cur["score"]) >= bar,
		"tried": tried, "kept": kept.size(), "steps": steps, "no_gain": no_gain, "still_failing": left, "reasons": reasons,
		"changed": changed and not dry, "undo": undo_s if undo_s != "" else ("dry: nothing was changed" if dry else "nothing was changed: no undo step"),
		"ms": Time.get_ticks_msec() - t0}


## serve `fix_until {bar?, max_steps?, dry?, path?}`: path = open that file first (as `open`)
static func serve(T: AgentTools, id: Variant, p: Dictionary) -> Dictionary:
	var bar: Variant = p.get("bar", DEFAULT_BAR)
	var ns: Variant = p.get("max_steps", DEFAULT_STEPS)
	if not (bar is int or bar is float) or float(bar) < 0.0 or float(bar) > 100.0:
		return T._err(id, -32602, "fix_until {\"bar\": N} needs a realism score from 0 to 100 (default %d)" % int(DEFAULT_BAR))
	if not (ns is int or ns is float) or int(ns) < 1 or int(ns) > MAX_STEPS:
		return T._err(id, -32602, "fix_until {\"max_steps\": N} needs a whole number from 1 to %d (default %d)" % [MAX_STEPS, DEFAULT_STEPS])
	if p.has("path"):
		var o: Dictionary = await T.request(id, "open", {"path": p["path"]})
		if o.has("error"):
			return o
	var r: Dictionary = await run(T.m, T, float(bar), int(ns), bool(p.get("dry", false)))
	return T._ok(id, r) if r["ok"] else T._err(id, -32000, r["error"])
