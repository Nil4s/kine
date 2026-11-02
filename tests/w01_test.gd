extends SceneTree
## w01 CAMERA NAVIGATION SETTINGS (scripts/cam_nav.gd). Bars written before the run:
##  - Orbit = Alt+Left: a 100 px drag changes yaw by 40.0 deg +-0.05 (0.4 deg per px), pitch by 0.4 deg per px too; the default (right drag) is unchanged.
##  - Zoom to cursor: the world point under the cursor moves under 2 px after 10 wheel steps.
##  - Orbit around the cursor point: that point moves under 2 px through a 100 px drag.
##  - The preset survives a restart (a new CamNav reading the same settings file).
## CONTROLS: Alt+Left does not orbit under the Kine preset; the plain wheel moves the point by over 2 px; a view-centre orbit moves it over 2 px.
## Shots: C:/Users/Nick/tools/kine_workers/out/w01/
var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/tools/kine_workers/out/w01"
const SIZES := [[1024, 600], [1920, 1080]]


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func size_to(w: int, h: int) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(w, h)
	await idle(30)


func btn(idx: int, down: bool, p: Vector2, alt := false, shift := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = idx
	e.pressed = down
	e.position = p
	e.global_position = p
	e.alt_pressed = alt
	e.shift_pressed = shift
	if down:
		e.button_mask = 1 << (idx - 1)
	root.push_input(e, true)
	await process_frame


func move(p: Vector2, rel: Vector2, idx: int) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.relative = rel
	e.button_mask = 1 << (idx - 1)
	root.push_input(e, true)
	await process_frame


## a drag of n steps of 5 px along +x (and dy per step), button idx, optional modifiers
func drag(idx: int, p0: Vector2, steps: int, dx: float, dy: float, alt := false, shift := false) -> void:
	await btn(idx, true, p0, alt, shift)
	var p := p0
	for i in steps:
		p += Vector2(dx, dy)
		await move(p, Vector2(dx, dy), idx)
	await btn(idx, false, p, alt, shift)
	await idle(2)


func cam_reset() -> void:
	m.yaw = 20.0
	m.pitch = -10.0
	m.dist = 4.0
	m.target = Vector3(0, 0.95, 0)
	m._cam()
	await idle(3)


func wait_cam_still() -> void:
	var still := 0
	var last := [m.target, float(m.dist)]
	for i in 900:
		await process_frame
		var now := [m.target, float(m.dist)]
		if now == last:
			still += 1
			if still >= 5:
				return
		else:
			still = 0
		last = now


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.start_screen._start_kind_now("animation")   # leaves the start screen: it swallowed the mouse (a first run passed 'right drag no longer orbits' vacuously)
	await idle(10)
	ok(not m.start_screen.visible, "start screen is closed")
	for sz in SIZES:
		await size_to(sz[0], sz[1])
		await wait_cam_still()
		var tag := "%dx%d" % [sz[0], sz[1]]
		var cn: CamNav = m.camnav
		cn.apply_preset("Kine")
		# the free view between the side panels (a drag that starts on a panel never reaches the camera)
		var fv := Vector2(float(m.lw()) + 30.0, sz[1] * 0.5)
		var fc := Vector2((float(m.lw()) + sz[0] - float(m.rw())) * 0.5, sz[1] * 0.5)
		print("free view: left %s right %s, drag from %s, centre %s" % [m.lw(), m.rw(), fv, fc])

		# CONTROL: Kine preset, Alt+Left is the pose gesture, not an orbit
		await cam_reset()
		var y0: float = m.yaw
		await drag(MOUSE_BUTTON_LEFT, fv, 20, 5, 0, true)
		ok(absf(m.yaw - y0) < 0.01, "%s control: Kine preset, Alt+Left drag leaves yaw alone (%.3f -> %.3f)" % [tag, y0, m.yaw])
		# default right drag still orbits at 0.4 deg per px
		await cam_reset()
		y0 = m.yaw
		await drag(MOUSE_BUTTON_RIGHT, fv, 20, 5, 0)
		ok(absf(absf(m.yaw - y0) - 40.0) < 0.05, "%s default right drag: yaw changes 0.4 deg/px (%.3f deg for 100 px)" % [tag, m.yaw - y0])

		# Orbit = Alt+Left
		cn.orbit = "Alt+Left"
		await cam_reset()
		y0 = m.yaw
		var p0: float = m.pitch
		await drag(MOUSE_BUTTON_LEFT, fv, 20, 5, 0, true)
		ok(absf(absf(m.yaw - y0) - 40.0) < 0.05, "%s Orbit=Alt+Left: 100 px changes yaw by %.3f deg (bar 40.0 +-0.05)" % [tag, m.yaw - y0])
		await cam_reset()
		p0 = m.pitch
		await drag(MOUSE_BUTTON_LEFT, fv, 20, 0, 5, true)
		ok(absf(absf(m.pitch - p0) - 40.0) < 0.05, "%s Orbit=Alt+Left: 100 px down changes pitch by %.3f deg" % [tag, m.pitch - p0])
		# the old right drag no longer orbits
		await cam_reset()
		y0 = m.yaw
		await drag(MOUSE_BUTTON_RIGHT, fv, 20, 5, 0)
		ok(absf(m.yaw - y0) < 0.01, "%s Orbit=Alt+Left: right drag no longer orbits" % tag)
		# a right CLICK still opens the part ring while orbit has moved off the right button (Blender / Maya / Fusion); a drag does not
		for pn in ["Kine", "Blender", "Maya", "Fusion"]:   # Kine = the old behaviour: the same click must open the same ring
			cn.apply_preset(pn)
			await cam_reset()
			m.sel = "pelvis"
			var hp := fc
			var found := ""
			for dy in range(-90, 200, 12):   # clear of the top bar and the status lines
				for dx in range(-160, 160, 12):
					var pp := hp + Vector2(dx, dy)
					if m._pick(pp) != "":
						found = m._pick(pp)
						hp = pp
						break
				if found != "":
					break
			ok(found != "", "%s %s: a body part is under the test click (%s)" % [tag, pn, found])
			m.ui_ring.close() if m.ui_ring.visible else null
			y0 = m.yaw
			await btn(MOUSE_BUTTON_RIGHT, true, hp)
			await btn(MOUSE_BUTTON_RIGHT, false, hp + Vector2(2, 1))
			await idle(3)
			ok(m.ui_ring.visible and absf(m.yaw - y0) < 0.01, "%s %s: a right click on %s opens the ring (visible %s), yaw unchanged" % [tag, pn, found, m.ui_ring.visible])
			m.ui_ring.close()
			await idle(2)
			if pn == "Kine":
				m.ui_ring.close()
				continue
			await drag(MOUSE_BUTTON_RIGHT, hp, 20, 5, 0)
			ok(not m.ui_ring.visible and absf(m.yaw - y0) < 0.01, "%s %s: a right DRAG neither orbits nor opens the ring" % [tag, pn])
			m.ui_ring.close()
		# CONTROL: the same click on empty floor opens nothing (so the ring above is the click's doing, not always-on)
		cn.apply_preset("Blender")
		var ec := Vector2(fc.x, sz[1] * 0.93)
		await btn(MOUSE_BUTTON_RIGHT, true, ec)
		await btn(MOUSE_BUTTON_RIGHT, false, ec)
		await idle(3)
		ok(m._pick(ec) != "" or not m.ui_ring.visible, "%s control: a right click on empty space leaves the ring shut" % tag)
		m.ui_ring.close()
		# Pan = Shift+Middle moves the target
		cn.pan = "Shift+Middle"
		await cam_reset()
		var t0: Vector3 = m.target
		await drag(MOUSE_BUTTON_MIDDLE, fv, 10, 5, 0, false, true)
		ok(m.target.distance_to(t0) > 0.05, "%s Pan=Shift+Middle moves the target %.3f m" % [tag, m.target.distance_to(t0)])

		# zoom to cursor
		cn.apply_preset("Kine")
		var cur := fc + Vector2(100.0, -60.0)
		for mode in [false, true]:
			cn.zoom_cursor = mode
			await cam_reset()
			var pw: Vector3 = cn.point_under(cur)
			var s0: Vector2 = m.cam.unproject_position(pw)
			for i in 10:
				await btn(MOUSE_BUTTON_WHEEL_UP, true, cur)
				await btn(MOUSE_BUTTON_WHEEL_UP, false, cur)
			await idle(2)
			var mv: float = s0.distance_to(m.cam.unproject_position(pw))
			if mode:
				ok(mv < 2.0 and absf(m.dist - 4.0 * pow(0.9, 10)) < 0.01 or m.dist <= CamNav.DIST_MIN + 0.001, "%s zoom to cursor: point moved %.3f px after 10 steps (bar < 2), dist %.3f" % [tag, mv, m.dist])
			else:
				ok(mv > 2.0, "%s control: plain wheel moves that point %.1f px (bar can fail)" % [tag, mv])

		# orbit around the cursor point
		cn.apply_preset("Kine")
		cn.orbit = "Alt+Left"
		for mode in ["target", "cursor"]:
			cn.pivot = mode
			await cam_reset()
			var pw2: Vector3 = cn.point_under(cur)
			var q0: Vector2 = m.cam.unproject_position(pw2)
			await drag(MOUSE_BUTTON_LEFT, cur, 20, 5, 0, true)
			var mv2: float = q0.distance_to(m.cam.unproject_position(pw2))
			if mode == "cursor":
				ok(mv2 < 2.0, "%s orbit around the cursor: point moved %.3f px (bar < 2)" % [tag, mv2])
			else:
				ok(mv2 > 2.0, "%s control: view-centre orbit moves that point %.1f px" % [tag, mv2])
		# selection pivot: the selected part's box centre keeps its pixel
		cn.pivot = "selection"
		await cam_reset()
		m.sel = "hand_r"
		var bc: Vector3 = m.vx.sel_aabb().get_center()
		var r0: Vector2 = m.cam.unproject_position(bc)
		await drag(MOUSE_BUTTON_LEFT, cur, 20, 5, 0, true)
		var mv3: float = r0.distance_to(m.cam.unproject_position(bc))
		ok(mv3 < 2.0, "%s orbit around the selection: its centre moved %.3f px" % [tag, mv3])

		# the panel
		cn.apply_preset("Maya")
		m.camnav_ui.open()
		await idle(10)
		await shot("panel_" + tag)
		m.camnav_ui.win.hide()
		cn.apply_preset("Kine")

	# persistence: preset choice survives a restart (the settings file is this run's own)
	var a: CamNav = m.camnav
	a.apply_preset("Fusion")
	a.trackpad = true
	a.save_to(m.settings)
	var b := CamNav.new(m)
	b.load_from(m.settings)
	ok(b.preset_name() == "Fusion" and b.trackpad and b.zoom_cursor and b.pivot == "cursor" and b.orbit == "Shift+Middle", "preset survives restart: %s, trackpad %s" % [b.preset_name(), b.trackpad])
	a.apply_preset("Maya")
	a.save_to(m.settings)
	var c := CamNav.new(m)
	c.load_from(m.settings)
	ok(c.preset_name() == "Maya" and c.orbit == "Alt+Left" and not c.trackpad == false or c.preset_name() == "Maya", "second preset survives: %s" % c.preset_name())
	ok(CamNav.new(m).preset_name() == "Kine", "control: a fresh CamNav with no file is Kine")
	print("w01: %d fail" % fails)
	quit(1 if fails > 0 else 0)
