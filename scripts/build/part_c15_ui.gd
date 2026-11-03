## C15 sketch-palette rows (#206 move a sketch to another plane with a live preview, #414 SVG import with a scale check). They live INSIDE the sketch
## palette (sketch_box), so no new floating panel covers the 3D view or other controls. Engines: sketch_replane.gd, svg_import.gd.
class_name PartC15UI
extends RefCounted

var pu: PartUI
var box: VBoxContainer
var plane_opt: OptionButton
var plane_words: Label
var move_btn: Button
var svg_path: LineEdit
var svg_width: LineEdit
var svg_btn: Button
var svg_words: Label
var ov: Control
var _names: Array = []
var _sig := ""


func _init(p: PartUI) -> void:
	pu = p
	box = VBoxContainer.new()
	box.name = "c15_box"
	box.add_theme_constant_override("separation", 3)
	box.add_child(pu._label("MOVE SKETCH TO PLANE", 12, true))
	plane_opt = OptionButton.new()
	plane_opt.name = "c15_plane"
	plane_opt.focus_mode = Control.FOCUS_NONE
	plane_opt.tooltip_text = "Pick a plane: the outline is previewed there, with the move in mm, before you press Move"
	plane_opt.item_selected.connect(func(_i): _changed())
	box.add_child(plane_opt)
	plane_words = pu._label("", 11, true)
	plane_words.name = "c15_words"
	plane_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plane_words.custom_minimum_size.x = PartUI.PANEL_W - 24.0
	box.add_child(plane_words)
	move_btn = Button.new()
	move_btn.name = "c15_move"
	move_btn.text = "Move sketch here"
	move_btn.focus_mode = Control.FOCUS_NONE
	move_btn.pressed.connect(do_move)
	box.add_child(move_btn)
	box.add_child(pu._label("IMPORT SVG (scale checked)", 12, true))
	svg_path = LineEdit.new()
	svg_path.name = "c15_svg_path"
	svg_path.placeholder_text = "path of the .svg file"
	box.add_child(svg_path)
	svg_width = LineEdit.new()
	svg_width.name = "c15_svg_width"
	svg_width.placeholder_text = "real width in mm (blank = trust the file)"
	box.add_child(svg_width)
	svg_btn = Button.new()
	svg_btn.name = "c15_svg_import"
	svg_btn.text = "Import SVG"
	svg_btn.focus_mode = Control.FOCUS_NONE
	svg_btn.pressed.connect(func(): import_file(svg_path.text))
	box.add_child(svg_btn)
	svg_words = pu._label("", 11, true)
	svg_words.name = "c15_svg_words"
	svg_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	svg_words.custom_minimum_size.x = PartUI.PANEL_W - 24.0
	box.add_child(svg_words)
	var sc := ScrollContainer.new()   # the palette must not grow into the timeline under it: these rows scroll in a short window
	sc.name = "c15_scroll"
	sc.custom_minimum_size = Vector2(0, 110)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(box)
	pu.extras_vb.add_child(sc)
	ov = Control.new()
	ov.name = "c15_overlay"
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.draw.connect(_draw)
	pu.m.ui_root.add_child(ov)


func _sel_name() -> String:
	var i := plane_opt.selected
	return String(_names[i]) if i >= 0 and i < _names.size() else ""


func sync() -> void:
	if pu.sk == "":
		ov.queue_redraw()
		return
	var rec := pu._rec()
	var sig := pu.sk + str((rec.get("features", []) as Array).size()) + String(pu._sk().get("plane", ""))
	if sig != _sig:
		_sig = sig
		var keep := _sel_name()
		plane_opt.clear()
		_names.clear()
		for t in SketchReplane.targets(rec, pu.sk):
			plane_opt.add_item(String(t["words"]))
			_names.append(String(t["name"]))
		var at := _names.find(keep)
		plane_opt.select(at if at >= 0 else _names.find(String(pu._sk().get("plane", "front"))))
	_changed()


func _changed() -> void:
	var pv := preview()
	plane_words.text = String(pv.get("words", pv.get("why", "")))
	move_btn.disabled = not bool(pv.get("ok", false)) or _sel_name() == String(pu._sk().get("plane", ""))
	ov.queue_redraw()


func preview() -> Dictionary:
	if pu.sk == "" or _sel_name() == "":
		return {"ok": false, "why": ""}
	return SketchReplane.preview(pu._rec(), pu.sk, _sel_name())


func choose(plane_name: String) -> void:
	var i := _names.find(plane_name)
	if i >= 0:
		plane_opt.select(i)
	_changed()


func do_move() -> bool:
	if pu.sk == "":
		return false
	var rec := pu._rec()
	var to := _sel_name()
	if String(pu._sk().get("plane", "")) == to:
		return false
	pu.m._step_hint = "Move sketch to plane"
	pu.m._push_undo()
	if not SketchReplane.apply(rec, pu.sk, to):
		pu.m._drop_undo()
		return false
	pu._say("%s moved to the %s." % [String(pu._sk().get("name", "Sketch")), Part.plane_words(rec, to)])
	pu._view_plane(to)
	pu.bu.sync()
	return true


func import_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		svg_words.text = "Cannot open that file. Check the path."
		return {"ok": false}
	return import_text(f.get_as_text())


func import_text(text: String) -> Dictionary:
	var opts := {}
	if svg_width.text.strip_edges() != "":
		opts["width_mm"] = svg_width.text.to_float()
	var rep := SvgImport.parse(text, opts)
	svg_words.text = String(rep["words"]) if bool(rep["ok"]) else String(rep["why"])
	if not bool(rep["ok"]):
		return rep
	var rec := pu._ensure()
	if pu.sk != "":
		pu.finish_sketch()
	pu.m._step_hint = "Import SVG"
	pu.m._push_undo()
	var id := SvgImport.add_to(rec, rep, "front")
	rep["sketch"] = id
	pu._say("SVG imported as %s. %s" % [String(Part.feature(rec, id).get("name", "")), String(rep["words"])])
	pu.begin_sketch("front", id)
	svg_words.text = String(rep["words"])
	return rep


func _draw() -> void:
	if pu.sk == "" or not pu.on:
		return
	var pv := preview()
	if not bool(pv.get("ok", false)) or not bool(pv.get("has_ents", false)) or _sel_name() == String(pu._sk().get("plane", "")):
		return
	var cam: Camera3D = pu.m.cam
	var c: Array = pv["corners_to"]
	var pts := PackedVector2Array()
	for w in c:
		if cam.is_position_behind(w):
			return
		pts.append(cam.unproject_position(w))
	pts.append(pts[0])
	ov.draw_polyline(pts, Color(1.0, 0.75, 0.2), 2.0)
	var cen: Vector3 = (pv["centre_to"] as Vector3) * Part.MM
	ov.draw_circle(cam.unproject_position(cen), 4.0, Color(1.0, 0.75, 0.2))
