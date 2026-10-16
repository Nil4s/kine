## godot --path . -s tests/paste_test.gd     (GATES Q1; needs a window)
## COPY / PASTE POSE through the real keys (Ctrl+C, Ctrl+V, Ctrl+Shift+V) and the registry's "Paste to this part":
## a paste reproduces the copied pose to 1e-4 deg, mirrored equals Mirror (the whole pose) of it, a part paste changes
## that chain and nothing else, each paste is ONE undo step, and pasting with nothing copied does nothing.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func key(code: Key, shift := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.ctrl_pressed = true
		e.shift_pressed = shift
		e.pressed = down
		root.push_input(e)
	await process_frame


func angs() -> Dictionary:
	return m.B.ang.duplicate()


## the largest angle difference between two poses, over these joints (all if empty), and where
func diff(a: Dictionary, b: Dictionary, only := []) -> Array:
	var worst := 0.0
	var at := ""
	for j in a:
		if not only.is_empty() and not j in only:
			continue
		var d: float = ((a[j] as Vector3) - (b[j] as Vector3)).abs()[((a[j] as Vector3) - (b[j] as Vector3)).abs().max_axis_index()]
		if d > worst:
			worst = d
			at = j
	return [worst, at]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	# nothing copied: nothing happens
	var u0: int = m.undo.size()
	await key(KEY_V)
	ok(m.undo.size() == u0 and String(m.ui_status.text).begins_with("nothing copied"), "Ctrl+V with nothing copied: no change, says '%s'" % m.ui_status.text.left(40))
	m._card_pick(2)
	var c3 := angs()
	var off3: Vector3 = m.B.offset
	u0 = m.undo.size()
	await key(KEY_C)
	ok(not m.pose_clip.is_empty() and m.undo.size() == u0, "Ctrl+C on card 3: copied, no undo step")
	m._card_pick(6)
	var c7 := angs()
	ok(diff(c3, c7)[0] > 5.0, "card 7 differs from card 3 (by %.0f deg at %s)" % diff(c3, c7))
	var u1: int = m.undo.size()
	await key(KEY_V)
	var d: Array = diff(c3, angs())
	ok(d[0] < 1e-4 and m.B.offset.is_equal_approx(off3), "Ctrl+V: the body is card 3's pose (worst %.6f deg at %s), hips too" % d)
	ok(m.undo.size() == u1 + 1, "  one undo step (%d)" % (m.undo.size() - u1))
	m._undo()
	ok(diff(c7, angs())[0] < 1e-4, "  Ctrl+Z: card 7's pose again")
	# mirrored = Mirror (whole pose) of card 3's angles
	m._card_pick(2)
	m.B.mirror_pose()
	var mir := angs()
	var mir_off: Vector3 = m.B.offset
	m._card_pick(6)
	u1 = m.undo.size()
	await key(KEY_V, true)
	d = diff(mir, angs())
	ok(d[0] < 1e-4 and m.B.offset.is_equal_approx(mir_off), "Ctrl+Shift+V: card 3 mirrored (worst %.6f deg at %s), hips x flipped" % d)
	ok(m.undo.size() == u1 + 1, "  one undo step")
	m._undo()
	# part: the left arm only
	m.sel = "upperarm_l"
	var chain: Array = m.B.below("upperarm_l")
	ok(chain.has("lowerarm_l") and chain.has("hand_l") and not chain.has("upperarm_r") and not chain.has("spine_03"), "the left arm's chain: %d joints, hand in, the other arm and spine out" % chain.size())
	var before := angs()
	var off_before: Vector3 = m.B.offset
	ok(not off_before.is_equal_approx(off3), "  (card 7's hips differ from card 3's, so the next check can fail)")
	ok(diff(c3, before, chain)[0] > 1.0, "  (card 7's left arm differs from card 3's by %.0f deg, so the arm check can fail)" % diff(c3, before, chain)[0])
	var paste: Callable
	for c in m._commands():
		if c["name"] == "Paste to this part":
			paste = c["run"]
	ok(paste.is_valid(), "'Paste to this part' is a registry command")
	paste.call()
	var now := angs()
	var others := []
	for j in now:
		if not j in chain:
			others.append(j)
	d = diff(c3, now, chain)
	var e: Array = diff(before, now, others)
	ok(d[0] < 1e-4 and e[0] == 0.0, "part paste: the arm is card 3's (worst %.6f deg), every other joint untouched (%.6f)" % [d[0], e[0]])
	ok(m.B.offset.is_equal_approx(off_before), "  the hips stay where they were")
	print("PASTE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
