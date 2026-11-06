## godot --path . -s tests/wrinkle_test.gd     (L62, ROADMAP I09: EXPRESSION-DRIVEN WRINKLES on the geometry face. Needs a window: :w.)
## scripts/face_wrinkle.gd measures, per mask vertex, how much the posed skin is COMPRESSED against rest (a 2x2 Green strain in the
## tangent plane, fitted from the incident edges; the heavy loop is KineWrinkleNative in C++, GDScript twin = the fallback). The most
## compressive principal direction gives the wrinkle line (perpendicular to it) and the depth; the face shader draws the ridges.
## Because the strain is MEASURED from the blendshapes, it works for any AU mix. FaceWrinkle.EXTRA adds AU2 (outer brow raiser) and
## AU9 (nose wrinkler), which d["au"] does not hold.
## SOURCES (FROM MEMORY, not re-read this run): Ekman, Friesen & Hager, FACS manual (2002): AU1/AU2 "wrinkles across the forehead
## (horizontal)", AU4 "vertical wrinkles between the brows", AU6 "crow's feet: lines radiating from the outer eye corner", AU9 "wrinkles
## along the sides of the nose root, the bunny lines", AU12 "deepens the nasolabial furrow (nose wing to the mouth corner)".
## Bars written BEFORE the implementation and committed first (they fail on the base). Planted controls: the same checker on a wrong input
## must say FAIL.
##  W1 at neutral the wrinkle normal delta is < 1e-3 everywhere; CONTROL AU1+AU2 = 1: the forehead delta >= 0.15 (a slope of 0.15 = 8.5 deg).
##  W2 each AU lights ONLY its region: >= 80 % of sum(amp^2) inside the AU's anatomical mask (masks below, from the landmarks x s), and the
##     AU lights it (max normal delta in the mask >= 0.15). CONTROL: the same energy against another AU's mask must be < 80 %.
##  W3 line orientation (xy, frontal; axial angles): forehead mean within 15 deg of the brow line (principal axis of the brow vertices);
##     glabella within 15 deg of vertical; crow's feet: amp-weighted mean |angle to the radial from the lateral canthus| <= 20 deg;
##     nasolabial within 15 deg of the wing-to-corner line. CONTROL: every direction turned 90 deg must break each.
##  W4 cost, one head, 1080p: CPU (compute with changing AUs, ms) + GPU (wrinkle shader vs the plain mask, ms, clipped at 0), medians of 5 <= 0.5.
##  W5 save/reload and undo exact: state hash after a JSON round trip of the AU state, and after change + undo, equals the original.
##  W6 native == GDScript twin (strain 1e-5, direction 1e-4), native present.
##  W7 the app: face_geo_au AU1 -> the mask mesh carries CUSTOM0 with the wrinkle amplitude, a ShaderMaterial; neutral -> 0.
##  W8 RENDER: forehead high-frequency energy at AU1+2 / neutral >= 2.0; CONTROL the shader with wrinkles off at AU1+2: <= 1.2.
##  FACE_WRINKLE_SHOT=<path> writes the contact sheet (neutral | AU1+2 | AU6+12), <= 1000 px wide.
extends SceneTree

var fails := 0
var m: Node
const MM := 1000.0
var WR: GDScript = load("res://scripts/face_wrinkle.gd") if ResourceLoader.exists("res://scripts/face_wrinkle.gd") else null


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func stt(au := {}) -> Dictionary:
	return {"au": au, "jaw_deg": 0.0, "eye_pitch_deg": 0.0, "eye_yaw_deg": 0.0}


func skinned_head(mm: Node) -> PackedVector3Array:
	return mm.call("_head_pts")


# ---------------------------------------------------------------- masks (metres, x s); every one from the landmarks of d["anchors"]
## returns {name: Callable(Vector3)->bool}; frontal (x, y) tests only
func make_masks(d: Dictionary) -> Dictionary:
	var an: Dictionary = d["anchors"]
	var s := float(an["top"]) / 1.754
	var hx := float((an["eye_l"] as Vector3).x)
	var ey := float((an["eye_l"] as Vector3).y)
	var by := float((an["brow_l"] as Vector3).y)
	var my := float((an["mouth"] as Vector3).y)
	var wing := Vector2(0.019 * s, my + 0.022 * s)       # the alar groove (nose wing), x of the left side
	var corner := Vector2(0.031 * s, my - 0.004 * s)     # the fold ends just lateral of the mouth corner
	var masks := {}
	masks["AU1"] = func(p: Vector3) -> bool: return absf(p.x) <= 0.040 * s and p.y >= by + 0.004 * s and p.y <= by + 0.030 * s
	masks["AU4"] = func(p: Vector3) -> bool: return absf(p.x) <= 0.014 * s and p.y >= by - 0.012 * s and p.y <= by + 0.016 * s
	masks["AU6"] = func(p: Vector3) -> bool:
		for sg in [-1.0, 1.0]:
			var c := Vector2(sg * (hx + 0.015 * s), ey)
			if Vector2(p.x, p.y).distance_to(c) <= 0.028 * s and absf(p.x) >= hx + 0.008 * s:
				return true
		return false
	masks["AU12"] = func(p: Vector3) -> bool:
		var q := Vector2(absf(p.x), p.y)
		var ab := corner - wing
		var t := clampf((q - wing).dot(ab) / ab.length_squared(), 0.0, 1.0)
		return q.distance_to(wing + ab * t) <= 0.012 * s
	masks["AU9"] = func(p: Vector3) -> bool: return absf(p.x) >= 0.005 * s and absf(p.x) <= 0.020 * s and p.y >= ey - 0.020 * s and p.y <= ey + 0.004 * s
	return masks


func energy_in(d: Dictionary, w: Dictionary, mask: Callable) -> Dictionary:
	var vs: PackedVector3Array = d["verts"]
	var amp: PackedFloat32Array = w["amp"]
	var tot := 0.0
	var inn := 0.0
	for i in vs.size():
		var e := float(amp[i]) * float(amp[i])
		tot += e
		if mask.call(vs[i]):
			inn += e
	return {"tot": tot, "in": inn, "frac": inn / tot if tot > 1.0e-12 else 0.0}


func max_delta(d: Dictionary, w: Dictionary, mask: Callable) -> float:
	var nd: PackedVector3Array = WR.call("normal_delta", d, w)
	var vs: PackedVector3Array = d["verts"]
	var mx := 0.0
	for i in vs.size():
		if mask.is_valid() and not mask.call(vs[i]):
			continue
		mx = maxf(mx, nd[i].length())
	return mx


# ---------------------------------------------------------------- orientation: axial angles in the frontal plane
func axial_mean(angles: Array, wts: Array) -> float:
	var sx := 0.0
	var sy := 0.0
	for i in angles.size():
		sx += float(wts[i]) * cos(2.0 * float(angles[i]))
		sy += float(wts[i]) * sin(2.0 * float(angles[i]))
	return 0.5 * atan2(sy, sx)


func axial_diff(a: float, b: float) -> float:
	var x := fposmod(a - b + PI * 0.5, PI) - PI * 0.5
	return absf(x)


## {"mean": the weighted axial mean angle of the line directions inside mask, "w": total weight, "rad": weighted mean |angle to the radial from c|}
func orient(d: Dictionary, w: Dictionary, mask: Callable, turn: float = 0.0, centers: Array = []) -> Dictionary:
	var vs: PackedVector3Array = d["verts"]
	var amp: PackedFloat32Array = w["amp"]
	var dir: PackedVector3Array = w["dir"]
	var ang := []
	var wt := []
	var rad := 0.0
	for i in vs.size():
		if amp[i] < 0.05 or not mask.call(vs[i]):
			continue
		var a := atan2(dir[i].y, dir[i].x) + turn
		ang.append(a)
		wt.append(float(amp[i]))
		if not centers.is_empty():
			var best := 1.0e9
			var rr := 0.0
			for c in centers:
				var dd := Vector2(vs[i].x, vs[i].y).distance_to(c)
				if dd < best:
					best = dd
					rr = atan2(vs[i].y - (c as Vector2).y, vs[i].x - (c as Vector2).x)
			rad += float(amp[i]) * axial_diff(a, rr)
	var tw := 0.0
	for x in wt:
		tw += float(x)
	return {"mean": axial_mean(ang, wt) if not ang.is_empty() else 0.0, "w": tw, "rad": rad / tw if tw > 0.0 else 9.0}


func deg(r: float) -> float:
	return rad_to_deg(r)


func _init() -> void:
	if WR == null:
		ok(false, "scripts/face_wrinkle.gd exists")
		print("wrinkle: %d fail" % fails)
		quit(fails)
		return
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	m._commands()
	var head_pts: PackedVector3Array = skinned_head(m)
	var d := FaceGeo.build(head_pts)
	var an: Dictionary = d["anchors"]
	var s := float(an["top"]) / 1.754
	print("scale s = %.4f, mask %d vertices; native present: %s" % [s, (d["verts"] as PackedVector3Array).size(), str(WR.call("native_available"))])
	var masks := make_masks(d)
	var hx := float((an["eye_l"] as Vector3).x)
	var ey := float((an["eye_l"] as Vector3).y)
	var by := float((an["brow_l"] as Vector3).y)
	var my := float((an["mouth"] as Vector3).y)

	var A12 := {"AU1": 1.0, "AU2": 1.0}
	var w0: Dictionary = WR.call("compute", d, stt())
	var w12: Dictionary = WR.call("compute", d, stt(A12))

	# ---- W1
	var n0 := max_delta(d, w0, Callable())
	ok(n0 < 1.0e-3, "W1 neutral: max wrinkle normal delta %.6f (< 1e-3)" % n0)
	var f12 := max_delta(d, w12, masks["AU1"])
	ok(f12 >= 0.15, "W1 CONTROL AU1+AU2 = 1: forehead max normal delta %.3f (>= 0.15)" % f12)

	# ---- W2
	var cases := {"AU1": A12, "AU4": {"AU4": 1.0}, "AU6": {"AU6": 1.0}, "AU12": {"AU12": 1.0}, "AU9": {"AU9": 1.0}}
	var wc := {}
	for k in cases:
		wc[k] = WR.call("compute", d, stt(cases[k]))
		var e := energy_in(d, wc[k], masks[k])
		var lit := max_delta(d, wc[k], masks[k])
		ok(float(e["frac"]) >= 0.80 and lit >= 0.15, "W2 %s: %.1f %% of the wrinkle energy inside its region (>= 80), max normal delta there %.3f (>= 0.15)" % [k, float(e["frac"]) * 100.0, lit])
	var other := {"AU1": "AU12", "AU4": "AU1", "AU6": "AU9", "AU12": "AU6", "AU9": "AU4"}
	for k in cases:
		var ec := energy_in(d, wc[k], masks[other[k]])
		ok(float(ec["frac"]) < 0.80, "W2 CONTROL %s energy against the %s mask: %.1f %% (< 80)" % [k, other[k], float(ec["frac"]) * 100.0])

	# ---- W3
	# the brow line: principal axis of the brow vertices (rest)
	var rg: PackedInt32Array = d["region"]
	var vs0: PackedVector3Array = d["verts"]
	var bx: Array = []
	var bw: Array = []
	for i in vs0.size():
		if rg[i] == int(FaceGeo.REGION["brow_l"]) or rg[i] == int(FaceGeo.REGION["brow_r"]):
			bx.append(vs0[i])
	var cxm := 0.0
	var cym := 0.0
	for p in bx:
		cxm += (p as Vector3).x
		cym += (p as Vector3).y
	cxm /= bx.size()
	cym /= bx.size()
	var sxx := 0.0
	var sxy := 0.0
	var syy := 0.0
	for p in bx:
		var dx: float = (p as Vector3).x - cxm
		var dy: float = (p as Vector3).y - cym
		sxx += dx * dx
		sxy += dx * dy
		syy += dy * dy
	var brow_ang := 0.5 * atan2(2.0 * sxy, sxx - syy)
	print("brow line: %d vertices, principal axis %.1f deg from horizontal" % [bx.size(), deg(brow_ang)])
	var of := orient(d, w12, masks["AU1"])
	ok(deg(axial_diff(float(of["mean"]), brow_ang)) <= 15.0, "W3 forehead lines %.1f deg off the brow line (<= 15)" % deg(axial_diff(float(of["mean"]), brow_ang)))
	var ofc := orient(d, w12, masks["AU1"], PI * 0.5)
	ok(deg(axial_diff(float(ofc["mean"]), brow_ang)) > 15.0, "W3 CONTROL forehead directions turned 90 deg: %.1f deg off (> 15), caught" % deg(axial_diff(float(ofc["mean"]), brow_ang)))
	var og := orient(d, wc["AU4"], masks["AU4"])
	ok(deg(axial_diff(float(og["mean"]), PI * 0.5)) <= 15.0, "W3 glabella furrows %.1f deg off vertical (<= 15)" % deg(axial_diff(float(og["mean"]), PI * 0.5)))
	var ogc := orient(d, wc["AU4"], masks["AU4"], PI * 0.5)
	ok(deg(axial_diff(float(ogc["mean"]), PI * 0.5)) > 15.0, "W3 CONTROL glabella turned 90 deg: %.1f deg off (> 15), caught" % deg(axial_diff(float(ogc["mean"]), PI * 0.5)))
	var cans := [Vector2(hx + 0.015 * s, ey), Vector2(-(hx + 0.015 * s), ey)]
	var oc := orient(d, wc["AU6"], masks["AU6"], 0.0, cans)
	ok(deg(float(oc["rad"])) <= 20.0, "W3 crow's feet: mean angle to the radial from the lateral canthus %.1f deg (<= 20)" % deg(float(oc["rad"])))
	var occ := orient(d, wc["AU6"], masks["AU6"], PI * 0.5, cans)
	ok(deg(float(occ["rad"])) > 20.0, "W3 CONTROL crow's feet turned 90 deg: %.1f deg (> 20), caught" % deg(float(occ["rad"])))
	# nasolabial: the line wing -> corner, mirrored to the left side (x > 0); the right side is its mirror, so fold both onto one axis
	var wing := Vector2(0.019 * s, my + 0.022 * s)
	var corner := Vector2(0.031 * s, my - 0.004 * s)
	var nl_ang := atan2(corner.y - wing.y, corner.x - wing.x)
	var left_only := func(p: Vector3) -> bool: return p.x > 0.0 and masks["AU12"].call(p)
	var on := orient(d, wc["AU12"], left_only)
	ok(deg(axial_diff(float(on["mean"]), nl_ang)) <= 15.0, "W3 nasolabial (left) %.1f deg off the wing-corner line (%.1f deg) (<= 15)" % [deg(axial_diff(float(on["mean"]), nl_ang)), deg(nl_ang)])
	var onc := orient(d, wc["AU12"], left_only, PI * 0.5)
	ok(deg(axial_diff(float(onc["mean"]), nl_ang)) > 15.0, "W3 CONTROL nasolabial turned 90 deg: %.1f deg off (> 15), caught" % deg(axial_diff(float(onc["mean"]), nl_ang)))

	# ---- W5
	var stA := stt({"AU1": 0.75, "AU2": 0.5, "AU6": 0.5, "AU12": 1.0})
	var hA: int = WR.call("state_hash", WR.call("compute", d, stA))
	var h0: int = WR.call("state_hash", w0)
	var stJ: Dictionary = JSON.parse_string(JSON.stringify(stA))
	var hJ: int = WR.call("state_hash", WR.call("compute", d, stJ))
	ok(hJ == hA and hA != h0, "W5 save/reload: hash after a JSON round trip equals (%d vs %d), and differs from neutral (%d)" % [hJ, hA, h0])
	var stack := [stt().duplicate(true)]
	stack.append(stA.duplicate(true))
	var stB := stA.duplicate(true)
	stB["au"]["AU4"] = 0.5
	stack.append(stB)
	var hB: int = WR.call("state_hash", WR.call("compute", d, stB))
	stack.pop_back()
	var hU1: int = WR.call("state_hash", WR.call("compute", d, stack.back()))
	stack.pop_back()
	var hU2: int = WR.call("state_hash", WR.call("compute", d, stack.back()))
	ok(hU1 == hA and hU2 == h0 and hB != hA, "W5 undo: back one step %s the state before, back two %s neutral (B differs: %s)" % ["==" if hU1 == hA else "!=", "==" if hU2 == h0 else "!=", str(hB != hA)])
	var hBad: int = WR.call("state_hash", WR.call("compute", d, stt({"AU1": 0.75, "AU2": 0.5, "AU6": 0.5, "AU12": 0.99})))
	ok(hBad != hA, "W5 CONTROL a 0.01 change in one weight changes the hash")

	# ---- W6
	var stE := stt({"AU1": 0.7, "AU4": 0.4, "AU6": 0.6, "AU12": 0.9, "AU9": 0.5})
	var wn: Dictionary = WR.call("compute", d, stE, false)
	var wg: Dictionary = WR.call("compute", d, stE, true)
	var dc := 0.0
	var dd2 := 0.0
	for i in (d["verts"] as PackedVector3Array).size():
		dc = maxf(dc, absf(float((wn["comp"] as PackedFloat32Array)[i]) - float((wg["comp"] as PackedFloat32Array)[i])))
		if float((wg["comp"] as PackedFloat32Array)[i]) > 0.01:
			dd2 = maxf(dd2, ((wn["dir"] as PackedVector3Array)[i] - (wg["dir"] as PackedVector3Array)[i]).length())
	ok(bool(WR.call("native_available")) and bool(wn["native"]) and not bool(wg["native"]), "W6 native present and used (native %s, gd %s)" % [str(wn["native"]), str(wg["native"])])
	ok(dc <= 1.0e-5 and dd2 <= 1.0e-4, "W6 native == GDScript twin: strain max diff %.2e (<= 1e-5), direction max diff %.2e (<= 1e-4)" % [dc, dd2])

	# ---- W4 (CPU)
	var cpu := []
	for rep in 5:
		var t0 := Time.get_ticks_usec()
		for k in 20:
			WR.call("compute", d, stt({"AU1": 0.3 + 0.03 * k + 0.01 * rep, "AU4": 0.2, "AU6": 0.5, "AU12": 0.4, "AU9": 0.2}))
		cpu.append(float(Time.get_ticks_usec() - t0) / 1000.0 / 20.0)
	cpu.sort()
	var cpu_ms: float = cpu[2]
	var gpu_ms := 0.0
	var gp := await gpu_cost(d, head_pts)
	gpu_ms = float(gp["delta"])
	ok(cpu_ms + gpu_ms <= 0.5 and float(gp["plain"]) > 0.0, "W4 added cost at 1080p: CPU %.3f ms + GPU %.3f ms (wrinkle %.3f vs plain %.3f ms, clipped at 0) = %.3f (<= 0.5)" % [cpu_ms, gpu_ms, float(gp["wr"]), float(gp["plain"]), cpu_ms + gpu_ms])

	# ---- W7 the app
	m._face_geo_set(true)
	await idle(3)
	var mk := {}
	for nm in ["neutral", "AU1"]:
		m.face_geo_au = {} if nm == "neutral" else {"AU1": 1.0, "AU2": 1.0}
		m.face_geo_key = ""
		m._refresh()
		await idle(3)
		var mesh := m.face_geo_mask.mesh as ArrayMesh
		var ar := mesh.surface_get_arrays(0)
		var c0: PackedFloat32Array = ar[Mesh.ARRAY_CUSTOM0] if ar[Mesh.ARRAY_CUSTOM0] != null else PackedFloat32Array()
		var mx := 0.0
		for i in range(3, c0.size(), 4):
			mx = maxf(mx, c0[i])
		mk[nm] = mx
		mk[nm + "_sm"] = m.face_geo_mask.material_override is ShaderMaterial
	ok(bool(mk["AU1_sm"]) and float(mk["AU1"]) >= 0.3 and float(mk["neutral"]) < 1.0e-3, "W7 the app's mask: ShaderMaterial %s, CUSTOM0 amplitude max %.3f at AU1+2 (>= 0.3), %.5f at neutral (< 1e-3)" % [str(mk["AU1_sm"]), float(mk["AU1"]), float(mk["neutral"])])
	m.face_geo_au = {}
	m._face_geo_set(false)

	# ---- W8 render
	var rr := await render_bars(d, head_pts)
	ok(float(rr["ratio"]) >= 2.0, "W8 forehead high-frequency energy AU1+2 / neutral = %.2f (>= 2.0)" % float(rr["ratio"]))
	ok(float(rr["control"]) <= 1.2, "W8 CONTROL wrinkles off at AU1+2: ratio %.2f (<= 1.2)" % float(rr["control"]))

	print("WRINKLE TEST %s" % ["PASS" if fails == 0 else "FAIL %d" % fails])
	print("wrinkle: %d fail" % fails)
	quit(fails)


# ---------------------------------------------------------------- studio
func make_studio(d: Dictionary, head_pts: PackedVector3Array, size: Vector2i, fov: float, wr_on: bool) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = size
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.30, 0.31, 0.35)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.57, 0.62)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 25, 0)    # from above and the side: the ridges throw light and shadow
	sun.light_energy = 1.3
	vp.add_child(sun)
	var cam := Camera3D.new()
	var an: Dictionary = d["anchors"]
	var fc := Vector3(0, float(an["chin"]) + 0.62 * float(an["H"]), 0.12)
	cam.fov = fov
	cam.position = fc + Vector3(0, 0, 0.52)
	vp.add_child(cam)
	cam.look_at(fc, Vector3.UP)
	cam.current = true
	var sm := SurfaceTool.new()
	sm.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in head_pts:
		sm.add_vertex(v)
	sm.generate_normals()
	var head_mi := MeshInstance3D.new()
	head_mi.mesh = FaceGeo.cut_head(sm.commit(), d)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.80, 0.82, 0.88)
	hmat.roughness = 0.85
	head_mi.material_override = hmat
	vp.add_child(head_mi)
	var mask_mi := MeshInstance3D.new()
	if wr_on:
		mask_mi.material_override = WR.call("material", null)
	else:
		var mmat := StandardMaterial3D.new()
		mmat.vertex_color_use_as_albedo = true
		mmat.roughness = 0.8
		mask_mi.material_override = mmat
	vp.add_child(mask_mi)
	return {"vp": vp, "mask": mask_mi, "cam": cam}


func set_state(st: Dictionary, d: Dictionary, state: Dictionary, wr_on: bool, amp_scale: float = 1.0) -> void:
	var w: Dictionary = WR.call("compute", d, state)
	if amp_scale != 1.0:
		var a: PackedFloat32Array = w["amp"]
		for i in a.size():
			a[i] *= amp_scale
		w["amp"] = a
	var vsp: PackedVector3Array = w["verts"]
	(st["mask"] as MeshInstance3D).mesh = WR.call("mask_mesh", d, vsp, w)


func gpu_cost(d: Dictionary, head_pts: PackedVector3Array) -> Dictionary:
	var out := {"wr": 0.0, "plain": 0.0, "delta": 0.0}
	for pass_i in 2:
		var on := pass_i == 0
		var st := make_studio(d, head_pts, Vector2i(1920, 1080), 21.0, on)
		var vrid := (st["vp"] as SubViewport).get_viewport_rid()
		RenderingServer.viewport_set_measure_render_time(vrid, true)
		set_state(st, d, {"au": {"AU1": 1.0, "AU2": 1.0, "AU6": 0.6, "AU12": 0.8}, "jaw_deg": 0.0}, on)
		await idle(6)
		var meds := []
		for rep in 5:
			var acc := 0.0
			for k in 20:
				await RenderingServer.frame_post_draw
				acc += RenderingServer.viewport_get_measured_render_time_gpu(vrid)
			meds.append(acc / 20.0)
		meds.sort()
		out["wr" if on else "plain"] = float(meds[2])
		(st["vp"] as SubViewport).queue_free()
		await idle(2)
	out["delta"] = maxf(0.0, float(out["wr"]) - float(out["plain"]))
	return out


func lap_energy(img: Image, r: Rect2i) -> float:
	var acc := 0.0
	var n := 0
	for y in range(r.position.y + 1, r.end.y - 1):
		for x in range(r.position.x + 1, r.end.x - 1):
			var c := img.get_pixel(x, y).get_luminance()
			var b := (img.get_pixel(x - 1, y).get_luminance() + img.get_pixel(x + 1, y).get_luminance() + img.get_pixel(x, y - 1).get_luminance() + img.get_pixel(x, y + 1).get_luminance()) * 0.25
			acc += absf(c - b)
			n += 1
	return acc / maxf(n, 1)


func render_bars(d: Dictionary, head_pts: PackedVector3Array) -> Dictionary:
	var an: Dictionary = d["anchors"]
	var s := float(an["top"]) / 1.754
	var by := float((an["brow_l"] as Vector3).y)
	var st := make_studio(d, head_pts, Vector2i(330, 330), 15.0, true)
	var cam: Camera3D = st["cam"]
	var shots := {}
	var plan := [["neutral", {}, 1.0], ["AU12", {"AU1": 1.0, "AU2": 1.0}, 1.0], ["AU612", {"AU6": 1.0, "AU12": 1.0}, 1.0], ["off", {"AU1": 1.0, "AU2": 1.0}, 0.0]]
	for pl in plan:
		set_state(st, d, {"au": pl[1], "jaw_deg": 0.0}, true, float(pl[2]))
		await idle(3)
		await RenderingServer.frame_post_draw
		shots[pl[0]] = (st["vp"] as SubViewport).get_texture().get_image()
	var z := 0.12 + 0.0
	var p0 := cam.unproject_position(Vector3(-0.040 * s, by + 0.026 * s, 0.10))
	var p1 := cam.unproject_position(Vector3(0.040 * s, by + 0.006 * s, 0.10))
	var r := Rect2i(int(minf(p0.x, p1.x)), int(minf(p0.y, p1.y)), int(absf(p1.x - p0.x)), int(absf(p1.y - p0.y)))
	var en := lap_energy(shots["neutral"], r)
	var ew := lap_energy(shots["AU12"], r)
	var eo := lap_energy(shots["off"], r)
	print("forehead crop %s: laplacian energy neutral %.5f, AU1+2 %.5f, wrinkles off %.5f" % [str(r), en, ew, eo])
	var path := OS.get_environment("FACE_WRINKLE_SHOT")
	if path != "":
		var sheet := Image.create(990, 330, false, Image.FORMAT_RGBA8)
		var i := 0
		for k in ["neutral", "AU12", "AU612"]:
			sheet.blit_rect(shots[k], Rect2i(0, 0, 330, 330), Vector2i(330 * i, 0))
			i += 1
		sheet.save_png(path)
		print("sheet -> ", path)
	(st["vp"] as SubViewport).queue_free()
	return {"ratio": ew / maxf(en, 1.0e-9), "control": eo / maxf(en, 1.0e-9)}
