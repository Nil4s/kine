## W16 TEST PRINT: FIT STRIP (Easy Part, Parts > Type it): From / To / Step boxes (mm, default 0.1 / 0.5 / 0.1) and "Test print: fit strip".
## One press adds a plate of pegs and a plate of holes, one cell per clearance with its value cut in (scripts/build/fit_strip.gd), beside what is
## on the floor: ONE undo step. The search box row "Easy Part: Test print: fit strip" presses the same button.
extends VBoxContainer

var ep: Node            # the Easy Part panel
var edits := {}
var go_btn: Button


func setup(easy: Node) -> void:
	ep = easy
	name = "easypart_fitstrip"
	visible = false
	add_theme_constant_override("separation", 3)
	var words := Label.new()
	words.name = "easypart_fitstrip_words"
	words.text = "Test print: pegs and holes with the gap on each side (mm), to find what fits your printer"
	words.add_theme_font_size_override("font_size", 13)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(words)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	add_child(hb)
	for row in [["from", "From", "0.1"], ["to", "To", "0.5"], ["step", "Step", "0.1"]]:
		var l := Label.new()
		l.text = String(row[1])
		l.add_theme_font_size_override("font_size", 13)
		hb.add_child(l)
		var le := LineEdit.new()
		le.name = "easypart_fitstrip_" + String(row[0])
		le.text = String(row[2])
		le.custom_minimum_size = Vector2(52, 0)
		le.add_theme_font_size_override("font_size", 13)
		le.text_submitted.connect(func(_t: String) -> void: _press())
		hb.add_child(le)
		edits[row[0]] = le
	go_btn = Button.new()
	go_btn.name = "easypart_fitstrip_go"
	go_btn.text = "Test print: fit strip"
	go_btn.focus_mode = Control.FOCUS_NONE
	go_btn.tooltip_text = "Add a strip of 5 pegs and 5 holes with growing gaps, each engraved with its gap, to print and test: one press, one undo step"
	go_btn.add_theme_font_size_override("font_size", 13)
	go_btn.pressed.connect(_press)
	add_child(go_btn)


## [lo, hi, step] from the boxes, or [] when one is not a number
func range_of() -> Array:
	var out := []
	for k in ["from", "to", "step"]:
		var t := String((edits[k] as LineEdit).text).replace("mm", "").strip_edges()
		if not t.is_valid_float():
			return []
		out.append(float(t))
	return out


func _press() -> void:
	if not Part.available():
		ep._screw_sync()
		return
	var rg := range_of()
	if rg.is_empty():
		ep._say("Type a number in From, To and Step (mm)")
		return
	var probe := FitStrip.build(rg[0], rg[1], rg[2])
	if not bool(probe["ok"]):
		ep._say(String(probe["why"]))
		return
	ep.armed = ""
	ep.hole_base = {}
	ep.split_id = ""
	ep._flush_if_dirty()
	var snap: Dictionary = ep.m.S.part.duplicate(true)
	ep.m._step_hint = "Test print: fit strip"
	ep.m._push_undo()
	var rec: Dictionary = ep.m.S.part
	var body0 := 0
	var origin := Vector2.ZERO
	if rec.is_empty():
		rec = Part.make("Part")
		ep.m.S.part = rec
	else:
		ep.pu.upto = -1
		ep.pu.sync()
		body0 = int(ep.pu.res.get("bodies", 0))
		var bb: AABB = ep.pu.res.get("aabb", AABB())
		if body0 > 0:
			origin = Vector2(bb.end.x / Part.MM + 10.0, 0.0)   # right of what is there (Kine metres -> mm)
	var d := FitStrip.build(rg[0], rg[1], rg[2], FitStrip.PEG_D, rec, body0, origin)
	ep.tweak = {}
	ep.pu.upto = -1
	ep.pu.sync()
	if not (ep.pu.res.get("errors", {}) as Dictionary).is_empty() or int(ep.pu.res.get("bodies", 0)) != body0 + 2:
		ep.m.S.part = snap
		ep.m._drop_undo()
		ep.pu.upto = -1
		ep.pu.sync()
		ep._say("The strip did not build: try another range")
		return
	ep.frame()
	ep._say("Fit strip: %d pegs and %d holes, gaps %s to %s mm on each side. Print it flat and see which peg turns in which hole" % [(d["cells"] as Array).size(), (d["cells"] as Array).size(), FitStrip.label(float((d["cells"] as Array)[0]["c"])), FitStrip.label(float((d["cells"] as Array)[-1]["c"]))])
	ep._screw_sync()
