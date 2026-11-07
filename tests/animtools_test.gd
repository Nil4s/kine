## godot --path . -s tests/animtools_test.gd     (ROADMAP_400 L07 L09 L10 L11; a window is needed: the real poser is built)
## ANIMATION TOOLS. Bars written BEFORE the implementation (lane L87):
## L07 ONION: playhead on frame 10 of combo3, 2 before + 2 after, every 2nd frame -> ghosts at frames {6, 8, 12, 14} and no others
##   (planted control: step 1 gives {8, 9, 11, 12}, a different set). Per-part: 2 picked parts -> 2 x 4 = 8 visible meshes and only the
##   picked pieces are visible; past ghosts wear Tok onion_past, future ones onion_future, and the two colours differ.
## L09 BREAKDOWN on 3 selected parts of a middle card: factor 0 = the card before, 1 = the card after (rotation components within 1e-5),
##   0.5 = an independent slerp midpoint within 1e-5, 1.3 overshoots past the next card (angle from the before-card is larger than at 1),
##   every unselected joint byte-identical (var_to_bytes), and a call is exactly one undo step that Ctrl+Z restores byte for byte.
## L10 RETIME: moving card 3's arrival +5 frames with ripple -> every later card's arrival (and every later part key) moves exactly +5
##   frames (error under 1e-6 frame), earlier cards / part keys byte-identical, one undo step. Without ripple a move that would cross the
##   next key is REFUSED (nothing changes, no undo step); a legal non-ripple move leaves every OTHER key's arrival where it was (1e-6 frame).
##   Planted control: the byte-compare helper does flag a card whose move was nudged by one frame.
## L11 KEYING SETS: a set of upperarm_r + lowerarm_r active, auto-key on, a hand_l change keys exactly those two parts at the playhead
##   (part keys on nothing else, no new card), one undo step; the sets save and reload (to_dict, JSON, from_dict: same sets + active);
##   with no active set auto-key still makes a card (the old behaviour). Making a keying set is one undo step.
## The agent tool `animtools` answers the same numbers (AnimTools.serve ops onion, breakdown, retime, keyset).
extends SceneTree

var fails := 0
var n_ok := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if c:
		n_ok += 1
	else:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func at(t: float) -> void:
	m.playhead = t
	m._refresh()
	await idle(2)


func frames_of(rigs: Array, fps: float) -> Array:
	var out := []
	for r in rigs:
		out.append(int(round(float(r.t) * fps)))
	out.sort()
	return out


func card_bytes(i: int) -> PackedByteArray:
	return var_to_bytes(m.S.cards[i])


func q_gap(a: Quaternion, b: Quaternion) -> float:
	var s := 1.0 if a.dot(b) >= 0.0 else -1.0
	return maxf(maxf(absf(a.x - s * b.x), absf(a.y - s * b.y)), maxf(absf(a.z - s * b.z), absf(a.w - s * b.w)))


func ang_q(j: String, v: Vector3) -> Quaternion:
	return m.B.compose(j, v)


func unsel_bytes_equal(js: Array, ref: Dictionary) -> bool:
	for j in m.B.ang:
		if js.has(j):
			continue
		if var_to_bytes(m.B.ang[j]) != var_to_bytes(ref[j]):
			return false
	return true


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	var S: Scene = m.S
	var fps := float(S.fps)
	var ov: Overlays = m.ov

	# ---------------------------------------------------------------- L07 onion
	m._onion_panel_open()
	m.sel = "upperarm_r"
	m._onion_pick_sel()
	m.sel = "lowerarm_r"
	m._onion_pick_sel()
	m._onion_set_parts(true)
	ov.onion_before = 2
	ov.onion_after = 2
	ov.onion_step = 2
	await at(10.0 / fps)
	var fr := frames_of(ov._rigs, fps)
	ok(fr == [6, 8, 12, 14], "L07 every 2nd frame, 2 before + 2 after, playhead frame 10: ghosts at %s (bar [6, 8, 12, 14])" % str(fr))
	ok(ov._rigs.size() == 4, "L07 no other ghost: %d rigs (bar 4)" % ov._rigs.size())
	ok(ov.onion_mesh_count() == 8, "L07 per-part: 2 picked parts x 4 ghosts = %d meshes (bar 8)" % ov.onion_mesh_count())
	var only_picked := true
	for r in ov._rigs:
		for pj in r.pieces:
			if (r.pieces[pj] as MeshInstance3D).visible != ov.onion_picks.has(pj):
				only_picked = false
	ok(only_picked, "L07 per-part: only the picked pieces are visible on every ghost")
	var past_ok := true
	var fut_ok := true
	for r in ov._rigs:
		var c: Color = (r.mat as StandardMaterial3D).albedo_color
		var is_past := float(r.t) < 10.0 / fps
		var want: Color = Tok.c("onion_past" if is_past else "onion_future")
		if absf(c.r - want.r) + absf(c.g - want.g) + absf(c.b - want.b) > 1e-4:
			if is_past:
				past_ok = false
			else:
				fut_ok = false
	ok(past_ok and fut_ok, "L07 past ghosts wear onion_past, future ones onion_future (past %s future %s)" % [past_ok, fut_ok])
	var pc: Color = Tok.c("onion_past")
	var fc: Color = Tok.c("onion_future")
	var cdiff := absf(pc.r - fc.r) + absf(pc.g - fc.g) + absf(pc.b - fc.b)
	ok(cdiff > 0.5, "L07 past and future colours differ by %.2f (bar > 0.5)" % cdiff)
	ov.onion_step = 1
	await at(10.0 / fps)
	var fr1 := frames_of(ov._rigs, fps)
	ok(fr1 == [8, 9, 11, 12] and fr1 != fr, "L07 planted control: step 1 gives %s, not the step-2 set" % str(fr1))
	ov.onion_step = 2
	var tool_on: Dictionary = AnimTools.serve(m, {"op": "onion", "before": 2, "after": 2, "step": 2, "frame": 10})
	ok(tool_on.get("ok", false) and tool_on["result"]["frames"] == [6, 8, 12, 14], "L07 tool: onion frames %s" % str(tool_on.get("result", tool_on)))
	ov.onion_on = false
	ov.onion_parts_on = false

	# ---------------------------------------------------------------- L09 breakdown
	var k := 3
	m.sel_card = k
	m._select_set(["upperarm_r", "lowerarm_r", "thigh_l"])
	var js := ["upperarm_r", "lowerarm_r", "thigh_l"]
	var prev: Dictionary = Moves._flat(S.cards[k - 1]["pose"])["ang"]
	var nxt: Dictionary = Moves._flat(S.cards[k + 1]["pose"])["ang"]
	S.apply(m.B, S.times()[k][1])
	m._refresh()
	var base_ang: Dictionary = m.B.ang.duplicate(true)
	var base_state: Dictionary = m.B.state()
	var cards_before := var_to_bytes(S.cards)
	var u0: int = m.undo.size()
	m._breakdowner(0.0)
	ok(m.undo.size() == u0 + 1, "L09 one breakdown = one undo step (%d -> %d)" % [u0, m.undo.size()])
	var g0 := 0.0
	for j in js:
		g0 = maxf(g0, q_gap(ang_q(j, m.B.ang[j]), ang_q(j, prev[j])))
	ok(g0 < 1e-5, "L09 factor 0 = the card before: worst rotation gap %.8f (bar 1e-5)" % g0)
	ok(unsel_bytes_equal(js, base_ang), "L09 unselected joints byte-identical after factor 0")
	m._undo()
	ok(m.undo.size() == u0 and var_to_bytes(S.cards) == cards_before and var_to_bytes(m.B.state()) == var_to_bytes(base_state), "L09 Ctrl+Z restores the body and the cards byte for byte")
	m._breakdowner(1.0)
	var g1 := 0.0
	for j in js:
		g1 = maxf(g1, q_gap(ang_q(j, m.B.ang[j]), ang_q(j, nxt[j])))
	ok(g1 < 1e-5, "L09 factor 1 = the card after: worst rotation gap %.8f (bar 1e-5)" % g1)
	m._undo()
	m._breakdowner(0.5)
	var gm := 0.0
	for j in js:
		var want := ang_q(j, prev[j]).slerp(ang_q(j, nxt[j]), 0.5)
		gm = maxf(gm, q_gap(ang_q(j, m.B.ang[j]), want))
	ok(gm < 1e-5, "L09 factor 0.5 = the slerp midpoint: worst gap %.8f (bar 1e-5)" % gm)
	ok(unsel_bytes_equal(js, base_ang), "L09 unselected joints byte-identical after factor 0.5")
	m._undo()
	m._breakdowner(1.3)
	var past := 0.0
	for j in js:
		var a1 := rad_to_deg((ang_q(j, prev[j]).inverse() * ang_q(j, m.B.ang[j])).get_angle())
		var a2 := rad_to_deg((ang_q(j, prev[j]).inverse() * ang_q(j, nxt[j])).get_angle())
		past = maxf(past, a1 - a2)
	ok(past > 0.01, "L09 factor 1.3 overshoots past the next card by up to %.3f deg (bar > 0.01)" % past)
	m._undo()
	var t_bd: Dictionary = AnimTools.serve(m, {"op": "breakdown", "card": k, "factor": 0.5, "parts": js})
	ok(t_bd.get("ok", false) and absf(float(t_bd["result"]["factor"]) - 0.5) < 1e-9 and int(t_bd["result"]["moved"]) >= 1, "L09 tool: breakdown %s" % str(t_bd.get("result", t_bd)))
	m._undo()

	# ---------------------------------------------------------------- L10 retime
	var ts0: Array = S.times().duplicate(true)
	var t3 := float(ts0[3][1])
	m._do(func():
		PartKeys.put(S.part_keys, "head", t3 - 0.2, Vector3(5, 0, 0))
		PartKeys.put(S.part_keys, "head", t3 + 0.3, Vector3(9, 0, 0))
		PartKeys.put(S.part_keys, "hand_r", t3 + 0.6, Vector3(11, 0, 0)))
	var ts1: Array = S.times().duplicate(true)
	var pk1 := S.part_keys.duplicate(true)
	var cb1: Array = []
	for i in S.cards.size():
		cb1.append(card_bytes(i))
	var u1: int = m.undo.size()
	var r: Dictionary = m._retime_key(3, 5, true)
	ok(r.get("ok", false) and m.undo.size() == u1 + 1, "L10 ripple +5 frames on card 3: ok %s, one undo step (%d -> %d)" % [r.get("ok"), u1, m.undo.size()])
	var ts2: Array = S.times()
	var worst_later := 0.0
	for i in range(4, S.cards.size()):
		worst_later = maxf(worst_later, absf((float(ts2[i][1]) - float(ts1[i][1])) * fps - 5.0))
	ok(worst_later < 1e-6, "L10 every later card moved exactly +5 frames: worst error %.9f frame (bar 1e-6), %d cards" % [worst_later, S.cards.size() - 4])
	ok(absf((float(ts2[3][1]) - float(ts1[3][1])) * fps - 5.0) < 1e-6, "L10 the dragged key itself moved +5 frames")
	var earlier_same := true
	for i in 3:
		if card_bytes(i) != cb1[i]:
			earlier_same = false
	ok(earlier_same, "L10 cards before the key are byte-identical")
	var pk_ok := true
	for j in pk1:
		var arr: Array = pk1[j]
		var now: Array = S.part_keys[j]
		for q in arr.size():
			var want_t := float(arr[q]["t"]) + (5.0 / fps if float(arr[q]["t"]) > t3 + 1e-9 else 0.0)
			if absf(float(now[q]["t"]) - want_t) > 1e-9 or var_to_bytes(now[q]["v"]) != var_to_bytes(arr[q]["v"]):
				pk_ok = false
	ok(pk_ok, "L10 part keys after the key moved +5 frames exactly, earlier ones and all values untouched")
	m._undo()
	ok(m.undo.size() == u1 and var_to_bytes(S.part_keys) == var_to_bytes(pk1) and card_bytes(3) == cb1[3], "L10 one Ctrl+Z puts the cards and part keys back byte for byte")
	var nudged := (S.cards[2] as Dictionary).duplicate(true)
	nudged["move"] = float(nudged["move"]) + 1.0 / fps
	ok(var_to_bytes(nudged) != cb1[2], "L10 planted control: a card nudged by one frame IS flagged by the byte compare")
	ts1 = S.times().duplicate(true)
	var all_before := var_to_bytes(S.cards)
	var u2: int = m.undo.size()
	var gap_next := (float(ts1[4][1]) - float(ts1[3][1])) * fps
	var rc: Dictionary = m._retime_key(3, int(ceil(gap_next)) + 2, false)
	ok(not rc.get("ok", true) and m.undo.size() == u2 and var_to_bytes(S.cards) == all_before, "L10 no ripple: moving key 3 past key 4 (+%d frames) is refused, nothing changes, no undo step (%s)" % [int(ceil(gap_next)) + 2, str(rc.get("why", ""))])
	var rp: Dictionary = m._retime_key(3, -1, false)
	var ts3: Array = S.times()
	var others := 0.0
	for i in S.cards.size():
		if i == 3:
			continue
		others = maxf(others, absf((float(ts3[i][1]) - float(ts1[i][1])) * fps))
	ok(rp.get("ok", false) and m.undo.size() == u2 + 1 and others < 1e-6, "L10 no ripple, legal -1 frame: ok %s, every other key stays (worst %.9f frame), one undo step" % [rp.get("ok"), others])
	ok(absf((float(ts3[3][1]) - float(ts1[3][1])) * fps + 1.0) < 1e-6, "L10 the moved key is -1 frame")
	m._undo()
	var t_rt: Dictionary = AnimTools.serve(m, {"op": "retime", "card": 3, "frames": 5, "ripple": true})
	ok(t_rt.get("ok", false) and absf(float(t_rt["result"]["frames"]) - 5.0) < 1e-9, "L10 tool: retime %s" % str(t_rt.get("result", t_rt)))
	m._undo()

	# ---------------------------------------------------------------- L11 keying sets
	var ps := PartSets.of(m)
	var cards_n := S.cards.size()
	var u3: int = m.undo.size()
	m._select_set(["upperarm_r", "lowerarm_r"])
	ps.make("keying")
	ok(m.undo.size() == u3 + 1, "L11 making a keying set is one undo step (%d -> %d)" % [u3, m.undo.size()])
	var nm := ps.active()
	ok(nm != "" and ps.parts_of("keying", nm) == ["upperarm_r", "lowerarm_r"], "L11 the new keying set '%s' is active and holds the two parts" % nm)
	m.auto_key = true
	S.part_keys.clear()
	await at(float(ts0[2][1]) + 0.07)
	var u4: int = m.undo.size()
	m._do(func(): m.B.set_ang("hand_l", Vector3(30, 0, 0)))
	var keyed := S.part_keys.keys()
	keyed.sort()
	ok(keyed == ["lowerarm_r", "upperarm_r"], "L11 auto-key on the set keys only its parts: %s (bar [lowerarm_r, upperarm_r])" % str(keyed))
	ok(S.cards.size() == cards_n, "L11 no card was added by the set's auto-key (%d cards, was %d)" % [S.cards.size(), cards_n])
	var tk_ok := true
	for j in keyed:
		if absf(float((S.part_keys[j] as Array)[0]["t"]) - m.playhead) > 1e-6:
			tk_ok = false
	ok(tk_ok and m.undo.size() == u4 + 1, "L11 the keys sit at the playhead and the change + keys are one undo step (%d -> %d)" % [u4, m.undo.size()])
	m._undo()
	ok(S.part_keys.is_empty() and S.cards.size() == cards_n, "L11 Ctrl+Z takes the keys back")
	var keep: Dictionary = m.B.state()
	var d: Dictionary = JSON.parse_string(JSON.stringify(S.to_dict(m.B, false)))
	m.B.set_state(keep)
	var S2 := Scene.new()
	S2.from_dict(d)
	ok(var_to_str(S2.sets) == var_to_str(S.sets) and String(S2.sets.get("active", "")) == nm, "L11 the sets save and reload: %s" % JSON.stringify(S2.sets))
	var t_ks: Dictionary = AnimTools.serve(m, {"op": "keyset", "name": "legs", "parts": ["thigh_l", "thigh_r"], "active": true})
	ok(t_ks.get("ok", false) and ps.active() == "legs" and ps.parts_of("keying", "legs") == ["thigh_l", "thigh_r"], "L11 tool: keyset %s" % str(t_ks.get("result", t_ks)))
	m._undo()
	ps.use_none()
	S.part_keys.clear()
	var n0 := S.cards.size()
	await at(float(ts0[2][1]) + 0.07)
	m._do(func(): m.B.set_ang("hand_l", Vector3(35, 0, 0)))
	ok(S.cards.size() == n0 + 1 and S.part_keys.is_empty(), "L11 control: no active set, auto-key makes a card as before (%d -> %d cards)" % [n0, S.cards.size()])
	print("ANIMTOOLS: %d ok, %d failed" % [n_ok, fails])
	quit(1 if fails > 0 else 0)
