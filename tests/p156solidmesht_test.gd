extends SceneTree
## p156solidmesht (Friday plan item 156: "Solid -> mesh to sculpt details on a built part"): a beginner on the BUILDING card makes a box
## (Draw shape, Box, drag, Pull it up). The suggest row shows "Sculpt details?" beside Round the edges? and Hollow it?. One click turns
## the solid into a sculpt mesh on Expert's Sculpt page (Easy goes off for it). A real drag on the mesh changes its surface (a detail);
## Esc leaves and the Easy solid is still there, unchanged. Every number is measured from the mesh and the built result, never from the
## code's variables.
##   S0 the box: one body, 12 mm or more square (BUILDING card, Easy, Pull it up)
##   S1 "Sculpt details?" is in the suggest row after Pull it up: visible, not greyed, plain words
##   S2 one click: the Sculpt page is open with the sculpt on, Easy is off, one mesh whose box is the solid's box (within 0.5 mm)
##   S3 the Easy solid is unchanged: one body, newest step still the pull, undo count unchanged by the click
##   S4 one real drag over the mesh moves its surface: the largest vertex move is >= 0.2 mm
##   S5 Esc leaves the sculpt: sculpt off, Easy solid still one body, newest step still the pull
##   S6 the words are plain (no jargon)
## shots: C:/Temp/claude/p156solidmesht/*.png
const SHOT := "C:/Temp/claude/p156solidmesht"
const DIRT := "user://p156solidmesht_test"
var fails := 0
var m: Node
var said := []


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


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func solid() -> Dictionary:
	return Part.replay(m.S.part, -1, {"faces": true, "props": true})


func mm(v: float) -> float:
	return v / Part.MM


func newest() -> String:
	var feats: Array = m.S.part.get("features", [])
	return String(feats[feats.size() - 1].get("t", "")) if not feats.is_empty() else ""


func press_key(k: Key, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.key_label = k
	e.pressed = true
	e.ctrl_pressed = ctrl
	root.push_input(e, true)
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
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var pu = m.bld.part
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(60)

	# S0 the box: Draw shape, Box, drag a 40 mm box on the grid, Pull it up
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_pts([scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02))])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var s0 := solid()
	var bb0: AABB = s0["aabb"]
	ok(int(s0["bodies"]) == 1 and mm(bb0.size.y) >= 12.0 and mm(bb0.size.x) >= 12.0,
		"S0 the box: one body, %.1f x %.1f x %.1f mm" % [mm(bb0.size.x), mm(bb0.size.y), mm(bb0.size.z)])

	# S1 the chip is in the suggest row after Pull it up
	var sbtn: Button = ep.suggest_row.find_child("easypart_suggest_sculpt", true, false) as Button
	var s1 := sbtn != null and sbtn.is_visible_in_tree() and not sbtn.disabled and sbtn.text == "Sculpt details?"
	ok(s1, "S1 Sculpt details? is in the suggest row after Pull it up (%s)" % (sbtn.text if sbtn != null else "missing"))
	said.append(String(ep.hint_l.text) + " | " + String(ep.msg))
	await shot("chip")

	# S2 one click: the sculpt is open on the Sculpt page, Easy is off, the mesh box is the solid's box
	var ub2: int = m.undo.size()
	if s1:
		await click_ctl(sbtn)
	await idle(20)
	var ksc = m.ksc
	var sculpt_on: bool = ksc != null and ksc.on
	var easy_off: bool = m.easy != null and not m.easy.on
	var mesh_bb := AABB()
	var nv := 0
	if sculpt_on:
		nv = ksc.mesh.vert_count()
		var first := true
		for v in ksc.mesh.verts:
			if first:
				mesh_bb = AABB(v, Vector3.ZERO)
				first = false
			else:
				mesh_bb = mesh_bb.expand(v)
	var same_box := sculpt_on and absf(mm(mesh_bb.size.x) - mm(bb0.size.x)) <= 0.5 and absf(mm(mesh_bb.size.y) - mm(bb0.size.y)) <= 0.5 and absf(mm(mesh_bb.size.z) - mm(bb0.size.z)) <= 0.5
	ok(s1 and sculpt_on and m.cur_page == "SCULPT" and easy_off and same_box and nv >= 8,
		"S2 one click: sculpt on %s, page %s, Easy off %s, %d vertices, box %.1f x %.1f x %.1f mm (solid %.1f x %.1f x %.1f)" % [sculpt_on, m.cur_page, easy_off, nv,
			mm(mesh_bb.size.x), mm(mesh_bb.size.y), mm(mesh_bb.size.z), mm(bb0.size.x), mm(bb0.size.y), mm(bb0.size.z)])
	said.append(String(ep.msg))
	await shot("sculpt")

	# S3 the Easy solid is unchanged: one body, the pull is still the newest step, no undo step taken by the click
	var s3 := solid()
	var ub3: int = m.undo.size()
	ok(int(s3["bodies"]) == 1 and newest() == "extrude" and ub3 == ub2,
		"S3 the solid is unchanged: %d body, newest step %s, undo %d -> %d" % [int(s3["bodies"]), newest(), ub2, ub3])

	# S4 a real drag over the mesh moves its surface
	var before: PackedVector3Array = PackedVector3Array()
	if sculpt_on:
		before = ksc.mesh.verts.duplicate()
		var c_w := mesh_bb.get_center() + Vector3(1.0, 0.0, 0.0)
		m.target = c_w
		m.dist = 0.35
		m._cam()
		await idle(20)
		var mid := scr(c_w)
		await drag_pts([mid + Vector2(-40.0, -10.0), mid + Vector2(0.0, -10.0), mid + Vector2(40.0, -10.0)])
		await idle(10)
	var moved := 0.0
	if sculpt_on and ksc.mesh.verts.size() == before.size():
		for i in before.size():
			moved = maxf(moved, mm(ksc.mesh.verts[i].distance_to(before[i])))
	ok(sculpt_on and moved >= 0.2, "S4 a drag over the mesh moves its surface: largest move %.2f mm (want >= 0.2)" % moved)
	await shot("stroke")

	# S5 Esc leaves the sculpt; the Easy solid is still there
	await press_key(KEY_ESCAPE)
	await idle(10)
	var s5 := solid()
	var left: bool = ksc != null and not ksc.on
	ok(left and int(s5["bodies"]) == 1 and newest() == "extrude",
		"S5 Esc leaves the sculpt (off %s), the Easy solid stays: %d body, newest %s" % [left, int(s5["bodies"]), newest()])

	# S6 plain words
	said.append(String(m.ui_status.text) if m.ui_status != null else "")
	var all_words := " | ".join(said).to_lower() + " | " + sbtn.text.to_lower()
	var jargon := ["sketch", "extrude", "shell", "split", "boolean", "feature", "loft", "kernel", "taper", "fillet", "topology", "manifold"]
	var bad := ""
	for j in jargon:
		if all_words.find(j) >= 0:
			bad = j
	ok(bad == "" and all_words.find("sculpt details?") >= 0, "S6 the words are plain, no jargon (%s)" % bad)

	print("P156SOLIDMESHT %d fails" % fails)
	quit(1 if fails > 0 else 0)
