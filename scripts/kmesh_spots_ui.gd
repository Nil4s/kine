class_name KMeshSpotsUI
extends PanelContainer
## C05 (#311, #619, #618): the "Bad spots" panel (MeshTools line "op:mesh_spots"). Lists the mesh's validate problems, the
## hand-shape findings and the finger-bleed findings, each with a Jump button that selects exactly its elements, draws red
## crosses on them that show through the surface, and turns the camera onto them. "Next spot" cycles; "See-through" makes
## the surface translucent. Placed top left of the free view (below the model-checks panel when that is open).

const NAME := "mesh_spots"
const W := 360.0
const MAX_H := 0.55
const PAD := 12.0

var m: Node
var spots: Array = []
var cur := -1
var see := false
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _head: Label
var _marks: MeshInstance3D


static func of(main: Node) -> KMeshSpotsUI:
	var n = main.ui_root.get_node_or_null(NAME)
	if n == null:
		n = KMeshSpotsUI.new()
		n.name = NAME
		n.m = main
		n._build()
		main.ui_root.add_child(n)
	return n


static func toggle(main: Node) -> String:
	var p := of(main)
	if p.visible:
		p.close()
		return "Model: bad spots closed"
	if main.kmed == null or not main.kmed.on:
		main._kmesh_edit_start()
	p.visible = true
	return p.scan()


func close() -> void:
	visible = false
	if m.kmed != null and m.kmed.view != null:
		KMeshSpots.see_through(m.kmed.view, false)
	if _marks != null:
		_marks.mesh = null
	see = false


func _build() -> void:
	visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = Color(Tok.c("float"), 0.95)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(10)
	add_theme_stylebox_override("panel", st)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	var title: Label = m._label("Bad spots", 15, "text")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	for spec in [["btn_sp_scan", "Scan", "check the mesh again: surface, hands, finger weights"], ["btn_sp_next", "Next spot", "jump to the next bad spot"]]:
		var b := Button.new()
		b.name = spec[0]
		b.text = spec[1]
		b.tooltip_text = spec[2]
		b.pressed.connect(func(): if spec[0] == "btn_sp_scan": scan() else: next_spot())
		top.add_child(b)
	var x := Button.new()
	x.name = "btn_sp_close"
	x.text = "x"
	x.pressed.connect(close)
	top.add_child(x)
	vb.add_child(top)
	var cb := CheckButton.new()
	cb.name = "chk_sp_see"
	cb.text = "See-through"
	cb.tooltip_text = "make the surface translucent so spots behind it show"
	cb.toggled.connect(set_see)
	vb.add_child(cb)
	_head = m._label("", 13, "text", true)
	_head.name = "head"
	_head.custom_minimum_size = Vector2(W - 20.0, 0)
	vb.add_child(_head)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(W - 20.0, 60.0)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	_scroll.add_child(_rows)
	vb.add_child(_scroll)


## all the findings for the open mesh: surface problems, then hands, then finger bleed
func gather() -> Array:
	var ed = m.kmed
	var out := KMeshSpots.spots(ed.mesh)
	if m.skel != null:
		var bones := KMeshAutoWeights.bones_from_skeleton(m.skel)
		var xf: Transform3D = (m.skel as Node3D).global_transform.affine_inverse() * ed.view.global_transform
		for sd in HandShapeCheck.sides(bones):
			out.append_array(HandShapeCheck.check(ed.mesh, bones, sd, xf)["findings"])
		out.append_array(FingerBleedCheck.check(ed.mesh, bones)["findings"])
	return out


func scan() -> String:
	var ed = m.kmed
	if ed == null or not ed.on:
		return "Model: open a mesh first"
	spots = gather()
	cur = -1
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	_head.text = "Nothing wrong found." if spots.is_empty() else "%d bad spot%s" % [spots.size(), "" if spots.size() == 1 else "s"]
	for i in spots.size():
		var f: Dictionary = spots[i]
		var row := VBoxContainer.new()
		row.name = "row_%d" % i
		row.add_child(m._label("%d. %s" % [i + 1, f["title"]], 12, "text", true))
		var b := Button.new()
		b.name = "btn_sp_jump_%d" % i
		b.text = "Jump to it"
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.pressed.connect(jump.bind(i))
		row.add_child(b)
		_rows.add_child(row)
	place()
	var said := "Model: bad spots: " + ("none" if spots.is_empty() else "%d, first: %s" % [spots.size(), spots[0]["title"]])
	m._say(said)
	return said


func next_spot() -> void:
	if not spots.is_empty():
		jump((cur + 1) % spots.size())


func jump(i: int) -> void:
	var ed = m.kmed
	if ed == null or not ed.on or i < 0 or i >= spots.size():
		return
	cur = i
	var f: Dictionary = spots[i]
	var sel: KMeshSelect = ed.sel
	sel.clear()
	sel.mode = int(f["mode"])
	for it in f["items"]:
		match int(f["mode"]):
			0:
				sel.verts[int(it)] = true
			1:
				sel.edges[it as Vector2i] = true
			2:
				sel.faces[int(it)] = true
	ed.view.mark_dirty()
	if _marks == null:
		_marks = MeshInstance3D.new()
		_marks.name = "spot_marks"
		_marks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _marks.get_parent() != ed.view:
		if _marks.get_parent() != null:
			_marks.get_parent().remove_child(_marks)
		ed.view.add_child(_marks)
	_marks.mesh = KMeshSpots.marker_mesh(ed.mesh, f)
	ModelChecksUI.of(m).frame(f)
	m._say("Model: bad spot %d of %d: %s" % [i + 1, spots.size(), f["title"]])


func set_see(on: bool) -> void:
	see = on
	if m.kmed != null and m.kmed.view != null:
		KMeshSpots.see_through(m.kmed.view, on)


func place() -> void:
	var cl: Rect2 = m.nav_clear_rect()
	_scroll.custom_minimum_size.y = 60.0
	var rest := get_combined_minimum_size().y - 60.0
	_scroll.custom_minimum_size.y = clampf(_rows.get_combined_minimum_size().y, 40.0, maxf(40.0, cl.size.y * MAX_H - rest))
	reset_size()
	size = Vector2(W, get_combined_minimum_size().y)
	var y := cl.position.y + PAD
	var mc = m.ui_root.get_node_or_null(ModelChecksUI.NAME)
	if mc != null and mc.visible:
		y += mc.size.y + PAD
	position = Vector2(cl.position.x + PAD, y)


func _process(_dt: float) -> void:
	if visible and (m == null or m.kmed == null or not m.kmed.on):
		visible = false
