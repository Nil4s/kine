## FIGHT DISTANCE KEEPER panel (ROADMAP I18; the maths: scripts/distance_keeper.gd). With two fighters, the active one attacks and the other
## defends (as the fight phrase does). The panel lists every strike with its class, reach and gap in numbers; the timeline wears a colour band
## per strike (red = jammed, amber = out of range, blue = in range). "Slide the defender" on a flagged row builds the fix; Preview plays
## the defender with the slide (the scene is not changed), Accept writes it as ONE undo step on the defender.
class_name DistanceKeeperUI
extends RefCounted

var m: Node
var a_k := 0           # attacker (actors_rt index)
var d_k := 1           # defender
var rep: Dictionary = {}
var sel := -1
var fx: Dictionary = {}
var pv: Scene = null
var pv_t := 0.0
var pv_end := 0.0


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Fight distance keeper", "", show, "distance range jammed too close too far reach strike fighters defender slide step spacing gap fight",
		false, "with two fighters: the gap between each strike's tip and the other fighter against the strike's measured reach; jammed / out of range / in range on the timeline; Slide the defender fixes a flagged one (feet planted, preview, then Accept = one undo step)")


func halt() -> void:
	pv = null


func clear_overlay() -> void:
	rep = {}
	fx = {}
	sel = -1
	pv = null
	_overlay()


func _xf() -> Transform3D:
	return (m.actors_rt[a_k]["xf"] as Transform3D).affine_inverse() * (m.actors_rt[d_k]["xf"] as Transform3D)


func _fps() -> int:
	return maxi(1, (m.actors_rt[a_k]["S"] as Scene).fps)


func compute() -> void:
	m._actors_sync()
	rep = DistanceKeeper.analyze(m.actors_rt[a_k]["S"], m.actors_rt[d_k]["S"], _xf(), _fps())
	fx = {}
	sel = -1
	_overlay()


func _overlay() -> void:
	var tl = m.ui_timeline
	if tl == null:
		return
	var bands := []
	for s in rep.get("spans", []):
		bands.append({"t0": float(s["t0"]), "t1": float(s["t1"]), "cls": String(s["cls"])})
	tl.dk = bands
	tl.queue_redraw()


func show() -> void:
	m._actors_sync()
	if m.actors_rt.size() < 2:
		m._say("the distance keeper needs two fighters: 'Actor: add a second fighter' first (the active one attacks, the other defends)")
		return
	a_k = m.actor_on
	d_k = 1 - a_k
	compute()
	_panel()


func _line(s: Dictionary) -> String:
	var cls := String(s["cls"])
	var nm := "JAMMED" if cls == "jammed" else ("OUT OF RANGE" if cls == "out" else "in range")
	var t := "card %d  %.2f-%.2f s  %s  reach %.0f cm (%s)  gap at start %.0f cm" % [int(s["card"]) + 1, float(s["t0"]), float(s["t1"]), nm, float(s["reach"]) * 100.0,
		String(s["tip"]).replace("_", " "), float(s["root_gap"]) * 100.0]
	if cls == "jammed":
		t += "  (under %.0f%% of the reach = %.0f cm)" % [DistanceKeeper.JAM * 100.0, DistanceKeeper.JAM * float(s["reach"]) * 100.0]
	t += "  closest %.1f cm at %.2f s" % [float(s["miss"]) * 100.0, float(s["t_min"])]
	return t


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var spans: Array = rep.get("spans", [])
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("FIGHT DISTANCE  -  %s" % String(rep.get("msg", "")), 14, "warn" if int(rep.get("flagged", 0)) > 0 else "heading", true)
	title.name = "dk_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", _close))
	L.add_child(m._label("%s attacks, %s defends. Jammed: the target is closer than 60%% of the strike's measured reach when it starts. Out of range: the tip's closest approach misses by more than 5 cm. Slide the defender moves him with steps (feet planted); Preview changes nothing, Accept is one undo step." % [
		m.actors_rt[a_k]["name"], m.actors_rt[d_k]["name"]], 13, "text:0.6", true))
	for k in spans.size():
		var s: Dictionary = spans[k]
		var row := HBoxContainer.new()
		var cls := String(s["cls"])
		var lb: Label = m._label(_line(s), 13, "text:0.85" if cls == "in" else ("fail" if cls == "jammed" else "warn"), true)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lb.custom_minimum_size = Vector2(300, 0)
		row.add_child(lb)
		if cls != "in":
			var b: Button = m._button(("> " if sel == k else "") + "Slide the defender", select.bind(k), "work out how far to slide the defender (with steps, feet planted) so this strike is in range")
			b.name = "dk_slide_%d" % k
			row.add_child(b)
		L.add_child(row)
	if not fx.is_empty():
		var l2: Label = m._label("FIX  -  " + String(fx["msg"]) + ("; then the strike is %s (closest %.1f cm)" % ["in range" if fx["after"]["cls"] == "in" else String(fx["after"]["cls"]), float(fx["after"]["miss"]) * 100.0]), 13, "heading", true)
		l2.name = "dk_fix"
		l2.custom_minimum_size = Vector2(380, 0)
		L.add_child(l2)
		var r2 := HBoxContainer.new()
		var pb: Button = m._button("Preview", preview, "play the defender with the slide; the scene is not changed")
		pb.name = "dk_preview"
		var ab: Button = m._button("Accept", accept, "write the slide; one undo step")
		ab.name = "dk_accept"
		r2.add_child(pb)
		r2.add_child(ab)
		L.add_child(r2)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(420, clampf(200.0 + 40.0 * spans.size() + (90.0 if not fx.is_empty() else 0.0), 220.0,
		minf(520.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("fight distance: " + String(rep.get("msg", "")) + (".  'Slide the defender' on a flagged strike builds the fix" if int(rep.get("flagged", 0)) > 0 else ""))


func select(k: int) -> void:
	var f := DistanceKeeper.fix(m.actors_rt[a_k]["S"], m.actors_rt[d_k]["S"], _xf(), _fps(), k, rep)
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
		m._say("nothing to preview: press 'Slide the defender' on a flagged strike first")
		return
	pv = (fx["scene"] as Scene).clone()
	pv_t = 0.0
	pv_end = maxf(pv.length(), (m.actors_rt[a_k]["S"] as Scene).length())
	m.playing = false
	m._say("fight distance: previewing the slide (the scene is not changed)")


func tick(dt: float) -> void:
	if pv == null:
		return
	pv_t += dt
	if pv_t >= pv_end:
		pv = null
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		return
	(m.actors_rt[a_k]["S"] as Scene).apply(m.actors_rt[a_k]["B"], pv_t)
	pv.apply(m.actors_rt[d_k]["B"], pv_t)
	m._refresh()


func accept() -> void:
	if fx.is_empty():
		m._say("nothing to accept: press 'Slide the defender' on a flagged strike first")
		return
	pv = null
	var sc: Scene = fx["scene"]
	var msg := String(fx["msg"])
	m._actors_sync()
	m._step_hint = "Slide the defender"
	m._push_undo()   # (the snapshot holds every fighter's cards: the attacker stays the active one)
	(m.actors_rt[d_k]["S"] as Scene).cards = sc.cards.duplicate(true)
	m._rebuild_cards()
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	m._say("fight distance: %s.  Ctrl+Z undoes it in one step" % msg)
	compute()
	_panel()
