extends SceneTree
## godot --path . --position 4000,4000 -s tests/replaygap_test.gd     (REPLAYGAP: duplicate Part.replay calls in one Easy Part press; scripts/easy_part.gd + scripts/build/part_ui.gd; needs a window and the CAD DLL)
## Real clicks and drags at 1280 x 720 from the real start screen: a 3D BUILDING project, Expert's Part button, its Easy button, then 30 Easy presses
## (Draw shape, Pull it up, Round the edges, Cut a hole, Mirror that, Repeat it, then Draw, Pull, Round, Hole again). Part.replay is not changed:
## a probe (Part.calls_log, off unless set) records each call's record hash, step, wants and caller.
## Bars:
##   1 BOOT      the building project opens in Easy Part with the CAD DLL
##   2 DUPS      in every press, no record is replayed twice (a keep replay is not counted: it returns kept solids that must be released)
##   3 SAME      after every press the shown part (pu.res) equals a fresh replay of the record (volume, bodies, error keys); at every press the volume, bodies,
##               error count and feature count equal the baseline written by the run before the fix (C:/Temp/claude/replaygap/baseline_old.txt, written only if absent)
##   4 STEPS     the 30 presses all happen
## Writes C:/Temp/claude/replaygap/table.csv (press, kind, feats, ms, replays, dup, fingerprint) and shot.png. Press times are printed as TABLE lines.

const SHOT := "C:/Temp/claude/replaygap"
const DIRT := "user://replaygap_test"
const STEPS := 30
const SEQ := ["draw", "pull", "round", "hole", "mirror", "repeat"]
const CYC := ["draw", "pull", "round", "hole"]
var fails := 0
var m: Node
var rows := []


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
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


## a click on a control: the commit is the release, timed to two frames after it (ms)
func press(c: Control) -> float:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	var t0 := Time.get_ticks_usec()
	await ev_mouse(p, false)
	await process_frame
	await process_frame
	return (Time.get_ticks_usec() - t0) / 1000.0


func draw_floor(a: Vector3, b: Vector3) -> float:
	var pa := scr(a)
	var pb := scr(b)
	await ev_move(pa, false)
	await ev_mouse(pa, true)
	for i in range(1, 13):
		await ev_move(pa.lerp(pb, i / 12.0))
	var t0 := Time.get_ticks_usec()
	await ev_mouse(pb, false)
	await process_frame
	await process_frame
	return (Time.get_ticks_usec() - t0) / 1000.0


## the largest number of non-keep replays of one record in a press's log
func dup_max(log: Array) -> int:
	var cnt := {}
	var mx := 0
	for c in log:
		if String(c[2]).find("keep") >= 0:
			continue
		var k := String(c[0]) + "|" + String(c[1])
		cnt[k] = int(cnt.get(k, 0)) + 1
		mx = maxi(mx, int(cnt[k]))
	return mx


func fp_of(rec: Dictionary, r: Dictionary) -> String:
	return "%s|%s|%s|%s|%s" % [str(hash(JSON.stringify(rec.get("features", [])))), str(snappedf(float(r["volume"]) * 1e9, 0.1)), str(r["bodies"]), str(r["errors"].size()), str((rec.get("features", []) as Array).size())]


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
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await press(ss._cards["building"])
	await idle(3)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	ok(Part.available(), "1 BOOT the CAD DLL is there")
	if not Part.available():
		quit(1)
		return
	await press(pu().part_btn)
	await idle(3)
	await press(pu().easy_open_btn)
	await idle(4)
	m.S.part = Part.make("Part")
	pu().upto = -1
	pu().sync()
	m.target = Vector3(0.0, 0.0, 0.0)
	m.pitch = -40.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	var i := 0
	var cyc := 0
	var dup_bad := 0
	var same_bad := 0
	var fps := []
	while rows.size() < STEPS and cyc < 20:
		var kind: String = SEQ[i] if i < SEQ.size() else CYC[(i - SEQ.size()) % CYC.size()]
		i += 1
		var ms := 0.0
		Part.calls_log = []
		match kind:
			"draw":
				await press(ep().make_btns["draw"])
				var x := -0.12 + 0.06 * float(cyc % 5)
				var z := -0.06 + 0.08 * float(cyc % 3)
				ms = await draw_floor(Vector3(x, 0.0, z), Vector3(x + 0.04, 0.0, z + 0.04))
			_:
				ms = await press(ep().make_btns[kind])
		var log: Array = Part.calls_log
		Part.calls_log = null
		cyc = i / 4
		var rec: Dictionary = ep()._rec()
		var fresh := Part.replay(rec)
		var same := absf(float(pu().res["volume"]) - float(fresh["volume"])) < 1e-9 and int(pu().res["bodies"]) == int(fresh["bodies"]) and (pu().res["errors"] as Dictionary).keys() == (fresh["errors"] as Dictionary).keys()
		var dmax := dup_max(log)
		var nrep := 0
		for c in log:
			if String(c[2]).find("keep") < 0:
				nrep += 1
		var fp := fp_of(rec, fresh)
		fps.append(fp)
		if dmax > 1:
			dup_bad += 1
		if not same:
			same_bad += 1
		rows.append({"kind": kind, "feats": (rec.get("features", []) as Array).size(), "ms": ms, "replays": nrep, "dup": dmax, "fp": fp})
		print("TABLE %d %s feats %d ms %.1f replays %d dup %d same %s" % [rows.size(), kind, rows[-1]["feats"], ms, nrep, dmax, str(same)])
		for c in log:
			print("  CALL %s upto=%s want=%s from=%s:%s" % c)
		if rows.size() == STEPS:
			DirAccess.make_dir_recursive_absolute(SHOT)
			await idle(3)
			root.get_texture().get_image().save_png("%s/shot.png" % SHOT)
	ok(rows.size() == STEPS, "4 STEPS the %d presses all happened (%d)" % [STEPS, rows.size()])
	ok(dup_bad == 0, "2 DUPS no press replays a record twice (%d presses with a duplicate)" % dup_bad)
	ok(same_bad == 0, "3a SAME the shown part equals a fresh replay after every press (%d differ)" % same_bad)
	var base := "%s/baseline_old.txt" % SHOT
	if FileAccess.file_exists(base):
		var blines := FileAccess.get_file_as_string(base).split("\n")
		# volume, bodies, error count and feature count at every press are the same as the baseline. The feature JSON hash is printed, not barred:
		# the Round search is time-budgeted (EROUND ROUND_BUDGET_US), so the edges it picks differ run to run on the old code too
		var base_ok := blines.size() >= STEPS
		var hash_same := 0
		for k in STEPS:
			if k >= blines.size():
				break
			var b := blines[k].split("|")
			var c := String(fps[k]).split("|")
			base_ok = base_ok and b.slice(1) == c.slice(1)
			hash_same += 1 if b[0] == c[0] else 0
		ok(base_ok, "3b SAME volume, bodies, error count and feature count at each of the %d presses are the same as the baseline (before the fix)" % STEPS)
		print("INFO feature hash equal to the baseline at %d of %d presses (time-budgeted Round may differ)" % [hash_same, STEPS])
	else:
		var g := FileAccess.open(base, FileAccess.WRITE)
		g.store_string("\n".join(fps) + "\n")
		g.close()
		print("baseline written: %s" % base)
	var lines := ["press,kind,feats,ms,replays,dup,fp"]
	for k in rows.size():
		var r: Dictionary = rows[k]
		lines.append("%d,%s,%d,%.1f,%d,%d,%s" % [k + 1, r["kind"], r["feats"], r["ms"], r["replays"], r["dup"], r["fp"]])
	var f := FileAccess.open("%s/table.csv" % SHOT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	print("replaygap: %d fail" % fails)
	quit(1 if fails > 0 else 0)
