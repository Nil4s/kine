class_name KMeshSpotsUI
extends PanelContainer
## C05 (#311, #619, #618): the "Bad spots" panel (MeshTools line "op:mesh_spots"). Lists the mesh's validate problems, the
## hand-shape findings and the finger-bleed findings, each with a Jump button that selects exactly its elements, draws red
## crosses on them that show through the surface, and turns the camera onto them. "Next spot" cycles; "See-through" makes
## the surface translucent. Docked by place(): the tallest free spot of the free view that no other panel covers.

const NAME := "mesh_spots"
const W := 360.0
const PAD := 12.0
const ROW_GAP := 4
const STEP := 6.0
const MIN_LIST := 100.0   # px of list the spot must hold

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
	_head = m._label("Bad spots", 15, "text")
	_head.name = "head"
	_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.clip_text = true
	top.add_child(_head)
	for spec in [["btn_sp_scan", "Scan", "check the mesh again: surface, hands, finger weights"], ["btn_sp_next", "Next", "jump to the next bad spot"]]:
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
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(240.0, 60.0)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", ROW_GAP)
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
	_head.text = "Bad spots: none" if spots.is_empty() else "Bad spots (%d)" % spots.size()
	for i in spots.size():
		var f: Dictionary = spots[i]
		var row := HBoxContainer.new()
		row.name = "row_%d" % i
		row.add_theme_constant_override("separation", 6)
		var lb: Label = m._label("%d. %s" % [i + 1, f["title"]], 12, "text", true)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lb.custom_minimum_size = Vector2(150.0, 0)
		row.add_child(lb)
		var b := Button.new()
		b.name = "btn_sp_jump_%d" % i
		b.text = "Jump"
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
	_recentre(f)
	m._say("Model: bad spot %d of %d: %s" % [i + 1, spots.size(), f["title"]])


## the free view left of this panel: where a jumped-to spot is centred
func view_region() -> Rect2:
	var cl: Rect2 = m.nav_clear_rect()
	if not visible:
		return cl
	var left := Rect2(cl.position, Vector2(position.x - PAD - cl.position.x, cl.size.y))
	var right := Rect2(Vector2(position.x + size.x + PAD, cl.position.y), Vector2(cl.end.x - position.x - size.x - PAD, cl.size.y))
	var r := left if left.size.x >= right.size.x else right
	return r if r.size.x >= 150.0 else cl


func _recentre(f: Dictionary) -> void:
	var ed = m.kmed
	var pts := ModelChecks.points_of(ed.mesh, f, ed.view.global_transform)
	if pts.is_empty():
		return
	var c := Vector3.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var cam: Camera3D = m.cam
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var t := tan(deg_to_rad(cam.fov * 0.5))
	var d := view_region().get_center() - cam.unproject_position(c)
	var mpp: float = 2.0 * float(m.dist) * t / vs.y
	m.target = m.target - cam.global_basis.x * d.x * mpp + cam.global_basis.y * d.y * mpp
	m._cam()


func set_see(on: bool) -> void:
	see = on
	if m.kmed != null and m.kmed.view != null:
		KMeshSpots.see_through(m.kmed.view, on)


## the controls this panel must not cover: visible, clickable (or panels), outside this panel, under 40 % of the window wide
## and 80 % high (the full-width status strips are the free view's own edge: nav_clear_rect), the ones inside another
## listed one dropped
func _blockers() -> Array:
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var rs: Array = []
	for c in m.ui_root.find_children("*", "Control", true, false):
		var ct := c as Control
		if ct == self or is_ancestor_of(ct) or ct.is_ancestor_of(self) or not ct.is_visible_in_tree():
			continue
		if ct.mouse_filter == Control.MOUSE_FILTER_IGNORE and not (ct is PanelContainer):
			continue
		var r := ct.get_global_rect()
		if r.size.x < 8 or r.size.y < 8 or r.size.x > 0.4 * vs.x or r.size.y > 0.8 * vs.y:
			continue
		rs.append(r.grow(2.0))
	return rs.filter(func(r): return not rs.any(func(o): return o != r and o.encloses(r) and o.size > r.size))


func _free(r: Rect2, bl: Array) -> bool:
	for o in bl:
		if (o as Rect2).intersects(r):
			return false
	return true


## docked in the free view where no other panel is: the widest of W / 320 / 280 px that gets MIN_LIST px of list, and the
## tallest spot for it (searched on a STEP px grid, right and top first); at 1280x720 that is the right end of the view
## under the "Editing: ..." bar. The list takes the height left.
func place() -> void:
	var cl: Rect2 = m.nav_clear_rect()
	_scroll.custom_minimum_size.y = 60.0
	reset_size()
	var chrome := get_combined_minimum_size().y - 60.0
	var bl := _blockers()
	var best := Rect2()
	var need := chrome + MIN_LIST
	for w: float in [W, 320.0, 280.0]:
		best = Rect2()
		var y := cl.position.y + 4.0
		while y + need <= cl.end.y - 4.0:
			var x := cl.end.x - w - 4.0
			while x >= cl.position.x + 4.0:
				if _free(Rect2(x, y, w, need), bl):
					var h := need
					while y + h + STEP <= cl.end.y - 4.0 and _free(Rect2(x, y, w, h + STEP), bl):
						h += STEP
					if h > best.size.y:
						best = Rect2(x, y, w, h)
					break
				x -= STEP
			y += STEP
		if best.size.y >= need:
			break
	if best.size.y < need:   # nowhere clear: the old top-left corner at the least height
		best = Rect2(cl.position + Vector2(PAD, PAD), Vector2(W, need))
	_scroll.custom_minimum_size = Vector2(best.size.x - 20.0, clampf(_rows.get_combined_minimum_size().y, 40.0, best.size.y - chrome))
	_head.custom_minimum_size.x = 0.0
	reset_size()
	size = Vector2(best.size.x, get_combined_minimum_size().y)
	position = best.position


func _process(_dt: float) -> void:
	if visible and (m == null or m.kmed == null or not m.kmed.on):
		visible = false
