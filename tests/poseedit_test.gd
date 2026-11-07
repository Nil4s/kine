## godot --path . -s tests/poseedit_test.gd     (ROADMAP_400 A20; boots main.tscn: needs a window)
## Pose-aware edit: the body is POSED (elbow 90 deg, shoulder raised), a KNOWN posed-space displacement d is applied to a vertex set of
## the forearm through the pose-edit map (SculptPose: stroke_begin / map_back, bracketed by SculptPose.PoseUndo), and the edit lands in REST by
## inverse skinning: rest_delta = inverse(sum_i w_i B_i) * d (LBS, scene blend k = 0). The test's own matrix math (sum of w_i B_i
## component by component, Basis.inverse) is independent of SculptPose.affine_of / to_rest. Bars, written BEFORE any implementation change:
##   0 INSTRUMENT  the forearm turns 90 +- 2 deg at the elbow; the shoulder raise moves the elbow > 5 cm; >= 100 edited vertices
##                 (forearm weight > 0.5) and >= 30 PURE ones (forearm weight 1)
##   1 RESKIN      re-skinning the edited rest at the SAME pose gives posed + d within 1e-5 m on EVERY edited vertex
##   2 REST DELTA  the stored rest delta (new rest - old rest) equals inverse(M) * d computed by the test within 1e-5 m on every
##                 edited vertex (M from the pose the edit was made in); and the delta is NOT d itself (differs by > 1 mm on >= 20 vertices)
##   3 BONE FRAME  another pose (elbow 20, shoulder lowered): each pure vertex keeps its distance to the forearm bone axis (elbow -> hand, world)
##                 within 1e-5 m of what it had in the edit pose; control: the edit changed that distance by > 2 mm on >= 10 pure vertices
##   4 OUTSIDE     every rest vertex not edited is byte-identical (==) after the edit
##   5 ONE UNDO    the whole edit is ONE step on the rest mesh's undo (steps +1); undo puts rest back bit-exact; redo brings the edit back bit-exact
##   6 PLANTED FAKE  the mapping WITHOUT the inverse (rest += d) must FAIL bar 1's check (max error > 1 mm); the real edit passes the same check
##   7 tools/run_all.sh has the poseedit line
extends SceneTree

var fails := 0
var m: Node
var skin: Skin
var sp: SculptPose
const TOL := 1e-5


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func pose(forearm_deg: float, shoulder: Vector3) -> void:
	(m.B as Body).ang["lowerarm_r"] = Vector3(forearm_deg, 0.0, 0.0)
	(m.B as Body).ang["upperarm_r"] = shoulder
	m._refresh()
	await idle(3)


func bone_global(name: String) -> Transform3D:
	var sk: Skeleton3D = m.skel
	var b := sk.find_bone(name)
	var t := sk.get_bone_pose(b)
	var p := sk.get_bone_parent(b)
	while p >= 0:
		t = sk.get_bone_pose(p) * t
		p = sk.get_bone_parent(p)
	return sk.global_transform * t


## the test's own M = sum_i w_i B_i for vertex v (LBS)
func blended(v: int, mats: Array) -> Transform3D:
	var x := Vector3.ZERO
	var y := Vector3.ZERO
	var z := Vector3.ZERO
	var o := Vector3.ZERO
	for q in 4:
		var w := sp.w[v * 4 + q]
		if w <= 0.0:
			continue
		var B: Transform3D = mats[sp.bo[v * 4 + q]]
		x += B.basis.x * w
		y += B.basis.y * w
		z += B.basis.z * w
		o += B.origin * w
	return Transform3D(Basis(x, y, z), o)


## bar 1's check: max |skin(rest_verts) - want| over the edited set
func reskin_err(rest_verts: PackedVector3Array, want: Dictionary, mats: Array) -> float:
	var s := DqSkin.skin_surface(rest_verts, sp.bo, sp.w, mats, 0.0)
	var e := 0.0
	for v in want:
		e = maxf(e, s[v].distance_to(want[v]))
	return e


func axis_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := (p - a).dot(ab) / ab.length_squared()
	return p.distance_to(a + ab * t)


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
	KMeshMask.ensure(R)
	sp = SculptPose.new().setup(R, skin, sk)
	var la := sk.find_bone("lowerarm_r")
	# 0 instrument
	await pose(0.0, Vector3.ZERO)
	var d0 := bone_global("hand_r").origin - bone_global("lowerarm_r").origin
	var el0 := bone_global("lowerarm_r").origin
	await pose(90.0, Vector3(0.0, 0.0, -50.0))
	var d90 := bone_global("hand_r").origin - bone_global("lowerarm_r").origin
	var turn := rad_to_deg(d0.angle_to(d90))
	var lift := bone_global("lowerarm_r").origin.distance_to(el0)
	sp.set_pose(0.0)
	sp.reskin()
	var mats: Array = sp.mats
	var edited := PackedInt32Array()
	var pure := PackedInt32Array()
	for v in R.verts.size():
		var fw := 0.0
		for q in 4:
			var w := sp.w[v * 4 + q]
			if w > 0.0 and SkinPaint.bind_bone(skin, sk, sp.bo[v * 4 + q]) == la:
				fw += w
		if fw > 0.5:
			edited.append(v)
		if fw > 0.9999:
			pure.append(v)
	ok(absf(turn - 90.0) <= 2.0 and lift > 0.05, "0 instrument: forearm turns %.1f deg, shoulder raise moves the elbow %.1f cm" % [turn, lift * 100.0])
	ok(edited.size() >= 100 and pure.size() >= 30, "0 edited set %d (forearm weight > 0.5), pure %d" % [edited.size(), pure.size()])
	# known posed displacement d per edited vertex: about 1 cm plus a per-vertex wiggle
	var dd := {}
	var want := {}
	for v in edited:
		dd[v] = Vector3(0.004, 0.009, -0.003) + Vector3(sin(v * 0.7), cos(v * 1.3), sin(v * 2.1)) * 0.002
		want[v] = sp.posed.verts[v] + dd[v]
	var before := R.verts.duplicate()
	var posed_before := sp.posed.verts.duplicate()
	var un := SculptPose.PoseUndo.new(sp)
	var n_steps := un.steps.size()
	# THE EDIT (one undo step): displace the posed vertices, map back
	un.begin(sp.posed)
	var pv := sp.posed.verts
	for v in edited:
		pv[v] = posed_before[v] + dd[v]
	sp.posed.verts = pv
	un.commit("poseedit")
	var after := R.verts.duplicate()
	# 1 reskin at the same pose
	var e1 := reskin_err(after, want, mats)
	ok(e1 <= TOL, "1 re-skinning the edited rest at the same pose reproduces posed + d: worst %.8f m over %d vertices" % [e1, edited.size()])
	# 2 rest delta vs the test's own inverse
	var worst2 := 0.0
	var differs := 0
	for v in edited:
		var inv: Vector3 = blended(v, mats).basis.inverse() * dd[v]
		var got: Vector3 = after[v] - before[v]
		worst2 = maxf(worst2, got.distance_to(inv))
		if got.distance_to(dd[v]) > 0.001:
			differs += 1
	ok(worst2 <= TOL, "2 stored rest delta = inverse(sum w B) * d: worst %.8f m" % worst2)
	ok(differs >= 20, "2 the delta is not d itself: %d vertices differ by > 1 mm" % differs)
	# 3 bone frame in another pose
	var ax0a := bone_global("lowerarm_r").origin
	var ax0b := bone_global("hand_r").origin
	var dist_a := {}
	var unedited_a := {}
	var sA := DqSkin.skin_surface(after, sp.bo, sp.w, mats, 0.0)
	var sU := DqSkin.skin_surface(before, sp.bo, sp.w, mats, 0.0)
	for v in pure:
		dist_a[v] = axis_dist(sA[v], ax0a, ax0b)
		unedited_a[v] = axis_dist(sU[v], ax0a, ax0b)
	await pose(20.0, Vector3(0.0, 0.0, 30.0))
	sp.set_pose(0.0)
	var mats2: Array = sp.mats
	var ax1a := bone_global("lowerarm_r").origin
	var ax1b := bone_global("hand_r").origin
	var sB := DqSkin.skin_surface(after, sp.bo, sp.w, mats2, 0.0)
	var worst3 := 0.0
	var real := 0
	for v in pure:
		worst3 = maxf(worst3, absf(axis_dist(sB[v], ax1a, ax1b) - float(dist_a[v])))
		if absf(float(dist_a[v]) - float(unedited_a[v])) > 0.002:
			real += 1
	ok(ax1b.distance_to(ax0b) > 0.05, "3 the second pose really moved the hand: %.1f cm" % (ax1b.distance_to(ax0b) * 100.0))
	ok(worst3 <= TOL, "3 distance to the forearm axis preserved in another pose: worst %.8f m over %d pure vertices" % [worst3, pure.size()])
	ok(real >= 10, "3 control: the edit changed that distance by > 2 mm on %d pure vertices" % real)
	# 4 outside
	var same := true
	var is_ed := {}
	for v in edited:
		is_ed[v] = true
	for v in R.verts.size():
		if not is_ed.has(v) and after[v] != before[v]:
			same = false
	ok(same, "4 every unedited rest vertex is byte-identical")
	# 5 one undo step
	ok(un.steps.size() == n_steps + 1, "5 the edit is one undo step (%d -> %d)" % [n_steps, un.steps.size()])
	un.undo()
	ok(R.verts == before, "5 undo puts rest back bit-exact")
	un.redo()
	ok(R.verts == after, "5 redo brings the edit back bit-exact")
	# 6 planted fake: no inverse
	await pose(90.0, Vector3(0.0, 0.0, -50.0))
	sp.set_pose(0.0)
	var fake := before.duplicate()
	for v in edited:
		fake[v] = before[v] + dd[v]
	var e6 := reskin_err(fake, want, sp.mats)
	ok(e6 > 0.001, "6 planted fake (rest += d, no inverse) fails bar 1's check: error %.8f m" % e6)
	ok(reskin_err(after, want, sp.mats) <= TOL, "6 control: the real edit passes the same check")
	# 7 run_all
	var f := FileAccess.open("res://tools/run_all.sh", FileAccess.READ)
	ok(f != null and f.get_as_text().contains("poseedit:w"), "7 tools/run_all.sh has the poseedit line")
	print("%s poseedit_test: %d failed" % ["FAIL" if fails > 0 else "PASS", fails])
	quit(1 if fails > 0 else 0)
