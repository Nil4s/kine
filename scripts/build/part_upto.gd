extends RefCounted
## C44 (#238, #239): Extrude "Up to" a picked face, with an optional offset. The Extrude dialog gets one button, "Up to a face or edge": press it, click
## the face the extrude should end on (the face of any body, front-facing ones), and the distance is worked out from that face. The step stores
## "upto": [x, y, z] mm (the picked face's centre) and "upto_off": mm (stop short of the face when negative, run past it when positive; 0 = end ON it).
## At replay the distance is re-worked from the sketch's plane every time (so editing an earlier step keeps the extrude ending on the face's plane),
## and a step without "upto" is read exactly as before. Distance typed by hand clears the pick.

const MM := 0.001


## the extrude with its distance worked out: a COPY when it carries "upto", the same dictionary otherwise; pl = the sketch's plane (metres)
static func resolve(f: Dictionary, pl: Dictionary) -> Dictionary:
	if not f.has("upto") or pl.is_empty():
		return f
	var p: Array = f["upto"]
	var n: Vector3 = pl["n"]
	var d := ((Vector3(float(p[0]), float(p[1]), float(p[2])) * MM) - (pl["o"] as Vector3)).dot(n) / MM
	if absf(d) < 1e-6:
		return f   # the sketch already lies on that plane: nothing to reach, the stored distance stays
	var g := f.duplicate()
	g["dist"] = d + signf(d) * float(f.get("upto_off", 0.0))
	g["both"] = false
	return g


static func _sync_hint(ui: Object) -> void:
	var l: Label = ui.dlg.get("upto_lab")
	if l == null:
		return
	l.text = "Ends level with what you picked" if ui.dlg.has("upto") else "Click a face or an edge to end on it" if bool(ui.dlg.get("upto_arm", false)) else "or type a distance"


## the rows (called when the Extrude dialog opens; f = the step being edited or {})
static func open_rows(ui: Object, f: Dictionary) -> void:
	ui.dlg.erase("upto")
	ui.dlg["upto_arm"] = false
	if f.has("upto"):
		ui.dlg["upto"] = f["upto"]
	var b := Button.new()
	b.name = "part_upto"
	b.text = "Up to a face or edge"
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "Click a face: the extrude ends on it"
	b.button_pressed = false
	b.toggled.connect(func(on: bool):
		ui.dlg["upto_arm"] = on
		if on:
			var Pt = load("res://scripts/build/part.gd")
			var base: Dictionary = Pt.replay(ui.call("_rec"), int(ui.dlg["edit"]) - 1 if int(ui.dlg["edit"]) >= 0 else ui.upto, {"faces": true, "edges": true, "body": ui.call("_body_measures")})
			ui.face_cache = base["faces"]
			ui.edge_cache = base["edges"]
			ui.hover_face = -1
		_sync_hint(ui)
		ui.pov.queue_redraw())
	ui.dlg_rows.add_child(b)
	var lab := Label.new()
	lab.name = "part_upto_lab"
	lab.add_theme_font_size_override("font_size", 13)
	lab.modulate = Color(1, 1, 1, 0.7)
	ui.dlg["upto_lab"] = lab
	ui.dlg_rows.add_child(lab)
	var h := HBoxContainer.new()
	var l2 := Label.new()
	l2.text = "Offset from the face"
	l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l2)
	var le := LineEdit.new()
	le.name = "part_upto_off"
	le.custom_minimum_size.x = 60
	le.text = str(snappedf(float(f.get("upto_off", 0.0)), 0.001))
	le.text_changed.connect(func(_t): ui.call("_preview"))
	h.add_child(le)
	h.add_child(Label.new())
	(h.get_child(2) as Label).text = "mm"
	ui.dlg["upto_off_le"] = le
	ui.dlg_rows.add_child(h)
	if ui.f_num != null and not ui.f_num.has_meta("c44"):
		ui.f_num.set_meta("c44", true)
		ui.f_num.text_changed.connect(func(_t): _typed(ui))
	_sync_hint(ui)


static func _typed(ui: Object) -> void:
	if ui.dlg.is_empty() or not ui.dlg.has("upto"):
		return
	ui.dlg.erase("upto")
	_sync_hint(ui)


## the dialog's feature gets the pick (dialog_feature calls this after it built an extrude's dictionary)
static func extend(ui: Object, f: Dictionary) -> void:
	if not ui.dlg.has("upto"):
		return
	f["upto"] = ui.dlg["upto"]
	var le: LineEdit = ui.dlg.get("upto_off_le")
	var o: String = le.text.strip_edges() if le != null else "0"
	f["upto_off"] = float(o) if o.is_valid_float() else 0.0


## hover while armed: the face under the pointer lights up
static func hover(ui: Object, p: Vector2) -> void:
	if ui.dlg.get("t", "") != "extrude" or not bool(ui.dlg.get("upto_arm", false)):
		return
	var fi: int = ui.call("_pick_face", p)
	if fi != ui.hover_face:
		ui.hover_face = fi
		ui.pov.queue_redraw()


## a click while armed picks the face; true = the click is used
static func press(ui: Object, p: Vector2) -> bool:
	if ui.dlg.get("t", "") != "extrude" or not bool(ui.dlg.get("upto_arm", false)):
		return false
	var ei: int = ui.call("_pick_edge", p)   # an edge near the pointer wins (#239: end level with an edge); else a face
	var fi: int = -1 if ei >= 0 else ui.call("_pick_face", p)
	if ei < 0 and fi < 0:
		ui.call("_say", "Nothing there: click a face or an edge of the solid")
		return true
	var c: Vector3 = ui.edge_cache[ei]["c"] if ei >= 0 else ui.face_cache[fi]["c"]
	ui.picked = [] if ei >= 0 else [ui.face_cache[fi]]
	ui.dlg["upto"] = [c.x / MM, c.y / MM, c.z / MM]
	ui.dlg["upto_arm"] = false
	var b: Button = ui.dlg_rows.find_child("part_upto", true, false)
	if b != null:
		b.set_pressed_no_signal(false)
	# the number field shows the worked-out distance (a plain extrude of that length would end on the same face)
	var Part = load("res://scripts/build/part.gd")   # at run time: part.gd preloads this file
	var rec: Dictionary = ui.call("_rec")
	var pl := Part.resolve_plane(rec, String((Part.feature(rec, String(ui.dlg.get("sketch", "")))).get("plane", "front")))
	var g := resolve({"upto": ui.dlg["upto"], "upto_off": 0.0, "dist": 10.0}, pl)
	ui.f_num.text = ui.call("_fmt", float(g["dist"]))
	_sync_hint(ui)
	ui.call("_preview")
	ui.pov.queue_redraw()
	return true

