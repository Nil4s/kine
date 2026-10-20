## FIGHT RHYTHM panel (ROADMAP I19; the maths: scripts/fight_rhythm.gd). With two or more fighters the timeline wears a rhythm strip (one tick per
## action, coloured by fighter: tall = strike, short = block or step, hollow = feint; a red band under the flagged stretches) and the panel
## lists every flag with a one-click suggestion. A suggestion is worked out first: Preview plays the fighter it changes (the scene is not
## touched), Accept writes it as ONE undo step.
class_name FightRhythmUI
extends RefCounted

var m: Node
var rep: Dictionary = {}
var fx: Dictionary = {}
var sel := -1
var pv: Scene = null
var pv_who := 0
var pv_t := 0.0
var pv_end := 0.0


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Fight rhythm", "", show, "rhythm tempo beat interval monotony dead air pause feint side rush strikes exchange fighters choreography",
		false, "with two fighters: a tempo map of the exchange (who attacks, who answers, the time between beats) as a strip on the timeline; flags monotony, dead air and rush, each with a one-click suggestion (pause, change side, feint); preview, then accept = one undo step")


func halt() -> void:
	pv = null


func clear_overlay() -> void:
	rep = {}
	fx = {}
	sel = -1
	pv = null
	_overlay()


func _scenes() -> Array:
	return m.actors_rt.map(func(a): return a["S"])


func _names() -> Array:
	return m.actors_rt.map(func(a): return String(a["name"]))


func compute() -> void:
	m._actors_sync()
	rep = FightRhythm.analyze(_scenes(), _names(), maxi(1, (m.actors_rt[0]["S"] as Scene).fps))
	fx = {}
	sel = -1
	_overlay()


func _overlay() -> void:
	var tl = m.ui_timeline
	if tl == null:
		return
	var flagged := {}
	var bands := []
	for f in rep.get("flags", []):
		bands.append({"t0": float(f["t0"]), "t1": float(f["t1"])})
	var ticks := []
	for e in rep.get("events", []):
		ticks.append({"t": float(e["t"]), "who": int(e["who"]), "type": String(e["type"])})
	tl.rh = ticks
	tl.rh_flags = bands
	tl.queue_redraw()


func show() -> void:
	m._actors_sync()
	if m.actors_rt.size() < 2:
		m._say("the fight rhythm needs two fighters: 'Actor: add a second fighter' first")
		return
	compute()
	_panel()


func _event_line(e: Dictionary) -> String:
	var t := "%.2f s  %s  %s" % [float(e["t"]), e["name"], String(e["kind"])]
	if e["type"] == "strike":
		t += " (%s)" % String(e["limb"]).replace("_", " ")
		t += "  answered by %s" % e["answer"] if e["answer"] != "" else "  unanswered"
	return t


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var flags: Array = rep.get("flags", [])
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("FIGHT RHYTHM  -  %s" % String(rep.get("msg", "")), 14, "warn" if not flags.is_empty() else "heading", true)
	title.name = "rh_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", _close))
	var iv: Array = rep.get("intervals", [])
	var tempo := ""
	for k in iv.size():
		tempo += "%.2f%s" % [float(iv[k]), "  " if k < iv.size() - 1 else ""]
	var tm: Label = m._label("Tempo (s between attacks): %s" % (tempo if tempo != "" else "fewer than two attacks"), 13, "text:0.85", true)
	tm.name = "rh_tempo"
	tm.custom_minimum_size = Vector2(380, 0)
	L.add_child(tm)
	for k in flags.size():
		var f: Dictionary = flags[k]
		var row := HBoxContainer.new()
		var lb: Label = m._label("%.2f-%.2f s  %s" % [float(f["t0"]), float(f["t1"]), f["text"]], 13, "fail" if f["type"] == "rush" else "warn", true)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lb.custom_minimum_size = Vector2(300, 0)
		row.add_child(lb)
		var fixd: Dictionary = f["fix"]
		var b: Button = m._button(("> " if sel == k else "") + String(fixd.get("label", "No suggestion")), select.bind(k), "work out this suggestion; nothing changes until you Accept")
		b.name = "rh_fix_%d" % k
		row.add_child(b)
		L.add_child(row)
	if not fx.is_empty():
		var l2: Label = m._label("FIX  -  " + String(fx["msg"]), 13, "heading", true)
		l2.name = "rh_fix"
		l2.custom_minimum_size = Vector2(380, 0)
		L.add_child(l2)
		var r2 := HBoxContainer.new()
		var pb: Button = m._button("Preview", preview, "play the fighter it changes with the suggestion; the scene is not changed")
		pb.name = "rh_preview"
		var ab: Button = m._button("Accept", accept, "write the suggestion; one undo step")
		ab.name = "rh_accept"
		r2.add_child(pb)
		r2.add_child(ab)
		L.add_child(r2)
	L.add_child(m._label("Ticks on the timeline: one per strike, block, step or feint, coloured by fighter (amber = %s, blue = %s). Flags: the same gap three times, one side four times, one kind three times, dead air over 1.2 s (my number, a heuristic), a strike sooner than the recovery the timing coach allows. Preview changes nothing; Accept is one undo step." % [
		m.actors_rt[0]["name"], m.actors_rt[1]["name"]], 13, "text:0.6", true))
	var evs: Array = rep.get("events", [])
	for e in evs.slice(0, 14):
		var lb2: Label = m._label(_event_line(e), 12, "text:0.7", true)
		lb2.custom_minimum_size = Vector2(380, 0)
		L.add_child(lb2)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(440, clampf(260.0 + 36.0 * flags.size() + (80.0 if not fx.is_empty() else 0.0), 260.0,
		minf(560.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("fight rhythm: " + String(rep.get("msg", "")) + (".  Each flag has a one-click suggestion: press it, then Preview or Accept" if not flags.is_empty() else ""))


func select(k: int) -> void:
	var flags: Array = rep.get("flags", [])
	if k < 0 or k >= flags.size():
		m._say("pick a flag from the list first")
		return
	var f := FightRhythm.fix(_scenes(), _names(), flags[k])
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
		m._say("nothing to preview: press a suggestion beside a flag first")
		return
	pv = (fx["scene"] as Scene).clone()
	pv_who = int(fx["who"])
	pv_t = 0.0
	pv_end = pv.length()
	for s in _scenes():
		pv_end = maxf(pv_end, (s as Scene).length())
	m.playing = false
	m._say("fight rhythm: previewing the suggestion (the scene is not changed)")


func tick(dt: float) -> void:
	if pv == null:
		return
	pv_t += dt
	if pv_t >= pv_end:
		pv = null
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		return
	for k in m.actors_rt.size():
		var sc: Scene = pv if k == pv_who else m.actors_rt[k]["S"]
		sc.apply(m.actors_rt[k]["B"], pv_t)
	m._refresh()


func accept() -> void:
	if fx.is_empty():
		m._say("nothing to accept: press a suggestion beside a flag first")
		return
	pv = null
	var sc: Scene = fx["scene"]
	var msg := String(fx["msg"])
	var w := int(fx["who"])
	m._actors_sync()
	m._step_hint = "Fight rhythm"
	m._push_undo()   # (the snapshot holds every fighter's cards)
	(m.actors_rt[w]["S"] as Scene).cards = sc.cards.duplicate(true)
	m._rebuild_cards()
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	m._say("fight rhythm: %s.  Ctrl+Z undoes it in one step" % msg)
	compute()
	_panel()
