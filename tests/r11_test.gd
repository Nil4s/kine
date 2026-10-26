## godot --path . -s tests/r11_test.gd     (ROADMAP round 2, R11: body mass thickens the skin; needs a window)
## Sources: ANSUR II public files (Gordon et al. 2014, NATICK/TR-15/007; 4082 men, 1986 women). The elasticity of a
## circumference to body mass at a fixed stature, e in  ln C = a + e ln(mass) + c ln(stature)  (recomputed for R11, the
## table is in scripts/proportions.gd): waist (omphalion) 0.728, thigh 0.573, forearm (flexed) 0.368 for men. So mass
## P5 -> P95 (a factor m95/m5 = 1.72) grows C by (m95/m5)^e: waist x1.48, thigh x1.36, forearm x1.22.
## BARS, written before measuring (one man, 50th-percentile stature 1.756 m, T pose, mass at the 5th / 50th / 95th):
##  1 WAIST from the MESH: the convex hull perimeter of the skinned vertices in a 1.5 cm slab at the omphalion height
##    (0.6016 stature, ANSUR II men's mean 1056 / 1756) grows by the ANSUR ratio (m95/m5)^0.728 within 15 %
##  2 FOREARM grows less than the waist, and by (m95/m5)^0.368 within 15 % (mid-forearm slab across its axis)
##  3 BONES UNCHANGED: every segment length (Proportions.lengths) and every joint's rest point, 5th vs 95th, < 0.1 mm
##  4 SOLES: sole_low within 1 mm of the floor at all three, and the lowest skin vertex moves < 1 mm between the 5th and 95th
##  5 COLLISION IN STEP: the thigh capsule radius ratio 95th / 5th equals exp(e x d-lambda) of the thigh within 0.1 %, and
##    the thigh's mesh circumference ratio is within 15 % of it
##  6 ONE UNDO STEP per mass drag (12 moves = +1), history untouched mid-drag; Ctrl+Z gives the scene JSON back exactly
##  7 NOTHING WRITTEN: data/skeleton.json bytes identical
##  8 PLACEMENT (whole-body view): the three people of the same height (head tops within 3 px, soles on the floor), the
##    95th wider on screen than the 5th at the belt row, all inside the view. Screenshot: jobs/9afc22db/tmp/r11.png
extends SceneTree

var m: Node
var fails := 0
const OUT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/r11.png"
const E_WAIST := 0.728
const E_FOREARM := 0.368
const E_THIGH := 0.573


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func hull_perimeter(pts: Array) -> float:   # Array of Vector2, Andrew's monotone chain
	var p := pts.duplicate()
	p.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	if p.size() < 3:
		return 0.0
	var h := []
	for pass_i in 2:
		var start := h.size()
		for q in p:
			while h.size() >= start + 2 and ((h[-1] - h[-2]) as Vector2).cross((q as Vector2) - (h[-2] as Vector2)) <= 0.0:
				h.pop_back()
			h.append(q)
		h.pop_back()
		p.reverse()
	var per := 0.0
	for i in h.size():
		per += ((h[i] as Vector2) - (h[(i + 1) % h.size()] as Vector2)).length()
	return per


## every skinned vertex now (world), from the app's own pick skinning (it reads the meshes as drawn)
func verts() -> PackedVector3Array:
	m.skp.mark()
	m.skp.refresh()
	var out := PackedVector3Array()
	for s in m.skp.surfs:
		out.append_array(s["pos"])
	return out


## the posed vertices whose dominant part (the pick's rule) is one of these parts
func part_verts(names: Array) -> PackedVector3Array:
	m.skp.mark()
	m.skp.refresh()
	var want := {}
	for n in names:
		want[Body.ORDER.find(n)] = true
	var out := PackedVector3Array()
	for s in m.skp.surfs:
		var per: int = s["per"]
		var bo: PackedInt32Array = s["bones"]
		var w: PackedFloat32Array = s["w"]
		var pos: PackedVector3Array = s["pos"]
		for i in pos.size():
			var acc := {}
			for q in per:
				var pi: int = m.skp.bind_part[bo[i * per + q]]
				acc[pi] = float(acc.get(pi, 0.0)) + w[i * per + q]
			var best := -1
			for pi in acc:
				if best < 0 or acc[pi] > acc[best]:
					best = pi
			if want.has(best):
				out.append(pos[i])
	return out


## slab perimeters. axis 1 = a horizontal slab at height c (hull in x,z), axis 0 = a slab across x at c (hull in y,z; one side)
func girth_at(axis: int, c: float, half: float, side := 0.0) -> float:
	var pts := []
	for v in verts():
		if absf(v[axis] - c) > half:
			continue
		if side > 0.0 and v.x < 0.0:
			continue
		if axis == 1:
			if absf(v.x) < 0.6:   # the torso column (a T-pose arm is at shoulder height, far above)
				pts.append(Vector2(v.x, v.z))
		else:
			pts.append(Vector2(v.y, v.z))
	return hull_perimeter(pts)


func set_mass(p: float) -> void:
	var pr := BodyModel.DEFAULT.duplicate()
	pr["mass"] = p
	m.proportions_set(BodyModel.body_for(pr))
	for j in Body.ORDER:
		m.B.ang[j] = Vector3.ZERO
	m.B.offset = Vector3.ZERO
	m.B.offset.y -= m.B.sole_low()
	m.B.fk()
	m._refresh()


func measure() -> Dictionary:
	await idle(2)
	var st := float(m.B.body["stature"])
	var lo := INF
	for v in verts():
		lo = minf(lo, v.y)
	var d := {"waist": girth_at(1, lo + 0.6016 * st, 0.0075), "lo": lo, "sole": m.B.sole_low()}
	var mid: float = ((m.B.P["lowerarm_l"] as Vector3).x + (m.B.P["hand_l"] as Vector3).x) * 0.5
	d["forearm"] = girth_at(0, mid, 0.0075, 1.0)
	var tx: float = (m.B.P["thigh_l"] as Vector3).y * 0.55 + (m.B.P["calf_l"] as Vector3).y * 0.45
	d["thigh"] = girth_at(1, tx, 0.03, 1.0)   # the leg mesh has sparse rings: a wider slab
	if float(d["thigh"]) == 0.0:
		var cnt := 0
		var mnx := INF
		var mxx := -INF
		for v in verts():
			if absf(v.y - tx) < 0.0075:
				cnt += 1
				mnx = minf(mnx, v.x)
				mxx = maxf(mxx, v.x)
		print("     thigh slab empty at y=%.3f: %d vertices, x %.3f..%.3f" % [tx, cnt, mnx, mxx])
	d["lens"] = Proportions.lengths(m.B)
	var pj := {}
	for j in Body.ORDER:
		pj[j] = m.B.p0[j]
	d["p0"] = pj
	d["rad_thigh"] = float(m.B.rad["thigh_l"])
	d["lam"] = Proportions.girth_lambda(m.B.body)
	d["top"] = Proportions.head_top(m.B).y
	return d


func _init() -> void:
	var skel0 := FileAccess.get_file_as_bytes("res://data/skeleton.json")
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m._page_set("BODY", false)
	await idle(4)
	var P: BodyPanel = m.ui_body
	var u0: int = m.undo.size()
	var scene0 := JSON.stringify(m.S.to_dict(m.B))
	# ---- one undo step per mass drag
	var sl: HSlider = P.sliders["mass"]
	sl.drag_started.emit()
	var mid_ok := true
	for i in 12:
		sl.value = lerpf(50.0, 95.0, float(i + 1) / 12.0)
		mid_ok = mid_ok and m.undo.size() == u0
	sl.drag_ended.emit(true)
	await idle()
	ok(mid_ok and m.undo.size() == u0 + 1, "6 a mass drag (12 moves): history untouched mid-drag, then exactly ONE undo step (%d -> %d)" % [u0, m.undo.size()])
	ok(absf(m.corr.last_lambda) > 0.1, "6 the skin follows the slider: girth lambda %.3f (mass %.1f kg)" % [m.corr.last_lambda, float(m.B.body.get("mass", 0.0))])
	m._undo()
	await idle(2)
	ok(JSON.stringify(m.S.to_dict(m.B)) == scene0 and m.undo.size() == u0 and m.corr.last_lambda == 0.0, "6 Ctrl+Z: scene JSON identical (%d bytes), the girth back to 0" % scene0.length())
	# ---- the three men
	var R := {}
	for p in [5, 50, 95]:
		set_mass(float(p))
		R[p] = await measure()
		var r: Dictionary = R[p]
		print("     %2dth mass %.1f kg: lambda %+.3f, waist %.1f cm, forearm %.1f cm, thigh %.1f cm, thigh capsule r %.1f mm, sole %.2f mm" % [
			p, float(m.B.body["mass"]), float(r["lam"]), float(r["waist"]) * 100.0, float(r["forearm"]) * 100.0, float(r["thigh"]) * 100.0, float(r["rad_thigh"]) * 1000.0, float(r["sole"]) * 1000.0])
	var mr: float = float(BodyModel.mass_at(1.0, 95.0)) / float(BodyModel.mass_at(1.0, 5.0))
	var w5: Dictionary = R[5]
	var w95: Dictionary = R[95]
	var want_w := pow(mr, E_WAIST)
	var got_w: float = float(w95["waist"]) / float(w5["waist"])
	ok(absf(got_w / want_w - 1.0) < 0.15, "1 waist circumference from the mesh x%.3f for mass x%.3f; ANSUR II x%.3f (%+.1f %%, bar 15 %%)" % [got_w, mr, want_w, (got_w / want_w - 1.0) * 100.0])
	var want_f := pow(mr, E_FOREARM)
	var got_f: float = float(w95["forearm"]) / float(w5["forearm"])
	ok(got_f < got_w and absf(got_f / want_f - 1.0) < 0.15, "2 forearm x%.3f < waist x%.3f; ANSUR II x%.3f (%+.1f %%)" % [got_f, got_w, want_f, (got_f / want_f - 1.0) * 100.0])
	var drl: float = float(w95["lam"]) - float(w5["lam"])
	var got_t: float = float(w95["thigh"]) / float(w5["thigh"])
	var want_t := pow(mr, E_THIGH)
	var rr: float = float(w95["rad_thigh"]) / float(w5["rad_thigh"])
	var maxl := 0.0
	for k in w5["lens"]:
		maxl = maxf(maxl, absf(float(w5["lens"][k]) - float(w95["lens"][k])))
	var maxp := 0.0
	for j in Body.ORDER:
		maxp = maxf(maxp, ((w5["p0"][j] as Vector3) - (w95["p0"][j] as Vector3)).length())
	ok(maxl < 1e-4 and maxp < 1e-4, "3 bone lengths 5th vs 95th differ by %.4f mm, rest joints by %.4f mm (bar 0.1 mm)" % [maxl * 1000.0, maxp * 1000.0])
	var soles := true
	for p in [5, 50, 95]:
		soles = soles and absf(float(R[p]["sole"])) < 0.001
	ok(soles and absf(float(w95["lo"]) - float(w5["lo"])) < 0.001, "4 soles: sole_low %.2f / %.2f / %.2f mm, lowest skin vertex 5th %.2f mm vs 95th %.2f mm" % [float(R[5]["sole"]) * 1000.0, float(R[50]["sole"]) * 1000.0, float(R[95]["sole"]) * 1000.0, float(w5["lo"]) * 1000.0, float(w95["lo"]) * 1000.0])
	ok(absf(rr - exp(0.575 * drl)) < 0.001 * rr and absf(got_t / rr - 1.0) < 0.15, "5 thigh capsule radius x%.3f (= exp(0.575 x %.3f)); thigh mesh circumference x%.3f (ANSUR x%.3f), %+.1f %% from the capsule" % [rr, drl, got_t, want_t, (got_t / rr - 1.0) * 100.0])
	ok(absf(float(w5["top"]) - float(w95["top"])) < 0.0005, "3 same height: head top %.4f vs %.4f m" % [float(w5["top"]), float(w95["top"])])
	ok(FileAccess.get_file_as_bytes("res://data/skeleton.json") == skel0, "7 data/skeleton.json is byte-identical")
	# ---- 8 placement: three people, one camera
	if m.dummy_on:
		m._dummy_toggle()
	m.sel = "pelvis"
	m._do(func(): m._arms_relaxed())
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var view_r := Rect2(m.lw(), 60.0, vs.x - m.lw() - m.rw(), vs.y - m.bottom_h - 60.0)
	var pic := {}
	var tops := {}
	var wide := {}
	var cxs := {}
	for q in [5, 50, 95]:
		P.pr["stat"] = 50.0
		P.pr["mass"] = float(q)
		P._set_sliders()
		P.begin.emit()
		P.commit.emit(BodyModel.body_for(P.pr))
		m.B.offset.y -= m.B.sole_low()
		m.B.fk()
		await idle(3)
		m._view(1)
		await idle(6)
		await RenderingServer.frame_post_draw
		pic[q] = m.get_viewport().get_texture().get_image()
		tops[q] = m.cam.unproject_position(Proportions.head_top(m.B))
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var vy: float = (m.B.P["pelvis"] as Vector3).y + 0.15
		var minx := INF
		var maxx := -INF
		for v in verts():
			var sp: Vector2 = m.cam.unproject_position(v)
			lo = lo.min(sp)
			hi = hi.max(sp)
		for v in part_verts(["pelvis", "spine_01", "spine_02"]):   # the trunk's own skin (the relaxed arms hang beside it)
			if absf(v.y - vy) < 0.04:
				var sp2: Vector2 = m.cam.unproject_position(v)
				minx = minf(minx, sp2.x)
				maxx = maxf(maxx, sp2.x)
		wide[q] = maxx - minx
		cxs[q] = (lo.x + hi.x) * 0.5
		print("     %dth: head top y %.0f px, skin box %s, belt row %.0f px wide, soles %.2f mm off the floor" % [q, tops[q].y, Rect2(lo, hi - lo), wide[q], m.B.sole_low() * 1000.0])
		ok(view_r.has_point(lo) and view_r.has_point(hi), "8 %dth inside the view %s" % [q, view_r])
	ok(absf(tops[5].y - tops[95].y) < 3.0 and absf(tops[50].y - tops[95].y) < 3.0, "8 same height on screen: head tops y %.0f / %.0f / %.0f px" % [tops[5].y, tops[50].y, tops[95].y])
	ok(wide[95] > wide[50] * 1.10 and wide[50] > wide[5] * 1.10, "8 wider with mass on screen at the belt row: %.0f / %.0f / %.0f px" % [wide[5], wide[50], wide[95]])
	var sc: float = float((pic[95] as Image).get_width()) / vs.x
	var half := int(190.0 * sc)
	var gap := int(240.0 * sc)
	var y0 := int(60.0 * sc)
	var hh := int((vs.y - m.bottom_h - 60.0) * sc)
	var out: Image = (pic[95] as Image).duplicate()
	var mid := int(((m.lw() + vs.x - m.rw()) * 0.5) * sc)
	out.fill_rect(Rect2i(int(m.lw() * sc), y0, int((vs.x - m.lw() - m.rw()) * sc), hh), out.get_pixel(int(vs.x * sc) - 5, y0 + 5))
	for pair in [[5, mid - gap], [50, mid], [95, mid + gap]]:
		var cxq := int(float(cxs[pair[0]]) * sc)
		out.blit_rect(pic[pair[0]], Rect2i(cxq - half, y0, 2 * half, hh), Vector2i(pair[1] - half, y0))
	out.save_png(OUT)
	print("     screenshot: %s (%dx%d): 5th, 50th, 95th percentile mass, one man, one camera" % [OUT, out.get_width(), out.get_height()])
	print("R11 %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
