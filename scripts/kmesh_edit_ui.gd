class_name KMeshEditUI
extends Node
## "Model: edit a test cube (preview)" (ROADMAP_400 A05/A06): the first visible step of the MODEL page. A 4x4-per-side cube
## (side 0.6 m, resting on the floor beside the fighter) is added to the stage as a KMeshView; while it is active:
##   1 / 2 / 3  vertex / edge / face mode (the selection converts)      click  select the element under the mouse
##   Shift+click  toggle it in the selection                            B  box select (drag a rectangle), L  lasso (drag a loop)
##   drag from empty space  box select                                  X  x-ray (select through to the far side)
##   A  select all                                                      Esc  disarm B / L, or leave
##   M  measure the selection (B20, KMeshMeasure; follows the selection)  Shift+M  next material (the mass with the volume)
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
var meas: KMeshMeasure   # B20: the ruler + readout while measuring, else null


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
	view.queue_free()
	view = null
	meas = null
	m._say("Model: left the test cube (nothing was saved). Run Model: edit a test cube (preview) to come back")


func set_mode(md: int) -> void:
	sel.set_mode(md)
	view.mark_dirty()
	m._say("Model: %s mode, %d selected. Click an element, or B and drag a box" % [["vertex", "edge", "face"][md], sel.count()])
	_remeasure()


func _process(_dt: float) -> void:
	if meas != null and on:
		_ov.queue_redraw()   # the label follows the camera


## main passes every unhandled input here while `on`; true = used
func input(ev: InputEvent) -> bool:
	if not on:
		return false
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k := (ev as InputEventKey).keycode
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
			KEY_M:
				_measure_key((ev as InputEventKey).shift_pressed)
			KEY_A:
				sel.select_all()
				view.mark_dirty()
				m._say("Model: all %d selected. Click empty space to clear" % sel.count())
				_remeasure()
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


## B20: M turns the measure on / off; Shift+M (turning it on if needed) steps the material for the mass
func _measure_key(shift: bool) -> void:
	if meas != null and not shift:
		meas.queue_free()
		meas = null
		_ov.queue_redraw()
		m._say("Model: measure off")
		return
	if meas == null:
		meas = KMeshMeasure.new()
		meas.name = "kmesh_measure"
		view.add_child(meas)
	if shift:
		meas.cycle_material()
	_remeasure()


func _remeasure() -> void:
	if meas == null:
		return
	var r := meas.measure(mesh, sel)
	_ov.queue_redraw()
	m._say("Model: measure %s%s" % [r["text"], "" if meas.material == "" else " (%s %.0f kg/m³)" % [meas.material, meas.density]])


func _report() -> void:
	if meas != null:
		_remeasure()
		return
	var nm: String = ["vertices", "edges", "faces"][sel.mode]
	if sel.count() == 0:
		m._say("Model: nothing selected. Click an element, or B and drag a box")
	else:
		m._say("Model: %d %s selected (Shift+click adds, 1 / 2 / 3 converts)" % [sel.count(), nm])


func _draw_overlay() -> void:
	if on and meas != null:
		meas.draw_label(_ov, m.cam)
	if not on or not _drag:
		return
	var c := Tok.c("pick_hover")
	if _kind == "box":
		var r := Rect2(_press, Vector2.ZERO).expand(_cur)
		_ov.draw_rect(r, Color(c, 0.15), true)
		_ov.draw_rect(r, c, false, 1.0)
	elif _kind == "lasso" and _lasso.size() > 1:
		_ov.draw_polyline(_lasso, c, 1.5)
