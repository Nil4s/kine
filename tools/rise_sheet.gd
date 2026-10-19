## godot --path . -s tools/rise_sheet.gd -- <out.png>    (needs a window) a sheet of the get-up rendered in the app itself:
## the app's own cards (SET > Get up), its own camera (His right view), seven instants, whole body.
extends SceneTree

var m: Node


func grab() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()


func _init() -> void:
	var out := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/situp.png"
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 7:
		await process_frame
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.S.name = "zz_rise_sheet"
	m.S.cards.clear()   # an empty scene: the run is all there is
	m.sel_card = -1
	m._rise_get_up()
	for i in 4:
		await process_frame
	m._big_view()
	if m.dummy_on:
		m._dummy_toggle()   # the target dummy off
	var ts: Array = m.S.times()
	var an: Array = Rise.get_up(m.B, Vector2.ZERO)["report"]["anchors"]
	var anchors := [an[0], an[1], an[2], an[3], an[4], an[5], an[6]]   # supine, side, prop, long-sit, kneel, half-kneel, stand
	var imgs := []
	for k in anchors:
		var t: float = ts[k][1]
		m.playhead = t
		m._ps().apply(m.B, t)
		m._refresh()
		m._turn_to(-90.0, -6.0, 5.8, Vector3(0.0, 0.9, 0.15), false)
		for i in 4:
			await process_frame
		imgs.append(await grab())
		print("FRAME card %d (%s) t=%.2f" % [k, m.S.cards[k]["name"], t])
	var w: int = imgs[0].get_width()
	var h: int = imgs[0].get_height()
	var cw := w / 2
	var ch := int(h * 0.62) / 2
	var sheet := Image.create(cw * 4, ch * 2, false, Image.FORMAT_RGBA8)
	for i in imgs.size():
		var im: Image = imgs[i]
		im.convert(Image.FORMAT_RGBA8)
		im = im.get_region(Rect2i(0, int(im.get_height() * 0.08), im.get_width(), int(im.get_height() * 0.62)))
		im.resize(cw, ch, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(im, Rect2i(0, 0, cw, ch), Vector2i((i % 4) * cw, (i / 4) * ch))
	sheet.save_png(out)
	print("saved ", out, " ", sheet.get_size())
	quit()
