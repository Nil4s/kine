extends SceneTree
## godot --path . --position 4000,4000 -s tests/p034yourownpic_test.gd     (P034 YOUR OWN PICTURE: Easy Part's Draw shape row gets a Picture chip: a picture file becomes a raised logo, one step; scripts/easy_part.gd _picture_press, scripts/build/picture_trace.gd; needs the CAD DLL)
## Bars (real clicks through root.push_input at 1280 x 720, from the start screen: a 3D BUILDING project, Part, Easy; the picture is a 20 x 20 px PNG written under user://):
##   1 CHIP        Draw shape shows a Picture chip; a click opens a file dialog (the walk picks the file by its own file_selected signal)
##   2 LOGO        the left half of the picture is ink (a 20 x 40 mm block): ONE undo step, a sketch + a 2 mm pull, no failed step; 2 mm high
##                 (measured from the built result: aabb and volume), volume = ink area 800 mm2 x 2 mm = 1600 mm3 within 5 pct
##   3 UNDO        Undo takes the logo back in one step (the volume goes to 0)
##   4 BLANK       an all-white picture: refused in words that name the next step, no undo step, no feature
##   5 NOT A PIC   a file that is not a picture: refused in words, no undo step, no feature
##   6 WORDS       no key name in any visible Easy text with the Draw shape row open
## Shots: C:/Temp/claude/p034yourownpic/shot_chip.png (Draw shape with the Picture chip), shot_logo.png (the logo built)
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/peasy3"
const DIRT := "user://peasy3_test"


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


## a click at a point in the view (no control under it)
func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


## a real press, a drag through every point, a release (the grid draws)
func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func dot_near(p: Vector2) -> bool:
	var ep = m.bld.part.ep
	for d in ep._dot_list():
		if (d["scr"] as Vector2).distance_to(p) <= 30.0:
			return true
	return false


## a point in the clear view at fractions (fx, fy), moved down until no amber dot or Easy panel is under it
func free_at(fx: float, fy: float) -> Vector2:
	var ep = m.bld.part.ep
	var cl: Rect2 = m.nav_clear_rect()
	var p := Vector2(cl.position.x + cl.size.x * fx, cl.position.y + cl.size.y * fy)
	for i in 40:
		if not dot_near(p) and not ep._over_ui(p):
			return p
		p += Vector2(0, 14)
	return p


## the screen point of the middle of body i (the mean of its triangle corners)
func body_at(i: int) -> Vector2:
	var faces := Part.body_faces(m.S.part, -1)
	var sum := Vector3.ZERO
	var n := 0
	for q in faces[i]:
		sum += q
		n += 1
	return m.cam.unproject_position(sum / float(maxi(n, 1)))


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func overlaps(names: Array) -> Array:
	var bad := []
	var cl: Rect2 = m.nav_clear_rect()
	var rs := []
	for c in names:
		var ctl: Control = c
		if ctl.visible:
			rs.append([ctl.name, Rect2(ctl.global_position, ctl.size)])
	for i in rs.size():
		var r: Rect2 = rs[i][1]
		if r.position.x < cl.position.x - 1.0 or r.end.x > cl.end.x + 1.0 or r.position.y < cl.position.y - 1.0 or r.end.y > cl.end.y + 1.0:
			bad.append("%s outside the clear view %s (clear %s)" % [rs[i][0], r, cl])
		for j in range(i + 1, rs.size()):
			if r.intersects(rs[j][1]):
				bad.append("%s overlaps %s" % [rs[i][0], rs[j][0]])
	return bad


func texts(n: Node, out: Array) -> void:
	if n is Control and not (n as Control).visible:
		return
	if n is Button:
		out.append((n as Button).text)
	if n is Label:
		out.append((n as Label).text)
	if n is Control:
		out.append((n as Control).tooltip_text)
	for c in n.get_children():
		texts(c, out)


func count_kind(rec: Dictionary, t: String) -> int:
	var n := 0
	for f in rec.get("features", []):
		if String(f["t"]) == t:
			n += 1
	return n


func last_of(rec: Dictionary, t: String) -> Dictionary:
	var out := {}
	for f in rec.get("features", []):
		if String(f["t"]) == t:
			out = f
	return out


## a real drag of the slider knob to value v (held with the left button, 24 mouse steps)
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


const PIC_DIR := "user://p034yourownpic_test"


## a 20 x 20 px PNG: the left half dark (ink), the right half white; blank = all white
func write_png(nm: String, blank := false) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PIC_DIR))
	var img := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	if not blank:
		for x in 10:
			for y in 20:
				img.set_pixel(x, y, Color(0, 0, 0, 1))
	var p := "%s/%s" % [PIC_DIR, nm]
	img.save_png(p)
	return ProjectSettings.globalize_path(p)


func file_dialog() -> FileDialog:
	for c in m.find_children("*", "FileDialog", true, false):
		if (c as FileDialog).visible:
			return c
	return null


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
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the picture chip cannot run")
		quit(1)
		return
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep
	m.S.part = {}
	pu.upto = -1
	pu.sync()
	# 1 CHIP
	await click_ctl(ep.make_btns["draw"])
	var pic_btn: Button = null
	for c in ep.shape_box.find_children("easypart_shape_picture", "Button", true, false):
		pic_btn = c
	ok(pic_btn != null and ep.shape_box.visible, "1 Draw shape shows a Picture chip")
	if pic_btn == null:
		print("FAIL: no Picture chip, the rest cannot run")
		quit(1)
		return
	await shot("shot_chip")
	await click_ctl(pic_btn)
	var fd := file_dialog()
	ok(fd != null, "1 a click on Picture opens a file dialog")
	if fd == null:
		print("FAIL: no file dialog, the rest cannot run")
		quit(1)
		return
	var ub0: int = m.undo.size()
	var nf0 := (m.S.part.get("features", []) as Array).size()
	# 4 BLANK first (no step may be made from it)
	fd.file_selected.emit(write_png("blank.png", true))
	await idle(4)
	ok(m.undo.size() == ub0 and (m.S.part.get("features", []) as Array).size() == nf0 and ep.hint_l.text != "",
		"4 an all-white picture: refused in words, no undo step (%d -> %d) [%s]" % [ub0, m.undo.size(), ep.hint_l.text])
	# 5 NOT A PICTURE
	await click_ctl(pic_btn)
	fd = file_dialog()
	if fd != null:
		var bad := "%s/notapic.png" % ProjectSettings.globalize_path(PIC_DIR)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PIC_DIR))
		var fa := FileAccess.open(PIC_DIR + "/notapic.png", FileAccess.WRITE)
		fa.store_string("this is not a picture")
		fa = null
		fd.file_selected.emit(bad)
	await idle(4)
	ok(m.undo.size() == ub0 and (m.S.part.get("features", []) as Array).size() == nf0,
		"5 a file that is not a picture: refused in words, no undo step, no feature (%d -> %d) [%s]" % [ub0, m.undo.size(), ep.hint_l.text])
	# 2 LOGO: the left half is ink
	await click_ctl(pic_btn)
	fd = file_dialog()
	if fd != null:
		fd.file_selected.emit(write_png("logo.png"))
	await idle(6)
	var lg: Dictionary = pu.res
	var ab: AABB = lg.get("aabb", AABB())
	var dims := [ab.size.x * 1000.0, ab.size.y * 1000.0, ab.size.z * 1000.0]
	dims.sort()
	var vol := float(lg.get("volume", 0.0)) * 1e9   # mm3
	ok(m.undo.size() == ub0 + 1 and (lg.get("errors", {}) as Dictionary).is_empty() and vol > 0.0,
		"2 the picture makes ONE step (%d -> %d), no failed step, a solid: %.1f mm3" % [ub0, m.undo.size(), vol])
	ok(absf(float(dims[0]) - 2.0) < 0.2 and absf(float(dims[1]) - 20.0) < 1.0 and absf(float(dims[2]) - 40.0) < 1.0,
		"2 the ink half is 20 x 40 mm, 2 mm high: measured %.2f x %.2f x %.2f mm" % [dims[0], dims[1], dims[2]])
	ok(absf(vol - 1600.0) < 0.05 * 1600.0,
		"2 volume = ink 800 mm2 x 2 mm = 1600 mm3 (within 5 pct): measured %.1f mm3" % vol)
	await shot("shot_logo")
	# 3 UNDO
	m._undo()
	await idle(6)
	var vol_u := float(pu.res.get("volume", 0.0)) * 1e9
	ok(vol_u < 0.5 and m.undo.size() == ub0, "3 Undo takes the logo back in one step: %.1f mm3 left" % vol_u)
	# 6 WORDS
	var words := []
	texts(ep.shape_box, words)
	var bad_w := []
	for w in words:
		var s := String(w).to_lower()
		for key in ["ctrl", "shift", "alt+", " key", "press the", "hotkey", "f1", "esc"]:
			if s.contains(key):
				bad_w.append(String(w))
	ok(bad_w.is_empty(), "6 no key name in the Draw shape row: %s" % str(bad_w))
	ok(not ep.hint_l.text.contains("Ctrl"), "6 the hint has no key name")
	print("ENDOK fails=%d" % fails)
	quit(1 if fails > 0 else 0)
