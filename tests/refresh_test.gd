extends SceneTree
## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/refresh_test.gd     (L64 L-REFRESH: playback _refresh skips unchanged work)
## docs/PERF_SCOUT_1106.md item 8: during playback _process took 8.2 ms and 7.5 ms of that was Main._refresh (the hands card and its dock).
## The real app (main.tscn), combo3, off-screen window, vsync off. `_process(1/60)` is driven by the test. PerfDoc.refresh_full = true is the
## REFERENCE path (every block of _refresh runs every frame, as before this lane); false is the new path.
## BARS (written before any implementation, never moved):
##   R1 SPEED   1 fighter, playing, 5 runs of 60 frames, median of the 5 run medians of _process: < 5.0 ms.
##   R2 SPEED4  4 fighters (tests/perf4_test.gd's setup, 1600 x 900), the same measure: the new path is LOWER than the reference path, run
##              alternately in one process (same load). The number is printed.
##   R3 EQUAL   30 playing frames of the clip: SHA-256 of (the hero's Body.state(), the hands card: visible, position, size, state text, the
##              buttons' disabled / pressed / tooltip, the flow's width) per frame. New path == reference path in the same process AND == GOLDEN
##              (the hash of the code before this lane). CONTROL: with PerfDoc.refresh_plant (a refresh that should have run is skipped) the hash
##              must DIFFER from the reference (else the hash cannot see a stale card).
##   R4 SAME FRAME  scrub (playhead set + _refresh), a card edit made mid-playback, undo, redo, a part pick, a camera orbit: the block state right
##              after each step (before the next _process) is hashed; new == reference at every step, and the steps are not all equal to each
##              other (anti-vacuity: the card does move).
## SPEED numbers are taken with the machine load printed (CPU %, godot processes); a speed bar fails only on the number, the load is reported.
var fails := 0
var m: Node
const DT := 1.0 / 60.0
## the pose part of the 30-frame hash on the code before this lane (3 runs, 3 loads: identical). The block part (the card) follows the status
## label, which follows the real clock, so its absolute hash is not a golden: it is compared with the reference path in the same process.
const GOLDEN_POSE := "3bdfd48fe68d"   # R3: filled from the run on the unchanged code (a measured identity, not a threshold)
const R1_BAR := 5.0
const RUNS := 5
const FR := 60


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func load_line() -> String:
	var out := []
	OS.execute("powershell", ["-NoProfile", "-Command", "$c=(Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average; $g=(Get-Process -Name Godot* -ErrorAction SilentlyContinue | Measure-Object).Count; ('cpu ' + $c + '%, godot processes ' + $g)"], out, true)
	return String(out[0]).strip_edges() if not out.is_empty() else "load unknown"


func boot(w: int, h: int) -> void:
	if m != null:
		m.undo.clear()
		m.redo.clear()
		m.queue_free()
		await idle(3)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(w, h))
	root.size = Vector2i(w, h)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.easy.set_on(false, false)
	m._as_wait = -1e9
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.undo.clear()
	m.redo.clear()
	m.S.loop = true
	m._page_set("ANIMATE", false)
	await idle(3)


## the 4-fighter scene of tests/perf4_test.gd (hero + mirrored combo3 + walk_bat and its mirror)
func fighters4() -> void:
	var M := Body.new()
	M.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var hero_d: Dictionary = m.S.to_dict(m.B)
	hero_d.erase("actors")
	var S2 := Scene.new()
	S2.from_dict(Scene.mirror_file(hero_d, M))
	var W3 := Scene.new()
	W3.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	var S3 := W3.clone()
	var S4 := Scene.new()
	S4.from_dict(Scene.mirror_file(W3.to_dict(M), M))
	m.S.actors = [
		{"name": "fighter 2", "xf": {"pos": [0.0, 1.5], "yaw": 180.0}, "scene": S2},
		{"name": "fighter 3", "xf": {"pos": [1.5, 1.5], "yaw": 225.0}, "scene": S3},
		{"name": "fighter 4", "xf": {"pos": [1.5, 0.0], "yaw": 90.0}, "scene": S4},
	]
	m._actors_build(m.B, m.S)
	for a in m.actors_rt:
		(a["S"] as Scene).loop = true
	m._refresh()


func median(a: Array) -> float:
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() / 2])


## median of RUNS run-medians of the app's _process (ms), the reference or the new path
func speed(full: bool) -> float:
	PerfDoc.refresh_full = full
	m.set_process(false)
	m.playing = true
	var meds := []
	for r in RUNS:
		var ts := []
		for f in FR + 10:
			var t0 := Time.get_ticks_usec()
			m._process(DT)
			if f >= 10:
				ts.append((Time.get_ticks_usec() - t0) / 1000.0)
		meds.append(median(ts))
	m.playing = false
	PerfDoc.refresh_full = false
	return median(meds)


## the hands card and the dock as the user sees them
func block_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	var pnl: Control = m.ui_hands_panel
	if pnl == null:
		return out
	out.append_array(var_to_bytes([pnl.visible, pnl.position, pnl.size]))
	for d in m.ui_hands:
		if d["easy"]:
			continue
		out.append_array(var_to_bytes([(d["state"] as Label).text, (d["both"] as Button).disabled, (d["let_l"] as Button).disabled, (d["let_r"] as Button).disabled,
			(d["follow"] as Button).button_pressed, (d["only"] as Button).button_pressed, (d["let_l"] as Button).tooltip_text, (d["let_r"] as Button).tooltip_text,
			(d["both"] as Button).get_parent().custom_minimum_size]))
	return out


## the status and mouse-hint labels are blockers of the card and follow the real clock: the same text for every pass
func pin_labels() -> void:
	if m.ui_status != null:
		m.ui_status.text = "status line"


func hash_frames(mode: String) -> Dictionary:
	PerfDoc.refresh_full = mode == "full"
	PerfDoc.refresh_plant = mode == "plant"
	m.set_process(false)
	m.playhead = 0.0
	m.playing = true
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	var hp := HashingContext.new()   # (INFO) the pose part and the block part apart, to see which one moves between processes
	hp.start(HashingContext.HASH_SHA256)
	var hb := HashingContext.new()
	hb.start(HashingContext.HASH_SHA256)
	var shown := 0
	var pos := {}
	for f in 30:
		pin_labels()
		m._process(DT)
		hc.update(var_to_bytes(m.B.state()))
		hc.update(block_bytes())
		hp.update(var_to_bytes(m.B.state()))
		hb.update(block_bytes())
		if m.ui_hands_panel != null and m.ui_hands_panel.visible:
			shown += 1
			pos[str(m.ui_hands_panel.position)] = true
	m.playing = false
	PerfDoc.refresh_full = false
	PerfDoc.refresh_plant = false
	return {"h": hc.finish().hex_encode(), "hp": hp.finish().hex_encode().substr(0, 12), "hb": hb.finish().hex_encode().substr(0, 12), "shown": shown, "spots": pos.size()}


func step_hash() -> String:
	return block_bytes().hex_encode().sha256_text() + "|" + var_to_bytes(m.B.state()).hex_encode().sha256_text()


## the same user steps, hashing the blocks right after each one
func steps(full: bool) -> Array:
	PerfDoc.refresh_full = full
	m.set_process(false)
	m.playhead = 0.0
	m.playing = true
	var out := []
	for i in 12:
		m._process(DT)
	for t in [0.9, 0.2, 1.4, 0.0]:
		m.playing = false
		m.playhead = t
		m._refresh()
		out.append(step_hash())
	m.playing = true
	m.playhead = 0.5
	for i in 4:
		m._process(DT)
	m._do(func():
		var p: Dictionary = (m.S.cards[1]["pose"] as Dictionary).duplicate(true)
		var o: Array = p["offset"]
		p["offset"] = [float(o[0]) + 0.3, float(o[1]), float(o[2])]
		m.S.cards[1]["pose"] = p)
	out.append(step_hash())   # the edit, before the next frame
	m._process(DT)
	out.append(step_hash())
	m._undo()
	out.append(step_hash())
	m._process(DT)
	out.append(step_hash())
	m._redo()
	out.append(step_hash())
	m.sel = "hand_l"
	m._refresh()
	out.append(step_hash())
	m.yaw += 40.0
	m._cam()
	m._refresh()
	out.append(step_hash())
	m._process(DT)
	out.append(step_hash())
	m.playing = false
	PerfDoc.refresh_full = false
	return out


## INFO only: the PerfDoc brackets (ms per frame) of the playing frames, top 14
func profile(tag: String) -> void:
	PerfDoc.on = true
	PerfDoc.acc = {}
	m.set_process(false)
	m.playing = true
	for f in 60:
		m._process(DT)
	m.playing = false
	PerfDoc.on = false
	var rows := []
	for k in PerfDoc.acc:
		rows.append([float(PerfDoc.acc[k]) / 60000.0, k])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	var sres := []
	for r in rows.slice(0, 40):
		sres.append("%s %.2f" % [r[1], r[0]])
	print("INFO profile %s: %s" % [tag, ", ".join(sres)])
	PerfDoc.acc = {}
	print("INFO natives: dock scans %d, corrective pushes %d, in-place mesh rewrites %d (reuse_ok %s); dock lists built %d" % [HandsDock.native_calls, Corrective.native_pushes, m.corr.reused, str(m.corr.reuse_ok), HandsDock.rebuilds])


## R5: the two C++ loops equal their GDScript twins, bit for bit, on random inputs
func equality() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6464
	ok(HandsDock.native_ok() and Corrective.native_ok(), "R5 anti-vacuity: KineDockNative is loaded")
	var bad_ff := 0
	var found := 0
	var none := 0
	for c in 400:
		var n := rng.randi_range(0, 500)
		var spots := PackedFloat64Array()
		for i in n:
			spots.append(float(rng.randi_range(0, 200)) * 6.0 + (0.5 if c % 7 == 0 else 0.0))
			spots.append(float(rng.randi_range(0, 120)) * 6.0)
		var ps := Vector2(rng.randf_range(100, 560), rng.randf_range(40, 300))
		var big := c % 2 == 0   # half the bodies are wider than the room: every spot rejected (the `none` outcome)
		var body := Rect2(rng.randf_range(0, 100), rng.randf_range(0, 50), rng.randf_range(1300, 2200), rng.randf_range(800, 1400)) if big else Rect2(rng.randf_range(0, 1200), rng.randf_range(0, 700), rng.randf_range(0, 900), rng.randf_range(0, 600))
		var pts := []
		for k in rng.randi_range(0, 80):
			pts.append(Vector2(rng.randf_range(0, 1400), rng.randf_range(0, 800)))
		for avoid in [true, false]:
			var a := HandsDock._first_free_gd(spots, ps, body, avoid, pts)
			var b: int = HandsDock._door.first_free(spots, ps.x, ps.y, body, avoid, PackedVector2Array(pts), 2.0)
			if a != b:
				bad_ff += 1
			if a >= 0:
				found += 1
			else:
				none += 1
	ok(bad_ff == 0 and found > 100 and none > 100, "R5 first_free: native == GDScript twin on 800 cases (%d found a spot, %d none), %d differ" % [found, none, bad_ff])
	var bad_p := 0
	for c in 200:
		var n := rng.randi_range(1, 3000)
		var vs := PackedVector3Array()
		var dv := PackedVector3Array()
		for i in n:
			vs.append(Vector3(rng.randf_range(-1, 1), rng.randf_range(-2, 2), rng.randf_range(-1, 1)))
			dv.append(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)))
		var ai := PackedInt32Array()
		for i in rng.randi_range(0, n):
			ai.append(rng.randi_range(0, n - 1))
		var amp := 0.013 * rng.randf_range(0.0, 1.0)
		if Corrective._push_gd(vs, dv, ai, amp) != Corrective._door.push(vs, dv, ai, amp):
			bad_p += 1
	ok(bad_p == 0, "R5 push: native == GDScript twin on 200 random meshes (bit for bit), %d differ" % bad_p)


func _init() -> void:
	await idle(2)
	print("load before: " + load_line())
	# ---- 1 fighter (R3 first: a fresh app, so the golden does not depend on what ran before it)
	await boot(1280, 720)
	hash_frames("full")   # warm-up pass: the first pass leaves the dock cache and the first-frame state behind
	var href := hash_frames("full")
	var hnew := hash_frames("new")
	var hpl := hash_frames("plant")
	print("INFO R3 parts: pose %s block %s" % [href["hp"], href["hb"]])
	print("INFO R3 hashes: ref %s new %s plant %s shown %d frames, %d distinct card spots" % [href["h"], hnew["h"], hpl["h"], href["shown"], href["spots"]])
	ok(int(href["shown"]) >= 25, "R3 anti-vacuity: the hands card is on screen in %d of 30 frames" % href["shown"])
	ok(String(href["h"]) == String(hnew["h"]), "R3 new path == reference path over 30 frames")
	ok(String(href["hp"]) == GOLDEN_POSE and String(hnew["hp"]) == GOLDEN_POSE, "R3 pose part of the new path == GOLDEN (the code before this lane): %s" % hnew["hp"])
	ok(String(hpl["h"]) != String(href["h"]), "R3 CONTROL: a skipped hands refresh changes the hash (the hash sees a stale card)")
	if OS.get_environment("REFRESH_ONLY") == "r3":
		quit(0)
		return
	var ld1 := load_line()
	if OS.get_environment("REFRESH_ONLY") == "prof":
		profile("1 fighter")
		quit(0)
		return
	profile("1 fighter")
	var old1 := speed(true)
	var new1 := speed(false)
	var old1b := speed(true)
	var new1b := speed(false)
	var o1 := minf(old1, old1b)
	var n1 := maxf(new1, new1b)
	print("INFO R1 1 fighter _process median-of-5: reference %.2f / %.2f ms, new %.2f / %.2f ms; load %s" % [old1, old1b, new1, new1b, ld1])
	ok(n1 < R1_BAR, "R1 1 fighter playing: _process %.2f ms (worst of 2 rounds) < %.1f ms (reference %.2f ms)" % [n1, R1_BAR, o1])
	equality()
	# ---- R4
	await boot(1280, 720)
	var sa := steps(true)
	await boot(1280, 720)
	var sb := steps(false)
	var same := 0
	var uniq := {}
	for i in sa.size():
		if sa[i] == sb[i]:
			same += 1
		uniq[sa[i]] = true
	ok(same == sa.size(), "R4 same frame: %d of %d steps (scrub x4, edit, frame, undo, frame, redo, pick, orbit, frame) equal the reference" % [same, sa.size()])
	ok(uniq.size() >= 6, "R4 anti-vacuity: the steps give %d distinct states" % uniq.size())
	# ---- 4 fighters
	await boot(1600, 900)
	fighters4()
	await idle(3)
	var ld4 := load_line()
	var old4 := speed(true)
	var new4 := speed(false)
	var old4b := speed(true)
	var new4b := speed(false)
	print("INFO R2 4 fighters _process median-of-5: reference %.2f / %.2f ms, new %.2f / %.2f ms; load %s" % [old4, old4b, new4, new4b, ld4])
	ok(maxf(new4, new4b) < minf(old4, old4b), "R2 4 fighters: new %.2f ms (worst) < reference %.2f ms (best)" % [maxf(new4, new4b), minf(old4, old4b)])
	print("load after: " + load_line())
	print("refresh: %d fail" % fails)
	quit(1 if fails > 0 else 0)
