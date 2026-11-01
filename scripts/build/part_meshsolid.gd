class_name PartMeshSolid
extends RefCounted
## s155 MESH -> SOLID (Friday plan item 155: "turn a sculpt into a CAD body you can drill and fillet"; the reverse of 156 "Sculpt details?").
## The Sculpt page's "Make it a solid part" button turns the open sculpt mesh into ONE solid of the part record, so Easy Part can drill,
## round and hollow it. The kernel sews every triangle into one closed shell and makes a solid of it (KCad.solid_from_mesh: the native
## KineCAD call added for this item: BRepBuilderAPI_Sewing + MakeSolid). The mesh must be CLOSED (no hole in its skin) and in one piece.
## The record step: {"t": "meshsolid", "id", "name", "v": base64 of float32 x,y,z in MM, "f": base64 of int32 triangle corners, "tris": count,
## "vol": the mesh's own volume in mm3}. Plain strings, so the undo snapshot, the scene file and the JSON hold it cheaply. A faceted solid
## (its faces ARE the mesh's triangles): holes cut through it like through any solid; fillets of the facets are not meaningful.
## The sewn master solid is kept per mesh (a replay runs on every slider move): a replay takes a copy of it.

const KCad := preload("res://scripts/kcad.gd")
const MM := 0.001
const TOL := 1e-6          # m: sewing tolerance (1 micron; the mesh's corners are shared by index, so they meet exactly)
const MAX_TRIS := 60000    # a mesh above this is too heavy for the kernel to cut quickly: it is told to remesh coarser

static var _masters := {}   # content hash -> kernel id of the sewn solid (never released: a replay copies it)


## the mesh as the record wants it, or why not. Returns {"ok", "why", "f": the step's fields, "vol_mm3", "size_mm": Vector3, "tris"}.
## basis: how the sculpt view is turned (identity unless the sculpt is of a posed body). The mesh is centred left-right and front-back and
## rests on the floor (its lowest point at y = 0), like a part dropped from the library
static func from_mesh(km: KMesh, basis := Basis()) -> Dictionary:
	if km == null or km.vert_count() < 4 or km.face_count() < 4:
		return {"ok": false, "why": "There is no sculpt to turn into a part yet. Open a sculpt first"}
	var open_n := km.boundary_edge_count()
	if open_n > 0:
		return {"ok": false, "why": "This sculpt is not closed: its skin has %d open edges (a hole you can see through). Close the hole, then try again" % open_n}
	if not km.is_manifold():
		return {"ok": false, "why": "This sculpt folds back on itself (some edges are shared by three faces). Smooth or remesh it, then try again"}
	var tri := PackedInt32Array()
	for fc in km.faces:
		var f: PackedInt32Array = fc
		for k in range(1, f.size() - 1):
			tri.append(f[0])
			tri.append(f[k])
			tri.append(f[k + 1])
	if tri.size() / 3 > MAX_TRIS:
		return {"ok": false, "why": "This sculpt has %d faces: too many to cut and drill. Use Voxel remesh to make it lighter, then try again" % (tri.size() / 3)}
	var pts := PackedVector3Array()
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in km.verts:
		var p: Vector3 = basis * v * 1000.0
		pts.append(p)
		lo = lo.min(p)
		hi = hi.max(p)
	var shift := Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5)
	var buf := PackedFloat32Array()
	var vol := 0.0
	for i in pts.size():
		pts[i] -= shift
		buf.append(pts[i].x)
		buf.append(pts[i].y)
		buf.append(pts[i].z)
	for t in range(0, tri.size(), 3):
		vol += pts[tri[t]].dot(pts[tri[t + 1]].cross(pts[tri[t + 2]])) / 6.0
	var ib := PackedInt32Array(tri)
	return {"ok": true, "why": "", "vol_mm3": absf(vol), "size_mm": hi - lo, "tris": tri.size() / 3,
		"f": {"v": Marshalls.raw_to_base64(buf.to_byte_array()), "f": Marshalls.raw_to_base64(ib.to_byte_array()), "tris": tri.size() / 3, "vol": absf(vol)}}


## the kernel solid of a meshsolid step (a fresh id the caller owns), or 0 with KCad.last_error() saying why
static func solid(f: Dictionary) -> int:
	var key := hash(String(f.get("v", "")) + "|" + String(f.get("f", "")))
	if _masters.has(key):
		var c := KCad.translate(int(_masters[key]), Vector3.ZERO)
		if c != 0:
			return c
		_masters.erase(key)   # the kernel was cleared (release_all): sew again
	var vb := Marshalls.base64_to_raw(String(f.get("v", ""))).to_float32_array()
	var ib := Marshalls.base64_to_raw(String(f.get("f", ""))).to_int32_array()
	var vs := PackedVector3Array()
	for i in range(0, vb.size() - 2, 3):
		vs.append(Vector3(vb[i], vb[i + 1], vb[i + 2]) * MM)
	var id := KCad.solid_from_mesh(vs, ib, TOL)
	if id == 0:
		return 0
	_masters[key] = id
	return KCad.translate(id, Vector3.ZERO)


## the replay arm (Part.replay): the step adds ONE new body. "" or the plain reason it could not
static func add(bodies: Array, f: Dictionary) -> String:
	if not KCad.has_mesh_solid():
		return "The part library is older than this step: restart Kine, or reinstall it"
	var id := solid(f)
	if id == 0:
		return KCad.last_error() if KCad.last_error() != "" else "The mesh could not become a solid"
	bodies.append(id)
	return ""


## the Sculpt page's "Make it a solid part": the open sculpt becomes the part (ONE undo step) and Easy Part shows it.
## Returns the plain sentence that was said (tests read it too)
static func convert(m: Node) -> String:
	var say := _convert(m)
	m._say(say)
	return say


static func _convert(m: Node) -> String:
	if not Part.available() or not KCad.has_mesh_solid():
		return "Solid parts need the part library, and it is not loaded: restart Kine first"
	var ksc = m.get("ksc")
	if ksc == null or not ksc.on or ksc.mesh == null:
		return "Open a sculpt first (Test sphere), then press Make it a solid part"
	var basis := Basis()
	if ksc.view != null:
		basis = Basis(ksc.view.transform.basis.get_rotation_quaternion())
	var got := from_mesh(ksc.mesh, basis)
	if not bool(got["ok"]):
		return String(got["why"])
	var rec: Dictionary = m.S.part if not m.S.part.is_empty() else Part.make("Part")
	rec = rec.duplicate(true)
	var had := (rec.get("features", []) as Array).size()
	var feat := Part.new_feature(rec, "meshsolid", {"name": "Sculpt solid"})
	for k in (got["f"] as Dictionary):
		feat[k] = (got["f"] as Dictionary)[k]
	rec["features"].append(feat)
	var res := Part.replay(rec)
	var errs: Dictionary = res["errors"]
	if errs.has(String(feat["id"])):
		return "The sculpt could not become a solid: " + String(errs[String(feat["id"])]) + ". Smooth the skin or remesh it, then try again"
	var want := float(got["vol_mm3"])
	var have := float(res["volume"]) / (MM * MM * MM)
	if int(res["bodies"]) != (1 if had == 0 else int(res["bodies"])) or absf(have - want) > 0.02 * want:
		return "The sculpt did not become a clean solid (its volume came out %.0f mm3, the sculpt is %.0f mm3). Remesh it, then try again" % [have, want]
	m._step_hint = "Make it a solid part"
	m._push_undo()
	m.S.part = rec
	if ksc.on:
		ksc.stop()   # leaves the sculpt; nothing else of it is saved
	m._page_set("BUILD")   # back from the Sculpt page to the building page (the sculpt turned Easy off)
	m.bld.part.open_easy()
	m._fit_top.call_deferred()
	return "Done: your sculpt is a solid part now (%.0f x %.0f x %.0f mm). Press Cut a hole to drill it, or Undo to take it back" % [(got["size_mm"] as Vector3).x, (got["size_mm"] as Vector3).y, (got["size_mm"] as Vector3).z]
