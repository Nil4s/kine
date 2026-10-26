## godot --path . -s tests/onion_parts_test.gd     (ROADMAP 70: per-part onion skin)
## PER-PART ONION: combo3, the playhead mid-scene, one part picked (upperarm_r), 2 frames before and 2 after, step 1.
## BARS (stated before the run): ghost meshes = picked parts x (before + after) = 1 x 4 = 4 (and 2 x 4 = 8 with two picks); each ghost frame's bones lie
## within 1 mm (0.001 m) of a fresh mannequin posed from the body at that frame's time; past frames warm, future cool,
## the nearest frame stronger than the farthest; two picks -> 8; before 1 / after 3 / step 2 -> 4 ghosts at the times
## t -/+ 2 frames; the onion off -> 0 ghosts and no rigs left. The options are written to the test settings file only.
## Saves the picture to tmp/onion_parts.png (a window is needed for the picture: run it as a :w suite).
extends SceneTree

var fails := 0
var m: Node
var GB: Body


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func at(t: float) -> void:
	m.playhead = t
	m._refresh()
	await idle(2)


## the largest bone-origin gap (m) between a rig's skeleton and a fresh mannequin posed from the body at time t
func gap_at(rig: Dictionary, t: float) -> float:
	m.S.apply(GB, t)
	var fresh := Overlays.mannequin(m.ov, StandardMaterial3D.new())
	Overlays.pose_skeleton(fresh[1], fresh[2], GB)
	var worst := 0.0
	var fsk: Skeleton3D = fresh[1]
	var rsk: Skeleton3D = rig.sk
	for j in Body.ORDER:
		var a: int = rig.idx[j]
		var b: int = fresh[2][j]
		if a >= 0 and b >= 0:
			worst = maxf(worst, rsk.get_bone_global_pose(a).origin.distance_to(fsk.get_bone_global_pose(b).origin))
	(fresh[0] as Node3D).queue_free()
	return worst


func _init() -> void:
	GB = Body.new()
	GB.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	var ov: Overlays = m.ov
	var ts: Array = m.S.times()
	var mid := (float(ts[5][1]) + float(ts[6][1])) * 0.5
	var fps := float(m.S.fps)
	var h1 := 1.0 / fps   # one frame, s
	m._onion_panel_open()   # the View options panel: its controls drive the settings
	m.sel = "upperarm_r"
	m._onion_pick_sel()
	m._onion_set_parts(true)
	await at(mid)
	ok(ov.onion_on and ov.onion_parts_on and ov.onion_picks == ["upperarm_r"], "1 picked upperarm_r, parts-only on, onion on (picks %s)" % str(ov.onion_picks))
	var n1 := ov.onion_mesh_count()
	var shown := 0
	for r in ov._rigs:
		for pj in r.pieces:
			if (r.pieces[pj] as MeshInstance3D).is_visible_in_tree():
				shown += 1
	ok(n1 == 4 and shown == 4 and ov._rigs.size() == 4, "2 ghost meshes = 1 part x (2 before + 2 after) = %d (in the tree: %d, rigs %d; bar 4)" % [n1, shown, ov._rigs.size()])
	var worst := 0.0
	var fr := Overlays.onion_times(mid, m.S.length(), fps, 2, 2, 1)
	var worst_stale := 0.0
	for i in fr.size():
		var g := gap_at(ov._rigs[i], fr[i][0])
		worst = maxf(worst, g)
		worst_stale = maxf(worst_stale, gap_at(ov._rigs[i], mid))
	ok(worst <= 0.001 and worst_stale > 0.001, "3 bones at their own frame's time: worst gap %.6f m (bar 0.001); the same rigs against the playhead's pose: %.4f m (proves the frames differ)" % [worst, worst_stale])
	var a := []
	var h := []
	for i in fr.size():
		var c: Color = ov._rigs[i].mat.albedo_color
		a.append(c.a)
		h.append(c.h)
	ok(fr[0][1] == -1 and a[0] > a[1] and a[2] > a[3] and a[0] > a[3], "4 alpha by time distance: before %.2f -> %.2f, after %.2f -> %.2f (nearest strongest)" % [a[0], a[1], a[2], a[3]])
	var warm: Color = Tok.c("onion_past")
	var cool: Color = Tok.c("onion_future")
	var col0: Color = ov._rigs[0].mat.albedo_color
	var col2: Color = ov._rigs[2].mat.albedo_color
	ok(absf(col0.h - warm.h) < 0.02 and absf(col2.h - cool.h) < 0.02, "5 past frames take Tok onion_past (hue %.2f), future take onion_future (hue %.2f)" % [col0.h, col2.h])
	# two picks: 8 ghosts
	m.sel = "lowerarm_r"
	m._onion_pick_sel()
	await at(mid)
	var n2 := ov.onion_mesh_count()
	ok(n2 == 8, "6 two parts picked (upperarm_r, lowerarm_r): ghost meshes %d (bar 2 x 4 = 8)" % n2)
	# the picture: the picked arm's ghosts, on the cards
	m.onion_pop.hide()   # the picture shows the ghosts, not the panel over them
	await at(mid)
	for f in 3:
		await process_frame
	var img: Image = m.get_viewport().get_texture().get_image()
	img.save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/onion_parts.png")
	ok(FileAccess.file_exists("C:/Users/Nick/.claude/jobs/9afc22db/tmp/onion_parts.png"), "7 screenshot saved (tmp/onion_parts.png)")
	# frame choice, typed into the panel's spin boxes (two picks: upperarm_r, lowerarm_r): 1 before, 3 after, step 2 ->
	# four frames at t - 2f, t + 2f, t + 4f, t + 6f; each frame shows both picks: 2 x 4 = 8 ghost meshes
	(m._onion_ui["before"] as SpinBox).value = 1
	(m._onion_ui["after"] as SpinBox).value = 3
	(m._onion_ui["step"] as SpinBox).value = 2
	await at(mid)
	var want := Overlays.onion_times(mid, m.S.length(), fps, 1, 3, 2)
	var rt := []
	for r in ov._rigs:
		rt.append(snappedf(float(r.t), 0.0001))
	var wt := []
	for x in want:
		wt.append(snappedf(float(x[0]), 0.0001))
	var exp_t := [snappedf(mid - 2 * h1, 0.0001), snappedf(mid + 2 * h1, 0.0001), snappedf(mid + 4 * h1, 0.0001), snappedf(mid + 6 * h1, 0.0001)]
	ok(ov.onion_mesh_count() == 8 and rt == exp_t and wt == exp_t,
		"8 before 1 / after 3 / step 2, two parts: ghost meshes %d (bar 2 x 4 = 8), rig times %s (bar t-2f, t+2f, t+4f, t+6f = %s)" % [ov.onion_mesh_count(), str(rt), str(exp_t)])
	# saved to the test's settings file, never poser.cfg
	var cf := ConfigFile.new()
	cf.load(m.settings)
	ok(m.settings != "user://poser.cfg" and int(cf.get_value("onion", "before", -1)) == 1 and int(cf.get_value("onion", "step", -1)) == 2 and (cf.get_value("onion", "picks", []) as Array).size() == 2,
		"9 saved: before 1, step 2, two picks, in %s (not poser.cfg)" % m.settings)
	# off: no ghosts, no rigs
	m.ov.onion_on = false
	await at(mid)
	ok(ov.onion_mesh_count() == 0 and not ov.has_rigs(), "10 onion off: ghost meshes 0, rigs %d" % ov._rigs.size())
	print("ONION PARTS: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
