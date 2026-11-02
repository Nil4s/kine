extends SceneTree
## S243 FRAMING FACTS FROM THE SILHOUETTE (scripts/build/frame_facts.gd; agent calls frame_facts, frame_to). Needs a real (off-screen) window for the mask renders.
## godot --path . --position 4000,4000 -s tests/s243_test.gd
##   A  a box seen front-on: the silhouette share equals its exact projection (4 f / depth) within 1 px
##   B  a roof with lifted corners: the silhouette share differs from the 3D-box share (> 2 %) and matches a MASK RENDER (a separate pass) within 1 %
##   C  frame_to(width 0.835) hits 83.5 % within 0.5 % by the facts AND by a mask render at the camera it returned; keep fov / height / distance each
##   D  a piece partly outside the frame reports the cut share (asked 150 % of the width: one third of the silhouette box is cut, 25 % of the width each side)
##   E  neither call moves the camera unless asked (apply: false leaves the camera's transform and fov bit for bit)
##   F  a 270-body part (merged surfaces, one look): every body is found by name; a named body's box equals its exact projection within 1 px; the rows of
##      chosen pieces are reported; the time of the render-free path is printed
var fails := 0
var W := 1280
var H := 720


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func box_mesh(sz: Vector3) -> ArrayMesh:
	var bm := BoxMesh.new()
	bm.size = sz
	return ArrayMesh.new() if false else _to_array(bm)


func _to_array(m: Mesh) -> ArrayMesh:
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, m.surface_get_arrays(0))
	return am


## a roof: a ridge, four eave corners lifted, eave middles low, ends curled: nothing like its box
func roof_mesh() -> ArrayMesh:
	var r1 := Vector3(-4, 2, 0)
	var r2 := Vector3(4, 2, 0)
	var ring := [Vector3(-6, 1.5, -4), Vector3(0, 0, -3.5), Vector3(6, 1.5, -4), Vector3(6.5, 0.5, 0), Vector3(6, 1.5, 4), Vector3(0, 0, 3.5), Vector3(-6, 1.5, 4), Vector3(-6.5, 0.5, 0)]
	var vs := PackedVector3Array()
	var ix := PackedInt32Array()
	for v in ring:
		vs.append(v)
	vs.append(r1)
	vs.append(r2)
	for i in 8:
		var a := i
		var b := (i + 1) % 8
		var rr := 8 if i >= 4 and i < 8 or i == 0 and false else 9
		rr = 8 if (i == 5 or i == 6 or i == 7) else 9
		ix.append_array(PackedInt32Array([a, b, rr]))
	ix.append_array(PackedInt32Array([8, 9, 1]))
	ix.append_array(PackedInt32Array([8, 5, 9]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_INDEX] = ix
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am


## MASK RENDER (a separate pass): the pieces drawn flat white on a transparent isolated world; the bbox of the covered pixels
func mask_bbox(meshes: Array, xfs: Array, pos: Vector3, tg: Vector3, fov: float, w: int, h: int) -> Rect2:
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color.WHITE
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in meshes.size():
		var mi := MeshInstance3D.new()
		mi.mesh = meshes[i]
		mi.material_override = mat
		mi.transform = xfs[i]
		vp.add_child(mi)
	var cam := Camera3D.new()
	cam.transform = FrameFacts.look(pos, tg)
	cam.fov = fov
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.far = 5000.0
	vp.add_child(cam)
	cam.current = true
	root.add_child(vp)
	for i in 6:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	root.remove_child(vp)
	vp.queue_free()
	var x0 := 1 << 30
	var y0 := 1 << 30
	var x1 := -1
	var y1 := -1
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				x0 = mini(x0, x)
				x1 = maxi(x1, x + 1)
				y0 = mini(y0, y)
				y1 = maxi(y1, y + 1)
	return Rect2(x0, y0, x1 - x0, y1 - y0)


func make_m() -> Node3D:
	var sc := GDScript.new()
	sc.source_code = "extends Node3D\nvar cam: Camera3D\n"
	sc.reload()
	var m := Node3D.new()
	m.set_script(sc)
	root.add_child(m)
	var c := Camera3D.new()
	m.add_child(c)
	c.current = true
	m.cam = c
	return m


func cam_state(m: Node) -> String:
	return str(m.cam.global_transform) + str(m.cam.fov)


func _init() -> void:
	await process_frame
	root.size = Vector2i(W, H)
	await process_frame
	var m := make_m()
	# ------------------------------------------------------------------ A  box front-on
	var bx := MeshInstance3D.new()
	bx.name = "Block"
	bx.mesh = box_mesh(Vector3(4, 2, 2))
	m.add_child(bx)
	m.cam.global_transform = FrameFacts.look(Vector3(0, 0, 20), Vector3.ZERO)
	m.cam.fov = 45.0
	var ra := FrameFacts.serve(m, {"w": 1024, "h": 1024, "pieces": ["Block"]})
	var f := (512.0) / tan(deg_to_rad(45.0) * 0.5)
	var want_w: float = 4.0 * f / 19.0   # the front face (depth 19) is the widest
	var got_w: float = float(ra["selection"]["bbox_px"][2]) - float(ra["selection"]["bbox_px"][0])
	ok(bool(ra["ok"]) and absf(got_w - want_w) <= 1.0, "A box front-on: silhouette %.2f px, exact projection %.2f px (share %.4f)" % [got_w, want_w, float(ra["selection"]["share_w"])])
	ok(absf(float(ra["scene"]["share_w"]) - float(ra["selection"]["share_w"])) < 1e-6, "A one piece: scene == selection")
	bx.free()
	# ------------------------------------------------------------------ B  lifted roof
	var rf := MeshInstance3D.new()
	rf.name = "Roof"
	rf.mesh = roof_mesh()
	m.add_child(rf)
	var pc := Vector3(14, 6, 18)
	var pt := Vector3(0, 1, 0)
	m.cam.global_transform = FrameFacts.look(pc, pt)
	m.cam.fov = 40.0
	var rb := FrameFacts.serve(m, {"w": W, "h": H, "pieces": ["Roof"]})
	var sel: Dictionary = rb["selection"]
	var mk: Rect2 = await mask_bbox([rf.mesh], [rf.transform], pc, pt, 40.0, W, H)
	var mk_share := mk.size.x / W
	print("     roof: silhouette share %.4f  3D-box share %.4f  mask render %.4f   rows %d..%d" % [float(sel["share_w"]), float(sel["bbox_share_w"]), mk_share, int(sel["top_row"]), int(sel["bottom_row"])])
	ok(absf(float(sel["share_w"]) - float(sel["bbox_share_w"])) > 0.02, "B silhouette share differs from the box share by %.1f %% of the width" % (100.0 * absf(float(sel["share_w"]) - float(sel["bbox_share_w"]))))
	ok(absf(float(sel["share_w"]) - mk_share) <= 0.01 and absf(float(sel["share_h"]) - mk.size.y / H) <= 0.01, "B silhouette matches the mask render within 1 %% (w %.4f vs %.4f, h %.4f vs %.4f)" % [float(sel["share_w"]), mk_share, float(sel["share_h"]), mk.size.y / H])
	ok(absi(int(sel["top_row"]) - int(mk.position.y)) <= 1 and absi(int(sel["bottom_row"]) - int(mk.end.y)) <= 1, "B top / bottom rows %d / %d match the mask %d / %d within 1 row" % [int(sel["top_row"]), int(sel["bottom_row"]), int(mk.position.y), int(mk.end.y)])
	# ------------------------------------------------------------------ E before C: the camera is not moved
	var before := cam_state(m)
	var rc := FrameFacts.serve_to(m, {"w": W, "h": H, "pieces": ["Roof"], "width_share": 0.835})
	FrameFacts.serve(m, {"w": W, "h": H})
	ok(cam_state(m) == before and not bool(rc["applied"]), "E frame_to / frame_facts leave the user's camera exactly as it was (apply false)")
	# ------------------------------------------------------------------ C  frame_to
	for keep in ["fov", "height", "distance"]:
		var r2 := FrameFacts.serve_to(m, {"w": W, "h": H, "pieces": ["Roof"], "width_share": 0.835, "keep": keep})
		if not bool(r2["ok"]):
			ok(false, "C keep %s: %s" % [keep, str(r2.get("error"))])
			continue
		var cp: Array = r2["camera"]["pos"]
		var ct: Array = r2["camera"]["target"]
		var cpos := Vector3(cp[0], cp[1], cp[2])
		var ctg := Vector3(ct[0], ct[1], ct[2])
		var cfov := float(r2["camera"]["fov"])
		var mk2: Rect2 = await mask_bbox([rf.mesh], [rf.transform], cpos, ctg, cfov, W, H)
		var okh: bool = true
		if keep == "height":
			okh = absf(cpos.y - pc.y) < 1e-3 and absf(ctg.y - pt.y) < 1e-3
		elif keep == "distance":
			okh = absf(cpos.distance_to(Vector3(0, 1, 0)) - pc.distance_to(Vector3(0, 1, 0))) < 0.03 * pc.distance_to(Vector3(0, 1, 0))
		else:
			okh = absf(cfov - 40.0) < 1e-3
		print("     frame_to keep %s: asked 0.835 got %.4f (facts), mask %.4f, centre offset %s px, %d iterations" % [keep, float(r2["facts"]["share_w"]), mk2.size.x / W, str(r2["facts"]["centre_offset_px"]), int(r2["iterations"])])
		ok(absf(float(r2["facts"]["share_w"]) - 0.835) <= 0.005 and absf(mk2.size.x / W - 0.835) <= 0.005 and okh, "C frame_to keep %s: 83.5 %% within 0.5 %% by facts and by the mask render, kept what it says" % keep)
	var rr := FrameFacts.serve_to(m, {"w": W, "h": H, "pieces": ["Roof"], "rows": {"top": 100, "bottom": 600}})
	ok(bool(rr["ok"]) and absi(int(rr["facts"]["top_row"]) - 100) <= 1 and absi(int(rr["facts"]["bottom_row"]) - 600) <= 1, "C rows 100..600 asked: got %s..%s" % [str(rr["facts"].get("top_row")), str(rr["facts"].get("bottom_row"))])
	var rerr := FrameFacts.serve_to(m, {"w": W, "h": H, "pieces": ["Nothing*"], "width_share": 0.5})
	ok(not bool(rerr["ok"]), "C an unknown piece is an error naming the problem: %s" % str(rerr.get("error")))
	# ------------------------------------------------------------------ D  cut share
	var rd := FrameFacts.serve_to(m, {"w": W, "h": H, "pieces": ["Roof"], "width_share": 1.5, "center": "xy"})
	var cut: Dictionary = rd["facts"]["cut"]
	var sh := FrameFacts.serve(m, {"w": W, "h": H, "pieces": ["Roof"], "camera": rd["camera"]})
	var cs: Dictionary = sh["selection"]["cut"]
	ok(absf(float(cs["share"]) - 1.0 / 3.0) < 0.01 and absf(float(cs["left_px"]) - 0.25 * W) < 0.01 * W and absf(float(cs["right_px"]) - 0.25 * W) < 0.01 * W and float(sh["selection"]["visible_share_w"]) > 0.999, "D 150 %% wide: cut share %.4f (1/3), %.0f px off each side (%.0f), visible width %.3f" % [float(cs["share"]), float(cs["left_px"]), 0.25 * W, float(sh["selection"]["visible_share_w"])])
	ok(float(cut["share"]) > 0.3, "D frame_to's own facts say the same cut (%.4f)" % float(cut["share"]))
	# ------------------------------------------------------------------ F  270 bodies
	if not Part.available():
		print("FAIL no DLL")
		fails += 1
	else:
		var rec := Part.make("big")
		for k in 270:
			Part.prim(rec, "box", {"x": (k % 17) * 30.0, "y": 0.0, "z": (k / 17) * 30.0, "w": 20.0, "h": 20.0 + (k % 5) * 4.0, "d": 20.0, "name": "B%d" % k})
		var res := Part.replay(rec)
		var pm := MeshInstance3D.new()
		pm.mesh = res["mesh"]
		m.add_child(pm)
		var surfs: int = pm.mesh.get_surface_count()
		var t0 := Time.get_ticks_usec()
		var g := FrameFacts.gather_part(pm, res)
		var t1 := Time.get_ticks_usec()
		var cam := {"xf": FrameFacts.look(Vector3(0.25, 3.0, 12.0), Vector3(0.25, 0.1, 0.1)), "fov": 45.0, "keep_width": false, "w": W, "h": H, "near": 0.05}
		var fs := FrameFacts.scene_facts(g, [], cam)
		var t2 := Time.get_ticks_usec()
		var idx := FrameFacts.select(g, ["B1", "B2*"])
		var fp := FrameFacts.scene_facts(g, idx, cam)
		var t3 := Time.get_ticks_usec()
		var names: Array = g["names"]
		ok(names.size() == 270 and surfs <= 256 and names.has("B269") and names.has("B0"), "F %d bodies found by name from %d surfaces (merged by look)" % [names.size(), surfs])
		# B100: a 20 x (20 + 0 * 4) x 20 box at x 10 * 30 = 300 mm, z 5 * 30 = 150 mm... its silhouette equals the exact projection of its own 8 corners
		var i100: int = names.find("B100")
		var bb: AABB = g["aabb"][i100]
		var inv: Transform3D = (cam["xf"] as Transform3D).affine_inverse()
		var fl := (H * 0.5) / tan(deg_to_rad(45.0) * 0.5)
		var ex0 := INF
		var ex1 := -INF
		var ey0 := INF
		var ey1 := -INF
		for k in 8:
			var c: Vector3 = inv * (bb.position + Vector3(bb.size.x * (k & 1), bb.size.y * ((k >> 1) & 1), bb.size.z * ((k >> 2) & 1)))
			var px := W * 0.5 + c.x * fl / -c.z
			var py := H * 0.5 - c.y * fl / -c.z
			ex0 = minf(ex0, px)
			ex1 = maxf(ex1, px)
			ey0 = minf(ey0, py)
			ey1 = maxf(ey1, py)
		var f100 := FrameFacts.scene_facts(g, [i100], cam)
		var b100: Array = f100["bbox_px"]
		ok(absf(float(b100[0]) - ex0) <= 1.0 and absf(float(b100[2]) - ex1) <= 1.0 and absf(float(b100[3]) - ey1) <= 1.0, "F B100's silhouette x %.1f..%.1f, bottom %.1f; exact box corners %.1f..%.1f, %.1f; the box is 20 mm = %.3f m wide" % [float(b100[0]), float(b100[2]), float(b100[3]), ex0, ex1, ey1, bb.size.x])
		ok(bb.size.x > 0.015 and bb.size.x < 0.025 and int(f100["bottom_row"]) == int(round(ey1)), "F B100 bottom row %d (\"bases at row %d\")" % [int(f100["bottom_row"]), int(round(ey1))])
		print("     270 bodies: gather %.1f ms, whole scene facts %.1f ms, 2 chosen pieces (%d) %.1f ms; scene share_w %.4f rows %d..%d" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, idx.size(), (t3 - t2) / 1000.0, float(fs["share_w"]), int(fs["top_row"]), int(fs["bottom_row"])])
		ok((t2 - t1) / 1000.0 < 1000.0 and (t3 - t0) / 1000.0 < 3000.0, "F render-free path: gather %.0f ms + whole scene %.0f ms (270 bodies, %d vertices)" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0, _nv(g)])
		Part.release_kept(res.get("ids", []))
	print("s243: %d fail%s" % [fails, "" if fails == 1 else "s"])
	quit(1 if fails > 0 else 0)


func _nv(g: Dictionary) -> int:
	var n := 0
	for v in g["verts"]:
		n += (v as PackedVector3Array).size()
	return n
