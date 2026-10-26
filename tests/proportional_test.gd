## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/proportional_test.gd    (ROADMAP_400 B07)
## PROPORTIONAL EDITING in the model preview, through real keys (O / Shift+O / Alt+O, then the Blender-style G X 0.1 Enter).
## The mesh: a plane of 1 cm quads (41 x 11, x -20..20 cm, z -5..5 cm) plus a separate one-quad island 5 cm above the
## selected vertex (x -15 cm). Radius 30 cm (the default). Bars (stated before measuring):
##  1 O turns it on (status says so); the radius is 30 cm; Shift+O walks smooth sphere root linear sharp constant
##  2 for EACH falloff, G X 0.1 Enter: the verts 0 / 15 / 30 / 31 cm along the row move 10 cm * f(t), t = 1 - d / 0.3,
##    curves written out here (not read from the script): within 0.1 mm (constant is not checked at exactly 30 cm,
##    the boundary itself); nothing moves off the X axis; ONE KMeshUndo step; Ctrl+Z puts every vertex back bit-exact
##  3 connected only (Alt+O): the island (5.2 cm away in space) does not move at all, while with it off it moves
##    10 cm * smooth(5.2 / 30) (+-0.1 mm); a grid vert 3 cm along / 4 cm across (5 cm straight, 7 cm along the edges)
##    moves by smooth at 7 cm, not 5 cm (+-0.1 mm); Ctrl+Z bit-exact
##  4 the wheel during a live G: radius x 1.1 (33 cm), the 31 cm vert now moves (10 cm * smooth(1 - 31/33), +-0.1 mm),
##    the circle's pixel radius grows x 1.1 (+-3%); Esc puts every vertex back bit-exact and keeps no step
##  5 PLACEMENT: mid-G the circle is drawn centred on the selected vertex's screen point (+-1.5 px) with the pixel radius
##    of 30 cm at that depth (+-3%), inside the window, and the screenshot shows the circle's colour on >= 6 of 8 points
##    of the ring and on <= 2 of 8 points of a ring at 0.6 r (env PROP_SHOT saves it)
extends SceneTree

var fails := 0
var m: Node
var ui


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func tap(code: Key, ctrl := false, shift := false, alt := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.ctrl_pressed = ctrl
		e.shift_pressed = shift
		e.alt_pressed = alt
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func typ(s: String) -> void:
	for ch in s:
		await tap(KEY_PERIOD if ch == "." else (KEY_0 + int(ch)) as Key)


func curve(kind: String, d: float, r: float) -> float:
	if d > r:
		return 0.0
	var t := 1.0 - d / r
	match kind:
		"smooth":
			return t * t * (3.0 - 2.0 * t)
		"sphere":
			return sqrt(1.0 - (1.0 - t) * (1.0 - t))
		"root":
			return pow(t, 0.5)
		"linear":
			return t
		"sharp":
			return t * t
		_:
			return 1.0


const NX := 41
const NZ := 11


func gi(ix: int, iz: int) -> int:
	return iz * NX + ix


func grab_x(amount: String, keep := true) -> void:
	await tap(KEY_G)
	await tap(KEY_X)
	await typ(amount)
	if keep:
		await tap(KEY_ENTER)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._card_add()
	m.blk.set_on(true, false)
	m._kmesh_edit_start()
	await idle(3)
	ui = m.kmed
	# the plane of 1 cm quads + the island
	var vs := PackedVector3Array()
	for iz in NZ:
		for ix in NX:
			vs.append(Vector3(-0.20 + ix * 0.01, 0.0, -0.05 + iz * 0.01))
	var fs: Array = []
	for iz in NZ - 1:
		for ix in NX - 1:
			fs.append(PackedInt32Array([gi(ix, iz), gi(ix, iz + 1), gi(ix + 1, iz + 1), gi(ix + 1, iz)]))
	var isl := vs.size()
	for q in [Vector3(-0.16, 0.05, -0.01), Vector3(-0.16, 0.05, 0.01), Vector3(-0.14, 0.05, 0.01), Vector3(-0.14, 0.05, -0.01)]:
		vs.append(q)
	fs.append(PackedInt32Array([isl, isl + 1, isl + 2, isl + 3]))
	var mesh := KMesh.new()
	mesh.from_arrays(vs, fs)
	ui.mesh = mesh
	ui.undo = KMeshUndo.new()
	ui._after_topo()
	var s0 := gi(5, 5)   # x -15 cm, z 0
	var row := {0.0: s0, 0.15: gi(20, 5), 0.30: gi(35, 5), 0.31: gi(36, 5)}
	print("     selected at %s, row verts at %s %s %s" % [mesh.verts[s0], mesh.verts[row[0.15]], mesh.verts[row[0.30]], mesh.verts[row[0.31]]])
	ui.sel.verts = {s0: true}
	var base: PackedVector3Array = mesh.verts.duplicate()
	m._turn_to(0.0, -35.0, 1.2, ui.view.global_transform * Vector3(-0.05, 0, 0), false)
	await idle(3)

	# 1
	await tap(KEY_O)
	ok(ui.prop.on and "proportional editing on" in m.ui_status.text and is_equal_approx(ui.prop.radius, 0.3) and ui.prop.falloff == "smooth",
		"1a O: on, smooth, radius %.3f (%s)" % [ui.prop.radius, m.ui_status.text.left(70)])

	# 2 + 5
	var order := []
	for k in 6:
		order.append(ui.prop.falloff)
		var u0: int = ui.undo.steps.size()
		await grab_x("0.1", false)
		if k == 0:   # 5. placement mid-G, smooth
			await idle(4)
			var cam: Camera3D = m.cam
			var wc: Vector3 = ui.view.global_transform * mesh.verts[s0]
			var want_c := cam.unproject_position(wc)
			var want_r := want_c.distance_to(cam.unproject_position(wc + cam.global_basis.x * 0.3))
			var lc: Dictionary = ui.prop.last_circle
			var vp: Rect2 = root.get_visible_rect()
			print("     circle %s, expected centre %s r %.1f px" % [lc, want_c, want_r])
			var placed: bool = not lc.is_empty() and (lc["centre"] as Vector2).distance_to(want_c) <= 1.5 and absf(float(lc["r"]) / want_r - 1.0) <= 0.03 \
				and vp.encloses(Rect2(want_c - Vector2.ONE * want_r, Vector2.ONE * want_r * 2.0)) and want_r > 20.0
			ok(placed, "5a the circle is centred on the selected vertex (%.2f px off) with 30 cm's pixel radius (%.1f / %.1f), inside the window" % [
				(lc.get("centre", Vector2.INF) as Vector2).distance_to(want_c), float(lc.get("r", 0.0)), want_r])
			var img: Image = root.get_texture().get_image()
			var shot := OS.get_environment("PROP_SHOT")
			if shot != "":
				img.save_png(shot)
			var col := Tok.c("pick_hover")
			var on_ring := 0
			var inner := 0
			for a in 8:
				var dir := Vector2.from_angle(TAU * a / 8.0 + 0.2)
				if _has_col(img, want_c + dir * want_r, col):
					on_ring += 1
				if _has_col(img, want_c + dir * want_r * 0.6, col):
					inner += 1
			ok(on_ring >= 6 and inner <= 2, "5b screenshot: the circle's colour on %d / 8 ring points, %d / 8 at 0.6 r" % [on_ring, inner])
		await tap(KEY_ENTER)
		var f: String = order[k]
		var worst := 0.0
		var line := ""
		for d in row:
			if f == "constant" and is_equal_approx(d, 0.30):
				continue
			var want := 0.1 * curve(f, d, 0.3) if d > 0.0 else 0.1
			var got: Vector3 = mesh.verts[row[d]] - base[row[d]]
			worst = maxf(worst, absf(got.x - want) + absf(got.y) + absf(got.z))
			line += " %d cm %.5f/%.5f" % [roundi(d * 100), got.x, want]
		print("     %s:%s" % [f, line])
		ok(worst <= 1e-4 and ui.undo.steps.size() == u0 + 1, "2 %s: 0/15/30/31 cm moved by the curve (worst %.6f m), one step" % [f, worst])
		await tap(KEY_Z, true)
		ok(mesh.verts == base and ui.undo.steps.size() == u0, "2 %s: Ctrl+Z puts every vertex back bit-exact" % f)
		await tap(KEY_O, false, true)
	ok(order == ["smooth", "sphere", "root", "linear", "sharp", "constant"] and ui.prop.falloff == "smooth", "1b Shift+O walks %s and back to smooth" % [order])

	# 3. connected only
	var diag := gi(8, 9)   # 3 cm along, 4 cm across: 5 cm straight, 7 cm along the edges
	await grab_x("0.1")
	var di := base[isl].distance_to(base[s0])
	var want_i := 0.1 * curve("smooth", di, 0.3)
	var got_i: float = (mesh.verts[isl] - base[isl]).x
	var got_d0: float = (mesh.verts[diag] - base[diag]).x
	ok(absf(got_i - want_i) <= 1e-4 and absf(got_d0 - 0.1 * curve("smooth", 0.05, 0.3)) <= 1e-4,
		"3a connected off: the island (%.4f m away) moves %.5f (want %.5f), the diagonal vert by smooth at 5 cm" % [di, got_i, want_i])
	await tap(KEY_Z, true)
	await tap(KEY_O, false, false, true)
	ok(ui.prop.connected and "connected only" in m.ui_status.text, "3b Alt+O: connected only")
	await grab_x("0.1")
	var moved_isl := 0.0
	for j in 4:
		moved_isl = maxf(moved_isl, (mesh.verts[isl + j] - base[isl + j]).length())
	var got_d: float = (mesh.verts[diag] - base[diag]).x
	var got_15: float = (mesh.verts[row[0.15]] - base[row[0.15]]).x
	print("     connected: island %s, diagonal %.5f (7 cm %.5f, 5 cm %.5f), 15 cm %.5f" % [moved_isl, got_d, 0.1 * curve("smooth", 0.07, 0.3), 0.1 * curve("smooth", 0.05, 0.3), got_15])
	ok(moved_isl == 0.0 and absf(got_d - 0.1 * curve("smooth", 0.07, 0.3)) <= 1e-4 and absf(got_15 - 0.05) <= 1e-4 and ui.undo.steps.size() == 1,
		"3c connected: the island does not move (%s), the diagonal goes by the 7 cm path, 15 cm still 0.05, one step" % moved_isl)
	await tap(KEY_Z, true)
	ok(mesh.verts == base and ui.undo.steps.is_empty(), "3d Ctrl+Z bit-exact")
	await tap(KEY_O, false, false, true)
	ok(not ui.prop.connected, "3e Alt+O again: connected off")

	# 4. the wheel
	await grab_x("0.1", false)
	await idle(3)
	var r0 := float(ui.prop.last_circle.get("r", 0.0))
	var w31_0: float = (mesh.verts[row[0.31]] - base[row[0.31]]).x
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_WHEEL_UP
		e.pressed = down
		e.position = root.get_visible_rect().size * 0.5
		root.push_input(e)
		await process_frame
	await idle(3)
	var r1 := float(ui.prop.last_circle.get("r", 0.0))
	var w31: float = (mesh.verts[row[0.31]] - base[row[0.31]]).x
	var want31 := 0.1 * curve("smooth", 0.31, 0.33)
	print("     wheel: radius %.4f, circle %.1f -> %.1f px, 31 cm vert %.5f -> %.5f (want %.5f)" % [ui.prop.radius, r0, r1, w31_0, w31, want31])
	ok(absf(ui.prop.radius - 0.33) < 1e-6 and r0 > 0.0 and absf(r1 / r0 - 1.1) <= 0.03 and w31_0 == 0.0 and absf(w31 - want31) <= 1e-4 and m.blk.active == "G",
		"4a wheel up mid-G: radius 33 cm, circle x %.3f, the 31 cm vert now moves %.5f" % [r1 / maxf(r0, 1e-6), w31])
	await tap(KEY_ESCAPE)
	ok(mesh.verts == base and ui.undo.steps.is_empty() and m.blk.active == "",
		"4b Esc: every vertex bit-exact, no step")
	await idle(2)
	ok(ui.prop.last_circle.is_empty(), "4c the circle is gone after Esc")
	m.blk.set_on(false, false)
	print("PROPORTIONAL: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)


func _has_col(img: Image, p: Vector2, col: Color) -> bool:
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var x := int(p.x) + dx
			var y := int(p.y) + dy
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var c := img.get_pixel(x, y)
			if absf(c.r - col.r) + absf(c.g - col.g) + absf(c.b - col.b) < 0.25:
				return true
	return false
