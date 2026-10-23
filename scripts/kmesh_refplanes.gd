class_name KMeshRefPlanes
extends RefCounted
## REFERENCE IMAGES ON PLANES IN THE MODEL PREVIEW (ROADMAP_400 B21). Pure data + geometry; the nodes, the panel and the
## clicks are scripts/kmesh_refplanes_ui.gd. (The poser's own reference images, over the fighter, are scripts/ref_image.gd.)
## The planes live ON THE MESH (meta META, an Array of entries) and are saved in its .kmesh ("refplanes"): the smaller
## change of the two (the model preview's mesh is not part of the scene file; a .kmesh already carries LODs the same way).
## Only the picture's PATH and its SHA-256 are stored, never the pixels.
## An entry (mesh-local metres, the plane's own axes: right, up, normal toward the camera that looks at it):
##   "path"     the picture file (as picked or dropped)          "hash"   SHA-256 of its bytes when it was placed
##   "axis"     "front" (seen from +Z, looking down -Z), "side" (from +X, looking down -X), "top" (from above, down -Y)
##   "base"     [x, y, z] where it was placed: behind the mesh's box on that axis, bottom on the box's bottom
##   "offset"   [right, up, depth] m from base along the plane's own axes
##   "height"   m: the picture's height (its width follows the picture's aspect, "aspect" = w / h)
##   "opacity"  0..1    "flip" mirror left-right    "lock" no edits    "only_view" drawn only in its matching view
## Planes never take picks: the mesh's pick (KMeshView.ray_face) only ever tests the mesh's own triangles.

const META := "refplanes"
const AXES := ["front", "side", "top"]
const GAP := 0.05           # m behind the mesh's box
const MATCH_DEG := 10.0     # "only in its view": the camera's forward within this of the plane's view direction
const IMG_EXT := ["png", "jpg", "jpeg", "webp", "bmp", "tga"]
const MIN_H := 0.001
const MAX_H := 100.0


static func is_image(path: String) -> bool:
	return path.get_extension().to_lower() in IMG_EXT


static func hash_of(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""


## the plane's turn: its +x right, +y up, +z the normal (toward the camera of its view)
static func basis_of(axis: String) -> Basis:
	match axis:
		"side": return Basis(Vector3.UP, PI * 0.5)        # right -Z, up +Y, normal +X
		"top": return Basis(Vector3.RIGHT, -PI * 0.5)     # right +X, up -Z, normal +Y
	return Basis.IDENTITY


## the direction the camera looks along in the plane's view
static func view_dir(axis: String) -> Vector3:
	return -basis_of(axis).z


## is a camera that looks along `fwd` (world, unit) in this plane's view?
static func matches(axis: String, fwd: Vector3, view_basis := Basis.IDENTITY) -> bool:
	return fwd.normalized().dot((view_basis * view_dir(axis)).normalized()) >= cos(deg_to_rad(MATCH_DEG))


## a new entry for a picture (size px) placed behind a mesh's box (mesh-local AABB)
static func entry(path: String, axis: String, img_size: Vector2, box: AABB) -> Dictionary:
	if not axis in AXES:
		axis = "front"
	var c := box.get_center()
	var h := 1.0
	var base := Vector3.ZERO
	match axis:
		"front":
			h = box.size.y
			base = Vector3(c.x, box.position.y, box.position.z - GAP)
		"side":
			h = box.size.y
			base = Vector3(box.position.x - GAP, box.position.y, c.z)
		"top":
			h = box.size.z
			base = Vector3(c.x, box.position.y - GAP, box.end.z)
	h = clampf(h if h > MIN_H else 1.0, MIN_H, MAX_H)
	var e := {"path": path, "hash": hash_of(path), "axis": axis, "base": [base.x, base.y, base.z], "offset": [0.0, 0.0, 0.0],
		"height": h, "aspect": img_size.x / maxf(img_size.y, 1.0), "opacity": 0.5, "flip": false, "lock": false, "only_view": false}
	# base is the bottom edge's middle; the centre sits half a height up the plane
	e["offset"][1] = h * 0.5
	return e


static func centre(e: Dictionary) -> Vector3:
	var b := basis_of(e["axis"])
	var o: Array = e["offset"]
	return Vector3(e["base"][0], e["base"][1], e["base"][2]) + b.x * float(o[0]) + b.y * float(o[1]) + b.z * float(o[2])


static func size_of(e: Dictionary) -> Vector2:
	return Vector2(float(e["height"]) * float(e["aspect"]), float(e["height"]))


## the plane's transform in the mesh's space (the quad is 1 x 1 in its own xy, scaled to the size)
static func xform(e: Dictionary) -> Transform3D:
	var s := size_of(e)
	var b := basis_of(e["axis"]).scaled_local(Vector3(s.x, s.y, 1.0))
	return Transform3D(b, centre(e))


## new height, the bottom edge kept (top planes: the centre kept)
static func set_height(e: Dictionary, h: float) -> void:
	h = clampf(h, MIN_H, MAX_H)
	if e["axis"] != "top":
		e["offset"][1] = float(e["offset"][1]) + (h - float(e["height"])) * 0.5
	e["height"] = h


## a point on the picture (u right, v down, 0..1, before the flip) -> mesh-local
static func uv_to_local(e: Dictionary, uv: Vector2) -> Vector3:
	var u := 1.0 - uv.x if bool(e["flip"]) else uv.x
	return xform(e) * Vector3(u - 0.5, 0.5 - uv.y, 0.0)


## a mesh-local ray -> the picture's (u, v) where it meets the plane (0..1 inside), or null when it misses the plane
static func ray_uv(e: Dictionary, o: Vector3, d: Vector3) -> Variant:
	var x := xform(e)
	var n := x.basis.z.normalized()
	var den := d.dot(n)
	if absf(den) < 1e-9:
		return null
	var t := (x.origin - o).dot(n) / den
	if t <= 0.0:
		return null
	var q := x.affine_inverse() * (o + d * t)
	var u := q.x + 0.5
	var v := 0.5 - q.y
	if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
		return null
	return Vector2(1.0 - u if bool(e["flip"]) else u, v)


## TWO-POINT SCALE: two points on the picture (uv) are `metres` apart -> the height that makes them so (the aspect kept)
static func height_for(e: Dictionary, a: Vector2, b: Vector2, metres: float) -> float:
	var d := Vector2((a.x - b.x) * float(e["aspect"]), a.y - b.y).length()   # in picture heights
	return float(e["height"]) if d < 1e-9 else metres / d


## "180", "180 cm", "1.8 m", "1800 mm" -> metres (NAN when it is not a length); a bare number is cm
static func parse_len(s: String) -> float:
	var t := s.strip_edges().to_lower().replace(",", ".")
	var k := 0.01
	for u in [["mm", 0.001], ["cm", 0.01], ["m", 1.0]]:
		if t.ends_with(u[0]):
			t = t.trim_suffix(u[0]).strip_edges()
			k = u[1]
			break
	if not t.is_valid_float():
		return NAN
	var v := t.to_float() * k
	return v if is_finite(v) and v > 0.0 else NAN


# ---------------------------------------------------------------- on the mesh, in the .kmesh

static func list(m: KMesh) -> Array:
	return m.get_meta(META) if m != null and m.has_meta(META) else []


static func store(m: KMesh, l: Array) -> void:
	if l.is_empty():
		if m.has_meta(META):
			m.remove_meta(META)
	else:
		m.set_meta(META, l)


static func to_file(m: KMesh) -> Array:
	return clean(list(m))


## read them back (KMesh.from_dict): only what is valid, every number finite and in range; never crashes on a bad file
static func from_file(m: KMesh, d) -> void:
	store(m, clean(d))


static func clean(l) -> Array:
	var out := []
	if not l is Array:
		return out
	for e in l:
		if not e is Dictionary or String((e as Dictionary).get("path", "")) == "":
			continue
		var o := {"path": String(e["path"]), "hash": String(e.get("hash", "")),
			"axis": String(e.get("axis", "front")) if String(e.get("axis", "front")) in AXES else "front",
			"base": _v3(e.get("base"), [0.0, 0.0, 0.0]), "offset": _v3(e.get("offset"), [0.0, 0.0, 0.0]),
			"height": clampf(_f(e.get("height", 1.0), 1.0), MIN_H, MAX_H), "aspect": clampf(_f(e.get("aspect", 1.0), 1.0), 0.001, 1000.0),
			"opacity": clampf(_f(e.get("opacity", 0.5), 0.5), 0.0, 1.0), "flip": bool(e.get("flip", false)),
			"lock": bool(e.get("lock", false)), "only_view": bool(e.get("only_view", false))}
		out.append(o)
	return out


static func _f(v, d: float) -> float:
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return d
	var x := float(v)
	return x if is_finite(x) else d


static func _v3(v, d: Array) -> Array:
	if not v is Array or (v as Array).size() < 3:
		return d.duplicate()
	return [_f(v[0], d[0]), _f(v[1], d[1]), _f(v[2], d[2])]
