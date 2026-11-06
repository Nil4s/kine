## godot --path . -s tests/bgthread_test.gd     (window suite: bgthread:w)   L42: THE THROW JUDGE AND THE SIM BAKE OFF THE MAIN THREAD.
## Two merged limits: (#249) ThrowTruth.judge ran on the main thread (~95 ms a 34-frame clip) on every card / partner change, so dragging stuttered;
## (#251) Bake sim ran the cape and soft sims on the main thread (~12 s, the UI blocked) and the scene key was md5-hashed on EVERY read.
## Now: the judge runs on a WorkerThreadPool task behind a debounce (the panel says "checking..." and then the result; a result of an older edit is never
## shown: a generation counter); Bake sim runs on a worker with the progress bar and Cancel of the import panel, writes its files atomically
## (temp file + rename, committed on the main thread only when the bake completed and the scene is still the one it read), and its undo step is
## pushed only on completion; the scene key is memoized per edit generation (SimCacheLive.edited()).
## Bars, written BEFORE the code (this file's first commit has none of it). Each has a PLANTED CONTROL.
##   a FRAME TIME   during a 34-frame judge (8 edits, each watched from the edit until 10 frames after its result landed) and during a bake (cape + soft),
##                  the main thread's frame time is <= 20 ms at p95 (a probe on process_frame, pooled). CONTROL: the same loop with the judge / the
##                  sim run SYNCHRONOUSLY on the main thread trips the bar (p95 > 20 ms).
##   b BIT-EXACT    the panel's result after an edit equals the synchronous ThrowTruth.judge of that scene (var_to_str equal); the background bake's
##                  files equal the synchronous bake's files byte for byte. CONTROL: a result with one number nudged by 0.1 mm is seen as different.
##   c LAST EDIT    five edits in quick succession: the panel never shows the readout of edits 1-4 and ends on edit 5's (equal to the direct judge),
##                  and the judge ran fewer than 5 times (debounced). While it works the panel says "checking...". CONTROL: a stale result injected with
##                  an old generation is dropped (panel unchanged); the same result put straight into the panel IS seen (the detector works).
##   d CANCEL       Cancel mid-bake leaves no file (no .ksim, .tmp or .pending in the folder), no meta and no undo step; an edit mid-bake drops the
##                  result the same way. The completed bake pushes exactly ONE undo step, and not before it completes. CONTROL: the completed bake
##                  does leave its files (the folder listing can see a file).
##   e KEY MEMO     with the cache fresh, 500 state() reads hash the key at most once per edit generation (counted: SimCacheLive.hashes); an edit and an
##                  undo each cost one more; stale / fresh answers are right. The read cost (mean of 2000 frame_at) is <= the old per-read-hash cost
##                  measured in the same run, and <= 0.5 ms. CONTROL: 50 raw key_for calls move the counter by 50 (it can see hashing).
extends SceneTree

var fails := 0
var m: Node
const FPS := 30
const DIR := "user://bgthread_test"
const TMP := "user://bgthread_scene.json"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func control(claim: bool, what: String) -> void:
	print(("ok   control caught: " if not claim else "FAIL control NOT caught: ") + what)
	if claim:
		fails += 1


class Probe:
	var dt: Array = []
	var last := 0
	var on := false

	func tick() -> void:
		var now := Time.get_ticks_usec()
		if on and last > 0:
			dt.append(float(now - last) / 1000.0)
		last = now

	func p95() -> float:
		if dt.is_empty():
			return 0.0
		var s := dt.duplicate()
		s.sort()
		return float(s[mini(int(ceil(0.95 * s.size())) - 1, s.size() - 1)])

	func at_max() -> int:
		var v := 0.0
		var k := 0
		for i in dt.size():
			if float(dt[i]) > v:
				v = float(dt[i])
				k = i
		return k

	func mx() -> float:
		var v := 0.0
		for x in dt:
			v = maxf(v, float(x))
		return v


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func stand() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b


func load_scene(S: Scene) -> void:
	var fa := FileAccess.open(TMP, FileAccess.WRITE)
	fa.store_string(JSON.stringify(S.to_dict(stand(), false)))
	fa.close()
	m._load_scene(TMP)
	m._rebuild_cards()
	m.playing = false
	await idle(2)


func wait_until(f: Callable, ms := 60000) -> bool:
	var end := Time.get_ticks_msec() + ms
	while not f.call() and Time.get_ticks_msec() < end:
		await process_frame
	return f.call()


## the panel's text for a direct (synchronous) result
func shown(r: Dictionary) -> String:
	var P := ThrowPanel.new()
	P.show_result(r)
	return P.readout()


func shot(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	if img.get_width() > 1000:
		img.resize(1000, int(round(1000.0 * img.get_height() / img.get_width())))
	img.save_png("C:/Temp/claude/L42/%s.png" % name)


func tweak(v: float) -> void:
	m._do(func(): ((m.S.cards[0]["pose"]["joints"] as Dictionary)["pelvis"] as Dictionary).set("bend", v))


func files_in(d: String) -> Array:
	var out := []
	var da := DirAccess.open(d)
	if da == null:
		return out
	for f in da.get_files():
		out.append(f)
	return out


func turn_scene() -> Scene:
	var S := Scene.new()
	S.fps = 30
	S.name = "zz_bgthread"
	var rest := {}
	for j in Body.ORDER:
		rest[j] = {"bend": 0.0, "side": 0.0, "twist": 0.0}
	S.add("stand", {"joints": rest.duplicate(true), "offset": [0.0, 0.0, 0.0]})
	(S.cards[-1] as Dictionary)["hold"] = 1.5
	var turned := rest.duplicate(true)
	(turned["pelvis"] as Dictionary)["twist"] = 90.0
	S.add("turn", {"joints": turned, "offset": [0.0, 0.0, 0.0]})
	(S.cards[-1] as Dictionary)["move"] = 0.25
	(S.cards[-1] as Dictionary)["hold"] = 3.0
	return S


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var probe := Probe.new()
	process_frame.connect(probe.tick)

	# ================= THE THROW JUDGE
	var osoto := ThrowFixtures.build("osoto")
	var fh := FileAccess.open(TMP, FileAccess.WRITE)
	fh.store_string(JSON.stringify(osoto.to_dict(stand(), false)))
	fh.close()
	m._load_scene(TMP)
	m._rebuild_cards()
	m.playing = false
	m.throw_on = true
	m._refresh()
	await idle(2)
	ok(await wait_until(func(): return not m._throw_busy()), "0 the first judge lands")
	var P: ThrowPanel = m.throw_panel
	var n_fr: int = (P.res.get("frames", []) as Array).size()
	ok(n_fr >= 30 and n_fr <= 40, "0 the clip is a ~34-frame clip (%d frames)" % n_fr)
	var t0 := Time.get_ticks_usec()
	var d0 := ThrowTruth.judge(m.S, FPS)
	print("     one synchronous judge: %.1f ms" % (float(Time.get_ticks_usec() - t0) / 1000.0))
	ok(var_to_str(P.res) == var_to_str(d0), "b1 the landed result equals the synchronous judge of the same scene, bit for bit")

	# c. five edits in quick succession
	var vals := [3.0, 6.0, 9.0, 12.0, 15.0]
	var direct := []
	for v in vals:   # the direct judge of each intermediate state (on a clone: the app's scene is not touched)
		var sc: Scene = m.S.clone()
		((sc.cards[0]["pose"]["joints"] as Dictionary)["pelvis"] as Dictionary)["bend"] = v
		direct.append(shown(ThrowTruth.judge(sc, FPS)))
	var distinct := true
	for i in 4:
		distinct = distinct and direct[i] != direct[4]
	ok(distinct, "c0 the five edits give five different readouts (the check is not vacuous)")
	var runs0: int = m.throw_judge_runs
	var seen := []
	var saw_checking := false
	for v in vals:
		tweak(v)
		saw_checking = saw_checking or P.readout().contains("checking")
		seen.append(P.readout())
		await process_frame
		seen.append(P.readout())
	var t_end := Time.get_ticks_msec() + 20000
	while m._throw_busy() and Time.get_ticks_msec() < t_end:
		seen.append(P.readout())
		await process_frame
	await idle(3)
	var stale_seen := false
	for s in seen:
		for i in 4:
			stale_seen = stale_seen or String(s) == direct[i]
	ok(saw_checking, "c the panel says 'checking...' right after an edit")
	ok(not stale_seen, "c the panel never showed the readout of edits 1-4 (%d readouts watched)" % seen.size())
	ok(P.readout() == direct[4], "c the panel ends on edit 5's readout: %s" % P.readout())
	ok(m.throw_judge_runs - runs0 < 5, "c the judge ran %d times for 5 quick edits (debounced, < 5)" % (m.throw_judge_runs - runs0))
	ok(var_to_str(P.res) == var_to_str(ThrowTruth.judge(m.S, FPS)), "b2 after the five edits the panel's result equals the synchronous judge, bit for bit")
	# controls: a stale result is dropped; the detector sees one that is not
	var before := P.readout()
	var sc_old: Scene = m.S.clone()
	((sc_old.cards[0]["pose"]["joints"] as Dictionary)["pelvis"] as Dictionary)["bend"] = 3.0
	var stale := ThrowTruth.judge(sc_old, FPS)   # edit 1's numbers (the unedited fixture leans 15 deg: the same as edit 5)
	var landed: bool = m._throw_land(int(m.throw_gen) - 1, stale)
	ok(not landed and P.readout() == before, "c CONTROL-A a stale result injected with an old generation is dropped (the panel is unchanged)")
	P.show_result(stale)
	control(P.readout() == before, "c CONTROL-B a stale result put straight in the panel changes what it shows (the detector can see it)")
	m._throw_key_reset()
	m._refresh()
	await wait_until(func(): return not m._throw_busy())
	ok(P.readout() == before, "c the panel recovers the true result after the injection")
	var nudged: Dictionary = P.res.duplicate(true)
	nudged["frames"][int(nudged["frame"])]["partner"]["out"] = float(nudged["frames"][int(nudged["frame"])]["partner"]["out"]) + 0.0001
	control(var_to_str(nudged) == var_to_str(P.res), "b CONTROL a number nudged by 0.1 mm is a different result")

	# the picture: the panel while the judge works ("checking...") and after
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/L42")
	tweak(20.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var vr := Rect2(Vector2.ZERO, Vector2(root.get_viewport().get_visible_rect().size))
	var pr := P.get_global_rect()
	ok(P.visible and vr.encloses(pr) and pr.size.x >= 500.0 and P.readout().contains("checking"), "p PLACEMENT the throw panel (%s) lies inside the window (%s) and says checking..." % [str(pr), str(vr)])
	shot("throw_checking")
	print("SHOT C:/Temp/claude/L42/throw_checking.png readout: ", P.readout())
	await wait_until(func(): return not m._throw_busy())
	await idle(3)
	await RenderingServer.frame_post_draw
	shot("throw_done")
	print("SHOT C:/Temp/claude/L42/throw_done.png readout: ", P.readout())

	# a. frame time while the judge works: 8 edits, pooled
	probe.dt.clear()
	for i in 8:
		probe.on = true
		tweak(1.0 + float(i) * 2.0)
		await process_frame
		await wait_until(func(): return not m._throw_busy())
		await idle(10)
		probe.on = false
		await process_frame
	var p_async: float = probe.p95()
	print("     judge async: %d frames, p95 %.1f ms, max %.1f ms" % [probe.dt.size(), p_async, probe.mx()])
	ok(p_async <= 20.0, "a the main thread's frame time during a 34-frame judge is %.1f ms at p95 (<= 20)" % p_async)
	probe.dt.clear()
	for i in 8:
		probe.on = true
		ThrowTruth.judge(m.S, FPS)   # the old way: on the main thread
		await idle(4)
		probe.on = false
		await process_frame
	var p_sync: float = probe.p95()
	print("     judge SYNC: %d frames, p95 %.1f ms, max %.1f ms" % [probe.dt.size(), p_sync, probe.mx()])
	control(p_sync <= 20.0, "a CONTROL the same loop with the judge run synchronously has p95 %.1f ms (> 20)" % p_sync)
	m.throw_on = false
	m._refresh()

	# ================= THE BAKE
	m.simc.dir = DIR + "/session"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(m.simc.dir))
	var S := turn_scene()
	await load_scene(S)
	m._do(func(): m.S.cape = Cloth.bake_scene(m.S.clone(), stand()))
	m._do(func(): m.S.soft = {"regions": ["belly"]})
	await idle(2)
	await wait_until(func(): return m.soft_live.ready(), 120000)
	var u0: int = m.undo.size()
	# the synchronous reference
	var rep: Dictionary = m._simc_bake()
	var objs: Array = rep.get("objects", [])
	ok(objs.has("cape") and objs.has("soft:belly"), "0 the synchronous bake cached the cape and the belly (%s)" % str(objs))
	var ref := {}
	for n in objs:
		ref[n] = FileAccess.get_file_as_bytes(m.simc.file_of(n))
	m._undo()
	ok(m.simc.meta.is_empty() and m.undo.size() == u0, "0 undo took the synchronous bake back")
	var left0 := files_in(m.simc.dir)
	ok(left0.is_empty(), "0 the folder is empty before the background bake (%s)" % str(left0))

	# d. cancel
	var u1: int = m.undo.size()
	m._simc_bake_bg()
	ok(m._imp_busy(), "d Bake sim returns at once with the job running in the background")
	await idle(5)
	ok(m.undo.size() == u1 and m.simc.meta.is_empty(), "d no undo step and no cache while the bake runs")
	m._import_cancel()
	ok(await wait_until(func(): return not m._imp_busy()), "d Cancel ends the job")
	await idle(3)
	ok(files_in(m.simc.dir).is_empty() and m.simc.meta.is_empty() and m.undo.size() == u1, "d Cancel left no file (%s), no meta, no undo step" % str(files_in(m.simc.dir)))
	# an edit mid-bake: the result is for a scene that is gone
	m._simc_bake_bg()
	await idle(5)
	tweak(7.0)
	ok(await wait_until(func(): return not m._imp_busy()), "d the bake ends after an edit mid-bake")
	await idle(3)
	var u_edit: int = m.undo.size()
	ok(files_in(m.simc.dir).is_empty() and m.simc.meta.is_empty(), "d an edit mid-bake drops the result: no file, no meta")
	m._undo()
	ok(m.undo.size() == u_edit - 1, "d (the edit itself was its own undo step)")

	# a/b. the completed background bake
	var u2: int = m.undo.size()
	await process_frame   # (the first sample must start at a frame boundary, not include the test's own work above)
	probe.dt.clear()
	probe.on = true
	m._simc_bake_bg()
	var steps_before_done := 0
	var t_bake := Time.get_ticks_msec()
	var shot_done := false
	while m._imp_busy() and Time.get_ticks_msec() < t_bake + 180000:
		await process_frame
		if m._imp_busy():
			steps_before_done = maxi(steps_before_done, m.undo.size() - u2)
			if not shot_done and Time.get_ticks_msec() - t_bake > 120:
				shot_done = true
				probe.on = false
				await RenderingServer.frame_post_draw
				var ip: Control = m._imp_panel
				ok(ip != null and ip.visible and vr.encloses(ip.get_global_rect()) and m._imp_bar.value >= 0.0 and m._imp_cancel_btn != null and m._imp_cancel_btn.visible and not m._imp_cancel_btn.disabled, "p PLACEMENT the bake panel %s is inside the window, bar at %.0f %%, Cancel visible" % [str(ip.get_global_rect()) if ip != null else "-", m._imp_bar.value])
				shot("bake_bar")
				print("SHOT C:/Temp/claude/L42/bake_bar.png progress ", VideoIQ.progress)
				await process_frame
				probe.on = true
	var bake_ms := Time.get_ticks_msec() - t_bake
	ok(shot_done, "p the bake panel was caught on screen while the bake ran")
	await idle(10)
	probe.on = false
	var p_bake: float = probe.p95()
	print("     bake async: %d ms, %d frames, p95 %.1f ms, max %.1f ms at frame %d" % [bake_ms, probe.dt.size(), p_bake, probe.mx(), probe.at_max()])
	ok(steps_before_done == 0, "d no undo step before the bake completed")
	ok(m.undo.size() == u2 + 1, "d the completed bake pushed exactly ONE undo step (%d -> %d)" % [u2, m.undo.size()])
	ok(p_bake <= 20.0 and probe.dt.size() >= 30, "a the main thread's frame time during the bake (%d ms long) is %.1f ms at p95 (<= 20), %d frames watched" % [bake_ms, p_bake, probe.dt.size()])
	var fl := files_in(m.simc.dir)
	var junk := fl.filter(func(f): return not String(f).ends_with(".ksim"))
	ok(fl.size() == 2 and junk.is_empty(), "d the completed bake left its 2 files and no temp / pending file (%s)" % str(fl))
	control(fl.is_empty(), "d CONTROL the folder listing sees the files a completed bake leaves")
	var same := true
	for n in objs:
		same = same and m.simc.state(m.S, n) == "fresh" and FileAccess.get_file_as_bytes(m.simc.file_of(n)) == ref[n]
	ok(same, "b the background bake's files equal the synchronous bake's files, byte for byte (cape %d B, belly %d B)" % [ref["cape"].size(), ref["soft:belly"].size()])
	var wrong: PackedByteArray = (ref["cape"] as PackedByteArray).duplicate()
	wrong[wrong.size() - 1] = (wrong[wrong.size() - 1] + 1) % 256
	control(wrong == ref["cape"], "b CONTROL a file with one byte changed is different")
	# the synchronous way trips the frame bar
	probe.dt.clear()
	for i in 3:
		probe.on = true
		SimCacheLive.compute(m.S)
		await idle(4)
		probe.on = false
		await process_frame
	var p_bsync: float = probe.p95()
	print("     bake SYNC: %d frames, p95 %.1f ms, max %.1f ms" % [probe.dt.size(), p_bsync, probe.mx()])
	control(p_bsync <= 20.0, "a CONTROL the bake run synchronously on the main thread has p95 %.1f ms (> 20)" % p_bsync)

	# e. the key memo
	var k_obj := "cape"
	ok(m.simc.state(m.S, k_obj) == "fresh", "e the cache is fresh")
	var h0: int = SimCacheLive.hashes
	for i in 500:
		m.simc.state(m.S, k_obj)
	var h1: int = SimCacheLive.hashes - h0
	ok(h1 <= 1, "e 500 reads of a fresh cache hashed the key %d time(s) (<= 1 per edit generation)" % h1)
	var n_obj: int = m.simc.meta.size()
	var t1 := Time.get_ticks_usec()
	for i in 2000:
		m.simc.frame_at(m.S, k_obj, float(i % 30) / 30.0)
	var new_ms := float(Time.get_ticks_usec() - t1) / 2000.0 / 1000.0
	var t2 := Time.get_ticks_usec()
	for i in 200:
		SimCacheLive.key_for(m.S, k_obj)
		m.simc.frame_at(m.S, k_obj, float(i % 30) / 30.0)
	var old_ms := float(Time.get_ticks_usec() - t2) / 200.0 / 1000.0
	print("     read cost: %.4f ms now, %.4f ms with a hash on every read" % [new_ms, old_ms])
	ok(new_ms <= old_ms and new_ms <= 0.5, "e the read cost %.4f ms <= the hash-every-read cost %.4f ms and <= 0.5 ms" % [new_ms, old_ms])
	var h2: int = SimCacheLive.hashes
	m._do(func(): ((m.S.cards[1]["pose"]["joints"] as Dictionary)["pelvis"] as Dictionary).set("twist", 40.0))
	var st_e := ""
	for i in 500:
		st_e = m.simc.state(m.S, k_obj)
	ok(st_e == "stale" and SimCacheLive.hashes - h2 <= n_obj, "e after an edit: stale, and the app's redraw plus 500 reads hashed %d time(s) (<= 1 per cached object = %d; each object has its own key)" % [SimCacheLive.hashes - h2, n_obj])
	var h3: int = SimCacheLive.hashes
	m._undo()
	for i in 500:
		st_e = m.simc.state(m.S, k_obj)
	ok(st_e == "fresh" and SimCacheLive.hashes - h3 <= n_obj, "e after the undo: fresh, and the redraw plus 500 reads hashed %d time(s) (<= 1 per cached object = %d)" % [SimCacheLive.hashes - h3, n_obj])
	var h4: int = SimCacheLive.hashes
	for i in 50:
		SimCacheLive.key_for(m.S, k_obj)
	control(SimCacheLive.hashes - h4 <= 1, "e CONTROL 50 raw key_for calls move the counter by %d (it can see hashing)" % (SimCacheLive.hashes - h4))

	print("BGTHREAD TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
