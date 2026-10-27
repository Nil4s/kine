extends SceneTree
## godot --path . --position 4000,4000 -s tests/peasy2_test.gd     (EASY PART, the four new big buttons: scripts/easy_part.gd on the Part record; needs the CAD DLL)
## Bars (real clicks and drags through root.push_input at 1280 x 720, from Easy home: a 3D BUILDING project, Part, Easy; no keyboard):
##   1 CURVY LINE   a drag of a loop on the grid: ONE undo step, a closed spline sketch; Pull it up makes it a solid (volume grows, no failed step)
##   2 BLEND        two drawn shapes, then Blend two shapes: ONE undo step, a loft step with no error, the solid grows; the newer shape sits on an offset plane
##   3 CUT IN TWO   Cut in two: ONE undo step, two bodies, volume kept (within 1 %); the drag slider moves the cut: the split's offset changes,
##                  still two bodies, ONE undo step for the drag
##   4 COLOUR       Colour, then Red: one appear step per body, ONE undo step, the look is red; Glass: opacity 40 %, ONE undo step
##   5 WORDS        no key name in any visible Easy text (labels, tooltips, hints, status) with the MAKE row, the colour row and the shape row open
##   6 LAYOUT       at 1280 x 720 the MAKE row, the panel, the hint, the shape and colour rows, the status overlap nothing inside the clear view
## Shots: C:/Temp/claude/peasy2/shot.png (the Easy column), shot_colour.png (the colour row open)
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/peasy2"
const DIRT := "user://peasy2_test"


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


## a real press, a drag through every point, a release (the grid draws, the curve samples on the way)
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


## a real drag of the slider's knob to value v (held with the left button, 24 mouse steps)
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
		print("FAIL: no KineCAD DLL, the four buttons cannot run")
		quit(1)
		return
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep
	ok(pu.easy and ep.make_box.visible and ep.make_btns.size() == 12, "0 Easy home: Part on Easy's screen with twelve big buttons (%d; Repeat it + Stick together joined the ten in 729dbc23)" % ep.make_btns.size())
	# 1 CURVY LINE
	var ub: int = m.undo.size()
	var ns := count_kind(m.S.part, "sketch")
	await click_ctl(ep.make_btns["curve"])
	var c0 := free_at(0.3, 0.45)
	var loop := []
	for i in 25:
		var a := TAU * float(i) / 24.0
		loop.append(c0 + Vector2(cos(a), sin(a)) * 60.0)
	loop[24] = loop[0]
	await drag_pts(loop)
	var sk := last_of(m.S.part, "sketch")
	var ent: Dictionary = (sk.get("ents", [{}]) as Array)[0] if not sk.is_empty() else {}
	ok(m.undo.size() == ub + 1 and count_kind(m.S.part, "sketch") == ns + 1 and String(ent.get("k", "")) == "bspline" and bool(ent.get("closed", false)),
		"1 Curvy line: a closed spline sketch from one drag, ONE undo step (%d -> %d) [%s]" % [ub, m.undo.size(), ep.hint_l.text])
	var vol0: float = float(pu.res.get("volume", 0.0))
	await click_ctl(ep.make_btns["pull"])
	var r1: Dictionary = pu.res
	ok(float(r1.get("volume", 0.0)) > vol0 and (r1.get("errors", {}) as Dictionary).is_empty() and int(r1.get("bodies", 0)) >= 1,
		"1 Pull it up on the curve: volume %.1f -> %.1f cm3, no failed step" % [vol0 * 1e6, float(r1.get("volume", 0.0)) * 1e6])
	# 2 BLEND
	await click_ctl(ep.make_btns["draw"])
	var a0 := free_at(0.12, 0.2)
	await drag_pts([a0, a0 + Vector2(45, 35), a0 + Vector2(90, 70)])
	await click_ctl(ep.make_btns["draw"])
	var b0 := free_at(0.12, 0.45)
	await drag_pts([b0, b0 + Vector2(30, 30), b0 + Vector2(60, 60)])
	await click_ctl(ep.make_btns["draw"])
	var ub2: int = m.undo.size()
	var vol_b := float(pu.res.get("volume", 0.0))
	await click_ctl(ep.make_btns["blend"])
	var r2: Dictionary = pu.res
	var lf := last_of(m.S.part, "loft")
	var sks: Array = []
	for f in m.S.part["features"]:
		if f["t"] == "sketch":
			sks.append(f)
	var newer_planed: bool = sks.size() >= 2 and String(sks[sks.size() - 1]["plane"]) != "front"
	ok(not lf.is_empty() and m.undo.size() == ub2 + 1 and (r2.get("errors", {}) as Dictionary).is_empty() and float(r2.get("volume", 0.0)) > vol_b and newer_planed,
		"2 Blend two shapes: a loft, the newer shape on an offset plane, volume %.1f -> %.1f cm3, no failed step, ONE undo step (%d -> %d) [%s]" % [vol_b * 1e6, float(r2.get("volume", 0.0)) * 1e6, ub2, m.undo.size(), ep.hint_l.text])
	# 3 CUT IN TWO
	var ub3: int = m.undo.size()
	var vol_c := float(pu.res.get("volume", 0.0))
	await click_ctl(ep.make_btns["split"])
	var r3: Dictionary = pu.res
	var sp := last_of(m.S.part, "split")
	ok(not sp.is_empty() and int(r3.get("bodies", 0)) == 2 and m.undo.size() == ub3 + 1 and absf(float(r3.get("volume", 0.0)) - vol_c) < 0.01 * vol_c,
		"3 Cut in two: two bodies, volume %.2f -> %.2f cm3, ONE undo step (%d -> %d) [%s]" % [vol_c * 1e6, float(r3.get("volume", 0.0)) * 1e6, ub3, m.undo.size(), ep.hint_l.text])
	var at0 := float(sp.get("at", 0.0))
	var row: Dictionary = {}
	for rw in ep.rows:
		if rw["kind"] == "tweak":
			row = rw
	var sl: HSlider = row.get("slider", null)
	var ub4: int = m.undo.size()
	if sl != null:
		await drag_slider(sl, sl.value + (sl.max_value - sl.min_value) * 0.25)
	var sp2 := last_of(m.S.part, "split")
	var r4: Dictionary = pu.res
	ok(sl != null and absf(float(sp2.get("at", 0.0)) - at0) > 5.0 and int(r4.get("bodies", 0)) == 2 and m.undo.size() == ub4 + 1,
		"3 The drag slider moves the cut: %.0f -> %.0f mm, still two bodies, ONE undo step (%d -> %d)" % [at0, float(sp2.get("at", 0.0)), ub4, m.undo.size()])
	# 4 COLOUR
	await click_ctl(ep.make_btns["colour"])
	ok(ep.colour_box.visible, "4 Colour: the colour row opens")
	var nb := int(pu.res.get("bodies", 0))
	var ub5: int = m.undo.size()
	var nap := count_kind(m.S.part, "appear")
	await click_ctl(ep.colour_box.find_child("easypart_colour_red", true, false))
	var lk := Part.look_at(pu.res.get("body_looks", []), 0)
	var c_ok: bool = (lk["c"] as Color).r > (lk["c"] as Color).g + 0.3
	ok(count_kind(m.S.part, "appear") == nap + nb and m.undo.size() == ub5 + 1 and c_ok,
		"4 Red: one appear step per body (%d), the look is red, ONE undo step (%d -> %d)" % [nb, ub5, m.undo.size()])
	await click_ctl(ep.make_btns["colour"])
	var ub6: int = m.undo.size()
	await click_ctl(ep.colour_box.find_child("easypart_colour_glass", true, false))
	var alpha_ok := true
	for i in int(pu.res.get("bodies", 0)):
		alpha_ok = alpha_ok and absf(float(Part.look_at(pu.res.get("body_looks", []), i)["alpha"]) - 0.4) < 0.01
	ok(alpha_ok and m.undo.size() == ub6 + 1, "4 Glass: opacity 40 pct on every body, ONE undo step (%d -> %d)" % [ub6, m.undo.size()])
	# 5 WORDS, with the colour row and the shape row open
	await click_ctl(ep.make_btns["colour"])
	var all := []
	for n in [ep.bar, ep.make_box, ep.panel, ep.hint, ep.colour_box, ep.status]:
		texts(n, all)
	await click_ctl(ep.make_btns["colour"])
	await click_ctl(ep.make_btns["draw"])
	texts(ep.shape_box, all)
	await click_ctl(ep.make_btns["draw"])
	var bad_words := ["ctrl", "control", "shift", "alt", "esc", "escape", "enter", "return", "tab", "delete", "backspace", "space", "spacebar", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "key", "keys", "keyboard", "hotkey"]
	var hit := []
	var seen := 0
	for t in all:
		if String(t).strip_edges() != "":
			seen += 1
		for tok in String(t).to_lower().split(" ", false):
			var w := String(tok).strip_edges().trim_suffix(".").trim_suffix(",").trim_suffix(":").trim_suffix("?")
			if w in bad_words or w.contains("+"):
				hit.append("%s in '%s'" % [w, t])
	ok(hit.is_empty() and seen > 20, "5 no key names in %d Easy texts %s" % [seen, hit])
	# 6 LAYOUT
	await click_ctl(ep.make_btns["colour"])
	var lay := overlaps([ep.make_box, ep.panel, ep.hint, ep.colour_box, ep.status])
	await shot("shot_colour")
	await click_ctl(ep.make_btns["colour"])
	var lay2 := overlaps([ep.make_box, ep.panel, ep.hint, ep.status])
	ok(lay.is_empty() and lay2.is_empty(), "6 layout at 1280 x 720, with the colour row and without it: %s %s" % [str(lay), str(lay2)])
	await shot("shot")
	print("peasy2: %d fail" % fails)
	quit(1 if fails > 0 else 0)
