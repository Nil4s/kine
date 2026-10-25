## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/boneedit_test.gd     (ROADMAP_400 J01, BONE EDITOR;
## scripts/bone_editor.gd + bone_editor_ui.gd). Picture: BONEEDIT_SHOT=<png> (none when unset).
## Bars, written before measuring:
##   1 CHAIN: the command opens the editor; E (the key, through main's input) and the Extrude button add a 3-bone chain under hand_r:
##     parents hand_r -> 1 -> 2 -> 3, the first head on hand_r's rest end within 1e-6 m, each extrude exactly ONE undo step.
##   2 PANEL + VIEWPORT: length 6 cm on bone 2 = one step, its length 0.0600 within 1e-6 and the connected bone 3's head follows its
##     tail (1e-6); a mouse drag of bone 3's tail ball (press on it, move 40 px, release) = one step, the tail moved > 1 cm, the
##     head stayed (1e-6); a click on bone 1's middle picks it.
##   3 SAVE: the app's scene file written and opened again: every bone's rest frame comes back EXACTLY (Transform3D ==), the bone
##     list var_to_str-equal; the file validates against docs/scene.schema.json; a scene without bones has no "bones" key.
##   4 REPARENT: bone 3 onto hand_r keeps its world rest frame within 1e-5 (origin and each axis), one step; a loop (bone 1 under
##     bone 2) is refused with no step.
##   5 ROLL: roll +30 on bone 2 = one step; its head and tail stay (1e-6), the roll value goes up 30, its X axis turns 30 deg
##     (within 0.01 deg) about the unchanged Y axis, and every other bone's world rest frame stays (1e-5).
##   6 DELETE: in a hand_l chain 1-2-3 (rolled, so the frames are not the world's), deleting 2 hangs 3 on 1 with 3's world rest
##     frame kept within 1e-5; one step; Ctrl+Z gives back the list exactly.
##   7 UNDO COUNT: every edit since the load was exactly one step, and Ctrl+Z that many times gives back the loaded bones exactly.
##   8 FOLLOW: hand_r posed (and the forearm): every bone under it is at P[hand_r] + G[hand_r] * (rest - p0[hand_r]) within 1e-5,
##     and the chain moved > 2 cm from rest.
##   9 DRAWN + PLACEMENT: one octahedral bone per bone, coloured by depth (Tok s_hips / s_head, differing); each drawn shape's head
##     and tail vertices land on the screen within 2 px of the bone's head and tail (the independent formula of 8).
##  10 J24: "add a tail with 4 bones", pick its 2nd bone, roll 30: ONE step turns the chain into tail_1..tail_4 at the very same
##     points (1e-5) with tail_2 rolled 30; Ctrl+Z gives the chain and the bone list back exactly.
##  11 CORE KEPT: a roll or a length on hand_r is refused (no step); the body's rest skeleton (p0, e0) is byte-equal at the end.
extends SceneTree

var fails := 0
var m: Node
var B: Body
var ed: BoneEditUI


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func steps(f: Callable) -> int:
	var n0: int = m.undo.size()
	f.call()
	return m.undo.size() - n0


func rx(n: String) -> Transform3D:
	return BoneEdit.rest_xf(B, m.S.bones, n)


func xf_err(a: Transform3D, b: Transform3D) -> float:
	return maxf(a.origin.distance_to(b.origin), maxf(a.basis.x.distance_to(b.basis.x), maxf(a.basis.y.distance_to(b.basis.y), a.basis.z.distance_to(b.basis.z))))


func others_err(skip: String, before: Dictionary) -> float:
	var e := 0.0
	for n in before:
		if n != skip:
			e = maxf(e, xf_err(before[n], rx(n)))
	return e


func all_rest() -> Dictionary:
	var d := {}
	for b in m.S.bones:
		d[b["name"]] = rx(b["name"])
	return d


func core_of(n: String) -> String:
	while not BoneEdit.is_core(B, n):
		n = BoneEdit.get_bone(m.S.bones, n)["parent"]
	return n


## the independent formula: the core joint's pose carries the rest point
func carried(n: String, p: Vector3) -> Vector3:
	var c := core_of(n)
	return B.P[c] + (B.G[c] as Quaternion) * (p - B.p0[c])


func key(k: Key, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	e.shift_pressed = shift
	m._unhandled_input(e)


func mouse(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	m._unhandled_input(e)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	B = m.B
	for j in B.ang.keys():
		B.ang[j] = Vector3.ZERO
	B.fk()
	m._refresh()
	await idle(2)
	var core0 := var_to_str(B.p0) + var_to_str(B.e0)
	if m.ui_toast != null:
		m.ui_toast.visible = false
	m._turn_to(0.0, -5.0, 3.2, Vector3(0, 1.0, 0), false)
	await idle(3)
	var cam: Camera3D = m.cam

	# 1 chain
	var cmd := {}
	for c in m._commands():
		if c["id"] == "rig_bone_editor_add_delete_parent_bones":
			cmd = c
	ok(not cmd.is_empty() and not cmd["edits"], "1 the command 'Rig: bone editor' is in the registry (not an edit itself)")
	var s := steps(func(): cmd["run"].call())
	ed = m.bed
	ok(ed != null and ed.on and ed.panel.visible and s == 0, "1 the command opens the editor and its panel, no undo step (%d)" % s)
	ed.pick("hand_r")
	var n1 := [""]
	var n2 := [""]
	var n3 := [""]
	var s1 := steps(func(): n1[0] = ed.extrude())
	var s2 := steps(func(): (ed.panel.find_child("btn_bone_extrude", true, false) as Button).pressed.emit(); n2[0] = ed.cur)
	var s3 := steps(func(): key(KEY_E); n3[0] = ed.cur)
	var b1: String = n1[0]
	var b2: String = n2[0]
	var b3: String = n3[0]
	var par := [BoneEdit.get_bone(m.S.bones, b1).get("parent", ""), BoneEdit.get_bone(m.S.bones, b2).get("parent", ""), BoneEdit.get_bone(m.S.bones, b3).get("parent", "")]
	ok(m.S.bones.size() == 3 and par == ["hand_r", b1, b2], "1 three bones %s, parents %s" % [[b1, b2, b3], par])
	var dh: float = (BoneEdit.rest_ht(B, m.S.bones, b1)[0] as Vector3).distance_to(B.e0["hand_r"])
	ok(dh < 1e-6, "1 the chain starts on hand_r's rest end (%.9f m, bar 1e-6)" % dh)
	ok(s1 == 1 and s2 == 1 and s3 == 1, "1 extrude by call / button / E key: %d, %d, %d undo steps (bar 1 each)" % [s1, s2, s3])
	var nload := 0   # edits after the load (7)

	# 2 panel + viewport
	ed.pick(b2)
	s = steps(func(): ed.f_len.value = 6.0)
	var L2 := BoneEdit.length(B, m.S.bones, b2)
	var gap: float = (BoneEdit.rest_ht(B, m.S.bones, b3)[0] as Vector3).distance_to(BoneEdit.rest_ht(B, m.S.bones, b2)[1])
	ok(s == 1 and absf(L2 - 0.06) < 1e-6 and gap < 1e-6, "2 panel length 6 cm: %d step, length %.7f m, bone 3's head on bone 2's tail (%.9f m)" % [s, L2, gap])
	ed.pick(b3)
	ed.draw()
	await idle(2)
	var ht0 := BoneEdit.rest_ht(B, m.S.bones, b3)
	var tp := cam.unproject_position(BoneEdit.posed_ht(B, m.S.bones, b3)[1])
	s = steps(func():
		mouse(tp, true)
		var mv := InputEventMouseMotion.new()
		mv.position = tp + Vector2(40, -10)
		m._unhandled_input(mv)
		mouse(tp + Vector2(40, -10), false))
	var ht1 := BoneEdit.rest_ht(B, m.S.bones, b3)
	ok(s == 1 and (ht1[1] as Vector3).distance_to(ht0[1]) > 0.01 and (ht1[0] as Vector3).distance_to(ht0[0]) < 1e-6, "2 drag of the tail ball: %d step, tail moved %.1f cm, head moved %.9f m" % [s, (ht1[1] as Vector3).distance_to(ht0[1]) * 100.0, (ht1[0] as Vector3).distance_to(ht0[0])])
	var hb1 := BoneEdit.posed_ht(B, m.S.bones, b1)
	s = steps(func():
		mouse(cam.unproject_position(((hb1[0] as Vector3) + (hb1[1] as Vector3)) * 0.5), true)
		mouse(cam.unproject_position(((hb1[0] as Vector3) + (hb1[1] as Vector3)) * 0.5), false))
	ok(ed.cur == b1 and s == 0, "2 a click on bone 1 picks it (%s), no step" % ed.cur)

	# 3 save / load
	var rest := all_rest()
	var list0 := var_to_str(m.S.bones)
	var path := "user://boneedit_tmp.json"
	m._write(path, m._scene_dict())
	var errs := Validate.file(path)
	ok(errs.is_empty(), "3 the saved scene validates against the schema %s" % str(errs))
	m._load_scene(path)
	await idle(2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	for j in B.ang.keys():
		B.ang[j] = Vector3.ZERO
	B.fk()
	m._refresh()
	var exact := var_to_str(m.S.bones) == list0
	for n in rest:
		exact = exact and rx(n) == rest[n]
	ok(exact and m.S.bones.size() == 3, "3 saved + opened: %d bones, every rest frame EXACTLY the same, the list equal" % m.S.bones.size())
	ok(not Scene.new().to_dict(B).has("bones"), "3 a scene without bones has no 'bones' key")
	var after_load := var_to_str(m.S.bones)
	var u0: int = m.undo.size()

	# 4 reparent
	ed.pick(b3)
	var w3 := rx(b3)
	s = steps(func(): ed.set_parent("hand_r"))
	nload += s
	var e4 := xf_err(w3, rx(b3))
	ok(s == 1 and BoneEdit.get_bone(m.S.bones, b3)["parent"] == "hand_r" and e4 <= 1e-5, "4 %s onto hand_r: %d step, world rest kept within %.9f (bar 1e-5)" % [b3, s, e4])
	ed.pick(b1)
	s = steps(func(): ed.set_parent(b2))
	ok(s == 0 and BoneEdit.get_bone(m.S.bones, b1)["parent"] == "hand_r", "4 %s under its own child %s is refused, no step" % [b1, b2])

	# 5 roll
	ed.pick(b2)
	var before := all_rest()
	var ht_b := BoneEdit.rest_ht(B, m.S.bones, b2)
	var r0 := float(BoneEdit.get_bone(m.S.bones, b2)["roll"])
	s = steps(func(): ed.f_roll.value = r0 + 30.0)
	nload += s
	var ht_a := BoneEdit.rest_ht(B, m.S.bones, b2)
	var dr := float(BoneEdit.get_bone(m.S.bones, b2)["roll"]) - r0
	var xa: float = rad_to_deg(before[b2].basis.x.angle_to(rx(b2).basis.x))
	var ya: float = before[b2].basis.y.distance_to(rx(b2).basis.y)
	var ends := maxf((ht_a[0] as Vector3).distance_to(ht_b[0]), (ht_a[1] as Vector3).distance_to(ht_b[1]))
	ok(s == 1 and absf(dr - 30.0) < 1e-6 and ends < 1e-6, "5 roll +30 on %s: %d step, roll +%.4f, head / tail moved %.9f m" % [b2, s, dr, ends])
	ok(absf(xa - 30.0) < 0.01 and ya < 1e-5, "5 its X axis turned %.4f deg about the same Y axis (Y moved %.9f)" % [xa, ya])
	var oe := others_err(b2, before)
	ok(oe <= 1e-5, "5 every other bone's rest frame stayed (%.9f, bar 1e-5)" % oe)

	# 6 delete a middle bone
	ed.pick("hand_l")
	var cc := []
	for i in 3:
		nload += steps(func(): cc.append(ed.extrude()))
	var c1: String = cc[0]
	var c2: String = cc[1]
	var c3: String = cc[2]
	ed.pick(c1)
	nload += steps(func(): ed.set_roll(25.0))
	ed.pick(c2)
	nload += steps(func(): ed.set_roll(-40.0))
	ed.pick(c3)
	nload += steps(func(): ed.set_roll(70.0))
	var w := rx(c3)
	var keep6 := var_to_str(m.S.bones)
	ed.pick(c2)
	s = steps(func(): key(KEY_X))
	var e6 := xf_err(w, rx(c3))
	ok(s == 1 and BoneEdit.find(m.S.bones, c2) < 0 and BoneEdit.get_bone(m.S.bones, c3)["parent"] == c1 and e6 <= 1e-5 and w.basis.x.distance_to(Vector3.RIGHT) > 0.1,
		"6 delete %s: %d step, %s now on %s, world rest kept within %.9f (bar 1e-5)" % [c2, s, c3, BoneEdit.get_bone(m.S.bones, c3).get("parent", "?"), e6])
	m._undo()
	ok(var_to_str(m.S.bones) == keep6, "6 Ctrl+Z gives the deleted bone and its child's numbers back exactly")
	ed.pick(c2)
	nload += steps(func(): key(KEY_X))

	# 10 J24 chains
	var r: Dictionary = m._pose_words("add a tail with 4 bones")
	nload += 1
	var ti := -1
	for i in m.S.rigx.size():
		if m.S.rigx[i]["kind"] == "tail":
			ti = i
	var pts := RigWords.points(B, m.S.rigx[ti]) if ti >= 0 else PackedVector3Array()
	var to_rest := Transform3D(Basis(), B.p0["pelvis"]) * Transform3D(Basis(B.G["pelvis"] as Quaternion), B.P["pelvis"]).affine_inverse()   # the chain's points at rest (it rides the pelvis)
	var pel0: Vector3 = B.P["pelvis"]
	var rig0 := var_to_str(m.S.rigx)
	var bones0 := var_to_str(m.S.bones)
	ed.pick("rigx:%d:1" % ti)
	s = steps(func(): ed.set_roll(30.0))
	nload += s
	var pe := 0.0
	for k in 4:
		var ht := BoneEdit.rest_ht(B, m.S.bones, "tail_%d" % (k + 1))
		pe = maxf(pe, maxf((ht[0] as Vector3).distance_to(to_rest * pts[k]), (ht[1] as Vector3).distance_to(to_rest * pts[k + 1])))
	print("   (the pelvis moved %.4f m between the words and the edit: the app put the scene's pose back)" % pel0.distance_to(B.P["pelvis"]))
	ok(r["ok"] and s == 1 and m.S.rigx.filter(func(c): return c["kind"] == "tail").is_empty() and BoneEdit.find(m.S.bones, "tail_4") >= 0 and pe <= 1e-5 and absf(float(BoneEdit.get_bone(m.S.bones, "tail_2")["roll"]) - 30.0) < 1e-6,
		"10 the words-made tail edited: %d step, now tail_1..tail_4 at the chain's rest points (%.9f m), tail_2 roll 30" % [s, pe])
	m._undo()
	ok(var_to_str(m.S.rigx) == rig0 and var_to_str(m.S.bones) == bones0, "10 Ctrl+Z gives the chain and the bone list back exactly")
	nload -= 1
	ed.pick("rigx:%d:1" % ti)
	nload += steps(func(): ed.set_roll(30.0))

	# 11 core refused
	ed.pick("hand_r")
	s = steps(func():
		ed.set_roll(30.0)
		ed.set_length(0.3))
	ok(s == 0, "11 roll / length on hand_r (the body's own) refused: %d steps" % s)

	# 8 follow
	var restp := {}
	for b in m.S.bones:
		restp[b["name"]] = BoneEdit.rest_ht(B, m.S.bones, b["name"])
	B.ang["lowerarm_r"] = Vector3(70, 0, 0)
	B.ang["hand_r"] = Vector3(30, 15, 25)
	B.fk()
	m._refresh()
	await idle(2)
	var fe := 0.0
	var moved := INF
	for n in [b1, b2, b3]:
		var ht := BoneEdit.posed_ht(B, m.S.bones, n)
		fe = maxf(fe, maxf((ht[0] as Vector3).distance_to(carried(n, restp[n][0])), (ht[1] as Vector3).distance_to(carried(n, restp[n][1]))))
		moved = minf(moved, (ht[1] as Vector3).distance_to(restp[n][1]))
	ok(fe <= 1e-5 and moved > 0.02, "8 posed hand_r carries its bones: off the formula by %.9f m (bar 1e-5), each tail moved >= %.1f cm (bar 2)" % [fe, moved * 100.0])

	# 9 drawn + placement
	ed.pick(b3)
	m.hover_part = ""
	m.hit_tag.visible = false
	m.tag.visible = false
	m._turn_to(60.0, -10.0, 1.0, B.P["hand_r"], false)
	await idle(4)
	var nd1: MeshInstance3D = ed.nodes.get(b1)
	var nd2: MeshInstance3D = ed.nodes.get(b2)
	var drawn := 0
	for n in ed.nodes:
		if (ed.nodes[n] as Node3D).visible:
			drawn += 1
	ok(drawn == m.S.bones.size() and nd1 != null and nd1.mesh is ArrayMesh, "9 drawn: %d octahedral bones for %d bones" % [drawn, m.S.bones.size()])
	var col1 := (nd1.material_override as StandardMaterial3D).albedo_color
	var col2 := (nd2.material_override as StandardMaterial3D).albedo_color
	ok(col1.is_equal_approx(Tok.c("s_hips")) and col2.is_equal_approx(Tok.c("s_head")) and not col1.is_equal_approx(col2), "9 coloured by depth: depth 0 = Tok s_hips, depth 1 = Tok s_head")
	var worst := 0.0
	var vp := root.get_visible_rect()
	var inside := true
	for n in [b1, b2, b3]:
		var nd: MeshInstance3D = ed.nodes[n]
		var gx := nd.global_transform
		var want_h := cam.unproject_position(carried(n, restp[n][0]))
		var want_t := cam.unproject_position(carried(n, restp[n][1]))
		worst = maxf(worst, maxf(cam.unproject_position(gx * Vector3.ZERO).distance_to(want_h), cam.unproject_position(gx * Vector3.UP).distance_to(want_t)))
		inside = inside and vp.has_point(want_h) and vp.has_point(want_t)
	ok(worst <= 2.0 and inside, "9 placement: the drawn shapes' head / tail land %.3f px from the bones' head / tail on screen (bar 2 px), all in view" % worst)
	var shot := OS.get_environment("BONEEDIT_SHOT")
	if shot != "":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shot)
		print("   (picture: %s)" % shot)

	# 7 undo count
	var made: int = m.undo.size() - u0
	ok(made == nload, "7 every edit since the load was one step: %d steps for %d edits" % [made, nload])
	for i in made:
		m._undo()
	ok(var_to_str(m.S.bones) == after_load, "7 Ctrl+Z x%d gives back the loaded bones exactly" % made)

	# 11 core rest untouched
	ok(var_to_str(B.p0) + var_to_str(B.e0) == core0, "11 the body's own rest skeleton (p0, e0) is byte-equal after every edit")
	ed.stop()
	print("boneedit_test: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	TestFiles.cleanup()
	quit(0 if fails == 0 else 1)
