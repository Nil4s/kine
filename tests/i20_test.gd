## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/i20_test.gd     (Innovations I20; a window)
## FEINT MAKER (scripts/feint.gd, feint_ui.gd; the command "Make this a feint"). THE FIXTURE is combo3.json (read only), its CONTACT card (card 3,
## the bat swing, index 2), fighter 2 (a stand pose facing the hero) put where the swing lands (first spot of a short list at which the tip gets
## inside its body), with a counter block (I3) placed on the strike. Bars, written before the numbers:
##   1 STOP:     the feint's arrival tip is 40-60 % of the original strike's reach (chord start -> arrival), re-measured on the new scene
##   2 LINE:     the new scene's tip follows the ORIGINAL scene's tip within 2 cm over the first 40 % of the feint's time (9 samples)
##   3 REACTION: the feint's stop comes >= 0.2 s (Counter.REACT) after the wind-up becomes readable (the move into the wind-up begins)
##   4 REAL:     every variant (>= 2): the real strike's tip comes within 2 cm of the defender's surface (re-measured, 1/120 s)
##   5 COACH:    the real strike's move is inside the human range of its own travel and the coach has no STRIKE line for it
##   6 COUNTER:  the defender's counter card now arrives when the feint stops (>= wind-up + REACT + MV), every later card of his keeps its time
##   7 UNCHANGED: while the ghosts show, both fighters' cards (JSON) are identical; Preview does not change them either
##   8 ACCEPT:   Tab cycles; Enter is ONE undo step; the attacker has feint + re-chamber + real strike; Ctrl+Z restores both fighters' cards exactly
##   9 PLACEMENT: both ghosts stand on the attacker (node at his placement), labels inside the window; the screenshot
extends SceneTree

var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i20.png"
const SPOTS := [[0.4, 1.1], [0.6, 0.9], [0.4, 0.9], [0.0, 1.1], [0.6, 1.1], [0.2, 1.1], [0.0, 1.0], [0.0, 0.9]]
const CI := 2


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func stand_scene() -> Scene:
	var sb := DistanceKeeper.new_body()
	sb.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	sb.ground()
	var pose := sb.to_dict()
	var s := Scene.new()
	s.from_dict({"scene": "zz_still", "fps": 30, "cards": [{"name": "a", "pose": pose, "move": -1.0, "hold": 2.0}, {"name": "b", "pose": pose, "move": 0.5, "hold": 3.0}]})
	return s


func xf_at(x: float, z: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0, z))


func _init() -> void:
	var AS := Scene.new()
	AS.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var DS := stand_scene()
	var pos := []
	var found := false
	for sp in SPOTS:
		var P := Counter.strike(AS, Transform3D.IDENTITY, DS, xf_at(sp[0], sp[1]), CI)
		if bool(P["ok"]) and bool(P["contact"]):
			pos = sp
			found = true
			break
	ok(found, "FIXTURE: combo3 card %d lands on fighter 2 at %s" % [CI + 1, pos])
	if not found:
		quit(1)
		return
	var dxf := xf_at(pos[0], pos[1])
	var axf := Transform3D.IDENTITY
	# a counter block on the strike (I3), made the way the app makes it
	var sg := Counter.suggest(AS, axf, DS, dxf, float(AS.times()[CI][1]) - 0.02)
	var cn := -1
	for p in sg.get("list", []):
		if bool(p["ok"]) and String(p["kind"]) == "BLOCK":
			cn = PoseCopy.card_at(DS, float(p["t"]), p["pose"], "counter block", {"steps": {"_l": [0.0, 0.0, 0.0], "_r": [0.0, 0.0, 0.0]}})
			break
	ok(cn >= 0, "FIXTURE: the defender has a counter block card (card %d, arrives %.3f s)" % [cn + 1, float(DS.times()[maxi(cn, 0)][1])])
	var dcards0 := JSON.stringify(DS.cards)
	var acards0 := JSON.stringify(AS.cards)
	var f := Feint.make(AS, axf, DS, dxf, CI)
	ok(bool(f["ok"]), "Feint.make ok (%s)" % String(f.get("why", "")))
	if not bool(f["ok"]):
		quit(1)
		return
	var t0: float = f["t0"]
	var t_read: float = f["t_read"]
	var Tf: float = f["Tf"]
	print("     strike move starts %.3f s, arrives %.3f s, reach %.1f cm, feint %.3f s (bias %.2f, fit %.2f cm), wind-up reads from %.3f s" % [t0, float(f["t_arr"]), float(f["R"]) * 100.0, Tf, float(f["bias"]), float(f["dev"]) * 100.0, t_read])
	ok(JSON.stringify(AS.cards) == acards0 and JSON.stringify(DS.cards) == dcards0, "make() writes nothing into the scenes it reads")
	var B := Counter.scratch(AS)
	var DB := Counter.scratch(DS)
	var opts: Array = f["options"]
	ok(opts.size() >= 2, "offers %d variants (>= 2): %s" % [opts.size(), ", ".join(opts.map(func(o): return String(o["label"])))])
	var Bo := Counter.scratch(AS)
	var base_chk := Feint.check(AS)
	for o in opts:
		var N: Scene = o["scene"]
		var kf := int(o["k_feint"])
		var ts := N.times()
		var lbl := String(o["label"])
		# 1 STOP
		AS.apply(Bo, t0)
		var tip0: Vector3 = Choreo.tip(Bo, axf, DB, dxf)["p"]
		AS.apply(Bo, float(f["t_arr"]))
		var R_re := tip0.distance_to(Choreo.tip(Bo, axf, DB, dxf)["p"])
		N.apply(B, float(ts[kf][1]))
		var d_stop := tip0.distance_to(Choreo.tip(B, axf, DB, dxf)["p"])
		ok(d_stop / R_re >= 0.4 and d_stop / R_re <= 0.6, "1 STOP [%s]: the feint stops at %.1f%% of the reach (%.1f of %.1f cm)" % [lbl, d_stop / R_re * 100.0, d_stop * 100.0, R_re * 100.0])
		# 2 LINE
		var dev := 0.0
		var span := float(ts[kf][1]) - t0
		for k in range(0, 9):
			var t := t0 + span * 0.4 * float(k) / 8.0
			AS.apply(Bo, t)
			N.apply(B, t)
			dev = maxf(dev, (Choreo.tip(Bo, axf, DB, dxf)["p"] as Vector3).distance_to(Choreo.tip(B, axf, DB, dxf)["p"]))
		ok(dev <= 0.02, "2 LINE [%s]: the tip follows the original within %.2f cm over the first 40%% of the feint (<= 2)" % [lbl, dev * 100.0])
		# 3 REACTION
		var gap_r := float(ts[kf][1]) - t_read
		ok(gap_r >= Counter.REACT - 1e-6, "3 REACTION [%s]: the feint stops %.3f s after the wind-up is readable (>= %.1f); the feint's own move is %.3f s" % [lbl, gap_r, Counter.REACT, Tf])
		# 4 REAL
		var kr := int(o["k_real"])
		var gap := INF
		var t_a := float(ts[kr][0])
		var t_b := float(ts[kr][1])
		for i in int(ceil((t_b - t_a) * 120.0)) + 1:
			var t := minf(t_a + float(i) / 120.0, t_b)
			N.apply(B, t)
			DS.apply(DB, t)
			gap = minf(gap, float(Choreo.surface_gap(Choreo.tip(B, axf, DB, dxf)["p"], DB, dxf)["gap"]))
		ok(gap <= 0.02, "4 REAL [%s]: the real strike's tip comes to %.1f cm of the defender (<= 2)" % [lbl, gap * 100.0])
		# 5 COACH
		var tr := TimingCoach._travel(N, B, t_a, t_b)
		var lo_hi := TimingCoach.peak_range(float(tr[0]))
		var mv := N.move_time(kr)
		var sugs := TimingCoach.compute(N, B, {}).filter(func(s): return int(s["card"]) == kr and String(s["kind"]) == "STRIKE")
		var cap := maxf(lo_hi[0], N.move_time(int(o["k_re"])) / TimingCoach.ANTIC_RATIO)
		print("     [%s] travel %.2f m, coach range %.3f-%.3f s (fist), cap %.3f, real move %.3f s, re-chamber %.3f s" % [lbl, tr[0], lo_hi[0], lo_hi[1], cap, mv, N.move_time(int(o["k_re"]))])
		ok(sugs.is_empty(), "5 COACH [%s]: the timing coach has no STRIKE line for the real strike (move %.3f s)" % [lbl, mv])
		ok(mv >= lo_hi[0] - 0.005 and mv <= minf(lo_hi[1], cap) + 0.005, "5 COACH [%s]: the real move %.3f s is inside the human range" % [lbl, mv])
		# 6 COUNTER
		if o["def"] != null:
			var D2: Scene = o["def"]
			var want := maxf(float(ts[kf][1]), t_read + Counter.REACT + Counter.MV)
			var arr := float(D2.times()[cn][1])
			ok(absf(arr - want) <= 0.005, "6 COUNTER [%s]: the counter card arrives %.3f s (feint stop %.3f; was %.3f)" % [lbl, arr, want, float(DS.times()[cn][1])])
			var same := true
			var tsd := DS.times()
			var tsn := D2.times()
			for k in range(cn + 1, DS.cards.size()):
				if absf(float(tsd[k][1]) - float(tsn[k][1])) > 0.002:
					same = false
			ok(same, "6 COUNTER [%s]: every later card of the defender keeps its time" % lbl)
		else:
			ok(false, "6 COUNTER [%s]: the counter card was not moved" % lbl)
		var fl := Feint.check(N)
		var red := fl.filter(func(x): return x["sev"] == "FAIL")
		var rn := Feint.red_new(fl, base_chk)
		print("     [%s] Check: %d findings, %d red, %d NEW red%s" % [lbl, fl.size(), red.size(), rn.size(), "" if rn.is_empty() else ": " + ", ".join(rn.map(func(x): return "%s@%.2f" % [x["rule"], x["t"]]))])

	# the app
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": pos, "yaw": 180.0}, "scene": DS.clone()})
	m._actors_sync()
	m._refresh()
	await idle()
	ok(m._fighters_on() and m.actors_rt.size() == 2, "two fighters in the app")
	m.playhead = float(AS.times()[CI][1]) - 0.05
	m._ps().apply(m.B, m.playhead)
	m.yaw = 90.0
	m.pitch = -6.0
	m.dist = 5.0
	m.target = Vector3(0.3, 1.35, 0.6)
	m._cam()
	m._refresh()
	await idle(2)
	var before := JSON.stringify([m.actors_rt[0]["S"].cards, m.actors_rt[1]["S"].cards])
	var n0: int = m.undo.size()
	var rr: Dictionary = m.feint_ui.start(CI)
	ok(bool(rr.get("ok", false)) and m.feint_ui.on, "the command shows the ghosts")
	await idle(3)
	var ui = m.feint_ui
	ok(before == JSON.stringify([m.actors_rt[0]["S"].cards, m.actors_rt[1]["S"].cards]) and m.undo.size() == n0, "7 UNCHANGED: both fighters' cards identical while the ghosts show, no undo step")
	ui.preview()
	for i in 12:
		ui.tick(0.1)
	ok(before == JSON.stringify([m.actors_rt[0]["S"].cards, m.actors_rt[1]["S"].cards]) and m.undo.size() == n0, "7 UNCHANGED: after Preview played, still identical")
	ui.pv = null
	# 9 PLACEMENT
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var xf: Transform3D = m.actors_rt[0]["xf"]
	var good := true
	for g in [ui._fg, ui._rg]:
		var nd: Node3D = g["node"]
		if not nd.visible or nd.transform.origin.distance_to(xf.origin) > 1e-3:
			good = false
		var lp: Vector3 = (g["label"] as Label3D).global_position
		var sp: Vector2 = m.cam.unproject_position(lp)
		print("     label at ", sp)
		if sp.x < 0 or sp.y < 0 or sp.x > vp.x or sp.y > vp.y or m.cam.is_position_behind(lp):
			good = false
	ok(good, "9 PLACEMENT: both ghosts at the attacker's placement, labels inside the window (%s)" % vp)
	var img: Image = m.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(SHOT.get_base_dir())
	var e := img.save_png(SHOT)
	ok(e == OK and img.get_width() > 0, "screenshot saved to %s (error %d)" % [SHOT, e])
	# 8 ACCEPT
	var k0: int = ui.sel
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	m._unhandled_input(tab)
	ok(ui.sel == (k0 + 1) % (ui.res["options"] as Array).size(), "Tab picks the next variant (%d -> %d)" % [k0, ui.sel])
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	var ncard0: int = m.actors_rt[0]["S"].cards.size()
	m._unhandled_input(enter)
	ok(m.undo.size() == n0 + 1 and not ui.on, "8 ACCEPT: Enter is ONE undo step (%d -> %d), ghosts put away" % [n0, m.undo.size()])
	var cs: Array = m.actors_rt[0]["S"].cards
	ok(cs.size() == ncard0 + 2 and String(cs[CI]["name"]) == "feint" and String(cs[CI + 1]["name"]) == "re-chamber" and String(cs[CI + 2]["name"]).contains("real"), "8 ACCEPT: the attacker has feint + re-chamber + real strike (%d -> %d cards: %s)" % [ncard0, cs.size(), ", ".join(cs.slice(CI, CI + 3).map(func(c): return String(c["name"])))])
	m._undo()
	ok(before == JSON.stringify([m.actors_rt[0]["S"].cards, m.actors_rt[1]["S"].cards]) and m.undo.size() == n0, "8 ACCEPT: Ctrl+Z restores both fighters' cards exactly and the undo list")
	print("fails: ", fails)
	quit(1 if fails > 0 else 0)
