extends SceneTree
## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/perf60_test.gd     (L12: 60 fps with two fighters and one cloth item)
## The benchmark: the real app (main.tscn) in a 1920 x 1080 window, vsync off. combo3 (a 12-card fight clip, 30 fps) on the hero,
## its mirrored second fighter (Actor: add), and the baked cape (ClothJob, the app's own bake). 600 frames are played, each one
## `m._process(1/60)` followed by one real engine frame (await process_frame: the draw and the GPU sync are in the wall time).
## Per frame it records: wall ms (between engine frames), _process ms, the engine's TIME_PROCESS / TIME_PHYSICS_PROCESS monitors,
## and every PerfDoc bracket (the app's own: pose evaluation, skinning, UI, actors, cloth, ...). It prints p50 / p95 / p99 and
## each subsystem's share of the _process time.
## Bars, written before measuring:
##   a HONEST    600 frames ran; the hero AND the second fighter posed differently in at least 50 % of the frames (whole-body
##               state bytes); the cape's vertices changed in at least 100 distinct frames; CONTROL: the same detector run on a
##               paused clip (playing = false, 60 frames) says NOT animating for all three (the bar is not vacuous).
##   b BUDGET    p95 wall frame ms. Round one: REPORT ONLY (P95_TARGET_MS < 0). After that run the target below is registered and
##               not moved again: p95 <= P95_TARGET_MS.
##   c EQUAL     each optimisation's output equals the old path's within 1e-6 on the same frames (EQUAL bars below).
##   d NOTHING ELSE REGRESSES: easypart, peasy3, freestart and the suites of the code touched (wtest).
const FRAMES := 600
const WARM := 30
const DT := 1.0 / 60.0
const P95_TARGET_MS := -1.0   # REGISTERED AFTER THE FIRST RUN (see the commit that sets it)
const MIN_ANIM_FRAC := 0.5
const MIN_CLOTH_FRAMES := 100

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func boot() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	root.size = Vector2i(1920, 1080)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._actor_add()
	await idle(2)
	m.S.loop = true
	# the cape: the app's own background bake, driven to the end here
	var job := ClothJob.start(m.S)
	while not job.sample_for(50000):
		pass
	job.start_sim()
	while job.poll() != 2:
		await process_frame
	m.S.cape = job.take_result()
	m._refresh()
	m.playhead = 0.0
	m.playing = false
	m.set_process(false)   # only the test's frames run _process: each one is a fixed 1/60 s step


static func pct(a: Array, p: float) -> float:
	var b := a.duplicate()
	b.sort()
	return float(b[clampi(int(ceil(p / 100.0 * b.size())) - 1, 0, b.size() - 1)])


## what the detector sees of one frame: the hero's body, the second fighter's body, the cape's vertices at the playhead
func snap() -> Array:
	return [var_to_bytes(m.B.state()), var_to_bytes((m.actors_rt[1]["B"] as Body).state()), var_to_bytes(Cloth.verts_at(m.S.cape, m.playhead))]


## how many frames (after the first) differ from the frame before, for the hero, the second fighter and the cape
func changes(seq: Array) -> Array:
	var c := [0, 0, 0]
	for f in range(1, seq.size()):
		for k in 3:
			if seq[f][k] != seq[f - 1][k]:
				c[k] += 1
	return c


func run_frames(n: int, play: bool, record: bool) -> Dictionary:
	var rec := {"wall": [], "proc": [], "tproc": [], "tphys": [], "br": {}, "seq": []}
	PerfDoc.on = true
	var last := Time.get_ticks_usec()
	for f in n:
		m.playing = play
		PerfDoc.acc = {}
		var t0 := Time.get_ticks_usec()
		m._process(DT)
		var t1 := Time.get_ticks_usec()
		var brk := PerfDoc.acc.duplicate()
		if record:
			rec["seq"].append(snap())
		await process_frame
		var now := Time.get_ticks_usec()
		if record:
			rec["wall"].append((now - last) / 1000.0)
			rec["proc"].append((t1 - t0) / 1000.0)
			rec["tproc"].append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			rec["tphys"].append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			for k in brk:
				if not rec["br"].has(k):
					rec["br"][k] = []
				rec["br"][k].append(float(brk[k]) / 1000.0)
		last = now
	PerfDoc.on = false
	return rec


func report(tag: String, rec: Dictionary) -> float:
	var w: Array = rec["wall"]
	var p50 := pct(w, 50)
	var p95 := pct(w, 95)
	var p99 := pct(w, 99)
	print("BUDGET[%s] wall   ms  p50 %.2f  p95 %.2f  p99 %.2f  (fps at p50 %.1f)" % [tag, p50, p95, p99, 1000.0 / p50])
	for key in ["proc", "tproc", "tphys"]:
		var a: Array = rec[key]
		print("BUDGET[%s] %-6s ms  p50 %.2f  p95 %.2f  p99 %.2f" % [tag, key, pct(a, 50), pct(a, 95), pct(a, 99)])
	var tot := 0.0
	for x in rec["proc"]:
		tot += float(x)
	var rows := []
	for k in rec["br"]:
		var a2: Array = rec["br"][k]
		var s := 0.0
		for x in a2:
			s += float(x)
		rows.append({"k": k, "mean": s / w.size(), "p50": pct(a2, 50), "p95": pct(a2, 95), "p99": pct(a2, 99), "share": s / maxf(tot, 1e-9)})
	rows.sort_custom(func(a, b): return a["mean"] > b["mean"])
	for r in rows:
		print("BUDGET[%s]   %-10s mean %.3f  p50 %.3f  p95 %.3f  p99 %.3f ms  share of _process %.1f %%" % [tag, r["k"], r["mean"], r["p50"], r["p95"], r["p99"], 100.0 * r["share"]])
	var wsum := 0.0
	for x in w:
		wsum += float(x)
	print("BUDGET[%s] _process is %.1f %% of the wall frame (the rest: engine draw, GPU wait, idle)" % [tag, 100.0 * tot / maxf(wsum, 1e-9)])
	return p95


func _init() -> void:
	create_timer(600.0).timeout.connect(func(): quit(2))
	await boot()
	print("window %s, cape frames %d, scene %.1f s, fighters %d" % [str(DisplayServer.window_get_size()), (m.S.cape["frames"] as Array).size(), m.S.length(), m.actors_rt.size()])
	await run_frames(WARM, true, false)   # warm-up (shaders, first loads): not counted
	m.playhead = 0.0
	var rec := await run_frames(FRAMES, true, true)
	var ch := changes(rec["seq"])
	ok(rec["wall"].size() == FRAMES, "a 600 frames were played (%d)" % rec["wall"].size())
	ok(ch[0] >= MIN_ANIM_FRAC * (FRAMES - 1) and ch[1] >= MIN_ANIM_FRAC * (FRAMES - 1) and ch[2] >= MIN_CLOTH_FRAMES,
		"a animating: hero posed differently in %d of %d frames, second fighter %d, cape vertices changed in %d" % [ch[0], FRAMES - 1, ch[1], ch[2]])
	# CONTROL: a paused clip must be caught as not animating
	var ctl := await run_frames(60, false, true)
	var cc := changes(ctl["seq"])
	ok(cc[0] < MIN_ANIM_FRAC * 59 and cc[1] < MIN_ANIM_FRAC * 59 and cc[2] < MIN_CLOTH_FRAMES,
		"a control: a PAUSED clip is caught as not animating (hero %d, second fighter %d, cape %d changed frames of 59)" % [cc[0], cc[1], cc[2]])
	m.playhead = 0.0
	var p95 := report("play", rec)
	if P95_TARGET_MS < 0.0:
		print("b BUDGET (report only, no target registered yet): p95 %.2f ms" % p95)
	else:
		ok(p95 <= P95_TARGET_MS, "b budget: p95 %.2f ms <= registered target %.2f ms" % [p95, P95_TARGET_MS])
	print("PERF60 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
