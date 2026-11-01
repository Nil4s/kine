## s193 FIT TO OBJECT (Easy Part, Parts > Boards): one button; it opens a small window where a phone scan (.obj / .glb / .stl from Polycam, Scaniverse,
## RealityScan) is read, laid flat on the floor, given its real size, and turned into a Holder (a block with the object's shape sunk into it, open on
## top) or a Case (two halves split at the widest section). The geometry is scripts/build/part_fit.gd; this file is only the panel.
extends HBoxContainer

const PFit := preload("res://scripts/build/part_fit.gd")
const MM := 0.001

var ep: Node            # the Easy Part panel (its undo, sync and say helpers)
var win: Window
var path_edit: LineEdit
var read_lab: Label
var side_pick: OptionButton
var true_edit: LineEdit
var holder_btn: Button
var case_btn: Button
var clear_sl: HSlider
var wall_sl: HSlider
var depth_sl: HSlider
var clear_lab: Label
var wall_lab: Label
var depth_lab: Label
var depth_row: HBoxContainer
var build_btn: Button
var msg: Label
var open_btn: Button

var base: PackedVector3Array = PackedVector3Array()    # the scan lying flat, in the file's own numbers taken as mm
var tris: PackedVector3Array = PackedVector3Array()    # base x scale: the real size
var k := 1.0
var mode := "holder"
var scan_mi: MeshInstance3D


func setup(easy: Node) -> void:
	ep = easy
	name = "easypart_fit_row"
	visible = false
	open_btn = Button.new()
	open_btn.name = "easypart_fit_open_btn"
	open_btn.text = "Fit to an object"
	open_btn.focus_mode = Control.FOCUS_NONE
	open_btn.tooltip_text = "Scan an object with your phone (Polycam, Scaniverse, RealityScan), export .obj, .glb or .stl, then Kine builds a holder or a case that fits it"
	open_btn.add_theme_font_size_override("font_size", 13)
	open_btn.pressed.connect(open_window)
	add_child(open_btn)


func _row(parent: Control) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	parent.add_child(hb)
	return hb


func _lab(t: String, parent: Control, w := 0.0) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 13)
	if w > 0.0:
		l.custom_minimum_size = Vector2(w, 0)
	parent.add_child(l)
	return l


func _btn(nm: String, t: String, tip: String, f: Callable, parent: Control) -> Button:
	var b := Button.new()
	b.name = nm
	b.text = t
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.pressed.connect(f)
	parent.add_child(b)
	return b


func _slider(nm: String, lo: float, hi: float, step: float, v: float, parent: Control) -> HSlider:
	var s := HSlider.new()
	s.name = nm
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	s.custom_minimum_size = Vector2(90, 24)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(s)
	return s


func open_window() -> void:
	if not Part.available():
		ep._say(Part.why_not())
		return
	if win == null:
		_make_window()
	win.visible = true
	_show_scan()
	ep._say("Fit to an object: type the scan's file name, press Open, then set its real size and press Build")


func _make_window() -> void:
	win = Window.new()
	win.name = "easypart_fit_window"
	win.title = "Fit to an object"
	win.size = Vector2i(660, 272)
	win.position = Vector2i(8, 444)   # the client area; its title bar sits above it. Wide and short: the 3D view above stays free for the scan
	win.exclusive = false
	win.unresizable = true
	win.visible = false
	win.close_requested.connect(func() -> void:
		win.visible = false
		_show_scan())
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	win.add_child(bg)
	var mg := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		mg.add_theme_constant_override("margin_" + s, 8)
	bg.add_child(mg)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	mg.add_child(cols)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.custom_minimum_size = Vector2(330, 0)
	cols.add_child(vb)
	var vb2 := VBoxContainer.new()
	vb2.add_theme_constant_override("separation", 4)
	vb2.custom_minimum_size = Vector2(290, 0)
	cols.add_child(vb2)

	_lab("1. The scan file (.obj, .glb, .stl)", vb)
	var r1 := _row(vb)
	path_edit = LineEdit.new()
	path_edit.name = "easypart_fit_path"
	path_edit.placeholder_text = "C:/Users/you/Downloads/scan.obj"
	path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_edit.add_theme_font_size_override("font_size", 13)
	path_edit.text_submitted.connect(func(_t: String) -> void: open_scan())
	r1.add_child(path_edit)
	_btn("easypart_fit_browse", "Browse", "Pick the scan file", _browse, r1)
	_btn("easypart_fit_open", "Open", "Read the scan and lay it flat on the floor", open_scan, r1)

	read_lab = _lab("No scan yet.", vb)
	read_lab.name = "easypart_fit_read"
	read_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	read_lab.custom_minimum_size = Vector2(320, 66)

	_lab("2. Real size: scans often come in the wrong units", vb)
	var r2 := _row(vb)
	side_pick = OptionButton.new()
	side_pick.name = "easypart_fit_side"
	for t in ["Length", "Width", "Height"]:
		side_pick.add_item(t)
	side_pick.add_theme_font_size_override("font_size", 13)
	r2.add_child(side_pick)
	true_edit = LineEdit.new()
	true_edit.name = "easypart_fit_true"
	true_edit.placeholder_text = "true mm, e.g. 60"
	true_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	true_edit.add_theme_font_size_override("font_size", 13)
	true_edit.text_submitted.connect(func(_t: String) -> void: apply_size())
	r2.add_child(true_edit)
	_btn("easypart_fit_apply", "Set size", "Scale the whole scan so this side is exactly this long (the shape does not stretch)", apply_size, r2)

	_lab("3. What to make", vb2)
	var r3 := _row(vb2)
	holder_btn = _btn("easypart_fit_holder", "Holder", "A block with the object's shape sunk into it, open on top", func() -> void: _set_mode("holder"), r3)
	case_btn = _btn("easypart_fit_case", "Case", "Two halves split at the widest section, with a wall all round", func() -> void: _set_mode("case"), r3)
	holder_btn.toggle_mode = true
	case_btn.toggle_mode = true
	holder_btn.button_pressed = true

	var r4 := _row(vb2)
	_lab("Fit clearance", r4, 92)
	clear_sl = _slider("easypart_fit_clear", 0.1, 1.5, 0.05, 0.4, r4)
	clear_lab = _lab("0.40 mm", r4, 54)
	var r5 := _row(vb2)
	_lab("Wall", r5, 92)
	wall_sl = _slider("easypart_fit_wall", 1.0, 8.0, 0.5, 3.0, r5)
	wall_lab = _lab("3.0 mm", r5, 54)
	depth_row = _row(vb2)
	_lab("Depth (holder)", depth_row, 92)
	depth_sl = _slider("easypart_fit_depth", 3.0, 30.0, 0.5, 30.0, depth_row)
	depth_lab = _lab("", depth_row, 54)
	clear_sl.value_changed.connect(func(_v: float) -> void: _labels())
	wall_sl.value_changed.connect(func(_v: float) -> void: _labels())
	depth_sl.value_changed.connect(func(_v: float) -> void: _labels())

	build_btn = _btn("easypart_fit_build", "Build", "Build it with the CAD kernel: one press, one undo step", build, vb2)
	build_btn.custom_minimum_size = Vector2(0, 34)
	msg = _lab("", vb2)
	msg.name = "easypart_fit_msg"
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(280, 56)
	ep.shape_box.get_parent().add_child(win)
	_labels()


func _labels() -> void:
	clear_lab.text = "%.2f mm" % clear_sl.value
	wall_lab.text = "%.1f mm" % wall_sl.value
	depth_lab.text = "%.1f mm" % depth_sl.value


func _set_mode(md: String) -> void:
	mode = md
	holder_btn.set_pressed_no_signal(md == "holder")
	case_btn.set_pressed_no_signal(md == "case")
	depth_row.visible = md == "holder"


func _browse() -> void:
	var fd := FileDialog.new()
	fd.name = "easypart_fit_dialog"
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.obj, *.glb, *.gltf, *.stl ; 3D scans"])
	fd.title = "Pick your scan"
	fd.file_selected.connect(func(p: String) -> void:
		fd.queue_free()
		path_edit.text = p
		open_scan())
	fd.canceled.connect(fd.queue_free)
	win.add_child(fd)
	fd.popup_centered(Vector2i(560, 400))


func _say(t: String) -> void:
	if msg != null:
		msg.text = t
	ep._say(t)


## Open: read the file, lay the scan flat, show it on the floor with its size as the file gives it
func open_scan() -> void:
	var r := PFit.load_scan(path_edit.text.strip_edges())
	if not bool(r["ok"]):
		_say(String(r["why"]))
		return
	base = PFit.oriented(r["tris"])
	k = 1.0
	tris = base
	var sz := PFit.size_of(base)
	var hint := ""
	var longest := maxf(sz.x, maxf(sz.y, sz.z))
	if longest < 2.0:
		hint = " That is tiny: the file is probably in metres. Type the true length of one side below."
	elif longest > PFit.MAX_SIDE:
		hint = " That is huge: type the true length of one side below."
	_read("Scan as the file says: %s x %s x %s mm, lying flat (longest side along Length).%s" % [_n(sz.x), _n(sz.y), _n(sz.z), hint])
	_after_size()
	_say("Scan read: %d triangles. Set its real size, then press Build" % (base.size() / 3))


func _read(t: String) -> void:
	read_lab.text = t


static func _n(v: float) -> String:
	return "%.2f" % v if absf(v) < 10.0 else "%.1f" % v


## the typed true length of the picked side scales the whole scan the same on every axis
func apply_size() -> void:
	if base.is_empty():
		_say("Open a scan first")
		return
	var want := float(true_edit.text.strip_edges())
	if not (want > 0.0):
		_say("Type the true length of that side in mm, like 60")
		return
	var sz := PFit.size_of(base)
	var cur: float = [sz.x, sz.y, sz.z][side_pick.selected]
	if cur <= 1e-9:
		_say("That side of the scan has no length: pick another side")
		return
	k = want / cur
	tris = PFit.scaled(base, k)
	var s2 := PFit.size_of(tris)
	_read("Real size: %s x %s x %s mm (the file's numbers times %s)." % [_n(s2.x), _n(s2.y), _n(s2.z), String.num(k, 4)])
	_after_size()
	_say("Real size set: %s x %s x %s mm" % [_n(s2.x), _n(s2.y), _n(s2.z)])


func _after_size() -> void:
	var sz := PFit.size_of(tris)
	depth_sl.min_value = 3.0
	depth_sl.max_value = maxf(sz.z + 2.0 * clear_sl.value, 4.0)
	depth_sl.value = depth_sl.max_value
	_labels()
	_show_scan()
	_aim(Vector3(sz.x * 0.5, sz.z * 0.5, -sz.y * 0.5) * MM, maxf(sz.x, sz.y) * MM)


## the camera looks at c (metres) from a 3/4 view, the thing of width span filling about a fifth of the screen, shifted into the free corner:
## above the window while it is open (it sits bottom left), low on the screen once the window has closed (the Easy panel is on the right)
func _aim(c: Vector3, span: float, low := false) -> void:
	ep.m.target = c
	ep.m.dist = clampf(span * (4.6 if low else 3.6), 0.1, 3.0)
	ep.m.pitch = -38.0
	ep.m._cam()
	ep.m.target += ep.m.cam.global_basis.x * (float(ep.m.dist) * 0.34) + ep.m.cam.global_basis.y * (float(ep.m.dist) * (0.17 if low else -0.06))
	ep.m._cam()


## the scan as a see-through shape: on the floor before a build, in its pocket after one
func _show_scan() -> void:
	var want := win != null and not tris.is_empty() and (win.visible or not _rec_fit().is_empty())
	if scan_mi == null:
		if not want:
			return
		scan_mi = MeshInstance3D.new()
		scan_mi.name = "easypart_fit_scan"
		var mt := StandardMaterial3D.new()
		mt.albedo_color = Color(0.25, 0.65, 1.0, 0.55)
		mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mt.cull_mode = BaseMaterial3D.CULL_DISABLED
		mt.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		scan_mi.material_override = mt
		ep.pu.bu.root3.add_child(scan_mi)
	scan_mi.visible = want
	if not want:
		return
	var o := Vector3.ZERO
	var rec_f := _rec_fit()
	if not rec_f.is_empty():
		o = PFit.placement(rec_f)
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	for i in tris.size() / 3:
		var a := Vector3(tris[3 * i].x + o.x, tris[3 * i].z + o.z, -(tris[3 * i].y + o.y)) * MM
		var b := Vector3(tris[3 * i + 1].x + o.x, tris[3 * i + 1].z + o.z, -(tris[3 * i + 1].y + o.y)) * MM
		var c := Vector3(tris[3 * i + 2].x + o.x, tris[3 * i + 2].z + o.z, -(tris[3 * i + 2].y + o.y)) * MM
		var n := (b - a).cross(c - a).normalized()
		vs.append(a)
		vs.append(b)
		vs.append(c)
		ns.append(n)
		ns.append(n)
		ns.append(n)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	scan_mi.mesh = am


## the fit step on the floor now when it is built around THIS scan (the scan moves to its pocket), or {}
func _rec_fit() -> Dictionary:
	var feats: Array = ep._rec().get("features", [])
	if feats.size() != 1 or String(feats[0].get("t", "")) != "fitobj" or tris.is_empty():
		return {}
	var sz := PFit.size_of(tris)
	var fs: Array = feats[0].get("size", [0, 0, 0])
	if absf(float(fs[0]) - sz.x) > 1e-6 or absf(float(fs[1]) - sz.y) > 1e-6 or absf(float(fs[2]) - sz.z) > 1e-6:
		return {}
	return feats[0]


var _shown_hash := 0


func _process(_d: float) -> void:
	if scan_mi != null and scan_mi.visible:
		var h := hash(JSON.stringify(_rec_fit().get("slabs", []))) + hash(str(_rec_fit().get("wall", 0))) * 3 + hash(str(_rec_fit().get("clear", 0))) * 7 + hash(str(_rec_fit().get("mode", "")))
		if _rec_fit().is_empty():
			h = 0
		if h != _shown_hash:
			_shown_hash = h
			_show_scan()


## Build: one solid (Holder) or two halves (Case) from the scan, one undo step
func build() -> void:
	if tris.is_empty():
		_say("Open a scan first")
		return
	var sz := PFit.size_of(tris)
	if not PFit.fits_holder(sz):
		_say("The scan is %s x %s x %s mm. Parts take %d to %d mm a side: type the true length of one side in Real size, then press Build" % [_n(sz.x), _n(sz.y), _n(sz.z), int(PFit.MIN_SIDE), int(PFit.MAX_SIDE)])
		return
	var slabs := PFit.slabs_of(tris)
	if slabs.is_empty():
		_say("The scan has no volume Kine can use: scan the object again")
		return
	var rec: Dictionary = Part.make("Fit " + mode)
	var f: Dictionary = Part.new_feature(rec, "fitobj", PFit.step(mode, slabs, sz, clear_sl.value, wall_sl.value, depth_sl.value))
	rec["features"].append(f)
	ep.armed = ""
	ep.hole_base = {}
	ep.split_id = ""
	ep._flush_if_dirty()
	var snap: Dictionary = ep._rec().duplicate(true)
	ep.m._step_hint = "Fit to an object"
	ep.m._push_undo()
	ep.m.S.part = rec
	ep.tweak = {}
	ep.pu.upto = -1
	ep.pu.sync()
	var want_bodies := 1 if mode == "holder" else 2
	if not (ep.pu.res.get("errors", {}) as Dictionary).is_empty() or int(ep.pu.res.get("bodies", 0)) != want_bodies:
		var why := ""
		for kk in (ep.pu.res.get("errors", {}) as Dictionary):
			why = String(ep.pu.res["errors"][kk])
		ep.m.S.part = snap
		ep.m._drop_undo()
		ep.pu.upto = -1
		ep.pu.sync()
		_say("That did not build%s. Nothing was changed: try a smaller wall or clearance" % ((": " + why) if why != "" else ""))
		return
	_show_scan()
	var bb: AABB = ep.pu.res.get("aabb", AABB())
	_aim(bb.get_center(), maxf(bb.size.x, bb.size.z), true)
	win.visible = false   # the result is what to look at now; the Fit to an object button brings the window back
	_show_scan()
	_say("%s built around your scan (%s x %s x %s mm, clearance %.2f mm, wall %.1f mm). Undo takes it back" % ["A holder" if mode == "holder" else "A two-half case", _n(sz.x), _n(sz.y), _n(sz.z), clear_sl.value, wall_sl.value])
	ep._screw_sync()
