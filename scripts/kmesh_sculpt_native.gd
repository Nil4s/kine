extends RefCounted
## The only script that names KineSculptNative (native/, a GDExtension DLL). KMeshSculpt load()s THIS file by path, and
## only when ClassDB.class_exists("KineSculptNative"): with no DLL this file is never compiled, so the app runs on the
## GDScript path alone. No class_name on purpose (a global class would be compiled at project scan).
## Arithmetic mirrors KMeshSculpt (native/src/kine_sculpt_native.cpp); tests/sculptnative_test.gd holds the two to 1e-5.

const BRUSH_ID := {"draw": 0, "clay strips": 1, "inflate": 2, "smooth": 3, "flatten": 4, "pinch": 5, "crease": 6, "grab": 7, "snake hook": 8}
const FALLOFF_ID := {"smooth": 0, "sphere": 1, "sharp": 2, "linear": 3}


static func version() -> int:
	return KineSculptNative.version()


static func make_ctx(verts: PackedVector3Array, faces: Array, cell: float) -> Dictionary:
	return KineSculptNative.make_ctx(verts, faces, cell)


static func verts_in(ctx: Dictionary, verts: PackedVector3Array, c: Vector3, r: float) -> PackedInt32Array:
	return KineSculptNative.verts_in(ctx, verts, c, r)


## brush draw..snake; null when the brush is not one the native core does (grab, mask, face set)
static func displacements(ctx: Dictionary, verts: PackedVector3Array, vnorm: PackedVector3Array, ids: PackedInt32Array, brush: String,
		falloff: String, hit: Vector3, n: Vector3, r: float, a: float, strength: float, sgn: float, has_last: bool, last: Vector3):
	if not BRUSH_ID.has(brush) or brush == "grab":
		return null
	return KineSculptNative.displacements(ctx, verts, vnorm, ids, BRUSH_ID[brush], FALLOFF_ID.get(falloff, 0), hit, n, r, a, strength, sgn, has_last, last)


## adds d, refreshes the normals in `mesh`; returns the verts moved
static func apply(ctx: Dictionary, mesh: KMesh, ids: PackedInt32Array, d: PackedVector3Array, sym: PackedInt32Array, sax: int,
		mask: PackedFloat32Array, lock: PackedByteArray) -> int:
	var vs := mesh.verts
	var fn := mesh._face_normals
	var vn := mesh._vert_normals
	mesh.verts = PackedVector3Array()   # drop the owners: the native call copies once, not twice
	mesh._face_normals = PackedVector3Array()
	mesh._vert_normals = PackedVector3Array()
	var res: Array = KineSculptNative.apply(ctx, vs, fn, vn, ids, d, sym, sax, mask, lock)
	mesh.verts = res[0]
	mesh._face_normals = res[1]
	mesh._vert_normals = res[2]
	return res[3]


static func renormal(ctx: Dictionary, mesh: KMesh, moved: PackedInt32Array) -> void:
	var fn := mesh._face_normals
	var vn := mesh._vert_normals
	mesh._face_normals = PackedVector3Array()
	mesh._vert_normals = PackedVector3Array()
	var res: Array = KineSculptNative.renormal(ctx, mesh.verts, fn, vn, moved)
	mesh._face_normals = res[0]
	mesh._vert_normals = res[1]
