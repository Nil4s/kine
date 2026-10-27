extends SceneTree
## godot --path . --position 4000,4000 -s tests/instancing_test.gd     (M3 INSTANCING: scripts/prop_instances.gd, main.gd _props_show / _prop_copies_row; needs a window for the frame rate)
## A probe model: a 5046-face cube (29 x 29 quads a side, a KMesh written through MeshProps as a library model) as a prop.
## Bars, written before measuring:
##   1 SHARED   200 still copies of the probe in the set: ONE group, and one MultiMeshInstance3D per mesh of the model, 200 instances each
##   2 SAME     each instance sits where its own drawn node would: the global transform of 5 copies' meshes (sampled across the set,
##              the nodes built by Props.mesh and put in the tree) equals the instance's, within 1e-5 on origin and basis
##   3 OUT      a keyed copy and a single copy are not drawn shared; the picked copy keeps its own node; a box (no model) is never shared
##   4 ROW      "Copies in a row" of the probe: 10 copies, each one gap (10 cm) plus the probe's drawn width beyond the last, within 1 mm;
##              every copy on the floor (origin y within 1 mm of 0)
##   5 APP      the app: 3 probes added, the 3rd picked, then Copies in a row: the picked copy keeps its own node, the other 12 are one
##              MultiMeshInstance3D with 12 instances, and the 13 props are all in the scene's list; Add prop's last item does the same
##   6 FPS      200 instances of the probe drawn in the window, vsync off, 240 frames: >= 60 frames a second
##   7 DRAWS    the 200 instances are drawn in <= 2 draw calls (one per mesh of the model); the app before M3 (one node per prop) needs >= 100
##   8 MEMORY   the bytes of the 200 instances (the mesh once, 48 bytes a copy in the MultiMesh buffer) <= 1.5 x the bytes of one copy
## Shots: user:// (instancing_row.png, instancing_app.png), copied to C:/Temp/claude/instancing/ by the run.
## Only user:// is written (the probe's model and note are removed at the end).

const PROBE := "instancing_probe"
const N := 200
const DIRT := "user://instancing_test"
var fails := 0
var m: Node
var app_done := false


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the bytes of a mesh's surfaces (vertex, normal, uv, colour, index arrays as they are stored)
func mesh_bytes(mesh: Mesh) -> int:
	var b := 0
	for s in mesh.get_surface_count():
		for a in mesh.surface_get_arrays(s):
			if a == null:
				continue
			if a is PackedVector3Array:
				b += (a as PackedVector3Array).size() * 12
			elif a is PackedVector2Array:
				b += (a as PackedVector2Array).size() * 8
			elif a is PackedColorArray:
				b += (a as PackedColorArray).size() * 16
			elif a is PackedInt32Array:
				b += (a as PackedInt32Array).size() * 4
			elif a is PackedFloat32Array:
				b += (a as PackedFloat32Array).size() * 4
	return b


## every MeshInstance3D under n with its global transform (n must be in the tree)
func mesh_nodes(n: Node) -> Array:
	var out := []
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		out.append(mi)
	return out


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	await _run()
	ok(app_done, "the run reached its last bar (no script error cut it short)")
	# tidy: the probe's model and its note (this run wrote them; nothing else is removed)
	var dir := MeshProps.props_dir()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s.glb" % [dir, PROBE]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s.licence.txt" % [dir, PROBE]))
	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)


func _run() -> void:
	# ---- the probe model: a 5046-face cube, written as a library model (what MODEL > Use in scene makes)
	var k := KMeshView.make_cube(1.0, 29)
	print("probe faces ", k.face_count())
	var kind := MeshProps.write_model(k, PROBE, "instancing test")
	ok(kind == "my " + PROBE, "probe model written and registered as %s" % kind)
	if kind == "":
		return
	var faces_ok := k.face_count() >= 5000 and k.face_count() <= 5100
	ok(faces_ok, "probe is a 5k-face mesh (%d faces)" % k.face_count())

	# ---- 1 SHARED, 2 SAME
	var props := []
	for i in N:
		var xf := Transform3D(Basis.IDENTITY, Vector3(float(i % 14) * 1.5, 0.0, float(i / 14) * 1.5))
		props.append(Props.make(kind, xf))
	var plan := PropInstances.plan(props)
	ok(plan.size() == 1 and (plan[0] as Array).size() == N, "1 SHARED: 200 still copies form ONE group of 200 (%d groups)" % plan.size())
	var mms := PropInstances.build(props, plan[0])
	var parts_ok := not mms.is_empty()
	for mmi in mms:
		parts_ok = parts_ok and (mmi as MultiMeshInstance3D).multimesh.instance_count == N
	ok(parts_ok and mms.size() == 1, "1 SHARED: one MultiMeshInstance3D for the probe's one mesh, %d instances (%d nodes)" % [N, mms.size()])

	# the drawn nodes of 5 copies, in the tree, against the instance transforms
	var sample := [0, 37, 101, 150, 199]
	var worst := 0.0
	var ref := Node3D.new()
	root.add_child(ref)
	var mmi_root := Node3D.new()
	root.add_child(mmi_root)
	for mmi in mms:
		mmi_root.add_child(mmi)
	var nodes := {}
	for i in sample:
		var n := Props.mesh(props[i])
		ref.add_child(n)
		nodes[i] = mesh_nodes(n)
	await idle(2)   # the nodes enter the tree at the next frame (global transforms need it)
	for i in sample:
		var j: int = (plan[0] as Array).find(i)
		var mis: Array = nodes[i]
		for q in mis.size():
			if q >= mms.size():
				continue
			var mm_q: MultiMesh = (mms[q] as MultiMeshInstance3D).multimesh
			var want: Transform3D = (mis[q] as MeshInstance3D).global_transform
			var got: Transform3D = (mms[q] as MultiMeshInstance3D).global_transform * mm_q.get_instance_transform(j)
			worst = maxf(worst, (want.origin - got.origin).length())
			for c in 3:
				worst = maxf(worst, (want.basis[c] - got.basis[c]).length())
	ok(worst <= 1e-5, "2 SAME: 5 copies' drawn meshes sit where their instances are (worst %.7f m)" % worst)
	ref.queue_free()
	mmi_root.queue_free()
	await idle(2)

	# ---- 3 OUT
	var keyed := Props.make(kind, Transform3D(Basis.IDENTITY, Vector3(40.0, 0.0, 0.0)))
	Props.key_at(keyed, 0.0, keyed["xf"])
	var one := [Props.make(kind, Transform3D(Basis.IDENTITY, Vector3(50.0, 0.0, 0.0)))]
	var box := Props.make("box", Transform3D(Basis.IDENTITY, Vector3(60.0, 0.0, 0.0)))
	var mixed := props.duplicate()
	mixed.append(keyed)
	mixed.append(box)
	var pl := PropInstances.plan(mixed, N + 1)
	var outs := true
	for g in pl:
		outs = outs and not ((g as Array).has(N) or (g as Array).has(N + 1))
	ok(outs, "3 OUT: a keyed copy, a box, and the picked copy are not in any shared group")
	ok(PropInstances.plan(one).is_empty(), "3 OUT: a single copy of a kind is not shared")
	var picked_group := PropInstances.plan(props, 3)
	ok(picked_group.size() == 1 and (picked_group[0] as Array).size() == N - 1 and not (picked_group[0] as Array).has(3), "3 OUT: the picked copy keeps its own node (group of %d)" % (N - 1))

	# ---- 4 ROW
	var sel := Props.make(kind, Transform3D(Basis.IDENTITY, Vector3(-10.0, 0.0, 0.0)))
	var row_props := [sel]
	var copies := PropInstances.row(row_props, 0, 10, 0.1)
	ok(copies.size() == 10, "4 ROW: 10 copies (%d)" % copies.size())
	# the probe's drawn width, measured from the built node in the tree
	var probe_node := Props.mesh(sel)
	root.add_child(probe_node)
	await idle(2)
	var lo := INF
	var hi := -INF
	for mi in mesh_nodes(probe_node):
		var bb: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).mesh.get_aabb()
		lo = minf(lo, bb.position.x)
		hi = maxf(hi, bb.end.x)
	var w := hi - lo
	probe_node.queue_free()
	var row_ok := true
	var prev := (sel["xf"] as Transform3D).origin.x
	var worst_gap := 0.0
	for c in copies:
		var x: float = (c["xf"] as Transform3D).origin.x
		worst_gap = maxf(worst_gap, absf((x - prev) - (w + 0.1)))
		prev = x
		row_ok = row_ok and absf((c["xf"] as Transform3D).origin.y) <= 0.001
	ok(worst_gap <= 0.001 and row_ok, "4 ROW: each copy %.3f m beyond the last (drawn width %.3f m + 0.100 m), worst error %.4f m, on the floor" % [w + 0.1, w, worst_gap])

	# ---- 6 FPS, 7 DRAWS, 8 MEMORY: the 200 drawn in the window
	var world := Node3D.new()
	root.add_child(world)
	mms = PropInstances.build(props, plan[0])   # fresh nodes: the ones above were freed with their test root
	for mmi in mms:
		world.add_child(mmi)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(10.0, 14.0, 26.0)
	cam.look_at(Vector3(10.0, 0.0, 5.0), Vector3.UP)
	cam.current = true
	var light := DirectionalLight3D.new()
	world.add_child(light)
	light.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	var prev_vsync := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await idle(30)
	var t0 := Time.get_ticks_usec()
	for i in 240:
		await process_frame
	var secs := float(Time.get_ticks_usec() - t0) / 1e6
	var fps := 240.0 / secs
	ok(fps >= 60.0, "6 FPS: 200 instances of the 5k-face probe at %.1f frames a second (vsync off, 240 frames, %.2f s)" % [fps, secs])

	var draws := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	get_root().get_texture().get_image().save_png("user://instancing_row.png")

	var mesh0: Mesh = (mms[0] as MultiMeshInstance3D).multimesh.mesh
	# baseline = the app before M3: one node per prop, each built by Props.mesh (its own material), in the same window
	for mmi in mms:
		world.remove_child(mmi)
		mmi.queue_free()
	await idle(1)
	for i in N:
		world.add_child(Props.mesh(props[i]))
	await idle(30)
	var t1 := Time.get_ticks_usec()
	for i in 240:
		await process_frame
	var base_fps := 240.0 / (float(Time.get_ticks_usec() - t1) / 1e6)
	var base_draws := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	print("     baseline, one node per prop (before M3): %d draw calls, %.1f frames a second" % [base_draws, base_fps])
	ok(draws <= 2 and base_draws >= N / 2, "7 DRAWS: shared, %d draw calls; one node per prop (before M3), %d draw calls" % [draws, base_draws])
	DisplayServer.window_set_vsync_mode(prev_vsync)
	world.queue_free()
	await idle(2)

	var one_bytes := mesh_bytes(mesh0) + 48
	var group_bytes := mesh_bytes(mesh0) + 48 * N
	var ratio := float(group_bytes) / float(one_bytes)
	ok(ratio <= 1.5, "8 MEMORY: 200 instances take %d bytes, one copy %d bytes: %.3f x (mesh %d bytes once, 48 bytes a copy)" % [group_bytes, one_bytes, ratio, mesh_bytes(mesh0)])

	# ---- 5 APP: the real set in the app
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(20)
	for i in 3:
		m._prop_add(kind)
	await idle(2)
	var before: int = m.S.props.size()
	m._prop_copies_row()
	await idle(3)
	var n_props: int = m.S.props.size()
	ok(n_props == before + 10 and before == 3, "5 APP: 3 probes, then Copies in a row adds 10 (%d props)" % n_props)
	var picked_node: Node = m.ui_props_root.get_node_or_null("prop_%d" % m.sel_prop)
	var shared_inst := 0
	var shared_nodes := 0
	for c in m.ui_props_root.get_children():
		if c is MultiMeshInstance3D:
			shared_nodes += 1
			shared_inst += (c as MultiMeshInstance3D).multimesh.instance_count
	ok(picked_node != null and shared_nodes == 1 and shared_inst == n_props - 1, "5 APP: the picked copy keeps its node, the other %d are one MultiMeshInstance3D (%d node)" % [shared_inst, shared_nodes])
	# the Expert way: Add prop's menu, its last item
	var ap := m.find_child("menu_add_prop", true, false) as MenuButton
	var menu_ok := false
	if ap != null:
		m._prop_menu_fill(ap)
		var pm := ap.get_popup()
		var row_id: int = Props.catalogue().size()
		var before2: int = m.S.props.size()
		m._prop_menu_pick(row_id, ap)
		await idle(2)
		menu_ok = pm.get_item_text(pm.item_count - 1) == "Copies in a row of the picked prop" and m.S.props.size() == before2 + 10
	ok(menu_ok, "5 MENU: Add prop's last item, Copies in a row of the picked prop, adds 10 copies")
	var win := get_root().get_texture().get_image()
	win.save_png("user://instancing_app.png")
	app_done = true
