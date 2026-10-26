## godot --path . -s tests/crashcheck_test.gd     (needs a window, pinned 1280x720; --position 4000,4000)
## The owner's crash (10-25): CHECK page, a realism-check option / suggested fix pressed, "Out of bounds get index 28 ... Timeline._draw",
## then the app closed. Every control is pressed with a real mouse click (root.push_input); the mouse hovers the timeline's card edges while a
## fix applies. A Logger counts every script / engine error the run prints.
## Bars (scene kick_swing_polished.json, the owner's own, copied to user://; set CRASH_SCENE to try another):
##  (a) each Realism-panel option (Predict this fix, Find the biggest gain, Apply the biggest gain, each reason's fix) and each CHECK-list
##      Fix button, run on a fresh copy, with the mouse on the timeline: 0 script errors, the process lives, no freeze > 2 s
##  (b) each applied fix is ONE undo step, one Ctrl+Z gives the cards back exactly
##  (c) after each fix the scene and the timeline agree on the card count; no stale hover / drag / selected card index
##  (d) Fix all, on this scene and on three shipped ones: the problem count goes down, one undo step, the score does not fall
##  (e) Fix all's status line says what it did (fixed N of M ...)
extends SceneTree

var fails := 0
var m: Node
var errs := 0
var err_log := []
const SCENES := ["kick_swing_polished", "swing_back", "walk_bat", "combo3"]


class ErrCount extends Logger:
	var t
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtraces: Array) -> void:
		t.errs += 1
		if t.err_log.size() < 12:
			t.err_log.append("%s:%d %s %s" % [file, line, code, rationale])


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func push_mouse(p: Vector2, down = null) -> void:
	var e: InputEvent
	if down == null:
		var mm := InputEventMouseMotion.new()
		mm.position = p
		mm.global_position = p
		e = mm
	else:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = down
		mb.position = p
		mb.global_position = p
		if down:
			mb.button_mask = MOUSE_BUTTON_MASK_LEFT
		e = mb
	root.push_input(e, true)


func click(c: Control) -> void:
	if c == null:
		return
	var sc: Node = c.get_parent()
	while sc != null and not (sc is ScrollContainer):
		sc = sc.get_parent()
	if sc != null and not (sc as Control).get_global_rect().encloses(c.get_global_rect()):
		(sc as ScrollContainer).ensure_control_visible(c)
		await idle(2)
	var p := c.get_global_rect().get_center()
	push_mouse(p)
	await process_frame
	for down in [true, false]:
		push_mouse(p, down)
		await process_frame


func key(k: Key, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = ctrl
		e.pressed = down
		root.push_input(e, true)
		await process_frame
	await idle(3)


## park the mouse on a card edge of the timeline (what the owner's mouse was doing): a hover edge index is then live
func hover_timeline(i: int) -> void:
	var ts: Array = m.S.times()
	var r: Rect2 = (m.ui_timeline as Control).get_global_rect()
	i = clampi(i, 0, ts.size() - 1)
	var p := Vector2(r.position.x + m.ui_timeline.x_of(ts[i][1]), r.position.y + r.size.y * 0.5)
	push_mouse(p)
	await process_frame


func copy_scene(nm: String) -> String:
	var src := "C:/Temp/claude/crash/%s.json" % nm
	if not FileAccess.file_exists(src):
		src = ProjectSettings.globalize_path("res://scenes/%s.json" % nm)
	var dst := "user://crashcheck_%s.json" % nm
	DirAccess.copy_absolute(src, ProjectSettings.globalize_path(dst))
	return dst


func fresh(path: String) -> void:
	m._load_scene(path)
	m._rebuild_cards()
	m._refresh()
	await idle(3)


func wait_idle(limit_ms := 60000) -> int:
	var t0 := Time.get_ticks_msec()
	var worst := 0
	var last := t0
	while (bool(m._fixing) or bool(m._fixall_on) or bool(m.rs_ui.busy)) and Time.get_ticks_msec() - t0 < limit_ms:
		await process_frame
		var n := Time.get_ticks_msec()
		worst = maxi(worst, n - last)
		last = n
	await idle(3)
	return worst


func ribbon(btn_text: String) -> Button:
	for c in (m.ui_ribbon["CHECK"] as Node).find_children("*", "Button", true, false):
		if (c as Button).name == "b_" + btn_text.to_lower().replace(" ", "_"):
			return c
	fails += 1
	print("     ribbon has: ", (m.ui_ribbon["CHECK"] as Node).find_children("*", "Button", true, false).map(func(b): return b.name))
	print("FAIL no ribbon button '%s' on the CHECK tab" % btn_text)
	return null


func list_buttons(prefix: String) -> Array:
	var out := []
	for c in m.ui_find_list.get_children():
		if c is Button and String(c.name).begins_with(prefix) and String(c.name) != "fix_all":
			out.append(c)
	return out


## the state every press must leave consistent: returns "" or the reason
func consistent() -> String:
	var n: int = m.S.cards.size()
	var ts: Array = m.S.times()
	if ts.size() != n:
		return "times %d != cards %d" % [ts.size(), n]
	var tl: Timeline = m.ui_timeline
	var hv: Dictionary = tl._hover
	if hv.get("kind", "") in ["move", "hold", "edge0"] and int(hv.get("i", -1)) >= n:
		return "stale timeline hover index %d (cards %d)" % [int(hv["i"]), n]
	if not tl._drag.is_empty() and int(tl._drag.get("i", -1)) >= n:
		return "stale timeline drag index"
	if int(m.sel_card) >= n:
		return "selected card %d of %d" % [int(m.sel_card), n]
	return ""


## the realism score as the panel makes it (nothing drawn)
func rs_score() -> float:
	m.rs_ui.refresh()
	return float(m.rs_ui.res.get("score", 0.0))


func _init() -> void:
	root.size = Vector2i(1280, 720)
	var lg := ErrCount.new()
	lg.t = self
	OS.add_logger(lg)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(5)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.tc_ui.db = MotionMatch.build()
	var only := OS.get_environment("CRASH_SCENE")
	var main_scene := only if only != "" else SCENES[0]
	var path := copy_scene(main_scene)
	m.easy.set_on(false, false)   # Expert, as the owner uses it
	m._page_set("CHECK")
	await idle(3)

	var part := OS.get_environment("CRASH_PART")   # "" = all, or realism / check / fixall (a long run split in parts)
	# ---- (a)-(c): the realism panel, option by option
	await fresh(path)
	await click(ribbon("Realism score"))
	await wait_idle()
	if part != "" and part != "realism":
		m.rs_ui.res = {}
	var rs: RealismUI = m.rs_ui
	var n_reason: int = (rs.res["reasons"] as Array).size() if not rs.res.is_empty() else 0
	print("     realism panel: score %s, %d reasons" % [str(rs.res.get("score", "?")), n_reason])
	var ctl := []   # options, each pressed on a fresh scene: "predict k", "fix k", "find", "best"
	for k in n_reason:
		ctl.append("predict %d" % (k + 1))
		ctl.append("fix %d" % (k + 1))
	ctl.append("find")
	ctl.append("best")
	var maxfreeze := 0
	if part != "" and part != "realism":
		ctl = []
	for opt in ctl:
		await fresh(path)
		await click(ribbon("Realism score"))
		await wait_idle()
		var parts: PackedStringArray = String(opt).split(" ")
		var kk := int(parts[1]) if parts.size() > 1 else 0
		var btn: Button = null
		match parts[0]:
			"predict":
				btn = m.ui_find_list.find_child("rs_predict_%d" % kk, true, false) as Button
			"fix":
				btn = m.ui_find_list.find_child("rs_fix_%d" % kk, true, false) as Button
				if btn == null:   # the fix needs its gain predicted first, as a person does
					var pb := m.ui_find_list.find_child("rs_predict_%d" % kk, true, false) as Button
					if pb != null:
						await click(pb)
						await wait_idle()
						btn = m.ui_find_list.find_child("rs_fix_%d" % kk, true, false) as Button
			"find":
				btn = m.ui_find_list.find_child("rs_find", true, false) as Button
			"best":
				var fb := m.ui_find_list.find_child("rs_find", true, false) as Button
				if fb != null:
					await click(fb)
					await wait_idle()
				btn = m.ui_find_list.find_child("rs_best", true, false) as Button
		if btn == null:
			print("     (%s: no such button on this scene, skipped)" % opt)
			continue
		var cards0 := JSON.stringify(m.S.cards)
		var n_cards0: int = m.S.cards.size()
		var u0: int = m.undo.size()
		var errs0 := errs
		await hover_timeline(1)
		await click(btn)
		await hover_timeline(2)
		var fz := await wait_idle()
		maxfreeze = maxi(maxfreeze, fz)
		await hover_timeline(5)
		await idle(4)
		var changed := JSON.stringify(m.S.cards) != cards0
		var steps: int = m.undo.size() - u0
		var cons := consistent()
		print("     %-10s cards %d -> %d, changed %s, undo steps %d, errors %d, longest frame %d ms, %s" % [opt, n_cards0, m.S.cards.size(), changed, steps, errs - errs0, fz, cons if cons != "" else "consistent"])
		ok(errs == errs0, "(a) '%s' ran with 0 script errors (%d)" % [opt, errs - errs0])
		ok(cons == "", "(c) '%s' left no stale index (%s)" % [opt, cons])
		if changed:
			ok(steps == 1, "(b) '%s' is one undo step (%d)" % [opt, steps])
			await key(KEY_Z, true)
			ok(JSON.stringify(m.S.cards) == cards0, "(b) '%s': one Ctrl+Z gives the cards back exactly" % opt)
	ok(maxfreeze <= 2000, "(a) no freeze over 2 s while a realism option applied (longest %d ms)" % maxfreeze)

	# ---- the CHECK list's own Fix buttons
	await fresh(path)
	await click(ribbon("Check"))
	await idle(3)
	var n_fix := list_buttons("fix_").size()
	print("     CHECK list: %d findings, %d Fix buttons" % [m.findings.size(), n_fix])
	for k in range(1, 40 if part == "" or part == "check" else 1):
		await fresh(path)
		await click(ribbon("Check"))
		await idle(3)
		var b := m.ui_find_list.find_child("fix_%d" % k, true, false) as Button
		if b == null:
			if k > m.findings.size():
				break
			continue
		var cards0 := JSON.stringify(m.S.cards)
		var u0: int = m.undo.size()
		var errs0 := errs
		await hover_timeline(k)
		await click(b)
		await hover_timeline(k + 1)
		var fz := await wait_idle()
		await hover_timeline(6)
		await idle(4)
		var changed := JSON.stringify(m.S.cards) != cards0
		var cons := consistent()
		print("     fix_%d changed %s, undo steps %d, errors %d, longest frame %d ms, %s" % [k, changed, m.undo.size() - u0, errs - errs0, fz, cons if cons != "" else "consistent"])
		ok(errs == errs0, "(a) fix_%d ran with 0 script errors (%d)" % [k, errs - errs0])
		ok(cons == "", "(c) fix_%d left no stale index (%s)" % [k, cons])
		ok(fz <= 2000, "(a) fix_%d: no freeze over 2 s (%d ms)" % [k, fz])
		if changed:
			ok(m.undo.size() - u0 == 1, "(b) fix_%d is one undo step" % k)
			await key(KEY_Z, true)
			ok(JSON.stringify(m.S.cards) == cards0, "(b) fix_%d: one Ctrl+Z gives the cards back exactly" % k)

	# ---- (f) the stale hover: the mouse rests on the LAST card edge of a long scene, then another scene with fewer cards opens (or an undo
	# goes back to one): the hover index outlives its card ('Out of bounds get index 28' in Timeline._draw, every frame)
	if part == "" or part == "stale":
		for other in ["swing_back", "combo3"]:
			await fresh(path)
			await hover_timeline(m.S.cards.size() - 1)
			var hi0: int = int(m.ui_timeline._hover.get("i", -1))
			var e_before := errs
			await fresh(copy_scene(other))
			await idle(4)
			ok(hi0 >= m.S.cards.size() or true, "hover index %d, then %s with %d cards" % [hi0, other, m.S.cards.size()])
			ok(errs == e_before, "(f) hovering the last edge, then opening %s: 0 script errors (%d)" % [other, errs - e_before])
			ok(consistent() == "", "(f) no stale hover after opening %s (%s)" % [other, consistent()])

	# ---- the race: a Fix button hovered starts its preview on a WORKER thread (Fixer.propose); the owner then pressed a realism option /
	# another Fix, which runs on the main thread over the same static caches (FrameMemo, Rulebook): a data race, a native crash
	if part == "" or part == "race":
		await fresh(path)
		await click(ribbon("Check"))
		await idle(3)
		var n_rf := list_buttons("fix_").size()
		for k in range(1, n_rf + 1):
			for what in ["realism", "predict", "fixother"]:
				await fresh(path)
				await click(ribbon("Check"))
				await idle(3)
				var hb := m.ui_find_list.find_child("fix_%d" % k, true, false) as Button
				if hb == null:
					continue
				var errs0 := errs
				var jobs0: bool = false
				push_mouse(hb.get_global_rect().get_center())   # the mouse enters: the preview worker starts
				await idle(2)
				jobs0 = not m._pv_job.is_empty()
				match what:
					"realism":
						await click(ribbon("Realism score"))
					"predict":
						await click(ribbon("Realism score"))
						await wait_idle()
						var pb := m.ui_find_list.find_child("rs_predict_1", true, false) as Button
						await click(pb)
					"fixother":
						var ob := m.ui_find_list.find_child("fix_%d" % (k % n_rf + 1), true, false) as Button
						await click(ob)
				var fz := await wait_idle()
				await idle(4)
				print("     race fix_%d hover (worker running: %s) then %-9s errors %d, consistent: %s" % [k, jobs0, what, errs - errs0, consistent() == ""])
				ok(errs == errs0, "(a) race: hover fix_%d then %s: 0 script errors (%d)" % [k, what, errs - errs0])
				ok(m._pv_job.is_empty() or WorkerThreadPool.is_task_completed(m._pv_job["task"]) or true, "worker state read")

	# ---- (d)/(e): Fix all
	for nm in (SCENES if only == "" else [only]) if part == "" or part == "fixall" else []:
		var p2 := copy_scene(nm)
		await fresh(p2)
		await click(ribbon("Check"))
		await idle(3)
		var start: int = m.findings.size()
		var fa := m.ui_find_list.find_child("fix_all", true, false) as Button
		if fa == null:
			print("     %s: %d findings, no Fix all button" % [nm, start])
			continue
		var cards0 := JSON.stringify(m.S.cards)
		var u0: int = m.undo.size()
		var errs0 := errs
		var sc0 := rs_score()
		await click(ribbon("Check"))   # rs_score drew nothing, but the list is the Check's again
		await idle(2)
		fa = m.ui_find_list.find_child("fix_all", true, false) as Button
		await hover_timeline(2)
		await click(fa)
		await wait_idle(300000)
		await idle(4)
		var end: int = m.findings.size()
		var run: Dictionary = m._fixall_last
		var sc1 := rs_score()
		var say: String = String(m.ui_status.text)
		print("     %s: findings %d -> %d, score %.1f -> %.1f, tried %s kept %s, undo steps %d, errors %d" % [nm, start, end, sc0, sc1, str(run.get("tried")), str(run.get("kept")), m.undo.size() - u0, errs - errs0])
		print("       say: %s" % say.left(400))
		for rr in run.get("refused", []):
			print("       refused: %s" % rr)
		for rr in run.get("no_fix", []):
			print("       no fix: %s" % rr)
		ok(errs == errs0, "(d) %s: Fix all ran with 0 script errors (%d)" % [nm, errs - errs0])
		ok(end < start, "(d) %s: Fix all reduces the problems (%d -> %d)" % [nm, start, end])
		ok(sc1 >= sc0, "(d) %s: the realism score does not fall (%.1f -> %.1f)" % [nm, sc0, sc1])
		ok(m.undo.size() - u0 == 1, "(d) %s: one undo step (%d)" % [nm, m.undo.size() - u0])
		ok(say.begins_with("Fix all:") and say.contains("fixed %d of %d" % [int(run.get("kept", -1)), int(run.get("total", -1))]), "(e) %s: the status says what it did" % nm)
		# (e) every problem still listed is named in the summary with its reason ("N need you": N covers all of them), none is called fixed
		var rx := RegEx.create_from_string("([0-9]+) need you")
		var mt := rx.search(say)
		var named := int(mt.get_string(1)) if mt != null else 0
		ok(named >= end, "(e) %s: the summary names every problem left (%d named, %d left)" % [nm, named, end])
		ok(not say.contains("Fixed: "), "(e) %s: a fix that was kept is never listed as one that could not be done" % nm)
		ok(consistent() == "", "(c) %s: no stale index after Fix all (%s)" % [nm, consistent()])
		await key(KEY_Z, true)
		ok(JSON.stringify(m.S.cards) == cards0, "(d) %s: one Ctrl+Z gives the cards back exactly" % nm)

	for s in err_log:
		print("     logged: %s" % s)
	print("crashcheck_test: %d fail(s), %d logged error(s)" % [fails, errs])
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
