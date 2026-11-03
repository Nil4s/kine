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
##  730 render time estimate (scripts/render_estimate.gd; the command "Estimate render time", says it, renders nothing)
##   R1 pure: 1080p 100 frames, volumetric off: T0; volumetric on: T1 >= 2 * T0; costliest = "volumetric fog".
##      With volumetric off and 16 blur sub-frames, costliest = "samples (motion blur sub-frames)"; with neither, costliest = "".
##   R2 measured: render 6 frames at 640x360 in a SubViewport with volumetric fog off (time a), then on (time b). Calibrate the
##      estimate from run a only; the estimate for run b is within [0.5, 2.0] x the measured b.
##      CONTROL: the estimate with the volumetric multiplier removed misses b (ratio < 0.5) when b/a >= 2.5 is measured; if b/a < 2.5
##      the volumetric cost is not measurable on this GPU and the control is reported as not decidable (a FAIL line, not a pass).
##   R3 the command: with volumetric fog on in the scene's environment, its text names "volumetric fog", the frame count and
##      "s" / "min"; no folder under exports/shots is made. CONTROL: with fog off the text does not name volumetric fog.
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
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
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


func fog_run(on: bool, frames: int) -> float:
	var sv := SubViewport.new()
	sv.size = Vector2i(640, 360)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sv)
	var cam := Camera3D.new()
	sv.add_child(cam)
	cam.position = Vector3(0, 1, 4)
	var env := Environment.new()
	env.volumetric_fog_enabled = on
	env.volumetric_fog_density = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	sv.add_child(we)
	var l := DirectionalLight3D.new()
	l.shadow_enabled = true
	l.light_volumetric_fog_energy = 1.0
	sv.add_child(l)
	var mi := MeshInstance3D.new()
	mi.mesh = SphereMesh.new()
	sv.add_child(mi)
	await idle(3)
	var t0 := Time.get_ticks_usec()
	for i in frames:
		await RenderingServer.frame_post_draw
		sv.get_texture().get_image()
	var dt := float(Time.get_ticks_usec() - t0) / 1e6
	sv.queue_free()
	return dt


func shots_dirs() -> int:
	var p := ProjectSettings.globalize_path("res://exports/shots")
	return DirAccess.get_directories_at(p).size() if DirAccess.dir_exists_absolute(p) else 0


func _init() -> void:
	wd()
	# ---- 730 pure ----
	var base := {"w": 1920, "h": 1080, "frames": 100}
	var e0: Dictionary = RenderEstimate.estimate(base)
	var sv: Dictionary = base.duplicate()
	sv["volumetric"] = true
	var e1: Dictionary = RenderEstimate.estimate(sv)
	ok(float(e1["secs"]) >= 2.0 * float(e0["secs"]) and String(e1["costliest"]) == "volumetric fog", "R1 volumetric on %.1f s vs off %.1f s, costliest '%s'" % [e1["secs"], e0["secs"], e1["costliest"]])
	var bl: Dictionary = base.duplicate()
	bl["blur_n"] = 16
	ok(String(RenderEstimate.estimate(bl)["costliest"]) == "samples (motion blur sub-frames)" and String(e0["costliest"]) == "", "R1b blur 16 names samples; plain names nothing ('%s')" % e0["costliest"])
	# ---- 730 measured ----
	var a := await fog_run(false, 6)
	var b := await fog_run(true, 6)
	var small := {"w": 640, "h": 360, "frames": 6}
	var cal := RenderEstimate.calibrate(small, a)
	var sb: Dictionary = small.duplicate()
	sb["volumetric"] = true
	var pred: float = RenderEstimate.estimate(sb, cal)["secs"]
	var ratio := pred / maxf(b, 1e-6)
	print("  measured a=%.3f b=%.3f (b/a %.2f), predicted b=%.3f, ratio %.2f" % [a, b, b / maxf(a, 1e-6), pred, ratio])
	ok(ratio >= 0.5 and ratio <= 2.0, "R2 estimate for the fog run within [0.5, 2.0] of measured: %.2f" % ratio)
	if b / maxf(a, 1e-6) >= 2.5:
		var flat: float = RenderEstimate.estimate(small, cal)["secs"]
		ok(flat / b < 0.5, "R2 control: fog multiplier removed misses (%.2f)" % (flat / b))
	else:
		ok(false, "R2 control: volumetric cost not measurable here (b/a %.2f < 2.5): not decidable" % (b / maxf(a, 1e-6)))
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
	var r: Dictionary = m._render_estimate()
	var txt := String(r.get("text", ""))
	ok(txt.find("volumetric fog") >= 0 and txt.find("frames") >= 0 and (txt.find(" s") >= 0 or txt.find("min") >= 0) and d0 == shots_dirs(), "R3 fog on: '%s'; no folder made" % txt)
	await shot("estimate")
	env.volumetric_fog_enabled = false
	var txt2 := String(m._render_estimate().get("text", ""))
	ok(txt2.find("volumetric fog") < 0, "R3 control fog off: '%s'" % txt2)
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
	print("c25: %d fail" % fails)
	quit(1 if fails > 0 else 0)
