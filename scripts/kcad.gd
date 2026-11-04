extends RefCounted
## KCad: the one door to exact solids (BUILD mode kernel: Open CASCADE through the KineCAD GDExtension in native/cad).
## A shape is an int id (0 = failed, read KCad.last_error()). Everything works with no DLL too, just as failures: available() is false,
## every builder returns 0, tessellate() returns null, last_error() says what is missing. Kine starts and its tests pass without it.
## Build + licence notes: native/CAD_BUILD.md. Units are the caller's (Kine: metres).

const MISSING := "KineCAD is not installed: build native/cad and copy the OCCT DLLs (see native/CAD_BUILD.md)"
const NATIVE := "res://scripts/kcad_native.gd"
const NATIVE_NEW := "res://scripts/kcad_native_new.gd"   # calls an older DLL may lack (see its header)

static var _impl = null   # the kcad_native.gd script, or null
static var _tried := false
static var _err := ""


static func available() -> bool:
	return _n() != null


static func _n():
	if not _tried:
		_tried = true
		if NativeExt.ensure("kine_cad", "KineCAD"):
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


## C70: base fused with every id in tools in ONE boolean (the copies of a pattern); 0 when the kernel is old (no union_many) or refuses: the caller joins them in pairs
static func union_many(base: int, tools: PackedInt32Array) -> int:
	var n = _n()
	return load(NATIVE_NEW).union_many(base, tools) if n != null and has_union_many() else 0


static func overlap_volume(a: int, b: int) -> float:   # C70: -1 when the kernel lacks it
	var n = _n()
	return load(NATIVE_NEW).overlap_volume(a, b) if n != null and ClassDB.class_exists("KineCAD") and ClassDB.class_has_method("KineCAD", "overlap_volume") else -1.0


static func has_union_many() -> bool:
	return ClassDB.class_exists("KineCAD") and ClassDB.class_has_method("KineCAD", "union_many")


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
	if n == null:
		return -1.0
	if _vol_cache.has(id):   # s233: a shape never changes, so its volume is asked of the kernel once while the shape lives
		return _vol_cache[id]
	var v: float = n.volume(id)
	_vol_cache[id] = v
	return v


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


## ---- phase 2: sketch -> solid (Fusion-style PART tools). A sketch plane is (origin, x_dir, normal); (u, v) = origin + u*x + v*(normal x x).
## Sketch items: KCad.line(a, b), KCad.arc(a, mid, b), KCad.circle(c, r), KCad.bspline(pts, closed); give them in any order, forming ONE loop.
## Edge / face ids are positions in that shape's own list (see edges() / faces()): stable for one shape id, not across derived shapes.

static func line(a: Vector2, b: Vector2) -> Dictionary:
	return {"t": "line", "a": a, "b": b}


## three-point arc: from a to b through m
static func arc(a: Vector2, m: Vector2, b: Vector2) -> Dictionary:
	return {"t": "arc", "a": a, "m": m, "b": b}


static func circle(c: Vector2, r: float) -> Dictionary:
	return {"t": "circle", "c": c, "r": r}


## interpolating B-spline through pts; closed = a periodic curve (do not repeat the first point)
static func bspline(pts: PackedVector2Array, closed := false) -> Dictionary:
	return {"t": "bspline", "pts": pts, "closed": closed}


## closed polygon as line items
static func polygon(pts: PackedVector2Array) -> Array:
	var out := []
	for i in pts.size():
		out.append(line(pts[i], pts[(i + 1) % pts.size()]))
	return out


static func sketch_wire(items: Array, origin := Vector3.ZERO, x_dir := Vector3.RIGHT, normal := Vector3.BACK) -> int:
	var n = _n()
	return n.sketch_wire(items, origin, x_dir, normal) if n != null else 0


## planar face (its normal is the sketch normal whatever the winding)
static func sketch_face(items: Array, origin := Vector3.ZERO, x_dir := Vector3.RIGHT, normal := Vector3.BACK) -> int:
	var n = _n()
	return n.sketch_face(items, origin, x_dir, normal) if n != null else 0


static func path_wire(points: PackedVector3Array) -> int:
	var n = _n()
	return n.path_wire(points) if n != null else 0


static func face_from_wire(wire: int) -> int:
	var n = _n()
	return n.face_from_wire(wire) if n != null else 0


## along the face normal. both: symmetric about the sketch plane, `dist` is the TOTAL. taper (radians): > 0 narrows with height.
static func extrude(face: int, dist: float, both := false, taper := 0.0) -> int:
	var n = _n()
	return n.extrude(face, dist, both, taper) if n != null else 0


## radians >= TAU (or <= -TAU) is a full turn
static func revolve(profile: int, axis_origin: Vector3, axis_dir: Vector3, radians := TAU) -> int:
	var n = _n()
	return n.revolve(profile, axis_origin, axis_dir, radians) if n != null else 0


## profile face -> solid, profile wire -> shell; path = wire (sketch_wire / path_wire)
static func sweep(profile: int, path: int) -> int:
	var n = _n()
	return n.sweep(profile, path) if n != null else 0


## profiles: wires or faces, in order. ruled = straight between profiles, else smooth.
static func loft(profiles: PackedInt32Array, ruled := false, solid := true) -> int:
	var n = _n()
	return n.loft(profiles, ruled, solid) if n != null else 0


## [{id, center (mid point of the curve), a, b, length, dir (unit tangent at the middle), faces: [face ids]}]
static func edges(id: int) -> Array:
	var n = _n()
	return n.edges(id) if n != null else []


## [{id, center (centre of mass snapped onto the face), normal (outward there), mass_center, area, type}]
static func faces(id: int) -> Array:
	var n = _n()
	return n.faces(id) if n != null else []


static func fillet_edges(id: int, edge_ids: PackedInt32Array, radius: float) -> int:
	var n = _n()
	return n.fillet_edges(id, edge_ids, radius) if n != null else 0


static func chamfer_edges(id: int, edge_ids: PackedInt32Array, dist: float) -> int:
	var n = _n()
	return n.chamfer_edges(id, edge_ids, dist) if n != null else 0


## Offset one face (ids as in faces()) along its outward normal by dist (metres): dist > 0 adds a prism fused on, dist < 0 cuts it out. 0 on failure.
static func offset_face(id: int, face_id: int, dist: float) -> int:
	var n = _n()
	return n.offset_face(id, face_id, dist) if n != null else 0


## Draft faces (ids as in faces()) by angle (radians) about the neutral plane through neutral_origin with normal pull_dir. 0 on failure.
static func draft_faces(id: int, face_ids: PackedInt32Array, angle: float, pull_dir: Vector3, neutral_origin: Vector3) -> int:
	var n = _n()
	return n.draft_faces(id, face_ids, angle, pull_dir, neutral_origin) if n != null else 0


## the reflected copy only (use mirror_join for the part + its mirror)
static func mirror(id: int, origin := Vector3.ZERO, normal := Vector3.RIGHT) -> int:
	var n = _n()
	return n.mirror(id, origin, normal) if n != null else 0


static func mirror_join(id: int, origin := Vector3.ZERO, normal := Vector3.RIGHT) -> int:
	var m := mirror(id, origin, normal)
	if m == 0:
		return 0
	var u := union(id, m)
	release(m)
	return u


## count copies (the original included) spaced by `step`, fused into one shape
static func pattern_linear(id: int, step: Vector3, count: int) -> int:
	var n = _n()
	return n.pattern_linear(id, step, count) if n != null else 0


## count copies round an axis. A full turn (>= TAU) spreads them evenly; a smaller angle is the span from the first to the last copy.
static func pattern_circular(id: int, axis_origin: Vector3, axis_dir: Vector3, count: int, total_radians := TAU) -> int:
	var n = _n()
	return n.pattern_circular(id, axis_origin, axis_dir, count, total_radians) if n != null else 0


## {volume, area, center (of mass), inertia (Basis about the centre, density 1)}; empty on failure
static func mass_properties(id: int) -> Dictionary:
	var n = _n()
	if n == null:
		return {}
	if _mass_cache.has(id):   # s233: the hall's 220 bodies cost about 170 s here (roof shells); a shape never changes, so ask once while it lives
		return (_mass_cache[id] as Dictionary).duplicate()
	var d: Dictionary = n.mass_properties(id)
	_mass_cache[id] = d.duplicate()
	return d


## s233 SHARED SHAPES: the kernel's shapes are never changed in place (every operation answers a NEW id), so two owners can hold one id.
## retain(id) adds an owner; release(id) drops one and frees the shape only when the last owner lets go. The replay cache (Part.inc_cache)
## shares the bodies of a step with the next step instead of deep-copying every body per step (that copy was O(steps x bodies) in time and memory).
static var _owners := {}   # id -> extra owners beyond the first
static var _vol_cache := {}    # id -> volume (m3), dropped when the shape is freed
static var _mass_cache := {}   # id -> mass_properties
static var _epoch := 0         # release_all makes every earlier cache key stale
static var _gens := {}         # id -> how many shapes have been freed under this id (ids may be reused): cache keys of other modules include it


## the number to put in a cache key beside the id: it changes when the id is freed, so a reused id never meets an old entry
static func gen(id: int) -> int:
	return _epoch * 1000000 + int(_gens.get(id, 0))


static func retain(id: int) -> void:
	if id != 0:
		_owners[id] = int(_owners.get(id, 0)) + 1


static func release(id: int) -> void:
	if _owners.has(id):
		var k: int = int(_owners[id]) - 1
		if k <= 0:
			_owners.erase(id)
		else:
			_owners[id] = k
		return
	_vol_cache.erase(id)
	_mass_cache.erase(id)
	_gens[id] = int(_gens.get(id, 0)) + 1
	var n = _n()
	if n != null:
		n.release(id)


static func release_all() -> void:
	_owners.clear()
	_vol_cache.clear()
	_mass_cache.clear()
	_epoch += 1
	var n = _n()
	if n != null:
		n.release_all()


static func live_count() -> int:
	var n = _n()
	return n.live_count() if n != null else 0


## s155: the triangles (verts in metres, tris = 3 indices each) sewn into ONE closed solid; 0 + last_error() when the mesh is open or the
## library is older than this call (has_mesh_solid())
static func solid_from_mesh(verts: PackedVector3Array, tris: PackedInt32Array, tol := 1e-6) -> int:
	var n = _n()
	return load(NATIVE_NEW).solid_from_mesh(verts, tris, tol) if n != null and has_mesh_solid() else 0


static func has_mesh_solid() -> bool:
	return ClassDB.class_exists("KineCAD") and ClassDB.class_has_method("KineCAD", "solid_from_mesh")


## s155b: the library's version as a number (0 = no library); version() above is the sentence
static func version_number() -> int:
	var n = _n()
	return int(n.version()) if n != null else 0


## s155b (KineCAD 5): the kernel's own solid offset exists
static func has_offset() -> bool:
	return ClassDB.class_exists("KineCAD") and ClassDB.class_has_method("KineCAD", "offset") and version_number() >= 5


## s155b: the whole solid grown (distance_m > 0) or shrunk (< 0) on every face by the kernel (BRepOffsetAPI_MakeOffsetShape, sharp corners
## first, rounded when the kernel refuses them); a NEW id, `id` stays valid. 0 + last_error() when refused or the library is older than 5.
static func offset(id: int, distance_m: float) -> int:
	var n = _n()
	return load(NATIVE_NEW).offset(id, distance_m) if n != null and has_offset() else 0
