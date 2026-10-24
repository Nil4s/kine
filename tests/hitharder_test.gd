## godot --headless --path . -s tests/hitharder_test.gd     (INNOVATIONS N065, HIT HARDER: scripts/hit_harder.gd, hit_harder_ui.gd)
## FOUR STRIKES, on the default body (built here or from the templates; nothing on disk is written):
##   jab         templates/punch.json's guard, the LEAD (left) arm solved straight at chin height (MoveKnobs' limb solve, 97 %
##               reach): guard -> "JAB" (0.14 s, holds 0.05) -> recover; a PLAIN scene (no spline): the jab card is a stop
##   cross       templates/punch.json card 3 "CROSS" (a spline scene; the recover after it comes back)
##   roundhouse  the guard, then "chamber" (right thigh bend 60 / side 45, knee 110, pelvis turned 25), "ROUNDHOUSE KICK" (thigh
##               70 / 65, knee 10, pelvis 45, 0.14 s), "re-chamber" (= the chamber), recover; a spline scene
##   sword       templates/sword_swing.json card 3 "CUT", its move lengthened by the test until the hand peaks at <= 80 % of its
##               I47 cap (the template's 0.084 s cut peaks the hand at 15.8 m/s, OVER the 13.79 m/s cap: it is at the cap as made)
## The test measures on its own, on the clip as it plays: the contact = where the striking end (fist / toe point / weapon tip)
## is at the contact card's arrival before the change, and when (1 ms steps, -0.1 .. +0.05 s) it passes nearest that spot after;
## the speed there |p(t) - p(t - 1/60)| x 60 (Dummy.hits' rule); the blow J = (1 + e) mu v with HitPhysics' masses. (First run: a
## 1 ms search grid only, and the roundhouse read 2.3 % off the plan: its foot brakes through the contact, so its speed changes
## that much inside 1 ms; the grid is now refined to 0.05 ms around its best, the instrument's fix, not the bar's.)
## BARS (written after one probe run of the plan on these strikes, before this test's first run):
##   1 GAIN: each of the four gets an own-measured gain of the blow >= 5 %, and the plan's after speed is the test's own within
##     2 % (or the strike's levers each say which cap / limit stops them, with the number)
##   2 LIMITS: every joint of every card after the change is inside data/body_limits.json (clamp changes nothing, 1e-3 deg)
##   3 CAPS: SpeedEnv (I47) over the whole clip after: no channel's peak over max(its cap, its peak before) (1e-6)
##   4 BALANCE: every 60 Hz frame of the whole clip that had the COM over the feet before still has it (Balance.read margin >= 0);
##     the clip keeps its length (1e-6 s), so the frames are the same times
##   5 CONTACT: the own-measured contact moves at most 1 frame (1 / fps)
##   6 AT CAP: the cross with its move shortened until the hand peaks at 99-100 % of 13.79 m/s: "at_cap", 0 % gain, no new cards,
##     "at the human cap" in the words
##   7 ASSERTIONS: the cross with the saved line "right fist speed under V m/s 0.7-0.8 s" (V = its own fastest frame there +
##     0.1 m/s, passing before): no kept lever breaks it (it still passes after), and the levers that would are refused naming it.
##     (First written "... all clip": it read refused [] because the clip's fastest 30 fps frame, 7.12 m/s, is before the
##     contact and no lever passes it, so the premise "a lever would break it" was false; replaced by the contact's window.)
##   8 DRY: on the live poser, hit_harder {card: 3, dry: true} leaves the cards (JSON text), the body (var_to_str of
##     Body.state()) and the undo stack byte for byte; its answer equals the wet one (dry / undo_steps aside)
##   9 UNDO: the wet call is ONE undo step; one Ctrl+Z gives the cards and the body back bit for bit
##  10 SERVE: card 2 'load' -> a -32602 error saying it is not a strike card and naming 3 'CROSS'
##  11 UI: the HIT HARDER button is greyed with that reason on card 2, live on card 3; pressed, one undo step and the line says
##     the gain in %; hit_harder_ui.gd has no colour literal
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


func jab_scene() -> Scene:
	var S := scene("res://templates/punch.json")
	S.spline = false
	var B := body()
	var g: Dictionary = S.cards[0]["pose"]
	Scene.put(B, Moves._flat(g))
	MoveKnobs._strike(B, {"limb": "hand_l", "end": "hand_l", "kind": "punch"}, 0.0, 97.0)
	S.cards = [{"name": "guard", "pose": g.duplicate(true), "move": -1.0, "hold": 0.3},
		{"name": "JAB", "pose": B.to_dict(), "move": 0.14, "hold": 0.05},
		{"name": "recover", "pose": g.duplicate(true), "move": 0.25, "hold": 0.3}]
	S.name = "jab"
	return S


func kick_scene() -> Scene:
	var S := scene("res://templates/punch.json")
	var B := body()
	var g: Dictionary = S.cards[0]["pose"]
	var cards := [{"name": "guard", "pose": g.duplicate(true), "move": -1.0, "hold": 0.3}]
	for c in [["chamber", 60.0, 45.0, 110.0, 25.0, 0.25], ["ROUNDHOUSE KICK", 70.0, 65.0, 10.0, 45.0, 0.14]]:
		Scene.put(B, Moves._flat(g))
		var p: Vector3 = B.ang["pelvis"]
		B.set_ang("pelvis", Vector3(p.x, p.y, p.z + c[4]))
		B.set_ang("thigh_r", Vector3(c[1], c[2], 0))
		B.set_ang("calf_r", Vector3(c[3], 0, 0))
		cards.append({"name": c[0], "pose": B.to_dict(), "move": c[5], "hold": 0.0})
	cards.append({"name": "re-chamber", "pose": (cards[1]["pose"] as Dictionary).duplicate(true), "move": 0.2, "hold": 0.0})
	cards.append({"name": "recover", "pose": g.duplicate(true), "move": 0.35, "hold": 0.3})
	S.cards = cards
	S.spline = true
	S.name = "roundhouse"
	return S


## the strike card's move lengthened until channel ch peaks at <= 80 % of its cap
func slow(S: Scene, i: int, ch: String, lim: float) -> void:
	var B := MoveKnobs.scratch(S)
	for it in 4:
		var pk := float(SpeedEnv.card_peaks(S, B, i)[ch]["peak"])
		if pk <= 0.8 * lim:
			return
		S.cards[i]["move"] = snappedf(S.move_time(i) * pk / (0.75 * lim), 0.001)


func with_cards(S: Scene, cards: Variant) -> Scene:
	var W := S.clone()
	if cards != null:
		W.cards = (cards as Array).duplicate(true)
	return W


func end_at(S: Scene, B: Body, kind: String, sd: String, t: float) -> Vector3:
	S.apply(B, maxf(t, 0.0))
	if kind == "weapon":
		return B.wep_point(B.wep_len)
	return B.E[("ball" if kind == "kick" else "hand") + sd]


## the test's own blow: {t, v, J}; X = null: at the card's arrival
func own_blow(S: Scene, i: int, kind: String, sd: String, part: String, X: Variant, tc: float) -> Dictionary:
	var B := MoveKnobs.scratch(S)
	var t := tc
	var miss := 0.0
	if X != null:
		var best := INF
		for k in range(-100, 51):
			var tk := tc + k * 0.001
			var d := end_at(S, B, kind, sd, tk).distance_to(X)
			if d < best:
				best = d
				t = tk
		var t1 := t
		for k in range(-20, 21):   # then 0.05 ms steps +-1 ms (a braking kick's speed changes 2 % within the 1 ms grid)
			var tk := t1 + k * 0.00005
			var d := end_at(S, B, kind, sd, tk).distance_to(X)
			if d < best:
				best = d
				t = tk
		miss = best
	var p1 := end_at(S, B, kind, sd, t)
	var v := (p1 - end_at(S, B, kind, sd, t - 1.0 / 60.0)) * 60.0
	S.apply(B, t)
	var me := HitPhysics.strike_mass({"part": part, "u": B.wep_len if kind == "weapon" else 0.0}, B, v)
	var sh := maxf((B.P["upperarm_l"] as Vector3).y, (B.P["upperarm_r"] as Vector3).y)
	var M := HitPhysics.struck_mass("head" if p1.y > sh else "spine_02", body())
	return {"t": t, "v": v.length(), "J": (1.0 + HitPhysics.RESTITUTION) * me * M / (me + M) * v.length(), "at": p1, "miss": miss}


func clip_peaks(S: Scene) -> Dictionary:
	var B := MoveKnobs.scratch(S)
	var out := {}
	for r in SpeedEnv.analyse(S, B):
		for a in r["all"]:
			out[a["id"]] = maxf(float(out.get(a["id"], 0.0)), float(a["peak"]))
	return out


func balance(S: Scene) -> Array:
	var B := MoveKnobs.scratch(S)
	var out := []
	var n := int(ceil(S.length() * 60.0))
	for k in n + 1:
		S.apply(B, k / 60.0)
		var r := Balance.read(B)
		out.append(float(r["margin"]) if (r["down"] as Array).size() > 0 else -INF)
	return out


func _init() -> void:
	var t_start := Time.get_ticks_msec()
	var SW := scene("res://templates/sword_swing.json")
	slow(SW, 2, "hand", 13.79)
	var strikes := [["jab", jab_scene(), 1], ["cross", scene("res://templates/punch.json"), 2], ["roundhouse", kick_scene(), 2], ["sword", SW, 2]]
	var LB := body()
	for st in strikes:
		var nm: String = st[0]
		var S: Scene = st[1]
		var i: int = st[2]
		var t0 := Time.get_ticks_msec()
		var pl := HitHarder.plan(S, i)
		ok(pl["ok"], "%s: plan in %d ms: %s" % [nm, Time.get_ticks_msec() - t0, pl.get("said", pl.get("error", ""))])
		if not pl["ok"]:
			continue
		for lv in pl["levers"]:
			print("     %-18s %s %+.1f %%  %s%s" % [lv["name"], "APPLIED" if lv["applied"] else "-      ", float(lv["gain"]), lv.get("did", lv["why_not"]),
				("  [" + String(lv.get("capped", lv.get("limited", ""))) + "]") if lv.has("capped") or lv.has("limited") else ""])
		var W := with_cards(S, pl["cards"])
		var R := HitHarder.roles(S, MoveKnobs.scratch(S), i)
		var kind: String = R["kind"]
		var sd: String = R["sd"]
		var tc: float = S.times()[i][1]
		var b0 := own_blow(S, i, kind, sd, R["part"], null, tc)
		var b1 := own_blow(W, i, kind, sd, R["part"], b0["at"], tc)
		var gain := (float(b1["J"]) / float(b0["J"]) - 1.0) * 100.0
		var vdiff := absf(float(b1["v"]) - float(pl["after"]["speed_mps"])) / maxf(float(b1["v"]), 1e-6)
		var named := (pl["levers"] as Array).all(func(x): return x["applied"] or String(x["why_not"]).contains("cap") or String(x["why_not"]).contains("limit"))
		ok((gain >= 5.0 or named) and vdiff <= 0.02, "1 %s GAIN: own %.2f -> %.2f m/s, J %.2f -> %.2f N s = %+.1f %% (bar 5); the plan says %.2f m/s (%.1f %% off, bar 2)" % [nm,
			b0["v"], b1["v"], b0["J"], b1["J"], gain, float(pl["after"]["speed_mps"]), vdiff * 100.0])
		# 2 limits
		var worst := 0.0
		for c in W.cards:
			var js: Dictionary = c["pose"]["joints"]
			for j in js:
				if LB.lim.has(j):
					var v := Vector3(js[j]["bend"], js[j]["side"], js[j]["twist"])
					worst = maxf(worst, (LB.clamp_ang(j, v) - v).length())
		ok(worst <= 1e-3, "2 %s LIMITS: every joint of the %d cards inside its range (worst clamp %.5f deg)" % [nm, W.cards.size(), worst])
		# 3 caps
		var pk0 := clip_peaks(S)
		var pk1 := clip_peaks(W)
		var over := []
		for c in SpeedEnv.CH:
			var id: String = c["id"]
			if float(pk1[id]) > maxf(float(c["limit"]), float(pk0[id])) + 1e-6:
				over.append("%s %.1f (cap %.1f, before %.1f)" % [id, pk1[id], c["limit"], pk0[id]])
		ok(over.is_empty(), "3 %s CAPS: hand %.2f -> %.2f m/s (cap 13.79), foot %.2f -> %.2f (cap 15.84), elbow %.0f -> %.0f deg/s; over: %s" % [nm, pk0["hand"], pk1["hand"],
			pk0["foot"], pk1["foot"], pk0["elbow"], pk1["elbow"], over])
		# 4 balance
		var bl0 := balance(S)
		var bl1 := balance(W)
		var lost := []
		for k in mini(bl0.size(), bl1.size()):
			if bl0[k] >= 0.0 and bl1[k] < 0.0:
				lost.append("%.3f s %.1f cm" % [k / 60.0, -float(bl1[k]) * 100.0])
		ok(absf(W.length() - S.length()) <= 1e-6 and lost.is_empty(), "4 %s BALANCE: length %.3f -> %.3f s; %d of %d frames balanced before, lost: %s" % [nm, S.length(), W.length(),
			bl0.filter(func(x): return x >= 0.0).size(), bl0.size(), lost])
		# 5 contact
		var df := absf(float(b1["t"]) - tc) * float(S.fps)
		ok(df <= 1.0 + 1e-6, "5 %s CONTACT: %.3f -> %.3f s = %.2f frames at %d fps (bar 1); it lands %.1f cm from its old spot" % [nm, tc, b1["t"], df, S.fps, float(b1["miss"]) * 100.0])

	# 6 AT CAP: the cross shortened to 99-100 % of the hand cap
	var SC := scene("res://templates/punch.json")
	var BC := MoveKnobs.scratch(SC)
	var lo := 0.02
	var hi: float = SC.move_time(2)
	var pkc := 0.0
	for it in 30:
		var mid := (lo + hi) * 0.5
		SC.cards[2]["move"] = mid
		pkc = float(SpeedEnv.card_peaks(SC, BC, 2)["hand"]["peak"])
		if pkc > 13.79:
			lo = mid
		elif pkc < 0.99 * 13.79:
			hi = mid
		else:
			break
	var pc := HitHarder.plan(SC, 2)
	ok(pkc >= 0.99 * 13.79 and pkc <= 13.79 and pc["ok"] and pc["at_cap"] and float(pc["gain_pct"]) == 0.0 and pc["cards"] == null and String(pc["said"]).contains("at the human cap"),
		"6 AT CAP: the cross at %.3f s peaks the hand at %.2f m/s (%.1f %% of 13.79): %s" % [SC.cards[2]["move"], pkc, pkc / 13.79 * 100.0, pc.get("said", pc.get("error", ""))])

	# 7 ASSERTIONS
	var SA := scene("res://templates/punch.json")
	var BA := MoveKnobs.scratch(SA)
	var probe := BodyAssert.run(SA, BA, ["right fist speed under 100 m/s 0.7-0.8 s"])
	var vmax := float(probe["results"][0]["worst"]["value"])
	var line := "right fist speed under %.2f m/s 0.7-0.8 s" % (vmax + 0.1)
	SA.asserts = [line]
	var before_a := BodyAssert.run(SA, BA, SA.asserts)
	var pa := HitHarder.plan(SA, 2)
	var WA := with_cards(SA, pa["cards"])
	var after_a := BodyAssert.run(WA, MoveKnobs.scratch(WA), WA.asserts)
	var refused := (pa["levers"] as Array).filter(func(x): return String(x["why_not"]).contains("saved assertion"))
	ok(before_a["pass"] and after_a["pass"] and not refused.is_empty(), "7 ASSERTIONS: '%s' passes before %s, after %s; refused: %s; said %s" % [line, before_a["pass"], after_a["pass"],
		refused.map(func(x): return "%s (%s)" % [x["name"], String(x["why_not"]).left(110)]), pa.get("said", "")])
	print("     the pure part took %d ms" % (Time.get_ticks_msec() - t_start))

	# ---- the live poser: 8 DRY, 9 UNDO, 10 SERVE, 11 UI
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var T := AgentTools.new(m)
	var o: Dictionary = await T.request(1, "open", {"path": "templates/punch.json"})
	ok(o.has("result"), "open templates/punch.json")
	m._card_pick(2)
	var c0: String = JSON.stringify(m.S.cards)
	var b0s: String = var_to_str(m.B.state())
	var u0: int = m.undo.size()
	var rd: Dictionary = await T.request(2, "hit_harder", {"card": 3, "dry": true})
	ok(rd.has("result") and JSON.stringify(m.S.cards) == c0 and var_to_str(m.B.state()) == b0s and m.undo.size() == u0,
		"8 DRY: cards, body and undo (%d) unchanged; it says: %s" % [m.undo.size(), rd.get("result", {}).get("said", rd.get("error"))])
	var rw: Dictionary = await T.request(3, "hit_harder", {"card": 3})
	var a1: Dictionary = rd.get("result", {}).duplicate()
	var a2: Dictionary = rw.get("result", {}).duplicate()
	for k in ["dry", "undo_steps"]:
		a1.erase(k)
		a2.erase(k)
	ok(rw.has("result") and JSON.stringify(a1) == JSON.stringify(a2), "8 DRY = WET: the two answers are the same, dry / undo_steps aside (gain %s %%)" % a2.get("gain_pct", "?"))
	ok(rw.has("result") and m.undo.size() - u0 == 1 and JSON.stringify(m.S.cards) != c0 and int(rw["result"]["undo_steps"]) == 1,
		"9 one undo step (%d), %d cards now" % [m.undo.size() - u0, m.S.cards.size()])
	m._undo()
	ok(JSON.stringify(m.S.cards) == c0 and var_to_str(m.B.state()) == b0s, "9 UNDO: one Ctrl+Z gives the cards and the body back bit for bit")
	var e1: Dictionary = await T.request(4, "hit_harder", {"card": 2})
	ok(e1.has("error") and int(e1["error"]["code"]) == -32602 and String(e1["error"]["message"]).contains("not a strike card") and String(e1["error"]["message"]).contains("3 'CROSS'"),
		"10 SERVE card 2: '%s'" % e1.get("error", {}).get("message", "").left(140))
	var ui: HitHarderUI = m.hit_harder_ui
	m._card_pick(1)
	ui.refresh()
	ok(ui != null and ui.button.disabled and ui.button.tooltip_text.contains("not a strike card"), "11 UI card 2: greyed, '%s'" % ui.button.tooltip_text.get_slice("\n", 1).left(90))
	m._card_pick(2)
	ui.refresh()
	var u11: int = m.undo.size()
	ok(not ui.button.disabled, "11 UI card 3 'CROSS': the button is live")
	ui.button.pressed.emit()
	ok(m.undo.size() - u11 == 1 and ui.note.text.contains("%"), "11 UI pressed: %d undo step, '%s'" % [m.undo.size() - u11, ui.note.text.left(120)])
	var src := FileAccess.get_file_as_string("res://scripts/hit_harder_ui.gd")
	ok(not src.contains("Color("), "11 hit_harder_ui.gd: no colour literal (the theme's tokens only)")
	print("HITHARDER %s (%d fails, %d ms)" % ["PASS" if fails == 0 else "FAIL", fails, Time.get_ticks_msec() - t_start])
	m.queue_free()
	quit(1 if fails > 0 else 0)
