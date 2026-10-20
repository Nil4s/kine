## godot --path . -s tests/i34_test.gd     (ROADMAP I34: fatigue, scripts/exertion.gd + exertion_ui.gd; needs a window)
## SYNTHETIC EXCHANGES from real poses (poses/stand.json and a right arm raised to the farthest of seven reaches): fighter 1 throws 20 jabs
## at a CONSTANT speed (0.25 s move, 0.2 s recover, 0.1 s guard; ~14 s), fighter 2 throws 3. Bars, written before measuring:
##  (1) 20 strikes found; late third >= 95 % of the early third's peak fist speed; the fatigue at the late strikes > 0.6; the fatigue at the first
##      strike < 0.3; positive work > 0 and the fatigue never falls while he keeps striking (F at the last strike >= F at the first);
##      flagged STILL FRESH, and the guard flagged too (it dropped < 1 cm)
##  (2) the 3-strike fighter: not flagged ("too few for a verdict"), whatever his fatigue
##  (3) JSON untouched: both fighters' cards byte-identical after the panel, Tire him (the offer) and Preview; Accept = ONE undo step; the status
##      names the numbers (strikes slowed, cm); Ctrl+Z restores both fighters' cards exactly
##  (4) after Tire him: late strike speed <= 90 % of the early speed; the guard dropped >= 1 cm (late vs early); the fighter is no longer flagged;
##      Check has no MUST FIX that it did not have before
##  (5) PLACEMENT: the timeline carries a fatigue strip per fighter inside the track, green at the start and redder at the end; the screenshot is taken on it
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


## a real guard: both fists up at the chin (found by search over the arm angles: each hand within 6 cm of the point 10 cm above the shoulder line,
## 15 cm in front of the shoulder), and the punch: that guard with the right arm thrown to the farthest of seven reaches
func make_poses() -> void:
	var b := DistanceKeeper.new_body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	var base: Dictionary = b.to_dict()
	b.fk()
	var fwd := Vector3.FORWARD
	for sd in ["_l", "_r"]:
		var bestc := INF
		var besta := [Vector3.ZERO, Vector3.ZERO]
		for ax in range(-100, 101, 20):
			for az in range(-60, 61, 20):
				for ay in range(-60, 61, 30):
					for lb in [-130, -110, -90, -70, 70, 90, 110, 130]:
						b.ang["upperarm" + sd] = Vector3(ax, ay, az)
						b.ang["lowerarm" + sd] = Vector3(lb, 0, 0)
						b.fk()
						var sh: Vector3 = b.P["upperarm" + sd]
						var want: Vector3 = sh + Vector3(0.0, 0.10, 0.0) + (b.G["pelvis"] as Quaternion) * fwd * 0.15
						var cst: float = (b.P["hand" + sd] as Vector3).distance_to(want)
						if cst < bestc:
							bestc = cst
							besta = [Vector3(ax, ay, az), Vector3(lb, 0, 0)]
		b.ang["upperarm" + sd] = besta[0]
		b.ang["lowerarm" + sd] = besta[1]
		b.fk()
		print("guard", sd, ": miss %.3f m, hand y %.2f, shoulder y %.2f" % [bestc, (b.P["hand" + sd] as Vector3).y, (b.P["upperarm" + sd] as Vector3).y])
	stand = b.to_dict()
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
	b.ang["lowerarm_r"] = Vector3.ZERO
	b.fk()
	punch_r = b.to_dict()
	print("punch reach %.2f m" % best)


func exchange(n: int) -> Array:
	var cards := [{"name": "guard", "pose": stand, "move": -1.0, "hold": 0.4}]
	for k in n:
		cards.append({"name": "jab", "pose": punch_r, "move": 0.25, "hold": 0.0})
		cards.append({"name": "guard", "pose": stand, "move": 0.2, "hold": 0.1})
	return cards


func cards_json() -> String:
	return JSON.stringify([m.actors_rt[0]["S"].cards, m.actors_rt[1]["S"].cards])


func fails_now() -> int:
	m._check()
	return (m.findings as Array).filter(func(f): return f["sev"] == "FAIL").size()


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
	var S2 := Scene.new()
	S2.from_dict({"scene": "zz_f2", "fps": 30, "cards": exchange(3)})
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, 1.1], "yaw": 180.0}, "scene": S2})
	m._actors_sync()
	m.S.markers = []
	m.S.cards = exchange(20)
	m.actors_rt[1]["S"].cards = exchange(3)
	m._actors_sync()
	m._rebuild_cards()
	m._refresh()
	await idle()
	ok(m._fighters_on(), "two fighters")
	var ui = m.fa_ui
	print("constants: ", Exertion.constants_text())

	# (1) + (2)
	ui.show()
	await idle()
	var r1: Dictionary = ui.reps[0]
	var r2: Dictionary = ui.reps[1]
	var st1: Array = r1["strikes"]
	print("fighter 1: work %.0f J, fmax %.2f, strikes %d, early %.2f late %.2f m/s, f_late %.2f, guard drop %.4f m" % [r1["work"], r1["fmax"], st1.size(), r1.get("early", 0.0), r1.get("late", 0.0), r1.get("f_late", 0.0), r1.get("guard_drop", 0.0)])
	print("  ", r1["msg"])
	print("fighter 2: work %.0f J, fmax %.2f, strikes %d  %s" % [r2["work"], r2["fmax"], r2["strikes"].size(), r2["msg"]])
	ok(st1.size() == 20, "(1) 20 strikes found (%d)" % st1.size())
	ok(float(r1["late"]) >= 0.95 * float(r1["early"]), "(1) late strikes %.2f m/s are %.0f %% of early %.2f (>= 95 %%)" % [r1["late"], 100.0 * float(r1["late"]) / float(r1["early"]), r1["early"]])
	ok(float(r1["f_late"]) > 0.6 and float(st1[0]["F"]) < 0.3 and float(st1[19]["F"]) >= float(st1[0]["F"]), "(1) fatigue first strike %.2f (< 0.3), late %.2f (> 0.6)" % [st1[0]["F"], r1["f_late"]])
	ok(float(r1["work"]) > 0.0, "(1) positive work %.0f J" % r1["work"])
	ok(bool(r1["flag"]) and bool(r1["fresh"]) and bool(r1["high"]), "(1) flagged still fresh and guard high: %s" % r1["msg"])
	ok(not bool(r2["flag"]) and r2["strikes"].size() == 3, "(2) the 3-strike fighter is not flagged: %s" % r2["msg"])

	# (3) JSON untouched until Accept
	var before := cards_json()
	var u0: int = m.undo.size()
	var f1_before := fails_now()
	ui.offer(0)
	await idle(4)
	root.get_texture().get_image().save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/i34.png")
	ui.preview()
	for i in 6:
		ui.tick(0.1)
	ok(cards_json() == before and m.undo.size() == u0, "(3) cards byte-identical after the panel, Tire him and Preview; no undo step yet")
	var plan: Dictionary = ui.plan
	print("plan: ", plan["msg"])
	ok(int(plan["slowed"]) > 0 and int(plan["guards"]) > 0, "(3) the plan slows %d strikes, lowers %d guards, lengthens %d recovers" % [plan["slowed"], plan["guards"], plan["recovers"]])
	ui.accept()
	await idle()
	var say: String = m.ui_status.text
	print("status: ", say)
	ok(m.undo.size() == u0 + 1 and cards_json() != before, "(3) Accept is ONE undo step (%d -> %d) and changed the cards" % [u0, m.undo.size()])
	ok(say.contains("strikes slowed") and say.contains(" cm") and say.contains("recovers"), "(3) the status says the numbers")
	var tired: Dictionary = Exertion.analyze(m.actors_rt[0]["S"], m.actors_rt[0]["B"])
	ok(float(tired["late"]) <= 0.90 * float(tired["early"]), "(4) late strike speed %.2f m/s is %.0f %% of the early %.2f (<= 90 %%)" % [tired["late"], 100.0 * float(tired["late"]) / float(tired["early"]), tired["early"]])
	ok(float(tired.get("guard_drop", 0.0)) >= Exertion.GUARD_DROP, "(4) the guard dropped %.1f cm between the early and the late third (>= 1 cm)" % (100.0 * float(tired.get("guard_drop", 0.0))))
	ok(not bool(tired["flag"]), "(4) no longer flagged: %s" % tired["msg"])
	var f1_after := fails_now()
	ok(f1_after <= f1_before, "(4) Check: MUST FIX %d before, %d after" % [f1_before, f1_after])
	# placement: the strip on the timeline (the tired clip's own strip)
	var tl = m.ui_timeline
	ui.compute()
	ui._panel()
	await idle(4)
	ok(tl.fa_n == 2 and not tl.fa.is_empty(), "(5) the timeline carries a strip per fighter (%d segments)" % tl.fa.size())
	var inside := true
	for b in tl.fa:
		var x0: float = tl.x_of(float(b["t0"]))
		inside = inside and x0 >= -1.0 and x0 <= tl.size.x + 1.0
	ok(inside and tl.size.y > 24.0, "(5) the strip sits inside the track (%.0f x %.0f)" % [tl.size.x, tl.size.y])
	var f1_segs: Array = tl.fa.filter(func(b): return int(b["who"]) == 0)
	var c0: Color = Exertion.color(float(f1_segs[0]["f"]))
	var c1: Color = Exertion.color(float(f1_segs[-1]["f"]))
	ok(c0.g > c0.r and c1.r > c1.g, "(5) green at the start (%s), red at the end (%s)" % [c0.to_html(false), c1.to_html(false)])
	await idle(3)
	m._undo()
	await idle()
	ok(cards_json() == before and m.undo.size() == u0, "(3) Ctrl+Z restores both fighters' cards exactly")
	print("I34 ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
