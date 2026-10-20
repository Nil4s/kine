## RECOVERY STEP panel (ROADMAP I39; the maths: scripts/recovery.gd, the floor drawing: scripts/recovery_view.gd). The struck pose is the card
## at or before the playhead. Pick a shove (small / medium / huge) and the direction it comes from: the panel reads the capture point against
## the base of support and says HOLD (no step), STEP (a foot lands at the capture point, 2 cards inserted after the struck card) or FALLS
## (longer than a person can step: see the Breakfall check). Preview plays the step (the scene is not changed), Accept writes the cards as ONE undo step.
class_name RecoveryUI
extends RefCounted

var m: Node
var rd: Dictionary = {}
var pl: Dictionary = {}
var shove := "medium"
var dir := "forward"
var speed := -1.0   # m/s; < 0 = the named shove's
var pv := false
var pv_t := 0.0
var pv_t1 := 0.0
var pv_sc: Scene = null


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Recovery step", "", show, "recovery step capture point extrapolated centre of mass shove push hit step balance base of support fall xcom",
		false, "after a shove or hit: reads the capture point (Hof 2005) against the feet; a small shove needs no step, a medium one gets a stepping recovery to the capture point, a huge one is flagged as a fall (preview, then Accept = one undo step)")


func halt() -> void:
	pv = false
	pv_sc = null


func clear_overlay() -> void:
	rd = {}
	pl = {}
	halt()
	if m.rc_view != null:
		m.rc_view.show_rep({}, {})


## the card of the struck pose: the last one that has arrived by the playhead
func card_at() -> int:
	var S: Scene = m.S
	var ts: Array = S.times()
	var k := 0
	for i in S.cards.size():
		if float(ts[i][1]) <= float(m.playhead) + 1e-4:
			k = i
	return k


func speed_now() -> float:
	return speed if speed >= 0.0 else float(Recovery.SHOVES[shove])


func compute() -> void:
	m._actors_sync()
	rd = {}
	pl = {}
	if m.S == null or (m.S as Scene).cards.is_empty():
		return
	pl = Recovery.plan(m.S, card_at(), float(Recovery.DIRS[dir]), speed_now())
	rd = pl.get("rd", {})
	if m.rc_view != null:
		m.rc_view.show_rep(rd, pl)


func show() -> void:
	compute()
	_panel()


static func word(v: String) -> String:
	return {"hold": "HOLD", "step": "STEP", "fall": "FALLS"}.get(v, v)


func _pick(s: String, d: String) -> void:
	if s != "":
		shove = s
		speed = -1.0
	if d != "":
		dir = d
	compute()
	_panel()


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	L.add_child(head)
	var verdict := String(rd.get("verdict", "")) if not rd.is_empty() else ""
	var title: Label = m._label("RECOVERY STEP  -  %s" % (word(verdict) if verdict != "" else "pick a shove"), 14, "fail" if verdict == "fall" else ("warn" if verdict == "step" else "heading"), true)
	title.name = "rc_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", _close))
	L.add_child(m._label("Capture point = the COM's floor point + its speed / omega0, omega0 = sqrt(g / pendulum length) (Hof, Gazendam and Sinke 2005). Inside the feet: he holds. Outside: a foot must land on it, in %.2f s, up to a step of %.0f%% of the leg; longer is a fall. The shove is the speed the push gives the COM." % [Recovery.STEP_T, Recovery.MAX_STEP_LEG * 100.0],
		13, "text:0.6", true))
	var r1 := HBoxContainer.new()
	for s in Recovery.SHOVES:
		var b: Button = m._button(("[%s]" if s == shove else "%s") % (String(s).capitalize() + " shove"), _pick.bind(s, ""), "the COM gains %.2f m/s" % float(Recovery.SHOVES[s]))
		b.name = "rc_shove_" + String(s)
		r1.add_child(b)
	L.add_child(r1)
	var r2 := HBoxContainer.new()
	for dn in Recovery.DIRS:
		var b2: Button = m._button(("[%s]" if dn == dir else "%s") % ("Pushed " + String(dn)), _pick.bind("", dn), "the direction the COM is sent, from the body's facing")
		b2.name = "rc_dir_" + String(dn)
		r2.add_child(b2)
	L.add_child(r2)
	if rd.is_empty() or not bool(rd.get("ok", true)):
		var why := String(pl.get("why", "the scene has no pose card: add one with the fighter standing, then try again"))
		var lw: Label = m._label(why, 13, "warn", true)
		lw.name = "rc_why"
		lw.custom_minimum_size = Vector2(380, 0)
		L.add_child(lw)
		m.ui_find.visible = true
		m._say("recovery step: " + why)
		return
	var lines := ["COM speed %.2f m/s, omega0 %.2f /s over a pendulum of %.0f cm" % [float(rd["speed"]), float(rd["w0"]), float(rd["l"]) * 100.0],
		"capture point %.0f cm from the COM, %.1f cm %s the feet" % [(Vector2(rd["xi"]) - Vector2(rd["com0"])).length() * 100.0, absf(float(rd["margin"])) * 100.0, "inside" if float(rd["margin"]) >= 0.0 else "outside"]]
	if verdict != "hold":
		lines.append("the step: %.0f cm (a person can step %.0f cm)" % [float(rd["step"]) * 100.0, float(rd["max"]) * 100.0])
	if bool(pl.get("ok", false)):
		lines.append("lands %.1f cm from the capture point, in %.2f s; the capture point is then %.1f cm inside the feet" % [float(pl["land_err"]) * 100.0, Recovery.STEP_T, float(pl["margin_after"]) * 100.0])
	var li := 0
	for t in lines:
		var lb: Label = m._label(String(t), 13, "text:0.85", true)
		lb.name = "rc_line_%d" % li
		lb.custom_minimum_size = Vector2(380, 0)
		L.add_child(lb)
		li += 1
	if verdict == "hold":
		var lh: Label = m._label("HOLD  the capture point stays inside the feet: no step is needed", 13, "heading", true)
		lh.name = "rc_hold"
		L.add_child(lh)
	elif verdict == "fall" or bool(pl.get("fall", false)):
		var lf: Label = m._label("FALLS  " + String(pl.get("why", "")), 13, "fail", true)
		lf.name = "rc_fall"
		lf.custom_minimum_size = Vector2(380, 0)
		L.add_child(lf)
		var bb: Button = m._button("Breakfall check", func(): m.bk_ui.show(), "judge the landing of the fall")
		bb.name = "rc_breakfall"
		L.add_child(bb)
	if bool(pl.get("ok", false)):
		var r3 := HBoxContainer.new()
		var pb: Button = m._button("Preview", preview, "play the step; the scene is not changed")
		pb.name = "rc_preview"
		var ab: Button = m._button("Accept", accept, "write the two step cards; one undo step")
		ab.name = "rc_accept"
		r3.add_child(pb)
		r3.add_child(ab)
		L.add_child(r3)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(440, clampf(330.0, 220.0,
		minf(560.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("recovery step: %s" % (String(pl["msg"]) if bool(pl.get("ok", false)) else (word(verdict) + ", pick a stronger or weaker shove to compare")))


func _close() -> void:
	clear_overlay()
	m._close_findings()


func preview() -> void:
	if not bool(pl.get("ok", false)):
		m._say("nothing to preview: pick a medium shove first, the step appears when the capture point leaves the feet")
		return
	halt()
	pv_sc = (pl["scene"] as Scene).clone()
	pv_t = maxf(0.0, float(pl["t0"]) - 0.1)
	pv_t1 = float(pl["t1"]) + 0.2
	pv = true
	m.playing = false
	m._say("recovery step: previewing the step (the scene is not changed)")


func tick(dt: float) -> void:
	if not pv:
		return
	pv_t += dt
	if pv_t >= pv_t1:
		halt()
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		return
	pv_sc.apply(m.B, pv_t)
	m._refresh()


func accept() -> void:
	if not bool(pl.get("ok", false)):
		m._say("nothing to accept: pick a medium shove first, the step appears when the capture point leaves the feet")
		return
	halt()
	var f := pl
	m._actors_sync()
	m._step_hint = "Recovery step"
	m._push_undo()
	(m.S as Scene).cards = (f["scene"] as Scene).cards.duplicate(true)
	m._rebuild_cards()
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	m._say("recovery step: %s.  Ctrl+Z undoes it in one step" % String(f["msg"]))
	compute()
	_panel()
