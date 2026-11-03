## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/c25_test.gd     (C25, complaints 198 730; a window)
## BARS (written and committed before the first run). Env C25_SHOT=<dir> saves 1280x720 screenshots.
##  198 one Move rule in and out of sketch (scripts/build/move_rule.gd; opt-in: MoveRule.unified, default false)
##   M1 the rule: snap(12.3, 5) = 10, snap(12.3, 1) = 12, Alt (free) = 12.3; the sketch grid (PartUI.snap) gives the same numbers
##      as MoveRule per component with unified on AND off at snap 5 (nothing existing changes).
##   M2 a real drag of a piece with unified ON and the sketch snap at 5 mm: the cube's x and z on the plate are multiples of 5 (0.01).
##      CONTROL: the same drag with unified OFF lands on whole mm, and NOT a multiple of 5 in x or z.
##   M3 typed distance: unified ON, drag, type 1 5 (keys), release: the slide across the face is 15.000 mm (0.01).
##      CONTROL: the same drag with no typing slides some other length (differs from 15 by > 1 mm).
##   M4 Esc after typing clears the number and the piece drops by the pointer (control for M3's key route).
##  730 render time estimate (scripts/render_estimate.gd). FIX ROUND 1: calibrate on scene A, judge on a HELD-OUT heavier scene B.
##   Scene A (calibration): one sphere + one shadow light in a SubViewport, 8 frames per timing, the median of 3 timings, per-frame secs.
##     fit(): plain 320x180 and plain 960x540 give the per-frame overhead and the per-pixel rate. learn(): at 640x360 each of ssao, sdfgi
##     and volumetric fog is timed; its extra is kept only when >= 0.3 of a plain frame, else the setting is DROPPED (not guessed).
##   Scene B (held out, timed only AFTER the calibration): 1280x720, 12 spheres, shadow light, SSAO on (and SDFGI on), 8 frames.
##   R1 pure: with a planted calibration extra {ssao 1.0, sdfgi 2.0}: sdfgi + ssao on names "SDFGI"; none on names ""; 16 blur
##      sub-frames name "samples (motion blur sub-frames)"; with the DEFAULT calibration (no extras) a volumetric flag names nothing.
##   R2a a setting is named costly iff its measured extra on scene A was >= 0.3 (volumetric included).
##   R2b the estimate for scene B (calibration from A only) is within [0.5, 2.0] x the measured time of B.
##   R2c CONTROL: the same estimate with the rate times 10 is outside the band (> 2.0).
##   R3 the Export dialog: a real click on its "Estimate render time" button puts the sentence (frames, time) in its label and in the
##      status line, and makes no folder under exports/shots. With volumetric fog on in the scene the sentence names fog iff R2a says
##      fog is costly. A real click on the "Say the time first" checkbox sets RenderEstimate.show_first.
##   R4 ribbon button count: none added (ribbonsd unchanged).
##  198 reachability
##   M5 a real click on the checkbox "One Move rule" (sketch panel next to Grid) sets MoveRule.unified; a second click clears it.
extends SceneTree

const SHOT := "C:/Temp/claude/c25"
const DIRT := "user://c25_test"
var fails := 0
var m: Node
var last_p := Vector2.ZERO


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


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = p - last_p
	last_p = p
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func key(k: int) -> void:
	for d in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = d
		root.push_input(e, true)
		await process_frame


func click_ctl(c: Control) -> void:
	# C30 moved the Export dialog options into export_opts_scroll: bring the control into view first, as a user would
	var sq: Node = c.get_parent()
	while sq != null:
		if sq is ScrollContainer:
			(sq as ScrollContainer).ensure_control_visible(c)
			await process_frame
			await process_frame
			break
		sq = sq.get_parent()
	var w: Window = c.get_window()   # a dialog is its own window: the click goes to it
	var p := c.get_global_rect().get_center()
	if w.is_embedded():
		p += Vector2(w.position)   # an embedded dialog: its content sits at its position in the root
		w = root
	var chain := ""
	var q: Node = c
	while q != null and q != root:
		if q is CanvasItem and not (q as CanvasItem).visible:
			chain += " HIDDEN:" + str(q.name)
		q = q.get_parent()
	print("  click %s in window %s (root %s) embedded %s%s" % [c.name, w.name, str(w == root), str(w.is_embedded()), chain])
	for d in [null, true, false]:
		var e: InputEvent
		if d == null:
			var mm := InputEventMouseMotion.new()
			mm.position = p
			mm.global_position = p
			e = mm
		else:
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			mb.pressed = d
			mb.position = p
			mb.global_position = p
			if d:
				mb.button_mask = MOUSE_BUTTON_MASK_LEFT
			e = mb
		w.push_input(e, true)
		await process_frame
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	var d := OS.get_environment("C25_SHOT")
	if d == "":
		d = SHOT
	DirAccess.make_dir_recursive_absolute(d)
	root.get_texture().get_image().save_png("%s/%s.png" % [d, nm])


func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func box_of(i: int) -> Array:
	var faces: Array = Part.body_faces(m.S.part, -1)
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in faces[i]:
		lo = lo.min(v)
		hi = hi.max(v)
	return [lo * 1000.0, hi * 1000.0]


func rect_piece(rec: Dictionary, a: Vector2, b: Vector2, h: float) -> void:
	var sk := Part.new_feature(rec, "sketch", {"plane": "top", "ents": [{"k": "rect", "a": [a.x, a.y], "b": [b.x, b.y]}], "dims": []})
	rec["features"].append(sk)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": sk["id"], "dist": h, "both": false, "op": "new"}))


func reset_pieces() -> void:
	var rec := Part.make("Part")
	rect_piece(rec, Vector2(-20, -20), Vector2(20, 20), 10.0)
	rect_piece(rec, Vector2(80, -10), Vector2(100, 10), 20.0)
	m.S.part = rec
	pu().sync()


## grab the cube, drag over the plate top to (12.3, 10, 7.1) mm, optionally type keys, release. Returns the cube's box after.
func drag_cube(typed: Array) -> Array:
	reset_pieces()
	await idle(20)
	var grab := Vector3(0.09, 0.020, 0.0)
	var drop := Vector3(0.0123, 0.010, 0.0071)
	await ev_move(scr(grab), false)
	await ev_mouse(scr(grab), true)
	for i in range(1, 9):
		await ev_move(scr(grab).lerp(scr(drop), i / 9.0))
	await ev_move(scr(drop))
	for k in typed:
		await key(k)
	await idle(2)
	await ev_mouse(scr(drop), false)
	await idle(10)
	return box_of(1)


func wd() -> void:   # watchdog: a script error after an await must not hang the run
	await create_timer(600.0).timeout
	print("FAIL: c25 watchdog (600 s)")
	quit(1)


## per-frame seconds (median of 3 timings of 8 frames) of a SubViewport w x h; opts: ssao, sdfgi, volumetric, meshes
func timed(w: int, h: int, opts: Dictionary) -> float:
	var sv := SubViewport.new()
	sv.size = Vector2i(w, h)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sv)
	var cam := Camera3D.new()
	sv.add_child(cam)
	cam.position = Vector3(0, 1, 6)
	var env := Environment.new()
	env.ssao_enabled = bool(opts.get("ssao", false))
	env.sdfgi_enabled = bool(opts.get("sdfgi", false))
	env.volumetric_fog_enabled = bool(opts.get("volumetric", false))
	env.volumetric_fog_density = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	sv.add_child(we)
	var l := DirectionalLight3D.new()
	l.shadow_enabled = true
	sv.add_child(l)
	for i in maxi(1, int(opts.get("meshes", 1))):
		var mi := MeshInstance3D.new()
		mi.mesh = SphereMesh.new()
		mi.position = Vector3((i % 4) * 1.5 - 2.2, (i / 4) * 1.2 - 1.0, 0)
		sv.add_child(mi)
	await idle(3)
	var runs := []
	for rep in 3:
		var t0 := Time.get_ticks_usec()
		for i in 8:
			await RenderingServer.frame_post_draw
			sv.get_texture().get_image()
		runs.append(float(Time.get_ticks_usec() - t0) / 1e6 / 8.0)
	sv.queue_free()
	runs.sort()
	return runs[1]


func shots_dirs() -> int:
	var p := ProjectSettings.globalize_path("res://exports/shots")
	return DirAccess.get_directories_at(p).size() if DirAccess.dir_exists_absolute(p) else 0


func _init() -> void:
	wd()
	# ---- 730 pure ----
	var planted := {"over": 0.0, "rate": 1e-9, "extra": {"ssao": 1.0, "sdfgi": 2.0}}
	var jj := {"w": 1920, "h": 1080, "frames": 100, "ssao": true, "sdfgi": true}
	ok(String(RenderEstimate.estimate(jj, planted)["costliest"]) == "SDFGI", "R1 planted: sdfgi+ssao names SDFGI")
	ok(String(RenderEstimate.estimate({"w": 1920, "h": 1080, "frames": 100}, planted)["costliest"]) == "", "R1 nothing on names nothing")
	ok(String(RenderEstimate.estimate({"w": 1920, "h": 1080, "frames": 100, "blur_n": 16}, planted)["costliest"]) == "samples (motion blur sub-frames)", "R1 blur 16 names samples")
	ok(String(RenderEstimate.estimate({"w": 1920, "h": 1080, "frames": 100, "volumetric": true})["costliest"]) == "", "R1 default calibration: volumetric flag names nothing")
	# ---- 730 measured: scene A (calibration) ----
	var t_lo := await timed(320, 180, {})
	var t_hi := await timed(960, 540, {})
	var cal := RenderEstimate.fit(320, 180, t_lo, 960, 540, t_hi)
	var tp := await timed(640, 360, {})
	var measured := {}
	for k in ["ssao", "sdfgi", "volumetric"]:
		var tk := await timed(640, 360, {k: true})
		cal = RenderEstimate.learn(cal, k, 640, 360, tk)
		measured[k] = tk / maxf(float(cal["over"]) + float(cal["rate"]) * 640.0 * 360.0, 1e-12) - 1.0   # extra = share of a plain frame
	print("  cal over %.4f rate %s plain640 %.4f measured extras %s kept %s" % [cal["over"], str(cal["rate"]), tp, str(measured), str(cal["extra"])])
	var consistent := true
	for k in measured:
		consistent = consistent and ((cal["extra"] as Dictionary).has(k) == (float(measured[k]) >= RenderEstimate.MIN_EXTRA))
	ok(consistent, "R2a named costly iff measured >= %.1f (fog extra %.2f, kept %s)" % [RenderEstimate.MIN_EXTRA, measured["volumetric"], str((cal["extra"] as Dictionary).has("volumetric"))])
	# ---- scene B (held out) ----
	var tb := await timed(1280, 720, {"ssao": true, "sdfgi": true, "meshes": 12})
	var pb: float = RenderEstimate.estimate({"w": 1280, "h": 720, "frames": 1, "ssao": true, "sdfgi": true}, cal)["secs"]
	var ratio := pb / maxf(tb, 1e-9)
	print("  scene B measured %.4f s/frame predicted %.4f ratio %.2f" % [tb, pb, ratio])
	ok(ratio >= 0.5 and ratio <= 2.0, "R2b held-out scene B estimate within [0.5, 2.0] of measured: %.2f" % ratio)
	var cal10 := cal.duplicate(true)
	cal10["rate"] = float(cal["rate"]) * 10.0
	cal10["over"] = float(cal["over"]) * 10.0
	var r10: float = float(RenderEstimate.estimate({"w": 1280, "h": 720, "frames": 1, "ssao": true, "sdfgi": true}, cal10)["secs"]) / maxf(tb, 1e-9)
	ok(r10 > 2.0, "R2c control: rate x10 is outside the band (%.2f)" % r10)
	# ---- the app ----
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var env: Environment = m.world_env
	env.volumetric_fog_enabled = true
	var d0 := shots_dirs()
	RenderEstimate.app_cal = cal
	m._export_dialog_open()
	await idle(6)
	var xd = m.export_ui
	var chk: CheckBox = xd.dlg.find_child("chk_estimate_first", true, false)
	var btn: Button = xd.dlg.find_child("btn_estimate_time", true, false)
	var lab: Label = xd.dlg.find_child("lbl_estimate_time", true, false)
	ok(chk != null and btn != null and lab != null, "R3 the Export dialog holds the checkbox, button and label")
	await idle(10)
	print("  dlg visible %s btn rect %s" % [str(xd.dlg.visible), str(btn.get_global_rect()) if btn != null else "-"])
	if btn != null:
		await click_ctl(btn)
		var txt := lab.text
		ok(txt.find("frames") >= 0 and (txt.find(" s") >= 0 or txt.find("min") >= 0) and d0 == shots_dirs(), "R3 clicked: '%s'; no folder made" % txt)
		ok((txt.find("volumetric fog") >= 0) == ((cal["extra"] as Dictionary).has("volumetric")), "R3 fog named iff learned costly ('%s')" % txt)
		await shot("estimate")
	if chk != null:
		await click_ctl(chk)
		ok(RenderEstimate.show_first, "R3 click on 'Say the time first' sets show_first")
		await click_ctl(chk)
		ok(not RenderEstimate.show_first, "R3 second click clears it")
	xd.dlg.hide()
	await idle(5)
	# ---- 198 ----
	ok(is_equal_approx(MoveRule.snap(12.3, 5.0, false), 10.0) and is_equal_approx(MoveRule.snap(12.3, 1.0, false), 12.0) and is_equal_approx(MoveRule.snap(12.3, 5.0, true), 12.3), "M1 rule numbers")
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3.ZERO
	m.pitch = -30.0
	m.yaw = 25.0
	m._cam()
	await idle(40)
	var same := true
	for u in [false, true]:
		MoveRule.unified = u
		var v: Vector2 = pu().snap(Vector2(12.3, 7.1))
		same = same and is_equal_approx(v.x, MoveRule.snap(12.3, pu().snap_mm, false)) and is_equal_approx(v.y, MoveRule.snap(7.1, pu().snap_mm, false))
	ok(same and pu().snap_mm == 5.0, "M1b sketch grid equals the rule, on and off (snap %.0f)" % pu().snap_mm)
	MoveRule.unified = true
	pu().snap_mm = 5.0
	var c1 := await drag_cube([])
	var x5 := absf(fposmod(float(c1[0].x) + 2.5, 5.0) - 2.5) < 0.01 and absf(fposmod(float(c1[0].z) + 2.5, 5.0) - 2.5) < 0.01
	ok(x5, "M2 unified: cube min x %.3f z %.3f are multiples of 5" % [c1[0].x, c1[0].z])
	await shot("move_unified")
	MoveRule.unified = false
	var c0 := await drag_cube([])
	var whole := absf(float(c0[0].x) - roundf(float(c0[0].x))) < 0.01 and absf(float(c0[0].z) - roundf(float(c0[0].z))) < 0.01
	var not5 := absf(fposmod(float(c0[0].x) + 2.5, 5.0) - 2.5) > 0.01 or absf(fposmod(float(c0[0].z) + 2.5, 5.0) - 2.5) > 0.01
	ok(whole and not5, "M2 control: default lands on whole mm (%.3f, %.3f), not on 5" % [c0[0].x, c0[0].z])
	MoveRule.unified = true
	var ct := await drag_cube([KEY_1, KEY_5])
	var slide := Vector2(float(ct[0].x) - 80.0, float(ct[0].z) + 10.0).length()
	ok(absf(slide - 15.0) < 0.01, "M3 typed 15: slide %.3f mm" % slide)
	var cn := await drag_cube([])
	var slide2 := Vector2(float(cn[0].x) - 80.0, float(cn[0].z) + 10.0).length()
	ok(absf(slide2 - 15.0) > 1.0, "M3 control: no typing slides %.3f mm" % slide2)
	var ce := await drag_cube([KEY_1, KEY_5, KEY_ESCAPE])
	ok((Vector2(float(ce[0].x), float(ce[0].z)) - Vector2(float(cn[0].x), float(cn[0].z))).length() < 0.01, "M4 Esc clears the typed number: lands where no typing lands")
	MoveRule.unified = false
	# M5 last: Expert (a real click), a sketch open, the checkbox in the sketch panel
	await click_ctl(pu().ep.expert_btn)
	await idle(20)
	var skid := ""
	for f in (m.S.part["features"] as Array):
		if String(f.get("type", f.get("t", ""))) == "sketch":
			skid = String(f["id"])
			break
	pu().sk = skid
	pu().sync()
	await idle(10)
	var mchk: CheckBox = pu().move_chk
	print("  move_chk visible %s rect %s sk '%s'" % [str(mchk.is_visible_in_tree()), str(mchk.get_global_rect()), skid])
	await shot("move_checkbox")
	ok(mchk.is_visible_in_tree() and not MoveRule.unified, "M5 the checkbox is on screen in Expert's sketch panel, off by default")
	await click_ctl(mchk)
	ok(MoveRule.unified, "M5 a real click turns the one Move rule on")
	await click_ctl(mchk)
	ok(not MoveRule.unified, "M5 a second click turns it off")
	print("c25: %d fail" % fails)
	quit(1 if fails > 0 else 0)
