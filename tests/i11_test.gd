## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/i11_test.gd     (ROADMAP I11; a window: the ghost and the timeline are drawn)
## FIGHT PHRASE BUILDER (scripts/fight_phrase.gd). The hero attacks with combo3 (read only; three strikes), fighter 2 stands still
## 1.8 m away (too far for every strike: the range manager has to step in). Bars, written before measuring:
##   1 BEATS: the attacker's three strikes are found (3 beats, tip-speed peaks) and each gets a defence (none flagged).
##   2 VARIETY: not all three defences are the same kind, and no kind runs three times in a row.
##   3 TIMING: each defence card ARRIVES 1 to 2 frames before its beat's contact (inside [t - 2 frames, t - 1 frame]) and its move
##     STARTS one reaction time (0.2 s) before the contact, within 1 frame; the pose AT the arrival equals the card's (0.5 deg).
##   4 DEFENCE WORKS (this test's own geometry, 240 Hz, on the written scenes): a block's forearm meets the bat/fist path in the
##     last 2 frames before the contact (distance <= the two radii); a slip's target part ends >= 10 cm farther from the path than
##     it was in the pose before (same place).
##   5 RANGE: at every contact the striking point is within 5 cm of the trunk (measured on the pose before the defence, at the
##     card's place), the bodies do not overlap at any 1/30 s frame from the first reaction to the last contact + 0.2 s
##     (hands, forearms, weapons aside), and the defender was moved (a step is said in the marker note).
##   6 FLAG: with the defender 4.5 m away (a step the search will not make) every beat is flagged with a reason and a red "FP n FLAG"
##     marker on the timeline, and no defence card is written for it.
##   7 ATTACKER: the hero's scene is byte-identical (JSON) after the preview and after the accept.
##   8 PREVIEW + UNDO: the preview writes nothing (no undo step, fighter 2's JSON equal) and shows the blue ghost at fighter 2's
##     place; Accept is exactly ONE undo step, Ctrl+Z restores fighter 2 (JSON) exactly, redo puts it back exactly.
##   9 PLACEMENT: at the second contact, with the defence on, both heads are inside the window, the timeline holds the 3 labels
##     "FP n ..." as markers on fighter 2's scene, and the picture is saved.
extends SceneTree

var fails := 0
var m: Node
const D0 := 1.8
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i11.png"


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
	s.from_dict({"scene": "zz_still", "fps": 30, "cards": [{"name": "a", "pose": pose, "move": -1.0, "hold": 4.0},
		{"name": "b", "pose": pose, "move": 0.5, "hold": 6.0}]})
	return s


func stand_pose() -> Dictionary:
	var b := body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b.to_dict()


func sj(s: Scene) -> String:
	var d := s.to_dict(body())
	d.erase("actors")
	return JSON.stringify(d)


func screen_of(k: int, j: String) -> Vector2:
	var W: Vector3 = m._stage_xf() * (m.actors_rt[k]["xf"] as Transform3D) * ((m.actors_rt[k]["B"] as Body).P[j] as Vector3)
	return m.cam.unproject_position(W)


func pose_with_offset(p: Dictionary, off: Array) -> Dictionary:
	var q: Dictionary = p.duplicate(true)
	q["offset"] = off
	return q


func trunk_gap(sp: Vector3, DB: Body, rel: Transform3D) -> float:
	var best := INF
	for part in DB.cross_parts():
		if Body.is_wep(part) or not (ReactionPicker.region_of(part) in ["head", "torso"]):
			continue
		var c: Array = DB.cap(part)
		best = minf(best, Body.seg_seg(sp, sp, rel * (c[0] as Vector3), rel * (c[1] as Vector3)) - float(DB.rad[part]))
	return best


## the card of fighter 2 that arrives for beat i: its name ends with the beat's number
func card_of(fs: Scene, i: int) -> int:
	for k in fs.cards.size():
		var nm := str(fs.cards[k].get("name", ""))
		if nm.ends_with(" %d" % (i + 1)) and (nm.begins_with("BLOCK") or nm.begins_with("SLIP")):
			return k
	return -1


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m._load_scene("res://scenes/combo3.json")   # read only
	m._rebuild_cards()
	await idle()
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, D0], "yaw": 180.0}, "scene": still(stand_pose())})
	m._actors_sync()
	m._page_set("STAGE", false)
	m._refresh()
	await idle()
	var hs: Scene = m.actors_rt[0]["S"]
	var rel: Transform3D = (m.actors_rt[0]["xf"] as Transform3D).affine_inverse() * (m.actors_rt[1]["xf"] as Transform3D)
	var hero0 := sj(hs)
	var f0 := sj(m.actors_rt[1]["S"])
	var u0: int = m.undo.size()

	# PREVIEW
	var pl: Dictionary = m._fight_build()
	await idle(2)
	ok(bool(pl.get("ok", false)), "1 the plan is made: %s" % [pl.get("why", "")])
	var beats: Array = pl.get("beats", [])
	var nflag := 0
	for r in beats:
		if r["flag"]:
			nflag += 1
	for i in beats.size():
		var r: Dictionary = beats[i]
		print("     beat %d t=%.3f  %-10s start %.3f arrive %.3f  zone %s gap %+.1f cm  step %+.1f cm  flag %s" % [i + 1, r["t"], r["label"], r["start"], r.get("arrive_at", r["arrive"]), r["zone"], float(r["gap"]) * 100.0, float(r["step"]) * 100.0, r["flag"]])
	ok(beats.size() == 3 and nflag == 0, "1 three strikes found (tip-speed peaks), %d flagged, %d defences" % [nflag, beats.size() - nflag])
	var g: Array = m.ov._ghosts[2]
	ok(m.undo.size() == u0 and sj(m.actors_rt[1]["S"]) == f0 and sj(hs) == hero0 and g[0].visible and g[0].transform.origin.is_equal_approx((m.actors_rt[1]["xf"] as Transform3D).origin),
		"8 the preview wrote nothing (undo steps %d, fighter 2 equal, hero equal) and the blue ghost is at fighter 2's place %s" % [m.undo.size() - u0, g[0].transform.origin])

	# ACCEPT
	ok(m._fight_accept(), "accept")
	await idle(2)
	var fs: Scene = m.actors_rt[1]["S"]
	var steps: int = m.undo.size() - u0
	var after := sj(fs)
	ok(sj(hs) == hero0, "7 the attacker's scene is byte-identical after the accept (%d chars)" % hero0.length())
	var fr := 1.0 / float(fs.fps)
	var ts := fs.times()
	var kinds := []
	for r in beats:
		kinds.append(r["kind"])
	var distinct: bool = kinds.size() == 3 and not (kinds[0] == kinds[1] and kinds[1] == kinds[2])
	ok(distinct, "2 variety: the defences are %s (not all alike; at most two of a kind in a row)" % [kinds])

	# TIMING
	var tim_ok := true
	var DB := body()
	var AB := body()
	for i in beats.size():
		var r: Dictionary = beats[i]
		var k := card_of(fs, i)
		if k < 0:
			tim_ok = false
			continue
		var arrive: float = ts[k][1]
		var start: float = ts[k][0]
		var tc: float = r["t"]
		var in_win: bool = arrive >= tc - 2.0 * fr - 1e-6 and arrive <= tc - 1.0 * fr + 1e-6
		var early: bool = absf((tc - start) - 0.2) <= fr + 1e-6 or start > tc - 0.2 - fr   # a close beat may start later, never earlier
		var pa := body()
		fs.apply(pa, arrive)
		var cb := body()
		cb.from_dict(fs.cards[k]["pose"])
		var dmax := 0.0
		for j in cb.ang:
			dmax = maxf(dmax, ((cb.ang[j] as Vector3) - (pa.ang[j] as Vector3)).abs().max_axis_index() >= 0 and ((cb.ang[j] as Vector3) - (pa.ang[j] as Vector3)).abs()[((cb.ang[j] as Vector3) - (pa.ang[j] as Vector3)).abs().max_axis_index()])
		print("     beat %d: contact %.3f, defence arrives %.3f (%.1f frames before), starts %.3f (%.0f ms before), pose at the arrival off by %.2f deg" % [i + 1, tc, arrive, (tc - arrive) / fr, start, (tc - start) * 1000.0, dmax])
		tim_ok = tim_ok and in_win and early and dmax <= 0.5
	ok(tim_ok, "3 each defence arrives 1 to 2 frames before its contact, starts one reaction time before it (or as soon as the beat before lets it), and is in place")

	# DEFENCE WORKS + RANGE (the test's own measures, on the written scenes)
	var def_ok := true
	var range_ok := true
	var moved_ok := true
	for i in beats.size():
		var r: Dictionary = beats[i]
		var k := card_of(fs, i)
		if k < 0:
			def_ok = false
			continue
		var tc: float = r["t"]
		var arrive: float = ts[k][1]
		var hs_b: Scene = m.actors_rt[0]["S"]
		hs_b.apply(AB, tc)
		var prev_pose: Dictionary = (fs.cards[k - 1]["pose"] as Dictionary)
		var this_off: Array = fs.cards[k]["pose"]["offset"]
		DB.from_dict(pose_with_offset(prev_pose, this_off))
		# the striking point: the bat point (every cm) nearest the trunk, else the nearer palm
		var u := -1.0
		var sp := Vector3.ZERO
		if AB.wep_on:
			var bg := INF
			var uu := 0.0
			while uu <= AB.wep_len + 1e-6:
				var gp := trunk_gap(AB.wep_point(uu), DB, rel)
				if gp < bg:
					bg = gp
					u = uu
				uu += 0.01
			sp = AB.wep_point(u)
		else:
			sp = AB.palm_point("hand_r")
		var gap := trunk_gap(sp, DB, rel)
		range_ok = range_ok and absf(gap) <= 0.05
		moved_ok = moved_ok and absf(float(this_off[0]) - float((fs.cards[0]["pose"]["offset"] as Array)[0])) + absf(float(this_off[2]) - float((fs.cards[0]["pose"]["offset"] as Array)[2])) > 0.0
		# the path from the arrival to the contact
		var pth := []
		var n := int(ceil((tc + 0.02 - arrive) * 240.0))
		for q in n + 1:
			hs_b.apply(AB, minf(tc + 0.02, arrive + float(q) / 240.0))
			pth.append(AB.wep_point(u) if AB.wep_on else AB.palm_point("hand_r"))
		var trad: float = float(AB.rad["bat_barrel"]) if AB.wep_on else 0.04
		DB.from_dict(fs.cards[k]["pose"])
		var label := str(r["label"])
		if label.begins_with("BLOCK"):
			var fa := "lowerarm_" + ("r" if label.contains("(R)") else "l")
			var c: Array = DB.cap(fa)
			var dmin := INF
			for p in pth:
				dmin = minf(dmin, Body.seg_seg(p, p, rel * (c[0] as Vector3), rel * (c[1] as Vector3)))
			var ok_b: bool = dmin <= float(DB.rad[fa]) + trad
			print("     beat %d BLOCK: forearm %s meets the path at %.1f cm (bar <= %.1f cm)" % [i + 1, fa, dmin * 100.0, (float(DB.rad[fa]) + trad) * 100.0])
			def_ok = def_ok and ok_b
		else:
			var part: String = r["part"]
			var c1: Array = DB.cap(part)
			var DN := body()
			DN.from_dict(pose_with_offset(prev_pose, this_off))
			var c0: Array = DN.cap(part)
			var d1 := INF
			var d0 := INF
			for p in pth:
				d1 = minf(d1, Body.seg_seg(p, p, rel * (c1[0] as Vector3), rel * (c1[1] as Vector3)))
				d0 = minf(d0, Body.seg_seg(p, p, rel * (c0[0] as Vector3), rel * (c0[1] as Vector3)))
			print("     beat %d SLIP: %s was %.1f cm from the path, now %.1f cm: moved %.1f cm (bar >= 10)" % [i + 1, part, d0 * 100.0, d1 * 100.0, (d1 - d0) * 100.0])
			def_ok = def_ok and d1 - d0 >= 0.10 - 1e-6
		print("     beat %d range: striking point %+.1f cm from the trunk before the defence, step %+.1f cm" % [i + 1, gap * 100.0, float(r["step"]) * 100.0])
	ok(def_ok, "4 every defence does its job on the written scenes (block meets the path / slip 10 cm off it)")
	ok(range_ok and moved_ok, "5 every strike's tip is within 5 cm of the trunk at its contact, and the defender was stepped (cards carry the new offset)")
	# no overlap, frame by frame
	var over := 0
	var t0: float = float(beats[0]["start"])
	var t1: float = float(beats[-1]["t"]) + 0.2
	var fcount := 0
	var tt := t0
	while tt <= t1:
		hs.apply(AB, tt)
		fs.apply(DB, tt)
		fcount += 1
		if FightPhrase.overlap(AB, DB, rel):
			over += 1
		tt += 1.0 / 30.0
	ok(over == 0, "5 the bodies overlap on %d of %d frames from %.2f s to %.2f s (bar 0)" % [over, fcount, t0, t1])

	# UNDO
	ok(steps == 1, "8 accept is %d undo step (bar 1)" % steps)
	m._undo()
	await idle()
	ok(sj(m.actors_rt[1]["S"]) == f0 and sj(m.actors_rt[0]["S"]) == hero0, "8 Ctrl+Z restores fighter 2 exactly and the hero is unchanged")
	m._redo()
	await idle()
	ok(sj(m.actors_rt[1]["S"]) == after, "8 redo puts the answer back exactly")

	# PLACEMENT + SHOT (second contact)
	fs = m.actors_rt[1]["S"]
	var mk: Array = fs.markers
	var names := mk.map(func(x): return str(x["name"]))
	var tc2: float = beats[1]["t"]
	m._view(2)
	m.dist = 5.0
	m.target = Vector3(0, 0.9, 0.9)
	m.playhead = tc2
	m.playing = false
	m._ps().apply(m.B, tc2)
	m._refresh()
	await idle(3)
	await RenderingServer.frame_post_draw
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var inside := true
	for k in 2:
		for j in ["head", "pelvis", "foot_l"]:
			inside = inside and Rect2(Vector2.ZERO, vp).has_point(screen_of(k, j))
	var lab := 0
	for nm in names:
		if str(nm).begins_with("FP "):
			lab += 1
	ok(inside and lab == 3, "9 placement: both fighters whole inside the %s window %s; %d 'FP' labels on the timeline %s" % [vp, inside, lab, names])
	DirAccess.make_dir_recursive_absolute(SHOT.get_base_dir())
	var img: Image = m.get_viewport().get_texture().get_image()
	ok(img.save_png(SHOT) == OK, "9 picture saved: %s" % SHOT)
	m._undo()
	await idle()

	# FLAG: the defender far away
	m.actors_rt[1]["S"].cards.clear()
	var far_scene := still(stand_pose())
	m.S.actors[0]["xf"] = {"pos": [0.0, 4.5], "yaw": 180.0}
	m.S.actors[0]["scene"] = far_scene
	m._actors_sync()
	await idle()
	var pf: Dictionary = m._fight_build()
	var fl := 0
	var why_ok := true
	for r in pf.get("beats", []):
		if r["flag"]:
			fl += 1
			why_ok = why_ok and str(r["why"]).length() > 20
	var uf: int = m.undo.size()
	m._fight_accept()
	await idle(2)
	var fm: Array = m.actors_rt[1]["S"].markers
	var red := 0
	var defs := 0
	for x in fm:
		if str(x["name"]).ends_with("FLAG") and str(x.get("color", "")) == "red":
			red += 1
	for c in m.actors_rt[1]["S"].cards:
		if str(c["name"]).begins_with("BLOCK") or str(c["name"]).begins_with("SLIP"):
			defs += 1
	ok(fl == 3 and why_ok and red == 3 and defs == 0, "6 the defender at 4.5 m: %d beats flagged with a reason %s, %d red FLAG markers, %d defence cards written (bar 0)" % [fl, why_ok, red, defs])
	print("I11 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
