## godot --path . -s tests/bodymesh_test.gd     (ROADMAP_400 A18 ★; needs a window for bar 9: the view and its legend)
## BODY-AWARE MESH (scripts/kmesh_body.gd). The mannequin's skin (assets/mannequin.glb, both surfaces welded into one
## KMesh, 8.5k verts) labelled against its own skeleton at rest (T pose: the left arm along +x). Bars, written before
## measuring:
##   1 PLACES: the crown (highest vert) -> head / head; each fingertip (the vert furthest out along x) -> a finger bone
##     of that side / hand_<side>; each kneecap (the most forward vert within 3 cm of the knee joint's height on that
##     side) -> thigh_<side> or calf_<side> with the matching region; mid upper arm (the top of the arm half way along
##     the bone) -> upperarm_<side> / upperarm_<side>, 2..8 cm from the bone; mid forearm -> lowerarm / forearm; the toe
##     tip -> ball / foot; the navel (the most forward vert on the middle line at y 1.0..1.1) -> spine_01 or spine_02 /
##     abdomen; the crown is under 15 cm from the head bone
##   2 SEGMENT, NOT JOINT: on the top of the left upper arm at 64 % of its length the nearest JOINT is lowerarm_l, the
##     nearest SEGMENT upperarm_l, and the labels say upperarm_l (the instrument can tell the two apart: verts where the
##     two answers differ > 100)
##   3 EVERY VERT: 0 verts unlabelled, every bone / region index in its table, every distance finite and >= 0; the
##     labels equal a brute-force pass over every segment for every vert (0 labels that are not a nearest bone, ties
##     within 1 um allowed; distances within 1e-4 cm)
##   4 LEFT / RIGHT: 0 verts whose region has a side on the wrong side of x = 0 (|x| > 1 mm); mirrored vertex pairs
##     (KMesh.symmetry_map, 1 mm) carry the mirrored region on >= 99.5 % of pairs
##   5 STABLE: one vert moved 1 mm: refresh relabels exactly 1 vert, every other vert's bone / region / cm bit-identical;
##     the result equals a full compute of the edited mesh on every vert
##   6 TIME: a full labelling of the mannequin skin < 200 ms (best of 3), the 1-vert refresh < 15 ms, a refresh with
##     nothing changed < 5 ms
##   7 BODY CHANGES: the left elbow bent 90 deg (skeleton pose): refresh does a full pass, > 100 verts change label, and
##     the result equals a fresh compute on the bent segments
##   8 SAVED: to_dict -> from_dict and KMesh.save -> load_file give the three channels back bit-for-bit
##   9 VIEW (window): the Model test cube is labelled from the first frame (0 unlabelled verts, before any key);
##     Shift+H (a real key): the region layer is on, its box equals the mesh's within 3 mm (world), its corner colours are
##     the region colours of their verts (within 0.01: vertex colours come back 8-bit), it is drawn (a front face's centre pixel differs from the plain view by > 0.1);
##     the legend is visible, wholly inside the free view (nav_clear_rect), overlaps neither the Add primitive panel nor
##     the topology legend (H on too), and shows exactly the regions present; a mouse move onto a front vertex says
##     KMeshBody.readout of that vertex ("<region>, x.x cm from bone <bone>"); a 1 mm vertex nudge relabels exactly 1
##     vert next frame; Shift+H again hides layer and legend
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func key(k: int, shift := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.shift_pressed = shift
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func shot() -> Image:
	await idle(4)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


## the mannequin's skin as one KMesh (each surface welded, then appended)
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


func lab(k: KMesh, v: int) -> Dictionary:
	return KMeshBody.label(k, v)


func best_vert(k: KMesh, keep: Callable, score: Callable) -> int:
	var bv := -1
	var bs := -INF
	for v in k.verts.size():
		var p := k.verts[v]
		if keep.call(p):
			var s: float = score.call(p)
			if s > bs:
				bs = s
				bv = v
	return bv


func chans(k: KMesh) -> Array:
	return [(k.attr_data(KMeshBody.CH_BONE) as PackedFloat32Array).duplicate(), (k.attr_data(KMeshBody.CH_CM) as PackedFloat32Array).duplicate(),
		(k.attr_data(KMeshBody.CH_REGION) as PackedFloat32Array).duplicate()]


## brute force: every segment for every vert -> [the nearest bones (every bone within 1 um of the nearest: a tie at a
## shared joint), cm]
func brute(k: KMesh, segs: Array) -> Array:
	var bo := []
	var cm := PackedFloat32Array()
	for p in k.verts:
		var ds := PackedFloat32Array()
		var bd := INF
		for s in segs:
			var a: Vector3 = s["a"]
			var ab: Vector3 = s["b"] - a
			var l2 := ab.length_squared()
			var t := 0.0 if l2 < 1e-12 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			ds.append(d)
			bd = minf(bd, d)
		var near := PackedInt32Array()
		for i in segs.size():
			if ds[i] <= bd + 1e-6:
				near.append(segs[i]["bi"])
		bo.append(near)
		cm.append(bd * 100.0)
	return [bo, cm]


func _init() -> void:
	var man: Node3D = (load("res://assets/mannequin.glb") as PackedScene).instantiate()
	root.add_child(man)
	for ap in man.find_children("*", "AnimationPlayer", true, false):
		ap.queue_free()
	await idle(2)
	var sk: Skeleton3D = man.find_children("*", "Skeleton3D", true, false)[0]
	sk.reset_bone_poses()
	var k := skin_kmesh(man)
	var segs := KMeshBody.segments_from_skeleton(sk, true)
	print("mannequin skin: %d verts, %d faces, %d bone segments" % [k.verts.size(), k.face_count(), segs.size()])
	var r0 := KMeshBody.refresh(k, segs)
	var seg_of := {}
	for s in segs:
		seg_of[s["bone"]] = s

	# ---- 1 places
	var crown := best_vert(k, func(_p): return true, func(p): return p.y)
	var lc := lab(k, crown)
	ok(lc["bone"] == "head" and lc["region"] == "head" and lc["cm"] < 15.0, "bar 1: crown v%d %s -> %s / %s, %.1f cm" % [crown, k.verts[crown], lc["bone"], lc["region"], lc["cm"]])
	for side in ["_l", "_r"]:
		var sg := 1.0 if side == "_l" else -1.0
		var tip := best_vert(k, func(_p): return true, func(p): return p.x * sg)
		var lt := lab(k, tip)
		var fing := false
		for f in ["thumb", "index", "middle", "ring", "pinky"]:
			if String(lt["bone"]).begins_with(f) and String(lt["bone"]).ends_with(side):
				fing = true
		ok(fing and lt["region"] == "hand" + side, "bar 1: fingertip%s v%d %s -> %s / %s, %.1f cm" % [side, tip, k.verts[tip], lt["bone"], lt["region"], lt["cm"]])
		var ky: float = seg_of["calf" + side]["a"].y
		var knee := best_vert(k, func(p): return p.x * sg > 0.03 and absf(p.y - ky) < 0.03, func(p): return p.z)
		var lk := lab(k, knee)
		ok((lk["bone"] == "thigh" + side and lk["region"] == "thigh" + side) or (lk["bone"] == "calf" + side and lk["region"] == "shin" + side),
			"bar 1: kneecap%s v%d %s (joint y %.3f) -> %s / %s, %.1f cm" % [side, knee, k.verts[knee], ky, lk["bone"], lk["region"], lk["cm"]])
		var ua: Dictionary = seg_of["upperarm" + side]
		var ux: float = lerpf(ua["a"].x, ua["b"].x, 0.5)
		var mid := best_vert(k, func(p): return absf(p.x - ux) < 0.012, func(p): return p.y)
		var lm := lab(k, mid)
		ok(lm["bone"] == "upperarm" + side and lm["region"] == "upperarm" + side and lm["cm"] >= 2.0 and lm["cm"] <= 8.0,
			"bar 1: mid upper arm%s v%d %s -> %s / %s, %.1f cm" % [side, mid, k.verts[mid], lm["bone"], lm["region"], lm["cm"]])
		var fa: Dictionary = seg_of["lowerarm" + side]
		var fx: float = lerpf(fa["a"].x, fa["b"].x, 0.5)
		var mf := best_vert(k, func(p): return absf(p.x - fx) < 0.012, func(p): return -p.y)
		var lf := lab(k, mf)
		ok(lf["bone"] == "lowerarm" + side and lf["region"] == "forearm" + side, "bar 1: mid forearm%s (underside) v%d %s -> %s / %s, %.1f cm" % [side, mf, k.verts[mf], lf["bone"], lf["region"], lf["cm"]])
		var toe := best_vert(k, func(p): return p.x * sg > 0.02 and p.y < 0.1, func(p): return p.z)
		var lo := lab(k, toe)
		ok(lo["bone"] == "ball" + side and lo["region"] == "foot" + side, "bar 1: toe tip%s v%d %s -> %s / %s, %.1f cm" % [side, toe, k.verts[toe], lo["bone"], lo["region"], lo["cm"]])
	var navel := best_vert(k, func(p): return absf(p.x) < 0.02 and p.y > 1.0 and p.y < 1.1, func(p): return p.z)
	var ln := lab(k, navel)
	ok(ln["bone"] in ["spine_01", "spine_02"] and ln["region"] == "abdomen", "bar 1: navel v%d %s -> %s / %s, %.1f cm" % [navel, k.verts[navel], ln["bone"], ln["region"], ln["cm"]])

	# ---- 2 segment, not joint
	var ual: Dictionary = seg_of["upperarm_l"]
	var x64: float = lerpf(ual["a"].x, ual["b"].x, 0.64)
	var v64 := best_vert(k, func(p): return absf(p.x - x64) < 0.01, func(p): return p.y)
	var nj := ""
	var njd := INF
	var differ := 0
	var bon: PackedFloat32Array = k.attr_data(KMeshBody.CH_BONE)
	for v in k.verts.size():
		var jb := ""
		var jd := INF
		for s in segs:
			var d: float = k.verts[v].distance_to(s["a"])
			if d < jd:
				jd = d
				jb = s["bone"]
		if v == v64:
			nj = jb
			njd = jd
		if jb != KMeshBody.BONES[int(bon[v])]:
			differ += 1
	ok(nj == "lowerarm_l" and lab(k, v64)["bone"] == "upperarm_l" and differ > 100,
		"bar 2: upper arm at 64%% (v%d %s): nearest joint %s (%.1f cm), label %s (%.1f cm); %d verts where joint and segment differ" % [v64, k.verts[v64], nj, njd * 100.0, lab(k, v64)["bone"], lab(k, v64)["cm"], differ])

	# ---- 3 every vert
	var cm0: PackedFloat32Array = k.attr_data(KMeshBody.CH_CM)
	var rg0: PackedFloat32Array = k.attr_data(KMeshBody.CH_REGION)
	var bad := 0
	for v in k.verts.size():
		if bon[v] < 0 or int(bon[v]) >= KMeshBody.BONES.size() or rg0[v] < 0 or int(rg0[v]) >= KMeshBody.REGIONS.size() or not is_finite(cm0[v]) or cm0[v] < 0.0:
			bad += 1
	var bf := brute(k, segs)
	var bdiff := 0
	var ties := 0
	var cdiff := 0.0
	for v in k.verts.size():
		if not (bf[0][v] as PackedInt32Array).has(int(bon[v])):
			bdiff += 1
		if (bf[0][v] as PackedInt32Array).size() > 1:
			ties += 1
		cdiff = maxf(cdiff, absf(cm0[v] - bf[1][v]))
	ok(bad == 0 and r0["n"] == k.verts.size(), "bar 3: %d of %d verts labelled, %d bad" % [int(r0["n"]), k.verts.size(), bad])
	ok(bdiff == 0 and cdiff < 1e-4, "bar 3: against brute force over %d segments: %d labels not a nearest bone (%d verts tie two bones at a joint), max distance difference %.6f cm (culled run: %d tests, brute %d)" % [segs.size(), bdiff, ties, cdiff, int(r0["tests"]), k.verts.size() * segs.size()])

	# ---- 4 left / right
	var swapped := 0
	for v in k.verts.size():
		var rn: String = KMeshBody.REGIONS[int(rg0[v])]
		var x := k.verts[v].x
		if (rn.ends_with("_l") and x < -0.001) or (rn.ends_with("_r") and x > 0.001):
			swapped += 1
	var sm := k.symmetry_map(0, 0.001)
	var pairs := 0
	var agree := 0
	for v in k.verts.size():
		var w: int = sm[v]
		if w < 0 or w == v:
			continue
		pairs += 1
		var a: String = KMeshBody.REGIONS[int(rg0[v])]
		var b: String = KMeshBody.REGIONS[int(rg0[w])]
		var mb := b.trim_suffix("_l") + "_r" if b.ends_with("_l") else (b.trim_suffix("_r") + "_l" if b.ends_with("_r") else b)
		if a == mb:
			agree += 1
	ok(swapped == 0, "bar 4: %d verts on the wrong side of x = 0" % swapped)
	ok(pairs > 1000 and agree >= 0.995 * pairs, "bar 4: mirrored pairs %d, mirrored region on %d (%.2f %%)" % [pairs, agree, 100.0 * agree / maxf(pairs, 1)])

	# ---- 5 stable + 6 time
	var before := chans(k)
	var vs := k.verts
	vs[v64] += Vector3(0.001, 0, 0)
	k.verts = vs
	var r1 := KMeshBody.refresh(k, segs)
	var after := chans(k)
	var other := 0
	for v in k.verts.size():
		if v == v64:
			continue
		for c in 3:
			if before[c][v] != after[c][v]:
				other += 1
				break
	var k2 := KMesh.new().from_arrays(k.verts, k.faces)
	KMeshBody.compute(k2, segs)
	var full := chans(k2)
	var neq := 0
	for v in k.verts.size():
		for c in 3:
			if full[c][v] != after[c][v]:
				neq += 1
				break
	ok(int(r1["n"]) == 1 and not r1["full"] and other == 0, "bar 5: a 1 mm move of v%d: refresh relabelled %d vert (full %s), %d other verts changed" % [v64, int(r1["n"]), r1["full"], other])
	ok(neq == 0, "bar 5: incremental vs a full compute of the edited mesh: %d verts differ" % neq)
	var tbest := INF
	for i in 3:
		tbest = minf(tbest, float(KMeshBody.compute(k2, segs)["ms"]))
	var t1 := float(r1["ms"])
	var tu0 := Time.get_ticks_usec()
	var r2 := KMeshBody.refresh(k, segs)
	var tnone := (Time.get_ticks_usec() - tu0) / 1000.0
	vs = k.verts
	vs[crown] += Vector3(0, 0.001, 0)
	k.verts = vs
	tu0 = Time.get_ticks_usec()
	KMeshBody.refresh(k, segs)
	var t1b := (Time.get_ticks_usec() - tu0) / 1000.0
	ok(tbest < 200.0, "bar 6: full labelling of %d verts: %.1f ms best of 3 (bar 200)" % [k.verts.size(), tbest])
	ok(minf(t1, t1b) < 15.0 and int(r2["n"]) == 0 and tnone < 5.0, "bar 6: 1-vert refresh %.2f / %.2f ms (bar 15), nothing changed %.2f ms (bar 5, relabelled %d)" % [t1, t1b, tnone, int(r2["n"])])

	# ---- 7 body changes
	var before7 := chans(k)
	var ib := sk.find_bone("lowerarm_l")
	sk.set_bone_pose_rotation(ib, sk.get_bone_pose_rotation(ib) * Quaternion(Vector3(0, 0, 1), deg_to_rad(90.0)))
	var segs2 := KMeshBody.segments_from_skeleton(sk, true)
	var moved_hand: float = (segs2.filter(func(s): return s["bone"] == "hand_l")[0]["a"] as Vector3).distance_to(seg_of["hand_l"]["a"])
	var r7 := KMeshBody.refresh(k, segs2)
	var after7 := chans(k)
	var changed7 := 0
	for v in k.verts.size():
		if before7[0][v] != after7[0][v]:
			changed7 += 1
	var k3 := KMesh.new().from_arrays(k.verts, k.faces)
	KMeshBody.compute(k3, segs2)
	var ref7 := chans(k3)
	var neq7 := 0
	for v in k.verts.size():
		for c in 3:
			if ref7[c][v] != after7[c][v]:
				neq7 += 1
				break
	ok(r7["full"] and changed7 > 100 and neq7 == 0 and moved_hand > 0.1, "bar 7: elbow bent 90 deg (hand moved %.0f cm): full pass %s in %.1f ms, %d verts changed bone, %d differ from a fresh compute" % [moved_hand * 100.0, r7["full"], float(r7["ms"]), changed7, neq7])
	sk.reset_bone_poses()
	KMeshBody.refresh(k, segs)

	# ---- 8 saved
	var ch8 := chans(k)
	var kd := KMesh.new().from_dict(JSON.parse_string(JSON.stringify(k.to_dict())))
	var path := "user://bodymesh_test.kmesh"
	var err := k.save(path)
	var kf := KMesh.load_file(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var same_d: bool = kd != null and kd.has_attr(KMeshBody.CH_REGION) and chans(kd) == ch8
	var same_f: bool = kf != null and kf.has_attr(KMeshBody.CH_REGION) and chans(kf) == ch8
	ok(same_d and same_f and err == OK, "bar 8: channels back bit-for-bit through to_dict/from_dict %s, save/load_file %s (err %d)" % [same_d, same_f, err])
	if kf != null:
		ok(KMeshBody.readout(kf, v64) == KMeshBody.readout(k, v64), "bar 8: the loaded mesh reads '%s'" % KMeshBody.readout(kf, v64))
	man.queue_free()

	# ---- 9 view
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._kmesh_edit_start()
	var ui: KMeshEditUI = m.kmed
	var unl := 0
	for r in (ui.mesh.attr_data(KMeshBody.CH_REGION) as PackedFloat32Array):
		if r < 0.0:
			unl += 1
	ok(ui.mesh.has_attr(KMeshBody.CH_REGION) and unl == 0, "bar 9: the test cube is labelled from its first frame (%d verts, %d unlabelled; regions %s)" % [ui.mesh.verts.size(), unl, KMeshBody.counts(ui.mesh)])
	await idle(3)
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 2.4, wc + Vector3(0, 0.12, 0), false)
	await idle(4)
	m.ui_root.visible = false
	var img_off := await shot()
	m.ui_root.visible = true
	await key(KEY_H, true)
	var bd: KMeshBody = ui.body
	var lay: MeshInstance3D = bd.layer
	ok(bd.on and lay != null and lay.visible and lay.mesh != null and lay.mesh.get_surface_count() == 1, "bar 9: Shift+H: colour by region on %s, layer %s" % [bd.on, lay])
	if lay != null and lay.mesh != null and lay.mesh.get_surface_count() == 1:
		var lb := lay.global_transform * lay.mesh.get_aabb()
		var mb := AABB(ui.mesh.verts[0], Vector3.ZERO)
		for p in ui.mesh.verts:
			mb = mb.expand(p)
		mb = ui.view.global_transform * mb
		var dbox := maxf((lb.position - mb.position).abs()[(lb.position - mb.position).abs().max_axis_index()], (lb.end - mb.end).abs()[(lb.end - mb.end).abs().max_axis_index()])
		ok(dbox < 0.003, "bar 9: the layer's box %s vs the mesh's %s: %.1f mm apart (bar 3)" % [lb, mb, dbox * 1000.0])
		var arr := lay.mesh.surface_get_arrays(0)
		var lp: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var lcols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
		var wrong := 0
		for i in lp.size():   # each layer corner: its nearest mesh vert's region colour
			var bv := 0
			var bdd := INF
			for v in ui.mesh.verts.size():
				var d := ui.mesh.verts[v].distance_squared_to(lp[i])
				if d < bdd:
					bdd = d
					bv = v
			var want := KMeshBody.color_of(lab(ui.mesh, bv)["region"])
			if absf(lcols[i].r - want.r) + absf(lcols[i].g - want.g) + absf(lcols[i].b - want.b) > 0.01:   # (8-bit vertex colours)
				wrong += 1
		ok(wrong == 0 and lp.size() > 0, "bar 9: %d layer corners, %d not their vertex's region colour (within 0.01)" % [lp.size(), wrong])
	# a front face (normal +z: the camera looks down -z) near the middle
	var ff := -1
	var fd := INF
	for fi in ui.mesh.face_count():
		if ui.mesh.face_normals[fi].z > 0.99:
			var d: float = ui.mesh.face_center(fi).distance_to(Vector3(0.05, 0.05, 0.3))
			if d < fd:
				fd = d
				ff = fi
	var fcp: Vector2 = m.cam.unproject_position(ui.view.global_transform * ui.mesh.face_center(ff))
	m.ui_root.visible = false
	var img_on := await shot()
	m.ui_root.visible = true
	var con := img_on.get_pixelv(Vector2i(fcp))
	var cof := img_off.get_pixelv(Vector2i(fcp))
	var cdist := sqrt(pow(con.r - cof.r, 2) + pow(con.g - cof.g, 2) + pow(con.b - cof.b, 2))
	ok(cdist > 0.1, "bar 9: face %d centre pixel %s: %s with regions, %s plain (distance %.2f; its region %s)" % [ff, fcp, con.to_html(false), cof.to_html(false), cdist, lab(ui.mesh, ui.mesh.faces[ff][0])["region"]])
	var outp := OS.get_environment("BODYMESH_SHOT")
	if outp != "":
		img_on.save_png(outp)
		print("shot saved: ", outp)
	# the legend
	await key(KEY_H)   # the topology heat map's legend too: the two must not overlap
	await idle(2)
	var lg: PanelContainer = bd.legend
	var cl: Rect2 = m.nav_clear_rect()
	var lr: Rect2 = lg.get_global_rect() if lg != null else Rect2()
	var pr: Rect2 = ui.prim_panel.get_global_rect()
	var tr: Rect2 = ui.legend.get_global_rect() if ui.legend != null and ui.legend.visible else Rect2()
	ok(lg != null and lg.visible and cl.encloses(lr) and lr.size.x > 60 and not lr.intersects(pr) and ui.legend != null and ui.legend.visible and not lr.intersects(tr),
		"bar 9: legend %s inside the free view %s, clear of Add primitive %s and the topology legend %s" % [lr, cl, pr, tr])
	var shown := []
	if lg != null:
		for r in KMeshBody.REGIONS:
			if (lg.get_node("rows/" + r) as Control).visible:
				shown.append(r)
	var present := KMeshBody.counts(ui.mesh).keys()
	shown.sort()
	present.sort()
	ok(shown == present and shown.size() > 0, "bar 9: the legend shows %s; the mesh has %s" % [shown, present])
	await key(KEY_H)
	# hover: the front face's first corner
	var hv: int = ui.mesh.faces[ff][0]
	var hp: Vector2 = m.cam.unproject_position(ui.view.global_transform * ui.mesh.verts[hv])
	var mv := InputEventMouseMotion.new()
	mv.position = hp + Vector2(2, 2)
	root.push_input(mv)
	await idle(2)
	ok(bd.hover_text == KMeshBody.readout(ui.mesh, hv) and bd.hover_text.contains(" cm from bone "), "bar 9: hover over v%d at %s says '%s' (expected '%s')" % [hv, hp, bd.hover_text, KMeshBody.readout(ui.mesh, hv)])
	# a mesh edit: refreshed next frame, one vert
	var cv := ui.mesh.verts
	cv[hv] += Vector3(0.001, 0, 0)
	ui.mesh.verts = cv
	await idle(2)
	ok(int(bd.last.get("n", -1)) == 1 and not bd.last.get("full", true), "bar 9: a 1 mm nudge relabelled %d vert next frame (full %s)" % [int(bd.last.get("n", -1)), bd.last.get("full", null)])
	await key(KEY_H, true)
	ok(not bd.on and (bd.layer == null or not bd.layer.visible) and not bd.legend.visible, "bar 9: Shift+H again: layer and legend hidden")
		# ---- round 2 bar: Apply body with NO edit writes nothing (the rebuild split the UV seams: 6994 -> 7330 verts)
	var mb = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(mb)
	await idle(6)
	mb._load_scene("res://scenes/combo3.json")
	mb._rebuild_cards()
	await idle(3)
	var n_before := BaseBody.read(mb).verts.size()
	var g_before := BaseBody.gen(mb)
	for c in mb._commands():
		if c["name"] == "Model: edit the body mesh":
			(c["run"] as Callable).call()
	await idle(3)
	for c in mb._commands():
		if c["name"] == "Model: apply the body mesh to the fighter":
			(c["run"] as Callable).call()
	await idle(2)
	var n_after := BaseBody.read(mb).verts.size()
	ok(n_after == n_before and BaseBody.gen(mb) == g_before, "R2 apply body with no edit: %d -> %d verts, generations %d -> %d (bar: unchanged)" % [n_before, n_after, g_before, BaseBody.gen(mb)])
	mb.queue_free()
	await idle(2)
	print("BODYMESH ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
