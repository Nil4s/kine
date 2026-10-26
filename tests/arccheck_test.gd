## godot --path . -s tests/arccheck_test.gd     (ROADMAP L26, "arc checker": scripts/arc_check.gd; needs a window)
## Natural motion follows arcs (the twelve principles): a kink in a joint's path without a stop reads as mechanical.
## Bars, written before measuring (scenes: right shoulder swept at constant speed, 0.1 s per 30 deg, linear, no spline):
##  (1) a wrist on a smooth circular arc (x sweep -60..60 deg): 0 kinks on every joint
##  (2) the same sweep whose last four keys turn to another axis (a corner at 0.6 s, a 60 deg turn at 1.4 m/s): exactly 1 kink, on hand_r,
##      at 0.6 s +-1/30, turning 45..75 deg (the built 60), at a speed over 1 m/s; no other joint flagged
##  (3) a stop-and-reverse (smooth ease, the speed goes to zero at the apex): 0 kinks. CONTROL: the same reversal with linear ease
##      (no stop) IS flagged at the apex +-1/30 (else (3) passes by emptiness)
##  (4) scenes/combo3.json (read only): runs, prints the count; every finding has a joint, time, angle, speed, severity
##  (5) PLACEMENT: after the command on scene (2), in the whole-body view, the kink dot is within 30 px of the right wrist on screen,
##      the playhead is on the worst kink, the dot is inside the 3D view and clear of the panel; screenshot arccheck.png
##  (6) reading changes nothing: cards and the undo list byte-identical after the command
extends SceneTree

var fails := 0
var m: Node
const OUT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/arccheck.png"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## a scene from a list of {joint: Vector3 deg} per key, 0.1 s between keys, constant speed (linear) or the default smooth ease
func scene(keys: Array, linear: bool) -> Scene:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var S := Scene.new()
	S.name = "zz_arc"
	S.natural = false
	S.spline = false
	for i in keys.size():
		for j in keys[i]:
			B.set_ang(j, keys[i][j])
		B.fk()
		S.add("k%d" % i, B.to_dict())
		B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		B.fk()
		S.cards[i]["move"] = 0.1 if i > 0 else 0.0
		S.cards[i]["hold"] = 0.0
		if linear:
			S.cards[i]["ease"] = "linear"
	return S


func sweep(n := 5) -> Array:   # the shoulder swept by 15 deg a key from -60 (its limit): the wrist runs a circle of the arm's length at 1.4 m/s
	var k := []
	for i in n:
		k.append({"upperarm_r": Vector3(-60.0 + 15.0 * i, 0, 0)})
	return k


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()

	var circ := scene(sweep(9), true)
	var k1 := ArcCheck.check(circ, B)
	ok(k1.is_empty(), "(1) a wrist on a smooth circular arc: %d kinks" % k1.size())
	var sm1 := ArcCheck.sample(circ, B)
	var peak := 0.0
	var p1: Array = sm1["hand_r"]["p"]
	for i in range(1, p1.size()):
		peak = maxf(peak, ((p1[i] as Vector3) - p1[i - 1]).length() * 60.0)
	ok(peak > 1.0, "CONTROL 1 the wrist is moving at speed (peak %.1f m/s > 1), so 0 kinks is not emptiness" % peak)

	# the corner: after 6 keys of the sweep (x to 30 deg, the wrist going level) the next four go up as well: x +7.5, y +13 deg a key
	# (measured on this body: 30 deg of x moves the wrist 0.283 m level, 30 deg of y 0.283 m up) = 0.07 m level + 0.123 m up per key,
	# the same 0.141 m a key as before, turned atan(0.123 / 0.07) = 60 deg
	var ck := sweep(7)
	for i in range(1, 5):
		ck.append({"upperarm_r": Vector3(30.0 + 7.5 * i, 13.0 * i, 0)})
	var cor := scene(ck, true)
	var k2 := ArcCheck.check(cor, B)
	for k in k2:
		print("  kink: %s t %.3f angle %.1f excess %.1f speed %.2f %s" % [k["joint"], k["t"], k["angle"], k["excess"], k["speed"], k["sev"]])
	ok(k2.size() == 1 and k2[0]["joint"] == "hand_r", "(2) the corner: exactly 1 kink, on hand_r (%d found)" % k2.size())
	if k2.size() >= 1:
		ok(absf(float(k2[0]["t"]) - 0.6) <= 1.0 / 30.0 + 1e-6, "(2) at %.3f s (corner key at 0.600 s, +-1/30)" % k2[0]["t"])
		ok(float(k2[0]["angle"]) >= 45.0 and float(k2[0]["angle"]) <= 75.0 and float(k2[0]["speed"]) > 1.0, "(2) turns %.0f deg (45..75) at %.1f m/s (> 1)" % [k2[0]["angle"], k2[0]["speed"]])

	var rv := sweep()
	for i in range(3, -1, -1):
		rv.append(rv[i])
	var stop := scene(rv, true)
	stop.cards[4]["ease"] = "smooth"   # the two moves round the apex ease: the speed goes to zero there
	stop.cards[5]["ease"] = "smooth"
	var k3 := ArcCheck.check(stop, B)
	ok(k3.is_empty(), "(3) stop-and-reverse (smooth ease): %d kinks" % k3.size())
	var nostop := scene(rv, true)
	var k3b := ArcCheck.check(nostop, B)
	ok(k3b.size() >= 1 and k3b[0]["joint"] == "hand_r" and absf(float(k3b[0]["t"]) - 0.4) <= 1.0 / 30.0 + 1e-6,
		"CONTROL 3 the same reversal at constant speed (no stop) is flagged: %s" % ("%d at %.3f s, %.0f deg" % [k3b.size(), k3b[0]["t"], k3b[0]["angle"]] if k3b.size() > 0 else "none"))

	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	var u0: int = m.undo.size()
	var cards0 := JSON.stringify(m.S.cards)
	var t0 := Time.get_ticks_msec()
	m._arc_check()
	var list: Array = m.arc_list
	var by := {}
	var good := true
	for k in list:
		by[k["joint"]] = int(by.get(k["joint"], 0)) + 1
		good = good and k.has("joint") and k.has("t") and k.has("angle") and k.has("speed") and k.has("sev")
	print("combo3: %d kinks %s in %d ms (card length %.1f s); worst: %s" % [list.size(), by, Time.get_ticks_msec() - t0, m.S.length(),
		("%s %.2f s %.0f deg" % [list[0]["joint"], list[0]["t"], list[0]["angle"]]) if not list.is_empty() else "-"])
	ok(good, "(4) combo3 runs; every finding has joint, time, angle, speed, severity")
	ok(JSON.stringify(m.S.cards) == cards0 and m.undo.size() == u0, "(6) combo3 cards byte-identical, no undo step (undo list %d)" % m.undo.size())
	m._arc_close()

	m.S = cor
	m._rebuild_cards()
	await idle()
	m._arc_check()
	await idle(3)
	m._turn_to(0.0, -8.0, 5.0, Vector3(-0.8, 0.95, 0), false)   # the whole body, shifted right so the findings panel on the left clears the arm
	await idle(5)
	root.get_texture().get_image().save_png(OUT)
	ok(m.arc_list.size() == 1 and m.arc_marks.size() == 1, "(5) the command found the corner and drew its dot")
	var cam: Camera3D = m.get_viewport().get_camera_3d()
	var vp := m.get_viewport().get_visible_rect().size
	if m.arc_marks.size() > 0:
		ok(absf(float(m.playhead) - 0.6) <= 1.0 / 30.0 + 1e-6, "(5) the playhead is on the worst kink (%.3f s)" % m.playhead)
		var pw: Vector2 = cam.unproject_position(m.B.P["hand_r"])
		var pm: Vector2 = cam.unproject_position(m.arc_marks[0])
		var pr: Rect2 = m.ui_find.get_global_rect()
		print("screen: wrist %s dot %s panel %s viewport %s" % [pw, pm, pr, vp])
		ok(pm.distance_to(pw) <= 30.0, "(5) PLACEMENT: the dot is %.1f px from the wrist (<= 30)" % pm.distance_to(pw))
		ok(Rect2(Vector2.ZERO, vp).has_point(pm) and not pr.has_point(pm) and m.arc_view.visible, "(5) the dot is inside the view, clear of the panel, and the drawing is visible")
	print("ARCCHECK RESULT: ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(fails)
