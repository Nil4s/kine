class_name SculptAlphaStrip
extends Node
## The alpha strip of the sculpt page (ROADMAP_400 C08; the pictures scripts/sculpt_alphas.gd, the stamping
## scripts/sculpt_alpha_stroke.gd). It sits at the TOP RIGHT of the clear view (the matcap strip is top left, the presets
## panel under it on the left); when the clear view is too narrow for both strips side by side it drops to the bottom right.
##   row 1: "none" and one thumbnail per alpha (a click picks it; A / Shift+A step through them in sculpt)
##   row 2: the stroke method (dots / drag rect / spray), the rotation (follow the stroke / fixed / random), the fixed angle
##          (deg) and "Load PNG..." (any picture becomes an alpha, under its file name)
## DRAG RECT in sculpt: press on the sphere = the stamp's centre, drag = its radius and rotation (a square and a ring follow
## the mouse on the surface's tangent plane), release = the stamp, one undo step. Shift while pressing still smooths.

var ui                        # the KMeshSculptUI
var strip: PanelContainer
var method_box: OptionButton
var rot_box: OptionButton
var angle_box: SpinBox
var row: HBoxContainer
var dlg: FileDialog
var _btns := {}               # alpha name ("" = none) -> Button
var _ov: Control
var _drag := false
var _a := Vector3.ZERO        # drag rect: the press point and normal (world)
var _n := Vector3.UP
var _b := Vector3.ZERO
var last_rect := 0.0          # the last drag rect's radius (m; the tests read it)
var _group := ButtonGroup.new()


func setup(sculpt_ui) -> void:
	ui = sculpt_ui
	name = "sculpt_alpha_strip"
	SculptAlphas.make_all()   # the pictures, made once at startup
	strip = PanelContainer.new()
	strip.name = "alpha_strip"
	strip.visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = Tok.c("float")
	st.set_corner_radius_all(8)
	st.set_content_margin_all(4)
	strip.add_theme_stylebox_override("panel", st)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	strip.add_child(vb)
	row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	vb.add_child(row)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 4)
	vb.add_child(r2)
	method_box = OptionButton.new()
	method_box.name = "alpha_method"
	method_box.focus_mode = Control.FOCUS_NONE
	method_box.tooltip_text = "stroke method: dots (stamps along the stroke), drag rect (drag out one stamp), spray (jittered stamps)"
	for k in SculptAlphaStroke.METHODS:
		method_box.add_item(k)
	method_box.item_selected.connect(func(i: int): set_method(SculptAlphaStroke.METHODS[i]))
	r2.add_child(method_box)
	rot_box = OptionButton.new()
	rot_box.name = "alpha_rotation"
	rot_box.focus_mode = Control.FOCUS_NONE
	rot_box.tooltip_text = "the alpha's rotation: follow the stroke, fixed (the angle box), or random per stamp"
	for k in SculptAlphaStroke.ROTATIONS:
		rot_box.add_item(k)
	rot_box.item_selected.connect(func(i: int): set_rotation(SculptAlphaStroke.ROTATIONS[i]))
	r2.add_child(rot_box)
	angle_box = SpinBox.new()
	angle_box.name = "alpha_angle"
	angle_box.min_value = -180
	angle_box.max_value = 180
	angle_box.step = 5
	angle_box.suffix = "deg"
	angle_box.tooltip_text = "the alpha's angle (the whole rotation when fixed, added to the stroke's direction otherwise)"
	angle_box.value_changed.connect(func(v: float): ui.alpha_angle = v)
	r2.add_child(angle_box)
	var lb := Button.new()
	lb.name = "btn_alpha_load"
	lb.text = "Load PNG..."
	lb.focus_mode = Control.FOCUS_NONE
	lb.tooltip_text = "use a picture of yours as an alpha (its brightness: white pushes, black leaves)"
	lb.pressed.connect(open_dialog)
	r2.add_child(lb)
	ui.m.ui_root.add_child(strip)
	_ov = Control.new()
	_ov.name = "alpha_drag_overlay"
	_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ov.draw.connect(_draw_drag)
	ui.m.ui_root.add_child(_ov)
	fill()


## the alpha buttons, again (after a PNG is loaded)
func fill() -> void:
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()
	_btns.clear()
	var t := Label.new()
	t.text = "Alpha"
	t.tooltip_text = "A next alpha, Shift+A the one before"
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(t)
	for nm in [""] + SculptAlphas.names():
		var b := Button.new()
		b.name = "btn_alpha_" + (String(nm).validate_node_name().replace(" ", "_") if nm != "" else "none")
		b.toggle_mode = true
		b.button_group = _group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(26, 26)
		if nm == "":
			b.text = "none"
			b.tooltip_text = "no alpha: the plain round brush (A steps the alphas)"
		else:
			b.icon = SculptAlphas.thumb(nm, 20)
			b.tooltip_text = "%s (A steps the alphas)" % nm
		b.pressed.connect(pick.bind(nm))
		row.add_child(b)
		_btns[nm] = b
	_mark()


func attach() -> void:
	strip.visible = true
	_mark()
	place()


func detach() -> void:
	strip.visible = false
	_drag = false
	_ov.queue_redraw()


func _mark() -> void:
	if ui == null:
		return
	if _btns.has(ui.alpha):
		(_btns[ui.alpha] as Button).set_pressed_no_signal(true)
	method_box.select(maxi(SculptAlphaStroke.METHODS.find(ui.stroke_method), 0))
	rot_box.select(maxi(SculptAlphaStroke.ROTATIONS.find(ui.alpha_rot), 0))
	angle_box.set_value_no_signal(ui.alpha_angle)


func pick(nm: String) -> void:
	if nm != "" and not SculptAlphas.has(nm):
		return
	ui.alpha = nm
	_mark()
	ui.m._say("Sculpt: alpha %s, %s stroke, rotation %s (A next alpha)" % [nm, ui.stroke_method, ui.alpha_rot] if nm != "" else "Sculpt: no alpha, the plain round brush (A picks one)")


func cycle(step := 1) -> void:
	var all := [""] + SculptAlphas.names()
	pick(all[posmod(all.find(ui.alpha) + step, all.size())])


func set_method(k: String) -> void:
	if not SculptAlphaStroke.METHODS.has(k):
		return
	ui.stroke_method = k
	_mark()
	ui.m._say({SculptAlphaStroke.DOTS: "Sculpt: dots, stamps along the stroke", SculptAlphaStroke.DRAG_RECT: "Sculpt: drag rect: press on the surface and drag out one stamp (its size and turn), it lands on release",
		SculptAlphaStroke.SPRAY: "Sculpt: spray: stamps jittered in place, turn and size"}[k])


func set_rotation(k: String) -> void:
	if not SculptAlphaStroke.ROTATIONS.has(k):
		return
	ui.alpha_rot = k
	_mark()
	ui.m._say("Sculpt: the alpha's rotation: %s" % {SculptAlphaStroke.R_STROKE: "follows the stroke", SculptAlphaStroke.R_FIXED: "fixed at %d deg" % roundi(ui.alpha_angle), SculptAlphaStroke.R_RANDOM: "random per stamp"}[k])


func open_dialog() -> void:
	if dlg == null:
		dlg = FileDialog.new()
		dlg.name = "alpha_png_dialog"
		dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dlg.access = FileDialog.ACCESS_FILESYSTEM
		dlg.filters = PackedStringArray(["*.png ; PNG pictures", "*.jpg, *.jpeg, *.webp ; other pictures"])
		dlg.title = "A picture to use as an alpha"
		dlg.file_selected.connect(load_png)
		ui.m.ui_root.add_child(dlg)
	dlg.popup_centered_ratio(0.6)


## a user picture as an alpha, picked at once; true when it loaded
func load_png(path: String) -> bool:
	var nm := SculptAlphas.load_png(path)
	if nm == "":
		ui.m._say("Sculpt: could not read %s as a picture" % path.get_file())
		return false
	fill()
	pick(nm)
	return true


## top right of the clear view; below the clear view's top band at the bottom right when it would meet the matcap strip
func place() -> void:
	var cl: Rect2 = ui.m.nav_clear_rect()
	strip.size = strip.get_combined_minimum_size()
	var pos := Vector2(cl.end.x - strip.size.x - 12.0, cl.position.y + 12.0)
	var r := Rect2(pos, strip.size)
	if ui.matcap != null and ui.matcap.strip.visible and r.intersects(ui.matcap.strip.get_global_rect().grow(6.0)):
		pos.y = cl.end.y - strip.size.y - 12.0
	strip.global_position = pos


func _process(_dt: float) -> void:
	if strip != null and strip.visible:
		place()


func _world_drag_end(cam: Camera3D, p: Vector2) -> Variant:
	return Plane(_n, _a).intersects_ray(cam.project_ray_origin(p), cam.project_ray_normal(p))


## sculpt keys A / Shift+A, and the drag rect gesture. true = used
func input(ev: InputEvent) -> bool:
	if ev is InputEventKey:
		var ke := ev as InputEventKey
		if ke.pressed and not ke.echo and ke.keycode == KEY_A and not ke.ctrl_pressed and not ke.alt_pressed and not ke.meta_pressed:
			cycle(-1 if ke.shift_pressed else 1)
			return true
		return false
	if ui.stroke_method != SculptAlphaStroke.DRAG_RECT:
		return false
	var cam: Camera3D = ui.m.cam
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		if mb.pressed:
			if mb.shift_pressed:
				return false   # Shift: the smooth stroke, as ever
			var s: Dictionary = ui.surface_at(cam, mb.position)
			if s.is_empty():
				return false
			_drag = true
			_a = s["point"]
			_n = s["normal"]
			_b = _a
			_ov.queue_redraw()
			return true
		if not _drag:
			return false
		_drag = false
		_ov.queue_redraw()
		var e: Variant = _world_drag_end(cam, mb.position)
		if e != null:
			_b = e
		stamp(_a, _n, _b, ui._params(mb))
		return true
	if ev is InputEventMouseMotion and _drag:
		var e2: Variant = _world_drag_end(cam, (ev as InputEventMouseMotion).position)
		if e2 != null:
			_b = e2
		_ov.queue_redraw()
		return true
	return false


## the drag rect stamp from world a (normal n) to world b: one undo step; returns the radius (0: too short)
func stamp(a: Vector3, n: Vector3, b: Vector3, params: Dictionary) -> float:
	var la: Vector3 = ui._local(a)
	var lb: Vector3 = ui._local(b)
	var ln: Vector3 = ui._local_n(n)
	var d := lb - la
	if (d - ln * ln.dot(d)).length() < 0.002:
		ui.m._say("Sculpt: drag rect: drag farther to size the stamp (nothing done)")
		return 0.0
	ui.undo.begin(ui.mesh)
	var r := SculptAlphaStroke.drag_rect(ui.sculpt, ui.mesh, params, la, lb, ln)
	ui.undo.commit("sculpt alpha stamp")
	ui.view.mark_dirty()
	last_rect = r
	ui.m._say("Sculpt: one %s stamp, radius %d mm, one undo step (Ctrl+Z takes it back)" % [ui.alpha if ui.alpha != "" else "round", roundi(r * 1000.0)])
	return r


func _draw_drag() -> void:
	if not _drag or ui == null or not ui.on:
		return
	var cam: Camera3D = ui.m.cam
	if cam.is_position_behind(_a):
		return
	var d := _b - _a
	d -= _n * _n.dot(d)
	var r := d.length()
	var c := Tok.c("pick_hover")
	var sa := cam.unproject_position(_a)
	if r < 1e-5:
		_ov.draw_circle(sa, 3.0, c)
		return
	var t := d / r
	var bb := t.cross(_n)
	var pts := PackedVector2Array()
	for k in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]:
		pts.append(cam.unproject_position(_a + (t * k.x + bb * k.y) * r))
	_ov.draw_polyline(pts, c, 1.5, true)
	var ring := PackedVector2Array()
	for i in 49:
		var ang := TAU * i / 48.0
		ring.append(cam.unproject_position(_a + (t * cos(ang) + bb * sin(ang)) * r))
	_ov.draw_polyline(ring, c, 1.0, true)
	_ov.draw_line(sa, cam.unproject_position(_b), c, 2.0, true)
