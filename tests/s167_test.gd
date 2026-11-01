extends SceneTree
## godot --path . --position 4000,4000 -s tests/s167_test.gd     (Friday plan 167: Easy Part starts under 1 s from the BUILDING card)
## Bar: 5 starts (app booted to Home, then a real click on the BUILDING card): the time from the press to the first frame where the
## Draw shape button is on screen, enabled, and a real click on it arms drawing. Median of 5 < 1000 ms. The first start is the coldest.
var fails := 0
var _dbg := false
var m: Node
const SHOT := "C:/Temp/claude/s167"


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


func boot() -> void:
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://s167_test"))
	ss.dirs_override = ["user://s167_test"]
	m.easy.set_on(true)   # a beginner: Easy is on, so the BUILDING card opens Easy Part
	ss._card_easy["building"] = true   # the card's Easy mode (what a beginner has)
	ss._sync_modes("building")
	ss.show_screen()
	await idle(30)   # Home is up and settled


## ms from the press on the BUILDING card to the first frame where a click on Draw shape arms it; -1 = never in 15 s
func start_once(shot_name := "") -> int:
	var ss: StartScreen = m.start_screen
	var card: Control = ss._cards["building"]
	var p := card.get_global_rect().get_center()
	var t0 := Time.get_ticks_usec()
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	var got := -1
	while (Time.get_ticks_usec() - t0) < 15000000:
		var ep = m.bld.part.ep if m.bld != null and m.bld.part != null else null
		if ep != null and ep.make_btns.has("draw"):
			var b: Button = ep.make_btns["draw"]
			if b.is_visible_in_tree() and not b.disabled and b.get_global_rect().size.x > 4.0 and Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(b.get_global_rect()):
				var c := b.get_global_rect().get_center()
				await ev_mouse(c, true)
				await ev_mouse(c, false)
				if ep.armed == "draw":
					got = int((Time.get_ticks_usec() - t0) / 1000)
					break
		await process_frame
		if got < 0 and (Time.get_ticks_usec() - t0) > 3000000 and not _dbg:
			_dbg = true
			var e2 = m.bld.part.ep if m.bld != null and m.bld.part != null else null
			print("DEBUG kind=%s page=%s part_on=%s easy=%s ep=%s" % [m.S.kind, m.cur_page, m.bld.part.on if m.bld != null else "-", m.bld.part.easy if m.bld != null else "-", e2 != null])
			if e2 != null and e2.make_btns.has("draw"):
				var b2: Button = e2.make_btns["draw"]
				print("DEBUG draw vis=%s dis=%s rect=%s armed='%s'" % [b2.is_visible_in_tree(), b2.disabled, b2.get_global_rect(), e2.armed])
	if shot_name != "" and got >= 0:
		await idle(3)
		DirAccess.make_dir_recursive_absolute(SHOT)
		root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, shot_name])
	return got


func _init() -> void:
	var times := []
	for i in 5:
		_dbg = false
		await boot()
		var t := await start_once("start%d" % i if i == 0 or i == 4 else "")
		print("start %d: %d ms" % [i + 1, t])
		times.append(t)
		m.queue_free()
		await idle(10)
	var s := times.duplicate()
	s.sort()
	var med: int = s[2]
	print("times %s  median %d ms" % [str(times), med])
	ok(not times.has(-1), "every start reached an interactive Draw shape button")
	ok(med < 1000, "median of 5 starts %d ms < 1000 ms" % med)
	print("s167: %d fail" % fails)
	quit(1 if fails > 0 else 0)
