extends SceneTree
## godot --path . --position 4000,4000 -s tests/deadcode_test.gd     (DEADCODE: removing functions nothing calls from scripts/easy_part.gd; this checks Easy Part still works; needs the CAD DLL)
## Bars (from the start screen, a 3D BUILDING project, Part, Easy; mouse only; 1280 x 720):
##   1 OPEN    Easy Part opens by real clicks from the start screen
##   2 MAKE    the first template chip, pressed with a real click, makes a part (volume above 0) and takes ONE undo step
##   3 UNDO    Undo gives back the part as it was before the press
##   4 REDO    Redo gives back the part as it was after the press
## Shots: C:/Temp/claude/deadcode/shot_end.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/deadcode"
const DIRT := "user://deadcode_test"


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
	await idle(2)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func rec() -> Dictionary:
	return m.S.part


func vol() -> float:
	return float(m.bld.part.res.get("volume", 0.0))


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


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
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("FAIL: no KineCAD DLL, Easy Part cannot run")
		quit(1)
		return
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep
	ok(ep.active(), "1 OPEN: Easy Part is open from the start screen by clicks")
	var pre_n: int = m.undo.size()
	var pre := JSON.stringify(rec())
	# the template on the grid at the start changes nothing when pressed, so take the first other one
	var first_t: String = ""
	for t in PartTemplates.ORDER:
		if t != ep._tpl() and first_t == "":
			first_t = t
	await click_ctl(ep.chips[first_t])
	var dn: int = m.undo.size() - pre_n
	await idle(3)
	var post := JSON.stringify(rec())
	var v := vol()
	ok(v > 0.0 and dn == 1, "2 MAKE: chip %s makes a part (volume %.6f) as ONE undo step (%d -> %d)" % [first_t, v, pre_n, m.undo.size()])
	await shot("shot_made")
	m._undo()
	await idle(3)
	ok(post != pre and JSON.stringify(rec()) == pre, "3 UNDO: undo gives back the part as it was before the press")
	m._redo()
	await idle(3)
	ok(JSON.stringify(rec()) == post, "4 REDO: redo gives back the part as it was after the press")
	await shot("shot_end")
	print("RESULT deadcode fails=%d" % fails)
	quit(1 if fails > 0 else 0)
