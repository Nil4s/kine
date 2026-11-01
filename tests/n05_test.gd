extends SceneTree
## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/n05_test.gd     (N05: three speed-ups, each measured before/after)
## (A) the Export dialog's slicer lookup (SlicerSend.detect_system, ~2 s) is made once per app run (cache + worker-thread prewarm), not per open.
##     BAR: dialog open, second and later, < 300 ms median of 5; the cached list equals the uncached list.
## (B) AnyGrip.MeshField.build_banded answers the same triangles at the same cell from the last result (Remesh's correction loop, then apply).
##     BAR: the remeshed mesh is identical (vertex count equal, positions within 1e-6; faces equal).
## (C) build_banded's hot loop in C++ (native/src/kine_field_native.cpp, door scripts/any_grip_field_native.gd; KINE_NO_NATIVE=1 = GDScript).
##     BAR: field within 1e-5 relative, remesh vertex count identical, >= 5x on build_banded; Remesh lighter press total A+B+C vs origin, median of 3.
## The sculpt sphere (30 cm, 24 splits = 6912 triangles) is the profile's mesh.
var fails := 0
var m: Node
const RUNS := 5


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


static func med(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() / 2])


func tm(c: Callable, n := RUNS) -> Array:
	var out := []
	for i in n:
		var t := Time.get_ticks_usec()
		c.call()
		out.append((Time.get_ticks_usec() - t) / 1000.0)
	return out


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
	await idle(2)


func pick_part(t: String) -> void:
	var chip := root.find_child("easypart_chip_" + t, true, false) as Button
	if chip != null and chip.is_visible_in_tree():
		await click_ctl(chip)
		await idle(3)
		return
	await click_ctl(root.find_child("easypart_more_examples", true, false) as Control)
	await idle(10)
	var bc: BuildChoose = m.build_choose
	await click_ctl(bc.btns["template"]["easy"])
	await idle(4)
	bc._starters.id_pressed.emit(1000 + PartTemplates.ORDER.find(t))
	await idle(20)
	var sc := root.find_child("easypart_panel_scroll", true, false) as ScrollContainer
	if sc != null:
		sc.scroll_vertical = 0
		await idle(3)



func tris_of(mesh: KMesh) -> PackedVector3Array:
	var tris := PackedVector3Array()
	for f in mesh.faces:
		var fa := f as PackedInt32Array
		for k in range(1, fa.size() - 1):
			tris.append(mesh.verts[fa[0]])
			tris.append(mesh.verts[fa[k]])
			tris.append(mesh.verts[fa[k + 1]])
	return tris


## remesh_by(-1) step by step, with the same calls (loop of up to 2 remeshes + apply). wipe = forget the field before every call (= origin)
func press(sph: KMesh, wipe: bool) -> Dictionary:
	var mesh := KMeshDecimate.copy(sph)
	mesh.rebuild()
	KMeshMask.ensure(mesh)
	var undo := KMeshUndo.new()
	AnyGrip.MeshField._last = null   # never reuse across presses
	var h0 := AnyGrip.MeshField.hits
	var t0 := Time.get_ticks_usec()
	var target := maxf(float(mesh.triangle_count()) * 0.5, 12.0)
	var area := 0.0
	for f in mesh.faces:
		var fa := f as PackedInt32Array
		for k in range(1, fa.size() - 1):
			area += (mesh.verts[fa[k]] - mesh.verts[fa[0]]).cross(mesh.verts[fa[k + 1]] - mesh.verts[fa[0]]).length() * 0.5
	var h := sqrt(3.0 * area / target)
	var calls := 0
	for _i in 2:
		if wipe:
			AnyGrip.MeshField._last = null
		var t := KMeshVoxelRemesh.remesh(mesh, h)
		calls += 1
		if not t["ok"]:
			break
		var got := float((t["mesh"] as KMesh).triangle_count())
		if absf(got / target - 1.0) < 0.03:
			break
		h *= sqrt(got / target)
	if wipe:
		AnyGrip.MeshField._last = null
	calls += 1
	var r := KMeshVoxelRemesh.apply(mesh, h, undo)
	return {"ms": (Time.get_ticks_usec() - t0) / 1000.0, "mesh": mesh, "ok": r["ok"], "calls": calls, "hits": AnyGrip.MeshField.hits - h0, "h": h}


func same_mesh(a: KMesh, b: KMesh) -> Vector2:   # (equal 1/0, max position diff)
	var eq := 1.0 if a.verts.size() == b.verts.size() and a.faces.size() == b.faces.size() else 0.0
	var worst := 0.0
	if eq == 1.0:
		for i in a.verts.size():
			worst = maxf(worst, (a.verts[i] - b.verts[i]).length())
		for i in a.faces.size():
			if a.faces[i] != b.faces[i]:
				eq = 0.0
				break
	return Vector2(eq, worst)


## open the dialog and land on 3D printing (the part may not count as 'free part on screen' here, so pick the target the way the user does)
func open_print() -> void:
	var ui: ExportDialog = m.export_ui
	ui.open()
	for i in ui.ui_target.item_count:
		if ui.ui_target.get_item_text(i).contains("3D printing"):
			if ui.ui_target.selected != i:
				ui.ui_target.select(i)
				ui._fill_formats()
				ui._refresh()
			break


func _init() -> void:
	var have := NativeExt.ensure("kine_native", "KineFieldNative")
	print("n05: KineFieldNative loaded: %s; KINE_NO_NATIVE='%s'; native_on=%s" % [str(have), OS.get_environment("KINE_NO_NATIVE"), str(AnyGrip.MeshField.native_on)])
	var env_native: bool = AnyGrip.MeshField.native_on
	var sph := KMeshSculptUI.make_sphere()
	print("n05: sculpt sphere %d verts, %d triangles" % [sph.verts.size(), sph.triangle_count()])
	var tris := tris_of(sph)
	var area := 0.0
	for t in tris.size() / 3:
		area += (tris[3 * t + 1] - tris[3 * t]).cross(tris[3 * t + 2] - tris[3 * t]).length() * 0.5
	var cell := sqrt(3.0 * area / (sph.triangle_count() * 0.5))

	# ============================================== (C) build_banded, GDScript vs native, field equality + timing
	AnyGrip.MeshField.native_on = false
	AnyGrip.MeshField._last = null
	var fg := AnyGrip.MeshField.build_banded(tris, cell)
	var t_gd := []
	for i in RUNS:
		AnyGrip.MeshField._last = null
		var t0 := Time.get_ticks_usec()
		AnyGrip.MeshField.build_banded(tris, cell)
		t_gd.append((Time.get_ticks_usec() - t0) / 1000.0)
	print("n05: build_banded GDScript: median %.1f ms (grid %dx%dx%d)" % [med(t_gd), fg.nx, fg.ny, fg.nz])
	if have:
		AnyGrip.MeshField.native_on = true
		AnyGrip.MeshField._last = null
		var fn := AnyGrip.MeshField.build_banded(tris, cell)
		var t_nat := []
		for i in RUNS:
			AnyGrip.MeshField._last = null
			var t0 := Time.get_ticks_usec()
			AnyGrip.MeshField.build_banded(tris, cell)
			t_nat.append((Time.get_ticks_usec() - t0) / 1000.0)
		var f_speed := med(t_gd) / maxf(med(t_nat), 0.001)
		ok(fn.nx == fg.nx and fn.ny == fg.ny and fn.nz == fg.nz and fn.gmin == fg.gmin and fn.d.size() == fg.d.size(), "C grid identical (%dx%dx%d)" % [fn.nx, fn.ny, fn.nz])
		var worst_abs := 0.0
		var worst_rel := 0.0
		var sign_diff := 0
		for i in fg.d.size():
			var a := fg.d[i]
			var b := fn.d[i]
			worst_abs = maxf(worst_abs, absf(a - b))
			worst_rel = maxf(worst_rel, absf(a - b) / maxf(absf(a), 1e-3 * cell))
			if (a < 0.0) != (b < 0.0):
				sign_diff += 1
		print("n05: field max abs diff %s m, max rel diff (floor 1e-3 cell) %s, sign flips %d of %d" % [str(worst_abs), str(worst_rel), sign_diff, fg.d.size()])
		ok(worst_rel <= 1e-5 and sign_diff == 0, "C field native == GDScript within 1e-5 relative (max rel %s), no sign flip" % str(worst_rel))
		print("n05: TABLE build_banded: GDScript %.1f ms / native %.1f ms / x%.1f" % [med(t_gd), med(t_nat), f_speed])
		ok(f_speed >= 5.0, "C native >= 5x on build_banded (x%.1f)" % f_speed)
	else:
		print("SKIP C: no KineFieldNative (DLL missing)")

	# ============================================== (B) the cache: same inputs prove, mesh identical
	AnyGrip.MeshField.native_on = false
	var ra := press(sph, true)
	var rb := press(sph, false)
	print("n05: GDScript press: origin(wipe) %.0f ms with %d builds; cache %.0f ms with %d builds (%d answered from the last)" % [ra["ms"], ra["calls"], rb["ms"], rb["calls"] - rb["hits"], rb["hits"]])
	var sm := same_mesh(ra["mesh"], rb["mesh"])
	ok(ra["ok"] and rb["ok"] and sm.x == 1.0 and sm.y <= 1e-6, "B remeshed mesh identical with the cache (verts %d, faces equal, max pos diff %s)" % [(rb["mesh"] as KMesh).verts.size(), str(sm.y)])
	var f1 := AnyGrip.MeshField.build_banded(tris, cell)
	var h1 := AnyGrip.MeshField.hits
	var f2 := AnyGrip.MeshField.build_banded(tris, cell)
	ok(AnyGrip.MeshField.hits == h1 + 1 and f1.d == f2.d and f1 != f2, "B same triangles + cell: answered from the last, a copy (hash %d)" % hash(tris))
	var tris2 := tris.duplicate()
	tris2[0] += Vector3(0, 0, 1e-4)
	AnyGrip.MeshField.build_banded(tris2, cell)
	ok(AnyGrip.MeshField.hits == h1 + 1, "B one vertex moved 0.1 mm: NOT answered from the last")
	AnyGrip.MeshField.build_banded(tris2, cell * 1.01)
	ok(AnyGrip.MeshField.hits == h1 + 1, "B another cell: NOT answered from the last")

	# ============================================== the press, three times each: origin / B (GDScript) / B+C
	var origin := []
	var cached := []
	var full := []
	var rc: Dictionary = {}
	for i in 3:
		AnyGrip.MeshField.native_on = false
		origin.append(press(sph, true)["ms"])
		cached.append(press(sph, false)["ms"])
		if have:
			AnyGrip.MeshField.native_on = true
			rc = press(sph, false)
			full.append(rc["ms"])
	print("n05: TABLE Remesh lighter press (median of 3): origin %.0f ms / B only %.0f ms / B+C %.0f ms" % [med(origin), med(cached), med(full)])
	if have:
		var sm2 := same_mesh(ra["mesh"], rc["mesh"])
		ok(sm2.x == 1.0, "C remesh vertex count identical native vs GDScript (%d), faces equal; max pos diff %s" % [(rc["mesh"] as KMesh).verts.size(), str(sm2.y)])
		ok(sm2.y <= 1e-5, "C remeshed positions within 1e-5 (%s)" % str(sm2.y))
	AnyGrip.MeshField.native_on = env_native

	# ============================================== (A) the Export dialog open on 3D printing
	var f_det := SlicerSend.detect_system()
	var t_det := tm(func(): SlicerSend.detect_system(), 3)
	print("n05: SlicerSend.detect_system: median %.0f ms, found %s" % [med(t_det), str(f_det)])
	SlicerSend.forget()
	ok(SlicerSend.detect_cached() == f_det, "A cached list == uncached list (%d slicers)" % f_det.size())
	var t_c := tm(func(): SlicerSend.detect_cached(), 5)
	ok(med(t_c) < 1.0 and SlicerSend.detect_cached() == f_det, "A detect_cached() after the first: median %.3f ms" % med(t_c))
	SlicerSend.forget()
	ok(not SlicerSend.is_ready(), "A forget() = look again")
	SlicerSend.prewarm()
	var tw := Time.get_ticks_usec()
	var pw := SlicerSend.detect_cached()
	print("n05: prewarm then detect_cached waited %.0f ms" % ((Time.get_ticks_usec() - tw) / 1000.0))
	ok(pw == f_det, "A the worker-thread lookup gives the same list")

	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	if not Part.available():
		print("SKIP A dialog: no KineCAD DLL")
		print("n05: %d fail" % fails)
		quit(0)
		return
	var ss: StartScreen = m.start_screen
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://n05_test"))
	ss.dirs_override = ["user://n05_test"]
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	pu.set_on(false)
	m.S.part = {}
	await idle(8)
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var rec := Part.make("N05 block")
	var fs: Array = rec["features"]
	var sk := PartTemplates._sk(fs, "front", [PartTemplates._rect(Vector2(0, 0), Vector2(40, 25))])
	PartTemplates._ex(fs, sk, "extrude", 20.0, "new")
	rec["seq"] = fs.size()
	m.S.part = rec
	pu._rec_sig = ""
	pu.sync()
	await idle(10)
	if not pu.on:
		pu.set_on(true)
		m.S.part = rec
		pu._rec_sig = ""
		pu.sync()
		await idle(6)
	m.export_ui = ExportDialog.new(m)
	print("n05: part.on %s; targets: %s" % [str(pu.on), str((m.export_ui._tg() as Array).map(func(t): return t["id"]))])
	var origin_open := []
	for i in RUNS:
		SlicerSend.forget()   # origin: the dialog looked again on every open
		PrintCheck._cache_key = 0
		PrintCheck._cache = {}
		var to := Time.get_ticks_usec()
		open_print()
		origin_open.append((Time.get_ticks_usec() - to) / 1000.0)
		m.export_ui.dlg.hide()
		await idle(2)
	var after_open := []
	for i in RUNS + 1:
		PrintCheck._cache_key = 0
		PrintCheck._cache = {}
		var to := Time.get_ticks_usec()
		open_print()
		after_open.append((Time.get_ticks_usec() - to) / 1000.0)
		m.export_ui.dlg.hide()
		await idle(2)
	var first_open: float = after_open[0]
	after_open.remove_at(0)
	var warm_cache := []   # the print check cache warm too (the record unchanged)
	for i in RUNS:
		var to := Time.get_ticks_usec()
		open_print()
		warm_cache.append((Time.get_ticks_usec() - to) / 1000.0)
		m.export_ui.dlg.hide()
		await idle(2)
	print("n05: TABLE Export dialog open (3D printing, block): origin (lookup every open, print check cold) %.0f ms / after: first open %.0f ms, later opens %.0f ms (print check cold), %.0f ms (print check warm)" % [med(origin_open), first_open, med(after_open), med(warm_cache)])
	print("n05:   origin opens %s; later opens %s" % [str(origin_open), str(after_open)])
	ok(med(after_open) < 300.0, "A second and later opens of the Export dialog < 300 ms median of 5 (%.0f ms; origin %.0f ms)" % [med(after_open), med(origin_open)])
	ok(m.export_ui.slicers() == f_det, "A the dialog's slicer list == the uncached detect_system list")
	# the split of one open (3D printing), each block timed alone
	var ui: ExportDialog = m.export_ui
	var split := {}
	var pieces := {
		"open() whole (as the user presses Export)": func(): ui.open(),
		"text_of(print): format text + MeshExport.check_lines": func(): ui.text_of("print", 0),
		"MeshExport.check_lines alone (replay + tessellate + weld + PrintCheck)": func(): MeshExport.check_lines(m.S.part),
		"_refresh_slicer (slicers() + option list)": func(): ui._slicers_known = false; ui._refresh_slicer(),
		"SlicerSend.detect_cached()": func(): SlicerSend.detect_cached(),
		"_fill_formats()": func(): ui._fill_formats(),
		"_refresh() whole": func(): ui._refresh(),
	}
	for k in pieces:
		var tt := tm(pieces[k], 3)
		print("n05: SPLIT %-72s median %.1f ms" % [k, med(tt)])
	PrintCheck._cache_key = 0
	PrintCheck._cache = {}
	print("n05: SPLIT MeshExport.check_lines, print-check cache cold: %.1f ms" % med(tm(func(): PrintCheck._cache_key = 0; PrintCheck._cache = {}; MeshExport.check_lines(m.S.part), 3)))
	print("n05: %d fail" % fails)
	quit(0 if fails == 0 else 1)
