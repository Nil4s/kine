## godot --headless --path . -s tests/drivers_test.gd     (USER DRIVERS, GAP_ANALYSIS row 15; scripts/drivers.gd)
## Bars, written before measuring:
##   1 FORMULA: two cards and a layer on the upper arm; at 10 times of the played scene the driven clavicle's bend =
##     source * factor + offset within 1e-6, the source read from the body AS IT STANDS after the play (so the driver ran
##     after the cards and the layer). Anti-vacuity: without the driver the clavicle is 0 at those times.
##   2 FROM: the source counts only above its threshold: below it the driven angle is the offset alone, above it
##     (source - from) * factor + offset, within 1e-6 at 10 times.
##   3 LIMIT: factor 10 on a large source: the driven angle is clamped at the joint's limit (30 deg), never past it, and
##     the play reports the clamp.
##   4 FILE: "drivers" only when there is one; to_dict -> JSON -> from_dict plays within 1e-6 of the original at 10 times;
##     a malformed entry (unknown joint, axis 5, no factor) is dropped on load.
##   5 MIRROR: a scene with a bend driver and a SIDE driver (clavicle bend drives upper-arm side): the mirrored scene's
##     whole pose equals Body.mirror_pose of the original's pose at 10 times, every joint within 1e-3 deg. The mirrored
##     drivers name the twin joints. Anti-vacuity: with the side driver's sign flipped the pose check fails.
##   6 NOTHING WITHOUT ONE: every scene in scenes/ (read only) with no "drivers" key loads, saves without the key, and
##     Drivers.play([]) changes no angle.
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


func pose(B: Body, angs: Dictionary) -> Dictionary:
	for j in Body.ORDER:
		B.ang[j] = Vector3.ZERO
	B.wep_on = false
	for j in angs:
		B.ang[j] = B.clamp_ang(j, angs[j])
	B.fk()
	return B.to_dict()


func times(S: Scene) -> Array:
	var out := []
	for i in 10:
		out.append(S.length() * (i + 0.5) / 10.0)
	return out


## the two-card scene: the upper arm swings from 0 to 120 deg, the clavicle at rest
func arm_scene(B: Body) -> Scene:
	var S := Scene.new()
	S.name = "drivers_arm"
	S.add("start", pose(B, {"upperarm_r": Vector3(0, 0, 0)}))
	S.add("raised", pose(B, {"upperarm_r": Vector3(120, 0, 0)}))
	return S


func drv(driven: String, axis: int, source: String, src_axis: int, factor: float, offset: float, from = null) -> Dictionary:
	var d := {"driven": driven, "axis": axis, "source": source, "src_axis": src_axis, "factor": factor, "offset": offset}
	if from != null:
		d["from"] = from
	return d


## the worst joint gap (deg) between the mirrored scene's pose and Body.mirror_pose of the original's, over 10 times
func gap(S: Scene, Sm: Scene, B: Body, M: Body) -> float:
	var worst := 0.0
	for t in times(S):
		S.apply(B, t)
		var MB := Body.new()
		MB.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		for j in Body.ORDER:
			MB.ang[j] = B.ang[j]
		MB.mirror_pose()
		Sm.apply(M, t)
		for j in Body.ORDER:
			worst = maxf(worst, (M.ang[j] as Vector3).distance_to(MB.ang[j] as Vector3))
	return worst


func _init() -> void:
	var B := body()

	# 1 FORMULA (after the cards and a layer)
	var S := arm_scene(B)
	S.layer = {"upperarm_r": Vector3(10, 0, 0)}
	S.layer_w = 1.0
	S.drivers = [drv("clavicle_r", 0, "upperarm_r", 0, 0.1, 2.0)]
	var worst := 0.0
	var moved := 0.0
	for t in times(S):
		S.apply(B, t)
		var src: float = B.ang["upperarm_r"].x
		var got: float = B.ang["clavicle_r"].x
		worst = maxf(worst, absf(got - (src * 0.1 + 2.0)))
		moved = maxf(moved, absf(got))
	ok(worst < 1e-6, "1 driven = source x factor + offset at 10 times of the played scene, worst %.9f deg (bar 1e-6)" % worst)
	var S0 := arm_scene(B)
	S0.layer = S.layer.duplicate()
	S0.layer_w = 1.0
	var off_by := 0.0
	for t in times(S0):
		S0.apply(B, t)
		off_by = maxf(off_by, absf(B.ang["clavicle_r"].x))
	ok(off_by < 1e-9 and moved > 1.0, "1 anti-vacuity: with no driver the clavicle stays at 0 (%.9f) while the driven one reaches %.2f deg" % [off_by, moved])

	# 2 FROM: the source counts only above 60 deg
	var S2 := arm_scene(B)
	S2.drivers = [drv("clavicle_r", 0, "upperarm_r", 0, 0.25, 1.0, 60.0)]
	worst = 0.0
	var below := 0.0
	for t in times(S2):
		S2.apply(B, t)
		var src: float = B.ang["upperarm_r"].x
		var want := 1.0 if src <= 60.0 else (src - 60.0) * 0.25 + 1.0
		worst = maxf(worst, absf(B.ang["clavicle_r"].x - want))
		if src <= 60.0:
			below = maxf(below, absf(B.ang["clavicle_r"].x - 1.0))
	ok(worst < 1e-6 and below < 1e-6, "2 from 60: offset alone below the threshold, (source - 60) x 0.25 + 1 above it, worst %.9f deg" % worst)

	# 3 LIMIT
	var S3 := arm_scene(B)
	S3.drivers = [drv("clavicle_r", 0, "upperarm_r", 0, 10.0, 0.0)]
	var over := 0.0
	var reported := false
	for t in times(S3):
		S3.apply(B, t)
		var c: float = B.ang["clavicle_r"].x
		over = maxf(over, c - 30.0)
		if c >= 30.0 - 1e-9:
			reported = true
	var rep := Drivers.play([drv("clavicle_r", 0, "upperarm_r", 0, 10.0, 0.0)], B)
	ok(over <= 1e-9 and reported and not rep.is_empty() and bool(rep[0]["clamped"]), "3 limit: the driven clavicle sits at its 30 deg limit and never past it (over by %.9f), the play says so" % over)

	# 4 FILE
	var S4 := arm_scene(B)
	S4.drivers = [drv("clavicle_r", 0, "upperarm_r", 0, 0.1, 2.0), drv("clavicle_l", 0, "upperarm_r", 0, -0.2, 0.0, 30.0)]
	var d4 := S4.to_dict(B, false)
	ok(d4.has("drivers") and not S0.to_dict(B, false).has("drivers"), "4 'drivers' in the file only when there is one")
	var parsed = JSON.parse_string(JSON.stringify(d4))
	var R := Scene.new()
	R.from_dict(parsed)
	var rt := 0.0
	for t in times(S4):
		S4.apply(B, t)
		var a := {"clavicle_r": B.ang["clavicle_r"].x, "clavicle_l": B.ang["clavicle_l"].x}
		R.apply(B, t)
		rt = maxf(rt, maxf(absf(a["clavicle_r"] - B.ang["clavicle_r"].x), absf(a["clavicle_l"] - B.ang["clavicle_l"].x)))
	ok(rt < 1e-6 and R.drivers.size() == 2, "4 file round trip plays within %.9f deg of the original at 10 times" % rt)
	var bad := Drivers.from_file([{"driven": "nope", "axis": 0, "source": "upperarm_r", "src_axis": 0, "factor": 1.0},
		{"driven": "clavicle_r", "axis": 5, "source": "upperarm_r", "src_axis": 0, "factor": 1.0},
		{"driven": "clavicle_r", "axis": 0, "source": "upperarm_r", "src_axis": 0},
		{"driven": "clavicle_r", "axis": 0, "source": "clavicle_r", "src_axis": 0, "factor": 1.0}])
	ok(bad.is_empty(), "4 malformed drivers (unknown joint, axis 5, no factor, a joint driving itself) are dropped on load")

	# 5 MIRROR: bend on bend, and a side driver (the clavicle's bend drives the upper arm's side)
	var S5 := arm_scene(B)
	S5.drivers = [drv("clavicle_r", 0, "upperarm_r", 0, 0.1, 2.0), drv("upperarm_r", 1, "clavicle_r", 0, 0.5, 0.0)]
	var M := Body.new()
	M.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var mirrored := Scene.mirror_file(S5.to_dict(B, false), M)
	var S6 := Scene.new()
	S6.from_dict(mirrored)
	var names_ok: bool = S6.drivers[0]["driven"] == "clavicle_l" and S6.drivers[0]["source"] == "upperarm_l" and S6.drivers[1]["driven"] == "upperarm_l"
	ok(names_ok, "5 mirrored drivers name the twins (clavicle_l <- upperarm_l, upperarm_l side <- clavicle_l)")
	var pose_worst := gap(S5, S6, B, M)
	var flipped := mirrored.duplicate(true)
	flipped["drivers"][1]["factor"] = -float(flipped["drivers"][1]["factor"])
	var S7 := Scene.new()
	S7.from_dict(flipped)
	var flip_worst := gap(S5, S7, B, M)
	ok(pose_worst < 1e-3, "5 mirrored scene's whole pose = mirror_pose of the original's, every joint within %.9f deg" % pose_worst)
	ok(flip_worst > 1e-2, "5 anti-vacuity: the side driver with its sign flipped is off by %.2f deg" % flip_worst)

	# 6 NOTHING WITHOUT ONE
	var n := 0
	var untouched := true
	var dir := DirAccess.open("res://scenes")
	if dir != null:
		for f in dir.get_files():
			if not f.ends_with(".json") or n >= 12:
				continue
			var txt := FileAccess.get_file_as_string("res://scenes/" + f)
			var pd = JSON.parse_string(txt)
			if not (pd is Dictionary and pd.has("cards")):
				continue
			n += 1
			var sc := Scene.new()
			sc.from_dict(pd)
			if sc.to_dict(B, false).has("drivers"):
				untouched = false
	var before: Vector3 = B.ang["upperarm_r"]
	var rep0: Array = Drivers.play([], B)
	ok(untouched and n > 0 and rep0.is_empty() and B.ang["upperarm_r"] == before, "6 %d scenes in scenes/ save without a 'drivers' key; play([]) changes nothing" % n)

	print("%d failures" % fails)
	quit(fails)
