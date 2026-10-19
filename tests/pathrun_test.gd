## godot --headless --path . -s tests/pathrun_test.gd     (ROADMAP 92c; a window for the picture is not needed)
## PathRun.build(): run cards along a 20 m straight path at 3.5 m/s. Bars, stated before measuring:
##   1 cadence 171 steps/min within 2 SD of people (Fukuchi 2017 PeerJ 5:e3298 Table 4: 85.68 +- 5.27 strides/min -> 160.4-181.6)
##   2 FLIGHT: every stride has a phase with both feet off the floor: flights == steps - 1, each 40-130 ms
##   3 stance share of the stride 33-43 % (Tsai 2008 at 3.5 m/s: 38.34 %)
##   4 a standing foot slides < 5 mm on its mark, every frame (walk_legs_test's bar)
##   5 peak knee flexion in the swing 87.4-130 deg (Fukuchi 2017: 108.68 +- 10.65, 2 SD)
##   6 the speed outside 3.0-4.0 and a 1 m bend are refused with a next step
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var pts := [Vector3(0, 0, 0), Vector3(0, 0, 20.0)]
	var r := PathRun.build(pts, 3.5)
	if not r["ok"]:
		print("FAIL did not build: ", r["why"])
		quit(1)
		return
	var S := Scene.new()
	S.from_dict(r["scene"])
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var cad: float = r["cadence"]
	ok(cad >= 160.4 and cad <= 181.6, "1 cadence %.1f steps/min (people 171.4 +- 10.5)" % cad)
	var n: int = r["steps"]
	var fl := S.flights()
	var good := 0
	var fmin := 9.0
	var fmax := 0.0
	for f in fl:
		var d: float = float(f["t1"]) - float(f["t0"])
		fmin = minf(fmin, d)
		fmax = maxf(fmax, d)
		if d >= 0.04 and d <= 0.13:
			good += 1
	ok(fl.size() == n - 1 and good == fl.size(), "2 flights %d for %d steps (bar steps-1), each %.0f-%.0f ms (bar 40-130)" % [fl.size(), n, fmin * 1000.0, fmax * 1000.0])
	# 3-5 at 120 Hz over the running part
	var ts := S.times()
	var t0: float = ts[2][0]
	var t1: float = ts[-2][1]
	var fps := 120.0
	var down := {"_l": 0, "_r": 0}
	var frames := 0
	var mark := {}
	var prev := {}
	var worst := 0.0
	var kmax := 0.0
	for k in int((t1 - t0) * fps) + 1:
		S.apply(B, t0 + k / fps)
		frames += 1
		for sd in ["_l", "_r"]:
			var ball: Vector3 = B.P["ball" + sd]
			var is_down := ball.y < 0.022
			if is_down:
				down[sd] += 1
			var slow: bool = prev.has(sd) and Vector2(ball.x - prev[sd].x, ball.z - prev[sd].z).length() * fps < 0.2
			if is_down and slow:
				if not mark.has(sd):
					mark[sd] = ball
				worst = maxf(worst, Vector2(ball.x - mark[sd].x, ball.z - mark[sd].z).length())
			elif not is_down:
				mark.erase(sd)
				kmax = maxf(kmax, float(B.ang["calf" + sd].x))
			prev[sd] = ball
	var share := 100.0 * float(down["_l"] + down["_r"]) / (2.0 * frames) * 2.0   # per foot, as a share of the stride: one foot's frames / stride frames = ... (two feet's mean)
	share = 100.0 * float(down["_l"] + down["_r"]) / (2.0 * frames)
	ok(share >= 33.0 and share <= 43.0, "3 stance share of the stride %.1f %% (Tsai 2008: 38.3; bar 33-43)" % share)
	ok(worst < 0.005, "4 a standing foot slides %.2f mm (bar < 5)" % (worst * 1000.0))
	ok(kmax >= 87.4 and kmax <= 130.0, "5 swing knee peak %.1f deg (Fukuchi 2017 108.7 +- 10.7; bar 87.4-130)" % kmax)
	var bad := PathRun.build(pts, 5.0)
	var bend := []
	for i in 11:
		bend.append(Vector3(0, 0, 3.0 * i / 10.0))
	for i in range(1, 12):
		var phi := (PI / 2.0) * i / 11.0
		bend.append(Vector3(1.0 - cos(phi), 0, 3.0 + sin(phi)))
	for i in range(1, 12):
		bend.append(Vector3(1.0 + 3.0 * i / 11.0, 0, 4.0))
	var bad2 := PathRun.build(bend, 3.5)
	ok(not bad["ok"] and not bad2["ok"] and String(bad2["why"]).contains("Widen"), "6 refusals: '%s' / '%s'" % [bad["why"], bad2.get("why", "built")])
	print("PATH RUN TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
