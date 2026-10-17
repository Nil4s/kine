## godot --path . -s tests/browser_place_test.gd     (GATES AA2, UPGRADES #6; a window: real clicks and wheel)
## BROWSER KEEPS ITS PLACE: in the Browser tab a real click picks the left forearm's row, two folders are folded (Torso,
## Right leg), the left arm's fingers unfolded, and the tree is scrolled by the wheel so the row is in sight but not
## centred. Then each of: a plain refresh (what every drag does), a card added, a card deleted, another scene opened,
## the theme switched (and back), the UI scale changed (and back), a part picked IN THE VIEW: the picked row, the
## folds and the scroll are as they were (the last: the new part's row picked, the folds kept).
extends SceneTree

var fails := 0
var m: Node
var br: Browser


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func find(t: String) -> TreeItem:
	var stack: Array = [br.get_root()]
	while stack.size() > 0:
		var it: TreeItem = stack.pop_back()
		if it.get_text(0) == t:
			return it
		for c in it.get_children():
			stack.append(c)
	return null


## what the user sees: [the picked part, the folded folders' texts, the scroll]
func place() -> Array:
	var sel := ""
	var it := br.get_selected()
	if it != null and it.get_metadata(0) is Dictionary:
		sel = String(it.get_metadata(0).get("part", ""))
	var folded := []
	var stack: Array = [br.get_root()]
	while stack.size() > 0:
		var x: TreeItem = stack.pop_back()
		if x != br.get_root() and x.get_child_count() > 0 and x.collapsed:
			var path := x.get_text(0).get_slice("  (", 0).get_slice(":", 0)   # by its path: "index" is under both arms (Scene's name and count change)
			var up := x.get_parent()
			while up != null and up != br.get_root():
				path = up.get_text(0) + "/" + path
				up = up.get_parent()
			folded.append(path)
		for c in x.get_children():
			stack.append(c)
	folded.sort()
	return [sel, folded.filter(func(f): return not "/fingers/" in f), br.get_scroll().y]   # (the 10 single fingers, folded inside, left out of the print)


func mouse(p: Vector2, button: MouseButton) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = down
		e.position = p
		e.global_position = p
		root.push_input(e)
		await process_frame


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.ui_browser.open_all()   # round 36 (RR6): the tree starts with Scene and the body's groups folded; open them as a user would
	m.ui_browser._lib.collapsed = false   # and the pose Library (21 rows): the tree far taller than its box
	m.ui_browser._scene_root.collapsed = true   # Scene folded, as a user's starts: its clip rows (a card added, another
	await idle(2)                               # scene) would otherwise move every row under them
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	br = m.ui_browser
	pass   # round 36 (RR3): the tree is the whole left panel, no tab to open
	await idle(4)

	find("Torso").collapsed = true
	find("Right leg").collapsed = true
	var row: TreeItem = br.rows["lowerarm_l"]
	var lf := row.get_parent().get_children().filter(func(c): return c.get_text(0) == "fingers")[0] as TreeItem
	lf.collapsed = false
	for c in lf.get_children():   # round 36: rows under the forearm, so the wheel's two notches stay short of the
		c.collapsed = false       # bottom (at the bottom a theme's 5 px margin clamped the scroll: a fixture edge)
	await idle(2)
	br.scroll_to_item(row, true)
	await idle(2)
	var r := br.get_item_area_rect(row)
	await mouse(br.get_global_transform() * (r.position + r.size * 0.5), MOUSE_BUTTON_LEFT)
	await idle(3)
	var gp := br.get_global_rect().get_center()
	for i in 2:
		await mouse(gp, MOUSE_BUTTON_WHEEL_DOWN)
	await idle(3)
	var p0 := place()
	var in_sight := br.get_global_rect().has_point(br.get_global_transform() * br.get_item_area_rect(row).get_center())
	ok(p0[0] == "lowerarm_l" and m.sel == "lowerarm_l" and p0[1].has("Body/Torso") and p0[1].has("Body/Right leg") and in_sight and p0[2] > 0.0,
		"0 a real click picked the left forearm ('%s', sel '%s'); Torso and Right leg folded; scrolled by the wheel to %.0f px, the row in sight (%s) %s" % [p0[0], m.sel, p0[2], in_sight, p0[1]])

	var steps := [["1 a plain refresh (every drag)", func(): m._refresh()],
		["2 a card added", func(): m._card_add()],
		["3 a card deleted", func(): m._card_del(m.S.cards.size() - 1)],
		["4 another scene opened", func(): m._load_scene("res://scenes/thrust.json"); m._rebuild_cards()],
		["5 the theme switched", func(): m._set_light(Tok.dark)],
		["6 and back", func(): m._set_light(Tok.dark)],
		["7 the UI scale 125 %", func(): m._set_scale(125)],
		["8 and back", func(): m._set_scale(100)]]
	for s in steps:
		var before := place()
		s[1].call()
		await idle(6)
		var after := place()
		ok(after == before, "%s: picked '%s', folded %s, scroll %.0f px (before: '%s', %s, %.0f)" % [s[0], after[0], after[1], after[2], before[0], before[1], before[2]])
	var f0: Array = place()[1]
	m.sel = "upperarm_r"
	m._refresh()
	await idle(6)
	var p9 := place()
	ok(p9[0] == "upperarm_r" and p9[1] == f0, "9 a part picked in the view (the right upper arm): its row picked, the folds as they were %s" % [p9[1]])
	# and a row OUT of sight is still brought into sight: scrolled to the top, a part low in the tree picked (round 36:
	# the clips and the pose library above the body made the bottom-scroll leave the neck in sight)
	for i in 60:
		await mouse(gp, MOUSE_BUTTON_WHEEL_UP)
	await idle(3)
	find("Torso").collapsed = false
	await idle(2)
	var hid: TreeItem = br.rows["foot_l"]
	var was_hidden := not br.get_global_rect().has_point(br.get_global_transform() * br.get_item_area_rect(hid).get_center())
	m.sel = "foot_l"
	m._refresh()
	await idle(6)
	var seen := br.get_global_rect().has_point(br.get_global_transform() * br.get_item_area_rect(hid).get_center())
	ok(was_hidden and seen and place()[0] == "foot_l", "10 a part whose row was out of sight (the left foot, scrolled away %s) picked in the view: its row picked and scrolled into sight (%s)" % [was_hidden, seen])
	print("BROWSER PLACE: %d failed" % fails)
	quit(1 if fails > 0 else 0)
