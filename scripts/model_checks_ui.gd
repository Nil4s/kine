class_name ModelChecksUI
extends PanelContainer
## "Model: model checks (grade for animation)" (ROADMAP_400 B30; the MeshTools line "op:model_checks" shows / hides it):
## the page of scripts/model_checks.gd in the model preview (kmesh_edit_ui.gd). One button grades the mesh open in the
## preview against the fighter's skeleton: the score (0-100) with its formula, then the problems worst first, each with
## its points, its next step and a "Show me" button that selects exactly the offending elements (in their mode: verts,
## edges or faces) and turns the camera onto them (facing their average normal when they face one way, their radius at
## most 40 % of the view, centred in the free view right of the panel so none of them hides under it).
## PLACED top left of the free view (nav_clear_rect): the Materials panel has the top right, the topology legend the
## bottom left, the region legend the bottom right; the list scrolls past MAX_H of the free view's height.
## No new key (the preview's keys are crowded): the S box line opens it; Esc in the preview leaves as before and the
## panel hides with it.

const NAME := "model_checks"
const W := 360.0
const MAX_H := 0.62      # of the free view's height
const PAD := 12.0
const MIN_REGION := 200.0   # px
const FRAME_MIN := 0.35  # m

var m: Node
var res := {}            # the last grade
var segs_override = null # a test's own skeleton segments (world); null = the fighter's
var _score: Label
var _formula: Label
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _grade_btn: Button


## the panel of main (made on first use)
static func of(main: Node) -> ModelChecksUI:
	var n = main.ui_root.get_node_or_null(NAME)
	if n == null:
		n = ModelChecksUI.new()
		n.name = NAME
		n.m = main
		n._build()
		main.ui_root.add_child(n)
	return n


## the MeshTools op: shown (and graded at once) / hidden. Returns what it says
static func toggle(main: Node) -> String:
	var p := of(main)
	if p.visible:
		p.visible = false
		return "Model: model checks closed"
	if main.kmed == null or not main.kmed.on:
		main._kmesh_edit_start()
	p.visible = true
	return p.grade_now()


func _build() -> void:
	visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = Color(Tok.c("float"), 0.95)
	st.set_corner_radius_all(8)
	st.set_content_margin_all(10)
	add_theme_stylebox_override("panel", st)
	var vb := VBoxContainer.new()
	vb.name = "vb"
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	var title: Label = m._label("Model checks", 15, "text")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	_grade_btn = Button.new()
	_grade_btn.name = "btn_mc_grade"
	_grade_btn.text = "Grade for animation"
	_grade_btn.tooltip_text = "grade the mesh: poles and n-gons at the joints, edge loops across elbows and knees, thin parts, broken surface, skin weights"
	_grade_btn.pressed.connect(func(): grade_now())
	top.add_child(_grade_btn)
	var close := Button.new()
	close.name = "btn_mc_close"
	close.text = "x"
	close.tooltip_text = "close the model checks"
	close.pressed.connect(func(): visible = false)
	top.add_child(close)
	vb.add_child(top)
	_score = m._label("", 22, "text")
	_score.name = "score"
	vb.add_child(_score)
	_formula = m._label(ModelChecks.FORMULA, 11, "text:0.6", true)
	_formula.name = "formula"
	_formula.custom_minimum_size = Vector2(W - 20.0, 0)
	vb.add_child(_formula)
	_scroll = ScrollContainer.new()
	_scroll.name = "scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(W - 20.0, 60.0)
	_rows = VBoxContainer.new()
	_rows.name = "rows"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	_scroll.add_child(_rows)
	vb.add_child(_scroll)


## grade the preview's mesh now: the panel filled, the score said
func grade_now() -> String:
	var ed = m.kmed
	if ed == null or not ed.on:
		return "Model: open a mesh first (Model: edit a test cube, or Model: edit the body mesh)"
	var segs: Array = segs_override if segs_override != null else (KMeshBody.segments_from_skeleton(m.skel, true) if m.skel != null else [])
	res = ModelChecks.grade(ed.mesh, segs, ed.view.global_transform)
	_fill()
	var fs: Array = res["findings"]
	var said := "Model: model checks: %d / 100 for animation, %s" % [int(res["score"]), "nothing to fix" if fs.is_empty() else "%d problem%s, worst: %s" % [fs.size(), "" if fs.size() == 1 else "s", fs[0]["title"]]]
	if segs.is_empty():
		said += " (no skeleton: the joint checks were skipped)"
	m._say(said)
	return said


func _fill() -> void:
	for c in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	_score.text = "%d / 100" % int(res["score"])
	var fs: Array = res["findings"]
	if fs.is_empty():
		_rows.add_child(m._label("Nothing to fix: ready to animate.", 13, "text:0.8", true))
	for i in fs.size():
		var f: Dictionary = fs[i]
		var row := VBoxContainer.new()
		row.name = "row_%d" % i
		row.add_theme_constant_override("separation", 2)
		var head := HBoxContainer.new()
		var t: Label = m._label("%d. %s" % [i + 1, f["title"]], 13, "text", true)
		t.name = "title"
		head.add_child(t)
		var pts: Label = m._label("-%.1f" % float(f["pts"]), 13, "text:0.8")
		pts.name = "pts"
		head.add_child(pts)
		row.add_child(head)
		var nx: Label = m._label("Next: " + String(f["next"]), 12, "text:0.7", true)
		nx.name = "next"
		row.add_child(nx)
		var b := Button.new()
		b.name = "btn_mc_show_%d" % i
		b.text = "Show me"
		b.tooltip_text = "select these %d element%s and turn the camera onto them" % [int(f["count"]), "" if int(f["count"]) == 1 else "s"]
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.pressed.connect(show_me.bind(i))
		row.add_child(b)
		_rows.add_child(row)
	place()


## "Show me": finding i's elements become the selection (its mode), the camera frames them
func show_me(i: int) -> void:
	var ed = m.kmed
	var fs: Array = res.get("findings", [])
	if ed == null or not ed.on or i < 0 or i >= fs.size():
		return
	var f: Dictionary = fs[i]
	var sel: KMeshSelect = ed.sel
	sel.clear()
	sel.mode = int(f["mode"])
	for it in f["items"]:
		match int(f["mode"]):
			ModelChecks.SEL_VERT:
				sel.verts[int(it)] = true
			ModelChecks.SEL_EDGE:
				sel.edges[it as Vector2i] = true
			ModelChecks.SEL_FACE:
				sel.faces[int(it)] = true
	ed.view.mark_dirty()
	frame(f)
	m._say("Model: %s. %d selected. Next: %s" % [f["title"], sel.count(), f["next"]])


## the camera onto a finding: centred on its elements, far enough for all of them, facing their mean normal
func frame(f: Dictionary) -> void:
	var ed = m.kmed
	var xf: Transform3D = ed.view.global_transform
	var pts := ModelChecks.points_of(ed.mesh, f, xf)
	if pts.is_empty():
		return
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var c := (lo + hi) * 0.5
	var r := (hi - lo).length() * 0.5
	var n := Vector3.ZERO
	var vn: PackedVector3Array = ed.mesh.vert_normals
	for v in _verts_of(ed.mesh, f):
		n += (xf.basis * vn[v]).normalized()
	n /= maxf(1.0, _verts_of(ed.mesh, f).size())
	if n.length() > 0.3:
		n = n.normalized()
		m.yaw = rad_to_deg(atan2(n.x, n.z))
		m.pitch = clampf(rad_to_deg(-asin(clampf(n.y, -1.0, 1.0))), -80.0, 80.0)
	var t := tan(deg_to_rad((m.cam as Camera3D).fov * 0.5))
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var reg := view_region()
	var half := 0.4 * minf(reg.size.x, reg.size.y)   # px: the elements' radius on screen at most this
	m.target = c
	m.dist = maxf(FRAME_MIN, r / maxf(half, 1.0) * vs.y / (2.0 * t) + r)
	m._cam()
	# centred in the part of the free view the panel leaves: the target slides in the view plane by the pixels between
	var cam: Camera3D = m.cam
	var d := reg.get_center() - cam.unproject_position(c)
	var mpp: float = 2.0 * float(m.dist) * t / vs.y
	m.target = c - cam.global_basis.x * d.x * mpp + cam.global_basis.y * d.y * mpp
	m._cam()


## where "Show me" centres the elements: the free view right of the panel (all of it when the panel is hidden or the
## rest is under MIN_REGION px wide)
func view_region() -> Rect2:
	var cl: Rect2 = m.nav_clear_rect()
	if not visible:
		return cl
	var pr := get_global_rect()
	var x0 := pr.end.x + PAD
	if cl.end.x - x0 < MIN_REGION:
		return cl
	return Rect2(x0, cl.position.y, cl.end.x - x0, cl.size.y)


static func _verts_of(mesh: KMesh, f: Dictionary) -> Array:
	var vs := {}
	for it in f["items"]:
		match int(f["mode"]):
			ModelChecks.SEL_VERT:
				vs[int(it)] = true
			ModelChecks.SEL_EDGE:
				vs[(it as Vector2i).x] = true
				vs[(it as Vector2i).y] = true
			ModelChecks.SEL_FACE:
				for v in (mesh.faces[int(it)] as PackedInt32Array):
					vs[v] = true
	return vs.keys()


## top left of the free view; the list scrolls instead of passing MAX_H of its height
func place() -> void:
	var cl: Rect2 = m.nav_clear_rect()
	_scroll.custom_minimum_size.y = 60.0
	var rest := get_combined_minimum_size().y - 60.0   # everything but the list
	var want := _rows.get_combined_minimum_size().y
	_scroll.custom_minimum_size.y = clampf(want, 40.0, maxf(40.0, cl.size.y * MAX_H - rest))
	reset_size()
	size = Vector2(W, get_combined_minimum_size().y)
	position = Vector2(cl.position.x + PAD, cl.position.y + PAD)


func _process(_dt: float) -> void:
	if visible and (m == null or m.kmed == null or not m.kmed.on):
		visible = false   # the preview closed: the page goes with it
	elif visible:
		var cl: Rect2 = m.nav_clear_rect()
		if position != Vector2(cl.position.x + PAD, cl.position.y + PAD):
			place()   # a side panel folded / the window resized
