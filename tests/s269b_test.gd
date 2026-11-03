extends SceneTree
## s269b FILM MODE v2: (1) the panel is fully opaque at 1600x900 and 1024x600; (2) the reflective floor follows keyed materials.
## Bars (written before the run):
##   MIRROR  reflect floor on, hue-cycle ring: the reflected ring's hue is within 0.02 of the ring's own hue (read from the rendered image) at t=0 and t=1
##   CONTROL a mirror left as it was made (old behaviour: not re-synced) at t=1 is red against the cyan ring: hue gap > 0.2 (fails the bar)
##   OPAQUE  at 1600x900 and 1024x600: the panel's pixels are identical with the app drawn under it and with a magenta slab instead (0 differing pixels)
##   CONTROL the same with the old 0.97 panel alpha: differing pixels > 1000 (the bar can fail)
##   FILL    the view texture and its rect have the same aspect (within 2 percent): no side bars
const SHOT_UI := "C:/Users/Nick/tools/kine_workers/out/s269b"
const DIRT := "user://s269b_test"
var fails := 0
var host: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func hd(a: float, b: float) -> float:
	var d := absf(fposmod(a, 1.0) - fposmod(b, 1.0))
	return minf(d, 1.0 - d)


func fixture() -> Dictionary:
	var rec := Part.make("Fan")
	Part.prim(rec, "box", {"x": -100.0, "y": 0.0, "z": -5.0, "w": 200.0, "h": 10.0, "d": 40.0, "name": "Fan"})
	(rec["features"] as Array).append(Part.new_feature(rec, "appear", {"body": 0, "preset": "Custom", "color": [0.5, 0.5, 0.55], "rough": 0.4, "metal": 0.6, "alpha": 1.0}))
	Part.prim(rec, "box", {"x": 130.0, "y": 0.0, "z": -20.0, "w": 40.0, "h": 40.0, "d": 40.0, "name": "Ring"})
	var f := {"body": 1, "preset": "Custom", "color": [0.1, 0.1, 0.1], "rough": 0.5, "metal": 0.0, "alpha": 1.0}
	f.merge(PartGlow.fields(Color(1, 0, 0), 4.0))
	(rec["features"] as Array).append(Part.new_feature(rec, "appear", f))
	return rec


func ring_hue_img(img: Image, stg: FilmStage) -> float:
	var it: Dictionary = stg.items[1]
	var c: Vector3 = (it["mi"] as MeshInstance3D).transform * (it["centre"] as Vector3)
	var q := stg.cam.global_transform.affine_inverse() * c
	var f := 1.0 / tan(deg_to_rad(stg.cam.fov) * 0.5)
	var sz := Vector2(stg.size)
	var px := Vector2((q.x / -q.z * f / (sz.x / sz.y) + 1.0) * 0.5 * sz.x, (1.0 - q.y / -q.z * f) * 0.5 * sz.y)
	return img.get_pixelv(Vector2i(px)).h



func mirror_pos(stg: FilmStage, i: int) -> Vector2i:
	var it: Dictionary = stg.items[i]
	var c: Vector3 = (it["mi"] as MeshInstance3D).transform * (it["centre"] as Vector3)
	c.y = 2.0 * stg.floor_y - c.y
	var q := stg.cam.global_transform.affine_inverse() * c
	var f := 1.0 / tan(deg_to_rad(stg.cam.fov) * 0.5)
	var sz := Vector2(stg.size)
	return Vector2i(Vector2((q.x / -q.z * f / (sz.x / sz.y) + 1.0) * 0.5 * sz.x, (1.0 - q.y / -q.z * f) * 0.5 * sz.y))


func _init() -> void:
	host = Node.new()
	root.add_child(host)
	await process_frame
	if not Part.available():
		print("SKIP: the CAD kernel is not available")
		quit(0)
		return
	var rec := fixture()
	Film.hue_cycle(rec, 1, 0.0, 4.0, 2.0, 1.0, 1.0, 4.0, 0.0, "glow")
	Film.spin(rec, 0, 1500.0, Vector3.UP)
	var stg := FilmStage.new(host, rec, Vector2i(960, 540))
	ok(stg.ok and stg.items.size() == 2 and stg.items[1].has("mir"), "stage built with a mirror per body")
	var hs: Array = []
	for t in [0.0, 1.0]:
		var img: Image = await stg.frame(t)
		var hr := ring_hue_img(img, stg)
		var mp := mirror_pos(stg, 1)
		var hm := img.get_pixelv(mp).h
		print("   t=%.1f ring hue %.3f, mirror px %s hue %.3f sat %.2f" % [t, hr, str(mp), hm, img.get_pixelv(mp).s])
		hs.append(hd(hr, hm))
		ok(hd(hr, hm) < 0.02 and img.get_pixelv(mp).s > 0.3, "MIRROR: t=%.0f reflected ring hue %.3f vs ring %.3f, gap %.4f (< 0.02)" % [t, hm, hr, hd(hr, hm)])
	stg.close()
	var old := FilmStage.new(host, rec, Vector2i(960, 540))
	await old.frame(0.0)
	for it in old.items:
		it.erase("mir")   # the mirror stays as made at t=0
	var io: Image = await old.frame(1.0)
	var gap := hd(ring_hue_img(io, old), io.get_pixelv(mirror_pos(old, 1)).h)
	ok(gap > 0.2, "CONTROL: an un-synced mirror at t=1 is %.3f hue off the ring (> 0.2, fails the bar)" % gap)
	old.close()
	await ui_bars()
	print("S269B ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)


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


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv, true)
	await process_frame
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)



func panel_diff(m: Node, panel: Control, name_: String) -> int:
	var rect := panel.get_global_rect()
	var a := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(SHOT_UI)
	a.save_png("%s/film_%s.png" % [SHOT_UI, name_])
	var hidden: Array = []
	for c in m.ui_root.get_children():
		if c != panel and c is CanvasItem and (c as CanvasItem).visible:
			(c as CanvasItem).visible = false
			hidden.append(c)
	var slab := ColorRect.new()
	slab.color = Color(1, 0, 1)
	slab.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.ui_root.add_child(slab)
	m.ui_root.move_child(slab, 0)
	var parent := m as Node
	var had_bg := RenderingServer.get_default_clear_color()
	RenderingServer.set_default_clear_color(Color(1, 0, 1))
	await idle(4)
	var b := root.get_texture().get_image()
	slab.queue_free()
	RenderingServer.set_default_clear_color(had_bg)
	for c in hidden:
		(c as CanvasItem).visible = true
	var n := 0
	var r := Rect2i(rect)
	for y in range(r.position.y, mini(r.end.y, a.get_height())):
		for x in range(r.position.x, mini(r.end.x, a.get_width())):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				n += 1
	return n


func ui_bars() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	await idle(4)
	var ss: StartScreen = m.start_screen
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT + "_ui"))
	ss.dirs_override = [DIRT + "_ui"]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	m.S.part = {}
	await process_frame
	m.S.part = fixture()
	await click_ctl(pu.part_btn)
	await idle(3)
	pu._view_model()
	await idle(3)
	for sz in [Vector2i(1600, 900), Vector2i(1024, 600)]:
		root.size = sz
		root.content_scale_size = sz
		await idle(6)
		var fb: Button = m.ui_root.find_child("part_film_btn", true, false)
		ok(fb != null and fb.is_visible_in_tree(), "%s: the Film button is there" % str(sz))
		if fb == null or not fb.is_visible_in_tree():
			continue
		await click_ctl(fb)
		await idle(8)
		var panel: PanelContainer = m.ui_root.find_child("film_panel", true, false)
		ok(panel != null and panel.visible, "%s: Film opens" % str(sz))
		if panel == null:
			continue
		var tex := panel.find_child("film_view", true, false) as TextureRect
		var ts := tex.texture.get_size()
		var ar := absf(ts.x / ts.y - tex.size.x / tex.size.y) / (tex.size.x / tex.size.y)
		ok(ar < 0.02, "FILL %s: texture %s in rect %s, aspect gap %.4f (< 0.02)" % [str(sz), str(ts), str(tex.size), ar])
		var d := await panel_diff(m, panel, "%dx%d" % [sz.x, sz.y])
		ok(d == 0, "OPAQUE %s: %d panel pixels differ with the app removed (0)" % [str(sz), d])
		var sbx := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		sbx.bg_color.a = 0.97
		panel.add_theme_stylebox_override("panel", sbx)
		await idle(3)
		var d2 := await panel_diff(m, panel, "%dx%d_alpha97_control" % [sz.x, sz.y])
		ok(d2 > 1000, "CONTROL %s: with alpha 0.97 (the old panel) %d pixels differ (> 1000, fails the bar)" % [str(sz), d2])
		await click_ctl(panel.find_child("film_close", true, false))
		await idle(3)
