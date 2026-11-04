## dq_skin.gd - DUAL-QUATERNION SKINNING (ROADMAP_400 H04): no candy-wrapper wrists.
## Linear-blend skinning (LBS, what Godot's skeleton does) averages the bone MATRICES of a vertex: two rotations 90 deg apart
## average to a matrix that is no rotation at all, so a twisted forearm's wrist collapses onto the bone axis (the candy
## wrapper) and a bent elbow loses volume. Dual-quaternion skinning (Kavan, Collins, Zara, O'Sullivan 2007 "Skinning with dual
## quaternions"; 2008 "Geometric skinning with approximate dual quaternion blending") averages the bones as unit dual
## quaternions instead and normalises the sum, so the blend is always a rigid motion:
##   q_k = (r_k, d_k),  r_k = the rotation of bind k,  d_k = 0.5 * (0, t_k) * r_k     (t_k = its translation)
##   b   = sum_k w_k s_k q_k,   s_k = sign(r_k . r_pivot)   (the ANTIPODALITY fix: q and -q are the same rotation; every
##                                                           influence is put in the hemisphere of the heaviest one)
##   b  /= |b_r|                (normalise: the blend is a unit dual quaternion, a rotation + a translation)
##   v'  = (b_r v b_r* + 2 (b_d b_r*).xyz) * sum_k w_k
## The last factor is the vertex's weight sum: a file's weights sum to 1 only to float precision (the mannequin's to 4e-5)
## and LBS draws that sum, so DQS keeps it too and the two agree at rest to the last digit instead of 50 um apart.
## SCALE (Kavan 2008, "two-phase skinning"): a bone with a scale (Proportions, an impact squash) is split M_k = [R_k|t_k] S_k;
## the scale parts are blended linearly in rest space first (v_s = sum w_k S_k v), then the rigid parts by dual quaternions.
## For bones without scale S_k = I and this is plain DQS.
## The LBS / DQS mix: a 0..1 blend k (the scene's dq_skin), times an optional per-vertex 0..1 mask:
##   p(v) = lerp(LBS(v), DQS(v), k * mask(v))
##
## HOW IT REACHES THE SCREEN (the GPU path): the engine's own skeleton still skins every vertex on the GPU by LBS. Each vertex
## that more than one bone moves gets a REST-SPACE pre-correction so the GPU's LBS lands exactly on the DQS position:
##   M(v) = sum_k w_k M_k (the matrix the GPU applies),  v_rest' = M(v)^-1 p(v),  n_rest' = M(v).basis^-1 n_p(v)
## so  M(v) v_rest' = p(v)  exactly (bar 6 of tests/dqskin_test.gd). Nothing else changes: the materials, the skin pick, the
## weight paint, playback, the playblast and the posed-OBJ export preview all draw / read the same mesh. The correction is a
## CPU pass per changed pose (its cost is bar 10 of the test), spread over the WorkerThreadPool; a vertex one bone moves is
## never touched. With the blend at 0 the meshes are the very ones it found.
## A custom GPU skinning shader was not used: Godot 4 skins in its own compute pass before the material's vertex() runs,
## so a shader would need the skeleton detached and every material (skin pick tint, heat paint, toon) rewritten.
## EXPORT stays LBS: glb / fbx / usd write the rest mesh + weights, and every engine (UE5, Unity, Godot) skins those by
## LBS. An engine set to DQ (Unity's skin "Dual Quaternion" option, UE5 has none by default) can turn it on there.
## Corrective shapes (ROADMAP 71) compose: their mesh is the rest mesh this pass corrects.
class_name DqSkin
extends RefCounted

const EPS := 1e-6          # m: a vertex corrected by less than 1 um keeps its LBS rest position (float32 noise at 2 m is 0.1 um)
const DET_MIN := 1e-6      # a blended LBS matrix this near singular is not inverted (that vertex stays LBS)

var skel: Skeleton3D
var skin: Skin
var mask := {}             # optional per-vertex weights: vertex count -> PackedFloat32Array (0..1), {} = 1 everywhere
var threads := true        # the surfaces are corrected on the WorkerThreadPool
var _entries := []         # [{"mi", "base", "out"}] per mesh instance
var _sig := 0              # the hash of the last (mats, k): the same pose twice rebuilds nothing
var rebuilds := 0          # meshes rebuilt by the last update
var corrected := 0         # vertex corrections made by the last update (summed over the pieces)
var singular := 0          # vertices left LBS because their blended matrix was singular
var last_ms := 0.0         # the last update's time
var prof := {}             # the last full update: {"prep" ms (reading changed base meshes), "jobs" ms (the threaded pass)}
var _cache := {}           # base mesh id -> [mesh, _prep's surfaces]
var _multi := {}           # skin + triangles hash -> the vertices with 2+ distinct binds


## the meshes to skin by DQ (each MeshInstance3D with this skin)
func attach(meshes: Array, sk: Skeleton3D) -> void:
	skel = sk
	_entries = []
	_sig = 0
	for mi in meshes:
		var m := mi as MeshInstance3D
		if m == null or m.skin == null or not (m.mesh is ArrayMesh):
			continue
		if skin == null:
			skin = m.skin
		_entries.append({"mi": m, "base": m.mesh, "out": null})


## every bind's skinning matrix in the skeleton's space: bone global pose * bind pose. The globals are composed from the
## local poses here (parents first), as skin_pick.gd does: the engine's cached global pose can lag a set_bone_pose_rotation.
static func bind_mats(sk: Skeleton3D, sn: Skin) -> Array:
	var nb := sk.get_bone_count()
	var g := []
	g.resize(nb)
	for b in nb:
		var p := sk.get_bone_parent(b)
		g[b] = (g[p] as Transform3D) * sk.get_bone_pose(b) if p >= 0 else sk.get_bone_pose(b)
	var out := []
	for k in sn.get_bind_count():
		out.append((g[SkinPaint.bind_bone(sn, sk, k)] as Transform3D) * sn.get_bind_pose(k))
	return out


## the dual quaternion of every matrix: [r (Quaternion), d (Quaternion), S (Basis: the scale/shear part, R^-1 B), rigid (bool)]
static func dqs_of(mats: Array) -> Array:
	var out := []
	for m in mats:
		var M: Transform3D = m
		var R := M.basis.orthonormalized()
		var r := R.get_rotation_quaternion().normalized()
		var t := M.origin
		var d := (Quaternion(t.x, t.y, t.z, 0.0) * r) * 0.5
		var S := R.inverse() * M.basis
		out.append([r, d, S, S.is_equal_approx(Basis.IDENTITY)])
	return out


## THE REFERENCE (plain, one vertex; the tests hold the fast pass to it): the skinned position of rest vertex v by LBS
## (k = 0), DQS (k = 1) or their mix. bo/w/per: the influences. -> [position, the LBS matrix M(v)]
static func skin_one(v: Vector3, i: int, bo: PackedInt32Array, w: PackedFloat32Array, per: int, mats: Array, dq: Array, k: float) -> Array:
	var bx := Vector3.ZERO
	var by := Vector3.ZERO
	var bz := Vector3.ZERO
	var bo_ := Vector3.ZERO
	var piv := -1
	var pw := -1.0
	for q in per:
		if w[i * per + q] > pw:
			pw = w[i * per + q]
			piv = bo[i * per + q]
	var rp: Quaternion = dq[piv][0]
	var br := Quaternion(0, 0, 0, 0)
	var bd := Quaternion(0, 0, 0, 0)
	var sx := Vector3.ZERO
	var sy := Vector3.ZERO
	var sz := Vector3.ZERO
	var ws := 0.0
	var rigid := true
	for q in per:
		var x := w[i * per + q]
		if x <= 0.0:
			continue
		ws += x
		var b := bo[i * per + q]
		var M: Transform3D = mats[b]
		bx += M.basis.x * x
		by += M.basis.y * x
		bz += M.basis.z * x
		bo_ += M.origin * x
		var e: Array = dq[b]
		var r: Quaternion = e[0]
		var s := x if r.dot(rp) >= 0.0 else -x   # the antipodality fix
		br += r * s
		bd += (e[1] as Quaternion) * s
		var S: Basis = e[2]
		sx += S.x * x
		sy += S.y * x
		sz += S.z * x
		rigid = rigid and bool(e[3])
	var ML := Transform3D(Basis(bx, by, bz), bo_)
	var lbs := ML * v
	var n := br.length()
	if n < 1e-9 or k <= 0.0:
		return [lbs, ML]
	br = br / n
	bd = bd / n
	var vs := v if rigid else Basis(sx / ws, sy / ws, sz / ws) * v
	var tq := bd * br.inverse()
	var p := (br * vs + Vector3(tq.x, tq.y, tq.z) * 2.0) * ws
	return [lbs.lerp(p, k) if k < 1.0 else p, ML]


## posed positions of a whole surface (CPU reference, for the tests and the checks): k = 0 LBS, 1 DQS
static func skin_surface(verts: PackedVector3Array, bo: PackedInt32Array, w: PackedFloat32Array, mats: Array, k: float) -> PackedVector3Array:
	var per := bo.size() / maxi(1, verts.size())
	var dq := dqs_of(mats)
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i in verts.size():
		out[i] = skin_one(verts[i], i, bo, w, per, mats, dq, k)[0]
	return out


## the vertices of a surface that two or more DIFFERENT binds move (the only ones DQS can change). used: the index list of
## a piece's own triangles (only its vertices), or empty for every vertex
static func multi_of(bo: PackedInt32Array, w: PackedFloat32Array, per: int, nv: int, used := PackedInt32Array()) -> PackedInt32Array:
	var out := PackedInt32Array()
	var only := PackedByteArray()
	if not used.is_empty():
		only.resize(nv)
		for i in used:
			only[i] = 1
	for i in nv:
		if not only.is_empty() and only[i] == 0:
			continue
		var first := -1
		for q in per:
			if w[i * per + q] <= 0.0:
				continue
			var b := bo[i * per + q]
			if first < 0:
				first = b
			elif b != first:
				out.append(i)
				break
	return out


## the per-frame bind data the fast pass reads, as packed arrays (no per-vertex allocation): LBS columns + origin, the DQ
## real / dual parts as 4 floats each, the scale columns, rigid flags
static func frame_of(mats: Array) -> Dictionary:
	var bx := PackedVector3Array()
	var by := PackedVector3Array()
	var bz := PackedVector3Array()
	var bo := PackedVector3Array()
	var r4 := PackedFloat32Array()
	var d4 := PackedFloat32Array()
	var sx := PackedVector3Array()
	var sy := PackedVector3Array()
	var sz := PackedVector3Array()
	var rig := PackedByteArray()
	var dq := dqs_of(mats)
	for k in mats.size():
		var M: Transform3D = mats[k]
		bx.append(M.basis.x)
		by.append(M.basis.y)
		bz.append(M.basis.z)
		bo.append(M.origin)
		var r: Quaternion = dq[k][0]
		var d: Quaternion = dq[k][1]
		r4.append_array([r.x, r.y, r.z, r.w])
		d4.append_array([d.x, d.y, d.z, d.w])
		var S: Basis = dq[k][2]
		sx.append(S.x)
		sy.append(S.y)
		sz.append(S.z)
		rig.append(1 if dq[k][3] else 0)
	return {"bx": bx, "by": by, "bz": bz, "bo": bo, "r": r4, "d": d4, "sx": sx, "sy": sy, "sz": sz, "rig": rig}


## THE PRE-CORRECTION of one surface's arrays (the fast pass): a copy whose rest vertices (and normals, tangents) make the
## GPU's LBS draw the blend k of LBS and DQS, on the vertices in `multi` only. fr = frame_of(mats). msk: per-vertex 0..1 or
## empty. Pure math on packed arrays (safe on a worker thread). -> [arrays, vertices corrected, vertices left singular]
static var force_gd := false   # tests: true = the GDScript pass even with the DLL (C75)
static var _door = null        # scripts/dq_skin_native.gd once KineSkinNative is known to exist
static var _door_tried := false


## C75: true when the C++ pass (KineSkinNative) is loaded and not switched off (force_gd, KINE_NO_NATIVE=1)
static func native_ok() -> bool:
	if force_gd or OS.get_environment("KINE_NO_NATIVE") == "1":
		return false
	if not _door_tried:
		_door_tried = true
		if NativeExt.ensure("kine_native", "KineSkinNative"):
			_door = load("res://scripts/dq_skin_native.gd")
	return _door != null and ClassDB.class_exists("KineSkinNative")


static func correct_arrays(arr: Array, fr: Dictionary, k: float, multi: PackedInt32Array, msk := PackedFloat32Array()) -> Array:
	if not native_ok():
		return correct_arrays_gd(arr, fr, k, multi, msk)
	var has_n: bool = arr[Mesh.ARRAY_NORMAL] != null
	var has_t: bool = arr[Mesh.ARRAY_TANGENT] != null
	var r: Dictionary = _door.correct(arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_NORMAL] if has_n else PackedVector3Array(), arr[Mesh.ARRAY_TANGENT] if has_t else PackedFloat32Array(), arr[Mesh.ARRAY_BONES], arr[Mesh.ARRAY_WEIGHTS], fr, k, multi, msk)
	var out := arr.duplicate()
	out[Mesh.ARRAY_VERTEX] = r["v"]
	if has_n:
		out[Mesh.ARRAY_NORMAL] = r["n"]
	if has_t:
		out[Mesh.ARRAY_TANGENT] = r["t"]
	return [out, int(r["cnt"]), int(r["sing"])]


static func correct_arrays_gd(arr: Array, fr: Dictionary, k: float, multi: PackedInt32Array, msk := PackedFloat32Array()) -> Array:
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var per := bo.size() / maxi(1, vs.size())
	var has_n: bool = arr[Mesh.ARRAY_NORMAL] != null
	var has_t: bool = arr[Mesh.ARRAY_TANGENT] != null
	var nv := vs.duplicate()
	var nn: PackedVector3Array = (arr[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate() if has_n else PackedVector3Array()
	var nt: PackedFloat32Array = (arr[Mesh.ARRAY_TANGENT] as PackedFloat32Array).duplicate() if has_t else PackedFloat32Array()
	var FX: PackedVector3Array = fr["bx"]
	var FY: PackedVector3Array = fr["by"]
	var FZ: PackedVector3Array = fr["bz"]
	var FO: PackedVector3Array = fr["bo"]
	var R: PackedFloat32Array = fr["r"]
	var D: PackedFloat32Array = fr["d"]
	var SX: PackedVector3Array = fr["sx"]
	var SY: PackedVector3Array = fr["sy"]
	var SZ: PackedVector3Array = fr["sz"]
	var RIG: PackedByteArray = fr["rig"]
	var cnt := 0
	var sing := 0
	var use_m := msk.size() == vs.size()
	for i in multi:
		var kk := k * (msk[i] if use_m else 1.0)
		if kk <= 0.0:
			continue
		var o := i * per
		var piv := bo[o]   # the heaviest influence: every other is put in its hemisphere
		var pw := w[o]
		for q in range(1, per):
			if w[o + q] > pw:
				pw = w[o + q]
				piv = bo[o + q]
		var p4 := piv * 4
		var px := R[p4]
		var py := R[p4 + 1]
		var pz := R[p4 + 2]
		var pq := R[p4 + 3]
		var cx := Vector3.ZERO
		var cy := Vector3.ZERO
		var cz := Vector3.ZERO
		var co := Vector3.ZERO
		var rx := 0.0
		var ry := 0.0
		var rz := 0.0
		var rw := 0.0
		var dx := 0.0
		var dy := 0.0
		var dz := 0.0
		var dw := 0.0
		var sx := Vector3.ZERO
		var sy := Vector3.ZERO
		var sz := Vector3.ZERO
		var ws := 0.0
		var rigid := true
		for q in per:
			var x := w[o + q]
			if x <= 0.0:
				continue
			var b := bo[o + q]
			ws += x
			cx += FX[b] * x
			cy += FY[b] * x
			cz += FZ[b] * x
			co += FO[b] * x
			var b4 := b * 4
			var s := x if R[b4] * px + R[b4 + 1] * py + R[b4 + 2] * pz + R[b4 + 3] * pq >= 0.0 else -x   # antipodality
			rx += R[b4] * s
			ry += R[b4 + 1] * s
			rz += R[b4 + 2] * s
			rw += R[b4 + 3] * s
			dx += D[b4] * s
			dy += D[b4 + 1] * s
			dz += D[b4 + 2] * s
			dw += D[b4 + 3] * s
			if RIG[b] == 0:
				rigid = false
				sx += SX[b] * x
				sy += SY[b] * x
				sz += SZ[b] * x
			else:
				sx += Vector3.RIGHT * x
				sy += Vector3.UP * x
				sz += Vector3.BACK * x
		var ML := Transform3D(Basis(cx, cy, cz), co)
		var ln := sqrt(rx * rx + ry * ry + rz * rz + rw * rw)
		if absf(ML.basis.determinant()) < DET_MIN or ln < 1e-9:
			sing += 1
			continue
		var br := Quaternion(rx / ln, ry / ln, rz / ln, rw / ln)
		var bd := Quaternion(dx / ln, dy / ln, dz / ln, dw / ln)
		var v := vs[i]
		var SB := Basis.IDENTITY
		if not rigid:
			SB = Basis(sx / ws, sy / ws, sz / ws)
			v = SB * v
		var tq := bd * br.inverse()
		var p := (br * v + Vector3(tq.x, tq.y, tq.z) * 2.0) * ws
		if kk < 1.0:
			p = (ML * vs[i]).lerp(p, kk)
		var inv := ML.affine_inverse()
		var v2 := inv * p
		if v2.distance_squared_to(vs[i]) < EPS * EPS:
			continue
		nv[i] = v2
		cnt += 1
		var bi := inv.basis
		if has_n:
			var n0 := nn[i]
			var nd := br * (n0 if rigid else SB.inverse().transposed() * n0)
			nn[i] = (bi * (ML.basis * n0).normalized().lerp(nd.normalized(), kk)).normalized()
		if has_t:
			var t0 := Vector3(nt[i * 4], nt[i * 4 + 1], nt[i * 4 + 2])
			var td := br * (SB * t0)
			var t2 := (bi * (ML.basis * t0).normalized().lerp(td.normalized(), kk)).normalized()
			nt[i * 4] = t2.x
			nt[i * 4 + 1] = t2.y
			nt[i * 4 + 2] = t2.z
	var out := arr.duplicate()
	out[Mesh.ARRAY_VERTEX] = nv
	if has_n:
		out[Mesh.ARRAY_NORMAL] = nn
	if has_t:
		out[Mesh.ARRAY_TANGENT] = nt
	return [out, cnt, sing]




## a base mesh's surfaces as the pass reads them, made once per base mesh (main thread: it reads the mesh from the
## RenderingServer): [{"arr", "multi" (the piece's own 2+-bone vertices), "fmt", "mat"}]
func _prep(base: ArrayMesh) -> Array:
	var key := base.get_instance_id()
	if _cache.has(key) and _cache[key][0] == base:
		return _cache[key][1]
	var out := []
	for si in base.get_surface_count():
		var arr := base.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var multi := PackedInt32Array()
		if arr[Mesh.ARRAY_BONES] != null and arr[Mesh.ARRAY_WEIGHTS] != null:
			var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var mk := hash([bo, arr[Mesh.ARRAY_WEIGHTS], arr[Mesh.ARRAY_INDEX]])   # the same skin + triangles: the same list
			if not _multi.has(mk):
				var ix = arr[Mesh.ARRAY_INDEX]
				_multi[mk] = multi_of(bo, arr[Mesh.ARRAY_WEIGHTS], bo.size() / maxi(1, vs.size()), vs.size(), ix if ix != null else PackedInt32Array())
			multi = _multi[mk]
		out.append({"arr": arr, "multi": multi, "fmt": base.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS, "mat": base.surface_get_material(si)})
	if _cache.size() > 512:
		_cache.clear()
	_cache[key] = [base, out]
	return out


## one piece on a worker: its surfaces corrected, and a NEW ArrayMesh of them when any vertex moved (a new resource made on
## the thread that fills it, assigned on the main thread). jb: {"pr", "fr", "k", "msk"} -> jb gets "am", "cnt", "sing"
static func _piece_job(jb: Dictionary) -> void:
	var pr: Array = jb["pr"]
	var outs := []
	var cnt := 0
	var sing := 0
	for si in pr.size():
		var multi: PackedInt32Array = pr[si]["multi"]
		if multi.is_empty():
			outs.append(pr[si]["arr"])
			continue
		var vn: int = (pr[si]["arr"][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var res := correct_arrays(pr[si]["arr"], jb["fr"], jb["k"], multi, (jb["msk"] as Dictionary).get(vn, PackedFloat32Array()))
		cnt += int(res[1])
		sing += int(res[2])
		outs.append(res[0] if int(res[1]) > 0 else pr[si]["arr"])
	jb["cnt"] = cnt
	jb["sing"] = sing
	if cnt == 0:
		return
	var am := ArrayMesh.new()
	for si in outs.size():
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, outs[si], [], {}, int(pr[si]["fmt"]))
		am.surface_set_material(si, pr[si]["mat"])
	am.custom_aabb = jb["aabb"]
	jb["am"] = am


## write the blend k (0 = plain LBS, 1 = DQS) for the skeleton's current pose into the meshes. Call after the pose is on the
## skeleton and after Corrective.update (its mesh is the rest this corrects). k = 0 puts back the mesh each instance had.
## Each piece is corrected AND its mesh built on the WorkerThreadPool (pure math + a new resource per job); the main thread
## reads the base meshes (once per base) and assigns the results.
func update(k: float) -> void:
	rebuilds = 0
	var t0 := Time.get_ticks_usec()
	for e in _entries:   # a mesh someone else set (a corrective, the weight paint) is the new rest to correct
		var mi: MeshInstance3D = e["mi"]
		if mi.mesh != (e["base"] if e["out"] == null else e["out"]):   # (the old rest put back over our mesh counts too)
			e["base"] = mi.mesh
			e["out"] = null
			_sig = 0
	if k <= 0.0 or skel == null or skin == null:
		for e in _entries:
			var mi: MeshInstance3D = e["mi"]
			if e["out"] != null and mi.mesh == e["out"]:
				mi.mesh = e["base"]
				rebuilds += 1
			e["out"] = null
		_sig = 0
		last_ms = (Time.get_ticks_usec() - t0) / 1000.0
		return
	native_ok()   # resolve the door on the main thread before the workers run
	var mats := bind_mats(skel, skin)
	var sig := hash([mats, k, mask.size()])
	if sig == _sig:
		last_ms = (Time.get_ticks_usec() - t0) / 1000.0
		return
	_sig = sig
	var fr := frame_of(mats)
	var jobs := []
	var tp := Time.get_ticks_usec()
	for e in _entries:
		var base := e["base"] as ArrayMesh
		jobs.append({"pr": _prep(base), "fr": fr, "k": k, "msk": mask, "aabb": base.custom_aabb, "cnt": 0, "sing": 0, "am": null})
	var tj := Time.get_ticks_usec()
	var run := func(j: int) -> void:
		_piece_job(jobs[j])
	if threads and jobs.size() > 1:
		var gid := WorkerThreadPool.add_group_task(run, jobs.size(), -1, true, "dq_skin")
		WorkerThreadPool.wait_for_group_task_completion(gid)
	else:
		for j in jobs.size():
			run.call(j)
	prof = {"prep": (tj - tp) / 1000.0, "jobs": (Time.get_ticks_usec() - tj) / 1000.0}
	corrected = 0
	singular = 0
	for ei in _entries.size():
		var e: Dictionary = _entries[ei]
		var jb: Dictionary = jobs[ei]
		var mi: MeshInstance3D = e["mi"]
		corrected += int(jb["cnt"])
		singular += int(jb["sing"])
		if jb["am"] == null:
			if mi.mesh != e["base"]:
				mi.mesh = e["base"]
				rebuilds += 1
			e["out"] = null
			continue
		e["out"] = jb["am"]
		mi.mesh = jb["am"]
		rebuilds += 1
	last_ms = (Time.get_ticks_usec() - t0) / 1000.0


## the menu / status word of a blend
static func describe(k: float) -> String:
	if k <= 0.0:
		return "linear blend (LBS)"
	if k >= 1.0:
		return "dual quaternion (DQS)"
	return "%d%% dual quaternion, %d%% linear blend" % [roundi(k * 100.0), 100 - roundi(k * 100.0)]
