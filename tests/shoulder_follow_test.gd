## godot --path . -s tests/shoulder_follow_test.gd     (round 43, GATES YY5; needs the window: main.tscn)
## SHOULDERS THAT FOLLOW: an arm raise measured against McClure et al. 2001 (bone pins, 8 people): the clavicle rises
## ~10 and draws back ~21 over 11 -> 147 deg, the scapula still in the first 30. Bars:
##   1 the raise sweep (the right upper arm's side from hanging to overhead): the clavicle is 0 while the arm is
##     under 30 deg; never goes down as the arm goes up; at the top elevation 10.0 (people ~10) and retraction at
##     this body's limit 15 (people ~21: the limit, printed).
##   2 fixed point: after a follow, the clavicle equals follow_clav(the arm's elevation measured WITH it) (0.05 deg).
##   3 the rate between: clavicle elevation per degree of arm raise past 30 = 10 / 117 (printed beside McClure).
##   4 the window: the upper-arm SLIDER raised to overhead brings the clavicle up (> 8) and its twin is untouched.
##   5 off: with "Shoulders follow the arm" switched off the same slider leaves the clavicle at 0.
##   6 old poses identical: loading a scene and a library pose changes no angle (the follow runs on hand edits only).
##   7 a hand PULL (reach) is not overridden: the clavicle is whatever reach chose.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	# the raise as a hand makes it: the upper arm through set_ang_safe (it stops at the head), then the follow
	var below := true
	var mono := true
	var fixed := 0.0
	var hit := false
	var stopped := []
	var last := Vector3.ZERO
	var at147 := Vector3(NAN, 0, 0)
	var e147 := 0.0
	var s := -90.0
	while s <= 90.0:
		for j in B.ang:
			B.ang[j] = Vector3.ZERO
		B.fk()
		B.set_ang_safe("upperarm_r", Vector3(0, s, 0))
		var reached := B.shoulder_follow("_r")
		var e := B.arm_elevation("_r")
		var c: Vector3 = B.ang["clavicle_r"]
		if B.contacts().size() > 0:
			hit = true
		if e < 30.0:   # McClure: the girdle still in the first 30 deg (a literal: the bar must not move with the code)
			below = below and c.length() < 1e-6
		if reached:
			fixed = maxf(fixed, (c - B.clamp_ang("clavicle_r", B.follow_clav(e))).length())
			mono = mono and c.x >= last.x - 1e-6 and c.y <= last.y + 1e-6
			last = c
			if e >= 147.0 and is_nan(at147.x):
				at147 = c
				e147 = e
		else:
			stopped.append("side %.0f (arm %.0f deg)" % [s, e])
		s += 5.0
	ok(below and mono and absf(at147.x - 10.0) < 1e-4 and absf(at147.y + 15.0) < 1e-4,
		"1 the raise: clavicle 0 under 30 deg %s, never down as the arm rises %s; at McClure's top (arm %.0f deg) up %.1f, back %.1f (people ~10 / ~21; the body's limit 15)" % [below, mono, e147, at147.x, -at147.y])
	ok(fixed < 0.05 and stopped.size() <= 3, "2 fixed point: where it reached, the clavicle = follow_clav(the elevation measured with it) within %.4f deg; stopped by a contact at %s (the overhead arm meets the head: at most the top 3 steps)" % [fixed, stopped])
	ok(not hit, "2b no contact anywhere on the raise with the follow on")
	var rate := Body.FOLLOW_ELEV / (Body.FOLLOW_TO - Body.FOLLOW_FROM)
	ok(absf(rate - 10.0 / 117.0) < 1e-9, "3 rate: %.3f deg of clavicle per deg of arm past 30 (McClure: ~10 over the raise)" % rate)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle()
	m._reset_all()
	await idle()
	m.sel = "upperarm_r"
	m._on_slider(80.0, "side")
	await idle()
	var cr: Vector3 = m.B.ang["clavicle_r"]
	var cl: Vector3 = m.B.ang["clavicle_l"]
	ok(cr.x > 8.0 and cl.length() < 1e-6, "4 the slider raises the right arm overhead: its clavicle up %.1f back %.1f; the left clavicle %s" % [cr.x, -cr.y, cl])
	m._reset_all()
	await idle()
	m.shoulder_follow = false
	m.sel = "upperarm_r"
	m._on_slider(80.0, "side")
	await idle()
	ok((m.B.ang["clavicle_r"] as Vector3).length() < 1e-6, "5 off: the same slider leaves the clavicle at %s" % m.B.ang["clavicle_r"])
	# 6 / 7: the same steps with the follow ON and OFF must give the same angles (a load, a card, a hand pull)
	var runs := []
	for on in [true, false]:
		m.shoulder_follow = on
		m._reset_all()
		await idle()
		m._load_scene("res://scenes/combo3.json")   # read only
		await idle()
		m._card_pick(1)
		await idle()
		var after_load: Dictionary = m.B.ang.duplicate()
		m._reset_all()
		await idle()
		m.sel = "hand_r"
		m._grab = Vector3(NAN, NAN, NAN)
		m._drag_joint(Vector2(0, -120), false, false, false)
		await idle()
		runs.append([after_load, m.B.ang.duplicate(), m.B.P["hand_r"]])
	var load_same := true
	for j in runs[0][0]:
		load_same = load_same and (runs[0][0][j] as Vector3).is_equal_approx(runs[1][0][j])
	ok(load_same, "6 old poses identical: combo3's card 1 loads to the same angles, follow on or off (every joint)")
	var pull_same := true
	for j in runs[0][1]:
		pull_same = pull_same and (runs[0][1][j] as Vector3).is_equal_approx(runs[1][1][j])
	ok(pull_same, "7 a hand pull is left to reach: same angles follow on or off (clavicle %s)" % runs[0][1]["clavicle_r"])
	m.shoulder_follow = true
	print("SHOULDER FOLLOW TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
