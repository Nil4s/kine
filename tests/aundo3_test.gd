extends SceneTree
## godot --path . --position 4000,4000 -s tests/aundo3_test.gd     (AUNDO3: EASY UNDO, a beginner from the start screen: 10 real-click edits, Undo all, Redo all; 1280 x 720; needs a window)
## The edits: a pose drag (left arm), a card (Punch), a Then card, Faster, a pose drag (right arm), Bigger, a card pick + Cut end (card remove),
## a Then card, His colour, Slower: 10 edits that each change the body or the cards.
## BARS (stated before measuring):
##  1 START: a fresh start (no settings file) opens Easy with the home panel showing (0 clicks).
##  2 EACH EDIT: each of the 10 edits changes the state (body, cards, colour, ...) and adds >= 1 undo step (a card pick is its own step).
##  3 UNDO ALL: each Undo click takes back exactly one step (the undo depth drops by 1) and the state is EXACTLY the one recorded at that depth.
##  4 REDO ALL: each Redo click puts back exactly one step (the redo depth drops by 1) and the state is EXACTLY the one recorded at that depth.
##  5 BUTTONS: the Undo and Redo buttons are visible and clickable (a real click) at every step.
##  6 BACK TO START: after Undo all the state is the start state; after Redo all it is the state after the last edit.
## Shots: C:/Temp/claude/aundo3/aundo3_*.png. user:// only.
const SHOT := "C:/Temp/claude/aundo3"
const KEYS := ["body", "pbody", "cards", "props", "fps", "bcol", "holds", "markers", "pk", "bmats", "plants", "ik", "layers", "face", "attrs", "clips", "bones", "hair", "rigx", "lip"]

var fails := 0
var m: Node
var states := {}      # undo depth -> the state (a dictionary of keys) after the step that reached that depth


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


## a real click on a Control: the mouse moves in, presses and releases on its middle
func click_ctl(c: Control) -> bool:
	if c == null or not c.is_visible_in_tree():
		return false
	var at: Vector2 = c.get_global_rect().get_center()
	await ev_move(at)
	await ev_mouse(at, true)
	await ev_mouse(at, false)
	await idle(3)
	return true


## a real press at p, six moves to p + dx, the release there (a body drag)
func drag_px(p: Vector2, dx: float) -> void:
	await ev_move(p)
	await ev_mouse(p, true)
	for i in 6:
		await ev_move(p.lerp(p + Vector2(dx, 0.0), float(i + 1) / 6.0), true)
	await ev_mouse(p + Vector2(dx, 0.0), false)
	await idle(3)


## a point on a body part (the middle first) that the pick returns as that part
func aim(part: String) -> Vector2:
	await process_frame
	var c: Array = m.B.cap(part)
	for t in [0.5, 0.35, 0.65, 0.25, 0.75]:
		var p: Vector2 = m.cam.unproject_position((c[0] as Vector3).lerp(c[1], t))
		if m._pick(p) == part:
			return p
	return m.cam.unproject_position((c[0] as Vector3).lerp(c[1], 0.5))


## the words on a button: its text, else the Label inside it
func text_of(b: Button) -> String:
	if b.text.strip_edges() != "":
		return b.text.strip_edges()
	for n in _walk(b, []):
		if n is Label and (n as Label).text.strip_edges() != "":
			return (n as Label).text.strip_edges()
	return ""


func _walk(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children():
		_walk(c, out)
	return out


## the first visible button whose words are txt (or begin with it when prefix)
func vis_btn(txt: String, prefix := false) -> Button:
	for n in _walk(root, []):
		if n is Button and (n as Button).is_visible_in_tree():
			var t := text_of(n as Button)
			if t == txt or (prefix and t.begins_with(txt)):
				return n as Button
	return null


## the state as a dictionary: each key the undo step keeps (the same snapshot Ctrl+Z restores), as text
func snap() -> Dictionary:
	var s: Dictionary = m._snapshot()
	var d := {}
	for k in KEYS:
		d[k] = var_to_str(s.get(k))
	d["playhead"] = var_to_str(m.playhead)   # where the clip's time is: the body is posed there
	return d


## the keys whose text differs between two states (empty = the same state)
func diff_keys(a: Dictionary, b: Dictionary) -> Array:
	var out := []
	for k in KEYS + ["playhead"]:
		if String(a.get(k, "")) != String(b.get(k, "")):
			out.append(k)
	return out


## where two texts first differ: a window of each around the first differing character (for the printout)
func where(a: String, b: String) -> String:
	var tag := "%d" % Time.get_ticks_msec()
	var fa := FileAccess.open("user://aundo3_dbg_%s_a.txt" % tag, FileAccess.WRITE)
	fa.store_string(a)
	fa.close()
	var fb := FileAccess.open("user://aundo3_dbg_%s_b.txt" % tag, FileAccess.WRITE)
	fb.store_string(b)
	fb.close()
	return "full states written: user:// aundo3_dbg_%s_a.txt / _b.txt" % tag


## the state at this undo depth is recorded the first time the depth is reached
func record() -> void:
	var dp: int = m.undo.size()
	if not states.has(dp):
		states[dp] = snap()


## Stop the clip before a state is read: a clip still playing moves the body every frame
func settle() -> void:
	if m.playing:
		var st := vis_btn("Stop")
		if st != null:
			await click_ctl(st)
		else:
			m.playing = false
		await idle(4)


func shot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/aundo3_%s.png" % [SHOT, nm])


## one edit: the real clicks (fn), then the state must change and the undo depth must rise
func edit(i: int, nm: String, fn: Callable) -> void:
	var d0: int = m.undo.size()
	var pre := snap()
	var did: bool = await fn.call()
	await idle(4)
	await settle()
	record()
	var post := snap()
	var d1: int = m.undo.size()
	ok(did and d1 > d0 and not diff_keys(pre, post).is_empty(), "2. edit %d '%s': clicked %s, undo steps %d -> %d, the state %s" % [i, nm, str(did), d0, d1, "changed" if not diff_keys(pre, post).is_empty() else "DID NOT CHANGE"])


func _init() -> void:
	EasyMode.start_fresh = true   # a fresh install: no settings file, so the app opens in Easy
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	var home: EasyHome = m.easy.home
	# 1. START
	ok(m.easy.on and home.shown() == "panel", "1. a fresh start opens Easy with the home panel showing (easy %s, shown %s)" % [str(m.easy.on), home.shown()])
	record()
	await shot("0_start")
	var start_state: Dictionary = snap()
	var raw: Dictionary = m._snapshot()
	ok(raw.has("cards") and raw.has("bcol") and raw.has("holds") and raw.has("fps") and raw.has("playhead"), "guard: the undo step carries cards, His colour, holds, fps and the playhead (the keys this test compares)")

	# 2. THE TEN EDITS (each one a press or a drag a beginner makes)
	await edit(1, "Pose: left arm", func():
		var p: Vector2 = await aim("upperarm_l")
		await drag_px(p, 40.0)
		return true)
	await edit(2, "Card: Punch", func():
		return await click_ctl(vis_btn("Punch")))
	await edit(3, "Then card", func():
		return await click_ctl(vis_btn("Then ", true)))
	await edit(4, "Timing: Faster", func():
		return await click_ctl(vis_btn("Faster")))
	await edit(5, "Pose: right arm", func():
		var p: Vector2 = await aim("upperarm_r")
		await drag_px(p, -30.0)
		return true)
	await edit(6, "Motion: Bigger", func():
		return await click_ctl(vis_btn("Bigger")))
	await edit(7, "Card remove: Cut end", func():
		var pc: Node = m.ui_cards.get_node_or_null("card_2")
		var pk: Control = pc.find_child("b_pick", true, false) as Control if pc != null else null
		if not await click_ctl(pk):
			return false
		await idle(4)
		await settle()
		record()   # the pick is a step of its own: its state is recorded at its depth
		return await click_ctl(vis_btn("Cut end")))
	await edit(8, "Then card again", func():
		return await click_ctl(vis_btn("Then ", true)))
	await edit(9, "Colour: His colour", func():
		return await click_ctl(vis_btn("His colour")))
	await edit(10, "Timing: Slower", func():
		return await click_ctl(vis_btn("Slower")))
	await shot("1_edited")
	var end_state: Dictionary = snap()
	var n: int = m.undo.size()
	ok(n >= 10, "2. the 10 edits left %d undo steps (each edit is at least one)" % n)

	# 3. UNDO ALL
	var bad3 := 0
	var clicks3 := 0
	while m.undo.size() > 0 and clicks3 < 60:
		var dp: int = m.undo.size()
		var ub: Control = m.easy.button("Undo") as Control
		var vis: bool = ub != null and ub.is_visible_in_tree()
		var did := await click_ctl(ub)
		clicks3 += 1
		await idle(3)
		var got := snap()
		var dk: Array = diff_keys(got, states[dp - 1]) if states.has(dp - 1) else ["no state recorded"]
		var good: bool = vis and did and m.undo.size() == dp - 1 and dk.is_empty()
		if not good:
			bad3 += 1
			print("     undo from depth %d: depth now %d, keys that differ %s %s" % [dp, m.undo.size(), str(dk), where(String(states[dp - 1]["body"]), String(got["body"])) if states.has(dp - 1) and "body" in dk else ""])
	ok(bad3 == 0 and m.undo.size() == 0, "3. UNDO ALL: %d Undo clicks, each one step back to its exact state; depth now %d (%d bad)" % [clicks3, m.undo.size(), bad3])
	ok(diff_keys(snap(), start_state).is_empty(), "6. after Undo all the state is the start state (exactly)")
	await shot("2_undone")

	# 4. REDO ALL
	var bad4 := 0
	var clicks4 := 0
	while m.redo.size() > 0 and clicks4 < 60:
		var dp: int = m.undo.size()
		var did := await click_ctl(m.easy.button("Redo") as Control)
		clicks4 += 1
		await idle(3)
		var got := snap()
		var dk: Array = diff_keys(got, states[dp + 1]) if states.has(dp + 1) else ["no state recorded"]
		var good: bool = did and m.undo.size() == dp + 1 and dk.is_empty()
		if not good:
			bad4 += 1
			print("     redo from depth %d: depth now %d, keys that differ %s %s" % [dp, m.undo.size(), str(dk), where(String(states[dp + 1]["body"]), String(got["body"])) if states.has(dp + 1) and "body" in dk else ""])
	ok(bad4 == 0 and m.redo.size() == 0, "4. REDO ALL: %d Redo clicks, each one step forward to its exact state; redo left %d (%d bad)" % [clicks4, m.redo.size(), bad4])
	ok(diff_keys(snap(), end_state).is_empty() and m.undo.size() == n, "6. after Redo all the state is the state after the last edit (exactly), depth %d" % m.undo.size())
	await shot("3_redone")
	print("aundo3: 10 edits, %d undo steps, %d fail" % [n, fails])
	quit(1 if fails > 0 else 0)
