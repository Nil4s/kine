## godot --path . -s tests/fixall_test.gd     (FIX ALL: scripts/main.gd _fix_all; needs a window, pinned 1280x720)
## Bars, written before measuring. On scenes/axe_strike_pose.json: a COPY is loaded (user://), the shipped file is never written.
## Every click is a real mouse press at the control's centre (root.push_input), every key a real key press.
##  (a) the "Fix all (N)" button is shown in the CHECK list (visible in the tree), N = the number of Fix buttons under it
##  (b) ONE click on it: the findings go down by >= 50 % of the start, OR to the count that one-by-one clicking of the Fix
##      buttons reaches (both measured on fresh copies; both numbers are printed)
##  (c) ONE Ctrl+Z restores the original cards exactly (JSON of the cards equal), and the run added exactly one undo step
##  (d) no frame gap > 250 ms while the run is going (measured across process frames, from the click to the run's end)
##  (e) the shipped scene file's bytes are the same after the test
##  (f) the longest single fix in that run takes <= 40 % of the old code's (OLD_WORST_MS: tools/fixspeed_dump.gd on the old code)
##  (g) the cards after Fix all are the old code's, byte for byte (tests/data/fixall_axe_old.var, saved from the old code)
## Expected on the old code: (a) and (b) FAIL (there is no button to click), (c) FAILs with them.
extends SceneTree

var fails := 0
var m: Node
const SRC := "res://scenes/axe_strike_pose.json"
const COPY := "user://fixall_axe_copy.json"
const GAP_MS := 250
## the old code's longest single Fix (ms) in one Fix all on this clip: tools/fixspeed_dump.gd on the code before the speed-up
## (10-25: fix 4 HEAD QUIET 10.1 s alone; the run's worst 11363 ms)
const OLD_WORST_MS := 11363
const OLD_CARDS := "res://tests/data/fixall_axe_old.var"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the Fix buttons under the CHECK list (fix_N, as main names them; not Fix all, not the layer buttons)
func fix_buttons() -> Array:
	var out := []
	for c in m.ui_find_list.get_children():
		if c is Button and String(c.name).begins_with("fix_") and String(c.name) != "fix_all":
			out.append(c)
	return out


func fix_all_button() -> Button:
	return m.ui_find_list.find_child("fix_all", true, false) as Button


func fresh() -> void:
	DirAccess.copy_absolute(ProjectSettings.globalize_path(SRC), ProjectSettings.globalize_path(COPY))
	m._load_scene(COPY)
	m._rebuild_cards()
	m._check()
	await idle(3)


## a real click: the press and the release at the control's centre; no waiting in between (the caller measures)
func push_click(c: Control) -> void:
	var sc: Node = c.get_parent()
	while sc != null and not (sc is ScrollContainer):
		sc = sc.get_parent()
	if sc != null and not (sc as Control).get_global_rect().encloses(c.get_global_rect()):
		(sc as ScrollContainer).ensure_control_visible(c)
	await idle(2)
	var p := c.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame


func key(k: Key, ctrl: bool) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = ctrl
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(3)


## one-by-one: a person clicks the Fix buttons top to bottom, once each (a refused one is not clicked again)
func one_by_one() -> Dictionary:
	await fresh()
	var start: int = m.findings.size()
	var clicks := 0
	var refused := {}
	var t0 := Time.get_ticks_msec()
	while clicks < 60:
		var pick: Button = null
		for b in fix_buttons():
			if not refused.has(int(String(b.name).trim_prefix("fix_"))):
				pick = b
				break
		if pick == null:
			break
		var k := int(String(pick.name).trim_prefix("fix_"))
		var before := JSON.stringify(m.S.cards)
		await push_click(pick)
		var guard := 0
		while m._fixing and guard < 3000:
			await process_frame
			guard += 1
		clicks += 1
		if JSON.stringify(m.S.cards) == before:
			refused[k] = true
	return {"start": start, "end": m.findings.size(), "clicks": clicks, "ms": Time.get_ticks_msec() - t0,
		"fix_left": fix_buttons().size()}


func _init() -> void:
	root.size = Vector2i(1280, 720)
	var m0: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m0)
	m = m0
	await idle(5)
	var shipped0 := FileAccess.get_file_as_string(SRC)

	# (a) and (b) with the one click
	await fresh()
	var start: int = m.findings.size()
	var n_fix := fix_buttons().size()
	var fa := fix_all_button()
	var shown := fa != null and fa.is_visible_in_tree()
	print("     axe_strike_pose: %d findings (%d must fix), %d with a Fix button; Fix all button: %s" % [
		start, m.findings.filter(func(x): return x["sev"] == "FAIL").size(), n_fix, fa.text if fa != null else "none"])
	ok(shown and fa.text == "Fix all (%d)" % n_fix, "(a) the Fix all button is shown in the CHECK list with its count (%d)" % n_fix)

	var cards0 := JSON.stringify(m.S.cards)
	var undo0: int = m.undo.size()
	var t0 := Time.get_ticks_msec()
	var last := Time.get_ticks_msec()
	var gap := 0
	var frames := 0
	if shown:
		await push_click(fa)   # the click starts the run (its press and release are the only input)
		while bool(m.get("_fixall_on")) or frames < 2:
			await process_frame
			frames += 1
			var now := Time.get_ticks_msec()
			gap = maxi(gap, now - last)
			last = now
	await idle(3)
	var end: int = m.findings.size()
	var run: Dictionary = m.get("_fixall_last") if m.get("_fixall_last") != null else {}
	var ms := Time.get_ticks_msec() - t0
	print("     Fix all: %d findings -> %d in %.1f s (%d fixes tried, %d kept, longest single fix %d ms, longest frame gap %d ms)" % [
		start, end, ms / 1000.0, int(run.get("tried", -1)), int(run.get("kept", -1)), int(run.get("worst_ms", -1)), gap])
	for s in run.get("refused", []):
		print("     skipped (made it worse): %s" % s)
	for s in run.get("not_reached", []):
		print("     not reached: %s" % s)
	for s in run.get("no_fix", []):
		print("     no automatic fix: %s" % s)

	# one-by-one on a fresh copy: the same count is what a person reaches by clicking
	var obo: Dictionary = await one_by_one()
	print("     one-by-one: %d findings -> %d after %d clicks (%.1f s, %d Fix buttons left)" % [obo["start"], obo["end"], obo["clicks"],
		obo["ms"] / 1000.0, obo["fix_left"]])

	var half: bool = end <= int(floor(start * 0.5))
	var same: bool = end <= int(obo["end"])
	var worst_ms: int = int(run.get("worst_ms", 1 << 30))
	ok(worst_ms <= 0.4 * OLD_WORST_MS, "(f) the longest single fix %d ms <= 40%% of the old %d ms (limit %d ms)" % [worst_ms, OLD_WORST_MS, int(0.4 * OLD_WORST_MS)])
	ok(shown and (half or same) and end < start, "(b) one click: %d -> %d findings (>= 50%% down: %s; reaches the one-by-one count %d: %s)" % [
		start, end, half, int(obo["end"]), same])

	# (c) one undo step, Ctrl+Z restores the cards exactly
	await fresh()
	fa = fix_all_button()
	cards0 = JSON.stringify(m.S.cards)
	undo0 = m.undo.size()
	var c_ok := false
	var steps_ok := false
	var same_old := false
	if fa != null and fa.is_visible_in_tree():
		await push_click(fa)
		while bool(m.get("_fixall_on")):
			await process_frame
		await idle(3)
		steps_ok = m.undo.size() == undo0 + 1 and JSON.stringify(m.S.cards) != cards0
		if OS.get_environment("FIXALL_WRITE_REF") == "1":   # run with the OLD Fixer (the pre-speed rulebook / fixer) to re-make the reference
			var fw := FileAccess.open(OLD_CARDS, FileAccess.WRITE)
			fw.store_string(var_to_str(m.S.cards))
			fw.close()
		same_old = var_to_str(m.S.cards) == FileAccess.get_file_as_string(OLD_CARDS)
		ok(same_old, "(g) the cards after Fix all equal the old code's (tests/data/fixall_axe_old.var, %d bytes)" % FileAccess.get_file_as_string(OLD_CARDS).length())
		await key(KEY_Z, true)
		c_ok = JSON.stringify(m.S.cards) == cards0
	ok(c_ok and steps_ok, "(c) the run added one undo step (%s) and one Ctrl+Z restores the original cards exactly (%s)" % [steps_ok, c_ok])

	# (d) the frame gap during a run, measured again on its own copy (the click's own frames included)
	await fresh()
	fa = fix_all_button()
	gap = 0
	if fa != null and fa.is_visible_in_tree():
		last = Time.get_ticks_msec()
		await push_click(fa)
		frames = 0
		while bool(m.get("_fixall_on")) or frames < 2:
			await process_frame
			frames += 1
			var now2 := Time.get_ticks_msec()
			gap = maxi(gap, now2 - last)
			last = now2
	ok(fa != null and gap <= GAP_MS, "(d) no frame gap over %d ms while Fix all runs (longest %d ms)" % [GAP_MS, gap])

	# (h) the sliced run leaves the same scene as the blocking call (same cards and findings, byte for byte)
	var blocking := {}
	var sliced := {}
	for mode in [true, false]:
		m.fixall_sync = mode
		await fresh()
		fa = fix_all_button()
		if fa != null and fa.is_visible_in_tree():
			await push_click(fa)
			while bool(m.get("_fixall_on")):
				await process_frame
		await idle(3)
		var out := var_to_str(m.S.cards) + var_to_str(m.findings)
		if mode:
			blocking["out"] = out
		else:
			sliced["out"] = out
	m.fixall_sync = false
	ok(blocking.has("out") and sliced.has("out") and blocking["out"] == sliced["out"],
		"(h) the sliced Fix all leaves the same cards and findings as the blocking call (%d bytes)" % blocking.get("out", "").length())

	# (e) the shipped file untouched
	ok(FileAccess.get_file_as_string(SRC) == shipped0, "(e) the shipped scene file is unchanged")

	if FileAccess.file_exists(COPY):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(COPY))
	print("fixall_test: %d fail(s)" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
