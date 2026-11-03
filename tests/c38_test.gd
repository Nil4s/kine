extends SceneTree
## godot --path . -s tests/c38_test.gd     (C38: booleans you can trust; complaints #85 coincident faces, #289 a slow boolean)
## BARS (written and committed BEFORE the numbers were read):
##  A COINCIDENT FACES. A 100 mm cube cut by a cylinder of r = 50 mm (tangent to all four walls), and a cylinder r = 20 tangent to a corner pair.
##   A1 CONTROL (fails on origin): the raw kernel answer has open edges > 0 (this is the failure being fixed; its volume is right, its mesh is not).
##   A2 through Part.replay (a Combine step): mesh open edges == 0, volume within 0.5 % of the analytic answer, no error, lumps == 1.
##   A3 the words: the step's warning says "0.01 mm" and the open-edge count; the nudge is at most 0.01 mm per axis.
##   A4 CONTROL: a plain cut that is not coincident (cylinder r 30) gives NO warning and is not moved (exact same volume as the raw kernel).
##   A5 the same on a body turned 0.7 rad (A2 bars again).
##  B HEAVY BOOLEAN. 60 cylinder tools cut one plate, one tool per frame.
##   B0 IDLE: the median idle frame gap is measured here first (ms).
##   B1 FRAME GAP: the longest gap between frames during the job <= 0.5 x the total time of the same work run in one synchronous loop (ratio to
##      this machine; the CONTROL is the synchronous loop itself, whose longest gap is its whole total and so fails the bar), and it is
##      reported as a multiple of the idle gap.
##   B2 PROGRESS: on_progress is called total + 1 times, `done` never goes down, the last call is (total, total).
##   B3 SAME ANSWER: the job volume equals the synchronous result volume within 1e-9 m3.
##   B4 CANCEL (real click on the Cancel button, 1280 x 720): after the click the job stops within 2 frames of finishing its step, returns the
##      target id itself, the target volume and its tessellated vertex hash are byte-equal to before, and live solid count == before.
##   B5 SHOT: C:/Users/Nick/tools/kine_workers/out/c38/busy.png (looked at by hand).
const KCad := preload("res://scripts/kcad.gd")
const BS := preload("res://scripts/build/boolean_safe.gd")
const BUI := preload("res://scripts/build/boolean_progress_ui.gd")
const OUT := "C:/Users/Nick/tools/kine_workers/out/c38"
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func _init() -> void:
	if not Part.available():
		print("SKIP: no CAD kernel")
		print("C38 SKIP")
		quit(0)
		return
	# a watchdog: the whole test ends by itself
	var wd := create_timer(240.0)
	wd.timeout.connect(func():
		print("FAIL watchdog: c38 ran 240 s")
		quit(1))
	await bars_a()
	await bars_b()
	print("C38 ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)


func rec_for(r_mm: float, cx: float, cy: float) -> Dictionary:
	var rec := Part.make("C38")
	rec["features"] = [
		{"t": "sketch", "id": "s1", "name": "S1", "plane": "front", "ents": [{"k": "rect", "a": [0.0, 0.0], "b": [100.0, 100.0]}], "dims": []},
		{"t": "extrude", "id": "e1", "name": "E1", "sketch": "s1", "dist": 100.0, "both": false, "op": "new"},
		{"t": "sketch", "id": "s2", "name": "S2", "plane": "front", "ents": [{"k": "circle", "c": [cx, cy], "r": r_mm}], "dims": []},
		{"t": "extrude", "id": "e2", "name": "E2", "sketch": "s2", "dist": 100.0, "both": false, "op": "new"},
		{"t": "combine", "id": "c1", "name": "C1", "target": 0, "tools": [1], "op": "cut", "keep": false}]
	return rec


func replay_bars(tag: String, rec: Dictionary, expect: float, want_warning: bool) -> void:
	var r := Part.replay(rec)
	var q := BS.inspect_mesh(r["mesh"])
	var v := float((r["volumes"] as Array)[0]) if (r["volumes"] as Array).size() > 0 else -1.0
	var err := absf(v - expect) / expect
	ok((r["errors"] as Dictionary).is_empty() and int(q["open"]) == 0 and err <= 0.005 and int(q["lumps"]) == 1,
			"%s A2 replay: errors %s open %s lumps %s vol err %.4f %%" % [tag, r["errors"], q["open"], q["lumps"], err * 100.0])
	var w := String((r["warnings"] as Dictionary).get("c1", ""))
	ok(w.contains("0.01 mm") == want_warning, "%s A3 words: '%s'" % [tag, w])


func bars_a() -> void:
	var A := KCad.box(0.1, 0.1, 0.1)
	var cyl := KCad.cylinder(0.05, 0.1)
	var raw := KCad.cut(A, cyl)
	var q0 := BS.inspect(raw)
	ok(int(q0["open"]) > 0, "A1 CONTROL raw kernel cut (cyl r50 in cube 100): open edges %s (>0 = the defect), volume %s" % [q0["open"], KCad.volume(raw)])
	var cube_v := 1e-3
	replay_bars("r50 tangent", rec_for(50.0, 50.0, 50.0), cube_v - PI * 0.05 * 0.05 * 0.1, true)
	replay_bars("r20 corner", rec_for(20.0, 80.0, 80.0), cube_v - PI * 0.02 * 0.02 * 0.1, true)
	# A4 a cut that does not touch: no words, same volume as the raw kernel
	var r4 := Part.replay(rec_for(30.0, 50.0, 50.0))
	var raw4 := KCad.cut(KCad.translate(A, Vector3(0.05, 0.05, 0.05)), KCad.translate(KCad.cylinder(0.03, 0.1), Vector3(0.05, 0.05, 0.05)))
	ok(String((r4["warnings"] as Dictionary).get("c1", "")) == "" and absf(float((r4["volumes"] as Array)[0]) - KCad.volume(raw4)) < 1e-9,
			"A4 CONTROL non-coincident cut: no words, volume %s vs raw %s" % [(r4["volumes"] as Array)[0], KCad.volume(raw4)])
	# A5 polish on a turned body, direct
	var ax := Vector3(1, 2, 3).normalized()
	var At := KCad.rotate(A, ax, 0.7)
	var Ct := KCad.rotate(cyl, ax, 0.7)
	var rawt := KCad.cut(At, Ct)
	var p := BS.polish(At, Ct, "cut", rawt)
	var qp := BS.inspect(int(p["id"]))
	var dv := absf(KCad.volume(int(p["id"])) - (cube_v - PI * 0.05 * 0.05 * 0.1)) / (cube_v - PI * 0.05 * 0.05 * 0.1)
	ok(int(qp["open"]) == 0 and dv <= 0.005 and maxf(absf((p["by"] as Vector3).x), maxf(absf((p["by"] as Vector3).y), absf((p["by"] as Vector3).z))) <= 1.0001e-5 and bool(p["nudged"]),
			"A5 turned body: open %s, vol err %.4f %%, by %s" % [qp["open"], dv * 100.0, p["by"]])
	await process_frame


func make_plate_and_tools(n: int) -> Array:
	var plate := KCad.box(0.4, 0.4, 0.02)
	var tools: Array = []
	for i in n:
		var x := -0.17 + 0.034 * (i % 11)
		var y := -0.17 + 0.034 * (i / 11)
		tools.append(KCad.translate(KCad.cylinder(0.01, 0.04), Vector3(x, y, 0)))
	return [plate, tools]


func vhash(id: int) -> int:
	var m := KCad.tessellate(id, 0.001)
	var h := 7
	for s in m.get_surface_count():
		h = hash([h, hash(m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])])
	return h


func bars_b() -> void:
	root.size = Vector2i(1280, 720)
	await process_frame
	# B0 idle
	var gaps: Array = []
	var t := Time.get_ticks_usec()
	for i in 40:
		await process_frame
		var n := Time.get_ticks_usec()
		gaps.append((n - t) / 1000.0)
		t = n
	gaps.sort()
	var idle: float = gaps[gaps.size() / 2]
	print("B0 idle frame median %.2f ms" % idle)
	var pt := make_plate_and_tools(60)
	var plate: int = pt[0]
	var tools: Array = pt[1]
	# synchronous control
	var s0 := Time.get_ticks_usec()
	var cur := plate
	for tl in tools:
		var nx := BS.polish(cur, tl, "cut")
		if cur != plate:
			KCad.release(cur)
		cur = int(nx["id"])
	var sync_ms := (Time.get_ticks_usec() - s0) / 1000.0
	var sync_vol := KCad.volume(cur)
	print("sync total %.1f ms, volume %s" % [sync_ms, sync_vol])
	# job, with a frame-gap probe
	var holder := Control.new()
	holder.size = Vector2(1280, 720)
	root.add_child(holder)
	var ui: Control = BUI.new()
	ui.position = Vector2(20, 20)
	holder.add_child(ui)
	var job := {"cancel": false}
	var calls: Array = []
	job["on_progress"] = func(d, tt, txt):
		calls.append([d, tt])
		ui.set_progress(d, tt, txt)
	ui.cancel_pressed.connect(func(): job["cancel"] = true)
	var mg := [0.0]
	var probing := [true]
	var last := [Time.get_ticks_usec()]
	var cb := func():
		if probing[0]:
			var n := Time.get_ticks_usec()
			mg[0] = maxf(mg[0], (n - last[0]) / 1000.0)
			last[0] = n
	process_frame.connect(cb)
	var res: Dictionary = await BS.run_job(self, plate, tools, "cut", job)
	probing[0] = false
	process_frame.disconnect(cb)
	var maxgap: float = mg[0]
	ok(maxgap <= 0.5 * sync_ms, "B1 FRAME GAP: longest %.1f ms <= 0.5 x sync %.1f ms (= %.1f x the idle %.2f ms); CONTROL the sync loop's gap %.1f ms %s the bar" % [maxgap, sync_ms, maxgap / idle, idle, sync_ms, "fails" if sync_ms > 0.5 * sync_ms else "passes"])
	var mono := true
	for i in range(1, calls.size()):
		mono = mono and calls[i][0] >= calls[i - 1][0]
	ok(calls.size() == tools.size() + 1 and mono and calls[calls.size() - 1][0] == tools.size() and calls[calls.size() - 1][1] == tools.size(),
			"B2 PROGRESS: %d calls, monotonic %s, last %s" % [calls.size(), mono, calls[calls.size() - 1]])
	ok(res["ok"] and absf(KCad.volume(int(res["id"])) - sync_vol) < 1e-9, "B3 SAME ANSWER: job %s vs sync %s" % [KCad.volume(int(res["id"])), sync_vol])
	# B4 cancel by a real click
	ui.free()
	ui = BUI.new()
	ui.position = Vector2(20, 20)
	holder.add_child(ui)
	var job2 := {"cancel": false}
	var step := [0]
	job2["on_progress"] = func(d, tt, txt):
		step[0] = d
		ui.set_progress(d, tt, txt)
	ui.cancel_pressed.connect(func(): job2["cancel"] = true)
	var v0 := KCad.volume(plate)
	var h0 := vhash(plate)
	var live0 := KCad.live_count()
	var cancel_at := [-1]
	var fin := [null]
	var starter := func(): fin[0] = await BS.run_job(self, plate, tools, "cut", job2)
	starter.call()
	for k in 600:
		await process_frame
		if step[0] >= 5:
			break
	await process_frame
	var pc: Vector2 = ui.btn.get_global_rect().get_center()
	if step[0] >= 5:
		get_root().get_viewport().get_texture().get_image().save_png(OUT + "/busy.png") if DirAccess.make_dir_recursive_absolute(OUT) == OK else null
	for d in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = d
		e.position = pc
		e.global_position = pc
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if d else 0
		root.push_input(e)
		await process_frame
	cancel_at[0] = step[0]
	while fin[0] == null:
		await process_frame
	var r2: Dictionary = fin[0]
	ok(r2["cancelled"] and int(r2["id"]) == plate and step[0] - cancel_at[0] <= 2 and absf(KCad.volume(plate) - v0) == 0.0 and vhash(plate) == h0 and KCad.live_count() <= live0 + 0,
			"B4 CANCEL: cancelled %s, stopped at step %d (clicked at %d), id same %s, vol equal, hash equal %s, live %d -> %d" % [r2["cancelled"], step[0], cancel_at[0], int(r2["id"]) == plate, vhash(plate) == h0, live0, KCad.live_count()])
	ok(FileAccess.file_exists(OUT + "/busy.png"), "B5 SHOT saved " + OUT + "/busy.png")
