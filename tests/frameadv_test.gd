## godot --headless --path . -s tests/frameadv_test.gd     (INNOVATIONS N080: hitstun and frame advantage, scripts/frame_advantage.gd)
## Bars, written before measuring (60 fps; + = the attacker acts first; stun = frames after the contact frame):
##  1 SYNTHETIC, hand-built timings (plain ease, no floor, no pin): the attacker holds 10 f, swings the right arm forward in 3 f,
##    holds 17 f, pulls back in 12 f, holds 3 f (45 f). Its startup 10, active 3, recovery 32, exactly (0 frames off).
##    The hit clip (first card = impact) recoils in 2 f, holds 40 f, snaps back in 1 f: back on clip frame 43, so with the contact
##    on the first active frame (10) the stun end is 53, hitstun 42 and on hit +8; the block clip holds 20 f: stun end 33,
##    blockstun 22, on block -12. All exact.
##  2 PUNISHABLE: -12 on block vs a defender whose fastest move starts in 12 f: NOT punishable (12 > 12 is false); add a move
##    of startup 5: punishable; the fastest startup reported is 5.
##  3 RECOVER 10 F SLOWER (the last card's hold + 10/60 s): recovery +10, on hit and on block each change by exactly -10;
##    the stuns do not change. The same on combo3 (4).
##  4 COMBO3 vs a standing fighter 1.0 m in front, his reaction baked by HitReaction at the first contact: the contact is a real
##    one (from "contact"), hitstun >= 1, and the test's OWN recount agrees exactly: recovery end = the count of combo3's frames,
##    stun end = its own scan (first frame after the peak, back within 2 cm for 3 frames), advantage = stun end - recovery end,
##    hitstun = stun end - contact - 1. The defender is out of guard (> 2 cm) on the frame before the stun end, in on it.
##  5 EXPORT: FrameData.write_json of the exchange's frame data has exchange.{on_hit, on_block, hitstun, blockstun, punishable,
##    recovery_end, contact_f} equal to the numbers; a frame data without an exchange exports with no "exchange" key.
##  6 SERVE: frame_data on combo3 by default has startup/active/recovery and NO "exchange" and no "frames"; with hit_clip and
##    block_clip it has the exchange, equal to of_clips' numbers. An unknown clip path is a -32602 error.
extends SceneTree

var fails := 0
const FPS := 60


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func stand() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b


func posed(j: String, v: Vector3) -> Dictionary:
	var b := stand()
	b.ang[j] = v
	b.fk()
	return b.to_dict()


func plain(cards: Array) -> Scene:
	var s := Scene.new()
	s.from_dict({"scene": "zz_frameadv", "fps": 30, "natural": false, "on_floor": false, "pin": false, "cards": cards})
	return s


func f(n: float) -> float:
	return n / float(FPS)


## the attacker: hold `pre` f, swing in 3 f, hold 17, back in 12, hold `tail`
func attacker(pre := 10, tail := 3) -> Scene:
	var B := stand()
	var a0: Vector3 = B.ang["upperarm_r"]
	var guard := posed("upperarm_r", Vector3(-40.0, a0.y, a0.z))
	var hit := posed("upperarm_r", Vector3(70.0, a0.y, a0.z))
	return plain([{"name": "guard", "pose": guard, "move": -1.0, "hold": f(pre)},
		{"name": "strike", "pose": hit, "move": f(3), "hold": f(17)},
		{"name": "back", "pose": guard, "move": f(12), "hold": f(tail)}])


## a reaction clip: impact (stance), recoil in 2 f held `h` f, back in 1 f, held 30 f
func reaction(h: int) -> Scene:
	var B := stand()
	var st := B.to_dict()
	var s3: Vector3 = B.ang["spine_03"]
	var rec := posed("spine_03", s3 + Vector3(-25.0, 0, 0))
	return plain([{"name": "impact", "pose": st, "move": -1.0, "hold": 0.0},
		{"name": "recoil", "pose": rec, "move": f(2), "hold": f(h)},
		{"name": "guard", "pose": st, "move": f(1), "hold": f(30)}])


## the test's own stun scan (not FrameAdvantage.stun): joint + end points minus the pelvis, max distance to the pose at t_hit
func shape_of(B: Body) -> Array:
	var out := []
	for j in B.P:
		out.append((B.P[j] as Vector3) - (B.P["pelvis"] as Vector3))
	for j in B.E:
		out.append((B.E[j] as Vector3) - (B.P["pelvis"] as Vector3))
	return out


func own_dev(S: Scene, B: Body, t: float, ref: Array) -> float:
	S.apply(B, t)
	var sh := shape_of(B)
	var d := 0.0
	for i in sh.size():
		d = maxf(d, (sh[i] as Vector3).distance_to(ref[i]))
	return d


func own_stun_end(S: Scene, B: Body, t_hit: float, tol: float) -> int:
	var c := int(ceil(t_hit * FPS - 1e-6))
	S.apply(B, t_hit)
	var ref := shape_of(B)
	var last := int(floor(S.length() * FPS + 1e-6))
	var ds := {}
	var pk := c
	for fr in range(c, last + 1):
		ds[fr] = own_dev(S, B, float(fr) / FPS, ref)
		if float(ds[fr]) > float(ds[pk]):
			pk = fr
	if float(ds[pk]) <= tol:
		return c + 1
	for fr in range(pk + 1, last + 1):
		var good := true
		for k in range(fr, mini(fr + 3, last + 1)):
			if float(ds[k]) > tol:
				good = false
		if good:
			return fr
	return last + 1


func _init() -> void:
	var DB := stand()
	var AB := stand()
	# 1
	var A := attacker()
	var ex := FrameAdvantage.of_clips(A, AB, reaction(40), reaction(20), DB, FPS, [attacker(12)])
	var fd: Dictionary = ex["fd"]
	print("synthetic: n %d, startup %d, active %d, recovery %d | contact %d, hit end %s stun %s on hit %s | block end %s stun %s on block %s | fastest %s punishable %s"
		% [fd["n"], fd["startup"], fd["active"], fd["recovery"], ex["contact_f"], ex["hit_stun_end"], ex["hitstun"], ex["on_hit"],
		ex["block_stun_end"], ex["blockstun"], ex["on_block"], ex["defender_fastest_startup"], ex["punishable"]])
	ok(int(fd["n"]) == 45 and int(fd["startup"]) == 10 and int(fd["active"]) == 3 and int(fd["recovery"]) == 32,
		"1 synthetic attacker: 45 f = startup %d + active %d + recovery %d (want 10 + 3 + 32)" % [fd["startup"], fd["active"], fd["recovery"]])
	ok(ex["contact_f"] == 10 and ex["hit_stun_end"] == 53 and ex["hitstun"] == 42 and ex["on_hit"] == 8,
		"1 on hit: contact %s, stun end %s, hitstun %s, advantage %s (want 10, 53, 42, +8)" % [ex["contact_f"], ex["hit_stun_end"], ex["hitstun"], ex["on_hit"]])
	ok(ex["block_stun_end"] == 33 and ex["blockstun"] == 22 and ex["on_block"] == -12,
		"1 on block: stun end %s, blockstun %s, advantage %s (want 33, 22, -12)" % [ex["block_stun_end"], ex["blockstun"], ex["on_block"]])
	# 2
	ok(ex["defender_fastest_startup"] == 12 and ex["punishable"] == false, "2 -12 on block vs a 12 f startup: punishable %s (want false)" % ex["punishable"])
	var ex2 := FrameAdvantage.of_clips(A, AB, reaction(40), reaction(20), DB, FPS, [attacker(12), attacker(5)])
	ok(ex2["defender_fastest_startup"] == 5 and ex2["punishable"] == true, "2 with a 5 f move: fastest %s, punishable %s (want 5, true): %s" % [ex2["defender_fastest_startup"], ex2["punishable"], FrameAdvantage.words(ex2)])
	# 3
	var ex3 := FrameAdvantage.of_clips(attacker(10, 13), AB, reaction(40), reaction(20), DB, FPS, [attacker(12)])
	ok(int(ex3["fd"]["recovery"]) - int(fd["recovery"]) == 10 and int(ex3["on_hit"]) - int(ex["on_hit"]) == -10 and int(ex3["on_block"]) - int(ex["on_block"]) == -10
		and ex3["hitstun"] == ex["hitstun"] and ex3["blockstun"] == ex["blockstun"],
		"3 synthetic +10 f recovery: recovery %+d, on hit %+d, on block %+d, stuns %s/%s" % [int(ex3["fd"]["recovery"]) - int(fd["recovery"]),
		int(ex3["on_hit"]) - int(ex["on_hit"]), int(ex3["on_block"]) - int(ex["on_block"]), ex3["hitstun"], ex3["blockstun"]])

	# 4 combo3 vs a standing fighter, his reaction baked at the first contact
	var C := Scene.new()
	C.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var CB := stand()
	var D0 := stand()
	var pose := D0.to_dict()
	var DS := Scene.new()
	DS.from_dict({"scene": "zz_def", "fps": 30, "cards": [{"name": "a", "pose": pose, "move": -1.0, "hold": 2.0},
		{"name": "b", "pose": pose, "move": 0.5, "hold": 3.0}]})
	var xf := Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 1.0))
	var t0 := Time.get_ticks_msec()
	var hits := Dummy.fighter_hits(C, CB, DS, D0, xf, FPS).filter(func(h): return h["by"] == "hero")
	ok(not hits.is_empty(), "4 combo3 reaches the fighter 1.0 m out: %d contact(s), first at %.3f s on %s" % [hits.size(), hits[0]["t"] if not hits.is_empty() else -1.0, hits[0]["on"] if not hits.is_empty() else "-"])
	var blk := reaction(20)
	var c3 := {}
	if not hits.is_empty():
		var fd_c := FrameData.analyze(C, CB, FPS)
		var ct := FrameAdvantage.contact(fd_c, hits)
		var hrow: Dictionary = hits[0]
		for h in hits:
			if float(h["t"]) == float(ct["t"]):
				hrow = h
		var r := HitReaction.react(DS, D0, xf, hrow, CB)
		ok(bool(r.get("ok", false)), "4 HitReaction baked the reaction (%s)" % r.get("why", ""))
		DS.cards = r["cards"]
		c3 = FrameAdvantage.of_actors(C, CB, DS, D0, xf, FPS, blk, [])
		var fdc: Dictionary = c3["fd"]
		var count := 0
		var first := -1
		var lastf := -1
		for fr in fdc["frames"]:
			count += 1
			if fr["active"]:
				lastf = int(fr["f"])
				if first < 0:
					first = int(fr["f"])
		var own_R := count   # the first frame after the scene's last: last active + recovery + 1
		var own_E := own_stun_end(DS, stand(), float(ct["t"]), 0.02)
		var c := int(c3["contact_f"])
		var own_Eb := c + own_stun_end(blk, stand(), 0.0, 0.02)
		print("combo3: %d f, startup %d active %d recovery %d, contact %s (%s, %.3f s on %s), hit stun end %s (own %d) peak %s, block end %s (own %d); %s (%d ms)"
			% [fdc["n"], fdc["startup"], fdc["active"], fdc["recovery"], c, c3["contact_from"], ct["t"], ct["on"], c3["hit_stun_end"], own_E, "-", c3["block_stun_end"], own_Eb, FrameAdvantage.words(c3), Time.get_ticks_msec() - t0])
		ok(c3["contact_from"] == "contact" and int(c3["hitstun"]) >= 1, "4 a real contact (%s) and a hitstun of %s f" % [c3["contact_from"], c3["hitstun"]])
		ok(int(c3["recovery_end"]) == own_R and own_R == lastf + int(fdc["recovery"]) + 1, "4 recovery end %s = own count %d = last active %d + recovery %d + 1" % [c3["recovery_end"], own_R, lastf, fdc["recovery"]])
		ok(int(c3["hit_stun_end"]) == own_E and int(c3["on_hit"]) == own_E - own_R and int(c3["hitstun"]) == own_E - c - 1,
			"4 on hit: stun end %s = own %d, advantage %s = %d - %d, hitstun %s = %d - %d - 1" % [c3["hit_stun_end"], own_E, c3["on_hit"], own_E, own_R, c3["hitstun"], own_E, c])
		ok(int(c3["block_stun_end"]) == own_Eb and int(c3["on_block"]) == own_Eb - own_R and int(c3["blockstun"]) == own_Eb - c - 1,
			"4 on block: stun end %s = own %d, advantage %s = %d - %d" % [c3["block_stun_end"], own_Eb, c3["on_block"], own_Eb, own_R])
		var Bt := stand()
		DS.apply(Bt, float(ct["t"]))
		var ref := shape_of(Bt)
		var d_in := own_dev(DS, Bt, float(own_E) / FPS, ref)
		var d_out := own_dev(DS, Bt, float(own_E - 1) / FPS, ref)
		ok(d_out > 0.02 and d_in <= 0.02, "4 out of guard by %.1f cm the frame before the stun end, %.1f cm on it (tolerance 2 cm)" % [d_out * 100.0, d_in * 100.0])
		for tol in [0.01, 0.05]:
			var st := FrameAdvantage.stun(DS, stand(), float(ct["t"]), FPS, tol)
			print("  sensitivity: tolerance %d cm -> hitstun %d (peak %.1f cm at frame %d)" % [int(tol * 100.0), st["stun"], float(st["peak_m"]) * 100.0, st["peak_f"]])
		# 3 on combo3: the last card held 10 f longer
		var C2 := C.clone()
		C2.cards[-1]["hold"] = float(C2.cards[-1]["hold"]) + 10.0 / FPS
		var c3b := FrameAdvantage.of_actors(C2, CB, DS, D0, xf, FPS, blk, [])
		ok(int(c3b["fd"]["recovery"]) - int(fdc["recovery"]) == 10 and int(c3b["on_hit"]) - int(c3["on_hit"]) == -10 and int(c3b["on_block"]) - int(c3["on_block"]) == -10
			and c3b["hitstun"] == c3["hitstun"],
			"3 combo3 +10 f recovery: recovery %+d, on hit %+d, on block %+d" % [int(c3b["fd"]["recovery"]) - int(fdc["recovery"]), int(c3b["on_hit"]) - int(c3["on_hit"]), int(c3b["on_block"]) - int(c3["on_block"])])

	# 5 export
	var fdx: Dictionary = (ex["fd"] as Dictionary).duplicate()
	var plain_json := FrameData.to_json(fdx)
	fdx["exchange"] = FrameAdvantage.to_json(ex)
	var path := "user://frameadv_test.json"
	ok(FrameData.write_json(fdx, path) == OK, "5 written")
	var back: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var e: Dictionary = back.get("exchange", {})
	var same := true
	for k in ["on_hit", "on_block", "hitstun", "blockstun", "recovery_end", "contact_f", "hit_stun_end", "block_stun_end", "defender_fastest_startup"]:
		if not e.has(k) or int(e[k]) != int(ex[k]):
			same = false
	ok(same and e.get("punishable") == ex["punishable"] and not plain_json.has("exchange"),
		"5 export: exchange %s; without one, no key (%s)" % [JSON.stringify(e).left(200), plain_json.has("exchange")])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# 6 serve
	var tmpd := "user://frameadv_clips"
	DirAccess.make_dir_recursive_absolute(tmpd)
	var hp := ProjectSettings.globalize_path(tmpd + "/hit.json")
	var bp := ProjectSettings.globalize_path(tmpd + "/block.json")
	for kv in [[hp, reaction(40)], [bp, reaction(20)]]:
		var fh := FileAccess.open(kv[0], FileAccess.WRITE)
		fh.store_string(JSON.stringify((kv[1] as Scene).to_dict(stand(), false)))
		fh.close()
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	var T := AgentTools.new(m)
	await T.request(1, "open", {"path": "scenes/combo3.json"})
	var d0: Dictionary = await T.request(2, "frame_data", {})
	var d1: Dictionary = await T.request(3, "frame_data", {"hit_clip": hp, "block_clip": bp})
	var d2: Dictionary = await T.request(4, "frame_data", {"hit_clip": "nope/none.json"})
	var r0: Dictionary = d0.get("result", {})
	var r1: Dictionary = d1.get("result", {})
	var want := FrameAdvantage.of_clips(C, stand(), reaction(40), reaction(20), stand(), FPS)
	var x1: Dictionary = r1.get("exchange", {})
	ok(r0.has("startup") and r0.has("recovery") and not r0.has("exchange") and not r0.has("frames"),
		"6 serve default: %s" % JSON.stringify(r0).left(160))
	ok(not x1.is_empty() and x1.get("on_hit") == want["on_hit"] and x1.get("on_block") == want["on_block"] and x1.get("hitstun") == want["hitstun"],
		"6 serve opt-in exchange: on hit %s on block %s hitstun %s (of_clips: %s %s %s)" % [x1.get("on_hit"), x1.get("on_block"), x1.get("hitstun"), want["on_hit"], want["on_block"], want["hitstun"]])
	ok(d2.has("error") and int(d2["error"]["code"]) == -32602, "6 a missing clip: %s" % JSON.stringify(d2.get("error", {})).left(160))
	m.queue_free()
	DirAccess.remove_absolute(hp)
	DirAccess.remove_absolute(bp)
	print("FRAMEADV TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
