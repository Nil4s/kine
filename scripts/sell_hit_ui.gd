## SELL THE HIT panel (ROADMAP I21; the maths: scripts/sell_hit.gd). With two fighters the active one attacks. Each strike is classed as the shot
## camera sees it: SOLD (clear in 3D, overlaps the target on screen), NOT SOLD (a visible gap, in px and cm), UNSAFE (a real 3D contact: red).
## The timeline wears a badge per strike. "Move the camera" / "Offset the aim" on a NOT SOLD row builds the fix; Preview plays it (the scene is
## not changed), Accept writes it as ONE undo step.
class_name SellHitUI
extends RefCounted

var m: Node
var a_k := 0
var d_k := 1
var rep: Dictionary = {}
var fx: Dictionary = {}
var pv := false
var pv_t := 0.0
var pv_t1 := 0.0
var pv_sc: Scene = null
var pv_shots: Array = []
var shots_saved: Array = []
var swapped := false


func _init(main: Node) -> void:
	m = main


func commands(add: Callable) -> void:
	add.call("Sell the hit", "", show, "shot camera strike hit sold cheat angle miss overlap screen safety unsafe contact stunt camera offset aim",
		false, "with two fighters and a shot camera: each strike's 3D miss against what the camera shows; SOLD / NOT SOLD / UNSAFE on the timeline; fixes: move the camera along the line of action or offset the strike's aim (preview, then Accept = one undo step)")


func _hero() -> Scene:
	return m.actors_rt[0]["S"]


func _xf() -> Transform3D:
	return (m.actors_rt[a_k]["xf"] as Transform3D).affine_inverse() * (m.actors_rt[d_k]["xf"] as Transform3D)


func _ctf() -> Transform3D:
	return (m.actors_rt[a_k]["xf"] as Transform3D).affine_inverse() * (m.actors_rt[0]["xf"] as Transform3D)


func _fps() -> int:
	return maxi(1, (m.actors_rt[a_k]["S"] as Scene).fps)


func _restore() -> void:
	if swapped:
		_hero().shots = shots_saved
		swapped = false


func halt() -> void:
	pv = false
	_restore()


func clear_overlay() -> void:
	rep = {}
	fx = {}
	halt()
	_overlay()


func compute() -> void:
	m._actors_sync()
	rep = SellHit.analyze(m.actors_rt[a_k]["S"], m.actors_rt[d_k]["S"], _xf(), _hero().shots, _ctf(), _fps())
	fx = {}
	_overlay()


func _overlay() -> void:
	var tl = m.ui_timeline
	if tl == null:
		return
	var bands := []
	for r in rep.get("rows", []):
		bands.append({"t0": float(r["t0"]), "t1": float(r["t1"]), "cls": String(r["cls"])})
	tl.sh = bands
	tl.queue_redraw()


func show() -> void:
	m._actors_sync()
	if m.actors_rt.size() < 2:
		m._say("sell the hit needs two fighters: 'Actor: add a second fighter' first (the active one attacks, the other is struck)")
		return
	a_k = m.actor_on
	d_k = 1 - a_k
	compute()
	_panel()


static func name_of(cls: String) -> String:
	return "SOLD" if cls == "sold" else ("UNSAFE" if cls == "unsafe" else "NOT SOLD")


func _line(r: Dictionary) -> String:
	var cls := String(r["cls"])
	var t := "card %d  %.2f-%.2f s  %s  3D miss %.1f cm at %.2f s" % [int(r["card"]) + 1, float(r["t0"]), float(r["t1"]), name_of(cls), float(r["miss"]) * 100.0, float(r["t"])]
	if cls == "unsafe":
		t += "  SAFETY: " + ("a real contact" if r["contact"] else "inside the %.0f cm margin" % (SellHit.SAFE * 100.0))
	elif cls == "notsold":
		t += "  screen gap %.0f px = %.0f cm at the target's depth" % [float(r["gap_px"]), float(r["gap_cm"])]
	else:
		t += "  overlaps the target by %.0f px" % -float(r["gap_px"])
	return t


func _panel() -> void:
	var L: VBoxContainer = m.ui_find_list
	for c in L.get_children():
		L.remove_child(c)
		c.queue_free()
	var rows: Array = rep.get("rows", [])
	var head := HBoxContainer.new()
	L.add_child(head)
	var title: Label = m._label("SELL THE HIT  -  %s" % String(rep.get("msg", "")), 14, "fail" if int(rep.get("unsafe", 0)) > 0 else ("warn" if int(rep.get("notsold", 0)) > 0 else "heading"), true)
	title.name = "sh_title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(m._button("Close", _close))
	L.add_child(m._label("Seen through the shot camera. SOLD: at least %.0f cm clear in 3D (a stunt rule of thumb, a heuristic) and the tip overlaps the target on screen. NOT SOLD: a visible gap. UNSAFE: closer than the margin, or touching. Move the camera turns it along the line of action (distance and lens kept); Offset the aim moves the strike (IK on the arm). Preview changes nothing, Accept is one undo step." % (SellHit.SAFE * 100.0),
		13, "text:0.6", true))
	for k in rows.size():
		var r: Dictionary = rows[k]
		var row := HBoxContainer.new()
		var cls := String(r["cls"])
		var lb: Label = m._label(_line(r), 13, "text:0.85" if cls == "sold" else ("fail" if cls == "unsafe" else "warn"), true)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lb.custom_minimum_size = Vector2(300, 0)
		row.add_child(lb)
		if cls == "notsold":
			var b1: Button = m._button("Move the camera", select.bind(k, "camera"), "turn the shot camera along the line of action so the gap is hidden behind the target; the 3D miss is not touched")
			b1.name = "sh_cam_%d" % k
			var b2: Button = m._button("Offset the aim", select.bind(k, "aim"), "move the strike toward the camera axis (IK on the striking arm), keeping the 3D margin")
			b2.name = "sh_aim_%d" % k
			row.add_child(b1)
			row.add_child(b2)
		L.add_child(row)
	if not fx.is_empty():
		var af: Dictionary = fx.get("after", {})
		var l2: Label = m._label("FIX  -  " + String(fx["msg"]) + ("; then the strike is %s (3D miss %.1f cm)" % [name_of(String(af["cls"])), float(af["miss"]) * 100.0] if not af.is_empty() else ""), 13, "heading", true)
		l2.name = "sh_fix"
		l2.custom_minimum_size = Vector2(380, 0)
		L.add_child(l2)
		var r2 := HBoxContainer.new()
		var pb: Button = m._button("Preview", preview, "play the strike with the fix; the scene is not changed")
		pb.name = "sh_preview"
		var ab: Button = m._button("Accept", accept, "write the fix; one undo step")
		ab.name = "sh_accept"
		r2.add_child(pb)
		r2.add_child(ab)
		L.add_child(r2)
	(m.ui_find.get_child(0) as ScrollContainer).custom_minimum_size = Vector2(420, clampf(200.0 + 44.0 * rows.size() + (90.0 if not fx.is_empty() else 0.0), 220.0,
		minf(520.0, m.get_viewport().get_visible_rect().size.y - m.bottom_h - 82 - (m.TOP_H + 12) - 26)))
	m.ui_find.visible = true
	m._say("sell the hit: " + String(rep.get("msg", "")) + (".  'Move the camera' or 'Offset the aim' on a NOT SOLD strike builds the fix" if int(rep.get("notsold", 0)) > 0 else ""))


func select(k: int, kind: String) -> void:
	var A: Scene = m.actors_rt[a_k]["S"]
	var D: Scene = m.actors_rt[d_k]["S"]
	var f := SellHit.camera_fix(A, D, _xf(), _hero().shots, _ctf(), _fps(), k, rep) if kind == "camera" else SellHit.aim_fix(A, D, _xf(), _hero().shots, _ctf(), _fps(), k, rep)
	if not f["ok"]:
		m._say(String(f["why"]))
		return
	fx = f
	_panel()


func _close() -> void:
	clear_overlay()
	m._close_findings()


func preview() -> void:
	if fx.is_empty():
		m._say("nothing to preview: press 'Move the camera' or 'Offset the aim' on a NOT SOLD strike first")
		return
	var r: Dictionary = rep["rows"][int(fx["k"])]
	halt()
	if fx["kind"] == "camera":
		shots_saved = _hero().shots
		_hero().shots = (fx["shots"] as Array).duplicate(true)
		swapped = true
	else:
		pv_sc = (fx["scene"] as Scene).clone()
	pv_t = maxf(0.0, float(r["t0"]) - 0.3)
	pv_t1 = float(r["t1"]) + 0.4
	pv = true
	m.playing = false
	m._say("sell the hit: previewing the fix (the scene is not changed)")


func tick(dt: float) -> void:
	if not pv:
		return
	pv_t += dt
	if pv_t >= pv_t1:
		pv = false
		pv_sc = null
		_restore()
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		return
	if pv_sc != null:
		pv_sc.apply(m.actors_rt[a_k]["B"], pv_t)
		(m.actors_rt[d_k]["S"] as Scene).apply(m.actors_rt[d_k]["B"], pv_t)
	else:
		m.playhead = pv_t
		m._ps().apply(m.B, pv_t)
	m._refresh()


func accept() -> void:
	if fx.is_empty():
		m._say("nothing to accept: press 'Move the camera' or 'Offset the aim' on a NOT SOLD strike first")
		return
	halt()
	pv_sc = null
	var f := fx
	m._actors_sync()
	m._step_hint = "Sell the hit"
	m._push_undo()
	if f["kind"] == "camera":
		_hero().shots = (f["shots"] as Array).duplicate(true)
	else:
		(m.actors_rt[a_k]["S"] as Scene).cards = (f["scene"] as Scene).cards.duplicate(true)
		m._rebuild_cards()
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	m._say("sell the hit: %s.  Ctrl+Z undoes it in one step" % String(f["msg"]))
	compute()
	_panel()
