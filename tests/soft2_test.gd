extends SceneTree
## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/soft2_test.gd     (L32 SOFT-2: the flesh of #236 / #239, faster, bounded, shaded)
## SOFT2_SHOT=<dir> also renders the before / after close-ups of the landing (strength 1).
##
## THE WORK. #239 shipped with three known limits; this suite is their bars, written BEFORE the implementation (this file's first commit
## has no C++ skin deform, no normal recompute, no arm tuning). Each bar has a PLANTED CONTROL that the detector must catch.
##
##   A ARM WINDOW    The arm region peaked at 84 mm in the landing arm swing. L17's thigh window (2 .. 40 mm) does not carry over to the
##                   arm. SOURCE (found 11-06, registered before re-measuring): Blache Y, Dumas R, Lundberg A, Begon M (2017) "Main
##                   component of soft tissue artifact of the upper-limbs with respect to different functional, daily life and sports
##                   movements", J Biomech 62:30-38 (intracortical pins in clavicle, scapula and humerus of four subjects, up to seven
##                   skin markers per segment, flexion / rotation / daily-life / sports tasks). I could not open the full text (the
##                   publisher and the HAL copy were blocked); the figure used is a SECOND-HAND citation of it: "the displacement of
##                   markers positioned on the arm ranged on average between 3.9 mm and 25.6 mm". Those are per-marker AVERAGES, so a
##                   PEAK of a node is allowed up to 30 mm (the top of the average range plus ~17 %), and at least 4 mm (the bottom).
##                   Pain MTG, Challis JH (2006) J Biomech 39(1):119-24 supplies the mechanism (soft tissue on the bone takes the first
##                   100 ms of a landing) but no arm amplitude I could read. The window is therefore: 4 .. 30 mm, HONESTLY a wobbling-mass
##                   / marker-artefact bracket for the upper arm, not a measured landing amplitude of arm flesh.
##                   A1  arm_l and arm_r: peak node travel over the landing clip (60 Hz bake, shipped REGIONS) in 4 .. 30 mm.
##                   A2  CONTROL: E x 0.04 (a floppy arm) leaves the window above; E x 1000 (bone-stiff) leaves it below (the window is not vacuous).
##   P PERF          The hot loop (skin deform of the near-region vertices, the offsets, the mesh swap) is C++. 6 regions, the landing
##                   clip played 240 frames: the mean of what SoftLive.tick spends is <= 2.0 ms and its p95 <= 3.0 ms (was ~8 ms on combo3).
##                   P1  native path under both bars.  P2 CONTROL: SoftLive.force_gd (the #239 GDScript path) is over the mean bar.
##   E EQUALITY      E1 the drawn vertices equal SoftBody.skin_deform fed the bake's frame (1e-6 m), at 4 frames, the C++ path.
##                   E2 CONTROL: the frame 3 steps off differs by > 1e-5.  E3 the C++ path equals the GDScript path (1e-6 m).
##                   E4 CONTROL: one vertex nudged 1e-6 m is seen by the comparison.
##   N NORMALS       N1 the normals of the drawn deformed region are recomputed: at least 20 vertices turn by more than 1 degree
##                   from the undeformed mesh's normal, all drawn normals are finite and unit (1e-3), and no vertex that shares no
##                   triangle with a displaced vertex has a changed normal (a 3 cm distance proxy first written here was wrong: the
##                   mannequin's triangles are longer than 3 cm, so a one-ring neighbour can be further than that).
##                   N2 CONTROL: SoftLive.normals_on = false (the #239 look) turns 0 vertices.
##                   N3 the C++ normals equal an independent GDScript reference (area weighted rest / deformed normals, the original
##                   normal turned by the shortest arc between them) within 0.2 degrees on every moved vertex.
##                   N4 CONTROL: the reference with one normal flipped is seen (> 0.2 degrees).
##   R RENDER        The shading on the deformed region changes with the deformation. 512 x 512 close-up of the landing, soft ON
##                   against soft OFF (strength 0 restores the plain mesh). Cells of 12 px inside the body in BOTH images and in the
##                   8 neighbours (the silhouette moves with the flesh, so edge cells are not shading), that contain a projected skin
##                   vertex: x = mean vertex displacement (world mm), y = mean |luminance difference| of the cell's pixels.
##                   FINDING while measuring: soft ON against soft OFF correlates with the displacement (r 0.6 - 0.7) even with the OLD
##                   normals, because the app's SSAO / shadows / outline respond to displaced geometry; that pair cannot tell the build
##                   from the current one. The bar therefore uses y = |L(normals recomputed) - L(same deformation, #239 normals)|.
##                   SECOND FINDING: x = mean vertex displacement gave r = 0.32 against y: a patch that shifts rigidly turns no normal, so the
##                   shading follows the normal TURN (the displacement gradient), not the displacement. The first threshold (0.4 on the
##                   displacement) was not met and is printed as information; the bar below uses x = the vertex normal's turn in degrees.
##                   R1 Pearson r(x, y) >= 0.4 over >= 30 cells, and the cells with x > 1 (deg) have a mean y of at least 0.004.
##                   R2 CONTROL: the #239 build rendered twice (normals_on = false both) fails the same bar.
##                   R3 CONTROL: x shuffled across the cells reads |r| < 0.2.
##   U USD           Not built (documented in docs/EXPORT.md); no bar.
var fails := 0
var m: Node
const TMP := "user://soft2_scene.json"
const ARM_LO := 0.004
const ARM_HI := 0.030


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func pose(thigh: float, calf: float, arm: float) -> Dictionary:
	var B := body()
	for sd in ["_l", "_r"]:
		B.set_ang("thigh" + sd, Vector3(thigh, 0, 0))
		B.set_ang("calf" + sd, Vector3(calf, 0, 0))
		B.set_ang("upperarm" + sd, Vector3(arm, 0, 0))
	B.fk()
	return B.to_dict()


## the L17 landing: dip, flight (arms swung up 100 degrees), a stiff landing
func landing_scene() -> Scene:
	var B := body()
	var S := Scene.new()
	S.name = "zz_soft2_land"
	S.add("stand", B.to_dict())
	S.add("dip", pose(50, 90, 0))
	S.add("air", pose(10, 20, 100))
	S.add("land", pose(50, 90, 0))
	S.add("stand", B.to_dict())
	var mvs := [0.3, 0.3, 0.2855, 0.08, 0.4]
	var hd := [0.1, 0.05, 0.0, 0.1, 0.2]
	for i in 5:
		S.cards[i]["move"] = mvs[i]
		S.cards[i]["hold"] = hd[i]
	S.cards[2]["air"] = true
	return S


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func boot_app() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.dummy_on = false


func load_landing(S: Scene) -> void:
	var fa := FileAccess.open(TMP, FileAccess.WRITE)
	fa.store_string(JSON.stringify(S.to_dict(m.B)))
	fa.close()
	m._load_scene(TMP)
	m._rebuild_cards()
	m.playing = false
	await idle(2)


func ctl(nm: String) -> Node:
	return m.ui_body.find_child(nm, true, false)


func wait_ready(limit_s := 90.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not m.soft_live.ready() and float(Time.get_ticks_msec() - t0) < limit_s * 1000.0:
		await process_frame
	return m.soft_live.ready()


func piece_verts(mesh: Mesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	for si in mesh.get_surface_count():
		out.append_array(mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX])
	return out


func piece_normals(mesh: Mesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	for si in mesh.get_surface_count():
		out.append_array(mesh.surface_get_arrays(si)[Mesh.ARRAY_NORMAL])
	return out


func used_mask(mesh: Mesh) -> PackedByteArray:
	var out := PackedByteArray()
	for si in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(si)
		var n := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var u := PackedByteArray()
		u.resize(n)
		var idx = arr[Mesh.ARRAY_INDEX]
		if idx is PackedInt32Array:
			for q in (idx as PackedInt32Array):
				u[q] = 1
		else:
			u.fill(1)
		out.append_array(u)
	return out


func max_diff(a: PackedVector3Array, b: PackedVector3Array, mask := PackedByteArray()) -> float:
	if a.size() != b.size():
		return INF
	var mx := 0.0
	for i in a.size():
		if mask.size() == a.size() and mask[i] == 0:
			continue
		mx = maxf(mx, (a[i] - b[i]).length())
	return mx


func expected_verts(piece: MeshInstance3D, regs: Array, disps: Array) -> PackedVector3Array:
	var orig: Mesh = m.soft_live.orig_mesh(piece)
	var tmp := MeshInstance3D.new()
	tmp.mesh = orig
	tmp.skin = piece.skin
	piece.get_parent().add_child(tmp)
	tmp.transform = piece.transform
	tmp.skeleton = piece.skeleton
	var dm := SoftBody.skin_deform(tmp, regs, m.B, disps)
	var out := piece_verts(dm if dm != null else orig)
	piece.get_parent().remove_child(tmp)
	tmp.free()
	return out


func at(t: float) -> void:
	m.playhead = t
	m._ps().apply(m.B, t)
	m._refresh()


static func pct(a: Array, p: float) -> float:
	var b := a.duplicate()
	b.sort()
	return float(b[clampi(int(ceil(p / 100.0 * b.size())) - 1, 0, b.size() - 1)])


func _init() -> void:
	var t_all := Time.get_ticks_msec()
	ok(SoftBody.native_on(), "0 the native door is open")

	# ---------- A ARM WINDOW (no app needed)
	var SL := landing_scene()
	var arm_peak := func(name: String, ov: Dictionary) -> float:
		var bk := SoftBody.bake_scene(SL, body(), [name], 60.0, ov)
		var pk := 0.0
		for d in (bk["regions"][name]["disp"] as Array):
			for v in (d as PackedVector3Array):
				pk = maxf(pk, v.length())
		return pk
	var pl: float = arm_peak.call("arm_l", {})
	var pr: float = arm_peak.call("arm_r", {})
	var E0: float = SoftBody.REGIONS["arm_l"]["E"]
	var p_soft: float = arm_peak.call("arm_l", {"E": E0 * 0.04})
	var p_over: float = arm_peak.call("arm_l", {"E": E0 * 1000.0})
	print("A ARM: peak node travel over the landing clip (60 Hz): arm_l %.2f mm, arm_r %.2f mm; window %.0f .. %.0f mm | control E x 0.04: %.2f mm, bone-stiff E x 1000: %.2f mm" % [
		pl * 1000.0, pr * 1000.0, ARM_LO * 1000.0, ARM_HI * 1000.0, p_soft * 1000.0, p_over * 1000.0])
	ok(pl >= ARM_LO and pl <= ARM_HI, "A1 arm_l peak %.2f mm is in the registered 4 .. 30 mm window" % (pl * 1000.0))
	ok(pr >= ARM_LO and pr <= ARM_HI, "A1 arm_r peak %.2f mm is in the registered 4 .. 30 mm window" % (pr * 1000.0))
	ok(p_soft > ARM_HI, "A2 CONTROL: a floppy arm (E x 0.04) reads %.2f mm, above the window: the window rejects it" % (p_soft * 1000.0))
	ok(p_over < ARM_LO, "A2 CONTROL: a bone-stiff arm (E x 1000) reads %.2f mm, below the window: the window rejects it" % (p_over * 1000.0))

	# ---------- the app
	await boot_app()
	var fl := SL.flights()
	var t_imp: float = float(fl[0]["t1"]) if fl.size() == 1 else 1.0
	var k_imp := int(round(t_imp * 60.0))
	await load_landing(SL)
	var names_ui := ["soft_belly", "soft_chest", "soft_thighs", "soft_arms"]
	for nm in names_ui:
		(ctl(nm) as BaseButton).button_pressed = true
	await idle(2)
	ok(await wait_ready(), "the bake for all six regions finished")
	var regs: Array = m.soft_live.regs
	var bake: Dictionary = m.soft_live.bake
	var names: Array = m.soft_live.names.duplicate()

	# ---------- E EQUALITY (C++ path vs skin_deform vs the GDScript path)
	m.soft_live.force_gd = false
	var worst := 0.0
	var worst_ctl := 0.0
	var worst_gd := 0.0
	var nudge_seen := 0.0
	var nf: int = int(bake["frames"])
	for off in [-2, 0, 3, 8]:
		var k: int = k_imp + off
		at(float(k) / 60.0)
		var disps := []
		var wrong := []
		for n in names:
			disps.append((bake["regions"][n]["disp"] as Array)[k])
			wrong.append((bake["regions"][n]["disp"] as Array)[clampi(k + 3, 0, nf - 1)])
		var live := {}
		for j in m.pieces:
			live[j] = piece_verts((m.pieces[j] as MeshInstance3D).mesh)
		for j in m.pieces:
			var piece: MeshInstance3D = m.pieces[j]
			var mask := used_mask(piece.mesh)
			var want := expected_verts(piece, regs, disps)
			worst = maxf(worst, max_diff(live[j], want, mask))
			var wr := expected_verts(piece, regs, wrong)
			if max_diff(want, wr, mask) > 1e-5:
				worst_ctl = maxf(worst_ctl, max_diff(live[j], wr, mask))
			if nudge_seen == 0.0 and want.size() > 10:
				var nd := want.duplicate()
				nd[3] += Vector3(1e-6, 0, 0)
				nudge_seen = max_diff(nd, want)
		m.soft_live.force_gd = true
		at(float(k) / 60.0)
		for j in m.pieces:
			var piece2: MeshInstance3D = m.pieces[j]
			worst_gd = maxf(worst_gd, max_diff(live[j], piece_verts(piece2.mesh), used_mask(piece2.mesh)))
		m.soft_live.force_gd = false
	print("E EQUALITY: drawn (C++) vs skin_deform worst %s m; vs the GDScript path %s m; wrong-frame control %s m" % [worst, worst_gd, worst_ctl])
	ok(worst < 1e-6, "E1 the C++ path draws skin_deform's vertices: worst %s m (bar 1e-6)" % worst)
	ok(worst_ctl > 1e-5, "E2 CONTROL: the frame 3 steps off differs by %s m (> 1e-5)" % worst_ctl)
	ok(worst_gd < 1e-6, "E3 the C++ path equals the GDScript path: worst %s m (bar 1e-6)" % worst_gd)
	ok(nudge_seen > 5e-7, "E4 CONTROL: a vertex nudged 1e-6 m reads %s m in the comparison" % nudge_seen)

	# ---------- N NORMALS
	at(float(k_imp) / 60.0)
	var n_turn := 0
	var n_bad := 0
	var n_far := 0
	var n_max_deg := 0.0
	var ref_worst := 0.0
	var ref_n := 0
	var flip_seen := 0.0
	for j in m.pieces:
		var piece3: MeshInstance3D = m.pieces[j]
		var orig_m: Mesh = m.soft_live.orig_mesh(piece3)
		var dn := piece_normals(piece3.mesh)
		var on := piece_normals(orig_m)
		var dv := piece_verts(piece3.mesh)
		var ov := piece_verts(orig_m)
		var mask3 := used_mask(piece3.mesh)
		var near := PackedByteArray()   # 1 = shares a triangle with a displaced vertex
		near.resize(dv.size())
		var ixa := PackedInt32Array()
		var base_v := 0
		for si3 in orig_m.get_surface_count():
			var a3 := orig_m.surface_get_arrays(si3)
			var ii = a3[Mesh.ARRAY_INDEX]
			if ii is PackedInt32Array:
				var t3 := 0
				var ia: PackedInt32Array = ii
				while t3 + 2 < ia.size():
					var tri := [base_v + ia[t3], base_v + ia[t3 + 1], base_v + ia[t3 + 2]]
					if (dv[tri[0]] - ov[tri[0]]).length() > 1e-6 or (dv[tri[1]] - ov[tri[1]]).length() > 1e-6 or (dv[tri[2]] - ov[tri[2]]).length() > 1e-6:
						near[tri[0]] = 1
						near[tri[1]] = 1
						near[tri[2]] = 1
					t3 += 3
			base_v += (a3[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		for i in dn.size():
			if mask3[i] == 0:
				continue
			if not (is_finite(dn[i].x) and is_finite(dn[i].y) and is_finite(dn[i].z)) or absf(dn[i].length() - 1.0) > 1e-3:
				n_bad += 1
			var ang := rad_to_deg(on[i].angle_to(dn[i])) if on[i].length() > 0.5 and dn[i].length() > 0.5 else 0.0
			n_max_deg = maxf(n_max_deg, ang)
			if ang > 1.0:
				n_turn += 1
			if ang > 0.05 and near[i] == 0:
				n_far += 1
		# N3: the independent reference, only where the C++ turned a normal
		var rf := ref_normals(orig_m, piece3.mesh)
		for i in dn.size():
			if mask3[i] == 1 and rf.size() == dn.size() and rf[i].length() > 0.5:
				var a := rad_to_deg(rf[i].angle_to(dn[i]))
				ref_worst = maxf(ref_worst, a)
				ref_n += 1
				if ref_n == 7:
					flip_seen = rad_to_deg((-rf[i]).angle_to(dn[i]))
	print("N NORMALS: %d vertices turned > 1 degree (max %.2f deg), %d not unit / not finite, %d changed with no displaced triangle neighbour; reference worst %.3f deg over %d vertices" % [n_turn, n_max_deg, n_bad, n_far, ref_worst, ref_n])
	ok(n_turn >= 20, "N1 at least 20 drawn vertices turned by more than 1 degree (%d)" % n_turn)
	ok(n_bad == 0, "N1 every drawn normal is finite and unit (%d bad)" % n_bad)
	ok(n_far == 0, "N1 no normal changed on a vertex that shares no triangle with a displaced vertex (%d)" % n_far)
	ok(ref_n > 100 and ref_worst < 0.2, "N3 the C++ normals equal the GDScript reference: worst %.3f deg over %d vertices (bar 0.2)" % [ref_worst, ref_n])
	ok(flip_seen > 0.2, "N4 CONTROL: the reference with one normal flipped reads %.1f deg (> 0.2)" % flip_seen)
	m.soft_live.normals_on = false
	at(float(k_imp) / 60.0)
	var n_turn_off := 0
	for j in m.pieces:
		var p4: MeshInstance3D = m.pieces[j]
		var dn4 := piece_normals(p4.mesh)
		var on4 := piece_normals(m.soft_live.orig_mesh(p4))
		var mk4 := used_mask(p4.mesh)
		for i in dn4.size():
			if mk4[i] == 1 and dn4[i].length() > 0.5 and on4[i].length() > 0.5 and rad_to_deg(on4[i].angle_to(dn4[i])) > 1.0:
				n_turn_off += 1
	ok(n_turn_off == 0, "N2 CONTROL: with normals_on = false (the #239 look) %d vertices turn: the detector sees the old build" % n_turn_off)
	m.soft_live.normals_on = true

	# ---------- P PERF
	m.soft_live.force_gd = false
	m.soft_live.prof = [0, 0, 0, 0, 0]
	var fr_native := await measure_ticks(240)
	var pf: Array = m.soft_live.prof.duplicate()
	print("P PROFILE per frame (us): entry %.0f, skin mats + C++ deform %.0f, mesh bytes %.0f; pieces drawn deformed %.1f" % [pf[0] / 240.0, pf[1] / 240.0, pf[2] / 240.0, pf[3] / 240.0])
	m.soft_live.force_gd = true
	var fr_gd := await measure_ticks(240)
	m.soft_live.force_gd = false
	var mean_n := mean_of(fr_native)
	var mean_g := mean_of(fr_gd)
	print("P PERF (tick ms, 240 played frames, 6 regions): C++ mean %.3f p50 %.3f p95 %.3f | GDScript (#239) mean %.3f p50 %.3f p95 %.3f" % [
		mean_n, pct(fr_native, 50), pct(fr_native, 95), mean_g, pct(fr_gd, 50), pct(fr_gd, 95)])
	ok(mean_n <= 2.0 and pct(fr_native, 95) <= 3.0, "P1 the C++ tick: mean %.3f ms (<= 2.0), p95 %.3f ms (<= 3.0)" % [mean_n, pct(fr_native, 95)])
	ok(mean_g > 2.0, "P2 CONTROL: the #239 GDScript path reads mean %.3f ms (> 2.0): the timer sees the work" % mean_g)

	# ---------- R RENDER
	await render_bars(k_imp)

	print("soft2: %d failures (%.1f s)" % [fails, float(Time.get_ticks_msec() - t_all) / 1000.0])
	var shot := OS.get_environment("SOFT2_SHOT")
	if shot != "":
		await shoot(shot, k_imp)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)


func mean_of(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += float(x)
	return s / maxf(float(a.size()), 1.0)


## what SoftLive.tick spent in each of n played frames (ms)
func measure_ticks(n: int) -> Array:
	var out := []
	m.playing = true
	m.playhead = 0.0
	await process_frame
	for i in n:
		var w0: int = m.soft_live.work_us
		await process_frame
		out.append(float(int(m.soft_live.work_us) - w0) / 1000.0)
	m.playing = false
	return out


## REFERENCE normals: area weighted vertex normals of the undeformed and of the deformed mesh over the index array; where they differ, the
## original normal is turned by the shortest arc between the two. [] when the mesh has no indices. Same layout as piece_normals().
func ref_normals(orig_m: Mesh, drawn: Mesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	for si in orig_m.get_surface_count():
		var ao := orig_m.surface_get_arrays(si)
		var ad := drawn.surface_get_arrays(si)
		var vo: PackedVector3Array = ao[Mesh.ARRAY_VERTEX]
		var vd: PackedVector3Array = ad[Mesh.ARRAY_VERTEX]
		var no: PackedVector3Array = ao[Mesh.ARRAY_NORMAL]
		var idx = ao[Mesh.ARRAY_INDEX]
		var sa := PackedVector3Array()
		var sb := PackedVector3Array()
		sa.resize(vo.size())
		sb.resize(vo.size())
		if not (idx is PackedInt32Array):
			out.append_array(no)
			continue
		var t := 0
		var ix: PackedInt32Array = idx
		while t + 2 < ix.size():
			var a := ix[t]
			var b := ix[t + 1]
			var c := ix[t + 2]
			var fo := (vo[b] - vo[a]).cross(vo[c] - vo[a])
			var fd := (vd[b] - vd[a]).cross(vd[c] - vd[a])
			sa[a] += fo
			sa[b] += fo
			sa[c] += fo
			sb[a] += fd
			sb[b] += fd
			sb[c] += fd
			t += 3
		for i in vo.size():
			var n0 := no[i]
			if sa[i].length() > 1e-12 and sb[i].length() > 1e-12 and (sb[i].normalized() - sa[i].normalized()).length() > 1e-9:
				var q := Quaternion(sa[i].normalized(), sb[i].normalized())
				n0 = (q * n0).normalized()
			out.append(n0)
	return out


# ------------------------------------------------------------ R: the render bar

func render_bars(k_imp: int) -> void:
	var size := 512
	var cell := 12
	var sv := SubViewport.new()
	sv.size = Vector2i(size, size)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.own_world_3d = false
	root.add_child(sv)
	var cam := Camera3D.new()
	sv.add_child(cam)
	cam.current = true
	cam.fov = 20.0
	cam.global_position = Vector3(1.9, 1.25, 2.3)
	cam.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
	var k := k_imp + 3
	m.soft_live.force_gd = false
	m.soft_live.normals_on = true
	# the background: the same view with the body pieces hidden
	at(float(k) / 60.0)
	for j in m.pieces:
		(m.pieces[j] as MeshInstance3D).visible = false
	var img_bg := await grab(sv)
	for j in m.pieces:
		(m.pieces[j] as MeshInstance3D).visible = true
	m.soft_strength_set(0.0)
	at(float(k) / 60.0)
	var img_off := await grab(sv)
	m.soft_strength_set(1.0)
	m.soft_live.normals_on = true
	at(float(k) / 60.0)
	var img_on := await grab(sv)
	# the vertex displacement, projected
	var pts := []   # [Vector2 px, float displacement m]
	for j in m.pieces:
		var piece: MeshInstance3D = m.pieces[j]
		var om: Mesh = m.soft_live.orig_mesh(piece)
		var w0: PackedVector3Array = m.soft_live.posed_world(piece, om)
		var w1: PackedVector3Array = m.soft_live.posed_world(piece, piece.mesh)
		var mk := used_mask(piece.mesh)
		var nrm_d := piece_normals(piece.mesh)
		var nrm_o := piece_normals(om)
		if w0.size() != w1.size():
			continue
		for i in w0.size():
			if mk[i] == 1 and not cam.is_position_behind(w0[i]):
				var turn := 0.0
				if i < nrm_d.size() and i < nrm_o.size() and nrm_d[i].length() > 0.5 and nrm_o[i].length() > 0.5:
					turn = rad_to_deg(nrm_d[i].angle_to(nrm_o[i]))
				pts.append([cam.unproject_position(w0[i]), (w1[i] - w0[i]).length(), turn])
	# What the bar can and cannot see. soft ON against soft OFF changes the picture through the GEOMETRY too (the app's SSAO, shadows and outline answer to
	# displaced vertices), so that comparison correlates with the displacement even when the normals are the old ones (printed below, informational).
	# The shading bar therefore compares ON (normals recomputed) against the same deformation with the #239 normals: positions identical, only normals differ.
	var res_geo := cell_stats(img_bg, img_off, img_on, pts, size, cell)
	m.soft_live.normals_on = false
	at(float(k) / 60.0)
	var img_old := await grab(sv)
	var res_geo_old := cell_stats(img_bg, img_off, img_old, pts, size, cell)
	at(float(k) / 60.0)
	var img_old2 := await grab(sv)
	m.soft_live.normals_on = true
	var res_disp := cell_stats(img_bg, img_old, img_on, pts, size, cell)
	var res_on := cell_stats(img_bg, img_old, img_on, pts, size, cell, 2, 1.0)
	var res_old := cell_stats(img_bg, img_old, img_old2, pts, size, cell, 2, 1.0)
	var xs: Array = (res_on["x"] as Array).duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(xs.size() - 1, 0, -1):
		var jj := rng.randi_range(0, i)
		var tmp = xs[i]
		xs[i] = xs[jj]
		xs[jj] = tmp
	var r_shuf := pearson(xs, res_on["y"])
	print("R RENDER: informational, soft ON vs OFF (geometry + shading): r = %.3f, mean dL %.4f (normals ON) | r = %.3f, mean dL %.4f (the #239 normals)" % [
		res_geo["r"], res_geo["ymean_disp"], res_geo_old["r"], res_geo_old["ymean_disp"]])
	print("R RENDER: shading change against the vertex DISPLACEMENT (mm): r = %.3f (a rigid shift of a patch turns no normal, so this r is not the bar)" % res_disp["r"])
	print("R RENDER: shading only (ON vs the same deformation with #239 normals) against the NORMAL TURN (deg): %d cells, r = %.3f, mean dL in turned cells %.4f | #239 vs #239 r = %.3f, %.4f | shuffled r = %.3f" % [
		(res_on["x"] as Array).size(), res_on["r"], res_on["ymean_disp"], res_old["r"], res_old["ymean_disp"], r_shuf])
	ok((res_on["x"] as Array).size() >= 30 and float(res_on["r"]) >= 0.4 and float(res_on["ymean_disp"]) >= 0.004,
		"R1 the recomputed normals change the shading where they turned: r = %.3f (>= 0.4) over %d cells, mean luminance change in displaced cells %.4f (>= 0.004)" % [res_on["r"], (res_on["x"] as Array).size(), res_on["ymean_disp"]])
	var old_fails: bool = float(res_old["r"]) < 0.4 or float(res_old["ymean_disp"]) < 0.004
	ok(old_fails, "R2 CONTROL: the #239 build (normals_on = false, rendered twice) fails the same bar: r = %.3f, mean change %.4f" % [res_old["r"], res_old["ymean_disp"]])
	ok(absf(r_shuf) < 0.2, "R3 CONTROL: the displacement shuffled across the cells reads r = %.3f (|r| < 0.2)" % r_shuf)
	sv.queue_free()


func grab(sv: SubViewport) -> Image:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = sv.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


static func lum(d: PackedByteArray, p: int) -> float:
	return (0.2126 * d[p] + 0.7152 * d[p + 1] + 0.0722 * d[p + 2]) / 255.0


func pearson(a: Array, b: Array) -> float:
	var n := a.size()
	if n < 3:
		return 0.0
	var ma := 0.0
	var mb := 0.0
	for i in n:
		ma += float(a[i])
		mb += float(b[i])
	ma /= n
	mb /= n
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in n:
		var da := float(a[i]) - ma
		var db := float(b[i]) - mb
		sab += da * db
		saa += da * da
		sbb += db * db
	return sab / maxf(sqrt(saa * sbb), 1e-12)


## per cell of `cell` px: foreground (differs from the empty background in BOTH images), has a projected vertex; x = mean displacement (mm),
## y = mean |luminance difference| between img_off and img_on over the cell. Cells whose 8 neighbours are not all foreground are dropped.
func cell_stats(bg: Image, off: Image, on: Image, pts: Array, size: int, cell: int, xi := 1, xscale := 1000.0) -> Dictionary:
	var db := bg.get_data()
	var d0 := off.get_data()
	var d1 := on.get_data()
	var nc := size / cell
	var fg := PackedByteArray()
	fg.resize(nc * nc)
	var ysum := PackedFloat64Array()
	ysum.resize(nc * nc)
	for cy in nc:
		for cx in nc:
			var all_fg := true
			var s := 0.0
			for py in range(cy * cell, (cy + 1) * cell):
				for px in range(cx * cell, (cx + 1) * cell):
					var p := (py * size + px) * 4
					if absf(lum(d0, p) - lum(db, p)) < 0.01 or absf(lum(d1, p) - lum(db, p)) < 0.01:
						all_fg = false
					s += absf(lum(d1, p) - lum(d0, p))
			fg[cy * nc + cx] = 1 if all_fg else 0
			ysum[cy * nc + cx] = s / float(cell * cell)
	var xsum := PackedFloat64Array()
	xsum.resize(nc * nc)
	var cnt := PackedInt32Array()
	cnt.resize(nc * nc)
	for pt in pts:
		var px2: Vector2 = pt[0]
		var cx2 := int(px2.x) / cell
		var cy2 := int(px2.y) / cell
		if cx2 >= 0 and cy2 >= 0 and cx2 < nc and cy2 < nc:
			xsum[cy2 * nc + cx2] += float(pt[xi]) * xscale
			cnt[cy2 * nc + cx2] += 1
	var xs := []
	var ys := []
	var yd := 0.0
	var nd := 0
	for cy in range(1, nc - 1):
		for cx in range(1, nc - 1):
			var ci := cy * nc + cx
			if cnt[ci] == 0:
				continue
			var inner := true
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if fg[(cy + dy) * nc + cx + dx] == 0:
						inner = false
			if not inner:
				continue
			var x := xsum[ci] / float(cnt[ci])
			xs.append(x)
			ys.append(ysum[ci])
			if x > 1.0:
				yd += ysum[ci]
				nd += 1
	return {"x": xs, "y": ys, "r": pearson(xs, ys), "ymean_disp": yd / maxf(float(nd), 1.0), "n_disp": nd}


## close-ups of the landing at strength 1: soft OFF, the #239 look (no normals), now (normals recomputed), and |now - before| x 8
func shoot(dir: String, k_imp: int) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var size := 480
	var sv := SubViewport.new()
	sv.size = Vector2i(size, size)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.own_world_3d = false
	root.add_child(sv)
	var cam := Camera3D.new()
	sv.add_child(cam)
	cam.current = true
	var views := [["torso", Vector3(0.0, 1.22, 0.05), 11.0], ["thigh", Vector3(0.1, 0.72, 0.1), 11.0]]
	var rows := []
	for vw in views:
		cam.fov = vw[2]
		cam.global_position = Vector3(1.9, 1.25, 2.3)
		cam.look_at(vw[1], Vector3.UP)
		for off in [0, 3]:
			var k: int = k_imp + off
			var row := []
			for mode in ["plain", "before", "after"]:
				m.soft_live.force_gd = false
				m.soft_live.normals_on = mode == "after"
				m.soft_strength_set(0.0 if mode == "plain" else 1.0)
				at(float(k) / 60.0)
				var im := await grab(sv)
				im.save_png(dir.path_join("close_%s_%s_%+d.png" % [vw[0], mode, off]))
				row.append(im)
			var diff := Image.create(size, size, false, Image.FORMAT_RGBA8)
			var d1: PackedByteArray = (row[1] as Image).get_data()
			var d2: PackedByteArray = (row[2] as Image).get_data()
			for y in size:
				for x in size:
					var p := (y * size + x) * 4
					var v := clampf(absf(lum(d2, p) - lum(d1, p)) * 8.0, 0.0, 1.0)
					diff.set_pixel(x, y, Color(v, v, v, 1.0))
			row.append(diff)
			rows.append(row)
	var sheet := Image.create(size * 4, size * rows.size(), false, Image.FORMAT_RGBA8)
	for r in rows.size():
		for c in 4:
			sheet.blit_rect(rows[r][c], Rect2i(0, 0, size, size), Vector2i(c * size, r * size))
	sheet.save_png(dir.path_join("soft2.png"))
	m.soft_live.normals_on = true
	sv.queue_free()
