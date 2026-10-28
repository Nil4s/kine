extends SceneTree
## godot --path . --position 4000,4000 -s tests/ecolour_test.gd     (EASY PART COLOUR: one piece, then the whole part, then Undo; the colour kept in a scene and in My parts; needs a window and the CAD DLL)
## BARS, stated before any measurement (real clicks / drags / key presses at 1280 x 720 from the start screen; the store folder is user://myparts_test):
##  C1 ONE PIECE  a box drawn and pulled in Easy Part, Colour then Red: one appear step per body, ONE undo step, the look is red
##  C2 WHOLE      then Blue on the whole part: ONE undo step, every body is blue; Ctrl+Z goes back to red, Ctrl+Z again back to no colour
##  C3 SCENE      Red again, then Use in a scene: the prop on the STAGE is drawn red (the material on the mesh, not the default grey)
##  C4 MY PARTS   the saved record reopens red (replay of the file), and its picture is reddish, not grey
## Shots: C:/Temp/claude/ecolour/shot.png (the stage with the red prop).
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/ecolour"
const DIRT := "user://myparts_test"
const DIRP := "user://myparts_test/parts"


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
	await idle(3)


func press_ctrl_z() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_Z
	e.physical_keycode = KEY_Z
	e.key_label = KEY_Z
	e.ctrl_pressed = true
	e.pressed = true
	root.push_input(e, true)
	await process_frame
	e.pressed = false
	root.push_input(e, true)
	await idle(4)


func count_kind(rec: Dictionary, t: String) -> int:
	var n := 0
	for f in rec.get("features", []):
		if String(f["t"]) == t:
			n += 1
	return n


## the colour of body i of the part on screen (its replayed look)
func look_now(i := 0) -> Color:
	return Part.look_at(m.bld.part.res.get("body_looks", []), i)["c"]


## the active material colour of the first MeshInstance3D that draws this mesh (a dummy colour when none draws it)
func drawn_color(mesh: Mesh) -> Color:
	var found: Array = []
	_find_mi(root, mesh, found)
	if found.is_empty():
		return Color(-1, -1, -1)
	var mt := (found[0] as MeshInstance3D).get_active_material(0) as StandardMaterial3D
	return mt.albedo_color if mt != null else Color(-2, -2, -2)


func _find_mi(n: Node, mesh: Mesh, out: Array) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh == mesh:
		out.append(n)
	for c in n.get_children():
		_find_mi(c, mesh, out)


func is_red(c: Color) -> bool:
	return c.r > c.g + 0.3 and c.r > c.b + 0.3


func is_blue(c: Color) -> bool:
	return c.b > c.r + 0.3


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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT))
	var sc: GDScript = load("res://scripts/build/myparts.gd") as GDScript
	sc.dir = DIRP
	var ss: StartScreen = m.start_screen
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		ok(false, "C0 the CAD DLL loads")
		print("ecolour: %d fail" % fails)
		quit(1)
		return
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	m.S.part["name"] = "Ecolour"
	var ep: EasyPart = pu.ep
	await click_ctl(ep.make_btns["draw"])
	var cam: Camera3D = m.cam
	await drag_screen(cam.unproject_position(Vector3(1.4, 0.0, 0.0)), cam.unproject_position(Vector3(1.5, 0.1, 0.0)))
	await click_ctl(ep.make_btns["pull"])
	await idle(3)
	var nb := int(pu.res.get("bodies", 0))

	# C1 one piece: Colour, Red
	var u0: int = m.undo.size()
	var a0 := count_kind(m.S.part, "appear")
	await click_ctl(ep.make_btns["colour"])
	await click_ctl(ep.colour_box.find_child("easypart_colour_red", true, false))
	ok(nb >= 1 and count_kind(m.S.part, "appear") == a0 + nb and m.undo.size() == u0 + 1 and is_red(look_now(0)),
		"C1 one piece: Red = one appear step per body (%d), ONE undo step (%d -> %d), the look is red %s" % [nb, u0, m.undo.size(), str(look_now(0))])

	# C2 whole part: Blue on everything, then Ctrl+Z twice
	await click_ctl(ep.make_btns["colour"])
	await click_ctl(ep.colour_box.find_child("easypart_colour_blue", true, false))
	var all_blue := true
	for i in int(pu.res.get("bodies", 0)):
		all_blue = all_blue and is_blue(look_now(i))
	ok(all_blue and m.undo.size() == u0 + 2, "C2 whole part: Blue on every body, ONE undo step (undo %d -> %d)" % [u0 + 1, m.undo.size()])
	await press_ctrl_z()
	ok(is_red(look_now(0)) and count_kind(m.S.part, "appear") == a0 + nb, "C2 Ctrl+Z: back to red, the blue step is gone")
	await press_ctrl_z()
	ok(count_kind(m.S.part, "appear") == a0 and not is_red(look_now(0)) and not is_blue(look_now(0)),
		"C2 Ctrl+Z again: back to no colour (the default grey)")
	await click_ctl(ep.make_btns["colour"])
	await click_ctl(ep.colour_box.find_child("easypart_colour_red", true, false))

	# C3 Use in a scene: the prop on the stage is drawn red
	await click_ctl(ep.use_scene_btn)
	await idle(6)
	var kind := String(m.S.props[-1].get("kind", "")) if m.S.props.size() > 0 else ""
	var mesh: Mesh = Props.kind_of(kind).get("mesh", null) if Props.has_kind(kind) else null
	var dc := drawn_color(mesh) if mesh != null else Color(-3, -3, -3)
	root.get_texture().get_image().save_png(SHOT + "/shot.png")
	ok(kind.begins_with("part:Ecolour") and is_red(dc), "C3 Use in a scene: the prop drawn on the stage is red %s (kind %s)" % [str(dc), kind])

	# C4 My parts: the file reopens red, its picture is reddish
	var path: String = sc.path_of("Ecolour")
	var thumb: String = sc.thumb_of("Ecolour")
	for i in 180:
		if FileAccess.file_exists(ProjectSettings.globalize_path(thumb)):
			break
		await idle(1)
	var saved: Dictionary = sc.load_part("Ecolour")
	var res: Dictionary = Part.replay(saved) if not saved.is_empty() else {}
	var bl: Array = res.get("body_looks", [])
	var reopened: Color = Part.look_at(bl, 0)["c"] if bl.size() > 0 else Color(-1, -1, -1)
	var reds := 0   # the picture's clearly red pixels (a grey part has none)
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path(thumb)) if FileAccess.file_exists(ProjectSettings.globalize_path(thumb)) else null
	if img != null and not img.is_empty():
		for y in img.get_height():
			for x in img.get_width():
				var px := img.get_pixel(x, y)
				if px.a > 0.5 and px.r > px.g + 0.2 and px.r > px.b + 0.2:
					reds += 1
	ok(is_red(reopened) and reds >= 20, "C4 My parts: the saved part reopens red %s, its picture has %d red pixels [%s]" % [str(reopened), reds, path])
	print("ecolour: %d fail" % fails)
	quit(1 if fails > 0 else 0)
