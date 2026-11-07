## godot --headless --path . -s tests/graphed_test.gd     (L84, ROADMAP_400 track L: L03 weighted tangents + buffer curves + snapshot compare; L12 modifiers)
## Builds on PartKeys (handles with a length in time = the weight; modifiers noise / stepped / limits / cycles), adds
## PartKeys.weight_of / set_weight (weight 1.0 = the default handle, a third of the segment), CurveBuffer (snapshot, swap, compare, ghost)
## and the agent tool `curve_graph` (CurveGraphServe). A stub main node gives the tool a Scene and an undo list.
## Keys: right forearm, 4 keys at 0, 1, 2, 3 s, bend 0 / 40 / 10 / 70, side and twist moving too.
##   1 WEIGHT 1.0   set_weight(1.0) on any handle: every sample of the whole curve byte-identical (var_to_str) to before
##   2 WEIGHT 2.0   out handle of key 1: the curve inside segment 1 moves (> 0.05 deg), every key value byte-identical, segments 0 and 2
##                  byte-identical samples, weight_of reads 2.0 back (<= 1e-6); a huge weight clamps to the segment (3.0) and x(u) never runs back
##   3 BUFFER       snapshot, then edit (weight + a move + a modifier), swap: live == the snapshot string exactly; swap again: the edit exactly;
##                  compare of equal curves is exactly 0, after an edit equals an independent brute force (<= 1e-9)
##   4 CYCLES       closed loop (first = last): v(t + P) == v(t) <= 1e-6 for k = -2..3, seam jump <= 1e-4; "offset" mode unequal ends: seam jump <= 1e-4
##   5 STEPPED      the value between two step instants is exactly the value at the step start (0 difference over every frame)
##   6 NOISE        same seed twice: identical; other seed: different; |offset| <= strength / 2 (depth 2 too); strength 0: curve exactly the bare keys
##   7 LIMITS       clamped into min..max, never outside, over 500 samples
##   8 NON-DESTRUCTIVE  all four modifiers added through the tool then removed: the part-key data is byte-identical var_to_str to the start
##   9 UNDO         weight / swap / mod / unmod each add exactly ONE undo step on the stub; snapshot / compare / read add none
##  10 SAVE         Scene.to_dict -> JSON -> from_dict: weighted handles and the stack sample the same (<= 0.02 deg, the file keeps 0.01); an old scene
##                  (no weights, no mods) writes neither
##  11 TOOL         "curve_graph" in AgentTools.MCP_EXTRA and tools/mcp/poser_mcp.py (MATH_TOOLS and the table)
extends SceneTree

var fails := 0
const J := "lowerarm_r"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func keys() -> Array:
	return [{"t": 0.0, "v": Vector3(0, 4, -6)}, {"t": 1.0, "v": Vector3(40, 10, 2)}, {"t": 2.0, "v": Vector3(10, -8, 5)}, {"t": 3.0, "v": Vector3(70, 0, -6)}]


func samples(ks: Array, t0: float, t1: float, n: int) -> Array:
	var o := []
	for i in n + 1:
		o.append(PartKeys.value_at(ks, t0 + (t1 - t0) * float(i) / float(n)))
	return o


func call_tool(m: Node, p: Dictionary) -> Dictionary:
	return CurveGraphServe.serve(m, p)


func _mx(v: Vector3) -> float:
	return maxf(absf(v.x), maxf(absf(v.y), absf(v.z)))


func _init() -> void:
	var stub_src := "extends Node\nvar S\nvar undo := []\nfunc _push_undo() -> void:\n\tundo.append(var_to_str(S.part_keys))\n"
	var gs := GDScript.new()
	gs.source_code = stub_src
	gs.reload()
	var m: Node = gs.new()
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var S := Scene.new()
	S.add("a", B.to_dict())
	S.part_keys = {J: keys()}
	m.S = S
	var pk: Dictionary = S.part_keys
	# 1 weight 1.0
	var before_all := var_to_str(samples(pk[J], 0.0, 3.0, 300))
	var r1 := true
	for ki in [1, 2]:
		for side in ["in", "out"]:
			r1 = r1 and PartKeys.set_weight(pk, J, ki, side, 1.0)
	var after_all := var_to_str(samples(pk[J], 0.0, 3.0, 300))
	ok(r1 and before_all == after_all, "1 weight 1.0 on four handles: all 301 samples byte-identical to the unweighted curve (%d chars)" % before_all.length())
	pk = {J: keys()}
	m.S.part_keys = pk
	# 2 weight 2.0
	var s0 := samples(pk[J], 0.0, 1.0, 100)
	var s1 := samples(pk[J], 1.0, 2.0, 100)
	var s2 := samples(pk[J], 2.0, 3.0, 100)
	var kv0 := var_to_str((pk[J] as Array).map(func(k): return [k["t"], k["v"]]))
	var w_before := PartKeys.weight_of(pk[J], 1, "out")
	var okw := PartKeys.set_weight(pk, J, 1, "out", 2.0)
	var n0 := samples(pk[J], 0.0, 1.0, 100)
	var n1 := samples(pk[J], 1.0, 2.0, 100)
	var n2 := samples(pk[J], 2.0, 3.0, 100)
	var moved := 0.0
	for i in n1.size():
		moved = maxf(moved, (n1[i] - s1[i]).length())
	var kv1 := var_to_str((pk[J] as Array).map(func(k): return [k["t"], k["v"]]))
	var w_after := PartKeys.weight_of(pk[J], 1, "out")
	ok(okw and moved > 0.05 and kv0 == kv1 and var_to_str(n0) == var_to_str(s0) and var_to_str(n2) == var_to_str(s2) and absf(w_after - 2.0) <= 1e-6 and absf(w_before - 1.0) <= 1e-6,
		"2 weight 2.0 on key 1 out: segment moved %.4f deg (> 0.05), key values identical %s, segments 0 and 2 byte-identical %s %s, weight %.6f -> %.6f" % [moved, kv0 == kv1, var_to_str(n0) == var_to_str(s0), var_to_str(n2) == var_to_str(s2), w_before, w_after])
	PartKeys.set_weight(pk, J, 1, "out", 99.0)
	var wmax := PartKeys.weight_of(pk[J], 1, "out")
	var xs_ok := true
	var xp := -1.0
	for i in 101:
		var x := PartKeys.bezier_x(pk[J], 1, float(i) / 100.0)
		xs_ok = xs_ok and x >= xp - 1e-12
		xp = x
	ok(absf(wmax - 3.0) <= 1e-6 and xs_ok, "   a weight of 99 clamps to %.6f (the whole segment = 3.0) and x(u) never runs back in time %s" % [wmax, xs_ok])
	# 3 buffer
	pk = {J: keys()}
	m.S.part_keys = pk
	var snapstr := var_to_str(pk[J])
	var slot := CurveBuffer.snapshot(pk, J)
	var eq0 := CurveBuffer.compare(pk, J, slot)
	PartKeys.set_weight(pk, J, 2, "in", 1.8)
	PartKeys.add_mod(pk, J, {"type": "limits", "ch": 0, "min": 5.0, "max": 50.0, "mix": 1.0})
	PartKeys.put(pk, J, 1.0, Vector3(55, 10, 2))
	var edited := var_to_str(pk[J])
	var cmp := CurveBuffer.compare(pk, J, slot)
	var worst := 0.0
	var snap_keys: Array = CurveBuffer.keys_of(slot, J)
	for i in 301:
		var t := 3.0 * float(i) / 300.0
		worst = maxf(worst, _mx(PartKeys.value_at(pk[J], t) - PartKeys.value_at(snap_keys, t)))
	CurveBuffer.swap(pk, J, slot)
	var back_ok := var_to_str(pk[J]) == snapstr
	CurveBuffer.swap(pk, J, slot)
	var fwd_ok := var_to_str(pk[J]) == edited
	ok(eq0["max"] == 0.0 and back_ok and fwd_ok and cmp["max"] > 1.0 and absf(float(cmp["max"]) - worst) <= 1e-9,
		"3 buffer: equal compare max %.9f (bar exactly 0); edit then swap restores the snapshot exactly %s, swap again the edit exactly %s; compare after edit max %.4f deg vs brute force %.4f (diff %.2e)" % [eq0["max"], back_ok, fwd_ok, cmp["max"], worst, absf(float(cmp["max"]) - worst)])
	# 4 cycles
	var loop := [{"t": 0.0, "v": Vector3(10, 0, 0)}, {"t": 0.5, "v": Vector3(50, 0, 0)}, {"t": 1.0, "v": Vector3(10, 0, 0)}]
	var pc := {J: loop.duplicate(true)}
	PartKeys.add_mod(pc, J, {"type": "cycles", "ch": -1, "before": "repeat", "after": "repeat", "before_n": 0, "after_n": 0, "mix": 1.0})
	var per := 0.0
	for k in range(-2, 4):
		for i in 21:
			var t := float(i) / 20.0 * 0.99
			per = maxf(per, _mx(PartKeys.value_at(pc[J], t + float(k)) - PartKeys.value_at(pc[J], t)))
	var seam := _mx(PartKeys.value_at(pc[J], 1.0 - 1e-7) - PartKeys.value_at(pc[J], 1.0 + 1e-7))
	var po := {J: [{"t": 0.0, "v": Vector3(0, 0, 0)}, {"t": 1.0, "v": Vector3(30, 0, 0)}]}
	PartKeys.add_mod(po, J, {"type": "cycles", "ch": -1, "before": "offset", "after": "offset", "before_n": 0, "after_n": 0, "mix": 1.0})
	var seam_o := _mx(PartKeys.value_at(po[J], 1.0 - 1e-7) - PartKeys.value_at(po[J], 1.0 + 1e-7))
	var lap2 := absf(PartKeys.value_at(po[J], 2.5).x - (PartKeys.value_at(po[J], 0.5).x + 60.0))
	ok(per <= 1e-6 and seam <= 1e-4 and seam_o <= 1e-4 and lap2 <= 1e-6, "4 cycles: period error %.2e (<= 1e-6), seam jump closed loop %.2e and offset mode %.2e (<= 1e-4), offset lap 2 error %.2e" % [per, seam, seam_o, lap2])
	# 5 stepped
	var ps := {J: keys()}
	PartKeys.add_mod(ps, J, {"type": "stepped", "step": 0.25, "offset": 0.0, "mix": 1.0})
	var w5 := 0.0
	var flat := true
	for f in range(0, 91):
		var t := float(f) / 30.0
		var st := floorf(t / 0.25 + 1e-9) * 0.25
		w5 = maxf(w5, _mx(PartKeys.value_at(ps[J], t) - PartKeys.at(ps[J], st)))
		flat = flat and PartKeys.value_at(ps[J], st + 0.01) == PartKeys.value_at(ps[J], st + 0.24)
	ok(w5 == 0.0 and flat, "5 stepped 0.25 s: worst |value - at(step start)| over 91 frames %.9f (bar exactly 0), flat between instants %s" % [w5, flat])
	# 6 noise
	var nm := {"type": "noise", "ch": -1, "strength": 6.0, "scale": 0.3, "phase": 0.0, "seed": 7, "depth": 2, "mix": 1.0}
	var pn := {J: keys()}
	PartKeys.add_mod(pn, J, nm)
	var again := {J: keys()}
	PartKeys.add_mod(again, J, nm)
	var nm2 := nm.duplicate()
	nm2["seed"] = 8
	var other := {J: keys()}
	PartKeys.add_mod(other, J, nm2)
	var nm0 := nm.duplicate()
	nm0["strength"] = 0.0
	var zero := {J: keys()}
	PartKeys.add_mod(zero, J, nm0)
	var amp := 0.0
	var diff_seed := 0.0
	var z0 := 0.0
	for i in 501:
		var t := 3.0 * float(i) / 500.0
		amp = maxf(amp, _mx(PartKeys.value_at(pn[J], t) - PartKeys.at(pn[J], t)))
		diff_seed = maxf(diff_seed, _mx(PartKeys.value_at(pn[J], t) - PartKeys.value_at(other[J], t)))
		z0 = maxf(z0, _mx(PartKeys.value_at(zero[J], t) - PartKeys.at(zero[J], t)))
	ok(var_to_str(samples(pn[J], 0.0, 3.0, 500)) == var_to_str(samples(again[J], 0.0, 3.0, 500)) and amp <= 3.0 + 1e-9 and amp > 0.5 and diff_seed > 0.3 and z0 == 0.0,
		"6 noise: same seed identical, peak %.4f deg <= 3.0 (strength 6), other seed differs by %.3f, strength 0 error %.9f (bar exactly 0)" % [amp, diff_seed, z0])
	# 7 limits
	var pl := {J: keys()}
	PartKeys.add_mod(pl, J, {"type": "limits", "ch": 0, "min": 5.0, "max": 45.0, "mix": 1.0})
	var over := 0.0
	var touched := false
	for i in 501:
		var v: Vector3 = PartKeys.value_at(pl[J], 3.0 * float(i) / 500.0)
		over = maxf(over, maxf(v.x - 45.0, 5.0 - v.x))
		touched = touched or absf(v.x - 45.0) < 1e-9 or absf(v.x - 5.0) < 1e-9
	ok(over <= 0.0 and touched, "7 limits 5..45: worst excursion outside %.9f (bar <= 0), the clamp is reached %s" % [over, touched])
	# 8 and 9: the tool, non-destructive and undo steps
	pk = {J: keys()}
	m.S.part_keys = pk
	m.undo.clear()
	var base := var_to_str(pk)
	var steps := []
	var u := func(p: Dictionary) -> Dictionary:
		var n0u: int = m.undo.size()
		var r := call_tool(m, p)
		steps.append([String(p["action"]), m.undo.size() - n0u, r["ok"]])
		return r
	u.call({"action": "read", "joint": J})
	var sn: Dictionary = u.call({"action": "snapshot", "joint": J})
	u.call({"action": "compare", "joint": J, "slot": 0})
	u.call({"action": "weight", "joint": J, "key": 1, "side": "out", "weight": 1.5})
	u.call({"action": "mod", "joint": J, "type": "cycles"})
	u.call({"action": "mod", "joint": J, "type": "noise", "strength": 4.0, "seed": 3})
	u.call({"action": "mod", "joint": J, "type": "stepped", "step": 0.1})
	u.call({"action": "mod", "joint": J, "type": "limits", "min": 0.0, "max": 60.0})
	var nmods := PartKeys.mods_of(pk[J]).size()
	for i in 4:
		u.call({"action": "unmod", "joint": J, "index": 0})
	ok(nmods == 4 and PartKeys.mods_of(pk[J]).is_empty() and sn["ok"], "8 four modifiers added through the tool (stack %d), then all removed: stack empty %s" % [nmods, PartKeys.mods_of(pk[J]).is_empty()])
	var swapr: Dictionary = u.call({"action": "swap", "joint": J, "slot": 0})
	var bad := []
	for s in steps:
		var want := 0 if s[0] in ["read", "snapshot", "compare"] else 1
		if s[1] != want or not s[2]:
			bad.append(s)
	ok(bad.is_empty() and swapr["ok"], "9 undo: %d tool calls, each edit exactly 1 step and each read / snapshot / compare 0 (violations: %s)" % [steps.size(), bad])
	ok(var_to_str(pk) == base, "8b the swap brought back the snapshot taken before every edit: part-key data byte-identical to the start (%d chars)" % base.length())
	pk = {J: keys()}
	m.S.part_keys = pk
	var b2 := var_to_str(pk)
	for ty in ["cycles", "noise", "stepped", "limits"]:
		call_tool(m, {"action": "mod", "joint": J, "type": ty})
	for i in 4:
		call_tool(m, {"action": "unmod", "joint": J, "index": 0})
	ok(var_to_str(pk) == b2, "8c add four, remove four: var_to_str(part_keys) byte-identical to before")
	# 10 save
	pk = {J: keys()}
	m.S.part_keys = pk
	var plain := JSON.stringify(S.to_dict(B))
	var legacy_ok := not plain.contains("wout") and not plain.contains("mods")
	PartKeys.set_weight(pk, J, 1, "out", 2.0)
	PartKeys.set_weight(pk, J, 2, "in", 0.5)
	PartKeys.add_mod(pk, J, {"type": "limits", "ch": 0, "min": 5.0, "max": 60.0, "mix": 1.0})
	var js := JSON.stringify(S.to_dict(B))
	var S2 := Scene.new()
	S2.from_dict(JSON.parse_string(js))
	var w10 := 0.0
	for i in 301:
		var t := 3.0 * float(i) / 300.0
		w10 = maxf(w10, _mx(PartKeys.value_at(pk[J], t) - PartKeys.value_at(S2.part_keys[J], t)))
	ok(legacy_ok and js.contains("wout") and w10 <= 0.02, "10 save/reload: weights and stack come back, worst %.5f deg (<= 0.02, the file keeps 0.01); a scene without weights or mods writes neither (%s)" % [w10, legacy_ok])
	# 11 tool registered
	var at_src := FileAccess.get_file_as_string("res://scripts/agent_tools.gd")
	var py_src := FileAccess.get_file_as_string("res://tools/mcp/poser_mcp.py")
	ok(at_src.contains("\"curve_graph\"") and py_src.contains("\"curve_graph\""), "11 curve_graph is in AgentTools and the MCP server")
	var bad_in := call_tool(m, {"action": "weight", "joint": J, "key": 9, "side": "out", "weight": 1.0})
	ok(not bad_in["ok"] and not call_tool(m, {"action": "zzz"})["ok"], "   a bad key and an unknown action are refused with a message")
	print("GRAPHED TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
