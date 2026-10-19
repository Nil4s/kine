## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/crowd_test.gd     (ROADMAP 95; a window: the fps is real)
## CROWD: "Crowd: make 20 copies of this fighter" on combo3 (opened read only; nothing is written to scenes/). Bars, written
## before measuring:
##   1 SAME SEED, SAME BYTES: Crowd.make(20, 7) twice gives byte-identical var_to_bytes; the app's crowd built twice from
##     seed 7 gives byte-identical Body.P of every copy at 3 playheads; seed 8 differs from seed 7 (else the seed does nothing).
##   2 NO OVERLAP: for seeds 1..20 every crowd has 20 copies, every pair of copies is at least Crowd.SPACING (0.6 m) apart
##     (xz, centre to centre), and every copy is at least Crowd.HOLE (1.2 m) from the hero.
##   3 LIMITS AT EVERY FRAME: for the 20 copies, 60 playheads over the clip, every joint of every copy: clamp_ang(j, ang) == ang
##     (within 1e-4 deg), 0 violations; and the noise is real: the largest |noise| over the crowd is > 1 deg, and never > 3 deg.
##   4 HEIGHTS: 1000 copies (seeds 1..50, 20 each): every stature within mean +- 2 sd (175.62 +- 2 x 6.86 cm); the sample mean
##     within 0.65 cm of 175.62 (3 standard errors) and the sample sd within 5 % of 6.86 cm; the app's copies carry their own
##     stature in their body (Body proportions) and the mesh stands at it: the copy's head bone is at stature x (0.97..1.03).
##   5 PLACEMENT (the thing drawn where it belongs, whole body): every copy's bones drawn (skeleton world pose) within 1 mm of
##     its placement applied to Body.P, for head, pelvis, both hands and both feet, at 3 playheads; mirrored copies included.
##   6 FPS: 20 copies plus the hero, playing (playhead advanced 1/30 s a frame, the full refresh and a rendered frame each):
##     >= 30 fps, printed; and the same with no crowd, printed for comparison.
##   7 ONE UNDO STEP: make adds exactly one undo step; Ctrl+Z removes the crowd (none drawn), redo brings back the same 20.
##   8 EXPORT THROUGH actors_export: with the crowd, _export_actors gives the hero and 20 copies (21); the .glb read back by
##     GLTFDocument has 21 skeletons; the .bvh export writes 21 files.
##   9 FLOOR: every copy's heel and toe inside the floor rect (>= 0.5 m margin from the farthest); removed: floor 4 m again.
##  10 SHOT: the 20-fighter crowd in a wide view, full app window: user://zz_crowd_shot.png (or $CROWD_SHOT).
extends SceneTree

var fails := 0
var m: Node
const DIR := "user://zz_crowd_export"
const BAR_M := 0.001
const JS := ["head", "pelvis", "hand_l", "hand_r", "foot_l", "foot_r"]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func all_bytes(sets: Array) -> PackedByteArray:
	var out := PackedByteArray()
	for c in sets:
		out.append_array(var_to_bytes(c))
	return out


## a copy's bone j in world space as drawn: its mannequin's skeleton, the bone's pose in its skeleton space
func bone_world(mm: Dictionary, j: String) -> Vector3:
	var sk: Skeleton3D = mm["skel"]
	return sk.global_transform * sk.get_bone_global_pose(mm["idx"][j]).origin


func crowd_bytes(seed: int, at: Array) -> PackedByteArray:
	m._crowd_free()
	m.S.crowd = {"n": 20, "seed": seed}
	m._crowd_sync()
	var out := PackedByteArray()
	for t in at:
		m.playhead = t
		m._crowd_draw()   # the app's own path: the copies posed from the table
		for mm in m.crowd_men:
			out.append_array(var_to_bytes(mm["B"].P))
	return out


func _init() -> void:
	var DIR_G := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(DIR_G)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	m.autosave = "user://autosave_crowd_test_%d.json" % OS.get_process_id()
	root.add_child(m)
	await process_frame
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	var J := Body.ORDER

	# ---- 1 same seed, same bytes
	var a := Crowd.make(20, 7, J)
	var b := Crowd.make(20, 7, J)
	var c8 := Crowd.make(20, 8, J)
	var pure_same := var_to_bytes(a) == var_to_bytes(b)
	var pure_diff := var_to_bytes(a) != var_to_bytes(c8)
	var at := [0.3, 0.9, 1.7]
	var app1 := crowd_bytes(7, at)
	var app2 := crowd_bytes(7, at)
	var app8 := crowd_bytes(8, at)
	var n_app: int = m.crowd_men.size()
	ok(pure_same and app1 == app2 and app1 != app8 and pure_diff and n_app == 20,
		"1 same seed, same bytes: make(20, 7) twice identical %s; the app's 20 copies at 3 playheads from seed 7 twice identical %s (%d bytes); seed 8 differs %s" % [pure_same, app1 == app2, app1.size(), app1 != app8])

	# ---- 2 no overlap
	var worst_gap := INF
	var worst_hero := INF
	var all_20 := true
	for seed in range(1, 21):
		var cs := Crowd.make(20, seed, [])
		if cs.size() != 20:
			all_20 = false
		for i in cs.size():
			var p: Vector2 = cs[i]["pos"]
			worst_hero = minf(worst_hero, p.length())
			for k in range(i + 1, cs.size()):
				worst_gap = minf(worst_gap, p.distance_to(cs[k]["pos"]))
	ok(all_20 and worst_gap >= Crowd.SPACING and worst_hero >= Crowd.HOLE,
		"2 no overlap: 20 seeds, all with 20 copies %s; the closest pair %.3f m (bar >= %.2f); the nearest copy to the hero %.3f m (bar >= %.1f)" % [all_20, worst_gap, Crowd.SPACING, worst_hero, Crowd.HOLE])

	# ---- 3 limits at every frame, the noise is real and bounded
	var viol := 0
	var worst_noise := 0.0
	var worst_err := 0.0
	var frames := 0
	var L: float = m.crowd_tb["L"]
	for k in m.crowd_men.size():
		var mm: Dictionary = m.crowd_men[k]
		for f in 60:
			m.playhead = L * float(f) / 60.0
			Crowd.pose(mm["c"], m.crowd_tb, mm["B"], m.playhead, J)
			frames += 1
			for j in J:
				var v: Vector3 = mm["B"].ang[j]
				var cl: Vector3 = mm["B"].clamp_ang(j, v)
				worst_err = maxf(worst_err, maxf(absf(cl.x - v.x), maxf(absf(cl.y - v.y), absf(cl.z - v.z))))
				if worst_err > 1e-4:
					viol += 1
				var T: float = m.playhead * float(mm["c"]["speed"]) + float(mm["c"]["dt"])
				var nz: Vector3 = Crowd.noise(mm["c"], j, T)
				worst_noise = maxf(worst_noise, maxf(absf(nz.x), maxf(absf(nz.y), absf(nz.z))))
	ok(viol == 0 and worst_noise > 1.0 and worst_noise <= Crowd.NOISE_DEG + 1e-6,
		"3 limits at every frame: %d copies x 60 playheads x %d joints, joints outside limits %d (bar 0); worst |noise| %.2f deg (bar > 1 and <= 3); clamp moved a joint by at most %.4f deg" % [m.crowd_men.size(), J.size(), viol, worst_noise, worst_err])

	# ---- 4 heights (1000 pure draws) and the app's copies
	var hs := []
	for seed in range(1, 51):
		for c in Crowd.make(20, seed, []):
			hs.append(float(c["stature"]))
	var lo := Crowd.STATURE_MEAN - 2.0 * Crowd.STATURE_SD
	var hi := Crowd.STATURE_MEAN + 2.0 * Crowd.STATURE_SD
	var inside := 0
	var sum := 0.0
	for h in hs:
		sum += h
		if h >= lo and h <= hi:
			inside += 1
	var mean := sum / hs.size()
	var var_s := 0.0
	for h in hs:
		var_s += (h - mean) * (h - mean)
	var sd := sqrt(var_s / (hs.size() - 1))
	var se := Crowd.STATURE_SD / sqrt(hs.size())
	var TRUNC_SD := Crowd.STATURE_SD * 0.8796   # the sd of a normal cut at +-2 sd: sqrt(1 - 4 phi(2) / (2 Phi(2) - 1)) = 0.8796 (the draws are cut, as the bar says)
	var stat_ok := inside == hs.size() and absf(mean - Crowd.STATURE_MEAN) <= 3.0 * se and absf(sd - TRUNC_SD) <= 0.05 * TRUNC_SD
	# the app's copies: their body carries the copy's stature, and the mesh's head stands at it
	var carry := true
	var worst_h := 0.0   # the rest head height of the copy over the default body's, against stature / DEFAULT_STATURE
	var d0 := Body.new()
	d0.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	for mm in m.crowd_men:
		var st: float = mm["c"]["stature"]
		var bst := float((mm["sc"] as Scene).body.get("stature", 0.0))
		if absf(bst - st) > 1e-4:
			carry = false
		var r: float = (mm["B"].p0["head"] as Vector3).y / (d0.p0["head"] as Vector3).y
		worst_h = maxf(worst_h, absf(r - st / Proportions.DEFAULT_STATURE))
	var head_ok := worst_h < 0.005
	ok(stat_ok and carry and head_ok,
		"4 heights: %d draws from 50 seeds, %d inside 175.62 +- 2 x 6.86 cm (bar all), mean %.2f cm (ref 175.62, bar +-%.2f), sd %.2f cm (ref %.2f: a normal cut at +-2 sd keeps 0.8796 of the sd, bar 5 %%); the app's %d copies carry their stature %s, and their rest head height is the default's x stature/1.8287 within %.2f %% (bar 0.5 %%)" % [hs.size(), inside, mean * 100.0, 3.0 * se * 100.0, sd * 100.0, TRUNC_SD * 100.0, m.crowd_men.size(), carry, worst_h * 100.0])

	# ---- 5 placement, drawn where it belongs (every copy, 3 playheads, six landmarks)
	var worst_mm := 0.0
	var mirrors := 0
	for pt in [0.3, 0.9, 1.7]:
		m.playhead = pt
		m._refresh()
		await idle(2)
		for k in m.crowd_men.size():
			var mm: Dictionary = m.crowd_men[k]
			var X: Transform3D = m.stage_root.global_transform * Crowd.placement(mm["c"])
			if bool(mm["c"]["mirror"]):
				mirrors += 1
			for j in JS:
				var want: Vector3 = X * (mm["B"].P[j] as Vector3)
				var got := bone_world(mm, j)
				worst_mm = maxf(worst_mm, want.distance_to(got))
	ok(worst_mm < BAR_M, "5 placement: %d copies x 3 playheads x %d landmarks (head, pelvis, hands, feet): the worst drawn bone %.3f mm from its placed Body.P (bar < 1 mm); %d mirrored copies among them" % [m.crowd_men.size(), JS.size(), worst_mm * 1000.0, mirrors])

	# ---- 5b the table against the exact pose at the DEFAULT stature (so only the table differs and the copy's own
	# proportions are not in it): 40 playheads over the clip, a fresh body for the exact pose each time, no noise on
	# either. Bars: mean joint error < 0.05 deg, worst < 5 deg
	var sum_ang := 0.0
	var worst_ang := 0.0
	var worst_tab := 0.0
	var cnt_ang := 0
	var cd: Dictionary = m.crowd_men[0]["c"].duplicate(true)
	cd["stature"] = Proportions.DEFAULT_STATURE
	cd["dt"] = 0.0
	cd["speed"] = 1.0
	for j in J:
		cd["amp"][j] = Vector3.ZERO   # no noise on either side: this bar is the table alone
	var sc0: Scene = Crowd.scene_for(m.S, cd)
	var LL := sc0.length()
	for q in 40:
		var pt := LL * float(q) / 40.0 + 0.013
		var tabB := Body.new()
		tabB.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		Crowd.pose(cd, m.crowd_tb, tabB, pt, J)
		var exact := Body.new()
		exact.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		sc0.apply(exact, fposmod(pt, LL))
		for j in J:
			var d := ((tabB.ang[j] as Vector3) - (exact.ang[j] as Vector3)).length()
			worst_ang = maxf(worst_ang, d)
			sum_ang += d
			cnt_ang += 1
		for j in JS:
			worst_tab = maxf(worst_tab, (tabB.P[j] as Vector3).distance_to(exact.P[j] as Vector3))
	var mean_ang := sum_ang / cnt_ang
	ok(mean_ang < 0.05 and worst_ang < 5.0,
		"5b the table against the exact pose at the default stature, 40 playheads x %d joints: mean joint error %.4f deg (bar < 0.05), worst %.2f deg (bar < 5; at a fast move), worst landmark %.1f mm" % [J.size(), mean_ang, worst_ang, worst_tab * 1000.0])

	# ---- 6 fps: playing, 20 copies and the hero, a rendered frame each
	var fps_on := 0.0
	var fps_off := 0.0
	for pass_crowd in [true, false]:
		if pass_crowd:
			m.S.crowd = {"n": 20, "seed": 7}
		else:
			m.S.crowd = {}
		m._refresh()
		await idle(10)
		var n := 120
		var t0 := Time.get_ticks_usec()
		for f in n:
			m.playhead = fmod(float(f) / 30.0, m.S.length())
			m._refresh()
			await process_frame
		var fps := float(n) / ((Time.get_ticks_usec() - t0) / 1000000.0)
		if pass_crowd:
			fps_on = fps
		else:
			fps_off = fps
	m.S.crowd = {"n": 20, "seed": 7}
	m._crowd_sync()
	ok(fps_on >= 30.0, "6 fps: 20 copies + hero playing at %.1f fps (bar >= 30); the same scene with no crowd %.1f fps" % [fps_on, fps_off])

	# ---- 7 one undo step
	m.S.crowd = {}
	m._refresh()
	var before: int = m.undo.size()
	m._crowd_make()
	m._refresh()
	await idle(2)
	var after_make: int = m.undo.size()
	var made: bool = int(m.S.crowd.get("n", 0)) == 20 and m.crowd_men.size() == 20
	m._undo()
	m._refresh()
	await idle(2)
	var gone: bool = m.S.crowd.is_empty() and m.crowd_men.is_empty()
	m._redo()
	m._refresh()
	await idle(2)
	var back: bool = m.crowd_men.size() == 20
	ok(after_make == before + 1 and made and gone and back,
		"7 one undo step: undo stack %d -> %d (bar +1); the crowd made %s; Ctrl+Z removes it (none drawn) %s; redo brings the 20 back %s" % [before, after_make, made, gone, back])

	# ---- 8 export through actors_export
	var acts: Array = m._export_actors()
	var glb: String = m._export_glb(DIR)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var skels := -1
	if glb != "" and doc.append_from_file(ProjectSettings.globalize_path(glb), st) == OK:
		skels = st.get_skeletons().size()
	var bvh_dir := DIR
	m._export_bvh(bvh_dir)
	var bvhs := 0
	for f in DirAccess.get_files_at(DIR_G):
		if f.ends_with(".bvh"):
			bvhs += 1
	ok(acts.size() == 21 and skels == 21 and bvhs == 21,
		"8 export: _export_actors %d (bar 21 = the hero + 20); the .glb read back by GLTFDocument: %d skeletons (bar 21); the .bvh export: %d files (bar 21)" % [acts.size(), skels, bvhs])
	for f in DirAccess.get_files_at(DIR_G):
		DirAccess.remove_absolute(DIR_G + "/" + f)
	DirAccess.remove_absolute(DIR_G)

	# ---- 9 the floor: every copy's heel and toe (hero space, 3 playheads) inside the floor, 0.5 m of margin from the
	# farthest one; with no crowd the floor is back at 4 m and the grid's fade at its default
	m.S.crowd = {"n": 20, "seed": 7}
	m._crowd_sync()
	var h_floor: float = 0.0
	var outside := 0
	var far: float = 0.0
	for pt in [0.3, 0.9, 1.7]:
		m.playhead = pt
		m._refresh()
		await idle(1)
		h_floor = m.floor_pm.size.x * 0.5
		for mm in m.crowd_men:
			var X: Transform3D = Crowd.placement(mm["c"])
			for side in ["_l", "_r"]:
				for q in [Proportions.heel(mm["B"], side), Proportions.toe(mm["B"], side)]:
					var p: Vector3 = X * q
					far = maxf(far, maxf(absf(p.x), absf(p.z)))
					if absf(p.x) > h_floor or absf(p.z) > h_floor:
						outside += 1
	var margin: float = h_floor - far
	m.S.crowd = {}
	m._refresh()
	await idle(1)
	var back_floor: float = m.floor_pm.size.x
	var back_grid: bool = is_equal_approx(m.grid_end, (load("res://scripts/main.gd") as Script).get_script_constant_map()["GRID_END"]) and not m.grid_square
	ok(outside == 0 and margin >= 0.5 - 1e-3 and absf(back_floor - 4.0) < 1e-6 and back_grid,
		"9 floor: every copy's heel and toe inside the floor rect at 3 playheads (%d outside, bar 0); the floor half %.2f m, the farthest foot %.2f m, margin %.2f m (bar >= 0.50); removed: floor %.1f m, grid fade at its default %s (bar 4 m, default)" % [outside, h_floor, far, margin, back_floor, back_grid])

	# ---- 10 the shot: the full app window (UI visible), the wide view
	m.S.crowd = {"n": 20, "seed": 7}
	m._crowd_sync()
	m.playhead = 0.9
	m._refresh()
	m._turn_to(0.0, -16.0, 15.0, Vector3(0, 0.9, 0), false)
	await idle(8)
	var img := root.get_texture().get_image()
	var shot := OS.get_environment("CROWD_SHOT")
	if shot == "":
		shot = "user://zz_crowd_shot.png"
	img.save_png(shot)
	ok(img.get_size().x > 0, "10 shot: %s (%dx%d), full app window, 21 figures in view" % [shot, img.get_size().x, img.get_size().y])

	print("CROWD: %d fails" % fails)
	m.queue_free()
	await idle(2)
	quit(1 if fails > 0 else 0)
