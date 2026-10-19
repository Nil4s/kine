## shot_gizmo.gd - THE SHOT CAMERA IN THE 3D VIEW (follow-up to scripts/shot_camera.gd). When the view is NOT looking
## through the shot camera, a small camera body sits where the shot camera is at the playhead: a box (the body, behind the
## lens) and the lens frustum (four lines from the lens to the corners of the 16:9 frame 0.5 m in front, along its aim).
## Drawn in the free view only: nothing in a clean render (the playblast, --clean), nothing while looking through, nothing
## when the scene has no camera. It polls its host (main.gd) every frame, so play, scrub, keys and look-through need no
## call from main.gd; main.gd only attaches it once (_world).
class_name ShotGizmo
extends Node3D

const COLOR := Color(0.35, 0.9, 1.0)     # the camera's colour (the timeline's diamonds use it too)
const DIST := 0.5                        # m: the frame's distance in front of the lens
const BODY := Vector3(0.10, 0.07, 0.12) # m: the box, behind the lens (its front face is the lens)

var host                                 # main.gd: reads clean, shot_through, playhead, shot_at()
var _im: ImmediateMesh
var _mat: StandardMaterial3D
var _f := -1.0                           # the focal length the frustum was last drawn for


## put a gizmo under host (main.gd's _world, once)
static func attach(host: Node3D) -> ShotGizmo:
	var g := ShotGizmo.new()
	g.name = "shot_gizmo"
	g.host = host
	host.add_child(g)
	return g


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_im = ImmediateMesh.new()
	var lines := MeshInstance3D.new()
	lines.mesh = _im
	add_child(lines)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = BODY
	box.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = COLOR.darkened(0.3)
	box.material_override = bmat
	box.position = Vector3(0, 0, BODY.z * 0.5)   # the camera looks down -Z: the body is behind the lens (+Z)
	add_child(box)
	visible = false


func _process(_dt: float) -> void:
	sync()


## the gizmo at the shot camera's place at the playhead, or hidden (clean render, looking through, no keys)
func sync() -> void:
	var on: bool = host != null and is_instance_valid(host) and not host.clean and not host.shot_through
	var k: Dictionary = host.shot_at(host.playhead) if on else {}
	on = on and not k.is_empty()
	visible = on
	if not on:
		return
	global_transform = ShotCam.xf(k["pos"], k["aim"])
	var f := float(k["f"])
	if not is_equal_approx(f, _f):
		_f = f
		_draw_frame(f)


func _seg(a: Vector3, b: Vector3) -> void:
	_im.surface_set_color(COLOR)
	_im.surface_add_vertex(a)
	_im.surface_set_color(COLOR)
	_im.surface_add_vertex(b)


## the frustum: lens (origin) to the four corners of the 16:9 frame at DIST, and the frame's own rectangle
func _draw_frame(f: float) -> void:
	var h := DIST * tan(deg_to_rad(ShotCam.fov_v(f)) * 0.5)
	var w := h * ShotCam.ASPECT
	var c := [Vector3(-w, h, -DIST), Vector3(w, h, -DIST), Vector3(w, -h, -DIST), Vector3(-w, -h, -DIST)]
	_im.clear_surfaces()
	_im.surface_begin(Mesh.PRIMITIVE_LINES, _mat)
	for p in c:
		_seg(Vector3.ZERO, p)
	for i in 4:
		_seg(c[i], c[(i + 1) % 4])
	_im.surface_end()
