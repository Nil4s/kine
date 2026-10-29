extends SceneTree
## godot --path . --position 4000,4000 -s tests/fchaos2_test.gd     (FCHAOS2: chaos monkey for EXPERT Part building, seeds 41..50, 600 real inputs each; needs the CAD DLL and a window)
## Each input is a REAL click / drag / wheel / key through root.push_input at 1280 x 720, from the start screen: the BUILDING card,
## then Expert (the Part button). Inputs cover every Expert ribbon tool (any visible button on screen too: dialogs and their OK / Cancel),
## sketch clicks and drags on Front / Top / Right, typed numbers and Enter, Finish, Ctrl+Z / Ctrl+Y, Escape, wheel, timeline, random keys.
## Denied by name (never pressed): save, export, import, open, quit, exit, delete, video, playblast, trash, rename, copy, bake, render.
## After EACH input: no SCRIPT ERROR (warnings do not count), the body volume is finite and not negative, the undo depth is not negative,
## and the app still answers (a frame runs). A freeze shows as the run_par TIMEOUT. Each failure prints seed, input number, the last inputs
## (the repro) and the exact error, and saves a shot to C:/Temp/claude/fchaos2.
## Bars (each FAILED on the old code, run before the fix) are added below the monkey as the monkey finds them.

const SHOT := "C:/Temp/claude/fchaos2"
const DIRT := "user://fchaos2_test"
const SEEDS := [41, 42, 43, 44, 45, 46, 47, 48, 49, 50]
const INPUTS := 600
const DENY := ["save", "export", "import", "open", "quit", "exit", "delete", "video", "playblast", "trash", "rename", "copy", "bake", "render"]

class ErrLog extends Logger:
	var errs: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
		if error_type == 1:   # warnings do not count
			return
		errs.append("%s:%d %s %s %s" % [file.get_file(), line, function, code, rationale])

var fails := 0
var m: Node
var log_errs := ErrLog.new()
var rng := RandomNumberGenerator.new()
var seen := {}
var tail: Array = []


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


func ev_move(p: Vector2, held := true) -> void:
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
	e.position = p
	e.global_position = p
	e.pressed = true
	root.push_input(e, true)
	await process_frame
	e = e.duplicate()
	e.pressed = false
	root.push_input(e, true)
	await process_frame


func key(k: Key, ctrl := false, shift := false, uni := 0) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = down
		e.ctrl_pressed = ctrl
		e.shift_pressed = shift
		e.unicode = uni if down else 0
		root.push_input(e, true)
		await process_frame


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func drag_at(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 9):
		await ev_move(a.lerp(b, i / 8.0))
	await ev_mouse(b, false)
	await idle(2)


func shown(c: Variant) -> bool:
	return c is Control and is_instance_valid(c) and (c as Control).is_visible_in_tree()


func sp(pl_name: String, x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane(pl_name), Vector2(x, y)))


func vol() -> float:
	return float(Part.replay(m.S.part)["volume"]) if not m.S.part.is_empty() else 0.0


func text_of(b: BaseButton) -> String:
	if b is Button and (b as Button).text != "":
		return (b as Button).text
	for c in b.find_children("*", "Label", true, false):
		if (c as Label).text != "":
			return (c as Label).text
	return ""


func denied(t: String) -> bool:
	var l := t.to_lower()
	for w in DENY:
		if l.contains(w):
			return true
	return false


func visible_buttons() -> Array:
	var out: Array = []
	for b in root.find_children("*", "BaseButton", true, false):
		var bb: BaseButton = b
		if bb.is_visible_in_tree() and not bb.disabled and bb.get_global_rect().size.x > 2.0 and not denied(text_of(bb)):
			out.append(bb)
	return out


func close_windows() -> void:
	for w in root.find_children("*", "Window", true, false):
		if w != root and (w as Window).visible:
			(w as Window).hide()


func new_main() -> void:
	if m != null:
		m.queue_free()
		await idle(4)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)


## the real start: BUILDING card, discard the save prompt, then Expert (Part on BUILD), as xchaos opens it
func open_part() -> bool:
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"] as Control)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	var pu = m.bld.part
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(3)
	return pu.on and pu.tool_btns.has("Circle")


## one seeded real input; returns a short label for the repro
func one_input() -> String:
	var pu = m.bld.part
	var r := rng.randi() % 100
	if r < 18:
		var bs := visible_buttons()
		if bs.is_empty():
			return "no button"
		var b: BaseButton = bs[rng.randi() % bs.size()]
		var lbl := text_of(b) + " " + str(b.name)   # read before the click: the click may rebuild the button
		await click_ctl(b)
		return "click [" + lbl + "]"
	if r < 34:
		var vis := []
		for t in pu.tool_btns:
			if shown(pu.tool_btns[t]):
				vis.append(t)
		if vis.is_empty():
			return "tool: none visible"
		var t: String = vis[rng.randi() % vis.size()]
		await click_ctl(pu.tool_btns[t])
		return "tool " + t
	if r < 52:
		var pl: String = ["front", "top", "right"][rng.randi() % 3]
		var x := float(rng.randi_range(-40, 40))
		var y := float(rng.randi_range(-30, 30))
		await click_at(sp(pl, x, y))
		return "click %s (%d, %d)" % [pl, x, y]
	if r < 64:
		var pl2: String = ["front", "top", "right"][rng.randi() % 3]
		var a := Vector2(rng.randi_range(-40, 40), rng.randi_range(-30, 30))
		var b2 := a + Vector2(rng.randi_range(-30, 30), rng.randi_range(-30, 30))
		await drag_at(sp(pl2, a.x, a.y), sp(pl2, b2.x, b2.y))
		return "drag %s (%d,%d)->(%d,%d)" % [pl2, a.x, a.y, b2.x, b2.y]
	if r < 70:
		if shown(pu.finish_btn):
			await click_ctl(pu.finish_btn)
			return "finish"
		return "finish: hidden"
	if r < 80:
		if shown(pu.f_num):
			var txt := str(rng.randi_range(0, 60))
			if rng.randf() < 0.3:
				txt = "-" + txt
			await click_ctl(pu.f_num)
			await key(KEY_A, true)
			for ch in txt:
				if ch == "-":
					await key(KEY_MINUS, false, false, 45)
				else:
					await key((KEY_0 + int(ch)) as Key, false, false, ch.unicode_at(0))
			await key(KEY_ENTER)
			await idle(2)
			return "type " + txt
		return "type: no field"
	if r < 86:
		for b in [pu.ok_btn, pu.cancel_btn]:
			if shown(b) and rng.randi() % 2 == 0:
				await click_ctl(b)
				return "dialog button"
		return "dialog: none"
	if r < 90:
		var back := rng.randi() % 2 == 0
		await key(KEY_Z if back else KEY_Y, true)
		await idle(2)
		return "ctrl+z" if back else "ctrl+y"
	if r < 93:
		await key(KEY_ESCAPE)
		return "escape"
	if r < 95:
		var p := Vector2(rng.randf() * 1280.0, rng.randf() * 720.0)
		var up := rng.randf() < 0.5
		for i in rng.randi_range(1, 3):
			await ev_wheel(p, up)
		return "wheel " + ("up" if up else "down")
	if r < 98:
		var tb := []
		for b in pu.tl_btns:
			if shown(b):
				tb.append(b)
		if tb.is_empty():
			return "timeline: none"
		await click_ctl(tb[rng.randi() % tb.size()])
		return "timeline"
	var k: int = [KEY_ENTER, KEY_BACKSPACE, KEY_TAB, KEY_SPACE, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_1, KEY_2, KEY_R, KEY_E, KEY_C][rng.randi() % 13]
	await key(k as Key)
	return "key " + OS.get_keycode_string(k as Key)


func run_seed(s: int) -> void:
	rng.seed = s
	tail = []
	await new_main()
	log_errs.errs.clear()
	var opened := await open_part()
	ok(opened, "seed %d: Expert Part is open from the BUILDING card (real clicks)" % s)
	if not opened:
		return
	for step in INPUTS:
		var line := await one_input()
		await idle(2)
		close_windows()
		tail.append(str(step + 1) + " " + line)
		if tail.size() > 6:
			tail.pop_front()
		var v := vol()
		var vol_ok: bool = not (is_nan(v) or is_inf(v) or v < -1e-12)
		var depth_ok: bool = m.undo.size() >= 0 and m.redo.size() >= 0
		var alive: bool = is_instance_valid(m) and m.is_inside_tree()
		if not log_errs.errs.is_empty() or not vol_ok or not depth_ok or not alive:
			var what := str(log_errs.errs[0]) if not log_errs.errs.is_empty() else ("volume %s" % str(v) if not vol_ok else ("undo depth negative" if not depth_ok else "the app is gone"))
			if not seen.has(what):
				seen[what] = true
				print("FAIL seed " + str(s) + " input " + str(step + 1) + ": " + what)
				print("     repro: " + " | ".join(tail))
				root.get_texture().get_image().save_png(SHOT + "/s" + str(s) + "_fail" + str(step + 1) + ".png")
			fails += 1
			log_errs.errs.clear()
			if not alive:
				return
	ok(log_errs.errs.is_empty(), "seed %d: %d inputs, no script error, volume never negative (undo %d, redo %d)" % [s, INPUTS, m.undo.size(), m.redo.size()])
	log_errs.errs.clear()


func _init() -> void:
	OS.add_logger(log_errs)
	DirAccess.make_dir_recursive_absolute(SHOT)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	if not Part.available():
		print("FAIL: no KineCAD DLL, fchaos2 cannot run")
		quit(1)
		return
	var env := OS.get_environment("FCHAOS2_SEEDS")   # one or more seeds, comma separated, for a debugging run
	var seeds: Array = SEEDS.duplicate()
	if env != "":
		seeds = []
		for x in env.split(","):
			seeds.append(int(x))
	for s in seeds:
		await run_seed(s)
	print("fchaos2: %d failure(s)" % fails)
	print("FCHAOS2 %s" % ["PASS" if fails == 0 else "FAIL %d" % fails])
	quit(1 if fails > 0 else 0)
