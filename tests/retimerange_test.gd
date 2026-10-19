## godot --headless --path . -s tests/retimerange_test.gd     (ROADMAP 67; pure data, no window)
## RETIME A RANGE AROUND THE PLAYHEAD (scripts/retime_range.gd). Bars (written before measuring):
##   1 playhead = range start 1.0, range 1.0-3.0 s, 150 %: a part key at p + 0.4 (1.4 s) lands at 1.6 s, within one frame (1/30 s).
##   2 keys before the range (0.5 s, and the start 1.0 s itself) are byte-identical; card 0 (before the range) is byte-identical; card 1 keeps its move (its hold runs into the range: 0.5 -> 0.75).
##   3 a key after the range (4.0 s) moves by exactly the range's length change: 2.0 s x (1.5 - 1) = 1.0 s -> 5.0 s.
##   4 cards: arrivals of card 2 (2.0 s) -> 2.5 s, card 3 (3.0 s) -> 4.0 s, card 4 (4.0 s) -> 5.0 s, each within 1 ms.
##   5 100 %: no-op: the cards and part keys are byte-identical and apply() reports 0 cards.
##   6 playhead mid-range (2.0 s in 1-3 s) at 50 %: key 2.4 -> 2.2, key 4.0 -> 3.5, card 3 arrival 3.0 -> 2.5 (within 1 ms).
##   7 a stretch that would run back over the content before the range is refused (check() names it) and changes nothing.
##   8 the playhead outside the range, and a percent outside 10-1000, are refused.
##   9 a modifier's range_start/range_end move with the warp (2.0 -> 2.0, 2.5 -> 2.25 at 50 % about 2.0), its blend_in halves (0.2 -> 0.1),
##     and a handle's dt inside the range halves (0.4 -> 0.2).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## eight cards: card 0 holds 0.5 s; every card after moves 0.5 s and holds 0.5 s. Arrival of card i = i s, end of its hold = i + 0.5 s
func make() -> Scene:
	var S := Scene.new()
	S.fps = 30
	for i in 8:
		S.cards.append({"name": "c%d" % i, "pose": {}, "move": 0.0 if i == 0 else 0.5, "hold": 0.5})
	S.part_keys = {"lowerarm_r": [
		{"t": 0.5, "v": Vector3(10, 0, 0)},
		{"t": 1.0, "v": Vector3(20, 0, 0)},
		{"t": 1.4, "v": Vector3(30, 0, 0)},
		{"t": 4.0, "v": Vector3(40, 0, 0)},
	]}
	return S


func key_t(S: Scene, joint: String, i: int) -> float:
	return float(S.part_keys[joint][i]["t"])


func _init() -> void:
	# bars 1-4: the playhead at the range start, 150 %
	var S := make()
	var before_keys := var_to_str(S.part_keys)
	var pre := var_to_str(S.part_keys["lowerarm_r"][0])
	var at_start := var_to_str(S.part_keys["lowerarm_r"][1])
	var c0 := var_to_str(S.cards[0])
	var len0 := S.length()
	ok(RetimeRange.check(S, 1.0, 3.0, 1.0, 150.0) == "", "bar 1: 150 % about the range start is allowed")
	var n := RetimeRange.apply(S, 1.0, 3.0, 1.0, 150.0)
	ok(n > 0, "bar 1: cards rewritten (%d)" % n)
	var got := key_t(S, "lowerarm_r", 2)
	ok(absf(got - 1.6) < 1.0 / 30.0, "bar 1: key at p+0.4 lands at %.4f s (want 1.6 +- 1 frame)" % got)
	ok(var_to_str(S.part_keys["lowerarm_r"][0]) == pre, "bar 2: key at 0.5 s (before) is byte-identical")
	ok(var_to_str(S.part_keys["lowerarm_r"][1]) == at_start, "bar 2: key at the range start 1.0 s stays at 1.0 s")
	ok(var_to_str(S.cards[0]) == c0, "bar 2: card 0 (before the range) is byte-identical")
	ok(absf(float(S.cards[1]["move"]) - 0.5) < 1e-9 and absf(float(S.cards[1]["hold"]) - 0.75) < 1e-3, "bar 2: card 1 keeps its move 0.5; its hold runs into the range: %.3f (want 0.75)" % float(S.cards[1]["hold"]))
	var after := key_t(S, "lowerarm_r", 3)
	ok(absf(after - 5.0) < 1e-6, "bar 3: key at 4.0 s moves by the length change (1.0 s): now %.4f s" % after)
	var ts: Array = S.times()
	ok(absf(float(ts[2][1]) - 2.5) < 1e-3, "bar 4: card 2 arrival 2.0 -> %.4f s (want 2.5)" % float(ts[2][1]))
	ok(absf(float(ts[3][1]) - 4.0) < 1e-3, "bar 4: card 3 arrival 3.0 -> %.4f s (want 4.0)" % float(ts[3][1]))
	ok(absf(float(ts[4][1]) - 5.0) < 1e-3, "bar 4: card 4 arrival 4.0 -> %.4f s (want 5.0)" % float(ts[4][1]))
	ok(absf(S.length() - (len0 + 1.0)) < 1e-3, "bar 3: the scene is %.4f s, one second longer than %.4f s" % [S.length(), len0])
	ok(RetimeRange.apply(S, 1.0, 3.0, 1.0, 100.0) == 0, "bar 5: 100 % changes no card (checked on a fresh scene below)")

	# bar 5: 100 % is a no-op
	var S2 := make()
	var cards_before := var_to_str(S2.cards)
	var keys_before := var_to_str(S2.part_keys)
	var n2 := RetimeRange.apply(S2, 1.0, 3.0, 2.0, 100.0)
	ok(n2 == 0 and var_to_str(S2.cards) == cards_before and var_to_str(S2.part_keys) == keys_before,
		"bar 5: 100 %% is a no-op: cards and part keys byte-identical (%d cards touched)" % n2)

	# bar 6: the playhead mid-range, 50 %
	var S3 := make()
	S3.part_keys["lowerarm_r"][2]["t"] = 2.4   # the key at p + 0.4
	RetimeRange.apply(S3, 1.0, 3.0, 2.0, 50.0)
	var k3: Array = S3.part_keys["lowerarm_r"]
	ok(absf(float(k3[2]["t"]) - 2.2) < 1e-6, "bar 6: key 2.4 -> %.4f s (want 2.2)" % float(k3[2]["t"]))
	ok(absf(float(k3[3]["t"]) - 3.5) < 1e-6, "bar 6: key 4.0 -> %.4f s (want 3.5)" % float(k3[3]["t"]))
	var t3: Array = S3.times()
	ok(absf(float(t3[2][1]) - 2.0) < 1e-3, "bar 6: card 2 arrival (2.0, the playhead) stays %.4f s" % float(t3[2][1]))
	ok(absf(float(t3[3][1]) - 2.5) < 1e-3, "bar 6: card 3 arrival 3.0 -> %.4f s (want 2.5)" % float(t3[3][1]))

	# bar 7: a stretch that would run back over the content before the range is refused
	var S4 := make()
	var refuse := RetimeRange.check(S4, 1.0, 3.0, 2.0, 150.0)
	ok(refuse != "" and refuse.contains("run it back"), "bar 7: 150 %% about 2.0 s refused: %s" % refuse)
	ok(RetimeRange.check(S4, 1.0, 3.0, 2.0, 50.0) == "", "bar 7: the same range at 50 % is allowed (a gap, nothing overlaps)")

	# bar 8: playhead outside, percent outside
	ok(RetimeRange.check(S4, 1.0, 3.0, 0.5, 150.0).contains("outside"), "bar 8: a playhead outside the range is refused")
	ok(RetimeRange.check(S4, 1.0, 3.0, 1.0, 5.0) != "", "bar 8: 5 % is refused")

	# bar 9: modifiers and handles
	var S5 := make()
	S5.part_keys["lowerarm_r"][2]["hout"] = [0.4, 0.0, 0.0, 0.0]
	S5.part_keys["lowerarm_r"][2]["t"] = 2.0
	S5.part_keys["lowerarm_r"][0]["mods"] = [{"type": "noise", "ch": 0, "mix": 1.0, "range_start": 2.0, "range_end": 2.5, "blend_in": 0.2}]
	RetimeRange.apply(S5, 1.0, 3.0, 2.0, 50.0)
	var md: Dictionary = S5.part_keys["lowerarm_r"][0]["mods"][0]
	ok(absf(float(md["range_start"]) - 2.0) < 1e-6 and absf(float(md["range_end"]) - 2.25) < 1e-6,
		"bar 9: modifier range 2.0-2.5 -> %.3f-%.3f s (want 2.0-2.25)" % [float(md["range_start"]), float(md["range_end"])])
	ok(absf(float(md["blend_in"]) - 0.1) < 1e-6, "bar 9: blend_in 0.2 -> %.3f (want 0.1)" % float(md["blend_in"]))
	var hout: Array = S5.part_keys["lowerarm_r"][2]["hout"]
	ok(absf(float(hout[0]) - 0.2) < 1e-6, "bar 9: handle dt 0.4 -> %.3f (want 0.2)" % float(hout[0]))

	print("RETIME RANGE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
