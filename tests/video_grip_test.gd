## godot --headless --path . -s tests/video_grip_test.gd     (round 45, GATES AA3)
## HIS WEAPON IN BOTH HANDS. refs/video/axe_strike_track.json: MediaPipe on 12 s of a real person striking with a long
## two-handed weapon (Nick 10-18's video: Matthew Thomas-Robinson, "Viking Locomotion - Double Handed Axe", 13.5-25.5 s;
## landmarks only, the video is not kept). The tracker sees no weapon; it sees both wrists on it. Against MediaPipe's own
## wrist-to-wrist distance, every 3rd frame:
##   1 the long axe is a weapon (Dane axe: haft 0.9-1.2 m, a bit each side of the tip) and a command
##   2 DENSE (a card a frame): with the long axe picked, |median| <= 6 cm and |p90| <= 10 cm (measured 4.3 / 6.4); the
##     control without it is worse than 8 cm (measured 10.5: the fit put each arm's direction on our own shoulders and
##     arm lengths, so two arms aimed at one point landed apart); every card holds the axe in both hands
##   3 SPARSE (what the import keeps, 6 cards a second): on the cards |median| <= 6 cm (4.7); between them |median| <= 8 cm
##     (6.4; the p90 is reported: two arms blending between keys of a fast swing, the price of editable cards)
##   4 between two cards that both hold it, the second hand SLIDES along the shaft (grip_m at the move's middle is
##     half way), it does not jump at the next card
##   5 the weapon costs at most 2.5x the import without it (measured 11.3 s against 7.3)
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func run(B: Body, P: Dictionary, held: String, dense: bool) -> Dictionary:
	var keep := B.state()
	var t0 := Time.get_ticks_msec()
	var fitted := VideoImport.solve(B, P["frames"], held)
	var V := VideoImport.to_scene(B, fitted, P["fps"], 1, "grip")
	MocapClean.clean(V, B, {})
	if not dense:
		V = VideoImport.thin(V, VideoImport.every_for(V.fps))
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	var both := 0
	for c in V.cards:
		var w: Dictionary = c["pose"].get("weapon", {})
		if String(w.get("kind", "")) == "long_axe" and bool(w.get("two_hand_grip", false)):
			both += 1
	var key_t := {}
	for tt in V.times():
		key_t[snappedf(float(tt[1]), 0.01)] = true
	var on := []
	var off := []
	var fr: Array = P["frames"]
	for i in range(0, fr.size(), 3):
		var w: Array = fr[i]["w"]
		var t := float(fr[i]["t"])
		V.apply(B, t)
		var e := absf((B.P["hand_l"] as Vector3).distance_to(B.P["hand_r"]) - (w[15] as Vector3).distance_to(w[16]))
		(on if key_t.has(snappedf(t, 0.01)) else off).append(e)
	B.set_state(keep)
	var all := on + off
	return {"secs": secs, "cards": V.cards.size(), "both": both, "all": q(all, 0.5), "all90": q(all, 0.9), "on": q(on, 0.5),
		"off": q(off, 0.5), "off90": q(off, 0.9)}


static func q(a: Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[int(p * (b.size() - 1))])


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var B: Body = m.B
	# 1
	var k: Dictionary = Body.KINDS.get("long_axe", {})
	var cmd := false
	for c in m._commands():
		if c["id"] == "weapon_long_axe":
			cmd = true
	ok(float(k.get("len", 0)) >= 0.9 and float(k.get("len", 0)) <= 1.2 and (k.get("head", []) as Array).size() == 2 and cmd,
		"1 long axe: %s, the command %s" % [k, cmd])
	var P := VideoImport.load_file("res://refs/video/axe_strike_track.json")
	# 2 dense
	var dn := run(m.B, P, "", true)
	var da := run(m.B, P, "long_axe", true)
	ok(da["all"] <= 0.06 and da["all90"] <= 0.10 and dn["all"] > 0.08 and da["both"] == da["cards"],
		"2 dense, wrists off MediaPipe's: with the axe |median| %.3f m, |p90| %.3f (bars 0.06, 0.10); without %.3f (> 0.08); %d of %d cards hold it in both hands"
		% [da["all"], da["all90"], dn["all"], da["both"], da["cards"]])
	# 3 sparse
	var sa := run(m.B, P, "long_axe", false)
	ok(sa["on"] <= 0.06 and sa["off"] <= 0.08 and sa["both"] == sa["cards"],
		"3 sparse (%d cards): on the cards |median| %.3f (bar 0.06), between %.3f (bar 0.08), between p90 %.3f (reported)" % [sa["cards"], sa["on"], sa["off"], sa["off90"]])
	# 4 slide
	var S := Scene.new()
	B.set_kind("long_axe")
	B.weapon_to_hand("hand_r")
	B.grip = true
	B.grip_u = 0.3
	S.add("a", B.to_dict())
	B.grip_u = 0.7
	S.add("b", B.to_dict())
	S.natural = false
	S.cards[1]["move"] = 1.0
	S.cards[1]["ease"] = "linear"
	S.cards[0]["hold"] = 0.0
	var mid: Dictionary = S.sample(0.5)
	var gm := float(mid["weapon"].get("grip_m", -1.0))
	ok(absf(gm - 0.5) < 0.02 and bool(mid["weapon"].get("grip", false)), "4 half way between grip_m 0.3 and 0.7 the second hand holds at %.3f (bar 0.5 +- 0.02)" % gm)
	# 5
	ok(da["secs"] <= 2.5 * dn["secs"], "5 the import took %.1f s with the axe, %.1f s without (bar 2.5x)" % [da["secs"], dn["secs"]])
	m.queue_free()
	print("VIDEO GRIP TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
