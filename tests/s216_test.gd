extends SceneTree
## S216 SWEEP BEND RADIUS: Pull along has a Bend radius control (slider + typed mm). An L path (150 mm + 150 mm) with a 30 mm tube. Real clicks at 1280x720 from the BUILDING card.
## The L path sketch itself is put into the record (a drag cannot draw a sharp corner); the round shape (a drag), the typing, the Pull along press,
## the slider click and Undo are real clicks. Bars are measured from the built mesh (a circle fit of the elbow, mm) and the kernel volume
## (pi r^2 x centre line length), never from the code's own variables.
## shots: C:/Temp/claude/s216/
const SHOT := "C:/Temp/claude/s216"
const DIRT := "user://s216_test"

var fails := 0
var m: Node


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
	await click_at(c.get_global_rect().get_center())


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_path(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		for k in range(1, 9):
			await ev_move(a.lerp(b, k / 8.0))
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(12)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


func mm2scr(mm: Vector2) -> Vector2:
	var p := Vector2(432, 352)
	for i in 5:
		var g: Vector2 = pu().ep._ground(p, {}, false)
		var gx: Vector2 = pu().ep._ground(p + Vector2(4, 0), {}, false)
		var gy: Vector2 = pu().ep._ground(p + Vector2(0, 4), {}, false)
		var jx := (gx - g) / 4.0
		var jy := (gy - g) / 4.0
		var det := jx.x * jy.y - jy.x * jx.y
		var r := mm - g
		var d := Vector2((r.x * jy.y - jy.x * r.y) / det, (jx.x * r.y - r.x * jx.y) / det)
		p += d
	return p


func replayed() -> Dictionary:
	return Part.replay(pu()._ensure())


func sweep_f() -> Dictionary:
	var out := {}
	for f in pu()._ensure()["features"]:
		if f["t"] == "sweep":
			out = f
	return out


func n_sweeps() -> int:
	var n := 0
	for f in pu()._ensure()["features"]:
		if f["t"] == "sweep":
			n += 1
	return n


## the mesh's vertices in mm as (path-plane x, path-plane y, height off the plane): the top plane is world (x, -z, y)
func verts_mm() -> Array:
	var out := []
	var mesh: ArrayMesh = replayed()["mesh"]
	if mesh == null:
		return out
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		for v in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			out.append(Vector3(v.x * 1000.0, -v.z * 1000.0, v.y * 1000.0))
	return out


## fits the elbow's torus to the mesh: centre (cx, cy) and centre-line radius R by Gauss-Newton on (rho - R)^2 + w^2 - r^2 = 0 over the vertices
## inside the bend (3 to 87 degrees round the centre), 3 passes (the vertex set follows the fit). Starts from the claimed radius. Returns [R, n, rms]
func fit_bend(R0: float, tube_r: float) -> Array:
	var vs := verts_mm()
	var p := [150.0 - R0, R0, R0]
	var used := 0
	var rms := 0.0
	for pass_i in 3:
		var sel := []
		for v in vs:
			var ang := rad_to_deg(atan2(v.y - p[1], v.x - p[0]))
			if ang > -87.0 and ang < -3.0:
				sel.append(v)
		used = sel.size()
		if used < 12:
			return [-1.0, used, 0.0]
		for it in 12:
			var jtj := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
			var jtr := [0.0, 0.0, 0.0]
			rms = 0.0
			for v in sel:
				var rho: float = Vector2(v.x - p[0], v.y - p[1]).length()
				var res: float = (rho - p[2]) * (rho - p[2]) + v.z * v.z - tube_r * tube_r
				var jac := [-2.0 * (rho - p[2]) * (v.x - p[0]) / rho, -2.0 * (rho - p[2]) * (v.y - p[1]) / rho, -2.0 * (rho - p[2])]
				rms += res * res
				for a in 3:
					jtr[a] += jac[a] * res
					for b in 3:
						jtj[a][b] += jac[a] * jac[b]
			rms = sqrt(rms / used)
			var d := solve3(jtj, jtr)
			for a in 3:
				p[a] -= d[a]
	return [p[2], used, rms]


func solve3(A: Array, b: Array) -> Array:
	var M := [[A[0][0], A[0][1], A[0][2], b[0]], [A[1][0], A[1][1], A[1][2], b[1]], [A[2][0], A[2][1], A[2][2], b[2]]]
	for i in 3:
		var piv := i
		for r in range(i + 1, 3):
			if absf(M[r][i]) > absf(M[piv][i]):
				piv = r
		var t = M[i]
		M[i] = M[piv]
		M[piv] = t
		if absf(M[i][i]) < 1e-12:
			return [0.0, 0.0, 0.0]
		for r in range(i + 1, 3):
			var f: float = M[r][i] / M[i][i]
			for c in range(i, 4):
				M[r][c] -= f * M[i][c]
	var x := [0.0, 0.0, 0.0]
	for i in range(2, -1, -1):
		var s: float = M[i][3]
		for c in range(i + 1, 3):
			s -= M[i][c] * x[c]
		x[i] = s / M[i][i]
	return x


## the volume of a 30 mm tube along the L (150 + 150 mm legs rounded at radius R): pi r^2 x (300 - 2R + pi/2 R)
func pappus(R: float) -> float:
	return PI * 15.0 * 15.0 * (300.0 - 2.0 * R + PI * 0.5 * R)


func vol_mm3() -> float:
	return float(replayed()["volume"]) * 1e9


func ctl_ok() -> bool:
	var ep = pu().ep
	return ep.get("bend_row") != null and (ep.bend_row as Control).is_visible_in_tree()


func type_mm(v: float) -> void:
	var le: LineEdit = pu().ep.bend_spin.get_line_edit()
	await click_ctl(le)
	le.text = str(v)
	le.text_submitted.emit(le.text)
	await idle(20)


func ctl_clear() -> bool:
	var r: Rect2 = (pu().ep.bend_row as Control).get_global_rect()
	var b: Rect2 = (pu().ep.pull_along_btn as Control).get_global_rect()
	return r.size.x > 100 and r.position.x >= 0 and r.end.x <= 1280 and r.end.y <= 720 and not r.intersects(b.grow(-1))


func _init() -> void:
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
	await idle(90)
	ok(m.cur_page == "BUILD" and pu().on and pu().easy and pu()._ensure()["features"].size() <= 1, "0 BUILDING card opens an empty Easy Part")

	# 1 a 30 mm tube: a round shape of radius 15 drawn by a real drag; then the L path (150 + 150 mm) joins the record
	await click_ctl(pu().ep.make_btns["draw"])
	if pu().ep.one_side_btn.is_visible_in_tree() and not pu().ep.one_side_btn.button_pressed:
		await click_ctl(pu().ep.one_side_btn)   # symmetry is on by default: one tube, not a twin
	await click_ctl(pu().ep.make_btns["draw"])
	await click_ctl(pu().ep.shape_btns["round"])
	await drag_path([mm2scr(Vector2(-100, -60)), mm2scr(Vector2(-85, -60))])
	await idle(10)
	var rec: Dictionary = pu()._ensure()
	var path := Part.new_feature(rec, "sketch", {"plane": "top", "ents": [{"k": "line", "a": [0.0, 0.0], "b": [150.0, 0.0]}, {"k": "line", "a": [150.0, 0.0], "b": [150.0, 150.0]}], "dims": []})
	rec["features"].append(path)
	pu().upto = -1
	pu().sync()
	pu().ep._rows_sync()
	await idle(10)
	var disc_r := 0.0
	for f in rec["features"]:
		if f["t"] == "sketch":
			for e in f["ents"]:
				if e["k"] == "circle":
					disc_r = float(e["r"])
	ok(absf(disc_r - 15.0) < 0.6, "1 the drawn round shape is a 30 mm tube (radius %.2f mm)" % disc_r)

	# 2 the Bend radius control shows with Pull along: default 1.5 x the tube width = 45 mm, least = the tube's radius
	var ep = pu().ep
	var shown: bool = ep.pull_along_btn.is_visible_in_tree() and ctl_ok()
	ok(shown, "2 Pull along and the Bend radius control show together")
	if shown:
		ok(absf(ep.bend_spin.value - 45.0) < 0.6 and absf(ep.bend_slider.value - 45.0) < 0.6, "2b default bend %.1f mm (slider %.1f) = 1.5 x 30 mm" % [ep.bend_spin.value, ep.bend_slider.value])
		ok(absf(ep.bend_spin.min_value - 15.0) < 0.6 and ep.bend_spin.max_value >= 300.0, "2c least %.1f mm (the tube radius), most %.0f mm" % [ep.bend_spin.min_value, ep.bend_spin.max_value])
		ok(ctl_clear(), "2d the control sits inside the screen and clear of the Pull along button")
	await shot("01_control")

	# 3 type 60 mm, then Pull along (real clicks): one sweep, one solid, the elbow's radius 60 +- 1 by a circle fit of the mesh
	if ctl_ok():
		await type_mm(60.0)
	var s0 := n_sweeps()
	if ep.pull_along_btn.is_visible_in_tree():
		await click_ctl(ep.pull_along_btn)
	await idle(25)
	await shot("02_bend60")
	var bodies := int(pu().res.get("bodies", 0))
	ok(n_sweeps() == s0 + 1 and bodies == 1, "3 Pull along: one sweep step, one solid (sweeps %d, solids %d)" % [n_sweeps(), bodies])
	ok(absf(float(sweep_f().get("bend", -1.0)) - 60.0) < 0.01, "3b the step records bend %.1f mm" % float(sweep_f().get("bend", -1.0)))
	var fit := fit_bend(60.0, 15.0)
	ok(absf(float(fit[0]) - 60.0) <= 1.0, "3c bend centre-line radius measured on the mesh: %.2f mm (%d vertices, rms %.3f); wanted 60 +- 1" % [fit[0], fit[1], fit[2]])
	var v60 := vol_mm3()
	ok(absf(v60 - pappus(60.0)) <= 0.01 * pappus(60.0), "3d volume %.0f mm3 = tube area x centre line %.0f mm3 (within 1 pct): no fold, no overlap" % [v60, pappus(60.0)])
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for v in verts_mm():
		lo = lo.min(v)
		hi = hi.max(v)
	ok(absf(hi.x - 165.0) < 1.0 and absf(hi.y - 150.0) < 1.0 and absf(hi.z - 15.0) < 1.0 and absf(lo.z + 15.0) < 1.0, "3e outer size: x to %.1f, y to %.1f (end cap at 150), tube +- %.1f mm" % [hi.x, hi.y, hi.z])
	ok(ctl_ok() and absf(ep.bend_spin.value - 60.0) < 0.6, "3f the control stays on the pipe, showing %.1f mm" % ep.bend_spin.value)

	# 4 change it with the slider (a real click on the track) and by typing: the pipe follows each time, one undo step each
	var u0: int = m.undo.size()
	var sl: HSlider = ep.bend_slider
	var rr := sl.get_global_rect()
	var frac := (90.0 - sl.min_value) / (sl.max_value - sl.min_value)
	await ev_move(Vector2(rr.position.x + 40.0, rr.get_center().y), false)
	await click_at(Vector2(rr.position.x + 8.0 + frac * (rr.size.x - 16.0), rr.get_center().y))
	await idle(25)
	var b1 := float(sweep_f().get("bend", -1.0))
	var fit1 := fit_bend(b1, 15.0)
	ok(absf(b1 - sl.value) < 0.6 and b1 > 70.0 and m.undo.size() == u0 + 1, "4 slider click: bend %.1f mm (slider %.1f), one more undo step (%d -> %d)" % [b1, sl.value, u0, m.undo.size()])
	ok(absf(float(fit1[0]) - b1) <= 1.0 and absf(vol_mm3() - pappus(b1)) <= 0.01 * pappus(b1), "4b the mesh follows: radius %.2f mm, volume %.0f vs %.0f mm3" % [fit1[0], vol_mm3(), pappus(b1)])
	await type_mm(30.0)
	var b2 := float(sweep_f().get("bend", -1.0))
	var fit2 := fit_bend(b2, 15.0)
	ok(absf(b2 - 30.0) < 0.01 and absf(float(fit2[0]) - 30.0) <= 1.0 and absf(vol_mm3() - pappus(30.0)) <= 0.01 * pappus(30.0) and m.undo.size() == u0 + 2 and int(pu().res.get("bodies", 0)) == 1,
		"4c typed 30 mm: record %.1f, mesh radius %.2f mm, volume %.0f vs %.0f mm3, one solid, undo steps %d" % [b2, fit2[0], vol_mm3(), pappus(30.0), m.undo.size() - u0])
	await shot("03_bend30")

	# 5 a radius the legs cannot hold (200 mm on 150 mm legs) is refused in words, the pipe stays as it was, no undo step
	await type_mm(200.0)
	ok(absf(float(sweep_f().get("bend", -1.0)) - 30.0) < 0.01 and m.undo.size() == u0 + 2 and String(ep.msg).find("does not fit") >= 0, "5 200 mm is refused (%s); the pipe keeps 30 mm" % String(ep.msg))

	# 6 Undo twice: back to the slider's radius, then to 60 mm; the mesh is measured again each time
	await click_ctl(ep.undo_btn)
	await idle(25)
	var b3 := float(sweep_f().get("bend", -1.0))
	var f3 := fit_bend(b1, 15.0)
	ok(absf(b3 - b1) < 0.01 and absf(float(f3[0]) - b1) <= 1.0, "6 Undo: bend back to %.1f mm, mesh radius %.2f mm" % [b3, f3[0]])
	await click_ctl(ep.undo_btn)
	await idle(25)
	var b4 := float(sweep_f().get("bend", -1.0))
	var f4 := fit_bend(60.0, 15.0)
	ok(absf(b4 - 60.0) < 0.01 and absf(float(f4[0]) - 60.0) <= 1.0 and absf(vol_mm3() - v60) < 1.0, "6b Undo: bend back to %.1f mm, mesh radius %.2f mm, volume %.0f mm3" % [b4, f4[0], vol_mm3()])
	ok(ctl_ok() and absf(ep.bend_spin.value - 60.0) < 0.6, "6c the control shows %.1f mm again" % ep.bend_spin.value)
	await click_ctl(ep.undo_btn)
	await idle(25)
	ok(n_sweeps() == s0 and int(pu().res.get("bodies", 0)) == 0, "6d Undo once more removes the pipe (sweeps %d, solids %d)" % [n_sweeps(), int(pu().res.get("bodies", 0))])

	# 7 untouched default: the next Pull along (the typed 60 is remembered for this shape) uses what the control shows
	await idle(10)
	var shown7: float = ep.bend_spin.value
	if ep.pull_along_btn.is_visible_in_tree():
		await click_ctl(ep.pull_along_btn)
	await idle(25)
	var b5 := float(sweep_f().get("bend", -1.0))
	var f5 := fit_bend(b5, 15.0)
	ok(absf(b5 - shown7) < 0.01 and absf(float(f5[0]) - b5) <= 1.0, "7 Pull along again: bend %.1f mm = the control's %.1f mm, mesh radius %.2f mm" % [b5, shown7, f5[0]])
	await shot("04_again")

	print("s216: %d fail" % fails)
	quit(1 if fails > 0 else 0)
