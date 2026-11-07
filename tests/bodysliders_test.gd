## godot --headless --path . -s tests/bodysliders_test.gd     (ROADMAP_400 C22: fat / muscle / bone sliders as brushes)
## BodySliders (scripts/body_sliders.gd): three region brushes on the mannequin skin (assets/mannequin.glb welded into one
## KMesh, T pose, rest) over a bone's region (the verts KMeshBody assigns to upperarm_l). A stroke asks for an AMOUNT: the
## change of the region girth in metres at mid-bone (circumference of the cross-section by the plane square to the bone,
## half way along it).
##   lean  reduces subcutaneous volume (girth - amount)    bulk  grows muscle volume (girth + amount)
##   soft  relaxes the surface (Laplacian toward the neighbours; no girth amount)
## Bars, written before any implementation (this file was committed first; none moved after a run):
##   1 BULK +2.0 cm on the left upper arm: measured girth change 1.8 .. 2.2 cm (stated +-10 %). LEAN -1.5 cm: -1.35 .. -1.65 cm.
##   2 LANDMARKS: bulk and lean leave every skeleton bone origin within 0.5 mm, and every mesh vert within 1.5 cm of the
##     shoulder joint or the elbow joint within 0.5 mm of where it was.
##   3 SOFT: the region gets planted roughness (+-1.5 mm along the normals, fixed seed); the variance of the per-vertex
##     curvature proxy (|Laplacian vector|) over the region falls to <= 0.90 of before; |girth change| <= 5 mm; landmarks
##     as bar 2.
##   4 ANSUR BOUND: 20 bulk strokes of +2 cm on a fresh arm stop at the bound: final girth <= bound + 1 mm and >= bound - 5 mm;
##     at least one stroke is clamped and its message names ANSUR; no message before the first clamp. 12 lean strokes of
##     -2 cm stop at the lower bound the same way (girth >= lower bound - 1 mm, <= lower bound + 5 mm).
##     BOUND (BodySliders.BOUNDS, mean +- 3 SD, men / women): ANSUR II (Gordon et al. 2014, NATICK/TR-15/007) "biceps
##     circumference, flexed" -- the numbers in the table are UNVERIFIED (from memory; no DOI / PMID checked). The bar tests
##     that the code obeys ITS table, not that the table is right.
##   5 UNBRUSHED: after bulk, lean and soft on the left upper arm, every vert outside that region is byte-identical (right
##     arm, legs, trunk included); the face list is identical.
##   6 UNDO: each stroke is exactly one KMeshUndo step; undo returns all verts bit-for-bit; redo returns the stroked state.
##   7 PLANTED FAKES must FAIL the checks: (a) a brush that grows the arm by moving every region vert out with no taper (the
##     elbow ring moves) fails the landmark check; (b) a stroke that grew 3 cm when 2 cm was asked fails bar 1's window;
##     (c) a stroke that also nudged the right arm fails bar 5's check.
extends SceneTree

var fails := 0
const REG := "upperarm_l"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func skin_kmesh(man: Node3D) -> KMesh:
	var vs := PackedVector3Array()
	var fs := []
	for mi in man.find_children("*", "MeshInstance3D", true, false):
		var am := (mi as MeshInstance3D).mesh as ArrayMesh
		for si in am.get_surface_count():
			var k := KMesh.new().from_array_mesh(am, si)
			var o := vs.size()
			vs.append_array(k.verts)
			for f in k.faces:
				var g := PackedInt32Array(f)
				for i in g.size():
					g[i] += o
				fs.append(g)
	return KMesh.new().from_arrays(vs, fs)


func clone(k: KMesh) -> KMesh:
	return KMesh.new().from_arrays(k.verts.duplicate(), k.faces.duplicate())


func joint(sk: Skeleton3D, nm: String) -> Vector3:
	for b in sk.get_bone_count():
		if sk.get_bone_name(b).to_lower() == nm:
			return sk.get_bone_global_pose(b).origin
	return Vector3.ZERO


func bones(sk: Skeleton3D) -> PackedVector3Array:
	var o := PackedVector3Array()
	for b in sk.get_bone_count():
		o.append(sk.get_bone_global_pose(b).origin)
	return o


## max move (m) of the verts within `r` of `pts` between a and b
func landmark_move(a: PackedVector3Array, b: PackedVector3Array, pts: Array, r: float) -> float:
	var w := 0.0
	var n := 0
	for i in a.size():
		for p in pts:
			if a[i].distance_to(p) <= r:
				w = maxf(w, a[i].distance_to(b[i]))
				n += 1
				break
	return w if n > 0 else 999.0


## max move (m) of the verts NOT in `ids`
func outside_move(a: PackedVector3Array, b: PackedVector3Array, ids: PackedInt32Array) -> float:
	var inside := {}
	for i in ids:
		inside[i] = true
	var w := 0.0
	for i in a.size():
		if not inside.has(i):
			w = maxf(w, a[i].distance_to(b[i]))
	return w


func hash_of(k: KMesh) -> String:
	return k.verts.to_byte_array().hex_encode().sha256_text()


func _init() -> void:
	var man: Node3D = (load("res://assets/mannequin.glb") as PackedScene).instantiate()
	root.add_child(man)
	for ap in man.find_children("*", "AnimationPlayer", true, false):
		ap.queue_free()
	await idle(2)
	var sk: Skeleton3D = man.find_children("*", "Skeleton3D", true, false)[0]
	sk.reset_bone_poses()
	var base := skin_kmesh(man)
	var ids := BodySliders.region_verts(base, sk, REG)
	var sho := joint(sk, "upperarm_l")
	var elb := joint(sk, "lowerarm_l")
	var lm := [sho, elb]
	var g0 := BodySliders.girth(base, sk, REG)
	print("region %s: %d verts of %d; mid-bone girth %.1f mm; arm length %.1f cm" % [REG, ids.size(), base.verts.size(), g0 * 1000.0, sho.distance_to(elb) * 100.0])
	ok(ids.size() > 200 and g0 > 0.15 and g0 < 0.5, "bar 0: the region has verts and a plausible girth (%.1f mm)" % [g0 * 1000.0])

	# ---- 1 + 2 bulk / lean amount and landmarks
	var b0 := bones(sk)
	var kb := clone(base)
	var ub := KMeshUndo.new()
	BodySliders.stroke_undoable(ub, kb, sk, REG, "bulk", 0.020)
	var db: float = BodySliders.girth(kb, sk, REG) - g0
	ok(db >= 0.018 and db <= 0.022, "bar 1: bulk +2.0 cm -> girth change %.2f cm (window 1.80 .. 2.20)" % [db * 100.0])
	var lmb := landmark_move(base.verts, kb.verts, lm, 0.015)
	ok(lmb <= 0.0005, "bar 2: bulk, mesh verts within 1.5 cm of shoulder / elbow moved %.3f mm (<= 0.5)" % [lmb * 1000.0])
	var bn := bones(sk)
	var bmax := 0.0
	for i in b0.size():
		bmax = maxf(bmax, b0[i].distance_to(bn[i]))
	ok(bmax <= 0.0005, "bar 2: skeleton bone origins moved %.4f mm (<= 0.5)" % [bmax * 1000.0])

	var kl := clone(base)
	var ul := KMeshUndo.new()
	BodySliders.stroke_undoable(ul, kl, sk, REG, "lean", 0.015)
	var dl: float = BodySliders.girth(kl, sk, REG) - g0
	ok(dl <= -0.01350 and dl >= -0.01650, "bar 1: lean 1.5 cm -> girth change %.2f cm (window -1.35 .. -1.65)" % [dl * 100.0])
	var lml := landmark_move(base.verts, kl.verts, lm, 0.015)
	ok(lml <= 0.0005, "bar 2: lean, landmark verts moved %.3f mm (<= 0.5)" % [lml * 1000.0])

	# ---- 3 soft on planted roughness
	var ks := clone(base)
	var rng := RandomNumberGenerator.new()
	rng.seed = 22
	var nrm := ks.vert_normals
	for v in ids:
		ks.verts[v] += nrm[v] * rng.randf_range(-0.0015, 0.0015)
	ks.rebuild()
	var rough := clone(ks)
	var cv0: float = BodySliders.curvature_variance(ks, ids)
	var gs0: float = BodySliders.girth(ks, sk, REG)
	var us := KMeshUndo.new()
	BodySliders.stroke_undoable(us, ks, sk, REG, "soft", 0.0)
	var cv1: float = BodySliders.curvature_variance(ks, ids)
	var gs1: float = BodySliders.girth(ks, sk, REG)
	ok(cv0 > 0.0 and cv1 <= 0.90 * cv0, "bar 3: soft, curvature variance %.3e -> %.3e (ratio %.3f, <= 0.90)" % [cv0, cv1, cv1 / maxf(cv0, 1e-30)])
	ok(absf(gs1 - gs0) <= 0.005, "bar 3: soft, girth change %.2f mm (<= 5)" % [(gs1 - gs0) * 1000.0])
	var lms := landmark_move(rough.verts, ks.verts, lm, 0.015)
	ok(lms <= 0.0005, "bar 3: soft, landmark verts moved %.3f mm (<= 0.5)" % [lms * 1000.0])

	# ---- 4 ANSUR bound
	var hi: float = BodySliders.bound(REG, "male")["max"]
	var lo: float = BodySliders.bound(REG, "male")["min"]
	var ka := clone(base)
	var ua := KMeshUndo.new()
	var first_clamp := -1
	var early_msg := false
	var nclamp := 0
	var msg_ansur := true
	for i in 20:
		var r: Dictionary = BodySliders.stroke_undoable(ua, ka, sk, REG, "bulk", 0.020)
		if bool(r.get("clamped", false)):
			nclamp += 1
			if first_clamp < 0:
				first_clamp = i
			msg_ansur = msg_ansur and String(r.get("message", "")).contains("ANSUR")
		elif first_clamp < 0 and String(r.get("message", "")) != "":
			early_msg = true
	var ga: float = BodySliders.girth(ka, sk, REG)
	print("bulk x20: bound %.1f mm, final %.1f mm, first clamp at stroke %d, %d clamped" % [hi * 1000.0, ga * 1000.0, first_clamp, nclamp])
	ok(ga <= hi + 0.001 and ga >= hi - 0.005, "bar 4: repeated bulk ends %.1f mm vs bound %.1f (<= bound+1, >= bound-5)" % [ga * 1000.0, hi * 1000.0])
	ok(first_clamp > 0 and nclamp >= 1 and msg_ansur and not early_msg, "bar 4: clamp message names ANSUR, none before the first clamp (first at %d)" % first_clamp)
	var kn := clone(base)
	var un := KMeshUndo.new()
	for i in 12:
		BodySliders.stroke_undoable(un, kn, sk, REG, "lean", 0.020)
	var gn: float = BodySliders.girth(kn, sk, REG)
	ok(gn >= lo - 0.001 and gn <= lo + 0.005, "bar 4: repeated lean ends %.1f mm vs lower bound %.1f" % [gn * 1000.0, lo * 1000.0])

	# ---- 5 unbrushed byte-identical
	var o1 := outside_move(base.verts, kb.verts, ids)
	var o2 := outside_move(base.verts, kl.verts, ids)
	var o3 := outside_move(rough.verts, ks.verts, ids)
	ok(o1 == 0.0 and o2 == 0.0 and o3 == 0.0, "bar 5: verts outside the region moved bulk %.6f lean %.6f soft %.6f mm (all 0)" % [o1 * 1000.0, o2 * 1000.0, o3 * 1000.0])
	var same_faces := kb.faces.size() == base.faces.size()
	for i in mini(kb.faces.size(), base.faces.size()):
		if kb.faces[i] != base.faces[i]:
			same_faces = false
	ok(same_faces, "bar 5: face list identical")

	# ---- 6 undo
	var ku := clone(base)
	var uu := KMeshUndo.new()
	var h0 := hash_of(ku)
	var steps_ok := true
	for br in [["bulk", 0.01], ["lean", 0.01], ["soft", 0.0]]:
		var n0 := uu.steps.size()
		BodySliders.stroke_undoable(uu, ku, sk, REG, br[0], br[1])
		steps_ok = steps_ok and uu.steps.size() == n0 + 1
	ok(steps_ok and uu.steps.size() == 3, "bar 6: 3 strokes = 3 undo steps (%d)" % uu.steps.size())
	var h3 := hash_of(ku)
	ok(h3 != h0, "bar 6: the strokes changed the mesh")
	uu.undo()
	uu.undo()
	uu.undo()
	ok(hash_of(ku) == h0, "bar 6: three undos give every vert back bit-for-bit")
	uu.redo()
	uu.redo()
	uu.redo()
	ok(hash_of(ku) == h3, "bar 6: three redos give the stroked state bit-for-bit")

	# ---- 7 planted fakes
	var fk := clone(base)
	var fn := fk.vert_normals
	var ax := (elb - sho).normalized()
	for v in ids:
		var rad: Vector3 = fn[v] - ax * fn[v].dot(ax)
		fk.verts[v] += rad.normalized() * (0.020 / TAU)
	var fl := landmark_move(base.verts, fk.verts, lm, 0.015)
	ok(not (fl <= 0.0005), "bar 7a: untapered fake moves the elbow ring %.2f mm and is CAUGHT by the landmark check" % [fl * 1000.0])
	var d3 := 0.030
	ok(not (d3 >= 0.018 and d3 <= 0.022), "bar 7b: a 3 cm growth for a 2 cm ask is outside the window")
	var fr := clone(kb)
	var rid := BodySliders.region_verts(base, sk, "upperarm_r")
	fr.verts[rid[0]] += Vector3(0.0002, 0, 0)
	ok(not (outside_move(kb.verts, fr.verts, ids) == 0.0), "bar 7c: a nudge of the right arm is CAUGHT by the unbrushed check")

	print("bodysliders: %d fail" % fails)
	quit(1 if fails > 0 else 0)
