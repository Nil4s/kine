extends SceneTree
## godot --path . --position 4000,4000 -s tests/fspeed_test.gd     (FSPEED: the Easy Part steps are fast for a beginner; scripts/easy_part.gd _make; needs the CAD DLL and a window)
## Real clicks (root.push_input) at 1280 x 720, from the BUILDING card on a blank part. Each step is timed click-to-picture:
## from the mouse-down of the click to the next frame painted (RenderingServer.frame_post_draw). Five samples per step, each on a fresh blank part.
## Only the step's own click is timed; the prep (a drawn shape, a pulled solid, two shapes) is real clicks and drags, untimed.
## Bars (per step: median of 5 under 300 ms; each sample must change the part, or the step was refused and the timing means nothing):
##   draw, pull, round, hole (Cut a hole), split (Cut in two), repeat, blend, mirror
## shots: C:/Temp/claude/fspeed/<step>.png (the picture after the first sample of each step)
const SHOT := "C:/Temp/claude/fspeed"
const DIRT := "user://fspeed_test"
const BAR_MS := 300.0
const N := 5

var fails := 0
var m: Node
var results := {}


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


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func pu() -> PartUI:
	return m.bld.part


func ep():
	return pu().ep


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


## a real click on a control; returns the ms from the mouse-down to the next painted frame after the release
func click_ms(c: Control) -> float:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	var t0 := Time.get_ticks_usec()
	await ev_mouse(p, false)
	await RenderingServer.frame_post_draw
	return (Time.get_ticks_usec() - t0) / 1000.0


## a drag on the floor from world a to world b (metres); untimed
func draw_floor(a: Vector3, b: Vector3) -> void:
	var pa := scr(a)
	var pb := scr(b)
	await ev_move(pa, false)
	await ev_mouse(pa, true)
	for i in range(1, 13):
		await ev_move(pa.lerp(pb, i / 12.0))
	await ev_mouse(pb, false)
	await idle(3)


func shot(nm: String) -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func fresh() -> void:
	m.S.part = Part.make("Part")
	pu().upto = -1
	pu().sync()
	ep().armed = ""   # a Draw press toggles: a tool left armed by the last sample would switch off
	m.target = Vector3(0.0, 0.0, 0.0)
	m.pitch = -40.0
	m.yaw = 20.0
	m._cam()
	await idle(60)


func nsteps() -> int:
	return (ep()._rec().get("features", []) as Array).size()


func prep_shape() -> void:
	await click_ms(ep().make_btns["draw"])
	await draw_floor(Vector3(-0.06, 0.0, -0.04), Vector3(0.06, 0.0, 0.04))


func prep_solid() -> void:
	await prep_shape()
	await click_ms(ep().make_btns["pull"])


func prep_two_shapes() -> void:
	await prep_shape()
	await click_ms(ep().make_btns["draw"])
	await draw_floor(Vector3(0.1, 0.0, -0.04), Vector3(0.2, 0.0, 0.04))


## one step: N fresh parts, the prep untimed, the step's own click timed; returns [median, samples, changed count]
func measure(step: String, prep: Callable, btn: String) -> void:
	var samples := []
	var changed := 0
	for i in N:
		await fresh()
		await prep.call()
		var n0 := nsteps()
		var u0: int = m.undo.size()
		var ms := await click_ms(ep().make_btns[btn])
		await idle(2)
		var did: bool = (ep().armed == "draw") if step == "draw" else (nsteps() != n0 or m.undo.size() != u0)
		if did:
			changed += 1
		else:
			print("fspeed %s sample %d did not change: steps %d -> %d, undo %d -> %d" % [step, i, n0, nsteps(), u0, m.undo.size()])
		samples.append(ms)
		if i == 0:
			shot(step)
	samples.sort()
	var med: float = samples[N / 2]
	results[step] = med
	print("fspeed %-7s median %.0f ms  samples %s  changed %d/%d" % [step, med, str(samples.map(func(x): return snappedf(x, 1.0))), changed, N])
	ok(changed == N, "%s each click took effect (%d/%d)" % [step, changed, N])
	ok(med < BAR_MS, "%s median %.0f ms under %.0f" % [step, med, BAR_MS])


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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ms(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	await fresh()
	ok(pu().on and pu().easy and ep().make_btns.has("draw"), "0 BUILDING card opens the blank Easy Part")

	await measure("draw", Callable(self, "_nothing"), "draw")
	await measure("pull", Callable(self, "prep_shape"), "pull")
	await measure("round", Callable(self, "prep_solid"), "round")
	await measure("hole", Callable(self, "prep_solid"), "hole")
	await measure("split", Callable(self, "prep_solid"), "split")
	await measure("repeat", Callable(self, "prep_solid"), "repeat")
	await measure("blend", Callable(self, "prep_two_shapes"), "blend")
	await measure("mirror", Callable(self, "prep_solid"), "mirror")

	var worst := ""
	var wv := -1.0
	for k in results:
		if results[k] > wv:
			wv = results[k]
			worst = k
	print("fspeed: slowest %s %.0f ms" % [worst, wv])
	print("fspeed: %d fail" % fails)
	quit(1 if fails > 0 else 0)


func _nothing() -> void:
	pass
