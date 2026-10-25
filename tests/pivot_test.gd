## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/pivot_test.gd    (ROADMAP_400 B14)
## PIVOT MODES FOR R / S AND THE 3D CURSOR in the model preview (scripts/kmesh_pivot.gd, hooks in bl_keys.gd). Real key
## and mouse events pushed into the window, Blender keys on. Bars (stated before measuring):
##  1 PLACEMENT: Shift+right-click on a cube face that faces the camera puts the cursor on that face's plane (< 1e-5 m)
##    under the mouse (its projection within 0.5 px); the crosshair is DRAWN there: the pixels that changed in a 60 px
##    window round the click (screenshots before / after) have their centre within 2 px of the click, and there are
##    >= 30 of them (it is drawn at all); drawn_at within 2 px. Screenshot env PIVOT_SHOT
##  2 "." cycles median -> active -> cursor -> individual -> median (the status line names each)
##  3 CURSOR: S 2 Enter on 6 vertices maps each p to c + 2 (p - c) (world, < 1e-6 m), ONE KMeshUndo step; the cursor is
##    > 5 cm from their median (a median scale would fail the bar)
##  4 INDIVIDUAL ORIGINS: two faces with no shared vertex, S 2 Enter: each face's centre stays (< 1e-6 m) and each of its
##    corners is at centre + 2 (p - centre) (< 1e-6); each centre is > 5 cm from the median of both; ONE step
##  5 ACTIVE: three vertices clicked (click, Shift+click, Shift+click) with the mouse; the last clicked is the active one;
##    S 2 Enter keeps it bit-exact where it was and maps the others to a + 2 (p - a) (< 1e-6); it is > 1 cm from the
##    median; ONE step. R Z 90 about it keeps it too
##  6 Ctrl+Z three times walks the three transforms back: the mesh is bit-exact the cube as it was
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


func tap(code: Key, ctrl := false, shift := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.ctrl_pressed = ctrl
		e.shift_pressed = shift
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func typ(s: String) -> void:
	for ch in s:
		await tap(KEY_PERIOD if ch == "." else (KEY_0 + int(ch)) as Key)


func click(p: Vector2, button: MouseButton, shift := false) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	root.push_input(mv)
	await process_frame
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = p
		e.global_position = p
		e.button_index = button
		e.shift_pressed = shift
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func wpos(v: int) -> Vector3:
	return ui.view.global_transform * ui.mesh.verts[v]


func shot() -> Image:
	await RenderingServer.frame_post_draw
	return m.get_viewport().get_texture().get_image()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	ok(m.settings.begins_with("user://poser_test_"), "0 own config (%s)" % m.settings)
	m.blk.set_on(true, false)
	m._kmesh_edit_start()
	await idle(3)
	ui = m.kmed
	m._turn_to(30.0, -20.0, 2.6, Vector3(0.8, 0.45, 0.0), false)
	await idle(4)
	var cam: Camera3D = m.cam
	var cube0: PackedVector3Array = ui.mesh.verts.duplicate()
	var xf: Transform3D = ui.view.global_transform

	# 1. placement: a face that faces the camera, near the screen's middle
	var bf := -1
	var bdot := 0.0
	for fi in ui.mesh.faces.size():
		var f: PackedInt32Array = ui.mesh.faces[fi]
		var c := Vector3.ZERO
		for v in f:
			c += wpos(v)
		c /= f.size()
		var nrm: Vector3 = (wpos(f[1]) - wpos(f[0])).cross(wpos(f[2]) - wpos(f[0])).normalized()
		var dd := nrm.dot((cam.global_position - c).normalized())
		if dd > bdot and ui.view.point_visible(cam, c):
			bdot = dd
			bf = fi
	var fpts: PackedInt32Array = ui.mesh.faces[bf]
	var fc := Vector3.ZERO
	for v in fpts:
		fc += wpos(v)
	fc /= fpts.size()
	var aim: Vector2 = cam.unproject_position(fc) + Vector2(3.0, -2.0)
	print("     face %d (facing %.2f), click at %s, cursor now drawn at %s" % [bf, bdot, aim, ui.pivot.drawn_at])
	var before: Image = await shot()
	await click(aim, MOUSE_BUTTON_RIGHT, true)
	await idle(3)
	var after: Image = await shot()
	var n0: Vector3 = (wpos(fpts[1]) - wpos(fpts[0])).cross(wpos(fpts[2]) - wpos(fpts[0])).normalized()
	var on_plane := absf((ui.pivot.cursor - wpos(fpts[0])).dot(n0))
	var under: float = cam.unproject_position(ui.pivot.cursor).distance_to(aim)
	ok(on_plane < 1e-5 and under < 0.5, "1a the cursor is on the face's plane (%s m), under the mouse (%.3f px)" % [str(on_plane), under])
	var sum := Vector2.ZERO
	var cnt := 0
	for y in range(int(aim.y) - 30, int(aim.y) + 31):
		for x in range(int(aim.x) - 30, int(aim.x) + 31):
			if x < 0 or y < 0 or x >= before.get_width() or y >= before.get_height():
				continue
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.12:
				sum += Vector2(x + 0.5, y + 0.5)
				cnt += 1
	var cen := sum / maxf(cnt, 1)
	print("     crosshair: %d changed pixels, centre %s, the click %s, drawn_at %s" % [cnt, cen, aim, ui.pivot.drawn_at])
	ok(cnt >= 30 and cen.distance_to(aim) <= 2.0, "1b the crosshair is drawn at the click: changed pixels' centre %.2f px off (%d px)" % [cen.distance_to(aim), cnt])
	ok(ui.pivot.drawn_at.is_finite() and ui.pivot.drawn_at.distance_to(aim) <= 2.0, "1c drawn_at %.2f px from the click" % ui.pivot.drawn_at.distance_to(aim))
	var sp := OS.get_environment("PIVOT_SHOT")
	after.save_png(sp if sp != "" else "user://pivot.png")

	# 2. the cycle
	var seen := []
	var said := ""
	for i in 4:
		await tap(KEY_PERIOD)
		seen.append(ui.pivot.mode)
		if i == 0:
			said = m.ui_status.text
	print("     status after the first '.': ", said)
	ok(seen == ["active", "cursor", "individual", "median"] and "active element" in said, "2 '.' cycles %s, the status line names it" % [seen])
	await tap(KEY_PERIOD)
	await tap(KEY_PERIOD)
	ok(ui.pivot.mode == "cursor", "2b two more: cursor")

	# 3. scale 2 about the cursor
	var vs := [0, 5, 10, 17, 30, 41]
	ui.sel.set_mode(KMeshSelect.VERT)
	ui.sel.clear()
	for v in vs:
		ui.sel.verts[v] = true
	var med := Vector3.ZERO
	var p0 := {}
	for v in vs:
		p0[v] = wpos(v)
		med += wpos(v)
	med /= vs.size()
	var c3: Vector3 = ui.pivot.cursor
	var st0: int = ui.undo.steps.size()
	await tap(KEY_S)
	await typ("2")
	await tap(KEY_ENTER)
	var e3 := 0.0
	for v in vs:
		e3 = maxf(e3, wpos(v).distance_to(c3 + 2.0 * ((p0[v] as Vector3) - c3)))
	ok(e3 < 1e-6 and c3.distance_to(med) > 0.05 and ui.undo.steps.size() == st0 + 1,
		"3 S 2 about the cursor: p -> c + 2(p - c) within %s m (cursor %.3f m from the median), one step" % [str(e3), c3.distance_to(med)])

	# 4. individual origins: two faces with no shared vertex
	await tap(KEY_PERIOD)
	ok(ui.pivot.mode == "individual", "4a '.' -> individual origins")
	ui.sel.set_mode(KMeshSelect.FACE)
	ui.sel.clear()
	var fa := 0
	var fb := -1
	var fav := {}
	for v in (ui.mesh.faces[fa] as PackedInt32Array):
		fav[v] = true
	for fi in range(ui.mesh.faces.size() - 1, 0, -1):
		var share := false
		for v in (ui.mesh.faces[fi] as PackedInt32Array):
			if fav.has(v):
				share = true
		if not share:
			fb = fi
			break
	ui.sel.faces[fa] = true
	ui.sel.faces[fb] = true
	var cents := {}
	var corners := {}
	var allm := Vector3.ZERO
	var alln := 0
	for fi in [fa, fb]:
		var c := Vector3.ZERO
		for v in (ui.mesh.faces[fi] as PackedInt32Array):
			c += wpos(v)
			corners[v] = wpos(v)
			allm += wpos(v)
			alln += 1
		cents[fi] = c / (ui.mesh.faces[fi] as PackedInt32Array).size()
	allm /= alln
	await tap(KEY_S)
	await typ("2")
	await tap(KEY_ENTER)
	var ec := 0.0
	var ep := 0.0
	var far := INF
	for fi in [fa, fb]:
		var c := Vector3.ZERO
		for v in (ui.mesh.faces[fi] as PackedInt32Array):
			c += wpos(v)
			ep = maxf(ep, wpos(v).distance_to((cents[fi] as Vector3) + 2.0 * ((corners[v] as Vector3) - (cents[fi] as Vector3))))
		c /= (ui.mesh.faces[fi] as PackedInt32Array).size()
		ec = maxf(ec, c.distance_to(cents[fi]))
		far = minf(far, (cents[fi] as Vector3).distance_to(allm))
	ok(ec < 1e-6 and ep < 1e-6 and far > 0.05 and ui.undo.steps.size() == st0 + 2,
		"4b faces %d and %d: centres kept (%s m), corners at c + 2(p - c) (%s m), centres %.3f m from the median, one step" % [fa, fb, str(ec), str(ep), far])

	# 5. active: three vertices clicked with the mouse
	await tap(KEY_PERIOD)
	await tap(KEY_PERIOD)
	ok(ui.pivot.mode == "active", "5a '.' '.' -> active element")
	ui.sel.set_mode(KMeshSelect.VERT)
	ui.sel.clear()
	ui.view.mark_dirty()
	await idle(2)
	var pick := []
	var spots := []
	for v in ui.mesh.verts.size():
		var w := wpos(v)
		if not ui.view.point_visible(cam, w):
			continue
		var s := cam.unproject_position(w)
		var h: Dictionary = ui.view.pick(cam, s)
		if h.is_empty() or int(h["vert"]) != v:
			continue
		var apart := true
		for q in spots:
			if s.distance_to(q) < 60.0:
				apart = false
		if apart and m.get_viewport().get_visible_rect().grow(-40).has_point(s):
			pick.append(v)
			spots.append(s)
		if pick.size() == 3:
			break
	for k in pick.size():
		await click(spots[k], MOUSE_BUTTON_LEFT, k > 0)
	var a5: int = pick[2] if pick.size() == 3 else -1
	print("     clicked %s, selected %s, active %s" % [pick, ui.sel.verts.keys(), ui.pivot.active])
	ok(pick.size() == 3 and ui.sel.verts.size() == 3 and ui.pivot.active.get("key", -1) == a5, "5b three clicked, the last (%d) is the active one" % a5)
	if pick.size() == 3:
		var q0 := {}
		var med5 := Vector3.ZERO
		for v in pick:
			q0[v] = ui.mesh.verts[v]
			med5 += wpos(v)
		med5 /= 3.0
		var aw := wpos(a5)
		await tap(KEY_S)
		await typ("2")
		await tap(KEY_ENTER)
		var e5 := 0.0
		for v in pick:
			e5 = maxf(e5, wpos(v).distance_to(aw + 2.0 * (xf * (q0[v] as Vector3) - aw)))
		ok(ui.mesh.verts[a5] == q0[a5] and e5 < 1e-6 and aw.distance_to(med5) > 0.01 and ui.undo.steps.size() == st0 + 3,
			"5c S 2 about the active vertex: it stays bit-exact, the others at a + 2(p - a) (%s m); %.3f m from the median; one step" % [str(e5), aw.distance_to(med5)])
		var q1: Vector3 = ui.mesh.verts[a5]
		await tap(KEY_R)
		await tap(KEY_Z)
		await typ("90")
		await tap(KEY_ENTER)
		ok(ui.mesh.verts[a5].distance_to(q1) < 1e-6 and ui.undo.steps.size() == st0 + 4, "5d R Z 90 about it keeps it (%s m)" % str(ui.mesh.verts[a5].distance_to(q1)))
		await tap(KEY_Z, true)

	# 6. undo walks back
	for i in 3:
		await tap(KEY_Z, true)
	ok(ui.mesh.verts == cube0 and ui.undo.steps.size() == st0, "6 Ctrl+Z x3: the cube bit-exact as it was (%d steps)" % ui.undo.steps.size())

	m.blk.set_on(false, false)
	print("PIVOT: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
