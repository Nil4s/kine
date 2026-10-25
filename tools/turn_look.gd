## godot --path . -s tools/turn_look.gd -- <out.png>    (needs a window) the turn around in the app itself, Easy mode, the front
## view: four instants of templates/turn_around.json in one sheet (the frames as the app plays them, not the bake's numbers).
extends SceneTree

var m: Node


func grab() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()


func _init() -> void:
	var out := "C:/Temp/claude/turn_sheet.png"
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	EasyMode.start_fresh = true
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 7:
		await process_frame
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.S.from_dict(Templates.read("turn_around"))
	m.S.name = "zz_turn_look"
	m._rebuild_cards()
	m.sel_card = -1
	for i in 4:
		await process_frame
	m._view_home(false)
	var T: float = m.S.length()
	var imgs := []
	for f in [0.12, 0.38, 0.62, 0.97]:
		m.playhead = T * f
		m._ps().apply(m.B, T * f)
		m._refresh()
		m._turn_to(0.0, -4.0, 3.2, Vector3(0.0, 0.75, 0.0), false)
		for i in 4:
			await process_frame
		imgs.append(await grab())
		print("FRAME t=%.2f of %.2f" % [T * f, T])
	var w: int = imgs[0].get_width()
	var h: int = imgs[0].get_height()
	var cw := w / 2
	var ch := h / 2
	var sheet := Image.create(cw * 4, ch, false, Image.FORMAT_RGBA8)
	for i in imgs.size():
		var im: Image = imgs[i]
		im.convert(Image.FORMAT_RGBA8)
		im.resize(cw, ch, Image.INTERPOLATE_LANCZOS)
		im.save_png(out.replace(".png", "_%d.png" % i))
		sheet.blit_rect(im, Rect2i(0, 0, cw, ch), Vector2i(i * cw, 0))
	sheet.save_png(out)
	print("saved ", out, " ", sheet.get_size())
	quit()
