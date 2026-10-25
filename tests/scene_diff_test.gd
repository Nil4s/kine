## godot --path . -s tests/scene_diff_test.gd [-- shot=<png>]   (ROADMAP 98, DIFF REPORT; a window: main is built)
## Bars, stated before the numbers:
##   identical versions -> no rows, the head says "No changes"
##   one joint rotated 10 deg on card 3 -> exactly one row, naming "right elbow" and "10.0°"
##   a card inserted at the front -> exactly 1 row, "added" (not N changed)
##   a hold change 0.3 -> 0.5 s -> exactly one timing row with "0.30 s -> 0.50 s"
##   a joint moved 0.3 deg -> no row (under 0.5 deg); 0.7 deg -> one row
##   two 30-card scenes -> the report in < 200 ms
##   comparing (the panel, a row click, Show both) writes nothing: the scene file's bytes and the open scene are the same
##   a row click lands on its card and selects its joint; Show both ghosts the older card's pose at that card's time
##   the ghost is translucent (alpha 0.35), writes no depth, and is grown 4 mm along its normals (no z-fight with the body)
## With shot=<png> the panel with a ghosted pose, whole body, is saved to that file (the one shot).
extends SceneTree

var fails := 0
var m: Node
const DIR := "user://sdiff_test"
const OLD := "user://sdiff_test/v001.json"
const SAME := "user://sdiff_test/v_same.json"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


## a pose: the upper arm and the elbow (lowerarm_r) bent, every other joint at 0; the body's own dictionary
func pose_dict(upper: float, elbow: float) -> Dictionary:
	for j in Body.ORDER:
		m.B.ang[j] = Vector3.ZERO
	m.B.ang["upperarm_r"] = Vector3(upper, 0, 0)
	m.B.ang["lowerarm_r"] = Vector3(elbow, 0, 0)
	m.B.fk()
	return m.B.to_dict()


## start / reach / hold, every move 0.5 s, the hold's elbow at elbow3 and its hold at hold3
func scene3(elbow3 := 60.0, hold3 := 0.3) -> Scene:
	var S := Scene.new()
	S.name = "zz_sdiff"
	S.add("start", pose_dict(0, 0))
	S.add("reach", pose_dict(40, 30))
	S.add("hold", pose_dict(40, elbow3))
	for c in S.cards:
		c["move"] = 0.5
	S.cards[2]["hold"] = hold3
	return S


func nice(j: String) -> String:
	return m.nice(j)


func cleanup() -> void:
	for f in [OLD, SAME]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	cleanup()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))

	# ---- the report, as data (scene_report.gd)
	var named := func(j: String) -> String: return m.nice(j)
	var A := scene3()
	ok(SceneReport.report(A, scene3(), named).is_empty(), "1 identical versions: no rows")
	var r2: Array = SceneReport.report(A, scene3(70.0), named)
	ok(r2.size() == 1 and r2[0]["kind"] == "joint" and r2[0]["joint"] == "lowerarm_r" and r2[0]["card"] == 2
		and "right elbow" in r2[0]["text"] and "10.0°" in r2[0]["text"] and absf(float(r2[0]["deg"]) - 10.0) < 1e-3,
		"2 one joint rotated 10 deg on card 3: %d row(s): %s" % [r2.size(), str(r2.map(func(r): return r["text"]))])
	var B3 := scene3()
	B3.add("intro", pose_dict(0, 0), 0)
	var r3: Array = SceneReport.report(A, B3, named)
	ok(r3.size() == 1 and r3[0]["kind"] == "added" and r3[0]["card"] == 0 and r3[0]["text"].begins_with("+ added    intro"),
		"3 a card inserted at the front: %d row(s), %s" % [r3.size(), str(r3.map(func(r): return r["text"]))])
	var r4: Array = SceneReport.report(A, scene3(60.0, 0.5), named)
	ok(r4.size() == 1 and r4[0]["kind"] == "timing" and "0.30 s -> 0.50 s" in r4[0]["text"],
		"4 hold 0.3 -> 0.5 s: %d row(s), %s" % [r4.size(), str(r4.map(func(r): return r["text"]))])
	var r5a: Array = SceneReport.report(A, scene3(60.3), named)
	var r5b: Array = SceneReport.report(A, scene3(60.7), named)
	ok(r5a.is_empty() and r5b.size() == 1, "5 0.3 deg: %d rows (none), 0.7 deg: %d row (one)" % [r5a.size(), r5b.size()])
	# two 30-card scenes: the time of the report alone (the scenes' times are read inside it, not warmed up)
	var P := Scene.new()
	var Q := Scene.new()
	for i in 30:
		P.add("c%d" % i, pose_dict(float(i % 40), float((i * 7) % 90)))
		Q.add("c%d" % i, pose_dict(float(i % 40), float((i * 7) % 90) + (10.0 if i == 14 else 0.0)))
	for c in P.cards:
		c["move"] = 0.4
	for c in Q.cards:
		c["move"] = 0.4
	var t0 := Time.get_ticks_usec()
	var rp: Array = SceneReport.report(P, Q, named)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	ok(ms < 200.0 and rp.size() == 1, "6 two 30-card scenes: %.2f ms, %d row (bar < 200 ms)" % [ms, rp.size()])

	# ---- the panel, on the window: the scene file must stay the same bytes
	m._new_scene()
	m.S.name = "_wip/zz_sdiff"
	m.S.cards = scene3().cards
	m._write(OLD, m._scene_dict())
	m._write(SAME, m._scene_dict())
	m.S.cards[2]["pose"] = pose_dict(40, 70)   # the open scene: card 3's elbow 10 deg more than the saved one
	m._refresh()
	await idle()
	var h_before := hash(FileAccess.get_file_as_bytes(OLD))
	var j_before := JSON.stringify(m._scene_dict(), "", true)
	m._sdiff_open([OLD])
	await idle(2)
	var n_rows: int = m.ui_sdiff_list.get_child_count()
	ok(m.ui_sdiff.visible and n_rows == 1 and "1 changes" in m.ui_sdiff_head.text and "right elbow" in (m.ui_sdiff_list.get_child(0) as Button).text,
		"7 the panel: %d row, head '%s'" % [n_rows, m.ui_sdiff_head.text])
	m._sdiff_jump(0)
	await idle(2)
	var tc := float(m.S.times()[2][1])
	ok(m.sel_card == 2 and m.sel == "lowerarm_r" and absf(m.playhead - tc) < 1e-3,
		"8 the row click: card %d, selected %s, playhead %.2f s (card 3 at %.2f s)" % [m.sel_card + 1, m.sel, m.playhead, tc])
	m.ui_sdiff_both.button_pressed = true   # Show both: the older card's pose ghosted over the open scene
	await idle(2)
	var ta := float(old_card3_time())
	ok(bool(m.vdiff.get("sdiff", false)) and absf(float(m.vdiff.get("ghost_t", -1.0)) - ta) < 1e-3 and m.ov._ghosts[5][0].visible,
		"9 show both: the ghost at the older card (%.2f s) is on: %s" % [ta, str(m.ov._ghosts[5][0].visible)])
	var old_scene := VersionDiff.load_scene(OLD)
	var fresh := Body.new()
	fresh.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	old_scene.apply(fresh, ta)
	var worst := 0.0
	for j in Body.ORDER:
		worst = maxf(worst, (m.ov.GB.ang[j] - fresh.ang[j]).length())
	ok(worst < 1e-6, "10 the ghost is the older card's pose, joint by joint: worst diff %s" % str(worst))
	m._sdiff_close()
	await idle()
	var same_bytes := hash(FileAccess.get_file_as_bytes(OLD)) == h_before and JSON.stringify(m._scene_dict(), "", true) == j_before
	ok(same_bytes, "11 the scene file's bytes and the open scene are the same after the report, a click and Show both")

	# identical: the open scene made the same as the saved one
	m.S.cards[2]["pose"] = pose_dict(40, 60)
	m._refresh()
	m._sdiff_open([SAME])
	await idle(2)
	ok(m.ui_sdiff_list.get_child_count() == 1 and "No changes" in m.ui_sdiff_head.text,
		"12 identical versions: '%s'" % m.ui_sdiff_head.text)

	# the screenshot: the open scene with the 10 deg change, the older card ghosted, whole body
	m.S.cards[2]["pose"] = pose_dict(40, 70)
	m._refresh()
	m._sdiff_open([OLD])
	await idle(2)
	m._sdiff_jump(0)
	m.ui_sdiff_both.button_pressed = true
	m._view_home(false)
	await idle(3)
	# 14 the ghost's material (it sits on the body's own surfaces: a z-fight unless it is grown and writes no depth)
	var gmats := []
	for gmi in m.ov._ghosts[5][0].find_children("*", "MeshInstance3D", true, false):
		gmats.append((gmi as MeshInstance3D).material_override)
	var g0 := gmats[0] as StandardMaterial3D if not gmats.is_empty() else null
	var all_same := g0 != null and gmats.all(func(x): return x == g0)
	ok(all_same and g0.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED and g0.grow and absf(g0.grow_amount - Overlays.VERSION_GROW) < 1e-9 and absf(g0.albedo_color.a - 0.35) < 1e-6,
		"14 the diff ghost: %d meshes, alpha %.2f, depth write off, grown %.3f m (want 0.35, off, 0.004)" % [gmats.size(), g0.albedo_color.a if g0 != null else -1.0, g0.grow_amount if g0 != null else -1.0])
	print("shot numbers: open scene lowerarm_r %s, ghost lowerarm_r %s, open hand_r P %s, ghost hand_r P %s, playhead %.2f" % [
		str(m.B.ang["lowerarm_r"]), str(m.ov.GB.ang["lowerarm_r"]), str(m.B.P["hand_r"]), str(m.ov.GB.P["hand_r"]), m.playhead])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("shot="):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(a.trim_prefix("shot="))
			print("shot saved: %s" % a.trim_prefix("shot="))
	m._sdiff_close()
	m._vdiff_clear()
	await idle()
	cleanup()
	var left := FileAccess.file_exists(OLD) or FileAccess.file_exists(SAME) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DIR))
	ok(not left, "13 everything it wrote in user:// removed (%s)" % left)
	print("SCENE_DIFF: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)


## the saved version's card-3 arrival time (its own timeline)
func old_card3_time() -> float:
	return float(VersionDiff.load_scene(OLD).times()[2][1])
