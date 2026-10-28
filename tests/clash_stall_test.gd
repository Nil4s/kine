extends SceneTree
## godot --path . -s tests/clash_stall_test.gd   (the STALL work's bar: the UI run of the B24 clash through the app's own tick
## gives the SAME result as before the slicing. A digest of the whole result (every frame's words and clearances, the worst list,
## each part's minimum) for the elbow scene and the ROM test, pinned to the digest the unsliced job gave.)

var fails := 0
var m: Node
const EXPECT_SCENE := "5ea6d50688c05ea5439ff631c1ca1f9b"
const EXPECT_ROM := "2914991c08140fed566358cf02f649d9"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func plate(k0: KMesh, off: float, tag: String) -> KMesh:
	var fs := ArmourFromBody.pick_faces(k0, ArmourFromBody.parse(tag))
	var cp := ArmourFromBody.copy_faces(k0, fs)
	var cl := ArmourFromBody.clean(cp[0], cp[1])
	var patch: KMesh = cl[0]
	var sw := KMeshShrinkwrap.build(k0)
	sw.wrap_mesh(patch, {"offset": off})
	ArmourFromBody.copy_weights(k0, patch, cl[1])
	return patch


func digest(res: Dictionary) -> String:
	var d := res.duplicate()
	d.erase("ms")
	return str(var_to_bytes(d).hex_encode().md5_text())


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	await idle()
	var skel: Skeleton3D = m.skel
	var k0 := BaseBody.read(m)
	KMeshAnatomy.seed_tags(k0, skel, (m.pieces.values()[0] as MeshInstance3D).global_transform)
	var p4 := plate(k0, 0.004, "biceps_l")
	ArmourFromBody.attach(m, p4, "biceps_l")
	await idle(2)
	# the elbow scene, as the stall test sets it up
	var B: Body = m.B
	var cards := []
	for kk in [[0.0, -1.0, 0.3], [150.0, 1.0, 0.4], [0.0, 0.8, 0.2]]:
		for j in B.ang:
			B.ang[j] = Vector3.ZERO
		B.offset = Vector3.ZERO
		B.ang["lowerarm_l"] = Vector3(kk[0], 0, 0)
		B.fk()
		cards.append({"name": "zz_elbow %d" % kk[0], "pose": B.to_dict(), "move": kk[1], "hold": kk[2]})
	m.S.from_dict({"scene": "zz_elbow", "fps": 30, "free_limits": true, "cards": cards})
	m._rebuild_cards()
	for j in B.ang:
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3.ZERO
	B.fk()
	m.playhead = 0.0
	m._ps().apply(B, 0.0)
	m._refresh()
	await idle(2)
	var got := {}
	for how in ["scene", "rom"]:
		m.clash_ui.run(how)
		var n := 0
		while m.clash_ui.job.running() and n < 5000:
			await process_frame
			n += 1
		got[how] = digest(m.clash_ui.res)
		print("DIGEST %s %s frames %d worst %d" % [how, got[how], (m.clash_ui.res["frames"] as Array).size(), (m.clash_ui.res["worst"] as Array).size()])
	ok(got["scene"] == EXPECT_SCENE, "STALL same result: the elbow scene's digest is the unsliced job's (%s)" % got["scene"])
	ok(got["rom"] == EXPECT_ROM, "STALL same result: the ROM test's digest is the unsliced job's (%s)" % got["rom"])
	print("CLASH STALL RESULT: %s %d" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
