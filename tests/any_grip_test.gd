## godot --headless --path . -s tests/any_grip_test.gd     (ROADMAP 18; docs/research/ANY_GRIP.md)
## THE GRIP FOR ANY PROP: the fingers closed round a prop's surface (scripts/any_grip.gd), the prop given as a distance field.
##   1 a hand at a 4 cm cylinder (a mesh: 12 cm tall, upright, 24 sides): the pattern is "cylinder"; every fingertip
##     touches the surface (<= 3 mm) or is at its joint limit; no segment inside the cylinder by more than 1 mm; the thumb
##     meets it too (<= 3 mm or its limit)
##   2 a 22 cm ball (props.gd "ball"): the pattern is "sphere"; every fingertip on the surface (<= 3 mm) or at its limit,
##     none inside by more than 1 mm
##   3 the weapon wrap is unchanged: GripWrap.wrap on the metal bat gives the same rows before and after the two prop
##     wraps (AnyGrip keeps no state in the body beyond the joint angles it sets)
##   4 the keys: grip_prop's key_hand puts the 15 finger and thumb joints at the playhead, each at the angle it closed to
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## the rows of a wrap as one string (the weapon check compares them exactly)
func _rows(rep: Dictionary) -> String:
	var out := []
	for f in GripWrap.LONG:
		out.append(rep[f])
	out.append(rep["thumb"])
	return JSON.stringify(out)


## the closure's verdict on one prop: [fingertips, finger segments inside > 1 mm, thumb segments inside > 1 mm]
func _verdict(rep: Dictionary) -> Array:
	var tips := []
	var bad := []
	for f in GripWrap.LONG:
		var tip: Array = rep[f][2]
		tips.append("%s %+.1f mm%s" % [f, float(tip[1]) * 1000.0, " (limit)" if tip[2] == "limit" else ""])
		if not (float(tip[1]) <= 0.003 or tip[2] == "limit"):
			bad.append("%s tip %.1f mm off" % [f, float(tip[1]) * 1000.0])
		for row in rep[f]:
			if float(row[1]) < -0.001:
				bad.append("%s joint inside %.1f mm" % [f, float(row[1]) * 1000.0])
	var thumb_bad := []
	for row in rep["thumb"]:
		if float(row[1]) < -0.001:
			thumb_bad.append("%.1f mm" % [float(row[1]) * 1000.0])
	return [tips, bad, thumb_bad]


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var B: Body = m.B
	var keep := B.state()
	# 3a the bat's wrap before any prop
	B.set_kind("metal_bat")
	B.weapon_to_hand("hand_r")
	var hd := GripWrap.handle_of(B)
	var w1 := _rows(GripWrap.wrap(B, "hand_r", hd[0], hd[1], hd[2], GripWrap.type_of("metal_bat")))
	# the hand's place for the props: the bat's standard grip, with the bat taken away (the arm is where the bat's hand
	# is, so the palm faces the side the handle was on and the arm reaches it without a wrist past its limit)
	B.set_kind("metal_bat")
	B.weapon_to_hand("hand_r")
	B.wep_on = false
	B.grip = false
	var keep2 := B.state()
	B.set_state(keep2)
	# the hand's place for the props: on the side the palm faces at rest (curl_dir), the prop's surface 2-3 cm beyond the
	# palm (a prop straight out along the reach needed the wrist turned 90 deg, past its limit)
	var palm: Vector3 = B.palm_point("hand_r")
	var reach: Vector3 = AnyGrip.curl_dir(B, "hand_r")   # the side the palm faces at rest (the wrist turns least there)
	# 1 the 4 cm cylinder
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.02
	cyl.bottom_radius = 0.02
	cyl.height = 0.12
	cyl.radial_segments = 24
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	var cc := palm + reach * 0.045
	mi.transform = Transform3D(Basis(), cc)
	var t0 := Time.get_ticks_msec()
	var F := AnyGrip.field_of_node(mi)
	var t_field := Time.get_ticks_msec() - t0
	var pl := AnyGrip.place_hand(B, "hand_r", F)
	t0 = Time.get_ticks_msec()
	var rep := AnyGrip.wrap(B, "hand_r", F)
	var t_wrap := Time.get_ticks_msec() - t0
	var v := _verdict(rep)
	print("     cylinder: field %d ms, wrap %d ms; placed: wrist %.1f mm off the arm's aim, palm %+.1f mm from the surface" % [
		t_field, t_wrap, float(pl["wrist_m"]) * 1000.0, float(pl["palm_m"]) * 1000.0])
	print("     pattern %s; fingertips: %s" % [rep["pattern"], ", ".join(v[0])])
	var th: Array = rep["thumb"]
	print("     thumb tip %+.1f mm (%s)" % [float(th[1][1]) * 1000.0, th[1][2]])
	ok(rep["pattern"] == "cylinder", "1 a 4 cm cylinder is classed a cylinder (got %s)" % [rep["pattern"]])
	ok((v[1] as Array).is_empty(), "1 every fingertip on the cylinder (<= 3 mm) or at its limit; no finger segment inside by > 1 mm (bad: %s)" % [v[1]])
	ok((v[2] as Array).is_empty(), "1 the thumb outside the cylinder (segments inside: %s)" % [v[2]])
	ok(float(th[1][1]) <= 0.003 or th[1][2] == "limit", "1 the thumb opposes: its tip on the cylinder (<= 3 mm) or at its limit")
	# 4 the keys
	var pk := {}
	AnyGrip.key_hand(B, "hand_r", pk, 0.5)
	var keyed := 0
	for j in pk:
		keyed += 1
	ok(keyed == 15 and is_equal_approx(float(pk["index_02_r"][0]["t"]), 0.5), "4 key_hand keys the 15 finger and thumb joints at the playhead (got %d)" % [keyed])
	# 2 the balls: the hand's place is searched (AnyGrip.search_sphere: 26 palm directions x 3 rolls, each placed and
	# wrapped, scored by the fingertip and thumb-tip distances from the surface); the bar is strict: every fingertip ON the
	# ball (<= 3 mm, no limit allowance), no segment inside. The span (thumb tip to little finger tip, hand open) against
	# the arc the tips must cover (the chord of the ball's surface between them) is printed
	B.set_state(keep2)   # the span is measured in the bat-grip pose the balls start from (not after the cylinder)
	var span := AnyGrip.span_of(B, "hand_r")
	for D in [0.22, 0.09]:
		B.set_state(keep2)
		var bc: Vector3 = palm + reach * (D / 2.0 + 0.03)
		var bp := Props.make("ball", Props.xf_at(Vector3(bc.x, bc.y - D / 2.0, bc.z)))
		var FB := AnyGrip.field_of(bp)
		var tb := Time.get_ticks_msec()
		var best: Dictionary = AnyGrip.search_sphere(B, "hand_r", bc, D / 2.0, FB)
		var arc: float = D / 2.0 * 2.0 * asin(clampf(span / D, 0.0, 1.0))
		print("     ball %.0f cm (search %d s): span %.1f mm (thumb tip to little tip, open) vs the arc between them %.1f mm" % [
			D * 100.0, (Time.get_ticks_msec() - tb) / 1000, span * 1000.0, arc * 1000.0])
		var tips := []
		var on := 0
		for g in best["tips"]:
			tips.append("%+.1f" % [float(g) * 1000.0])
			if float(g) <= 0.003:
				on += 1
		var pat: String = (best["rep"] as Dictionary)["pattern"]
		print("     placed: palm dir %s, roll %s; fingertips (index, middle, ring, pinky) %s mm; thumb tip %+.1f mm" % [
			best["dir"], best["roll"], ", ".join(tips), float(best["thumb_m"]) * 1000.0])
		ok(pat == "sphere", "2 a %.0f cm ball is a spherical grasp (pattern %s)" % [D * 100.0, pat])
		ok(on == 4 and not bool(best["inside"]), "2 %.0f cm ball: every fingertip ON it (<= 3 mm, no limit allowance; %d of 4) and no segment inside" % [D * 100.0, on])
		ok(float(best["thumb_m"]) <= 0.003, "2 %.0f cm ball: the thumb tip on it (<= 3 mm; %+.1f mm)" % [D * 100.0, float(best["thumb_m"]) * 1000.0])
	B.set_state(keep2)
	B.fast = false
	# 3b the bat's wrap again, from the same body state as 3a (the arm the prop placements moved is put back)
	B.set_state(keep)
	B.set_kind("metal_bat")
	B.weapon_to_hand("hand_r")
	hd = GripWrap.handle_of(B)
	var w2 := _rows(GripWrap.wrap(B, "hand_r", hd[0], hd[1], hd[2], GripWrap.type_of("metal_bat")))
	ok(w1 == w2, "3 the weapon wrap is bit-identical before and after the prop wraps")
	B.set_state(keep)
	print("FAILS %d" % [fails])
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
