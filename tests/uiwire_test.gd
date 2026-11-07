## godot --path . -s tests/uiwire_test.gd     (window suite: uiwire:w)   lane L95 UIWIRE: features merged as agent tools only, now reachable by a user.
## BARS, written and committed BEFORE the implementation (scripts/ui_wire.gd + small hooks in main.gd / curve_editor.gd); none is edited after a run.
## Every item is driven through the REAL control (button press, menu item id_pressed, palette command run, slider drag_ended, mouse events on the
## graph editor), then compared with what the agent tool gives from the SAME start state: byte-identical (var_to_bytes) where the tool is deterministic.
##  1 ANYKEY   a) main registers the stage's real lights (key, fill, rim) and the floor material in AnyKey.targets when a scene is opened (the
##               registries were emptied first), the very same objects; the cube mesh when the model cube opens.
##             b) palette "Key this property": its panel's picker lists the registered ids; keying light_energy 2 -> 6 through the Key button
##               plays 4.0 (+-1e-6) on the real key light at the midpoint, and a shape key on the cube plays 0.5 (+-1e-6); each Key press = one undo step;
##               S.anykeys is byte-identical to the agent tool "anykey" doing the same keys.
##             c) CONTROL: an id whose target is not registered is still keyed, is NOT written at playback, is listed by UiWire.skipped, and the panel
##               and the status line SAY so; a registered id is not listed (planted: registering the ghost target empties the list and plays one more).
##  2 GRAPH    a) the Ghost toggle shows the buffer curve: ghost_keys == the agent tool's snapshot of the same joint (bytes); every ghost point
##               lies on the ORIGINAL curve (<= 0.01 px) while the live curve is edited; no undo step; off hides it. Off: ghost_line is empty.
##             b) Alt-drag on a tangent handle sets the weight (win/wout): the weight reads 2.0 +-1e-4 when dragged to 2/3 of a second at a 1 s
##               segment; the key's t/v and the OTHER handle's weight are untouched; ONE undo step for the whole drag; part_keys byte-identical to the
##               agent tool curve_graph weight with that weight. CONTROL: the same drag without Alt gives different data (slope moves).
##  3 AU       the channel picker puts the editor in au mode on the face channel: the drawn curve = AuCurves.value_at clamped (<= 0.01 px),
##             the sync does not pull it back to the picked part, an Alt-drag there is byte-identical to curve_graph {"au"} weight and one undo step,
##             picking "Part keys" returns to the part.
##  4 PALETTE  rig_anim mirror (pose, keys) on a custom rig, react_place / react_time, the mass slider: each palette command / slider release gives the
##             same bytes as its tool, one undo step; refusals (no own rig, no cue) push no step and say why in the status line.
##  5 SLERP    the curve editor's Interp menu: "slerp" on the picked key = the palette command; "slerp the whole part" on / off = the euler_warp
##             slerp tool, bytes, one undo step each. The quaternion readout (a Label) equals the tool "quat" frame within 1e-5 at two playheads and
##             changes nothing (no undo step, part keys unchanged).
##  6 NAMES    no existing palette command id is renamed (a fixed list of ids that existed before this lane), ids are unique, the new ones exist.
##  7 FILES    tools/run_all.sh lists uiwire.
extends SceneTree

var fails := 0
var nok := 0
var m: Node
var T: AgentTools
var rid := 1
var stand: Dictionary
var punch_r: Dictionary


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	if c:
		nok += 1
	else:
		fails += 1


func control(claim: bool, w: String) -> void:
	print(("ok   control caught: " if not claim else "FAIL control NOT caught: ") + w)
	if claim:
		fails += 1
	else:
		nok += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func req(method: String, p: Dictionary) -> Dictionary:
	rid += 1
	return await T.request(rid, method, p)


func cmd(id: String) -> Callable:
	for c in m._commands():
		if c["id"] == id:
			return c["run"]
	return Callable()


func state() -> String:
	return JSON.stringify(m.S.to_dict(m.B, false))


func scene3() -> Scene:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.name = "zz_uiwire"
	S.fps = 30
	B.fk()
	S.add("a", B.to_dict())
	B.ang["upperarm_r"] = Vector3(70, 40, 10)
	B.fk()
	S.add("b", B.to_dict())
	B.ang["upperarm_r"] = Vector3(-30, 80, -20)
	B.fk()
	S.add("c", B.to_dict())
	S.cards[1]["move"] = 0.6
	S.cards[2]["move"] = 0.5
	return S


func use(S: Scene) -> void:
	m.S = S
	m._rebuild_cards()
	m._refresh()


func mbtn(ed: Control, pos: Vector2, pressed: bool, alt := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.alt_pressed = alt
	if pressed:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	ed._gui_input(e)


func mmov(ed: Control, pos: Vector2, alt := false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.alt_pressed = alt
	ed._gui_input(e)


func kbytes(ks: Array) -> PackedByteArray:
	return var_to_bytes(ks.map(func(k): return [k["t"], k["v"]]))


## ---------------------------------------------------------------- fixtures for the palette items
func make_poses() -> void:
	var b := DistanceKeeper.new_body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	stand = b.to_dict()
	b.fk()
	b.from_dict(stand)
	b.ang["upperarm_r"] = Vector3(-90, 0, 0)
	b.fk()
	punch_r = b.to_dict()


func hero() -> Scene:
	var wind := FightRhythm.blend_pose(stand, punch_r, 0.5)
	var S := Scene.new()
	S.from_dict({"scene": "zz_hero", "fps": 30, "cards": [{"name": "guard", "pose": stand, "move": -1.0, "hold": 0.5},
		{"name": "wind-up", "pose": wind, "move": 0.3, "hold": 0.1}, {"name": "jab", "pose": punch_r, "move": 0.15, "hold": 0.0},
		{"name": "guard", "pose": stand, "move": 0.2, "hold": 0.3}]})
	Markers.add(S.markers, float(S.times()[2][1]), "hit", "hit")
	return S


func still() -> Scene:
	var S := Scene.new()
	S.from_dict({"scene": "zz_still", "fps": 30, "cards": [{"name": "guard", "pose": stand, "move": -1.0, "hold": 0.8},
		{"name": "guard", "pose": stand, "move": 0.3, "hold": 0.6}]})
	return S


func blocker(onset: float) -> Scene:
	var S := Scene.new()
	S.from_dict({"scene": "zz_blocker", "fps": 30, "cards": [{"name": "guard", "pose": stand, "move": -1.0, "hold": onset},
		{"name": "block", "pose": stand, "move": 0.25, "hold": 0.2}, {"name": "guard", "pose": stand, "move": 0.3, "hold": 0.4}]})
	return S


func pair(A: Scene, D: Scene) -> Scene:
	var S := A.clone()
	S.actors = [{"name": "B", "xf": {"pos": [0.0, 1.1], "yaw": 180.0}, "scene": D}]
	return S


func save(S: Scene, name: String) -> String:
	DirAccess.make_dir_recursive_absolute("user://uiwire")
	var p := ProjectSettings.globalize_path("user://uiwire/" + name + ".json")
	var fh := FileAccess.open(p, FileAccess.WRITE)
	fh.store_string(JSON.stringify(S.to_dict(DistanceKeeper.new_body(), false)))
	fh.close()
	return p


func opened(S: Scene, name: String) -> void:
	await req("open", {"path": save(S, name)})
	await idle()


## a small mirror-symmetric rig with keys at frames 0 and 10
func mir(t: Transform3D) -> Transform3D:
	var MX := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
	return Transform3D(MX * t.basis * MX, Vector3(-t.origin.x, t.origin.y, t.origin.z))


func small_rig() -> Dictionary:
	var rows := []
	var add := func(n: String, p: String, o: Vector3, e: Vector3):
		rows.append([n, p, Transform3D(Basis.from_euler(e), o)])
	var prs := func(nl: String, nr: String, pl: String, pr: String, o: Vector3, e: Vector3):
		var t := Transform3D(Basis.from_euler(e), o)
		rows.append([nl, pl, t])
		rows.append([nr, pr, mir(t)])
	add.call("root", "", Vector3(0, 0.5, 0), Vector3.ZERO)
	add.call("hips", "root", Vector3(0, 0.05, 0), Vector3(0.1, 0, 0))
	add.call("spine", "hips", Vector3(0, 0, 0.15), Vector3(-0.05, 0, 0))
	add.call("head", "spine", Vector3(0, 0.03, 0.12), Vector3(0.3, 0, 0))
	prs.call("arm_l", "arm_r", "spine", "spine", Vector3(0.08, -0.05, 0.0), Vector3(1.4, 0.0, 0.1))
	prs.call("hand_l", "hand_r", "arm_l", "arm_r", Vector3(0, 0, 0.2), Vector3(-0.5, 0.0, 0.0))
	var names := []
	var parent := []
	var rest := []
	for r in rows:
		names.append(r[0])
		var pi := -1
		for k in rows.size():
			if rows[k][0] == r[1]:
				pi = k
		parent.append(pi)
		rest.append(r[2])
	var rig := {"ok": true, "why": "", "names": names, "parent": parent, "rest": rest, "pose": {}, "keys": {}, "fps": 30.0, "core_matched": 0, "human": false}
	var axes := [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 1, 0)]
	var bones := ["spine", "head", "arm_l", "hand_r"]
	for fi in 2:
		for k in bones.size():
			CustomRig.set_pose(rig, bones[k], Quaternion(axes[k].normalized(), deg_to_rad(25.0 * (fi + 1) * (1.0 if k % 2 == 0 else -1.0))))
		rig["pos"] = Vector3(0.1 * fi, 0.02 * fi, 0.3 * fi)
		CustomRig.key(rig, 10 * fi)
	return rig


func rig_state() -> String:
	var rig: Dictionary = m.S.own_rig
	return var_to_str(rig.get("keys", {})) + var_to_str(rig.get("pose", {})) + var_to_str(rig.get("pkeys", {})) + var_to_str(rig.get("pos", Vector3.ZERO))


func open_graph() -> Control:
	if m.ui_curve == null or not m.ui_curve.visible:
		m._curve_toggle()
	m._curve_sync()
	return m.ui_curve


func qread(text: String) -> Dictionary:
	var out := {}
	for tok in text.split(" ", false):
		if tok.length() > 2 and tok[1] == "=":
			out[tok[0]] = float(tok.substr(2))
	return out


func _init() -> void:
	create_timer(420.0).timeout.connect(func():
		print("UIWIRE WATCHDOG: the test did not finish")
		quit(2))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	T = AgentTools.new(m)
	make_poses()

	# ---------------------------------------------------------------- 1 ANYKEY
	AnyKey.targets = {}
	AnyKey.meshes = {}
	var S1 := scene3()
	m._open_scene_dict("res://scenes/zz_uiwire.json", S1.to_dict(m.B, false), true)
	await idle()
	var same: bool = m.light_key != null and m.light_fill != null and m.light_rim != null and m.floor_mat != null
	same = same and AnyKey.targets.get("key") == m.light_key and AnyKey.targets.get("fill") == m.light_fill
	same = same and AnyKey.targets.get("rim") == m.light_rim and AnyKey.targets.get("floor") == m.floor_mat
	ok(same, "1a opening a scene registers the real key / fill / rim lights and the floor material (targets: %s)" % str(AnyKey.targets.keys()))
	m._kmesh_edit_start()
	await idle()
	ok(m.kmed != null and m.kmed.mesh != null and AnyKey.meshes.get("cube") == m.kmed.mesh, "1a the model cube is registered as mesh 'cube' when it opens")
	var cube: KMesh = m.kmed.mesh
	var dl := PackedVector3Array()
	dl.resize(cube.verts.size())
	dl[0] = Vector3(0.1, 0.0, 0.0)
	KMeshShapes.add_key(cube, "smile", dl, KMeshShapes.BASIS, 0.0)

	var run_key: Callable = cmd("key_this_property")
	ok(run_key.is_valid(), "1b the palette has 'Key this property'")
	run_key.call()
	await idle()
	var W = m.uiw
	ok(W != null and W.panel != null and W.panel.visible, "1b the command opens the wire panel")
	var lid := "prop:key:light_energy"
	var sid := "shape:cube:smile"
	var pick_i := -1
	var shape_i := -1
	for i in W.id_pick.item_count:
		if W.id_pick.get_item_text(i) == lid:
			pick_i = i
		if W.id_pick.get_item_text(i) == sid:
			shape_i = i
	ok(pick_i >= 0 and shape_i >= 0, "1b the picker lists %s (item %d) and %s (item %d) among %d ids" % [lid, pick_i, sid, shape_i, W.id_pick.item_count])
	W.id_pick.select(maxi(pick_i, 0))
	W.id_pick.item_selected.emit(maxi(pick_i, 0))
	ok(W.id_edit.text == lid, "1b picking an id fills the id box ('%s')" % W.id_edit.text)
	var base_any: PackedByteArray = var_to_bytes(m.S.anykeys)
	var u0: int = m.undo.size()
	m.playhead = 0.0
	W.value_box.value = 2.0
	W.key_btn.pressed.emit()
	m.playhead = 1.0
	W.value_box.value = 6.0
	W.key_btn.pressed.emit()
	ok(m.undo.size() == u0 + 2, "1b two Key presses = two undo steps (%d -> %d)" % [u0, m.undo.size()])
	m.playhead = 0.0
	W.id_edit.text = sid
	W.value_box.value = 0.0
	W.key_btn.pressed.emit()
	m.playhead = 1.0
	W.value_box.value = 1.0
	W.key_btn.pressed.emit()
	ok(m.undo.size() == u0 + 4, "1b four Key presses = four undo steps")
	m.S.apply(m.B, 0.5)
	var le: float = m.light_key.light_energy
	ok(absf(le - 4.0) <= 1e-6, "1b the real key light reads %.9f at the midpoint (bar 4.0 +-1e-6)" % le)
	var si := KMeshShapes.find(cube, "smile")
	var sv := float(KMeshShapes.keys(cube)[si]["value"]) if si >= 0 else -1.0
	ok(absf(sv - 0.5) <= 1e-6, "1b the cube's shape key reads %.9f at the midpoint (bar 0.5 +-1e-6)" % sv)
	var ui_any: PackedByteArray = var_to_bytes(m.S.anykeys)
	for i in 4:
		m._undo()
	ok(var_to_bytes(m.S.anykeys) == base_any and m.undo.size() == u0, "1b four undos give the anykeys back byte for byte")
	for kk in [[lid, 0.0, 2.0], [lid, 1.0, 6.0], [sid, 0.0, 0.0], [sid, 1.0, 1.0]]:
		await req("anykey", {"id": kk[0], "t": kk[1], "value": kk[2]})
	ok(var_to_bytes(m.S.anykeys) == ui_any, "1b S.anykeys after the UI keys == after the agent tool 'anykey' keys (byte-identical)")
	# the control: an unregistered target
	var gid := "prop:ghost:roughness"
	m.playhead = 0.0
	W.id_edit.text = gid
	W.value_box.value = 0.7
	u0 = m.undo.size()
	W.key_btn.pressed.emit()
	ok(m.undo.size() == u0 + 1 and m.S.anykeys.has(gid), "1c the unregistered id is still keyed (one undo step), kept in the scene")
	var sk: Array = UiWire.skipped(m.S)
	ok(sk.has(gid) and not sk.has(lid) and not sk.has(sid), "1c UiWire.skipped lists only the ghost id: %s" % str(sk))
	ok(W.report.text.contains("ghost") and W.report.text.contains("not registered"), "1c the panel says it: '%s'" % W.report.text)
	ok(W.last_say.contains("not registered") and W.last_say.contains(gid), "1c the status line says it: '%s'" % W.last_say)
	var played := AnyKey.play(m.S, 0.5)
	ok(played == 2, "1c playback writes the 2 registered ids and skips the ghost (%d written)" % played)
	AnyKey.targets["ghost"] = StandardMaterial3D.new()
	control(UiWire.skipped(m.S).has(gid) or AnyKey.play(m.S, 0.5) != 3, "registering the ghost target empties the list and plays 3 (planted)")
	AnyKey.targets.erase("ghost")
	m._undo()

	# ---------------------------------------------------------------- 2 GRAPH
	CurveBuffer.slots = []
	var S2 := scene3()
	for tv in [[0.0, Vector3(0, 0, 0)], [1.0, Vector3(40, 10, 0)], [2.0, Vector3(10, -20, 0)]]:
		PartKeys.put(S2.part_keys, "upperarm_r", tv[0], tv[1])
	use(S2)
	m.sel = "upperarm_r"
	var ed = open_graph()
	await idle(4)
	ok(ed != null and ed.size.x > 100.0 and ed.size.y > 60.0, "2 the graph editor is open and laid out (%s)" % str(ed.size))
	ed.frame_all()
	var k1: Vector2 = ed.key_pos(0, 1)
	mbtn(ed, k1, true)
	mbtn(ed, k1, false)
	var hp: Vector2 = ed.handle_pos(0, 1, "out")
	var hh: Array = ed.pick_handle(hp)
	ok(ed.sel_i == 1 and hh.size() == 3 and hh[1] == 1 and hh[2] == "out", "2 clicking the key shows its out handle (%s)" % str(hh))
	# 2a ghost
	var orig_keys: Array = (m.S.part_keys["upperarm_r"] as Array).duplicate(true)
	var gb = ed._ghost_btn
	ok(gb != null and gb is Button and gb.toggle_mode and ed.ghost_line(0).is_empty(), "2a there is a Ghost toggle, and with it off the ghost line is empty")
	var uG: int = m.undo.size()
	gb.button_pressed = true
	ok(not ed.ghost_keys.is_empty() and m.undo.size() == uG, "2a Ghost on shows the buffer and pushes no undo step")
	var snap := await req("curve_graph", {"action": "snapshot", "joint": "upperarm_r"})
	var slot := int(snap.get("result", {}).get("slot", -1))
	ok(slot >= 0 and var_to_bytes(CurveBuffer.keys_of(slot)) == var_to_bytes(ed.ghost_keys), "2a ghost_keys == the agent tool's snapshot of the joint (bytes)")
	# 2b weight (alt-drag), the live curve is edited while the ghost stays
	var base_pk: PackedByteArray = var_to_bytes(m.S.part_keys)
	var base_kv: PackedByteArray = kbytes(m.S.part_keys["upperarm_r"])
	var w_in0 := PartKeys.weight_of(m.S.part_keys["upperarm_r"], 1, "in")
	var tgt := Vector2(ed.t_to_x(1.0 + 2.0 / 3.0), hp.y - 20.0)
	var u1: int = m.undo.size()
	mbtn(ed, hp, true, true)
	mmov(ed, hp + Vector2(8, -6), true)
	mmov(ed, (hp + tgt) * 0.5, true)
	mmov(ed, tgt, true)
	mbtn(ed, tgt, false, true)
	var wk: Array = m.S.part_keys["upperarm_r"]
	var w_out := PartKeys.weight_of(wk, 1, "out")
	ok(absf(w_out - 2.0) <= 1e-4, "2b Alt-drag sets the out weight to %.6f (bar 2.0 +-1e-4)" % w_out)
	ok(kbytes(wk) == base_kv and absf(PartKeys.weight_of(wk, 1, "in") - w_in0) <= 1e-9, "2b key times and values and the other handle's weight are untouched")
	ok(m.undo.size() == u1 + 1, "2b the whole drag is ONE undo step (%d -> %d)" % [u1, m.undo.size()])
	var ui_pk: PackedByteArray = var_to_bytes(m.S.part_keys)
	var worst_g := 0.0
	for p in ed.ghost_line(0):
		var want_y: float = ed.cv_to_y(0, PartKeys.value_at(orig_keys, ed.x_to_t(p.x))[0])
		worst_g = maxf(worst_g, absf(p.y - want_y))
	ok(ed.ghost_line(0).size() > 50 and worst_g <= 0.01, "2a every ghost point lies on the original curve while the live one changed: worst %.5f px over %d points" % [worst_g, ed.ghost_line(0).size()])
	var stored: float = float((wk[1] as Dictionary).get("wout", 1.0))
	m._undo()
	ok(var_to_bytes(m.S.part_keys) == base_pk, "2b one undo gives the part keys back byte for byte")
	await req("curve_graph", {"action": "weight", "joint": "upperarm_r", "key": 1, "side": "out", "weight": stored})
	ok(var_to_bytes(m.S.part_keys) == ui_pk, "2b part_keys after the Alt-drag == after the agent tool weight %.6f (byte-identical)" % stored)
	m._undo()
	# control: the same drag without Alt moves the slope
	mbtn(ed, hp, true, false)
	mmov(ed, hp + Vector2(8, -6))
	mmov(ed, tgt)
	mbtn(ed, tgt, false)
	control(var_to_bytes(m.S.part_keys) == ui_pk, "the same drag without Alt gives the Alt result")
	m._undo()
	gb.button_pressed = false
	ok(ed.ghost_keys.is_empty() and ed.ghost_line(0).is_empty(), "2a Ghost off hides it")

	# ---------------------------------------------------------------- 3 AU
	CurveBuffer.slots = []
	var S3 := scene3()
	for tv in [[0.0, 0.2], [1.0, 1.3], [2.0, 0.4]]:
		PartKeys.put(S3.face, "jaw", tv[0], Vector3(tv[1], 0, 0))
	use(S3)
	m.sel = "upperarm_r"
	ed = open_graph()
	await idle(3)
	var ap = ed._au_pick
	var ji := -1
	for i in ap.item_count:
		if ap.get_item_text(i) == "jaw":
			ji = i
	ok(ap != null and ji > 0, "3 the channel picker lists the face channels ('jaw' at item %d of %d)" % [ji, ap.item_count])
	ap.select(ji)
	ap.item_selected.emit(ji)
	m._curve_sync()
	ed.frame_all()
	await idle(2)
	ok(ed.au and ed.joint == "jaw", "3 picking 'jaw' puts the editor in au mode on jaw (au=%s joint=%s) and the sync keeps it" % [str(ed.au), ed.joint])
	var worst_au := 0.0
	var top := 0.0
	for p in ed.polyline(0):
		var vv := AuCurves.value_at(m.S.face, "jaw", ed.x_to_t(p.x))
		top = maxf(top, vv)
		worst_au = maxf(worst_au, absf(p.y - ed.cv_to_y(0, vv)))
	ok(worst_au <= 0.01 and top <= 1.0 + 1e-9 and float(m.S.face["jaw"][1]["v"].x) > 1.0, "3 the drawn curve == AuCurves.value_at, worst %.5f px, drawn max %.4f <= 1 (the key holds 1.3)" % [worst_au, top])
	var ak1: Vector2 = ed.key_pos(0, 1)
	mbtn(ed, ak1, true)
	mbtn(ed, ak1, false)
	var ahp: Vector2 = ed.handle_pos(0, 1, "out")
	var atgt := Vector2(ed.t_to_x(1.0 + 2.0 / 3.0), ahp.y - 15.0)
	var base_face: PackedByteArray = var_to_bytes(m.S.face)
	var base_pk3: PackedByteArray = var_to_bytes(m.S.part_keys)
	var uA: int = m.undo.size()
	mbtn(ed, ahp, true, true)
	mmov(ed, ahp + Vector2(8, -6), true)
	mmov(ed, atgt, true)
	mbtn(ed, atgt, false, true)
	var ui_face: PackedByteArray = var_to_bytes(m.S.face)
	var aw := PartKeys.weight_of(m.S.face["jaw"], 1, "out")
	ok(absf(aw - 2.0) <= 1e-4 and m.undo.size() == uA + 1 and var_to_bytes(m.S.part_keys) == base_pk3, "3 Alt-drag in au mode: weight %.6f, one undo step, part keys untouched" % aw)
	var astored: float = float((m.S.face["jaw"][1] as Dictionary).get("wout", 1.0))
	m._undo()
	ok(var_to_bytes(m.S.face) == base_face, "3 one undo gives the face keys back")
	await req("curve_graph", {"action": "weight", "au": "jaw", "key": 1, "side": "out", "weight": astored})
	ok(var_to_bytes(m.S.face) == ui_face, "3 face keys after the Alt-drag == after curve_graph {au: jaw} weight (byte-identical)")
	ap.select(0)
	ap.item_selected.emit(0)
	m._curve_sync()
	ok(not ed.au and ed.joint == "upperarm_r", "3 picking 'Part keys' returns to the picked part (au=%s joint=%s)" % [str(ed.au), ed.joint])

	# ---------------------------------------------------------------- 5 SLERP (before the palette items: the same graph fixture)
	var S5 := scene3()
	for tv in [[0.0, Vector3(0, 0, 0)], [1.0, Vector3(40, 10, 0)], [2.0, Vector3(10, -20, 0)]]:
		PartKeys.put(S5.part_keys, "upperarm_r", tv[0], tv[1])
	use(S5)
	m.sel = "upperarm_r"
	ed = open_graph()
	await idle(3)
	ed.frame_all()
	var im = ed._interp
	ok(im != null and im is MenuButton, "5 the curve editor has an Interp menu")
	var texts := []
	for i in im.get_popup().item_count:
		texts.append(im.get_popup().get_item_text(i))
	ok(texts.has("slerp") and texts.has("bezier") and texts.has("constant") and texts.has("linear"), "5 the Interp menu lists bezier / constant / linear / slerp (%s)" % str(texts))
	var base5: PackedByteArray = var_to_bytes(m.S.part_keys)
	var u5: int = m.undo.size()
	var k0: Vector2 = ed.key_pos(0, 0)
	mbtn(ed, k0, true)
	mbtn(ed, k0, false)
	var id_slerp := -1
	var id_on := -1
	var id_off := -1
	for i in im.get_popup().item_count:
		var tx: String = im.get_popup().get_item_text(i)
		if tx == "slerp":
			id_slerp = im.get_popup().get_item_id(i)
		elif tx.begins_with("Slerp the whole part") and tx.ends_with("on"):
			id_on = im.get_popup().get_item_id(i)
		elif tx.begins_with("Slerp the whole part") and tx.ends_with("off"):
			id_off = im.get_popup().get_item_id(i)
	ok(id_slerp >= 0 and id_on >= 0 and id_off >= 0 and id_on != id_off, "5 the menu has slerp for the picked key and 'Slerp the whole part' on / off")
	m.playhead = 0.0
	im.get_popup().id_pressed.emit(id_slerp)
	var ui_one: PackedByteArray = var_to_bytes(m.S.part_keys)
	ok(m.undo.size() == u5 + 1 and PartKeys.interp_of(m.S.part_keys["upperarm_r"][0]) == "slerp" and PartKeys.interp_of(m.S.part_keys["upperarm_r"][1]) != "slerp", "5 'slerp' on the picked key: key 0 only, one undo step")
	m._undo()
	cmd("part_key_slerp_interpolation").call()
	ok(var_to_bytes(m.S.part_keys) == ui_one, "5 the menu item == the palette command 'Part key: slerp interpolation' (byte-identical)")
	m._undo()
	ok(var_to_bytes(m.S.part_keys) == base5, "5 undo gives the keys back")
	u5 = m.undo.size()
	im.get_popup().id_pressed.emit(id_on)
	var ui_on: PackedByteArray = var_to_bytes(m.S.part_keys)
	ok(m.undo.size() == u5 + 1, "5 'Slerp the whole part on' = one undo step")
	m._undo()
	await req("euler_warp", {"action": "slerp", "joints": ["upperarm_r"], "on": true})
	ok(var_to_bytes(m.S.part_keys) == ui_on, "5 the menu == the euler_warp slerp tool, on (byte-identical)")
	im.get_popup().id_pressed.emit(id_off)
	var ui_off: PackedByteArray = var_to_bytes(m.S.part_keys)
	m._undo()
	await req("euler_warp", {"action": "slerp", "joints": ["upperarm_r"], "on": false})
	ok(var_to_bytes(m.S.part_keys) == ui_off, "5 the menu == the euler_warp slerp tool, off (byte-identical)")
	m._undo()
	m._undo()
	# quaternion readout
	var run_q: Callable = cmd("quaternion_view_show_the_readout")
	ok(run_q.is_valid(), "5 the palette has 'Quaternion view: show the readout'")
	run_q.call()
	await idle()
	W = m.uiw
	var ql = W.quat_label
	ok(ql is Label and not (ql is LineEdit), "5 the readout is a read-only Label")
	var pk5: PackedByteArray = var_to_bytes(m.S.part_keys)
	u5 = m.undo.size()
	var worst_q := 0.0
	for pt in [0.5, 1.25]:
		m.playhead = pt
		m._refresh()
		var got := qread(ql.text)
		var qr := await req("euler_warp", {"action": "quat", "joint": "upperarm_r", "t0": pt, "t1": pt})
		var fr: Array = qr.get("result", {}).get("frames", [[0, 0, 0, 0, 0]])
		var f0: Array = fr[0]
		var dq := 0.0
		for pair_i in [["w", 1], ["x", 2], ["y", 3], ["z", 4]]:
			dq = maxf(dq, absf(float(got.get(pair_i[0], 99.0)) - float(f0[pair_i[1]])))
		worst_q = maxf(worst_q, dq)
		print("     playhead %.2f  readout '%s'  tool %s" % [pt, ql.text, str(f0)])
	ok(worst_q <= 1e-5, "5 the readout == the tool 'quat' frame at two playheads, worst %.8f (bar 1e-5)" % worst_q)
	ok(m.undo.size() == u5 and var_to_bytes(m.S.part_keys) == pk5, "5 the readout changes nothing (no undo step, keys unchanged)")

	# ---------------------------------------------------------------- 4 PALETTE items
	# rig_anim mirror on a custom rig
	var S4 := scene3()
	S4.own_rig = small_rig()
	use(S4)
	var r_before := rig_state()
	var run_mp: Callable = cmd("rig_mirror_the_pose")
	var run_mk: Callable = cmd("rig_mirror_the_keys")
	ok(run_mp.is_valid() and run_mk.is_valid(), "4 the palette has 'Rig: mirror the pose' and 'Rig: mirror the keys'")
	for it in [["pose", run_mp, "pose"], ["keys", run_mk, "keys"]]:
		var uR: int = m.undo.size()
		it[1].call()
		var ui_r := rig_state()
		ok(m.undo.size() == uR + 1 and ui_r != r_before, "4 rig mirror %s: one undo step, the rig changed" % it[0])
		m._undo()
		ok(rig_state() == r_before, "4 rig mirror %s: one undo gives the rig back" % it[0])
		await req("rig_anim", {"action": "mirror", "what": it[2]})
		ok(rig_state() == ui_r, "4 rig mirror %s == the rig_anim tool (byte-identical)" % it[0])
		m._undo()
	use(scene3())
	var uN: int = m.undo.size()
	run_mk.call()
	ok(m.undo.size() == uN and m.uiw.last_say.contains("no own rig"), "4 CONTROL: no own rig -> no undo step, the status line says why ('%s')" % m.uiw.last_say)
	# react
	var Aa := hero()
	var cue := ReactTime.cue(Aa)
	await opened(pair(Aa, blocker(cue + 0.08)), "planted80")
	var b0 := state()
	var run_rp: Callable = cmd("react_place_the_block_after_the_cue")
	var run_rt: Callable = cmd("react_read_the_timing")
	ok(run_rp.is_valid() and run_rt.is_valid(), "4 the palette has 'React: place the block after the cue' and 'React: read the timing'")
	var uT: int = m.undo.size()
	run_rt.call()
	ok(m.undo.size() == uT and state() == b0 and m.uiw.last_say.contains("superhuman"), "4 react read: says superhuman, changes nothing ('%s')" % m.uiw.last_say.left(90))
	run_rp.call()
	var ui_rp := state()
	ok(m.undo.size() == uT + 1 and ui_rp != b0, "4 react place: one undo step, the block moved")
	m._undo()
	ok(state() == b0, "4 react place: one undo gives the scene back")
	await req("react_place", {})
	ok(state() == ui_rp, "4 react place == the react_place tool (byte-identical)")
	m._undo()
	await opened(pair(still(), blocker(0.4)), "nocue")
	b0 = state()
	uT = m.undo.size()
	var er := await req("react_place", {})
	var err_txt := String((er.get("error", {}) as Dictionary).get("message", "?"))
	m.uiw.last_say = ""
	run_rp.call()
	ok(m.undo.size() == uT and state() == b0 and m.uiw.last_say.contains(err_txt), "4 CONTROL: no cue -> no step, unchanged, the status line carries the tool's reason ('%s')" % err_txt.left(70))
	# mass slider
	await opened(hero(), "weight")
	b0 = state()
	cmd("weight_open_the_mass_slider").call()
	await idle()
	W = m.uiw
	var sl: HSlider = W.weight_slider
	uT = m.undo.size()
	sl.value = 1.0
	ok(m.undo.size() == uT and state() == b0, "4 moving the slider handle alone changes nothing until it is released")
	sl.drag_ended.emit(true)
	var ui_ws := state()
	ok(m.undo.size() == uT + 1 and ui_ws != b0, "4 mass slider released at 1.0: one undo step, the clip changed")
	sl.drag_ended.emit(true)
	ok(m.undo.size() == uT + 1, "4 the same value again adds no step")
	m._undo()
	ok(state() == b0, "4 mass slider: one undo gives the clip back")
	var wr := await req("weight_slider", {"value": 1.0})
	ok(state() == ui_ws, "4 mass slider == the weight_slider tool (byte-identical)")
	ok(W.weight_label.text.contains(String(wr.get("result", {}).get("msg", "\u0001"))), "4 the slider's label shows the tool's message ('%s')" % W.weight_label.text.left(90))
	m._undo()

	# ---------------------------------------------------------------- 6 NAMES
	var ids := []
	for c in m._commands():
		ids.append(c["id"])
	var seen := {}
	var dup := false
	for i in ids:
		if seen.has(i):
			dup = true
		seen[i] = true
	ok(not dup, "6 command ids are unique (%d commands)" % ids.size())
	var old_ids := ["curve_editor", "undo", "redo", "bake_to_cards", "key_the_part_here", "graph_editor_every_keyed_part_channels", "graph_editor_normalize",
		"part_keys_add_cycles_modifier", "part_key_bezier_interpolation", "part_key_constant_interpolation", "part_key_linear_interpolation", "part_key_slerp_interpolation",
		"weight_make_it_heavier", "weight_make_it_lighter", "weight_time_the_swing_to_the_weapon", "reduce_part_keys_tolerance_slider", "auto_opponent", "breakdowner_50",
		"mode_easy_13_buttons_large", "help_save_this_session_as_a_script", "record_macro", "stop_macro_recording", "guided_first_pose", "first_steps_tour",
		"breakdown_add_a_key_at_the_playhead_in_between", "model_edit_a_test_cube_preview", "model_subdivide_the_test_cube_catmull-clark"]
	var missing := []
	for i in old_ids:
		if not seen.has(i):
			missing.append(i)
	ok(missing.is_empty(), "6 every pre-existing command id is still there (missing: %s)" % str(missing))
	var new_ids := ["key_this_property", "rig_mirror_the_pose", "rig_mirror_the_keys", "react_place_the_block_after_the_cue", "react_read_the_timing",
		"weight_open_the_mass_slider", "quaternion_view_show_the_readout"]
	var nm := []
	for i in new_ids:
		if not seen.has(i):
			nm.append(i)
	ok(nm.is_empty(), "6 the new commands exist (missing: %s)" % str(nm))
	ok(FileAccess.get_file_as_string("res://tools/run_all.sh").contains("uiwire"), "7 tools/run_all.sh lists uiwire")
	print("UIWIRE: %d fail (%d ok)" % [fails, nok])
	quit(0 if fails == 0 else 1)
