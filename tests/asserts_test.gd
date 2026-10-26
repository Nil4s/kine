## godot --headless --path . -s tests/asserts_test.gd     (INNOVATIONS N002, BODY ASSERTIONS: scripts/body_assert.gd)
## A synthetic clip whose geometry the test builds and reads itself, so every miss has a known answer:
##   30 fps, 4 cards held a second each, joined by 1 ms moves (no grid frame falls inside a move: each frame is exactly
##   one card's pose; the switch frames are 31 / 61 / 91 by construction):
##     card 1 (0-1 s) rest;  card 2 (1-2 s) right elbow flexed 90, the upper arm raised 80;  card 3 (2-3 s) card 2 slid
##     5 cm along +x;  card 4 (3-4 s) card 3 with the left knee raised (thigh bend 40).
##   Fighter 2 (an actor, rest, facing the hero) is placed so his head capsule is 0.5 cm from the hero's right fist
##   capsule in card 2 (bisection on his distance, to 1e-7 m, with the test's own Body.seg_seg).
## BARS (written before the first run):
##   1 each kind passes when true and fails when false: planted, touches, inside, angle (below / between), distance (at
##     least / at most), speed (under / over): 15 lines, each pass / fail as built.
##   2 the miss is the analytic one within 1 mm (cm values within 0.1), 0.1 deg, 0.001 m/s, and at the analytic frame
##     (exact frame): slide 5 cm - 2.5 = 2.5 cm at frame 61; lift at card 4; fist gap at 0.6 s - 1 cm; elbow 30 deg;
##     elbow 100 deg at frame 0; head gap 30 cm - the clip's smallest gap at its first frame; pelvis 0.75 - 0.5 m/s at
##     frame 60; COM past the right foot at card 4.
##   3 the event window's time miss is exact: "touches at 0.6 s +-1 f" holds first at frame 31: 12 frames late.
##   4 an unread line returns the grammar (error + the GRAMMAR lines), counted as unread, never as a pass.
##   5 saved assertions round-trip: to_dict -> JSON text -> from_dict gives the same lines; the file validates against
##     docs/scene.schema.json; Mirror swaps left <-> right in them.
##   6 Check (Rulebook.check) shows a failing saved assertion as one MUST FIX "ASSERT" finding with the miss (30 deg) at
##     its frame's card; a passing one adds nothing; an unread saved one is a "look".
##   7 serve: on a live poser, `assert {lines, save}` answers the same numbers, keeps the lines, and `check` lists the
##     failing one; `assert` with an unread line carries the grammar.
extends SceneTree

var fails := 0
const FPS := 30.0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


func near(a: Variant, b: float, tol: float) -> bool:
	return a != null and absf(float(a) - b) <= tol


func res_of(r: Dictionary, line: String) -> Dictionary:
	for x in r["results"]:
		if x["line"] == line:
			return x
	return {}


func fist_head_gap(S: Scene, B: Body, B2: Body, t: float) -> float:
	S.apply_true(B, t)
	(S.actors[0]["scene"] as Scene).apply_true(B2, t)
	var X := Constraints.actor_xf(S.actors[0]["xf"])
	var c: Array = B.cap("hand_r")
	var h: Array = B2.cap("head")
	return Body.seg_seg(c[0], c[1], X * (h[0] as Vector3), X * (h[1] as Vector3)) - float(B.rad["hand_r"]) - float(B2.rad["head"])


func build() -> Scene:
	var B := body()
	var S := Scene.new()
	S.name = "zz_asserts"
	S.fps = 30
	S.natural = false
	S.on_floor = false
	S.pin = false
	S.add("rest", B.to_dict())
	B.set_ang("upperarm_r", Vector3(80, 0, 0))
	B.set_ang("lowerarm_r", Vector3(90, 0, 0))
	B.fk()
	S.add("punch", B.to_dict())
	B.offset = Vector3(0.05, 0, 0)
	B.fk()
	S.add("slid", B.to_dict())
	B.set_ang("thigh_l", Vector3(40, 0, 0))
	B.fk()
	S.add("knee", B.to_dict())
	for i in S.cards.size():
		S.cards[i]["hold"] = 1.0 if i == 0 else 0.999
		S.cards[i]["move"] = -1.0 if i == 0 else 0.001
	# fighter 2: rest, facing the hero (yaw 180), at z = D
	var S2 := Scene.new()
	S2.name = "zz_b"
	S2.natural = false
	S2.on_floor = false
	S2.pin = false
	var R := body()
	S2.add("a", R.to_dict())
	S2.add("b", R.to_dict())
	S2.cards[0]["hold"] = 2.0
	S2.cards[1]["hold"] = 2.0
	S.actors = [{"name": "B", "xf": {"pos": [0.0, 1.0], "yaw": 180.0}, "scene": S2}]
	var lo := 0.0
	var hi := 3.0
	var B1 := body()
	var B2 := body()
	for it in 60:
		var mid := (lo + hi) * 0.5
		S.actors[0]["xf"]["pos"] = [0.0, mid]
		if fist_head_gap(S, B1, B2, 1.5) > 0.005:
			hi = mid
		else:
			lo = mid
	S.actors[0]["xf"]["pos"] = [0.0, (lo + hi) * 0.5]
	return S


func _init() -> void:
	var S := build()
	var B := body()
	var B2 := body()
	var ts: Array = S.times()
	ok(absf(float(ts[1][1]) - 1.001) < 1e-6 and absf(float(ts[2][1]) - 2.001) < 1e-6 and absf(float(ts[3][1]) - 3.001) < 1e-6 and absf(S.length() - 3.999) < 1e-3,
		"0 the clip is built as stated: cards arrive at %.3f / %.3f / %.3f s, %.3f s long" % [ts[1][1], ts[2][1], ts[3][1], S.length()])
	var g15 := fist_head_gap(S, B, B2, 1.5)
	ok(absf(g15 - 0.005) < 1e-6, "0 fighter 2's head is %.4f cm from the right fist on card 2" % (g15 * 100.0))

	# the analytic numbers, read by the test from the posed bodies
	S.apply_true(B, 0.0)
	var ball0: Vector3 = B.P["ball_l"]
	var pel59: Vector3
	var pel61: Vector3
	S.apply_true(B, 59 / FPS)
	pel59 = B.P["pelvis"]
	S.apply_true(B, 61 / FPS)
	pel61 = B.P["pelvis"]
	var spd60 := pel61.distance_to(pel59) / (2.0 / FPS)
	S.apply_true(B, 2.5)
	var ballc: Vector3 = B.P["ball_l"]
	var slide := Vector2(ballc.x - ball0.x, ballc.z - ball0.z).length()
	S.apply_true(B, 3.5)
	var lift := (B.P["ball_l"] as Vector3).y - (B.p0["ball_l"] as Vector3).y
	var bal4 := Balance.read(B)
	S.apply_true(B, 1.5)
	var elbow := float((B.ang["lowerarm_r"] as Vector3).x)
	var g06 := fist_head_gap(S, B, B2, 0.6)
	var gmin := INF
	var fmin := -1
	for i in int(S.length() * FPS + 1e-6) + 1:
		var g := fist_head_gap(S, B, B2, minf(i / FPS, S.length()))
		if g < gmin - 1e-12:
			gmin = g
			fmin = i
	print("analytic: slide %.4f cm, lift %.4f cm, margin(card 4) %.4f cm, elbow %.3f deg, gap(0.6 s) %.4f cm, min gap %.4f cm @%d, pelvis %.4f m/s" % [slide * 100, lift * 100, bal4["margin"] * 100, elbow, g06 * 100, gmin * 100, fmin, spd60])

	var L := {
		"p1": "left foot planted 0-1.9 s", "p2": "left foot planted 0-2.9 s", "p3": "left foot planted 3.1-3.9 s",
		"t1": "right fist touches fighter 2 head at 1.5 s +-1 f", "t2": "right fist touches fighter 2 head at 0.6 s +-1 f", "t3": "right fist touches fighter 2 head 1.1-1.9 s",
		"c1": "COM inside the feet 0-0.9 s", "c2": "COM inside the feet 3.1-3.9 s",
		"a1": "right elbow below 120 deg flex 1.1-1.9 s", "a2": "right elbow below 60 deg flex 1.1-1.9 s", "a3": "right elbow between 100 and 130 deg all clip",
		"d1": "fighter 2 head at least 30 cm from fighter 1 right fist all clip", "d2": "fighter 2 head at most 3 m from right fist all clip",
		"s1": "pelvis speed under 0.5 m/s 1.5-2.5 s", "s2": "pelvis speed over 0.5 m/s at 2.0 s +-1 f",
		"u": "dance like nobody is watching"}
	var want := {"p1": true, "p2": false, "p3": false, "t1": true, "t2": false, "t3": true, "c1": true, "c2": false,
		"a1": true, "a2": false, "a3": false, "d1": false, "d2": true, "s1": false, "s2": true}
	var keep := B.state()
	var r := BodyAssert.run(S, B, L.values())
	ok(B.state() == keep, "0 run puts the body back as it was")
	var wrong := []
	for k in want:
		var x := res_of(r, L[k])
		if x.is_empty() or not x["ok"] or bool(x["pass"]) != bool(want[k]):
			wrong.append("%s (%s)" % [L[k], x.get("say", x.get("error", "missing"))])
	ok(wrong.is_empty() and r["passed"] == 7 and r["failed"] == 8, "1 15 lines pass / fail as built: %d passed, %d failed; wrong: %s" % [r["passed"], r["failed"], wrong])
	for k in want:
		print("     said: " + String(res_of(r, L[k]).get("say", "")))

	var x2 := res_of(r, L["p2"])
	ok(near(x2["miss"]["value"], (slide - BodyAssert.SLIDE) * 100.0, 0.1) and x2["miss"]["frame"] == 61 and absf(slide - 0.05) < 1e-3,
		"2 planted 0-2.9 s: slides %.2f cm (analytic %.2f), misses %s cm at frame %d (analytic %.2f cm at 61)" % [x2["worst"]["slide_cm"], slide * 100.0, x2["miss"]["value"], x2["miss"]["frame"], (slide - 0.025) * 100.0])
	var x3 := res_of(r, L["p3"])
	ok(near(x3["miss"]["value"], (lift - BodyAssert.DOWN) * 100.0, 0.1) and x3["miss"]["frame"] >= 93 and x3["miss"]["frame"] <= 117,
		"2 planted 3.1-3.9 s: the toe base up %.2f cm, misses %s cm (analytic %.2f) at frame %d" % [x3["worst"]["lift_cm"], x3["miss"]["value"], (lift - 0.02) * 100.0, x3["miss"]["frame"]])
	var xt := res_of(r, L["t2"])
	ok(near(xt["miss"]["value"], (g06 - BodyAssert.TOUCH) * 100.0, 0.1) and xt["miss"]["frame"] >= 17 and xt["miss"]["frame"] <= 19,
		"2 touches at 0.6 s: misses %s cm (analytic %.2f) at frame %d" % [xt["miss"]["value"], (g06 - 0.01) * 100.0, xt["miss"]["frame"]])
	ok(xt.has("time_miss") and xt["time_miss"].get("frames", -1) == 12 and xt["time_miss"].get("late", false),
		"3 touches at 0.6 s +-1 f: first holds 12 frames late (frame 31): %s" % [xt.get("time_miss", {})])
	var xc := res_of(r, L["c2"])
	ok(bal4["margin"] < 0.0 and near(xc["miss"]["value"], -bal4["margin"] * 100.0, 0.1),
		"2 COM inside on one foot: misses %s cm (analytic %.2f, past the right foot)" % [xc["miss"]["value"], -bal4["margin"] * 100.0])
	var xa := res_of(r, L["a2"])
	ok(near(xa["miss"]["value"], elbow - 60.0, 0.1) and absf(elbow - 90.0) < 0.5 and xa["miss"]["unit"] == "deg",
		"2 elbow below 60: misses %s deg (analytic %.2f)" % [xa["miss"]["value"], elbow - 60.0])
	var xb := res_of(r, L["a3"])
	ok(near(xb["miss"]["value"], 100.0, 0.1) and xb["miss"]["frame"] == 0, "2 elbow between 100 and 130: misses %s deg at frame %d (analytic 100 at 0)" % [xb["miss"]["value"], xb["miss"]["frame"]])
	var xd := res_of(r, L["d1"])
	ok(near(xd["miss"]["value"], (0.30 - gmin) * 100.0, 0.1) and xd["miss"]["frame"] == fmin,
		"2 head at least 30 cm: misses %s cm at frame %d (analytic %.2f at %d)" % [xd["miss"]["value"], xd["miss"]["frame"], (0.30 - gmin) * 100.0, fmin])
	var xs := res_of(r, L["s1"])
	ok(near(xs["miss"]["value"], spd60 - 0.5, 0.001) and absf(spd60 - 0.75) < 1e-3 and xs["miss"]["frame"] == 60 and xs["miss"]["unit"] == "m/s",
		"2 pelvis speed under 0.5: misses %s m/s at frame %d (analytic %.3f at 60)" % [xs["miss"]["value"], xs["miss"]["frame"], spd60 - 0.5])
	var xu := res_of(r, L["u"])
	ok(not xu.is_empty() and not xu["ok"] and not xu["pass"] and (xu["grammar"] as Array).size() >= 8 and r["unread"] == 1 and not r["pass"],
		"4 an unread line: '%s', the grammar (%d lines) comes back" % [xu.get("error", ""), (xu.get("grammar", []) as Array).size()])
	var bad := BodyAssert.parse("right foot touches")
	ok(not bad["ok"] and bad.has("grammar"), "4 half a line is unread too: %s" % bad.get("error", ""))

	# 5 round trip
	S.asserts = [L["a2"], L["p1"], L["t2"]]
	var d: Dictionary = S.to_dict(B)
	var back: Variant = JSON.parse_string(JSON.stringify(d))
	var S3 := Scene.new()
	S3.from_dict(back)
	ok(S3.asserts == S.asserts and d.has("asserts"), "5 asserts round-trip through the file: %s" % [S3.asserts])
	var es: Array = Validate.data(back)
	ok(es.is_empty(), "5 the file with asserts validates against the schema (%s)" % [es.slice(0, 2)])
	var mir: Dictionary = Scene.mirror_file(back, body())
	ok(mir["asserts"] == ["left elbow below 60 deg flex 1.1-1.9 s", "right foot planted 0-1.9 s", "left fist touches fighter 2 head at 0.6 s +-1 f"],
		"5 Mirror swaps the sides in them: %s" % [mir["asserts"]])
	var S4 := Scene.new()
	S4.from_dict(JSON.parse_string(JSON.stringify(S3.to_dict(B))))
	ok(BodyAssert.run(S4, B, S4.asserts)["failed"] == 2, "5 the reloaded scene's saved lines check the same (2 fail)")

	# 6 Check
	S.asserts = [L["a2"], L["a1"]]
	var fs := Rulebook.check(S, B).filter(func(f): return f["rule"] == "ASSERT")
	ok(fs.size() == 1 and fs[0]["sev"] == "FAIL" and near(fs[0]["v"], elbow - 60.0, 0.1) and fs[0]["card"] == 1 and String(fs[0]["msg"]).contains("misses by 30"),
		"6 Check: one ASSERT finding for the failing line: %s" % [fs.map(func(f): return "%s %.2f s card %d: %s" % [f["sev"], f["t"], f["card"] + 1, f["msg"]])])
	S.asserts = [L["a1"], "wiggle"]
	fs = Rulebook.check(S, B).filter(func(f): return f["rule"] == "ASSERT")
	ok(fs.size() == 1 and fs[0]["sev"] == "WARN", "6 a passing line adds nothing; an unread one is a look: %s" % [fs.map(func(f): return f["msg"])])

	# 7 serve, on a live poser
	S.asserts = []
	var path := "res://scenes/_wip/zz_asserts_test.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/_wip"))
	var fh := FileAccess.open(path, FileAccess.WRITE)
	fh.store_string(JSON.stringify(S.to_dict(B)))
	fh.close()
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var T := AgentTools.new(m)
	var o: Dictionary = await T.request(1, "open", {"path": path})
	var q: Dictionary = await T.request(2, "assert", {"lines": [L["a2"], L["s1"], L["a1"]], "save": true})
	var qr: Dictionary = q.get("result", {})
	var qa := res_of(qr, L["a2"]) if qr.has("results") else {}
	ok(o.has("result") and qr.get("failed", -1) == 2 and qr.get("passed", -1) == 1 and not qa.is_empty() and near(qa["miss"]["value"], elbow - 60.0, 0.1)
		and (qr["saved"] as Array).size() == 3, "7 serve assert: %d pass, %d fail, the elbow misses %s deg, %d saved" % [qr.get("passed", -1), qr.get("failed", -1), qa.get("miss", {}).get("value"), (qr.get("saved", []) as Array).size()])
	var c: Dictionary = await T.request(3, "check", {})
	var cf: Array = (c.get("result", {}).get("findings", []) as Array).filter(func(f): return f["rule"] == "ASSERT")
	ok(cf.size() == 2 and cf.all(func(f): return f["sev"] == "MUST FIX"), "7 serve check lists the 2 failing saved lines: %s" % [cf.map(func(f): return f["msg"].left(70))])
	var u: Dictionary = await T.request(4, "assert", {"lines": ["wiggle the thing"]})
	ok(u.get("result", {}).get("unread", 0) == 1 and (u["result"].get("grammar", []) as Array).size() >= 8, "7 serve assert with an unread line carries the grammar")
	var e: Dictionary = await T.request(5, "assert", {"lines": "not a list"})
	ok(e.has("error") and e["error"]["code"] == -32602, "7 bad params: %s" % e.get("error", {}).get("message", ""))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("ASSERTS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
