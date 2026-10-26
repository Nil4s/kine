## godot --path . -s tests/i18_test.gd     (ROADMAP I18: fight distance keeper, scripts/distance_keeper.gd + distance_keeper_ui.gd; needs a window)
## The scene: the hero plays combo3's first two strikes (cards 0-6: the swing at 0.76-0.91 s and the back swing at 1.74-1.89 s; the third strike
## of combo3 is a step in another direction and has no distance at which all three land, measured), fighter 2 stands still (poses/stand.json)
## facing him. D_OK = 1.1 m is the spacing at which both swings land (measured beforehand: 1.0-1.2 m).
## Bars, written before measuring:
##  (1) 0.5 m too far (1.6 m): every strike is flagged OUT OF RANGE (none jammed, none in range); Slide the defender: the root moves 0.5 m
##      +-0.1 toward the attacker, afterwards the tip's closest approach to the target is within 2 cm (|gap| <= 2 cm) at the first strike
##      and the strike is in range; the defender's PLANT SLIDE is under 1 cm (a foot whose ball is within 4 mm of its standing height never moves more than 1 cm from where it came down)
##      while his root has travelled the slide
##  (2) 0.4 m too close (0.7 m): every strike is JAMMED (target within 60 % of the reach); the slide moves him back 0.4 m +-0.1 and the strike is
##      then in range with the target at >= 60 % of the reach; plant slide under 1 cm
##  (3) correctly spaced (1.1 m): all strikes in range; no fix is offered (Slide the defender says so), nothing in the scene changes
##  (4) Preview plays to its end and the scenes' cards are byte-identical before and after
##  (5) Accept is ONE undo step; the slide is in the defender's cards, the attacker's are untouched; after it every strike is in range; Ctrl+Z restores
##      both fighters' cards exactly
##  (6) placement: the timeline holds one colour band per strike inside the track (red/amber for the flagged ones), the panel rows carry the numbers
extends SceneTree

const D_OK := 1.1
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func still(pose: Dictionary) -> Scene:
	var s := Scene.new()
	s.from_dict({"scene": "zz_still", "fps": 30, "cards": [{"name": "a", "pose": pose, "move": -1.0, "hold": 2.0},
		{"name": "b", "pose": pose, "move": 0.5, "hold": 3.0}]})
	return s


## the largest distance a foot on the floor moves from where it landed (m), over the scene's whole time
func plant_slide(D: Scene) -> float:
	var B := DistanceKeeper.new_body()
	var c := D.clone()
	var n := int(ceil(c.length() * 60.0))
	var ys := {"_l": [], "_r": []}
	var ps := {"_l": [], "_r": []}
	for f in n + 1:
		c.apply(B, float(f) / 60.0)
		for sd in ["_l", "_r"]:
			var p: Vector3 = B.P["ball" + sd]
			ys[sd].append(p.y)
			ps[sd].append(p)
	var base := minf(float(ys["_l"][0]), float(ys["_r"][0]))   # the ball joint's height standing on the floor at t = 0
	var worst := 0.0
	for sd in ys:
		var anchor := Vector3.ZERO
		var on := false
		for f in ys[sd].size():
			var down: bool = float(ys[sd][f]) < base + 0.004
			if down and not on:
				anchor = ps[sd][f]
			if down:
				worst = maxf(worst, Vector3(ps[sd][f].x - anchor.x, 0, ps[sd][f].z - anchor.z).length())
			on = down
	return worst


func root_travel(D: Scene) -> float:
	var B := DistanceKeeper.new_body()
	var c := D.clone()
	c.apply(B, 0.0)
	var a: Vector3 = B.P["pelvis"]
	c.apply(B, c.length())
	var b: Vector3 = B.P["pelvis"]
	return Vector3(b.x - a.x, 0, b.z - a.z).length()


func cards_json() -> String:
	return JSON.stringify([m.actors_rt[0]["S"].cards, m.actors_rt[1]["S"].cards, (m.actors_rt[1]["xf"] as Transform3D).origin])


func all_cls(rep: Dictionary, cls: String) -> bool:
	for s in rep["spans"]:
		if s["cls"] != cls:
			return false
	return not (rep["spans"] as Array).is_empty()


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
	m.S.cards = m.S.cards.slice(0, 7)
	m._rebuild_cards()
	var sb := DistanceKeeper.new_body()
	sb.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	sb.ground()
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, 1.6], "yaw": 180.0}, "scene": still(sb.to_dict())})
	m._actors_sync()
	m._refresh()
	await idle()
	ok(m._fighters_on() and m.actor_on == 0, "two fighters, the hero attacks")
	var ui = m.dk_ui

	# (1) too far
	m.actor_place(1, Vector2(0.0, D_OK + 0.5), 180.0)
	ui.show()
	await idle()
	var rep: Dictionary = ui.rep
	for s in rep["spans"]:
		print("       card %d %.2f-%.2f s  %s  reach %.2f m  root gap %.2f m  closest %.1f cm" % [int(s["card"]) + 1, s["t0"], s["t1"], s["cls"], s["reach"], s["root_gap"], float(s["miss"]) * 100.0])
	ok(all_cls(rep, "out") and rep["spans"].size() == 2, "(1) 0.5 m too far: %d strikes, all out of range (%s)" % [rep["spans"].size(), rep["msg"]])
	var before := cards_json()
	ui.select(0)
	var fx: Dictionary = ui.fx
	var af: Dictionary = fx.get("after", {})
	var ps1 := plant_slide(fx["scene"])
	var rt1 := root_travel(fx["scene"])
	print("       slide p = %.3f m, after: closest %.1f cm (%s), root travelled %.3f m, plant slide %.2f cm, defender cards %d -> %d" % [fx["p"], float(af["miss"]) * 100.0, af["cls"], rt1, ps1 * 100.0, m.actors_rt[1]["S"].cards.size(), fx["scene"].cards.size()])
	ok(absf(float(fx["p"]) - 0.5) <= 0.1 and absf(float(af["miss"])) <= 0.02 and af["cls"] == "in", "(1) slide %.0f cm toward the attacker, the tip then reaches the target (%.1f cm, bar 2 cm)" % [float(fx["p"]) * 100.0, float(af["miss"]) * 100.0])
	ok(ps1 < 0.01 and absf(rt1 - absf(float(fx["p"]))) < 0.01, "(1) plant slide %.2f cm (bar 1 cm), the root travelled %.1f cm of the slide's %.1f" % [ps1 * 100.0, rt1 * 100.0, absf(float(fx["p"])) * 100.0])
	var again := DistanceKeeper.analyze(m.actors_rt[0]["S"], fx["scene"], m.actors_rt[1]["xf"], 30)
	ok(again["flagged"] == 0, "(1) with the slide on the defender, both strikes are in range (%s)" % again["msg"])

	# (6) placement + screenshot (on this flagged scene, the slide worked out and shown)
	var tl = m.ui_timeline
	await idle(4)
	var inside := true
	for b in tl.dk:
		var x0: float = tl.x_of(float(b["t0"]))
		var x1: float = tl.x_of(float(b["t1"]))
		inside = inside and x0 >= 0.0 and x1 <= tl.size.x and x1 > x0
	var rows := 0
	for c in m.ui_find_list.get_children():
		if c is HBoxContainer and c.get_child_count() > 0 and c.get_child(0) is Label and String((c.get_child(0) as Label).text).begins_with("card "):
			rows += 1
	ok(tl.dk.size() == rep["spans"].size() and inside and rows == rep["spans"].size() and m.ui_find.visible and m.ui_find_list.find_child("dk_accept", true, false) != null,
		"(6) the timeline holds %d bands inside the track, the panel %d numbered rows with Preview and Accept" % [tl.dk.size(), rows])
	m.yaw = 90.0   # the side view: both fighters in the frame, to the right of the panel
	m.pitch = -4.0
	m.dist = 6.2
	m.target = Vector3(0.0, 0.9, 1.6)
	m._cam()
	m.playhead = 0.9
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	await idle(4)
	root.get_texture().get_image().save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/i18.png")

	# (4) preview
	ui.preview()
	var ticks := 0
	while ui.pv != null and ticks < 900:
		await process_frame
		ticks += 1
	ok(ui.pv == null and ticks > 5 and cards_json() == before, "(4) the preview played %d frames; both fighters' cards are byte-identical" % ticks)

	# (5) accept: one undo, exact
	var u0: int = m.undo.size()
	var hero_before := JSON.stringify(m.actors_rt[0]["S"].cards)
	ui.accept()
	await idle()
	m._actors_sync()
	var changed := cards_json() != before
	var rep2 := DistanceKeeper.analyze(m.actors_rt[0]["S"], m.actors_rt[1]["S"], m.actors_rt[1]["xf"], 30)
	ok(m.undo.size() == u0 + 1 and changed and JSON.stringify(m.actors_rt[0]["S"].cards) == hero_before and rep2["flagged"] == 0,
		"(5) Accept is one undo step (%d -> %d), the attacker's cards untouched, afterwards %s" % [u0, m.undo.size(), rep2["msg"]])
	m._undo()
	await idle()
	m._actors_sync()
	ok(cards_json() == before and m.undo.size() == u0, "(5) Ctrl+Z: both fighters' cards exact")

	# (2) too close
	m.actor_place(1, Vector2(0.0, D_OK - 0.4), 180.0)
	ui.show()
	await idle()
	rep = ui.rep
	for s in rep["spans"]:
		print("       card %d %.2f-%.2f s  %s  reach %.2f m  root gap %.2f m (60%% = %.2f)" % [int(s["card"]) + 1, s["t0"], s["t1"], s["cls"], s["reach"], s["root_gap"], 0.6 * float(s["reach"])])
	ok(all_cls(rep, "jammed") and rep["spans"].size() == 2, "(2) 0.4 m too close: all %d strikes jammed (%s)" % [rep["spans"].size(), rep["msg"]])
	ui.select(0)
	fx = ui.fx
	af = fx.get("after", {})
	var ps2 := plant_slide(fx["scene"])
	var rt2 := root_travel(fx["scene"])
	print("       slide p = %.3f m, after: %s, gap at start %.2f m of reach %.2f, root travelled %.3f m, plant slide %.2f cm" % [fx["p"], af["cls"], af["root_gap"], af["reach"], rt2, ps2 * 100.0])
	ok(absf(float(fx["p"]) + 0.4) <= 0.1 and af["cls"] == "in" and float(af["root_gap"]) >= 0.6 * float(af["reach"]),
		"(2) slid back %.0f cm; the strike is in range with the target at %.0f%% of the reach" % [-float(fx["p"]) * 100.0, float(af["root_gap"]) / float(af["reach"]) * 100.0])
	ok(ps2 < 0.01 and absf(rt2 - absf(float(fx["p"]))) < 0.01, "(2) plant slide %.2f cm (bar 1 cm), root travelled %.1f cm" % [ps2 * 100.0, rt2 * 100.0])

	# (3) correct spacing
	m.actor_place(1, Vector2(0.0, D_OK), 180.0)
	ui.show()
	await idle()
	rep = ui.rep
	for s in rep["spans"]:
		print("       card %d %.2f-%.2f s  %s  reach %.2f m  root gap %.2f m  closest %.1f cm" % [int(s["card"]) + 1, s["t0"], s["t1"], s["cls"], s["reach"], s["root_gap"], float(s["miss"]) * 100.0])
	var u1: int = m.undo.size()
	var c1 := cards_json()
	ui.select(0)
	var fx3 := DistanceKeeper.fix(m.actors_rt[0]["S"], m.actors_rt[1]["S"], m.actors_rt[1]["xf"], 30, 0, rep)
	ok(all_cls(rep, "in") and ui.fx.is_empty() and not fx3["ok"] and m.undo.size() == u1 and cards_json() == c1,
		"(3) correct spacing: all %d strikes in range, no fix offered (%s), nothing changed" % [rep["spans"].size(), fx3["why"]])

	print("I18 FIGHT DISTANCE KEEPER %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
