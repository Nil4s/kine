extends SceneTree
## s193 Fit to an object (Friday plan 193). Real clicks at 1280 x 720 from the real start screen, on the live Easy Part: Parts > Boards > Fit to an object.
## Test scans are generated here: a 60 x 30 x 15 mm box with 3 mm rounded edges, written as .obj at 1/1000 scale (the units fix), with 0.06 mm
## gaussian jitter on every vertex (a phone-like noisy copy), and tumbled on its side (the auto-orient).
##   1 the window opens from the Boards page; a tumbled scan lies flat (60 x 30 x 15, shortest axis up, low corner on the floor)
##   2 the 1/1000 file reads 0.06 mm; typing 60 for Length makes it 60.0 x 30.0 x 15.0 within 0.3 mm (clean and noisy), measured from the shown mesh
##   3 Holder: one solid, one undo step; the pocket is >= scan + clearance and <= scan + clearance + 0.5 mm at 8+ ray casts from the built mesh;
##     the scan sits below the holder's top; Depth slider changes the block height; Undo takes it off
##   4 Case: two solids with a pocket each, wall = slider value within 0.3 mm (rays), the halves meet, 150 random rays from the scan cannot leave
##     (control: the open-top holder DOES let rays out), one undo step
## shots: C:/Temp/claude/s193/

const SHOT_DIR := "C:/Temp/claude/s193"
const DIRT := "user://s193_test"

var fails := 0
var m: Node
var woff := Vector2.ZERO


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
	await click_at(c.get_global_rect().get_center() + woff)


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_slider(s: HSlider, v: float) -> void:
	var r := s.get_global_rect()
	r.position += woff
	var gw := _grab_w(s)
	var y := r.get_center().y
	var p0 := Vector2(r.position.x + gw * 0.5 + (s.value - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw), y)
	var x1 := r.position.x + gw * 0.5 + (v - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw)
	await ev_move(p0, false)
	await ev_mouse(p0, true)
	for i in range(1, 25):
		await ev_move(Vector2(lerpf(p0.x, x1, i / 24.0), y))
	await ev_mouse(Vector2(x1, y), false)
	await idle(3)


func _grab_w(sl: HSlider) -> float:
	var g := sl.get_theme_icon("grabber")
	return float(g.get_width()) if g != null else 16.0


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT_DIR, nm])


func pu():
	return m.bld.part


func ep():
	return pu().ep


## a rounded box (half sizes h, edge radius r), mm, triangles outward
func rbox(hx: float, hy: float, hz: float, r: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var half := Vector3(hx, hy, hz)
	var inner := half - Vector3(r, r, r)
	for a in 3:
		for sgn in [-1.0, 1.0]:
			var b := (a + 1) % 3
			var c := (a + 2) % 3
			var lb := bp(half[b], r)
			var lc := bp(half[c], r)
			for i in lb.size() - 1:
				for j in lc.size() - 1:
					var q: Array = []
					for dd in [[0, 0], [1, 0], [1, 1], [0, 1]]:
						var v := Vector3.ZERO
						v[a] = sgn * half[a]
						v[b] = lb[i + dd[0]]
						v[c] = lc[j + dd[1]]
						var pin := Vector3(clampf(v.x, -inner.x, inner.x), clampf(v.y, -inner.y, inner.y), clampf(v.z, -inner.z, inner.z))
						var d := v - pin
						q.append(pin + d.normalized() * r if d.length() > 1e-9 else v)
					for tri in [[0, 1, 2], [0, 2, 3]]:
						var p0: Vector3 = q[tri[0]]
						var p1: Vector3 = q[tri[1]]
						var p2: Vector3 = q[tri[2]]
						var nrm := (p1 - p0).cross(p2 - p0)
						if nrm.dot((p0 + p1 + p2) / 3.0) < 0.0:
							var t := p1
							p1 = p2
							p2 = t
						out.append(p0)
						out.append(p1)
						out.append(p2)
	return out


func bp(h: float, r: float) -> Array:
	return [-h, -h + r * 0.25, -h + r * 0.5, -h + r * 0.75, -h + r, h - r, h - r * 0.75, h - r * 0.5, h - r * 0.25, h]


## an indexed .obj like a scanning app writes it: one line per distinct vertex, shared by the triangles around it
func write_obj(path: String, tris: PackedVector3Array, k: float, sigma := 0.0, seed_ := 1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var ix := {}
	var lines := PackedStringArray()
	var faces := PackedStringArray()
	var ids: Array = []
	for v in tris:
		var key := Vector3i((v * 1000.0).round())
		if not ix.has(key):
			var w := v + (Vector3(rng.randfn(0.0, sigma), rng.randfn(0.0, sigma), rng.randfn(0.0, sigma)) if sigma > 0.0 else Vector3.ZERO)
			ix[key] = ix.size() + 1
			lines.append("v %.7f %.7f %.7f" % [w.x * k, w.y * k, w.z * k])
		ids.append(ix[key])
	for i in tris.size() / 3:
		faces.append("f %d %d %d" % [ids[3 * i], ids[3 * i + 1], ids[3 * i + 2]])
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("
".join(lines) + "
" + "
".join(faces) + "
")
	f.close()


func jitter(tris: PackedVector3Array, sigma: float, seed_: int) -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var out := tris.duplicate()
	for i in out.size():
		out[i] += Vector3(rng.randfn(0.0, sigma), rng.randfn(0.0, sigma), rng.randfn(0.0, sigma))
	return out


func tumble(tris: PackedVector3Array) -> PackedVector3Array:
	var bs := Basis(Vector3(0.3, 0.8, 0.5).normalized(), 1.9)
	var out := tris.duplicate()
	for i in out.size():
		out[i] = bs * out[i] + Vector3(5, -7, 3)
	return out


## triangles of a mesh node in world metres
func node_tris(mi: MeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	if mi == null or mi.mesh == null:
		return out
	var t := mi.global_transform
	for s in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix = arr[Mesh.ARRAY_INDEX]
		if ix == null or (ix as PackedInt32Array).is_empty():
			for v in vs:
				out.append(t * v)
		else:
			for i in ix:
				out.append(t * vs[i])
	return out


func tris_box(t: PackedVector3Array) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for v in t:
		lo = lo.min(v)
		hi = hi.max(v)
	return AABB(lo, hi - lo)


## the distances along a ray (metres) at which it crosses the triangles, sorted, repeats within 1 um dropped
func hits(t: PackedVector3Array, o: Vector3, d: Vector3) -> Array:
	var ts: Array = []
	# Moeller-Trumbore in millimetres (Godot's Geometry3D version drops a triangle whose determinant is under 1e-5, and in metres every small one is)
	var om := o * 1000.0
	for i in t.size() / 3:
		var a := t[3 * i] * 1000.0
		var e1 := t[3 * i + 1] * 1000.0 - a
		var e2 := t[3 * i + 2] * 1000.0 - a
		var pv := d.cross(e2)
		var det := e1.dot(pv)
		if absf(det) < 1e-12:
			continue
		var inv := 1.0 / det
		var tv := om - a
		var u := tv.dot(pv) * inv
		if u < -1e-9 or u > 1.0 + 1e-9:
			continue
		var qv := tv.cross(e1)
		var v := d.dot(qv) * inv
		if v < -1e-9 or u + v > 1.0 + 1e-9:
			continue
		var tt := e2.dot(qv) * inv
		if tt > 1e-9:
			ts.append(tt / 1000.0)
	ts.sort()
	var out: Array = []
	for x in ts:
		if out.is_empty() or float(x) - float(out[out.size() - 1]) > 1e-6:
			out.append(x)
	return out


func fit():
	return root.find_child("easypart_fit_row", true, false)


func win() -> Window:
	return root.find_child("easypart_fit_window", true, false) as Window


func set_woff() -> void:
	var w := win()
	if w != null and w.visible:
		woff = Vector2(w.position)
	else:
		woff = Vector2.ZERO


func wc(nm: String) -> Control:
	return root.find_child(nm, true, false) as Control


func load_scan(path: String) -> void:
	wc("easypart_fit_path").text = ProjectSettings.globalize_path(path)
	await click_ctl(wc("easypart_fit_open"))
	await idle(5)


func ensure_win() -> void:
	if win() == null or not win().visible:
		woff = Vector2.ZERO
		var obn := wc("easypart_fit_open_btn")
		print("note: reopening the window; button visible in tree: ", obn.is_visible_in_tree(), " rect ", obn.get_global_rect())
		if obn.is_visible_in_tree():
			await click_ctl(obn)
		await idle(5)
		if win() == null or not win().visible:
			print("note: the button press did not open the window; calling open_window()")
			fit().open_window()
			await idle(5)
	set_woff()


func set_true(side: int, mm: float) -> void:
	var sp: OptionButton = wc("easypart_fit_side")
	sp.select(side)
	wc("easypart_fit_true").text = str(mm)
	await click_ctl(wc("easypart_fit_apply"))
	await idle(5)


func scan_size() -> Vector3:
	var s := tris_box(node_tris(fit().scan_mi)).size / Part.MM
	return Vector3(s.x, s.z, s.y)   # world y is up: length, width, height


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
	await idle(30)

	# the scans
	var box := rbox(30.0, 15.0, 7.5, 3.0)
	var p_clean := DIRT + "/box_k.obj"
	var p_noisy := DIRT + "/box_noisy_k.obj"
	var p_tumb := DIRT + "/box_tumbled.obj"
	write_obj(ProjectSettings.globalize_path(p_clean), box, 0.001)
	write_obj(ProjectSettings.globalize_path(p_noisy), box, 0.001, 0.06, 7)
	write_obj(ProjectSettings.globalize_path(p_tumb), tumble(box), 1.0)

	# 1 the button on the Boards page opens the window
	await click_ctl(wc("easypart_chip_parts"))
	await click_ctl(wc("easypart_lib_Boards"))
	var ob: Button = wc("easypart_fit_open_btn") as Button
	ok(ob != null and ob.is_visible_in_tree(), "1a the Fit to an object button shows on Parts > Boards")
	await click_ctl(ob)
	await idle(5)
	set_woff()
	ok(win() != null and win().visible, "1b the Fit to an object window opens")
	#print("DBG woff ", woff, " win ", win().position, " embedded ", win().is_embedded(), " rect ", wc("easypart_fit_open").get_global_rect(), " title_h ", win().get_theme_constant("title_height", "Window"))
	await load_scan(p_tumb)
	var sz1 := scan_size()
	var bx1 := tris_box(node_tris(fit().scan_mi))
	ok(absf(sz1.x - 60.0) < 0.3 and absf(sz1.y - 30.0) < 0.3 and absf(sz1.z - 15.0) < 0.3, "1c a tumbled scan lies flat: %.2f x %.2f x %.2f mm (60 x 30 x 15, shortest side up)" % [sz1.x, sz1.y, sz1.z])
	ok(absf(bx1.position.y) < 1e-6 and absf(bx1.position.x) < 1e-6, "1d its low corner sits on the floor (y %.6f, x %.6f)" % [bx1.position.y, bx1.position.x])

	# 2 the units fix
	await load_scan(p_clean)
	var sz2 := scan_size()
	ok(sz2.x < 0.1 and sz2.x > 0.02, "2a the 1/1000 file reads %.3f x %.3f x %.3f mm before the fix" % [sz2.x, sz2.y, sz2.z])
	ok((wc("easypart_fit_read") as Label).text.find("metres") >= 0, "2b the panel says it is probably metres: %s" % (wc("easypart_fit_read") as Label).text.left(100))
	await set_true(0, 60.0)
	var sz3 := scan_size()
	ok(absf(sz3.x - 60.0) <= 0.3 and absf(sz3.y - 30.0) <= 0.3 and absf(sz3.z - 15.0) <= 0.3, "2c after typing 60 the scan measures %.2f x %.2f x %.2f mm (60 x 30 x 15 within 0.3)" % [sz3.x, sz3.y, sz3.z])
	await shot("01_scan_on_floor")
	await load_scan(p_noisy)
	await set_true(0, 60.0)
	var sz4 := scan_size()
	ok(absf(sz4.x - 60.0) <= 0.3 and absf(sz4.y - 30.0) <= 0.3 and absf(sz4.z - 15.0) <= 0.3, "2d the noisy scan (0.06 mm jitter) measures %.2f x %.2f x %.2f mm (within 0.3)" % [sz4.x, sz4.y, sz4.z])
	await load_scan(p_clean)
	await set_true(0, 60.0)

	# 3 Holder
	var clr: float = (wc("easypart_fit_clear") as HSlider).value
	var u0: int = m.undo.size()
	await ensure_win()
	await click_ctl(wc("easypart_fit_holder"))
	await click_ctl(wc("easypart_fit_build"))
	await idle(20)
	var errs: Dictionary = pu().res.get("errors", {})
	ok(int(pu().res.get("bodies", 0)) == 1 and errs.is_empty() and m.undo.size() == u0 + 1, "3a Holder: one solid, no errors, one undo step (bodies %s, undo %d -> %d, %s) msg: %s" % [pu().res.get("bodies", 0), u0, m.undo.size(), errs, (wc("easypart_fit_msg") as Label).text])
	var scan_t := node_tris(fit().scan_mi)
	var part_t := node_tris(pu().part_mesh)
	var sb := tris_box(scan_t)
	var pb := tris_box(part_t)
	var c := sb.get_center()
	var specs: Array = [
		[c, Vector3.RIGHT], [c, Vector3.LEFT], [c, Vector3(0, 0, 1)], [c, Vector3(0, 0, -1)], [c, Vector3.DOWN],
		[c + Vector3(0.012, 0, 0), Vector3(0, 0, 1)], [c + Vector3(-0.012, 0, 0), Vector3(0, 0, -1)],
		[c + Vector3(0, 0.002, 0.006), Vector3.RIGHT], [c + Vector3(0, -0.002, -0.006), Vector3.LEFT], [c + Vector3(0.02, 0, 0.005), Vector3.DOWN]]
	var gmin := 1e9
	var gmax := -1e9
	var n_ok := 0
	for sp in specs:
		var o: Vector3 = sp[0]
		var d: Vector3 = sp[1]
		var hs := hits(scan_t, o, d)
		var hp := hits(part_t, o, d)
		if hs.is_empty() or hp.is_empty():
			continue
		var g := (float(hp[0]) - float(hs[hs.size() - 1])) / Part.MM
		gmin = minf(gmin, g)
		gmax = maxf(gmax, g)
		n_ok += 1
	ok(n_ok >= 6, "3b %d ray casts hit both the scan and the pocket" % n_ok)
	ok(gmin >= clr - 0.02 and gmax <= clr + 0.5, "3c pocket - scan gap %.3f .. %.3f mm over %d rays (clearance %.2f; bar >= clearance, <= clearance + 0.5)" % [gmin, gmax, n_ok, clr])
	ok(sb.end.y <= pb.end.y + 1e-7, "3d the scan sits below the holder's top (scan top %.3f, holder top %.3f mm)" % [sb.end.y / Part.MM, pb.end.y / Part.MM])
	var esc_holder := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var rays: Array = []
	for i in 150:
		var vi := rng.randi() % scan_t.size()
		var dir := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		rays.append([scan_t[vi] * 0.97 + c * 0.03, dir])
	for r in rays:
		if hits(part_t, r[0], r[1]).is_empty():
			esc_holder += 1
	ok(esc_holder > 0, "3e control: the open-top holder lets %d of 150 random rays out (the enclosure check can fail)" % esc_holder)
	await shot("02_holder")
	await ensure_win()
	# depth slider
	var wall_h := float((wc("easypart_fit_wall") as HSlider).value)
	var dsl: HSlider = wc("easypart_fit_depth") as HSlider
	var dmax := dsl.value
	await drag_slider(dsl, 8.0)
	var dval := dsl.value
	var u1: int = m.undo.size()
	await ensure_win()
	await click_ctl(wc("easypart_fit_build"))
	await idle(20)
	var pb2 := tris_box(node_tris(pu().part_mesh))
	ok(m.undo.size() == u1 + 1 and absf(pb2.size.y / Part.MM - (wall_h + dval)) <= 0.1, "3f Depth slider %.1f (was %.1f): holder is %.2f mm tall = wall %.1f + depth, one undo step" % [dval, dmax, pb2.size.y / Part.MM, wall_h])
	m._undo()
	await idle(10)
	var pb3 := tris_box(node_tris(pu().part_mesh))
	ok(absf(pb3.size.y - pb.size.y) < 1e-6, "3g Undo takes the shallow holder back to the deep one (%.2f mm)" % (pb3.size.y / Part.MM))

	# 4 Case
	await ensure_win()
	await click_ctl(wc("easypart_fit_case"))
	await drag_slider(wc("easypart_fit_wall") as HSlider, 2.5)
	var wallv: float = (wc("easypart_fit_wall") as HSlider).value
	var u2: int = m.undo.size()
	await click_ctl(wc("easypart_fit_build"))
	await idle(30)
	errs = pu().res.get("errors", {})
	var vols: Array = pu().res.get("volumes", [])
	ok(int(pu().res.get("bodies", 0)) == 2 and errs.is_empty() and m.undo.size() == u2 + 1 and vols.size() == 2 and float(vols[0]) > 0.0 and float(vols[1]) > 0.0,
		"4a Case: two solids, no errors, one undo step (bodies %s, volumes %s, undo +%d, %s)" % [pu().res.get("bodies", 0), vols, m.undo.size() - u2, errs])
	scan_t = node_tris(fit().scan_mi)
	part_t = node_tris(pu().part_mesh)
	sb = tris_box(scan_t)
	c = sb.get_center()
	var h := sb.size.y
	var w_specs: Array = []
	for fy in [0.3, 0.7]:
		var oy: float = sb.position.y + h * fy
		var oc := Vector3(c.x, oy, c.z)
		w_specs.append([oc, Vector3.RIGHT])
		w_specs.append([oc, Vector3.LEFT])
		w_specs.append([oc, Vector3(0, 0, 1)])
		w_specs.append([oc, Vector3(0, 0, -1)])
	w_specs.append([c, Vector3.DOWN])
	w_specs.append([c, Vector3.UP])
	var wmin := 1e9
	var wmax := -1e9
	var wn := 0
	for sp in w_specs:
		var hp2 := hits(part_t, sp[0], sp[1])
		if hp2.size() >= 2:
			var wl := (float(hp2[1]) - float(hp2[0])) / Part.MM
			wmin = minf(wmin, wl)
			wmax = maxf(wmax, wl)
			wn += 1
	ok(wn == w_specs.size() and absf(wmin - wallv) <= 0.3 and absf(wmax - wallv) <= 0.3, "4b wall thickness %.3f .. %.3f mm over %d of %d rays through both halves, slider %.1f (within 0.3)" % [wmin, wmax, wn, w_specs.size(), wallv])
	var pm: ArrayMesh = pu().part_mesh.mesh
	var v0: PackedVector3Array = pm.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var v1: PackedVector3Array = pm.surface_get_arrays(1)[Mesh.ARRAY_VERTEX] if pm.get_surface_count() > 1 else PackedVector3Array()
	var b0 := tris_box(v0)
	var b1 := tris_box(v1)
	ok(v1.size() > 0 and absf(b0.end.y - b1.position.y) < 1e-6, "4c the halves meet: one top %.3f, other bottom %.3f mm (surfaces %d)" % [b0.end.y / Part.MM, b1.position.y / Part.MM, pm.get_surface_count()])
	rays = []
	for i in 150:
		var vj := rng.randi() % scan_t.size()
		rays.append([scan_t[vj] * 0.97 + c * 0.03, Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()])
	var esc_case := 0
	for r in rays:
		if hits(part_t, r[0], r[1]).is_empty():
			esc_case += 1

	ok(esc_case == 0, "4d the two halves enclose the scan: %d of 150 random rays from the scan get out" % esc_case)
	await idle(90)
	await shot("03_case")
	m._undo()
	await idle(10)
	ok(m.undo.size() == u2 and int(pu().res.get("bodies", 0)) == 1, "4e Undo takes the case off in one step (bodies %s)" % pu().res.get("bodies", 0))

	# 5 the noisy scan builds too
	await load_scan(p_noisy)
	await set_true(0, 60.0)
	await ensure_win()
	await click_ctl(wc("easypart_fit_holder"))
	await click_ctl(wc("easypart_fit_build"))
	await idle(20)
	scan_t = node_tris(fit().scan_mi)
	part_t = node_tris(pu().part_mesh)
	sb = tris_box(scan_t)
	c = sb.get_center()
	var nmin := 1e9
	for sp in [[c, Vector3.RIGHT], [c, Vector3.LEFT], [c, Vector3(0, 0, 1)], [c, Vector3(0, 0, -1)], [c, Vector3.DOWN]]:
		var hs2 := hits(scan_t, sp[0], sp[1])
		var hp3 := hits(part_t, sp[0], sp[1])
		if not hs2.is_empty() and not hp3.is_empty():
			nmin = minf(nmin, (float(hp3[0]) - float(hs2[hs2.size() - 1])) / Part.MM)
	ok(int(pu().res.get("bodies", 0)) == 1 and (pu().res.get("errors", {}) as Dictionary).is_empty() and nmin >= clr - 0.02, "5 the noisy scan builds a holder; pocket gap >= clearance on 5 rays (min %.3f mm)" % nmin)
	print("s193: %d fail" % fails)
	quit(1 if fails > 0 else 0)
