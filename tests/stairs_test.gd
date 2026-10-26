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
##   7 TOE BEND (a box step, 17.8 cm top, front edge at z = +0.2): the left foot is planted with its ball 2 cm short of the front
##     edge and its toes past it. On every planted frame: the ball's contact is on the top within 3 mm and the heel too; the
##     toes bend DOWN over the edge at least 10 deg (the ball joint's bend, within its -30 deg limit); the toe tip is 3 cm or
##     more below the top; the foot's axis is inside no prop by more than 2 mm.
##   8 WEDGE (ramp15 is a wedge, not a slab): its top is on the floor at the low end (within 0.5 mm of the formula 0.00268 m at
##     1 cm from the end, so no lip), 0.2679 m at the middle, 0.5332 m at 1 cm from the high end.
##   3 RAMP (ramp15, 15 degrees): both feet planted at mid-ramp. On every planted frame: each sole's normal is within 3 deg of
##     the ramp's normal, each sole point within 3 mm of the ramp, and no ankle, ball, calf or thigh is past its limit (the
##     clamp moves none of them by more than 0.01 deg). The ramp's slope is read from the ground's normal and must be 15 deg.
##   4 FLAT GROUND: the stance plant on flat floor with a table 10 m away (no prop under the feet) plays every planted frame
##     bit for bit the same as the same scene with no props (the body dictionary and the offset).
##   5 SNAP ON A STEP: a standing pose (both feet flat on a box step's 17.8 cm top) lifted 30 cm: after FloorSnap with the
##     set, the lowest sole point is on the top to within 1 mm, and the root moved down 0.30 - 0.178 = 0.122 m to within 1 mm.
##   6 PLACEMENT (windowed run only; POSER_STAIRS_PNG names the screenshot): built through the app's own commands: the stairs
##     added with the app's add (_prop_add) and put under the stride; the Target dummy off; played at t = 1 s. Read from the
##     RENDERED mannequin's bones (the skeleton's global poses, not the body's numbers): each foot's sole points are heel
##     (ankle less its rest height along its up) and ball (ball joint less its rest height). The left heel and ball are on
##     tread 1 (their surface is at 17.8 cm) within 3 mm; the right heel and ball are on the floor within 3 mm. The rendered
##     ankles are within 1 mm of the body's (anti-vacuity: the bones are the body's). Then a whole-body side view is saved.
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

	# 7 TOE BEND ------------------------------------------------------------------------------------------------
	# the ball 2 cm short of a box step's front edge (z = +0.2 local), the toes past it: the ball stays on the top, the toes bend
	var c0 := scene(STRIDE, [], plants)
	c0.apply(B, T0)
	var ball_z := (sole_pts(B, "_l")[1] as Vector3).z
	var toe_box := Props.make("step_code", Props.xf_at(Vector3(0, 0, ball_z - 0.02 - 0.2)))
	var SO := scene(STRIDE, [toe_box], plants)
	var worst_ball := 0.0
	var worst_heel := 0.0
	var min_bend := INF
	var toe_low := INF
	var worst_axis := 0.0
	var ball_lim := 0.0
	var nt := 0
	for t in plant_times(SO):
		SO.apply(B, t)
		var props7: Array = SO.solid_props()
		nt += 1
		var sp := sole_pts(B, "_l")
		worst_heel = maxf(worst_heel, absf(clearance(props7, sp[0])))
		worst_ball = maxf(worst_ball, absf(clearance(props7, sp[1])))
		var r7: Dictionary = SO.plant_last.get(0, {})
		min_bend = minf(min_bend, float(r7.get("toe_bend", 0.0)))
		toe_low = minf(toe_low, TREAD - (sp[2] as Vector3).y)
		worst_axis = maxf(worst_axis, Props.depth(toe_box, B.P["foot_l"], B.E["ball_l"], 0.0))
		ball_lim = minf(ball_lim, (B.ang["ball_l"] as Vector3).x)
	print("toe: %d planted frames; heel %.2f mm, ball %.2f mm off the top (worst); toes bent %.1f deg at least; toe tip %.1f cm under the top at least; ball bend at most %.1f deg (limit -30); foot axis in the box %.2f mm" % [nt, worst_heel * 1000.0, worst_ball * 1000.0, min_bend, toe_low * 100.0, ball_lim, worst_axis * 1000.0])
	ok(worst_ball <= 0.003 and worst_heel <= 0.003, "7 the ball and the heel stay on the step's top within 3 mm on every frame (worst %.2f, %.2f mm)" % [worst_ball * 1000.0, worst_heel * 1000.0])
	ok(min_bend >= 10.0, "7 the toes bend down over the edge at least 10 deg on every frame (least %.1f deg)" % min_bend)
	ok(ball_lim >= -30.01, "7 the ball's bend stays within its limit (-30 deg; most %.2f)" % ball_lim)
	# the toes are ~7 cm long and stop at their -30 deg limit, so the tip can drop at most ~7 * sin 30 = 3.5 cm (+ ball give):
	# the old 5 cm bar was past what the joint allows (coordinator, 2026-10-19). 3 cm = bent to near the limit
	ok(toe_low >= 0.03, "7 the toe tip is 3 cm or more under the top it overhangs (%.1f cm)" % (toe_low * 100.0))
	ok(worst_axis <= 0.002, "7 the foot's axis is inside the step by no more than 2 mm (%.2f mm)" % (worst_axis * 1000.0))

	# 8 WEDGE: the ramp's top is a plane from the floor at its low end (no lip), 0.268 m at the middle
	var wedge := [Props.make("ramp15", Props.xf_at(Vector3(0, 0, 0)))]
	var top_lo := float(Props.surface_below(wedge, Vector3(0, 1.0, -0.99))["y"])
	var top_mid := float(Props.surface_below(wedge, Vector3(0, 1.0, 0.0))["y"])
	var top_hi := float(Props.surface_below(wedge, Vector3(0, 1.0, 0.99))["y"])
	print("wedge: top %.2f mm at 1 cm from the low end, %.2f mm at the middle, %.2f mm at 1 cm from the high end" % [top_lo * 1000.0, top_mid * 1000.0, top_hi * 1000.0])
	ok(absf(top_lo - 0.00268) <= 0.0005, "8 the wedge's top is on the floor at its low end (no lip): %.2f mm at 1 cm from it" % (top_lo * 1000.0))
	ok(absf(top_mid - 0.26795) <= 0.0005, "8 the wedge's top is 26.8 cm up at the middle (%.2f mm)" % (top_mid * 1000.0))
	ok(absf(top_hi - 0.53322) <= 0.0005, "8 the wedge's top is 53.3 cm up 1 cm from the high end (%.2f mm)" % (top_hi * 1000.0))

	# 6 PLACEMENT, in the app, on the rendered bones (windowed run only); the whole-body side view is saved beside it
	var png := OS.get_environment("POSER_STAIRS_PNG")
	if DisplayServer.get_name() != "headless":
		await app_placement(png)
	else:
		print("placement: skipped (needs the app's window to read the rendered bones)")

	print("RESULT %s (%d failed)" % ["PASS" if fails == 0 else "FAIL", fails])
	TestFiles.cleanup()
	quit(0 if fails == 0 else 1)


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the stride on the stairs, built in the app (its own add and its own pose), read on the rendered skeleton, then a side view
func app_placement(png: String) -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.dummy_on = false   # Target dummy: off
	var plants := [{"foot": "foot_l", "t0": T0, "t1": T1}, {"foot": "foot_r", "t0": T0, "t1": T1}]
	m.S = scene(STRIDE, [], plants)
	m._rebuild_cards()
	m.sel_card = 0
	m._prop_add("stairs_code")   # the app's add: the stairs go in front of the body
	var sp := 0   # the stairs are the first prop
	# put tread 1 under the left sole, as a user drags it: a first guess, the body posed at t = 1 s, then the tread centred on the sole
	m.S.props[sp]["xf"] = Props.xf_at(Vector3(0.089, 0, 0.329))
	m._props_show()   # the app's own refresh after a move: the drawn stairs and the body's set follow the prop
	m.S.apply(m.B, 1.0)
	var lm: Vector3 = (sole_pts(m.B, "_l")[0] + sole_pts(m.B, "_l")[2]) * 0.5
	m.S.props[sp]["xf"] = Props.xf_at(Vector3(lm.x, 0, lm.z - 0.14))
	m._props_show()
	m.playhead = 1.0
	m._refresh()
	await idle(4)
	var skel: Skeleton3D = m.skel
	skel.force_update_all_bone_transforms()
	var rend := {}
	for j in ["foot_l", "ball_l", "foot_r", "ball_r"]:
		rend[j] = skel.global_transform * skel.get_bone_global_pose(int(m.bone_idx[j]))
	# the body's frame from the rendered bone: the bone's world basis is its body frame times its rest basis, so the frame is
	# rendered * rest^-1 (checked against the body's own G for every bone read, to 0.5 deg: the bones are the body's)
	var frame := {}
	var frame_err := 0.0
	for j in ["foot_l", "ball_l", "foot_r", "ball_r"]:
		var rb_: Basis = skel.get_bone_global_rest(int(m.bone_idx[j])).basis
		var fr: Basis = (rend[j] as Transform3D).basis * rb_.inverse()
		frame[j] = fr.get_rotation_quaternion()
		frame_err = maxf(frame_err, rad_to_deg((frame[j] as Quaternion).angle_to(m.B.G[j] as Quaternion)))
	# the rendered sole points: the ankle less its rest height along its up, the ball joint less its rest height along its up
	var mapping := 0.0
	for j in ["foot_l", "ball_l", "foot_r", "ball_r"]:
		mapping = maxf(mapping, ((rend[j] as Transform3D).origin as Vector3).distance_to(m.B.P[j]))
	var heel_l: Vector3 = (rend["foot_l"] as Transform3D).origin - (frame["foot_l"] as Quaternion) * Vector3(0, float((m.B.p0["foot_l"] as Vector3).y), 0)
	var ball_l: Vector3 = (rend["ball_l"] as Transform3D).origin - (frame["ball_l"] as Quaternion) * Vector3(0, float((m.B.p0["ball_l"] as Vector3).y), 0)
	var heel_r: Vector3 = (rend["foot_r"] as Transform3D).origin - (frame["foot_r"] as Quaternion) * Vector3(0, float((m.B.p0["foot_r"] as Vector3).y), 0)
	var ball_r: Vector3 = (rend["ball_r"] as Transform3D).origin - (frame["ball_r"] as Quaternion) * Vector3(0, float((m.B.p0["ball_r"] as Vector3).y), 0)
	var props_now: Array = m.S.solid_props()
	var top_l := [float(Props.surface_below(props_now, heel_l)["y"]), float(Props.surface_below(props_now, ball_l)["y"])]
	var dev_l := maxf(absf(heel_l.y - top_l[0]), absf(ball_l.y - top_l[1]))
	var dev_r := maxf(absf(heel_r.y), absf(ball_r.y))
	print("placement (rendered bones): left heel %.1f mm, ball %.1f mm, their surface %.1f / %.1f mm; right heel %.1f mm, ball %.1f mm; rendered vs body ankle/ball %.3f mm" % [heel_l.y * 1000.0, ball_l.y * 1000.0, top_l[0] * 1000.0, top_l[1] * 1000.0, heel_r.y * 1000.0, ball_r.y * 1000.0, mapping * 1000.0])
	ok(mapping <= 0.001 and frame_err <= 0.5, "6 the rendered bones are the body's: ankles and balls within 1 mm (worst %.3f mm), frames within 0.5 deg (worst %.3f deg)" % [mapping * 1000.0, frame_err])
	ok(absf(top_l[0] - TREAD) <= 0.001 and absf(top_l[1] - TREAD) <= 0.001, "6 the left foot's surface is tread 1 at 17.8 cm (%.1f and %.1f mm)" % [top_l[0] * 1000.0, top_l[1] * 1000.0])
	ok(dev_l <= 0.003, "6 the left heel and ball sit on tread 1 within 3 mm (worst %.2f mm)" % (dev_l * 1000.0))
	ok(dev_r <= 0.003, "6 the right heel and ball sit on the floor within 3 mm (worst %.2f mm)" % (dev_r * 1000.0))
	if png != "":
		m._turn_to(90.0, -4.0, 4.8, Vector3(0.09, 0.85, 0.42), false)   # the whole body (1.8 m) and the stairs in the free view
		m._refresh()
		await idle(4)
		get_root().get_texture().get_image().save_png(png)
		print("screenshot: %s" % png)
