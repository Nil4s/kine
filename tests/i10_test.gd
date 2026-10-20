## godot --path . -s tests/i10_test.gd     (I10; needs a window)
## YOUR MOVES LEARN YOU (ROADMAP I10): the R27 habits index (scripts/next_pose.gd) also learns Nick's TIMING and favourite in-betweens.
## Synthetic scenes only (a temp dir under user://); the real user:// index and scenes/ are never written.
## BARS (stated before measuring):
##  1 ALWAYS 0.18: scenes where pose A -> pose B is always move 0.18 / hold 0.07, and A -> C always 0.50 / 0.20 (the poses are
##    >= 13 deg apart by NextPose.kdist, printed): usual(A, B') (B' = B moved 1.5 deg) = move 0.18, hold 0.07, n >= 2; usual(A, C) = 0.50.
##    A pose Z far from every learned one (> T_MAXD from all): usual = {} (no guess).
##  2 IN THE APP (usual_on): scene [A]; Clip with the body at B -> card 2 has move 0.18, hold 0.07, the strip says "your usual 0.18 s",
##    in the card_usual colour (not the plain one). Touch it (move 0.5): the text is the plain timing and the colour override is gone.
##    Clip with the body at Z: move -1.0, hold 0.3 (the app's default), no tag, the text is the plain "~..." form.
##    Clip = ONE undo step; Ctrl+Z restores the scene JSON byte for byte. Duplicate on card 1 (pose A after A): no learned pair that near,
##    so the copy keeps the original's timing and carries no tag.
##  3 U: select the touched card, press U: exactly one more undo step, move 0.18, hold 0.07, tagged; Ctrl+Z restores the scene JSON.
##    U on a card with no usual (the Z card): says why, no undo step, nothing changes. A two-card range takes the usual on the card that has one.
##  4 IN-BETWEEN: scenes A -> X -> C three times (X: move 0.20, hold 0.05): with [A, C] open and card 1 current, the ghost list has a
##    "your usual in-between" ghost (count 3) whose pose is X (kdist < 1), timing 0.20 / 0.05; taking it = ONE undo step, a card between A and C
##    whose strip text is "your usual 0.2 s"; Ctrl+Z restores the JSON. With the same pair seen only twice (poses D, E, F): no such ghost.
##  5 INCREMENTAL: a second NextPose on the first one's cache reads 0 files; update_file of ONE new scene (Z -> W four times at 0.33)
##    reads exactly 1 (reparsed == 1) and usual(Z, W) goes from {} to 0.33.
##  6 NO REAL INDEX: the app's np.cache_path is a zz_ file (not user://next_pose_index.json), and the real index's modified time is
##    the same before and after (or it never existed).
##  7 PLACEMENT (whole-body view, ANIMATE page, screenshot tmp/i10.png): with the scene [P, A(usual), C] and card 2 current, the in-between
##    ghost is on screen (head, feet and hands inside the 3D view), to the right of the hero, its label reads "your usual in-between", and the strip
##    shows the "your usual 0.18 s" card with the next-pose strip right after the current card.
extends SceneTree

var fails := 0
var m: Node
const TMP := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/"
var dir := "user://zz_i10_scenes_%d/" % OS.get_process_id()
var cache := "user://zz_i10_cache_%d.json" % OS.get_process_id()
var open_path := "user://zz_i10_open_%d.json" % OS.get_process_id()


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what + "   [%.0f s]" % (Time.get_ticks_msec() / 1000.0))
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


## pose number n: ~14 joints at large, n-specific angles, so two different n are far apart by NextPose.kdist
func pose_n(n: int, nudge := 0.0) -> Dictionary:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + n
	for j in NextPose.KEYJ:
		b.ang[j] = b.clamp_ang(j, Vector3(rng.randf_range(-75.0, 75.0), rng.randf_range(-40.0, 40.0), rng.randf_range(-30.0, 30.0)))
	if nudge != 0.0:
		b.ang["upperarm_r"] = b.clamp_ang("upperarm_r", (b.ang["upperarm_r"] as Vector3) + Vector3(nudge, 0, 0))
	b.fk()
	return b.to_dict()


func timing_btn(n: int) -> Button:
	var c: Node = m.ui_cards.get_node_or_null("card_%d" % n)
	return c.find_child("b_timing", true, false) as Button if c != null else null


func card(nm: String, pose: Dictionary, mv: float, hd: float) -> Dictionary:
	return {"name": nm, "pose": pose, "move": mv, "hold": hd}


func write_to(path: String, cards: Array) -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"fps": 30, "cards": cards}))
	f.close()
	return path


func write_scene(name: String, cards: Array) -> String:
	return write_to(dir + name + ".json", cards)


func key(code: Key, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	m._unhandled_input(e)
	await process_frame


func close_to(a: Dictionary, b: Dictionary, np: NextPose) -> float:
	return np.kdist(np.key_of(NextPose.full_of_pose(a)), 0, np.key_of(NextPose.full_of_pose(b)), 0)


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var real_mt := FileAccess.get_modified_time(NextPose.CACHE) if FileAccess.file_exists(NextPose.CACHE) else -1
	var pa := pose_n(1)
	var pb := pose_n(2)
	var pc := pose_n(3)
	var px := pose_n(4)
	var pz := pose_n(5)
	var pw := pose_n(6)
	var pp := pose_n(7)
	var pd := pose_n(8)
	var pe := pose_n(9)
	var pf := pose_n(10)
	# the learned scenes
	for i in 5:
		write_scene("ab_%d" % i, [card("A", pa, -1.0, 0.3), card("B", pb, 0.18, 0.07)])
	for i in 3:
		write_scene("ac_%d" % i, [card("A", pa, -1.0, 0.3), card("C", pc, 0.5, 0.2)])
	for i in 3:
		write_scene("axc_%d" % i, [card("P", pp, -1.0, 0.3), card("A", pa, 0.18, 0.07), card("X", px, 0.2, 0.05), card("C", pc, 0.4, 0.1)])
	for i in 2:
		write_scene("def_%d" % i, [card("D", pd, -1.0, 0.3), card("E", pe, 0.25, 0.05), card("F", pf, 0.35, 0.1)])
	var np := NextPose.new()
	np.dirs = [dir]
	np.cache_path = cache
	var n_read := np.refresh()
	var dmin := INF
	var all := [pa, pb, pc, px, pz, pw, pp, pd, pe, pf]
	for i in all.size():
		for j in range(i + 1, all.size()):
			dmin = minf(dmin, close_to(all[i], all[j], np))
	print("     %d scene files read, %d cards, nearest two of the 10 test poses are %.1f deg apart (bar >= 13, past T_MAXD 10)" % [n_read, np.card_count(), dmin])
	ok(dmin >= 13.0, "0 the synthetic poses are far apart (min %.1f deg, bar 13: past the T_MAXD of 10): the bars below can tell them apart" % dmin)
	# 1 usual
	var u_ab := np.usual(pa, pose_n(2, 1.5), "B")
	var u_ac := np.usual(pa, pc, "C")
	var u_z := np.usual(pa, pz, "Z")
	var u_far := np.usual(pz, pb, "B")   # the new card is B but the card before is far from every learned A
	ok(not u_ab.is_empty() and is_equal_approx(float(u_ab["mv"]), 0.18) and is_equal_approx(float(u_ab["hd"]), 0.07) and int(u_ab["n"]) >= 2,
		"1 usual(A, B+1.5 deg) = move %s hold %s from %s transitions (bar 0.18 / 0.07, n >= 2)" % [u_ab.get("mv"), u_ab.get("hd"), u_ab.get("n")])
	ok(not u_ac.is_empty() and is_equal_approx(float(u_ac["mv"]), 0.5) and is_equal_approx(float(u_ac["hd"]), 0.2),
		"1b usual(A, C) = move %s hold %s (bar 0.50 / 0.20: the pair decides, not one global time)" % [u_ac.get("mv"), u_ac.get("hd")])
	ok(u_z.is_empty() and u_far.is_empty(), "1c a pose far from every learned one (Z after A; B after Z): no guess (%s, %s)" % [str(u_z), str(u_far)])

	# the app
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	m.np.dirs = [dir]
	m.np.cache_path = cache
	m.np.refresh()
	m.usual_on = true
	m.sg_on = false
	write_to(open_path, [card("A", pa, -1.0, 0.3)])
	m._load_scene(open_path)
	m._rebuild_cards()
	m._page_set("ANIMATE", false)
	await idle(3)
	m.sel_card = 0
	var json0 := JSON.stringify(m._scene_dict())
	var undo0: int = m.undo.size()
	Scene.put(m.B, Moves._flat(pose_n(2, 1.5)))
	m._card_add()
	await idle(3)
	var c1: Dictionary = m.S.cards[1]
	var tb := timing_btn(2)
	ok(m.S.cards.size() == 2 and is_equal_approx(float(c1["move"]), 0.18) and is_equal_approx(float(c1["hold"]), 0.07) and m.undo.size() == undo0 + 1,
		"2 Clip at B after A: card 2 move %.3f hold %.3f (bar 0.18 / 0.07), undo steps +%d (bar 1)" % [c1["move"], c1["hold"], m.undo.size() - undo0])
	var col_ok: bool = tb != null and tb.has_theme_color_override("font_color") and tb.get_theme_color("font_color").is_equal_approx(Tok.c("card_usual"))
	ok(tb != null and tb.text == "your usual 0.18 s" and col_ok, "2b the strip card says '%s' in the card_usual colour: %s (bar: 'your usual 0.18 s', coloured)" % [tb.text if tb != null else "(no button)", col_ok])
	m._undo()
	await idle(2)
	ok(JSON.stringify(m._scene_dict()) == json0 and m.S.cards.size() == 1, "2c Ctrl+Z restores the scene JSON byte for byte (%d cards)" % m.S.cards.size())
	m._redo()
	await idle(2)
	# touch it
	m.sel_card = 1
	m._push_undo()
	m.S.cards[1]["move"] = 0.5
	m._rebuild_cards()
	await idle(2)
	tb = timing_btn(2)
	ok(tb != null and not tb.text.begins_with("your usual") and not tb.has_theme_color_override("font_color") and not m._card_is_usual(m.S.cards[1]),
		"2d touched (move 0.5): the strip says '%s', the usual colour is gone" % [tb.text if tb != null else "(no button)"])
	# a pose far from everything
	m.sel_card = 1
	Scene.put(m.B, Moves._flat(pz))
	var undo1: int = m.undo.size()
	m._card_add()
	await idle(2)
	var cz: Dictionary = m.S.cards[2]
	ok(is_equal_approx(float(cz["move"]), -1.0) and is_equal_approx(float(cz["hold"]), 0.3) and not cz.has("usual") and m.undo.size() == undo1 + 1,
		"2e Clip at Z (far from everything learned): move %.2f hold %.2f, no tag (bar: the app's default -1 / 0.3), undo +%d" % [cz["move"], cz["hold"], m.undo.size() - undo1])
	# duplicate card 1 (A after A): the copy keeps the original timing, no learned pair that near
	var cnt_before: int = m.S.cards.size()
	var json_d := JSON.stringify(m._scene_dict())
	m.sel_card = 0
	m._card_duplicate(0)
	await idle(2)
	ok(m.S.cards.size() == cnt_before + 1 and not m.S.cards[1].has("usual") and is_equal_approx(float(m.S.cards[1]["hold"]), 0.3),
		"2f Duplicate card 1: %d -> %d cards, the copy keeps the original's timing (hold %.2f) and carries no tag (no pair A->A learned)" % [cnt_before, m.S.cards.size(), m.S.cards[1]["hold"]])
	m._undo()
	await idle(2)
	ok(JSON.stringify(m._scene_dict()) == json_d, "2g Ctrl+Z after Duplicate restores the scene JSON")

	# 3 U
	m.sel_card = 1
	m.sel_end = -1
	m.msel = []
	var json3 := JSON.stringify(m._scene_dict())
	var undo3: int = m.undo.size()
	await key(KEY_U)
	var c1b: Dictionary = m.S.cards[1]
	ok(is_equal_approx(float(c1b["move"]), 0.18) and is_equal_approx(float(c1b["hold"]), 0.07) and m._card_is_usual(c1b) and m.undo.size() == undo3 + 1,
		"3 U on the touched card: move %.3f hold %.3f tagged %s, undo +%d (bar 0.18 / 0.07, tagged, +1)" % [c1b["move"], c1b["hold"], m._card_is_usual(c1b), m.undo.size() - undo3])
	m._undo()
	await idle(2)
	ok(JSON.stringify(m._scene_dict()) == json3, "3b Ctrl+Z after U restores the scene JSON byte for byte")
	m.sel_card = 2   # the Z card: no usual
	var json3c := JSON.stringify(m._scene_dict())
	var undo3c: int = m.undo.size()
	await key(KEY_U)
	ok(m.undo.size() == undo3c and JSON.stringify(m._scene_dict()) == json3c, "3c U on the Z card (nothing learned near it): no undo step, nothing changed")
	m.sel_card = 1
	m.sel_end = 2
	m._range_of = 1
	var undo3d: int = m.undo.size()
	await key(KEY_U)
	ok(m.undo.size() == undo3d + 1 and is_equal_approx(float(m.S.cards[1]["move"]), 0.18) and is_equal_approx(float(m.S.cards[2]["move"]), -1.0),
		"3d U on the range 2..3: ONE undo step (+%d), card 2 takes 0.18, card 3 (no usual) keeps its timing %.2f" % [m.undo.size() - undo3d, m.S.cards[2]["move"]])
	m.sel_end = -1

	# 4 in-between
	write_to(open_path, [card("A", pa, -1.0, 0.3), card("C", pc, 0.5, 0.2)])
	m._load_scene(open_path)
	m._rebuild_cards()
	m._page_set("ANIMATE", false)
	m.sg_on = true
	m.dist = 6.4
	m._cam()
	m._card_pick(0)
	await idle(4)
	var bt: Dictionary = {}
	var srcs := []
	for s in m.sg_list:
		srcs.append(s["src"])
		if s["src"] == "between":
			bt = s
	var x_ok := not bt.is_empty() and np.kdist(np.key_of(bt["full"]), 0, np.key_of(NextPose.full_of_pose(px)), 0) < 1.0
	ok(not bt.is_empty() and bt["label"] == "your usual in-between" and int(bt["count"]) == 3 and x_ok and is_equal_approx(float(bt["mv"]), 0.2) and is_equal_approx(float(bt["hd"]), 0.05),
		"4 between A and C: ghosts %s; in-between count %s, timing %s / %s, is X: %s (bar count 3, 0.20 / 0.05)" % [str(srcs), bt.get("count"), bt.get("mv"), bt.get("hd"), x_ok])
	var json4 := JSON.stringify(m._scene_dict())
	var undo4: int = m.undo.size()
	var bi := srcs.find("between")
	if bi >= 0:
		m._sg_accept(bi)
	await idle(3)
	var tb4 := timing_btn(2)
	ok(m.S.cards.size() == 3 and m.undo.size() == undo4 + 1 and tb4 != null and tb4.text == "your usual 0.2 s",
		"4b taking it: %d cards, undo +%d, strip text '%s' (bar 3 cards, +1, 'your usual 0.2 s')" % [m.S.cards.size(), m.undo.size() - undo4, tb4.text if tb4 != null else "(none)"])
	m._undo()
	await idle(2)
	ok(JSON.stringify(m._scene_dict()) == json4, "4c Ctrl+Z restores the scene JSON byte for byte")
	# only twice: D -> F open, E was used twice
	write_to(open_path, [card("D", pd, -1.0, 0.3), card("F", pf, 0.35, 0.1)])
	m._load_scene(open_path)
	m._rebuild_cards()
	m._page_set("ANIMATE", false)
	m._card_pick(0)
	await idle(4)
	var any_between := false
	for s in m.sg_list:
		any_between = any_between or s["src"] == "between"
	ok(not any_between and m.np.between(pd, pf, Vector3.ZERO).is_empty(), "4d D -> E -> F seen only 2 times: no in-between offered (ghosts %s)" % str(m.sg_list.map(func(s): return s["src"])))

	# 5 incremental
	var np2 := NextPose.new()
	np2.dirs = [dir]
	np2.cache_path = cache
	var n2 := np2.refresh()
	var before := np2.usual(pz, pw, "W")
	var zw := write_scene("zw_0", [card("Z", pz, -1.0, 0.3), card("W", pw, 0.33, 0.1), card("Z", pz, 0.33, 0.1), card("W", pw, 0.33, 0.1), card("Z", pz, 0.33, 0.1)])
	np2.update_file(zw)
	var after := np2.usual(pz, pw, "W")
	ok(n2 == 0 and np2.reparsed == 1 and before.is_empty() and not after.is_empty() and is_equal_approx(float(after.get("mv", 0.0)), 0.33),
		"5 a second NextPose on the cache read %d files (bar 0); update_file of one new scene read %d (bar 1); usual(Z, W) %s -> %s (bar {} -> 0.33)" % [n2, np2.reparsed, str(before), after.get("mv")])

	# 6 no real index
	var real_mt2 := FileAccess.get_modified_time(NextPose.CACHE) if FileAccess.file_exists(NextPose.CACHE) else -1
	ok(String(m.np.cache_path) != NextPose.CACHE and String(m.np.cache_path).contains("zz_") and real_mt == real_mt2,
		"6 the app's index is '%s' (a test's own); the real index's modified time %d -> %d (bar unchanged)" % [m.np.cache_path, real_mt, real_mt2])

	# 7 placement + screenshot: [P, C] open, Clip A after P (usual 0.18), card 2 current with C after it
	write_to(open_path, [card("P", pp, -1.0, 0.3), card("C", pc, 0.5, 0.2)])
	m._load_scene(open_path)
	m._rebuild_cards()
	m._page_set("ANIMATE", false)
	m.sel_card = 0
	Scene.put(m.B, Moves._flat(pa))
	m._card_add()
	m.dist = 6.4
	m._cam()
	m._card_pick(1)
	await idle(14)
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var view := Rect2(m.lw(), m.TOP_H, vp.x - m.lw() - m.rw(), vp.y - m.TOP_H - m.bottom_h)
	var cam: Camera3D = m.cam
	var bi7 := -1
	for i in m.sg_list.size():
		if m.sg_list[i]["src"] == "between":
			bi7 = i
	var inside := bi7 >= 0
	var right_ok := false
	var label := ""
	if bi7 >= 0:
		var node: Node3D = m.ov._sg[bi7].node
		var sk: Skeleton3D = m.ov._sg[bi7].sk
		var body_r := -INF
		for j in ["head", "hand_l", "hand_r", "foot_l", "foot_r", "pelvis"]:
			body_r = maxf(body_r, cam.unproject_position(m.B.P[j]).x)
		var left_min := INF
		for jn in ["foot_l", "foot_r", "head", "hand_l", "hand_r"]:
			var wp: Vector3 = node.global_transform * sk.get_bone_global_pose(m.ov._sg[bi7].idx[jn]).origin
			var q := cam.unproject_position(wp)
			inside = inside and view.grow(-8).has_point(q)
			left_min = minf(left_min, q.x)
		right_ok = left_min > body_r
		label = String(m.sg_list[bi7]["label"])
	var tb7 := timing_btn(2)
	var strip_after: bool = m._sg_strip != null and m._sg_strip.get_index() == m.ui_cards.get_node("card_2").get_index() + 1
	ok(inside and right_ok and label == "your usual in-between" and tb7 != null and tb7.text == "your usual 0.18 s" and strip_after,
		"7 placement: the in-between ghost '%s' is inside the 3D view: %s, right of the hero: %s; card 2 reads '%s'; the next-pose strip follows it: %s" % [
		label, inside, right_ok, tb7.text if tb7 != null else "(none)", strip_after])
	var img: Image = m.get_viewport().get_texture().get_image()
	img.save_png(TMP + "i10.png")

	m.queue_free()
	await idle(2)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cache))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(open_path))
	print("I10: %d failed" % fails)
	quit(1 if fails > 0 else 0)
