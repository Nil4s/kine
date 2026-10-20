## godot --path . -s tests/i19_test.gd     (ROADMAP I19: fight rhythm, scripts/fight_rhythm.gd + fight_rhythm_ui.gd; needs a window)
## SYNTHETIC EXCHANGES, built here from real poses (poses/stand.json and its arm-raised variant, so the hands really travel): the hero throws
## punches at stated times (each strike card arrives exactly then), fighter 2 answers with block cards. The reading is checked against the times
## that were put in. Bars, written before measuring:
##  (1) MONOTONY: strikes 0.8 s apart three times (1.0, 1.8, 2.6, 3.4; sides and kinds varied, blocks 0.3 s after each) -> exactly one flag,
##      type interval, text with the 0.80 s; nothing else flagged
##  (2) DEAD AIR: a 2.0 s gap between actions (1.7 -> 3.7) -> exactly one flag, dead_air, gap = 2.00 s +-0.02
##  (3) CLEAN: strikes 0.8 / 1.1 / 0.6 s apart, sides r l r r, four kinds, every strike blocked 0.3 s later -> NO flags
##  (4) SIDE (4 right-side strikes), KIND (3 hooks), RUSH (two punches 0.20 s apart; the coach's settle rule asks 1.5 x the 0.15 s move = 0.225 s)
##      -> each exactly one flag of its type and no other
##  (5) each suggestion: the scenes' cards are byte-identical after the flag is read, after selecting the suggestion and after Preview played to
##      its end; Accept is ONE undo step; afterwards NO flag of that type; Ctrl+Z restores both fighters' cards exactly. What changed is measured:
##      the pause grows the interval by 0.30 s +-0.01 (rush: to >= 0.225 s), the mirror turns the 4th strike's side to the other hand, the feint
##      leaves no action gap over 1.2 s (dead air) / no run of 3 hooks (kind) and the clip is as long as before (+-0.02 s)
##  (6) PLACEMENT: the timeline holds one tick per action inside the track, a red band under the flags; the panel holds a row per flag with its
##      button; the screenshot is taken on a clip with all five flags
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
	for a in [Vector3(-90, 0, 0), Vector3(0, 0, 80), Vector3(0, 0, -80), Vector3(80, 0, 0), Vector3(0, 80, 0), Vector3(-60, 0, 60), Vector3(60, 0, 60)]:
		b.from_dict(stand)
		b.ang["upperarm_r"] = a
		b.ang["lowerarm_r"] = Vector3(0, 0, 0)
		b.fk()
		var d: float = (b.P["hand_r"] as Vector3).distance_to(h0)
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
	print("       punch pose: upperarm_r %s, the hand travels %.2f m" % [best_a, best])


## the hero: strikes = [[arrival time, name, "r" / "l"]] ascending. Each strike card arrives at its time (a MV move), a return card follows
func hero(strikes: Array) -> Scene:
	var cards := [{"name": "guard", "pose": stand, "move": -1.0, "hold": maxf(0.0, float(strikes[0][0]) - MV)}]
	for k in strikes.size():
		var s: Array = strikes[k]
		cards.append({"name": String(s[1]), "pose": punch_r if s[2] == "r" else punch_l, "move": MV, "hold": 0.0})
		var gap: float = (float(strikes[k + 1][0]) - float(s[0])) if k + 1 < strikes.size() else 1.0
		var ret := clampf(gap - MV, 0.04, 0.2)
		cards.append({"name": "guard", "pose": stand, "move": ret, "hold": maxf(0.0, gap - MV - ret) if k + 1 < strikes.size() else 0.2})
	var S := Scene.new()
	S.from_dict({"scene": "zz_hero", "fps": 30, "cards": cards})
	return S


## fighter 2: a block card arriving at each time
func blocker(times: Array) -> Scene:
	var cards := [{"name": "guard", "pose": stand, "move": -1.0, "hold": maxf(0.0, float(times[0]) - 0.15)}]
	for k in times.size():
		cards.append({"name": "block", "pose": stand, "move": 0.15, "hold": maxf(0.0, (float(times[k + 1]) - float(times[k]) - 0.15) if k + 1 < times.size() else 0.2)})
	var S := Scene.new()
	S.from_dict({"scene": "zz_blocker", "fps": 30, "cards": cards})
	return S


func put(h: Scene, d: Scene) -> void:
	m.S.markers = []
	m.S.cards = h.cards.duplicate(true)
	m.actors_rt[1]["S"].cards = d.cards.duplicate(true)
	m._actors_sync()
	m._rebuild_cards()
	m._refresh()


func cards_json() -> String:
	return JSON.stringify([m.actors_rt[0]["S"].cards, m.actors_rt[1]["S"].cards])


func types(rep: Dictionary) -> Array:
	return (rep["flags"] as Array).map(func(f): return String(f["type"]))


func strike_ts(rep: Dictionary) -> Array:
	return (rep["events"] as Array).filter(func(e): return e["type"] == "strike").map(func(e): return float(e["t"]))


func max_gap(rep: Dictionary) -> float:
	var g := 0.0
	var ev: Array = rep["events"]
	for k in range(1, ev.size()):
		g = maxf(g, float(ev[k]["t"]) - float(ev[k - 1]["t"]))
	return g


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
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, 1.1], "yaw": 180.0}, "scene": blocker([1.3])})
	m._actors_sync()
	m._refresh()
	await idle()
	ok(m._fighters_on(), "two fighters")
	var ui = m.rh_ui

	var fix_cases := []   # [name, hero strikes, blocks, expected type]
	var mono_h := [[1.0, "jab", "r"], [1.8, "cross", "l"], [2.6, "hook", "r"], [3.4, "jab", "l"]]
	var mono_d := [1.3, 2.1, 2.9, 3.7]

	# (1) monotony
	put(hero(mono_h), blocker(mono_d))
	ui.show()
	await idle()
	var rep: Dictionary = ui.rep
	print("       strikes at %s, intervals %s, flags %s" % [strike_ts(rep), rep["intervals"], types(rep)])
	ok(types(rep) == ["interval"] and String(rep["flags"][0]["text"]).contains("0.80"), "(1) 3 equal intervals: one flag %s (%s)" % [types(rep), rep["flags"][0]["text"] if not rep["flags"].is_empty() else ""])
	var st_ok := true
	for k in 4:
		st_ok = st_ok and absf(float(strike_ts(rep)[k]) - float(mono_h[k][0])) < 0.02
	ok(st_ok and rep["events"].size() == 8, "(1) the reading finds the 4 strikes at the times put in (+-0.02 s) and the 4 blocks")
	var ans := (rep["events"] as Array).filter(func(e): return e["type"] == "strike" and e["answer"] != "").size()
	ok(ans == 4, "(1) every strike is shown answered by fighter 2's block (%d of 4)" % ans)

	# (2) dead air
	put(hero([[1.0, "jab", "r"], [1.7, "hook", "l"], [3.7, "cross", "r"]]), blocker([1.3, 4.0]))
	ui.show()
	await idle()
	rep = ui.rep
	var gap2 := (float(rep["flags"][0]["t1"]) - float(rep["flags"][0]["t0"])) if not rep["flags"].is_empty() else 0.0
	print("       flags %s gap %.3f" % [types(rep), gap2])
	ok(types(rep) == ["dead_air"] and absf(gap2 - 2.0) <= 0.02, "(2) a 2 s gap: one flag %s, gap %.2f s" % [types(rep), gap2])

	# (3) clean
	put(hero([[1.0, "jab", "r"], [1.8, "hook", "l"], [2.9, "cross", "r"], [3.5, "uppercut", "r"]]), blocker([1.3, 2.1, 3.2, 3.8]))
	ui.show()
	await idle()
	rep = ui.rep
	print("       intervals %s, flags %s: %s" % [rep["intervals"], types(rep), rep["msg"]])
	ok(rep["flags"].is_empty() and rep["events"].size() == 8, "(3) a varied exchange: no flags (%s)" % rep["msg"])

	# (4)(5) one fixture per kind of flag; each is read, selected, previewed, accepted, undone
	var cases := [
		["interval", mono_h, mono_d],
		["dead_air", [[1.0, "jab", "r"], [1.7, "hook", "l"], [3.7, "cross", "r"]], [1.3, 4.0]],
		["side", [[1.0, "jab", "r"], [1.7, "cross", "r"], [2.7, "hook", "r"], [3.5, "uppercut", "r"]], [1.3, 2.0, 3.0, 3.8]],
		["kind", [[1.0, "hook", "r"], [1.7, "hook", "l"], [2.7, "hook", "r"], [3.5, "jab", "l"]], [1.3, 2.0, 3.0, 3.8]],
		["rush", [[1.0, "jab", "r"], [1.2, "cross", "l"], [2.4, "hook", "r"]], [1.3, 1.5, 2.7]]]
	for cs in cases:
		var ty: String = cs[0]
		put(hero(cs[1]), blocker(cs[2]))
		ui.show()
		await idle()
		rep = ui.rep
		ok(types(rep) == [ty], "(4) %s fixture: exactly one flag, %s (%s)" % [ty, types(rep), rep["flags"][0]["text"] if not rep["flags"].is_empty() else rep["msg"]])
		if types(rep) != [ty]:
			continue
		var before := cards_json()
		var len0: float = m.actors_rt[0]["S"].length()
		var ts_before := strike_ts(rep)
		var gap_before := max_gap(rep)
		ui.select(0)
		await idle()
		var sel_ok: bool = not ui.fx.is_empty() and cards_json() == before
		ui.preview()
		var ticks := 0
		while ui.pv != null and ticks < 1500:
			await process_frame
			ticks += 1
		ok(sel_ok and cards_json() == before and ticks > 5, "(5) %s: after reading, selecting '%s' and Preview (%d frames) both fighters' cards are byte-identical" % [ty, rep["flags"][0]["fix"]["label"], ticks])
		var u0: int = m.undo.size()
		ui.accept()
		await idle()
		m._actors_sync()
		var after: Dictionary = ui.rep
		var ts_after := strike_ts(after)
		var extra := ""
		var good := true
		match ty:
			"interval":
				var d_before: float = ts_before[2] - ts_before[1]
				var d_after: float = ts_after[2] - ts_after[1]
				extra = "the 2nd interval %.2f -> %.2f s" % [d_before, d_after]
				good = absf(d_after - d_before - 0.3) <= 0.01
			"rush":
				var d_after2: float = ts_after[1] - ts_after[0]
				extra = "the strikes %.2f -> %.2f s apart (need 0.225)" % [ts_before[1] - ts_before[0], d_after2]
				good = d_after2 >= 0.225 - 1e-3 and d_after2 <= 0.65
			"side":
				var e4: Dictionary = (after["events"] as Array).filter(func(e): return e["type"] == "strike")[3]
				extra = "the 4th strike now %s hand" % ("left" if e4["side"] == "l" else "right")
				good = e4["side"] == "l"
			"kind", "dead_air":
				var nf: int = (after["events"] as Array).filter(func(e): return e["type"] == "feint").size()
				var len1: float = m.actors_rt[0]["S"].length()
				extra = "%d feint, longest action gap %.2f -> %.2f s, clip %.2f -> %.2f s" % [nf, gap_before, max_gap(after), len0, len1]
				good = nf == 1 and absf(len1 - len0) <= 0.02 and (ty != "dead_air" or max_gap(after) <= 1.2 + 1e-6)
		ok(m.undo.size() == u0 + 1 and not types(after).has(ty) and good, "(5) %s: Accept is one undo step (%d -> %d), no %s flag after (%s); %s" % [ty, u0, m.undo.size(), ty, types(after), extra])
		m._undo()
		await idle()
		m._actors_sync()
		ok(cards_json() == before and m.undo.size() == u0, "(5) %s: Ctrl+Z restores both fighters' cards exactly" % ty)

	# (6) placement + screenshot: a clip with all five flags
	var show_h := [[0.8, "jab", "r"], [1.6, "jab", "r"], [2.4, "jab", "r"], [3.2, "cross", "r"], [5.4, "hook", "l"], [5.6, "cross", "r"]]
	put(hero(show_h), blocker([1.1, 1.9, 2.7, 3.5, 5.7]))
	ui.show()
	await idle(4)
	rep = ui.rep
	var tl = m.ui_timeline
	var inside := true
	for e in tl.rh:
		var x: float = tl.x_of(float(e["t"]))
		inside = inside and x >= 0.0 and x <= tl.size.x
	var rows := 0
	for c in m.ui_find_list.get_children():
		if c is HBoxContainer and c.get_child_count() > 1 and c.get_child(1) is Button and String((c.get_child(1) as Button).name).begins_with("rh_fix_"):
			rows += 1
	print("       showcase flags: %s" % [types(rep)])
	ok(tl.rh.size() == rep["events"].size() and tl.rh_flags.size() == rep["flags"].size() and inside and rows == rep["flags"].size() and rows >= 4 and m.ui_find.visible,
		"(6) the timeline holds %d ticks (one per action) inside the track and %d red bands; the panel %d flag rows with their buttons" % [tl.rh.size(), tl.rh_flags.size(), rows])
	ui.select(0)
	await idle(4)
	m._say("fight rhythm: 5 flags; each has a one-click suggestion, Preview then Accept")
	m.playhead = 0.0
	m._refresh()
	await idle(4)
	root.get_texture().get_image().save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/i19.png")

	print("I19 FIGHT RHYTHM %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	quit(1 if fails > 0 else 0)
