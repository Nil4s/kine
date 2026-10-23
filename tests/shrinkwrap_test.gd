## godot --path . -s tests/shrinkwrap_test.gd     (ROADMAP_400 B13 shrinkwrap / project onto the body, scripts/kmesh_shrinkwrap.gd;
## run_all: shrinkwrap:w, the model preview part needs a window)
## Bars, stated before the run (except where marked AFTER A PROBE, with why):
##   1 SPHERE, NEAREST: a 41 x 41 plane 0.2 m above a 0.5 m sphere (64 x 32) wrapped with nearest: offset 0, +10 mm and
##     -5 mm: every vertex's distance to the sphere MESH (brute force over all its triangles, not the BVH) is |offset|
##     +- 0.1 mm, on the right side (+ outside the sphere, - inside); the same sphere with every face reversed (inside-out
##     winding) gives the same result: outside is read from the part's volume, not the winding. REVISED after the first
##     run, which had "max diff < 1e-9 m" and saw 0.07 mm: a plane vertex over the faceted sphere has near-tie nearest
##     points (distances equal to 2e-8 m, 0.07 mm apart) and the turned corner order rounds the other way. The bar is now
##     max diff < 0.5 mm (a winding read wrong would land 2 x offset = 10 to 20 mm away)
##   2 PROJECT along the vertex normal (both ways), max distance 0.25 m, offset 10 mm: every vertex whose sphere hit is
##     within reach (analytic, with 1 mm margin) lands |offset| +- 0.1 mm off the sphere mesh; every vertex out of reach is
##     untouched BIT FOR BIT; both groups are non-empty (the instrument can move). Axis mode, -Y ("in"), gives the same as
##     the normal mode within 1e-6 m; axis +Y only ("out") hits nothing and changes nothing
##   3 INFLUENCE: the selection (one half) moves only those (the rest bit for bit); a 0.5 weight channel moves every vertex
##     exactly half way (1e-6 m); a missing channel is refused with a message and nothing moves
##   4 THE BODY TARGET (the fighter's G01 skin): its parts' winding read from their volumes; >= 95 % of the kept triangles'
##     outward normals point AWAY from the nearest bone segment (the bone-axis check, independent of the volumes); the
##     parity test reads >= 99 % of skin points pushed 3 mm in as inside and >= 99 % pushed 3 mm out as outside. REVISED
##     after the first run (1744 / 1806 = 96.6 % out): a point 3 mm out of a finger can be inside the next finger, really;
##     the out half is now judged where the skin has room (bar 5's free ball >= 4.5 mm), the in half on every point
##   5 OFFSET 4 mm ON THE BODY: every skin vertex not buried in another part, lifted 0..10 mm off the skin, wrapped nearest
##     +4 mm. AFTER A PROBE (the first run): the mannequin's skin faces itself closer than 8 mm in places (between fingers,
##     the crotch): no point there can be 4 mm from all the skin. So the bar is split by ROOM, measured independently: the
##     free ball touching the skin point along its normal (shrinking-ball, against every part). Room (ball radius >= 4.5
##     mm): EVERY vertex is 4 +- 0.5 mm from the skin (the nearest of every part, the true union) AND outside by parity.
##     Tight: reported; >= 95 % still outside. (The instrument floor, "over 1500 room verts", was first 3000 and is
##     the count after the probe: 2359 room / 2366 tight: the hands are a third of the skin's verts.)
##   6 CURRENT POSE: the right elbow bent 90 deg (INSTRUMENT: a forearm skin vertex moves > 5 cm): the body target's
##     vertices equal the app's own CPU skinning (SkinPaint, the weight-paint positions) within 0.1 mm, and a vertex
##     wrapped near the bent forearm lands 4 +- 0.5 mm from the POSED skin and > 3 cm from where the rest skin was
##   7 TIME: 5,000 verts (the lifted body copy) nearest +4 mm onto the ~7k-vert body (target cached): under 2,500 ms
##     (shared cores, other agents running)
##   8 MODIFIER: a "shrinkwrap" modifier (other target = the sphere) on the plane: the base is unchanged (verts ==), the
##     evaluated mesh equals the one-shot op's result bit for bit; the stack (a channel name included) saves / loads exactly
##     and the loaded mesh evaluates the same
##   9 THE PREVIEW (main.tscn): the test cube, "Model: shrinkwrap onto the body" (the S box op) = ONE undo step; every
##     vertex with room ends 4 +- 0.5 mm from the posed skin (an independent world-space target) and every vertex outside;
##     Ctrl+Z (a real key) puts every vertex back bit for bit. The modifier added from the panel: one step, the base
##     untouched, the evaluated mesh wrapped; PLACEMENT: the panel with the shrinkwrap block (its channel field included)
##     lies inside the window
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func key(k: int, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = ctrl
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


## the distance from p to a mesh, every triangle tried (the reference the BVH is held to)
static func brute(p: Vector3, tris: PackedVector3Array) -> float:
	var best := INF
	for i in range(0, tris.size(), 3):
		var b := KMeshShrinkwrap.closest_bary(p, tris[i], tris[i + 1], tris[i + 2])
		best = minf(best, p.distance_squared_to(tris[i] * b.x + tris[i + 1] * b.y + tris[i + 2] * b.z))
	return sqrt(best)


static func tris_of(k: KMesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	for f in k.faces:
		var fp: PackedInt32Array = f
		for i in range(1, fp.size() - 1):
			out.append_array([k.verts[fp[0]], k.verts[fp[i]], k.verts[fp[i + 1]]])
	return out


## the free ball at skin point c along outward n (shrinking ball against the whole target): its radius
static func ball(t: KMeshShrinkwrap, c: Vector3, n: Vector3) -> float:
	var r := 0.05
	for i in 30:
		var h := t.nearest(c + n * r)
		if float(h["d"]) >= r - 1e-6:
			return r
		var q: Vector3 = h["p"]
		var den := 2.0 * n.dot(q - c)
		var rn := (c - q).length_squared() / den if den > 1e-12 else 0.0
		if rn >= r - 1e-7:
			return r
		r = maxf(rn, 0.0)
		if r < 1e-5:
			return r
	return r


static func reversed(k: KMesh) -> KMesh:
	var fs := []
	for f in k.faces:
		var fp: PackedInt32Array = f
		var g := PackedInt32Array([fp[0]])   # the same first corner: the same fan diagonals, only the winding turned
		for i in range(fp.size() - 1, 0, -1):
			g.append(fp[i])
		fs.append(g)
	return KMesh.new().from_arrays(k.verts, fs)


func the_plane() -> KMesh:
	var p := KMeshPrims.plane(0.8, 0.8, 40, 40)
	var V := p.verts
	for i in V.size():
		V[i].y = 0.7
	return KMesh.new().from_arrays(V, p.faces)


func _init() -> void:
	await idle(1)
	var R := 0.5
	var sphere := KMeshPrims.uv_sphere(R, 64, 32)
	var stris := tris_of(sphere)
	var sw := KMeshShrinkwrap.build(sphere)
	var swr := KMeshShrinkwrap.build(reversed(sphere))
	print("info: sphere target %d triangles, %d parts (%d wound inward), BVH %d nodes, built in %.1f ms" % [sw.tri_count(), sw.parts, sw.flipped, sw.bmin.size(), sw.build_ms])

	# ---- 1 nearest
	for off in [0.0, 0.01, -0.005]:
		var pl := the_plane()
		var r := sw.wrap_mesh(pl, {"offset": off})
		var pr := the_plane()
		swr.wrap_mesh(pr, {"offset": off})
		var worst := 0.0
		var side := true
		var same := 0.0
		for v in pl.verts.size():
			var d := brute(pl.verts[v], stris)
			worst = maxf(worst, absf(d - absf(off)))
			if off != 0.0:
				side = side and ((pl.verts[v].length() > R * 0.995) if off > 0.0 else (pl.verts[v].length() < R))
			same = maxf(same, pl.verts[v].distance_to(pr.verts[v]))
		ok(r["moved"] == 1681 and worst <= 0.0001 and side, "(1) nearest offset %+.0f mm: %d verts, worst |d - offset| %.4f mm (bar 0.1), on the %s side %s" % [off * 1000.0, r["moved"], worst * 1000.0, "outer" if off >= 0.0 else "inner", side])
		ok(same < 0.0005, "(1) the inside-out sphere gives the same (max diff %.4f mm, bar 0.5)" % (same * 1000.0))

	# ---- 2 project along the normal, max distance
	var md := 0.25
	var pl2 := the_plane()
	var before := pl2.verts.duplicate()
	var r2 := sw.wrap_mesh(pl2, {"mode": "normal", "offset": 0.01, "max_dist": md})
	var n_in := 0
	var n_out := 0
	var bad_in := 0.0
	var out_exact := true
	var amb := 0
	for v in before.size():
		var p := before[v]
		var rr := Vector2(p.x, p.z).length()
		var t := (0.7 - sqrt(R * R - rr * rr)) if rr < R else INF
		if t < md - 0.001:
			n_in += 1
			bad_in = maxf(bad_in, absf(brute(pl2.verts[v], stris) - 0.01))
		elif t > md + 0.001:
			n_out += 1
			out_exact = out_exact and pl2.verts[v] == p
		else:
			amb += 1
	ok(n_in > 50 and n_out > 50, "(2) INSTRUMENT: %d verts within reach, %d out of reach (%d within the 1 mm margin, not judged)" % [n_in, n_out, amb])
	ok(bad_in <= 0.0001, "(2) normal mode: every vertex in reach lands 10 mm off the sphere (worst miss %.4f mm, bar 0.1)" % (bad_in * 1000.0))
	ok(out_exact and int(r2["missed"]) >= n_out, "(2) every vertex out of reach is untouched bit for bit (%d left alone)" % r2["missed"])
	var pl3 := the_plane()
	sw.wrap_mesh(pl3, {"mode": "axis", "axis": Vector3.UP, "dirs": "in", "offset": 0.01, "max_dist": md})
	var dax := 0.0
	for v in pl3.verts.size():
		dax = maxf(dax, pl3.verts[v].distance_to(pl2.verts[v]))
	var pl4 := the_plane()
	var r4 := sw.wrap_mesh(pl4, {"mode": "axis", "axis": Vector3.UP, "dirs": "out", "offset": 0.01})
	ok(dax <= 1e-6 and r4["moved"] == 0 and pl4.verts == before, "(2) axis -Y = normal mode (max diff %s m); +Y only hits nothing (%d moved)" % [str(dax), r4["moved"]])

	# ---- 3 influence
	var pl5 := the_plane()
	var half := PackedInt32Array()
	for v in pl5.verts.size():
		if pl5.verts[v].x < 0.0:
			half.append(v)
	sw.wrap_mesh(pl5, {"offset": 0.01, "verts": half})
	var full_w := the_plane()
	sw.wrap_mesh(full_w, {"offset": 0.01})
	var sel_ok := true
	for v in before.size():
		sel_ok = sel_ok and (pl5.verts[v] == full_w.verts[v] if before[v].x < 0.0 else pl5.verts[v] == before[v])
	ok(sel_ok and half.size() > 100, "(3) selection (%d verts): those moved as a full wrap moves them, the rest bit for bit" % half.size())
	var pl6 := the_plane()
	pl6.add_attr("w", KMesh.AD_VERT, TYPE_FLOAT, 0.5)
	var hw := pl6.attr_data("w") as PackedFloat32Array
	hw.fill(0.5)
	pl6.set_attr_data("w", hw)
	sw.wrap_mesh(pl6, {"offset": 0.01, "channel": "w"})
	var hd := 0.0
	for v in before.size():
		hd = maxf(hd, pl6.verts[v].distance_to(before[v].lerp(full_w.verts[v], 0.5)))
	ok(hd <= 1e-6, "(3) a 0.5 weight channel moves every vertex half way (max miss %s m)" % str(hd))
	var pl7 := the_plane()
	var r7 := sw.wrap_mesh(pl7, {"channel": "nope"})
	ok(String(r7["error"]).contains("nope") and pl7.verts == before, "(3) a missing channel is refused: \"%s\"" % r7["error"])

	# ---- 8 modifier (pure part: the other target)
	KMeshShrinkwrap.set_other(sphere)
	var base := the_plane()
	var bv := base.verts.duplicate()
	KMeshModifiers.add(base, "shrinkwrap", {"target": 1, "offset": 0.01, "channel": ""})
	var ev := KMeshModifiers.evaluate(base)
	var op := the_plane()
	KMeshShrinkwrap.other().wrap_mesh(op, {"offset": 0.01})
	ok(base.verts == bv and ev.verts == op.verts and ev.verts != bv, "(8) modifier: the base unchanged, the evaluated mesh = the op's result bit for bit")
	KMeshModifiers.set_param(base, 0, "channel", "armour_w")
	KMeshModifiers.set_param(base, 0, "mode", 1)
	KMeshModifiers.set_param(base, 0, "max_dist", 0.25)
	var path := OS.get_user_data_dir().path_join("shrinkwrap_test.kmesh")
	var e := base.save(path)
	var ld := KMesh.load_file(path)
	ok(e == OK and ld != null and ld.modifiers == base.modifiers and String(ld.modifiers[0]["channel"]) == "armour_w",
		"(8) the stack saves and loads exactly: %s" % (str(ld.modifiers) if ld != null else "null"))
	base.modifiers[0]["channel"] = ""
	ld.modifiers[0]["channel"] = ""
	ok(ld != null and KMeshModifiers.evaluate(ld).verts == KMeshModifiers.evaluate(base).verts, "(8) the loaded mesh evaluates to the same verts")
	ok(KMeshModifiers.describe(base.modifiers[0]).begins_with("Shrinkwrap other normal"), "(8) the panel line: %s" % KMeshModifiers.describe(base.modifiers[0]))

	await body_part()
	print("shrinkwrap: %d failed" % fails)
	quit(1 if fails > 0 else 0)


func body_part() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.get("ui_tour") != null and m.ui_tour != null:
		m.ui_tour.visible = false
	var t0 := Time.get_ticks_msec()
	var sw := KMeshShrinkwrap.body(m)
	var first_ms := Time.get_ticks_msec() - t0
	var full := sw.full if sw.full != null else sw
	var nb := 0
	var npart := 0
	for b in sw.buried:
		nb += 1 if b == 1 else 0
		npart += 1 if b == 2 else 0
	print("info: the body target: %d triangles in %d parts (%d wound inward, turned), %d buried in another part (left out), %d partly; first build %d ms (rest + pose + buried mask), BVH %.0f ms" % [full.tri_count(), sw.parts, sw.flipped, nb, npart, first_ms, sw.build_ms])

	# ---- 4 bone axis, parity
	var p0 := m.pieces.values()[0] as MeshInstance3D
	var to_body := p0.global_transform.affine_inverse()
	var segs := []
	for s in KMeshBody.segments_from_skeleton(m.skel):
		segs.append([to_body * (s["a"] as Vector3), to_body * (s["b"] as Vector3)])
	var away := 0
	for j in sw.tri_count():
		var c := (sw.tp[j * 3] + sw.tp[j * 3 + 1] + sw.tp[j * 3 + 2]) / 3.0
		var bd := INF
		var bq := Vector3.ZERO
		for s in segs:
			var q := Geometry3D.get_closest_point_to_segment(c, s[0], s[1])
			if c.distance_squared_to(q) < bd:
				bd = c.distance_squared_to(q)
				bq = q
		away += 1 if sw.tn[j].dot(c - bq) > 0.0 else 0
	ok(away >= 0.95 * sw.tri_count(), "(4) bone axis: %.1f %% of the kept triangles' outward normals point away from the nearest bone (bar 95; the file's own winding would give the rest)" % (100.0 * away / sw.tri_count()))
	var pin := 0
	var pout := 0
	var np := 0
	var nr := 0
	for j in range(0, sw.tri_count(), 5):
		var c := (sw.tp[j * 3] + sw.tp[j * 3 + 1] + sw.tp[j * 3 + 2]) / 3.0
		np += 1
		pin += 1 if sw.inside(c - sw.tn[j] * 0.003) else 0
		if ball(full, c, sw.tn[j]) >= 0.0045:   # REVISED after the first run, see the header
			nr += 1
			pout += 0 if sw.inside(c + sw.tn[j] * 0.003) else 1
	ok(pin >= 0.99 * np and pout >= 0.99 * nr, "(4) parity: %d / %d skin points 3 mm in read inside, %d / %d with room 3 mm out read outside (bar 99 %%)" % [pin, np, pout, nr])

	# ---- 5 offset 4 mm on the body
	var k := KMeshShrinkwrap.posed_body(m)
	var V := k.verts.duplicate()
	var vis := PackedInt32Array()
	var room := {}
	for v in V.size():
		var h := full.nearest(V[v])
		var n := full.normal_at(h["t"], h["b"])
		if sw.inside(V[v] + n * 1e-4):
			continue
		vis.append(v)
		room[v] = ball(full, h["p"], n) >= 0.0045
		V[v] += n * 0.01 * (0.5 + 0.5 * sin(v * 1.7))
	var src := KMesh.new().from_arrays(V, k.faces)
	var r5 := sw.wrap_mesh(src, {"offset": 0.004, "verts": vis})
	var n_room := 0
	var worst := 0.0
	var room_in := 0
	var n_tight := 0
	var tight_out := 0
	var tight_worst := 0.0
	for v in vis:
		var d: float = full.nearest(src.verts[v])["d"]
		var ins := sw.inside(src.verts[v])
		if room[v]:
			n_room += 1
			worst = maxf(worst, absf(d - 0.004))
			room_in += 1 if ins else 0
		else:
			n_tight += 1
			tight_out += 0 if ins else 1
			tight_worst = maxf(tight_worst, absf(d - 0.004))
	ok(n_room > 1500 and worst <= 0.0005 and room_in == 0, "(5) %d skin verts with room, wrapped +4 mm: worst |d - 4 mm| %.3f mm (bar 0.5), %d inside (bar 0)" % [n_room, worst * 1000.0, room_in])
	ok(tight_out >= 0.95 * n_tight, "(5) %d tight verts (the skin faces itself closer than 9 mm: fingers, crotch): %d outside (bar 95 %%), worst |d - 4 mm| %.2f mm (no bar: no room)" % [n_tight, tight_out, tight_worst * 1000.0])
	print("info: %d of %d verts are buried in another part (not skin) and were not wrapped; the wrap took %.0f ms" % [V.size() - vis.size(), V.size(), r5["ms"]])

	# ---- 7 time
	var sel5 := PackedInt32Array()
	for v in 5000:
		sel5.append(v)
	var src7 := KMesh.new().from_arrays(V, k.faces)
	var t7 := Time.get_ticks_usec()
	var sw7 := KMeshShrinkwrap.body(m)
	var r7 := sw7.wrap_mesh(src7, {"offset": 0.004, "verts": sel5})
	var ms7 := (Time.get_ticks_usec() - t7) / 1000.0
	ok(r7["moved"] == 5000 and ms7 < 2500.0, "(7) TIME: 5,000 verts onto the %d-vert body in %.0f ms (bar 2500; the target cached: same object %s)" % [k.verts.size(), ms7, sw7 == sw])

	# ---- 6 the current pose
	var skin := BaseBody.skin_of(m)
	var krest := BaseBody.read(m)
	var la := krest.attr_data("skin:lowerarm_r") as PackedFloat32Array
	var fv := -1
	for v in vis:
		if la[v] > 0.99 and room[v]:
			fv = v
			break
	var rest_p := k.verts[fv]
	var rest_sw := sw
	m.B.ang["lowerarm_r"] = Vector3(90.0, m.B.ang["lowerarm_r"].y, m.B.ang["lowerarm_r"].z)
	m._refresh()
	await process_frame
	SkinPaint.refresh(m.wp)
	var kp := KMeshShrinkwrap.posed_body(m)
	var moved := kp.verts[fv].distance_to(rest_p)
	ok(moved > 0.05, "(6) INSTRUMENT: the forearm vertex %d moved %.1f cm with the 90 deg elbow" % [fv, moved * 100.0])
	var at := {}
	for v in kp.verts.size():
		at[krest.verts[v]] = v
	var dev := 0.0
	var seen := 0
	for s in m.wp["surfs"]:
		var rv: PackedVector3Array = s["verts"]
		var pv: PackedVector3Array = s["pos"]
		for i in rv.size():
			var v: int = at.get(rv[i], -1)
			if v >= 0:
				dev = maxf(dev, kp.verts[v].distance_to(pv[i]))
				seen += 1
	ok(seen > 6000 and dev <= 0.0001, "(6) the posed body target = the app's CPU skinning (SkinPaint) within %.4f mm over %d verts (bar 0.1 mm)" % [dev * 1000.0, seen])
	var swp := KMeshShrinkwrap.body(m)
	var hp := swp.nearest(kp.verts[fv])
	var probe := KMesh.new().from_arrays(PackedVector3Array([kp.verts[fv] + swp.normal_at(hp["t"], hp["b"]) * 0.008]), [])
	swp.wrap_mesh(probe, {"offset": 0.004})
	var pfull := swp.full if swp.full != null else swp
	var dpost: float = pfull.nearest(probe.verts[0])["d"]
	var drest: float = (rest_sw.full if rest_sw.full != null else rest_sw).nearest(probe.verts[0])["d"]
	ok(swp != rest_sw and absf(dpost - 0.004) <= 0.0005 and drest > 0.03, "(6) a vertex wrapped by the bent forearm: %.2f mm from the posed skin (bar 4 +- 0.5), %.1f cm from the rest skin (bar > 3)" % [dpost * 1000.0, drest * 100.0])
	m.B.ang["lowerarm_r"] = Vector3(0.0, m.B.ang["lowerarm_r"].y, m.B.ang["lowerarm_r"].z)
	m._refresh()
	await process_frame

	# ---- 9 the preview
	m._kmesh_edit_start()
	await idle(3)
	var ui: KMeshEditUI = m.kmed
	ui.sel.clear()
	var v0 := ui.mesh.verts.duplicate()
	var n0 := ui.undo.steps.size()
	var said := MeshTools.op("shrinkwrap", m)
	await idle(2)
	# the independent check: the posed skin and the cube in WORLD space
	var kw := KMeshShrinkwrap.posed_body(m)
	var Wv := kw.verts.duplicate()
	for i in Wv.size():
		Wv[i] = p0.global_transform * Wv[i]
	var tw := KMeshShrinkwrap.build(KMesh.new().from_arrays(Wv, kw.faces))
	var twf := tw.full if tw.full != null else tw
	var wv := ui.view.global_transform
	var w_room := 0
	var w_worst := 0.0
	var w_in := 0
	for p in ui.mesh.verts:
		var q: Vector3 = wv * p
		var h := twf.nearest(q)
		var d := float(h["d"])
		w_in += 1 if tw.inside(q) else 0
		var hs := twf.nearest(h["p"] + (q - h["p"]).normalized() * 1e-5)
		if ball(twf, hs["p"], (q - h["p"]).normalized()) >= 0.0045:
			w_room += 1
			w_worst = maxf(w_worst, absf(d - 0.004))
	ok(ui.undo.steps.size() == n0 + 1 and said.contains("shrinkwrapped"), "(9) the S box op = one undo step (%d): %s" % [ui.undo.steps.size() - n0, said])
	ok(w_room > 0.8 * ui.mesh.verts.size() and w_worst <= 0.0005 and w_in == 0, "(9) the cube on the posed skin: %d / %d verts with room, worst |d - 4 mm| %.3f mm (bar 0.5); %d inside (bar 0)" % [w_room, ui.mesh.verts.size(), w_worst * 1000.0, w_in])
	await key(KEY_Z, true)
	ok(ui.mesh.verts == v0, "(9) Ctrl+Z (a real key) puts every vertex back bit for bit")
	var n1 := ui.undo.steps.size()
	var i := ui.mods.add("shrinkwrap")
	await idle(3)
	var evm: KMesh = ui.mods.evaluated
	var e_worst := 0.0
	if evm != null:
		for p in evm.verts:
			var q: Vector3 = wv * p
			var h := twf.nearest(q)
			var hs := twf.nearest(h["p"] + (q - h["p"]).normalized() * 1e-5)
			if ball(twf, hs["p"], (q - h["p"]).normalized()) >= 0.0045:
				e_worst = maxf(e_worst, absf(float(h["d"]) - 0.004))
	ok(i == 0 and ui.undo.steps.size() == n1 + 1 and ui.mesh.verts == v0 and evm != null and evm.verts != v0 and e_worst <= 0.0005,
		"(9) the modifier from the panel: one step (%d), the base untouched, the evaluated mesh on the skin (worst %.3f mm with room)" % [ui.undo.steps.size() - n1, e_worst * 1000.0])
	var win := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var pr: Rect2 = ui.mods.panel.get_global_rect()
	var chf := ui.mods._list.find_child("mod_0_channel", true, false) as Control
	ok(chf is LineEdit and win.encloses(pr) and pr.encloses(chf.get_global_rect().grow(-1)), "(9) PLACEMENT: the panel %s with the shrinkwrap block (channel field %s) inside the window %s" % [pr, chf.get_global_rect() if chf != null else Rect2(), win.size])
	await key(KEY_ESCAPE)
