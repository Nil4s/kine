## godot --headless --path . -s tests/video_import_test.gd     (round 45, GATES AA0)
## VIDEO TO ANIMATION, ON A KNOWN ANSWER. walk_bat's 33 landmarks written exactly as tools/export_landmarks.gd writes
## them (MediaPipe's layout and axes, the hips at 0: no travel), read back by VideoImport and fitted:
##   1 the pose: every landmark of the fitted body within 1.5 cm of the original on average, 4 cm at worst
##   2 the knees and elbows: the hinge bend within 2 deg of the original on average
##   3 the travel: MediaPipe's hips never move; the rebuilt walk travels within 5 % of walk_bat's own distance
##   4 the floor: the lower sole within 1 cm of the floor in every frame
##   5 the scene: one card per frame plays the fitted angles back (0.01 deg) at the frame times
##   6 a bad file is refused with a sentence, never a crash
##   7 a 16 fps clip: the tracker writes fps 16, no frame is invented, the scene plays the clip's length (within 1 frame)
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## 10 A FLIGHT READ ON AN UNSEEN HIP (round 58, the cmb02_cross clip of the kine batch: its hip image sat at the frame's top edge with
## visibility 0.5 and its ankles at 0.05 in raw frame 49, so the flight detector read a 0.3 m rise and lifted the whole pelvis for two
## frames, a 19.6 m/s hand peak with it). tests/data/spike_cross_pose.json (kine batch combat/cmb02_cross, 2.7-4.0 s; 138 KB). Bar:
##   c the cross clip's peak hand speed is 20 m/s or less (old 48.6; the torso filter gives 16.4)
##   b the keeper (tests/fixtures/gen_hammer_pose.json) keeps its peak hand speed within 10 % (base 1.84 m/s)
##   a the largest pelvis step between frames in 3.05-3.13 s is 0.05 m or less (old: a flight read lifted the pelvis at 3.07-3.08 s)
func _bar10_spike_pelvis() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var P := VideoImport.load_file("res://tests/data/spike_cross_pose.json")
	ok(P["ok"], "10 the cross-punch spike file reads (%s)" % P.get("why", ""))
	if not P["ok"]:
		return
	var keep := B.state()
	var R := VideoIQ.process(B, P, "", "spike_test", true)
	B.set_state(keep)
	var fit: Array = R["fitted"]
	var step := 0.0
	var step_at := 0.0
	for i in range(1, fit.size()):
		var t := float(R["frames"][i]["t"])   # the fitted frame's own time (the tracker's clock, after the fill)
		if t < 3.05 or t > 3.13:
			continue
		var d := absf(float(fit[i]["offset"].y) - float(fit[i - 1]["offset"].y))
		if d > step:
			step = d
			step_at = t
	# b the keeper: a clip with no glitch keeps its hand speed (tests/fixtures/gen_hammer_pose.json, peak 1.84 m/s on base; the
	# fast-move keeper cmb01_jab is not in the repo). Within 10 % of the old peak
	var K := VideoImport.load_file("res://tests/fixtures/gen_hammer_pose.json")
	if K["ok"]:
		var B3 := Body.new()
		B3.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		var keep3 := B3.state()
		var RK := VideoIQ.process(B3, K, "", "keeper_test", true)
		B3.set_state(keep3)
		var B4 := Body.new()
		B4.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		var smk := Rulebook.sample(RK["scene"], B4)
		var pk := 0.0
		for hk in ["hand_l", "hand_r"]:
			for x in smk[hk]:
				pk = maxf(pk, float(x))
		ok(absf(pk - 1.84) <= 0.184, "10b the keeper's peak hand speed is %.2f m/s (base 1.84; bar within 10 %%)" % pk)
	# c the fitted hand peak of the cross clip (old 48.6 m/s at 2.97 s, the left shoulder's one-frame jump at 3.00 s; the torso filter
	# brings it to 16.4): bar 20. The 12 m/s fist bar is not reached yet (the shoulder steps 0.24 m at 3.00 s and stays low)
	var B5 := Body.new()
	B5.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var smc := Rulebook.sample(R["scene"], B5)
	var pkc := 0.0
	for hk in ["hand_l", "hand_r"]:
		for x in smc[hk]:
			pkc = maxf(pkc, float(x))
	ok(pkc <= 20.0, "10c the cross clip's peak hand speed is %.1f m/s (old 48.6; bar 20, the fist bar 12 is not reached)" % pkc)
	ok(step <= 0.05, "10a the largest pelvis step in 3.05-3.13 s is %.3f m at %.3f s (bar 0.05; old code 1.22 m at 3.125 s)" % [step, step_at])


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/walk_bat.json")))
	var fps := 30.0
	var orig := []
	var frames := []
	for i in int(S.length() * fps) + 1:
		var t := minf(i / fps, S.length())
		S.apply(B, t)
		B.fk()
		var w := VideoImport.landmarks_of(B)
		var ang := {}
		for j in Body.BODY:
			ang[j] = B.ang[j]
		orig.append({"w": w, "pel": B.P["pelvis"], "ang": ang, "knee": [B.ang["calf_l"], B.ang["calf_r"], B.ang["lowerarm_l"], B.ang["lowerarm_r"]]})
		frames.append({"t": snappedf(t, 0.001), "world": w.map(func(p): return [p.x, -p.y, -p.z])})
	var P := VideoImport.parse(JSON.stringify({"fps": fps, "frames": frames}))
	ok(P["ok"] and P["frames"].size() == frames.size(), "0 the pose file reads: %d frames" % P.get("frames", []).size())
	var fitted := VideoImport.solve(B, P["frames"])
	# 1, 2 the pose
	var sum := 0.0
	var n := 0
	var worst := 0.0
	var worst_at := ""
	var hsum := 0.0
	var hn := 0
	for i in fitted.size():
		for j in fitted[i]["ang"]:
			B.ang[j] = fitted[i]["ang"][j]
		B.offset = fitted[i]["offset"]
		B.fk()
		var w := VideoImport.landmarks_of(B)
		for k in VideoImport.MAP:
			var d: float = (w[k] as Vector3).distance_to(orig[i]["w"][k])
			sum += d
			n += 1
			if d > worst:
				worst = d
				worst_at = "frame %d landmark %d (%s)" % [i, k, VideoImport.MAP[k][0]]
		for m in 4:
			var jn: String = ["calf_l", "calf_r", "lowerarm_l", "lowerarm_r"][m]
			hsum += absf(absf((B.ang[jn] as Vector3).x) - absf((orig[i]["knee"][m] as Vector3).x))
			hn += 1
	var mean := sum / maxf(1, n)
	ok(mean <= 0.015 and worst <= 0.04, "1 the fitted body's landmarks %.2f cm from the original on average, %.2f at worst (%s) (bar 1.5, 4)" % [mean * 100.0, worst * 100.0, worst_at])
	ok(hsum / maxf(1, hn) <= 2.0, "2 the knees' and elbows' bend %.2f deg from the original on average (bar 2)" % (hsum / maxf(1, hn)))
	# 3 the travel
	var o0: Vector3 = orig[0]["pel"]
	var o1: Vector3 = orig[-1]["pel"]
	var dist := Vector2(o1.x - o0.x, o1.z - o0.z).length()
	var f0: Vector3 = fitted[0]["offset"]
	var f1: Vector3 = fitted[-1]["offset"]
	var got := Vector2(f1.x - f0.x, f1.z - f0.z).length()
	ok(dist > 1.0 and absf(got - dist) <= 0.05 * dist, "3 the rebuilt walk travels %.3f m, walk_bat %.3f m (bar within 5 %%; the pose file's hips never move)" % [got, dist])
	# 4 the floor
	var fl := 0.0
	for i in fitted.size():
		for j in fitted[i]["ang"]:
			B.ang[j] = fitted[i]["ang"][j]
		B.offset = fitted[i]["offset"]
		B.fk()
		fl = maxf(fl, absf(B.sole_low()))
	ok(fl <= 0.01, "4 the lower sole's worst distance from the floor %.4f m (bar 0.01)" % fl)
	# 5 the scene
	var V := VideoImport.to_scene(B, fitted, fps)
	var sw := 0.0
	var sw_at := ""
	var vt := V.times()
	for i in fitted.size():
		V.apply(B, float(vt[i][1]))   # the card's own time (the frame times summed as moves)
		for j in fitted[i]["ang"]:
			# the angle numbers themselves (Quaternion.angle_to is acos of a dot near 1: float32 floors it at ~0.07 deg for
			# the SAME rotation, measured here on identical angles, the round 41 finding)
			var dv: Vector3 = (B.ang[j] as Vector3) - (fitted[i]["ang"][j] as Vector3)
			var dd := maxf(absf(dv.x), maxf(absf(dv.y), absf(dv.z)))
			if dd > sw:
				sw = dd
				sw_at = "card %d %s %s vs %s" % [i, j, B.ang[j], fitted[i]["ang"][j]]
	ok(V.cards.size() == fitted.size() and sw <= 0.01, "5 one card per frame (%d) plays the fit back: worst %.4f deg (bar 0.01) %s" % [V.cards.size(), sw, sw_at])
	# 6 refusals
	var r1 := VideoImport.parse("{}")
	var r2 := VideoImport.parse("not json")
	var r3 := VideoImport.parse(JSON.stringify({"frames": [frames[0]]}))
	ok(not r1["ok"] and not r2["ok"] and not r3["ok"] and String(r3["why"]).length() > 10, "6 bad files refused: %s | %s | %s" % [r1["why"], r2["why"], r3["why"]])
	_bar7_fps16()
	_bar8_flight()
	_bar9_lost_foot()
	_bar10_spike_pelvis()
	print("VIDEO IMPORT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


## 7 A 16 FPS CLIP (round 45 fps fix): tests/fixtures/fps16_hammer_2s.webm is 2 s at 16 fps (32 frames). tools/see_video.py must
## write fps 16 (it wrote 30, the sampling target, and the importer's filters and gap fill ran on a 30 fps clock: a fake frame
## between every two real ones). Bars: the file's fps is 16 and its frames are 1/16 s apart; the fit keeps the 32 frames (none
## invented); the scene's length is the clip's 2.0 s within one frame (1/16 s) and its fps is 16.
func _bar7_fps16() -> void:
	var out := ProjectSettings.globalize_path("user://fps16_pose.json")
	if FileAccess.file_exists("user://fps16_pose.json"):
		DirAccess.remove_absolute(out)
	var log := []
	var code := OS.execute("python", PackedStringArray([ProjectSettings.globalize_path("res://tools/see_video.py"),
		ProjectSettings.globalize_path("res://tests/fixtures/fps16_hammer_2s.webm"), out]), log, true)
	ok(code == 0 and FileAccess.file_exists("user://fps16_pose.json"), "7 the tracker runs on the 16 fps fixture (exit %d, %s)" % [code, String(log[0]).strip_edges().left(60) if log.size() > 0 else "no output"])
	if not FileAccess.file_exists("user://fps16_pose.json"):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string("user://fps16_pose.json"))
	var nf: int = (d["frames"] as Array).size()
	var t_last := float(d["frames"][nf - 1]["t"])
	ok(absf(float(d["fps"]) - 16.0) < 0.01 and absf(t_last - float(nf - 1) / 16.0) < 0.002,
		"7 the pose file says fps %.2f (bar 16) and its %d frames span %.4f s (16 fps: %.4f)" % [float(d["fps"]), nf, t_last, float(nf - 1) / 16.0])
	var P := VideoImport.load_file("user://fps16_pose.json")
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var R := VideoIQ.process(B, P, "", "fps16", false)
	var V: Scene = R["scene"]
	ok(R["frames"].size() == nf, "7 the fit keeps every tracked frame: %d in, %d out (bar: none invented)" % [nf, R["frames"].size()])
	ok(V.fps == 16 and absf(V.length() - 2.0) <= 1.0 / 16.0 + 1e-6,
		"7 the scene plays %.4f s at %d fps (bar: the clip's 2.0 s within 1/16 s, fps 16)" % [V.length(), V.fps])


## 8 A JUMP IN THE AIR (round 56; the hurdles clip's trail foot was "planted" in its clearance and the body was pinned to the floor).
## tests/data/flight_jump_pose.json, 2 s at 60 fps, made by a script (not in the repo): run, a 0.4 s jump with the whole body 22 cm
## up (its image hip and ankle heights carry the rise, the tracker's hips-relative landmarks do not), run again. Bars:
##   a no foot contact overlaps the jump's middle (0.9-1.1 s: the flight)
##   b the pelvis peaks at least 0.12 m above its standing height in the jump (the old body never left the floor: 0)
##   c no frame's pelvis height steps more than 3 cm (the landing eases in, the take-off is the tracker's rise)
func _bar8_flight() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var P := VideoImport.load_file("res://tests/data/flight_jump_pose.json")
	ok(P["ok"], "8 the synthetic jump file reads (%s)" % P.get("why", ""))
	if not P["ok"]:
		return
	var keep := B.state()
	var R := VideoIQ.process(B, P, "", "flight_test", false)
	B.set_state(keep)
	var fit: Array = R["fitted"]
	var clash := []
	for c in R["iq"]["contacts"]:
		if float(c["t1"]) > 0.9 and float(c["t0"]) < 1.1:
			clash.append("%s %.2f-%.2f" % [c["part"], float(c["t0"]), float(c["t1"])])
	ok(clash.is_empty(), "8a no foot contact in the air at 0.9-1.1 s: %s (bar none)" % (str(clash) if not clash.is_empty() else "none"))
	var stand := float(fit[int(0.78 * 60.0)]["offset"].y)
	var peak := -INF
	var step := 0.0
	var step_at := 0
	for i in fit.size():
		var t := float(P["frames"][i]["t"])
		if t >= 0.8 and t <= 1.2:
			peak = maxf(peak, float(fit[i]["offset"].y))
		if i > 0:
			var d := absf(float(fit[i]["offset"].y) - float(fit[i - 1]["offset"].y))
			if d > step:
				step = d
				step_at = i
	ok(peak - stand >= 0.12, "8b the pelvis peaks %.3f m above its standing height in the jump (bar 0.12)" % (peak - stand))
	ok(step <= 0.03, "8c the largest pelvis step between frames is %.3f m at frame %d (bar 0.03)" % [step, step_at])


## 9 A LOST FOOT IS NOT PLANTED (round 57; an AI walk where the person walks out of shot: 20 frames, the left foot under the
## tracker's LOST confidence in most of them). Its landmarks are the repair's fill, which reads low and still, and the old
## contacts planted that foot for the whole 1.19 s clip while the body walked away (93 cm of slide). Bars:
##   a no left-foot contact lasts 0.6 s or more (old: one 0.00-1.19 s contact)
##   b contacts() with a foot marked unseen in every frame gives that foot no contact at all
func _bar9_lost_foot() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var P := VideoImport.load_file("res://tests/data/lost_foot_walk_pose.json")
	ok(P["ok"], "9 the lost-foot walk file reads (%s)" % P.get("why", ""))
	if not P["ok"]:
		return
	var keep := B.state()
	var R := VideoIQ.process(B, P, "", "lost_foot_test", true)
	B.set_state(keep)
	var longest := 0.0
	for c in R["iq"]["contacts"]:
		if c["part"] == "foot_l":
			longest = maxf(longest, float(c["t1"]) - float(c["t0"]))
	ok(longest < 0.6, "9a the left foot (lost in most frames) has no contact of 0.6 s or more: longest %.2f s (old 1.19)" % longest)
	var fr: Array = R["frames"]
	var none := {"_l": [], "_r": []}
	for i in fr.size():
		none["_l"].append(false)
		none["_r"].append(true)
	var K := VideoIQ.contacts(fr, float(P["fps"]), {}, none)
	var left := (K["list"] as Array).filter(func(c): return c["part"] == "foot_l")
	ok(left.is_empty(), "9b a foot unseen in every frame gets no contact (%d)" % left.size())
