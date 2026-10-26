## godot --path . -s tests/i31_test.gd     (ROADMAP I31: precog check, scripts/precog.gd + precog_ui.gd; needs a window)
## SYNTHETIC EXCHANGES from real poses (poses/stand.json and an arm-raised variant): the hero guards 0.5 s, winds up (0.3 s move from 0.5 s),
## holds 0.1 s and jabs (0.15 s move, arrives 1.05 s = the contact); fighter 2 answers with a block card. Readable = 0.50 s (the wind-up begins:
## Counter.read_time). Bars, written before measuring:
##  (1) PRECOG: a block starting 0.55 s (0.05 s after readable), 0.25 s long -> status precog (gap 0.05 +-0.005), not late; the fix starts it at
##      0.79 s (gap >= Counter.REACT 0.29 - 0.005), its length 0.25 s unchanged; afterwards status ok
##  (2) LATE (shorten): a block starting 0.80 s, 0.40 s long (arrives 1.20, 0.15 s after the hit) -> late; fix: arrives at the hit (1.05 +-0.005),
##      move 0.25 s (>= Counter.MV 0.12); afterwards ok, fighter 1's cards untouched
##  (3) LATE (delay the strike): a block starting 1.00 s, 0.20 s long -> late; it cannot be shortened to 0.12 s in time, so the strike is
##      delayed (fighter 1's cards change, move still 0.15 s), the block's move is 0.12 s, afterwards ok and readable unchanged (0.50)
##  (4) CLEAN: a block starting 0.82 s, 0.15 s long -> one item, status ok, no flags, a fix is refused
##  (5) for every fix: the cards of both fighters are byte-identical after reading, selecting and Preview; Accept is ONE undo step; Ctrl+Z restores
##      both fighters' cards exactly
##  (6) PLACEMENT: a clip with a PRECOG and a LATE reaction: the timeline holds a badge per reaction inside the track, the panel a row per
##      item with a Retime button on the flagged ones; the screenshot is taken on it
extends SceneTree

var fails := 0
var m: Node
var stand: Dictionary
var punch_r: Dictionary


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


func hero(two := false) -> Scene:
	var wind := FightRhythm.blend_pose(stand, punch_r, 0.5)
	var cards := [{"name": "guard", "pose": stand, "move": -1.0, "hold": 0.5},
		{"name": "wind-up", "pose": wind, "move": 0.3, "hold": 0.1},
		{"name": "jab", "pose": punch_r, "move": 0.15, "hold": 0.0},
		{"name": "guard", "pose": stand, "move": 0.2, "hold": 0.3 if two else 0.5}]
	if two:
		cards.append({"name": "wind-up", "pose": wind, "move": 0.3, "hold": 0.1})
		cards.append({"name": "cross", "pose": punch_r, "move": 0.15, "hold": 0.4})
	var S := Scene.new()
	S.from_dict({"scene": "zz_hero", "fps": 30, "cards": cards})
	return S


## fighter 2: stands until `onset`, then a block card of `mv` seconds (a second one at onset2 / mv2 when given)
func blocker(onset: float, mv: float, onset2 := -1.0, mv2 := 0.3) -> Scene:
	var cards := [{"name": "guard", "pose": stand, "move": -1.0, "hold": onset},
		{"name": "block", "pose": stand, "move": mv, "hold": 0.3 if onset2 < 0.0 else onset2 - onset - mv}]
	if onset2 >= 0.0:
		cards.append({"name": "block", "pose": stand, "move": mv2, "hold": 0.3})
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
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, 1.1], "yaw": 180.0}, "scene": blocker(0.55, 0.25)})
	m._actors_sync()
	m._refresh()
	await idle()
	ok(m._fighters_on(), "two fighters")
	var ui = m.pc_ui

	# (4) clean first
	put(hero(), blocker(0.82, 0.15))   # 0.32 s after readable: over Counter.REACT 0.29 s (Liu 2018, measured)
	ui.show()
	await idle()
	var rep: Dictionary = ui.rep
	var it0: Dictionary = rep["items"][0] if not rep["items"].is_empty() else {}
	print("       clean: %s" % [it0])
	ok(rep["items"].size() == 1 and rep["flags"].is_empty() and it0["status"] == "ok" and absf(float(it0["readable"]) - 0.5) <= 0.005 and absf(float(it0["contact"]) - 1.05) <= 0.005,
		"(4) a block starting 0.32 s after the wind-up: one item, ok, no flags (readable %.2f, hit %.2f)" % [it0.get("readable", -1.0), it0.get("contact", -1.0)])
	ok(not Precog.fix(ui._scenes(), ui._names(), it0)["ok"], "(4) a fix for a clean reaction is refused")

	# (1)-(3), (5)
	var cases := [
		["precog", 0.55, 0.25, "precog"],
		["late_shorten", 0.80, 0.40, "late"],
		["late_delay", 1.00, 0.20, "late"]]
	for cs in cases:
		var nm: String = cs[0]
		put(hero(), blocker(cs[1], cs[2]))
		ui.show()
		await idle()
		rep = ui.rep
		var it: Dictionary = rep["items"][0] if not rep["items"].is_empty() else {}
		print("       %s: %s" % [nm, it])
		ok(rep["items"].size() == 1 and it["status"] == cs[3], "%s: read as %s (gap %.2f, arrives %.2f, hit %.2f)" % [nm, it.get("status", "?"), it.get("gap", 0.0), it.get("arrival", 0.0), it.get("contact", 0.0)])
		if rep["items"].is_empty() or it["status"] != cs[3]:
			continue
		if nm == "precog":
			ok(absf(float(it["gap"]) - 0.05) <= 0.005, "(1) the block starts %.3f s after readable (0.05 +-0.005)" % it["gap"])
		var before := cards_json()
		var hero_before := JSON.stringify(m.actors_rt[0]["S"].cards)
		ui.select(0)
		await idle()
		var sel_ok: bool = not ui.fx.is_empty() and cards_json() == before
		ui.preview()
		var ticks := 0
		while ui.playing and ticks < 1500:
			await process_frame
			ticks += 1
		ok(sel_ok and cards_json() == before and ticks > 5, "(5) %s: after reading, selecting and Preview (%d frames) both fighters' cards are byte-identical" % [nm, ticks])
		var u0: int = m.undo.size()
		ui.accept()
		await idle()
		m._actors_sync()
		var af: Dictionary = ui.rep["items"][0] if not ui.rep["items"].is_empty() else {}
		print("       after: %s" % [af])
		var good := false
		var dts: Array = (m.actors_rt[1]["S"] as Scene).times()
		var mv_after := float(dts[1][1]) - float(dts[1][0])
		var hero_changed := JSON.stringify(m.actors_rt[0]["S"].cards) != hero_before
		var extra := ""
		match nm:
			"precog":
				good = float(af["gap"]) >= Counter.REACT - 0.005 and absf(mv_after - 0.25) <= 0.002 and not hero_changed
				extra = "onset - readable %.3f s (>= REACT), move %.3f s (0.25), hero untouched %s" % [af["gap"], mv_after, not hero_changed]
			"late_shorten":
				good = absf(float(af["arrival"]) - float(af["contact"])) <= 0.005 and absf(mv_after - 0.25) <= 0.002 and mv_after >= Counter.MV and not hero_changed
				extra = "arrives %.3f s at the hit %.3f s, move %.3f s (0.25, >= 0.12), hero untouched %s" % [af["arrival"], af["contact"], mv_after, not hero_changed]
			"late_delay":
				good = float(af["arrival"]) <= float(af["contact"]) + 0.005 and absf(mv_after - Counter.MV) <= 0.002 and hero_changed and absf(float(af["readable"]) - 0.5) <= 0.005 and float(af["gap"]) >= Counter.REACT - 0.005
				extra = "arrives %.3f s, hit now %.3f s, move %.3f s (0.12), strike delayed %s, readable %.2f" % [af["arrival"], af["contact"], mv_after, hero_changed, af["readable"]]
		ok(m.undo.size() == u0 + 1 and af.get("status", "") == "ok" and good, "(%s) Accept is one undo step (%d -> %d), status ok afterwards; %s" % [nm, u0, m.undo.size(), extra])
		m._undo()
		await idle()
		m._actors_sync()
		ok(cards_json() == before and m.undo.size() == u0, "(5) %s: Ctrl+Z restores both fighters' cards exactly" % nm)

	# (6) placement + screenshot
	put(hero(true), blocker(0.55, 0.25, 2.0, 0.3))
	ui.show()
	await idle(4)
	rep = ui.rep
	var tl = m.ui_timeline
	var inside := true
	for b in tl.pc:
		var x: float = tl.x_of(float(b["t"]))
		inside = inside and x >= 0.0 and x <= tl.size.x
	var rows := 0
	var btns := 0
	for c in m.ui_find_list.get_children():
		if c is HBoxContainer and c.get_child_count() > 0 and c.get_child(0) is Label and String(c.get_child(0).name).begins_with("pc_row_"):
			rows += 1
			btns += 1 if c.get_child_count() > 1 else 0
	var sts: Array = (rep["items"] as Array).map(func(i): return String(i["status"]))
	print("       showcase: %s" % [sts])
	ok(sts == ["precog", "late"] and tl.pc.size() == 2 and inside and rows == 2 and btns == 2 and m.ui_find.visible,
		"(6) %s: the timeline holds %d badges inside the track; the panel %d rows, %d with Retime" % [sts, tl.pc.size(), rows, btns])
	ui.select(0)
	await idle(4)
	m.playhead = 0.55
	m._refresh()
	await idle(4)
	root.get_texture().get_image().save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/i31.png")

	print("I31 PRECOG CHECK %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
