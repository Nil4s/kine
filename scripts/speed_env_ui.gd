## SPEED ENVELOPE panel (ROADMAP I47; the maths: scripts/speed_env.gd). Kept out of main.gd like BestTakeUI: main makes one (main.se_ui), lists its
## command and ribbon button (CHECK > GRADE) and calls tick() each frame.
##   "Speed limits"  lists the cards whose hand/foot/joint speed is above the MEASURED human top, with the number, the top and the source.
##   "Slow them to the limit"  lengthens only those cards' move time; Preview plays a copy, Accept is ONE undo step.
class_name SpeedEnvUI
extends RefCounted

var m: Node
var rows: Array = []
var plan: Dictionary = {}
var pv: Scene = null
var pv_t := 0.0
var pv_end := 0.0
var ms := 0.0


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Speed limits", "", show, "speed limits human speed envelope fast punch kick too fast hand foot elbow shoulder knee trunk measured maximum",
		false, "the cards whose hand, foot or joint speed is above the measured human top, with the number, the top and the source; Preview, then Accept (one undo step)")


func halt() -> void:
	pv = null


func _clear() -> VBoxContainer:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	return L


func show() -> void:
	if m.S.cards.size() < 2:
		m._say("speed limits needs a clip of two cards or more: press Enter to add the body as a card (two at least)")
		return
	var t0 := Time.get_ticks_usec()
	var keep: Dictionary = m.B.state()   # the body as it was (an unkeyed pose stays): analyse samples the clip on it
	rows = SpeedEnv.analyse(m.S, m.B)
	plan = {}
	ms = float(Time.get_ticks_usec() - t0) / 1000.0
	m.B.set_state(keep)
	_panel()


func _panel() -> void:
	var L := _clear()
	var fl := SpeedEnv.flagged(rows)
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("SPEED LIMITS  -  " + ("%d of %d cards above the human top" % [fl.size(), rows.size()] if not fl.is_empty() else "every card is within the human top"), 14,
		"warn" if not fl.is_empty() else "heading", true)
	title.name = "se_title"
	title.custom_minimum_size = Vector2(230, 0)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", m._close_findings))
	L.add_child(m._label("Peak hand and foot speed (world) and joint turning speed of each card, against the fastest measured people. Nothing is changed until you Accept.", 13, "text:0.6", true))
	var k := 0
	for r in fl:
		var t: Label = m._label(SpeedEnv.words(r), 13, "text:0.85", true)
		t.name = "se_row_%d" % k
		t.custom_minimum_size = Vector2(330, 0)
		L.add_child(t)
		k += 1
	if not fl.is_empty():
		var mb: Button = m._button("Slow them to the limit", make_plan, "lengthen only these cards' move time until they peak at the measured top; Preview, then Accept")
		mb.name = "se_make"
		L.add_child(mb)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(350, clampf(150.0 + 56.0 * k, 200.0,
		minf(520.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.offset_right = m.ui_find.offset_left + 370   # narrower than the usual 420 so the body (its far hand) stays clear of the panel
	m.ui_find.visible = true
	if fl.is_empty():
		m._say("speed limits: every card is within the measured human top; nothing to change")
	else:
		m._say("speed limits: %d card%s above the measured human top" % [fl.size(), "" if fl.size() == 1 else "s"])


func make_plan() -> void:
	if rows.is_empty():
		show()
	var keep: Dictionary = m.B.state()
	plan = SpeedEnv.plan(m.S, m.B, rows)
	m.B.set_state(keep)
	m._ps().apply(m.B, m.playhead)
	_plan_panel()


func _plan_panel() -> void:
	var L := _clear()
	var ch: Array = plan["changes"]
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("SLOW THEM TO THE LIMIT  -  " + ("%d card%s retimed" % [ch.size(), "" if ch.size() == 1 else "s"] if not ch.is_empty() else "nothing to retime"), 14, "heading", true)
	title.name = "se_plan_title"
	title.custom_minimum_size = Vector2(230, 0)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", m._close_findings))
	L.add_child(m._label("Only the move time of these cards is lengthened, on a copy. Preview changes nothing; Accept is one undo step (Ctrl+Z).", 13, "text:0.6", true))
	var row := HBoxContainer.new()
	var pb: Button = m._button("Preview", preview, "play the clip with these cards slowed; the scene is not changed")
	pb.name = "se_preview"
	var ab: Button = m._button("Accept", accept, "write the new move times; one undo step")
	ab.name = "se_accept"
	row.add_child(pb)
	row.add_child(ab)
	L.add_child(row)
	var k := 0
	for c in ch:
		var u := String(c["ch"]["unit"])
		var t: Label = m._label("card %d %s: move %.2f s -> %.2f s, %s%s %s -> %s (top %s)" % [int(c["card"]) + 1, String(c["name"]), float(c["from"]), float(c["to"]), String(c["side"]),
			String(c["ch"]["label"]), SpeedEnv.fmt(float(c["before"]), u), SpeedEnv.fmt(float(c["after"]), u), SpeedEnv.fmt(float(c["limit"]), u)], 13, "text:0.85", true)
		t.name = "se_change_%d" % k
		t.custom_minimum_size = Vector2(330, 0)
		L.add_child(t)
		k += 1
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(350, clampf(190.0 + 40.0 * ch.size(), 230.0,
		minf(520.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.offset_right = m.ui_find.offset_left + 370   # narrower than the usual 420 so the body (its far hand) stays clear of the panel
	m.ui_find.visible = true
	m._say("speed limits: %d card%s slowed; Preview plays it, Accept writes it (Ctrl+Z undoes)" % [ch.size(), "" if ch.size() == 1 else "s"])


func preview() -> void:
	if plan.is_empty() or (plan["changes"] as Array).is_empty():
		m._say("nothing to preview: press Slow them to the limit first, in the Speed limits panel")
		return
	pv = (plan["scene"] as Scene).clone()
	pv_t = 0.0
	pv_end = pv.length()
	m.playing = false
	m._say("speed limits: previewing (the scene is not changed)")


func tick(dt: float) -> void:
	if pv == null:
		return
	pv_t += dt
	if pv_t >= pv_end:
		pv = null
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		return
	pv.apply(m.B, pv_t)
	m._refresh()


func accept() -> void:
	if plan.is_empty() or (plan["changes"] as Array).is_empty():
		m._say("nothing to accept: press Slow them to the limit first, in the Speed limits panel")
		return
	pv = null
	var n: int = (plan["changes"] as Array).size()
	m._step_hint = "Speed limits"
	m._push_undo()
	m._markers_hold()
	m.S.cards = ((plan["scene"] as Scene).cards).duplicate(true)
	m._markers_follow()
	m._retimed()
	m._say("speed limits: %d card%s slowed.  Ctrl+Z undoes it in one step" % [n, "" if n == 1 else "s"])
	plan = {}
	rows = []
	m._ps().apply(m.B, m.playhead)
