extends SceneTree
## s029 (Friday plan 29, Kine's own): Holes in a pattern. After Cut a hole, Row / Around / Grid copy the round hole into a row (count + spacing mm),
## round a circle (count + radius mm, round the part's middle or a picked point) or a grid (rows x columns + spacing mm). One build step (the hole's
## own sketch and cut), every press and slider change one undo step, the holes are real cuts.
## godot --path . --position 4000,4000 -s tests/s029_test.gd     (needs a window and the CAD DLL)
## Bars (real clicks through root.push_input at 1280 x 720; a 100 x 60 x 10 mm plate from the Plate chip, a 6 mm hole):
##   ROW     4 holes at 20 mm: volume = 4 x pi x 3^2 x 10 within 1 %, ONE solid, centres (read off the built mesh) 20.0 mm apart within 0.05
##   AROUND  6 holes on r 20 mm: centres 60 deg apart within 0.1 deg, 20 mm from the middle within 0.05, volume within 1 %
##   GRID    3 rows x 2 columns at 15 mm: 6 holes' volume within 1 %, centres 15 mm apart within 0.05
##   STEPS   each chip = one undo step and no extra build step; one Undo click takes it back; Pick centre = one undo step
## Shots in C:/Temp/claude/s029/ . Only user:// is written (and the shots).
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s029"
const DIRT := "user://s029_test"


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
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


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


func click_ctl_at(p: Vector2) -> void:
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)



## a fresh 100 x 60 x 10 mm plate from the Plate chip (its Width and Length sliders in cm), then Cut a hole, then Hole size = 6 mm across
func fresh_plate(ep: EasyPart) -> void:
	m.S.part = {}   # start over: no part, no hole chips (the state the first plate was made from)
	ep.hole_base = {}
	ep.tweak = {}
	ep._rows_sig = ""
	ep.pu.sync()
	await idle(6)
	await click_ctl(ep.chips["plate"])
	await idle(3)
	for r in ep.rows:
		if String(r["key"]) == "width":
			(r["slider"] as HSlider).value = 10.0
		elif String(r["key"]) == "length":
			(r["slider"] as HSlider).value = 6.0
	await idle(4)


func hole6(ep: EasyPart) -> void:
	await click_ctl(ep.make_btns["hole"])
	await idle(3)
	(ep.rows[-1]["slider"] as HSlider).value = 0.6   # Hole size 0.6 cm = 6 mm across
	await idle(4)


func set_hp(ep: EasyPart, key: String, v: float) -> void:
	for r in ep.hpat_rows:
		if String(r["key"]) == key:
			(r["slider"] as HSlider).value = v
	await idle(4)


func hbtn(ep: EasyPart, nm: String) -> Button:
	return ep.hole_box.find_child("easypart_hole_" + nm, true, false) as Button


func vol_mm3() -> float:
	return float(Part.replay(m.S.part)["volume"]) * 1e9


## the hole centres (plate mm) found on the built mesh: the vertices on the top face (z = the plate's top) that are not on the plate's outline,
## grouped by closeness (a 6 mm hole is 3 mm from its middle), each group's middle
func hole_centres() -> Array:
	var r := Part.replay(m.S.part)
	var bb: AABB = r["aabb"]
	var top := bb.end.z / Part.MM
	var verts: PackedVector3Array = (r["mesh"] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var seen := {}
	var pts: Array = []
	for v in verts:
		var q := v / Part.MM
		if absf(q.z - top) > 0.01:
			continue
		if absf(q.x - bb.position.x / Part.MM) < 0.01 or absf(q.x - bb.end.x / Part.MM) < 0.01 or absf(q.y - bb.position.y / Part.MM) < 0.01 or absf(q.y - bb.end.y / Part.MM) < 0.01:
			continue
		var k := Vector2i(roundi(q.x * 100.0), roundi(q.y * 100.0))
		if seen.has(k):
			continue
		seen[k] = true
		pts.append(Vector2(q.x, q.y))
	var groups: Array = []
	for p in pts:
		var placed := false
		for g in groups:
			if (g[0] as Vector2).distance_to(p) < 7.0:
				(g as Array).append(p)
				placed = true
				break
		if not placed:
			groups.append([p])
	var out: Array = []
	for g in groups:
		var s := Vector2.ZERO
		for p in g:
			s += p
		out.append(s / float(g.size()))
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
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("SKIP: no KineCAD DLL")
		quit(1)
		return
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep: EasyPart = pu.ep
	var HOLE_MM3 := PI * 9.0 * 10.0   # one 6 mm hole through the 10 mm plate
	var win := Rect2(Vector2.ZERO, Vector2(1280, 720))

	# ---- ROW: 4 holes, 20 mm apart
	await fresh_plate(ep)
	var plate_v := vol_mm3()
	var bb0: AABB = Part.replay(m.S.part)["aabb"]
	ok(absf(bb0.size.x / Part.MM - 100.0) < 0.01 and absf(bb0.size.y / Part.MM - 60.0) < 0.01 and absf(bb0.size.z / Part.MM - 10.0) < 0.01,
		"0 PLATE: %.2f x %.2f x %.2f mm (want 100 x 60 x 10)" % [bb0.size.x / Part.MM, bb0.size.y / Part.MM, bb0.size.z / Part.MM])
	await hole6(ep)
	var one_v := vol_mm3()
	ok(absf((plate_v - one_v) - HOLE_MM3) < HOLE_MM3 * 0.01, "0 HOLE: the single 6 mm hole removes %.1f mm3 (want %.1f within 1 %%)" % [plate_v - one_v, HOLE_MM3])
	var feats_hole: int = m.S.part["features"].size()
	var rb := hbtn(ep, "row")
	var ab := hbtn(ep, "around")
	var gb := hbtn(ep, "grid")
	ok(rb != null and ab != null and gb != null and rb.is_visible_in_tree() and ab.is_visible_in_tree() and gb.is_visible_in_tree(), "1 CHIPS: Row, Around and Grid chips are on the Cut a hole panel")
	var u0: int = m.undo.size()
	await click_ctl(rb)
	var u1: int = m.undo.size()
	ok(u1 == u0 + 1 and m.S.part["features"].size() == feats_hole, "1 ONE STEP: the Row chip is one undo step (%d -> %d) and adds no build step (%d steps stay %d)" % [u0, u1, feats_hole, m.S.part["features"].size()])
	await click_ctl(ep.undo_btn)
	await idle(4)
	ok(absf(vol_mm3() - one_v) < 1e-6 and m.undo.size() == u0, "1 UNDO: one Undo click takes the row away (volume %.3f mm3 = the single hole's %.3f)" % [vol_mm3(), one_v])
	await click_ctl(rb)
	await set_hp(ep, "hp_count", 4.0)
	await set_hp(ep, "hp_gap", 20.0)
	var r1 := Part.replay(m.S.part)
	var removed := plate_v - vol_mm3()
	var want := 4.0 * HOLE_MM3
	ok(int(r1["bodies"]) == 1 and r1["errors"].is_empty() and absf(removed - want) < want * 0.01, "2 ROW VOLUME: ONE solid, the 4 holes remove %.1f mm3 (want %.1f within 1 %%)" % [removed, want])
	var cs := hole_centres()
	cs.sort_custom(func(a, b): return a.x < b.x)
	var worst := 0.0
	var ys_ok := true
	for i in range(1, cs.size()):
		worst = maxf(worst, absf((cs[i] as Vector2).x - (cs[i - 1] as Vector2).x - 20.0))
		ys_ok = ys_ok and absf((cs[i] as Vector2).y - (cs[0] as Vector2).y) < 0.05
	ok(cs.size() == 4 and worst < 0.05 and ys_ok, "2 ROW CENTRES: %d holes, spacing off by at most %.4f mm (want 20.0 within 0.05), all on one line %s" % [cs.size(), worst, str(ys_ok)])
	await shot("row")
	var inside := win.encloses(ep.hole_box.get_global_rect()) and win.encloses(ep.panel.get_global_rect())
	ok(inside, "2 FITS: the Cut a hole panel %s and the Easy panel %s are inside 1280 x 720" % [ep.hole_box.get_global_rect(), ep.panel.get_global_rect()])
	var sl_row: HSlider = null
	for r in ep.hpat_rows:
		if String(r["key"]) == "hp_gap":
			sl_row = r["slider"]
	var u_s: int = m.undo.size()
	(sl_row as HSlider).value = 25.0
	await idle(4)
	ok(m.undo.size() == u_s + 1, "2 SLIDER STEP: a Spacing change is one undo step")
	# the hole size slider moves every hole of the row
	var v_before_size := vol_mm3()
	(ep.rows[-1]["slider"] as HSlider).value = 0.8
	await idle(4)
	var d_size := v_before_size - vol_mm3()
	ok(d_size > 4.0 * PI * (16.0 - 9.0) * 10.0 * 0.97 and int(Part.replay(m.S.part)["bodies"]) == 1, "2 SIZE: Hole size 8 mm cuts all 4 holes wider (%.0f mm3 more, want about %.0f)" % [d_size, 4.0 * PI * 7.0 * 10.0])

	# ---- AROUND: 6 holes on a circle of 20 mm round the middle
	await fresh_plate(ep)
	await hole6(ep)
	ok(m.S.part["features"].size() == feats_hole, "3 BASE: a fresh plate and hole again (%d steps)" % m.S.part["features"].size())
	ab = hbtn(ep, "around")
	var ua0: int = m.undo.size()
	await click_ctl(ab)
	ok(m.undo.size() == ua0 + 1 and m.S.part["features"].size() == feats_hole, "3 ONE STEP: the Around chip is one undo step and no extra build step")
	await set_hp(ep, "hp_count", 6.0)
	await set_hp(ep, "hp_rad", 20.0)
	var r2 := Part.replay(m.S.part)
	var rem2 := plate_v - vol_mm3()
	ok(int(r2["bodies"]) == 1 and r2["errors"].is_empty() and absf(rem2 - 6.0 * HOLE_MM3) < 6.0 * HOLE_MM3 * 0.01, "3 AROUND VOLUME: ONE solid, 6 holes remove %.1f mm3 (want %.1f within 1 %%)" % [rem2, 6.0 * HOLE_MM3])
	var c2 := hole_centres()
	var mid := Vector2.ZERO
	for q in c2:
		mid += q
	mid /= maxf(c2.size(), 1)
	var angs: Array = []
	var rad_off := 0.0
	for q in c2:
		angs.append(rad_to_deg(atan2((q as Vector2).y - mid.y, (q as Vector2).x - mid.x)))
		rad_off = maxf(rad_off, absf(((q as Vector2) - mid).length() - 20.0))
	angs.sort()
	var worst_a := 0.0
	for i in angs.size():
		var nxt: float = angs[(i + 1) % angs.size()] + (360.0 if i + 1 == angs.size() else 0.0)
		worst_a = maxf(worst_a, absf(nxt - float(angs[i]) - 60.0))
	ok(c2.size() == 6 and worst_a < 0.1 and rad_off < 0.05 and mid.distance_to(Vector2(50, 30)) < 0.05, "3 AROUND CENTRES: %d holes, 60 deg steps off by at most %.4f deg (want 0.1), radius off by %.4f mm, circle middle %s (the part's middle 50, 30)" % [c2.size(), worst_a, rad_off, str(mid)])
	await shot("around")

	# Pick centre: the circle goes round the point clicked on the part
	ok(hbtn(ep, "pickc") != null and hbtn(ep, "pickc").is_visible_in_tree(), "4 PICK: Pick centre shows beside Holes around")
	await set_hp(ep, "hp_rad", 8.0)
	await click_ctl(hbtn(ep, "pickc"))
	var up0: int = m.undo.size()
	var target := Vector3(25.0, 15.0, 10.0) * Part.MM   # on the plate's top face, 25 mm in and 15 mm up
	var sp: Vector2 = m.cam.unproject_position(target)
	await click_ctl_at(sp)
	await idle(4)
	var hp: Dictionary = Part.feature(m.S.part, ep.hole_id).get("hpat", {})
	var r4 := Part.replay(m.S.part)
	var c4 := hole_centres()
	var mid4 := Vector2.ZERO
	for q in c4:
		mid4 += q
	mid4 /= maxf(c4.size(), 1)
	ok(m.undo.size() == up0 + 1 and absf(float(hp.get("px", 0.0)) - mid4.x) < 0.1 and absf(float(hp.get("py", 0.0)) - mid4.y) < 0.1 and mid4.distance_to(Vector2(50, 30)) > 5.0 and int(r4["bodies"]) == 1 and c4.size() == 6,
		"4 PICK: one undo step, the 6 holes now go round (%.1f, %.1f), picked near (25, 15), one solid" % [mid4.x, mid4.y])
	await shot("pick")

	# ---- GRID: 3 rows x 2 columns, 15 mm apart
	await fresh_plate(ep)
	await hole6(ep)
	gb = hbtn(ep, "grid")
	var ug0: int = m.undo.size()
	await click_ctl(gb)
	ok(m.undo.size() == ug0 + 1 and m.S.part["features"].size() == feats_hole, "5 ONE STEP: the Grid chip is one undo step and no extra build step")
	await set_hp(ep, "hp_rows", 3.0)
	await set_hp(ep, "hp_cols", 2.0)
	var v_pre_gap := vol_mm3()
	await set_hp(ep, "hp_gap", 15.0)
	var r3 := Part.replay(m.S.part)
	var rem3 := plate_v - vol_mm3()
	ok(int(r3["bodies"]) == 1 and r3["errors"].is_empty() and absf(rem3 - 6.0 * HOLE_MM3) < 6.0 * HOLE_MM3 * 0.01, "5 GRID VOLUME: ONE solid, 3 x 2 holes remove %.1f mm3 (want %.1f within 1 %%)" % [rem3, 6.0 * HOLE_MM3])
	var c3 := hole_centres()
	var xs := {}
	var ysd := {}
	for q in c3:
		xs[snappedf((q as Vector2).x, 0.1)] = true
		ysd[snappedf((q as Vector2).y, 0.1)] = true
	var xk: Array = xs.keys()
	var yk: Array = ysd.keys()
	xk.sort()
	yk.sort()
	ok(c3.size() == 6 and xk.size() == 2 and yk.size() == 3 and absf(float(xk[1]) - float(xk[0]) - 15.0) < 0.05 and absf(float(yk[1]) - float(yk[0]) - 15.0) < 0.05 and absf(float(yk[2]) - float(yk[1]) - 15.0) < 0.05,
		"5 GRID CENTRES: %d holes in %d columns x %d rows, spacing %.3f / %.3f mm (want 15 within 0.05)" % [c3.size(), xk.size(), yk.size(), float(xk[1]) - float(xk[0]) if xk.size() > 1 else 0.0, float(yk[1]) - float(yk[0]) if yk.size() > 1 else 0.0])
	await shot("grid")
	await click_ctl(ep.undo_btn)
	await idle(4)
	ok(int(Part.replay(m.S.part)["bodies"]) == 1 and absf(vol_mm3() - v_pre_gap) < 1e-6, "5 UNDO: one Undo takes back the last Spacing step (volume %.3f mm3 = %.3f before it)" % [vol_mm3(), v_pre_gap])

	print("s029: %d fail" % fails)
	quit(1 if fails > 0 else 0)
