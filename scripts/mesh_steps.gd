class_name MeshSteps
extends PanelContainer
## P151 MODEL FROM WORDS, STEPS (Friday plan 151): on the MODEL page, a panel of TYPED steps. Each line is a plain phrase
## run through MeshWords (scripts/mesh_words.gd: "extrude the top 5 cm", "make it 2 cm thicker"); the list keeps the
## phrases in order. Edit a row and press Enter: the mesh goes back to before that row and the rows from it are run again
## with the new words. The x on a row removes it the same way. Ctrl+Z takes back the newest step and its row.
## Each step is ONE KMeshUndo step (MeshWords makes it); a row keeps {text, at, n}: at = the undo count before the step,
## n = the steps it made. A mesh changed by hand after the last row is not rewound: the panel says so in words.
## Built by KMeshEditUI.setup (one line); shown only while the test cube is open on the MODEL page.

var kmed: KMeshEditUI
var entries: Array = []   # {text, at, n, bad}
var _line: LineEdit
var _rows: VBoxContainer
var _say: Label


func setup(ui: KMeshEditUI) -> void:
	kmed = ui
	name = "mesh_steps_panel"
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	grow_vertical = Control.GROW_DIRECTION_BEGIN   # the panel grows up from the bottom edge as rows are added
	var vb := VBoxContainer.new()
	add_child(vb)
	var title := Label.new()
	title.text = "Model from words: type a step, Enter"
	title.add_theme_color_override("font_color", Tok.of("heading"))
	vb.add_child(title)
	_line = LineEdit.new()
	_line.name = "steps_add"
	_line.placeholder_text = "e.g. extrude the top 5 cm"
	_line.custom_minimum_size = Vector2(300, 0)
	_line.tooltip_text = "a plain step: extrude the top 5 cm, make it 2 cm thicker, subdivide it twice. Enter adds it as one undo step"
	_line.text_submitted.connect(func(_t): _add())
	vb.add_child(_line)
	_rows = VBoxContainer.new()
	_rows.name = "steps_rows"
	vb.add_child(_rows)
	_say = Label.new()
	_say.name = "steps_say"
	_say.add_theme_color_override("font_color", Tok.of("info"))
	_say.autowrap_mode = TextServer.AUTOWRAP_WORD
	_say.custom_minimum_size = Vector2(300, 0)
	vb.add_child(_say)
	_show_rows()
	_say.text = "Type a step and press Enter. Edit a step and press Enter to run the list again from it."


func _process(_dt: float) -> void:
	if kmed == null:
		return
	var on_page := kmed.on and kmed.showing and kmed._model_page and not kmed.has_meta("base_body")   # the test cube's panel, not the fighter's body's (it sat over the POSE page tab)
	if not kmed.on and not entries.is_empty():
		entries.clear()   # the test cube was left: the steps went with it
		_show_rows()
	# a Ctrl+Z took the newest step back: its row goes too
	var made := kmed.undo.steps.size()
	var changed := false
	while not entries.is_empty() and int(entries.back()["at"]) + int(entries.back()["n"]) > made:
		entries.pop_back()
		changed = true
	if changed:
		_show_rows()
	if visible != on_page:
		visible = on_page


func _expected() -> int:
	if entries.is_empty():
		return 0
	var e: Dictionary = entries.back()
	return int(e["at"]) + int(e["n"])


## one typed phrase: run it, keep the row when it worked (a refused phrase stays in the box, the words say why)
func _add() -> void:
	var t := _line.text.strip_edges()
	if t == "":
		_say.text = "Type a step first, e.g. extrude the top 5 cm"
		return
	if not entries.is_empty() and kmed.undo.steps.size() != _expected():
		_say.text = "The mesh changed by hand after the last step. Press Ctrl+Z until the last row is gone, or remove a row."
		return
	var at := kmed.undo.steps.size()
	var r := MeshWords.run(kmed.m, t)
	if not bool(r.get("ok", false)):
		_say.text = "Not a step yet: %s. Try a phrase like extrude the top 5 cm" % String(r.get("error", "not understood"))
		return
	entries.append({"text": t, "at": at, "n": int(r.get("steps", 0)), "bad": false})
	_line.text = ""
	_show_rows()
	_say.text = "Step %d added: %s" % [entries.size(), t]


## the row at i is changed (text) or removed (texts = the rest): the mesh goes back to before row i, then the rows run again
func _replay(i: int, new_rows: Array) -> void:
	if not entries.is_empty() and kmed.undo.steps.size() != _expected():
		_say.text = "The mesh changed by hand after the last step. Press Ctrl+Z until the last row is gone, then edit this step."
		return
	if i < entries.size():
		var back_to := int(entries[i]["at"])
		while kmed.undo.steps.size() > back_to:
			kmed.undo.undo()
		kmed.sel.restore(kmed.undo.last_sel)
		kmed.view.mark_dirty()
		entries = entries.slice(0, i)
	var bad := 0
	for t in new_rows:
		var at := kmed.undo.steps.size()
		var r := MeshWords.run(kmed.m, String(t))
		if bool(r.get("ok", false)):
			entries.append({"text": String(t), "at": at, "n": int(r.get("steps", 0)), "bad": false})
		else:
			entries.append({"text": String(t), "at": at, "n": 0, "bad": true, "error": String(r.get("error", ""))})
			bad += 1
	_show_rows()
	_say.text = ("%d step(s) run again. " % new_rows.size()) + ("%d no longer makes sense: the row is red, change its words" % bad if bad > 0 else "Ctrl+Z takes back the newest one")


func _show_rows() -> void:
	for c in _rows.get_children():
		c.queue_free()
		_rows.remove_child(c)
	for i in entries.size():
		var e: Dictionary = entries[i]
		var hb := HBoxContainer.new()
		var num := Label.new()
		num.text = "%d." % (i + 1)
		hb.add_child(num)
		var le := LineEdit.new()
		le.name = "steps_row_%d" % (i + 1)
		le.text = String(e["text"])
		le.custom_minimum_size = Vector2(240, 0)
		le.add_theme_color_override("font_color", Tok.of("fail") if bool(e["bad"]) else Tok.of("text"))
		le.tooltip_text = "Enter runs the list again from this step"
		le.text_submitted.connect(_edit_row.bind(i))
		hb.add_child(le)
		var x := Button.new()
		x.name = "steps_remove_%d" % (i + 1)
		x.text = "x"
		x.tooltip_text = "remove this step (the steps after it run again)"
		x.focus_mode = Control.FOCUS_NONE
		x.pressed.connect(_remove_row.bind(i))
		hb.add_child(x)
		_rows.add_child(hb)


func _edit_row(new_text: String, i: int) -> void:
	var t := new_text.strip_edges()
	var texts: Array = []
	for k in entries.size():
		if k < i:
			continue
		texts.append(t if k == i and t != "" else String(entries[k]["text"]))
	if t == "":
		_say.text = "A step cannot be empty: press the x to remove it"
		_show_rows()
		return
	_replay(i, texts)


func _remove_row(i: int) -> void:
	var texts: Array = []
	for k in entries.size():
		if k != i and k > i:
			texts.append(String(entries[k]["text"]))
	_replay(i, texts)
