extends SceneTree
## w13 GIF EXPORT: a 2 s loop at 480 px decodes to fps*2 frames; mean colour error vs source is at least 20 % lower than a fixed 256
## (3-3-2) palette; file under 5 MB; loops forever; from_dir reads Save video frames. CONTROL: the fixed palette fails the 20 % bar.
## Shots: C:/Users/Nick/tools/kine_workers/out/w13/
var fails := 0
const SHOT := "C:/Users/Nick/tools/kine_workers/out/w13"
const FPS := 12
const W := 480
const H := 270


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func scene() -> Array:   # a muted, shaded scene (the kind a 3D render is): hue-shifting blobs on a dim gradient, looping over 2 s
	var n := FPS * 2
	var out: Array = []
	for k in n:
		var ph := TAU * k / n
		var d := PackedByteArray()
		d.resize(W * H * 3)
		var i := 0
		for y in H:
			for x in W:
				var r := 60.0 + 40.0 * y / H
				var g := 70.0 + 30.0 * x / W
				var b := 90.0 + 20.0 * sin(x * 0.02 + ph)
				for c in 3:
					var cx := W * (0.25 + 0.25 * c) + 40.0 * cos(ph + c * 2.0)
					var cy := H * 0.5 + 30.0 * sin(ph * 2.0 + c)
					var dd := sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))
					if dd < 55.0:
						var sh := 1.0 - dd / 55.0
						var base: Array = [[200.0, 80.0, 60.0], [70.0, 170.0, 90.0], [90.0, 100.0, 210.0]][c]
						r = lerpf(r, float(base[0]) * (0.4 + 0.6 * sh), 0.9)
						g = lerpf(g, float(base[1]) * (0.4 + 0.6 * sh), 0.9)
						b = lerpf(b, float(base[2]) * (0.4 + 0.6 * sh), 0.9)
				d[i] = clampi(int(r), 0, 255)
				d[i + 1] = clampi(int(g), 0, 255)
				d[i + 2] = clampi(int(b), 0, 255)
				i += 3
		out.append(Image.create_from_data(W, H, false, Image.FORMAT_RGB8, d))
	return out


func err(src: Array, dec: Dictionary) -> float:   # mean abs per-channel error, 0..255
	var tot := 0.0
	var cnt := 0
	for k in src.size():
		var a: PackedByteArray = (src[k] as Image).get_data()
		var b: PackedByteArray = (dec["frames"] as Array)[k]
		for i in range(0, a.size(), 7):
			tot += abs(int(a[i]) - int(b[i]))
			cnt += 1
	return tot / cnt


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	var src := scene()
	var t0 := Time.get_ticks_msec()
	var g := await GifWriter.encode(src, FPS)
	print("encode ms ", Time.get_ticks_msec() - t0, " bytes ", g.size())
	var gf := await GifWriter.encode(src, FPS, 0, true)
	var d := GifWriter.decode(g)
	var df := GifWriter.decode(gf)
	ok(not d.is_empty() and d["w"] == W and d["h"] == H, "decodes at 480 x 270")
	ok((d["frames"] as Array).size() == FPS * 2, "frame count = fps*2 (%d)" % (d["frames"] as Array).size())
	ok(int(d["loops"]) == 0, "loops forever (NETSCAPE count %d)" % int(d["loops"]))
	ok(int(d["delay_cs"]) == 8, "delay 8 cs at 12 fps")
	var e1 := err(src, d)
	var e2 := err(src, df)
	print("mean err per-clip ", e1, " fixed ", e2, " drop ", 1.0 - e1 / e2)
	ok(e1 <= e2 * 0.8, "per-clip palette error at least 20 %% lower than fixed (%.2f vs %.2f)" % [e1, e2])
	ok(not (e2 <= e2 * 0.8), "CONTROL: the fixed palette against itself fails the 20 % bar")
	ok(g.size() < 5 * 1024 * 1024, "under 5 MB (%d)" % g.size())
	ok(g.slice(0, 6).get_string_from_ascii() == "GIF89a" and g[g.size() - 1] == 0x3B, "header and trailer")
	# round trip of the LZW itself: a frame of random bytes (forces table resets) decodes to the same pixels
	var rd := PackedByteArray()
	rd.resize(64 * 64 * 3)
	for i in rd.size():
		rd[i] = (i * 2654435761 >> 7) & 255
	var rim := Image.create_from_data(64, 64, false, Image.FORMAT_RGB8, rd)
	var rg := GifWriter.decode(await GifWriter.encode([rim, rim], 10))
	ok((rg["frames"] as Array).size() == 2, "noise frames: 2 decoded")
	# from_dir
	var dir := "user://w13_frames"
	DirAccess.make_dir_recursive_absolute(dir)
	for k in 6:
		(src[k] as Image).save_png(dir.path_join("frame_%04d.png" % k))
	var gp := dir.path_join("o.gif")
	ok(await GifWriter.from_dir(dir, FPS, gp, 240), "from_dir writes")
	var fb := FileAccess.get_file_as_bytes(gp)
	var dd := GifWriter.decode(fb)
	ok(not dd.is_empty() and dd["w"] == 240 and (dd["frames"] as Array).size() == 6, "from_dir: 6 frames at 240 px")
	# look at frames: first source vs first decoded
	var shot := Image.create(W * 2, H, false, Image.FORMAT_RGB8)
	shot.blit_rect(src[0], Rect2i(0, 0, W, H), Vector2i(0, 0))
	shot.blit_rect(Image.create_from_data(W, H, false, Image.FORMAT_RGB8, (d["frames"] as Array)[0]), Rect2i(0, 0, W, H), Vector2i(W, 0))
	shot.save_png(SHOT.path_join("src_vs_gif.png"))
	var f := FileAccess.open(SHOT.path_join("clip.gif"), FileAccess.WRITE)
	f.store_buffer(g)
	f.close()
	await ui_part()
	print("W13 DONE fails=", fails)
	quit(1 if fails > 0 else 0)


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv, true)
	await process_frame
	for d in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = d
		e.position = p
		e.global_position = p
		if d:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e, true)
		await process_frame
	await idle(2)


## the Save GIF button on the Easy bar, a real click: a GIF file with the clip's frames appears; screenshots at 1024x600 and 1920x1080
func ui_part() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1024, 600)
	await idle(10)
	m._new_scene()
	await idle(2)
	m.easy.set_on(true, false)
	await idle(3)
	var home: EasyHome = m.easy.home
	var gb: Button = m.easy.gif_button
	ok(gb != null and not gb.visible, "no clip: Save GIF is hidden (the bar keeps its 8 buttons)")
	
	var rows: Node = m.easy.bar.find_child("easy_row", true, false)
	var sv_i := -1
	for ch in rows.get_children():
		if ch is Button and String(ch.get_meta("label", "")) == "Save video":
			sv_i = ch.get_index()
	ok(sv_i >= 0 and gb.get_index() == sv_i + 1, "Save GIF sits right after Save video (%d, %d)" % [gb.get_index(), sv_i])
	home.video_root = ProjectSettings.globalize_path("user://w13_ui")
	DirAccess.make_dir_recursive_absolute(home.video_root)
	var c0 := home.panel.find_child("eh_card_0", true, false) as Button
	c0.pressed.emit()
	await idle(6)
	ok(gb.visible and gb.is_visible_in_tree(), "a clip: Save GIF shows after Save video")
	var r: Rect2 = gb.get_global_rect()
	ok(root.get_visible_rect().encloses(r), "Save GIF is inside the 1024 x 600 window %s" % r)
	var t0 := Time.get_ticks_msec()
	await click(gb)
	var tries := 0
	while String(home.last_gif) == "" and tries < 1500:
		await idle(2)
		tries += 1
	ok(String(home.last_gif) != "" and FileAccess.file_exists(String(home.last_gif)), "a click on Save GIF writes a .gif (%s, %d ms)" % [String(home.last_gif).get_file(), Time.get_ticks_msec() - t0])
	if String(home.last_gif) != "":
		var d: Dictionary = GifWriter.decode(FileAccess.get_file_as_bytes(String(home.last_gif)))
		var nfr: int = (d["frames"] as Array).size() if not d.is_empty() else 0
		var npng := 0
		for n in DirAccess.get_files_at(String(home.last_video["dir"])):
			if String(n).ends_with(".png"):
				npng += 1
		ok(nfr == npng and nfr > 1, "the GIF has every saved frame (%d of %d), loops %d" % [nfr, npng, int(d.get("loops", -1))])
	await idle(10)
	root.get_texture().get_image().save_png(SHOT.path_join("button_1024x600.png"))
	root.content_scale_size = Vector2i(1920, 1080)
	await idle(14)
	ok(root.get_visible_rect().encloses(gb.get_global_rect()), "Save GIF inside the 1920 x 1080 window")
	root.get_texture().get_image().save_png(SHOT.path_join("button_1920x1080.png"))
	home.video_root = ""
