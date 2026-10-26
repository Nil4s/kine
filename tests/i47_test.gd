## godot --path . -s tests/i47_test.gd     (ROADMAP I47: human speed envelope, scripts/speed_env.gd + speed_env_ui.gd; needs a window)
## A synthetic clip (poses of scenes/thrust.json, written under user://) with ONE too-fast punch: ready -> chamber (0.30 s) -> STRIKE (0.04 s) -> recover (0.50 s).
## Bars, written before measuring:
##  (1) the card list flags exactly the strike card (index 2) and no other; its worst channel is the hand, above 13.79 m/s (Stanley 2018 mean + SD)
##  (2) the hand peak is right: SpeedEnv's number for that card equals an independent 240 Hz finite difference of B.E hand (metres) within 5 %
##  (3) the plan lengthens ONLY the strike card's move; the card's worst channel then peaks within 5 % of the limit and not above it
##      (checked on the plan's scene by SpeedEnv); every other card is byte-identical (JSON)
##  (4) analysis and planning are read only: B.state() and the scene JSON are identical after them; Preview plays to its end and leaves the scene JSON identical
##  (5) Accept is ONE undo step; Ctrl+Z restores the cards and scene JSON exactly
##  (6) scenes/combo3.json (read only, hashes the same after): its flagged cards are printed; its STRIKE (step) card is flagged with a hand above 25 m/s
##  (7) PLACEMENT: the panel is inside the window with a sentence per flagged card; every joint of the body and the hand/foot tips are drawn inside the window,
##      none under the panel
extends SceneTree

const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i47.png"
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func write(path: String, d: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func _init() -> void:
	var combo_md5 := FileAccess.get_md5("res://scenes/combo3.json")
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var B: Body = m.B
	var th: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/thrust.json"))
	var ready: Dictionary = th["cards"][0]["pose"]
	var chamber: Dictionary = th["cards"][6]["pose"]
	var thrust: Dictionary = th["cards"][9]["pose"]
	var rows := [["guard ready", ready, -1.0, 0.25], ["wind-up", chamber, 0.30, 0.05], ["STRIKE", thrust, 0.04, 0.10], ["recover", ready, 0.50, 0.20]]
	var cs := []
	for r in rows:
		cs.append({"name": r[0], "pose": (r[1] as Dictionary).duplicate(true), "move": r[2], "hold": r[3]})
	var tmp := "user://i47_%d/" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(tmp)
	var path := tmp + "fast.json"
	write(path, {"scene": "fast", "fps": 30, "cards": cs})
	m._load_scene(path)
	m._rebuild_cards()
	await idle()
	var S: Scene = m.S
	var json0 := JSON.stringify(S.to_dict(B, false))
	var cards0: Array = JSON.parse_string(JSON.stringify(S.cards))
	var state0 := JSON.stringify(B.state())

	# (1)(2)(4) the analysis
	m.se_ui.show()
	await idle()
	var rws: Array = m.se_ui.rows
	var fl := SpeedEnv.flagged(rws)
	for r in rws:
		print("     card %d %s: worst %s%s %.1f %s (limit %.1f, ratio %.2f)" % [int(r["card"]) + 1, r["name"], r["side"], r["ch"]["label"], r["peak"], r["ch"]["unit"], r["limit"], r["ratio"]])
	ok(fl.size() == 1 and int(fl[0]["card"]) == 2 and String(fl[0]["ch"]["id"]) == "hand" and float(fl[0]["peak"]) > 13.79,
		"(1) exactly the strike card is flagged: %d flagged, card index %d, %s %.1f m/s > 13.79 m/s" % [fl.size(), int(fl[0]["card"]) if fl.size() > 0 else -1, fl[0]["ch"]["id"] if fl.size() > 0 else "-", float(fl[0]["peak"]) if fl.size() > 0 else 0.0])
	var ts := S.times()
	var ref := 0.0
	var prev := {}
	var t0 := float(ts[1][2])
	var t1 := float(ts[2][1])
	var nn := int(ceil((t1 - t0) * 240.0))
	for k in nn + 1:
		S.apply(B, t0 + (t1 - t0) * float(k) / float(nn))
		for h in ["hand_l", "hand_r"]:
			var q: Vector3 = B.E[h]
			if prev.has(h):
				ref = maxf(ref, (q - (prev[h] as Vector3)).length() * float(nn) / (t1 - t0))
			prev[h] = q
	var got := float(fl[0]["peak"]) if fl.size() > 0 else 0.0
	ok(ref > 0.0 and absf(got - ref) <= 0.05 * ref, "(2) strike hand peak %.2f m/s vs an independent 240 Hz difference %.2f m/s (within 5 %%)" % [got, ref])
	m._ps().apply(B, m.playhead)
	state0 = JSON.stringify(B.state())

	# (3) the plan
	m.se_ui.make_plan()
	await idle()
	var plan: Dictionary = m.se_ui.plan
	var W: Scene = plan["scene"]
	var ch: Array = plan["changes"]
	ok(JSON.stringify(B.state()) == state0 and JSON.stringify(S.to_dict(B, false)) == json0, "(4) analysis and planning left the body state and the scene JSON as they were")
	var only := true
	for i in S.cards.size():
		if i != 2 and JSON.stringify(W.cards[i]) != JSON.stringify(S.cards[i]):
			only = false
	var c2: Dictionary = (W.cards[2] as Dictionary).duplicate(true)
	var c2o: Dictionary = (S.cards[2] as Dictionary).duplicate(true)
	c2.erase("move")
	c2o.erase("move")
	only = only and JSON.stringify(c2) == JSON.stringify(c2o) and float(W.cards[2]["move"]) > float(S.cards[2]["move"])
	ok(only and ch.size() == 1, "(3) only the strike card's move changed: %.3f s -> %.3f s; the other cards are byte-identical" % [float(S.cards[2]["move"]), float(W.cards[2]["move"])])
	var after := SpeedEnv.analyse(W, B)
	var a2: Dictionary = after[1]
	print("     after: card 3 worst %s%s %.1f %s (limit %.1f, ratio %.3f)" % [a2["side"], a2["ch"]["label"], a2["peak"], a2["ch"]["unit"], a2["limit"], a2["ratio"]])
	ok(float(a2["ratio"]) >= 0.95 and float(a2["ratio"]) <= 1.0, "(3) the strike card now peaks at %.1f%% of its limit (within 5 %% and not above)" % (100.0 * float(a2["ratio"])))
	var others_ok := true
	for i in [0, 2]:
		others_ok = others_ok and float(after[i]["ratio"]) <= 1.0
	ok(others_ok, "(3) no other card is flagged after the fix")
	state0 = JSON.stringify(B.state())

	# (7) placement, with the panel on the plan
	m.playhead = float(ts[2][1])   # the pose the strike card arrives in: the body the panel is about
	m._ps().apply(B, m.playhead)
	m._refresh()
	await idle(3)
	m._ps().apply(B, m.playhead)
	var img: Image = root.get_texture().get_image()
	var panel: Control = m.ui_find
	var pr: Rect2 = panel.get_global_rect()
	var vp: Rect2 = m.get_viewport().get_visible_rect()
	var cam: Camera3D = m.get_viewport().get_camera_3d()
	var clear := cam != null
	var where := []
	for j in Body.BODY:
		var pt: Vector2 = cam.unproject_position(B.P[j]) if cam != null else Vector2.ZERO
		clear = clear and vp.has_point(pt) and not pr.has_point(pt)
	for j in ["hand_l", "hand_r", "foot_l", "foot_r"]:
		var pt: Vector2 = cam.unproject_position(B.E[j]) if cam != null else Vector2.ZERO
		where.append("%s %s" % [j, pt])
		clear = clear and vp.has_point(pt) and not pr.has_point(pt)
	ok(panel.visible and vp.encloses(pr) and m.ui_find_list.find_child("se_change_0", true, false) != null and clear,
		"(7) panel %s inside the window %s with a sentence per retimed card; body points clear of it: %s" % [pr, vp, where])
	img.save_png(SHOT)
	print("     picture: " + SHOT)

	# (4) preview
	m.se_ui.preview()
	var guard := 0
	while m.se_ui.pv != null and guard < 900:
		await process_frame
		guard += 1
	ok(m.se_ui.pv == null and JSON.stringify(S.to_dict(B, false)) == json0, "(4) Preview played to its end (%d frames) and the scene JSON is byte-identical" % guard)

	# (5) accept / undo
	var u0: int = m.undo.size()
	m.se_ui.accept()
	await idle()
	ok(m.undo.size() == u0 + 1 and float(m.S.cards[2]["move"]) > 0.04, "(5) Accept is ONE undo step (%d -> %d), strike move now %.3f s" % [u0, m.undo.size(), float(m.S.cards[2]["move"])])
	m._undo()
	await idle()
	ok(JSON.stringify(m.S.cards) == JSON.stringify(cards0) and JSON.stringify(m.S.to_dict(B, false)) == json0, "(5) Ctrl+Z restores the cards and the scene JSON exactly")

	# (6) combo3, read only
	var Sr := Scene.new()
	Sr.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var keep6: Dictionary = B.state()
	var r6 := SpeedEnv.analyse(Sr, B)
	var f6 := SpeedEnv.flagged(r6)
	print("     combo3: %d of %d cards flagged" % [f6.size(), r6.size()])
	var strike_hand := 0.0
	for r in f6:
		print("       - " + SpeedEnv.words(r))
		if String(r["name"]).contains("STRIKE (step)"):
			for a in r["all"]:
				if String(a["id"]) == "hand":
					strike_hand = float(a["peak"])
	ok(strike_hand > 25.0 and JSON.stringify(B.state()) == JSON.stringify(keep6) and FileAccess.get_md5("res://scenes/combo3.json") == combo_md5,
		"(6) combo3 STRIKE (step) is flagged with hand %.1f m/s (> 25 m/s) and the file and body state are untouched" % strike_hand)

	print("I47 SPEED ENVELOPE %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
