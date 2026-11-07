## godot --path . -s tests/pageundo2_test.gd     (L126, follow-up to P12 pageundo_test: the rest of the edits join the ONE ordered undo log; needs a window)
## P12 put the sculpt sphere, the model cube and the pose steps in one order. Still outside it: the body sculpt's page tag, the weight /
## vertex / texture paint's own Ctrl+Z, the Assembly screen's list (asm_undo) and bl_keys' own Ctrl+Z. And a History-panel jump
## (Main._tree_go) swapped the pose list under a log that still held the old pose entries. Bars, written BEFORE the implementation and
## not moved after a run (pageundo_test and undo_audit are untouched):
##   A  (the fighter's body open on MODEL; real mouse and real keys)
##   1  four different states: a BODY SCULPT stroke (S0 -> S1), a WEIGHT PAINT stroke (S1 -> S2), a POSE KEY (p0 -> p1); page MODEL
##   2  real Ctrl+Z #1 takes back the pose key (pose byte-identical to p0, the body mesh still S2), page MODEL
##   3  Ctrl+Z #2 takes back the weight stroke: the body mesh (verts, faces, bone and weight channels) is byte-identical to S1
##   4  Ctrl+Z #3 takes back the sculpt stroke: byte-identical to S0, page MODEL (the sculpt was left; the body editor owns the step)
##   5  Ctrl+Shift+Z x3 redoes in reverse: S1, S2, then the pose key p1; each byte-identical, page MODEL
##   6  GRS: with the Blender-style layer on, G on a vertex + Enter is a step (S2 -> S3); a pose key follows (p1 -> pg). Ctrl+Z #1 takes back
##      the POSE KEY (not the GRS step: bl_keys used to undo its own list first), Ctrl+Z #2 takes back the GRS (S2). Redo x2 brings both
##   7  HISTORY JUMP: after pose key k2, a weight stroke w2 (S3 -> S4) and pose key k3 made on the SURFACE page, a jump in the History
##      list back to the state after pg lands the pose on pg exactly with the mesh untouched (S4); then Ctrl+Z #1 takes back the WEIGHT
##      STROKE (S3, pose still pg, page MODEL: not the stale k3 entry, which was on SURFACE and would have undone a pose step), Ctrl+Z #2
##      the pose key pg -> p1 (mesh still S3), Ctrl+Z #3 the GRS step (S2)
##   B  (a building project, the Assembly screen)
##   8  a POSE KEY made on ANIMATE, then an ASSEMBLY MOVE (a typed position) on BUILD: Ctrl+Z #1 takes back the move (the record JSON
##      byte-identical to before, page BUILD, the pose still p1b), Ctrl+Z #2 the pose key (p0b, page ANIMATE); Ctrl+Shift+Z brings the key
##      (ANIMATE), Ctrl+Y the move (JSON equal to after, page BUILD)
##   P  planted controls that must be able to fail: a 1e-6 tamper is DIFFERENT under the byte comparison; S0..S4 and p0 / p1 differ
##      pairwise where they must; a hand-built log with a stale pose entry and NO sync picks that wrong entry (page SURFACE), and the same
##      log after sync_pose(1, 1) picks the mesh entry
extends SceneTree

var fails := 0
var m: Node
var A: AssemblyUI


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func move(p: Vector2, held := true, rel := Vector2.ZERO) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func drag(a: Vector2, b: Vector2, steps := 8) -> void:
	await mouse(a, true)
	for k in steps:
		await move(a.lerp(b, (k + 1) / float(steps)))
	await mouse(b, false)
	await idle(2)


func click_at(p: Vector2) -> void:
	await move(p, false)
	await mouse(p, true)
	await mouse(p, false)
	await idle(2)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())
	await idle(2)


func key(k: int, ctrl := false, shift := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = ctrl
		e.shift_pressed = shift
		e.pressed = down
		root.push_input(e, true)
		await process_frame
	await idle(2)


func vbytes(v: PackedVector3Array) -> PackedByteArray:
	return v.to_byte_array()


## the whole mesh: verts, faces and every attribute channel (bones, weights, mask ...)
func msig(mm) -> PackedByteArray:
	var chans := {}
	for k in mm.attrs.keys():
		chans[k] = mm.attrs[k]
	return vbytes(mm.verts) + var_to_bytes(mm.faces) + var_to_bytes(chans)


func pose_sig() -> PackedByteArray:
	return (JSON.stringify(m.B.state()) + JSON.stringify(m.S.cards)).to_utf8_buffer()


func nd(nm: String) -> Node:
	return root.find_child(nm, true, false)


## a screen point (nearest the middle of the view) where the ray from the camera hits `view`'s mesh
func hit_point(view) -> Vector2:
	var vs := root.get_visible_rect().size
	var pts: Array = []
	for yy in range(int(vs.y * 0.25), int(vs.y * 0.8), 14):
		for xx in range(int(vs.x * 0.32), int(vs.x * 0.68), 14):
			pts.append(Vector2(xx, yy))
	var c := vs * 0.5
	pts.sort_custom(func(a, b): return a.distance_to(c) < b.distance_to(c))
	for p in pts:
		var h = view.ray_face(m.cam.project_ray_origin(p), m.cam.project_ray_normal(p))
		if not h.is_empty():
			return p
	return Vector2(-1, -1)


func pose_edit(joint: String, ang: Vector3) -> void:
	m._do(func():
		m.B.ang[joint] = ang
		m.B.fk())
	await idle(2)


func new_main() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false


# ---------------------------------------------------------------- A
func seg_a() -> void:
	await new_main()
	m.S.dq_skin = 0.0
	m.auto_key = true
	m.wp_key = "pageundo2_test"
	# the body sculpt stroke
	ExpertPages._sculpt_body(m)
	await idle(4)
	var on_body: bool = m._body_sculpt_on()
	var kd = m.kmed
	var ks = m.ksc
	ok(on_body and kd != null and ks != null and ks.mesh == kd.mesh, "(0) the body sculpt is open on the body mesh (%s), page %s" % [on_body, m.cur_page])
	var c: Vector3 = ks.view.global_position + Vector3(0, 0.95, 0)
	m._turn_to(0.0, 0.0, 3.0, c, false)
	await idle(6)
	var hp := hit_point(ks.view)
	ok(hp.x >= 0.0, "(0) a screen point %s hits the body mesh" % str(hp))
	var S0 := msig(kd.mesh)
	await drag(hp, hp + Vector2(40, 0))
	var S1 := msig(kd.mesh)
	# back to the body editor (the Esc of the sculpt) and weight paint
	m._page_set("MODEL")
	await idle(4)
	var pset: bool = not m._body_sculpt_on() and kd.on and m.cur_page == "MODEL"
	ok(pset, "(0) MODEL: the sculpt left, the body editor on (%s), page %s" % [pset, m.cur_page])
	var wp := KMeshWPaintUI.of(m)
	var tools = null
	for t in MeshTools.TOOLS:
		if t["do"] == "op:wpaint":
			tools = t
	if tools != null:
		MeshTools.run(tools, m)
	await idle(4)
	var bid := int(wp.bones[wp.bones.size() - 1]["id"]) if not wp.bones.is_empty() else -1
	wp.set_bone(bid)
	wp.brush = KMeshWPaint.SET
	wp.value = 1.0
	wp.strength = 1.0
	wp.radius = 0.04
	var hw := hit_point(kd.view)
	ok(wp.on and bid >= 0 and hw.x >= 0.0, "(0) weight paint is on, bone '%s', a hit point %s" % [wp.bone_name(bid), str(hw)])
	await click_at(hw)
	var S2 := msig(kd.mesh)
	# the pose key (on the mesh page: the body stays open)
	var p0 := pose_sig()
	await pose_edit("upperarm_r", Vector3(0.0, 0.0, 0.9))
	var p1 := pose_sig()
	ok(S0 != S1 and S1 != S2 and p0 != p1 and m.cur_page == "MODEL",
		"(1) three edits: body sculpt stroke %s, weight stroke %s, pose key %s; page %s" % [S0 != S1, S1 != S2, p0 != p1, m.cur_page])
	# 2..4 undo
	await key(KEY_Z, true)
	ok(pose_sig() == p0 and msig(kd.mesh) == S2 and m.cur_page == "MODEL",
		"(2) Ctrl+Z #1: the pose key is back (%s), the body mesh still S2 (%s), page %s" % [pose_sig() == p0, msig(kd.mesh) == S2, m.cur_page])
	await key(KEY_Z, true)
	ok(msig(kd.mesh) == S1 and pose_sig() == p0 and m.cur_page == "MODEL",
		"(3) Ctrl+Z #2: the weight stroke is back, mesh byte-identical to S1 (%s), pose p0 (%s), page %s" % [msig(kd.mesh) == S1, pose_sig() == p0, m.cur_page])
	await key(KEY_Z, true)
	ok(msig(kd.mesh) == S0 and m.cur_page == "MODEL",
		"(4) Ctrl+Z #3: the body sculpt stroke is back, mesh byte-identical to S0 (%s), page %s" % [msig(kd.mesh) == S0, m.cur_page])
	# 5 redo in reverse
	await key(KEY_Z, true, true)
	var r1: bool = msig(kd.mesh) == S1 and m.cur_page == "MODEL"
	await key(KEY_Z, true, true)
	var r2: bool = msig(kd.mesh) == S2 and pose_sig() == p0 and m.cur_page == "MODEL"
	await key(KEY_Z, true, true)
	var r3: bool = pose_sig() == p1 and msig(kd.mesh) == S2 and m.cur_page == "MODEL"
	ok(r1 and r2 and r3, "(5) Ctrl+Shift+Z x3: sculpt stroke %s, weight stroke %s, pose key %s" % [r1, r2, r3])
	# 6 GRS (the Blender-style layer on: bl_keys used to take its own Ctrl+Z first)
	KMeshWPaintUI.toggle(m)
	await idle(3)
	m.blk.set_on(true, false)
	kd.sel.set_mode(KMeshSelect.VERT)
	kd.sel.verts = {120: true}
	await key(KEY_G)
	var gact: bool = m.blk.active == "G"
	var gp := Vector2(root.get_visible_rect().size) * 0.5
	for i in 4:
		await move(gp + Vector2(10 * (i + 1), 0), false, Vector2(10, 0))
	await key(KEY_ENTER)
	var S3 := msig(kd.mesh)
	await pose_edit("upperarm_l", Vector3(0.0, 0.0, -0.7))
	var pg := pose_sig()
	ok(gact and S3 != S2 and pg != p1 and m.blk.active == "", "(6) GRS: G started %s, kept as a step (mesh changed %s), then a pose key (%s)" % [gact, S3 != S2, pg != p1])
	await key(KEY_Z, true)
	var g1: bool = pose_sig() == p1 and msig(kd.mesh) == S3
	await key(KEY_Z, true)
	var g2: bool = msig(kd.mesh) == S2 and pose_sig() == p1
	await key(KEY_Z, true, true)
	var g3: bool = msig(kd.mesh) == S3
	await key(KEY_Z, true, true)
	var g4: bool = pose_sig() == pg and msig(kd.mesh) == S3
	ok(g1 and g2 and g3 and g4, "(6) Ctrl+Z #1 takes the pose key (%s), #2 the GRS step (%s); redo brings the GRS (%s) then the key (%s)" % [g1, g2, g3, g4])
	# 7 the History jump
	KMeshWPaintUI.toggle(m)
	await idle(3)
	await pose_edit("lowerarm_r", Vector3(0.0, 0.0, 0.5))
	wp.value = 0.0
	var hw2 := hit_point(kd.view)
	await click_at(hw2)
	var S4 := msig(kd.mesh)
	m._page_set("SURFACE")
	await idle(3)
	var on_surface: bool = m.cur_page == "SURFACE"
	await pose_edit("lowerarm_l", Vector3(0.0, 0.0, 0.6))
	m._page_set("MODEL")
	await idle(3)
	var U: int = m.undo.size()
	m._history_go(U - 2)
	await idle(3)
	var jumped: bool = pose_sig() == pg and msig(kd.mesh) == S4 and m.undo.size() == U - 2
	ok(on_surface and S4 != S3 and jumped and m.cur_page == "MODEL",
		"(7) jump in the History list to the state after the GRS key: pose is pg %s, mesh untouched S4 %s, %d -> %d steps; k3 was made on SURFACE (%s); page %s" % [pose_sig() == pg, msig(kd.mesh) == S4, U, m.undo.size(), on_surface, m.cur_page])
	await key(KEY_Z, true)
	var j1: bool = msig(kd.mesh) == S3 and pose_sig() == pg and m.cur_page == "MODEL"
	print("measure: after the jump Ctrl+Z #1 -> mesh back to S3 %s, pose untouched %s, page %s" % [msig(kd.mesh) == S3, pose_sig() == pg, m.cur_page])
	await key(KEY_Z, true)
	var j2: bool = pose_sig() == p1 and msig(kd.mesh) == S3 and m.cur_page == "MODEL"
	await key(KEY_Z, true)
	var j3: bool = msig(kd.mesh) == S2 and pose_sig() == p1
	ok(j1 and j2 and j3, "(7) after the jump Ctrl+Z #1 undoes the weight stroke, not a stale pose entry (%s), #2 the pose key (%s), #3 the GRS (%s)" % [j1, j2, j3])
	# P planted controls
	var tam: PackedVector3Array = kd.mesh.verts.duplicate()
	tam[5] += Vector3(1e-6, 0, 0)
	ok(vbytes(tam) != vbytes(kd.mesh.verts) and S0 != S1 and S1 != S2 and S2 != S3 and S3 != S4 and p0 != p1 and p1 != pg,
		"(P) planted: a 1e-6 tamper is detected and the states differ pairwise")
	var PU = load("res://scripts/page_undo.gd")
	var yes := func(_e, _b): return true
	var ua = PU.new()
	ua.note("pose", "MODEL")
	ua.note("model", "MODEL", 1)
	ua.note("pose", "SURFACE")
	var ea: Dictionary = ua.take(true, yes)
	var ub = PU.new()
	ub.note("pose", "MODEL")
	ub.note("model", "MODEL", 1)
	ub.note("pose", "SURFACE")
	ub.sync_pose(1, 1, "MODEL")
	var eb: Dictionary = ub.take(true, yes)
	ok(String(ea.get("k", "")) == "pose" and String(ea.get("page", "")) == "SURFACE" and String(eb.get("k", "")) == "model",
		"(P) planted: a log with a stale pose entry and no sync picks it (%s on %s); after sync_pose(1, 1) it picks '%s'" % [ea.get("k", ""), ea.get("page", ""), eb.get("k", "")])


# ---------------------------------------------------------------- B
func box_rec(nm: String, x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> Dictionary:
	var fs: Array = []
	var pl := "front"
	if z0 != 0.0:
		fs.append({"t": "plane", "id": "f1", "name": "Plane1", "from": "front", "mm": z0})
		pl = "f1"
	var sk := "f%d" % (fs.size() + 1)
	fs.append({"t": "sketch", "id": sk, "name": "Sketch", "plane": pl, "ents": [{"k": "rect", "a": [x0, y0], "b": [x1, y1]}], "dims": []})
	fs.append({"t": "extrude", "id": "f%d" % (fs.size() + 1), "name": "Extrude", "sketch": sk, "dist": z1 - z0, "both": false, "op": "new"})
	var rec := Part.make(nm)
	rec["features"] = fs
	rec["seq"] = fs.size()
	return rec


func part_of(id: String, nm: String, rec: Dictionary, pos := [0.0, 0.0, 0.0]) -> Dictionary:
	return {"id": id, "name": nm, "src": "", "rec": rec, "pos": pos, "rot": [0.0, 0.0, 0.0]}


func seg_b() -> void:
	m.queue_free()
	await idle(4)
	await new_main()
	if not Part.available():
		ok(false, "(8) the CAD DLL is missing")
		return
	m.auto_key = true
	var ss: StartScreen = m.start_screen
	ss.dirs_override = ["user://pageundo2_test"]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(4)
	# the pose key, made on ANIMATE
	m._page_set("ANIMATE")
	await idle(3)
	var pg_key: String = m.cur_page
	var p0 := pose_sig()
	await pose_edit("upperarm_r", Vector3(0.0, 0.0, 0.9))
	var p1 := pose_sig()
	# the assembly on BUILD
	m._page_set("BUILD")
	await idle(3)
	A = m.bld.asm
	m.build_choose.show_chooser()
	await idle(4)
	await click_ctl(nd("build_choose_assembly") as Button)
	await idle(4)
	var rec := Assembly.make("pageundo2")
	rec["parts"] = [part_of("p1", "Base", box_rec("Base", 0, 0, 0, 40, 10, 20)), part_of("p2", "Lid", box_rec("Lid", 0, 0, 0, 20, 5, 20), [0.0, 12.0, 0.0])]
	rec["seq"] = 2
	A.open_record(rec)
	await idle(6)
	var a0 := JSON.stringify(A.asm, "", true)
	var ed := A.pos_edits[0] as LineEdit
	ed.text = "45"
	ed.text_submitted.emit(ed.text)
	await idle(3)
	var a1 := JSON.stringify(A.asm, "", true)
	ok(pg_key == "ANIMATE" and p0 != p1 and a0 != a1 and m.cur_page == "BUILD" and A.on,
		"(8) pose key on %s (%s), assembly move on %s (record changed %s, screen on %s)" % [pg_key, p0 != p1, m.cur_page, a0 != a1, A.on])
	await key(KEY_Z, true)
	var b1: bool = JSON.stringify(A.asm, "", true) == a0 and m.cur_page == "BUILD" and pose_sig() == p1
	await key(KEY_Z, true)
	var b2: bool = pose_sig() == p0 and m.cur_page == "ANIMATE" and JSON.stringify(A.asm, "", true) == a0
	ok(b1 and b2, "(8) Ctrl+Z #1 takes back the assembly move (record identical, page BUILD, pose kept) %s; #2 the pose key (page ANIMATE) %s" % [b1, b2])
	await key(KEY_Z, true, true)
	var b3: bool = pose_sig() == p1 and m.cur_page == "ANIMATE"
	await key(KEY_Y, true)
	var b4: bool = JSON.stringify(A.asm, "", true) == a1 and m.cur_page == "BUILD"
	ok(b3 and b4, "(8) Ctrl+Shift+Z brings the key back on ANIMATE %s; Ctrl+Y the move on BUILD %s" % [b3, b4])


func _init() -> void:
	await seg_a()
	await seg_b()
	print("pageundo2: %d fail" % fails)
	quit(1 if fails > 0 else 0)
