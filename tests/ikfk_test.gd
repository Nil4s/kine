## godot --headless --path . -s tests/ikfk_test.gd     (ROADMAP 62: IK/FK match at this frame, no pop; scripts/limb_ik.gd to_fk / to_ik)
## Bars, written before measuring. combo3, the right arm (hand_r) and the left leg (foot_l), 3 frames each (the middle of
## cards 4, 7 and 11, snapped to a frame), both directions:
##   1 NO POP AT THE SWITCH: the limb's world pose at the switch frame, read just before the command and just after:
##     the tip (wrist / ankle) within 0.1 mm, every joint of the chain within 0.05 deg (largest of bend / side / twist).
##     FK -> IK: the limb in FK; IK -> FK: the limb pinned at card 1 (LimbIK.pin) and in IK at the switch frame.
##   2 CONTINUITY: the tip's per-frame step in the 4 frames either side of the switch. The switch adds no spike: its
##     step i of the window exceeds the motion's own step i (no switch: FK for FK -> IK; the pinned scene up to the switch frame
##     and the FK scene after it for IK -> FK) by no more than the scene's p95 tip step (an excess over the motion's own, in
##     the motion's own units), AND the step INTO the switch frame (f-1 -> f) is <= 0.1 mm + the no-switch
##     step there. The scene's own p95 tip step (FK, every frame) is printed beside it, as the motion's own scale.
##   3 BLEND KEYED: FK -> IK leaves the blend 1 at the frame and 0 a frame earlier; IK -> FK leaves it 0 at the frame
##     and 1 a frame earlier. ANTI-VACUITY: a NAIVE switch (blend keyed with no matching: the old target / pole) pops
##     the tip by more than 1 cm at the same frame, so the measure can see a pop.
##   4 MIRROR: the scene after the switches, mirrored (Scene.mirror_file) and played: the twin limb's tip is the
##     reflection (x negated) within 0.5 mm on every frame of the window (cards store 0.01 deg).
##   5 SAVE ROUND TRIP: to_dict -> JSON text -> from_dict: the tip within 0.5 mm and every joint within 0.1 deg of the
##     in-memory scene on every frame of the window (the file rounds angles to 0.01 deg, points to 0.1 mm).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func load_scene(path: String) -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	return S


func pose_at(S: Scene, B: Body, tip: String, t: float) -> Dictionary:
	S.apply(B, t)
	var ang := {}
	for j in LimbIK.chain(B, tip):
		ang[j] = B.ang[j]
	return {"tip": B.P[tip], "ang": ang}


func ang_diff(a: Dictionary, b: Dictionary) -> float:
	var w := 0.0
	for j in a["ang"]:
		var d: Vector3 = ((a["ang"][j] as Vector3) - (b["ang"][j] as Vector3)).abs()
		w = maxf(w, d[d.max_axis_index()])
	return w


## the tip's step f-1 -> f for each frame f in lo..hi
func steps(S: Scene, B: Body, tip: String, f0: int, lo: int, hi: int) -> Array:
	var out := []
	var prev: Vector3 = pose_at(S, B, tip, float(f0 + lo - 1) / S.fps)["tip"]
	for f in range(f0 + lo, f0 + hi + 1):
		var p: Vector3 = pose_at(S, B, tip, float(f) / S.fps)["tip"]
		out.append((p - prev).length())
		prev = p
	return out


func mx(a: Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, float(v))
	return m


func p95_step(S: Scene, B: Body, tip: String) -> float:
	var n := int(S.length() * S.fps)
	var st := steps(S, B, tip, 0, 1, n)
	st.sort()
	return float(st[int(st.size() * 0.95)])


func _init() -> void:
	var B := body()
	var M := body()
	var path := "res://scenes/combo3.json"
	var base := load_scene(path)
	var fps := base.fps
	var ts := base.times()
	var frames := []
	for ci in [3, 6, 10]:
		var mid: float = (float(ts[ci][1]) + float(ts[ci][2])) * 0.5
		frames.append(int(round(mid * fps)))
	print("combo3: %d cards, %.2f s, %d fps; switch frames %s" % [base.cards.size(), base.length(), fps, frames])
	var worst := {"tip": 0.0, "ang": 0.0, "spike": -INF, "into": -INF, "rt_tip": 0.0, "rt_ang": 0.0, "mir": 0.0, "naive": INF}
	var blend_ok := true
	var n_cases := 0
	for tip in ["hand_r", "foot_l"]:
		var p95 := p95_step(base, B, tip)
		for dir in ["fk2ik", "ik2fk"]:
			for f in frames:
				n_cases += 1
				var t := float(f) / fps
				var S := load_scene(path)
				# the no-switch reference: FK for fk2ik; the limb pinned at card 1 for ik2fk
				var ref := load_scene(path)
				if dir == "ik2fk":
					for X in [S, ref]:
						var t0 := (float(ts[0][1]) + float(ts[0][2])) * 0.5
						X.apply(B, t0)
						LimbIK.pin(X, B, tip, t0)
				var before := pose_at(S, B, tip, t)
				var ref_st := steps(ref, B, tip, f, -4, 4)
				if dir == "ik2fk":   # the motion's own: pinned up to the switch frame, the FK scene after it
					var fk_st := steps(base, B, tip, f, -4, 4)
					for q in range(5, 9):
						ref_st[q] = fk_st[q]
				var r: Dictionary
				if dir == "fk2ik":
					r = LimbIK.to_ik(S, B, tip, t)
				else:
					r = LimbIK.to_fk(S, B, tip, t)
					if not r["ok"]:
						ok(false, "%s %s f%d: to_fk refused (%s)" % [tip, dir, f, r.get("why", "?")])
						continue
				var after := pose_at(S, B, tip, t)
				var dtip := ((after["tip"] as Vector3) - (before["tip"] as Vector3)).length()
				var dang := ang_diff(before, after)
				worst["tip"] = maxf(worst["tip"], dtip)
				worst["ang"] = maxf(worst["ang"], dang)
				var st := steps(S, B, tip, f, -4, 4)
				var ex := 0.0
				for q in st.size():
					ex = maxf(ex, float(st[q]) - float(ref_st[q]))
				worst["spike"] = maxf(worst["spike"], ex - p95)
				worst["into"] = maxf(worst["into"], float(st[4]) - float(ref_st[4]))   # index 4 = the step f-1 -> f
				print("  %s %s f%d: tip moved %.4f mm, joints %.4f deg, window max step %.2f mm (the motion's own %.2f), largest excess over it %.2f mm, p95 %.2f mm" % [tip, dir, f, dtip * 1000.0, dang, mx(st) * 1000.0, mx(ref_st) * 1000.0, ex * 1000.0, p95 * 1000.0])
				# 3 the blend keys
				var ks: Array = S.ik[tip]
				var w1 := LimbIK.weight_at(ks, t)
				var w0 := LimbIK.weight_at(ks, t - 1.0 / fps)
				if dir == "fk2ik":
					blend_ok = blend_ok and absf(w1 - 1.0) < 1e-6 and absf(w0) < 1e-6
				else:
					blend_ok = blend_ok and absf(w1) < 1e-6 and absf(w0 - 1.0) < 1e-6
				# anti-vacuity: the naive switch pops
				if dir == "fk2ik":
					var N := load_scene(path)
					N.apply(B, 0.0)
					var other := LimbIK.pin(N, B, tip, 0.0)   # an IK target from elsewhere (pose at 0)
					N.ik.erase(tip)
					LimbIK.put(N.ik, tip, {"t": t, "target": other["target"], "pole": other["pole"], "w": 1.0})
					var np := pose_at(N, B, tip, t)
					worst["naive"] = minf(worst["naive"], ((np["tip"] as Vector3) - (before["tip"] as Vector3)).length())
				# 5 save round trip
				var d: Dictionary = JSON.parse_string(JSON.stringify(S.to_dict(B)))
				var R := Scene.new()
				R.from_dict(d)
				var rt_tip := 0.0
				var rt_ang := 0.0
				for g in range(f - 4, f + 5):
					var a := pose_at(S, B, tip, float(g) / fps)
					var b := pose_at(R, B, tip, float(g) / fps)
					rt_tip = maxf(rt_tip, ((a["tip"] as Vector3) - (b["tip"] as Vector3)).length())
					rt_ang = maxf(rt_ang, ang_diff(a, b))
				worst["rt_tip"] = maxf(worst["rt_tip"], rt_tip)
				worst["rt_ang"] = maxf(worst["rt_ang"], rt_ang)
				# 4 mirror
				var Sm := Scene.new()
				Sm.from_dict(Scene.mirror_file(JSON.parse_string(JSON.stringify(S.to_dict(B))), M))
				var twin := Body.twin(tip)
				var mir := 0.0
				for g in range(f - 4, f + 5):
					var a := pose_at(S, B, tip, float(g) / fps)
					var b := pose_at(Sm, B, twin, float(g) / fps)
					var pa: Vector3 = a["tip"]
					var pb: Vector3 = b["tip"]
					mir = maxf(mir, (Vector3(-pa.x, pa.y, pa.z) - pb).length())
				worst["mir"] = maxf(worst["mir"], mir)
				print("    mirror %.3f mm, round trip %.3f mm / %.4f deg" % [mir * 1000.0, rt_tip * 1000.0, rt_ang])
	print("%d cases (2 limbs x 2 directions x 3 frames)" % n_cases)
	print("worst: tip %.4f mm, joints %.4f deg, extra window step %.3f mm, extra step into switch %.3f mm" % [worst["tip"] * 1000.0, worst["ang"], worst["spike"] * 1000.0, worst["into"] * 1000.0])
	print("round trip: tip %.3f mm, joints %.4f deg; mirror: %.3f mm; naive switch pops %.1f mm at best" % [worst["rt_tip"] * 1000.0, worst["rt_ang"], worst["mir"] * 1000.0, worst["naive"] * 1000.0])
	ok(n_cases == 12, "12 cases ran")
	ok(worst["tip"] <= 0.0001, "1 tip pose equal across the switch within 0.1 mm")
	ok(worst["ang"] <= 0.05, "1 joints equal across the switch within 0.05 deg")
	ok(worst["spike"] <= 0.0, "2 no spike: no step in the window exceeds the motion's own (pinned before the switch, FK after) by more than the scene's p95")
	ok(worst["into"] <= 0.0001, "2 the step into the switch frame no more than the no-switch step + 0.1 mm")
	ok(blend_ok, "3 the blend keyed 1/0 (FK -> IK) and 0/1 (IK -> FK) at the frame / a frame earlier")
	ok(worst["naive"] > 0.01, "3 anti-vacuity: a naive switch pops > 1 cm")
	ok(worst["mir"] <= 0.0005, "4 mirror: the twin limb is the reflection within 0.5 mm")
	ok(worst["rt_tip"] <= 0.0005 and worst["rt_ang"] <= 0.1, "5 save round trip within 0.5 mm / 0.1 deg")
	print("ikfk_test: %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
