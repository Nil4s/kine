## godot --path . -s tests/meshcurves_test.gd     (ROADMAP_400 B11 spin / screw / lathe, B12 curves -> mesh;
## scripts/kmesh_lathe.gd, kmesh_curve.gd, kmesh_curves_ui.gd; run_all: meshcurves:w, the drag needs a real camera)
## (the suite is "meshcurves": "curves" is already the animation f-curve suite, tests/curves_test.gd)
## Bars, stated before the first run:
## B11
##   1 LATHE of the unit-square profile r 1..2, y 0..1 (closed) around Y, 64 steps, 360 deg: closed, manifold, Euler 0,
##     exactly 4 x 64 verts (the seam welded: no doubled verts, KMeshValidate finds nothing). VOLUME: the faceting error of
##     an inscribed 64-gon is known exactly, V = pi (4 - 1) 1 x sin(2 pi / 64) / (2 pi / 64), 0.1606 % under the annulus
##     pi (4 - 1) 1 = 3 pi: the mesh must match that within 1e-6 (relative) and so lie within 0.17 % of 3 pi
##   2 POLES: a half circle touching the axis at both ends (16 segments, 32 steps) gives ONE vert per axis point
##     (15 x 32 + 2 verts), 64 pole triangles, closed manifold Euler 2, and its smallest face > 1e-6 m^2 (no zero area);
##     a closed profile with a segment ON the axis (0,0 1,0 1,1 0,1) makes no face from that segment: closed, manifold,
##     Euler 2, smallest face > 1e-6 m^2, volume within the 64-gon faceting of pi r^2 h (1e-6)
##   3 SCREW: a closed 10 x 10 cm square profile at r 0.5 m, 32 steps, 2 turns, 30 cm a turn: every vert of the end ring
##     is its start ring vert + (0, 0.6, 0) within 1e-6 m (the rise is exactly 2 x the offset), height 0.7 m (1e-6), not
##     welded (4 x 65 verts); a 90 deg spin of an open 2-point profile, 8 steps: 9 rings, open
##   4 UVs: every corner of the annulus has u = its angle / 360 deg (the seam's closing corners u = 1) within 1e-5 and v =
##     its arc fraction along the profile (0, .25, .5, .75; 1 on the closing edge) within 1e-6
##   5 THE PREVIEW: a chain of 4 edges of the test cube in edge mode, "op:lathe" around Y through the 3D cursor = ONE undo
##     step; changing steps 32 -> 12 rebuilds it (vert count follows) and stays ONE step; Ctrl+Z gives the cube back
##     exactly (verts, faces)
## B12
##   6 FRAMES: along a 3-turn helix (r 0.3, pitch 0.2) sampled 128 per turn, the RMF normal turns < 5 deg between samples
##     and stays square to the tangent (< 1e-6); the instrument can move: an up-vector frame (world Y made square to the
##     tangent) on a circle standing in the XY plane turns > 90 deg between two samples (the flip), the RMF on the same
##     samples < 5 deg; a closed curve's frame comes round with < 5 deg between the last sample and the first.
##     REVISED after the first run (9.0 deg): that closed curve was sampled at the default 12 a segment, where its TANGENT
##     turns 9.4 deg a sample (the lift bends it), so any frame must turn that much. It is now sampled 32 a segment like
##     the circle (bar 5 deg unchanged), and the seam step (last -> first) must be no bigger than the largest interior
##     step (the seam check the bar was for: it was 7.7 vs 9.0 deg in the first run)
##   7 RADIUS: a 12-sided tube r 2 cm along an open 4-point 3D S-curve: every vert's distance to the curve's centre line (a
##     400-per-segment polyline, point-to-segment) is r within 0.5 %; with a taper 1 -> 0.4 every vert is r x taper(arc
##     fraction of its nearest centre point) within 0.5 %; a strap 4 cm x 4 mm: every ring's sides measure w and h within 0.5 %;
##     a tilt of 90 deg on every point turns every frame normal 90 deg about the tangent (0.01 deg)
##   8 CLOSED: a closed (4-point, one point lifted 10 cm) curve swept: closed, manifold, Euler 0, no doubled verts,
##     KMeshValidate clean, volume > 0 (outward); an open one with caps: closed, manifold, Euler 2
##   9 BELT ON THE WAIST (main.tscn, the mannequin): a closed strap (4 cm x 4 mm) round the waist (y 1.12 m), shrinkwrapped
##     3 mm: EVERY inner-face vert is 3 +- 0.5 mm from the skin (the union of every part, a target built independently from
##     the posed skin) and no belt vert is inside the body (parity); instrument: the same measure on the belt before the
##     wrap lies outside 3 +- 0.5 mm
##  10 THE PREVIEW: "op:curve_add" = ONE undo step and the curve is drawn (lines + the tube); a real mouse drag (press on
##     point 2's screen position, motion +60 px right, release) moves it: its screen position ends within 1.5 px of the
##     mouse, ONE undo step for the drag, its handles moved with it; Ctrl+Z puts the point back exactly; a field change
##     (radius 1 -> 2 -> 3 cm) is ONE step; PLACEMENT: the panel lies inside the window and its Convert button inside it;
##     "op:curve_to_mesh" = ONE step adding the sweep's verts; Ctrl+Z gives the mesh back exactly AND the curve back
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
		e.ctrl_pressed = ctrl
		e.pressed = down
		Input.parse_input_event(e)
		await process_frame


func min_area(km: KMesh) -> float:
	var lo := INF
	for fi in km.face_count():
		lo = minf(lo, km._newell(fi).length() * 0.5)
	return lo


func seg_dist(p: Vector3, a: Vector3, b: Vector3) -> Array:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-30), 0.0, 1.0)
	return [p.distance_to(a + ab * t), t]


func _init() -> void:
	b11()
	b12()
	await preview()
	print("meshcurves: %d failed" % fails)
	quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- B11

func b11() -> void:
	var sq := PackedVector3Array([Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(2, 1, 0), Vector3(1, 1, 0)])
	var km := KMeshLathe.spin(sq, {"steps": 64, "closed_profile": true})
	var vol := KMeshValidate._volume(km)
	var a := TAU / 64.0
	var exact := PI * 3.0 * sin(a) / a
	var facet := (3.0 * PI - exact) / (3.0 * PI)
	var rep := KMeshValidate.report(km)
	ok(km.vert_count() == 256 and km.face_count() == 256 and km.is_closed() and km.is_manifold() and km.euler() == 0 and KMeshValidate._doubled(km).is_empty() and rep["ok"],
		"(1) annulus lathe: %d verts (expect 256), %d faces, closed %s, manifold %s, Euler %d, doubled %d, validate %s" % [km.vert_count(), km.face_count(), km.is_closed(), km.is_manifold(), km.euler(), KMeshValidate._doubled(km).size(), str((rep["problems"] as Array).map(func(q): return q["kind"]))])
	ok(absf(vol - exact) / exact < 1e-6 and absf(vol - 3.0 * PI) / (3.0 * PI) <= 0.0017,
		"(1) volume %.6f m^3; the 64-gon faceting %.6f (diff %s rel); vs the annulus 3 pi = %.6f: %.4f %% under (the faceting error %.4f %%, bar 0.17 %%)" % [vol, exact, str(absf(vol - exact) / exact), 3.0 * PI, (3.0 * PI - vol) / (3.0 * PI) * 100.0, facet * 100.0])

	# 2 poles
	var hc := PackedVector3Array()
	for k in 17:
		var th := PI * k / 16.0
		hc.append(Vector3(sin(th) if k > 0 and k < 16 else 0.0, -cos(th), 0.0))
	var sp := KMeshLathe.spin(hc, {"steps": 32})
	var tris := 0
	for f in sp.faces:
		tris += 1 if (f as PackedInt32Array).size() == 3 else 0
	ok(sp.vert_count() == 15 * 32 + 2 and tris == 64 and sp.is_closed() and sp.is_manifold() and sp.euler() == 2 and min_area(sp) > 1e-6 and KMeshValidate.report(sp)["ok"],
		"(2) half circle on the axis: %d verts (expect %d), %d pole triangles (64), closed %s manifold %s Euler %d, smallest face %s m^2 (bar > 1e-6), volume %.4f (sphere 4.18879)" % [sp.vert_count(), 15 * 32 + 2, tris, sp.is_closed(), sp.is_manifold(), sp.euler(), str(min_area(sp)), KMeshValidate._volume(sp)])
	var cy := KMeshLathe.spin(PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)]), {"steps": 64, "closed_profile": true})
	var cyv := KMeshValidate._volume(cy)
	var cyx := PI * sin(a) / a
	ok(cy.is_closed() and cy.is_manifold() and cy.euler() == 2 and min_area(cy) > 1e-6 and absf(cyv - cyx) / cyx < 1e-6 and cy.vert_count() == 2 * 64 + 2,
		"(2) closed profile with a segment ON the axis: %d verts (130), closed %s manifold %s Euler %d, smallest face %s m^2, volume %.6f vs 64-gon pi r^2 h %.6f" % [cy.vert_count(), cy.is_closed(), cy.is_manifold(), cy.euler(), str(min_area(cy)), cyv, cyx])

	# 3 screw
	var ps := PackedVector3Array([Vector3(0.5, 0, 0), Vector3(0.6, 0, 0), Vector3(0.6, 0.1, 0), Vector3(0.5, 0.1, 0)])
	var sc := KMeshLathe.spin(ps, {"steps": 32, "turns": 2, "screw": 0.3, "closed_profile": true})
	var worst := 0.0
	var lo := INF
	var hi := -INF
	for v in sc.verts:
		lo = minf(lo, v.y)
		hi = maxf(hi, v.y)
	# ring i of profile point j is vert j * 65 + i (rings run inside each profile point's row)
	for j in 4:
		worst = maxf(worst, sc.verts[j * 65 + 64].distance_to(sc.verts[j * 65] + Vector3(0, 0.6, 0)))
	ok(sc.vert_count() == 4 * 65 and worst < 1e-6 and absf(hi - lo - 0.7) < 1e-6,
		"(3) screw 2 turns x 30 cm: %d verts (260, not welded), end ring = start ring + 60 cm within %s m, height %.6f m (0.7)" % [sc.vert_count(), str(worst), hi - lo])
	var q90 := KMeshLathe.spin(PackedVector3Array([Vector3(0.5, 0, 0), Vector3(0.5, 0.3, 0)]), {"angle": 90.0, "steps": 8})
	ok(q90.vert_count() == 18 and q90.face_count() == 8 and not q90.is_closed() and q90.is_manifold(), "(3) 90 deg, 8 steps: %d verts (18 = 9 rings), %d faces, open" % [q90.vert_count(), q90.face_count()])

	# 4 UVs on the annulus
	var uv: PackedVector2Array = km.attr_data("uv")
	var vfrac := {Vector2(1, 0): 0.0, Vector2(2, 0): 0.25, Vector2(2, 1): 0.5, Vector2(1, 1): 0.75}
	var c := 0
	var bad_u := 0
	var bad_v := 0
	for f in km.faces:
		var g: PackedInt32Array = f
		var us := []
		for i in g.size():
			us.append(uv[c + i].x)
		for i in g.size():
			var p := km.verts[g[i]]
			var ang := fposmod(atan2(-p.z, p.x), TAU) / TAU
			if ang > 1.0 - 1e-6:
				ang = 0.0
			var u: float = uv[c + i].x
			var seam: bool = ang < 1e-6 and (us.max() as float) > 0.5
			if absf(u - (1.0 if seam else ang)) > 1e-5:
				bad_u += 1
			var key2 := Vector2(roundf(Vector2(p.x, p.z).length()), roundf(p.y))
			var vx: float = vfrac[key2]
			var v: float = uv[c + i].y
			if absf(v - vx) > 1e-6 and not (vx == 0.0 and absf(v - 1.0) < 1e-6):
				bad_v += 1
		c += g.size()
	ok(bad_u == 0 and bad_v == 0 and c == uv.size(), "(4) UVs: %d of %d corners off in u (angle / 360), %d off in v (arc fraction)" % [bad_u, c, bad_v])


# ---------------------------------------------------------------- B12

func max_turn(N: PackedVector3Array, wrap := false) -> float:
	var w := 0.0
	var n := N.size()
	for i in (n if wrap else n - 1):
		w = maxf(w, rad_to_deg(N[i].angle_to(N[(i + 1) % n])))
	return w


func helix() -> KMeshCurve:
	var cv := KMeshCurve.new()
	var R := 0.3
	var pitch := 0.2
	var per := 8
	for k in 3 * per + 1:
		var th := TAU * k / per
		var p := Vector3(R * cos(th), pitch * th / TAU, -R * sin(th))
		var d := Vector3(-R * sin(th), pitch / TAU, -R * cos(th)) * (TAU / per / 3.0)
		cv.pts.append(KMeshCurve.point(p, p - d, p + d))
	cv.res = 16
	return cv


func b12() -> void:
	# 6 frames
	var hx := helix()
	var sm := hx.samples()
	var N := KMeshCurve.rmf(sm["x"], sm["t"])
	var sq := 0.0
	for i in N.size():
		sq = maxf(sq, absf(N[i].dot((sm["t"] as PackedVector3Array)[i])))
	ok(max_turn(N) < 5.0 and sq < 1e-6, "(6) helix, %d samples: RMF normal turns at most %.2f deg between samples (bar 5), off square %s" % [N.size(), max_turn(N), str(sq)])
	var ring := KMeshCurve.circle(Vector3.ZERO, 0.3, Vector3.BACK)
	for d in ring.pts:   # 10 deg about Z so no sample lands exactly on a vertical tangent
		for k in ["p", "l", "r"]:
			d[k] = (d[k] as Vector3).rotated(Vector3.BACK, deg_to_rad(10.0))
	ring.res = 32
	var rs := ring.samples()
	var upN := PackedVector3Array()
	for t in (rs["t"] as PackedVector3Array):
		upN.append((Vector3.UP - t * t.dot(Vector3.UP)).normalized())
	var rN := KMeshCurve.rmf(rs["x"], rs["t"], true, rs["s"], rs["L"])
	ok(max_turn(upN, true) > 90.0 and max_turn(rN, true) < 5.0, "(6) a circle standing in XY: the up-vector frame turns %.1f deg between two samples (the flip, instrument > 90), the RMF %.2f deg (bar 5), last -> first included" % [max_turn(upN, true), max_turn(rN, true)])
	var lift := KMeshCurve.circle(Vector3.ZERO, 0.3)
	lift.pts[1]["p"] += Vector3(0, 0.1, 0)
	lift.pts[1]["l"] += Vector3(0, 0.1, 0)
	lift.pts[1]["r"] += Vector3(0, 0.1, 0)
	lift.res = 32
	var ls := lift.samples()
	var lN := KMeshCurve.rmf(ls["x"], ls["t"], true, ls["s"], ls["L"])
	var seam := rad_to_deg(lN[lN.size() - 1].angle_to(lN[0]))
	ok(max_turn(lN, true) < 5.0 and seam <= max_turn(lN) + 1e-9, "(6) a closed lifted circle: the frame comes round, %.2f deg at most between samples (bar 5); the seam step %.2f deg <= the largest interior %.2f" % [max_turn(lN, true), seam, max_turn(lN)])

	# 7 radius
	var cv := KMeshCurve.new()
	cv.pts = [KMeshCurve.point(Vector3(0, 0, 0), Vector3(-0.1, 0, 0), Vector3(0.15, 0.1, 0.05)),
		KMeshCurve.point(Vector3(0.4, 0.2, 0.1), Vector3(0.3, 0.2, -0.05), Vector3(0.5, 0.2, 0.25)),
		KMeshCurve.point(Vector3(0.7, 0.0, 0.3), Vector3(0.65, 0.1, 0.2), Vector3(0.75, -0.1, 0.4)),
		KMeshCurve.point(Vector3(1.0, -0.1, 0.2), Vector3(0.9, -0.1, 0.3), Vector3(1.1, -0.1, 0.1))]
	cv.radius = 0.02
	cv.sides = 12
	cv.res = 24
	for tap in [false, true]:
		cv.taper = PackedVector2Array([Vector2(0, 1), Vector2(1, 0.4)]) if tap else PackedVector2Array()
		var r := cv.sweep()
		var km: KMesh = r["mesh"]
		var poly := cv.polyline(400)
		var acc := PackedFloat64Array([0.0])
		for i in range(1, poly.size()):
			acc.append(acc[i - 1] + poly[i].distance_to(poly[i - 1]))
		var Ltot := acc[acc.size() - 1]
		var np: int = r["ring"]
		var nring: int = km.vert_count() / np
		var worst := 0.0
		for ri in nring:
			var centre_i := int(round(float(ri) / (nring - 1) * (poly.size() - 1)))
			for k in np:
				var p := km.verts[ri * np + k]
				var best := INF
				var bf := 0.0
				for j in range(maxi(0, centre_i - 250), mini(poly.size() - 1, centre_i + 250)):
					var dd := seg_dist(p, poly[j], poly[j + 1])
					if dd[0] < best:
						best = dd[0]
						bf = (acc[j] + (acc[j + 1] - acc[j]) * float(dd[1])) / Ltot
				var want := 0.02 * (lerpf(1.0, 0.4, bf) if tap else 1.0)
				worst = maxf(worst, absf(best - want) / want)
		ok(worst < 0.005, "(7) %s tube, %d rings x %d: worst |distance to the centre line - target| %.3f %% (bar 0.5 %%)" % ["tapered 1 -> 0.4" if tap else "plain", nring, np, worst * 100.0])
	cv.taper = PackedVector2Array()
	cv.profile = "rect"
	cv.width = 0.04
	cv.height = 0.004
	var rr := cv.sweep()
	var rk: KMesh = rr["mesh"]
	var np2: int = rr["ring"]
	var wworst := 0.0
	for ri in rk.vert_count() / np2:
		var b := ri * np2
		# profile order: 0 (-h,-w) 1 (h,-w) ... 1+segs (h,w) 2+segs (-h,w)
		var hh := rk.verts[b].distance_to(rk.verts[b + 1])
		var ww := rk.verts[b + 1].distance_to(rk.verts[b + 1 + cv.rect_segs])
		wworst = maxf(wworst, maxf(absf(hh - 0.004) / 0.004, absf(ww - 0.04) / 0.04))
	ok(wworst < 0.005, "(7) strap 4 cm x 4 mm: every ring's sides within %.3f %% (bar 0.5 %%)" % (wworst * 100.0))
	var n_flat: PackedVector3Array = rr["n"]
	var t_flat: PackedVector3Array = rr["t"]
	for d in cv.pts:
		d["tilt"] = 90.0
	var n_tilt: PackedVector3Array = cv.sweep()["n"]
	var tw_worst := 0.0
	for i in n_flat.size():
		var ang := rad_to_deg(atan2(t_flat[i].dot(n_flat[i].cross(n_tilt[i])), n_flat[i].dot(n_tilt[i])))
		tw_worst = maxf(tw_worst, absf(ang - 90.0))
	ok(tw_worst < 0.01, "(7) TILT 90 deg at every point: every frame normal turned 90 deg about the tangent within %.4f deg" % tw_worst)
	for d in cv.pts:
		d["tilt"] = 0.0

	# 8 closed
	lift.radius = 0.03
	lift.res = 16
	var lk: KMesh = lift.sweep()["mesh"]
	var rep := KMeshValidate.report(lk)
	ok(lk.is_closed() and lk.is_manifold() and lk.euler() == 0 and KMeshValidate._doubled(lk).is_empty() and rep["ok"] and KMeshValidate._volume(lk) > 0.0,
		"(8) closed curve: %d verts, closed %s, manifold %s, Euler %d, doubled %d, validate %s, volume %.5f m^3 (torus 2 pi^2 R r^2 ~ %.5f)" % [lk.vert_count(), lk.is_closed(), lk.is_manifold(), lk.euler(), KMeshValidate._doubled(lk).size(), str((rep["problems"] as Array).map(func(q): return q["kind"])), KMeshValidate._volume(lk), 2.0 * PI * PI * 0.3 * 0.0009])
	cv.profile = "circle"
	var ok8: KMesh = cv.sweep()["mesh"]
	ok(ok8.is_closed() and ok8.is_manifold() and ok8.euler() == 2 and KMeshValidate._volume(ok8) > 0.0, "(8) open curve with caps: closed %s, manifold %s, Euler %d, volume %.6f > 0" % [ok8.is_closed(), ok8.is_manifold(), ok8.euler(), KMeshValidate._volume(ok8)])


# ---------------------------------------------------------------- the mannequin + the preview

func preview() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.get("ui_tour") != null and m.ui_tour != null:
		m.ui_tour.visible = false

	# 9 the belt (the body's own space: the model preview is not open, so the target is in it)
	var sw := KMeshShrinkwrap.body(m)
	var belt := KMeshCurve.circle(Vector3(0.0, 1.12, 0.02), 1.0)
	for d in belt.pts:
		for k in ["p", "l", "r"]:
			var q: Vector3 = d[k] - Vector3(0.0, 1.12, 0.02)
			d[k] = Vector3(0.0, 1.12, 0.02) + Vector3(q.x * 0.17, q.y, q.z * 0.15)
	belt.profile = "rect"
	belt.width = 0.04
	belt.height = 0.004
	belt.res = 16
	var kw := KMeshShrinkwrap.posed_body(m)
	var tw := KMeshShrinkwrap.build(KMesh.new().from_arrays(kw.verts, kw.faces))   # independent of the cached target
	var twf := tw.full if tw.full != null else tw
	var raw: KMesh = belt.sweep()["mesh"]   # INSTRUMENT: the same measure on the belt before the wrap must fail the bar
	var rlo := INF
	var rhi := 0.0
	for v in raw.vert_count():
		if belt.inner_ids().has(v % int(belt.profile_2d().size())):
			var d := float(twf.nearest(raw.verts[v])["d"])
			rlo = minf(rlo, d)
			rhi = maxf(rhi, d)
	ok(rhi > 0.0035 or rlo < 0.0025, "(9) instrument: the belt before the wrap is %.1f .. %.1f mm off the skin (outside 3 +- 0.5: the measure can fail)" % [rlo * 1000.0, rhi * 1000.0])
	belt.wrap(sw, 0.003)
	var r := belt.sweep(sw)
	var bk: KMesh = r["mesh"]
	var inner := belt.inner_ids()
	var np: int = r["ring"]
	var worst := 0.0
	var dmin := INF
	var dmax := 0.0
	var n_in := 0
	var inside := 0
	for v in bk.vert_count():
		if tw.inside(bk.verts[v]):
			inside += 1
		if not inner.has(v % np):
			continue
		var d := float(twf.nearest(bk.verts[v])["d"])
		n_in += 1
		worst = maxf(worst, absf(d - 0.003))
		dmin = minf(dmin, d)
		dmax = maxf(dmax, d)
	ok(n_in > 100 and worst <= 0.0005 and inside == 0, "(9) the belt on the waist: %d inner verts %.2f .. %.2f mm off the skin (bar 3 +- 0.5), %d of %d belt verts inside the body (bar 0)" % [n_in, dmin * 1000.0, dmax * 1000.0, inside, bk.vert_count()])

	# 5 + 10 the preview
	m._kmesh_edit_start()
	await idle(3)
	var ui: KMeshEditUI = m.kmed
	var v0 := ui.mesh.verts.duplicate()
	var f0 := ui.mesh.faces.duplicate()
	# a vertical chain of 4 edges on the cube's +X side (x = +0.3, z = 0, y -0.3 .. 0.3)
	var col := []
	for i in ui.mesh.vert_count():
		var p := ui.mesh.verts[i]
		if absf(p.x - 0.3) < 1e-6 and absf(p.z) < 1e-6:
			col.append(i)
	col.sort_custom(func(a, b): return ui.mesh.verts[a].y < ui.mesh.verts[b].y)
	ui.set_mode(KMeshSelect.EDGE)
	ui.sel.edges = {}
	for i in col.size() - 1:
		ui.sel.edges[KMeshSelect.ekey(col[i], col[i + 1])] = true
	ui.pivot.cursor = ui.view.global_transform * Vector3(0.0, 0.0, 0.0)
	var n0 := ui.undo.steps.size()
	var said := MeshTools.op("lathe", m)
	await idle(2)
	var c1 := ui.mesh.vert_count()
	ok(col.size() == 5 and ui.undo.steps.size() == n0 + 1 and c1 == 98 + 5 * 32, "(5) lathe of the cube's 4-edge column: one step (%d), %d verts (expect %d): %s" % [ui.undo.steps.size() - n0, c1, 98 + 5 * 32, said])
	var cu := KMeshCurvesUI.of(ui)
	(cu._f["steps"] as SpinBox).value = 12
	await idle(2)
	ok(ui.undo.steps.size() == n0 + 1 and ui.mesh.vert_count() == 98 + 5 * 12 and cu.lathe_is_live(), "(5) steps 32 -> 12: %d verts (expect %d), still one step (%d)" % [ui.mesh.vert_count(), 98 + 5 * 12, ui.undo.steps.size() - n0])
	await key(KEY_Z, true)
	ok(ui.mesh.verts == v0 and KMeshUndo._same_faces(ui.mesh.faces, f0), "(5) Ctrl+Z: the test cube back exactly (%d verts)" % ui.mesh.vert_count())
	(cu._f["steps"] as SpinBox).value = 32

	# 10 the curve
	ui.set_mode(KMeshSelect.VERT)
	var n1 := ui.undo.steps.size()
	said = MeshTools.op("curve_add", m)
	await idle(2)
	var im := cu.lines.mesh as ImmediateMesh
	ok(cu.curve != null and ui.undo.steps.size() == n1 + 1 and im.get_surface_count() == 2 and cu.tube.mesh != null, "(10) new curve: one step (%d), drawn (%d line surfaces, tube %s): %s" % [ui.undo.steps.size() - n1, im.get_surface_count(), cu.tube.mesh != null, said])
	var cam: Camera3D = m.cam
	var p_before: Dictionary = (cu.curve.pts[1] as Dictionary).duplicate()
	var s0 := cam.unproject_position(ui.view.global_transform * (p_before["p"] as Vector3))
	var s1 := s0 + Vector2(60, 0)
	var n2 := ui.undo.steps.size()
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = s0
	m._unhandled_input(e)
	for k in 6:
		var mm := InputEventMouseMotion.new()
		mm.position = s0.lerp(s1, (k + 1) / 6.0)
		m._unhandled_input(mm)
		await process_frame
	var e2 := InputEventMouseButton.new()
	e2.button_index = MOUSE_BUTTON_LEFT
	e2.pressed = false
	e2.position = s1
	m._unhandled_input(e2)
	await idle(2)
	var pa: Dictionary = cu.curve.pts[1]
	var s_now := cam.unproject_position(ui.view.global_transform * (pa["p"] as Vector3))
	var dv: Vector3 = pa["p"] - p_before["p"]
	var hand_ok: bool = (pa["l"] - p_before["l"]).distance_to(dv) < 1e-6 and (pa["r"] - p_before["r"]).distance_to(dv) < 1e-6
	ok(s_now.distance_to(s1) < 1.5 and dv.length() > 0.01 and hand_ok and ui.undo.steps.size() == n2 + 1,
		"(10) PICK + DRAG: point 2 from %s to %s px (mouse %s, off %.2f px, bar 1.5), moved %.1f cm, handles with it %s, one step (%d)" % [s0, s_now, s1, s_now.distance_to(s1), dv.length() * 100.0, hand_ok, ui.undo.steps.size() - n2])
	await key(KEY_Z, true)
	ok((cu.curve.pts[1]["p"] as Vector3) == p_before["p"] and ui.mesh.verts == v0, "(10) Ctrl+Z puts the point back exactly (the mesh untouched)")
	var n3 := ui.undo.steps.size()
	for x in [2.0, 3.0]:
		(cu._f["radius"] as SpinBox).value = x
		await process_frame
	ok(ui.undo.steps.size() == n3 + 1 and absf(cu.curve.radius - 0.03) < 1e-9, "(10) radius 1 -> 2 -> 3 cm: one step (%d), radius %.1f cm" % [ui.undo.steps.size() - n3, cu.curve.radius * 100.0])
	await idle(2)
	var win := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var pr := cu.panel.get_global_rect()
	var cb := cu.panel.find_child("btn_curve_to_mesh", true, false) as Control
	ok(cu.panel.visible and win.encloses(pr) and cb != null and pr.encloses(cb.get_global_rect()), "(10) PLACEMENT: the panel %s inside the window %s, Convert %s inside it" % [pr, win.size, cb.get_global_rect() if cb != null else Rect2()])
	var nv: int = (cu.curve.sweep()["mesh"] as KMesh).vert_count()
	var n4 := ui.undo.steps.size()
	said = MeshTools.op("curve_to_mesh", m)
	await idle(2)
	ok(ui.undo.steps.size() == n4 + 1 and ui.mesh.vert_count() == 98 + nv and cu.curve == null, "(10) convert to mesh: one step (%d), +%d verts (the sweep's %d), the curve gone: %s" % [ui.undo.steps.size() - n4, ui.mesh.vert_count() - 98, nv, said])
	await key(KEY_Z, true)
	ok(ui.mesh.verts == v0 and KMeshUndo._same_faces(ui.mesh.faces, f0) and cu.curve != null and absf(cu.curve.radius - 0.03) < 1e-9, "(10) Ctrl+Z: the mesh back exactly and the curve back (radius %.1f cm)" % (cu.curve.radius * 100.0 if cu.curve != null else -1.0))
	await key(KEY_ESCAPE)
	await idle(2)
	ok(not cu.panel.visible and cu.curve == null, "(10) leaving the preview drops the curve and hides the panel")
