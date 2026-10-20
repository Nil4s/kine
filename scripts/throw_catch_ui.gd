## throw_catch_ui.gd - I27: the command "Throw to...". At the playhead the held prop is let go with the hand's velocity and spin,
## the ballistic arc and the catch are solved (scripts/throw_catch.gd), the panel says what it found (or why it is red), the arc is
## drawn in the view with a tick per frame and the catch point, Preview plays it on a copy, Accept writes it as ONE undo step.
## Kept out of main.gd: main makes one (main.tc_ui), lists its command and calls tick() each frame.
class_name ThrowCatchUI
extends RefCounted

const TICK := 0.025     # m: half the size of a frame's tick mark
const RING := 0.09      # m: the catch ring's radius (a little over a palm)

var m: Node
var pl: Dictionary = {}       # the plan on show
var pi := -1
var catcher: Dictionary = {}
var pv: Scene = null          # the preview's copy of the scene ("not previewing" = null)
var pv_t := 0.0
var pv_end := 0.0
var arc: MeshInstance3D = null
var verts := 0                # vertices in the last drawing (tests)


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Throw to...", "", show, "throw toss catch juggle ballistic arc gravity release prop ball hand flight spin",
		false, "lets the held prop go at the playhead with the hand's velocity and spin, solves the ballistic arc (g = 9.81 m/s^2, no drag) and the catch by the other hand: the hand is placed there by IK and the prop re-attached. Red when no catch is possible, saying why. Preview, then Accept (one undo step) (ROADMAP I27)")


## the prop held at the playhead (the picked one if it is held, else the first carry going on)
func held_prop() -> int:
	var t: float = snappedf(m.playhead, 1.0 / m.S.fps)
	if m.sel_prop >= 0 and not ThrowCatch.held(m.S, m.B, m.sel_prop, t).is_empty():
		return m.sel_prop
	for c in m.S.carries():
		if not ThrowCatch.held(m.S, m.B, int(c["prop"]), t).is_empty():
			return int(c["prop"])
	return -1


## the catching hand: the picked hand when it is not the one holding, else the holding body's other hand
func pick_catcher(hd: Dictionary) -> Dictionary:
	var holders: Array = (hd["c"]["hands"] as Array).map(func(h): return ThrowCatch.tip_of(String(h)))
	var want := LimbIK.limb_of(m.sel)
	var tip := ""
	if want in ["hand_l", "hand_r"] and not want in holders:
		tip = want
	else:
		for h in ["hand_l", "hand_r"]:
			if not h in holders:
				tip = h
				break
	return {"S": m.S, "B": m.B, "hand": tip}


func compute() -> Dictionary:
	var p := held_prop()
	if p < 0:
		return {"ok": false, "why": "no prop is held at the playhead: Pick up a prop on a card, move the playhead after it, then Throw to..."}
	pi = p
	var t: float = snappedf(m.playhead, 1.0 / m.S.fps)
	var hd := ThrowCatch.held(m.S, m.B, p, t)
	catcher = pick_catcher(hd)
	if String(catcher["hand"]) == "":
		return {"ok": false, "why": "both hands hold the prop: there is no free hand here to catch it; another fighter's hand can (not in this panel yet)"}
	var r := ThrowCatch.plan(m.S, m.B, p, t, catcher)
	m.S.apply(m.B, m.playhead)   # the plan posed the body at other times
	return r


func show() -> void:
	halt()
	pl = compute()
	if pl.get("keys", null) == null:
		m._say(String(pl["why"]))
		clear_arc()
		return
	_panel()
	draw_arc(pl)
	if bool(pl["ok"]):
		preview()
	else:
		m._say("Throw to... is red: " + String(pl["why"]))


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("THROW TO...  -  %s" % ("catch at " + Units.time(float(pl["t_catch"]), m.S.fps) if bool(pl["ok"]) else "red"), 18, "heading" if bool(pl["ok"]) else "fail")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", close))
	var v0: Vector3 = pl["v0"]
	var w: Vector3 = pl["w"]
	var l1: Label = m._label("Release at %s: speed %.2f m/s (%.2f m/s up), spin %.0f deg/s about the vertical (all from the hand, one frame apart). Arc: ballistic, g = 9.81 m/s^2, no air drag." % [
		Units.time(float(pl["t0"]), m.S.fps), v0.length(), v0.y, rad_to_deg(w.y)], 13, "text:0.6", true)
	l1.name = "tc_release"
	l1.custom_minimum_size = Vector2(380, 0)
	L.add_child(l1)
	var l2: Label
	if bool(pl["ok"]):
		l2 = m._label("The %s hand catches it %d frames later (%s) at %.0f cm from the shoulder (reach %.0f cm); the prop moves at %.1f m/s there, the hand travels at %.1f m/s (heuristic human limit %.0f m/s)." % [
			"left" if String(pl["tip"]).ends_with("_l") else "right", int(pl["catch_n"]), Units.time(float(pl["t_catch"]) - float(pl["t0"]), m.S.fps),
			(pl["catch_pos"] as Vector3).distance_to(m.B.P[ThrowCatch.root_of(m.B, String(pl["tip"]))]) * 100.0, float(pl["arm"]) * 100.0,
			float(pl["speed_prop"]), float(pl["speed_hand"]), ThrowCatch.V_HAND_MAX], 14, "text:0.85", true)
	else:
		l2 = m._label("No catch: " + String(pl["why"]), 14, "fail", true)
	l2.name = "tc_result"
	l2.custom_minimum_size = Vector2(380, 0)
	L.add_child(l2)
	var row := HBoxContainer.new()
	var pb: Button = m._button("Preview", preview, "play the throw on a copy; the scene is not changed")
	pb.name = "tc_preview"
	var ab: Button = m._button("Accept", accept, "write the flight keys and the catching hand; one undo step")
	ab.name = "tc_accept"
	ab.disabled = not bool(pl["ok"])
	row.add_child(pb)
	row.add_child(ab)
	L.add_child(row)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(400, 190)
	m.ui_find.visible = true


func close() -> void:
	halt()
	clear_arc()
	m._close_findings()


## stop the preview and put the view back as the playhead has it
func halt() -> void:
	if pv != null:
		pv = null
		m._ps().apply(m.B, m.playhead)
		m._props_pose()
		m._refresh()


func preview() -> void:
	if pl.is_empty() or not bool(pl.get("ok", false)):
		return
	pv = ThrowCatch.copy_scene(m.S)
	ThrowCatch.commit(pv, pi, pl, {"S": pv, "B": m.B, "hand": catcher["hand"]})
	pv_t = maxf(0.0, float(pl["t0"]) - 0.4)
	pv_end = float(pl["t_catch"]) + 0.6
	m.playing = false
	m._say("throw preview: release at %s, catch at %s (the scene is not changed)" % [Units.time(float(pl["t0"]), m.S.fps), Units.time(float(pl["t_catch"]), m.S.fps)])


func tick(dt: float) -> void:
	if pv == null:
		return
	pv_t += dt
	if pv_t >= pv_end:
		halt()
		return
	pv.apply(m.B, pv_t)
	var pa := pv.props_at(pv_t, m.B)
	m._refresh()
	for i in pa.size():
		var n: Node = m.ui_props_root.get_node_or_null("prop_%d" % i)
		if n != null:
			Props.pose_node(n as Node3D, pa[i])


func accept() -> void:
	halt()
	var fresh := compute()
	if not bool(fresh.get("ok", false)):
		m._say("Throw to... is red, nothing written: " + String(fresh.get("why", "")))
		return
	commit(fresh)


## write a plan: ONE undo step
func commit(plan: Dictionary) -> void:
	pl = plan
	m._step_hint = "Throw to..."
	m._push_undo()
	ThrowCatch.commit(m.S, pi, pl, catcher)
	m._rebuild_cards()
	m._props_show()
	m.S.apply(m.B, m.playhead)
	m._props_pose()
	m._refresh()
	m._doc_line()
	m._say("threw the %s at %s and caught it %d frames later with the %s hand (Ctrl+Z takes it all back)" % [m._prop_name(pi),
		Units.time(float(pl["t0"]), m.S.fps), int(pl["catch_n"]), "left" if String(pl["tip"]).ends_with("_l") else "right"])
	draw_arc(pl)
	m.ui_find.visible = false


# ---------------------------------------------------------------- the arc in the view

func clear_arc() -> void:
	if arc != null:
		arc.queue_free()
		arc = null
	verts = 0


## the arc as a line, a cross at every frame (the ticks: their spacing is the speed), the release mark and the catch ring
func draw_arc(p: Dictionary) -> void:
	clear_arc()
	if p.get("keys", null) == null:
		return
	arc = MeshInstance3D.new()
	arc.name = "throw_arc"
	var im := ImmediateMesh.new()
	arc.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.render_priority = 3
	arc.material_override = mat
	var ok: bool = bool(p.get("ok", false))
	var line_c: Color = Tok.c("heading") if ok else Tok.c("fail")
	var tick_c: Color = Tok.c("say")
	var catch_c: Color = Tok.c("warn")
	var keys: Array = p["keys"]
	verts = 0
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in keys.size() - 1:
		im.surface_set_color(line_c)
		im.surface_add_vertex(keys[i]["pos"])
		im.surface_set_color(line_c)
		im.surface_add_vertex(keys[i + 1]["pos"])
		verts += 2
	for k in keys:
		var q: Vector3 = k["pos"]
		for ax in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			im.surface_set_color(tick_c)
			im.surface_add_vertex(q - ax * TICK)
			im.surface_set_color(tick_c)
			im.surface_add_vertex(q + ax * TICK)
			verts += 2
	if ok:
		var c: Vector3 = p["catch_pos"]
		for ax2 in [[Vector3.RIGHT, Vector3.UP], [Vector3.UP, Vector3.BACK], [Vector3.RIGHT, Vector3.BACK]]:
			for s in 24:
				var a0 := TAU * s / 24.0
				var a1 := TAU * (s + 1) / 24.0
				im.surface_set_color(catch_c)
				im.surface_add_vertex(c + (ax2[0] as Vector3) * cos(a0) * RING + (ax2[1] as Vector3) * sin(a0) * RING)
				im.surface_set_color(catch_c)
				im.surface_add_vertex(c + (ax2[0] as Vector3) * cos(a1) * RING + (ax2[1] as Vector3) * sin(a1) * RING)
				verts += 2
	im.surface_end()
	m.add_child(arc)
