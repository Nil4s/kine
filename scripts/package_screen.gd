class_name PackageScreen
extends Control
## VEHICLE, STEP 1 PACKAGE + STEP 6 COMPARE: the Vehicle card's screen (replaces the ready-made car body on the card: see
## scripts/easy_vehicle.gd, kept but no longer opened by the card). The user sets the hard points (CarPackage.PARAMS, the tyre) and
## reads the layout (CarPlan: side and top views in mm), the 3D preview (CarPackage.build_3d), the readouts (length, width, height,
## angles, head room) and "Yours vs real cars" (the nearest real car, every metric, red where far off the chosen class).
## Easy: sliders and pick lists (mouse only). Expert: the same numbers typed in mm. One undo step per change (a slider drag is one).
## Record: m.S.vehicle["package"] = the hard points (CarPackage.start's keys). No key names in any text here.

const THROTTLE_MS := 60
const SKY := Color("#73BFFF")
const AMBER := Color("#FFC933")
const RED := Color("#FF6B6B")
const PW := 340.0
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]

var m: Node
var plan: CarPlan
var vp: SubViewport
var world: Node3D
var cam: Camera3D
var view: TextureRect
var car3d: Node3D = null
var title_l: Label
var undo_btn: Button
var redo_btn: Button
var panel: PanelContainer
var status: PanelContainer
var status_l: Label
var easy := true
var msg := ""
var rows := {}                 # key -> {"slider": HSlider, "pill": Label, "edit": LineEdit, "row": VBoxContainer}
var tyre_opt: OptionButton
var tyre_edit: LineEdit
var tyre_row: VBoxContainer
var readouts := {}             # key -> Label
var feet_hint: Label           # red under the feet readout when the heel point hits the front wheel
var cls_btns := {}
var tab_hp: Button
var tab_cmp: Button
var sec_hp: VBoxContainer
var sec_cmp: VBoxContainer
var cmp_box: VBoxContainer
var cmp_head: Label
var built_3d := 0              # the 3D preview rebuilds (the test counts them)
var _held := false
var _edit_n := -1
var _edit_before := ""
var _last_ms := 0


func build(root: Control) -> void:
	name = "package_screen"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # the screen covers BUILD: a click here never reaches the house below
	visible = false
	root.add_child(self)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var top := PanelContainer.new()
	top.name = "package_bar"
	top.add_theme_stylebox_override("panel", _style(Color(0.09, 0.1, 0.13), 0, 6))
	top.anchor_right = 1.0
	top.offset_bottom = m.TOP_H
	add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	top.add_child(row)
	row.add_child(_bar_btn("Back to BUILD", "Leave the package: the numbers stay as they are", close))
	title_l = Label.new()
	title_l.name = "package_title"
	title_l.add_theme_font_size_override("font_size", 20)
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title_l)
	undo_btn = _bar_btn("Undo", "Take back the last change", func(): m._undo())
	redo_btn = _bar_btn("Redo", "Put back what Undo took back", func(): m._redo())
	row.add_child(undo_btn)
	row.add_child(redo_btn)
	# the layout (side and top views), the 3D view under it
	plan = CarPlan.new()
	plan.name = "package_plan"
	plan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plan)
	vp = SubViewport.new()
	vp.name = "package_view"
	vp.own_world_3d = true
	vp.size = Vector2i(900, 240)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	world = Node3D.new()
	world.name = "world"
	vp.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.23, 0.28)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.75)
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(sun)
	cam = Camera3D.new()
	cam.name = "package_cam"
	cam.fov = 40.0
	cam.current = true
	world.add_child(cam)
	view = TextureRect.new()
	view.name = "package_viewrect"
	view.texture = vp.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	# the right panel: the class chooser, two tabs, and the section
	panel = PanelContainer.new()
	panel.name = "package_panel"
	panel.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.95), 10, 8))
	add_child(panel)
	var v := VBoxContainer.new()
	v.name = "package_panel_vb"
	v.add_theme_constant_override("separation", 5)
	panel.add_child(v)
	var cl := Label.new()
	cl.text = "Start from a class"
	cl.tooltip_text = "Chooser: sets the hard points to the average of the real cars in that class"
	cl.add_theme_font_size_override("font_size", 14)
	v.add_child(cl)
	var crow := HBoxContainer.new()
	crow.name = "package_classes"
	crow.add_theme_constant_override("separation", 3)
	v.add_child(crow)
	for c in CarPackage.CLASSES:
		var b := _small_btn(String(c[0]), "Start from the average of the real %s cars: wheelbase, track, height, clearance and seat height" % String(c[2]), set_class.bind(String(c[0])))
		b.toggle_mode = true
		b.name = "package_class_" + String(c[0]).to_lower()
		crow.add_child(b)
		cls_btns[String(c[0])] = b
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	v.add_child(tabs)
	tab_hp = _small_btn("Hard points", "The numbers you set, and the readouts", func(): _show_tab(true))
	tab_hp.name = "package_tab_points"
	tab_hp.toggle_mode = true
	tabs.add_child(tab_hp)
	tab_cmp = _small_btn("Yours vs real cars", "Your numbers beside the real cars, and the nearest one", func(): _show_tab(false))
	tab_cmp.name = "package_tab_compare"
	tab_cmp.toggle_mode = true
	tab_cmp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(tab_cmp)
	var sc := ScrollContainer.new()
	sc.name = "package_scroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var body := VBoxContainer.new()
	body.name = "package_body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 5)
	sc.add_child(body)
	sec_hp = VBoxContainer.new()
	sec_hp.name = "package_section_points"
	sec_hp.add_theme_constant_override("separation", 3)
	body.add_child(sec_hp)
	for prm in CarPackage.PARAMS:
		sec_hp.add_child(_make_row(prm))
	tyre_row = _tyre_row()
	sec_hp.add_child(tyre_row)
	sec_hp.add_child(HSeparator.new())
	var rd := GridContainer.new()
	rd.columns = 1
	rd.name = "package_readouts"
	sec_hp.add_child(rd)
	for rr in [["length", "Length", "Overall length: nose, wheelbase and tail"], ["width", "Width", "Overall width: the wider track plus the tyre width"],
			["height", "Height", "Overall height: the roof above the ground"], ["approach", "Approach angle", "Approach angle: atan(height off the ground / nose length): how steep a kerb the nose clears"],
			["departure", "Departure angle", "Departure angle: atan(height off the ground / tail length): how steep a slope the tail clears"],
			["head", "Head room", "Head clearance: the roof minus the seated fighter's head top (the seat back angle counts)"],
			["breakover", "Ramp angle", "Breakover angle: 2 x atan(height off the ground / half the wheelbase): the largest hump the middle clears"],
			["hpt", "H-point above ground", "H-point above ground: the ground clearance + the floor (150 mm) + the seat height above the floor"],
			["feet", "Feet clear of the front wheel", "Feet clear: the heel point (seat from the front wheel minus the seated thigh + shin reach along the floor) must be behind the front axle by the tyre radius + 100 mm"]]:
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # the long feet line wraps instead of widening the panel
		l.name = "package_read_" + String(rr[0])
		l.tooltip_text = String(rr[2])
		l.add_theme_font_size_override("font_size", 15)
		rd.add_child(l)
		readouts[String(rr[0])] = l
	feet_hint = Label.new()
	feet_hint.name = "package_hint_feet"
	feet_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feet_hint.add_theme_font_size_override("font_size", 13)
	feet_hint.add_theme_color_override("font_color", RED)
	rd.add_child(feet_hint)
	sec_cmp = VBoxContainer.new()
	sec_cmp.name = "package_section_compare"
	sec_cmp.add_theme_constant_override("separation", 4)
	body.add_child(sec_cmp)
	cmp_head = Label.new()
	cmp_head.name = "package_nearest"
	cmp_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cmp_head.add_theme_font_size_override("font_size", 14)
	sec_cmp.add_child(cmp_head)
	cmp_box = VBoxContainer.new()
	cmp_box.name = "package_cmp_rows"
	cmp_box.add_theme_constant_override("separation", 3)
	sec_cmp.add_child(cmp_box)
	# the one sentence, under the views
	status = PanelContainer.new()
	status.name = "package_status"
	status.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 6))
	status_l = Label.new()
	status_l.add_theme_font_size_override("font_size", 15)
	status_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_child(status_l)
	add_child(status)
	_show_tab(true)
	layout()


## the screen shows: the package is made if there is none, the view framed. easy_on: sliders; else the numbers typed in mm
func open(easy_on: bool) -> void:
	ensure()
	easy = easy_on
	visible = true
	msg = "Set the hard points, then read the layout and the comparison" if easy else "Type a number in mm, then click away from the box"
	_apply_mode()
	_sync()
	frame()


func close() -> void:
	visible = false


## the hard points (m.S.vehicle["package"]); {} until made
func pkg() -> Dictionary:
	var v: Dictionary = m.S.vehicle
	return v.get("package", {})


func ensure() -> void:
	if not pkg().is_empty():
		return
	m._step_hint = "Start a package"
	m._push_undo()
	m.S.vehicle["package"] = CarPackage.start("Hatch")
	_sync()


func _style(c: Color, r: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(r)
	sb.set_content_margin_all(margin)
	return sb


func _bar_btn(t: String, tip: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, m.TOP_H - 12)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(f)
	return b


func _small_btn(t: String, tip: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(f)
	return b


## one number row: the plain label and its value, the slider (Easy) or the typed box (Expert), the engineering term as the tooltip
func _make_row(prm: Array) -> Control:
	var k: String = prm[0]
	var v := VBoxContainer.new()
	v.name = "package_row_" + k
	v.add_theme_constant_override("separation", 0)
	v.tooltip_text = String(prm[2])
	var top := HBoxContainer.new()
	v.add_child(top)
	var lab := Label.new()
	lab.text = String(prm[1])
	lab.tooltip_text = String(prm[2])
	lab.add_theme_font_size_override("font_size", 15)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(lab)
	var pill := Label.new()
	pill.add_theme_font_size_override("font_size", 15)
	pill.add_theme_color_override("font_color", SKY)
	top.add_child(pill)
	var sl := HSlider.new()
	sl.name = "package_slider_" + k
	sl.min_value = float(prm[4])
	sl.max_value = float(prm[5])
	sl.step = float(prm[6])
	sl.focus_mode = Control.FOCUS_NONE
	sl.custom_minimum_size = Vector2(0, 20)
	sl.value_changed.connect(_on_value.bind(k))
	sl.drag_started.connect(_on_start.bind(k))
	sl.drag_ended.connect(_on_end.bind(k))
	v.add_child(sl)
	var ed := LineEdit.new()
	ed.name = "package_edit_" + k
	ed.custom_minimum_size = Vector2(0, 30)
	ed.tooltip_text = String(prm[2]) + ". Type a number, then click away from the box"
	ed.text_submitted.connect(_typed.bind(k))
	ed.focus_exited.connect(func(): _typed(ed.text, k))
	v.add_child(ed)
	rows[k] = {"slider": sl, "pill": pill, "edit": ed, "row": v, "prm": prm}
	return v


func _tyre_row() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = "package_row_tyre"
	v.tooltip_text = "Tyre size: width / aspect R rim (inches), like 225/45R17. The diameter is worked out from it"
	var lab := Label.new()
	lab.text = "Tyre size"
	lab.tooltip_text = v.tooltip_text
	lab.add_theme_font_size_override("font_size", 15)
	v.add_child(lab)
	tyre_opt = OptionButton.new()
	tyre_opt.name = "package_tyre_pick"
	tyre_opt.focus_mode = Control.FOCUS_NONE
	for t in CarPackage.TYRES:
		tyre_opt.add_item(String(t))
	tyre_opt.item_selected.connect(func(i: int): _set_tyre(String(CarPackage.TYRES[i])))
	v.add_child(tyre_opt)
	tyre_edit = LineEdit.new()
	tyre_edit.name = "package_edit_tyre"
	tyre_edit.custom_minimum_size = Vector2(0, 30)
	tyre_edit.placeholder_text = "like 225/45R17"
	tyre_edit.tooltip_text = v.tooltip_text + ". Type it, then click away from the box"
	tyre_edit.text_submitted.connect(func(t: String): _typed_tyre(t))
	tyre_edit.focus_exited.connect(func(): _typed_tyre(tyre_edit.text))
	v.add_child(tyre_edit)
	return v


# ---------------------------------------------------------------- undo steps (one per change)

func _begin(label: String) -> void:
	m._step_hint = label
	m._push_undo()
	_edit_n = m.undo.size()
	_edit_before = JSON.stringify(pkg())


## the step ends; a step that changed nothing is taken back out
func _end() -> void:
	if _edit_n >= 0 and m.undo.size() == _edit_n and JSON.stringify(pkg()) == _edit_before:
		m._drop_undo()
	_edit_n = -1


func _label_of(k: String) -> String:
	for prm in CarPackage.PARAMS:
		if prm[0] == k:
			return String(prm[1])
	return "tyre size"


## one number, one undo step (clamped to its range and snapped to its step)
func set_param(k: String, v: float) -> void:
	ensure()
	var prm: Array = rows[k]["prm"]
	var w := clampf(snappedf(v, float(prm[6])), float(prm[4]), float(prm[5]))
	_begin("Change " + _label_of(k))
	pkg()[k] = w
	_end()
	_sync()


## the tyre size, one undo step (only a size we can read)
func _set_tyre(t: String) -> void:
	ensure()
	if not CarPackage.tyre(t)["ok"] or String(pkg().get("tyre", "")) == t:
		_sync()
		return
	_begin("Change tyre size")
	pkg()["tyre"] = t
	_end()
	_sync()


func _typed_tyre(t: String) -> void:
	if not CarPackage.tyre(t)["ok"]:
		msg = "Type a tyre size like 225/45R17 (width, aspect, R, rim in inches)"
		_sync()
		return
	_set_tyre(t.strip_edges())


func _typed(t: String, k: String) -> void:
	if not t.strip_edges().is_valid_float():
		msg = "Type a number in mm, like %d" % int(rows[k]["prm"][4])
		_sync()
		return
	var v := float(t)
	if absf(v - float(pkg().get(k, 0.0))) < 0.001:
		_sync()
		return
	set_param(k, v)


func _on_start(k: String) -> void:
	_held = true
	ensure()
	_begin("Change " + _label_of(k))


func _on_value(v: float, k: String) -> void:
	var prm: Array = rows[k]["prm"]
	var w := clampf(snappedf(v, float(prm[6])), float(prm[4]), float(prm[5]))
	if not _held:   # a click on the track, or a nudge: one step of its own
		set_param(k, w)
		return
	pkg()[k] = w
	if Time.get_ticks_msec() - _last_ms >= THROTTLE_MS:
		_last_ms = Time.get_ticks_msec()
		_sync()


func _on_end(_changed: bool, k: String) -> void:
	_held = false
	var sl: HSlider = rows[k]["slider"]
	pkg()[k] = snappedf(sl.value, float(rows[k]["prm"][6]))
	_end()
	_sync()


## a class on the card: the hard points start from its real cars' averages (one undo step)
func set_class(cls: String) -> void:
	ensure()
	if String(pkg().get("class", "")) == cls:
		_sync()
		return
	m._step_hint = "Start from " + cls
	m._push_undo()
	m.S.vehicle["package"] = CarPackage.start(cls)
	msg = "Starting from the average of the real %s cars. Change any number from here" % CarPackage.class_row(cls)[2]
	_sync()


func _show_tab(points: bool) -> void:
	sec_hp.visible = points
	sec_cmp.visible = not points
	tab_hp.set_pressed_no_signal(points)
	tab_cmp.set_pressed_no_signal(not points)


func _apply_mode() -> void:
	for k in rows:
		(rows[k]["slider"] as HSlider).visible = easy
		(rows[k]["edit"] as LineEdit).visible = not easy
	tyre_opt.visible = easy
	tyre_edit.visible = not easy


# ---------------------------------------------------------------- the views

## the screen's words and numbers from the hard points: every control reads the record
func _sync() -> void:
	var p := pkg()
	if p.is_empty():
		return
	var d := CarPackage.derive(p)
	for prm in CarPackage.PARAMS:
		var k: String = prm[0]
		var r: Dictionary = rows[k]
		var v := float(p[k])
		(r["slider"] as HSlider).set_value_no_signal(v)
		var unit := String(prm[3])
		(r["pill"] as Label).text = "%s %s" % [str(int(v)) if unit == "mm" else str(snappedf(v, 0.1)), unit]
		var ed: LineEdit = r["edit"]
		if not ed.has_focus():
			ed.text = str(int(v))
	tyre_opt.select(maxi(0, CarPackage.TYRES.find(String(p.get("tyre", "")))))
	if not tyre_edit.has_focus():
		tyre_edit.text = String(p.get("tyre", ""))
	readouts["length"].text = "Length  %d mm" % int(d["length"])
	readouts["width"].text = "Width  %d mm" % int(d["width"])
	readouts["height"].text = "Height  %d mm" % int(d["height"])
	readouts["approach"].text = "Approach angle  %s deg" % str(snappedf(float(d["approach"]), 0.1))
	readouts["departure"].text = "Departure angle  %s deg" % str(snappedf(float(d["departure"]), 0.1))
	readouts["head"].text = "Head room  %d mm" % int(d["head"])
	readouts["breakover"].text = "Ramp angle  %s deg" % str(snappedf(float(d["breakover"]), 0.1))
	readouts["hpt"].text = "H-point above ground  %d mm" % int(d["hpt_ground"])
	var fok := bool(d["feet_ok"])
	readouts["feet"].text = "Feet clear of the front wheel  %d mm (needs %d)" % [int(d["heel"]), int(d["feet_min"])]
	readouts["feet"].add_theme_color_override("font_color", Color(1, 1, 1) if fok else RED)
	feet_hint.text = "" if fok else "  the driver's feet hit the front wheel"
	feet_hint.visible = not fok
	for c in CarPackage.CLASSES:
		(cls_btns[String(c[0])] as Button).set_pressed_no_signal(String(c[0]) == String(p.get("class", "")))
	plan.set_points(p)
	_build_3d(p)
	_build_compare(p)
	title_l.text = "Vehicle: package, %s" % String(p.get("class", "")) if not p.is_empty() else "Vehicle: package"
	undo_btn.disabled = m.undo.is_empty()
	redo_btn.disabled = m.redo.is_empty()
	var reds := 0
	for r in CarPackage.rows(p):
		reds += 1 if r["red"] else 0
	var line := msg
	if line == "":
		line = "%d of %d measures are more than 10 %% off a %s: see Yours vs real cars" % [reds, CarPackage.METRICS.size(), String(p.get("class", "")).to_lower()] if reds > 0 else "Every measure is within 10 %% of the real %s cars" % String(p.get("class", "")).to_lower()
	status_l.text = line


func _build_3d(p: Dictionary) -> void:
	if car3d != null:
		world.remove_child(car3d)
		car3d.free()
	car3d = CarPackage.build_3d(p)
	world.add_child(car3d)
	built_3d += 1


func _build_compare(p: Dictionary) -> void:
	var near := CarPackage.nearest(p, CarPackage.derive(p))
	cmp_head.text = "Yours: %s class. Nearest real car: %s (length, width, height and wheelbase)" % [String(p.get("class", "")), String(near.get("name", "none"))]
	for c in cmp_box.get_children():
		cmp_box.remove_child(c)
		c.queue_free()
	var hd := GridContainer.new()
	hd.columns = 4
	hd.name = "package_cmp_head"
	cmp_box.add_child(hd)
	for t in ["Measure", "Yours", "Real", "Diff"]:
		var l := Label.new()
		l.text = t
		l.add_theme_font_size_override("font_size", 13)
		l.modulate = Color(1, 1, 1, 0.7)
		l.custom_minimum_size = Vector2(60, 0) if t != "Measure" else Vector2(120, 0)
		hd.add_child(l)
	for r in CarPackage.rows(p):
		var box := VBoxContainer.new()
		box.name = "package_cmp_" + String(r["key"])
		box.set_meta("red", bool(r["red"]))
		cmp_box.add_child(box)
		var g := GridContainer.new()
		g.columns = 4
		box.add_child(g)
		var col := RED if bool(r["red"]) else Color(1, 1, 1)
		var cells := [String(r["label"]), str(int(round(float(r["yours"])))), str(int(round(float(r["real"])))),
			("%+d" % int(round(float(r["diff"]))))]
		for i in 4:
			var l := Label.new()
			l.text = cells[i]
			l.add_theme_font_size_override("font_size", 14)
			l.add_theme_color_override("font_color", col)
			l.custom_minimum_size = Vector2(120, 0) if i == 0 else Vector2(60, 0)
			g.add_child(l)
		if bool(r["red"]):
			var h := Label.new()
			h.name = "package_hint_" + String(r["key"])
			h.text = "  " + String(r["hint"])
			h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			h.add_theme_font_size_override("font_size", 13)
			h.add_theme_color_override("font_color", RED)
			box.add_child(h)


## the rows the screen shows now (for the tests): [{key, red, yours, real, hint}]
func compare_rows() -> Array:
	return CarPackage.rows(pkg())


## the camera: the car from the front-left, the whole package in the view
func frame() -> void:
	var p := pkg()
	if p.is_empty():
		return
	var L := float(CarPackage.derive(p)["length"]) * 0.001
	var dist := maxf(L * 1.3, 4.0)
	var at := Vector3(0.0, 0.5, 0.0)
	cam.position = at + Vector3(-dist * 0.75, dist * 0.38, dist * 0.62)
	cam.look_at(at, Vector3.UP)


func layout() -> void:
	var vs := get_viewport_rect().size
	var top := float(m.TOP_H)
	var avail := vs.y - top - 52.0
	var vw := vs.x - PW - 16.0
	var ph := avail * 0.62
	plan.position = Vector2(0.0, top)
	plan.size = Vector2(vw, ph)
	view.position = Vector2(0.0, top + ph + 4.0)
	view.size = Vector2(vw, avail - ph - 6.0)
	if vp != null and vp.size != Vector2i(int(vw), int(avail - ph - 6.0)) and vw > 1.0 and avail - ph - 6.0 > 1.0:
		vp.size = Vector2i(int(vw), int(avail - ph - 6.0))
	panel.position = Vector2(vs.x - PW - 8.0, top + 6.0)
	panel.size = Vector2(PW, vs.y - top - 12.0)
	status.position = Vector2(12.0, top + avail + 6.0)
	status.size = Vector2(vw - 24.0, 40.0)


func _process(_dt: float) -> void:
	if not visible:
		return
	if vp != null and view != null and view.size.x > 1.0 and vp.size != Vector2i(view.size):
		layout()