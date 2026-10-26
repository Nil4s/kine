extends SceneTree
## godot --path . --position 4000,4000 -s tests/buildpage_test.gd     (BUILD mode phase 1b: the BUILD page; scripts/build/build_ui.gd; needs a window)
## Bars, written before measuring (real clicks, drags and keys through root.push_input at 1280 x 720; a 3D BUILDING project):
##   1 START   the 3D BUILDING card opens a project of kind "building" on the BUILD page; the page bar is BUILD | STAGE | CHECK |
##             DELIVER (BUILD first, MODEL hidden); the empty-state hint "Drag on the floor to make a room"; Wall / Pull / Floor /
##             Roof / Piece / Words are on the ribbon, disabled, tooltip "coming next"
##   2 ROOM    a real drag 4 x 3 m: the label showed "4.0 m x 3.0 m" DURING the drag and nothing was in the record yet; after the
##             release the record has one 4 x 3 room (outer sizes), the mesh is closed and manifold, exactly one undo step; undo
##             empties the record, redo brings it back
##   3 TYPED   a drag then 4 Tab 3 Enter: a 4 x 3 room, one undo step (and undone again)
##   4 DOOR    a click on the front wall adds a door: the volume drops 0.378 m3 (1e-6), the mesh stays closed, one undo step, undo
##             restores the volume
##   5 SLIDE   a drag along the wall slides the door to 1.0 m (snapped), one undo step
##   6 DELETE  Delete removes it: the volume is back exactly, one undo step; undo puts it back
##   7 PANEL   Wall height typed to 3.0 in the panel: params and mesh follow (volume exact, mesh 3.2 m tall with the floor), one undo
##             step, undo restores; the + stepper is one step of 0.1 m
##   8 FILE    save + new scene + reopen: the record, the mesh volume and the BUILD page come back
##   9 CHROME  (round 1c) on BUILD of a building project the mannequin, joint dots, part tag, target dummy, clips strip, side panels and rails,
##             mouse legend, readout and Next: line are not visible; the ghost person is; an animation project has them all back
##  10 LOOK    the ribbon is icon + one word; "Use in a scene" is top right, disabled, "coming next"; a toast and the status line never cover the
##             panel; a click in a number field selects its whole value
##  11 DOOR    a picked door shows its sky-blue box and is inside the free view; a door on the back wall turns the camera to its outside
## Screenshots: C:/Temp/claude/build1c/{empty,dragging,door,panel,selected,door_back}.png. Only user:// is written.
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/build1c"
const DIRT := "user://buildpage_test"


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


func key(k: Key, ctrl := false, uni := 0) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.unicode = uni
		e.pressed = down
		e.ctrl_pressed = ctrl
		root.push_input(e, true)
		await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


## the screen point of a floor / wall point
func sp(v: Vector3) -> Vector2:
	return m.cam.unproject_position(v)


func drag_floor(x0: float, z0: float, x1: float, z1: float, release := true) -> void:
	await ev_move(sp(Vector3(x0, 0, z0)), false)
	await ev_mouse(sp(Vector3(x0, 0, z0)), true)
	await ev_move(sp(Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)))
	await ev_move(sp(Vector3(x1, 0, z1)))
	if release:
		await ev_mouse(sp(Vector3(x1, 0, z1)), false)
		await idle(2)


func vol() -> float:
	return KMeshValidate._volume(Building.to_kmesh(m.S.building))


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func rec() -> String:
	return JSON.stringify(Building.to_file(m.S.building)) if not m.S.building.is_empty() else "{}"


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
	var bld: BuildUI = m.bld
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]

	# 1 START
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	await idle(6)
	ok(not ss.visible and m.cur_page == "BUILD" and m.S.kind == "building" and bld.on, "1 the 3D BUILDING card: kind %s, page %s" % [m.S.kind, m.cur_page])
	var tabs := []
	var h: Control = (m.ui_page_btns["BUILD"] as Button).get_parent().get_parent()
	for c in h.get_children():
		if String(c.name).begins_with("cell_tab_") and c.visible:
			tabs.append((c.get_child(0) as Button).text)
	ok(tabs == ["BUILD", "STAGE", "CHECK", "DELIVER"], "1 the page bar is %s" % [tabs])
	ok(bld.hint_box.visible and (bld.hint_box.get_child(0) as Label).text == "Drag on the floor to make a room", "1 the empty-state hint shows")
	var later_ok := true
	for t in ["wall", "pull", "floor", "roof", "piece", "words"]:
		var bt: Button = m.ui_ribbon["BUILD"].find_child("build_tool_" + t, true, false)
		later_ok = later_ok and bt != null and bt.disabled and bt.tooltip_text.contains("coming next")
	ok(later_ok, "1 Wall / Pull / Floor / Roof / Piece / Words: on the ribbon, disabled, tooltip \"coming next\"")
	ok(m.S.building.is_empty() and bld.house.mesh == null, "1 no building yet")
	await shot("empty")

	# 2 ROOM
	var n0: int = m.undo.size()
	await drag_floor(0, 0, 4, 3, false)
	var during: String = bld.size_text
	var rec_during: bool = m.S.building.is_empty()
	await shot("dragging")
	await ev_mouse(sp(Vector3(4, 0, 3)), false)
	await idle(2)
	ok(during == "4.0 m x 3.0 m" and rec_during, "2 the label during the drag: \"%s\", the record empty until the release: %s" % [during, rec_during])
	var rooms: Array = m.S.building.get("rooms", [])
	var r0: Dictionary = rooms[0] if rooms.size() == 1 else {}
	ok(rooms.size() == 1 and absf(float(r0["w"]) - 4.0) < 1e-6 and absf(float(r0["d"]) - 3.0) < 1e-6 and absf(float(r0["x"])) < 1e-6 and absf(float(r0["z"])) < 1e-6,
		"2 the record has one room: %s" % [r0])
	var km := Building.to_kmesh(m.S.building)
	ok(km.boundary_edge_count() == 0 and km.is_manifold() and bld.house.mesh != null, "2 the mesh is closed (%d boundary) and manifold %s, drawn %s" % [km.boundary_edge_count(), km.is_manifold(), bld.house.mesh != null])
	ok(m.undo.size() == n0 + 1, "2 exactly one undo step (%d -> %d)" % [n0, m.undo.size()])
	var after_room := rec()
	m._undo()
	await idle(2)
	ok(m.S.building.is_empty() and bld.house.mesh == null, "2 undo empties the record and the mesh")
	m._redo()
	await idle(2)
	ok(rec() == after_room and bld.house.mesh != null, "2 redo brings the room back")

	# 3 TYPED
	n0 = m.undo.size()
	await drag_floor(-5, 0, -4, 1, false)
	for k in [KEY_4, KEY_TAB, KEY_3, KEY_ENTER]:
		await key(k)
	await ev_mouse(sp(Vector3(-4, 0, 1)), false)
	await idle(2)
	rooms = m.S.building.get("rooms", [])
	var r1: Dictionary = rooms[1] if rooms.size() == 2 else {}
	ok(rooms.size() == 2 and absf(float(r1["w"]) - 4.0) < 1e-6 and absf(float(r1["d"]) - 3.0) < 1e-6 and absf(float(r1["x"]) + 5.0) < 1e-6 and m.undo.size() == n0 + 1,
		"3 typed 4 Tab 3 Enter: a 4 x 3 room at x -5, one undo step: %s" % [r1])
	m._undo()
	await idle(2)
	ok(rec() == after_room, "3 undone: back to the one room")

	# 4 DOOR
	await click_ctl(m.ui_ribbon["BUILD"].find_child("build_tool_opening", true, false))
	var v_room := vol()
	n0 = m.undo.size()
	var pick := Vector3(2.0, 2.3, 0.1)   # high on the front wall: the ray clears the back wall
	await click_ctl_at(sp(pick))
	var dv := v_room - vol()
	var km2 := Building.to_kmesh(m.S.building)
	ok(m.S.building["openings"].size() == 1 and absf(dv - 0.378) < 1e-6 and km2.boundary_edge_count() == 0 and km2.is_manifold(),
		"4 a click on the wall: a door, the volume dropped %.6f m3 (want 0.378), closed %s" % [dv, km2.boundary_edge_count() == 0])
	ok(m.undo.size() == n0 + 1, "4 one undo step (%d -> %d)" % [n0, m.undo.size()])
	var with_door := rec()
	m._undo()
	await idle(2)
	ok(absf(vol() - v_room) < 1e-9 and m.S.building["openings"].is_empty(), "4 undo restores the volume (%.6f)" % vol())
	m._redo()
	await idle(2)
	ok(rec() == with_door, "4 redo: the door is back")
	await shot("door")

	# 5 SLIDE
	n0 = m.undo.size()
	await ev_move(sp(Vector3(2.0, 1.9, 0.1)), false)
	await ev_mouse(sp(Vector3(2.0, 1.9, 0.1)), true)
	await ev_move(sp(Vector3(2.5, 1.9, 0.1)))
	await ev_move(sp(Vector3(3.0, 1.9, 0.1)))
	await ev_mouse(sp(Vector3(3.0, 1.9, 0.1)), false)
	await idle(2)
	var at := float(m.S.building["openings"][0]["at"])
	ok(absf(at - 1.0) < 1e-6 and m.undo.size() == n0 + 1, "5 slid along the wall: at %.3f m (want 1.0, snapped), steps %d" % [at, m.undo.size() - n0])
	ok(absf((v_room - vol()) - 0.378) < 1e-6, "5 the door still removes exactly 0.378 m3")

	# 6 DELETE
	n0 = m.undo.size()
	var slid := rec()
	await key(KEY_DELETE)
	ok(m.S.building["openings"].is_empty() and absf(vol() - v_room) < 1e-9 and m.undo.size() == n0 + 1, "6 Delete: the hole fills, volume back to %.6f, one step" % vol())
	m._undo()
	await idle(2)
	ok(rec() == slid, "6 undo puts the slid door back")

	# 7 PANEL
	n0 = m.undo.size()
	var before_h := rec()
	var le: LineEdit = bld.fields["wall_height"]
	await click_ctl(le)
	await key(KEY_A, true)   # select the whole number
	for e in [["3", KEY_3], [".", KEY_PERIOD], ["0", KEY_0]]:
		await key(e[1], false, e[0].unicode_at(0))
	await key(KEY_ENTER)
	await idle(2)
	var want := (4.0 * 3.0 - 3.6 * 2.6) * 3.0 - 0.378 + 4.0 * 3.0 * 0.2
	var hbox: AABB = bld.house.mesh.get_aabb()
	ok(absf(float(m.S.building["params"]["wall_height"]) - 3.0) < 1e-9 and absf(vol() - want) < 1e-5 and absf(hbox.size.y - 3.2) < 1e-4 and m.undo.size() == n0 + 1,
		"7 Wall height typed 3.0: params %.1f, volume %.6f (want %.6f), mesh %.2f m tall, steps %d" % [float(m.S.building["params"]["wall_height"]), vol(), want, hbox.size.y, m.undo.size() - n0])
	await shot("panel")
	n0 = m.undo.size()
	await click_ctl(bld.panel.find_child("step_wall_height_plus", true, false))
	ok(absf(float(m.S.building["params"]["wall_height"]) - 3.1) < 1e-9 and m.undo.size() == n0 + 1, "7 the + stepper: 3.1 m, one step")
	m._undo()
	m._undo()
	await idle(2)
	ok(rec() == before_h, "7 undo x2 restores the record before the height edit")
	m._redo()
	m._redo()
	await idle(2)

	# 8 FILE
	var saved := rec()
	var vsaved := vol()
	var path := DIRT + "/bp.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(m.S.to_dict(m.B, false)))
	f.close()
	m._new_scene()
	await idle(3)
	ok(m.S.building.is_empty() and bld.house.mesh == null, "8 a new scene has no building")
	m._load_scene(path)
	await idle(4)
	ok(rec() == saved and absf(vol() - vsaved) < 1e-6 and bld.house.mesh != null and m.cur_page == "BUILD" and m.S.kind == "building",
		"8 reopened: the record, the mesh (volume %.6f) and the BUILD page are back" % vol())

	# 9 CHROME  (round 1c: a building project's BUILD page shows nothing that animates a fighter)
	await idle(4)
	var hid := true
	var why := []
	for e in [["mannequin", m.man_root], ["target dummy", m.dummy_node], ["part tag", m.tag], ["clips strip", m.ui_bp], ["left panel", m.ui_side_of["left"]], ["right panel", m.ui_side_of["right"]],
			["mouse legend", m.ui_mouse], ["readout", m.ui_bar], ["Next: line", m.ui_next]] + m.dots.values().map(func(d): return ["joint dot", d]) + m.stage_marks.map(func(d): return ["axes / stage square", d]):
		var n: Node = e[1]
		var shown: bool = n != null and ((n as CanvasItem).is_visible_in_tree() if n is CanvasItem else (n as Node3D).is_visible_in_tree())
		if shown:
			hid = false
			why.append(e[0])
	for k in m.ui_rails:
		if (m.ui_rails[k] as Control).is_visible_in_tree():
			hid = false
			why.append("rail " + k)
	ok(hid, "9 on BUILD of a building project the animating chrome is not visible (still visible: %s)" % [why])
	ok(bld.person.visible and bld.person.is_visible_in_tree(), "9 the ghost person (scale) is the one figure left")
	m._new_scene()
	await idle(4)
	ok(m.cur_page == "POSE" and m.man_root.visible and m.ui_bp.visible and not m._hides("figure") and m.dots["head"].visible and m.tag.visible and m.ui_bar.visible,
		"9 an animation project (page %s): mannequin %s, clips strip %s, joint dots %s, readout %s are back" % [m.cur_page, m.man_root.visible, m.ui_bp.visible, m.dots["head"].visible, m.ui_bar.visible])
	m._load_scene(path)
	await idle(4)
	ok(m.cur_page == "BUILD" and not m.man_root.visible and not m.ui_bp.visible, "9 the building project again: the chrome is gone again")

	# 10 RIBBON, TOAST, FIELD
	var words := {"Room": "room", "Wall": "wall", "Pull": "pull", "Opening": "opening", "Floor": "floor", "Roof": "roof", "Piece": "piece", "Words": "words"}
	var rib_ok := true
	for w in words:
		var bt: Button = m.ui_ribbon["BUILD"].find_child("build_tool_" + words[w], true, false)
		rib_ok = rib_ok and bt != null and bt.icon != null and bt.text == w and bt.is_visible_in_tree()
	ok(rib_ok, "10 the ribbon: icon + one word on Room Wall Pull Opening Floor Roof Piece Words")
	var ub: Button = bld.use_btn
	ok(ub != null and ub.is_visible_in_tree() and ub.disabled and ub.tooltip_text.contains("coming next") and ub.text == "Use in a scene" and ub.get_global_rect().position.x > 640.0 and ub.get_global_rect().position.y < 40.0,
		"10 \"Use in a scene\": top right, disabled, tooltip \"coming next\"")
	m._toast("Undid: Opening: removed, the wall is whole again")
	await idle(3)
	var tr: Rect2 = m.ui_toast.get_global_rect()
	var pr: Rect2 = bld.panel.get_global_rect()
	ok(m.ui_toast.is_visible_in_tree() and bld.panel.is_visible_in_tree() and not tr.intersects(pr) and not m.ui_status.get_global_rect().intersects(pr),
		"10 a toast %s and the status line %s never cover the panel %s (title: \"%s\")" % [tr, m.ui_status.get_global_rect(), pr, bld.panel_title.text])
	for fk in ["wall_height", "door_width"]:
		var fe: LineEdit = bld.fields[fk]
		await click_ctl(fe)
		ok(fe.has_focus() and fe.has_selection() and fe.get_selected_text() == fe.text and fe.text != "", "10 a click in %s selects the whole value (\"%s\")" % [fk, fe.get_selected_text()])
	bld.fields["door_width"].release_focus()
	await idle(2)

	# 11 THE DOOR IS SEEN  (a picked opening: sky blue, its width, the slide hint; a door on the far wall turns the camera to it)
	await click_ctl(m.ui_ribbon["BUILD"].find_child("build_tool_opening", true, false))
	var door := Vector3(2.0, 2.3, 0.1)
	await click_ctl_at(sp(door))
	await ev_mouse(sp(Vector3(2.0, 1.9, 0.1)), false)
	await idle(3)
	ok(bld.sel != "" and bld.sel_box.visible and bld.drag == "", "11 a door is picked: id %s, the sky-blue box shows" % bld.sel)
	var cbox := bld._opening_aabb(bld._opening(bld.sel)).get_center()
	var cl: Rect2 = m.nav_clear_rect()
	var dp := sp(cbox)
	ok(cl.has_point(dp) and not pr.has_point(dp), "11 the door is inside the free view at %s (view %s)" % [dp, cl])
	await shot("selected")
	var to_cam: Vector3 = (m.cam.global_position - Vector3(2.0, 0.0, 0.0))
	ok(to_cam.z < 0.0, "11 the door on the front wall is seen from outside (camera z %.1f)" % m.cam.global_position.z)
	await click_ctl_at(sp(Vector3(2.0, 2.3, 2.9)))   # the far wall's inner face, seen over the near wall
	await idle(2)
	var od: Dictionary = bld._opening(bld.sel)
	ok(not od.is_empty() and String(od["wall"]) == "back" and m.cam.global_position.z > 3.0, "11 a door on the back wall: the camera turned to its outside (wall %s, camera z %.1f)" % [od.get("wall", ""), m.cam.global_position.z])
	await shot("door_back")

	print("BUILDPAGE %s: %d failed" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)


func click_ctl_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)
