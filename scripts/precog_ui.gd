## PRECOG CHECK panel (ROADMAP I31; the maths: scripts/precog.gd). Lists every answered strike with when its wind-up becomes readable, when the
## defender starts to move and when he arrives; PRECOG / LATE ones get a one-click retime. A retime is worked out first: Preview plays it (the
## scenes are not touched), Accept writes it as ONE undo step. The timeline wears a badge at each flagged reaction.
class_name PrecogUI
extends RefCounted

var m: Node
var rep: Dictionary = {}
var fx: Dictionary = {}
var sel := -1
var pv: Dictionary = {}   # fighter -> Scene (the previewed clones)
var pv_t := 0.0
var pv_end := 0.0
var playing := false


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Precog check", "", show, "precog reaction time late block parry slip human 0.2 s wind-up readable fighters choreography",
		false, "with two fighters: for each answered strike, when it becomes readable and when the defender starts to move; flags a reaction faster than a person can (PRECOG) or one that lands after the hit (LATE), each with a one-click retime; preview, then accept = one undo step")


func halt() -> void:
	playing = false
	pv = {}


func _scenes() -> Array:
	return m.actors_rt.map(func(a): return a["S"])


func _names() -> Array:
	return m.actors_rt.map(func(a): return String(a["name"]))


func clear_overlay() -> void:
	rep = {}
	fx = {}
	sel = -1
	halt()
	_overlay()


func compute() -> void:
	m._actors_sync()
	rep = Precog.analyze(_scenes(), _names())
	fx = {}
	sel = -1
	_overlay()


func _overlay() -> void:
	var tl = m.ui_timeline
	if tl == null:
		return
	tl.pc = (rep.get("items", []) as Array).map(func(i): return {"t": float(i["onset"]), "status": String(i["status"]), "def": int(i["def"])})
	tl.queue_redraw()


func show() -> void:
	m._actors_sync()
	if m.actors_rt.size() < 2:
		m._say("the precog check needs two fighters: 'Actor: add a second fighter' first")
		return
	compute()
	_panel()


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var items: Array = rep.get("items", [])
	var bad: Array = rep.get("flags", [])
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("PRECOG CHECK  -  %s" % String(rep.get("msg", "")), 14, "warn" if not bad.is_empty() else "heading", true)
	title.name = "pc_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", _close))
	var exp: Label = m._label("A person needs at least %.1f s to start answering what they see (simple visual reaction 0.20-0.25 s, Woodworth & Schlosberg 1954): the defender may move no sooner than that after the wind-up begins, and must be in place when the hit lands." % Counter.REACT, 12, "text:0.6", true)
	exp.custom_minimum_size = Vector2(380, 0)
	L.add_child(exp)
	for k in items.size():
		var it: Dictionary = items[k]
		var st := String(it["status"])
		var row := HBoxContainer.new()
		var lb: Label = m._label("%s  readable %.2f s  starts %.2f s  arrives %.2f s  hit %.2f s  -  %s" % [st.to_upper(), it["readable"], it["onset"], it["arrival"], it["contact"], it["text"]], 13,
			"text:0.8" if st == "ok" else ("warn" if st == "late" else "fail"), true)
		lb.name = "pc_row_%d" % k
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lb.custom_minimum_size = Vector2(300, 0)
		row.add_child(lb)
		if st != "ok":
			var b: Button = m._button(("> " if sel == k else "") + "Retime", select.bind(k), "work out the retime (reaction later, or shorter, or the strike delayed); nothing changes until you Accept")
			b.name = "pc_fix_%d" % k
			row.add_child(b)
		L.add_child(row)
	if not fx.is_empty():
		var l2: Label = m._label("FIX  -  " + String(fx["msg"]), 13, "heading", true)
		l2.name = "pc_fix"
		l2.custom_minimum_size = Vector2(380, 0)
		L.add_child(l2)
		var r2 := HBoxContainer.new()
		var pb: Button = m._button("Preview", preview, "play the exchange with the retime; the scenes are not changed")
		pb.name = "pc_preview"
		var ab: Button = m._button("Accept", accept, "write the retime; one undo step")
		ab.name = "pc_accept"
		r2.add_child(pb)
		r2.add_child(ab)
		L.add_child(r2)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(460, clampf(200.0 + 44.0 * items.size() + (80.0 if not fx.is_empty() else 0.0), 220.0,
		minf(560.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("precog check: " + String(rep.get("msg", "")) + (".  Press Retime beside a flagged reaction, then Preview or Accept" if not bad.is_empty() else ""))


func select(k: int) -> void:
	var items: Array = rep.get("items", [])
	if k < 0 or k >= items.size():
		m._say("pick a flagged reaction from the list first")
		return
	var f := Precog.fix(_scenes(), _names(), items[k])
	if not f["ok"]:
		m._say(String(f["why"]))
		return
	sel = k
	fx = f
	_panel()


func _close() -> void:
	clear_overlay()
	m._close_findings()


func preview() -> void:
	if fx.is_empty():
		m._say("nothing to preview: press Retime beside a flagged reaction first")
		return
	pv = {}
	pv_end = 0.0
	for w in (fx["scenes"] as Dictionary):
		pv[w] = (fx["scenes"][w] as Scene).clone()
	for s in _scenes():
		pv_end = maxf(pv_end, (s as Scene).length())
	for w in pv:
		pv_end = maxf(pv_end, (pv[w] as Scene).length())
	pv_t = 0.0
	playing = true
	m.playing = false
	m._say("precog check: previewing the retime (the scenes are not changed)")


func tick(dt: float) -> void:
	if not playing:
		return
	pv_t += dt
	if pv_t >= pv_end:
		halt()
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		return
	for k in m.actors_rt.size():
		var sc: Scene = pv[k] if pv.has(k) else m.actors_rt[k]["S"]
		sc.apply(m.actors_rt[k]["B"], pv_t)
	m._refresh()


func accept() -> void:
	if fx.is_empty():
		m._say("nothing to accept: press Retime beside a flagged reaction first")
		return
	halt()
	var msg := String(fx["msg"])
	var chg: Dictionary = fx["scenes"]
	m._actors_sync()
	m._step_hint = "Precog check"
	m._push_undo()   # (the snapshot holds every fighter's cards)
	for w in chg:
		(m.actors_rt[w]["S"] as Scene).cards = (chg[w] as Scene).cards.duplicate(true)
	var it: Array = rep.get("items", [])
	m.sj.log("precog check", String(it[sel]["status"]) if sel >= 0 and sel < it.size() else "flag", -1, {}, m.undo.size())
	m._rebuild_cards()
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	m._say("precog check: %s.  Ctrl+Z undoes it in one step" % msg)
	compute()
	_panel()
