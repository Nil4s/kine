## The Transform panel (L120, ROADMAP_400 P10): X / Y / Z / Rot of the selected props. Type a value + Enter = absolute (all
## selected get it); drag a field's label sideways = relative (each moves by the same delta); "—" = the values differ.
## The panel only reports (signals); main.gd edits the scene.
class_name MultiPanel
extends PanelContainer

signal typed(field: String, text: String)
signal scrub_begin(field: String)
signal scrub_move(field: String, delta: float)
signal scrub_end(field: String)

const NAMES := {"x": "X", "y": "Y", "z": "Z", "rot": "Rot"}

var edits := {}
var scrubs := {}
var _title: Label
var _drag := ""
var _acc := 0.0


func _init() -> void:
	name = "MultiPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	add_child(v)
	_title = Label.new()
	v.add_child(_title)
	for f in MultiEdit.FIELDS:
		var h := HBoxContainer.new()
		v.add_child(h)
		var lab := Label.new()
		lab.text = "%s ↔" % NAMES[f]
		lab.custom_minimum_size = Vector2(52, 0)
		lab.mouse_filter = Control.MOUSE_FILTER_STOP
		lab.mouse_default_cursor_shape = Control.CURSOR_HSIZE
		lab.tooltip_text = "Drag sideways: every selected object moves by the same amount. Type a value on the right: they all get it."
		lab.gui_input.connect(_label_input.bind(f))
		h.add_child(lab)
		var le := LineEdit.new()
		le.custom_minimum_size = Vector2(90, 0)
		le.text_submitted.connect(func(t: String): typed.emit(f, t))
		h.add_child(le)
		scrubs[f] = lab
		edits[f] = le


func show_values(texts: Dictionary, count: int) -> void:
	_title.text = "Transform" if count < 2 else "Transform (%d objects)" % count
	for f in MultiEdit.FIELDS:
		if not (edits[f] as LineEdit).has_focus() or texts[f] == MultiEdit.MIXED:
			(edits[f] as LineEdit).text = texts[f]


func _label_input(ev: InputEvent, f: String) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if (ev as InputEventMouseButton).pressed:
			_drag = f
			_acc = 0.0
			scrub_begin.emit(f)
		elif _drag == f:
			_drag = ""
			scrub_end.emit(f)
		accept_event()
	elif ev is InputEventMouseMotion and _drag == f:
		_acc += (ev as InputEventMouseMotion).relative.x
		scrub_move.emit(f, _acc * float(MultiEdit.RATE[f]))
		accept_event()
