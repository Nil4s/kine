## godot --headless --path . -s tests/knobs_test.gd     (INNOVATIONS N025, MOVE KNOBS: scripts/move_knobs.gd, move_knobs_ui.gd)
## THREE STRIKES, on the default body:
##   punch   templates/punch.json, card 3 "CROSS" (the rear hand; both feet down)
##   kick    built here from the punch template's guard: guard, chamber (right thigh bend 70, knee 100), "FRONT KICK" (thigh
##           75, knee 15), recover = the guard. The striker is the right foot, so there is no stance at contact
##   weapon  templates/sword_swing.json, card 3 "CUT" (one hand on the weapon: the left hand guards)
## Every number the test judges is measured by the test itself on the card's pose (Scene.put, as picking the card does):
## the end (wrist / ankle / weapon tip) and the guard wrist against SayIt.landmark's chin, shoulder / hip to wrist / ankle
## over the two segments, the ankles' floor distance; the feet grounded with Body.ground as playback grounds them.
## BARS (written before the first run):
##   1 READ: every knob a number, except the kick's stance (N/A, with a reason): 11 numbers, 1 reason.
##   2 SAME: setting each strike to the values it read changes no joint of any card by more than 0.1 deg (and pushes no
##     undo step on the live poser).
##   3 LANDS: each knob set alone, by +5 cm (height, guard), -5 cm (stance) or -5 % (reach: the cross is already straight),
##     lands within 1 cm / 1 % of the request on the contact card (11 sets). (First run: stance +5; the sword's rear knee
##     is straight at contact, so +5 is not reachable with the hips held: moved to -5, and +5 joined bar 7.)
##   4 FEET: in those 11 sets, on every card of the scene, a foot on the floor before (sole within 4 cm of the lower one)
##     is still on it with its ankle and ball within 1 cm, grounded (the stance knob's own moved foot aside).
##   5 LIMITS: every joint of every card after every set is inside data/body_limits.json (clamp changes nothing, 1e-3 deg).
##   6 UNDO: on the live poser, `knobs {card, set}` is ONE undo step; one Ctrl+Z gives the cards and the body back bit for
##     bit (JSON text of the cards, var_to_str of Body.state()).
##   7 UNREACHABLE: reach 130 % on each strike is reported unreached, naming the limb's middle joint on its stop (lowerarm_r
##     elbow for the punch and the weapon, calf_r knee for the kick); the sword's stance +10 cm names a joint of the rear leg
##     on its stop (first written "the straight knee, calf_r"; measured: the hip's -25 deg extension stop, also a true
##     stop, so the bar is the rear leg) and its planted lead foot still stays within 1 cm.
##   8 SERVE: `knobs` on a non-strike card, an unknown knob, the kick's stance: each a -32602 error saying why; read = the
##     direct MoveKnobs.read; the CLI path (T.request) answers the same values.
##   9 UI: the MOVE KNOBS rows (4 SpinBoxes) are greyed with a reason with no card picked; on the cross they read the
##     card's values and are editable; on the kick the stance box is greyed with its reason; a typed value is one undo
##     step and lands within 1 cm; move_knobs_ui.gd has no colour literal.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


func scene(path: String) -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(path)))
	return S


func kick_scene() -> Scene:
	var S := scene("res://templates/punch.json")
	var B := body()
	var g: Dictionary = S.cards[0]["pose"]
	Scene.put(B, Moves._flat(g))
	var cards := [{"name": "guard", "pose": g.duplicate(true), "move": -1.0, "hold": 0.3}]
	for c in [["chamber", 70.0, 100.0, 0.25], ["FRONT KICK", 75.0, 15.0, 0.12]]:
		Scene.put(B, Moves._flat(g))
		B.set_ang("thigh_r", Vector3(c[1], 0, 0))
		B.set_ang("calf_r", Vector3(c[2], 0, 0))
		cards.append({"name": c[0], "pose": B.to_dict(), "move": c[3], "hold": 0.0})
	cards.append({"name": "recover", "pose": g.duplicate(true), "move": 0.35, "hold": 0.3})
	S.cards = cards
	S.name = "kick"
	return S


## the test's own numbers on card i: {end, guard wrist, chin, reach %, stance}
func own(S: Scene, i: int, R: Dictionary) -> Dictionary:
	var B := body()
	Scene.put(B, Moves._flat(S.cards[i]["pose"]))
	var c := SayIt.landmark(B, "chin", "", "_r")
	var tip: String = R["limb"]
	var e: Vector3 = B.wep_point(B.wep_len) if R["kind"] == "weapon" else B.P[tip]
	var root := "upperarm" + tip.right(2) if tip.begins_with("hand") else "thigh" + tip.right(2)
	var mid := "lowerarm" + tip.right(2) if tip.begins_with("hand") else "calf" + tip.right(2)
	var L: float = (B.P[root] as Vector3).distance_to(B.P[mid]) + (B.P[mid] as Vector3).distance_to(B.P[tip])
	var d: Vector3 = (B.P["foot_l"] as Vector3) - (B.P["foot_r"] as Vector3)
	return {"strike_height_cm": (e.y - c.y) * 100.0, "reach_pct": 100.0 * (B.P[root] as Vector3).distance_to(B.P[tip]) / L,
		"stance_cm": Vector2(d.x, d.z).length() * 100.0, "guard_cm": ((B.P[R["guard"]] as Vector3).y - c.y) * 100.0 if R["guard"] != "" else null}


## the feet on the floor of every card, grounded: [{sd: [ankle, ball]}]
func feet(S: Scene) -> Array:
	var out := []
	var B := body()
	for c in S.cards:
		Scene.put(B, Moves._flat(c["pose"]))
		B.ground()
		var lo := minf(B.foot_sole_low("_l"), B.foot_sole_low("_r"))
		var f := {}
		for sd in ["_l", "_r"]:
			if B.foot_sole_low(sd) - lo < 0.04:
				f[sd] = [B.P["foot" + sd], B.P["ball" + sd]]
		out.append(f)
	return out


## the largest joint change between two card lists (deg)
func ang_diff(a: Array, b: Array) -> float:
	var w := 0.0
	for i in a.size():
		var ja: Dictionary = a[i]["pose"]["joints"]
		var jb: Dictionary = b[i]["pose"]["joints"]
		for j in ja:
			for ax in ["bend", "side", "twist"]:
				w = maxf(w, absf(float(ja[j][ax]) - float(jb[j][ax])))
	return w


func applied(S: Scene, pl: Dictionary) -> Scene:
	var S2 := S.clone()
	for k in pl["poses"]:
		S2.cards[k]["pose"] = pl["poses"][k]
	return S2


func _init() -> void:
	var strikes := [["punch", scene("res://templates/punch.json"), 2, "lowerarm_r"], ["kick", kick_scene(), 2, "calf_r"],
		["weapon", scene("res://templates/sword_swing.json"), 2, "lowerarm_r"]]
	var DELTA := {"strike_height_cm": 5.0, "reach_pct": -5.0, "stance_cm": -5.0, "guard_cm": 5.0}
	var n_num := 0
	var n_na := 0
	var worst_same := 0.0
	var lands := []
	var worst_land := 0.0
	var worst_feet := 0.0
	var feet_lost := 0
	var worst_lim := 0.0
	var n_sets := 0
	var unr_ok := 0
	var LB := body()
	for st in strikes:
		var nm: String = st[0]
		var S: Scene = st[1]
		var i: int = st[2]
		var r := MoveKnobs.read(S, i)
		ok(r["ok"], "%s: read card %d '%s' -> %s, striker %s, guard %s, stance foot %s; NA %s; the end: %s" % [nm, i + 1, r.get("name", ""), JSON.stringify(r.get("values", {})),
			r.get("striker", ""), r.get("guard_hand", ""), r.get("stance_foot", ""), r.get("na", {}), r.get("end_words", r.get("error", ""))])
		if not r["ok"]:
			continue
		var R := MoveKnobs.roles(S, body(), i)
		var mine := own(S, i, R)
		for k in MoveKnobs.KNOBS:
			if r["values"][k] != null:
				n_num += 1
				ok(absf(float(r["values"][k]) - float(mine[k])) <= 0.051, "%s: %s read %s = the test's own %.2f" % [nm, k, r["values"][k], float(mine[k])])
			elif r["na"].has(k):
				n_na += 1
		# 2 SAME
		var same := {}
		for k in MoveKnobs.KNOBS:
			if r["values"][k] != null:
				same[k] = r["values"][k]
		var ps := MoveKnobs.plan(S, i, same)
		worst_same = maxf(worst_same, ang_diff(S.cards, applied(S, ps).cards))
		ok(ps["ok"] and ps["poses"].is_empty(), "%s: set to the values read: %d cards written, already %s" % [nm, ps.get("poses", {}).size(), ps.get("already", [])])
		# 3 / 4 / 5 each knob alone
		var f0 := feet(S)
		for k in MoveKnobs.KNOBS:
			if r["values"][k] == null:
				continue
			var want: float = float(r["values"][k]) + float(DELTA[k])
			var pl := MoveKnobs.plan(S, i, {k: want})
			var S2 := applied(S, pl)
			var got: float = float(own(S2, i, R)[k])
			var miss := absf(got - want)
			worst_land = maxf(worst_land, miss)
			n_sets += 1
			lands.append("%s %s %.1f -> %.1f (miss %.2f, cards %s)" % [nm, k, float(r["values"][k]), got, miss, pl["cards"]])
			ok(pl["ok"] and miss <= 1.0 and pl["unreached"].is_empty(), "%s: %s asked %.1f got %.2f (bar 1 %s), cards %s, the others now %s" % [nm, k, want, got, MoveKnobs.UNIT[k], pl["cards"], JSON.stringify(pl["after"])])
			var f1 := feet(S2)
			var wf0 := worst_feet
			var skip: String = String(R["foot"]) if k == "stance_cm" else ""
			for c in f0.size():
				for sd in f0[c]:
					if sd == skip:
						continue
					if not f1[c].has(sd):
						feet_lost += 1
						continue
					worst_feet = maxf(worst_feet, maxf((f0[c][sd][0] as Vector3).distance_to(f1[c][sd][0]), (f0[c][sd][1] as Vector3).distance_to(f1[c][sd][1])))
			for c in S2.cards:
				var js: Dictionary = c["pose"]["joints"]
				for j in js:
					if not LB.lim.has(j):
						continue
					var v := Vector3(js[j]["bend"], js[j]["side"], js[j]["twist"])
					worst_lim = maxf(worst_lim, (LB.clamp_ang(j, v) - v).length())
			if worst_feet > wf0:
				lands[-1] += ", planted feet now up to %.2f cm" % (worst_feet * 100.0)
		# 7 UNREACHABLE
		var pu := MoveKnobs.plan(S, i, {"reach_pct": 130.0})
		var u: Dictionary = pu["unreached"][0] if pu["ok"] and not pu["unreached"].is_empty() else {}
		if u.get("knob", "") == "reach_pct" and u.get("joint", "") == st[3]:
			unr_ok += 1
		ok(u.get("joint", "") == st[3], "7 %s: reach 130 %% -> got %s %%, stopped by %s (expected %s)" % [nm, u.get("got", "?"), u.get("limit", {}).get("words", "nothing"), st[3]])
	var SW: Scene = strikes[2][1]
	var sv: float = float(MoveKnobs.read(SW, 2)["values"]["stance_cm"])
	var pst := MoveKnobs.plan(SW, 2, {"stance_cm": sv + 10.0})
	var ust: Dictionary = pst["unreached"][0] if pst["ok"] and not pst["unreached"].is_empty() else {}
	var fa := feet(SW)
	var fb := feet(applied(SW, pst))
	var lead_w := 0.0
	for c in fa.size():
		for sd in fa[c]:
			if sd != "_r":
				lead_w = maxf(lead_w, (fa[c][sd][0] as Vector3).distance_to(fb[c].get(sd, [Vector3(9, 9, 9)])[0]))
	if String(ust.get("joint", "")) in ["thigh_r", "calf_r", "foot_r"] and lead_w <= 0.01:
		unr_ok += 1
	ok(String(ust.get("joint", "")) in ["thigh_r", "calf_r", "foot_r"] and lead_w <= 0.01, "7 weapon: stance +10 cm -> got %s cm, stopped by %s; the lead foot moved %.2f cm (bar 1)" % [ust.get("got", "?"),
		ust.get("limit", {}).get("words", "nothing"), lead_w * 100.0])
	ok(n_num == 11 and n_na == 1, "1 READ: %d numbers (bar 11), %d not-on-this-strike reasons (bar 1: the kick's stance)" % [n_num, n_na])
	ok(worst_same <= 0.1, "2 SAME: read -> set the same values: the largest joint change %.4f deg (bar 0.1)" % worst_same)
	ok(n_sets == 11 and worst_land <= 1.0, "3 LANDS: %d sets, the worst miss %.2f cm / %% (bar 1)" % [n_sets, worst_land])
	for l in lands:
		print("     " + l)
	ok(worst_feet <= 0.01 and feet_lost == 0, "4 FEET: planted feet moved at most %.2f cm (bar 1), %d left the floor (bar 0)" % [worst_feet * 100.0, feet_lost])
	ok(worst_lim <= 1e-3, "5 LIMITS: every joint of every card inside its range after every set (worst clamp %.5f deg)" % worst_lim)
	ok(unr_ok == 4, "7 UNREACHABLE: %d of 4 requests name the stopping joint" % unr_ok)

	# ---- the live poser: 6 UNDO, 8 SERVE, 9 UI
	print("     the pure part took %d ms" % Time.get_ticks_msec())
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var T := AgentTools.new(m)
	var o: Dictionary = await T.request(1, "open", {"path": "templates/punch.json"})
	ok(o.has("result"), "open templates/punch.json")
	m._card_pick(2)
	var rd: Dictionary = await T.request(2, "knobs", {"card": 3, "read": true})
	var direct := MoveKnobs.read(m.S, 2)
	ok(rd.has("result") and JSON.stringify(rd["result"]) == JSON.stringify(direct), "8 serve knobs read = MoveKnobs.read: %s" % JSON.stringify(rd.get("result", {}).get("values", rd.get("error"))))
	var same_v: Dictionary = rd["result"]["values"]
	var c_same: String = JSON.stringify(m.S.cards)
	var u_same: int = m.undo.size()
	var rs: Dictionary = await T.request(3, "knobs", {"card": 3, "set": same_v})
	ok(rs.has("result") and JSON.stringify(m.S.cards) == c_same and m.undo.size() == u_same, "2 SAME (live): set to the values read: cards byte-identical, %d undo steps" % (m.undo.size() - u_same))
	var c0: String = JSON.stringify(m.S.cards)
	var b0: String = var_to_str(m.B.state())
	var u0: int = m.undo.size()
	var hv: float = float(same_v["strike_height_cm"]) + 5.0
	var gv: float = float(same_v["guard_cm"]) + 5.0
	var st6: Dictionary = await T.request(4, "knobs", {"card": 3, "set": {"strike_height_cm": hv, "guard_cm": gv}})
	var after6: Dictionary = st6.get("result", {}).get("after", {})
	ok(st6.has("result") and m.undo.size() - u0 == 1 and JSON.stringify(m.S.cards) != c0 and absf(float(after6.get("strike_height_cm", 0)) - hv) <= 1.0 and absf(float(after6.get("guard_cm", 0)) - gv) <= 1.0,
		"6 two knobs at once: %d undo step (bar 1), now %s; said: %s" % [m.undo.size() - u0, JSON.stringify(after6), st6.get("result", {}).get("said", st6.get("error"))])
	m._undo()
	ok(JSON.stringify(m.S.cards) == c0 and var_to_str(m.B.state()) == b0, "6 UNDO: one Ctrl+Z gives the cards and the body back bit for bit")
	var e1: Dictionary = await T.request(5, "knobs", {"card": 1, "read": true})
	var e2: Dictionary = await T.request(6, "knobs", {"card": 3, "set": {"elbow": 3}})
	ok(e1.has("error") and int(e1["error"]["code"]) == -32602 and String(e1["error"]["message"]).contains("3 'CROSS'") and e2.has("error") and String(e2["error"]["message"]).contains("reach_pct"),
		"8 errors: card 1 '%s'; unknown knob '%s'" % [e1.get("error", {}).get("message", ""), e2.get("error", {}).get("message", "")])
	# 9 UI on the cross
	var ui: MoveKnobsUI = m.knobs_ui
	var sbs: Array = MoveKnobs.KNOBS.map(func(k): return ui.boxes.get(k))
	ok(ui != null and sbs.all(func(b): return b is SpinBox), "9 UI: the MOVE KNOBS rows exist in the inspector with 4 spin boxes")
	m.sel_card = -1
	ui.refresh()
	ok(sbs.all(func(b): return not (b as SpinBox).editable) and ui.note.text.contains("pick a strike card"), "9 no card picked: all four greyed, '%s'" % ui.note.text)
	m._card_pick(1)
	ui.refresh()
	ok(sbs.all(func(b): return not (b as SpinBox).editable) and ui.note.text.contains("not a strike card"), "9 card 2 'load': greyed, '%s'" % ui.note.text.left(90))
	m._card_pick(2)
	ui.refresh()
	var rv: Dictionary = MoveKnobs.read(m.S, 2)["values"]
	var shown := MoveKnobs.KNOBS.all(func(k): return absf((ui.boxes[k] as SpinBox).value - float(rv[k])) < 1e-6)
	ok(sbs.all(func(b): return (b as SpinBox).editable) and shown, "9 the cross: editable, the boxes read %s" % [MoveKnobs.KNOBS.map(func(k): return (ui.boxes[k] as SpinBox).value)])
	var u9: int = m.undo.size()
	var want9: float = float(rv["guard_cm"]) + 4.0
	(ui.boxes["guard_cm"] as SpinBox).value = want9
	var g9: float = float(MoveKnobs.read(m.S, 2)["values"]["guard_cm"])
	ok(m.undo.size() - u9 == 1 and absf(g9 - want9) <= 1.0, "9 guard typed %.1f: %d undo step, the card reads %.1f; note '%s'" % [want9, m.undo.size() - u9, g9, ui.note.text.left(100)])
	m.S = kick_scene()
	m._rebuild_cards()
	m._card_pick(2)
	ui.refresh()
	var sk: SpinBox = ui.boxes["stance_cm"]
	ok(not sk.editable and sk.tooltip_text.contains("one foot is the strike") and (ui.boxes["reach_pct"] as SpinBox).editable, "9 the kick: stance greyed ('%s'), reach editable" % sk.tooltip_text.get_slice("\n", 1))
	var e3: Dictionary = await T.request(7, "knobs", {"card": 3, "set": {"stance_cm": 50}})
	ok(e3.has("error") and String(e3["error"]["message"]).contains("not on this strike"), "8 the kick's stance: '%s'" % e3.get("error", {}).get("message", ""))
	var src := FileAccess.get_file_as_string("res://scripts/move_knobs_ui.gd")
	ok(not src.contains("Color("), "9 move_knobs_ui.gd: no colour literal (the theme's tokens only)")
	print("KNOBS %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	m.queue_free()
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
