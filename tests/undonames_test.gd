## godot --path . -s tests/undonames_test.gd     (ROADMAP 45: UNDO THAT NEVER SURPRISES; needs a window: the real UI is built)
## Six different edits, made the way the app makes them (a button or command through _do, a say-named step through
## _push_undo + _say). Checks: the step names list matches the edits in order, none empty, none "Edit" or the generic
## "Change"; the Undo tooltip reads "Undo: <last name>"; the Redo tooltip reads "Redo: <the step Ctrl+Y gives back>";
## jumping back 3 through the History panel restores the scene hash of the state before those 3 edits; a 15-step
## history shows only its newest 10 rows.
extends SceneTree

var fails := 0
var m: Node

const EXPECT := ["Mirror pose", "ROTATING the right upper arm", "Retime: 3 cards", "Snap the hips",
	"Card 12: the right foot planted", "Drag left hand"]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


## everything an undo step must bring back: the body and the cards (the scene's hash)
func fp() -> String:
	return JSON.stringify(m.B.state()) + JSON.stringify(m.S.cards)


## a button / command edit: the press names the step (its hint), the edit goes through _do
func do_hint(hint: String, j: String, v: float) -> void:
	m._step_hint = hint
	m._do(func():
		m.B.ang[j] = Vector3(0.0, 0.0, v)
		m.B.fk())


## a say-named edit: the step is pushed, the body moves, the status line names it
func do_say(say: String, j: String, v: float) -> void:
	m._push_undo()
	m.B.ang[j] = Vector3(0.0, 0.0, v)
	m.B.fk()
	m._say(say)


func labels() -> Array:
	var out := []
	for u in m.undo:
		out.append(m._step_label(u))
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
	m._undo_tips()

	var before := fp()
	ok(m.ui_undo_btn.tooltip_text.begins_with("Undo (Ctrl+Z)") and "nothing to undo" in m.ui_undo_btn.tooltip_text,
		"0 steps: the Undo tooltip says there is nothing to undo")

	# six different edits, in order; the states after each are kept for the jump check
	var states := []
	do_hint(EXPECT[0], "upperarm_l", 10.0)
	states.append(fp())
	do_say(EXPECT[1], "upperarm_r", 20.0)
	states.append(fp())
	do_hint(EXPECT[2], "calf_l", 30.0)
	states.append(fp())
	do_hint(EXPECT[3], "thigh_r", 40.0)
	states.append(fp())
	do_say(EXPECT[4], "foot_r", 15.0)
	states.append(fp())
	do_hint(EXPECT[5], "lowerarm_l", 50.0)
	states.append(fp())

	var names := labels()
	ok(names == EXPECT, "6 edits: the step names list matches them in order: %s" % str(names))
	var plain := true
	for n in names:
		if String(n) == "" or String(n) == "Edit" or String(n) == "Change":
			plain = false
	ok(plain, "every step has a non-empty name, none of them 'Edit' or the generic 'Change'")
	ok(m.ui_undo_btn.tooltip_text == "Undo: " + EXPECT[5], "Undo tooltip = 'Undo: %s' (the last step): '%s'" % [EXPECT[5], m.ui_undo_btn.tooltip_text])
	ok(m.ui_redo_btn.tooltip_text.begins_with("Redo (Ctrl+Y)") and "nothing to redo" in m.ui_redo_btn.tooltip_text,
		"no redo yet: the Redo tooltip says there is nothing to redo")

	# the History panel: jump back 3 to the state after edit 3 (before edits 4, 5, 6)
	m._toggle_history()
	await idle()
	var want := fp()   # the live state (after edit 6), to show the jump really moves
	var target: int = m._tree.path()[3]
	m._tree_go(target)
	await idle()
	var h3 := hash(states[2])
	ok(fp() == states[2], "jump back 3 through History: the scene hash %d is the state after edit 3 (before 4, 5, 6)" % h3)
	ok(fp() != want, "the jump moved the work (the state after edit 6 differs)")
	ok(m.undo.size() == 3 and labels() == EXPECT.slice(0, 3), "after the jump the step list is the first 3 names: %s" % str(labels()))
	ok(m.ui_undo_btn.tooltip_text == "Undo: " + EXPECT[2], "after the jump the Undo tooltip is 'Undo: %s'" % EXPECT[2])
	ok(m.ui_redo_btn.tooltip_text == "Redo: " + EXPECT[3], "after the jump the Redo tooltip is 'Redo: %s' (the step Ctrl+Y gives back)" % EXPECT[3])

	# Ctrl+Z three times gives the same state as the jump did
	m._undo()
	m._undo()
	m._undo()
	ok(fp() == before, "Ctrl+Z x3 from there gives back the state before the first edit (scene hash %d)" % hash(before))

	# the History panel shows the newest 10 of a longer history
	m._redo()
	m._redo()
	m._redo()
	m._redo()
	m._redo()
	m._redo()
	ok(m.undo.size() == 6, "redo x6 brings the six edits back")
	for i in 9:   # 6 + 9 = 15 steps on the trunk
		do_hint("Nudge %d" % (i + 1), "upperarm_l", 60.0 + i)
	await idle()
	m._history_rows()
	var shown := 0
	for c in m.ui_hist_list.get_children():
		if c is Button and c.text != "Close":
			shown += 1
	ok(shown == 10, "a 15-step history lists the newest 10 rows (shown %d)" % shown)
	ok(m.undo.size() == 15, "all 15 steps are still undoable (Ctrl+Z reaches the older ones): %d" % m.undo.size())

	var shot := OS.get_environment("UNDONAMES_SHOT")
	if shot != "":   # the History panel with the named steps, for a look
		await idle(3)
		root.get_texture().get_image().save_png(shot)

	print("")
	print("RESULT %s (%d fail%s)" % ["PASS" if fails == 0 else "FAIL", fails, "" if fails == 1 else "s"])
	quit(fails)
