extends RefCounted
## C70: the Gear sketch tool. A "Gear" button in the Shapes row opens a dialog (module, teeth, pressure angle, profile shift, root fillet, centre, bore) with a
## live outline and the pitch / tip / root diameters; "Add gear" puts the involute loop (PartGear.ents) into the open sketch in one edit. Extrude it like any loop.

const PGEAR := preload("res://scripts/build/part_gear.gd")
const FIELDS := [
	["m", "Module (mm)", 0.2, 50.0, 2.0, 0.1, "MODULE: the tooth size in mm. Pitch diameter = module x teeth."],
	["z", "Teeth", 6.0, 400.0, 20.0, 1.0, "TEETH: how many teeth round the wheel (6 to 400)."],
	["pa", "Pressure angle", 5.0, 35.0, 20.0, 0.5, "PRESSURE ANGLE (degrees): 20 is the usual one. A bigger angle makes a stronger, wider-footed tooth."],
	["x", "Profile shift", -1.5, 1.5, 0.0, 0.05, "PROFILE SHIFT (in modules): moves the tooth out (+) or in (-). A small pinion needs + to avoid undercut."],
	["rho", "Root fillet (mm)", 0.0, 20.0, 0.0, 0.05, "ROOT FILLET (mm): rounds the corner where a tooth meets the root. 0 = the usual 0.38 x module."],
	["cx", "Centre X (mm)", -5000.0, 5000.0, 0.0, 1.0, "CENTRE X: where the gear's middle goes in the sketch."],
	["cy", "Centre Y (mm)", -5000.0, 5000.0, 0.0, 1.0, "CENTRE Y: where the gear's middle goes in the sketch."],
	["bore", "Bore diameter (mm)", 0.0, 1000.0, 0.0, 0.5, "BORE: a round hole through the middle (0 = none)."]]

var ui: Node
var card: PanelContainer
var spins := {}
var info: Label
var prev: Control
var add_btn: Button
var btn: Button
var is_open := false


func _init(u: Node) -> void:
	ui = u


func build(row: Node) -> void:
	btn = ui.m._button("Gear", func(): set_open(not is_open), "GEAR: an involute spur gear from module, teeth, pressure angle, profile shift and root fillet, as one closed loop in the sketch. Extrude it for the solid.")
	btn.name = "part_tool_gear"
	row.add_child(btn)
	card = PanelContainer.new()
	card.name = "part_gear_dialog"
	card.visible = false
	card.z_index = 60
	var sb := StyleBoxFlat.new()   # opaque: the sketch and the timeline must not show through
	sb.bg_color = Color(0.11, 0.12, 0.15, 1.0)
	sb.border_color = Color(0.4, 0.62, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", sb)
	ui.m.ui_root.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	card.add_child(v)
	var t := Label.new()
	t.text = "Involute gear"
	v.add_child(t)
	var hb := HBoxContainer.new()
	v.add_child(hb)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	hb.add_child(grid)
	for f in FIELDS:
		var l := Label.new()
		l.text = f[1]
		l.tooltip_text = f[6]
		grid.add_child(l)
		var s := SpinBox.new()
		s.min_value = f[2]
		s.max_value = f[3]
		s.step = f[5]
		s.value = f[4]
		s.allow_greater = false
		s.custom_minimum_size = Vector2(96, 0)
		s.tooltip_text = f[6]
		s.name = "gear_" + String(f[0])
		s.value_changed.connect(func(_x): refresh())
		grid.add_child(s)
		spins[f[0]] = s
	prev = Control.new()
	prev.name = "gear_preview"
	prev.custom_minimum_size = Vector2(150, 150)
	prev.draw.connect(_draw_prev)
	hb.add_child(prev)
	info = Label.new()
	info.name = "gear_info"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(440, 0)
	v.add_child(info)
	var bb := HBoxContainer.new()
	v.add_child(bb)
	add_btn = ui.m._button("Add gear", add_gear, "Put this gear into the open sketch (one edit; Undo takes it out).")
	add_btn.name = "gear_add"
	bb.add_child(add_btn)
	var cb: Button = ui.m._button("Close", func(): set_open(false))
	cb.name = "gear_close"
	bb.add_child(cb)
	refresh()


func val(k: String) -> float:
	return (spins[k] as SpinBox).value


func set_open(v: bool) -> void:
	is_open = v
	if v and ui.sk == "":
		ui.begin_sketch("front")
	card.visible = v and ui.sk != ""
	if card.visible:
		var vs: Vector2 = ui.m.ui_root.get_viewport_rect().size
		card.position = Vector2(maxf(8.0, vs.x * 0.5 - 320.0), 118.0)
	btn.set_pressed_no_signal(v)
	refresh()


func sync() -> void:
	if card != null:
		card.visible = is_open and ui.sk != "" and ui.shows()


func why() -> String:
	return PGEAR.check(val("m"), int(val("z")), val("pa"), val("x"))


func refresh() -> void:
	if info == null:
		return
	var w := why()
	var m := val("m")
	var z := int(val("z"))
	if w == "":
		var g := PGEAR.geom(m, z, val("pa"), val("x"))
		info.text = tr("Pitch diameter %.2f mm, tip %.2f mm, root %.2f mm, %d teeth.") % [2.0 * g["rp"], 2.0 * g["ra"], 2.0 * g["rf"], z]
	else:
		info.text = w
	if add_btn != null:
		add_btn.disabled = w != ""
	prev.queue_redraw()


func _draw_prev() -> void:
	var w := why()
	if w != "":
		return
	var ol := PGEAR.outline(val("m"), int(val("z")), val("pa"), val("x"), val("rho") if val("rho") > 0.0 else -1.0)
	if ol.is_empty():
		return
	var R := 0.0
	for p in ol:
		R = maxf(R, p.length())
	var k := 78.0 / R
	var c := prev.size * 0.5
	var pts := PackedVector2Array()
	for p in ol:
		pts.append(c + Vector2(p.x, -p.y) * k)
	prev.draw_colored_polygon(pts, Color(0.55, 0.62, 0.75, 0.35))
	pts.append(pts[0])
	prev.draw_polyline(pts, Color(0.9, 0.93, 1.0), 1.5, true)
	if val("bore") > 0.0:
		prev.draw_arc(c, val("bore") * 0.5 * k, 0.0, TAU, 32, Color(0.9, 0.93, 1.0), 1.5)


func add_gear() -> void:
	if why() != "":
		return
	if ui.sk == "":
		ui.begin_sketch("front")
	var list := PGEAR.ents(val("m"), int(val("z")), val("pa"), val("x"), val("rho") if val("rho") > 0.0 else -1.0,
		Vector2(val("cx"), val("cy")), 0.0, val("bore"))
	ui.shp._add(list)
	ui._say(tr("Gear added: %d teeth, module %s. Extrude it to make the solid.") % [int(val("z")), ui._fmt(val("m"))])
