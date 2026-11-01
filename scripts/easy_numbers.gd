## s229 BY NUMBERS (Easy Part, Parts > Type it): a shape chip (Box, Cylinder, Tube, Cone, Sphere, Wedge), typed position and sizes in mm, and "Add it":
## ONE "prim" step (scripts/build/part_prim.gd), ONE undo step, as its own piece beside what is on the floor (Stick together joins pieces).
## The same record Expert's Primitive dialog and Part.prim(rec, kind, fields) make.
extends VBoxContainer

const PPRIM := preload("res://scripts/build/part_prim.gd")
const KIND_WORDS := {"box": "Box", "cylinder": "Cylinder", "tube": "Tube", "cone": "Cone", "sphere": "Sphere", "wedge": "Wedge"}
const AXIS_WORDS := ["Across (X)", "Up (Y)", "Front to back (Z)"]

var ep: Node            # the Easy Part panel
var kind := "box"
var kind_btns := {}
var grid: GridContainer
var edits := {}
var axis_opt: OptionButton
var add_btn: Button
var words: Label


func setup(easy: Node) -> void:
	ep = easy
	name = "easypart_numbers"
	visible = false
	add_theme_constant_override("separation", 3)
	words = Label.new()
	words.name = "easypart_num_words"
	words.text = "By numbers: pick a shape, type where it goes and how big (mm)"
	words.add_theme_font_size_override("font_size", 13)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(words)
	var kr := HFlowContainer.new()
	kr.add_theme_constant_override("h_separation", 3)
	kr.add_theme_constant_override("v_separation", 3)
	add_child(kr)
	for k in PPRIM.KINDS:
		var b := Button.new()
		b.name = "easypart_num_kind_" + String(k)
		b.text = String(KIND_WORDS[k])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 28)
		b.add_theme_font_size_override("font_size", 12)
		b.tooltip_text = "%s: made in one step from the numbers below" % String(KIND_WORDS[k])
		b.pressed.connect(_kind_press.bind(String(k)))
		kr.add_child(b)
		kind_btns[k] = b
	grid = GridContainer.new()
	grid.name = "easypart_num_grid"
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	add_child(grid)
	var ar := HBoxContainer.new()
	ar.add_theme_constant_override("separation", 4)
	add_child(ar)
	axis_opt = OptionButton.new()
	axis_opt.name = "easypart_num_axis"
	axis_opt.focus_mode = Control.FOCUS_NONE
	for t in AXIS_WORDS:
		axis_opt.add_item(t)
	axis_opt.select(1)
	axis_opt.add_theme_font_size_override("font_size", 12)
	ar.add_child(axis_opt)
	add_btn = Button.new()
	add_btn.name = "easypart_num_add"
	add_btn.text = "Add it"
	add_btn.focus_mode = Control.FOCUS_NONE
	add_btn.custom_minimum_size = Vector2(0, 30)
	add_btn.add_theme_font_size_override("font_size", 13)
	add_btn.tooltip_text = "Add the shape as its own piece: one press, one undo step"
	add_btn.pressed.connect(_add_press)
	ar.add_child(add_btn)
	_kind_press(kind)


func _kind_press(k: String) -> void:
	kind = k
	for b in kind_btns:
		(kind_btns[b] as Button).set_pressed_no_signal(b == k)
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	edits = {}
	for row in PPRIM.fields_of(k):
		var key := String(row[0])
		var l := Label.new()
		l.text = key.to_upper() if key in ["x", "y", "z"] else String(row[1]).replace(" (X)", "").replace(" (Y)", "").replace(" (Z)", "")
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", Color(0.7, 0.73, 0.78))
		grid.add_child(l)
		var le := LineEdit.new()
		le.name = "easypart_num_" + key
		le.text = str(snappedf(float(row[2]), 0.001))
		le.custom_minimum_size = Vector2(50, 0)
		le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		le.select_all_on_focus = true
		le.add_theme_font_size_override("font_size", 12)
		le.text_submitted.connect(func(_t: String) -> void: _add_press())
		grid.add_child(le)
		edits[key] = le
	axis_opt.visible = k in ["cylinder", "tube", "cone"]


## the fields as a record ({} + why when a number is wrong)
func fields() -> Dictionary:
	var f := {"kind": kind, "op": "new"}
	for key in edits:
		var t := String((edits[key] as LineEdit).text).replace("mm", "").strip_edges()
		if not t.is_valid_float():
			return {"why": "Type a number in every box (mm)"}
		f[key] = float(t)
	if kind in ["cylinder", "tube", "cone"]:
		f["axis"] = "xyz"[axis_opt.selected]
	var why := PPRIM.problem(f)
	if why != "":
		return {"why": why[0].to_upper() + why.substr(1)}
	return f


func _add_press() -> void:
	if not Part.available():
		ep._screw_sync()
		return
	var f := fields()
	if f.has("why"):
		ep._say(String(f["why"]))
		return
	ep.armed = ""
	ep.hole_base = {}
	ep.split_id = ""
	ep._flush_if_dirty()
	ep.m._step_hint = "Add a %s" % String(KIND_WORDS[kind]).to_lower()
	ep.m._push_undo()
	var rec: Dictionary = ep.m.S.part
	if rec.is_empty():
		rec = Part.make("Part")
		ep.m.S.part = rec
	Part.prim(rec, kind, f)
	ep.tweak = {}
	ep.pu.upto = -1
	ep.pu.sync()
	ep.frame()
	if not (ep.pu.res.get("errors", {}) as Dictionary).is_empty():
		ep._say("That did not build: Undo takes it back")
	else:
		ep._say("A %s is on the part. Stick together joins it to the others" % String(KIND_WORDS[kind]).to_lower())
	ep._screw_sync()
