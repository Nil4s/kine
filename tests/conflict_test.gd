## godot --headless --path . -s tests/conflict_test.gd     (INNOVATIONS N006, CONFLICT EXPLAINER: scripts/conflict_explain.gd)
## Three built-in wish sets whose answers the test works out itself from the posed bodies (not from the explainer):
##   (a) REACH vs PLANTED. The hero's right arm points straight forward (upper arm bend 90, elbow straight), both feet down.
##       Fighter 2 (rest, facing him) is placed so his chin sits in front of the right shoulder, exactly far enough that
##       the straight arm needs a 12 cm step along the floor: s = dz - sqrt((L + 1 cm)^2 - dy^2) = 0.12 m, L = the
##       shoulder to the far surface of the fist (the straight chain + the hand capsule's radius), dz / dy the chin's
##       floor distance / height from the shoulder. Wishes: the reach, "both feet planted", "COM inside the feet",
##       "left elbow below 30 deg" (the last two hold anyway and must NOT be named).
##   (b) BALANCE vs LEAN. The rest body; "COM inside the feet" + "lean 40 deg forward" (+ the same harmless elbow line).
##       The test's own lean limit: every de Leva part (Balance.MASS) but the feet turned rigidly about the ankle axis
##       (through the ankles' midpoint, square to his forward) until the COM's floor point reaches the edge of the start's
##       support polygon (bisection to 0.01 deg); the limit is the start's ankle-to-neck tilt + that angle.
##   (c) A SATISFIABLE SET: the (a) body with the chin 10 cm INSIDE the straight arm's reach, plus planted and COM inside.
## BARS (written before the first run):
##   1 (a) conflict; the minimal set is exactly {the reach, "both feet planted"}; the step needed to free "both feet
##     planted" is 12 +-1 cm, and the reach's shortfall with the feet planted is the test's own D - L - 1 cm within 1 cm;
##     the words say "step" with the number and "drop 'both feet planted'".
##   2 (b) conflict; the minimal set is exactly {"COM inside the feet", "lean 40 deg forward"}; the words name balance;
##     the lean bound it reports is the test's own lean limit within 2 deg.
##   3 (c) "no conflict", minimal empty.
##   4 MINIMAL is minimal: for (a) and (b), the full set does not solve, the minimal set does not solve, and EVERY proper
##     subset of the minimal set solves (ConflictExplain.solve, enumerated by the test).
##   5 the scene is unchanged after every call: the scene file text (to_dict through a scratch body) and the hero body's
##     state are byte-identical before / after.
##   6 serve: on a live poser, explain_conflict {lines, card: 1} gives the same minimal set and step as the static call,
##     leaves the live scene and body as they were; bad params (lines not a list, a speed line, an unread line) are
##     -32602 errors that say what to send.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


func two_cards(name: String, B: Body) -> Scene:
	var S := Scene.new()
	S.name = name
	S.natural = false
	S.on_floor = false
	S.pin = false
	S.add("a", B.to_dict())
	S.add("b", B.to_dict())
	S.cards[0]["hold"] = 1.0
	S.cards[1]["hold"] = 1.0
	return S


## the hero with the right arm straight forward; the opponent placed so the needed step along the floor is `step` m
## (negative = the chin that far inside the reach). Returns [S, numbers]
func reach_scene(step: float) -> Array:
	var B := body()
	B.set_ang("upperarm_r", Vector3(90, 0, 0))
	B.fk()
	var S := two_cards("zz_conflict_reach", B)
	var R := body()
	S.actors = [{"name": "B", "xf": {"pos": [0.0, 1.0], "yaw": 180.0}, "scene": two_cards("zz_conflict_b", R)}]
	S.apply_true(B, 0.5)
	var sh: Vector3 = B.P["upperarm_r"]
	var e: Vector3 = B.E["hand_r"]
	var chain: float = sh.distance_to(B.P["lowerarm_r"]) + (B.P["lowerarm_r"] as Vector3).distance_to(B.P["hand_r"]) + (B.P["hand_r"] as Vector3).distance_to(e)
	var L: float = sh.distance_to(e) + float(B.rad["hand_r"])
	var cl := SayIt.landmark(R, "chin", "", "_r")   # the chin in his own space; yaw 180: X * p = (pos.x - p.x, p.y, pos.z - p.z)
	var dy := cl.y - sh.y
	var dz := step + sqrt((L + BodyAssert.TOUCH) * (L + BodyAssert.TOUCH) - dy * dy)
	S.actors[0]["xf"]["pos"] = [sh.x + cl.x, sh.z + dz + cl.z]
	var X := Constraints.actor_xf(S.actors[0]["xf"])
	var T: Vector3 = X * cl
	var D := T.distance_to(sh)
	return [S, {"L": L, "straight": absf(chain - sh.distance_to(e)), "dz": dz, "dy": dy, "D": D, "short": D - L - BodyAssert.TOUCH, "T": T, "sh": sh}]


## the test's own lean limit for the rest body (deg of ankle-to-neck tilt): every part but the feet turned rigidly
func lean_limit(B: Body) -> Dictionary:
	var r0 := Balance.read(B)
	var poly: PackedVector2Array = r0["poly"]
	var piv: Vector3 = ((B.P["foot_l"] as Vector3) + (B.P["foot_r"] as Vector3)) * 0.5
	var F := BodyFrame.fighter(B)
	var fwd: Vector3 = F["fwd"]
	var ax := Vector3.UP.cross(fwd).normalized()
	var v: Vector3 = (B.P["neck_01"] as Vector3) - piv
	var tilt0 := rad_to_deg(atan2(v.dot(fwd), v.y))
	var margin_at := func(deg: float) -> float:
		var R := Quaternion(ax, deg_to_rad(deg))
		var s := Vector3.ZERO
		var w := 0.0
		for j in Balance.MASS:
			var c: Array = B.cap(j)
			var mid: Vector3 = ((c[0] as Vector3) + (c[1] as Vector3)) * 0.5
			if not String(j).begins_with("foot"):
				mid = piv + R * (mid - piv)
			s += mid * float(Balance.MASS[j])
			w += float(Balance.MASS[j])
		var com := s / w
		return Balance.signed_dist(poly, Vector2(com.x, com.z))
	var lo := 0.0
	var hi := 60.0
	while hi - lo > 0.01:
		var mid := (lo + hi) * 0.5
		if float(margin_at.call(mid)) >= 0.0:
			lo = mid
		else:
			hi = mid
	return {"tilt0": tilt0, "lean": lo, "limit": tilt0 + lo, "margin0": r0["margin"]}


func scene_text(S: Scene) -> String:
	return JSON.stringify(S.to_dict(body()))


## the minimal set: the full set and the core clash, every proper subset of the core solves
func check_minimal(S: Scene, lines: Array, core: Array, tag: String) -> void:
	var B := body()
	var ws := lines.map(func(l): return ConflictExplain.wish(l))
	var cw := ws.filter(func(w): return String(w["line"]).strip_edges() in core)
	var ctx := ConflictExplain.moment(S, B, 0.5, [0, 1] if S.actors.size() > 0 else [0])
	var full: bool = ConflictExplain.solve(ws, ctx)["ok"]
	var whole: bool = ConflictExplain.solve(cw, ctx)["ok"]
	var bad := []
	var n := cw.size()
	for mask in range(0, (1 << n) - 1):   # every proper subset (the empty one too)
		var sub := []
		for i in n:
			if mask & (1 << i):
				sub.append(cw[i])
		if not ConflictExplain.solve(sub, ctx)["ok"]:
			bad.append(sub.map(func(w): return w["line"]))
	ok(not full and not whole and bad.is_empty() and n >= 1,
		"4 %s: the full set clashes (%s), the minimal set clashes (%s), all %d proper subsets solve (failing: %s)" % [tag, not full, not whole, (1 << n) - 1, bad])


func _init() -> void:
	# ---------------------------------------------------------------- (a)
	var ra := reach_scene(0.12)
	var Sa: Scene = ra[0]
	var na: Dictionary = ra[1]
	print("analytic (a): L %.4f m (chain straight to %.6f m), chin %.4f m away (dz %.4f, dy %.4f), shortfall %.2f cm, step 12 cm" % [na["L"], na["straight"], na["D"], na["dz"], na["dy"], na["short"] * 100.0])
	var La := ["right fist touches fighter 2 chin", "both feet planted", "COM inside the feet", "left elbow below 30 deg"]
	var B := body()
	var keep := B.state()
	var txt := scene_text(Sa)
	var t0 := Time.get_ticks_msec()
	var a := ConflictExplain.explain(Sa, B, La, 0.5)
	var ms_a := Time.get_ticks_msec() - t0
	print("     said: " + String(a.get("say", a.get("error", ""))))
	ok(B.state() == keep and scene_text(Sa) == txt, "5 (a) the scene and the body are unchanged after the call")
	var core_a := ["right fist touches fighter 2 chin", "both feet planted"]
	ok(a.get("ok", false) and a.get("conflict", false) and (a["minimal"] as Array).size() == 2 and core_a.all(func(l): return l in a["minimal"]),
		"1 (a) conflict, minimal = %s (%d solves, %d ms)" % [a.get("minimal"), a.get("solves", -1), ms_a])
	var cp := {}
	var cr := {}
	for c in a.get("costs", []):
		if c["kind"] == "planted":
			cp = c
		if c["kind"] == "touches":
			cr = c
	ok(not cp.is_empty() and absf(float(cp.get("step_cm", -99)) - 12.0) <= 1.0, "1 (a) freeing 'both feet planted' takes a step of %s cm (bar 12 +-1): %s" % [cp.get("step_cm"), cp.get("say", "")])
	ok(not cr.is_empty() and absf(float(cr.get("shortfall_cm", -99)) - na["short"] * 100.0) <= 1.0 and absf(float(cr.get("step_cm", -99)) - 12.0) <= 1.0,
		"1 (a) the fist's shortfall %s cm (test: %.2f), its step fix %s cm: %s" % [cr.get("shortfall_cm"), na["short"] * 100.0, cr.get("step_cm"), cr.get("say", "")])
	var sa: String = a.get("say", "")
	ok(sa.contains("step 12.") or sa.contains("step 11.") , "1 (a) the words carry the step: %s" % sa.contains("step 1"))
	ok(sa.contains("drop 'both feet planted'"), "1 (a) the words offer to drop 'both feet planted'")
	check_minimal(Sa, La, core_a, "(a)")

	# ---------------------------------------------------------------- (b)
	var Br := body()
	var Sb := two_cards("zz_conflict_lean", Br)
	var ll := lean_limit(Br)
	print("analytic (b): start tilt %.3f deg, rigid lean %.3f deg to the COM at the edge: limit %.3f deg (start margin %.2f cm)" % [ll["tilt0"], ll["lean"], ll["limit"], ll["margin0"] * 100.0])
	var Lb := ["COM inside the feet", "lean 40 deg forward", "left elbow below 30 deg"]
	B = body()
	keep = B.state()
	txt = scene_text(Sb)
	var b := ConflictExplain.explain(Sb, B, Lb, 0.5)
	print("     said: " + String(b.get("say", b.get("error", ""))))
	ok(B.state() == keep and scene_text(Sb) == txt, "5 (b) the scene and the body are unchanged after the call")
	var core_b := ["COM inside the feet", "lean 40 deg forward"]
	ok(b.get("ok", false) and b.get("conflict", false) and (b["minimal"] as Array).size() == 2 and core_b.all(func(l): return l in b["minimal"]),
		"2 (b) conflict, minimal = %s (%d solves)" % [b.get("minimal"), b.get("solves", -1)])
	var cl := {}
	for c in b.get("costs", []):
		if c["kind"] == "lean":
			cl = c
	ok(String(b.get("say", "")).contains("balance"), "2 (b) the words name balance")
	ok(not cl.is_empty() and absf(float(cl.get("bound", -99)) - float(ll["limit"])) <= 2.0,
		"2 (b) the lean bound %s deg vs the test's limit %.2f deg (bar 2): %s" % [cl.get("bound"), ll["limit"], cl.get("say", "")])
	check_minimal(Sb, Lb, core_b, "(b)")

	# ---------------------------------------------------------------- (c)
	var rc := reach_scene(-0.10)
	var Sc: Scene = rc[0]
	var Lc := ["right fist touches fighter 2 chin", "both feet planted", "COM inside the feet"]
	B = body()
	keep = B.state()
	txt = scene_text(Sc)
	var c3 := ConflictExplain.explain(Sc, B, Lc, 0.5)
	print("     said: " + String(c3.get("say", c3.get("error", ""))))
	ok(B.state() == keep and scene_text(Sc) == txt, "5 (c) the scene and the body are unchanged after the call")
	ok(c3.get("ok", false) and not c3.get("conflict", true) and (c3.get("minimal", [0]) as Array).is_empty() and String(c3.get("say", "")).begins_with("no conflict"),
		"3 (c) a satisfiable set: %s" % c3.get("say", c3.get("error", "")))

	# ---------------------------------------------------------------- 6 serve
	var path := "res://scenes/_wip/zz_conflict_test.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/_wip"))
	var fh := FileAccess.open(path, FileAccess.WRITE)
	fh.store_string(JSON.stringify(Sa.to_dict(body())))
	fh.close()
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var T := AgentTools.new(m)
	var o: Dictionary = await T.request(1, "open", {"path": path})
	var live0 := JSON.stringify(T.scene_dict())
	var bs0 := T.body_json()
	var q: Dictionary = await T.request(2, "explain_conflict", {"lines": La, "card": 1})
	var qr: Dictionary = q.get("result", {})
	var qp := {}
	for c in qr.get("costs", []):
		if c["kind"] == "planted":
			qp = c
	ok(o.has("result") and qr.get("conflict", false) and core_a.all(func(l): return l in qr.get("minimal", [])) and (qr.get("minimal", []) as Array).size() == 2
		and absf(float(qp.get("step_cm", -99)) - float(cp.get("step_cm", 99))) <= 0.1,
		"6 serve: minimal %s, step %s cm (static %s)" % [qr.get("minimal"), qp.get("step_cm"), cp.get("step_cm")])
	ok(JSON.stringify(T.scene_dict()) == live0 and T.body_json() == bs0, "6 serve leaves the live scene and body as they were")
	var e1: Dictionary = await T.request(3, "explain_conflict", {"lines": "not a list"})
	var e2: Dictionary = await T.request(4, "explain_conflict", {"lines": ["right fist speed over 6 m/s"]})
	var e3: Dictionary = await T.request(5, "explain_conflict", {"lines": ["wiggle the thing"]})
	ok(e1.get("error", {}).get("code", 0) == -32602 and e2.get("error", {}).get("code", 0) == -32602 and e3.get("error", {}).get("code", 0) == -32602
		and String(e1["error"]["message"]).contains("lines") and String(e2["error"]["message"]).contains("one moment"),
		"6 bad params are -32602: '%s' / '%s' / '%s'" % [e1.get("error", {}).get("message", ""), e2.get("error", {}).get("message", ""), e3.get("error", {}).get("message", "")])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("CONFLICT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
