## godot --path . -s tests/i36_test.gd     (ROADMAP I36: momentum ledger, scripts/momentum.gd + momentum_ui.gd; needs a window)
## SYNTHETIC LUNGE from the real poses/stand.json: the hips travel 0.8 m forward in 0.9 s (the root finishes at 70 % of a move: Scene.LAG) and the card holds 0.6 s, then the body returns
## (1.2 s, smooth). A: the move into the lunge is LINEAR (it arrives at full speed: a dead stop); B: the same lunge with the default smooth ease.
## Bars, written before measuring:
##  (1) A is flagged at the lunge card (card 2): linear, momentum along the travel >= 60 kg m/s going in, <= 25 % of it coming out, within <= 2
##      frames, the force over 0.05 s >= 1.5 x the 1.5 BW bar; the sentence names "kg m/s", "frame" and "no foot moves"; the return card is not flagged
##  (2) B is not flagged anywhere and its largest braking force is < the 1.5 BW bar (the ledger can say no)
##  (3) CONSERVATION: the linear momentum read at the mid-move of A equals mass x (0.8 m / 0.63 s) within 3 % (the mass model and the 60 Hz
##      differences are right); body mass is the app's (sum of the pieces)
##  (4) the fix: Ease the stop offers a plan that clears the flag (analysis of the plan's clone has no flag at card 2); cards byte-identical
##      after the panel, the offer and the Preview; Accept = ONE undo step; the status names the move times; the scene is no longer flagged
##  (5) Ctrl+Z restores the cards JSON byte for byte
##  (6) a SPIN: a hips yaw of 90 deg in 0.9 s linear, held, is flagged "spin"; the same with the smooth ease is not
##  (7) PLACEMENT: the panel is inside the window, the STOP badge is inside the track at the card's arrival, and in a side view the whole body
##      (head and both feet at the stop) is inside the view and clear of the panel; the screenshot is taken on it
extends SceneTree

const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i36.png"
var fails := 0
var m: Node
var stand: Dictionary
var lunge: Dictionary
var spun: Dictionary


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
	b.fk()
	stand = b.to_dict()
	b.offset += Vector3(0.0, 0.0, -0.8)
	b.fk()
	lunge = b.to_dict()
	b.from_dict(stand)
	b.ang["pelvis"] = (b.ang["pelvis"] as Vector3) + Vector3(0.0, 0.0, 90.0)
	b.fk()
	spun = b.to_dict()
	print("stand offset ", stand.get("offset"), " lunge offset ", lunge.get("offset"))


func cards_for(target: Dictionary, ease: String, move: float) -> Array:
	var c1 := {"name": "go", "pose": target, "move": move, "hold": 0.6}
	if ease != "":
		c1["ease"] = ease
	return [{"name": "stand", "pose": stand, "move": -1.0, "hold": 0.4}, c1, {"name": "back", "pose": stand, "move": 1.2, "hold": 0.2}]


func cards_json() -> String:
	return JSON.stringify(m.S.cards)


func load_cards(cs: Array) -> void:
	m.S.markers = []
	m.S.cards = cs
	m._rebuild_cards()
	m._refresh()


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
	print(Momentum.bar_text())
	var ui = m.ml_ui

	# (1) the dead stop
	load_cards(cards_for(lunge, "linear", 0.9))
	await idle()
	var bef := cards_json()
	var rA: Dictionary = Momentum.analyze(m.S, m.B)
	var rowA: Dictionary = rA["rows"][0]
	print("A: ", rA["msg"], " | mass %.1f kg" % rA["mass"])
	for r in rA["rows"]:
		print("   card %d: f %.2f BW (bar %.1f) p_in %.1f p_out %.1f frames %d flag %s" % [int(r["card"]) + 1, r["f_bw"], r["bar_bw"], r["p_in"], r["p_out"], r["frames"], str(r["flag"])])
	print("   ", rowA["msg"])
	ok(bool(rowA["flag"]) and rowA["kind"] == "linear" and not bool(rA["rows"][1]["flag"]), "(1) A: the lunge card is flagged linear, the return is not")
	ok(float(rowA["p_in"]) >= 60.0 and float(rowA["p_out"]) <= 0.25 * float(rowA["p_in"]) and int(rowA["frames"]) <= 2, "(1) %.1f kg m/s going in, %.1f kg m/s out, in %d frame(s)" % [rowA["p_in"], rowA["p_out"], rowA["frames"]])
	ok(float(rowA["f_bw"]) >= 1.5 * Momentum.BRACE_BW, "(1) the force %.1f BW is >= 1.5 x the %.1f BW bar" % [rowA["f_bw"], Momentum.BRACE_BW])
	var msgA := String(rowA["msg"])
	ok(msgA.contains("kg m/s") and msgA.contains("frame") and msgA.contains("no foot moves"), "(1) the sentence has the numbers: %s" % msgA)

	# (3) conservation
	var sm: Dictionary = Momentum.sample(m.S, m.B)
	var ts: Array = m.S.times()
	var imid := int(round((float(ts[1][0]) + 0.15) * Momentum.HZ))
	var pz: float = absf((sm["P"][imid] as Vector3).z)
	var want: float = float(sm["mass"]) * 0.8 / (0.9 * (1.0 - Scene.LAG))   # the root (level 0) finishes at 70 % of the move: Scene.LAG
	ok(absf(pz - want) <= 0.03 * want, "(3) mid-move momentum %.1f kg m/s vs mass %.1f kg x 1.27 m/s = %.1f kg m/s (3 %%)" % [pz, sm["mass"], want])

	# (2) the eased stop
	load_cards(cards_for(lunge, "", 0.9))
	var rB: Dictionary = Momentum.analyze(m.S, m.B)
	var fmax := 0.0
	for r in rB["rows"]:
		fmax = maxf(fmax, float(r["f_bw"]))
	print("B: ", rB["msg"], " | max braking %.2f BW" % fmax)
	ok(rB["flags"].is_empty() and fmax < Momentum.BRACE_BW, "(2) B (smooth) is not flagged; its largest braking force is %.2f BW (< %.1f BW)" % [fmax, Momentum.BRACE_BW])

	# (4) the fix on A
	load_cards(cards_for(lunge, "linear", 0.9))
	await idle()
	bef = cards_json()
	var u0: int = m.undo.size()
	ui.show()
	await idle(2)
	ok(ui.rep["flags"].size() == 1 and (m.ui_timeline.ml as Array).size() == 1, "(4) the panel lists one stop and the timeline carries one badge")
	ui.offer(1)
	await idle(3)
	ui.preview()
	for i in 6:
		ui.tick(0.1)
	var plan: Dictionary = ui.plan
	print("plan: ", plan["msg"])
	var planrep: Dictionary = Momentum.analyze(plan["scene"], m.B)
	ok(bool(plan["ok"]) and planrep["flags"].is_empty(), "(4) the plan clears the flag (%s)" % planrep["msg"])
	ok(cards_json() == bef and m.undo.size() == u0, "(4) cards byte-identical after the panel, the offer and the Preview; no undo step yet")
	ui.accept()
	await idle()
	var say: String = m.ui_status.text
	print("status: ", say)
	var rAfter: Dictionary = Momentum.analyze(m.S, m.B)
	ok(m.undo.size() == u0 + 1 and cards_json() != bef, "(4) Accept is ONE undo step (%d -> %d) and changed the cards" % [u0, m.undo.size()])
	ok(say.contains(" s to ") and say.contains("BW"), "(4) the status names the move times and the bar")
	ok(rAfter["flags"].is_empty(), "(4) the scene is no longer flagged (%s)" % rAfter["msg"])
	m._undo()
	await idle()
	ok(cards_json() == bef and m.undo.size() == u0, "(5) Ctrl+Z restores the cards JSON byte for byte")

	# (6) a spin
	load_cards(cards_for(spun, "linear", 0.9))
	var rS: Dictionary = Momentum.analyze(m.S, m.B)
	print("spin linear: ", rS["msg"])
	for r in rS["flags"]:
		print("   ", r["msg"])
	load_cards(cards_for(spun, "", 0.9))
	var rS2: Dictionary = Momentum.analyze(m.S, m.B)
	print("spin smooth: ", rS2["msg"], " max tau ", rS2["rows"][0]["tau_ratio"])
	ok(rS["flags"].size() >= 1 and String(rS["flags"][0]["kind"]) == "spin" and rS2["flags"].is_empty(), "(6) the dead-stop spin is flagged 'spin', the smooth one is not")

	# (7) placement, on A at the stop
	load_cards(cards_for(lunge, "linear", 0.9))
	await idle()
	ui.show()
	m.yaw = 90.0
	m.pitch = -4.0
	m.dist = 4.2
	var t_stop: float = float(m.S.times()[1][1])
	m.playhead = t_stop + 0.05
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	var vr: Rect2 = m.get_viewport().get_visible_rect()
	var panel_r: Rect2 = m.ui_find.get_global_rect()
	var inside := false
	for dz in [0.0, 0.4, 0.8, -0.4, -0.8, 1.2, -1.2]:
		m.target = Vector3(0.0, 0.95, -0.3 + dz)
		m._cam()
		await idle(2)
		panel_r = m.ui_find.get_global_rect()
		var pts := [m.B.P["head"], m.B.P["foot_l"], m.B.P["foot_r"], m.B.P["hand_l"]]
		inside = true
		for p in pts:
			var q: Vector2 = m.cam.unproject_position(m._stage_xf() * (p as Vector3))
			inside = inside and vr.grow(-12.0).has_point(q) and not panel_r.has_point(q)
		if inside:
			break
	await idle(3)
	var tl = m.ui_timeline
	var bx: float = tl.x_of(t_stop)
	ok(m.ui_find.visible and vr.encloses(panel_r), "(7) the panel is inside the window (%s of %s)" % [panel_r, vr])
	ok(bx > 0.0 and bx < tl.size.x and tl.size.y > 30.0 and (tl.ml as Array).size() == 1, "(7) the STOP badge sits at the arrival x=%.0f inside the track (%.0f x %.0f)" % [bx, tl.size.x, tl.size.y])
	ok(inside, "(7) in a side view the whole body (head, hand, both feet) is inside the view and clear of the panel")
	root.get_texture().get_image().save_png(SHOT)
	print("I36 ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
