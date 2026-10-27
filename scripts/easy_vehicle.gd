class_name EasyVehicle
extends Control
## VEHICLE, EASY (B3, the second round): a screen of its own over BUILD, opened by the chooser's Vehicle card (Easy).
## The car in a 3D view on the left; "Change your car" on the right: Length, Width, Height, Wheelbase (the car body) and Wheel size
## (the wheel): sliders in cm, one undo step per release, a click on the track is one step. "Drive it" plays the car along a straight
## 10 m and then a curve: each wheel turns by the distance it has rolled / its radius (no slip), the camera follows.
## "Use in a scene" puts the car in the set as a prop (Props.register_solids; STAGE collides with it) and opens STAGE.
## "Expert" opens the car's BODY as a Part (the Part workspace on BUILD). Mouse only: no key names in any text here.
## Without the CAD DLL (Part.available() false) it says why and changes nothing. Record: m.S.part = the car body, m.S.vehicle = {"wheel"}.

const SPEED := 3.0            # m/s the car drives at
const THROTTLE_MS := 100      # a held slider rebuilds the car at most this often
const SKY := Color("#73BFFF")
const AMBER := Color("#FFC933")
const PW := 318.0             # the panel's width (right)
const BAD_WORDS := ["ctrl", "shift", "alt+", "esc", "enter", "tab ", "delete", "backspace", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", "spacebar", "return key"]
## the sliders: [template key, label, which record ("car" | "wheel")]; the ranges and words are the template's (scripts/build/part_templates.gd)
const ROWS := [
	["body_length", "Length", "car"],
	["body_width", "Width", "car"],
	["body_height", "Height", "car"],
	["wheelbase", "Wheelbase", "car"],
	["radius", "Wheel size", "wheel"],
]

var m: Node
var vp: SubViewport
var world: Node3D
var cam: Camera3D
var view: TextureRect
var car_root: Node3D = null
var title_l: Label
var undo_btn: Button
var redo_btn: Button
var panel: PanelContainer
var rows := []                # [{"slider": HSlider, "pill": Label, "k", "rec", "label"}]
var status: PanelContainer
var status_l: Label
var drive_btn: Button
var use_btn: Button
var driving := false
var drive_s := 0.0            # m the car has covered on its path
var path := {}
var msg := ""
var flushes := 0              # rebuilds of the car (the test counts them against the clock)
var _pending := {"car": {}, "wheel": {}}
var _dirty := false
var _last_ms := 0
var _held := false
var _edit_n := -1
var _edit_before := ""
var _sig := ""


func build(root: Control) -> void:
	name = "easy_vehicle"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # the screen covers BUILD: a click here never reaches the house below
	visible = false
	root.add_child(self)
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	# the top bar
	var top := PanelContainer.new()
	top.name = "easyvehicle_bar"
	top.add_theme_stylebox_override("panel", _style(Color(0.09, 0.1, 0.13), 0, 6))
	top.anchor_right = 1.0
	top.offset_bottom = m.TOP_H
	add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	top.add_child(row)
	var back := _bar_btn("Back to BUILD", "Leave the car: the car stays as it is", close)
	back.name = "easyvehicle_back"
	row.add_child(back)
	title_l = Label.new()
	title_l.name = "easyvehicle_title"
	title_l.text = "Vehicle"
	title_l.add_theme_font_size_override("font_size", 20)
	title_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title_l)
	undo_btn = _bar_btn("Undo", "Take back the last change", func(): m._undo())
	redo_btn = _bar_btn("Redo", "Put back what Undo took back", func(): m._redo())
	row.add_child(undo_btn)
	row.add_child(redo_btn)
	row.add_child(_bar_btn("Expert", "The car's body as a Part, with every feature and number", expert))
	# the 3D view: the car, lit, on a ground plane
	vp = SubViewport.new()
	vp.name = "easyvehicle_view"
	vp.own_world_3d = true
	vp.size = Vector2i(960, 600)
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
	sun.shadow_enabled = true   # the car casts its shadow on the floor
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(60, 60)
	ground.mesh = pl
	ground.material_override = Vehicle.floor_material()   # the floor grid
	world.add_child(ground)
	cam = Camera3D.new()
	cam.name = "easyvehicle_cam"
	cam.fov = 40.0
	cam.current = true
	world.add_child(cam)
	view = TextureRect.new()
	view.name = "easyvehicle_viewrect"
	view.texture = vp.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	# the panel: "Change your car"
	panel = PanelContainer.new()
	panel.name = "easyvehicle_panel"
	panel.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.95), 12, 12))
	add_child(panel)
	var v := VBoxContainer.new()
	v.name = "easyvehicle_panel_vb"
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var pt := Label.new()
	pt.name = "easyvehicle_panel_title"
	pt.text = "Change your car"
	pt.add_theme_font_size_override("font_size", 22)
	v.add_child(pt)
	var rows_vb := VBoxContainer.new()
	rows_vb.name = "easyvehicle_rows"
	rows_vb.add_theme_constant_override("separation", 4)
	v.add_child(rows_vb)
	for r in ROWS:
		rows_vb.add_child(_make_row(r))
	drive_btn = _big_btn("Drive it", "Drive it: a straight 10 m, then a curve. The wheels turn as far as the car rolls", drive)
	drive_btn.name = "easyvehicle_drive"
	v.add_child(drive_btn)
	use_btn = _big_btn("Use in a scene", "The car goes into the set as a prop, and STAGE opens", use_in_scene)
	use_btn.name = "easyvehicle_use"
	v.add_child(use_btn)
	# the one sentence, under the view
	status = PanelContainer.new()
	status.name = "easyvehicle_status"
	status.add_theme_stylebox_override("panel", _style(Color(0.1, 0.11, 0.14, 0.92), 10, 6))
	status_l = Label.new()
	status_l.add_theme_font_size_override("font_size", 15)
	status_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_child(status_l)
	add_child(status)
	layout()


## the screen shows (from the chooser): the car is made if there is none, the view framed, the sliders read the car
func open() -> void:
	ensure()
	visible = true
	msg = "Drag a slider, or press Drive it"
	driving = false
	_sig = ""
	_rebuild_view()
	_sync()
	frame()


func close() -> void:
	visible = false
	driving = false


## the car body (the Part record) and the wheel: {} until the car is made
func car() -> Dictionary:
	return m.S.part


func wheel() -> Dictionary:
	return m.S.vehicle.get("wheel", {})


func is_car() -> bool:
	return String(car().get("easy", {}).get("t", "")) == "car" and not wheel().is_empty()


## a car exists: start one when the scene has none (one undo step). A part that is not a car is replaced: its undo step brings it back
func ensure() -> void:
	if is_car() or not Part.available():
		return
	m._step_hint = "Start a car"
	m._push_undo()
	var set := Vehicle.make_set()
	m.S.part = set["car"]
	m.S.vehicle = {"wheel": set["wheel"]}
	if m.bld != null:
		m.bld.sync()


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


func _big_btn(t: String, tip: String, f: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_stylebox_override("normal", _style(AMBER, 8, 6))
	b.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
	b.add_theme_stylebox_override("hover", _style(AMBER.lightened(0.12), 8, 6))
	b.add_theme_color_override("font_hover_color", Color(0.1, 0.1, 0.1))
	b.pressed.connect(f)
	return b


## one slider row: the label and its number, the slider in cm (the record says mm), the template's two words under it
func _make_row(r: Array) -> Control:
	var rec_key := String(r[2])
	var d := _param(rec_key, String(r[0]))
	var v := VBoxContainer.new()
	v.name = "easyvehicle_row_" + String(r[0])
	v.add_theme_constant_override("separation", 0)
	var top := HBoxContainer.new()
	v.add_child(top)
	var lab := Label.new()
	lab.text = String(r[1])
	lab.add_theme_font_size_override("font_size", 16)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(lab)
	var pill := Label.new()
	pill.add_theme_font_size_override("font_size", 16)
	pill.add_theme_color_override("font_color", SKY)
	top.add_child(pill)
	var sl := HSlider.new()
	sl.name = "easyvehicle_slider_" + String(r[0])
	sl.min_value = float(d["lo"]) / 10.0
	sl.max_value = float(d["hi"]) / 10.0
	sl.step = float(d["step"]) / 10.0
	sl.focus_mode = Control.FOCUS_NONE
	sl.custom_minimum_size = Vector2(0, 22)
	sl.value_changed.connect(_on_value.bind(r))
	sl.drag_started.connect(_on_start.bind(r))
	sl.drag_ended.connect(_on_end.bind(r))
	v.add_child(sl)
	var words := HBoxContainer.new()
	var w0 := Label.new()
	w0.text = String(d["words"][0])
	w0.add_theme_font_size_override("font_size", 12)
	w0.modulate = Color(1, 1, 1, 0.6)
	w0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(w0)
	var w1 := Label.new()
	w1.text = String(d["words"][1])
	w1.add_theme_font_size_override("font_size", 12)
	w1.modulate = Color(1, 1, 1, 0.6)
	words.add_child(w1)
	v.add_child(words)
	rows.append({"slider": sl, "pill": pill, "k": String(r[0]), "rec": rec_key, "label": String(r[1]), "unit": "cm"})
	return v


func _param(rec_key: String, k: String) -> Dictionary:
	return PartTemplates.param("car" if rec_key == "car" else "wheel", k)


## the sliders show the records (cm); a changed record re-reads them
func _sync() -> void:
	for row in rows:
		var rec: Dictionary = car() if row["rec"] == "car" else wheel()
		if rec.is_empty():
			continue
		var v := float(rec["easy"]["p"].get(row["k"], 0.0)) / 10.0
		var sl: HSlider = row["slider"]
		sl.set_value_no_signal(v)
		(row["pill"] as Label).text = "%s cm" % str(snappedf(v, 0.1))
	var ok := Part.available()
	for row in rows:
		(row["slider"] as HSlider).editable = ok
	drive_btn.disabled = not ok or not is_car()
	use_btn.disabled = not ok
	title_l.text = "Vehicle" if is_car() else "Vehicle: no car yet"
	undo_btn.disabled = m.undo.is_empty()
	redo_btn.disabled = m.redo.is_empty()
	status_l.text = msg if ok else "The car needs the KineCAD add-on, which is not installed."


# ---------------------------------------------------------------- undo steps (one per release)

func _begin(label: String) -> void:
	m._step_hint = label
	m._push_undo()
	_edit_n = m.undo.size()
	_edit_before = JSON.stringify([car(), m.S.vehicle])


## the step ends; a step that changed nothing is taken back out
func _end() -> void:
	if _edit_n >= 0 and m.undo.size() == _edit_n and JSON.stringify([car(), m.S.vehicle]) == _edit_before:
		m._drop_undo()
	_edit_n = -1


func _on_start(r: Array) -> void:
	_held = true
	_begin("Change " + String(r[1]))


func _on_value(v: float, r: Array) -> void:
	_set_value(r, v)
	(rows[_row_index(r)]["pill"] as Label).text = "%s cm" % str(snappedf(v, 0.1))
	if not _held:   # a click on the track or a nudge: one step of its own
		_begin("Change " + String(r[1]))
		_flush()
		_end()
		return
	if Time.get_ticks_msec() - _last_ms >= THROTTLE_MS:
		_flush()


func _on_end(_changed: bool, r: Array) -> void:
	_held = false
	_set_value(r, (rows[_row_index(r)]["slider"] as HSlider).value)
	_flush()
	_end()


func _row_index(r: Array) -> int:
	for i in rows.size():
		if rows[i]["k"] == String(r[0]):
			return i
	return 0


func _set_value(r: Array, v: float) -> void:
	_pending[String(r[2])][String(r[0])] = v * 10.0   # the slider says cm, the record mm
	if String(r[0]) == "radius":   # the arches follow the wheel: the car body gets the radius too (73229623)
		_pending["car"]["wheel_r"] = v * 10.0
	_dirty = true


## the pending numbers go into the records (the template rewrites its own features), the car is rebuilt
func _flush() -> void:
	flushes += 1
	_dirty = false
	_last_ms = Time.get_ticks_msec()
	if not is_car():
		_pending = {"car": {}, "wheel": {}}
		return
	if not (_pending["car"] as Dictionary).is_empty():
		PartTemplates.retemplate(car(), _pending["car"])
	if not (_pending["wheel"] as Dictionary).is_empty():
		PartTemplates.retemplate(wheel(), _pending["wheel"])
	_pending = {"car": {}, "wheel": {}}
	driving = false
	_rebuild_view()
	_sync()


## the car in the 3D view, from the records (Part.replay: the kernel's solids and mesh)
func _rebuild_view() -> void:
	if car_root != null:
		world.remove_child(car_root)
		car_root.free()
		car_root = null
	if not is_car() or not Part.available():
		return
	car_root = Vehicle.build_node(car(), wheel())
	world.add_child(car_root)
	Vehicle.drive(car_root, Vehicle.drive_path(), 0.0)
	_sig = JSON.stringify([car(), wheel()])


## the camera: the car side-on and a little from the front, the whole car in the view
func frame() -> void:
	if not is_car():
		return
	var L := float(car()["easy"]["p"]["body_length"]) * Part.MM
	var dist := maxf(L * 1.7, 3.6)
	var at := Vector3(0.0, 0.35, 0.0)
	cam.position = at + Vector3(-dist * 0.72, dist * 0.42, -dist * 0.62)
	cam.look_at(at, Vector3.UP)


func drive() -> void:
	if not Part.available() or not is_car():
		return
	if car_root == null:
		_rebuild_view()
	path = Vehicle.drive_path()
	drive_s = 0.0
	driving = true
	msg = "Driving: 10 m straight, then the curve. Each wheel turns by the distance it rolls over its radius"
	_sync()


## a car in the set: one prop (its boxes), replacing an earlier car in the set; STAGE opens
func use_in_scene() -> void:
	if not Part.available() or not is_car():
		return
	var kind := "car:Vehicle"
	Props.register_solids(kind, Vehicle.prop_solids(car(), wheel()))
	m._push_undo()
	var kept := []
	for p in m.S.props:
		if String(p["kind"]) != kind:
			kept.append(p)
	m.S.props = kept
	m.S.props.append(Props.make(kind, Transform3D.IDENTITY))
	m._props_show()
	close()
	m._page_set("STAGE")
	m._say("The car is in the set on STAGE: a prop with its body and four wheels")


## the car's body opens as a Part (Expert): the Part workspace on BUILD
func expert() -> void:
	close()
	m._page_set("BUILD")
	if m.bld != null and m.bld.part != null:
		m.bld.part.set_on(true)
	m._say("The car's body is open as a Part: sketch, extrude, and every feature on the timeline")


func layout() -> void:
	var vs := get_viewport_rect().size
	var top := float(m.TOP_H)
	var vw := vs.x - PW - 8.0
	var vh := vs.y - top - 56.0
	view.position = Vector2(0.0, top)
	view.size = Vector2(vw, vh)
	if vp != null and vp.size != Vector2i(int(vw), int(vh)) and vw > 1.0 and vh > 1.0:
		vp.size = Vector2i(int(vw), int(vh))
	panel.position = Vector2(vs.x - PW - 8.0, top + 8.0)
	panel.size = Vector2(PW, vs.y - top - 16.0)
	status.position = Vector2(12.0, top + vh - 44.0)
	status.size = Vector2(vw - 24.0, 40.0)


func _process(dt: float) -> void:
	if not visible:
		return
	if vp != null and view != null and view.size.x > 1.0 and vp.size != Vector2i(view.size):
		layout()
	if _dirty and Time.get_ticks_msec() - _last_ms >= THROTTLE_MS and not _held:
		_flush()
	if driving and car_root != null:
		drive_s += dt * SPEED
		var total := float(path["len"])
		if drive_s >= total:
			drive_s = total
			driving = false
			msg = "Done: the car rolled 10 m and then the curve. The wheels turned as far as the car went"
			_sync()
		var root := car_root
		Vehicle.drive(root, path, drive_s)
		var back := Quaternion(Vector3.UP, root.rotation.y) * Vector3(0.0, 2.2, -6.0)
		cam.position = root.position + back
		cam.look_at(root.position + Vector3(0.0, 0.5, 0.0), Vector3.UP)
	elif _sig != JSON.stringify([car(), wheel()]) and is_car():
		_rebuild_view()
		_sync()
	status_l.text = msg
