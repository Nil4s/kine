extends SceneTree
## P076 WHAT FITS HERE? (Friday plan item 76, Kine's own idea: the hole asks the library what fits it): a beginner makes a plate, cuts a
## screw hole, and presses What fits here? to see which of MY PARTS go through it. Real clicks and drags at 1280 x 720.
##   BUILDING card -> Easy Part (blank) -> Draw shape (box 18 x 6 cm) -> Pull it up = the plate
##   -> Cut a hole -> M4 screw (a 4.5 mm clearance hole) -> What fits here? -> the words name the saved parts that fit
##   -> M3 screw (3.4 mm) -> What fits here? -> nothing fits, and the words say to make the hole bigger
## Two saved parts (made here as records and saved with MyParts.save): Thin peg (radius 1.2 mm, 2.4 mm across) and Wide peg (radius 3 mm,
## 6 mm across). The rule (the same one the code uses, written here in words): a part fits when its two smallest sides, corner to corner,
## fit the hole with 0.2 mm to spare on each side: diagonal <= hole - 0.4 mm. The hole sizes come from the built result: the plate's volume
## lost to the screw hole is compared with the ISO clearance cylinder + counterbore (computed here from the ISO numbers, never from the code).
## Bars (run on the code before this change: see the report):
##   P0 after an M4 screw hole the What fits here? button is on the screen
##   P1 the words name Thin peg, and not Wide peg
##   P2 the words name the 4.5 mm hole, and the plate's built volume lost matches a 4.5 mm hole + 7 mm x 4 mm counterbore (within 3 %)
##   P3 What fits here? is not an undo step (the undo count does not move)
##   P4 no jargon (sketch, extrude, boolean, feature, body, loft, cylinder, aabb) in the words
##   P5 after an M3 screw hole the built volume matches 3.4 mm + 5.5 mm x 3 mm (within 3 %), and What fits here? says nothing fits and names the next step (bigger)
##   P6 the M3 words name 3.4 mm
## shots: C:/Temp/claude/p076whatfitshe/plate.png, fits.png, nofit.png
const SHOT := "C:/Temp/claude/p076whatfitshe"
const DIRT := "user://p076whatfitshe_test"
const PARTS := "user://p076whatfitshe_parts"
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


func labels(n: Node, out: Array) -> void:
	if n is Label and (n as Label).is_visible_in_tree():
		out.append((n as Label).text)
	for c in n.get_children():
		labels(c, out)


func solid() -> Dictionary:
	return Part.replay(m.S.part)


func vol_mm3(s: Dictionary) -> float:
	return float(s.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


## the volume a screw hole takes out of a plate T mm deep: a clearance cylinder through it + the counterbore ring for the head
func want_mm3(clear_mm: float, head_mm: float, head_h: float, T: float) -> float:
	var r := clear_mm / 2.0
	var R := head_mm / 2.0
	return PI * r * r * T + PI * (R * R - r * r) * head_h


## a saved part for the test: one round peg of radius r mm and height h mm (a circle on the top plane, pulled up)
func peg_rec(nm: String, r: float, h: float) -> Dictionary:
	var rec := Part.make(nm)
	var sk := Part.new_feature(rec, "sketch", {"plane": "top", "ents": [{"k": "circle", "c": Part.arr2(Vector2.ZERO), "r": r}], "dims": []})
	rec["features"].append(sk)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": sk["id"], "dist": h, "both": false, "op": "new"}))
	return rec


## the two smallest sides of a built part, in mm (the cross-section the hole has to take)
func two_smallest_mm(s: Dictionary) -> Array:
	var sz: Vector3 = (s["aabb"] as AABB).size / Part.MM
	var a := [sz.x, sz.y, sz.z]
	a.sort()
	return [a[0], a[1]]


func solid_of(nm: String) -> Dictionary:
	return Part.replay(MyParts.load_part(nm))


func fits_rule(hole_mm: float, s: Dictionary) -> bool:
	var t := two_smallest_mm(s)
	return sqrt(t[0] * t[0] + t[1] * t[1]) <= hole_mm - 0.4


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
	# the saved parts live in their own test folder: a clean one each run (only this test's two pegs are in it)
	MyParts.dir = PARTS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PARTS))
	for f in DirAccess.get_files_at(ProjectSettings.globalize_path(PARTS)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PARTS + "/" + f))
	MyParts.save(peg_rec("Thin peg", 1.2, 20.0), "Thin peg")
	MyParts.save(peg_rec("Wide peg", 3.0, 20.0), "Wide peg")
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
	m.pitch = 35.0
	m.yaw = 30.0
	m._cam()
	await idle(60)

	# the plate: a box on the grid (18 cm x 6 cm), Pull it up (2 cm)
	await click_ctl(ep.make_btns["draw"])
	await drag_pts([scr(Vector3(-0.09, 0.0, -0.03)), scr(Vector3(0.09, 0.0, 0.03))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var s1 := solid()
	var v1 := vol_mm3(s1)
	var bb1: AABB = s1["aabb"]
	var T := bb1.size.z / Part.MM   # the plate's depth in mm, from the built result
	ok(int(s1["bodies"]) == 1 and v1 > 1000.0, "plate: one body, volume %.0f mm3, depth %.1f mm" % [v1, T])
	await shot("plate")

	# an M4 screw hole (4.5 mm), then What fits here?
	await click_ctl(ep.make_btns["hole"])
	await idle(10)
	var n0: int = m.undo.size()
	if ep.hole_btns.has("screw4"):
		await click_ctl(ep.hole_btns["screw4"])
	await idle(10)
	var s2 := solid()
	var removed4 := v1 - vol_mm3(s2)
	var want4 := want_mm3(4.5, 7.0, 4.0, T)
	ok(int(s2["bodies"]) == 1 and absf(removed4 - want4) < 0.03 * want4,
		"P2a M4 screw hole built: plate lost %.1f mm3 (a 4.5 mm hole + 7 mm x 4 mm counterbore = %.1f mm3)" % [removed4, want4])

	var fb: Button = ep.hole_box.find_child("easypart_hole_fits", true, false) as Button
	ok(fb != null and fb.is_visible_in_tree(), "P0 after an M4 screw hole: the What fits here? button is on the screen")
	var n1: int = m.undo.size()
	if fb != null:
		await click_ctl(fb)
	await idle(10)
	var n2: int = m.undo.size()
	var said := String(ep.hint_l.text) + " " + String(ep.msg)
	ok(said.find("Thin peg") >= 0 and said.find("Wide peg") < 0, "P1 the words name Thin peg and not Wide peg: [%s]" % said)
	ok(said.find("fit") >= 0 and said.find("4.5 mm") >= 0, "P2 the words are the fit answer and name the 4.5 mm hole: [%s]" % said)
	ok(fb != null and n2 == n1 and n2 >= n0, "P3 What fits here? is not an undo step (undo count %d -> %d)" % [n1, n2])
	var thin := solid_of("Thin peg")
	var wide := solid_of("Wide peg")
	ok(fits_rule(4.5, thin) and not fits_rule(4.5, wide) and not fits_rule(3.4, thin), "P1b the built sizes agree with the rule: thin fits 4.5 mm, wide does not, thin does not fit 3.4 mm")
	await shot("fits")

	var words := said
	var lab := []
	labels(ep.status, lab)
	words += " " + " ".join(lab)
	var jargon := []
	for w in ["sketch", "extrude", "boolean", "feature", "body", "loft", "cylinder", "aabb"]:
		if words.to_lower().find(w) >= 0:
			jargon.append(w)
	ok(jargon.is_empty(), "P4 no jargon on the words %s: [%s]" % [jargon, said])

	# an M3 screw hole (3.4 mm) replaces it: nothing saved fits, and the words say to make the hole bigger
	if ep.hole_btns.has("screw3"):
		await click_ctl(ep.hole_btns["screw3"])
	await idle(10)
	var s3 := solid()
	var removed3 := v1 - vol_mm3(s3)
	var want3 := want_mm3(3.4, 5.5, 3.0, T)
	ok(int(s3["bodies"]) == 1 and absf(removed3 - want3) < 0.03 * want3,
		"P5a M3 screw hole built: plate lost %.1f mm3 (a 3.4 mm hole + 5.5 mm x 3 mm counterbore = %.1f mm3)" % [removed3, want3])
	fb = ep.hole_box.find_child("easypart_hole_fits", true, false) as Button
	if fb != null:
		await click_ctl(fb)
	await idle(10)
	var said3 := String(ep.hint_l.text) + " " + String(ep.msg)
	ok(said3.find("Nothing") >= 0 and said3.find("bigger") >= 0,
		"P5 after M3: the words say nothing fits and to make the hole bigger: [%s]" % said3)
	ok(said3.find("fit") >= 0 and said3.find("3.4 mm") >= 0, "P6 the M3 words are the fit answer and name the 3.4 mm hole: [%s]" % said3)
	await shot("nofit")

	MyParts.dir = ""
	print("p076whatfitshe: %d fail" % fails)
	quit(1 if fails > 0 else 0)
