## godot --path . -s tests/c75_test.gd   (C75: KineSkinNative.correct, the per-vertex DQ/LBS pre-correction of DqSkin.correct_arrays)
## Bars, stated before measuring:
##   1 EQUAL: C++ vs GDScript (correct_arrays_gd), per-vertex positions, normals and tangents within 1e-5, on 3 rigs x 20 poses
##     (rig 0 the mannequin with its own weights; rig 1 a 2-bone scaled tube; rig 2 a dense 5-bone chain, 4 influences per vertex).
##     The 20 poses include 180-degree twists (the DQ antipodal case) and scaled bones (the two-phase scale path). Also the
##     vertex counts "corrected" and "singular" are equal, and the blend 0.5 with a per-vertex mask is equal.
##   2 SPEED: deform ms per frame (one correct_arrays call on the densest mesh) at least 10x faster native (median of 3 each)
##   3 FALLBACK: DqSkin.force_gd = true selects the GDScript pass (result == correct_arrays_gd exactly), and a full
##     DqSkin.update on the mannequin with force_gd builds meshes equal (1e-5) to the native update's
##   4 CONTROL: weights perturbed by 1 ulp (every float32 weight bumped one step) are NOT called equal at 1e-9 (comparator works)
## Skipped (printed, not failed) when the DLL has no KineSkinNative.
extends SceneTree

var fails := 0
const TOL := 1e-5


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func vdiff(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.size() != b.size():
		return 1e9
	var m := 0.0
	for i in a.size():
		m = maxf(m, (a[i] - b[i]).abs().max_axis_value())
	return m


func fdiff(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.size() != b.size():
		return 1e9
	var m := 0.0
	for i in a.size():
		m = maxf(m, absf(a[i] - b[i]))
	return m


func med(a: Array) -> float:
	var s := a.duplicate()
	s.sort()
	return s[1]


## compare two correct_arrays results: max over positions, normals, tangents
func cmp(a: Array, b: Array) -> float:
	var A: Array = a[0]
	var B: Array = b[0]
	var m := vdiff(A[Mesh.ARRAY_VERTEX], B[Mesh.ARRAY_VERTEX])
	if A[Mesh.ARRAY_NORMAL] != null:
		m = maxf(m, vdiff(A[Mesh.ARRAY_NORMAL], B[Mesh.ARRAY_NORMAL]))
	if A[Mesh.ARRAY_TANGENT] != null:
		m = maxf(m, fdiff(A[Mesh.ARRAY_TANGENT], B[Mesh.ARRAY_TANGENT]))
	if a[1] != b[1] or a[2] != b[2]:
		m = maxf(m, 1e3)
	return m


## a tube of nr rings x ns segments along y, nb bones every 0.2 m, 4 influences per vertex. -> arrays
func tube(nr: int, ns: int, nb: int) -> Array:
	var vs := PackedVector3Array()
	var nn := PackedVector3Array()
	var nt := PackedFloat32Array()
	var bo := PackedInt32Array()
	var w := PackedFloat32Array()
	var h_all := 0.2 * float(nb)
	for r in nr:
		var y := h_all * float(r) / float(nr - 1)
		var f := clampf(y / 0.2, 0.0, nb - 1.0)
		var j := mini(int(f), nb - 2)
		for s in ns:
			var a := TAU * float(s) / ns
			var rad := 0.08 + 0.02 * sin(y * 9.0)
			vs.append(Vector3(rad * cos(a), y, rad * sin(a)))
			nn.append(Vector3(cos(a), 0.0, sin(a)))
			nt.append_array([-sin(a), 0.0, cos(a), 1.0])
			var ids := [maxi(j - 1, 0), j, j + 1, mini(j + 2, nb - 1)]
			var wt := []
			var tot := 0.0
			for q in 4:
				var d := f - float(ids[q])
				var x := exp(-d * d * 1.5)
				wt.append(x)
				tot += x
			for q in 4:
				bo.append(ids[q])
				w.append(wt[q] / tot)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = nn
	arr[Mesh.ARRAY_TANGENT] = nt
	arr[Mesh.ARRAY_BONES] = bo
	arr[Mesh.ARRAY_WEIGHTS] = w
	return arr


## skinning matrices of a chain of nb bones for pose p (0..19): rotations, 180-degree twists, scales
func chain_mats(nb: int, p: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000 + p * 13 + nb
	var mats := []
	var G := Transform3D.IDENTITY
	for k in nb:
		var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var ang := rng.randf_range(-1.2, 1.2)
		if p % 5 == 0 and k == 1:
			axis = Vector3.UP
			ang = PI   # the forearm turned half a revolution about its own axis
		if p % 5 == 1 and k == 2:
			axis = Vector3.UP
			ang = PI * 0.999
		var bas := Basis(axis, ang)
		if p >= 10 and k % 2 == 1:
			bas = bas * Basis.from_scale(Vector3(1.0 + 0.1 * (p % 4), 0.8 + 0.05 * (p % 3), 1.2))
		var local := Transform3D(bas, Vector3(0, 0.2 if k > 0 else 0.0, 0))
		G = G * local
		var rest := Transform3D(Basis.IDENTITY, Vector3(0, 0.2 * k, 0))
		mats.append(G * rest.affine_inverse())
	return mats


func multi_all(arr: Array) -> PackedInt32Array:
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	return DqSkin.multi_of(bo, arr[Mesh.ARRAY_WEIGHTS], bo.size() / vs.size(), vs.size())


func pose_mannequin(sk: Skeleton3D, p: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + p
	sk.reset_bone_poses()
	for b in sk.get_bone_count():
		var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		sk.set_bone_pose_rotation(b, Quaternion(axis, rng.randf_range(-0.9, 0.9)))
		if p >= 10 and b % 3 == 0:
			sk.set_bone_pose_scale(b, Vector3(1.0 + 0.1 * (p % 4), 0.85, 1.15))
	if p % 5 == 0:   # 180-degree twists on a few chains
		for b in range(1, sk.get_bone_count(), 4):
			sk.set_bone_pose_rotation(b, Quaternion(Vector3.UP, PI))


func _init() -> void:
	if not NativeExt.ensure("kine_native", "KineSkinNative"):
		print("SKIP KineSkinNative is not in the DLL")
		print("C75 SKIP")
		quit(0)
		return
	DqSkin.force_gd = false
	ok(DqSkin.native_ok(), "native pass is selected by default")
	var worst := [0.0, 0.0, 0.0]
	var moved := [0, 0, 0]
	var sing_tot := 0

	# ---- rig 0: the mannequin
	var mq := Overlays.mannequin(root, StandardMaterial3D.new())
	var man: Node3D = mq[0]
	var sk: Skeleton3D = mq[1]
	var mi: MeshInstance3D = man.find_children("*", "MeshInstance3D", true, false)[0]
	var skin: Skin = mi.skin
	var msurf := []
	for si in (mi.mesh as ArrayMesh).get_surface_count():
		msurf.append((mi.mesh as ArrayMesh).surface_get_arrays(si))
	var mn := 0
	for a in msurf:
		mn += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	print("rig0 mannequin: %d vertices in %d surfaces" % [mn, msurf.size()])
	for p in 20:
		pose_mannequin(sk, p)
		var fr := DqSkin.frame_of(DqSkin.bind_mats(sk, skin))
		for a in msurf:
			if a[Mesh.ARRAY_BONES] == null:
				continue
			var multi := multi_all(a)
			var g := DqSkin.correct_arrays_gd(a, fr, 1.0, multi)
			var n := DqSkin.correct_arrays(a, fr, 1.0, multi)
			worst[0] = maxf(worst[0], cmp(g, n))
			moved[0] += int(n[1])
			sing_tot += int(n[2])

	# ---- rig 1 (2 bones, 8k verts) and rig 2 (5 bones, dense)
	var t1 := tube(80, 100, 2)
	var t2 := tube(300, 200, 5)
	var rigs := [t1, t2]
	var nbs := [2, 5]
	var maskv := PackedFloat32Array()
	for ri in 2:
		var arr: Array = rigs[ri]
		var multi := multi_all(arr)
		for p in 20:
			var fr := DqSkin.frame_of(chain_mats(nbs[ri], p))
			var g := DqSkin.correct_arrays_gd(arr, fr, 1.0, multi)
			var n := DqSkin.correct_arrays(arr, fr, 1.0, multi)
			worst[ri + 1] = maxf(worst[ri + 1], cmp(g, n))
			moved[ri + 1] += int(n[1])
			sing_tot += int(n[2])
	for ri in 3:
		ok(worst[ri] <= TOL and moved[ri] > 0, "1 equal rig %d: max diff %.3g (<= 1e-5), %d vertices corrected over 20 poses" % [ri, worst[ri], moved[ri]])
	print("singular vertices over all runs: %d" % sing_tot)
	# the blend 0.5 with a mask
	var arr1: Array = t1
	var nv1: int = (arr1[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	maskv.resize(nv1)
	for i in nv1:
		maskv[i] = float(i % 7) / 6.0
	var fr1 := DqSkin.frame_of(chain_mats(2, 3))
	var m1 := multi_all(arr1)
	var d_mask := cmp(DqSkin.correct_arrays_gd(arr1, fr1, 0.5, m1, maskv), DqSkin.correct_arrays(arr1, fr1, 0.5, m1, maskv))
	ok(d_mask <= TOL, "1b equal at blend 0.5 with a per-vertex mask: max diff %.3g" % d_mask)

	# ---- 2 speed on the densest mesh
	var dense: Array = t2
	var dm := multi_all(dense)
	var frd := DqSkin.frame_of(chain_mats(5, 4))
	var tg := []
	var tn := []
	for r in 3:
		var t0 := Time.get_ticks_usec()
		DqSkin.correct_arrays_gd(dense, frd, 1.0, dm)
		tg.append((Time.get_ticks_usec() - t0) / 1000.0)
		t0 = Time.get_ticks_usec()
		DqSkin.correct_arrays(dense, frd, 1.0, dm)
		tn.append((Time.get_ticks_usec() - t0) / 1000.0)
	var sp := med(tg) / maxf(0.001, med(tn))
	print("PROF densest mesh %d verts (%d multi): gdscript %.1f ms, native %.2f ms per frame" % [(dense[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), dm.size(), med(tg), med(tn)])
	ok(sp >= 10.0, "2 speed: %.1fx faster native (>= 10x)" % sp)

	# ---- 3 fallback
	DqSkin.force_gd = true
	ok(not DqSkin.native_ok(), "3a force_gd hides the native pass")
	var gsel := DqSkin.correct_arrays(dense, frd, 1.0, dm)
	var gref := DqSkin.correct_arrays_gd(dense, frd, 1.0, dm)
	ok(cmp(gsel, gref) == 0.0, "3b fallback path selected: result identical to correct_arrays_gd")
	pose_mannequin(sk, 5)
	var dq_gd := DqSkin.new()
	dq_gd.threads = false
	dq_gd.attach([mi], sk)
	dq_gd.update(1.0)
	var mesh_gd: ArrayMesh = mi.mesh
	var vg: Array = []
	for si in mesh_gd.get_surface_count():
		vg.append(mesh_gd.surface_get_arrays(si))
	mi.mesh = dq_gd._entries[0]["base"]
	DqSkin.force_gd = false
	var dq_nat := DqSkin.new()
	dq_nat.threads = false
	dq_nat.attach([mi], sk)
	dq_nat.update(1.0)
	var mesh_nat: ArrayMesh = mi.mesh
	var dmax := 0.0
	for si in mesh_nat.get_surface_count():
		var an := mesh_nat.surface_get_arrays(si)
		dmax = maxf(dmax, vdiff(an[Mesh.ARRAY_VERTEX], vg[si][Mesh.ARRAY_VERTEX]))
		if an[Mesh.ARRAY_NORMAL] != null:
			dmax = maxf(dmax, vdiff(an[Mesh.ARRAY_NORMAL], vg[si][Mesh.ARRAY_NORMAL]))
	ok(dq_gd.corrected > 0 and dq_gd.corrected == dq_nat.corrected and dmax <= TOL, "3c DqSkin.update: GDScript vs native meshes equal (max %.3g), corrected %d vs %d" % [dmax, dq_gd.corrected, dq_nat.corrected])

	# ---- 4 control: 1-ulp weight perturbation
	var wp: PackedFloat32Array = (dense[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array)
	var pb := wp.to_byte_array()
	for i in wp.size():
		pb.encode_u32(i * 4, pb.decode_u32(i * 4) + 1)
	var dense2 := dense.duplicate()
	dense2[Mesh.ARRAY_WEIGHTS] = pb.to_float32_array()
	var n0 := DqSkin.correct_arrays(dense, frd, 1.0, dm)
	var n1 := DqSkin.correct_arrays(dense2, frd, 1.0, dm)
	var dc := cmp(n0, n1)
	var same_self := cmp(n0, DqSkin.correct_arrays(dense, frd, 1.0, dm))
	ok(same_self <= 1e-9 and dc > 1e-9, "4 control: identical input equal at 1e-9 (%.3g), 1-ulp perturbed weights NOT equal at 1e-9 (diff %.3g)" % [same_self, dc])
	print("C75 %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
