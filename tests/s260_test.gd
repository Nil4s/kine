extends SceneTree
## s260 CURVE EXTRAPOLATION (ledger 260). Curves.eval gets a per-curve mode: constant (default, = the old read), linear, cycle.
## A hinge feature carries "extrap" only when not constant; its dialog has an "After the last key" choice (Hold / Continue / Repeat).
## Bars (written before the code ran), curve [[0,0],[3,90]] (30 deg/s), one frame = 1/30 s:
##   1 LINEAR   one frame after the last key = 91.0 deg (90 + 30/30); one frame before the first key = -1.0
##   2 CYCLE    at t = 6 (one loop past the end) the first key's value 0.0; at 3 + 1/30 it is 1.0 (the loop restarted)
##   3 CONSTANT default and "constant": 90.0 after the end, identical to the old eval on 200 sampled times
##   4 SAVED    a constant hinge's dict has no "extrap" key (same JSON as before); linear/cycle carry it
##   CONTROL    the old eval (no mode) one frame after the end gives 90.0, which FAILS bar 1 (and 2): the bars can fail
##   5 UI       the dialog choice, one undo step (see ui_bars)
const SHOT_UI := "C:/Users/Nick/tools/kine_workers/out/s260"
const DIR_UI := "user://s260_test"

var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func _init() -> void:
	var tr: Array = [[0.0, 0.0], [3.0, 90.0]]
	var fr := 1.0 / 30.0
	var lin := float(Curves.eval(tr, 3.0 + fr, "linear"))
	var pre := float(Curves.eval(tr, -fr, "linear"))
	ok(absf(lin - 91.0) < 1e-4 and absf(pre + 1.0) < 1e-4, "1 LINEAR: after the end %.4f (91), before the start %.4f (-1)" % [lin, pre])
	var c6 := float(Curves.eval(tr, 6.0, "cycle"))
	var c1 := float(Curves.eval(tr, 3.0 + fr, "cycle"))
	ok(absf(c6) < 1e-4 and absf(c1 - 1.0) < 1e-4, "2 CYCLE: t=6 -> %.4f (0), t=3+1/30 -> %.4f (1)" % [c6, c1])
	var same := true
	for i in 200:
		var t := -2.0 + float(i) * 0.04
		if float(Curves.eval(tr, t)) != float(Curves.eval(tr, t, "constant")):
			same = false
	ok(same and float(Curves.eval(tr, 3.0 + fr)) == 90.0, "3 CONSTANT: default = explicit constant, holds 90 after the end")
	var f0 := {"t": "hinge", "track": tr}
	ok(not f0.has("extrap") and Curves.mode_of(f0) == "constant" and Curves.mode_of({"extrap": "cycle"}) == "cycle" and Curves.mode_of({"extrap": "junk"}) == "constant",
			"4 SAVED: constant dict has no extrap key; modes read back; junk reads as constant")
	var old := float(Curves.eval(tr, 3.0 + fr))
	ok(not (absf(old - 91.0) < 1e-4) and not (absf(float(Curves.eval(tr, 3.0 + fr)) - 1.0) < 1e-4), "CONTROL: the old (hold) eval gives %.1f, which fails the linear and cycle bars" % old)
	await ui_bars()
	print("S260 ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)


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


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_at(p: Vector2) -> void:
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func shot_ui(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT_UI)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT_UI, nm])




func ui_bars() -> void:
	if not Part.available():
		print("SKIP 5-6: the CAD kernel is not available")
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
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR_UI))
	ss.dirs_override = [DIR_UI]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	m.S.part = Part.make("Lid")
	m.S.part["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [0, -20], "b": [800, 20]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 2000.0, "both": false, "op": "new"},
	]
	m.S.part["seq"] = 2
	await click_ctl(pu.part_btn)
	await idle(3)
	pu._view_model()
	await idle(3)
	var rec_before: int = (m.S.part["features"] as Array).size()
	var n0: int = m.undo.size()
	var b: Button = pu.tool_btns["Hinge"]
	if b.is_visible_in_tree():
		await click_ctl(b)
	else:
		await click_ctl(m.ui_more)
		m.ui_more.get_popup().hide()
		m._more_pick(m._more_tools.find(b))
		await idle(2)
	# the lid: its centre, then its edge nearest the corner (0, -20, z 0..2000 mm)
	var lid_tris: PackedVector3Array = Part.body_faces(m.S.part, -1)[0]
	var lid_pt := Vector3.ZERO
	for v in lid_tris:
		lid_pt += v / float(lid_tris.size())
	await click_at(m.cam.unproject_position(lid_pt))
	var best := -1
	var best_d := INF
	for i in pu.edge_cache.size():
		var e: Dictionary = pu.edge_cache[i]
		if int(e["body"]) != 0 or (e["a"] as Vector3).distance_to(e["b"] as Vector3) < 1e-6:
			continue
		var dd := (e["c"] as Vector3).distance_to(Vector3(0.0, -0.02, 1.0))
		if dd < best_d:
			best_d = dd
			best = i
	if best >= 0:
		await click_at(m.cam.unproject_position((pu.edge_cache[best] as Dictionary)["c"]))
	# 5 UI: the "After the last key" choice is in the dialog; Repeat picked; OK = ONE undo step; saved with the key only now
	var ob: OptionButton = pu.dlg_rows.find_child("part_extrap", true, false)
	var row_ok := ob != null and ob.is_visible_in_tree() and ob.selected == 0
	ok(row_ok, "5 UI: the choice is shown, default Hold")
	if row_ok:
		await click_ctl(ob)
		ob.get_popup().hide()
		ob.select(2)
		ob.item_selected.emit(2)
	await idle(2)
	await shot_ui("extrap_dialog_%dx%d" % [root.size.x, root.size.y])
	await click_ctl(pu.ok_btn)
	await idle(3)
	var feats: Array = m.S.part["features"]
	var hf: Dictionary = feats[-1] if not feats.is_empty() else {}
	ok(feats.size() == rec_before + 1 and String(hf.get("extrap", "")) == "cycle" and m.undo.size() == n0 + 1,
			"5 UI: one hinge step, extrap %s (cycle), %d undo step" % [hf.get("extrap", "?"), m.undo.size() - n0])
	var cyc := float(Curves.eval(hf["track"], 3.0 + 1.0 / 30.0, Curves.mode_of(hf)))
	ok(absf(cyc - 1.0) < 0.01, "5 UI: the saved hinge repeats: %.3f deg a frame past the end (1.0)" % cyc)
	m._undo()
	await idle(2)
	ok((m.S.part["features"] as Array).size() == rec_before, "5 UI: one Ctrl+Z takes the hinge away")
	m.queue_free()
	await idle(2)
