extends SceneTree
## godot --path . --position 4000,4000 -s tests/libchaos_test.gd     (LIBCHAOS: the object library chaos monkey, seeds 1..5, 600 real inputs each)
## Real clicks, drags, wheel and keys at 1280 x 720 from the real start screen (ANIMATION card), then the library opened by its Library button.
## After EACH input: no SCRIPT ERROR / push_error in the log, undo depth never negative, the window still answers (a frame runs, the app is alive).
## Denied by name (never pressed): Save, Export, Import, Open, Quit, Delete, Video, Playblast, Trash, Rename, Copy, Bake, Render.
## Writes user:// and C:/Temp/claude/libchaos only. Prints one line per distinct failure: seed, input number, the last inputs, the exact error.
## Bars (each FAILED on the old code, run before the fix) are added below as the monkey finds them.

const SHOT := "C:/Temp/claude/libchaos"
const DIRT := "user://libchaos_test"
const SEEDS := [1, 2, 3, 4, 5]
const INPUTS := 600
const DENY := ["save", "export", "import", "open", "quit", "exit", "delete", "video", "playblast", "trash", "rename", "copy", "bake", "render"]
const KEYS := [KEY_Z, KEY_Y, KEY_ESCAPE, KEY_ENTER, KEY_BACKSPACE, KEY_TAB, KEY_SPACE, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_A, KEY_C, KEY_H, KEY_O, KEY_T, KEY_1, KEY_2, KEY_0]

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
var seen := {}          # distinct failure texts (one line each)
var tail: Array = []    # the last inputs of the seed, for the repro line


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


func ev_key(code: int, ctrl := false, shift := false) -> void:
	var uni := 0
	if not ctrl and code >= KEY_A and code <= KEY_Z:
		uni = code + (32 if not shift else 0)
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code as Key
		e.physical_keycode = code as Key
		e.pressed = down
		e.ctrl_pressed = ctrl
		e.shift_pressed = shift
		e.unicode = uni if down else 0
		root.push_input(e, true)
		await process_frame


## a real click on a control: move, press, release, then frames
func press(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func vp_size() -> Vector2:
	return root.get_visible_rect().size


func rand_point() -> Vector2:
	var s := vp_size()
	return Vector2(rng.randf() * s.x, rng.randf() * s.y)


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


## the start screen, ANIMATION card, then the object library opened by its Library button (Easy bar), else STAGE's Library entry
func start_app() -> bool:
	EasyMode.start_fresh = true
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await press(ss._cards["animation"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(10)
	for b in visible_buttons():
		if text_of(b) == "Library":
			await press(b)
			await idle(6)
			return m.ui_library != null and m.ui_library.visible
	m.ui_page_btns["STAGE"].pressed.emit()   # Expert: the STAGE page's Library entry
	await idle(6)
	return m.ui_library != null and m.ui_library.visible


## one random real input; returns a line for the repro
func one_input() -> String:
	var r := rng.randi() % 100
	if r < 30:
		var bs := visible_buttons()
		if bs.is_empty():
			return "no button"
		var b: BaseButton = bs[rng.randi() % bs.size()]
		var lbl := text_of(b) + " " + str(b.name)   # read before the click: the click may rebuild (free) the button
		await press(b)
		return "click [" + lbl + "]"
	if r < 45:
		var bs2 := visible_buttons()
		var from := rand_point()
		if not bs2.is_empty() and rng.randf() < 0.7:
			from = (bs2[rng.randi() % bs2.size()] as Control).get_global_rect().get_center()
		var to := rand_point()
		await ev_move(from, false)
		await ev_mouse(from, true)
		for i in range(1, 13):
			await ev_move(from.lerp(to, i / 12.0))
		await ev_mouse(to, false)
		await idle(2)
		return "drag " + str(from.round()) + " to " + str(to.round())
	if r < 55:
		var p := rand_point()
		var up := rng.randf() < 0.5
		for i in rng.randi_range(1, 4):
			await ev_wheel(p, up)
		return "wheel " + str(p.round()) + (" up" if up else " down")
	if r < 75:
		var k: int = KEYS[rng.randi() % KEYS.size()]
		var ctrl := rng.randf() < 0.35
		await ev_key(k, ctrl, rng.randf() < 0.15)
		return "key " + ("Ctrl+" if ctrl else "") + OS.get_keycode_string(k)
	var q := rand_point()
	await ev_move(q, false)
	await ev_mouse(q, true)
	await ev_mouse(q, false)
	await idle(2)
	return "click empty " + str(q.round())


## modal windows (a dialog that opened) are hidden, not left to block the next inputs
func close_windows() -> void:
	for w in root.find_children("*", "Window", true, false):
		if w != root and (w as Window).visible:
			(w as Window).hide()


func run_seed(s: int) -> void:
	rng.seed = s
	tail = []
	var lib_open := await start_app()
	ok(lib_open, "seed %d: the object library is open from the start screen (real clicks)" % s)
	if not lib_open:
		return
	for step in INPUTS:
		var line := await one_input()
		await idle(2)
		close_windows()
		tail.append(str(step + 1) + " " + line)
		if tail.size() > 6:
			tail.pop_front()
		var depth_ok: bool = m.undo.size() >= 0 and m.redo.size() >= 0
		var alive: bool = is_instance_valid(m) and m.is_inside_tree()
		if not log_errs.errs.is_empty() or not depth_ok or not alive:
			var what := str(log_errs.errs[0]) if not log_errs.errs.is_empty() else ("undo depth negative" if not depth_ok else "the app is gone")
			if not seen.has(what):
				seen[what] = true
				print("FAIL seed " + str(s) + " input " + str(step + 1) + ": " + what)
				print("     repro: " + " | ".join(tail))
				root.get_texture().get_image().save_png(SHOT + "/s" + str(s) + "_fail" + str(step + 1) + ".png")
			fails += 1
			log_errs.errs.clear()
			if not alive:
				return
	ok(log_errs.errs.is_empty(), "seed %d: %d inputs, no script error (undo %d, redo %d)" % [s, INPUTS, m.undo.size(), m.redo.size()])
	log_errs.errs.clear()
	m.queue_free()
	await idle(4)


## BAR 1 LOOP_NAMES (found by the monkey, seed 2 input 501, as a Check run after a tree click: _tree_go -> _restore -> _check -> rule_loop):
## a loop scene with a pose seam: Rulebook.rule_loop named the joint through main's instance method nice() called on the
## script class, so "Can't call non-static function 'nice'" and an empty joint name ("the  is 73.4 deg off"). The bar: no
## script error from the check, and the finding names the joint ("right upper arm").
func bar_loop_names() -> bool:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	m._load_scene("res://scenes/combo3.json")
	var P: Array = m.S.cards.map(func(c): return c["pose"])
	var S := Scene.new()
	S.name = "zz_libchaos_loop"
	for k in [P[0], P[6], P[3]]:
		S.add("c%d" % (S.cards.size() + 1), (k as Dictionary).duplicate(true))
		S.cards[-1]["hold"] = 0.3
	S.loop = true
	log_errs.errs.clear()
	var found: Array = Rulebook.rule_loop(S, m.B)
	var text := ""
	for f in found:
		text += str(f.get("msg", f.get("text", "")))
	var errs := log_errs.errs.size()
	ok(errs == 0 and text.contains("right upper arm"), "BAR loop_names: a pose seam is named with no script error (errors %d, finding %s)" % [errs, text.left(90)])
	m.queue_free()
	await idle(3)
	return errs == 0 and text.contains("right upper arm")


## BAR 2 AI_ADDRESS (found by the monkey, seed 3 input 244: Z typed in the AI box's address field, then Enter): the address "Z"
## became the request URL "Z/api/chat", the engine logged "Invalid URL scheme: ''" (http_request.cpp:66, from llm_client.gd chat()).
## The bar: the same real clicks and keys from the start screen: ANIMATE, Ask AI, the address field, Z, the question, Enter:
## no script error, and the box says the address must start with http:// or https://.
func bar_ai_address() -> bool:
	EasyMode.start_fresh = true
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await press(ss._cards["animation"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(10)
	for b in visible_buttons():
		if text_of(b) == "Switch to Expert":
			await press(b)
			await idle(8)
			break
	var tab: Button = null
	for b in visible_buttons():
		if text_of(b) == "ANIMATE":
			tab = b
	if tab != null:
		await press(tab)
	await idle(4)
	var make: Button = null
	for b in visible_buttons():
		if text_of(b).begins_with("MAKE"):
			make = b
	if make == null:
		ok(false, "BAR ai_address: the ANIMATE page has the MAKE menu (Ask AI is in it)")
		return false
	await press(make)   # the caption's menu opens; its item is picked by id, as the beginner monkey picks View items
	await idle(3)
	var picked := false
	for pm in root.find_children("*", "PopupMenu", true, false):
		var p: PopupMenu = pm
		for i in p.item_count:
			if p.is_item_disabled(i) == false and p.get_item_text(i) == "Ask AI" and p.visible:
				p.id_pressed.emit(p.get_item_id(i))
				picked = true
	await idle(4)
	if not picked:
		ok(false, "BAR ai_address: MAKE's menu has an Ask AI item")
		return false
	var box = m.ui_ai
	log_errs.errs.clear()
	await press(box.ui_url)
	await ev_key(KEY_Z, false, true)
	await press(box.ui_in)
	await ev_key(KEY_X)
	await ev_key(KEY_ENTER)
	await idle(8)
	var said := " ".join(box.log_lines)   # the box's own log: the refusal is a line in it
	var errs := log_errs.errs.size()
	var good: bool = errs == 0 and said.contains("http")
	ok(good, "BAR ai_address: a bad address is refused in words, no script error (errors %d, box says: %s)" % [errs, said.right(120)])
	m.queue_free()
	await idle(3)
	return good


func _init() -> void:
	OS.add_logger(log_errs)
	DirAccess.make_dir_recursive_absolute(SHOT)
	await bar_loop_names()
	await bar_ai_address()
	var env := OS.get_environment("LIBCHAOS_SEEDS")   # e.g. "2" or "1,3": one seed per process keeps a run under the tool's 10 min
	var seeds: Array = SEEDS.duplicate()
	if env != "":
		seeds = []
		for x in env.split(","):
			seeds.append(int(x))
	if OS.get_environment("LIBCHAOS_BARS_ONLY") != "":
		seeds = []
	for s in seeds:
		await run_seed(s)
	print("libchaos: %d failure(s)" % fails)
	quit(1 if fails > 0 else 0)
