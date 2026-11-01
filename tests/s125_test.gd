extends SceneTree
## S125 COLLIDE LIVE (Friday plan 125, "the door hits the wall -> red flash"): on Easy Part, two pieces made apart; Swing it turns the newest
## piece on its back top edge and the check runs every step (CollideLive: boxes, then triangles). At the first touch the turn stops at the last
## free angle, the two pieces flash red 0.3 s, and the words say what hit. Real clicks at 1280 x 720. Every number is measured from the built
## result (kernel bboxes, mesh materials, pixels, the undo list); the contact angle is worked out from the geometry (asin(gap / height)).
##   1 Swing it stops at the analytic contact angle (+-1 deg)   2 the words name both pieces and the angle
##   3 red in the contact frame (pixels)   4 red gone 0.5 s later (pixels, surfaces)   5 no undo step from the check
##   6 per-step check median < 4 ms   7 a lid swung 0 to 120 degrees stops at acos(-w/R) - atan(t/D) (+-1 deg)
##   8 clearance: 0 contacts over 0..120   9 two 2k-triangle parts: per-frame check median < 4 ms (printed)
const SHOT := "C:/Temp/claude/s125"
const DIRT := "user://s125_test"

var fails := 0
var m: Node
var CL = load("res://scripts/build/collide_live.gd")


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


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


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


func shot(nm: String) -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func hinges() -> Array:
	var out: Array = []
	for f in m.S.part.get("features", []):
		if String(f.get("t", "")) == "hinge":
			out.append(f)
	return out


func red_surfaces() -> int:
	var pm: MeshInstance3D = pu().part_mesh
	var n := 0
	if pm.mesh == null:
		return 0
	for s in pm.mesh.get_surface_count():
		var mt := pm.get_surface_override_material(s) as StandardMaterial3D
		if mt != null and mt.albedo_color.is_equal_approx(Tok.c("mk_red")):
			n += 1
	return n


func red_pixels() -> int:
	var im := root.get_texture().get_image()
	var rc: Color = Tok.c("mk_red")
	var n := 0
	for y in range(0, im.get_height(), 2):
		for x in range(0, im.get_width(), 2):
			var c := im.get_pixel(x, y)
			if absf(c.r - rc.r) < 0.04 and absf(c.g - rc.g) < 0.04 and absf(c.b - rc.b) < 0.04:
				n += 1
	return n


func median(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2]) if b.size() > 0 else -1.0


## a box as 12 triangles (metres)
func box(lo: Vector3, hi: Vector3) -> PackedVector3Array:
	var c: Array = []
	for i in 8:
		c.append(Vector3(hi.x if i & 1 else lo.x, hi.y if i & 2 else lo.y, hi.z if i & 4 else lo.z))
	var q := [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
	var out := PackedVector3Array()
	for f in q:
		out.append_array([c[f[0]], c[f[1]], c[f[2]], c[f[0]], c[f[2]], c[f[3]]])
	return out


## a UV sphere of 2 * seg * (seg - 1) triangles
func sphere(ctr: Vector3, r: float, seg: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	var pts: Array = []
	for i in range(seg + 1):
		var row: Array = []
		var la := PI * float(i) / float(seg)
		for j in range(seg):
			var lo := TAU * float(j) / float(seg)
			row.append(ctr + r * Vector3(sin(la) * cos(lo), cos(la), sin(la) * sin(lo)))
		pts.append(row)
	for i in range(seg):
		for j in range(seg):
			var j2 := (j + 1) % seg
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i][j2]
			var c: Vector3 = pts[i + 1][j]
			var d: Vector3 = pts[i + 1][j2]
			if i > 0:
				out.append_array([a, c, b])
			if i < seg - 1:
				out.append_array([b, c, d])
	return out


func _init() -> void:
	# ---- 7, 8, 9: the module on plain triangles (no UI): a lid and a wall behind it, and two 2k-triangle parts
	var t_ := 0.005
	var D := 0.06
	var w := 0.008
	var lid := box(Vector3(-0.03, -t_, 0.0), Vector3(0.03, 0.0, D))
	var wall := box(Vector3(-0.05, -0.2, -0.05), Vector3(0.05, 0.05, -w))
	var P: Dictionary = CL.prep_soups(lid, [wall], Vector3.ZERO, Vector3.RIGHT)
	var R := sqrt(D * D + t_ * t_)
	var want7 := rad_to_deg(acos(-w / R) - atan(t_ / D))
	var r7: Dictionary = CL.first_contact(P, 0.0, 120.0, 1.5)
	ok(bool(r7.get("hit", false)) and absf(float(r7["free"]) - want7) <= 1.0, "7 a lid swung 0 to 120 degrees stops at %.2f deg (free), first hit %.2f, analytic %.2f deg (+-1)" % [float(r7.get("free", -1)), float(r7.get("deg", -1)), want7])
	var wall2 := box(Vector3(-0.05, -0.2, -0.05), Vector3(0.05, 0.05, -0.07))   # clearance: 70 mm behind, the lid reaches 60.2 mm
	var P2: Dictionary = CL.prep_soups(lid, [wall2], Vector3.ZERO, Vector3.RIGHT)
	var contacts := 0
	var d := 0.0
	while d <= 120.0:
		if CL.hit_at(P2, d) >= 0:
			contacts += 1
		d += 0.5
	ok(contacts == 0, "8 clearance: %d contacts over 0..120 degrees (241 frames)" % contacts)
	var A := sphere(Vector3(0.0, 0.0, 0.03), 0.02, 33)   # 2 * 33 * 32 - 2 * 33 = 2046 triangles
	var B := sphere(Vector3(0.0, -0.025, 0.0), 0.02, 33)
	var P3: Dictionary = CL.prep_soups(A, [B], Vector3.ZERO, Vector3.RIGHT)
	CL.ms = PackedFloat64Array()
	var hits := 0
	var a := 0.0
	while a <= 120.0:
		if CL.hit_at(P3, a) >= 0:
			hits += 1
		a += 0.25
	var ms3: Array = Array(CL.ms)
	ms3.sort()
	var med3 := median(ms3)
	print("timing: %d triangles x %d triangles, %d checks, %d hit frames, median %.3f ms, p95 %.3f ms, max %.3f ms" % [A.size() / 3, B.size() / 3, ms3.size(), hits, med3, float(ms3[int(ms3.size() * 0.95)]), float(ms3[-1])])
	ok(med3 < 4.0 and A.size() / 3 >= 2000 and hits > 0, "9 2k-triangle parts (%d x %d tris), per-frame check median %.3f ms (< 4), %d of %d frames touch" % [A.size() / 3, B.size() / 3, med3, hits, ms3.size()])

	# ---- the app
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)

	var draw = pu().ep.make_btns["draw"]
	await click_ctl(draw)
	await drag_screen(scr(Vector3(-0.03, 0.0, -0.03)), scr(Vector3(0.03, 0.0, 0.03)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(10)
	await click_ctl(draw)
	await drag_screen(scr(Vector3(-0.03, 0.0, 0.04)), scr(Vector3(0.03, 0.0, 0.10)))
	await click_ctl(pu().ep.make_btns["pull"])
	await idle(10)
	var sw = m.find_child("easypart_swing_it", true, false)
	var faces: Array = Part.body_faces(m.S.part, -1)
	if faces.size() != 2 or sw == null:
		ok(false, "S0 two pieces: %d bodies, Swing it %s" % [faces.size(), str(sw)])
		print("s125: %d fail" % fails)
		quit(1)
		return
	# the geometry in mm, from the kernel's own boxes: piece 0 is the obstacle, piece 1 swings
	var b0 := PackedVector3Array(faces[0])
	var b1 := PackedVector3Array(faces[1])
	var lo0 := Vector3(INF, INF, INF)
	var hi0 := -lo0
	var lo1 := lo0
	var hi1 := -lo0
	for v in b0:
		lo0 = lo0.min(v)
		hi0 = hi0.max(v)
	for v in b1:
		lo1 = lo1.min(v)
		hi1 = hi1.max(v)
	var H := hi1.y - lo1.y
	var gap := lo1.z - hi0.z
	var want := rad_to_deg(asin(gap / H))
	print("geometry: swinging piece height %.2f mm, back edge z %.2f, obstacle front z %.2f, gap %.2f mm, analytic contact %.2f deg" % [H, lo1.z, hi0.z, gap, want])

	var undo0: int = m.undo.size()
	await click_ctl(sw)
	var undo1: int = m.undo.size()
	var h := hinges()
	ok(h.size() == 1 and undo1 == undo0 + 1, "S1 one real click on Swing it: %d hinge, undo list %d -> %d" % [h.size(), undo0, undo1])
	var red_t0 := -1
	var red_px := 0
	var red_n := 0
	var red_ms := -1
	var after_px := -1
	var t0 := Time.get_ticks_msec()
	var undo_max: int = undo1
	while Time.get_ticks_msec() - t0 < 6000:
		await process_frame
		undo_max = maxi(undo_max, m.undo.size())
		if red_t0 < 0 and red_surfaces() > 0:
			red_t0 = Time.get_ticks_msec()
			red_n = red_surfaces()
			await process_frame
			red_px = red_pixels()
			await shot("contact")
		elif red_t0 >= 0 and red_ms < 0 and red_surfaces() == 0:
			red_ms = Time.get_ticks_msec() - red_t0
		if red_t0 >= 0 and Time.get_ticks_msec() - red_t0 > 500:
			after_px = red_pixels()
			break
	await shot("after")
	var log: Dictionary = pu().ep.swing_log
	var free := float(log.get("free", -1.0))
	ok(bool(log.get("hit", false)) and absf(free - want) <= 1.0, "1 Swing it stops at %.2f deg (first hit %.2f), analytic contact %.2f deg (+-1)" % [free, float(log.get("deg", -1.0)), want])
	var pose_deg := float((pu().pose as Dictionary).get("deg", -99.0))
	ok(absf(pose_deg - free) < 0.01, "1b the view holds the last free pose: %.2f deg" % pose_deg)
	var said := String(pu().ep.msg)
	ok(said.find("piece 2") >= 0 and said.find("hits piece 1") >= 0 and said.find("%d degrees" % roundi(want)) >= 0, "2 the words: '%s'" % said)
	ok(red_px >= 300 and red_n == 2, "3 red in the contact frame: %d red pixels (every 2nd px), %d surfaces were red" % [red_px, red_n])
	ok(red_ms >= 250 and red_ms <= 600, "3b the flash lasts %d ms (0.3 s)" % red_ms)
	ok(after_px >= 0 and after_px < 20 and red_surfaces() == 0, "4 red gone 0.5 s later: %d red pixels, %d red surfaces" % [after_px, red_surfaces()])
	ok(undo_max == undo1, "5 no undo step from the check: undo list stayed %d during the playback (max %d)" % [undo1, undo_max])
	var cm: Array = log.get("check_ms", [])
	var medc := median(cm)
	print("timing: Easy playback, %d steps, per-step check median %.3f ms, max %.3f ms" % [cm.size(), medc, float(cm.max()) if cm.size() > 0 else -1.0])
	ok(cm.size() >= 2 and medc < 4.0, "6 per-step check median %.3f ms (< 4)" % medc)

	print("s125: %d fail" % fails)
	quit(1 if fails > 0 else 0)
