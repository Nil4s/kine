## godot --path . -s tests/gentle_test.gd     (ROADMAP 60; needs a window: the real poser UI is built)
## GENTLE ERRORS: never a crash dialog, always a next step. EVERY command in the registry (main._commands(), the list
## undo_audit and the agent tools use) is run from several HOSTILE start states:
##   EMPTY     no cards at all                   NOPICK    combo3, no weapon but its handle "picked", no card, no prop picked
##   ONECARD   a scene of one card               PROPGONE  a set prop whose model file is missing
##   POSEFILE  a pose file opened as a scene     NAN       a scene file with infinity / null where a card's angle, move, hold and lift go
##   ZERORANGE the card range and the preview range have zero length (in == out, first == last)
## Bars (stated before measuring), for every command x state cell:
##   B1  no engine error on the Godot output: a custom Logger (OS.add_logger, 4.5+) sees every SCRIPT ERROR / push_error /
##       C++ error raised while the command runs (warnings are not counted)
##   B2  the app still responds: main is valid, its scene is a Scene, and two frames render (the frame counter moves)
##   B3  if the command did nothing (body and scene unchanged) and is an edit, the status line says so with a next step:
##       a verb from say_next_test's NEXT list (an edit that refused SILENTLY is a failure)
## Commands that write files / open dialogs / are the undo itself are skipped with undo_audit's reasons (its SKIP table).
extends SceneTree

const STATES := ["EMPTY", "NOPICK", "ONECARD", "PROPGONE", "POSEFILE", "NAN", "ZERORANGE"]
## the NEXT verbs of say_next_test.gd (a message that tells the user what to do)
const NEXT := ["pick", "click", "press", "open", "lock", "put", "add", "turn", "move", "type", "tick", "untick", "use",
	"select", "drag", "choose", "copy", "make", "free", "try", "give", "save", "close", "run"]
## commands that do nothing from a state and say nothing, on purpose (reason each)
const NAN_FILE := "user://zz_gentle_nan.json"
const QUIET := {}
## skipped here besides undo_audit's table
const SKIP2 := {"export_for_unreal_5...": "writes exports/ (a file)", "export_for_unity...": "writes exports/ (a file)", "export_for_godot...": "writes exports/ (a file)",
	"review_export_a_review_page": "writes exports/review/ (a file)",
	"live_start_the_webcam_puppet": "starts a python tracker on the webcam (live_puppet_test runs it on a recorded file)"}

class Catch extends Logger:
	var errs: Array = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _bt: Array) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		errs.append("%s:%d %s %s" % [file.get_file(), line, code, rationale])

var fails := 0
var m: Node
var lg := Catch.new()
var problems := {}   # "cmd @ state" -> what
var cells := 0
var dirty := true
var last_kind := ""
var need_fresh := false
var reg := {}   # id -> the command of the app now running


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func fp() -> String:
	var sd := {"cards": m.S.cards, "name": m.S.name, "natural": m.S.natural, "spline": m.S.spline, "on_floor": m.S.on_floor,
		"part_keys": var_to_str(m.S.part_keys), "markers": m.S.markers, "notes": m.S.notes, "layer": var_to_str(m.S.layer),
		"layers": var_to_str(m.S.layers), "audio": var_to_str(m.S.audio), "ik": var_to_str(m.S.ik), "cons": var_to_str(m.S.cons),
		"props": JSON.stringify(m.S.props.map(func(q): return Props.to_dict(q))), "shots": var_to_str(m.S.shots),
		"sets": var_to_str(m.S.sets), "clips": var_to_str(m.S.clips), "drivers": var_to_str(m.S.drivers),
		"secondary": var_to_str(m.S.secondary), "lip": var_to_str(m.S.lip), "plants": var_to_str(m.S.plants),
		"body": var_to_str(m.S.body), "fps": m.S.fps, "n_actors": m.S.actors.size()}
	return var_to_str(m.B.state()) + "|" + var_to_str(sd) + "|" + str(m.scene_path)


func start(kind: String) -> void:
	m.playing = false
	m.stepped_view = false
	m.pv_in = -1.0
	m.pv_out = -1.0
	m.sel_prop = -1
	m.sel_more = []
	m.sel_end = -1
	m._range_of = -1
	if kind == "EMPTY":
		m._new_scene()
		m.sel = "lowerarm_r"
	elif kind == "POSEFILE":
		m._load_scene("res://poses/stand.json")   # a pose file where a scene belongs
		m._rebuild_cards()
		m.sel = "lowerarm_r"
	else:
		m._load_scene("res://scenes/combo3.json")
		m._rebuild_cards()
		m._card_pick(2)
		m.sel = "lowerarm_r"
		if kind == "NOPICK":
			# the app never clears its pick (sel is always a joint), so "no part picked" is: the weapon's handle picked
			# with no weapon in the hand, no card picked and no prop picked
			m._bat_remove()
			m.sel = "bat_handle"
			m.sel_card = -1
			m._rebuild_cards()
		elif kind == "ONECARD":
			m.S.cards = [m.S.cards[0]]
			m.S.cards[0]["move"] = -1.0
			m._rebuild_cards()
			m._card_pick(0)
		elif kind == "PROPGONE":
			if not Props.EXTRA.has("zz_gone"):   # once: a worker thread may be reading the table
				Props.register("zz_gone", AABB(Vector3(-0.3, 0, -0.3), Vector3(0.6, 0.6, 0.6)), "user://library/props/zz_gone_missing.glb", 1.0)
			m.S.props = [Props.make("zz_gone", Props.xf_at(Vector3(1.0, 0.0, 0.6), 0.0))]
			m.sel_prop = 0
			m._props_show()
		elif kind == "NAN":
			# numbers that are not numbers, as a file can hold them (1e999 reads as infinity, null where a number goes)
			var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json"))
			var cs: Array = d["cards"]
			var pj: Dictionary = cs[2]["pose"]["joints"]
			for j in ["upperarm_r", "lowerarm_r", "head"]:
				if pj.has(j):
					pj[j]["bend"] = "@@INF@@"
					pj[j]["side"] = "@@INF@@"
			cs[2]["move"] = "@@INF@@"
			cs[2]["hold"] = null
			cs[1]["hold"] = "@@INF@@"
			cs[1]["lift"] = null
			cs[3]["move"] = "@@INF@@"
			var f := FileAccess.open(NAN_FILE, FileAccess.WRITE)
			f.store_string(JSON.stringify(d).replace("\"@@INF@@\"", "1e999"))
			f.close()
			m._load_scene(NAN_FILE)
			m._rebuild_cards()
			m._card_pick(2)
			m.sel = "lowerarm_r"
		elif kind == "ZERORANGE":
			m.sel_card = 1
			m.sel_end = 1
			m._range_of = 1
			m.pv_in = 1.0
			m.pv_out = 1.0
			m.playhead = 1.0
	m._refresh()
	m.undo.clear()
	m.redo.clear()
	m._say_plain("")
	await process_frame


## what a command can leave open: dialogs (a second exclusive popup is an engine error), the webcam puppet, a co-edit
func cleanup() -> void:
	for w in m.get_children():
		if w is Window and (w as Window).visible:
			(w as Window).hide()
	m.mm_ui.halt()   # motion matching steers the body every frame while it is on
	if m.live.running:
		m.live.stop()
	if m.co != null:
		m._co_stop(false)


## the status line, empty after a start
func status() -> String:
	return String(m.ui_status.text) if m.ui_status != null else ""


func has_next(t: String) -> bool:
	var words := {}
	for w in RegEx.create_from_string("[a-z]+").search_all(t.to_lower()):
		words[w.get_string()] = true
	return NEXT.any(func(v): return words.has(v))


## a command can leave a panel open that makes every later frame slow (the graph editor: 0.4 s a frame), or a view
## toggle on: a fresh app every FRESH_EVERY cells keeps each cell measuring the command, not the last one's leftovers
var FRESH_EVERY := 60


func fresh() -> void:
	if m != null:
		cleanup()
		root.remove_child(m)
		m.queue_free()
		await process_frame
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	reg = {}
	for c in m._commands():   # the callables are bound to THIS app
		reg[c["id"]] = c


func kids_changed(k0: int) -> bool:
	return m.get_child_count() != k0


func trial(c0: Dictionary, kind: String) -> void:
	var tc := Time.get_ticks_msec()
	if cells % FRESH_EVERY == 0 or need_fresh:
		need_fresh = false
		await fresh()
		dirty = true
	var c: Dictionary = reg[c0["id"]]
	await trial2(c, kind)
	need_fresh = false
	if Time.get_ticks_msec() - tc > 1000:
		print("     cell %d %s %d ms nodes %d objects %d orphan %d fps %d" % [cells, c["id"], Time.get_ticks_msec() - tc, Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT), Performance.get_monitor(Performance.TIME_FPS)])
	if Time.get_ticks_msec() - tc > 1500:
		print("     slow cell %s @ %s: %d ms" % [c["id"], kind, Time.get_ticks_msec() - tc])


func trial2(c: Dictionary, kind: String) -> void:
	cleanup()
	if OS.get_cmdline_user_args().has("trace"):   # a crash loses the buffered output: the last cell reached is kept on disk
		var tf := FileAccess.open("user://gentle_last.txt", FileAccess.WRITE)
		tf.store_string("%s @ %s" % [c["id"], kind])
		tf.close()
	# BATCHED: a command that changed nothing leaves the start state as it was, so the next one runs on it as it stands
	# (a start is a scene load + a full UI rebuild: most of a cell's time); any change, error or popup restarts it
	if dirty or last_kind != kind or OS.get_cmdline_user_args().has("nobatch"):
		await start(kind)
	else:
		m._say_plain("")
	last_kind = kind
	dirty = true
	lg.errs.clear()
	var f0 := fp()
	var kids0: int = m.get_child_count()
	var u0: int = m.undo.size()
	m._say_plain("")
	m._why_cmd = c["name"]
	var f_before := Engine.get_process_frames()
	(c["run"] as Callable).call()
	var said_now := status()   # before the frames: a per-frame readout (motion match) may take the line over
	await process_frame
	m.playing = false
	cells += 1
	var key := "%s @ %s" % [c["id"], kind]
	var errs: Array = lg.errs.duplicate()
	var alive: bool = is_instance_valid(m) and m.S is Scene and Engine.get_process_frames() >= f_before + 1
	var f1 := fp()
	var opened := m.get_child_count() > kids0   # a dialog or panel was put up: that is the answer, not a silent refusal
	for w in m.get_children():
		if w is Window and (w as Window).visible:
			opened = true
	var did_nothing: bool = f1 == f0 and m.undo.size() == u0 and not opened
	var said := said_now if said_now.strip_edges() != "" else status()
	var bad := ""
	if not errs.is_empty():
		bad += "ENGINE ERROR: %s; " % str(errs[0]).left(150)
	if not alive:
		bad += "APP NOT RESPONDING; "
	if did_nothing and c["edits"] and not QUIET.has(c["id"]) and said.strip_edges() == "":
		bad += "SILENT REFUSAL (edit did nothing, status line empty); "
	elif WhyWrong.is_problem(said) and not has_next(said):
		bad += "NO NEXT STEP in %s; " % said.left(100)
	dirty = f1 != f0 or m.undo.size() != u0 or opened or not errs.is_empty() or not alive or kids_changed(kids0)
	if bad != "":
		problems[key] = bad
		print("PROBLEM %-60s %s" % [key, bad])
	# the next frame after the command must also be quiet (a deferred call / the UI refresh it queued)
	m._refresh()
	await process_frame
	if not lg.errs.is_empty() and not problems.has(key):
		problems[key] = "ENGINE ERROR on the next refresh: %s" % str(lg.errs[0]).left(150)
		print("PROBLEM %-60s %s" % [key, problems[key]])


func _init() -> void:
	OS.add_logger(lg)
	root.disable_3d = true   # the checks are of the app's logic and UI: drawing the 3D view every frame only costs time
	await fresh()
	var skip: Dictionary = (load("res://tests/undo_audit_test.gd") as GDScript).get_script_constant_map()["SKIP"]
	var cmds: Array = m._commands()
	var only := ""
	var only_state := ""
	var from_n := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5)
		if a.begins_with("fresh="):
			FRESH_EVERY = int(a.substr(6))
		if a.begins_with("from="):
			from_n = int(a.substr(5))
		if a.begins_with("state="):
			only_state = a.substr(6)
	var t0 := Time.get_ticks_msec()
	# each hostile state alone must build without an engine error (a start that errors is a finding too)
	for kind in STATES:
		if only_state != "" and kind != only_state:
			continue
		lg.errs.clear()
		await start(kind)
		await process_frame
		ok(lg.errs.is_empty(), "state %-9s builds and renders quietly %s" % [kind, "" if lg.errs.is_empty() else str(lg.errs[0]).left(160)])
	var run_n := 0
	for kind in STATES:
		if only_state != "" and kind != only_state:
			continue
		for c in cmds:
			if from_n > 0 and cmds.find(c) < from_n:
				continue
			if (only != "" and c["id"] != only) or skip.has(c["id"]) or SKIP2.has(c["id"]):
				continue
			if kind == STATES[0]:
				run_n += 1
			await trial(c, kind)
		print("     state %s done at %.0f s" % [kind, (Time.get_ticks_msec() - t0) / 1000.0])
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("     %d commands in the registry, %d skipped (undo_audit's table), %d run x %d states = %d cells in %.0f s" % [cmds.size(), skip.size(), run_n, STATES.size(), cells, secs])
	for k in problems:
		print("     PROBLEM %s: %s" % [k, problems[k]])
	ok(problems.is_empty(), "every command x state cell is gentle: no engine error, the app answers, a refusal names a next step (%d problems in %d cells)" % [problems.size(), cells])
	ok(secs < 540.0, "under 10 minutes wall (%.0f s)" % secs)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(NAN_FILE))
	OS.remove_logger(lg)
	print("GENTLE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	cleanup()
	root.remove_child(m)
	m.free()
	await process_frame
	quit(fails)
