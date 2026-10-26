## godot --headless --path . -s tests/spline_test.gd [-- scenes/x.json]
## GATES A2-A5 on a real scene switched to spline, interior cards made pass-through except every third (a stop):
##   A2 pass-through: speed in == speed out at the card; not stopped unless that angle turns back there
##   A3 stop card: zero speed arriving and leaving
##   A4 the hand level is exactly on each card's pose at the card's time
##   A5 every in-between angle stays inside its two cards' values (so inside the limits)
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var f: String = a[0] if a.size() > 0 else "res://scenes/combo3.json"
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(f)))
	S.spline = true
	for i in range(1, S.cards.size() - 1):
		S.cards[i]["hold"] = 0.12 if i % 3 == 0 else 0.0
	var ts := S.times()
	var F := {}
	var dt := 2e-3
	var worst4 := 0.0
	var worst2 := 0.0
	var worst3 := 0.0
	var moving := 0
	var throughs := 0
	var worst5 := 0.0
	for i in range(1, S.cards.size() - 1):
		var tk: float = ts[i][1]
		for j in S._flat_of(F, 0)["ang"]:
			if Scene.level(j) != 5 and Scene.level(j) != 1:
				continue
			# A4 on the curve itself (lead 0): the card's value at the card's time
			var y := S._val(F, i, j)
			var v := S._curve(F, j, tk, ts)
			worst4 = maxf(worst4, Scene._d(y, v, j).abs()[Scene._d(y, v, j).abs().max_axis_index()])
			# one-sided speeds by Richardson (2 D(h/2) - D(h)): a plain difference reads f''*h at a stop (float32 forbids tiny h)
			var vin := 2.0 * Scene._d(S._curve(F, j, tk - dt / 2.0, ts), v, j) / (dt / 2.0) - Scene._d(S._curve(F, j, tk - dt, ts), v, j) / dt
			var vout := 2.0 * Scene._d(v, S._curve(F, j, tk + dt / 2.0, ts), j) / (dt / 2.0) - Scene._d(v, S._curve(F, j, tk + dt, ts), j) / dt
			if S._stop(i):
				worst3 = maxf(worst3, maxf(vin.length(), vout.length()))
			else:
				throughs += 1
				worst2 = maxf(worst2, (vout - vin).length() / maxf(10.0, vin.length()))   # under 10 deg/s = stopped
				var dl := Scene._d(S._val(F, i - 1, j), y, j)
				var dr := Scene._d(y, S._val(F, i + 1, j), j)
				for c in 3:
					if dl[c] * dr[c] > 1e-6 and absf(vin[c]) > 1e-3:
						moving += 1
	# A5: every 2 ms, every joint, inside its segment's two card values
	var t := 0.0
	while t < S.length():
		var w := S._where(t, ts)
		if w[1] >= 0.0:
			var i: int = w[0]
			for j in S._flat_of(F, 0)["ang"]:
				var lo := S._val(F, i - 1, j)
				var hi := lo + Scene._d(lo, S._val(F, i, j), j)
				var v := S._curve(F, j, t, ts)
				var dv := Scene._d(lo, v, j)
				for c in 3:
					var span := hi[c] - lo[c]
					var x := lo[c] + dv[c]
					var out := maxf(minf(lo[c], hi[c]) - x, x - maxf(lo[c], hi[c]))
					worst5 = maxf(worst5, out)
		t += 0.002
	ok(worst4 < 1e-4, "A4 cards hit at their times: worst %.6f deg" % worst4)
	ok(worst3 < 0.5, "A3 stop cards: worst speed %.4f deg/s" % worst3)
	ok(worst2 < 0.02, "A2 pass-through speed continuous over %d joint-cards: worst jump %.4f (relative)" % [throughs, worst2])
	ok(moving > 0, "A2 pass-through cards keep moving: %d angle components cross a card at speed" % moving)
	ok(worst5 < 1e-3, "A5 nothing leaves its two cards' range: worst %.6f deg" % worst5)
	# the scene still samples whole (lead, hips, weapon) at every frame
	var n := 0
	for k in int(S.length() * S.fps) + 1:
		var s := S.sample(float(k) / S.fps)
		n += 1 if s.has("weapon") and s["ang"].size() > 20 else 0
	ok(n == int(S.length() * S.fps) + 1, "every frame samples a full pose (%d frames)" % n)
	print("SPLINE %s  (%s, %d cards, %.2f s)" % ["PASS" if fails == 0 else "FAIL %d" % fails, f.get_file(), S.cards.size(), S.length()])
	TestFiles.cleanup()
	quit(fails)
