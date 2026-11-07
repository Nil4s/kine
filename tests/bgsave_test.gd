## godot --path . -s tests/bgsave_test.gd     (LANE L124, ROADMAP_400 P15 Large-file safety: saves in the background)
## BEFORE THIS LANE: _save_scene_now built the dict, JSON.stringify-ed it and wrote it on the main thread (_write), so a big
## scene froze the UI for the whole write. THE FEATURE (scripts/bg_save.gd, BgSave): the dict is snapshotted on the main
## thread (duplicate(true)), serialised + written to <file>.tmp on a WorkerThreadPool task, then renamed over the target;
## a chip says saving / saved / error; a save while one runs is queued per path (latest wins), never two writers;
## quitting calls wait_all(); a write error leaves the old file untouched and says so. Scenes under BgSave.threshold bytes
## (estimated) keep the old synchronous write, so every other suite sees the file at once as before.
## FIXTURE: a scene of >= 2000 frames (cards repeated from combo3) plus 40 props; its file size is printed.
## BARS (written before the code; never moved after a run):
##  1 fixture: S.length()*fps >= 2000 frames and the saved file is > 300 KB.
##  2 LONGEST MAIN-THREAD FRAME during a real m._save_scene_now of that scene (the call itself, then every frame until
##    the chip says saved) < 50 ms. The old path (_scene_dict + _write on the main thread, same scene) is measured and
##    printed for comparison; it must be reported, and the new one must be shorter than the old one.
##  3 the file the background writer made is byte-identical to a synchronous JSON.stringify(d, " ") write of the same dict.
##  4 edits made while the write runs (the dict and the live scene both mutated right after request()) do NOT reach the file.
##  5 a forced write failure (injected, half the bytes already in the temp file) leaves the previous file byte-identical,
##    leaves no .tmp, the result is not ok, the chip shows the error; and a REAL failure (parent of the target is a file)
##    reports an error too.
##  6 three quick saves of the same path (states 1, 2, 3): the final file == state 3; never more than ONE writer at a time
##    (max_active == 1); at most 2 writes happened (the first and the latest).
##  7 wait_all() (what quitting calls) returns with nothing busy and the file complete.
##  8 PLANTED fake fails: (a) the leak detector flags a file that does contain the post-request edit; (b) the byte-equality
##    check rejects a one-byte-different text; (c) a bar of 0.001 ms on the real longest frame fails.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func rd(p: String) -> String:
	return FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else "<missing>"


func wr(p: String, s: String) -> void:
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(s)
	f.close()


func wait_idle(bg: Node, frames_out: Array) -> void:
	var t := Time.get_ticks_usec()
	var n := 0
	while (bg.busy() or n < 4) and n < 4000:
		await process_frame
		var t2 := Time.get_ticks_usec()
		frames_out.append((t2 - t) / 1000.0)
		t = t2
		n += 1


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	var S: Scene = m.S
	var base: Array = S.cards.duplicate(true)
	var k := 0
	while S.length() * S.fps < 2000.0 and k < 400:
		S.cards.append((base[k % base.size()] as Dictionary).duplicate(true))
		k += 1
	S.props = []
	for i in 40:
		S.props.append(Props.make("box", Props.xf_at(Vector3(i * 0.3, 0, 5.0 + (i % 5)), i * 7.0)))
	m._rebuild_cards()
	m._refresh()
	await idle(4)
	var frames := int(S.length() * S.fps)
	print("fixture: %d cards, %d frames at %d fps, %d props" % [S.cards.size(), frames, int(S.fps), S.props.size()])
	var bg: Node = m.bgs()
	var dir := ProjectSettings.globalize_path(UserPaths.w("res://scenes"))
	DirAccess.make_dir_recursive_absolute(dir)

	# idle noise floor (what a frame costs with nothing saving)
	var floor_ms := []
	for i in 20:
		var t := Time.get_ticks_usec()
		await process_frame
		floor_ms.append((Time.get_ticks_usec() - t) / 1000.0)
	var noise := 0.0
	for x in floor_ms:
		noise = maxf(noise, x)
	print("idle longest frame: %.1f ms (the noise floor of this machine under load)" % noise)

	# ---- 2 OLD path, same scene: dict + stringify + write on the main thread (first call warms bad_frames; second is the number)
	var old_ms := 0.0
	for rep in 2:
		var t0 := Time.get_ticks_usec()
		var d_old: Dictionary = m._scene_dict()
		m._write("res://scenes/zz_bgsave_old.json", d_old)
		old_ms = (Time.get_ticks_usec() - t0) / 1000.0
		await idle(2)
	var size_old := FileAccess.get_file_as_bytes(dir + "/zz_bgsave_old.json").size()
	print("OLD path longest frame (_scene_dict + _write, warm): %.1f ms; file %d KB" % [old_ms, size_old / 1024])
	ok(frames >= 2000 and size_old > 300 * 1024, "1 fixture: %d frames, file %d KB (> 300 KB)" % [frames, size_old / 1024])

	# ---- 2 NEW path through the real app function
	var pre := []
	for i in 10:
		var tp := Time.get_ticks_usec()
		await process_frame
		pre.append((Time.get_ticks_usec() - tp) / 1000.0)
	print("idle frame right before the save: max %.1f ms, min %.1f ms (load shows here)" % [pre.max(), pre.min()])
	var gaps := []
	var t1 := Time.get_ticks_usec()
	m._save_scene_now("zz_bgsave_new")
	var call_ms := (Time.get_ticks_usec() - t1) / 1000.0
	print("save stages (cumulative ms): ", m.save_prof)
	var saw_saving: bool = String(bg.chip_text()).findn("saving") >= 0
	await wait_idle(bg, gaps)
	var longest := call_ms
	var gmax := 0.0
	for g in gaps:
		gmax = maxf(gmax, g)
	longest = maxf(longest, gmax)
	print("NEW path: call %.1f ms, longest following frame %.1f ms, longest overall %.1f ms (old %.1f ms)" % [call_ms, gmax, longest, old_ms])
	ok(longest < 50.0, "2 longest main-thread frame during the save %.1f ms < 50 ms" % longest)
	ok(longest < old_ms, "2 and shorter than the old path (%.1f < %.1f ms)" % [longest, old_ms])
	ok(saw_saving, "2 the chip said 'saving' right after the call")
	ok(String(bg.chip_text()).findn("saved") >= 0, "2 the chip says saved at the end (got '%s')" % bg.chip_text())
	var newtxt := rd(dir + "/zz_bgsave_new.json")
	var js = JSON.parse_string(newtxt)
	ok(js is Dictionary and (js as Dictionary).get("cards", []).size() == S.cards.size(), "2 the scene file parses and has all %d cards" % S.cards.size())
	ok(m.scene_path.ends_with("zz_bgsave_new.json"), "2 scene_path points at the new file")

	# ---- 3 byte-identical to the synchronous write of the same dict
	var d: Dictionary = m._scene_dict()
	var want := JSON.stringify(d, " ")
	bg.request(dir + "/zz_bgsave_b3.json", d)
	await wait_idle(bg, [])
	var got := rd(dir + "/zz_bgsave_b3.json")
	ok(got == want and got.length() > 1000, "3 background file == synchronous stringify of the same dict (%d chars)" % got.length())
	m._write("res://scenes/zz_bgsave_b3s.json", d)
	ok(rd(dir + "/zz_bgsave_b3s.json") == got, "3 and == the old _write's file")

	# ---- 4 edits during the write do not leak
	var d4: Dictionary = m._scene_dict()
	var want4 := JSON.stringify(d4, " ")
	bg.request(dir + "/zz_bgsave_b4.json", d4)
	d4["scene"] = "MUTATED_AFTER"
	(d4["cards"] as Array).clear()
	var keep_name := S.name
	S.name = "MUTATED_LIVE"
	S.cards.pop_back()
	await wait_idle(bg, [])
	S.name = keep_name
	var got4 := rd(dir + "/zz_bgsave_b4.json")
	ok(got4 == want4 and not got4.contains("MUTATED"), "4 the file is the state at request time, no edit leaked")
	ok(got4.contains("\"cards\""), "4 and its cards are all still there")

	# ---- 5 forced failure keeps the old file
	var p5 := dir + "/zz_bgsave_b5.json"
	wr(p5, "OLD-CONTENT-THAT-MUST-SURVIVE\n" + "x".repeat(5000))
	var old5 := rd(p5)
	BgSave.inject_fail = true
	bg.request(p5, d)
	await wait_idle(bg, [])
	BgSave.inject_fail = false
	ok(rd(p5) == old5, "5 injected failure: previous file byte-identical (%d chars)" % old5.length())
	ok(not FileAccess.file_exists(p5 + ".tmp"), "5 no .tmp left behind")
	ok(not bg.last_ok and String(bg.last_error) != "", "5 result not ok, error text: '%s'" % bg.last_error)
	ok(String(bg.chip_text()).findn("error") >= 0 or String(bg.chip_text()).findn("not saved") >= 0, "5 the chip shows the error (got '%s')" % bg.chip_text())
	wr(dir + "/zz_bgsave_afile", "i am a file")
	bg.request(dir + "/zz_bgsave_afile/x.json", d)
	await wait_idle(bg, [])
	ok(not bg.last_ok and String(bg.last_error) != "", "5 a REAL failure (parent is a file) reports an error: '%s'" % bg.last_error)
	bg.request(p5, d)
	await wait_idle(bg, [])
	ok(bg.last_ok and rd(p5) == want, "5 the next save after the errors works and replaces the file")

	# ---- 6 three quick saves
	var p6 := dir + "/zz_bgsave_b6.json"
	var ds := []
	for i in 3:
		var di: Dictionary = d.duplicate(true)
		di["scene"] = "state_%d" % (i + 1)
		ds.append(di)
	bg.reset_stats()
	for i in 3:
		bg.request(p6, ds[i])
	await wait_idle(bg, [])
	ok(rd(p6) == JSON.stringify(ds[2], " "), "6 the final file is state 3")
	ok(bg.max_active == 1, "6 never more than one writer (max_active %d)" % bg.max_active)
	ok(bg.writes <= 2 and bg.writes >= 1, "6 at most 2 writes for 3 requests (%d)" % bg.writes)

	# ---- 7 wait_all
	var p7 := dir + "/zz_bgsave_b7.json"
	bg.request(p7, d)
	bg.wait_all()
	ok(not bg.busy() and rd(p7) == want, "7 wait_all returns with nothing busy and the file complete")

	# ---- 8 planted fakes
	var leaky := got4.replace("\"scene\"", "\"scene\": \"MUTATED_AFTER\", \"x\"")
	ok(leaky.contains("MUTATED"), "8a the leak detector flags a file with the edit in it")
	ok(want.substr(0, want.length() - 1) + "X" != want, "8b the byte-equality check rejects a one-byte-different text")
	ok(not (longest < 0.001), "8c a bar of 0.001 ms on the real longest frame (%.1f ms) fails, as it must" % longest)

	for f in ["old", "new", "b3", "b3s", "b4", "b5", "b6", "b7"]:
		DirAccess.remove_absolute(dir + "/zz_bgsave_%s.json" % f)
	DirAccess.remove_absolute(dir + "/zz_bgsave_afile")
	print("RESULT bgsave fails=%d" % fails)
	quit(1 if fails > 0 else 0)
