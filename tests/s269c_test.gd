extends SceneTree
## s269c FILM MODE leftovers: (1) the camera frames the bodies AND their floor reflection; (2) film keys on bodies past 256; (3) spin / move keys drawn as curves.
## Bars (written before the first run):
##   FRAME    at stage sizes 1024x600 and 1600x900 (and the film's first and last moment): the screen box of the bodies plus the reflection the floor shows lies
##            inside the picture with >= 1 percent of its height spare on every side
##   CONTROL  the same with frame_mirror = false (the s269b framing): the reflection's bottom lies below the picture (> 100 percent of the height)
##   BIG      300 boxes of one look (the replay merges them to 256 surfaces); spin on body 280 and move on body 290: the stage has an item for each,
##            its mesh is that one box (size 10 mm +- 0.1), at t = 1 body 290 is at x = 0.05 m +- 1e-6 and body 280 is turned (basis differs from identity);
##            every vertex of the part is still drawn (vertex total equal to the plain replay)
##   CONTROL  the plain replay (the old stage) has no surface of body 280 or 290: the bar can fail
##   CURVES   the Film panel's curve strip, body with a spin (2 keys) and a move on X (2 keys): 2 dots on the spin channel at the keys' times (x within 0.6 px of
##            the time axis), a pixel of the channel colour (RGB distance < 0.15) under every dot in the screenshot; the other channels draw nothing
##   CONTROL  after Film.clear_body the strip has 0 dots and the same pixels are not the channel colour (distance > 0.3)
const SHOT_UI := "C:/Users/Nick/tools/kine_workers/out/s269c"
const DIRT := "user://s269c_test"
var fails := 0
var host: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func fixture() -> Dictionary:
	var rec := Part.make("Fan")
	Part.prim(rec, "box", {"x": -100.0, "y": 0.0, "z": -5.0, "w": 200.0, "h": 10.0, "d": 40.0, "name": "Fan"})
	(rec["features"] as Array).append(Part.new_feature(rec, "appear", {"body": 0, "preset": "Custom", "color": [0.5, 0.5, 0.55], "rough": 0.4, "metal": 0.6, "alpha": 1.0}))
	Part.prim(rec, "box", {"x": 130.0, "y": 0.0, "z": -20.0, "w": 40.0, "h": 40.0, "d": 40.0, "name": "Ring"})
	var f := {"body": 1, "preset": "Custom", "color": [0.1, 0.1, 0.1], "rough": 0.5, "metal": 0.0, "alpha": 1.0}
	f.merge(PartGlow.fields(Color(1, 0, 0), 4.0))
	(rec["features"] as Array).append(Part.new_feature(rec, "appear", f))
	return rec


## the screen rect (px) of the bodies plus the reflection the floor shows, for stage s at its current camera
func refl_rect(s: FilmStage) -> Rect2:
	var lo := maxf(2.0 * s.floor_y - s.box.end.y, s.floor_y - float(s.fade_h))
	var hi := 2.0 * s.floor_y - s.box.position.y
	var bb := s.box.merge(AABB(Vector3(s.box.position.x, lo, s.box.position.z), Vector3(s.box.size.x, maxf(hi - lo, 0.0), s.box.size.z)))
	return NiceRender._screen_box(s.cam, bb)


func inside(r: Rect2, sz: Vector2i) -> float:
	var h := float(sz.y)
	var w := float(sz.x)
	return minf(minf(r.position.y, h - r.end.y) / h, minf(r.position.x, w - r.end.x) / w)


func _init() -> void:
	host = Node.new()
	root.add_child(host)
	await process_frame
	if not Part.available():
		print("SKIP: the CAD kernel is not available")
		quit(0)
		return
	var rec := fixture()
	Film.spin(rec, 0, 1500.0, Vector3.UP)
	Film.move(rec, 1, [[0.0, Vector3.ZERO], [2.0, Vector3(100, 0, 0)]])
	for sz in [Vector2i(1024, 600), Vector2i(1600, 900)]:
		var st := FilmStage.new(host, rec, sz)
		var worst := 9.0
		for t in [0.0, Film.duration(rec)]:
			st.set_time(t)
			worst = minf(worst, inside(refl_rect(st), sz))
		print("   %s margin %.4f" % [str(sz), worst])
		ok(worst >= 0.01, "FRAME %s: the bodies and their reflection lie inside the picture, spare %.3f of the height (>= 0.01)" % [str(sz), worst])
		st.close()
		var old := FilmStage.new(host, rec, sz, {"frame_mirror": false})
		var m := refl_rect(old)
		var low := m.end.y / float(sz.y)
		ok(low > 1.0, "CONTROL FRAME %s: the s269b framing puts the reflection's bottom at %.3f of the height (> 1.0, cut off)" % [str(sz), low])
		old.close()
	await big()
	await ui_bars()
	print("S269C ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)


func big() -> void:
	var rec := Part.make("Many")
	for i in 300:
		Part.prim(rec, "box", {"x": float(i % 20) * 15.0, "y": 0.0, "z": float(i / 20) * 15.0, "w": 10.0, "h": 10.0, "d": 10.0, "name": "B%d" % i})
	Film.spin(rec, 280, 600.0, Vector3.UP)
	Film.move(rec, 290, [[0.0, Vector3.ZERO], [2.0, Vector3(100, 0, 0)]])
	var plain := Part.replay(rec)
	var pv := 0
	for s in (plain["mesh"] as ArrayMesh).get_surface_count():
		pv += ((plain["mesh"] as ArrayMesh).surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	ok((plain["mesh"] as ArrayMesh).get_surface_count() == 256 and not (plain["surf_body"] as Array).has(280) and not (plain["surf_body"] as Array).has(290), "CONTROL BIG: the plain replay has 256 surfaces and none for body 280 or 290 (%d surfaces)" % (plain["mesh"] as ArrayMesh).get_surface_count())
	var stg := FilmStage.new(host, rec, Vector2i(640, 360), {"reflect": false})
	ok(stg.ok, "BIG: the stage is built")
	var i280 := -1
	var i290 := -1
	var sv := 0
	for k in stg.items.size():
		var it: Dictionary = stg.items[k]
		sv += ((it["mi"] as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
		if int(it["body"]) == 280:
			i280 = k
		if int(it["body"]) == 290:
			i290 = k
	ok(i280 >= 0 and i290 >= 0, "BIG: an item for body 280 (%d) and for body 290 (%d)" % [i280, i290])
	if i280 >= 0 and i290 >= 0:
		for k in [i280, i290]:
			var sz: Vector3 = ((stg.items[k]["mi"] as MeshInstance3D).mesh as ArrayMesh).get_aabb().size
			ok(absf(sz.x - 0.01) < 1e-4 and absf(sz.y - 0.01) < 1e-4 and absf(sz.z - 0.01) < 1e-4, "BIG: item %d draws one 10 mm box, size %s" % [k, str(sz)])
		stg.set_time(1.0)
		var x290 := (stg.items[i290]["mi"] as MeshInstance3D).transform.origin.x
		ok(absf(x290 - 0.05) < 1e-6, "BIG: body 290 at t = 1 is at x = %.7f m (0.05)" % x290)
		stg.set_time(0.0125)   # 600 rpm = 3600 deg/s: 45 deg (t = 1 is ten whole turns, back at identity)
		var ang := rad_to_deg(absf((stg.items[i280]["mi"] as MeshInstance3D).transform.basis.get_euler().y))
		ok(absf(ang - 45.0) < 0.01, "BIG: body 280 at t = 0.0125 is turned %.3f deg (45)" % ang)
	ok(sv == pv, "BIG: every vertex is still drawn (%d of %d)" % [sv, pv])
	stg.close()


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


func cdist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


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
	var rec := fixture()
	Film.spin(rec, 0, 1500.0, Vector3.UP)
	Film.move(rec, 1, [[0.0, Vector3.ZERO], [2.0, Vector3(100, 0, 0)]])
	m.S.part = rec
	await click_ctl(pu.part_btn)
	await idle(3)
	pu._view_model()
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT_UI)
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
		var ui: FilmUI = fb.get_meta("film_ui")
		var panel: PanelContainer = m.ui_root.find_child("film_panel", true, false)
		ok(panel != null and panel.visible, "%s: Film opens" % str(sz))
		if panel == null:
			continue
		var worst := 9.0
		for t in [0.0, Film.duration(m.S.part)]:
			ui.stage.set_time(t)
			worst = minf(worst, inside(refl_rect(ui.stage), ui.stage.size))
		ok(worst >= 0.01, "FRAME %s: in the panel's own view (%s) the bodies and the reflection lie inside, spare %.3f (>= 0.01)" % [str(sz), str(ui.stage.size), worst])
		ui.body_pick.select(0)
		ui._show_time()
		ui.stage.set_time(0.5)
		ui._show_time()
		await idle(6)
		var cv: FilmCurves = ui.curves
		var d: Array = cv.dots()
		var okn := d.size() == 2
		for e in d:
			okn = okn and int(e["ch"]) == 0
		ok(okn, "CURVES %s: body 0 (spin) draws %d dots, all on the spin channel (2)" % [str(sz), d.size()])
		var img := root.get_texture().get_image()
		img.save_png("%s/film_%dx%d.png" % [SHOT_UI, sz.x, sz.y])
		var org := cv.get_global_rect().position
		var sc := float(img.get_width()) / float(root.content_scale_size.x)   # the window may be larger than the canvas size asked for
		var keys: Array = cv.chan_keys(0)
		for j in d.size():
			var e: Dictionary = d[j]
			var px := (org + (e["pos"] as Vector2)) * sc
			var dx := absf((e["pos"] as Vector2).x - cv.t_to_x(float(keys[j][0])))
			var c := img.get_pixelv(Vector2i(px))
			ok(dx < 0.6 and cdist(c, FilmCurves.COLS[0]) < 0.15, "CURVES %s: dot %d at t = %.2f is at x %.1f (axis %.1f) with the spin colour under it (distance %.3f < 0.15)" % [str(sz), j, e["t"], (e["pos"] as Vector2).x, cv.t_to_x(float(keys[j][0])), cdist(c, FilmCurves.COLS[0])])
		ui.body_pick.select(1)
		ui._show_time()
		await idle(4)
		var d1: Array = cv.dots()
		ok(d1.size() == 2 and int(d1[0]["ch"]) == 1, "CURVES %s: body 1 (move X) draws %d dots on channel %d (2 on channel 1)" % [str(sz), d1.size(), int(d1[0]["ch"]) if d1.size() > 0 else -1])
		# CONTROL: clear the keys of body 0, the same pixels are background
		ui.body_pick.select(0)
		var spots: Array = []
		for e in d:
			spots.append((org + (e["pos"] as Vector2)) * sc)
		ui._clear()
		await idle(6)
		var img2 := root.get_texture().get_image()
		var worst_c := 9.0
		for sp in spots:
			worst_c = minf(worst_c, cdist(img2.get_pixelv(Vector2i(sp as Vector2)), FilmCurves.COLS[0]))
		ok(cv.dots().is_empty() and worst_c > 0.3, "CONTROL CURVES %s: after Clear keys %d dots, the spin colour is gone from those pixels (distance %.3f > 0.3)" % [str(sz), cv.dots().size(), worst_c])
		await click_ctl(panel.find_child("film_close", true, false))
		await idle(3)
		m.S.part = fixture()
		Film.spin(m.S.part, 0, 1500.0, Vector3.UP)
		Film.move(m.S.part, 1, [[0.0, Vector3.ZERO], [2.0, Vector3(100, 0, 0)]])
		await idle(3)
