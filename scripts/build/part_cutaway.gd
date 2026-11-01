extends RefCounted
## S016 CUT-AWAY WHILE THE WALL MOVES (Friday plan 16): while Hollow inside's Wall slider is held (and 1.5 s after), the shown part is cut in
## half through its middle, the half nearest the eye removed, so the cut face (the back faces of the wall, drawn in a contrasting colour)
## reads as a band of the wall's thickness. The record is never touched: this is a view only (a surface material), so it is no undo step.
## The cut plane is vertical and faces the camera (its normal is the camera's horizontal direction), or the up axis from straight above.
## It is re-applied after every mesh the slider preview lands (PartUI._look_surfaces calls cut_hook), and taken off 1.5 s after the release.

const HOLD_AFTER := 1.5   # seconds the cut stays after the release
const SHADER := """shader_type spatial;
render_mode cull_disabled, unshaded;
uniform vec4 cut = vec4(0.0, 0.0, 1.0, 0.0);
uniform vec4 cap : source_color = vec4(1.0, 0.45, 0.62, 1.0);
uniform vec4 solid : source_color = vec4(0.85, 0.86, 0.89, 1.0);
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	if (dot(cut.xyz, wp) > cut.w) {
		discard;
	}
	if (FRONT_FACING) {
		ALBEDO = solid.rgb * (0.7 + 0.3 * abs(NORMAL.z));
	} else {
		ALBEDO = cap.rgb;
	}
}
"""

var pu: Node
var on := false
var token := 0
var mat: ShaderMaterial = null
var presses := 0   # probe


func _init(part_ui: Node) -> void:
	pu = part_ui


## the Wall slider is pressed: the cut goes on, its plane fixed from the camera now
func hold() -> void:
	token += 1
	presses += 1
	if pu == null or pu.part_mesh == null or pu.m == null or pu.m.cam == null:
		return
	if mat == null:
		mat = ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = SHADER
		mat.shader = sh
		mat.set_shader_parameter("cap", Tok.c("sg_phase"))
		mat.set_shader_parameter("solid", Tok.c("body_clay"))
	var mi: MeshInstance3D = pu.part_mesh
	var ctr: Vector3 = mi.global_transform * mi.get_aabb().get_center()
	var to_eye: Vector3 = pu.m.cam.global_position - ctr
	var n := Vector3(to_eye.x, 0.0, to_eye.z)
	if n.length() < 0.2 * to_eye.length():
		n = Vector3.UP if to_eye.y >= 0.0 else Vector3.DOWN
	n = n.normalized()
	mat.set_shader_parameter("cut", Vector4(n.x, n.y, n.z, n.dot(ctr)))
	on = true
	pu.cut_hook = apply
	apply()


## the Wall slider is let go: the whole part comes back after HOLD_AFTER seconds, unless it is pressed again
func release() -> void:
	token += 1
	var my := token
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		off()
		return
	await tree.create_timer(HOLD_AFTER).timeout
	if my == token:
		off()


func off() -> void:
	if not on:
		return
	on = false
	pu.cut_hook = Callable()
	if pu.part_mesh != null:
		pu._look_surfaces()   # each body's own look comes back (a surface override outranks material_override)
		pu._sec_apply()


## the cut material on every surface of the shown mesh
func apply() -> void:
	if not on or mat == null or pu.part_mesh == null or pu.part_mesh.mesh == null:
		return
	for sf in pu.part_mesh.mesh.get_surface_count():
		pu.part_mesh.set_surface_override_material(sf, mat)
