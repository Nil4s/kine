extends "res://scripts/easy_part_base.gd"
## EASY PART LAYOUT: where everything sits on the screen. The button and chip makers, the panel and the boxes placed each frame (layout,
## _chrome_sync), the camera framing (it eases, never jumps), the amber drag dots, the floor grid and the upright plane, the outline of a
## shape being drawn, and the face of a solid under the pointer.

func _big_btn(nm: String, txt: String, tip: String, f: Callable) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = txt
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(110, 44)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(f)
	return b


func _colour_btn(key: String, txt: String, c: Color) -> Button:
	var b := Button.new()
	b.name = "easypart_colour_" + key
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(84, 44)   # 84 (was 92): eight chips with Wood still end left of the panel at 1280 x 720
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", Color(0.08, 0.08, 0.1))
	var st := StyleBoxFlat.new()
	st.bg_color = c
	st.set_corner_radius_all(8)
	for sn in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(sn, st)
	return b


func _style(c: Color, r: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(r)
	s.set_content_margin_all(margin)
	return s


func _pill(nm: String, fs: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = nm
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.visible = false
	p.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 10))
	var l := Label.new()
	l.name = nm + "_text"
	l.add_theme_font_size_override("font_size", fs)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


func _bar_btn(t: String, tip: String, f: Callable) -> Button:
	var b := Button.new()
	b.name = "easypart_btn_" + t.to_lower()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(96, m.TOP_H - 12)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(func(): m._step_hint = t; f.call())
	return b


## FMEASURE: the part's size in cm, W x D x H (wide, deep, high), a small plain label under the part's front bottom edge.
## Shown while a solid is made (Easy Part only); the numbers are the replayed box (metres -> cm, one decimal).
func _size_sync() -> void:
	var res: Dictionary = pu.res if pu != null else {}
	var bb: AABB = res.get("aabb", AABB())
	var solid := active() and int(res.get("bodies", 0)) > 0 and bb.size.x > 0.0 and bb.size.y > 0.0 and bb.size.z > 0.0
	size_l.visible = solid
	if not solid or m.cam == null:
		return
	var w := snappedf(bb.size.x * 100.0, 0.1)
	var d := snappedf(bb.size.z * 100.0, 0.1)
	var h := snappedf(bb.size.y * 100.0, 0.1)
	size_l.text = "Size: %s x %s x %s cm (wide x deep x high), %s" % [_cm1(w), _cm1(d), _cm1(h), _print_words()]
	var front := Vector3(bb.get_center().x, bb.position.y, bb.end.z)
	if m.cam.is_position_behind(front):
		size_l.visible = false
		return
	var p: Vector2 = m.cam.unproject_position(front)
	var sz := size_l.get_combined_minimum_size()
	size_l.size = sz
	# FMOBILE: the label stays on the window (a part low on a short window pushed it off the bottom) and hides rather than sit on a box or panel
	var vp := get_viewport().get_visible_rect()
	var pos := Vector2(clampf(p.x - sz.x * 0.5, 4.0, vp.end.x - sz.x - 4.0), minf(p.y + 12.0, vp.end.y - sz.y - 4.0))
	size_l.position = pos
	var r := Rect2(size_l.get_global_position(), sz)
	for bx in [panel, repeat_box, stick_box, colour_box, hint, status]:
		var c := bx as Control
		if c != null and c.is_visible_in_tree() and r.intersects(c.get_global_rect()):
			size_l.visible = false
			return


## EFRAME: after a step that changes the part's box a lot, the camera eases so the box fills FRAME_FILL of the free view.
## Never while the mouse is held (a drag, an orbit, a pan) and never for a small edit: the reference box moves only when framed.
func _frame_step() -> void:
	if m.cam == null or pu.res.is_empty():
		_frame_grid()   # GRIDFRAME: an empty part has no box: its floor grid is framed instead (once per visit)
		if not _ease.is_empty():
			_ease_step()
		return
	var held := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or not _drag.is_empty() or not _draft.is_empty()
	if held:
		_ease = {}   # the user has the view: the ease stops where it is
		return
	if not _ease.is_empty():
		_ease_step()
		return
	var bb: AABB = pu.res.get("aabb", AABB())
	var len := bb.size.length()
	if not _fr_has:
		_fr_ref = bb
		_fr_has = true
		return
	var ref_len := _fr_ref.size.length()
	var lk := str(repeat_box.visible)   # EPANELVIEW: a Repeat it box opening or closing changes the free view: frame again (not Stick together: its picks need a still view)
	if lk != _fr_lk:
		_fr_lk = lk
		_fr_ref = AABB()
		ref_len = 0.0
	if len < 1e-4:
		_fr_ref = bb   # an empty part: nothing to frame yet
		_frame_grid()  # GRIDFRAME: its floor grid is framed instead (once per visit)
		if not _ease.is_empty():
			_ease_step()
		return
	# FREEWALK D2: a step that keeps the box size (Cut a hole) can still leave the solid off the screen: then frame it again
	var off := bb != _off_tried and not _centre_free(bb)   # one try per box: a view that cannot hold it is not chased every frame
	if off:
		_off_tried = bb
	if not off and ref_len >= 1e-4 and absf(len - ref_len) <= FRAME_CHANGE * ref_len:
		return
	_fr_ref = bb
	var pose := _hinge_pose(bb) if _tpl() == "hinge" else _frame_pose(bb)   # p067framefix: a hinge fills its clear-view share, not the free view
	if pose.is_empty():
		return
	_ease = {"t0": m.target, "d0": float(m.dist), "t1": pose[0], "d1": pose[1], "s": 0.0}


## the free view: the clear view minus the MAKE row above and the side panel at the right, minus the status line at the bottom
func free_rect() -> Rect2:
	var boxes := [hint, hole_box, split_box, round_box, shape_box, colour_box, repeat_box, stick_box]   # the words and the chip rows under the MAKE row: the part sits below them
	var top := _free_top(boxes)                                                              # (ewalk4: the Through / Hollow inside chips covered the mug's rim)
	# FSHELF: the Repeat row sits at the left under the words; open, its bottom left the free view under 0 px high (no framing, the copies
	# of a row stayed off screen). When that happens the row does not push the view down (it floats over the left of the grid)
	if _cl.end.y - 70.0 - top < 120.0:
		top = _free_top(boxes.filter(func(c): return c != repeat_box))
	var x0 := _cl.position.x + 12.0
	var x1 := _cl.end.x - PW - 16.0
	# EPANELVIEW: an open Repeat it box at the lower left takes its columns out of the free view (the part is framed to its right)
	if repeat_box.visible and repeat_box.position.y < _cl.end.y - 70.0 and repeat_box.position.y + repeat_box.size.y > top:
		x0 = maxf(x0, repeat_box.position.x + repeat_box.size.x + 8.0)
	return Rect2(x0, top, x1 - x0, _cl.end.y - 70.0 - top)


## the top edge of the free view: under the MAKE row and under each visible panel in boxes
func _free_top(boxes: Array) -> float:
	var top := _cl.position.y + 4.0 + MAKE_H + 8.0
	for c in boxes:
		if c != null and (c as Control).visible:
			top = maxf(top, (c as Control).get_global_rect().end.y + 8.0)
	return top


## FBOLT: a Draw shape press finishes a camera ease that is still running, so the view is where it lands before the next press
func _ease_end() -> void:
	if _ease.is_empty() or m.cam == null:
		return
	m.target = _ease["t1"]
	m.dist = float(_ease["d1"])
	m._cam()
	_ease = {}


## the ease in progress: one step per frame toward its end pose (smoothstep), then it is cleared
func _ease_step() -> void:
	_ease["s"] = minf(float(_ease["s"]) + get_process_delta_time(), FRAME_EASE)
	var k: float = float(_ease["s"]) / FRAME_EASE
	k = k * k * (3.0 - 2.0 * k)
	m.target = (_ease["t0"] as Vector3).lerp(_ease["t1"] as Vector3, k)
	m.dist = lerpf(float(_ease["d0"]), float(_ease["d1"]), k)
	m._cam()
	if float(_ease["s"]) >= FRAME_EASE:
		_ease = {}


## GRIDFRAME (Nick 2026-10-28, Fusion 360 style): an empty Easy Part opens with its 1 m floor grid centred in the free view and filling most of it.
## Framed again when the free view itself changes (the lens shift follows it), but only while the user has not moved the camera since
## the last automatic framing. The view angle is kept (the 3/4 entry view).
const GRID_FILL := 0.85          # the grid's bigger side fills this share of the free view
var _grid_framed := false
var _grid_fr := Rect2()          # the free view the grid was last framed in
var _grid_cam: Array = []        # the camera [target, dist, yaw, pitch] the last automatic framing left
func _frame_grid() -> void:
	if _ease.size() > 0 or m.cam == null:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or not _drag.is_empty() or not _draft.is_empty():
		return   # the user has the mouse (a drag, a sketch, an orbit): the view stays where it is
	if m._view_tw != null and m._view_tw.is_valid():
		return   # the view tween that the card click started still moves the look-at point: framed after it ends
	var fr := free_rect()
	if fr.size.x < 40.0 or fr.size.y < 40.0:
		return
	if _grid_framed:
		if fr.is_equal_approx(_grid_fr) or not _grid_auto():
			return   # framed already, or the user has the view
		if armed != "":
			return   # a tool is armed (Draw, Curvy, Pull ...): the free view changes as its panel opens, and the view must not move under the clicks that follow
	var e := 10 * 50.0 * Part.MM   # the floor grid's half side (scripts: _floor_sync, n = 10 lines of 5 cm)
	var pose := _grid_pose(AABB(Vector3(-e, 0.0, -e), Vector3(2.0 * e, 0.0, 2.0 * e)), GRID_FILL)
	if pose.is_empty():
		return   # no pose yet: try again next frame
	_grid_framed = true
	_grid_fr = fr
	_grid_cam = [pose[0], pose[1], float(m.yaw), float(m.pitch)]
	_ease = {"t0": m.target, "d0": float(m.dist), "t1": pose[0], "d1": pose[1], "s": 0.0}


## true while the camera is still where the last automatic grid framing left it (the user has not orbited, panned or zoomed)
func _grid_auto() -> bool:
	if _grid_cam.is_empty():
		return false
	return m.target.is_equal_approx(_grid_cam[0]) and absf(float(m.dist) - float(_grid_cam[1])) < 1e-4 and absf(float(m.yaw) - float(_grid_cam[2])) < 1e-3 and absf(float(m.pitch) - float(_grid_cam[3])) < 1e-3


## GRIDFRAME, closed loop: the look-at point and distance that put the grid's screen box at the free view's centre and GRID_FILL of it.
## Each step measures the box on screen (the camera's lens shift is not trusted) and moves the look-at point by the pixel error
## (one pixel = 2 d tan(fov/2) / view height world units, the view height is kept). Returns [t, d], or [] when no pose is found.
func _grid_pose(bb: AABB, fill: float) -> Array:
	var fr := free_rect()
	if fr.size.x < 40.0 or fr.size.y < 40.0:
		return []
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var t0: Vector3 = m.target
	var d0 := float(m.dist)
	var t := bb.get_center()
	var d := d0
	var ok_pose := false
	for it in 60:
		var b := Basis.from_euler(Vector3(deg_to_rad(float(m.pitch)), deg_to_rad(float(m.yaw)), 0))
		var r := _box_at(bb, t, d)
		if r.size == Vector2.ZERO:
			d *= 1.5   # a corner behind the lens: back off
			continue
		var wpp := 2.0 * d * tan(deg_to_rad(m.cam.fov * 0.5)) / vs.y
		var need := maxf(r.size.x / fr.size.x, r.size.y / fr.size.y) / fill
		var ex := fr.get_center().x - r.get_center().x
		var ey := fr.get_center().y - r.get_center().y
		if absf(ex) < 1.0 and absf(ey) < 1.0 and absf(need - 1.0) < 0.01:
			ok_pose = true
			break
		t += b.x * (-ex) * wpp + b.y * ey * wpp
		if absf(need - 1.0) >= 0.01:
			d = clampf(d * clampf(need, 0.5, 2.0), 0.02, 40.0)
	m.target = t0
	m.dist = d0
	m._cam()
	if not ok_pose:
		return []
	return [t, d]


## true when the box's middle projects on the screen (and is in front of the lens): the solid can be seen and clicked
func _centre_free(bb: AABB) -> bool:
	var c := bb.get_center()
	if m.cam.is_position_behind(c):
		return false
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var p: Vector2 = m.cam.unproject_position(c)
	return p.x >= 0.0 and p.y >= 0.0 and p.x <= vs.x and p.y <= vs.y


## The look-at point is the box's middle, moved so the box sits in the free view's middle (as Easy's frame() moves it); the distance
## is found by a few steps: the box's size on screen goes as 1 / distance, so each step scales the distance by the size ratio.
## the look-at point and distance that put the box (its eight corners) at FRAME_FILL of the free view; the view angle is kept.
## (fill: the share of the free view the box takes; FRAME_FILL unless an empty part's grid tile asks for more)
func _frame_pose(bb: AABB, fill := FRAME_FILL) -> Array:
	var fr := free_rect()
	if fr.size.x < 40.0 or fr.size.y < 40.0:
		return []
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var t0: Vector3 = m.target
	var d0 := float(m.dist)
	var d := d0
	var t := bb.get_center()
	for it in 40:
		var b := Basis.from_euler(Vector3(deg_to_rad(float(m.pitch)), deg_to_rad(float(m.yaw)), 0))
		var span := 2.0 * d * tan(deg_to_rad(m.cam.fov * 0.5)) * vs.x / vs.y
		var tt := bb.get_center() + b.x * (span * (vs.x * 0.5 - fr.get_center().x) / vs.x) + b.y * (span * (fr.get_center().y - vs.y * 0.5) / vs.y)
		var r := _box_at(bb, tt, d)
		if r.size == Vector2.ZERO:
			d *= 1.5   # a corner behind the lens: back off
			continue
		t = tt
		var need := maxf(r.size.x / fr.size.x, r.size.y / fr.size.y) / fill
		if absf(need - 1.0) < 0.01:
			break
		d = clampf(d * clampf(need, 0.5, 2.0), 0.02, 40.0)
	m.target = t0
	m.dist = d0
	m._cam()
	return [t, d]


## the box's screen rectangle seen from look-at point t at distance d (the camera is put back by the caller).
## Zero size when a corner is behind the lens.
func _box_at(bb: AABB, t: Vector3, d: float) -> Rect2:
	m.target = t
	m.dist = d
	m._cam()
	var r := Rect2()
	var first := true
	for i in 8:
		var q := bb.get_endpoint(i)
		if m.cam.is_position_behind(q):
			return Rect2()
		var sp: Vector2 = m.cam.unproject_position(q)
		r = Rect2(sp, Vector2.ZERO) if first else r.expand(sp)
		first = false
	return r


func _chrome_sync() -> void:
	var t := _tpl()
	var rec := _rec()
	_steps_sync()   # NSTEPLIST
	title_l.text = "Part: %s" % String(rec.get("name", "Part")) if not rec.is_empty() else "Part"
	panel_title.text = "Change your %s" % _nm()
	redo_btn.visible = not m.redo.is_empty()
	var off := not Part.available()
	for k in make_btns:
		m._grey(make_btns[k], Part.why_not() if off else "")
	(make_btns["draw"] as Button).set_pressed_no_signal(armed == "draw" and not off)
	(make_btns["curve"] as Button).set_pressed_no_signal(armed == "curve" and not off)
	(make_btns["colour"] as Button).set_pressed_no_signal(armed == "colour" and not off)
	(make_btns["stick"] as Button).set_pressed_no_signal(armed == "stick" and not off)
	m._grey(back_btn, Part.why_not() if off else ("" if t != "" else "Pick a shape above first"))
	m._grey(use_scene_btn, Part.why_not() if off else ("" if not _rec().get("features", []).is_empty() else "Draw a shape first"))
	easy_btn.set_pressed_no_signal(true)
	expert_btn.set_pressed_no_signal(false)
	_chips_sync()
	_rows_sync()
	_values_sync()
	_sync_shape()
	_hole_sync()
	var res: Dictionary = pu.res
	var text := ""
	if off:
		text = Part.why_not()
	elif msg != "":
		text = msg
	elif armed != "":
		text = _arm_words(armed)
	elif t != "":
		text = "Drag an amber dot, or use the sliders"
	elif not res.is_empty() and int(res.get("bodies", 0)) > 0:
		text = "Press a button above to change it, or pick a shape on the right"   # a part of the user's own (no template): not "draw a shape"
	else:
		text = "Press Draw shape, then drag on the grid (or pick a template on the right)"   # FKEY: a beginner sees the verb first, not a shape that is not there
	hint_l.text = text
	var errs: Dictionary = res.get("errors", {}) if not res.is_empty() else {}
	var bodies := int(res.get("bodies", 0)) if not res.is_empty() else 0
	if off:
		status_l.text = "Greyed out: this tool is not in this copy of Kine"
	elif rec.is_empty():
		status_l.text = "Nothing here yet"
	elif not errs.is_empty():
		status_l.text = "One step could not follow the new sizes. Undo takes it back"
	elif bodies == 1 and _lumps(res) > 1:
		status_l.text = "%d pieces that do not touch: Stick together joins them" % _lumps(res)   # a join of copies with a gap is one body of apart pieces
	elif bodies == 1:
		status_l.text = "Looks good: one solid, no gaps"
	elif bodies == 0:
		status_l.text = "No solid yet"
	else:
		status_l.text = "%d separate pieces" % bodies


func _sync_shape() -> void:
	for k in shape_btns:
		(shape_btns[k] as Button).set_pressed_no_signal(k == shape)


## the panel's height if it is not cut short: its column plus its own margins
func _panel_need() -> float:
	return panel_vb.get_combined_minimum_size().y + panel.get_theme_stylebox("panel").get_minimum_size().y


## FMOBILE: a bottom-left box's top: its usual place, never above the sentence under the hint, and above the one sentence at the bottom when the room allows
static func _low_box_y(want: float, h: float, low_y: float, stat_top: float) -> float:
	return clampf(want, low_y, maxf(low_y, stat_top - h))


## the layout, from PartUI.layout(cl): the clear view's rectangle
func layout(cl: Rect2) -> void:
	if not active():
		return
	_cl = cl
	var w := cl.size.x - 16.0
	var narrow := get_viewport().get_visible_rect().size.x < NARROW_W   # FMOBILE: at 1024 wide the bar row is wider than the window: its buttons shrink, the title shortens
	use_scene_btn.custom_minimum_size.x = 96.0 if narrow else 150.0
	var tight := get_viewport().get_visible_rect().size.x < 1300.0   # FMOBILE5: 1280 wide, the bar row (What to build at its end) needs the short words at 72 px
	for sb in [undo_btn, redo_btn, easy_btn, expert_btn]:
		(sb as Button).custom_minimum_size.x = 72.0 if tight else 96.0
	give_btn.custom_minimum_size.x = 110.0 if narrow else 170.0
	_narrow_bar_text(narrow)   # P172LAYOUTS: the long bar words trim at 1024 wide instead of setting the row wider than the window
	dup_btn.custom_minimum_size.x = 92.0 if narrow else 120.0   # FMOBILE2: 1024 wide, the bar row (with What to build at its end) must fit the window
	if bar_home != null:
		bar_home.custom_minimum_size.x = 88.0 if narrow else 110.0
	if pu != null and pu.reopen_btn != null:
		pu.reopen_btn.add_theme_font_size_override("font_size", 14 if narrow else 16)
	# FMOBILE: at 1024 wide the Repeat it row (Row Up Forward Ring Corners) is narrower, so it fits left of the panel instead of under it
	for rb in rep_btns.values():
		(rb as Button).custom_minimum_size.x = 92.0 if narrow else 110.0
	export_btn.custom_minimum_size.x = 84.0 if narrow else 110.0
	title_l.clip_text = narrow
	title_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if narrow else TextServer.OVERRUN_NO_TRIMMING
	var n := float(MAKES.size())   # twelve buttons in one row: each takes its share (the row is as wide as the clear view allows)
	var bw := minf(176.0, (w - (n - 1.0) * 8.0) / n)
	make_box.reset_size()
	for b in make_btns.values():
		(b as Control).custom_minimum_size.x = bw
	make_box.size = Vector2(bw * n + (n - 1.0) * 8.0, MAKE_H)
	make_box.position = Vector2(cl.position.x + 8.0, cl.position.y + 4.0)
	var top := make_box.position.y + maxf(MAKE_H, make_box.size.y) + 8.0   # the side panel's top
	view_box.reset_size()   # P107 FITVIEW: the five view buttons, a narrow column at the top right of the clear view, just left of the panel: the
	# left column keeps its place and the grid's middle and bottom (where the pieces stand) stay free; the words stop short of it
	view_box.position = Vector2(cl.end.x - PW - 18.0 - view_box.size.x, top)
	var fnt: Font = hint_l.get_theme_font("font")   # the words' width on one line (a label that wraps reports no width)
	var one_line := fnt.get_string_size(hint_l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, hint_l.get_theme_font_size("font_size")).x + 40.0
	hint.size.x = minf(one_line, minf(cl.size.x - PW - 40.0, view_box.position.x - cl.position.x - 24.0))   # P107: never under the view column
	hint.size.y = hint.get_combined_minimum_size().y   # the height of the words wrapped to that width
	hint.position = Vector2(cl.position.x + 12.0, top)
	shape_box.reset_size()
	shape_box.position = Vector2(cl.position.x + 12.0, top + hint.size.y + 6.0)
	var shape_nat := 24.0   # EASYPART5: the six shapes in one row; the choice wraps to the room left of the panel, never under it
	for c in (shape_box.get_child(0) as Control).get_children():
		shape_nat += (c as Control).get_combined_minimum_size().x + 6.0
	shape_box.size.x = minf(cl.end.x - PW - 32.0 - shape_box.position.x, shape_nat)
	shape_box.size.y = shape_box.get_combined_minimum_size().y
	hole_box.reset_size()
	hole_box.position = shape_box.position
	split_box.reset_size()
	split_box.position = shape_box.position
	round_box.reset_size()   # NROUNDFILTER: the filter chips sit where the other chip rows do
	round_box.position = shape_box.position
	colour_box.reset_size()
	colour_box.position = shape_box.position
	# FMOBILE: the floating boxes stay left of the panel (the colour chips wrap) and below the sentence (the hint)
	var room := cl.end.x - PW - 32.0 - colour_box.position.x
	var nat := 24.0   # the chips in one row (their own widths and the gaps): the box is only as wide as its chips when the room is wide
	for c in (colour_box.get_child(0) as Control).get_children():
		nat += (c as Control).get_combined_minimum_size().x + 6.0
	colour_box.size.x = minf(room, nat)
	colour_box.size.y = colour_box.get_combined_minimum_size().y
	# the Repeat it and Stick together rows sit at the lower left, above the one sentence, off the model's pieces (and never over the sentence)
	var low_y := hint.position.y + hint.size.y + 6.0
	var stat_top := _low_end(cl) - status.get_combined_minimum_size().y - 12.0   # the one sentence at the bottom-left: the boxes end above it
	# a short window: the Fewer / More words under the Repeat it sliders go first, so the box fits between the sentence and the one line at the bottom
	# (hysteresis: the words toggle only when the box crosses the room, never every frame)
	if not rep_rows.is_empty():
		var room_h := stat_top - low_y - 4.0
		var words_on := bool((rep_rows[0]["words"] as Control).visible)
		var wh := float((rep_rows[0]["words"] as Control).get_combined_minimum_size().y) + 4.0
		repeat_box.reset_size()
		var h_now := repeat_box.get_combined_minimum_size().y
		var want_on := (h_now + wh) <= room_h if not words_on else h_now <= room_h
		if want_on != words_on:
			for r in rep_rows:
				(r["words"] as Control).visible = want_on
	repeat_box.reset_size()
	repeat_box.position = Vector2(cl.position.x + 12.0, _low_box_y(cl.end.y - repeat_box.size.y - 64.0, repeat_box.size.y, low_y, stat_top))
	stick_box.reset_size()
	stick_box.position = Vector2(cl.position.x + 12.0, _low_box_y(cl.end.y - stick_box.size.y - 64.0, stick_box.size.y, low_y, stat_top))
	tilt_box.reset_size()
	var tilt_y := cl.end.y - tilt_box.size.y - 64.0
	if repeat_box.visible:   # FMOBILE5: Tilt it and Repeat it show together (nothing armed): Tilt sits above the Repeat rows, never over their sliders
		tilt_y = repeat_box.position.y - tilt_box.size.y - 6.0
	var tilt_x := cl.position.x + 12.0
	if repeat_box.visible and tilt_y < low_y:   # a short window: no room above the Repeat rows, so Tilt it stands beside them
		tilt_x = repeat_box.position.x + repeat_box.size.x + 8.0
		tilt_y = repeat_box.position.y + repeat_box.size.y - tilt_box.size.y
	tilt_box.position = Vector2(tilt_x, _low_box_y(tilt_y, tilt_box.size.y, _tilt_low(low_y), stat_top))
	explode_box.reset_size()   # EXPLODE (p103): the Pull apart slider sits under the Round filter row (that row is up whenever a solid is), clear of the low rows and the view's drags
	explode_box.position = Vector2(cl.position.x + 12.0, round_box.position.y + round_box.size.y + 6.0)
	# the panel on the right, as tall as it needs; the words under the sliders go first when the room is short
	var avail := _panel_room(cl.end.y - top - 4.0, top)   # P172LAYOUTS: the step list keeps the window's bottom edge (narrow)
	panel.reset_size()
	var need := _panel_need()
	if need > avail and not _compact:
		_compact = true
		_rows_sig = ""
		_rows_sync()
		panel.reset_size()
		need = _panel_need()
	elif need < avail - 70.0 and _compact:
		_compact = false
		_rows_sig = ""
		_rows_sync()
		panel.reset_size()
		need = _panel_need()
	panel.size = Vector2(PW, minf(need, avail))
	panel.position = Vector2(cl.end.x - PW - 8.0, top)
	_steps_place(cl, _steps_y(panel.position.y + maxf(panel.size.y, need) + 8.0, panel.position.y + panel.size.y + 8.0))   # NSTEPLIST: under the panel, on the right; under its CONTENT when the Parts page runs past the clamped size (the list sat over the screw chips)
	_flat_narrow()   # P172LAYOUTS: the Lay it flat box beside the sentence at 1024 wide, not under the step list (off the window)
	status.reset_size()
	status.size.x = minf(status.get_combined_minimum_size().x, cl.size.x - PW - 40.0)
	status.position = Vector2(cl.position.x + 12.0, _low_end(cl) - status.size.y - 6.0)
	# FMOBILE: a short window: when a Repeat it / Stick together box would cover the one sentence, the sentence goes under the panel on the right
	var sbox := Rect2()
	for bx in [repeat_box, stick_box]:
		if (bx as Control).visible:
			sbox = sbox.merge(Rect2((bx as Control).position, (bx as Control).size))
	if sbox.size != Vector2.ZERO and Rect2(status.position, status.size).intersects(sbox):
		status.size.x = PW
		status.position = Vector2(panel.position.x, panel.position.y + panel.size.y + 8.0)


# ---------------------------------------------------------------- amber dots and the shape being drawn

func _dot_list() -> Array:
	var out := []
	var e: Dictionary = _rec().get("easy", {})
	if e.is_empty() or m.cam == null:
		return out
	for d in PartTemplates.T[e["t"]]["params"]:
		var dd := PartTemplates.dot_of(String(e["t"]), String(d["k"]), e["p"])
		if dd.is_empty():
			continue
		var at: Vector3 = dd["at"]
		if m.cam.is_position_behind(at):
			continue
		dd["k"] = d["k"]
		dd["label"] = d["label"]
		dd["scr"] = m.cam.unproject_position(at)
		out.append(dd)
	return out


func dot_screen(k: String) -> Vector2:
	for d in _dot_list():
		if d["k"] == k:
			return d["scr"]
	return Vector2(-1, -1)


## the body whose projected triangles are nearest the screen point, within PICK_PX; -1 when none is that close
func _near_body(p: Vector2, faces: Array) -> int:
	var best := -1
	var best_d := PICK_PX
	for bi in faces.size():
		var tris: PackedVector3Array = faces[bi]
		for k in range(0, tris.size() - 2, 3):
			var q := _proj3(tris, k)
			if q.is_empty():
				continue
			var d := _tri_px(p, q)
			if d < best_d:
				best_d = d
				best = bi
	return best


## the crease edges of a triangle soup: an edge whose two triangles turn more than ~8 deg (or that has one triangle) is drawn;
## the diagonals inside a flat face are not. Points are matched to 0.01 mm
func _creases(tris: PackedVector3Array) -> PackedVector3Array:
	var seen := {}   # edge key -> [a, b, normal of the first triangle, still to draw]
	var out := PackedVector3Array()
	for k in range(0, tris.size() - 2, 3):
		var n := (tris[k + 1] - tris[k]).cross(tris[k + 2] - tris[k]).normalized()
		for j in 3:
			var a: Vector3 = tris[k + j]
			var b: Vector3 = tris[k + (j + 1) % 3]
			var ka := str((a * 1e5).round())
			var kb := str((b * 1e5).round())
			var key := ka + "|" + kb if ka < kb else kb + "|" + ka
			if seen.has(key):
				seen[key][3] = (seen[key][2] as Vector3).dot(n) < 0.99
			else:
				seen[key] = [a, b, n, true]
	for e in seen.values():
		if e[3]:
			out.append(e[0])
			out.append(e[1])
	return out


## the three corners of triangle k on screen (empty when one is behind the camera)
func _proj3(tris: PackedVector3Array, k: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for j in 3:
		var w: Vector3 = tris[k + j]
		if m.cam.is_position_behind(w):
			return PackedVector2Array()
		out.append(m.cam.unproject_position(w))
	return out


## the screen distance from p to a triangle (0 inside it)
func _tri_px(p: Vector2, q: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(p, q):
		return 0.0
	var d := INF
	for j in 3:
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, q[j], q[(j + 1) % 3])))
	return d


func _draw_dots() -> void:
	var font := ThemeDB.fallback_font
	if del_on:   # FDELETE: the picked piece glows red-amber
		for k in range(0, del_tris.size() - 2, 3):
			var q := _proj3(del_tris, k)
			if q.size() < 3 or absf((q[1] - q[0]).cross(q[2] - q[0])) < 0.5:
				continue
			dots.draw_colored_polygon(q, Color(1.0, 0.35, 0.2, 0.3))
	for bi in stick_picks:   # the picked piece glows: its faces tinted, its edges amber
		var tris: PackedVector3Array = stick_tris.get(bi, PackedVector3Array())
		for k in range(0, tris.size() - 2, 3):
			var q := _proj3(tris, k)
			if q.size() < 3 or absf((q[1] - q[0]).cross(q[2] - q[0])) < 0.5:
				continue   # a face seen edge-on is a line on screen: no polygon to fill (the triangulation refuses it)
			dots.draw_colored_polygon(q, Color(AMBER, 0.28))
		var ed: PackedVector3Array = stick_edges.get(bi, PackedVector3Array())
		for k in range(0, ed.size() - 1, 2):
			if m.cam.is_position_behind(ed[k]) or m.cam.is_position_behind(ed[k + 1]):
				continue
			dots.draw_line(m.cam.unproject_position(ed[k]), m.cam.unproject_position(ed[k + 1]), AMBER, 2.0, true)
	if not _draft.is_empty():
		var pts := _draft_outline()
		if pts.size() > 1:
			dots.draw_polyline(pts, AMBER, 3.0, true)
	_draw_line_show()   # P045 LINE SHOW: the Line just drawn stays on the grid
	var e: Dictionary = _rec().get("easy", {})
	for d in _dot_list():
		var p: Vector2 = d["scr"]
		var hot: bool = _hover == d["k"] or (not _drag.is_empty() and _drag["k"] == d["k"])
		dots.draw_circle(p, 13.0 if hot else 11.0, Color(0.1, 0.11, 0.14))
		dots.draw_arc(p, 12.0 if hot else 10.0, 0.0, TAU, 28, AMBER, 3.0, true)
		dots.draw_circle(p, 4.0, AMBER)
		if not hot:
			continue   # the label of a dot shows while the mouse is on it or holds it (all of them hid the model)
		var v: float = float(e["p"][d["k"]]) / 10.0
		var txt := "%s %s cm" % [d["label"], str(snappedf(v, 0.1))]
		var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		var tp := p + Vector2(-sz.x * 0.5, 30.0)
		dots.draw_rect(Rect2(tp + Vector2(-8, -sz.y + 1), sz + Vector2(16, 6)), Color(0.1, 0.11, 0.14, 0.9))
		dots.draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


## THE FLOOR GRID: the Part grid laid on the top plane (y = 0): a line every 5 cm (every 25 cm brighter) across 1 m, the axes tinted.
## Built once (an ImmediateMesh of lines beside the camera), shown only while Easy Part is on
var floor_mi: MeshInstance3D     # THE FLOOR GRID as 3D lines in the world: the part hides it, the buttons sit above it (a 2D overlay drew over both)


func _floor_sync(on: bool) -> void:
	if floor_mi == null:
		if not on or m.cam == null or m.cam.get_parent() == null:
			return
		var n := 10
		var e := n * 50.0 * Part.MM
		var im := ImmediateMesh.new()
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in range(-n, n + 1):
			var v := float(i) * 50.0 * Part.MM
			var col := Color(0.4, 0.48, 0.6, 0.3 if i % 5 == 0 else 0.16)
			if i == 0:
				col = Color(0.85, 0.35, 0.35, 0.5)
			for ln in [[Vector3(-e, 0, v), Vector3(e, 0, v)], [Vector3(v, 0, -e), Vector3(v, 0, e)]]:
				for q in ln:
					im.surface_set_color(col)
					im.surface_add_vertex(q)
		im.surface_end()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		floor_mi = MeshInstance3D.new()
		floor_mi.name = "EasyFloorGrid"
		floor_mi.mesh = im
		floor_mi.material_override = mat
		floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.cam.get_parent().add_child(floor_mi)
	floor_mi.visible = on


## UPRIGHT THROUGH THE MIDDLE (side-on): the camera looks along a horizontal line (|pitch| < SIDE_ON), so a press on empty space draws on
## the upright plane through the part's middle that faces the camera: Front (+Z) or Right (+X), whichever the yaw is nearer to.
const SIDE_ON := 15.0       # deg: the camera within this of level looks side-on (the ViewCube's FRONT / RIGHT); Easy opens at ENTRY_PITCH


func _side_on() -> bool:
	return absf(float(m.pitch)) < SIDE_ON


## {"pl": the plane (offset to the part box's middle), "base": "front"|"right", "mm": the offset along its normal, "through": true}
func _upright() -> Dictionary:
	var yr := deg_to_rad(float(m.yaw))
	var base := "right" if absf(sin(yr)) > absf(cos(yr)) else "front"
	var bb: AABB = pu.res.get("aabb", AABB()) if pu != null else AABB()
	var c := bb.position + bb.size * 0.5   # metres
	var mm := snappedf((c.x if base == "right" else c.z) / Part.MM, 0.01)
	var pl := Part.plane(base)
	pl["o"] = (pl["o"] as Vector3) + (pl["n"] as Vector3) * mm * Part.MM
	return {"pl": pl, "base": base, "mm": mm, "through": true}


var upright_mi: MeshInstance3D   # THE UPRIGHT PLANE: a faint grid through the part, 3D lines in the world (shown only while drawing side-on)
var _upright_key := ""


func _upright_sync(on: bool) -> void:
	if not on or m.cam == null or m.cam.get_parent() == null:
		if upright_mi != null:
			upright_mi.visible = false
		return
	var up := _upright()
	var pl: Dictionary = up["pl"]
	var bb: AABB = pu.res.get("aabb", AABB()) if pu != null else AABB()
	var c2 := Part.to_plane(pl, bb.position + bb.size * 0.5)
	var half := maxf(60.0, maxf(bb.size.x, maxf(bb.size.y, bb.size.z)) / Part.MM * 0.6 + 20.0)
	var key := "%s %s %s" % [up["base"], str(up["mm"]), str(snappedf(half, 1.0))]
	if upright_mi == null:
		upright_mi = MeshInstance3D.new()
		upright_mi.name = "EasyUprightGrid"
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		upright_mi.material_override = mat
		upright_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.cam.get_parent().add_child(upright_mi)
	upright_mi.visible = true
	if key == _upright_key:
		return
	_upright_key = key
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var col_g := Color(0.55, 0.75, 1.0, 0.14)
	var col_e := Color(0.55, 0.75, 1.0, 0.45)
	var n := int(roundf(half / 10.0))
	for i in range(-n, n + 1):
		var v := float(i) * 10.0
		var col := col_g if i != -n and i != n else col_e
		for ln in [[Vector2(-half, v), Vector2(half, v)], [Vector2(v, -half), Vector2(v, half)]]:
			for q in ln:
				im.surface_set_color(col)
				im.surface_add_vertex(Part.to_world(pl, c2 + (q as Vector2)))
	im.surface_end()
	upright_mi.mesh = im

func _draft_outline() -> PackedVector2Array:
	var a: Vector2 = _draft["a"]
	var b: Vector2 = _draft["b"]
	var pts := PackedVector2Array()
	if String(_draft["shape"]) == "curve" or String(_draft["shape"]) == "line":   # P040: a Line shows its points as they come
		for q in _draft["pts"]:
			pts.append(m.cam.unproject_position(_pw(q as Vector2)))
		return pts
	if String(_draft["shape"]) == "box":
		for q in [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y), a]:
			pts.append(m.cam.unproject_position(_pw(q)))
	elif String(_draft["shape"]) == "pointy":
		for q in _pointy_pts(a, b) + [a]:
			pts.append(m.cam.unproject_position(_pw(q)))
	elif String(_draft["shape"]) == "hex" or String(_draft["shape"]) == "poly":
		for q in _poly_pts(a, b, _draft_sides()) + [a]:
			pts.append(m.cam.unproject_position(_pw(q)))
	else:
		var r := a.distance_to(b)
		for i in 33:
			var q := a + Vector2.from_angle(TAU * i / 32.0) * r
			pts.append(m.cam.unproject_position(_pw(q)))
	return pts


## P044 SKETCH DIMS: the length of every side of the draft while the mouse holds it: a small label in mm beside each side's middle.
## The labels are children of the dots canvas (made once, reused, hidden when no draft has sides). A curve or a round shape has no sides: none shown
var dim_labels: Array = []


func _dim_label(i: int) -> Label:
	while dim_labels.size() <= i:
		var l := Label.new()
		l.name = "easypart_draft_dim_%d" % dim_labels.size()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", Color.WHITE)
		l.add_theme_stylebox_override("normal", _style(Color(0.1, 0.11, 0.14, 0.9), 4, 6))
		dots.add_child(l)
		dim_labels.append(l)
	return dim_labels[i]


## the corners (mm, on the draft's plane) of a box, pointy or polygon draft; [] for the rest
func _draft_corners_mm() -> Array:
	var a: Vector2 = _draft["a"]
	var b: Vector2 = _draft["b"]
	match String(_draft.get("shape", "")):
		"box":
			return [a, Vector2(b.x, a.y), b, Vector2(a.x, b.y)]
		"pointy":
			return _pointy_pts(a, b)
		"hex", "poly":
			return _poly_pts(a, b, _draft_sides())
	return []


## the side lengths are read from the mm corners, then each label sits just outside its side's middle (away from the shape's centre)
func _draft_dims_sync() -> void:
	var poly := [] if _draft.is_empty() else _draft_corners_mm()
	var n := 0
	if poly.size() >= 3:
		var sc: Array = []
		var cen := Vector2.ZERO
		for q in poly:
			var s: Vector2 = m.cam.unproject_position(_pw(q))
			sc.append(s)
			cen += s / float(poly.size())
		for i in poly.size():
			var j := (i + 1) % poly.size()
			var mid: Vector2 = ((sc[i] + sc[j]) * 0.5)
			var l := _dim_label(n)
			l.text = _fmt((poly[i] as Vector2).distance_to(poly[j]), "mm")
			l.reset_size()
			l.position = mid + (mid - cen).normalized() * 18.0 - l.size * 0.5 - dots.global_position
			l.visible = true
			n += 1
	for i in range(n, dim_labels.size()):
		(dim_labels[i] as Label).visible = false


## POINTY: the drag's corners a and b make an isoceles triangle: the base is a's side of the box (a to (b.x, a.y)), the point is at the middle of the far edge (b's side: (middle x, b.y))
func _pointy_pts(a: Vector2, b: Vector2) -> Array:
	return [a, Vector2(b.x, a.y), Vector2((a.x + b.x) * 0.5, b.y)]


## NPOLY2: the sides of the draft being drawn: a Sides shape its slider's count, a Hex 6
func _draft_sides() -> int:
	return sides if String(_draft.get("shape", "")) == "poly" else 6


## NPOLY2: the Sides row: the word Sides, a slider 3 to 12 (a click or a drag), and the count in words. Moving it picks the Sides shape
func _sides_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "easypart_sides_row"
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var sl_l := Label.new()
	sl_l.name = "easypart_sides_label"
	sl_l.text = "Sides"
	sl_l.add_theme_font_size_override("font_size", 16)
	row.add_child(sl_l)
	var sl := HSlider.new()
	sl.name = "easypart_sides"
	sl.min_value = 3
	sl.max_value = 12
	sl.step = 1
	sl.value = sides
	sl.focus_mode = Control.FOCUS_NONE
	sl.custom_minimum_size = Vector2(120, 40)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.tooltip_text = "Sides: how many sides the shape has (3 is a triangle, 6 a hexagon, 12 nearly round)"
	var tr := _style(Color(0.2, 0.21, 0.26), 4, 0)
	tr.content_margin_top = 4
	tr.content_margin_bottom = 4
	var fill := _style(AMBER, 4, 0)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	sl.add_theme_stylebox_override("slider", tr)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	var kn := _knob()
	sl.add_theme_icon_override("grabber", kn)
	sl.add_theme_icon_override("grabber_highlight", kn)
	row.add_child(sl)
	var rd := Label.new()
	rd.name = "easypart_sides_value"
	rd.add_theme_font_size_override("font_size", 16)
	rd.text = "%d sides" % sides
	row.add_child(rd)
	sl.value_changed.connect(func(v: float): sides = int(v); shape = "poly"; rd.text = "%d sides" % sides; _sync_shape())
	return row


## POLY: a regular polygon with `n` sides in the drag box: a vertex on the box's right, the rest round, centred on the box's middle. The box's width and height are the most it can reach (a Hex is the n = 6 case)
func _poly_pts(a: Vector2, b: Vector2, n: int) -> Array:
	if n == 6:
		return _hex_pts(a, b)
	var c := (a + b) * 0.5
	var mx := 0.0
	var my := 0.0
	for i in n:
		mx = maxf(mx, absf(cos(TAU * i / n)))
		my = maxf(my, absf(sin(TAU * i / n)))
	var r := minf(absf(b.x - a.x) * 0.5 / mx, absf(b.y - a.y) * 0.5 / my)
	var out := []
	for i in n:
		out.append(c + Vector2.from_angle(TAU * i / n) * r)
	return out


## HEX: a regular hexagon in the drag box, centred on its middle, flat top and bottom (the box's width is the corner-to-corner, its height the across-flats); the drag takes the smaller of the two sizes
func _hex_pts(a: Vector2, b: Vector2) -> Array:
	var c := (a + b) * 0.5
	var r := minf(absf(b.x - a.x) * 0.5, absf(b.y - a.y) * 0.5 / 0.8660254)
	var out := []
	for i in 6:
		out.append(c + Vector2.from_angle(PI / 3.0 * i) * r)
	return out


## the world point of a draft coordinate (the draft plane, else the FLOOR: the Part top plane, y = 0)
func _pw(q: Vector2) -> Vector3:
	return Part.to_world(_draft.get("pl", Part.plane("top")), q)


## DRAW ON A FACE: the flat face under a press, or {} (none, a curved face, or not within 5 deg of +-X, +-Y or +-Z).
## {"pl": the plane through the face, "base": "right"|"top"|"front", "mm": distance along the base normal, "out": +1 or -1 (the face normal side)}
func _face_hit(p: Vector2) -> Dictionary:
	var fc := _face_hit_at(p)
	if String(fc.get("base", "")) == "top":
		return fc
	# FBOX: a press on a wall's top edge within 2 mm of the solid's top (a rim 3 mm wide, seen from the far side) is the TOP face there (a lid on the rim)
	var top_m: float = (pu.res.get("aabb", AABB()) as AABB).end.y if pu != null else 0.0
	if top_m > 0.0 and fc.has("hit") and absf((fc["hit"] as Vector3).y - top_m) <= 0.002:
		var tp := Part.plane("top")
		tp["o"] = (tp["o"] as Vector3) + (tp["n"] as Vector3) * top_m
		return {"pl": tp, "base": "top", "mm": snappedf(top_m / Part.MM, 0.01), "out": 1}
	# a press on a solid's top edge or corner (a chair leg's corner, seen from the side) lands on the side face just below the top:
	# a tip-of-the-top press a few px higher takes the TOP face there, so a seat drawn on the leg tops sits on them
	for off in [Vector2(0.0, -6.0), Vector2(-6.0, -6.0), Vector2(6.0, -6.0)]:
		var up := _face_hit_at(p + off)
		if String(up.get("base", "")) == "top":
			return up
	# FBRACKET: a press that misses every face (a press on the FAR edge of a top face grazes it) is a press a few px lower,
	# which is inside the top face; without this the flange was drawn on the floor and came out beside the plate
	if fc.is_empty():
		for off in [Vector2(0.0, 6.0), Vector2(-6.0, 6.0), Vector2(6.0, 6.0)]:
			var dn := _face_hit_at(p + off)
			if String(dn.get("base", "")) == "top":
				return dn
	return fc


func _face_hit_at(p: Vector2) -> Dictionary:
	if not Part.available():
		return {}
	var faces: Array = _shown_faces()
	var ro: Vector3 = m.cam.project_ray_origin(p)
	var rd: Vector3 = m.cam.project_ray_normal(p)
	var best_d := INF
	var bi := -1
	var bk := -1
	var bh := Vector3.ZERO
	for b in faces.size():
		var tris: PackedVector3Array = faces[b]
		for k in range(0, tris.size() - 2, 3):
			var hit: Variant = SkinPick.ray_tri_mm(ro, rd, tris[k], tris[k + 1], tris[k + 2])
			if hit != null and ro.distance_to(hit as Vector3) < best_d:
				best_d = ro.distance_to(hit as Vector3)
				bi = b
				bk = k
				bh = hit
	if bi < 0:
		return {}
	var tris: PackedVector3Array = faces[bi]
	var a: Vector3 = tris[bk]
	var c1: Vector3 = tris[bk + 1]
	var c2: Vector3 = tris[bk + 2]
	var nrm := (c1 - a).cross(c2 - a)
	if nrm.length() < 1e-12:
		return {}
	nrm = nrm.normalized()
	if nrm.dot(rd) > 0.0:
		nrm = -nrm   # the side the camera sees: the outward normal of a front face
	var ax := -1
	for i in 3:
		if absf(nrm.dot(FACE_N[i])) >= cos(deg_to_rad(5.0)):
			ax = i
	if ax < 0:
		return {}
	# flat: a triangle across an edge that bends by 1 to 40 deg means a curved face (a cylinder, a sphere): no face
	for j in range(0, tris.size() - 2, 3):
		if j == bk:
			continue
		var shared := 0
		for v in [tris[j], tris[j + 1], tris[j + 2]]:
			if v.is_equal_approx(a) or v.is_equal_approx(c1) or v.is_equal_approx(c2):
				shared += 1
		if shared != 2:
			continue
		var nj := (tris[j + 1] - tris[j]).cross(tris[j + 2] - tris[j])
		if nj.length() < 1e-12:
			continue
		var ang := nrm.angle_to(nj.normalized())
		if ang > deg_to_rad(1.0) and ang < deg_to_rad(40.0):
			return {}
	var mm := snappedf(bh.dot(FACE_N[ax]) / Part.MM, 0.01)
	var out := 1 if nrm.dot(FACE_N[ax]) > 0.0 else -1
	var pl := Part.plane(FACE_BASE[ax])
	pl["o"] = (pl["o"] as Vector3) + (pl["n"] as Vector3) * mm * Part.MM
	return {"pl": pl, "base": FACE_BASE[ax], "mm": mm, "out": out, "hit": bh}


## FSPOON: the triangles a press is tested against: the shown mesh of the last step's replay (a press costs no replay of a part
## with a hollow or a blend: each one is seconds). A step not yet shown (a slider edit still pending) replays the record as before
func _shown_faces() -> Array:
	var mesh: Variant = pu.res.get("mesh") if pu != null else null
	if not (mesh is ArrayMesh) or _dirty or (mesh as ArrayMesh).get_surface_count() == 0:
		return Part.body_faces(_rec(), -1)
	var tris := PackedVector3Array()
	var am := mesh as ArrayMesh
	for sf in am.get_surface_count():
		var arr := am.surface_get_arrays(sf)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx == null:
			tris.append_array(verts)
		else:
			for k in (idx as PackedInt32Array):
				tris.append(verts[k])
	return [tris]


const FACE_BASE := ["right", "top", "front"]   # the Part plane each axis is drawn on (+X, +Y, +Z)
const FACE_N := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]


## NSTEPLIST: the list sits under the panel on the right, as tall as the room left (it scrolls past that)
func _steps_place(cl: Rect2, y: float) -> void:
	steps_box.reset_size()
	var room := cl.end.y - y - 44.0
	var sc := steps_box.find_child("easypart_steps_scroll", true, false) as ScrollContainer
	if sc != null:
		sc.custom_minimum_size.y = clampf(steps_vb.get_combined_minimum_size().y, 40.0, maxf(40.0, room - 40.0))
	steps_box.reset_size()
	steps_box.position = Vector2(cl.end.x - PW - 8.0, y)
	flat_box.reset_size()   # p113: the printing box sits under the step list
	flat_box.position = Vector2(steps_box.position.x, y + steps_box.get_combined_minimum_size().y + 6.0)

## p059printtimee (Friday plan 59): the print time, in plain words, on the size label: "about 3 h 39 min to print". A print is mostly infill:
## the walls (1.2 mm over the whole surface) and 20 percent of the middle are what the printer lays down, at about 20 cm3 an hour (a typical
## desktop rate). The surface is the built mesh's triangles, so the words are worked out again only when the volume changes, and not while a slider is in hand
var _print_vol := -1.0     # the volume the print words were worked out for (m3)
var _print_text := ""      # those words

func _print_words() -> String:
	var vol := float(pu.res.get("volume", 0.0))
	if vol <= 0.0:
		return ""
	if vol != _print_vol and not pu.coarse:   # a slider in hand: the coarse mesh is no surface to count; the words follow on release
		_print_vol = vol
		var area := 0.0   # m2: the triangles of the built mesh (every body's outside)
		var mesh: ArrayMesh = pu.res.get("mesh")
		for s in (mesh.get_surface_count() if mesh != null else 0):
			var arr := mesh.surface_get_arrays(s)
			var vx: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var n := ix.size() if ix.size() > 0 else vx.size()
			for t in range(0, n - 2, 3):
				var a := vx[ix[t]] if ix.size() > 0 else vx[t]
				var b := vx[ix[t + 1]] if ix.size() > 0 else vx[t + 1]
				var c := vx[ix[t + 2]] if ix.size() > 0 else vx[t + 2]
				area += 0.5 * (b - a).cross(c - a).length()
		var wall := minf(area * 0.0012, vol)   # m3 of walls
		var mins := roundi((wall + (vol - wall) * 0.2) * 1.0e6 / 20.0 * 60.0)   # m3 -> cm3, ÷ 20 cm3 an hour, -> minutes
		if mins < 1:
			_print_text = "under 1 min to print"
		elif mins < 60:
			_print_text = "about %d min to print" % mins
		else:
			_print_text = "about %d h %d min to print" % [mins / 60, mins % 60]
	return _print_text


## P045 LINE SHOW: the Line just drawn stays on the grid, in the accent colour (Tok, 3 px), each straight stretch with its length in mm.
## {"id": the sketch feature's id, "pl": its plane, "ents": its entities in plane mm}. It hides once another step is the newest (a solid pulled, an undo)
var line_show: Dictionary = {}


func _draw_line_show() -> void:
	var fs: Array = _rec().get("features", [])
	if line_show.is_empty() or fs.is_empty() or String((fs.back() as Dictionary).get("id", "")) != String(line_show["id"]):
		line_show = {}
		return
	var col: Color = Tok.c("accent")
	var font := ThemeDB.fallback_font
	for e in line_show["ents"]:
		var q: Array = [e["a"], e["b"]] if String(e["k"]) == "line" else e["pts"]
		var sc := PackedVector2Array()
		for p in q:
			sc.append(m.cam.unproject_position(Part.to_world(line_show["pl"], Vector2(p[0], p[1]))))
		if sc.size() < 2:
			continue
		dots.draw_polyline(sc, col, 3.0, true)
		if String(e["k"]) != "line":
			continue
		var txt := _fmt(Vector2(e["a"][0], e["a"][1]).distance_to(Vector2(e["b"][0], e["b"][1])), "mm")
		var sz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		var tp := (sc[0] + sc[1]) * 0.5 + Vector2(-sz.x * 0.5, -14.0)
		dots.draw_rect(Rect2(tp + Vector2(-8, -sz.y + 1), sz + Vector2(16, 6)), Color(0.1, 0.11, 0.14, 0.9))
		dots.draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


## p067framefix: a hinge (a Piano strip is the door's full height, a Butt plate is 100 mm) is framed so the solid fills HINGE_SHARE of the
## clear view's height. The free view is shorter than the clear view (the chip rows sit above it), so a FRAME_FILL of the free view left a Piano at 17 %.
const HINGE_SHARE := 0.34
func _hinge_pose(bb: AABB) -> Array:
	var fr := free_rect()
	if fr.size.y < 40.0:
		return []
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	return _frame_pose(bb, HINGE_SHARE * vs.y / fr.size.y)


## P172LAYOUTS: at 1024 wide the two long words of the Easy bar row ("Save and use in a scene" 193 px, "Give to a character" 157 px)
## took their width from their text, so What to build ran off the right edge. Narrow, they keep their set width and trim the words
## (the tooltip has the full words); wide, nothing changes.
func _narrow_bar_text(narrow: bool) -> void:
	for b in [use_scene_btn, give_btn]:
		(b as Button).clip_text = narrow
		(b as Button).text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if narrow else TextServer.OVERRUN_NO_TRIMMING


## P172LAYOUTS: at 1024 wide the one sentence at the bottom-left and the Tilt box go to the window's bottom edge: the clear view is too
## short for the words, the round filter row, Tilt and the sentence together (the Tilt box sat on the round row)
func _low_end(cl: Rect2) -> float:
	var vp := get_viewport().get_visible_rect()
	return vp.end.y - 6.0 if vp.size.x < NARROW_W else cl.end.y


## P172LAYOUTS: at 1024 wide Tilt it goes under the round filter row (it was placed on the row's line)
func _tilt_low(low_y: float) -> float:
	if get_viewport().get_visible_rect().size.x < NARROW_W and round_box.visible:
		return maxf(low_y, round_box.position.y + round_box.size.y + 6.0)
	return low_y


## P172LAYOUTS: the panel gives up the room the step list needs when the list would otherwise run off the window's bottom
func _panel_room(avail: float, top: float) -> float:
	if steps_box == null or not steps_box.is_visible_in_tree():
		return avail
	var win_b := get_viewport().get_visible_rect().end.y
	var steps_h := steps_box.get_combined_minimum_size().y
	if top + maxf(avail, _panel_need()) + 8.0 + steps_h <= win_b - 6.0:
		return avail
	return minf(avail, win_b - 6.0 - steps_h - 8.0 - top)


## P172LAYOUTS: the step list under the panel's content, or under the panel's own (shorter) bottom when the content would push it off the window
func _steps_y(content_y: float, panel_y: float) -> float:
	if content_y + steps_box.get_combined_minimum_size().y <= get_viewport().get_visible_rect().end.y - 6.0:
		return content_y
	return panel_y


## P172LAYOUTS: at 1024 wide the printing box (Lay it flat, Show overhangs) sat under the step list, off the window's bottom: it goes
## to the bottom edge between the sentence and the step list
func _flat_narrow() -> void:
	var vp := get_viewport().get_visible_rect()
	if vp.size.x < NARROW_W and flat_box.visible:
		flat_box.position = Vector2(260.0, vp.end.y - 6.0 - flat_box.size.y)
