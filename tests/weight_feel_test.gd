## godot --path . -s tests/weight_feel_test.gd     (ROADMAP 40: weight feel, scripts/weight_feel.gd; needs a window)
## Same swing (scenes/combo3.json, hit marker on its CONTACT card) with a 0.9 kg bat, a 2.5 kg hammer, a 0.3 kg dagger.
## Bars, written before measuring:
##  (1) inertia about the shoulder ordered dagger < bat < hammer, and equal to m r^2 + I_cm worked by hand here
##  (2) wind-up and recovery durations ordered by inertia (dagger < bat < hammer) and each equal to the bat's x (I / I_bat)^0.27
##      (Cross & Bower 2006, V = C / I^n, n = 0.27; time over a fixed arc goes as 1/V) within 10 %
##  (3) the contact card unchanged: pose, hold, index; every card's pose untouched; the hit marker still on the contact card
##  (4) running it again changes nothing (refused, named); hammer then dagger lands where dagger straight from the bat does (3 %)
##  (5) no hit marker / no weapon: refused with a next step, nothing changes
##  (6) in the app: the command is ONE undo step and one Ctrl+Z puts every card back byte for byte; the file keeps weight_i
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## combo3 with the hit marker on card 3 (CONTACT) and the contact card holding weapon `kind`
func fresh(kind: String, marker := true) -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var w: Dictionary = S.cards[2]["pose"]["weapon"]
	w["kind"] = kind
	if marker:
		Markers.add(S.markers, float(S.times()[2][1]), "hit", "hit")
	return S


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var B: Body = m.B

	# (1) inertia by hand: reach = 0.6 x hand + forearm + upper arm of the rest skeleton
	var reach := WeightFeel.reach(B)
	var I := {}
	for kind in ["dagger", "metal_bat", "long_hammer"]:
		var k: Dictionary = Body.KINDS[kind]
		var L: float = k["len"]
		var hl: float = k["handle"] if float(k["handle"]) >= 0.0 else L + float(k["handle"])
		var r := reach + float(k["com"]) * L - minf(0.18, 0.5 * hl)
		var by_hand := float(k["mass"]) * r * r + float(k["mass"]) * pow(float(k["k"]) * L, 2.0)
		I[kind] = WeightFeel.inertia(B, kind)["i"]
		ok(absf(float(I[kind]) - by_hand) < 1e-9, "(1) %s: m %.2f kg, I about the shoulder %.3f kg m2 = m r^2 + I_cm by hand (%.3f)" % [kind, k["mass"], I[kind], by_hand])
	ok(I["dagger"] < I["metal_bat"] and I["metal_bat"] < I["long_hammer"], "(1) ordered dagger %.3f < bat %.3f < hammer %.3f" % [I["dagger"], I["metal_bat"], I["long_hammer"]])

	# (2) + (3) the three swings
	var base := fresh("metal_bat")
	var c := WeightFeel.contact_card(base)
	ok(c == 2, "contact card found from the hit marker: card %d (%s)" % [c + 1, base.cards[c]["name"]])
	var w0 := WeightFeel.windup_s(base, c)
	var r0 := WeightFeel.recovery_s(base, c)
	var res := {}
	for kind in ["dagger", "metal_bat", "long_hammer"]:
		var S := fresh(kind)
		var poses := S.cards.map(func(x): return JSON.stringify(x["pose"]))
		var cdict := JSON.stringify(S.cards[c]["pose"]) + str(S.cards[c]["hold"]) + str(S.cards[c]["name"])
		var out := WeightFeel.apply(S, B)
		var wu := WeightFeel.windup_s(S, c)
		var rc := WeightFeel.recovery_s(S, c)
		res[kind] = [wu, rc]
		var want := pow(float(I[kind]) / float(I["metal_bat"]), 0.27)
		print("     %-12s wind-up %.3f s (x%.3f, cited relation x%.3f)  recovery %.3f s (x%.3f)" % [kind, wu, wu / w0, want, rc, rc / r0])
		ok(absf(wu / w0 / want - 1.0) < 0.10 and absf(rc / r0 / want - 1.0) < 0.10,
			"(2) %s: wind-up x%.3f and recovery x%.3f of the bat's, cited x%.3f, within 10 %%" % [kind, wu / w0, rc / r0, want])
		var arrive := float(S.times()[c][1])
		ok(JSON.stringify(S.cards[c]["pose"]) + str(S.cards[c]["hold"]) + str(S.cards[c]["name"]) == cdict,
			"(3) %s: the contact card's pose, hold and name are as they were (%s)" % [kind, "retimed" if out["ok"] else "the reference: nothing to do"])
		var allp := true
		for i in S.cards.size():
			allp = allp and JSON.stringify(S.cards[i]["pose"]) == poses[i]
		ok(allp, "(3) %s: all %d poses byte-identical; contact arrival moved %+.3f s (= the wind-up change %+.3f)" % [kind, S.cards.size(), arrive - float(base.times()[c][1]), wu - w0])
	ok(res["dagger"][0] < res["metal_bat"][0] and res["metal_bat"][0] < res["long_hammer"][0], "(2) wind-up ordered by inertia: dagger %.3f < bat %.3f < hammer %.3f s" % [res["dagger"][0], res["metal_bat"][0], res["long_hammer"][0]])
	ok(res["dagger"][1] < res["metal_bat"][1] and res["metal_bat"][1] < res["long_hammer"][1], "(2) recovery ordered by inertia: dagger %.3f < bat %.3f < hammer %.3f s" % [res["dagger"][1], res["metal_bat"][1], res["long_hammer"][1]])

	# (4) idempotent, and by ratio
	var H := fresh("long_hammer")
	WeightFeel.apply(H, B)
	var hs := JSON.stringify(H.cards)
	var again := WeightFeel.apply(H, B)
	ok(not again["ok"] and JSON.stringify(H.cards) == hs and String(again["msg"]).contains("change the weapon"), "(4) run twice: refused (%s), cards unchanged" % again["msg"].left(70))
	H.cards[c]["pose"]["weapon"]["kind"] = "metal_bat"
	WeightFeel.apply(H, B)
	var wd := WeightFeel.windup_s(H, c)
	ok(absf(wd / w0 - 1.0) < 0.03, "(4) hammer then back to the bat: wind-up %.3f s vs the bat's original %.3f s (3 %%; one run never moves more than x%.1f / x%.1f, so hammer to dagger takes two)" % [wd, w0, WeightFeel.FMIN, WeightFeel.FMAX])

	# (5) refusals
	var N1 := fresh("long_hammer", false)
	var n1 := JSON.stringify(N1.cards)
	var r1 := WeightFeel.apply(N1, B)
	ok(not r1["ok"] and JSON.stringify(N1.cards) == n1 and String(r1["msg"]).contains("hit marker"), "(5) no hit marker: refused, \"%s\"" % String(r1["msg"]).left(80))

	# (6) the app: one undo step, byte-for-byte undo, the file keeps the key
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	m.S.cards[2]["pose"]["weapon"]["kind"] = "long_hammer"
	Markers.add(m.S.markers, float(m.S.times()[2][1]), "hit", "hit")
	var before := JSON.stringify(m.S.cards)
	var mk_before: Array = m.S.markers.duplicate(true)
	var u0: int = m.undo.size()
	m._weight_feel()
	await idle()
	ok(m.undo.size() == u0 + 1 and JSON.stringify(m.S.cards) != before, "(6) the command is one undo step (%d -> %d) and retimed the cards" % [u0, m.undo.size()])
	var hit_t := float(m.S.markers[0]["t"])
	var arrive_now := float(m.S.times()[2][1])
	ok(absf(hit_t - arrive_now) < 1e-6 and arrive_now > float(mk_before[0]["t"]), "(6) the hit marker rode with the contact card: %.3f -> %.3f s" % [mk_before[0]["t"], hit_t])
	var d: Dictionary = m.S.to_dict(m.B, false)
	var S2 := Scene.new()
	S2.from_dict(d)
	ok(S2.cards[2].has("weight_i") and absf(float(S2.cards[2]["weight_i"]) - float(m.S.cards[2]["weight_i"])) < 1e-9, "(6) the file keeps weight_i = %.3f kg m2" % float(S2.cards[2]["weight_i"]))
	var shot := root.get_texture().get_image()
	shot.save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/weight.png")
	m._undo()
	await idle()
	ok(JSON.stringify(m.S.cards) == before, "(6) one Ctrl+Z: every card byte for byte as before")

	print("WEIGHT FEEL %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	quit(1 if fails > 0 else 0)
