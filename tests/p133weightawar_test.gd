extends SceneTree
## p133weightawar (Friday plan item 133: Weight-aware motion: a heavy part (from material weight) slows the swing in typed moves).
## A beginner types a move in the words box ("overhead axe strike, step in"); the built move is timed to the weapon it holds
## (WeightFeel: a heavier implement takes longer over the same arc). Slow only: a lighter weapon keeps its timing.
## Bars, measured from the BUILT scene (its card times and markers, never the code's own variables):
##   0 "overhead axe strike, step in" builds (ok) and its status says the swing is slowed for the axe's weight
##   1 the built scene carries one hit marker, on the strike card's arrival (within 2 ms of that card's arrival)
##   2 the axe's wind-up after / before is above 1.0 and at most 2.0 (heavier = slower, within the cap)
##   3 the recovery after / before ratio matches the wind-up ratio within 1 pct (one factor for the whole swing)
##   4 the strike card's own hold is unchanged (the contact keeps its place in the swing)
##   5 no card in any phrase gets SHORTER by the weight step (slow only)
##   6 a fist ("fast jab") has no weight step: nothing changes, the result says so with ok = false
## shots: none (no windows; the scene is read from the built result)

const PHRASE := "overhead axe strike, step in"
const FIST := "fast jab"
const PHRASES := ["overhead axe strike, step in", "bat swing left", "staff sweep right, pivot", "dagger thrust lunge", "heavy hammer overhead, step back", "uppercut"]

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## a fresh built move (the text_blocking build on a scratch body, as the words box does), its body and the scene
func built(text: String) -> Dictionary:
	var W := Body.new()
	W.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var r: Dictionary = load("res://scripts/text_blocking.gd").build(text, W)
	return {"r": r, "W": W}


## the strike card's arrival, from the built scene's times (times()[i] = [start, arrival, hold end])
func hit_card(S: Scene) -> int:
	var t := -1.0
	for mk in S.markers:
		if String(mk["kind"]) == "hit":
			t = float(mk["t"])
	var ts := S.times()
	var best := -1
	for i in S.cards.size():
		if best < 0 or absf(float(ts[i][1]) - t) < absf(float(ts[best][1]) - t):
			best = i
	return best


func _init() -> void:
	var TB := load("res://scripts/text_blocking.gd")
	var b := built(PHRASE)
	var r: Dictionary = b["r"]
	ok(bool(r["ok"]), "bar 0a: '%s' builds: %s" % [PHRASE, str(r.get("error", ""))])
	if bool(r["ok"]):
		var S: Scene = r["scene"]
		var t0: Array = S.times().duplicate(true)
		var c := hit_card(S)
		var hits := 0
		for mk in S.markers:
			if String(mk["kind"]) == "hit":
				hits += 1
		ok(hits == 1 and c >= 0 and absf(float(S.times()[c][1]) - float(S.markers.filter(func(m): return String(m["kind"]) == "hit")[0]["t"])) <= 0.002,
			"bar 1: one hit marker, on card %d's arrival (%d hit marks)" % [c + 1, hits])
		var wu0 := float(t0[c][1]) - float(t0[0][2])
		var rc0 := float(t0[-1][2]) - float(t0[c][2])
		var hold0 := float(S.cards[c]["hold"])
		var wt: Dictionary = TB.weight_slow(S, b["W"])
		ok(bool(wt["ok"]) and String(wt["msg"]).find("slowed for the long axe") >= 0,
			"bar 0b: the status says the swing is slowed for the axe's weight: %s" % str(wt["msg"]))
		var t1: Array = S.times()
		var wu1 := float(t1[c][1]) - float(t1[0][2])
		var rc1 := float(t1[-1][2]) - float(t1[c][2])
		var fw := wu1 / wu0 if wu0 > 0.0 else 0.0
		ok(fw > 1.0 and fw <= 2.0, "bar 2: wind-up %.3f -> %.3f s (x%.3f, above 1 and at most 2)" % [wu0, wu1, fw])
		ok(absf(rc1 / rc0 - fw) <= 0.01 * fw, "bar 3: recovery %.3f -> %.3f s (x%.3f) matches the wind-up factor" % [rc0, rc1, rc1 / rc0])
		ok(absf(float(S.cards[c]["hold"]) - hold0) < 0.0005, "bar 4: strike card hold %.3f s -> %.3f s (unchanged)" % [hold0, float(S.cards[c]["hold"])])
	var shrunk := []
	for p in PHRASES:
		var bb := built(p)
		var rr: Dictionary = bb["r"]
		if not bool(rr["ok"]):
			shrunk.append("%s: build failed" % p)
			continue
		var S2: Scene = rr["scene"]
		var before: Array = S2.times().duplicate(true)
		TB.weight_slow(S2, bb["W"])
		var after: Array = S2.times()
		for i in S2.cards.size():
			if float(after[i][1]) - float(after[i][0]) < float(before[i][1]) - float(before[i][0]) - 0.001:
				shrunk.append("%s card %d" % [p, i + 1])
	ok(shrunk.is_empty(), "bar 5: no card in %d phrases gets shorter by the weight step: %s" % [PHRASES.size(), str(shrunk)])
	var f := built(FIST)
	var fr: Dictionary = f["r"]
	if bool(fr["ok"]):
		var FS: Scene = fr["scene"]
		var tb: Array = FS.times().duplicate(true)
		var fw2: Dictionary = TB.weight_slow(FS, f["W"])
		var same := true
		for i in FS.cards.size():
			same = same and absf(float(FS.times()[i][1]) - float(tb[i][1])) < 0.0005
		ok(not bool(fw2["ok"]) and same, "bar 6: '%s' (a fist) has no weight step: ok = %s, times unchanged = %s" % [FIST, str(fw2["ok"]), str(same)])
	else:
		ok(false, "bar 6: '%s' builds: %s" % [FIST, str(fr.get("error", ""))])
	print("TOTAL FAILS: %d" % fails)
	quit(fails)
