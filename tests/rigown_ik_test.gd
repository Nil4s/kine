## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/rigown_ik_test.gd     (ROADMAP_400 track J, lane L78 RIGOWN3)
## The own rig, round 3: timeline key row + real Play, IK on marked chains (two-bone + pole, CCD tail), per-bone limits, root position keys,
## the human-only panels gated. Bars written and committed BEFORE the implementation; none edited after.
##   1 TIMELINE   keys at 0 and 10: the strip's own-rig key row lists frames [0,10]; the key diamond for frame 10 is drawn at x_of(10/30) within 0.5 px
##      and inside the strip, and the only marks are the two keys.
##   2 PLAY       the real Play path (m._toggle_play + m._process_body at 1/30 s): after 10 steps the playhead is frame 10 and tail_3 reads the keyed angle
##      within 1e-3 rad; after 5 steps half of it. Also in a scene with no cards (Play was refused before). Control: frame 0 does not read it.
##   3 LIMITS     per-bone euler limits (deg): FK past the limit is clamped to it (1e-3 deg), keys and the interpolated frames stay inside, IK stays inside;
##      the violation measure catches a planted over-limit pose (control); bad limits are refused.
##   4 IK 2-BONE  leg_fl (upper, lower, paw) with a pole: a target made by FORWARD kinematics of a different pose (independent chain product) is
##      reached within 1 mm; the knee is on the pole side, and with the pole flipped it is on the other side and the foot still within 1 mm.
##      A target 5 m away: reached=false, "out of reach", the limb points at it within 1 deg.
##   5 IK CHAIN   tail_1..tail_5 (CCD, limits +-30 deg): an FK-made target within 1 mm; limits never exceeded; a far target says out of reach.
##   6 ROOT KEYS  root position keys: at frame 5 the drawn root is at the lerp within 0.1 mm and every drawn joint moved by the same offset; frame 10 by Play.
##      Control: frame 0 is not moved. Saved and reopened, the pos keys, limits and chains come back identical.
##   7 GATES      the six human-only entry points (Check, human-limits Check, feasibility Check, contacts, retarget, keep balance) answer "not a human rig"
##      and change nothing: N of N. Control: with the rig not the active subject the contacts and balance toggles do run.
##   8 MANNY      the body's joint angles at frame 0 before the rig and after it is gone: difference 0.0.
extends SceneTree

var fails := 0
var m: Node
const PATH := "res://scenes/_wip/rigown_ik_test.json"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func rows() -> Array:
	var r := []
	var add := func(n: String, p: String, o: Vector3, eul: Vector3):
		r.append({"name": n, "parent": p, "xf": Transform3D(Basis.from_euler(eul), o)})
	add.call("root", "", Vector3(0, 0.5, 0), Vector3(0.0, 0.0, 0.0))
	add.call("hips", "root", Vector3(0, 0.05, 0), Vector3(0.1, 0.0, 0.0))
	add.call("spine_1", "hips", Vector3(0, 0.0, 0.15), Vector3(-0.05, 0.02, 0.0))
	add.call("spine_2", "spine_1", Vector3(0, 0.0, 0.15), Vector3(0.04, 0.0, 0.03))
	add.call("spine_3", "spine_2", Vector3(0, 0.0, 0.15), Vector3(0.0, 0.05, 0.0))
	add.call("neck_1", "spine_3", Vector3(0, 0.03, 0.12), Vector3(0.3, 0.0, 0.0))
	add.call("neck_2", "neck_1", Vector3(0, 0.0, 0.1), Vector3(0.2, 0.0, 0.05))
	add.call("skull", "neck_2", Vector3(0, 0.0, 0.08), Vector3(-0.4, 0.0, 0.0))
	add.call("jaw", "skull", Vector3(0, -0.03, 0.06), Vector3(0.5, 0.0, 0.0))
	for leg in ["fl", "fr", "hl", "hr"]:
		var front: bool = leg.begins_with("f")
		var side := 1.0 if leg.ends_with("l") else -1.0
		var top := "spine_3" if front else "hips"
		add.call("leg_%s_upper" % leg, top, Vector3(0.08 * side, -0.05, 0.0), Vector3(1.4, 0.0, 0.1 * side))
		add.call("leg_%s_lower" % leg, "leg_%s_upper" % leg, Vector3(0, 0.0, 0.2), Vector3(-0.5 if front else 0.6, 0.0, 0.0))
		add.call("leg_%s_paw" % leg, "leg_%s_lower" % leg, Vector3(0, 0.0, 0.2), Vector3(0.4, 0.02, 0.0))
		add.call("leg_%s_toe" % leg, "leg_%s_paw" % leg, Vector3(0, 0.0, 0.06), Vector3(0.2, 0.0, 0.0))
	var prev := "hips"
	for i in range(1, 6):
		add.call("tail_%d" % i, prev, Vector3(0, 0.0, -0.1 if i == 1 else -0.08), Vector3(0.15 + 0.02 * i, 0.03, 0.0))
		prev = "tail_%d" % i
	return r


func write_fixture(path: String) -> Error:
	var rt := Node3D.new()
	rt.name = "creature"
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	rt.add_child(sk)
	for r in rows():
		var i := sk.get_bone_count()
		sk.add_bone(r["name"])
		if r["parent"] != "":
			sk.set_bone_parent(i, sk.find_bone(r["parent"]))
		sk.set_bone_rest(i, r["xf"])
		sk.set_bone_pose_position(i, (r["xf"] as Transform3D).origin)
		sk.set_bone_pose_rotation(i, (r["xf"] as Transform3D).basis.get_rotation_quaternion())
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	rt.add_child(mi)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in [Vector3(-0.1, 0.5, 0), Vector3(0.1, 0.5, 0), Vector3(0, 0.7, 0)]:
		st.set_bones(PackedInt32Array([0, 1, 2, 3]))
		st.set_weights(PackedFloat32Array([0.25, 0.25, 0.25, 0.25]))
		st.add_vertex(p)
	mi.mesh = st.commit()
	mi.skin = sk.create_skin_from_rest_transforms()
	mi.skeleton = mi.get_path_to(sk)
	return GltfExport._write(rt, path)


## INDEPENDENT of CustomRig.globals: the chain product over the fixture rows; extra local rotations (bone -> Basis) after the rest; off added to the root
func world_of(bone: String, extra: Dictionary, off := Vector3.ZERO) -> Vector3:
	var by := {}
	for r in rows():
		by[r["name"]] = r
	var chain := []
	var c := bone
	while c != "":
		chain.push_front(by[c])
		c = by[c]["parent"]
	var g := Transform3D.IDENTITY
	for r in chain:
		var x: Transform3D = r["xf"]
		if extra.has(r["name"]):
			x = Transform3D(x.basis * (extra[r["name"]] as Basis), x.origin)
		if r["parent"] == "":
			x.origin += off
		g = g * x
	return g.origin


func drawn(n: String) -> Vector3:
	var nd: Node3D = m.rig_ui.nodes.get(n)
	return nd.global_position if nd != null else Vector3(INF, INF, INF)


func pose_extra() -> Dictionary:
	var e := {}
	for b in m.S.own_rig["pose"]:
		e[b] = Basis(m.S.own_rig["pose"][b] as Quaternion)
	return e


## where the rig's current pose puts a bone, by the independent chain product
func foot(bone: String) -> Vector3:
	return world_of(bone, pose_extra(), m.S.own_rig.get("pos", Vector3.ZERO))


func eul(bone: String) -> Vector3:
	var q: Quaternion = (m.S.own_rig["pose"] as Dictionary).get(bone, Quaternion.IDENTITY)
	return Basis(q).get_euler() * (180.0 / PI)


## how far outside [mn, mx] (deg) a rotation is, over the three axes
func over(q: Quaternion, mn: Vector3, mx: Vector3) -> float:
	var e := Basis(q).get_euler() * (180.0 / PI)
	var v := 0.0
	for i in 3:
		v = maxf(v, maxf(mn[i] - e[i], e[i] - mx[i]))
	return v


func ang_of(bone: String) -> float:
	return ((m.S.own_rig["pose"] as Dictionary).get(bone, Quaternion.IDENTITY) as Quaternion).get_angle()


func at(frame: int) -> void:
	m.playhead = float(frame) / 30.0
	m._refresh()


func play_steps(n: int) -> void:
	for i in n:
		m._process_body(1.0 / 30.0)


func body_ang() -> Dictionary:
	var d := {}
	for j in m.B.ang:
		d[j] = m.B.ang[j]
	return d


func _init() -> void:
	var glb := "user://rigown_ik/creature.glb"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://rigown_ik"))
	ok(write_fixture(glb) == OK, "0 fixture written")
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	m._turn_to(90.0, 0.0, 3.5, Vector3(0, 0.5, 0), false)
	m.playhead = 0.0
	m._refresh()
	await idle(2)
	var body0 := body_ang()
	var why: String = m.rig_import(glb)
	await idle(3)
	ok(why == "" and m.rig_ui.nodes.size() == 30, "0 rig imported, 30 joints drawn")
	m.S.loop = false

	# 3 limits (set first: everything after is inside them)
	var R: Dictionary = m.S.own_rig
	ok(CustomRig.set_limit(R, "tail_3", Vector3(-30, -30, -30), Vector3(30, 30, 30)) == "", "3 set_limit tail_3 answers ok")
	for t in ["tail_1", "tail_2", "tail_4"]:
		CustomRig.set_limit(R, t, Vector3(-30, -30, -30), Vector3(30, 30, 30))
	CustomRig.set_limit(R, "leg_fl_lower", Vector3(-80, -60, -60), Vector3(80, 60, 60))
	CustomRig.set_limit(R, "leg_fl_upper", Vector3(-80, -60, -60), Vector3(80, 60, 60))
	ok(CustomRig.set_limit(R, "nope", Vector3.ZERO, Vector3.ZERO) != "", "3 control: a limit on a bone that is not there is refused")
	ok(CustomRig.set_limit(R, "tail_2", Vector3(20, 0, 0), Vector3(-20, 0, 0)) != "", "3 control: min above max is refused")
	m.rig_ui.rotate_deg("leg_fl_lower", Vector3(120, 0, 0))
	var e1 := eul("leg_fl_lower")
	print("     FK leg_fl_lower asked 120 deg, limit 80: reads %.4f" % e1.x)
	ok(absf(e1.x - 80.0) < 1e-3, "3 FK past the limit is clamped to it (%.5f)" % e1.x)
	m.rig_ui.rotate_deg("leg_fl_lower", Vector3(-100, 0, 0))
	ok(absf(eul("leg_fl_lower").x + 80.0) < 1e-3, "3 FK below the limit is clamped to it")
	var wild := Quaternion(Basis.from_euler(Vector3(deg_to_rad(120), 0, 0)))
	var wo := over(wild, Vector3(-80, -60, -60), Vector3(80, 60, 60))
	ok(wo > 30.0, "3 control: the violation measure catches an unclamped 120 deg pose (%.1f deg over)" % wo)
	m.rig_ui.rotate_deg("leg_fl_lower", Vector3(0, 0, 0))

	# 1 + 2 keys, timeline, play
	at(0)
	m.rig_ui.cur = "tail_3"
	m.rig_ui.key_now()
	at(10)
	m.rig_ui.rotate_deg("tail_3", Vector3(20, 0, 0))   # inside the +-30 limit
	m.rig_ui.key_now()
	await idle(4)
	var tl = m.ui_timeline
	ok(tl.rig_key_frames() == [0, 10], "1 the strip's own-rig key row lists frames [0, 10] (%s)" % str(tl.rig_key_frames()))
	var x10: float = tl.x_of(10.0 / 30.0)
	var drawn_x: Array = tl.rk_drawn.map(func(p): return p.x)
	var best := 1e9
	for x in drawn_x:
		best = minf(best, absf(x - x10))
	print("     key diamonds drawn at x=%s; frame 10 expected %.2f (nearest %.3f px)" % [str(drawn_x), x10, best])
	ok(drawn_x.size() == 2 and best < 0.5 and x10 > 0.0 and x10 < tl.size.x, "1 the frame-10 key is drawn at x_of(10/30) within 0.5 px, inside the strip")
	var only := true
	for x in drawn_x:
		only = only and (absf(x - x10) < 0.5 or absf(x - tl.x_of(0.0)) < 0.5)
	ok(only, "1 the only marks are the two keys")

	# 2 play
	m.playhead = 0.0
	m._refresh()
	var a0 := ang_of("tail_3")
	m._toggle_play()
	ok(m.playing, "2 Play starts with an own rig keyed (%s)" % str(m.playing))
	play_steps(5)
	var a5 := ang_of("tail_3")
	play_steps(5)
	var a10 := ang_of("tail_3")
	var fr: int = m.rig_ui.frame_now()
	print("     real Play: frame %d, tail_3 angle frame0 %.5f, frame5 %.5f, frame10 %.5f (keyed %.5f)" % [fr, a0, a5, a10, deg_to_rad(20)])
	ok(fr == 10 and absf(a10 - deg_to_rad(20)) < 1e-3, "2 real Play reaches the keyed angle at frame 10 within 1e-3 rad")
	ok(absf(a5 - deg_to_rad(10)) < 1e-3, "2 real Play at frame 5 is halfway within 1e-3 rad")
	ok(absf(a0) < 1e-3 and absf(a0 - a10) > 0.2, "2 control: frame 0 does not read the keyed angle")
	if m.playing:
		m._toggle_play()
	var keep_cards: Array = m.S.cards.duplicate(true)
	m.S.cards.clear()
	m.playhead = 0.0
	m._refresh()
	m._toggle_play()
	play_steps(10)
	ok(m.rig_ui.frame_now() == 10 and absf(ang_of("tail_3") - deg_to_rad(20)) < 1e-3, "2 Play also works in a scene with no cards (frame %d)" % m.rig_ui.frame_now())
	if m.playing:
		m._toggle_play()
	m.S.cards = keep_cards
	m.playhead = 0.0
	m._refresh()

	# 3 keys + interpolation inside limits
	m.rig_ui.cur = "tail_3"
	at(10)
	m.rig_ui.rotate_deg("tail_3", Vector3(60, 0, 0))   # past the +30 limit
	m.rig_ui.key_now()
	var worst := 0.0
	for f in range(0, 11):
		at(f)
		worst = maxf(worst, over(m.S.own_rig["pose"].get("tail_3", Quaternion.IDENTITY), Vector3(-30, -30, -30), Vector3(30, 30, 30)))
	for f in m.S.own_rig["keys"]:
		worst = maxf(worst, over(m.S.own_rig["keys"][f].get("tail_3", Quaternion.IDENTITY), Vector3(-30, -30, -30), Vector3(30, 30, 30)))
	print("     worst limit violation over keys 0..10 and every frame: %.6f deg" % worst)
	ok(worst < 1e-3, "3 keys and every interpolated frame stay inside the limits (%.6f deg over)" % worst)

	# 4 two-bone IK (the rig is at frame 0 of its keys; clear the pose of the leg)
	at(0)
	var leg := ["leg_fl_upper", "leg_fl_lower", "leg_fl_paw"]
	var aim := {"leg_fl_upper": Basis.from_euler(Vector3(0.5, 0.1, 0.0)), "leg_fl_lower": Basis.from_euler(Vector3(0.9, 0.0, 0.0))}
	var tgt := world_of("leg_fl_paw", aim)
	var mid_fk := world_of("leg_fl_lower", aim)
	var top := world_of("leg_fl_upper", aim)
	var line := tgt - top
	var side := (mid_fk - top) - line * ((mid_fk - top).dot(line) / line.length_squared())   # the knee's bend away from the hip-foot line
	ok(m.rig_ui.mark_chain("leg_fl", leg, top + side * 5.0) == "", "4 chain leg_fl marked with a pole on the knee's side")
	var res: Dictionary = m.rig_ui.ik_to("leg_fl", tgt)
	var err := foot("leg_fl_paw").distance_to(tgt)
	var knee := foot("leg_fl_lower")
	var kside := (knee - top) - line * ((knee - top).dot(line) / line.length_squared())
	print("     2-bone IK: foot error %.4f mm, reached=%s, knee on pole side dot=%.4f" % [err * 1000.0, str(res.get("reached")), kside.dot(side)])
	ok(res.get("reached", false) == true and err < 0.001, "4 the IK foot reaches the FK-made target within 1 mm (%.4f mm)" % (err * 1000.0))
	ok(kside.dot(side) > 0.0, "4 the knee is on the pole side")
	m.rig_ui.mark_chain("leg_fl", leg, top - side * 5.0)
	var res2: Dictionary = m.rig_ui.ik_to("leg_fl", tgt)
	var err2 := foot("leg_fl_paw").distance_to(tgt)
	var knee2 := foot("leg_fl_lower")
	var kside2 := (knee2 - top) - line * ((knee2 - top).dot(line) / line.length_squared())
	ok(err2 < 0.001 and kside2.dot(side) < 0.0, "4 control: with the pole flipped the knee flips and the foot still lands (%.4f mm, reached=%s)" % [err2 * 1000.0, str(res2.get("reached"))])
	var far := top + Vector3(0, 0, 5.0)
	var res3: Dictionary = m.rig_ui.ik_to("leg_fl", far)
	var dir_now := (foot("leg_fl_paw") - top).normalized()
	var off_deg := rad_to_deg(dir_now.angle_to((far - top).normalized()))
	print("     out of reach: reached=%s why=%s, limb points %.3f deg off" % [str(res3.get("reached")), str(res3.get("why")), off_deg])
	ok(res3.get("reached", true) == false and "out of reach" in String(res3.get("why", "")), "4 a target 5 m away says out of reach")
	ok(off_deg < 1.0 or res3.get("limited", false), "4 the limb stretches toward the unreachable target (%.3f deg off)" % off_deg)
	# a tight knee limit that the target needs more of
	CustomRig.set_limit(m.S.own_rig, "leg_fl_lower", Vector3(-10, -5, -5), Vector3(20, 5, 5))
	var res4: Dictionary = m.rig_ui.ik_to("leg_fl", tgt)
	var viol := over(m.S.own_rig["pose"]["leg_fl_lower"], Vector3(-10, -5, -5), Vector3(20, 5, 5))
	print("     IK with a tight knee limit: limited=%s, reached=%s, violation %.6f deg" % [str(res4.get("limited")), str(res4.get("reached")), viol])
	ok(viol < 1e-3 and (res4.get("limited", false) or res4.get("reached", false)), "4 a tight knee limit is never exceeded by IK")
	CustomRig.set_limit(m.S.own_rig, "leg_fl_lower", Vector3(-80, -60, -60), Vector3(80, 60, 60))

	# 5 tail CCD
	var tail := ["tail_1", "tail_2", "tail_3", "tail_4", "tail_5"]
	var taim := {"tail_1": Basis.from_euler(Vector3(0.2, 0.15, 0.0)), "tail_2": Basis.from_euler(Vector3(0.25, -0.2, 0.0)), "tail_3": Basis.from_euler(Vector3(-0.2, 0.1, 0.0)), "tail_4": Basis.from_euler(Vector3(0.3, 0.2, 0.0))}
	var ttgt := world_of("tail_5", taim)
	ok(m.rig_ui.mark_chain("tail", tail, null) == "", "5 chain tail marked (no pole: CCD)")
	ok(m.rig_ui.mark_chain("bad", ["tail_1", "tail_3"], null) != "", "5 control: bones that are not a parent-child path are refused")
	var res5: Dictionary = m.rig_ui.ik_to("tail", ttgt)
	var err5 := foot("tail_5").distance_to(ttgt)
	var v5 := 0.0
	for b in ["tail_1", "tail_2", "tail_3", "tail_4"]:
		v5 = maxf(v5, over(m.S.own_rig["pose"].get(b, Quaternion.IDENTITY), Vector3(-30, -30, -30), Vector3(30, 30, 30)))
	print("     tail CCD: tip error %.4f mm, reached=%s, limit violation %.6f deg" % [err5 * 1000.0, str(res5.get("reached")), v5])
	ok(err5 < 0.001 and res5.get("reached", false), "5 the tail tip reaches an FK-made target within 1 mm (%.4f mm)" % (err5 * 1000.0))
	ok(v5 < 1e-3, "5 tail limits never exceeded by the CCD")
	var res6: Dictionary = m.rig_ui.ik_to("tail", Vector3(0, 0.5, -3.0))
	ok(res6.get("reached", true) == false and "out of reach" in String(res6.get("why", "")), "5 a tail target 3 m away says out of reach")

	# 6 root position keys
	for b in R["pose"].keys():
		R["pose"][b] = Quaternion.IDENTITY
	R["keys"].clear()
	R["pkeys"] = {}
	at(0)
	m.rig_ui.move_root(Vector3.ZERO)
	m.rig_ui.key_now()
	at(10)
	m.rig_ui.move_root(Vector3(1.0, 0.0, 0.5))
	m.rig_ui.key_now()
	await idle(2)
	at(5)
	var rt := drawn("root")
	var want := world_of("root", {}, Vector3(0.5, 0.0, 0.25))
	var mx := 0.0
	for r in rows():
		mx = maxf(mx, drawn(r["name"]).distance_to(world_of(r["name"], {}, Vector3(0.5, 0.0, 0.25))))
	print("     root drawn %s want %s; max joint deviation %.5f mm" % [str(rt), str(want), mx * 1000.0])
	ok(rt.distance_to(want) < 1e-4 and mx < 1e-4, "6 a root position key moves the drawn root and every joint (frame 5, within 0.1 mm)")
	at(0)
	ok(drawn("root").distance_to(world_of("root", {})) < 1e-4, "6 control: frame 0 is not moved")
	m.playhead = 0.0
	m._refresh()
	m._toggle_play()
	play_steps(10)
	if m.playing:
		m._toggle_play()
	ok(drawn("root").distance_to(world_of("root", {}, Vector3(1.0, 0.0, 0.5))) < 1e-4, "6 real Play carries the root to the frame-10 position within 0.1 mm")
	var before := var_to_str(CustomRig.to_file(m.S.own_rig))
	m._write(PATH, m.S.to_dict(m.B))
	m._load_scene(PATH, true)
	await idle(4)
	ok(before == var_to_str(CustomRig.to_file(m.S.own_rig)) and (m.S.own_rig.get("chains", {}) as Dictionary).has("leg_fl") and (m.S.own_rig.get("limits", {}) as Dictionary).has("leg_fl_lower"), "6 position keys, limits and chains come back identical from the file")

	# 7 gates
	var tools := ["check", "human_limits", "feasible", "contacts", "retarget", "balance"]
	var kb: bool = m.keep_balance
	var ic: bool = m.ik_contact
	var hl: bool = HumanLimits.on
	var cr: bool = m.check_ran
	var rt_on: bool = m._retarget_on()
	m.own_gate_log.clear()
	m._check()
	m._human_check()
	m._feasible_check()
	m._ik_contact_toggle()
	m._retarget_toggle()
	m._toggle_keep_balance()
	var got := 0
	for t in tools:
		if "not a human rig" in String(m.own_gate_log.get(t, "")):
			got += 1
	print("     gates answering 'not a human rig': %d of %d" % [got, tools.size()])
	ok(got == tools.size(), "7 each human-only panel returns the gate (%d of %d)" % [got, tools.size()])
	ok(m.keep_balance == kb and m.ik_contact == ic and HumanLimits.on == hl and m.check_ran == cr and m._retarget_on() == rt_on, "7 and none of them changed anything")
	m.rig_ui.active = false
	m._ik_contact_toggle()
	m._toggle_keep_balance()
	ok(m.ik_contact != ic and m.keep_balance != kb, "7 control: with the rig not the active subject the toggles run")
	m._ik_contact_toggle()
	m._toggle_keep_balance()
	m.rig_ui.active = true

	# 8 Manny unchanged
	m.S.own_rig = {}
	m.playhead = 0.0
	m._refresh()
	await idle(2)
	var body1 := body_ang()
	var diff := 0.0
	for j in body0:
		diff = maxf(diff, (body0[j] as Vector3).distance_to(body1.get(j, Vector3(INF, INF, INF))))
	print("     body pose difference before / after the rig: %.8f" % diff)
	ok(diff == 0.0 and body0.size() > 10, "8 Manny's pose is unchanged by the rig (difference %.8f over %d joints)" % [diff, body0.size()])

	print("rigown_ik: %d failed" % fails)
	quit(1 if fails > 0 else 0)
