class_name KMeshMaskTint
extends MeshInstance3D
## ROADMAP_400 C03: the sculpt mask drawn as a dark see-through layer on the mesh (KMeshMask.tint_arrays). Added as a child
## of the KMeshView that draws the mesh (same local space). It rebuilds itself when the verts or the mask values change
## (two packed-array compares a frame against copies of the last ones), so strokes, mask ops and undo need no extra call.

var mesh_ref: KMesh
var _last_v := PackedVector3Array()
var _last_m := PackedFloat32Array()
var _mat: StandardMaterial3D


func _init(m: KMesh = null) -> void:
	name = "mask_tint"
	mesh_ref = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.vertex_color_use_as_albedo = true
	_mat.albedo_color = Color.WHITE
	_mat.cull_mode = BaseMaterial3D.CULL_BACK
	material_override = _mat


func _process(_dt: float) -> void:
	refresh()


## rebuild if the mesh or its mask changed; true when it rebuilt
func refresh(force := false) -> bool:
	if mesh_ref == null:
		mesh = null
		return false
	var mv := KMeshMask.values(mesh_ref)
	if not force and mv == _last_m and mesh_ref.verts == _last_v:
		return false
	_last_m = mv.duplicate()   # copies: a packed array read from the mesh is the live one, written in place by the brushes
	_last_v = mesh_ref.verts.duplicate()
	var a := KMeshMask.tint_arrays(mesh_ref)
	var pos: PackedVector3Array = a[0]
	if pos.is_empty():
		mesh = null
		return true
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_COLOR] = a[1]
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh = am
	return true
