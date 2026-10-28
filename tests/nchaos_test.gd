extends SceneTree
## godot --path . --position 4000,4000 -s tests/nchaos_test.gd     (CHAOS MONKEY on EASY PART: scripts/easy_part.gd; needs the CAD DLL and a window)
## Seeds 1..5, 600 seeded random REAL inputs each at 1280 x 720, from the real start screen (Building card, Part, Easy):
## clicks on any visible button / chip / slider under Easy Part, drags on the grid, ViewCube clicks, Undo, the Empty chip,
## keys Ctrl+Z / Ctrl+Y / Escape. Checked after every input:
##   E  no SCRIPT ERROR or push_error (captured by a Logger; warnings do not count)
##   U  undo depth never negative (and never above the 60-step cap)
##   R  the part still replays (Part.replay of the Easy record: no errors)
##   W  the window still responds (frames keep being drawn; the main scene is alive)
## Trace: C:/Temp/claude/nchaos/trace.txt (every input). On a problem: the seed and the last 20 inputs go to
## C:/Temp/claude/nchaos/fail_s<seed>.txt, a shot to fail_s<seed>.png, and that seed stops (the next seed runs).
## Bars: one "ok"/"FAIL" line per seed and check; exit 1 on any FAIL.

const SHOT := "C:/Temp/claude/nchaos3/s1"
const DIRT := "user://nchaos_test"
const STEPS := 600
const SEEDS := [1, 2, 3, 4, 5]
const LAST_N := 20


class ErrLog extends Logger:
	var errs: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array) -> void:
		if error_type == 1:   # warnings do not count
			return
		errs.append("%s:%d %s %s %s" % [file.get_file(), line, function, code, rationale])


var fails := 0
var m: Node
var rng := RandomNumberGenerator.new()
var trace: FileAccess
var log_errs := ErrLog.new()
var hist: Array = []
var opened := 0


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


func ev_key(code: Key, ctrl: bool) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.ctrl_pressed = ctrl
		e.pressed = down
		root.push_input(e, true)
		await process_frame
	await idle(2)


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func rnd_point_in(r: Rect2) -> Vector2:
	return Vector2(r.position.x + r.size.x * rng.randf(), r.position.y + r.size.y * rng.randf())


func cur_ep() -> Node:
	var pu = m.bld.part if m != null and m.bld != null else null
	if pu == null or pu.ep == null or not is_instance_valid(pu.ep) or not pu.ep.is_inside_tree():
		return null
	return pu.ep


## every visible, enabled button / chip and every slider under Easy Part (plus the ViewCube), on screen
func targets(ep: Node) -> Array:
	var out: Array = []
	var screen := Rect2(Vector2.ZERO, Vector2(1280, 720))
	# Easy Part's rows sit in the screen's UI root (not under ep, a Node): its own boxes are the Control vars of ep whose parent is that root
	var ui: Node = ep.make_box.get_parent() if ep.make_box != null and ep.make_box.get_parent() != null else ep
	var cand: Array = []
	for pr in ep.get_property_list():
		if pr["type"] == TYPE_OBJECT and pr["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v = ep.get(pr["name"])
			if v is Control and (v as Control).get_parent() == ui:
				cand.append(v)
				cand.append_array((v as Control).find_children("*", "Control", true, false))
	for nm in ["undo_btn", "empty_chip", "easy_btn", "expert_btn"]:   # the bar and the chips, wherever they sit
		var b = ep.get(nm)
		if b is Control and is_instance_valid(b):
			cand.append(b)
	var seen := {}
	for n in cand:
		if seen.has(n):
			continue
		seen[n] = true
		var c := n as Control
		if not c.is_visible_in_tree() or c.size.x < 2 or c.size.y < 2:
			continue
		var r := c.get_global_rect()
		if not screen.encloses(r):
			continue
		if c is BaseButton and not (c as BaseButton).disabled:
			out.append({"kind": "btn", "name": str(c.get_path()).get_file(), "node": c})
		elif c is Range:
			out.append({"kind": "slider", "name": str(c.get_path()).get_file(), "node": c})
	if m.ui_cube != null and m.ui_cube.is_visible_in_tree():
		out.append({"kind": "cube", "name": "ViewCube", "node": m.ui_cube})
	return out


func count_btns(ep: Node) -> int:
	var k := 0
	for t in targets(ep):
		if t["kind"] == "btn":
			k += 1
	return k


func _shot(nm: String) -> void:
	await idle(2)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func open_easy() -> bool:
	opened += 1
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	var pt := ss._cards["building"] as Control
	await click_at(pt.get_global_rect().get_center())
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	var pu = m.bld.part
	await click_at(pu.part_btn.get_global_rect().get_center())
	await click_at(pu.easy_open_btn.get_global_rect().get_center())
	await idle(4)
	return cur_ep() != null


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


## one random REAL input; returns its one-line description
func do_input(step: int, ep: Node) -> String:
	var roll := rng.randf()
	var tg := targets(ep)
	if roll < 0.55 and tg.size() > 0:
		var t: Dictionary = tg[rng.randi_range(0, tg.size() - 1)]
		var c: Control = t["node"]
		if t["kind"] == "slider":
			var r := c.get_global_rect()
			var f := rng.randf()
			await drag_pts([Vector2(r.position.x + 2.0, r.get_center().y), Vector2(r.position.x + r.size.x * f, r.get_center().y)])
			return "%d slider %s drag to %.2f" % [step, t["name"], f]
		var p := rnd_point_in(c.get_global_rect().grow(-2.0))
		await click_at(p)
		if t["kind"] == "cube":
			return "%d cube click %s at (%d,%d)" % [step, t["name"], p.x, p.y]
		return "%d click %s at (%d,%d)" % [step, t["name"], p.x, p.y]
	if roll < 0.75:   # drag on the grid (start off the controls)
		var s := Vector2.ZERO
		for i in 40:
			s = Vector2(rng.randf_range(40, 1240), rng.randf_range(120, 680))
			if not ep._over_ui(s):
				break
		var pts: Array = [s]
		var n := rng.randi_range(2, 6)
		for i in n:
			pts.append(pts[-1] + Vector2(rng.randf_range(-90, 90), rng.randf_range(-90, 90)))
		await drag_pts(pts)
		return "%d grid drag from (%d,%d) %d points" % [step, s.x, s.y, n + 1]
	if roll < 0.82:
		var ub: Control = ep.undo_btn if ep.undo_btn != null and is_instance_valid(ep.undo_btn) else null
		if ub != null and ub.is_visible_in_tree():
			await click_at(ub.get_global_rect().get_center())
			return "%d click Undo button" % step
		return "%d (no Undo button shown)" % step
	if roll < 0.88:
		var em: Control = ep.empty_chip if ep.empty_chip != null and is_instance_valid(ep.empty_chip) else null
		if em != null and em.is_visible_in_tree():
			await click_at(em.get_global_rect().get_center())
			return "%d click Empty chip" % step
		return "%d (no Empty chip shown)" % step
	var k := rng.randi_range(0, 2)
	if k == 0:
		await ev_key(KEY_Z, true)
		return "%d key Ctrl+Z" % step
	if k == 1:
		await ev_key(KEY_Y, true)
		return "%d key Ctrl+Y" % step
	await ev_key(KEY_ESCAPE, false)
	return "%d key Escape" % step


## checks after one input: "" when all hold, else the problem in words
func check(ep: Node, frames0: int) -> String:
	if log_errs.errs.size() > 0:
		return "E error in log: " + str(log_errs.errs[0])
	var u: int = m.undo.size()
	if u < 0 or u > 60:
		return "U undo depth %d" % u
	if ep != null:
		var res: Dictionary = Part.replay(ep._rec())
		var errs: Dictionary = res.get("errors", {})
		if errs.size() > 0:
			return "R part does not replay: %s" % str(errs)
	if Engine.get_frames_drawn() <= frames0 or not is_instance_valid(m):
		return "W window stopped drawing"
	return ""


func run_seed(sd: int) -> void:
	rng.seed = sd
	hist.clear()
	log_errs.errs.clear()
	await new_main()
	var ok_open := await open_easy()
	ok(ok_open, "s%d open Easy Part from the start screen" % sd)
	if not ok_open:
		return
	trace.store_line("== seed %d start" % sd)
	var tg0 := targets(cur_ep())
	var nb := 0
	var ns := 0
	for t in tg0:
		if t["kind"] == "btn":
			nb += 1
		elif t["kind"] == "slider":
			ns += 1
	trace.store_line("== seed %d targets: %d buttons, %d sliders, 1 ViewCube" % [sd, nb, ns])
	var mk: Node = cur_ep().make_box
	trace.store_line("== diag make_box visible=%s in_tree=%s parent=%s btns=%d screen=%s" % [str(mk.visible), str(mk.is_inside_tree()), str(mk.get_parent().name if mk.get_parent() else "-"), cur_ep().make_btns.size(), str(mk.get_global_rect()) if mk.is_inside_tree() else "-"])
	trace.flush()
	ok(nb >= 20 and ns >= 1, "s%d the monkey sees %d buttons and %d sliders under Easy Part" % [sd, nb, ns])
	var problem := ""
	for step in range(1, STEPS + 1):
		var ep := cur_ep()
		if ep == null:   # a press left Easy Part: back to it from the start screen (logged)
			trace.store_line("s%d #%d left Easy Part: reopen" % [sd, step])
			hist.append("%d reopen Easy Part (left it)" % step)
			await new_main()
			if not await open_easy():
				problem = "could not reopen Easy Part"
				break
			ep = cur_ep()
		if count_btns(ep) < 5:   # Expert (or a page change) hid the Easy rows: back to Easy from the start screen (logged)
			trace.store_line("s%d #%d Easy rows hidden: reopen from the start screen" % [sd, step])
			hist.append("%d reopen Easy Part (its rows were hidden)" % step)
			await new_main()
			if not await open_easy():
				problem = "could not reopen Easy Part"
				break
			continue
		log_errs.errs.clear()
		var f0 := Engine.get_frames_drawn()
		var line := await do_input(step, ep)
		await idle(3)
		hist.append(line)
		trace.store_line("s%d %s" % [sd, line])
		trace.flush()
		problem = check(cur_ep(), f0)
		if problem != "":
			problem = "step %d: %s" % [step, problem]
			break
	var last := hist.slice(maxi(0, hist.size() - LAST_N))
	if problem != "":
		var fp := FileAccess.open("%s/fail_s%d.txt" % [SHOT, sd], FileAccess.WRITE)
		fp.store_line("seed %d" % sd)
		fp.store_line("problem: %s" % problem)
		fp.store_line("last %d inputs:" % last.size())
		for l in last:
			fp.store_line("  " + str(l))
		fp.close()
		await _shot("fail_s%d" % sd)
		ok(false, "s%d %s (seed %d; last inputs in fail_s%d.txt)" % [sd, problem, sd, sd])
	else:
		await _shot("end_s%d" % sd)
		ok(true, "s%d %d inputs: no error, undo in range, part replays, window responds (undo %d)" % [sd, hist.size(), m.undo.size()])


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	OS.add_logger(log_errs)
	trace = FileAccess.open("%s/trace.txt" % SHOT, FileAccess.WRITE)
	if not Part.available():
		print("FAIL: no KineCAD DLL, the Easy Part monkey cannot run")
		quit(1)
		return
	var seeds: Array = SEEDS
	var pick := OS.get_environment("NCHAOS_SEEDS")   # e.g. NCHAOS_SEEDS=1,2 to run part of the list (a tool call is 10 min)
	if pick != "":
		seeds = []
		for x in pick.split(","):
			seeds.append(int(x))
	for sd in seeds:
		await run_seed(sd)
	trace.close()
	print("nchaos: %d fail (seeds %s, %d Easy Part openings)" % [fails, str(seeds), opened])
	quit(1 if fails > 0 else 0)
