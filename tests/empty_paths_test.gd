## godot --path . -s tests/empty_paths_test.gd     (GATES GG1, UPGRADES #47; a real window, real clicks)
## THREE WAYS IN: an empty scene's strip shows "Clip this pose", "Open a scene" and the three examples, each wholly on
## screen. A REAL click on Clip this pose: clip 1, the body's pose. On Open a scene: the scene list's popup opens. On an
## example: that scene opened as a copy (cards, no file path). With cards in the scene none of the three paths shows.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
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
	await idle(3)


func paths() -> Array:
	return m.ui_cards.get_children().filter(func(c): return c is Button and (String(c.name).begins_with("start_") or c.text.begins_with("Example: ")))


func empty() -> void:
	m._new_scene()
	m._refresh()
	await idle(4)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	await empty()
	var win := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var ps := paths()
	var off := []
	for b in ps:
		if not (b as Control).is_visible_in_tree() or not win.encloses((b as Control).get_global_rect()):
			off.append(b.text)
	ok(ps.size() == 5 and off.is_empty(), "1 an empty scene: %d ways in %s, each wholly on screen (not: %s)" % [ps.size(), ps.map(func(b): return b.text), off])
	m.B.ang["upperarm_r"] = Vector3(0, 0, 33)
	m.B.fk()
	await click(m.ui_cards.get_node("start_clip"))
	var clipped: bool = m.S.cards.size() == 1
	ok(clipped, "2 a real click on 'Clip this pose': %d clip" % m.S.cards.size())
	await empty()
	await click(m.ui_cards.get_node("start_open"))
	var opened: bool = m.ui_scenes.get_popup().visible
	m.ui_scenes.get_popup().hide()
	await idle(2)
	ok(opened and m.ui_scenes.item_count > 1, "3 a real click on 'Open a scene': the scene list opens (%d scenes in it)" % m.ui_scenes.item_count)
	await empty()
	var ex: Array = paths().filter(func(b): return b.text.begins_with("Example: "))
	var et: String = ex[0].text   # the button goes when the cards are rebuilt
	await click(ex[0])
	ok(m.S.cards.size() >= 2 and m.scene_path == "" and m.S.name.ends_with("_mine"), "4 a real click on '%s': %d cards, opened as a copy '%s' (no file path)" % [et, m.S.cards.size(), m.S.name])
	ok(paths().is_empty(), "5 with cards in the scene no way-in shows (%d)" % paths().size())
	print("EMPTY PATHS: %d failed" % fails)
	quit(1 if fails > 0 else 0)
