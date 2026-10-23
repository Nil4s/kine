class_name KMeshFaceSetTint
extends MeshInstance3D
## ROADMAP_400 C09: the face sets drawn as a see-through colour layer, one stable colour per set (KMeshFaceSets.tint_arrays;
## the default set 1 and hidden faces are not drawn). A child of the KMeshView that draws the mesh (same local space), like
## C03's KMeshMaskTint. It rebuilds itself when the verts, the faces or the face-set values change (compares against
## copies of the last ones every frame), so strokes, face-set ops and undo need no extra call. When the face-set values
## change it also rebuilds its sibling mask tint (hiding a set must take that set's mask shade away too).

var mesh_ref: KMesh
var _last_v := PackedVector3Array()
var _last_s := PackedFloat32Array()
var _last_nf := -1
var _mat: StandardMaterial3D


func _init(m: KMesh = null) -> void:
	name = "face_set_tint"
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


## rebuild if the mesh or its face sets changed; true when it rebuilt
func refresh(force := false) -> bool:
	if mesh_ref == null:
		mesh = null
		return false
	var sv := KMeshFaceSets.values(mesh_ref)
	var sets_changed := sv != _last_s or mesh_ref.face_count() != _last_nf
	if not force and not sets_changed and mesh_ref.verts == _last_v:
		return false
	_last_s = sv.duplicate()
	_last_v = mesh_ref.verts.duplicate()
	_last_nf = mesh_ref.face_count()
	if sets_changed:
		var mt := get_parent().get_node_or_null("mask_tint") if get_parent() != null else null
		if mt != null and mt.has_method("refresh"):
			mt.refresh(true)
	var a := KMeshFaceSets.tint_arrays(mesh_ref)
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


## the tint on `view` (made the first time); the existing one when it is there
static func on(view: Node3D, m: KMesh) -> KMeshFaceSetTint:
	var t := view.get_node_or_null("face_set_tint") as KMeshFaceSetTint
	if t == null:
		t = KMeshFaceSetTint.new(m)
		view.add_child(t)
	t.mesh_ref = m
	return t
