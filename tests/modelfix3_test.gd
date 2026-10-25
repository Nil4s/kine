extends SceneTree
## MODEL FIX ROUND 3 (walk-through 3 of the expert MODEL page). Bars, stated before measuring (each one fails on the
## round-2 code, the run log of that run is in C:/Temp/claude/mf3_old/):
##   1 UV editor: opened on a MODEL page with the Materials panel, it does not cover the mesh on screen, and a pointer
##     over the mesh is not over the UV panel (the walk's clicks landed on the panel and Assign found nothing selected)
##   2 view cube: the Materials panel does not cover the ViewCube (the walk saw a clipped "TO" at the top right)
##   3 knife: a click off the model says so ("missed the model"); Enter with one point keeps the knife running and says
##     how many points it needs; two clicks on a face + Enter cut (the guard: the cut itself still works)
##   4 mirror: the default plane is the mesh's own centre, so the copy of an off-origin mesh lands on the mesh (the
##     walk's table: the copy went to the far side of x = 0); an explicit plane still works when "centre" is off
##   5 G / R / S with Z: the status line says "Z (depth; up is Y here)"
##   6 Export model -> "Use last export as a prop": the exported GLB is in My models (Props) at its real size
## Script errors are checked by the runner's log scan (a SCRIPT ERROR line fails the suite).
var fails := 0
func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1

func idle(n := 3) -> void:
	for i in n:
		await process_frame

func mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame

func hover(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e)
	await process_frame
	await idle(2)

func click(p: Vector2) -> void:
	await hover(p)
	await mouse(p, true)
	await mouse(p, false)
	await idle(2)

func key(k: Key, shift := false) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.shift_pressed = shift
		ev.pressed = down
		root.push_input(ev)
		await process_frame
	await idle(3)

## the on-screen rect of the edit mesh (its vertices projected); a zero rect when none is in view
func mesh_rect(m: Node) -> Rect2:
	var v: KMeshView = m.kmed.view
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for i in m.kmed.mesh.vert_count():
		var s: Variant = v._screen(m.cam, v._to_world(i))
		if s == null:
			continue
		lo = lo.min(s)
		hi = hi.max(s)
	return Rect2(lo, hi - lo)

func status(m: Node) -> String:
	return str(m.ui_status.text)

func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.easy.set_on(false, false)
	await idle(2)
	m.ui_page_btns["MODEL"].pressed.emit()
	await idle(3)
	m._kmesh_edit_start()
	await idle(4)
	var kmed = m.kmed
	var mat: Control = kmed.mat_panel

	# 1 + 2: the UV editor and the view cube against the Materials panel and the mesh
	kmed.toggle_uv_editor()
	await idle(6)
	var uv: Control = kmed.uved
	var mr := mesh_rect(m)
	var uvr: Rect2 = uv.get_global_rect()
	ok(uv.visible and mat.visible and mr.size.x > 10.0, "1a the UV editor and the Materials panel are open over the MODEL page (mesh on screen %s)" % str(mr))
	var matr0: Rect2 = mat.get_global_rect()
	ok(uvr.position.x >= matr0.position.x - 1.0 and not uvr.grow(-1.0).intersects(mr.grow(-1.0)),
		"1b the UV editor (%s) is docked in the Materials column (%s) and does not cover the mesh (%s)" % [str(uvr), str(matr0), str(mr)])
	var hov := m.get_viewport().gui_get_hovered_control()
	var over_uv: bool = hov != null and (hov == uv or uv.is_ancestor_of(hov))
	await hover(mr.get_center())
	hov = m.get_viewport().gui_get_hovered_control()
	over_uv = hov != null and (hov == uv or uv.is_ancestor_of(hov))
	ok(not over_uv, "1c a pointer over the mesh (%s) is not taken by the UV editor (under it: %s)" % [str(mr.get_center()), "nothing" if hov == null else str(hov.name)])
	var cube: Control = m.ui_cube
	var matr: Rect2 = mat.get_global_rect()
	ok(not cube.get_global_rect().grow(-1.0).intersects(matr.grow(-1.0)), "2 the Materials panel (%s) does not cover the ViewCube (%s)" % [str(matr), str(cube.get_global_rect())])
	kmed.toggle_uv_editor()   # close it again for the knife
	await idle(4)

	# 3 knife: a miss says so, Enter with one point keeps the tool, two clicks on a face cut
	var c_face := -1
	var f_pts := []
	for fi in kmed.mesh.face_count():
		var fp: PackedInt32Array = kmed.mesh.faces[fi]
		var cen := Vector2.ZERO
		var pts := []
		for v in fp:
			var s: Variant = kmed.view._screen(m.cam, kmed.view._to_world(v))
			if s == null:
				pts = []
				break
			pts.append(s)
			cen += s
		if pts.is_empty():
			continue
		cen /= float(pts.size())
		if not kmed.view.pick(m.cam, cen, 12.0).is_empty() and pts.size() == 4:
			c_face = fi
			# a cut across the quad: the midpoints of two opposite edges (the snap lands each click on its edge)
			f_pts = [(pts[0] + pts[1]) * 0.5, (pts[2] + pts[3]) * 0.5]
			break
	ok(c_face >= 0, "3a a face of the cube is on screen to click (face %d)" % c_face)
	var miss := Vector2(-1, -1)
	for y in range(120, 700, 40):
		for x in range(320, 1100, 40):
			if kmed.view.pick(m.cam, Vector2(x, y), 12.0).is_empty() and mesh_rect(m).has_point(Vector2(x, y)) == false:
				miss = Vector2(x, y)
				break
		if miss.x >= 0:
			break
	await key(KEY_K, true)
	await click(miss)
	var st := status(m)
	ok(st.contains("missed the model") and st.contains("0 points"),
		"3a a knife click off the model says so: \"%s\"" % st)
	await click(f_pts[0])
	await key(KEY_ENTER)
	var tool = KMeshCutTool.of(kmed)
	ok(tool != null and tool.mode == "knife" and tool.pts.size() == 1, "3b Enter with one point keeps the knife running (mode %s, %d point)" % [str(tool.mode if tool else "none"), tool.pts.size() if tool else -1])
	ok(status(m).contains("2 points") or status(m).contains("needs 2"), "3c that Enter says how many points it needs: \"%s\"" % status(m))
	# the second point: the opposite edge's midpoint, then Enter cuts
	var v0: int = kmed.mesh.vert_count()
	await click(f_pts[1])
	await key(KEY_ENTER)
	ok(kmed.mesh.vert_count() > v0 and KMeshCutTool.of(kmed).mode == "", "3d two clicks across a face + Enter cut it (verts %d -> %d)" % [v0, kmed.mesh.vert_count()])

	# 5 G / R / S with the Z axis: the status says what Z is here
	m.blk.where = "mesh"
	m.blk.active = "S"
	m.blk.axis = 2
	var rd: String = m.blk.readout()
	ok(rd.contains("Z (depth; up is Y here)"), "5 a Z-constrained S reads \"%s\"" % rd)
	m.blk.active = ""
	m.blk.axis = -1
	m.blk.where = ""

	# 4 mirror: the default plane is the mesh's own centre (an off-origin mesh does not grow its bbox)
	var base_v := PackedVector3Array()
	var cube_m := KMeshView.make_cube(0.5, 2)
	for v in cube_m.verts:
		base_v.append(v + Vector3(1.0, 0.0, 0.0))
	var k := KMesh.new().from_arrays(base_v, cube_m.faces)
	KMeshModifiers.add(k, "mirror")
	var out := KMeshModifiers.evaluate(k)
	var lo0 := Vector3(1e9, 1e9, 1e9)
	var hi0 := -lo0
	for v in k.verts:
		lo0 = lo0.min(v)
		hi0 = hi0.max(v)
	var lo1 := Vector3(1e9, 1e9, 1e9)
	var hi1 := -lo1
	for v in out.verts:
		lo1 = lo1.min(v)
		hi1 = hi1.max(v)
	ok((lo1 - lo0).length() < 1e-4 and (hi1 - hi0).length() < 1e-4,
		"4a Mirror on X of a mesh at x = 1 m keeps its bounds (x %.3f..%.3f -> %.3f..%.3f)" % [lo0.x, hi0.x, lo1.x, hi1.x])
	var k2 := KMesh.new().from_arrays(base_v, cube_m.faces)
	KMeshModifiers.add(k2, "mirror", {"centre": false, "plane": 0.0})
	var out2 := KMeshModifiers.evaluate(k2)
	var lo2 := Vector3(1e9, 1e9, 1e9)
	for v in out2.verts:
		lo2 = lo2.min(v)
	ok(lo2.x < -0.5, "4b an explicit plane (centre off, plane 0) still mirrors about it: min x %.3f" % lo2.x)

	# 6 Export model -> Use as a prop
	kmed.undo.steps.clear()
	var path: String = m._export_model()
	ok(path != "" and FileAccess.file_exists(path), "6a Export model writes the GLB (%s)" % path)
	ok(m.has_method("_use_export_as_prop"), "6b the export has a 'Use as a prop' route")
	if m.has_method("_use_export_as_prop"):
		m._use_export_as_prop()
		await idle(3)
		var kind := "my test_cube"
		var reg := Props.has_kind(kind)
		ok(reg, "6c the exported model is in My models (Props kind '%s')" % kind)
		if reg:
			var kd: Dictionary = Props.kind_of(kind)
			var bb := Vector3.ZERO
			var mn := Vector3(1e9, 1e9, 1e9)
			var mx := -mn
			for v in kmed.mesh.verts:
				mn = mn.min(v)
				mx = mx.max(v)
			bb = mx - mn
			var sz: Vector3 = (kd["aabb"] as AABB).size * float(kd["factor"])
			ok(sz.distance_to(bb) < 0.01, "6d the prop is at its real size: %s m vs the mesh %s m" % [str(sz), str(bb)])
			# clean up what this run wrote (the prop copy and the export files)
			Props.EXTRA.erase(kind)
			for p in [String(kd["glb"]), path, path.trim_suffix(".glb") + ".obj", path.trim_suffix(".glb") + ".mtl"]:
				if FileAccess.file_exists(p):
					DirAccess.remove_absolute(p)

	print("MODEL FIX 3 ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
