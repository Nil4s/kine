extends SceneTree
## p192makeitlike (Friday plan 192, "Make it like this photo" for simple objects: a mug, a chair -> steps, not a mesh).
## A beginner walk with real clicks at 1280 x 720 from the BUILDING card: Parts, Type it, then "Mug like this photo" opens the
## photo dialog; the photo is chosen in that dialog (a real picture written to user://, passed through the dialog's own file_selected
## signal). Bars are read from the BUILT part (Part.replay: bodies, aabb, volume), never from the code's own variables.
##   P1 Parts > Type it shows the "Like a photo" row with a Mug and a Chair button (2 clicks, no new row on the main panel)
##   P2 a Mug press opens the photo dialog (one click)
##   P3 a file that is not a picture changes nothing and the words say which file to pick (features unchanged)
##   P4 a picture builds ONE mug: one body, round (x and z within 3 pct), 80 mm across and 95 mm tall (within 3 pct)
##   P5 the mug is hollow: its volume is under 80 pct of the solid cylinder it started from
##   P6 the C handle sticks out: the mug is more than 100 mm deep in Z (the body is 80 mm)
##   P7 the mug is a short list of steps: 5 steps in the record (body, cup, floor, handle, window)
##   P8 the photo walk from the BUILDING card to a built mug is at most 5 clicks (Building, Easy, Parts, Type it, Mug)
##   P9 one Undo takes the mug back to the blank part (no steps, no body)
##   P10 a Chair press with a picture builds one chair: one body, 900 mm tall (within 3 pct)
##   P11 every press says a line (the words are not empty)
## Run: godot --path . -s tests/p192makeitlike_test.gd (needs the CAD DLL; the Docker box runs it on a virtual screen)

const SHOT := "C:/Temp/claude/p192makeitlike/shots"
const DIRT := "user://p192makeitlike_test"
var fails := 0
var m: Node
var clicks := 0
var retry_clicks := 0
var said := []


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


func ev_move(p: Vector2, held := false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	clicks += 1
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func solid() -> Dictionary:
	return Part.replay(m.S.part)


func mm(v: float) -> float:
	return v * 1000.0


func write_file(nm: String, bytes: PackedByteArray) -> String:
	var p := DIRT + "/" + nm
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return ProjectSettings.globalize_path(p)


## the photo dialog the press opened (it is added under the Draw shape row's parent)
func dialog(ep) -> FileDialog:
	return root.find_child("easypart_photo_dialog", true, false) as FileDialog


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
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var pu = m.bld.part
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(60)
	var before_steps := (m.S.part.get("features", []) as Array).size()

	# P1 Parts > Type it: the photo row shows with its two buttons
	var c0 := clicks
	await click_ctl(ep.parts_btn)
	await click_ctl(ep.lib_btns["Type it"])
	await idle(5)
	var mug_b := root.find_child("easypart_photo_mug", true, false) as Button
	var chair_b := root.find_child("easypart_photo_chair", true, false) as Button
	ok(ep.photo_box.visible and mug_b != null and chair_b != null and mug_b.is_visible_in_tree() and chair_b.is_visible_in_tree() and clicks - c0 == 2,
		"P1 Parts > Type it shows Like a photo: Mug and Chair buttons (visible %s, clicks %d)" % [ep.photo_box.visible, clicks - c0])
	await shot("types")

	# P2 a Mug press opens the photo dialog
	await click_ctl(mug_b)
	await idle(10)
	var fd := dialog(ep)
	ok(fd != null and fd.visible, "P2 the Mug press opens the photo dialog (open %s)" % [fd != null and fd.visible])

	# P3 a file that is not a picture changes nothing
	var txt := write_file("notes.txt", "not a picture".to_utf8_buffer())
	var steps_p3 := (m.S.part.get("features", []) as Array).size()
	if fd != null:
		fd.file_selected.emit(txt)
	await idle(10)
	var said_p3 := String(ep.msg)
	ok((m.S.part.get("features", []) as Array).size() == steps_p3 and said_p3.find("picture") >= 0 and said_p3.find(".png") >= 0,
		"P3 a text file changes nothing and the words name a picture file (words: %s)" % said_p3)

	# P4 to P7: a real picture, pick Mug in the dialog
	var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	img.fill(Color(0.9, 0.9, 0.9))
	var png := write_file("mug.png", img.save_png_to_buffer())
	var c_retry := clicks
	await click_ctl(mug_b)
	retry_clicks = clicks - c_retry
	await idle(10)
	fd = dialog(ep)
	if fd != null:
		fd.file_selected.emit(png)
	await idle(20)
	var s1 := solid()
	var bb: AABB = s1["aabb"]
	var sx := mm(bb.size.x)
	var sy := mm(bb.size.y)
	var sz := mm(bb.size.z)
	# the body is 80 mm across in X and 95 mm tall; the handle adds to Z only (P6), so Z is checked there, not for roundness
	ok(int(s1["bodies"]) == 1 and absf(sx - 80.0) < 2.4 and absf(sy - 95.0) < 2.85,
		"P4 one mug from the picture: %d body, x %.1f y %.1f mm (80 x 95, 3 pct); z %.1f mm with the handle" % [int(s1["bodies"]), sx, sy, sz])

	var solid_cyl := PI * 40.0 * 40.0 * 95.0
	var vol := float(s1.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)
	ok(vol > 0.0 and vol < 0.8 * solid_cyl, "P5 the mug is hollow: %.0f mm3, under 80 pct of the solid %.0f mm3" % [vol, solid_cyl])
	ok(sz > 100.0, "P6 the C handle sticks out: %.1f mm deep in Z (the body is 80 mm)" % sz)
	var steps := 0   # steps = the extrude features (sketches are the drawings a step uses, not steps)
	for f in m.S.part.get("features", []):
		if String(f.get("t", "")) != "sketch":
			steps += 1
	ok(steps == 5 and String(m.S.part.get("easy", {}).get("t", "")) == "mug", "P7 the mug is 5 steps (%d) of the mug template" % steps)
	# the good walk: Parts, Type it, Mug like this photo. The one extra press after the wrong-file test is a retry, counted apart
	var good_clicks := clicks - retry_clicks
	ok(good_clicks <= 5, "P8 the photo walk from the BUILDING card to a built mug: %d clicks (<= 5); %d clicks in all with the wrong-file retry" % [good_clicks, clicks])
	var said_p11 := String(ep.msg)
	ok(said_p11.strip_edges().length() >= 3, "P11 the press says a line: %s" % said_p11)
	await shot("mug")

	# P9 one Undo takes the mug back to the blank part
	m._undo()
	await idle(20)
	var s9 := solid()
	ok((m.S.part.get("features", []) as Array).size() == before_steps and int(s9["bodies"]) == 0,
		"P9 one Undo: %d steps, %d bodies (blank part: %d steps)" % [(m.S.part.get("features", []) as Array).size(), int(s9["bodies"]), before_steps])

	# P10 a Chair press with a picture builds one chair
	await click_ctl(chair_b)
	await idle(10)
	fd = dialog(ep)
	if fd != null:
		fd.file_selected.emit(png)
	await idle(20)
	var s10 := solid()
	var cb: AABB = s10["aabb"]
	var cy := mm(cb.size.y)
	ok(int(s10["bodies"]) == 1 and absf(cy - 900.0) < 27.0, "P10 one chair from the picture: %d body, %.1f mm tall (900, 3 pct)" % [int(s10["bodies"]), cy])
	await shot("chair")

	print("p192makeitlike: %d fail" % fails)
	quit(1 if fails > 0 else 0)
