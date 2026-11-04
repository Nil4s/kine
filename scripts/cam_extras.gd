## CAMERA EXTRAS (C01, complaints #713, #184, #689). Three opt-in things, all off until used:
##  1. VIEW HISTORY: the last 20 settled views; Alt+Left = back, Alt+Right = forward (SketchUp's Previous / Next), and two small buttons
##     left of the ViewCube. A view counts once the camera has held still for SETTLE seconds; stepping through history is not recorded.
##  2. INVERT ORBIT / INVERT PAN: flips the drag direction of that gesture. Saved in the settings file ([camx]), never in a scene.
##  3. THE CUBE'S TOP: right-click a cube face, "Make this face Top"; the cube's labels turn so that face reads TOP and the neighbours
##     follow. Saved WITH THE SCENE (key "cube_top"); a scene without the key shows the cube as always.
class_name CamExtras
extends RefCounted

const SECTION := "camx"
const KEY := "cube_top"
const MAX := 20
const SETTLE := 0.35
const POS_EPS := 0.02
const ANG_EPS := 0.5

var m: Node
var invert_orbit := false
var invert_pan := false
var invert_orbit_x := false   # C41 (#184): flip only the left-right (yaw) part of an orbit; XORs with invert_orbit
var invert_orbit_y := false   # C41: flip only the up-down (pitch) part
var cube_top := Vector3.ZERO   # ZERO = the world's up is Top (the default)
var hist: Array = []
var at := -1
var _still := 0.0
var _last := {}
var bar: VBoxContainer
var b_back: Button
var b_fwd: Button
var menu: PopupMenu
var _menu_face := -1


func _init(main: Node = null) -> void:
	m = main
	if m != null:
		load_from(m.settings)


# ---- the view and its history ------------------------------------------------------------------------------------------

func view_now() -> Dictionary:
	return {"yaw": float(m.yaw), "pitch": float(m.pitch), "dist": float(m.dist), "target": m.target}


static func same(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	return absf(wrapf(float(a["yaw"]) - float(b["yaw"]), -180.0, 180.0)) < ANG_EPS and absf(float(a["pitch"]) - float(b["pitch"])) < ANG_EPS \
		and absf(float(a["dist"]) - float(b["dist"])) < POS_EPS * maxf(float(b["dist"]), 1.0) and (a["target"] - b["target"]).length() < POS_EPS


## put the view in the history now (after the forward part is dropped); false when it equals the current entry
func note(v: Dictionary = {}) -> bool:
	if v.is_empty():
		v = view_now()
	if at >= 0 and same(hist[at], v):
		return false
	hist = hist.slice(0, at + 1)
	hist.append(v)
	if hist.size() > MAX:
		hist = hist.slice(hist.size() - MAX)
	at = hist.size() - 1
	_sync_buttons()
	return true


## called about ten times a second: a view that has held still for SETTLE seconds is noted
func tick(dt: float) -> void:
	if m == null or (m._view_tw != null and m._view_tw.is_valid() and m._view_tw.is_running()):
		return
	var v := view_now()
	if not _last.is_empty() and same(v, _last):
		_still += dt
		if _still >= SETTLE:
			note(v)
	else:
		_still = 0.0
	_last = v
	_sync_buttons()


func _off_entry() -> bool:
	return at >= 0 and not same(hist[at], view_now())


func can_back() -> bool:
	return at > 0 or (at == 0 and _off_entry())


func can_forward() -> bool:
	return at >= 0 and at < hist.size() - 1


func back() -> bool:
	if _off_entry():
		note()   # the view you are on but never held still: it is what Forward returns to
	if at <= 0:
		return false
	return _go(at - 1)


func forward() -> bool:
	if not can_forward():
		return false
	return _go(at + 1)


func _go(i: int) -> bool:
	at = i
	var v: Dictionary = hist[at]
	_last = v
	_still = 0.0
	m._turn_to(float(v["yaw"]), float(v["pitch"]), float(v["dist"]), v["target"], true)
	_sync_buttons()
	return true


## Alt+Left / Alt+Right; true = handled
func key(ev: InputEvent) -> bool:
	if not (ev is InputEventKey) or not ev.pressed or ev.echo:
		return false
	var k := ev as InputEventKey
	if not k.alt_pressed or k.ctrl_pressed or k.shift_pressed or (k.keycode != KEY_LEFT and k.keycode != KEY_RIGHT):
		return false
	var f: Control = m.get_viewport().gui_get_focus_owner()
	if f is LineEdit or f is SpinBox or f is TextEdit:
		return false
	if k.keycode == KEY_LEFT:
		back()
	else:
		forward()
	return true


# ---- invert -------------------------------------------------------------------------------------------------------------

## main calls this on a drag step: the drag with its direction flipped when that gesture is inverted
func inv(act: String, rel: Vector2) -> Vector2:
	if (act == "orbit" and invert_orbit) or (act == "pan" and invert_pan):
		rel = -rel
	if act == "orbit" and (invert_orbit_x or invert_orbit_y):   # C41
		rel = Vector2(-rel.x if invert_orbit_x else rel.x, -rel.y if invert_orbit_y else rel.y)
	return rel


func set_invert(orbit_on: bool, pan_on: bool) -> void:
	invert_orbit = orbit_on
	invert_pan = pan_on
	save_to(m.settings)


func load_from(path: String) -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK or not cf.has_section(SECTION):
		return
	invert_orbit = bool(cf.get_value(SECTION, "invert_orbit", false))
	invert_pan = bool(cf.get_value(SECTION, "invert_pan", false))
	invert_orbit_x = bool(cf.get_value(SECTION, "invert_orbit_x", false))
	invert_orbit_y = bool(cf.get_value(SECTION, "invert_orbit_y", false))


func save_to(path: String) -> void:
	var cf := ConfigFile.new()
	cf.load(path)
	cf.set_value(SECTION, "invert_orbit", invert_orbit)
	cf.set_value(SECTION, "invert_pan", invert_pan)
	cf.set_value(SECTION, "invert_orbit_x", invert_orbit_x)
	cf.set_value(SECTION, "invert_orbit_y", invert_orbit_y)
	cf.save(path)


# ---- the cube's Top, saved with the scene ---------------------------------------------------------------------------------

## the rotation that carries the chosen face to +Y (identity = the default)
static func remap_of(c: Vector3) -> Basis:
	if c.length() < 0.5:
		return Basis.IDENTITY
	c = c.normalized()
	if c.is_equal_approx(Vector3.UP):
		return Basis.IDENTITY
	if c.is_equal_approx(Vector3.DOWN):
		return Basis(Vector3.RIGHT, PI)
	return Basis(Quaternion(c, Vector3.UP))


func set_top(c: Vector3) -> void:
	cube_top = Vector3.ZERO if (c.length() < 0.5 or c.normalized().is_equal_approx(Vector3.UP)) else c.normalized()
	_apply_cube()


func _apply_cube() -> void:
	if m != null and m.ui_cube != null:
		m.ui_cube.set_remap(remap_of(cube_top))


## _scene_dict: only a changed Top is written
func put_key(d: Dictionary) -> void:
	if cube_top != Vector3.ZERO:
		d[KEY] = [snappedf(cube_top.x, 0.001), snappedf(cube_top.y, 0.001), snappedf(cube_top.z, 0.001)]


## a scene opened: its Top back, or the default when the file has none
func from_scene(d: Dictionary) -> void:
	var a = d.get(KEY, null)
	cube_top = Vector3(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() == 3 else Vector3.ZERO
	_apply_cube()


## right-click on cube face i (screen position pos): "Make this face Top" / "Reset Top"
func cube_menu(i: int, pos: Vector2) -> void:
	_menu_face = i
	if menu == null or not is_instance_valid(menu):
		menu = PopupMenu.new()
		menu.id_pressed.connect(_menu_pick)
		m.add_child(menu)
	menu.clear()
	menu.add_item("Make this face Top", 1)
	menu.add_item("Reset Top", 2)
	menu.set_item_disabled(1, cube_top == Vector3.ZERO)
	menu.popup(Rect2i(Vector2i(pos), Vector2i(0, 0)))


func _menu_pick(id: int) -> void:
	if id == 1 and _menu_face >= 0:
		# the face shown at cube position _menu_face is, in the world, the one whose normal the current remap carries there
		set_top(remap_of(cube_top).inverse() * ViewCube.FACES[_menu_face][0])
	elif id == 2:
		set_top(Vector3.ZERO)


# ---- the two buttons ------------------------------------------------------------------------------------------------------

func build(parent: Control) -> void:
	bar = VBoxContainer.new()
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.add_theme_constant_override("separation", 2)
	b_back = _btn("< View", "Previous view (Alt+Left): the last 20 views", func(): back())
	b_fwd = _btn("View >", "Next view (Alt+Right)", func(): forward())
	bar.add_child(b_back)
	bar.add_child(b_fwd)
	parent.add_child(bar)
	var t := Timer.new()
	t.wait_time = 0.1
	t.autostart = true
	t.timeout.connect(func(): tick(0.1))
	m.add_child(t)
	_sync_buttons()
	_apply_cube()
	place()


func _btn(txt: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(64, 24)
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	return b


## left of the ViewCube, level with its top
func place() -> void:
	if bar == null or m.ui_cube == null:
		return
	bar.offset_right = m.ui_cube.offset_left - 6.0
	bar.offset_left = bar.offset_right - 64.0
	bar.offset_top = m.ui_cube.offset_top
	bar.offset_bottom = bar.offset_top + 50.0


func _sync_buttons() -> void:
	if bar != null:
		bar.visible = not (m.bld != null and m.bld.on)   # the BUILD pages put their own buttons where the bar would sit (peasy3 clicks there): keys still work
	if b_back != null:
		m._grey(b_back, "" if can_back() else "there is no earlier view yet: move the camera first")   # B07: greyed says why
		m._grey(b_fwd, "" if can_forward() else "there is no later view: go back first")
