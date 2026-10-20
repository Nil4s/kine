## GAZE DIRECTOR panel (ROADMAP I41; the maths: scripts/gaze.gd). With two fighters the active one is the one whose head and neck are keyed: it
## looks at the other's upper chest, glances at each incoming weapon, and (switch "Telegraph glance") looks at the target 0.2 s before its own
## strike. The panel shows the plan and the share of frames the gaze sits on the chest; Preview plays the clip with the gaze (the scene is not
## changed), Accept writes the neck and head keys as ONE undo step.
class_name GazeUI
extends RefCounted

var m: Node
var a_k := 0
var d_k := 1
var tele := true
var plan: Dictionary = {}
var habit: Dictionary = {}
var share_now := 0.0
var share_new := 0.0
var pv := false
var pv_t := 0.0
var pv_t1 := 0.0
var pv_sc: Scene = null


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Gaze director", "", show, "gaze look eyes head neck chest opponent weapon glance telegraph fighter focus attention",
		false, "with two fighters: where each fighter looks over the clip (the opponent's upper chest, a glance at each incoming weapon, an optional telegraph glance at the target 0.2 s before a strike); preview, then Accept = one undo step")


func halt() -> void:
	pv = false
	pv_sc = null


func _xf() -> Transform3D:
	return (m.actors_rt[a_k]["xf"] as Transform3D).affine_inverse() * (m.actors_rt[d_k]["xf"] as Transform3D)


func _fps() -> int:
	return maxi(1, (m.actors_rt[a_k]["S"] as Scene).fps)


func compute() -> void:
	m._actors_sync()
	var A: Scene = m.actors_rt[a_k]["S"]
	var D: Scene = m.actors_rt[d_k]["S"]
	habit = Gaze.learn(A, D, _xf(), _fps())
	plan = Gaze.compute(A, D, _xf(), tele, habit, _fps())
	share_now = float(Gaze.measure(A, D, _xf(), _fps())["on_chest"])
	share_new = float(Gaze.measure(Gaze.applied(A, plan), D, _xf(), _fps())["on_chest"])


func show() -> void:
	m._actors_sync()
	if m.actors_rt.size() < 2:
		m._say("gaze director needs two fighters: 'Actor: add a second fighter' first (the active one gets the gaze keys, the other is looked at)")
		return
	a_k = m.actor_on
	d_k = 1 - a_k
	compute()
	_panel()


func set_tele(on: bool) -> void:
	tele = on
	halt()
	compute()
	_panel()


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("GAZE DIRECTOR  -  %s" % String(plan.get("msg", "")), 14, "heading", true)
	title.name = "gz_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", _close))
	L.add_child(m._label("Default gaze: the opponent's upper chest (skilled karate and boxing players fixate the head and chest region, Williams & Elliott 1999; Ripoll 1995 - from memory, a stated default). A short glance at each incoming weapon, and with the telegraph switch on a glance at the target %.1f s before the fighter's own strike. Written as neck and head keys within the neck's limits. Preview changes nothing, Accept is one undo step." % Gaze.TELEGRAPH_LEAD,
		13, "text:0.6", true))
	L.add_child(m._label("Habit: %s (%s%s)" % ["glance at the incoming weapon" if habit.get("weapon", true) else "no weapon glance", String(habit.get("source", "default")),
		", %d strikes read from your head keys" % int(habit["n"]) if int(habit.get("n", 0)) > 0 else ""], 13, "text:0.85", true))
	var tb: Button = m._button("Telegraph glance: " + ("on" if tele else "off"), set_tele.bind(not tele), "look at the target of the fighter's own strike %.1f s before it lands (people do, and a defender can read it); off keeps the gaze on the chest" % Gaze.TELEGRAPH_LEAD)
	tb.name = "gz_tele"
	L.add_child(tb)
	var ev: Dictionary = plan.get("ev", {"tele": [], "weap": []})
	for w in ev["weap"]:
		L.add_child(m._label("weapon glance  %.2f-%.2f s  at the opponent's %s, strike lands %.2f s" % [float(w["t0"]), float(w["t1"]), String(w["tip"]).replace("_", " "), float(w["arrive"])], 13, "text:0.85", true))
	for w in ev["tele"]:
		L.add_child(m._label("telegraph glance  %.2f-%.2f s  at the target's %s, own strike lands %.2f s" % [float(w["t0"]), float(w["t1"]), String(w["part"]).replace("_", " "), float(w["arrive"])], 13, "text:0.85", true))
	var sl: Label = m._label("gaze on the chest (within %.0f cm): %.0f %% of frames now, %.0f %% with the plan" % [Gaze.ON_CHEST * 100.0, share_now * 100.0, share_new * 100.0], 13, "heading", true)
	sl.name = "gz_share"
	L.add_child(sl)
	var r2 := HBoxContainer.new()
	var pb: Button = m._button("Preview", preview, "play the clip with the gaze; the scene is not changed")
	pb.name = "gz_preview"
	var ab: Button = m._button("Accept", accept, "write the neck and head keys; one undo step")
	ab.name = "gz_accept"
	r2.add_child(pb)
	r2.add_child(ab)
	L.add_child(r2)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(420, clampf(260.0 + 26.0 * (ev["weap"].size() + ev["tele"].size()), 260.0,
		minf(520.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("gaze director: " + String(plan.get("msg", "")) + ".  Preview plays it, Accept writes it")


func _close() -> void:
	halt()
	m._close_findings()


func preview() -> void:
	if plan.is_empty() or not plan.get("ok", false):
		m._say("nothing to preview: open the Gaze director with two fighters and a clip of at least two cards first")
		return
	halt()
	pv_sc = Gaze.applied(m.actors_rt[a_k]["S"], plan)
	pv_t = 0.0
	pv_t1 = pv_sc.length()
	pv = true
	m.playing = false
	m._say("gaze director: previewing the gaze (the scene is not changed)")


func tick(dt: float) -> void:
	if not pv:
		return
	pv_t += dt
	if pv_t >= pv_t1:
		halt()
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		return
	pv_sc.apply(m.actors_rt[a_k]["B"], pv_t)
	(m.actors_rt[d_k]["S"] as Scene).apply(m.actors_rt[d_k]["B"], pv_t)
	m._refresh()


func accept() -> void:
	if plan.is_empty() or not plan.get("ok", false):
		m._say("nothing to accept: open the Gaze director with two fighters and a clip of at least two cards first")
		return
	halt()
	var g := plan
	m._actors_sync()
	m._step_hint = "Gaze director"
	m._push_undo()
	var S: Scene = m.actors_rt[a_k]["S"]
	for j in Gaze.JOINTS:
		S.part_keys[j] = (g["keys"][j] as Array).duplicate(true)
	m._rebuild_cards()
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	m._say("gaze director: %s.  Ctrl+Z undoes it in one step" % String(g["msg"]))
	compute()
	_panel()
