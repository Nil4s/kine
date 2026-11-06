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
##   b BUDGET    GOAL: p95 wall frame <= 16.7 ms (60 fps), printed as a report line and marked GOAL UNMET when it is not met (it is
##               not counted into the fail total: the goal is the target, not a regression gate). REGRESSION bar (counted): in the
##               same process, 3 alternating pairs of 240 frames, reference paths (PerfDoc.slow, SkinPick.force_gd) then the fixes
##               on the same app, median fixed p95 < median reference p95.
##   c EQUAL     each optimisation's output equals the old path's within 1e-6 on the same frames (EQUAL bars below).
##     EQUAL_TOUCH  Body.touching_parts() == the old loop (touching_parts_ref) on 60 poses of the clip, both fighters
##     EQUAL_DOCK   HandsDock.blockers (no 3D subtrees) == the full walk; the hands card lands on the same position and size
##                  (fast vs PerfDoc.slow) on 60 poses, with the card VISIBLE (a weapon in hand: anti-vacuity)
##     EQUAL_SKIN   SkinPick.refresh C++ == GDScript: every posed vertex within 1e-6 m and every chunk box within 1e-6 m
##   d NOTHING ELSE REGRESSES: easypart, peasy3, freestart and the suites of the code touched (wtest).
const FRAMES := 600
const WARM := 30
const DT := 1.0 / 60.0
const GOAL_P95_MS := 16.7
## the pick's distance is along a ray ~5.5 m long from the camera: one float32 step there is 4.8e-7 m and the vertices differ by up to 2.4e-7 m
## (EQUAL_SKIN holds those to 1e-6), so the hit distance is held to 10 micrometres; the PART must be identical.
const PICK_T_TOL := 1e-5
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
	if OS.get_environment("PERF60_SOFT") == "1":   # L22: the same benchmark with the soft flesh on (all six regions); not part of any bar
		for g in SoftBody.GROUPS:
			m.soft_set(g, true)
		await idle(2)
		while not m.soft_live.ready():
			await process_frame
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


## pose the hero at playhead t and refresh (the pose, the second fighter and the panels follow)
func pose_at(t: float) -> void:
	m.playing = false
	m.playhead = t
	m._ps().apply(m.B, m._ps().play_t(t))
	m._refresh()


static func mx(v: Variant) -> float:
	var a = v.abs()
	return maxf(a.x, maxf(a.y, a.z if a is Vector3 else 0.0))


func rect_dev(a: AABB, b: AABB) -> float:
	return maxf(mx(a.position - b.position), mx(a.size - b.size))


func equality() -> void:
	var n := 60
	var L: float = m.S.length()
	# touch
	var t_ok := 0
	var t_any := 0
	for k in n:
		pose_at(L * float(k) / float(n))
		for B in [m.B, (m.actors_rt[1]["B"] as Body)]:
			var a: Dictionary = B.touching_parts()
			var b: Dictionary = B.touching_parts_ref()
			if a.hash() == b.hash() and a.size() == b.size():
				t_ok += 1
			t_any += 1 if not b.is_empty() else 0
	ok(t_ok == 2 * n, "c EQUAL_TOUCH touching_parts == the old loop on %d poses x 2 fighters (%d)" % [n, t_ok])
	print("     touching sets non-empty on %d of %d" % [t_any, 2 * n])
	# dock: blockers and the card
	var panel: Control = m.ui_hands_panel
	var d_ok := 0
	var vis := 0
	var blk_ok := 0
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var vrect := Rect2(float(m.LEFT_W), float(m.TOP_H), vs.x - float(m.LEFT_W) - float(m.RIGHT_W), vs.y - float(m.TOP_H) - float(m.bottom_h))
	for k in n:
		pose_at(L * float(k) / float(n))
		PerfDoc.slow = true
		var b_old: Array = HandsDock.blockers(m, panel, vrect, [m.ui_status, m.ui_mouse, m.ui_bar, m.ui_cube])
		m._hands_refresh()
		var p_old := [panel.position, panel.size, panel.visible]
		PerfDoc.slow = false
		var b_new: Array = HandsDock.blockers(m, panel, vrect, [m.ui_status, m.ui_mouse, m.ui_bar, m.ui_cube])
		m._hands_refresh()
		var p_new := [panel.position, panel.size, panel.visible]
		if b_old == b_new:
			blk_ok += 1
		elif k == 0:
			print("     blockers old %d new %d; first diff:" % [b_old.size(), b_new.size()])
			for i in mini(b_old.size(), b_new.size()):
				if b_old[i] != b_new[i]:
					print("       ", i, b_old[i], b_new[i])
					break
		if mx(p_old[0] - p_new[0]) <= 1e-6 and mx(p_old[1] - p_new[1]) <= 1e-6 and p_old[2] == p_new[2]:
			d_ok += 1
		if p_new[2]:
			vis += 1
	ok(blk_ok == n and d_ok == n, "c EQUAL_DOCK blockers lists equal %d/%d, the card's position and size equal %d/%d" % [blk_ok, n, d_ok, n])
	ok(vis == n, "c EQUAL_DOCK anti-vacuity: the hands card was visible (placed) on %d of %d poses" % [vis, n])
	# skin: C++ vs GDScript
	if not SkinPick.native_ok():
		print("SKIP c EQUAL_SKIN: the DLL has no KineSkinNative.skin_points")
		return
	var sp: SkinPick = m.skp
	var worst_v := 0.0
	var worst_b := 0.0
	var cnt := 0
	for k in 20:
		pose_at(L * float(k) / 20.0)
		SkinPick.force_gd = true
		sp.dirty = true
		sp.refresh()
		var pos_gd := []
		var box_gd := []
		for s2 in sp.surfs:
			pos_gd.append((s2["pos"] as PackedVector3Array).duplicate())
		for gr in sp.groups:
			for c in gr["chunks"]:
				box_gd.append(c["box"])
		SkinPick.force_gd = false
		sp.dirty = true
		sp.refresh()
		for i in sp.surfs.size():
			var a2: PackedVector3Array = sp.surfs[i]["pos"]
			var b2: PackedVector3Array = pos_gd[i]
			if a2.size() != b2.size():
				worst_v = INF
			for j in a2.size():
				worst_v = maxf(worst_v, mx(a2[j] - b2[j]))
				cnt += 1
		var bi := 0
		for gr in sp.groups:
			for c in gr["chunks"]:
				worst_b = maxf(worst_b, rect_dev(c["box"], box_gd[bi]))
				bi += 1
	ok(cnt > 100000 and worst_v <= 1e-6 and worst_b <= 1e-6, "c EQUAL_SKIN C++ vs GDScript re-skin: %d vertices over 20 poses, worst vertex %s m, worst chunk box %s m (bar 1e-6)" % [cnt, str(worst_v), str(worst_b)])


func set_slow(on: bool) -> void:
	PerfDoc.slow = on
	SkinPick.force_gd = on


func paired() -> void:
	var slow_p := []
	var fast_p := []
	for r in 3:
		set_slow(true)
		m.playhead = 0.0
		var a := await run_frames(240, true, true)
		slow_p.append(pct(a["wall"], 95))
		set_slow(false)
		m.playhead = 0.0
		var b := await run_frames(240, true, true)
		fast_p.append(pct(b["wall"], 95))
	var ss := slow_p.duplicate()
	ss.sort()
	var ff := fast_p.duplicate()
	ff.sort()
	print("     paired p95 ms: reference %s, fixes %s" % [str(slow_p), str(fast_p)])
	ok(float(ff[1]) < float(ss[1]), "b REGRESSION fixed median p95 %.2f ms < reference median p95 %.2f ms (same process, alternating)" % [ff[1], ss[1]])


func equality2() -> void:
	var L: float = m.S.length()
	var sp: SkinPick = m.skp
	# PICK: the same part and distance with the C++ re-skin and the GDScript one, the cursor on the body
	var same := 0
	var hits := 0
	for k in 20:
		pose_at(L * float(k) / 20.0)
		var mp: Vector2 = m.cam.unproject_position(m.B.P["spine_03"])
		SkinPick.force_gd = true
		sp.dirty = true
		var a: String = m._pick(mp)
		var ta: float = m._pick_t
		SkinPick.force_gd = false
		sp.dirty = true
		var b: String = m._pick(mp)
		var tb: float = m._pick_t
		if a == b and (absf(ta - tb) <= PICK_T_TOL or (is_inf(ta) and is_inf(tb))):
			same += 1
		if a != b or absf(ta - tb) > PICK_T_TOL:
			print("     pick differs at pose %d: gd '%s' %s, native '%s' %s" % [k, a, str(ta), b, str(tb)])
		if b != "":
			hits += 1
	ok(same == 20, "c EQUAL_PICK part and distance equal, C++ vs GDScript re-skin, cursor on the body, 20 poses (%d)" % same)
	ok(hits >= 15, "c EQUAL_PICK anti-vacuity: the cursor was on the body in %d of 20 poses" % hits)
	# MOUSE HINT: playing + an unmoved mouse = no new look; stopped = a look
	var mh = m.ui_mouse
	m.playing = true
	mh.tick(0.3)
	var l0: int = mh.looks
	var s0: int = mh.skipped
	mh.tick(0.3)
	mh.tick(0.3)
	var skipped_ok: bool = mh.looks == l0 and mh.skipped == s0 + 2
	m.playing = false
	mh.tick(0.3)
	ok(skipped_ok and mh.looks == l0 + 1, "b MOUSE HINT playing with an unmoved mouse makes no look (2 skipped), stopped makes one (looks %d -> %d)" % [l0, mh.looks])
	# HANDS CARD CACHE: cached placement == fresh placement over 60 poses, then a planted UI change must recompute
	var panel: Control = m.ui_hands_panel
	PerfDoc.slow = false
	var c_ok := 0
	var rb0: int = HandsDock.recomputes
	var cc0: int = HandsDock.cached_calls
	for k in 60:
		pose_at(L * float(k) / 60.0)
		m._hands_refresh()
		var pc := [panel.position, panel.size]
		PerfDoc.slow = true
		m._hands_refresh()
		var pf := [panel.position, panel.size]
		PerfDoc.slow = false
		if mx(pc[0] - pf[0]) <= 1e-6 and mx(pc[1] - pf[1]) <= 1e-6:
			c_ok += 1
	var used: int = HandsDock.cached_calls - cc0
	ok(c_ok == 60 and used >= 30, "c EQUAL_CACHE cached placement == fresh over 60 poses (%d/60); %d calls answered from the lists, signature changed %d times" % [c_ok, used, HandsDock.recomputes - rb0])
	m._hands_refresh()
	var before: Vector2 = panel.position
	var plug := Button.new()
	plug.text = "planted"
	plug.custom_minimum_size = Vector2(520, 320)
	m.add_child(plug)
	plug.global_position = panel.position - Vector2(60, 60)
	plug.size = Vector2(520, 320)
	var rc0: int = HandsDock.recomputes
	m._hands_refresh()
	var pc2 := [panel.position, panel.size]
	var re1: bool = HandsDock.recomputes > rc0
	PerfDoc.slow = true
	m._hands_refresh()
	var pf2 := [panel.position, panel.size]
	PerfDoc.slow = false
	ok(re1 and mx(pc2[0] - pf2[0]) <= 1e-6 and mx(pc2[1] - pf2[1]) <= 1e-6 and mx(pc2[0] - before) > 1.0,
		"c EQUAL_CACHE planted Button: the signature changed (recomputed), the card moved %.0f px and equals the fresh placement" % mx(pc2[0] - before))
	plug.queue_free()
	await process_frame
	m._hands_refresh()
	m._hands_refresh()
	var pc3: Vector2 = panel.position
	PerfDoc.slow = true
	m._hands_refresh()
	var pf3: Vector2 = panel.position
	PerfDoc.slow = false
	ok(mx(pc3 - pf3) <= 1e-6 and mx(pc3 - before) <= 1e-6, "c EQUAL_CACHE planted Button removed: the card is back where it was and equals the fresh placement")


func _init() -> void:
	create_timer(600.0).timeout.connect(func(): quit(2))
	if OS.get_environment("PERF60_SLOW") == "1":   # the BEFORE run: the reference paths of every fix
		PerfDoc.slow = true
		SkinPick.force_gd = true
		print("PERF60_SLOW: reference paths (before the fixes)")
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
	if OS.get_environment("PERF60_SLOW") != "1":
		await equality()
		await equality2()
	if p95 <= GOAL_P95_MS:
		print("b GOAL MET: p95 %.2f ms <= %.1f ms" % [p95, GOAL_P95_MS])
	else:
		print("b GOAL UNMET: p95 %.2f ms > %.1f ms (60 fps)" % [p95, GOAL_P95_MS])
	if OS.get_environment("PERF60_SLOW") != "1":
		await paired()
	print("PERF60 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
