class_name SecondView
extends Control
## SECOND 3D VIEW (lane L37): a second camera on the app's own world (the same hero, the same pose, live), orbited by dragging with the left mouse
## button, zoomed by the wheel. It is a panel like any other: Detach moves it to its own OS window (scripts/panel_detach.gd), for a second monitor.
## It never edits anything; the pose, the playhead and undo stay main's.

const SENS := 0.4   # degrees of orbit per pixel dragged
const ZOOM := 0.9   # distance factor per wheel notch

var m: Node
var sv: SubViewport
var cam: Camera3D
var yaw := 90.0
var pitch := -8.0
var dist := 4.0
var _drag := false
var _last := Vector2.ZERO


func setup(main: Node) -> void:
	m = main
	yaw = float(m.yaw) + 90.0
	dist = float(m.dist)
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(160, 100)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(svc)
	sv = SubViewport.new()
	sv.world_3d = m.get_viewport().world_3d
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.size = Vector2i(320, 220)
	svc.add_child(sv)
	cam = Camera3D.new()
	cam.fov = float(m.cam.fov) if m.cam != null else 50.0
	sv.add_child(cam)
	cam.current = true
	_place()


func _place() -> void:
	if cam == null or m == null:
		return
	var b := Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0))
	cam.transform = Transform3D(b, (m.target as Vector3) + b * Vector3(0, 0, dist))


func orbit(dx: float, dy: float) -> void:
	yaw -= dx * SENS
	pitch = clampf(pitch - dy * SENS, -89.0, 89.0)
	_place()


func _process(_dt: float) -> void:
	_place()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var e := ev as InputEventMouseButton
		if e.button_index == MOUSE_BUTTON_LEFT:
			_drag = e.pressed
			_last = e.position
			accept_event()
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = maxf(0.3, dist * ZOOM)
			_place()
			accept_event()
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = minf(60.0, dist / ZOOM)
			_place()
			accept_event()
	elif ev is InputEventMouseMotion and _drag:
		var d := (ev as InputEventMouseMotion).position - _last   # from positions, so a synthetic motion without `relative` orbits too
		_last = (ev as InputEventMouseMotion).position
		orbit(d.x, d.y)
		accept_event()
