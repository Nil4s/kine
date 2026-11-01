extends SceneTree
## godot --path . --position 4000,4000 -s tests/s219_test.gd     (S219: every Part step kind has a timeline icon; an unknown name falls back instead of a script error)
## Bars (wtest also fails the run on any SCRIPT ERROR line in the log):
##   1 KINDS    every feature kind named in the Part source (KINDS list + every new_feature(rec, "kind") call in scripts/) has a drawing in Icons.DRAW
##   2 MOVE     a part with a Move step (Part.new_feature "move", appended to the record): 10 timeline refreshes, the Move step button shows the part_move icon
##   3 FALLBACK Icons.tex / small / sized / big of a name with no drawing give a texture (the generic picture), not an error
## Shots: C:/Temp/claude/s219/timeline.png (the Move step in the timeline)
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s219"
const DIRT := "user://s219_test"
var pu: PartUI


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func kinds_in_source() -> Array:
	var out := {}
	var src := FileAccess.get_file_as_string("res://scripts/build/part.gd")
	var a := src.find("const KINDS := [")
	var b := src.find("]", a)
	for k in src.substr(a, b - a).split("\"", false):
		var s := String(k).strip_edges()
		if s.is_valid_identifier() and s != "const" and s != "KINDS":
			out[s] = true
	var re := RegEx.new()
	re.compile('new_feature[(][A-Za-z_.]+, "([a-z_]+)"')
	var stack := ["res://scripts"]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		for sub in DirAccess.get_directories_at(d):
			stack.append(d + "/" + sub)
		for fn in DirAccess.get_files_at(d):
			if fn.ends_with(".gd"):
				var t := FileAccess.get_file_as_string(d + "/" + fn)
				for r in re.search_all(t):
					out[r.get_string(1)] = true
	return out.keys()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	# 1 KINDS
	var kinds := kinds_in_source()
	var missing := []
	for k in kinds:
		var nm := "part_appearance" if k == "appear" else "part_" + String(k)
		if not Icons.DRAW.has(nm):
			missing.append(nm)
	ok(kinds.size() >= 25 and missing.is_empty(), "1 every feature kind in the Part source has an icon: %d kinds, missing %s" % [kinds.size(), str(missing)])
	# 3 FALLBACK
	var t1 := Icons.tex("part_no_such_kind")
	var t2 := Icons.small("part_no_such_kind")
	var t3 := Icons.sized("part_no_such_kind", 32)
	var t4 := Icons.big("part_no_such_kind")
	ok(t1 != null and t2 != null and t3 != null and t4 != null and t1.get_width() == 22 and t2.get_width() == 16 and t3.get_width() == 32 and t4.get_width() == 64, "3 an unknown icon name gives a generic texture at 22 / 16 / 32 / 64 px (%d, %d, %d, %d)" % [t1.get_width(), t2.get_width(), t3.get_width(), t4.get_width()])
	# 2 MOVE
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await idle(4)
	var rec: Dictionary = pu._ensure()
	var sk := Part.new_feature(rec, "sketch", {"plane": "front", "ents": [{"k": "circle", "c": [20.0, 15.0], "r": 8.0}], "dims": []})
	rec["features"].append(sk)
	var ex := Part.new_feature(rec, "extrude", {"sketch": sk["id"], "dist": 10.0, "both": false, "op": "new"})
	rec["features"].append(ex)
	var mv := Part.new_feature(rec, "move", {"body": 0, "d": [25.0, 0.0, 0.0]})
	rec["features"].append(mv)
	for i in 10:
		pu._rebuild(true)
		pu._tl_sig = ""
		pu._timeline_sync()
		await idle(2)
	var found: Button = null
	for b in root.find_children("part_step_*", "Button", true, false):
		if String((b as Button).tooltip_text).begins_with(String(mv["name"])):
			found = b
	var nsteps := (pu._feats() as Array).size()
	ok(nsteps == 3 and found != null and found.icon == Icons.tex("part_move") and found.is_visible_in_tree(), "2 a part with a Move step refreshed 10x: %d steps, the Move step button shows the part_move icon (button found: %s)" % [nsteps, str(found != null)])
	DirAccess.make_dir_recursive_absolute(SHOT)
	await idle(3)
	root.get_texture().get_image().save_png(SHOT + "/timeline.png")
	print("s219: %d fail" % fails)
	quit(1 if fails > 0 else 0)
