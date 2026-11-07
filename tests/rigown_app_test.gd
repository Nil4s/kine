## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/rigown_app_test.gd     (ROADMAP_400 track J, lane L73 RIGOWN2)
## The own rig (scripts/custom_rig.gd) USED IN THE APP: Scene menu "Import rig (glTF)...", drawn bones, a click picks, rotate + key on the
## timeline, playback interpolates, save and reopen, human-only tools gated. Numbers come from the app (m.rig_ui drawn nodes, the app's camera,
## the app's undo, its scene file). Bars written and committed BEFORE the implementation; none edited after.
##   1 IMPORT + DRAWN   the 30-bone fixture (.glb) imported through m.rig_import: S.own_rig has 30 bones, 30 joints drawn, and each drawn joint's
##      world position is within 1 mm of an INDEPENDENT chain product of the fixture's rest transforms. Control: a node moved 5 mm is caught.
##   2 PICK             camera from the side; every bone whose screen position is >= 24 px from every other bone's is picked by a left press
##      (through m._unhandled_input) at its screen position: all of them, and at least 20 such bones.
##      Control: a press 150 px from every joint changes nothing and is not consumed.
##   3 ROTATE + KEY     rotate tail_3 40 deg about X: the drawn tail_5 moves >= 5 cm and equals the independent chain product within 1 mm;
##      key at frame 0 (identity) and frame 10 (40 deg); each rotate / key is ONE undo step.
##   4 PLAYBACK         playhead 0 -> tail_3 angle 0, playhead 10/30 -> 40 deg within 1e-3 rad, playhead 5/30 -> 20 deg within 1e-3 rad
##      (read from the rig, and the drawn joints follow within 1 mm). Control: playhead 0 does NOT read 40 deg.
##   5 UNDO             Ctrl+Z (m._undo) takes the frame-10 key back: 1 key left.
##   6 SAVE + REOPEN    scene written and opened again: CustomRig.to_file of the rig identical (var_to_str), 30 drawn joints back within 1 mm,
##      the keys at frames 0 and 10 back; a scene without an own rig has no "own_rig" key and draws no rig joints.
##   7 GATE             on the own rig the panel's body-tools button says "not a human rig" (label text), ok=false, the body tool counter stays 0.
##      Control: a rig named with the 22 body joints runs the same wrapper once.
extends SceneTree

var fails := 0
var m: Node
const PATH := "res://scenes/_wip/rigown_app_test.json"


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


## INDEPENDENT of CustomRig.globals: the chain product over the fixture rows, with extra local rotations (bone -> Basis) applied after the rest
func world_of(bone: String, extra: Dictionary) -> Vector3:
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
		g = g * x
	return g.origin


func drawn(n: String) -> Vector3:
	var nd: Node3D = m.rig_ui.nodes.get(n)
	return nd.global_position if nd != null else Vector3(INF, INF, INF)


func max_dev(extra: Dictionary) -> float:
	var e := 0.0
	for r in rows():
		e = maxf(e, drawn(r["name"]).distance_to(world_of(r["name"], extra)))
	return e


func press(pos: Vector2) -> bool:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pos
	m._unhandled_input(e)
	return m.rig_ui.last_consumed


func ang_of(bone: String) -> float:
	var q: Quaternion = (m.S.own_rig["pose"] as Dictionary).get(bone, Quaternion.IDENTITY)
	return q.get_angle()


func at(frame: int) -> void:
	m.playhead = float(frame) / 30.0
	m._refresh()


func _init() -> void:
	var glb := "user://rigown_app/creature.glb"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://rigown_app"))
	var we := write_fixture(glb)
	ok(we == OK, "0 fixture written (%s)" % error_string(we))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	m._turn_to(90.0, 0.0, 3.5, Vector3(0, 0.5, 0), false)
	await idle(3)
	var cam: Camera3D = m.cam

	# 1 import + drawn
	ok(not (m.S.to_dict(m.B) as Dictionary).has("own_rig"), "6a a scene without an own rig has no own_rig key")
	var why: String = m.rig_import(glb)
	await idle(3)
	ok(why == "", "1 rig_import answers ok (%s)" % why)
	ok((m.S.own_rig.get("names", []) as Array).size() == 30, "1 S.own_rig has 30 bones (%d)" % (m.S.own_rig.get("names", []) as Array).size())
	ok(m.rig_ui.nodes.size() == 30, "1 30 joints drawn (%d)" % m.rig_ui.nodes.size())
	var dev := max_dev({})
	print("     max drawn-joint deviation from the independent chain product: %.6f mm" % (dev * 1000.0))
	ok(dev < 0.001, "1 every drawn joint within 1 mm of the rig's world joint")
	var nd: Node3D = m.rig_ui.nodes["tail_5"]
	var keep := nd.global_position
	nd.global_position += Vector3(0.005, 0, 0)
	ok(max_dev({}) >= 0.001, "1 control: a joint moved 5 mm is caught")
	nd.global_position = keep

	# 2 pick
	var scr := {}
	for r in rows():
		scr[r["name"]] = cam.unproject_position(drawn(r["name"]))
	var testable := []
	for n in scr:
		var iso := true
		for o in scr:
			if o != n and (scr[n] as Vector2).distance_to(scr[o]) < 24.0:
				iso = false
		if iso:
			testable.append(n)
	var wrong := []
	for n in testable:
		m.rig_ui.cur = ""
		press(scr[n])
		if m.rig_ui.cur != n:
			wrong.append("%s->%s" % [n, m.rig_ui.cur])
	print("     pickable bones tested: %d, wrong: %s" % [testable.size(), str(wrong)])
	ok(testable.size() >= 20 and wrong.is_empty(), "2 a press at a bone's screen position picks it (%d of %d)" % [testable.size() - wrong.size(), testable.size()])
	var far := Vector2(6, 400)
	for n in scr:
		if (scr[n] as Vector2).distance_to(far) < 150.0:
			far = Vector2(1100, 650)
	m.rig_ui.cur = "hips"
	var consumed := press(far)
	ok(m.rig_ui.cur == "hips" and not consumed, "2 control: a press far from every joint changes nothing and is not consumed")

	# 3 rotate + key
	at(0)
	var n0: int = m.undo.size()
	m.rig_ui.cur = "tail_3"
	m.rig_ui.key_now()
	ok(m.undo.size() - n0 == 1, "3 key at frame 0 is one undo step (%d)" % (m.undo.size() - n0))
	var rest5 := drawn("tail_5")
	n0 = m.undo.size()
	at(10)
	m.rig_ui.rotate_deg("tail_3", Vector3(40, 0, 0))
	await idle(2)
	ok(m.undo.size() - n0 == 1, "3 rotate is one undo step (%d)" % (m.undo.size() - n0))
	var moved := drawn("tail_5").distance_to(rest5)
	var d40 := max_dev({"tail_3": Basis(Vector3(1, 0, 0), deg_to_rad(40))})
	print("     tail_5 moved %.2f cm; deviation from chain product %.4f mm" % [moved * 100.0, d40 * 1000.0])
	ok(moved >= 0.05, "3 the drawn tail_5 moved >= 5 cm")
	ok(d40 < 0.001, "3 every drawn joint equals the independent chain product with tail_3 at 40 deg (1 mm)")
	n0 = m.undo.size()
	m.rig_ui.key_now()
	ok(m.undo.size() - n0 == 1 and (m.S.own_rig["keys"] as Dictionary).size() == 2, "3 key at frame 10 is one undo step, 2 keys")

	# 4 playback
	at(0)
	var a0 := ang_of("tail_3")
	at(10)
	var a10 := ang_of("tail_3")
	at(5)
	var a5 := ang_of("tail_3")
	print("     tail_3 angle: frame0 %.5f, frame5 %.5f, frame10 %.5f rad (keyed %.5f)" % [a0, a5, a10, deg_to_rad(40)])
	ok(absf(a10 - deg_to_rad(40)) < 1e-3, "4 frame 10 plays back the keyed angle within 1e-3 rad")
	ok(absf(a5 - deg_to_rad(20)) < 1e-3, "4 frame 5 is halfway within 1e-3 rad")
	ok(absf(a0) < 1e-3 and absf(a0 - deg_to_rad(40)) > 0.5, "4 control: frame 0 does not read 40 deg")
	ok(max_dev({"tail_3": Basis(Vector3(1, 0, 0), a5)}) < 0.001, "4 the drawn joints follow the frame-5 pose (1 mm)")

	# 5 undo
	m._undo()
	await idle(2)
	ok((m.S.own_rig["keys"] as Dictionary).size() == 1, "5 undo takes the frame-10 key back (%d keys left)" % (m.S.own_rig["keys"] as Dictionary).size())
	m.rig_ui.cur = "tail_3"
	at(10)
	m.rig_ui.rotate_deg("tail_3", Vector3(40, 0, 0))
	m.rig_ui.key_now()
	await idle(2)

	# 6 save + reopen
	var before := var_to_str(CustomRig.to_file(m.S.own_rig))
	var d: Dictionary = m.S.to_dict(m.B)
	ok(d.has("own_rig"), "6 the scene file has own_rig")
	m._write(PATH, d)
	m._load_scene(PATH, true)
	await idle(4)
	var after := var_to_str(CustomRig.to_file(m.S.own_rig))
	ok(before == after, "6 the rig comes back identical (file form)")
	at(0)
	ok(m.rig_ui.nodes.size() == 30 and max_dev({}) < 0.001, "6 30 joints drawn again, within 1 mm (frame 0 is the identity key)")
	ok(CustomRig.key_frames(m.S.own_rig) == [0, 10], "6 the keys at frames 0 and 10 are back")
	at(10)
	ok(absf(ang_of("tail_3") - deg_to_rad(40)) < 1e-3, "6 the reopened rig plays the keyed angle at frame 10")

	# 7 gate
	var cnt := [0]
	var g1: Dictionary = CustomRig.run_human_only(m.S.own_rig, "x", func(_r): cnt[0] += 1; return {"ok": true})
	m.rig_ui.body_tools_pressed()
	var txt: String = m.rig_ui.gate_label.text
	ok(not g1["ok"] and "not a human rig" in String(g1["why"]) and "not a human rig" in txt and cnt[0] == 0, "7 the panel's body tools say 'not a human rig' and nothing ran (%s)" % txt.left(60))
	var hr := {"ok": true, "names": Body.ORDER.slice(0, 22), "parent": [], "rest": [], "pose": {}, "keys": {}, "core_matched": 22}
	var g2: Dictionary = CustomRig.run_human_only(hr, "x", func(_r): cnt[0] += 1; return {"ok": true})
	ok(g2["ok"] and cnt[0] == 1, "7 control: a rig with the 22 body joints runs the tool once")

	# 6b no rig
	m.S.own_rig = {}
	m._refresh()
	await idle(2)
	ok(not (m.S.to_dict(m.B) as Dictionary).has("own_rig") and m.rig_ui.nodes.size() == 0, "6 a scene without an own rig: no own_rig key, no rig joints drawn")

	print("rigown_app: %d failed" % fails)
	quit(1 if fails > 0 else 0)
