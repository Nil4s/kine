## godot --path . -s tests/contactik_test.gd     (ROADMAP 88; needs a window for the screenshot)
## Contact-aware hand IK (scripts/contact_ik.gd): a hand dragged on a WALL slides along it with its palm on the face, never
## through it; contact off is the plain pull, byte for byte; one undo step per drag; a hand flat on a TABLE, whole body.
## Bars: palm gap within 3 mm of the face at every step; no penetration (capsule gap >= -1 mm); the elbow inside its joint
## limits; the wrist follows the mouse (miss <= 5 mm); 30 cm of slide. The hand's radius is Body.rad (the capsule).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var B: Body = m.B
	var h := "hand_r"
	var mid: String = B.parent[h]
	var snap: Dictionary = B.to_dict()
	var hp0: Vector3 = B.P[h]
	print("hand %s at %s, radius %.3f m" % [h, hp0, B.rad[h]])

	# ---- 1. THE WALL: a wall turned to run along Z, its face at x = -0.55 (the body side of it is the hand's side), the mouse
	# 9 cm off the face; then the hand is pulled 30 cm along the wall
	var face_x := -0.55   # the hand sits at 5 cm off it on the body side: the arm is bent, the slide is in reach
	var wall := Props.make("wall", Props.xf_at(Vector3(face_x - 0.075, 0, hp0.z), 90.0))
	m.S.props = [wall]
	B.props = m.S.solid_props()
	var faces := ContactIK.surfaces(m.S.props)
	var raw := Vector3(face_x + 0.09, hp0.y, hp0.z + 0.06)   # the stroke starts clear of the shoulder limit (it clamps just past -6 cm)
	for i in 80:   # the mouse holds still: the limb settles (one solve a frame)
		ContactIK.reach(B, h, raw, faces)
	var r := ContactIK.reach(B, h, raw, faces)
	var c: Vector3 = r["c"]
	var n: Vector3 = r["n"]
	print("approach: palm gap %.2f mm, miss %.2f mm, face normal %s" % [ContactIK.palm_gap(B, h, c, n) * 1000.0, float(r["miss"]) * 1000.0, n])
	ok(absf(ContactIK.palm_gap(B, h, c, n)) <= 0.003, "approach: the palm lands on the wall, gap %.2f mm (bar 3 mm)" % (ContactIK.palm_gap(B, h, c, n) * 1000.0))

	var worst_palm := 0.0
	var worst_tip := INF
	var worst_arm := INF
	var worst_miss := 0.0
	var worst_elbow := 0.0
	var z0 := (B.P[h] as Vector3).z
	for step in 30:   # 30 cm along the wall, 1 cm a step
		raw.z += 0.01
		r = ContactIK.reach(B, h, raw, faces)
		c = r["c"]
		n = r["n"]
		worst_palm = maxf(worst_palm, absf(ContactIK.palm_gap(B, h, c, n)))
		worst_tip = minf(worst_tip, ContactIK.tip_gap(B, h, c, n))
		worst_arm = minf(worst_arm, ContactIK.arm_gap(B, h, c, n))
		worst_miss = maxf(worst_miss, float(r["miss"]))
		var ang: Vector3 = B.ang[mid]
		worst_elbow = maxf(worst_elbow, (B.clamp_ang(mid, ang) - ang).length())
	var slid := (B.P[h] as Vector3).z - z0
	print("slide: %.1f cm along the wall; worst palm gap %.2f mm; worst capsule gap %.2f mm; worst miss %.2f mm; elbow off limits %.4f deg"
		% [slid * 100.0, worst_palm * 1000.0, worst_tip * 1000.0, worst_miss * 1000.0, worst_elbow])
	ok(slid >= 0.29, "slide: the hand moved %.1f cm along the wall (bar 30 cm)" % (slid * 100.0))
	ok(worst_palm <= 0.003, "palm: within %.2f mm of the wall plane at every step (bar 3 mm)" % (worst_palm * 1000.0))
	ok(worst_arm >= -0.001, "arm: every arm capsule (upper arm, forearm, hand) clear of the wall: worst %.2f mm (bar -1 mm)" % (worst_arm * 1000.0))
	ok(Rulebook.prop_hits(m.S.props, B).is_empty(), "app check: no body part in the wall after the slide (the app's own check)")
	ok(worst_tip >= -0.001, "no penetration: worst capsule gap %.2f mm (bar -1 mm)" % (worst_tip * 1000.0))
	ok(worst_miss <= 0.005, "follows the mouse: worst wrist miss %.2f mm (bar 5 mm)" % (worst_miss * 1000.0))
	ok(worst_elbow < 1e-3, "elbow: inside its joint limits at every step (worst excess %.5f deg)" % worst_elbow)

	# ---- 2. CONTACT OFF is the old pull, byte for byte: the drag's wrist target, through B.reach
	B.from_dict(snap)
	m.S.props = [wall]
	B.props = m.S.solid_props()
	m.ik_contact = false
	m.sel = h
	m.dragging = "joint"
	m._grab = Vector3(NAN, NAN, NAN)
	m._drag_joint(Vector2(30, -10), false, false, false)
	var via_drag := JSON.stringify(B.to_dict())
	var g: Vector3 = m._grab
	B.from_dict(snap)
	m.S.props = [wall]
	B.props = m.S.solid_props()
	B.reach(h, g)
	ok(JSON.stringify(B.to_dict()) == via_drag, "contact off: the drag is B.reach to the cursor, byte for byte")

	# ---- 3. CONTACT ON through the real drag: one drag, one undo step
	B.from_dict(snap)
	m.S.props = [wall]
	B.props = m.S.solid_props()
	m.ik_contact = true
	m.sel = h
	m.dragging = "joint"
	m._grab = Vector3(NAN, NAN, NAN)
	var undo_before: int = m.undo.size()
	m._push_undo()   # the press opens the drag's one undo step
	for i in 12:
		m._drag_joint(Vector2(4, 0), false, false, false)
	m._drag_joint(Vector2(0, 0), false, false, false)
	var r2 := ContactIK.reach(B, h, m._grab, ContactIK.surfaces(m.S.props))
	var undo_steps: int = m.undo.size() - undo_before
	ok(undo_steps == 1, "undo: the whole drag is one undo step (%d added)" % undo_steps)
	ok(bool(r2["on"]) and absf(ContactIK.palm_gap(B, h, r2["c"], r2["n"])) <= 0.003, "drag path: the palm is on the wall after the drag (gap %.2f mm)" % (ContactIK.palm_gap(B, h, r2["c"], r2["n"]) * 1000.0))
	m.ik_contact = false

	# ---- 4. A TABLE: the hand flat on its top, the arm bent, whole body in view
	# a standing body cannot reach a 75 cm top with its shoulder at 1.4 m: it SITS (the app's Sit-here pose, thighs and
	# calves at 90, pelvis on the seat, feet on the floor), a chair at the origin facing +Z, the table in front of it
	B.from_dict(snap)
	var pre: Dictionary = B.state()
	var chair := Props.make("chair", Props.xf_at(Vector3(0, 0, -0.13), 0.0))
	B.props = [chair]
	var fwd: Vector3 = ((chair["xf"] as Transform3D).basis * Vector3(0, 0, 1)).normalized()
	var sup: Dictionary = Props.supports(chair)[0]
	var seat: Vector3 = (sup["xf"] as Transform3D) * Vector3((sup["c"] as Vector2).x, 0.0, (sup["c"] as Vector2).y)
	var at := seat - fwd * 0.05
	B.set_ang("pelvis", Vector3(0, 0, rad_to_deg(atan2(fwd.x, fwd.z))))
	for sd in ["_l", "_r"]:
		B.set_ang("thigh" + sd, Vector3(90, 0, 0))
		B.set_ang("calf" + sd, Vector3(90, 0, 0))
	B.offset = Vector3(at.x - (B.p0["pelvis"] as Vector3).x, B.offset.y, at.z - (B.p0["pelvis"] as Vector3).z)
	B.fk()
	B.ground()
	var table_at := Vector3(0, 0, 0.45)   # its near edge 10 cm past the chair, clear of the torso
	var table := Props.make("table", Props.xf_at(table_at, 0.0))
	m.S.props = [chair, table]
	B.props = [chair]
	var tfaces := ContactIK.surfaces(m.S.props)
	var traw := Vector3(-0.3, 1.1, 0.22)
	# the elbow up and back (the pole the arm bends to on a table): the forearm stays over the top, not through it
	var shoulder_p: Vector3 = B.P[B.parent[mid]]
	LimbIK.solve(B, h, Vector3(-0.3, 0.8, 0.22), shoulder_p + Vector3(0.0, 0.6, -0.1))
	for i in 80:
		ContactIK.reach(B, h, traw, tfaces)
	var rt := ContactIK.reach(B, h, traw, tfaces)
	var tc: Vector3 = rt["c"]
	var tn: Vector3 = rt["n"]
	var wrist: Vector3 = B.P[h]
	var top_y := 0.75
	var bend := rad_to_deg((B.P[h] as Vector3 - B.P[mid]).angle_to(B.P[mid] - B.P[B.parent[mid]]))
	print("table: palm gap %.2f mm, wrist %s, top at %.3f, forearm-upper arm angle %.1f deg (180 = straight)"
		% [ContactIK.palm_gap(B, h, tc, tn) * 1000.0, wrist, top_y, 180.0 - bend])
	ok(absf(ContactIK.palm_gap(B, h, tc, tn)) <= 0.003, "table: the palm is ON the top, gap %.2f mm (bar 3 mm)" % (ContactIK.palm_gap(B, h, tc, tn) * 1000.0))
	var d_wrist := maxf(float(B.rad[h]), float(B.rad["lowerarm_r"]) - 0.0005)
	ok(absf(wrist.y - (top_y + d_wrist)) <= 0.002, "table: the wrist sits one forearm radius (less 0.5 mm) above the top: %.4f m (bar 2 mm)" % (wrist.y - top_y))
	var arm_t := ContactIK.arm_gap(B, h, tc, tn)
	var hits: Array = Rulebook.prop_hits(m.S.props, B)
	print("table: arm gap %.2f mm; app check hits %s" % [arm_t * 1000.0, str(hits)])
	ok(arm_t >= -0.001, "table: every arm capsule (upper arm, forearm, hand) clear of the top: worst %.2f mm (bar -1 mm)" % (arm_t * 1000.0))
	ok(hits.is_empty(), "table: the app's own check reports no body part in the chair or table (%d hits)" % hits.size())
	ok(absf(wrist.x - table_at.x) <= 0.6 and absf(wrist.z - table_at.z) <= 0.35, "table: the hand is over the table top, not beside it")
	ok(180.0 - bend > 20.0 and 180.0 - bend < 150.0, "table: the arm is bent, not straight or folded (%.1f deg)" % (180.0 - bend))

	# the pose is kept as a card (the app's own path, as Sit here does), so the frames the screenshot waits for keep it
	m._use_card("hand flat on the table", pre)
	B.props = m.S.solid_props()
	# the whole body, three quarters from the front: the chair, the table, the arm bent on the top
	m.dummy_on = false   # the target dummy put away: the picture is the seated body and the table
	m._dummy_refresh()
	m.yaw = -35.0
	m.pitch = -10.0
	m.dist = 4.2
	m._cam()
	for i in 4:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/contactik.png")
	ok(img != null and img.get_width() > 0, "screenshot: saved to the jobs tmp folder")
	var hp_after: Vector3 = B.P[h]
	ok(absf(ContactIK.palm_gap(B, h, tc, tn)) <= 0.003 and absf(hp_after.y - (top_y + d_wrist)) <= 0.002, "placement: after the card, the hand is still on the table top (gap %.2f mm)" % (ContactIK.palm_gap(B, h, tc, tn) * 1000.0))

	print("%s  (%d fail)" % ["PASS" if fails == 0 else "FAIL", fails])
	TestFiles.cleanup()
	quit(fails)
