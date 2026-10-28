extends SceneTree
## godot --path . --position 4000,4000 -s tests/xchaos_test.gd     (xchaos: chaos monkey for EXPERT Part; seeds 1..5, 600 seeded real inputs each; needs the CAD DLL and a window)
## Each input is a REAL click / drag / key through root.push_input at 1280 x 720, from the start screen (Building card, Part button).
## Inputs: tool buttons, sketch clicks and drags on Front / Top / Right, Finish, numbers typed into the dialog and Enter,
## OK / Cancel, Ctrl+Z / Ctrl+Y, Escape, timeline buttons.
## After every input: no SCRIPT ERROR / push_error (warnings are not counted), the body volume is finite and not negative,
## and the record replays with its volume unchanged by an undo + redo pair.
## Each failure prints its seed, step and the input list so far (the repro). Exit 1 on any FAIL.
## Repro bars for each fixed failure are added below the monkey as their own named checks.

const DIRT := "user://xchaos_test"
const SEEDS := [1, 2, 3, 4, 5]
const STEPS := 600
const MM := 0.001

class ErrLog extends Logger:
	var errs: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
		if error_type == 1:
			return
		errs.append("%s:%d %s %s %s" % [file.get_file(), line, function, code, rationale])

var fails := 0
var m: Node
var log_errs := ErrLog.new()
var trace: Array = []
var round_bad := ""


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
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


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func key(k: Key, ctrl := false, uni := 0) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.unicode = uni
		e.pressed = down
		e.ctrl_pressed = ctrl
		root.push_input(e, true)
		await process_frame


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func drag_at(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	await ev_move(a.lerp(b, 0.5))
	await ev_move(b)
	await ev_mouse(b, false)
	await idle(2)


func sp(pl_name: String, x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane(pl_name), Vector2(x, y)))


func vol() -> float:
	return float(Part.replay(m.S.part)["volume"]) if not m.S.part.is_empty() else 0.0


func sk_count() -> int:
	var pu = m.bld.part
	return pu._sk()["ents"].size() if pu.sk != "" else 0


func shown(c: Variant) -> bool:
	return c is Control and is_instance_valid(c) and (c as Control).is_visible_in_tree()


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


## the real start: Building card, discard the save prompt, Part button on BUILD
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
	await click_ctl(pu.part_btn)
	await idle(3)
	return pu.on and pu.tool_btns.has("Circle")


## one seeded input. Returns a short label for the trace.
func do_step(rng: RandomNumberGenerator) -> String:
	var pu = m.bld.part
	var r := rng.randi() % 100
	if r < 22:
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
	if r < 66:
		var pl2: String = ["front", "top", "right"][rng.randi() % 3]
		var a := Vector2(rng.randi_range(-40, 40), rng.randi_range(-30, 30))
		var b := a + Vector2(rng.randi_range(-30, 30), rng.randi_range(-30, 30))
		await drag_at(sp(pl2, a.x, a.y), sp(pl2, b.x, b.y))
		return "drag %s (%d,%d)->(%d,%d)" % [pl2, a.x, a.y, b.x, b.y]
	if r < 72:
		if shown(pu.finish_btn):
			await click_ctl(pu.finish_btn)
			return "finish"
		return "finish: hidden"
	if r < 82:
		if shown(pu.f_num):
			var txt := str(rng.randi_range(1, 60))
			await click_ctl(pu.f_num)
			await key(KEY_A, true)
			for ch in txt:
				await key(KEY_0 + int(ch), false, ch.unicode_at(0))
			await key(KEY_ENTER)
			await idle(2)
			return "type %s" % txt
		return "type: no field"
	if r < 86:
		for b in [pu.ok_btn, pu.cancel_btn]:
			if shown(b) and rng.randi() % 2 == 0:
				await click_ctl(b)
				return "dialog button"
		return "dialog: none"
	if r < 92:
		var back := rng.randi() % 2 == 0
		if not back:
			await key(KEY_Y, true)
			await idle(2)
			return "ctrl+y"
		# Ctrl+Z takes one step back (never below none), and Ctrl+Y puts the same volume back
		var v0 := vol()
		var n0: int = m.undo.size()
		# a text field with the keyboard (a dialog number, the angle) takes Ctrl+Z for its own text: no model step then
		var fo0 = root.gui_get_focus_owner()
		if fo0 is LineEdit or fo0 is TextEdit:
			await key(KEY_Z, true)
			await idle(2)
			return "ctrl+z (in the field)"
		await key(KEY_Z, true)
		await idle(2)
		var n1: int = m.undo.size()
		var v1 := vol()
		if n0 > 0 and n1 != n0 - 1:
			var pq = m.bld.part
			var fo = root.gui_get_focus_owner()
			round_bad = "undo %d -> %d (want %d) [focus %s, sk '%s', dlg '%s', tool '%s', on %s, easy %s]" % [n0, n1, n0 - 1, str(fo.get_class() if fo else "none") + " " + str(fo.name if fo else ""), pq.sk, str(pq.dlg.get("t", "")), pq.tool, str(pq.on), str(pq.easy)]
		elif n0 == 0 and n1 != 0:
			round_bad = "undo with nothing to undo changed the stack: %d" % n1
		await key(KEY_Y, true)
		await idle(2)
		if n0 > 0 and absf(vol() - v0) > 1e-9:
			round_bad = "undo then redo: volume %s, was %s (after undo %s)" % [str(vol()), str(v0), str(v1)]
		return "ctrl+z"
	if r < 96:
		await key(KEY_ESCAPE)
		return "escape"
	var tb := []
	for b in pu.tl_btns:
		if shown(b):
			tb.append(b)
	if tb.is_empty():
		return "timeline: none"
	await click_ctl(tb[rng.randi() % tb.size()])
	return "timeline"


func run_seed(seed_n: int) -> void:
	await new_main()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	log_errs.errs.clear()
	trace.clear()
	round_bad = ""
	ok(await open_part(), "seed %d: Part is open from the start screen" % seed_n)
	var bad := ""
	var step := 0
	var max_bodies := 0
	var max_undo := 0
	var max_ents := 0
	while step < STEPS and bad == "":
		var label := await do_step(rng)
		trace.append(label)
		step += 1
		max_bodies = maxi(max_bodies, int(m.bld.part.res.get("bodies", 0)))
		max_undo = maxi(max_undo, m.undo.size())
		max_ents = maxi(max_ents, sk_count())
		var v := vol()
		if round_bad != "":
			bad = round_bad
		elif not log_errs.errs.is_empty():
			bad = "error logged: %s" % str(log_errs.errs)
		elif is_nan(v) or is_inf(v) or v < -1e-12:
			bad = "volume %s" % str(v)
		if bad != "":
			break
	if bad != "":
		print("FAIL seed %d step %d: %s" % [seed_n, step, bad])
		print("  trace: " + " ; ".join(trace))
		fails += 1
	else:
		print("ok   seed %d: %d inputs, nothing logged, volume never negative" % [seed_n, step])
	print("   seed %d reach: bodies max %d, undo max %d, sketch entities max %d" % [seed_n, max_bodies, max_undo, max_ents])


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	OS.add_logger(log_errs)
	if not Part.available():
		print("FAIL: no KineCAD DLL, xchaos cannot run")
		quit(1)
		return
	var only := OS.get_environment("XCHAOS_SEEDS")   # a debugging run: XCHAOS_SEEDS=3 (the bars run 1..5)
	for s in ([int(only)] if only != "" else SEEDS):
		await run_seed(s)
	print("XCHAOS %s" % ["PASS" if fails == 0 else "FAIL %d" % fails])
	TestFiles.cleanup()
	quit(fails)
