extends VBoxContainer
## W10 JOIN HELPER panel: four mode buttons (Join / Cut / Overlap / New part), a status line in plain words, a "Nudge 0.01 mm and retry"
## button when the kernel says the two only touch, and Undo. The parts live in `parts` (kernel ids); every change is ONE history entry.

const JH := preload("res://scripts/build/join_helper.gd")
const KCad := preload("res://scripts/kcad.gd")

var parts: Array = []        # [target id, tool id] before; the results after
var history: Array = []      # snapshots of `parts` (ids stay alive while in history)
var pending_mode := ""
var status: Label
var nudge_btn: Button
var undo_btn: Button
var mode_btns := {}
var last: Dictionary = {}


func setup(a: int, b: int) -> void:
	parts = [a, b]
	history.clear()
	for m in JH.MODES:
		var bt := Button.new()
		bt.text = JH.MODE_NAMES[m]
		bt.name = "Mode_" + m
		bt.custom_minimum_size = Vector2(0, 32)
		bt.pressed.connect(_on_mode.bind(m))
		add_child(bt)
		mode_btns[m] = bt
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(260, 0)
	status.name = "Status"
	add_child(status)
	nudge_btn = Button.new()
	nudge_btn.text = "Nudge 0.01 mm and retry"
	nudge_btn.name = "Nudge"
	nudge_btn.visible = false
	nudge_btn.custom_minimum_size = Vector2(0, 32)
	nudge_btn.pressed.connect(_on_nudge)
	add_child(nudge_btn)
	undo_btn = Button.new()
	undo_btn.text = "Undo"
	undo_btn.name = "Undo"
	undo_btn.custom_minimum_size = Vector2(0, 32)
	undo_btn.pressed.connect(undo)
	add_child(undo_btn)
	status.text = "Pick how the two parts combine."


func body_count() -> int:
	var n := 0
	for p in parts:
		n += JH.lumps(p)
	return n


func _apply(res: Dictionary, b_override := -1) -> void:
	last = res
	status.text = String(res["message"])
	nudge_btn.visible = bool(res["nudge"])
	if res["ok"]:
		history.append(parts.duplicate())
		parts = (res["bodies"] as Array).duplicate()
		nudge_btn.visible = false
		status.text += "  Bodies now: %d." % body_count()


func _on_mode(m: String) -> void:
	if parts.size() != 2:
		status.text = "Already combined. Undo to try another mode."
		return
	pending_mode = m
	_apply(JH.run(parts[0], parts[1], m))


func _on_nudge() -> void:
	if parts.size() != 2 or pending_mode == "":
		return
	var r := JH.nudged_retry(parts[0], parts[1], pending_mode)
	if r["result"]["ok"]:
		# the nudged tool replaces the tool in the one history entry: undo gives back the ORIGINAL pair
		_apply(r["result"])
	else:
		_apply(r["result"])


func undo() -> void:
	if history.is_empty():
		return
	parts = history.pop_back()
	nudge_btn.visible = false
	status.text = "Undone: %d bodies." % body_count()
