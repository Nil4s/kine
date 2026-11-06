## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/n041_test.gd   (window suite: n041:w)
## INNOVATIONS N041 LOCK TRUTH: an armbar, a wristlock or a kimura uses the PARTNER's joint limits. scripts/lock_truth.gd judges, frame by frame, the
## partner's elbow, wrist and shoulder angles (the angles the CLIP ASKS of him: the cards' raw angles, before Body clamps them to his limits) against
## data/body_limits.json, on the arm(s) the locker is touching. Verdicts: "no contact" (the locker's body never touches the partner's arm: no lock),
## "lock not on" (touching, every angle of that arm more than 5 deg from a limit), "at limit" (the nearest limit is within 5 deg, not past),
## "past limit: injury" (the clip asks more than his limit; names the joint, the axis and the degrees past). The key frame is the touching frame with the
## smallest margin (the latest of equals). Wired like N040 (#249): panel row "Lock check" (CHECK ribbon), agent tool + CLI `lock_check`.
## Real reference (recorded; the bars use data/body_limits.json as the truth and the citation checks that file's values are in range):
##   AAOS (Greene & Heckman, The Clinical Measurement of Joint Motion, 1994) and Norkin & White, Measurement of Joint Motion (4th ed.): elbow flexion 0-150,
##   extension 0 (hyperextension 0 to about 10-15 in some healthy adults, more in women); wrist flexion 80, extension 70, radial deviation 20, ulnar
##   deviation 30; forearm pronation and supination about 80-90; shoulder internal rotation about 70, external about 90.
##   Soucie JM et al. (2011) "Range of motion measurements: reference values and a database for comparison studies", Haemophilia 17(3):500-507,
##   doi 10.1111/j.1365-2516.2010.02399.x (674 healthy people, goniometers: elbow flexion, extension, supination, pronation, shoulder flexion).
##   NOTE: only the Soucie abstract was fetched in this session; the AAOS / Norkin & White numbers above are quoted from memory of those tables, so the
##   range bars below are WIDE on purpose (they catch a typo such as 14.5 for 145, not a 5 degree disagreement).
## Bars, written BEFORE the implementation (fps 30; the locker is the hero at the origin; the partner 0.8 m in front at yaw 180; fixtures:
## scripts/lock_fixtures.gd; the cards' raw angles are the "demand" the judge reads, set by the fixture from the opts):
##  1 FIXTURES: armbar (elbow asks -12, limit 0) "past limit: injury", joint elbow, axis bend, side right, 12.0 deg past; armbar_light (elbow 40)
##    "lock not on"; wristlock (kote-gaeshi, wrist flexion 67, limit 70) "at limit", joint wrist, 3.0 deg inside; kimura (shoulder internal roll 85,
##    limit 70) "past limit: injury", joint shoulder, axis twist, 15.0 deg past; apart (the armbar demand 3 m away) "no contact".
##  2 RECOMPUTE: the degrees past (and the margin) at the key frame equal the test's own recompute (raw angle from the saved card, the limit read from
##    the JSON file, left side = twist range negated) within 0.1 deg, for elbow asks -0.5 / -3 / -12 / -25 on the right arm, the left arm (-12), the
##    kimura 85 and a left kimura (-85).
##  3 SWEEP: one clip whose elbow ask goes 45 -> -15: on EVERY frame the verdict equals the test's own classification of that frame's raw ask (frames
##    within 1e-3 deg of a boundary are skipped and counted); "past" flips on exactly once; the last not-past frame's ask >= the limit and the first past
##    frame's ask < it; the verdict order is lock not on, at limit, past limit (two changes). Static: ask 0.0 -> at limit (not past), -0.5 -> past by 0.5,
##    4.5 -> at limit, 5.5 -> lock not on.
##  4 ROLE SWAP: the armbar judged with the PARTNER as the locker (locker=1: the hero's arm is judged) is not "past limit: injury".
##  5 JSON: to_json round-trips through JSON.stringify / parse; verdict, frame, joint, axis, side, past_deg and the key frame's margin_deg equal within
##    0.1 deg; every frame carries verdict, margin_deg for contact frames; the words carry the upper-case verdict.
##  6 PANEL == DIRECT: the panel (m.lock_panel, ribbon toggle m.lock_on) readout and all frame tooltips equal the direct judge of the same saved file:
##    verdict equal, margin within 0.1 deg, on every frame, for armbar, armbar_light, wristlock, kimura, apart. A click on the key frame's cell sets the
##    playhead to key / fps and is not an undo step. One body: the panel says "needs two bodies" and changes nothing (no undo step, scene hash, playhead).
##  7 AGENT + CLI: lock_check {clip} == LockTruth.to_json(judge) for all five; an unknown clip and a one-body live scene answer -32602; "lock_check" is in
##    AgentTools.MCP_EXTRA, poser_mcp.py names it in TOOLS and MATH_TOOLS, poser_cli.gd has the one-shot subcommand.
##  8 LIMITS ARE THE FILE'S: judging the armbar against a copy of body_limits.json with the elbow's hyperextension opened to -20 is not "past limit".
##  9 CITATION: the file's values lie in the published ranges (listed in CITE below).
## 10 PLANTED CONTROLS (the claim is WRONG; the line is ok only when it is false): C1 the comparator accepts 0.2 deg off; C2 armbar_light is past limit;
##    C3 the apart clip (past-limit demand, no locker) is "past limit"; C4 the loosened-limits judge still says past limit; C5 the swapped armbar has the
##    same verdict; C6 a recompute that reads the wrist for the armbar gives 12.0; C7 the citation checker accepts an elbow flexion limit of 200; C8 the
##    kimura panel equals the armbar direct call; C9 a one-body scene judged as a pair reports ok; C10 the wristlock (3 deg inside) is past limit.
extends SceneTree

var fails := 0
const FPS := 30
const KINDS := ["armbar", "armbar_light", "wristlock", "kimura", "apart"]
const V_NONE := "no contact"
const V_OFF := "lock not on"
const V_AT := "at limit"
const V_PAST := "past limit: injury"
## the published ranges the file's values must lie in: [joint, axis, which (0 lo / 1 hi), min, max, what]
const CITE := [
	["lowerarm_r", "bend", 1, 135.0, 160.0, "elbow flexion limit (AAOS 150; Soucie 2011)"],
	["lowerarm_r", "bend", 0, -15.0, 0.0, "elbow extension limit (hyperextension 0 to 15 in healthy adults)"],
	["hand_r", "bend", 1, 60.0, 90.0, "wrist flexion limit (AAOS 80)"],
	["hand_r", "bend", 0, -80.0, -50.0, "wrist extension limit (AAOS 70)"],
	["hand_r", "twist", 1, 70.0, 95.0, "forearm supination/pronation (AAOS 80-90)"],
	["upperarm_r", "twist", 1, 55.0, 100.0, "shoulder internal/external rotation (AAOS 70 / 90)"],
	["upperarm_r", "twist", 0, -100.0, -55.0, "shoulder internal/external rotation (AAOS 70 / 90)"],
]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func control(claim: bool, what: String) -> void:
	print(("ok   control caught: " if not claim else "FAIL control NOT caught: ") + what)
	if claim:
		fails += 1


func stand() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b


func save(s: Scene, name: String) -> String:
	DirAccess.make_dir_recursive_absolute("user://n041")
	var p := ProjectSettings.globalize_path("user://n041/" + name + ".json")
	var fh := FileAccess.open(p, FileAccess.WRITE)
	fh.store_string(JSON.stringify(s.to_dict(stand(), false)))
	fh.close()
	return p


func load_scene(p: String) -> Scene:
	var s := Scene.new()
	s.from_dict(JSON.parse_string(FileAccess.get_file_as_string(p)))
	return s


func near_deg(a: float, b: float) -> bool:
	return absf(a - b) <= 0.1


## the test's own limit lookup: body_limits.json as written (right side + centre); the left twin = the right one with the twist range negated
func limit_of(joint: String, axis: String) -> Vector2:
	var J: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/body_limits.json"))
	var left := joint.ends_with("_l")
	var base := joint.trim_suffix("_l") + "_r" if left else joint
	var r: Array = J[base][axis]
	var lo := float(r[0])
	var hi := float(r[1])
	if left and axis == "twist":
		return Vector2(-hi, -lo)
	return Vector2(lo, hi)


## margin (deg) of a raw angle to its nearest limit; < 0 = past
func margin_of(joint: String, axis: String, raw: float) -> float:
	var L := limit_of(joint, axis)
	return minf(raw - L.x, L.y - raw)


func class_of(m: float) -> String:
	if m < -0.0001:
		return V_PAST
	return V_AT if m <= 5.0 else V_OFF


func verdict_in(text: String) -> String:
	var t := text.to_lower()
	for v in [V_PAST, V_AT, V_OFF, V_NONE]:
		if t.begins_with(v) or t.contains(": " + v) or t.contains(" " + v + " at") or t.contains(v + " at f"):
			return v
	return ""


func margin_in(text: String) -> float:
	var re := RegEx.new()
	re.compile("margin (-?[0-9]+\\.?[0-9]*) deg")
	var mt := re.search(text)
	return INF if mt == null else float(mt.get_string(1))


## the panel against the direct judge, every frame: "" when equal, else the first difference
func panel_vs_direct(P: LockPanel, r: Dictionary) -> String:
	var fr: Array = r["frames"]
	var ro := P.readout()
	var k: int = r["frame"]
	if verdict_in(ro) != String(r["verdict"]) or not ("f %d" % k) in ro:
		return "readout '%s' vs %s at f %d" % [ro, r["verdict"], k]
	if r["verdict"] != V_NONE and not near_deg(margin_in(ro), float(fr[k]["margin_deg"])):
		return "readout margin '%s'" % ro
	for f in fr.size():
		var tip := P.tip_for(f)
		if tip == "" or verdict_in(tip.split(": ", true, 1)[1]) != String(fr[f]["verdict"]):
			return "frame %d verdict '%s' vs %s" % [f, tip, fr[f]["verdict"]]
		if bool(fr[f]["contact"]) and not near_deg(margin_in(tip), float(fr[f]["margin_deg"])):
			return "frame %d margin '%s' vs %.3f" % [f, tip, fr[f]["margin_deg"]]
	return ""


func raw_of(S: Scene, who: int, joint: String, t: float) -> Vector3:
	var sc: Scene = S if who == 0 else S.actors[0]["scene"]
	return (sc.sample(t)["ang"] as Dictionary)[joint]


func _init() -> void:
	# ---- fixtures
	var D := {}
	var paths := {}
	var S := {}
	for k in KINDS:
		S[k] = LockFixtures.build(k)
		paths[k] = save(S[k], k)
		D[k] = LockTruth.judge(load_scene(paths[k]), FPS)
		print("-- ", k, ": ", D[k]["text"])
	# 1 fixtures
	var A: Dictionary = D["armbar"]
	ok(A["verdict"] == V_PAST and A["joint"] == "elbow" and A["axis"] == "bend" and A["side"] == "right" and near_deg(float(A["past_deg"]), 12.0), "1 armbar: %s, %s %s %s, %.2f deg past (want 12.0)" % [A["verdict"], A["side"], A["joint"], A["axis"], A["past_deg"]])
	ok(D["armbar_light"]["verdict"] == V_OFF, "1 armbar_light: %s" % D["armbar_light"]["verdict"])
	var W: Dictionary = D["wristlock"]
	ok(W["verdict"] == V_AT and W["joint"] == "wrist" and near_deg(float(W["margin_deg"]), 3.0) and float(W["past_deg"]) == 0.0, "1 wristlock: %s, %s, %.2f deg inside (want 3.0)" % [W["verdict"], W["joint"], W["margin_deg"]])
	var K: Dictionary = D["kimura"]
	ok(K["verdict"] == V_PAST and K["joint"] == "shoulder" and K["axis"] == "twist" and near_deg(float(K["past_deg"]), 15.0), "1 kimura: %s, %s %s, %.2f deg past (want 15.0)" % [K["verdict"], K["joint"], K["axis"], K["past_deg"]])
	ok(D["apart"]["verdict"] == V_NONE and float(D["apart"]["min_gap"]) > 1.0, "1 apart: %s, closest %.2f m" % [D["apart"]["verdict"], D["apart"]["min_gap"]])
	for k in KINDS:
		ok(k == "apart" or int(D[k]["frames"].size()) > 20, "1 %s: %d frames judged" % [k, D[k]["frames"].size()])

	# 2 recompute
	var cases := [["armbar", {"elbow": -0.5}, "lowerarm_r", "bend", -0.5], ["armbar", {"elbow": -3.0}, "lowerarm_r", "bend", -3.0],
		["armbar", {"elbow": -12.0}, "lowerarm_r", "bend", -12.0], ["armbar", {"elbow": -25.0}, "lowerarm_r", "bend", -25.0],
		["armbar", {"elbow": -12.0, "arm": "l"}, "lowerarm_l", "bend", -12.0], ["kimura", {"roll": 85.0}, "upperarm_r", "twist", 85.0],
		["kimura", {"roll": -85.0, "arm": "l"}, "upperarm_l", "twist", -85.0]]
	for c in cases:
		var Sc: Scene = LockFixtures.build(c[0], c[1])
		var pth := save(Sc, "rc_%s_%s" % [c[0], str(c[4]).replace(".", "p").replace("-", "m")])
		var raw: Variant = (JSON.parse_string(FileAccess.get_file_as_string(pth))["actors"][0]["scene"]["cards"][1]["pose"]["joints"][c[2]][c[3]])
		var r := LockTruth.judge(load_scene(pth), FPS)
		var want := -margin_of(c[2], c[3], float(raw))
		ok(r["verdict"] == V_PAST and near_deg(float(r["past_deg"]), want) and near_deg(float(r["margin_deg"]), -want), "2 %s %s: card raw %.2f, own recompute %.3f past, judge %s %.3f (%s %s)" % [c[0], c[1], float(raw), want, r["verdict"], r["past_deg"], r["side"], r["joint"]])
	control(near_deg(12.0, 12.2), "C1 the comparator accepts 0.2 deg off")
	control(near_deg(-margin_of("hand_r", "bend", -12.0), 12.0), "C6 the wrist recompute of the armbar's -12 gives 12.0")

	# 3 sweep
	var SW: Scene = LockFixtures.build("sweep", {"from": 45.0, "to": -15.0})
	var rs := LockTruth.judge(SW, FPS)
	var lo_e := limit_of("lowerarm_r", "bend").x
	var prev_past := false
	var flips := 0
	var order := []
	var skipped := 0
	var bad := ""
	var last_not_past := INF
	var first_past := -INF
	for f in (rs["frames"] as Array).size():
		var fr: Dictionary = rs["frames"][f]
		var raw_e := raw_of(SW, 0, "lowerarm_l", 0.0).x   # placeholder to keep types honest
		raw_e = raw_of(SW, 1, "lowerarm_r", float(fr["t"])).x
		var m := margin_of("lowerarm_r", "bend", raw_e)
		if absf(m + 0.0) < 1e-3 or absf(m - 5.0) < 1e-3:
			skipped += 1
			continue
		if not bool(fr["contact"]):
			bad = "frame %d has no contact" % f
			break
		if fr["verdict"] != class_of(m):
			bad = "frame %d: raw %.3f -> %s, judge %s" % [f, raw_e, class_of(m), fr["verdict"]]
			break
		var past: bool = fr["verdict"] == V_PAST
		if past != prev_past:
			flips += 1
			if past:
				first_past = raw_e
			else:
				last_not_past = raw_e
		else:
			if not past:
				last_not_past = raw_e
		prev_past = past
		if order.is_empty() or order[-1] != fr["verdict"]:
			order.append(fr["verdict"])
	ok(bad == "", "3 sweep: every frame's verdict equals the own classification (%d skipped at a boundary) %s" % [skipped, bad])
	ok(flips == 1 and last_not_past >= lo_e and first_past < lo_e, "3 sweep: past flips on exactly %d time(s); last not-past ask %.3f >= %.1f > first past ask %.3f" % [flips, last_not_past, lo_e, first_past])
	ok(order == [V_OFF, V_AT, V_PAST], "3 sweep: verdict order %s" % str(order))
	for sv in [[0.0, V_AT, 0.0], [-0.5, V_PAST, 0.5], [4.5, V_AT, 0.0], [5.5, V_OFF, 0.0]]:
		var rr := LockTruth.judge(LockFixtures.build("armbar", {"elbow": sv[0]}), FPS)
		ok(rr["verdict"] == sv[1] and near_deg(float(rr["past_deg"]), sv[2]), "3 static elbow ask %.1f -> %s (%.2f past)" % [sv[0], rr["verdict"], rr["past_deg"]])

	# 4 role swap
	var sw := LockTruth.judge(load_scene(paths["armbar"]), FPS, 1)
	ok(sw["verdict"] != V_PAST and sw["verdict"] != A["verdict"], "4 role swap: the partner as locker judges the hero's arm: %s (armbar was %s)" % [sw["verdict"], A["verdict"]])
	control(sw["verdict"] == A["verdict"], "C5 the swapped armbar has the same verdict")

	# 5 json
	for k in KINDS:
		var js: Dictionary = JSON.parse_string(JSON.stringify(LockTruth.to_json(D[k])))
		var fk: int = D[k]["frame"]
		var good: bool = js["verdict"] == D[k]["verdict"] and int(js["frame"]) == fk and (js["frames"] as Array).size() == (D[k]["frames"] as Array).size()
		if k != "apart":
			good = good and js["joint"] == D[k]["joint"] and js["axis"] == D[k]["axis"] and js["side"] == D[k]["side"] and near_deg(float(js["past_deg"]), float(D[k]["past_deg"])) and near_deg(float(js["frames"][fk]["margin_deg"]), float(D[k]["frames"][fk]["margin_deg"]))
		ok(good and String(js["text"]).contains(String(D[k]["verdict"]).to_upper()), "5 %s: json round-trip equal, words '%s'" % [k, String(js["text"]).left(90)])

	# 8 limits are the file's
	var lj: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/body_limits.json"))
	lj["lowerarm_r"]["bend"] = [-20, 145]
	DirAccess.make_dir_recursive_absolute("user://n041")
	var lp := ProjectSettings.globalize_path("user://n041/loose_limits.json")
	var lf := FileAccess.open(lp, FileAccess.WRITE)
	lf.store_string(JSON.stringify(lj))
	lf.close()
	var loose := LockTruth.judge(load_scene(paths["armbar"]), FPS, 0, lp)
	ok(loose["verdict"] != V_PAST, "8 with the elbow's hyperextension opened to -20 the armbar (-12) is %s (%.2f inside)" % [loose["verdict"], loose["margin_deg"]])
	control(loose["verdict"] == V_PAST, "C4 the loosened-limits judge still says past limit")
	control(D["apart"]["verdict"] == V_PAST, "C3 the apart clip (past-limit demand, no locker) is past limit")
	control(D["armbar_light"]["verdict"] == V_PAST, "C2 armbar_light is past limit")
	control(W["verdict"] == V_PAST, "C10 the wristlock (3 deg inside) is past limit")

	# 9 citation
	var J: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/body_limits.json"))
	var cite_bad := []
	for c in CITE:
		var v := float(J[c[0]][c[1]][c[2]])
		if v < float(c[3]) or v > float(c[4]):
			cite_bad.append("%s %s=%.1f not in [%.0f,%.0f]" % [c[0], c[1], v, c[3], c[4]])
	ok(cite_bad.is_empty(), "9 citation: all %d file values lie in the published ranges %s" % [CITE.size(), str(cite_bad)])
	var wrong := float(200.0)
	control(wrong >= float(CITE[0][3]) and wrong <= float(CITE[0][4]), "C7 the citation range accepts an elbow flexion limit of 200")
	print("     finding (no bar): wrist side limits are %s (+ toward the thumb = radial); published radial 20 / ulnar 30" % str(J["hand_r"]["side"]))

	# ---- the app
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var T := AgentTools.new(m)
	var rid := 0
	var arm_panel: LockPanel = null
	for k in KINDS:
		rid += 1
		await T.request(rid, "open", {"path": paths[k]})
		m.lock_on = true
		m._refresh()
		for i in 3:
			await process_frame
		var P: LockPanel = m.lock_panel
		var diff := "no panel" if P == null or not P.visible else panel_vs_direct(P, D[k])
		ok(diff == "", "6 %s: the panel's readout and all %d tooltips equal the direct judge within 0.1 deg  %s" % [k, (D[k]["frames"] as Array).size(), diff])
		print("     readout: ", P.readout() if P != null else "-")
		if k == "armbar":
			arm_panel = P
		if k == "kimura":
			control(panel_vs_direct(P, A) == "", "C8 the kimura panel equals the armbar direct call")
		m.lock_on = false
		m._refresh()
	# click
	await T.request(70, "open", {"path": paths["armbar"]})
	m.lock_on = true
	m._refresh()
	for i in 3:
		await process_frame
	var P2: LockPanel = m.lock_panel
	var kf: int = A["frame"]
	var u1: int = m.undo.size()
	var click := func(f: int) -> void:
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = pressed
			ev.position = Vector2(P2.x_of_frame(f), P2.cell_y())
			P2._gui_input(ev)
	m.playhead = 0.0
	click.call(kf)
	ok(absf(float(m.playhead) - float(kf) / float(FPS)) <= 1e-6 and m.undo.size() == u1, "6 click on the key frame's cell: playhead %.4f s (want %.4f), undo stack unchanged" % [m.playhead, float(kf) / FPS])
	# one body
	await T.request(71, "open", {"path": "scenes/combo3.json"})
	m.lock_on = false
	m._refresh()
	var h0 := JSON.stringify(m.S.to_dict(m.B, false)).hash()
	var u0: int = m.undo.size()
	var ph0: float = m.playhead
	m.lock_on = true
	m._refresh()
	for i in 3:
		await process_frame
	var txt: String = m.lock_panel.readout() if m.lock_panel != null else ""
	ok(txt.to_lower().contains("needs two bodies") and m.undo.size() == u0 and JSON.stringify(m.S.to_dict(m.B, false)).hash() == h0 and is_equal_approx(m.playhead, ph0), "6 one body: '%s'; nothing changed" % txt.left(60))
	m.lock_on = false
	m._refresh()
	# 7 agent + cli
	for k in KINDS:
		rid += 1
		var rp: Dictionary = await T.request(rid + 100, "lock_check", {"clip": paths[k]})
		var got: Dictionary = JSON.parse_string(JSON.stringify(rp.get("result", {})))
		var want: Dictionary = JSON.parse_string(JSON.stringify(LockTruth.to_json(D[k])))
		ok(got == want and not (want["frames"] as Array).is_empty(), "7 %s: lock_check == LockTruth.to_json(judge), %s, %d bytes" % [k, want["verdict"], JSON.stringify(want).length()])
	var bad_r: Dictionary = await T.request(190, "lock_check", {"clip": "nope/none.json"})
	ok(bad_r.has("error") and int(bad_r["error"]["code"]) == -32602, "7 a missing clip answers -32602")
	await T.request(191, "open", {"path": "scenes/combo3.json"})
	var one: Dictionary = await T.request(192, "lock_check", {})
	ok(one.has("error") and int(one["error"]["code"]) == -32602 and String(one["error"]["message"]).contains("two bodies"), "7 one body (live combo3): %s" % JSON.stringify(one.get("error", {})).left(110))
	var py := FileAccess.get_file_as_string("res://tools/mcp/poser_mcp.py")
	var cli := FileAccess.get_file_as_string("res://tools/poser_cli.gd")
	ok("lock_check" in AgentTools.MCP_EXTRA, "7 MCP_EXTRA has lock_check")
	ok(py.contains("\"lock_check\": (\"lock_check\"") and py.split("MATH_TOOLS = [")[1].split("]")[0].contains("\"lock_check\""), "7 MCP: TOOLS names lock_check and MATH_TOOLS lists it")
	ok(cli.contains("\"lock_check\":"), "7 CLI: a one-shot `lock_check` subcommand")
	# C9 one body judged as a pair
	var one_s := Scene.new()
	one_s.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	control(bool(LockTruth.judge(one_s, FPS).get("ok", false)), "C9 a one-body scene judged as a pair reports ok")

	# the picture
	await T.request(193, "open", {"path": paths["armbar"]})
	m.lock_on = true
	m.playhead = float(kf) / float(FPS)
	m._refresh()
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/L39")
	img.save_png("C:/Temp/claude/L39/lock_armbar.png")
	print("SHOT C:/Temp/claude/L39/lock_armbar.png %dx%d" % [img.get_width(), img.get_height()])
	print("N041 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
