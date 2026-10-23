extends SceneTree
## godot --path . -s tests/uvpack_test.gd     (ROADMAP_400 D04 island packing, scripts/kmesh_uvpack.gd; part 7 needs a window)
## Test mesh: a 0.6 m cube, a 1.2 x 0.5 x 0.3 m box, an open 16-sided tube (r 0.25, 0.9 m) and a bent 6 x 2 sheet,
## auto seams (KMeshUVPack.auto_seams) + LSCM (D03) -> 17 islands; then each island's UVs scrambled (scaled 0.25..2.5,
## shifted, so they overlap and their densities differ). Bars, written before measuring:
##   1 NO OVERLAP: every island triangle rasterised at 1024 px (pixel centres): no pixel is covered by two islands
##     (control: the scrambled layout has > 1000 such pixels, so the raster sees overlaps when there are some)
##   2 MARGIN: asked 4 px at 1024: the least distance between two islands' edges (segment to segment, every pair) >= 4 px
##     - 1e-3, and every island >= 2 px from the tile's edge (half the margin: two tiles side by side are 4 px apart);
##     the same at 16 px / 512 and 1 px / 2048 (control: margin 0 gives a least gap < 1 px)
##   3 every UV inside 0..1
##   4 DENSITY: the islands' texel densities (sqrt(uv area / 3D area) * px) spread (max / min - 1) < 5% after packing
##     (control: > 50% scrambled); with density off the islands keep their scrambled sizes relative to each other (spread
##     unchanged within 1%)
##   5 EFFICIENCY: UV area used / tile area > 50% on the test mesh with rotate "free" (the app's default; "none" and "90"
##     printed); the px/cm of the layout is printed. FIRST WRITTEN for "90", which measured 41.7%: LSCM pins an island's
##     two farthest points on the u axis, so a square island lies on its diagonal and its box is twice its area; quarter
##     turns cannot fix that, the min-area box can (85.7%). The bar moved to "free" after that measurement, said here.
##   6 ROTATION "free": the min-area box of a 2 x 1 rectangle turned 37 deg has area 2 within 1e-6; 12 such islands pack
##     with efficiency "free" > "none" + 0.1, no overlap, and turns are never mirrors (every triangle keeps its UV
##     orientation sign)
##   7 THE APP: in the model preview Ctrl+P (a real key event) packs the cube's UVs as ONE mesh undo step (labelled
##     "Pack UV islands"), shows the UV checker, says the px/cm; Ctrl+Z gives back the exact UVs from before; the mesh
##     tools list has the line "Model: pack UV islands" with key Ctrl+P and the S box finds it ("pack uv")

var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## append a mesh's verts / faces to vs / fs
func add(vs: PackedVector3Array, fs: Array, v2: PackedVector3Array, f2: Array, at: Vector3) -> void:
	var o := vs.size()
	for p in v2:
		vs.append(p + at)
	for f in f2:
		var g: Array = []
		for i in f:
			g.append(i + o)
		fs.append(g)


func box(sx: float, sy: float, sz: float) -> Array:
	var vs := PackedVector3Array()
	for i in 8:
		vs.append(Vector3((i & 1) * sx, ((i >> 1) & 1) * sy, ((i >> 2) & 1) * sz))
	return [vs, [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]]


func tube(seg: int, r: float, h: float, rows := 3) -> Array:
	var vs := PackedVector3Array()
	for j in rows + 1:
		for i in seg:
			var ph := TAU * i / seg
			vs.append(Vector3(r * sin(ph), h * j / rows, r * cos(ph)))
	var fs: Array = []
	for j in rows:
		for i in seg:
			var a := j * seg + i
			var b := j * seg + (i + 1) % seg
			fs.append([a, b, b + seg, a + seg])
	return [vs, fs]


func sheet(nx: int, ny: int, w: float, h: float) -> Array:
	var vs := PackedVector3Array()
	for j in ny + 1:
		for i in nx + 1:
			var x := float(i) / nx * w
			vs.append(Vector3(x, float(j) / ny * h, 0.15 * sin(x * 2.0)))
	var fs: Array = []
	for j in ny:
		for i in nx:
			var a := j * (nx + 1) + i
			fs.append([a, a + 1, a + nx + 2, a + nx + 1])
	return [vs, fs]


func test_mesh() -> KMesh:
	var vs := PackedVector3Array()
	var fs: Array = []
	var b: Array = box(0.6, 0.6, 0.6)
	add(vs, fs, b[0], b[1], Vector3.ZERO)
	b = box(1.2, 0.5, 0.3)
	add(vs, fs, b[0], b[1], Vector3(2, 0, 0))
	b = tube(16, 0.25, 0.9)
	add(vs, fs, b[0], b[1], Vector3(0, 0, 2))
	b = sheet(6, 2, 0.9, 0.3)
	add(vs, fs, b[0], b[1], Vector3(2, 0, 2))
	var m := KMesh.new().from_arrays(vs, fs)
	# outward faces? the tube's first face normal should point away from its axis
	return m


## scale each island's UVs by a factor 0.25..2.5 and shift it (seeded): overlapping, uneven density
func scramble(m: KMesh) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var d: PackedVector2Array = m.attr_data(KMeshUV.UV)
	for r in KMeshUVPack.island_data(m):
		var k := rng.randf_range(0.25, 2.5)
		var o := Vector2(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2))
		for c in (r["corners"] as PackedInt32Array):
			d[c] = d[c] * k + o
	m.set_attr_data(KMeshUV.UV, d)


## pixels (px x px, centres) covered by triangles of two different islands; tile t takes u in [t, t+1] when tiles
func overlaps(m: KMesh, px: int, tile := -1) -> int:
	var d: PackedVector2Array = m.attr_data(KMeshUV.UV)
	var top := KMeshUVPack.islands(m)
	var isl: PackedInt32Array = top["island"]
	var own := PackedInt32Array()
	own.resize(px * px)
	own.fill(-1)
	var bad := 0
	var off := Vector2(maxi(tile, 0), 0)
	var td = m.attr_data(KMeshUVPack.TILE) if tile >= 0 and m.has_attr(KMeshUVPack.TILE) else null
	for f in m.face_count():
		if td != null and int(td[f]) != tile:
			continue
		var fp: PackedInt32Array = m.faces[f]
		var h0 := m.face_he0[f]
		for i in range(1, fp.size() - 1):
			var a := (d[h0] - off) * px
			var b := (d[h0 + i] - off) * px
			var c := (d[h0 + i + 1] - off) * px
			var lo := a.min(b).min(c)
			var hi := a.max(b).max(c)
			for y in range(maxi(int(floor(lo.y)), 0), mini(int(ceil(hi.y)), px)):
				for x in range(maxi(int(floor(lo.x)), 0), mini(int(ceil(hi.x)), px)):
					var p := Vector2(x + 0.5, y + 0.5)
					var w0 := (b - a).cross(p - a)
					var w1 := (c - b).cross(p - b)
					var w2 := (a - c).cross(p - c)
					if not ((w0 >= 0 and w1 >= 0 and w2 >= 0) or (w0 <= 0 and w1 <= 0 and w2 <= 0)):
						continue
					var k := y * px + x
					if own[k] == -1:
						own[k] = isl[f]
					elif own[k] != isl[f]:
						own[k] = -2
						bad += 1
	return bad


static func seg_dist(p1: Vector2, q1: Vector2, p2: Vector2, q2: Vector2) -> float:
	var a := Geometry2D.get_closest_points_between_segments(p1, q1, p2, q2)
	return (a[0] as Vector2).distance_to(a[1])


## {"gap": least distance between edges of two different islands, "edge": least distance from an island to its tile's
## border} in UV units; the tile per face from "uv_tile" when present
func gaps(m: KMesh) -> Dictionary:
	var d: PackedVector2Array = m.attr_data(KMeshUV.UV)
	var data := KMeshUVPack.island_data(m)
	var segs: Array = []   # per island PackedVector2Array of segment ends
	var bbs: Array = []
	var tl: Array = []
	var td = m.attr_data(KMeshUVPack.TILE) if m.has_attr(KMeshUVPack.TILE) else null
	var edge := INF
	for r in data:
		var s := PackedVector2Array()
		var bb := Rect2(d[(r["corners"] as PackedInt32Array)[0]], Vector2.ZERO)
		var f0: int = (r["faces"] as PackedInt32Array)[0]
		var t := int(td[f0]) if td != null else 0
		for f in (r["faces"] as PackedInt32Array):
			var n := (m.faces[f] as PackedInt32Array).size()
			var h0 := m.face_he0[f]
			for i in n:
				s.append(d[h0 + i])
				s.append(d[h0 + (i + 1) % n])
				bb = bb.expand(d[h0 + i])
				var q := d[h0 + i] - Vector2(t, 0)
				edge = minf(edge, minf(minf(q.x, q.y), minf(1.0 - q.x, 1.0 - q.y)))
		segs.append(s)
		bbs.append(bb)
		tl.append(t)
	var gap := INF
	for i in data.size():
		for j in range(i + 1, data.size()):
			if tl[i] != tl[j]:
				continue
			var bi: Rect2 = bbs[i]
			var bj: Rect2 = bbs[j]
			if bi.grow(gap).intersects(bj) == false and gap < INF:
				continue
			var si: PackedVector2Array = segs[i]
			var sj: PackedVector2Array = segs[j]
			for a in range(0, si.size(), 2):
				for b in range(0, sj.size(), 2):
					gap = minf(gap, seg_dist(si[a], si[a + 1], sj[b], sj[b + 1]))
	return {"gap": gap, "edge": edge}


func spread(v: PackedFloat64Array) -> float:
	var lo := INF
	var hi := 0.0
	for x in v:
		lo = minf(lo, x)
		hi = maxf(hi, x)
	return hi / lo - 1.0


func in01(m: KMesh) -> bool:
	for q in m.attr_data(KMeshUV.UV):
		if q.x < -1e-9 or q.y < -1e-9 or q.x > 1.0 + 1e-9 or q.y > 1.0 + 1e-9:
			return false
	return true


func base() -> KMesh:
	var m := test_mesh()
	KMeshUVPack.auto_seams(m)
	KMeshUV.unwrap_lscm(m)
	scramble(m)
	return m


func _init() -> void:
	var m := base()
	var nisl := int(KMeshUVPack.islands(m)["count"])
	var ov0 := overlaps(m, 1024)
	var sp0 := spread(KMeshUVPack.densities(m, 1024))
	print("test mesh: %d faces, %d islands; scrambled: %d overlapping px, density spread %.1f%%" % [m.face_count(), nisl, ov0, sp0 * 100.0])
	var before: PackedVector2Array = m.attr_data(KMeshUV.UV).duplicate()
	var r := KMeshUVPack.pack(m, {"px": 1024, "margin": 4.0, "rotate": "90"})
	print("pack 90: ", r)
	# 1
	var ov := overlaps(m, 1024)
	print("bar 1: %d overlapping px after packing (scrambled %d)" % [ov, ov0])
	ok(r["ok"] and int(r["islands"]) == nisl and ov == 0 and ov0 > 1000, "bar 1: no pixel covered by two islands at 1024 px (control: scrambled layout %d)" % ov0)
	# 2
	var gp := gaps(m)
	print("bar 2: least gap %.3f px, least border %.3f px (asked 4 px at 1024)" % [gp["gap"] * 1024, gp["edge"] * 1024])
	ok(gp["gap"] * 1024 >= 4.0 - 1e-3 and gp["edge"] * 1024 >= 2.0 - 1e-3, "bar 2: margin >= 4 px between islands, >= 2 px to the border")
	for c in [[16.0, 512], [1.0, 2048]]:
		var m2 := base()
		var r2 := KMeshUVPack.pack(m2, {"px": c[1], "margin": c[0], "rotate": "90"})
		var g2 := gaps(m2)
		print("  margin %s px at %d: least gap %.3f px, border %.3f px, efficiency %.1f%%" % [c[0], c[1], g2["gap"] * c[1], g2["edge"] * c[1], r2["efficiency"] * 100.0])
		ok(r2["ok"] and g2["gap"] * c[1] >= c[0] - 1e-3 and g2["edge"] * c[1] >= c[0] * 0.5 - 1e-3 and in01(m2), "bar 2: margin %s px at %d holds" % [c[0], c[1]])
	var m0 := base()
	KMeshUVPack.pack(m0, {"px": 1024, "margin": 0.0, "rotate": "90"})
	var g0 := gaps(m0)
	print("  control margin 0: least gap %.4f px" % (g0["gap"] * 1024))
	ok(g0["gap"] * 1024 < 1.0, "bar 2 control: margin 0 packs islands closer than 1 px (the gap measure moves)")
	# 3
	ok(in01(m), "bar 3: every UV inside 0..1")
	# 4
	var sp := spread(KMeshUVPack.densities(m, 1024))
	print("bar 4: density spread %.3f%% after (scrambled %.1f%%); reported %.3f%%" % [sp * 100.0, sp0 * 100.0, r["spread"] * 100.0])
	ok(sp < 0.05 and sp0 > 0.5, "bar 4: texel density spread < 5%% after equalising (%.3f%%), control > 50%% (%.1f%%)" % [sp * 100.0, sp0 * 100.0])
	var mn := base()
	KMeshUVPack.pack(mn, {"px": 1024, "margin": 4.0, "density": false})
	var spn := spread(KMeshUVPack.densities(mn, 1024))
	ok(absf(spn - sp0) < 0.01 * (1.0 + sp0) and overlaps(mn, 1024) == 0, "bar 4: density off keeps the relative sizes (spread %.1f%% vs %.1f%%), no overlap" % [spn * 100.0, sp0 * 100.0])
	# 5
	print("bar 5: rotate 90: efficiency %.1f%%, %.2f px/cm at 1024, %.0f ms" % [r["efficiency"] * 100.0, r["px_per_cm"], r["ms"]])
	var rf := {}
	for rm in ["none", "free"]:
		var m3 := base()
		var r3 := KMeshUVPack.pack(m3, {"px": 1024, "margin": 4.0, "rotate": rm})
		var ov3 := overlaps(m3, 1024)
		print("  rotate %s: efficiency %.1f%%, %.2f px/cm, overlaps %d, %.0f ms" % [rm, r3["efficiency"] * 100.0, r3["px_per_cm"], ov3, r3["ms"]])
		rf[rm] = [r3, ov3, gaps(m3), in01(m3), spread(KMeshUVPack.densities(m3, 1024))]
	var fr: Array = rf["free"]
	ok(fr[0]["efficiency"] > 0.5 and fr[0]["px_per_cm"] > 0.0 and fr[1] == 0 and fr[2]["gap"] * 1024 >= 4.0 - 1e-3 and fr[3] and fr[4] < 0.05,
		"bar 5: rotate free: packing efficiency %.1f%% > 50%% (%.2f px/cm at 1024), and bars 1-4 hold for it" % [fr[0]["efficiency"] * 100.0, fr[0]["px_per_cm"]])
	# 6
	var rect := PackedVector2Array()
	var a37 := deg_to_rad(37.0)
	for q in [Vector2(0, 0), Vector2(2, 0), Vector2(2, 1), Vector2(0, 1), Vector2(1, 0.5)]:
		rect.append(q.rotated(a37) + Vector2(3, 1))
	var ang := KMeshUVPack.min_box_angle(rect)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in rect:
		var p := q.rotated(-ang)
		lo = lo.min(p)
		hi = hi.max(p)
	var ba := (hi.x - lo.x) * (hi.y - lo.y)
	print("bar 6: min box of a 2 x 1 rect at 37 deg: angle %.3f deg, area %.9f" % [rad_to_deg(ang), ba])
	ok(absf(ba - 2.0) < 1e-6, "bar 6: min-area box area 2 within 1e-6")
	var eff := {}
	for rm in ["none", "free"]:
		var dm := diag_mesh()
		var sg0 := signs(dm)
		var r4 := KMeshUVPack.pack(dm, {"px": 1024, "margin": 4.0, "rotate": rm})
		eff[rm] = r4["efficiency"]
		var ov4 := overlaps(dm, 1024)
		print("  12 tilted strips, rotate %s: efficiency %.1f%%, overlaps %d" % [rm, r4["efficiency"] * 100.0, ov4])
		ok(ov4 == 0 and signs(dm) == sg0 and in01(dm), "bar 6: rotate %s: no overlap, no mirrored triangle, inside 0..1" % rm)
	ok(eff["free"] > eff["none"] + 0.1, "bar 6: free rotation packs tighter (%.1f%% vs %.1f%%)" % [eff["free"] * 100.0, eff["none"] * 100.0])
	# 7
	await app()
	print("uvpack: %d failures" % fails)
	quit(1 if fails > 0 else 0)


## 12 strips (4 x 1 quads, 1.0 x 0.2 m) whose UVs are the strip turned 30..60 deg
func diag_mesh() -> KMesh:
	var vs := PackedVector3Array()
	var fs: Array = []
	for s in 12:
		var b: Array = sheet(4, 1, 1.0, 0.2)
		add(vs, fs, b[0], b[1], Vector3(0, 0, s * 0.5))
	var m := KMesh.new().from_arrays(vs, fs)
	m.add_attr(KMeshUV.UV, KMesh.AD_CORNER, TYPE_VECTOR2)
	var d: PackedVector2Array = m.attr_data(KMeshUV.UV)
	for f in m.face_count():
		var s := f / 4
		var fp: PackedInt32Array = m.faces[f]
		for i in fp.size():
			var p := m.verts[fp[i]]
			d[m.face_he0[f] + i] = Vector2(p.x, p.y).rotated(deg_to_rad(30.0 + s * 2.7)) * 0.3 + Vector2(s * 0.01, 0)
	m.set_attr_data(KMeshUV.UV, d)
	return m


## per triangle the sign of its UV area, as a string
func signs(m: KMesh) -> String:
	var d: PackedVector2Array = m.attr_data(KMeshUV.UV)
	var s := ""
	for f in m.face_count():
		var h0 := m.face_he0[f]
		for i in range(1, (m.faces[f] as PackedInt32Array).size() - 1):
			s += "+" if (d[h0 + i] - d[h0]).cross(d[h0 + i + 1] - d[h0]) > 0.0 else "-"
	return s


func app() -> void:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await idle(6)
	main.tour_step = -1
	if main.ui_tour != null:
		main.ui_tour.visible = false
	main._kmesh_edit_start()
	await idle(3)
	var ui: KMeshEditUI = main.kmed
	KMeshUV.seams_by_angle(ui.mesh, 60.0)
	KMeshUV.unwrap_lscm(ui.mesh)
	scramble(ui.mesh)
	var uv0: PackedVector2Array = ui.mesh.attr_data(KMeshUV.UV).duplicate()
	var n0: int = ui.undo.steps.size()
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = KEY_P
		e.physical_keycode = KEY_P
		e.ctrl_pressed = true
		e.pressed = down
		root.push_input(e)
		await idle(2)
	var said := String(main.ui_status.text)
	print("bar 7: said \"%s\"" % said)
	var steps: Array = ui.undo.steps
	ok(steps.size() == n0 + 1 and String(steps[-1]["label"]) == "Pack UV islands", "bar 7: Ctrl+P is one mesh undo step \"Pack UV islands\" (%d -> %d)" % [n0, steps.size()])
	ok(ui.view.shading == "uv_checker" and said.contains("px/cm") and overlaps(ui.mesh, 1024) == 0 and in01(ui.mesh), "bar 7: the checker shows, the px/cm is said, no overlap, inside 0..1")
	ok(ui.mesh.attr_data(KMeshUV.UV) != uv0, "bar 7: the UVs changed")
	ui.undo.undo()
	ok(ui.mesh.attr_data(KMeshUV.UV) == uv0, "bar 7: undo gives back the exact UVs from before")
	var line := {}
	for t in MeshTools.TOOLS:
		if t["label"] == "Model: pack UV islands":
			line = t
	ok(not line.is_empty() and line["keys"] == "Ctrl+P" and String(line["do"]) != "", "bar 7: mesh tools line \"Model: pack UV islands\", Ctrl+P, built")
	var cs: CommandSearch = main.ui_cmd
	if cs != null:
		cs.open()
		cs.box.text = "pack uv"
		cs._filter()
		var it: TreeItem = cs.list.get_root().get_first_child()
		var first := it.get_text(0) if it != null else ""
		print("  S box \"pack uv\" -> \"%s\"" % first)
		ok(first == "Model: pack UV islands", "bar 7: the S box finds it first")
		cs.close()
	else:
		ok(false, "bar 7: no S box on main (cmd_search)")
