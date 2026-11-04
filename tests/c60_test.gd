extends SceneTree
## godot --path . -s tests/c60_test.gd   (C60: Part layout settles - no panel changes size from frame to frame)
## BAR (written before any number was seen): for the Part browser and each side dialog (Extrude, Combine, Hinge, Fillet, Shell, Pattern, Sweep)
## at 1024x600, 1280x720, 1600x900: record the size of the browser and of the side panel every frame over 60 idle frames after open;
## max - min = 0 px in BOTH axes.  Control: the spread measure sees a planted wobble.  On origin the browser (24 <-> 223 px) and Extrude at 1024 (491 <-> 499) fail.
const Part := preload("res://scripts/build/part.gd")
const TOOLS := ["Extrude", "Combine", "Hinge", "Fillet", "Shell", "Pattern", "Sweep"]
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


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
	await idle(3)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())



func rec_of(fs: Array) -> Dictionary:
	var r := Part.make("c58")
	r["features"] = fs
	r["seq"] = 20
	return r


func feats() -> Array:
	return [
		{"t": "plane", "id": "p1", "name": "Ceiling plane", "from": "front", "mm": 60.0},
		{"t": "sketch", "id": "f2", "name": "S2", "plane": "p1", "ents": [{"k": "rect", "a": [-20.0, -20.0], "b": [60.0, 60.0]}], "dims": []},
		{"t": "extrude", "id": "f3", "name": "Ceiling", "sketch": "f2", "dist": 10.0, "both": false, "op": "new"},
		{"t": "sketch", "id": "f4", "name": "Profile", "plane": "front", "ents": [{"k": "rect", "a": [0.0, 0.0], "b": [20.0, 20.0]}], "dims": []},
		{"t": "extrude", "id": "f5", "name": "Pull", "sketch": "f4", "dist": 30.0, "both": false, "op": "new"},
	]


func set_part(fs: Array) -> void:
	var pu = m.bld.part
	m.S.part = rec_of(fs)
	pu.upto = -1
	pu.sync()
	await idle(16)


func set_size(w: int, h: int) -> void:
	root.content_scale_size = Vector2i(w, h)
	root.size = Vector2i(w, h)
	await idle(8)



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


func spread(a: Array) -> Vector2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for v in a:
		lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.y))
		hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.y))
	return hi - lo


func settle(pu, label: String, tool: String, sz: Vector2i, scen := "") -> void:
	pu.close_dialog()
	await idle(3)
	if tool != "":
		pu.open_dialog(tool, -1)
		await idle(3)
		if pu.dlg.is_empty():
			print("skip ", label, " (did not open)")
			return
	var bs := []
	var ss := []
	for i in 60:
		await process_frame
		bs.append(pu.browser.size)
		ss.append(pu.side.size)
	var tag := "%s %dx%d" % [label, sz.x, sz.y] + " " + scen
	var b := spread(bs)
	ok(b == Vector2.ZERO, "browser at %s: size spread %s over 60 frames (first %s last %s)" % [tag, str(b), str(bs[0]), str(bs[59])])
	if tool != "":
		var d := spread(ss)
		ok(d == Vector2.ZERO, "dialog at %s: size spread %s over 60 frames (first %s last %s)" % [tag, str(d), str(ss[0]), str(ss[59])])
	pu.close_dialog()


func _init() -> void:
	if not Part.available():
		print("SKIP: no KineCAD DLL")
		quit(0)
		return
	var wd := create_timer(900.0)   # watchdog
	wd.timeout.connect(func():
		print("FAIL watchdog: c60 took over 900 s")
		quit(2))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var ss: StartScreen = m.start_screen
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://c60_test"))
	ss.dirs_override = ["user://c60_test"]
	ss.show_screen()
	await idle(3)
	if ss._easy_btn["building"].button_pressed:
		await click_ctl(ss._easy_btn["building"])
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(4)
	await set_part(feats())
	ok(spread([Vector2(5, 5), Vector2(5, 9)]) == Vector2(0, 4), "CONTROL: the spread measure sees a planted 4 px wobble")
	for scen in ["feats", "cubes"]:
		if scen == "cubes":
			pu.close_dialog()
			m.S.part = cubes([0, 50])
			pu._rebuild(true)
			await idle(6)
		for sz in [Vector2i(1024, 600), Vector2i(1280, 720), Vector2i(1600, 900)]:
			await set_size(sz.x, sz.y)
			await settle(pu, "Part browser", "", sz, scen)
			for t in TOOLS:
				await settle(pu, t, t, sz, scen)
	print("c60: %d fail" % fails)
	quit(1 if fails > 0 else 0)
