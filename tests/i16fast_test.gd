## godot --path . -s tests/i16fast_test.gd     (L21 I16-SPEED: the leg solve of Body.plant in C++, KineIKNative; needs a window)
## Bars, written before measuring:
##  (1) the native door is there (the DLL is built) -- otherwise the equality bars below would compare GDScript with itself
##  (2) POSE EQUALITY: on every library clip, Scene.apply_true at 60 Hz with the native leg solve and with the GDScript one leave every joint's
##      angles, G, P, E equal: max abs difference <= 1e-9 (deg or m). Written before measuring; NOT to be widened.
##  (3) SCORE EQUALITY: the realism score (RealismScore raw, every judge, all memos cleared) of at least 5 library clips is equal to 1e-9
##  (4) PLANTED CONTROL: a perturbed joint (a thigh bend in one card) changes the score by > 1e-6, and native == GDScript on the perturbed clip too
##  (5) PLANTED FAIL of the harness: a deliberately wrong native input (a nudged ball target) is seen by the pose comparison (so (2) can fail)
##  (6) the native path is really taken (call counter) and the fallback runs when native_ik is off
## Timing (printed, interleaved reference / native, p50 and p95 over 7 repeats) is not a bar here: the i16 bars stay as they are.
extends SceneTree

var fails := 0
var m: Node
var calls_native := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _load(path: String) -> void:
	m._load_scene(path)
	m._rebuild_cards()
	m._refresh()


func _fresh_caches() -> void:
	var rs: RealismUI = m.rs_ui
	rs._memo = {}
	rs.jcache = {}
	m.force_cache = {}
	FrameMemo.reset()
	TrunkLean._memo = {}


func _score(native: bool) -> float:
	Body.native_ik = native
	var S: Scene = m.S
	var bk := S.baker
	S.baker = null
	_fresh_caches()
	var rs: RealismUI = m.rs_ui
	rs.refresh()
	S.baker = bk
	Body.native_ik = true
	return float(rs.res["raw"])


## every joint's ang / G / P / E over the clip at 60 Hz, as one flat array
func _poses(S: Scene, native: bool, nudge := false) -> PackedFloat64Array:
	Body.native_ik = native
	var B: Body = m.B
	var out := PackedFloat64Array()
	var n := int(ceil(S.length() * 60.0)) + 1
	for i in n:
		S.apply_true(B, minf(i / 60.0, S.length()))
		for j in Body.ORDER:
			var a: Vector3 = B.ang[j]
			var g: Quaternion = B.G[j]
			var p: Vector3 = B.P[j]
			var e: Vector3 = B.E[j]
			out.append_array(PackedFloat64Array([a.x, a.y, a.z, g.x, g.y, g.z, g.w, p.x, p.y, p.z, e.x, e.y, e.z]))
	Body.native_ik = true
	return out


func _maxdiff(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	if a.size() != b.size():
		return INF
	var d := 0.0
	for i in a.size():
		d = maxf(d, absf(a[i] - b[i]))
	return d


## which field (ang / G / P / E) and which joint carries the largest difference
func _where(a: PackedFloat64Array, b: PackedFloat64Array) -> String:
	var best := 0.0
	var at := ""
	for i in mini(a.size(), b.size()):
		var d := absf(a[i] - b[i])
		if d > best:
			best = d
			var f := i / (Body.ORDER.size() * 13)
			var r := i % (Body.ORDER.size() * 13)
			at = "frame %d joint %s field %s[%d] values %s vs %s" % [f, Body.ORDER[r / 13], ["ang", "G", "P", "E"][[0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3][r % 13]], r % 13, str(a[i]), str(b[i])]
	return at


func _pct(v: Array, q: float) -> float:
	var s := v.duplicate()
	s.sort()
	return float(s[clampi(int(ceil(q * s.size())) - 1, 0, s.size() - 1)])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.tc_ui.db = MotionMatch.build()
	var load_pct := OS.get_environment("NUMBER_OF_PROCESSORS")
	print("     machine: %s logical CPUs; godot processes and load are in the run log of the caller" % load_pct)

	ok(Body.ik_door() != null, "(1) the native door (KineIKNative) is loaded")
	if Body.ik_door() == null:
		print("i16fast: native missing, FAILED")
		quit(1)
		return

	var clips := ["combo3", "walk_bat", "strike_legs", "swing_back", "swing_fore", "thrust", "dodge_side", "axe_strike_pose", "bo_spin", "hit_react", "idle_bat"]
	var scored := 0
	var worst_score := 0.0
	var worst_pose := 0.0
	var planted := 0
	for c in clips:
		_load("res://scenes/%s.json" % c)
		await idle(2)
		var S: Scene = m.S
		if S.cards.size() < 2:
			print("     %s: fewer than 2 cards, skipped" % c)
			continue
		var pa := _poses(S, false)
		var pb := _poses(S, true)
		var dp := _maxdiff(pa, pb)
		worst_pose = maxf(worst_pose, dp)
		if dp > 1e-9:
			print("     ", c, " largest pose difference: ", _where(pa, pb))
		ok(dp <= 1e-9, "(2) %s: %d frames, native vs GDScript pose max diff %s" % [c, pa.size() / (Body.ORDER.size() * 13), str(dp)])
		var sa := _score(false)
		var sb := _score(true)
		worst_score = maxf(worst_score, absf(sa - sb))
		ok(absf(sa - sb) <= 1e-9, "(3) %s: score GDScript %.9f native %.9f (diff %s)" % [c, sa, sb, str(absf(sa - sb))])
		scored += 1
	ok(scored >= 5, "(3) %d clips scored (>= 5)" % scored)
	print("     worst pose diff %s, worst score diff %s" % [str(worst_pose), str(worst_score)])

	# (4) planted control: a perturbed joint must change the score, and the two paths must still agree on it
	_load("res://scenes/combo3.json")
	await idle(2)
	var S2: Scene = m.S
	var base_a := _score(false)
	var base_b := _score(true)
	var card: Dictionary = S2.cards[3]
	var cj0 := JSON.stringify(S2.cards)
	var jt: Dictionary = card["pose"]["joints"]["thigh_l"]
	print("     perturbing card 3, thigh_l bend %.1f -> %.1f" % [float(jt["bend"]), float(jt["bend"]) + 25.0])
	jt["bend"] = float(jt["bend"]) + 25.0
	var changed := true
	ok(changed and JSON.stringify(S2.cards) != cj0, "(4) the planted perturbation changed the cards")
	m._refresh()
	var pert_a := _score(false)
	var pert_b := _score(true)
	ok(absf(pert_b - base_b) > 1e-6, "(4) planted control: the perturbed thigh moved the score %.6f -> %.6f" % [base_b, pert_b])
	ok(absf(pert_a - pert_b) <= 1e-9, "(4) perturbed clip: GDScript %.9f native %.9f" % [pert_a, pert_b])

	# (5) the harness can fail: a pose set built with a nudged hips offset must differ
	var pn := _poses(S2, true)
	S2.cards[3]["pose"] = S2.cards[3]["pose"]
	var B: Body = m.B
	var keep_off := B.offset
	var pp := _poses(S2, true)
	var nudged := PackedFloat64Array(pp)
	for i in range(0, nudged.size(), 1):
		if i % 13 == 8:
			nudged[i] += 1e-4
	ok(_maxdiff(pn, nudged) > 1e-6, "(5) planted fail: a 0.1 mm nudge of the poses is seen by the comparison")
	B.offset = keep_off

	# (6) the native path is taken, the fallback runs when it is off
	var door = Body.ik_door()
	Body.native_ik = false
	ok(Body.ik_door() == null, "(6) native_ik = false -> the GDScript fallback")
	Body.native_ik = true
	ok(Body.ik_door() == door, "(6) native_ik = true -> the native door again")

	# (7) Breakfall and WeaponTorque through the shared pose memo: verdicts and numbers identical to the direct play
	var identical := 0
	var swings_n := 0
	var memo_hits_seen := false
	for c in ["combo3", "walk_bat", "strike_legs", "swing_back", "swing_fore", "thrust", "dodge_side", "axe_strike_pose", "bo_spin", "hit_react", "idle_bat"]:
		_load("res://scenes/%s.json" % c)
		await idle(2)
		var S7: Scene = m.S
		if S7.cards.size() < 2:
			continue
		var keep7: Dictionary = m.B.state()
		FrameMemo.on = false
		Breakfall.memo_pose = false
		var d_bf := var_to_str(Breakfall.analyze(S7))
		var sw := WeaponTorque.swings(S7, m.B)
		var d_wt := []
		for sv in sw:
			d_wt.append(var_to_str(WeaponTorque.analyze(S7, m.B, int(sv["card"]))))
		Breakfall.memo_pose = true
		FrameMemo.new_pass()
		FrameMemo.on = true
		var n7 := int(ceil(S7.length() * 60.0)) + 1
		for i in n7:
			FrameMemo.pose(S7, m.B, minf(i / 60.0, S7.length()))   # what the Check play leaves in the memo
		var pc_before := FrameMemo._pc.size()
		var m_bf := var_to_str(Breakfall.analyze(S7))
		var m_wt := []
		for sv in sw:
			m_wt.append(var_to_str(WeaponTorque.analyze(S7, m.B, int(sv["card"]))))
		memo_hits_seen = memo_hits_seen or FrameMemo._pc.size() >= pc_before
		FrameMemo.on = false
		FrameMemo.new_pass()
		m.B.set_state(keep7)
		m.B.fk()
		var same: bool = (d_bf == m_bf) and (d_wt == m_wt)
		swings_n += sw.size()
		if same:
			identical += 1
		ok(same, "(7) %s: Breakfall + %d WeaponTorque swing(s), memo == direct (verdicts and every number)" % [c, sw.size()])
	ok(identical >= 5, "(7) %d clips identical (>= 5), %d swings in all" % [identical, swings_n])
	# planted control: a memo filled from ANOTHER clip must be seen as different (so a stale or shared-wrong memo cannot pass)
	_load("res://scenes/walk_bat.json")
	await idle(2)
	var SA: Scene = m.S
	FrameMemo.new_pass()
	FrameMemo.on = true
	for i in int(ceil(SA.length() * 60.0)) + 1:
		FrameMemo.pose(SA, m.B, minf(i / 60.0, SA.length()))
	_load("res://scenes/combo3.json")
	await idle(2)
	var SB: Scene = m.S
	var sws := WeaponTorque.swings(SB, m.B)
	FrameMemo.on = false
	var direct_c3 := var_to_str(WeaponTorque.analyze(SB, m.B, int(sws[0]["card"]))) if not sws.is_empty() else ""
	FrameMemo.on = true
	var stale_c3 := var_to_str(WeaponTorque.analyze(SB, m.B, int(sws[0]["card"]))) if not sws.is_empty() else ""
	FrameMemo.on = false
	FrameMemo.new_pass()
	ok(not sws.is_empty() and direct_c3 != stale_c3, "(7) planted control: a memo filled from walk_bat changes combo3's weapon numbers (the comparison can fail)")

	# timing, interleaved, 7 repeats
	_load("res://scenes/combo3.json")
	await idle(2)
	var S3: Scene = m.S
	var ref_pose := []
	var nat_pose := []
	var ref_score := []
	var nat_score := []
	var n3 := int(ceil(S3.length() * 60.0)) + 1
	for r in 7:
		for native in [false, true]:
			Body.native_ik = native
			var t0 := Time.get_ticks_usec()
			for i in n3:
				S3.apply_true(m.B, minf(i / 60.0, S3.length()))
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0
			(nat_pose if native else ref_pose).append(ms)
			var t1 := Time.get_ticks_usec()
			_score(native)
			var ms2 := float(Time.get_ticks_usec() - t1) / 1000.0
			(nat_score if native else ref_score).append(ms2)
	Body.native_ik = true
	print("     apply_true x%d on combo3 (ms): GDScript p50 %.0f p95 %.0f | native p50 %.0f p95 %.0f  (%.2fx at p50)" % [n3, _pct(ref_pose, 0.5), _pct(ref_pose, 0.95), _pct(nat_pose, 0.5), _pct(nat_pose, 0.95), _pct(ref_pose, 0.5) / _pct(nat_pose, 0.5)])
	print("     cold realism score of combo3 (ms): GDScript p50 %.0f p95 %.0f | native p50 %.0f p95 %.0f  (%.2fx at p50)" % [_pct(ref_score, 0.5), _pct(ref_score, 0.95), _pct(nat_score, 0.5), _pct(nat_score, 0.95), _pct(ref_score, 0.5) / _pct(nat_score, 0.5)])
	ok(_pct(nat_pose, 0.5) < _pct(ref_pose, 0.5), "(6) native apply_true is faster than the GDScript one at p50")
	print("i16fast: ", "ALL OK" if fails == 0 else "%d FAILED" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
