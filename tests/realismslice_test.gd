## godot --path . --position 4000,4000 -s tests/realismslice_test.gd   (REALISM / TIMING COACH SLICES: the scene database and the suggestions in slices, the score in stages)
## Bars, written before measuring (Nick: "Realism score and Timing coach still freeze"). Every click is a real one (root.push_input).
##  (a) Timing coach, cold database, on combo3: the longest frame from the click to the list is < 100 ms
##  (b) TimingCoach.compute_co (sliced) gives EXACTLY the blocking TimingCoach.compute's suggestions (var_to_str equal)
##  (c) Timing coach on the warm database, combo3: the longest frame from the click to the list is < 100 ms
##  (d) Realism score, cold database: the longest frame while the scenes are read is < 100 ms; the window keeps drawing during the score
##      (at least 12 frames while it runs, one between each stage and judge)
##  (e) the sliced score's number is the blocking refresh()'s number (cold caches), to 0.01 points
##  (f) a second click during the score cancels it within 60 frames; the panel keeps its last score; nothing is half written
##  (g) quitting with a database read still running: the process exits 0 (the crash at exit of 10-26 has this shape)
extends SceneTree

const MAX_MS := 100.0
var m: Node
var fails := 0
var errs := 0
var lg: Logger


## counts the engine's errors (as crashcheck does): its callback reaches this run's SceneTree, so it must be removed before the quit
class ErrCount extends Logger:
	var t
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtraces: Array) -> void:
		t.errs += 1


func ok(good: bool, what: String) -> void:
	print(("ok   " if good else "FAIL ") + what)
	if not good:
		fails += 1


func walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children(true):
		walk(c, out)
	return out


func ribbon(txt: String, page := "CHECK") -> Button:
	for n in walk(m.ui_ribbon[page], []):
		if n is Button and (str(n.get_meta("label")) if n.has_meta("label") else (n as Button).text.strip_edges()) == txt:
			return n
	return null


## the real click: mouse motion, press, release on the button's centre
func click(b: Button) -> void:
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


## frames until done.call() or n frames; returns [longest frame ms, frames run]
func frames_until(done: Callable, n: int) -> Array:
	var worst := 0.0
	var last := Time.get_ticks_usec()
	var k := 0
	for i in n:
		await process_frame
		k += 1
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		if done.call():
			break
	return [worst, k]


func cold(keep_db := false) -> void:
	MotionMatch._cache.clear()
	if not keep_db:
		m.tc_ui.db = {}
	m.rs_ui._memo = {}
	m.rs_ui.jcache = {}
	m.rs_ui.gains = {}
	m.force_cache = {}
	FrameMemo.reset()


func _init() -> void:
	lg = ErrCount.new()
	lg.t = self
	OS.add_logger(lg)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 6:
		await process_frame
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._page_set("CHECK")
	for i in 6:
		await process_frame
	var name_s: String = String(m.S.name)

	# (a) the timing coach, cold: the read is sliced, then the suggestions
	cold()
	m.ui_find.visible = false
	click(ribbon("Timing coach"))
	var r_a := await frames_until(func(): return m.ui_find.visible and not m.tc_ui._reading and not m.tc_ui._computing, 60000)
	ok(r_a[0] < MAX_MS, "(a) timing coach, cold database, combo3: the longest frame %.0f ms (< %.0f; %d frames)" % [r_a[0], MAX_MS, r_a[1]])
	var sugs_click: Array = m.tc_ui.sugs.duplicate(true)
	ok(int(m.tc_ui.db.get("n", 0)) > 0, "(a) the database read: %d clips" % int(m.tc_ui.db.get("n", 0)))

	# (b) the sliced suggestions are the blocking ones
	var keepB: Dictionary = m.B.state()
	var plainB: Array = TimingCoach.compute(m.S, m.B, m.tc_ui.db, name_s)
	m.B.set_state(keepB)
	m.B.fk()
	FrameMemo.slice_begin(8.0)
	var slicedB: Array = await TimingCoach.compute_co(m.S, m.B, m.tc_ui.db, name_s)
	FrameMemo.slice_end()
	m.B.set_state(keepB)
	m.B.fk()
	ok(not plainB.is_empty() and var_to_str(slicedB) == var_to_str(plainB), "(b) compute_co == compute: %d suggestions, identical" % plainB.size())
	ok(var_to_str(sugs_click) == var_to_str(plainB), "(b) the panel's list is the blocking compute's list")

	# (c) the timing coach, warm: only the suggestions are made
	m.ui_find.visible = false
	click(ribbon("Timing coach"))
	var r_c := await frames_until(func(): return not m.tc_ui._computing, 600)
	ok(r_c[0] < MAX_MS, "(c) timing coach, warm database, combo3: the longest frame %.0f ms (< %.0f; %d frames)" % [r_c[0], MAX_MS, r_c[1]])

	# (d) the realism score, cold: the read in slices, then the score in stages
	cold()
	m.ui_find.visible = false
	click(ribbon("Realism score"))
	var r_d1 := await frames_until(func(): return not m.tc_ui._reading or not m.rs_ui.busy, 60000)
	ok(r_d1[0] < MAX_MS, "(d) realism score, cold: the longest frame while the scenes are read %.0f ms (< %.0f; %d frames)" % [r_d1[0], MAX_MS, r_d1[1]])
	var r_d2 := await frames_until(func(): return not m.rs_ui.busy, 600000)
	ok(r_d2[1] >= 12, "(d) the window keeps drawing while the score runs: %d frames (>= 12); longest frame %.0f ms (not a bar: the judges' own stages)" % [r_d2[1], r_d2[0]])
	var sliced_score := float(m.rs_ui.res.get("score", -1.0))
	ok(m.ui_find.visible and m.rs_ui.res.size() > 0, "(d) the panel shows the score (%.2f)" % sliced_score)

	# (e) the same number as the blocking refresh
	var dbd: Dictionary = m.tc_ui.db.duplicate()
	cold()
	m.tc_ui.db = dbd   # the same database for both: the panel read it, the blocking refresh reads the same one
	m.rs_ui.refresh()
	var plain_score := float(m.rs_ui.res.get("score", -2.0))
	ok(absf(plain_score - sliced_score) < 0.01, "(e) the sliced score %.2f == the blocking refresh %.2f" % [sliced_score, plain_score])

	# (f) a second click during the score cancels it
	var before_res: Dictionary = m.rs_ui.res.duplicate(true)   # the score of (e): the panel's last one
	m.rs_ui._memo = {}
	m.rs_ui.jcache = {}
	m.rs_ui.gains = {}
	m.force_cache = {}
	FrameMemo.reset()
	m.ui_find.visible = false
	click(ribbon("Realism score"))
	await frames_until(func(): return false, 4)
	click(ribbon("Realism score"))
	var r_f := await frames_until(func(): return not m.rs_ui.busy, 60)
	ok(not m.rs_ui.busy and r_f[1] < 60, "(f) a second click cancels the score within 60 frames (%d)" % r_f[1])
	ok(not before_res.is_empty() and var_to_str(m.rs_ui.res) == var_to_str(before_res), "(f) the cancelled score left the panel's last score as it was")
	ok(m.S.cards.size() == 12 and not FrameMemo.on and FrameMemo.slice_ms == 0.0, "(f) no scene change, the memo off, no slice left on")

	# (g) quit with a database read still going: the last thing this run does (a crash at exit fails the suite by its exit code)
	cold()
	m.ui_find.visible = false
	click(ribbon("Realism score"))
	await frames_until(func(): return false, 3)
	print("ok   (g) quitting with the read still running (%s)" % ("reading" if m.tc_ui._reading else "idle"))
	print("realismslice_test: %d fail(s)" % fails)
	quit(1 if fails > 0 else 0)
