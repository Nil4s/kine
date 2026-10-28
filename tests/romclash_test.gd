## godot --path . -s tests/romclash_test.gd     (ROADMAP_400 B24 range-of-motion clash + B25 clothes-safe clearance:
## scripts/rom_clash.gd + scripts/rom_clash_ui.gd; needs a window).
## THE PLATE: the body faces tagged biceps_l (B23's pick + clean) shrinkwrapped (B13, nearest) 4 mm out onto the rest skin,
## its weights the nearest body vertex's (B23), on the fighter as a part (B23's attach). THE ELBOW SCENE: the left elbow
## 0 -> 150 deg (held) -> 0, free limits, 30 Hz. Bars, written before measuring:
##  (1) CLASH AT FLEXION, NOT AT REST: a frame of maximum flexion (150 +- 0.01 deg) has >= 5 plate verts inside the body
##      deeper than 1 mm; no frame with the elbow at <= 1 deg has any
##  (2) WORST FRAME: list row 1 is a frame of maximum flexion; its words name the left elbow
##  (3) DEPTH, INDEPENDENT: at that frame the skeleton is posed there and the welded body (BaseBody.read) and the plate are
##      skinned by DqSkin.skin_surface (the app's CPU reference); inside / outside by our own signed ray crossings (every
##      body triangle, each closed part oriented by its own signed volume, 3 rays, majority) and the distance by brute
##      force to every body triangle (own closest-point code): the reported deepest depth is within 0.5 mm of this
##      measurement at that vertex, every vertex reported inside is inside here too, and the deepest here over every plate
##      vertex is within 0.5 mm of the reported deepest
##  (4) 2 CM CONTROL: a plate over the left forearm extensors shrinkwrapped 2 cm out, a scene swinging the left shoulder
##      0 -> 90 deg forward and back (elbow straight): no frame cuts in, every vertex's minimum clearance > 1 cm (all green),
##      and the instrument reads the gap (not "far"): >= 90 % of its verts stay 20 +- 1 mm off the skin in every frame.
##      INFO, not a bar: the same 2 cm plate over the biceps through the elbow scene is printed (the forearm reaches it)
##  (5) B25 = BRUTE FORCE: for 12 sample verts of the 4 mm plate (spread, with the deepest) over every frame of the elbow
##      scene, skinned here by our own linear blend from the sampled matrices and measured as in (3) (capped at CAP): the
##      minimum over frames equals the reported minimum clearance within 0.1 mm, and the reported frame of it holds that
##      minimum within 0.1 mm
##  (6) DETERMINISTIC + THE APP'S SKINNING: two runs give identical per-frame clearances and the same list; with the scene
##      set to dual quaternions (dq_skin 1) the posed plate the job measured at its worst frame equals DqSkin.skin_surface
##      at k = 1 within 0.01 mm, and differs from the linear-blend run's by > 0.1 mm somewhere (the switch reaches it)
##  (7) ROM TEST (built in): for the biceps plate the joints swept include the left elbow and left shoulder, not the right
##      elbow; the left elbow's bend ramp ends at 145 deg (F14's limit, body_limits.json); pose 0 (rest) is clear; of the
##      elbow ramp the 145 deg pose cuts in deepest (total)
##  (8) PART AGAINST PART: a closed B23 shell over biceps_l (4 mm gap, 3 mm thick) and a sheet shrinkwrapped 5.5 mm out
##      over the same tag: at rest >= 5 of the sheet's verts read inside the shell, none deeper than 1.6 mm (the wall is
##      4..7 mm out), every vert's inside / outside agrees with our own signed crossings of the shell (skinned here) and
##      the deepest with our own nearest-triangle distance within 0.5 mm; the frame's words name the shell. (Written first
##      as ">= 50 % inside": measured 12 of 54. B23 trims and bevels the shell's rim, so the sheet's edge runs out past
##      it; the bar now checks the reading against an independent one instead of a coverage guess.)
##  (9) UI STALL: the ROM test and the elbow scene through the app's own per-frame tick (main-thread slices + workers):
##      the longest main-thread tick <= 16 ms (window frame gaps printed, not barred: other agents load this machine)
## (10) PLACEMENT: after the ROM test through the command, clicking list row 1 stands the fighter in that pose and draws
##      the overlay; on the screenshot (the list hidden for it) >= 90 % of the offending verts in the free view are on red
##      pixels (r >= 0.6, g and b <= 0.35; each read a third of the way into its first red triangle: a vertex is on the
##      overlay's rim), and those pixels are not red with the overlay hidden; the overlay draws nothing else: at plate
##      verts more than 3 cm from every offending one and 4 px clear of every red triangle on screen <= 10 % are red
## (11) HEAT MAP: one copy per part, its vertex colours exactly heat(minimum clearance), the part hidden while it shows,
##      shown again when it goes; the lane holds the scene's clash span, "off" takes it away
## (12) reading changes nothing: the body's angles, the skin's weights, the undo list; after the panel closes the
##      skeleton's bone rotations are the body's again
extends SceneTree

var fails := 0
var m: Node
const OUT := "user://romclash.png"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func grab() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()


## closest point on triangle abc to p (Ericson 5.1.5, written again here: the instrument is not the op's code)
func closest(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var den := 1.0 / (va + vb + vc)
	return a + ab * (vb * den) + ac * (vc * den)


## the welded body's triangles and, per triangle, the sign that turns its winding outward (own union-find + volume)
func body_tris(k: KMesh) -> Array:
	var T := PackedInt32Array()
	for f in k.faces:
		var fp: PackedInt32Array = f
		for i in range(1, fp.size() - 1):
			T.append_array([fp[0], fp[i], fp[i + 1]])
	var up := PackedInt32Array()
	up.resize(k.verts.size())
	for i in up.size():
		up[i] = i
	var root_of := func(i: int) -> int:
		while up[i] != i:
			i = up[i]
		return i
	for t in range(0, T.size(), 3):
		var a: int = root_of.call(T[t])
		for c in [1, 2]:
			var b: int = root_of.call(T[t + c])
			if a != b:
				up[b] = a
	var vol := {}
	var cen := {}
	var cnt := {}
	for i in k.verts.size():
		var r: int = root_of.call(i)
		cen[r] = cen.get(r, Vector3.ZERO) + k.verts[i]
		cnt[r] = int(cnt.get(r, 0)) + 1
	for t in range(0, T.size(), 3):
		var r: int = root_of.call(T[t])
		var o: Vector3 = cen[r] / float(cnt[r])
		vol[r] = float(vol.get(r, 0.0)) + (k.verts[T[t]] - o).dot((k.verts[T[t + 1]] - o).cross(k.verts[T[t + 2]] - o))
	var sg := PackedFloat32Array()
	for t in range(0, T.size(), 3):
		sg.append(1.0 if float(vol[root_of.call(T[t])]) >= 0.0 else -1.0)
	return [T, sg]


## the triangles (of T over pts) with a corner within `pad` of p's box
func near_tris(pts: PackedVector3Array, T: PackedInt32Array, lo: Vector3, hi: Vector3) -> PackedInt32Array:
	var out := PackedInt32Array()
	for t in range(0, T.size(), 3):
		var a := pts[T[t]]
		var b := pts[T[t + 1]]
		var c := pts[T[t + 2]]
		var l := a.min(b).min(c)
		var h := a.max(b).max(c)
		if h.x >= lo.x and h.y >= lo.y and h.z >= lo.z and l.x <= hi.x and l.y <= hi.y and l.z <= hi.z:
			out.append(t / 3)
	return out


## ray vs triangle at mm (rayeps): Geometry3D.ray_intersects_triangle returns null when |edge1 . (dir x edge2)| < 1e-5, so a
## triangle with mm-sized edges given in metres is silently missed. The same ray on the x1000 triangle has 1e6 the determinant.
func ray_mm(o: Vector3, d: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Variant:
	var h: Variant = Geometry3D.ray_intersects_triangle(o * 1000.0, d, a * 1000.0, b * 1000.0, c * 1000.0)
	return null if h == null else (h as Vector3) / 1000.0


## signed distance of p to the posed body (pts): - inside (own signed crossings, every triangle, 3 rays majority),
## distance to the nearest triangle of `cand` (triangle numbers; brute force)
func signed_dist(p: Vector3, pts: PackedVector3Array, T: PackedInt32Array, sg: PackedFloat32Array, cand: PackedInt32Array) -> float:
	var bd := INF
	for t in cand:
		bd = minf(bd, p.distance_squared_to(closest(p, pts[T[t * 3]], pts[T[t * 3 + 1]], pts[T[t * 3 + 2]])))
	var votes := 0
	for d in [Vector3(0.31, 0.72, 0.62), Vector3(-0.64, -0.25, 0.73), Vector3(0.18, -0.55, -0.82)]:
		var dn := (d as Vector3).normalized()
		var w := 0
		for t in range(0, T.size(), 3):
			var a := pts[T[t]]
			var b := pts[T[t + 1]]
			var c := pts[T[t + 2]]
			if ray_mm(p, dn, a, b, c) != null:
				w += 1 if dn.dot((b - a).cross(c - a)) * sg[t / 3] > 0.0 else -1
		if w > 0:
			votes += 1
	return -sqrt(bd) if votes >= 2 else sqrt(bd)


func lbs(V: PackedVector3Array, IB: PackedInt32Array, IW: PackedFloat32Array, mats: Array, gt: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in V.size():
		var p := Vector3.ZERO
		for q in 4:
			if IW[i * 4 + q] > 0.0:
				p += (mats[IB[i * 4 + q]] as Transform3D) * V[i] * IW[i * 4 + q]
		out.append(gt * p)
	return out


func plate(k0: KMesh, off: float, tag: String) -> KMesh:
	var fs := ArmourFromBody.pick_faces(k0, ArmourFromBody.parse(tag))
	var cp := ArmourFromBody.copy_faces(k0, fs)
	var cl := ArmourFromBody.clean(cp[0], cp[1])
	var patch: KMesh = cl[0]
	var sw := KMeshShrinkwrap.build(k0)
	sw.wrap_mesh(patch, {"offset": off})
	ArmourFromBody.copy_weights(k0, patch, cl[1])
	return patch


func rest_all() -> void:
	for j in m.B.ang:
		m.B.ang[j] = Vector3.ZERO
	m.B.offset = Vector3.ZERO
	m.B.fk()


func scene_of(bone: String, keys: Array, nm: String) -> void:
	var B: Body = m.B
	var cards := []
	for kk in keys:
		rest_all()
		B.ang[bone] = Vector3(kk[0], 0, 0)
		B.fk()
		cards.append({"name": "%s %d" % [nm, kk[0]], "pose": B.to_dict(), "move": kk[1], "hold": kk[2]})
	m.S.from_dict({"scene": nm, "fps": 30, "free_limits": true, "cards": cards})
	m._rebuild_cards()
	rest_all()
	m.playhead = 0.0
	m._ps().apply(m.B, 0.0)
	m._refresh()


func elbow_scene() -> void:
	scene_of("lowerarm_l", [[0.0, -1.0, 0.3], [150.0, 1.0, 0.4], [0.0, 0.8, 0.2]], "zz_elbow")


func angles(bone: String, n: int) -> PackedFloat32Array:
	var G := Body.new()
	G.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var out := PackedFloat32Array()
	for f in n:
		m._ps().apply(G, float(f) / 30.0)
		out.append((G.ang[bone] as Vector3).x)
	return out


func job_of(how: String, parts: Array, o := {}) -> Array:
	var j := RomClash.new()
	var oo := {"parts": parts}
	oo.merge(o)
	var r := j.clash_now(m, how, oo)
	return [j, r]


## the command through the app's own tick; -> [longest tick ms, longest frame gap ms]
func run_ui(how: String) -> Array:
	m.clash_ui.run(how)
	var gap := 0.0
	var n := 0
	var last := Time.get_ticks_usec()
	while m.clash_ui.job.running() and n < 5000:
		await process_frame
		var now := Time.get_ticks_usec()
		gap = maxf(gap, float(now - last) / 1000.0)
		last = now
		n += 1
	var tk: Array = m.clash_ui.tick_ms
	print("  main-thread ms: start %.2f, longest tick %.2f over %d ticks (window frame gap %.1f ms)" % [tk[0], m.clash_ui.longest_tick(), tk.size(), gap])
	return [m.clash_ui.longest_tick(), gap]


func is_red(c: Color) -> bool:
	return c.r >= 0.6 and c.g <= 0.35 and c.b <= 0.35


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	await idle()
	var skel: Skeleton3D = m.skel
	var skin := BaseBody.skin_of(m)
	ok(skin != null and m.clash_ui != null, "the fighter has a skinned body and the app has the B24 panel object")
	var k0 := BaseBody.read(m)
	KMeshAnatomy.seed_tags(k0, skel, (m.pieces.values()[0] as MeshInstance3D).global_transform)   # A19's tags (B23 picks faces by them)
	var bt := body_tris(k0)
	var BT: PackedInt32Array = bt[0]
	var BS: PackedFloat32Array = bt[1]
	var binf := RomClash.infl4(k0, skin, skel)
	var p4 := plate(k0, 0.004, "biceps_l")
	var mi4 := ArmourFromBody.attach(m, p4, "biceps_l")
	ok(mi4 != null and p4.verts.size() > 20, "the 4 mm biceps plate is a part of the fighter (%d verts)" % p4.verts.size())
	var pinf := RomClash.infl4(p4, skin, skel)

	# ---- (1) (2) the elbow scene
	elbow_scene()
	var jr := job_of("scene", [mi4])
	var J: RomClash = jr[0]
	var r: Dictionary = jr[1]
	var nf: int = r["frames"].size()
	var ang := angles("lowerarm_l", nf)
	var amax := 0.0
	for a in ang:
		amax = maxf(amax, a)
	print("elbow scene: %d frames in %d ms on the workers; max elbow %.2f deg" % [nf, r["ms"], amax])
	for w in r["worst"]:
		print("  LIST: %s (%d verts, total %.1f mm)" % [w["text"], w["n"], float(w["sev"]) * 1000.0])
	var deep_max := 0
	var rest_bad := 0
	for f in nf:
		var clr: PackedFloat32Array = r["per"][f]["clr"][0]
		var n1 := 0
		var nin := 0
		for x in clr:
			if x < -0.001:
				n1 += 1
			if x < -RomClash.EPS_IN:
				nin += 1
		if absf(ang[f] - amax) <= 0.01:
			deep_max = maxi(deep_max, n1)
		if ang[f] <= 1.0 and nin > 0:
			rest_bad += 1
	ok(absf(amax - 150.0) <= 0.01 and deep_max >= 5, "(1) at maximum flexion (%.2f deg) %d plate verts are inside the body deeper than 1 mm (>= 5)" % [amax, deep_max])
	ok(rest_bad == 0, "(1) no frame with the elbow at <= 1 deg has a vertex inside (%d have)" % rest_bad)
	var w1: Dictionary = r["worst"][0] if not r["worst"].is_empty() else {"frame": 0, "text": "", "v": -1, "deep": 0.0, "part": -1}
	var wf: int = w1["frame"]
	ok(absf(ang[wf] - amax) <= 0.01 and "left elbow" in str(w1["text"]), "(2) WORST FRAME %d is at maximum flexion (%.2f deg) and names the left elbow: %s" % [wf, ang[wf], w1["text"]])

	# ---- (3) the depth, measured independently at that frame
	var Mw: Array = J._d["frames"][wf][0]
	var gt: Transform3D = skel.global_transform
	var gi := gt.affine_inverse()
	var smats := []
	for x in Mw:
		smats.append(gi * (x as Transform3D))
	# the skeleton posed at that frame: the app's own bind matrices (DqSkin.bind_mats) must be the sampled ones
	var Gw := Body.new()
	Gw.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	m._ps().apply(Gw, float(wf) / 30.0)
	Overlays.pose_skeleton(skel, m.bone_idx, Gw)
	var bm := DqSkin.bind_mats(skel, skin)
	Overlays.pose_skeleton(skel, m.bone_idx, m.B)
	var mdiff := 0.0
	for q in bm.size():
		for c in 4:
			mdiff = maxf(mdiff, ((bm[q] as Transform3D).basis[c] if c < 3 else (bm[q] as Transform3D).origin).distance_to(((smats[q] as Transform3D).basis[c] if c < 3 else (smats[q] as Transform3D).origin)))
	ok(mdiff < 1e-4, "(3) INSTRUMENT the sampled frame is the scene's pose: its matrices equal DqSkin.bind_mats with the skeleton posed there (off %.6f m)" % mdiff)
	var k_now := float(m.S.dq_skin)
	var bodyp := DqSkin.skin_surface(k0.verts, binf[0], binf[1], bm, k_now)
	var platep := DqSkin.skin_surface(p4.verts, pinf[0], pinf[1], bm, k_now)
	for i in bodyp.size():
		bodyp[i] = gt * bodyp[i]
	for i in platep.size():
		platep[i] = gt * platep[i]
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for p in platep:
		lo = lo.min(p)
		hi = hi.max(p)
	var cand := near_tris(bodyp, BT, lo - Vector3.ONE * 0.06, hi + Vector3.ONE * 0.06)
	var rep_clr: PackedFloat32Array = r["per"][wf]["clr"][0]
	var indep := PackedFloat32Array()
	for i in platep.size():
		indep.append(signed_dist(platep[i], bodyp, BT, BS, cand))
	var wv: int = w1["v"]
	var agree := 0
	var nrep := 0
	var imax := 0.0
	for i in platep.size():
		imax = maxf(imax, -indep[i])
		if rep_clr[i] < -RomClash.EPS_IN:
			nrep += 1
			if indep[i] < 0.0:
				agree += 1
	print("  frame %d vertex %d: reported %.3f mm, measured here %.3f mm; deepest here %.3f mm, reported %.3f mm" % [wf, wv, -rep_clr[wv] * 1000.0 if wv >= 0 else 0.0, -indep[wv] * 1000.0 if wv >= 0 else 0.0, imax * 1000.0, float(w1["deep"]) * 1000.0])
	ok(wv >= 0 and absf(rep_clr[wv] - indep[wv]) <= 0.0005, "(3) DEPTH the reported deepest (%.2f mm) matches the independent nearest-triangle measurement (%.2f mm) within 0.5 mm" % [-rep_clr[wv] * 1000.0 if wv >= 0 else 0.0, -indep[wv] * 1000.0 if wv >= 0 else 0.0])
	ok(nrep > 0 and agree == nrep, "(3) every vertex reported inside (%d) is inside by the independent crossings too (%d)" % [nrep, agree])
	ok(absf(imax - float(w1["deep"])) <= 0.0005, "(3) the deepest over every plate vertex here (%.2f mm) is the reported deepest (%.2f mm) within 0.5 mm" % [imax * 1000.0, float(w1["deep"]) * 1000.0])

	# ---- (5) B25 against brute force
	var nv := p4.verts.size()
	var samples := PackedInt32Array()
	for s in 11:
		samples.append(roundi(float(s) * float(nv - 1) / 10.0))
	samples.append(wv)
	var pd: Dictionary = r["parts"][0]
	var minc: PackedFloat32Array = pd["minc"]
	var minf: PackedInt32Array = pd["minf"]
	var bmin := PackedFloat32Array()
	bmin.resize(samples.size())
	bmin.fill(INF)
	var atf := []   # per sample, per frame
	for s in samples.size():
		atf.append([])
	var t5 := Time.get_ticks_msec()
	for f in nf:
		var mats := []
		for x in J._d["frames"][f][0]:
			mats.append(gi * (x as Transform3D))
		var bp := lbs(k0.verts, binf[0], binf[1], mats, gt)
		var pp := lbs(p4.verts, pinf[0], pinf[1], mats, gt)
		var l2 := Vector3.INF
		var h2 := -Vector3.INF
		for s in samples:
			l2 = l2.min(pp[s])
			h2 = h2.max(pp[s])
		var cd := near_tris(bp, BT, l2 - Vector3.ONE * (RomClash.CAP + 0.01), h2 + Vector3.ONE * (RomClash.CAP + 0.01))
		for s in samples.size():
			var v := minf(signed_dist(pp[samples[s]], bp, BT, BS, cd), RomClash.CAP)
			(atf[s] as Array).append(v)
			bmin[s] = minf(bmin[s], v)
	var worst5 := 0.0
	var worstf := 0.0
	for s in samples.size():
		var v := samples[s]
		worst5 = maxf(worst5, absf(bmin[s] - minc[v]))
		worstf = maxf(worstf, absf(float((atf[s] as Array)[minf[v]]) - bmin[s]))
	print("  B25 brute force: %d verts x %d frames in %d ms; worst |min - reported| %.4f mm, worst at the reported frame %.4f mm" % [samples.size(), nf, Time.get_ticks_msec() - t5, worst5 * 1000.0, worstf * 1000.0])
	ok(worst5 <= 0.0001, "(5) B25 the minimum clearance of %d sample verts equals the brute-force minimum over all %d frames within 0.1 mm (worst %.4f mm)" % [samples.size(), nf, worst5 * 1000.0])
	ok(worstf <= 0.0001, "(5) B25 the reported frame of each minimum holds it within 0.1 mm (worst %.4f mm)" % (worstf * 1000.0))

	# ---- (6) deterministic; the app's skinning method
	var r2: Dictionary = job_of("scene", [mi4])[1]
	var same: bool = r2["frames"].size() == nf
	for f in nf:
		if same:
			same = r2["per"][f]["clr"][0] == r["per"][f]["clr"][0] and r2["per"][f]["pv"][0] == r["per"][f]["pv"][0]
	var t1: Array = r["worst"].map(func(x): return x["text"])
	var t2: Array = r2["worst"].map(func(x): return x["text"])
	ok(same and t1 == t2, "(6) DETERMINISTIC two runs: every frame's clearances identical, the same list of %d" % t1.size())
	m.S.dq_skin = 1.0
	var jd := job_of("scene", [mi4])
	var rd: Dictionary = jd[1]
	m.S.dq_skin = 0.0
	var wfd: int = rd["worst"][0]["frame"] if not rd["worst"].is_empty() else wf
	var dm := []
	for x in (jd[0] as RomClash)._d["frames"][wfd][0]:
		dm.append(gi * (x as Transform3D))
	var ref := DqSkin.skin_surface(p4.verts, pinf[0], pinf[1], dm, 1.0)
	var lb := lbs(p4.verts, pinf[0], pinf[1], dm, gt)
	var dd := 0.0
	var dl := 0.0
	var posd: PackedVector3Array = rd["posed"][wfd][0] if rd["posed"].has(wfd) else PackedVector3Array()
	for i in mini(posd.size(), ref.size()):
		dd = maxf(dd, posd[i].distance_to(gt * ref[i]))
		dl = maxf(dl, posd[i].distance_to(lb[i]))
	print("  DQS run: worst %s" % (rd["worst"][0]["text"] if not rd["worst"].is_empty() else "none"))
	ok(posd.size() == nv and dd <= 0.00001, "(6) DQS the plate the job measured at frame %d is DqSkin.skin_surface at k = 1 (off %.5f mm)" % [wfd, dd * 1000.0])
	ok(dl > 0.0001, "(6) DQS differs from linear blend there by %.2f mm (> 0.1: the switch reaches the measurement)" % (dl * 1000.0))

	# ---- (7) the built-in ROM test
	var jrm := job_of("rom", [mi4])
	var JR: RomClash = jrm[0]
	var rr: Dictionary = jrm[1]
	var poses: Array = JR._d["poses"]
	var swept := {}
	var elbow_end := 0.0
	var elbow_frames := []
	for f in poses.size():
		swept[String(poses[f]["entry"])] = true
		if poses[f]["entry"] == "lowerarm_l" and poses[f]["axis"] == "bend":
			elbow_end = maxf(elbow_end, float(poses[f]["deg"]))
			elbow_frames.append(f)
	print("ROM test: %d poses over %s in %d ms" % [poses.size(), ", ".join(PackedStringArray(swept.keys())), rr["ms"]])
	for w in rr["worst"]:
		print("  ROM LIST: %s (%d verts)" % [w["text"], w["n"]])
	ok(swept.has("lowerarm_l") and swept.has("upperarm_l") and not swept.has("lowerarm_r"), "(7) the joints swept for the biceps plate include the left elbow and shoulder, not the right elbow")
	ok(absf(elbow_end - 145.0) <= 0.01, "(7) the left elbow's bend ramp ends at %.1f deg (F14's limit 145)" % elbow_end)
	ok(float(rr["frames"][0]["sev"]) <= RomClash.EPS_IN, "(7) pose 0 (rest) is clear")
	var ebest := -1
	for f in elbow_frames:
		if ebest < 0 or float(rr["frames"][f]["sev"]) > float(rr["frames"][ebest]["sev"]):
			ebest = f
	ok(ebest >= 0 and absf(float(poses[ebest]["deg"]) - 145.0) <= 0.01 and float(rr["frames"][ebest]["sev"]) > 0.0, "(7) of the elbow ramp the %s pose cuts in deepest (%s)" % [poses[ebest]["label"] if ebest >= 0 else "?", rr["frames"][ebest]["text"] if ebest >= 0 else ""])

	# ---- (4) the 2 cm control, and the info
	var p20 := plate(k0, 0.02, "forearm_extensors_l")
	var mi20 := ArmourFromBody.attach(m, p20, "forearm_extensors_l 2 cm")
	scene_of("upperarm_l", [[0.0, -1.0, 0.3], [90.0, 1.0, 0.3], [0.0, 1.0, 0.2]], "zz_shoulder")
	var r20: Dictionary = job_of("scene", [mi20])[1]
	var pd20: Dictionary = r20["parts"][0]
	var in20 := 0
	for f in r20["frames"]:
		if float(f["sev"]) > RomClash.EPS_IN:
			in20 += 1
	var band_ok := true
	var band_lo := 1.0
	for f in r20["frames"].size():
		var c: PackedFloat32Array = r20["per"][f]["clr"][0]
		var nb := 0
		for x in c:
			if absf(x - 0.02) <= 0.001:
				nb += 1
		band_lo = minf(band_lo, float(nb) / float(c.size()))
		band_ok = band_ok and float(nb) / float(c.size()) >= 0.9
	ok(in20 == 0, "(4) 2 CM the forearm plate 2 cm off cuts in on no frame of the shoulder swing (%d frames do)" % in20)
	ok(int(pd20["red"]) == 0 and int(pd20["yellow"]) == 0 and float(pd20["low"]) > RomClash.WARN, "(4) 2 CM every one of its %d verts stays green (closest %.2f mm > 10)" % [p20.verts.size(), float(pd20["low"]) * 1000.0])
	ok(band_ok, "(4) INSTRUMENT >= 90 %% of its verts read 20 +- 1 mm off the skin in every frame (worst frame: %.0f %%)" % (band_lo * 100.0))
	var pb20 := plate(k0, 0.02, "biceps_l")
	var mib20 := ArmourFromBody.attach(m, pb20, "biceps_l 2 cm")
	elbow_scene()
	var rb20: Dictionary = job_of("scene", [mib20])[1]
	print("INFO the 2 cm BICEPS plate through the elbow scene: %s; %s" % [rb20["worst"][0]["text"] if not rb20["worst"].is_empty() else "clear", "; ".join(PackedStringArray(rb20["warn"]))])

	# ---- (8) part against part
	var gx0 := (m.pieces.values()[0] as MeshInstance3D).global_transform
	var shell := ArmourFromBody.build(k0, skel, gx0, "biceps_l")
	if shell["ok"]:
		var mis := ArmourFromBody.attach(m, shell["mesh"], "biceps_l shell")
		var p55 := plate(k0, 0.0055, "biceps_l")
		var mi55 := ArmourFromBody.attach(m, p55, "biceps_l 5.5 mm")
		var j8 := job_of("scene", [mi55, mis])
		var r8: Dictionary = j8[1]
		var pv: PackedFloat32Array = r8["per"][0]["pv"][0]
		var nin := 0
		var dmax := 0.0
		for x in pv:
			if x > RomClash.EPS_IN:
				nin += 1
				dmax = maxf(dmax, x)
		print("  part vs part at rest: %d of %d sheet verts inside the shell, deepest %.2f mm: %s" % [nin, pv.size(), dmax * 1000.0, r8["frames"][0]["text"]])
		# the independent reading: both skinned here (own linear blend, frame 0's matrices), the shell's own signed crossings
		var m0 := []
		for x in (j8[0] as RomClash)._d["frames"][0][0]:
			m0.append(gi * (x as Transform3D))
		var sk_shell: KMesh = shell["mesh"]
		var shinf := RomClash.infl4(sk_shell, skin, skel)
		var s55 := RomClash.infl4(p55, skin, skel)
		var shp := lbs(sk_shell.verts, shinf[0], shinf[1], m0, gt)
		var shp55 := lbs(p55.verts, s55[0], s55[1], m0, gt)
		var stt := body_tris(sk_shell)
		var allt := PackedInt32Array()
		for t in (stt[0] as PackedInt32Array).size() / 3:
			allt.append(t)
		var agree8 := 0
		var own_in := 0
		var own_deep := 0.0
		for i in shp55.size():
			var sd := signed_dist(shp55[i], shp, stt[0], stt[1], allt)
			var mine := sd < 0.0
			if mine:
				own_in += 1
				own_deep = maxf(own_deep, -sd)
			if mine == (pv[i] > RomClash.EPS_IN):
				agree8 += 1
		print("  part vs part, measured here: %d inside the shell, deepest %.2f mm; %d of %d verts agree" % [own_in, own_deep * 1000.0, agree8, pv.size()])
		ok(nin >= 5 and agree8 == pv.size() and absf(own_deep - dmax) <= 0.0005 and dmax <= 0.0016, "(8) PART vs PART %d of %d verts of the 5.5 mm sheet read inside the 4..7 mm shell, each vert agreeing with our own crossings (%d agree), deepest %.2f mm (here %.2f; <= 1.6)" % [nin, pv.size(), agree8, dmax * 1000.0, own_deep * 1000.0])
		ok("shell" in str(r8["frames"][0]["text"]), "(8) the frame's words name the shell: %s" % r8["frames"][0]["text"])
	else:
		ok(false, "(8) the B23 shell: %s" % shell["error"])

	# ---- (9) (10) (11) (12) through the app
	ArmourFromBody.restore(m, [mi4])   # the fighter wears the 4 mm plate alone now
	await idle(2)
	elbow_scene()
	await idle(2)
	var ang0: Dictionary = m.B.ang.duplicate()
	var w0 := []
	for s in m.wp["surfs"]:
		w0.append([(s["bones"] as PackedInt32Array).duplicate(), (s["w"] as PackedFloat32Array).duplicate()])
	var u0: int = m.undo.size()
	var se: Array = await run_ui("scene")
	ok(se[0] <= 16.0, "(9) UI STALL elbow scene: longest main-thread tick %.2f ms (<= 16)" % se[0])
	await idle(3)
	var tl: Timeline = m.ui_timeline
	ok(tl.ph == m.clash_ui.lane and (m.clash_ui.lane as Array).size() == 1, "(11) the timeline's red lane holds the scene's clash span (%d)" % (m.clash_ui.lane as Array).size())
	m.clash_ui.clear()
	ok(tl.ph.is_empty(), "(11) 'off' takes the lane away")
	var sr: Array = await run_ui("rom")
	ok(sr[0] <= 16.0, "(9) UI STALL ROM test: longest main-thread tick %.2f ms (<= 16)" % sr[0])
	await idle(3)
	var rres: Dictionary = m.clash_ui.res
	var b1: Button = m.ui_find_list.find_child("romclash_1", true, false)
	ok(m.ui_find.visible and b1 != null, "(10) the panel lists the worst poses (row 1: %s)" % (b1.text if b1 != null else "none"))
	var heat_lbl: Label = m.ui_find_list.find_child("romclash_part_1", true, false)
	ok(heat_lbl != null and "closest" in heat_lbl.text, "(11) the panel has the part's clearance line: %s" % (heat_lbl.text if heat_lbl != null else "none"))
	if b1 != null:
		b1.pressed.emit()
		await idle(3)
		var f1: int = rres["worst"][0]["frame"]
		ok(m.clash_ui.overlay != null and m.clash_ui.shown == f1, "(10) clicking row 1 shows pose %d with its overlay" % f1)
		var off: Dictionary = m.clash_ui.offending(f1)[0]
		var pp: PackedVector3Array = rres["posed"][f1][0]
		var cen := Vector3.ZERO
		for i in off:
			cen += pp[i]
		cen /= maxf(1.0, float(off.size()))
		m._turn_to(25.0, -15.0, 1.4, cen, false)
		await idle(6)
		m.ui_find.visible = false   # the list sits over the free view's middle: away for the two pictures
		var on := await grab()
		m.clash_ui.overlay.visible = false
		var offimg := await grab()
		m.clash_ui.overlay.visible = true
		m.ui_find.visible = true
		var cam: Camera3D = m.cam
		var vs: Vector2 = m.get_viewport().get_visible_rect().size
		var fr := Rect2(Vector2(m.lw(), m.TOP_H), Vector2(vs.x - m.rw() - m.lw(), vs.y - m.bottom_h - m.LINE_H - m.TOP_H))
		var n_on := 0
		var n_red := 0
		var n_was := 0
		var n_far := 0
		var n_far_red := 0
		var mg: Transform3D = m.global_transform
		var PT: PackedInt32Array = rres["parts"][0]["T"]
		# the overlay's triangles on screen (a vertex sits on their rim: each offending vert is read a third of the way into
		# its first red triangle, so a pixel on the rim's wrong side cannot decide it)
		var tris2 := []
		var into := {}
		for t in range(0, PT.size(), 3):
			if off.has(PT[t]) or off.has(PT[t + 1]) or off.has(PT[t + 2]):
				var c3 := (pp[PT[t]] + pp[PT[t + 1]] + pp[PT[t + 2]]) / 3.0
				var q := PackedVector2Array()
				for c in 3:
					q.append(cam.unproject_position(mg * pp[PT[t + c]]))
					if off.has(PT[t + c]) and not into.has(PT[t + c]):
						into[PT[t + c]] = pp[PT[t + c]].lerp(c3, 0.34)
				tris2.append(q)
		for i in pp.size():
			var w: Vector3 = mg * (into[i] if into.has(i) else pp[i])
			if cam.is_position_behind(w):
				continue
			var sp := cam.unproject_position(w)
			if not fr.has_point(sp):
				continue
			var pi := Vector2i(sp)
			if off.has(i):
				n_on += 1
				if is_red(on.get_pixelv(pi)):
					n_red += 1
				if is_red(offimg.get_pixelv(pi)):
					n_was += 1
			else:
				# far: 3 cm from every offending vert and, on screen, 4 px clear of every red triangle (the overlay draws
				# through the body, so a vert behind it on screen would be red rightly)
				var far := true
				for j in off:
					if pp[i].distance_to(pp[j]) <= 0.03:
						far = false
						break
				for q in tris2:
					if not far:
						break
					var qq: PackedVector2Array = q
					if Geometry2D.is_point_in_polygon(sp, qq):
						far = false
					for e in 3:
						if Geometry2D.get_closest_point_to_segment(sp, qq[e], qq[(e + 1) % 3]).distance_to(sp) < 4.0:
							far = false
				if far:
					n_far += 1
					if is_red(on.get_pixelv(pi)):
						n_far_red += 1
		print("  overlay: %d offending verts on screen, %d on red pixels (%d red without the overlay); %d far verts, %d red" % [n_on, n_red, n_was, n_far, n_far_red])
		ok(n_on >= 5 and n_red * 10 >= n_on * 9, "(10) PLACEMENT %d of %d offending verts on screen are on red pixels (>= 90 %%)" % [n_red, n_on])
		ok(n_was * 10 <= n_on, "(10) PLACEMENT those pixels are not red without the overlay (%d are)" % n_was)
		ok(n_far == 0 or n_far_red * 10 <= n_far, "(10) the overlay draws nothing else: %d of %d far verts red (<= 10 %%)" % [n_far_red, n_far])
		on.save_png(OUT)
		print("screenshot: ", ProjectSettings.globalize_path(OUT))
	# (11) the heat map
	m.clash_ui.toggle_heat()
	await idle(2)
	var hm: Array = m.clash_ui.heat
	var col_ok := hm.size() == 1
	if col_ok:
		var cols: PackedColorArray = ((hm[0] as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var mc: PackedFloat32Array = rres["parts"][0]["minc"]
		col_ok = cols.size() == mc.size()
		for i in mini(cols.size(), mc.size()):
			var hc := RomClash.heat(mc[i])
			col_ok = col_ok and absf(cols[i].r - hc.r) <= 0.005 and absf(cols[i].g - hc.g) <= 0.005 and absf(cols[i].b - hc.b) <= 0.005
	print("  heat: %d copies, part visible %s" % [hm.size(), mi4.visible])
	ok(col_ok and not mi4.visible, "(11) HEAT MAP one copy per part, colours = heat(minimum clearance) per vertex, the part hidden under it")
	m.clash_ui.toggle_heat()
	ok(m.clash_ui.heat.is_empty() and mi4.visible, "(11) heat map off: the part shows again")
	# (12)
	m._close_findings()
	await idle(2)
	var rot_ok := true
	var ref_sk := Skeleton3D.new()
	var rot0 := []
	for b in skel.get_bone_count():
		rot0.append(skel.get_bone_pose_rotation(b))
	Overlays.pose_skeleton(skel, m.bone_idx, m.B)
	for b in skel.get_bone_count():
		rot_ok = rot_ok and (skel.get_bone_pose_rotation(b) as Quaternion).is_equal_approx(rot0[b])
	ref_sk.free()
	ok(rot_ok and m.clash_ui.overlay == null, "(12) after the panel closes the skeleton is the body's pose again and the overlay is gone")
	var same_w := true
	for si in m.wp["surfs"].size():
		var s: Dictionary = m.wp["surfs"][si]
		same_w = same_w and s["bones"] == w0[si][0] and s["w"] == w0[si][1]
	ok(m.B.ang == ang0 and same_w and m.undo.size() == u0, "(12) body angles, the skin's weights and the undo list unchanged by the checks")
	m.clash_ui.clear()
	print("ROMCLASH RESULT: ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(fails)
