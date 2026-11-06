extends SceneTree
## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/softwire_test.gd     (L22 SOFT-WIRE: the flesh of PR #236 in the app)
## SOFT_WIRE_SHOT=<dir> also renders the close-up of the landing (frames -2, 0, +3, +8; with and without soft).
##
## THE WORK: tests/soft_test.gd proved the flesh in a harness (35 bars). This suite proves the WIRING, bars written BEFORE the code
## (this file's first commit has no scripts/soft_live.gd):
##   - an Expert BODY panel row per region (belly, chest, thighs, arms) and a strength slider; default OFF;
##   - playback: the bake runs on a worker thread when the clip changes, the drawn skin is deformed each frame from the bake;
##   - the sag is measured along gravity in the BODY frame (a body upside down is not "standing" in the flesh's eyes);
##   - the scene key: S.soft = {"regions": [...], "strength": x}; the strength only in the file when it is not 1.
## Each bar has a PLANTED CONTROL: the same measurement on a deliberately wrong system, which the detector must see.
##   1 OFF IS BYTE-IDENTICAL   the toggles are off and the slider at 100 % on a fresh app; 40 played frames of a clip give the same
##                             pose bytes and the same vertex bytes of every body piece as after a toggle ON, a finished bake and a
##                             toggle OFF; the scene dict has no "soft" key before and after. CONTROL: with regions ON the vertex
##                             bytes of at least one frame differ and the key appears.
##   2 LIVE == BAKE            the vertices of the drawn pieces at frames -2, 0, +3, +8 of the landing equal SoftBody.skin_deform
##                             fed the bake's displacement at that frame (within 1e-6 m); the worker's bake equals a bake made on
##                             the main thread (1e-12). CONTROL: the expected vertices from the frame 3 steps off differ (> 1e-5).
##   2b STRENGTH               strength 2 moves the vertices twice as far as strength 1 (ratio 2 +- 1 %), strength 0 leaves the
##                             mesh as it was. CONTROL: strength 1 against strength 1 reads a ratio of 1.
##   3 PLACEMENT               every vertex that moved is inside a region's box on its host part, and each region moves >= 5 vertices.
##                             CONTROL: the same deform with the regions shifted 0.10 m up moves vertices outside the true boxes.
##   4 SAG IN THE BODY FRAME   a belly region, the body turned upside down and held: the flesh hangs down in the world, the standing
##                             sag turned with the bones: the settled offset along down is 2 s (s = the standing sag) in the body
##                             frame and 0 in the old world frame. CONTROL: the world-frame number reads ~0 and fails the 2 s claim.
##   5 SCENE KEY               toggles write regions in order, undo takes them back, the strength is in the file only when it is not
##                             1, and loads back; mirror keeps it. CONTROL: strength 1 writes no "strength".
##   6 COST                    the soft-OFF hook is a flag test (mean < 0.02 ms a call, no thread, no mesh swapped); with soft ON the
##                             same call costs more than 10x that. CONTROL: the ON cost is seen. The frame times (p50 / p95) of 240 played frames
##                             off and on are PRINTED; the perf60 number is in the lane report.
var fails := 0
var m: Node
const G_DOWN := Vector3(0.0, -1.0, 0.0)
const TMP := "user://softwire_scene.json"


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


## the L17 landing: dip, flight, a stiff landing
func landing_scene() -> Scene:
	var B := body()
	var S := Scene.new()
	S.name = "zz_softwire_land"
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


func digest(b: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_MD5)
	h.update(b)
	return h.finish().hex_encode()


func piece_verts(mesh: Mesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	for si in mesh.get_surface_count():
		out.append_array(mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX])
	return out


## the pose bytes and every piece's vertex bytes at time t, as the app draws them
func frame_sig(t: float) -> String:
	m.playhead = t
	m._ps().apply(m.B, t)
	m._refresh()
	var parts := PackedByteArray()
	parts.append_array(var_to_bytes(m.B.state()))
	var keys: Array = m.pieces.keys()
	keys.sort()
	for j in keys:
		parts.append_array(var_to_bytes(piece_verts((m.pieces[j] as MeshInstance3D).mesh)))
	return digest(parts)


func sigs(n: int) -> Array:
	var out := []
	for i in n:
		out.append(frame_sig(float(i) / 60.0))
	return out


func boot_app() -> void:
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


func wait_ready(limit_s := 60.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not m.soft_live.ready() and float(Time.get_ticks_msec() - t0) < limit_s * 1000.0:
		await process_frame
	return m.soft_live.ready()


func scaled(d: PackedVector3Array, s: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	for v in d:
		out.append(v * s)
	return out


## the vertices SoftBody.skin_deform makes for this piece from the ORIGINAL mesh and the displacements disps
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


## the vertices a mesh draws (its index arrays use them); the rest of a piece's vertex buffer is never drawn
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


## largest vertex difference over the DRAWN vertices (mask) of a piece
func max_diff(a: PackedVector3Array, b: PackedVector3Array, mask := PackedByteArray()) -> float:
	if a.size() != b.size():
		return INF
	var mx := 0.0
	for i in a.size():
		if mask.size() == a.size() and mask[i] == 0:
			continue
		mx = maxf(mx, (a[i] - b[i]).length())
	return mx


func _init() -> void:
	var t_all := Time.get_ticks_msec()
	ok(SoftBody.native_on(), "0 the native door is open (the bake would take minutes in GDScript)")
	await boot_app()
	var S := landing_scene()
	var fl := S.flights()
	var t_imp: float = float(fl[0]["t1"]) if fl.size() == 1 else 1.0
	var k_imp := int(round(t_imp * 60.0))

	# ---------- 1 OFF IS BYTE-IDENTICAL
	await load_landing(S)
	var names_ui := ["soft_belly", "soft_chest", "soft_thighs", "soft_arms"]
	var all_off := true
	for nm in names_ui:
		var c := ctl(nm)
		all_off = all_off and c is BaseButton and not (c as BaseButton).button_pressed
	var sl := ctl("soft_strength") as HSlider
	ok(all_off, "1a the four BODY toggles (belly, chest, thighs, arms) exist and are OFF on a fresh app")
	ok(sl != null and absf(sl.value - 100.0) < 1e-6, "1a the strength slider exists and reads 100 %% (%s)" % [str(sl.value) if sl != null else "missing"])
	ok(m.S.soft.is_empty() and not SoftBody.active(m.S) and not m.soft_live.engaged, "1a the scene has no soft state and the live layer is not engaged")
	var d_off := JSON.stringify(m.S.to_dict(m.B, false))
	var sig_a := sigs(40)
	ok(not d_off.contains("\"soft\""), "1b the scene dict has no 'soft' key")
	ok(m.soft_live.work_us == 0 and m.soft_live.starts == 0 and not m.soft_live.busy(), "1b with soft off the live layer did nothing in 40 played frames (work %d us, %d bakes)" % [m.soft_live.work_us, m.soft_live.starts])
	# ON, bake finished, drawn, then OFF again
	(ctl("soft_belly") as BaseButton).button_pressed = true
	(ctl("soft_thighs") as BaseButton).button_pressed = true
	await idle(2)
	var ready1 := await wait_ready()
	ok(ready1, "1c the bake finished on its worker (no stall)")
	var sig_on := sigs(40)
	var diff_on := 0
	for i in 40:
		if sig_on[i] != sig_a[i]:
			diff_on += 1
	ok(diff_on >= 5 and JSON.stringify(m.S.to_dict(m.B, false)).contains("\"soft\""),
		"1c CONTROL: with belly + thighs ON the vertex bytes differ in %d of 40 frames and the 'soft' key is written (the detector sees a change)" % diff_on)
	(ctl("soft_belly") as BaseButton).button_pressed = false
	(ctl("soft_thighs") as BaseButton).button_pressed = false
	await idle(2)
	var sig_b := sigs(40)
	var back := true
	for i in 40:
		back = back and sig_b[i] == sig_a[i]
	ok(back, "1c after ON and OFF again the 40 frames are byte-identical to the untouched app (pose bytes and every vertex)")
	ok(JSON.stringify(m.S.to_dict(m.B, false)) == d_off and m.S.soft.is_empty() and not m.soft_live.engaged,
		"1c the scene dict is byte-identical to before and S.soft is empty again (the last region off drops the key)")
	ok(m.soft_live._cache.is_empty() and not m.soft_live.busy(), "1c the live layer let go of every piece (no cache, no thread)")

	# ---------- 2 LIVE == BAKE   (all four groups, strength 1)
	for nm in names_ui:
		(ctl(nm) as BaseButton).button_pressed = true
	await idle(2)
	ok(await wait_ready(), "2 the bake for all six regions finished")
	var names: Array = m.soft_live.names.duplicate()
	ok(names.size() == 6, "2 six regions are live (%s)" % str(names))
	var regs: Array = m.soft_live.regs
	var bake: Dictionary = m.soft_live.bake
	var nf: int = int(bake["frames"])
	var worst := 0.0
	var worst_ctl := 0.0
	var peaks := []
	var moved_total := 0
	var out_of_box := 0
	var inside_by_region := {}
	for n in names:
		inside_by_region[n] = {}
	for off in [-2, 0, 3, 8]:
		var k: int = k_imp + off
		var t := float(k) / 60.0
		m.playhead = t
		m._ps().apply(m.B, t)
		m._refresh()
		var disps := []
		var disps_wrong := []
		var pk := 0.0
		for n in names:
			var d: PackedVector3Array = (bake["regions"][n]["disp"] as Array)[k]
			disps.append(d)
			disps_wrong.append((bake["regions"][n]["disp"] as Array)[clampi(k + 3, 0, nf - 1)])
			for v in d:
				pk = maxf(pk, v.length())
		peaks.append(pk)
		for j in m.pieces:
			var piece: MeshInstance3D = m.pieces[j]
			var live := piece_verts(piece.mesh)
			var want := expected_verts(piece, regs, disps)
			var mask := used_mask(piece.mesh)
			worst = maxf(worst, max_diff(live, want, mask))
			var wrong := expected_verts(piece, regs, disps_wrong)
			# the control only counts where the right and the wrong frame differ at all
			if max_diff(want, wrong, mask) > 1e-5:
				worst_ctl = maxf(worst_ctl, max_diff(live, wrong, mask))
			# 3 PLACEMENT, on the same frames
			var orig_v := piece_verts(m.soft_live.orig_mesh(piece))
			var world: PackedVector3Array = m.soft_live.posed_world(piece, m.soft_live.orig_mesh(piece))
			for i in live.size():
				if (live[i] - orig_v[i]).length() > 1e-9:
					moved_total += 1
					var inside := false
					for ri in regs.size():
						if SoftBody.in_box(regs[ri], m.B, world[i], 1e-6):
							inside = true
							(inside_by_region[names[ri]] as Dictionary)[str(j) + ":" + str(i)] = true
					if not inside:
						out_of_box += 1
	print("2 LIVE vs BAKE: peak flesh travel at -2/0/+3/+8: %s mm; worst vertex difference %s m; wrong-frame control %s m" % [str(peaks.map(func(p): return snappedf(p * 1000.0, 0.01))), worst, worst_ctl])
	ok(worst < 1e-6, "2 the drawn vertices equal skin_deform of the bake's frame: worst %s m (bar 1e-6)" % worst)
	ok(worst_ctl > 1e-5, "2 CONTROL: the expected vertices from the frame 3 steps off are %s m away (> 1e-5): the comparison sees the wrong frame" % worst_ctl)
	ok(peaks.max() > 0.001, "2 anti-vacuity: the flesh moves %.2f mm at the largest of the 4 frames (> 1 mm)" % (float(peaks.max()) * 1000.0))
	var bk_main := SoftBody.bake_scene(S, body(), names, 60.0, {"sag_frame": "body"})
	var bd := 0.0
	for n in names:
		for k in [k_imp - 2, k_imp, k_imp + 3, k_imp + 8]:
			bd = maxf(bd, max_diff((bake["regions"][n]["disp"] as Array)[k], (bk_main["regions"][n]["disp"] as Array)[k]))
	ok(bd < 1e-12, "2 the worker's bake equals a bake made on the main thread: worst %s m" % bd)
	var nudged := ((bk_main["regions"][names[0]]["disp"] as Array)[k_imp] as PackedVector3Array).duplicate()
	nudged[3] += Vector3(1e-6, 0, 0)
	ok(max_diff((bake["regions"][names[0]]["disp"] as Array)[k_imp], nudged) > 1e-7, "2 CONTROL: one node nudged 1e-6 m is seen by the bake comparison")

	# ---------- 3 PLACEMENT
	var each_ok := true
	var counts := []
	for n in names:
		var c: int = (inside_by_region[n] as Dictionary).size()
		counts.append(c)
		each_ok = each_ok and c >= 5
	print("3 PLACEMENT: %d vertex moves over 4 frames, %d outside every box; moved vertices per region %s" % [moved_total, out_of_box, str(counts)])
	ok(moved_total > 0 and out_of_box == 0, "3 every moved vertex is inside a region box on its host part (%d moves, %d outside)" % [moved_total, out_of_box])
	ok(each_ok, "3 each region moves at least 5 skin vertices (%s)" % str(counts))
	# CONTROL: the regions shifted 0.10 m up, deforming the same pieces: vertices move OUTSIDE the true boxes
	var shifted := []
	var rest_b := body()
	for n in names:
		shifted.append(SoftBody.region_new(rest_b, n, {"shift": Vector3(0, 0.10, 0)}))
	var k0 := k_imp
	m.playhead = float(k0) / 60.0
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	var disps0 := []
	for n in names:
		disps0.append((bake["regions"][n]["disp"] as Array)[k0])
	var out_ctl := 0
	for j in m.pieces:
		var piece2: MeshInstance3D = m.pieces[j]
		var o2: Mesh = m.soft_live.orig_mesh(piece2)
		var tmp := MeshInstance3D.new()
		tmp.mesh = o2
		tmp.skin = piece2.skin
		piece2.get_parent().add_child(tmp)
		tmp.transform = piece2.transform
		tmp.skeleton = piece2.skeleton
		var dm := SoftBody.skin_deform(tmp, shifted, m.B, disps0)
		if dm != null:
			var nv := piece_verts(dm)
			var ov := piece_verts(o2)
			var wv: PackedVector3Array = m.soft_live.posed_world(piece2, o2)
			for i in nv.size():
				if (nv[i] - ov[i]).length() > 1e-9:
					var inside := false
					for ri in regs.size():
						if SoftBody.in_box(regs[ri], m.B, wv[i], 1e-6):
							inside = true
					if not inside:
						out_ctl += 1
		piece2.get_parent().remove_child(tmp)
		tmp.free()
	ok(out_ctl > 0, "3 CONTROL: the regions shifted 0.10 m up move %d vertices outside the true boxes: the placement test rejects it" % out_ctl)

	# ---------- 2b STRENGTH
	var amp := func(s: float) -> float:
		sl.value = s * 100.0
		await process_frame
		m.playhead = float(k_imp) / 60.0
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		var tot := 0.0
		for j in m.pieces:
			var p: MeshInstance3D = m.pieces[j]
			var lv := piece_verts(p.mesh)
			var ov := piece_verts(m.soft_live.orig_mesh(p))
			for i in lv.size():
				tot += (lv[i] - ov[i]).length()
		return tot
	var a1: float = await amp.call(1.0)
	var a2: float = await amp.call(2.0)
	var a0: float = await amp.call(0.0)
	var a1b: float = await amp.call(1.0)
	print("2b STRENGTH: summed vertex travel at the impact frame: x1 %.3f mm, x2 %.3f mm, x0 %s mm" % [a1 * 1000.0, a2 * 1000.0, a0 * 1000.0])
	ok(a1 > 0.0 and absf(a2 / a1 - 2.0) < 0.02, "2b strength 2 moves the vertices %.3f times as far as strength 1 (bar 2 +- 2 %%)" % (a2 / maxf(a1, 1e-12)))
	ok(a0 < 1e-9, "2b strength 0 leaves the mesh as it was (%s m summed)" % a0)
	ok(absf(a1b / a1 - 1.0) < 1e-6 and absf(a1b / maxf(a1, 1e-12) - 2.0) > 0.5, "2b CONTROL: strength 1 against strength 1 reads a ratio of %.4f, not 2" % (a1b / a1))
	sl.value = 100.0
	await process_frame

	# ---------- 4 SAG IN THE BODY FRAME
	await _sag_bars()

	# ---------- 5 SCENE KEY
	for nm in names_ui:
		(ctl(nm) as BaseButton).button_pressed = false
	await idle(2)
	ok(m.S.soft.is_empty() and not m.S.to_dict(m.B, false).has("soft"), "5 all four toggles off: S.soft is empty and the key is gone")
	(ctl("soft_thighs") as BaseButton).button_pressed = true
	(ctl("soft_belly") as BaseButton).button_pressed = true
	var rg: Array = m.S.soft.get("regions", [])
	ok(rg.has("thigh_l") and rg.has("thigh_r") and rg.has("belly") and rg.size() == 3, "5 thighs + belly write thigh_l, thigh_r, belly (%s)" % str(rg))
	m._undo()
	await idle(2)
	ok(not (m.S.soft.get("regions", []) as Array).has("belly") and (m.S.soft.get("regions", []) as Array).has("thigh_l"), "5 Ctrl+Z takes the belly toggle back (%s)" % str(m.S.soft))
	sl.value = 250.0
	await process_frame
	var dd: Dictionary = m.S.to_dict(m.B, false)
	ok(dd.has("soft") and absf(float(dd["soft"].get("strength", 1.0)) - 2.5) < 1e-9, "5 strength 250 %% is in the file as 2.5")
	var S2 := Scene.new()
	S2.from_dict(dd)
	ok(absf(SoftBody.strength_of(S2) - 2.5) < 1e-9 and SoftBody.regions_of(S2) == SoftBody.regions_of(m.S), "5 the strength and regions load back")
	var mir := SoftBody.mirror_file(dd["soft"])
	ok(absf(float(mir.get("strength", 1.0)) - 2.5) < 1e-9 and (mir["regions"] as Array).has("thigh_r"), "5 mirror keeps the strength and swaps sides")
	sl.value = 100.0
	await process_frame
	var d1: Dictionary = m.S.to_dict(m.B, false)
	ok(d1.has("soft") and not (d1["soft"] as Dictionary).has("strength"), "5 CONTROL: strength 1 writes no 'strength' key (a #236 file stays byte-identical)")
	for nm in names_ui:
		(ctl(nm) as BaseButton).button_pressed = false
	await idle(2)

	# ---------- 6 COST
	var tcall := func(n: int) -> float:
		var t0 := Time.get_ticks_usec()
		for i in n:
			m._soft_draw()
		return float(Time.get_ticks_usec() - t0) / 1000.0 / float(n)
	var off_ms: float = tcall.call(3000)
	ok(off_ms < 0.02 and not m.soft_live.engaged and not m.soft_live.busy(), "6 the soft-OFF hook costs %.5f ms a call (< 0.02), no thread, nothing engaged" % off_ms)
	(ctl("soft_thighs") as BaseButton).button_pressed = true
	(ctl("soft_belly") as BaseButton).button_pressed = true
	await idle(2)
	await wait_ready()
	var on_ms: float = tcall.call(200)
	ok(on_ms > 10.0 * maxf(off_ms, 0.0005), "6 CONTROL: the same call with thighs + belly ON costs %.4f ms (> 10 x the off cost): the timer sees the work" % on_ms)
	for nm in names_ui:
		(ctl(nm) as BaseButton).button_pressed = false
	await idle(2)
	var fr_off := await _frames(240)
	for nm in names_ui:
		(ctl(nm) as BaseButton).button_pressed = true
	await idle(2)
	await wait_ready()
	var fr_on := await _frames(240)
	print("6 FRAMES (240 played frames, the landing clip, 1920 x 1080 not forced; wall ms): soft OFF p50 %.2f p95 %.2f | soft ON (6 regions) p50 %.2f p95 %.2f" % [
		_pct(fr_off, 50), _pct(fr_off, 95), _pct(fr_on, 50), _pct(fr_on, 95)])

	print("softwire: %d failures (%.1f s)" % [fails, float(Time.get_ticks_msec() - t_all) / 1000.0])
	var shot := OS.get_environment("SOFT_WIRE_SHOT")
	if shot != "":
		await _shot(shot, S, k_imp)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)


func _pct(a: Array, p: float) -> float:
	var b := a.duplicate()
	b.sort()
	return float(b[clampi(int(ceil(p / 100.0 * b.size())) - 1, 0, b.size() - 1)])


func _frames(n: int) -> Array:
	var w := []
	m.playing = true
	m.playhead = 0.0
	var last := Time.get_ticks_usec()
	for i in n:
		await process_frame
		var now := Time.get_ticks_usec()
		w.append(float(now - last) / 1000.0)
		last = now
	m.playing = false
	return w


## 4: a belly region, settled standing, then the host bone turned over 180 degrees about x (the joint stays) and held 2.5 s.
## (The pelvis is limited to +-100 degrees of bend in data/body_limits.json, so a whole body cannot be turned over by a clip; the bone is
## turned directly here, which is what the region sees of any pose.) Returns [s (standing sag, m), mean y offset after the turn]
func _flip_run(body_sag: bool) -> Array:
	var B := body()
	var reg := SoftBody.region_new(B, "belly", {})
	var so := {"dt": 1.0 / 60.0, "nsub": 8, "iters": SoftBody.DEFAULT_ITERS, "g": Vector3(0.0, -9.81, 0.0), "damp_scale": 1.0}
	for k in 90:
		SoftBody.region_step(reg, B, so)
	reg["static"] = SoftBody.region_disp(reg, B)
	if body_sag:
		reg["sag_body"] = true
		reg["g0"] = B.G[reg["host"]]
	var s_sag := 0.0
	for v in (reg["static"] as PackedVector3Array):
		s_sag -= v.y
	s_sag /= float((reg["static"] as PackedVector3Array).size())
	var y_stand := 0.0
	for v in SoftBody.region_disp(reg, B):
		y_stand += v.y
	y_stand /= float((reg["static"] as PackedVector3Array).size())
	B.G[reg["host"]] = Quaternion(Vector3(1, 0, 0), PI) * (B.G[reg["host"]] as Quaternion)
	for k in 150:
		SoftBody.region_step(reg, B, so)
	var d := SoftBody.region_disp(reg, B)
	var y := 0.0
	for v in d:
		y += v.y
	return [s_sag, y / float(d.size()), y_stand]


func _sag_bars() -> void:
	var rb := _flip_run(true)
	var rw := _flip_run(false)
	var s_sag: float = rb[0]
	var yb: float = rb[1]
	var yw: float = rw[1]
	print("4 SAG: standing sag s = %.3f mm; host turned over and settled, mean y offset: body frame %.3f mm (claim -2 s = %.3f), world frame %.3f mm; before the turn: body %.4f world %.4f mm" % [
		s_sag * 1000.0, yb * 1000.0, -2.0 * s_sag * 1000.0, yw * 1000.0, float(rb[2]) * 1000.0, float(rw[2]) * 1000.0])
	ok(s_sag > 0.0002, "4 anti-vacuity: the standing sag is %.3f mm (> 0.2 mm)" % (s_sag * 1000.0))
	ok(absf(float(rb[2])) < 0.25 * s_sag and absf(float(rw[2])) < 0.25 * s_sag, "4 standing, both frames read ~0")
	ok(yb < -1.5 * s_sag and yb > -2.5 * s_sag, "4 body frame: turned over the flesh sits %.3f mm below the bone-carried place = %.2f s (bar 1.5 .. 2.5 s)" % [yb * 1000.0, -yb / s_sag])
	ok(absf(yw) < 0.3 * s_sag, "4 world frame (the L17 behaviour) reads %.2f s: the standing sag is subtracted unturned, so the offset is lost" % (-yw / s_sag))
	ok(not (yw < -1.5 * s_sag and yw > -2.5 * s_sag), "4 CONTROL: the world-frame subtraction fails the 2 s claim (%.2f s)" % (-yw / s_sag))


## the close-up of the landing, with and without soft (SOFT_WIRE_SHOT=<dir>)
func _shot(dir: String, S: Scene, k_imp: int) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var strength_list := [1.0]
	var sv := SubViewport.new()
	sv.size = Vector2i(900, 900)
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.own_world_3d = false
	root.add_child(sv)
	var cam := Camera3D.new()
	sv.add_child(cam)
	cam.current = true
	cam.fov = 18.0
	cam.global_position = Vector3(3.2, 0.95, 1.2)
	cam.look_at(Vector3(0.0, 0.95, 0.0), Vector3.UP)
	var names_ui := ["soft_belly", "soft_chest", "soft_thighs", "soft_arms"]
	for st in strength_list:
		for on in [false, true]:
			for nm in names_ui:
				(ctl(nm) as BaseButton).button_pressed = on
			(ctl("soft_strength") as HSlider).value = float(st) * 100.0
			await idle(2)
			if on:
				await wait_ready()
			for off in [-2, 0, 3, 8]:
				var t := float(k_imp + off) / 60.0
				m.playhead = t
				m._ps().apply(m.B, t)
				m._refresh()
				for i in 3:
					await process_frame
				await RenderingServer.frame_post_draw
				var img: Image = sv.get_texture().get_image()
				img.save_png(dir.path_join("close_%s_%+d.png" % ["soft" if on else "plain", off]))
	sv.queue_free()
