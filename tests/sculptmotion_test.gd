## godot --path . -s tests/sculptmotion_test.gd     (ROADMAP_400 C23; boots main.tscn: needs a window / GPU)
## Sculpt checked in motion: after a body-sculpt stroke (C19 pose sculpt, SculptPose.PoseUndo.commit) the 8 frames of the open
## scene where the STROKED REGION deforms most play as thumbnails (scripts/sculpt_motion.gd + sculpt_motion_ui.gd).
## THE METRIC (stated before any code): frames f = 0 .. ceil(length * fps) at t = min(f / fps, length), the scene applied on a
## body of its own, the skeleton posed, the rest mesh (as just sculpted) skinned (the scene's dq_skin blend). The REGION R =
## the rest vertices the stroke moved. E = the mesh edges with BOTH ends in R (rest length > 1 mm).
##   score(f) = mean over E of | ln( posed edge length / rest edge length ) |      (0 = rigid, bigger = more stretch or squash)
## chosen = the 8 frames with the highest score (ties: the lower frame), shown in time order; fewer than 8 frames: all of them.
## Bars, written BEFORE the implementation:
##   0 INSTRUMENT  the scene has >= 90 frames; the elbow region has >= 40 vertices and >= 40 edges, the knee region too; the elbow
##                 bends >= 100 deg in some frame (read back from the scene) and the knee too; the elbow region's score range
##                 max/min > 1.5; the 8th and 9th best elbow scores differ by > 1e-5 (the top-8 is not a tie-break)
##   1 TOP-8 ELBOW the module's region == the vertices the stroke moved in rest (the test diffs rest before / after); its 8 chosen
##                 frames are EXACTLY the top-8 of the test's own score (own edge list from the faces, own LBS loop from the bind
##                 matrices, own frame loop); every module score within 1e-5 of the test's; >= 6 of the 8 have the elbow bent > 60 deg
##   2 SHIN        a stroke on the knee / shin region picks 8 frames that are EXACTLY the test's top-8 for that region, share <= 2
##                 frames with the elbow stroke's, and >= 6 of them have the knee bent > 60 deg
##   3 THUMBS      8 images (160 x 160) per stroke, each non-empty (> 5 pct of its pixels are not the background, colour spread
##                 > 0.02), >= 5 of the 8 pairwise different (the bend shows); the region is drawn red: red pixels exist in every
##                 image; the region's projected bbox (the test projects its own skinned region vertices with the thumbnail's
##                 stored camera, orthographic) lies inside the image with a 4 px margin, and the red pixels' bbox is within 12 px of
##                 it on every side
##   4 TIMING      stroke -> all 8 thumbnails on the strip <= 4.0 s (measured under the machine's load, printed); the main thread's
##                 longest slice of the job (the module's own clock) <= 50 ms AND the longest frame gap the test sees <= 120 ms
##                 (printed, the load of other lanes counts); the strip's second stroke supersedes a running first (one result)
##   5 FEW FRAMES  a 3-frame scene: the chosen frames are all 3 in order, 3 thumbnails
##   6 PLANTED FAKES  the same checker FAILS (a) a random frame choice (seeded), (b) the shin's frames given for the elbow stroke
##   7 tools/run_all.sh has the sculptmotion line
extends SceneTree

var fails := 0
var m: Node
var skin: Skin
var sp: SculptPose
var spu: SculptPoseUI
var R: KMesh
var G: Body
var skc: Skeleton3D
var fps := 30
var NF := 0

func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func world_of(bone: String) -> Vector3:
	var sk: Skeleton3D = m.skel
	var b := sk.find_bone(bone)
	var t := sk.get_bone_pose(b)
	var p := sk.get_bone_parent(b)
	while p >= 0:
		t = sk.get_bone_pose(p) * t
		p = sk.get_bone_parent(p)
	return t.origin   # skeleton space: the space the rest mesh lives in


## the test's own edge list of the region: faces -> undirected edges with both ends in the region, rest length > 1 mm
func region_edges(verts: PackedVector3Array, region: Dictionary) -> Array:
	var seen := {}
	var out := []
	for f in R.faces:
		var n: int = f.size()
		for i in n:
			var a: int = f[i]
			var b: int = f[(i + 1) % n]
			if not region.has(a) or not region.has(b):
				continue
			var key := mini(a, b) * 1000003 + maxi(a, b)
			if seen.has(key):
				continue
			seen[key] = true
			if verts[a].distance_to(verts[b]) > 0.001:
				out.append(Vector2i(mini(a, b), maxi(a, b)))
	return out


## the test's own LBS of one vertex from the bind matrices
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


## the test's score of every frame for a region
func my_scores(region: Dictionary) -> PackedFloat64Array:
	var verts := R.verts
	var edges := region_edges(verts, region)
	var out := PackedFloat64Array()
	for f in NF:
		var mats := mats_at(f)
		var cache := {}
		var s := 0.0
		for e in edges:
			for v in [e.x, e.y]:
				if not cache.has(v):
					cache[v] = lbs(verts[v], v, mats)
			s += absf(log(cache[e.x].distance_to(cache[e.y]) / verts[e.x].distance_to(verts[e.y])))
		out.append(s / maxf(1.0, edges.size()))
	return out


func top8(sc: PackedFloat64Array) -> Array:
	var ix := range(sc.size())
	ix.sort_custom(func(a, b): return sc[a] > sc[b] or (sc[a] == sc[b] and a < b))
	return ix.slice(0, mini(8, ix.size()))


## the checker the planted fakes go through: `frames` is exactly the top-8 of `sc` (as a set)
func is_top8(frames: Array, sc: PackedFloat64Array) -> bool:
	var want := top8(sc)
	want.sort()
	var got := frames.duplicate()
	got.sort()
	return got == want


func bend_at(f: int, joint: String) -> float:
	m._ps().apply(G, minf(float(f) / fps, m._ps().length()))
	return (G.ang[joint] as Vector3).x


func shared(a: Array, b: Array) -> int:
	var n := 0
	for x in a:
		if b.has(x):
			n += 1
	return n


## the cards: rest, elbow 130, rest, knee 120, rest, elbow 70 + knee 60 (both), rest; different move times so no two passes tie
func build_scene() -> void:
	var B: Body = m.B
	var cards := []
	var keys := [[0.0, 0.0, -1.0, 0.1], [130.0, 0.0, 0.7, 0.0], [0.0, 0.0, 0.9, 0.0], [0.0, 120.0, 1.1, 0.0],
		[0.0, 0.0, 0.8, 0.0], [70.0, 60.0, 0.6, 0.0], [0.0, 0.0, 1.3, 0.1]]
	for k in keys:
		for j in B.ang:
			B.ang[j] = Vector3.ZERO
		B.offset = Vector3.ZERO
		B.ang["lowerarm_r"] = Vector3(k[0], 0, 0)
		B.ang["calf_r"] = Vector3(k[1], 0, 0)
		B.fk()
		cards.append({"name": "sm %d/%d" % [k[0], k[1]], "pose": B.to_dict(), "move": k[2], "hold": k[3]})
	m.S.from_dict({"scene": "zz_sculptmotion", "fps": fps, "free_limits": true, "dq_skin": 0.0, "cards": cards})
	m._rebuild_cards()
	for j in B.ang:
		B.ang[j] = Vector3.ZERO
	B.fk()
	m._refresh()


func few_scene() -> void:
	var B: Body = m.B
	var cards := []
	for a in [0.0, 100.0]:
		for j in B.ang:
			B.ang[j] = Vector3.ZERO
		B.ang["lowerarm_r"] = Vector3(a, 0, 0)
		B.fk()
		cards.append({"name": "few %d" % a, "pose": B.to_dict(), "move": 0.2, "hold": 0.0})
	m.S.from_dict({"scene": "zz_sculptmotion_few", "fps": 10, "free_limits": true, "dq_skin": 0.0, "cards": cards})
	m._rebuild_cards()


## a stroke through the real hook: the posed vertices of `verts` move 1 cm, PoseUndo.commit maps them to rest
func stroke(verts: Array) -> void:
	var before := R.verts.duplicate()
	spu.undo.begin(sp.posed)
	var pv := sp.posed.verts
	for v in verts:
		pv[v] += Vector3(0.0, 0.0, 0.012)
	sp.posed.verts = pv
	spu.undo.commit("sculptmotion test stroke")
	var moved := {}
	for i in R.verts.size():
		if R.verts[i] != before[i]:
			moved[i] = true
	last_moved = moved


var last_moved := {}
var gap_max := 0.0


## wait for the strip: -> ms from the stroke to the last thumbnail
func wait_strip(ui: Node, t0: int) -> float:
	var last := Time.get_ticks_usec()
	gap_max = 0.0
	var n := 0
	while ui.busy and n < 2000:
		await process_frame
		var now := Time.get_ticks_usec()
		gap_max = maxf(gap_max, float(now - last) / 1000.0)
		last = now
		n += 1
	return float(Time.get_ticks_usec() - t0) / 1000.0


func region_near(c: Vector3, rad: float) -> Array:
	var out := []
	for i in R.verts.size():
		if sp.posed.verts[i].distance_to(c) < rad:
			out.append(i)
	return out


func px_of(thumb: Dictionary, p: Vector3) -> Vector2:
	var l: Vector3 = (thumb["cam_xf"] as Transform3D).affine_inverse() * p
	var sz: float = thumb["cam_size"]
	var W: float = (thumb["image"] as Image).get_width()
	var H: float = (thumb["image"] as Image).get_height()
	return Vector2((l.x / sz + 0.5) * W, (0.5 - l.y / sz) * H)


## bar 3 for one stroke's result: -> [ok count line, bool]
func check_thumbs(ui: Node, label: String, region: Dictionary) -> void:
	var th: Array = ui.sm.thumbs
	ok(th.size() == 8, "%s: 8 thumbnails (%d)" % [label, th.size()])
	var hashes := {}
	var all_filled := true
	var all_red := true
	var all_inside := true
	var all_close := true
	var worst_margin := 1e9
	var worst_off := 0.0
	var spread_min := 1e9
	var fill_min := 1e9
	for t in th:
		var img: Image = t["image"]
		if img == null or img.is_empty() or img.get_width() != 160 or img.get_height() != 160:
			all_filled = false
			continue
		hashes[hash(img.get_data())] = true
		var bg := img.get_pixel(0, 0)
		var non := 0
		var lo := 1.0
		var hi := 0.0
		var rx0 := 1e9
		var ry0 := 1e9
		var rx1 := -1e9
		var ry1 := -1e9
		var reds := 0
		for y in 160:
			for x in 160:
				var c := img.get_pixel(x, y)
				if absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b) > 0.06:
					non += 1
				var lu := (c.r + c.g + c.b) / 3.0
				lo = minf(lo, lu)
				hi = maxf(hi, lu)
				if c.r > 0.78 and c.g < 0.25 and c.b < 0.25:
					reds += 1
					rx0 = minf(rx0, x)
					ry0 = minf(ry0, y)
					rx1 = maxf(rx1, x)
					ry1 = maxf(ry1, y)
		fill_min = minf(fill_min, non / 25600.0)
		spread_min = minf(spread_min, hi - lo)
		if non < 0.05 * 25600.0 or hi - lo < 0.02:
			all_filled = false
		if reds < 12:
			all_red = false
			continue
		# the test's own skinned region vertices at this frame -> projected bbox
		var mats := mats_at(int(t["frame"]))
		var x0 := 1e9
		var y0 := 1e9
		var x1 := -1e9
		var y1 := -1e9
		for v in region:
			var p := px_of(t, lbs(R.verts[v], v, mats))
			x0 = minf(x0, p.x)
			y0 = minf(y0, p.y)
			x1 = maxf(x1, p.x)
			y1 = maxf(y1, p.y)
		var marg := minf(minf(x0, y0), minf(160.0 - x1, 160.0 - y1))
		worst_margin = minf(worst_margin, marg)
		if marg < 4.0:
			all_inside = false
		var off := maxf(maxf(absf(rx0 - x0), absf(ry0 - y0)), maxf(absf(rx1 - x1), absf(ry1 - y1)))
		worst_off = maxf(worst_off, off)
		if off > 12.0:
			all_close = false
	ok(all_filled, "%s: every image non-empty (> 5 pct non-background %.1f pct min, colour spread %.3f min)" % [label, fill_min * 100.0, spread_min])
	ok(hashes.size() >= 5, "%s: %d of 8 images pairwise different" % [label, hashes.size()])
	ok(all_red, "%s: the stroked region is drawn red in every image" % label)
	ok(all_inside, "%s: the region's projected bbox is inside every image (smallest margin %.1f px)" % [label, worst_margin])
	ok(all_close, "%s: the red pixels' bbox is within 12 px of the projected bbox (worst %.1f px)" % [label, worst_off])


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
	build_scene()
	G = Body.new()
	G.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	skc = (m.skel as Skeleton3D).duplicate()
	NF = int(ceil(m._ps().length() * fps)) + 1
	var say := SculptPoseUI.op("sculpt_pose", m)
	await idle(3)
	spu = SculptPoseUI.get_ui(m)
	sp = spu.sp
	ok(spu.is_on() and spu.undo != null, "the pose sculpt is open: " + say.left(80))
	var ui: Node = m.get_node_or_null("sculpt_motion")
	ok(ui != null, "the sculpt-motion UI node exists on main")
	if ui == null:
		print("sculptmotion: %d fails" % (fails + 1))
		quit(1)
		return
	# 0 INSTRUMENT
	var elbow_c := world_of("lowerarm_r")
	var knee_c := world_of("calf_r")
	var elbow_v := region_near(elbow_c, 0.07)
	var knee_v := region_near(knee_c, 0.08)
	var max_el := 0.0
	var max_kn := 0.0
	for f in NF:
		max_el = maxf(max_el, bend_at(f, "lowerarm_r"))
		max_kn = maxf(max_kn, bend_at(f, "calf_r"))
	var elset := {}
	for v in elbow_v:
		elset[v] = true
	var knset := {}
	for v in knee_v:
		knset[v] = true
	ok(NF >= 90, "0 the scene has %d frames" % NF)
	ok(elbow_v.size() >= 40 and knee_v.size() >= 40 and region_edges(R.verts, elset).size() >= 40 and region_edges(R.verts, knset).size() >= 40,
		"0 elbow region %d verts / %d edges, knee region %d / %d" % [elbow_v.size(), region_edges(R.verts, elset).size(), knee_v.size(), region_edges(R.verts, knset).size()])
	ok(max_el >= 100.0 and max_kn >= 100.0, "0 elbow bends %.0f deg, knee %.0f deg at most" % [max_el, max_kn])
	# 1 ELBOW STROKE through the real hook
	var t0 := Time.get_ticks_usec()
	stroke(elbow_v)
	var ms1: float = await wait_strip(ui, t0)
	var sc_el := my_scores(last_moved)
	var mn := 1e9
	var mx := 0.0
	for s in sc_el:
		mn = minf(mn, s)
		mx = maxf(mx, s)
	var t8 := top8(sc_el)
	var srt := sc_el.duplicate()
	srt.sort()
	var gap89 := srt[srt.size() - 8] - srt[srt.size() - 9]
	ok(mx / maxf(mn, 1e-9) > 1.5 and gap89 > 1e-5, "0 elbow score range %.5f .. %.5f (x%.1f); 8th - 9th best = %.2e" % [mn, mx, mx / maxf(mn, 1e-9), gap89])
	var reg_ok: bool = ui.sm != null and Array(ui.sm.region).size() == last_moved.size()
	if reg_ok:
		for v in ui.sm.region:
			if not last_moved.has(v):
				reg_ok = false
	ok(reg_ok, "1 the module's region == the %d vertices the stroke moved in rest" % last_moved.size())
	var ch_el: Array = Array(ui.sm.chosen)
	ok(ch_el.size() == 8 and is_top8(ch_el, sc_el), "1 the 8 chosen frames %s are exactly the test's top-8 %s" % [str(ch_el), str(t8)])
	var maxd := 0.0
	for f in NF:
		maxd = maxf(maxd, absf(float(ui.sm.scores[f]) - sc_el[f]))
	ok(ui.sm.scores.size() == NF and maxd <= 1e-5, "1 every module score within 1e-5 of the test's (worst %.2e over %d frames)" % [maxd, NF])
	var bent := 0
	for f in ch_el:
		if bend_at(f, "lowerarm_r") > 60.0:
			bent += 1
	ok(bent >= 6, "1 %d of the 8 chosen frames have the elbow bent > 60 deg" % bent)
	check_thumbs(ui, "3 elbow", last_moved)
	var max_slice: float = ui.max_slice_ms
	print("   elbow stroke: strip ready after %.0f ms; longest main-thread slice %.1f ms; longest frame gap %.1f ms (machine load counts)" % [ms1, max_slice, gap_max])
	ok(ms1 <= 4000.0, "4 stroke -> strip %.0f ms <= 4000" % ms1)
	ok(max_slice <= 50.0, "4 longest main-thread slice %.1f ms <= 50" % max_slice)
	ok(gap_max <= 120.0, "4 longest frame gap %.1f ms <= 120" % gap_max)
	# 2 SHIN STROKE
	var gen0: int = ui.generation
	t0 = Time.get_ticks_usec()
	stroke(knee_v)
	var ms2: float = await wait_strip(ui, t0)
	var sc_kn := my_scores(last_moved)
	var ch_kn: Array = Array(ui.sm.chosen)
	ok(ui.generation == gen0 + 1, "4 one stroke = one result (generation %d -> %d)" % [gen0, ui.generation])
	ok(ch_kn.size() == 8 and is_top8(ch_kn, sc_kn), "2 the shin stroke's 8 frames %s are exactly the test's top-8 %s" % [str(ch_kn), str(top8(sc_kn))])
	ok(shared(ch_kn, ch_el) <= 2, "2 the shin and elbow strokes share %d frames (<= 2)" % shared(ch_kn, ch_el))
	var kb := 0
	for f in ch_kn:
		if bend_at(f, "calf_r") > 60.0:
			kb += 1
	ok(kb >= 6, "2 %d of the 8 shin frames have the knee bent > 60 deg" % kb)
	check_thumbs(ui, "3 shin", last_moved)
	print("   shin stroke: strip ready after %.0f ms, max slice %.1f ms, frame gap %.1f ms" % [ms2, ui.max_slice_ms, gap_max])
	ok(ui.max_slice_ms <= 50.0, "4 shin: longest slice %.1f ms <= 50" % ui.max_slice_ms)
	# 4b a second stroke while the first runs: one result, the last one
	var g1: int = ui.generation
	stroke(elbow_v)
	await process_frame
	stroke(knee_v)
	await wait_strip(ui, Time.get_ticks_usec())
	var ch_last: Array = Array(ui.sm.chosen)
	ok(ui.generation == g1 + 2 and is_top8(ch_last, my_scores(last_moved)), "4 a stroke during a running job: the result is the LAST stroke's (generation +2)")
	# 6 PLANTED FAKES through the same checker (elbow region's scores)
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var rnd := []
	while rnd.size() < 8:
		var f := rng.randi_range(0, NF - 1)
		if not rnd.has(f):
			rnd.append(f)
	ok(not is_top8(rnd, sc_el), "6 PLANTED FAKE: a random frame choice FAILS the top-8 checker")
	ok(not is_top8(ch_kn, sc_el), "6 PLANTED FAKE: the shin's frames for the elbow stroke FAIL the checker")
	ok(is_top8(ch_el, sc_el), "6 control: the real elbow choice passes the same checker")
	# 5 FEW FRAMES
	few_scene()
	NF = int(ceil(m._ps().length() * 10.0)) + 1
	fps = 10
	t0 = Time.get_ticks_usec()
	stroke(elbow_v)
	await wait_strip(ui, t0)
	var ch3: Array = Array(ui.sm.chosen)
	ok(NF == 3 and ch3 == [0, 1, 2] and ui.sm.thumbs.size() == 3, "5 a 3-frame scene shows all 3 frames in order: %s, %d thumbnails" % [str(ch3), ui.sm.thumbs.size()])
	# 7 run_all
	var ra := FileAccess.get_file_as_string("res://tools/run_all.sh")
	ok(ra.contains("sculptmotion:w"), "7 tools/run_all.sh has the sculptmotion line")
	print("sculptmotion: %d fails" % fails)
	quit(1 if fails > 0 else 0)
