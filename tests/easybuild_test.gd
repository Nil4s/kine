extends SceneTree
## godot --path . --position 4000,4000 -s tests/easybuild_test.gd     (EASY BUILDING: scripts/easy_build.gd; needs a window)
## Bars, written before measuring. Real mouse clicks and drags through root.push_input at 1280 x 720, from the start screen:
##   1 START   start screen: the Building card has an Easy / Expert toggle (no "Easy mode coming"); Easy then the card opens BUILD in Easy
##   2 LOOK    Easy's own big bar (Undo, Words, Switch to Expert, Done) and the left column (Room, Door, Window, + Floor, Roof, Stairs, Use in a
##             scene) show; Expert's ribbon, top strip, side panel, picker, Snap chip and Easy's own pose bar do not
##   3 ROOM    a drag on the floor makes one room: ONE undo step; undo empties the record, redo brings it back
##   4 OPENING Door then a click on a wall: one door, one undo step; Window then a click on a wall: one window, one undo step
##   5 FLOOR   + Floor: a second floor, one undo step
##   6 ROOF    Roof cycles gable, flat, none, gable: one undo step each, the record follows
##   7 STAIRS  Stairs then a click in the room: one stairs piece, one undo step
##   8 WORDS   Words opens the same words box (BuildWordsUI), right of the column
##   9 TEXT    no key name (Esc, Tab, Enter, Delete, Ctrl, Alt, Shift, Backspace, Space, F1..) in any visible text or in the tooltips of Easy's bar and column
##  10 FIT     at 1280 x 720 every Easy-build piece is inside the window and none overlaps another or the status line, the nav strip, the cube
##  11 EXPERT  Switch to Expert: the same building record (byte for byte), Expert's ribbon is back, Easy's bar and column are gone
##  12 SCENE   Use in a scene (Easy): the page is STAGE and the house is a set (prop) on STAGE
##  13 DONE    Done: the start screen shows (or the save question first)
## Screenshots: C:/Temp/claude/easybuild/{empty,house,scene}.png. Only user:// is written.
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/easybuild"
const DIRT := "user://easybuild_test"
const KEYS := ["Esc", "Escape", "Tab", "Enter", "Return", "Delete", "Del", "Ctrl", "Alt", "Shift", "Backspace", "Space", "Spacebar", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"]


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


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func sp(v: Vector3) -> Vector2:
	return m.cam.unproject_position(v)


func drag_floor(x0: float, z0: float, x1: float, z1: float) -> void:
	await ev_move(sp(Vector3(x0, 0, z0)), false)
	await ev_mouse(sp(Vector3(x0, 0, z0)), true)
	await ev_move(sp(Vector3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5)))
	await ev_move(sp(Vector3(x1, 0, z1)))
	await ev_mouse(sp(Vector3(x1, 0, z1)), false)
	await idle(2)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func rec() -> String:
	return JSON.stringify(Building.to_file(m.S.building)) if not m.S.building.is_empty() else "{}"


## a control of Easy's build screen by name
func btn(nm: String) -> Button:
	return m.ui_root.find_child(nm, true, false) as Button


func openings_of(kind: String) -> int:
	var n := 0
	for o in m.S.building.get("openings", []):
		if String(o["kind"]) == kind:
			n += 1
	return n


## the first key name in a text (whole words)
func key_in(t: String) -> String:
	var s := t
	for ch in ["/", ",", ".", ":", "(", ")", "+", "\n", "!", "?", ";", "\""]:
		s = s.replace(ch, " ")
	for w in s.split(" ", false):
		if KEYS.has(w):
			return w
	return ""


func texts_under(n: Node, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label and (n as Label).text.strip_edges() != "":
		out.append([String(n.name), (n as Label).text])
	elif n is Button and (n as Button).text.strip_edges() != "":
		out.append([String(n.name), (n as Button).text])
	for c in n.get_children():
		texts_under(c, out)


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
	var soon := ss.find_child("easy_soon_building", true, false)
	ok(soon == null and ss.find_child("easy_building", true, false) != null and ss.find_child("expert_building", true, false) != null, "1 the Building card has Easy and Expert buttons, no 'Easy mode coming'")
	await click_ctl(ss.find_child("easy_building", true, false))
	await click_ctl(ss._cards["building"])
	await idle(8)
	ok(not ss.visible and m.S.kind == "building" and m.cur_page == "BUILD" and bld.on and m.easy.on, "1 Building -> Easy opens BUILD in Easy (kind %s, page %s, easy %s)" % [m.S.kind, m.cur_page, m.easy.on])

	# 2 LOOK
	var eb: EasyBuild = m.easy.building
	var names := ["easybuild_btn_undo", "easybuild_btn_words", "easybuild_btn_switch_to_expert", "easybuild_btn_done"]
	var cols := ["easybuild_room", "easybuild_door", "easybuild_window", "easybuild_floor", "easybuild_roof", "easybuild_stairs", "easybuild_use"]
	var missing := []
	for n in names + cols:
		var b := m.ui_root.find_child(n, true, false) as Control
		if b == null or not b.is_visible_in_tree():
			missing.append(n)
	ok(missing.is_empty(), "2 Easy's bar (Undo, Words, Switch to Expert, Done) and the column (Room, Door, Window, + Floor, Roof, Stairs, Use in a scene) show %s" % [missing])
	var hidden_bad := []
	for c in [m.ui_top_bar, m.ui_ribbon["BUILD"], bld.panel, bld.picker, bld.chip, bld.hint_box, bld.use_btn, m.easy.bar, m.easy.views, m.easy.home.panel, m.easy.home.strip]:
		if c != null and (c as CanvasItem).is_visible_in_tree():
			hidden_bad.append(String(c.name))
	ok(hidden_bad.is_empty(), "2 nothing of Expert BUILD's ribbon, panel, picker, Snap chip, strip or Easy's pose bar shows %s" % [hidden_bad])
	ok((m.ui_root.find_child("easybuild_use", true, false) as Button).theme_type_variation == "Main" and eb.hint.visible and eb._hint_l.text == "Drag on the floor to make a room", "2 'Use in a scene' is the yellow Main button; the hint is one plain sentence (\"%s\")" % eb._hint_l.text)
	await shot("empty")

	# 3 ROOM
	var n0: int = m.undo.size()
	await drag_floor(0, 0, 8, 5)
	var rooms: Array = m.S.building.get("rooms", [])
	ok(rooms.size() == 1 and absf(float(rooms[0]["w"]) - 8.0) < 1e-6 and absf(float(rooms[0]["d"]) - 5.0) < 1e-6 and m.undo.size() == n0 + 1, "3 a drag on the floor: one 8 x 5 room, one undo step (%d -> %d)" % [n0, m.undo.size()])
	var after_room := rec()
	m._undo()
	await idle(2)
	var emptied: bool = m.S.building.is_empty() or (m.S.building.get("rooms", []) as Array).is_empty()
	m._redo()
	await idle(2)
	ok(emptied and rec() == after_room, "3 undo empties the building, redo brings the room back")

	# 4 OPENINGS
	await click_ctl(btn("easybuild_door"))
	ok(bld.tool == "Opening" and bld.kind == "door" and eb._hint_l.text == "Click a wall to put a door in it", "4 Door: the Opening tool with a door in hand, the hint says so (\"%s\")" % eb._hint_l.text)
	n0 = m.undo.size()
	await click_at(sp(Vector3(2.0, 1.2, 0.1)))
	ok(openings_of("door") == 1 and m.undo.size() == n0 + 1, "4 a click on the front wall: one door, one undo step (doors %d, steps %d)" % [openings_of("door"), m.undo.size() - n0])
	await click_ctl(btn("easybuild_window"))
	n0 = m.undo.size()
	print("     window click at ", sp(Vector3(5.0, 1.2, 0.1)))
	await click_at(sp(Vector3(5.0, 1.2, 0.1)))
	ok(openings_of("window") == 1 and openings_of("door") == 1 and m.undo.size() == n0 + 1, "4 Window then a click on a wall: one window, one undo step (windows %d, steps %d)" % [openings_of("window"), m.undo.size() - n0])

	# 5 FLOOR
	n0 = m.undo.size()
	await click_ctl(btn("easybuild_floor"))
	ok(Building.storey_count(m.S.building) == 2 and m.undo.size() == n0 + 1, "5 + Floor: %d floors, one undo step" % Building.storey_count(m.S.building))

	# 6 ROOF
	var kinds := []
	var steps_ok := true
	for i in 4:
		n0 = m.undo.size()
		await click_ctl(btn("easybuild_roof"))
		kinds.append(String(m.S.building.get("roof", {}).get("kind", "none")))
		steps_ok = steps_ok and m.undo.size() == n0 + 1
	ok(kinds == ["gable", "flat", "none", "gable"] and steps_ok, "6 Roof cycles gable, flat, none, gable, one undo step each %s" % [kinds])

	# 7 STAIRS
	await click_ctl(btn("easybuild_stairs"))
	ok(bld.tool == "Piece" and bld.piece_kind == "stairs" and not bld.picker.visible, "7 Stairs: in hand, no Expert picker")
	n0 = m.undo.size()
	await click_at(sp(Vector3(4.0, 0, 2.5)))
	var stairs := 0
	for p in m.S.building.get("pieces", []):
		if BuildPieces.is_stairs(p):
			stairs += 1
	ok(stairs == 1 and m.undo.size() == n0 + 1, "7 a click in the room: one stairs piece, one undo step (stairs %d, steps %d)" % [stairs, m.undo.size() - n0])
	await click_ctl(btn("easybuild_room"))
	await shot("house")

	# 8 WORDS
	await click_ctl(btn("easybuild_btn_words"))
	var wbox: Control = bld.words.box
	ok(bld.tool == "Words" and wbox.is_visible_in_tree() and wbox.get_global_rect().position.x >= eb.col.get_global_rect().end.x, "8 Words opens the same words box, right of the column (tool %s, box x %.0f, column end %.0f)" % [bld.tool, wbox.get_global_rect().position.x, eb.col.get_global_rect().end.x])
	await shot("words")
	await click_ctl(btn("easybuild_room"))
	ok(bld.tool == "Room" and not wbox.is_visible_in_tree(), "8 Room closes the words box")

	# 9 TEXT
	var seen := []
	texts_under(root, seen)
	var bad := []
	for t in seen:
		var k := key_in(String(t[1]))
		if k != "":
			bad.append("%s '%s' (%s)" % [t[0], t[1], k])
	for c in [eb.bar, eb.col]:
		for n in (c as Node).find_children("*", "Button", true, false):
			var k2 := key_in((n as Button).tooltip_text)
			if k2 != "":
				bad.append("tooltip of %s (%s)" % [n.name, k2])
	ok(bad.is_empty() and seen.size() > 8, "9 no key name in %d visible texts and the Easy tooltips %s" % [seen.size(), bad])

	# 10 FIT
	var win := Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size))
	var pieces := {"bar": eb.bar, "col": eb.col, "hint": eb.hint}
	var outside := []
	for k in pieces:
		var r: Rect2 = (pieces[k] as Control).get_global_rect()
		if not (pieces[k] as Control).is_visible_in_tree() or not win.encloses(r):
			outside.append("%s %s" % [k, r])
	for c in (eb.col.get_child(0) as Node).get_children():
		print("     ", c.name, (c as Control).size, (c as Control).get_combined_minimum_size())
	print("     col %s status %s %s nav %s" % [eb.col.get_global_rect(), m.ui_status.get_global_rect(), m.ui_status.text, m.ui_nav.get_global_rect()])
	ok(outside.is_empty(), "10 the bar, the column and the hint are inside the 1280 x 720 window %s" % [outside])
	var others := {"status": m.ui_status, "nav": m.ui_nav, "cube": m.ui_cube, "toast": m.ui_toast}
	var over := []
	for k in pieces:
		for j in others:
			var o: Control = others[j]
			if o != null and o.is_visible_in_tree() and (j != "status" or m.ui_status.text != "") and (pieces[k] as Control).get_global_rect().intersects(o.get_global_rect()):
				over.append("%s/%s" % [k, j])
	var pk := pieces.keys()
	for i in pk.size():
		for j in range(i + 1, pk.size()):
			if (pieces[pk[i]] as Control).get_global_rect().intersects((pieces[pk[j]] as Control).get_global_rect()):
				over.append("%s/%s" % [pk[i], pk[j]])
	ok(over.is_empty(), "10 no overlap between them, the status line, the nav strip, the cube or a toast %s" % [over])

	# 11 EXPERT
	var before := rec()
	await click_ctl(btn("easybuild_btn_switch_to_expert"))
	await idle(4)
	ok(not m.easy.on and rec() == before and not before.is_empty(), "11 Switch to Expert keeps the same building record (easy %s)" % m.easy.on)
	ok(m.cur_page == "BUILD" and m.ui_ribbon["BUILD"].is_visible_in_tree() and not eb.bar.visible and not eb.col.visible, "11 Expert's ribbon is back, Easy's bar and column are gone")
	m.easy.set_on(true, false)   # the way back to Easy for the next bar (a test's setup)
	await idle(4)

	# 12 SCENE
	ok(eb.is_active() and rec() == before, "12 back in Easy on BUILD, the same record")
	await click_ctl(eb.use_btn)
	await idle(6)
	ok(m.cur_page == "STAGE" and BuildStage.prop_index(m.S) >= 0, "12 Use in a scene: page %s, the house is a set on STAGE (prop %d)" % [m.cur_page, BuildStage.prop_index(m.S)])
	await shot("scene")

	# 13 DONE (a fresh BUILD page first)
	m._page_set("BUILD")
	await idle(4)
	await click_ctl(btn("easybuild_btn_done"))
	await idle(4)
	var asked: bool = m.ui_save_ask != null and m.ui_save_ask.visible
	ok(ss.visible or asked, "13 Done: the start screen shows (or the save question first: %s)" % asked)
	if asked:
		m.ui_save_ask.hide()

	print("EASYBUILD: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
