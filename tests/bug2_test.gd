extends SceneTree
## godot --path . -s tests/bug2_test.gd     (Nick 11-01: opening the 3D building (Easy Part) hides the floor until Top / Side is pressed)
## Bars (real clicks from the start screen at 1280 x 720; pixels measured from the screenshot, grid share = pixels that change when the grid is hidden):
##   A first   on the first calm frame after the BUILDING card (and after re-entering from STAGE): the grid is visible, its corners are
##             in front of the lens, and the grid takes at least 15 pct of the frame
##   B views   Top and Side presses give the same camera as before the fix (yaw/pitch of VIEW_ANGLES, the grid still in view)
const SHOT := "C:/Temp/claude/bug2"
const DIRT := "user://bug2_test"
var fails := 0
var m: Node
var ss: StartScreen


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e, true)
		await process_frame
	await idle(4)


func img() -> Image:
	return root.get_texture().get_image()


## the share of the frame the floor grid covers: its four corners projected, clipped to the window (a corner behind the lens: 0)
func grid_share(nm: String, half := -1.0) -> float:
	await idle(2)
	img().save_png("%s/%s.png" % [SHOT, nm])
	var e: float = ep_floor_half() if half < 0.0 else half
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var hit := 0
	var tot := 0
	for y in range(0, int(vs.y), 4):
		for x in range(0, int(vs.x), 4):
			tot += 1
			var o: Vector3 = m.cam.project_ray_origin(Vector2(x, y))
			var d: Vector3 = m.cam.project_ray_normal(Vector2(x, y))
			if absf(d.y) < 1e-6:
				continue
			var tt := -o.y / d.y
			if tt <= 0.0:
				continue
			var q := o + d * tt
			if absf(q.x) <= e and absf(q.z) <= e:
				hit += 1
	return float(hit) / float(tot)


## half side (m) of the drawn floor: the 1 m tile plus the outer floor out to where its lines have faded
func ep_floor_half() -> float:
	return m.bld.part.ep.FLOOR_OUT


## the share of the frame's pixels that change when the floor is not drawn (its lines; the labels stay): what the eye sees of the floor
func floor_pixels() -> float:
	var fl: MeshInstance3D = m.bld.part.ep.floor_mi
	var a := img()
	fl.layers = 0
	await idle(3)
	var b := img()
	fl.layers = 1
	await idle(2)
	var n := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.02:
				n += 1
	return float(n) / float(((a.get_height() + 1) / 2) * ((a.get_width() + 1) / 2))


## the house builder's own floor grid (BuildUI.grid, 12 m each side): visible, and the share of the frame it covers
func house_floor(tag: String) -> void:
	var g: MeshInstance3D = m.bld.grid
	var s := await grid_share("house_" + tag, 12.0)
	var a := img()
	g.layers = 0
	await idle(3)
	var b := img()
	g.layers = 1
	await idle(2)
	var n := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.02:
				n += 1
	var px := float(n) / float(((a.get_height() + 1) / 2) * ((a.get_width() + 1) / 2))
	print("     house %s: grid visible %s, floor %.1f pct of the frame, lines %.1f pct of the pixels, easy %s, part on %s, %s" % [tag, g.is_visible_in_tree(), s * 100.0, px * 100.0, m.easy.on, m.bld.part.on, cam_s()])
	ok(g.is_visible_in_tree() and s >= 0.15 and px > 0.005, "H %s: house grid visible, floor %.1f pct of the frame (>= 15), lines %.2f pct of the pixels" % [tag, s * 100.0, px * 100.0])


func house_enter(easy_on: bool) -> void:
	m.easy.set_on(easy_on)
	ss.show_screen()
	await idle(4)
	await click(ss._easy_btn["building"] if easy_on else ss._expert_btn["building"])
	if m.bld.part.on:
		m.bld.part.set_on(false)   # the house builder, as bug6 reaches it
	await idle(90)


## how many of the grid's four corners project in front of the lens and inside the window
func corners_in() -> int:
	var e := 0.5
	var vs: Vector2 = m.get_viewport().get_visible_rect().size
	var n := 0
	for c in [Vector3(-e, 0, -e), Vector3(e, 0, -e), Vector3(e, 0, e), Vector3(-e, 0, e)]:
		if m.cam.is_position_behind(c):
			continue
		var p: Vector2 = m.cam.unproject_position(c)
		if p.x >= 0 and p.y >= 0 and p.x <= vs.x and p.y <= vs.y:
			n += 1
	return n


func cam_s() -> String:
	return "target %s dist %.3f yaw %.1f pitch %.1f" % [m.target, float(m.dist), float(m.yaw), float(m.pitch)]


func calm() -> void:
	await idle(90)


func measure(tag: String, frames := 90) -> float:
	await idle(frames)
	var ep0 = m.bld.part.ep
	var fl: MeshInstance3D = ep0.floor_mi
	var share := await grid_share(tag)
	var px: float = await floor_pixels()
	print("     %s: floor lines %.1f pct of the pixels; ep active %s, floor visible %s, corners in window %d, share %.1f pct, %s, page %s" % [tag, px * 100.0, ep0.active(), fl != null and fl.is_visible_in_tree(), corners_in(), share * 100.0, cam_s(), m.cur_page])
	return share


## one entry path: `how` starts the Easy Part; the grid is measured on the first calm frame
func entry(tag: String) -> void:
	var s20 := await measure(tag + "_t20", 20)
	var s := await measure(tag, 70)
	var fl: MeshInstance3D = m.bld.part.ep.floor_mi
	ok(fl != null and fl.is_visible_in_tree() and corners_in() >= 1 and s >= 0.15, "A %s: grid visible, share %.1f pct (%.1f at 20 frames) >= 15" % [tag, s * 100.0, s20 * 100.0])


func card_easy() -> void:
	m.easy.set_on(true)
	ss.show_screen()
	await idle(4)
	await click(ss._easy_btn["building"])


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	DirAccess.make_dir_recursive_absolute(SHOT)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	ss = m.start_screen
	ss.dirs_override = [DIRT]
	await idle(6)

	# 1 fresh: the card's Easy chip
	await card_easy()
	await entry("fresh")
	# 2 Top and Side keep working (camera numbers of the views)
	var ep = m.bld.part.ep
	var tgt0: Vector3 = m.target
	for k in ["top", "side"]:
		await click(root.find_child("easypart_view_" + k, true, false))
		await idle(60)
		var s2 := await grid_share("after_" + k)
		var ang: Array = ep.VIEW_ANGLES[k]
		ok(m.target.is_equal_approx(tgt0) and absf(float(m.dist) - 0.9) < 0.01, "B %s: look-at point untouched, distance 0.9 (target %s, dist %.3f)" % [k, m.target, float(m.dist)])
		print("     after %s: share %.1f pct, %s" % [k, s2 * 100.0, cam_s()])
		ok((s2 > 0.02 or k == "side") and absf(float(m.yaw) - float(ang[0])) < 0.5 and absf(float(m.pitch) - float(ang[1])) < 0.5, "B %s: grid in view (%.1f pct), yaw/pitch as VIEW_ANGLES" % [k, s2 * 100.0])
	# 3 again from the start screen while Easy Part is open (after Side)
	await card_easy()
	await entry("again_after_side")
	# 4 from STAGE
	m.easy.set_on(false)
	m._new_scene()
	m._page_set("STAGE")
	await idle(10)
	await card_easy()
	await entry("from_stage")
	# 5 the 3/4 button keeps its angles
	await click(root.find_child("easypart_view_3q", true, false))
	await idle(60)
	ok(absf(float(m.yaw) - 30.0) < 0.5 and absf(float(m.pitch) + 22.0) < 0.5, "B 3/4: yaw %.1f pitch %.1f (30 / -22)" % [float(m.yaw), float(m.pitch)])
	# H: the HOUSE builder (Easy: Room / Door / Window ...; Expert: Room / Wall / Pull ...), fresh and after an ANIMATION project
	for entry in ["fresh", "after_anim"]:
		for easy_on in [true, false]:
			if entry == "after_anim":
				m.easy.set_on(true)
				ss.show_screen()
				await idle(4)
				await click(ss._cards["animation"])
				await idle(10)
			elif easy_on:
				m._new_scene()
				m._page_set("POSE")
				await idle(6)
			await house_enter(easy_on)
			await house_floor("%s_%s" % [entry, "easy" if easy_on else "expert"])
	print("bug2: %d fail" % fails)
	quit()
