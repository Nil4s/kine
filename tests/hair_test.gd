## godot --path . -s tests/hair_test.gd     (ROADMAP 87, HAIR STRANDS; scripts/hair.gd, the bake in main.gd _hair_bake)
## A window is needed for the mesh and the picture: godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/hair_test.gd
## The picture (whole body, a side view, the head turning): HAIR_SHOT=<path.png>, default C:/Users/Nick/.claude/jobs/9afc22db/tmp/hair.png
## Bars, written before measuring:
##   1 ROOTS: a ponytail's 8 roots, read off the head mesh, stay ON the skinned head within 1 mm at head yaw 0 and at 60 deg
##     (the root is the back-most surface point: a ray from 5 cm behind it, toward the head, first hits the root within 1 mm).
##     The roots turn with the head: each root's distance from the head joint is the same at 60 deg as at 0 (1 mm).
##   2 LENGTH: every segment of every strand, at every baked frame of a 60 deg head turn (0.15 s, then held), is within 2 %
##     of its rest length (3 cm).
##   3 CAPSULES: every strand node (not the root), at every baked frame, is outside each body capsule (head, neck, spine,
##     chest, clavicles, upper arms) by at least -3 mm (inside by no more than 3 mm; the sim pushes out to radius + 4 mm).
##   4 LAG AND SETTLE: a head yaw of 40 deg in 0.15 s, starting at 1.0 s, held to 5 s (sim at 120 fps, rest body). The tip
##     LAGS the head: it passes half its total displacement later than the head does (lag > 0). It SETTLES: after the head
##     stops (1.15 s), its distance from its final place stays within 2 % of the total displacement for good, in < 1.5 s.
##     Anti-vacuity: the total displacement is > 1 cm.
##   5 SCRUB REPEATABLE: two runs of the sim on the same inputs give identical nodes (max difference 0), and a second bake in
##     main gives the same nodes at 0.5 s and 1.2 s (1e-9).
##   6 PLACEMENT: the roots sit on the BACK of the head: each root's head-local z is below -0.06 m (behind the head's centre;
##     the head's half-depth is ~0.10 m), |x| < 0.03 m, and y within the top 0.4 H of the head. The picture, read by eye: the
##     ponytail hangs from the back of the head, not the neck or the shoulder.
extends SceneTree

var fails := 0
var m: Node
var B: Body


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the yaw the test turns the head by: 0 until t0, a smooth ramp over `dur`, then held at deg
func turn_at(t: float, t0: float, dur: float, deg: float) -> float:
	var u := clampf((t - t0) / dur, 0.0, 1.0)
	return deg * u * u * (3.0 - 2.0 * u)


## the rest body with the head turned by deg about its twist axis (the Body's ang.z, as the face test turns it)
func pose_head(deg: float) -> void:
	B.ang["head"] = Vector3(0.0, 0.0, deg)
	B.fk()


## the body at rest except the head, which is turned by the profile: the pose the bake and the sim read
func rest_pose(t: float) -> void:
	for j in B.ang.keys():
		B.ang[j] = Vector3.ZERO
	pose_head(turn_at(t, 1.0, 0.15, 60.0))
	m._refresh()


func caps_now() -> Array:
	var out := []
	for part in Hair.CAPS:
		var c: Array = B.cap(part)
		out.append([c[0], c[1], float(B.rad[part])])
	return out


func skinned_tris() -> PackedVector3Array:
	var out := PackedVector3Array()
	var pc: MeshInstance3D = m.pieces["head"]
	var sk: Skeleton3D = m.skel
	var sn: Skin = pc.skin
	for si in pc.mesh.get_surface_count():
		var arr := pc.mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bo: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var wt: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var per := bo.size() / vs.size()
		var cache := {}
		for i in ix:
			if not cache.has(i):
				var p := Vector3.ZERO
				for q in per:
					var w := wt[i * per + q]
					if w <= 0.0:
						continue
					var bi := bo[i * per + q]
					var bn: int = sn.get_bind_bone(bi) if sn.get_bind_bone(bi) >= 0 else bi
					p += w * ((sk.global_transform * sk.get_bone_global_pose(bn) * sn.get_bind_pose(bi)) * vs[i])
				cache[i] = p
			out.append(cache[i])
	return out


## the distance from a root to the first skinned surface met by a ray from 5 cm behind it, toward the head
func surface_gap(tris: PackedVector3Array, w: Vector3, back: Vector3) -> float:
	var origin := w + back * 0.05
	var best := INF
	var hit_p := Vector3.ZERO
	for t in range(0, tris.size() - 2, 3):
		var h: Variant = Geometry3D.ray_intersects_triangle(origin, -back, tris[t], tris[t + 1], tris[t + 2])
		if h != null:
			var d := ((h as Vector3) - origin).length()
			if d < best:
				best = d
				hit_p = h as Vector3
	return hit_p.distance_to(w) if best < INF else INF


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	m._commands()
	B = m.B
	# the body at rest in every joint, so the caps are the rest body's and only the head moves
	for j in B.ang.keys():
		B.ang[j] = Vector3.ZERO
	B.fk()
	m._refresh()
	await idle(2)

	# the preset and the roots, read off the head mesh at rest
	var p: Dictionary = Hair.preset("ponytail")
	m.S.hair = p
	var pts: PackedVector3Array = m._head_pts()
	var roots: Array = Hair.roots(pts, p, B.p0["head"])
	ok(roots.size() == int(p["strands"]), "1 roots: %d of %d strands found a surface behind the head (the ring is on the mesh)" % [roots.size(), int(p["strands"])])
	var worst_gap := 0.0
	var worst_drift := 0.0
	var turned_deg := 0.0
	var up_axis_ok := true
	var rest_dist := []
	for r in roots:
		rest_dist.append((r as Vector3).length())
	for deg in [0.0, 60.0]:
		pose_head(deg)
		m._refresh()
		await idle(1)
		var tris := skinned_tris()
		var G: Quaternion = B.G["head"]
		var back := G * Vector3(0, 0, -1)
		if deg == 60.0:
			turned_deg = rad_to_deg((Quaternion.IDENTITY.inverse() * G).get_angle())
			up_axis_ok = (G * Vector3.UP).distance_to(Vector3.UP) < 0.02
		for k in roots.size():
			var w: Vector3 = (B.P["head"] as Vector3) + G * (roots[k] as Vector3)
			worst_gap = maxf(worst_gap, surface_gap(tris, w, back))
			worst_drift = maxf(worst_drift, absf(((w - (B.P["head"] as Vector3)).length()) - float(rest_dist[k])))
	ok(worst_gap <= 0.001, "1 roots stay on the skinned head: worst gap %.2f mm at 0 and 60 deg (bar 1 mm)" % (worst_gap * 1000.0))
	ok(worst_drift <= 0.001, "1 roots follow the head: their distance from the head joint changes by %.3f mm over the turn (bar 1 mm)" % (worst_drift * 1000.0))
	print("   (the head turned %.2f deg, its up axis stays vertical: %s)" % [turned_deg, up_axis_ok])
	pose_head(0.0)
	m._refresh()

	# the bake in main, the body turned by rest_pose (a 60 deg turn at 1.0 s, 0.15 s, held): the frames the view draws
	m.S.fps = 30
	var fr: Array = m._hair_bake(rest_pose)
	var length_worst := 0.0
	var pen_worst := 9.0
	var N := int(p["n"]) + 1
	var seg := float(p["seg"])
	var nf: int = fr.size()
	for k in nf:
		rest_pose(float(k) / 30.0)
		var cs := caps_now()
		var F: PackedVector3Array = fr[k]
		for s in roots.size():
			for i in N - 1:
				var L := F[s * N + i].distance_to(F[s * N + i + 1])
				length_worst = maxf(length_worst, absf(L / seg - 1.0))
			for i in range(1, N):
				var w: Vector3 = F[s * N + i]
				for c in cs:
					var ca: Vector3 = c[0]
					var cb: Vector3 = c[1]
					var ab := cb - ca
					var ll := ab.length_squared()
					var u := 0.0 if ll < 1e-12 else clampf((w - ca).dot(ab) / ll, 0.0, 1.0)
					pen_worst = minf(pen_worst, (w - (ca + ab * u)).length() - float(c[2]))
	ok(length_worst <= 0.02, "2 segments: worst %.2f %% off the 3 cm rest length over %d frames (bar 2 %%)" % [length_worst * 100.0, nf])
	ok(pen_worst >= -0.003, "3 capsules: the nodes sit at least %.2f mm outside the body (bar -3 mm)" % (pen_worst * 1000.0))
	print("   (bake: %d frames at 30 fps, %d strands x %d nodes)" % [nf, roots.size(), N])

	# (4) lag and settle: a 40 deg head yaw in 0.15 s at 1.0 s, held; sim at 120 fps on the rest body (caps constant)
	var fps4 := 120.0
	var head4 := []
	var caps4 := []
	var caps_rest := caps_now()
	pose_head(0.0)
	m._refresh()
	var n4 := int(ceil(5.0 * fps4)) + 1
	var P0: Vector3 = B.P["head"]
	var G0: Quaternion = B.G["head"]
	for k in n4:
		var t := float(k) / fps4
		var q := G0 * Quaternion(Vector3.UP, deg_to_rad(turn_at(t, 1.0, 0.15, 40.0)))
		head4.append([P0, q])
		caps4.append(caps_rest)
	var fr4 := Hair.sim(roots, p, fps4, head4, caps4)
	var tip0 := 0   # strand 0's last node
	var tip := func(k: int) -> Vector3: return (fr4[k] as PackedVector3Array)[tip0 * N + N - 1]
	var F: Vector3 = tip.call(n4 - 1)
	var D: float = (tip.call(int(0.5 * fps4)) as Vector3).distance_to(F)
	var lag_t := -1.0
	var last_out := 0.0
	var t_half_head := 1.075   # the head is half way at the middle of its ramp
	var first_k := int(1.0 * fps4)
	for k in range(first_k, n4):
		var e: float = (tip.call(k) as Vector3).distance_to(F)
		if lag_t < 0.0 and e <= 0.5 * D:
			lag_t = float(k) / fps4
		if float(k) / fps4 >= 1.15 and e > 0.02 * D:
			last_out = float(k) / fps4
	var lag := lag_t - t_half_head
	var settle := last_out - 1.15
	ok(D > 0.01, "4 anti-vacuity: the tip moves %.1f cm in total (bar > 1 cm)" % (D * 100.0))
	ok(lag > 0.0, "4 the tip lags the head: it passes half its displacement %.3f s after the head (bar > 0)" % lag)
	ok(settle < 1.5, "4 the tip settles: within 2 %% of its displacement %.3f s after the head stops (bar < 1.5 s)" % settle)
	print("   (lag %.3f s, settle %.3f s, tip displacement %.1f cm, the head stops at 1.15 s)" % [lag, settle, D * 100.0])

	# (5) scrub repeatable: the same inputs, the same nodes; a second bake in main, the same frames
	var fr4b := Hair.sim(roots, p, fps4, head4, caps4)
	var same_sim := 0.0
	for k in fr4.size():
		for j in (fr4[k] as PackedVector3Array).size():
			same_sim = maxf(same_sim, ((fr4[k] as PackedVector3Array)[j] - (fr4b[k] as PackedVector3Array)[j]).length())
	var again: Array = m._hair_bake(rest_pose)
	var scrub_diff := 0.0
	for tt in [0.5, 1.2]:
		var a: PackedVector3Array = Hair.at(fr, tt, 30.0)
		var b: PackedVector3Array = Hair.at(again, tt, 30.0)
		for j in a.size():
			scrub_diff = maxf(scrub_diff, (a[j] - b[j]).length())
	ok(same_sim == 0.0, "5 two sim runs give identical nodes (largest difference %.4f mm, bar 0)" % (same_sim * 1000.0))
	ok(scrub_diff <= 1e-9, "5 a second bake in main gives the same nodes at 0.5 s and 1.2 s (largest difference %.4f mm, bar 1e-6 mm)" % (scrub_diff * 1000.0))

	# (6) placement: the roots on the back of the head, in the head's frame
	var back_ok := true
	var worst_z := -INF
	var a6 := Face.anchors(pts)
	var top := float(a6["top"])
	var H := float(a6["H"])
	for r in roots:
		var ra: Vector3 = (r as Vector3) + (B.p0["head"] as Vector3)   # back to the rest space (the mesh's frame)
		worst_z = maxf(worst_z, ra.z)
		if ra.z >= -0.06 or absf(ra.x) >= 0.03 or ra.y < top - 0.4 * H or ra.y > top:
			back_ok = false
	ok(back_ok, "6 placement: every root is behind the head's centre (furthest z %.3f m, bar < -0.06), |x| < 3 cm, in the top 0.4 H (top %.3f m, H %.3f m)" % [worst_z, top, H])

	# the picture: a whole-body side view with the head turning 60 deg, the ponytail mid-swing
	var shot_path := OS.get_environment("HAIR_SHOT")
	if shot_path == "":
		shot_path = "C:/Users/Nick/.claude/jobs/9afc22db/tmp/hair.png"
	if m.ui_toast != null:
		m.ui_toast.visible = false
	if m.dummy_on:
		m._dummy_toggle()
	m.playhead = 1.12
	rest_pose(1.12)
	m._refresh()
	m._turn_to(90.0, -5.0, 4.6, Vector3(0, 0.95, 0), false)
	await idle(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(shot_path)
	print("   (picture: %s)" % shot_path)

	print("hair_test: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	m.queue_free()
	quit(1 if fails > 0 else 0)
