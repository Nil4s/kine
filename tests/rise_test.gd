## godot --headless --path . -s tests/rise_test.gd     (ROADMAP 94: sit / stand / get up from the floor; helpers in scripts/rise.gd)
## BARS, written before the numbers (the cited sources are the roadmap's; the thresholds are ours unless marked):
##  SIT-TO-STAND, a chair (Props "chair"), Rise.stand_up from the seated pose to standing:
##   (1) seated: the thigh's lowest surface within 2.5 cm of the seat top (the hips rest on the seat).
##   (2) seat-off (key 3 of 0..8 = 3/8 = 0.375 of the rise): trunk flexion 40-50 deg (Schenkman 1990, Riley 1991).
##   (3) COM: inside the support at seat-off by >= 2 cm, and inside (margin > 0) at every key from seat-off to standing.
##   (4) feet: sampled at 60 Hz through the whole rise, each ball within 5 mm of where it stood (no skating).
##   (5) the rise lasts 1.5-2.5 s (the cited total).
##   (6) sit_down: the same keys backwards; the seat-on is card 5 and equals the stand-up's seat-off pose.
##  GET UP FROM THE FLOOR, Rise.get_up (supine, roll to side, hands and knees):
##   (7) no part through the floor by more than 1 cm: at every card, and at 60 Hz through the moves with the scene's
##       grounding OFF (the raw blend; with it on, the check would pass by the grounding lifting the body).
##   (8) kneel: each hand's centre 5 mm from its floor mark; each thigh's lowest point 5 mm from the floor.
##   (9) a sheet of four frames (supine, rolling, on the side, kneel) is printed as FRAME lines (joint capsules).
## The get-up is kneel -> half-kneel -> stand (9 cards: 5 anchors and a blend between each pair).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## a Scene of cards (Scene.add, then the move, hold and plant fields as the app keeps them)
func scene_of(cards: Array, body_floor := false, grounded := true) -> Scene:
	var S := Scene.new()
	S.name = "zz_rise"
	S.natural = false   # in-between keys are solved for a synchronised blend; the per-joint lag would unsync them
	S.floor_body = body_floor   # a get-up lies on its back: its whole body's lowest point on the floor (Scene._ground)
	S.on_floor = grounded
	for c in cards:
		S.add(c["name"], c["pose"])
		var last: Dictionary = S.cards[S.cards.size() - 1]
		last["move"] = c["move"]
		last["hold"] = c["hold"]
		last["plant"] = c["plant"]
		if c.has("ease"):
			last["ease"] = c["ease"]
	return S


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var prop := Props.make("chair", Props.xf_at(Vector3.ZERO, 0.0))
	var seat_top := Rise.seat_of(prop).y

	# ---- SIT-TO-STAND
	var r := Rise.stand_up(B, prop)
	var cards: Array = r["cards"]
	var keys := []
	for c in cards:
		keys.append(c["pose"])

	# (1) the seated card: the thigh's lowest surface against the seat's top
	B.from_dict(keys[0])
	var thigh_low := minf((B.P["thigh_l"] as Vector3).y, (B.E["thigh_l"] as Vector3).y) - float(B.rad["thigh_l"])
	ok(absf(thigh_low - seat_top) < 0.025, "1 seated: the left thigh's lowest surface %.1f cm from the seat top %.2f m (bar 2.5 cm)" % [(thigh_low - seat_top) * 100.0, seat_top])

	# (2) seat-off: the trunk's flexion from the card pose
	B.from_dict(keys[3])
	var tf := Rise.trunk_flex(B)
	ok(tf >= 40.0 and tf <= 50.0, "2 seat-off (card 3): trunk flexion %.1f deg (bar 40-50 deg; Schenkman 1990, Riley 1991)" % tf)

	# (3) the COM against the support: from seat-off to standing, every card
	var margins := []
	for k in range(3, keys.size()):
		B.from_dict(keys[k])
		margins.append(float(Balance.read(B)["margin"]))
	var inside := true
	for m in margins:
		inside = inside and m > 0.0
	ok(margins[0] >= 0.02 - 1e-4 and inside, "3 COM inside the support from seat-off to standing: margins %s cm (seat-off bar 2.0)" % str(margins.map(func(m): return snappedf(m * 100.0, 0.1))))

	# (4) the feet, sampled at 60 Hz through the whole rise (the cards plant the feet)
	var S := scene_of(cards)
	var t_end: float = S.times()[S.cards.size() - 1][1]
	var first := {}
	var slide := 0.0
	var n := int(ceil(t_end * 60.0))
	for i in range(0, n + 1):
		S.apply(B, minf(i / 60.0, t_end))
		for sd in ["_l", "_r"]:
			var b: Vector3 = B.P["ball" + sd]
			if not first.has(sd):
				first[sd] = b
			slide = maxf(slide, Vector2(b.x - (first[sd] as Vector3).x, b.z - (first[sd] as Vector3).z).length())
	ok(slide < 0.005, "4 feet sampled at 60 Hz over %.2f s: the worst ball's creep %.2f mm (bar 5 mm)" % [t_end, slide * 1000.0])

	# (5) duration
	ok(t_end >= 1.5 and t_end <= 2.5, "5 the rise lasts %.2f s (bar 1.5-2.5 s, Schenkman 1990 / Riley 1991 as cited)" % t_end)

	# (6) sit-down: the same keys backwards
	var sd_r := Rise.sit_down(B, prop)
	var sd_cards: Array = sd_r["cards"]
	var same: bool = sd_cards.size() == cards.size() and sd_cards[0]["pose"] == keys[keys.size() - 1] and sd_cards[5]["pose"] == keys[3]
	ok(same, "6 sit_down: %d cards; card 0 is the standing pose, card 5 (the seat-on) is the stand-up's seat-off pose" % sd_cards.size())

	# ---- GET UP FROM THE FLOOR
	var g := Rise.get_up(B, Vector2(0.0, 0.0))
	var gcards: Array = g["cards"]
	var gkeys := []
	for c in gcards:
		gkeys.append(c["pose"])
	var depths: Array = g["report"]["depth"]
	var worst_key := 0.0
	for d in depths:
		worst_key = maxf(worst_key, float(d))
	# (7) the raw blend: the scene's grounding off, sampled at 60 Hz
	var RAW := scene_of(gcards, false, false)   # as the report's scene settings say: no grounding, the lifts are in the cards
	var t_g: float = RAW.times()[RAW.cards.size() - 1][1]
	var worst_s := 0.0
	var worst_t := 0.0
	for i in range(0, int(ceil(t_g * 60.0)) + 1):
		var t := minf(i / 60.0, t_g)
		RAW.apply(B, t)
		var d := Rise.floor_depth(B)
		if d > worst_s:
			worst_s = d
			worst_t = t
	ok(worst_key <= 0.01 and worst_s <= 0.01, "7 floor: the cards' depth at most %.1f mm; the raw blend at 60 Hz through %.1f s, %.1f mm (at %.2f s); bar 10 mm" % [worst_key * 1000.0, t_g, worst_s * 1000.0, worst_t])

	# (8) kneel: the hands on their marks, the thighs on the floor
	B.from_dict(gkeys[g["report"]["anchors"][3]])   # the kneel anchor (the fourth)
	var hand_miss := 0.0
	for sd in ["_l", "_r"]:
		hand_miss = maxf(hand_miss, absf((B.P["hand" + sd] as Vector3).y - Rise.HAND_R))
	var thigh_miss := 0.0
	for sd in ["_l", "_r"]:
		var tl := minf((B.P["thigh" + sd] as Vector3).y, (B.E["thigh" + sd] as Vector3).y) - float(B.rad["thigh" + sd])
		thigh_miss = maxf(thigh_miss, absf(tl))
	ok(hand_miss < 0.005 and thigh_miss < 0.005, "8 kneel: hands %.1f mm, thighs %.1f mm from the floor (bar 5 mm)" % [hand_miss * 1000.0, thigh_miss * 1000.0])

	# (10) COM over the support at each anchor (Rise.support_margin: the app's foot footprints plus the floor contacts)
	var anchor_m := []
	for k in g["report"]["anchors"]:
		B.from_dict(gkeys[k])
		anchor_m.append(snappedf(Rise.support_margin(B), 0.001))
	var com_ok := true
	for m in anchor_m:
		com_ok = com_ok and float(m) >= 0.0
	ok(com_ok, "10 COM over the support at supine, side, side-sit, kneel, half-kneel, stand: margins %s m (bar >= 0)" % str(anchor_m))

	# (9) the sheet: four frames of the get-up, whole body, as joint capsules (printed; the screenshot script reads them)
	var FS := RAW
	var t_f: float = FS.times()[FS.cards.size() - 1][1]
	var frames := [0.0, t_f * 0.25, t_f * 0.5, t_f]
	for t in frames:
		FS.apply(B, t)
		var caps := []
		for j in Body.ORDER:
			if j.begins_with("thumb") or j.begins_with("index") or j.begins_with("middle") or j.begins_with("ring") or j.begins_with("pinky"):
				continue
			var c: Array = B.cap(j)
			caps.append({"j": j, "a": [c[0].x, c[0].y, c[0].z], "b": [c[1].x, c[1].y, c[1].z], "r": B.rad[j]})
		print("FRAME " + JSON.stringify({"t": t, "caps": caps}))
	ok(frames.size() == 4, "9 sheet: %d frames printed (FRAME lines) at t = %s s" % [frames.size(), str(frames)])

	print("RESULT %s (%d fail)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
