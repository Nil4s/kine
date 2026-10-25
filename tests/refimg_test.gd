## godot --path . -s tests/refimg_test.gd     (ROADMAP_400 C25 + B21, windowed: reference images and "Match: fit the body to the reference")
## The reference is the body itself, rendered from a DIFFERENT camera (farther, shifted) to a PNG in user://: a perfect
## reference whose landmarks are known (the body's joints projected by the camera that rendered it). Bars, stated before measuring:
##   1 BLEND: a solid red picture as the camera overlay at opacity 0.5 reads 0.5 * red + 0.5 * what was under it (each channel
##     within 0.02), and 1.0 reads red, 0.0 reads what was under it (within 0.02)
##   2 FIT: the self-render, mis-placed on purpose (scale 0.6, shifted), is fitted by Match through the REAL runner path (a stub
##     tracker run as python -I, polled) from its landmarks: the mean residual (the picture's landmarks vs the body's joints
##     as the current camera sees them) < 10 px, measured here independently of the fit's own report; the same by the 2-point
##     fallback (head top + heel clicked on the picture) < 10 px; with no interpreter the fit asks for the 2 clicks (says so)
##   3 PLANES: front = a plane behind the body with normal +z (toward the Front camera, which sees its face), side = normal -x
##     (toward His right camera), behind every joint, BACK / SIDE_BACK m from the centre line (the side one clears the arms-out hands); free at yaw 30 = normal (sin30, 0, cos30)
##   4 FILE: the entry round-trips through the scene file form (to_dict -> JSON -> from_dict) field for field; the path is stored
##     relative to the scene file's folder and resolves back to the picture; each change is one undo step and Ctrl+Z restores;
##     scenes/ holds the same files after the test as before
##   5 PLACEMENT: a reference of the body with one arm raised, matched, is drawn over the body in the whole-body view: the
##     overlay's head and hips land within 10 px of the body's, and the overlay covers the body's whole box (screenshot)
## Shot: C:/Users/Nick/.claude/jobs/9afc22db/tmp/refimg.png
extends SceneTree

const DIR := "user://refimg_test"
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/refimg.png"
var fails := 0
var m: Node
var win := Vector2.ZERO


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func scenes_listing() -> String:
	var out := []
	for d in ["res://scenes", "res://scenes/_wip"]:
		var da := DirAccess.open(d)
		if da == null:
			continue
		var fs := Array(da.get_files())
		fs.sort()
		for f in fs:
			out.append("%s/%s:%d" % [d, f, FileAccess.get_modified_time(d + "/" + f)])
	return "\n".join(out)


func set_cam(y: float, p: float, d: float, t: Vector3) -> void:
	m.yaw = y
	m.pitch = p
	m.dist = d
	m.target = t
	m._cam()


## the 3D view alone (UI hidden; the reference layer stays: it is its own canvas layer)
func shot() -> Image:
	m.ui_root.visible = false
	await idle(6)
	var img := root.get_texture().get_image()
	m.ui_root.visible = true
	await idle(2)
	return img


func points_uv() -> Array:
	var bp: Dictionary = RefImage.body_points(m.B)
	var lms := []
	for k in 33:
		if bp.has(k):
			var s: Vector2 = m.cam.unproject_position(bp[k])
			lms.append([s.x / win.x, s.y / win.y, 1.0])
		else:
			lms.append([0.0, 0.0, 0.0])
	return lms


func write_png_and_landmarks(name: String, img: Image, lms: Array) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var p := ProjectSettings.globalize_path(DIR + "/" + name)
	img.save_png(p)
	var f := FileAccess.open(p + ".lm.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"size": [img.get_width(), img.get_height()], "image": lms}))
	f.close()
	return p


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var before := scenes_listing()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	win = root.get_visible_rect().size
	m.S.refimgs = []
	m.undo.clear()
	m.redo.clear()
	m.refimg.python = "python"
	m.refimg.tool = "res://tests/fixtures/ri_stub.py"
	# the reference render: the standing body from a farther, shifted camera
	for j in Body.BODY:
		m.B.ang[j] = Vector3.ZERO
	m.B.fk()
	m._refresh()
	set_cam(0.0, -8.0, 6.0, Vector3(0.4, 1.1, 0.0))
	await idle(4)
	var ref_img: Image = await shot()
	var ref_lms := points_uv()
	var ref_path := write_png_and_landmarks("self.png", ref_img, ref_lms)
	# the arm-up variant reference (bar 5)
	m.B.ang["upperarm_r"] = Vector3(0.0, 0.0, 60.0)
	m.B.ang["lowerarm_r"] = Vector3(40.0, 0.0, 0.0)
	m.B.fk()
	m._refresh()
	await idle(4)
	var var_img: Image = await shot()
	var var_lms := points_uv()
	var var_path := write_png_and_landmarks("armup.png", var_img, var_lms)
	for j in Body.BODY:
		m.B.ang[j] = Vector3.ZERO
	m.B.fk()
	m._refresh()
	# the app's view: home camera (nearer), the standing body
	set_cam(0.0, -8.0, 4.0, Vector3(0, 0.95, 0))
	await idle(4)
	var view: Rect2 = m.refimg.view_rect()

	# ---- 1 blend
	var red := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	red.fill(Color(1, 0, 0, 1))
	var red_path := ProjectSettings.globalize_path(DIR + "/red.png")
	red.save_png(red_path)
	var spot := Vector2i(int(view.get_center().x - 0.4 * view.size.y), int(view.get_center().y - 0.3 * view.size.y))
	var under: Color = (await shot()).get_pixelv(spot)
	ok(m.refimg.load_path(red_path), "1 loads a PNG as a camera overlay")
	var e0: Dictionary = m.S.refimgs[0]
	ok(e0["mode"] == "camera" and absf(float(e0["opacity"]) - 0.5) < 1e-6, "  default: camera overlay at opacity 0.5")
	await idle(3)
	var half: Color = (await shot()).get_pixelv(spot)
	m.refimg.set_fields({"opacity": 1.0})
	var full: Color = (await shot()).get_pixelv(spot)
	m.refimg.set_fields({"opacity": 0.0})
	var none: Color = (await shot()).get_pixelv(spot)
	var want := under * 0.5 + Color(1, 0, 0, 1) * 0.5
	var e_half := maxf(absf(half.r - want.r), maxf(absf(half.g - want.g), absf(half.b - want.b)))
	var e_full := maxf(absf(full.r - 1.0), maxf(absf(full.g), absf(full.b)))
	var e_none := maxf(absf(none.r - under.r), maxf(absf(none.g - under.g), absf(none.b - under.b)))
	print("     under %s half %s want %s full %s none %s" % [under, half, want, full, none])
	ok(e_half < 0.02 and e_full < 0.02 and e_none < 0.02, "1 pixel blend: 0.5 off by %.4f, 1.0 off by %.4f, 0.0 off by %.4f (< 0.02)" % [e_half, e_full, e_none])
	m.refimg.remove()
	await idle(2)
	ok(m.refimg.node_of(0) == null and m.S.refimgs.is_empty(), "  removing it takes the picture off the view")

	# ---- 2 fit
	ok(m.refimg.load_path(ref_path), "2 loads the self-render reference")
	m.refimg.set_fields({"scale": 0.6, "offset": [0.12, -0.07]})
	await idle(2)
	var lms_ref: Array = ref_lms
	var e: Dictionary = m.S.refimgs[0]
	var res0 := RefImage.residual_px(m.B, lms_ref, m.refimg.size_of(0), e, view, func(p): return m.cam.unproject_position(p))
	var n_undo: int = m.undo.size()
	m.refimg.match_body()
	var t := 0.0
	while m.refimg._pid >= 0 and t < 20.0:
		await process_frame
		t += 0.016
	await idle(2)
	e = m.S.refimgs[0]
	var res1 := RefImage.residual_px(m.B, lms_ref, m.refimg.size_of(0), e, view, func(p): return m.cam.unproject_position(p))
	print("     residual before %.1f px, after %.2f px (the fit reports %.2f over %d points); scale %.3f offset %s" % [res0, res1, float(m.refimg.last.get("res_px", -1)), int(m.refimg.last.get("n", 0)), float(e["scale"]), e["offset"]])
	ok(m.refimg.last.get("method", "") == "detector" and res1 < 10.0 and res0 > 30.0, "2 Match through the tracker runner: residual %.1f -> %.2f px (< 10)" % [res0, res1])
	ok(m.undo.size() == n_undo + 1, "  Match is one undo step (%d -> %d)" % [n_undo, m.undo.size()])
	m._undo()
	ok(absf(float(m.S.refimgs[0]["scale"]) - 0.6) < 1e-6, "  Ctrl+Z puts the scale back (0.6)")
	# the 2-point fallback: clicks at the picture's head top and heel, on the mis-placed layout
	e = m.S.refimgs[0]
	var sz: Vector2 = m.refimg.size_of(0)
	var r: Rect2 = RefImage.layout(view, sz, e)
	var head_w: Vector3 = m.B.E["head"]
	var heel_w: Vector3 = VideoImport.heel(m.B, "_l")
	var hr: Vector3 = VideoImport.heel(m.B, "_r")
	if hr.y < heel_w.y:
		heel_w = hr
	# those two body points as the REFERENCE camera saw them: the picture's own pixels (known head / heel positions)
	set_cam(0.0, -8.0, 6.0, Vector3(0.4, 1.1, 0.0))
	var ph: Vector2 = m.cam.unproject_position(head_w) / win
	var pf: Vector2 = m.cam.unproject_position(heel_w) / win
	set_cam(0.0, -8.0, 4.0, Vector3(0, 0.95, 0))
	await idle(2)
	var c0 := r.position + ph * r.size
	var c1 := r.position + pf * r.size
	var f2: Dictionary = m.refimg.apply_two_point(c0, c1)
	await idle(2)
	e = m.S.refimgs[0]
	var res2 := RefImage.residual_px(m.B, lms_ref, sz, e, view, func(p): return m.cam.unproject_position(p))
	ok(f2.get("ok", false) and res2 < 10.0, "2 two-point fallback (head top + heel): residual over all joints %.2f px (< 10), reported %.2f" % [res2, float(f2.get("res_px", -1))])
	m._undo()
	m.refimg.python = "no_such_python_zz"
	m.refimg.match_body()
	ok(m.refimg.picking == 1, "2 with no detector the fit asks for the two clicks (picking %d)" % m.refimg.picking)
	m.refimg._end_pick()
	m.refimg.python = "python"
	# information only: the real MediaPipe on the mannequin render
	m.refimg.tool = "res://tools/see_image.py"
	m.refimg.match_body()
	t = 0.0
	while m.refimg._pid >= 0 and t < 40.0:
		await process_frame
		t += 0.016
	await idle(2)
	print("     (info, no bar) the real detector on the mannequin render: picking %d, last %s" % [m.refimg.picking, m.refimg.last])
	m.refimg._end_pick()
	m.refimg.tool = "res://tests/fixtures/ri_stub.py"

	# ---- 3 planes
	m.refimg.set_fields({"mode": "front", "scale": 1.0, "offset": [0.0, 0.0]})
	await idle(3)
	var pl := m.refimg.node_of(0) as Node3D
	var bp: Dictionary = RefImage.body_points(m.B)
	var zmin := 1e9
	var xmax := -1e9
	var xmin := 1e9
	for k in bp:
		zmin = minf(zmin, (bp[k] as Vector3).z)
		xmax = maxf(xmax, (bp[k] as Vector3).x)
		xmin = minf(xmin, (bp[k] as Vector3).x)
	var n: Vector3 = pl.global_transform.basis.z
	var front_cam_dir: Vector3 = (m.cam.global_position - pl.global_position)
	ok(pl is MeshInstance3D and n.distance_to(Vector3(0, 0, 1)) < 1e-4 and pl.global_position.z < zmin - 0.05 and absf(pl.global_position.z + RefImage.BACK) < 1e-4 and front_cam_dir.dot(n) > 0.0,
		"3 front plane: normal %s, z %.2f behind the body (nearest joint z %.2f), the Front camera sees its face" % [n, pl.global_position.z, zmin])
	m.refimg.set_fields({"mode": "side"})
	await idle(3)
	pl = m.refimg.node_of(0) as Node3D
	n = pl.global_transform.basis.z
	ok(n.distance_to(Vector3(-1, 0, 0)) < 1e-4 and pl.global_position.x > xmax + 0.05 and absf(pl.global_position.x - RefImage.SIDE_BACK) < 1e-4,
		"3 side plane: normal %s (toward His right camera), x %.2f behind the body (farthest joint x %.2f)" % [n, pl.global_position.x, xmax])
	m.refimg.set_fields({"mode": "free", "yaw": 30.0, "pos": [0.2, 1.0, -0.8]})
	await idle(3)
	pl = m.refimg.node_of(0) as Node3D
	n = pl.global_transform.basis.z
	ok(n.distance_to(Vector3(sin(deg_to_rad(30.0)), 0, cos(deg_to_rad(30.0)))) < 1e-4 and pl.global_position.distance_to(Vector3(0.2, 1.0, -0.8)) < 1e-4,
		"3 free plane at yaw 30: normal %s, centre %s" % [n, pl.global_position])
	# a world plane's size: BASE_H x scale tall
	var qs: Vector2 = ((pl as MeshInstance3D).mesh as QuadMesh).size
	ok(absf(qs.y - RefImage.BASE_H) < 1e-4 and absf(qs.x / qs.y - sz.x / sz.y) < 1e-4, "  the plane is %.2f m tall with the picture's aspect" % qs.y)

	# ---- 4 file
	m.refimg.set_fields({"mode": "camera", "opacity": 0.35, "scale": 1.7, "offset": [0.1, -0.2], "flip": true})
	m.scene_path = "res://scenes/_wip/zz_refimg_never_saved.json"   # only a name: nothing is written
	var d: Dictionary = m.S.to_dict(m.B)
	var js: Dictionary = JSON.parse_string(JSON.stringify(d))
	var S2 := Scene.new()
	S2.from_dict(js)
	var a: String = JSON.stringify(m.S.refimgs[0], "", true)
	var b: String = JSON.stringify(S2.refimgs[0], "", true) if S2.refimgs.size() == 1 else "none"
	ok(js.has("refimgs") and a == b, "4 the entry round-trips through the scene file (%d entries, opacity %.2f scale %.2f flip %s)" % [S2.refimgs.size(), S2.refimgs[0]["opacity"] if S2.refimgs.size() > 0 else -1.0, S2.refimgs[0]["scale"] if S2.refimgs.size() > 0 else -1.0, S2.refimgs[0]["flip"] if S2.refimgs.size() > 0 else "-"])
	var sdir: String = ProjectSettings.globalize_path("res://scenes/_wip")
	var rel := RefImage.store_path(ref_path, sdir)
	var back := RefImage.resolve(rel, sdir)
	print("     stored path: %s  -> resolves to %s" % [rel, back])
	ok(not rel.is_absolute_path() and back.to_lower() == ref_path.replace("\\", "/").to_lower(), "4 the path is stored relative to the scene folder and resolves back to the picture")
	m.refimg.remove()
	var u0: int = m.undo.size()
	ok(m.refimg.load_path(ref_path), "4 load again with a scene open")
	ok(not String(m.S.refimgs[0]["path"]).is_absolute_path() and m.undo.size() == u0 + 1, "4 the loaded entry holds a relative path (%s) and is one undo step" % m.S.refimgs[0]["path"])
	await idle(2)
	ok(m.refimg.node_of(0) != null, "4 the relative path resolves to a drawn picture")
	m._undo()
	await idle(2)
	ok(m.S.refimgs.is_empty() and m.refimg.node_of(0) == null, "4 Ctrl+Z takes the picture off")
	m.scene_path = ""
	ok(scenes_listing() == before, "4 scenes/ holds the same files, same times, after the test")

	# ---- 5 placement
	m.refimg.python = "python"
	ok(m.refimg.load_path(var_path), "5 loads the arm-up reference")
	m.refimg.set_fields({"scale": 0.7, "offset": [-0.1, 0.1]})
	m.refimg.match_body()
	t = 0.0
	while m.refimg._pid >= 0 and t < 20.0:
		await process_frame
		t += 0.016
	await idle(4)
	e = m.S.refimgs[0]
	sz = m.refimg.size_of(0)
	r = RefImage.layout(view, sz, e)
	var bpn: Dictionary = RefImage.body_points(m.B)
	var d_head: float = (r.position + Vector2(var_lms[0][0], var_lms[0][1]) * r.size).distance_to(m.cam.unproject_position(bpn[0]))
	var hip_o: Vector2 = (r.position + Vector2(var_lms[23][0], var_lms[23][1]) * r.size + r.position + Vector2(var_lms[24][0], var_lms[24][1]) * r.size) * 0.5
	var hip_b: Vector2 = (m.cam.unproject_position(bpn[23]) + m.cam.unproject_position(bpn[24])) * 0.5
	var box := Rect2(m.cam.unproject_position(bpn[0]), Vector2.ZERO)
	for k in bpn:
		box = box.expand(m.cam.unproject_position(bpn[k]))
	var lo: Vector2 = m.cam.unproject_position(VideoImport.heel(m.B, "_l"))
	box = box.expand(lo)
	print("     head off by %.1f px, hips off by %.1f px; overlay %s, body box %s; Match said %s" % [d_head, hip_o.distance_to(hip_b), r, box, m.refimg.last])
	ok(d_head < 10.0 and hip_o.distance_to(hip_b) < 10.0 and r.encloses(box), "5 the overlay is drawn over the body: head %.1f px, hips %.1f px off; the picture covers the body's box" % [d_head, hip_o.distance_to(hip_b)])
	ok(m.refimg.node_of(0) is TextureRect and (m.refimg.node_of(0) as TextureRect).modulate.a == 0.5, "5 drawn as a half-opaque layer under the panels")
	# the screenshot: the whole window, panels on, the panel closed
	m.refimg.open_panel()
	await idle(4)
	var panel_ok: bool = m.refimg.win != null and m.refimg.win.visible and absf((m.refimg._ctl["opacity"] as HSlider).value - 0.5) < 1e-6
	ok(panel_ok, "  the reference panel opens and shows opacity 0.5")
	m.refimg.win.hide()
	await idle(8)
	var snap: Image = root.get_texture().get_image()
	snap.save_png(SHOT)
	print("     shot %s (%dx%d)" % [SHOT, snap.get_width(), snap.get_height()])
	print("REFIMG %s (%d fail)" % ["FAIL" if fails > 0 else "PASS", fails])
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
