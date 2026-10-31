extends SceneTree
## godot --path . --position 4000,4000 -s tests/p201physicalto_test.gd     (P201 PHYSICAL TO DIGITAL, Friday plan 201: Easy Part's Photo size chip (Draw shape row): a photo of a real object with a coin beside it;
##  six clicks (the coin's two edges, the object's width edges, its height edges) turn the pixels into mm and make a plate of that size in the part.
##  scripts/easy_part_photo.gd; the chip and the open call are in scripts/easy_part.gd)
## Bars (real clicks through root.push_input at 1280 x 720, from the BUILDING card: a blank Easy Part. The file dialog is answered by its own
## file_selected signal, every other step is a click on the screen. Sizes are measured from the built result (pu.res aabb), never from the code):
##   1 CHIP     Draw shape armed: the Photo size chip shows; a click opens the file dialog
##   2 PANEL    the picked photo opens the measuring panel: the prompt says "1 of 6" and Make the part is off
##   3 EARLY    with four clicks in, Make the part is still off, and the part is still empty (no undo step)
##   4 SIX      the other two clicks: the prompt says all six are in and Make the part turns on
##   5 MAKE     Euro 2 coin (the default): ONE solid, sorted sizes 10 / 50 / 80 mm within 1 mm (mm from the picture's pixels), one undo step, the panel closes
##   6 UNDO     Undo takes the plate back: no step left in the part
##   7 COIN     the US quarter chip, a second photo: sorted sizes 10 / 47.1 / 75.4 mm within 1 mm (the coin changes the scale), one solid
## Shots: C:/Temp/claude/p201physicalto/ (the six marks, the made plate). Only user:// is written (the test picture) and the shots.
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/p201physicalto"
const DIRT := "user://p201physicalto_test"
const IMG := Vector2(800, 500)
## the picture's edges in its own pixels: the coin is a disc of 154.5 px across (25.75 mm at 6 px per mm), the object a dark box 480 x 300 px (80 x 50 mm)
const COIN_A := Vector2(22.75, 100.0)
const COIN_B := Vector2(177.25, 100.0)
const OBJ_L := Vector2(250.0, 300.0)
const OBJ_R := Vector2(730.0, 300.0)
const OBJ_T := Vector2(490.0, 150.0)
const OBJ_B := Vector2(490.0, 450.0)


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
	await idle(2)


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


## the test picture: white, a grey disc (the coin) on the left, a dark box (the object) on the right, saved as a PNG the way a phone photo is
func make_photo() -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	var im := Image.create(int(IMG.x), int(IMG.y), false, Image.FORMAT_RGB8)
	im.fill(Color.WHITE)
	for y in int(IMG.y):
		for x in int(IMG.x):
			var q := Vector2(x + 0.5, y + 0.5)
			if q.distance_to(Vector2(100.0, 100.0)) <= 77.25:
				im.set_pixel(x, y, Color(0.6, 0.6, 0.6))
			if x >= 250 and x < 730 and y >= 150 and y < 450:
				im.set_pixel(x, y, Color(0.2, 0.2, 0.2))
	var p := ProjectSettings.globalize_path(DIRT + "/measure.png")
	im.save_png(p)
	return p


## a picture pixel -> a screen point, for the picture's shown rect (KEEP_ASPECT_CENTERED: one scale, centred)
func img_to_screen(q: Vector2) -> Vector2:
	var pic: Control = root.find_child("easypart_photo_pic", true, false)
	var r := pic.get_global_rect()
	var s := minf(r.size.x / IMG.x, r.size.y / IMG.y)
	return r.position + (r.size - IMG * s) * 0.5 + q * s


func btn(nm: String) -> Button:
	return root.find_child(nm, true, false) as Button


func prompt_text() -> String:
	var l: Label = root.find_child("easypart_photo_prompt", true, false)
	return l.text if l != null else ""


## the part's sizes from the built result: the solid's bounding box, sorted small to large (mm)
func built_sizes(pu) -> Array:
	var bb: AABB = pu.res.get("aabb", AABB())
	var s := [bb.size.x * 1000.0, bb.size.y * 1000.0, bb.size.z * 1000.0]
	s.sort()
	return s


func sizes_ok(got: Array, want: Array) -> bool:
	for i in 3:
		if absf(float(got[i]) - float(want[i])) > 1.0:
			return false
	return true


## the Draw shape row's Photo size chip, then the file dialog's pick (the dialog's own signal), then the panel is open
func open_photo(path: String) -> void:
	var chip := btn("easypart_shape_photo")
	if chip == null or not chip.is_visible_in_tree():   # Draw shape is not armed (the chip shows only under it): arm it
		await click_ctl(m.bld.part.ep.make_btns["draw"])
	print("P201 diag open_photo: chip visible %s, draw pressed %s, armed '%s'" % [str(btn("easypart_shape_photo") != null and btn("easypart_shape_photo").is_visible_in_tree()), str(m.bld.part.ep.make_btns["draw"].button_pressed), str(m.bld.part.ep.armed)])
	await click_ctl(btn("easypart_shape_photo"))
	var dlg: FileDialog = root.find_child("easypart_photo_dialog", true, false)
	print("P201 diag open_photo: dialog %s" % str(dlg != null))
	if dlg != null:
		dlg.file_selected.emit(path)
	await idle(4)


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
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the photo size cannot run")
		quit(1)
		return
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep
	var path := make_photo()

	# 1 CHIP: Draw shape armed, the Photo size chip shows; the chip opens the file dialog
	await click_ctl(ep.make_btns["draw"])
	var chip := btn("easypart_shape_photo")
	ok(chip != null and chip.is_visible_in_tree(), "1 Draw shape armed: the Photo size chip shows in the shape row")
	await click_ctl(chip)
	ok(root.find_child("easypart_photo_dialog", true, false) != null, "1 a press on Photo size opens the file dialog [%s]" % ep.msg)
	var dlg: FileDialog = root.find_child("easypart_photo_dialog", true, false)
	if dlg != null:
		dlg.file_selected.emit(path)
	await idle(4)

	# 2 PANEL: the picture opens the measuring panel at "1 of 6", Make off
	var panel: Control = root.find_child("easypart_photo", true, false)
	ok(panel != null and panel.is_visible_in_tree() and prompt_text().begins_with("1 of 6"), "2 the photo opens the measuring panel at 1 of 6 [%s]" % prompt_text())
	ok(btn("easypart_photo_make") != null and btn("easypart_photo_make").disabled, "2 Make the part is off before six clicks")
	await shot("panel_open")

	# the clicks: the coin's two edges, the object's width edges, its height edges
	var n_part0: int = (m.S.part.get("features", []) as Array).size() if not m.S.part.is_empty() else 0
	var ub0: int = m.undo.size()
	await click_at(img_to_screen(COIN_A))
	await click_at(img_to_screen(COIN_B))
	await click_at(img_to_screen(OBJ_L))
	await click_at(img_to_screen(OBJ_R))

	# 3 EARLY: four clicks in, Make still off, nothing built, no undo step
	var n_part1: int = (m.S.part.get("features", []) as Array).size() if not m.S.part.is_empty() else 0
	ok(btn("easypart_photo_make").disabled and n_part1 == n_part0 and m.undo.size() == ub0, "3 four clicks in: Make the part is still off, the part is unchanged, no undo step [%s]" % prompt_text())

	await click_at(img_to_screen(OBJ_T))
	await click_at(img_to_screen(OBJ_B))

	# 4 SIX: all six in, Make on
	ok(prompt_text().contains("All six") and not btn("easypart_photo_make").disabled, "4 six clicks in: the prompt says all six are in, Make the part is on [%s]" % prompt_text())
	await shot("six_marks")

	# 5 MAKE: one solid, sizes measured from the built result
	await click_ctl(btn("easypart_photo_make"))
	await idle(4)
	var bodies: int = int(pu.res.get("bodies", 0))
	var got := built_sizes(pu)
	ok(bodies == 1 and sizes_ok(got, [10.0, 50.0, 80.0]), "5 Make: one solid, sizes 10 / 50 / 80 mm within 1 mm (bodies %d, built %s) [%s]" % [bodies, str(got), ep.msg])
	ok(m.undo.size() == ub0 + 1 and not panel.visible, "5 Make is one undo step and the panel closes (undo %d -> %d)" % [ub0, m.undo.size()])
	await shot("made")

	# 6 UNDO: the plate goes back
	await click_ctl(ep.undo_btn)
	await idle(4)
	var left := (m.S.part.get("features", []) as Array).size() if not m.S.part.is_empty() else 0
	ok(left == 0, "6 Undo takes the plate back: no step left in the part (steps %d)" % left)

	# 7 COIN: the US quarter chip, a second photo: the same six clicks give a smaller object
	await open_photo(path)
	var qc := btn("easypart_photo_coin_quarter")
	await ev_move(qc.get_global_rect().get_center(), false)
	print("P201 diag coin: quarter rect %s, hovered %s, panel rect %s, viewport %s" % [str(qc.get_global_rect()), str(root.gui_get_hovered_control()), str(root.find_child("easypart_photo", true, false).get_global_rect()), str(root.get_visible_rect())])
	await shot("pass7_before_coin")
	await click_ctl(qc)
	if not qc.button_pressed:   # the first button press after the photo dialog closes is lost (probe 10-31: the next press lands); press once more
		print("P201 note: the first coin press after the dialog did not land, pressing again")
		await click_ctl(qc)
	print("P201 diag coin: after click pressed %s, prompt '%s'" % [str(qc.button_pressed), prompt_text()])
	await click_at(img_to_screen(COIN_A))
	await click_at(img_to_screen(COIN_B))
	await click_at(img_to_screen(OBJ_L))
	await click_at(img_to_screen(OBJ_R))
	await click_at(img_to_screen(OBJ_T))
	await click_at(img_to_screen(OBJ_B))
	print("P201 diag pass 7: prompt '%s', make disabled %s, panel visible %s, coin chip pressed %s" % [prompt_text(), str(btn("easypart_photo_make").disabled), str(root.find_child("easypart_photo", true, false).is_visible_in_tree()), str(btn("easypart_photo_coin_quarter").button_pressed)])
	await click_ctl(btn("easypart_photo_make"))
	await idle(4)
	var got2 := built_sizes(pu)
	ok(int(pu.res.get("bodies", 0)) == 1 and sizes_ok(got2, [10.0, 47.1, 75.4]), "7 US quarter: one solid, sizes 10 / 47.1 / 75.4 mm within 1 mm (built %s) [%s]" % [str(got2), ep.msg])

	print("P201PHYSICALTO fails=%d" % fails)
	quit(1 if fails > 0 else 0)
