extends SceneTree
## godot --path . --position 4000,4000 -s tests/peasy3_test.gd     (EASY PART, two more big buttons: Repeat it and Stick together; scripts/easy_part.gd on the Part record; needs the CAD DLL)
## Bars (real clicks and drags through root.push_input at 1280 x 720, from Easy home: a 3D BUILDING project, Part, Easy; no keyboard):
##   1 REPEAT IT   refused in plain words with no solid; then a shape pulled up, Repeat it: ONE undo step, a Part pattern step (row, 3 copies),
##                 the volume is 3 times the shape (within 3 pct), no failed step; the How many slider drag to 5: ONE undo step, 5 copies
##   2 RING        Ring: ONE undo step, the pattern turns circular round the up axis (Y), no failed step; the Gap slider is off in Ring
##   3 STICK       Cut in two (two pieces), Stick together, click each piece in the view, Keep the overlap: refused in words, no undo step;
##                 then Join: ONE undo step, one solid left, a combine step; with one piece left Stick together is refused in words
##   4 WORDS       no key name in any visible Easy text (labels, tooltips, hints, status) with the MAKE row, the repeat row and the stick row open
##   5 LAYOUT      at 1280 x 720 all twelve MAKE buttons are inside the window, and the MAKE row, panel, hint, status and repeat row overlap nothing
## Shots: C:/Temp/claude/peasy3/shot.png (the Easy column with the repeat row open), shot_stick.png (two pieces picked)
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
	if not Part.available():
		print("FAIL: no KineCAD DLL, the new buttons cannot run")
		quit(1)
		return
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep
	ok(pu.easy and ep.make_box.visible and ep.make_btns.size() == 12, "0 Easy home: Part on Easy with twelve big buttons (%d)" % ep.make_btns.size())
	# 1 REPEAT IT: refused with no solid
	m.S.part = {}   # an empty part (the building project's start has a solid already): nothing to repeat yet
	pu.upto = -1
	pu.sync()
	await click_ctl(ep.make_btns["draw"])
	var a0 := free_at(0.2, 0.25)
	await drag_pts([a0, a0 + Vector2(45, 35), a0 + Vector2(90, 70)])
	await click_ctl(ep.make_btns["draw"])
	var ub1: int = m.undo.size()
	await click_ctl(ep.make_btns["repeat"])
	ok(count_kind(m.S.part, "pattern") == 0 and m.undo.size() == ub1 and ep.hint_l.text.contains("solid"),
		"1 Repeat it with no solid: refused in words, no undo step (%d -> %d) [%s]" % [ub1, m.undo.size(), ep.hint_l.text])
	await click_ctl(ep.make_btns["pull"])
	var vol0: float = float(pu.res.get("volume", 0.0))
	ok(vol0 > 0.0 and int(pu.res.get("bodies", 0)) == 1, "1 a shape pulled up: one solid, volume %.3f cm3" % (vol0 * 1e6))
	var ub2: int = m.undo.size()
	await click_ctl(ep.make_btns["repeat"])
	var pt := last_of(m.S.part, "pattern")
	var r1: Dictionary = pu.res
	ok(not pt.is_empty() and String(pt.get("kind", "")) == "linear" and int(pt.get("count", 0)) == 3 and m.undo.size() == ub2 + 1
		and (r1.get("errors", {}) as Dictionary).is_empty() and absf(float(r1.get("volume", 0.0)) - 3.0 * vol0) < 0.03 * 3.0 * vol0,
		"1 Repeat it: a row of 3, volume %.3f -> %.3f cm3 (3 times), no failed step, ONE undo step (%d -> %d)" % [vol0 * 1e6, float(r1.get("volume", 0.0)) * 1e6, ub2, m.undo.size()])
	ok(ep.repeat_box.visible, "1 the Repeat it row opens under the MAKE row")
	var row_count: Dictionary = {}
	var row_gap: Dictionary = {}
	for rw in ep.rep_rows:
		if rw["key"] == "count":
			row_count = rw
		else:
			row_gap = rw
	var ub3: int = m.undo.size()
	await drag_slider(row_count["slider"], 5.0)
	var pt2 := last_of(m.S.part, "pattern")
	var r2: Dictionary = pu.res
	ok(int(pt2.get("count", 0)) == 5 and m.undo.size() == ub3 + 1 and (r2.get("errors", {}) as Dictionary).is_empty() and float(r2.get("volume", 0.0)) > 4.9 * vol0,
		"1 How many slider drag to 5: 5 copies, ONE undo step (%d -> %d), volume %.3f cm3" % [ub3, m.undo.size(), float(r2.get("volume", 0.0)) * 1e6])
	await idle(2)
	ok(int(r2.get("bodies", 0)) != 1 or ep.status_l.text.begins_with("5 pieces that do not touch"),
		"1 five joined copies with a gap are not called \"one solid, no gaps\": [%s]" % ep.status_l.text)
	# 2 RING
	var ub4: int = m.undo.size()
	await click_ctl(ep.rep_btns["ring"])
	var pt3 := last_of(m.S.part, "pattern")
	var r3: Dictionary = pu.res
	ok(String(pt3.get("kind", "")) == "circular" and String(pt3.get("axis", "")) == "y" and float(pt3.get("deg", 0.0)) == 360.0 and m.undo.size() == ub4 + 1 and (r3.get("errors", {}) as Dictionary).is_empty(),
		"2 Ring: a full turn round the up axis (Y), no failed step, ONE undo step (%d -> %d)" % [ub4, m.undo.size()])
	ok(not (row_gap["slider"] as HSlider).editable, "2 the Gap slider is off in Ring")
	await click_ctl(ep.rep_btns["row"])
	ok(String(last_of(m.S.part, "pattern").get("kind", "")) == "linear", "2 Row again: the copies go back in a straight line")
	# 3 STICK TOGETHER: two pieces from Cut in two
	# two apart pieces: a new part, two boxes drawn and pulled up (the ring above sent copies far off)
	m.S.part = {}
	pu.upto = -1
	pu.sync()
	await click_ctl(ep.make_btns["draw"])
	var pa := free_at(0.22, 0.3)
	await drag_pts([pa, pa + Vector2(40, 40), pa + Vector2(80, 80)])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await click_ctl(ep.make_btns["draw"])
	var pb := free_at(0.6, 0.3)
	await drag_pts([pb, pb + Vector2(40, 40), pb + Vector2(80, 80)])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await click_ctl(ep.make_btns["split"])   # the two boxes fuse into one body (one solid): Cut in two gives two pieces, one box each
	var nb := int(pu.res.get("bodies", 0))
	ok(nb == 2, "3 Cut in two between the two boxes: two pieces (%d) [%s]" % [nb, ep.hint_l.text])
	var ub5: int = m.undo.size()
	await click_ctl(ep.make_btns["stick"])
	ok(ep.armed == "stick" and not ep.stick_box.visible, "3 Stick together: armed, the three buttons wait for two picks [%s]" % ep.hint_l.text)
	await click_at(body_at(0))
	await click_at(body_at(1))
	ok(ep.stick_picks.size() == 2 and ep.stick_box.visible, "3 two clicks in the view pick two pieces, the three buttons show [%s]" % ep.hint_l.text)
	await shot("shot_stick")
	await click_ctl(ep.stick_btns["intersect"])
	ok(m.undo.size() == ub5 and int(pu.res.get("bodies", 0)) == 2 and count_kind(m.S.part, "combine") == 0 and ep.hint_l.text.contains("cannot"),
		"3 Keep the overlap on two apart pieces: refused in words, no undo step (%d -> %d) [%s]" % [ub5, m.undo.size(), ep.hint_l.text])
	await click_ctl(ep.make_btns["stick"])
	await click_at(body_at(0))
	await click_at(body_at(1))
	var ub6: int = m.undo.size()
	await click_ctl(ep.stick_btns["join"])
	var cb := last_of(m.S.part, "combine")
	ok(not cb.is_empty() and String(cb.get("op", "")) == "join" and int(pu.res.get("bodies", 0)) == 1 and m.undo.size() == ub6 + 1,
		"3 Join: one solid, a combine step, ONE undo step (%d -> %d) [%s]" % [ub6, m.undo.size(), ep.hint_l.text])
	await click_ctl(ep.make_btns["stick"])
	ok(ep.armed != "stick" and ep.hint_l.text.contains("solid"), "3 one solid left: Stick together refused in words [%s]" % ep.hint_l.text)
	# 4 WORDS, with the repeat row and the stick row open
	var all := []
	await click_ctl(ep.make_btns["repeat"])
	for n in [ep.bar, ep.make_box, ep.panel, ep.hint, ep.repeat_box, ep.status]:
		texts(n, all)
	for b in ep.stick_btns.values():
		all.append((b as Button).text)
		all.append((b as Button).tooltip_text)
	await click_ctl(ep.make_btns["stick"])
	texts(ep.make_box, all)
	await click_ctl(ep.make_btns["stick"])
	var bad_words := ["ctrl", "control", "shift", "alt", "esc", "escape", "enter", "return", "tab", "delete", "backspace", "space", "spacebar", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "key", "keys", "keyboard", "hotkey"]
	var hit := []
	var seen := 0
	for t in all:
		if String(t).strip_edges() != "":
			seen += 1
		for tok in String(t).to_lower().split(" ", false):
			var w := String(tok).strip_edges().trim_suffix(".").trim_suffix(",").trim_suffix(":").trim_suffix("?")
			if w in bad_words or w.contains("+"):
				hit.append("%s in %s" % [w, t])
	ok(hit.is_empty() and seen > 30, "4 no key names in %d Easy texts %s" % [seen, hit])
	# 5 LAYOUT
	var btn_bad := []
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
	for k in ep.make_btns:
		var b: Control = ep.make_btns[k]
		if not vp.encloses(Rect2(b.global_position, b.size)):
			btn_bad.append("%s outside the window" % k)
	var lay := overlaps([ep.make_box, ep.panel, ep.hint, ep.status])
	await click_ctl(ep.make_btns["repeat"])
	var lay2 := overlaps([ep.make_box, ep.panel, ep.hint, ep.repeat_box, ep.status])
	var lay3 := overlaps([ep.make_box, ep.panel, ep.hint, ep.stick_box, ep.status])
	await shot("shot")
	ok(btn_bad.is_empty() and lay.is_empty() and lay2.is_empty() and lay3.is_empty(), "5 layout at 1280 x 720: all twelve buttons in the window %s, no overlap %s %s" % [str(btn_bad), str(lay), str(lay2)])
	print("peasy3: %d fail" % fails)
	quit(1 if fails > 0 else 0)
