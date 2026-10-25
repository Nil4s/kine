## godot --path . -s tests/rigid_drop_test.gd     (ROADMAP 85: rigid prop physics; needs a window for the screenshot)
## RIGID PROP PHYSICS (scripts/rigid_drop.gd). A sword let go by a hand falls as a rigid body: it keeps the hand's velocity
## and spin at the let-go, falls under g = 9.81, hits the floor (restitution 0.5, friction 0.47: cited in rigid_drop.gd),
## and comes to rest. Simulated at a fixed 240 Hz step and BAKED on the drop card ("drop_rig"). Bars (stated before the run):
##   1 free fall from 1.0 m (lowest point) reaches the floor at sqrt(2h/g) = 0.4515 s within one 240 Hz step (4.17 ms)
##   2 the first bounce's apex is e^2 h = 0.25 m (bar 1 cm); the second contact comes after it
##   3 release velocity: the sword's velocity at the let-go (the bake's input) equals the hand's, within 1 %
##   4 at rest by 3 s: lowest point within 2 mm of y = 0, speed under 1 mm/s (COM over 10 ms)
##   5 a tilted drop (35 deg, one end first) ends LYING FLAT: both ends within 2 mm of the same height, lowest point 2 mm of 0
##   6 scrubbing: the pose at each time is byte-identical forwards and backwards; two runs of the sim are byte-identical
##   7 the scene: a sword put down on a floor card is baked (drop_rig); props_at follows the bake; save and load keep it
##     byte-identical; mirrored twice = the original; a box put down bakes nothing (its old fall is unchanged)
##   8 Put down is ONE undo step: undo removes the drop and its bake, redo brings it back
##   9 the render: a whole-body view with the sword lying on the floor and its fall path (trail) drawn; the screenshot
##     is written to $ZZ_PROPS_SHOT (default user://zz_props.png); the placement bar: its lowest end is on the floor
##     (y within 2 mm of 0) and inside the floor's frame in the view (the trail's first point is in the picture)
extends SceneTree

var fails := 0
var m: Node
var run_id := OS.get_process_id()
const H_DROP := 1.0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ends_of(xf: Transform3D, L: float) -> Array:
	var ax := xf.basis.x * (L * 0.5)
	return [xf.origin + ax, xf.origin - ax]


## a prop's transform (origin on the floor, the Props convention) as the sword's centre-of-mass transform
func com_of(xf: Transform3D) -> Transform3D:
	return RigidDrop.com_xf(xf, float(RigidDrop.sword_body()["R"]))


func lowest(xf: Transform3D, body: Dictionary) -> float:
	var e := ends_of(xf, float(body["L"]))
	return minf(e[0].y, e[1].y) - float(body["R"])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var body := RigidDrop.sword_body()
	var DT := RigidDrop.DT
	var g := RigidDrop.G

	# 1 free fall: flat, at rest, its lowest point 1.0 m up (centre at 1.0 + R)
	var f1 := RigidDrop.simulate(Vector3(0, H_DROP + float(body["R"]), 0), Quaternion.IDENTITY, Vector3.ZERO, Vector3.ZERO, body)
	var t_exp := sqrt(2.0 * H_DROP / g)
	var t_hit := float((f1["hits"][0] as Array)[0])
	ok(absf(t_hit - t_exp) <= DT, "1 free fall from 1.0 m: contact at %.4f s vs sqrt(2h/g) = %.4f s (bar one step %.2f ms; off %.2f ms)" % [t_hit, t_exp, DT * 1000.0, absf(t_hit - t_exp) * 1000.0])

	# 2 the bounce: the apex after the first contact vs e^2 h (the rod flat: both ends hit together)
	var h2 := 0.0
	var t2 := float((f1["hits"][1] as Array)[0]) if (f1["hits"] as Array).size() > 1 else -1.0
	var k0 := int(round(t_hit / DT))
	var k1 := int(round(t2 / DT)) if t2 > 0.0 else k0
	var n1: int = f1["steps"]
	for k in range(k0, mini(k1, n1 - 1)):
		var xf := RigidDrop.pose_at(f1["poses"], float(k) * DT)
		h2 = maxf(h2, xf.origin.y - float(body["R"]) - 0.0)
	var apex := h2 - 0.0
	var want := RigidDrop.E * RigidDrop.E * H_DROP
	ok(t2 > 0.0 and absf(apex - want) < 0.01, "2 first bounce: apex %.4f m vs e^2 h = %.4f m (bar 1 cm); second contact at %.3f s" % [apex, want, t2])

	# 3 release velocity: the bake starts with the hand's velocity (checked in the scene part, bar 3)

	# 4 at rest by 3 s, lying on the floor
	var xf3 := RigidDrop.pose_at(f1["poses"], 3.0)
	var xf299 := RigidDrop.pose_at(f1["poses"], 2.99)
	var sp := (xf3.origin - xf299.origin).length() / 0.01
	var low := lowest(xf3, body)
	ok(absf(low) < 0.002 and sp < 0.001, "4 at rest by 3 s: lowest point %.4f mm from the floor (bar 2 mm), speed %.4f mm/s (bar 1 mm/s), settled at %.3f s" % [low * 1000.0, sp * 1000.0, float(f1["t_rest"])])

	# 5 a tilted drop: 35 deg from the horizontal, the +X end first (the axis tipped down toward +X)
	var tilt := Quaternion(Vector3.BACK, deg_to_rad(35.0))
	var f5 := RigidDrop.simulate(Vector3(0, 1.0 + float(body["R"]) + 0.3, 0), tilt, Vector3.ZERO, Vector3.ZERO, body)
	var xf5 := RigidDrop.pose_at(f5["poses"], 3.0)
	var e5 := ends_of(xf5, float(body["L"]))
	var flat := absf(e5[0].y - e5[1].y)
	ok(flat < 0.002 and absf(lowest(xf5, body)) < 0.002, "5 tilted 35 deg: ends %.4f and %.4f m high (bar 2 mm apart), lowest point %.4f mm from the floor, at rest %.3f s" % [e5[0].y, e5[1].y, lowest(xf5, body) * 1000.0, float(f5["t_rest"])])

	# 6 determinism: forwards then backwards, the same bytes; two runs, the same bytes
	var fwd := []
	for i in range(0, 3001, 1):
		fwd.append(var_to_bytes(RigidDrop.pose_at(f1["poses"], float(i) * 0.001)))
	var same := true
	for i in range(3000, -1, -1):
		same = same and var_to_bytes(RigidDrop.pose_at(f1["poses"], float(i) * 0.001)) == fwd[i]
	var f1b := RigidDrop.simulate(Vector3(0, H_DROP + float(body["R"]), 0), Quaternion.IDENTITY, Vector3.ZERO, Vector3.ZERO, body)
	ok(same and var_to_bytes(f1["poses"]) == var_to_bytes(f1b["poses"]), "6 scrubbing: 3001 poses forwards and backwards byte-identical; a second run of the sim too (%d steps)" % int(f1["steps"]))

	# 7 the scene: a sword held by the right hand over a moving card, put down onto the floor (Put down = Main._prop_put)
	var B: Body = m.B
	var c: Array = B.cap("hand_r")
	var mid: Vector3 = ((c[0] as Vector3) + (c[1] as Vector3)) / 2.0
	var S: Scene = Scene.new()
	S.name = "zz_props_rigid"
	S.fps = 60
	# the sword keyed in the hand at the first card: a prop with no key is put on the floor when a scene is opened, and
	# the pick-up would then grip it 1.4 m below the hand (the app's rule: a held prop keeps its keyed place)
	var sw := Props.make("sword", Props.xf_at(mid, 0.0))
	sw["keys"] = [{"t": 0.0, "pos": mid, "yaw": 0.0, "swing": 0.0}]
	S.props = [sw]
	S.on_floor = false
	S.pin = false
	S.add("rest", B.to_dict())
	for mv in [Vector3(1, 0, 0), Vector3(1, 0.25, 0), Vector3(1, 0, 0)]:
		B.offset += mv
		B.fk()
		S.add("m", B.to_dict())
	S.cards[0]["take"] = {"prop": 0, "hands": ["_r"]}
	S.cards[2]["flow"] = true
	m.S = S
	m._rebuild_cards()
	m.sel_card = 2
	m.playhead = S.times()[2][1]
	m._refresh()
	await idle(2)
	# the hand's velocity at the let-go, read the way the scene reads it (1/60 s before, to the let-go)
	var tb: float = S.times()[2][1]
	var tp := tb - 1.0 / 60.0
	S.apply(B, tp)
	var a := (S.props_at(tp, B)[0]["xf"] as Transform3D).origin
	S.apply(B, tb - 1e-9)
	var b := (S.props_at(tb - 1e-9, B)[0]["xf"] as Transform3D).origin
	var v_hand := (b - a) * 60.0
	S.apply(B, S.times()[0][1])
	var before: int = m.undo.size()
	m._prop_put()
	var after: int = m.undo.size()
	ok(after - before == 1, "8a Put down: %d undo step(s) added (bar exactly one)" % (after - before))
	S = m.S
	var d: Array = S._carry_data(B)
	var cs := S.carries()
	var k := -1
	for j in cs.size():
		if int(cs[j]["b"]) == 2:
			k = j
	ok(k >= 0 and (S.cards[2] as Dictionary).has("drop_rig"), "7a the sword put down on card 3 is baked on the card (drop_rig present)")
	var rig: Dictionary = d[k]["rig"]
	var inp: Array = rig["in"]
	var v_sim := Vector3(float(inp[7]), float(inp[8]), float(inp[9]))
	var ve := (v_sim - v_hand).length() / maxf(v_hand.length(), 1e-9)
	ok(v_hand.length() > 0.2 and ve < 0.01, "3 release velocity: the sword starts at %s m/s, the hand moves at %s m/s (off %.2f %%, bar 1 %%)" % [v_sim, v_hand, ve * 100.0])
	var rest_scene: Transform3D = com_of(S.props_at(tb + 5.0, B)[0]["xf"])
	var lo := lowest(rest_scene, body)
	ok(absf(lo) < 0.002, "  the sword at rest on the floor in the scene: its lowest point %.4f mm from y = 0 (bar 2 mm)" % (lo * 1000.0))
	var fall_ok := true
	for dt in [0.1, 0.5, 1.2]:
		var want_xf := RigidDrop.prop_xf(RigidDrop.pose_at(rig["poses"], dt), float(body["R"]))
		var got: Transform3D = S.props_at(tb + dt, B)[0]["xf"]
		fall_ok = fall_ok and got.origin.distance_to(want_xf.origin) < 1e-9 and got.basis.is_equal_approx(want_xf.basis)
	ok(fall_ok, "7b props_at follows the bake at 0.1, 0.5 and 1.2 s after the let-go (exact)")
	# save and load: the same bytes, the same pose
	var j1 := JSON.stringify(S.to_dict(B), "", false)
	var S2 := Scene.new()
	S2.from_dict(JSON.parse_string(j1))
	var j2 := JSON.stringify(S2.to_dict(B), "", false)
	var p2: Transform3D = S2.props_at(tb + 1.2, B)[0]["xf"]
	var fd := -1
	for i in mini(j1.length(), j2.length()):
		if j1[i] != j2[i]:
			fd = i
			break
	if fd >= 0:
		print("     first difference at %d: [%s] vs [%s]" % [fd, j1.substr(maxi(fd - 60, 0), 120), j2.substr(maxi(fd - 60, 0), 120)])
	ok(j1 == j2 and p2.origin.distance_to(RigidDrop.prop_xf(RigidDrop.pose_at(rig["poses"], 1.2), float(body["R"])).origin) < 1e-9, "7c save, load, save: the same JSON (%d bytes) and the same pose after the trip" % j1.length())
	# mirror twice = the original; once, the sword's x is the reflection
	var M1 := Scene.mirror_card(S.cards[2], B)
	var M2 := Scene.mirror_card(M1, B)
	var q1: Array = M1["drop_rig"]["poses"]
	var q0: Array = S.cards[2]["drop_rig"]["poses"]
	ok(var_to_bytes(M2["drop_rig"]) == var_to_bytes(S.cards[2]["drop_rig"]) and absf(float(q1[0]) + float(q0[0])) < 1e-9, "7d mirrored twice = the original bake; once, its x is reflected")
	# a box put down: no bake, its old plain fall unchanged
	var S3: Scene = Scene.new()
	S3.props = [Props.make("box", Props.xf_at(Vector3(mid.x, 0, mid.z), 0.0))]
	S3.add("a", B.to_dict())
	S3.cards[0]["take"] = {"prop": 0, "hands": ["_r"]}
	S3.cards[0]["drop"] = 0
	var nb := S3.bake_drop(B, 0)
	ok(not nb and not S3.cards[0].has("drop_rig"), "7e a box put down bakes nothing (only a rod drops as a rigid body)")

	# 8 one undo step: undo removes the drop and its bake; redo brings them back
	m._undo()
	var u: Scene = m.S
	ok(not u.cards[2].has("drop") and not u.cards[2].has("drop_rig"), "8b undo: the drop and its bake are gone from card 3")
	m._redo()
	ok(m.S.cards[2].has("drop") and m.S.cards[2].has("drop_rig"), "8c redo: the drop and its bake are back")

	# 9 the render: the sword on the floor, its fall path drawn, in a whole-body view
	m.S = S
	m._rebuild_cards()
	var end_t := S.length() - 0.001
	m.playhead = end_t
	m._refresh()
	m._props_pose()
	S.apply(B, tb)
	var hc: Array = B.cap("hand_r")
	print("     the right hand at the let-go: centre y %.3f m (capsule %s to %s)" % [((hc[0] as Vector3).y + (hc[1] as Vector3).y) * 0.5, hc[0], hc[1]])
	S.apply(B, tb - 1.0 / 60.0)
	var trail := ImmediateMesh.new()
	trail.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var first := Vector3.ZERO
	var tr_n := 0
	var t_end := tb + float(rig["poses"].size() / 7) * RigidDrop.DT
	var tt := tb - 1.0 / 60.0
	while tt <= t_end:
		S.apply(B, tt)   # the hand is read from the body posed at tt (props_at needs it while held)
		var p: Vector3 = com_of(S.props_at(tt, B)[0]["xf"]).origin
		if tr_n == 0:
			first = p
		trail.surface_add_vertex(p + Vector3.UP * 0.01)
		tr_n += 1
		tt += 1.0 / 60.0
	trail.surface_end()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.45, 0.1)
	trail.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = trail
	m.ui_props_root.add_child(mi)
	var at: Transform3D = com_of(S.props_at(end_t, B)[0]["xf"])
	m._turn_to(-22.0, -8.0, 5.2, Vector3(at.origin.x * 0.5, 0.5, at.origin.z * 0.5), false)
	await idle(20)
	var img := root.get_viewport().get_texture().get_image()
	var shot := OS.get_environment("ZZ_PROPS_SHOT")
	if shot == "":
		shot = "user://zz_props_%d.png" % run_id
	img.save_png(shot)
	var cam: Camera3D = m.cam
	var px: Vector2 = cam.unproject_position(first)
	var sp_: Vector2 = cam.unproject_position(at.origin)
	var in_view := Rect2(Vector2.ZERO, Vector2(img.get_size())).has_point(sp_) and Rect2(Vector2.ZERO, Vector2(img.get_size())).has_point(px)
	ok(in_view and absf(lo) < 0.002, "9 the render: sword and trail start in the frame (%s, %s), lowest point on the floor; shot %s" % [sp_, px, shot])
	print("     trail: %d samples over %.2f s, first at %s, rest at %s (playhead %.2f s of %.2f s)" % [tr_n, t_end - tb, first, at.origin, end_t, S.length()])

	print("RESULT: %d failure(s)" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
