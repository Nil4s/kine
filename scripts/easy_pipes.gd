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
	_p3_build()


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


# ---------------------------------------------------------------- s215: Pipe through points (a tube along a path of points placed in 3D)
var p3_pts: Array = []          # Vector3, mm, world
var p3_pick := false            # the next press on the part (or the floor) adds a point
var p3_xyz: LineEdit
var p3_list: Label
var p3_d_btn: Button
var p3_wall_btn: Button
var p3_bend_btn: Button
var p3_make: Button
var p3_pick_btn: Button
var p3_di := 1                  # index in PipeParts.DS
var p3_wi := 1                  # 0 solid, 1 the PVC wall, 2 double
var p3_bi := 0                  # index in P3_BEND
const P3_BEND := [1.5, 2.0, 3.0]   # bend radius in pipe widths


func _p3_build() -> void:
	var t := Label.new()
	t.name = "easypart_p3_words"
	t.text = "Pipe through points: type X Y Z (mm) or click the part, then Make the pipe"
	t.add_theme_font_size_override("font_size", 13)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(t)
	var r1 := HFlowContainer.new()
	r1.add_theme_constant_override("h_separation", 3)
	add_child(r1)
	p3_xyz = LineEdit.new()
	p3_xyz.name = "easypart_p3_xyz"
	p3_xyz.placeholder_text = "X Y Z mm"
	p3_xyz.custom_minimum_size = Vector2(110, 30)
	p3_xyz.tooltip_text = "A point of the pipe's path in millimetres: three numbers, for example 0 0 100"
	p3_xyz.text_submitted.connect(func(_s): _p3_add_typed())
	r1.add_child(p3_xyz)
	var ab := _chip("easypart_p3_add", "Add point", "Adds the typed X Y Z as the next point of the path", _p3_add_typed)
	ab.toggle_mode = false
	r1.add_child(ab)
	p3_pick_btn = _chip("easypart_p3_pick", "Pick on the part", "Then click a face or a corner of the part (or the floor): that spot is the next point. Corners snap", _p3_arm)
	r1.add_child(p3_pick_btn)
	p3_list = Label.new()
	p3_list.name = "easypart_p3_list"
	p3_list.add_theme_font_size_override("font_size", 13)
	p3_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(p3_list)
	var r2 := HFlowContainer.new()
	r2.add_theme_constant_override("h_separation", 3)
	add_child(r2)
	p3_d_btn = _chip("easypart_p3_width", "", "The pipe's outside width. Press to change it", _p3_cycle.bind("d"))
	p3_wall_btn = _chip("easypart_p3_wall", "", "Solid rod, or a hollow pipe with a wall. Press to change it", _p3_cycle.bind("w"))
	p3_bend_btn = _chip("easypart_p3_bend", "", "How wide the bends are, in pipe widths (a bigger number is a gentler bend). Press to change it", _p3_cycle.bind("b"))
	for b in [p3_d_btn, p3_wall_btn, p3_bend_btn]:
		(b as Button).toggle_mode = false
		r2.add_child(b)
	var r3 := HFlowContainer.new()
	r3.add_theme_constant_override("h_separation", 3)
	add_child(r3)
	p3_make = _chip("easypart_p3_make", "Make the pipe", "Sweeps the pipe along the points, with smooth bends at the corners: one step", _p3_make_press)
	p3_make.toggle_mode = false
	r3.add_child(p3_make)
	var cb := _chip("easypart_p3_clear", "Clear points", "Forgets the points (the pipe already made stays)", _p3_clear)
	cb.toggle_mode = false
	r3.add_child(cb)
	_p3_text()


func _p3_text() -> void:
	var d: int = PipeParts.DS[p3_di]
	p3_d_btn.text = "Width %d mm" % d
	p3_wall_btn.text = "Solid" if p3_wi == 0 else "Wall %s mm" % str(_p3_wall())
	p3_bend_btn.text = "Bend %s x" % str(P3_BEND[p3_bi])
	if p3_pts.is_empty():
		p3_list.text = "No points yet"
	else:
		var s: PackedStringArray = []
		for i in p3_pts.size():
			var q: Vector3 = p3_pts[i]
			s.append("%d: %s %s %s" % [i + 1, str(snappedf(q.x, 0.01)), str(snappedf(q.y, 0.01)), str(snappedf(q.z, 0.01))])
		p3_list.text = "Points (mm)  " + "   ".join(s)


func _p3_wall() -> float:
	var w := PipeParts.wall(float(PipeParts.DS[p3_di]))
	return 0.0 if p3_wi == 0 else (w if p3_wi == 1 else w * 2.0)


func _p3_cycle(what: String) -> void:
	if what == "d":
		p3_di = (p3_di + 1) % PipeParts.DS.size()
	elif what == "w":
		p3_wi = (p3_wi + 1) % 3
	else:
		p3_bi = (p3_bi + 1) % P3_BEND.size()
	_p3_text()


func _p3_add_typed() -> void:
	var parts := p3_xyz.text.replace(",", " ").split(" ", false)
	if parts.size() != 3 or not (parts[0].is_valid_float() and parts[1].is_valid_float() and parts[2].is_valid_float()):
		ep._say("Type three numbers: X Y Z in millimetres, for example 0 0 100")
		return
	_p3_push(Vector3(float(parts[0]), float(parts[1]), float(parts[2])))
	p3_xyz.text = ""


func _p3_push(q: Vector3) -> void:
	if not p3_pts.is_empty() and (p3_pts[-1] as Vector3).distance_to(q) < 0.05:
		ep._say("That is the same spot as the last point")
		return
	p3_pts.append(q)
	_p3_text()
	ep._say("Point %d added. Two or more points make a pipe: press Make the pipe" % p3_pts.size())


func _p3_clear() -> void:
	p3_pts = []
	p3_pick = false
	p3_pick_btn.set_pressed_no_signal(false)
	_p3_text()


func _p3_arm() -> void:
	p3_pick = p3_pick_btn.button_pressed
	if p3_pick:
		ep.armed = ""
		ep._say("Click a face or a corner of the part, or the floor: the point goes there")
	else:
		ep._say("Pick on the part cancelled")


## the press while Pick on the part is on: a corner of the part within 14 px wins, else the face under the pointer, else the floor. true = taken
func _p3_press(p: Vector2) -> bool:
	var faces: Array = Part.body_faces(ep._rec(), -1)
	var best := Vector3.ZERO
	var found := false
	var bd := 14.0
	for tris in faces:
		var t: PackedVector3Array = tris
		for v in t:
			if ep.m.cam.is_position_behind(v):
				continue
			var d: float = ep.m.cam.unproject_position(v).distance_to(p)
			if d < bd:
				bd = d
				best = v
				found = true
	if not found:
		var hit: Dictionary = ep.pu._ray_hit(p, faces)
		if not hit.is_empty():
			best = hit["at"]
			found = true
	if not found:
		var ro: Vector3 = ep.m.cam.project_ray_origin(p)
		var rd: Vector3 = ep.m.cam.project_ray_normal(p)
		if absf(rd.y) > 1e-6 and -ro.y / rd.y > 0.0:
			best = ro + rd * (-ro.y / rd.y)
			found = true
	if not found:
		ep._say("Nothing there: click the part or the floor")
		return true
	p3_pick = false
	p3_pick_btn.set_pressed_no_signal(false)
	_p3_push(best * 1000.0)
	return true


## one step: the pipe3d feature, replayed by the kernel; a failure takes the step back and says why
func _p3_make_press() -> void:
	if not Part.available():
		ep._say(Part.why_not())
		return
	if p3_pts.size() < 2:
		ep._say("A pipe needs two points or more: type X Y Z and press Add point")
		return
	ep._flush_if_dirty()
	ep.armed = ""
	var snap: Dictionary = ep._rec().duplicate(true)
	ep._begin("Pipe through points")
	var rec: Dictionary = ep.pu._ensure()
	var pts: Array = []
	for q in p3_pts:
		pts.append([snappedf(q.x, 0.001), snappedf(q.y, 0.001), snappedf(q.z, 0.001)])
	var d: float = PipeParts.DS[p3_di]
	var f := Part.new_feature(rec, "pipe3d", {"pts": pts, "r": d * 0.5, "wall": _p3_wall(), "bend": d * float(P3_BEND[p3_bi]), "op": "join"})
	rec["features"].append(f)
	var err: String = ep._last_error(rec, String(f["id"]))
	if err != "":
		ep.m.S.part = snap
		ep.m._drop_undo()
		ep._edit_n = -1
		ep._say("The pipe was not made: %s" % err)
		return
	ep._end()
	ep.pu.upto = -1
	ep.pu.sync()
	ep._rows_sync()
	ep._values_sync()
	ep.frame()
	ep._say("Pipe made through %d points. Undo takes it back" % p3_pts.size())
	p3_pts = []
	_p3_text()
