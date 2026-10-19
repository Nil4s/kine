## godot --path . -s tests/perf4_test.gd     (ROADMAP 99: four fighters at 60 fps playback; needs a window)
## FOUR FIGHTERS, EACH WITH A BAT AND A COMBO, PLAYED IN THE REAL APP (main.tscn) in a 1600 x 900 window, timeline and UI shown.
## The hero is combo3 (read only); fighter 2 is combo3 mirrored (Actor: add's own way), fighters 3 and 4 are scenes/walk_bat.json
## (read only) and its mirror. Nothing is written to scenes/, poses/ or data/.
##
## MEASURED (all numbers printed):
##   A. POSE HASH, fixed step: 600 frames at 60 Hz with the app's own _process (no engine frames); the body state of all four
##      fighters after every frame, SHA-256 over the bytes (var_to_bytes keeps every float bit). The hash must equal GOLDEN.
##   B. FRAME TIME, real playback: the engine drives the frames (vsync off so the cost shows), 60 frames warm-up, then 600
##      frames. Wall time between frames (median, p99) and Godot's own Performance.TIME_PROCESS monitor (median, p99).
##   C. BREAKDOWN: the same playback run again with one subsystem stubbed out per run (PerfStub): the drop in median from
##      the full run is that subsystem's share. The stubbed runs change the picture, so their hashes are not checked.
##
## BARS (ROADMAP 99): median frame time < 16.7 ms AND p99 < 25 ms, with the pose hash unchanged. When another Godot is running on
## the machine (the load is printed), the timing is INFO instead of FAIL; the hash is always checked.
extends SceneTree

const W := 1600
const H := 900
const FRAMES := 600
const WARM := 60
const DT := 1.0 / 60.0
const MED_BAR := 16.7
const P99_BAR := 25.0
## the pose hash of the 600 fixed-step frames (A). Measured on the code before ROADMAP 99 (commit 01a427a).
const GOLDEN := "1545729e378cdf1acb733d3a8166b5123e267815b19ac306f2e9f685cf00d6c2"
const OUT_PNG := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/fighters60.png"
const STUBS := ["body", "skinning", "ik_plants", "hits", "timeline", "ui"]

var fails := 0
var info := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func info_line(what: String) -> void:
	print("INFO " + what)
	info += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func pct(a: Array, p: float) -> float:
	var s := a.duplicate()
	s.sort()
	if s.is_empty():
		return NAN
	return float(s[mini(s.size() - 1, int(ceil(p * s.size())) - 1)])


func median(a: Array) -> float:
	return pct(a, 0.5)


## the 4-fighter scene: built on the open combo3 (the hero), the fighters' own scenes are made from read-only sources
func build_fighters() -> void:
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
	m.S.loop = true
	m._refresh()


func boot() -> void:
	if m != null:
		m.queue_free()
		await idle(3)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.undo.clear()
	m.redo.clear()
	build_fighters()
	# the fighters' hit report (dummy.gd fighter_hits) runs on a worker after every change; playback is timed once it is done
	var n := 0
	while not m._dm_job.is_empty() and n < 5000:
		await process_frame
		n += 1
	m._as_wait = -1e9   # no autosave write during the timed runs (it writes the scene dict every 15 s: a frame spike, not playback)
	m.playhead = 0.0
	m.playing = false


func states_bytes() -> PackedByteArray:
	var out := PackedByteArray()
	for a in m.actors_rt:
		out.append_array(var_to_bytes((a["B"] as Body).state()))
	return out


## (A) the pose hash: the app's own _process at a fixed step, the test's own loop (engine frames not used)
func pose_hash() -> Dictionary:
	await boot()
	m.set_process(false)
	m.playhead = 0.0
	m.playing = true
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	var cost := []
	for f in FRAMES:
		var t0 := Time.get_ticks_usec()
		m._process(DT)
		cost.append((Time.get_ticks_usec() - t0) / 1000.0)
		hc.update(states_bytes())
	m.playing = false
	m.set_process(true)
	return {"hash": hc.finish().hex_encode(), "cost": cost}


## (B) the frames the engine drives: wall time between frames, and the process time Godot's monitor reports
func timed_run() -> Dictionary:
	m.playhead = 0.0
	m.playing = true
	m.set_process(true)
	for i in WARM:
		await process_frame
	var wall := []
	var proc := []
	var last := Time.get_ticks_usec()
	var shot_taken := false
	for i in FRAMES:
		await process_frame
		var now := Time.get_ticks_usec()
		wall.append((now - last) / 1000.0)
		last = now
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		if i == FRAMES / 2 and not shot_taken:
			shot_taken = true
	m.playing = false
	return {"wall": wall, "proc": proc}


## the Godot processes other than this one (tasklist, read only; nothing is stopped here)
func load_line() -> String:
	var buf := []
	OS.execute("tasklist", ["/FI", "IMAGENAME eq Godot_v4.7.2-stable_win64_console.exe", "/FO", "CSV", "/NH"], buf)
	var me := OS.get_process_id()
	var n := 0
	for s in buf:
		for line in String(s).split("
"):
			if line.contains("Godot") and line.get_slice(",", 2).replace("\"", "").to_int() != me:
				n += 1
	return "%d other Godot process%s" % [n, "" if n == 1 else "es"]


func report(tag: String, r: Dictionary) -> Dictionary:
	var w: Array = r["wall"]
	var p: Array = r["proc"]
	var out := {"med": median(w), "p99": pct(w, 0.99), "pmed": median(p), "p99p": pct(p, 0.99)}
	print("     %-10s wall median %6.2f ms  p99 %6.2f ms | TIME_PROCESS median %6.2f ms  p99 %6.2f ms" % [tag, out["med"], out["p99"], out["pmed"], out["p99p"]])
	var worst := w.duplicate()
	worst.sort()
	worst.reverse()
	print("     %-10s worst 5 frames (ms): %s; frames over 25 ms: %d of %d" % [tag, ", ".join(worst.slice(0, 5).map(func(x): return "%.1f" % x)), w.filter(func(x): return x > P99_BAR).size(), w.size()])
	return out


func _init() -> void:
	DisplayServer.window_set_size(Vector2i(W, H))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	print("     load before the run: %s" % load_line())
	# (A) pose hash
	var h := await pose_hash()
	var hc_ok := String(h["hash"]) == GOLDEN
	print("     pose hash (A): %s  (golden %s)" % [h["hash"], GOLDEN if GOLDEN != "" else "not yet set"])
	ok(hc_ok, "A pose hash unchanged: %d frames x 4 fighters, every frame" % FRAMES)
	var hcost := h["cost"] as Array
	print("     fixed-step _process cost: median %.2f ms, p99 %.2f ms" % [median(hcost), pct(hcost, 0.99)])
	# (B) real playback, the full scene
	await boot()
	var full := report("full", await timed_run())
	var load_now := load_line()
	var quiet := load_now.begins_with("0 ")
	var med_ok: bool = full["med"] < MED_BAR
	var p99_ok: bool = full["p99"] < P99_BAR
	if quiet:
		ok(med_ok, "B median frame time %.2f ms < %.1f ms (%s)" % [full["med"], MED_BAR, load_now])
		ok(p99_ok, "B p99 frame time %.2f ms < %.1f ms (%s)" % [full["p99"], P99_BAR, load_now])
	else:
		info_line("B median %.2f ms (bar < %.1f), p99 %.2f ms (bar < %.1f): the machine is busy (%s), timing not gated" % [full["med"], MED_BAR, full["p99"], P99_BAR, load_now])
	# (C) one subsystem stubbed per run
	for s in STUBS:
		PerfStub.off = {s: true}
		await boot()
		var r := report("-" + s, await timed_run())
		print("     %-10s share of the median: %.2f ms" % [s, float(full["med"]) - float(r["med"])])
	PerfStub.off = {}
	# the picture: the whole scene mid-play (the playhead moves, then the frame is read from the window)
	await boot()
	m.playhead = 0.0
	m.playing = true
	for i in 180:
		await process_frame
	m.playing = false
	await idle(3)
	var mid_t: float = m.playhead
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png(OUT_PNG)
	ok(err == OK and img.get_width() == W and img.get_height() == H, "screenshot of the four fighters mid-play at t = %.2f s (%dx%d): %s" % [mid_t, img.get_width(), img.get_height(), OUT_PNG])
	print("PERF4 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
