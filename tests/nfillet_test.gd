extends SceneTree
## godot --path . --position 4000,4000 -s tests/nfillet_test.gd     (NFILLET: Easy Part's rounds and blends survive a slider move; scripts/easy_part.gd, scripts/build/part_templates.gd; needs the CAD DLL and a window)
## Real clicks and drags at 1280 x 720 only (the chaos seeds 4, 5 and the sword's Thickness drag to 0 found them).
## Bars (each one replays the part and counts its errors; FAILED on the old code, as noted):
##   1 THICK  Round the edges on a sword, the Thickness slider dragged to its least: the part replays with no error (FAILED on the old code: "f16: fillet failed")
##   2 LENGTH a round made at Blade length 63 cm, then the Blade length slider dragged to 55 cm: replays (chaos seed 2 did this; FAILED on the old code)
##   3 LAST   the How round slider (the round is the last step) dragged to its most: the round shrinks to what fits, the part replays (FAILED on the old code)
##   4 BLEND  Blend two shapes on a sword, then the Blade length slider dragged: the part replays (FAILED on the old code: "f18: an edge it rounded is not there any more", chaos seed 5)
##   5 ROUND  Round, Blend, then the Blade length slider: the part replays and the round is still in the record
const SHOT := "C:/Temp/claude/nfillet"
const DIRT := "user://nfillet_test"

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


## a real drag of the slider knob to value v
func drag_slider(s: HSlider, v: float) -> void:
	var r := s.get_global_rect()
	var y := r.get_center().y
	var gw := 24.0
	var p0 := Vector2(r.position.x + gw * 0.5 + (s.value - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw), y)
	var x1 := r.position.x + gw * 0.5 + (v - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw)
	await ev_move(p0, false)
	await ev_mouse(p0, true)
	for i in range(1, 25):
		await ev_move(Vector2(lerpf(p0.x, x1, i / 24.0), y))
	await ev_mouse(Vector2(x1, y), false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


## a fresh sword made by its template, the Easy screen on it
func fresh_sword() -> void:
	m.S.part = PartTemplates.make("sword")
	pu().upto = -1
	pu().sync()
	await idle(6)


func row_of(key: String, kind := "tpl") -> Dictionary:
	for r in ep().rows:
		if String(r["key"]) == key and String(r["kind"]) == kind:
			return r
	return {}


func errs() -> Dictionary:
	return Part.replay(m.S.part)["errors"]


func has_fillet() -> bool:
	for f in m.S.part["features"]:
		if String(f["t"]) == "fillet":
			return true
	return false


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
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	# Nick 2026-10-28 (free 3D building, #100): the BUILDING card now opens a blank Easy Part itself. Start from the
	# state the card gave before (Part off, no part), so the clicks below drive the same opening they always did
	pu().set_on(false)
	pu().m.S.part = {}
	await process_frame
	await click_ctl(pu().part_btn)
	await click_ctl(pu().easy_open_btn)
	await idle(4)
	var e = ep()

	# 1 THICK: Round the edges, then Thickness dragged to its least
	await fresh_sword()
	await click_ctl(e.make_btns["round"])
	ok(has_fillet(), "1a THICK Round the edges made a round on the sword")
	var rt: Dictionary = row_of("thickness")
	await drag_slider(rt["slider"], (rt["slider"] as HSlider).min_value)
	ok(errs().is_empty(), "1 THICK the sword with a round replays after Thickness to its least: errors %s, words \"%s\"" % [str(errs()), e.msg])

	# 2 LENGTH: Blade length 63 cm, Round the edges, then Blade length dragged down to 55 cm (chaos seed 2, step 339-342)
	await fresh_sword()
	var rl: Dictionary = row_of("blade_length")
	await drag_slider(rl["slider"], 63.0)
	await click_ctl(e.make_btns["round"])
	rl = row_of("blade_length")
	await drag_slider(rl["slider"], 55.0)
	ok(errs().is_empty(), "2 LENGTH the sword with a round replays after Blade length to its least: errors %s, words \"%s\"" % [str(errs()), e.msg])

	# 3 LAST: the round's own slider (How round) dragged to its most: the round shrinks to fit and the part replays
	await fresh_sword()
	await click_ctl(e.make_btns["round"])
	var rw: Dictionary = {}
	for r in e.rows:
		if String(r["kind"]) == "tweak":
			rw = r
	ok(not rw.is_empty(), "3a LAST the round has its own How round slider")
	if not rw.is_empty():
		await drag_slider(rw["slider"], (rw["slider"] as HSlider).max_value)
	ok(errs().is_empty(), "3 LAST the round dragged to its most still replays: errors %s, words \"%s\"" % [str(errs()), e.msg])
	await shot("shrunk_round")

	# 4 BLEND: Blend two shapes, Round the edges, then the Blade length slider (chaos seed 5: the round's edge was not found again)
	await fresh_sword()
	await click_ctl(e.make_btns["blend"])
	ok(String(e.msg).find("cannot") < 0 and Part.count_of(m.S.part, "loft") == 1, "4a BLEND the sword's two shapes blend (words \"%s\")" % e.msg)
	await click_ctl(e.make_btns["round"])
	rl = row_of("blade_length")
	await drag_slider(rl["slider"], (rl["slider"] as HSlider).min_value + 0.75 * ((rl["slider"] as HSlider).max_value - (rl["slider"] as HSlider).min_value))
	ok(errs().is_empty(), "4 BLEND a blend survives a Blade length drag: errors %s, words \"%s\"" % [str(errs()), e.msg])

	# 5 ROUND: Round, Blend, then Blade length: the round is still in the part and it replays
	await fresh_sword()
	await click_ctl(e.make_btns["round"])
	await click_ctl(e.make_btns["blend"])
	rl = row_of("blade_length")
	await drag_slider(rl["slider"], (rl["slider"] as HSlider).min_value)
	ok(errs().is_empty() and has_fillet(), "5 ROUND round + blend + Blade length: replays, the round kept: errors %s" % str(errs()))
	await shot("round_blend")

	print("nfillet: %d fail" % fails)
	quit(1 if fails > 0 else 0)
