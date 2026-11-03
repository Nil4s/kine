## PIVOTS AND CAMERAS (C07, complaints #709 iClone camera orbit, #686 Onshape orbit centre, #465 DAZ rotate-about-joint). Three opt-in things, all off
## until switched on in "Camera navigation" (saved in the settings file, [campiv]; never in a scene, never an undo step):
##  1. OWN-AXIS CAMERA: looking through the shot camera, an orbit drag turns the camera about ITS OWN position (a look-around), where the old
##     behaviour leaves the camera view and swings the free view round the camera's aim point. Camera position stays put to the millimetre.
##  2. SHOW THE PIVOT: a small orange ball at the point the orbit turns around (the view centre, the point under the cursor, or the
##     selection, whichever "Orbit around" says; the camera itself for 1.). Shown while orbiting and for FADE seconds after.
##  3. JOINT DOT: a cyan ball on the selected part's joint (the point a drag of it turns about), drawn over the body.
## The balls are plain unshaded meshes with no collider: nothing picks them, they cover no control (they live in the 3D view only).
class_name CamPivot
extends RefCounted

const SECTION := "campiv"
const FADE := 0.8
const SCREEN_K := 0.014      # ball radius as a fraction of the view distance (a constant size on screen)

var m: Node
var own_cam := false
var show_pivot := false
var joint_dot := false
var pv_node: MeshInstance3D
var jd_node: MeshInstance3D
var _fade := 0.0
var _last_pv := Vector3.ZERO


func _init(main: Node = null) -> void:
	m = main
	if m != null:
		load_from(m.settings)


func any_on() -> bool:
	return own_cam or show_pivot or joint_dot


# ---- 1. the camera's own axis -----------------------------------------------------------------------------------------

## main calls this just before the shot camera's view is handed over to the free view by an orbit drag
func own_begin() -> void:
	if not own_cam or m.camnav == null:
		return
	m.camnav._pv = m.cam.global_position
	m.camnav._pv_on = true


# ---- 2/3. the balls --------------------------------------------------------------------------------------------------------

func _ball(col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 1.0
	sp.height = 2.0
	sp.radial_segments = 16
	sp.rings = 8
	mi.mesh = sp
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.no_depth_test = true
	mat.render_priority = 100
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	m.add_child(mi)
	return mi


## the point the orbit turns about right now, for the pivot option in force
func pivot_point() -> Vector3:
	var cn: CamNav = m.camnav
	if cn._pv_on and m.dragging == "orbit":
		return cn._pv
	if cn.pivot == "selection" and m.vx != null:
		return (m.vx.sel_aabb() as AABB).get_center()
	if cn.pivot == "cursor" and m.is_inside_tree():
		return cn.point_under(m.get_viewport().get_mouse_position())
	return m.target


func tick(dt: float) -> void:
	if m == null or m.cam == null:
		return
	if show_pivot:
		if m.dragging == "orbit":
			_fade = FADE
		elif _fade > 0.0:
			_fade -= dt
		if pv_node == null:
			pv_node = _ball(Color(1.0, 0.55, 0.05))
		pv_node.visible = _fade > 0.0
		if pv_node.visible:
			if m.dragging == "orbit":
				_last_pv = pivot_point()
			pv_node.global_position = _last_pv
			pv_node.scale = Vector3.ONE * (m.cam.global_position.distance_to(_last_pv) * SCREEN_K)
	elif pv_node != null:
		pv_node.visible = false
	if joint_dot and m.B != null and m.B.P.has(m.sel):
		if jd_node == null:
			jd_node = _ball(Color(0.1, 0.85, 1.0))
		var p: Vector3 = m.B.P[m.sel]
		jd_node.global_position = p
		jd_node.scale = Vector3.ONE * (m.cam.global_position.distance_to(p) * SCREEN_K * 0.7)
		jd_node.visible = true
	elif jd_node != null:
		jd_node.visible = false


# ---- the settings file -------------------------------------------------------------------------------------------------------

func load_from(path: String) -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK or not cf.has_section(SECTION):
		return
	own_cam = bool(cf.get_value(SECTION, "own_cam", false))
	show_pivot = bool(cf.get_value(SECTION, "show_pivot", false))
	joint_dot = bool(cf.get_value(SECTION, "joint_dot", false))


func save_to(path: String) -> void:
	var cf := ConfigFile.new()
	cf.load(path)
	cf.set_value(SECTION, "own_cam", own_cam)
	cf.set_value(SECTION, "show_pivot", show_pivot)
	cf.set_value(SECTION, "joint_dot", joint_dot)
	cf.save(path)
