## godot --path . -s tests/facesets_test.gd     (ROADMAP_400 C09; scripts/kmesh_face_sets.gd, kmesh_face_set_tint.gd,
## kmesh_face_sets_ui.gd, the face sets in kmesh_sculpt.gd / kmesh_view.gd; needs a window for bars 8 to 10).
## Bars, written before measuring:
##   1 ANATOMY: the mannequin skin seeded with A19 tags (as anatomy_test). Face sets from the tags: EVERY face's set is
##     its tag + 2, the tag of a face being KMesh.label_pick of its corners (face for face, 0 mismatches); the number of
##     sets made is the number of distinct face tags (> 40); every face whose corners all carry one tag T (counted
##     without label_pick) is in set T + 2. Regions (A18) the same, face for face. UV islands of a cube cut on its 12 edges
##     (seams by angle) give 6 sets, one per side (each side's 16 faces in one set)
##   2 HIDE: a 2 m plane of 40 x 40 quads, the faces with x < 0 in set 2, hidden. Strokes across both halves (draw,
##     inflate, smooth, grab, a C18 inflate filter): every vert of a hidden face is bit-identical; the visible side moves
##     (> 1 cm). Instrument: the same draw stroke with nothing hidden moves those verts (> 1 cm)
##   3 ONLY THIS SET: set 2 = the faces with |x| < 0.3; a draw stroke across the plane with only_set 2: every vert of a
##     face of another set bit-identical, the inner verts of set 2 move (> 1 cm)
##   4 GROW / SHRINK: set 2 a 4 x 4 block: grow -> exactly the 6 x 6 block around it (20 faces added); shrink -> exactly
##     the 4 x 4 again; shrink -> exactly the inner 2 x 2, the faces given up back in set 1; grow does not take hidden faces
##   5 MASK FROM SET: a mask of 0.3 everywhere; "set" on the 4 x 4 block: 1 on exactly its 25 verts, 0.3 elsewhere;
##     "others": 1 on exactly the 1681 - 9 verts that are not inner verts of the block, its 9 inner verts keep 0.3
##   6 FILE + UNDO: sets with a hidden one survive to_dict -> JSON -> from_dict value for value; a face-set brush stroke in
##     KMeshUndo is ONE step, undo gives the old channel back exactly, redo the new; a hide too
##   7 BRUSH: one face-set dab (r 0.25) puts in a NEW set (next id) exactly the faces with a corner nearer than r to the
##     hit, moves no vert, and paints no hidden face
##   8 KEYS (the test sphere, real key / mouse events): W picks the face-set brush; a drag paints a new set (one undo step,
##     no vert moved); H over it hides exactly its faces, the view's surface loses exactly their triangles and ray_face
##     no longer hits them; a D draw drag across the hidden and visible faces moves no vert of a hidden face (bit-exact)
##     and some visible ones; Alt+H shows all; Shift+W then a D drag pressed on the set moves no vert of another face set;
##     Alt+] grows the set by exactly one ring, Alt+[ takes exactly that ring off; Ctrl+M masks exactly the set's verts;
##     Shift+H isolates it (every other face hidden); every op one undo step, Ctrl+Z steps back exactly
##   9 MODEL commands (mesh_tools op:fset_*, the test cube): sets from 4 selected faces, hide them (the surface loses 8
##     triangles), show all; sets from the anatomy tags face for face as bar 1
##  10 PLACEMENT (shot -> user://facesets.png): a set painted at the front centre of the sphere: the colour layer's centre
##     within the brush radius of the press point, the pixel there differs from the same pixel with the layer hidden by
##     > 0.1, a sphere pixel 0.2 m to the side (outside the set, on the sphere: differs > 0.05 from the no-sphere shot)
##     differs < 0.02; H hides the set: the centre pixel is then within 0.03 of the shot without the sphere (the hole shows
##     what is behind)
extends SceneTree

var fails := 0
var m: Node
var ui: KMeshSculptUI


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


static func plane(n: int, size := 2.0) -> KMesh:
	var vs := PackedVector3Array()
	for j in n + 1:
		for i in n + 1:
			vs.append(Vector3(-size * 0.5 + size * i / n, 0.0, -size * 0.5 + size * j / n))
	var fs: Array = []
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			fs.append([a, a + n + 1, a + n + 2, a + 1])
	return KMesh.new().from_arrays(vs, fs)


## set the face sets by a rule on the face index
static func set_by(km: KMesh, f: Callable) -> void:
	KMeshFaceSets.ensure(km)
	var d := PackedFloat32Array()
	d.resize(km.face_count())
	for fi in d.size():
		d[fi] = f.call(fi)
	km.set_attr_data(KMeshFaceSets.NAME, d)


## the faces of a 40 x 40 plane in the block i, j in [a, b)
static func block(n: int, a: int, b: int) -> Dictionary:
	var out := {}
	for j in range(a, b):
		for i in range(a, b):
			out[j * n + i] = true
	return out


static func faces_in(km: KMesh, id: int) -> Dictionary:
	var out := {}
	for fi in KMeshFaceSets.faces_of(km, id):
		out[fi] = true
	return out


static func same_keys(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k):
			return false
	return true


## per vert: a corner of a face that `pred` (face index) says
static func verts_of(km: KMesh, pred: Callable) -> Dictionary:
	var out := {}
	for fi in km.face_count():
		if pred.call(fi):
			for v in (km.faces[fi] as PackedInt32Array):
				out[v] = true
	return out


## a stroke of `brush` along x from -0.6 to 0.6 at z 0.05 (radius 0.25)
static func stroke(km: KMesh, brush: String, extra := {}) -> void:
	var sc := KMeshSculpt.new()
	var p := {"brush": brush, "radius": 0.25, "strength": 0.01}
	p.merge(extra, true)
	sc.begin(km, p)
	for k in 13:
		var x := -0.6 + 0.1 * k
		if brush == KMeshSculpt.GRAB:
			sc.to(Vector3(-0.1, 0, 0.05) + Vector3(0, 0.02 * k, 0), Vector3.UP)
		else:
			sc.to(Vector3(x, 0.0, 0.05), Vector3.UP)
	sc.end()


static func moved(a: PackedVector3Array, b: PackedVector3Array, which: Dictionary) -> Array:
	var exact := true
	var mx := 0.0
	for v in which:
		if a[v] != b[v]:
			exact = false
		mx = maxf(mx, a[v].distance_to(b[v]))
	return [exact, mx]


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func mouse(p: Vector2, down: bool, ctrl := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	e.ctrl_pressed = ctrl
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func drag(a: Vector2, b: Vector2, steps := 8) -> void:
	await mouse(a, true)
	for k in steps:
		await move(a.lerp(b, (k + 1) / float(steps)))
	await mouse(b, false)
	await idle(2)


func key(k: int, ctrl := false, shift := false, alt := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = ctrl
		e.shift_pressed = shift
		e.alt_pressed = alt
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func shot() -> Image:
	await idle(4)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


static func dist(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2))


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


## face for face: every face's set == label_pick(corner labels) + 2; returns [mismatches, distinct face labels,
## faces with one label on every corner, of those the ones in the wrong set]
static func match_labels(km: KMesh, ch: String) -> Array:
	var vd: PackedFloat32Array = km.attr_data(ch)
	var bad := 0
	var seen := {}
	var uni := 0
	var uni_bad := 0
	for fi in km.face_count():
		var fp: PackedInt32Array = km.faces[fi]
		var want := int(KMesh.label_pick(vd, fp))
		if want >= 0:
			seen[want] = true
		var got := KMeshFaceSets.set_of(km, fi)
		if got != maxi(want, -1) + 2:
			bad += 1
		var one := true
		for v in fp:
			one = one and vd[v] == vd[fp[0]]
		if one:
			uni += 1
			if got != maxi(int(vd[fp[0]]), -1) + 2:
				uni_bad += 1
	return [bad, seen.size(), uni, uni_bad]


func _init() -> void:
	# 1 anatomy / regions / uv islands
	var man: Node3D = (load("res://assets/mannequin.glb") as PackedScene).instantiate()
	root.add_child(man)
	for ap in man.find_children("*", "AnimationPlayer", true, false):
		ap.queue_free()
	await idle(2)
	var sk: Skeleton3D = man.find_children("*", "Skeleton3D", true, false)[0]
	sk.reset_bone_poses()
	var sk_m := skin_kmesh(man)
	KMeshAnatomy.seed_tags(sk_m, sk)
	var n_an := KMeshFaceSets.from_labels(sk_m, "anatomy")
	var ra := match_labels(sk_m, KMeshAnatomy.CH)
	ok(n_an == ra[1] and n_an > 40 and ra[0] == 0 and ra[2] > sk_m.face_count() * 0.5 and ra[3] == 0 and KMeshFaceSets.ids(sk_m).size() == n_an,
		"(1) anatomy: %d sets from %d faces (%d distinct face tags), %d faces off their tag; %d one-tag faces, %d of them in the wrong set" % [n_an, sk_m.face_count(), ra[1], ra[0], ra[2], ra[3]])
	KMeshBody.compute(sk_m, KMeshBody.segments_from_skeleton(sk, true))
	var n_rg := KMeshFaceSets.from_labels(sk_m, "region")
	var rr := match_labels(sk_m, KMeshBody.CH_REGION)
	ok(n_rg == rr[1] and n_rg > 10 and rr[0] == 0 and rr[3] == 0, "(1) regions: %d sets (%d distinct), %d faces off, %d one-region faces wrong" % [n_rg, rr[1], rr[0], rr[3]])
	man.queue_free()
	var cube := KMeshView.make_cube(1.0, 4)
	KMeshUV.seams_by_angle(cube, 60.0)
	var n_uv := KMeshFaceSets.from_labels(cube, "uv")
	var side_ok := true   # each side (the face normal's axis and sign) all in one set, six different sets
	var side_set := {}
	for fi in cube.face_count():
		var nn := cube.face_normals[fi]
		var sk_key := Vector3i(roundi(nn.x), roundi(nn.y), roundi(nn.z))
		var s := KMeshFaceSets.set_of(cube, fi)
		if side_set.has(sk_key) and side_set[sk_key] != s:
			side_ok = false
		side_set[sk_key] = s
	var distinct := {}
	for k in side_set:
		distinct[side_set[k]] = true
	ok(n_uv == 6 and side_ok and distinct.size() == 6, "(1) uv islands: %d sets, each side one set %s, %d different" % [n_uv, side_ok, distinct.size()])
	# 2 hide
	var worst_exact := true
	var vis_moved := 1e9
	var words := PackedStringArray()
	for br in [KMeshSculpt.DRAW, KMeshSculpt.INFLATE, KMeshSculpt.SMOOTH, KMeshSculpt.GRAB, "filter"]:
		var p2 := plane(40)
		if br == KMeshSculpt.SMOOTH:   # something to smooth: a bump
			stroke(p2, KMeshSculpt.DRAW, {"strength": 0.02})
		set_by(p2, func(fi): return -2.0 if (fi % 40) < 20 else 1.0)
		var hv := verts_of(p2, func(fi): return KMeshFaceSets.is_hidden(p2, fi))
		var vv := {}
		for v in p2.vert_count():
			if not hv.has(v):
				vv[v] = true
		var a2 := p2.verts.duplicate()
		if br == "filter":
			KMeshFilters.inflate(p2, 0.02)
		else:
			stroke(p2, br)
		var h := moved(a2, p2.verts, hv)
		var vm := moved(a2, p2.verts, vv)
		worst_exact = worst_exact and h[0]
		vis_moved = minf(vis_moved, vm[1])
		words.append("%s hidden exact %s, visible max %.4f" % [br, h[0], vm[1]])
	var p2b := plane(40)
	var a2b := p2b.verts.duplicate()
	stroke(p2b, KMeshSculpt.DRAW)
	var hv0 := verts_of(p2b, func(fi): return (fi % 40) < 20)
	var instr := moved(a2b, p2b.verts, hv0)
	ok(worst_exact and vis_moved > 0.01 and instr[1] > 0.01, "(2) hide: %s; nothing hidden: those verts move %.4f" % ["; ".join(words), instr[1]])
	# 3 only this set
	var p3 := plane(40)
	set_by(p3, func(fi): return 2.0 if absf(-1.0 + ((fi % 40) + 0.5) * 0.05) < 0.3 else 1.0)
	var other := verts_of(p3, func(fi): return KMeshFaceSets.set_of(p3, fi) != 2)
	var inner := {}
	for v in p3.vert_count():
		if not other.has(v):
			inner[v] = true
	var a3 := p3.verts.duplicate()
	stroke(p3, KMeshSculpt.DRAW, {"only_set": 2})
	var o3 := moved(a3, p3.verts, other)
	var i3 := moved(a3, p3.verts, inner)
	ok(o3[0] and i3[1] > 0.01 and other.size() > 0 and inner.size() > 0, "(3) only set 2: %d verts of other sets bit-exact %s; %d inner verts moved up to %.4f" % [other.size(), o3[0], inner.size(), i3[1]])
	# 4 grow / shrink
	var p4 := plane(40)
	set_by(p4, func(fi): return 2.0 if block(40, 18, 22).has(fi) else 1.0)
	var g1 := KMeshFaceSets.grow(p4, 2)
	var after_g := same_keys(faces_in(p4, 2), block(40, 17, 23))
	var s1 := KMeshFaceSets.shrink(p4, 2)
	var after_s := same_keys(faces_in(p4, 2), block(40, 18, 22))
	var s2 := KMeshFaceSets.shrink(p4, 2)
	var after_s2 := same_keys(faces_in(p4, 2), block(40, 19, 21))
	var ones := faces_in(p4, 1).size() == 1600 - 4
	var p4h := plane(40)
	set_by(p4h, func(fi): return 2.0 if block(40, 18, 22).has(fi) else (-3.0 if (fi % 40) == 17 else 1.0))
	var gh := KMeshFaceSets.grow(p4h, 2)
	var hid_kept := faces_in(p4h, 3).size() == 40 and KMeshFaceSets.hidden_faces(p4h).count(1) == 40
	ok(g1 == 20 and after_g and s1 == 20 and after_s and s2 == 12 and after_s2 and ones and gh == 20 - 6 and hid_kept,
		"(4) grow +%d (6 x 6 exactly %s), shrink -%d (4 x 4 %s), shrink -%d (2 x 2 %s, rest in set 1 %s); grow beside a hidden column +%d, hidden kept %s" % [g1, after_g, s1, after_s, s2, after_s2, ones, gh, hid_kept])
	# 5 mask from set
	var p5 := plane(40)
	set_by(p5, func(fi): return 2.0 if block(40, 18, 22).has(fi) else 1.0)
	KMeshMask.fill(p5, 0.3)
	var n5 := KMeshFaceSets.mask_from(p5, 2, "set")
	var bv := verts_of(p5, func(fi): return KMeshFaceSets.set_of(p5, fi) == 2)
	var mk := KMeshMask.values(p5)
	var set_ok := true
	for v in mk.size():
		set_ok = set_ok and is_equal_approx(mk[v], 1.0 if bv.has(v) else 0.3)
	var p5b := plane(40)
	set_by(p5b, func(fi): return 2.0 if block(40, 18, 22).has(fi) else 1.0)
	KMeshMask.fill(p5b, 0.3)
	var n5b := KMeshFaceSets.mask_from(p5b, 2, "others")
	var outv := verts_of(p5b, func(fi): return KMeshFaceSets.set_of(p5b, fi) != 2)
	var mk2 := KMeshMask.values(p5b)
	var oth_ok := true
	var n_one := 0
	for v in mk2.size():
		oth_ok = oth_ok and is_equal_approx(mk2[v], 0.3 if not outv.has(v) else 1.0)
		if mk2[v] == 1.0:
			n_one += 1
	ok(n5 == 25 and bv.size() == 25 and set_ok and n5b == 1672 and n_one == 1672 and oth_ok,
		"(5) mask from set: %d verts to 1 (block corners %d), the rest 0.3: %s; others: %d verts to 1 (%d at 1), inner 9 keep 0.3: %s" % [n5, bv.size(), set_ok, n5b, n_one, oth_ok])
	# 6 file + undo
	var p6 := plane(40)
	set_by(p6, func(fi): return [1.0, 2.0, -3.0, 4.0][fi % 4])
	var js := JSON.stringify(p6.to_dict())
	var back6 := KMesh.new().from_dict(JSON.parse_string(js))
	var file_ok: bool = back6 != null and KMeshFaceSets.values(back6) == KMeshFaceSets.values(p6) and back6.attr_info(KMeshFaceSets.NAME)["domain"] == KMesh.AD_FACE
	var u0 := KMeshFaceSets.values(p6).duplicate()
	var un := KMeshUndo.new()
	un.begin(p6)
	var fb := KMeshSculpt.new()
	fb.begin(p6, {"brush": KMeshSculpt.FSET, "radius": 0.2})
	for k in 6:
		fb.to(Vector3(-0.3 + 0.1 * k, 0, 0), Vector3.UP)
	fb.end()
	un.commit("face set brush")
	var u1 := KMeshFaceSets.values(p6).duplicate()
	var st1 := un.steps.size()
	un.begin(p6)
	KMeshFaceSets.hide(p6, 5)
	un.commit("hide")
	var u2 := KMeshFaceSets.values(p6).duplicate()
	var st2 := un.steps.size()
	un.undo()
	var b1: bool = KMeshFaceSets.values(p6) == u1
	un.undo()
	var b0: bool = KMeshFaceSets.values(p6) == u0
	un.redo()
	un.redo()
	var r2: bool = KMeshFaceSets.values(p6) == u2
	ok(file_ok and st1 == 1 and st2 == 2 and u1 != u0 and u2 != u1 and b1 and b0 and r2 and fb.p["fset_id"] == 5,
		"(6) save/load keeps the channel %s; brush stroke = %d step (new set %d), hide = 1 more; undo exact %s / %s, redo exact %s" % [file_ok, st1, fb.p["fset_id"], b1, b0, r2])
	# 7 brush
	var p7 := plane(40)
	set_by(p7, func(fi): return -3.0 if (fi % 40) == 22 else (2.0 if fi < 400 else 1.0))
	var a7 := p7.verts.duplicate()
	var H := Vector3(0.1, 0, 0.05)
	var b7 := KMeshSculpt.new()
	b7.begin(p7, {"brush": KMeshSculpt.FSET, "radius": 0.25})
	b7.dab(H, Vector3.UP)
	var want7 := {}
	for fi in p7.face_count():
		if (fi % 40) == 22:
			continue
		for v in (p7.faces[fi] as PackedInt32Array):
			if a7[v].distance_to(H) < 0.25:
				want7[fi] = true
				break
	var got7 := faces_in(p7, 4)
	var hid7 := KMeshFaceSets.hidden_faces(p7).count(1) == 40
	ok(b7.p["fset_id"] == 4 and same_keys(got7, want7) and want7.size() > 20 and p7.verts == a7 and hid7,
		"(7) brush dab: new set %d, %d faces painted (want %d, same %s), verts unmoved %s, the hidden column untouched %s" % [b7.p["fset_id"], got7.size(), want7.size(), same_keys(got7, want7), p7.verts == a7, hid7])
	await _ui()
	print("FACESETS ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(1 if fails else 0)


func _tris(view: KMeshView) -> int:
	var am: Mesh = view._surf.mesh
	if am == null or am.get_surface_count() == 0:
		return 0
	var n := 0
	for s in am.get_surface_count():
		n += am.surface_get_array_len(s)
	return n / 3


func _ui() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._sculpt_start()
	await idle(3)
	ui = m.ksc
	var mesh := ui.mesh
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 1.6, wc, false)
	await idle(6)
	var cam: Camera3D = m.cam
	var cs := cam.unproject_position(wc)
	# 8a brush by keys
	await key(KEY_W)
	var picked := ui.brush
	var v0 := mesh.verts.duplicate()
	var s0: int = ui.undo.steps.size()
	var hit0: Dictionary = ui.surface_at(cam, cs)
	await drag(cs + Vector2(-10, 0), cs + Vector2(10, 0))
	var set_faces := faces_in(mesh, 2)
	var paint_ok: bool = picked == KMeshSculpt.FSET and set_faces.size() > 10 and mesh.verts == v0 and ui.undo.steps.size() == s0 + 1
	ok(paint_ok, "(8) W -> %s; a drag painted set 2 on %d faces, verts unmoved %s, undo steps +%d" % [picked, set_faces.size(), mesh.verts == v0, ui.undo.steps.size() - s0])
	# 10 placement (the colour layer), before the hide
	await move(cs + Vector2(300, 300), false)
	m.ui_root.visible = false
	var tn: KMeshFaceSetTint = ui.fsets.tint
	var tc := Vector3.INF
	if tn != null and tn.mesh != null:
		var ab := tn.mesh.get_aabb()
		tc = ui.view.global_transform * (ab.position + ab.size * 0.5)
	var off_c: float = tc.distance_to(hit0["point"]) if not hit0.is_empty() else INF
	var side := cam.unproject_position(wc + Vector3(0.2, 0.0, 0.0) + (cam.global_position - wc).normalized() * 0.2)
	var img := await shot()
	img.save_png("user://facesets.png")
	tn.visible = false
	var img_no := await shot()
	ui.view.visible = false
	var img_none := await shot()
	ui.view.visible = true
	tn.visible = true
	var pc := Vector2i(cs.round())
	var ps := Vector2i(side.round())
	var d_c := dist(img.get_pixelv(pc), img_no.get_pixelv(pc))
	var d_s := dist(img.get_pixelv(ps), img_no.get_pixelv(ps))
	var on_sph := dist(img_no.get_pixelv(ps), img_none.get_pixelv(ps)) > 0.05
	ok(off_c < ui.radius and d_c > 0.1 and d_s < 0.02 and on_sph and not set_faces.has(int(ui.surface_at(cam, side).get("face", -1))),
		"(10) placement: layer centre %.4f m from the press (brush %.3f); centre pixel differs %.3f with / without the layer; side pixel %s (on the sphere %s, outside the set) differs %.4f (shot user://facesets.png)" % [off_c, ui.radius, d_c, ps, on_sph, d_s])
	m.ui_root.visible = true
	# 8b hide
	var tri0 := _tris(ui.view)
	var set_tris := 0
	for fi in set_faces:
		set_tris += (mesh.faces[fi] as PackedInt32Array).size() - 2
	await move(cs, false)
	await key(KEY_H)
	var hid := {}
	var hb := KMeshFaceSets.hidden_faces(mesh)
	for fi in hb.size():
		if hb[fi]:
			hid[fi] = true
	ui.view.rebuild()
	var tri1 := _tris(ui.view)
	var ray_miss: bool = ui.surface_at(cam, cs).is_empty() or not set_faces.has(int(ui.surface_at(cam, cs)["face"]))
	m.ui_root.visible = false
	await move(cs + Vector2(300, 300), false)
	var img_h := await shot()
	m.ui_root.visible = true
	var d_h := dist(img_h.get_pixelv(pc), img_none.get_pixelv(pc))
	ok(same_keys(hid, set_faces) and tri0 - tri1 == set_tris and ray_miss and d_h < 0.03,
		"(8) H hid %d faces (the set: %s); surface %d -> %d triangles (the set's %d); the ray at the centre misses them %s; (10) the centre pixel is now %.4f from the no-sphere shot" % [hid.size(), same_keys(hid, set_faces), tri0, tri1, set_tris, ray_miss, d_h])
	# 8c a draw drag across hidden + visible
	await key(KEY_D)
	var hv := verts_of(mesh, func(fi): return hid.has(fi))
	var vv := {}
	for v in mesh.vert_count():
		if not hv.has(v):
			vv[v] = true
	var a8 := mesh.verts.duplicate()
	await drag(cs + Vector2(-150, 0), cs + Vector2(150, 0), 20)
	var h8 := moved(a8, mesh.verts, hv)
	var v8 := moved(a8, mesh.verts, vv)
	ok(h8[0] and v8[1] > 0.001, "(8) D drag across: %d verts of hidden faces bit-exact %s; visible ones moved up to %.4f m" % [hv.size(), h8[0], v8[1]])
	await key(KEY_H, false, false, true)
	var shown: bool = KMeshFaceSets.hidden_faces(mesh).is_empty()
	# 8d only this set
	await key(KEY_W, false, true)
	var only_on: bool = ui.fsets.only
	var oth := verts_of(mesh, func(fi): return KMeshFaceSets.set_of(mesh, fi) != 2)
	var inn := {}
	for v in mesh.vert_count():
		if not oth.has(v):
			inn[v] = true
	var a9 := mesh.verts.duplicate()
	await drag(cs, cs + Vector2(150, 0), 20)
	var o9 := moved(a9, mesh.verts, oth)
	var i9 := moved(a9, mesh.verts, inn)
	await key(KEY_W, false, true)
	ok(shown and only_on and not ui.fsets.only and o9[0] and i9[1] > 0.0005,
		"(8) Alt+H shows all %s; Shift+W only on %s; D drag pressed on set 2: %d verts of other sets bit-exact %s, the set's inner verts moved %.4f; Shift+W off again %s" % [shown, only_on, oth.size(), o9[0], i9[1], not ui.fsets.only])
	# 8e grow / shrink / mask / isolate by keys
	var before := faces_in(mesh, 2)
	var sv := verts_of(mesh, func(fi): return before.has(fi))
	var ring := {}
	for fi in mesh.face_count():
		if before.has(fi):
			continue
		for v in (mesh.faces[fi] as PackedInt32Array):
			if sv.has(v):
				ring[fi] = true
				break
	var want_g := before.duplicate()
	want_g.merge(ring)
	var st0: int = ui.undo.steps.size()
	await move(cs, false)
	await key(KEY_BRACKETRIGHT, false, false, true)
	var grown := same_keys(faces_in(mesh, 2), want_g)
	await key(KEY_BRACKETLEFT, false, false, true)
	var shrunk := same_keys(faces_in(mesh, 2), before)
	KMeshMask.clear(mesh)
	await key(KEY_M, true)
	var mk := KMeshMask.values(mesh)
	var mask_ok := true
	for v in mk.size():
		mask_ok = mask_ok and (mk[v] == 1.0) == sv.has(v)
	await key(KEY_H, false, true)
	var hb2 := KMeshFaceSets.hidden_faces(mesh)
	var iso_ok := not hb2.is_empty()
	for fi in mesh.face_count():
		iso_ok = iso_ok and (hb2[fi] == 1) == (not before.has(fi))
	var steps: int = ui.undo.steps.size() - st0
	await key(KEY_Z, true)
	var und1: bool = KMeshFaceSets.hidden_faces(mesh).is_empty()
	await key(KEY_Z, true)
	var und2: bool = KMeshMask.values(mesh).count(1.0) == 0
	ok(grown and ring.size() > 0 and shrunk and mask_ok and iso_ok and steps == 4 and und1 and und2,
		"(8) Alt+] grows by the %d-face ring %s, Alt+[ takes it off %s; Ctrl+M masks exactly the set's %d verts %s; Shift+H isolates %s; %d undo steps; Ctrl+Z un-isolates %s, then unmasks %s" % [ring.size(), grown, shrunk, sv.size(), mask_ok, iso_ok, steps, und1, und2])
	await key(KEY_ESCAPE)
	await _model()


func _model() -> void:
	m._kmesh_edit_start()
	await idle(3)
	var ed: KMeshEditUI = m.kmed
	var km: KMesh = ed.mesh
	ed.sel.set_mode(KMeshSelect.FACE)
	ed.sel.faces = {0: true, 1: true, 2: true, 3: true}
	ed.view.mark_dirty()
	await idle(2)
	var t0 := _tris(ed.view)
	MeshTools.op("fset_from_sel", m)
	var id := KMeshFaceSets.set_of(km, 0)
	var same := KMeshFaceSets.faces_of(km, id).size() == 4
	MeshTools.op("fset_hide", m)
	await idle(2)
	ed.view.rebuild()
	var t1 := _tris(ed.view)
	var tint_on: bool = ed.view.get_node_or_null("face_set_tint") != null
	MeshTools.op("fset_show_all", m)
	await idle(2)
	ed.view.rebuild()
	var t2 := _tris(ed.view)
	var has_tags: bool = km.has_attr(KMeshAnatomy.CH)
	MeshTools.op("fset_anatomy", m)
	var r := match_labels(km, KMeshAnatomy.CH) if has_tags else [1, 0, 0, 1]
	ok(id == 2 and same and t0 - t1 == 8 and t2 == t0 and tint_on and has_tags and r[0] == 0 and r[3] == 0 and r[1] > 0,
		"(9) model: selection -> set %d (4 faces %s); hide: %d -> %d triangles, show all: %d; colour layer on the view %s; sets from the cube's %d anatomy tags: %d faces off" % [id, same, t0, t1, t2, tint_on, r[1], r[0]])
