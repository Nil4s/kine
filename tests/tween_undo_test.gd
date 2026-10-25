## godot --path . -s tests/tween_undo_test.gd     (GATES F2; needs a window: the real poser UI is built)
## In the real poser: pick card 4 of combo3, slide the tween three times (one drag), ONE Ctrl+Z puts the body back on
## card 4's pose; the scene's cards are not touched by sliding (only Update writes a card). "+ tween" adds one card,
## halfway, and the scene keeps its length.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	var cards_before := JSON.stringify(m.S.cards)
	m._card_pick(3)
	var card_pose := JSON.stringify(m.B.to_dict())
	var depth: int = m.undo.size()
	for v in [0.3, 0.6, 1.2]:
		m._tween(v)
	ok(JSON.stringify(m.B.to_dict()) != card_pose, "sliding changed the body")
	ok(m.undo.size() == depth + 1, "one drag = one undo step (%d pushed)" % (m.undo.size() - depth))
	ok(JSON.stringify(m.S.cards) == cards_before, "sliding leaves the scene's cards alone (Update keeps it)")
	m._undo()
	ok(JSON.stringify(m.B.to_dict()) == card_pose, "one Ctrl+Z: the body is card 4's pose again")
	m._tween_armed = false
	var n: int = m.S.cards.size()
	var len0: float = m.S.length()
	m._tween_add()
	ok(m.S.cards.size() == n + 1 and m.S.cards[4]["name"] == "tween", "+ tween: one card added after card 4 (%d -> %d)" % [n, m.S.cards.size()])
	ok(absf(m.S.length() - len0) < 1e-4, "+ tween: the scene keeps its length (%.3f -> %.3f s)" % [len0, m.S.length()])
	# D3: the trail plays for 60 frames and is built once; an edit rebuilds it once more
	m.ov.trail_on = true
	m.ov.mark_dirty()
	m._refresh()
	var b0: int = m.ov.builds
	m.playhead = 0.0
	m.playing = true
	for k in 60:
		await process_frame
	m.playing = false
	ok(m.playhead > 0.5, "playback really ran: playhead at %.2f s" % m.playhead)
	ok(m.ov.builds == b0, "trail: 60 frames of playback, %d rebuilds (must be 0)" % (m.ov.builds - b0))
	m._rebuild_cards()
	m._refresh()
	ok(m.ov.builds == b0 + 1, "trail: one edit, one rebuild (%d)" % (m.ov.builds - b0))
	print("TWEEN UNDO %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
