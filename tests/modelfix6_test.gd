## godot --path . -s tests/modelfix6_test.gd   (MODEL FIX ROUND 6, from walk-through 5, frictions A and B)
## A: a hole in the test cube (one face deleted) is closed by Alt+F with a rim edge selected (a), by F with the 4 rim
##    edges selected (b), by Alt+F with nothing selected (c). Each: the faces go 95 -> 96, no open edge, the new face's
##    normal points out, one undo step, and Ctrl+Z gives the hole back.
## B: F2 (rename) focuses the name box; Enter or Esc gives the keyboard back to the view, and F3 opens the search box.
##    (e) F2, type a name, Enter: the name is set, then F3 opens the search; (f) F2, Esc, then F3 opens it.
## Real keys and clicks (root.push_input(e, true)), 1280 x 720 pinned.
extends SceneTree

var fails := 0
var m: Node
var kmed = null


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func key(k: Key, ctrl := false, shift := false, alt := false) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.ctrl_pressed = ctrl
		ev.shift_pressed = shift
		ev.alt_pressed = alt
		ev.pressed = down
		root.push_input(ev, true)
		await process_frame
	await idle(3)


func typed(s: String) -> void:
	for c in s:
		var code: int = c.to_upper().unicode_at(0)
		for down in [true, false]:
			var ev := InputEventKey.new()
			ev.keycode = code as Key
			ev.physical_keycode = code as Key
			ev.unicode = c.unicode_at(0)
			ev.pressed = down
			root.push_input(ev, true)
			await process_frame
	await idle(4)


func button(txt: String) -> void:
	for n in root.find_children("*", "Button", true, false):
		var b := n as Button
		if b.is_visible_in_tree() and b.text.strip_edges() == txt:
			var c: Vector2 = b.get_global_rect().get_center()
			for down in [true, false]:
				var e := InputEventMouseButton.new()
				e.button_index = MOUSE_BUTTON_LEFT
				e.pressed = down
				e.position = c
				e.global_position = c
				if down:
					e.button_mask = MOUSE_BUTTON_MASK_LEFT
				root.push_input(e, true)
				await process_frame
			await idle(10)
			return
	print("   no visible button %s" % txt)


func click(p: Vector2, shift := false) -> void:
	var hm := InputEventMouseMotion.new()
	hm.position = p
	hm.global_position = p
	root.push_input(hm, true)
	await process_frame
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		e.shift_pressed = shift
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e, true)
		await process_frame
	await idle(3)


func nv() -> int:
	return kmed.mesh.verts.size()


func nf() -> int:
	return kmed.mesh.face_count()


func vw(i: int) -> Vector3:
	return kmed.view._to_world(i)


func face_center(fi: int) -> Vector3:
	var f: PackedInt32Array = kmed.mesh.faces[fi]
	var c := Vector3.ZERO
	for vi in f:
		c += vw(vi)
	return c / float(f.size())


func on_screen(p: Vector2) -> bool:
	return m.get_viewport().get_visible_rect().has_point(p)


func scr(wp: Vector3) -> Vector2:
	return m.cam.unproject_position(wp)


func pick_face() -> int:
	var best := -1
	var bd := 0.0
	var cam_pos: Vector3 = m.cam.global_position
	for fi in nf():
		var c: Vector3 = face_center(fi)
		if m.cam.is_position_behind(c) or not on_screen(scr(c)):
			continue
		var n: Vector3 = (kmed.view.global_transform.basis * kmed.mesh.face_normals[fi]).normalized()
		var d: float = n.dot((cam_pos - c).normalized())
		if d > bd:
			bd = d
			best = fi
	return best


## the visible edge nearest the camera with ok(a, b) true; [a, b, screen point] or []
func pick_edge(ok_fn: Callable) -> Array:
	var best := []
	var bdist := 1e9
	var cam_pos: Vector3 = m.cam.global_position
	for fi in nf():
		var f: PackedInt32Array = kmed.mesh.faces[fi]
		for i in f.size():
			var a: int = f[i]
			var b: int = f[(i + 1) % f.size()]
			var mid: Vector3 = (vw(a) + vw(b)) * 0.5
			if m.cam.is_position_behind(mid) or not on_screen(scr(mid)):
				continue
			if not ok_fn.call(a, b):
				continue
			var dd: float = cam_pos.distance_to(mid)
			if dd < bdist:
				bdist = dd
				best = [a, b, scr(mid)]
	return best


func edge_uses(a: int, b: int) -> int:
	var c := 0
	for f in kmed.mesh.faces:
		var n: int = f.size()
		for i in n:
			var p: int = f[i]
			var q: int = f[(i + 1) % n]
			if (p == a and q == b) or (p == b and q == a):
				c += 1
	return c


## undirected edges used by one face only (the open border of a hole)
func open_edges() -> int:
	var cnt := {}
	for f in kmed.mesh.faces:
		var n: int = f.size()
		for i in n:
			var a: int = f[i]
			var b: int = f[(i + 1) % n]
			var k := Vector2i(mini(a, b), maxi(a, b))
			cnt[k] = int(cnt.get(k, 0)) + 1
	var c := 0
	for k in cnt:
		if cnt[k] == 1:
			c += 1
	return c


## directed edges used twice: two faces that wind the same way across an edge
func same_way_edges() -> int:
	var cnt := {}
	for f in kmed.mesh.faces:
		var n: int = f.size()
		for i in n:
			var k := Vector2i(f[i], f[(i + 1) % n])
			cnt[k] = int(cnt.get(k, 0)) + 1
	var c := 0
	for k in cnt:
		if cnt[k] > 1:
			c += 1
	return c


## true when every face from index f0 on has its Newell normal pointing away from the mesh centre
func new_faces_out(f0: int) -> bool:
	var mc := Vector3.ZERO
	for p in kmed.mesh.verts:
		mc += p
	mc /= maxf(1.0, float(nv()))
	var all_out := true
	for fi in range(f0, nf()):
		var f: PackedInt32Array = kmed.mesh.faces[fi]
		var nrm := Vector3.ZERO
		var fc := Vector3.ZERO
		for i in f.size():
			var p: Vector3 = kmed.mesh.verts[f[i]]
			var q: Vector3 = kmed.mesh.verts[f[(i + 1) % f.size()]]
			nrm += Vector3((p.y - q.y) * (p.z + q.z), (p.z - q.z) * (p.x + q.x), (p.x - q.x) * (p.y + q.y))
			fc += p
		fc /= float(f.size())
		if nrm.dot(fc - mc) <= 0.0:
			all_out = false
	return all_out


func fresh() -> void:
	if kmed != null and kmed.on:
		await key(KEY_ESCAPE)
	await button("MODEL")
	await button("Test cube")
	await idle(10)
	kmed = m.kmed


## the test cube with one visible face deleted; edge mode after. Returns the face count after the delete.
func make_hole() -> int:
	await key(KEY_3)
	var fd := pick_face()
	if fd >= 0:
		await click(scr(face_center(fd)))
		await key(KEY_DELETE)
	await key(KEY_2)
	return nf()


func is_rim(a: int, b: int) -> bool:
	return edge_uses(a, b) == 1


## the closing checks for one fill: the hole closed, outward normal, one undo step, undo gives the hole back
func check_close(tag: String, f_hole: int, steps0: int) -> void:
	var f1 := nf()
	var steps: int = int(kmed.undo.steps.size()) - steps0
	print("   %s: faces %d -> %d, open edges %d, same-way edges %d, new face normal out %s, undo steps +%d" % [tag, f_hole, f1, open_edges(), same_way_edges(), str(new_faces_out(f_hole)), steps])
	ok(f1 == f_hole + 1 and open_edges() == 0 and same_way_edges() == 0 and new_faces_out(f_hole), "%s: the hole closes with one new face (faces %d -> %d, 0 open edges, normal out)" % [tag, f_hole, f1])
	ok(steps == 1, "%s: one undo step (steps +%d)" % [tag, steps])
	await key(KEY_Z, true)
	ok(nf() == f_hole and open_edges() == 4, "%s: Ctrl+Z gives the hole back (faces %d, open edges %d)" % [tag, nf(), open_edges()])
	await idle(3)


func _init() -> void:
	get_root().size = Vector2i(1280, 720)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(10)
	if m.easy.on:
		await button("Switch to Expert")
		await idle(10)

	# ---- A (a): one rim edge selected, Alt+F
	await fresh()
	if kmed != null and kmed.on:
		var f_hole := await make_hole()
		var e: Array = pick_edge(func(a: int, b: int) -> bool: return is_rim(a, b))
		if not e.is_empty():
			await click(e[2])
		print("   (a) rim edge picked: %s; selected edges %d, verts %d" % [str(not e.is_empty()), kmed.sel.edges.size(), kmed.sel.verts.size()])
		var steps0: int = kmed.undo.steps.size()
		await key(KEY_F, false, false, true)
		print("   status: %s" % str(m.ui_status.text).left(120))
		await check_close("(a) rim edge + Alt+F", f_hole, steps0)
	else:
		ok(false, "(a) the test cube opened")

	# ---- (b): the 4 rim edges selected, F
	await fresh()
	if kmed != null and kmed.on:
		var f_hole := await make_hole()
		var picked: Array = []
		for i in 4:
			var pk: Array = picked.duplicate()
			var e: Array = pick_edge(func(a: int, b: int) -> bool:
				if not is_rim(a, b):
					return false
				for p in pk:
					if (p.x == a and p.y == b) or (p.x == b and p.y == a):
						return false
				return true)
			if e.is_empty():
				break
			picked.append(Vector2i(e[0], e[1]))
			await click(e[2], i > 0)
		print("   (b) rim edges picked %d; selected edges %d" % [picked.size(), kmed.sel.edges.size()])
		var steps0: int = kmed.undo.steps.size()
		await key(KEY_F)
		print("   status: %s" % str(m.ui_status.text).left(120))
		await check_close("(b) 4 rim edges + F", f_hole, steps0)
	else:
		ok(false, "(b) the test cube opened")

	# ---- (c): nothing selected, Alt+F
	await fresh()
	if kmed != null and kmed.on:
		var f_hole := await make_hole()
		print("   (c) selected %d after the delete (nothing picked)" % kmed.sel.count())
		var steps0: int = kmed.undo.steps.size()
		await key(KEY_F, false, false, true)
		print("   status: %s" % str(m.ui_status.text).left(120))
		await check_close("(c) nothing selected + Alt+F", f_hole, steps0)
	else:
		ok(false, "(c) the test cube opened")

	# ---- B (e): F2, type a name, Enter, then F3
	await fresh()
	if kmed != null and kmed.on:
		await key(KEY_F2)
		await typed("walk5")
		await key(KEY_ENTER)
		var nm := str(m.ui_scene_name.text)
		var fo := m.get_viewport().gui_get_focus_owner()
		print("   (e) name box '%s', focus owner %s" % [nm, str(fo.name) if fo != null else "none"])
		ok(nm == "walk5", "(e) F2, type a name, Enter: the name is set (%s)" % nm)
		await key(KEY_F3)
		ok(m.ui_cmd != null and m.ui_cmd.visible, "(e) then F3 opens the search box")
		m.ui_cmd.close()
		await idle(3)
	else:
		ok(false, "(e) the test cube opened")

	# ---- B (f): F2, Esc, then F3
	await fresh()
	if kmed != null and kmed.on:
		await key(KEY_F2)
		await key(KEY_ESCAPE)
		await key(KEY_F3)
		ok(m.ui_cmd != null and m.ui_cmd.visible, "(f) F2, Esc, then F3 opens the search box")
		m.ui_cmd.close()
		await idle(3)
	else:
		ok(false, "(f) the test cube opened")

	print("fails: %d" % fails)
	quit(1 if fails > 0 else 0)
