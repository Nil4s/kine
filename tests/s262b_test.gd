extends SceneTree
## godot --path . --position 4000,4000 -s tests/s262b_test.gd   (s262b EXPLODED VIEW v2: scripts/build/explode_keys.gd, scripts/easy_explode.gd; needs the CAD DLL)
## Bars (written before the first run). Fixture: backplate, plate, 2 screws through both (as s262ui), made as records; window 1280x720, 1024x600, 1920x1080.
##   1 LIMIT     300 synthetic bodies (one look) pack into < 300 surfaces; body_ids = 300; split_pieces gives 300 meshes of 4 vertices at the right boxes;
##               shifted_mesh moves body 299 by 1 m and every other vertex 0 m. CONTROL: one surface per body would need 300 surfaces (surface count != 300).
##   2 KEYS      "Put on the timeline" (real click): one prop, one slide joint per moving body, one undo step; at 14 times the joint value (mm) equals the planner's
##               distance within 1e-4 mm. CONTROL: a planted wrong key (+1 mm) is caught by the same comparison.
##   3 NODES     the prop's piece nodes at the playhead (the app's own _props_pose) sit within 0.02 mm of ExplodeView.boxes_at; screws leave before the plate
##   4 EXPORT    m._blast_frame (the export's own step) at 3 times: pieces within 0.02 mm of the plan, and the PNG the real _export_playblast wrote for the same
##               time is the same picture (mean abs diff < 0.5 of 255). CONTROL: frame 0 and the frame at the end of out differ (mean abs diff > 1)
##   5 RELOAD    save, forget the kind, reload: the joints and keys are back, values at 3 times the same
##   6 VISIBLE   the pieces' silhouette in every camera frame sits inside ep.free_rect() (2 px) at every window size. CONTROL: framed to the whole window it
##               overlaps the panel (silhouette past free_rect().end.x) in at least one frame at 1280x720
var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/tools/kine_workers/out/s262b"
const DIRT := "user://s262b_test"


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv, true)
	await process_frame
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func box1(id0: int, a: Array, b: Array, d: float) -> Array:
	return [
		{"t": "sketch", "id": "f%d" % id0, "name": "Sketch%d" % id0, "plane": "front", "ents": [{"k": "rect", "a": a, "b": b}], "dims": []},
		{"t": "extrude", "id": "f%d" % (id0 + 1), "name": "Extrude%d" % id0, "sketch": "f%d" % id0, "dist": d, "both": true, "op": "new"}]


func set_part2(feats: Array, nm: String) -> void:
	var pu = m.bld.part
	var rec := Part.make(nm)
	rec["features"] = feats
	rec["seq"] = feats.size()
	m.S.part = rec
	pu.upto = -1
	pu.sync()
	await idle(3)


func test_limit() -> void:
	var mesh := ArrayMesh.new()
	var pend: Array = []
	for i in 300:
		var o := Vector3(i * 0.01, 0, 0)
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([o, o + Vector3(0.005, 0, 0), o + Vector3(0.005, 0.005, 0), o + Vector3(0, 0.005, 0)])
		arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		pend.append([arr, {"c": Color.RED}, i])
	var res := {"looks": [], "surf_body": [], "body_names": [], "volumes": []}
	Part.pack_surfaces(mesh, pend, res)
	ok(mesh.get_surface_count() < 300, "1 LIMIT 300 bodies packed into %d surfaces" % mesh.get_surface_count())
	var ids := ExplodeKeys.body_ids(mesh, res)
	ok(ids.size() == 300, "1 LIMIT body_ids = %d" % ids.size())
	var sp := ExplodeKeys.split_pieces(mesh, res)
	var good := sp.size() == 300
	for i in 300:
		if not sp.has(i):
			good = false
			continue
		var pm: ArrayMesh = sp[i]
		var vs: PackedVector3Array = pm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var bx := ExplodeKeys.box_of(vs)
		if vs.size() != 4 or absf(bx.position.x - i * 0.01) > 1e-6 or absf(bx.size.x - 0.005) > 1e-6:
			good = false
	ok(good, "1 LIMIT 300 pieces, 4 vertices each, boxes right")
	var sh := ExplodeKeys.shifted_mesh(mesh, res, {299: Vector3(0, 1, 0)})
	var bv := ExplodeKeys.body_verts(sh, res)
	var moved := 0
	var still := 0
	for i in 300:
		var bx := ExplodeKeys.box_of(bv[i])
		if absf(bx.position.y - 1.0) < 1e-6:
			moved += 1
		elif absf(bx.position.y) < 1e-6:
			still += 1
	ok(moved == 1 and still == 299 and bv.has(299), "1 LIMIT shifted_mesh moved %d, left %d" % [moved, still])
	ok(mesh.get_surface_count() != 300, "1 CONTROL one surface per body would need 300 surfaces, there are %d" % mesh.get_surface_count())
	res["mesh"] = mesh
	var pl := ExplodeKeys.plan_of(res, {"axis": Vector3.UP, "gap_mm": 5.0})
	ok(bool((pl["plan"] as Dictionary).get("ok", false)) and (pl["ids"] as Array).size() == 300, "1 LIMIT the planner takes the 300 bodies")


func piece_world_boxes(n: Node3D, count: int) -> Array:
	var out: Array = []
	for i in count:
		var mi := n.find_child("piece_%d" % i, true, false) as MeshInstance3D
		out.append(mi.global_transform * mi.get_aabb())
	return out


func plan_offsets(kd: Dictionary, sched: Dictionary, t: float) -> Array:
	return ExplodeView.offsets_at(kd["explode_plan"], sched, t)


func run_at(size: Vector2i, tag: String) -> void:
	root.content_scale_size = size
	root.size = size
	await idle(4)
	var pu: PartUI = m.bld.part
	var ep = pu.ep
	var feats: Array = []
	feats.append_array(box1(1, [-30.0, 0.0], [30.0, 2.0], 10.0))
	feats.append_array(box1(3, [-30.0, 2.0], [30.0, 4.0], 10.0))
	feats.append_array(box1(5, [-24.0, -2.0], [-20.0, 5.0], 2.0))
	feats.append_array(box1(7, [20.0, -2.0], [24.0, 5.0], 2.0))
	await set_part2(feats, "Stack")
	await idle(40)
	var xb = ep.xview_box
	var rowx: Dictionary = {}
	for r in EasySearch.rows(m):
		if String(r["name"]) == "Easy Part: Exploded view":
			rowx = r
	await (rowx["run"] as Callable).call()
	await idle(4)
	# 6 VISIBLE
	xb.cam_check.button_pressed = true
	xb.make(Vector3.UP, 10.0, false, true, 1.0, 0.4)
	var fr: Rect2 = ep.free_rect()
	var g := FrameFacts.gather(ep.m)
	var lob: Array = []
	lob.resize((g["names"] as Array).size())
	for u in (xb.plan["units"] as Array).size():
		for bi in xb.plan["units"][u]:
			lob[int(bi)] = u
	var W := float(root.content_scale_size.x)
	var H := float(root.content_scale_size.y)
	var cam0 := FrameFacts.camera_of(ep.m, {})
	var times: Array = [0.0, xb.sched["out_total"]]
	var inside := true
	var worst := 0.0
	var control_over := false
	var f_vis := ExplodeView.camera_frames(g, cam0, xb.plan, xb.sched, times, lob, 0.8, fr)
	var f_win := ExplodeView.camera_frames(g, cam0, xb.plan, xb.sched, times, lob, 0.8)
	for pass_i in 2:
		for fi in (f_vis if pass_i == 0 else f_win).size():
			var f: Dictionary = (f_vis if pass_i == 0 else f_win)[fi]
			var offs := ExplodeView.offsets_at(xb.plan, xb.sched, float(f["t"]))
			var verts: Array = []
			var boxes: Array = []
			for b in (g["names"] as Array).size():
				var vs: PackedVector3Array = g["verts"][b]
				var mv := PackedVector3Array()
				for v in vs:
					mv.append(v + (offs[int(lob[b])] as Vector3))
				verts.append(mv)
				var bb: AABB = g["aabb"][b]
				boxes.append(AABB(bb.position + (offs[int(lob[b])] as Vector3), bb.size))
			var cam := {"xf": FrameFacts.look(f["pos"], f["target"]), "fov": f["fov"], "keep_width": cam0["keep_width"], "w": cam0["w"], "h": cam0["h"], "near": 0.01}
			var sil: Dictionary = FrameFacts.measure({"names": g["names"], "verts": verts, "aabb": boxes}, [], cam)["sil"]
			if pass_i == 0:
				var over := maxf(maxf(fr.position.x - float(sil["x0"]), float(sil["x1"]) - fr.end.x), maxf(fr.position.y - float(sil["y0"]), float(sil["y1"]) - fr.end.y))
				worst = maxf(worst, over)
				inside = inside and over <= 2.0
			elif float(sil["x1"]) > fr.end.x + 2.0:
				control_over = true
	ok(inside, tag + " 6 VISIBLE silhouette inside the clear view %s in all %d frames (worst overshoot %.1f px)" % [str(fr), f_vis.size(), worst])
	if tag == "w1280":
		ok(control_over, tag + " 6 CONTROL framed to the whole window the silhouette reaches under the panel")
	xb.cam_check.button_pressed = true
	xb.put_back()
	await idle(3)
	if tag != "w1280":
		return
	# 2 KEYS (real click)
	var ub: int = m.undo.size()
	var np: int = m.S.props.size()
	var anc: Node = xb.get_parent()
	while anc != null and not (anc is ScrollContainer):
		anc = anc.get_parent()
	if anc != null:
		(anc as ScrollContainer).ensure_control_visible(xb.send_btn)
		await idle(3)
	print("SEND visible ", xb.send_btn.is_visible_in_tree(), " rect ", xb.send_btn.get_global_rect())
	await click_ctl(xb.send_btn)
	await idle(6)
	print("SEND said: ", m.ui_status.text, " props ", m.S.props.size())
	if m.S.props.size() == np:
		print("SEND click did not land, direct call: ", xb.send())
	var pi: int = m.S.props.size() - 1
	var p: Dictionary = m.S.props[pi]
	var kd: Dictionary = Props.kind_of(String(p["kind"]))
	var plan: Dictionary = kd["explode_plan"]
	var sched := ExplodeView.schedule(plan, 1.0, 0.4, 0.5)
	var moving := 0
	for u in (plan["units"] as Array).size():
		if float(plan["dist"][u]) > 0.0:
			moving += (plan["units"][u] as Array).size()
	ok(m.S.props.size() == np + 1 and ExplodeKeys.is_kind(String(p["kind"])) and (kd["pjoints"] as Array).size() == moving and m.undo.size() == ub + 1, tag + " 2 KEYS one prop, %d joints (%d moving bodies), %d undo step" % [(kd["pjoints"] as Array).size(), moving, m.undo.size() - ub])
	var tmax := float(sched["total"])
	var tt: Array = []
	for i in 14:
		tt.append(tmax * float(i) / 13.0)
	var worst_mm := 0.0
	var worst_bad := 0.0
	for t in tt:
		var ang := PropJoints.angles_at(p, t)
		for j in kd["pjoints"]:
			var u := int(j["unit"])
			var want := ExplodeView.dist_at(plan, sched, u, t) * 1000.0
			worst_mm = maxf(worst_mm, absf(float(ang[j["name"]]) - want))
			worst_bad = maxf(worst_bad, absf(float(ang[j["name"]]) + 1.0 - want))
	ok(worst_mm <= 1e-4, tag + " 2 KEYS timeline = plan at 14 times, worst %.6f mm" % worst_mm)
	ok(worst_bad > 0.5, tag + " 2 CONTROL a planted +1 mm key is seen (%.3f mm)" % worst_bad)
	ok(m.S.length() >= tmax - 1e-6, tag + " 2 KEYS the scene is %.2f s long, the run %.2f s" % [m.S.length(), tmax])
	# 3 NODES
	var nb: int = (kd["pieces"] as Array).size()
	var worst_n := 0.0
	var rest_boxes: Array = []
	m.playhead = 0.0
	m._props_pose()
	await idle(2)
	var n0 := m.ui_props_root.get_node_or_null("prop_%d" % pi) as Node3D
	rest_boxes = piece_world_boxes(n0, nb)
	var order_t := {}
	for t in tt:
		m.playhead = t
		m._props_pose()
		await idle(2)
		var n := m.ui_props_root.get_node_or_null("prop_%d" % pi) as Node3D
		var bxs := piece_world_boxes(n, nb)
		var offs := ExplodeView.offsets_at(plan, sched, t)
		for u in (plan["units"] as Array).size():
			for bi in plan["units"][u]:
				var d: Vector3 = (bxs[int(bi)] as AABB).position - (rest_boxes[int(bi)] as AABB).position
				worst_n = maxf(worst_n, (d - (offs[u] as Vector3)).length())
				if d.length() > 1e-4 and not order_t.has(u):
					order_t[u] = t
	ok(worst_n <= 0.00002, tag + " 3 NODES piece nodes follow the plan, worst %.5f mm" % (worst_n * 1000.0))
	var scr_first := true
	var plate_u := -1
	for u in (plan["units"] as Array).size():
		if plan["units"][u][0] == 1:
			plate_u = u
	for u in (plan["units"] as Array).size():
		if plan["units"][u][0] >= 2 and plate_u >= 0 and order_t.has(plate_u):
			scr_first = scr_first and order_t.has(u) and order_t[u] <= order_t[plate_u]
	ok(scr_first, tag + " 3 NODES screws start moving before the plate: " + str(order_t))
	# 4 EXPORT
	var out_total := float(sched["out_total"])
	var fps: int = m.S.fps
	m.pv_in = 0.0
	m.pv_out = out_total
	var r: Dictionary = await m._export_playblast("user://s262b_export", "", false)
	m.pv_in = -1.0
	m.pv_out = -1.0
	var nfr := PlayblastExport.frame_count(0.0, out_total, fps)
	ok(int(r.get("frames", 0)) == nfr, tag + " 4 EXPORT %d frames written (want %d)" % [int(r.get("frames", 0)), nfr])
	var pick := [0, nfr / 2, nfr - 1]
	var diffs: Array = []
	var worst_e := 0.0
	var keep_clean: bool = m.clean
	m.clean = true   # the export film has no UI: the same state for the comparison
	m.ui_root.visible = false
	var shot: Dictionary = m._shot_blast_begin()
	for k in pick:
		var t := PlayblastExport.time_of(k, 0.0, out_total, fps)
		var img: Image = await m._blast_frame(shot, t, fps, 0.0, out_total)
		var n := m.ui_props_root.get_node_or_null("prop_%d" % pi) as Node3D
		var bxs := piece_world_boxes(n, nb)
		var offs := ExplodeView.offsets_at(plan, sched, t)
		for u in (plan["units"] as Array).size():
			for bi in plan["units"][u]:
				var d: Vector3 = (bxs[int(bi)] as AABB).position - (rest_boxes[int(bi)] as AABB).position
				worst_e = maxf(worst_e, (d - (offs[u] as Vector3)).length())
		var png := Image.load_from_file("%s/frame_%04d.png" % [r["dir"], k])
		img.convert(Image.FORMAT_RGB8)
		png.convert(Image.FORMAT_RGB8)
		var a := img.get_data()
		var b2 := png.get_data()
		var sum := 0.0
		var cnt := 0
		var i := 0
		while i < a.size():
			sum += absf(float(a[i]) - float(b2[i]))
			cnt += 1
			i += 37
		diffs.append(sum / maxf(cnt, 1))
		DirAccess.make_dir_recursive_absolute(SHOT)
		png.save_png("%s/export_%02d.png" % [SHOT, k])
	m._shot_blast_end(shot)
	m.ui_root.visible = true
	m.clean = keep_clean
	ok(worst_e <= 0.00002, tag + " 4 EXPORT pieces at the export's own frames follow the plan, worst %.5f mm" % (worst_e * 1000.0))
	ok(float(diffs[0]) < 0.5 and float(diffs[1]) < 0.5 and float(diffs[2]) < 0.5, tag + " 4 EXPORT written PNG = the timeline's picture, mean abs diff %s (of 255)" % str(diffs))
	var p0 := Image.load_from_file("%s/frame_%04d.png" % [r["dir"], 0])
	var p1 := Image.load_from_file("%s/frame_%04d.png" % [r["dir"], nfr - 1])
	p0.convert(Image.FORMAT_RGB8)
	p1.convert(Image.FORMAT_RGB8)
	var da := p0.get_data()
	var db := p1.get_data()
	var s2 := 0.0
	var c2 := 0
	var j := 0
	while j < da.size():
		s2 += absf(float(da[j]) - float(db[j]))
		c2 += 1
		j += 37
	ok(s2 / maxf(c2, 1) > 1.0, tag + " 4 CONTROL first and last export frame differ (%.2f of 255)" % (s2 / maxf(c2, 1)))
	# 5 RELOAD
	var d: Dictionary = m.S.to_dict(m.B)
	var js := JSON.stringify(d)
	var kind := String(p["kind"])
	Props.EXTRA.erase(kind)
	var S2 := Scene.new()
	S2.from_dict(JSON.parse_string(js))
	var qi := -1
	for i in S2.props.size():
		if String(S2.props[i]["kind"]) == kind:
			qi = i
	var re_ok := qi >= 0 and Props.has_kind(kind) and (Props.kind_of(kind)["pjoints"] as Array).size() == moving
	var worst_r := 999.0
	if re_ok:
		worst_r = 0.0
		for t in [0.3, out_total * 0.5, out_total]:
			var a1 := PropJoints.angles_at(S2.props[qi], t)
			var a2 := PropJoints.angles_at(p, t)
			for k in a2:
				worst_r = maxf(worst_r, absf(float(a1[k]) - float(a2[k])))
	ok(re_ok and worst_r <= 1e-3, tag + " 5 RELOAD joints %d, keys back, worst %.5f mm" % [(Props.kind_of(kind)["pjoints"] as Array).size() if Props.has_kind(kind) else -1, worst_r])
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png(SHOT + "/timeline_" + tag + ".png")


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	test_limit()
	var ss: StartScreen = m.start_screen
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	await run_at(Vector2i(1280, 720), "w1280")
	await run_at(Vector2i(1024, 600), "w1024")
	await run_at(Vector2i(1920, 1080), "w1920")
	print("s262b: %d fail" % fails)
	quit(1 if fails > 0 else 0)
