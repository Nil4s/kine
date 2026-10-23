## godot --headless --path . -s tests/sepjoin_test.gd     (ROADMAP_400 B17 + the vertex-click fix in KMeshView.ray_face)
## Bars, written before measuring:
##  0 VERTEX CLICK (the fix): 1000 clicks EXACTLY on the projected point of a seen vertex (random camera 1.5-3 m away, any
##    direction; a vertex is seen when one of its faces faces the camera) on each of: the 1-quad-a-side cube, the 4x4 test
##    cube, the dense test sphere (KMeshSculptUI.make_sphere, 24 splits): ray_face hits a face at every one (0 misses
##    of 3000). The same rays through the OLD strict Moller-Trumbore (a copy kept here) miss some (> 0): the instrument can
##    move. Named cases: the click on each of a front-seen cube's 8 corners that faces the camera, and on a sphere vertex
##    on the silhouette, hit. Not too lenient: from 3 m on the cube's axis a ray 0.1 mm outside the silhouette corner
##    misses, 0.1 mm inside hits.
extends SceneTree

var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


## the pre-fix ray_face test (strict barycentric bounds), for the before / after count
static func strict_hit(m: KMesh, o: Vector3, d: Vector3) -> bool:
	for f in m.faces:
		var fp: PackedInt32Array = f
		for i in range(1, fp.size() - 1):
			var a := m.verts[fp[0]]
			var e1 := m.verts[fp[i]] - a
			var e2 := m.verts[fp[i + 1]] - a
			var p := d.cross(e2)
			var det := e1.dot(p)
			if det <= 1e-14:
				continue
			var iv := 1.0 / det
			var tv := o - a
			var u := tv.dot(p) * iv
			if u < 0.0 or u > 1.0:
				continue
			var q := tv.cross(e1)
			var v := d.dot(q) * iv
			if v < 0.0 or u + v > 1.0:
				continue
			if e2.dot(q) * iv > 1e-6:
				return true
	return false


func seen(m: KMesh, vi: int, cam_pos: Vector3) -> bool:
	for fi in m.vert_faces(vi):
		if m.face_normals[fi].dot(cam_pos - m.verts[vi]) > 0.0:
			return true
	return false


func _init() -> void:
	await process_frame
	var cam := Camera3D.new()
	root.add_child(cam)
	await process_frame
	# ---- 0 the vertex click
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var total_new := 0
	var total_old := 0
	for which in ["cube", "cube4", "sphere"]:
		var km: KMesh = KMeshPrims.cube() if which == "cube" else (KMeshView.make_cube(1.0, 4) if which == "cube4" else KMeshSculptUI.make_sphere())
		var v := KMeshView.new()
		root.add_child(v)
		await process_frame
		v.set_mesh(km)
		var miss := 0
		var miss_old := 0
		var n := 0
		while n < 1000:
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
			cam.position = dir * rng.randf_range(1.5, 3.0)
			cam.look_at(Vector3.ZERO, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
			var vi := rng.randi() % km.vert_count()
			if not seen(km, vi, cam.position):
				continue
			n += 1
			var sp := cam.unproject_position(km.verts[vi])
			var o := cam.project_ray_origin(sp)
			var d := cam.project_ray_normal(sp)
			if v.ray_face(o, d).is_empty():
				miss += 1
			if not strict_hit(km, o, d):
				miss_old += 1
		total_new += miss
		total_old += miss_old
		print("  %s: %d of 1000 vertex clicks missed before the fix, %d after" % [which, miss_old, miss])
		ok(miss == 0, "(0) %s (%d verts): 1000 clicks exactly on seen vertices, %d miss (bar 0; the old strict test missed %d)" % [which, km.vert_count(), miss, miss_old])
		v.free()
	ok(total_old > 0, "(0) the instrument can move: the old strict test misses %d of the same 3000 rays" % total_old)
	# named cases: a cube seen from a corner direction, every camera-facing corner; a silhouette vertex of the sphere
	var cube := KMeshPrims.cube()
	var cv := KMeshView.new()
	root.add_child(cv)
	await process_frame
	cv.set_mesh(cube)
	cam.position = Vector3(1.7, 1.3, 2.1)
	cam.look_at(Vector3.ZERO)
	var corners_hit := 0
	var corners_seen := 0
	for vi in cube.vert_count():
		if seen(cube, vi, cam.position):
			corners_seen += 1
			var sp := cam.unproject_position(cube.verts[vi])
			corners_hit += 0 if cv.ray_face(cam.project_ray_origin(sp), cam.project_ray_normal(sp)).is_empty() else 1
	ok(corners_seen == 7 and corners_hit == corners_seen, "(0) a cube seen from (1.7, 1.3, 2.1): a click on each of its %d seen corners hits (%d)" % [corners_seen, corners_hit])
	var sph := KMeshSculptUI.make_sphere()
	var sv := KMeshView.new()
	root.add_child(sv)
	await process_frame
	sv.set_mesh(sph)
	cam.position = Vector3(0, 0, 2.0)
	cam.look_at(Vector3.ZERO)
	var sil := -1   # the seen vertex nearest the outline (its normal most nearly square to the view)
	var best := INF
	for vi in sph.vert_count():
		var nn := sph.verts[vi].normalized()
		var c := nn.dot((cam.position - sph.verts[vi]).normalized())
		if c > 0.0 and c < best and seen(sph, vi, cam.position):
			best = c
			sil = vi
	var ssp := cam.unproject_position(sph.verts[sil])
	ok(not sv.ray_face(cam.project_ray_origin(ssp), cam.project_ray_normal(ssp)).is_empty(), "(0) a click on the sphere's silhouette vertex %d (its normal %.2f deg short of square to the view) hits" % [sil, 90.0 - rad_to_deg(acos(best))])
	sv.free()
	# not too lenient: 3 m away on the axis, the corner (0.5, 0.5, 0.5) is on the outline
	cam.position = Vector3(0, 0, 3.0)
	cam.look_at(Vector3.ZERO)
	var out_p := Vector3(0.5001, 0.5001, 0.5)
	var in_p := Vector3(0.4999, 0.4999, 0.5)
	var h_out := cv.ray_face(cam.position, (out_p - cam.position).normalized())
	var h_in := cv.ray_face(cam.position, (in_p - cam.position).normalized())
	ok(h_out.is_empty() and not h_in.is_empty(), "(0) 0.1 mm outside the outline corner misses (%s), 0.1 mm inside hits (%s)" % [h_out.is_empty(), not h_in.is_empty()])
	cv.free()
	print("SEPJOIN ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
