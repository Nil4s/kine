## CAMERA NAVIGATION SETTINGS (triage W01). Which mouse gesture orbits, pans and zooms the free view, whether the wheel zooms toward
## the cursor, what the orbit turns around (the view's target, the point under the cursor, or the selection), a trackpad-safe switch
## (two-finger scroll pans, pinch zooms), and four presets: Kine, Blender, Fusion, Maya.
## A binding is a string "Alt+Left" / "Middle" / "Shift+Middle" / "" (off): optional Shift/Ctrl/Alt, then Left, Middle or Right; the
## modifiers must match exactly. The Kine preset is exactly the old behaviour (right-drag orbit, middle-drag pan, wheel zoom), for which
## main.gd's own code runs unchanged: press() then returns false. Everything here is a VIEW setting: saved in the settings file
## ([camnav]), never in a scene, never an undo step. The orbit keeps 0.4 deg per pixel, as before.
## "Around the point under the cursor" means the point on the plane through the view target, facing the camera, under the cursor at the
## moment the drag starts. The wheel and the orbit keep that point on the same pixel.
class_name CamNav
extends RefCounted

const SECTION := "camnav"
const WHEEL_STEP := 0.9
const DIST_MIN := 0.5
const DIST_MAX := 12.0
const PRESETS := ["Kine", "Blender", "Fusion", "Maya"]
const PRESET := {
	"Kine": {"orbit": "Right", "pan": "Middle", "zoom_drag": "", "zoom_cursor": false, "pivot": "target"},
	"Blender": {"orbit": "Middle", "pan": "Shift+Middle", "zoom_drag": "Ctrl+Middle", "zoom_cursor": false, "pivot": "target"},
	"Fusion": {"orbit": "Shift+Middle", "pan": "Middle", "zoom_drag": "", "zoom_cursor": true, "pivot": "cursor"},
	"Maya": {"orbit": "Alt+Left", "pan": "Alt+Middle", "zoom_drag": "Alt+Right", "zoom_cursor": false, "pivot": "target"},
}
const PIVOTS := ["target", "cursor", "selection"]

var m: Node
var preset := "Kine"
var orbit := "Right"
var pan := "Middle"
var zoom_drag := ""
var zoom_cursor := false
var pivot := "target"
var trackpad := false
var _pv := Vector3.ZERO      # the point the running orbit turns around (valid while _pv_on)
var _pv_on := false
var _b0 := Basis.IDENTITY    # the camera basis before this orbit step


func _init(main: Node = null) -> void:
	m = main
	apply_preset("Kine")


func apply_preset(nm: String) -> void:
	if not PRESET.has(nm):
		return
	preset = nm
	var p: Dictionary = PRESET[nm]
	orbit = p["orbit"]
	pan = p["pan"]
	zoom_drag = p["zoom_drag"]
	zoom_cursor = p["zoom_cursor"]
	pivot = p["pivot"]


## the preset the bindings equal, else "Custom"
func preset_name() -> String:
	for nm in PRESETS:
		var p: Dictionary = PRESET[nm]
		if p["orbit"] == orbit and p["pan"] == pan and p["zoom_drag"] == zoom_drag and p["zoom_cursor"] == zoom_cursor and p["pivot"] == pivot:
			return nm
	return "Custom"


func is_default() -> bool:
	return orbit == "Right" and pan == "Middle" and zoom_drag == "" and pivot == "target"


static func binding_of(mb: InputEventMouseButton) -> String:
	var nm := {MOUSE_BUTTON_LEFT: "Left", MOUSE_BUTTON_MIDDLE: "Middle", MOUSE_BUTTON_RIGHT: "Right"}.get(mb.button_index, "") as String
	if nm == "":
		return ""
	return ("Shift+" if mb.shift_pressed else "") + ("Ctrl+" if mb.ctrl_pressed else "") + ("Alt+" if mb.alt_pressed else "") + nm


## "orbit" / "pan" / "zoom" for this press, or "" when no gesture is bound to it
func action_for(mb: InputEventMouseButton) -> String:
	var b := binding_of(mb)
	if b == "":
		return ""
	if orbit == b:
		return "orbit"
	if pan == b:
		return "pan"
	if zoom_drag == b:
		return "zoom"
	return ""


## main._unhandled_input calls this for every view press (a mouse button, pressed). true = handled here.
func press(mb: InputEventMouseButton) -> bool:
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if not zoom_cursor:
			return false
		zoom_at(mb.position, WHEEL_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / WHEEL_STEP)
		return true
	if is_default():
		return false   # the old code runs as it always did
	var act := action_for(mb)
	if act == "":
		# a button the old code would have used to orbit / pan, now given away: it does nothing; left stays the pose button
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			# a right CLICK still opens the part's ring (main's release code, "rclick" = the click-or-nothing drag); only a drag is unbound
			m._rpress = {"at": mb.position, "yaw": m.yaw, "pitch": m.pitch, "part": m._pick(mb.position)}
			m.dragging = "rclick"
			return true
		return mb.button_index == MOUSE_BUTTON_MIDDLE
	m.dragging = act
	_pv_on = false
	if act == "orbit":
		_begin_pivot(mb.position)
	return true


func _begin_pivot(pos: Vector2) -> void:
	_pv_on = false
	if pivot == "cursor":
		_pv = point_under(pos)
		_pv_on = true
	elif pivot == "selection" and m.vx != null:
		var bb: AABB = m.vx.sel_aabb()
		_pv = bb.get_center()
		_pv_on = true


## the point on the plane through the view target, facing the camera, under the screen position
func point_under(pos: Vector2) -> Vector3:
	var ro: Vector3 = m.cam.project_ray_origin(pos)
	var rn: Vector3 = m.cam.project_ray_normal(pos)
	var fwd: Vector3 = -m.cam.global_basis.z
	var den := rn.dot(fwd)
	if absf(den) < 1e-6:
		return m.target
	return ro + rn * ((m.target - ro).dot(fwd) / den)


## main calls these two around the yaw / pitch change of one orbit step
func orbit_pre() -> void:
	_b0 = Basis.from_euler(Vector3(deg_to_rad(m.pitch), deg_to_rad(m.yaw), 0))


func orbit_post() -> void:
	if not _pv_on:
		return
	var b1 := Basis.from_euler(Vector3(deg_to_rad(m.pitch), deg_to_rad(m.yaw), 0))
	m.target = _pv + b1 * (_b0.inverse() * (m.target - _pv))   # the pivot keeps its place in the camera's own frame


## the wheel, or a zoom drag, toward the point under pos (that point stays on its pixel)
func zoom_at(pos: Vector2, factor: float) -> void:
	var p := point_under(pos)
	var s0: Vector2 = m.cam.unproject_position(p)
	var d1 := clampf(m.dist * factor, DIST_MIN, DIST_MAX)
	var k: float = d1 / m.dist
	m.target = p + (m.target - p) * k   # the camera moves along the line to p; its look-at point goes with it
	m.dist = d1
	m._cam()
	for i in 3:   # the frustum offsets of the free view make the first step a pixel or so off: pull it back onto its pixel
		var d: Vector2 = s0 - m.cam.unproject_position(p)
		if d.length() < 0.05:
			break
		var vs: Vector2 = m.get_viewport().get_visible_rect().size
		var mpp: float = 2.0 * m.dist * tan(deg_to_rad(m.cam.fov * 0.5)) / vs.y
		m.target -= m.cam.global_basis.x * d.x * mpp - m.cam.global_basis.y * d.y * mpp
		m._cam()


func zoom_drag_move(rel: Vector2, pos: Vector2) -> void:
	var f := pow(1.01, rel.y)   # drag down = back away, as Maya
	if zoom_cursor:
		zoom_at(pos, f)
	else:
		m.dist = clampf(m.dist * f, DIST_MIN, DIST_MAX)
		m._cam()


## trackpad-safe: two-finger scroll pans, pinch zooms. true = handled
func gesture(ev: InputEvent) -> bool:
	if not trackpad:
		return false
	if ev is InputEventPanGesture:
		var k: float = m.dist * 0.0012 * 8.0
		var d: Vector2 = (ev as InputEventPanGesture).delta
		m.target += -m.cam.global_basis.x * d.x * k + m.cam.global_basis.y * d.y * k * -1.0
		m._cam()
		return true
	if ev is InputEventMagnifyGesture:
		var f: float = (ev as InputEventMagnifyGesture).factor
		if f > 0.0:
			var pos: Vector2 = (ev as InputEventMagnifyGesture).position
			if zoom_cursor:
				zoom_at(pos, 1.0 / f)
			else:
				m.dist = clampf(m.dist / f, DIST_MIN, DIST_MAX)
				m._cam()
		return true
	return false


# ---- the settings file ----------------------------------------------------------------------------------------------

func load_from(path: String) -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK or not cf.has_section(SECTION):
		return
	orbit = String(cf.get_value(SECTION, "orbit", orbit))
	pan = String(cf.get_value(SECTION, "pan", pan))
	zoom_drag = String(cf.get_value(SECTION, "zoom_drag", zoom_drag))
	zoom_cursor = bool(cf.get_value(SECTION, "zoom_cursor", zoom_cursor))
	pivot = String(cf.get_value(SECTION, "pivot", pivot))
	if not pivot in PIVOTS:
		pivot = "target"
	trackpad = bool(cf.get_value(SECTION, "trackpad", trackpad))
	preset = preset_name()


func save_to(path: String) -> void:
	var cf := ConfigFile.new()
	cf.load(path)   # keeps the other sections
	cf.set_value(SECTION, "preset", preset_name())
	cf.set_value(SECTION, "orbit", orbit)
	cf.set_value(SECTION, "pan", pan)
	cf.set_value(SECTION, "zoom_drag", zoom_drag)
	cf.set_value(SECTION, "zoom_cursor", zoom_cursor)
	cf.set_value(SECTION, "pivot", pivot)
	cf.set_value(SECTION, "trackpad", trackpad)
	cf.save(path)
