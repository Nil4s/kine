extends SceneTree
## godot --headless --path . -s tests/psplit_test.gd     (GAP 4 + 7: SPLIT by a plane, INTERSECT op, SHELL (wall thickness, open face), EXTRUDE TAPER: scripts/build/part.gd
## + part_ui.gd; needs the CAD DLL, else the no-DLL bar only). Every number in the record is mm. Bars, written before measuring:
##   1 SPLIT     a 100 mm cube (x, y, z 0..100) split by the Right plane at x = 50 mm: bodies = 2, each 5e-4 m3 within 1e-8, sum 1e-3
##   2 PLANE     the Right plane at x = 200 mm misses the cube: an error that names the plane; the bodies stay as they were (1, 1e-3)
##   3 INTERSECT the cube and a half box (x 0..50): op intersect gives 1 body of 5e-4 m3 within 1e-8
##   4 SHELL     100 x 60 x 40 mm box, wall 5 mm, the top face (+Z) open: closed form 100x60x40 - 90x50x35 = 82500 mm3 = 8.25e-5 m3 within 1 %
##   5 CLOSED    the same box with no face open (open ""): a closed cavity, volume = 240000 - 90x50x30 mm3 = 1.05e-4 m3 within 1 %
##   6 TAPER     100 x 60 mm extruded 40 mm with taper 11.4592 deg (0.2 rad): one closed body, 0 < volume < 2.4e-4 m3 (the untapered box)
##   7 SAVE      the record of bars 1-6 as JSON and back (save -> load): the same replay, the same volumes (1e-12)
##   8 NO DLL    Part.force_off: replay answers no bodies and an empty error list (runs with or without the DLL)
##   9 ORDER     a split then a shell replays with no failed step (the shell takes the newest body)
## UI bars (a 3D building project, real clicks on the Part ribbon, 1280 x 720): see ui_bars below.
const KCad := preload("res://scripts/kcad.gd")
const SHOT := "C:/Temp/claude/psplit"
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func cube(extra: Array) -> Dictionary:
	var rec := Part.make("Cube")
	rec["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [0, 0], "b": [100, 100]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 100.0, "both": false, "op": "new"},
	]
	for f in extra:
		rec["features"].append(f)
	return rec


func box_rec(extra: Array) -> Dictionary:   # 100 x 60 mm, 40 mm high (+Z)
	var rec := Part.make("Box")
	rec["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [0, 0], "b": [100, 60]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 40.0, "both": false, "op": "new"},
	]
	for f in extra:
		rec["features"].append(f)
	return rec


func _init() -> void:
	var split := {"t": "split", "id": "f3", "name": "Split1", "plane": "right", "at": 50.0}
	var r1 := Part.replay(cube([split]))
	if not Part.available():
		print("SKIP 1-7, 9: the CAD kernel is not available (" + KCad.last_error() + ")")
		var was := Part.force_off
		Part.force_off = true
		var nd := Part.replay(cube([split]))
		Part.force_off = was
		ok(int(nd["bodies"]) == 0 and (nd["errors"] as Dictionary).is_empty(), "8 NO DLL: no bodies, no errors (%s)" % nd["bodies"])
		print("PSPLIT ", "PASS" if fails == 0 else "FAIL %d" % fails)
		quit(1 if fails > 0 else 0)
		return

	# 1 SPLIT
	var v1: Array = r1["volumes"]
	ok(int(r1["bodies"]) == 2 and (r1["errors"] as Dictionary).is_empty() and v1.size() == 2 and absf(float(v1[0]) - 5e-4) < 1e-8 and absf(float(v1[1]) - 5e-4) < 1e-8 and absf(float(r1["volume"]) - 1e-3) < 1e-8,
			"1 SPLIT: bodies %s, volumes %s, errors %s" % [r1["bodies"], v1, r1["errors"]])

	# 2 PLANE misses
	var r2 := Part.replay(cube([{"t": "split", "id": "f3", "name": "Split1", "plane": "right", "at": 200.0}]))
	ok(int(r2["bodies"]) == 1 and absf(float(r2["volume"]) - 1e-3) < 1e-8 and String((r2["errors"] as Dictionary).get("f3", "")).contains("does not cut"),
			"2 PLANE: a plane that misses says so (%s), bodies %s" % [r2["errors"], r2["bodies"]])

	# 3 INTERSECT
	var half := {"t": "sketch", "id": "f3", "name": "Sketch2", "plane": "front", "ents": [{"k": "rect", "a": [0, 0], "b": [50, 100]}], "dims": []}
	var inter := {"t": "extrude", "id": "f4", "name": "Extrude2", "sketch": "f3", "dist": 100.0, "both": false, "op": "intersect"}
	var r3 := Part.replay(cube([half, inter]))
	ok(int(r3["bodies"]) == 1 and (r3["errors"] as Dictionary).is_empty() and absf(float(r3["volume"]) - 5e-4) < 1e-8,
			"3 INTERSECT: bodies %s, volume %s, errors %s" % [r3["bodies"], r3["volume"], r3["errors"]])

	# 4 SHELL, top open (+Z): 100x60x40 minus the cavity 90x50x35 (5 mm walls, the open top)
	var r4 := Part.replay(box_rec([{"t": "shell", "id": "f3", "name": "Shell1", "body": 0, "thick": 5.0, "open": "+z"}]))
	var want4 := 82500e-9
	ok((r4["errors"] as Dictionary).is_empty() and absf(float(r4["volume"]) / want4 - 1.0) < 0.01,
			"4 SHELL open top: volume %s, want %s (rel %s), errors %s" % [r4["volume"], want4, absf(float(r4["volume"]) / want4 - 1.0), r4["errors"]])

	# 5 SHELL closed: a closed cavity, walls 5 mm all round: 100x60x40 - 90x50x30
	var r5 := Part.replay(box_rec([{"t": "shell", "id": "f3", "name": "Shell1", "body": 0, "thick": 5.0, "open": ""}]))
	var want5 := (240000.0 - 90.0 * 50.0 * 30.0) * 1e-9
	ok((r5["errors"] as Dictionary).is_empty() and absf(float(r5["volume"]) / want5 - 1.0) < 0.01,
			"5 SHELL closed: volume %s, want %s, errors %s" % [r5["volume"], want5, r5["errors"]])

	# 6 TAPER
	var r6 := Part.replay(box_rec([]))
	var tr := box_rec([])
	(tr["features"][1] as Dictionary)["taper"] = rad_to_deg(0.2)
	var r6t := Part.replay(tr)
	var v_plain := float(r6["volume"])
	ok((r6t["errors"] as Dictionary).is_empty() and int(r6t["bodies"]) == 1 and float(r6t["volume"]) > 0.0 and float(r6t["volume"]) < v_plain and float(r6t["volume"]) < 2.4e-4,
			"6 TAPER 0.2 rad: volume %s (untapered %s), bodies %s, errors %s" % [r6t["volume"], v_plain, r6t["bodies"], r6t["errors"]])

	# 7 SAVE -> LOAD -> REPLAY
	var rec7 := cube([split, half, inter])
	var txt := JSON.stringify(Part.to_file(rec7))
	var back := Part.from_file(JSON.parse_string(txt))
	var a7 := Part.replay(rec7)
	var b7 := Part.replay(back)
	ok(back.get("features", []).size() == rec7["features"].size() and absf(float(a7["volume"]) - float(b7["volume"])) < 1e-12 and int(a7["bodies"]) == int(b7["bodies"]) and (b7["errors"] as Dictionary).is_empty(),
			"7 SAVE/LOAD: %d features kept, volume %s vs %s, bodies %s vs %s" % [back.get("features", []).size(), a7["volume"], b7["volume"], a7["bodies"], b7["bodies"]])

	# 9 ORDER: split then shell (the shell takes the newest body, the right half)
	var r9 := Part.replay(cube([split, {"t": "shell", "id": "f4", "name": "Shell1", "body": 1, "thick": 5.0, "open": "+x"}]))
	ok((r9["errors"] as Dictionary).is_empty() and int(r9["bodies"]) == 2 and float(r9["volume"]) < 1e-3,
			"9 ORDER split then shell: no failed step, bodies %s, volume %s, errors %s" % [r9["bodies"], r9["volume"], r9["errors"]])

	# 8 NO DLL
	var was := Part.force_off
	Part.force_off = true
	var nd := Part.replay(cube([split]))
	Part.force_off = was
	ok(int(nd["bodies"]) == 0 and (nd["errors"] as Dictionary).is_empty(), "8 NO DLL: no bodies, no errors")

	await ui_bars()
	print("PSPLIT ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


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
	await idle(2)


## UI bars: the Part ribbon on a 3D building project, real clicks at 1280 x 720. Needs a window (the shot); headless = SKIP.
##   10 RIBBON   Split (CREATE ribbon) clicked, typed 50 mm, OK clicked: ONE undo step; 2 bodies of 5e-4 m3 each; the timeline's last step is a split
##   11 UNDO     undo: 1 body of 1e-3 m3; redo: 2 bodies again
##   12 SHELL    after the undo, Shell (MODIFY ribbon) clicked, 5 mm typed, its open face left at the default (+Y, top), OK clicked: ONE step;
##               volume = 1e-3 - 90 x 95 x 90 mm3 = 2.305e-4 m3 within 1 %
##   13 SHOT     C:/Temp/claude/psplit/shot.png: the split body in the Part view
func ui_bars() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP 10-13: no window (the ribbon clicks and the shot need one)")
		return
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
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	var dirt := "user://psplit_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dirt))
	ss.dirs_override = [dirt]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.S.part = cube([])
	if not pu.on:
		await click_ctl(pu.part_btn)
		await idle(3)
	pu._rebuild(true)
	await idle(2)
	var n0: int = m.undo.size()
	var sp: Button = pu.tool_btns["Split"]
	ok(sp.visible and not sp.disabled, "10 RIBBON: the Split button is on the ribbon and enabled")
	await click_ctl(sp)
	await idle(2)
	pu.f_num.text = "50 mm"
	pu._preview()
	await idle(2)
	ok(pu.ok_btn.disabled == false, "10 RIBBON: the dialog's OK is on (%s)" % pu.dlg_info.text)
	await click_ctl(pu.ok_btn)
	await idle(3)
	var feats: Array = m.S.part["features"]
	var v10: Array = pu.res.get("volumes", [])
	ok(m.undo.size() == n0 + 1 and feats[-1]["t"] == "split" and int(pu.res.get("bodies", 0)) == 2 and v10.size() == 2 and absf(float(v10[0]) - 5e-4) < 1e-8 and absf(float(v10[1]) - 5e-4) < 1e-8,
			"10 RIBBON: one undo step (%d -> %d), last step %s, bodies %s, volumes %s" % [n0, m.undo.size(), feats[-1]["t"], pu.res.get("bodies", 0), v10])
	await shot("shot_split")
	m._undo()
	await idle(3)
	ok(int(pu.res.get("bodies", 0)) == 1 and absf(float(pu.res.get("volume", 0.0)) - 1e-3) < 1e-8, "11 UNDO: one step back: 1 body of 1e-3 m3 (%s)" % pu.res.get("volume", 0.0))
	m._redo()
	await idle(3)
	ok(int(pu.res.get("bodies", 0)) == 2, "11 REDO: 2 bodies again")
	m._undo()
	await idle(3)
	var n1: int = m.undo.size()
	var sh: Button = pu.tool_btns["Shell"]
	await click_ctl(sh)
	await idle(2)
	pu.f_num.text = "5 mm"
	pu._preview()
	await idle(2)
	await click_ctl(pu.ok_btn)
	await idle(3)
	var want12 := 1e-3 - 90.0 * 95.0 * 90.0 * 1e-9
	var v12 := float(pu.res.get("volume", 0.0))
	ok(m.undo.size() == n1 + 1 and String(m.S.part["features"][-1]["t"]) == "shell" and absf(v12 / want12 - 1.0) < 0.01 and (pu.res.get("errors", {}) as Dictionary).is_empty(),
			"12 SHELL: one step, volume %s (want %s), errors %s" % [v12, want12, pu.res.get("errors", {})])
