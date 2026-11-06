## godot --path . -s tests/browser_tree_test.gd     (GATES RR3; needs a window)
## THE BROWSER: the left panel is ONE slim tree (no tabs): Scene (its clips), Poses (Library / Mine), Body, Weapon,
## Target dummy; at most 240 px wide; rows at most 22 px. A pose row clicked applies the pose, a clip row shows the clip,
## a part row picks the part. Every button the round-35 left panel had is found somewhere and works: Save pose (the
## header's icon, a name dialog), Rename / Delete pose / CLIP this pose (a pose row's right-click menu), the weapon
## picker, 2nd hand, Slide, Hand to the end (the inspector's WEAPON), the dummy's On/off, Closer, Farther, Solid (its
## row's menu; the row reads the dummy's line). The test's own pose is zz_rr3_* in moves/ and leaves no file behind.
extends SceneTree

var fails := 0
var m: Node
var br: Tree


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func press(p: Vector2, bi := MOUSE_BUTTON_LEFT) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = bi
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT if bi == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
		root.push_input(e)
		await process_frame


func row_at(it: TreeItem) -> Vector2:
	br.scroll_to_item(it)
	await idle(2)
	var r := br.get_item_area_rect(it)
	return br.get_global_transform() * (r.position + Vector2(40, r.size.y * 0.5))


func click_row(it: TreeItem, bi := MOUSE_BUTTON_LEFT) -> void:
	await press(await row_at(it), bi)
	await idle(3)


## the row under `under` whose text begins with t
func find(t: String, under: TreeItem = null) -> TreeItem:
	var stack: Array = [under if under != null else br.get_root()]
	while stack.size() > 0:
		var it: TreeItem = stack.pop_back()
		if it != br.get_root() and it.get_text(0).begins_with(t):
			return it
		for c in it.get_children():
			stack.append(c)
	return null


## right-click the row, pick the menu item by its words
func menu(it: TreeItem, item: String) -> bool:
	await click_row(it, MOUSE_BUTTON_RIGHT)
	var pm: PopupMenu = m.ui_ctx
	if pm == null or not pm.visible:
		return false
	for k in pm.item_count:
		if pm.get_item_text(k) == item:
			pm.id_pressed.emit(pm.get_item_id(k))
			pm.hide()
			await idle(3)
			return true
	pm.hide()
	return false


func btn(t: String) -> Button:
	for b in m.find_children("*", "Button", true, false):
		if m.label_of(b) == t and (b as Button).is_visible_in_tree():
			return b
	return null


func _init() -> void:
	var moves := ProjectSettings.globalize_path("res://moves")
	# the test's own zz_rr3_* poses: a run that died (or a second run at once) leaves them, and a leftover makes Save pose ask to overwrite
	for f in ["zz_rr3_a.json", "zz_rr3_b.json"]:
		if FileAccess.file_exists("res://moves/" + f):
			DirAccess.remove_absolute(moves.path_join(f))
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.ui_browser.open_all()   # round 36 (RR6): the tree starts with Scene and the body's groups folded; open them as a user would
	await idle(2)
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle(4)
	br = m.ui_browser
	var lp: Control = m.ui_side_of["left"]
	ok(m.find_children("*", "TabContainer", true, false).filter(func(t): return lp.is_ancestor_of(t)).is_empty() and lp.is_ancestor_of(br) and br.is_visible_in_tree(),
		"the left panel is one tree, no tabs")
	ok(lp.get_global_rect().end.x <= 240.0 + 1.0, "the panel ends at x %.0f (at most 240)" % lp.get_global_rect().end.x)
	var tops := []
	for c in br.get_root().get_children():
		if not c.visible:
			continue   # the Set folder (round 37) shows only when the scene has props
		tops.append(c.get_text(0).get_slice(":", 0).get_slice("  ", 0))
	tops.erase("Sets")   # the selection / keying sets folder (wave A)
	tops.erase("Outliner")   # L36: the Outliner folder (scene objects by parent), tests/outliner_test.gd
	ok(tops == ["Scene", "Poses", "Body", "Target dummy"] or tops == ["Scene", "Poses", "Body", "Weapon", "Target dummy"], "the top rows: %s" % [tops])
	var hh := []
	for t in ["Scene", "Poses", "Body", "Torso", "hips"]:
		hh.append(br.get_item_area_rect(find(t)).size.y)
	ok(hh.all(func(h): return h <= 22.0 and h >= 14.0), "rows at most 22 px: %s" % [hh])
	# a clip row shows the clip; a part row picks it
	await click_row(find("3  CONTACT"))
	ok(m.sel_card == 2, "the clip row '3  CONTACT' clicked: clip %d picked" % (m.sel_card + 1))
	await click_row(find("head"))
	ok(m.sel == "head", "the part row 'head' clicked: %s selected" % m.sel)
	# Save pose: the header's icon, a name, the file in moves/
	var sv := btn("Save pose")
	ok(sv != null and sv.text == "" and sv.icon != null and m.ui_side_of["left"].is_ancestor_of(sv), "Save pose: an icon in the browser's header")
	m.B.ang["upperarm_r"] = Vector3(33, 0, 0)
	m.B.fk()
	await press(sv.get_global_rect().get_center())
	await idle(3)
	ok(m.ui_name_dlg.visible, "  clicked: the name dialog opens")
	m.ui_pose_name.text = "zz_rr3_a"
	m.ui_name_dlg.get_ok_button().pressed.emit()
	await idle(3)
	ok(FileAccess.file_exists("res://moves/zz_rr3_a.json") and find("zz rr3 a", find("Mine")) != null, "  'zz_rr3_a' saved: the file in moves/ and its row under Mine")
	# a pose row: applies; its menu: CLIP / Rename / Delete
	m.B.ang["upperarm_r"] = Vector3.ZERO
	m.B.fk()
	var row := find("zz rr3 a", find("Mine"))
	await click_row(row)
	ok(is_equal_approx((m.B.ang["upperarm_r"] as Vector3).x, 33.0), "the pose row clicked: the body takes it (arm %.0f)" % (m.B.ang["upperarm_r"] as Vector3).x)
	var n0: int = m.S.cards.size()
	ok(await menu(find("zz rr3 a", find("Mine")), "CLIP this pose (Enter)") and m.S.cards.size() == n0 + 1, "its menu > CLIP this pose: %d -> %d clips" % [n0, m.S.cards.size()])
	ok(await menu(find("zz rr3 a", find("Mine")), "Rename...") and m.ui_name_dlg.visible and m.ui_pose_name.text == "zz rr3 a", "its menu > Rename...: the dialog, the old name in it ('%s')" % m.ui_pose_name.text)
	m.ui_pose_name.text = "zz_rr3_b"
	m.ui_name_dlg.get_ok_button().pressed.emit()
	await idle(3)
	ok(FileAccess.file_exists("res://moves/zz_rr3_b.json") and not FileAccess.file_exists("res://moves/zz_rr3_a.json") and find("zz rr3 b", find("Mine")) != null, "  renamed: zz_rr3_b")
	ok(await menu(find("zz rr3 b", find("Mine")), "Delete pose") and m.ui_confirm != null and m.ui_confirm.visible, "its menu > Delete pose: it asks first")
	m.ui_confirm.get_ok_button().pressed.emit()
	await idle(3)
	ok(not FileAccess.file_exists("res://moves/zz_rr3_b.json") and find("zz rr3 b", find("Mine")) == null, "  deleted: gone from moves/ and from Mine")
	for f in DirAccess.get_files_at("res://trash"):
		if f.begins_with("zz_rr3_"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("res://trash/" + f))
	# the weapon rows: the inspector's WEAPON
	m._kind("metal_bat")
	m.sel = "bat_handle"
	m._refresh()
	await idle(4)
	var g0: bool = m.B.grip
	var b2 := btn("2nd hand on/off (G)")
	if b2 != null:
		await press(b2.get_global_rect().get_center())
	ok(b2 != null and m.B.grip != g0, "WEAPON > 2nd hand: grip %s -> %s" % [g0, m.B.grip])
	var s0: bool = m.slide_body
	await press(m.ui_slide_btn.get_global_rect().get_center())
	ok(m.ui_slide_btn.is_visible_in_tree() and m.slide_body != s0, "WEAPON > Slide: %s -> %s" % [s0, m.slide_body])
	var he := btn("Hand to the end")
	m._kind("staff")   # a long weapon: its hand is not at the end yet (the bat's is, 0.07 m)
	m._bat_put("hand_r")
	m._refresh()
	await idle(3)
	var hu0: float = m.B.hold_u()
	if he != null:
		await press(he.get_global_rect().get_center())
		await idle(2)
	ok(he != null and m.B.hold_u() < hu0 - 0.01 and m.find_children("opt_weapon_panel", "OptionButton", true, false).size() == 1,
		"WEAPON > Hand to the end clicked: the hand %.2f -> %.2f m along; the weapon picker is there" % [hu0, m.B.hold_u()])
	# the dummy: its row's menu
	if m.dummy_on:
		m._dummy_toggle()   # from off: the toggle turns it on, and the row then reads a live line
	await idle(3)
	var dm := find("Target dummy")
	var on0: bool = m.dummy_on
	ok(await menu(dm, "On/off (H)") and m.dummy_on != on0, "the dummy row's menu > On/off: %s -> %s" % [on0, m.dummy_on])
	await idle(3)
	var d0: float = m.T.dist
	ok(await menu(find("Target dummy"), "Closer") and m.T.dist < d0, "  > Closer: %.2f -> %.2f m" % [d0, m.T.dist])
	d0 = m.T.dist
	ok(await menu(find("Target dummy"), "Farther") and m.T.dist > d0, "  > Farther: %.2f -> %.2f m" % [d0, m.T.dist])
	var so: bool = m.solid
	ok(await menu(find("Target dummy"), "Solid / see-through") and m.solid != so, "  > Solid / see-through: %s -> %s" % [so, m.solid])
	await idle(3)
	ok(find("Target dummy").get_text(0).contains(m.ui_dummy.text.get_slice("\n", 0).left(10)), "  the row reads the dummy: '%s'" % find("Target dummy").get_text(0))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(m.settings))
	print("BROWSER TREE TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
