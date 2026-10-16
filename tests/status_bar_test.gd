## godot --path . -s tests/status_bar_test.gd     (GATES P4; needs a window)
## The status bar: one line, always on screen, reading what is picked (part + angles, or the weapon), the card, the
## playhead, and Check's count. Six changes are driven through the poser's own functions; after each the test waits
## frames and reads the LABEL the user sees (not bar_text()), so a bar that never re-draws fails.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func shown() -> String:
	await process_frame
	await process_frame
	return m.ui_bar.text


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m._refresh()
	var t: String = await shown()
	print("     start: " + t)
	var vr: Rect2 = root.get_visible_rect()
	var br: Rect2 = m.ui_bar.get_global_rect()
	ok(m.ui_bar.is_visible_in_tree() and vr.encloses(br) and br.size.y >= 20, "the bar is on screen: %s" % br)
	ok(not br.intersects(m.ui_status.get_global_rect()), "it does not cover the say line")
	ok(t.contains("12 cards, none picked") and t.contains("Check: not run") and t.contains("/ 4.67 s"), "fresh scene: 12 cards, none picked, Check not run, length 4.67 s")

	# 1. pick a part
	m.sel = "lowerarm_l"
	m._panel()
	t = await shown()
	ok(t.begins_with("left forearm") or t.begins_with(m.nice("lowerarm_l")), "1 pick the left forearm: '%s'" % t.get_slice("|", 0))
	# 2. turn it (an edit)
	m._do(func(): m.B.set_ang_safe("lowerarm_l", Vector3(80, 0, 0)))
	t = await shown()
	ok(t.contains("swing 80"), "2 set its swing to 80: '%s'" % t.get_slice("|", 0).strip_edges())
	# 3. pick card 3
	m._card_pick(2)
	t = await shown()
	ok(t.contains("card 3 / 12"), "3 pick card 3: '%s'" % t.get_slice("|", 1).strip_edges())
	# 4. move the playhead
	m.playhead = 2.5
	m._ps().apply(m.B, m.playhead)
	m._refresh()
	t = await shown()
	ok(t.contains("2.50 / 4.67 s"), "4 playhead to 2.5 s: '%s'" % t.get_slice("|", 2).strip_edges())
	# 5. run Check
	m._check()
	t = await shown()
	var n: int = m.findings.size()
	var f: int = m.findings.filter(func(x): return x["sev"] == "FAIL").size()
	ok(t.contains("Check: %d (%d must fix)" % [n, f]) and not t.contains("changed since"), "5 Check: '%s'" % t.get_slice("|", 3).strip_edges())
	# 6. edit after Check: the count is marked as from before the edit; Undo brings it back to current
	m._do(func(): m.B.set_ang_safe("lowerarm_l", Vector3(40, 0, 0)))
	t = await shown()
	ok(t.contains("changed since"), "6 an edit after Check: '%s'" % t.get_slice("|", 3).strip_edges())
	m._undo()
	t = await shown()
	ok(not t.contains("changed since"), "  Undo it: '%s'" % t.get_slice("|", 3).strip_edges())
	# 7. pick the weapon
	m.sel = "bat_barrel"
	m._panel()
	t = await shown()
	ok(t.begins_with("metal bat  in the"), "7 pick the bat: '%s'" % t.get_slice("|", 0).strip_edges())
	# 8. a new empty scene resets the card count and Check
	m.S = Scene.new()
	m.check_ran = false
	m.sel_card = -1
	m.playhead = 0.0
	m._rebuild_cards()
	t = await shown()
	ok(t.contains("no cards") and t.contains("Check: not run"), "8 a new empty scene: '%s'" % t)
	print("STATUS BAR TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
