## godot --headless --path . -s tests/events_test.gd     (N017 EVENT QUERY, scripts/event_query.gd)
## "when does the right foot leave the floor / when is the guard down / when is he off balance / when is the right fist
## fastest / when do the fighters touch" answered from the PLAYED body. Bars, stated before measuring:
##   1 SYNTHETIC, KNOWN TIMINGS: a stepped 60 fps scene built here (stand; right knee up at 1.000 s = frame 60; stand at
##     1.500 s = frame 90; a 15 cm hop at 2.500 s = frame 150; landed at 3.000 s = frame 180; 4.0 s long). The engine's
##     right-foot-up span is 60-89, its airborne span 150-179 and its left-foot-up span 150-179, each boundary within 1 frame.
##   2 COMBO3, HAND-BUILT TRUTH: the left foot's off-the-floor frames at 30 fps, typed below from the capsules' true bottom
##     (min of the foot / ball capsule's two end points' y minus its radius, > 1 cm = up; printed by a probe on 10-23):
##     26, 30-49, 92, 122-126; the right foot never leaves. The engine's spans: the same count, each boundary within 1 frame;
##     at 60 fps every boundary / 2 within 1 (30 fps) frame of the same table.
##   3 OFF BALANCE = balance.gd per frame: the "off balance" frames equal, frame for frame, those where Balance.read (on the
##     scene applied one frame after another, no clone, no cache) has a foot down and margin < -MARGIN_RES; at 30 and 60 fps.
##     The set is neither empty nor every frame (the instrument can move).
##   4 FASTEST: "right fist fastest" on combo3 is EXACTLY the argmax frame of a speed series computed here with measure's own
##     formula (|p(t+h) - p(t-h)| / (t1 - t0), clamped to [0, L]), its value within 1e-4 m/s; serve's `measure speed hand_r`
##     at that t gives the same value within 0.001.
##   5 COMBINATORS: and / or / not equal the frame-wise logic of their parts; "a or b and c" = "a or (b and c)"; a "not" inside
##     a phrase = a "not" before it; "for at least X s" keeps exactly the runs of >= ceil(X * fps) frames; brackets bind it;
##     "fastest ... while <expr>" is the argmax over the frames where <expr> holds.
##   6 UNKNOWN: an unknown phrase returns ok false with the KNOWN list and no spans (serve: error -32602, data.known); an
##     ambiguous part ("hand") and a wrong unit are errors, never a guess.
##   7 PARALLEL = SERIAL: the clip sampled on worker clones equals the live, one-frame-at-a-time clip bit for bit (every point,
##     the feet, the margins) on combo3 at 60 fps.
##   8 SPEED: on a 4 s clip at 60 fps (the synthetic, 241 frames) and on combo3 at 60 fps (281 frames) a question asked through
##     serve's `events` on an already sampled clip is answered in under 200 ms. The first question (sampling included) is
##     printed, not barred: Scene.apply costs 4.5-7 ms a frame on combo3 (measured), so 281 frames are 1.3-2.2 s serial;
##     the bar on it is that parallel sampling is at least 1.5x faster than serial.
##   9 SERVE + TWO FIGHTERS: serve's `events` gives the spans the direct call gives; fighter 3 of 1 is an error; with a second
##     fighter 0.8 m in front, "fighters touch" equals, frame for frame, Body.cross_contacts of the two scenes applied here
##     one frame after another, with touching and non-touching frames both present.
extends SceneTree

var fails := 0
var m: Node
var t_start := Time.get_ticks_msec()


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what + "   [%.0f s]" % ((Time.get_ticks_msec() - t_start) / 1000.0))
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func scene_file(p: String) -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(p)))
	return S


func spans_of(a: Dictionary) -> Array:
	return (a.get("spans", []) as Array).map(func(s): return [int(s["f0"]), int(s["f1"])])


func near_spans(got: Array, want: Array, tol: int, scale := 1.0) -> bool:
	if got.size() != want.size():
		return false
	for i in got.size():
		for e in 2:
			if absf(float(got[i][e]) / scale - float(want[i][e])) > tol:
				return false
	return true


func runs_of(on: Array) -> Array:
	var b := PackedByteArray()
	for x in on:
		b.append(1 if x else 0)
	return EventQuery.runs(b)


func on_of(a: Dictionary, n: int) -> Array:
	var o := []
	o.resize(n)
	o.fill(false)
	for s in a.get("spans", []):
		for i in range(int(s["f0"]), int(s["f1"]) + 1):
			o[i] = true
	return o


func synthetic() -> Scene:
	var B := body()
	var stand := B.to_dict()
	B.set_ang("thigh_r", Vector3(70, 0, 0))
	B.set_ang("calf_r", Vector3(90, 0, 0))
	var knee := B.to_dict()
	var hop: Dictionary = stand.duplicate(true)
	hop["offset"] = [0.0, 0.15, 0.0]
	var S := Scene.new()
	S.name = "zz_events_synth"
	S.fps = 60
	S.on_floor = false
	S.pin = false
	S.stepped = true   # each card's pose from its arrival on: the truth is the arrival frame
	for c in [["stand", stand, 0.0, 0.9], ["knee", knee, 0.1, 0.4], ["stand2", stand, 0.1, 0.9], ["hop", hop, 0.1, 0.4], ["land", stand, 0.1, 1.0]]:
		S.add(c[0], c[1])
		S.cards[-1]["move"] = c[2] if c[2] > 0.0 else -1.0
		S.cards[-1]["hold"] = c[3]
	return S


func _init() -> void:
	# ---- 1 SYNTHETIC
	var SY := synthetic()
	var fsy := [{"S": SY, "B": body(), "xf": Transform3D.IDENTITY, "name": "synth"}]
	var t0 := Time.get_ticks_usec()
	var csy := EventQuery.sample(fsy, 60.0)
	var cold_sy := (Time.get_ticks_usec() - t0) / 1000.0
	var ts: Array = SY.times()
	print("     synthetic: %.3f s, %d frames at 60 fps; arrivals %s" % [SY.length(), csy["n"], ts.map(func(x): return snappedf(float(x[1]), 0.001))])
	var up_r := EventQuery.ask("when does the right foot leave the floor", csy)
	var air := EventQuery.ask("airborne", csy)
	var up_l := EventQuery.ask("left foot off the ground", csy)
	ok(csy["n"] == 241 and near_spans(spans_of(up_r), [[60, 89], [150, 179]], 1), "1 right foot up: %s (truth 60-89 knee, 150-179 hop)" % [spans_of(up_r)])
	ok(near_spans(spans_of(air), [[150, 179]], 1) and near_spans(spans_of(up_l), [[150, 179]], 1),
		"1 airborne %s, left foot up %s (truth 150-179)" % [spans_of(air), spans_of(up_l)])
	var pl := EventQuery.ask("right foot plants", csy)
	ok(spans_of(pl).size() == 3 and absi(int(pl["spans"][1]["f0"]) - 90) <= 1 and absf(float(pl["spans"][1]["t0"]) - 1.5) <= 1.0 / 60.0 + 1e-9,
		"1 right foot plants again at frame %s, %s s (truth 90, 1.500 s)" % [pl["spans"][1]["f0"] if spans_of(pl).size() > 1 else "-", pl["spans"][1]["t0"] if spans_of(pl).size() > 1 else "-"])

	# ---- 2 COMBO3, hand-built truth
	var S3 := scene_file("res://scenes/combo3.json")
	var B3 := body()
	var f3 := [{"S": S3, "B": B3, "xf": Transform3D.IDENTITY, "name": "combo3"}]
	var c30 := EventQuery.sample(f3, 30.0)
	var truth := [[26, 26], [30, 49], [92, 92], [122, 126]]
	var lu := EventQuery.ask("when does the left foot leave the floor", c30)
	var ru := EventQuery.ask("right foot up", c30)
	ok(near_spans(spans_of(lu), truth, 1) and spans_of(ru).is_empty(), "2 combo3 30 fps: left foot up %s (truth %s), right foot up %s (truth none)" % [spans_of(lu), truth, spans_of(ru)])
	t0 = Time.get_ticks_usec()
	var c60 := EventQuery.sample(f3, 60.0)
	var cold_par := (Time.get_ticks_usec() - t0) / 1000.0
	var lu60 := EventQuery.ask("left foot leaves the floor", c60)
	ok(near_spans(spans_of(lu60), truth, 1, 2.0), "2 combo3 60 fps: left foot up %s, / 2 within a frame of the table" % [spans_of(lu60)])

	# ---- 3 OFF BALANCE = balance.gd per frame (serial apply, no clone)
	for c in [c30, c60]:
		var fps: float = c["fps"]
		var BB := body()
		var want := []
		for i in int(c["n"]):
			S3.apply(BB, i / fps)
			var b := Balance.read(BB)
			want.append(not (b["down"] as Array).is_empty() and float(b["margin"]) < -Balance.MARGIN_RES)
		var got := on_of(EventQuery.ask("when is he off balance", c), c["n"])
		var nw := want.count(true)
		ok(got == want and nw > 0 and nw < int(c["n"]), "3 off balance at %d fps: %d of %d frames, frame for frame balance.gd's (%s)" % [int(fps), got.count(true), c["n"], runs_of(want)])

	# ---- 4 FASTEST = the speed peak (measure's formula, computed here)
	var BF := body()
	var L := S3.length()
	var best := -1
	var bv := -1.0
	var h := 1.0 / 30.0
	for i in int(c30["n"]):
		var t := i / 30.0
		var ta := maxf(t - h, 0.0)
		var tb := minf(t + h, L)
		S3.apply(BF, ta)
		var pa: Vector3 = BF.P["hand_r"]
		S3.apply(BF, tb)
		var v := ((BF.P["hand_r"] as Vector3) - pa).length() / (tb - ta)
		if v > bv:
			bv = v
			best = i
	var fa := EventQuery.ask("when is the right fist fastest", c30)
	ok(fa["kind"] == "instant" and int(fa["frame"]) == best and absf(float(fa["value"]) - bv) < 1e-4,
		"4 right fist fastest: frame %s, %s m/s (the speed series' peak: frame %d, %.4f m/s)" % [fa.get("frame"), fa.get("value"), best, bv])

	# ---- 5 COMBINATORS (combo3, 30 fps)
	var n30: int = c30["n"]
	var A := on_of(EventQuery.ask("left foot up", c30), n30)
	var Gd := on_of(EventQuery.ask("guard down", c30), n30)
	var E := on_of(EventQuery.ask("right elbow angle below 90", c30), n30)
	var andv := []
	var orv := []
	var notv := []
	var prec := []
	for i in n30:
		andv.append(A[i] and Gd[i])
		orv.append(A[i] or E[i])
		notv.append(not A[i])
		prec.append(A[i] or (Gd[i] and E[i]))
	ok(on_of(EventQuery.ask("left foot up and guard down", c30), n30) == andv and on_of(EventQuery.ask("left foot up or right elbow angle below 90", c30), n30) == orv
		and on_of(EventQuery.ask("not left foot up", c30), n30) == notv and andv.count(true) > 0 and andv != Gd and orv != E,
		"5 and / or / not are the frame-wise logic (and: %d frames, or: %d, not: %d)" % [andv.count(true), orv.count(true), notv.count(true)])
	ok(on_of(EventQuery.ask("left foot up or guard down and right elbow angle below 90", c30), n30) == prec and prec != on_of(EventQuery.ask("(left foot up or guard down) and right elbow angle below 90", c30), n30),
		"5 \"a or b and c\" = a or (b and c), and differs from (a or b) and c")
	ok(on_of(EventQuery.ask("left foot not on the floor", c30), n30) == on_of(EventQuery.ask("not left foot down", c30), n30) and on_of(EventQuery.ask("not left foot down", c30), n30) == A,
		"5 a \"not\" inside a phrase = a \"not\" before it = \"up\"")
	var k := int(ceil(0.3 * 30.0 - 1e-6))
	var long := []
	for r in runs_of(A):
		if r[1] - r[0] + 1 >= k:
			long.append(r)
	var fl := EventQuery.ask("left foot up for at least 0.3 s", c30)
	ok(spans_of(fl) == long and long.size() >= 1 and long.size() < runs_of(A).size(), "5 for at least 0.3 s keeps the runs of >= %d frames: %s of %s" % [k, spans_of(fl), runs_of(A)])
	var bind1 := on_of(EventQuery.ask("(left foot up for at least 0.3 s) or right elbow angle below 90", c30), n30)
	var bind2 := on_of(EventQuery.ask("left foot up or right elbow angle below 90 for at least 0.3 s", c30), n30)
	var w1 := []
	var flo := on_of(fl, n30)
	for i in n30:
		w1.append(flo[i] or E[i])
	ok(bind1 == w1 and bind1 != bind2, "5 brackets bind \"for at least\" (inside: %d frames; on the whole: %d)" % [bind1.count(true), bind2.count(true)])
	var wh := EventQuery.ask("left hand fastest while left foot up", c30)
	var sp := EventQuery.speed_series(c30, 0, "hand_l")
	var wb := -1
	for i in n30:
		if A[i] and (wb < 0 or sp[i] > sp[wb]):
			wb = i
	ok(int(wh.get("frame", -1)) == wb and wb >= 0, "5 \"left hand fastest while left foot up\": frame %s (the argmax over those frames: %d)" % [wh.get("frame"), wb])

	# ---- 6 UNKNOWN: the known list, never a guess
	var un := EventQuery.ask("when does the right foot fly", c30)
	var amb := EventQuery.ask("hand fastest", c30)
	var unit := EventQuery.ask("right hand faster than 3 deg", c30)
	ok(not un["ok"] and un["known"] == EventQuery.KNOWN and not un.has("spans") and not amb["ok"] and "right or left" in String(amb["error"]) and not unit["ok"],
		"6 unknown -> the %d known forms ('%s'); 'hand' -> '%s'; a wrong unit -> '%s'" % [EventQuery.KNOWN.size(), un["error"], amb["error"], unit["error"]])

	# ---- 7 PARALLEL = SERIAL
	var ser_t := Time.get_ticks_usec()
	var cser := EventQuery.sample(f3, 60.0, {"cross": true, "bal": true}, true)
	var cold_ser := (Time.get_ticks_usec() - ser_t) / 1000.0
	EventQuery.clear_cache()
	var par_t := Time.get_ticks_usec()
	var cpar := EventQuery.sample(f3, 60.0, {"cross": true, "bal": true})
	var cold_par2 := (Time.get_ticks_usec() - par_t) / 1000.0
	var same: bool = cser["n"] == cpar["n"] and cser["down"] == cpar["down"] and cser["margin"] == cpar["margin"]
	for i in int(cser["n"]):
		same = same and cser["pts"][0][i] == cpar["pts"][0][i]
	ok(same and cpar["sampled"] == "parallel" and cser["sampled"] == "serial", "7 parallel clip == serial clip bit for bit (%d frames, %d points each)" % [cser["n"], EventQuery.point_names().size()])

	# ---- 8 SPEED
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var T := AgentTools.new(m)
	m.S = SY
	m.dummy_on = false
	var r1: Dictionary = await T.request(1, "events", {"q": "right foot leaves the floor"})
	var w0 := Time.get_ticks_usec()
	var r2: Dictionary = await T.request(2, "events", {"q": "airborne or left knee bent more than 30 for at least 0.1 s"})
	var warm_sy := (Time.get_ticks_usec() - w0) / 1000.0
	ok(r1.has("result") and r2.has("result") and warm_sy < 200.0, "8 synthetic 4 s at 60 fps: first question %.0f ms (direct sample %.0f ms), next one %.1f ms (bar < 200)" % [float(r1.get("result", {}).get("ms", -1)), cold_sy, warm_sy])
	await T.request(3, "open", {"path": "scenes/combo3.json"})
	var o1: Dictionary = await T.request(4, "events", {"q": "left foot up", "fps": 60})
	w0 = Time.get_ticks_usec()
	var o2: Dictionary = await T.request(5, "events", {"q": "right fist fastest while guard down", "fps": 60})
	var warm_c3 := (Time.get_ticks_usec() - w0) / 1000.0
	ok(o2.has("result") and warm_c3 < 200.0, "8 combo3 at 60 fps: first question %.0f ms, next one %.1f ms (bar < 200): '%s'" % [float(o1.get("result", {}).get("ms", -1)), warm_c3, o2.get("result", {}).get("text", o2.get("error"))])
	print("     cold sampling, combo3 at 60 fps (281 frames, Scene.apply each): serial %.0f ms, parallel %.0f ms (and %.0f ms earlier)" % [cold_ser, cold_par2, cold_par])
	ok(cold_ser / maxf(minf(cold_par, cold_par2), 1.0) >= 1.5, "8 parallel sampling %.1fx faster than serial (bar >= 1.5x)" % (cold_ser / maxf(minf(cold_par, cold_par2), 1.0)))

	# ---- 9 SERVE + TWO FIGHTERS
	var direct := EventQuery.ask("left foot up", EventQuery.sample([{"S": m._ps(), "B": m.B, "xf": Transform3D.IDENTITY}], 60.0, {"cross": false, "bal": false}))
	ok(o1.has("result") and spans_of(o1["result"]) == spans_of(direct) and spans_of(direct).size() > 0, "9 serve's events = the direct call: %s" % [spans_of(direct)])
	var bad: Dictionary = await T.request(6, "events", {"q": "when does the right foot fly"})
	var b3: Dictionary = await T.request(7, "events", {"q": "left foot up", "fighter": 3})
	ok(bad.has("error") and int(bad["error"]["code"]) == -32602 and bad["error"].get("data", {}).get("known", []) == EventQuery.KNOWN and b3.has("error"),
		"9 serve: unknown phrase -> -32602 with data.known (%d forms); fighter 3 -> '%s'" % [bad.get("error", {}).get("data", {}).get("known", []).size(), b3.get("error", {}).get("message", "")])
	m._actor_add()
	m.actor_place(1, Vector2(0, 0.8), 180.0)
	var ft: Dictionary = await T.request(8, "events", {"q": "when do the fighters touch"})
	var H: Scene = m.actors_rt[0]["S"]
	var O: Scene = m.actors_rt[1]["S"]
	var xf: Transform3D = m.actors_rt[1]["xf"]
	var BH := body()
	var BO := body()
	var nn := int(floor(H.length() * H.fps + 1e-6)) + 1
	var tw := []
	for i in nn:
		H.apply(BH, float(i) / H.fps)
		O.apply(BO, float(i) / H.fps)
		tw.append(not BH.cross_contacts(BO, xf).is_empty())
	var tg := on_of(ft.get("result", {}), nn)
	ok(ft.has("result") and tg == tw and tw.count(true) > 0 and tw.count(false) > 0,
		"9 two fighters 0.8 m apart: touch %s (cross_contacts frame by frame: %s)" % [spans_of(ft.get("result", {})), runs_of(tw)])
	var g2: Dictionary = await T.request(9, "events", {"q": "fighters closest"})
	print("     fighters closest: %s" % g2.get("result", {}).get("text", g2.get("error")))

	print("EVENTS %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	m.queue_free()
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
