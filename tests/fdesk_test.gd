extends SceneTree
## FDESK (Nick 2026-10-28: free 3D building, like Fusion 360): a beginner from the REAL start screen builds an office desk
## with a drawer, by real clicks and drags at 1280 x 720, never having read a manual.
##   BUILDING card (one click) -> Easy Part (blank) -> two side panels (Draw shape on the floor, Pull it up, How far slider)
##   -> a top drawn ON the top of the left panel and pulled up, reaching over both panels (the table way)
##   -> a drawer box (its own piece, drawn on the floor in front of the desk, pulled up) -> a handle drawn on the drawer front.
const SHOT := "C:/Temp/claude/fdesk"
const DIRT := "user://fdesk_test"
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


func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


## a rectangle drawn by a real drag: corner to corner, through the points between
func drag_rect(a: Vector3, b: Vector3) -> void:
	var pa := scr(a)
	var pb := scr(b)
	var pts := []
	for i in 13:
		pts.append(pa.lerp(pb, i / 12.0))
	await drag_pts(pts)


## a slider set by a real press on its track and a drag to a fraction of its range (0 = low end, 1 = high end)
func slider_to(s: HSlider, frac: float) -> void:
	var r := s.get_global_rect()
	var y := r.get_center().y
	var x0 := r.position.x + 8.0
	var x1 := r.end.x - 8.0
	var p := Vector2(x0, y)
	await ev_move(p, false)
	await ev_mouse(p, true)
	for i in range(1, 9):
		await ev_move(Vector2(lerpf(x0, x0 + (x1 - x0) * frac, i / 8.0), y))
	await ev_mouse(Vector2(x0 + (x1 - x0) * frac, y), false)
	await idle(4)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func labels(n: Node, out: Array) -> void:
	if n is Label and (n as Label).is_visible_in_tree():
		out.append((n as Label).text)
	for c in n.get_children():
		labels(c, out)


func dump(tag: String, ep) -> void:
	for f in m.S.part["features"]:
		print("DUMP %s %s id=%s plane=%s from=%s out=%s dist=%s op=%s" % [tag, f.get("t"), f.get("id"), f.get("plane"), f.get("from"), f.get("out"), f.get("dist"), f.get("op")])
	print("DUMP %s hint=[%s] armed=%s" % [tag, String(ep.hint_l.text), str(ep.armed)])


func solid() -> Dictionary:
	return Part.replay(m.S.part)


func last_slider(ep) -> HSlider:
	return ep.rows[-1]["slider"] if not ep.rows.is_empty() else null


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
	var chooser_open: bool = m.build_choose != null and m.build_choose.open
	var note_words := String(pu.note_l.text) if pu.note_l != null else ""
	ok(m.cur_page == "BUILD" and pu.on and not chooser_open and note_words.find("Easy") >= 0,
		"F0 BUILDING card, one click: blank part on page BUILD, no chooser, words name Easy (page %s, chooser %s, words [%s])" % [m.cur_page, chooser_open, note_words])
	var plain := true
	for w in ["sketch", "plane", "browser"]:
		if note_words.to_lower().find(w) >= 0:
			plain = false
	ok(plain, "F0b the blank part's words are plain: no sketch, plane or browser on the note [%s]" % note_words)
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.35, 0.0)   # the desk's middle, the view from the front and above, far enough back for both panels (clear of the Easy panel)
	m.pitch = -30.0   # negative pitch: the camera is above the floor (positive looks up from under it)
	m.yaw = 0.0
	m.dist = 2.6
	m._cam()
	await idle(60)
	await shot("open")

	# F1 left panel: a 6 x 60 cm rectangle on the floor, pulled up to 72 cm
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_rect(Vector3(-0.58, 0.0, -0.30), Vector3(-0.52, 0.0, 0.30))
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(6)
	await slider_to(last_slider(ep), 0.2305)   # about 72 cm of the 0.2..300 cm range
	await idle(8)
	var s1 := solid()
	var bb1: AABB = s1["aabb"]
	ok(int(s1["bodies"]) == 1 and absf(bb1.end.y - 0.72) < 0.03,
		"F1 left panel: one body, top at %.1f cm (want 72)" % (bb1.end.y * 100.0))
	await shot("panels")

	# F2 right panel
	dump("F1", ep)
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	dump("F2a", ep)
	await drag_rect(Vector3(0.52, 0.0, -0.30), Vector3(0.58, 0.0, 0.30))
	dump("F2b", ep)
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(6)
	await slider_to(last_slider(ep), 0.2305)
	await idle(8)
	var s2 := solid()
	var bb2: AABB = s2["aabb"]
	var lumps2: int = ep._lumps(s2)
	ok(lumps2 == 2 and absf(bb2.end.y - 0.72) < 0.03,
		"F2 right panel: two pieces that do not touch (%d pieces), top at %.1f cm (want 72)" % [lumps2, bb2.end.y * 100.0])
	dump("F2", ep)

	# F3 the top: drawn on the top face of the left panel, reaching over both panels, pulled up 3 cm
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	m.pitch = -55.0   # looking more from above: the panels' top faces are big enough on screen to be the face the press picks
	m._cam()
	await idle(30)
	var top_y: float = bb2.end.y   # the panels' top faces (the picked face is at this height)
	await drag_rect(Vector3(-0.55, top_y, 0.26), Vector3(0.62, top_y, -0.34))
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(6)
	await slider_to(last_slider(ep), 0.009)   # about 3 cm
	await idle(8)
	var s3 := solid()
	var bb3: AABB = s3["aabb"]
	dump("F3", ep)
	var lumps3: int = ep._lumps(s3)
	ok(lumps3 == 1 and absf(bb3.end.y - 0.75) < 0.02,
		"F3 top on the panels: one solid (%d lumps, bodies %d), top at %.1f cm (want 75)" % [lumps3, int(s3["bodies"]), bb3.end.y * 100.0])
	await shot("top")

	# F4 the drawer box: its own piece, drawn on the floor in front of the desk, pulled up 15 cm
	m.target = Vector3(0.0, 0.3, 0.3)
	m._cam()
	await idle(40)
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_rect(Vector3(-0.2, 0.0, 0.40), Vector3(0.2, 0.0, 0.62))
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(6)
	await slider_to(last_slider(ep), 0.07)   # about 15 cm
	await idle(8)
	var s4 := solid()
	var bb4: AABB = s4["aabb"]
	var lumps4: int = ep._lumps(s4)
	ok(lumps4 == 2, "F4 drawer is its own piece: %d pieces that do not touch (want 2 = desk and drawer), top %.1f cm" % [lumps4, bb4.end.y * 100.0])
	await shot("drawer")

	# F5 the handle: a 10 x 2 cm bar drawn on the drawer's front face and pulled out 3 cm
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_rect(Vector3(-0.05, 0.06, 0.62), Vector3(0.05, 0.08, 0.62))
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(6)
	await slider_to(last_slider(ep), 0.009)
	await idle(8)
	var s5 := solid()
	var lumps5: int = ep._lumps(s5)
	ok(lumps5 == 2 and (s5["errors"] as Dictionary).is_empty(),
		"F5 handle joins the drawer front: %d pieces (want 2), failed steps %d" % [lumps5, (s5["errors"] as Dictionary).size()])
	await shot("handle")

	var lab := []
	labels(ep.status, lab)
	var words := " ".join(lab) + " " + String(ep.hint_l.text) + " " + String(ep.msg)
	var jargon := []
	for w in ["sketch", "extrude", "loft", "boolean", "feature", "body"]:
		if words.to_lower().find(w) >= 0:
			jargon.append(w)
	ok(jargon.is_empty(), "F6 no jargon on the words %s: [%s]" % [jargon, String(ep.msg)])
	var hint_now := String(ep.hint_l.text).to_lower()
	ok(hint_now.find("how far") >= 0 or hint_now.find("mirror") >= 0 or hint_now.find("cut") >= 0 or hint_now.find("round") >= 0,
		"F7 the words name the next step: [%s]" % String(ep.hint_l.text))
	print("fdesk: %d fail" % fails)
	quit(1 if fails > 0 else 0)
