extends SceneTree
## godot --path . --position 4000,4000 -s tests/p145scenelibra_test.gd     (Friday 145, the scene library: rooms and outdoor sets from the
## free builder). A beginner walk with real clicks at 1280 x 720: start screen -> 3D building -> What to build -> From a template (Easy).
## Bars written before the code. Every measure is read from the built record (mm, counts), never from the code's own variables.
##   R1 the Template list (a real click on the Easy button) names a "Room" and a "Yard" set beside the three houses
##   R2 Room: the chooser closes, Easy on, page BUILD; the building is one room 4000 x 3000 mm, 1 door, 1 window, a flat roof
##   R3 one undo step: Undo takes the room back (the record is the one from before the pick)
##   R4 Yard: one room 6000 x 4000 mm with a 300 mm edge (height 0.3 m), no door, no window, no roof
##   R5 Yard holds a fence, a table and 2 benches (pieces by kind), and one undo step takes the yard back
##   R6 Yard in Expert (Easy off): the same yard record, page BUILD, chooser closed
##   R7 the Room and the Yard are picked in one click each: no refusal text on the status line
## Screenshots: C:/Temp/claude/p145scenelibra/{template_list,room_build,yard_build}.png. Writes only user:// (Houses dir).
const SHOT := "C:/Temp/claude/p145scenelibra"
const BuildStarters := preload("res://scripts/build/build_starters.gd")

var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## a real mouse click at the centre of a control (press and release through the viewport)
func click(c: Control) -> void:
	var p: Vector2 = c.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e, true)
		await process_frame
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


## the number of pieces of one kind in a building record
func pieces_of(b: Dictionary, kind: String) -> int:
	var n := 0
	for p in b.get("pieces", []):
		if String(p.get("kind", "")) == kind:
			n += 1
	return n


## the openings of one kind in a building record
func openings_of(b: Dictionary, kind: String) -> int:
	var n := 0
	for o in b.get("openings", []):
		if String(o.get("kind", "")) == kind:
			n += 1
	return n


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
	var bc: BuildChoose = m.build_choose
	var dirt := "user://p145scenelibra_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dirt))
	ss.dirs_override = [dirt]

	# the beginner's walk: the start screen, the 3D building card, then What to build (a real click on the reopen button)
	ss.show_screen()
	await idle(3)
	await click(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(8)
	await click(m.bld.part.reopen_btn)
	await idle(6)

	# R1 the Template card's Easy button opens the list (a real click); the list has the Room and the Yard
	await click(bc.btns["template"]["easy"])
	var pm: PopupMenu = bc._starters
	var names := []
	if pm != null:
		for i in pm.item_count:
			names.append(pm.get_item_text(i))
	var room_i := -1
	var yard_i := -1
	for i in BuildStarters.LIST.size():
		var nm := String(BuildStarters.LIST[i]["name"])
		if nm == "Room":
			room_i = i
		if nm == "Yard":
			yard_i = i
	var listed: bool = false
	if pm != null and pm.visible and room_i >= 0 and yard_i >= 0:
		var has_room := false
		var has_yard := false
		for t in names:
			has_room = has_room or String(t).begins_with("Room:")
			has_yard = has_yard or String(t).begins_with("Yard:")
		listed = has_room and has_yard
	ok(listed, "R1 the Template list (a real click on Easy) shows a Room and a Yard set: %s" % str(names))
	await shot("template_list")

	# R2 pick Room (Easy): the chooser closes, Easy on, page BUILD; the record is one 4 m x 3 m room, 1 door, 1 window, flat roof
	var before := JSON.stringify(Building.to_file(m.S.building)) if not m.S.building.is_empty() else ""
	pm.id_pressed.emit(room_i)
	await idle(6)
	var b: Dictionary = m.S.building
	var rooms: Array = b.get("rooms", [])
	var r2: bool = not bc.open and m.easy.on and m.cur_page == "BUILD" and rooms.size() == 1
	if r2:
		var r0: Dictionary = rooms[0]
		r2 = int(round(float(r0["w"]) * 1000.0)) == 4000 and int(round(float(r0["d"]) * 1000.0)) == 3000
		r2 = r2 and openings_of(b, "door") == 1 and openings_of(b, "window") == 1
		r2 = r2 and String((b.get("roof", {}) as Dictionary).get("kind", "")) == "flat"
	var got2 := "%d rooms" % rooms.size()
	if rooms.size() == 1:
		got2 = "room %d x %d mm, %d doors, %d windows, roof %s" % [int(round(float(rooms[0]["w"]) * 1000.0)), int(round(float(rooms[0]["d"]) * 1000.0)),
			openings_of(b, "door"), openings_of(b, "window"), String((b.get("roof", {}) as Dictionary).get("kind", "none"))]
	ok(r2, "R2 Room (Easy): chooser closed, Easy on, page BUILD, one room 4000 x 3000 mm, 1 door, 1 window, flat roof (%s, page %s)" % [got2, m.cur_page])
	await shot("room_build")

	# R3 one undo step takes the room back
	m._undo()
	await idle(4)
	var back: bool = JSON.stringify(Building.to_file(m.S.building)) == before if before != "" else (m.S.building.is_empty() or (m.S.building.get("rooms", []) as Array).is_empty())
	ok(back, "R3 one undo step: Undo takes the room back to the record from before the pick")

	# R4 + R5 pick Yard (Easy): the room is 6000 x 4000 mm with a 300 mm edge; no door, no window, no roof; a fence, a table, 2 benches
	bc.show_chooser()
	await idle(4)
	await click(bc.btns["template"]["easy"])
	pm = bc._starters
	pm.id_pressed.emit(yard_i)
	await idle(6)
	var yb: Dictionary = m.S.building
	var yrooms: Array = yb.get("rooms", [])
	var r4: bool = yrooms.size() == 1
	if r4:
		var y0: Dictionary = yrooms[0]
		var h_mm := int(round(float(y0.get("height", -1.0)) * 1000.0))
		r4 = int(round(float(y0["w"]) * 1000.0)) == 6000 and int(round(float(y0["d"]) * 1000.0)) == 4000 and h_mm == 300
		r4 = r4 and openings_of(yb, "door") == 0 and openings_of(yb, "window") == 0 and not yb.has("roof")
	ok(r4, "R4 Yard: one room 6000 x 4000 mm, edge 300 mm high, no door, no window, no roof (%d rooms)" % yrooms.size())
	var r5: bool = pieces_of(yb, "fence") == 1 and pieces_of(yb, "table") == 1 and pieces_of(yb, "bench") == 2
	ok(r5, "R5 Yard pieces: 1 fence, 1 table, 2 benches (fence %d, table %d, bench %d)" % [pieces_of(yb, "fence"), pieces_of(yb, "table"), pieces_of(yb, "bench")])
	await shot("yard_build")

	# R6 Yard in Expert (Easy off): the same yard record, page BUILD, chooser closed
	m._undo()
	await idle(4)
	m.easy.set_on(false)
	bc.show_chooser()
	await idle(4)
	await click(bc.btns["template"]["expert"])
	pm = bc._starters
	pm.id_pressed.emit(yard_i)
	await idle(6)
	var r6: bool = not bc.open and not m.easy.on and m.cur_page == "BUILD" and String(m.S.building.get("name", "")) == "Yard"
	r6 = r6 and pieces_of(m.S.building, "fence") == 1 and not m.S.building.has("roof")
	ok(r6, "R6 Yard (Expert): Easy off, page BUILD, chooser closed, the yard record (name Yard, fence, no roof)")

	# R7 no refusal on the status line after the picks
	var said := String(m._step_hint) + " " + String(m.ui_status.text) if m.ui_status != null else ""
	ok(not said.to_lower().contains("did not build") and not said.to_lower().contains("doesn't know"), "R7 no refusal text after the picks: %s" % said.left(120))

	print("p145scenelibra fails: %d" % fails)
	quit(fails)
