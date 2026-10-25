## godot --path . -s tests/easytweak_test.gd     (EASY TWEAK, "monkey brain easy": Faster / Slower / Bigger / Smaller on the strip; needs a window)
## BARS (stated before measuring):
##  1. After a Punch card, the strip shows the four big buttons: Faster, Slower, Bigger, Smaller (eh_faster ... eh_smaller).
##  2. Faster: the scene length x 0.8 (+-2 %). Slower: x 1.25 (+-2 %).
##  3. Bigger: the peak wrist travel (both hands, from their own start, over the clip at 120 Hz through Scene.apply) rises by
##     at least 10 %. Smaller: falls by at least 10 %.
##  4. After Bigger (and Smaller): the lowest sole stays within 2 cm of the floor at every sampled frame (Body.sole_low, |.| < 2 cm).
##  5. Each press is exactly one undo step; Undo restores the length (Faster / Slower) or the wrist travel (Bigger / Smaller) exactly.
##  6. Repeated Faster stops at the limit: a press that changes nothing, no undo step, and the one sentence "That's as fast as it goes.".
##  7. Each press keeps the clip playing (the body is moving after the press).
## The measured numbers are printed (the instrument has to be shown to move: the wrist travel and the length before and after).
extends SceneTree

const FAST_STOP := "That's as fast as it goes."

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func btn(nm: String) -> Button:
	return m.easy.home.strip.find_child(nm, true, false) as Button


func say() -> String:
	return String(m.ui_status.text) if m.ui_status != null else ""


## the peak travel of the two hands (from each hand's own start) over the clip, and the largest sole gap to the floor
func measure() -> Dictionary:
	var L: float = m.S.length()
	var n := maxi(2, int(ceil(L * 120.0)))
	var start := {}
	var peak := 0.0
	var gap := 0.0
	for i in n + 1:
		var t := L * float(i) / float(n)
		m.S.apply(m.B, t)
		for h in ["hand_l", "hand_r"]:
			var p: Vector3 = m.B.P[h]
			if i == 0:
				start[h] = p
			peak = maxf(peak, (p - (start[h] as Vector3)).length())
		gap = maxf(gap, absf(m.B.sole_low()))
	m.S.apply(m.B, 0.0)
	return {"travel": peak, "gap": gap, "len": L}


## one press of a strip button: the undo steps it made, and whether the clip is playing after it
func press(nm: String) -> Dictionary:
	var u0: int = m.undo.size()
	btn(nm).pressed.emit()
	await idle(3)
	return {"undo": m.undo.size() - u0, "playing": m.playing}


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m.easy.set_on(true, false)
	await idle(2)
	m._new_scene()
	await idle(2)
	m.easy.home.panel.find_child("eh_card_3", true, false).pressed.emit()   # Punch
	await idle(4)

	# 1. the strip with the four buttons
	var names := ["eh_faster", "eh_slower", "eh_bigger", "eh_smaller"]
	var have := 0
	for nm in names:
		if btn(nm) != null:
			have += 1
	ok(m.easy.home.shown() == "strip" and have == 4, "1. after Punch the strip shows the four buttons (%d of 4; shown: %s)" % [have, m.easy.home.shown()])
	ok(btn("eh_faster").text == "Faster" and btn("eh_slower").text == "Slower" and btn("eh_bigger").text == "Bigger" and btn("eh_smaller").text == "Smaller",
		"1. the buttons say Faster, Slower, Bigger, Smaller")
	ok(m.S.cards.size() >= 2, "1. the Punch clip has %d cards" % m.S.cards.size())

	var base := measure()
	var u_base: int = m.undo.size()
	print("base: length %.4f s, wrist travel %.2f cm, sole gap %.2f mm" % [base["len"], base["travel"] * 100.0, base["gap"] * 1000.0])

	# 2. Faster x 0.8, one undo step, plays, says
	var r := await press("eh_faster")
	var L1: float = m.S.length()
	var ratio := L1 / float(base["len"])
	ok(absf(ratio - 0.8) <= 0.02 * 0.8, "2. Faster: length %.4f -> %.4f s, x %.4f (want 0.8 +-2 %%)" % [base["len"], L1, ratio])
	ok(r["undo"] == 1, "6. Faster is one undo step (%d)" % r["undo"])
	ok(r["playing"], "7. Faster keeps the clip playing")
	ok(say().begins_with("Faster: the punch now takes "), "2. the say line names it: '%s'" % say())
	await press("eh_faster")  # not counted: a second step, then undo back to base below
	m._undo()
	await idle(3)
	m._undo()
	await idle(3)
	var back := measure()
	ok(absf(float(back["len"]) - float(base["len"])) < 1e-6 and m.undo.size() == u_base, "5. Undo x2 restores the length exactly (%.6f vs %.6f s), undo size %d = %d" % [back["len"], base["len"], m.undo.size(), u_base])

	# 3. Slower x 1.25
	r = await press("eh_slower")
	var L2: float = m.S.length()
	ratio = L2 / float(base["len"])
	ok(absf(ratio - 1.25) <= 0.02 * 1.25, "2. Slower: length %.4f -> %.4f s, x %.4f (want 1.25 +-2 %%)" % [base["len"], L2, ratio])
	ok(r["undo"] == 1 and r["playing"], "5/7. Slower is one undo step and keeps playing (undo %d, playing %s)" % [r["undo"], str(r["playing"])])
	m._undo()
	await idle(3)
	ok(absf(float(measure()["len"]) - float(base["len"])) < 1e-6, "5. Undo restores the length after Slower")

	# 4. Bigger: the wrist travel up, the feet on the floor
	r = await press("eh_bigger")
	var big := measure()
	var tr_ratio := float(big["travel"]) / float(base["travel"])
	print("bigger: wrist travel %.2f -> %.2f cm (x %.3f), sole gap %.2f -> %.2f mm" % [float(base["travel"]) * 100.0, float(big["travel"]) * 100.0, tr_ratio, float(base["gap"]) * 1000.0, float(big["gap"]) * 1000.0])
	ok(tr_ratio >= 1.10, "3. Bigger raises the peak wrist travel by %.1f %% (want >= 10 %%)" % ((tr_ratio - 1.0) * 100.0))
	ok(float(big["gap"]) < 0.02, "4. after Bigger the lowest foot is %.2f mm from the floor at its worst frame (want < 20 mm)" % (float(big["gap"]) * 1000.0))
	ok(r["undo"] == 1 and r["playing"], "5/7. Bigger is one undo step and keeps playing (undo %d)" % r["undo"])
	ok(say().begins_with("Bigger: the punch now moves 20 %"), "2. the say line names it: '%s'" % say())
	m._undo()
	await idle(3)
	var und := measure()
	ok(absf(float(und["travel"]) - float(base["travel"])) < 1e-6, "5. Undo restores the wrist travel exactly (%.6f vs %.6f cm)" % [float(und["travel"]) * 100.0, float(base["travel"]) * 100.0])

	# 5. Smaller: the wrist travel down, the feet on the floor
	r = await press("eh_smaller")
	var sm := measure()
	var sm_ratio := float(sm["travel"]) / float(base["travel"])
	print("smaller: wrist travel %.2f -> %.2f cm (x %.3f), sole gap %.2f mm" % [float(base["travel"]) * 100.0, float(sm["travel"]) * 100.0, sm_ratio, float(sm["gap"]) * 1000.0])
	ok(sm_ratio <= 0.90, "3. Smaller lowers the peak wrist travel by %.1f %% (want >= 10 %%)" % ((1.0 - sm_ratio) * 100.0))
	ok(float(sm["gap"]) < 0.02, "4. after Smaller the lowest foot is %.2f mm from the floor (want < 20 mm)" % (float(sm["gap"]) * 1000.0))
	ok(r["undo"] == 1, "5. Smaller is one undo step (%d)" % r["undo"])
	m._undo()
	await idle(3)

	# 6. repeated Faster stops at the limit with the sentence
	var presses := 0
	var stopped := false
	var L_before := 0.0
	var u_before := 0
	for i in 40:
		L_before = m.S.length()
		u_before = m.undo.size()
		await press("eh_faster")
		presses += 1
		if say() == FAST_STOP:
			stopped = true
			break
	print("faster presses until the stop: %d, length %.4f s" % [presses, m.S.length()])
	ok(stopped and presses > 1, "6. repeated Faster reaches the limit after %d presses and says '%s'" % [presses, FAST_STOP])
	ok(stopped and absf(m.S.length() - L_before) < 1e-9 and m.undo.size() == u_before, "6. the stopped press changes nothing: length and undo size unchanged")
	var again := await press("eh_faster")
	ok(say() == FAST_STOP and int(again["undo"]) == 0 and absf(m.S.length() - L_before) < 1e-9, "6. one more Faster at the limit: the same sentence, no undo step")

	# 7. Smoother with an empty neighbouring card pose (a card whose pose was cleared): no script error, every inner card smoothed
	var n7: int = m.S.cards.size()
	var keep7: Dictionary = (m.S.cards[0]["pose"] as Dictionary).duplicate(true)
	(m.S.cards[0]["pose"] as Dictionary).clear()
	var sm7: Dictionary = EasyTweak.smoothed(m.S, m.B)
	m.S.cards[0]["pose"] = keep7   # put the card back before anything plays it
	ok(n7 >= 3 and sm7.size() == n7 - 2, "7. Smoother next to an empty card pose smooths the %d inner cards (got %d)" % [n7 - 2, sm7.size()])

	m.easy.set_on(false, false)
	await idle(2)
	print("EASYTWEAK TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
