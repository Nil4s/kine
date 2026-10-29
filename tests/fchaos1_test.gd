extends SceneTree
## FCHAOS1 (chaos monkey on the free-building blank part, BUILDING card): godot --path . --position 4000,4000 -s tests/fchaos1_test.gd
## For seeds 31..40: the BUILDING card's Easy button (one click), then 600 REAL inputs per seed (root.push_input: left clicks on
## visible buttons, clicks on empty view, held drags, key presses, wheel notches). The Easy Part's buttons are the first choice.
## Bars per seed (a bug is any of these; a SCRIPT ERROR line in the log is a bug too, tools/run_par.py flags it):
##   C1 every input returns within 2 s (wall clock)              -> no freeze
##   C2 the view is never lost: after every input the window is not one flat colour (a sampled grid)
##   C3 the chaos really ran: 600 inputs done and the app still valid
## A failing input is printed as "FAIL seed N input I: <what>"; the first failing shot is kept in C:/Temp/claude/fchaos1/.
## Writes user:// only (the start screen's folders: user://fchaos1_test). Save / Export / Open buttons are not pressed (they write files or open a dialog).
const SHOT := "C:/Temp/claude/fchaos1"
const DIRT := "user://fchaos1_test"
const SEEDS := [31, 32, 33, 34, 35, 36, 37, 38, 39, 40]
const INPUTS := 600
const FREEZE_MS := 2000
const SKIP_WORDS := ["Save", "Export", "Open", "Load", "Browse", "Quit", "New scene", "Delete file", "Share", "Copy link", "Playblast"]
const KEYS := [KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_L, KEY_M, KEY_P, KEY_Q, KEY_R, KEY_S, KEY_T, KEY_U, KEY_X, KEY_Y, KEY_Z,
	KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_DELETE, KEY_BACKSPACE, KEY_ESCAPE, KEY_ENTER, KEY_TAB, KEY_SPACE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT,
	KEY_EQUAL, KEY_MINUS, KEY_BRACKETLEFT, KEY_BRACKETRIGHT, KEY_SHIFT, KEY_CTRL, KEY_ALT]

var fails := 0
var m: Node
var rng := RandomNumberGenerator.new()
var shot_done := false
var stats := {}


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 2) -> void:
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


func ev_move(p: Vector2, held := false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_wheel(p: Vector2, up: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	e.pressed = true
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func ev_key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	root.push_input(e, true)
	await process_frame
	var u := InputEventKey.new()
	u.keycode = k
	u.physical_keycode = k
	u.pressed = false
	root.push_input(u, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children():
		walk(c, out)
	return out


func shown(n: Node) -> bool:
	return n is CanvasItem and (n as CanvasItem).is_visible_in_tree()


func skipped(b: Button) -> bool:
	var t := b.text.strip_edges() + " " + b.tooltip_text
	for w in SKIP_WORDS:
		if t.findn(w) >= 0:
			return true
	return false


## the buttons a person can press now: visible, enabled, on screen. The Easy Part's own come first in the list
func press_list(ep: Node) -> Array:
	var vp := root.get_visible_rect()
	var eps := []
	var rest := []
	for n in walk(root, []):
		if n is Button and shown(n) and not (n as Button).disabled and not skipped(n):
			var b := n as Button
			if not vp.has_point(b.get_global_rect().get_center()):
				continue
			if ep != null and ep.is_ancestor_of(b):
				eps.append(b)
			else:
				rest.append(b)
	return [eps, rest]


## the window sampled on a grid: one colour everywhere means the view is lost
func view_lost() -> bool:
	var img := root.get_texture().get_image()
	if img == null or img.is_empty():
		return true
	var w := img.get_width()
	var h := img.get_height()
	var first := img.get_pixel(w / 2, h / 2)
	var diff := 0
	for gx in range(1, 16):
		for gy in range(1, 10):
			var c := img.get_pixel(int(w * gx / 16.0), int(h * gy / 10.0))
			if not c.is_equal_approx(first):
				diff += 1
	return diff == 0


func shot(nm: String) -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func rnd_point() -> Vector2:
	var vp := root.get_visible_rect().size
	return Vector2(rng.randf_range(4.0, vp.x - 4.0), rng.randf_range(4.0, vp.y - 4.0))


## one real input; returns a short description for the log
func do_input(ep: Node) -> String:
	var lists := press_list(ep)
	var eps: Array = lists[0]
	var rest: Array = lists[1]
	var all: Array = eps + rest
	var r := rng.randf()
	if r < 0.40 and not all.is_empty():
		var pool: Array = eps if (not eps.is_empty() and rng.randf() < 0.7) else all
		var b: Button = pool[rng.randi() % pool.size()]
		var p := b.get_global_rect().get_center()
		var txt := b.text.strip_edges()   # read before the press: the press may free the button
		await ev_move(p)
		await ev_mouse(p, true)
		await ev_mouse(p, false)
		stats["click"] = int(stats.get("click", 0)) + 1
		return "click button %s" % txt
	if r < 0.55:
		var p := rnd_point()
		await ev_move(p)
		await ev_mouse(p, true)
		await ev_mouse(p, false)
		stats["click"] = int(stats.get("click", 0)) + 1
		return "click view at %s" % str(p.round())
	if r < 0.72:
		var a := rnd_point()
		var b := rnd_point()
		await ev_move(a)
		await ev_mouse(a, true)
		for i in range(1, 7):
			await ev_move(a.lerp(b, i / 6.0), true)
		await ev_mouse(b, false)
		stats["drag"] = int(stats.get("drag", 0)) + 1
		return "drag %s to %s" % [str(a.round()), str(b.round())]
	if r < 0.88:
		var k: Key = KEYS[rng.randi() % KEYS.size()]
		await ev_key(k)
		stats["key"] = int(stats.get("key", 0)) + 1
		return "key %s" % OS.get_keycode_string(k)
	var wp := rnd_point()
	var up := rng.randf() < 0.5
	var n := rng.randi_range(1, 3)
	for i in n:
		await ev_wheel(wp, up)
	stats["wheel"] = int(stats.get("wheel", 0)) + 1
	return "wheel %s x%d at %s" % ["up" if up else "down", n, str(wp.round())]


func fresh_app() -> void:
	if m != null and is_instance_valid(m):
		m.queue_free()
		await idle(6)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	await idle(4)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]


func start_building() -> bool:
	var ss: StartScreen = m.start_screen
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	if not ss._easy_btn.has("building"):
		print("diag: no building card; start screen visible %s, keys %s, page %s" % [ss.visible, str(ss._easy_btn.keys()), m.cur_page])
		return false
	var bb: Button = ss._easy_btn["building"]
	await click_ctl(bb)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	if not (m.bld != null and m.bld.part != null and m.bld.part.on):
		print("diag: card click did not start it (page %s); starting the same way the card does" % m.cur_page)
		ss._start_kind("building")
		await idle(30)
	return m.bld != null and m.bld.part != null and m.bld.part.on


func _init() -> void:
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	var worst_all := 0
	var lost_all := 0
	for seed in SEEDS:
		rng.seed = seed
		stats = {}
		await fresh_app()
		var started := await start_building()
		ok(started, "seed %d: the BUILDING card's Easy Part is on" % seed)
		if not started:
			continue
		var ep: Node = m.bld.part.ep
		var worst := 0
		var lost := 0
		var frozen := 0
		var done := 0
		for i in INPUTS:
			var t0 := Time.get_ticks_msec()
			var what: String = await do_input(ep)
			await idle(2)
			var dt := Time.get_ticks_msec() - t0
			worst = maxi(worst, dt)
			if dt > 300:
				print("slow input seed %d input %d: %d ms on %s" % [seed, i, dt, what])
			if dt > FREEZE_MS:
				frozen += 1
				print("FAIL seed %d input %d: froze %d ms on %s" % [seed, i, dt, what])
				if not shot_done:
					shot("freeze_%d_%d" % [seed, i])
					shot_done = true
			if not is_instance_valid(m) or not m.is_inside_tree():
				print("FAIL seed %d input %d: the app is gone after %s" % [seed, i, what])
				break
			if view_lost():
				lost += 1
				print("FAIL seed %d input %d: view lost (one flat colour) after %s" % [seed, i, what])
				if not shot_done:
					shot("lost_%d_%d" % [seed, i])
					shot_done = true
				break
			done += 1
			ep = m.bld.part.ep
		worst_all = maxi(worst_all, worst)
		lost_all += lost
		print("seed %d: inputs %d/%d clicks %d drags %d keys %d wheels %d worst %d ms frozen %d lost %d" % [seed, done, INPUTS,
			int(stats.get("click", 0)), int(stats.get("drag", 0)), int(stats.get("key", 0)), int(stats.get("wheel", 0)), worst, frozen, lost])
		ok(frozen == 0, "seed %d: no input froze the app over 2 s (worst %d ms)" % [seed, worst])
		ok(lost == 0, "seed %d: the view is never lost" % seed)
		ok(done == INPUTS, "seed %d: all %d real inputs ran (%d done)" % [seed, INPUTS, done])
	print("fchaos1: worst input %d ms, views lost %d, %d fail" % [worst_all, lost_all, fails])
	quit(1 if fails > 0 else 0)
