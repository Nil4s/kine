## AUTO OPPONENT panel (ROADMAP I37; the maths: scripts/auto_opponent.gd). Lists every strike of the hero's clip with fighter 2's answer
## (strike -> response -> why). Preview plays the hero with a GHOST of fighter 2 doing the new track (nothing is written); Accept
## replaces fighter 2's cards with it in ONE undo step.
class_name AutoOpponentUI
extends RefCounted

const GHOST_A := 0.5

var m: Node
var res: Dictionary = {}
var hab: Dictionary = {}      # Nick's habits (AutoOpponent.habits); a test may set it before show()
var use_hab := false          # true = hab was given, do not read the scenes folder
var playing := false
var pv_t := 0.0
var pv_end := 0.0
var n_undo := 0
var root: Node3D
var _g: Dictionary = {}       # the ghost: {node, skel, idx, mat}
var _gb: Body


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Auto opponent", "", show, "auto opponent fighter 2 reaction block parry slip step back take the hit counter choreography generate answer strikes",
		false, "with two fighters: for each strike of the hero's clip, fighter 2's answer (block, parry, slip, step back or taking the hit) chosen by what your own clips do most for that strike and timed so a person could do it (0.2 s to react); Preview ghosts fighter 2, Accept replaces its cards in one undo step (Innovations I37)")


func halt() -> void:
	playing = false


func _hero() -> Dictionary:
	return m.actors_rt[0]


func _other() -> Dictionary:
	return m.actors_rt[1]


## the plan for the scene as it is. Nothing is written
func show() -> Dictionary:
	m._actors_sync()
	if m.actors_rt.size() < 2:
		m._say("Auto opponent: needs two fighters: 'Actor: add a second fighter' first, then draw the hero's strikes")
		return {"ok": false}
	if not use_hab:
		hab = AutoOpponent.habits()
	var A: Dictionary = _hero()
	var D: Dictionary = _other()
	res = AutoOpponent.plan(A["S"], A["xf"], D["S"], D["xf"], hab)
	if not bool(res["ok"]):
		m._say("Auto opponent: " + String(res["why"]))
		_ghost_hide()
		return res
	n_undo = m.undo.size()
	_ghost_build()
	_panel()
	_ghost_pose(float(m.playhead))
	return res


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var items: Array = res["items"]
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("AUTO OPPONENT  -  %s" % String(res["msg"]), 14, "heading", true)
	title.name = "ao_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", _close))
	var nd := int(hab.get("_files", 0))
	var exp: Label = m._label("Fighter 2 answers each strike the way your own two-fighter clips answer that kind of strike (%d clip%s with two fighters read, the scenes folder is untouched); with no data for a kind a default order stands. A defence must start 0.2 s or more after the wind-up shows and be in place by the hit, or he takes it." % [
		nd, "" if nd == 1 else "s"], 12, "text:0.6", true)
	exp.custom_minimum_size = Vector2(380, 0)
	L.add_child(exp)
	for k in items.size():
		var it: Dictionary = items[k]
		var rs := String(it["resp"])
		var txt := ""
		if rs == "NONE":
			txt = "STRIKE %d  %s at %.2f s  ->  no answer: %s" % [k + 1, it["kind"], it["contact"], it["why"]]
		elif rs == "HIT":
			txt = "STRIKE %d  %s at %.2f s (shows %.2f s)  ->  TAKES THE HIT: %s" % [k + 1, it["kind"], it["contact"], it["readable"], it["why"]]
		else:
			txt = "STRIKE %d  %s at %.2f s (shows %.2f s)  ->  %s starts %.2f s, in place %.2f s  -  why: %s" % [k + 1, it["kind"], it["contact"], it["readable"], rs, it["start"], it["t"], it["why"]]
		var lb: Label = m._label(txt, 13, "fail" if rs == "HIT" else ("warn" if rs == "NONE" else "text:0.8"), true)
		lb.name = "ao_row_%d" % k
		lb.custom_minimum_size = Vector2(420, 0)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		L.add_child(lb)
	var r2 := HBoxContainer.new()
	var pb: Button = m._button("Preview", preview, "play the hero with a ghost of fighter 2 doing the new track; the scenes are not changed")
	pb.name = "ao_preview"
	var ab: Button = m._button("Accept", accept, "replace fighter 2's cards with the new track; one undo step")
	ab.name = "ao_accept"
	r2.add_child(pb)
	r2.add_child(ab)
	L.add_child(r2)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(460, clampf(150.0 + 62.0 * items.size(), 220.0,
		minf(560.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("Auto opponent: " + String(res["msg"]) + ".  Preview ghosts fighter 2, Accept replaces its cards (one undo step)")


func _close() -> void:
	halt()
	res = {}
	_ghost_hide()
	m._close_findings()


func preview() -> void:
	if res.is_empty() or not bool(res.get("ok", false)):
		m._say("Auto opponent: nothing to preview: press 'Auto opponent' first")
		return
	pv_t = 0.0
	pv_end = maxf(float((_hero()["S"] as Scene).length()), float((res["scene"] as Scene).length()))
	playing = true
	m.playing = false
	_ghost_pose(0.0)
	m._say("Auto opponent: previewing fighter 2's new track as a ghost (the scenes are not changed)")


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
		(m.actors_rt[k]["S"] as Scene).apply(m.actors_rt[k]["B"], pv_t)
	_ghost_pose(pv_t)
	m._refresh()


## end of a refresh: an edit since the plan was made drops it; else the ghost stands at the playhead (or the preview's time)
func refresh() -> void:
	if res.is_empty():
		return
	if m.undo.size() != n_undo:
		res = {}
		_ghost_hide()
		return
	_ghost_pose(pv_t if playing else float(m.playhead))


## ONE undo step: fighter 2's cards become the plan's
func accept() -> Dictionary:
	if res.is_empty() or not bool(res.get("ok", false)):
		m._say("Auto opponent: nothing to accept: press 'Auto opponent' first")
		return {"ok": false}
	halt()
	m._actors_sync()
	if m.actors_rt.size() < 2:
		return {"ok": false}
	var msg := String(res["msg"])
	var cards: Array = (res["scene"] as Scene).cards.duplicate(true)
	m._step_hint = "Auto opponent"
	m._push_undo()   # (the snapshot holds every fighter's cards)
	(_other()["S"] as Scene).cards = cards
	m.sj.log("auto opponent", "accept", -1, {}, m.undo.size())
	m._rebuild_cards()
	m._ps().apply(m.B, m.playhead)
	_ghost_hide()
	res = {}
	m._refresh()
	m._say("Auto opponent: %s.  Ctrl+Z undoes it in one step" % msg)
	return {"ok": true}


# ---------------------------------------------------------------- the ghost

func _ghost_build() -> void:
	if root == null or not is_instance_valid(root):
		root = Node3D.new()
		root.name = "auto_opponent_ghost"
		m.stage_root.add_child(root)
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		var mq := Overlays.mannequin(root, mat)
		_g = {"node": mq[0], "skel": mq[1], "idx": mq[2], "mat": mat}
	var col: Color = Tok.c("mk_gold")
	col.a = GHOST_A
	(_g["mat"] as StandardMaterial3D).albedo_color = col
	_gb = Counter.scratch(res["scene"])


func _ghost_hide() -> void:
	if not _g.is_empty() and is_instance_valid(_g["node"]):
		(_g["node"] as Node3D).visible = false


func _ghost_pose(t: float) -> void:
	if res.is_empty() or _g.is_empty() or _gb == null or not is_instance_valid(_g["node"]) or m.actors_rt.size() < 2:
		return
	(res["scene"] as Scene).apply(_gb, t)
	_gb.fk()
	var n := _g["node"] as Node3D
	n.transform = _other()["xf"]
	Overlays.pose_skeleton(_g["skel"], _g["idx"], _gb)
	n.visible = true
