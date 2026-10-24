## godot --path . -s tests/i23_test.gd     (ROADMAP I23: my combos, scripts/combo_mine.gd + combo_ui.gd; needs a window)
## Synthetic clips under user:// (with the PID); the real scenes/ are only hashed. Bars, before measuring:
##  (1) jab-cross-hook in 2 clips (moves 0.15/0.20/0.15 and 0.17/0.22/0.13, holds 0.05/0.04/0.10 and 0.07/0.06/0.12) is found ONCE
##      with count 2 in 2 clips, mean moves 0.16/0.21/0.14 and holds 0.06/0.05/0.11 within 0.5 ms; its 2-card parts are not listed separately
##  (2) slash-stab seen once is not offered (no combo names slash or stab)
##  (3) the name reads "jab-cross-hook, your 0.16/0.21/0.14 rhythm, used 2 times in 2 clips"
##  (4) pick -> ghost (the scene JSON byte-identical); Enter (the app's key path) = ONE undo step, +3 cards, each move/hold within 1 ms of the mean;
##      Ctrl+Z restores the cards exactly
##  (5) a pick on the other side mirrors the poses (== Scene.mirror_card of his card); same side copies them unchanged
##  (6) the cache: a second read is "cached"; rewriting a clip makes it mined again
##  (7) the source clips are byte-equal after everything (md5), and the real scenes/, poses/, data/ hash the same
##  (8) real scenes: the panel lists combos mined from Nick's own clips (>= 1), is on screen, and the ghost is drawn in the whole-body view
##      (visible, its head within 1.5 m of the live body's head)
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


func clip(cards: Array, poses: Dictionary, nm: String) -> Dictionary:
	var cs := []
	for c in cards:
		cs.append({"name": c[0], "pose": (poses[c[1]] as Dictionary).duplicate(true), "move": c[2], "hold": c[3]})
	return {"scene": nm, "fps": 30, "cards": cs}


func write(path: String, d: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	m._unhandled_input(ev)


func _init() -> void:
	var before_files := hashes()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var th: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/thrust.json"))
	var poses := {"ready": th["cards"][0]["pose"], "chamber": th["cards"][6]["pose"], "thrust": th["cards"][9]["pose"]}
	var pid := OS.get_process_id()
	var tmp := "user://zz_i23_%d/" % pid
	var cache := "user://zz_i23_cache_%d.json" % pid
	DirAccess.make_dir_recursive_absolute(tmp)
	write(tmp + "a.json", clip([["ready", "ready", -1.0, 0.3], ["jab", "thrust", 0.15, 0.05], ["cross", "chamber", 0.20, 0.04], ["hook", "thrust", 0.15, 0.10]], poses, "a"))
	write(tmp + "b.json", clip([["ready", "ready", -1.0, 0.3], ["jab", "thrust", 0.17, 0.07], ["cross", "chamber", 0.22, 0.06], ["hook", "thrust", 0.13, 0.12]], poses, "b"))
	write(tmp + "c.json", clip([["ready", "ready", -1.0, 0.3], ["slash", "thrust", 0.30, 0.05], ["stab", "chamber", 0.40, 0.05]], poses, "c"))
	var src_md5 := {}
	for fn in DirAccess.get_files_at(tmp):
		src_md5[fn] = FileAccess.get_md5(tmp + fn)

	# (1)-(3) mining
	var r := ComboMine.mined([tmp], m.B, cache)
	m._ps().apply(m.B, m.playhead)
	var combos: Array = r["combos"]
	print("     mined %d combos from %d clips in %.0f ms: %s" % [combos.size(), r["clips"], r["ms"], JSON.stringify(combos.map(func(c): return c["text"]))])
	var c0: Dictionary = combos[0] if not combos.is_empty() else {}
	var wm := [0.16, 0.21, 0.14]
	var wh := [0.06, 0.05, 0.11]
	var worst := 0.0
	if not c0.is_empty():
		for k in 3:
			worst = maxf(worst, maxf(absf(float(c0["moves"][k]) - wm[k]), absf(float(c0["holds"][k]) - wh[k])))
	ok(combos.size() == 1 and not c0.is_empty() and String(c0["name"]) == "jab-cross-hook" and int(c0["count"]) == 2 and int(c0["clips"]) == 2 and worst <= 0.0005,
		"(1) one combo jab-cross-hook, count 2 in 2 clips, worst mean timing error %.3f ms (<= 0.5 ms); the 2-card parts are not listed" % (worst * 1000.0))
	var named := false
	for c in combos:
		named = named or String(c["name"]).contains("slash") or String(c["name"]).contains("stab")
	ok(not named and not r["cached"], "(2) slash-stab (seen once) is not offered")
	ok(not c0.is_empty() and String(c0["text"]) == "jab-cross-hook, your 0.16/0.21/0.14 rhythm, used 2 times in 2 clips", "(3) the name: '%s'" % (c0.get("text", "") if not c0.is_empty() else ""))

	# (4) insert
	m.cm_ui.dirs = [tmp]
	m.cm_ui.cache = cache
	m.cm_ui.data = {}
	var tgt := clip([["ready", "ready", -1.0, 0.3], ["wind-up", "chamber", 0.30, 0.10], ["recover", "ready", 0.50, 0.20]], poses, "mine")
	m.S.from_dict(tgt)
	m._rebuild_cards()
	await idle()
	m.cm_ui.show()
	await idle(3)
	m.sel_card = 1
	m.sel_end = -1
	var json0 := JSON.stringify(m.S.to_dict(m.B, false))
	var cards0 := JSON.stringify(m.S.cards)
	m.cm_ui.pick(0)
	await idle(3)
	var gh: bool = m.ov._fg_on
	ok(m.cm_ui.pv != null and gh and JSON.stringify(m.S.to_dict(m.B, false)) == json0 and JSON.stringify(m.S.cards) == cards0, "(4) pick: the ghost is up (%s) and the scene JSON is byte-identical" % str(gh))
	var u0: int = m.undo.size()
	key(KEY_ENTER)
	await idle(2)
	var S: Scene = m.S
	var tm := 0.0
	if S.cards.size() == 6:
		for k in 3:
			tm = maxf(tm, maxf(absf(float(S.cards[2 + k]["move"]) - wm[k]), absf(float(S.cards[2 + k]["hold"]) - wh[k])))
	ok(m.undo.size() == u0 + 1 and S.cards.size() == 6 and tm <= 0.001 and String(S.cards[2]["name"]) == "jab" and m.cm_ui.pv == null,
		"(4) Enter: one undo step (%d -> %d), 3 cards inserted after card 2 (jab, cross, hook), worst timing error %.3f ms (<= 1 ms)" % [u0, m.undo.size(), tm * 1000.0])
	m._undo()
	await idle(2)
	ok(JSON.stringify(m.S.cards) == cards0 and JSON.stringify(m.S.to_dict(m.B, false)) == json0, "(4) Ctrl+Z restores the cards and the scene JSON exactly")

	# (5) mirror
	var lead := String(c0["lead"])
	var other := "l" if lead == "r" else "r"
	var kept := ComboMine.cards_for(c0, lead)
	var flipped := ComboMine.cards_for(c0, other)
	var a_d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(tmp + "a.json"))
	var A2 := Scene.new()
	A2.from_dict(a_d)
	var M := DistanceKeeper.new_body()
	var want_flip := Scene.mirror_card(A2.cards[1], M)
	ok(JSON.stringify(kept[0]["pose"]) == JSON.stringify(A2.cards[1]["pose"]) and JSON.stringify(flipped[0]["pose"]) == JSON.stringify(want_flip["pose"]) and JSON.stringify(flipped[0]["pose"]) != JSON.stringify(kept[0]["pose"]),
		"(5) picked side %s = lead %s: his poses unchanged; side %s: Scene.mirror_card's poses (and they differ)" % [lead, lead, other])

	# (6) the cache
	var r2 := ComboMine.mined([tmp], m.B, cache)
	OS.delay_msec(1200)
	write(tmp + "c.json", clip([["ready", "ready", -1.0, 0.3], ["slash", "thrust", 0.30, 0.05], ["stab", "chamber", 0.41, 0.05]], poses, "c"))
	var r3 := ComboMine.mined([tmp], m.B, cache)
	m._ps().apply(m.B, m.playhead)
	ok(bool(r2["cached"]) and not bool(r3["cached"]), "(6) second read cached (%.1f ms), after a clip is rewritten it is mined again (%.1f ms)" % [r2["ms"], r3["ms"]])

	# (7) the source clips
	var same_src := true
	for fn in ["a.json", "b.json"]:
		same_src = same_src and FileAccess.get_md5(tmp + fn) == src_md5[fn]
	ok(same_src, "(7) the source clips a.json and b.json are byte-equal (md5) after mining, pick, insert and undo")

	# (8) the real scenes + screenshot
	m.cm_ui.dirs = ["res://scenes/"]
	m.cm_ui.cache = "user://zz_i23_real_%d.json" % pid
	m.cm_ui.data = {}
	var cm: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json"))
	m.S.from_dict(cm)
	m._rebuild_cards()
	await idle(2)
	m.cm_ui.show()
	await idle(4)
	var real: Array = m.cm_ui.data["combos"]
	print("     Nick's real clips: %d combos" % real.size())
	for c in real:
		print("       " + String(c["text"]) + "   [" + ", ".join(c["files"]) + "]")
	m.sel_card = 5
	m.sel_end = -1
	m.cm_ui.pick(0)
	await idle(4)
	var pr: Rect2 = (m.ui_find.get_child(0) as Control).get_global_rect()
	var vr := Rect2(Vector2.ZERO, m.get_viewport().get_visible_rect().size)
	var g0: Node3D = m.ov._ghosts[2][0]
	var gd := 99.0
	if m.cm_ui.pv != null:
		var GB := DistanceKeeper.new_body()
		m.cm_ui.pv.apply(GB, m.cm_ui.pv_t)
		gd = (GB.P["head"] as Vector3).distance_to(m.B.P["head"])
	ok(real.size() >= 1 and m.ui_find.visible and vr.encloses(pr.grow(-1.0)) and m.cm_ui.pv != null and g0.visible and gd < 1.5,
		"(8) panel on screen at %s with %d combos from Nick's clips; ghost visible=%s, head %.2f m from the live body's (< 1.5 m)" % [str(pr), real.size(), str(g0.visible), gd])
	m._say("my combos: %d mined from your clips; the ghost shows the pick after card 5, Enter inserts it" % real.size())
	await idle(240)   # the earlier step's "Undid: ..." toast has gone
	m._say("my combos: %d mined from your clips; the ghost shows the pick after card 5, Enter inserts it" % real.size())
	await idle(3)
	root.get_texture().get_image().save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/i23.png")
	m.cm_ui.halt()
	var after_files := hashes()
	var same := after_files.size() == before_files.size()
	for k in before_files:
		same = same and after_files.get(k, "") == before_files[k]
	ok(same, "(7) %d files under scenes/, poses/, data/ hash the same before and after" % before_files.size())
	for fn in DirAccess.get_files_at(tmp):
		DirAccess.remove_absolute(tmp + fn)
	DirAccess.remove_absolute(tmp)
	DirAccess.remove_absolute(cache)
	DirAccess.remove_absolute(m.cm_ui.cache)
	print("I23 MY COMBOS %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	quit(1 if fails > 0 else 0)
