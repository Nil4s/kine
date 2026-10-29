extends SceneTree
## FMEASURE (Nick 2026-10-28: "free 3D building, like Fusion 360"; a beginner wants to know how big the part is): from the REAL start
## screen at 1280 x 720, a beginner builds a box with real clicks and drags (Draw shape, Pull it up) and reads its size on screen with
## no Expert: a plain label "Size: W x D x H cm (wide x deep x high)" under the part's front bottom edge.
## Bars (run on the old code before the change; see the report):
##   G0 the BUILDING card, one click: page BUILD, a blank part, Easy on
##   G1 after Pull it up: the size label is up and shows "Size: W x D x H cm" (a real solid)
##   G2 the numbers are the part's box in cm (match the replayed aabb to 0.1 cm)
##   G3 the box is the drawn size: wide ~18 cm, deep ~6 cm, high ~2 cm (within 1.5 cm)
##   G4 the label sits under the part (its top is below the part's front bottom point) and on the 1280 x 720 screen
##   G5 the words are plain: no sketch, extrude, fillet, boolean, feature, body, loft
##   G6 Undo of the pull: no solid, the size label is hidden
## shots: C:/Temp/claude/fmeasure/open.png, size.png, undo.png
const SHOT := "C:/Temp/claude/fmeasure"
const DIRT := "user://fmeasure_test"
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


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func solid() -> Dictionary:
	return Part.replay(m.S.part)


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
	ok(m.cur_page == "BUILD" and pu.on and not chooser_open,
		"G0 BUILDING card, one click -> a blank part on page BUILD, no chooser (page %s, chooser %s)" % [m.cur_page, chooser_open])
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 35.0
	m.yaw = 30.0
	m._cam()
	await idle(60)
	await shot("open")

	# a box on the grid (18 cm x 6 cm), then Pull it up
	await click_ctl(ep.make_btns["draw"])
	await drag_pts([scr(Vector3(-0.09, 0.0, -0.03)), scr(Vector3(0.09, 0.0, 0.03))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(20)
	var s1 := solid()
	var bb: AABB = s1["aabb"]
	var lab: Label = root.find_child("easypart_size", true, false) as Label
	var txt := lab.text if lab != null else ""
	var rx := RegEx.new()
	rx.compile("^Size: ([0-9.]+) x ([0-9.]+) x ([0-9.]+) cm")
	var mt := rx.search(txt)
	var shown := lab != null and lab.is_visible_in_tree() and mt != null
	ok(shown and int(s1["bodies"]) == 1, "G1 the size label is up after Pull it up: [%s]" % txt)
	await shot("size")

	var w := mt.get_string(1).to_float() if mt != null else -1.0
	var d := mt.get_string(2).to_float() if mt != null else -1.0
	var h := mt.get_string(3).to_float() if mt != null else -1.0
	var aw := bb.size.x * 100.0
	var ad := bb.size.z * 100.0
	var ah := bb.size.y * 100.0
	ok(mt != null and absf(w - aw) <= 0.1 and absf(d - ad) <= 0.1 and absf(h - ah) <= 0.1,
		"G2 the label numbers are the box in cm: shown %.1f x %.1f x %.1f, box %.2f x %.2f x %.2f" % [w, d, h, aw, ad, ah])
	ok(mt != null and absf(w - 18.0) <= 1.5 and absf(d - 6.0) <= 1.5 and absf(h - 2.0) <= 1.5,
		"G3 the box is the drawn size: %.1f x %.1f x %.1f cm (want 18 x 6 x 2)" % [w, d, h])

	var front := Vector3(bb.get_center().x, bb.position.y, bb.end.z)
	var fp := scr(front)
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var under := lab != null and lab.position.y >= fp.y and absf(lab.get_global_rect().get_center().x - fp.x) < 200.0
	ok(under and vp.encloses(lab.get_global_rect()) if lab != null else false,
		"G4 the label sits under the part's front edge (label top %.0f, front %.0f) and on screen %s" % [lab.position.y if lab != null else -1.0, fp.y, str(lab.get_global_rect()) if lab != null else ""])
	var jargon := []
	for jw in ["sketch", "extrude", "fillet", "boolean", "feature", "body", "loft"]:
		if txt.to_lower().find(jw) >= 0:
			jargon.append(jw)
	ok(jargon.is_empty(), "G5 the size words are plain %s: [%s]" % [jargon, txt])

	await click_ctl(ep.undo_btn)
	await idle(20)
	var gone := lab != null and not lab.visible
	ok(gone and int(solid()["bodies"]) == 0, "G6 Undo of the pull: no solid, the size label is hidden")
	await shot("undo")
	print("fmeasure: %d fail" % fails)
	quit(1 if fails > 0 else 0)
