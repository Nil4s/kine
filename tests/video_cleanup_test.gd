## godot --headless --path . -s tests/video_cleanup_test.gd     (ROADMAP 16, phone video to clean animation)
## THE CLEANUP ON A KNOWN ANSWER, NO VIDEO. walk_bat (READ ONLY) sampled at 30 fps as MediaPipe's 33 landmarks, then made
## video-like: 1.5 cm gaussian noise per coordinate (seeded), the whole scene tilted 3 deg (a camera looking down at the floor).
## The path is the video import's: parse -> VideoCleanup.run -> VideoImport.solve -> to_scene -> thin, with the plants written.
##   1 the planted feet: the sole (ball, heel) moves <= 1 mm over each plant's range, as played
##   2 the jitter: the high-frequency turn of the bones falls >= 70 % (landmarks, deg/frame)
##   3 the peak hand speed within 10 % of the clean source's (the clean walk_bat, sampled the same way)
##   4 the floor: the tilt removed within 0.3 deg (the planted feet's plane after cleanup), and the correction found ~3 deg
##   5 the ground: the lowest planted sole within 1 cm of y = 0
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	var fps := 30.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260518
	var tilt_axis := Vector3(1.0, 0.0, 0.5).normalized()
	var R := Quaternion(tilt_axis, deg_to_rad(3.0))
	# the clean source at 30 fps: the landmarks (video layout) and the hands' world speed
	var frames := []
	var hand_clean := 0.0
	var prev_h := []
	var n := int(S.length() * fps) + 1
	for i in n:
		var t := minf(i / fps, S.length())
		S.apply(B, t)
		B.fk()
		var w := VideoImport.landmarks_of(B)
		var video := []
		for p in w:
			var q: Vector3 = p + Vector3(rng.randfn(0.0, 0.015), rng.randfn(0.0, 0.015), rng.randfn(0.0, 0.015))
			video.append(R * q)
		frames.append({"t": snappedf(t, 0.001), "world": video.map(func(p): return [p.x, -p.y, -p.z])})
		var h := [B.P["hand_r"], B.P["hand_l"]]
		if not prev_h.is_empty():
			for k in 2:
				hand_clean = maxf(hand_clean, ((h[k] as Vector3) - (prev_h[k] as Vector3)).length() * fps)
		prev_h = h
	# the clean source's peak hand speed is read from the scene as it plays, below (the same sampling for both)
	var P := VideoImport.parse(JSON.stringify({"fps": fps, "frames": frames}))
	ok(P["ok"], "0 the video-like pose file reads: %d frames" % frames.size())
	var C := VideoCleanup.run(P["frames"], fps)
	var fitted := VideoImport.solve(B, C["frames"])
	var V := VideoImport.to_scene(B, fitted, fps)
	V = VideoImport.thin(V, VideoImport.every_for(fps))
	V.plants = FootPlant.from_file(C["plants"])
	V.plants = VideoCleanup.reachable(V, B, V.plants, fps)
	print("     " + VideoCleanup.report(V.plants.size(), C["jitter_raw"], C["jitter_clean"], C["tilt"]))
	ok(V.plants.size() >= 4, "0b the plants found: %d (a walk of two feet and several steps; want >= 4)" % V.plants.size())
	# 1 the plants: the sole as played, over each plant's range, against where it stood at t0
	var slide := 0.0
	var slide_at := ""
	var soles_low := 1e9
	for p in V.plants:
		var sd: String = String(p["foot"]).right(2)
		var t0 := float(p["t0"])
		var t1 := float(p["t1"])
		# R14b: a plant with "tf" starts at a heel strike (toes still up): the sole is flat, and so held, from tf; before tf only the
		# HEEL is held, the ball is coming down onto the floor (not planted yet). The reference is the sole as held (at tf).
		var tb := maxf(t0, float(p.get("tf", t0)))
		V.apply(B, tb)
		var b0: Vector3 = B.P["ball" + sd]
		var h0: Vector3 = FootRoll.heel_point(B, sd)
		var steps := maxi(1, int(round((t1 - t0) * fps * 4.0)))
		for k in steps + 1:
			var t := t0 + (t1 - t0) * float(k) / float(steps)
			V.apply(B, t)
			var d := (FootRoll.heel_point(B, sd) - h0).length()
			if t >= tb - 1e-6:
				d = maxf(d, ((B.P["ball" + sd] as Vector3) - b0).length())
			if d > slide:
				slide = d
				slide_at = "%s %.2f s" % [p["foot"], t]
			soles_low = minf(soles_low, minf((B.P["ball" + sd] as Vector3).y, (FootRoll.heel_point(B, sd) as Vector3).y))
	ok(slide <= 0.001, "1 planted feet slide %.2f mm over the plants (bar 1 mm; worst %s)" % [slide * 1000.0, slide_at])
	# 2 the jitter: the high-frequency turn of the bones, raw against cleaned (the same landmark reading)
	var raw_frames: Array = P["frames"]
	var jr := VideoCleanup.jitter(raw_frames)
	var jc := VideoCleanup.jitter(C["frames"])
	var red := 1.0 - jc / maxf(jr, 1e-9)
	ok(red >= 0.70, "2 jitter %.2f -> %.2f deg/frame, %.0f %% less (bar 70 %%)" % [jr, jc, red * 100.0])
	# 3 the peak hand speed, as played, against the clean source's (sampled at the same 30 fps)
	var hand_out := 0.0
	var prev := []
	var S_hand := 0.0
	var prev_s := []
	for i in int(V.length() * fps) + 1:
		var t := minf(i / fps, V.length())
		V.apply(B, t)
		var h := [B.P["hand_r"], B.P["hand_l"]]
		if not prev.is_empty():
			for k in 2:
				hand_out = maxf(hand_out, ((h[k] as Vector3) - (prev[k] as Vector3)).length() * fps)
		prev = h
	for i in int(S.length() * fps) + 1:
		var t := minf(i / fps, S.length())
		S.apply(B, t)
		var h := [B.P["hand_r"], B.P["hand_l"]]
		if not prev_s.is_empty():
			for k in 2:
				S_hand = maxf(S_hand, ((h[k] as Vector3) - (prev_s[k] as Vector3)).length() * fps)
		prev_s = h
	var hand_err := absf(hand_out - S_hand) / maxf(S_hand, 1e-6)
	ok(hand_err <= 0.10, "3 peak hand speed %.2f m/s, clean source %.2f m/s, %.1f %% off (bar 10 %%)" % [hand_out, S_hand, hand_err * 100.0])
	# 4 the floor: the planted feet's plane after cleanup, against level
	var resid := rad_to_deg(VideoCleanup.plane_normal(VideoCleanup.planted_points(C["frames"], C["plants"])).angle_to(Vector3.UP))
	ok(resid <= 0.3 and absf(float(C["tilt"]) - 3.0) <= 1.0, "4 floor tilt: %.2f deg corrected (the injected 3 deg), %.2f deg left (bar 0.3)" % [C["tilt"], resid])
	# 5 the ground: the lowest planted sole as played
	ok(absf(soles_low) <= 0.01, "5 lowest planted sole %.4f m from the floor (bar 0.01)" % soles_low)
	print("VIDEO CLEANUP TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
