extends SceneTree
## godot --path . --position 4000,4000 -s tests/s013_test.gd     (Friday plans 13 + 36: Soft / Medium / Sharp presets for Round the edges, and a Rib chip on the Brackets page;
## scripts/easy_part.gd; needs the CAD DLL)
## Bars (real clicks at 1280 x 720, from the BUILDING card; the slider moves set the slider's value, which fires its changed signal). All numbers are
## read from the BUILT result (mesh vertices in mm, the kernel volume in mm3), never from the code's own variables.
##   R0 a box 40 x 40 x 20 mm is drawn and pulled up (measured box)
##   R1 Soft: ONE undo step, the flat top face is 40 - 2 r wide with r = 5.0 (within 0.05), the volume matches a box rounded by 5.0 (0.2 pct), one solid
##   R2 Medium (pressed right after Soft: it replaces the round, one step): r = 2.4 within 0.05 from the top face and from the volume
##   R3 Sharp: r = 0.8 within 0.05 the same two ways
##   R4 one Undo brings the Medium round back (top face again 40 - 4.8)
##   R5 the three chips are on the 1280 x 720 screen, and left of the panel
##   B1 Add a rib with no bracket on the floor: ONE undo step, an L-bracket + rib: ONE solid, volume = L + 0.5 x 20 x 20 x 3 = +600 mm3 within 2 pct
##   B2 the rib's corner points are in the mesh: (25, 5) and (5, 25) at z = +-1.5 mm
##   B3 Size 30 mm: ONE undo step, +1350 mm3 within 2 pct; Thickness 5 mm: ONE undo step, +2250 mm3 within 2 pct, still one solid
##   B4 pressing the chip again takes the rib off (one step): the volume is the plain L-bracket's (0.1 pct)
##   B5 the T-bracket takes the rib too (one solid, volume larger than the T); the Corner brace says it has its gusset (no change of the part)
##   B6 no key name in the words
## Shots: C:/Temp/claude/s013/round.png (the presets), rib.png (the rib chip + sliders, bracket with a rib)
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s013"
const DIRT := "user://s013_test"
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]
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


func ctl(nm: String) -> Control:
	return root.find_child(nm, true, false) as Control


## the kernel volume (mm3) and bodies of the part on the floor, replayed fresh
func vol() -> float:
	return float(Part.replay(m.S.part).get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


func bodies() -> int:
	return int(Part.replay(m.S.part).get("bodies", 0))


## all mesh vertices of the part, in mm
func verts() -> Array:
	var out := []
	for f in Part.body_faces(m.S.part):
		for v in (f as PackedVector3Array):
			out.append(v * 1000.0)
	return out


func bbox() -> Array:
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for p in verts():
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	return [lo, hi]


## the radius read from the TOP face: the flat top of a 40 mm box rounded by r is 40 - 2 r wide (x extent of the vertices at the top height)
func r_from_top() -> float:
	var bb := bbox()
	var top: float = (bb[1] as Vector3).y
	var xmin := 1e9
	var xmax := -1e9
	for p in verts():
		if p.y >= top - 0.01:
			xmin = minf(xmin, p.x)
			xmax = maxf(xmax, p.x)
	return (((bb[1] as Vector3).x - (bb[0] as Vector3).x) - (xmax - xmin)) * 0.5


## the volume of a box a x b x c with all twelve edges rounded by r (the Minkowski sum of the inner box and a ball of radius r)
func box_vol(a: float, b: float, c: float, r: float) -> float:
	var A := a - 2.0 * r
	var B := b - 2.0 * r
	var C := c - 2.0 * r
	return A * B * C + 2.0 * r * (A * B + B * C + C * A) + PI * r * r * (A + B + C) + 4.0 / 3.0 * PI * r * r * r


## the radius that gives volume v on a 40 x 40 x 20 box (bisection on box_vol, which falls as r grows)
func r_from_vol(v: float) -> float:
	var lo := 0.0
	var hi := 9.99
	for i in 60:
		var mid := (lo + hi) * 0.5
		if box_vol(40.0, 40.0, 20.0, mid) > v:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5


func has_vertex(x: float, y: float, az: float) -> bool:
	for p in verts():
		if absf(p.x - x) <= 0.05 and absf(p.y - y) <= 0.05 and absf(absf(p.z) - az) <= 0.05:
			return true
	return false


func near(a: float, b: float, rel: float) -> bool:
	return absf(a - b) <= rel * absf(b)


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
	pu = m.bld.part
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 35.0
	m.yaw = 30.0
	m._cam()
	await idle(60)

	# R0 the box 40 x 40 x 20
	await click_ctl(ep.make_btns["draw"])
	await drag_pts([scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var bb := bbox()
	var sz: Vector3 = (bb[1] as Vector3) - (bb[0] as Vector3)
	var v0 := vol()
	ok(bodies() == 1 and sz.distance_to(Vector3(40.0, 20.0, 40.0)) <= 0.2, "R0 box drawn and pulled up: %.2f x %.2f x %.2f mm (want 40 x 20 x 40: Y up), volume %.0f mm3" % [sz.x, sz.y, sz.z, v0])

	# the How round row shows once the first round is made: Round the edges (the MAKE button), then the presets swap it
	ok(ctl("easypart_roundpreset_soft") == null or not ctl("easypart_roundpreset_soft").is_visible_in_tree(), "R-1 before any round the presets row is hidden (it would cover the grid)")
	await click_ctl(ep.make_btns["round"])
	await idle(10)
	# R5 the chips are on screen, left of the panel
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var presets := {}
	for k in ["soft", "medium", "sharp"]:
		presets[k] = ctl("easypart_roundpreset_" + k)
	var on_screen := true
	var left_of_panel := true
	for k in presets:
		var c: Control = presets[k]
		if c == null or not c.is_visible_in_tree():
			on_screen = false
			continue
		var r := Rect2(c.global_position, c.size)
		on_screen = on_screen and vp.encloses(r)
		left_of_panel = left_of_panel and r.end.x <= 1280.0 - 318.0
	ok(on_screen and left_of_panel, "R5 Soft / Medium / Sharp are visible chips on the 1280 x 720 screen, left of the panel")
	await shot("round")
	if not on_screen:
		print("s013: %d fail" % (fails + 1))
		quit(1)
		return

	# R1 Soft
	var n0: int = m.undo.size()
	await click_ctl(presets["soft"])
	await idle(10)
	var rt := r_from_top()
	var rv := r_from_vol(vol())
	ok(m.undo.size() == n0 + 1 and bodies() == 1 and absf(rt - 5.0) <= 0.05 and absf(rv - 5.0) <= 0.05, "R1 Soft: one undo step (%d -> %d), r from the top face %.3f, from the volume %.3f (want 5.0 +-0.05), %d solid" % [n0, m.undo.size(), rt, rv, bodies()])
	await shot("soft")

	# R2 Medium after Soft: replaces the round
	var n1: int = m.undo.size()
	await click_ctl(presets["medium"])
	await idle(10)
	rt = r_from_top()
	rv = r_from_vol(vol())
	ok(m.undo.size() == n1 + 1 and bodies() == 1 and absf(rt - 2.4) <= 0.05 and absf(rv - 2.4) <= 0.05, "R2 Medium: one undo step (%d -> %d), r from the top face %.3f, from the volume %.3f (want 2.4 +-0.05)" % [n1, m.undo.size(), rt, rv])
	var fil := 0
	for f in m.S.part["features"]:
		if String(f.get("t", "")) == "fillet":
			fil += 1
	ok(fil == 1, "R2 the Medium round replaced the Soft one (%d round steps in the record)" % fil)

	# R3 Sharp
	var n2: int = m.undo.size()
	await click_ctl(presets["sharp"])
	await idle(10)
	rt = r_from_top()
	rv = r_from_vol(vol())
	ok(m.undo.size() == n2 + 1 and bodies() == 1 and absf(rv - 0.8) <= 0.05, "R3 Sharp: one undo step (%d -> %d), r from the volume %.3f (want 0.8 +-0.05; the top-face edge of a 0.8 mm arc is %.3f: tessellation, not a bar)" % [n2, m.undo.size(), rv, rt])

	# R4 one Undo: the Medium round is back
	m._undo()
	await idle(6)
	rt = r_from_top()
	ok(absf(rt - 2.4) <= 0.05, "R4 one Undo brings the Medium round back: r from the top face %.3f" % rt)

	# B1 Add a rib with no bracket: from the Brackets page. The plain L-bracket first, for its volume (read, then undone)
	var pb := ctl("easypart_chip_parts") as Button
	if pb != null:
		await click_ctl(pb)
	var lib := ctl("easypart_lib_Brackets") as Button
	if lib != null:
		await click_ctl(lib)
	var lchip := ctl("easypart_bracket_L") as Button
	await click_ctl(lchip)
	await idle(6)
	var vL := vol()
	m._undo()
	await idle(6)
	var rib := ctl("easypart_rib") as Button
	var rib_vis := rib != null and rib.is_visible_in_tree() and vp.encloses(Rect2(rib.global_position, rib.size))
	var s_sl := ctl("easypart_rib_size") as HSlider
	var t_sl := ctl("easypart_rib_t") as HSlider
	var sl_vis := s_sl != null and t_sl != null and s_sl.is_visible_in_tree() and t_sl.is_visible_in_tree() and vp.encloses(Rect2(s_sl.global_position, s_sl.size)) and vp.encloses(Rect2(t_sl.global_position, t_sl.size))
	ok(rib_vis and sl_vis and vL > 20000.0, "B0 the Brackets page has the Add a rib chip and the two sliders on screen (L-bracket %.0f mm3)" % vL)
	if not (rib_vis and sl_vis):
		print("s013: %d fail" % (fails + 1))
		quit(1)
		return
	var n3: int = m.undo.size()
	await click_ctl(rib)
	await idle(8)
	var v1 := vol()
	ok(m.undo.size() == n3 + 1 and bodies() == 1 and near(v1 - vL, 600.0, 0.02), "B1 Add a rib (no bracket yet): one undo step (%d -> %d), one solid (%d), +%.1f mm3 (want 600 +-2 pct)" % [n3, m.undo.size(), bodies(), v1 - vL])
	ok(has_vertex(25.0, 5.0, 1.5) and has_vertex(5.0, 25.0, 1.5) and has_vertex(25.0, 5.0, 1.5) and not has_vertex(25.0, 25.0, 1.5), "B2 the rib's corner points are in the mesh: (25, 5) and (5, 25) at z +-1.5 mm, nothing at (25, 25)")
	await idle(4)
	var sc: Node = t_sl
	while sc != null and not (sc is ScrollContainer):
		sc = sc.get_parent()
	var scr_r: Rect2 = (sc as Control).get_global_rect() if sc != null else vp
	var s_in := scr_r.encloses(Rect2(s_sl.global_position, s_sl.size)) or scr_r.encloses(Rect2(s_sl.global_position, Vector2(s_sl.size.x, 1.0)))
	var t_in := scr_r.encloses(Rect2(t_sl.global_position, t_sl.size))
	ok(t_in, "B1 after Add a rib the Rib thickness slider is inside the panel's visible area (scrolled into view): slider %s, panel %s" % [str(Rect2(t_sl.global_position, t_sl.size)), str(scr_r)])
	await shot("rib")

	# B3 sliders: size 30, thickness 5
	var n4: int = m.undo.size()
	s_sl.value = 30.0
	await idle(6)
	var v2 := vol()
	ok(m.undo.size() == n4 + 1 and bodies() == 1 and near(v2 - vL, 1350.0, 0.02), "B3 Size 30: one undo step (%d -> %d), one solid, +%.1f mm3 (want 1350 +-2 pct)" % [n4, m.undo.size(), v2 - vL])
	var n5: int = m.undo.size()
	t_sl.value = 5.0
	await idle(6)
	var v3 := vol()
	ok(m.undo.size() == n5 + 1 and bodies() == 1 and near(v3 - vL, 2250.0, 0.02), "B3 Thickness 5: one undo step (%d -> %d), one solid, +%.1f mm3 (want 2250 +-2 pct)" % [n5, m.undo.size(), v3 - vL])
	await shot("rib_big")

	# B4 the chip again takes it off
	var n6: int = m.undo.size()
	await click_ctl(rib)
	await idle(8)
	ok(m.undo.size() == n6 + 1 and near(vol(), vL, 0.001) and bodies() == 1, "B4 the chip again takes the rib off: one undo step, volume %.1f vs the L-bracket's %.1f" % [vol(), vL])

	# B5 T-bracket takes the rib; the Corner brace has a gusset already
	await click_ctl(ctl("easypart_bracket_T") as Button)
	await idle(6)
	var vT := vol()
	t_sl.value = 3.0
	s_sl.value = 20.0
	await idle(3)
	await click_ctl(rib)
	await idle(8)
	var vT2 := vol()
	ok(bodies() == 1 and near(vT2 - vT, 600.0, 0.02), "B5 the T-bracket takes the rib: one solid, +%.1f mm3 (want 600 +-2 pct)" % (vT2 - vT))
	await click_ctl(ctl("easypart_bracket_corner") as Button)
	await idle(8)
	var vC := vol()
	var corner_has_rib := false
	for f in m.S.part["features"]:
		if bool(f.get("rib", false)):
			corner_has_rib = true
	ok(bodies() == 1 and not corner_has_rib and vC > 38000.0 and vC < 38700.0, "B5 the Corner brace (gusset already) carries no rib: volume %.0f (38327 expected), rib steps %s" % [vC, str(corner_has_rib)])

	# B6 words
	var hit := []
	var texts := [ep.hint_l.text, ep.status_l.text, rib.text, String(ep.msg)]
	for k in ["soft", "medium", "sharp"]:
		texts.append((presets[k] as Button).text)
	for t in texts:
		for w in BAD_WORDS:
			if String(t).to_lower().contains(w):
				hit.append("%s in [%s]" % [w, t])
	ok(hit.is_empty(), "B6 no key name in the chips, hint or status %s" % str(hit))
	print("s013: %d fail" % fails)
	quit(1 if fails > 0 else 0)
