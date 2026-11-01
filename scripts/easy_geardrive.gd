extends PanelContainer
## s124 GEARS DRIVE EACH OTHER (Friday plan 124): Turn it, under the Gear pair's sliders. Drag the slider (or press Spin) to turn the small gear;
## the big gear turns -N1 / N2 times as far the other way (a 20 : 40 pair: the small one a full turn, the big one half a turn back), the teeth
## staying meshed. The turn is a VIEW (PartUI.gear_turn): the part record is not touched and there is no undo step. Save pose writes the angle
## into the record as one undo step (rec["gear_pose"]); Straight puts the view back to the saved pose.

const GEAR_DRIVE := preload("res://scripts/gear_drive.gd")
const SPIN_DEG_S := 90.0

var ep: Node               # the Easy Part screen (set by easy_part.gd): _rec(), pu, _say(), _begin() and _end()
var slider: HSlider
var pill: Label
var spin_btn: Button
var save_btn: Button
var straight_btn: Button
var spinning := false


func _init() -> void:
	name = "easypart_gear_drive"
	visible = false
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	add_child(vb)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 6)
	vb.add_child(r1)
	var t := Label.new()
	t.text = "Turn it"
	t.add_theme_font_size_override("font_size", 14)
	r1.add_child(t)
	slider = HSlider.new()
	slider.name = "easypart_gear_turn"
	slider.min_value = -360.0
	slider.max_value = 360.0
	slider.step = 1.0
	slider.value = 0.0
	slider.custom_minimum_size = Vector2(120, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE
	slider.tooltip_text = "Drag to turn the small gear. The big gear turns the other way, by the ratio of the teeth"
	slider.value_changed.connect(_on_slide)
	r1.add_child(slider)
	pill = Label.new()
	pill.name = "easypart_gear_turn_words"
	pill.add_theme_font_size_override("font_size", 12)
	vb.add_child(pill)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 6)
	vb.add_child(r2)
	spin_btn = _btn("easypart_gear_spin", "Spin", "Turn the small gear round and round (the part is not changed)")
	spin_btn.toggle_mode = true
	spin_btn.toggled.connect(_on_spin)
	r2.add_child(spin_btn)
	save_btn = _btn("easypart_gear_save_pose", "Save pose", "Keep the gears turned like this in the part (one undo step)")
	save_btn.pressed.connect(_on_save)
	r2.add_child(save_btn)
	straight_btn = _btn("easypart_gear_straight", "Straight", "Back to the saved pose")
	straight_btn.pressed.connect(_on_straight)
	r2.add_child(straight_btn)
	_words()


func _btn(nm: String, text: String, tip: String) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 26)
	b.add_theme_font_size_override("font_size", 13)
	return b


func _pair() -> Dictionary:
	return GEAR_DRIVE.pair_of(ep._rec()) if ep != null else {}


func _words() -> void:
	var gp := _pair()
	if gp.is_empty():
		pill.text = ""
		return
	var a := slider.value
	pill.text = "Small gear %d deg, big gear %s deg (%d : %d teeth)" % [roundi(a), _n(GEAR_DRIVE.out_angle(a, int(gp["n1"]), int(gp["n2"]))), int(gp["n1"]), int(gp["n2"])]


static func _n(v: float) -> String:
	return str(snappedf(v, 0.1)).trim_suffix(".0")


func _on_slide(v: float) -> void:
	_show(v)


## the view shows the small gear turned to a degrees (no record change, no undo step)
func _show(a: float) -> void:
	if ep == null or ep.pu == null:
		return
	ep.pu.gear_turn = a
	ep.pu._rebuild(true)
	_words()


func _on_spin(on: bool) -> void:
	spinning = on
	if on:
		ep._say("Turn it: the small gear spins and the big gear turns the other way. The part is not changed")


func _process(dt: float) -> void:
	if not spinning or not visible:
		return
	var v := slider.value + SPIN_DEG_S * dt
	if v > slider.max_value:
		v -= 720.0
	slider.value = v   # value_changed -> _show


func _on_save() -> void:
	var gp := _pair()
	if gp.is_empty():
		return
	var a := slider.value
	ep._begin("Save pose")
	ep._rec()["gear_pose"] = a
	ep._end()
	ep.pu.gear_turn = NAN
	ep.pu._rebuild(true)
	ep._say("Pose saved: the small gear at %d degrees, the big gear at %s degrees. Undo takes it back" % [roundi(a), _n(GEAR_DRIVE.out_angle(a, int(gp["n1"]), int(gp["n2"])))])


func _on_straight() -> void:
	spin_btn.set_pressed_no_signal(false)
	spinning = false
	sync_to_record()
	if ep != null and ep.pu != null:
		ep.pu.gear_turn = NAN
		ep.pu._rebuild(true)


## the slider reads the record's saved pose (without turning anything)
func sync_to_record() -> void:
	if ep == null:
		return
	slider.set_value_no_signal(clampf(float(ep._rec().get("gear_pose", 0.0)), slider.min_value, slider.max_value))
	_words()
