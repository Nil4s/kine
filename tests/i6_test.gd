## godot --path . -s tests/i6_test.gd     (ROADMAP I6: style dial, scripts/style_dial.gd + style_dial_ui.gd; needs a window)
## Bars, written before measuring:
##  (1) the committed SPREAD equals a fresh measurement on scenes/ + moves/ within 5 % (so "+1" is still his clips' 90th percentile)
##  (2) all four sliders at 0: style_cards returns the cards byte-identical; and after moving a slider and putting it back the scene JSON is
##      byte-identical to the one opened
##  (3) tired +1 on combo3: mean joint speed LOWER and mean head height LOWER than neutral, hold share not lower
##  (4) angry +1 on combo3: peak hand speed HIGHER and the joint range (clip_features "range") HIGHER than neutral
##  (5) contacts: for tired +1, angry +1, heavier +1, sneaky +1 and all four at once, every strike card's contact point (weapon tip) at its
##      arrival, through the full Scene.apply, within 1 cm of where it was
##  (6) foot plants: at every card where a ball of the foot was on the floor (< 4 cm), it is within 2 cm of its old place (full Scene.apply
##      at the card's arrival), for tired +1 and angry +1
##  (7) the slider: a drag (value_changed x several, then drag_ended) is ONE undo step; Ctrl+Z restores the cards and the scene JSON exactly
##  (9) HUMAN LIMITS: angry +1 (and all four): every move's peak hand speed (120 Hz, either hand) is at most max(cited human limit
##      11.95 m/s / weapon factor, the same move's NEUTRAL peak); the angry clip's overall peak is reported next to the neutral one
##  (8) PLACEMENT: the picture is composited from three captures of the app (neutral / tired / angry) at the same frame; the body is drawn
##      inside the 3D view in each (the head's screen point is inside the viewport, not at the origin)
extends SceneTree

const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i6b.png"
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _scene_with(S: Scene, cards: Array) -> Scene:
	var c := S.clone()
	c.cards = cards.duplicate(true)
	return c


## the strike cards' contact points and the planted balls at each card's arrival, full pipeline
func _probe(S: Scene, B: Body, cards_idx: Array) -> Dictionary:
	var ts := S.times()
	var tips := {}
	for i in cards_idx:
		S.apply(B, float(ts[i][1]))
		tips[i] = StyleDial.contact_point(B)[0]
	var balls := []
	for i in S.cards.size():
		S.apply(B, float(ts[i][1]))
		balls.append({"l": B.P["ball_l"], "r": B.P["ball_r"]})
	return {"tips": tips, "balls": balls}


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var B: Body = m.B
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	var S: Scene = m.S
	var base: Array = S.cards.duplicate(true)
	var json0 := JSON.stringify(S.to_dict(B, false))
	var cards0 := JSON.stringify(S.cards)

	# (1) the learned spreads
	var db := MotionMatch.build()
	var t0 := Time.get_ticks_msec()
	# only the files the committed SPREAD was built from (StyleDial.SPREAD_CLIPS, with their per-clip numbers): a checkout with a scene
	# deleted or an extra one of Nick's measures the same list. A listed file that is missing is skipped (printed); the fresh spread of
	# the files present is compared with the spread of the COMMITTED numbers of those same files (all present: the committed SPREAD)
	var bf := StyleDial.spread_basis_files()
	if not (bf["missing"] as Array).is_empty():
		print("     NOTE: %d of %d listed files are not in this checkout and are skipped: %s" % [(bf["missing"] as Array).size(), StyleDial.SPREAD_CLIPS.size(), bf["missing"]])
	if not (bf["changed"] as Array).is_empty():
		print("     NOTE: %d listed files differ from the ones SPREAD was built from (md5), measured as they are: %s" % [(bf["changed"] as Array).size(), bf["changed"]])
	var ms := StyleDial.measure_spreads(db, ["res://scenes/"], bf["use"])
	print("     measured on %s in %d ms" % [ms["basis"], Time.get_ticks_msec() - t0])
	ok(ms["basis"]["clips"] == (bf["use"] as Array).size(), "(1) the measurement used exactly the %d listed files that are present (%d clips)" % [(bf["use"] as Array).size(), ms["basis"]["clips"]])
	var cw := []
	for p in bf["use"]:
		cw.append(StyleDial.SPREAD_CLIPS[p])
	var committed := StyleDial.spread_of(cw)
	var allc := StyleDial.spread_of(StyleDial.SPREAD_CLIPS.values())
	for c in ms["clips"]:
		print("       %-20s speed %6.1f deg/s still %.2f sharp %.2f range %5.1f deg flex %5.1f head %.3f m com %.3f m knee %5.1f" % [
			c["name"], c["speed"], c["still"], c["sharp"], c["range"], c["flex"], c["head_h"], c["com_h"], c["knee"]])
	for k in StyleDial.FEATS:
		var a: float = ms["spread"][k]
		var b: float = committed[k]
		print("     spread %-5s measured %.4f   committed (same files) %.4f   committed SPREAD %.4f" % [k, a, b, StyleDial.SPREAD[k]])
		ok(absf(a - b) <= 0.05 * maxf(absf(a), 1e-6) + 1e-4, "(1) %s: committed %.4f vs measured %.4f within 5 %%" % [k, b, a])
		ok(absf(allc[k] - StyleDial.SPREAD[k]) <= 1e-3 * maxf(absf(StyleDial.SPREAD[k]), 1e-6) + 1e-4, "(1) %s: the committed rows give SPREAD %.4f (listed %.4f)" % [k, allc[k], StyleDial.SPREAD[k]])

	# (2) neutral
	var r0 := StyleDial.style_cards(S, B, base, StyleDial.neutral())
	ok(JSON.stringify(r0["cards"]) == cards0, "(2) sliders at 0: the cards are byte-identical")

	# the five styled versions
	var cases := {"tired": {"tired": 1.0}, "angry": {"angry": 1.0}, "heavier": {"heavier": 1.0}, "sneaky": {"sneaky": 1.0},
		"all": {"heavier": 0.5, "tired": -0.5, "angry": 0.5, "sneaky": 1.0}}
	var made := {}
	for k in cases:
		var v := StyleDial.neutral()
		for s in cases[k]:
			v[s] = cases[k][s]
		var t1 := Time.get_ticks_msec()
		made[k] = StyleDial.style_cards(S, B, base, v)
		print("     %-8s %d ms  drop %.3f m  feet err %.4f m  tip err %s  move x%s hold x%.2f" % [k, Time.get_ticks_msec() - t1, made[k]["report"]["drop_m"],
			made[k]["report"]["feet_err_m"], made[k]["report"]["tip_err_m"], (made[k]["report"]["timing"]["move_factor"] as Dictionary).values().slice(0, 3), made[k]["report"]["timing"]["hold_factor"]])

	# (3) tired, (4) angry
	var f_n := StyleDial.scene_features(S, B)
	var h_n := StyleDial.hand_stats(S, B)
	var S_t := _scene_with(S, made["tired"]["cards"])
	var S_a := _scene_with(S, made["angry"]["cards"])
	var f_t := StyleDial.scene_features(S_t, B)
	var f_a := StyleDial.scene_features(S_a, B)
	var h_t := StyleDial.hand_stats(S_t, B)
	var h_a := StyleDial.hand_stats(S_a, B)
	print("     neutral: speed %.1f deg/s still %.2f range %.1f flex %.1f head %.3f m | hand peak %.2f m/s reach %.3f m" % [f_n["speed"], f_n["still"], f_n["range"], f_n["flex"], f_n["head_h"], h_n["peak"], h_n["reach"]])
	print("     tired  : speed %.1f deg/s still %.2f range %.1f flex %.1f head %.3f m | hand peak %.2f m/s reach %.3f m" % [f_t["speed"], f_t["still"], f_t["range"], f_t["flex"], f_t["head_h"], h_t["peak"], h_t["reach"]])
	print("     angry  : speed %.1f deg/s still %.2f range %.1f flex %.1f head %.3f m | hand peak %.2f m/s reach %.3f m" % [f_a["speed"], f_a["still"], f_a["range"], f_a["flex"], f_a["head_h"], h_a["peak"], h_a["reach"]])
	ok(f_t["speed"] < f_n["speed"] and f_t["head_h"] < f_n["head_h"] and f_t["still"] >= f_n["still"],
		"(3) tired +1: speed %.1f < %.1f deg/s, head %.3f < %.3f m, hold share %.2f >= %.2f" % [f_t["speed"], f_n["speed"], f_t["head_h"], f_n["head_h"], f_t["still"], f_n["still"]])
	ok(h_a["peak"] > h_n["peak"] and f_a["range"] > f_n["range"],
		"(4) angry +1: peak hand speed %.2f > %.2f m/s, joint range %.1f > %.1f deg" % [h_a["peak"], h_n["peak"], f_a["range"], f_n["range"]])

	# (5) contacts and (6) planted feet, through the full pipeline
	var contacts: Array = made["tired"]["report"]["contacts"]
	print("     strike cards: %s" % [contacts])
	var P0 := _probe(S, B, contacts)
	for k in cases:
		var Sx := _scene_with(S, made[k]["cards"])
		var Px := _probe(Sx, B, contacts)
		var worst := 0.0
		for i in contacts:
			worst = maxf(worst, ((Px["tips"][i] as Vector3) - (P0["tips"][i] as Vector3)).length())
		ok(worst <= 0.01, "(5) %s: contact points move at most %.1f mm (bar 10 mm), %d strike cards" % [k, worst * 1000.0, contacts.size()])
		if k == "tired" or k == "angry":
			var fw := 0.0
			var np := 0
			for i in S.cards.size():
				for s in ["l", "r"]:
					var b0: Vector3 = P0["balls"][i][s]
					if b0.y < 0.04:
						np += 1
						fw = maxf(fw, ((Px["balls"][i][s] as Vector3) - b0).length())
			ok(np > 0 and fw <= 0.02, "(6) %s: %d planted balls, worst %.1f mm from their old place (bar 20 mm)" % [k, np, fw * 1000.0])

	# (9) human limits
	var pk_n := StyleDial.move_peaks(S, B)
	for k in ["angry", "all"]:
		var Sx2 := _scene_with(S, made[k]["cards"])
		var pk := StyleDial.move_peaks(Sx2, B)
		var viol := []
		var worst_peak := 0.0
		for q in pk.size():
			var lim := maxf(float(pk[q]["limit"]), float(pk_n[q]["peak"]))
			worst_peak = maxf(worst_peak, float(pk[q]["peak"]))
			print("       %-5s card %d travel %.3f m  dur %.3f -> %.3f s  peak %.2f (neutral %.2f) m/s  limit %.2f" % [k, pk[q]["card"], pk[q]["travel"], pk_n[q]["dur"], pk[q]["dur"], pk[q]["peak"], pk_n[q]["peak"], lim])
			if float(pk[q]["peak"]) > lim * 1.02 + 0.05:
				viol.append(pk[q]["card"])
		ok(viol.is_empty(), "(9) %s: capped peak hand speed %.2f m/s (neutral clip %.2f); moves over their limit: %s; capped: %s" % [k, worst_peak, h_n["peak"], viol, made[k]["report"]["capped"].keys()])
		ok(float(StyleDial.hand_stats(Sx2, B)["peak"]) > 0.0, "(9) %s: hand_stats peak %.2f m/s" % [k, float(StyleDial.hand_stats(Sx2, B)["peak"])])

	# (7) the slider, through the panel
	m.sd_ui.show()
	await idle()
	var sl: HSlider = m.ui_find_list.find_child("sd_tired", true, false)
	ok(sl != null and m.ui_find.visible and m.get_viewport().get_visible_rect().encloses(m.ui_find.get_global_rect()), "(7) the dial is shown inside the window with a Tired slider")
	var u0: int = m.undo.size()
	sl.drag_started.emit()
	for x in [0.2, 0.5, 0.8, 1.0]:
		sl.value = x
	ok(m.undo.size() == u0 and JSON.stringify(m.S.cards) == cards0, "(7) during the drag nothing is written")
	sl.drag_ended.emit(true)
	await idle()
	ok(m.undo.size() == u0 + 1, "(7) the release is ONE undo step (%d -> %d)" % [u0, m.undo.size()])
	ok(JSON.stringify(m.S.cards) != cards0 and absf(float(m.S.move_time(1)) - float(S.move_time(1))) >= 0.0, "(7) the clip changed")
	var after_cards := JSON.stringify(m.S.cards)
	print("     slider commit: %.0f ms" % m.sd_ui.last_ms)
	m._undo()
	await idle(2)
	ok(JSON.stringify(m.S.cards) == cards0 and JSON.stringify(m.S.to_dict(m.B, false)) == json0, "(7) Ctrl+Z: cards and scene JSON exact")

	# (2b) a slider moved and put back: byte-identical, via the panel
	m.sd_ui.show()
	await idle()
	var sl2: HSlider = m.ui_find_list.find_child("sd_angry", true, false)
	m.sd_ui.set_value("angry", 0.7)
	await idle()
	m.sd_ui.set_value("angry", 0.0)
	await idle()
	ok(JSON.stringify(m.S.cards) == cards0 and JSON.stringify(m.S.to_dict(m.B, false)) == json0, "(2) angry 0.7 then back to 0: cards and scene JSON byte-identical")
	m._undo()
	m._undo()
	await idle(2)

	# (8) the picture: neutral / tired / angry at the same frame (0.91 s) and at each one's own CONTACT arrival
	m.ui_find.visible = false   # the Check panel covered the bodies in the first picture
	await idle(2)
	var shots := {}
	var heads := {}
	var arrivals := {}
	var order := [["neutral", cards0], ["tired", JSON.stringify(made["tired"]["cards"])], ["angry", JSON.stringify(made["angry"]["cards"])]]
	for pair in order:
		m.S.cards = JSON.parse_string(pair[1]) if false else _revive(pair[0], made, base)
		m._rebuild_cards()
		await idle(2)
		var rows := []
		var ts: Array = m.S.times()
		for t in [0.91, float(ts[2][1])]:
			m.playhead = t
			m._ps().apply(m.B, t)
			m._refresh()
			await idle(3)
			rows.append(root.get_texture().get_image())
			var cam: Camera3D = m.get_viewport().get_camera_3d()
			if cam != null:
				heads[pair[0] + str(t)] = cam.unproject_position(m.B.P["head"])
		shots[pair[0]] = rows
		arrivals[pair[0]] = float(ts[2][1])
	_composite(shots)
	var vp := m.get_viewport().get_visible_rect()
	var placed := true
	for k in heads:
		var p: Vector2 = heads[k]
		placed = placed and vp.has_point(p) and p.length() > 20.0
	ok(not m.ui_find.visible, "(8) the Check panel is closed for the captures")
	ok(heads.size() >= 5 and placed, "(8) the head is drawn inside the window in all captures (neutral CONTACT is 0.91 s, so 5 distinct times): %s" % [heads])
	print("     CONTACT arrives at %s s" % [arrivals])
	m.S.cards = base.duplicate(true)
	m._rebuild_cards()

	print("I6 STYLE DIAL %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	quit(1 if fails > 0 else 0)


func _revive(name: String, made: Dictionary, base: Array) -> Array:
	return base.duplicate(true) if name == "neutral" else (made[name]["cards"] as Array).duplicate(true)


## three columns (neutral / tired / angry), two rows (the same time / each one's own CONTACT), cropped to the 3D view
func _composite(shots: Dictionary) -> void:
	var names := ["neutral", "tired", "angry"]
	var first: Image = shots["neutral"][0]
	var W := first.get_width()
	var H := first.get_height()
	var cx0 := int(W * 0.22)
	var cw := int(W * 0.56)
	var ch := int(H * 0.80)
	var out := Image.create(cw * 3, ch * 2, false, Image.FORMAT_RGBA8)
	for c in 3:
		for r in 2:
			var im: Image = shots[names[c]][r]
			im.convert(Image.FORMAT_RGBA8)
			out.blit_rect(im, Rect2i(cx0, int(H * 0.06), cw, ch), Vector2i(c * cw, r * ch))
	out.save_png(SHOT)
	print("     picture: %s  (columns neutral / tired / angry; top row = 0.91 s in all three, bottom row = each one's CONTACT card)" % SHOT)
