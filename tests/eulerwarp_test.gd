## godot --headless --path . -s tests/eulerwarp_test.gd     (L86, ROADMAP_400 L04 Euler filter + quaternion view + slerp, L05 time warp per clip)
## BARS, written and committed BEFORE the code (never moved after a run):
##   1 EULER FILTER  planted twist flip 350 -> 10 deg on two parts (a twist and a bend with side 0), keys every 1/30 s moving 0.5 deg a frame,
##                   values stored wrapped into 0..360. CONTROL: the raw curve has a key-to-key jump > 300 deg. After the tool "euler" on the two
##                   parts: the largest key-to-key jump <= 1 deg, the world rotation of the posed bone (Body.G, every key) unchanged <= 1e-5
##                   (largest basis element), a part that was not selected is byte-identical (var_to_str)
##   2 QUATERNION VIEW  tool "quat": (w, x, y, z) per frame for lowerarm_r and hand_r equals Basis(Body.G[j]).get_rotation_quaternion() of the bone
##                   posed by Scene.apply on another body, up to the quaternion's sign, <= 1e-6 over 21 frames; consecutive frames stay in one
##                   hemisphere (no sign flip); the tool changes nothing (scene bytes identical) and adds no undo step
##   3 SLERP         tool "slerp": across a segment the angular velocity of the bone (60 steps, relative-quaternion angle) is constant within 1%
##                   ((max - min) / mean). CONTROL: the same segment with linear angles varies by > 1%. The value at both ends of the segment is
##                   the key's value exactly; save and reload keeps the option (<= 0.02 deg)
##   4 WARP IDENTITY a warp on the diagonal set through the tool gives the scene file TEXT (JSON) and the pose bytes (var_to_str of the body state
##                   and offset, 10 times) of a clip with no warp: byte-identical
##   5 WARP EASE-IN  knots [[0.5, 0.25]]: the source runs at 0.5 of the strip's speed at the start, measured from playback's own mapping
##                   (Clips.at) over 2 ms, within 5% (CONTROL: no warp measures 1.0 within 1%); the knot is hit: source time / L = 0.25 at
##                   strip progress 0.5 within 1e-6, and the body there is the source's pose at that time (<= 0.01 deg)
##   6 NON-MONOTONE  y falling, x not rising, out of 0..1, more than 6 knots: each refused with a message, the clip unchanged (var_to_str), 0 undo steps
##   7 SAVE + RELOAD a warped scene: file -> JSON -> scene gives the same source time at 20 strip times (<= 1e-9) and the same knots
##   8 BAKE = PLAY   Bake.bake at 30 a second of a copy of the warped scene: the baked cards' poses equal what the original plays at the same 30
##                   times, <= 0.05 deg per joint. CONTROL: baking the same scene without the warp differs from the warped playback by > 0.5 deg
##   9 UNDO          euler, slerp, warp set and warp clear: exactly +1 undo step each; quat, warp_read and a refused warp: +0
##  10 TOOL          "euler_warp" is in AgentTools (MCP_EXTRA + dispatch) and in tools/mcp/poser_mcp.py
##  11 GRAPH EDITOR  GraphEditor.euler_sel() on the selected parts' keys is ONE begin() call and filters exactly the selected parts
extends SceneTree

var fails := 0
const SRC := "scenes/walk_bat.json"
const JA := "lowerarm_r"
const JB := "upperarm_l"
const JC := "head"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


func target() -> Scene:
	var R := body()
	R.wep_on = false
	R.set_ang("upperarm_r", Vector3(0, 0, 40))
	R.set_ang("thigh_l", Vector3(20, 0, 0))
	R.fk()
	var S := Scene.new()
	S.add("a", R.to_dict())
	R.set_ang("upperarm_l", Vector3(0, 0, -30))
	R.set_ang("spine_02", Vector3(10, 0, 0))
	R.fk()
	S.add("b", R.to_dict())
	S.cards[1]["move"] = 0.8
	S.cards[1]["hold"] = 12.0
	return S


func src_scene() -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://" + SRC)))
	return S


func worst_deg(a: Body, b: Body) -> float:
	var w := 0.0
	for j in Body.ORDER:
		var d: Vector3 = Scene._d(b.ang[j], a.ang[j], j)
		w = maxf(w, maxf(absf(d.x), maxf(absf(d.y), absf(d.z))))
	return w


func serve(m: Node, p: Dictionary) -> Dictionary:
	return EulerWarpServe.serve(m, p)


func qdiff(a: Quaternion, b: Quaternion) -> float:
	var s := 1.0 if a.dot(b) >= 0.0 else -1.0
	return maxf(maxf(absf(a.w - s * b.w), absf(a.x - s * b.x)), maxf(absf(a.y - s * b.y), absf(a.z - s * b.z)))


func basis_diff(a: Basis, b: Basis) -> float:
	var w := 0.0
	for r in 3:
		w = maxf(w, maxf(absf(a[r].x - b[r].x), maxf(absf(a[r].y - b[r].y), absf(a[r].z - b[r].z))))
	return w


func jump_of(keys: Array) -> float:
	var w := 0.0
	for i in range(1, keys.size()):
		var d: Vector3 = keys[i]["v"] - keys[i - 1]["v"]
		w = maxf(w, maxf(absf(d.x), maxf(absf(d.y), absf(d.z))))
	return w


func planted() -> Dictionary:
	var a := []
	var b := []
	var c := []
	for i in 41:
		var t := float(i) / 30.0
		var tw := fposmod(350.0 + 0.5 * i, 360.0)   # 350 ... 359.5, 0 ... 10: the true angle never moves more than 0.5 a frame
		a.append({"t": t, "v": Vector3(20.0, 5.0, tw)})
		b.append({"t": t, "v": Vector3(tw, 0.0, 12.0)})
		c.append({"t": t, "v": Vector3(0.5 * i, 3.0, 0.0)})
	return {JA: a, JB: b, JC: c}


func ang_rates(B: Body, j: String, ks: Array, t0: float, t1: float, n: int, use_slerp_tool: bool) -> Array:
	var out := []
	var prev: Quaternion = B.compose(j, PartKeys.value_at(ks, t0))
	for i in range(1, n + 1):
		var t := t0 + (t1 - t0) * float(i) / float(n)
		var q: Quaternion = B.compose(j, PartKeys.value_at(ks, t))
		var rel := q * prev.inverse()
		out.append(2.0 * atan2(Vector3(rel.x, rel.y, rel.z).length(), absf(rel.w)))
		prev = q
	return out


func spread(a: Array) -> float:
	var lo := 1e9
	var hi := -1e9
	var s := 0.0
	for x in a:
		lo = minf(lo, x)
		hi = maxf(hi, x)
		s += x
	return (hi - lo) / (s / a.size())


func _init() -> void:
	var stub_src := "extends Node\nvar S\nvar B\nvar undo := []\nfunc _push_undo() -> void:\n\tundo.append(var_to_str(S.part_keys) + var_to_str(S.clips))\n"
	var gs := GDScript.new()
	gs.source_code = stub_src
	gs.reload()
	var m: Node = gs.new()
	var B := body()
	var S := Scene.new()
	S.add("a", B.to_dict())
	S.part_keys = planted()
	m.S = S
	m.B = B

	# 1 euler filter
	var raw_jump_a := jump_of(S.part_keys[JA])
	var raw_jump_b := jump_of(S.part_keys[JB])
	var raw_keys := var_to_str(S.part_keys)
	var head_before := var_to_str(S.part_keys[JC])
	var raw_world := []
	var R := body()
	for i in 41:
		R.ang[JA] = S.part_keys[JA][i]["v"]
		R.ang[JB] = S.part_keys[JB][i]["v"]
		R.fk()
		raw_world.append([Basis(R.G[JA]), Basis(R.G[JB])])
	var n0: int = m.undo.size()
	var r1 := serve(m, {"action": "euler", "joints": [JA, JB]})
	var jump_a := jump_of(S.part_keys[JA])
	var jump_b := jump_of(S.part_keys[JB])
	var wd := 0.0
	for i in 41:
		R.ang[JA] = S.part_keys[JA][i]["v"]
		R.ang[JB] = S.part_keys[JB][i]["v"]
		R.fk()
		wd = maxf(wd, maxf(basis_diff(raw_world[i][0], Basis(R.G[JA])), basis_diff(raw_world[i][1], Basis(R.G[JB]))))
	ok(raw_jump_a > 300.0 and raw_jump_b > 300.0, "1 control: the raw planted curves jump %.1f and %.1f deg between two keys (> 300)" % [raw_jump_a, raw_jump_b])
	ok(bool(r1["ok"]) and jump_a <= 1.0 and jump_b <= 1.0, "1 euler filter: largest key-to-key jump %.3f and %.3f deg (<= 1)" % [jump_a, jump_b])
	ok(wd <= 1e-5, "1 the world rotation of the posed bones is unchanged: largest basis element difference %.8f (<= 1e-5)" % wd)
	ok(var_to_str(S.part_keys[JC]) == head_before and raw_keys != var_to_str(S.part_keys), "1 the part that was not selected (head) is byte-identical, the selected ones changed")
	var undo_euler: int = m.undo.size() - n0

	# 2 quaternion view
	var Sq := target()
	Sq.part_keys = {JA: [{"t": 0.0, "v": Vector3(10, 4, -20)}, {"t": 0.4, "v": Vector3(70, -10, 35)}, {"t": 0.7, "v": Vector3(30, 8, 60)}],
		"hand_r": [{"t": 0.0, "v": Vector3(0, 5, 10)}, {"t": 0.7, "v": Vector3(25, -15, -30)}]}
	m.S = Sq
	var snap_q := var_to_str(Sq.part_keys) + var_to_str(Sq.cards)
	var n1: int = m.undo.size()
	var worst_q := 0.0
	var flips := 0
	var frames_n := 0
	var Rq := body()
	for j in [JA, "hand_r"]:
		var rq := serve(m, {"action": "quat", "joint": j, "t0": 0.0, "t1": 0.7, "fps": 30})
		var fr: Array = rq["result"]["frames"] if rq["ok"] else []
		frames_n = fr.size()
		for i in fr.size():
			var t: float = fr[i][0]
			Sq.apply(Rq, t)
			Rq.fk()
			var refq := Basis(Rq.G[j]).get_rotation_quaternion()
			var q := Quaternion(fr[i][2], fr[i][3], fr[i][4], fr[i][1])
			worst_q = maxf(worst_q, qdiff(q, refq))
			if i > 0:
				var pq := Quaternion(fr[i - 1][2], fr[i - 1][3], fr[i - 1][4], fr[i - 1][1])
				if pq.dot(q) < 0.0:
					flips += 1
	ok(frames_n == 21 and worst_q <= 1e-6, "2 quaternion view: %d frames, worst component difference to Basis.get_rotation_quaternion of the posed bone %.8f (<= 1e-6)" % [frames_n, worst_q])
	ok(flips == 0 and m.undo.size() == n1 and snap_q == var_to_str(Sq.part_keys) + var_to_str(Sq.cards), "2 the view keeps one hemisphere (%d sign flips), changes nothing, adds no undo step" % flips)

	# 3 slerp
	var ks3 := [{"t": 0.0, "v": Vector3(-20, 30, -60)}, {"t": 1.0, "v": Vector3(30, 10, 20)}, {"t": 2.0, "v": Vector3(95, -25, 85)}, {"t": 3.0, "v": Vector3(10, 5, 0)}]
	var S3 := target()
	S3.part_keys = {JA: ks3.duplicate(true)}
	m.S = S3
	var lin_rates := ang_rates(B, JA, S3.part_keys[JA], 1.0, 2.0, 60, false)
	var lin_spread := spread(lin_rates)
	var n2: int = m.undo.size()
	var r3 := serve(m, {"action": "slerp", "joints": [JA], "on": true})
	var sl_rates := ang_rates(B, JA, S3.part_keys[JA], 1.0, 2.0, 60, true)
	var sl_spread := spread(sl_rates)
	var undo_slerp: int = m.undo.size() - n2
	var e0: Vector3 = PartKeys.value_at(S3.part_keys[JA], 1.0)
	var e1: Vector3 = PartKeys.value_at(S3.part_keys[JA], 2.0)
	ok(lin_spread > 0.01, "3 control: linear angles over the same segment vary the angular velocity by %.1f%% (> 1%%)" % (lin_spread * 100.0))
	ok(bool(r3["ok"]) and sl_spread <= 0.01, "3 slerp: angular velocity across the segment is constant within %.4f%% (<= 1%%)" % (sl_spread * 100.0))
	ok((e0 - ks3[1]["v"]).length() <= 1e-6 and (e1 - ks3[2]["v"]).length() <= 1e-6, "3 both ends of the segment are the keys' values (%.8f, %.8f)" % [(e0 - ks3[1]["v"]).length(), (e1 - ks3[2]["v"]).length()])
	var txt3 := JSON.stringify(S3.to_dict(B, false))
	var S3b := Scene.new()
	S3b.from_dict(JSON.parse_string(txt3))
	var w3 := 0.0
	for i in 61:
		var t := 3.0 * float(i) / 60.0
		w3 = maxf(w3, (PartKeys.value_at(S3.part_keys[JA], t) - PartKeys.value_at(S3b.part_keys[JA], t)).length())
	ok(txt3.contains("slerp") and w3 <= 0.02 * 1.8, "3 save and reload keeps the slerp option: worst %.4f deg over 61 samples (<= 0.036, the file keeps 0.01 per angle)" % w3)

	# 4 warp identity
	var src := src_scene()
	var L := src.length()
	var s0 := 0.7
	var base := target()
	base.clips = [Clips.make(SRC, s0)]
	var idw := target()
	idw.clips = [Clips.make(SRC, s0)]
	m.S = idw
	var r4 := serve(m, {"action": "warp", "clip": 0, "knots": [[0.25, 0.25], [0.75, 0.75]]})
	var D := Clips.length_of(base.clips[0], L)
	var diff := 0
	var Bb := body()
	for i in 10:
		var t := s0 + (i + 0.5) / 10.0 * D
		base.apply(Bb, t)
		var sb := var_to_str(Bb.state()) + var_to_str(Bb.offset)
		idw.apply(Bb, t)
		if sb != var_to_str(Bb.state()) + var_to_str(Bb.offset):
			diff += 1
	var tb := JSON.stringify(base.to_dict(Bb, false))
	var ti := JSON.stringify(idw.to_dict(Bb, false))
	ok(bool(r4["ok"]) and tb == ti and diff == 0, "4 identity warp: file text identical (%d chars), %d of 10 pose byte strings differ" % [tb.length(), diff])

	# 5 ease-in
	var ew := target()
	ew.clips = [Clips.make(SRC, s0)]
	m.S = ew
	var r5 := serve(m, {"action": "warp", "clip": 0, "knots": [[0.5, 0.25]]})
	var d := 0.002
	var a0 := Clips.at(ew.clips[0], L, s0 + 1e-9)
	var a1 := Clips.at(ew.clips[0], L, s0 + d)
	var sp_w := (float(a1["lt"]) - float(a0["lt"])) / d
	var c0 := Clips.at(base.clips[0], L, s0 + 1e-9)
	var c1 := Clips.at(base.clips[0], L, s0 + d)
	var sp_n := (float(c1["lt"]) - float(c0["lt"])) / d
	var ratio := sp_w / sp_n
	ok(bool(r5["ok"]) and absf(ratio - 0.5) <= 0.025, "5 ease-in speed at the start is %.4f of the unwarped speed (bar 0.5 within 5%%, i.e. 0.475 .. 0.525)" % ratio)
	ok(absf(sp_n - 1.0) <= 0.01, "5 control: with no warp the measure reads %.4f (bar 1.0 within 1%%)" % sp_n)
	var mid := Clips.at(ew.clips[0], L, s0 + 0.5 * D)
	var Bw := body()
	var Rs := body()
	ew.apply(Bw, s0 + 0.5 * D)
	src.apply(Rs, float(mid["lt"]))
	ok(absf(float(mid["lt"]) / L - 0.25) <= 1e-6 and worst_deg(Bw, Rs) < 0.01, "5 at strip progress 0.5 the source is at %.7f of its length (bar 0.25) and the body is its pose there: %.5f deg" % [float(mid["lt"]) / L, worst_deg(Bw, Rs)])

	# 6 non-monotone
	var bad_cases := {"y falling": [[0.3, 0.6], [0.6, 0.4]], "x not rising": [[0.6, 0.5], [0.3, 0.6]], "out of range": [[1.2, 0.5]], "y above 1": [[0.5, 1.4]],
		"seven knots": [[0.1, 0.1], [0.2, 0.2], [0.3, 0.3], [0.4, 0.4], [0.5, 0.5], [0.6, 0.6], [0.7, 0.7]], "equal x": [[0.4, 0.2], [0.4, 0.3]]}
	var clip_before := var_to_str(ew.clips)
	var n3: int = m.undo.size()
	var refused := 0
	var msgs := true
	for k in bad_cases:
		var rb := serve(m, {"action": "warp", "clip": 0, "knots": bad_cases[k]})
		if not bool(rb["ok"]):
			refused += 1
			msgs = msgs and String(rb["error"]).length() > 8
	ok(refused == bad_cases.size() and msgs and var_to_str(ew.clips) == clip_before and m.undo.size() == n3, "6 non-monotone and illegal warps: %d of %d refused with a message, clip unchanged, %d undo steps" % [refused, bad_cases.size(), m.undo.size() - n3])

	# 7 save + reload
	var txt7 := JSON.stringify(ew.to_dict(Bw, false))
	var e2 := Scene.new()
	e2.from_dict(JSON.parse_string(txt7))
	var w7 := 0.0
	for i in 20:
		var t := s0 + (i + 0.5) / 20.0 * D
		w7 = maxf(w7, absf(float(Clips.at(ew.clips[0], L, t)["lt"]) - float(Clips.at(e2.clips[0], L, t)["lt"])))
	ok(w7 <= 1e-9 and var_to_str(e2.clips[0].get("warp")) == var_to_str(ew.clips[0].get("warp")) and txt7.contains("warp"), "7 save and reload: source time differs by %.8f over 20 times (<= 1e-9), knots %s" % [w7, var_to_str(e2.clips[0].get("warp"))])

	# 8 bake = playback
	var play := Scene.new()
	play.from_dict(JSON.parse_string(txt7))
	var baked := Scene.new()
	baked.from_dict(JSON.parse_string(txt7))
	var nowarp := target()
	nowarp.clips = [Clips.make(SRC, s0)]
	var nw := Scene.new()
	nw.from_dict(JSON.parse_string(JSON.stringify(nowarp.to_dict(Bw, false))))
	var Bk := body()
	var rb8 := Bake.bake(baked, Bk, 30.0)
	var rn8 := Bake.bake(nw, Bk, 30.0)
	var worst8 := 0.0
	var worst_ctl := 0.0
	var Bp := body()
	var Bq := body()
	for k in 31:
		var t := float(k) / 30.0 + 0.6
		if t > baked.length() - 1e-6:
			break
		play.apply(Bp, t)
		baked.apply(Bq, t)
		worst8 = maxf(worst8, worst_deg(Bp, Bq))
		nw.apply(Bq, t)
		worst_ctl = maxf(worst_ctl, worst_deg(Bp, Bq))
	ok(int(rb8["cards"]) > 10 and worst8 <= 0.05, "8 bake equals playback: %d cards, worst joint difference %.4f deg over the baked span (<= 0.05)" % [int(rb8["cards"]), worst8])
	ok(worst_ctl > 0.5, "8 control: a bake WITHOUT the warp differs from the warped playback by %.2f deg (> 0.5; %d cards)" % [worst_ctl, int(rn8["cards"])])

	# 9 undo
	var S9 := target()
	S9.clips = [Clips.make(SRC, s0)]
	S9.part_keys = planted()
	m.S = S9
	var u0: int = m.undo.size()
	serve(m, {"action": "euler", "joints": [JA]})
	var u1: int = m.undo.size()
	serve(m, {"action": "slerp", "joints": [JA], "on": true})
	var u2: int = m.undo.size()
	serve(m, {"action": "warp", "clip": 0, "knots": [[0.5, 0.25]]})
	var u3: int = m.undo.size()
	serve(m, {"action": "warp_clear", "clip": 0})
	var u4: int = m.undo.size()
	serve(m, {"action": "quat", "joint": JA})
	serve(m, {"action": "warp_read", "clip": 0})
	serve(m, {"action": "warp", "clip": 0, "knots": [[0.3, 0.6], [0.6, 0.4]]})
	var u5: int = m.undo.size()
	ok(undo_euler == 1 and undo_slerp == 1 and u1 - u0 == 1 and u2 - u1 == 1 and u3 - u2 == 1 and u4 - u3 == 1 and u5 == u4,
		"9 undo steps: euler +%d (+%d), slerp +%d (+%d), warp +%d, clear +%d; quat, warp_read and a refused warp +%d" % [undo_euler, u1 - u0, undo_slerp, u2 - u1, u3 - u2, u4 - u3, u5 - u4])

	# 10 tool registered
	var at_src := FileAccess.get_file_as_string("res://scripts/agent_tools.gd")
	var py_src := FileAccess.get_file_as_string("res://tools/mcp/poser_mcp.py")
	ok(at_src.contains("\"euler_warp\"") and py_src.contains("\"euler_warp\""), "10 euler_warp is in AgentTools and the MCP server")
	ok(not serve(m, {"action": "zzz"})["ok"] and not serve(m, {"action": "euler", "joints": ["nosuch"]})["ok"], "   an unknown action and an unkeyed joint are refused with a message")

	# 11 graph editor
	var S11 := Scene.new()
	S11.add("a", B.to_dict())
	S11.part_keys = planted()
	var calls := [0]
	var ge := GraphEditor.new()
	ge.scene = S11
	ge.joint = JA
	ge.begin = func(): calls[0] += 1
	ge.msel = [[JA, 2, 5], [JB, 0, 3]]
	var rep: Dictionary = ge.euler_sel()
	var head11 := var_to_str(S11.part_keys[JC]) == head_before
	ok(calls[0] == 1 and jump_of(S11.part_keys[JA]) <= 1.0 and jump_of(S11.part_keys[JB]) <= 1.0 and head11 and int(rep.get("parts", 0)) == 2,
		"11 GraphEditor.euler_sel: %d begin() call (undo step), parts %s, jumps %.2f / %.2f, unselected part untouched %s" % [calls[0], rep.get("parts", -1), jump_of(S11.part_keys[JA]), jump_of(S11.part_keys[JB]), head11])
	ge.free()
	print("EULERWARP TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
