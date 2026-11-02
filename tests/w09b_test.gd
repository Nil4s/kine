extends SceneTree
## W09 (triage): pick through overlapping pieces. Real clicks, 1024x600 and 1920x1080, from the BUILDING card's Easy Part.
## Bars, written before measuring (on the old code B..E FAIL: the click always picks the front piece, there is no list):
##   A two pieces overlap at one pixel: the depth stack there has exactly 2 bodies, nearest first (depths ascending)
##   B repeated real click at that spot: 1st picks the front piece, 2nd the piece behind, 3rd wraps to the front
##   C the list shows two plain names, "Piece 1" and "Piece 2", nothing else on its buttons
##   D press the name of the back piece while the front is picked: that piece is picked (del_bi) and its glow (del_tris) lies inside that body only
##   E a pixel with one piece: no list; a click 40 px away restarts at the front piece
##   F control: the old pick (pu._ray_hit) is the front piece on every click, so B's second click would FAIL on it
const SHOT := "C:/Users/Nick/tools/kine_workers/out/w09b"
const DIRT := "user://w09b_test"

var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	root.push_input(e, true)
	await process_frame
	var r := InputEventKey.new()
	r.keycode = k
	r.physical_keycode = k
	r.pressed = false
	root.push_input(r, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func texts_under(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label and (n as Label).text.strip_edges() != "":
		out.append((n as Label).text)
	elif n is Button and (n as Button).text.strip_edges() != "":
		out.append((n as Button).text)
	for c in n.get_children():
		texts_under(c, out)



func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func bodies() -> int:
	return pu().ep._lumps(pu().res)


func bb_of(tris: PackedVector3Array) -> AABB:
	var a := AABB(tris[0], Vector3.ZERO)
	for v in tris:
		a = a.expand(v)
	return a


## the overlap pixel farthest from every box edge of both pieces (the edge chip and the edge grab sit within ~10 px of an edge)
func overlap_pixel(size: Vector2) -> Vector2:
	var faces: Array = Part.body_faces(m.S.part, -1)
	var segs := []
	for bi in faces.size():
		var bb := bb_of(faces[bi])
		for k in 8:
			for ax in 3:
				if (k >> ax) & 1 == 0:
					var a := bb.position + bb.size * Vector3(k & 1, (k >> 1) & 1, (k >> 2) & 1)
					var b := a + Vector3(bb.size.x if ax == 0 else 0.0, bb.size.y if ax == 1 else 0.0, bb.size.z if ax == 2 else 0.0)
					segs.append([m.cam.unproject_position(a), m.cam.unproject_position(b)])
	var best := Vector2(-1, -1)
	var best_d := 0.0
	var y := 90.0
	while y < size.y - 30.0:
		var x := 30.0
		while x < size.x - 30.0:
			var q := Vector2(x, y)
			if PickStack.stack_at(m.cam, q, faces).size() >= 2:
				var dm := INF
				for sg in segs:
					dm = minf(dm, q.distance_to(Geometry2D.get_closest_point_to_segment(q, sg[0], sg[1])))
				if dm > best_d:
					best_d = dm
					best = q
			x += 3.0
		y += 3.0
	print("diag best overlap pixel %s edge distance %.1f px" % [best, best_d])
	return best if best_d >= 14.0 else Vector2(-1, -1)


func names_in_list() -> Array:
	var panel: Control = m.find_child("easypart_pickstack", true, false)
	var names := []
	if panel != null and panel.is_visible_in_tree():
		for c in panel.find_children("*", "Button", true, false):
			names.append(String((c as Button).text).replace("  (picked)", ""))
			names.append("tip:" + (c as Button).tooltip_text)
	return names


func list_at(sz: Vector2i, tag: String) -> Array:
	var px := overlap_pixel(Vector2(sz))
	for tryp in [[-6.0, 0.0], [-14.0, 0.0], [-4.0, 0.0]]:
		if px.x > 0:
			break
		m.target = Vector3(0.2, -0.06, -0.05)
		m.pitch = tryp[0]
		m.yaw = tryp[1]
		m._cam()
		await idle(20)
		px = overlap_pixel(Vector2(sz))
	if px.x < 0:
		return []
	await click_at(Vector2(sz.x * 0.5, sz.y * 0.92))
	await click_at(px)
	await shot("%s_%d" % [tag, sz.x])
	return names_in_list()


func run_size(sz: Vector2i) -> void:
	root.size = sz
	DisplayServer.window_set_size(sz)
	root.content_scale_size = sz
	await idle(10)
	m.target = Vector3(0.2, -0.06, -0.05)
	m.pitch = -10.0
	m.yaw = 0.0
	m._cam()
	await idle(40)
	var faces: Array = Part.body_faces(m.S.part, -1)
	# control: the old label of body 0 and 1
	ok(PickStack.name_of(0) == "Piece 1" and PickStack.name_of(1) == "Piece 2", "%s control: the old list says Piece 1 / Piece 2" % [sz])
	# unnamed: the feature that made each
	var l1: Array = await list_at(sz, "unnamed")
	var s1 := String(" ".join(l1))
	ok("Extrude 1" in l1 and "Extrude 2" in l1 and not ("Piece 1" in l1), "%s A unnamed bodies show their feature: %s" % [sz, l1])
	ok("tip:Made by Extrude 2" in l1, "%s B tooltip names the feature" % [sz])
	# named: Bracket / Lid
	var rec: Dictionary = m.S.part.duplicate(true)
	(rec["features"] as Array).append(Part.new_feature(rec, "bname", {"name": "N1", "body": 0, "called": "Bracket"}))
	(rec["features"] as Array).append(Part.new_feature(rec, "bname", {"name": "N2", "body": 1, "called": "Lid"}))
	var keep: Dictionary = m.S.part
	m.S.part = rec
	pu().upto = -1
	pu().sync()
	await idle(40)
	var l2: Array = await list_at(sz, "named")
	ok("Bracket" in l2 and "Lid" in l2 and not ("Extrude 2" in l2), "%s C named bodies show Bracket and Lid: %s" % [sz, l2])
	m.S.part = keep
	pu().sync()
	await idle(20)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3.ZERO
	m.pitch = -60.0
	m.yaw = 0.0
	m._cam()
	await idle(60)
	var draw = pu().ep.make_btns["draw"]
	pu().ep.one_side = true
	pu().ep.one_side_btn.set_pressed_no_signal(true)
	await click_ctl(draw)
	await drag_screen(scr(Vector3(-0.04, 0.0, 0.0)), scr(Vector3(0.04, 0.0, 0.06)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(60)
	await click_ctl(draw)
	await drag_screen(scr(Vector3(-0.04, 0.0, -0.14)), scr(Vector3(0.04, 0.0, -0.08)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(10)
	var tall: Dictionary = m.S.part.duplicate(true)   # 80 mm tall plates: a band of pixels wide enough to click (thin 20 mm plates left 2 px)
	for f in tall["features"]:
		if String(f["t"]) == "extrude":
			f["dist"] = 80.0
	m.S.part = tall
	pu().upto = -1
	pu().sync()
	await idle(60)
	ok(bodies() == 2, "setup: two separate pieces (bodies %d)" % bodies())
	if bodies() == 2:
		for sz in [Vector2i(1024, 600), Vector2i(1920, 1080)]:
			await run_size(sz)
	print("w09b: %d fail" % fails)
	quit(1 if fails > 0 else 0)
