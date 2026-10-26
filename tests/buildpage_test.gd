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
## Phase 1d (real clicks and drags; a fresh 6 x 4 house with a front door):
##  12 WALL    Wall, Pull, Floor and Roof are enabled (Words not); a drag inside the room adds an interior wall at 3.0 m: 1 undo step, closed, +0.972 m3;
##             a wall on a wall is refused; a click on that wall with Opening adds a door in it (-0.189 m3)
##  13 PULL    dragging a side wall 1 m out: the room is 7 x 4, ONE undo step, the live label says "+1.0 m", the front door keeps its offset from the
##             wall's middle, the interior wall stays at world x 3
##  14 FLOOR   + Floor: a second room at storey 1, 1 undo step, closed, the exact added volume, the panel lists "Floor 2", the house is 5.5 m tall
##  15 ROOF    Gable button: 1 step, closed, analytic prism volume, the overhang follows the param; undo / redo
##  16 SCENE   Use in a scene: STAGE, a prop with collision (boxes = walls + floors volume), the doorway open and the wall beside it solid, named point
##             "front door"; editing the door in BUILD moves the gap
##  17 WALK    "Walk through the front door": cards in a new scene, the root passes the doorway plane, no foot inside a wall box, feet on the floor
## (bars 1 and 10 of phase 1b said Wall / Pull / Floor / Roof / "Use in a scene" are disabled "coming next": phase 1d enables them, so those two
## bars now say the opposite, and Piece / Words stay disabled)
## Screenshots: C:/Temp/claude/build1c/{empty,dragging,door,panel,selected,door_back}.png and C:/Temp/claude/build1d/{wall,pull,floors,roof,scene,scene_walk}.png.
## Only user:// is written.
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
	for t in ["piece", "words"]:   # (1d: Wall, Pull, Floor and Roof are tools now: bar 12)
		var bt: Button = m.ui_ribbon["BUILD"].find_child("build_tool_" + t, true, false)
		later_ok = later_ok and bt != null and bt.disabled and bt.tooltip_text.contains("coming next")
	ok(later_ok, "1 Piece / Words: on the ribbon, disabled, tooltip \"coming next\"")
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
	ok(ub != null and ub.is_visible_in_tree() and not ub.disabled and ub.text == "Use in a scene" and ub.get_global_rect().position.x > 640.0 and ub.get_global_rect().position.y < 40.0,
		"10 \"Use in a scene\": top right, enabled (phase 1d; there is a room)")
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

	# ======================================================= phase 1d: Wall, Pull, Floor, Roof, Use in a scene (a fresh 6 x 4 house)
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	await idle(6)
	await drag_floor(0, 0, 6, 4)
	await click_ctl(m.ui_ribbon["BUILD"].find_child("build_tool_opening", true, false))
	await click_ctl_at(sp(Vector3(3.0, 2.3, 0.1)))
	var front_door := String(m.S.building["openings"][0]["id"]) if m.S.building.get("openings", []).size() == 1 else ""
	ok(front_door != "" and String(m.S.building["openings"][0]["wall"]) == "front", "12 a fresh 6 x 4 house with a front door (%s)" % [m.S.building.get("openings", [])])
	var v_room6 := vol()

	# 12 WALL
	var wbtn: Button = m.ui_ribbon["BUILD"].find_child("build_tool_wall", true, false)
	ok(not wbtn.disabled and not (m.ui_ribbon["BUILD"].find_child("build_tool_pull", true, false) as Button).disabled and not (m.ui_ribbon["BUILD"].find_child("build_tool_floor", true, false) as Button).disabled
		and not (m.ui_ribbon["BUILD"].find_child("build_tool_roof", true, false) as Button).disabled and (m.ui_ribbon["BUILD"].find_child("build_tool_words", true, false) as Button).disabled,
		"12 Wall, Pull, Floor, Roof are enabled; Words stays coming next")
	await click_ctl(wbtn)
	n0 = m.undo.size()
	await drag_floor(3.0, 0.8, 3.0, 3.2, false)
	var wprev: Dictionary = bld.wall_spec()
	await ev_mouse(sp(Vector3(3.0, 0, 3.2)), false)
	await idle(2)
	var iws: Array = m.S.building.get("walls", [])
	var kw := Building.to_kmesh(m.S.building)
	ok(wprev.get("ok", false) and iws.size() == 1 and String(iws[0]["axis"]) == "z" and absf(float(iws[0]["pos"]) - 3.0) < 1e-9 and m.undo.size() == n0 + 1 and kw.boundary_edge_count() == 0 and kw.is_manifold(),
		"12 a drag inside the room: an interior wall %s, one undo step, closed %s" % [iws, kw.boundary_edge_count() == 0])
	ok(absf((vol() - v_room6) - 0.1 * 3.6 * 2.7) < 1e-5, "12 the wall adds %.6f m3 (want %.6f)" % [vol() - v_room6, 0.1 * 3.6 * 2.7])
	var with_wall := rec()
	m._undo()
	await idle(2)
	ok(m.S.building.get("walls", []).is_empty() and absf(vol() - v_room6) < 1e-9, "12 undo takes the wall away again")
	m._redo()
	await idle(2)
	ok(rec() == with_wall, "12 redo: the wall is back")
	await click_ctl(wbtn)
	await drag_floor(3.0, 1.2, 3.0, 2.8, false)   # a second wall on the same place: refused, no new undo step
	var dup_spec: Dictionary = bld.wall_spec()
	n0 = m.undo.size()
	await ev_mouse(sp(Vector3(3.0, 0, 2.8)), false)
	await idle(2)
	ok(not bool(dup_spec["ok"]) and m.S.building["walls"].size() == 1 and m.undo.size() == n0, "12 a wall on top of a wall is refused (\"%s\"), no undo step" % dup_spec.get("why", ""))
	await click_ctl(m.ui_ribbon["BUILD"].find_child("build_tool_opening", true, false))
	n0 = m.undo.size()
	var v_w := vol()
	await click_ctl_at(sp(Vector3(3.05, 2.3, 2.0)))
	var ops: Array = m.S.building["openings"]
	var inner_door: Dictionary = ops[-1]
	var kd2 := Building.to_kmesh(m.S.building)
	ok(ops.size() == 2 and String(inner_door["wall"]) == "i1" and absf((v_w - vol()) - 0.9 * 2.1 * 0.1) < 1e-5 and kd2.boundary_edge_count() == 0 and kd2.is_manifold() and m.undo.size() == n0 + 1,
		"12 a door in the interior wall: wall %s, removes %.6f m3 (want %.6f), closed, one step" % [inner_door.get("wall", ""), v_w - vol(), 0.9 * 2.1 * 0.1])
	await shot2("wall")

	# 13 PULL
	await click_ctl(m.ui_ribbon["BUILD"].find_child("build_tool_pull", true, false))
	var before_pull := rec()
	var left_side: bool = m.cam.global_position.x < 3.0
	var fx := 0.02 if left_side else 5.98
	var tx := -0.98 if left_side else 6.98
	n0 = m.undo.size()
	await ev_move(sp(Vector3(fx, 1.5, 2.0)), false)
	await ev_mouse(sp(Vector3(fx, 1.5, 2.0)), true)
	await ev_move(sp(Vector3((fx + tx) * 0.5, 1.5, 2.0)))
	await ev_move(sp(Vector3(tx, 1.5, 2.0)))
	var pull_text: String = bld._pull.get("text", "")
	var rd: Dictionary = m.S.building["rooms"][0]
	var steps_during: int = m.undo.size() - n0
	await shot2("pull")
	await ev_mouse(sp(Vector3(tx, 1.5, 2.0)), false)
	await idle(2)
	rd = m.S.building["rooms"][0]
	var iw0: Dictionary = m.S.building["walls"][0]
	var fdoor: Dictionary = m.S.building["openings"][0]
	var fbox: AABB = Building.opening_box(m.S.building, rd, fdoor)
	ok(absf(float(rd["w"]) - 7.0) < 1e-9 and absf(float(rd["x"]) - (-1.0 if left_side else 0.0)) < 1e-9 and absf(float(rd["d"]) - 4.0) < 1e-9 and m.undo.size() == n0 + 1 and steps_during == 1,
		"13 a pull of the %s wall by 1 m: the room is %s x %s at x %s, ONE undo step (after the first move: %d)" % ["left" if left_side else "right", rd["w"], rd["d"], rd["x"], steps_during])
	ok(pull_text.contains("1.0 m") and pull_text.contains("7.0"), "13 the live label said \"%s\"" % pull_text)
	ok(absf(float(fdoor["at"])) < 1e-9 and absf(fbox.get_center().x - (float(rd["x"]) + float(rd["w"]) * 0.5)) < 1e-6 and absf(float(rd["x"]) + float(iw0["pos"]) - 3.0) < 1e-9,
		"13 the front door kept its offset from the wall's middle (at %.2f, centre x %.2f, wall middle %.2f); the interior wall stayed at world x %.2f" % [fdoor["at"], fbox.get_center().x, float(rd["x"]) + float(rd["w"]) * 0.5, float(rd["x"]) + float(iw0["pos"])])
	var kp := Building.to_kmesh(m.S.building)
	ok(kp.boundary_edge_count() == 0 and kp.is_manifold(), "13 the pulled house is closed (%d boundary), manifold" % kp.boundary_edge_count())
	m._undo()
	await idle(2)
	ok(rec() == before_pull, "13 undo gives the room back at 6 m")
	m._redo()
	await idle(2)

	# 14 FLOOR
	await click_ctl(m.ui_ribbon["BUILD"].find_child("build_tool_floor", true, false))
	var v_one_floor := vol()
	var rd1: Dictionary = m.S.building["rooms"][0]
	var pw := float(rd1["w"])
	var pd := float(rd1["d"])
	n0 = m.undo.size()
	var addf: Button = bld.panel.find_child("build_add_floor", true, false)
	ok(addf != null and addf.is_visible_in_tree(), "14 the Floor tool shows + Floor in the panel (list: \"%s\")" % bld.floors_label.text.replace("\n", " | "))
	await click_ctl(addf)
	var rooms2: Array = m.S.building["rooms"]
	var ring_a := pw * pd - (pw - 0.4) * (pd - 0.4)
	var added := ring_a * 2.7 + 0.1 * (pd - 0.4) * 2.7 + pw * pd * 0.2 - ring_a * 0.1 - 0.1 * (pd - 0.4) * 0.1
	var k2 := Building.to_kmesh(m.S.building)
	ok(rooms2.size() == 2 and int(rooms2[1].get("storey", 0)) == 1 and m.undo.size() == n0 + 1 and k2.boundary_edge_count() == 0 and k2.is_manifold() and absf((vol() - v_one_floor) - added) < 1e-4,
		"14 + Floor: 2 rooms (storey %s), one undo step, closed %s, the floor adds %.6f m3 (want %.6f)" % [rooms2[1].get("storey", 0) if rooms2.size() > 1 else "-", k2.boundary_edge_count() == 0, vol() - v_one_floor, added])
	ok(bld.floors_label.text.contains("Floor 2") and absf(float(m.S.building["params"]["floor_height"]) - 2.8) < 1e-9 and absf(bld.house.mesh.get_aabb().end.y - 5.5) < 1e-3,
		"14 the panel lists the floors (\"%s\"); floor_height 2.8, the house is %.2f m tall" % [bld.floors_label.text.replace("\n", " | "), bld.house.mesh.get_aabb().end.y])
	await shot2("floors")

	# 15 ROOF
	await click_ctl(m.ui_ribbon["BUILD"].find_child("build_tool_roof", true, false))
	var v_floors := vol()
	n0 = m.undo.size()
	await click_ctl(bld.panel.find_child("build_roof_gable", true, false))
	var rfk := Building.to_kmesh(m.S.building)
	var rect_w := pw + 0.9
	var rect_d := pd + 0.9
	var rspan := minf(rect_w, rect_d)
	var rlen := maxf(rect_w, rect_d)
	var rrise := tan(deg_to_rad(Building.ROOF_PITCH)) * rspan
	var want_g := 0.5 * rspan * rrise * 0.5 * rlen
	ok(m.S.building.get("roof", {}).get("kind", "") == "gable" and m.undo.size() == n0 + 1 and rfk.boundary_edge_count() == 0 and rfk.is_manifold() and absf((vol() - v_floors) - want_g) < 1e-4,
		"15 Roof gable: record %s, one undo step, closed %s, the roof adds %.6f m3 (analytic %.6f)" % [m.S.building.get("roof", {}), rfk.boundary_edge_count() == 0, vol() - v_floors, want_g])
	ok(m.S.building["roof"]["overhang"] == "roof_overhang" and Building.num(m.S.building, m.S.building["roof"]["overhang"]) == 0.45, "15 the overhang follows the roof_overhang param (0.45 m)")
	await shot2("roof")
	m._undo()
	await idle(2)
	ok(m.S.building.get("roof", {}).is_empty(), "15 undo takes the roof off")
	m._redo()
	await idle(2)

	# 16 USE IN A SCENE
	var ub2: Button = bld.use_btn
	ok(ub2.is_visible_in_tree() and not ub2.disabled and ub2.text == "Use in a scene", "16 \"Use in a scene\" is enabled now that there is a room")
	n0 = m.undo.size()
	var np: int = m.S.props.size()
	await click_ctl(ub2)
	await idle(3)
	var pidx := BuildStage.prop_index(m.S)
	ok(m.cur_page == "STAGE" and pidx >= 0 and m.S.props.size() == np + 1 and m.undo.size() == n0 + 1 and ub2.text == "Back to BUILD" and bld.stage_panel.visible,
		"16 Use in a scene: page %s, the house is prop %d of %d, one undo step, the button reads \"%s\", the STAGE panel shows" % [m.cur_page, pidx, m.S.props.size(), ub2.text])
	var prop: Dictionary = m.S.props[pidx]
	var cbx: Array = Building.collision_boxes(m.S.building)
	var cvol := 0.0
	for bx in cbx:
		var hh: Vector3 = bx["half"]
		cvol += 8.0 * hh.x * hh.y * hh.z
	var door_pt: Dictionary = Building.anchor(m.S.building, "front door")
	var dpos: Vector3 = door_pt.get("pos", Vector3.ZERO)
	var in_door := dpos + Vector3(0, 1.0, 0)
	var beside := dpos + Vector3(1.3, 1.0, 0)
	ok(Props.solids(prop).size() == cbx.size() and cbx.size() > 4 and absf(cvol - vol_roles(["wall", "floor"])) < 1e-4 and Props.depth(prop, in_door, in_door, 0.05) == 0.0 and Props.depth(prop, beside, beside, 0.05) > 0.0,
		"16 collision on STAGE: %d boxes, volume %.6f = the walls + floors %.6f; the doorway is open (depth %.3f), the wall beside it is not (depth %.3f)" % [cbx.size(), cvol, vol_roles(["wall", "floor"]), Props.depth(prop, in_door, in_door, 0.05), Props.depth(prop, beside, beside, 0.05)])
	ok(Props.supports(prop).size() == 2 and not Building.anchors(m.S.building).is_empty() and Building.anchors(m.S.building)[0]["name"] == "front door",
		"16 the floor slabs hold the feet (%d supports); the named points: %s" % [Props.supports(prop).size(), Building.anchors(m.S.building).map(func(a): return a["name"])])
	await shot2("scene")
	# the house follows an edit: back to BUILD, widen the door, the gap on STAGE moves with it (re-registered from the record)
	await click_ctl(ub2)
	await idle(2)
	ok(m.cur_page == "BUILD" and ub2.text == "Use in a scene", "16 Back to BUILD returns to BUILD")
	m.S.building["openings"][0]["at"] = 1.0
	bld.sync()
	var moved_gap := Building.anchor(m.S.building, "front door")["pos"] as Vector3
	var p_after: Dictionary = m.S.props[BuildStage.prop_index(m.S)]
	ok(absf(moved_gap.x - (dpos.x + 1.0)) < 1e-6 and Props.depth(p_after, moved_gap + Vector3(0, 1, 0), moved_gap + Vector3(0, 1, 0), 0.05) == 0.0 and Props.depth(p_after, in_door, in_door, 0.05) > 0.0,
		"16 the door moved 1 m in BUILD: the gap on STAGE moved with it (old gap now solid: %s)" % [Props.depth(p_after, in_door, in_door, 0.05) > 0.0])
	m.S.building["openings"][0]["at"] = 0.0
	bld.sync()
	await click_ctl(ub2)
	await idle(3)

	# 17 WALK THROUGH THE FRONT DOOR
	var wbt: Button = bld.stage_panel.find_child("build_walk_front_door", true, false)
	ok(wbt != null and wbt.is_visible_in_tree() and wbt.text == "Walk through the front door", "17 the STAGE panel offers \"Walk through the front door\"")
	var old_scene: Scene = m.S
	n0 = m.undo.size()
	await click_ctl(wbt)
	await idle(4)
	var Sw: Scene = m.S
	var pi2 := BuildStage.prop_index(Sw)
	ok(Sw != old_scene and Sw.cards.size() > 4 and pi2 >= 0 and Sw.kind == "building" and not Sw.building.is_empty() and m.undo.size() == n0 + 1,
		"17 the walk: %d cards in a new scene that carries the house (prop %d); one undo step" % [Sw.cards.size(), pi2])
	var pr2: Dictionary = Sw.props[pi2]
	var fw: Dictionary = Building.anchor(Sw.building, "front door")
	var dpt: Vector3 = fw["pos"]
	var outw: Vector3 = fw["out"]
	var ts: Array = Sw.times()
	var t0: float = ts[0][0]
	var t1: float = ts[-1][1]
	var wall_boxes := Building.collision_boxes(Sw.building).filter(func(bx): return (bx["xf"] as Transform3D).origin.y - (bx["half"] as Vector3).y > -1e-6)   # the walls: not the slabs under the floor
	Props.register_building("building:_walls_probe", wall_boxes, [])
	var wall_prop := Props.make("building:_walls_probe", Transform3D.IDENTITY)
	var inside_min := INF
	var inside_max := -INF
	var worst_depth := 0.0
	var floor_sink := -INF
	var low_ball := INF
	var worst_wall_gap := INF
	var frames := 0
	var start_off := Vector3.ZERO
	for fi in int((t1 - t0) * 60.0) + 1:
		Sw.apply(m.B, t0 + fi / 60.0)
		frames += 1
		var off: Vector3 = m.B.offset
		if fi == 0:
			start_off = off
		var along := -((off - dpt).dot(outw))   # metres past the doorway plane, going in
		inside_min = minf(inside_min, along)
		inside_max = maxf(inside_max, along)
		for j in ["ball_l", "ball_r", "foot_l", "foot_r"]:
			var jp: Vector3 = m.B.P[j]
			worst_depth = maxf(worst_depth, Props.depth(wall_prop, jp, jp, 0.02))
			floor_sink = maxf(floor_sink, -jp.y)
			if j.begins_with("ball"):
				low_ball = minf(low_ball, jp.y)
	ok(inside_min < -0.5 and inside_max > 0.5, "17 the fighter's root passes the doorway plane: from %.2f m outside to %.2f m inside (start %s)" % [-inside_min, inside_max, start_off])
	ok(worst_depth == 0.0, "17 no foot (ankle or ball) is inside a wall box over %d frames (%d wall boxes): the deepest is %.4f m" % [frames, wall_boxes.size(), worst_depth])
	ok(low_ball > -0.01 and low_ball < 0.05 and floor_sink < 0.01, "17 the feet stay on the floor: the lowest ball is at y %.4f m" % low_ball)
	Sw.apply(m.B, t0 + (t1 - t0) * 0.45)
	m.playhead = t0 + (t1 - t0) * 0.45
	await idle(4)
	await shot2("scene_walk")

	print("BUILDPAGE %s: %d failed" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)


func click_ctl_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


const SHOT2 := "C:/Temp/claude/build1d"


func shot2(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT2)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT2, nm])


func vol_roles(roles: Array) -> float:
	return KMeshValidate._volume(Building.to_kmesh(m.S.building, roles))
