extends SceneTree
## P080 WOOD BOARDS (Friday plan item 80): the Easy Part Parts library gets a Wood boards category; inside it a 2x4 board (38 x 89 mm, 8 ft = 2438 mm)
## and an MDF sheet 15 mm (1220 x 2440 mm). A board lies flat on the floor: 89 wide (X), 38 thick (Y), 2438 long (Z). Its three sliders
## (Width, Thickness, Length, in cm) show; a star readout says how many of this board one MDF sheet cuts (across x along).
## A beginner walk with real clicks on the live Easy Part, from the BUILDING card (no keyboard). Measured from the BUILT result (mesh mm,
## undo steps), never from the code's own variables. Bars are written before the code.
##   1 PAGE      Parts opens the page, Wood boards is a chip on the 1280 x 720 screen, 34 px or taller, with an icon; its two board chips (2x4 board, MDF sheet 15 mm) are shown on the same screen   (FAILS on old code)
##   2 2X4       Wood boards, then 2x4 board: ONE undo step, one solid, built lying flat: X 89 +- 0.5, Y 38 +- 0.5, Z 2438 +- 0.5 mm (measured from the mesh)                              (FAILS on old code)
##   3 MDF       MDF sheet 15 mm: ONE undo step, it replaces the 2x4 (one solid), X 1220 +- 0.5, Y 15 +- 0.5, Z 2440 +- 0.5 mm                                                  (FAILS on old code)
##   4 SLIDERS   the board shows three sliders, named Width, Thickness and Length, in plain words; no screw sizes on screen                                                    (FAILS on old code)
##   5 SHEET     the star readout names how many of the built board one MDF sheet cuts: the number in the readout = floor(1220 / X) x floor(2440 / Z) from the mesh (2x4 gives 13)  (FAILS on old code)
##   6 SAME      2x4 board again while the 2x4 is on the floor: no undo step, the words say it is already there                                                                    (FAILS on old code)
##   7 SCREW     Screws, then M4 x 16 still builds to ISO 4762 with ONE undo step (the Screws page is not broken by Wood boards)                                                           (passes on old code: a guard)
##   8 WORDS     no key name in the board words, the readout or the status line; Wood boards says no 'coming soon'                                                                      (FAILS on old code)
## Shots: C:/Temp/claude/p080woodboards/page.png (the Wood boards page), board2x4.png, boardmdf.png (the sheet on the floor)
const SHOT := "C:/Temp/claude/p080woodboards"
const DIRT := "user://p080woodboards_test"
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]
const ISO4 := [7.0, 20.0, 4.0, 16.0]   # M4 x 16 (ISO 4762) standing on the floor: head 7 across, 4 head + 16 shank = 20 tall (Y), mm
const WANT_2X4 := [89.0, 38.0, 2438.0]     # X (width), Y (thickness), Z (length), mm
const WANT_MDF := [1220.0, 15.0, 2440.0]
const SHEET_W := 1220.0
const SHEET_L := 2440.0
var fails := 0
var m: Node
var pu: PartUI
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


## a real click on a visible control; a missing control is reported by the bar that needs it (no crash)
func click_ctl(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)
	return true


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func named(nm: String) -> Control:
	return root.find_child(nm, true, false) as Control


func lib_wood() -> Button:
	return named("easypart_lib_Wood boards") as Button


func board_chip(key: String) -> Button:
	return named("easypart_wood_" + key) as Button


func screw_chip(d: int, L: int) -> Button:
	return named("easypart_screw_M%d_%d" % [d, L]) as Button


## the built part's size along X, Y, Z (mm), from the mesh; [] when there is no geometry
func dims() -> Array:
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var any := false
	for f in Part.body_faces(m.S.part):
		var arr: PackedVector3Array = f
		for v in arr:
			var p := v * 1000.0
			lo = lo.min(p)
			hi = hi.max(p)
			any = true
	if not any:
		return []
	var sz := hi - lo
	return [sz.x, sz.y, sz.z]


func near3(d: Array, want: Array) -> bool:
	if d.size() != 3:
		return false
	for i in 3:
		if absf(float(d[i]) - float(want[i])) > 0.5:
			return false
	return true


## the first whole number in the readout text, -1 when there is none
func first_int(txt: String) -> int:
	var re := RegEx.new()
	re.compile("[0-9]+")
	var r := re.search(txt)
	return int(r.get_string()) if r != null else -1


func readout() -> String:
	var l := named("easypart_wood_cut") as Label
	return l.text if l != null and l.is_visible_in_tree() else ""


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
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the boards cannot run")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))

	# 1 PAGE: the Parts page shows Wood boards and its two board chips on the screen
	await click_ctl(named("easypart_chip_parts") as Button)
	var lb := lib_wood()
	var on_screen := lb != null and lb.is_visible_in_tree() and vp.encloses(Rect2(lb.global_position, lb.size))
	var tall := lb != null and lb.size.y >= 34.0
	var icon := lb != null and lb.icon != null
	await click_ctl(lb)
	var b2 := board_chip("2x4")
	var bm := board_chip("mdf")
	var chips_ok := b2 != null and bm != null and b2.is_visible_in_tree() and bm.is_visible_in_tree()
	chips_ok = chips_ok and vp.encloses(Rect2(b2.global_position, b2.size)) and vp.encloses(Rect2(bm.global_position, bm.size))
	ok(on_screen and tall and icon and chips_ok, "1 Parts opens the page: Wood boards on the screen (%s), 34 px or taller (%s), with an icon (%s), the 2x4 and MDF chips on the screen (%s)" % [str(on_screen), str(tall), str(icon), str(chips_ok)])
	await shot("page")

	# 2 2X4: one undo step, one solid, lying flat at 89 x 38 x 2438 mm
	var ub0: int = m.undo.size()
	await click_ctl(b2)
	var d2 := dims()
	ok(near3(d2, WANT_2X4) and m.undo.size() == ub0 + 1 and int(pu.res.get("bodies", 0)) == 1, "2 2x4 board: one undo step (%d -> %d), one solid, X x Y x Z %s mm (want 89 x 38 x 2438 +- 0.5)" % [ub0, m.undo.size(), str(d2)])
	await shot("board2x4")

	# 3 MDF: one undo step, replaces the 2x4 (one solid), 1220 x 15 x 2440 mm
	var ub1: int = m.undo.size()
	await click_ctl(bm)
	var d3 := dims()
	ok(near3(d3, WANT_MDF) and m.undo.size() == ub1 + 1 and int(pu.res.get("bodies", 0)) == 1, "3 MDF sheet 15 mm: one undo step (%d -> %d), replaces the 2x4 (one solid), X x Y x Z %s mm (want 1220 x 15 x 2440 +- 0.5)" % [ub1, m.undo.size(), str(d3)])
	await shot("boardmdf")

	# 4 SLIDERS: Width, Thickness, Length on the board; no screw sizes on screen
	var labels := []
	for r in ep.rows:
		if String(r.get("kind", "")) == "tpl":
			labels.append(String(r.get("label", "")))
	var screws_on := 0
	for L in [10, 16, 20, 30]:
		var sc := screw_chip(4, L)
		if sc != null and sc.is_visible_in_tree():
			screws_on += 1
	ok(labels == ["Width", "Thickness", "Length"] and screws_on == 0, "4 the board has three sliders %s, no screw sizes on screen (%d)" % [str(labels), screws_on])

	# 5 SHEET: the readout's number is the cut count from the built mesh (the MDF sheet itself: 1)
	var want_mdf := 1
	var got_mdf := first_int(readout())
	await click_ctl(b2)
	var d5 := dims()
	var want_2x4 := 0
	if d5.size() == 3 and float(d5[0]) > 0.0 and float(d5[2]) > 0.0:
		want_2x4 = int(floor(SHEET_W / float(d5[0]))) * int(floor(SHEET_L / float(d5[2])))
	var got_2x4 := first_int(readout())
	ok(got_mdf == want_mdf and got_2x4 == want_2x4 and want_2x4 == 13, "5 star readout: the MDF sheet cuts %d (want %d), the 2x4 cuts %d (want floor(1220/%.0f) x floor(2440/%.0f) = %d)" % [got_mdf, want_mdf, got_2x4, float(d5[0]) if d5.size() == 3 else -1.0, float(d5[2]) if d5.size() == 3 else -1.0, want_2x4])

	# 6 SAME: the 2x4 on the floor again: no undo step, the words say so
	var ub2: int = m.undo.size()
	await click_ctl(b2)
	var st := String(ep.hint_l.text)   # the words of a press are the hint line
	ok(m.undo.size() == ub2 and st.to_lower().contains("already"), "6 2x4 again: no undo step (%d -> %d), the words say already (%s)" % [ub2, m.undo.size(), st])

	# 7 SCREW: M4 x 16 still builds to ISO 4762 in one undo step
	await click_ctl(named("easypart_lib_Screws") as Button)
	var ub3: int = m.undo.size()
	await click_ctl(screw_chip(4, 16))
	var sd := dims()
	var iso_ok := sd.size() == 3 and absf(float(sd[0]) - ISO4[0]) <= 0.1 and absf(float(sd[2]) - ISO4[0]) <= 0.1 and absf(float(sd[1]) - ISO4[1]) <= 0.1
	ok(iso_ok and m.undo.size() == ub3 + 1, "7 Screws, M4 x 16: one undo step (%d -> %d), head 7 across, 20 tall (4 head + 16 shank) from the mesh %s" % [ub3, m.undo.size(), str(sd)])

	# 8 WORDS: no key names in the board words, the readout or the status; Wood boards says no 'coming soon'
	var hit := []
	var texts := [ep.hint_l.text, ep.status_l.text, readout()]
	for c in [b2, bm, lib_wood()]:
		if c != null:
			texts.append(String(c.text))
	for t in texts:
		for w in BAD_WORDS:
			if String(t).to_lower().contains(w):
				hit.append("%s in [%s]" % [w, t])
	var sl := named("easypart_lib_soon") as Label
	var soon_shown := sl != null and sl.is_visible_in_tree() and sl.text.to_lower().contains("coming soon")
	ok(hit.is_empty() and not soon_shown, "8 no key name in the board words, the readout or the status %s; Wood boards is not 'coming soon' (%s)" % [str(hit), str(soon_shown)])
	print("p080woodboards: %d fail" % fails)
	quit(1 if fails > 0 else 0)
