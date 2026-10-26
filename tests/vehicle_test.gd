extends SceneTree
## godot --headless --path . -s tests/vehicle_test.gd     (B3 VEHICLE: scripts/vehicle.gd; needs the CAD DLL; no window)
## Bars, written before measuring (every size in the Part records is mm; the numbers below are m and m3):
##   0 KCad is available (the DLL is there; without it nothing can be measured and the suite fails)
##   1 WHEEL     the wheel (r 0.30 m, 0.20 m wide, a revolve) has volume pi r^2 w = 0.056549 m3 within 1 %
##   2 BODY      the car body (2.4 x 1.2 x 0.5 m box) has volume 1.44 m3 within 1 %
##   3 STRAIGHT  a car driven 10 m on a straight path: every 0.5 m, each of the four wheels has turned s / r within 1 %
##               (10 / 0.3 = 33.33 rad at the end); the pivots read back the same angle; the car ends at (0, 0, 10) within 1 mm
##   4 CURVE     an S-shaped path: each wheel turns (smoothed arc length) / r within 1 %, and that arc is more than 5 % longer than
##               the chord (so the bar tells arc from chord)
##   5 GROUND    every wheel's centre is r above the ground (the tyre touches y = 0 within 1 um)
##   6 CLEAR     the four wheels and the body share no volume (KCad intersect volume = 0; all 4 body-wheel pairs and the 6 wheel pairs)
##   7 CONTROL   a wheel moved 5 cm into the body DOES share volume (> 0.005 m3, a 5 cm slice of the tyre): the intersect check can fail
##   Writes nothing; no shots (nothing is drawn on BUILD: the card stays greyed, see scripts/vehicle.gd).

const KCad := preload("res://scripts/kcad.gd")
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	if not c:
		fails += 1


func near(a: float, b: float, rel: float) -> bool:
	return absf(a - b) <= rel * absf(b)


func _init() -> void:
	ok(KCad.available(), "0 KCad is available (the CAD DLL is in native/bin/)")
	if not KCad.available():
		quit(1)
		return
	var car := PartTemplates.make("car")
	var wh := PartTemplates.make("wheel")
	var cp: Dictionary = car["easy"]["p"]
	var wp: Dictionary = wh["easy"]["p"]
	var r := float(wp["radius"]) * Part.MM
	var w := float(wp["width"]) * Part.MM

	# 1 wheel volume
	var wv := Part.replay(wh)["volume"] as float
	var wanted := PI * r * r * w
	ok(near(wv, wanted, 0.01), "1 WHEEL volume %.6f m3, pi r^2 w = %.6f (within 1 %%)" % [wv, wanted])

	# 2 body volume
	var bv := Part.replay(car)["volume"] as float
	var bw := float(cp["body_length"]) * float(cp["body_width"]) * float(cp["body_height"]) * Part.MM * Part.MM * Part.MM
	ok(near(bv, bw, 0.01), "2 BODY volume %.6f m3, L W H = %.6f (within 1 %%)" % [bv, bw])

	var lay := Vehicle.layout(cp, wp)

	# 3 straight 10 m
	var straight := PathWalk.curve([Vector3(0, 0, 0), Vector3(0, 0, 10)])
	var root := Vehicle.build_node(car, wh)
	var pivots: Array = root.get_meta("wheels")
	var worst := 0.0
	var pivot_ok := true
	var s := 0.0
	while s <= 10.0 + 1e-6:
		var a := Vehicle.drive(root, straight, s)
		var want := s / r
		worst = maxf(worst, absf(a - want) / maxf(want, 1e-9))
		for pv in pivots:
			pivot_ok = pivot_ok and absf(-(pv as Node3D).rotation.x - want) <= 0.01 * maxf(want, 1e-9) + 1e-9
		s += 0.5
	var end_ok := root.position.distance_to(Vector3(0, 0, 10)) < 0.001
	ok(worst <= 0.01 and pivot_ok, "3 STRAIGHT 10 m: each wheel turns s / r (33.33 rad at the end), worst error %.4f %% of the angle, pivots agree" % (worst * 100.0))
	ok(end_ok and near(float(straight["len"]), 10.0, 0.001), "3 STRAIGHT the car ends at (0, 0, 10) within 1 mm (path %.4f m)" % float(straight["len"]))

	# 4 curve
	var curve := PathWalk.curve([Vector3(0, 0, 0), Vector3(0, 0, 4), Vector3(3, 0, 6), Vector3(3, 0, 10)])
	var L: float = curve["len"]
	var chord := Vector3(3, 0, 10).length()
	var a2 := Vehicle.drive(root, curve, L)
	ok(near(a2, L / r, 0.01) and L > chord * 1.05, "4 CURVE: each wheel turns %.4f rad = arc %.4f m / r (chord %.4f m, arc %.1f %% longer)" % [a2, L, chord, (L / chord - 1.0) * 100.0])

	# 5 ground
	var ground_ok := true
	for p in lay["wheels"]:
		ground_ok = ground_ok and absf((p as Vector3).y - r) < 1e-6
	ok(ground_ok, "5 GROUND: every wheel centre is r = %.3f m above the ground" % r)

	# 6 clearance: all pairs
	var ids := []
	var body := Vehicle.solid_at(car, lay["body"])
	ids.append(body)
	for p in lay["wheels"]:
		ids.append(Vehicle.solid_at(wh, p))
	var worst_v := 0.0
	var pairs := 0
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			worst_v = maxf(worst_v, Vehicle.overlap(ids[i], ids[j]))
			pairs += 1
	ok(pairs == 10 and worst_v == 0.0, "6 CLEAR: %d body/wheel pairs share no volume (worst %.6f m3)" % [pairs, worst_v])

	# 7 control: a wheel 5 cm into the body must overlap
	var into := lay["wheels"][1] as Vector3
	into.x -= 0.05
	var inside := Vehicle.solid_at(wh, into)
	var bad := Vehicle.overlap(body, inside)
	ok(bad > 0.005, "7 CONTROL: a wheel 5 cm into the body shares %.4f m3 (must be > 0.005: a 5 cm slice of the tyre)" % bad)
	for id in ids:
		KCad.release(id)
	KCad.release(inside)
	root.free()
	quit(fails)
