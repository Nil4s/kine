## s079 PIPES (Easy Part, Parts > Pipes): kind chips (Pipe, Elbow 90, Elbow 45, T-piece, Sleeve), size chips (the real outside width, 20 25 32 40 50 mm),
## the Fit chip for the sleeve, and "Add to the part" (the next kind joins the end of what is on the floor as its own piece, ready for Stick together).
## The geometry is scripts/build/pipe_parts.gd; this file is only the page.
extends VBoxContainer

var ep: Node            # the Easy Part panel
var kind_btns := {}
var size_btns := {}
var fit_btn: Button
var add_btn: Button
var words: Label
var sel_d := 25
var fit := PipeParts.FIT_DEFAULT


func setup(easy: Node) -> void:
	ep = easy
	name = "easypart_pipes"
	visible = false
	add_theme_constant_override("separation", 3)
	words = Label.new()
	words.name = "easypart_pipe_words"
	words.text = "Pipes: PVC by real size. Pick a kind and an outside width (mm)"
	words.add_theme_font_size_override("font_size", 13)
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(words)
	var kr := HFlowContainer.new()
	kr.add_theme_constant_override("h_separation", 3)
	kr.add_theme_constant_override("v_separation", 3)
	add_child(kr)
	for k in PipeParts.KINDS:
		var b := _chip("easypart_pipe_kind_" + String(k), String(PipeParts.KIND_WORDS[k]), _kind_tip(String(k)), _kind_press.bind(String(k)))
		kr.add_child(b)
		kind_btns[k] = b
	var sr := HFlowContainer.new()
	sr.add_theme_constant_override("h_separation", 3)
	sr.add_theme_constant_override("v_separation", 3)
	add_child(sr)
	for d in PipeParts.DS:
		var b := _chip("easypart_pipe_size_%d" % d, "%d mm" % d, "Outside width %d mm, wall %s mm (PVC pressure pipe)" % [d, str(PipeParts.wall(float(d)))], _size_press.bind(int(d)))
		sr.add_child(b)
		size_btns[d] = b
	var fr := HFlowContainer.new()
	fr.add_theme_constant_override("h_separation", 3)
	add_child(fr)
	fit_btn = _chip("easypart_pipe_fit", "", "How loose the sleeve is on the pipe: Tight 0.0 mm, Snug 0.1, Slides 0.2, Loose 0.4 on each side. Press to change it", _fit_press)
	fit_btn.toggle_mode = false
	fr.add_child(fit_btn)
	add_btn = _chip("easypart_pipe_add", "Add to the part", "On: the next kind is a new piece at the end of what is on the floor. Then Stick together makes them one solid", _add_press)
	fr.add_child(add_btn)
	_fit_text()


func _chip(nm: String, txt: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = txt
	b.tooltip_text = tip
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 30)
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(cb)
	return b


func _kind_tip(k: String) -> String:
	match k:
		"pipe":
			return "A straight pipe, 300 mm long (the Length slider changes it)"
		"elbow":
			return "A 90 degree bend with a short straight end each side"
		"elbow45":
			return "A 45 degree bend with a short straight end each side"
		"tee":
			return "A T: a straight run with a branch off its middle"
	return "A sleeve that slips over the pipe, with the Fit gap"


func _fit_index() -> int:
	for i in PipeParts.FIT_MM.size():
		if absf(float(PipeParts.FIT_MM[i]) - fit) < 0.005:
			return i
	return 2


func _fit_text() -> void:
	fit_btn.text = "Fit: %s %s mm" % [PipeParts.FIT_NAMES[_fit_index()], str(fit)]


func _on_floor() -> bool:
	return PipeParts.KINDS.has(ep._tpl()) and not (ep._rec().get("features", []) as Array).is_empty()


## the chips follow the part on the floor
func sync() -> void:
	var on := _on_floor()
	var cur: String = ep._tpl() if on else ""
	if on:
		var p: Dictionary = (ep._rec().get("easy", {}) as Dictionary).get("p", {})
		sel_d = int(roundf(float(p.get("d", sel_d))))
		if cur == "sleeve":
			fit = float(p.get("fit", fit))
			_fit_text()
	for k in kind_btns:
		var b: Button = kind_btns[k]
		b.set_pressed_no_signal(cur == k)
		ep.m._grey(b, Part.why_not() if not Part.available() else "")
	for d in size_btns:
		var b2: Button = size_btns[d]
		b2.set_pressed_no_signal(int(d) == sel_d)
		ep.m._grey(b2, Part.why_not() if not Part.available() else "")


func _add_press() -> void:
	ep._say("Add to the part is %s. %s" % [("on" if add_btn.button_pressed else "off"), ("The next kind joins the end of the pipe on the floor as its own piece" if add_btn.button_pressed else "The next kind starts a new part")])


## the pose the next piece starts from: the end of the first piece and the pieces added after it
func end_pose(rec: Dictionary) -> Array:
	var e: Dictionary = rec.get("easy", {})
	var p: Dictionary = e.get("p", {})
	var scratch: Array = []
	var pose := PipeParts.add_piece(scratch, String(e["t"]), float(p["d"]), [0.0, 0.0, 0.0], float(p.get("len", 300.0)), float(p.get("fit", PipeParts.FIT_DEFAULT)))
	for x in e.get("xp", []):
		pose = PipeParts.add_piece(scratch, String(x["k"]), float(x["d"]), pose, float(x.get("len", 300.0)), float(x.get("fit", PipeParts.FIT_DEFAULT)))
	return pose


func _finish(label: String) -> void:
	ep.tweak = {}
	ep.pu.upto = -1
	ep.pu.sync()
	ep.frame()
	if not (ep.pu.res.get("errors", {}) as Dictionary).is_empty():
		ep._say("%s did not build. Press Reset, then pick again" % label)
	else:
		ep._say("%s on the floor" % label)
	ep._screw_sync()


func _begin(hint: String) -> void:
	ep.armed = ""
	ep.hole_base = {}
	ep.split_id = ""
	ep._flush_if_dirty()
	ep.m._step_hint = hint
	ep.m._push_undo()


func _kind_press(kind: String) -> void:
	if not Part.available():
		ep._screw_sync()
		return
	var label := "%s %d mm" % [PipeParts.KIND_WORDS[kind], sel_d]
	if add_btn.button_pressed and _on_floor():
		var rec: Dictionary = ep._rec()
		var pose := end_pose(rec)
		if kind == "sleeve" and (absf(float(pose[2])) > 1e-6 or absf(float(pose[0])) > 1e-6):
			ep._say("A sleeve goes on a straight pipe. Add it before the elbow")
			ep._screw_sync()
			return
		_begin("Add %s" % label.to_lower())
		rec = ep._rec()
		var plen := float((rec["easy"]["p"] as Dictionary).get("len", 300.0))
		PipeParts.add_piece(rec["features"], kind, float(sel_d), pose, plen, fit)
		rec["seq"] = maxi(int(rec.get("seq", 0)), (rec["features"] as Array).size())
		if not (rec["easy"] as Dictionary).has("xp"):
			rec["easy"]["xp"] = []
		(rec["easy"]["xp"] as Array).append({"k": kind, "d": sel_d, "len": plen, "fit": fit})
		_finish("Added " + label)
		return
	if ep._tpl() == kind and _on_floor() and int((ep._rec()["easy"]["p"] as Dictionary).get("d", 0)) == sel_d:
		ep._say("Already %s on the floor. Pick another size to change it" % label)
		ep._screw_sync()
		return
	_begin("Start a pipe part")
	ep.m.S.part = PartTemplates.make(kind, {"d": sel_d, "fit": fit})
	if kind == "sleeve":
		ep.m.S.part["fit_mm"] = fit
	_finish(label)


func _size_press(d: int) -> void:
	sel_d = d
	if not (Part.available() and _on_floor()):
		ep._screw_sync()
		return
	var p: Dictionary = ep._rec()["easy"]["p"]
	if int(roundf(float(p.get("d", 0)))) == d:
		ep._say("Already %d mm. Pick another size to change it" % d)
		ep._screw_sync()
		return
	_begin("Change the pipe size")
	PartTemplates.retemplate(ep._rec(), {"d": d})
	_finish("%s %d mm" % [PipeParts.KIND_WORDS[ep._tpl()], d])


func _fit_press() -> void:
	var nxt := (_fit_index() + 1) % PipeParts.FIT_MM.size()
	fit = float(PipeParts.FIT_MM[nxt])
	_fit_text()
	fit_btn.set_pressed_no_signal(false)
	if Part.available() and _on_floor() and ep._tpl() == "sleeve":
		_begin("Change fit")
		PartTemplates.retemplate(ep._rec(), {"fit": fit})
		ep._rec()["fit_mm"] = fit
		_finish("Sleeve with the %s fit" % String(PipeParts.FIT_NAMES[nxt]).to_lower())
		return
	ep._say("%s fit: %s mm on each side. The next sleeve uses it" % [PipeParts.FIT_NAMES[nxt], str(fit)])
