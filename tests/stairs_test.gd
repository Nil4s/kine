## godot --headless --path . -s tests/stairs_test.gd     (ROADMAP 93: stairs and slopes; scripts/props.gd ground props and
## surface_below, scripts/foot_plant.gd ground_ref and _lower_for_reach, scripts/body.gd surface_at, scripts/floor_snap.gd)
## Bars, written before measuring:
##   1 STEP (stairs_code, 17.8 cm risers, 28 cm treads): the left foot planted on tread 1 over [0.5, 1.5] s, the right on the
##     floor in front of the stairs. On EVERY planted frame at 120 Hz: the left sole's heel, ball and toe tip each within 3 mm
##     of the tread, the right sole's three points within 3 mm of the floor; no sole point under its surface by more than 2 mm;
##     the foot's axis (ankle to ball) inside no prop by more than 2 mm.
##   2 REACH: on every planted frame each planted leg's ankle is within its leg's length, and the planted ankle is within 1 mm
##     of its target (FootPlant.play's miss). The hips drop with the plant: the played hips (the same stride unplanted) are
##     more than 1 mm above the planted hips (anti-vacuity: the lower foot is out of reach of the played hips).
##   3 RAMP (ramp15, 15 degrees): both feet planted at mid-ramp. On every planted frame: each sole's normal is within 3 deg of
##     the ramp's normal, each sole point within 3 mm of the ramp, and no ankle, ball, calf or thigh is past its limit (the
##     clamp moves none of them by more than 0.01 deg). The ramp's slope is read from the ground's normal and must be 15 deg.
##   4 FLAT GROUND: the stance plant on flat floor with a table 10 m away (no prop under the feet) plays every planted frame
##     bit for bit the same as the same scene with no props (the body dictionary and the offset).
##   5 SNAP ON A STEP: a standing pose (both feet flat on a box step's 17.8 cm top) lifted 30 cm: after FloorSnap with the
##     set, the lowest sole point is on the top to within 1 mm, and the root moved down 0.30 - 0.178 = 0.122 m to within 1 mm.
##   6 SCREENSHOT (windowed run only, POSER_STAIRS_PNG names the file): the stride on the stairs in the app, a whole-body side
##     view. Placement is read by hand: the stance foot ON the tread, the other ON the floor below it.
extends SceneTree

var fails := 0
const HZ := 120
const T0 := 0.5
const T1 := 1.5
const TREAD := 0.178   # m: the riser of the step (17.8 cm)
const STANCE := {"thigh_l": Vector3(-6, 0, 0), "calf_l": Vector3(38, 0, 0), "foot_l": Vector3(25, 0, 0), "thigh_r": Vector3(-6, 0, 0), "calf_r": Vector3(38, 0, 0), "foot_r": Vector3(25, 0, 0)}
## the ramp's stance: a near-straight leg, so the foot's world pitch is the slope's to take (a 38 deg calf tilts the foot 46 deg
## with the shin, and the ankle's 25 deg of toe-up cannot take the slope from there)
const RAMP_STANCE := {"thigh_l": Vector3(-3, 0, 0), "calf_l": Vector3(5, 0, 0), "foot_l": Vector3(0, 0, 0), "thigh_r": Vector3(-3, 0, 0), "calf_r": Vector3(5, 0, 0), "foot_r": Vector3(0, 0, 0)}
## the left foot forward (its toe on a tread), the right back on the floor (negative thigh = back, positive = forward)
const STRIDE := {"thigh_l": Vector3(30, 0, 0), "calf_l": Vector3(8, 0, 0), "foot_l": Vector3(0, 0, 0), "thigh_r": Vector3(-15, 0, 0), "calf_r": Vector3(10, 0, 0), "foot_r": Vector3(0, 0, 0)}


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func pose(B: Body, angs: Dictionary, off: Vector3) -> Dictionary:
	for j in Body.ORDER:
		B.ang[j] = Vector3.ZERO
	B.offset = off
	B.wep_on = false
	for j in angs:
		B.ang[j] = B.clamp_ang(j, angs[j])
	B.fk()
	return B.to_dict()


## one static pose held 2 s (the second card of the same pose is where the plant's read ends), the plants on the set `props`
func scene(angs: Dictionary, props: Array, plants: Array) -> Scene:
	var B := body()
	var S := Scene.new()
	S.fps = 30
	S.pin = false
	S.on_floor = true
	S.props = props
	S.add("stand", pose(B, angs, Vector3.ZERO))
	S.add("end", pose(B, angs, Vector3.ZERO))
	S.cards[0]["move"] = 0.0
	S.cards[0]["hold"] = 2.0
	S.cards[1]["move"] = 0.0
	S.cards[1]["hold"] = 0.0
	S.plants = FootPlant.from_file(plants)
	return S


## a foot's three sole contacts: the heel, and the ball and toe tip less their rest heights along the ball's up (at rest each
## is on the floor: the body's own grounding measures them so)
func sole_pts(B: Body, sd: String) -> Array:
	var gb: Quaternion = B.G["ball" + sd]
	return [FootRoll.heel_point(B, sd), (B.P["ball" + sd] as Vector3) - gb * Vector3(0, (B.p0["ball" + sd] as Vector3).y, 0), (B.E["ball" + sd] as Vector3) - gb * Vector3(0, (B.e0["ball" + sd] as Vector3).y, 0)]


## a point's height over the surface under it (m; 0 = on it, < 0 = into it)
func clearance(props: Array, pt: Vector3) -> float:
	return pt.y - float(Props.surface_below(props, pt)["y"])


## the times of the planted frames at 120 Hz (the plant's weight is 1 over [T0, T1])
func plant_times(S: Scene) -> Array:
	var out := []
	var n := int(ceilf(S.length() * HZ - 1e-6)) + 1
	for k in n:
		var t := float(k) / float(HZ)
		if t >= T0 - 1e-9 and t <= T1 + 1e-9:
			out.append(t)
	return out


## the step scene's measures on every planted frame, into m (a dictionary: a closure would copy a number, not keep it)
func measure_step(S: Scene, B: Body, m: Dictionary) -> void:
	for t in plant_times(S):
		S.apply(B, t)
		var props: Array = S.solid_props()
		m["n"] = int(m["n"]) + 1
		for sd in ["_l", "_r"]:
			for q in sole_pts(B, sd):
				var c := clearance(props, q)
				m["sole" + sd] = maxf(float(m["sole" + sd]), absf(c))
				m["pen"] = maxf(float(m["pen"]), -c)
			for p in props:
				m["axis"] = maxf(float(m["axis"]), Props.depth(p, B.P["foot" + sd], B.P["ball" + sd], 0.0))
			var reach := (B.p0["calf" + sd] as Vector3).distance_to(B.p0["thigh" + sd] as Vector3) + (B.p0["foot" + sd] as Vector3).distance_to(B.p0["calf" + sd] as Vector3)
			var got := (B.P["thigh" + sd] as Vector3).distance_to(B.P["foot" + sd] as Vector3)
			m["reach"] = maxf(float(m["reach"]), got - reach)
		for i in S.plant_last:
			m["miss"] = maxf(float(m["miss"]), float(S.plant_last[i]["miss"]))
		m["pelvis"] = B.offset.y


func _init() -> void:
	var B := body()

	# 1 + 2 STEP ------------------------------------------------------------------------------------------------
	# the stride's left foot is over tread 1: the stairs' origin puts the tread's centre (0.14 m in) under the heel-ball middle
	var probe := scene(STRIDE, [], [])
	probe.apply(B, 0.0)
	var plants := [{"foot": "foot_l", "t0": T0, "t1": T1}, {"foot": "foot_r", "t0": T0, "t1": T1}]
	# the tread is centred under the planted left sole: a first pass plants it (the heel's place moves when the foot is flattened),
	# the second pass puts the tread's centre (0.14 m in) under the middle of that sole's heel and toe
	var stairs := Props.make("stairs_code", Props.xf_at(Vector3(0.089, 0, 0.329)))
	var first := scene(STRIDE, [stairs], plants)
	first.apply(B, 1.0)
	var lmid: Vector3 = (sole_pts(B, "_l")[0] + sole_pts(B, "_l")[2]) * 0.5
	stairs = Props.make("stairs_code", Props.xf_at(Vector3(lmid.x, 0, lmid.z - 0.14)))
	var S1 := scene(STRIDE, [stairs], plants)
	var m := {"n": 0, "sole_l": 0.0, "sole_r": 0.0, "pen": 0.0, "axis": 0.0, "miss": 0.0, "reach": -INF, "pelvis": 0.0}
	var m_sole := {"sole_l": 0.0, "sole_r": 0.0}
	measure_step(S1, B, m)
	var S0 := scene(STRIDE, [stairs], [])
	S0.apply(B, T0)
	var played := B.offset.y
	print("step: %d planted frames at 120 Hz; left sole on tread 1 (17.8 cm) worst |clearance| %.2f mm; right on the floor %.2f mm" % [int(m["n"]), float(m["sole_l"]) * 1000.0, float(m["sole_r"]) * 1000.0])
	print("step: worst sole penetration %.2f mm; foot axis inside a prop %.2f mm; worst plant miss %.3f mm; worst leg overstretch %.2f mm" % [float(m["pen"]) * 1000.0, float(m["axis"]) * 1000.0, float(m["miss"]) * 1000.0, float(m["reach"]) * 1000.0])
	print("step: hips played %.1f mm, planted %.1f mm (drop %.1f mm)" % [played * 1000.0, float(m["pelvis"]) * 1000.0, (played - float(m["pelvis"])) * 1000.0])
	ok(float(m["sole_l"]) <= 0.003 and float(m["sole_r"]) <= 0.003, "1 every planted sole point is within 3 mm of its surface on every frame (left on the tread, right on the floor)")
	ok(float(m["pen"]) <= 0.002, "1 no sole point is under its surface by more than 2 mm")
	ok(float(m["axis"]) <= 0.002, "1 the foot's axis is inside no prop by more than 2 mm")
	ok(float(m["miss"]) <= 0.001, "2 the planted ankles hit their targets within 1 mm")
	ok(float(m["reach"]) <= 1e-6, "2 no ground-planted leg is stretched past its length")
	ok(float(m["pelvis"]) < played - 0.001, "2 the hips drop with the plant (the played hips are out of the lower foot's reach)")

	# 4 FLAT GROUND ---------------------------------------------------------------------------------------------
	var table := Props.make("table", Props.xf_at(Vector3(10, 0, 10)))
	var A := scene(STANCE, [], plants)
	var Z := scene(STANCE, [table], plants)
	var same := true
	var nflat := 0
	for t in plant_times(A):
		A.apply(B, t)
		var a := [B.to_dict(), B.offset]
		Z.apply(B, t)
		var b := [B.to_dict(), B.offset]
		nflat += 1
		if var_to_str(a) != var_to_str(b):
			same = false
	ok(same, "4 flat floor with a table 10 m away: all %d planted frames are bit for bit the same as with no props" % nflat)

	# 3 RAMP ----------------------------------------------------------------------------------------------------
	var ramp := Props.make("ramp15", Props.xf_at(Vector3(0, 0, 0)))
	var R := scene(RAMP_STANCE, [ramp], plants)
	var worst_ang := 0.0
	var worst_sole := 0.0
	var worst_lim := 0.0
	var slope_deg := 0.0
	var nr := 0
	for t in plant_times(R):
		R.apply(B, t)
		var props: Array = R.solid_props()
		nr += 1
		var ground_n: Vector3 = Props.surface_below(props, FootRoll.heel_point(B, "_l"))["n"]
		slope_deg = rad_to_deg(acos(clampf(ground_n.dot(Vector3.UP), -1.0, 1.0)))
		for sd in ["_l", "_r"]:
			var sole_n: Vector3 = (B.G["foot" + sd] as Quaternion) * Vector3.UP
			worst_ang = maxf(worst_ang, rad_to_deg(acos(clampf(sole_n.normalized().dot(ground_n.normalized()), -1.0, 1.0))))
			for q in sole_pts(B, sd):
				worst_sole = maxf(worst_sole, absf(clearance(props, q)))
			for j in ["thigh" + sd, "calf" + sd, "foot" + sd, "ball" + sd]:
				worst_lim = maxf(worst_lim, ((B.clamp_ang(j, B.ang[j]) as Vector3) - (B.ang[j] as Vector3)).length())
	print("ramp: %d planted frames; the ramp is %.2f deg; worst sole-to-ramp angle %.2f deg; worst sole point %.2f mm; worst joint past its limit %.3f deg" % [nr, slope_deg, worst_ang, worst_sole * 1000.0, worst_lim])
	ok(absf(slope_deg - 15.0) < 0.01, "3 the ramp is 15 degrees (%.2f)" % slope_deg)
	ok(worst_ang <= 3.0, "3 each sole is parallel to the ramp within 3 deg on every frame (worst %.2f)" % worst_ang)
	ok(worst_sole <= 0.003, "3 each sole point is within 3 mm of the ramp on every frame (worst %.2f mm)" % (worst_sole * 1000.0))
	ok(worst_lim <= 0.01, "3 no ankle, ball, calf or thigh is past its limit (worst %.3f deg)" % worst_lim)

	# 5 SNAP ON A STEP ------------------------------------------------------------------------------------------
	var box := Props.make("step_code", Props.xf_at(Vector3(0, 0, 0.04)))
	var SB := body()
	var stand := pose(SB, {}, Vector3.ZERO)
	var lifted := stand.duplicate(true)
	lifted["offset"] = [0.0, float((stand["offset"] as Array)[1]) + 0.3, 0.0]
	var snapped := FloorSnap.snapped_pose(SB, lifted, [box])
	SB.from_dict(snapped)
	SB.props = [box]
	SB.fk()
	var low := INF
	for sd in ["_l", "_r"]:
		for q in sole_pts(SB, sd):
			low = minf(low, clearance([box], q))
	var dropped := float((lifted["offset"] as Array)[1]) - float((snapped["offset"] as Array)[1])
	print("snap: lifted 30 cm; the lowest sole point is %.2f mm over the top after the snap; the root moved down %.1f mm (30 cm less the 17.8 cm step)" % [low * 1000.0, dropped * 1000.0])
	ok(absf(low) <= 0.001, "5 after the snap the lowest sole point is on the top (within 1 mm)")
	ok(absf(dropped - (0.3 - TREAD)) <= 0.001, "5 the root moved down 0.122 m, to the step (within 1 mm)")

	# 6 SCREENSHOT: the stride on the stairs in the app, a whole-body side view (needs a window; POSER_STAIRS_PNG names the file)
	var png := OS.get_environment("POSER_STAIRS_PNG")
	if png != "" and DisplayServer.get_name() != "headless":
		await shot(S1, png)
		print("screenshot: %s" % png)

	print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the app with the scene S (the stride on the stairs), its camera on the +X side looking back at the body: the feet along Z
func shot(S: Scene, png: String) -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.S = S
	m._rebuild_cards()
	m.sel_card = 0
	m.playhead = 1.0
	m._refresh()
	m._turn_to(90.0, -4.0, 4.8, Vector3(0.09, 0.85, 0.42), false)   # the whole body (1.8 m) and the stairs in the free view
	m._refresh()
	await idle(4)
	get_root().get_texture().get_image().save_png(png)
