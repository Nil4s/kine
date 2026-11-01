extends SceneTree
## godot --path . --position 4000,4000 -s tests/s175_test.gd     (Friday plan 175: the undo memory budget; scripts/undo_budget.gd)
## Bars: 200 edits on a part -> the undo stack's bytes (sum of entry sizes) <= the budget and >= 4x smaller than unpacked;
## undo 200 times -> the exact original part JSON; at a 1 MB budget the oldest steps go and the note says so.
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s175"


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


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func fresh_part() -> void:
	m.undo.clear()
	m.redo.clear()
	m._tree.reset()
	m.undo_dropped = 0
	m.undo_note = ""
	m.S.part = Part.from_file({"name": "Budget", "features": [{"t": "sketch", "id": "f1", "plane": "xy", "pts": [[0.0, 0.0], [10.0, 0.0], [10.0, 10.0]]}]})
	m.bld.sync()


## one edit = one undo step that adds a sketch step with n points on a 0.5 mm grid
func edit(i: int, n: int) -> void:
	m._push_undo()
	var pts := []
	for k in n:
		pts.append([float((i * 7 + k * 13) % 40) * 0.5, float((i * 3 + k * 5) % 40) * 0.5])
	(m.S.part["features"] as Array).append({"t": "sketch", "id": "f%d" % (i + 2), "plane": "xy", "pts": pts})
	m.S.part["seq"] = i + 2


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
	ss.dirs_override = ["user://s175_test"]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	await click_ctl(m.bld.part.part_btn)
	await click_ctl(m.bld.part.easy_open_btn)
	await idle(4)
	UndoBudget.budget_mb = 64.0
	fresh_part()
	var orig := JSON.stringify(m._part_file())
	var t0 := Time.get_ticks_msec()
	for i in 200:
		edit(i, 40)
		UndoBudget.settle(m)
	var st: Dictionary = UndoBudget.stats(m)
	var budget := 64 * 1048576
	print("steps %d packed %d  stack bytes %d  unpacked bytes %d  ratio %.1fx  (200 edits %d ms)" % [st["steps"], st["packed"], st["bytes"], st["raw"], float(st["raw"]) / maxf(1.0, float(st["bytes"])), Time.get_ticks_msec() - t0])
	ok(m.undo.size() == 200, "200 edits keep 200 undo steps (%d)" % m.undo.size())
	ok(int(st["bytes"]) <= budget, "stack %d bytes <= budget %d" % [st["bytes"], budget])
	ok(float(st["raw"]) >= 4.0 * float(st["bytes"]), "stack at least 4x smaller than unpacked: %d vs %d" % [st["bytes"], st["raw"]])
	ok(int(st["packed"]) == 190, "the newest 10 stay plain, 190 packed (%d)" % st["packed"])
	ok(m.undo_note == "", "no note while within the budget")
	await shot("stack")
	var mid_ok := true
	for i in 200:
		m._undo()
		if i == 100 and JSON.stringify(m._part_file()).length() >= orig.length() * 20:
			mid_ok = false
	await idle(2)
	var back := JSON.stringify(m._part_file())
	ok(back == orig, "200 undos give back the exact original part JSON (%d chars)" % orig.length())
	ok(m.undo.is_empty(), "undo stack empty after 200 undos (%d)" % m.undo.size())
	var st2: Dictionary = UndoBudget.stats(m)
	print("after 200 undos: redo steps %d  bytes %d  unpacked %d" % [m.redo.size(), st2["bytes"], st2["raw"]])
	for i in 200:
		m._redo()
	await idle(2)
	ok(m.undo.size() == 200 and (m.S.part["features"] as Array).size() == 201, "200 redos bring all 200 edits back (%d, %d features)" % [m.undo.size(), (m.S.part["features"] as Array).size()])
	# the forgotten note at a 1 MB budget
	UndoBudget.budget_mb = 1.0
	fresh_part()
	for i in 200:
		edit(i, 120)
		UndoBudget.settle(m)
	var st3: Dictionary = UndoBudget.stats(m)
	print("1 MB budget: steps %d  bytes %d  dropped %d  note '%s'" % [st3["steps"], st3["bytes"], m.undo_dropped, m.undo_note])
	ok(int(st3["bytes"]) <= 1048576, "stack %d bytes <= 1 MB" % st3["bytes"])
	ok(m.undo_dropped > 0 and m.undo.size() < 200, "oldest steps dropped (%d dropped, %d kept)" % [m.undo_dropped, m.undo.size()])
	ok(m.undo_note == "oldest undo steps forgotten to save memory", "note: " + m.undo_note)
	await idle(3)
	ok(m.ui_status != null and m.ui_status.text == m.undo_note, "status line says it: '%s'" % (m.ui_status.text if m.ui_status != null else ""))
	ok(m.ui_undo_btn != null and m.ui_undo_btn.tooltip_text.contains(m.undo_note), "Undo tooltip carries the note")
	var k: int = m.undo.size()
	for i in k:
		m._undo()
	ok(m.undo.is_empty(), "the kept steps all undo (%d)" % k)
	await shot("note")
	print("s175: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])
