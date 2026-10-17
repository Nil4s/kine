## godot --path . -s tests/fold_test.gd     (GATES QQ4; needs a window)
## ROOM TO WORK: each side panel folds to its rail with one real click on its << / >> and opens again from the rail;
## the scene panel folds to the timeline and Play ("Fold") and opens again ("Clips"); every fold is saved; the say
## strip, the status bar, the cube and the nav block move to the view's new edges; the body stays in the middle of the
## free view; the big view (Tab) hides the rails too; the folded bottom's contents fit BOTTOM_FOLDED; every visible
## play-row button is on screen; with all three folded (combo3 open) the view is >= 70 % of a 1600x900 window.
extends SceneTree

var m: Node
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e)
		await process_frame
	await idle()


func saved(k: String) -> Variant:
	var cf := ConfigFile.new()
	cf.load(m.settings)
	return cf.get_value("layout", "fold_" + k, null)


func on_screen(c: Control) -> bool:
	return c.is_visible_in_tree() and m.get_viewport().get_visible_rect().encloses(c.get_global_rect())


## the window's pixels no chrome covers, as a share (the measure of tools/layout_measure.gd)
func view_share() -> float:
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var rs: Array = []
	for c in m.ui_root.get_children():
		if c is Control and c.is_visible_in_tree() and (c is PanelContainer or c is Panel or c == m.ui_status or c == m.ui_bar) and c != m.ui_tour:
			rs.append((c as Control).get_global_rect())
	var free := 0
	var tot := 0
	for y in range(0, int(vs.y), 4):
		for x in range(0, int(vs.x), 4):
			tot += 1
			if y < m.TOP_H:
				continue
			if not rs.any(func(r): return r.has_point(Vector2(x, y))):
				free += 1
	return 100.0 * free / tot


## the body's middle on screen, against the middle of the free view (between the sides)
func body_off() -> float:
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var mid: float = (m.lw() + vs.x - m.rw()) * 0.5
	return absf(m.cam.unproject_position(m.target).x - mid)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	ok(not m.fold["left"] and not m.fold["right"] and not m.fold["bottom"], "a test starts with every panel open")
	var lp: Control = m.ui_side_of["left"]
	var rp: Control = m.ui_side_of["right"]
	# left
	ok(on_screen(m.ui_fold_btn["left"]), "the left panel has its << on screen")
	await click(m.ui_fold_btn["left"])
	var rl: Control = m.ui_rails["left"]
	ok(m.fold["left"] and not lp.visible and on_screen(rl) and rl.get_global_rect().size.x <= m.RAIL_W and saved("left") == true,
		"a click on <<: the left panel folds to its rail (%d px wide, on screen %s), saved" % [rl.get_global_rect().size.x, on_screen(rl)])
	# round 36 (RR5): one status line: its messages start at the view's left edge; the readout ends at the camera bar
	ok(is_equal_approx(m.ui_status.get_global_rect().position.x, m.lw() + 12) and m.ui_bar.get_global_rect().position.x >= m.lw() + 12 and m.ui_bar.get_global_rect().end.x <= m.ui_nav.get_global_rect().position.x,
		"the status line moves to the view's new left edge (%d), its readout still left of the camera bar" % (m.lw() + 12))
	ok(body_off() < 4.0, "the body stays in the middle of the free view (%.1f px off)" % body_off())
	await click(rl.find_child("open_left", true, false))
	ok(not m.fold["left"] and lp.visible and not rl.visible and saved("left") == false, "the rail's >>: the panel back, saved")
	# right
	ok(on_screen(m.ui_fold_btn["right"]), "the right panel has its >> on screen")
	await click(m.ui_fold_btn["right"])
	var rr: Control = m.ui_rails["right"]
	ok(m.fold["right"] and not rp.visible and on_screen(rr) and rr.get_global_rect().size.x <= m.RAIL_W and saved("right") == true,
		"a click on >>: the right panel folds to its rail (%d px wide, on screen %s), saved" % [rr.get_global_rect().size.x, on_screen(rr)])
	var cube_r: float = m.ui_cube.get_global_rect().end.x
	var vsx: float = m.get_viewport().get_visible_rect().size.x
	ok(cube_r > vsx - m.RAIL_W - 20 and cube_r <= vsx - m.RAIL_W, "the view cube moves out to the rail (its right edge %d)" % cube_r)
	ok(body_off() < 4.0, "the body stays in the middle of the free view (%.1f px off)" % body_off())
	# the big view hides the rails too, and gives them back
	await click(m.ui_fold_btn["left"])
	m._big_view()
	await idle()
	ok(not rl.visible and not rr.visible and not lp.visible and not rp.visible, "the big view (Tab): no panel, no rail")
	m._big_view()
	await idle()
	ok(rl.visible and rr.visible and not lp.visible and not rp.visible, "Tab again: the two rails back, the panels still folded")
	# the bottom
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	var fb: Button = m.ui_fold_btn["bottom"]
	ok(on_screen(fb), "a scene with clips: the scene panel has its Fold on screen")
	await click(fb)
	var pr: Rect2 = m.ui_bp.get_global_rect()
	ok(m.fold["bottom"] and m.bottom_h == m.BOTTOM_FOLDED and not m.ui_card_row.visible and m.ui_timeline.is_visible_in_tree() and saved("bottom") == true,
		"Fold: the scene panel is the timeline and the play row (%d px), saved" % pr.size.y)
	var need: float = m.ui_bp.get_combined_minimum_size().y
	ok(need <= m.BOTTOM_FOLDED and pr.encloses(m.ui_timeline.get_global_rect()) and pr.encloses(m.ui_play_row.get_global_rect()),
		"its contents fit: they need %d px of BOTTOM_FOLDED %d" % [need, m.BOTTOM_FOLDED])
	await idle(2)
	var row: Array = m.ui_play_row.get_children().filter(func(c): return c is Control and c.visible)
	ok(row.all(on_screen), "every play-row control shown is on screen (%d)" % row.size())
	var share := view_share()
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	print("     the view: %.1f %% of %dx%d" % [share, vs.x, vs.y])
	if vs == Vector2(1600, 900):
		ok(share >= 70.0, "all three folded, combo3 open, 1600x900: the view is %.1f %% of the window (bar 70)" % share)
	await click(m.ui_fold_btn["bottom_open"])
	ok(not m.fold["bottom"] and m.bottom_h == m.BOTTOM_H and m.ui_card_row.visible and saved("bottom") == false, "Clips: the scene panel back, saved")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	print("FOLD TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
