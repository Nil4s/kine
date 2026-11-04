extends SceneTree
## CH4: WOOD THAT OBEYS ITS GRAIN. The dovetailed oak box (scripts/build/oak_box.gd, docs/CH4_REFERENCE.md) with a SOLID (3D) grain field
## (scripts/build/wood_solid.gd + wood_solid.gdshader + native/src/kine_wood_native.cpp).
## godot --headless --path . -s tests/ch4_test.gd   (the render bars need a real window: use wtest.sh)
## BARS (written before any number was read; 1 px = 0.125 mm, the bake of the continuity bar):
##   A BUILD       the Part record replays with 0 errors: 5 bodies (4 boards + lid), box 160 x 70 x 100 mm +- 0.2, lid on top 168 x 10 x 108, the lid has chamfer faces
##   B SLOPE       every dovetail flank of the Front board (mesh triangles, normal in the XY plane, not axis aligned) is 1:8 = 7.125 deg +- 0.5 deg; at least 12 flank triangles
##   C GAP         the gap between each Front tail flank and the Left board's pin flank, from the meshes: max < 0.1 mm and min > 0.02 mm (a fit, not an overlap)
##   D CONTINUITY  at every crease of every body (dihedral > 20 deg: tail corners, dovetail flanks, the chamfer): the ring phase on the two faces one pixel apart
##                 straddling the edge differs by <= 1 px of distance (|dg| / |grad g| <= 0.125 mm); at least 40 creases, including chamfer and tail-end creases
##   E END / SIDE  E1 a billet end face (pith inside) shows >= 4 CLOSED rings: circle fit rms < 8 % of the radius, centre within 2 mm of the pith, boundary points all round (gap <= 30 deg)
##                 E2 a long face (the Front's outside) has its ring gradients across the grain: >= 70 % within 25 deg of the cross-grain axis
##                 E3 the lid's flat-sawn top shows cathedrals: ring contours slanted along the grain on >= 30 % of the face and turning both ways across it (>= 10 % each)
##                 E4 every one of the 30 bbox faces of the 5 bodies: a window of up to 60 x 60 mm: its pores are round on an end face (mean aspect < 2.5) and streaks on a long face (>= 4); all 30 classified right
##   F SHADER      the lit-off render of the shader on a flat patch equals the GDScript field: >= 99 % of pixels within 3/255, mean error < 1/255
##   G CHAMFER     the chamfer face's points: the C++ (sampled) colour and phase equal an independent GDScript evaluation of the analytic field within 1e-4; the chamfer exposes >= 3 rings
##   H NATIVE      C++ and GDScript agree on 20000 random points of 5 specs within 1e-4 on all six outputs (FAILS if the DLL is not built)
##   R RENDER      the shader's phase image across the chamfer's top edge (3 px each side): the jump J = |d_cross - mean(d_left, d_right)| has mean <= 0.06 ring and p90 <= 0.12 ring
##   L LOOK        close-ups (corner with dovetails, chamfer, end grain, whole box) are written and are not flat (luminance sd > 0.03)
##   CONTROL       a 2D UV-mapped texture (the same grain read on each face's flat coordinates) FAILS D (median > 1 px) and FAILS E4 (misclassifies >= 8 of the 30 faces);
##                 a 1:6 box fails B, a 0.3 mm gap fails C
const OUT := "C:/Users/Nick/tools/kine_workers/out/ch4"
const PX := 0.125
var fails := 0
var cc := {}


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func _init() -> void:
	_run.call_deferred()


# ---------------------------------------------------------------- mesh helpers (mm)

func tris_of(mesh: ArrayMesh, s: int) -> PackedVector3Array:
	var a := mesh.surface_get_arrays(s)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ix = a[Mesh.ARRAY_INDEX]
	var out := PackedVector3Array()
	if ix == null or (ix as PackedInt32Array).is_empty():
		for i in v.size():
			out.append(v[i] * 1000.0)
	else:
		for i in (ix as PackedInt32Array):
			out.append(v[i] * 1000.0)
	return out


func tri_n(t: PackedVector3Array, i: int) -> Vector3:
	return (t[i + 1] - t[i]).cross(t[i + 2] - t[i]).normalized()


func bbox(t: PackedVector3Array) -> AABB:
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for p in t:
		lo = lo.min(p)
		hi = hi.max(p)
	return AABB(lo, hi - lo)


func is_flank(n: Vector3) -> bool:
	return absf(n.z) < 0.02 and absf(n.x) > 0.05 and absf(n.y) > 0.05


func flank_angles(t: PackedVector3Array) -> Array:
	var out := []
	for i in range(0, t.size(), 3):
		var n := tri_n(t, i)
		if is_flank(n):
			out.append(rad_to_deg(atan(absf(n.x) / absf(n.y))))
	return out


func gap_stats(tf: PackedVector3Array, tl: PackedVector3Array) -> Vector2:
	# Front flank centroids (x < T) against the Left board's flank triangles
	var lf := []
	for i in range(0, tl.size(), 3):
		if is_flank(tri_n(tl, i)):
			lf.append(i)
	var mn := 1e9
	var mx := 0.0
	var n := 0
	for i in range(0, tf.size(), 3):
		if not is_flank(tri_n(tf, i)):
			continue
		var c := (tf[i] + tf[i + 1] + tf[i + 2]) / 3.0
		if c.x > 12.0 and c.x < 148.0:
			continue
		var best := 1e9
		for j in lf:
			var q: Vector3 = Part._closest_on_tri(c, tl[j], tl[j + 1], tl[j + 2])
			best = minf(best, c.distance_to(q))
		if best < 1.0:   # the flank facing it (the neighbouring tail's flank is a pin width away)
			mn = minf(mn, best)
			mx = maxf(mx, best)
			n += 1
	return Vector2(mn if n > 0 else -1.0, mx if n > 0 else 99.0)


func key(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x * 200.0), roundi(p.y * 200.0), roundi(p.z * 200.0)]


## creases of a surface: [{p0, p1, n1, n2, o1, o2}] (o: the third vertex of each side's triangle)
func creases(t: PackedVector3Array) -> Array:
	var em := {}
	for i in range(0, t.size(), 3):
		for k in 3:
			var a := t[i + k]
			var b := t[i + (k + 1) % 3]
			var ka := key(a)
			var kb := key(b)
			var kk := ka + "|" + kb if ka < kb else kb + "|" + ka
			if not em.has(kk):
				em[kk] = []
			(em[kk] as Array).append([a, b, i, t[i + (k + 2) % 3]])
	var out := []
	for kk in em:
		var l: Array = em[kk]
		if l.size() != 2:
			continue
		var n1 := tri_n(t, int(l[0][2]))
		var n2 := tri_n(t, int(l[1][2]))
		if n1.dot(n2) > cos(deg_to_rad(20.0)):
			continue
		var p0: Vector3 = l[0][0]
		var p1: Vector3 = l[0][1]
		if p0.distance_to(p1) < 0.5:
			continue
		out.append({"p0": p0, "p1": p1, "n1": n1, "n2": n2, "o1": l[0][3], "o2": l[1][3]})
	return out


func into_face(c: Dictionary, which: int, p: Vector3) -> Vector3:
	var o: Vector3 = c["o1"] if which == 1 else c["o2"]
	var e: Vector3 = ((c["p1"] as Vector3) - (c["p0"] as Vector3)).normalized()
	var d := (o - p) - e * (o - p).dot(e)
	return d.normalized()


func grad_g(p: Vector3, spec: Dictionary, two_d: Dictionary) -> float:
	var h := 0.05
	var pts := PackedVector3Array()
	for ax in 3:
		var d := Vector3.ZERO
		d[ax] = h
		pts.append(p + d)
		pts.append(p - d)
	var r := sample(pts, spec, two_d)
	var gv := Vector3((r[0 * 6 + 3] - r[1 * 6 + 3]) / (2 * h), (r[2 * 6 + 3] - r[3 * 6 + 3]) / (2 * h), (r[4 * 6 + 3] - r[5 * 6 + 3]) / (2 * h))
	return gv.length()


## the field, or the planted 2D control (two_d: {"o", "ex", "ey"} the face's own flat mapping)
func sample(pts: PackedVector3Array, spec: Dictionary, two_d: Dictionary) -> PackedFloat32Array:
	if two_d.is_empty():
		return WoodSolid.sample(pts, spec)
	return WoodSolid.sample_2d(pts, two_d["o"], two_d["ex"], two_d["ey"], spec)


func flat_map(n: Vector3) -> Dictionary:
	var ex := n.cross(Vector3.UP)
	if ex.length() < 0.1:
		ex = n.cross(Vector3.RIGHT)
	ex = ex.normalized()
	return {"o": Vector3.ZERO, "ex": ex, "ey": n.cross(ex).normalized()}


## the continuity measure over every crease of the given surfaces; two_d: plant the UV-mapped control
func continuity(tris: Array, specs: Array, two_d: bool) -> Dictionary:
	var vals := []
	var chamfer := 0
	var tail_end := 0
	for s in tris.size():
		var cr := creases(tris[s])
		var step := maxi(cr.size() / 60, 1)
		for ci in range(0, cr.size(), step):
			var c: Dictionary = cr[ci]
			for fr in [0.3, 0.7]:
				var p: Vector3 = (c["p0"] as Vector3).lerp(c["p1"], fr)
				var pa := p + into_face(c, 1, p) * PX * 0.5
				var pb := p + into_face(c, 2, p) * PX * 0.5
				var m1 := flat_map(c["n1"]) if two_d else {}
				var m2 := flat_map(c["n2"]) if two_d else {}
				var ra := sample(PackedVector3Array([pa]), specs[s], m1)
				var rb := sample(PackedVector3Array([pb]), specs[s], m2)
				var gr := grad_g(p, specs[s], m1)
				if gr < 1e-4:
					continue
				vals.append(absf(ra[3] - rb[3]) / gr / PX)
			var nn: Array = [c["n1"], c["n2"]]
			for nv in nn:
				if absf((nv as Vector3).y) > 0.5 and absf((nv as Vector3).y) < 0.9 and s == 4:
					chamfer += 1
			if s < 4 and (absf((c["n1"] as Vector3).x) > 0.99 or absf((c["n2"] as Vector3).x) > 0.99) and (absf((c["n1"] as Vector3).z) > 0.99 or absf((c["n2"] as Vector3).z) > 0.99):
				tail_end += 1
	vals.sort()
	return {"n": vals.size(), "med": vals[vals.size() / 2] if not vals.is_empty() else 99.0, "max": vals[vals.size() - 1] if not vals.is_empty() else 99.0, "chamfer": chamfer, "tail": tail_end}


# ---------------------------------------------------------------- faces and images

func bake(o: Vector3, ex: Vector3, ey: Vector3, w: float, h: float, ppm: float, spec: Dictionary, two_d: Dictionary = {}) -> Dictionary:
	var nw := int(round(w * ppm))
	var nh := int(round(h * ppm))
	var pts := PackedVector3Array()
	pts.resize(nw * nh)
	var k := 0
	for j in nh:
		for i in nw:
			pts[k] = o + ex * ((i + 0.5) / ppm) + ey * ((j + 0.5) / ppm)
			k += 1
	return {"w": nw, "h": nh, "d": sample(pts, spec, two_d)}


## ring-boundary pixels of ring k: [Vector2 (mm)]
func boundaries(b: Dictionary, ppm: float, o2: Vector2) -> Dictionary:
	var nw: int = b["w"]
	var nh: int = b["h"]
	var d: PackedFloat32Array = b["d"]
	var by := {}
	for j in nh - 1:
		for i in nw - 1:
			var g0 := floorf(d[(j * nw + i) * 6 + 3])
			var g1 := floorf(d[(j * nw + i + 1) * 6 + 3])
			var g2 := floorf(d[((j + 1) * nw + i) * 6 + 3])
			for gg in [g1, g2]:
				if gg != g0:
					var k := int(maxf(g0, gg))
					if not by.has(k):
						by[k] = []
					(by[k] as Array).append(o2 + Vector2((i + 1.0) / ppm, (j + 0.5) / ppm) if gg == g1 else o2 + Vector2((i + 0.5) / ppm, (j + 1.0) / ppm))
	return by


func fit_circle(pts: Array) -> Dictionary:
	# Kasa: x^2 + y^2 + D x + E y + F = 0
	var n := pts.size()
	var sx := 0.0
	var sy := 0.0
	var sxx := 0.0
	var syy := 0.0
	var sxy := 0.0
	var sz := 0.0
	var sxz := 0.0
	var syz := 0.0
	for p in pts:
		var x: float = p.x
		var y: float = p.y
		var z := x * x + y * y
		sx += x
		sy += y
		sxx += x * x
		syy += y * y
		sxy += x * y
		sz += z
		sxz += x * z
		syz += y * z
	var m := Basis(Vector3(sxx, sxy, sx), Vector3(sxy, syy, sy), Vector3(sx, sy, n))
	var rhs := Vector3(-sxz, -syz, -sz)
	var sol := m.inverse() * rhs
	var cx := -sol.x / 2.0
	var cy := -sol.y / 2.0
	var r := sqrt(maxf(cx * cx + cy * cy - sol.z, 0.0))
	var se := 0.0
	var angs := []
	for p in pts:
		var dd := sqrt((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy)) - r
		se += dd * dd
		angs.append(atan2(p.y - cy, p.x - cx))
	angs.sort()
	var gap := 0.0
	for i in angs.size():
		var nx: float = angs[(i + 1) % angs.size()]
		var dg: float = nx - angs[i]
		if i == angs.size() - 1:
			dg += TAU
		gap = maxf(gap, dg)
	return {"c": Vector2(cx, cy), "r": r, "rms": sqrt(se / n), "gap": rad_to_deg(gap)}


func grad_stats(b: Dictionary, ppm: float, grain_axis: int) -> Dictionary:
	var nw: int = b["w"]
	var nh: int = b["h"]
	var d: PackedFloat32Array = b["d"]
	var cross_ok := 0
	var tot := 0
	var pos := 0
	var neg := 0
	var slant := 0
	for j in range(1, nh - 1):
		for i in range(1, nw - 1):
			var gx := (d[(j * nw + i + 1) * 6 + 3] - d[(j * nw + i - 1) * 6 + 3]) * ppm / 2.0
			var gy := (d[((j + 1) * nw + i) * 6 + 3] - d[((j - 1) * nw + i) * 6 + 3]) * ppm / 2.0
			var m := sqrt(gx * gx + gy * gy)
			if m < 1e-3:
				continue
			tot += 1
			var cross_v := absf(gy) if grain_axis == 0 else absf(gx)   # the grain runs along image x (0) or y (1)
			if cross_v / m > cos(deg_to_rad(25.0)):
				cross_ok += 1
			var cr := gy if grain_axis == 0 else gx
			var al := gx if grain_axis == 0 else gy
			if absf(al) > 0.1 * m:
				slant += 1
			if absf(cr) > 0.1 * m:
				if cr > 0.0:
					pos += 1
				else:
					neg += 1
	return {"cross": float(cross_ok) / maxf(tot, 1), "pos": float(pos) / maxf(tot, 1), "neg": float(neg) / maxf(tot, 1), "slant": float(slant) / maxf(tot, 1)}


func pore_aspect(b: Dictionary) -> float:
	var nw: int = b["w"]
	var nh: int = b["h"]
	var d: PackedFloat32Array = b["d"]
	var seen := PackedByteArray()
	seen.resize(nw * nh)
	var asp := []
	for j in nh:
		for i in nw:
			var k := j * nw + i
			if seen[k] == 1 or d[k * 6 + 4] <= 0.5:
				continue
			var st := [Vector2i(i, j)]
			seen[k] = 1
			var lo := Vector2i(i, j)
			var hi := Vector2i(i, j)
			var cnt := 0
			while not st.is_empty():
				var q: Vector2i = st.pop_back()
				cnt += 1
				lo = Vector2i(mini(lo.x, q.x), mini(lo.y, q.y))
				hi = Vector2i(maxi(hi.x, q.x), maxi(hi.y, q.y))
				for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = q + dd
					if n.x < 0 or n.y < 0 or n.x >= nw or n.y >= nh:
						continue
					var nk := n.y * nw + n.x
					if seen[nk] == 0 and d[nk * 6 + 4] > 0.5:
						seen[nk] = 1
						st.append(n)
			if lo.x == 0 or lo.y == 0 or hi.x == nw - 1 or hi.y == nh - 1:
				continue   # cut by the window
			if cnt < 4:
				continue
			var w := float(hi.x - lo.x + 1)
			var h := float(hi.y - lo.y + 1)
			asp.append(maxf(w, h) / minf(w, h))
	if asp.size() < 5:
		return -1.0
	var s := 0.0
	for a in asp:
		s += a
	return s / asp.size()


# ---------------------------------------------------------------- rendering

var vp: SubViewport
var holder: Node3D
var cam: Camera3D


func make_view(w: int, h: int, ortho: float, lit: bool) -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	root.add_child(vp)
	holder = Node3D.new()
	vp.add_child(holder)
	cam = Camera3D.new()
	cam.near = 0.002
	cam.far = 3.0
	if ortho > 0.0:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = ortho
	else:
		cam.fov = 28.0
	vp.add_child(cam)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.2)
	if lit:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.75, 0.78, 0.85)
		env.ambient_light_energy = 0.55
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, -35, 0)
		sun.light_energy = 1.4
		vp.add_child(sun)
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(-20, 140, 0)
		fill.light_energy = 0.5
		vp.add_child(fill)
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	cam.environment = env


func shot() -> Image:
	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()


func free_view() -> void:
	vp.queue_free()
	await process_frame


func look_at_mm(from_mm: Vector3, to_mm: Vector3) -> void:
	cam.position = from_mm * 0.001
	cam.look_at(to_mm * 0.001, Vector3.UP)


func luminance_sd(im: Image) -> float:
	var s := 0.0
	var s2 := 0.0
	var n := 0
	for j in range(0, im.get_height(), 3):
		for i in range(0, im.get_width(), 3):
			var c := im.get_pixel(i, j)
			var l := 0.3 * c.r + 0.59 * c.g + 0.11 * c.b
			s += l
			s2 += l * l
			n += 1
	var m := s / n
	return sqrt(maxf(s2 / n - m * m, 0.0))


func ang_diff(a: float, b: float) -> float:
	var d := fmod(a - b, 1.0)
	if d > 0.5:
		d -= 1.0
	elif d < -0.5:
		d += 1.0
	return d


# ---------------------------------------------------------------- the run

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	ok(Part.available(), "0 the CAD kernel is there")
	if not Part.available():
		print("ch4: %d fail" % fails)
		quit(1)
		return
	var rec := OakBox.record()
	var res := Part.replay(rec.duplicate(true))
	var mesh: ArrayMesh = res["mesh"]
	var specs := []
	for i in 5:
		specs.append(OakBox.spec_of(i))
	# A BUILD
	ok((res["errors"] as Dictionary).is_empty(), "A replay: 0 errors (%s)" % str(res["errors"]))
	ok(int(res["bodies"]) == 5 and mesh != null and mesh.get_surface_count() == 5, "A five bodies, five surfaces (%d)" % int(res["bodies"]))
	var tris := []
	for s in mesh.get_surface_count():
		tris.append(tris_of(mesh, s))
	var all := PackedVector3Array()
	for s in 4:
		all.append_array(tris[s])
	var bb := bbox(all)
	ok(absf(bb.size.x - 160.0) < 0.2 and absf(bb.size.y - 70.0) < 0.2 and absf(bb.size.z - 100.0) < 0.2, "A box %s mm" % str(bb.size))
	var lb := bbox(tris[4])
	ok(absf(lb.size.x - 168.0) < 0.2 and absf(lb.size.y - 10.0) < 0.2 and absf(lb.size.z - 108.0) < 0.2 and absf(lb.position.y - 70.0) < 0.2, "A lid %s at y %.2f" % [str(lb.size), lb.position.y])
	var ch_tris := PackedVector3Array()
	var tt: PackedVector3Array = tris[4]
	for i in range(0, tt.size(), 3):
		var n := tri_n(tt, i)
		if absf(n.y) > 0.5 and absf(n.y) < 0.9:
			ch_tris.append_array(PackedVector3Array([tt[i], tt[i + 1], tt[i + 2]]))
	ok(ch_tris.size() >= 12, "A the lid has chamfer faces (%d triangles)" % (ch_tris.size() / 3))
	# B SLOPE
	var fa := flank_angles(tris[0])
	var mn := 99.0
	var mx := 0.0
	for a in fa:
		mn = minf(mn, a)
		mx = maxf(mx, a)
	var want := rad_to_deg(atan(1.0 / 8.0))
	ok(fa.size() >= 12 and absf(mn - want) <= 0.5 and absf(mx - want) <= 0.5, "B slope: %d flank triangles, %.3f..%.3f deg (want %.3f +- 0.5)" % [fa.size(), mn, mx, want])
	# C GAP
	var gs := gap_stats(tris[0], tris[2])
	ok(gs.x > 0.02 and gs.y < 0.1, "C gap Front/Left: min %.4f max %.4f mm (bars > 0.02, < 0.1)" % [gs.x, gs.y])
	# CONTROLS for B and C: a 1:6 box, a 0.3 mm gap
	var r6 := Part.replay(OakBox.record(6.0, 0.05, 0.0))
	var f6 := flank_angles(tris_of(r6["mesh"], 0))
	var a6 := 0.0
	for a in f6:
		a6 = maxf(a6, a)
	ok(f6.size() > 0 and absf(a6 - want) > 0.5, "CONTROL a 1:6 box: flank %.2f deg fails B" % a6)
	var rg := Part.replay(OakBox.record(8.0, 0.3, 0.0))
	var gg := gap_stats(tris_of(rg["mesh"], 0), tris_of(rg["mesh"], 2))
	ok(gg.y >= 0.1, "CONTROL a 0.3 mm gap: max %.3f mm fails C" % gg.y)
	# H NATIVE (before the heavy bars, so a missing DLL says so first)
	var has_n := WoodSolid.has_native()
	ok(has_n, "H the C++ field is loaded (KineWoodNative)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var pts := PackedVector3Array()
	for i in 4000:
		pts.append(Vector3(rng.randf_range(-20, 190), rng.randf_range(-20, 100), rng.randf_range(-20, 120)))
	var worst := 0.0
	var t_c := 0
	var t_g := 0
	for s in specs:
		var t0 := Time.get_ticks_usec()
		var rc := WoodSolid.sample(pts, s)
		t_c += Time.get_ticks_usec() - t0
		t0 = Time.get_ticks_usec()
		var rgd := WoodSolid.sample(pts, s, true)
		t_g += Time.get_ticks_usec() - t0
		for k in rc.size():
			worst = maxf(worst, absf(rc[k] - rgd[k]))
	ok(has_n and worst <= 1e-4, "H C++ vs GDScript on 20000 points: worst diff %s (bar 1e-4); C++ %.1f ms, GDScript %.1f ms (%.0fx)" % [String.num_scientific(worst), t_c / 1000.0, t_g / 1000.0, float(t_g) / maxf(t_c, 1)])
	# D CONTINUITY
	var d_solid := continuity(tris, specs, false)
	ok(int(d_solid["n"]) >= 80 and int(d_solid["chamfer"]) >= 4 and int(d_solid["tail"]) >= 4, "D coverage: %d samples, %d chamfer creases, %d tail-end creases" % [int(d_solid["n"]), int(d_solid["chamfer"]), int(d_solid["tail"])])
	ok(float(d_solid["max"]) <= 1.0, "D continuity: worst ring-phase step across a crease %.3f px (median %.3f; bar <= 1 px = 0.125 mm)" % [float(d_solid["max"]), float(d_solid["med"])])
	var d_2d := continuity(tris, specs, true)
	ok(float(d_2d["med"]) > 1.0, "CONTROL a 2D UV-mapped texture: median step %.2f px, worst %.1f px fails D" % [float(d_2d["med"]), float(d_2d["max"])])
	# E1 closed rings on a billet end
	var fix := {"kind": "oak3d", "seed": 21, "pith": [0.0, 0.0, 0.0], "dir": [0.0, 0.0, 1.0], "ring": 2.0}
	var ppm := 10.0
	var b1 := bake(Vector3(-18, -18, 0), Vector3.RIGHT, Vector3.UP, 36, 36, ppm, fix)
	var by := boundaries(b1, ppm, Vector2(-18, -18))
	var closed := 0
	var worst_rms := 0.0
	var worst_c := 0.0
	var worst_gap := 0.0
	for k in by:
		var l: Array = by[k]
		if l.size() < 80 or k < 4 or k > 8:
			continue
		var ft := fit_circle(l)
		closed += 1
		worst_rms = maxf(worst_rms, float(ft["rms"]) / float(ft["r"]))
		worst_c = maxf(worst_c, (ft["c"] as Vector2).length())
		worst_gap = maxf(worst_gap, float(ft["gap"]))
	ok(closed >= 4 and worst_rms < 0.08 and worst_c < 2.0 and worst_gap <= 30.0, "E1 billet end: %d closed rings, worst rms/r %.3f, centre off %.2f mm, widest gap %.1f deg" % [closed, worst_rms, worst_c, worst_gap])
	# E2 long face: the Front's outside (z = 0), grain along x
	var ppm2 := 4.0
	var b2 := bake(Vector3(0, 0, 0), Vector3.RIGHT, Vector3.UP, 160, 70, ppm2, specs[0])
	var gs2 := grad_stats(b2, ppm2, 0)
	ok(float(gs2["cross"]) >= 0.7, "E2 long face: %.1f %% of the ring gradient is across the grain (bar >= 70 %%)" % (100.0 * float(gs2["cross"])))
	var cl := boundaries(b2, ppm2, Vector2.ZERO)
	var end_closed := 0
	for k in cl:
		var l: Array = cl[k]
		if l.size() >= 80:
			var ft := fit_circle(l)
			if float(ft["gap"]) <= 30.0 and float(ft["rms"]) / maxf(float(ft["r"]), 1e-6) < 0.08:
				end_closed += 1
	ok(end_closed == 0, "CONTROL the long face run through the closed-ring test: %d closed rings (must be 0)" % end_closed)
	# E3 cathedral on the lid top
	var b3 := bake(Vector3(-4, 80, -4), Vector3.RIGHT, Vector3(0, 0, 1), 168, 108, 3.0, specs[4])
	var gs3 := grad_stats(b3, 3.0, 0)
	ok(float(gs3["slant"]) >= 0.3 and float(gs3["pos"]) >= 0.1 and float(gs3["neg"]) >= 0.1, "E3 lid top cathedral: contours slanted along the grain on %.1f %% (bar >= 30 %%) and turning both ways across it (%.1f %% / %.1f %%, bar >= 10 %% each)" % [100.0 * float(gs3["slant"]), 100.0 * float(gs3["pos"]), 100.0 * float(gs3["neg"])])
	var flatb := bake(Vector3(-4, 80, -4), Vector3.RIGHT, Vector3(0, 0, 1), 168, 108, 3.0, {"kind": "oak3d", "seed": 15, "pith": [80.0, 25.0, 54.0], "dir": [1.0, 0.0, 0.0], "ring": 2.4})
	var gsf := grad_stats(flatb, 3.0, 0)
	ok(float(gsf["slant"]) < 0.3, "CONTROL a straight-axis trunk (no taper) gives parallel bands, not cathedrals: slant %.1f %% fails E3" % (100.0 * float(gsf["slant"])))
	# E4 every bbox face
	var grain := [0, 0, 2, 2, 0]   # axis of the grain per body: X X Z Z X
	var wrong := 0
	var wrong_2d := 0
	var nf := 0
	var asp_end := []
	var asp_long := []
	for s in 5:
		var tb := bbox(tris[s])
		for ax in 3:
			for side in 2:
				var n := Vector3.ZERO
				n[ax] = 1.0 if side == 1 else -1.0
				var u_ax := (ax + 1) % 3
				var v_ax := (ax + 2) % 3
				var ex := Vector3.ZERO
				ex[u_ax] = 1.0
				var ey := Vector3.ZERO
				ey[v_ax] = 1.0
				var o := tb.position + tb.size * 0.5
				o[ax] = tb.position[ax] + (tb.size[ax] if side == 1 else 0.0)
				var wu := minf(tb.size[u_ax], 60.0)
				var wv := minf(tb.size[v_ax], 60.0)
				o[u_ax] -= wu * 0.5
				o[v_ax] -= wv * 0.5
				var win := bake(o, ex, ey, wu, wv, 15.0, specs[s])
				var asp := pore_aspect(win)
				var is_end := ax == int(grain[s])
				var pred_end := asp >= 0.0 and asp < 2.5
				var pred_long := asp >= 4.0
				if (is_end and not pred_end) or ((not is_end) and not pred_long):
					wrong += 1
				(asp_end if is_end else asp_long).append(asp)
				# control: the same window through the 2D mapping
				var win2 := bake(o, ex, ey, wu, wv, 15.0, specs[s], {"o": Vector3.ZERO, "ex": ex, "ey": ey})
				var asp2 := pore_aspect(win2)
				if (is_end and not (asp2 >= 0.0 and asp2 < 2.5)) or ((not is_end) and not asp2 >= 4.0):
					wrong_2d += 1
				nf += 1
	ok(nf == 30 and wrong == 0, "E4 end vs side grain on all %d faces: %d misclassified (end aspects %s, long aspects %s)" % [nf, wrong, str(asp_end.map(func(a): return snappedf(a, 0.1))), str(asp_long.map(func(a): return snappedf(a, 0.1)))])
	ok(wrong_2d >= 8, "CONTROL a 2D UV-mapped texture misclassifies %d of 30 faces (bar: >= 8)" % wrong_2d)
	# G CHAMFER sampled vs analytic
	var cpts := PackedVector3Array()
	for i in range(0, ch_tris.size(), 3):
		cpts.append((ch_tris[i] + ch_tris[i + 1] + ch_tris[i + 2]) / 3.0)
		cpts.append(ch_tris[i] * 0.6 + ch_tris[i + 1] * 0.2 + ch_tris[i + 2] * 0.2)
		cpts.append(ch_tris[i] * 0.2 + ch_tris[i + 1] * 0.6 + ch_tris[i + 2] * 0.2)
	# the long chamfer edges are two triangles each: add a dense line along every chamfer's length
	for k in 200:
		cpts.append(Vector3(-4.0 + 168.0 * k / 199.0, 80.0 - 1.5, -4.0 + 1.5))
		cpts.append(Vector3(-4.0 + 1.5, 80.0 - 1.5, -4.0 + 108.0 * k / 199.0))
	var sc := WoodSolid.sample(cpts, specs[4])
	var an := WoodSolid.sample(cpts, specs[4], true)
	var wd := 0.0
	var rings := {}
	for i in cpts.size():
		for k in 6:
			wd = maxf(wd, absf(sc[i * 6 + k] - an[i * 6 + k]))
		rings[floori(sc[i * 6 + 3])] = true
	ok(cpts.size() >= 400 and wd <= 1e-4 and rings.size() >= 3, "G chamfer: %d points, sampled vs analytic worst diff %s, %d rings exposed" % [cpts.size(), String.num_scientific(wd), rings.size()])
	# F SHADER vs GDScript field on a flat patch
	make_view(256, 256, 0.0256, false)
	var ps := Vector3(40, 20, 0)
	var quad := ArrayMesh.new()
	var qa := []
	qa.resize(Mesh.ARRAY_MAX)
	qa[Mesh.ARRAY_VERTEX] = PackedVector3Array([ps * 0.001, (ps + Vector3(25.6, 0, 0)) * 0.001, (ps + Vector3(25.6, 25.6, 0)) * 0.001, (ps + Vector3(0, 25.6, 0)) * 0.001])
	qa[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	qa[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, qa)
	quad.surface_set_material(0, WoodSolid.material(specs[0], 1))
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	holder.add_child(mi)
	cam.position = Vector3(52.8, 32.8, 100.0) * 0.001
	cam.rotation = Vector3.ZERO
	var im := await shot()
	var pf := PackedVector3Array()
	for j in 256:
		for i in 256:
			pf.append(Vector3(40.0 + (i + 0.5) / 10.0, 45.6 - (j + 0.5) / 10.0, 0.0))
	var fr := WoodSolid.sample(pf, specs[0])
	var within := 0
	var sume := 0.0
	for j in 256:
		for i in 256:
			var c := im.get_pixel(i, j)
			var k := (j * 256 + i) * 6
			var e := maxf(maxf(absf(c.r * 255.0 - fr[k] * 255.0), absf(c.g * 255.0 - fr[k + 1] * 255.0)), absf(c.b * 255.0 - fr[k + 2] * 255.0))
			sume += e
			if e <= 3.0:
				within += 1
	var wf := float(within) / 65536.0
	ok(wf >= 0.99 and sume / 65536.0 < 1.0, "F shader vs GDScript field: %.2f %% of pixels within 3/255, mean error %.3f/255" % [100.0 * wf, sume / 65536.0])
	im.save_png(OUT + "/f_shader_patch.png")
	await free_view()
	# R RENDER: phase image across the chamfer's top edge (z = -4 .. chamfer along x)
	var painted := mesh.duplicate() as ArrayMesh
	make_view(1200, 800, 0.07, false)
	for s in 5:
		painted.surface_set_material(s, WoodSolid.material(specs[s], 2))
	var mi2 := MeshInstance3D.new()
	mi2.mesh = painted
	holder.add_child(mi2)
	var tgt := Vector3(60, 79, -2)
	look_at_mm(tgt + Vector3(0, 100, -100), tgt)
	var im2 := await shot()
	im2.save_png(OUT + "/r_phase.png")
	var pa0 := cam.unproject_position(Vector3(20, 80, -1) * 0.001)   # top edge of the front chamfer (z = -1)
	var pa1 := cam.unproject_position(Vector3(100, 80, -1) * 0.001)
	var edir := (pa1 - pa0).normalized()
	var perp := Vector2(-edir.y, edir.x)
	var js := []
	for k in 60:
		var p := pa0.lerp(pa1, (k + 0.5) / 60.0)
		var vals := []
		for off in [-4.5, -1.5, 1.5, 4.5]:
			var q: Vector2 = p + perp * off
			var c := im2.get_pixelv(Vector2i(q))
			vals.append(atan2(c.r - 0.5, c.g - 0.5) / TAU)
		var d_l := ang_diff(vals[1], vals[0])
		var d_r := ang_diff(vals[3], vals[2])
		var d_c := ang_diff(vals[2], vals[1])
		js.append(absf(d_c - 0.5 * (d_l + d_r)))
	js.sort()
	var jm := 0.0
	for j in js:
		jm += j
	jm /= js.size()
	ok(jm <= 0.06 and js[int(js.size() * 0.9)] <= 0.12, "R render across the chamfer edge: jump mean %.3f ring, p90 %.3f ring (bars 0.06 / 0.12)" % [jm, js[int(js.size() * 0.9)]])
	await free_view()
	# L LOOK: lit close-ups
	var views := {
		"corner": [Vector3(-75, 78, -85), Vector3(2, 38, 2), 0],
		"chamfer": [Vector3(30, 120, -70), Vector3(40, 77, -3), 0],
		"endgrain": [Vector3(-95, 82, -25), Vector3(-4, 75, 40), 0],
		"box": [Vector3(-190, 190, -250), Vector3(80, 38, 50), 0]}
	var lit := mesh.duplicate() as ArrayMesh
	Part.paint(lit, res["looks"])
	for name in views:
		make_view(960, 720, 0.0, true)
		var m3 := MeshInstance3D.new()
		m3.mesh = lit
		holder.add_child(m3)
		look_at_mm(views[name][0], views[name][1])
		var imv := await shot()
		imv.save_png(OUT + "/" + name + ".png")
		var sd := luminance_sd(imv)
		ok(sd > 0.03, "L look %s: luminance sd %.3f" % [name, sd])
		await free_view()
	print("ch4: %d fail" % fails)
	quit(1 if fails > 0 else 0)
