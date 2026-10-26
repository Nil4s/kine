## MOMENTUM LEDGER panel (ROADMAP I36; the maths: scripts/momentum.gd). "Momentum ledger" reads the whole body's linear and angular momentum
## going in and coming out of every card (60 Hz, the app's own de Leva mass model), says in words with numbers where one drops faster than a
## body can brace without a step or a pivot ("0.42 s: 38 kg m/s forward drops to 0 kg m/s in 1 frame, no foot moves"), and puts a STOP / SPIN
## badge on the timeline at that card. "Ease the stop" works out a smooth ease and, if needed, a longer move into the card (the time the
## force bar needs); Preview plays it (nothing changes), Accept writes it as ONE undo step. It reads the scene on the stage (the hero).
class_name MomentumUI
extends RefCounted

var m: Node
var rep: Dictionary = {}
var plan: Dictionary = {}   # the fix being offered: {"card", "scene", "msg", "ok"}
var pv: Scene = null
var pv_t := 0.0
var pv_end := 0.0
var ms := 0.0


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Momentum ledger", "", show, "momentum ledger linear angular stop dead brace step pivot lunge spin card transition force ground",
		false, "the body's linear and angular momentum going into and out of every card; flags a stop that drops faster than a body can brace without a step or pivot, in words with numbers; ease the stop over the time the force bar needs; preview, then accept = one undo step")


func halt() -> void:
	pv = null


func compute() -> void:
	var t0 := Time.get_ticks_usec()
	rep = Momentum.analyze(m.S, m.B)
	ms = float(Time.get_ticks_usec() - t0) / 1000.0
	plan = {}
	_overlay()


func _overlay() -> void:
	var tl = m.ui_timeline
	if tl == null:
		return
	var marks := []
	if rep.get("ok", false):
		for r in rep["flags"]:
			marks.append({"t": float(r["t"]), "flag": true, "kind": r["kind"], "card": r["card"]})
	tl.ml = marks
	tl.queue_redraw()


func clear_overlay() -> void:
	rep = {}
	plan = {}
	halt()
	_overlay()


func show() -> void:
	if m.S.cards.size() < 2:
		m._say("Momentum ledger needs a scene of two cards or more: press Enter to add the body as a card (two at least), or open a scene in the list below")
		return
	m._say("momentum ledger: reading the clip's momentum...")
	compute()
	_panel()


## the Momentum ledger button: show() with the clip read on a worker thread (checkslice)
func show_bg() -> void:
	if m.S.cards.size() < 2:
		show()   # the "needs two cards" line
		return
	var C: Scene = m.S.clone()
	var st: Dictionary = m.B.state()
	var t0 := Time.get_ticks_usec()
	var r: Dictionary = await m.bg_run("momentum ledger", "momentum ledger: reading the clip's momentum...", func(): return Momentum.analyze(C, m.bg_body(st)))
	if not r["ok"]:
		return
	rep = r["v"]
	ms = float(Time.get_ticks_usec() - t0) / 1000.0
	plan = {}
	_overlay()
	_panel()


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var flags: Array = rep.get("flags", [])
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("MOMENTUM LEDGER  -  " + ("%d stop%s no body can brace" % [flags.size(), "" if flags.size() == 1 else "s"] if not flags.is_empty() else "every stop can be braced"), 16, "warn" if not flags.is_empty() else "heading", true)
	title.name = "ml_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", _close))
	var exp: Label = m._label("Newton: the outside force is dP/dt. " + Momentum.bar_text(), 12, "text:0.6", true)
	exp.custom_minimum_size = Vector2(380, 0)
	L.add_child(exp)
	if rep.get("ok", false):
		var sum: Label = m._label("%s  (body mass %.0f kg, weight %.0f N)" % [rep["msg"], rep["mass"], rep["bw"]], 13, "text:0.85", true)
		sum.name = "ml_sum"
		sum.custom_minimum_size = Vector2(380, 0)
		L.add_child(sum)
	for r in flags:
		var lb: Label = m._label("card %d  -  %s" % [int(r["card"]) + 1, r["msg"]], 13, "warn", true)
		lb.name = "ml_row_%d" % int(r["card"])
		lb.custom_minimum_size = Vector2(380, 0)
		L.add_child(lb)
		var b: Button = m._button("Ease the stop (card %d)" % [int(r["card"]) + 1], offer.bind(int(r["card"])), "a smooth ease into this card and, if the bar still fails, a longer move: the stop takes the time the force bar needs; nothing changes until you Accept")
		b.name = "ml_fix_%d" % int(r["card"])
		L.add_child(b)
	if not plan.is_empty():
		var l2: Label = m._label("EASE THE STOP  -  " + String(plan["msg"]), 13, "heading" if plan["ok"] else "warn", true)
		l2.name = "ml_plan"
		l2.custom_minimum_size = Vector2(380, 0)
		L.add_child(l2)
		var r2 := HBoxContainer.new()
		var pb: Button = m._button("Preview", preview, "play the eased stop; the scene is not changed")
		pb.name = "ml_preview"
		var ab: Button = m._button("Accept", accept, "write the eased stop; one undo step")
		ab.name = "ml_accept"
		r2.add_child(pb)
		r2.add_child(ab)
		L.add_child(r2)
	L.add_child(m._label("computed in %.0f ms" % ms, 12, "text:0.5", true))
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(440, clampf(170.0 + 95.0 * flags.size() + (90.0 if not plan.is_empty() else 0.0), 200.0,
		minf(560.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("momentum ledger: " + String(rep.get("msg", "")) + (".  " + String(flags[0]["msg"]) if not flags.is_empty() else ""))


func offer(card: int) -> void:
	if card < 1 or card >= m.S.cards.size():
		m._say("pick a flagged card from the list first")
		return
	var p := Momentum.fix(m.S, m.B, card)
	p["card"] = card
	plan = p
	_panel()
	m._say("ease the stop: %s.  Preview, or Accept (Ctrl+Z undoes)" % plan["msg"])


func _close() -> void:
	clear_overlay()
	m._close_findings()


func preview() -> void:
	if plan.is_empty():
		m._say("nothing to preview: press Ease the stop beside a flagged card first")
		return
	pv = (plan["scene"] as Scene).clone()
	pv_t = 0.0
	pv_end = maxf(pv.length(), 0.1)
	m.playing = false
	m._say("ease the stop: previewing the eased clip (the scene is not changed)")


func tick(dt: float) -> void:
	if pv == null:
		return
	pv_t += dt
	if pv_t >= pv_end:
		halt()
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		return
	pv.apply(m.B, pv_t)
	m._refresh()


func accept() -> void:
	if plan.is_empty():
		m._say("nothing to accept: press Ease the stop beside a flagged card first")
		return
	if not bool(plan["ok"]):
		m._say("this fix does not clear the stop: add a step or a pivot card before it by hand, or pick another card")
		return
	halt()
	var msg := String(plan["msg"])
	m._step_hint = "Momentum ledger: ease the stop"
	m._push_undo()
	m._markers_hold()
	m.S.cards = (plan["scene"] as Scene).cards.duplicate(true)
	m._markers_follow()
	m.sj.log("momentum", "ease the stop", -1, {}, m.undo.size())
	m._rebuild_cards()
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	compute()
	_panel()
	m._say("ease the stop: %s.  Ctrl+Z undoes it in one step" % msg)
