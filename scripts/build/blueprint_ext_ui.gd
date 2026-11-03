## blueprint_ext_ui.gd - the second row of the Blueprint sheet view: dimension style preset, custom sheet size (W x H mm, 1:1 option),
## detail callouts (letter + two clicks on the sheet: the label, then the target). Opt-in; BlueprintUI calls attach() and decorate().
class_name BlueprintExtUI
extends RefCounted

var ui: BlueprintUI
var preset: OptionButton
var cw: SpinBox
var ch: SpinBox
var one: CheckBox
var letter: LineEdit
var arm: Button
var callouts := {}      # tab -> [{"letter", "p", "t"}]
var armed := false
var _first := Vector2.ZERO
var _have_first := false
var custom := false


static func attach(u: BlueprintUI, vb: VBoxContainer) -> BlueprintExtUI:
	var x := BlueprintExtUI.new()
	x.ui = u
	var row := HBoxContainer.new()
	row.name = "blueprint_ext_row"
	row.add_theme_constant_override("separation", 6)
	vb.add_child(row)
	vb.move_child(row, 1)
	var l := Label.new()
	l.text = "Dim style"
	row.add_child(l)
	x.preset = OptionButton.new()
	x.preset.name = "blueprint_dim_preset"
	x.preset.tooltip_text = "Dimension style: extension line gap and overshoot, text gap, text background"
	for n in BlueprintExt.preset_names():
		x.preset.add_item(String(n))
	x.preset.item_selected.connect(x._on_preset)
	row.add_child(x.preset)
	var l2 := Label.new()
	l2.text = "  Sheet mm"
	row.add_child(l2)
	x.cw = x._spin("blueprint_sheet_w", 600.0)
	row.add_child(x.cw)
	x.ch = x._spin("blueprint_sheet_h", 400.0)
	row.add_child(x.ch)
	x.one = CheckBox.new()
	x.one.name = "blueprint_custom_on"
	x.one.text = "Custom 1:1"
	x.one.tooltip_text = "Draw on a W x H mm sheet at true 1:1 (otherwise A4 / A3 at the best scale)"
	x.one.toggled.connect(x._on_custom)
	row.add_child(x.one)
	var l3 := Label.new()
	l3.text = "  Detail"
	row.add_child(l3)
	x.letter = LineEdit.new()
	x.letter.name = "blueprint_callout_letter"
	x.letter.text = "A"
	x.letter.max_length = 3
	x.letter.custom_minimum_size.x = 44
	x.letter.tooltip_text = "The detail letter (editable). Changing it renames the last callout on this sheet"
	x.letter.text_submitted.connect(x._on_letter)
	row.add_child(x.letter)
	x.arm = u.m._button("Add callout", x._arm, "Click the label spot on the sheet, then the spot it points at")
	x.arm.name = "blueprint_callout_add"
	row.add_child(x.arm)
	u.area.gui_input.connect(x._area_input)
	return x


func _spin(nm: String, v: float) -> SpinBox:
	var s := SpinBox.new()
	s.name = nm
	s.min_value = BlueprintExt.MIN_MM
	s.max_value = BlueprintExt.MAX_MM
	s.step = 10
	s.value = v
	s.value_changed.connect(func(_v): _on_custom(custom))
	return s


func _on_preset(i: int) -> void:
	BlueprintExt.use_preset(preset.get_item_text(i))
	_redo()


func _on_custom(on: bool) -> void:
	custom = on
	var bd: Dictionary = ui.b._bld()
	ui.pick = BlueprintExt.custom_pick(cw.value, ch.value, 1) if on else Blueprint.choose(bd)
	if ui.pick.is_empty():
		ui.pick = Blueprint.choose(bd)
	_redo()


func _redo() -> void:
	if ui.tab != "":
		ui._pick_tab(ui.tab)


func _arm() -> void:
	armed = true
	_have_first = false
	ui.status.text = "Callout %s: click where the label goes" % BlueprintExt.clean_letter(letter.text)


func _on_letter(t: String) -> void:
	var l: Array = callouts.get(ui.tab, [])
	if not l.is_empty():
		BlueprintExt.rename_callout(l, String(l[-1]["letter"]), t)
		_redo()


func _area_input(e: InputEvent) -> void:
	if not armed or not (e is InputEventMouseButton) or not e.pressed or e.button_index != MOUSE_BUTTON_LEFT:
		return
	var p: Vector2 = (e.position - ui.view.position) / ui.view.ppm
	if not Rect2(Vector2.ZERO, Vector2(float(ui.sheet["w"]), float(ui.sheet["h"]))).has_point(p):
		return
	if not _have_first:
		_first = p
		_have_first = true
		ui.status.text = "Callout: now click the spot it points at"
		return
	var l: Array = callouts.get(ui.tab, [])
	l.append({"letter": BlueprintExt.clean_letter(letter.text), "p": _first, "t": p})
	callouts[ui.tab] = l
	letter.text = BlueprintExt.next_letter(l)
	armed = false
	_redo()


## called after BlueprintUI built a sheet: adds this tab's callouts
func decorate() -> void:
	BlueprintExt.apply_callouts(ui.sheet, callouts.get(ui.tab, []))
	ui.view.sheet = ui.sheet
