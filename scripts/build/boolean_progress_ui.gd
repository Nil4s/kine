extends PanelContainer
## C38: the busy bar of a heavy boolean: a words line, a ProgressBar and a Cancel button. Put it under any Control; BooleanSafe.run_job's
## on_progress feeds set_progress(), and the caller sets job["cancel"] when cancel_pressed fires.
signal cancel_pressed
var line: Label
var bar: ProgressBar
var btn: Button


func _init() -> void:
	name = "bool_busy"
	var vb := VBoxContainer.new()
	add_child(vb)
	line = Label.new()
	line.name = "bool_busy_line"
	vb.add_child(line)
	bar = ProgressBar.new()
	bar.name = "bool_busy_bar"
	bar.custom_minimum_size = Vector2(240, 14)
	bar.show_percentage = false
	vb.add_child(bar)
	btn = Button.new()
	btn.name = "bool_busy_cancel"
	btn.text = "Cancel"
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func():
		btn.disabled = true
		line.text = "Cancelling after this step..."
		cancel_pressed.emit())
	vb.add_child(btn)


func set_progress(done: int, total: int, text: String) -> void:
	bar.max_value = maxi(total, 1)
	bar.value = done
	if not btn.disabled:
		line.text = "%s  (%d%%)" % [text, int(100.0 * done / maxi(total, 1))]
