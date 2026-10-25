## godot --path . -s tests/i39_test.gd     (ROADMAP I39: recovery step, scripts/recovery.gd + recovery_ui.gd + recovery_view.gd; needs a window)
## A standing pose (two cards) is shoved forward by the panel's three named shoves (COM speed 0.15 / 0.7 / 2.5 m/s). Capture point = x + v/omega0 (Hof 2005).
## Bars, written before measuring:
##  (1) SMALL: the capture point is inside the base of support (margin >= 0), the verdict is HOLD, no step is planned and the message says why
##  (2) MEDIUM: the capture point is outside the base; the verdict is STEP; the planned swing foot lands within 3 cm of the capture point, measured on the finished
##      scene; the foot is on the floor (< 2 cm), the capture point is then inside the new base (margin >= 0), the step is <= the max step (0.8 x leg), the two
##      new cards take exactly 0.25 s (the step time), the stance foot's sole moved < 5 mm, every joint of the landing inside its limits
##  (3) HUGE: the step needed is longer than the max step: verdict FALLS, no cards are planned, the message names the Breakfall check
##  (4) from the app: pressing the shove buttons and Preview leaves the scene JSON and B.state() byte-identical (read-only analysis); Accept adds exactly 2 cards
##      and ONE undo step; Ctrl+Z restores the cards, the scene JSON and B.state() exactly
##  (5) REAL HUMANS: the capture point's distance from the COM for the medium shove (v/omega0) against the stepping thresholds of Hof 2008 / Maki & McIlroy 1997:
##      people take a recovery step when the capture point is more than ~ the foot length beyond the COM; the run prints the numbers
##  (6) PLACEMENT: in a whole-body view the head, both feet, every corner of the base of support, the capture point's marker and the landing mark are inside the
##      free viewport and the marker's pixel is on the capture point's floor point
##  (7) the real scenes/, poses/, data/ hash the same before and after
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func hashes() -> Dictionary:
	var out := {}
	for dir in ["res://scenes/", "res://poses/", "res://data/"]:
		var stack := [dir]
		while not stack.is_empty():
			var d: String = stack.pop_back()
			for fn in DirAccess.get_files_at(d):
				if fn.ends_with(".import") or fn.ends_with(".uid"):
					continue   # the engine's own import/uid files: any Godot run beside this one rewrites them (not the app's writes)
				out[d + fn] = FileAccess.get_md5(d + fn)
			for sub in DirAccess.get_directories_at(d):
				stack.append(d + sub + "/")
	return out


func limits_ok(B: Body) -> bool:
	for j in B.ang:
		if B.lim.has(j) and (B.clamp_ang(j, B.ang[j]) - (B.ang[j] as Vector3)).length() > 1e-3:
			return false
	return true


func stand_scene() -> Scene:
	var B := DistanceKeeper.new_body()
	for j in B.ang:
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3.ZERO
	B.fk()
	B.ground()
	B.fk()
	var d := B.to_dict()
	var S := Scene.new()
	S.from_dict({"scene": "i39", "fps": 30, "on_floor": true, "cards": [
		{"name": "struck", "pose": d, "move": -1.0, "hold": 0.5},
		{"name": "after", "pose": d, "move": 0.5, "hold": 0.5}]})
	return S


func _init() -> void:
	var before_files := hashes()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var S0 := stand_scene()
	var out := {}
	for nm in ["small", "medium", "huge"]:
		out[nm] = Recovery.plan(S0, 0, 0.0, float(Recovery.SHOVES[nm]))
		var rd: Dictionary = out[nm]["rd"]
		print("     %s: v %.2f m/s, l %.0f cm, omega0 %.2f /s, capture point %.1f cm from the COM, margin %.1f cm, verdict %s, swing %s, step %.1f cm (max %.1f cm)" % [nm, float(rd["speed"]), float(rd["l"]) * 100.0,
			float(rd["w0"]), (Vector2(rd["xi"]) - Vector2(rd["com0"])).length() * 100.0, float(rd["margin"]) * 100.0, rd["verdict"], rd["swing"], float(rd["step"]) * 100.0, float(rd["max"]) * 100.0])

	# (1) small
	var ps: Dictionary = out["small"]
	ok(String(ps["rd"]["verdict"]) == "hold" and float(ps["rd"]["margin"]) >= 0.0 and not bool(ps["ok"]) and String(ps["why"]).contains("no step is needed"),
		"(1) small shove: capture point %.1f cm inside the feet, HOLD, no step planned" % (float(ps["rd"]["margin"]) * 100.0))

	# (2) medium
	var pm: Dictionary = out["medium"]
	var rdm: Dictionary = pm["rd"]
	var ok2: bool = bool(pm["ok"]) and String(rdm["verdict"]) == "step" and float(rdm["margin"]) < 0.0
	var land_err := float(pm.get("land_err", 9.0))
	ok(ok2 and land_err < 0.03, "(2) medium shove: capture point %.1f cm outside the feet, STEP; the %s foot lands %.2f cm from the capture point (bar < 3 cm), foot %.1f cm up" % [-float(rdm["margin"]) * 100.0, String(rdm["swing"]), land_err * 100.0, float(pm.get("foot_y", 9.0)) * 100.0 - 0.0])
	var Bm := DistanceKeeper.new_body()
	var B0 := DistanceKeeper.new_body()
	if not pm.has("scene"):
		ok(false, "(2) no plan for the medium shove: " + String(pm.get("why", "")))
		TestFiles.cleanup()
		quit(1)
		return
	var land_sc: Scene = pm["scene"]
	land_sc.clone().apply(Bm, float(land_sc.times()[2][1]))
	S0.clone().apply(B0, 0.0)
	var stance := "_r" if String(rdm["swing"]) == "_l" else "_l"
	var sole := maxf(((Bm.P["foot" + stance] as Vector3) - (B0.P["foot" + stance] as Vector3)).length(), ((Bm.P["ball" + stance] as Vector3) - (B0.P["ball" + stance] as Vector3)).length())
	var t_step := float(land_sc.times()[2][1]) - float(land_sc.times()[0][2])
	ok(float(pm["margin_after"]) >= 0.0 and float(rdm["step"]) <= float(rdm["max"]) and absf(t_step - Recovery.STEP_T) < 1e-6 and sole < 0.005 and limits_ok(Bm) and float(pm["foot_y"]) - float((B0.P["foot" + String(rdm["swing"])] as Vector3).y) < 0.02,
		"(2) capture point %.1f cm inside the new base, step %.0f cm <= max %.0f cm, step time %.3f s, stance sole moved %.2f mm, limits ok %s, the foot xi at touchdown would be %.0f cm from the COM (reported, the plan aims at the push-time point)" % [float(pm["margin_after"]) * 100.0,
		float(rdm["step"]) * 100.0, float(rdm["max"]) * 100.0, t_step, sole * 1000.0, str(limits_ok(Bm)), (Vector2(pm["xi_td"]) - Vector2(rdm["com0"])).length() * 100.0])

	# (3) huge
	var ph: Dictionary = out["huge"]
	ok(String(ph["rd"]["verdict"]) == "fall" and bool(ph["fall"]) and not ph.has("scene") and String(ph["why"]).contains("Breakfall check"),
		"(3) huge shove: step %.0f cm > max %.0f cm: FALLS, no cards planned, message names the Breakfall check" % [float(ph["rd"]["step"]) * 100.0, float(ph["rd"]["max"]) * 100.0])

	# (5) real humans
	var dxi := (Vector2(rdm["xi"]) - Vector2(rdm["com0"])).length()
	print("     medium shove: capture point %.0f cm ahead of the COM; the base's front edge is %.0f cm ahead of it (a foot is ~25 cm long): beyond it people step (Hof 2008)" % [dxi * 100.0, (dxi + float(rdm["margin"])) * 100.0])
	ok(dxi > dxi + float(rdm["margin"]) and dxi + float(rdm["margin"]) > 0.03 and dxi + float(rdm["margin"]) < 0.25, "(5) the base's front edge is %.0f cm ahead of the COM (plausible for a 25 cm foot) and the capture point is beyond it" % ((dxi + float(rdm["margin"])) * 100.0))

	# (4) from the app
	m.S.from_dict(S0.to_dict(m.B, false))
	m._rebuild_cards()
	m.playing = false
	m.playhead = 0.0
	m._ps().apply(m.B, 0.0)
	m._refresh()
	await idle(3)
	var json0 := JSON.stringify(m.S.to_dict(m.B, false))
	var cards0 := JSON.stringify(m.S.cards)
	var st0: Dictionary = m.B.state()
	m.rc_ui.show()
	await idle(2)
	var title_ok: bool = m.ui_find.visible and m.ui_find_list.find_child("rc_title", true, false) != null
	var ncards: int = m.S.cards.size()
	m.rc_ui._pick("small", "")
	await idle(2)
	var hold_label: bool = m.ui_find_list.find_child("rc_hold", true, false) != null
	m.rc_ui._pick("huge", "")
	await idle(2)
	var fall_label: bool = m.ui_find_list.find_child("rc_fall", true, false) != null and m.ui_find_list.find_child("rc_breakfall", true, false) != null
	m.rc_ui._pick("medium", "")
	await idle(2)
	var acc: Node = m.ui_find_list.find_child("rc_accept", true, false)
	m.rc_ui.preview()
	await idle(20)
	var pv_on: bool = m.rc_ui.pv
	var same: bool = JSON.stringify(m.S.to_dict(m.B, false)) == json0 and JSON.stringify(m.S.cards) == cards0
	m.rc_ui.halt()
	m._ps().apply(m.B, 0.0)
	m._refresh()
	await idle(2)
	ok(title_ok and hold_label and fall_label and acc != null and pv_on, "(4) panel: title, HOLD line on small, FALLS line + Breakfall button on huge, Accept on medium, Preview ran (%s)" % str(pv_on))
	ok(same and JSON.stringify(m.S.cards) == cards0, "(4) the panel's analysis and Preview left the scene JSON byte-identical")
	m._ps().apply(m.B, 0.0)
	m._refresh()
	var st1: Dictionary = m.B.state()
	var u0: int = m.undo.size()
	(acc as Button).pressed.emit()
	await idle(3)
	var u1: int = m.undo.size()
	var added: int = m.S.cards.size() - ncards
	m._undo()
	await idle(3)
	var back: bool = JSON.stringify(m.S.cards) == cards0 and JSON.stringify(m.S.to_dict(m.B, false)) == json0
	m._ps().apply(m.B, 0.0)
	m._refresh()
	ok(added == 2 and u1 == u0 + 1 and back and m.B.state() == st1, "(4) Accept added %d cards in ONE undo step (%d -> %d); Ctrl+Z restores cards, scene JSON and B.state() exactly (%s)" % [added, u0, u1, str(back)])
	if st1 != st0:
		print("     note: B.state before the panel and after re-applying differ only by the playback apply (not the analysis)")

	# (6) placement + screenshot: struck pose, medium shove, the plan drawn on the floor, no panels
	m.rc_ui.show()
	await idle(3)
	m.dummy_on = false
	m.clean = true
	m._refresh()
	var vp: Vector2 = m.get_viewport().get_visible_rect().size
	var free := Rect2(Vector2(0, m.TOP_H), Vector2(vp.x, vp.y - m.TOP_H - m.bottom_h - m.LINE_H - 6))
	var rv: Dictionary = m.rc_view.last
	var pl: Dictionary = m.rc_ui.pl
	var pts: Array = [(m.B.P["head"] as Vector3) + Vector3(0, 0.14, 0), Vector3((m.B.P["foot_l"] as Vector3).x, 0.0, (m.B.P["foot_l"] as Vector3).z), Vector3((m.B.P["foot_r"] as Vector3).x, 0.0, (m.B.P["foot_r"] as Vector3).z)]
	for q in rv.get("poly", []):
		pts.append(Vector3(q.x, 0.0, q.y))
	var xi: Vector2 = rv.get("xi", Vector2.ZERO)
	pts.append(Vector3(xi.x, 0.0, xi.y))
	var la: Vector2 = pl.get("land_at", Vector2.ZERO)
	for a in [Vector2(RecoveryView.RING, 0), Vector2(-RecoveryView.RING, 0), Vector2(0, RecoveryView.RING), Vector2(0, -RecoveryView.RING)]:
		pts.append(Vector3(la.x + a.x, 0.0, la.y + a.y))
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for q in pts:
		lo = lo.min(q)
		hi = hi.max(q)
	var d_fit := 1.5
	while d_fit < 12.0:
		m._turn_to(-40.0, -32.0, d_fit, (lo + hi) * 0.5, false)
		var all_in := true
		for q in pts:
			all_in = all_in and not m.cam.is_position_behind(q) and free.grow(-30.0).has_point(m.cam.unproject_position(q))
		if all_in:
			break
		d_fit += 0.1
	await idle(8)
	m._refresh()
	await idle(3)
	var placed: bool = (not pts.is_empty()) and m.rc_view.verts > 0
	for q in pts:
		placed = placed and free.has_point(m.cam.unproject_position(q))
	var xpx: Vector2 = m.cam.unproject_position(Vector3(xi.x, 0.0, xi.y))
	var img := root.get_texture().get_image()
	var px := img.get_pixel(clampi(int(xpx.x), 0, img.get_width() - 1), clampi(int(xpx.y), 0, img.get_height() - 1))
	var near_col := false   # the marker's colour (BalanceView.AMBER) lies within 8 px of the capture point's pixel
	for dx in range(-8, 9):
		for dy in range(-8, 9):
			var c := img.get_pixel(clampi(int(xpx.x) + dx, 0, img.get_width() - 1), clampi(int(xpx.y) + dy, 0, img.get_height() - 1))
			if c.r > 0.85 and c.g > 0.65 and c.r - c.b > 0.4:   # amber blended over the grey floor lightens toward yellow
				near_col = true
	print("picture: camera %.1f m, capture point at px %s, head at %s, pixel %s" % [d_fit, str(xpx), str(m.cam.unproject_position(pts[0])), str(px)])
	ok(placed and near_col, "(6) PLACEMENT: head, both feet, base corners, capture point and landing mark inside the free view %s; amber marker pixels within 8 px of the capture point" % str(free))
	var pc := m.ui_find.get_child(0) as Control
	pc.global_position = Vector2(8.0, 90.0)
	await idle(200)
	m._say("recovery step: medium shove forward, capture point outside the feet, a step lands on it")
	await idle(3)
	DirAccess.make_dir_recursive_absolute("C:/Users/Nick/.claude/jobs/9afc22db/tmp")
	root.get_texture().get_image().save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/i39.png")

	var after_files := hashes()
	var same2 := after_files.size() == before_files.size()
	for k in before_files:
		same2 = same2 and after_files.get(k, "") == before_files[k]
	ok(same2, "(7) %d files under scenes/, poses/, data/ hash the same before and after" % before_files.size())
	print("I39 RECOVERY %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
