extends RefCounted
## C37 SKETCH SHAPES (M #225, #212): Rounded rectangle and Slot as sketch shapes, a typed Radius field for Circle / corner radius / slot end
## radius, and an opt-in "Size first" flow (type W x D x H, pick a shape, one press makes the solid).
## A shape is drawn from the sketch entities that already exist (lines and arcs, plus the tag "shape"), so the kernel, the dimensions,
## the file format and every old test read it the way they read any sketch. The tools sit in a small row in the SKETCH PALETTE; the
## ribbon, the old tools and their defaults are unchanged: with the Radius field blank, Circle works exactly as before.
## Bars (tests/c37_test.gd): closed profile that extrudes to the analytic volume, one undo step, typed radius, Size first.

const TOOLS := ["Rounded rectangle", "Slot"]
const KINDS := {"Rounded rectangle": "rrect", "Slot": "slot"}
const TIP := {
	"Rounded rectangle": "ROUNDED RECTANGLE: drag from one corner to the other (or click both corners). Type a number in Radius first for the corner size; blank = a fifth of the short side. Or type 40x30 and Enter.",
	"Slot": "SLOT: press one end centre, drag to the other end centre. Type a number in Radius first for the end radius; blank = a fifth of the length. Or type the length and Enter."}
const FIRST_SHAPES := ["Box", "Rounded box", "Slot", "Round"]

var ui: Node   # the PartUI
var row: HFlowContainer
var btns := {}
var radius_edit: LineEdit
var first_btn: Button
var first_panel: PanelContainer
var first_edits := {}
var first_shape := "Box"
var first_shape_btns := {}


func _init(u: Node) -> void:
	ui = u


# ---------------------------------------------------------------- geometry (static, mm)

## A rounded rectangle as lines and quarter arcs (one closed loop). r is clamped to half the short side; r ~ 0 = the plain rect entity.
static func rrect_ents(a: Vector2, b: Vector2, r: float) -> Array:
	var x0 := minf(a.x, b.x)
	var x1 := maxf(a.x, b.x)
	var y0 := minf(a.y, b.y)
	var y1 := maxf(a.y, b.y)
	r = clampf(r, 0.0, minf(x1 - x0, y1 - y0) * 0.5)
	if r < 0.01:
		return [{"k": "rect", "a": Part.arr2(Vector2(x0, y0)), "b": Part.arr2(Vector2(x1, y1)), "shape": "rrect"}]
	var out: Array = []
	var s := 0.70710678
	var sides := [
		[Vector2(x0 + r, y0), Vector2(x1 - r, y0)], [Vector2(x1, y0 + r), Vector2(x1, y1 - r)],
		[Vector2(x1 - r, y1), Vector2(x0 + r, y1)], [Vector2(x0, y1 - r), Vector2(x0, y0 + r)]]
	for sd in sides:
		if (sd[0] as Vector2).distance_to(sd[1]) > 0.01:
			out.append({"k": "line", "a": Part.arr2(sd[0]), "b": Part.arr2(sd[1]), "shape": "rrect"})
	var cs := [Vector2(x1 - r, y0 + r), Vector2(x1 - r, y1 - r), Vector2(x0 + r, y1 - r), Vector2(x0 + r, y0 + r)]
	var dirs := [Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]
	for i in 4:
		var c: Vector2 = cs[i]
		var d: Vector2 = dirs[i]
		var p0: Vector2
		var p1: Vector2
		match i:
			0:
				p0 = c + Vector2(0, -r)
				p1 = c + Vector2(r, 0)
			1:
				p0 = c + Vector2(r, 0)
				p1 = c + Vector2(0, r)
			2:
				p0 = c + Vector2(0, r)
				p1 = c + Vector2(-r, 0)
			_:
				p0 = c + Vector2(-r, 0)
				p1 = c + Vector2(0, -r)
		out.append({"k": "arc", "a": Part.arr2(p0), "m": Part.arr2(c + Vector2(d.x * s, d.y * s) * r), "b": Part.arr2(p1), "shape": "rrect"})
	return out


## A slot: two end centres a and b and an end radius r (the width is 2 r), two straight sides and two half circles.
static func slot_ents(a: Vector2, b: Vector2, r: float) -> Array:
	var d := b - a
	if d.length() < 0.01:
		return [{"k": "circle", "c": Part.arr2(a), "r": r, "shape": "slot"}]
	d = d.normalized()
	var n := Vector2(-d.y, d.x)
	return [
		{"k": "line", "a": Part.arr2(a + n * r), "b": Part.arr2(b + n * r), "shape": "slot"},
		{"k": "arc", "a": Part.arr2(b + n * r), "m": Part.arr2(b + d * r), "b": Part.arr2(b - n * r), "shape": "slot"},
		{"k": "line", "a": Part.arr2(b - n * r), "b": Part.arr2(a - n * r), "shape": "slot"},
		{"k": "arc", "a": Part.arr2(a - n * r), "m": Part.arr2(a - d * r), "b": Part.arr2(a + n * r), "shape": "slot"}]


## the radius a shape gets when the field is blank
static func auto_rrect_r(a: Vector2, b: Vector2) -> float:
	return snappedf(minf(absf(b.x - a.x), absf(b.y - a.y)) * 0.2, 0.01)


static func auto_slot_r(a: Vector2, b: Vector2) -> float:
	return snappedf(a.distance_to(b) * 0.2, 0.01)


## the analytic area (mm2) of each shape, for the tests and the readout
static func rrect_area(w: float, h: float, r: float) -> float:
	r = clampf(r, 0.0, minf(w, h) * 0.5)
	return w * h - (4.0 - PI) * r * r


static func slot_area(centre_len: float, r: float) -> float:
	return centre_len * 2.0 * r + PI * r * r


# ---------------------------------------------------------------- the row in the sketch palette

func build_row(box: Node) -> void:
	row = HFlowContainer.new()
	row.name = "part_shape_row"
	box.add_child(row)
	var fc: Node = ui.free_chk
	if fc != null and fc.get_parent() == box:   # high in the palette: the foot of it sits under the timeline at 1280x720
		box.move_child(row, fc.get_index() + 1)
	for t in TOOLS:
		var b: Button = ui.m._button(t.replace("Rounded rectangle", "Rounded rect"), ui._pick.bind(t), String(TIP[t]))
		b.name = "part_tool_" + t.to_lower().replace(" ", "_")
		b.toggle_mode = true
		btns[t] = b
		row.add_child(b)
	radius_edit = LineEdit.new()
	radius_edit.name = "part_shape_radius"
	radius_edit.placeholder_text = "Radius"
	radius_edit.custom_minimum_size = Vector2(76, 0)
	radius_edit.tooltip_text = "RADIUS (mm; 5, 0.5in and 2 cm work): a Circle click makes a circle of this radius; Rounded rect uses it for the corners; Slot for the ends. Blank = the old way / an automatic size."
	radius_edit.text_changed.connect(func(_t): ui.pov.queue_redraw())
	row.add_child(radius_edit)
	first_btn = ui.m._button("Size first", open_first, "SIZE FIRST: type the width, depth and height, pick a shape, press Make: the solid appears (one undo step). The drawing tools stay as they are.")
	first_btn.name = "part_size_first"
	row.add_child(first_btn)
	_build_first()


func owns(t: String) -> bool:
	return TOOLS.has(t)


func sync() -> void:
	for t in btns:
		(btns[t] as Button).set_pressed_no_signal(t == ui.tool)


## the radius typed in the field in mm; -1 when blank or no length above 0
func radius() -> float:
	if radius_edit == null or radius_edit.text.strip_edges() == "":
		return -1.0
	return ui._typed_len(radius_edit.text.strip_edges())


func pick(t: String) -> void:
	if ui.dlg.size() > 0:
		ui.close_dialog()
	if ui.sk == "":
		ui.begin_sketch("front")
	ui.tool = t
	ui.draft = {}
	ui.typed = ""
	ui.dim_target = {}
	ui.dim_edit.visible = false
	ui.picked = []
	if ui.con_open:
		ui.con_open = false
	ui._tool_sync()
	ui.bu.sync()
	ui.pov.queue_redraw()
	ui._say(String(TIP[t]))


# ---------------------------------------------------------------- drawing with the tools

## a press while a shape tool is picked, or Circle with a typed radius. true = handled
func press(a: Vector2) -> bool:
	if ui.tool == "Circle" and ui.draft.is_empty() and radius() > 0.0:
		ui._add_ent({"k": "circle", "c": Part.arr2(a), "r": radius()})
		ui._say("Circle made, radius %s mm" % ui._fmt(radius()))
		return true
	if not owns(ui.tool):
		return false
	if not ui.draft.is_empty() and not ui.draft.get("down", true):
		ui.draft["b"] = a
		commit()
	else:
		ui.draft = {"k": String(KINDS[ui.tool]), "a": a, "b": a, "down": true}
	return true


## the shapes of a draft a -> b with the field's radius (or the automatic one)
func ents_for(kind: String, a: Vector2, b: Vector2) -> Array:
	var r := radius()
	if kind == "rrect":
		return rrect_ents(a, b, r if r > 0.0 else auto_rrect_r(a, b))
	return slot_ents(a, b, r if r > 0.0 else auto_slot_r(a, b))


## true when the draft was one of ours (committed, or refused in words)
func commit() -> bool:
	var kind := String(ui.draft.get("k", ""))
	if kind != "rrect" and kind != "slot":
		return false
	var a: Vector2 = ui.draft["a"]
	var b: Vector2 = ui.draft["b"]
	var ok := (absf(a.x - b.x) > 0.01 and absf(a.y - b.y) > 0.01) if kind == "rrect" else a.distance_to(b) > 0.01
	if ok:
		_add(ents_for(kind, a, b))
	else:
		ui._say("Drag further to set the size")
	ui.draft = {}
	ui.typed = ""
	return true


func _add(list: Array) -> void:
	var ents: Array = ui._sk()["ents"]
	for e in list:
		ents.append(e)
	ui._after_sketch_edit()   # the whole shape lands in the sketch's one undo step


func draw_draft(c: Color) -> void:
	var a: Vector2 = ui.draft.get("a", Vector2.ZERO)
	var b: Vector2 = ui.draft.get("b", a)
	var kind := String(ui.draft["k"])
	var list := ents_for(kind, a, b) if (a.distance_to(b) > 0.01) else []
	for e in list:
		match String(e["k"]):
			"line":
				ui.pov.draw_line(ui.scr(Part.v2(e["a"])), ui.scr(Part.v2(e["b"])), c, 2.0)
			"arc":
				ui._draw_arc_ent(Part.v2(e["a"]), Part.v2(e["m"]), Part.v2(e["b"]), c)
			"rect":
				ui.pov.draw_polyline(PackedVector2Array([ui.scr(a), ui.scr(Vector2(b.x, a.y)), ui.scr(b), ui.scr(Vector2(a.x, b.y)), ui.scr(a)]), c, 2.0)
			"circle":
				var pts := PackedVector2Array()
				for j in 65:
					pts.append(ui.scr(Part.v2(e["c"]) + Vector2.from_angle(TAU * j / 64.0) * float(e["r"])))
				ui.pov.draw_polyline(pts, c, 2.0)
	if ui.typed != "":
		ui._readout("%s mm (Enter)" % ui.typed)
	elif kind == "rrect":
		var r := radius() if radius() > 0.0 else auto_rrect_r(a, b)
		ui._readout("%s x %s mm, corner R %s" % [ui._fmt(absf(b.x - a.x)), ui._fmt(absf(b.y - a.y)), ui._fmt(r)])
	else:
		var r2 := radius() if radius() > 0.0 else auto_slot_r(a, b)
		ui._readout("ends %s mm apart, R %s" % [ui._fmt(a.distance_to(b)), ui._fmt(r2)])


## keys while a shape is being drawn: a typed size (40x30 for the rounded rectangle, the length for the slot), Backspace, Enter. true = handled
func key(k: InputEventKey) -> bool:
	if not owns(ui.tool) or ui.sk == "" or ui.dim_edit.visible:
		return false
	if radius_edit != null and radius_edit.has_focus():
		return false
	if ui.draft.is_empty():
		if ui._typed_key(k, false) != "":
			ui._say("Click the first point, then type the size")
			return true
		return false
	var kind := String(ui.draft["k"])
	var tk: String = ui._typed_key(k, kind == "rrect")
	if tk != "":
		ui.typed += tk
		ui.pov.queue_redraw()
		return true
	if k.keycode == KEY_BACKSPACE and ui.typed != "":
		ui.typed = ui.typed.left(-1)
		ui.pov.queue_redraw()
		return true
	if k.keycode in [KEY_ENTER, KEY_KP_ENTER] and ui.typed != "":
		var a: Vector2 = ui.draft["a"]
		var cur: Vector2 = ui.draft.get("b", a)
		if kind == "rrect":
			var wh: PackedStringArray = ui.typed.split("x")
			var w: float = ui._typed_len(wh[0]) if wh.size() == 2 else -1.0
			var h: float = ui._typed_len(wh[1]) if wh.size() == 2 else -1.0
			if w <= 0.0 or h <= 0.0:
				ui._say("Type width x height, like 40x30")
				return true
			var sx := 1.0 if cur.x >= a.x else -1.0
			var sy := 1.0 if cur.y >= a.y else -1.0
			_add(ents_for("rrect", a, a + Vector2(sx * w, sy * h)))
		else:
			var l: float = ui._typed_len(ui.typed)
			if l <= 0.0:
				ui._say("Type the length between the two end centres, above 0")
				return true
			var dir := cur - a
			dir = dir.normalized() if dir.length() > 1e-6 else Vector2.RIGHT
			_add(ents_for("slot", a, a + dir * l))
		ui.typed = ""
		ui.draft = {}
		ui.pov.queue_redraw()
		return true
	return false


# ---------------------------------------------------------------- Size first (opt-in beginner flow)

func _build_first() -> void:
	first_panel = PanelContainer.new()
	first_panel.name = "part_size_first_panel"
	first_panel.visible = false
	first_panel.set_anchors_preset(Control.PRESET_CENTER)
	first_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	first_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	ui.m.ui_root.add_child(first_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	first_panel.add_child(vb)
	var t := Label.new()
	t.text = "SIZE FIRST: how big is it?"
	t.add_theme_font_size_override("font_size", 16)
	vb.add_child(t)
	var grid := GridContainer.new()
	grid.columns = 2
	vb.add_child(grid)
	for pair in [["W", "Width (mm)"], ["D", "Depth (mm)"], ["H", "Height (mm)"]]:
		var l := Label.new()
		l.text = String(pair[1])
		grid.add_child(l)
		var e := LineEdit.new()
		e.name = "part_first_" + String(pair[0]).to_lower()
		e.custom_minimum_size = Vector2(110, 0)
		grid.add_child(e)
		first_edits[pair[0]] = e
	var sl := Label.new()
	sl.text = "Then the shape:"
	vb.add_child(sl)
	var sr := HFlowContainer.new()
	vb.add_child(sr)
	for s in FIRST_SHAPES:
		var b := Button.new()
		b.text = s
		b.toggle_mode = true
		b.name = "part_first_shape_" + s.to_lower().replace(" ", "_")
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): pick_first_shape(s))
		sr.add_child(b)
		first_shape_btns[s] = b
	pick_first_shape("Box")
	var br := HBoxContainer.new()
	vb.add_child(br)
	var make := Button.new()
	make.text = "Make it"
	make.name = "part_first_make"
	make.pressed.connect(make_first)
	br.add_child(make)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.name = "part_first_cancel"
	cancel.pressed.connect(func(): first_panel.visible = false)
	br.add_child(cancel)


func pick_first_shape(s: String) -> void:
	first_shape = s
	for k in first_shape_btns:
		(first_shape_btns[k] as Button).set_pressed_no_signal(k == s)


func open_first() -> void:
	first_panel.visible = not first_panel.visible
	if first_panel.visible:
		(first_edits["W"] as LineEdit).grab_focus()
		ui._say("SIZE FIRST: type width, depth and height, pick a shape, then Make it.")


## the ents of a Size-first shape centred on the origin of the top plane (W along x, D the other way); a rounded box uses the Radius field or a sixth of the short side
func first_ents(shape: String, w: float, d: float) -> Array:
	var a := Vector2(-w * 0.5, -d * 0.5)
	var b := Vector2(w * 0.5, d * 0.5)
	match shape:
		"Rounded box":
			var r := radius()
			return rrect_ents(a, b, r if r > 0.0 else snappedf(minf(w, d) / 6.0, 0.01))
		"Slot":
			var r2 := minf(d * 0.5, w * 0.5)
			var half := w * 0.5 - r2
			if half < 0.01:
				return [{"k": "circle", "c": [0.0, 0.0], "r": r2, "shape": "slot"}]
			return slot_ents(Vector2(-half, 0.0), Vector2(half, 0.0), r2)
		"Round":
			return [{"k": "circle", "c": [0.0, 0.0], "r": minf(w, d) * 0.5, "shape": "round"}]
	return [{"k": "rect", "a": Part.arr2(a), "b": Part.arr2(b)}]


## Make it: one undo step, a top-plane sketch and an Extrude of H
func make_first() -> bool:
	var w: float = ui._typed_len((first_edits["W"] as LineEdit).text.strip_edges())
	var d: float = ui._typed_len((first_edits["D"] as LineEdit).text.strip_edges())
	var h: float = ui._typed_len((first_edits["H"] as LineEdit).text.strip_edges())
	if w <= 0.0 or d <= 0.0 or h <= 0.0:
		ui._say("Type all three sizes first (width, depth, height), each above 0")
		return false
	if not Part.available():
		ui._say(Part.why_not())
		return false
	if ui.sk != "":
		ui.finish_sketch()
	var rec: Dictionary = ui._ensure()
	ui.m._step_hint = "Size first"
	ui.m._push_undo()
	var sk := Part.new_feature(rec, "sketch", {"plane": "top", "ents": first_ents(first_shape, w, d), "dims": []})
	rec["features"].append(sk)
	var ex := Part.new_feature(rec, "extrude", {"sketch": sk["id"], "dist": h, "both": false, "op": "new"})
	rec["features"].append(ex)
	ui.upto = -1
	first_panel.visible = false
	ui.tool = ""
	ui._rec_sig = ""
	ui._tool_sync()
	ui.bu.sync()
	ui._view_model()
	ui._say("Made: %s, %s x %s x %s mm. Two steps are on the timeline; double-click one to change it." % [first_shape, ui._fmt(w), ui._fmt(d), ui._fmt(h)])
	return true
