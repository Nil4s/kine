extends SceneTree
## godot --headless --path . -s tests/pcombine_test.gd     (COMBINE, Fusion Combine: a target body with tool bodies, Join / Cut / Intersect, keep tools:
## scripts/build/part.gd _combine_step + part_ui.gd COMBINE section; needs the CAD DLL, else the no-DLL bar only). Every number is mm in the record.
## Replay bars: 1 JOIN (two 100 mm cubes overlapping by 50 mm: 1.5e-3 m3), 2 CUT (5e-4), 3 INTERSECT (5e-4), 4 KEEP (tool body left: 2 bodies),
## 5 SAVE (JSON round trip), 6 LOOK (target keeps its look), 7 ERRORS (own tool, disjoint intersect, missing body), 8 MULTI (3 bodies: 2.2e-3), 9 NO DLL.
## UI bars (a 3D building project, real clicks on the Part ribbon, 1280 x 720; headless = SKIP): 10 RIBBON, 11 BROWSER, 12 VIEW (Cut, one undo step),
## 13 UNDO, 14 KEEP (intersect, tool kept), 15 SAVE UI, 16 SHOT (C:/Temp/claude/pcombine/shot.png).
const KCad := preload("res://scripts/kcad.gd")
const SHOT := "C:/Temp/claude/pcombine"
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


## one 100 mm cube per x0 in x0s (y 0..100, z 0..100); each one is a new body
func cubes(x0s: Array, extra: Array) -> Dictionary:
	var rec := Part.make("Cubes")
	var feats: Array = []
	var k := 0
	for x0 in x0s:
		k += 1
		feats.append({"t": "sketch", "id": "s%d" % k, "name": "Sketch%d" % k, "plane": "front", "ents": [{"k": "rect", "a": [float(x0), 0.0], "b": [float(x0) + 100.0, 100.0]}], "dims": []})
		feats.append({"t": "extrude", "id": "e%d" % k, "name": "Extrude%d" % k, "sketch": "s%d" % k, "dist": 100.0, "both": false, "op": "new"})
	rec["features"] = feats
	for f in extra:
		rec["features"].append(f)
	return rec


func comb(id: String, target: int, tools: Array, op: String, keep := false) -> Dictionary:
	return {"t": "combine", "id": id, "name": "Combine" + id, "target": target, "tools": tools, "op": op, "keep": keep}


func _init() -> void:
	if not Part.available():
		print("SKIP 1-8: the CAD kernel is not available (" + KCad.last_error() + ")")
		var was := Part.force_off
		Part.force_off = true
		var nd := Part.replay(cubes([0, 50], [comb("c1", 0, [1], "join")]))
		Part.force_off = was
		ok(int(nd["bodies"]) == 0 and (nd["errors"] as Dictionary).is_empty(), "9 NO DLL: no bodies, no errors (%s)" % nd["bodies"])
		await ui_bars()
		print("PCOMBINE ", "PASS" if fails == 0 else "FAIL %d" % fails)
		quit(1 if fails > 0 else 0)
		return

	# 1 JOIN
	var r1 := Part.replay(cubes([0, 50], [comb("c1", 0, [1], "join")]))
	var v1: Array = r1["volumes"]
	ok(int(r1["bodies"]) == 1 and (r1["errors"] as Dictionary).is_empty() and v1.size() == 1 and absf(float(v1[0]) - 1.5e-3) < 1e-8,
			"1 JOIN: bodies %s, volumes %s, errors %s" % [r1["bodies"], v1, r1["errors"]])

	# 2 CUT, 3 INTERSECT
	var r2 := Part.replay(cubes([0, 50], [comb("c1", 0, [1], "cut")]))
	var r3 := Part.replay(cubes([0, 50], [comb("c1", 0, [1], "intersect")]))
	ok(int(r2["bodies"]) == 1 and (r2["errors"] as Dictionary).is_empty() and absf(float((r2["volumes"] as Array)[0]) - 5e-4) < 1e-8,
			"2 CUT: bodies %s, volumes %s, errors %s" % [r2["bodies"], r2["volumes"], r2["errors"]])
	ok(int(r3["bodies"]) == 1 and (r3["errors"] as Dictionary).is_empty() and absf(float((r3["volumes"] as Array)[0]) - 5e-4) < 1e-8,
			"3 INTERSECT: bodies %s, volumes %s, errors %s" % [r3["bodies"], r3["volumes"], r3["errors"]])

	# 4 KEEP
	var rj := Part.replay(cubes([0, 50], [comb("c1", 0, [1], "join", true)]))
	var rc := Part.replay(cubes([0, 50], [comb("c1", 0, [1], "cut", true)]))
	var vj: Array = rj["volumes"]
	var vc: Array = rc["volumes"]
	ok(int(rj["bodies"]) == 2 and vj.size() == 2 and absf(float(vj[0]) - 1.5e-3) < 1e-8 and absf(float(vj[1]) - 1e-3) < 1e-8,
			"4 KEEP join: bodies %s, volumes %s, errors %s" % [rj["bodies"], vj, rj["errors"]])
	ok(int(rc["bodies"]) == 2 and vc.size() == 2 and absf(float(vc[0]) - 5e-4) < 1e-8 and absf(float(vc[1]) - 1e-3) < 1e-8,
			"4 KEEP cut: bodies %s, volumes %s, errors %s" % [rc["bodies"], vc, rc["errors"]])

	# 5 SAVE -> LOAD -> REPLAY
	var rec5 := cubes([0, 50], [comb("c1", 0, [1], "join", true)])
	var back := Part.from_file(JSON.parse_string(JSON.stringify(Part.to_file(rec5))))
	var b5 := Part.replay(back)
	ok(back.get("features", []).size() == rec5["features"].size() and int(b5["bodies"]) == 2 and absf(float(b5["volume"]) - (float(vj[0]) + float(vj[1]))) < 1e-12 and (b5["errors"] as Dictionary).is_empty(),
			"5 SAVE/LOAD: %d features, bodies %s, volume %s" % [back.get("features", []).size(), b5["bodies"], b5["volume"]])

	# 6 LOOK: the target's look is kept; the tool's look goes with the tool (no keep)
	var red := {"t": "appear", "id": "a1", "name": "Appearance1", "body": 0, "preset": "Paint", "color": [0.75, 0.1, 0.1], "rough": 0.35, "metal": 0.0, "alpha": 1.0}
	var r6 := Part.replay(cubes([0, 50], [red, comb("c1", 0, [1], "join")]))
	var bl6: Array = r6["body_looks"]
	ok(int(r6["bodies"]) == 1 and bl6.size() == 1 and (bl6[0]["c"] as Color).is_equal_approx(Color(0.75, 0.1, 0.1)), "6 LOOK target keeps red: bodies %s, looks %s" % [r6["bodies"], bl6])
	var blue := {"t": "appear", "id": "a1", "name": "Appearance1", "body": 1, "preset": "Paint", "color": [0.1, 0.2, 0.8], "rough": 0.35, "metal": 0.0, "alpha": 1.0}
	var r6c := Part.replay(cubes([0, 50], [blue, comb("c1", 1, [0], "join")]))
	var bl6c: Array = r6c["body_looks"]
	ok(int(r6c["bodies"]) == 1 and bl6c.size() == 1 and (bl6c[0]["c"] as Color).is_equal_approx(Color(0.1, 0.2, 0.8)), "6 LOOK target 1 keeps blue: looks %s, errors %s" % [bl6c, r6c["errors"]])

	# 7 ERRORS
	var r7a := Part.replay(cubes([0, 50], [comb("c1", 0, [0], "join")]))
	var r7b := Part.replay(cubes([0, 200], [comb("c1", 0, [1], "intersect")]))
	var r7c := Part.replay(cubes([0, 50], [comb("c1", 0, [7], "join")]))
	ok(String((r7a["errors"] as Dictionary).get("c1", "")) != "" and int(r7a["bodies"]) == 2 and absf(float(r7a["volume"]) - 2e-3) < 1e-8,
			"7 ERRORS own tool: %s, bodies %s" % [r7a["errors"], r7a["bodies"]])
	ok(String((r7b["errors"] as Dictionary).get("c1", "")) != "" and int(r7b["bodies"]) == 2 and absf(float(r7b["volume"]) - 2e-3) < 1e-8,
			"7 ERRORS disjoint intersect: %s, bodies %s" % [r7b["errors"], r7b["bodies"]])
	ok(String((r7c["errors"] as Dictionary).get("c1", "")) != "" and int(r7c["bodies"]) == 2,
			"7 ERRORS no body 7: %s" % r7c["errors"])

	# 8 MULTI: A (0..100), B (50..150), C (120..220) joined: one slab 0..220 = 2.2e-3
	var r8 := Part.replay(cubes([0, 50, 120], [comb("c1", 0, [1, 2], "join")]))
	ok(int(r8["bodies"]) == 1 and (r8["errors"] as Dictionary).is_empty() and absf(float((r8["volumes"] as Array)[0]) - 2.2e-3) < 1e-8,
			"8 MULTI: bodies %s, volumes %s, errors %s" % [r8["bodies"], r8["volumes"], r8["errors"]])

	# 9 NO DLL (the kernel is here: the same record with the DLL turned off)
	var was := Part.force_off
	Part.force_off = true
	var nd := Part.replay(cubes([0, 50], [comb("c1", 0, [1], "join")]))
	Part.force_off = was
	ok(int(nd["bodies"]) == 0 and (nd["errors"] as Dictionary).is_empty(), "9 NO DLL: no bodies, no errors")

	await ui_bars()
	print("PCOMBINE ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)


## a tool by name: its own button when it shows on the row, else its caption menu's item (the same as a press on the menu)
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


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


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


## a screen point where the view hits body bi itself (a triangle centre of its faces): body 0 from its far left, body 1 from its far right
func view_point(m: Node, pu: PartUI, bi: int) -> Vector2:
	var best := Vector2(-1, -1)
	var best_d := -INF
	var tris: PackedVector3Array = pu.cmb_faces[bi]
	var screen := Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size))
	for k in range(0, tris.size() - 2, 3):
		var c: Vector3 = (tris[k] + tris[k + 1] + tris[k + 2]) / 3.0
		if m.cam.is_position_behind(c):
			continue
		var sp: Vector2 = m.cam.unproject_position(c)
		if not screen.has_point(sp):
			continue
		if int(pu._ray_hit(sp, pu.cmb_faces).get("body", -1)) != bi:
			continue
		var d := -c.x if bi == 0 else c.x
		if d > best_d:
			best_d = d
			best = sp
	return best


## UI bars: the Part ribbon on a 3D building project, real clicks at 1280 x 720. Headless = SKIP.
func ui_bars() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP 10-16: no window (the ribbon clicks and the shot need one)")
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
	var dirt := "user://pcombine_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dirt))
	ss.dirs_override = [dirt]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	# Nick 2026-10-28 (free 3D building, #100): the BUILDING card now opens a blank Easy Part itself. Start from the
	# state the card gave before (Part off, no part), so the clicks below drive the same opening they always did
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	m.S.part = cubes([0, 50], [])
	if not pu.on:
		await click_ctl(pu.part_btn)
		await idle(3)
	pu._rebuild(true)
	await idle(3)

	# 10 RIBBON
	var cb: Button = pu.tool_btns["Combine"]
	ok(not cb.disabled, "10 RIBBON: the Combine button is on and enabled (two bodies)")
	await press_tool(m, pu, "Combine")
	await idle(2)
	ok(String(pu.dlg.get("t", "")) == "combine" and pu.ok_btn.disabled, "10 RIBBON: the combine dialog opens, OK off (%s)" % pu.dlg_info.text)

	# 11 BROWSER
	await click_ctl(pu.browser.find_child("part_body_0", true, false))
	await idle(2)
	await click_ctl(pu.browser.find_child("part_body_1", true, false))
	await idle(2)
	var pv11 := float(pu.prev.get("volume", 0.0)) if not pu.prev.is_empty() else -1.0
	ok(int(pu.cmb.get("target", -1)) == 0 and (pu.cmb.get("tools", []) as Array) == [1] and not pu.ok_btn.disabled and absf(pv11 - 1.5e-3) < 1e-8,
			"11 BROWSER: target Body1, tool Body2, OK on, preview %s m3 (%s)" % [pv11, pu.dlg_info.text])

	# 12 VIEW: Combine again (a fresh dialog), Cut, both bodies clicked on their faces
	await press_tool(m, pu, "Combine")
	await idle(2)
	pu._view_plane("front")
	await idle(4)
	var p0 := view_point(m, pu, 0)
	var p1 := view_point(m, pu, 1)
	ok(p0.x >= 0 and p1.x >= 0, "12 VIEW: both bodies show a face in the front view (%s, %s)" % [p0, p1])
	await click_at(p0)
	await idle(2)
	await click_at(p1)
	await idle(2)
	ok(int(pu.cmb.get("target", -1)) == 0 and (pu.cmb.get("tools", []) as Array) == [1], "12 VIEW: the view clicks picked Body1 (target) and Body2 (tool): %s" % [pu.cmb])
	pu.f_cmb_op.select(1)
	pu.f_cmb_op.item_selected.emit(1)
	await idle(2)
	ok(not pu.ok_btn.disabled, "12 VIEW: Cut is on (%s)" % pu.dlg_info.text)
	var n12: int = m.undo.size()
	await click_ctl(pu.ok_btn)
	await idle(3)
	var feats: Array = m.S.part["features"]
	var v12: Array = pu.res.get("volumes", [])
	ok(m.undo.size() == n12 + 1 and String(feats[-1]["t"]) == "combine" and int(pu.res.get("bodies", 0)) == 1 and v12.size() == 1 and absf(float(v12[0]) - 5e-4) < 1e-8,
			"12 VIEW: one undo step (%d -> %d), last step %s, bodies %s, volumes %s" % [n12, m.undo.size(), feats[-1]["t"], pu.res.get("bodies", 0), v12])

	# 13 UNDO / REDO
	m._undo()
	await idle(3)
	ok(int(pu.res.get("bodies", 0)) == 2 and absf(float(pu.res.get("volume", 0.0)) - 2e-3) < 1e-8, "13 UNDO: back to 2 bodies, 2e-3 m3 (%s)" % pu.res.get("volume", 0.0))
	m._redo()
	await idle(3)
	ok(int(pu.res.get("bodies", 0)) == 1, "13 REDO: 1 body again")
	m._undo()
	await idle(3)

	# 14 KEEP: Intersect, target Body2 by its row, tool Body1 in the view, keep tools
	await press_tool(m, pu, "Combine")
	await idle(2)
	await click_ctl(pu.browser.find_child("part_body_1", true, false))
	await idle(2)
	await click_at(view_point(m, pu, 0))
	await idle(2)
	pu.f_cmb_op.select(2)
	pu.f_cmb_op.item_selected.emit(2)
	pu.f_cmb_keep.button_pressed = true
	pu.f_cmb_keep.toggled.emit(true)
	await idle(2)
	var n14: int = m.undo.size()
	await click_ctl(pu.ok_btn)
	await idle(3)
	var v14: Array = pu.res.get("volumes", [])
	ok(m.undo.size() == n14 + 1 and int(pu.res.get("bodies", 0)) == 2 and v14.size() == 2 and absf(float(v14[0]) - 1e-3) < 1e-8 and absf(float(v14[1]) - 5e-4) < 1e-8,
			"14 KEEP: intersect with keep: one step, bodies %s, volumes %s (Body1 kept at 0, the result in Body2's place at 1)" % [pu.res.get("bodies", 0), v14])

	# 15 SAVE: the record as a file and back
	var back2: Dictionary = Part.from_file(JSON.parse_string(JSON.stringify(Part.to_file(m.S.part))))
	var rb := Part.replay(back2)
	ok(int(rb["bodies"]) == 2 and absf(float(rb["volume"]) - float(pu.res.get("volume", 0.0))) < 1e-12, "15 SAVE: the saved record replays the same (bodies %s, volume %s)" % [rb["bodies"], rb["volume"]])
	await shot("shot")
	ok(FileAccess.file_exists(SHOT + "/shot.png"), "16 SHOT: %s/shot.png written" % SHOT)
