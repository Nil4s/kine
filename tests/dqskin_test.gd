## godot --path . -s tests/dqskin_test.gd     (ROADMAP_400 H04: dual-quaternion skinning, scripts/dq_skin.gd; run_all: dqskin:w,
## windowed, so bar 10 times the real renderer; headless it runs every bar but 10, which the dummy renderer cannot time)
## Bars, stated before measuring (the mannequin as shipped, its own weights):
##   1 REST: with the skeleton at its rest pose, LBS and DQS give the same vertices (max diff < 1e-5 m), and DqSkin.update(1)
##     at rest rebuilds no mesh (the drawn meshes are the file's own)
##   2 TWIST, LBS: the left hand turned 90 deg about the forearm's own axis (pronation at the wrist). The wrist section (the
##     plane across the forearm axis through the wrist joint, the middle of the hand / forearm blend band) loses X % of its
##     area with LBS: X measured, and X > 10 so the test means something (the candy wrapper)
##   3 TWIST, DQS: the same section with DQS stays within 5 % of its rest area
##   4 ELBOW 90 deg: the body's closed volume (signed tetrahedra about the elbow centre, so the rigid swing of the forearm
##     changes nothing) changes LESS with DQS than with LBS: |dV_dqs| < |dV_lbs|
##   5 BULGE (the known DQS artefact on bends): reported at 90 deg and at the elbow's 145 deg stop: the volume DQS changes and
##     the most any elbow vertex ends OUT from the elbow centre beyond its rest distance (mm). Sanity bar: under 20 mm
##   6 THE GPU PATH: the pre-corrected rest mesh, skinned by plain LBS (what Godot's skeleton does), lands on the CPU DQS
##     positions within 1e-5 m (twist and bend), with no vertex left singular
##   7 BLEND 0.5: the wrist area lies between LBS's and DQS's; a per-vertex mask of 0 gives LBS exactly (diff < 1e-6 m)
##   8 OFF and caching: update(0) puts back the very mesh objects that were there; the same pose twice rebuilds nothing
##   9 SAVED: Scene.dq_skin round-trips through to_dict / from_dict (0.5 -> 0.5) and is absent from a file at 0 (old files
##     save byte-identical)
##  10 PERF at the mannequin's size (the app's 52 pieces, every joint posed, 8 different poses): the CPU frame with DQS
##     (pose the skeleton + corrective + DQ pass) is at most the LBS frame (pose + corrective) + 16 ms on average
##     (16 ms = half a 30 fps frame: playback keeps 30 fps on the machine that runs the suites)
## THE WRIST INSTRUMENT (changed after the first run, said here so nobody mistakes it for a moved bar): bars 2-3 were first
## read on the DRAWN triangles cut by the plane. DQS then lost 7.5 % (LBS 44 %), yet every wrist vertex kept its distance to
## the axis within 0.06 mm under DQS: the loss was the chord of the mannequin's coarse wrist (two vertex rings ~1 cm apart,
## turned ~45 deg against each other, joined by straight edges that cut inside the skin), which no skinning can change.
## The bars are now read on the SKIN FIELD: the triangles within 3 cm of the plane cut 8 x 8, rest positions and weights
## mixed across each triangle, every sample skinned (at rest it gives the drawn area to the digit: 17.50 cm2 both ways).
## The drawn-mesh numbers are still printed.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## every surface of a mesh as one list: [verts, bones, weights, index list over the concatenation]
static func flat(m: ArrayMesh) -> Dictionary:
	var vs := PackedVector3Array()
	var bo := PackedInt32Array()
	var w := PackedFloat32Array()
	var ix := PackedInt32Array()
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		var base := vs.size()
		var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		vs.append_array(sv)
		bo.append_array(arr[Mesh.ARRAY_BONES])
		w.append_array(arr[Mesh.ARRAY_WEIGHTS])
		var sx = arr[Mesh.ARRAY_INDEX]
		if sx == null:
			for i in sv.size():
				ix.append(base + i)
		else:
			for i in (sx as PackedInt32Array):
				ix.append(base + i)
	return {"v": vs, "b": bo, "w": w, "i": ix}


## the cross-section area (m^2) of the triangles idx over pos cut by the plane (P, n): the convex hull of the cut points
static func section_area(pos: PackedVector3Array, idx: PackedInt32Array, P: Vector3, n: Vector3) -> float:
	var pts := []
	for t in range(0, idx.size(), 3):
		var a := pos[idx[t]]
		var b := pos[idx[t + 1]]
		var c := pos[idx[t + 2]]
		var da := n.dot(a - P)
		var db := n.dot(b - P)
		var dc := n.dot(c - P)
		for e in [[a, b, da, db], [b, c, db, dc], [c, a, dc, da]]:
			var d0: float = e[2]
			var d1: float = e[3]
			if (d0 > 0.0) != (d1 > 0.0):
				pts.append((e[0] as Vector3).lerp(e[1], d0 / (d0 - d1)))
	if pts.size() < 3:
		return 0.0
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := n.cross(u)
	var p2 := []
	for p in pts:
		var q: Vector3 = p - P
		p2.append(Vector2(q.dot(u), q.dot(v)))
	return hull_area(p2)


static func hull_area(p: Array) -> float:
	p.sort_custom(func(x, y): return x.x < y.x if x.x != y.x else x.y < y.y)
	var lo := []
	for q in p:
		while lo.size() >= 2 and _cross2(lo[-2], lo[-1], q) <= 0.0:
			lo.pop_back()
		lo.append(q)
	var up := []
	for i in range(p.size() - 1, -1, -1):
		var q: Vector2 = p[i]
		while up.size() >= 2 and _cross2(up[-2], up[-1], q) <= 0.0:
			up.pop_back()
		up.append(q)
	lo.pop_back()
	up.pop_back()
	var h := lo + up
	var a := 0.0
	for i in h.size():
		var x: Vector2 = h[i]
		var y: Vector2 = h[(i + 1) % h.size()]
		a += x.x * y.y - y.x * x.y
	return absf(a) * 0.5


static func _cross2(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a - o).x * (b - o).y - (a - o).y * (b - o).x


## the signed volume of the triangles about the point O (sum of tetrahedra O a b c)
static func volume(pos: PackedVector3Array, idx: PackedInt32Array, O: Vector3) -> float:
	var s := 0.0
	for t in range(0, idx.size(), 3):
		var a := pos[idx[t]] - O
		var b := pos[idx[t + 1]] - O
		var c := pos[idx[t + 2]] - O
		s += a.dot(b.cross(c))
	return s / 6.0


## the weight bind set S has on every vertex
static func weight_on(F: Dictionary, binds: Dictionary) -> PackedFloat32Array:
	var vs: PackedVector3Array = F["v"]
	var bo: PackedInt32Array = F["b"]
	var w: PackedFloat32Array = F["w"]
	var per := bo.size() / vs.size()
	var out := PackedFloat32Array()
	out.resize(vs.size())
	for i in vs.size():
		var s := 0.0
		for q in per:
			if binds.has(bo[i * per + q]):
				s += w[i * per + q]
		out[i] = s
	return out


static func max_diff(a: PackedVector3Array, b: PackedVector3Array) -> float:
	var m := 0.0
	for i in a.size():
		m = maxf(m, a[i].distance_to(b[i]))
	return m


## a bone's global pose in the skeleton's space, composed from the local poses
static func gpose(sk: Skeleton3D, b: int) -> Transform3D:
	var p := sk.get_bone_parent(b)
	return gpose(sk, p) * sk.get_bone_pose(b) if p >= 0 else sk.get_bone_pose(b)


## turn bone b by deg about the world-space axis ax through its own origin (its local pose is rewritten)
static func turn_bone(sk: Skeleton3D, b: int, ax: Vector3, deg: float) -> void:
	var G := gpose(sk, b)
	var G2 := Transform3D(Basis(ax.normalized(), deg_to_rad(deg)) * G.basis, G.origin)
	var p := sk.get_bone_parent(b)
	var L := gpose(sk, p).affine_inverse() * G2
	sk.set_bone_pose_rotation(b, L.basis.get_rotation_quaternion())
	sk.set_bone_pose_position(b, L.origin)


## the distance of p from the axis line through o along ax
static func _rad(p: Vector3, o: Vector3, ax: Vector3) -> float:
	var d := p - o
	return (d - ax * d.dot(ax)).length()


## the area of the convex hull of the vertices ids projected on the plane across ax through o (the wrist's cross-section
## read at the skin's own vertices: no triangle edge between them is cut)
static func ring_area(pos: PackedVector3Array, ids: PackedInt32Array, o: Vector3, ax: Vector3) -> float:
	var u := ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := ax.cross(u)
	var p2 := []
	for i in ids:
		var q := pos[i] - o
		p2.append(Vector2(q.dot(u), q.dot(v)))
	return hull_area(p2)


## bar 6: every surface pre-corrected by the fast pass, then skinned by plain LBS, against the reference DQS -> [max m, singular]
static func gpu_check(src: ArrayMesh, mats: Array) -> Array:
	var fr := DqSkin.frame_of(mats)
	var err := 0.0
	var sing := 0
	for si in src.get_surface_count():
		var arr := src.surface_get_arrays(si)
		var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var res := DqSkin.correct_arrays(arr, fr, 1.0, DqSkin.multi_of(bo, arr[Mesh.ARRAY_WEIGHTS], bo.size() / sv.size(), sv.size()))
		sing += int(res[2])
		var gpu := DqSkin.skin_surface((res[0] as Array)[Mesh.ARRAY_VERTEX], bo, arr[Mesh.ARRAY_WEIGHTS], mats, 0.0)
		err = maxf(err, max_diff(gpu, DqSkin.skin_surface(sv, bo, arr[Mesh.ARRAY_WEIGHTS], mats, 1.0)))
	return [err, sing]


## THE SKIN FIELD near a plane: every triangle of tris (indices over F) with a corner within reach of the plane (P, ax) at
## rest is cut into n x n smaller triangles; each sample's rest position AND weights are the barycentric mix of the corners'
## (the skinning field the weights define between the vertices, not the straight chord the GPU draws). -> {"v", "b", "w",
## "per", "t"}: the samples (per = 12 influences, zero-padded) and the small triangles over them
static func refine(F: Dictionary, rest: PackedVector3Array, tris: PackedInt32Array, P: Vector3, ax: Vector3, reach: float, n: int) -> Dictionary:
	var V: PackedVector3Array = F["v"]
	var bo: PackedInt32Array = F["b"]
	var w: PackedFloat32Array = F["w"]
	var per := bo.size() / V.size()
	var PER := 12
	var sv := PackedVector3Array()
	var sb := PackedInt32Array()
	var sw := PackedFloat32Array()
	var st := PackedInt32Array()
	for t in range(0, tris.size(), 3):
		var c := [tris[t], tris[t + 1], tris[t + 2]]
		var near := false
		for i in c:
			if absf((rest[i] - P).dot(ax)) < reach:
				near = true
		if not near:
			continue
		var base := sv.size()
		var id := {}
		for i in n + 1:
			for j in n + 1 - i:
				var l := [float(n - i - j) / n, float(i) / n, float(j) / n]
				var p := Vector3.ZERO
				var inf := {}
				for m in 3:
					p += V[c[m]] * l[m]
					for q in per:
						var x := w[c[m] * per + q]
						if x > 0.0:
							inf[bo[c[m] * per + q]] = inf.get(bo[c[m] * per + q], 0.0) + x * l[m]
				id[Vector2i(i, j)] = sv.size()
				sv.append(p)
				var ks := inf.keys()
				for q in PER:
					sb.append(ks[q] if q < ks.size() else 0)
					sw.append(inf[ks[q]] if q < ks.size() else 0.0)
		for i in n:
			for j in n - i:
				st.append_array([id[Vector2i(i, j)], id[Vector2i(i + 1, j)], id[Vector2i(i, j + 1)]])
				if i + j < n - 1:
					st.append_array([id[Vector2i(i + 1, j)], id[Vector2i(i + 1, j + 1)], id[Vector2i(i, j + 1)]])
	return {"v": sv, "b": sb, "w": sw, "t": st}


func _init() -> void:
	var mq := Overlays.mannequin(root, StandardMaterial3D.new())
	var man: Node3D = mq[0]
	var sk: Skeleton3D = mq[1]
	var idx: Dictionary = mq[2]
	var mi: MeshInstance3D = man.find_children("*", "MeshInstance3D", true, false)[0]
	var skin: Skin = mi.skin
	var src: ArrayMesh = mi.mesh
	var F := flat(src)
	var V: PackedVector3Array = F["v"]
	var T: PackedInt32Array = F["i"]
	print("mannequin: %d vertices, %d triangles, %d binds" % [V.size(), T.size() / 3, skin.get_bind_count()])
	var bind_of := {}   # skeleton bone -> bind index
	for k in skin.get_bind_count():
		bind_of[SkinPaint.bind_bone(skin, sk, k)] = k

	# ---- 1 REST
	sk.reset_bone_poses()
	var mats := DqSkin.bind_mats(sk, skin)
	var r_l := DqSkin.skin_surface(V, F["b"], F["w"], mats, 0.0)
	var r_d := DqSkin.skin_surface(V, F["b"], F["w"], mats, 1.0)
	var rd := max_diff(r_l, r_d)
	print("rest: LBS vs DQS max vertex diff %.4f um (LBS vs the file's vertices %.1f um)" % [rd * 1e6, max_diff(r_l, V) * 1e6])
	var dqs := DqSkin.new()
	dqs.attach([mi], sk)
	dqs.update(1.0)
	ok(rd < 1e-5, "bar 1: rest pose, LBS and DQS identical (max diff %.4f um < 10 um)" % (rd * 1e6))
	ok(dqs.rebuilds == 0 and mi.mesh == src, "bar 1b: DQ on at rest rebuilds nothing (%d rebuilds, the file's mesh kept)" % dqs.rebuilds)

	# ---- the wrist: the forearm axis, the plane across it through the wrist joint (the middle of the hand / forearm blend band)
	var hb: int = idx["hand_l"]
	var fb: int = idx["lowerarm_l"]
	var wh := weight_on(F, {bind_of[hb]: true})
	var wf := weight_on(F, {bind_of[fb]: true})
	var elbow := gpose(sk, fb).origin
	var wrist := gpose(sk, hb).origin
	var ax := (wrist - elbow).normalized()
	var band := PackedInt32Array()   # every vertex both the hand and the forearm move, >= 5 % each
	var s_lo := 1e9
	var s_hi := -1e9
	for i in V.size():
		if wh[i] >= 0.05 and wf[i] >= 0.05:
			band.append(i)
			s_lo = minf(s_lo, (r_l[i] - wrist).dot(ax))
			s_hi = maxf(s_hi, (r_l[i] - wrist).dot(ax))
	print("wrist: %d vertices weighted >= 5 %% on both the hand and the forearm, %.1f .. %.1f mm along the forearm from the wrist joint" % [band.size(), s_lo * 1000.0, s_hi * 1000.0])
	var sec := PackedInt32Array()   # the forearm + hand skin: triangles whose corners all weigh >= 0.5 on the two bones
	for t in range(0, T.size(), 3):
		if wh[T[t]] + wf[T[t]] >= 0.5 and wh[T[t + 1]] + wf[T[t + 1]] >= 0.5 and wh[T[t + 2]] + wf[T[t + 2]] >= 0.5:
			sec.append_array([T[t], T[t + 1], T[t + 2]])
	var RF := refine(F, r_l, sec, wrist, ax, 0.03, 8)
	var RV: PackedVector3Array = RF["v"]
	print("  the skin field: %d triangles within 3 cm of the plane, cut 8 x 8 -> %d samples" % [(RF["t"] as PackedInt32Array).size() / 3 / 64, RV.size()])
	var A0 := section_area(DqSkin.skin_surface(RV, RF["b"], RF["w"], mats, 0.0), RF["t"], wrist, ax)
	var C0 := section_area(r_l, sec, wrist, ax)

	# ---- 2, 3 TWIST 90 deg
	turn_bone(sk, hb, ax, 90.0)
	mats = DqSkin.bind_mats(sk, skin)
	var A_l := section_area(DqSkin.skin_surface(RV, RF["b"], RF["w"], mats, 0.0), RF["t"], wrist, ax)
	var A_d := section_area(DqSkin.skin_surface(RV, RF["b"], RF["w"], mats, 1.0), RF["t"], wrist, ax)
	var A_h := section_area(DqSkin.skin_surface(RV, RF["b"], RF["w"], mats, 0.5), RF["t"], wrist, ax)
	var X := (A0 - A_l) / A0 * 100.0
	var Y := (A_d - A0) / A0 * 100.0
	var t_l := DqSkin.skin_surface(V, F["b"], F["w"], mats, 0.0)
	var t_d := DqSkin.skin_surface(V, F["b"], F["w"], mats, 1.0)
	var rl := 0.0   # the most a band vertex comes nearer the forearm axis (mm)
	var rdq := 0.0
	for i in band:
		var r0 := _rad(r_l[i], wrist, ax)
		rl = maxf(rl, r0 - _rad(t_l[i], wrist, ax))
		rdq = maxf(rdq, absf(r0 - _rad(t_d[i], wrist, ax)))
	print("wrist section (the skin field cut across the forearm at the wrist joint): rest %.2f cm2; hand twisted 90 deg LBS %.2f cm2 (%.1f %%), DQS %.2f cm2 (%+.1f %%), blend 0.5 %.2f cm2" % [A0 * 1e4, A_l * 1e4, -X, A_d * 1e4, Y, A_h * 1e4])
	print("  per vertex: LBS pulls a wrist vertex up to %.1f mm onto the axis; DQS changes a wrist vertex's distance to the axis by at most %.3f mm" % [rl * 1000.0, rdq * 1000.0])
	var C_l := section_area(t_l, sec, wrist, ax)
	var C_d := section_area(t_d, sec, wrist, ax)
	print("  the DRAWN mesh cut at the same plane (its own coarse triangles): rest %.2f cm2, LBS %.2f cm2 (%+.1f %%), DQS %.2f cm2 (%+.1f %%): straight edges between vertex rings turned against each other cut inside the skin (a chord), whatever the skinning; a denser wrist mesh closes that gap" % [C0 * 1e4, C_l * 1e4, 100.0 * (C_l - C0) / C0, C_d * 1e4, 100.0 * (C_d - C0) / C0])
	ok(X > 10.0, "bar 2: LBS twist shrinks the wrist section by X > 10 %% (X = %.1f %%)" % X)
	ok(absf(Y) <= 5.0, "bar 3: DQS twist keeps the wrist section within 5 %% of rest (%+.1f %%)" % Y)
	ok(A_h > A_l and A_h < maxf(A_d, A0) + 1e-9, "bar 7a: blend 0.5 lies between (LBS %.2f < %.2f < DQS %.2f cm2)" % [A_l * 1e4, A_h * 1e4, A_d * 1e4])
	# 6 the GPU path on the twist
	var multi := DqSkin.multi_of(F["b"], F["w"], (F["b"] as PackedInt32Array).size() / V.size(), V.size())
	var g := gpu_check(src, mats)
	var g_err: float = g[0]
	var g_sing: int = g[1]
	# 7b a zero mask is LBS
	var arr0 := src.surface_get_arrays(0)
	var bo0: PackedInt32Array = arr0[Mesh.ARRAY_BONES]
	var sv0: PackedVector3Array = arr0[Mesh.ARRAY_VERTEX]
	var zm := PackedFloat32Array()
	zm.resize(sv0.size())
	var zres := DqSkin.correct_arrays(arr0, DqSkin.frame_of(mats), 1.0, DqSkin.multi_of(bo0, arr0[Mesh.ARRAY_WEIGHTS], bo0.size() / sv0.size(), sv0.size()), zm)
	var zdiff := max_diff((zres[0] as Array)[Mesh.ARRAY_VERTEX], sv0)
	ok(zdiff < 1e-6 and int(zres[1]) == 0, "bar 7b: a per-vertex mask of 0 leaves LBS exactly (max diff %.4f um)" % (zdiff * 1e6))
	print("%d of %d vertices have 2+ different bones (the only ones DQS can move)" % [multi.size(), V.size()])

	# ---- 4, 5 ELBOW 90 deg
	sk.reset_bone_poses()
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	B.ground()
	for j in ["lowerarm_l", "lowerarm_r", "calf_l", "calf_r"]:
		B.ang[j] = Vector3(0.0, B.ang[j].y, B.ang[j].z)
	Overlays.pose_skeleton(sk, idx, B)
	mats = DqSkin.bind_mats(sk, skin)
	var e_ref := DqSkin.skin_surface(V, F["b"], F["w"], mats, 0.0)   # the straight arm, both ways
	var e_ref_d := DqSkin.skin_surface(V, F["b"], F["w"], mats, 1.0)
	var O0 := gpose(sk, fb).origin
	B.ang["lowerarm_l"] = Vector3(90.0, B.ang["lowerarm_l"].y, B.ang["lowerarm_l"].z)
	Overlays.pose_skeleton(sk, idx, B)
	mats = DqSkin.bind_mats(sk, skin)
	var O1 := gpose(sk, fb).origin
	var e_l := DqSkin.skin_surface(V, F["b"], F["w"], mats, 0.0)
	var e_d := DqSkin.skin_surface(V, F["b"], F["w"], mats, 1.0)
	var V0 := absf(volume(e_ref, T, O0))   # (the file's triangles wind inward: the signed sum is negative)
	var V0d := absf(volume(e_ref_d, T, O0))
	var dV_l := absf(volume(e_l, T, O1)) - V0
	var dV_d := absf(volume(e_d, T, O1)) - V0d
	print("elbow 90 deg: body volume %.2f L straight; change LBS %+.1f cm3 (%+.3f %% of the body), DQS %+.1f cm3 (%+.3f %%)" % [V0 * 1000.0, dV_l * 1e6, 100.0 * dV_l / V0, dV_d * 1e6, 100.0 * dV_d / V0d])
	ok(absf(dV_d) < absf(dV_l), "bar 4: the elbow's volume changes less with DQS (|%.1f| < |%.1f| cm3)" % [dV_d * 1e6, dV_l * 1e6])
	# the bulge: elbow vertices (2+ bones among upper arm / forearm), the farthest any ends out from the elbow centre
	var ub: int = idx["upperarm_l"]
	var we := weight_on(F, {bind_of[ub]: true, bind_of[fb]: true})
	var bulge := -INF
	for deg in [90.0, 145.0]:
		B.ang["lowerarm_l"] = Vector3(deg, B.ang["lowerarm_l"].y, B.ang["lowerarm_l"].z)
		Overlays.pose_skeleton(sk, idx, B)
		var bm := DqSkin.bind_mats(sk, skin)
		var Ob := gpose(sk, fb).origin
		var b_l := DqSkin.skin_surface(V, F["b"], F["w"], bm, 0.0)
		var b_d := DqSkin.skin_surface(V, F["b"], F["w"], bm, 1.0)
		var bv_l := absf(volume(b_l, T, Ob)) - V0
		var bv_d := absf(volume(b_d, T, Ob)) - V0d
		var bg := -INF
		var bg_l := -INF
		var out_l := 0.0   # the most DQS puts an elbow vertex farther from the joint centre than LBS does
		var n_el := 0
		for i in V.size():
			if we[i] < 0.9 or wf[i] < 0.1 or wf[i] > 0.9:
				continue
			n_el += 1
			var r0 := e_ref[i].distance_to(O0)
			bg = maxf(bg, b_d[i].distance_to(Ob) - r0)
			bg_l = maxf(bg_l, b_l[i].distance_to(Ob) - r0)
			out_l = maxf(out_l, b_d[i].distance_to(Ob) - b_l[i].distance_to(Ob))
		bulge = maxf(bulge, bg)
		print("DQS bulge, elbow at %.0f deg (%d elbow vertices, 10-90 %% forearm): volume DQS %+.1f cm3 / LBS %+.1f cm3 against straight; the most an elbow vertex ends farther from the joint centre than at rest: DQS %+.1f mm, LBS %+.1f mm; the most DQS sits outside LBS: %.1f mm" % [deg, n_el, bv_d * 1e6, bv_l * 1e6, bg * 1000.0, bg_l * 1000.0, out_l * 1000.0])
	B.ang["lowerarm_l"] = Vector3(90.0, B.ang["lowerarm_l"].y, B.ang["lowerarm_l"].z)
	Overlays.pose_skeleton(sk, idx, B)
	ok(bulge < 0.02, "bar 5: the DQS bulge is reported and under the 20 mm sanity bar (%.1f mm)" % (bulge * 1000.0))
	# 6 the GPU path on the bend
	g = gpu_check(src, mats)
	g_err = maxf(g_err, g[0])
	g_sing += int(g[1])
	print("GPU path: LBS of the pre-corrected rest vs CPU DQS, max diff %.3f um, %d singular vertices" % [g_err * 1e6, g_sing])
	ok(g_err < 1e-5 and g_sing == 0, "bar 6: the pre-corrected rest skinned by LBS is DQS (%.3f um < 10 um, %d singular)" % [g_err * 1e6, g_sing])

	# ---- 8 OFF and caching, on the real mesh instance
	dqs.update(1.0)
	var rb1 := dqs.rebuilds
	var c1 := dqs.corrected
	var ms1 := dqs.last_ms
	var drawn := mi.mesh
	dqs.update(1.0)
	var rb2 := dqs.rebuilds
	dqs.update(0.0)
	print("update: DQ on %d rebuilt (%d vertices corrected, %.1f ms), the same pose again %d, off -> the original mesh: %s" % [rb1, c1, ms1, rb2, mi.mesh == src])
	ok(rb1 == 1 and drawn != src and rb2 == 0 and mi.mesh == src, "bar 8: on rebuilds once, the same pose twice rebuilds nothing, off puts the file's own mesh back")

	# ---- 9 SAVED
	var S := Scene.new()
	var d0 := S.to_dict(B, false)
	S.dq_skin = 0.5
	var d1 := S.to_dict(B, false)
	var S2 := Scene.new()
	S2.from_dict(d1)
	ok(not d0.has("dq_skin") and d1.get("dq_skin", -1.0) == 0.5 and S2.dq_skin == 0.5 and S.clone().dq_skin == 0.5,
		"bar 9: dq_skin is saved (0.5 round-trips, cloned) and absent at 0")

	# ---- 10 PERF on the app's 52 pieces
	var pieces := Overlays.split_parts(man, sk, idx)
	var corr := Corrective.new()
	corr.attach(pieces.values(), sk)
	var pd := DqSkin.new()
	pd.attach(pieces.values(), sk)
	var poses := []
	for f in ["stand", "salute", "bat_hold", "command_point", "bat_ready_nick", "t_pose"]:
		var PB := Body.new()
		PB.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		PB.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/%s.json" % f)))
		poses.append(PB.ang.duplicate(true))
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	while poses.size() < 8:   # two more with every joint swung within its limits
		var a := {}
		for j in B.ang:
			var lim: Dictionary = B.lim.get(j, {})
			var v := Vector3.ZERO
			for c in 3:
				var r: Vector2 = lim.get(["bend", "side", "twist"][c], Vector2.ZERO)
				v[c] = rng.randf_range(r.x, r.y) * 0.6
			a[j] = v
		poses.append(a)
	# one warm-up pass first (not timed): each piece's list of 2+-bone vertices is made once per skin and kept
	var tw := Time.get_ticks_usec()
	for a in poses:
		B.ang = (a as Dictionary).duplicate(true)
		B.fk()
		Overlays.pose_skeleton(sk, idx, B)
		corr.update(B)
		pd.update(1.0)
	print("warm-up (the first pass over the %d poses, once per skin): %.0f ms" % [poses.size(), (Time.get_ticks_usec() - tw) / 1000.0])
	pd.update(0.0)
	var t_lbs := 0.0
	var t_dqs := 0.0
	var t_pass := 0.0
	var worst := 0.0
	var t_prep := 0.0
	var t_jobs := 0.0
	var last_rb := 0
	var last_c := 0
	var reps := 2
	for rep in reps:
		for mode in ["lbs", "dqs"]:   # the same poses, once each way (the corrective rebuilds alike in both)
			for a in poses:
				B.ang = (a as Dictionary).duplicate(true)
				B.fk()
				var t0 := Time.get_ticks_usec()
				Overlays.pose_skeleton(sk, idx, B)
				corr.update(B)
				if mode == "dqs":
					pd.update(1.0)
					t_pass += pd.last_ms
					worst = maxf(worst, pd.last_ms)
					t_prep += float(pd.prof.get("prep", 0.0))
					t_jobs += float(pd.prof.get("jobs", 0.0))
					last_rb = pd.rebuilds
					last_c = pd.corrected
				var dt := (Time.get_ticks_usec() - t0) / 1000.0
				if mode == "dqs":
					t_dqs += dt
				else:
					t_lbs += dt
			pd.update(0.0)
	var n := reps * poses.size()
	t_lbs /= n
	t_dqs /= n
	t_pass /= n
	print("PERF (%d pieces, %d frames, %d worker threads): LBS frame %.1f ms, DQS frame %.1f ms (the DQ pass %.1f ms mean, %.1f ms worst: reading the corrective's new meshes %.1f ms, the threaded correction + mesh build %.1f ms; last pass %d meshes rebuilt, %d vertex corrections)" % [pieces.size(), n, OS.get_processor_count(), t_lbs, t_dqs, t_pass, worst, t_prep / n, t_jobs / n, last_rb, last_c])
	if DisplayServer.get_name() == "headless":
		print("bar 10 not held headless: the dummy renderer's mesh upload is not the app's (run windowed, as run_all does)")
	else:
		ok(t_dqs <= t_lbs + 16.0, "bar 10: the DQS frame is at most the LBS frame + 16 ms (%.1f <= %.1f + 16 ms)" % [t_dqs, t_lbs])

	print("RESULT %s (%d fail)" % ["PASS" if fails == 0 else "FAIL", fails])
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
