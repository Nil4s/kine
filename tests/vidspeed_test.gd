## godot --headless --path . -s tests/vidspeed_test.gd     (VIDEO SPEED, scripts/video_iq.gd + scripts/scene.gd)
## THE SAME ANSWER, FASTER. tests/fixtures/vidspeed_pose_A.json is tools/see_video.py's pose file for gen_hammer.webm (5 s, 81 frames);
## vidspeed_golden_A.json holds the fitted angles that the pre-speed-up code gave for it (every 4th frame, from w4-integ).
## The bars, stated before they were measured:
##   1 SAME      every fitted joint angle of VideoIQ.process within 0.01 deg of the golden (41 frames x 30 joints)
##   2 SCENE     Scene.flights() is [] on a scene with no air card, and Scene._where_memo returns exactly Scene._where at 500 times
##   3 SPEED     VideoIQ.process on clip A takes at most 70 % of the pre-speed-up time, 14.4 s (min of two runs of
##               tests/_vidspeed_prof.gd on this PC, 2026-10-23). The whole pipeline also includes see_video.py (about 20 s on
##               the same clip), which this test does not time. A bar the numbers do not meet prints as KNOWN FAIL with its
##               number, never as a pass.
extends SceneTree

const BASE_PROCESS_S := 14.4
const SPEED_BAR := 0.7

var fails := 0
var known := []


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func kf(c: bool, what: String) -> void:
	if c:
		print("ok   (KNOWN FAIL now passes) " + what)
	else:
		print("KNOWN FAIL " + what)
		known.append(what)


func _init() -> void:
	var P := VideoImport.load_file("res://tests/fixtures/vidspeed_pose_A.json")
	ok(P["ok"], "0 the pose file reads: %d frames" % P.get("frames", []).size())
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var t0 := Time.get_ticks_usec()
	var R := VideoIQ.process(B, P, "", "vidspeed", true)
	var secs: float = (Time.get_ticks_usec() - t0) / 1e6
	ok(not R.is_empty(), "1 the import runs (%s)" % R.get("text", ""))
	# 1 SAME
	var gold: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/vidspeed_golden_A.json"))
	var fitted: Array = R["fitted"]
	var worst := 0.0
	var where := ""
	var n := 0
	for g in gold["frames"]:
		var i := -1
		for k in fitted.size():
			if absf(float(fitted[k]["t"]) - float(g["t"])) < 1e-6:
				i = k
				break
		if i < 0:
			worst = INF
			where = "frame t=%s missing" % g["t"]
			break
		for j in g["ang"]:
			var a: Vector3 = str_to_var("Vector3" + String(g["ang"][j]))
			var b: Vector3 = fitted[i]["ang"][j]
			n += 1
			var d: float = maxf(absf(a.x - b.x), maxf(absf(a.y - b.y), absf(a.z - b.z)))
			if d > worst:
				worst = d
				where = "t=%s %s" % [g["t"], j]
	print("     worst joint angle difference %.5f deg over %d angles (%s)" % [worst, n, where])
	ok(n > 1000 and worst < 0.01, "2 SAME: every fitted angle within 0.01 deg of the golden (worst %.5f)" % worst)
	# 2 SCENE
	var V := Scene.new()
	V.cards = []
	for k in 3:
		V.cards.append({"pose": {"ang": {}, "offset": Vector3.ZERO, "weapon": {}}, "move": 0.2, "hold": 0.1})
	ok(V.flights().is_empty(), "3a a scene with no air card has no flights")
	var dense: Scene = R["scene"]
	var T := float(dense.times()[-1][2])
	var same := true
	var wc := {}
	for i in 500:
		var tt := T * i / 499.0
		var b: Array = dense._where(tt, dense.times())
		var c: Array = dense._where_memo(tt, dense.times(), wc)
		if b != c:
			same = false
			break
	ok(same, "3b _where_memo equals _where at 500 times on the fitted scene")
	# 3c REACH CALLS: VideoCleanup.reachable made 4022 Scene.apply calls on clip A before the shared-pose memo (measured on w4-reach
	# HEAD, 2026-10-25); the bar is 60 % of that. Its number is printed with it, KNOWN FAIL until it is met
	const OLD_REACH_APPLIES := 4022
	var n_reach := VideoIQ.reach_applies
	print("     reachable made %d Scene.apply calls (old count %d, bar %d)" % [n_reach, OLD_REACH_APPLIES, int(OLD_REACH_APPLIES * 0.6)])
	kf(n_reach <= int(OLD_REACH_APPLIES * 0.6), "3c reachable on clip A calls Scene.apply at most %d times (60 %% of %d): %d" % [int(OLD_REACH_APPLIES * 0.6), OLD_REACH_APPLIES, n_reach])
	# 3 SPEED (a bar the numbers may not meet: KNOWN FAIL with its number)
	print("     process %.2f s on this run (pre-speed-up %.1f s)" % [secs, BASE_PROCESS_S])
	kf(secs <= BASE_PROCESS_S * SPEED_BAR, "3 SPEED: process %.2f s <= %.1f s (70 %% of %.1f s)" % [secs, BASE_PROCESS_S * SPEED_BAR, BASE_PROCESS_S])
	print("")
	print("%d FAIL, %d KNOWN FAIL" % [fails, known.size()])
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
