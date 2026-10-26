extends RefCounted
## KCad: the one door to exact solids (BUILD mode kernel: Open CASCADE through the KineCAD GDExtension in native/cad).
## A shape is an int id (0 = failed, read KCad.last_error()). Everything works with no DLL too, just as failures: available() is false,
## every builder returns 0, tessellate() returns null, last_error() says what is missing. Kine starts and its tests pass without it.
## Build + licence notes: native/CAD_BUILD.md. Units are the caller's (Kine: metres).

const MISSING := "KineCAD is not installed: build native/cad and copy the OCCT DLLs (see native/CAD_BUILD.md)"
const NATIVE := "res://scripts/kcad_native.gd"

static var _impl = null   # the kcad_native.gd script, or null
static var _tried := false
static var _err := ""


static func available() -> bool:
	return _n() != null


static func _n():
	if not _tried:
		_tried = true
		if ClassDB.class_exists("KineCAD"):
			_impl = load(NATIVE)
			if _impl == null:
				_err = "KineCAD loaded but " + NATIVE + " would not compile"
		else:
			_err = MISSING
	return _impl


static func last_error() -> String:
	var n = _n()
	if n != null:
		var e: String = n.last_error()
		return e if e != "" else _err
	return _err


static func version() -> String:
	var n = _n()
	return "KineCAD %d / OCCT %s" % [n.version(), n.occt_version()] if n != null else "none"


static func box(dx: float, dy: float, dz: float) -> int:
	var n = _n()
	return n.box(dx, dy, dz) if n != null else 0


static func cylinder(r: float, h: float) -> int:
	var n = _n()
	return n.cylinder(r, h) if n != null else 0


static func sphere(r: float) -> int:
	var n = _n()
	return n.sphere(r) if n != null else 0


static func translate(id: int, by: Vector3) -> int:
	var n = _n()
	return n.translate(id, by) if n != null else 0


static func rotate(id: int, axis: Vector3, radians: float) -> int:
	var n = _n()
	return n.rotate(id, axis, radians) if n != null else 0


static func union(a: int, b: int) -> int:
	var n = _n()
	return n.union(a, b) if n != null else 0


static func cut(a: int, b: int) -> int:
	var n = _n()
	return n.cut(a, b) if n != null else 0


static func intersect(a: int, b: int) -> int:
	var n = _n()
	return n.intersect(a, b) if n != null else 0


static func fillet_all(id: int, radius: float) -> int:
	var n = _n()
	return n.fillet_all(id, radius) if n != null else 0


## hollow with walls `thickness` thick (inwards); a non-zero open_dir also opens the planar face that points that way
static func shell(id: int, thickness: float, open_dir := Vector3.ZERO) -> int:
	var n = _n()
	return n.shell(id, thickness, open_dir) if n != null else 0


static func volume(id: int) -> float:
	var n = _n()
	return n.volume(id) if n != null else -1.0


static func area(id: int) -> float:
	var n = _n()
	return n.area(id) if n != null else -1.0


static func face_count(id: int) -> int:
	var n = _n()
	return n.face_count(id) if n != null else -1


static func edge_count(id: int) -> int:
	var n = _n()
	return n.edge_count(id) if n != null else -1


## one ArrayMesh surface with normals; deflection = max distance from the true surface, angle = max angle between facets (radians).
## Not welded across B-rep faces. null on failure.
static func tessellate(id: int, deflection := 0.01, angle := 0.3) -> ArrayMesh:
	var n = _n()
	return n.tessellate(id, deflection, angle) if n != null else null


## path may be res:// or user://
static func export_step(id: int, path: String) -> bool:
	var n = _n()
	return n.export_step(id, ProjectSettings.globalize_path(path)) if n != null else false


static func import_step(path: String) -> int:
	var n = _n()
	return n.import_step(ProjectSettings.globalize_path(path)) if n != null else 0


static func release(id: int) -> void:
	var n = _n()
	if n != null:
		n.release(id)


static func release_all() -> void:
	var n = _n()
	if n != null:
		n.release_all()


static func live_count() -> int:
	var n = _n()
	return n.live_count() if n != null else 0
