## fight_panel.gd - the FIGHT panel (L76, CHECK ribbon "Fight bake"): the contact frames of the open two-body clip, one row each, with Bake reaction / Fix impact / Bake momentum
## buttons. A clip with no contact (or one fighter) has no rows and no buttons. The buttons only ask the app (signals); the app makes the undo step.
class_name FightPanel
extends Control

signal bake_pressed(i: int)
signal fix_pressed(i: int)
signal momentum_pressed(i: int)
signal frame_picked(f: int)

const W := 560.0
const ROW := 30.0
const HEAD := 24.0
const COL_BG := Color(0.12, 0.12, 0.15, 0.94)

var _rows: Array = []
var _btn := {}      # "bake0" -> Button
var _label := Label.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_label.position = Vector2(10, 4)
	_label.add_theme_font_size_override("font_size", 12)
	add_child(_label)
	custom_minimum_size = Vector2(W, HEAD + ROW)


func height() -> float:
	return HEAD + ROW * float(maxi(_rows.size(), 1))


func rows() -> Array:
	return _rows


func has_button(kind: String, i: int) -> bool:
	return _btn.has(kind + str(i))


func press(kind: String, i: int) -> void:
	if _btn.has(kind + str(i)):
		(_btn[kind + str(i)] as Button).pressed.emit()


func set_contacts(cs: Array, why := "") -> void:
	_rows = cs
	for b in _btn.values():
		(b as Button).queue_free()
	_btn = {}
	if cs.is_empty():
		_label.text = "Fight bake: " + (why if why != "" else "no contact (the hero's strike must land on a partner)")
	else:
		_label.text = "Fight bake: %d contact%s" % [cs.size(), "" if cs.size() == 1 else "s"]
	for i in cs.size():
		var c: Dictionary = cs[i]
		var l := Button.new()
		l.flat = true
		l.text = "f %d  %s %s -> %s (%s)  J %.0f N s%s" % [c["frame"], c["kind"], c["side"], c["region"], c["struck"], c["impulse"], ("  FLAGS: " + ", ".join(c["flags"])) if not (c["flags"] as Array).is_empty() else ""]
		l.position = Vector2(8, HEAD + ROW * i)
		l.size = Vector2(300, ROW - 4)
		l.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var fr: int = c["frame"]
		l.pressed.connect(func(): frame_picked.emit(fr))
		add_child(l)
		_btn["row" + str(i)] = l
		var x := 312.0
		for spec in [["bake", "Bake reaction", bake_pressed, 96.0], ["fix", "Fix impact", fix_pressed, 80.0], ["mom", "Momentum", momentum_pressed, 70.0]]:
			var b := Button.new()
			b.text = spec[1]
			b.position = Vector2(x, HEAD + ROW * i)
			b.size = Vector2(spec[3], ROW - 4)
			var sig: Signal = spec[2]
			var idx := i
			b.pressed.connect(func(): sig.emit(idx))
			if spec[0] == "fix" and (c["flags"] as Array).is_empty():
				b.disabled = true
				b.tooltip_text = "the impact is clean: nothing to fix"
			add_child(b)
			_btn[spec[0] + str(i)] = b
			x += float(spec[3]) + 4.0
	custom_minimum_size = Vector2(W, height())
	size = Vector2(W, height())
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
