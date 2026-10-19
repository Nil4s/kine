## godot --path . -s tests/fatigue_test.gd     (ROADMAP 39; needs a window for the undo step)
## FATIGUE: a 60 s fight of identical strikes slows as it goes by the cited decline (docs/research/FATIGUE.md).
## Bars (written before measuring):
##   1 default fitness 0.5: the first strike's speed is unchanged (< 0.5 %), the last strike is slower by 10.3 % +- 2 points
##     (Sensors 2025: -10.7 % straight, -9.9 % swing, mean 10.3), speed = 1 / the strike move's duration.
##   2 fitness 1: no card's timing changes by more than 1 %, and the scene's length by < 1 %.
##   3 contact still lands: every hit marker sits on its strike card's arrival (1 ms) and the pose sampled there IS that
##     card's pose (angles within 1e-4); no marker lost.
##   4 rest recovers: a 10 s rest in the middle -> the strike after it is faster than the one before it.
##   5 one undo step; undo restores cards, markers and fitness byte for byte. Fitness 0 slows more than 0.5.
##   6 the file: fitness is written only when not 0.5 and reads back.
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


## a fight of n identical cycles (ready, wind-up, STRIKE, recover) from the poses of combo3's first four cards
func fight(n: int, rest_after := -1, rest_s := 10.0) -> void:
	var base: Array = m.S.cards.slice(0, 4).map(func(c): return c["pose"].duplicate(true))
	var mv := [0.25, 0.2, 0.15, 0.3]
	var hd := [0.1, 0.05, 0.1, 0.1]
	m.S.cards = []
	m.S.markers = []
	for c in n:
		for k in 4:
			var cd := {"name": "c%d_%d" % [c, k], "pose": base[k].duplicate(true), "move": mv[k], "hold": hd[k]}
			if k == 3 and c == rest_after:
				cd["hold"] = rest_s
			m.S.cards.append(cd)
	var ts: Array = m.S.times()
	for c in n:
		Markers.add(m.S.markers, ts[c * 4 + 2][1], "hit%d" % c, "hit")


func speeds() -> Array:   # per strike card: 1 / its move
	return Fatigue.strike_cards(m.S).map(func(i): return 1.0 / m.S.move_time(i))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	fight(48)
	var len0: float = m.S.length()
	var before_cards := JSON.stringify(m.S.cards)
	var before_mk := JSON.stringify(m.S.markers)
	var sp0 := speeds()
	var u0: int = m.undo.size()
	var e: String = m.fatigue(0.5)
	var sp := speeds()
	var dec: float = 1.0 - sp[-1] / sp[0]
	var first: float = absf(sp[0] / sp0[0] - 1.0)
	ok(e == "" and sp.size() == 48 and first < 0.005 and absf(dec - 0.103) <= 0.02,
		"1 fitness 0.5, %.1f s fight of %d strikes: first strike speed change %.2f %%, last strike %.1f %% slower (cited 10.3 +- 2); scene %.1f -> %.1f s" % [len0, sp.size(), first * 100.0, dec * 100.0, len0, m.S.length()])
	var mono := true
	for i in range(1, sp.size()):
		mono = mono and sp[i] <= sp[i - 1] + 0.01 * sp[0]
	ok(mono, "1b the strikes never speed up as the fight goes (within 1 % rounding)")
	var ts: Array = m.S.times()
	var landed: bool = m.S.markers.size() == 48
	var worst := 0.0
	var dt := 0.0
	var idxs := Fatigue.strike_cards(m.S)
	for n in idxs.size():
		var i: int = idxs[n]
		dt = maxf(dt, absf(float(m.S.markers[n]["t"]) - float(ts[i][1])))
		var want: Dictionary = Moves._flat(m.S.cards[i]["pose"])["ang"]
		var got: Dictionary = m.S.sample(float(ts[i][1]))["ang"]
		for j in want:
			worst = maxf(worst, ((want[j] as Vector3) - (got[j] as Vector3)).length())
	ok(landed and dt <= 0.001 and worst <= 1e-4, "3 contact lands: 48 markers on their strike card's arrival (worst %.4f ms), pose there off by %.5f deg at worst" % [dt * 1000.0, worst])
	ok(m.undo.size() == u0 + 1, "5a one undo step (%d -> %d)" % [u0, m.undo.size()])
	m._undo()
	await idle()
	ok(JSON.stringify(m.S.cards) == before_cards and JSON.stringify(m.S.markers) == before_mk and m.S.fitness == 0.5, "5b undo: cards, markers and fitness byte for byte as before")
	m.fatigue(0.0)
	var dec0: float = 1.0 - speeds()[-1] / speeds()[0]
	m._undo()
	ok(dec0 > dec * 1.5, "5c fitness 0 slows more than 0.5 (%.1f %% vs %.1f %%)" % [dec0 * 100.0, dec * 100.0])
	e = m.fatigue(1.0)
	var worst_card := 0.0
	var old: Array = JSON.parse_string(before_cards)
	for i in range(1, old.size()):
		worst_card = maxf(worst_card, absf(m.S.move_time(i) - float(old[i]["move"])) / maxf(0.01, float(old[i]["move"])))
	var dlen: float = absf(m.S.length() / len0 - 1.0)
	ok(e == "" and worst_card < 0.01 and dlen < 0.01, "2 fitness 1: worst card move change %.2f %%, scene length change %.2f %% (bar < 1 %%)" % [worst_card * 100.0, dlen * 100.0])
	m._undo()
	m.S.fitness = 0.5
	fight(24, 11, 10.0)
	m.fatigue(0.5)
	var s2 := speeds()
	ok(s2[12] > s2[11] * 1.01, "4 a 10 s rest after strike 12: the next strike is faster (%.3f -> %.3f per s)" % [s2[11], s2[12]])
	m.S.fitness = 0.8
	var d: Dictionary = m.S.to_dict(m.B, false)
	var s3 := Scene.new()
	s3.from_dict(d)
	m.S.fitness = 0.5
	var d0: Dictionary = m.S.to_dict(m.B, false)
	ok(is_equal_approx(s3.fitness, 0.8) and d.has("fitness") and not d0.has("fitness"), "6 file: fitness 0.8 written and read back, 0.5 not written")
	print("FATIGUE: %d failed" % fails)
	quit(1 if fails > 0 else 0)
