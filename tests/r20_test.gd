## godot --path . -s tests/r20_test.gd     (ROADMAP round 2, R20: timed version snapshots; a window for the menu picture)
## A fake clock drives main.autover_tick() (5 min interval, last 30 timed kept) on a scene whose versions go to a temp
## folder of its own (versions_root; never scenes/, never user://). BARS, stated before measuring:
##  1 t=0 baseline (2 cards), card added at t=1: t=4 no snapshot, t=5 exactly one (v001, timed, diff "cards 2 -> 3")
##  2 no edits t=6..10: still 1 file (no snapshot without a change)
##  3 t=11 hold of card 1 0.3 -> 0.5 and the right upper arm turned on all 3 cards: t=15 exactly one more (v002) whose
##    diff names "cards 1 hold" with 0.30 and 0.50 and "right upper arm changed on 3 cards"; no "cards 2 -> 3"
##  4 a manual 'Save a version' at t=16 (v003, not timed); the tick at t=20 with no change adds nothing (3 files)
##  5 the menu lists the diff line under each version (disabled rows) and marks timed ones
##  6 35 more timed snapshots (each a real change, 5 min apart): exactly 30 timed + the manual one remain, the newest
##    timed is kept, the manual v003 is still there
##  7 restoring a timed snapshot = one undo step; Ctrl+Z (undo) brings the cards back
##  8 the whole scene's real files untouched: nothing under res://scenes/_versions was written
extends SceneTree

var fails := 0
var m: Node
var T := 0.0   # the fake clock, seconds
var DIR := ""


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func tick_at(minute: float) -> bool:
	T = minute * 60.0
	return m.autover_tick()


func files() -> Array:
	return m.versions()


func info(path: String) -> Dictionary:
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (d.get("version", {}) as Dictionary) if d is Dictionary else {}


func rm_tree(p: String) -> void:
	var d := DirAccess.open(p)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(p + "/" + f)
	for s in d.get_directories():
		rm_tree(p + "/" + s)
	DirAccess.remove_absolute(p)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	DIR = OS.get_temp_dir().path_join("r20_versions_%d" % OS.get_process_id()).replace("\\", "/")
	m.versions_root = DIR
	m.autover_clock = func(): return T
	m.autover_min = 5
	m.autover_keep = 30
	var real_before := DirAccess.open("res://scenes/_versions") != null
	m._new_scene()
	m.S.name = "_wip/zz_r20"
	m.B.ang["upperarm_r"] = Vector3(0, 0, 10)
	m.B.fk()
	m._card_add()
	m.B.ang["upperarm_r"] = Vector3(0, 0, 40)
	m.B.fk()
	m._card_add()
	m.S.cards[0]["hold"] = 0.3
	await idle()
	# 1
	var a := tick_at(0)
	m.B.ang["upperarm_r"] = Vector3(0, 0, 70)
	m.B.fk()
	m._card_add()   # t=1: a third card
	var b := tick_at(4)
	var c := tick_at(5)
	var f1: Array = files()
	var i1: Dictionary = info(f1[0]) if f1.size() > 0 else {}
	ok(not a and not b and c and f1.size() == 1 and bool(i1.get("auto", false)) and String(i1.get("diff", "")) == "cards 2 -> 3",
		"1 baseline t=0 (%s), t=4 (%s), t=5 (%s): %d file, timed %s, diff '%s'" % [a, b, c, f1.size(), i1.get("auto", false), i1.get("diff", "")])
	# 2
	var any := false
	for t in [6, 7, 8, 9, 10]:
		any = tick_at(t) or any
	ok(not any and files().size() == 1, "2 no edits t=6..10: %d file, snapshot taken: %s" % [files().size(), any])
	# 3
	m.S.cards[0]["hold"] = 0.5
	for card in m.S.cards:
		var q: Dictionary = card["pose"]["joints"]["upperarm_r"]
		q["side"] = float(q.get("side", 0.0)) + 30.0
	var t15 := tick_at(15)
	var f2: Array = files()
	var i2: Dictionary = info(f2[0]) if f2.size() > 0 else {}
	var dtxt := String(i2.get("diff", ""))
	ok(t15 and f2.size() == 2 and dtxt.contains("card 1") and dtxt.contains("hold 0.30 s -> 0.50 s") and dtxt.contains("right upper arm changed on 3 cards") and not dtxt.contains("cards 2 -> 3"),
		"3 t=15: %d files, diff '%s'" % [f2.size(), dtxt])
	# 4
	T = 16.0 * 60.0
	m._save_version()
	var d20 := tick_at(20)
	var f3: Array = files()
	var i3: Dictionary = info(f3[0]) if f3.size() > 0 else {}
	ok(not d20 and f3.size() == 3 and not bool(i3.get("auto", false)) and String(i3.get("diff", "")) != "",
		"4 manual v003 at t=16 (timed %s, diff '%s'); t=20 no change: %d files" % [i3.get("auto", false), i3.get("diff", ""), f3.size()])
	# 5 the version list
	m._versions_menu()
	var pm: PopupMenu = m.ui_versions.get_popup()
	var texts := []
	var diff_rows := 0
	for i in pm.item_count:
		if pm.is_item_separator(i):
			continue
		texts.append(pm.get_item_text(i))
		if pm.get_item_id(i) == 1 and pm.is_item_disabled(i) and pm.get_item_text(i).strip_edges().length() > 0:
			diff_rows += 1
	var has_hold := texts.any(func(t): return String(t).contains("hold 0.30 s -> 0.50 s"))
	var timed_rows := texts.filter(func(t): return String(t).ends_with("(timed)")).size()
	ok(diff_rows == 3 and has_hold and timed_rows == 2, "5 the list: %d diff rows, hold line shown %s, %d timed rows" % [diff_rows, has_hold, timed_rows])
	# picture: the version list with its diff lines
	pm.popup(Rect2i(Vector2i(300, 120), Vector2i(780, 0)))
	await idle(4)
	var img := root.get_texture().get_image()
	img.save_png("C:/Users/Nick/.claude/jobs/9afc22db/tmp/r20.png")
	pm.hide()
	# 7 restore one timed snapshot = one undo step
	var cards_now: int = m.S.cards.size()
	var u0: int = m.undo.size()
	var v1_idx: int = m._version_paths.size() - 1   # the oldest = v001 (2 cards -> 3 at snapshot time)
	m._open_version(m._version_paths[v1_idx])
	var after_n: int = m.S.cards.size()
	var steps: int = m.undo.size() - u0
	var hold_back := float(m.S.cards[0]["hold"])
	m._undo()
	var hold_undone := float(m.S.cards[0]["hold"])
	ok(steps == 1 and m.S.cards.size() == cards_now and after_n == 3 and is_equal_approx(hold_back, 0.3) and is_equal_approx(hold_undone, 0.5),
		"7 restored v001: %d cards, card 1 hold %.2f (+%d undo step); one undo: hold %.2f (was 0.50)" % [after_n, hold_back, steps, hold_undone])
	# 6 pruning: 35 more timed snapshots
	var made := 0
	for k in 35:
		m.S.cards[0]["hold"] = 0.6 + 0.01 * k
		if tick_at(25 + 5 * k):
			made += 1
	var all: Array = files()
	var autos := all.filter(func(p): return bool(info(p).get("auto", false)))
	var manual := all.filter(func(p): return not bool(info(p).get("auto", false)))
	var newest_n: int = int(info(all[0]).get("n", 0))
	ok(made == 35 and autos.size() == 30 and manual.size() == 1 and newest_n == 38 and int(info(manual[0]).get("n", 0)) == 3,
		"6 35 more taken, kept: %d timed + %d manual (manual is v%d), newest v%d" % [autos.size(), manual.size(), int(info(manual[0]).get("n", 0)) if manual.size() > 0 else -1, newest_n])
	# 8
	var real_after := DirAccess.open("res://scenes/_versions/_wip/zz_r20") != null
	ok(not real_after and real_before == (DirAccess.open("res://scenes/_versions") != null), "8 nothing written under res://scenes/_versions (zz_r20 folder there: %s)" % real_after)
	rm_tree(DIR)
	print("r20: %d failure(s)" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
