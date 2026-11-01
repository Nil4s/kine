extends SceneTree
## godot --path . --position 4000,4000 -s tests/s120_test.gd   (S120: MOVING PARTS. A two-piece box, base 100 x 60 x 40 mm and a lid 100 x 60 x 6 mm with a lid hinge at the base's back top edge about -X; a real click on "Save and use in a scene"; the lid keyed on the STAGE timeline)
## BARS: 1 one prop with 2 child meshes, volumes within 0.5 pct of the part's bodies | 2 pivot within 0.1 mm of the hinge, axis within 0.5 deg
##       3 frame 15: lid 45 +-1 deg, corner within 0.5 mm of the analytic turn, lid box within 0.5 mm of the kernel's own posed lid | 4 key 120 plays at the limit (90), said in words
##       5 the base piece moves 0.0 mm | 6 the send is one undo step | 7 save + reload (kind forgotten first): joint keys and the 45 deg survive
## Shots: C:/Temp/claude/s120/*.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s120"


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func part_index() -> int:
	for i in m.S.props.size():
		if String(m.S.props[i]["kind"]).begins_with("part:"):
			return i
	return -1


func nparts() -> int:
	var n := 0
	for p in m.S.props:
		if String(p["kind"]).begins_with("part:"):
			n += 1
	return n


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func prop_node(i: int) -> Node3D:
	return m.ui_props_root.get_node_or_null("prop_%d" % i) as Node3D


func piece(n: Node3D, i: int) -> MeshInstance3D:
	return n.find_child("piece_%d" % i, true, false) as MeshInstance3D


## the AABB of a piece in the prop node's frame
func box_in(n: Node3D, mi: MeshInstance3D) -> AABB:
	return (n.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()


func at_time(t: float) -> void:
	m.playhead = t
	m._props_pose()
	await idle(2)


func lid_angle(n: Node3D) -> float:
	var jn := n.find_child("joint_1", true, false) as Node3D
	return rad_to_deg((n.global_transform.affine_inverse() * jn.global_transform).basis.get_rotation_quaternion().get_angle())


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://s120_test"))
	var ss: StartScreen = m.start_screen
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	ss.dirs_override = ["user://s120_test"]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		ok(false, "S0 the CAD DLL loads")
		print("s120: %d fail" % fails)
		quit(1)
		return
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep: EasyPart = pu.ep

	# the part: a base box and a lid on a plane 40 mm up, hinged at the base's back top edge about -X
	var rec := Part.make("Lidbox")
	var f1 := Part.new_feature(rec, "sketch", {"plane": "top", "ents": [{"k": "rect", "a": [-50.0, -30.0], "b": [50.0, 30.0]}], "dims": []})
	rec["features"].append(f1)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": f1["id"], "dist": 40.0, "both": false, "op": "new"}))
	var pl := Part.new_feature(rec, "plane", {"from": "top", "mm": 40.0})
	rec["features"].append(pl)
	var f2 := Part.new_feature(rec, "sketch", {"plane": pl["id"], "ents": [{"k": "rect", "a": [-50.0, -30.0], "b": [50.0, 30.0]}], "dims": []})
	rec["features"].append(f2)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": f2["id"], "dist": 6.0, "both": false, "op": "new"}))
	var hf := Part.new_feature(rec, "hinge", {"body": 1, "o": [0.0, 40.0, -30.0], "axis": [-1.0, 0.0, 0.0], "track": [[0.0, 0.0], [1.0, 90.0]], "clear": []})
	rec["features"].append(hf)
	m.S.part = rec
	pu.upto = -1
	pu.sync()
	await idle(6)
	var truth := Part.replay(rec)
	print("  part bodies ", truth["bodies"], " volumes ", truth["volumes"], " errors ", truth["errors"])
	ok(int(truth["bodies"]) == 2, "0 the part has 2 bodies (%d)" % int(truth["bodies"]))
	if m.S.cards.is_empty():
		m.S.add("start", m.B.to_dict())
	m.sel_card = 0
	var ux: int = m.undo.size()
	await click_ctl(ep.use_scene_btn)
	await idle(8)
	var uxd: int = m.undo.size() - ux
	var pi := part_index()
	if pi < 0:
		ok(false, "S0 the part is in the scene")
		print("s120: %d fail" % fails)
		quit(1)
		return
	var p: Dictionary = m.S.props[pi]
	var n := prop_node(pi)
	var meshes := n.find_children("*", "MeshInstance3D", true, false)
	var v0 := PropJoints.mesh_volume((meshes[0] as MeshInstance3D).mesh) if meshes.size() > 0 else 0.0
	var v1 := PropJoints.mesh_volume((meshes[1] as MeshInstance3D).mesh) if meshes.size() > 1 else 0.0
	var e0 := absf(v0 - float(truth["volumes"][0])) / float(truth["volumes"][0])
	var e1 := absf(v1 - float(truth["volumes"][1])) / float(truth["volumes"][1])
	ok(nparts() == 1 and meshes.size() == 2 and e0 <= 0.005 and e1 <= 0.005, "1 one prop with %d child meshes; volumes %.3f / %.3f cm3 vs part %.3f / %.3f cm3 (err %.3f / %.3f pct)" % [meshes.size(), v0 * 1e6, v1 * 1e6, float(truth["volumes"][0]) * 1e6, float(truth["volumes"][1]) * 1e6, e0 * 100, e1 * 100])
	ok(uxd == 1, "6 the send is %d undo step" % uxd)
	print("  status: ", m.ui_status.text)

	# 2 the pivot, measured on the joint node against the base piece's box (its back top edge); the axis from the node's own turn at 90 deg
	var bb := box_in(n, piece(n, 0))
	var jn := n.find_child("joint_1", true, false) as Node3D
	var piv := (n.global_transform.affine_inverse() * jn.global_transform).origin
	var want := Vector3(bb.get_center().x, bb.end.y, bb.position.z)
	var dp := (piv - want).length()
	m.sel_prop = pi
	await at_time(0.0)
	m._prop_joint_key("Hinge1", 0.0)
	await at_time(1.0)
	m._prop_joint_key("Hinge1", 90.0)
	await at_time(1.0)
	n = prop_node(pi)
	jn = n.find_child("joint_1", true, false) as Node3D
	var q := (n.global_transform.affine_inverse() * jn.global_transform).basis.get_rotation_quaternion()
	var hax := Vector3(-1, 0, 0)
	var dang := rad_to_deg(q.get_axis().angle_to(hax))
	ok(dp <= 0.0001 and dang <= 0.5, "2 pivot %.3f mm from the hinge (bar 0.1), axis %.3f deg from the hinge axis (bar 0.5), turned %.2f deg at 1 s" % [dp * 1000, dang, rad_to_deg(q.get_angle())])

	# 3 frame 15 (0.5 s at 30 fps)
	await at_time(0.0)
	n = prop_node(pi)
	var lid_rest := box_in(n, piece(n, 1))
	var corner := lid_rest.end
	var base0 := box_in(n, piece(n, 0))
	await at_time(15.0 / float(m.S.fps))
	n = prop_node(pi)
	var lid_mi := piece(n, 1)
	var ang15 := lid_angle(n)
	var got := (n.global_transform.affine_inverse() * lid_mi.global_transform) * lid_mi.get_aabb().end
	var anal := want + Basis(hax, deg_to_rad(45.0)) * (corner - want)
	var dc := (got - anal).length()
	# the kernel's own turned lid, moved to the prop frame
	var kp := Part.replay(rec, -1, {"pose": {"f": hf["id"], "deg": 45.0}})
	var kbox := AABB()
	var first := true
	for s in (kp["mesh"] as ArrayMesh).get_surface_count():
		if int(kp["surf_body"][s]) == 1:
			for vtx in ((kp["mesh"] as ArrayMesh).surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				kbox = AABB(vtx, Vector3.ZERO) if first else kbox.expand(vtx)
				first = false
	kbox.position += Props.kind_of(String(p["kind"]))["mesh_at"]
	var lbox := box_in(n, lid_mi)
	var dk := maxf((lbox.position - kbox.position).length(), (lbox.end - kbox.end).length())
	ok(absf(ang15 - 45.0) <= 1.0 and dc <= 0.0005 and dk <= 0.0005, "3 frame 15: lid at %.2f deg (bar 45 +-1); corner %.3f mm from the analytic turn (bar 0.5); lid box %.3f mm from the kernel's posed lid (bar 0.5)" % [ang15, dc * 1000, dk * 1000])
	var base15 := box_in(n, piece(n, 0))
	m.target = (p["xf"] as Transform3D).origin + Vector3(0.0, 0.06, 0.0)
	m.dist = 0.45
	m.pitch = -25.0
	m.yaw = 55.0
	m._cam()
	await idle(10)
	await shot("a_frame15")
	await at_time(30.0 / float(m.S.fps))
	n = prop_node(pi)
	var base30 := box_in(n, piece(n, 0))
	var ang30 := lid_angle(n)
	var move := maxf(maxf((base15.position - base0.position).length(), (base30.position - base0.position).length()), maxf((base15.end - base0.end).length(), (base30.end - base0.end).length()))
	ok(move == 0.0 and absf(ang30 - 90.0) <= 0.5, "5 the base piece moved %.4f mm over frames 0, 15, 30; frame 30 lid at %.2f deg" % [move * 1000, ang30])
	await shot("b_frame30")

	# 4 key 120: the part's limit is 90
	var r120: Dictionary = m._prop_joint_key("Hinge1", 120.0)
	var said: String = m.ui_status.text
	print("  status: ", said)
	await at_time(1.0)
	n = prop_node(pi)
	var ang120 := lid_angle(n)
	await at_time(2.0)
	n = prop_node(pi)
	var ang2s := lid_angle(n)
	ok(absf(ang120 - 90.0) <= 0.5 and absf(ang2s - 90.0) <= 0.5 and bool(r120.get("limited", false)) and said.find("limit") >= 0, "4 key 120 plays at %.2f deg (1 s) and %.2f deg (2 s); keyed value %.0f; said: %s" % [ang120, ang2s, float(r120.get("value", -1)), said])

	# 7 save and reload: the kind is forgotten first, so the file must make it again from the record
	var d: Dictionary = m.S.to_dict(m.B)
	var js := JSON.stringify(d)
	var kind := String(p["kind"])
	Props.EXTRA.erase(kind)
	var S2 := Scene.new()
	S2.from_dict(JSON.parse_string(js))
	var qi := -1
	for i in S2.props.size():
		if String(S2.props[i]["kind"]) == kind:
			qi = i
	var ks: Array = (S2.props[qi].get("jkeys", {}) as Dictionary).get("Hinge1", []) if qi >= 0 else []
	var back: Dictionary = Props.posed(S2.props[qi], 0.5) if qi >= 0 else {}
	var rn: Node3D = Props.mesh(back) if qi >= 0 else null
	var ja := float((back.get("jang", {}) as Dictionary).get("Hinge1", -1.0))
	var rj: Node3D = rn.find_child("joint_1", true, false) as Node3D if rn != null else null
	var rang := rad_to_deg(rj.transform.basis.get_rotation_quaternion().get_angle()) if rj != null else -1.0
	ok(qi >= 0 and ks.size() == 2 and absf(ja - 45.0) <= 1.0 and absf(rang - 45.0) <= 1.0, "7 reloaded: joint keys %d, value at 0.5 s %.2f deg, rebuilt node turned %.2f deg" % [ks.size(), ja, rang])
	if rn != null:
		rn.free()
	print("s120: %d fail" % fails)
	quit(1 if fails > 0 else 0)
