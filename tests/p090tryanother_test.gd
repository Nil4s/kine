extends SceneTree
## P090 TRY ANOTHER WAY (Friday plan item 90): the undo tree keeps every branch; the History panel has a Try another way
## button: press it, click an earlier step, and the work goes there (one action, no undo step) and the next change starts
## a NEW way. The Ways list under the rows lists each way (its last step) and goes back to any of them, the first way
## included. A beginner walk: real clicks on Undo, History, Try another way, the step rows and the Ways rows; the
## edits are the app's own edit steps (one undo step each). Bars are measured from the built state (the body's
## fingerprint, the tree's node and way counts, the undo list's length, the button's pixel size), not from the code's own
## variables. Bars were written before the code.
##   B1 three steps made: Step 1, Step 2, Step 3 (undo list 3)
##   B2 real click on Undo twice: the body is the state after Step 1, undo list 1, redo list 2
##   B3 one new change from Step 1 starts a way: the undo list grows by exactly 1 (2), the ways count is 2
##   B4 real click on History: the panel is on screen; Try another way is a button, at least 28 px tall, inside the panel
##   B5 real click on Try another way: its text now says Cancel, the status names the next step
##   B6 real click on the row "Step 2" (an earlier step, on the first way): the body is the state after Step 2 byte for byte,
##      the node count is the same as before the jump (a jump adds no step), the Try button is off again
##   B7 Try another way, then a click on the step the work is ON: the status says so, and the picker stays on
##   B8 a change from Step 2 is a new third way: the ways count is 3, the undo list grows by exactly 1
##   B9 real click on the Ways row "Way 1 (first)": the body is the state after Step 3 byte for byte, the first way is back,
##      its row is marked, and the node count is still 6 (nothing was lost)
##   B10 the Ways list shows 3 rows, the first one named "Way 1 (first)"
## Set P090_SHOT=<png path> to save a picture of the History panel with the Ways list.

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2, held := false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


## a real click on a control: the mouse moves there, presses and releases (no call into the app's code)
func click_ctl(c: Control) -> void:
	if c == null:
		fails += 1
		print("FAIL a control to click is missing")
		return
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


## the button under `from` whose text contains `t` (null when there is none)
func find_btn(from: Node, t: String) -> Button:
	for c in from.find_children("*", "Button", true, false):
		if (c as Button).text.contains(t):
			return c
	return null


## the History row of the step named `what` (its node name is "step_<id>")
func row(what: String) -> Button:
	var id := node_named(what)
	return m.ui_hist.find_child("step_%d" % id, true, false) as Button if id != -1 else null


## the id of the node the step named `what` made (-1 when there is none)
func node_named(what: String) -> int:
	for id in m._tree.nodes:
		if String(m._tree.node(id).get("name", "")) == what:
			return id
	return -1


## everything an undo step must bring back: the body and the cards
func fp() -> String:
	return JSON.stringify(m.B.state()) + JSON.stringify(m.S.cards)


## one edit the way the app makes one: a step pushed, the body moved, the step named by what the app says
func edit(j: String, v: float, what: String) -> void:
	m._push_undo()
	m.B.ang[j] = Vector3(0.0, 0.0, v)
	m.B.fk()
	m._say(what)


## the ways: the tree's leaves (a branch's last step), oldest first
func ways() -> Array:
	var out := []
	for id in m._tree.nodes:
		if id != m._tree.root and (m._tree.node(id)["kids"] as Array).is_empty():
			out.append(id)
	out.sort()
	return out


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle()
	m._load_scene("res://scenes/combo3.json")   # read only
	await idle()
	m.undo.clear()
	m.redo.clear()
	m._tree_sync()

	# B1: three steps
	edit("upperarm_l", 10.0, "Step 1")
	var s1 := fp()
	edit("upperarm_l", 20.0, "Step 2")
	var s2 := fp()
	edit("upperarm_l", 30.0, "Step 3")
	var s3 := fp()
	ok(m.undo.size() == 3, "B1 three steps made: the undo list has 3 (%d)" % m.undo.size())

	# B2: real clicks on Undo, twice
	await click_ctl(m.ui_undo_btn)
	await click_ctl(m.ui_undo_btn)
	ok(fp() == s1 and m.undo.size() == 1 and m.redo.size() == 2,
		"B2 two real clicks on Undo: the body is the state after Step 1 (undo %d, redo %d)" % [m.undo.size(), m.redo.size()])

	# B3: a new change from Step 1 starts a second way
	var nodes_before_way: int = m._tree.nodes.size()
	edit("upperarm_r", 45.0, "Way B step")
	var sb := fp()
	ok(m.undo.size() == 2 and ways().size() == 2,
		"B3 a change from Step 1 starts a way: undo list 2 (one step added), ways %d" % ways().size())

	# B4: real click on History: the panel shows, Try another way is a button on it, at least 28 px tall
	await click_ctl(m.ui_hist_btn)
	var try_btn := find_btn(m.ui_hist, "Try another way")
	var panel: Rect2 = m.ui_hist.get_global_rect()
	var inside: bool = try_btn != null and panel.encloses(try_btn.get_global_rect())
	ok(m.ui_hist.visible and try_btn != null and try_btn.size.y >= 28.0 and inside,
		"B4 History opened: Try another way is on the panel, %d px tall, inside the panel" % (int(try_btn.size.y) if try_btn != null else -1))

	# B5: real click on Try another way: the picker is on, the text says so, the status names the next step
	await click_ctl(try_btn)
	try_btn = find_btn(m.ui_hist, "Cancel")
	ok(try_btn != null and m.ui_status.text.to_lower().contains("earlier step"),
		"B5 Try another way pressed: the button says Cancel, the status says to click an earlier step (\"%s\")" % m.ui_status.text)

	# B6: real click on the row "Step 2": an earlier step, on the first way
	var rows_before: int = m._tree.nodes.size()
	await click_ctl(row("Step 2"))
	ok(fp() == s2 and m._tree.nodes.size() == rows_before,
		"B6 click on Step 2: the body is the state after Step 2 byte for byte, no step added (nodes %d)" % m._tree.nodes.size())
	ok(find_btn(m.ui_hist, "Try another way") != null and find_btn(m.ui_hist, "Cancel") == null,
		"  the picker is off again: the button says Try another way")

	# B7: Try another way, then a click on the step the work is on: refused in words, the picker stays on
	await click_ctl(find_btn(m.ui_hist, "Try another way"))
	await click_ctl(m.ui_hist.find_child("step_%d" % m._tree.cur, true, false))   # the live step's row
	ok(find_btn(m.ui_hist, "Cancel") != null and m.ui_status.text.to_lower().contains("already"),
		"B7 click on the step you are on: the status says you are already there, the picker stays on (\"%s\")" % m.ui_status.text)
	await click_ctl(find_btn(m.ui_hist, "Cancel"))

	# B8: a change from Step 2 is a third way; one undo step
	var undo_before: int = m.undo.size()
	edit("thigh_l", 25.0, "Way C step")
	ok(m.undo.size() == undo_before + 1 and ways().size() == 3,
		"B8 a change from Step 2 is a new third way: undo list +1 (%d), ways %d" % [m.undo.size(), ways().size()])

	# B9: real click on the first way in the Ways list: back to Step 3 byte for byte
	m._history_rows()
	await idle(2)
	var way1 := find_btn(m.ui_hist, "Way 1 (first)")
	ok(way1 != null and ways().size() == 3, "B10 the Ways list: 3 rows, the first one named \"Way 1 (first)\"")
	var way1_on_panel: bool = way1 != null and m.ui_hist.get_global_rect().encloses(way1.get_global_rect())   # measured before the click (the click rebuilds the rows)
	await click_ctl(way1)
	ok(fp() == s3,
		"B9 click on Way 1 (first): the body is the state after Step 3 byte for byte")
	ok(m._tree.nodes.size() == rows_before + 1 and ways().size() == 3,
		"  nothing lost: nodes %d, ways %d, the Way B and Way C steps are still there" % [m._tree.nodes.size(), ways().size()])
	ok(find_btn(m.ui_hist, "> Way 1 (first)") != null, "  the first way's row is marked '> ' (the live way)")
	ok(way1_on_panel, "B10b the first way's row is on the panel (no scrolling needed to see it)")

	var shot := OS.get_environment("P090_SHOT")
	if shot != "":
		await idle(2)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(shot)
		print("     picture: %s" % shot)
	print("TRY ANOTHER WAY TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
