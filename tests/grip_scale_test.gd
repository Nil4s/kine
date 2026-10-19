## godot --headless --path . -s tests/grip_scale_test.gd     (round 52, PROPORTIONS follow-up: grips scale with the hand)
## Every hand-LOCAL offset (the knob's place in the hand, the second wrist on the shaft, the palm point) is stored in
## default-body metres and multiplied by the hand segment's scale (Body.hand_s) where it is used.
##   1 the default body: hand_s is exactly 1 and the knob, the palm point and the second wrist come out of the SAME
##     formulas as before, bit for bit (exact equality, not within a tolerance)
##   2 the 5th-percentile woman (female_5): the bat's knob sits at hand_s times the default distance from the wrist,
##     and the palm's distance from the handle surface (GripMagnet.palm_off, the way tests/grip_wrap_test.gd and
##     capture_second place the palm) is within 1 mm of the default body's at the same pose: the handle sits in the palm
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _same(a: Vector3, b: Vector3) -> bool:
	return a.x == b.x and a.y == b.y and a.z == b.z


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var B: Body = m.B
	B.fast = true
	B.set_proportions({})
	B.set_kind("metal_bat")
	B.weapon_to_hand("hand_r")
	# 1 the default body: exact
	var s0 := B.hand_s("hand_r")
	var x0 := B.wep_xform()
	var g0: Quaternion = B.G["hand_r"]
	var raw_knob: Vector3 = (B.P["hand_r"] as Vector3) + g0 * B.wep_lpos
	var raw_palm: Vector3 = (B.P["hand_r"] as Vector3).lerp(B.E["hand_r"], 0.6) + g0 * Vector3(0, -0.03, 0)
	var palm0 := B.palm_point("hand_r")
	var ex1 := s0 == 1.0 and _same(x0[0], raw_knob) and _same(palm0, raw_palm)
	ok(ex1, "1 default body: hand_s %s, knob %s, palm %s: the same formulas as before, exactly" % [s0, _vs(x0[0]), _vs(palm0)])
	var d_default := GripMagnet.palm_off(B, "hand_r")
	var knob0 := (x0[0] as Vector3) - (B.P["hand_r"] as Vector3)
	var lp0 := B.wep_lpos
	var lr0 := B.wep_lrot
	# 2 the 5th-percentile woman, the same pose (the same angles, the same weapon kind and standard grip)
	B.set_proportions(Proportions.preset("female_5"))
	B.set_kind("metal_bat")
	B.weapon_to_hand("hand_r")
	var s := B.hand_s("hand_r")
	var knob1 := (B.wep_xform()[0] as Vector3) - (B.P["hand_r"] as Vector3)
	var d_female := GripMagnet.palm_off(B, "hand_r")
	print("     female_5 hand scale %.3f; knob %.1f mm from the wrist (default %.1f mm, x%.3f)" % [s, knob1.length() * 1000.0, knob0.length() * 1000.0, knob1.length() / maxf(knob0.length(), 1e-9)])
	print("     palm off the handle: default %.1f mm, female_5 %.1f mm (difference %.2f mm); the knob's stored place %s -> %s (default-hand metres)" % [d_default * 1000.0, d_female * 1000.0, absf(d_female - d_default) * 1000.0, _vs(lp0), _vs(B.wep_lpos)])
	# the knob's place along the bat's axis (in the hand) is the stored place scaled by the hand, exactly
	var a0 := lr0 * Vector3.UP
	var along_f := B.knob_in_hand(B.wep_lpos, B.wep_lrot, "hand_r").dot(a0)
	var along_d := lp0.dot(a0)
	ok(s < 1.0 and absf(along_f - s * along_d) < 1e-5, "2a the knob's place along the bat, in the hand: %.4f m (default %.4f m x hand scale %.3f = %.4f m); the female's knob is %.1f mm from the wrist" % [along_f, along_d, s, s * along_d, knob1.length() * 1000.0])
	ok(absf(d_female - d_default) <= 0.001, "2b the palm's offset from the handle %.2f mm, the default body's %.2f mm at the same pose (within 1 mm)" % [d_female * 1000.0, d_default * 1000.0])
	B.set_proportions({})
	m.queue_free()
	print("GRIP SCALE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


func _vs(v: Vector3) -> String:
	return "(%.4f, %.4f, %.4f)" % [v.x, v.y, v.z]
