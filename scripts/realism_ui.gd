## realism_ui.gd - REALISM SCORE panel (ROADMAP I16; the maths and the weights: scripts/realism_score.gd).
##   "Realism score"  asks the judges the app already has (Check, Timing coach, push limits, Force view, and Make it physical's cached
##                    result), shows ONE number 0..100 in the CHECK panel and on the scene strip's header, and the 3 biggest reasons with
##                    their seconds, judge and numbers. Each reason has one button wired to that judge's own fix (Check's Fix, the timing
##                    coach's Accept, Make it physical's Accept span); the score is recomputed after it. Looking changes nothing.
class_name RealismUI
extends RefCounted

## hits the push-limit table says make the struck fighter step or fall, where the struck pelvis moved less than REACT_M in PUSH_SPAN s.
## REACT_M = 0.15 m is ours (a recovery step is longer: Pai & Patton 1997 measured 0.3 m and more).
const REACT_M := 0.15

var m: Node
var res := {}
var inp := {}
var key := ""        # the cards the score was made for (the header shows it only while they are the same)
var ms := 0.0
var busy := false
var _memo := {}      # {"key", "sm", "findings", "tc"}: the Check and timing answers for the cards they were made for
var prof := {}       # ms per stage of the last refresh (FrameMemo.tick)
var lap := {}        # ms per judge, the last gather
var gains := {}      # {cards key + reason text: predicted gain in points, or -1.0 if the fix could not be scored}
var _card_scores := {}   # {the cards a Check fix leaves (and the saved lines): the score on them}: two reasons whose fix leaves the same cards score once
var gain_ms := 0.0   # what the last predictions cost
var jcache := {}     # I45: the newer judges' answers per scene revision (judge_suite.gd)
var jlap := {}       # ms per newer judge, the last gather (0 = from the cache)
var best := {}       # I45: {"item", "gain"}: the fix, of any judge, that adds the most points (biggest_gain)
var found_key := ""  # the cards + saved lines the biggest-gain search was made for ("" = not searched): the panel shows best only for these


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Realism score", "", show, "realism score how realistic number 0 100 judges check timing coach push limits force view physics reasons fix", false,
		"one score 0-100 for the clip from the judges the app already has (Check's human limits, timing coach, push limits, force view, the physics judge if it ran), the 3 biggest reasons with their seconds, and a one-click fix for each")


## the header's tail on the scene strip: "" until the score was made for exactly these cards
func tag() -> String:
	if res.is_empty() or key != str(m.S.cards.hash()):
		return ""
	return "  ·  realism %d" % roundi(float(res["score"]))


## ask every judge; nothing is written to the scene. TimingCoach needs the move database (read once, ~20 s) unless `db` is given.
func gather(db: Dictionary) -> Dictionary:
	var S: Scene = m.S
	var out := {"findings": [], "tc": [], "force": {}, "push": [], "phys": null, "judges": {}}
	if S.cards.size() < 2:   # nothing to judge (empty, or a pose with no clip): do not play anything
		lap = {"check": 0.0, "timing": 0.0, "force": 0.0}
		return out
	m._pv_quiesce()   # a fix preview still on its worker thread shares FrameMemo with this pass
	FrameMemo.new_pass()
	FrameMemo.on = true   # only the frames a fix changed are played again (frame_memo.gd)
	var body0: Dictionary = m.B.state()   # a view: the body comes back as it was
	var t0 := Time.get_ticks_usec()
	var ck := str(S.cards.hash()) + var_to_str(S.body) + var_to_str(S.asserts)   # a judge's answer is kept while the cards and the body are the same (N005: and the saved N002 lines, which Check grades)
	if String(_memo.get("key", "")) != ck:
		m._bake_validate()
		var sm := Rulebook.sample(S, m.ov.GB)
		var keep: bool = HumanLimits.on
		HumanLimits.on = true   # the human-limit rules are part of this score
		var fnd := Rulebook.check(S, m.ov.GB, sm)
		HumanLimits.on = keep
		lap["check"] = float(Time.get_ticks_usec() - t0) / 1000.0
		t0 = Time.get_ticks_usec()
		var tcs := TimingCoach.compute(S, m.B, db, String(S.name))
		lap["timing"] = float(Time.get_ticks_usec() - t0) / 1000.0
		_memo = {"key": ck, "sm": sm, "findings": fnd, "tc": tcs}
		t0 = Time.get_ticks_usec()
	else:
		lap["check"] = 0.0
		lap["timing"] = 0.0
	m._sm = _memo["sm"]   # a Fix re-uses the sample instead of playing the scene again
	out["findings"] = _memo["findings"]
	out["tc"] = _memo["tc"]
	out["force"] = m._force_data()
	lap["force"] = float(Time.get_ticks_usec() - t0) / 1000.0
	out["push"] = _push_items()
	var mp: MakePhysical = m.mp_ui.mp
	if mp.done and mp.failed == "" and not mp.summary.is_empty():
		out["phys"] = mp.spans.duplicate()
	t0 = Time.get_ticks_usec()
	out["judges"] = JudgeSuite.run(m, jcache, jlap)   # I45: weapon, reaction, fatigue, momentum, recovery, spin, breakfall, precog (poses shared through the frame memo)
	lap["judges"] = float(Time.get_ticks_usec() - t0) / 1000.0
	FrameMemo.on = false
	m.B.set_state(body0)   # the judges posed the body at other times
	m.B.fk()
	return out


func _short(t: String) -> String:
	return t if t.length() <= 120 else t.left(117) + "..."


func _push_items() -> Array:
	var out := []
	if PushLimits.table().is_empty() or not m._fighters_on():
		return out
	for i in m.fighter_hits.size():
		var r: Dictionary = m.fighter_hits[i]
		if (r["kind"] != "hit" and r["kind"] != "struck") or Body.is_wep(String(r["on"])):
			continue
		var vk: int = 0 if r["by"] == "other" else int(r["vs"])
		var sk: int = int(r["vs"]) if r["by"] == "other" else 0
		if vk >= m.actors_rt.size() or sk >= m.actors_rt.size():
			continue
		var blow := HitPhysics.measure(m.actors_rt[vk]["S"], m.actors_rt[vk]["B"], m.actors_rt[vk]["xf"], r, m.actors_rt[sk]["B"])
		if not blow["ok"]:
			continue
		var lab := PushLimits.label(PushLimits.key_of(String(blow["body"])), float(blow["J_h"]), float(blow["dir_deg"]))
		if lab != "steps" and lab != "falls":
			continue
		var Ss: Scene = m.actors_rt[sk]["S"]
		var Bs: Body = m.actors_rt[sk]["B"]
		var keep := Bs.state()
		var t := float(r["t"])
		Ss.apply(Bs, t)
		Bs.fk()
		var p0: Vector3 = Bs.P["pelvis"]
		Ss.apply(Bs, t + RealismScore.PUSH_SPAN)
		Bs.fk()
		var p1: Vector3 = Bs.P["pelvis"]
		Bs.set_state(keep)
		var moved := Vector2(p1.x - p0.x, p1.z - p0.z).length()
		if moved < REACT_M:
			out.append({"t0": t, "t1": t + RealismScore.PUSH_SPAN, "text": "hit %d should make the struck fighter %s (J %.1f N s) but the pelvis moves only %s in %.1f s" % [
				i + 1, "step" if lab == "steps" else "fall", float(blow["J_h"]), Units.len(moved), RealismScore.PUSH_SPAN]})
	return out


## the score the clip WOULD have with these cards (the scene gets them for the length of the call and is put back, the same object;
## the judges' answers for the real cards, the frame memo and the force cache are put back too)
func _score_with(changes: Array, tc_fix := {}) -> float:
	var S: Scene = m.S
	var origs := changes.map(func(c): return (c["S"] as Scene).cards)
	var keep_j := jcache.duplicate()
	var keep_memo := _memo
	var keep_force: Dictionary = m.force_cache
	var keep_sm = m._sm
	var keep_lap := lap.duplicate()
	for c in changes:
		(c["S"] as Scene).cards = c["cards"]
	if not tc_fix.is_empty():
		TimingCoach.accept(S, tc_fix)
	_memo = {}
	FrameMemo.probe = true
	var sc := float(RealismScore.compute(S, gather(m.tc_ui.db))["raw"])   # raw: the unfloored 100 - total, so a clip at 0 still shows a gain
	FrameMemo.probe = false
	for k in changes.size():
		(changes[k]["S"] as Scene).cards = origs[k]
	jcache = keep_j
	_memo = keep_memo
	m.force_cache = keep_force
	m._sm = keep_sm
	lap = keep_lap
	return sc


## the points a reason's own fix would add, worked out on a copy: -1.0 = this reason has no fix that can be scored
func gain_of(r: Dictionary) -> float:
	var gk := _gkey(r)
	if gains.has(gk):
		return gains[gk]
	var fx: Dictionary = r["fix"]
	var g := -99.0
	var S: Scene = m.S
	match String(fx["kind"]):
		"timing":
			g = RealismScore.shown(_score_with([{"S": S, "cards": S.cards.duplicate(true)}], inp["tc"][int(fx["i"])])) - RealismScore.shown(float(res["raw"]))
		"check":
			var f: Dictionary = inp["findings"][int(fx["i"])]
			if Fixer.label(f, S) != "":
				var cards: Array = Fixer.propose(f, S, m.ov.GB, m._sm)
				if not cards.is_empty():
					var ck := var_to_str([cards, S.asserts])
					if not _card_scores.has(ck):
						_card_scores[ck] = RealismScore.shown(_score_with([{"S": S, "cards": cards}]))
					g = float(_card_scores[ck]) - RealismScore.shown(float(res["raw"]))
		"judge":
			var fz := JudgeSuite.fix(m, r)
			if not fz.is_empty():
				g = RealismScore.shown(_score_with(fz["changes"])) - RealismScore.shown(float(res["raw"]))
	gains[gk] = g
	return g


## the cache key of one reason's predicted gain (N005: a saved line changes what a fix is worth)
func _gkey(r: Dictionary) -> String:
	return key + "|" + var_to_str(m.S.asserts) + "|" + String(r["text"])


## the key the biggest-gain search is kept for: the cards and the saved lines
func _find_key() -> String:
	return key + "|" + var_to_str(m.S.asserts)


## I45: the fix, of ANY judge, that adds the most points: each of the MAX_CAND largest fixable reasons is tried on a copy (gain_of; the
## answer is kept per cards) and the best gain over GAIN_MIN wins. {} when no fix helps.
const MAX_CAND := 6
const GAIN_MIN := 0.05


func biggest_gain() -> Dictionary:
	var cand := []
	var sorted: Array = (res["items"] as Array).duplicate()
	sorted.sort_custom(func(x, y): return float(x["pen"]) > float(y["pen"]))
	var seen := {}
	for it in sorted:
		var kd := String(it["fix"]["kind"])
		if kd == "none" or kd == "phys" or (kd == "check" and Fixer.label(inp["findings"][int(it["fix"]["i"])], m.S) == ""):
			continue
		var sk := String(it["judge"]) + String(it["text"])
		if seen.has(sk):
			continue
		seen[sk] = true
		cand.append(it)
		if cand.size() >= MAX_CAND:
			break
	var t0 := Time.get_ticks_usec()
	var pick := {}
	var bg := GAIN_MIN
	for it in cand:
		var g := gain_of(it)
		if g > bg:
			bg = g
			pick = {"item": it, "gain": g}
	gain_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	return pick


func show() -> void:
	if m.S.cards.size() < 2:
		m._say("Realism score needs a scene of two cards or more: press Enter to add the body as a card (two at least), or open a scene in the list below")
		return
	if int(m.tc_ui.db.get("n", 0)) == 0:
		m._say("realism score: reading your scenes for the timing coach (once, about 20 s)...")
		await m.get_tree().process_frame
		m.tc_ui.db = MotionMatch.build()
	refresh()
	_panel()


func refresh() -> void:
	var t0 := Time.get_ticks_usec()
	FrameMemo.prof = {}   # the profile of this score (FrameMemo.tick)
	inp = gather(m.tc_ui.db)
	res = RealismScore.compute(m.S, inp)
	if key != str(m.S.cards.hash()):
		gains = {}
		_card_scores = {}
	key = str(m.S.cards.hash())
	if found_key != _find_key():
		best = {}
		found_key = ""
	ms = float(Time.get_ticks_usec() - t0) / 1000.0
	prof = FrameMemo.prof.duplicate()
	m._doc_line(true)


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var score := roundi(float(res["score"]))
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("REALISM  %d / 100" % score, 22, "heading" if score >= 90 else "warn")
	title.name = "rs_score"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", m._close_findings))
	var rs: Array = res["reasons"]
	if found_key != "" and found_key == _find_key():
		if not best.is_empty():
			var bi: Dictionary = best["item"]
			var bl: Label = m._label("BIGGEST GAIN  %s  +%.1f points\n%s" % [bi["judge"], float(best["gain"]), _short(String(bi["text"]))], 14, "heading", true)
			bl.name = "rs_best_label"
			bl.custom_minimum_size = Vector2(380, 0)
			L.add_child(bl)
			var bb: Button = m._button("Apply the biggest gain", fix.bind(bi), "the single fix that adds the most points, predicted on a copy of the clip; one undo step")
			bb.name = "rs_best"
			L.add_child(bb)
	else:
		var fb: Button = m._button("Find the biggest gain", find_biggest, "predicts each reason's fix on a copy of the clip (a few seconds each) and offers the one that adds the most points; nothing changes until you press its button")
		fb.name = "rs_find"
		L.add_child(fb)
	if rs.is_empty():
		L.add_child(m._label("Nothing flagged: every judge that ran is satisfied.", 14, "text:0.85", true))
	for k in rs.size():
		var r: Dictionary = rs[k]
		var lb: Label = m._label("%d. %s   %.2f-%.2f s   -%.1f points\n%s" % [k + 1, r["judge"], float(r["t0"]), float(r["t1"]), float(r["pen"]), _short(String(r["text"]))], 14, "text:0.85", true)
		lb.name = "rs_reason_%d" % (k + 1)
		lb.custom_minimum_size = Vector2(380, 0)
		L.add_child(lb)
		var fx: Dictionary = r["fix"]
		var b: Button = null
		var why_not := ""
		var predict_btn := false   # a gain not worked out yet: the row gets a "Predict this fix" button, the gain is worked out when it is pressed
		match String(fx["kind"]):
			"check", "timing":
				var lab := ""
				if String(fx["kind"]) == "check":
					lab = Fixer.label(inp["findings"][int(fx["i"])], m.S)
				else:
					lab = "Fix: accept the timing coach's move time"
				if lab != "":
					if gains.has(_gkey(r)):
						var gn := gain_of(r)
						if gn > 0.05:
							b = m._button("%s   +%.1f points" % [lab, gn], fix.bind(r), "predicted on a copy of the clip: the score goes up by %.1f points; one undo step" % gn)
						elif gn > -90.0:
							why_not = "   its own fix would %s the score (%+.1f points): the judges disagree here, so it is not offered" % ["lower" if gn < -0.05 else "not change", gn]
					else:
						b = _predict_button(r, k)
						predict_btn = true
			"judge":
				var fzz := JudgeSuite.fix(m, r)
				if fzz.is_empty():
					why_not = "   no one-click fix from the %s judge here: change the pose or timing" % String(r["judge"]).to_lower()
				elif gains.has(_gkey(r)):
					var gj := gain_of(r)
					if gj > GAIN_MIN:
						b = m._button("%s   +%.1f points" % [JudgeSuite.LABEL[r["judge"]], gj], fix.bind(r), "predicted on a copy of the clip: the score goes up by %.1f points; one undo step" % gj)
					else:
						why_not = "   its own fix would %s the score (%+.1f points): not offered" % ["lower" if gj < -GAIN_MIN else "not change", gj]
				else:
					b = _predict_button(r, k)
					predict_btn = true
			"phys":
				b = m._button("Accept span (Make it physical)", fix.bind(r), "replace the cards in that red span with the physical version; one undo step")
		if b != null:
			if not predict_btn:
				b.name = "rs_fix_%d" % (k + 1)
			L.add_child(b)
		else:
			L.add_child(m._label(why_not if why_not != "" else "   no one-click fix: change the pose or timing there", 12, "text:0.5", true))
	var pen: Dictionary = res["pen"]
	var shr: Dictionary = res["share"]
	var rows := PackedStringArray()
	for jd in RealismScore.JUDGES:
		if jd == "PHYSICS" and not res["judged"]:
			rows.append("PHYSICS  not judged (run Make it physical)")
		else:
			rows.append("%s  %.0f x %.0f %% of the clip = -%.1f" % [jd, RealismScore.weight_of(jd), float(shr[jd]) * 100.0, float(pen[jd])])
	for jd in RealismScore.NEW:
		if res["abstain"].has(jd):
			rows.append("%s  abstains (%s)" % [jd, res["abstain"][jd]])
		else:
			rows.append("%s  %.0f x %.0f %% of the %s flagged = -%.1f points" % [jd, RealismScore.weight_of(jd), float(shr[jd]) * 100.0, JudgeSuite.UNIT[jd], float(pen[jd])])
	var jl: Label = m._label("score = 100 points x exp(-total / 100 points), total = sum of: weight x share of the clip (older judges) or of the things judged (newer ones) flagged; about 100 points minus the total when the total is small, never stuck at zero. An abstaining judge does not move the score.\n" + "\n".join(rows), 12, "text:0.6", true)
	jl.name = "rs_judges"
	L.add_child(jl)
	L.add_child(m._label("computed in %.0f ms" % ms, 12, "text:0.5", true))
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(400, clampf(300.0 + 95.0 * rs.size(), 120.0,
		minf(520.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("realism score %d / 100%s" % [score, "" if rs.is_empty() else ": the biggest reason is %s. Each reason has its own fix (Ctrl+Z undoes it)" % rs[0]["judge"]])


## run one reason's own fix, then ask the judges again
func fix(r: Dictionary) -> void:
	if busy:
		return
	busy = true
	var fx: Dictionary = r["fix"]
	var i := int(fx["i"])
	match String(fx["kind"]):
		"check":
			await m._fix(inp["findings"][i])
		"timing":
			m.tc_ui.sugs = inp["tc"]
			m.tc_ui.accept(i)
		"phys":
			m.mp_ui.sel = i
			m.mp_ui.accept()
		"judge":
			var fz := JudgeSuite.fix(m, r)
			if not fz.is_empty():
				m._actors_sync()
				m._step_hint = "Realism score: %s" % JudgeSuite.LABEL[r["judge"]]
				m._push_undo()
				m._markers_hold()
				for c in fz["changes"]:
					(c["S"] as Scene).cards = (c["cards"] as Array).duplicate(true)
				m._markers_follow()
				m._retimed()
				m._ps().apply(m.B, m.playhead)
				m._refresh()
	busy = false
	refresh()
	_panel()


## the biggest gain, found on demand: each candidate's fix is predicted (a few seconds each), then the panel is drawn with the best one
func find_biggest() -> void:
	m._say("Working... (a few seconds per fix)")
	await m.get_tree().process_frame
	best = biggest_gain()
	found_key = _find_key()
	_panel()


## a reason's gain, predicted on demand: then the panel is drawn again with its fix button or its why-not text
func predict(r: Dictionary) -> void:
	m._say("Working... (a few seconds per fix)")
	await m.get_tree().process_frame
	gain_of(r)
	_panel()


func _predict_button(r: Dictionary, k: int) -> Button:
	var b: Button = m._button("Predict this fix", predict.bind(r), "predicts what this one fix adds to the score (a few seconds, on a copy of the clip); nothing changes")
	b.name = "rs_predict_%d" % (k + 1)
	return b
