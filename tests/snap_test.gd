## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/snap_test.gd    (ROADMAP_400 B08)
## SNAPPING DURING G / R / S in the model preview (scripts/kmesh_snap.gd, hooks in bl_keys.gd). Real key and mouse events
## (pushed into the window), Blender keys on. Bars (stated before measuring):
##  0 closest_on_tri agrees with a dense barycentric sampling of the triangle (within the sampling's step) on 50
##    random points: the helper the body bar uses is itself measured
##  1 VERTEX: one vertex grabbed toward a neighbour and left 1.2 cm off it. Without Ctrl it stays > 1 cm away (the bar
##    can fail); with Ctrl held it lands on the neighbour (distance < 1e-6 m), ONE KMeshUndo step on Enter, Ctrl+Z puts
##    it back bit-exact; the marker is drawn within 2 px of the neighbour's screen point
##  2 GRID 5 cm (Shift+Tab x5 from vertex picks it): the vertex's world x, y, z each lie on a 5 cm multiple (1e-6);
##    without Ctrl at least one of them is > 1 mm off one
##  3 FACE: the grabbed vertex ends on the plane of the face it snapped to (distance < 1e-5 m) and inside it, and that
##    face does not hold the vertex; without Ctrl it is > 1 mm off that plane
##  4 BODY: a vertex > 5 cm from the fighter's skin, grabbed with Ctrl, ends < 1 mm from the nearest skin triangle
##    (brute force over EVERY visible skin triangle, no broad phase)
##  5 R with Ctrl: a 47.3 deg mouse turn snaps to 45 deg (the vertex's angle about the centre, 1e-3 deg); S with Ctrl:
##    x 1.135 snaps to x 1.1 (distance ratio, 1e-5); each is one undo step
##  6 the toggle ("Model: snapping always on / off", run from the S box's mesh row): snapping without Ctrl; Ctrl lets go
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


## the mouse moved so that a G moves by dw (its part in the view plane), Ctrl held or not
func move_by(dw: Vector3, ctrl: bool) -> void:
	var mpp: float = m.blk._mpp()
	var bx: Vector3 = m.cam.global_basis.x
	var by: Vector3 = m.cam.global_basis.y
	var e := InputEventMouseMotion.new()
	e.position = Vector2(500, 400)
	e.relative = Vector2(dw.dot(bx) / mpp, -dw.dot(by) / mpp)
	e.ctrl_pressed = ctrl
	root.push_input(e)
	await idle(3)


func mouse_x(px: float, ctrl: bool) -> void:
	var e := InputEventMouseMotion.new()
	e.position = Vector2(500, 400)
	e.relative = Vector2(px, 0)
	e.ctrl_pressed = ctrl
	root.push_input(e)
	await idle(3)


func select_only(v: int) -> void:
	ui.sel.set_mode(KMeshSelect.VERT)
	ui.sel.clear()
	ui.sel.verts[v] = true
	ui.view.mark_dirty()


func wpos(v: int) -> Vector3:
	return ui.view.global_transform * ui.mesh.verts[v]


## brute force: the distance from w to the nearest visible skin triangle
func skin_dist(w: Vector3) -> float:
	var sp: SkinPick = m.skp
	sp.refresh()
	var best := INF
	for gr in sp.groups:
		if not (gr["mi"] as MeshInstance3D).is_visible_in_tree():
			continue
		var pos: PackedVector3Array = sp.surfs[gr["k"]]["pos"]
		for c in gr["chunks"]:
			var tris: PackedInt32Array = c["tris"]
			for t in range(0, tris.size(), 3):
				best = minf(best, KMeshSnap.closest_on_tri(w, pos[tris[t]], pos[tris[t + 1]], pos[tris[t + 2]]).distance_to(w))
	return best


func off_grid(w: Vector3, g: float) -> float:
	var worst := 0.0
	for a in 3:
		worst = maxf(worst, absf(w[a] - snappedf(w[a], g)))
	return worst


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	ok(m.settings.begins_with("user://poser_test_"), "0 own config (%s)" % m.settings)

	# 0. the triangle helper against sampling
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var worst0 := 0.0
	for n in 50:
		var a := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		var b := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		var c := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		var p := Vector3(rng.randf_range(-2, 2), rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		var got := KMeshSnap.closest_on_tri(p, a, b, c).distance_to(p)
		var best := INF
		var N := 120
		for i in N + 1:
			for j in N + 1 - i:
				best = minf(best, (a + (b - a) * (float(i) / N) + (c - a) * (float(j) / N)).distance_to(p))
		worst0 = maxf(worst0, got - best)   # never farther than a sample; a sample at most ~a step nearer is not possible
		if got > best + 1e-6 or best - got > 0.03:
			worst0 = INF
	ok(worst0 <= 1e-6, "0 closest_on_tri never beaten by a sample of the triangle (worst %s)" % str(worst0))

	m.blk.set_on(true, false)
	m._kmesh_edit_start()
	await idle(3)
	ui = m.kmed
	m._turn_to(30.0, -20.0, 2.6, Vector3(0.8, 0.45, 0.0), false)
	await idle(3)
	var cz: Vector3 = m.cam.global_basis.z

	# 1. vertex
	var P := -1   # a pair of grid neighbours (< 0.2 m apart) lying as flat to the view as any
	var T := -1
	var bestd := INF
	var flat := INF
	for i in ui.mesh.verts.size():
		for j in ui.mesh.verts.size():
			var dv: Vector3 = ui.mesh.verts[j] - ui.mesh.verts[i]
			if i != j and dv.length() < 0.2 and absf(dv.dot(cz)) < flat:
				flat = absf(dv.dot(cz))
				bestd = dv.length()
				P = i
				T = j
	var tw := wpos(T)
	var dw: Vector3 = (tw - wpos(P)) + m.cam.global_basis.x * 0.012
	print("     vertex %d -> %d (%.3f m apart, depth part %.4f)" % [P, T, bestd, (tw - wpos(P)).dot(cz)])
	select_only(P)
	var base: PackedVector3Array = ui.mesh.verts.duplicate()
	var steps0: int = ui.undo.steps.size()
	await tap(KEY_G)
	await move_by(dw, false)
	var d_free := wpos(P).distance_to(tw)
	await tap(KEY_ESCAPE)
	ok(d_free > 0.01 and ui.mesh.verts == base, "1a without Ctrl the vertex stays %.4f m off the neighbour (Esc: back bit-exact)" % d_free)
	await tap(KEY_G)
	await move_by(dw, true)
	await idle(2)
	var d_snap := wpos(P).distance_to(tw)
	var mark: Vector2 = ui.snap.drawn_at
	var want: Vector2 = m.cam.unproject_position(tw)
	print("     marker drawn at %s, the neighbour at %s" % [mark, want])
	ok(d_snap < 1e-6, "1b with Ctrl it lands on the neighbour (%s m)" % str(d_snap))
	ok(mark.is_finite() and mark.distance_to(want) <= 2.0, "1c the marker is drawn on the target (%.2f px)" % mark.distance_to(want))
	await tap(KEY_ENTER)
	var others := true
	for i in base.size():
		if i != P and ui.mesh.verts[i] != base[i]:
			others = false
	ok(ui.undo.steps.size() == steps0 + 1 and wpos(P).distance_to(tw) < 1e-6 and others, "1d Enter keeps it: one undo step (%d), the other vertices untouched" % (ui.undo.steps.size() - steps0))
	await idle(2)
	ok(not ui.snap.drawn_at.is_finite(), "1e the marker is gone after Enter")
	await tap(KEY_Z, true)
	ok(ui.mesh.verts == base and ui.undo.steps.size() == steps0, "1f Ctrl+Z puts it back bit-exact")

	# 2. grid 5 cm
	for i in 5:
		await tap(KEY_TAB, false, true)
	ok(ui.snap.target == "grid5", "2a Shift+Tab x5 picks grid 5 cm (%s)" % ui.snap.target)
	select_only(5)
	var g_dw: Vector3 = m.cam.global_basis.x * 0.0337 + m.cam.global_basis.y * 0.0213
	await tap(KEY_G)
	await move_by(g_dw, false)
	var g_free := off_grid(wpos(5), 0.05)
	await tap(KEY_ESCAPE)
	await tap(KEY_G)
	await move_by(g_dw, true)
	await tap(KEY_ENTER)
	var g_snap := off_grid(wpos(5), 0.05)
	print("     grid: %s (off %s; without Ctrl %s)" % [wpos(5), str(g_snap), str(g_free)])
	ok(g_free > 0.001 and g_snap < 1e-6 and ui.undo.steps.size() == steps0 + 1, "2b on 5 cm multiples (%s m off; %.4f without Ctrl), one step" % [str(g_snap), g_free])

	# 3. face
	ui.snap.target = "face"
	var fv := 9
	select_only(fv)
	var f_dw: Vector3 = m.cam.global_basis.x * 0.05 + m.cam.global_basis.y * 0.03
	await tap(KEY_G)
	await move_by(f_dw, true)
	var hf: int = int(ui.snap.hit.get("face", -1))
	await tap(KEY_ENTER)
	var f_ok := hf >= 0
	var plane_d := INF
	var free_d := INF
	var inside := false
	if f_ok:
		var f: PackedInt32Array = ui.mesh.faces[hf]
		var a: Vector3 = ui.mesh.verts[f[0]]
		var nrm: Vector3 = (ui.mesh.verts[f[1]] - a).cross(ui.mesh.verts[f[2]] - a).normalized()
		plane_d = absf((ui.mesh.verts[fv] - a).dot(nrm))
		free_d = absf((base[fv] + f_dw - a).dot(nrm))
		f_ok = not (fv in Array(f))
		var poly := []
		for v in f:
			poly.append(ui.mesh.verts[v])
		var c := Vector3.ZERO
		for q in poly:
			c += q
		c /= poly.size()
		# inside: the snapped point is a convex combination: every edge has it on the same side as the centre
		inside = true
		for k in poly.size():
			var e0: Vector3 = poly[k]
			var e1: Vector3 = poly[(k + 1) % poly.size()]
			var side: float = (e1 - e0).cross(ui.mesh.verts[fv] - e0).dot(nrm)
			var cside: float = (e1 - e0).cross(c - e0).dot(nrm)
			if side * signf(cside) < -1e-7:
				inside = false
	print("     face %d: plane distance %s, without Ctrl %s" % [hf, str(plane_d), str(free_d)])
	ok(f_ok and plane_d < 1e-5 and inside and free_d > 0.001, "3 face snap: on the plane of face %d (%s m), inside it; %.4f m off without Ctrl" % [hf, str(plane_d), free_d])

	# 4. body
	ui.snap.target = "body"
	var bv := 0
	var bestx := INF
	for i in ui.mesh.verts.size():   # the vertex nearest the fighter (at the origin)
		if wpos(i).x < bestx:
			bestx = wpos(i).x
			bv = i
	select_only(bv)
	var pre := skin_dist(wpos(bv))
	var b_dw: Vector3 = m.cam.global_basis.x * -0.35
	await tap(KEY_G)
	await move_by(b_dw, true)
	await tap(KEY_ENTER)
	var post := skin_dist(wpos(bv))
	print("     body: vertex %d from %.4f m to %s m off the skin, at %s" % [bv, pre, str(post), wpos(bv)])
	ok(pre > 0.05 and post < 0.001, "4 body snap: %.3f m -> %.6f m from the nearest skin triangle (brute force)" % [pre, post])

	# 5. R / S increments
	ui.sel.set_mode(KMeshSelect.VERT)
	ui.sel.clear()
	for i in [20, 21, 22, 25]:
		ui.sel.verts[i] = true
	var r0: PackedVector3Array = ui.mesh.verts.duplicate()
	var cen := (r0[20] + r0[21] + r0[22] + r0[25]) / 4.0
	var n0: int = ui.undo.steps.size()
	await tap(KEY_R)
	await tap(KEY_Z)
	await mouse_x(47.3 / BlKeys.DEG_PER_PX, true)
	await tap(KEY_ENTER)
	var v0: Vector3 = r0[20] - cen
	var v1: Vector3 = ui.mesh.verts[20] - cen
	var ang := rad_to_deg(atan2(v1.y, v1.x) - atan2(v0.y, v0.x))
	ang = fposmod(ang + 180.0, 360.0) - 180.0
	print("     R with Ctrl: %.5f deg" % ang)
	ok(absf(absf(ang) - 45.0) < 1e-3 and ui.undo.steps.size() == n0 + 1, "5a R Z with Ctrl: 47.3 deg of mouse snapped to %.4f deg, one step" % ang)
	var s0: PackedVector3Array = ui.mesh.verts.duplicate()
	await tap(KEY_S)
	await mouse_x(0.135 / BlKeys.SCALE_PER_PX, true)
	await tap(KEY_ENTER)
	var ratio: float = (ui.mesh.verts[20] - cen).length() / (s0[20] - cen).length()
	ok(absf(ratio - 1.1) < 1e-5 and ui.undo.steps.size() == n0 + 2, "5b S with Ctrl: x1.135 of mouse snapped to x%.6f, one step" % ratio)

	# 6. the toggle, from the S box's row
	var row := {}
	for r in MeshTools.rows(m):
		if (r["tool"] as Dictionary)["id"] == "mesh_snap_toggle":
			row = r
	ok(not row.is_empty(), "6a the S box has 'Model: snapping always on / off'")
	if not row.is_empty():
		(row["run"] as Callable).call()
	ui.snap.target = "vert"
	select_only(P)
	var t0: PackedVector3Array = ui.mesh.verts.duplicate()
	tw = ui.view.global_transform * t0[T]
	dw = (tw - ui.view.global_transform * t0[P]) + m.cam.global_basis.x * 0.012
	await tap(KEY_G)
	await move_by(dw, false)
	var d_on := wpos(P).distance_to(tw)
	await move_by(Vector3.ZERO, true)   # Ctrl held: lets go
	var d_let := wpos(P).distance_to(tw)
	await tap(KEY_ESCAPE)
	ok(ui.snap.always and d_on < 1e-6 and d_let > 0.01, "6b always on: snaps without Ctrl (%s m), Ctrl lets go (%.4f m)" % [str(d_on), d_let])
	ui.snap.always = false

	m.blk.set_on(false, false)
	print("SNAP: %d failed" % fails)
	quit(1 if fails > 0 else 0)
