## godot --headless --path . -s tests/aucurves_test.gd     (L94, ROADMAP_400 L30: the graph editor for face AU channels with the L84 tools)
## The face AUs (Scene.face = {channel: [{"t", "v": Vector3(x,0,0)}]}, scripts/face.gd) are PartKeys curves, so weights, buffer curves and
## modifiers apply to them. AuCurves (scripts/au_curves.gd) reads one channel as the graph editor draws it: PartKeys.value_at(..).x clamped to
## Face.range_of (0..1, brows and eyes -1..1). The tool is `curve_graph` with {"au": "<channel>"} in place of {"joint"}.
## Shape-key (KMeshShapes) weights are not time-keyed anywhere on this base (L88's tracks are not here), so only the AU channels are graphed.
##   1 READ      curve keyed 0 -> 1: the graph editor's samples == Face.values_at (playback) at 50 samples, <= 1e-6; also with a limits stack on
##   2 WEIGHT    weight 2.0 on key 1 out: segment 1 moves (> 0.01), key values and segments 0 and 2 byte-identical, weight reads 2.0 back (<= 1e-6)
##   3 NOISE     noise on a 0..1 curve: playback and graph never leave 0..1 (500 samples); stepped: error vs at(step start) exactly 0
##   4 BUFFER    snapshot, edit (weight + key + mod), swap: the curve is byte for byte the snapshot; swap again: the edit
##   5 CONTROL   the same noise unclamped (PartKeys.value_at) exceeds 1 and drops below 0, so the clamp is what holds it; a brow keeps -1..1
##   6 UNDO      weight / swap / mod / unmod add exactly ONE undo step each; read / snapshot / compare add none
##   7 SAVE      Scene.to_dict -> JSON -> from_dict: keys, weights, stack identical (var_to_str) and 50 samples <= 1e-6
##   8 EDITOR    CurveEditor in au mode draws the AU's curve (every polyline point = the clamped value) and edits scene.face
extends SceneTree

var fails := 0
const CH := "jaw"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func k4() -> Array:
	return [{"t": 0.0, "v": Vector3(0.0, 0, 0)}, {"t": 1.0, "v": Vector3(0.8, 0, 0)}, {"t": 2.0, "v": Vector3(0.3, 0, 0)}, {"t": 3.0, "v": Vector3(1.0, 0, 0)}]


func k2() -> Array:
	return [{"t": 0.0, "v": Vector3(0.0, 0, 0)}, {"t": 1.0, "v": Vector3(1.0, 0, 0)}]


func seg(face: Dictionary, ch: String, t0: float, t1: float, n: int) -> Array:
	var o := []
	for i in n + 1:
		o.append(AuCurves.value_at(face, ch, t0 + (t1 - t0) * float(i) / float(n)))
	return o


func _init() -> void:
	var gs := GDScript.new()
	gs.source_code = "extends Node\nvar S\nvar undo := []\nfunc _push_undo() -> void:\n\tundo.append(var_to_str(S.face))\n"
	gs.reload()
	var m: Node = gs.new()
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var S := Scene.new()
	S.add("a", B.to_dict())
	m.S = S
	var tool := func(p: Dictionary) -> Dictionary: return CurveGraphServe.serve(m, p)
	# 1 read
	S.face = {CH: k2()}
	var w1 := 0.0
	for stack in [false, true]:
		if stack:
			PartKeys.add_mod(S.face, CH, {"type": "limits", "ch": 0, "min": 0.1, "max": 0.7, "mix": 1.0})
		for i in 50:
			var t := float(i) / 49.0
			w1 = maxf(w1, absf(AuCurves.value_at(S.face, CH, t) - float(Face.values_at(S.face, t)[CH])))
	var mid := AuCurves.value_at(S.face, CH, 0.5)
	ok(w1 <= 1e-6 and absf(mid - 0.5) > 0.01 and mid <= 0.7 + 1e-9, "1 graph == playback at 50 samples (plain and with a limits stack): worst %.8f (<= 1e-6); the stack shows in both (mid %.4f, capped at 0.7)" % [w1, mid])
	# 2 weight
	S.face = {CH: k4()}
	var s0 := seg(S.face, CH, 0.0, 1.0, 100)
	var s1 := seg(S.face, CH, 1.0, 2.0, 100)
	var s2 := seg(S.face, CH, 2.0, 3.0, 100)
	var kv0 := var_to_str((S.face[CH] as Array).map(func(k): return [k["t"], k["v"]]))
	var w_b := PartKeys.weight_of(S.face[CH], 1, "out")
	var r2: Dictionary = tool.call({"action": "weight", "au": CH, "key": 1, "side": "out", "weight": 2.0})
	var n0 := seg(S.face, CH, 0.0, 1.0, 100)
	var n1 := seg(S.face, CH, 1.0, 2.0, 100)
	var n2 := seg(S.face, CH, 2.0, 3.0, 100)
	var moved := 0.0
	for i in n1.size():
		moved = maxf(moved, absf(n1[i] - s1[i]))
	var kv1 := var_to_str((S.face[CH] as Array).map(func(k): return [k["t"], k["v"]]))
	var w_a := PartKeys.weight_of(S.face[CH], 1, "out")
	ok(r2["ok"] and moved > 0.01 and kv0 == kv1 and var_to_str(n0) == var_to_str(s0) and var_to_str(n2) == var_to_str(s2) and absf(w_a - 2.0) <= 1e-6 and absf(w_b - 1.0) <= 1e-6,
		"2 weight 2.0 on key 1 out: segment moved %.4f, keys identical %s, segments 0 and 2 byte-identical %s %s, weight %.6f -> %.6f" % [moved, kv0 == kv1, var_to_str(n0) == var_to_str(s0), var_to_str(n2) == var_to_str(s2), w_b, w_a])
	# 3 noise, stepped
	S.face = {CH: k2()}
	var r3: Dictionary = tool.call({"action": "mod", "au": CH, "type": "noise", "strength": 0.6, "scale": 0.1, "seed": 3})
	var lo := INF
	var hi := -INF
	var plo := INF
	var phi := -INF
	for i in 501:
		var t := float(i) / 500.0
		var a := AuCurves.value_at(S.face, CH, t)
		var p := float(Face.values_at(S.face, t)[CH])
		lo = minf(lo, minf(a, p))
		hi = maxf(hi, maxf(a, p))
		plo = minf(plo, PartKeys.value_at(S.face[CH], t).x)
		phi = maxf(phi, PartKeys.value_at(S.face[CH], t).x)
	ok(r3["ok"] and lo >= 0.0 and hi <= 1.0 and hi > 0.9, "3 noise strength 0.6 on 0..1: graph and playback stay in [%.4f, %.4f] (inside 0..1)" % [lo, hi])
	# 5 control
	ok(phi > 1.0 and plo < 0.0, "5 CONTROL: the same noise unclamped (PartKeys.value_at) runs %.4f .. %.4f, so the clamp holds it" % [plo, phi])
	S.face = {"brow_l": k2()}
	PartKeys.add_mod(S.face, "brow_l", {"type": "noise", "ch": 0, "strength": 0.6, "scale": 0.1, "phase": 0.0, "seed": 3, "mix": 1.0})
	var blo := INF
	var bhi := -INF
	for i in 501:
		var a := AuCurves.value_at(S.face, "brow_l", float(i) / 500.0)
		blo = minf(blo, a)
		bhi = maxf(bhi, a)
	ok(AuCurves.range_of("brow_l") == Vector2(-1, 1) and blo >= -1.0 and bhi <= 1.0 and blo < 0.0, "   a brow has its own range -1..1: the curve dips to %.4f (below 0 is legal there) and stays in -1..1" % blo)
	S.face = {CH: k4()}
	tool.call({"action": "mod", "au": CH, "type": "stepped", "step": 0.1})
	var w3 := 0.0
	for i in 301:
		var t := 3.0 * float(i) / 300.0
		var st := floorf(t / 0.1 + 1e-9) * 0.1
		w3 = maxf(w3, absf(AuCurves.value_at(S.face, CH, t) - clampf(PartKeys.at(S.face[CH], st).x, 0.0, 1.0)))
	ok(w3 == 0.0, "3 stepped 0.1 s: worst |graph - at(step start)| over 301 samples %.9f (bar exactly 0)" % w3)
	# 4 buffer
	S.face = {CH: k4()}
	var snapstr := var_to_str(S.face[CH])
	var sn: Dictionary = tool.call({"action": "snapshot", "au": CH})
	var slot := int(sn["result"]["slot"])
	tool.call({"action": "weight", "au": CH, "key": 2, "side": "in", "weight": 1.8})
	tool.call({"action": "mod", "au": CH, "type": "limits", "ch": 0, "min": 0.2, "max": 0.6})
	PartKeys.put(S.face, CH, 1.0, Vector3(0.55, 0, 0))
	var edited := var_to_str(S.face[CH])
	var cmp: Dictionary = tool.call({"action": "compare", "au": CH, "slot": slot})
	tool.call({"action": "swap", "au": CH, "slot": slot})
	var back := var_to_str(S.face[CH]) == snapstr
	tool.call({"action": "swap", "au": CH, "slot": slot})
	var fwd := var_to_str(S.face[CH]) == edited
	ok(back and fwd and cmp["ok"] and float(cmp["result"]["max_deg"]) > 0.05, "4 buffer: swap restores the snapshot byte for byte %s, swap again the edit %s; compare after the edit max %.4f" % [back, fwd, float(cmp["result"]["max_deg"])])
	# 6 undo
	S.face = {CH: k4()}
	m.undo.clear()
	var steps := []
	tool.call({"action": "read", "au": CH})
	steps.append(m.undo.size())
	var sn2: Dictionary = tool.call({"action": "snapshot", "au": CH})
	tool.call({"action": "compare", "au": CH, "slot": int(sn2["result"]["slot"])})
	steps.append(m.undo.size())
	tool.call({"action": "weight", "au": CH, "key": 1, "side": "out", "weight": 1.5})
	steps.append(m.undo.size())
	tool.call({"action": "swap", "au": CH, "slot": int(sn2["result"]["slot"])})
	steps.append(m.undo.size())
	tool.call({"action": "mod", "au": CH, "type": "noise", "strength": 0.2})
	steps.append(m.undo.size())
	tool.call({"action": "unmod", "au": CH, "index": 0})
	steps.append(m.undo.size())
	ok(steps == [0, 0, 1, 2, 3, 4], "6 undo: read 0, snapshot + compare 0, weight / swap / mod / unmod one step each: counts %s" % str(steps))
	# 7 save
	S.face = {CH: k4(), "blink": k2()}
	PartKeys.set_weight(S.face, CH, 1, "out", 2.0)
	PartKeys.set_weight(S.face, CH, 2, "in", 0.5)
	PartKeys.add_mod(S.face, CH, {"type": "noise", "ch": 0, "strength": 0.25, "scale": 0.2, "phase": 0.0, "seed": 4, "mix": 1.0})
	PartKeys.add_mod(S.face, CH, {"type": "limits", "ch": 0, "min": 0.1, "max": 0.9, "mix": 1.0})
	var S2 := Scene.new()
	S2.from_dict(JSON.parse_string(JSON.stringify(S.to_dict(B))))
	var w7 := 0.0
	for i in 50:
		var t := 3.0 * float(i) / 49.0
		w7 = maxf(w7, absf(AuCurves.value_at(S.face, CH, t) - AuCurves.value_at(S2.face, CH, t)))
	ok(var_to_str(S.face) == var_to_str(S2.face) and w7 <= 1e-6, "7 save/reload: keys, weights and stack identical %s, worst sample error %.8f (<= 1e-6)" % [var_to_str(S.face) == var_to_str(S2.face), w7])
	# 8 editor
	S.face = {CH: k4()}
	PartKeys.add_mod(S.face, CH, {"type": "noise", "ch": 0, "strength": 0.6, "scale": 0.2, "phase": 0.0, "seed": 2, "mix": 1.0})
	var ed := CurveEditor.new()
	ed.scene = S
	ed.au = true
	ed.joint = CH
	ed.size = Vector2(400, 200)
	ed.t0 = 0.0
	ed.t1 = 3.0
	ed.v0 = -0.1
	ed.v1 = 1.1
	var pl := ed.polyline(0)
	var wy := 0.0
	for pt in pl:
		wy = maxf(wy, absf(pt.y - ed.cv_to_y(0, AuCurves.value_at(S.face, CH, ed.x_to_t(pt.x)))))
	var inside := true
	for pt in pl:
		inside = inside and ed.y_to_v(pt.y) <= 1.0 + 1e-6 and ed.y_to_v(pt.y) >= -1e-6
	ok(ed.keys() == S.face[CH] and pl.size() > 100 and wy <= 1e-3 and inside, "8 editor au mode: keys() is scene.face[jaw], %d polyline points, worst y error %.8f px (<= 1e-3), all inside 0..1 %s" % [pl.size(), wy, inside])
	print("AUCURVES TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
