## godot --headless --path . -s tests/floorinjury_test.gd     (L98: N035 floor material, N036 injury profile)
## N035 FLOOR MATERIAL (scripts/floor_material.gd): a scene floor sets the shoe-floor friction coefficient mu that the friction judges read:
## Momentum (the stop: horizontal ground force over a planted stop is at most mu x the vertical load, 1 body weight standing; the pivot:
## the friction couple scales with mu) and the Force view (the friction cone). No material = today, untouched.
## THE NUMBERS (static / dynamic shoe-floor COF), and where they come from (read by me 11-06, search results, primaries not all opened):
##   mat       0.75  (UNVERIFIED: 0.75 is not in the cited paper's text, which gives required COF 0.35/0.45/0.54; values may sit only in figures) rubber shoe sole on dry rubber floor tiles, 0.75 (Friction Coefficient of Rubber Shoe Sole Sliding Against Different Rubber
##                   Floor Tiles, Tribology in Industry 2022, tribology.rs/journals/2022/2022-2/5-1188.pdf)
##   concrete  1.00  rubber on dry concrete, 1.0 (a floor-safety trade article; no test method given: WEAK source; UNVERIFIED (from memory))
##   wet_tile  0.20  wet old tile 0.2-0.3, new wet tile 0.4-0.5 (tile-cleaning patent US 8,782,843 table; contaminated wet tile in a campus
##                   study lost 90-99 % of its friction): the low end, the slippery case Nick asked for. NOT a shoe-sole test; UNVERIFIED (from memory), patent not opened
##   wood      0.50  NO measured shoe-on-wood value found; 0.5 is the static COF adopted as a US floor-safety standard (Miller 1983, as cited
##                   in the sand-floor campus study, Safety Science 2006, UNVERIFIED (no source found)): a PLACEHOLDER, flagged
##   sand      0.40  NO measured shoe-on-sand value found (the campus study found sand on a floor drops friction well below dry and wet, no
##                   number read): 0.4 is MINE, flagged
## HOW the judge reads it: a body gets at most mu x 1 BW of horizontal force from a planted foot, so the stop's bar is min(1.6 BW, mu BW)
## (1.6 = the existing measured braking ceiling). Without a material the bar is exactly today's 1.6 and nothing else changes.
## N036 INJURY PROFILE (scripts/injury.gd): {"calf_r": {"rom": 0.30, "strength": 0.40}} = the joint's range of motion is 30 % smaller on every
## axis (both ends scaled about the rest angle 0) and its strength 40 % smaller. "knee_r" etc. are accepted names (knee = calf, shoulder =
## upperarm, hip = thigh, elbow = lowerarm, ankle = foot). Judges use the reduced values: INJURY ROM (the motion goes past the reduced stop),
## JOINT TORQUE and JOINT SPEED bars scaled by (1 - strength). Saved with the scene (the fighter).
## Bars (stated before any implementation):
##  F1 reads mu exactly: for each of the five materials Momentum.analyze reports mu == the table value and the stop's bar_bw == min(1.6, mu)
##  F2 PLANTED STOP needs mu 0.6 (a dash stop whose measured ground force is 0.50-0.70 BW, found by a fixed grid): no material -> not flagged;
##     wet_tile -> flagged (bar 0.2); mat -> not flagged; the force f_bw is identical in all three (only the bar moves)
##  F3 default is today's: no floor_mat key in to_dict, analyze keys unchanged (no "mu" key), set + clear leaves analyze and findings equal
##     byte for byte (var_to_str)
##  F4 pivot: Momentum.yaw_arm(mu) == 0.25 x min(1, mu) exactly; tau_ratio on wet tile >= the default's
##  F5 slide: ForceView.capture carries "mu" == 0.2 on wet tile and has no "mu" by default
##  F6 saved/loaded: to_dict -> JSON -> from_dict gives the same floor_mat and injury; clone() keeps both
##  I1 a knee profile at ROM -30 % clamps max flexion to 0.7 x the healthy max within 0.1 deg; clear restores B.lim byte for byte
##  I2 torque cap: shoulder strength 0.40 -> cap == 0.6 x healthy within 1e-9; rule_torque flags a 0.8 x warn series only with the profile; the
##     other shoulder is untouched. JOINT SPEED knee bar x0.6 the same way
##  I3 a KICK (knee 120 deg, healthy max 145) passes today; with the knee profile (max 101.5) it FAILs, INJURY ROM is listed with its frame
##     (the first frame past 101.5, inside the move) and its card, peak within 1 deg of 120, limit within 0.1 of 101.5
##  I4 remove the profile: HumanLimits.findings var_to_str equals the healthy baseline (byte for byte)
##  I5 CONTROL: both knees kick; a RIGHT knee profile gives the LEFT knee the same verdicts (no calf_l finding, with or without it); a LEFT
##     profile flags calf_l and not calf_r (the control is not vacuous)
##  I6 moves list: Injury.moves lists the kick card once, with its frame
##  U  each edit (floor set, floor clear, injury set, injury clear) is exactly ONE undo step; read/list add none; a refusal (unknown material,
##     unknown joint, rom 1.5) adds none and changes nothing
##  D  deterministic: Injury.findings and Momentum.analyze twice are byte-identical
extends SceneTree

var fails := 0
const MATS := {"mat": 0.75, "concrete": 1.0, "wet_tile": 0.2, "wood": 0.5, "sand": 0.4}


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func dash_scene(d: float, t: float) -> Scene:
	var B := body()
	var S := Scene.new()
	S.name = "zz_dash"
	S.add("stand", B.to_dict())
	B.offset = Vector3(0, 0, d)
	B.fk()
	S.add("dash", B.to_dict())
	S.cards[0]["hold"] = 0.3
	S.cards[1]["move"] = t
	S.cards[1]["hold"] = 0.5
	return S


func kick_scene(right := true, left := false, flex := 120.0) -> Scene:
	var B := body()
	var S := Scene.new()
	S.name = "zz_kick"
	S.add("stand", B.to_dict())
	if right:
		B.set_ang("calf_r", Vector3(flex, 0, 0))
	if left:
		B.set_ang("calf_l", Vector3(flex, 0, 0))
	B.fk()
	S.add("kick", B.to_dict())
	S.cards[0]["hold"] = 0.2
	S.cards[1]["move"] = 0.5
	S.cards[1]["hold"] = 0.4
	return S


func arm_scene() -> Scene:
	var B := body()
	var S := Scene.new()
	S.name = "zz_arms"
	S.add("stand", B.to_dict())
	B.set_ang("upperarm_r", Vector3(130, 0, 0))
	B.set_ang("upperarm_l", Vector3(130, 0, 0))
	B.fk()
	S.add("swing", B.to_dict())
	S.cards[0]["hold"] = 0.2
	S.cards[1]["move"] = 0.2
	S.cards[1]["hold"] = 0.4
	return S


func stub() -> Node:
	var gs := GDScript.new()
	gs.source_code = "extends Node\nvar S\nvar B\nvar undo := []\nfunc _push_undo() -> void:\n\tundo.append(var_to_str(S.floor_mat) + var_to_str(S.injury))\n"
	gs.reload()
	return gs.new()


func rows_of(S: Scene, B: Body) -> Dictionary:
	return Momentum.analyze(S, B)


func joint_findings(fs: Array, j: String) -> Array:
	return fs.filter(func(f): return String(f.get("joint", "")) == j and String(f["rule"]) == "INJURY ROM")


func _init() -> void:
	var B := body()
	# ---------- FLOOR
	ok(FloorMaterial.MU.size() == 5, "0 five materials: %s" % [FloorMaterial.MU.keys()])
	for k in MATS:
		ok(FloorMaterial.MU.has(k) and FloorMaterial.MU[k] == MATS[k], "0 %s mu is %.2f (table %s)" % [k, MATS[k], FloorMaterial.MU.get(k)])
	# calibrate the planted stop
	var best_d := 0.0
	var best_t := 0.0
	var best_f := 1e9
	for d in [0.5, 1.0, 1.5, 2.5, 4.0]:
		for t in [0.3, 0.5, 0.8, 1.2, 2.0]:
			var Sg := dash_scene(d, t)
			var a: Dictionary = rows_of(Sg, B)
			if a["ok"] and not a["rows"].is_empty() and not a["rows"][0]["flag"]:
				var f: float = a["rows"][0]["f_bw"]
				if absf(f - 0.6) < absf(best_f - 0.6):
					best_f = f
					best_d = d
					best_t = t
	print("     planted stop: dash %.1f m in %.1f s, ground force %.3f BW" % [best_d, best_t, best_f])
	ok(best_f >= 0.5 and best_f <= 0.7, "F2 a stop that needs mu 0.5-0.7 exists on the grid: %.3f BW" % best_f)
	var S := dash_scene(best_d, best_t)
	var a0: Dictionary = rows_of(S, B)
	var s0 := var_to_str(a0)
	var f0 := var_to_str(HumanLimits.findings(S, B))
	ok(not a0.has("mu") and not S.to_dict(B).has("floor_mat") and not S.to_dict(B).has("injury"), "F3 default: analyze has no mu key, the file has no floor_mat / injury key")
	ok(a0["flags"].is_empty(), "F2 no material: not flagged (%s)" % a0["msg"])
	for k in MATS:
		S.floor_mat = k
		var a: Dictionary = rows_of(S, B)
		ok(a.has("mu") and float(a["mu"]) == float(MATS[k]) and float(a["rows"][0]["bar_bw"]) == minf(Momentum.BRACE_BW, float(MATS[k])), "F1 %s: judge mu %s, bar %.3f BW (min(1.6, %.2f))" % [k, a.get("mu"), a["rows"][0]["bar_bw"], MATS[k]])
		if k == "wet_tile":
			ok(a["flags"].size() == 1 and a["rows"][0]["flag"] and absf(float(a["rows"][0]["f_bw"]) - best_f) < 1e-9, "F2 wet_tile: the %.3f BW stop is FLAGGED (bar 0.2): %s" % [best_f, a["msg"]])
			if not a["flags"].is_empty():
				print("     ", a["flags"][0]["msg"])
		if k == "mat":
			ok(a["flags"].is_empty() and absf(float(a["rows"][0]["f_bw"]) - best_f) < 1e-9, "F2 mat: the same stop passes (bar 0.75 > %.3f)" % best_f)
	var tau_def := 0.0
	var Sa := arm_scene()
	var aa: Dictionary = rows_of(Sa, B)
	tau_def = float(aa["rows"][0]["tau_ratio"])
	Sa.floor_mat = "wet_tile"
	var aw: Dictionary = rows_of(Sa, B)
	ok(Momentum.yaw_arm(0.2) == 0.25 * 0.2 and Momentum.yaw_arm(1.0) == 0.25 and Momentum.yaw_arm(1.5) == 0.25, "F4 yaw arm = 0.25 x min(1, mu): %.4f at 0.2" % Momentum.yaw_arm(0.2))
	ok(tau_def > 0.0 and float(aw["rows"][0]["tau_ratio"]) >= tau_def, "F4 pivot torque ratio dry %.4f -> wet tile %.4f (>= and the default is not zero)" % [tau_def, aw["rows"][0]["tau_ratio"]])
	S.floor_mat = ""   # the F1 loop left "sand" set; the default capture must see no material
	var capw := ForceView.capture(S, B)
	S.floor_mat = "wet_tile"
	var capw2 := ForceView.capture(S, B)
	S.floor_mat = ""
	ok(not capw.has("mu") and capw2.has("mu") and float(capw2["mu"]) == 0.2, "F5 ForceView.capture mu: default %s, wet tile %s" % [capw.get("mu"), capw2.get("mu")])
	# F3 set + clear leaves the output equal
	ok(var_to_str(rows_of(S, B)) == s0 and var_to_str(HumanLimits.findings(S, B)) == f0, "F3 set + clear: Momentum.analyze and HumanLimits.findings byte-identical")
	# ---------- INJURY
	var prof := {"calf_r": {"rom": 0.30, "strength": 0.40}}
	var healthy_max: float = B.lim["calf_r"]["bend"].y
	var lim0 := var_to_str(B.lim)
	Injury.apply(B, prof)
	B.set_ang("calf_r", Vector3(500, 0, 0))
	var got: float = B.ang["calf_r"].x
	B.set_ang("calf_l", Vector3(500, 0, 0))
	var got_l: float = B.ang["calf_l"].x
	ok(absf(got - 0.7 * healthy_max) <= 0.1 and absf(got_l - healthy_max) <= 0.1, "I1 ROM -30 %%: knee flexion max %.2f deg (0.7 x %.1f = %.2f); the left knee %.2f untouched" % [got, healthy_max, 0.7 * healthy_max, got_l])
	Injury.clear(B)
	ok(var_to_str(B.lim) == lim0, "I1 clear restores B.lim byte for byte")
	# torque and speed
	var base := float(HumanLimits.shoulder_bars(75.0)[0])
	var sp := {"upperarm_r": {"strength": 0.40}}
	ok(absf(Injury.torque_cap(sp, "upperarm_r", base) - 0.6 * base) <= 1e-9 and Injury.torque_cap(sp, "upperarm_l", base) == base, "I2 torque cap %.3f = 0.6 x %.3f; the left shoulder %.3f" % [Injury.torque_cap(sp, "upperarm_r", base), base, Injury.torque_cap(sp, "upperarm_l", base)])
	var ser_r := []
	var ser_l := []
	for i in 30:
		ser_r.append(0.8 * base)
		ser_l.append(0.8 * base)
	var smt := {"t": range(30).map(func(i): return i / 60.0), "torque": {"shoulder_r": ser_r, "shoulder_l": ser_l}, "mass": 75.0}
	var t_def := HumanLimits.rule_torque(smt)
	smt["injury"] = sp
	var t_inj := HumanLimits.rule_torque(smt)
	ok(t_def.is_empty() and t_inj.size() == 1 and String(t_inj[0]["msg"]).contains("shoulder"), "I2 0.8 x warn torque: %d findings healthy, %d with the profile (right shoulder only)" % [t_def.size(), t_inj.size()])
	var spd := {"t": range(30).map(func(i): return i / 60.0), "speed": {"knee_r": range(30).map(func(i): return 0.8 * 1874.0), "knee_l": range(30).map(func(i): return 0.8 * 1874.0)}}
	var sp_def := HumanLimits.rule_speed(spd)
	spd["injury"] = {"calf_r": {"strength": 0.40}}
	var sp_inj := HumanLimits.rule_speed(spd)
	ok(sp_def.is_empty() and sp_inj.size() == 1 and String(sp_inj[0]["joint"]) == "knee_r", "I2 knee speed bar x0.6: %d findings healthy, %d with the profile (right knee)" % [sp_def.size(), sp_inj.size()])
	# the kick
	var K := kick_scene()
	var base_f := HumanLimits.findings(K, B)
	var base_s := var_to_str(base_f)
	var base_inj := Injury.findings(K, B)
	ok(base_inj.is_empty() and base_f.filter(func(f): return f["sev"] == "FAIL").is_empty(), "I3 the healthy kick (knee 120 of %.0f) passes: %d findings, no FAIL" % [healthy_max, base_f.size()])
	K.injury = prof
	var fi := Injury.findings(K, B)
	var hl := HumanLimits.findings(K, B)
	var rom := joint_findings(fi, "calf_r")
	var inroute := hl.filter(func(f): return String(f["rule"]) == "INJURY ROM")
	var f1: Dictionary = rom[0] if not rom.is_empty() else {}
	var ts := K.times()
	var lim_inj := 0.7 * healthy_max
	ok(not rom.is_empty() and String(f1["sev"]) == "FAIL" and absf(float(f1["limit"]) - lim_inj) <= 0.1 and absf(float(f1["peak"]) - 120.0) <= 1.0 and int(f1["card"]) == 1, "I3 kick FAILs: %s" % [rom.map(func(f): return [f["sev"], f["frame"], f["peak"], f["limit"], f["card"]])])
	if not rom.is_empty():
		var tf := float(f1["frame"]) / float(K.fps)
		ok(tf >= float(ts[1][0]) - 0.04 and tf <= float(ts[1][1]) + 0.04 and String(f1["msg"]).contains("frame") and String(f1["msg"]).contains("knee"), "I3 the frame %d (%.2f s) is inside the move %.2f-%.2f s; msg: %s" % [f1["frame"], tf, ts[1][0], ts[1][1], f1["msg"]])
	ok(not inroute.is_empty(), "I3 the check path (HumanLimits.findings) lists INJURY ROM: %d" % inroute.size())
	var mv := Injury.moves(K, B)
	ok(mv.size() == 1 and int(mv[0]["card"]) == 1 and mv[0].has("frame") and String(mv[0]["name"]) == "kick", "I6 moves list: %s" % [mv])
	K.injury = {}
	ok(var_to_str(HumanLimits.findings(K, B)) == base_s and Injury.moves(K, B).is_empty(), "I4 profile removed: findings byte-identical to the healthy baseline")
	# control
	var K2 := kick_scene(true, true)
	var h2 := var_to_str(joint_findings(Injury.findings(K2, B), "calf_l")) + var_to_str(HumanLimits.findings(K2, B))
	K2.injury = {"calf_r": {"rom": 0.30, "strength": 0.40}}
	var r2 := Injury.findings(K2, B)
	var left_on_right := joint_findings(r2, "calf_l")
	var hl2 := HumanLimits.findings(K2, B).filter(func(f): return String(f["rule"]) != "INJURY ROM")
	ok(left_on_right.is_empty() and not joint_findings(r2, "calf_r").is_empty() and var_to_str(hl2) == var_to_str(HumanLimits.findings(kick_scene(true, true), B)), "I5 CONTROL right-knee profile: left knee findings %d (same as healthy), right %d; every other finding unchanged" % [left_on_right.size(), joint_findings(r2, "calf_r").size()])
	K2.injury = {"calf_l": {"rom": 0.30, "strength": 0.40}}
	var r3 := Injury.findings(K2, B)
	ok(not joint_findings(r3, "calf_l").is_empty() and joint_findings(r3, "calf_r").is_empty(), "I5 positive control, left profile: left %d, right %d" % [joint_findings(r3, "calf_l").size(), joint_findings(r3, "calf_r").size()])
	# determinism
	K.injury = prof
	ok(var_to_str(Injury.findings(K, B)) == var_to_str(Injury.findings(K, B)) and var_to_str(rows_of(S, B)) == var_to_str(rows_of(S, B)), "D deterministic: findings and analyze twice are byte-identical")
	# save / load / clone
	K.floor_mat = "wood"
	var js: Dictionary = JSON.parse_string(JSON.stringify(K.to_dict(B)))
	var KL := Scene.new()
	KL.from_dict(js)
	var KC := K.clone()
	ok(KL.floor_mat == "wood" and var_to_str(KL.injury) == var_to_str(prof) and KC.floor_mat == "wood" and var_to_str(KC.injury) == var_to_str(prof), "F6 saved and loaded (and cloned): %s %s" % [KL.floor_mat, KL.injury])
	# ---------- UNDO (the tools)
	var m := stub()
	var U := kick_scene()
	m.S = U
	m.B = B
	var u0: int = m.undo.size()
	var r_read: Dictionary = FloorMaterial.serve(m, {"action": "read"})
	var r_list: Dictionary = FloorMaterial.serve(m, {"action": "list"})
	var i_read: Dictionary = Injury.serve(m, {"action": "read"})
	var reads: int = m.undo.size() - u0
	var rs: Dictionary = FloorMaterial.serve(m, {"action": "set", "material": "wet_tile"})
	var s1: int = m.undo.size() - u0 - reads
	var rc: Dictionary = FloorMaterial.serve(m, {"action": "clear"})
	var s2: int = m.undo.size() - u0 - reads - s1
	var is_: Dictionary = Injury.serve(m, {"action": "set", "joint": "knee_r", "rom": 0.3, "strength": 0.4})
	var s3: int = m.undo.size() - u0 - reads - s1 - s2
	var iset := var_to_str(U.injury)
	var imv: Dictionary = Injury.serve(m, {"action": "moves"})
	var ic: Dictionary = Injury.serve(m, {"action": "clear"})
	var s4: int = m.undo.size() - u0 - reads - s1 - s2 - s3
	ok(r_read["ok"] and r_list["ok"] and i_read["ok"] and reads == 0, "U read / list add no undo step (%d)" % reads)
	ok(rs["ok"] and rc["ok"] and is_["ok"] and ic["ok"] and s1 == 1 and s2 == 1 and s3 == 1 and s4 == 1, "U floor set / clear, injury set / clear: one undo step each (%d %d %d %d)" % [s1, s2, s3, s4])
	ok(isset_ok(iset) and imv["ok"] and (imv["result"]["moves"] as Array).size() == 1 and U.injury.is_empty() and U.floor_mat == "", "U knee_r alias stored as calf_r; the tool lists the move; clear empties the scene")
	var before := var_to_str(U.injury) + U.floor_mat
	var n0: int = m.undo.size()
	var bad := [FloorMaterial.serve(m, {"action": "set", "material": "lava"}), Injury.serve(m, {"action": "set", "joint": "tail", "rom": 0.3}), Injury.serve(m, {"action": "set", "joint": "knee_r", "rom": 1.5})]
	var refused := bad.filter(func(r): return not r["ok"] and String(r["error"]).length() > 8).size()
	ok(refused == 3 and m.undo.size() == n0 and var_to_str(U.injury) + U.floor_mat == before, "U %d of 3 refusals with a sentence, %d undo steps, scene unchanged" % [refused, m.undo.size() - n0])
	print("FLOORINJURY: ", "ok" if fails == 0 else "%d FAIL" % fails)
	quit(1 if fails > 0 else 0)


func isset_ok(s: String) -> bool:
	return s.contains("calf_r") and not s.contains("knee_r")
