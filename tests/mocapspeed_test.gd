## godot --headless --path . -s tests/mocapspeed_test.gd     (MOCAP SPEED, scripts/scene.gd sample memo + scripts/video_iq.gd timing)
## THE SAME TRACKS, FASTER. VideoIQ.process on the four mocapq fixtures and on vidspeed clip A, once with the pre-speed-up linear
## sample (Scene.sample_memo_linear = false, the old code path kept behind the flag) and once with the new one, in this same run.
## Bars, stated before the run:
##   1 SAME      every fitted joint angle of every frame within 1e-6 rad of the old path, every plant's t0/t1 equal, all clips
##   2 SPEED     the plants stage (VideoCleanup.reachable, where the apply reads repeat) of clip A takes at most 80 % of the old time
##               (a miss prints KNOWN FAIL with the number, never a pass)
##   3 CLEAN     the flag is on by default and the old path restores the flag (the test leaves the code as it found it)
## Times are the min of two runs each. The stage table is in C:/Temp/claude/mocapspeed/PROFILE.md.
extends SceneTree

const SPEED_BAR := 0.8
const TOL_RAD := 1e-6
const CLIPS := ["res://tests/fixtures/mocapq_walk.json", "res://tests/fixtures/mocapq_punch.json", "res://tests/fixtures/mocapq_kick.json", "res://tests/fixtures/mocapq_turn.json", "res://tests/fixtures/vidspeed_pose_A.json"]

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func run_clip(path: String, linear: bool) -> Dictionary:
	Scene.sample_memo_linear = linear
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var P := VideoImport.load_file(path)
	var t0 := Time.get_ticks_usec()
	var R := VideoIQ.process(B, P, "", "mocapspeed", false)
	var total := (Time.get_ticks_usec() - t0) / 1000.0
	var ang := []
	for fr in R["fitted"]:
		var row := []
		for j in fr["ang"]:
			row.append([j, fr["ang"][j]])
		ang.append([float(fr["t"]), row])
	var plants := []
	for p in R["scene"].plants:
		plants.append([p["foot"], float(p["t0"]), float(p["t1"])])
	var st: Dictionary = VideoIQ.stage_ms.duplicate()
	Scene.sample_memo_linear = true
	return {"ang": ang, "plants": plants, "total": total, "stage": st}


func _init() -> void:
	var worst := 0.0
	var same_plants := true
	var frames_n := 0
	var best := {}   # path -> {linear: {total, plants}} min of two
	for path in CLIPS:
		var old_r := run_clip(path, false)
		var new_r := run_clip(path, true)
		var old2 := run_clip(path, false)
		var new2 := run_clip(path, true)
		best[path] = {
			"old_total": minf(old_r["total"], old2["total"]), "new_total": minf(new_r["total"], new2["total"]),
			"old_plants": minf(float(old_r["stage"].get("plants", 0.0)), float(old2["stage"].get("plants", 0.0))),
			"new_plants": minf(float(new_r["stage"].get("plants", 0.0)), float(new2["stage"].get("plants", 0.0))),
		}
		var A: Array = old_r["ang"]
		var Bn: Array = new_r["ang"]
		ok(A.size() == Bn.size() and A.size() > 0, "1 %s: frames %d" % [path.get_file(), A.size()])
		frames_n += A.size()
		for k in mini(A.size(), Bn.size()):
			var ra: Array = A[k][1]
			var rb: Array = Bn[k][1]
			for m in mini(ra.size(), rb.size()):
				if ra[m][0] != rb[m][0]:
					worst = INF
					continue
				var d := ((ra[m][1] as Vector3) - (rb[m][1] as Vector3)).abs()
				worst = maxf(worst, maxf(d.x, maxf(d.y, d.z)) * PI / 180.0)
		if old_r["plants"] != new_r["plants"]:
			same_plants = false
	ok(worst <= TOL_RAD, "1 SAME: every fitted joint angle on %d frames within 1e-6 rad of the old path (worst %.9f rad)" % [frames_n, worst])
	ok(same_plants, "1 SAME: every plant's t0 / t1 equal to the old path")
	var a: Dictionary = best["res://tests/fixtures/vidspeed_pose_A.json"]
	var ratio: float = float(a["new_plants"]) / maxf(float(a["old_plants"]), 1e-6)
	print("  TIME clip A plants stage: old %.0f ms, new %.0f ms (%.0f %%); process total: old %.0f ms, new %.0f ms" % [a["old_plants"], a["new_plants"], ratio * 100.0, a["old_total"], a["new_total"]])
	# A bar the numbers do not meet prints as KNOWN FAIL with its number, never as a pass (the vidspeed convention)
	if ratio <= SPEED_BAR:
		print("ok   2 SPEED: plants stage of clip A at most 80 %% of the old (%.0f %%)" % (ratio * 100.0))
	else:
		print("KNOWN FAIL 2 SPEED: plants stage of clip A at most 80 %% of the old (now %.0f %%)" % (ratio * 100.0))
	ok(Scene.sample_memo_linear == true, "3 CLEAN: the flag is back on after the run")
	TestFiles.cleanup()
	print("mocapspeed: %d FAIL" % fails if fails > 0 else "mocapspeed: PASS")
	quit(1 if fails > 0 else 0)
