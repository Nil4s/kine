## godot --path . -s tools/make_easy_tips.gd [-- only=pull,spin out=user://somewhere/]     (p094, Friday plan 94; needs the CAD DLL and a window)
## Makes the Easy Part tooltip clips (assets/tips/easy/): the app drives ITSELF with real clicks and real drags on a sample part
## (a 100 x 100 mm box pulled up 20 mm) and the tool captures the 3D view around the part while the action happens:
## 14 frames of 200 x 120 per MAKE button, 12 fps, one PNG sheet (7 x 2) per button + tips.json. Every clip: a few frames of the
## part BEFORE, the real press (or the real drag), then the part AFTER, with the camera swaying a little so the clip always moves.
## Nothing is saved but the clips (the part lives in memory and the app is thrown away at the end).
extends SceneTree

const N := 14
const FPS := 12
const W := 200
const H := 120
const COLS := 7
const OUT := "res://assets/tips/easy/"
const IDS := ["draw", "pull", "spin", "round", "hole", "mirror", "curve", "blend", "split", "colour", "repeat", "stick"]
const SWAY := 20.0    # degrees of camera yaw over the whole clip

var m: Node
var out_dir := OUT
var shots: Array = []
var yaw0 := 25.0
var cam_dist := 0.5
var cam_target := Vector3.ZERO
var locked := false
var k_shot := 0       # frames taken so far in this clip (the camera sway follows it)
var mid := Vector3(0.0, 0.01, 0.0)   # the world point the crop is centred on


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func win(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = win(p)
	e.global_position = win(p)
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = win(p)
	e.global_position = win(p)
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func ep():
	return m.bld.part.ep


func pu():
	return m.bld.part


func press(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func scr(w: Vector3) -> Vector2:
	lock_cam()
	return m.cam.unproject_position(w)


## the camera is the clip's own, not the app's auto-framing (which re-frames after every step and would make the clip jump)
func lock_cam() -> void:
	if not locked:
		ep()._ease_end()
		return
	ep()._ease = {}
	m.target = cam_target
	m.dist = cam_dist
	m._cam()


func sway() -> void:
	lock_cam()
	m.yaw = yaw0 + SWAY * float(k_shot) / float(N - 1)
	m._cam()


## one frame: the camera sways, the view is cut to 5:3 about the part and shrunk to 200 x 120
func shoot() -> void:
	sway()
	sway()
	var hid := [] if OS.get_cmdline_user_args().has("nohide") else hide_panels()   # the picture is the part, its drawn shape and the grid, no Easy Part buttons or chips
	await idle(2)
	await RenderingServer.frame_post_draw
	var full := root.get_texture().get_image()
	for c in hid:
		(c as Control).modulate.a = 1.0
	var f := root.get_final_transform()
	var c := f * scr(mid)
	var sc: float = f.get_scale().x
	var s100 := scr(mid + Vector3(0.05, 0, 0)).distance_to(scr(mid - Vector3(0.05, 0, 0)))   # 100 mm in canvas units: the crop follows the app's own framing
	var cw := clampf(2.1 * s100, 160.0, 900.0) * sc
	var ch := cw * 0.6
	var r := Rect2(c.x - cw * 0.5, c.y - ch * 0.5, cw, ch)
	r.position.x = clampf(r.position.x, 0.0, full.get_width() - cw)
	r.position.y = clampf(r.position.y, 0.0, full.get_height() - ch)
	var img := full.get_region(Rect2i(r))
	img.resize(W, H, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGB8)
	var d := img.get_data()
	for i in d.size():
		d[i] = d[i] & 0xF8   # 5 bits a channel: the sheets compress much smaller, the banding is below what 200 x 120 shows
	if k_shot == 8 and OS.get_cmdline_user_args().has("dbg"):
		for sl in m.ui_root.find_children("easypart_slider_*", "HSlider", true, false):
			if (sl as Control).is_visible_in_tree():
				print("   slider ", sl.name, " ", (sl as HSlider).min_value, "..", (sl as HSlider).max_value, " = ", (sl as HSlider).value)
	if k_shot == 1 and OS.get_cmdline_user_args().has("dbg"):
		full.save_png("C:/Temp/claude/s094/full_%d.png" % shots.size())
	if k_shot == 7 and OS.get_cmdline_user_args().has("dbg"):
		for n in m.ui_root.find_children("*", "Control", true, false):
			var cn := n as Control
			if cn.is_visible_in_tree() and cn.get_global_rect().intersects(Rect2(r.position / sc, r.size / sc)) and cn.get_global_rect().size.x > 100:
				print("   over: ", cn.get_path(), cn.get_global_rect())
	if k_shot == 0 or k_shot == 7:
		print("  dbg frame %d crop %s of %s mid at %s msg '%s'" % [k_shot, r, full.get_size(), c, ep().msg])
	shots.append(Image.create_from_data(W, H, false, Image.FORMAT_RGB8, d))
	k_shot += 1


## hides Easy Part's own panels (the sketch lines are drawn by the view, not by them); returns the ones it hid
func hide_panels() -> Array:
	var hid := []
	for nm in ["bar", "make_box", "view_box", "panel", "shape_box", "colour_box", "repeat_box", "stick_box", "explode_box", "tilt_box", "size_box", "hint", "status", "hole_box", "split_box", "round_box"]:
		var c = ep().get(nm)
		if c is Control and (c as Control).visible:
			(c as Control).modulate.a = 0.0   # not .visible: the page's own sync shows them again every frame
			hid.append(c)
	return hid


func hold(n: int) -> void:
	for i in n:
		await shoot()


func fresh() -> void:
	if m != null:
		m.queue_free()
		await idle(2)
	locked = false
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://make_easy_tips"))
	ss.dirs_override = ["user://make_easy_tips"]
	ss.show_screen()
	await idle(3)
	await press(ss._cards["building"])
	await idle(3)
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu().set_on(false)
	pu().m.S.part = {}
	await process_frame
	await press(pu().part_btn)
	await idle(3)
	await press(pu().easy_open_btn)
	await idle(4)
	m.S.part = Part.make("Part")
	pu().upto = -1
	pu().sync()
	m.target = Vector3(0.0, 0.0, 0.0)
	m.pitch = -38.0
	m.yaw = yaw0
	m._cam()
	await idle(40)
	# the app's own framing of the sample part (60 x 60 x 20 mm): its distance and look-at point are the clip's camera, kept for every frame
	await box(-0.03, -0.03, 0.03, 0.03)
	await make("pull")
	ep()._ease_end()
	cam_dist = m.dist
	locked = true
	cam_target = m.target
	print("  camera of the app on the sample: dist %.3f target %s" % [cam_dist, cam_target])
	m.S.part = Part.make("Part")
	pu().upto = -1
	pu().sync()
	await idle(40)
	shots.clear()
	k_shot = 0
	mid = Vector3(0.0, 0.01, 0.0)


## a drag on the floor from world a to world b (metres); `cap` frames are taken along it (0: none)
func draw_floor(a: Vector3, b: Vector3, cap := 0) -> void:
	var pa := scr(a)
	var pb := scr(b)
	await ev_move(pa, false)
	await ev_mouse(pa, true)
	for i in range(1, 13):
		await ev_move(pa.lerp(pb, i / 12.0))
		if cap > 0 and i % (12 / cap) == 0:
			await shoot()
	await ev_mouse(pb, false)
	await idle(3)


func box(x0: float, z0: float, x1: float, z1: float) -> void:
	await press(ep().make_btns["draw"])
	lock_cam()
	await idle(4)
	await draw_floor(Vector3(x0, 0.0, z0), Vector3(x1, 0.0, z1))


func make(which: String) -> void:
	await press(ep().make_btns[which])
	await idle(3)


func sample(pulled := true) -> void:
	await box(-0.03, -0.03, 0.03, 0.03)
	if pulled:
		await make("pull")


## the clip `id`: what is built before the first frame, then the frames
## the tweak slider of the step just made (easypart_slider_last or _count), moved by the app's own control from a to b over the rest of the clip
func ramp(a: float, b: float, lead: int) -> void:
	var sl: HSlider = null
	for c in m.ui_root.find_children("easypart_slider_*", "HSlider", true, false):
		if (c as Control).is_visible_in_tree() and (c.name == "easypart_slider_last" or c.name == "easypart_slider_count"):
			sl = c
	if sl == null:
		print("  no tweak slider for this clip")
		await hold(N - shots.size())
		return
	sl.value = a
	await idle(3)
	await hold(lead)
	var left := N - shots.size()
	for i in left:
		sl.value = lerpf(a, b, float(i + 1) / float(left))
		await idle(3)
		await shoot()


func clip(id: String) -> void:
	await fresh()
	match id:
		"draw":
			await hold(2)
			await press(ep().make_btns["draw"])
			await draw_floor(Vector3(-0.03, 0.0, -0.03), Vector3(0.03, 0.0, 0.03), 6)
			await make("pull")   # the drawn shape is a flat sketch the view does not paint once the mouse is up: the clip ends on the solid it becomes
			mid = Vector3(0.0, 0.02, 0.0)
			await hold(N - shots.size())
		"curve":
			await hold(2)
			await press(ep().make_btns["curve"])
			var pts := [Vector3(-0.04, 0, 0.0), Vector3(-0.025, 0, -0.03), Vector3(0.0, 0, -0.04), Vector3(0.03, 0, -0.02), Vector3(0.03, 0, 0.02), Vector3(0.0, 0, 0.04), Vector3(-0.03, 0, 0.025), Vector3(-0.04, 0, 0.0)]
			var p0 := scr(pts[0])
			await ev_move(p0, false)
			await ev_mouse(p0, true)
			for i in range(1, pts.size()):
				var pa := scr(pts[i - 1])
				var pb := scr(pts[i])
				for s in 3:
					await ev_move(pa.lerp(pb, (s + 1) / 3.0))
				await shoot()
			await ev_mouse(scr(pts[-1]), false)
			await idle(3)
			await make("pull")
			mid = Vector3(0.0, 0.02, 0.0)
			await hold(N - shots.size())
		"pull":
			await sample(false)
			await hold(1)
			await make("pull")
			mid = Vector3(0.0, 0.02, 0.0)
			await ramp(0.4, 2.6, 2)
		"spin", "blend":
			if id == "spin":   # a bowl is turned from a SIDE-ON drawing (the ViewCube's FRONT), a closed Curvy profile on the +X side of the middle line
				var cube: ViewCube = m.ui_cube
				var q := cube._quad(0)
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.pressed = true
				ev.position = (q[0] + q[1] + q[2] + q[3]) * 0.25
				cube._gui_input(ev)
				await idle(60)
				yaw0 = m.yaw
				cam_target = m.target
				cam_dist = m.dist
				await press(ep().make_btns["curve"])
				var prof := [[0.0, 0.0], [18.0, 0.5], [32.0, 6.0], [40.0, 20.0], [40.0, 40.0], [36.0, 56.0], [33.0, 56.0], [34.0, 40.0], [33.0, 20.0], [26.0, 8.0], [14.0, 4.0], [0.0, 4.0], [0.0, 0.0]]
				var pts := []
				for pp in prof:
					pts.append(scr(Vector3(pp[0] * 0.001, pp[1] * 0.001, 0.0)))
				await ev_move(pts[0], false)
				await ev_mouse(pts[0], true)
				for ii in range(1, pts.size()):
					for st in 3:
						await ev_move((pts[ii - 1] as Vector2).lerp(pts[ii], (st + 1) / 3.0))
				await ev_mouse(pts[-1], false)
				await idle(3)
				print("  spin drawing: ", ep().msg)
				mid = Vector3(0.02, 0.03, 0.0)
			else:
				await sample(false)
				await box(-0.015, 0.05, 0.015, 0.075)
				mid = Vector3(0.0, 0.01, 0.025)
			await hold(4)
			await make(id)
			await hold(N - shots.size())
		"colour":
			await sample()
			mid = Vector3(0.0, 0.02, 0.0)
			await hold(4)
			await press(ep().make_btns["colour"])
			var chips: Array = ep().colour_box.find_children("easypart_colour_*", "Button", true, false)
			var pick: Button = chips[1] if chips.size() > 1 else null
			if pick != null:
				await press(pick)
			await hold(N - shots.size())
		"stick":
			await sample()
			await box(0.04, -0.02, 0.08, 0.02)
			await make("pull")
			mid = Vector3(0.02, 0.015, 0.0)
			await hold(4)
			await press(ep().make_btns["stick"])
			await ev_move(Vector2(60, 400), false)
			var p1 := scr(Vector3(0.0, 0.02, 0.0))
			var p2 := scr(Vector3(0.06, 0.02, 0.0))
			await ev_move(p1, false)
			await ev_mouse(p1, true)
			await ev_mouse(p1, false)
			await idle(2)
			await shoot()
			await ev_move(p2, false)
			await ev_mouse(p2, true)
			await ev_mouse(p2, false)
			await idle(2)
			await shoot()
			var jb = ep().stick_btns.get("join", null)
			if jb != null and jb.is_visible_in_tree():
				await press(jb)
			await hold(N - shots.size())
		_:   # round, hole, mirror, split, repeat: the pulled box, then the press
			await sample()
			mid = Vector3(0.0, 0.02, 0.0)
			if id == "mirror":
				m.S.part = Part.make("Part")
				pu().sync()
				await idle(3)
				await box(-0.07, -0.03, -0.01, 0.03)
				await make("pull")
				mid = Vector3(0.0, 0.02, 0.0)
			await hold(3)
			await make(id)
			match id:   # the tweak slider the press opens, moved by the app's own control: the action visibly grows
				"round":
					await ramp(0.1, 1.0, 2)
				"hole":
					await ramp(0.6, 4.0, 2)
				"split":
					await ramp(-2.5, 2.5, 2)
				"repeat":
					await ramp(2.0, 6.0, 2)
				_:
					await hold(N - shots.size())
	while shots.size() > N:
		shots.pop_back()
	while shots.size() < N:
		await shoot()


func pack(id: String) -> Dictionary:
	var rows := int(ceil(float(N) / COLS))
	var sheet := Image.create(COLS * W, rows * H, false, Image.FORMAT_RGB8)
	for i in N:
		sheet.blit_rect(shots[i], Rect2i(0, 0, W, H), Vector2i((i % COLS) * W, (i / COLS) * H))
	var path := ProjectSettings.globalize_path(out_dir + id + ".png")
	sheet.save_png(path)
	var fa := FileAccess.open(path, FileAccess.READ)
	var kb := fa.get_length() / 1024.0
	fa.close()
	# the first and the middle frame differ: the share of changed pixels, printed
	var a: Image = shots[0]
	var b: Image = shots[N / 2]
	var ch := 0
	for y in H:
		for x in W:
			if a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)) == false:
				ch += 1
	print("clip %-7s %d frames %6.1f KB  first-vs-middle changed %.1f %%" % [id, N, kb, 100.0 * ch / float(W * H)])
	return {"sheet": id + ".png", "frames": N, "cols": COLS}


func _init() -> void:
	var only := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("only="):
			only = a.substr(5).split(",")
		if a.begins_with("out="):
			out_dir = a.substr(4).rstrip("/") + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var man := {"fps": FPS, "w": W, "h": H, "generated_by": "tools/make_easy_tips.gd", "clips": {}}
	var old := EasyTips.load_manifest(out_dir)
	if not old.is_empty():
		man["clips"] = old["clips"]
	for id in IDS:
		if only.is_empty() or id in only:
			await clip(id)
			man["clips"][id] = await pack(id)
	var fa := FileAccess.open(ProjectSettings.globalize_path(out_dir + "tips.json"), FileAccess.WRITE)
	fa.store_string(JSON.stringify(man, "\t"))
	fa.close()
	print("easy tips: %d clips, %.2f MB in %s" % [man["clips"].size(), EasyTips.dir_bytes(out_dir) / 1048576.0, out_dir])
	quit(0)
