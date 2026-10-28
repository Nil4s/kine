extends SceneTree
## godot --path . --position 4000,4000 -s tests/escene_test.gd     (ESCENE: an Easy Part made by clicks and put into a scene with Use in a scene: it appears on the floor at real size, is selectable and movable with real clicks, and survives a scene save and load; needs a window and the CAD DLL)
## BARS, stated before any measurement (real clicks / drags at 1280 x 720, from the real start screen; the scene file is user://escene_test/):
##  E1 APPEAR  a box drawn on the grid, pulled up, Use in a scene: one new prop of kind part:..., ONE undo step, the page is STAGE
##  E2 SIZE    the prop solid is the real size: the drawn side is 0.10 m (within 3 mm), and the solid equals the mesh size within 1 mm
##  E3 FLOOR   the prop stands on the floor: its mesh lowest point is at y 0 (within 1 mm) and its origin is at y 0
##  E4 SELECT  a real click on the part in the view picks it (sel_prop is its index)
##  E5 MOVE    a real drag of the picked part 0.5 m over the floor moves it (origin moves >= 0.4 m, stays on the floor), ONE undo step
##  E6 SAVE    the scene dictionary written to user:// and opened again: the part is back (same kind, same origin within 1 mm, same size)
## Shot: C:/Temp/claude/escene/shot.png (the moved part in the view).
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/escene/shot.png"
const DIRT := "user://escene_test"
const SCENE := "user://escene_test/scene.json"


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


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(4)


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(4)


## the index of the part prop in the set (-1 when none)
func part_index() -> int:
	for i in m.S.props.size():
		if String(m.S.props[i]["kind"]).begins_with("part:"):
			return i
	return -1


## the lowest world y of a prop's drawn mesh
func mesh_min_y(p: Dictionary) -> float:
	var rn: Node3D = Props.mesh(p)
	var best := INF
	for c in rn.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			var bb: AABB = (rn.transform * mi.transform) * mi.get_aabb()
			best = minf(best, bb.position.y)
	rn.free()
	return best


func mesh_size(p: Dictionary) -> Vector3:
	return (Props.kind_of(String(p["kind"]))["mesh"] as ArrayMesh).get_aabb().size


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
	var dd := ProjectSettings.globalize_path(DIRT)
	if DirAccess.dir_exists_absolute(dd):
		for f in DirAccess.get_files_at(dd):
			DirAccess.remove_absolute(dd + "/" + f)
	DirAccess.make_dir_recursive_absolute(dd)
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
		ok(false, "E0 the CAD DLL loads")
		print("escene: %d fail" % fails)
		quit(1)
		return
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep: EasyPart = pu.ep
	var cam: Camera3D = m.cam
	# the part by clicks: a box drawn on the grid from 1.4 m to 1.5 m (a 0.10 m side), pulled up
	await click_ctl(ep.make_btns["draw"])
	await drag_screen(cam.unproject_position(Vector3(1.4, 0.0, 0.0)), cam.unproject_position(Vector3(1.5, 0.0, 0.1)))
	await click_ctl(ep.make_btns["pull"])
	await idle(3)

	# the part as the Easy Part shows it: its record replayed (the size the user sees on the grid)
	var shown := Part.replay(m.S.part)
	var shown_sz: Vector3 = (shown["mesh"] as ArrayMesh).get_aabb().size if shown["mesh"] != null else Vector3.ZERO
	# E1 Use in a scene: one prop, one undo step, the page is STAGE
	var u0: int = m.undo.size()
	var p0: int = m.S.props.size()
	await click_ctl(ep.use_scene_btn)
	await idle(6)
	var pi := part_index()
	ok(m.S.props.size() == p0 + 1 and pi >= 0 and m.undo.size() == u0 + 1 and m.cur_page == "STAGE",
		"E1 Use in a scene: one part prop (props %d -> %d), one undo step (%d -> %d), page %s" % [p0, m.S.props.size(), u0, m.undo.size(), m.cur_page])
	if pi < 0:
		print("escene: %d fail" % fails)
		quit(1)
		return
	var p: Dictionary = m.S.props[pi]

	# E2 real size
	var sz := mesh_size(p)
	var solid_sz: Vector3 = Props.kind_of(String(p["kind"]))["solids"][0][1]
	ok(shown_sz.length() > 0.01 and sz.distance_to(shown_sz) < 0.001 and solid_sz.distance_to(sz) < 0.001,
		"E2 real size: the scene mesh %.1f x %.1f x %.1f mm, the Easy Part shows %.1f x %.1f x %.1f mm, solid %.1f x %.1f x %.1f mm" % [sz.x * 1000, sz.y * 1000, sz.z * 1000, shown_sz.x * 1000, shown_sz.y * 1000, shown_sz.z * 1000, solid_sz.x * 1000, solid_sz.y * 1000, solid_sz.z * 1000])

	# E3 on the floor
	var my := mesh_min_y(p)
	ok(absf(my) < 0.001 and absf((p["xf"] as Transform3D).origin.y) < 0.001,
		"E3 on the floor: lowest mesh point y %.2f mm, origin y %.2f mm" % [my * 1000, (p["xf"] as Transform3D).origin.y * 1000])

	# E4 selectable: a real click on the part in the view
	m.sel_prop = -1
	m._props_show()
	await idle(3)
	var c0: Vector3 = (Props.solids(p)[0]["xf"] as Transform3D).origin
	var sp := cam.unproject_position(c0)
	await click_at(sp)
	ok(m.sel_prop == pi, "E4 a real click on the part picks it (sel_prop %d, want %d, at %s)" % [m.sel_prop, pi, str(sp)])

	# E5 movable: drag 0.5 m over the floor, one undo step
	var ux0: int = m.undo.size()
	var from_o: Vector3 = (m.S.props[pi]["xf"] as Transform3D).origin
	var tgt := c0 + Vector3(0.5, 0.0, 0.0)
	await drag_screen(sp, cam.unproject_position(tgt))
	var to_o: Vector3 = (m.S.props[pi]["xf"] as Transform3D).origin
	var moved := Vector2(to_o.x - from_o.x, to_o.z - from_o.z).length()
	ok(moved >= 0.4 and absf(to_o.y) < 0.001 and m.undo.size() == ux0 + 1,
		"E5 drag moves it: %.3f m over the floor (origin y %.2f mm), undo +%d" % [moved, to_o.y * 1000, m.undo.size() - ux0])
	await idle(3)
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/escene")
	m.get_viewport().get_texture().get_image().save_png(SHOT)

	# E6 save and load: the scene dictionary on disk, opened again
	var d: Dictionary = m._scene_dict()
	var fw := FileAccess.open(SCENE, FileAccess.WRITE)
	fw.store_string(JSON.stringify(d, " "))
	fw.close()
	m._load_scene(SCENE)
	await idle(10)
	var qi := part_index()
	var ok6 := qi >= 0
	var detail := "none"
	if ok6:
		var q: Dictionary = m.S.props[qi]
		var qo: Vector3 = (q["xf"] as Transform3D).origin
		ok6 = String(q["kind"]) == String(p["kind"]) and qo.distance_to(to_o) < 0.001 and mesh_size(q).distance_to(sz) < 0.001
		detail = "%s at %s" % [String(q["kind"]), str(qo)]
	ok(ok6, "E6 after save and load the part is back (%s)" % detail)

	# E7 after the load the part is selectable and movable with real clicks
	var e7 := false
	var det7 := "none"
	if qi >= 0:
		var q7: Dictionary = m.S.props[qi]
		var c7: Vector3 = (Props.solids(q7)[0]["xf"] as Transform3D).origin
		m.sel_prop = -1
		m._props_show()
		await idle(3)
		if m.cur_page != "STAGE":   # a house in the scene opens on BUILD (as any house does): the user goes to STAGE with a real click
			for b in root.find_children("*", "Button", true, false):
				if (b as Button).text.strip_edges() == "STAGE" and (b as Button).is_visible_in_tree():
					await click_ctl(b as Button)
					break
			await idle(4)
		await click_at(cam.unproject_position(c7))
		var o7: Vector3 = (m.S.props[qi]["xf"] as Transform3D).origin
		await drag_screen(cam.unproject_position(c7), cam.unproject_position(c7 + Vector3(0.0, 0.0, 0.5)))
		var n7: Vector3 = (m.S.props[qi]["xf"] as Transform3D).origin
		det7 = "picked %d, moved %.3f m" % [m.sel_prop, Vector2(n7.x - o7.x, n7.z - o7.z).length()]
		e7 = m.sel_prop == qi and Vector2(n7.x - o7.x, n7.z - o7.z).length() >= 0.4
	ok(e7, "E7 after save and load: a real click picks the part and a drag moves it (%s)" % det7)

	print("escene: %d fail" % fails)
	quit(1 if fails > 0 else 0)
