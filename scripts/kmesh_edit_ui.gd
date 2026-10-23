class_name KMeshEditUI
extends Node
## "Model: edit a test cube (preview)" (ROADMAP_400 A05/A06): the first visible step of the MODEL page. A 4x4-per-side cube
## (side 0.6 m, resting on the floor beside the fighter) is added to the stage as a KMeshView; while it is active:
##   1 / 2 / 3  vertex / edge / face mode (the selection converts)      click  select the element under the mouse
##   Shift+click  toggle it in the selection                            B  box select (drag a rectangle), L  lasso (drag a loop)
##   drag from empty space  box select                                  X  x-ray (select through to the far side)
##   A  select all                                                      Esc  disarm B / L, or leave
##   Ctrl+T  triangulate (F06; the selected faces in face mode, else all)  Alt+J  triangles to quads (same rule)
##   H  topology heat map on / off (F08): poles, triangles, n-gons, stretched quads tinted, with a legend of counts
## Right / middle mouse still orbit and pan the camera. Nothing is written to the scene; the cube is dropped on leaving.

const SIDE := 0.6
const SPLIT := 4
const AT := Vector3(1.0, SIDE * 0.5, 0.0)   # on the floor, beside the fighter at the origin

var m: Node
var on := false
var mesh: KMesh
var sel: KMeshSelect
var view: KMeshView
var xray := false
var undo := KMeshUndo.new()   # B16: the Blender-style G / R / S edits, one step each
var armed := ""               # "", "box", "lasso"
var _press := Vector2.ZERO
var _drag := false
var _kind := ""               # the gesture in progress: "click", "box", "lasso"
var _add := false
var _lasso := PackedVector2Array()
var _ov: Control
var legend: PanelContainer   # F08: the heat map's legend (built on first use)


func setup(main: Node) -> void:
	m = main
	_ov = Control.new()
	_ov.name = "kmesh_overlay"
	_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ov.visible = false
	_ov.draw.connect(_draw_overlay)
	m.ui_root.add_child(_ov)


func start() -> void:
	if on:
		return
	mesh = KMeshView.make_cube(SIDE, SPLIT)
	undo = KMeshUndo.new()
	sel = KMeshSelect.new(mesh, KMeshSelect.VERT)
	view = KMeshView.new()
	view.name = "kmesh_view"
	view.set_mesh(mesh, sel)
	m.stage_root.add_child(view)
	view.position = AT
	on = true
	armed = ""
	xray = false
	_ov.visible = true
	view.rebuild()
	m._say("Model: test cube. 1 / 2 / 3 vert / edge / face, click selects, Shift+click adds, B box, L lasso, X x-ray, Esc leaves")


func stop() -> void:
	if not on:
		return
	on = false
	_drag = false
	_ov.visible = false
	if legend != null:
		legend.visible = false
	view.queue_free()
	view = null
	m._say("Model: left the test cube (nothing was saved). Run Model: edit a test cube (preview) to come back")


func set_mode(md: int) -> void:
	sel.set_mode(md)
	view.mark_dirty()
	m._say("Model: %s mode, %d selected. Click an element, or B and drag a box" % [["vertex", "edge", "face"][md], sel.count()])


## main passes every unhandled input here while `on`; true = used
func input(ev: InputEvent) -> bool:
	if not on:
		return false
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k := (ev as InputEventKey).keycode
		if k == KEY_T and (ev as InputEventKey).ctrl_pressed:
			topo("tri")
			return true
		if k == KEY_J and (ev as InputEventKey).alt_pressed:
			topo("quad")
			return true
		if k == KEY_Z and (ev as InputEventKey).ctrl_pressed and (undo.steps.size() > 0 if not (ev as InputEventKey).shift_pressed else undo.redos.size() > 0):
			var lbl := undo.redo() if (ev as InputEventKey).shift_pressed else undo.undo()   # the mesh's own steps first
			sel.clear()
			view.mark_dirty()
			view.rebuild()
			_legend_update()
			m._say("Model: %s %s (%d faces)" % ["redone" if (ev as InputEventKey).shift_pressed else "undone", lbl, mesh.face_count()])
			return true
		if k == KEY_H and not (ev as InputEventKey).ctrl_pressed and not (ev as InputEventKey).alt_pressed:
			topo("heat")
			return true
		match k:
			KEY_1:
				set_mode(KMeshSelect.VERT)
			KEY_2:
				set_mode(KMeshSelect.EDGE)
			KEY_3:
				set_mode(KMeshSelect.FACE)
			KEY_B:
				armed = "box"
				m._say("Model: drag a rectangle to box select (Shift adds, X toggles x-ray, Esc cancels)")
			KEY_L:
				armed = "lasso"
				m._say("Model: drag a loop to lasso select (Shift adds, X toggles x-ray, Esc cancels)")
			KEY_X:
				xray = not xray
				m._say("Model: x-ray %s: box and lasso %s" % ["on" if xray else "off", "select through to the far side" if xray else "only take what you can see"])
			KEY_A:
				sel.select_all()
				view.mark_dirty()
				m._say("Model: all %d selected. Click empty space to clear" % sel.count())
			KEY_ESCAPE:
				if armed != "" or _drag:
					armed = ""
					_drag = false
					_ov.queue_redraw()
					m._say("Model: B / L cancelled. Esc again leaves the test cube")
				else:
					stop()
			_:
				return false
		return true
	if ev is InputEventKey:
		return false
	var cam: Camera3D = m.cam
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		if mb.pressed:
			_press = mb.position
			_add = mb.shift_pressed
			_drag = true
			_lasso = PackedVector2Array([mb.position])
			_cur = mb.position
			if armed != "":
				_kind = armed
			else:
				if view.click(cam, mb.position, _add):
					_kind = "click"
					_report()
				else:
					_kind = "box"   # a press on empty space starts a box; released in place it just clears
					if not _add:
						view.mark_dirty()
			return true
		if not _drag:
			return false
		_drag = false
		var moved := mb.position.distance_to(_press) > 4.0
		match _kind:
			"box":
				if moved:
					view.select_box(cam, Rect2(_press, Vector2.ZERO).expand(mb.position), xray, _add)
					_report()
				elif armed == "":
					_report()
			"lasso":
				if moved:
					view.select_lasso(cam, _lasso, xray, _add)
					_report()
		if armed != "":
			armed = ""
		_ov.queue_redraw()
		return true
	if ev is InputEventMouseMotion and _drag:
		var mp := (ev as InputEventMouseMotion).position
		if _kind == "lasso" and (_lasso.is_empty() or _lasso[_lasso.size() - 1].distance_to(mp) > 3.0):
			_lasso.append(mp)
		_ov.queue_redraw()
		_cur = mp
		return true
	return false


var _cur := Vector2.ZERO


func _report() -> void:
	var nm: String = ["vertices", "edges", "faces"][sel.mode]
	if sel.count() == 0:
		m._say("Model: nothing selected. Click an element, or B and drag a box")
	else:
		m._say("Model: %d %s selected (Shift+click adds, 1 / 2 / 3 converts)" % [sel.count(), nm])


func _draw_overlay() -> void:
	if not on or not _drag:
		return
	var c := Tok.c("pick_hover")
	if _kind == "box":
		var r := Rect2(_press, Vector2.ZERO).expand(_cur)
		_ov.draw_rect(r, Color(c, 0.15), true)
		_ov.draw_rect(r, c, false, 1.0)
	elif _kind == "lasso" and _lasso.size() > 1:
		_ov.draw_polyline(_lasso, c, 1.5)


# ---------------------------------------------------------------- F06 / F08

## "tri" (triangulate), "quad" (tris to quads): the selected faces in face mode, else every face; one KMeshUndo step.
## "heat": the topology heat map on / off.
func topo(what: String) -> void:
	if not on:
		return
	if what == "heat":
		view.show_heat = not view.show_heat
		view.rebuild()
		_legend_update()
		if view.show_heat:
			m._say("Model: topology heat map on: " + KMeshTopo.words(view.heat) + ". H turns it off")
		else:
			m._say("Model: topology heat map off (H turns it on)")
		return
	var only = sel.faces.keys() if sel.mode == KMeshSelect.FACE and not sel.faces.is_empty() else null
	var nf0 := mesh.face_count()
	undo.begin(mesh)
	var r := KMeshTopo.triangulate(mesh, only) if what == "tri" else KMeshTopo.quadrangulate(mesh, only)
	var st := undo.commit("triangulate" if what == "tri" else "tris to quads")
	sel.clear()
	view.mark_dirty()
	view.rebuild()
	_legend_update()
	var scope := "the selected faces" if only != null else "the whole mesh"
	if st.is_empty():
		m._say("Model: nothing to %s in %s (%s)" % ["triangulate" if what == "tri" else "join", scope, "every face is already a triangle" if what == "tri" else "no pair of triangles is flat and square enough"])
	elif what == "tri":
		m._say("Model: triangulated %s: %d faces became %d triangles (%d faces now). Ctrl+Z undoes" % [scope, int(r["faces"]), int(r["tris"]), mesh.face_count()])
	else:
		m._say("Model: tris to quads on %s: %d quads made, %d triangles left (%d faces, was %d). Ctrl+Z undoes" % [scope, int(r["quads"]), int(r["left"]), mesh.face_count(), nf0])


func _legend_update() -> void:
	if legend == null:
		legend = PanelContainer.new()
		legend.name = "topo_legend"
		legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := StyleBoxFlat.new()
		st.bg_color = Color(Tok.c("float"), 0.92)
		st.set_corner_radius_all(8)
		st.set_content_margin_all(8)
		legend.add_theme_stylebox_override("panel", st)
		var vb := VBoxContainer.new()
		vb.name = "rows"
		vb.add_theme_constant_override("separation", 3)
		legend.add_child(vb)
		vb.add_child(m._label("Topology heat map (H)", 14, "text"))
		for r in KMeshTopo.LEGEND:
			var row := HBoxContainer.new()
			row.name = r[0]
			row.add_theme_constant_override("separation", 6)
			var sw := ColorRect.new()
			sw.name = "swatch"
			sw.color = r[3]
			sw.custom_minimum_size = Vector2(14, 14)
			sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(sw)
			var lb: Label = m._label("", 13, "text:0.8")
			lb.name = "words"
			row.add_child(lb)
			vb.add_child(row)
		m.ui_root.add_child(legend)
	legend.visible = on and view != null and view.show_heat
	if not legend.visible:
		return
	var c: Dictionary = view.heat["counts"]
	for r in KMeshTopo.LEGEND:
		var lb: Label = legend.get_node("rows/%s/words" % r[0])
		lb.text = "%s: %d  (%s)" % [r[1], int(c[r[0]]), r[2]]
	legend.reset_size()
	var cl: Rect2 = m.nav_clear_rect()
	legend.position = Vector2(cl.position.x + 12.0, cl.end.y - legend.get_combined_minimum_size().y - 12.0)
