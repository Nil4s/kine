## godot --path . -s tests/reactweight_test.gd     (window suite: reactweight:w)   L89: L29 reaction auto-timing + L23 "make it heavier / lighter".
## Written BEFORE the implementation (scripts/react_time.gd, the slider in scripts/weight_feel.gd, tools react_time / react_place / weight_slider).
## SOURCE of the reaction time: Counter.REACT = 0.29 s, the MEASURED simple visual reaction time of elite karate athletes, 292 +- 45 ms (n=28),
##   Liu, See, Chang et al. 2018, Arch Budo 14 (abstract), the figure that commit ce537bf4 "measured 0.29 s reaction time" moved the i31 fixture past.
##   A block is a choice response, so 0.29 s is the KIND bound. SUPERHUMAN = 0.20 s = 0.29 - 2 x 0.045 (mean minus two SD of the same sample;
##   the old textbook simple RT of Woodworth & Schlosberg 1954 is the same 0.20 s).
## DEFINITIONS (fixed here): cue = the first frame (1/60 s steps) at which any joint of the ATTACKER is more than 2 deg from its frame 0 pose;
##   block start = the start of the move into the defender's first card named like a block (FightRhythm.BLOCK_WORDS); gap = block start - cue.
## RT bars (the attacker: guard held 0.5 s, then a wind-up, a jab; the defender stands, then blocks; blocks placed at cue + gap):
##  R1 the cue is found within [0.50, 0.60] s and equals this test's own 1/60 s scan within 1 frame (1/30 s); Counter.REACT == 0.29.
##  R2 gaps 0.08 (PLANTED) and 0.15 are flagged "superhuman"; gaps 0.25, 0.29, 0.45 are not (status ok).
##  R3 place: for every gap the block start becomes cue + 0.29 within 1 frame (1/30 s); the block's own move length is unchanged, every later card
##     keeps its move and hold, the attacker is byte-identical, the defender's poses are untouched; read after place says ok.
##  R4 CONTROLS: an attacker that never moves: read says "no cue" (cue -1), place is refused and the defender is byte-identical; a defender with
##     no block card: "no block", refused, byte-identical.
##  R5 in the app (file opened): react_time answers the status; react_place on the planted 80 ms clip is exactly 1 undo step and one undo gives the
##     scene back byte for byte; on the no-cue clip it is an error and adds no undo step.
## WEIGHT bars (hero: guard, wind-up 0.3+0.1, jab 0.15 = the contact card with the hit marker, guard 0.2+0.3; slider value s = log2 of the mass ratio):
##  W1 peak velocity (this test's own measure: the biggest joint angle change of the move into the contact card / its time, from Scene.sample)
##     at s = 1 / 2 / -1 (mass x2 / x4 / x0.5) is the original / ratio (impulse / mass) within 5 %.
##  W2 anticipation (start of the first move -> start of the contact move) strictly increases over s = -1 -0.5 0 0.5 1 1.5 2, and at s = 1 it is
##     original x sqrt(2) within 5 %; settle (contact arrival -> the end) strictly increases and is original x sqrt(2) within 5 % at s = 1.
##  W3 slider 0 on the original: to_dict JSON byte-identical; the same value twice = once; s = 2 after s = 1 equals s = 2 from the original (2 ms).
##  W4 contacts and plants: the contact hand and both feet at every card's arrival differ from the original by < 5 mm at s = -1, 1, 2;
##     the hit marker stays on the contact card's arrival (1 ms). CONTROL: a clip whose contact pose is bent 10 deg more fails the same measure.
##  W5 a clip without a hit marker is refused with a next step and unchanged.
##  W6 in the app: weight_slider is exactly 1 undo step, one undo gives the clip back byte for byte; the same value again adds no step.
##  T  react_time, react_place, weight_slider are in AgentTools.MCP_EXTRA and tools/mcp/poser_mcp.py; tools/run_all.sh lists reactweight.
extends SceneTree

var fails := 0
var m: Node
var stand: Dictionary
var punch_r: Dictionary
const FR := 1.0 / 30.0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func control(claim: bool, what: String) -> void:
	print(("ok   control caught: " if not claim else "FAIL control NOT caught: ") + what)
	if claim:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func make_poses() -> void:
	var b := DistanceKeeper.new_body()
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	stand = b.to_dict()
	b.fk()
	b.from_dict(stand)
	b.ang["upperarm_r"] = Vector3(-90, 0, 0)
	b.fk()
	punch_r = b.to_dict()


func bent_punch() -> Dictionary:
	var b := DistanceKeeper.new_body()
	b.from_dict(punch_r)
	b.ang["upperarm_r"] = (b.ang["upperarm_r"] as Vector3) + Vector3(10, 0, 0)
	b.fk()
	return b.to_dict()


## the attacker: guard (hold 0.5), wind-up (0.3 + 0.1), jab (0.15; the contact card, card 2), guard (0.2 + 0.3)
func hero(punch := {}, marker := true) -> Scene:
	var pr: Dictionary = punch_r if punch.is_empty() else punch
	var wind := FightRhythm.blend_pose(stand, pr, 0.5)
	var S := Scene.new()
	S.from_dict({"scene": "zz_hero", "fps": 30, "cards": [{"name": "guard", "pose": stand, "move": -1.0, "hold": 0.5},
		{"name": "wind-up", "pose": wind, "move": 0.3, "hold": 0.1}, {"name": "jab", "pose": pr, "move": 0.15, "hold": 0.0},
		{"name": "guard", "pose": stand, "move": 0.2, "hold": 0.3}]})
	if marker:
		Markers.add(S.markers, float(S.times()[2][1]), "hit", "hit")
	return S


func still() -> Scene:
	var S := Scene.new()
	S.from_dict({"scene": "zz_still", "fps": 30, "cards": [{"name": "guard", "pose": stand, "move": -1.0, "hold": 0.8},
		{"name": "guard", "pose": stand, "move": 0.3, "hold": 0.6}]})
	return S


## the defender: stands `onset` s, then a block move of 0.25 s (hold 0.2), then a guard card (move 0.3, hold 0.4)
func blocker(onset: float, name := "block") -> Scene:
	var S := Scene.new()
	S.from_dict({"scene": "zz_blocker", "fps": 30, "cards": [{"name": "guard", "pose": stand, "move": -1.0, "hold": onset},
		{"name": name, "pose": stand, "move": 0.25, "hold": 0.2}, {"name": "guard", "pose": stand, "move": 0.3, "hold": 0.4}]})
	return S


func js(S: Scene) -> String:
	return JSON.stringify(S.to_dict(DistanceKeeper.new_body(), false))


## this test's own cue: the first 1/60 s frame at which a joint of the scene is more than 2 deg from frame 0
func own_cue(S: Scene) -> float:
	var a0: Dictionary = S.sample(0.0)["ang"]
	for f in range(1, int(S.length() * 60.0)):
		var t := float(f) / 60.0
		var a: Dictionary = S.sample(t)["ang"]
		for j in a:
			var d: Vector3 = ((a[j] as Vector3) - (a0.get(j, Vector3.ZERO) as Vector3)).abs()
			if maxf(d.x, maxf(d.y, d.z)) > 2.0:
				return t
	return -1.0


func peak_speed(S: Scene, c: int) -> float:
	var ts := S.times()
	var a0: Dictionary = S.sample(float(ts[c][0]))["ang"]
	var a1: Dictionary = S.sample(float(ts[c][1]))["ang"]
	var big := 0.0
	for j in a1:
		var d: Vector3 = ((a1[j] as Vector3) - (a0.get(j, Vector3.ZERO) as Vector3)).abs()
		big = maxf(big, maxf(d.x, maxf(d.y, d.z)))
	return big / (float(ts[c][1]) - float(ts[c][0]))


func anticip(S: Scene, c: int) -> float:
	return float(S.times()[c][0]) - float(S.times()[1][0])


func settle(S: Scene, c: int) -> float:
	return float(S.times()[-1][2]) - float(S.times()[c][1])


## worst distance (mm) of the contact hand and both balls of the feet, at every card's arrival, between two scenes of the same card count
func worst_mm(a: Scene, b: Scene) -> float:
	var ba := DistanceKeeper.new_body()
	var bb := DistanceKeeper.new_body()
	var ta := a.times()
	var tb := b.times()
	var w := 0.0
	for i in a.cards.size():
		a.apply(ba, float(ta[i][1]))
		b.apply(bb, float(tb[i][1]))
		for k in ["hand_r", "ball_l", "ball_r"]:
			w = maxf(w, (ba.E[k] as Vector3).distance_to(bb.E[k] as Vector3))
	return w * 1000.0


func pair(A: Scene, D: Scene) -> Scene:
	var S := A.clone()
	S.actors = [{"name": "B", "xf": {"pos": [0.0, 1.1], "yaw": 180.0}, "scene": D}]
	return S


func save(S: Scene, name: String) -> String:
	DirAccess.make_dir_recursive_absolute("user://reactweight")
	var p := ProjectSettings.globalize_path("user://reactweight/" + name + ".json")
	var fh := FileAccess.open(p, FileAccess.WRITE)
	fh.store_string(JSON.stringify(S.to_dict(DistanceKeeper.new_body(), false)))
	fh.close()
	return p


func state() -> String:
	return JSON.stringify(m.S.to_dict(m.B, false))


func _init() -> void:
	create_timer(240.0).timeout.connect(func():
		print("REACTWEIGHT WATCHDOG: the test did not finish")
		quit(2))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	make_poses()

	# ---------------------------------------------------------------- RT
	var A := hero()
	var cue := ReactTime.cue(A)
	var oc := own_cue(A)
	print("     cue %.4f s (own scan %.4f s); Counter.REACT %.3f" % [cue, oc, Counter.REACT])
	ok(cue >= 0.50 and cue <= 0.60 and absf(cue - oc) <= FR and absf(Counter.REACT - 0.29) < 1e-9, "R1 cue %.3f s in [0.50, 0.60], own scan %.3f s, REACT 0.29" % [cue, oc])
	for g in [0.08, 0.15, 0.25, 0.29, 0.45]:
		var D := blocker(cue + g)
		var r: Dictionary = ReactTime.read(A, D)
		var want := "superhuman" if g < 0.20 else "ok"
		ok(String(r.get("status", "")) == want and absf(float(r.get("gap", -1.0)) - g) <= FR, "R2 block %.2f s after the cue: status %s (want %s), gap %.3f" % [g, r.get("status"), want, float(r.get("gap", -1.0))])
		var ja := js(A)
		var d0 := D.clone()
		var pl: Dictionary = ReactTime.place(A, D)
		var t0 := D.times()
		var onset := float(t0[1][0])
		var same_moves := true
		for i in range(1, D.cards.size()):
			if absf(D.move_time(i) - d0.move_time(i)) > 1e-6 or (i >= 2 and absf(float(D.cards[i]["hold"]) - float(d0.cards[i]["hold"])) > 1e-6):
				same_moves = false
		var poses_same := true
		for i in D.cards.size():
			if D.cards[i]["pose"] != d0.cards[i]["pose"]:
				poses_same = false
		ok(bool(pl.get("ok", false)) and absf(onset - (cue + 0.29)) <= FR, "R3 gap %.2f placed: block starts %.3f s = cue + 0.29 = %.3f (within 1 frame)" % [g, onset, cue + 0.29])
		ok(same_moves and poses_same and js(A) == ja and String(ReactTime.read(A, D).get("status", "")) == "ok", "R3 gap %.2f: moves, later holds and poses untouched, attacker byte-identical, read after place ok" % g)
	# controls
	var St := still()
	var Dn := blocker(0.4)
	var jd := js(Dn)
	var rn: Dictionary = ReactTime.read(St, Dn)
	var pn: Dictionary = ReactTime.place(St, Dn)
	ok(String(rn.get("status", "")) == "no cue" and float(rn.get("cue", 0.0)) < 0.0 and not bool(pn.get("ok", true)) and js(Dn) == jd, "R4 control: a still attacker is 'no cue' and the block is never shifted (%s)" % str(pn.get("msg", "")))
	var Dx := blocker(0.4, "reach")
	var jx := js(Dx)
	var rx: Dictionary = ReactTime.read(A, Dx)
	var px: Dictionary = ReactTime.place(A, Dx)
	ok(String(rx.get("status", "")) == "no block" and not bool(px.get("ok", true)) and js(Dx) == jx, "R4 control: a defender without a block card is 'no block' and unchanged")

	# ---------------------------------------------------------------- WEIGHT
	var H := hero()
	var j0 := js(H)
	var v0 := peak_speed(H, 2)
	var an0 := anticip(H, 2)
	var st0 := settle(H, 2)
	var W := {}
	for s in [-1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 2.0]:
		var X := hero()
		var r: Dictionary = WeightFeel.slider(X, s)
		W[s] = X
		ok(bool(r.get("ok", false)) or s == 0.0, "     slider %.1f: %s" % [s, str(r.get("msg", "")).left(110)])
	for s in [1.0, 2.0, -1.0]:
		var ratio := pow(2.0, float(s))
		var v := peak_speed(W[s], 2)
		ok(absf(v / v0 - 1.0 / ratio) <= 0.05 / ratio, "W1 mass x%.2f: peak velocity x%.3f, impulse/mass says x%.3f (within 5 %%)" % [ratio, v / v0, 1.0 / ratio])
	var last_a := -1.0
	var last_s := -1.0
	var mono := true
	for s in [-1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 2.0]:
		var a := anticip(W[s], 2)
		var se := settle(W[s], 2)
		if a <= last_a or se <= last_s:
			mono = false
		last_a = a
		last_s = se
	ok(mono, "W2 anticipation and settle strictly increase from mass x0.5 to x4")
	ok(absf(anticip(W[1.0], 2) / an0 - sqrt(2.0)) <= 0.05 * sqrt(2.0) and absf(settle(W[1.0], 2) / st0 - sqrt(2.0)) <= 0.05 * sqrt(2.0),
		"W2 at x2: anticipation x%.3f, settle x%.3f (sqrt 2 = 1.414, within 5 %%)" % [anticip(W[1.0], 2) / an0, settle(W[1.0], 2) / st0])
	ok(js(W[0.0]) == j0, "W3 slider 0 on the original: byte-identical")
	var twice := hero()
	WeightFeel.slider(twice, 1.0)
	var once_js := js(twice)
	var r_again: Dictionary = WeightFeel.slider(twice, 1.0)
	ok(js(twice) == once_js and not bool(r_again.get("ok", true)), "W3 the same value twice = once (the second is refused, nothing changes)")
	var tt := hero()
	WeightFeel.slider(tt, 1.0)
	WeightFeel.slider(tt, 2.0)
	var worst_t := 0.0
	for i in tt.cards.size():
		worst_t = maxf(worst_t, absf(tt.move_time(i) - W[2.0].move_time(i)))
		worst_t = maxf(worst_t, absf(float(tt.cards[i]["hold"]) - float(W[2.0].cards[i]["hold"])))
	ok(worst_t <= 0.002, "W3 s = 2 after s = 1 equals s = 2 from the original (worst %.4f s)" % worst_t)
	for s in [-1.0, 1.0, 2.0]:
		var w := worst_mm(H, W[s])
		var mk := -1.0
		for k in W[s].markers:
			if String(k["kind"]) == "hit":
				mk = float(k["t"])
		ok(w < 5.0 and absf(mk - float(W[s].times()[2][1])) <= 0.001, "W4 s=%.0f: contact hand and feet at every card arrival within %.3f mm, hit marker on the contact (%.3f vs %.3f)" % [s, w, mk, float(W[s].times()[2][1])])
	var bad := worst_mm(H, hero(bent_punch()))
	control(bad < 5.0, "W4 a contact pose bent 10 deg more is %.1f mm off, over the 5 mm bar" % bad)
	var Nm := hero({}, false)
	var jn := js(Nm)
	var rnm: Dictionary = WeightFeel.slider(Nm, 1.0)
	ok(not bool(rnm.get("ok", true)) and js(Nm) == jn and String(rnm.get("msg", "")).contains("hit"), "W5 no hit marker: refused with a next step, unchanged (%s)" % str(rnm.get("msg", "")).left(100))

	# ---------------------------------------------------------------- the app
	var T := AgentTools.new(m)
	var rid := 1
	var cs := [["planted80", pair(A, blocker(cue + 0.08))], ["nocue", pair(St, blocker(0.4))]]
	for cc in cs:
		var path := save(cc[1], cc[0])
		rid += 1
		await T.request(rid, "open", {"path": path})
		await idle()
		var b0 := state()
		var u0: int = m.undo.size()
		rid += 1
		var rd: Dictionary = await T.request(rid, "react_time", {})
		var st := String(rd.get("result", {}).get("status", rd.get("error", "?")))
		ok(m.undo.size() == u0 and state() == b0, "R5 %s: react_time reads '%s' and changes nothing" % [cc[0], st])
		rid += 1
		var rp: Dictionary = await T.request(rid, "react_place", {})
		if cc[0] == "planted80":
			ok(st == "superhuman" and rp.has("result") and state() != b0 and m.undo.size() == u0 + 1, "R5 planted 80 ms: flagged, react_place = exactly 1 undo step (%d -> %d) %s" % [u0, m.undo.size(), str(rp.get("error", ""))])
			m._undo()
			ok(state() == b0 and m.undo.size() == u0, "R5 one undo gives the scene back byte for byte")
		else:
			ok(st == "no cue" and rp.has("error") and state() == b0 and m.undo.size() == u0, "R5 no-cue clip: react_place is an error, no undo step, unchanged")
	var wp := save(hero(), "weight")
	rid += 1
	await T.request(rid, "open", {"path": wp})
	await idle()
	var w0 := state()
	var wu: int = m.undo.size()
	rid += 1
	var wr: Dictionary = await T.request(rid, "weight_slider", {"value": 1.0})
	ok(wr.has("result") and state() != w0 and m.undo.size() == wu + 1, "W6 weight_slider 1.0: changed, exactly 1 undo step (%d -> %d) %s" % [wu, m.undo.size(), str(wr.get("error", ""))])
	rid += 1
	await T.request(rid, "weight_slider", {"value": 1.0})
	ok(m.undo.size() == wu + 1, "W6 the same value again adds no step")
	m._undo()
	ok(state() == w0 and m.undo.size() == wu, "W6 one undo gives the clip back byte for byte")

	# ---------------------------------------------------------------- tools and run_all
	var mcp := FileAccess.get_file_as_string("res://tools/mcp/poser_mcp.py")
	var all_in := true
	for tn in ["react_time", "react_place", "weight_slider"]:
		if not (tn in AgentTools.MCP_EXTRA) or not mcp.contains("\"" + tn + "\""):
			all_in = false
	ok(all_in, "T react_time, react_place, weight_slider are in MCP_EXTRA and poser_mcp.py")
	ok(FileAccess.get_file_as_string("res://tools/run_all.sh").contains("reactweight"), "T run_all.sh lists reactweight")
	print("REACTWEIGHT: %s (%d fails)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
