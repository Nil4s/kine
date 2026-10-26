## godot --headless --path . -s tests/edge_counts_test.gd     (GATES Y2, UPGRADES #11)
## EDGE COUNTS: scenes of 1, 2 and 30 cards (poses cycled from combo3), in the plain ease, the spline and stepped:
## the pose at each card's arrival is that card exactly (to 1e-3 deg, 1e-5 m) - in the spline, at a card passed
## THROUGH (hold 0), each joint at ITS time (the overlap: level L reads LEAD x (5 - L) s ahead, so it passes the card
## that much earlier; the hands exactly on it; the fingers, level 6, 15 ms after), at a stop too; t below 0 and past the end give the
## first and last card, also with NO hold on the first card (the first frame is the first card); never a NaN; a 1-card scene's length is its hold and every frame of it is that card; 30 cards'
## length is the sum of their moves and holds. And the body itself (apply) at those times, through the floor and feet.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## the biggest difference between two poses: [degrees over every joint and axis, metres of hips offset]; NaN -> INF
func gap(a: Dictionary, b: Dictionary) -> Array:
	if a.is_empty() or b.is_empty():
		return [INF, INF]
	var dg := 0.0
	for j in b["ang"]:
		if not a["ang"].has(j):
			return [INF, INF]
		var d: Vector3 = (a["ang"][j] as Vector3) - (b["ang"][j] as Vector3)
		for k in 3:
			if is_nan(d[k]):
				return [INF, INF]
			dg = maxf(dg, absf(wrapf(d[k], -180.0, 180.0)))
	var off: float = ((a["offset"] as Vector3) - (b["offset"] as Vector3)).length()
	return [dg, INF if is_nan(off) else off]


func build(n: int, src: Scene) -> Scene:
	var S := Scene.new()
	S.name = "zz_edge_%d" % n
	for i in n:
		var c: Dictionary = src.cards[i % src.cards.size()]
		S.add("c%d" % (i + 1), c["pose"].duplicate(true))
		S.cards[i]["move"] = 0.0 if i % 3 == 0 else 0.2 + 0.05 * (i % 4)   # some auto, some set
		S.cards[i]["hold"] = 0.0 if i % 4 == 1 else 0.1 * (1 + i % 3)     # some with no hold
	return S


func _init() -> void:
	var src := Scene.new()
	src.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	for mode in ["ease", "spline", "stepped"]:
		for n in [1, 2, 30]:
			var S := build(n, src)
			S.spline = mode == "spline"
			S.stepped = mode == "stepped"
			if n == 1:
				S.cards[0]["hold"] = 0.4
			elif mode == "spline" and n == 30:
				S.cards[0]["hold"] = 0.0   # the first card with no hold: the frame at t = 0 must still be it
			var ts := S.times()
			var L := S.length()
			var sum := 0.0
			for i in n:
				sum += S.move_time(i) + float(S.cards[i]["hold"])
			var worst := [0.0, 0.0]
			var at := -1
			var probe := []
			for i in n:
				probe.append([float(ts[i][1]), i])
			probe.append([-1.0, 0])
			probe.append([-1e-9, 0])
			probe.append([L, n - 1])
			probe.append([L + 5.0, n - 1])
			for pr in probe:
				var want := Moves._flat(S.cards[pr[1]]["pose"])
				var got: Dictionary = S.sample(pr[0]) if mode != "stepped" else want   # stepped never calls sample: its own read below
				if mode == "stepped":
					var k := 0
					for i in n:
						if pr[0] >= float(ts[i][1]) - 1e-6:
							k = i
					got = Moves._flat(S.cards[k]["pose"])
				if mode == "spline" and pr[0] >= 0.0 and pr[0] <= L:
					got = {"offset": S.sample(pr[0] - Scene.LEAD * 5.0)["offset"], "ang": {}}   # each joint at its own time
					for j in want["ang"]:
						got["ang"][j] = S.sample(pr[0] - Scene.LEAD * (5 - S.level(j)))["ang"][j]
				var g := gap(got, want)
				if g[0] > worst[0] or g[1] > worst[1]:
					worst = [maxf(g[0], worst[0]), maxf(g[1], worst[1])]
					at = pr[0] * 1000.0
			var nan := false
			var frames := int(ceil(L * 30.0)) + 2
			for f in range(-3, frames):
				var s: Dictionary = S.sample(f / 30.0) if mode != "stepped" else {}
				if mode != "stepped" and gap(s, Moves._flat(S.cards[0]["pose"]))[0] == INF:
					nan = true
				S.apply(B, f / 30.0)
				for j in B.ang:
					var v: Vector3 = B.ang[j]
					if is_nan(v.x) or is_nan(v.y) or is_nan(v.z):
						nan = true
				if is_nan(B.offset.x) or is_nan(B.offset.y):
					nan = true
			var still := true
			if n == 1:
				for f in range(-3, frames):
					still = still and gap(S.sample(f / 30.0) if mode != "stepped" else Moves._flat(S.cards[0]["pose"]), Moves._flat(S.cards[0]["pose"]))[0] < 1e-3
			var len_ok: bool = absf(L - sum) < 1e-9 and (n != 1 or absf(L - 0.4) < 1e-9)
			ok(worst[0] < 1e-3 and worst[1] < 1e-5 and not nan and len_ok and still,
				"%-7s %2d cards: at every arrival, before 0 and past the end the pose is that card (worst %.5f deg, %.6f m at %.0f ms); no NaN over %d frames (sample and the body); length %.3f s = the sum %.3f%s" % [
				mode, n, worst[0], worst[1], at, frames + 3, L, sum, "; still throughout" if n == 1 else ""])
	print("EDGE COUNTS: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
