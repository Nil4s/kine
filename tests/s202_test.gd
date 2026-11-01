extends SceneTree
## S202 (Friday plan 202, Smart tolerances: "How should it fit?"). A beginner builds a 40 mm box with real clicks at 1280 x 720, Cut a hole, and the
## Fit chip on the hole panel sets the clearance per side: Tight 0.0, Snug 0.1, Slides 0.2 (default), Loose 0.4 mm. Everything is measured from the BUILT mesh.
##   1 SLIDES    a 10 mm peg hole (Hole size 1.0 cm) at the default is 10.40 mm across (+-0.02)
##   2 LOOSE     one press of the Fit chip: 10.80 mm, ONE undo step, the Hole size slider still reads 1.0 cm; one Undo gives 10.40 again
##   3 TIGHT     Slides > Loose > Tight: 10.00 mm. SNUG: 10.20 mm; the part remembers it (fit_mm in the record) and the chip says it
##   4 LID       Hollow with a lid at Slides: the lid's lip is 0.2 mm smaller per side than the box's opening (measured, both axes)
##   5 LID LOOSE the Fit chip on the lid: 0.4 mm per side, ONE undo step; Tight: 0.0
##   6 WORDS     the chip says Fit: and a plain word, no jargon
## Shots: C:/Temp/claude/s202/hole.png, lid.png
const SHOT := "C:/Temp/claude/s202"
const DIRT := "user://s202_test"
var fails := 0
var m: Node
var ep


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


## the hole's across (mm): the nearest mesh vertex to the part's middle axis (the hole runs along Z through the middle), x2
func hole_across() -> float:
	var faces: Array = Part.body_faces(m.S.part)
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for f in faces:
		for v in (f as PackedVector3Array):
			lo = lo.min(Vector2(v.x, v.z) * 1000.0)
			hi = hi.max(Vector2(v.x, v.z) * 1000.0)
	var c := (lo + hi) * 0.5
	var best := 1e9
	for f in faces:
		for v in (f as PackedVector3Array):
			best = minf(best, (Vector2(v.x, v.z) * 1000.0 - c).length())
	return 2.0 * best


## the lid's lip and the box's opening (mm): [lip_x, lip_z, open_x, open_z]; empty when it is not two solids
func lip_vs_opening() -> Array:
	var faces: Array = Part.body_faces(m.S.part)
	if faces.size() != 2:
		return []
	var tops := []
	for f in faces:
		var t := -1e9
		for v in (f as PackedVector3Array):
			t = maxf(t, v.y * 1000.0)
		tops.append(t)
	var lid := 0 if float(tops[0]) > float(tops[1]) else 1
	var lid_top: float = tops[lid]
	var box_top: float = tops[1 - lid]
	var lx0 := 1e9
	var lx1 := -1e9
	var lz0 := 1e9
	var lz1 := -1e9
	for v in (faces[lid] as PackedVector3Array):
		if v.y * 1000.0 < lid_top - 5.0 - 0.05:   # below the 5 mm plate: the lip
			lx0 = minf(lx0, v.x * 1000.0)
			lx1 = maxf(lx1, v.x * 1000.0)
			lz0 = minf(lz0, v.z * 1000.0)
			lz1 = maxf(lz1, v.z * 1000.0)
	var wx0 := 1e9
	var wx1 := -1e9
	var wz0 := 1e9
	var wz1 := -1e9
	for v in (faces[1 - lid] as PackedVector3Array):
		wx0 = minf(wx0, v.x * 1000.0)
		wx1 = maxf(wx1, v.x * 1000.0)
		wz0 = minf(wz0, v.z * 1000.0)
		wz1 = maxf(wz1, v.z * 1000.0)
	var ox0 := 1e9
	var ox1 := -1e9
	var oz0 := 1e9
	var oz1 := -1e9
	for v in (faces[1 - lid] as PackedVector3Array):   # the rim's inner edge: top-height vertices that are not on the outside
		var x := v.x * 1000.0
		var z := v.z * 1000.0
		if absf(v.y * 1000.0 - box_top) < 0.05 and x > wx0 + 0.5 and x < wx1 - 0.5 and z > wz0 + 0.5 and z < wz1 - 0.5:
			ox0 = minf(ox0, x)
			ox1 = maxf(ox1, x)
			oz0 = minf(oz0, z)
			oz1 = maxf(oz1, z)
	return [lx1 - lx0, lz1 - lz0, ox1 - ox0, oz1 - oz0]


func gaps() -> Array:
	var lv := lip_vs_opening()
	if lv.size() != 4:
		return [-1.0, -1.0]
	return [(float(lv[2]) - float(lv[0])) * 0.5, (float(lv[3]) - float(lv[1])) * 0.5]


func size_row() -> Dictionary:
	var out := {}
	for rw in ep.rows:
		if String(rw["kind"]) == "tweak":
			out = rw
	return out


func press_fit() -> void:
	await click_ctl(ep.smartfit_btn)
	await idle(8)


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
	ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(60)
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.shape_btns["box"])
	await drag_pts([scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02))])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	m.pitch = 50.0
	m._cam()
	await idle(40)
	await click_ctl(ep.make_btns["hole"])
	await idle(10)
	var rw := size_row()
	var has_chip: bool = ep.smartfit_btn != null and ep.smartfit_btn.is_visible_in_tree()
	ok(not rw.is_empty() and has_chip, "0 the Cut a hole panel has a Hole size slider and a Fit chip (%s)" % [str(ep.smartfit_btn.text if ep.smartfit_btn != null else "none")])
	if rw.is_empty() or not has_chip:
		print("s202: %d fail" % (fails + 1))
		quit(1)
		return
	(rw["slider"] as HSlider).value = 1.0   # the peg: 10 mm
	await idle(10)
	await press_fit()   # fix102 fixture: the default fit is Exact now; this test picks Slides explicitly (Exact -> Snug -> Slides)
	await press_fit()
	var a1 := hole_across()
	ok(absf(a1 - 10.40) <= 0.02 and ep.smartfit_btn.text == "Fit: Slides", "1 SLIDES: a 10 mm peg hole is %.3f mm across (want 10.40 +-0.02), chip [%s]" % [a1, ep.smartfit_btn.text])
	await shot("hole")
	# 2 LOOSE: one press, one undo step, the size slider keeps its reading
	var u0: int = m.undo.size()
	await press_fit()
	var a2 := hole_across()
	rw = size_row()
	var sv: float = (rw["slider"] as HSlider).value
	ok(absf(a2 - 10.80) <= 0.02 and m.undo.size() == u0 + 1 and absf(sv - 1.0) <= 0.01, "2 LOOSE: %.3f mm (want 10.80), undo %d -> %d, slider reads %.2f cm (want 1.00), chip [%s]" % [a2, u0, m.undo.size(), sv, ep.smartfit_btn.text])
	m._undo()
	await idle(10)
	var a2u := hole_across()
	ok(absf(a2u - 10.40) <= 0.02 and m.undo.size() == u0, "2 one Undo gives 10.40 mm again: %.3f mm, undo %d" % [a2u, m.undo.size()])
	# 3 TIGHT: Slides > Loose > Tight
	await press_fit()
	await press_fit()
	var a3 := hole_across()
	ok(absf(a3 - 10.00) <= 0.02 and ep.smartfit_btn.text == "Fit: Tight", "3 TIGHT: %.3f mm (want 10.00), chip [%s]" % [a3, ep.smartfit_btn.text])
	await press_fit()
	var a4 := hole_across()
	var fm: float = float(m.S.part.get("fit_mm", -1.0))
	ok(absf(a4 - 10.20) <= 0.02 and absf(fm - 0.1) < 0.001 and ep.smartfit_btn.text == "Fit: Snug", "3 SNUG: %.3f mm (want 10.20), the part remembers fit_mm %.2f, chip [%s]" % [a4, fm, ep.smartfit_btn.text])
	await press_fit()
	var a5 := hole_across()
	ok(absf(a5 - 10.40) <= 0.02, "3 back to Slides: %.3f mm" % a5)
	# 4 LID at Slides
	await click_ctl(ep.hole_btns["lid"])
	await idle(12)
	var g4 := gaps()
	ok(absf(float(g4[0]) - 0.2) <= 0.02 and absf(float(g4[1]) - 0.2) <= 0.02, "4 LID at Slides: lip %.3f mm smaller per side than the opening in x, %.3f in z (want 0.20)" % [float(g4[0]), float(g4[1])])
	await shot("lid")
	# 5 LID LOOSE, then Tight
	var u1: int = m.undo.size()
	await press_fit()
	var g5 := gaps()
	ok(absf(float(g5[0]) - 0.4) <= 0.02 and absf(float(g5[1]) - 0.4) <= 0.02 and m.undo.size() == u1 + 1, "5 LID LOOSE: gap per side x %.3f z %.3f (want 0.40), undo %d -> %d" % [float(g5[0]), float(g5[1]), u1, m.undo.size()])
	await press_fit()   # Tight
	var g6 := gaps()
	ok(absf(float(g6[0])) <= 0.02 and absf(float(g6[1])) <= 0.02 and ep.smartfit_btn.text == "Fit: Tight", "5 LID TIGHT: gap per side x %.3f z %.3f (want 0.00), chip [%s]" % [float(g6[0]), float(g6[1]), ep.smartfit_btn.text])
	# 6 WORDS
	var words: String = (ep.smartfit_btn.text + " " + ep.smartfit_btn.tooltip_text + " " + String(ep.msg)).to_lower()
	var bad := ""
	for j in ["sketch", "extrude", "shell", "kernel", "feature", "boolean", "offset"]:
		if words.find(j) >= 0:
			bad = j
	ok(bad == "" and words.find("fit") >= 0, "6 WORDS: plain, no jargon (%s) [%s]" % [bad, words])
	print("s202: %d fail" % fails)
	quit(1 if fails > 0 else 0)
