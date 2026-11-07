## godot --path . -s tests/styleprint_test.gd     (L90: ROADMAP_400 L27 clip personality fingerprint + L21 style transfer; needs main.tscn for undo)
## scripts/clip_print.gd (ClipPrint: measure / compare / table), scripts/clip_restyle.gd (ClipRestyle: plan / apply_plan),
## scripts/clip_print_serve.gd (agent tool `clip_print`, ops fingerprint and transfer). Bars written BEFORE the code, never moved.
## Fixtures: A = a snappy clip (moves 0.25-0.3 s, holds 0.5-0.6 s, ease out, natural); B = a slow one with DIFFERENT poses
## (moves 1.0-1.3 s, holds 0.1 s, smooth, not natural), 4 cards each, the same joints moving.
##   1 FINGERPRINT SELF: the distance from a clip to a second measurement of itself is exactly 0 (A and B)
##   2 SYMMETRIC: |d(A,B) - d(B,A)| <= 1e-12
##   3 RETIME x2 SLOWER (Scene.retime 200 %): the speed is lower (ratio in 0.4 .. 0.6), the hold fraction is HIGHER, and the
##     slowed clip is at distance > 0 from the original
##   4 TWO DIFFERENT CLIPS: d(A,B) > 0.3, and the table has a row for >= 8 joints and names hand_r and the distance
##   5 TRANSFER A -> B through the agent tool: B's key poses (every card's pose) are byte-identical (var_to_str), same card count and names
##   6 TRANSFER: d(B', A) <= 0.6 x d(B, A) (at least 40 % closer), measured with a fresh measure of the open scene
##   7 TRANSFER A onto A changes nothing: cards, natural, plants and markers byte-identical, result changed == false
##   8 CONTROL: a fake "transfer" that copies A's poses into B's cards FAILS the key-pose check of bar 5 (and the real result passes it)
##   9 PLANTS: B has a foot_l plant from card 1 to card 2; after the transfer its t0 / t1 are card 1's and card 2's arrival times
##     (1 ms), the planted foot moves <= 5 mm over [t0, t1], and sits <= 5 mm from where it was at the old t0
##   10 EACH ACTION IS ONE UNDO STEP: transfer pushes exactly 1 and undo gives cards / natural / plants back exactly; fingerprint pushes 0
##   11 REFUSALS name a reason and push nothing: unknown op, no src, missing file, a scene with part keys (not retimed)
##   12 LISTED: agent_tools.gd (MCP_EXTRA and the match), tools/mcp/poser_mcp.py and tools/run_all.sh name the tool / suite
extends SceneTree

var fails := 0
var Bd: Body
const FA := "user://zz_styleprint_A_%d.json"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func mkbody() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.wep_on = false
	b.fk()
	return b


func pose_of(spec: Dictionary) -> Dictionary:
	var R := mkbody()
	for j in spec:
		R.set_ang(String(j), spec[j] as Vector3)
	R.fk()
	return R.to_dict()


func mk(specs: Array, moves: Array, holds: Array, ease: String, natural: bool) -> Scene:
	var S := Scene.new()
	for i in specs.size():
		S.add("c%d" % i, pose_of(specs[i]))
		S.cards[i]["move"] = 0.0 if i == 0 else float(moves[i])
		S.cards[i]["hold"] = float(holds[i])
		if i > 0 and ease != "smooth":
			S.cards[i]["ease"] = ease
	S.natural = natural
	S.fps = 30
	return S


func spec_a() -> Array:
	return [
		{},
		{"upperarm_r": Vector3(70, 0, 25), "lowerarm_r": Vector3(90, 0, 0), "spine_03": Vector3(18, 0, 8), "head": Vector3(8, 0, 12), "thigh_l": Vector3(25, 0, 0), "calf_l": Vector3(35, 0, 0)},
		{"upperarm_r": Vector3(-20, 0, -10), "lowerarm_r": Vector3(30, 0, 0), "spine_03": Vector3(-8, 0, -10), "head": Vector3(-5, 0, -10), "thigh_l": Vector3(-10, 0, 0), "calf_l": Vector3(10, 0, 0)},
		{"upperarm_r": Vector3(45, 0, 15), "lowerarm_r": Vector3(60, 0, 0), "spine_03": Vector3(12, 0, 4), "head": Vector3(3, 0, 6), "thigh_l": Vector3(15, 0, 0), "calf_l": Vector3(20, 0, 0)}]


func spec_b() -> Array:
	return [
		{},
		{"upperarm_r": Vector3(35, 0, 10), "lowerarm_r": Vector3(45, 0, 0), "spine_03": Vector3(8, 0, 4), "head": Vector3(4, 0, 6), "thigh_l": Vector3(12, 0, 0), "calf_l": Vector3(18, 0, 0)},
		{"upperarm_r": Vector3(-10, 0, -5), "lowerarm_r": Vector3(15, 0, 0), "spine_03": Vector3(-4, 0, -5), "head": Vector3(-2, 0, -5), "thigh_l": Vector3(-5, 0, 0), "calf_l": Vector3(5, 0, 0)},
		{"upperarm_r": Vector3(25, 0, 8), "lowerarm_r": Vector3(35, 0, 0), "spine_03": Vector3(6, 0, 2), "head": Vector3(2, 0, 3), "thigh_l": Vector3(8, 0, 0), "calf_l": Vector3(10, 0, 0)}]


func clip_a() -> Scene:
	return mk(spec_a(), [0, 0.25, 0.3, 0.25], [0.5, 0.6, 0.5, 0.5], "out", true)


func clip_b() -> Scene:
	var S := mk(spec_b(), [0, 1.1, 1.3, 1.0], [0.1, 0.1, 0.1, 0.1], "smooth", false)
	var ts := S.times()
	S.plants = [{"foot": "foot_l", "t0": snappedf(float(ts[1][1]), 0.001), "t1": snappedf(float(ts[2][1]), 0.001)}]
	return S


func keys_of(S: Scene) -> Array:
	return S.cards.map(func(c): return var_to_str(c["pose"]))


func keys_ok(S: Scene, ref: Array, names: Array) -> bool:
	if S.cards.size() != ref.size():
		return false
	for i in ref.size():
		if var_to_str(S.cards[i]["pose"]) != String(ref[i]) or String(S.cards[i]["name"]) != String(names[i]):
			return false
	return true


func foot_at(S: Scene, t: float) -> Vector3:
	S.apply(Bd, t)
	Bd.fk()
	return Bd.P["foot_l"]


func state_of(S: Scene) -> String:
	return var_to_str([S.cards, S.natural, S.plants, S.markers])


func _init() -> void:
	Bd = mkbody()
	var pid := OS.get_process_id()
	var pa: String = FA % pid
	var A := clip_a()
	var fa := FileAccess.open(pa, FileAccess.WRITE)
	fa.store_string(JSON.stringify(A.to_dict(mkbody())))
	fa.close()
	var B := clip_b()
	var ta := Time.get_ticks_msec()
	var fpA := ClipPrint.measure(A)
	var fpA2 := ClipPrint.measure(A)
	var fpB := ClipPrint.measure(B)
	var fpB2 := ClipPrint.measure(B)
	print("measure x4: %d ms" % (Time.get_ticks_msec() - ta))

	# 1 self
	var dAA: float = ClipPrint.compare(fpA, fpA2)["distance"]
	var dBB: float = ClipPrint.compare(fpB, fpB2)["distance"]
	ok(dAA == 0.0 and dBB == 0.0, "1 distance to itself: A %.12f, B %.12f (exactly 0)" % [dAA, dBB])

	# 2 symmetric
	var cAB: Dictionary = ClipPrint.compare(fpA, fpB)
	var dAB: float = cAB["distance"]
	var dBA: float = ClipPrint.compare(fpB, fpA)["distance"]
	ok(absf(dAB - dBA) <= 1e-12, "2 symmetric: d(A,B) %.9f, d(B,A) %.9f" % [dAB, dBA])

	# 3 retime x2 slower
	var Bs := clip_b()
	Bs.retime(0, Bs.cards.size() - 1, 200.0)
	var fpS := ClipPrint.measure(Bs)
	var spB: float = fpB["global"]["speed"]
	var spS: float = fpS["global"]["speed"]
	var hB: float = fpB["global"]["hold"]
	var hS: float = fpS["global"]["hold"]
	var dBS: float = ClipPrint.compare(fpB, fpS)["distance"]
	ok(spS / spB >= 0.4 and spS / spB <= 0.6 and hS > hB and dBS > 0.0,
		"3 retimed x2 slower: speed %.2f -> %.2f deg/s (ratio %.3f), hold %.3f -> %.3f, distance %.3f" % [spB, spS, spS / spB, hB, hS, dBS])

	# 4 different clips, table
	var tab: String = ClipPrint.table(fpA, fpB, "A", "B")
	var rows: Array = cAB["rows"]
	ok(dAB > 0.3 and rows.size() >= 8 and tab.contains("hand_r") and tab.to_lower().contains("distance"),
		"4 A vs B: distance %.3f, %d joint rows, terms %s" % [dAB, rows.size(), str(cAB["terms"])])
	print(tab)

	# the open scene for the tool bars
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 4:
		await process_frame
	m.S = B
	m._rebuild_cards()
	var refK := keys_of(B)
	var names := B.cards.map(func(c): return String(c["name"]))
	var t0_old := float(B.plants[0]["t0"])
	var foot_old := foot_at(B, t0_old)
	var before := state_of(B)
	# DIAGNOSTIC (not a bar): the same foot drift on B before any transfer
	var d_b := 0.0
	var tb0 := float(B.plants[0]["t0"])
	var fb0 := foot_at(B, tb0)
	var tq := tb0
	while tq <= float(B.plants[0]["t1"]):
		d_b = maxf(d_b, (foot_at(B, tq) - fb0).length())
		tq += 1.0 / 30.0
	print("diag: foot_l drift over the plant in B BEFORE the transfer: %.2f mm" % (d_b * 1000.0))

	# 5, 6, 9, 10 transfer A -> B
	m.undo.clear()
	var tt := Time.get_ticks_msec()
	var r: Dictionary = ClipPrintServe.serve(m, {"op": "transfer", "src": pa})
	var ms := Time.get_ticks_msec() - tt
	var S2: Scene = m.S
	ok(r.get("ok", false) and bool(r["result"].get("changed", false)), "transfer ran (%d ms): %s" % [ms, str(r.get("error", ""))])
	ok(keys_ok(S2, refK, names), "5 B's key poses byte-identical after the transfer (%d cards)" % S2.cards.size())
	var fpB2n := ClipPrint.measure(S2)
	var dNew: float = ClipPrint.compare(fpB2n, fpA)["distance"]
	ok(dNew <= 0.6 * dAB, "6 d(B', A) %.3f vs d(B, A) %.3f: %.1f %% closer (bar >= 40 %%); terms before %s after %s" % [
		dNew, dAB, 100.0 * (1.0 - dNew / maxf(dAB, 1e-9)), str(cAB["terms"]), str(ClipPrint.compare(fpB2n, fpA)["terms"])])
	ok(m.undo.size() == 1, "10 transfer pushed %d undo step(s)" % m.undo.size())
	# 9 plants
	var ts2 := S2.times()
	var p2: Dictionary = S2.plants[0] if S2.plants.size() == 1 else {}
	var plant_ok := not p2.is_empty() and absf(float(p2["t0"]) - float(ts2[1][1])) <= 0.001 and absf(float(p2["t1"]) - float(ts2[2][1])) <= 0.001
	var drift := 0.0
	var off := 1e9
	if plant_ok:
		var f0 := foot_at(S2, float(p2["t0"]))
		off = (f0 - foot_old).length()
		var t := float(p2["t0"])
		while t <= float(p2["t1"]):
			drift = maxf(drift, (foot_at(S2, t) - f0).length())
			t += 1.0 / 30.0
		drift = maxf(drift, (foot_at(S2, float(p2["t1"])) - f0).length())
	ok(plant_ok and drift <= 0.005 and off <= 0.005, "9 plant t0/t1 follow the cards %s, foot drift %.2f mm, offset from the old place %.2f mm" % [plant_ok, drift * 1000.0, off * 1000.0])
	# 10 undo
	m._undo()
	ok(state_of(m.S) == before, "10 undo gives cards / natural / plants / markers back exactly")

	# 8 control
	var fake := clip_b()
	for i in fake.cards.size():
		fake.cards[i]["pose"] = (A.cards[i]["pose"] as Dictionary).duplicate(true)
	ok(not keys_ok(fake, refK, names) and keys_ok(S2, refK, names), "8 control: copying A's poses fails the key-pose check; the real transfer passes it")

	# 7 A onto A
	var SA := Scene.new()
	SA.from_dict(JSON.parse_string(FileAccess.get_file_as_string(pa)))
	m.S = SA
	m._rebuild_cards()
	var stA := state_of(m.S)
	m.undo.clear()
	var rA: Dictionary = ClipPrintServe.serve(m, {"op": "transfer", "src": pa})
	ok(rA.get("ok", false) and not bool(rA["result"].get("changed", true)) and state_of(m.S) == stA, "7 A onto A: changed %s, cards / natural / plants / markers byte-identical %s, undo steps %d" % [
		str(rA.get("result", {}).get("changed")), state_of(m.S) == stA, m.undo.size()])

	# 10 fingerprint pushes nothing, and answers with the table and one distance
	var rF: Dictionary = ClipPrintServe.serve(m, {"op": "fingerprint", "src": pa})
	ok(rF.get("ok", false) and m.undo.size() == 0 and rF["result"].has("distance") and rF["result"].has("table") and float(rF["result"]["distance"]) == 0.0,
		"10 fingerprint: ok %s, undo steps %d, distance to itself %s" % [rF.get("ok"), m.undo.size(), str(rF.get("result", {}).get("distance"))])

	# 11 refusals
	var SP := clip_b()
	SP.part_keys = {"hand_r": [{"t": 0.0, "v": Vector3.ZERO}, {"t": 1.0, "v": Vector3(10, 0, 0)}]}
	m.S = SP
	m.undo.clear()
	var bad := [ClipPrintServe.serve(m, {"op": "dance"}), ClipPrintServe.serve(m, {"op": "transfer"}),
		ClipPrintServe.serve(m, {"op": "transfer", "src": "user://zz_no_such_file.json"}), ClipPrintServe.serve(m, {"op": "transfer", "src": pa})]
	var refused := true
	for b in bad:
		refused = refused and not b.get("ok", true) and String(b.get("error", "")).length() > 8
	ok(refused and m.undo.size() == 0, "11 four bad calls refused with a reason (%s), no undo step (%d)" % [" | ".join(bad.map(func(b): return String(b.get("error", "?")).left(40))), m.undo.size()])

	# 12 listed
	var tools_src := FileAccess.get_file_as_string("res://scripts/agent_tools.gd")
	var py := FileAccess.get_file_as_string("res://tools/mcp/poser_mcp.py")
	var ra := FileAccess.get_file_as_string("res://tools/run_all.sh")
	ok(tools_src.contains('"clip_print"') and tools_src.contains("ClipPrintServe.serve") and py.contains('"clip_print"') and ra.contains("styleprint:w"),
		"12 clip_print listed in agent_tools.gd and poser_mcp.py; styleprint in run_all.sh")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(pa))
	print("---- styleprint_test: %d failed" % fails)
	quit(1 if fails > 0 else 0)
