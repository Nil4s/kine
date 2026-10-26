## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/r16_test.gd     (ROADMAP R16; a window: the picker is drawn)
## HIT REACTION PICKER (scripts/reaction_picker.gd). Two fighters as in choreo_test: the hero plays combo3 (read only), fighter 2
## stands still D0 in front of him. The sample clips are written to scenes/_wip/reactions. Bars, written before measuring:
##   1 LIST: the picker lists >= 3 clips; each has 3 thumbnail frames that are three DIFFERENT poses and every row shows a picture;
##     the labels are read off the clips: head_snap hits the "head", bat_to_torso the "arm", knock_down FELL and the others stayed up.
##   2 DROP: dropping bat_to_torso at fighter 2's place in the view puts its cards on fighter 2: the first reaction card's MOVE STARTS within
##     1 frame (1/30 s) of the contact time the test's own 1/240 s sweep finds (the bat's first touch), and fighter 2's reaction cards are
##     the clip's cards (poses and moves equal, in order).
##   3 ATTACKER: the hero's scene is byte-identical (JSON) after the drop; fighter 2's cards before the contact are unchanged.
##   4 UNDO: one undo step for the drop; Ctrl+Z restores both scenes exactly (JSON equal to before), redo puts the reaction back.
##   5 FALL: knock_down dropped the same way: fighter 2's head at the end of the reaction is under half its standing height
##     (the body is down), and one undo restores both scenes exactly (floor rule too).
##   6 PLACEMENT: the panel is whole inside the window, no fighter's on-screen pelvis / head / foot is under it, a thumbnail
##     shows a figure (the pixels that differ from its background span >= 50 % of its height) and the picture is saved.
extends SceneTree

var fails := 0
var m: Node
const D0 := 1.2
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/r16.png"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


func still(pose: Dictionary) -> Scene:
	var s := Scene.new()
	s.from_dict({"scene": "zz_still", "fps": 30, "cards": [{"name": "a", "pose": pose, "move": -1.0, "hold": 2.0},
		{"name": "b", "pose": pose, "move": 0.5, "hold": 3.0}]})
	return s


func stand_pose() -> Dictionary:
	var b := body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b.to_dict()


func strike_t(hs: Scene, fs: Scene, xf: Transform3D) -> float:
	var a := hs.clone()
	var o := fs.clone()
	var ba := body()
	var bo := body()
	var n := int(ceil(maxf(a.length(), o.length()) * 240.0))
	for i in n + 1:
		var t := i / 240.0
		a.apply(ba, t)
		o.apply(bo, t)
		for c in ba.cross_contacts(bo, xf):
			if c[3] == "hit":
				return t
	return -1.0


func sj(s: Scene) -> String:
	var d := s.to_dict(body())
	d.erase("actors")   # the hero's file embeds the other fighters: compare this fighter alone
	return JSON.stringify(d)


func screen_of(k: int, j: String) -> Vector2:
	var W: Vector3 = m._stage_xf() * (m.actors_rt[k]["xf"] as Transform3D) * ((m.actors_rt[k]["B"] as Body).P[j] as Vector3)
	return m.cam.unproject_position(W)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m._load_scene("res://scenes/combo3.json")   # read only
	m._rebuild_cards()
	await idle()
	var stand := stand_pose()
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, D0], "yaw": 180.0}, "scene": still(stand)})
	m._actors_sync()
	m._page_set("STAGE", false)
	m._refresh()
	await idle()
	var hs: Scene = m.actors_rt[0]["S"]
	var fs: Scene = m.actors_rt[1]["S"]
	var t_sweep := strike_t(hs, fs, m.actors_rt[1]["xf"])
	ok(m.actors_rt.size() == 2 and t_sweep > 0.0, "two fighters; the sweep finds the bat's first touch of fighter 2 at %.4f s" % t_sweep)

	# 1 LIST
	m._reactions_toggle()
	await idle(3)
	var pk: ReactionPicker = m.ui_reactions
	for i in 40:
		if pk.pictures() == pk.clips.size():
			break
		await idle(3)
	var names := pk.clips.map(func(c): return c["name"])
	var distinct := true
	for c in pk.clips:
		var keys := (c["info"]["poses"] as Array).map(func(p): return SceneThumbs.pose_key(p))
		if keys.size() != 3 or keys[0] == keys[1] or keys[1] == keys[2] or keys[0] == keys[2]:
			distinct = false
	var by := {}
	for c in pk.clips:
		by[c["name"]] = c["info"]
	ok(pk.visible and pk.clips.size() >= 3 and distinct and pk.pictures() == pk.clips.size(),
		"1 the picker lists %d clips %s, three different frames each (%s), pictures on %d rows" % [pk.clips.size(), names, distinct, pk.pictures()])
	for n in by:
		print("     %-14s %s  (%.2f s)" % [n, by[n]["label"], by[n]["length"]])
	ok(by.has("head_snap") and by.has("bat_to_torso") and by.has("knock_down") and by["head_snap"]["where"] == "head" and by["bat_to_torso"]["where"] == "arm"
		and by["knock_down"]["fell"] and not by["head_snap"]["fell"] and not by["bat_to_torso"]["fell"],
		"1 labels read off the clips: head_snap -> head, bat_to_torso -> arm (the recoil runs through the gripped arms of the real hit_react cards), knock_down fell, the others stayed up")

	# 2 DROP
	var path_bat := "res://scenes/_wip/reactions/bat_to_torso.json"
	var clip := ReactionPicker.load_clip(path_bat)
	var hero0 := sj(hs)
	var f0 := sj(fs)
	var cards0: Array = fs.cards.duplicate(true)
	var u0: int = m.undo.size()
	var mp := screen_of(1, "pelvis")
	ok(m._reaction_drop(path_bat, mp), "2 dropped at fighter 2's place on screen (%.0f, %.0f)" % [mp.x, mp.y])
	await idle(2)
	var vs: Scene = m.actors_rt[1]["S"]
	var ts := vs.times()
	var first := -1
	for i in vs.cards.size():
		if str((vs.cards[i] as Dictionary).get("name", "")) == str(clip.cards[0]["name"]):
			first = i
			break
	var arr: float = float(ts[first][0]) if first >= 0 else -9.0
	ok(first >= 0 and absf(arr - t_sweep) <= 1.0 / 30.0 + 1e-9,
		"2 the first reaction card starts moving at %.4f s; the contact (sweep) is %.4f s: %.1f ms apart (bar one frame, 33.3 ms)" % [arr, t_sweep, absf(arr - t_sweep) * 1000.0])
	var same := first >= 0 and first + clip.cards.size() <= vs.cards.size()
	for i in range(1, clip.cards.size()):
		same = same and JSON.stringify(vs.cards[first + i]["pose"]) == JSON.stringify(clip.cards[i]["pose"]) and is_equal_approx(float(vs.cards[first + i]["move"]), float(clip.cards[i]["move"]))
	same = same and first >= 0 and JSON.stringify(vs.cards[first]["pose"]) == JSON.stringify(clip.cards[0]["pose"])
	ok(same, "2 fighter 2's %d reaction cards are the clip's cards, poses and moves equal, in order" % clip.cards.size())

	# 3 ATTACKER
	var before_ok := true
	for i in first:
		before_ok = before_ok and JSON.stringify(vs.cards[i]["pose"]) == JSON.stringify(cards0[i]["pose"])
	ok(sj(m.actors_rt[0]["S"]) == hero0 and before_ok and vs.cards.size() != cards0.size(),
		"3 the attacker's scene is byte-identical (%d chars); fighter 2's %d cards before the contact keep their poses; its cards %d -> %d" % [hero0.length(), first, cards0.size(), vs.cards.size()])

	# 4 UNDO
	var steps: int = m.undo.size() - u0
	var after := sj(vs)
	m._undo()
	await idle()
	ok(steps == 1 and sj(m.actors_rt[1]["S"]) == f0 and sj(m.actors_rt[0]["S"]) == hero0,
		"4 one undo step (%d); Ctrl+Z restores fighter 2 exactly (%s) and the hero (%s)" % [steps, sj(m.actors_rt[1]["S"]) == f0, sj(m.actors_rt[0]["S"]) == hero0])
	m._redo()
	await idle()
	ok(sj(m.actors_rt[1]["S"]) == after, "4 redo puts the reaction back exactly")
	m._undo()
	await idle()

	# 5 FALL
	var path_dn := "res://scenes/_wip/reactions/knock_down.json"
	var f1 := sj(m.actors_rt[1]["S"])
	var h1 := sj(m.actors_rt[0]["S"])
	var up := body()
	m.actors_rt[1]["S"].apply(up, 0.5)
	var stand_h: float = (up.P["head"] as Vector3).y
	ok(m._reaction_drop(path_dn, screen_of(1, "pelvis")), "5 knock_down dropped on fighter 2")
	await idle(2)
	var S2: Scene = m.actors_rt[1]["S"]
	var bd := body()
	S2.apply(bd, S2.length() - 0.01)
	var hd: float = (bd.P["head"] as Vector3).y
	ok(hd < 0.5 * stand_h and S2.floor_body, "5 fighter 2's head ends at %.2f m (standing %.2f m, bar under half) with the floor rule for a lying body %s" % [hd, stand_h, S2.floor_body])
	# the picture, at the moment the fighter is going down, seen from the side with both fighters in it
	m._view(2)
	m.dist = 5.5
	m.target = Vector3(0, 0.8, -0.6)
	var t_show: float = float(S2.times()[S2.cards.size() - 2][1]) - 0.05
	m.playhead = t_show
	m.playing = false
	m._ps().apply(m.B, t_show)
	m._refresh()
	await idle(3)
	await RenderingServer.frame_post_draw
	print("     shown at %.2f s: active actor %d, pelvis bend %.1f, pelvis y %.2f, head y %.2f" % [m.playhead, m.actor_on, m.B.ang["pelvis"].x, m.B.P["pelvis"].y, m.B.P["head"].y])
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var rect := Rect2(pk.global_position, pk.size)
	var clear := Rect2(Vector2.ZERO, vp).encloses(rect)
	var bodies_clear := true
	for k in 2:
		for j in ["pelvis", "head", "foot_l"]:
			if rect.has_point(screen_of(k, j)):
				bodies_clear = false
	var pic: Image = (pk.clips[0]["pic"] as TextureRect).texture.get_image()
	var bgc := pic.get_pixel(1, 1)
	var y0 := pic.get_height()
	var y1 := -1
	for y in pic.get_height():
		for x in pic.get_width():
			if not pic.get_pixel(x, y).is_equal_approx(bgc):
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	var frac := float(y1 - y0 + 1) / float(pic.get_height())
	ok(clear and bodies_clear and frac >= 0.5, "6 placement: panel %s inside the %s window %s, no fighter under it %s, thumbnail figure spans %.0f %% of its height (bar 50 %%)" % [rect, vp, clear, bodies_clear, frac * 100.0])
	DirAccess.make_dir_recursive_absolute(SHOT.get_base_dir())
	var img: Image = m.get_viewport().get_texture().get_image()
	ok(img.save_png(SHOT) == OK, "6 picture saved: %s" % SHOT)
	m._undo()
	await idle()
	ok(sj(m.actors_rt[1]["S"]) == f1 and sj(m.actors_rt[0]["S"]) == h1, "5 one undo puts fighter 2 back exactly (floor rule too) and the hero is unchanged")
	print("R16 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
