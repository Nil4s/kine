extends SceneTree
## FNAMECHANGE (Nick 2026-10-28: "rename the part from Part 1 to your own name by clicking its title; plain words"). A beginner
## from the start screen by real clicks at 1280x720: the BUILDING card (Easy, blank part, named Part N), a click on the title
## opens a name box, type a name, Enter. Bars:
##   0 the BUILDING card, one click: page BUILD, Easy Part on
##   1 the title shows the default name "Part N" (MyParts.free_name)
##   2 a real click on the title opens a name box (easypart_name) that holds the name and has the focus
##   3 typing "Bracket" and Enter: the record's name is "Bracket", the title says "Part: Bracket", the box is closed
##   4 Undo takes the name back to "Part N"; Redo puts "Bracket" back
##   5 Draw shape, drag, Pull it up, then Use in a scene: My parts has a record named "Bracket" on disk
##   6 the title's words are plain: no "part name" jargon, the tooltip says Click to rename
## shots: C:/Temp/claude/fnamechange/*.png
const SHOT := "C:/Temp/claude/fnamechange"
const DIRT := "user://fnamechange_test"

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


func key(code: int, ch := "") -> void:
	var e := InputEventKey.new()
	e.keycode = code as Key
	e.physical_keycode = code as Key
	e.key_label = code as Key
	e.unicode = ch.unicode_at(0) if ch != "" else 0
	e.pressed = true
	root.push_input(e, true)
	await process_frame
	e = e.duplicate()
	e.pressed = false
	root.push_input(e, true)
	await idle(2)


func type_text(s: String) -> void:
	for ch in s:
		await key(ch.to_upper().unicode_at(0), ch)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


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
	MyParts.dir = DIRT + "/parts"   # its own My parts folder: other suites clear theirs
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MyParts.dir))
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return

	# 0 the BUILDING card, one click
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	await idle(20)
	ok(m.cur_page == "BUILD" and m.S.kind == "building" and pu().on and pu().easy,
		"0 BUILDING card, one click -> Easy Part on (page %s)" % m.cur_page)

	# 1 the default name: Part N
	var ep = pu().ep
	var nm0 := String(m.S.part.get("name", ""))
	var rx := RegEx.new()
	rx.compile("^Part \\d+$")
	ok(rx.search(nm0) != null and ep.title_l.text == "Part: " + nm0,
		"1 the title shows the default name (record '%s', title '%s')" % [nm0, ep.title_l.text])
	await shot("01_title")

	# 2 a real click on the title opens the name box
	await click_ctl(ep.title_l)
	await idle(4)
	var box = m.find_child("easypart_name", true, false)
	var box_ok: bool = box != null and box is LineEdit and (box as LineEdit).is_visible_in_tree()
	ok(box_ok and (box as LineEdit).text == nm0 and (box as LineEdit).has_focus(),
		"2 a click on the title opens a name box with the name in it and the focus (box %s)" % (String((box as LineEdit).text) if box_ok else "none"))
	await shot("02_box")

	# 3 type Bracket, Enter
	if box_ok:
		(box as LineEdit).select_all()
	await type_text("Bracket")
	await key(KEY_ENTER)
	await idle(6)
	await shot("03_renamed")
	var box_gone: bool = m.find_child("easypart_name", true, false) == null or not (m.find_child("easypart_name", true, false) as Control).is_visible_in_tree()
	ok(String(m.S.part.get("name", "")) == "Bracket" and ep.title_l.text == "Part: Bracket" and box_gone,
		"3 Bracket + Enter: record '%s', title '%s', box closed %s" % [m.S.part.get("name", ""), ep.title_l.text, box_gone])

	# 4 Undo takes the name back, Redo puts it back
	await click_ctl(ep.undo_btn)
	var back := String(m.S.part.get("name", ""))
	await click_ctl(ep.redo_btn)
	var again := String(m.S.part.get("name", ""))
	ok(rx.search(back) != null and again == "Bracket", "4 Undo gives '%s' back, Redo gives '%s' back" % [back, again])

	# 5 draw, pull, Use in a scene: My parts has it under the name
	await click_ctl(ep.make_btns["draw"])
	await drag_screen(Vector2(830, 560), Vector2(950, 610))
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	await click_ctl(ep.use_scene_btn)
	await idle(10)
	var saved := MyParts.read(MyParts.path_of("Bracket"))
	ok(String(saved.get("name", "")) == "Bracket" and MyParts.exists("Bracket"),
		"5 My parts has the part named Bracket (file name '%s')" % String(saved.get("name", "")))
	await shot("05_used")

	# 6 plain words
	var tip: String = ep.title_l.tooltip_text
	ok(tip.find("Click") >= 0 and tip.to_lower().find("rename") >= 0 and tip.to_lower().find("jargon") < 0,
		"6 the title's tooltip says Click to rename (%s)" % tip)

	print("fnamechange: %d fail" % fails)
	quit(1 if fails > 0 else 0)
