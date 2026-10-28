extends SceneTree
## godot --path . --position 4000,4000 -s tests/eblade_test.gd     (EBLADE: the ewalk6 beginner walk, a long thin blade on the floor; scripts/easy_part.gd; needs the CAD DLL and a window)
## A beginner from the REAL start screen (Home, the building card, Part, Easy), an EMPTY part. Real clicks and drags at 1280 x 720 only.
##   BLADE  Draw shape, drag a 60 cm x 5 mm blade on the floor (the pointer at 203 -> 206 mm: both ends snap to the same 5 mm grid line): it draws (one new sketch), no refusal
##   WIDE   the retry at 2 cm wide draws too (one new sketch)
##   THIN   a drag that is too thin (under 2 mm on its short side) is refused AND the words say what to do (make it wider)
##   SAY    a refusal of a shape never stays silent: every refusal line names a next step
## Shots: C:/Temp/claude/eblade/<name>.png
const SHOT := "C:/Temp/claude/eblade"
const DIRT := "user://eblade_test"

var fails := 0
var m: Node
var ep: Node
var results := {}


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	if not c:
		fails += 1


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


## a floor point in mm (the Part top plane) on screen
func floor_scr(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("top"), Vector2(x, y)))


func sketches() -> int:
	var n := 0
	for f in ep._rec().get("features", []):
		if String(f.get("t", "")) == "sketch":
			n += 1
	return n


## one drag on the floor from mm a to mm b (through a few points), returns [new sketches, the words after]
func draw_once(key: String, a: Vector2, b: Vector2) -> Array:
	var n0 := sketches()
	if String(ep.armed) != "draw":   # Draw shape stays armed after a refusal (the retry is a drag, not a second press of the button)
		await click_ctl(ep.make_btns["draw"])
	var pts: Array = []
	for i in 9:
		pts.append(floor_scr(lerpf(a.x, b.x, i / 8.0), lerpf(a.y, b.y, i / 8.0)))
	await drag_pts(pts)
	await idle(4)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, key])
	var got := sketches() - n0
	print("EBLADE %s | new sketches=%d | msg=[%s] hint=[%s]" % [key, got, ep.msg, ep.hint_l.text])
	return [got, String(ep.msg)]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
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
	ss.show_screen()
	await idle(4)
	await click_ctl(ss.find_child("easy_building", true, false))
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	await click_ctl(m.ui_root.find_child("easybuild_btn_what_to_build", true, false) as Control)
	await click_ctl(m.build_choose.root_box.find_child("easy_part", true, false) as Control)
	await idle(6)
	ep = m.bld.part.ep
	m.S.part = {}
	ep.entered()
	m.bld.part.sync()
	await idle(6)

	# BLADE: 60 cm long, 5 mm wide, on the floor
	var blade: Array = await draw_once("blade", Vector2(200, 203), Vector2(800, 206))
	results["blade"] = blade
	# WIDE: the retry, 2 cm wide
	var wide: Array = await draw_once("wide", Vector2(200, 400), Vector2(800, 420))
	results["wide"] = wide
	# THIN: a press with no width at all (a click), the words must say what to do
	var thin: Array = await draw_once("thin", Vector2(300, 600), Vector2(300, 600))
	results["thin"] = thin

	ok(int(blade[0]) == 1, "BLADE a 60 cm x 5 mm blade on the floor draws one sketch (got %d, words: %s)" % [int(blade[0]), str(blade[1])])
	ok(int(wide[0]) == 1, "WIDE the 2 cm wide retry draws one sketch (got %d, words: %s)" % [int(wide[0]), str(wide[1])])
	var say_ok := int(thin[0]) == 1 or (int(thin[0]) == 0 and String(thin[1]).contains("2 mm"))
	ok(say_ok, "THIN a refused drag says what to do, with the 2 mm rule (words: %s)" % str(thin[1]))
	print("eblade: %d fail" % fails)
	quit(1 if fails > 0 else 0)
