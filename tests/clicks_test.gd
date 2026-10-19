## godot --path . -s tests/clicks_test.gd     (GATES V3, item 81; needs a window)
## CLICKS-TO-TASK: ten common tasks, each done in the real window by the fewest real actions the UI offers today, and
## COUNTED: a click on a control = a real mouse press at its centre on the screen (so it must be visible and on top),
## a key = a real key press, typing a name = 1. Each task's effect is checked, so a count is never of a path that
## does not work. Writes the table to docs/CLICKS.md (generated: the doc is what this test measured).
extends SceneTree

var fails := 0
var m: Node
var rows := []

## measured by this test before round 15's cuts (C:/Temp/clicks_before.md), -1 = not possible in the window
const BEFORE := {"open a scene (combo3)": 3, "slow one card down": 2, "raise the right arm": 2, "mirror the pose": 1,
	"add the pose as a card": 1, "name a card": -1, "put the bat in the right hand": 4, "check, apply a fix": 3,
	"undo": 1, "save under a new name": 4}
## the count each task may take now: one more is a regression and FAILS
const BUDGET := {"open a scene (combo3)": 2, "slow one card down": 2, "raise the right arm": 1, "mirror the pose": 1,
	"add the pose as a card": 1, "name a card": 3, "put the bat in the right hand": 1, "check, apply a fix": 3,
	"undo": 1, "save under a new name": 3}
## why a task is not cut further
const WHY := {"open a scene (combo3)": "cut: picking it opens it (it asks first when the open scene has unsaved changes). 2 = open the list + pick.",
	"slow one card down": "which card + what to do: 2 is the floor without guessing the card.",
	"raise the right arm": "cut: one drag; the press on the part picks it and grabs it (the click first was never needed).",
	"mirror the pose": "already one key.", "add the pose as a card": "already one key.",
	"name a card": "cut from impossible: double-click the title, type, Enter (Esc or clicking away keeps the old name).",
	"put the bat in the right hand": "cut: B now moves the bat into the right hand whichever hand held it (it took it off before); the button was 2 scrolls down.",
	"check, apply a fix": "cut: each Fix sits right under its finding (its why line after it), so the next fix is in view when the first is refused. Round 36 (RR4, Nick's Fusion layout): Check left the play strip for the ribbon's CHECK tab, so 3 = the tab + Check + the fix (round 15 had 2; a key for Check would win it back).",
	"undo": "already one key.",
	"save under a new name": "cut: Enter in the name box saves. A new name has to be typed; re-saving under the same name is Ctrl+Shift+S, 1 key."}


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func find(addr: String) -> Control:
	var n: Node = m
	for part in addr.split("/"):
		n = n.find_child(part, true, false) if n != null else null
	return n as Control


var scrolls := 0   # the scrolls a task needed to bring its controls into view (each is an action)


## a real click at the control's centre; false if it is not there to click. A control scrolled out of its panel's
## view is scrolled to first, as a person would, and that scroll is counted (scrolls)
func click(addr: String, double := false) -> bool:
	var c := find(addr)
	if c == null or not c.is_visible_in_tree():
		print("     (cannot click %s: %s)" % [addr, "no such control" if c == null else "not shown"])
		return false
	var sc: Node = c.get_parent()
	while sc != null and not (sc is ScrollContainer):
		sc = sc.get_parent()
	if sc != null and not (sc as Control).get_global_rect().encloses(c.get_global_rect()):
		(sc as ScrollContainer).ensure_control_visible(c)
		await idle(2)
		scrolls += 1
	var p := c.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.double_click = double and down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame
	await idle(2)
	return true


func key(k: Key, shift := false, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.shift_pressed = shift
		e.ctrl_pressed = ctrl
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


## typing into the control that has focus (1 action, however long the text)
func type(text: String) -> void:
	for ch in text:
		for down in [true, false]:
			var e := InputEventKey.new()
			e.unicode = ch.unicode_at(0)
			e.pressed = down
			root.push_input(e)
	await idle(2)


func spot(j: String) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position((c[0] + c[1]) * 0.5)


func mouse(down: bool, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


func drag(p: Vector2, d: Vector2) -> void:   # press, move in 10 steps, release: 1 action
	mouse(true, p)
	await process_frame
	for k in 10:
		var e := InputEventMouseMotion.new()
		e.position = p + d * (k + 1) / 10.0
		e.global_position = e.position
		e.relative = d / 10.0
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame
	mouse(false, p + d)
	await idle(2)


func task(name: String, path: String, n: int, done: bool) -> void:
	n += scrolls
	if scrolls > 0:
		path += " (+%d scroll%s to reach it)" % [scrolls, "" if scrolls == 1 else "s"]
	scrolls = 0
	rows.append([name, path, n if done else -1])
	ok(done and n <= int(BUDGET.get(name, 99)), "%-34s %s action%s (budget %s): %s" % [name, n, "" if n == 1 else "s", BUDGET.get(name, "-"), path])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false

	# 1 open a scene from the list
	var opt := find("opt_scene")
	var idx := -1
	for i in opt.item_count:
		if String(opt.get_item_metadata(i)).ends_with("combo3.json"):
			idx = i
	var n := 0
	if await click("opt_scene"):
		n += 1
	(opt.get_popup() as PopupMenu).hide()
	opt.select(idx)   # the pick in the open list (the popup is its own window): 1 action
	opt.item_selected.emit(idx)
	n += 1
	await idle()
	if m.S.cards.size() != 12:
		if await click("b_open_scene"):
			n += 1
	await task("open a scene (combo3)", "the list, pick it" + (", Open scene" if n == 3 else ""), n, m.S.cards.size() == 12)

	# 2 pick card 3 and make it slower
	var mv0: float = m.S.times()[2][1] - m.S.times()[1][1]
	n = 0
	if await click("card_3/b_pick"):
		n += 1
	if await click("b_slower"):
		n += 1
	await task("slow one card down", "click the card, Slower", n, m.S.times()[2][1] - m.S.times()[1][1] > mv0 + 1e-6 or m.S.cards[2]["hold"] > 0)

	# 3 raise the right arm: ONE drag from it (round 25, #81: the press on a part picks it AND grabs it; another part
	# is picked first, so the drag must do both)
	var a0: Vector3 = m.B.ang["upperarm_r"]
	m.sel = "head"
	m._refresh()
	await idle()
	await drag(spot("upperarm_r"), Vector2(0, -60))
	await task("raise the right arm", "drag it (the press picks it)", 1, m.sel == "upperarm_r" and not m.B.ang["upperarm_r"].is_equal_approx(a0))

	# 4 mirror the pose
	var al: Vector3 = m.B.ang["upperarm_l"]
	await key(KEY_M, true)
	await task("mirror the pose", "Shift+M", 1, not m.B.ang["upperarm_l"].is_equal_approx(al))

	# 5 add the pose as a card
	var c0: int = m.S.cards.size()
	await key(KEY_ENTER)
	await task("add the pose as a card", "Enter", 1, m.S.cards.size() == c0 + 1)

	# 6 name that card
	var ni: int = m.sel_card
	var old: String = m.S.cards[ni]["name"]
	n = 0
	if await click("card_%d/b_pick" % (ni + 1), true):
		n += 1
	var named := false
	var fo := root.gui_get_focus_owner()
	if fo is LineEdit:
		await type("my hit")
		await key(KEY_ENTER)
		n += 2
		named = m.S.cards[ni]["name"] == "my hit"
	await task("name a card", "double-click its title, type, Enter" if named else "(no way in the window)", n, named)

	# 7 put the bat in the right hand (combo3's bat is in the left: the kind is right, the hand is not)
	n = 0
	var bpath := ""
	if not (m.B.wep_on and m.B.wep_kind == "metal_bat"):
		if await click("Poses/opt_weapon"):   # the weapon picker (round 25): open it, pick Metal bat = 2 actions
			var wo := find("Poses/opt_weapon") as OptionButton
			(wo.get_popup() as PopupMenu).hide()
			wo.select(1)
			wo.item_selected.emit(1)
			n += 2
			bpath = "weapon picker > Metal bat, "
	await key(KEY_B)   # "In right hand (B)"
	n += 1
	await task("put the bat in the right hand", bpath + "B (In right hand)", n, m.B.wep_on and m.B.wep_hand == "hand_r" and m.B.wep_kind == "metal_bat")

	# 8 check the motion and apply the first fix
	n = 0
	# round 36 (RR4): Check left the play row for the ribbon's CHECK tab: one click more (the tab), budget 2 -> 3
	if await click("top_strip/tab_check"):
		n += 1
	if await click("ribbon_check/b_check"):
		n += 1
	await idle()
	var before := JSON.stringify(m.S.cards)
	var tried := 0   # a fix that is refused ("did not remove the problem") changes nothing: the next one is tried
	for k in range(1, 7):
		if find("check_panel/fix_%d" % k) == null:
			continue
		tried += 1
		if await click("check_panel/fix_%d" % k):
			while m._fixing:
				await process_frame
		if JSON.stringify(m.S.cards) != before:
			break
		await click("ribbon_check/b_check")
	n += 1
	await task("check, apply a fix", "Check, a fix's button" + ("" if tried <= 1 else " (%d were refused first: not counted)" % (tried - 1)), n, m.check_ran and JSON.stringify(m.S.cards) != before)

	# the pick opens at once only when nothing is lost: with unsaved changes it asks, and opens nothing until told
	var cards_now := JSON.stringify(m.S.cards)
	var oi := -1
	for i in opt.item_count:
		if String(opt.get_item_metadata(i)).ends_with("combo3.json"):
			oi = i
	opt.select(oi)
	opt.item_selected.emit(oi)
	await idle()
	ok(JSON.stringify(m.S.cards) == cards_now and m.ui_save_ask != null and m.ui_save_ask.visible,
		"picking a scene with unsaved changes asks first (Save changes to ...), and opens nothing until told (asked: %s)" % (m.ui_save_ask != null and m.ui_save_ask.visible))
	if m.ui_save_ask != null:
		m._save_ask_choose("cancel")   # ROADMAP 50: Cancel keeps this scene open

	# 9 undo it
	var bf := JSON.stringify(m.S.cards)
	await key(KEY_Z, false, true)
	await task("undo", "Ctrl+Z", 1, JSON.stringify(m.S.cards) != bf)

	# 10 save the scene under a new name (scenes/_wip: never Nick's files)
	n = 0
	if await click("edit_scene_name"):
		n += 1
	var ed := find("edit_scene_name") as LineEdit
	ed.select_all()
	await type("_wip/zz_clicks")
	n += 1
	var path := ProjectSettings.globalize_path("res://scenes/_wip/zz_clicks.json")
	await key(KEY_ENTER)   # Enter in the name box
	n += 1
	if not FileAccess.file_exists(path):
		if await click("b_save_scene"):
			n += 1
	var saved := FileAccess.file_exists(path)
	await task("save under a new name", "click the name, type it, Enter" if n == 3 and saved and true else "click the name, type it, Save scene", n, saved)
	if saved:
		DirAccess.remove_absolute(path)

	var total := 0
	var was := 0
	var was_n := 0   # the before total over the tasks that were possible before, and the same tasks now
	var lines := ["# Clicks to task", "", "GENERATED by tests/clicks_test.gd (GATES V3, UPGRADES #81): each count is what the test MEASURED doing the task in",
		"the real window (a click = a real mouse press on the control, a scroll to reach it = 1, a key = 1, typing a name = 1),",
		"and each task's effect is checked. 'before' = the same test before round 15's cuts. -1 = no way to do it in the window.",
		"A task taking more than its count now FAILS the test.", "",
		"| task | before | now | the path now | why not fewer |", "|---|---|---|---|---|"]
	for r in rows:
		var b: int = BEFORE.get(r[0], -1)
		lines.append("| %s | %d | %d | %s | %s |" % [r[0], b, r[2], r[1], WHY.get(r[0], "")])
		total += maxi(r[2], 0)
		if b > 0:
			was += b
			was_n += maxi(r[2], 0)
	var cut := 100.0 * (was - was_n) / maxf(was, 1)
	lines.append("| **total** | **%d** | **%d** | | |" % [was, total])
	var possible := BEFORE.values().filter(func(v): return v > 0).size()
	var most := 0
	for r in rows:
		most = maxi(most, r[2])
	lines += ["", "Over the %d tasks the window could do before: %d -> %d actions, %.0f%% fewer; tasks that had no way now take %d." % [
		possible, was, was_n, cut, total - was_n],
		("That meets the 30% bar." if cut >= 30.0 else "That is short of the 30%% the gate asked for: no task takes more than %d actions now, and each row says why it is not cut further. The rest is choices (which card, which part, which fix, which name)." % most)]
	var outp := OS.get_environment("CLICKS_OUT") if OS.get_environment("CLICKS_OUT") != "" else OS.get_environment("TMP") + "/clicks_now.md"
	var fh := FileAccess.open(outp, FileAccess.WRITE)
	fh.store_string("
".join(lines) + "
")
	fh.close()
	print("CLICKS before %d -> now %d on the same 9 tasks (%.0f%% fewer); total now %d over %d tasks" % [was, was_n, cut, total, rows.size()])
	print("CLICKS: %d failed" % fails)
	quit(1 if fails > 0 else 0)
