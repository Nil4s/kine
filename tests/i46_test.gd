## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/i46_test.gd     (ROADMAP I46: my hit reactions, scripts/hit_habits.gd; needs a window)
## Bars, written before measuring:
##  (1) 4 recorded edits, all x0.8 amplitude, +1 frame, recovery x1.0, in a journal under user://i46_<pid>/: habit() is on, n = 4, medians x0.8 / +1 frame.
##      The next reaction (a 12 m/s head hit), measured against the physics one with HitHabits.measure on the BAKED cards: amplitude 0.8 +-0.05, onset +1.0 +-0.35
##      frame (a frame = 1/30 s), recovery 1.0 +-0.25. The line reads "your usual x0.8 amplitude, +1 frame, recovery x1.0 (from 4 edits)".
##  (2) the physics-default key: the same hit again gives the original physics cards byte for byte (JSON), and its line says it is the physics default.
##  (3) with only 2 lessons the cards are the physics cards byte for byte and the line says "only 2 edits learned, 3 needed".
##  (4) in the app, an edit is a lesson: one reaction by the command, then every window card's deviation from the animation scaled x0.8 by hand; after the 2 s settle
##      (fake clock) the journal holds ONE lesson with amp 0.8 +-0.06 and delay 0 +-0.35 frame; a reaction that is undone instead gives NO lesson.
##  (5) in the app with 4 x0.8 / +1 frame lessons: the command's status line contains "your usual x0.8", "+1 frame", "from 4 edits"; it is ONE undo step and Ctrl+Z puts
##      the victim's cards back exactly; with the key pressed the cards equal the physics cards exactly.
##  (6) nothing is written outside user://i46_<pid>/: the real user://suggestion_journal.json is byte-identical (or still absent), no zz_suggestion_journal_<pid>.json
##      appears, and the folder holds only the journal files.
##  (7) placement: the reaction's line is the note over the view, inside the window, the struck fighter's head is on screen in the whole-body view; the picture is saved.
extends SceneTree

const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/i46.png"
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func stand_body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	b.ground()
	return b


func stand_scene(b: Body) -> Scene:
	var pose := b.to_dict()
	var s := Scene.new()
	s.from_dict({"scene": "zz_i46_stand", "fps": 30, "cards": [{"name": "a", "pose": pose, "move": -1.0, "hold": 2.0}, {"name": "b", "pose": pose, "move": 0.5, "hold": 3.0}]})
	return s


func striker() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


func hit_on(B: Body, part: String, side: float, v: float) -> Dictionary:
	var a: Array = B.cap(part)
	var mid := ((a[0] as Vector3) + (a[1] as Vector3)) * 0.5
	var r: float = float(B.rad[part])
	return {"t": 1.0, "kind": "hit", "zone": "X", "part": "bat_barrel", "on": part, "by": "hero", "vs": 1, "u": 0.6,
		"depth": 0.01, "speed": v, "at": mid + Vector3(side * r, 0, 0), "vec": Vector3(v, 0, 0)}


func scene_of(base: Scene, cards: Array) -> Scene:
	var s := base.clone()
	s.cards = cards.duplicate(true)
	return s


func lessons(sj: SuggestionJournal, n: int, J: float, amp := 0.8, delay := 1.0, rec := 1.0) -> void:
	for i in n:
		sj.add_habit(HitHabits.SRC, HitHabits.KIND, {"amp": amp, "delay": delay, "rec": rec, "J": J})


func _init() -> void:
	var dir := "user://i46_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(dir)
	var real := "user://suggestion_journal.json"
	var real0 := FileAccess.get_file_as_string(real) if FileAccess.file_exists(real) else "<absent>"
	var zz := "user://zz_suggestion_journal_%d.json" % OS.get_process_id()

	# (1)-(3) the maths, on a standing fighter
	var B := stand_body()
	var S0 := stand_scene(B)
	var h := hit_on(B, "head", -1.0, 12.0)
	var P := HitReaction.react(S0, B, Transform3D.IDENTITY, h, striker())
	var Jn := (P["J"] as Vector3).length()
	print("     physics: J %.2f kg m/s, window %.2f s, %d cards" % [Jn, float(P["t1"]) - float(P["t0"]), (P["cards"] as Array).size()])
	var hh := HitHabits.new(SuggestionJournal.new(dir + "/a.json"))
	lessons(hh.sj, 4, Jn)
	var hb := hh.habit(Jn, 30)
	ok(bool(hb["on"]) and int(hb["n"]) == 4 and absf(float(hb["amp"]) - 0.8) < 1e-6 and absf(float(hb["delay_f"]) - 1.0) < 1e-6, "(1) habit on from 4 lessons: %s" % hb["text"])
	var H := HitReaction.react(S0, B, Transform3D.IDENTITY, h, striker(), hh.chooser(30))
	var mm := HitHabits.measure(S0, scene_of(S0, P["cards"]), scene_of(S0, H["cards"]), B, float(P["t0"]), float(P["t1"]))
	print("     measured habit reaction vs physics: ", mm)
	ok(absf(float(mm["amp"]) - 0.8) <= 0.05, "(1) amplitude x%.3f (bar 0.8 +-0.05)" % float(mm["amp"]))
	ok(absf(float(mm["delay"]) - 1.0) <= 0.35, "(1) onset %+.2f frames (bar +1 +-0.35)" % float(mm["delay"]))
	ok(absf(float(mm["rec"]) - 1.0) <= 0.25, "(1) recovery x%.3f (bar 1.0 +-0.25)" % float(mm["rec"]))
	ok(hh.last_text == "your usual x0.8 amplitude, +1 frame, recovery x1.0 (from 4 edits)", "(1) the line: '%s'" % hh.last_text)
	var physics_json := JSON.stringify(P["cards"])
	hh.physics_only = true
	var K := HitReaction.react(S0, B, Transform3D.IDENTITY, h, striker(), hh.chooser(30))
	ok(JSON.stringify(K["cards"]) == physics_json and hh.last_text.contains("physics default"), "(2) the key restores the physics cards exactly: '%s'" % hh.last_text)
	hh.physics_only = false
	var hh2 := HitHabits.new(SuggestionJournal.new(dir + "/b.json"))
	lessons(hh2.sj, 2, Jn)
	var T := HitReaction.react(S0, B, Transform3D.IDENTITY, h, striker(), hh2.chooser(30))
	ok(JSON.stringify(T["cards"]) == physics_json and hh2.last_text.contains("only 2 edits learned, 3 needed"), "(3) 2 lessons keep the physics: '%s'" % hh2.last_text)
	var hh3 := HitHabits.new(SuggestionJournal.new(dir + "/c.json"))
	lessons(hh3.sj, 3, Jn)
	ok(bool(hh3.habit(Jn, 30)["on"]), "(3) 3 lessons are enough")

	# the app
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.sj = SuggestionJournal.new(dir + "/app.json")
	m.myhits.sj = m.sj
	var clk := [0.0]
	m.sj.now = func(): return clk[0]
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	var B2 := stand_body()
	m.S.actors.append({"name": "fighter 2", "xf": {"pos": [0.0, 1.2], "yaw": 180.0}, "scene": stand_scene(B2)})
	m._actors_sync()
	m._refresh()
	await idle()
	var xf2: Transform3D = m.actors_rt[1]["xf"]
	var hit := hit_on(m.actors_rt[1]["B"], "head", -1.0, 12.0)
	hit["at"] = xf2 * (hit["at"] as Vector3)
	hit["vec"] = xf2.basis * (hit["vec"] as Vector3)
	var rd := func(vk): return m.actors_rt[vk]["S"]

	# (4) an edit is a lesson (no lessons yet: the reaction is the physics one)
	m.fighter_hits = [hit]
	var cards0 := JSON.stringify(m.actors_rt[1]["S"].cards)
	var u0: int = m.undo.size()
	m._hit_react()
	var phys_app := JSON.stringify(m.actors_rt[1]["S"].cards)
	ok(phys_app != cards0 and m.ui_status.text.contains("physics default: only 0 edits learned"), "(4) with 0 lessons the reaction is physics and says why: '...%s'" % m.ui_status.text.right(90))
	m._undo()
	clk[0] += 5.0
	m.myhits.observe(m.undo.size(), rd, m.actors_rt[1]["B"])
	ok(m.sj.habit_rows(HitHabits.SRC, HitHabits.KIND).is_empty() and m.myhits.pending.is_empty(), "(4) an undone reaction is no lesson")
	m.fighter_hits = [hit]
	m._hit_react()
	ok(m.myhits.pending.size() == 1, "(4) the new reaction is watched")
	var base_sc: Scene = (m.myhits.pending[0]["base"] as Scene)
	var sc: Scene = m.actors_rt[1]["S"]
	var Bt: Body = m.actors_rt[1]["B"]
	var t0 := float(m.myhits.pending[0]["t0"])
	var t1 := float(m.myhits.pending[0]["t1"])
	var ts := sc.times()
	var edited := 0
	for i in sc.cards.size():
		var a: float = ts[i][1]
		if a >= t0 - 1e-6 and a < t1 - 1e-6:
			base_sc.apply(Bt, a)
			var g: Dictionary = Bt.ang.duplicate()
			Bt.from_dict(sc.cards[i]["pose"])
			for j in g:
				Bt.ang[j] = (g[j] as Vector3) + 0.8 * ((Bt.ang[j] as Vector3) - (g[j] as Vector3))
			Bt.fk()
			sc.cards[i]["pose"] = Bt.to_dict()
			edited += 1
	print("     scaled %d window cards by 0.8 by hand" % edited)
	clk[0] += 1.0
	m.myhits.observe(m.undo.size(), rd, Bt)
	ok(m.sj.habit_rows(HitHabits.SRC, HitHabits.KIND).is_empty(), "(4) not a lesson before the 2 s settle")
	clk[0] += 3.0
	m.myhits.observe(m.undo.size(), rd, Bt)
	var rows: Array = m.sj.habit_rows(HitHabits.SRC, HitHabits.KIND)
	print("     lesson: ", rows)
	var la := float(rows[0]["amp"]) if rows.size() > 0 else NAN
	var ld := float(rows[0]["delay"]) if rows.size() > 0 else NAN
	ok(rows.size() == 1 and absf(la - 0.8) <= 0.06 and absf(ld) <= 0.35, "(4) ONE lesson: amp %.3f (bar 0.8 +-0.06), delay %+.2f frames (bar 0 +-0.35)" % [la, ld])
	m._undo()
	ok(JSON.stringify(m.actors_rt[1]["S"].cards) == cards0 and m.undo.size() == u0, "(4) Ctrl+Z puts the victim's cards back exactly")

	# (5) four x0.8 / +1 frame lessons in the app
	m.sj.reset()
	lessons(m.sj, 4, Jn)
	m.fighter_hits = [hit]
	var u1: int = m.undo.size()
	m._hit_react()
	var line: String = m.ui_status.text
	print("     status: ", line)
	ok(line.contains("your usual x0.8") and line.contains("+1 frame") and line.contains("from 4 edits"), "(5) the line says your usual x0.8, +1 frame, from 4 edits")
	ok(m.undo.size() == u1 + 1 and JSON.stringify(m.actors_rt[1]["S"].cards) != phys_app, "(5) ONE undo step and the cards differ from the physics ones")
	m.yaw = 75.0
	m.pitch = -8.0
	m.dist = 5.2
	m.target = Vector3(0.0, 0.95, 0.0)
	m._cam()
	m.playhead = 1.0 + 0.15
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	await idle(6)
	if m.ui_toast != null:
		m.ui_toast.visible = false   # (the undo toast of the step before is not the picture's subject)
	await idle(2)
	var img: Image = m.get_viewport().get_texture().get_image()
	var vp: Rect2 = m.get_viewport().get_visible_rect()
	var strip: Rect2 = m.ui_note.get_global_rect() if m.ui_note != null else Rect2()
	ok(m.ui_note != null and m.ui_note.visible and vp.encloses(strip) and m.ui_note.text.contains("your usual x0.8"), "(7) the 'your usual' line is shown inside the window: %s of %s '%s'" % [strip, vp, m.ui_note.text if m.ui_note != null else ""])
	var Wh: Vector3 = m._stage_xf() * (xf2 * ((m.actors_rt[1]["B"] as Body).P["head"] as Vector3))
	var sp: Vector2 = m.cam.unproject_position(Wh)
	ok(not strip.intersects(Rect2(sp - Vector2(40, 40), Vector2(80, 80))), "(7) the note does not cover the struck head")
	ok(not m.cam.is_position_behind(Wh) and vp.grow(-20.0).has_point(sp), "(7) the struck fighter's head is on screen at %s" % sp)
	DirAccess.make_dir_recursive_absolute(SHOT.get_base_dir())
	var e := img.save_png(SHOT)
	ok(e == OK and img.get_width() > 0, "(7) picture saved to %s (%dx%d)" % [SHOT, img.get_width(), img.get_height()])
	m._undo()
	ok(JSON.stringify(m.actors_rt[1]["S"].cards) == cards0, "(5) Ctrl+Z puts the victim's cards back exactly")
	m.myhits.physics_only = true
	m.fighter_hits = [hit]
	m._hit_react()
	ok(JSON.stringify(m.actors_rt[1]["S"].cards) == phys_app, "(5) with the key pressed the cards equal the physics cards exactly")

	# (6) nothing outside user://i46_<pid>/
	var real1 := FileAccess.get_file_as_string(real) if FileAccess.file_exists(real) else "<absent>"
	var files := DirAccess.get_files_at(dir)
	print("     folder: ", files)
	ok(real1 == real0 and not FileAccess.file_exists(zz), "(6) the real journal is unchanged and no zz_suggestion_journal file appeared")
	ok(files.size() == 4 and files.has("app.json"), "(6) the folder holds only the journals (%d files)" % files.size())
	for f in files:
		DirAccess.remove_absolute(dir + "/" + f)
	DirAccess.remove_absolute(dir)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
