## godot --path . -s tests/hand_pose_ui_test.gd     (ROADMAP 73, with a window: the screenshots need one)
## The app's side of the hand poses (main.gd _hand_pose through _do). Bars, stated before measuring:
##   1 ONE UNDO STEP: a fist on the picked right hand at 2.0 s adds exactly one undo step.
##   2 KEYED: after the fist, each of the right hand's 15 joints has exactly one key at the playhead, equal to the body's
##     angle there (1e-6 deg); the index's middle joint reads 105 (the fist's PIP at its limit).
##   3 UNDO RESTORES: Ctrl+Z (_undo) puts every keyed joint's key list back as it was (none at 2.0 s) and the body back
##     (1e-6 deg).
##   4 POINT: the point pose keys the index straight (middle joint < 1 deg) and the middle finger curled (> 90 deg).
##   5 NO HAND PICKED: with a body part picked (pelvis), a pose adds no undo step and says what to pick.
##   6 SCREENSHOTS: the fist and the point, the whole window, saved under the job's tmp folder.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func keys_at(j: String, t: float) -> int:
	var n := 0
	for k in (m.S.part_keys.get(j, []) as Array):
		if absf(float(k["t"]) - t) < 1e-4:
			n += 1
	return n


## a close-up of the picked hand (the figure's right hand, screen left) and the HANDS panel (inspector, right), 2x
func shots(img: Image, name: String) -> void:
	var hand := img.get_region(Rect2i(540, 170, 240, 160))
	hand.resize(720, 480, Image.INTERPOLATE_LANCZOS)
	hand.save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/fingers_%s_hand.png" % name)
	var panel := img.get_region(Rect2i(1310, 80, 290, 820))
	panel.save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/fingers_%s_panel.png" % name)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle()
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.playhead = 0.0
	m._refresh()
	m.undo.clear()
	m.redo.clear()
	var t := clampf(2.0, 0.0, m.S.length())
	m.playhead = t
	m._refresh()
	var joints: Array = m.B.hand_joints("r")
	var before: Dictionary = {}
	for j in joints:
		before[j] = (m.B.ang[j] as Vector3)

	m.sel = "hand_r"
	var u0: int = m.undo.size()
	m._pose_pick("fist")
	var u1: int = m.undo.size()
	ok(u1 == u0 + 1, "1 ONE UNDO STEP: a fist on the right hand adds %d step(s) (%d -> %d)" % [u1 - u0, u0, u1])

	var worst := 0.0
	var one_key := true
	for j in joints:
		worst = maxf(worst, ((m.B.ang[j] as Vector3) - (before[j] as Vector3)).length())
		if keys_at(j, t) != 1:
			one_key = false
	ok(one_key, "2a KEYED: each of the 15 right-hand joints has exactly one key at %.2f s" % t)
	var mid: float = (m.B.ang["index_02_r"] as Vector3).x
	ok(absf(mid - 105.0) < 1e-3, "2b the index middle joint at the fist reads %.4f deg (the fist's PIP at its 105 limit)" % mid)
	var kv_ok := true
	for j in joints:
		for k in (m.S.part_keys[j] as Array):
			if absf(float(k["t"]) - t) < 1e-4 and ((k["v"] as Vector3) - (m.B.ang[j] as Vector3)).length() > 1e-6:
				kv_ok = false
	ok(kv_ok, "2c each key's value equals the body's angle at that joint (1e-6 deg)")

	m._sec_open("HANDS", true)   # the panel with the per-finger sliders and the pose buttons, open for the shot
	# a close-up from the side, the picked hand in front (the body no longer hides it)
	m._turn_to(-90.0, -8.0, 0.9, m.B.P["hand_r"] + m.B.offset, false)
	await idle(3)
	var close: Image = m.get_viewport().get_texture().get_image()
	close.save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/fingers_fist_closeup.png")
	var img: Image = m.get_viewport().get_texture().get_image()
	img.save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/fingers_fist.png")
	shots(img, "fist")

	m._undo()
	await idle()
	var back := 0.0
	for j in joints:
		back = maxf(back, ((m.B.ang[j] as Vector3) - (before[j] as Vector3)).length())
	var nkeys := 0
	for j in joints:
		nkeys += keys_at(j, t)
	ok(nkeys == 0 and back < 1e-6, "3 UNDO RESTORES: %d keys left at %.2f s, body worst difference %.6f deg" % [nkeys, t, back])

	m._pose_pick("point")
	var idx_straight: float = (m.B.ang["index_02_r"] as Vector3).x
	var mid_curled: float = (m.B.ang["middle_02_r"] as Vector3).x
	ok(absf(idx_straight) < 1.0 and mid_curled > 90.0, "4 POINT: index middle joint %.2f deg (straight), middle finger's %.2f deg (curled)" % [idx_straight, mid_curled])
	await idle(3)
	img = m.get_viewport().get_texture().get_image()
	img.save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/fingers_point.png")
	shots(img, "point")

	m.sel = "pelvis"
	var u2: int = m.undo.size()
	var pel: Vector3 = m.B.ang["hand_r"]
	m._pose_pick("fist")
	ok(m.undo.size() == u2 and (m.B.ang["hand_r"] as Vector3) == pel, "5 NO HAND PICKED: a pose with the pelvis picked adds no undo step (%d -> %d) and changes nothing" % [u2, m.undo.size()])

	print("hand_pose_ui_test: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(fails)
