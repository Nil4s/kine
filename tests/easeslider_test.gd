## godot --headless --path . -s tests/easeslider_test.gd     (ROADMAP 55: the card's ease slider, "Slow in ... Even ... Slow out")
## Bars, stated before measuring:
##   1 slider at 0 leaves every sampled frame of combo3 bit-identical (60 Hz; the key erased, and the key held as 0.0)
##   2 hand path, combo3 card 2 -> 3, the hand end (hand_r) at the time half of the move: bias +1 covers < 30 % of the distance,
##     bias -1 covers > 70 % (the slider's ends; the move is the card's own, so the hand's travel is real)
##   3 the ends hold at both biases: the move starts on its card before and lands on its card after (within 0.01 rad)
##   4 undo: the cards as they were before a drag, put back, sample to the original frames exactly
##   5 save / reload keeps the value (-0.42 comes back as -0.42); a 0 is never written; combo3 has no key but card 2
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func load_scene(path: String) -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	return S


## every sampled frame at 60 Hz: the angles (by joint name) and the offset, flattened
func frames(S: Scene) -> PackedFloat64Array:
	var acc := PackedFloat64Array()
	var k := 0
	while k / 60.0 <= S.length():
		var s: Dictionary = S.sample(k / 60.0)
		var keys: Array = s["ang"].keys()
		keys.sort()
		for j in keys:
			var v: Vector3 = s["ang"][j]
			acc.append_array([v.x, v.y, v.z])
		var o: Vector3 = s["offset"]
		acc.append_array([o.x, o.y, o.z])
		k += 1
	return acc


## the hand's path in space: hand_r's end point (Body.E) over the move INTO card 3 of combo3 (the scene is read only).
## Returns [the share of the hand's travel covered at the time half of the move, the travel in cm]
func hand_share(bias: float) -> Array:
	var sc := load_scene("res://scenes/combo3.json")
	sc.cards = [sc.cards[1], sc.cards[2]]
	sc.cards[1].erase("ease")
	Scene.set_ease_bias(sc.cards[1], bias)
	var ts := sc.times()
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	Scene.put(B, Moves._flat(sc.cards[0]["pose"]))
	var p0: Vector3 = B.E["hand_r"]
	Scene.put(B, Moves._flat(sc.cards[1]["pose"]))
	var p1: Vector3 = B.E["hand_r"]
	var span := (p1 - p0).length()
	var mid: float = ts[1][0] + 0.5 * (ts[1][1] - ts[1][0])
	Scene.put(B, sc.sample(mid))
	var pm: Vector3 = B.E["hand_r"]
	var share := (pm - p0).dot(p1 - p0) / maxf(span * span, 1e-9)
	return [share, span * 100.0]


func _init() -> void:
	# 1 slider at 0: bit-identical frames
	var ref := frames(load_scene("res://scenes/combo3.json"))
	var erased := load_scene("res://scenes/combo3.json")
	for c in erased.cards:
		Scene.set_ease_bias(c, 0.0)
	var held := load_scene("res://scenes/combo3.json")
	for c in held.cards:
		c["ease_bias"] = 0.0   # the key present at 0.0 in memory: the warp is skipped, so the same frames
	ok(ref.size() > 1000, "combo3 samples %d values at 60 Hz" % ref.size())
	ok(frames(erased) == ref, "slider at 0 (key erased): every sampled frame of combo3 is bit-identical")
	ok(frames(held) == ref, "slider at 0 (key held at 0.0 in memory): every sampled frame is bit-identical")

	# 2 the slider's ends on a real hand path
	var plus := hand_share(1.0)
	var minus := hand_share(-1.0)
	var none := hand_share(0.0)
	ok(float(plus[1]) > 5.0, "the hand travels %.1f cm on combo3 card 2 -> 3 (a real move, > 5 cm)" % float(plus[1]))
	ok(float(plus[0]) < 0.30, "bias +1 (slow out): the hand covers %.1f %% of its travel in the first half (want < 30 %%)" % (float(plus[0]) * 100.0))
	ok(float(minus[0]) > 0.70, "bias -1 (slow in): the hand covers %.1f %% of its travel in the first half (want > 70 %%)" % (float(minus[0]) * 100.0))
	ok(absf(float(none[0]) - 0.5) < 0.5 and float(none[0]) > 0.0, "bias 0: the curve as it is covers %.1f %% in the first half (between the two ends)" % (float(none[0]) * 100.0))

	# 3 the ends hold at both biases
	var edge := true
	for bias in [1.0, -1.0, 0.5, -0.5]:
		var sc := load_scene("res://scenes/combo3.json")
		sc.cards = [sc.cards[1], sc.cards[2]]
		sc.cards[1].erase("ease")
		Scene.set_ease_bias(sc.cards[1], bias)
		var ts := sc.times()
		var a: Vector3 = Moves._flat(sc.cards[0]["pose"])["ang"]["hand_r"]
		var b: Vector3 = Moves._flat(sc.cards[1]["pose"])["ang"]["hand_r"]
		var at0: Vector3 = sc.sample(ts[1][0])["ang"]["hand_r"]
		var at1: Vector3 = sc.sample(ts[1][1])["ang"]["hand_r"]
		var good := (at0 - a).length() < 0.01 and (at1 - b).length() < 0.01
		edge = edge and good
	ok(edge, "the move starts on its card and lands on it at biases +1, -1, +0.5, -0.5")
	var zero_ends := true
	var sc0 := Scene.new()
	for bias in [1.0, -1.0]:
		zero_ends = zero_ends and sc0._ease(0.0, 2, "", bias) == 0.0 and absf(sc0._ease(1.0, 2, "", bias) - 1.0) < 1e-12
	ok(zero_ends, "the warped progress has e(0) = 0 and e(1) = 1 exactly")

	# 4 undo: the cards as they were before the drag, put back, give the same frames
	var u := load_scene("res://scenes/combo3.json")
	var h0 := frames(u)
	var before := u.cards.duplicate(true)
	Scene.set_ease_bias(u.cards[1], 0.7)
	ok(frames(u) != h0, "a drag to +0.70 changes the frames of combo3")
	u.cards = before   # the undo step (main.gd _snapshot keeps cards.duplicate(true))
	ok(frames(u) == h0, "undo restores the frames exactly (the hash is back)")

	# 5 save / reload
	var sv := load_scene("res://scenes/combo3.json")
	Scene.set_ease_bias(sv.cards[1], -0.42)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(sv.to_dict(null, false)))
	var back := Scene.new()
	back.from_dict(saved)
	ok(back.cards.size() == sv.cards.size() and is_equal_approx(float(back.cards[1].get("ease_bias", 9.0)), -0.42), "save + load keeps card 2's ease_bias at -0.42")
	var keys_written := 0
	for c in saved["cards"]:
		if c.has("ease_bias"):
			keys_written += 1
	ok(keys_written == 1, "only the one card the slider touched writes the key (%d written)" % keys_written)
	var old := load_scene("res://scenes/combo3.json").to_dict(null, false)
	var old_keys := 0
	for c in old["cards"]:
		if c.has("ease_bias"):
			old_keys += 1
	ok(old_keys == 0, "an old scene (no slider touched) writes no ease_bias key (%d)" % old_keys)
	var z := {"name": "x", "pose": {}, "ease_bias": 0.0}
	Scene.set_ease_bias(z, 0.004)
	ok(not z.has("ease_bias"), "a slider value of 0 (or within 0.005) erases the key")
	Scene.set_ease_bias(z, 3.0)
	ok(float(z["ease_bias"]) == 1.0, "a value past the end is clamped to +1")

	print("FAILS %d" % fails)
	quit(1 if fails > 0 else 0)
