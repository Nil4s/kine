## godot --path . -s tests/perf1_test.gd     (PERF1: the cost of one played frame, Scene.apply_true)
## BAR (stated before measuring):
##   1 BIT FOR BIT: scenes combo3, walk_bat (read only), idle_bat, strike_legs, and combo3 with an IK key on the hand, each played at
##     60 Hz over its whole length, then again in reverse order (scrubbing): after EVERY frame the body's angles, hips offset,
##     G / P / E of every bone and the weapon are byte-equal (var_to_bytes) between the new code and the old code (Body.legacy_ik +
##     Scene.legacy_play run the bisections and the pose/ground/anchors sequence as they were before this change).
##     ANTI-VACUITY: the frames differ from each other (the bodies move), and the anchors memo hit more than 100 times.
##   2 SPEED: combo3, 4 alternating rounds of the whole scene (round 0 is warm-up): the new frame costs at most 80 % of the old
##     one (min over rounds; the target is 50 %). Printed as ms per frame, old and new, per scene.
## Nothing is written to scenes/, poses/ or data/.
extends SceneTree

var fails := 0
const SCENES := ["combo3", "walk_bat", "idle_bat", "strike_legs", "combo3+ik"]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func load_scene(nm: String) -> Scene:
	var S := Scene.new()
	var base := nm.split("+")[0]
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/%s.json" % base)))
	if nm.ends_with("+ik"):
		var L := S.length()
		var pole := Vector3(-0.6, 1.0, -0.3)
		S.ik = {"hand_l": [{"t": 0.0, "target": Vector3(0.3, 1.0, 0.3), "pole": pole, "w": 1.0},
			{"t": L, "target": Vector3(0.3, 1.2, 0.3), "pole": pole, "w": 1.0}]}
	return S


func new_body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	return B


func dump(B: Body) -> PackedByteArray:
	return var_to_bytes([B.ang, B.offset, B.G, B.P, B.E, B.wep_on, B.wep_pos, B.wep_rot, B.wep_lpos, B.wep_lrot, B.wep_hand, B.grip, B.grip_u])


func set_legacy(on: bool) -> void:
	Body.legacy_ik = on
	Scene.legacy_play = on


func times_for(S: Scene) -> Array:
	var out := []
	var L := S.length()
	var n := int(ceil(L * 60)) + 1
	for k in n:
		out.append(minf(k / 60.0, L))
	var rev := out.duplicate()
	rev.reverse()
	return out + rev


func ms_per_frame(S: Scene, B: Body, ts: Array) -> float:
	var t0 := Time.get_ticks_usec()
	for t in ts:
		S.apply_true(B, t)
	return (Time.get_ticks_usec() - t0) / 1000.0 / ts.size()


func _init() -> void:
	for nm in SCENES:
		var Sa := load_scene(nm)
		var Sb := load_scene(nm)
		var Ba := new_body()
		var Bb := new_body()
		var ts := times_for(Sa)
		var bad := 0
		var distinct := {}
		for t in ts:
			set_legacy(true)
			Sa.apply_true(Ba, t)
			var da := dump(Ba)
			set_legacy(false)
			Sb.apply_true(Bb, t)
			var db := dump(Bb)
			if da != db:
				bad += 1
			distinct[hash(da)] = true
		set_legacy(false)
		ok(bad == 0, "%s: %d frames (forward + reverse) byte-equal old vs new (%d differ)" % [nm, ts.size(), bad])
		ok(distinct.size() > ts.size() / 4, "%s: the body moves (%d distinct frames of %d)" % [nm, distinct.size(), ts.size()])
		# speed, alternating rounds on warm bodies
		var best_old := INF
		var best_new := INF
		for r in 5:
			set_legacy(true)
			var o := ms_per_frame(Sa, Ba, ts)
			set_legacy(false)
			var n := ms_per_frame(Sb, Bb, ts)
			if r > 0:
				best_old = minf(best_old, o)
				best_new = minf(best_new, n)
		print("     %-10s old %.3f ms/frame  new %.3f ms/frame  (%.0f%%)" % [nm, best_old, best_new, 100.0 * best_new / best_old])
		if nm == "combo3":
			ok(best_new <= 0.8 * best_old, "combo3: new frame at most 80%% of old (%.0f%%; target 50%%)" % (100.0 * best_new / best_old))
	set_legacy(false)
	print("PERF1 %s" % ("FAIL" if fails > 0 else "ok"))
	quit(1 if fails > 0 else 0)
