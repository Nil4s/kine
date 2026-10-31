extends SceneTree
## p059printtimee (Friday plan 59): "Print time estimate for 3D printing (volume ÷ typical rate)". From the REAL start screen at
## 1280 x 720, a beginner builds a box with real clicks and drags (Draw shape, Pull it up) and reads how long it takes to print on the
## same plain label that shows its size: "Size: W x D x H cm (wide x deep x high), about 3 h 39 min to print".
## The test works the print time out from the BUILT result (the replayed volume and surface area, not the code's numbers):
## a print is mostly infill, so the walls (1.2 mm over the whole surface) and 20 percent of the middle are laid down, at a typical
## desktop rate of 20 cm3 an hour. Those three numbers are written here in the test, not read from the game.
## Bars (written before the code; the box is 18 x 6 x 2 cm = 216 cm3, surface 312 cm2, so about 3 h 39 min):
##   G0 the BUILDING card, one click: page BUILD, a blank part, Easy on
##   G1 after Pull it up: the size label is up and says "to print" with a time (about N min / about N h M min / under 1 min)
##   G2 the time shown is the built box's print time (within 1 minute)
##   G3 the built box's surface is the drawn box's (312 cm2 within 2 percent): the surface the time is worked from is real
##   G4 the words are plain: no sketch, extrude, fillet, boolean, feature, body, loft
##   G5 the label sits under the part's front edge and on the 1280 x 720 screen
##   G6 Undo of the pull: no solid, the label is hidden
## shots: C:/Temp/claude/p059printtimee/open.png, size.png, undo.png
const SHOT := "C:/Temp/claude/p059printtimee"
const DIRT := "user://p059printtimee_test"
const WALL_M := 0.0012      # the wall thickness the test assumes (1.2 mm)
const INFILL := 0.2         # the middle is printed at 20 percent
const CM3_PER_H := 20.0     # a typical desktop printer: about 20 cm3 of plastic an hour
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
	return Part.replay(m.S.part, -1, {"props": true})


## the print minutes the test expects for a built part: its volume (m3) and surface (m2) from the replay, the walls and 20 percent infill
func expected_min(res: Dictionary) -> float:
	var vol := float(res["volume"])
	var area := 0.0
	for p in res["props"]:
		area += float(p["area"])
	var wall := minf(area * WALL_M, vol)
	return (wall + (vol - wall) * INFILL) * 1.0e6 / CM3_PER_H * 60.0


## the minutes the label shows: "about N min to print", "about N h M min to print", "under 1 min to print"; -1 when none
func shown_min(txt: String) -> float:
	if txt.find("under 1 min to print") >= 0:
		return 0.5
	var rh := RegEx.new()
	rh.compile("about ([0-9]+) h ([0-9]+) min to print")
	var mh := rh.search(txt)
	if mh != null:
		return mh.get_string(1).to_float() * 60.0 + mh.get_string(2).to_float()
	var rm := RegEx.new()
	rm.compile("about ([0-9]+) min to print")
	var mm := rm.search(txt)
	return mm.get_string(1).to_float() if mm != null else -1.0


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

	# a box on the grid (18 cm x 6 cm), then Pull it up (2 cm)
	await click_ctl(ep.make_btns["draw"])
	await drag_pts([scr(Vector3(-0.09, 0.0, -0.03)), scr(Vector3(0.09, 0.0, 0.03))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(20)
	var s1 := solid()
	var bb: AABB = s1["aabb"]
	var lab: Label = root.find_child("easypart_size", true, false) as Label
	var txt := lab.text if lab != null else ""
	var shown := lab != null and lab.is_visible_in_tree() and txt.find("to print") >= 0
	var mins := shown_min(txt)
	ok(shown and mins >= 0.0 and int(s1["bodies"]) == 1, "G1 the label is up and gives the print time: [%s]" % txt)
	await shot("size")

	var want := expected_min(s1)
	ok(mins >= 0.0 and absf(mins - want) <= 1.0,
		"G2 the time is the built box's: shown %.1f min, worked out from the built volume and surface %.1f min" % [mins, want])
	var area := 0.0
	for p in s1["props"]:
		area += float(p["area"])
	var box_cm2 := 2.0 * (18.0 * 6.0 + 18.0 * 2.0 + 6.0 * 2.0)
	ok(absf(area * 1.0e4 - box_cm2) <= box_cm2 * 0.02,
		"G3 the surface it is worked from is the box's: %.1f cm2 (want %.1f)" % [area * 1.0e4, box_cm2])
	var jargon := []
	for jw in ["sketch", "extrude", "fillet", "boolean", "feature", "body", "loft"]:
		if txt.to_lower().find(jw) >= 0:
			jargon.append(jw)
	ok(jargon.is_empty(), "G4 the words are plain %s: [%s]" % [jargon, txt])

	var front := Vector3(bb.get_center().x, bb.position.y, bb.end.z)
	var fp := scr(front)
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var under := lab != null and lab.position.y >= fp.y and absf(lab.get_global_rect().get_center().x - fp.x) < 200.0
	ok(under and vp.encloses(lab.get_global_rect()) if lab != null else false,
		"G5 the label sits under the part's front edge (label top %.0f, front %.0f) and on screen" % [lab.position.y if lab != null else -1.0, fp.y])

	await click_ctl(ep.undo_btn)
	await idle(20)
	var gone := lab != null and not lab.visible
	ok(gone and int(solid()["bodies"]) == 0, "G6 Undo of the pull: no solid, the label is hidden")
	await shot("undo")
	print("p059printtimee: %d fail" % fails)
	quit(1 if fails > 0 else 0)
