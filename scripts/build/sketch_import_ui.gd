extends RefCounted
## C53: the Import 2D button of the Part bar and the step it takes (parser: sketch_import.gd).
## import_text puts the drawing into ONE new sketch on the chosen plane (one undo step); what could not be read is listed on the status line.

const SI := preload("res://scripts/build/sketch_import.gd")
const PLANES := ["front", "top", "right"]


## once, when the Part UI is built: the plane menu (Front / Top / Right)
static func attach(ui: Object) -> void:
	var pm := PopupMenu.new()
	pm.name = "part_import2d_plane"
	for p in ["Front", "Top", "Right"]:
		pm.add_item(p)
	pm.id_pressed.connect(func(i): pick_file(ui, PLANES[clampi(i, 0, 2)]))
	ui.m.add_child(pm)
	ui.import2d_menu = pm


## every time the browser is rebuilt (after its Planes rows): the Import 2D row
static func browser_row(ui: Object, vb: Control) -> void:
	var b := Button.new()
	b.name = "part_import2d"
	b.text = "Import 2D"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "Import 2D: an .svg or .dxf drawing becomes a new sketch on the chosen plane, in mm (SVG px at 96 dpi). Closed shapes can be extruded. What cannot be read is listed, never dropped quietly (one undo step)"
	b.pressed.connect(func(): ask(ui))
	vb.add_child(b)
	ui.import2d_btn = b


## the button: pick the plane (Front / Top / Right), then the file
static func ask(ui: Object) -> void:
	var pm: PopupMenu = ui.import2d_menu
	pm.popup(Rect2i(Vector2i(ui.m.get_viewport().get_mouse_position()) + Vector2i(0, 8), Vector2i(0, 0)))


static func pick_file(ui: Object, plane: String) -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.svg, *.dxf ; 2D drawings"])
	fd.use_native_dialog = true
	fd.title = "Import 2D drawing (.svg, .dxf)"
	fd.file_selected.connect(func(p): import_file(ui, p, plane); fd.queue_free())
	fd.canceled.connect(fd.queue_free)
	ui.m.add_child(fd)
	fd.popup_centered(Vector2i(800, 500))


static func import_file(ui: Object, path: String, plane := "front") -> Dictionary:
	var txt := FileAccess.get_file_as_string(path)
	if txt == "":
		var w := "Could not read %s: the file is empty or not there" % path.get_file()
		ui._say(w)
		return {"ok": false, "words": w, "unsupported": []}
	return import_text(ui, path.get_extension(), txt, plane if plane != "" else "front")


static func import_text(ui: Object, ext: String, text: String, plane: String) -> Dictionary:
	var r := SI.parse(ext, text)
	var ents: Array = r["ents"]
	var uns: Array = r["unsupported"]
	var tail := ""
	if uns.size() > 0:
		tail = ". Not imported: %s" % ", ".join(PackedStringArray(uns))
	if ents.is_empty():
		var w := "Nothing to import: the file has no lines, arcs, circles or closed shapes this can read%s" % tail
		ui._say(w)
		return {"ok": false, "words": w, "unsupported": uns, "ents": 0}
	ui.begin_sketch(plane)
	ui._sk()["ents"].append_array(ents)
	ui._after_sketch_edit()
	var w2 := "Imported %d shapes from the %s file. %s%s" % [ents.size(), ext.to_upper(), String(r["units"]), tail]
	ui._say(w2)
	return {"ok": true, "words": w2, "unsupported": uns, "ents": ents.size(), "notes": r["notes"]}


## true when every separate loop of a sketch is a closed profile on its own
static func all_closed(groups: Array) -> bool:
	for g in groups:
		var face: int = Part.KCad.sketch_face(Part.items_of(g), Vector3.ZERO, Vector3.RIGHT, Vector3.BACK)
		if face == 0:
			return false
		Part.KCad.release(face)
	return true
