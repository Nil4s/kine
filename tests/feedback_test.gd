## godot --path . -s tests/feedback_test.gd     (GATES EE3, UPGRADES #41; a real window, real keys)
## FEEDBACK YOU CAN SEE: two named steps, then a REAL Ctrl+Z: a toast over the view says "Undid: <the step's name>"
## (the same name the History lists) at once, and it is gone within 2 s; Ctrl+Z twice fast: the second replaces the
## first (one toast, the newer name, still up after the first's time would have run out); Ctrl+Y: "Redid: ...". A Fix
## that keeps: the cards it changed (found here by comparing the cards before and after) flash, and only those;
## within 1 s they are back to normal. A Button's pressed look differs from its normal one (the theme's).
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


func key(k: Key, ctrl := true) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = ctrl
		e.pressed = down
		root.push_input(e)
		await process_frame


func wait(s: float) -> void:
	await create_timer(s).timeout


func toast() -> String:
	var t: Label = m.ui_toast
	return t.text if t != null and t.is_visible_in_tree() else ""


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._new_scene()
	await idle(2)
	# two named steps
	for j in ["upperarm_l", "thigh_r"]:
		m.sel = j
		m._push_undo()
		m.B.ang[j] = m.B.ang[j] + Vector3(0, 0, 10)
		m.B.fk()
		m._say("ROTATING the " + m.nice(j))
	await idle(2)
	var name2: String = m._step_label(m.undo[-1])
	var name1: String = m._step_label(m.undo[-2])
	ok(toast() == "", "1 before any undo: no toast")
	await key(KEY_Z)
	var t1 := toast()
	ok(t1 == "Undid: " + name2, "2 a real Ctrl+Z: at once the toast '%s' (the step: '%s')" % [t1, name2])
	await wait(1.0)
	await key(KEY_Z)
	var t2 := toast()
	await wait(0.9)   # 1.9 s after the first: the first's time is over, the second's not
	var t2b := toast()
	ok(t2 == "Undid: " + name1 and t2b == t2, "3 Ctrl+Z again 1 s later: the toast replaced ('%s'), still up 0.9 s on ('%s')" % [t2, t2b])
	await wait(1.0)
	ok(toast() == "", "4 gone within 2 s of the last one")
	await key(KEY_Y)
	var t3 := toast()
	ok(t3 == "Redid: " + name1, "5 a real Ctrl+Y: '%s'" % t3)
	# a Fix that keeps
	var flashed := []
	var changed := []
	var tried := 0
	for f in DirAccess.get_files_at("res://scenes/"):
		if not f.ends_with(".json") or not changed.is_empty():
			continue
		m._load_scene("res://scenes/" + f)
		m._rebuild_cards()
		if m.S.cards.size() < 2:
			continue
		m._check()
		for fd in m.findings.duplicate():
			if tried >= 8:
				break
			if Fixer.label(fd, m.S) == "":   # as the Check list: a Fix button only where there is a fix
				continue
			tried += 1
			var before: Array = m.S.cards.duplicate(true)
			var nu: int = m.undo.size()
			await m._fix(fd)
			if m.undo.size() == nu:
				continue
			for i in m.S.cards.size():
				if JSON.stringify(before[i]) != JSON.stringify(m.S.cards[i]):
					changed.append(i)
			await idle(1)
			for i in m.S.cards.size():
				var pc: Control = m.ui_cards.get_node("card_%d" % (i + 1))
				if pc.modulate.r > 1.2:
					flashed.append(i)
			ok(not changed.is_empty() and flashed == changed,
				"6 a Fix kept on %s (%s): cards changed %s, cards flashing %s (only those)" % [f, fd["rule"], changed, flashed])
			break
	ok(not changed.is_empty(), "   a Fix that keeps was found (%d tried)" % tried)
	await wait(1.0)
	var lit := []
	for i in m.S.cards.size():
		if not (m.ui_cards.get_node("card_%d" % (i + 1)) as Control).modulate.is_equal_approx(Color.WHITE):
			lit.append(i)
	ok(lit.is_empty(), "7 1 s later every card back to normal (still lit: %s)" % [lit])
	var b := Button.new()
	m.ui_root.add_child(b)
	await idle(1)   # main names new nodes deferred: let that run before the button goes
	var sn: StyleBox = b.get_theme_stylebox("normal")
	var sp: StyleBox = b.get_theme_stylebox("pressed")
	ok(sn is StyleBoxFlat and sp is StyleBoxFlat and not (sn as StyleBoxFlat).bg_color.is_equal_approx((sp as StyleBoxFlat).bg_color),
		"8 a button's pressed look differs from its normal one (%s -> %s)" % [(sn as StyleBoxFlat).bg_color, (sp as StyleBoxFlat).bg_color])
	b.queue_free()
	print("FEEDBACK: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
