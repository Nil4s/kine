## REAL-MOCAP CHECK panel (ROADMAP I48; the maths: scripts/mocap_check.gd). "Real-mocap check" scores every card by how often real people
## (CMU motion capture) stand in the same shoulder + elbow, hip + knee and spine-chain angles, lists the cards (least typical first),
## and for a pose below the line draws the NEAREST REAL POSE as a ghost beside the body at the playhead, with the joints that differ most
## in degrees. It only reads: the scene, the body and the undo list are not touched.
class_name MocapCheckUI
extends RefCounted

const GHOST_OFFSET := 0.9   # m, to the body's right in the world (+x) so both can be seen whole
const GHOST_A := 0.55

var m: Node
var rep: Dictionary = {}
var root: Node3D = null
var _g: Dictionary = {}
var _gb: Body = null
var ms := 0.0
var shown := -1   # the card whose real pose the ghost shows (-1 = none)


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Real-mocap check", "", show, "real motion capture pose typical statistics cmu shoulder elbow hip knee spine unnatural impossible ghost nearest real pose",
		false, "scores each card's pose against real motion capture (CMU): shoulder + elbow, hip + knee and spine chain; a pose that fewer than 1% of real frames reach is flagged with the nearest real pose as a ghost beside the body and the joints that differ most (degrees); nothing changes")


func compute() -> void:
	var t0 := Time.get_ticks_usec()
	rep = MocapCheck.analyze(m.S, m.B)
	ms = float(Time.get_ticks_usec() - t0) / 1000.0
	shown = -1


func show() -> void:
	if m.S.cards.is_empty():
		m._say("Real-mocap check needs a card: press Enter to add the body as a card, or open a scene in the list below")
		return
	compute()
	if not rep.get("ok", false):
		m._say(String(rep.get("msg", "")) + ". Run python tools/i48_build.py to make it")
		return
	_panel()
	tick(0.0)


func _order() -> Array:
	var idx := []
	for r in rep.get("cards", []):
		idx.append(int(r["i"]))
	var cards: Array = rep.get("cards", [])
	idx.sort_custom(func(a, b): return float(cards[a]["pct"]) < float(cards[b]["pct"]))
	return idx


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var cards: Array = rep["cards"]
	var nbad: int = rep["flagged"]
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("REAL-MOCAP CHECK  -  " + ("%d of %d poses are not ones people make" % [nbad, cards.size()] if nbad > 0 else "every pose is one people make"), 16, "warn" if nbad > 0 else "heading", true)
	title.name = "mc_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", _close))
	var exp: Label = m._label("Score = the percent of real motion-capture frames (%d frames, %d clips of CMU walking, boxing, kicks, martial-arts walks) that stand in a less-visited place for the joint group; 0 = never seen near it. Below %.0f%% a pose is flagged. Unseen is not proof it is impossible: the clips hold no gymnastics beyond a few kicks and jumps." % [int(MocapCheck.stat()["frames"]), int(MocapCheck.stat()["clips"]), MocapCheck.FLAG_PCT], 12, "text:0.6", true)
	exp.custom_minimum_size = Vector2(380, 0)
	L.add_child(exp)
	var shown_rows := 0
	for i in _order():
		var r: Dictionary = cards[i]
		if shown_rows >= 6 and not bool(r["flag"]):
			break
		shown_rows += 1
		var txt := "card %d  %s   typical %.0f%%  (%s)" % [i + 1, r["name"], float(r["pct"]), String(r["label"])]
		if bool(r["flag"]):
			var nr: Dictionary = r["near"]
			var bits := []
			for d in (nr["top"] as Array).slice(0, 3):
				bits.append("%s %.0f deg" % [d[0], float(d[1])])
			txt += "\nFLAGGED. Nearest real pose is %.0f deg off on average (RMS over 19 joints); differ most: %s" % [float(nr["rms"]), ", ".join(PackedStringArray(bits))]
		var b: Button = m._button(txt, _pick.bind(i), "go to this card%s" % ("; the nearest real pose is the ghost beside the body" if bool(r["flag"]) else ""))
		b.name = "mc_row_%d" % i
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(380, 0)
		L.add_child(b)
	L.add_child(m._label("computed in %.0f ms; the ghost beside the body is the nearest real pose of the card at the playhead" % ms, 12, "text:0.5", true))
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(440, clampf(170.0 + 62.0 * minf(6.0 + nbad, 9.0), 200.0,
		minf(560.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("real-mocap check: " + String(rep.get("msg", "")))


func _pick(i: int) -> void:
	m.playing = false
	m.playhead = float(m.S.times()[i][1])
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	tick(0.0)


## the card the playhead stands on (the last one that has arrived)
func card_at(t: float) -> int:
	var tm: Array = m.S.times()
	var best := 0
	for i in tm.size():
		if float(tm[i][1]) <= t + 0.0005:
			best = i
	return best


func tick(_dt: float) -> void:
	if rep.is_empty() or not rep.get("ok", false) or not m.ui_find.visible:
		_hide()
		return
	var cards: Array = rep["cards"]
	var i := card_at(float(m.playhead))
	if i >= cards.size() or not bool(cards[i]["flag"]):
		_hide()
		shown = -1
		return
	_build()
	var r: Dictionary = cards[i]
	var real: Dictionary = (r["near"]["ang"] as Dictionary).duplicate()
	for j in MocapCheck.NEAR_SKIP:
		real[j] = (r["ang"] as Dictionary)[j]   # faces the way the body faces, wears the card's own feet
	var S := MocapCheck.pose_scene(real)
	S.apply(_gb, 0.0)
	_gb.fk()
	var n := _g["node"] as Node3D
	var mine: Vector3 = m.B.P["pelvis"]
	var gp: Vector3 = _gb.P["pelvis"]
	n.position = Vector3(mine.x + GHOST_OFFSET - gp.x, 0.0, mine.z - gp.z)
	Overlays.pose_skeleton(_g["skel"], _g["idx"], _gb)
	n.visible = true
	shown = i


func _build() -> void:
	if root != null and is_instance_valid(root):
		return
	root = Node3D.new()
	root.name = "mocap_check_ghost"
	m.stage_root.add_child(root)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	var c := Tok.c("fv_ok")
	c.a = GHOST_A
	mat.albedo_color = c
	var mq := Overlays.mannequin(root, mat)
	_g = {"node": mq[0], "skel": mq[1], "idx": mq[2], "mat": mat}
	_gb = Body.new()
	_gb.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	if _gb.body != m.S.body:
		_gb.set_proportions(m.S.body)
	_gb.fk()


func _hide() -> void:
	if not _g.is_empty() and is_instance_valid(_g["node"]):
		(_g["node"] as Node3D).visible = false


func _close() -> void:
	rep = {}
	shown = -1
	_hide()
	m._close_findings()
