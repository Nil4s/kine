## godot --path . -s tests/shot_camera_test.gd     (GATES SC1-SC3; needs a window: it renders)
## THE SHOT CAMERA (scripts/shot_camera.gd, main.gd _shot_*). A 3-card built-in scene (24 fps) with 3 camera keys
## (50, 35, 85 mm). Nothing is written outside user:// (never scenes/, poses/, data/).
##   1 lens + maths: fov_v(50 mm) = 2 atan(36 / (16/9) / 2 / 50) within 0.01 deg, and the RENDERED frame's vertical angle
##     (points on rays +-fov_v/2 off the axis land on the frame's edges, unproject_position) within 0.01 deg; 96 world points
##     projected by the pinhole formula land where Camera3D.unproject_position says within 0.5 px (look-through with the
##     panels shown: an off-centre frame); between keys the camera's rendered position = the PCHIP formula written here
##     (Fritsch-Butland slopes, flat ends) within 1 mm at 10 times, its aim direction within 0.01 deg
##   2 look-through (clean): the frame's pixels = a reference render by a separate Camera3D set from the formula: 0 px differ
##   3 playblast through the camera: 16:9 frames of the frame's size; frames 0 / mid / last = look-through at their
##     times, 0 px differ; the picture moves
##   4 file round trip, schema, mirror (x negated, twice = original), each command one undo step, refusals
##   5 a scene with no camera: the playblast is the full viewport and equals the viewport scrubbed by hand (as PL0)
extends SceneTree

var fails := 0
var m: Node
var run_id := OS.get_process_id()


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func grab() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()


func ndiff(a: Image, b: Image) -> int:
	if a.get_size() != b.get_size():
		return -1
	var da := a.get_data()
	var db := b.get_data()
	if da == db:
		return 0
	var n := 0
	for i in range(0, da.size(), 3 if a.get_format() == Image.FORMAT_RGB8 else 4):
		if da[i] != db[i] or da[i + 1] != db[i + 1] or da[i + 2] != db[i + 2]:
			n += 1
	return n


func pose(thigh: float, arm: float) -> Dictionary:
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	R.set_ang("thigh_l", Vector3(thigh, 0, 0))
	R.set_ang("upperarm_r", Vector3(0, 0, arm))
	R.fk()
	return R.to_dict()


## the PCHIP the scene's keys follow, written out here (not PartKeys): slopes 0 at the ends, inside the weighted harmonic
## mean of the two secants (w1 = 2 h_r + h_l, w2 = h_r + 2 h_l), 0 where the value turns back; per component
func pchip(ts: Array, vs: Array, t: float) -> Vector3:
	if t <= ts[0]:
		return vs[0]
	if t >= ts[-1]:
		return vs[-1]
	var n := ts.size()
	var m_ := []
	for k in n:
		var s := Vector3.ZERO
		if k > 0 and k < n - 1:
			var hl: float = ts[k] - ts[k - 1]
			var hr: float = ts[k + 1] - ts[k]
			var dl: Vector3 = (vs[k] - vs[k - 1]) / hl
			var dr: Vector3 = (vs[k + 1] - vs[k]) / hr
			for c in 3:
				if dl[c] * dr[c] > 0.0:
					var w1 := 2.0 * hr + hl
					var w2 := hr + 2.0 * hl
					s[c] = (w1 + w2) / (w1 / dl[c] + w2 / dr[c])
		m_.append(s)
	var i := 0
	while t >= ts[i + 1]:
		i += 1
	var h: float = ts[i + 1] - ts[i]
	var u: float = (t - ts[i]) / h
	var u2 := u * u
	var u3 := u2 * u
	return (2 * u3 - 3 * u2 + 1) * vs[i] + (u3 - 2 * u2 + u) * h * m_[i] + (-2 * u3 + 3 * u2) * vs[i + 1] + (u3 - u2) * h * m_[i + 1]


func look(t: float) -> void:
	m.playhead = t
	m._ps().apply(m.B, t)
	m._refresh()
	m._shot_apply()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var S := Scene.new()
	S.name = "zz_shot_camera"
	S.fps = 24
	var poses := [pose(0, 0), pose(70, 80), pose(-25, -40)]
	for i in 3:
		S.add("c%d" % i, poses[i])
		S.cards[i]["move"] = 0.4
		S.cards[i]["hold"] = 0.1 if i < 2 else 0.0
	m.S = S
	m._rebuild_cards()
	m.sel_card = 0
	m.playhead = 0.0
	m._refresh()
	await idle(3)
	var L := S.length()
	var KT := [0.0, 0.5, L]
	var KP := [Vector3(2.8, 1.3, -1.2), Vector3(3.0, 1.1, 0.6), Vector3(-2.6, 1.6, -1.5)]
	var KA := [Vector3(0, 1.0, 0), Vector3(0.1, 0.9, 0.05), Vector3(0, 1.2, -0.1)]
	var KF := [50.0, 35.0, 85.0]
	var vs: Vector2 = root.get_viewport().get_visible_rect().size

	# 4 (refusals first, on the scene with no camera)
	m.playhead = 0.0
	m._shot_toggle()
	ok(not m.shot_through and String(m.ui_status.text).contains("use"), "4 look-through with no camera is refused and says what to use: %s" % String(m.ui_status.text).left(90))
	m._shot_lens(85.0)
	ok(S.camera.is_empty() and String(m.ui_status.text).contains("first"), "  a lens with no camera is refused: %s" % String(m.ui_status.text).left(90))

	# 5 no camera: the playblast is as before
	var base := "user://zz_sc_%d" % run_id
	var r0: Dictionary = await m._export_playblast(base + "_none", "")
	var d0: String = r0.get("dir", "")
	var mid0 := int(r0.get("frames", 2)) / 2
	var i0 := Image.load_from_file("%s/frame_%04d.png" % [d0, mid0])
	m.clean = true
	m._sides_apply()
	m.ui_root.visible = false
	m.playhead = float(mid0) / S.fps
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	var hand := await grab()
	m.ui_root.visible = true
	m.clean = false
	m._sides_apply()
	ok(i0 != null and Vector2(i0.get_size()) == vs and ndiff(i0, hand) == 0, "5 no camera: the playblast frame is the viewport's size %s and equals the view scrubbed by hand (%d px differ)" % [i0.get_size() if i0 else Vector2i(), ndiff(i0, hand) if i0 else -1])
	ok(m.cam.projection == Camera3D.PROJECTION_PERSPECTIVE and absf(m.cam.fov - 40.0) < 1e-6, "  the view camera is untouched: perspective, fov %.1f" % m.cam.fov)

	# 4 key from the view: one undo step
	m.playhead = 0.0
	m._refresh()
	var u0: int = m.undo.size()
	m._shot_key_view()
	ok(S.camera.size() == 1 and m.undo.size() == u0 + 1, "4 key the shot camera from the view: 1 key, %d undo step" % (m.undo.size() - u0))
	var vk: Dictionary = S.camera[0]
	ok((vk["aim"] as Vector3).distance_to(m.target) < 1e-6 and (vk["pos"] as Vector3).distance_to(m.cam.get_camera_transform().origin) < 1e-6,
		"  the key is the view: lens at the view's origin, aimed at its pivot, %.1f mm" % float(vk["f"]))
	m._undo()
	ok(S.camera.is_empty(), "  one Ctrl+Z takes it back (keys %d)" % S.camera.size())
	# the test's keys (the commands make them the same way: ShotCam.put)
	for i in 3:
		ShotCam.put(S.camera, {"t": KT[i], "pos": KP[i], "aim": KA[i], "f": KF[i]})

	# 1 the lens
	var want_v := rad_to_deg(2.0 * atan((36.0 / (16.0 / 9.0)) / 2.0 / 50.0))
	print("     fov_v(50 mm) = %.4f deg (formula 2 atan(20.25 / 2 / 50) = %.4f), fov_h = %.4f deg" % [ShotCam.fov_v(50.0), want_v, ShotCam.fov_h(50.0)])
	ok(absf(ShotCam.fov_v(50.0) - want_v) < 0.01 and absf(ShotCam.fov_h(50.0) - 39.5978) < 0.01, "1 fov from 50 mm on a 36 mm sensor, 16:9: %.4f deg vertical (want %.4f), %.4f horizontal (want 39.5978)" % [ShotCam.fov_v(50.0), want_v, ShotCam.fov_h(50.0)])
	m._shot_toggle()
	ok(m.shot_through, "  look-through on")
	await idle(2)
	var worst_fov := 0.0
	var worst_px := 0.0
	var npts := 0
	for t in [0.0, 0.5, L, 0.27]:
		look(t)
		await idle(1)
		var r: Rect2i = m.shot_rect()
		var k := ShotCam.sample(S.camera, t)
		var cx := r.position.x + r.size.x * 0.5
		# two points on rays turned +-fov_v/2 about the camera's x axis from its axis must land on the frame's top and
		# bottom edge (Camera3D.unproject_position: the projection the render uses); the miss in px as degrees
		var X: Transform3D = ShotCam.xf(k["pos"], k["aim"])
		var hv := deg_to_rad(ShotCam.fov_v(k["f"]) * 0.5)
		var up_p: Vector3 = X * (Basis(Vector3.RIGHT, hv) * Vector3(0, 0, -3))
		var dn_p: Vector3 = X * (Basis(Vector3.RIGHT, -hv) * Vector3(0, 0, -3))
		var miss := maxf(absf(m.cam.unproject_position(up_p).y - r.position.y), absf(m.cam.unproject_position(dn_p).y - r.end.y))
		worst_fov = maxf(worst_fov, miss * ShotCam.fov_v(k["f"]) / r.size.y)
		for ix in 4:
			for iy in 3:
				for d in [0.0, 0.7]:
					var p: Vector3 = (k["aim"] as Vector3) + Vector3(-0.6 + 0.4 * ix, -0.5 + 0.5 * iy, d - 0.35)
					var mine := ShotCam.project(k["pos"], k["aim"], k["f"], r, p)
					worst_px = maxf(worst_px, mine.distance_to(m.cam.unproject_position(p)))
					npts += 1
	print("     frame %s in a %s view (panels shown: off-centre)" % [m.shot_rect(), vs])
	ok(worst_fov < 0.01, "1 the rendered frame's vertical angle = fov_v(f) at 4 times (50, 35, 85 mm and between): worst %.5f deg (bar 0.01)" % worst_fov)
	ok(worst_px < 0.5, "  %d world points: the pinhole formula vs Camera3D.unproject_position, worst %.4f px (bar 0.5)" % [npts, worst_px])
	var worst_mm := 0.0
	var worst_aim := 0.0
	for j in 10:
		var t := L * (j + 0.5) / 10.0
		look(t)
		var want_p := pchip(KT, KP, t)
		var want_a := pchip(KT, KA, t)
		worst_mm = maxf(worst_mm, m.cam.global_position.distance_to(want_p) * 1000.0)
		worst_aim = maxf(worst_aim, rad_to_deg((-m.cam.global_basis.z).angle_to(want_a - want_p)))
	ok(worst_mm < 1.0 and worst_aim < 0.01, "1 between keys at 10 times: position vs the PCHIP formula worst %.4f mm (bar 1), aim worst %.5f deg" % [worst_mm, worst_aim])

	# 2 look-through vs a reference render (clean, panels hidden: the frame is centred)
	m.clean = true
	m._sides_apply()
	m.ui_root.visible = false
	var ref := Camera3D.new()
	m.add_child(ref)
	var worst2 := 0
	var rr := Rect2i()
	for t in [0.0, 0.31]:
		look(t)
		rr = m.shot_rect()
		var a := (await grab()).get_region(rr)
		var p := pchip(KT, KP, t)
		var am := pchip(KT, KA, t)
		var f: float = pchip(KT, KF.map(func(x): return Vector3(x, 0, 0)), t).x
		ref.near = m.cam.near
		ref.far = m.cam.far
		ref.global_transform = Transform3D.IDENTITY.looking_at(am - p, Vector3.UP)
		ref.global_position = p
		ref.fov = rad_to_deg(2.0 * atan(tan(atan(10.125 / f)) * vs.y / rr.size.y))
		ref.current = true
		var b := (await grab()).get_region(rr)
		m.cam.current = true
		var nd := ndiff(a, b)
		worst2 = maxi(worst2, nd if nd >= 0 else 999999)
	ref.queue_free()
	ok(worst2 == 0, "2 look-through = a separate Camera3D set from the formula: %d px differ in the %dx%d frame (bar 0)" % [worst2, rr.size.x, rr.size.y])
	m.ui_root.visible = true
	m.clean = false
	m._sides_apply()
	look(0.27)
	await idle(2)
	var shot := OS.get_environment("ZZ_SC_SHOT")
	if shot != "":
		(await grab()).save_png(shot)
		print("     screenshot: " + shot)
	ok(m.ui_shot != null and m.ui_shot.visible, "2 the 16:9 frame is drawn while looking through (panels shown)")

	# 3 playblast through the camera
	var r1: Dictionary = await m._export_playblast(base + "_cam", "")
	var d1: String = r1.get("dir", "")
	var n1: int = r1.get("frames", 0)
	m.clean = true
	m._sides_apply()
	m.ui_root.visible = false
	var crop: Rect2i = m.shot_rect()
	var worst3 := 0
	var sized := true
	for k in [0, n1 / 2, n1 - 1]:
		var img := Image.load_from_file("%s/frame_%04d.png" % [d1, k])
		sized = sized and img.get_size() == crop.size and img.get_width() * 9 == img.get_height() * 16
		look(PlayblastExport.time_of(k, 0.0, L, S.fps))
		var lt := (await grab()).get_region(crop)
		var nd := ndiff(img, lt)
		worst3 = maxi(worst3, nd if nd >= 0 else 999999)
	var f0 := Image.load_from_file("%s/frame_0000.png" % d1)
	var fl := Image.load_from_file("%s/frame_%04d.png" % [d1, n1 - 1])
	m.ui_root.visible = true
	m.clean = false
	m._sides_apply()
	ok(n1 == roundi(L * S.fps) + 1 and sized, "3 playblast through the camera: %d frames, each %s = 16:9 (w*9 == h*16)" % [n1, crop.size])
	ok(worst3 == 0, "  frames 0 / %d / %d = look-through at their times: worst %d px differ (bar 0)" % [n1 / 2, n1 - 1, worst3])
	ok(ndiff(f0, fl) > 1000, "  the picture moves: %d px differ between the first and the last frame" % ndiff(f0, fl))
	ok(m.shot_through and m.ui_root.visible, "  look-through still on after the export, panels back")

	# 4 file, schema, mirror
	var d := S.to_dict(m.B)
	var S2 := Scene.new()
	S2.from_dict(JSON.parse_string(JSON.stringify(d)))
	var d2 := S2.to_dict(m.B)
	ok(d.has("camera") and d["camera"].size() == 3 and JSON.stringify(d2) == JSON.stringify(d), "4 file round trip: 3 keys, the dict saved again is identical (%d chars)" % JSON.stringify(d).length())
	var errs := Validate.data(JSON.parse_string(JSON.stringify(d)))
	ok(errs.is_empty(), "  the schema accepts it %s" % [errs])
	var bad: Dictionary = JSON.parse_string(JSON.stringify(d))
	bad["camera"][0]["lens"] = 50
	ok(not Validate.data(bad).is_empty(), "  a misspelled key in a camera key is an error")
	var S3 := Scene.new()
	S3.from_dict({"scene": "x", "cards": d["cards"]})
	ok(not S3.to_dict(m.B).has("camera"), "  a scene with no camera writes no \"camera\" key")
	var M := Body.new()
	M.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var mi: Dictionary = Scene.mirror_file(JSON.parse_string(JSON.stringify(d)), M)
	var c0: Dictionary = d["camera"][1]
	var c1: Dictionary = mi["camera"][1]
	var mm := absf(float(c1["pos"][0]) + float(c0["pos"][0])) + absf(float(c1["aim"][0]) + float(c0["aim"][0])) + absf(float(c1["pos"][1]) - float(c0["pos"][1])) + absf(float(c1["f"]) - float(c0["f"]))
	var back: Dictionary = Scene.mirror_file(mi, M)
	ok(mm < 1e-9 and JSON.stringify(back["camera"]) == JSON.stringify(d["camera"]), "  mirror: pos / aim x negated, y and lens kept (error %.9f); twice = the original" % mm)
	# undo: lens, remove (each one step, back exactly)
	for step in [["Camera: lens 135 mm", func(): m._shot_lens(135.0)], ["lens between keys (adds a key)", func(): m.playhead = 0.2; m._shot_lens(24.0)], ["Camera: remove the key here", func(): m.playhead = 0.5; m._shot_remove()]]:
		var before := var_to_str(S.camera)
		var u1: int = m.undo.size()
		step[1].call()
		var changed := var_to_str(S.camera) != before
		var steps: int = m.undo.size() - u1
		m._undo()
		ok(changed and steps == 1 and var_to_str(S.camera) == before, "  %s: changed %s, %d undo step, one Ctrl+Z puts it back exactly" % [step[0], changed, steps])
	m.playhead = 0.33
	m._shot_remove()
	ok(String(m.ui_status.text).contains("move the playhead"), "  remove with no key at the playhead is refused: %s" % String(m.ui_status.text).left(80))
	m._shot_toggle()
	ok(not m.shot_through and m.cam.projection == Camera3D.PROJECTION_PERSPECTIVE and absf(m.cam.fov - 40.0) < 1e-6, "  look-through off: the view camera is back (perspective, fov %.1f)" % m.cam.fov)

	for b in ["_none", "_cam"]:
		_rm(ProjectSettings.globalize_path(base + b))
	print("SHOT CAMERA TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


func _rm(p: String) -> void:
	if not DirAccess.dir_exists_absolute(p):
		return
	for d in DirAccess.get_directories_at(p):
		_rm(p + "/" + d)
	for f in DirAccess.get_files_at(p):
		DirAccess.remove_absolute(p + "/" + f)
	DirAccess.remove_absolute(p)
