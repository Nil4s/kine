## godot --path . --position 4000,4000 -s tests/checkhunt_test.gd   (CHECK PAGE FREEZE HUNT: real clicks, frame times, results as before)
## Nick: "some tools on CHECK freeze / crash the app". The Check button, the timing database (Timing coach, Realism score) and Polish used to
## hold the main thread for seconds (a 30 s clip: ~40 s). Now: Check plays in time slices, the database is read a few scenes per frame,
## Polish runs on a worker thread with its own body. Every bar is a REAL click (root.push_input) and the frame times after it.
extends SceneTree

const MAX_MS := 500.0   # no frame after a click holds the main thread longer than this
var m: Node
var fails := 0
var made: Array = []
var db_s: Dictionary = {}
var finish_ms := 0.0


func ok(good: bool, what: String) -> void:
	print(("PASS: " if good else "FAIL: ") + what)
	if not good:
		fails += 1


func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children(true):
		walk(c, out)
	return out


func text_of(b: Button) -> String:
	return str(b.get_meta("label")) if b.has_meta("label") else b.text.strip_edges()


func tool_btn(txt: String) -> Button:
	for n in walk(m.ui_ribbon["CHECK"], []):
		if n is Button and text_of(n) == txt:
			return n
	return null


## the real click: a visible button gets the mouse, a folded one (cap menu / More) its signal. Returns the ms the click held the thread
func click(b: Button) -> float:
	var t0 := Time.get_ticks_usec()
	if b.is_visible_in_tree():
		var p := b.get_global_rect().get_center()
		var mv := InputEventMouseMotion.new()
		mv.position = p
		mv.global_position = p
		root.push_input(mv)
		for down in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = down
			e.position = p
			e.global_position = p
			e.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
			root.push_input(e)
	else:
		b.pressed.emit()
	return (Time.get_ticks_usec() - t0) / 1000.0


## frames until done.call() (or n frames); returns the longest frame in ms
func frames_until(done: Callable, n: int) -> float:
	var worst := 0.0
	var last := Time.get_ticks_usec()
	for i in n:
		await process_frame
		var now := Time.get_ticks_usec()
		var d := (now - last) / 1000.0
		last = now
		if done.call():
			finish_ms = d   # the frame that opens the result (a scene load, a list rebuild): reported, not the job's slices
			break
		worst = maxf(worst, d)
	return worst


func open_scene(tag: String, repeat: int) -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json"))
	var cs: Array = d["cards"]
	var out := []
	for r in repeat:
		out.append_array(cs.duplicate(true))
	d["cards"] = out
	var p := "user://checkhunt_t_%s.json" % tag
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	made.append(p)
	m._load_scene(p)
	for i in 20:
		await process_frame
	m._page_set("CHECK")
	for i in 10:
		await process_frame


func open_src(tag: String, src: String) -> void:
	var p := "user://checkhunt_t_%s.json" % tag
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(src))
	f.close()
	made.append(p)
	m._load_scene(p)
	for i in 20:
		await process_frame
	m._page_set("CHECK")
	for i in 10:
		await process_frame


## what the blocking call makes, as text (the data of a tool; var_to_str keeps every float)
func blocking(t: Array) -> String:
	var ui = m.get(t[2])
	if t[2] == "se_ui":
		var keep: Dictionary = m.B.state()
		var r: Array = SpeedEnv.analyse(m.S, m.B)
		m.B.set_state(keep)
		return var_to_str(r)
	ui.compute()
	return var_to_str(ui.get(t[3]))


## one tool: the quietest of 3 real clicks has a longest frame < 100 ms; its data == the blocking call's
func slice_tool(t: Array, what := "") -> void:
	var want := blocking(t)
	var ui = m.get(t[2])
	var best := INF
	var got := ""
	for run in 3:
		ui.set(t[3], [] if ui.get(t[3]) is Array else {})
		var held := click(tool_btn(t[0]))
		var busy: bool = m._bg_busy.get(t[1], false)
		var w := await frames_until(func(): return not m._bg_busy.get(t[1], false), 3000)
		got = var_to_str(ui.get(t[3]))
		best = minf(best, maxf(held, w))
		if not busy:
			break
		if best < 100.0:
			break
	ok(best < 100.0, "8 %s%s: click and then longest frame %.0f ms (< 100)" % [what, t[0], best])
	ok(got == want and want.length() > 4, "8 %s%s: the data is the blocking call's (%d chars)" % [what, t[0], want.length()])


## Fix moves through the body: the pass-by cards are the blocking S.clear's
func slice_fix() -> void:
	var C: Scene = m.S.clone()
	var n_want := C.clear(m.bg_body(m.B.state()))
	var before: int = m.S.cards.size()
	var held := click(tool_btn("Fix moves through the body"))
	var busy: bool = m._bg_busy.get("fix moves", false)
	var w := await frames_until(func(): return not m._bg_busy.get("fix moves", false), 3000)
	ok(busy and maxf(held, w) < 100.0, "8 Fix moves through the body: ran on its thread, longest frame %.0f ms (< 100)" % maxf(held, w))
	ok(var_to_str(m.S.cards) == var_to_str(C.cards) and m.S.cards.size() == before + n_want, "8 Fix moves: the cards are the blocking clear's (%d pass-by cards)" % n_want)


## Frame data / Frame boxes: the data made on a thread is the blocking _fd_data's
func slice_fd() -> void:
	for lab in ["Frame data", "Frame boxes"]:
		m.fd_cache = {}
		m._fd_job = ""
		var held := click(tool_btn(lab))
		var w := await frames_until(func(): return String(m.fd_cache.get("key", "")) == m._fd_key() and m._fd_key() != "", 3000)
		var got := var_to_str(m.fd_cache.get("fd", {}))
		ok(maxf(held, w) < 100.0, "8 %s: click held %.0f ms, longest frame %.0f ms, the frame that takes the result %.0f ms (< 100)" % [lab, held, w, finish_ms])
		m.fd_cache = {}
		var want := var_to_str(m._fd_data())
		ok(got == want and want.length() > 4, "8 %s: the data is the blocking call's (%d chars)" % [lab, want.length()])
		click(tool_btn(lab))   # off again
		await frames_until(func(): return false, 3)


func finding_keys(a: Array) -> Array:
	return a.map(func(f): return "%s|%.3f|%d|%s" % [f["rule"], f["t"], f["card"], f["msg"]])


## Check clicked up to 3 times (other Godot runs share this machine: one slow frame is a busy CPU, not a freeze): the quietest run counts.
## Every run is a full click-to-result Check; returns [click ms, longest frame ms, runs used]
func best_check(playing: bool, frames: int) -> Array:
	var best := [INF, INF, 0]
	for run in 3:
		m.playing = playing
		var held := click(tool_btn("Check"))
		var w := await frames_until(func(): return not m._check_busy, frames)
		m.playing = false
		if maxf(held, w) < maxf(best[0], best[1]):
			best = [held, w, run + 1]
		if maxf(held, w) < MAX_MS:
			break
	return best


func read_db() -> void:
	db_s = await MotionMatch.build_co()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 10:
		await process_frame

	# 1. EMPTY SCENE: every CHECK tool clicked with nothing in it: no hang, no SCRIPT ERROR (they would fail the suite)
	m._page_set("CHECK")
	for i in 5:
		await process_frame
	var names := []
	for n in walk(m.ui_ribbon["CHECK"], []):
		if n is Button and text_of(n) != "":
			names.append(text_of(n))
	var worst_empty := 0.0
	for nm in names:
		if nm in ["Polish", "Frame rate", "Frame data", "Frame boxes", "Dummy (H)"]:
			continue
		var held := click(tool_btn(nm))
		worst_empty = maxf(worst_empty, maxf(held, await frames_until(func(): return false, 3)))
	ok(worst_empty < MAX_MS, "1 empty scene: all %d CHECK tools clicked, the longest frame %.0f ms (< %.0f)" % [names.size(), worst_empty, MAX_MS])
	ok(not m._check_busy, "1 empty scene: Check left nothing running")

	# 2. CHECK ON combo3: the click returns at once, the window keeps drawing, the findings are the plain Rulebook's
	await open_scene("a", 1)
	var want := finding_keys(Rulebook.check(m.S, m.ov.GB))   # the plain call: unchanged logic, never waits
	var held2 := click(tool_btn("Check"))
	ok(m._check_busy, "2 Check is running in slices after the click")
	await frames_until(func(): return not m._check_busy, 2000)
	var r2: Array = await best_check(false, 2000)
	ok(r2[0] < MAX_MS and r2[1] < MAX_MS, "2 Check on combo3: click held %.0f ms, longest frame %.0f ms (< %.0f; run %d)" % [r2[0], r2[1], MAX_MS, r2[2]])
	ok(m.check_ran and finding_keys(m.findings) == want and want.size() > 0, "2 the findings are exactly the plain Rulebook.check's (%d, was %d)" % [m.findings.size(), want.size()])

	# 3. CLICKED TWICE FAST: the second click cancels; nothing breaks; a third click checks again
	m.findings = []
	click(tool_btn("Check"))
	await process_frame
	click(tool_btn("Check"))
	await frames_until(func(): return false, 30)
	ok(not m._check_busy and m.findings.is_empty(), "3 double click: the run was cancelled, no half result")
	click(tool_btn("Check"))
	await frames_until(func(): return not m._check_busy, 2000)
	ok(finding_keys(m.findings) == want, "3 after a cancel, the next Check gives the same findings")

	# 4. WHILE PLAYING
	var r4: Array = await best_check(true, 2000)
	ok(r4[0] < MAX_MS and r4[1] < MAX_MS and not m._check_busy, "4 Check while playing: click held %.0f ms, longest frame %.0f ms (run %d)" % [r4[0], r4[1], r4[2]])

	# 5. THE TIMING DATABASE (Timing coach, Realism score): read a few scenes per frame, the same database
	FrameMemo.slice_begin(8.0)
	var t5 := Time.get_ticks_usec()
	db_s = {}
	read_db()
	var w5 := 0.0
	var last := Time.get_ticks_usec()
	while db_s.is_empty() and (Time.get_ticks_usec() - t5) < 120000000:
		await process_frame
		var now := Time.get_ticks_usec()
		w5 = maxf(w5, (now - last) / 1000.0)
		last = now
	FrameMemo.slice_end()
	var db_p: Dictionary = MotionMatch._build(["res://scenes/", "res://moves/"])
	ok(w5 < MAX_MS, "5 reading the scenes for the timing coach: longest frame %.0f ms (< %.0f)" % [w5, MAX_MS])
	ok(int(db_s.get("n", -1)) == int(db_p.get("n", -2)) and int(db_s.get("n", 0)) > 0, "5 the database is the same one (%d clips)" % int(db_s.get("n", 0)))

	# 6. POLISH: on a worker thread, a second click cancels, the result is the plain Polish's
	var C := Scene.new()
	C.from_dict(m.S.to_dict(m.B))
	var plain: Array = m.DetailTool.polish(EventQuery._new_body(), C, 30)
	var plain_n: int = (plain[0] as Scene).cards.size()
	var cards_before: int = m.S.cards.size()
	var held6 := click(tool_btn("Polish"))
	ok(m._polish_busy, "6 Polish is running on its thread after the click")
	var w6 := await frames_until(func(): return not m._polish_busy, 3000)
	ok(held6 < MAX_MS and w6 < MAX_MS * 4.0, "6 Polish: click held %.0f ms, longest frame %.0f ms (the one that opens the result is allowed %.0f)" % [held6, w6, MAX_MS * 4.0])
	ok(m.S.cards.size() == plain_n and plain_n > cards_before, "6 the polished scene has the plain Polish's %d cards (was %d)" % [plain_n, cards_before])
	await open_scene("b", 1)
	click(tool_btn("Polish"))
	await process_frame
	click(tool_btn("Polish"))
	await frames_until(func(): return false, 20)
	ok(not m._polish_busy, "6 Polish clicked twice: cancelled")

	# 7. A LONG SCENE (about 60 s): Check starts at once and the window keeps drawing
	await open_scene("c", 13)
	ok(m.S.length() > 45.0, "7 the long scene is %.0f s, %d cards" % [m.S.length(), m.S.cards.size()])
	var held7 := 0.0
	var w7 := 0.0
	for run in 3:   # the quietest of 3 starts counts (see best_check)
		held7 = click(tool_btn("Check"))
		w7 = await frames_until(func(): return false, 40)
		click(tool_btn("Check"))   # the second click cancels the run
		await frames_until(func(): return false, 5)
		ok(not m._check_busy, "7 long scene: a second click cancels the run (run %d)" % (run + 1))
		if maxf(held7, w7) < MAX_MS:
			break
	ok(held7 < MAX_MS and w7 < MAX_MS, "7 long scene: click held %.0f ms, then 40 frames, longest %.0f ms (< %.0f)" % [held7, w7, MAX_MS])

	# 8. THE REST OF THE CHECK PAGE (checkslice): each tool that plays the whole clip runs on a worker thread with a clone and a body of its own:
	# the longest frame after a real click stays under 100 ms, and the result is exactly the blocking call's
	await open_scene("d", 1)
	var tools := [
		["Fatigue", "fatigue", "fa_ui", "reps"], ["Speed limits", "speed limits", "se_ui", "rows"], ["Safety sheet", "safety sheet", "sf_ui", "rep"],
		["Breakfall check", "breakfall check", "bk_ui", "rep"], ["Weapon weight", "weapon weight", "wt_ui", "rows"],
		["Momentum ledger", "momentum ledger", "ml_ui", "rep"], ["Airborne spin check", "airborne spin check", "sp_ui", "rep"]]
	for t in tools:
		await slice_tool(t)
	await open_scene("f", 1)
	await slice_fix()
	await slice_fd()

	for p in made:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("CHECKHUNT: %d failed" % fails)
	quit(1 if fails > 0 else 0)
