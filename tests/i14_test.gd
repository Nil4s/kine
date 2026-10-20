## godot --path . -s tests/i14_test.gd     (ROADMAP I14, rehearse against yourself; needs a window)
## A SYNTHETIC TAKE made from combo3 itself (a joint-angle sequence, no video): the strike's move is 0.08 s shorter (0.16 -> 0.08)
## and the pelvis twist is +20 deg on two cards (back coil, Nick load). DTW + event detection (scripts/rehearse.gd). BARS (stated
## before measuring):
##   1 the strike card: the move into it was 0.08 s faster, +-1 frame (0.033 s); the text says "faster"
##   2 the two hip cards: hip twist +20 deg +-3, and a "hip turned" line on each
##   3 NOTHING BIG ELSEWHERE: every other card has no joint line (< 8 deg) and |move delta| < 0.05 s
##   4 Use my timing: the clip's arrival of EVERY card is within 1 frame of the take's (the strike's reported); exactly ONE undo
##     step; Ctrl+Z restores the cards exactly (JSON); redo puts it back exactly
##   5 Use my pose on a hip card: that card's pelvis twist is the clip's +20 (+-3); ONE undo step; undo exact; no other card changes
##   6 the scene on disk is untouched: scenes/combo3.json md5 the same, scenes/_wip listing the same, the compare itself pushed no
##     undo step and changed no card
##   7 PLACEMENT: the comparison panel is on screen with a row per card and the Use my timing button, and the orange ghost is
##     visible, stands on the body's own spot (pelvis within 15 cm in plan) inside the view; screenshot saved
extends SceneTree

const TMP := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/"
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func cj(S: Scene) -> String:
	return JSON.stringify(S.cards)


func wip() -> Array:
	var out := []
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://scenes/_wip")):
		out = Array(DirAccess.get_files_at("res://scenes/_wip"))
	out.sort()
	return out


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	var md5_0 := FileAccess.get_md5("res://scenes/combo3.json")
	var wip0 := wip()
	m._load_scene("res://scenes/combo3.json")   # read only
	m._rebuild_cards()
	await idle()
	var S: Scene = m.S
	var fr := 1.0 / Rehearse.FPS
	var strike := -1
	for i in S.cards.size():
		if String(S.cards[i]["name"]).contains("STRIKE"):
			strike = i
	var hips := [4, 7]
	var T: Scene = S.clone()
	T.cards[strike]["move"] = snappedf(S.move_time(strike) - 0.08, 0.001)
	for k in hips:
		T.cards[k]["pose"]["joints"]["pelvis"]["twist"] = float(T.cards[k]["pose"]["joints"]["pelvis"]["twist"]) + 20.0
	print("     clip %.2f s, take %.2f s; strike = card %d (%s), move %.3f -> %.3f; hips on cards %s" % [S.length(), T.length(), strike + 1, S.cards[strike]["name"], S.move_time(strike), T.move_time(strike), hips])
	var cards0 := cj(S)
	var u0: int = m.undo.size()

	var t0 := Time.get_ticks_msec()
	var R: Dictionary = m._rehearse_compare(T, "synthetic take")
	await idle(2)
	print("     compare took %d ms" % (Time.get_ticks_msec() - t0))
	var C: Array = R["cards"]
	for c in C:
		print("     %2d %-22s clip %.3f take %.3f  move %+.3f  hip tw %+5.1f  | %s" % [int(c["i"]) + 1, c["name"], c["t_clip"], c["t_take"], c["move_delta"], (c["delta"]["pelvis"] as Vector3).z, c["text"]])

	# 1
	var sd: float = C[strike]["move_delta"]
	ok(absf(sd - (-0.08)) <= fr + 1e-6 and sd < 0.0 and String(C[strike]["text"]).contains("faster"), "1 the strike was %.3f s (bar -0.080 +-%.3f), text: %s" % [sd, fr, C[strike]["text"]])
	# 2
	for k in hips:
		var tw: float = (C[k]["delta"]["pelvis"] as Vector3).z
		var has := false
		for l in C[k]["lines"]:
			if String(l["text"]).contains("hip turned"):
				has = true
		ok(absf(tw - 20.0) <= 3.0 and has, "2 card %d hip twist %+.1f deg (bar +20 +-3), line: %s" % [k + 1, tw, C[k]["text"]])
	# 3
	var quiet := true
	var worst_t := 0.0
	var worst_j := 0.0
	for c in C:
		var i: int = c["i"]
		if hips.has(i) or i == strike:
			continue
		worst_t = maxf(worst_t, absf(float(c["move_delta"])))
		if not (c["lines"] as Array).is_empty():
			quiet = false
		for j in c["delta"]:
			worst_j = maxf(worst_j, (c["delta"][j] as Vector3).abs()[(c["delta"][j] as Vector3).abs().max_axis_index()])
	# the card after the strike and after a hip card carry the neighbour's change only through their own deltas
	ok(quiet and worst_t < 0.05, "3 nothing big elsewhere: worst other move delta %.3f s (bar < 0.05), worst other joint %.1f deg, no lines on them: %s" % [worst_t, worst_j, quiet])
	# 6 (part 1)
	ok(m.undo.size() == u0 and cj(S) == cards0, "6 the compare pushed no undo step and changed no card")

	# 7 PLACEMENT (the ghost at a moment the take is ahead of the clip)
	m.playhead = 3.0
	m._refresh()
	await idle(3)
	var panel: PanelContainer = m.ui_reh
	var rows := 0
	for q in S.cards.size():
		var rw: Node = panel.find_child("rehearse_row_%d" % q, true, false)
		if rw != null and (rw as Control).is_visible_in_tree():
			rows += 1
	var tbtn: Node = panel.find_child("rehearse_timing", true, false)
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var pr := panel.get_global_rect()
	var g: Array = m.ov._ghosts[6]
	var gb: int = g[2]["pelvis"]
	var gpos: Vector3 = (g[0] as Node3D).global_transform * (g[1] as Skeleton3D).get_bone_global_pose(gb).origin
	var bpos: Vector3 = m.B.P["pelvis"]
	var sp: Vector2 = m.cam.unproject_position(gpos)
	var off := Vector2(gpos.x - bpos.x, gpos.z - bpos.z).length()
	print("     ghost pelvis %s, body pelvis %s, panel %s, view %s" % [gpos, bpos, pr, vs])
	ok(panel.visible and rows == S.cards.size() and tbtn != null and pr.position.x >= 0 and pr.end.x <= vs.x and pr.end.y <= vs.y, "7 the panel is on screen with %d rows and the Use my timing button" % rows)
	ok((g[0] as Node3D).visible and off < 0.15 and sp.x > 0 and sp.x < vs.x and sp.y > 0 and sp.y < vs.y, "7 the orange ghost stands on the body's spot (%.1f cm off in plan), inside the view" % (off * 100.0))
	var img: Image = m.get_viewport().get_texture().get_image()
	img.save_png(TMP + "i14.png")
	print("     screenshot saved: ", TMP + "i14.png")

	# 4 USE MY TIMING
	var u1: int = m.undo.size()
	m._rehearse_timing()
	await idle(2)
	var after_t := cj(S)
	var ts := S.times()
	var tt := T.times()
	var worst := 0.0
	for i in S.cards.size():
		worst = maxf(worst, absf(float(ts[i][1]) - float(tt[i][1])))
	var sdiff := absf(float(ts[strike][1]) - float(tt[strike][1]))
	ok(worst <= fr + 1e-6, "4 after Use my timing every card arrives within a frame of the take: worst %.3f s (bar %.3f), the strike %.3f s off (clip %.3f, take %.3f)" % [worst, fr, sdiff, ts[strike][1], tt[strike][1]])
	ok(m.undo.size() - u1 == 1, "4 Use my timing is %d undo step (bar 1)" % (m.undo.size() - u1))
	m._undo()
	await idle(2)
	ok(cj(S) == cards0, "4 Ctrl+Z restores the cards exactly")
	m._redo()
	await idle(2)
	ok(cj(S) == after_t, "4 redo puts the timing back exactly")
	m._undo()
	await idle(2)
	ok(cj(S) == cards0, "4 and undone again, exactly")

	# 5 USE MY POSE (card 7 = Nick load)
	var k := 7
	var tw0: float = float(S.cards[k]["pose"]["joints"]["pelvis"]["twist"])
	var u2: int = m.undo.size()
	m._rehearse_pose(k)
	await idle(2)
	var tw1: float = float(S.cards[k]["pose"]["joints"]["pelvis"]["twist"])
	var others := true
	var c0: Array = JSON.parse_string(cards0)
	var c1: Array = JSON.parse_string(cj(S))
	for i in c0.size():
		if i != k and JSON.stringify(c0[i]) != JSON.stringify(c1[i]):
			others = false
	ok(absf((tw1 - tw0) - 20.0) <= 3.0 and others, "5 Use my pose on card %d: hip twist %.1f -> %.1f (bar +20 +-3), no other card changed: %s" % [k + 1, tw0, tw1, others])
	ok(m.undo.size() - u2 == 1, "5 Use my pose is %d undo step (bar 1)" % (m.undo.size() - u2))
	m._undo()
	await idle(2)
	ok(cj(S) == cards0, "5 Ctrl+Z restores the cards exactly")

	# 6 DISK
	ok(FileAccess.get_md5("res://scenes/combo3.json") == md5_0 and wip() == wip0, "6 scenes/combo3.json is byte-identical and scenes/_wip has no new file")
	print("I14 %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
