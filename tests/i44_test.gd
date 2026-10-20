## godot --path . -s tests/i44_test.gd     (ROADMAP I44: next beat for two fighters, scripts/next_beat.gd + next_beat_ui.gd; needs a window)
## SYNTHETIC 2-FIGHTER SCENE from real poses (poses/stand.json and a right arm swung to the farthest forward reach, as i19): the hero throws four
## punches 0.8 s apart, fighter 2 blocks each 0.3 s later (4 blocks), the playhead stands at 4.0 s inside fighter 2's last hold. Nick's combos are
## injected (one mined answer: block > cross, rhythm 0.15 / 0.18 s with a 0.02 s hold, 3 times in 2 clips). Bars, written before measuring:
##  (1) the TOP suggestion is fighter 2 ANSWERING (who 1, kind answer), its why names "blocked 4 times running", the cross, "0.20 s" (hold 0.02 +
##      move 0.18 = what the combo says) and "3 times in 2 clips"; the ranked list has >= 2 entries in descending score order
##  (2) OUT OF RANGE: fighter 2 moved to 2.2 m: the top suggestion is "close" (a step in); after inserting it the gap to the other fighter shrank
##      by the step (+-3 cm) and no strike is offered while out of range
##  (3) INSERT lands on the RIGHT fighter at the playhead: fighter 2's first new card starts at the playhead (+-1 ms), the hero's cards are
##      byte-identical, ONE undo step (undo.size() +1), the active fighter is fighter 2, and Ctrl+Z restores both fighters' cards exactly
##  (4) SPEED + CACHE: a suggestion set takes < 150 ms (fatigue, the inverse-dynamics part, is read once per revision of the cards and timed apart);
##      a second tick on the same scene and playhead works out nothing again (computes unchanged); an edit or a new playhead does
##  (5) JOURNAL (I26): accepting logs source "next beat" / kind answer (offers 1); an undo then counts it REJECTED
##  (6) PLACEMENT: after Tab the blue ghost stands on FIGHTER 2 (its origin at his xf, not at the hero's), the ranked panel is inside the view, one
##      row per suggestion each with a why; the screenshot is taken on that view (tmp/i44.png)
extends SceneTree

var fails := 0
var m: Node
var stand: Dictionary
var punch_r: Dictionary
var punch_l: Dictionary
const MV := 0.15


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func make_poses() -> void:
	var b := DistanceKeeper.new_body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	stand = b.to_dict()
	b.fk()
	var h0: Vector3 = b.P["hand_r"]
	var best := 0.0
	var best_a := Vector3.ZERO
	for ax in range(-180, 181, 30):
		for ay in range(-60, 61, 30):
			for az in range(-60, 61, 30):
				var a := Vector3(ax, ay, az)
				b.from_dict(stand)
				b.ang["upperarm_r"] = a
				b.ang["lowerarm_r"] = Vector3(0, 0, 0)
				b.fk()
				var d: float = (b.P["hand_r"] as Vector3).z - h0.z
				if d > best:
					best = d
					best_a = a
	b.from_dict(stand)
	b.ang["upperarm_r"] = best_a
	b.fk()
	punch_r = b.to_dict()
	b.mirror_pose()
	b.fk()
	punch_l = b.to_dict()
	print("       punch pose: the hand goes %.2f m forward" % best)


func hero(strikes: Array) -> Scene:
	var cards := [{"name": "guard", "pose": stand, "move": -1.0, "hold": maxf(0.0, float(strikes[0][0]) - MV)}]
	for k in strikes.size():
		var s: Array = strikes[k]
		cards.append({"name": String(s[1]), "pose": punch_r if s[2] == "r" else punch_l, "move": MV, "hold": 0.0})
		var gap: float = (float(strikes[k + 1][0]) - float(s[0])) if k + 1 < strikes.size() else 3.0
		var ret := clampf(gap - MV, 0.04, 0.2)
		cards.append({"name": "guard", "pose": stand, "move": ret, "hold": maxf(0.0, gap - MV - ret) if k + 1 < strikes.size() else 2.0})
	var S := Scene.new()
	S.from_dict({"scene": "zz_hero", "fps": 30, "cards": cards})
	return S


func blocker(times: Array) -> Scene:
	var cards := [{"name": "guard", "pose": stand, "move": -1.0, "hold": maxf(0.0, float(times[0]) - 0.15)}]
	for k in times.size():
		cards.append({"name": "block", "pose": stand, "move": 0.15, "hold": maxf(0.0, (float(times[k + 1]) - float(times[k]) - 0.15) if k + 1 < times.size() else 2.5)})
	var S := Scene.new()
	S.from_dict({"scene": "zz_blocker", "fps": 30, "cards": cards})
	return S


func cards_json() -> String:
	return JSON.stringify([m.actors_rt[0]["S"].cards, m.actors_rt[1]["S"].cards])


## the injected mined answer: block > cross; the cards it hands back are fixture cards (the real ones come from ComboMine.cards_for)
func fake_cards(c: Dictionary, side: String) -> Array:
	return [{"name": "block", "pose": stand.duplicate(true), "move": float(c["moves"][0]), "hold": float(c["holds"][0])},
		{"name": "cross", "pose": punch_r.duplicate(true), "move": float(c["moves"][1]), "hold": 0.0}]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	make_poses()
	var pb := DistanceKeeper.new_body()
	pb.from_dict(punch_r)
	pb.fk()
	var fist: Vector3 = pb.palm_point("hand_r")
	var db := DistanceKeeper.new_body()
	db.from_dict(stand)
	db.fk()
	var fz := 0.8
	for zi in range(130, 30, -1):
		var zz := float(zi) * 0.01
		if float(Choreo.surface_gap(fist, db, Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, zz)))["gap"]) <= -0.01:
			fz = zz
			break
	print("       fighter 2 at z = %.2f m" % fz)
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, fz], "yaw": 180.0}, "scene": blocker([1.3])})
	m._actors_sync()
	m.S.markers = []
	m.S.cards = hero([[1.0, "jab", "r"], [1.8, "cross", "l"], [2.6, "hook", "r"], [3.4, "jab", "l"]]).cards.duplicate(true)
	m.actors_rt[1]["S"].cards = blocker([1.3, 2.1, 2.9, 3.7]).cards.duplicate(true)
	m._actors_sync()
	m._rebuild_cards()
	m.sg_on = true
	m.cur_page = "ANIMATE"
	m.sel_card = 0
	m.playhead = 4.0
	var ui = m.nb_ui
	if ui == null:
		m._sg_tick()
		ui = m.nb_ui
	ui.combos_override = [{"key": "block>cross.hand.same", "n": 2, "words": ["block", "cross"], "count": 3, "clips": 2, "moves": [0.15, 0.18], "holds": [0.02, 0.0],
		"lead": "r", "strikes": [1], "name": "block-cross", "rhythm": "0.15/0.18", "src": {"file": "", "cards": [1, 2]}}]
	ui.cards_of = fake_cards
	m._refresh()
	await idle(3)
	ok(m._fighters_on() and ui.wants(), "two fighters, the beat list is what View > Next poses shows")

	# (1) the top suggestion
	var first_compute_ms := 0.0
	var t0 := Time.get_ticks_usec()
	ui.clear()
	m._sg_tick()
	first_compute_ms = float(Time.get_ticks_usec() - t0) / 1000.0   # the very first set: the fatigue is on a worker, the frame does not wait for it
	var w0 := Time.get_ticks_msec()
	while ui.fat_pending() and Time.get_ticks_msec() - w0 < 30000:
		await idle(2)
	m._sg_tick()
	var fat_ok: bool = not ui._fat.is_empty() and ui.ms_fatigue > 0.0
	ok(fat_ok and first_compute_ms < 150.0, "(4) the first set comes in %.1f ms without waiting; the fatigue (%.0f ms of inverse dynamics) arrives from the worker and the set is made again" % [first_compute_ms, ui.ms_fatigue])
	var L: Array = ui.list
	for i in L.size():
		print("       %d. %s [%s] score %.3f  %s" % [i + 1, L[i]["label"], L[i]["kind"], float(L[i]["score"]), L[i]["why"]])
	var top: Dictionary = L[0] if not L.is_empty() else {}
	var why := String(top.get("why", ""))
	ok(not top.is_empty() and int(top["who"]) == 1 and top["kind"] == "answer", "(1) top suggestion: fighter 2 answers (%s)" % [top.get("label", "none")])
	ok(why.contains("blocked 4 times running") and why.contains("cross") and why.contains("0.20 s") and why.contains("3 times in 2 clips"), "(1) the why names the 4 blocks, the cross, 0.20 s and 3 times in 2 clips")
	var desc := true
	for i in range(1, L.size()):
		desc = desc and float(L[i - 1]["score"]) >= float(L[i]["score"])
	ok(L.size() >= 2 and desc, "(1) %d ranked suggestions in descending score order" % L.size())
	var st: Array = ui.res["state"]["fighters"]
	print("       fighter 1 run %d gap %.2f m reach %.2f m in_range %s F %.2f | fighter 2 run %d gap %.2f m reach %.2f m in_range %s F %.2f" % [
		st[0]["run"], st[0]["gap"], st[0]["reach"], st[0]["in_range"], st[0]["F"], st[1]["run"], st[1]["gap"], st[1]["reach"], st[1]["in_range"], st[1]["F"]])

	# (4) speed and cache
	print("       first set %.1f ms; fatigue on the worker %.1f ms; the set itself %.1f ms" % [first_compute_ms, ui.ms_fatigue, ui.ms])
	var ms_set: float = ui.ms
	var n0: int = ui.computes
	m._sg_tick()
	m._sg_tick()
	ok(ui.computes == n0, "(4) the same scene and playhead: nothing worked out again (computes %d)" % ui.computes)
	var worst := 0.0
	for r in 8:
		m.playhead = 4.0 + 0.01 * float(r + 1)
		m._sg_tick()
		worst = maxf(worst, ui.ms)
	print("       8 sets at moving playheads: worst %.1f ms" % worst)
	ok(ui.computes == n0 + 8 and worst < 150.0 and ms_set < 150.0, "(4) a suggestion set takes %.1f ms (worst of 8: %.1f ms) < 150 ms; a new playhead works out a new set" % [ms_set, worst])
	m.playhead = 4.0
	m._sg_tick()

	# (6) placement + screenshot setup: Tab picks the top, the ghost stands on fighter 2
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.pressed = true
	ok(ui.key(key) and ui.sel == 0, "(6) Tab picks the first suggestion")
	await idle(3)
	var gh: Array = m.ov._ghosts[2]
	var f2: Transform3D = m.actors_rt[1]["xf"]
	var gpos: Vector3 = (gh[0] as Node3D).transform.origin
	ok((gh[0] as Node3D).visible and gpos.distance_to(f2.origin) < 0.01 and gpos.distance_to(m.actors_rt[0]["xf"].origin) > 0.3,
		"(6) the ghost stands on fighter 2 (origin %s, his xf %s, not the hero's)" % [gpos, f2.origin])
	var vr: Rect2 = m.get_viewport().get_visible_rect()
	var pr: Rect2 = ui.panel.get_global_rect()
	var rows := 0
	for ch in ui.panel.find_children("beat_*", "PanelContainer", true, false):
		rows += 1
	ok(ui.panel.visible and vr.encloses(pr) and rows == L.size(), "(6) the ranked panel (%d rows, one per suggestion) is inside the view %s" % [rows, pr])
	# the ghost's pose is the end of the beat: fighter 2's hand has gone forward of his guard (the cross)
	var gb: Body = m.ov.GB
	m.actors_rt[1]["S"].apply(gb, 4.0)
	var hand0: Vector3 = (f2 * (gb.E["hand_r"] as Vector3))
	ui.pv.apply(gb, ui.pv_t)
	var hand1: Vector3 = (f2 * (gb.E["hand_r"] as Vector3))
	ok(hand1.distance_to(hand0) > 0.2, "(6) the ghost shows the cross: fighter 2's right hand ends %.0f cm from where it stands now" % (hand1.distance_to(hand0) * 100.0))
	m.yaw = 90.0
	m.dist = 8.2
	m.pitch = -6.0
	m.target = Vector3(0, 0.50, fz * 0.5)
	m._cam()
	m._refresh()
	await idle(3)
	var inside := true
	var view := Rect2(m.lw(), 60.0, vr.size.x - m.lw() - m.rw(), ui.panel.get_global_rect().position.y - 70.0)
	for k in 2:
		var hp: Vector3 = (m.actors_rt[k]["xf"] as Transform3D) * (m.actors_rt[k]["B"].E["head"] as Vector3)
		var fp: Vector3 = (m.actors_rt[k]["xf"] as Transform3D) * (m.actors_rt[k]["B"].P["foot_l"] as Vector3)
		inside = inside and view.has_point(m.cam.unproject_position(m.stage_root.transform * hp)) and view.has_point(m.cam.unproject_position(m.stage_root.transform * fp))
	ok(inside, "(6) whole-body view: both fighters' heads and feet are inside the view above the ranked panel %s" % view)
	await idle(2)
	m.get_viewport().get_texture().get_image().save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/i44.png")

	# (3) insert on the right fighter at the playhead, one undo step, undo exact
	var before := cards_json()
	var hero_before := JSON.stringify(m.actors_rt[0]["S"].cards)
	var u0: int = m.undo.size()
	var ncards: int = m.actors_rt[1]["S"].cards.size()
	var res: Dictionary = ui.accept(0)
	await idle(2)
	var S2: Scene = m.actors_rt[1]["S"]
	var tsn := S2.times()
	var f := int(res.get("first", -1))
	ok(bool(res.get("ok", false)) and int(m.actor_on) == 1 and S2.cards.size() == ncards + 1 and f > 0 and absf(float(tsn[f][0]) - 4.0) <= 0.001 and String(S2.cards[f]["name"]) == "cross",
		"(3) the cross is fighter 2's new card %d and its move starts at %.3f s (the playhead 4.000 s)" % [f + 1, float(tsn[f][0]) if f > 0 else -1.0])
	ok(JSON.stringify(m.actors_rt[0]["S"].cards) == hero_before, "(3) the hero's cards are byte-identical")
	ok(m.undo.size() == u0 + 1, "(3) one undo step (%d -> %d)" % [u0, m.undo.size()])
	# (5) the journal
	var sk := "next beat|answer"
	ok(m.sj.stats.has(sk) and int(m.sj.stats[sk]["offers"]) == 1, "(5) the accept is in the suggestion journal as next beat / answer")
	m._undo()
	await idle(2)
	ok(cards_json() == before and m.undo.size() == u0, "(3) Ctrl+Z restores both fighters' cards exactly")
	m.sj.observe(m.undo.size())
	ok(int(m.sj.stats[sk]["rejected"]) == 1, "(5) the undo counts as REJECTED in the journal (%d)" % int(m.sj.stats[sk]["rejected"]))

	# (2) out of range
	m.actors_rt[1]["S"].cards = blocker([1.3, 2.1, 2.9, 3.7]).cards.duplicate(true)
	m.playhead = 4.0
	m.actors_rt[1]["xf"] = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 2.2))
	m._refresh()
	await idle(2)
	ui.clear()
	m._sg_tick()
	L = ui.list
	for i in L.size():
		print("       far %d. %s [%s] %.3f  %s" % [i + 1, L[i]["label"], L[i]["kind"], float(L[i]["score"]), L[i]["why"]])
	var kinds := L.map(func(x): return String(x["kind"]))
	ok(not L.is_empty() and L[0]["kind"] == "close" and not kinds.has("answer") and not kinds.has("strike") and not kinds.has("continue"), "(2) out of range: the top suggestion is to close the distance %s and no strike is offered" % [kinds])
	var cl: Dictionary = L[0]
	var kk := int(cl["who"])
	var gap_before := float(ui.res["state"]["fighters"][kk]["gap"])
	var pv := (m.actors_rt[kk]["S"] as Scene).clone()
	var fi := NextBeat.insert(pv, 4.0, cl["cards"])
	var scs: Array = [m.actors_rt[0]["S"], m.actors_rt[1]["S"]]
	scs[kk] = pv
	var after: Dictionary = NextBeat.analyze(scs, ["a", "b"], [m.actors_rt[0]["xf"], m.actors_rt[1]["xf"]], NextBeat.ghost_time(pv, fi, (cl["cards"] as Array).size()) + 0.01, {})
	var gap_after := float(after["state"]["fighters"][kk]["gap"])
	print("       gap %.3f m -> %.3f m after the step in; reach %.2f m" % [gap_before, gap_after, float(ui.res["state"]["fighters"][kk]["reach"])])
	var aimed := float(ui.res["state"]["fighters"][kk]["reach"]) * DistanceKeeper.JAM_AIM
	ok(gap_after < gap_before - 0.05 and (gap_after <= aimed + 0.03 or (cl["cards"] as Array).size() >= 2), "(2) after the step in the gap shrank by %.0f cm (aim %.0f cm of the reach)" % [(gap_before - gap_after) * 100.0, aimed * 100.0])

	ui.finish()
	var w1 := Time.get_ticks_msec()
	while ui.fat_pending() and Time.get_ticks_msec() - w1 < 30000:   # a worker still reading must finish before the engine quits
		await idle(2)
	print("i44: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)
