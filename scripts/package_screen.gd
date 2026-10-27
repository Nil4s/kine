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
const STEP_NAMES := ["1 Package", "2 Chassis", "3 Suspension", "4 Weight", "5 Body"]
const STEP_TIPS := ["the hard points: seat, wheelbase, tracks, tyres", "the steel floor structure: sills, rails, crossmembers", "the wheels on their arms: front and rear types, wheel tilt, steering axis, roll centre, bounce", "the mass of every part and where it sits: the axle loads, the balance, the centre of gravity", "not made yet"]
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
var drive_opt: OptionButton      # the drive side: Left drive / Right drive
var door_hint: Label             # red under the door readout when the seat is too close to the door
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
var show_3d := false           # the drawing area shows the 3D preview instead of the side + top views (one click on view_btn)
var view_btn: Button
var built_3d := 0              # the 3D preview rebuilds (the test counts them)
var step := 1                  # 1 Package (the hard points), 2 Chassis (the floor structure, carchassis)
var step_btns := {}            # step number -> its bar button
var chassis_panel: PanelContainer
var ch_rows := {}              # group -> {"btns": {word: Button}, "edits": [w, h, t LineEdit]}
var ch_mat: OptionButton
var ch_read: Label             # the chassis readouts (mass per group, the structure, I, E I, the body in white)
var ch_compare: Label
var susp_panel: PanelContainer     # step 3 SUSPENSION (carsusp): the types, Bounce, the readouts with their typical ranges
var susp_plan: CarSuspPlan         # the front view and the side view of the suspension (step 3)
var sp_front: OptionButton
var sp_rear: OptionButton
var sp_bounce: HSlider
var sp_pill: Label
var sp_read := {}                  # readout key -> Label
var sp_hint := {}                  # readout key -> red hint Label (hidden when inside the typical range)
var sp_travel: Label               # the wheel travel: tilt and track at full bump and full rebound
var sp_clear: Label                # the clearance to the chassis at full bump
var bounce := 0.0                  # Bounce, mm (+ = the wheel lifts). A view control: not saved, not an undo step
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
	var home_b: Button = m._home_button()   # the way back to the start screen, as on every bar (the Easy BUILD bar is hidden under this screen)
	home_b.custom_minimum_size = Vector2(110, m.TOP_H - 12)
	home_b.add_theme_font_size_override("font_size", 15)
	home_b.pressed.connect(close)   # Home leaves the package too: the BUILD bar comes back when BUILD is shown again
	row.add_child(home_b)
	row.add_child(_bar_btn("Back to BUILD", "Leave the package: the numbers stay as they are", close))
	title_l = Label.new()
	title_l.name = "package_title"
	title_l.add_theme_font_size_override("font_size", 20)
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title_l)
	# the step bar: 1 Package to 4 Weight are made; 5 Body is greyed (not made yet)
	var steps := HBoxContainer.new()
	steps.name = "package_steps"
	steps.add_theme_constant_override("separation", 4)
	row.add_child(steps)
	for i in STEP_NAMES.size():
		var sb := _bar_btn(STEP_NAMES[i], "Step %d: %s" % [i + 1, STEP_TIPS[i]], set_step.bind(i + 1))
		sb.name = "package_step_%d" % (i + 1)
		sb.toggle_mode = true
		if i >= 4:
			sb.disabled = true
			sb.tooltip_text = "Step %d: not made yet. The body comes after the weight" % (i + 1)
		steps.add_child(sb)
		step_btns[i + 1] = sb
	undo_btn = _bar_btn("Undo", "Take back the last change", func(): m._undo())
	redo_btn = _bar_btn("Redo", "Put back what Undo took back", func(): m._redo())
	view_btn = _bar_btn("See it in 3D", "Swap the side and top drawings for a 3D view of the package", func(): set_3d(not show_3d))
	view_btn.name = "package_view_btn"
	row.add_child(view_btn)
	row.add_child(undo_btn)
	row.add_child(redo_btn)
	# the layout (side and top views), the 3D view under it
	plan = CarPlan.new()
	plan.name = "package_plan"
	plan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plan)
	susp_plan = CarSuspPlan.new()
	susp_plan.name = "suspension_plan"
	susp_plan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	susp_plan.visible = false
	add_child(susp_plan)
	weight_plan = CarWeightPlan.new()   # step 4: the parts over the drawings (added after the plan, so it takes the mouse first)
	weight_plan.name = "weight_plan"
	weight_plan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weight_plan.visible = false
	weight_plan.under = plan
	weight_plan.moved.connect(_on_weight_moved)
	add_child(weight_plan)
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
	sec_hp.add_child(_drive_row())
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
			["door", "Seat to the door", "Door room: half the body width minus the seat from the middle and half a seat width (250 mm); needs 100 mm"],
			["feet", "Feet clear of the front wheel", "Feet clear: the heel point (seat from the front wheel minus the seated thigh + shin reach along the floor) must be behind the front axle by the tyre radius + 100 mm"]]:
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # the long feet line wraps instead of widening the panel
		l.name = "package_read_" + String(rr[0])
		l.tooltip_text = String(rr[2])
		l.add_theme_font_size_override("font_size", 15)
		rd.add_child(l)
		readouts[String(rr[0])] = l
	door_hint = Label.new()
	door_hint.name = "package_hint_door"
	door_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	door_hint.add_theme_font_size_override("font_size", 13)
	door_hint.add_theme_color_override("font_color", RED)
	rd.add_child(door_hint)
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
	_build_chassis_panel()
	_build_susp_panel()
	_build_weight_panel()
	_show_tab(true)
	set_step(1)
	layout()


## STEP 2 CHASSIS: the right panel of the chassis (carchassis): each member group's section (Easy: a size word; Expert: w, h, wall in mm),
## the material, and the readouts (mass, I, E I, the body in white). Shown instead of the hard points on step 2
func _build_chassis_panel() -> void:
	chassis_panel = PanelContainer.new()
	chassis_panel.name = "chassis_panel"
	chassis_panel.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.95), 10, 8))
	chassis_panel.position = Vector2.ZERO
	chassis_panel.visible = false
	add_child(chassis_panel)
	var v := VBoxContainer.new()
	v.name = "chassis_panel_vb"
	v.add_theme_constant_override("separation", 5)
	chassis_panel.add_child(v)
	var hd := Label.new()
	hd.text = "Chassis: the steel floor structure"
	hd.tooltip_text = "The floor structure is drawn from the package: box sections (a closed tube with a wall) along the sills, rails and crossmembers"
	hd.add_theme_font_size_override("font_size", 14)
	v.add_child(hd)
	var sc := ScrollContainer.new()
	sc.name = "chassis_scroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var body := VBoxContainer.new()
	body.name = "chassis_body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	sc.add_child(body)
	for g in CarChassis.GROUPS:
		var box := VBoxContainer.new()
		box.name = "chassis_row_" + g
		box.tooltip_text = String(CarChassis.GROUP_TIPS[g])
		box.add_theme_constant_override("separation", 2)
		body.add_child(box)
		var lab := Label.new()
		lab.text = String(CarChassis.GROUP_NAMES[g])
		lab.tooltip_text = box.tooltip_text
		lab.add_theme_font_size_override("font_size", 15)
		box.add_child(lab)
		var bd := {"btns": {}, "edits": []}
		var btns := HBoxContainer.new()
		btns.add_theme_constant_override("separation", 3)
		box.add_child(btns)
		for word in CarChassis.SIZE_WORDS:
			var s: Array = CarChassis.SIZES[word]
			var b := _small_btn(String(word), "%s: %d x %d mm, wall %s mm (width x height x wall)" % [word, int(s[0]), int(s[1]), str(s[2])], set_group_size.bind(g, String(word)))
			b.toggle_mode = true
			b.name = "chassis_%s_%s" % [g, String(word).to_lower()]
			btns.add_child(b)
			(bd["btns"] as Dictionary)[word] = b
		var ed_row := HBoxContainer.new()
		ed_row.add_theme_constant_override("separation", 3)
		box.add_child(ed_row)
		for part in [["w", "width (w)"], ["h", "height (h)"], ["t", "wall (t)"]]:
			var e := LineEdit.new()
			e.name = "chassis_edit_%s_%s" % [g, part[0]]
			e.custom_minimum_size = Vector2(0, 30)
			e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			e.placeholder_text = "%s mm" % part[0]
			e.tooltip_text = "%s of the box section, mm. Type a number, then click away from the box" % part[1]
			e.text_submitted.connect(func(_t: String): _typed_chassis(g))
			e.focus_exited.connect(func(): _typed_chassis(g))
			ed_row.add_child(e)
			(bd["edits"] as Array).append(e)
		ch_rows[g] = bd
	var mrow := HBoxContainer.new()
	mrow.name = "chassis_row_mat"
	mrow.tooltip_text = "Material: density sets the mass; Young modulus E sets the stiffness (steel 210 GPa, aluminium 70 GPa)"
	body.add_child(mrow)
	var ml := Label.new()
	ml.text = "Material"
	ml.tooltip_text = mrow.tooltip_text
	ml.add_theme_font_size_override("font_size", 15)
	mrow.add_child(ml)
	ch_mat = OptionButton.new()
	ch_mat.name = "chassis_mat_pick"
	ch_mat.focus_mode = Control.FOCUS_NONE
	ch_mat.tooltip_text = mrow.tooltip_text
	for mt in CarChassis.MATS:
		ch_mat.add_item(String(mt[0]))
	ch_mat.item_selected.connect(func(i: int): _set_mat(String(CarChassis.MATS[i][0])))
	mrow.add_child(ch_mat)
	ch_read = Label.new()
	ch_read.name = "chassis_read"
	ch_read.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ch_read.add_theme_font_size_override("font_size", 14)
	ch_read.tooltip_text = "mass: density x wall area x length (the wall area is 2 x wall x (width + height - 2 x wall)). second moment of area I: the section's stiffness against bending, mm4. E I: Young modulus x I, the sill's bending stiffness in N m2. body in white: the structure x 1.6 for the panels"
	body.add_child(ch_read)
	ch_compare = Label.new()
	ch_compare.name = "chassis_compare"
	ch_compare.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ch_compare.add_theme_font_size_override("font_size", 14)
	ch_compare.tooltip_text = "Yours vs the real cars: a real car's body-in-white mass is compared only where data/real_cars.json gives one with a source"
	body.add_child(ch_compare)


## the steps: 1 Package (the hard points), 2 Chassis (the floor structure over the package), 3 Suspension (the wheels on their arms),
## 4 Weight and balance (the parts' masses and places). One click switches; the package stays as it is
func set_step(n: int) -> void:
	if n < 1 or n > 4:
		return
	if n >= 2:
		ensure()
	step = n
	msg = ""
	panel.visible = step == 1
	chassis_panel.visible = step == 2
	susp_panel.visible = step == 3
	susp_plan.visible = step == 3
	weight_panel.visible = step == 4
	weight_plan.visible = step == 4
	weight_plan.mouse_filter = Control.MOUSE_FILTER_STOP if step == 4 else Control.MOUSE_FILTER_IGNORE
	for i in step_btns:
		(step_btns[i] as Button).set_pressed_no_signal(i == step)
	layout()
	_sync()


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


## the drive side (Left / Right), one undo step; a side that is already set is no step
func _drive_row() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.name = "package_row_drive"
	v.tooltip_text = "Drive side: the side the driver sits on. Left drive puts the driver's hip on the car's left, Right drive on the right"
	var lab := Label.new()
	lab.text = "Drive side"
	lab.tooltip_text = v.tooltip_text
	lab.add_theme_font_size_override("font_size", 15)
	v.add_child(lab)
	drive_opt = OptionButton.new()
	drive_opt.name = "package_drive_pick"
	drive_opt.focus_mode = Control.FOCUS_NONE
	drive_opt.add_item("Left drive")
	drive_opt.add_item("Right drive")
	drive_opt.item_selected.connect(func(i: int): _set_drive(String(CarPackage.DRIVES[i])))
	v.add_child(drive_opt)
	return v


func _set_drive(side: String) -> void:
	ensure()
	if String(pkg().get("drive", "Left")) == side:
		_sync()
		return
	_begin("Change drive side")
	pkg()["drive"] = side
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
	for g in ch_rows:
		for b in (ch_rows[g]["btns"] as Dictionary).values():
			(b as Button).visible = easy
		for e in ch_rows[g]["edits"]:
			(e as LineEdit).visible = not easy


# ---------------------------------------------------------------- step 2: the chassis (one undo step per change)

## the chassis record (S.vehicle["chassis"], filled in when missing): {mat, g: {group: {size, w, h, t}}}
func chassis() -> Dictionary:
	return CarChassis.norm(m.S.vehicle.get("chassis", {}))


## a chassis change: one undo step; a change that changes nothing is no step
func _set_chassis(label: String, c: Dictionary) -> void:
	ensure()
	if JSON.stringify(c) == JSON.stringify(chassis()):
		_sync()
		return
	m._step_hint = label
	m._push_undo()
	m.S.vehicle["chassis"] = c
	msg = ""
	_sync()


## one group's section by its size word (Easy)
func set_group_size(g: String, word: String) -> void:
	var c := chassis()
	c["g"][g] = CarChassis.sec_of_word(word)
	_set_chassis("Change %s to %s" % [String(CarChassis.GROUP_NAMES[g]).to_lower(), word.to_lower()], c)


## one group's section typed in mm (Expert): the width, height and wall; a size that matches a word keeps the word
func _typed_chassis(g: String) -> void:
	if not is_instance_valid(chassis_panel) or not m.S.vehicle.has("package"):
		return
	var vals := []
	for e in ch_rows[g]["edits"]:
		var t := (e as LineEdit).text.strip_edges()
		if not t.is_valid_float():
			msg = "Type the width, height and wall in mm, like 80, 60 and 1.5"
			_sync()
			return
		vals.append(float(t))
	if not CarChassis.valid(vals[0], vals[1], vals[2]):
		msg = "A section needs sides of 20 to 300 mm and a wall from 0.8 to 6 mm, less than half the smaller side"
		_sync()
		return
	var word := "Custom"
	for w in CarChassis.SIZE_WORDS:
		var s: Array = CarChassis.SIZES[w]
		if absf(float(s[0]) - vals[0]) < 1e-6 and absf(float(s[1]) - vals[1]) < 1e-6 and absf(float(s[2]) - vals[2]) < 1e-6:
			word = String(w)
	var c := chassis()
	c["g"][g] = {"size": word, "w": vals[0], "h": vals[1], "t": vals[2]}
	_set_chassis("Change %s section" % String(CarChassis.GROUP_NAMES[g]).to_lower(), c)


## the material (one undo step)
func _set_mat(name: String) -> void:
	var c := chassis()
	c["mat"] = name
	_set_chassis("Change material to %s" % name.to_lower(), c)


## the chassis panel's words and numbers from the record
func _sync_chassis() -> void:
	var c := chassis()
	var p := pkg()
	for g in ch_rows:
		var sec: Dictionary = c["g"][g]
		for word in (ch_rows[g]["btns"] as Dictionary):
			(ch_rows[g]["btns"][word] as Button).set_pressed_no_signal(String(sec["size"]) == String(word))
		var keys := ["w", "h", "t"]
		for i in 3:
			var e: LineEdit = ch_rows[g]["edits"][i]
			if not e.has_focus():
				e.text = _num(float(sec[keys[i]]))
	for i in CarChassis.MATS.size():
		if String(CarChassis.MATS[i][0]) == String(c["mat"]):
			ch_mat.select(i)
	var tot := CarChassis.totals(p, c)
	var mem := CarChassis.members(p, c)
	var lines := []
	for g in CarChassis.GROUPS:
		var n := 0
		for mm in mem:
			n += 1 if String(mm["group"]) == g else 0
		var sec: Dictionary = c["g"][g]
		lines.append("%s: %.1f kg (%d members, %s x %s x %s mm)" % [CarChassis.GROUP_NAMES[g], float(tot["by"][g]), n, _num(float(sec["w"])), _num(float(sec["h"])), _num(float(sec["t"]))])
	lines.append("Structure: %.1f kg (floor pan drawn, not weighed)" % float(tot["mass"]))
	lines.append("Sill (rocker), one: I %d mm4, E I %.0f N m2 (both sills %.0f N m2)" % [int(round(float(tot["sill_I"]))), float(tot["sill_EI"]), float(tot["sill_EI_pair"])])
	ch_read.text = "\n".join(lines)
	ch_compare.text = CarChassis.biw_compare(p, c)


func _num(v: float) -> String:
	return str(int(v)) if absf(v - round(v)) < 1e-6 else str(snappedf(v, 0.01))


# ---------------------------------------------------------------- step 3: the suspension (carsusp; one undo step per choice)


## the step 3 panel: the front and rear types, Bounce, the readouts with their typical ranges (red with a plain hint outside), the travel and the clearance
func _build_susp_panel() -> void:
	susp_panel = PanelContainer.new()
	susp_panel.name = "susp_panel"
	susp_panel.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.95), 10, 8))
	susp_panel.position = Vector2.ZERO
	susp_panel.visible = false
	add_child(susp_panel)
	var v := VBoxContainer.new()
	v.name = "susp_panel_vb"
	v.add_theme_constant_override("separation", 5)
	susp_panel.add_child(v)
	var hd := Label.new()
	hd.text = "Suspension: the wheels on their arms"
	hd.tooltip_text = "The hard points hang each wheel from the body: the arms and the knuckle, drawn in the front view and the side view"
	hd.add_theme_font_size_override("font_size", 14)
	v.add_child(hd)
	var sc := ScrollContainer.new()
	sc.name = "susp_scroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var body := VBoxContainer.new()
	body.name = "susp_body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	sc.add_child(body)
	sp_front = _pick_row(body, "Front", "susp_front_pick", "Front: a MacPherson strut (a spring strut that is also the steering axis, compact and cheap) or double wishbones (two arms per wheel, the most tuning room)", CarSusp.FRONT_OPTS)
	sp_front.item_selected.connect(func(i: int): _set_front(i))
	sp_rear = _pick_row(body, "Rear", "susp_rear_pick", "Rear: a twist beam (one trailing arm per side, simple and cheap) or multilink (several links per wheel, the wheel keeps its tilt better)", CarSusp.REAR_OPTS)
	sp_rear.item_selected.connect(func(i: int): _set_rear(i))
	var brow := HBoxContainer.new()
	brow.name = "susp_bounce_row"
	brow.tooltip_text = "Bounce: lift the wheel (plus) or let it drop (minus) with the body held still, up to %d mm. A view only: not saved, not an undo step" % int(CarSusp.TRAVEL)
	body.add_child(brow)
	var bl := Label.new()
	bl.text = "Bounce"
	bl.tooltip_text = brow.tooltip_text
	bl.add_theme_font_size_override("font_size", 15)
	brow.add_child(bl)
	sp_bounce = HSlider.new()
	sp_bounce.name = "susp_bounce"
	sp_bounce.min_value = -CarSusp.TRAVEL
	sp_bounce.max_value = CarSusp.TRAVEL
	sp_bounce.step = 1.0
	sp_bounce.focus_mode = Control.FOCUS_NONE
	sp_bounce.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp_bounce.custom_minimum_size = Vector2(120, 22)
	sp_bounce.tooltip_text = brow.tooltip_text
	sp_bounce.value_changed.connect(func(f: float): _on_bounce(f))
	brow.add_child(sp_bounce)
	sp_pill = Label.new()
	sp_pill.name = "susp_bounce_pill"
	sp_pill.custom_minimum_size = Vector2(70, 0)
	sp_pill.add_theme_font_size_override("font_size", 14)
	brow.add_child(sp_pill)
	var rows_def := [
		["camber", "Wheel tilt (camber)", "Camber: the lean of the wheel from vertical, seen from the front; top leaning in is minus. camber = atan2(W_y - C_y, W_z - C_z): W the wheel centre, C the contact patch. Typical -2 to 0 deg"],
		["kpi", "Steering tilt (KPI)", "Kingpin inclination (KPI): the steering axis from vertical, seen from the front; top leaning in is plus. KPI = atan2(L_y - T_y, T_z - L_z): L the lower ball joint, T the top. Typical 8 to 16 deg"],
		["scrub", "Scrub radius", "Scrub radius: on the ground, the distance from the steering axis to the middle of the tyre contact patch; plus = the axis is inboard. scrub = C_y - G_y, G where the axis meets the ground. Typical -20 to +60 mm"],
		["caster", "Caster (steering lean)", "Caster: the steering axis from vertical, seen from the side; top leaning back is plus. caster = atan2(L_x - T_x, T_z - L_z). Typical 2 to 8 deg"],
		["trail", "Trail (mechanical)", "Mechanical trail: the ground trail (G_x - C_x, G from the steering axis) times cos(caster), along the wheel plane. A bigger trail gives more self-centring"],
		["rc", "Roll centre height", "Roll centre (front): where the body rolls about, from the instant centre IC of the arms; the line C to IC crosses the centreline. Typical 0 to 150 mm"],
	]
	for rd in rows_def:
		var key: String = rd[0]
		var l := Label.new()
		l.name = "susp_read_" + key
		l.tooltip_text = String(rd[2])
		l.add_theme_font_size_override("font_size", 14)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(l)
		sp_read[key] = l
		var h := Label.new()
		h.name = "susp_hint_" + key
		h.add_theme_font_size_override("font_size", 13)
		h.add_theme_color_override("font_color", RED)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.visible = false
		body.add_child(h)
		sp_hint[key] = h
	sp_travel = Label.new()
	sp_travel.name = "susp_travel"
	sp_travel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sp_travel.add_theme_font_size_override("font_size", 13)
	sp_travel.tooltip_text = "Wheel travel: the wheel moves up and down by Bounce with the body held still. Wheel tilt and track (the spacing of the contact patches) change through the travel"
	body.add_child(sp_travel)
	sp_clear = Label.new()
	sp_clear.name = "susp_clear"
	sp_clear.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sp_clear.add_theme_font_size_override("font_size", 13)
	sp_clear.tooltip_text = "Clearance: the smallest gap between a tyre and any chassis member (sill, rail, crossmember) at full bump and full rebound. Red when they touch"
	body.add_child(sp_clear)
	var typ := Label.new()
	typ.name = "susp_typical"
	typ.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	typ.add_theme_font_size_override("font_size", 12)
	typ.modulate = Color(1, 1, 1, 0.7)
	typ.text = "Typical road car: wheel tilt -2 to 0 deg, steering tilt 8 to 16 deg, scrub -20 to +60 mm, caster 2 to 8 deg, roll centre 0 to 150 mm."
	typ.tooltip_text = "Ranges from Milliken and Milliken, Race Car Vehicle Dynamics (1995), and Reimpell, Stoll and Betzler, The Automotive Chassis (2001); as recalled, not checked against the books"
	body.add_child(typ)


## one choice row: a label and a pick list (mouse only). Returns the list
func _pick_row(parent: Control, label: String, nm: String, tip: String, items: Array) -> OptionButton:
	var row := HBoxContainer.new()
	row.name = nm + "_row"
	row.tooltip_text = tip
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.tooltip_text = tip
	l.custom_minimum_size = Vector2(60, 0)
	l.add_theme_font_size_override("font_size", 15)
	row.add_child(l)
	var ob := OptionButton.new()
	ob.name = nm
	ob.focus_mode = Control.FOCUS_NONE
	ob.tooltip_text = tip
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for it in items:
		ob.add_item(String(it))
	row.add_child(ob)
	return ob


## the suspension record (S.vehicle["susp"], filled in when missing)
func susp() -> Dictionary:
	return CarSusp.norm(m.S.vehicle.get("susp", {}))


## a suspension change: one undo step; a change that changes nothing is no step
func _set_susp(label: String, rec: Dictionary) -> void:
	ensure()
	if JSON.stringify(rec) == JSON.stringify(susp()):
		_sync()
		return
	m._step_hint = label
	m._push_undo()
	m.S.vehicle["susp"] = rec
	msg = ""
	_sync()


func _set_front(i: int) -> void:
	var rec := susp()
	rec["front"] = CarSusp.FRONT_OPTS[clampi(i, 0, CarSusp.FRONT_OPTS.size() - 1)]
	_set_susp("Front suspension: %s" % String(rec["front"]), rec)


func _set_rear(i: int) -> void:
	var rec := susp()
	rec["rear"] = CarSusp.REAR_OPTS[clampi(i, 0, CarSusp.REAR_OPTS.size() - 1)]
	_set_susp("Rear suspension: %s" % String(rec["rear"]), rec)


## Bounce: the view only (no undo step, not saved); the drawings and the 3D follow
func _on_bounce(v: float) -> void:
	bounce = clampf(round(v), -CarSusp.TRAVEL, CarSusp.TRAVEL)
	_sync()


func _num_or_none(v: float, unit: String) -> String:
	return "none" if is_nan(v) else "%d %s" % [int(round(v)), unit]


## the step 3 panel's words and numbers: the static readouts (Bounce 0) with their ranges, the travel and the clearance
func _sync_susp() -> void:
	var rec := susp()
	var p := pkg()
	var cc := chassis()
	sp_front.select(maxi(0, CarSusp.FRONT_OPTS.find(String(rec["front"]))))
	sp_rear.select(maxi(0, CarSusp.REAR_OPTS.find(String(rec["rear"]))))
	sp_bounce.set_value_no_signal(bounce)
	sp_pill.text = "%+d mm" % int(bounce)
	var r := CarSusp.readouts(p, cc, rec, 0.0)
	var units := {"camber": "deg", "kpi": "deg", "scrub": "mm", "caster": "deg", "rc": "mm"}
	for row in CarSusp.checks(p, cc, rec):
		var key := String(row["key"])
		var v := float(row["value"])
		var red := bool(row["red"]) and not is_nan(v)
		var shown := "none" if is_nan(v) else "%s %s" % [str(snappedf(v, 0.1)), units[key]]
		var nm := "Steering tilt (KPI)" if key == "kpi" else String(CarSusp.RANGE_WORDS[key])
		(sp_read[key] as Label).text = "%s  %s" % [nm, shown]
		(sp_read[key] as Label).add_theme_color_override("font_color", RED if red else Color(1, 1, 1))
		(sp_hint[key] as Label).text = "  " + String(row["hint"]) if red else ""
		(sp_hint[key] as Label).visible = red
	sp_read["trail"].text = "Trail (mechanical)  %s" % _num_or_none(float(r["trail"]), "mm")
	var up := CarSusp.readouts(p, cc, rec, CarSusp.TRAVEL)
	var dn := CarSusp.readouts(p, cc, rec, -CarSusp.TRAVEL)
	sp_travel.text = "Full bump (+%d mm): wheel tilt %s deg, track %d mm. Full rebound (-%d mm): wheel tilt %s deg, track %d mm." % [int(CarSusp.TRAVEL),
		str(snappedf(float(up["camber"]), 0.1)), int(round(float(up["track"]))), int(CarSusp.TRAVEL), str(snappedf(float(dn["camber"]), 0.1)), int(round(float(dn["track"])))]
	var clr := minf(CarSusp.clearance(p, cc, rec, CarSusp.TRAVEL), CarSusp.clearance(p, cc, rec, -CarSusp.TRAVEL))
	sp_clear.text = "Clearance to the chassis at full bump or rebound: %d mm%s" % [int(round(clr)), "" if clr >= 0.0 else ": the tyre hits the chassis"]
	sp_clear.add_theme_color_override("font_color", RED if clr < 0.0 else Color(1, 1, 1))
	susp_plan.set_data(p, cc, rec, bounce)


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
	drive_opt.select(maxi(0, CarPackage.DRIVES.find(String(p.get("drive", "Left")))))
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
	var dok := bool(d["door_ok"])
	readouts["door"].text = "Seat to the door  %d mm (needs 100)" % int(d["door_gap"])
	readouts["door"].add_theme_color_override("font_color", Color(1, 1, 1) if dok else RED)
	door_hint.text = "" if dok else "  the driver is too close to the door"
	door_hint.visible = not dok
	for c in CarPackage.CLASSES:
		(cls_btns[String(c[0])] as Button).set_pressed_no_signal(String(c[0]) == String(p.get("class", "")))
	plan.set_points(p)
	plan.set_chassis(chassis() if step == 2 or step == 4 else {})
	_build_3d(p)
	_build_compare(p)
	if step == 2:
		_sync_chassis()
	if step == 3:
		_sync_susp()
	if step == 4:
		_sync_weight()
	title_l.text = "Vehicle: chassis, %s" % String(p.get("class", "")) if step == 2 else "Vehicle: suspension, %s" % String(p.get("class", "")) if step == 3 else "Vehicle: weight and balance, %s" % String(p.get("class", "")) if step == 4 else "Vehicle: package, %s" % String(p.get("class", "")) if not p.is_empty() else "Vehicle: package"
	undo_btn.disabled = m.undo.is_empty()
	redo_btn.disabled = m.redo.is_empty()
	var reds := 0
	for r in CarPackage.rows(p):
		reds += 1 if r["red"] else 0
	var line := msg
	if line == "" and step == 2:
		var tot := CarChassis.totals(p, chassis())
		line = "Chassis: the structure weighs %.1f kg. Change a size, or type a section in mm. Each change is one undo step" % float(tot["mass"])
	elif line == "" and step == 3:
		line = "Front: %s. Rear: %s. One undo step per choice; Bounce is not saved" % [String(susp()["front"]), String(susp()["rear"])]
	elif line == "" and step == 4:
		line = _wt_status()
	elif line == "":
		line = "%d of %d measures are more than 10 %% off a %s: see Yours vs real cars" % [reds, CarPackage.METRICS.size(), String(p.get("class", "")).to_lower()] if reds > 0 else "Every measure is within 10 %% of the real %s cars" % String(p.get("class", "")).to_lower()
	status_l.text = line


func _build_3d(p: Dictionary) -> void:
	if car3d != null:
		world.remove_child(car3d)
		car3d.free()
	car3d = CarChassis.build_3d(p, chassis()) if step >= 2 else CarPackage.build_3d(p)   # steps 2 and 3: the members as boxes, over the package
	if step == 3:
		car3d.add_child(CarSusp.build_3d(p, chassis(), susp(), bounce))   # the arms, knuckles and tyres at the Bounce
	if step == 4:
		car3d.add_child(CarWeight.build_3d(p, chassis(), susp(), weight()))   # the parts as blocks at their places, the centre of gravity as a sphere
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


## the camera close to the front-left corner (step 3): the arms, the knuckle and the wheel read clearly
func frame_corner() -> void:
	var p := pkg()
	if p.is_empty():
		return
	var at := Vector3(float(p["track_f"]) * 0.5 * 0.001 - 0.15, 0.25, float(p["wheelbase"]) * 0.5 * 0.001 - 0.05)   # the front-left arms, 3D metres
	cam.position = at + Vector3(0.8, 0.9, 1.6)   # close to the corner, above and in front
	cam.look_at(at, Vector3.UP)


func layout() -> void:
	var vs := get_viewport_rect().size
	var top := float(m.TOP_H)
	var avail := vs.y - top - 52.0
	var vw := vs.x - PW - 16.0
	# the drawings and the 3D view share the whole area, one at a time: stacked, the drawings were height-bound to ~26 % of the width
	plan.position = Vector2(0.0, top)
	plan.size = Vector2(vw, avail)
	view.position = plan.position
	view.size = plan.size
	plan.visible = not show_3d and step != 3
	susp_plan.position = plan.position
	susp_plan.size = plan.size
	susp_plan.visible = not show_3d and step == 3
	view.visible = show_3d
	if vp != null:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if show_3d else SubViewport.UPDATE_DISABLED
		if vp.size != Vector2i(int(vw), int(avail)) and vw > 1.0 and avail > 1.0:
			vp.size = Vector2i(int(vw), int(avail))
	panel.position = Vector2(vs.x - PW - 8.0, top + 6.0)
	panel.size = Vector2(PW, vs.y - top - 12.0)
	if chassis_panel != null:
		chassis_panel.position = panel.position
		chassis_panel.size = panel.size
	if susp_panel != null:
		susp_panel.position = panel.position
		susp_panel.size = panel.size
	if weight_panel != null:
		weight_panel.position = panel.position
		weight_panel.size = panel.size
	if weight_plan != null:
		weight_plan.position = plan.position
		weight_plan.size = plan.size
		weight_plan.visible = not show_3d and step == 4
	status.position = Vector2(12.0, top + avail + 6.0)
	status.size = Vector2(vw - 24.0, 40.0)


func _process(_dt: float) -> void:
	if not visible:
		return
	if vp != null and view != null and view.size.x > 1.0 and vp.size != Vector2i(view.size):
		layout()


## one click swaps the drawings for the 3D view and back
func set_3d(on: bool) -> void:
	show_3d = on
	if view_btn != null:
		view_btn.text = "See the drawings" if on else "See it in 3D"
	layout()


# ---------------------------------------------------------------- step 4: weight and balance (carweight; one undo step per change)
var weight_panel: PanelContainer      # step 4 WEIGHT AND BALANCE: the drive layout, the fuel, the passengers, the cargo, the readouts
var weight_plan: CarWeightPlan        # the placeable parts drawn over the side and top views, dragged with the mouse (step 4)
var wt_layout: OptionButton
var wt_sl := {}                       # key (fuel, pax, cargo) -> HSlider
var wt_pill := {}                     # key -> Label (the value beside the name)
var wt_read := {}                     # readout key -> Label
var wt_hint := {}                     # compare key -> red hint Label
var wt_cmp := {}                      # compare key -> Label
var wt_parts: Label                   # every part's mass, the estimates named
var wt_held := false
var wt_before := ""
var wt_n := -1
var wt_last_ms := 0


## the step 4 panel: the drive layout, the fuel, the passengers and the cargo, the readouts, the compare
func _build_weight_panel() -> void:
	weight_panel = PanelContainer.new()
	weight_panel.name = "weight_panel"
	weight_panel.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.95), 10, 8))
	weight_panel.position = Vector2.ZERO
	weight_panel.visible = false
	add_child(weight_panel)
	var v := VBoxContainer.new()
	v.name = "weight_panel_vb"
	v.add_theme_constant_override("separation", 5)
	weight_panel.add_child(v)
	var hd := Label.new()
	hd.text = "Weight and balance: where the mass sits"
	hd.tooltip_text = "Every part's mass and where it sits. Drag a part on the drawings: one undo step per drag"
	hd.add_theme_font_size_override("font_size", 14)
	v.add_child(hd)
	var sc := ScrollContainer.new()
	sc.name = "weight_scroll"
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	var body := VBoxContainer.new()
	body.name = "weight_body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	sc.add_child(body)
	wt_layout = _pick_row(body, "Drive", "weight_layout_pick", "Drive layout: where the engine and the fuel sit. Choosing one moves the parts to its usual places (one undo step)", CarWeight.LAYOUTS)
	wt_layout.item_selected.connect(func(i: int): _set_layout(i))
	_wt_slider(body, "Fuel in the tank", "weight_fuel", "Fuel: the litres in the tank. Petrol is about 0.74 kg per litre (estimate). Drag it", "fuel", 0.0, 70.0, 1.0)
	_wt_slider(body, "Passengers", "weight_pax", "Passengers: 0 to 4 adults, each about 75 kg (estimate). They sit in the seat positions", "pax", 0.0, float(CarWeight.PAX_MAX), 1.0)
	_wt_slider(body, "Cargo", "weight_cargo", "Cargo: a load in the boot or the bed, in kg. Drag it", "cargo", 0.0, CarWeight.KG_MAX, 5.0)
	var rd := VBoxContainer.new()
	rd.name = "weight_readouts"
	body.add_child(rd)
	for pair in [["total", "Total mass", "Total mass: the sum of every part's mass (the parts marked estimate are typed estimates)"],
			["front", "Weight on the front wheels", "front axle load: the share of the total mass carried by the front axle, from the moments about the axles"],
			["rear", "Weight on the rear wheels", "rear axle load: the share of the total mass carried by the rear axle"],
			["split", "Front / rear", "Front / rear split: the front axle load as a share of the total"],
			["side", "Left / right", "Left / right split: the share of the total on the left wheels"],
			["cg", "Centre of gravity", "Centre of gravity height: the sum of mass times height over the total mass (height above the ground)"],
			["fl", "Front left wheel", "Corner load: the weight on one wheel. The four add up to the total"],
			["fr", "Front right wheel", "Corner load: the weight on one wheel. The four add up to the total"],
			["rl", "Rear left wheel", "Corner load: the weight on one wheel. The four add up to the total"],
			["rr", "Rear right wheel", "Corner load: the weight on one wheel. The four add up to the total"]]:
		var l := Label.new()
		l.name = "weight_read_" + String(pair[0])
		l.tooltip_text = String(pair[2])
		l.add_theme_font_size_override("font_size", 14)
		rd.add_child(l)
		wt_read[pair[0]] = l
	var cm := VBoxContainer.new()
	cm.name = "weight_compare"
	cm.tooltip_text = "Yours vs the real cars of the class: data/real_cars.json. Red when a real car of the class is more than 10 % off"
	body.add_child(cm)
	for key in ["front_split", "mass"]:
		var l := Label.new()
		l.name = "weight_cmp_" + key
		l.add_theme_font_size_override("font_size", 14)
		cm.add_child(l)
		wt_cmp[key] = l
		var h := Label.new()
		h.name = "weight_hint_" + key
		h.add_theme_font_size_override("font_size", 13)
		h.add_theme_color_override("font_color", RED)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cm.add_child(h)
		wt_hint[key] = h
	wt_parts = Label.new()
	wt_parts.name = "weight_parts"
	wt_parts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wt_parts.add_theme_font_size_override("font_size", 13)
	wt_parts.tooltip_text = "Each part with its mass. Estimate: a typed estimate for a typical car of the class (data/car_parts.json), not a measured mass"
	body.add_child(wt_parts)


## one slider row (the value in its pill); its drag is one undo step, a click is one step too
func _wt_slider(parent: Control, label: String, nm: String, tip: String, key: String, lo: float, hi: float, st: float) -> void:
	var v := VBoxContainer.new()
	v.name = nm + "_row"
	v.tooltip_text = tip
	parent.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var l := Label.new()
	l.text = label
	l.tooltip_text = tip
	l.add_theme_font_size_override("font_size", 15)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(l)
	var pill := Label.new()
	pill.add_theme_font_size_override("font_size", 15)
	pill.add_theme_color_override("font_color", SKY)
	top.add_child(pill)
	var sl := HSlider.new()
	sl.name = nm
	sl.min_value = lo
	sl.max_value = hi
	sl.step = st
	sl.focus_mode = Control.FOCUS_NONE
	sl.custom_minimum_size = Vector2(0, 20)
	sl.value_changed.connect(_wt_value.bind(key))
	sl.drag_started.connect(_wt_start.bind(key))
	sl.drag_ended.connect(_wt_end.bind(key))
	v.add_child(sl)
	wt_sl[key] = sl
	wt_pill[key] = pill


## the weight record (S.vehicle["weight"], filled in when missing)
func weight() -> Dictionary:
	return CarWeight.norm(m.S.vehicle.get("weight", {}), pkg())


## a weight change: one undo step; a change that changes nothing is no step
func _wt_commit(label: String, rec: Dictionary) -> void:
	ensure()
	var r := CarWeight.norm(rec, pkg())
	if JSON.stringify(r) == JSON.stringify(weight()):
		_sync()
		return
	m._step_hint = label
	m._push_undo()
	m.S.vehicle["weight"] = r
	msg = ""
	_sync()


func _wt_word(key: String) -> String:
	return {"fuel": "fuel in the tank", "pax": "passengers", "cargo": "cargo"}.get(key, key)


## a slider's drag starts: the undo step is pushed now and kept or dropped at the end
func _wt_start(key: String) -> void:
	wt_held = true
	ensure()
	wt_before = JSON.stringify(weight())
	m._step_hint = "Change " + _wt_word(key)
	m._push_undo()
	wt_n = m.undo.size()


func _wt_set(rec: Dictionary, key: String, v: float) -> void:
	match key:
		"fuel":
			rec["fuel_l"] = snappedf(v, 1.0)
		"pax":
			rec["pax"] = int(round(v))
		"cargo":
			rec["cargo_kg"] = snappedf(v, 5.0)


func _wt_value(v: float, key: String) -> void:
	var rec := weight()
	_wt_set(rec, key, v)
	if not wt_held:   # a click on the track or a key: one step of its own
		_wt_commit("Change " + _wt_word(key), rec)
		return
	m.S.vehicle["weight"] = CarWeight.norm(rec, pkg())
	if Time.get_ticks_msec() - wt_last_ms >= THROTTLE_MS:
		wt_last_ms = Time.get_ticks_msec()
		_sync()


func _wt_end(_changed: bool, key: String) -> void:
	wt_held = false
	var rec := weight()
	_wt_set(rec, key, (wt_sl[key] as HSlider).value)
	m.S.vehicle["weight"] = CarWeight.norm(rec, pkg())
	if m.undo.size() == wt_n and JSON.stringify(m.S.vehicle["weight"]) == wt_before:
		m._drop_undo()
	_sync()


## the drive layout (one undo step): the parts go back to the layout's usual places
func _set_layout(i: int) -> void:
	var rec := weight()
	rec["layout"] = CarWeight.LAYOUTS[clampi(i, 0, CarWeight.LAYOUTS.size() - 1)]
	rec["at"] = {}
	_wt_commit("Drive layout: " + String(rec["layout"]).to_lower(), rec)


## a part dragged on the drawings: its new place (one undo step)
func _on_weight_moved(id: String, place: Vector3) -> void:
	var rec := weight()
	rec["at"][id] = [place.x, place.y, place.z]
	_wt_commit("Move " + CarWeight.PLACE_WORDS.get(id, id).to_lower(), rec)


## the step 4 panel's words and numbers from the record and the mass list
func _sync_weight() -> void:
	var p := pkg()
	var rec := weight()
	var cls := String(p.get("class", "Hatch"))
	wt_layout.select(maxi(0, CarWeight.LAYOUTS.find(String(rec["layout"]))))
	wt_layout.tooltip_text = String(CarWeight.LAYOUT_TIPS.get(String(rec["layout"]), ""))
	var cap := CarWeight.fuel_cap(cls)
	(wt_sl["fuel"] as HSlider).max_value = cap
	(wt_sl["fuel"] as HSlider).set_value_no_signal(float(rec["fuel_l"]))
	(wt_sl["pax"] as HSlider).set_value_no_signal(float(rec["pax"]))
	(wt_sl["cargo"] as HSlider).set_value_no_signal(float(rec["cargo_kg"]))
	(wt_pill["fuel"] as Label).text = "%d L of %d (%d kg)" % [int(rec["fuel_l"]), int(cap), int(round(float(rec["fuel_l"]) * float(CarWeight.data().get("fuel_kg_per_l", 0.74))))]
	(wt_pill["pax"] as Label).text = "%d" % int(rec["pax"])
	(wt_pill["cargo"] as Label).text = "%d kg" % int(rec["cargo_kg"])
	var list := CarWeight.items(p, chassis(), susp(), rec)
	var s := CarWeight.analyse(list, p)
	var tot := float(s["total"])
	var fsh := float(s["front_split"])
	wt_read["total"].text = "Total mass  %d kg" % int(round(tot))
	wt_read["front"].text = "Weight on the front wheels  %d kg" % int(round(float(s["front"])))
	wt_read["rear"].text = "Weight on the rear wheels  %d kg" % int(round(float(s["rear"])))
	wt_read["split"].text = "Front / rear  %d %% / %d %%" % [int(round(fsh * 100.0)), int(round((1.0 - fsh) * 100.0))]
	wt_read["side"].text = "Left / right  %d %% / %d %%" % [int(round(float(s["left_split"]) * 100.0)), int(round((1.0 - float(s["left_split"])) * 100.0))]
	wt_read["cg"].text = "Centre of gravity  %d mm above the ground" % int(round(float(s["cg_z"])))
	var cn: Dictionary = s["corners"]
	wt_read["fl"].text = "Front left wheel  %d kg" % int(round(float(cn["fl"])))
	wt_read["fr"].text = "Front right wheel  %d kg" % int(round(float(cn["fr"])))
	wt_read["rl"].text = "Rear left wheel  %d kg" % int(round(float(cn["rl"])))
	wt_read["rr"].text = "Rear right wheel  %d kg" % int(round(float(cn["rr"])))
	for row in CarWeight.compare(p, s):
		var key: String = row["key"]
		var mine := ("%d %%" % int(round(float(row["yours"]) * 100.0))) if key == "front_split" else ("%d kg" % int(round(float(row["yours"]))))
		var real := ("%d %%" % int(round(float(row["real"]) * 100.0))) if key == "front_split" else ("%d kg" % int(round(float(row["real"]))))
		(wt_cmp[key] as Label).text = "%s: yours %s, real %s (%d cars)" % [String(row["label"]), mine, real, int(row["n"])]
		(wt_cmp[key] as Label).add_theme_color_override("font_color", RED if bool(row["red"]) else Color(1, 1, 1))
		(wt_hint[key] as Label).text = ("  " + String(row["hint"])) if bool(row["red"]) and String(row["hint"]) != "" else ""
	var lines := []
	for it in list:
		if String(it["kind"]) == "part":
			lines.append("%s %d kg" % [String(it["name"]), int(round(float(it["kg"])))])
	var est := "Masses are typed estimates for a typical %s (data/car_parts.json), not measured. " % CarPackage.class_row(cls)[2]
	wt_parts.text = est + "Parts: " + "; ".join(lines)
	weight_plan.set_data(p, chassis(), susp(), rec)


## the status line of step 4: the front share, and how to move a part
func _wt_status() -> String:
	var s := CarWeight.summary(pkg(), chassis(), susp(), weight())
	return "Front wheels carry %d kg (%d %%). Drag a part on a drawing: one undo step each" % [int(round(float(s["front"]))), int(round(float(s["front_split"]) * 100.0))]

