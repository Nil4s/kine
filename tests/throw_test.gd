## godot --headless --path . -s tests/throw_test.gd     (GATES WW8, UPGRADES_300 #308; headless is fine)
## THROWN PROPS. A prop let go by a MOVING hand leaves with the hand's velocity (the held prop's origin over the 1/60 s
## before the let-go) and flies p(t) = p0 + v0 t + g t^2 / 2 until it meets the top or floor under its current xz, then
## bounces with restitution e = 0.3 (MINE, unverified: no measured value for a box or crate on a floor was found) on the
## vertical, keeps its horizontal speed, and STOPS at the first bounce whose rebound apex is under 2 cm. Checked against
## the formulas: apex v_y^2 / 2g, time of flight, range, bounce apex e^2 times the last (1 mm / 1 ms). A still hand gives
## round 39's straight fall (no trajectory, no bounce); a scene with no carry reads the same set as ever; Check finds
## nothing "through" the released prop during RELEASE.
extends SceneTree

var fails := 0
const G := 9.81


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func scene(moves: Array, drop_card: int, flow := false) -> Scene:
	var B := body()
	var c := B.cap("hand_r")
	var mid: Vector3 = ((c[0] as Vector3) + (c[1] as Vector3)) / 2.0
	var h: float = mid.y - float(B.rad["hand_r"]) + 0.01
	Props.register("zz pillar", AABB(Vector3(-0.05, 0, -0.05), Vector3(0.1, h, 0.1)), "", 1.0)
	var S := Scene.new()
	S.name = "zz_throw"
	S.props = [Props.make("zz pillar", Props.xf_at(Vector3(mid.x, 0, mid.z), 0.0))]
	S.on_floor = false
	S.pin = false
	S.add("rest", B.to_dict())
	for mv in moves:
		B.offset += mv
		B.fk()
		S.add("m", B.to_dict())
	S.cards[0]["take"] = {"prop": 0, "hands": ["_r"]}
	S.cards[drop_card]["drop"] = 0
	if flow:
		S.cards[drop_card]["flow"] = true   # a pass-through key: the hand is still moving when it lets go
	return S


func origin(S: Scene, B: Body, t: float) -> Vector3:
	S.apply(B, t)
	return (S.props_at(t, B)[0]["xf"] as Transform3D).origin


func _init() -> void:
	# 1. the pure flight, exact numbers: from (0, 1.2, 0) at (2, 3, 0)
	var tr := Throw.trajectory(Vector3(0, 1.2, 0), Vector3(2, 3, 0), [], 0.3)
	var apex_t := 3.0 / G
	var apex_y := 1.2 + 9.0 / (2.0 * G)
	var p := Throw.pos_at(tr, apex_t)
	ok(absf(p.y - apex_y) < 0.001, "apex height %.4f m vs v_y^2/2g + y0 = %.4f (bar 1 mm)" % [p.y, apex_y])
	var tf := (3.0 + sqrt(9.0 + 2.0 * G * 1.2)) / G
	var hit: Array = tr["hits"][0]
	ok(absf(float(hit[0]) - tf) < 0.001, "time of flight %.4f s vs %.4f (bar 1 ms)" % [hit[0], tf])
	var pc := Throw.pos_at(tr, tf)
	ok(absf(pc.x - 2.0 * tf) < 0.001 and absf(pc.y) < 0.001, "range %.4f m vs v_x t = %.4f; lands at y %.4f" % [pc.x, 2.0 * tf, pc.y])
	var vin: float = hit[1]
	var apex2 := Throw.pos_at(tr, tf + 0.3 * absf(vin) / G).y
	var want2 := 0.09 * vin * vin / (2.0 * G)
	ok(absf(apex2 - want2) < 0.001 and want2 > 0.02, "bounce apex %.4f m vs e^2 * v_in^2/2g = %.4f (bar 1 mm)" % [apex2, want2])
	var vin2: float = tr["hits"][1][1]
	ok(absf(vin2 + 0.3 * absf(vin)) < 0.001, "second impact speed %.4f vs e * first = %.4f" % [vin2, -0.3 * absf(vin)])
	var apex3 := 0.09 * vin2 * vin2 / (2.0 * G)
	ok(apex3 < 0.02 and int(tr["bounces"]) == tr["hits"].size() and Throw.pos_at(tr, 9.0).distance_to(tr["rest"]) == 0.0,
		"third apex %.4f m < 2 cm: it stops at the 2nd contact, %d contacts, at rest %s" % [apex3, tr["bounces"], tr["rest"]])
	# onto a table top: lands at the top's height, not the floor
	var table := Props.make("table", Props.xf_at(Vector3.ZERO, 0.0))
	var top := 0.0
	for s in Props.supports(table):
		top = maxf(top, float(s["y"]))
	var tr2 := Throw.trajectory(Vector3(0.1, top + 0.5, 0.0), Vector3(0.3, 0, 0), [table], 0.3)
	ok(absf((tr2["rest"] as Vector3).y - top) < 0.001, "thrown over a table: rests on its top y %.3f (top %.3f)" % [(tr2["rest"] as Vector3).y, top])
	var tr3 := Throw.trajectory(Vector3(0.1, top + 0.5, 0.0), Vector3(3.0, 0, 0), [table], 0.3)
	ok((tr3["rest"] as Vector3).y == 0.0, "thrown clear of the table: past its edge it falls to the floor (rest y %.3f, x %.2f)" % [(tr3["rest"] as Vector3).y, (tr3["rest"] as Vector3).x])
	# 2. the scene: right hand swings 1 m, 1 m + 25 cm, 1 m; let go on the flow card 3 (index 2) while moving
	var B := body()
	var S := scene([Vector3(1, 0, 0), Vector3(1, 0.25, 0), Vector3(1, 0, 0)], 2, true)
	var ts := S.times()
	var tb: float = ts[2][1]
	var home := (S.props[0]["xf"] as Transform3D).origin
	var a := origin(S, B, tb - 1.0 / 60.0)
	var b := origin(S, B, tb - 1e-9)
	var v0 := (b - a) * 60.0
	var d: Dictionary = S._carry_data(B)[0]
	ok(d.has("tr"), "a moving hand: the drop has a trajectory (v0 = %s m/s)" % v0)
	var got_v: Vector3 = d["tr"]["segs"][0]["v"]
	ok(got_v.distance_to(v0) < 0.05 and v0.length() > 0.2, "  its v0 %s vs the held prop's drift %s (bar 5 cm/s; moving > 0.2 m/s)" % [got_v, v0])
	var p0: Vector3 = (d["drop"] as Transform3D).origin
	var worst := 0.0
	for dt in [0.02, 0.05, 0.1]:
		var want: Vector3 = p0 + got_v * dt + Vector3(0, -G * dt * dt / 2.0, 0)
		if want.y > 0.0:
			worst = maxf(worst, origin(S, B, tb + dt).distance_to(want))
	ok(worst < 0.001, "props_at follows p0 + v0 t + g t^2/2: off by at most %.3f mm at 20, 50, 100 ms" % (worst * 1000.0))
	var tr_s: Dictionary = d["tr"]
	var h0: float = tr_s["hits"][0][0]
	ok(absf(origin(S, B, tb + h0 + 0.0005).y) < 0.002 and h0 > 0.0, "first contact %.3f s after the let-go, at the floor" % h0)
	ok(origin(S, B, tb + 9.0).distance_to(tr_s["rest"]) < 1e-6 and absf((tr_s["rest"] as Vector3).y) < 1e-6, "at rest at %s" % tr_s["rest"])
	var fs := Rulebook.check(S, body())
	var thr := fs.filter(func(f): return f["rule"] == "THROUGH A PROP")
	ok(thr.is_empty(), "Check: nothing through the thrown prop (%d findings)" % fs.size())
	# 3. a still hand: round 39's fall exactly, no trajectory
	var S2 := scene([Vector3(0, 0.25, 0), Vector3.ZERO], 2)
	var ts2 := S2.times()
	var tb2: float = ts2[2][1]
	var d2: Dictionary = S2._carry_data(B)[0]
	ok(not d2.has("tr"), "a still hand (card 3 = card 2): no trajectory, the plain drop")
	var y0: float = (d2["drop"] as Transform3D).origin.y
	var w2 := 0.0
	for dt in [0.05, 0.10, 0.20]:
		w2 = maxf(w2, absf(origin(S2, B, tb2 + dt).y - (y0 - G * dt * dt / 2.0)))
	ok(w2 < 1e-6 and origin(S2, B, tb2 + 0.9).y == 0.0, "  y0 - g t^2/2 (worst %.9f m; bar 1 um, single-precision transforms), then the floor" % w2)
	# 3b. thrown UP: the scene's own apex and flight against the formulas, from the measured drift
	var S4 := scene([Vector3(0, 0.4, 0), Vector3(0, 0.4, 0), Vector3(0, 0.4, 0)], 2, true)
	var tb4: float = S4.times()[2][1]
	var v4 := (origin(S4, B, tb4 - 1e-9) - origin(S4, B, tb4 - 1.0 / 60.0)) * 60.0
	var d4: Dictionary = S4._carry_data(B)[0]
	var q0: Vector3 = (d4["drop"] as Transform3D).origin
	var apex_s := q0.y + v4.y * v4.y / (2.0 * G)
	var best := 0.0
	for k in 400:
		best = maxf(best, origin(S4, B, tb4 + k * 0.002).y)
	var tfl := (v4.y + sqrt(v4.y * v4.y + 2.0 * G * q0.y)) / G
	ok(v4.y > 0.2 and absf(best - apex_s) < 0.001, "thrown up at %.3f m/s: apex %.4f m vs y0 + v_y^2/2g = %.4f (bar 1 mm)" % [v4.y, best, apex_s])
	ok(absf(float(d4["tr"]["hits"][0][0]) - tfl) < 0.001, "  time of flight %.4f s vs %.4f (bar 1 ms)" % [d4["tr"]["hits"][0][0], tfl])
	# 4. no carry: the set itself
	var S3 := Scene.new()
	S3.props = [Props.make("table", Props.xf_at(Vector3.ZERO, 0.0))]
	ok(is_same(S3.props_at(0.5, B), S3.props), "no carry: props_at returns the set itself")
	print("THROW TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
