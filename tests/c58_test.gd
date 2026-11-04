extends SceneTree
## godot --path . -s tests/c58_test.gd   (C58: every Part side dialog keeps OK and Cancel visible and clickable at 1024x600 and 1280x720)
## BARS, written before any number was seen. For every tool open_dialog can open, at both sizes:
##   1 CANCEL/OK  both buttons lie inside the window, overlap the timeline by 0 px2, and a pointer on each one is over THAT button (gui_get_hovered_control)
##   2 CLICK      a real click on Cancel closes the dialog (dlg empty)
##   3 PANEL      the side panel's own rect overlaps the timeline by 0 px2
##   4 ROWS       every row is reachable: after scrolling to it, it lies inside the window, clear of the timeline (the scroll box is part_dialog_scroll)
##   Control: on origin Extrude at 1024x600 FAILS bars 1 and 2 (the timeline eats the click).
const Part := preload("res://scripts/build/part.gd")
const OUT := "C:/Users/Nick/tools/kine_workers/out/c58"
const TOOLS := ["Extrude", "Revolve", "Loft", "Sweep", "Pattern", "Offset plane", "Primitive", "Fillet", "Chamfer", "Offset face", "Draft", "Hinge", "Roof shell", "Mirror", "Split", "Shell", "Combine", "Canvas"]
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


func shot(nm: String) -> void:
	await idle(3)
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, nm])


func set_part(fs: Array) -> void:
	var pu = m.bld.part
	m.S.part = rec_of(fs)
	pu.upto = -1
	pu.sync()
	await idle(16)


func hover_is(p: Vector2, c: Control) -> bool:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv, true)
	await process_frame
	await process_frame
	var h := root.gui_get_hovered_control()
	return h == c


func ov(a: Rect2, b: Rect2) -> float:
	var i := a.intersection(b)
	return i.size.x * i.size.y if i.size.x > 0.0 and i.size.y > 0.0 else 0.0


func set_size(w: int, h: int) -> void:
	root.content_scale_size = Vector2i(w, h)
	root.size = Vector2i(w, h)
	await idle(8)


func one(pu, tool: String, w: int, h: int) -> void:
	var tag := "%s %dx%d" % [tool, w, h]
	pu.close_dialog()
	await idle(2)
	pu.open_dialog(tool, -1)
	await idle(8)
	if pu.dlg.is_empty():
		print("skip ", tag, " (did not open)")
		return
	var win := Rect2(Vector2.ZERO, Vector2(w, h))
	var tlr: Rect2 = pu.tl.get_global_rect()
	var cb: Control = pu.cancel_btn
	var ob: Control = pu.ok_btn
	var cr := cb.get_global_rect()
	var orr := ob.get_global_rect()
	ok(win.encloses(cr) and win.encloses(orr), "1 %s: Cancel %s and OK %s inside the window" % [tag, str(cr), str(orr)])
	ok(ov(cr, tlr) == 0.0 and ov(orr, tlr) == 0.0, "1 %s: 0 px2 of Cancel/OK under the timeline %s" % [tag, str(tlr)])
	var hc: bool = await hover_is(cr.get_center(), cb)
	var ho: bool = await hover_is(orr.get_center(), ob)
	ok(hc and ho, "1 %s: pointer on Cancel -> Cancel %s, on OK -> OK %s" % [tag, str(hc), str(ho)])
	var sr := Rect2(pu.side.global_position, pu.side.size)
	ok(ov(sr, tlr) == 0.0, "3 %s: the side panel %s overlaps the timeline by %.0f px2" % [tag, str(sr), ov(sr, tlr)])
	var sc: ScrollContainer = pu.dlg_box.find_child("part_dialog_scroll", true, false)
	var bad := 0
	var n := 0
	for r in pu.dlg_rows.get_children():
		var rc := r as Control
		if rc == null or not rc.visible:
			continue
		n += 1
		if sc != null:
			sc.ensure_control_visible(rc)
			await process_frame
		var rr := rc.get_global_rect()
		var inside := win.encloses(rr)
		if sc != null:
			inside = inside and sc.get_global_rect().grow(1.0).encloses(rr)
		if not inside or ov(rr, tlr) > 0.0:
			bad += 1
	ok(bad == 0, "4 %s: %d of %d rows reachable (scroll box %s)" % [tag, n - bad, n, "yes" if sc != null else "none"])
	if sc != null:
		sc.scroll_vertical = 0
	await shot("%s_%d" % [tool.replace(" ", "_"), w])
	await click_ctl(cb)
	ok(pu.dlg.is_empty(), "2 %s: a real click on Cancel closes the dialog" % tag)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	if not Part.available():
		print("SKIP: no KineCAD DLL")
		quit(0)
		return
	var wd := create_timer(600.0)   # watchdog
	wd.timeout.connect(func():
		print("FAIL watchdog: c58 took over 600 s")
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://c58_test"))
	ss.dirs_override = ["user://c58_test"]
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
	for sz in [Vector2i(1024, 600), Vector2i(1280, 720)]:
		await set_size(sz.x, sz.y)
		for t in TOOLS:
			await one(pu, t, sz.x, sz.y)
	print("c58: %d fail" % fails)
	quit(1 if fails > 0 else 0)
