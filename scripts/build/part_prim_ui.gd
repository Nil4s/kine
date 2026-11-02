extends RefCounted
## s229: the Expert dialogs of PartPrim (scripts/build/part_prim.gd), kept out of part_ui.gd.
##   PRIMITIVE  (CREATE > Primitive): a shape (box, cylinder, tube, cone, sphere, wedge), typed position and sizes in mm, a name, and what it does
##              (New body / Join / Cut / Intersect). Live preview; OK = one step, one undo.
##   PLANE      (CREATE > Offset plane): a "How" list above the old distance rows: Distance from a plane (the old way), Through 3 points,
##              Angled about an edge, Through an edge at an angle, On a face (click a face). The new plane is in the browser; click it to sketch on it.
## All state lives in ui.pr (a Dictionary rebuilt each time a dialog opens); the controls are named part_prim_* / part_plane_* for tests.

const PPRIM := preload("res://scripts/build/part_prim.gd")
const KIND_TXT := ["Box", "Cylinder", "Tube", "Cone", "Sphere", "Wedge"]
const OP_TXT := ["New body", "Join", "Cut", "Intersect"]
const OP_ID := ["new", "join", "cut", "intersect"]
const MODE_TXT := ["Distance from a plane", "Through 3 points", "Angled about an edge", "Through an edge at an angle", "On a face (click it)"]
const MODE_FROM := ["", "pts", "angle", "edge", "face"]


static func _fmt(v: float) -> String:
	return str(snappedf(v, 0.001))


static func _opt(nm: String, items: Array, sel: int, ui: Object) -> OptionButton:
	var o := OptionButton.new()
	o.name = nm
	o.focus_mode = Control.FOCUS_NONE
	for t in items:
		o.add_item(String(t))
	o.select(clampi(sel, 0, items.size() - 1))
	o.item_selected.connect(func(_i): ui._preview())
	return o


# ---------------------------------------------------------------- PRIMITIVE

static func open_prim(ui: Object, f: Dictionary, edit: int) -> void:
	var pr := {}
	ui.pr = pr
	var kind := String(f.get("kind", "box"))
	var ko := _opt("part_prim_kind", KIND_TXT, maxi(PPRIM.KINDS.find(kind), 0), ui)
	ko.item_selected.connect(func(_i): _rebuild_fields(ui, {}))
	pr["kind"] = ko
	ui.dlg_rows.add_child(ui._pat_row("Shape", ko, ""))
	var nm: LineEdit = ui._field("part_prim_name")
	nm.alignment = HORIZONTAL_ALIGNMENT_LEFT
	nm.custom_minimum_size.x = 110
	nm.text = String(f.get("name", "")) if edit >= 0 else ""
	nm.placeholder_text = "(auto)"
	pr["name"] = nm
	ui.dlg_rows.add_child(ui._pat_row("Name", nm, ""))
	var oo := _opt("part_prim_op", OP_TXT, maxi(OP_ID.find(String(f.get("op", "new"))), 0), ui)
	pr["op"] = oo
	ui.dlg_rows.add_child(ui._pat_row("Does", oo, ""))
	var holder := VBoxContainer.new()
	holder.name = "part_prim_fields"
	holder.add_theme_constant_override("separation", 4)
	pr["holder"] = holder
	ui.dlg_rows.add_child(holder)
	_rebuild_fields(ui, f)


static func _rebuild_fields(ui: Object, f: Dictionary) -> void:
	var pr: Dictionary = ui.pr
	var holder: VBoxContainer = pr["holder"]
	for c in holder.get_children():
		holder.remove_child(c)
		c.queue_free()
	var kind: String = PPRIM.KINDS[(pr["kind"] as OptionButton).selected]
	var fl := {}
	pr["fields"] = fl
	if kind in ["cylinder", "tube", "cone"]:
		var ax := _opt("part_prim_axis", ["Along X", "Along Y (up)", "Along Z"], "xyz".find(String(f.get("axis", "y"))), ui)
		pr["axis"] = ax
		holder.add_child(ui._pat_row("Axis", ax, ""))
	else:
		pr.erase("axis")
	var centre := CheckBox.new()
	centre.name = "part_prim_centre"
	centre.text = "X Y Z is the middle"
	centre.focus_mode = Control.FOCUS_NONE
	centre.button_pressed = bool(f.get("centre", false))
	centre.toggled.connect(func(_b): ui._preview())
	centre.visible = kind == "box"
	pr["centre"] = centre
	# the numbers in compact rows (the panel is short at 1280 x 720): Position (x y z), then Size (the rest), a line of their names under it
	var pos_h := HBoxContainer.new()
	var size_h := HBoxContainer.new()
	var names := []
	var pl: Label = ui._label("Position", 13)
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pos_h.add_child(pl)
	var sl: Label = ui._label("Size", 13)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_h.add_child(sl)
	for row in PPRIM.fields_of(kind):
		var k := String(row[0])
		var le: LineEdit = ui._field("part_prim_" + k)
		le.text = _fmt(float(f.get(k, row[2])))
		le.custom_minimum_size.x = 48
		le.tooltip_text = "%s (mm)" % String(row[1])
		le.placeholder_text = k
		fl[k] = le
		if k in ["x", "y", "z"]:
			pos_h.add_child(le)
		else:
			size_h.add_child(le)
			names.append(String(row[1]))
	holder.add_child(pos_h)
	holder.add_child(size_h)
	var nl: Label = ui._label("%s (mm)%s" % [", ".join(names), "" if kind in ["box", "wedge", "sphere"] else ": from the start cap"], 11, true)
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.custom_minimum_size.x = ui.PANEL_W - 24.0
	holder.add_child(nl)
	holder.add_child(centre)
	ui._preview()


## the feature the dialog describes ({} when a number is missing); PPRIM.problem says why when the numbers are not a solid
static func prim_feature(ui: Object) -> Dictionary:
	var pr: Dictionary = ui.pr
	if pr.is_empty() or not pr.has("fields"):
		return {}
	var kind: String = PPRIM.KINDS[(pr["kind"] as OptionButton).selected]
	var f := {"kind": kind, "op": OP_ID[(pr["op"] as OptionButton).selected]}
	for k in pr["fields"]:
		var v: float = ui._num(pr["fields"][k])
		if is_nan(v):
			return {}
		f[k] = v
	if pr.has("axis"):
		f["axis"] = "xyz"[(pr["axis"] as OptionButton).selected]
	if kind == "box" and (pr["centre"] as CheckBox).button_pressed:
		f["centre"] = true
	var nm := String((pr["name"] as LineEdit).text).strip_edges()
	f["name"] = nm if nm != "" else "%s%d" % [kind.capitalize(), Part.count_of(ui._rec(), "prim") + 1]
	if int(ui.dlg["edit"]) < 0 and f["op"] != "new" and int(ui.res.get("bodies", 0)) == 0:
		f["op"] = "new"   # nothing to join / cut yet: it is the first body
	return f


static func prim_hint(ui: Object) -> String:
	var f := prim_feature(ui)
	if f.is_empty():
		return "Type a number in every field."
	var why := PPRIM.problem(f)
	return why if why != "" else "Type the position and sizes, then OK."


# ---------------------------------------------------------------- PLANE

static func plane_open(ui: Object, f: Dictionary, edit: int) -> void:
	var pr := {}
	ui.pr = pr
	var offset_rows: Array = []
	for c in ui.dlg_rows.get_children():
		offset_rows.append(c)   # the old rows (Distance, the plane list)
	offset_rows.append(ui.f_plane)
	pr["offset_rows"] = offset_rows
	var mode := maxi(MODE_FROM.find(String(f.get("from", ""))), 0)
	var mo := OptionButton.new()
	mo.name = "part_plane_mode"
	mo.focus_mode = Control.FOCUS_NONE
	for t in MODE_TXT:
		mo.add_item(t)
	mo.select(mode)
	mo.item_selected.connect(func(_i): _plane_mode(ui); ui._preview())
	pr["mode"] = mo
	ui.dlg_rows.add_child(mo)
	ui.dlg_rows.move_child(mo, 0)
	var rows := {}
	pr["rows"] = rows
	# 1 three points
	var pts: Array = f.get("p", [[0, 0, 0], [100, 0, 0], [0, 100, 0]])
	var v1 := VBoxContainer.new()
	pr["pts"] = []
	for i in 3:
		var pl: Array = _xyz_row(ui, "part_plane_p%d" % (i + 1), "Point %d" % (i + 1), pts[i] if i < pts.size() else [0, 0, 0])
		v1.add_child(pl[0])
		(pr["pts"] as Array).append(pl[1])
	rows[1] = v1
	# 2 angled about an edge
	var v2 := VBoxContainer.new()
	var bases: Array = ["front", "top", "right"]
	for pf in ui._feats():
		if String(pf["t"]) == "plane" and String(pf["id"]) != String(f.get("id", "")):
			bases.append(String(pf["id"]))
	pr["bases"] = bases
	var bo := _opt("part_plane_base", bases.map(func(b): return Part.plane_words(ui._rec(), String(b)).get_slice(" (", 0)), maxi(bases.find(String(f.get("base", "front"))), 0), ui)
	pr["base"] = bo
	v2.add_child(ui._pat_row("Plane to turn", bo, ""))
	var edge: Variant = f.get("edge", "x")
	var eo := _opt("part_plane_edge", ["Its X axis", "Its Y axis", "An edge (2 points)"], 2 if edge is Array else (1 if String(edge) == "y" else 0), ui)
	eo.item_selected.connect(func(_i): _plane_mode(ui))
	pr["edge"] = eo
	v2.add_child(ui._pat_row("About", eo, ""))
	var ea: Array = _xyz_row(ui, "part_plane_ea", "Edge from", edge[0] if edge is Array else [0, 0, 0])
	var eb: Array = _xyz_row(ui, "part_plane_eb", "Edge to", edge[1] if edge is Array else [100, 0, 0])
	pr["ea"] = ea[1]
	pr["eb"] = eb[1]
	pr["edge_rows"] = [ea[0], eb[0]]
	v2.add_child(ea[0])
	v2.add_child(eb[0])
	var deg: LineEdit = ui._field("part_plane_deg")
	deg.text = _fmt(float(f.get("deg", 30.0)))
	pr["deg"] = deg
	v2.add_child(ui._pat_row("Angle", deg, "deg"))
	var off: LineEdit = ui._field("part_plane_mm")
	off.text = _fmt(float(f.get("mm", 0.0)))
	pr["mm"] = off
	v2.add_child(ui._pat_row("Moved first by", off, "mm"))
	rows[2] = v2
	# 3 through an edge at an angle
	var v3 := VBoxContainer.new()
	var ta: Array = _xyz_row(ui, "part_plane_ta", "Edge from", f.get("a", [0, 0, 0]))
	var tb: Array = _xyz_row(ui, "part_plane_tb", "Edge to", f.get("b", [100, 0, 0]))
	var tdeg: LineEdit = ui._field("part_plane_tdeg")
	tdeg.text = _fmt(float(f.get("deg", 30.0))) if mode == 3 else "30"
	pr["ta"] = ta[1]
	pr["tb"] = tb[1]
	pr["tdeg"] = tdeg
	v3.add_child(ta[0])
	v3.add_child(tb[0])
	v3.add_child(ui._pat_row("Angle from straight up", tdeg, "deg"))
	rows[3] = v3
	# 4 on a face
	var v4 := VBoxContainer.new()
	var fl: Label = ui._label("Click a face of the solid.", 13, true)
	fl.name = "part_plane_face_label"
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fl.custom_minimum_size.x = ui.PANEL_W - 24.0
	pr["face_label"] = fl
	v4.add_child(fl)
	rows[4] = v4
	for k in rows:
		ui.dlg_rows.add_child(rows[k])
	if mode == 4 and f.has("o"):
		ui.dlg["face"] = {"o": f["o"], "n": f["n"]}
	_plane_mode(ui)
	ui._base_faces(edit)
	ui._preview()


## [row, [x, y, z fields]]
static func _xyz_row(ui: Object, nm: String, label: String, v: Variant) -> Array:
	var h := HBoxContainer.new()
	h.name = nm
	var l: Label = ui._label(label, 13)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var fs: Array = []
	for i in 3:
		var le: LineEdit = ui._field("%s_%s" % [nm, "xyz"[i]])
		le.custom_minimum_size.x = 52
		le.text = _fmt(float(v[i]))
		h.add_child(le)
		fs.append(le)
	return [h, fs]


static func plane_mode(ui: Object) -> int:
	return (ui.pr["mode"] as OptionButton).selected if not ui.pr.is_empty() and ui.pr.has("mode") else 0


static func _plane_mode(ui: Object) -> void:
	var pr: Dictionary = ui.pr
	var mode := plane_mode(ui)
	for c in pr["offset_rows"]:
		if c != null and (c as Node).get_parent() != null:
			(c as Control).visible = mode == 0
	for k in pr["rows"]:
		(pr["rows"][k] as Control).visible = int(k) == mode
	var about_edge := (pr["edge"] as OptionButton).selected == 2
	for r in pr["edge_rows"]:
		(r as Control).visible = about_edge
	ui.picked = []


static func _v(ui: Object, fs: Array) -> Variant:
	var out := []
	for le in fs:
		var v: float = ui._num(le)
		if is_nan(v):
			return null
		out.append(v)
	return out


## the plane feature's fields from the open dialog ({} when a number is missing or no face is picked)
static func plane_feature(ui: Object) -> Dictionary:
	var pr: Dictionary = ui.pr
	var mode := plane_mode(ui)
	match mode:
		1:
			var p := []
			for fs in pr["pts"]:
				var v: Variant = _v(ui, fs)
				if v == null:
					return {}
				p.append(v)
			return {"from": "pts", "p": p}
		2:
			var d: float = ui._num(pr["deg"])
			var mm: float = ui._num(pr["mm"])
			if is_nan(d) or is_nan(mm):
				return {}
			var sel: int = (pr["edge"] as OptionButton).selected
			var edge: Variant = "x" if sel == 0 else "y"
			if sel == 2:
				var a: Variant = _v(ui, pr["ea"])
				var b: Variant = _v(ui, pr["eb"])
				if a == null or b == null:
					return {}
				edge = [a, b]
			return {"from": "angle", "base": pr["bases"][(pr["base"] as OptionButton).selected], "edge": edge, "deg": d, "mm": mm}
		3:
			var a3: Variant = _v(ui, pr["ta"])
			var b3: Variant = _v(ui, pr["tb"])
			var d3: float = ui._num(pr["tdeg"])
			if a3 == null or b3 == null or is_nan(d3):
				return {}
			return {"from": "edge", "a": a3, "b": b3, "deg": d3}
		4:
			if not ui.dlg.has("face"):
				return {}
			return {"from": "face", "o": ui.dlg["face"]["o"], "n": ui.dlg["face"]["n"]}
	return {}


static func plane_hint(ui: Object) -> String:
	match plane_mode(ui):
		1: return "Type three points (mm) that are not in a line."
		2: return "Pick the plane to turn, what it turns about, and the angle."
		3: return "Type the two ends of the edge and the angle."
		4: return "Click a face of the solid."
	return "Type the distance from the plane (mm)."


## a click in the view while the plane dialog is on face mode: the face under the pointer becomes the plane
static func face_press(ui: Object, p: Vector2) -> bool:
	var fi: int = ui._pick_face(p)
	if fi < 0:
		ui._say("No face there: click a face of the solid (the front-facing ones)")
		return true
	var fc: Dictionary = ui.face_cache[fi]
	var c: Vector3 = fc["c"] / Part.MM
	var n: Vector3 = fc["n"]
	ui.dlg["face"] = {"o": [snappedf(c.x, 0.0001), snappedf(c.y, 0.0001), snappedf(c.z, 0.0001)], "n": [snappedf(n.x, 0.000001), snappedf(n.y, 0.000001), snappedf(n.z, 0.000001)]}
	ui.picked = [fc]
	(ui.pr["face_label"] as Label).text = "Face at (%s, %s, %s) mm facing (%s, %s, %s)" % [Part._short(c.x), Part._short(c.y), Part._short(c.z), Part._short(n.x), Part._short(n.y), Part._short(n.z)]
	ui._preview()
	ui.pov.queue_redraw()
	return true
