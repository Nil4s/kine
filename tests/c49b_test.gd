extends SceneTree
## godot --path . --position 4000,4000 -s tests/c49b_test.gd     (C49b: the Off / Look / Print / Engineering warning strip sat over the top rows of the Part side dialogs)
## Bars (written before any number was read). Expert Part workspace, sizes 1024x600, 1280x720, 1600x900, each with a Part dialog open (Combine, Hinge, Extrude, Fillet, Shell) and with none:
##  1 OVERLAP  the strip (partwarn_panel) shares 0 px2 with the side dialog, the browser, the timeline and the view cube.  CONTROL: a planted overlapping pair reports > 0; the round-0 placement (left of the side panel) covers the browser at 1024 Extrude
##  2 REACH    every visible Button/Slider/LineEdit of the side panel has its centre in view and not under the strip
##  3 INSIDE   the strip is inside the view
##  4 CLICK    real clicks on Look, Print, Off, three rounds in a row (9 clicks): the level equals the clicked button every time and differs from before
##  5 DIALOG   a real click on Cancel closes; Extrude: a real click on OK closes it too
##  6 SEEN     at least 3 of 5 dialogs measured per size (not vacuous)
##  7 ONCE     the strip is placed per layout change, not per frame: 30 idle frames add 0 placements
##  8 NOCOLLAPSE no collapsed button, no ScrollContainer holding the level buttons
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c49b"
var fails := 0
var tag := "run"


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func cubes(x0s: Array) -> Dictionary:
	var rec := Part.make("Cubes")
	var feats: Array = []
	var k := 0
	for x0 in x0s:
		k += 1
		feats.append({"t": "sketch", "id": "s%d" % k, "name": "Sketch%d" % k, "plane": "front", "ents": [{"k": "rect", "a": [float(x0), 0.0], "b": [float(x0) + 100.0, 100.0]}], "dims": []})
		feats.append({"t": "extrude", "id": "e%d" % k, "name": "Extrude%d" % k, "sketch": "s%d" % k, "dist": 100.0, "both": false, "op": "new"})
	rec["features"] = feats
	return rec


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


func area(a: Rect2, b: Rect2) -> float:
	var r := a.intersection(b)
	return r.size.x * r.size.y if r.has_area() else 0.0


## the interactive controls of a node tree that are on screen
func controls(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Control and not (c as Control).is_visible_in_tree():
			continue
		if c is BaseButton or c is Range or c is LineEdit:
			out.append(c)
		controls(c, out)


## the visible Controls whose rect holds pt, in draw order (diagnostic for a click that did not land)
func over(n: Node, pt: Vector2, out: Array) -> void:
	for c in n.get_children():
		if c is Control and not (c as Control).visible:
			continue
		if c is Control and (c as Control).get_global_rect().has_point(pt) and (c as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			out.append(c)
		over(c, pt, out)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s_%s.png" % [SHOT, tag, nm])


func _init() -> void:
	if DisplayServer.get_name() == "headless" or not Part.available():
		print("SKIP: needs a window and the CAD DLL")
		quit(0)
		return
	var wd := Timer.new()   # watchdog: 6 minutes, then fail loudly instead of hanging
	wd.wait_time = 360.0
	wd.one_shot = true
	wd.autostart = true
	root.add_child(wd)
	wd.timeout.connect(func():
		print("FAIL watchdog: c49b ran over 360 s")
		quit(1))
	var t := OS.get_environment("C49B_TAG")
	if t != "":
		tag = t
	var pa := Rect2(0, 0, 100, 100)
	ok(area(pa, Rect2(50, 50, 100, 100)) > 0.0 and area(pa, Rect2(100, 0, 50, 50)) == 0.0, "1 CONTROL: the overlap measure sees a planted overlap (%.0f) and a planted miss (0)" % area(pa, Rect2(50, 50, 100, 100)))

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
	var dirt := "user://c49b_test"
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
	m.S.part = cubes([0, 50])
	if not pu.on:
		await click_ctl(pu.part_btn)
		await idle(3)
	pu._rebuild(true)
	await idle(3)
	print("setup: on %s chrome %s easy %s" % [pu.on, pu.chrome(), pu.easy])

	for sz in [Vector2i(1024, 600), Vector2i(1280, 720), Vector2i(1600, 900)]:
		root.content_scale_size = sz
		await idle(6)
		var vp := Rect2(Vector2.ZERO, Vector2(sz))
		var seen := 0
		for d in ["None", "Combine", "Hinge", "Extrude", "Fillet", "Shell"]:
			pu.close_dialog()
			await idle(2)
			if d != "None" and pu.tool_btns.has(d):
				await press_tool(m, pu, d)
			if pu.dlg.is_empty() and d == "Hinge":
				pu.open_dialog("hinge", -1)
			await idle(4)
			var wu: PartWarnUI = pu.warn_ui
			var label := "%dx%d %s" % [sz.x, sz.y, d]
			var dlg_on: bool = not pu.dlg.is_empty()
			if not wu.visible or (d != "None" and not dlg_on):
				print("note %s: dialog %s, strip %s -> not measured" % [label, dlg_on, wu.visible])
				continue
			if d != "None":
				seen += 1
			var sr: Rect2 = pu.side.get_global_rect() if pu.side.is_visible_in_tree() else Rect2()
			var wr := wu.get_global_rect()
			var br: Rect2 = pu.browser.get_global_rect()
			var cr: Rect2 = m.ui_cube.get_global_rect()
			var tr: Rect2 = m.ui_timeline.get_global_rect() if m.ui_timeline.is_visible_in_tree() else Rect2()
			var tot := area(wr, sr) + area(wr, br) + area(wr, tr) + area(wr, cr)
			ok(tot == 0.0, "1 OVERLAP %s: strip %s side %.0f browser %.0f timeline %.0f cube %.0f px2" % [label, wr, area(wr, sr), area(wr, br), area(wr, tr), area(wr, cr)])
			if sz.x == 1024 and d == "Extrude":
				var old_x := maxf(sr.position.x - 290.0 - 8.0, 8.0)
				var old := Rect2(old_x, 80.0, 290.0, wr.size.y)
				ok(area(old, br) > 0.0, "1 CONTROL: round-0 placement %s covers the browser %s (%.0f px2)" % [old, br, area(old, br)])
			var hidden := []
			var cs := []
			controls(pu.side, cs)
			for c in cs:
				var p: Vector2 = (c as Control).get_global_rect().get_center()
				if not vp.has_point(p) or wr.has_point(p):
					hidden.append(String(c.name) + "@" + str(p))
			ok(hidden.is_empty(), "2 REACH %s: %d side controls, covered/off-view %s" % [label, cs.size(), str(hidden)])
			ok(absf(area(wr, vp) - wr.size.x * wr.size.y) < 1.0, "3 INSIDE %s: strip %s in view" % [label, wr])
			var nsc := 0
			var stk := [wu]
			while not stk.is_empty():
				var n: Node = stk.pop_back()
				for c in n.get_children():
					stk.append(c)
					if c is ScrollContainer and (c as Node).is_ancestor_of(wu.lv_btns["off"]):
						nsc += 1
			ok(nsc == 0 and wu.get("compact_btn") == null, "8 NOCOLLAPSE %s: scroll holding the levels %d, compact button %s" % [label, nsc, wu.get("compact_btn")])
			var pl0: int = int(wu.get("places"))
			await idle(30)
			ok(int(wu.get("places")) == pl0, "7 ONCE %s: placements over 30 idle frames %d" % [label, int(wu.get("places")) - pl0])
			await shot("%dx%d_%s" % [sz.x, sz.y, d.to_lower()])
			var seq := ["look", "print", "off", "look", "print", "off", "look", "print", "off"]
			var okc := true
			var trace := []
			for lv in seq:
				var before: String = PartWarn.level_of(m.S.part)
				await click_ctl(wu.lv_btns[lv])
				var after: String = PartWarn.level_of(m.S.part)
				trace.append(after)
				if after != lv or after == before:
					okc = false
			ok(okc, "4 CLICK %s: levels after 9 clicks %s" % [label, str(trace)])
			if d != "None" and pu.cancel_btn != null and pu.cancel_btn.is_visible_in_tree():
				if d == "Extrude" and pu.ok_btn != null and pu.ok_btn.is_visible_in_tree():
					await click_ctl(pu.ok_btn)
					ok(pu.dlg.is_empty(), "5 DIALOG %s: a real click on OK closes the dialog" % label)
					await press_tool(m, pu, d)
					await idle(4)
				if not pu.dlg.is_empty():
					await click_ctl(pu.cancel_btn)
					ok(pu.dlg.is_empty(), "5 DIALOG %s: a real click on Cancel closes the dialog" % label)
		ok(seen >= 3, "6 SEEN %dx%d: %d of 5 dialogs measured" % [sz.x, sz.y, seen])
	print("C49b ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
