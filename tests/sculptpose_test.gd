## godot --path . -s tests/sculptpose_test.gd     (ROADMAP_400 C19; needs a window: real mouse / key events)
## Sculpt in pose: the fighter's body open in the model preview (G01), the right elbow bent 90 deg, "Model: sculpt the body
## in pose", real inflate strokes on the posed forearm. Bars, stated before the run:
##   0 INSTRUMENT: the forearm bone turns 90 +- 2 deg; the posed body is the skinned one (a vertex weighted 1 to the forearm
##     keeps its distance to the forearm bone within 1 mm of rest, in world space: the preview stands on the fighter)
##   1 PLACEMENT: a click lays its dab under the cursor: the dab centre projects within 2 px of the click; the vertex the
##     click moved most is within 2 cm of it (world)
##   2 LBS EXACT: after an inflate stroke on the posed forearm, re-skinning the edited rest at 90 deg gives the posed
##     result within 1e-5 m on EVERY vertex; > 20 vertices moved; and the map matters (the instrument can move): adding the
##     posed displacement to rest without the inverse misses by > 1 mm
##   3 OUTSIDE THE BRUSH: every rest vertex the stroke did not move is bit-exact; the rest vertices written are exactly the
##     posed vertices moved
##   4 ONE UNDO STEP a stroke (dabs > 1); Ctrl+Z puts rest back bit-exact and the posed body equal to its skin
##   5 AT 0 DEG: moving the pose re-skins the edited rest (the posed body = skin(rest) at 0 deg, within 1e-6 m); the rest
##     vertices that moved are the forearm's: each has more weight on the forearm side than on the upper arm
##   6 DQS: with the scene on dual quaternion, a stroke across the elbow (where DQS differs from LBS by > 0.1 mm on >= 5
##     vertices under the brush) re-skins (DQS) within 1e-5 m on every vertex
##   7 MASK + FACE SETS: masked vertices (mask 1) and the vertices of a hidden face set under the brush stay bit-exact in
##     rest while their neighbours move (control: the same stroke with nothing frozen moves >= 5 of them)
##   8 CORRECTIVE: the same stroke as a corrective leaves rest bit-exact; at 90 deg the posed body equals the rest-mode
##     stroke's within 1e-5 m; its key's value follows the corrective rule (drive(theta) / drive(90): 0 at 0 deg, that
##     ratio at 45 within 1e-6, 1 at 120); at 0 deg the posed body is skin(rest) bit-exact (the shape gone)
##   8b a rest-mode stroke where that corrective is on: skin(rest + key) = posed within 1e-5 m, the key's delta untouched
##   9 Esc: the model preview is back on the rest body (the same KMesh), its undo stack holds the pose strokes
extends SceneTree

var fails := 0
var m: Node
var ui: KMeshSculptUI
var spu: SculptPoseUI
var sp: SculptPose
var skin: Skin
var fore := {}    # bind -> true: lowerarm_r and its children
var upper := {}   # bind -> true: upperarm_r and its children outside the forearm


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


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
	root.push_input(e)
	await process_frame


func move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func drag(a: Vector2, b: Vector2, steps := 6) -> void:
	await mouse(a, true)
	for k in steps:
		await move(a.lerp(b, (k + 1) / float(steps)))
	await mouse(b, false)
	await idle(2)


func key(k: int, ctrl := false, shift := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = ctrl
		e.shift_pressed = shift
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func bend(deg: float) -> void:
	(m.B as Body).ang["lowerarm_r"] = Vector3(deg, 0.0, 0.0)
	m._refresh()
	await idle(3)


func skinned(verts: PackedVector3Array, k: float) -> PackedVector3Array:
	return DqSkin.skin_surface(verts, sp.bo, sp.w, DqSkin.bind_mats(m.skel, skin), k)


func max_err(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var e := 0.0
	for i in a.size():
		e = maxf(e, a[i].distance_to(b[i]))
	return e


func side_w(v: int, bs: Dictionary) -> float:
	var s := 0.0
	for q in 4:
		if bs.has(sp.bo[v * 4 + q]):
			s += sp.w[v * 4 + q]
	return s


func bone_global(name: String) -> Transform3D:
	var sk: Skeleton3D = m.skel
	var b := sk.find_bone(name)
	var t := sk.get_bone_pose(b)
	var p := sk.get_bone_parent(b)
	while p >= 0:
		t = sk.get_bone_pose(p) * t
		p = sk.get_bone_parent(p)
	return sk.global_transform * t


func world(p: Vector3) -> Vector3:
	return ui.view.global_transform * p


## the camera square on posed vertex v (along its normal), 0.7 m away; true when the ray at its projection hits within 1 cm
func face_vertex(v: int) -> bool:
	var n: Vector3 = (ui.view.global_transform.basis * sp.posed.vert_normals[v]).normalized()
	var yaw := rad_to_deg(atan2(n.x, n.z))
	var pitch := -rad_to_deg(asin(clampf(n.y, -1.0, 1.0)))
	m._turn_to(yaw, pitch, 0.7, world(sp.posed.verts[v]), false)
	await idle(3)
	var cam: Camera3D = m.cam
	var hit := ui.surface_at(cam, cam.unproject_position(world(sp.posed.verts[v])))
	return not hit.is_empty() and (hit["point"] as Vector3).distance_to(world(sp.posed.verts[v])) < 0.01


func screen_of(v: int) -> Vector2:
	return (m.cam as Camera3D).unproject_position(world(sp.posed.verts[v]))


func moved_set(a: PackedVector3Array, b: PackedVector3Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in a.size():
		if a[i] != b[i]:
			out.append(i)
	return out


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.S.dq_skin = 0.0
	BaseBody.start(m)
	await idle(3)
	var R: KMesh = m.kmed.mesh
	skin = BaseBody.skin_of(m)
	var sk: Skeleton3D = m.skel
	var la := sk.find_bone("lowerarm_r")
	var ua := sk.find_bone("upperarm_r")
	for b in skin.get_bind_count():
		var c := SkinPaint.bind_bone(skin, sk, b)
		var in_fore := false
		var in_up := false
		while c >= 0:
			if c == la:
				in_fore = true
				break
			if c == ua:
				in_up = true
				break
			c = sk.get_bone_parent(c)
		if in_fore:
			fore[b] = true
		elif in_up:
			upper[b] = true
	# 0 instrument: the elbow turns
	var d0 := bone_global("hand_r").origin - bone_global("lowerarm_r").origin
	await bend(90.0)
	var d90 := bone_global("hand_r").origin - bone_global("lowerarm_r").origin
	var turn := rad_to_deg(d0.angle_to(d90))
	var said := SculptPoseUI.op("sculpt_pose", m)
	await idle(3)
	spu = SculptPoseUI.get_ui(m)
	sp = spu.sp
	ui = m.ksc
	ok(spu.is_on() and ui.mesh == sp.posed and sp.rest == R and not m.kmed.on, "the op opens the pose sculpt on the body: %s" % said.left(120))
	# a vertex weighted 1 to the forearm, mid forearm
	await bend(0.0)
	var e0 := bone_global("lowerarm_r").origin
	var h0 := bone_global("hand_r").origin
	var mid0 := (e0 + h0) * 0.5
	var cands := []
	for v in R.verts.size():
		if side_w(v, fore) >= 0.999 and maxf(maxf(sp.w[v * 4], sp.w[v * 4 + 1]), maxf(sp.w[v * 4 + 2], sp.w[v * 4 + 3])) >= 0.999:
			var wp := world(sp.posed.verts[v])
			cands.append([wp.distance_to(mid0), v, wp.distance_to(Geometry3D.get_closest_point_to_segment(wp, e0, h0))])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	await bend(90.0)
	var e9 := bone_global("lowerarm_r").origin
	var h9 := bone_global("hand_r").origin
	var vA := -1
	var segd0 := 0.0
	var segd9 := 0.0
	var faced := false
	for c in cands.slice(0, 80):   # the first one the camera sees unhidden along its normal
		if await face_vertex(c[1]):
			vA = c[1]
			segd0 = c[2]
			faced = true
			break
	if vA >= 0:
		segd9 = world(sp.posed.verts[vA]).distance_to(Geometry3D.get_closest_point_to_segment(world(sp.posed.verts[vA]), e9, h9))
	ok(absf(turn - 90.0) <= 2.0 and vA >= 0 and absf(segd9 - segd0) < 0.001,
		"(0) instrument: the forearm turned %.2f deg; vertex %d (weight 1 forearm, mid forearm) is %.4f m from the forearm bone at 0 deg, %.4f m at 90 (world: the preview stands on the fighter)" % [turn, vA, segd0, segd9])
	ui.radius = 0.1   # the mannequin forearm is low-poly: a 10 cm brush run toward the wrist reaches > 20 vertices, not the elbow
	await key(KEY_I)
	faced = await face_vertex(vA)
	var cam: Camera3D = m.cam
	var sA := screen_of(vA)
	var along := (cam.unproject_position(h9) - cam.unproject_position(e9)).normalized()   # strokes run along the forearm
	# 1 placement: one click = one dab
	var P0 := sp.posed.verts.duplicate()
	var R0 := R.verts.duplicate()
	await mouse(sA, true)
	await mouse(sA, false)
	await idle(2)
	var dab_px := cam.unproject_position(world(ui.sculpt._last)).distance_to(sA)
	var mv := -1
	var md := 0.0
	for v in P0.size():
		var dd := sp.posed.verts[v].distance_to(P0[v])
		if dd > md:
			md = dd
			mv = v
	var near_m := world(sp.posed.verts[mv]).distance_to(world(ui.sculpt._last)) if mv >= 0 else INF
	ok(faced and dab_px <= 2.0 and near_m <= 0.02, "(1) placement: the dab lands %.2f px from the click; the vertex moved most (%.2f mm) is %.4f m from it (camera faces the forearm %s)" % [dab_px, md * 1000.0, near_m, faced])
	await key(KEY_Z, true)
	# 2-4 the inflate stroke at 90 deg, LBS
	var steps0: int = ui.undo.steps.size()
	await drag(sA + along * 15.0, sA + along * 70.0)
	var PA := sp.posed.verts.duplicate()
	var RA := R.verts.duplicate()
	var dabs: int = ui.sculpt.dabs
	var pm := moved_set(P0, PA)
	var rm := moved_set(R0, RA)
	var err := max_err(skinned(RA, 0.0), PA)
	var naive := R0.duplicate()
	for v in pm:
		naive[v] += PA[v] - P0[v]
	var nerr := max_err(skinned(naive, 0.0), PA)
	ok(pm.size() > 20 and err <= 1e-5 and nerr > 0.001, "(2) LBS: %d posed vertices moved (up to %.2f mm); re-skinned rest vs posed: max %.7f m (bar 1e-5); without the inverse it would miss by %.2f mm" % [pm.size(), max_err(P0, PA) * 1000.0, err, nerr * 1000.0])
	var outside_exact := true
	var inb := {}
	for v in pm:
		inb[v] = true
	for v in R0.size():
		if not inb.has(v) and R.verts[v] != R0[v]:
			outside_exact = false
	ok(outside_exact and rm == pm, "(3) outside the brush: every unmoved rest vertex bit-exact %s; rest written = posed moved (%d = %d)" % [outside_exact, rm.size(), pm.size()])
	var one := ui.undo.steps.size() - steps0
	await key(KEY_Z, true)
	var back_exact: bool = R.verts == R0
	var pskin := max_err(sp.posed.verts, skinned(R.verts, 0.0))
	ok(dabs > 1 and one == 1 and back_exact and pskin == 0.0, "(4) %d dabs = %d undo step; Ctrl+Z: rest bit-exact %s, posed = skin(rest) (max %.7f)" % [dabs, one, back_exact, pskin])
	await key(KEY_Z, true, true)   # redo: the stroke back
	var redo_ok: bool = R.verts == RA
	# 5 at 0 deg
	var rs0: int = spu.reskins
	await bend(0.0)
	var at0 := max_err(sp.posed.verts, skinned(R.verts, 0.0))
	var s_new := skinned(R.verts, 0.0)
	var s_old := skinned(R0, 0.0)
	var m0 := moved_set(s_old, s_new)
	var all_fore := m0.size() > 0
	var worst := 1.0
	for v in m0:
		var mar := side_w(v, fore) - side_w(v, upper)
		worst = minf(worst, mar)
		all_fore = all_fore and mar > 0.0
	ok(redo_ok and spu.reskins > rs0 and at0 <= 1e-6 and all_fore and m0.size() == pm.size(),
		"(5) 0 deg: re-skinned (%d -> %d), posed = skin(rest) max %.7f; %d rest vertices moved, all forearm-side %s (smallest forearm - upper arm weight %.3f); redo exact %s" % [rs0, spu.reskins, at0, m0.size(), all_fore, worst, redo_ok])
	# 6 DQS across the elbow
	await bend(90.0)
	m.S.dq_skin = 1.0
	await idle(3)
	var lbs90 := skinned(R.verts, 0.0)
	var dqs90 := skinned(R.verts, 1.0)
	var cand := []
	for v in R.verts.size():
		if side_w(v, fore) >= 0.3 and side_w(v, upper) >= 0.3:
			cand.append([lbs90[v].distance_to(dqs90[v]), v])
	cand.sort_custom(func(a, b): return a[0] > b[0])
	var vB := -1
	for c in cand.slice(0, 40):
		if await face_vertex(c[1]):
			vB = c[1]
			break
	var dq_on := max_err(sp.posed.verts, dqs90)
	var P1 := sp.posed.verts.duplicate()
	var differ := 0
	if vB >= 0:
		for v in R.verts.size():
			if P1[v].distance_to(P1[vB]) < ui.radius and lbs90[v].distance_to(dqs90[v]) > 1e-4:
				differ += 1
		var sB := screen_of(vB)
		await drag(sB - Vector2(10, 0), sB + Vector2(10, 0))
	var pmB := moved_set(P1, sp.posed.verts)
	var errB := max_err(skinned(R.verts, 1.0), sp.posed.verts)
	ok(vB >= 0 and dq_on <= 1e-6 and differ >= 5 and pmB.size() > 10 and errB <= 1e-5,
		"(6) DQS: the posed body is the DQS skin (%.7f); elbow vertex %d, %d vertices under the brush where DQS and LBS differ > 0.1 mm; %d moved; re-skinned (DQS) rest vs posed max %.7f m (bar 1e-5)" % [dq_on, vB, differ, pmB.size(), errB])
	await key(KEY_Z, true)
	m.S.dq_skin = 0.0
	await idle(3)
	# 7 mask + face sets on the forearm stroke
	await face_vertex(vA)
	sA = screen_of(vA)
	var right: Vector3 = (h9 - e9).normalized()
	var cw := world(sp.posed.verts[vA])
	var mask := PackedFloat32Array()
	mask.resize(R.verts.size())
	var masked := PackedInt32Array()
	var hidv := {}
	for v in R.verts.size():
		var o := world(sp.posed.verts[v]) - cw
		if o.length() < 0.12 and o.dot(right) > 0.02:
			mask[v] = 1.0
			masked.append(v)
	var hf := []
	for fi in R.faces.size():
		var fc := Vector3.ZERO
		for v in (R.faces[fi] as PackedInt32Array):
			fc += world(sp.posed.verts[v]) / 3.0
		var all_in := true
		for v in (R.faces[fi] as PackedInt32Array):
			all_in = all_in and (world(sp.posed.verts[v]) - cw).dot(right) < -0.02
		if all_in and (fc - cw).length() < 0.1:
			hf.append(fi)
	var fid := KMeshFaceSets.from_faces(R, hf)
	KMeshFaceSets.hide(R, fid)
	for fi in hf:
		for v in (R.faces[fi] as PackedInt32Array):
			hidv[v] = true
	R.set_attr_data(KMeshMask.NAME, mask)
	sp.reskin()
	ui.view.mark_dirty()
	var R7 := R.verts.duplicate()
	var P7 := sp.posed.verts.duplicate()
	await drag(sA - along * 50.0, sA + along * 50.0, 10)
	var mk_exact := true
	for v in masked:
		mk_exact = mk_exact and R.verts[v] == R7[v]
	var fs_exact := true
	for v in hidv:
		fs_exact = fs_exact and R.verts[v] == R7[v]
	var moved7 := moved_set(R7, R.verts).size()
	await key(KEY_Z, true)
	mask.fill(0.0)
	R.set_attr_data(KMeshMask.NAME, mask)
	KMeshFaceSets.show_all(R)
	sp.reskin()
	ui.view.mark_dirty()
	await idle(2)
	await drag(sA - along * 50.0, sA + along * 50.0, 10)   # the control: the same stroke, nothing frozen
	var would := 0
	for v in masked:
		would += 1 if R.verts[v] != R7[v] else 0
	for v in hidv:
		would += 1 if R.verts[v] != R7[v] else 0
	await key(KEY_Z, true)
	ok(masked.size() > 5 and hidv.size() > 5 and mk_exact and fs_exact and moved7 > 10 and would >= 5 and R.verts == R7,
		"(7) %d masked vertices bit-exact %s, %d vertices of a hidden face set bit-exact %s, %d others moved; the same stroke with nothing frozen moves %d of them" % [masked.size(), mk_exact, hidv.size(), fs_exact, moved7, would])
	# 8 corrective: the stroke of bar 2 again, as a corrective
	await face_vertex(vA)
	sA = screen_of(vA)
	var R8 := R.verts.duplicate()
	var P8 := sp.posed.verts.duplicate()
	await drag(sA + along * 15.0, sA + along * 70.0)
	var PR := sp.posed.verts.duplicate()   # the rest-mode result
	await key(KEY_Z, true)
	var same_start: bool = sp.posed.verts == P8
	SculptPoseUI.op("sculpt_pose_corr", m)
	await drag(sA + along * 15.0, sA + along * 70.0)
	var rest_exact: bool = R.verts == R8
	var kn := sp.last_key
	var at90 := max_err(sp.posed.verts, PR)
	var moved90 := max_err(sp.posed.verts, P8)
	var ki := KMeshShapes.find(R, kn)
	var vals := {}
	for deg in [0.0, 45.0, 120.0]:
		await bend(deg)
		vals[deg] = float(KMeshShapes.keys(R)[ki]["value"]) if ki >= 0 else NAN
		if deg == 0.0:
			vals["skin0"] = sp.posed.verts == skinned(R.verts, 0.0)
	var want45 := Corrective.drive_of(45.0) / Corrective.drive_of(90.0)
	ok(rest_exact and same_start and ki >= 0 and moved90 > 0.001 and at90 <= 1e-5 and vals[0.0] == 0.0 and absf(vals[45.0] - want45) <= 1e-6 and vals[120.0] == 1.0 and vals["skin0"],
		"(8) corrective '%s': rest bit-exact %s; at 90 deg the posed body moved %.2f mm and matches the rest-mode stroke within %.7f m; value 0 deg %.3f, 45 deg %.6f (rule %.6f), 120 deg %.3f; at 0 deg posed = skin(rest) bit-exact %s" % [kn, rest_exact, moved90 * 1000.0, at90, vals[0.0], vals[45.0], want45, vals[120.0], vals["skin0"]])
	SculptPoseUI.op("sculpt_pose_corr", m)
	# 8b a rest stroke where the corrective is on keeps the key a key (rest gets only the stroke's own change)
	await bend(90.0)
	await face_vertex(vA)
	sA = screen_of(vA)
	var kd: PackedVector3Array = (KMeshShapes.keys(R)[ki]["delta"] as PackedVector3Array).duplicate() if ki >= 0 else PackedVector3Array()
	var Pb := sp.posed.verts.duplicate()
	await drag(sA + along * 15.0, sA + along * 70.0)
	var errk := max_err(skinned(sp.eff_now(), 0.0), sp.posed.verts)
	var key_same: bool = ki >= 0 and (KMeshShapes.keys(R)[ki]["delta"] as PackedVector3Array) == kd
	ok(moved_set(Pb, sp.posed.verts).size() > 10 and errk <= 1e-5 and key_same,
		"(8b) a rest stroke over the corrective at 90 deg: re-skinned rest + key vs posed max %.7f m (bar 1e-5), the key untouched %s" % [errk, key_same])
	# 9 Esc
	var n_steps: int = ui.undo.steps.size()
	var k_steps: int = m.kmed.undo.steps.size()
	await key(KEY_ESCAPE)
	await idle(2)
	ok(not spu.is_on() and m.kmed.on and m.kmed.mesh == R and m.kmed.view.visible and m.kmed.undo.steps.size() == k_steps + n_steps,
		"(9) Esc: back in the model preview on the same rest body %s, its undo stack %d -> %d (the %d pose strokes)" % [m.kmed.mesh == R, k_steps, m.kmed.undo.steps.size(), n_steps])
	print("info: a re-skin of the %d-vertex body takes %.1f ms" % [R.verts.size(), _time_reskin()])
	print("SCULPT POSE ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)


func _time_reskin() -> float:
	var t0 := Time.get_ticks_usec()
	sp.reskin()
	return (Time.get_ticks_usec() - t0) / 1000.0
