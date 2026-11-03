extends SceneTree
## godot --path . -s tests/c46_test.gd     (C46: the Combine dialog runs a many-tool combine through C38's stepwise job; finishes complaint #289)
## N (stated): a combine with MORE THAN 8 tools is heavy (scripts/build/combine_heavy.gd MAX_SYNC_TOOLS = 8); 8 or fewer stay synchronous.
## BARS (written and committed BEFORE the numbers were read). Needs a window (wtest gives one off-screen) and the CAD kernel. 1280 x 720, real clicks.
##  A SMALL STAYS SYNC. 3 tools, real clicks on the browser rows and OK: no bool_busy node ever appears (sampled every frame), the step is committed, the
##    volume equals the analytic answer within 1e-9 m3. (A passes on origin too: it guards that nothing small changed.)
##  B HEAVY RUNS STEPWISE. 40 tools, real clicks on the rows and OK:
##   B1 CONTROL (fails on origin): a bool_busy node shows, its line says "of 40" and a percent, its bar max is 40, and the bar value rises over the job.
##   B2 FRAME GAP: the longest gap between frames during the job <= 0.5 x the combine's own share of one synchronous Part.replay of the same record
##      (a ratio to this machine; CONTROL: the synchronous run's longest gap is its whole time, which fails this bar).
##   B3 SAME ANSWER: the committed volume equals the synchronous replay's volume of the same record within 1e-9 m3; one undo step; busy node gone.
##   B4 COMMIT IS NOT A SECOND JOB: the frames from the job's end to the committed step take <= 0.5 x the synchronous combine share.
##  C CANCEL. 40 tools, OK, then a REAL click on the Cancel button once the job is at step >= 5:
##   C1 the job stops (busy gone, no step added, undo size unchanged), C2 the part record (JSON) is byte-identical,
##   C3 the replayed volumes equal the ones before and the live solid count is not higher than before OK, C4 the dialog is still open with OK enabled.
##  D SHOT: C:/Users/Nick/tools/kine_workers/out/c46/busy.png, taken mid-job (looked at by hand).
const KCad := preload("res://scripts/kcad.gd")
const OUT := "C:/Users/Nick/tools/kine_workers/out/c46"
const NT := 40
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func _init() -> void:
	if not Part.available():
		print("SKIP: no CAD kernel")
		print("C46 SKIP")
		quit(0)
		return
	if DisplayServer.get_name() == "headless":
		print("SKIP: needs a window")
		print("C46 SKIP")
		quit(0)
		return
	var wd := create_timer(420.0)
	wd.timeout.connect(func():
		print("FAIL watchdog: c46 ran 420 s")
		quit(1))
	await run()
	print("C46 ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)


## a plate (body 0, 400 x 400 x 20 mm) and n cylinder tools (bodies 1..n, r 4 mm, on a grid inside the plate)
func plate_rec(n: int) -> Dictionary:
	var rec := Part.make("C46")
	var feats: Array = [
		{"t": "sketch", "id": "s0", "name": "S0", "plane": "front", "ents": [{"k": "rect", "a": [0.0, 0.0], "b": [400.0, 400.0]}], "dims": []},
		{"t": "extrude", "id": "e0", "name": "E0", "sketch": "s0", "dist": 20.0, "both": false, "op": "new"}]
	for i in n:
		var cx := 30.0 + 45.0 * float(i % 8)
		var cy := 30.0 + 60.0 * float(i / 8)
		feats.append({"t": "sketch", "id": "t%d" % i, "name": "T%d" % i, "plane": "front", "ents": [{"k": "circle", "c": [cx, cy], "r": 4.0}], "dims": []})
		feats.append({"t": "extrude", "id": "u%d" % i, "name": "U%d" % i, "sketch": "t%d" % i, "dist": 60.0, "both": true, "op": "new"})
	rec["features"] = feats
	return rec


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


func click_at(p: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv, true)
	await process_frame
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func press_tool(m: Node, pu: PartUI, t: String) -> void:
	var b: Button = pu.tool_btns[t]
	if b.is_visible_in_tree():
		await click_ctl(b)
		return
	for pair in m.ui_caps.get("BUILD", []):
		if (pair[1] as Array).has(b):
			await click_ctl(pair[0])
			(pair[0] as MenuButton).get_popup().hide()
			m._run_tool(b, pair[0])
			await idle(2)
			return


## a real click on body i's browser row (scrolled into view first)
func click_row(pu: PartUI, i: int) -> void:
	var b: Control = pu.browser.find_child("part_body_%d" % i, true, false)
	var sc := pu.browser_vb.get_parent() as ScrollContainer
	if sc != null:
		sc.ensure_control_visible(b)
		await idle(2)
	await click_ctl(b)


func busy(pu: PartUI) -> Node:
	return pu.dlg_box.find_child("bool_busy", true, false) if pu.dlg_box != null else null


func open_combine(m: Node, pu: PartUI, ntools: int, op_idx: int) -> void:
	await press_tool(m, pu, "Combine")
	await idle(2)
	await click_row(pu, 0)
	for i in range(1, ntools + 1):
		await click_row(pu, i)
	pu.f_cmb_op.select(op_idx)
	pu.f_cmb_op.item_selected.emit(op_idx)
	await idle(2)


func boot(rec: Dictionary) -> Array:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	var pu: PartUI = m.bld.part
	var dirt := "user://c46_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dirt))
	ss.dirs_override = [dirt]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	m.S.part = rec
	if not pu.on:
		await click_ctl(pu.part_btn)
		await idle(3)
	pu._rebuild(true)
	await idle(3)
	return [m, pu]


func run() -> void:
	# ---- A: 3 tools stay synchronous
	var a := await boot(plate_rec(3))
	var m: Node = a[0]
	var pu: PartUI = a[1]
	await open_combine(m, pu, 3, 1)
	var seen_busy := [false]
	var watch := func():
		if busy(pu) != null:
			seen_busy[0] = true
	process_frame.connect(watch)
	var n0: int = m.undo.size()
	await click_ctl(pu.ok_btn)
	await idle(4)
	process_frame.disconnect(watch)
	var va: Array = pu.res.get("volumes", [])
	var want_a := 400.0 * 400.0 * 20.0 * 1e-9 - 3.0 * PI * 16.0 * 20.0 * 1e-9
	ok(not seen_busy[0] and m.undo.size() == n0 + 1 and va.size() == 1 and absf(float(va[0]) - want_a) < 1e-9,
			"A SMALL: busy shown %s, undo %d -> %d, volume %s vs analytic %s" % [seen_busy[0], n0, m.undo.size(), va, want_a])
	m.queue_free()
	await idle(4)

	# ---- reference: the same 40-tool combine by one synchronous replay
	var rec_ref := plate_rec(NT)
	var tl: Array = []
	for i in range(1, NT + 1):
		tl.append(i)
	rec_ref["features"].append({"t": "combine", "id": "c1", "name": "C1", "target": 0, "tools": tl, "op": "cut", "keep": false})
	var t0 := Time.get_ticks_usec()
	var ref := Part.replay(rec_ref)
	var sync_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var sync_vol := float((ref["volumes"] as Array)[0]) if (ref["volumes"] as Array).size() > 0 else -1.0
	t0 = Time.get_ticks_usec()
	Part.replay(plate_rec(NT))
	var prep_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var job_sync_ms := maxf(sync_ms - prep_ms, 1.0)   # the combine's own share
	print("ref: sync replay %.0f ms, prep %.0f ms, combine share %.0f ms, volume %s" % [sync_ms, prep_ms, job_sync_ms, sync_vol])

	# ---- B: 40 tools, stepwise
	var b := await boot(plate_rec(NT))
	m = b[0]
	pu = b[1]
	await open_combine(m, pu, NT, 1)
	ok((pu.cmb.get("tools", []) as Array).size() == NT and not pu.ok_btn.disabled, "B0 the dialog holds %d tools by real row clicks, OK on" % (pu.cmb.get("tools", []) as Array).size())
	var n1: int = m.undo.size()
	var st := {"line": "", "max": 0.0, "v0": -1.0, "v1": -1.0, "gap": 0.0, "last": Time.get_ticks_usec(), "shot": false, "seen": false}
	var cb2 := func():
		var now := Time.get_ticks_usec()
		var bz := busy(pu)
		if bz != null:
			st["seen"] = true
			st["gap"] = maxf(float(st["gap"]), (now - int(st["last"])) / 1000.0)
			st["line"] = String(bz.line.text)
			st["max"] = float(bz.bar.max_value)
			if float(st["v0"]) < 0.0:
				st["v0"] = float(bz.bar.value)
			st["v1"] = float(bz.bar.value)
			if not bool(st["shot"]) and float(bz.bar.value) >= 12.0:
				st["shot"] = true
				DirAccess.make_dir_recursive_absolute(OUT)
				root.get_texture().get_image().save_png(OUT + "/busy.png")
		st["last"] = now
	process_frame.connect(cb2)
	await click_ctl(pu.ok_btn)
	var t_end := Time.get_ticks_usec()
	for k in 3000:
		await process_frame
		if busy(pu) != null:
			t_end = Time.get_ticks_usec()   # the last frame the busy bar showed = the job's end
		if m.undo.size() > n1:
			break
	var t_commit := (Time.get_ticks_usec() - t_end) / 1000.0
	process_frame.disconnect(cb2)
	ok(bool(st["seen"]) and String(st["line"]).contains("of %d" % NT) and String(st["line"]).contains("%") and float(st["max"]) == float(NT) and float(st["v1"]) > float(st["v0"]),
			"B1 BUSY BAR: seen %s, line '%s', max %s, value %s -> %s" % [st["seen"], st["line"], st["max"], st["v0"], st["v1"]])
	ok(float(st["gap"]) > 0.0 and float(st["gap"]) <= 0.5 * job_sync_ms, "B2 FRAME GAP: longest %.1f ms <= 0.5 x sync combine %.1f ms; CONTROL the sync run's gap is its whole %.1f ms and %s the bar" % [st["gap"], job_sync_ms, job_sync_ms, "fails" if job_sync_ms > 0.5 * job_sync_ms else "passes"])
	await idle(3)
	var vb: Array = pu.res.get("volumes", [])
	ok(m.undo.size() == n1 + 1 and vb.size() == 1 and absf(float(vb[0]) - sync_vol) < 1e-9 and busy(pu) == null,
			"B3 SAME ANSWER: undo %d -> %d, volume %s vs sync %s, busy gone %s" % [n1, m.undo.size(), vb, sync_vol, busy(pu) == null])
	ok(t_commit <= 0.5 * job_sync_ms, "B4 COMMIT: job end to committed step %.0f ms <= 0.5 x sync combine %.0f ms" % [t_commit, job_sync_ms])
	m.queue_free()
	await idle(4)

	# ---- C: cancel by a real click
	var c := await boot(plate_rec(NT))
	m = c[0]
	pu = c[1]
	await open_combine(m, pu, NT, 1)
	var before := JSON.stringify(m.S.part)
	var undo0: int = m.undo.size()
	var vol0: Array = Part.replay(m.S.part)["volumes"]
	var live0 := KCad.live_count()
	await click_ctl(pu.ok_btn)
	var stp := 0
	for k in 3000:
		await process_frame
		var bz := busy(pu)
		if bz != null:
			stp = int(bz.bar.value)
			if stp >= 5:
				break
	var bz2 := busy(pu)
	ok(bz2 != null and stp >= 5, "C0 the job is at step %d with a Cancel button showing" % stp)
	if bz2 != null:
		await click_ctl(bz2.btn)
	await idle(6)
	var info := String(pu.dlg_info.text)
	ok(busy(pu) == null and m.undo.size() == undo0 and String(pu.dlg.get("t", "")) == "combine" and not pu.ok_btn.disabled,
			"C1/C4 CANCEL: busy gone %s, undo %d -> %d, dialog open %s, OK on %s ('%s')" % [busy(pu) == null, undo0, m.undo.size(), String(pu.dlg.get("t", "")) == "combine", not pu.ok_btn.disabled, info])
	var vol1: Array = Part.replay(m.S.part)["volumes"]
	ok(JSON.stringify(m.S.part) == before, "C2 the part record is byte-identical")
	ok(str(vol1) == str(vol0) and KCad.live_count() <= live0, "C3 volumes %s == %s, live solids %d -> %d" % [vol1, vol0, live0, KCad.live_count()])
	ok(FileAccess.file_exists(OUT + "/busy.png"), "D SHOT saved " + OUT + "/busy.png")
