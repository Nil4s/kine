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
var lap := {}        # ms per judge, the last gather


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Realism score", "", show, "realism score how realistic number 0 100 judges check timing coach push limits force view physics reasons fix", false,
		"one score 0-100 for the clip from the judges the app already has (Check's human limits, timing coach, push limits, force view, the physics judge if it ran), the 3 biggest reasons with their seconds, and a one-click fix for each")


## the header's tail on the scene strip: "" until the score was made for exactly these cards
func tag() -> String:
	if res.is_empty() or key != var_to_str(m.S.cards):
		return ""
	return "  ·  realism %d" % roundi(float(res["score"]))


## ask every judge; nothing is written to the scene. TimingCoach needs the move database (read once, ~20 s) unless `db` is given.
func gather(db: Dictionary) -> Dictionary:
	var S: Scene = m.S
	var out := {"findings": [], "tc": [], "force": {}, "push": [], "phys": null}
	var body0: Dictionary = m.B.state()   # a view: the body comes back as it was
	var t0 := Time.get_ticks_usec()
	var ck := var_to_str(S.cards) + var_to_str(S.body)   # a judge's answer is kept while the cards and the body are the same
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
	inp = gather(m.tc_ui.db)
	res = RealismScore.compute(m.S, inp)
	key = var_to_str(m.S.cards)
	ms = float(Time.get_ticks_usec() - t0) / 1000.0
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
		match String(fx["kind"]):
			"check":
				var f: Dictionary = inp["findings"][int(fx["i"])]
				var lab := Fixer.label(f, m.S)
				if lab != "":
					b = m._button(lab, fix.bind(r), "Check's own fix for this finding; one undo step")
			"timing":
				b = m._button("Accept the timing coach's move time", fix.bind(r), "write that one move time; one undo step")
			"phys":
				b = m._button("Accept span (Make it physical)", fix.bind(r), "replace the cards in that red span with the physical version; one undo step")
		if b != null:
			b.name = "rs_fix_%d" % (k + 1)
			L.add_child(b)
		else:
			L.add_child(m._label("   no one-click fix: change the pose or timing there", 12, "text:0.5", true))
	var pen: Dictionary = res["pen"]
	var shr: Dictionary = res["share"]
	var rows := PackedStringArray()
	for jd in RealismScore.JUDGES:
		if jd == "PHYSICS" and not res["judged"]:
			rows.append("PHYSICS  not judged (run Make it physical)")
		else:
			rows.append("%s  %.0f x %.0f %% of the clip = -%.1f" % [jd, RealismScore.weight_of(jd), float(shr[jd]) * 100.0, float(pen[jd])])
	var jl: Label = m._label("score = 100 - sum of: weight x share of the clip flagged.\n" + "\n".join(rows), 12, "text:0.6", true)
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
	busy = false
	refresh()
	_panel()
