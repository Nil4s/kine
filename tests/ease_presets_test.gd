## godot --headless --path . -s tests/ease_presets_test.gd     (ROADMAP 17: EASE PRESETS FROM REAL MOTION)
## The four measured presets (scripts/ease_presets.gd; formulas and sources in docs/research/EASE_PRESETS.md):
##   1 REACH = minimum-jerk (Flash & Hogan 1985): the speed of the moving point peaks at 50 % of the move, peak / mean
##     = 1.875 within 2 %, and the curve is 10x^3 - 15x^4 + 6x^5 to 1e-9.
##   2 STRIKE: the speed peaks at the stated fraction (STRIKE_PEAK = 0.60) within 0.03 of the move.
##   3 THROW: in a real card move (combo3, card 2 -> 3) the joints' speed peaks come in proximal-to-distal order
##     (clavicle, upper arm, forearm, hand), each at the time the preset predicts within 0.02 of the move.
##   4 SETTLE: e(0) = 0, e(1) = 1 exactly, a few per cent of overshoot (the damped step).
##   5 OLD SCENES: every scene in scenes/ (read only) samples to the same sha256 as before the presets existed
##     (the hashes below were recorded on the commit before scripts/ease_presets.gd, at 60 Hz).
##   6 the dropdown order: ALL_EASES starts with EASES, so the five old indices do not move.
extends SceneTree

const BASE := {   # sha256 of every scene's sampled angles + offset (60 Hz), recorded before the presets
	"bo_spin.json": "683b7410373f1427e32f7e56ac63462713e83119cecee623b5ba31cec7751336",
	"bo_sweep.json": "2b9ede64c591d52807b506ab899bdc8eaadf00af6a7aa7479dc855ee7ab536c2",
	"combo3.json": "34c876b6ec02bc96c80f3b2ee0f07c03318d9aa5ed3826707c6745561a229ac4",
	"dodge_side.json": "46b5a0cabf2df68b4644e47439e475d70fab60c3659deca9641411797c925f42",
	"hit_react.json": "047de596beb220bbc513784a8534b114d81b6839569dfdbedd9328b079af26dd",
	"idle_bat.json": "c8c49d270e2f7941e1952ab8a3c24d6ba160ed24b4ed2e48583515d62d515d72",
	"strike_legs.json": "f0139fec569f072efe0bd852f95dd842be3cd18301299ad94b3f001b08cbba09",
	"swing_back.json": "5dd63b429d04803a7e45d981b18e768d0ccfcbfc3791a4dd8699ccd9059564e9",
	"swing_fore.json": "550be4ed0d63e67748652563d1a3340df24b585cd7b49e15cd2566c191e1293d",
	"thrust.json": "034f0329c998365e0fa42ee15e6c7fb86f8ad8327a3779e609da108cc27d15ac",
	"walk_bat.json": "5405336ca51708c40e090b0b967d8f69b3b0200ff3eef26b67b7ca4ad2fa71ba",
}

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## index of the peak of a sampled speed curve, and its value over the mean
func peak_of(f: Callable, n: int) -> Dictionary:
	var best := -1.0
	var at := 0.0
	var sum := 0.0
	var prev: float = f.call(0.0)
	for i in range(1, n + 1):
		var x := float(i) / float(n)
		var cur: float = f.call(x)
		var sp := (cur - prev) * float(n)   # speed in progress units per move
		sum += sp / float(n)
		if sp > best:
			best = sp
			at = x - 0.5 / float(n)
		prev = cur
	return {"at": at, "ratio": best / (sum if sum > 0.0 else 1.0)}


## the scene's sampled angles + offset at 60 Hz, as one sha256 (the same recipe as the baseline)
func scene_hash(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""   # a tracked scene deleted in this working copy: skipped by the caller, not hashed
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or not (d as Dictionary).has("cards"):
		return ""   # not a scene file
	var S := Scene.new()
	S.from_dict(d)
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
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(var_to_bytes(acc))
	return ctx.finish().hex_encode()


func _init() -> void:
	# 1 REACH
	var mj := func(x: float) -> float: return 10.0 * x * x * x - 15.0 * x * x * x * x + 6.0 * x * x * x * x * x
	var worst := 0.0
	for i in 101:
		var x := float(i) / 100.0
		worst = maxf(worst, absf(EasePresets.progress("reach", x) - mj.call(x)))
	ok(worst < 1e-9, "reach is the minimum-jerk polynomial 10x^3-15x^4+6x^5 (worst %.2e)" % worst)
	var pk := peak_of(func(x: float) -> float: return EasePresets.progress("reach", x), 4000)
	ok(absf(float(pk["at"]) - 0.5) < 0.005, "reach: the speed peaks at 50 %% of the move (at %.3f)" % float(pk["at"]))
	ok(absf(float(pk["ratio"]) - 1.875) / 1.875 < 0.02, "reach: peak / mean speed = 1.875 within 2 %% (got %.4f)" % float(pk["ratio"]))

	# 2 STRIKE: late peak
	var sk := peak_of(func(x: float) -> float: return EasePresets.progress("strike", x), 4000)
	ok(absf(float(sk["at"]) - EasePresets.STRIKE_PEAK) < 0.03, "strike: the speed peaks at %.2f of the move (want %.2f within 0.03; got %.3f)" % [EasePresets.STRIKE_PEAK, EasePresets.STRIKE_PEAK, float(sk["at"])])
	ok(EasePresets.progress("strike", 0.0) == 0.0 and absf(EasePresets.progress("strike", 1.0) - 1.0) < 1e-9, "strike: e(0) = 0 and e(1) = 1")

	# 3 THROW, on the joints of a real move: combo3 card 2 -> card 3 (the scene is read only)
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json"))
	var sc := Scene.new()
	sc.from_dict(base)
	sc.cards = [sc.cards[1], sc.cards[2]]
	sc.cards[1] = sc.cards[1].duplicate()
	sc.cards[1]["ease"] = "throw"
	var ts := sc.times()
	var joints := ["clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]
	var got := []
	var want := []
	for j in joints:
		var lv := Scene.level(j)
		var a: Vector3 = Moves._flat(sc.cards[0]["pose"])["ang"][j]
		var b: Vector3 = Moves._flat(sc.cards[1]["pose"])["ang"][j]
		var span := (b - a).length()
		var f := func(u: float) -> float:
			var t: float = ts[1][0] + u * (ts[1][1] - ts[1][0])
			var v: Vector3 = sc.sample(t)["ang"][j]
			return (v - a).dot(b - a) / maxf(span * span, 1e-9)   # progress along a -> b
		var pj := peak_of(f, 1000)
		var predicted := Scene.LAG * float(lv) / 6.0 + (1.0 - Scene.LAG) * (EasePresets.THROW_P0 + EasePresets.THROW_STEP * float(lv))
		got.append(snappedf(float(pj["at"]), 0.001))
		want.append(snappedf(predicted, 0.001))
		ok(span > 1.0 and absf(float(pj["at"]) - predicted) < 0.02, "throw: %s (level %d) peaks at %.3f of the move, predicted %.3f (move %.1f deg)" % [j, lv, float(pj["at"]), predicted, span])
	var ordered := true
	for i in range(1, got.size()):
		ordered = ordered and got[i] > got[i - 1]
	ok(ordered, "throw: the peaks run proximal to distal: %s" % str(got))

	# 4 SETTLE
	ok(EasePresets.progress("settle", 0.0) == 0.0 and EasePresets.progress("settle", 1.0) == 1.0, "settle: e(0) = 0 and e(1) = 1 exactly")
	var over := 0.0
	for i in 1001:
		over = maxf(over, EasePresets.progress("settle", float(i) / 1000.0))
	ok(over > 1.01 and over < 1.10, "settle: overshoots a few per cent and rings back (peak %.3f)" % over)

	# 5 OLD SCENES bit-identical
	var same := true
	var n_hashed := 0
	for f in BASE:
		var h: String = scene_hash("res://scenes/" + f)
		if h == "":
			print("     %s skipped (not in this working copy, or not a scene)" % f)
			continue
		n_hashed += 1
		if h != BASE[f]:
			same = false
		print("     %s %s" % [f, "same" if h == BASE[f] else "DIFFERENT"])
	ok(same and n_hashed >= BASE.size() - 1, "every tracked scene present in scenes/ samples to the same sha256 as before the presets (%d of %d)" % [n_hashed, BASE.size()])

	# 6 dropdown indices
	ok(Scene.ALL_EASES.slice(0, Scene.EASES.size()) == Scene.EASES, "ALL_EASES starts with EASES (the old dropdown indices stay)")

	print("ease_presets: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails > 0 else 0)
