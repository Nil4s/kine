## godot --path . -s tests/empty_state_test.gd     (GATES N5; needs a window)
## No clips = the bottom panel is only the scene row and the CLIP hint; the first clip opens it; deleting the last,
## "New empty scene" and Ctrl+Z all land in the right state. What stands on the panel (side panels, status line,
## speed graph) moves with it and never overlaps it; the camera's centring follows. Measured on screen rects.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## the layout as it is on screen: panel height, what is shown, and nothing standing on the panel overlaps it
func state(tag: String, want_empty: bool) -> void:
	await process_frame
	await process_frame
	var bp: Rect2 = m.ui_bp.get_global_rect()
	var st: Rect2 = m.ui_status.get_global_rect()
	var over := 0
	for p in m.ui_side:
		if (p as Control).get_global_rect().end.y > bp.position.y + 0.5:
			over += 1
	if st.end.y > bp.position.y + 0.5:
		over += 1
	var want_h: float = m.BOTTOM_EMPTY if want_empty else m.BOTTOM_H
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var mpp: float = 2.0 * m.dist * tan(deg_to_rad(m.cam.fov * 0.5)) / vs.y
	var cam_ok: bool = is_equal_approx(m.cam.v_offset, -(want_h - m.TOP_H) * 0.5 * mpp)
	print("     %s: panel %.0f px tall (top at %.0f), timeline %s, play row %s, overlaps %d, camera centred %s" % [tag, bp.size.y, bp.position.y, m.ui_timeline.visible, m.ui_play_row.visible, over, cam_ok])
	ok(absf(bp.size.y - (want_h - 6.0)) < 1.0 and m.ui_timeline.visible != want_empty and m.ui_play_row.visible != want_empty and over == 0 and cam_ok,
		"%s: %s" % [tag, "collapsed (scene row + hint)" if want_empty else "full (cards, timeline, play row)"])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	await state("start, no clips", true)
	var hint: bool = m.ui_cards.get_child_count() == 1 and String(m.ui_cards.get_child(0).text).contains("CLIP this pose")
	ok(hint and m.ui_cards.get_child(0).is_visible_in_tree(), "  the hint is on screen: 'No clips yet ... CLIP this pose ...'")
	m._card_add()
	await state("after CLIP this pose (1 clip)", false)
	m._card_add()
	m._card_del(1)
	m._card_del(0)
	await state("both clips deleted", true)
	m._undo()
	await state("Ctrl+Z (a clip back)", false)
	ok(m.S.cards.size() == 1, "  Ctrl+Z after deleting the last clip: %d clip back (card edits are undoable now)" % m.S.cards.size())
	m._undo()
	ok(m.S.cards.size() == 2, "  Ctrl+Z again: %d clips" % m.S.cards.size())
	m._card_move(0, 1)
	var first: String = m.S.cards[0]["name"]
	m._undo()
	ok(m.S.cards[0]["name"] != first, "  moving a card is undone too ('%s' first again)" % m.S.cards[0]["name"])
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await state("combo3 opened", false)
	m.S = Scene.new()
	m.sel_card = -1
	m._rebuild_cards()
	await state("New empty scene", true)
	m._big_view()
	await state("big view, empty", true)
	m._big_view()
	print("EMPTY STATE %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
