## godot --headless --path . -s tests/motion_match_test.gd     (ROADMAP 33, MOTION-MATCHING PREVIEW; scripts/motion_match.gd)
## READ ONLY: the database is built from scenes/ and moves/; nothing is written to scenes/, poses/ or data/.
##   1 the database builds from Nick's scenes: frames > 0, every feature finite, the clip list printed
##   2 a frame's own features: the search returns that frame at cost 0 (or a frame with identical features), 12 frames
##     spread over the clips
##   3 straight ahead, trajectory alone, at walk_bat's own average forward velocity: the best walk_bat frame costs less
##     than the best frame of a strike (swing_*, strike_*, thrust, bo_*)
##   4 the same target with the pose of a strike's first frame (the full vector): reported, not barred
##   5 coverage: runs over every direction and speed, the gaps are listed, no error; 1 + 8 x speeds queries
##   6 the search over the full database: 200 queries, mean under 2 ms (bar)
##   7 the preview player, 3 s straight ahead: every output finite, walk_bat plays for most of the time (reported)
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var db := MotionMatch.build()
	print("database: %d frames in %d clips, built in %d ms" % [int(db["n"]), (db["clips"] as Array).size(), Time.get_ticks_msec() - t0])
	for c in db["clips"]:
		print("  %-14s %4d frames at %d fps" % [c["name"], c["n"], int(c["fps"])])
	# 1
	var z: PackedFloat32Array = db["z"]
	var finite := true
	for v in z:
		if is_nan(v) or is_inf(v):
			finite = false
			break
	ok(int(db["n"]) > 0 and finite and z.size() == int(db["n"]) * MotionMatch.DIM,
		"1 database: %d frames, %d-dim rows, every feature finite %s" % [int(db["n"]), MotionMatch.DIM, finite])
	# 2
	var n: int = db["n"]
	var own_ok := 0
	for k in 12:
		var g := (n - 1) * k / 11
		# the query is the frame's own normalised row (its pose and its own trajectory)
		var zq := PackedFloat32Array()
		zq.resize(MotionMatch.DIM)
		for d in MotionMatch.DIM:
			zq[d] = z[g * MotionMatch.DIM + d]
		var qc := MotionMatch.chunks(db, zq, MotionMatch.W_FULL)
		var res := MotionMatch.search(db, qc, MotionMatch.W_FULL)
		var same := int(res[0]) == g or MotionMatch.row_sq(db, qc, int(res[0]), MotionMatch.W_FULL) < 1e-12
		if same and float(res[1]) < 1e-9:
			own_ok += 1
		if k == 0:
			print("  own-feature query, frame %d: nearest %d cost %.6f" % [g, int(res[0]), sqrt(float(res[1]))])
	ok(own_ok == 12, "2 a frame's own features return that frame at cost 0: %d of 12" % own_ok)
	# 3
	var walk := -1
	var clips: Array = db["clips"]
	var clip_of: PackedInt32Array = db["clip_of"]
	for ci in clips.size():
		if clips[ci]["name"] == "walk_bat":
			walk = ci
	var vsum := Vector3.ZERO
	var nw := 0
	var raw2: PackedFloat32Array = db["raw"]
	var best_walk := INF
	var best_strike := INF
	var strike_name := ""
	var walk_speed := 0.0
	if walk >= 0:
		for g in n:
			if clip_of[g] == walk:
				vsum += Vector3(raw2[g * MotionMatch.DIM + 19], 0.0, raw2[g * MotionMatch.DIM + 20])   # the +1 s trajectory: the velocity
				nw += 1
		var vw := vsum / maxf(float(nw), 1.0)
		walk_speed = vw.length()
		var qt := MotionMatch.chunks(db, MotionMatch.query_of(db, 0, vw), MotionMatch.W_TRAJ)
		for g in n:
			var s := MotionMatch.row_sq(db, qt, g, MotionMatch.W_TRAJ)
			var cn: String = clips[clip_of[g]]["name"]
			if cn == "walk_bat":
				best_walk = minf(best_walk, s)
			elif cn.begins_with("swing") or cn.begins_with("strike") or cn.begins_with("thrust") or cn.begins_with("bo_"):
				if s < best_strike:
					best_strike = s
					strike_name = cn
		var rb := MotionMatch.search(db, qt, MotionMatch.W_TRAJ)
		print("  straight ahead %.2f m/s (walk_bat's own mean): best frame %s f%d cost %.3f; best walk %.3f, best strike %.3f (%s)" % [
			walk_speed, clips[clip_of[int(rb[0])]]["name"], int(db["frame_of"][int(rb[0])]), sqrt(float(rb[1])),
			sqrt(best_walk), sqrt(best_strike), strike_name])
	ok(walk >= 0 and best_walk < best_strike, "3 straight ahead at walk speed, trajectory alone: best walk %.3f < best strike %.3f" % [
		sqrt(best_walk), sqrt(best_strike)])
	# 4
	var strike_g := -1
	for g in n:
		if clips[clip_of[g]]["name"].begins_with("swing") and strike_g < 0:
			strike_g = g
	if strike_g >= 0 and walk >= 0:
		var qf := MotionMatch.chunks(db, MotionMatch.query_of(db, strike_g, Vector3(0.0, 0.0, walk_speed)), MotionMatch.W_FULL)
		var r4 := MotionMatch.search(db, qf, MotionMatch.W_FULL)
		print("  strike pose + straight ahead (full vector): best %s f%d cost %.3f" % [clips[clip_of[int(r4[0])]]["name"],
			int(db["frame_of"][int(r4[0])]), sqrt(float(r4[1]))])
	# 5
	var cov := MotionMatch.coverage(db)
	var rows: Array = cov["rows"]
	ok(rows.size() == 1 + 8 * MotionMatch.COVER_SPEEDS.size(), "5 coverage: %d queries (1 standing + 8 directions x %d speeds), %d gaps (cost > %.1f)" % [
		rows.size(), MotionMatch.COVER_SPEEDS.size(), (cov["gaps"] as Array).size(), MotionMatch.GOOD])
	print(cov["text"])
	# 6 (the database and its index are built above and not timed; one untimed call first so the first-call cost of the
	# script and the allocator is not read as the search's). Exactness: every query's argmin must equal a brute-force scan
	MotionMatch.search(db, MotionMatch.chunks(db, MotionMatch.query_of(db, 0, Vector3.ZERO), MotionMatch.W_FULL), MotionMatch.W_FULL)
	var tq := 0.0
	var worst_ms := 0.0
	var mism := 0
	var zf: PackedVector3Array = db["zf"]
	for k in 200:
		var g := (k * 37) % n
		var wt := MotionMatch.W_FULL if k % 4 != 3 else MotionMatch.W_TRAJ
		var qk := MotionMatch.chunks(db, MotionMatch.query_of(db, g, Vector3(0.0, 0.0, walk_speed * float(k % 3))), wt)
		var ts := Time.get_ticks_usec()
		var rk := MotionMatch.search(db, qk, wt)
		var ms := float(Time.get_ticks_usec() - ts) / 1000.0
		if wt == MotionMatch.W_FULL:
			tq += ms
			worst_ms = maxf(worst_ms, ms)
		var bf := INF
		var bfi := -1
		for i in n:
			var sq := MotionMatch.row_sq(db, qk, i, wt)
			if sq < bf:
				bf = sq
				bfi = i
		if int(rk[0]) != bfi:
			mism += 1
	var nt := 0
	for k in 200:
		if k % 4 != 3:
			nt += 1
	var mean_ms := tq / float(nt)
	ok(mean_ms < 2.0 and mism == 0, "6 search over the full database (%d frames): mean %.3f ms, worst %.3f ms (bar 2 ms); argmin differs from brute force on %d of 200 queries (bar 0)" % [n, mean_ms, worst_ms, mism])
	# 7
	var pl := MotionMatch.Player.new(db, walk if walk >= 0 else 0)
	var finite7 := true
	var walk_frames := 0
	var frames7 := 0
	var t := 0.0
	while t < 3.0:
		var out: Dictionary = pl.step(1.0 / 60.0, Vector3(0.0, 0.0, walk_speed))
		t += 1.0 / 60.0
		frames7 += 1
		if out["clip"] == "walk_bat":
			walk_frames += 1
		if is_nan(float(out["cost"])) or is_inf(float(out["cost"])):
			finite7 = false
		for v in (out["ang"] as PackedVector3Array):
			if not v.is_finite():
				finite7 = false
	ok(finite7, "7 preview 3 s straight ahead: %d of %d frames on walk_bat, %d searches, %d switches, last cost %.3f" % [
		walk_frames, frames7, pl.searches, pl.switches, pl.cost])
	print("MOTION MATCH TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
