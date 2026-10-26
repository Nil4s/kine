## godot --headless --path . -s tests/tween_test.gd     (GATES F1)
## The tween rule on two real cards: 0 = the left card, 1 = the right card, 0.5 = halfway on every angle, past the ends
## the body still never leaves its limits (put() clamps), and an angle at its limit at 1.25 is reported, not broken.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func worst(B: Body, want: Dictionary) -> float:
	var w := 0.0
	for j in want["ang"]:
		if B.lim.has(j):
			var d := Scene._d(want["ang"][j], B.ang[j], j).abs()
			w = maxf(w, d[d.max_axis_index()])
	return w


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var a := Moves._flat(S.cards[2]["pose"])   # CONTACT
	var b := Moves._flat(S.cards[3]["pose"])   # follow-through
	Scene.put(B, Scene.mix_flat(a, b, 0.0))
	ok(worst(B, a) < 1e-3, "0.00 = the card before: worst %.5f deg" % worst(B, a))
	Scene.put(B, Scene.mix_flat(a, b, 1.0))
	ok(worst(B, b) < 1e-3, "1.00 = the card after: worst %.5f deg" % worst(B, b))
	var half := {"ang": {}}
	for j in a["ang"]:
		half["ang"][j] = (a["ang"][j] as Vector3) + Scene._d(a["ang"][j], b["ang"][j], j) * 0.5
	Scene.put(B, Scene.mix_flat(a, b, 0.5))
	ok(worst(B, half) < 1e-3, "0.50 = halfway on every angle: worst %.5f deg" % worst(B, half))
	var out := 0
	var limited := 0
	for s in [-0.25, 1.25]:
		Scene.put(B, Scene.mix_flat(a, b, s))
		for j in B.ang:
			if not B.lim.has(j):
				continue
			if not (B.clamp_ang(j, B.ang[j]) as Vector3).is_equal_approx(B.ang[j]):
				out += 1
			if not B.at_limit(j).is_empty():
				limited += 1
	ok(out == 0, "overshoot -25%% / +25%%: no angle outside its limits (%d joints resting on a limit)" % limited)
	# the hips' whole-body turn takes the short way (170 -> -170 is 20 deg, not 340)
	var p := {"offset": Vector3.ZERO, "ang": {"pelvis": Vector3(0, 0, 170)}, "weapon": {}}
	var q := {"offset": Vector3.ZERO, "ang": {"pelvis": Vector3(0, 0, -170)}, "weapon": {}}
	var m := Scene.mix_flat(p, q, 0.5)
	ok(absf(absf((m["ang"]["pelvis"] as Vector3).z) - 180.0) < 1e-3, "pelvis 170 -> -170 at 0.5 = 180 (short way): %.2f" % (m["ang"]["pelvis"] as Vector3).z)
	print("TWEEN %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
