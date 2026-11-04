extends SceneTree
## godot --path . --position 4000,4000 -s tools/c60_shot.gd -- C:/Temp/claude/c60/after
## C60 look: the Part browser (cubes) with the Extrude dialog open at 1024x600; PNGs at idle frames 1, 4 and 40, plus the browser/side sizes each of those frames.
const Part := preload("res://scripts/build/part.gd")
var m: Node


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	for d in [null, true, false]:
		var e: InputEvent
		if d == null:
			e = InputEventMouseMotion.new()
		else:
			e = InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = d
			if d:
				e.button_mask = MOUSE_BUTTON_MASK_LEFT
		e.position = p
		e.global_position = p
		root.push_input(e, true)
		await process_frame
	await idle(3)


func _init() -> void:
	var out := "C:/Temp/claude/c60/shot"
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	var ss: StartScreen = m.start_screen
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://c60_shot"))
	ss.dirs_override = ["user://c60_shot"]
	ss.show_screen()
	await idle(3)
	if ss._easy_btn["building"].button_pressed:
		await click_ctl(ss._easy_btn["building"])
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(4)
	var rec := Part.make("Cubes")
	var feats: Array = []
	for k in [1, 2]:
		var x0: float = (k - 1) * 50.0
		feats.append({"t": "sketch", "id": "s%d" % k, "name": "Sketch%d" % k, "plane": "front", "ents": [{"k": "rect", "a": [x0, 0.0], "b": [x0 + 100.0, 100.0]}], "dims": []})
		feats.append({"t": "extrude", "id": "e%d" % k, "name": "Extrude%d" % k, "sketch": "s%d" % k, "dist": 100.0, "both": false, "op": "new"})
	rec["features"] = feats
	m.S.part = rec
	pu.upto = -1
	pu.sync()
	await idle(16)
	root.content_scale_size = Vector2i(1024, 600)
	root.size = Vector2i(1024, 600)
	await idle(8)
	pu.close_dialog()
	await idle(3)
	pu.open_dialog("Extrude", -1)
	var log := []
	for i in 41:
		await process_frame
		log.append("frame %d browser %s side %s" % [i, str(pu.browser.size), str(pu.side.size)])
		if i == 1 or i == 4 or i == 40:
			root.get_texture().get_image().save_png("%s_f%02d.png" % [out, i])
	print("\n".join(log))
	quit(0)
