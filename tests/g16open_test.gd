## godot --path . -s tests/g16open_test.gd     (lane G16: stroke retopology across a mesh's open edges; scripts/kmesh_holes.gd, scripts/kmesh_retopo_net.gd)
## BARS, COMMITTED BEFORE THE FIRST RUN (numbers fixed here; a fixture may change after a run only if the run shows it was wrong as a fixture, said in the report):
##   a MODES. Head fixture = the mannequin head cut at y = 1.64 (an open neck, from assets/mannequin.glb) with two eye holes punched out of its faces
##     (the asset has no eye holes of its own). Strokes: one ring at 1.715 m (AMENDED after the first runs, fixture only: rings at 1.78 / 1.805 gave 4-sided patches with 13 vs 4 opposite edges, and the eye holes span 1.72-1.78) + two section planes down to the neck cut. With open_policy: 0 regions
##     skipped, every valid region states a mode in {none, boundary_side, closed_hole, both}; the neck loop defaults to side, each eye hole to close;
##     >= 1 region is boundary_side and >= 1 is closed_hole. PLANTED: the old path (setup without open) on the same strokes skips >= 1 region.
##   b BOUNDARY SIDE. Every baked-mesh boundary vertex (the quads along the neck) lies within 1e-6 of the neck polyline; the number of those vertices equals
##     the sum of the boundary arcs' edge counts. PLANTED: a vertex moved 1e-4 off the polyline fails the same distance check.
##   c CLOSED HOLE. (1) the head with its eye holes closed has exactly the neck's boundary edges left open, no edge used twice in one direction, and no
##     more flipped neighbours than the unclosed head; (2) a planar ring filled: max distance to the plane <= 1e-6 x ring radius; (3) a spherical cap hole
##     (radius 1, cap of 40 deg) filled: max abs(|p| - 1) over the fill's vertices <= 0.4 x the cap's sagitta; (4) the cap fill has 0 open edges at
##     the seam and 0 flipped neighbours. PLANTED: the same cap filled with fair = false reads above the 0.4 bound; one fill face reversed is counted flipped.
##   d the existing retopo suites (sretopo, i11, rigretopo) still pass unchanged (run with this suite by wtest).
##   e C++ = GDScript: no native path was added, so nothing to compare.
##   f UI + RECORD. Q on the head: a hole_<key> OptionButton per open edge, the status tooltip names each open edge's mode and each region's mode; choosing
##     the other mode for an eye hole changes the modes; Bake stores the record in the mesh meta; Ctrl+Z removes it, Ctrl+Y puts it back; to_dict/from_dict keeps it.
##   LOOK: docs/g16open/head_*.png: source | strokes + patches | baked quads.
extends SceneTree

const ST := preload("res://tests/sretopo_test.gd")
const SHOT_DIR := "res://docs/g16open/"
const Y_CUT := 1.64
var fails := 0
var _quit_done := false
var head: KMesh


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	if not c:
		fails += 1


func say(s: String) -> void:
	print("     " + s)


func _init() -> void:
	create_timer(300.0).timeout.connect(func():
		print("FAIL watchdog")
		fails += 1
		_finish())
	head = load_head()
	ok(head != null and head.verts.size() > 100, "fixture: head cut at %.2f m, eye holes punched (%d verts, %d faces, %d boundary edges)" % [Y_CUT, head.verts.size(), head.faces.size(), head.boundary_edge_count()])
	var bb := AABB(head.verts[0], Vector3.ZERO)
	for v in head.verts:
		bb = bb.expand(v)
	say("head bbox %s" % str(bb))
	for l in KMeshHoles.loops(head):
		var ys := []
		for v in l["verts"]:
			ys.append(head.verts[v].y)
		say("loop n=%d key=%d y %.3f..%.3f diam %.3f" % [l["n"], l["key"], ys.min(), ys.max(), l["diam"]])
	bar_modes()
	bar_side()
	bar_close()
	await bar_ui()
	_finish()


func _finish() -> void:
	if _quit_done:
		return
	_quit_done = true
	print("g16open: %d failures" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)


func load_head() -> KMesh:
	var sc := load("res://assets/mannequin.glb") as PackedScene
	var node: Node3D = sc.instantiate()
	var mis := node.find_children("*", "MeshInstance3D", true, false)
	var k := KMesh.new().from_array_mesh((mis[0] as MeshInstance3D).mesh as ArrayMesh, 0)
	node.free()
	var top := 0
	for i in k.verts.size():
		if k.verts[i].y > k.verts[top].y:
			top = i
	var eyes: Array = []   # the front-most vertex near each eye position
	for sx in [-1.0, 1.0]:
		var best := INF
		var bv := Vector3.ZERO
		for v in k.verts:
			if v.y > 1.70 and v.y < 1.78 and v.z > 0.03:
				var scr := absf(v.x - 0.035 * sx) + 0.5 * absf(v.y - 1.74)
				if scr < best:
					best = scr
					bv = v
		eyes.append(bv)
	print("     eyes at ", eyes)
	var keepf: Array = []
	for f in k.faces:
		var c := Vector3.ZERO
		for v in f:
			c += k.verts[v]
		c /= float(f.size())
		if c.y < Y_CUT:
			continue
		var punched := false
		for e in eyes:
			for v in f:
				if k.verts[v].distance_to(e) < 0.005:
					punched = true
		if not punched:
			keepf.append(f)
	var nb := {}
	for f in keepf:
		for c in f.size():
			var a: int = f[c]
			var b: int = f[(c + 1) % f.size()]
			if not nb.has(a):
				nb[a] = []
			if not nb.has(b):
				nb[b] = []
			nb[a].append(b)
			nb[b].append(a)
	var keep := {top: true}
	var stack := [top]
	while not stack.is_empty():
		var v: int = stack.pop_back()
		for w in nb.get(v, []):
			if not keep.has(w):
				keep[w] = true
				stack.append(w)
	var remap := {}
	var vs := PackedVector3Array()
	for i in k.verts.size():
		if keep.has(i):
			remap[i] = vs.size()
			vs.append(k.verts[i])
	var fs := []
	for f in keepf:
		if keep.has(f[0]):
			var g := PackedInt32Array()
			for v in f:
				g.append(remap[v])
			fs.append(g)
	var m := KMesh.new().from_arrays(vs, fs)
	for l in KMeshHoles.loops(m):   # the neck cut is flat: the zigzag of a centroid cut made the rim 1.7 x longer than the ring above it
		if l["n"] > 20:
			for v in l["verts"]:
				vs[v].y = Y_CUT
	m = KMesh.new().from_arrays(vs, fs)
	for rep in 2:   # a punched hole may pinch a vertex: take the faces round every vertex of a loop that is not simple
		var bad := {}
		for l in KMeshHoles.loops(m):
			if not l["simple"] and l["diam"] < 0.2:
				for v in l["verts"]:
					bad[v] = true
		if bad.is_empty():
			break
		var fs2 := []
		for f in m.faces:
			var hit := false
			for v in f:
				hit = hit or bad.has(v)
			if not hit:
				fs2.append(f)
		m = KMesh.new().from_arrays(m.verts.duplicate(), fs2)
	return m


func head_strokes(k: KMesh) -> Array:
	var out := []
	for y in [1.715]:
		var r := ST.ring_at(k, y)
		if r.size() > 3:
			out.append(r)
	var zh := ST.z_mid(k, 1.67, 2.0)
	out.append_array(ST.runs_between(k, Vector3(1, 0, 0), 1e-4, 1.0, 9.0, 0.03))
	out.append_array(ST.runs_between(k, Vector3(0, 0, 1), zh + 1e-4, 1.0, 9.0, 0.03))
	return out


func head_net(open: bool) -> KMeshRetopoNet:
	var net := KMeshRetopoNet.new()
	net.setup(head, 0.03, open)
	var sl := head_strokes(head)
	say("strokes: %s" % str(sl.map(func(s): return "%d pts %.2f m" % [s.size(), ST.poly_len(s)])))
	ST.put_strokes(net, sl)
	return net


func check_a(net: KMeshRetopoNet) -> Array:
	var bad := []
	var sk := net.skipped_regions()
	if not sk.is_empty():
		bad.append("%d skipped (%s)" % [sk.size(), String(sk[0]["reason"])])
	for p in net.patches:
		if p["valid"] and not ["none", "boundary_side", "closed_hole", "boundary_side+closed_hole"].has(String(p.get("mode", ""))):
			bad.append("a region without a mode")
	return bad


func bar_modes() -> void:
	var net := head_net(true)
	var st := net.stats()
	var modes := {}
	for p in net.patches:
		if p["valid"]:
			modes[p["mode"]] = int(modes.get(p["mode"], 0)) + 1
	say("open policy: %s; modes %s; notes %s; holes %s" % [str(st), str(modes), str(net.notes), str(net.holes.map(func(h): return "%d:%s n=%d diam=%.3f simple=%s" % [h["key"], h["mode"], h["n"], h["diam"], h["simple"]]))])
	for s in net.skipped_regions():
		say("   skipped: %s" % s["reason"])
	for i in net.patches.size():
		var p: Dictionary = net.patches[i]
		say("   patch %d valid=%s ok=%s n=%s mode=%s corners=%d reason=%s" % [i, str(p["valid"]), str(p["ok"]), str(p["n"]), str(p.get("mode")), p["corners"].size(), p["reason"]])
	say("   arcs: %s" % str(net.arcs.map(func(a): return "%d:%d" % [a["stroke"], a["count"]])))
	var bad := check_a(net)
	ok(bad.is_empty(), "a  0 regions skipped, every region has a mode %s" % str(bad))
	var neck_side := 0
	var eyes_close := 0
	for h in net.holes:
		if h["mode"] == "side" and h["n"] >= 20:
			neck_side += 1
		if h["mode"] == "close" and h["n"] < 20:
			eyes_close += 1
	ok(neck_side == 1 and eyes_close == 2, "a  defaults: neck = use the boundary as a side (%d), eye holes = close (%d)" % [neck_side, eyes_close])
	ok(int(modes.get("boundary_side", 0)) + int(modes.get("boundary_side+closed_hole", 0)) >= 1 and int(modes.get("closed_hole", 0)) + int(modes.get("boundary_side+closed_hole", 0)) >= 1, "a  regions of both kinds: %s" % str(modes))
	var old := head_net(false)
	var obad := check_a(old)
	ok(not obad.is_empty(), "a  PLANTED: the old path still skips them (%s)" % str(obad))


func dist_to_poly(p: Vector3, pl: PackedVector3Array) -> float:
	var best := INF
	for i in pl.size() - 1:
		var ab := pl[i + 1] - pl[i]
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 1e-18 else clampf((p - pl[i]).dot(ab) / l2, 0.0, 1.0)
		best = minf(best, p.distance_to(pl[i] + ab * t))
	return best


func bar_side() -> void:
	var net := head_net(true)
	var baked := net.bake()
	var neck := PackedVector3Array()
	for id in net.bstrokes:
		if (net.bstrokes[id] as PackedVector3Array).size() > 20:
			neck = net.bstrokes[id]
	ok(not baked.faces.is_empty() and not neck.is_empty(), "b  baked %d quads; neck polyline %d points" % [baked.faces.size(), neck.size()])
	var bv := {}
	for f in baked.faces:
		for c in f.size():
			var a: int = f[c]
			var b: int = f[(c + 1) % f.size()]
			if baked.find_half_edge(b, a) == -1:
				bv[a] = true
	var on_neck := 0
	var worst := 0.0
	for v in bv:
		var d := dist_to_poly(baked.verts[v], neck)
		if d <= 1e-6:
			on_neck += 1
		worst = maxf(worst, d)
	var expect := 0
	for a in net.arcs:
		if int(a["stroke"]) < 0:
			expect += int(a["count"])
	say("baked boundary verts %d, boundary arcs' edge counts %d, worst distance %s" % [bv.size(), expect, str(worst)])
	ok(worst <= 1e-6 and bv.size() > 0, "b  every baked boundary vertex is on the neck polyline within 1e-6 (worst %s)" % str(worst))
	ok(on_neck == expect, "b  the quads along the neck use exactly the boundary arcs' vertices (%d == %d)" % [on_neck, expect])
	if bv.size() > 0:
		var moved: int = bv.keys()[0]
		var w2 := dist_to_poly(baked.verts[moved] + Vector3(0, 1e-4, 0), neck)
		ok(w2 > 1e-6, "b  PLANTED: a vertex 1e-4 off the polyline reads %s > 1e-6" % str(w2))


func cap_hole(deg: float) -> KMesh:
	var s := KMeshPrims.uv_sphere(1.0, 48, 24)
	var fs := []
	var lim := cos(deg_to_rad(deg))
	for f in s.faces:
		var c := Vector3.ZERO
		for v in f:
			c += s.verts[v]
		c /= float(f.size())
		if c.normalized().y < lim:
			fs.append(f)
	return KMesh.new().from_arrays(s.verts.duplicate(), fs)


func bar_close() -> void:
	var lps := KMeshHoles.loops(head)
	var eyes := lps.filter(func(l): return l["mode"] == "close")
	var neck_n := 0
	for l in lps:
		if l["mode"] == "side":
			neck_n = l["n"]
	var closed := KMeshHoles.close(head, eyes)
	var es := KMeshHoles.edge_stats(closed.faces)
	var f0 := KMeshHoles.flipped(head.verts, head.faces)
	var f1 := KMeshHoles.flipped(closed.verts, closed.faces)
	ok(eyes.size() == 2 and es["open_edges"] == neck_n and es["same_direction_edges"] == 0 and f1 <= f0, "c1 head: %d eye holes closed, open edges left %d (neck %d), same-direction edges %d, flipped %d (before %d)" % [eyes.size(), es["open_edges"], neck_n, es["same_direction_edges"], f1, f0])
	var n := 24
	var ring := PackedVector3Array()
	var lp := PackedInt32Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		ring.append(Vector3(cos(a), 0.0, sin(a)))
		lp.append(i)
	var r := KMeshHoles.fill(ring, lp, true)
	var worst := 0.0
	for v in (r["verts"] as PackedVector3Array):
		worst = maxf(worst, absf(v.y))
	ok(worst <= 1e-6, "c2 planar ring (r = 1, %d new verts): max distance to the plane %s <= 1e-6" % [r["verts"].size() - n, str(worst)])
	var cap := cap_hole(40.0)
	var cl := KMeshHoles.loops(cap)
	var sag := 1.0 - cos(deg_to_rad(40.0))
	var res := []
	for fair in [true, false]:
		var rr := KMeshHoles.fill(cap.verts, cl[0]["verts"], fair, KMeshHoles._outside_nbrs(cap))
		var w := 0.0
		for i in range(cap.verts.size(), (rr["verts"] as PackedVector3Array).size()):
			w = maxf(w, absf(rr["verts"][i].length() - 1.0))
		res.append([w, rr])
	ok(res[0][0] <= 0.4 * sag, "c3 cap fill (fair): max abs(|p| - 1) = %.4f <= 0.4 x sagitta %.4f = %.4f (%d new verts)" % [res[0][0], sag, 0.4 * sag, res[0][1]["verts"].size() - cap.verts.size()])
	ok(res[1][0] > 0.4 * sag, "c3 PLANTED: the unfaired fill reads %.4f > %.4f" % [res[1][0], 0.4 * sag])
	var allf: Array = cap.faces.duplicate()
	allf.append_array(res[0][1]["faces"])
	var es2 := KMeshHoles.edge_stats(allf)
	var fl := KMeshHoles.flipped(res[0][1]["verts"], allf)
	var fl0 := KMeshHoles.flipped(cap.verts, cap.faces)
	ok(es2["open_edges"] == 0 and es2["same_direction_edges"] == 0 and fl <= fl0, "c4 cap fill watertight (open %d, same-direction %d), flipped %d (before %d)" % [es2["open_edges"], es2["same_direction_edges"], fl, fl0])
	var rev: Array = allf.duplicate()
	var last: PackedInt32Array = rev[rev.size() - 1]
	rev[rev.size() - 1] = PackedInt32Array([last[2], last[1], last[0]])
	var fl2 := KMeshHoles.flipped(res[0][1]["verts"], rev)
	ok(fl2 > fl, "c4 PLANTED: one fill face reversed counts %d flipped (> %d)" % [fl2, fl])


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func key(code: int, ctrl := false) -> InputEventKey:
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = code
	k.physical_keycode = code
	k.ctrl_pressed = ctrl
	return k


func shot() -> Image:
	await idle(4)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		img.convert(Image.FORMAT_RGBA8)
	return img


func look_at_mesh(mn: Node, yaw: float, pitch: float, zoom := 1.0) -> void:
	var ui = mn.kmed
	var c := Vector3.ZERO
	var pts := []
	for v in ui.mesh.verts:
		pts.append(ui.view.global_transform * v)
		c += pts[pts.size() - 1]
	c /= float(pts.size())
	var r := 0.0
	for p in pts:
		r = maxf(r, (p - c).length())
	mn._turn_to(yaw, pitch, r * 3.0 * zoom, c, false)
	await idle(3)


func bar_ui() -> void:
	var mn: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(mn)
	await idle(3)
	if mn.kmed != null and mn.kmed.on:
		mn.kmed.stop()
	mn._kmesh_edit_start()
	await idle(2)
	var ui = mn.kmed
	ui.stop()
	var k0 := KMesh.new().from_arrays(head.verts.duplicate(), head.faces.duplicate())
	ui.source = func() -> Dictionary: return {"mesh": k0}
	ui.start()
	await idle(3)
	ui.input(key(KEY_Q))
	var t := KMeshRetopoUI.of(ui)
	ok(t != null and t.on, "f  Q opens Retopo on the head")
	if t == null or not t.on:
		return
	t.net.edge_len = 0.03
	ST.put_strokes(t.net, head_strokes(head))
	t._refresh()
	var obs := t.holes_box.find_children("hole_*", "OptionButton", true, false)
	ok(obs.size() == 3, "f  one choice per open edge in the panel (%d), selections %s" % [obs.size(), str(obs.map(func(o): return o.get_item_text(o.selected)))])
	var tip: String = t.status.tooltip_text
	ok(tip.contains("Open edge") and tip.contains("boundary used as a side") and tip.contains("hole closed") and tip.contains("Region"), "f  the tooltip names each open edge's mode and each region's: %s" % tip.replace("\n", " | ").left(300))
	var before: Dictionary = t.net.stats()
	var eye: OptionButton = null
	for o in obs:
		if o.selected == 1:
			eye = o
	if eye != null:
		eye.select(0)
		eye.item_selected.emit(0)
		var mset := {}
		for p in t.net.patches:
			if p["valid"]:
				mset[p["mode"]] = int(mset.get(p["mode"], 0)) + 1
		ok(t.net.holes.filter(func(h): return h["mode"] == "side").size() == 2, "f  one eye hole switched to boundary as a side: modes now %s, stats %s (was %s)" % [str(mset), str(t.net.stats()), str(before)])
		eye.select(1)
		eye.item_selected.emit(1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var have_win := DisplayServer.get_name() != "headless"
	var rows := []
	var views := [[25.0, -8.0], [-140.0, -12.0]]
	if have_win:
		t.stop()
		await idle(2)
		for v in views:
			await look_at_mesh(mn, v[0], v[1], 1.2)
			rows.append([await shot()])
		ui.input(key(KEY_Q))
		t = KMeshRetopoUI.of(ui)
		t.net.edge_len = 0.03
		ST.put_strokes(t.net, head_strokes(head))
		t._refresh()
		for i in 2:
			await look_at_mesh(mn, views[i][0], views[i][1], 1.2)
			rows[i].append(await shot())
	var rec_before: Variant = ui.mesh.get_meta(KMeshRetopoNet.META) if ui.mesh.has_meta(KMeshRetopoNet.META) else null
	t.bake()
	await idle(3)
	var rec: Variant = ui.mesh.get_meta(KMeshRetopoNet.META) if ui.mesh.has_meta(KMeshRetopoNet.META) else null
	ok(rec_before == null and rec != null and rec["holes"].size() == 3 and rec["skipped"] == 0, "f  Bake stores the record in the mesh: %s" % str(rec).left(200))
	var tm := KMesh.new().from_arrays(head.verts.duplicate(), head.faces.duplicate())
	tm.set_meta(KMeshRetopoNet.META, rec)
	var bk := KMesh.new()
	var back := bk.from_dict(tm.to_dict())
	ok(back != null and back.has_meta(KMeshRetopoNet.META), "f  the record survives to_dict / from_dict (save) %s" % bk.last_error)
	ui.input(key(KEY_Z, true))
	await idle(1)
	ok(not ui.mesh.has_meta(KMeshRetopoNet.META), "f  Ctrl+Z removes the record with the bake (undo)")
	ui.input(key(KEY_Y, true))
	await idle(1)
	ok(ui.mesh.has_meta(KMeshRetopoNet.META), "f  Ctrl+Y puts it back (redo)")
	if have_win:
		for i in 2:
			await look_at_mesh(mn, views[i][0], views[i][1], 1.2)
			rows[i].append(await shot())
		var names := ["head_front.png", "head_back.png"]
		for i in 2:
			var imgs: Array = rows[i]
			if imgs.size() != 3 or imgs[0] == null:
				continue
			var w: int = imgs[0].get_width()
			var h: int = imgs[0].get_height()
			var cx := int(w * 0.2)
			var cw := int(w * 0.6)
			var out := Image.create(cw * 3, h, false, Image.FORMAT_RGBA8)
			for j in 3:
				out.blit_rect(imgs[j], Rect2i(cx, 0, cw, h), Vector2i(j * cw, 0))
			out.resize(out.get_width() / 2, out.get_height() / 2, Image.INTERPOLATE_LANCZOS)
			out.save_png(SHOT_DIR + names[i])
			say("LOOK: %s%s" % [SHOT_DIR, names[i]])
