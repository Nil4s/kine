## godot --headless --path . -s tests/bodyframe_test.gd     (N007 BODY-FRAME NUMBERS, scripts/body_frame.gd)
## Bars, written BEFORE the first run:
##   1 round trip: for 212 points (200 seeded random in a 1.2 x 2.0 x 1.3 m box round an asymmetric pose, plus the 12
##     landmarks), words -> point -> words gives the SAME phrase for every one, and point -> words -> point is within
##     0.5 cm for every one (the rounding allows 0.087 cm). The INNOVATIONS example sentence reads to a point whose
##     own words read back to that point within 0.5 cm
##   2 a fighter turned 90 deg (and -90, 180), moved 1 m x 2 m: every one of the 212 points (carried with him) gets the
##     SAME words
##   3 left / right: 10 cm to +x of the standing sternum (+x is his left, body.gd) says "toward his left", his left hand's
##     joint says "the left hand"; the pose mirrored (Body.mirror_pose) with every point mirrored (x -> -x) gives the
##     words of the original with left and right swapped, for all 212 points
##   4 the other fighter (standing 1.5 m out, facing him, as the dummy): "at the opponent's chin" is his chin within
##     0.01 cm, its words are "level with the opponent's chin, at the opponent's chin height, not to either side",
##     "20 cm in front of the opponent's sternum" is 20 cm nearer the hero, "10 cm toward the opponent's left" is -x in
##     the hero's space; the 212-point round trip holds on him too
##   5 serve, in-process on main.tscn: measure without frame is unchanged by frame:"body" (the same JSON once each "body"
##     is taken out) and frame:"body" gives each distance's 2 parts in words; where {joint: hand_r} is hand_r's place
##     and place {its words} lands within 0.5 cm of it; where {of: opponent} speaks of the opponent; place "banana" is a
##     -32602 error that says what to send
## (the agent_tools transcript, bar 6 of the item, is its own suite: agent_tools)
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	B.ground()
	return B


func points(F: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7007
	var out := []
	for i in 200:
		out.append(Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.0, 2.0), rng.randf_range(-0.5, 0.8)))
	for k in BodyFrame.KEYS:
		out.append(F["lm"][k])
	return out


func swap_lr(s: String) -> String:
	return s.replace("left", "\u0001").replace("right", "left").replace("\u0001", "right")


func round_trip(F: Dictionary, O: Dictionary, pts: Array, opp: bool, tag: String) -> void:
	var same := 0
	var worst := 0.0
	var bad := ""
	for p: Vector3 in pts:
		var w1: String = BodyFrame.describe(p, F, opp)["words"]
		var r := BodyFrame.place(w1, O if opp else F, F if opp else O)
		if not r["ok"]:
			bad = w1 + " -> " + String(r["error"])
			continue
		var q: Vector3 = r["point"]
		var w2: String = BodyFrame.describe(q, F, opp)["words"]
		if w1 == w2:
			same += 1
		elif bad == "":
			bad = w1 + "  /  " + w2
		worst = maxf(worst, p.distance_to(q) * 100.0)
	ok(same == pts.size() and worst <= 0.5, "%s round trip: %d of %d phrases the same, point -> words -> point worst %.3f cm (bar 0.5)%s"
		% [tag, same, pts.size(), worst, "" if bad == "" else "; first miss: " + bad])


func _init() -> void:
	var B := body()
	B.set_ang("upperarm_r", Vector3(60, 20, 0))
	B.set_ang("calf_l", Vector3(40, 0, 0))
	B.set_ang("spine_02", Vector3(10, 0, 20))
	B.fk()
	var F := BodyFrame.fighter(B)
	var pts := points(F)
	print("     e.g. ", BodyFrame.describe(pts[0], F)["words"], "   |   ", BodyFrame.describe(pts[1], F)["words"])
	# 1
	round_trip(F, {}, pts, false, "1")
	var ex := "15 cm in front of the sternum, 3 cm above chin height, 10 cm toward his left"
	var r: Dictionary = BodyFrame.place(ex, F, {})
	var e1: Vector3 = r.get("point", Vector3.INF)
	var ew: String = BodyFrame.describe(e1, F)["words"] if r["ok"] else ""
	var e2: Vector3 = BodyFrame.place(ew, F, {}).get("point", Vector3.INF) if r["ok"] else Vector3.INF
	var sexp: Vector3 = F["lm"]["sternum"] + (F["fwd"] as Vector3) * 0.15 + (F["left"] as Vector3) * 0.10
	sexp.y = (F["lm"]["chin"] as Vector3).y + 0.03
	ok(r["ok"] and e1.distance_to(sexp) < 1e-5 and e1.distance_to(e2) * 100.0 <= 0.5,
		"1 the example reads to the point it says (%.5f cm off) and back to it within %.3f cm: \"%s\"" % [e1.distance_to(sexp) * 100.0, e1.distance_to(e2) * 100.0, ew])
	# 2
	for deg in [90.0, -90.0, 180.0]:
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(deg)), Vector3(1.0, 0.0, 2.0))
		var F2 := BodyFrame.fighter(B, xf)
		var same := 0
		var miss := ""
		for p: Vector3 in pts:
			var a: String = BodyFrame.describe(p, F)["words"]
			var b: String = BodyFrame.describe(xf * p, F2)["words"]
			if a == b:
				same += 1
			elif miss == "":
				miss = a + "  /  " + b
		ok(same == pts.size(), "2 turned %+d deg and moved: %d of %d points have the same words%s" % [int(deg), same, pts.size(), "" if miss == "" else "; first miss: " + miss])
	# 3
	var S0 := body()
	var FS := BodyFrame.fighter(S0)
	var wl: String = BodyFrame.describe((FS["lm"]["sternum"] as Vector3) + Vector3(0.10, 0, 0), FS)["words"]
	var wh: String = BodyFrame.describe(S0.P["hand_l"], FS)["words"]
	ok(wl.ends_with("10 cm toward his left") and wh == "level with the left hand, at left hand height, not to either side",
		"3 +x of the sternum: \"%s\"; the left hand joint: \"%s\"" % [wl, wh])
	var M := body()
	M.set_state(B.state())
	M.mirror_pose()
	M.fk()
	var FM := BodyFrame.fighter(M)
	var same := 0
	var miss := ""
	for p: Vector3 in pts:
		var a := swap_lr(BodyFrame.describe(p, F)["words"])
		var b: String = BodyFrame.describe(Vector3(-p.x, p.y, p.z), FM)["words"]
		if a == b:
			same += 1
		elif miss == "":
			miss = a + "  /  " + b
	ok(same == pts.size(), "3 mirrored pose, mirrored points: %d of %d say the same with left and right swapped%s" % [same, pts.size(), "" if miss == "" else "; first miss: " + miss])
	# 4
	var xo := Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 1.5))
	var O := BodyFrame.fighter(body(), xo)
	var oc: Vector3 = O["lm"]["chin"]
	var rc := BodyFrame.place("at the opponent's chin", F, O)
	var wc: String = BodyFrame.describe(oc, O, true)["words"]
	var os: Vector3 = O["lm"]["sternum"]
	var rf: Vector3 = BodyFrame.place("20 cm in front of the opponent's sternum", F, O)["point"]
	var rs: Vector3 = BodyFrame.place("level with the opponent's sternum, 10 cm toward the opponent's left", F, O)["point"]
	ok(rc["ok"] and (rc["point"] as Vector3).distance_to(oc) < 1e-4 and wc == "level with the opponent's chin, at the opponent's chin height, not to either side"
		and absf((os.z - rf.z) - 0.20) < 1e-4 and absf((rs.x - os.x) + 0.10) < 1e-4,
		"4 at the opponent's chin: %.4f cm off, words \"%s\"; in front of his sternum: %.1f cm nearer the hero; toward his left: %+.1f cm on x"
		% [(rc.get("point", Vector3.INF) as Vector3).distance_to(oc) * 100.0, wc, (os.z - rf.z) * 100.0, (rs.x - os.x) * 100.0])
	var opts := []
	for p: Vector3 in pts:
		opts.append(xo * p)
	round_trip(O, F, opts, true, "4 opponent")
	# 5
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var A := AgentTools.new(m)
	await A.request(1, "open", {"path": "scenes/combo3.json"})
	var what := ["distance hand_r head", "height head", "com", "balance"]
	var r0: Dictionary = await A.request(2, "measure", {"t": 0.5, "what": what})
	var r1: Dictionary = await A.request(3, "measure", {"t": 0.5, "what": what, "frame": "body"})
	var strip: Dictionary = JSON.parse_string(JSON.stringify(r1))
	var nb := 0
	for e: Dictionary in strip.get("result", {}).get("measures", []):
		if e.has("body"):
			nb += (e["body"] as Array).size()
			e.erase("body")
	var d0: Array = r1.get("result", {}).get("measures", [{}])[0].get("body", [])
	ok(r0.has("result") and JSON.stringify(strip.get("result")) == JSON.stringify(JSON.parse_string(JSON.stringify(r0)).get("result")) and d0.size() == 2 and nb == 4,
		"5 measure frame:body: the rest of the answer is the default's exactly, %d parts in words (distance: %s)" % [nb, d0.map(func(x): return x["part"] + ": " + x["words"])])
	var w1: Dictionary = await A.request(4, "where", {"joint": "hand_r"})
	var hr: Vector3 = m.B.P["hand_r"]
	var wr: Dictionary = w1.get("result", {})
	var p1: Dictionary = await A.request(5, "place", {"text": wr.get("words", "")})
	var pp: Array = p1.get("result", {}).get("point", [INF, INF, INF])
	var pv := Vector3(pp[0], pp[1], pp[2])
	var w2: Dictionary = await A.request(6, "where", {"joint": "hand_r", "of": "opponent"})
	var e3: Dictionary = await A.request(7, "place", {"text": "banana"})
	ok(String(wr.get("words", "")).begins_with("level with the right hand") and pv.distance_to(hr) * 100.0 <= 0.5
		and String(w2.get("result", {}).get("words", "")).contains("the opponent's")
		and int(e3.get("error", {}).get("code", 0)) == -32602 and String(e3.get("error", {}).get("message", "")).contains("cm in front of"),
		"5 where hand_r: \"%s\"; place it back: %.3f cm off; of opponent: \"%s\"; banana: %s"
		% [wr.get("words", w1), pv.distance_to(hr) * 100.0, w2.get("result", w2).get("words", w2), e3.get("error", {}).get("message", e3)])
	m.queue_free()
	print("BODYFRAME TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
