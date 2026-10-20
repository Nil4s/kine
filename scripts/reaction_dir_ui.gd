## REACTION DIRECTION panel (ROADMAP I33; the maths: scripts/reaction_dir.gd). With two fighters, every contact on a body part is judged: does the struck
## body go along the blow's impulse, turn the right way, start at the contact and move as much as the impulse says. A row per hit with the numbers
## (angle, sense, onset ms, ratio), a badge per hit on the timeline (blue = fine, red = flagged), and two arrows at the contact in the view of the
## selected hit: the IMPULSE (orange) and the REACTION (the momentum the body took, green when it follows the impulse, red when not), both at 0.04 m
## per N s. "Fix this reaction" builds the fix (retime the early start, or make the reaction again from the hit physics); Preview plays the struck
## fighter with it (the scene is not changed), Accept writes it as ONE undo step on the struck fighter.
class_name ReactionDirUI
extends RefCounted

const ARROW_PER_NS := 0.04

var m: Node
var rows := []       # [{"hit": row, "vk", "sk", "res": judge result}]
var sel := -1
var fx: Dictionary = {}
var pv: Scene = null
var pv_k := 0
var pv_t := 0.0
var pv_end := 0.0
var _arrows: Array = []   # the MeshInstance3Ds of the two arrows
var _node: Node3D


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Reaction direction", "", show, "reaction direction hit struck impulse push react wrong way flinch early pre-flinch onset rotation magnitude fighters physics",
		false, "with two fighters: for each hit, does the struck body go along the blow's impulse, turn about r x J the right way, start at the contact and move as much as J / mass says; flags on the timeline; Fix this reaction retimes or remakes it from the hit physics (preview, then Accept = one undo step)")


func halt() -> void:
	pv = null


func clear_overlay() -> void:
	rows = []
	fx = {}
	sel = -1
	pv = null
	_overlay()
	_draw_arrows()


func _bands() -> Array:
	var out := []
	var fps := 30.0
	for r in rows:
		var res: Dictionary = r["res"]
		if not res["ok"]:
			continue
		var t: float = res["t"]
		out.append({"t0": t - 0.5 / fps, "t1": t + 4.0 / fps, "cls": "bad" if res["bad"] else "ok",
			"txt": "%+.0f ms · %.0f° · x%.1f" % [float(res["onset_ms"]), float(res["angle"]) if not res["none"] else 180.0, float(res["ratio"])]})
	return out


func _overlay() -> void:
	var tl = m.ui_timeline
	if tl == null:
		return
	tl.rd = _bands()
	tl.queue_redraw()


func compute() -> void:
	m._actors_sync()
	var hs: Scene = (m.actors_rt[0]["S"] as Scene).clone()
	var others := []
	for i in range(1, m.actors_rt.size()):
		others.append({"name": m.actors_rt[i]["name"], "S": (m.actors_rt[i]["S"] as Scene).clone(), "xf": m.actors_rt[i]["xf"]})
	var hits: Array = m.call("_fighters_measure", hs, others)["hits"]
	rows = []
	for h in hits:
		if (h["kind"] != "hit" and h["kind"] != "struck") or Body.is_wep(String(h["on"])):
			continue
		var vk: int = 0 if h["by"] == "other" else int(h["vs"])
		var sk: int = int(h["vs"]) if h["by"] == "other" else 0
		var res := ReactionDir.judge(m.actors_rt[vk]["S"], m.actors_rt[vk]["B"], m.actors_rt[vk]["xf"], h, m.actors_rt[sk]["B"], m.actors_rt[sk]["S"])
		rows.append({"hit": h, "vk": vk, "sk": sk, "res": res})
	fx = {}
	sel = -1
	_overlay()
	_draw_arrows()


func flagged() -> int:
	var n := 0
	for r in rows:
		if r["res"]["bad"]:
			n += 1
	return n


func _msg() -> String:
	if rows.is_empty():
		return "no contact lands on a body part"
	return "%d hit%s judged, %d flagged" % [rows.size(), "" if rows.size() == 1 else "s", flagged()]


func show() -> void:
	m._actors_sync()
	if m.actors_rt.size() < 2:
		m._say("reaction direction needs two fighters: 'Actor: add a second fighter' first, then let a strike land on the other one")
		return
	compute()
	if not rows.is_empty():
		sel = 0
		_draw_arrows()
	_panel()


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("REACTION DIRECTION  -  %s" % _msg(), 14, "warn" if flagged() > 0 else "heading", true)
	title.name = "rd_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", _close))
	L.add_child(m._label("Direction: the struck body's velocity change within 45 deg of the impulse J. Rotation: the trunk turns about r x J. Onset: no rise in the struck spot's speed more than a frame before contact. Magnitude: the COM's velocity change within 0.5-2 of J / body mass. The limits are heuristics.", 13, "text:0.6", true))
	for k in rows.size():
		var res: Dictionary = rows[k]["res"]
		var row := HBoxContainer.new()
		var lb: Label = m._label(("> " if sel == k else "") + ReactionDir.line(res) + ((" - FLAGGED: " + ", ".join(res["flags"])) if res["bad"] else " - fine"), 13,
			"fail" if res["bad"] else "text:0.85", true)
		lb.name = "rd_row_%d" % k
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lb.custom_minimum_size = Vector2(300, 0)
		row.add_child(lb)
		var show_b: Button = m._button("Show", pick.bind(k), "put the playhead on this contact and draw the impulse and the reaction at it")
		show_b.name = "rd_show_%d" % k
		row.add_child(show_b)
		if res["bad"]:
			var b: Button = m._button("Fix this reaction", select.bind(k), "build the fix for this hit: retime an early reaction, or make the reaction again from the hit physics")
			b.name = "rd_fix_%d" % k
			row.add_child(b)
		L.add_child(row)
	if not fx.is_empty():
		var a: Dictionary = fx["after"]
		var l2: Label = m._label("FIX (%s)  -  %s; then %s" % [fx["kind"], fx["msg"], "fine" if not a["bad"] else "still flagged: " + ", ".join(a["flags"])], 13, "heading", true)
		l2.name = "rd_fix"
		l2.custom_minimum_size = Vector2(380, 0)
		L.add_child(l2)
		var r2 := HBoxContainer.new()
		var pb: Button = m._button("Preview", preview, "play the struck fighter with the fix; the scene is not changed")
		pb.name = "rd_preview"
		var ab: Button = m._button("Accept", accept, "write the fix; one undo step")
		ab.name = "rd_accept"
		r2.add_child(pb)
		r2.add_child(ab)
		L.add_child(r2)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(420, clampf(160.0 + 70.0 * rows.size() + (100.0 if not fx.is_empty() else 0.0), 220.0,
		minf(520.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("reaction direction: " + _msg() + (".  'Fix this reaction' on a flagged hit builds the fix" if flagged() > 0 else ""))


func pick(k: int) -> void:
	if k < 0 or k >= rows.size():
		return
	sel = k
	m.playing = false
	m.playhead = float(rows[k]["res"].get("t", rows[k]["hit"]["t"]))
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	_draw_arrows()
	_panel()


func select(k: int) -> void:
	var r: Dictionary = rows[k]
	var f := ReactionDir.fix(m.actors_rt[r["vk"]]["S"], m.actors_rt[r["vk"]]["B"], m.actors_rt[r["vk"]]["xf"], r["hit"], m.actors_rt[r["sk"]]["B"], r["res"], m.actors_rt[r["sk"]]["S"], m.myhits.chooser(m.actors_rt[r["vk"]]["S"].fps))
	if not f["ok"]:
		m._say(String(f["why"]))
		return
	sel = k
	fx = f
	fx["k"] = k
	_draw_arrows()
	_panel()


func _close() -> void:
	clear_overlay()
	m._close_findings()


func preview() -> void:
	if fx.is_empty():
		m._say("nothing to preview: press 'Fix this reaction' on a flagged hit first")
		return
	pv = (fx["scene"] as Scene).clone()
	pv_k = int(rows[int(fx["k"])]["vk"])
	pv_t = 0.0
	pv_end = maxf(pv.length(), (m.actors_rt[int(rows[int(fx["k"])]["sk"])]["S"] as Scene).length())
	m.playing = false
	m._say("reaction direction: previewing the fix (the scene is not changed)")


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
		if k == pv_k:
			pv.apply(m.actors_rt[k]["B"], pv_t)
		else:
			(m.actors_rt[k]["S"] as Scene).apply(m.actors_rt[k]["B"], pv_t)
	m._refresh()


func accept() -> void:
	if fx.is_empty():
		m._say("nothing to accept: press 'Fix this reaction' on a flagged hit first")
		return
	pv = null
	var sc: Scene = fx["scene"]
	var vk: int = int(rows[int(fx["k"])]["vk"])
	var msg := String(fx["msg"])
	var regen := String(fx["kind"]).contains("regenerate")   # only a reaction made again from the physics is shaped by my usual
	m._actors_sync()
	m._step_hint = "Fix this reaction"
	m._push_undo()   # (the snapshot holds every fighter's cards)
	var base_sc: Scene = (m.actors_rt[vk]["S"] as Scene).clone()
	(m.actors_rt[vk]["S"] as Scene).cards = sc.cards.duplicate(true)
	m.myhits.watch(vk, base_sc, m.actors_rt[vk]["S"], float(rows[int(fx["k"])]["hit"]["t"]), HitReaction.window_end(base_sc, float(rows[int(fx["k"])]["hit"]["t"])), float(rows[int(fx["k"])]["res"].get("Jn", 0.0)), m.undo.size())   # I46: my edits of it are lessons
	m._rebuild_cards()
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	m._say("reaction direction: %s.  Ctrl+Z undoes it in one step%s" % [msg, ("  (" + m.myhits.last_text + ")") if regen else ""])
	if regen:
		m._habit_note(m.myhits.last_text)
	compute()
	if not rows.is_empty():
		sel = 0
	_draw_arrows()
	_panel()


# ------------------------------------------------------------------------------------------------ the arrows at the contact

func _arrow(a: Vector3, b: Vector3, col: Color) -> void:
	var d := b - a
	var L := d.length()
	if L < 0.01:
		return
	var up := d / L
	var basis := Basis(Quaternion(Vector3.UP, up)) if up.dot(Vector3.UP) > -0.999 else Basis(Vector3.RIGHT, PI)
	var head := minf(0.09, L * 0.4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.render_priority = 3
	var shaft := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.011
	cm.bottom_radius = 0.011
	cm.height = L - head
	shaft.mesh = cm
	shaft.material_override = mat
	shaft.transform = Transform3D(basis, a + up * ((L - head) * 0.5))
	var tip := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.0
	tm.bottom_radius = 0.032
	tm.height = head
	tip.mesh = tm
	tip.material_override = mat
	tip.transform = Transform3D(basis, b - up * (head * 0.5))
	_node.add_child(shaft)
	_node.add_child(tip)


func _draw_arrows() -> void:
	if _node == null or not is_instance_valid(_node):
		_node = Node3D.new()
		_node.name = "rd_arrows"
		m.add_child(_node)
	for c in _node.get_children():
		_node.remove_child(c)
		c.queue_free()
	_arrows = []
	if sel < 0 or sel >= rows.size():
		return
	var res: Dictionary = rows[sel]["res"]
	if not res["ok"]:
		return
	var xs: Transform3D = m._stage_xf()
	var at: Vector3 = xs * (res["at"] as Vector3)
	var j_end: Vector3 = at + xs.basis * (res["J_h"] as Vector3) * ARROW_PER_NS
	_arrow(at, j_end, Color(1.0, 0.6, 0.1))
	var p: Vector3 = xs.basis * (res["p_h"] as Vector3)
	_arrow(at + Vector3(0, 0.02, 0), at + Vector3(0, 0.02, 0) + p * ARROW_PER_NS, Color(0.95, 0.2, 0.15) if "direction" in res["flags"] else Color(0.2, 0.9, 0.4))
	_arrows = _node.get_children()
