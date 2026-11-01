extends SceneTree
## godot --path . --position 4000,4000 -s tests/s146_test.gd   (S146: BUILD THEN ACT. A 30 x 2 x 2 cm stick built in Easy Part by real clicks, "Save and use in a scene": a prop 0.30 m long on the floor beside him, with an automatic grip on its long axis; Pick up brings his right hand to the grip; the prop list names it; changing the part updates the prop)
## BARS: S1 length 0.30 m within 0.002 | S2 min y 0 within 0.005 | S3 grip within 1 cm of the long axis | S4 palm within 3 cm of the grip on the pick-up card, prop taken by the right hand
##       S5 prop list shows "Stick" | S6 beside him (0.2..0.8 m from the hips) | S7 change the part, use again: still one prop, size re-measured
## Shots: C:/Temp/claude/s146/*.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s146"


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


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(4)


func part_index() -> int:
	for i in m.S.props.size():
		if String(m.S.props[i]["kind"]).begins_with("part:"):
			return i
	return -1


func nparts() -> int:
	var n := 0
	for p in m.S.props:
		if String(p["kind"]).begins_with("part:"):
			n += 1
	return n


func mesh_box(p: Dictionary) -> AABB:
	var rn: Node3D = Props.mesh(p)
	var bb := AABB()
	var first := true
	for c in rn.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var b: AABB = (rn.transform * mi.transform) * mi.get_aabb()
			bb = b if first else bb.merge(b)
			first = false
	rn.free()
	return bb


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func slider_to(ep: EasyPart, v: float) -> void:
	for r in ep.rows:
		if String(r["kind"]) == "tweak":
			var s: HSlider = r["slider"]
			var rc := s.get_global_rect()
			var y := rc.get_center().y
			var gw := 24.0
			var p0 := Vector2(rc.position.x + gw * 0.5 + (s.value - s.min_value) / (s.max_value - s.min_value) * (rc.size.x - gw), y)
			var x1 := rc.position.x + gw * 0.5 + (v - s.min_value) / (s.max_value - s.min_value) * (rc.size.x - gw)
			await ev_move(p0, false)
			await ev_mouse(p0, true)
			for i in range(1, 25):
				await ev_move(Vector2(lerpf(p0.x, x1, i / 24.0), y))
			await ev_mouse(Vector2(x1, y), false)
			await idle(3)
			print("  slider ", s.min_value, "..", s.max_value, " now ", s.value)


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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://s146_test"))
	var ss: StartScreen = m.start_screen
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	ss.dirs_override = ["user://s146_test"]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		ok(false, "S0 the CAD DLL loads")
		print("s146: %d fail" % fails)
		quit(1)
		return
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep: EasyPart = pu.ep
	var cam: Camera3D = m.cam
	await click_ctl(ep.make_btns["draw"])
	await drag_screen(cam.unproject_position(Vector3(0.0, 0.0, 0.0)), cam.unproject_position(Vector3(0.15, 0.0, 0.02)))
	await click_ctl(ep.make_btns["pull"])
	await slider_to(ep, 2.0)
	await idle(3)
	var shown := Part.replay(m.S.part)
	print("  built part size mm: ", (shown["mesh"] as ArrayMesh).get_aabb().size * 1000.0 if shown["mesh"] != null else "none")
	m.S.part["name"] = "Stick"
	if m.S.cards.is_empty():
		m.S.add("start", m.B.to_dict())
	m.sel_card = 0
	await click_ctl(ep.use_scene_btn)
	await idle(6)
	var pi := part_index()
	if pi < 0:
		ok(false, "S0 the stick is in the scene")
		print("s146: %d fail" % fails)
		quit(1)
		return
	var p: Dictionary = m.S.props[pi]
	var bb := mesh_box(p)
	var L := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
	ok(absf(L - 0.30) <= 0.002, "S1 length: the prop is %.1f mm long (want 300 within 2), size %.1f x %.1f x %.1f mm" % [L * 1000, bb.size.x * 1000, bb.size.y * 1000, bb.size.z * 1000])
	ok(absf(bb.position.y) <= 0.005, "S2 on the floor: lowest point y %.2f mm" % (bb.position.y * 1000))
	var g := PartScene.grip_world(p)
	var ax := 0
	for i in 3:
		if bb.size[i] > bb.size[ax]:
			ax = i
	var dvec := Vector3.ZERO
	dvec[ax] = 1.0
	var off := g - bb.get_center()
	var perp := off - dvec * off.dot(dvec)
	ok(perp.length() <= 0.01 and absf(off[ax]) <= L * 0.5 + 0.005, "S3 grip %s is %.1f mm from the long axis, %.0f mm from the middle along it" % [str(g), perp.length() * 1000, off[ax] * 1000])
	var hips: Vector3 = m.B.P["pelvis"]
	var dh := Vector2(bb.get_center().x - hips.x, bb.get_center().z - hips.z).length()
	ok(dh >= 0.2 and dh <= 0.8, "S6 beside him: the stick's middle is %.2f m from his hips on the floor plan" % dh)
	ok(m._prop_name(pi) == "Stick", "S5 the prop list name is '%s'" % m._prop_name(pi))
	m.target = Vector3(-0.2, 0.6, 0.0)
	m.dist = 3.2
	m.pitch = -30.0
	m.yaw = 25.0
	m._cam()
	await idle(10)
	await shot("a_in_scene")

	# S4 pick up: the prop picked, card 1 picked, Pick up
	m.sel_prop = pi
	m.sel_card = 0
	m._props_show()
	await idle(3)
	var nc: int = m.S.cards.size()
	var ux: int = m.undo.size()
	m._prop_take()
	print("  status: ", m.ui_status.text if m.get("ui_status") != null else "?")
	await idle(6)
	var made: bool = m.S.cards.size() == nc + 1 and m.S.cards[m.sel_card].has("take")
	var gap := 9.0
	if made:
		m._ps().apply(m.B, m.S.times()[m.sel_card][1])
		gap = PartScene.palm(m.B).distance_to(PartScene.grip_world(m.S.props[pi]))
	ok(made and gap <= 0.03 and m.undo.size() == ux + 1, "S4 pick up card: right palm %.1f mm from the grip (bar 30), card added %s, undo +%d" % [gap * 1000, str(made), m.undo.size() - ux])
	m._cam()
	await idle(10)
	await shot("b_pick_up")

	# S7 back to Easy Part, change it, use again
	m._page_set("STAGE")
	await idle(3)
	var bk: Button = root.find_child("build_back_to_part", true, false) as Button
	if bk != null and bk.is_visible_in_tree():
		await click_ctl(bk)
	await idle(6)
	print("  back button ", bk != null, " page ", m.cur_page, " rows ", pu.ep.rows.size(), " part feats ", m.S.part.get("features", []).size())
	ep = pu.ep
	await slider_to(ep, 5.0)
	print("  part rec after slider ", JSON.stringify(m.S.part.get("features", [])).left(400))
	await idle(3)
	await click_ctl(ep.use_scene_btn)
	await idle(6)
	var qi := part_index()
	var bb2 := mesh_box(m.S.props[qi]) if qi >= 0 else AABB()
	print("  after change mm: ", bb2.size * 1000.0)
	ok(qi >= 0 and nparts() == 1 and absf(bb2.size.y - bb.size.y) > 0.01, "S7 changed part: %d prop, height %.1f mm -> %.1f mm" % [nparts(), bb.size.y * 1000, bb2.size.y * 1000])
	await shot("c_changed")
	print("s146: %d fail" % fails)
	quit(1 if fails > 0 else 0)
