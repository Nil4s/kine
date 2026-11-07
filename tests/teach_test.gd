## godot --headless --path . -s tests/teach_test.gd     (INNOVATIONS section 7 TEACHING: N097 pro comparison / hip lead, N100 principles as physics /
## the landing, N093 what drives what / the balance; scripts/teach.gd; serve teach_chain, teach_landing, teach_stance)
## Kine's critique points at problems; these explain WHY from the clip's own numbers. THREE PLANTED FAULTS + CLEAN CONTROLS, built here:
##   chain    a cross whose hip turn happens in the SAME card as the arm (no hip lead). Clean: the hips get their own card first.
##   landing  a jump (tests/jump_physics_test.gd's builder) landing on straight knees (thigh 8 / calf 12). Clean: 50 / 90.
##   stance   a forward trunk lean held until the centre of mass is past the front of the feet (found by search, not guessed). Clean: 4 deg a joint.
## BARS (written before scripts/teach.gd, never moved after a run):
##   1 NAMES cause + frame + number: each fault gives exactly 1 finding with the right cause id; its frame and its number match an
##     INDEPENDENT measure made here (chain: hips' yaw from the line between the thighs, lead within 35 ms, frames within 2 of 30 fps;
##     landing: Rulebook.jumps' bend within 0.5 deg, v = g T / 2 within 0.05 m/s, touchdown frame within 1; stance: Balance.read
##     margin at the frame within 0.3 cm)
##   2 CLEAN: each clean control gives 0 findings; a fault's explainer on another fault's clip gives 0 (chain on the landing and
##     stance clips, landing on the others, stance on the others)
##   3 FIX: Teach.fixed(...) of each fault re-checks clean (0 findings) in the explainer that found it, the original scene is
##     unchanged, and the fix helps by a number: chain lead >= 80 ms; landing stop distance larger and force at least 2x lower;
##     stance margin >= +2 cm
##   4 TEXT: the text's own numbers, parsed back out, equal the measured ones (chain: frames, ms and m/s; landing: frame, deg, cm, BW;
##     stance: frame, cm, deg) and every number in it carries a unit
##   5 NOT CANNED: two different landing faults (calf 12 vs 30) and two stance faults (different lean) give different numbers and text
##   6 DETERMINISTIC: the same explain twice is byte-identical JSON; scene cards and body state are unchanged by every explain
##   7 SERVE: teach_chain / teach_landing / teach_stance on the live app: fault -> count 1 and the cause id; clean -> 0; {apply: true}
##     changes the live scene so the next call gives 0; apply "x" is -32602; teach.gd has no colour literal
extends SceneTree

var fails := 0
const FPS := 30.0
const PROX := ["pelvis", "spine_01", "spine_02", "spine_03"]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func ang_of(pose: Dictionary) -> Dictionary:
	var B := body()
	Scene.put(B, Moves._flat(pose))
	return B.ang.duplicate(true)


## a pose: base angles with `over` {joint: Vector3} replacing them, the joints in `from` (a joint list) taken from `src`
func pose_of(base: Dictionary, over := {}, src := {}, from := []) -> Dictionary:
	var B := body()
	for j in base:
		B.set_ang(j, base[j])
	for j in from:
		B.set_ang(j, src[j])
	for j in over:
		B.set_ang(j, over[j])
	B.fk()
	return B.to_dict()


func tpl() -> Array:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://templates/punch.json")))
	return S.cards


func chain_scene(with_hip_card: bool, turn := 25.0) -> Scene:
	var tc := tpl()
	var ag := ang_of(tc[0]["pose"])
	var al := ang_of(tc[1]["pose"])
	var ac := ang_of(tc[2]["pose"])
	var pel: Vector3 = ag["pelvis"]
	var sp2: Vector3 = ag["spine_02"]
	var turned := {"pelvis": Vector3(pel.x, pel.y, pel.z + turn), "spine_02": Vector3(sp2.x, sp2.y, sp2.z + turn * 0.5)}
	var S := Scene.new()
	S.name = "zz_teach_chain"
	var cards := [{"name": "guard", "pose": tc[0]["pose"].duplicate(true), "move": -1.0, "hold": 0.3}]
	cards.append({"name": "load", "pose": pose_of(al, {}, ag, PROX), "move": 0.25, "hold": 0.0})
	if with_hip_card:
		cards.append({"name": "hips", "pose": pose_of(al, turned, ag, ["spine_01", "spine_03"]), "move": 0.10, "hold": 0.0})
	cards.append({"name": "CROSS", "pose": pose_of(ac, turned, ag, ["spine_01", "spine_03"]), "move": 0.11, "hold": 0.0})
	cards.append({"name": "recover", "pose": tc[0]["pose"].duplicate(true), "move": 0.30, "hold": 0.3})
	S.cards = cards
	return S


func pose_leg(thigh: float, calf: float, arm: float) -> Dictionary:
	var B := body()
	for sd in ["_l", "_r"]:
		B.set_ang("thigh" + sd, Vector3(thigh, 0, 0))
		B.set_ang("calf" + sd, Vector3(calf, 0, 0))
		B.set_ang("upperarm" + sd, Vector3(arm, 0, 0))
	B.fk()
	return B.to_dict()


func jump_scene(land_thigh: float, land_calf: float) -> Scene:
	var B := body()
	var S := Scene.new()
	S.name = "zz_teach_land"
	S.add("stand", B.to_dict())
	S.add("dip", pose_leg(50, 90, 0))
	S.add("air", pose_leg(10, 20, 0))
	S.add("land", pose_leg(land_thigh, land_calf, 0))
	S.add("stand", B.to_dict())
	var mvs := [0.3, 0.3, 0.2855, 0.2855, 0.4]
	var hd := [0.1, 0.05, 0.0, 0.1, 0.2]
	for i in 5:
		S.cards[i]["move"] = mvs[i]
		S.cards[i]["hold"] = hd[i]
	S.cards[2]["air"] = true
	return S


func lean_scene(b: float) -> Scene:
	var B := body()
	var S := Scene.new()
	S.name = "zz_teach_stance"
	S.add("stand", B.to_dict())
	for j in ["spine_01", "spine_02", "spine_03"]:
		B.set_ang(j, Vector3(b, 0, 0))
	B.fk()
	S.add("lean", B.to_dict())
	S.cards[0]["move"] = -1.0
	S.cards[0]["hold"] = 0.2
	S.cards[1]["move"] = 0.3
	S.cards[1]["hold"] = 0.6
	return S


## the lean (a joint, deg) at which the held margin first drops to want_cm or less: a search, so the fault is measured, not guessed
func lean_for(want_cm: float) -> float:
	var b := 0.0
	while b <= 60.0:
		var S := lean_scene(b)
		var B := body()
		S.apply(B, S.length())
		if Balance.read(B)["margin"] * 100.0 <= want_cm:
			return b
		b += 2.0
	return -1.0


func state_sig(S: Scene, B: Body) -> String:
	return var_to_str(S.cards) + JSON.stringify(B.state())


func run_one(kind: String, S: Scene) -> Dictionary:
	var B := body()
	var sig0 := state_sig(S, B)
	var r: Dictionary = Callable(Teach, kind).call(S, B)
	ok(state_sig(S, B) == sig0, "6 %s %s: scene cards and body state unchanged" % [kind, S.name])
	return r


## numbers in a text with a given unit, as floats
func nums(text: String, unit: String) -> Array:
	var out := []
	var rx := RegEx.create_from_string("(-?\\d+(?:\\.\\d+)?) ?" + unit)
	for m in rx.search_all(text):
		out.append(float(m.get_string(1)))
	return out


func has_near(arr: Array, v: float, tol: float) -> bool:
	for x in arr:
		if absf(float(x) - v) <= tol:
			return true
	return false


## every number in the text carries a unit or follows the word frame (a sentence count or an ordinal is not allowed)
func unitless(text: String) -> Array:
	var bad := []
	var rx := RegEx.create_from_string("(frame )?(?<![A-Za-z0-9.])(-?\\d+(?:\\.\\d+)?)( ?(?:ms|m/s|cm|deg|BW|kN|N|%|s|x|frames?)\\b)?")
	for m in rx.search_all(text):
		if m.get_string(1) == "" and m.get_string(3) == "":
			bad.append(m.get_string(0))
	return bad


## independent: the hips' yaw (the line between the thighs' top ends) and the fastest hand, each at 60 Hz
func indep_chain(S: Scene) -> Dictionary:
	var B := body()
	var n := int(S.length() * 60.0) + 1
	var yaw := []
	var hl := []
	var hr := []
	for i in n:
		S.apply(B, float(i) / 60.0)
		var d: Vector3 = (B.P["thigh_l"] as Vector3) - B.P["thigh_r"]
		yaw.append(atan2(d.x, d.z))
		hl.append(B.P["hand_l"])
		hr.append(B.P["hand_r"])
	var best_v := 0.0
	var best_i := 0
	for hand in [hl, hr]:
		for i in range(1, n - 1):
			var v: float = ((hand[i + 1] as Vector3) - hand[i - 1]).length() * 30.0
			if v > best_v:
				best_v = v
				best_i = i
	var best_w := 0.0
	var wi := 0
	for i in range(maxi(1, best_i - 30), best_i + 1):
		var w := absf(angle_difference(yaw[i - 1], yaw[i + 1])) * 30.0
		if w > best_w:
			best_w = w
			wi = i
	return {"fist_i": best_i, "fist_v": best_v, "hip_i": wi, "lead_ms": (best_i - wi) / 60.0 * 1000.0}


func _init() -> void:
	var t_all := Time.get_ticks_msec()
	# ---- the clips
	var cf := chain_scene(false)
	var cc := chain_scene(true)
	var lf := jump_scene(8, 12)
	var lf2 := jump_scene(14, 30)
	var lc := jump_scene(50, 90)
	var b_hard := lean_for(-4.0)
	var b_soft := lean_for(-9.0)
	ok(b_hard > 0.0 and b_soft > b_hard, "0 planted stance faults exist: lean %.0f deg a joint puts the COM 4 cm past the feet, %.0f deg 9 cm" % [b_hard, b_soft])
	if b_hard < 0.0 or b_soft < 0.0:
		print("TEACH TEST FAIL (no planted lean)")
		quit(1)
		return
	var sf := lean_scene(b_hard)
	var sf2 := lean_scene(b_soft)
	var sc := lean_scene(4.0)
	var clips := {"chain": [cf, cc], "landing": [lf, lc], "stance": [sf, sc]}
	# ---- 1 / 6: the faults
	var rc := run_one("chain", cf)
	var rl := run_one("landing", lf)
	var rs := run_one("stance", sf)
	for pair in [["chain", rc, "no_hip_lead"], ["landing", rl, "stiff_landing"], ["stance", rs, "com_outside_feet"]]:
		var r: Dictionary = pair[1]
		ok(bool(r.get("ok", false)) and int(r.get("n", -1)) == 1 and String(r["findings"][0]["cause"]) == pair[2],
			"1 %s fault: 1 finding, cause %s (%s)" % [pair[0], pair[2], String(r.get("text", "")).left(200)])
	if int(rc.get("n", 0)) != 1 or int(rl.get("n", 0)) != 1 or int(rs.get("n", 0)) != 1:
		print("TEACH TEST FAIL (a fault was not found; the rest cannot be read)")
		quit(1)
		return
	var fc: Dictionary = rc["findings"][0]
	var fl: Dictionary = rl["findings"][0]
	var fs: Dictionary = rs["findings"][0]
	# chain vs the independent hips
	var ic := indep_chain(cf)
	var nc: Dictionary = fc["numbers"]
	print("chain: ours lead %.0f ms hip frame %d fist frame %d fist %.1f m/s turn %.0f deg | independent lead %.0f ms hip frame %.1f fist frame %.1f fist %.1f m/s" % [
		nc["lead_ms"], nc["hip_peak_frame"], nc["fist_peak_frame"], nc["fist_ms"], nc["hip_turn_deg"], ic["lead_ms"], ic["hip_i"] / 2.0, ic["fist_i"] / 2.0, ic["fist_v"]])
	ok(float(nc["lead_ms"]) < 40.0 and absf(float(nc["lead_ms"]) - float(ic["lead_ms"])) <= 35.0, "1 chain: lead %.0f ms under the 40 ms bar and within 35 ms of the independent %.0f ms" % [nc["lead_ms"], ic["lead_ms"]])
	ok(absf(float(nc["fist_peak_frame"]) - ic["fist_i"] / 2.0) <= 2.0 and absf(float(nc["hip_peak_frame"]) - ic["hip_i"] / 2.0) <= 2.0,
		"1 chain: fist frame %d / hip frame %d within 2 frames of the independent %.1f / %.1f" % [nc["fist_peak_frame"], nc["hip_peak_frame"], ic["fist_i"] / 2.0, ic["hip_i"] / 2.0])
	ok(absf(float(nc["fist_ms"]) - float(ic["fist_v"])) <= 0.5 and float(nc["hip_turn_deg"]) >= 10.0, "1 chain: fist speed %.1f m/s within 0.5 of %.1f, hips turn %.0f deg" % [nc["fist_ms"], ic["fist_v"], nc["hip_turn_deg"]])
	# landing vs Rulebook and the flight
	var jl: Array = Rulebook.jumps(lf, body())
	var nl: Dictionary = fl["numbers"]
	var v_ind: float = Scene.G * float(jl[0]["T"]) / 2.0
	print("landing: knee %.1f deg (Rulebook %.1f, bar %.1f) v %.2f m/s (independent %.2f) frame %d (t1 %.3f) stop %.1f cm force %.0f N = %.1f BW" % [
		nl["knee_deg"], jl[0]["land"], nl["bar_deg"], nl["impact_ms"], v_ind, nl["touchdown_frame"], jl[0]["t1"], nl["stop_cm"], nl["force_n"], nl["force_bw"]])
	ok(absf(float(nl["knee_deg"]) - float(jl[0]["land"])) <= 0.5 and float(nl["knee_deg"]) < float(nl["bar_deg"]), "1 landing: knee %.1f deg = Rulebook's %.1f and under the %.0f deg bar" % [nl["knee_deg"], jl[0]["land"], nl["bar_deg"]])
	ok(absf(float(nl["impact_ms"]) - v_ind) <= 0.05 and absi(int(nl["touchdown_frame"]) - int(round(float(jl[0]["t1"]) * FPS))) <= 1, "1 landing: impact %.2f m/s = g T / 2 = %.2f; frame %d vs %d" % [nl["impact_ms"], v_ind, nl["touchdown_frame"], int(round(float(jl[0]["t1"]) * FPS))])
	ok(float(nl["force_bw"]) >= 8.0 and float(nl["stop_cm"]) <= 5.0, "1 landing: stopping in %.1f cm means %.1f BW (bar >= 8 BW, <= 5 cm)" % [nl["stop_cm"], nl["force_bw"]])
	# stance vs Balance at the frame
	var ns: Dictionary = fs["numbers"]
	var Bq := body()
	sf.apply(Bq, float(ns["frame"]) / FPS)
	var mg := float(Balance.read(Bq)["margin"]) * 100.0
	print("stance: frame %d margin %.2f cm (independent %.2f) lean %.0f deg run %.2f s edge %s" % [ns["frame"], ns["margin_cm"], mg, ns["lean_deg"], ns["run_s"], str(ns["edge"])])
	ok(absf(float(ns["margin_cm"]) - mg) <= 0.3 and float(ns["margin_cm"]) <= -2.0, "1 stance: margin %.2f cm at frame %d = Balance's %.2f within 0.3 and past the 2 cm line" % [ns["margin_cm"], ns["frame"], mg])
	ok(absf(float(ns["lean_deg"]) - 3.0 * b_hard) <= 3.0 and String(ns["edge"]) == "front", "1 stance: lean %.0f deg vs the planted %.0f, edge %s" % [ns["lean_deg"], 3.0 * b_hard, ns["edge"]])
	# ---- 2 clean + cross
	for c in [["chain", cc], ["landing", lc], ["stance", sc]]:
		var r := run_one(c[0], c[1])
		ok(bool(r.get("ok", false)) and int(r.get("n", -1)) == 0, "2 clean %s control: 0 findings (%s)" % [c[0], String(r.get("text", "")).left(120)])
	var rcc := Teach.chain(cc, body())
	ok(float(rcc.get("measure", {}).get("lead_ms", 0.0)) >= 80.0, "2 clean chain: the hips lead the fist by %.0f ms (bar >= 80)" % float(rcc.get("measure", {}).get("lead_ms", 0.0)))
	for k in ["chain", "landing", "stance"]:
		for other in clips:
			if other == k:
				continue
			var r: Dictionary = Callable(Teach, k).call(clips[other][0], body())
			ok(int(r.get("n", -1)) == 0, "2 %s explainer on the %s fault clip: 0 findings" % [k, other])
	# ---- 3 fix
	for pair in [["chain", cf, fc], ["landing", lf, fl], ["stance", sf, fs]]:
		var S0: Scene = pair[1]
		var sig := var_to_str(S0.cards)
		var Sx: Scene = Teach.fixed(S0, body(), pair[2])
		var r: Dictionary = Callable(Teach, pair[0]).call(Sx, body())
		ok(var_to_str(S0.cards) == sig and Sx != S0 and int(r.get("n", -1)) == 0, "3 %s: the fix gives a new scene, the original is unchanged, and the re-check is clean (%s)" % [pair[0], String(pair[2].get("fix", {}).get("say", "")).left(140)])
		if pair[0] == "chain":
			var lead := float(r.get("measure", {}).get("lead_ms", 0.0))
			ok(lead >= 80.0, "3 chain: after the fix the hips lead by %.0f ms (bar >= 80, was %.0f)" % [lead, nc["lead_ms"]])
		elif pair[0] == "landing":
			var nl2: Dictionary = r.get("measure", {})
			ok(float(nl2.get("stop_cm", 0.0)) > float(nl["stop_cm"]) and float(nl2.get("force_n", 1e9)) * 2.0 <= float(nl["force_n"]),
				"3 landing: stop %.1f -> %.1f cm, force %.0f -> %.0f N (bar: at least 2x lower)" % [nl["stop_cm"], nl2.get("stop_cm", 0.0), nl["force_n"], nl2.get("force_n", 0.0)])
		else:
			var m2 := float(r.get("measure", {}).get("margin_cm", -99.0))
			ok(m2 >= 2.0, "3 stance: margin %.2f -> %.2f cm (bar >= +2)" % [ns["margin_cm"], m2])
	# ---- 4 text parsed back
	var tc_: String = fc["text"]
	ok(has_near(nums(tc_, "ms"), float(nc["lead_ms"]), 0.5) and has_near(nums(tc_, "ms"), float(ic["lead_ms"]), 35.0) and has_near(nums(tc_, "m/s"), float(ic["fist_v"]), 0.5)
		and has_near(nums(tc_, "deg"), float(nc["hip_turn_deg"]), 0.5), "4 chain text cites lead %.0f ms, fist %.1f m/s, hips %.0f deg: '%s'" % [nc["lead_ms"], ic["fist_v"], nc["hip_turn_deg"], tc_.left(240)])
	ok(tc_.contains("frame %d" % int(nc["fist_peak_frame"])) and tc_.contains("frame %d" % int(nc["hip_peak_frame"])), "4 chain text names frame %d and frame %d" % [nc["fist_peak_frame"], nc["hip_peak_frame"]])
	var tl_: String = fl["text"]
	ok(has_near(nums(tl_, "deg"), float(jl[0]["land"]), 0.5) and has_near(nums(tl_, "cm"), float(nl["stop_cm"]), 0.1) and has_near(nums(tl_, "m/s"), v_ind, 0.05)
		and has_near(nums(tl_, "BW"), float(nl["force_bw"]), 0.1) and tl_.contains("frame %d" % int(nl["touchdown_frame"])), "4 landing text cites knee %.0f deg, stop %.1f cm, %.2f m/s, %.1f BW, frame %d: '%s'" % [jl[0]["land"], nl["stop_cm"], v_ind, nl["force_bw"], nl["touchdown_frame"], tl_.left(260)])
	var ts_: String = fs["text"]
	ok(has_near(nums(ts_, "cm"), absf(mg), 0.3) and has_near(nums(ts_, "deg"), float(ns["lean_deg"]), 0.5) and ts_.contains("frame %d" % int(ns["frame"])) and ts_.contains("front"),
		"4 stance text cites %.1f cm past the front, lean %.0f deg, frame %d: '%s'" % [absf(mg), ns["lean_deg"], ns["frame"], ts_.left(240)])
	for t in [tc_, tl_, ts_]:
		ok(unitless(t).is_empty(), "4 every number carries a unit: %s" % str(unitless(t)))
	# ---- 5 not canned
	var rl2 := Teach.landing(lf2, body())
	var rs2 := Teach.stance(sf2, body())
	ok(int(rl2.get("n", 0)) == 1 and int(rs2.get("n", 0)) == 1, "5 the second landing (calf 30) and the second stance (lean %.0f) are also found" % b_soft)
	if int(rl2.get("n", 0)) == 1 and int(rs2.get("n", 0)) == 1:
		ok(rl2["findings"][0]["text"] != fl["text"] and absf(float(rl2["findings"][0]["numbers"]["knee_deg"]) - float(nl["knee_deg"])) > 3.0 and rs2["findings"][0]["text"] != fs["text"]
			and absf(float(rs2["findings"][0]["numbers"]["margin_cm"]) - float(ns["margin_cm"])) > 2.0,
			"5 different faults, different numbers: knee %.1f vs %.1f deg, margin %.1f vs %.1f cm" % [nl["knee_deg"], rl2["findings"][0]["numbers"]["knee_deg"], ns["margin_cm"], rs2["findings"][0]["numbers"]["margin_cm"]])
	# ---- 6 deterministic
	ok(JSON.stringify(Teach.chain(cf, body())) == JSON.stringify(rc) and JSON.stringify(Teach.landing(lf, body())) == JSON.stringify(rl) and JSON.stringify(Teach.stance(sf, body())) == JSON.stringify(rs),
		"6 a second explain of each fault is byte-identical")
	# ---- 7 the live app
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var T := AgentTools.new(m)
	var n_id := 10
	for c in [["teach_chain", cf, cc, "no_hip_lead"], ["teach_landing", lf, lc, "stiff_landing"], ["teach_stance", sf, sc, "com_outside_feet"]]:
		var tmp := ProjectSettings.globalize_path("user://teach_%s.json" % c[0])
		for which in [1, 2]:
			var f := FileAccess.open(tmp, FileAccess.WRITE)
			f.store_string(JSON.stringify((c[which] as Scene).to_dict(body())))
			f.close()
			n_id += 1
			await T.request(n_id, "open", {"path": tmp})
			n_id += 1
			var rr: Dictionary = (await T.request(n_id, c[0], {})).get("result", {})
			if which == 1:
				ok(int(rr.get("n", -1)) == 1 and String(rr.get("findings", [{}])[0].get("cause", "")) == c[3], "7 %s on the fault: 1 finding, %s" % [c[0], c[3]])
				n_id += 1
				var ap: Dictionary = (await T.request(n_id, c[0], {"apply": true})).get("result", {})
				n_id += 1
				var after: Dictionary = (await T.request(n_id, c[0], {})).get("result", {})
				ok(bool(ap.get("applied", false)) and int(after.get("n", -1)) == 0, "7 %s {apply: true}: applied %s, the next call gives %s findings" % [c[0], ap.get("applied", false), after.get("n", "?")])
			else:
				ok(int(rr.get("n", -1)) == 0, "7 %s on the clean control: 0 findings" % c[0])
		n_id += 1
		var bad: Dictionary = await T.request(n_id, c[0], {"apply": "x"})
		ok(bad.has("error") and int(bad["error"]["code"]) == -32602, "7 %s {apply: \"x\"} is -32602" % c[0])
		DirAccess.remove_absolute(tmp)
	var src := FileAccess.get_file_as_string("res://scripts/teach.gd")
	ok(src.length() > 500 and not src.contains("Color(") and not src.contains("add_theme_color_override"), "7 teach.gd has no colour literal")
	print("%s teach: %d failures (%.1f s)" % ["PASS" if fails == 0 else "FAIL", fails, (Time.get_ticks_msec() - t_all) / 1000.0])
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
