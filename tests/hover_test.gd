## godot --path . -s tests/hover_test.gd     (GATES GG2, UPGRADES #35; a real window, real mouse motion)
## HOVER SAYS WHAT IS UNDER THE MOUSE: a REAL mouse move (no button) to every body part's centre on screen: the hovered
## part is the one a click there would pick (main._pick, the same point), and for most parts it is that part itself
## (some centres are behind another part from the front: reported); it is drawn in HOVER (not the selected one's SEL)
## and named on the status line. Off the body: no hover. The selected part, hovered, keeps SEL. Pressing on a part and
## dragging: no hover during the drag. Moving onto a panel: the hover goes.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func move(p: Vector2, mask := 0) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = Vector2(1, 0)
	e.button_mask = mask
	root.push_input(e)
	await idle(2)


func button(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await idle(2)


func spot(j: String) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position((c[0] + c[1]) * 0.5)


func colour(j: String) -> Color:
	return (m.mats[j] as StandardMaterial3D).albedo_color


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._new_scene()
	m.sel = "head"
	m._refresh()
	await idle(3)
	var same := 0
	var itself := 0
	var tried := 0
	var bad := []
	var behind := []
	for j in Body.BODY:
		if j == "head":
			continue
		var p := spot(j)
		await move(p)
		var want: String = m._pick(p)
		if want == "" or want == "head":
			continue   # its centre is not on the body from here, or under the selected head
		tried += 1
		await create_timer(m.BAR_LEAVE + 0.05).timeout   # the bar's words follow a RESTED hover (QQ2: BAR_REST on, BAR_LEAVE off)
		await process_frame
		var h: String = m.hover_part
		var lit: bool = colour(h).is_equal_approx(Color(m.HOVER, 0.3)) if h != "" else false
		var named: bool = h != "" and m.bar_text().contains(m.nice(h))
		if h == want and lit and named:
			same += 1
		else:
			bad.append([j, h, want, lit, named])
		if h == j:
			itself += 1
		else:
			behind.append(j)
	ok(tried >= 16 and bad.is_empty() and itself >= tried * 0.7,
		"1 real moves to %d parts' centres: the hovered part = what a click there picks, lit HOVER, named on the bar: %d of %d; it is the part itself for %d (behind another: %s) (bad: %s)" % [tried, same, tried, itself, behind, bad.slice(0, 2)])
	await move(Vector2(m.LEFT_W + 30, m.TOP_H + 30))
	ok(m.hover_part == "", "2 off the body (a corner of the view): no hover ('%s')" % m.hover_part)
	var hp := spot("head")
	await move(hp)
	ok(colour("head").is_equal_approx(Color(m.SEL, 0.35)) or colour("head").b > colour("head").r + 0.3, "3 the selected head, hovered: it keeps its selected colour %s" % colour("head"))
	var ap := spot("upperarm_r")
	await move(ap)
	await button(ap, true)
	await move(ap + Vector2(0, -20), MOUSE_BUTTON_MASK_LEFT)
	await move(spot("thigh_l"), MOUSE_BUTTON_MASK_LEFT)
	var during: String = m.hover_part
	await button(spot("thigh_l"), false)
	ok(during == "" and m.sel == "upperarm_r", "4 a press on the arm and a drag over the left thigh: no hover during it ('%s'), the arm picked" % during)
	await move(spot("thigh_l"))
	var before: String = m.hover_part
	await move(Vector2(m.LEFT_W * 0.5, 300))   # over the left panel
	await idle(2)
	ok(before == "thigh_l" and m.hover_part == "", "5 hovering the thigh ('%s'), then onto the left panel: the hover goes ('%s')" % [before, m.hover_part])
	print("HOVER: %d failed" % fails)
	quit(1 if fails > 0 else 0)
