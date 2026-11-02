extends SceneTree
## s269 FILM KEYS (ledger 269): looks keyed in time (colour, emission colour + strength, hue-cycle helper), body spin (rpm + extrapolation) and move,
## all on the part record, played and exported in the dark studio ("Film" mode).
## Fixture: "Fan" (a 200 x 10 x 40 mm blade, built at x -100..100) and "Ring" (a 40 mm box, emissive).
## Bars (written before the code ran):
##   1 HUE      hue_cycle(h0 0, 2 cycles over 4 s): the ring's emission hue at t = 0, 0.5, 1.0, 1.3 (off a key), 2.0, 3.7 equals the keyed hue
##              fposmod(2 t / 4) within 0.002 (0.7 deg), read from look_at AND from the stage material; the rendered ring at t = 1.0 (cyan) is
##              within 0.06 hue of 0.5 and at 0 (red) of 0
##   2 FAN      1500 rpm about Y: at t = 2.0 the fan is at 18000 deg (= 50 turns): a blade tip is back where it started within 1e-5;
##              at t = 2.01 it is at 90 deg; the stage's body transform is the same
##   3 FRAMES   8 frames of the playback (play_step at 1/25 s) are pixel-identical to the exported PNGs (max channel difference 0)
##   4 SAVED    through JSON and Part.from_file the film keys read back the same (same hue at t = 1.3, same angle at 2.01)
##   CONTROL    before the change a look has no keys: the unkeyed look has the same glow at t 0 and 1, which FAILS bar 1;
##              the old hold read (constant extrapolation) puts the fan at 0 deg at 2.01, which FAILS bar 2
##   5 UI       the Film button opens the panel, Hue cycle / Spin / Export buttons act, one undo step per edit (see ui_bars)
const SHOT_UI := "C:/Users/Nick/tools/kine_workers/out/s269"
const DIRT := "user://s269_test"
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


func _init() -> void:
	host = Node.new()
	root.add_child(host)
	await process_frame
	if not Part.available():
		print("SKIP: the CAD kernel is not available")
		quit(0)
		return
	var rec := fixture()
	var old_look := Part.look_of(rec["features"][3])   # the ring's appear step, as before the change
	Film.hue_cycle(rec, 1, 0.0, 4.0, 2.0, 1.0, 1.0, 4.0, 0.0, "glow")
	Film.spin(rec, 0, 1500.0, Vector3.UP)
	var base := Part.look_of(rec["features"][3])
	var ts := [0.0, 0.5, 1.0, 1.3, 2.0, 3.7]
	var worst := 0.0
	for t in ts:
		var l := Film.look_at(rec, 1, t, base)
		worst = maxf(worst, hd((l["glow"] as Color).h, 2.0 * t / 4.0))
	ok(worst < 0.002, "1 HUE: look_at hue vs keyed hue at 6 times, worst %.5f (< 0.002)" % worst)
	var stg := FilmStage.new(host, rec, Vector2i(640, 360))
	ok(stg.ok and stg.items.size() == 2, "stage built: %d bodies" % stg.items.size())
	var worst2 := 0.0
	for t in ts:
		stg.set_time(t)
		worst2 = maxf(worst2, hd(((stg.items[1]["mat"] as StandardMaterial3D).emission).h, 2.0 * t / 4.0))
	ok(worst2 < 0.002, "1 HUE: stage material emission hue, worst %.5f (< 0.002)" % worst2)
	var img0: Image = await stg.frame(0.0)
	var img1: Image = await stg.frame(1.0)
	var h0 := ring_hue_img(img0, stg)
	var h1 := ring_hue_img(img1, stg)
	ok(hd(h0, 0.0) < 0.06 and hd(h1, 0.5) < 0.06, "1 HUE: rendered ring hue %.3f at t=0 (0) and %.3f at t=1 (0.5)" % [h0, h1])
	var oldh := (old_look["glow"] as Color).h
	ok(not (hd(oldh, 0.5) < 0.002), "CONTROL: the look without keys has hue %.3f at t=1 (keyed: 0.5), which fails bar 1" % oldh)
	# 2 FAN
	var c0: Vector3 = stg.items[0]["centre"]
	var dtip := Vector3(0.1, 0, 0)
	var x2 := Film.xform_at(rec, 0, 2.0, c0)
	var x201 := Film.xform_at(rec, 0, 2.01, c0)
	var q2 := x2 * (c0 + dtip)
	var q201 := x201 * (c0 + dtip)
	ok(Film.spin_deg(rec, 0, 2.0) == 18000.0 and q2.distance_to(c0 + dtip) < 1e-5, "2 FAN: 1500 rpm at t=2 s is %.3f deg, tip back at start (err %s)" % [Film.spin_deg(rec, 0, 2.0), str(q2.distance_to(c0 + dtip))])
	var want201 := c0 + Basis(Vector3.UP, deg_to_rad(90.0)) * dtip
	ok(q201.distance_to(want201) < 1e-5, "2 FAN: at t=2.01 s the tip is at 90 deg (err %s)" % q201.distance_to(want201))
	stg.set_time(2.01)
	var sx: Transform3D = (stg.items[0]["mi"] as MeshInstance3D).transform
	ok((sx * (c0 + dtip)).distance_to(want201) < 1e-5, "2 FAN: the stage's body transform agrees")
	var held := fposmod(float(Curves.eval(rec["film"]["spins"][0]["track"], 2.01, "constant")), 360.0)
	ok(absf(held - 90.0) > 1.0, "CONTROL: the old hold read gives %.1f deg at t=2.01 (needs 90), which fails bar 2" % held)
	# 3 FRAMES
	stg.close()
	var play := FilmStage.new(host, rec, Vector2i(480, 270))
	var seq: Array = []
	play.set_time(0.0)
	for i in 8:
		seq.append(await play.grab())
		play.play_step(1.0 / 25.0)
	play.close()
	var dir := ProjectSettings.globalize_path(DIRT)
	var n := await FilmStage.export(host, rec, dir, 25, Vector2i(480, 270))
	var maxd := 0
	for i in 8:
		var e := Image.load_from_file("%s/frame_%04d.png" % [dir, i])
		e.convert(Image.FORMAT_RGBA8)
		var a: PackedByteArray = e.get_data()
		var b: PackedByteArray = (seq[i] as Image).get_data()
		for k in a.size():
			maxd = maxi(maxd, absi(int(a[k]) - int(b[k])))
	ok(n == int(Film.duration(rec) * 25.0) and maxd == 0, "3 FRAMES: %d frames exported; playback vs export, 8 frames, max channel difference %d (0)" % [n, maxd])
	ok((seq[0] as Image).get_data() != (seq[4] as Image).get_data(), "3 FRAMES: the frames differ over time (the film moves)")
	# 4 SAVED
	var back := Part.from_file(JSON.parse_string(JSON.stringify(rec)))
	var bl := Film.look_at(back, 1, 1.3, Part.look_of(back["features"][3]))
	ok(hd((bl["glow"] as Color).h, 2.0 * 1.3 / 4.0) < 0.002 and absf(Film.spin_deg(back, 0, 2.01) - 18090.0) < 1e-6, "4 SAVED: film keys survive JSON + from_file")
	var nof := Part.from_file(JSON.parse_string(JSON.stringify(fixture())))
	ok(not nof.has("film") and not Film.has_any(nof), "4 SAVED: a part without film keys has no film field")
	# colour keys, strength, move
	var r2 := fixture()
	Film.key_look(r2, 0, 0.0, Color(1, 0, 0), null, null)
	Film.key_look(r2, 0, 2.0, Color(0, 1, 0), null, null)
	var mid := Film.look_at(r2, 0, 1.0, Part.look_of(r2["features"][1]))
	ok(absf((mid["c"] as Color).h - 1.0 / 6.0) < 0.002, "colour keys blend through yellow (hue %.3f)" % (mid["c"] as Color).h)
	Film.key_look(r2, 1, 0.0, null, null, 0.0)
	Film.key_look(r2, 1, 2.0, null, null, 8.0)
	ok(absf(float(Film.look_at(r2, 1, 1.0, Part.look_of(r2["features"][3]))["glow_k"]) - 4.0) < 1e-6, "emission strength key: 4.0 at the midpoint")
	Film.move(r2, 1, [[0.0, Vector3.ZERO], [2.0, Vector3(100, 0, 0)]])
	ok(Film.offset_at(r2, 1, 1.0).distance_to(Vector3(0.05, 0, 0)) < 1e-6, "move key: 50 mm at the midpoint")
	await ui_bars()
	print("S269 ", "PASS" if fails == 0 else "FAIL %d" % fails)
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


func ui_bars() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
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
	var fb: Button = m.ui_root.find_child("part_film_btn", true, false)
	ok(fb != null and fb.is_visible_in_tree(), "5 UI: the Film button is on the Part panel")
	if fb == null or not fb.is_visible_in_tree():
		return
	var n0: int = m.undo.size()
	await click_ctl(fb)
	await idle(4)
	var panel: Control = m.ui_root.find_child("film_panel", true, false)
	ok(panel != null and panel.visible, "5 UI: Film mode opens")
	if panel == null:
		return
	var pick := panel.find_child("film_body", true, false) as OptionButton
	pick.select(1)
	await click_ctl(panel.find_child("film_hue", true, false))
	await click_ctl(panel.find_child("film_spin", true, false))
	await idle(3)
	var film: Dictionary = m.S.part.get("film", {})
	ok((film.get("looks", []) as Array).size() == 1 and (film.get("spins", []) as Array).size() == 1 and m.undo.size() == n0 + 2, "5 UI: Hue cycle and Spin keyed on the ring (%d undo steps, 2)" % (m.undo.size() - n0))
	var sl := panel.find_child("film_slider", true, false) as HSlider
	sl.value = 1.0
	await idle(6)
	DirAccess.make_dir_recursive_absolute(SHOT_UI)
	root.get_texture().get_image().save_png("%s/film_%dx%d.png" % [SHOT_UI, root.size.x, root.size.y])
	var tl := panel.find_child("film_time", true, false) as Label
	ok(tl.text.contains("1.00"), "5 UI: the timeline slider moved the film to t = 1 (%s)" % tl.text.strip_edges())
	await click_ctl(panel.find_child("film_export", true, false))
	var st := panel.find_child("film_status", true, false) as Label
	for i in 400:
		if st.text.begins_with("Exported"):
			break
		await idle(5)
	ok(st.text.begins_with("Exported 100 frames"), "5 UI: Export wrote the frames (%s)" % st.text)
	await click_ctl(panel.find_child("film_close", true, false))
	await idle(3)
	m._undo()
	await idle(2)
