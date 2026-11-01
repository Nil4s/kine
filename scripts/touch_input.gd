class_name TouchInput
extends Node
## Friday plan 173 + 174: touch screens and gamepads drive the same camera and draw tools the mouse does. Added to main as a child.
##
## TOUCH (InputEventScreenTouch / InputEventScreenDrag; Godot's own touch-to-mouse emulation is turned off so two fingers can be told from one)
##   one finger     is the left mouse button: a press, the drag, the release. The press is held back until the finger has moved 6 px (or
##                  lifted), so a second finger landing a moment later has not started a sketch yet; a tap is a click.
##   two fingers    drag together = orbit (the same 0.4 degrees per pixel as a right-mouse drag); spread / pinch = zoom (the camera distance
##                  goes by the ratio of the finger gap); both fingers down and up again without moving = ONE undo.
## PEN            arrives as mouse events with pressure and tilt: nothing here changes them (the sculpt brush reads the pressure per dab,
##                KMeshSculpt.pressure_of). `pen_pressure` / `pen_tilt` keep the last pen reading for a readout.
## GAMEPAD (InputEventJoypadMotion / Button; deadzone 0.15 on every axis, the rest rescaled to 0..1)
##   left stick orbits (90 degrees per second at full tilt), triggers zoom (right in, left out), right stick pans,
##   A fits the view (Easy Part: its Fit view), B goes back (the camera before the last fit; with none, Escape).

const DEADZONE := 0.15
const DEG_PER_PX := 0.4              # the same as main's right-drag orbit
const START_PX := 6.0                # a finger that moved less than this is still a tap
const TAP_MS := 500                  # two fingers down and up inside this, barely moved: an undo
const TAP_MOVE_PX := 14.0
const STICK_DEG_PER_S := 90.0
const PAN_PX_PER_S := 500.0
const ZOOM_PER_S := 0.35             # the distance is multiplied by this much each second at full trigger

var m: Node                          # main
var touches := {}                    # finger index -> position
var mode := ""                       # "" | "one" | "two" | "wait" (two-finger gesture over, waiting for every finger to lift)
var _first := -1                     # the finger that is the mouse
var _start := Vector2.ZERO           # where that finger went down
var _sent := false                   # the mouse press has gone out
var _last := Vector2.ZERO
var _two_t0 := 0
var _two_move := 0.0
var _c_prev := Vector2.ZERO
var _g_prev := 0.0
var axes := {}                       # "device:axis" -> value
var fit_back: Array = []             # the camera before the last A press: [yaw, pitch, dist, target]
var pen_pressure := 0.0
var pen_tilt := Vector2.ZERO
var _no_tap := false                 # the first finger had begun a stroke when the second landed: that is not a tap
var taps := 0                        # two-finger taps that took an undo (a counter the tests read)


func _ready() -> void:
	Input.emulate_mouse_from_touch = false   # the touches below are turned into mouse events here, one finger at a time


func _ep():
	if m == null or m.get("bld") == null or m.bld.part == null:
		return null
	var ep = m.bld.part.get("ep")
	if ep != null and ep.has_method("active") and ep.active():
		return ep
	return null


func _mouse_ev(down: bool, p: Vector2, motion := false, held := true) -> void:
	var e: InputEvent
	if motion:
		var mm := InputEventMouseMotion.new()
		mm.relative = p - _last
		if held:
			mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		e = mm
	else:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = down
		if down:
			mb.button_mask = MOUSE_BUTTON_MASK_LEFT
		e = mb
	(e as InputEventMouse).position = p
	(e as InputEventMouse).global_position = p
	_last = p
	get_viewport().push_input(e, true)


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var pm := ev as InputEventMouseMotion
		if pm.pressure > 0.0:
			pen_pressure = pm.pressure
			pen_tilt = pm.tilt
		return
	if ev is InputEventScreenTouch:
		_touch(ev as InputEventScreenTouch)
	elif ev is InputEventScreenDrag:
		_drag(ev as InputEventScreenDrag)
	elif ev is InputEventJoypadMotion:
		var jm := ev as InputEventJoypadMotion
		axes["%d:%d" % [jm.device, jm.axis]] = jm.axis_value
	elif ev is InputEventJoypadButton and (ev as InputEventJoypadButton).pressed:
		var jb := ev as InputEventJoypadButton
		if jb.button_index == JOY_BUTTON_A:
			pad_fit()
			get_viewport().set_input_as_handled()
		elif jb.button_index == JOY_BUTTON_B:
			pad_back()
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ touch

func _touch(t: InputEventScreenTouch) -> void:
	if t.pressed:
		touches[t.index] = t.position
		if touches.size() == 1:
			mode = "one"
			_no_tap = false
			_first = t.index
			_start = t.position
			_last = t.position
			_sent = false
		elif touches.size() == 2 and mode != "wait":
			if mode == "one":
				_no_tap = _sent
				_cancel_one()
			mode = "two"
			_two_t0 = Time.get_ticks_msec()
			_two_move = 0.0
			_c_prev = _centroid()
			_g_prev = _gap()
		else:
			mode = "wait"
		return
	# released
	if not touches.has(t.index):
		return
	touches[t.index] = t.position
	if mode == "one" and t.index == _first:
		if not _sent:
			_mouse_ev(false, _start, true, false)   # a tap: the pointer arrives, presses and lets go there
			_mouse_ev(true, _start)
		_mouse_ev(false, t.position)
		_sent = false
	elif mode == "two":
		if Time.get_ticks_msec() - _two_t0 <= TAP_MS and _two_move <= TAP_MOVE_PX and not _no_tap:
			taps += 1
			if m != null:
				m.call_deferred("_undo")   # not inside the event dispatch
		mode = "wait"
	touches.erase(t.index)
	if touches.is_empty():
		mode = ""
		_first = -1


func _drag(d: InputEventScreenDrag) -> void:
	if not touches.has(d.index):
		return
	touches[d.index] = d.position
	if mode == "one" and d.index == _first:
		if not _sent:
			if d.position.distance_to(_start) < START_PX:
				return
			_mouse_ev(false, _start, true, false)
			_mouse_ev(true, _start)
			_sent = true
		_mouse_ev(false, d.position, true)
	elif mode == "two" and touches.size() == 2:
		var c := _centroid()
		var g := _gap()
		var dc := c - _c_prev
		_two_move += dc.length() + absf(g - _g_prev)
		if m != null and m.cam != null:
			orbit_px(dc)
			if g > 1.0 and _g_prev > 1.0:
				zoom_by(_g_prev / g)
		_c_prev = c
		_g_prev = g


## the first finger's press had gone out and a second finger has landed: the sketch / drag the press began is dropped, not finished
func _cancel_one() -> void:
	if not _sent:
		return
	var ep = _ep()
	if ep != null and ep.has_method("touch_cancel"):
		ep.touch_cancel()
	_mouse_ev(false, Vector2(-100000.0, -100000.0))   # let go far away: a click on the spot would pick a piece
	_sent = false


func _centroid() -> Vector2:
	var s := Vector2.ZERO
	for k in touches:
		s += touches[k]
	return s / maxf(1.0, float(touches.size()))


func _gap() -> float:
	var ks := touches.keys()
	return (touches[ks[0]] as Vector2).distance_to(touches[ks[1]]) if ks.size() >= 2 else 0.0


# ------------------------------------------------------------------ camera moves (shared by touch and pad)

## the camera turns as a right-mouse drag of d pixels does (main._unhandled_input, "orbit")
func orbit_px(d: Vector2) -> void:
	if m.shot_through:
		m._shot_hand_over()
	m.yaw -= d.x * DEG_PER_PX
	m.pitch = clampf(m.pitch + (d.y if m._mesh_orbit() else -d.y) * DEG_PER_PX, -89.0, 89.0)
	m._cam()


func zoom_by(f: float) -> void:
	m.dist = clampf(float(m.dist) * f, 0.5, 12.0)
	m._cam()


func pan_px(d: Vector2) -> void:
	var k: float = float(m.dist) * 0.0012
	m.target += -m.cam.global_basis.x * d.x * k + m.cam.global_basis.y * d.y * k
	m._cam()


# ------------------------------------------------------------------ gamepad

## an axis after the deadzone: 0 inside it, the rest rescaled so the edge of the deadzone is 0 and full tilt is 1 (signed)
static func dz(v: float) -> float:
	var a := absf(v)
	if a < DEADZONE:
		return 0.0
	return signf(v) * minf(1.0, (a - DEADZONE) / (1.0 - DEADZONE))


func axis(a: int) -> float:
	var best := 0.0
	for dev in 8:
		var v := dz(float(axes.get("%d:%d" % [dev, a], 0.0)))
		if absf(v) > absf(best):
			best = v
	return best


func _process(delta: float) -> void:
	if m == null or m.cam == null or axes.is_empty():
		return
	var dt := minf(delta, 0.1)
	var lx := axis(JOY_AXIS_LEFT_X)
	var ly := axis(JOY_AXIS_LEFT_Y)
	if lx != 0.0 or ly != 0.0:
		orbit_px(Vector2(lx, ly) * (STICK_DEG_PER_S / DEG_PER_PX) * dt)
	var z := axis(JOY_AXIS_TRIGGER_RIGHT) - axis(JOY_AXIS_TRIGGER_LEFT)
	if z != 0.0:
		zoom_by(pow(ZOOM_PER_S, z * dt))
	var rx := axis(JOY_AXIS_RIGHT_X)
	var ry := axis(JOY_AXIS_RIGHT_Y)
	if rx != 0.0 or ry != 0.0:
		pan_px(Vector2(rx, ry) * PAN_PX_PER_S * dt)


## A: the whole part in the clear view. The camera before it is kept for B
func pad_fit() -> void:
	if m == null or m.cam == null:
		return
	fit_back = [m.yaw, m.pitch, float(m.dist), m.target]
	var ep = _ep()
	if ep != null:
		ep.frame()
	else:
		m._turn_to(m.yaw, m.pitch, 4.0, Vector3(0, 0.95, 0), false)


## B: back to the camera before the last fit; with none, Escape (a sketch in hand, a dialog, a mode)
func pad_back() -> void:
	if m == null or m.cam == null:
		return
	if not fit_back.is_empty():
		m._turn_to(float(fit_back[0]), float(fit_back[1]), float(fit_back[2]), fit_back[3], false)
		fit_back = []
		return
	var k := InputEventKey.new()
	k.keycode = KEY_ESCAPE
	k.physical_keycode = KEY_ESCAPE
	k.pressed = true
	get_viewport().push_input(k)
