## godot --path . -s tests/i30_test.gd     (ROADMAP I30: weapon weight, scripts/weapon_torque.gd + weapon_torque_ui.gd; needs a window)
## ONE swing (scenes/combo3.json's ready / wind-up / CONTACT cards, a slow strike, an overshoot card after contact) is read with three weapons
## given by their numbers: a 0.5 kg stick (uniform rod: com 0.5, k 0.289), a 5 kg sledgehammer (com 0.85 L, k 0.2 L). Bars, written before measuring:
##  (1) the 0.5 kg stick: OK (wrist peak <= 12 N m, shoulder <= 75), no weightless flag
##  (2) the same swing with the 5 kg sledgehammer: flagged "over" (peak/max > 1) at the wrist AND the shoulder
##  (3) its fix: a COPY whose peaks are <= the maxima, the swing before contact longer, the original scene's JSON byte-identical
##  (4) an INSTANT STOP (the strike eased "in", so it arrives at full speed): the stick is flagged instant_stop + weightless; the fix removes it
##  (5) no wind-up (the wind-up card deleted): flagged no_windup; the fix adds an 'anticipation' card and the wind-up is then >= 15 % of the strike
##  (6) in the app: the panel lists the sledge swing with a wrist and a shoulder bar (drawn inside the window, red past the maximum); the scene's
##      JSON is untouched by Show, Work out a fix and Preview; Accept is ONE undo step and Ctrl+Z restores the cards byte for byte
extends SceneTree

var fails := 0
var t_mark := 0
var m: Node
const STICK := {"mass": 0.5, "len": 0.9, "com": 0.5, "k": 0.289}
const SLEDGE := {"mass": 5.0, "len": 0.9, "com": 0.85, "k": 0.2}
const T_STRIKE := 0.8


func ok(c: bool, what: String) -> void:
	what += "  [%d ms]" % (Time.get_ticks_msec() - t_mark)
	t_mark = Time.get_ticks_msec()
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func swing(ease := "", windup := true) -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var B := DistanceKeeper.new_body()
	S.cards = S.cards.slice(0, 4)   # ready, wind-up, CONTACT, follow-through
	S.cards[1]["move"] = 0.6
	S.cards[1]["hold"] = 0.1
	S.cards[2]["move"] = T_STRIKE
	S.cards[2]["hold"] = 0.1
	if ease != "":
		S.cards[2]["ease"] = ease
	S.cards[3]["move"] = 0.6
	S.cards[3]["hold"] = 0.2
	# an overshoot after contact, worked from the cards themselves (the combo's own follow-through card lifts the bat away, not on)
	var over := WeaponTorque._extrapolate(B, S.cards[2]["pose"], S.cards[1]["pose"], 0.35)
	S.cards.insert(3, {"name": "overshoot", "pose": over, "move": 0.5, "hold": 0.0})
	if not windup:
		S.cards.remove_at(1)
	S.markers = []
	return S


func cj(S: Scene) -> String:
	return JSON.stringify(S.cards)


func strike_index(S: Scene) -> int:
	for i in S.cards.size():
		if String(S.cards[i]["name"]) == "CONTACT":
			return i
	return -1


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	t_mark = Time.get_ticks_msec()
	var B := DistanceKeeper.new_body()
	var stick := WeaponTorque.profile("metal_bat", STICK)
	var sledge := WeaponTorque.profile("metal_bat", SLEDGE)
	print("       stick I_grip %.3f kg m2 (%s)" % [stick["i_grip"], stick["src"]])
	print("       sledge I_grip %.3f kg m2 (%s)" % [sledge["i_grip"], sledge["src"]])

	# (1) the stick
	var S1 := swing()
	var j1 := cj(S1)
	var r1 := WeaponTorque.analyze(S1, B, 2, stick)
	print("       stick: %s | wind-up %.2f follow %.2f" % [WeaponTorque.describe(r1), r1["windup"], r1["follow"]])
	ok(r1["ok"] and float(r1["wrist"][0]) <= WeaponTorque.WRIST_MAX and float(r1["shoulder"][0]) <= WeaponTorque.SHOULDER_MAX,
		"(1) 0.5 kg stick: OK, wrist %.1f N m, shoulder %.1f N m" % [r1["wrist"][0], r1["shoulder"][0]])

	# (2) the sledgehammer
	var r2 := WeaponTorque.analyze(S1, B, 2, sledge)
	print("       sledge: %s" % WeaponTorque.describe(r2))
	ok(r2["over"] and float(r2["wrist"][0]) > WeaponTorque.WRIST_MAX and float(r2["shoulder"][0]) > WeaponTorque.SHOULDER_MAX,
		"(2) 5 kg sledgehammer: over the maximum, wrist %.0f / %.0f, shoulder %.0f / %.0f N m" % [r2["wrist"][0], WeaponTorque.WRIST_MAX, r2["shoulder"][0], WeaponTorque.SHOULDER_MAX])
	ok(float(r2["wrist"][0]) > 5.0 * float(r1["wrist"][0]), "(2) and it needs well over 5x the stick's wrist torque (%.1fx)" % (float(r2["wrist"][0]) / float(r1["wrist"][0])))

	# (3) its fix
	var f3 := WeaponTorque.fix(S1, B, r2)
	var a3: Dictionary = f3["after"]
	print("       fix: %s" % f3["msg"])
	ok(f3["ok"] and float(a3["ratio"]) <= 1.0 and float(a3["stop_ratio"]) <= 1.0,
		"(3) fixed: wrist %.1f, shoulder %.1f N m (ratios %.2f / %.2f)" % [a3["wrist"][0], a3["shoulder"][0], a3["ratio"], a3["stop_ratio"]])
	ok(float(a3["windup_s"]) > float(r2["windup_s"]) + 0.2, "(3) the swing before contact is longer: %.2f -> %.2f s" % [r2["windup_s"], a3["windup_s"]])
	ok(cj(S1) == j1, "(3) the original scene's cards are byte-identical after the fix was worked out")

	# (4) instant stop
	var S4 := swing("in")
	var r4 := WeaponTorque.analyze(S4, B, 2, stick)
	print("       stick eased in: %s (stop %.2f x, early %.2f x)" % [WeaponTorque.describe(r4), r4["stop_ratio"], r4["early_ratio"]])
	ok(r4["instant_stop"] and r4["weightless"] and not r4["no_windup"], "(4) a stick that arrives at full speed: instant stop flagged, weightless")
	var f4 := WeaponTorque.fix(S4, B, r4)
	ok(f4["ok"] and not f4["after"]["instant_stop"] and f4["after"]["ratio"] <= 1.0 and not (f4["scene"] as Scene).cards[2].has("ease"),
		"(4) the fix eases the stop (ease removed): stop ratio %.2f -> %.2f; steps: %s" % [r4["stop_ratio"], f4["after"]["stop_ratio"], f4["steps"]])

	# (5) no wind-up
	var S5 := swing("", false)
	var i5 := strike_index(S5)
	var r5 := WeaponTorque.analyze(S5, B, i5, stick)
	print("       no wind-up: %s (wind-up %.2f)" % [WeaponTorque.describe(r5), r5["windup"]])
	ok(r5["no_windup"] and r5["weightless"], "(5) the wind-up card deleted: no_windup flagged (back %.0f%% of the strike)" % (100.0 * r5["windup"]))
	var f5 := WeaponTorque.fix(S5, B, r5)
	var c5 := (f5["scene"] as Scene).cards
	ok(f5["ok"] and String(c5[i5]["name"]) == "anticipation" and not f5["after"]["no_windup"],
		"(5) the fix adds an anticipation card (%.2f s): wind-up now %.0f%% of the strike (>= 15%%)" % [float(c5[i5]["move"]), 100.0 * f5["after"]["windup"]])

	# (6) in the app
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	var Sx := swing()
	m.S.cards = Sx.cards.duplicate(true)
	m.S.markers = []
	m._rebuild_cards()
	m._refresh()
	await idle()
	var ui = m.wt_ui
	ui.override = SLEDGE
	var before := cj(m.S)
	var u0: int = m.undo.size()
	ui.show()
	await idle()
	ok(ui.rows.size() == 1 and not ui.rows[0]["r"]["ok"], "(6) the panel lists the one swing, flagged")
	var bw: Control = m.ui_find_list.find_child("wt_bar_wrist_1", true, false)
	var bs: Control = m.ui_find_list.find_child("wt_bar_shoulder_1", true, false)
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var inside: bool = bw != null and bs != null and Rect2(Vector2.ZERO, vp).encloses(bw.get_global_rect()) and Rect2(Vector2.ZERO, vp).encloses(bs.get_global_rect()) \
		and bw.get_global_rect().size.x > 100.0 and m.ui_find.visible
	ok(inside, "(6) PLACEMENT: a wrist bar and a shoulder bar are drawn inside the window (%s)" % [bw.get_global_rect() if bw != null else "missing"])
	# (7) two numbers for one effect agree: the bar label's N m equals the verdict text's N m, for the wrist and the shoulder
	var tx: Label = m.ui_find_list.find_child("wt_text_1", true, false)
	var rx := RegEx.create_from_string("([0-9]+) N m at the (wrist|shoulder)")
	var from_text := {}
	for mt in rx.search_all(tx.text if tx != null else ""):
		from_text[mt.get_string(2)] = int(mt.get_string(1))
	var from_bar := {}
	for pr in [["wrist", bw], ["shoulder", bs]]:
		var lab: Label = (pr[1] as Node).get_child((pr[1] as Node).get_child_count() - 1)
		from_bar[pr[0]] = int(lab.text.split(" /")[0])
	print("       bar labels %s, verdict text %s, raw swing-only shoulder peak %.0f" % [from_bar, from_text, float(ui.rows[0]["r"]["shoulder"][0])])
	ok(from_text.size() == 2 and from_bar == from_text, "(7) the bar label equals the verdict text number (wrist %s/%s, shoulder %s/%s N m)" % [from_bar.get("wrist"), from_text.get("wrist"), from_bar.get("shoulder"), from_text.get("shoulder")])
	ui.fix(0)
	await idle()
	ui.preview(0)
	await idle(2)
	ok(cj(m.S) == before and m.undo.size() == u0, "(6) Show, Work out a fix and Preview leave the cards and the undo stack untouched")
	root.get_texture().get_image().save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/i30.png")
	ui.pv = null
	ui.accept(0)
	await idle()
	var changed := cj(m.S) != before
	ok(changed and m.undo.size() == u0 + 1, "(6) Accept: the cards changed (%d -> %d) and it is ONE undo step" % [Sx.cards.size(), m.S.cards.size()])
	var after_row: Dictionary = ui.rows[0]["r"]
	ok(after_row["ok"] or float(after_row["ratio"]) <= 1.0, "(6) after Accept the panel reads the swing again: ratio %.2f" % after_row["ratio"])
	m._undo()
	await idle()
	ok(cj(m.S) == before, "(6) Ctrl+Z restores the cards byte for byte")

	print("RESULT i30: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
