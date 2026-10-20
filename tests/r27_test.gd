## godot --path . -s tests/r27_test.gd     (R27; needs a window)
## NEXT-POSE SUGGESTIONS (Nick's idea; scripts/next_pose.gd, main.gd _sg_*). Ghost poses of what may come next after the current card.
## BARS (stated before measuring):
##  1 HABITS: a made-up set of scenes where pose A is followed by B five times and by C once: the habit source ranks B first with
##    count 5 and C second with count 1 (a query 1.5 deg off A still finds them); B's score is above C's; the tooltip text says
##    "seen 5 times"; the card B's timing (move 0.35, hold 0.1) comes with the suggestion.
##  2 INDEX CACHE (temp dir): refresh reads 6 files; a second NextPose on the same cache reads 0 (unchanged by modified time);
##    update_file on a new scene (A -> C) reads exactly 1 and C's count becomes 2; the cache file is only the test's own.
##  3 PHASE NAMES: "CONTACT" -> contact, "wind-up" -> windup, "follow-through" -> follow, "recover" -> recover, "ready" -> ready.
##  4 combo3 open at card 3 'CONTACT' (ANIMATE page): the list has 1..3 suggestions, the phase source is among them, labelled
##    "follow-through", and its pose comes from a card or library pose whose NAME reads follow-through; every suggestion has a tooltip
##    with its numbers; "real clip '...'" appears if the real-motion source answered.
##  5 NOTHING CHANGES: with the suggestions shown (and after Tab cycles them) the scene JSON is byte-identical, the undo list has
##    not grown and scenes/combo3.json on disk has the same md5 before and after.
##  6 ACCEPT: Tab to the phase suggestion, Enter: exactly one more undo step, one more card at index 3 whose pose is the suggestion's
##    pose, its move / hold the source's, the body shows it; Ctrl+Z restores the card list byte for byte and the same current card.
##    A click on a strip thumbnail does the same. Esc hides the ghosts and thumbnails; another card brings them back; the View toggle
##    off hides them and on shows them.
##  7 SPEED: np.suggest on combo3 card 3, 10 warm calls: mean under 30 ms (all three sources, real index, real motion database).
##  8 PLACEMENT (whole-body view, ANIMATE page): every ghost's head label and feet are inside the 3D view rectangle (between the left
##    and right panels, above the bottom panel), to the right of the hero's body on screen, with at least 90 px between two labels;
##    ghosts of different sources have different hues; the mini strip sits right after card 3 and on screen. Screenshot: tmp/r27.png.
extends SceneTree

var fails := 0
var m: Node
const TMP := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/"
var dir := "user://zz_r27_scenes_%d/" % OS.get_process_id()
var cache := "user://zz_r27_cache_%d.json" % OS.get_process_id()


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what + "   [%.0f s]" % (Time.get_ticks_msec() / 1000.0))
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func pose_of(angs: Dictionary) -> Dictionary:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	for j in angs:
		b.ang[j] = b.clamp_ang(j, angs[j])
	b.fk()
	return b.to_dict()


func write_scene(name: String, cards: Array) -> String:
	var path := dir + name + ".json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"fps": 30, "cards": cards}))
	f.close()
	return path


func key(code: Key, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.shift_pressed = shift
	m._unhandled_input(e)
	await process_frame


func shown_ghosts() -> int:
	var n := 0
	for g in m.ov._sg:
		if (g.node as Node3D).visible:
			n += 1
	return n


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var A := {"upperarm_r": Vector3(60, 0, 0), "thigh_l": Vector3(30, 0, 0), "spine_02": Vector3(10, 0, 0)}
	var Bp := {"upperarm_r": Vector3(-40, 20, 0), "lowerarm_r": Vector3(90, 0, 0), "spine_03": Vector3(0, 25, 0)}
	var Cp := {"thigh_r": Vector3(50, 0, 0), "calf_r": Vector3(80, 0, 0), "upperarm_l": Vector3(80, 30, 0)}
	var pa := pose_of(A)
	var pb := pose_of(Bp)
	var pc := pose_of(Cp)
	for i in 5:
		write_scene("ab_%d" % i, [{"name": "A", "pose": pa, "move": -1.0, "hold": 0.3}, {"name": "B", "pose": pb, "move": 0.35, "hold": 0.1}])
	write_scene("ac_0", [{"name": "A", "pose": pa, "move": -1.0, "hold": 0.3}, {"name": "C", "pose": pc, "move": 0.5, "hold": 0.2}])
	var np := NextPose.new()
	np.dirs = [dir]
	np.cache_path = cache
	var n_read := np.refresh()
	var A2 := A.duplicate()
	A2["upperarm_r"] = Vector3(61.5, 0, 0)
	var qp := pose_of(A2)
	var qk := np.key_of(NextPose.full_of_pose(qp))
	var hb: Array = np.habits(qk, Vector3.ZERO)
	var bk := np.key_of(NextPose.full_of_pose(pb))
	var ck := np.key_of(NextPose.full_of_pose(pc))
	ok(hb.size() == 2 and np.kdist(np.key_of(hb[0]["full"]), 0, bk, 0) < 0.5 and int(hb[0]["count"]) == 5 and np.kdist(np.key_of(hb[1]["full"]), 0, ck, 0) < 0.5 and int(hb[1]["count"]) == 1,
		"1 habits: B first (count %d), C second (count %d); scores %.2f > %.2f" % [hb[0]["count"], hb[1]["count"], hb[0]["score"], hb[1]["score"]])
	ok(float(hb[0]["score"]) > float(hb[1]["score"]) and String(hb[0]["tip"]).begins_with("seen 5 times after a pose like this") and is_equal_approx(float(hb[0]["mv"]), 0.35) and is_equal_approx(float(hb[0]["hd"]), 0.1),
		"1b tooltip '%s'; timing from the source: move %.2f hold %.2f (bar 0.35 / 0.1)" % [hb[0]["tip"], hb[0]["mv"], hb[0]["hd"]])
	var sg := np.suggest(qp, "A", 0.4)
	ok(sg.size() >= 1 and sg[0]["src"] == "habit" and np.kdist(np.key_of(sg[0]["full"]), 0, bk, 0) < 0.5, "1c suggest(): the first of %d is the habit B" % sg.size())
	# 2 the cache
	var np2 := NextPose.new()
	np2.dirs = [dir]
	np2.cache_path = cache
	var n2 := np2.refresh()
	ok(n_read == 6 and n2 == 0 and np2.pair_count() == 6, "2 index: first refresh read %d files (bar 6), a second NextPose on the cache read %d (bar 0), pairs %d" % [n_read, n2, np2.pair_count()])
	var p7 := write_scene("ac_1", [{"name": "A", "pose": pa, "move": -1.0, "hold": 0.3}, {"name": "C", "pose": pc, "move": 0.5, "hold": 0.2}])
	np2.update_file(p7)
	var hb2: Array = np2.habits(qk, Vector3.ZERO)
	var cnt_c := 0
	for h in hb2:
		if np2.kdist(np2.key_of(h["full"]), 0, ck, 0) < 0.5:
			cnt_c = int(h["count"])
	ok(np2.reparsed == 1 and cnt_c == 2 and np2.pair_count() == 7, "2b update_file read %d file (bar 1): C now counted %d times (bar 2), pairs %d" % [np2.reparsed, cnt_c, np2.pair_count()])
	ok(NextPose.phase_of("CONTACT") == "contact" and NextPose.phase_of("wind-up") == "windup" and NextPose.phase_of("follow-through") == "follow" and NextPose.phase_of("recover") == "recover" and NextPose.phase_of("ready") == "ready" and NextPose.phase_of("Nick overhead") == "",
		"3 phase names read: CONTACT, wind-up, follow-through, recover, ready, and 'Nick overhead' reads as none")

	# the app
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._page_set("ANIMATE", false)
	await idle(3)
	var md5_before := FileAccess.get_md5("res://scenes/combo3.json")
	var t_db := Time.get_ticks_msec()
	var db := MotionMatch.build(["res://scenes/"])
	print("     motion database: %d frames from %d clips, built in %.1f s" % [db["n"], (db["clips"] as Array).size(), (Time.get_ticks_msec() - t_db) / 1000.0])
	m.np.set_motion(db)
	m.np.refresh()
	m.sg_on = true
	m.dist = 6.4   # the whole body (and the ghosts beside it) in the frame
	m._cam()
	var json0 := JSON.stringify(m._scene_dict())
	var cards0 := JSON.stringify(m.S.cards)
	var undo0: int = m.undo.size()
	m._card_pick(2)   # card 3, 'CONTACT'
	undo0 = m.undo.size()
	await idle(4)
	var names := []
	var srcs := []
	for s in m.sg_list:
		names.append("%s/%s" % [s["src"], s["name"]])
		srcs.append(s["src"])
	print("     suggestions at card 3 '%s': %s" % [m.S.cards[2]["name"], str(names)])
	for s in m.sg_list:
		print("       %s | %s | score %.2f" % [s["label"], s["tip"], s["score"]])
	var cp: Dictionary = m.S.cards[2]["pose"]
	var qk3: PackedFloat32Array = m.np.key_of(NextPose.full_of_pose(cp))
	var phs: Array = m.np.phase(qk3, Vector3.ZERO, "CONTACT", m.scene_path)
	var ph: Dictionary = phs[0] if not phs.is_empty() else {}
	var in_list := false   # the phase pose is in the list, as its own ghost or merged with another source's
	for s in m.sg_list:
		if s["src"] == "phase" or (s.get("also", []) as Array).has("phase"):
			in_list = true
	ok(m.sg_list.size() >= 1 and m.sg_list.size() <= 3 and not ph.is_empty() and ph["label"] == "follow-through" and String(ph["name"]).to_lower().contains("follow") and in_list,
		"4 combo3 card 3 CONTACT: %d suggestions %s; phase source: '%s' named '%s' (%s); in the list: %s" % [m.sg_list.size(), str(srcs), ph.get("label", "none"), ph.get("name", ""), ph.get("from", ""), in_list])
	var tips_ok := true
	for s in m.sg_list:
		tips_ok = tips_ok and String(s["tip"]).length() > 20 and (not (s["src"] == "motion") or String(s["tip"]).begins_with("real clip '"))
	ok(tips_ok and shown_ghosts() == m.sg_list.size() and m._sg_strip != null and m._sg_strip.find_children("sg_*", "Button", true, false).size() == m.sg_list.size(),
		"4b every suggestion has its numbers in the tooltip; ghosts shown %d, strip thumbnails %d" % [shown_ghosts(), m._sg_strip.find_children("sg_*", "Button", true, false).size() if m._sg_strip != null else -1])
	# 5 nothing changes while shown and cycled
	await key(KEY_TAB)
	await key(KEY_TAB)
	var after_tab: int = m.sg_sel
	ok(JSON.stringify(m._scene_dict()) == json0 and JSON.stringify(m.S.cards) == cards0 and m.undo.size() == undo0 and FileAccess.get_md5("res://scenes/combo3.json") == md5_before and after_tab == (1 % m.sg_list.size()),
		"5 shown and cycled (Tab twice -> pick %d): scene JSON identical %s, cards identical %s, undo steps %d -> %d, file md5 same %s" % [after_tab,
		JSON.stringify(m._scene_dict()) == json0, JSON.stringify(m.S.cards) == cards0, undo0, m.undo.size(), FileAccess.get_md5("res://scenes/combo3.json") == md5_before])
	# 7 speed (warm)
	var tot := 0.0
	var worst := 0.0
	for r in 10:
		m.np.suggest(m.S.cards[2]["pose"], "CONTACT", 0.15, m.scene_path)
		tot += m.np.last_ms
		worst = maxf(worst, m.np.last_ms)
	ok(tot / 10.0 < 30.0, "7 speed: np.suggest on combo3 card 3 (index %d cards, %d frames): mean %.1f ms, worst %.1f ms (bar mean < 30); the first show took %.1f ms" % [m.np.card_count(), m.np.db.get("n", 0), tot / 10.0, worst, m.sg_ms])
	# 8 placement + screenshot (before the accept changes the cards)
	m.sg_sel = -1
	m._sg_place()
	m._sg_strip_sync()
	await idle(14)
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var view := Rect2(m.lw(), m.TOP_H, vp.x - m.lw() - m.rw(), vp.y - m.TOP_H - m.bottom_h)
	var cam: Camera3D = m.cam
	var body_r := -INF
	for j in ["head", "hand_l", "hand_r", "foot_l", "foot_r", "pelvis"]:
		body_r = maxf(body_r, cam.unproject_position(m.B.P[j]).x)
	var inside := true
	var gx := []
	var hues := []
	var left_min := INF
	for i in m.sg_list.size():
		var lp: Vector3 = m.ov.sugg_spot(i)
		var sp := cam.unproject_position(lp)
		gx.append(sp.x)
		inside = inside and view.grow(-8).has_point(sp)
		var node: Node3D = m.ov._sg[i].node
		var sk: Skeleton3D = m.ov._sg[i].sk
		for jn in ["foot_l", "foot_r", "head", "hand_l", "hand_r"]:
			var bi: int = m.ov._sg[i].idx[jn]
			var wp: Vector3 = node.global_transform * sk.get_bone_global_pose(bi).origin
			var q := cam.unproject_position(wp)
			inside = inside and view.grow(-8).has_point(q)
			left_min = minf(left_min, q.x)
		hues.append((m.ov._sg[i].mat.albedo_color as Color).h)
	var gap_ok := true
	for i in range(1, gx.size()):
		gap_ok = gap_ok and absf(gx[i] - gx[i - 1]) >= 90.0
	var hue_ok := true
	for i in hues.size():
		for k in range(i + 1, hues.size()):
			if m.sg_list[i]["src"] != m.sg_list[k]["src"]:
				hue_ok = hue_ok and absf(hues[i] - hues[k]) > 0.05
	var strip_ok: bool = m._sg_strip != null and m._sg_strip.get_index() == m.ui_cards.get_node("card_3").get_index() + 1 and m._sg_strip.is_visible_in_tree() and Rect2(Vector2.ZERO, vp).encloses(m._sg_strip.get_global_rect())
	ok(inside and left_min > body_r - 12.0 and gap_ok and hue_ok and strip_ok,
		"8 placement: ghosts inside the view %s (rect %s), left edge %.0f px vs the body's right %.0f, label x %s (gaps >= 90: %s), hues %s distinct %s, strip right after card 3 and on screen %s" % [
		inside, str(view), left_min, body_r, str(gx), gap_ok, str(hues), hue_ok, strip_ok])
	img_save()
	# 6 accept with Enter
	await key(KEY_ESCAPE)
	ok(shown_ghosts() == 0 and m.sg_list.is_empty() and m._sg_strip == null, "6a Esc hides the ghosts (%d) and the thumbnails" % shown_ghosts())
	m._card_pick(2)
	await idle(3)
	ok(m.sg_list.size() >= 1 and shown_ghosts() == m.sg_list.size(), "6b picking the card again brings them back (%d)" % m.sg_list.size())
	var pi := 0
	for i in m.sg_list.size():
		if m.sg_list[i]["src"] == "phase":
			pi = i
	var want: Dictionary = m.sg_list[pi]
	var want_pose := JSON.stringify(want["pose"])
	cards0 = JSON.stringify(m.S.cards)
	undo0 = m.undo.size()
	var n_cards: int = m.S.cards.size()
	while m.sg_sel != pi:
		await key(KEY_TAB)
	await key(KEY_ENTER)
	await idle(3)
	var nc: Dictionary = m.S.cards[3]
	ok(m.undo.size() == undo0 + 1 and m.S.cards.size() == n_cards + 1 and JSON.stringify(nc["pose"]) == want_pose and is_equal_approx(float(nc["move"]), float(want["mv"])) and is_equal_approx(float(nc["hold"]), float(want["hd"])) and m.sel_card == 3,
		"6 accept: undo steps +%d (bar 1), cards %d -> %d, new card 4 '%s' pose == suggestion %s, move %.2f hold %.2f (source %.2f / %.2f)" % [
		m.undo.size() - undo0, n_cards, m.S.cards.size(), nc["name"], JSON.stringify(nc["pose"]) == want_pose, nc["move"], nc["hold"], want["mv"], want["hd"]])
	m._undo()
	await idle(3)
	ok(JSON.stringify(m.S.cards) == cards0 and m.undo.size() == undo0 and m.sel_card == 2, "6c Ctrl+Z: card list byte-identical %s, undo steps back to %d, current card %d (bar 3)" % [JSON.stringify(m.S.cards) == cards0, m.undo.size(), m.sel_card + 1])
	m._card_pick(2)
	await idle(3)
	undo0 = m.undo.size()
	cards0 = JSON.stringify(m.S.cards)
	var b1: Button = m._sg_strip.find_child("sg_1", true, false)
	b1.pressed.emit()
	await idle(3)
	ok(m.undo.size() == undo0 + 1 and m.S.cards.size() == n_cards + 1, "6d clicking thumbnail 1: undo steps +%d, cards %d" % [m.undo.size() - undo0, m.S.cards.size()])
	m._undo()
	await idle(3)
	ok(JSON.stringify(m.S.cards) == cards0, "6e Ctrl+Z after the click restores the cards")
	m._card_pick(2)
	await idle(3)
	m._sg_toggle()
	await idle(2)
	var off_ok: bool = shown_ghosts() == 0 and m.sg_list.is_empty()
	m._sg_toggle()
	await idle(3)
	ok(off_ok and shown_ghosts() == m.sg_list.size() and m.sg_list.size() >= 1, "6f View toggle: off hides (%s), on shows %d again" % [off_ok, shown_ghosts()])
	ok(FileAccess.get_md5("res://scenes/combo3.json") == md5_before, "9 scenes/combo3.json untouched on disk")
	# clean up the temp files
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + f))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cache))
	print("R27: %d failed" % fails)
	quit(1 if fails > 0 else 0)


func img_save() -> void:
	var img: Image = m.get_viewport().get_texture().get_image()
	img.save_png(TMP + "r27.png")
