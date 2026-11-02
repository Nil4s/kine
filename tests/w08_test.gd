## godot --path . -s tests/w08_test.gd [-- --shot=C:/x.png]     W08: IN PLACE / TRAVELLING toggle on a clip, applied live
## BARS (written before the numbers): walk_bat clip, In place ON: the hips' net horizontal travel over the loop < 1 cm (and the
## largest horizontal excursion from the start < 1 cm); OFF again: within 1 mm of the source played by hand at every sample;
## ON changes no joint angle and no height; the toggle is ONE undo step, undo returns the travelling walk; file round trip keeps it.
## CONTROL: the clip with the flag off MUST travel more than 10 cm (else the bar could not fail).
extends SceneTree
const SRC := "scenes/walk_bat.json"
var fails := 0

func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1

func body() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b

func lum(c: Color) -> float:
	var f := func(x: float) -> float: return x / 12.92 if x <= 0.03928 else pow((x + 0.055) / 1.055, 2.4)
	return 0.2126 * f.call(c.r) + 0.7152 * f.call(c.g) + 0.0722 * f.call(c.b)

func hz(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)

func _init() -> void:
	var B := body()
	var R := body()
	var src := Scene.new()
	src.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://" + SRC)))
	var L := src.length()
	var S := Scene.new()
	S.add("a", B.to_dict())
	S.clips = [Clips.make(SRC, 0.0)]
	var n := 60
	var pos0 := Vector3.ZERO
	var net_off := 0.0
	var net_on := 0.0
	var ex_on := 0.0
	var d_off := 0.0
	var ang := 0.0
	var dy := 0.0
	S.apply(B, 0.0)
	pos0 = B.offset
	for i in n + 1:
		var t := L * i / n
		S.clips = [Clips.make(SRC, 0.0)]
		S.apply(B, t)
		var off_o := B.offset
		var ang_o := B.ang.duplicate()
		src.apply(R, t)
		d_off = maxf(d_off, (off_o - R.offset).length())
		if i == n:
			net_off = hz(off_o - pos0).length()
		S.clips = [Clips.make(SRC, 0.0, {"inplace": true})]
		S.apply(B, t)
		ex_on = maxf(ex_on, hz(B.offset - pos0).length())
		dy = maxf(dy, absf(B.offset.y - off_o.y))
		for j in Body.ORDER:
			ang = maxf(ang, ((B.ang[j] as Vector3) - (ang_o[j] as Vector3)).length())
		if i == n:
			net_on = hz(B.offset - pos0).length()
	ok(net_off > 0.10, "control: flag off travels %.1f cm over the loop (> 10)" % (net_off * 100))
	ok(net_on < 0.01 and ex_on < 0.01, "IN PLACE on: net travel %.3f cm, worst excursion %.3f cm (< 1 cm)" % [net_on * 100, ex_on * 100])
	ok(d_off < 0.001, "OFF: hips within %.4f mm of the source played by hand (< 1 mm)" % (d_off * 1000))
	ok(ang < 1e-4 and dy < 1e-6, "ON changes no joint (%.6f) and no height (%.6f)" % [ang, dy])
	var d := Clips.clean(Clips.make(SRC, 0.0, {"inplace": true}))
	var r := Clips.from_file(JSON.parse_string(JSON.stringify(Clips.to_file([d]))))
	ok(bool(r[0].get("inplace", false)) and not Clips.make(SRC, 0.0).has("inplace"), "file round trip keeps the flag; absent when off")
	await app_part()
	print("W08 TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)

func app_part() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	for i in 3:
		await process_frame
	m.S = Scene.new()
	m.S.add("a", m.B.to_dict())
	m.scene_path = ""
	m._rebuild_cards()
	m.undo.clear()
	m.clips_ui.place(SRC, 0.0, {})
	for i in 4:
		await process_frame
	var L := float(Clips.source(SRC)["len"])
	var u0: int = m.undo.size()
	var tl: Timeline = m.ui_timeline
	await size_to(1024, 600)
	ok(root.get_visible_rect().size == Vector2(1024, 600), "layout really is 1024x600 (visible rect %s)" % root.get_visible_rect().size)
	var cr: Rect2 = tl.inplace_rect(0)
	ok(cr.size.y >= 18.0 and cr.position.x >= 0.0 and cr.end.x <= tl.size.x and cr.position.y >= 0.0 and cr.end.y <= tl.size.y, "chip is %.0f px tall, fully inside the strip (%s of %s)" % [cr.size.y, cr, tl.size])
	var gr := Rect2(tl.get_global_rect().position + cr.position, cr.size)
	var hit_tr := []
	for nd in m.find_children("*", "Control", true, false):
		var c2 := nd as Control
		if c2.is_visible_in_tree() and c2 != tl and not c2.is_ancestor_of(tl) and not tl.is_ancestor_of(c2) and (c2 is Button or c2 is CheckBox) and c2.get_global_rect().intersects(gr) and String(c2.get("text")) in ["Real speed", "Loop", "Natural", "speed"]:
			hit_tr.append(String(c2.get("text")))
	ok(hit_tr.is_empty(), "chip does not touch the transport controls %s" % str(hit_tr))
	for pair in [[Timeline.CHIP_OFF_FILL, Timeline.CHIP_OFF_INK], [Timeline.CHIP_ON_FILL, Timeline.CHIP_ON_INK]]:
		var l1: float = lum(pair[0])
		var l2: float = lum(pair[1])
		var cr2 := (maxf(l1, l2) + 0.05) / (minf(l1, l2) + 0.05)
		ok(cr2 >= 4.5, "chip text contrast %.1f:1 (>= 4.5)" % cr2)
	for pr in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pr
		ev.position = cr.get_center()
		tl._gui_input(ev)
	ok(m.undo.size() == u0 + 1 and bool(m.S.clips[0].get("inplace", false)), "toggle on: ONE undo step (%d)" % (m.undo.size() - u0))
	m.S.apply(m.B, 0.0)
	var p0: Vector3 = m.B.offset
	m.S.apply(m.B, L)
	var on_off: float = hz(m.B.offset - p0).length()
	var ids: Array = m._commands().map(func(c): return c["id"])
	ok("clip_in_place_/_travelling" in ids or ids.any(func(i): return String(i).begins_with("clip_in_place")), "command is in the registry")
	m._undo()
	m.S.apply(m.B, 0.0)
	p0 = m.B.offset
	m.S.apply(m.B, L)
	var trav: float = hz(m.B.offset - p0).length()
	ok(not bool(m.S.clips[0].get("inplace", false)) and trav > on_off + 0.05, "undo returns the travelling walk (travel %.2f m vs %.3f m on the spot)" % [trav, on_off])
	m._redo()
	m.clips_ui.toggle_inplace()
	ok(not bool(m.S.clips[0].get("inplace", false)), "second toggle turns it off again")
	m.clips_ui.toggle_inplace()
	for i in 3:
		await process_frame
	m.playhead = L * 0.5
	m.S.apply(m.B, m.playhead)
	m._refresh()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			for wh in [[1024, 600], [1920, 1080]]:
				await size_to(wh[0], wh[1])
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(a.substr(7) + "_%dx%d.png" % [wh[0], wh[1]])
	m.queue_free()
	await process_frame


func size_to(w: int, h: int) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(w, h)
	for i in 14:
		await process_frame
