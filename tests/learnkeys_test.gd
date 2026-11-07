## godot --headless --path . -s tests/learnkeys_test.gd   (lane L114: ROADMAP_400 P18 learn-from-me hotkeys)
## Bars written BEFORE the code (scripts/learn_keys.gd). The threshold is LearnKeys.THRESHOLD = 5 runs, stated in the code and fixed here:
##  1. a command run 5x through the real S-box path is offered a key; one run 1x is not; one run 4x is not
##  2. the offered key is free against the real bindings (registry keys, built-in keys, page keys, main's fixed keys)
##  3. accept binds it, and a real key InputEvent then runs the command
##  4. decline: that command is never offered again this session (and not after a restart)
##  5. a command that already has a hotkey is never offered, however often it runs from the box
##  6. counts persist across save / reload (the test's own user dir, never Nick's)
##  7. planted: checkers that must say "taken" for a bound key and "no offer" for the 1-run command
extends SceneTree

var fails := 0
var m: Node
var lk: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func cmd_named(n: String) -> Dictionary:
	for c in m.ui_cmd.commands:
		if c["name"] == n:
			return c
	return {}


func by_id(id: String) -> Dictionary:
	for c in m.ui_cmd.commands:
		if c["id"] == id:
			return c
	return {}


## one run through the S box exactly as a user does: open, type the name, find the row, Enter's _run
func run_via_search(n: String) -> void:
	m.ui_cmd.open()
	m.ui_cmd.box.text = n
	m.ui_cmd._filter()
	var at := -1
	for i in m.ui_cmd.shown.size():
		if m.ui_cmd.shown[i]["name"] == n:
			at = i
			break
	if at < 0:
		print("     (row not found for %s)" % n)
		return
	m.ui_cmd._run(at)
	await idle(1)


func press(combo: String) -> void:
	var parts := combo.split("+")
	var e := InputEventKey.new()
	var code := OS.find_keycode_from_string(parts[parts.size() - 1])
	e.keycode = code
	e.physical_keycode = code
	e.ctrl_pressed = "Ctrl" in parts
	e.shift_pressed = "Shift" in parts
	e.alt_pressed = "Alt" in parts
	e.pressed = true
	root.push_input(e)
	await idle(3)
	var u := e.duplicate()
	u.pressed = false
	root.push_input(u)
	await idle(2)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	ok(String(m.settings).begins_with("user://poser_test_"), "0 the test saves to its own config (%s), never poser.cfg" % m.settings)
	lk = m.get_node_or_null("learn_keys")
	ok(lk != null, "0b the learner is in the poser")
	if lk == null:
		quit(1)
		return
	ok(LearnKeys.THRESHOLD == 5, "0c the threshold is 5 runs, stated in the code (%d)" % LearnKeys.THRESHOLD)
	if FileAccess.file_exists(m.hk.learn.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(m.hk.learn.path))
	m.hk.learn.counts = {}
	m.hk.learn.dismissed = []

	var A := cmd_named("Help: edit hotkeys")
	var B := cmd_named("Help: forget my command habits")
	var C := cmd_named("Help: Blender / Maya key helper off")
	var K := cmd_named("Every key on one screen")
	ok(not A.is_empty() and not B.is_empty() and not C.is_empty() and not K.is_empty(), "1 the four probe commands exist")
	ok(String(A["keys"]) == "" and String(B["keys"]) == "" and String(C["keys"]) == "" and String(K["keys"]) != "", "1b A, B, C have no key; K has one")
	var ida: String = A["id"]
	var idb: String = B["id"]
	var idc: String = C["id"]
	var idk: String = K["id"]
	var kkey: String = K["keys"]

	# 1. thresholds
	for i in 4:
		await run_via_search("Help: edit hotkeys")
		m.hk.close_editor()
	ok(lk.runs(ida) == 4 and lk.offer_id() == "", "2 A run 4x through the S box: counted 4, no offer yet (offer '%s')" % lk.offer_id())
	await run_via_search("Help: forget my command habits")
	await run_via_search("Help: edit hotkeys")
	m.hk.close_editor()
	ok(lk.runs(ida) == 5 and lk.runs(idb) == 1, "3 A counted 5, B counted 1 (%d, %d)" % [lk.runs(ida), lk.runs(idb)])
	ok(lk.offer_id() == ida, "4 the offer is for A (offer '%s')" % lk.offer_id())
	ok(lk.offer_id() != idb, "4b the offer is not for B")
	var key: String = lk.offer_key()
	ok(key != "", "5 the offer carries a key (%s)" % key)
	ok(lk.panel_visible(), "5b the offer is on screen")

	# 2. the key is free against the REAL bindings
	var cmds: Array = m.ui_cmd.commands
	ok(Hotkeys.holder(cmds, key).is_empty() and Hotkeys.built_in(cmds, key).is_empty(), "6 no command holds %s now or by default" % key)
	ok(not m.hk.scoped.has_key(key) and not (key in LearnKeys.FIXED), "6b no page binding and no fixed key of main is %s" % key)
	ok(not LearnKeys.is_free(cmds, m.hk.scoped, kkey), "6c planted: K's own key %s is NOT free" % kkey)
	ok(not LearnKeys.is_free(cmds, m.hk.scoped, "Alt+E"), "6d planted: Alt+E (hard-coded in main) is NOT free")
	m.hk.scoped.bind("Alt+A", "x_planted")
	ok(not LearnKeys.is_free(cmds, m.hk.scoped, "Alt+A"), "6e planted: a page-key binding makes Alt+A not free")
	m.hk.scoped.unbind("Alt+A")

	# 3. accept binds, a real key event runs A
	var r: Dictionary = lk.accept()
	ok(bool(r.get("ok", false)), "7 accept succeeded (%s)" % r.get("msg", ""))
	ok(String(by_id(ida)["keys"]) == key, "7b A's key in the registry is now %s (%s)" % [key, by_id(ida)["keys"]])
	ok(lk.offer_id() == "" and not lk.panel_visible(), "7c the offer is gone after accepting")
	m.hk.close_editor()
	ok(m.hk.ui == null or not m.hk.ui.visible, "7d the editor is closed before the key")
	await press(key)
	ok(m.hk.ui != null and m.hk.ui.visible, "8 a real %s key event ran A (the hotkey editor opened)" % key)
	m.hk.close_editor()
	ok(lk.runs(ida) == 5, "8b running A from its new key does not count as a box run (%d)" % lk.runs(ida))

	# 4. decline: C is offered after 5 runs, declined, never again this session
	for i in 5:
		await run_via_search("Help: Blender / Maya key helper off")
	ok(lk.offer_id() == idc, "9 C run 5x is offered (offer '%s')" % lk.offer_id())
	lk.decline()
	ok(lk.offer_id() == "" and not lk.panel_visible(), "9b declined: the offer is gone")
	for i in 8:
		await run_via_search("Help: Blender / Maya key helper off")
	ok(lk.offer_id() == "" and lk.runs(idc) == 13, "9c C run 8 more times: counted %d, never offered again" % lk.runs(idc))
	ok(String(by_id(idc)["keys"]) == "", "9d declining bound nothing")

	# 5. a command that already has a hotkey is never offered
	for i in 7:
		await run_via_search("Every key on one screen")
		m.keys_overlay(false)
	ok(lk.offer_id() == "", "10 K (has a key) run 7x from the box: no offer (offer '%s')" % lk.offer_id())
	ok(String(by_id(idk)["keys"]) == kkey, "10b K's key is unchanged")

	# 6. counts persist (a fresh CmdLearn on the test's own file)
	lk.save()
	var L2 := CmdLearn.new(m.hk.learn.path)
	ok(L2.runs(ida) == 5 and L2.runs(idb) == 1 and L2.runs(idc) == 13, "11 reloaded counts: A %d, B %d, C %d" % [L2.runs(ida), L2.runs(idb), L2.runs(idc)])
	ok(L2.is_dismissed(idc) and not L2.is_dismissed(idb), "11b the declined C is remembered, B is not")
	ok(String(m.hk.learn.path).begins_with("user://"), "11c the file lives in the test's own user dir (%s)" % m.hk.learn.path)
	var lk2: Node = LearnKeys.new(m)
	ok(lk2.runs(idb) == 1 and lk2.runs(ida) == 5, "12 a new learner sees the saved counts")
	lk2.free()

	# 7. planted: the checker must be able to say no
	ok(lk.would_offer(idb) == false, "13 B (1 run) would not be offered")
	ok(lk.would_offer("never_ran") == false, "13b an unknown command is not offered")
	ok(lk.would_offer(ida) == false, "13c A (now has a key) would not be offered")
	print("---- %s" % ("ALL OK" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails > 0 else 0)
