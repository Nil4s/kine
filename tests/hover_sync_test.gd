## godot --path . -s tests/hover_sync_test.gd     (GATES KK2, UPGRADES #35; a real window, real mouse motion)
## HOVER IN SYNC: the Browser tab open. (1) The mouse over the left thigh in the view: its Browser row lit. (2) The mouse
## onto empty view: the row unlit. (3) The mouse over the head's row in the Browser: the head lit in the view (HOVER),
## the bar says "pointing at the head", and it STAYS lit 10 frames on (the view's own clean-up must not wipe it).
## (4) The mouse onto a folder row: the head unlit, the bar no longer pointing. (5) Back on the head's row, then out of
## the Browser onto empty view: cleared. (6) Back on it, then straight onto the right panel: cleared too.
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func motion(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e)
	await idle(3)


func spot(j: String) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position((c[0] + c[1]) * 0.5)


## a row's middle on the screen (scrolled into sight first)
func row_at(it: TreeItem) -> Vector2:
	var t: Tree = m.ui_browser
	t.scroll_to_item(it, true)
	await idle(3)
	var r := t.get_item_area_rect(it)
	return t.get_global_transform() * Vector2(40, r.get_center().y)


func lit(j: String) -> bool:
	var it: TreeItem = m.ui_browser.rows[j]
	return it.get_custom_bg_color(0).is_equal_approx(Tok.c("btn_hover"))   # a cleared colour reads back as Color() (opaque black), not clear


func head_hover() -> bool:
	return (m.mats["head"] as StandardMaterial3D).albedo_color.is_equal_approx(Color(m.HOVER, 0.3))


func empty_view() -> Vector2:
	return Vector2(m.LEFT_W + 30, m.TOP_H + 200)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._new_scene()
	(m.ui_browser.get_parent() as TabContainer).current_tab = 1
	m.sel = "upperarm_r"
	m._refresh()
	await idle(4)
	await motion(spot("thigh_l"))
	var r1: bool = m.hover_part == "thigh_l" and lit("thigh_l")
	ok(r1, "1 the mouse on the left thigh in the view: hover '%s', its Browser row lit %s" % [m.hover_part, lit("thigh_l")])
	await motion(empty_view())
	ok(m.hover_part == "" and not lit("thigh_l"), "2 the mouse onto empty view: hover '%s', the row lit %s" % [m.hover_part, lit("thigh_l")])
	var hp := await row_at(m.ui_browser.rows["head"])
	await motion(hp)
	await create_timer(m.BAR_LEAVE + 0.05).timeout   # the bar's words follow a RESTED hover (QQ2: BAR_REST on, BAR_LEAVE off)
	await process_frame
	var named: bool = m.bar_text().contains("pointing at the head")
	var on_now := head_hover()
	await idle(10)
	ok(m.hover_part == "head" and on_now and named and head_hover(), "3 the mouse on the head's row: hover '%s', the head lit in the view %s, the bar points at it %s; 10 frames on still lit %s" % [m.hover_part, on_now, named, head_hover()])
	var fold: TreeItem = m.ui_browser.rows["head"].get_parent()   # the Torso folder
	await motion(await row_at(fold))
	await create_timer(m.BAR_LEAVE + 0.05).timeout   # the bar's words follow a RESTED hover (QQ2: BAR_REST on, BAR_LEAVE off)
	await process_frame
	ok(m.hover_part == "" and not head_hover() and not m.bar_text().contains("pointing at"), "4 the mouse onto the Torso folder row: hover '%s', the head lit %s" % [m.hover_part, head_hover()])
	await motion(await row_at(m.ui_browser.rows["head"]))
	var again: bool = m.hover_part == "head"
	await motion(empty_view())
	ok(again and m.hover_part == "" and not head_hover(), "5 back on the head's row (%s), then out onto empty view: hover '%s', the head lit %s" % [again, m.hover_part, head_hover()])
	await motion(await row_at(m.ui_browser.rows["head"]))
	var again2: bool = m.hover_part == "head"
	var vs := root.get_visible_rect().size
	await motion(Vector2(vs.x - m.RIGHT_W * 0.5, m.TOP_H + 60))   # straight onto the right panel, never through the view
	await idle(3)
	ok(again2 and m.hover_part == "" and not head_hover(), "6 the head's row (%s), then straight onto the right panel: hover '%s', the head lit %s" % [again2, m.hover_part, head_hover()])
	print("HOVER SYNC: %d failed" % fails)
	quit(1 if fails > 0 else 0)
