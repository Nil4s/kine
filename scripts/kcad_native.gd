extends RefCounted
## The only script that names KineCAD (native/cad, a GDExtension DLL + the Open CASCADE DLLs). KCad (scripts/kcad.gd) load()s THIS file
## by path and only when ClassDB.class_exists("KineCAD"): with no DLL this file is never compiled, so the app runs without it.
## No class_name on purpose (a global class would be compiled at project scan). Thin: every call is forwarded.


static func version() -> int:
	return KineCAD.version()


static func occt_version() -> String:
	return KineCAD.occt_version()


static func last_error() -> String:
	return KineCAD.last_error()


static func box(dx: float, dy: float, dz: float) -> int:
	return KineCAD.box(dx, dy, dz)


static func cylinder(r: float, h: float) -> int:
	return KineCAD.cylinder(r, h)


static func sphere(r: float) -> int:
	return KineCAD.sphere(r)


static func translate(id: int, by: Vector3) -> int:
	return KineCAD.translate(id, by)


static func rotate(id: int, axis: Vector3, radians: float) -> int:
	return KineCAD.rotate(id, axis, radians)


static func union(a: int, b: int) -> int:
	return KineCAD.union(a, b)


static func cut(a: int, b: int) -> int:
	return KineCAD.cut(a, b)


static func intersect(a: int, b: int) -> int:
	return KineCAD.intersect(a, b)


static func fillet_all(id: int, radius: float) -> int:
	return KineCAD.fillet_all(id, radius)


static func shell(id: int, thickness: float, open_dir: Vector3) -> int:
	return KineCAD.shell(id, thickness, open_dir)


static func volume(id: int) -> float:
	return KineCAD.volume(id)


static func area(id: int) -> float:
	return KineCAD.area(id)


static func face_count(id: int) -> int:
	return KineCAD.face_count(id)


static func edge_count(id: int) -> int:
	return KineCAD.edge_count(id)


static func tessellate(id: int, deflection: float, angle: float) -> ArrayMesh:
	return KineCAD.tessellate(id, deflection, angle)


static func export_step(id: int, path: String) -> bool:
	return KineCAD.export_step(id, path)


static func import_step(path: String) -> int:
	return KineCAD.import_step(path)


static func release(id: int) -> void:
	KineCAD.release(id)


static func release_all() -> void:
	KineCAD.release_all()


static func live_count() -> int:
	return KineCAD.live_count()


static func sketch_wire(items: Array, origin: Vector3, x_dir: Vector3, normal: Vector3) -> int:
	return KineCAD.sketch_wire(items, origin, x_dir, normal)


static func sketch_face(items: Array, origin: Vector3, x_dir: Vector3, normal: Vector3) -> int:
	return KineCAD.sketch_face(items, origin, x_dir, normal)


static func path_wire(points: PackedVector3Array) -> int:
	return KineCAD.path_wire(points)


static func face_from_wire(wire: int) -> int:
	return KineCAD.face_from_wire(wire)


static func extrude(face: int, dist: float, both: bool, taper: float) -> int:
	return KineCAD.extrude(face, dist, both, taper)


static func revolve(profile: int, axis_origin: Vector3, axis_dir: Vector3, radians: float) -> int:
	return KineCAD.revolve(profile, axis_origin, axis_dir, radians)


static func sweep(profile: int, path: int) -> int:
	return KineCAD.sweep(profile, path)


static func loft(profiles: PackedInt32Array, ruled: bool, solid: bool) -> int:
	return KineCAD.loft(profiles, ruled, solid)


static func edges(id: int) -> Array:
	return KineCAD.edges(id)


static func faces(id: int) -> Array:
	return KineCAD.faces(id)


static func fillet_edges(id: int, edge_ids: PackedInt32Array, radius: float) -> int:
	return KineCAD.fillet_edges(id, edge_ids, radius)


static func chamfer_edges(id: int, edge_ids: PackedInt32Array, dist: float) -> int:
	return KineCAD.chamfer_edges(id, edge_ids, dist)


static func mirror(id: int, origin: Vector3, normal: Vector3) -> int:
	return KineCAD.mirror(id, origin, normal)


static func pattern_linear(id: int, step: Vector3, count: int) -> int:
	return KineCAD.pattern_linear(id, step, count)


static func pattern_circular(id: int, axis_origin: Vector3, axis_dir: Vector3, count: int, total_radians: float) -> int:
	return KineCAD.pattern_circular(id, axis_origin, axis_dir, count, total_radians)


static func mass_properties(id: int) -> Dictionary:
	return KineCAD.mass_properties(id)
