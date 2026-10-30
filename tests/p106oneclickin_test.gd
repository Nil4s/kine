extends SceneTree
## P106 ONE-CLICK INSTRUCTION SHEET (Friday plan item 106, Kine's own idea; Nick: monkey-brain easy): the Easy Part step list has an
## "Instruction sheet" button. One click writes one printable page (an HTML file: open it, print, Save as PDF): the parts list (each piece
## with its volume), then each step with its picture (the part as it stands after that step) and its plain words. Real clicks at 1280 x 720
## from the real start screen, on the live Easy Part. Every number is read off the BUILT result (Part.replay), or off the page the button wrote
## (decoded PNGs, the words), never from the code's own variables.
##   S0 the BUILDING card, Easy; Draw shape + Box chip + drag a 40 mm box + Pull it up 3 cm (2 steps with words)
##   S1 the step list has the button "Instruction sheet" (easypart_sheet): one real click on it
##   S2 the page exists in the test folder and the browser was asked for it (last_shell is that file)
##   S3 the page has one picture per step: the same count as the step list (2), each PNG 240 x 180 px, not blank (>= 5 pct of its pixels differ from the corner)
##   S4 the parts list: one row per built piece (1), and its volume on the page is within 1 pct of the built volume; the built volume is 48 cm3 (40 x 40 x 30 mm, 10 pct)
##   S5 the page's words are the step list's words in order ("Pulled up 3 cm" among them), and no jargon in the body text
##   S6 the click changed nothing in the part (the record is the same JSON before and after) and took no undo step (the undo count is the same)
## shots: C:/Temp/claude/p106oneclickin/sheet.png
const SHOT := "C:/Temp/claude/p106oneclickin"
const DIRT := "user://p106oneclickin_test"
const JARGON := ["sketch", "extrude", "fillet", "feature", "kernel", "shell", "loft", "boolean", "profile"]
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
	if c == null:
		fails += 1
		print("FAIL a control to click is missing")
		return
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


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func solid() -> Dictionary:
	return Part.replay(m.S.part, -1, {"faces": true, "props": true})


func mm(v: float) -> float:
	return v / Part.MM


func find_named(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var f := find_named(c, nm)
		if f != null:
			return f
	return null


func step_buttons() -> Array:
	var box := find_named(m, "easypart_steps")
	if box == null:
		return []
	return box.find_children("easypart_step_*", "Button", true, false)


func step_words() -> Array:
	var out := []
	for b in step_buttons():
		out.append(String((b as Button).text))
	return out


func slide_to(sl: HSlider, v: float) -> void:
	if sl == null:
		fails += 1
		print("FAIL no slider to move")
		return
	var g := float(sl.get_theme_icon("grabber").get_width()) if sl.get_theme_icon("grabber") != null else 16.0
	var frac := (v - sl.min_value) / (sl.max_value - sl.min_value)
	var lx := g * 0.5 + frac * (sl.size.x - g)
	var p := sl.get_global_rect().position + Vector2(lx, sl.size.y * 0.5)
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_move(p)
	await ev_mouse(p, false)
	await idle(12)


func last_slider() -> HSlider:
	return find_named(m, "easypart_slider_last") as HSlider


## the page's <img> sources, decoded: [Image, ...] in page order
func page_pictures(html: String) -> Array:
	var out := []
	var at := 0
	while true:
		var i := html.find("data:image/png;base64,", at)
		if i < 0:
			break
		var s := i + "data:image/png;base64,".length()
		var e := html.find("\"", s)
		var raw := Marshalls.base64_to_raw(html.substr(s, e - s))
		var img := Image.new()
		if img.load_png_from_buffer(raw) == OK:
			out.append(img)
		at = e
	return out


## the share of pixels that differ from the top-left corner (a blank picture is 0)
func ink_share(img: Image) -> float:
	var bg := img.get_pixel(0, 0)
	var n := 0
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			var c := img.get_pixel(x, y)
			if absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) > 0.05:
				n += 1
	var total := ceili(img.get_width() / 3.0) * ceili(img.get_height() / 3.0)
	return float(n) / float(total)


## the words inside <body> (tags removed), lower case
func body_text(html: String) -> String:
	var b := html.find("<body")
	var t := html.substr(b if b >= 0 else 0)
	var out := ""
	var in_tag := false
	for ch in t:
		if ch == "<":
			in_tag = true
		elif ch == ">":
			in_tag = false
			out += " "
		elif not in_tag:
			out += ch
	return out.to_lower()


## the volumes written on the page, in cm3 ("Piece N ... N cm3" rows read as numbers)
func page_piece_vols(html: String) -> Array:
	var out := []
	var at := 0
	while true:
		var i := html.find("class=\"piece\"", at)
		if i < 0:
			break
		var s := html.find(">", i) + 1
		var e := html.find(" cm", s)
		out.append(float(html.substr(s, e - s).strip_edges()))
		at = e
	return out


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
	PartSheet.dir = DIRT + "/sheets"
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

	# S0 the box: Draw shape, Box chip, drag 40 mm, Pull it up 3 cm
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_pts([scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02))])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	await slide_to(last_slider(), 3.0)

	# S1 the one button, real click
	var sheet_btn := find_named(m, "easypart_sheet") as Button
	var rec_before := JSON.stringify(m.S.part)
	var undo_before: int = m.undo.size()
	ok(sheet_btn != null and sheet_btn.visible, "S1 the Instruction sheet button is on the step list (visible %s)" % (sheet_btn != null and sheet_btn.visible))
	m.last_shell = ""
	await click_ctl(sheet_btn)
	await idle(60)
	var path := String(m.last_shell)
	var html := FileAccess.get_file_as_string(path) if path != "" else ""
	ok(path.ends_with("_sheet.html") and html.find("<html") >= 0,
		"S2 one click writes the page and asks the browser for it (%s)" % path.get_file())
	if html.is_empty():
		print("FAIL no page to read, the rest cannot be checked")
		quit(1 if fails > 0 else 0)
		return
	await shot("sheet")

	# S3 one picture per step, 240 x 180, not blank
	var steps := step_words()
	var pics := page_pictures(html)
	var sized := true
	var inked := true
	for img in pics:
		sized = sized and img.get_width() == 240 and img.get_height() == 180
		inked = inked and ink_share(img) >= 0.05
	ok(pics.size() == steps.size() and steps.size() == 2 and sized and inked,
		"S3 %d pictures for %d steps, each 240 x 180 px and drawn (sized %s, inked %s)" % [pics.size(), steps.size(), sized, inked])

	# S4 the parts list: one row per built piece, volume within 1 pct of the built volume, 48 cm3 for 40 x 40 x 30 mm
	var s := solid()
	var bb: AABB = s["aabb"]
	var built_cm3: Array = []
	for v in s.get("volumes", []):
		built_cm3.append(float(v) * 1.0e6)
	var vols := page_piece_vols(html)
	var rows_ok := vols.size() == built_cm3.size() and vols.size() == 1
	var vol_ok := rows_ok and absf(float(vols[0]) - float(built_cm3[0])) <= 0.01 * float(built_cm3[0])
	var want := (mm(bb.size.x) * mm(bb.size.z) * mm(bb.size.y)) / 1000.0
	ok(rows_ok and vol_ok and absf(built_cm3[0] - 48.0) <= 0.1 * 48.0,
		"S4 parts list: %d row(s) for %d piece(s), page %s cm3 vs built %s cm3, box %.1f cm3 (48 want)" % [vols.size(), built_cm3.size(), str(vols), str(built_cm3), want])

	# S5 the words, in order, and no jargon in the body
	var text := body_text(html)
	var in_order := true
	var at := 0
	for w in steps:
		var k := text.find(String(w).to_lower(), at)
		if k < 0:
			in_order = false
			break
		at = k
	var jargon := []
	for j in JARGON:
		if text.find(j) >= 0:
			jargon.append(j)
	ok(in_order and text.find("pulled up 3 cm") >= 0 and jargon.is_empty(),
		"S5 the step words are on the page in order, Pulled up 3 cm among them, no jargon (found %s)" % str(jargon))

	# S6 nothing changed in the part, no undo step
	var undo_after: int = m.undo.size()
	ok(JSON.stringify(m.S.part) == rec_before and undo_after == undo_before,
		"S6 the click changed no part and took no undo step (undo %d -> %d)" % [undo_before, undo_after])

	print("p106oneclickin: %d fail(s)" % fails)
	quit(1 if fails > 0 else 0)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])
