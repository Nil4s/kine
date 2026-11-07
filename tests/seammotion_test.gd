## godot --path . -s tests/seammotion_test.gd     (ROADMAP_400 D13; boots main.tscn: needs a window / GPU)
## Seams that avoid motion: a UV seam that crosses a high-stretch area of the open scene's animation is flagged
## (scripts/seam_motion.gd; the UV editor lists and highlights it, scripts/kmesh_uv_editor.gd, keys M check / N suggest).
## THE METRIC (stated before any code), reusing SculptMotion's stretch: frames f = 0 .. ceil(length * fps), t = min(f / fps, length),
## the scene applied on a body of its own, the REST mesh skinned at that pose (the scene's dq_skin blend; this test: 0 = LBS).
##   own(e)   = max over frames of | ln( posed edge length / rest edge length ) |        (edges with rest length > 1 mm)
##   local(e) = max of own over e and every edge that shares a vertex with e              (the seam edge and its neighbours)
## A seam EDGE is flagged when local(e) >= THRESHOLD = 0.15; a seam (a chain) is flagged when any of its edges is.
## WHY 0.15: |ln r| = 0.15 is a 16 pct stretch (14 pct squash) of an edge, i.e. the texture on both sides of the cut moves
## 15 pct relative to the cut; below ~0.1 the cut hides in the shading, above ~0.15 it shears visibly. A choice, not a measurement.
## Bars, written BEFORE the implementation:
##   0 INSTRUMENT  the scene has >= 90 frames and the elbow bends >= 100 deg; seam A (front of the elbow crease, 6 cm above to 6 cm
##                 below, on the side the hand moves toward) has >= 4 edges and every vertex within 9 cm of the elbow joint; seam B
##                 (same side, 14 .. 22 cm above the elbow) has >= 4 edges and every vertex > 10 cm from it; both are real mesh paths
##   1 FLAG        in the elbow-flexion scene seam A is flagged (>= 2 edges with local >= 0.15) and seam B is not (max local < 0.15);
##                 in a STATIC scene (all cards at rest) seam A is not flagged and its max local < 0.001
##   2 NUMBERS     per seam edge, own and local match the test's own recomputation (own edge list from the faces, own LBS loop from the
##                 bind matrices, own frame loop) within 1e-5, for A and for B
##   3 SUGGEST     the suggested path for A has the same two endpoints, is a chain of real mesh edges, has max local < A's max local (the
##                 test's own number), and is no longer than 3 x A's rest length (it stays near)
##   4 EDITOR      with both seams on the mesh "seam" attribute, the UV editor's check lists exactly one flagged seam, whose edges are A's
##                 and not B's; its suggestion keeps the endpoints
##   5 NO WRITES   the mesh (verts, faces, every attribute: uv, seam, weights) is byte-identical before / after the module, the
##                 editor check and the suggestion
##   6 PLANTED FAKES  the same checkers FAIL (a) flags on random edges, (b) A's and B's flags swapped, (c) stretch numbers off by
##                 1e-3, (d) a suggested path with a different endpoint; the real results pass the same checkers
##   7 tools/run_all.sh has the seammotion line
extends SceneTree

var fails := 0
var m: Node
var skin: Skin
var sp: SculptPose
var R: KMesh
var G: Body
var skc: Skeleton3D
var fps := 30
var NF := 0
var inc := {}      # vertex -> Array of edge keys
var elen := {}     # edge key -> rest length


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ekey(a: int, b: int) -> int:
	return mini(a, b) * 1000003 + maxi(a, b)


func world_of(bone: String) -> Vector3:
	var sk: Skeleton3D = m.skel
	var b := sk.find_bone(bone)
	var t := sk.get_bone_pose(b)
	var p := sk.get_bone_parent(b)
	while p >= 0:
		t = sk.get_bone_pose(p) * t
		p = sk.get_bone_parent(p)
	return t.origin


func lbs(v: Vector3, i: int, mats: Array) -> Vector3:
	var x := Vector3.ZERO
	var y := Vector3.ZERO
	var z := Vector3.ZERO
	var o := Vector3.ZERO
	for q in 4:
		var wt := sp.w[i * 4 + q]
		if wt <= 0.0:
			continue
		var B: Transform3D = mats[sp.bo[i * 4 + q]]
		x += B.basis.x * wt
		y += B.basis.y * wt
		z += B.basis.z * wt
		o += B.origin * wt
	return Transform3D(Basis(x, y, z), o) * v


func mats_at(f: int) -> Array:
	m._ps().apply(G, minf(float(f) / fps, m._ps().length()))
	Overlays.pose_skeleton(skc, m.bone_idx, G)
	return DqSkin.bind_mats(skc, skin)


func build_incidence() -> void:
	inc = {}
	elen = {}
	for f in R.faces:
		var n: int = f.size()
		for i in n:
			var a: int = f[i]
			var b: int = f[(i + 1) % n]
			var k := ekey(a, b)
			if elen.has(k):
				continue
			elen[k] = R.verts[a].distance_to(R.verts[b])
			if not inc.has(a):
				inc[a] = []
			if not inc.has(b):
				inc[b] = []
			inc[a].append(k)
			inc[b].append(k)


## the test's own table for a list of seam edges: edge key -> [own, local]
func my_table(seam: Array) -> Dictionary:
	var sv := {}
	for e in seam:
		sv[e.x] = true
		sv[e.y] = true
	var need := {}      # edges with an end on a seam vertex
	var vs := {}
	for v in sv:
		for k in inc[v]:
			need[k] = true
	for k in need:
		vs[k / 1000003] = true
		vs[k % 1000003] = true
	var own := {}
	for k in need:
		own[k] = 0.0
	for f in NF:
		var mats := mats_at(f)
		var cache := {}
		for v in vs:
			cache[v] = lbs(R.verts[v], v, mats)
		for k in need:
			var a: int = k / 1000003
			var b: int = k % 1000003
			if elen[k] > 0.001:
				own[k] = maxf(own[k], absf(log(cache[a].distance_to(cache[b]) / elen[k])))
	var out := {}
	for e in seam:
		var k := ekey(e.x, e.y)
		var loc := 0.0
		for v in [e.x, e.y]:
			for kk in inc[v]:
				loc = maxf(loc, own[kk])
		out[k] = [own[k], loc]
	return out


func nearest(p: Vector3) -> int:
	var best := 0
	var bd := 1e9
	for i in R.verts.size():
		var d := R.verts[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func seam_len(seam: Array) -> float:
	var s := 0.0
	for e in seam:
		s += R.verts[e.x].distance_to(R.verts[e.y])
	return s


func scene_rest_pose() -> void:
	var B: Body = m.B
	for j in B.ang:
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3.ZERO
	B.fk()


func build_scene(static_scene: bool) -> void:
	var B: Body = m.B
	var cards := []
	var keys := [[0.0, 0.8], [130.0, 0.7], [0.0, 0.9], [90.0, 1.0], [0.0, 0.8]]
	for k in keys:
		scene_rest_pose()
		B.ang["lowerarm_r"] = Vector3(0.0 if static_scene else k[0], 0, 0)
		B.fk()
		cards.append({"name": "seam %d" % k[0], "pose": B.to_dict(), "move": k[1], "hold": 0.1})
	m.S.from_dict({"scene": "zz_seammotion", "fps": fps, "free_limits": true, "dq_skin": 0.0, "cards": cards})
	m._rebuild_cards()
	scene_rest_pose()
	m._refresh()
	NF = int(ceil(m._ps().length() * fps)) + 1


func bend_at(f: int) -> float:
	m._ps().apply(G, minf(float(f) / fps, m._ps().length()))
	return (G.ang["lowerarm_r"] as Vector3).x


func mesh_hash() -> int:
	var parts := [R.verts, R.faces]
	for nm in R.list_attrs():
		parts.append(R.attr_data(nm))
	return hash(var_to_bytes(parts))


## ---- the checkers the planted fakes go through
## flags: key -> bool for the report edges; tab: key -> [own, local] from the test
func flags_ok(flags: Dictionary, tab: Dictionary, thr: float) -> bool:
	for k in tab:
		if flags.get(k, false) != (tab[k][1] >= thr):
			return false
	return true


func numbers_ok(rep_edges: Array, tab: Dictionary) -> float:
	if rep_edges.size() != tab.size():
		return 1e9
	var worst := 0.0
	for r in rep_edges:
		var k := ekey(r["edge"].x, r["edge"].y)
		if not tab.has(k):
			return 1e9
		worst = maxf(worst, maxf(absf(float(r["own"]) - tab[k][0]), absf(float(r["local"]) - tab[k][1])))
	return worst


func path_ok(sg: Dictionary, a: int, b: int, orig_max: float, orig_len: float) -> bool:
	var pv: Array = sg.get("path", [])
	if pv.size() < 2 or pv[0] != a or pv[pv.size() - 1] != b:
		return false
	for i in range(pv.size() - 1):
		if not elen.has(ekey(pv[i], pv[i + 1])):
			return false
	var edges: Array = []
	for i in range(pv.size() - 1):
		edges.append(Vector2i(pv[i], pv[i + 1]))
	var tab := my_table(edges)
	var mx := 0.0
	for k in tab:
		mx = maxf(mx, tab[k][1])
	return mx < orig_max and seam_len(edges) <= 3.0 * orig_len


func flags_of(rep: Dictionary) -> Dictionary:
	var d := {}
	for r in rep["edges"]:
		d[ekey(r["edge"].x, r["edge"].y)] = bool(r["flag"])
	return d


func ends_of(seam: Array) -> Array:
	var deg := {}
	for e in seam:
		deg[e.x] = deg.get(e.x, 0) + 1
		deg[e.y] = deg.get(e.y, 0) + 1
	var out := []
	for v in deg:
		if deg[v] == 1:
			out.append(v)
	out.sort()
	return out


func to_edges(path: Array) -> Array:
	var out := []
	for i in range(path.size() - 1):
		out.append(Vector2i(mini(path[i], path[i + 1]), maxi(path[i], path[i + 1])))
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
	R = m.kmed.mesh
	skin = BaseBody.skin_of(m)
	G = Body.new()
	G.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	skc = (m.skel as Skeleton3D).duplicate()
	build_scene(false)
	sp = SculptPose.new().setup(R, skin, skc)
	build_incidence()
	# geometry of the seams
	var elbow := world_of("lowerarm_r")
	var shoulder := world_of("upperarm_r")
	var hand := world_of("hand_r")
	var u := (elbow - shoulder).normalized()
	var fmax := 0
	var bmax := 0.0
	for f in NF:
		var b := bend_at(f)
		if b > bmax:
			bmax = b
			fmax = f
	var mats := mats_at(fmax)
	var tip := nearest(hand)
	var d := lbs(R.verts[tip], tip, mats) - R.verts[tip]
	var n := (d - u * d.dot(u)).normalized()
	var pa := nearest(elbow - u * 0.06 + n * 0.05)
	var qa := nearest(elbow + u * 0.06 + n * 0.05)
	var pb := nearest(elbow - u * 0.14 + n * 0.05)
	var qb := nearest(elbow - u * 0.22 + n * 0.05)
	var A: Array = to_edges(SeamMotion.shortest(R, pa, qa))
	var Bs: Array = to_edges(SeamMotion.shortest(R, pb, qb))
	var a_near := true
	for e in A:
		if R.verts[e.x].distance_to(elbow) > 0.11 or R.verts[e.y].distance_to(elbow) > 0.11:
			a_near = false
	var b_far := true
	for e in Bs:
		if R.verts[e.x].distance_to(elbow) <= 0.10 or R.verts[e.y].distance_to(elbow) <= 0.10:
			b_far = false
	var real := true
	for e in A + Bs:
		real = real and elen.has(ekey(e.x, e.y))
	ok(NF >= 90 and bmax >= 100.0, "0 the scene has %d frames, the elbow bends %.0f deg (frame %d); bend direction %s" % [NF, bmax, fmax, str(n)])
	ok(A.size() >= 4 and a_near, "0 seam A: %d edges, rest length %.3f m, all within 11 cm of the elbow: %s" % [A.size(), seam_len(A), str(a_near)])
	ok(Bs.size() >= 3 and b_far, "0 seam B: %d edges, rest length %.3f m, all > 10 cm from the elbow: %s" % [Bs.size(), seam_len(Bs), str(b_far)])
	ok(real, "0 both seams are chains of real mesh edges")
	if A.size() < 1 or Bs.size() < 1:
		print("seammotion: %d fails" % fails)
		quit(1)
		return
	# seam attribute for the editor, then the byte baseline
	KMeshUV.mark_seams(R, A + Bs)
	var h0 := mesh_hash()
	# 1 FLAG + 2 NUMBERS in the elbow scene
	var repA: Dictionary = SeamMotion.run(R, m, A)
	var repB: Dictionary = SeamMotion.run(R, m, Bs)
	var tabA := my_table(A)
	var tabB := my_table(Bs)
	var nflagA := 0
	for r in repA["edges"]:
		if r["flag"]:
			nflagA += 1
	var maxA := 0.0
	var maxB := 0.0
	for k in tabA:
		maxA = maxf(maxA, tabA[k][1])
	for k in tabB:
		maxB = maxf(maxB, tabB[k][1])
	print("   threshold %.2f; seam A max local %.4f (%d of %d edges flagged), seam B max local %.4f; frames %d" % [SeamMotion.THRESHOLD, maxA, nflagA, A.size(), maxB, int(repA["frames"])])
	ok(SeamMotion.THRESHOLD == 0.15, "1 the threshold is the stated 0.15")
	ok(bool(repA["flagged_any"]) and nflagA >= 2, "1 seam A (front of the elbow) is flagged: %d edges" % nflagA)
	ok(not bool(repB["flagged_any"]) and maxB < 0.15, "1 seam B (upper arm, away from the crease) is not flagged: max local %.4f" % maxB)
	var dA := numbers_ok(repA["edges"], tabA)
	var dB := numbers_ok(repB["edges"], tabB)
	ok(dA <= 1e-5 and dB <= 1e-5, "2 own / local stretch per edge within 1e-5 of the test's (A worst %.8f, B worst %.8f)" % [dA, dB])
	ok(flags_ok(flags_of(repA), tabA, 0.15) and flags_ok(flags_of(repB), tabB, 0.15), "2 the flags equal local >= 0.15 on every edge of A and B")
	# 3 SUGGEST
	var sg: Dictionary = SeamMotion.suggest(R, repA, A)
	var ea := ends_of(A)
	var okpath := ea.size() == 2 and path_ok(sg, ea[0], ea[1], maxA, seam_len(A))
	var smax := 0.0
	var pe: Array = to_edges(sg.get("path", []))
	if pe.size() > 0:
		var tb := my_table(pe)
		for k in tb:
			smax = maxf(smax, tb[k][1])
	print("   suggested path: %d edges, rest length %.3f m (seam A %.3f m), max local %.4f (seam A %.4f)" % [pe.size(), seam_len(pe), seam_len(A), smax, maxA])
	ok(okpath, "3 the suggested path keeps the endpoints, uses real edges, has lower max stretch and stays near")
	# 4 EDITOR
	var ed := KMeshUVEditor.new()
	ed.setup(m.kmed)
	var lst: Dictionary = ed.seam_motion_check()
	var fl: Array = lst.get("flagged_seams", [])
	var fl_ok := fl.size() == 1
	if fl_ok:
		var ks := {}
		for e in fl[0]["edges"]:
			ks[ekey(e.x, e.y)] = true
		for e in A:
			fl_ok = fl_ok and ks.has(ekey(e.x, e.y))
		for e in Bs:
			fl_ok = fl_ok and not ks.has(ekey(e.x, e.y))
	ok(fl_ok, "4 the UV editor lists exactly one flagged seam, A (%d flagged seams listed)" % fl.size())
	var sg2: Array = ed.seam_motion_suggest()
	var ok2 := sg2.size() == 1 and (sg2[0]["path"] as Array).size() >= 2
	if ok2:
		var p2: Array = sg2[0]["path"]
		ok2 = ea.size() == 2 and p2[0] == ea[0] and p2[p2.size() - 1] == ea[1]
	ok(ok2, "4 the editor suggestion keeps the endpoints of seam A")
	# 5 NO WRITES
	ok(mesh_hash() == h0, "5 mesh verts, faces and all %d attributes byte-identical after module, editor check and suggestion" % R.list_attrs().size())
	# static scene
	build_scene(true)
	var repS: Dictionary = SeamMotion.run(R, m, A)
	var tabS := my_table(A)
	var maxS := 0.0
	for k in tabS:
		maxS = maxf(maxS, tabS[k][1])
	ok(not bool(repS["flagged_any"]) and maxS < 0.001, "1 STATIC scene: seam A not flagged, max local %.6f" % maxS)
	ok(numbers_ok(repS["edges"], tabS) <= 1e-5, "2 static scene numbers within 1e-5")
	ok(mesh_hash() == h0, "5 mesh byte-identical after the static run too")
	# 6 PLANTED FAKES
	var real_flags := flags_of(repA)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var rnd := {}
	for k in real_flags:
		rnd[k] = rng.randf() < 0.5
	if rnd == real_flags:
		for k in rnd:
			rnd[k] = not rnd[k]
	ok(not flags_ok(rnd, tabA, 0.15), "6 PLANTED FAKE: flags on random edges FAIL the flag checker")
	ok(not (flags_ok(flags_of(repB), tabA, 0.15) and flags_ok(flags_of(repA), tabB, 0.15)), "6 PLANTED FAKE: A and B flags swapped FAIL")
	var off: Array = []
	for r in repA["edges"]:
		var c: Dictionary = (r as Dictionary).duplicate()
		c["own"] = float(c["own"]) + 1e-3
		off.append(c)
	ok(numbers_ok(off, tabA) > 1e-5, "6 PLANTED FAKE: stretch numbers off by 1e-3 FAIL the 1e-5 check")
	var bad: Dictionary = sg.duplicate(true)
	if (bad["path"] as Array).size() > 2:
		(bad["path"] as Array)[(bad["path"] as Array).size() - 1] = (bad["path"] as Array)[(bad["path"] as Array).size() - 2]
	ok(not path_ok(bad, ea[0], ea[1], maxA, seam_len(A)), "6 PLANTED FAKE: a suggested path with a different endpoint FAILS")
	ok(flags_ok(real_flags, tabA, 0.15) and path_ok(sg, ea[0], ea[1], maxA, seam_len(A)), "6 control: the real flags and path pass the same checkers")
	# 7 run_all
	var ra := FileAccess.get_file_as_string("res://tools/run_all.sh")
	ok(ra.contains("seammotion:w"), "7 tools/run_all.sh has the seammotion line")
	print("seammotion: %d fails" % fails)
	quit(1 if fails > 0 else 0)
