extends SceneTree
## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/n01_test.gd     (N01: a MEASURED PROFILE of Kine's hot paths; no bars, only numbers)
## Run with: bash /c/Users/Nick/tools/kine_workers/wtest.sh n01       (needs a window and the CAD DLL; the numbers are the point, so compare them after the C++ ports land)
## Every line is `ok   <name>: median X ms, p95 Y ms` (>= 5 runs). It adds no timing hooks to the app: it times the SAME public calls the app makes
## (Part.replay, KCad.*, MeshExport.*, PrintCheck.analyse on a patched COPY of its source with stamps, KMeshSculpt, KMeshView.rebuild, Cloth, KMeshDecimate, KMeshVoxelRemesh).
## Actions measured:
##   1 Easy Part slider drag (12-step part): real drag frames, then one flush split into kernel replay / tessellation / ArrayMesh build / mesh assign / UI sync
##   2 Export dialog opened on 3D printing: total, and the checklist split (replay+tessellate+weld, report, PrintCheck scans: soup, grid, walls, overhangs, floating)
##   3 STL and 3MF writers
##   4 cloth bake (seconds per baked frame)
##   5 sculpt stroke of 30 dabs on the sculpt sphere (native door on, then off)
##   6 decimate to 2k, remesh lighter on the sculpt sphere
##   7 BUILDING card press -> first interactive frame
##   8 frames over 16 ms while clicking through Easy Part's pages (Parts, Through, Colour, Repeat it)
## The machine load (CPU %) is printed at the start of each group, since other tests share the box.
var fails := 0
var m: Node
const RUNS := 5
const KCad := preload("res://scripts/kcad.gd")
const SHOT := "C:/Temp/claude/n01"
const DIRT := "user://n01_test"
var _t0 := 0


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


# ---------------------------------------------------------------- numbers

static func med(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[s.size() / 2])


static func p95(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[mini(s.size() - 1, int(ceil(0.95 * s.size())) - 1)])


func rep(name: String, a: Array, note := "") -> void:
	ok(a.size() >= 1, "%s: median %.2f ms, p95 %.2f ms%s" % [name, med(a), p95(a), (" (n=%d%s)" % [a.size(), (", " + note) if note != "" else ""])])


## ms of one call, n times
func tm(c: Callable, n := RUNS) -> Array:
	var out := []
	for i in n:
		var t := Time.get_ticks_usec()
		c.call()
		out.append((Time.get_ticks_usec() - t) / 1000.0)
	return out


func cpu_load(tag: String) -> void:
	var o := []
	OS.execute("powershell", ["-NoProfile", "-c", "(Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average"], o)
	print("load %s: machine CPU %s %%" % [tag, String(o[0]).strip_edges() if not o.is_empty() else "?"])


func slider_x(s: HSlider, v: float) -> float:
	var r := s.get_global_rect()
	var gw := 24.0
	return r.position.x + gw * 0.5 + (v - s.min_value) / (s.max_value - s.min_value) * (r.size.x - gw)


## a real drag of the knob to value v in 24 mouse steps; the frame times (ms) while held, the flushes made
func drag_slider(s: HSlider, v: float) -> Dictionary:
	var y := s.get_global_rect().get_center().y
	var p0 := Vector2(slider_x(s, s.value), y)
	var ep: EasyPart = m.bld.part.ep
	var f0 := ep.flushes
	await ev_move(p0, false)
	await ev_mouse(p0, true)
	var frames := []
	var last := Time.get_ticks_usec()
	var x1 := slider_x(s, v)
	var fl_prev := ep.flushes
	var st := {"pf": 0, "pre": 0, "post": 0}
	var c1 := func(): st["pre"] = Time.get_ticks_usec()
	var c2 := func(): st["post"] = Time.get_ticks_usec()
	RenderingServer.frame_pre_draw.connect(c1)
	RenderingServer.frame_post_draw.connect(c2)
	for i in range(1, 25):
		st["pf"] = Time.get_ticks_usec()
		await ev_move(Vector2(lerpf(p0.x, x1, i / 24.0), y))
		var now := Time.get_ticks_usec()
		var d := (now - last) / 1000.0
		frames.append(d)
		if d > 30.0:
			print("n01:   slow drag frame %.1f ms: flush in it %s; from the frame start to pre_draw (input + _process + flush) %.1f ms, pre_draw to post_draw (render submit incl. canvas draws) %.1f ms" % [d, str(ep.flushes != fl_prev), (st["pre"] - st["pf"]) / 1000.0, (st["post"] - st["pre"]) / 1000.0])
		fl_prev = ep.flushes
		last = now
	RenderingServer.frame_pre_draw.disconnect(c1)
	RenderingServer.frame_post_draw.disconnect(c2)
	var fl := ep.flushes - f0
	var t_up := Time.get_ticks_usec()
	await ev_mouse(Vector2(x1, y), false)   # the release: the final full-detail flush + undo step
	var rel := (Time.get_ticks_usec() - t_up) / 1000.0
	await idle(2)
	return {"frames": frames, "flushes": fl, "release": rel}


# ---------------------------------------------------------------- PrintCheck with stamps (a patched COPY of the source; the app's file is untouched)

func stamped_print_check() -> GDScript:
	var src := FileAccess.get_file_as_string("res://scripts/build/print_check.gd")
	src = src.replace("\r\n", "\n")
	var kept := PackedStringArray()
	for ln in src.split("\n"):
		if not ln.strip_edges().begins_with("class_name"):
			kept.append(ln)
	src = "\n".join(kept)
	src = src.replace("static var _cache_key := 0\n", "static var TT := []\nstatic var _cache_key := 0\n")
	src = src.replace("static func analyse(bodies: Array) -> Dictionary:\n", "static func tt() -> Array:\n\treturn TT\n\nstatic func analyse(bodies: Array) -> Dictionary:\n\tTT = [Time.get_ticks_usec()]\n")
	for mk in ["\tvar nt := pa.size()\n", "\t# ---- thin walls\n", "\t# ---- overhangs\n", "\t# ---- floating pieces\n", "\t# ---- the words\n"]:
		src = src.replace(mk, "\tTT.append(Time.get_ticks_usec())\n" + mk)
	var gs := GDScript.new()
	gs.source_code = src
	var e := gs.reload()
	if e != OK:
		return null
	return gs


func _init() -> void:
	_t0 = Time.get_ticks_msec()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	DirAccess.make_dir_recursive_absolute(SHOT)
	var ss: StartScreen = m.start_screen
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	print("n01: Kine profile; Godot %s; DLL %s" % [Engine.get_version_info()["string"], str(Part.available())])
	cpu_load("start")
	if not Part.available():
		print("SKIP: no KineCAD DLL; the CAD profile cannot run")
		print("n01: 0 fail")
		quit(0)
		return

	# ======================================================= 7 BUILDING card -> first interactive frame
	var first := []
	var press := []
	var longest := []
	var state := ""
	for run in RUNS:
		ss.show_screen()
		await idle(5)
		var card: Control = ss._cards["building"]
		var p := card.get_global_rect().get_center()
		await ev_move(p, false)
		var tp := Time.get_ticks_usec()
		var ed := InputEventMouseButton.new()
		ed.button_index = MOUSE_BUTTON_LEFT
		ed.pressed = true
		ed.button_mask = MOUSE_BUTTON_MASK_LEFT
		ed.position = p
		ed.global_position = p
		root.push_input(ed, true)   # the card acts on the press
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = false
		e.position = p
		e.global_position = p
		root.push_input(e, true)
		press.append((Time.get_ticks_usec() - tp) / 1000.0)
		var fr := []
		var last := Time.get_ticks_usec()
		var t_first := -1.0
		var calm := 0
		for i in 90:
			await process_frame
			if m.ui_save_ask != null and m.ui_save_ask.visible:
				m._save_ask_choose("discard")
			var now := Time.get_ticks_usec()
			var d := (now - last) / 1000.0
			last = now
			fr.append(d)
			calm = calm + 1 if d < 25.0 else 0
			if calm >= 3 and t_first < 0.0:
				t_first = (now - tp) / 1000.0   # three frames in a row under 25 ms: the app answers
				break
		first.append(t_first if t_first >= 0.0 else (Time.get_ticks_usec() - tp) / 1000.0)
		longest.append(fr.max() if not fr.is_empty() else 0.0)
		state = "page %s kind %s part.on %s easy.on %s" % [m.cur_page, m.S.kind, str(pu.on), str(m.easy.on if m.easy != null else false)]
		await idle(6)
	rep("7 BUILDING card press: handler (the press call itself)", press)
	rep("7 BUILDING card press -> first interactive frame (3 calm frames under 25 ms)", first, state)
	rep("7 BUILDING card press: longest frame after the press", longest)

	# put the app in the Easy Part state as the easypart test does
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	m.S.part = {}
	await idle(8)
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep: EasyPart = pu.ep

	# ======================================================= which template is the 12-step part
	var best := ""
	var best_n := -1
	var counts := []
	for t in PartTemplates.ORDER:
		await pick_part(t)
		await idle(2)
		var nf: int = (m.S.part.get("features", []) as Array).size()
		counts.append("%s=%d" % [t, nf])
		if absi(nf - 12) < absi(best_n - 12) or best_n < 0:
			if ep.rows.size() > 0:
				best = t
				best_n = nf
	print("n01: steps per template: " + ", ".join(counts) + "  -> the 12-step part used: %s (%d steps)" % [best, best_n])
	await pick_part(best)
	await idle(3)
	var rec: Dictionary = m.S.part
	var r0 := Part.replay(rec)
	var tris := 0
	if r0["mesh"] != null:
		tris = (r0["mesh"] as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3
	print("n01: part %s: %d steps, %d bodies, %d triangles (fine tessellation)" % [best, (rec["features"] as Array).size(), int(r0["bodies"]), tris])

	# ======================================================= 1 SLIDER DRAG
	cpu_load("slider")
	var row: Dictionary = ep.rows[0]
	var sl: HSlider = row["slider"]
	var allf := []
	var flushes := []
	var rels := []
	var lo := sl.min_value
	var hi := sl.max_value
	for run in RUNS + 1:
		var v0 := sl.value
		var target := v0 + (hi - lo) * 0.18 * (1.0 if run % 2 == 0 else -1.0)
		target = clampf(target, lo, hi)
		var dr := await drag_slider(sl, target)
		if run > 0:   # the first drag warms the caches
			allf.append_array(dr["frames"])
			flushes.append(float(dr["flushes"]))
			rels.append(dr["release"])
	rep("1 slider drag: frame time while held (all %d frames of %d drags)" % [allf.size(), RUNS], allf)
	var worst := []
	for r in RUNS:
		worst.append((allf.slice(r * 24, r * 24 + 24) as Array).max())
	rep("1 slider drag: WORST frame of a drag (the 100 ms bar)", worst)
	ok(true, "1 slider drag: rebuilds per 24-step drag: median %.0f (throttle 100 ms)" % med(flushes))
	rep("1 slider drag: release (final full-detail flush + undo step)", rels)

	# who calls Part.replay during a drag (Part.calls_log: the caller function + line + the wants), one more drag
	Part.calls_log = []
	var dr2 := await drag_slider(sl, clampf(sl.value + (hi - lo) * 0.18, lo, hi))
	var cl: Array = Part.calls_log
	Part.calls_log = null
	var hist := {}
	for c in cl:
		var k := "%s:%s want=%s upto=%s" % [c[3], c[4], c[2], c[1]]
		hist[k] = int(hist.get(k, 0)) + 1
	print("n01: Part.replay calls in ONE 24-step drag + release (%d flushes during hold): %d" % [dr2["flushes"], cl.size()])
	for k in hist:
		print("n01:   %3d x %s" % [hist[k], k])
	# one flush split, called directly with the same inputs the drag makes (the coarse preview)
	await idle(3)
	rec = m.S.part
	var want := {"edges": false, "faces": false, "body": pu._body_measures(), "coarse": true}
	var full_want := {"edges": false, "faces": false, "body": pu._body_measures()}
	var t_json := tm(func(): var _s := "%s|%s" % [JSON.stringify(rec), JSON.stringify(pu._body_measures())])
	var t_replay := tm(func(): Part.replay(rec, -1, want))
	var t_replay_full := tm(func(): Part.replay(rec, -1, full_want))
	var want_edges := {"edges": true, "faces": true, "body": pu._body_measures()}
	var t_replay_edges := tm(func(): Part.replay(rec, -1, want_edges))
	var t_keep := []
	var t_tess := []
	var t_tess_full := []
	var t_mesh := []
	var t_vol := []
	var t_rel := []
	for i in RUNS:
		var tk := Time.get_ticks_usec()
		var ids: Array = Part.replay(rec, -1, {"keep": true, "coarse": true}).get("ids", [])
		t_keep.append((Time.get_ticks_usec() - tk) / 1000.0)
		var tms := []
		var t1 := Time.get_ticks_usec()
		for b in ids:
			tms.append(KCad.tessellate(int(b), Part.COARSE_DEFL, Part.COARSE_ANGLE))
		t_tess.append((Time.get_ticks_usec() - t1) / 1000.0)
		var t1b := Time.get_ticks_usec()
		for b in ids:
			KCad.tessellate(int(b), 0.0003, 0.25)
		t_tess_full.append((Time.get_ticks_usec() - t1b) / 1000.0)
		var t2 := Time.get_ticks_usec()
		var mesh := ArrayMesh.new()
		for tmx in tms:
			if tmx != null and (tmx as ArrayMesh).get_surface_count() > 0:
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, (tmx as ArrayMesh).surface_get_arrays(0))
		t_mesh.append((Time.get_ticks_usec() - t2) / 1000.0)
		var t3 := Time.get_ticks_usec()
		for b in ids:
			KCad.volume(int(b))
		t_vol.append((Time.get_ticks_usec() - t3) / 1000.0)
		for b in ids:
			KCad.release(int(b))
		t_rel.append(0.0)
	var kern := []
	for i in RUNS:
		kern.append(maxf(0.0, float(t_keep[i]) - float(t_tess[i]) - float(t_mesh[i]) - float(t_vol[i])))
	var m_mesh: ArrayMesh = Part.replay(rec, -1, want)["mesh"]
	var t_assign := tm(func():
		pu.part_mesh.mesh = m_mesh
		pu._look_surfaces())
	var t_sync := tm(func(): pu.sync())   # the record is unchanged: the replay is skipped, this is the UI sync alone
	var t_vals := tm(func(): ep._values_sync())
	var t_flush := []
	for i in RUNS:
		pu.coarse = true
		pu.replay_forget()
		pu._rec_sig = ""
		var tf := Time.get_ticks_usec()
		ep._flush()
		t_flush.append((Time.get_ticks_usec() - tf) / 1000.0)
	pu.coarse = false
	var t_flush_full := []
	for i in RUNS:
		pu.replay_forget()
		pu._rec_sig = ""
		var tf := Time.get_ticks_usec()
		ep._flush()
		t_flush_full.append((Time.get_ticks_usec() - tf) / 1000.0)
	rep("1 flush TOTAL, coarse preview (ep._flush with the replay forgotten)", t_flush)
	rep("1 flush TOTAL, full detail (what the release does)", t_flush_full)
	rep("1   record signature (JSON.stringify of the record + body measures)", t_json)
	rep("1   Part.replay coarse, whole", t_replay)
	rep("1     of it: CAD kernel features (KCad booleans / extrudes / fillets), by subtraction", kern)
	rep("1     of it: KCad.tessellate coarse (OpenCASCADE mesher)", t_tess)
	rep("1     of it: ArrayMesh build (surface_get_arrays + add_surface_from_arrays)", t_mesh)
	rep("1     of it: KCad.volume", t_vol)
	rep("1   Part.replay full detail, whole", t_replay_full)
	rep("1     KCad.tessellate full detail (0.3 mm)", t_tess_full)
	rep("1   Part.replay with edges + faces (Expert's pick arrays; Easy does not ask)", t_replay_edges)
	rep("1   part_mesh.mesh assign + _look_surfaces", t_assign)
	rep("1   PartUI.sync with nothing new (browser, timeline, numbers, inspector, look)", t_sync)
	rep("1   EasyPart._values_sync", t_vals)

	# ======================================================= 2 EXPORT DIALOG on 3D printing
	cpu_load("export dialog")
	var gs := stamped_print_check()
	ok(gs != null, "2 the stamped copy of PrintCheck compiles")
	var pc = gs.new() if gs != null else null
	if m.export_ui == null:
		m.export_ui = ExportDialog.new(m)
	var open_t := []
	var check_t := []
	for i in RUNS:
		PrintCheck._cache_key = 0
		PrintCheck._cache = {}
		var to := Time.get_ticks_usec()
		m.export_ui.open()
		open_t.append((Time.get_ticks_usec() - to) / 1000.0)
		m.export_ui.dlg.hide()
		await idle(2)
	rep("2 Export dialog open() on 3D printing (print cache cold), TOTAL", open_t, "open() runs _refresh twice; PrintCheck caches by record")
	var warm := []
	for i in RUNS:
		var to := Time.get_ticks_usec()
		m.export_ui.open()
		warm.append((Time.get_ticks_usec() - to) / 1000.0)
		m.export_ui.dlg.hide()
		await idle(2)
	rep("2 Export dialog open(), print cache warm (record unchanged)", warm, "still replays + welds the part twice")
	var t_slicers := tm(func(): SlicerSend.detect_system())
	rep("2   SlicerSend.detect_system (the dialog re-runs it on EVERY open: directory scans + `reg query` processes)", t_slicers)
	var t_bodies := tm(func(): MeshExport.bodies_of(rec))
	var bo: Dictionary = MeshExport.bodies_of(rec)
	var bodies: Array = bo["bodies"]
	var nbt := 0
	for b in bodies:
		nbt += (b["t"] as PackedInt32Array).size() / 3
	var t_report := tm(func(): MeshExport.report(bodies))
	var t_lines := tm(func(): MeshExport.check_lines(rec))
	rep("2   MeshExport.check_lines (bodies_of + report + PrintCheck), one call", t_lines)
	rep("2     MeshExport.bodies_of (replay + tessellate + weld)", t_bodies, "%d bodies, %d triangles" % [bodies.size(), nbt])
	rep("2     MeshExport.report", t_report)
	# bodies_of split
	var s_rep := []
	var s_tess := []
	var s_soup := []
	var s_weld := []
	for i in RUNS:
		var ta := Time.get_ticks_usec()
		var ids: Array = Part.replay(rec, -1, {"keep": true}).get("ids", [])
		var tb := Time.get_ticks_usec()
		var tms2 := []
		for id in ids:
			tms2.append(KCad.tessellate(int(id), MeshExport.DEFLECT_M, MeshExport.ANGLE))
			KCad.release(int(id))
		var tc := Time.get_ticks_usec()
		var soups := []
		for tmx in tms2:
			var soup := PackedVector3Array()
			if tmx != null:
				for s in (tmx as ArrayMesh).get_surface_count():
					var arr := (tmx as ArrayMesh).surface_get_arrays(s)
					var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					var idx = arr[Mesh.ARRAY_INDEX]
					if idx == null:
						soup.append_array(vs)
					else:
						for k in (idx as PackedInt32Array):
							soup.append(vs[k])
			soups.append(soup)
		var td := Time.get_ticks_usec()
		for sp in soups:
			MeshExport.weld(sp)
		var te := Time.get_ticks_usec()
		s_rep.append((tb - ta) / 1000.0)
		s_tess.append((tc - tb) / 1000.0)
		s_soup.append((td - tc) / 1000.0)
		s_weld.append((te - td) / 1000.0)
	rep("2       bodies_of: Part.replay (kernel features + coarse-ish tessellate inside it)", s_rep)
	rep("2       bodies_of: KCad.tessellate at 0.05 mm export detail", s_tess)
	rep("2       bodies_of: triangle soup (GDScript loop over every index)", s_soup)
	rep("2       bodies_of: MeshExport.weld (GDScript, dictionary on vertex keys)", s_weld)
	# PrintCheck scans
	if gs != null:
		var ph := {"soup": [], "grid": [], "walls": [], "over": [], "float": [], "words": [], "total": []}
		for i in RUNS:
			pc.call("analyse", bodies)
			var tt: Array = pc.call("tt")
			if tt.size() >= 6:
				ph["soup"].append((tt[1] - tt[0]) / 1000.0)
				ph["grid"].append((tt[2] - tt[1]) / 1000.0)
				ph["walls"].append((tt[3] - tt[2]) / 1000.0)
				ph["over"].append((tt[4] - tt[3]) / 1000.0)
				ph["float"].append((tt[5] - tt[4]) / 1000.0)
				ph["total"].append((tt[5] - tt[0]) / 1000.0)
		rep("2     PrintCheck.analyse TOTAL (patched copy, same code)", ph["total"], "%d triangles" % nbt)
		rep("2       scan: triangle soup + areas", ph["soup"])
		rep("2       scan: spatial grid (2 mm cells, a Dictionary of Arrays)", ph["grid"])
		rep("2       scan: thin walls (4 rays a triangle + union-find)", ph["walls"])
		rep("2       scan: overhangs (1 ray per down-facing triangle)", ph["over"])
		rep("2       scan: floating pieces (body-pair touch tests)", ph["float"])
		var per := []
		for v in ph["total"]:
			per.append(float(v) / maxf(1.0, nbt / 1000.0))
		rep("2     PrintCheck per 1000 triangles (all scans)", per)
	# scaling: a closed UV sphere (r 20 mm, resting on the bed) at 5k / 20k / 50k triangles through the same stamped scans
	if gs != null:
		for rings_v in [40, 80, 130]:
			var rings: int = rings_v
			var seg := rings * 2
			var vv := PackedVector3Array()
			var ti := PackedInt32Array()
			vv.append(Vector3(0, 0, 40))
			for ri in range(1, rings):
				var th := PI * ri / rings
				for si in seg:
					var ph := TAU * si / seg
					vv.append(Vector3(sin(th) * cos(ph), sin(th) * sin(ph), cos(th) + 1.0) * 20.0)
			vv.append(Vector3(0, 0, 0))
			var bot := vv.size() - 1
			for si in seg:
				ti.append_array(PackedInt32Array([0, 1 + si, 1 + (si + 1) % seg]))
			for ri in range(0, rings - 2):
				for si in seg:
					var a := 1 + ri * seg + si
					var b := 1 + ri * seg + (si + 1) % seg
					ti.append_array(PackedInt32Array([a, a + seg, b, b, a + seg, b + seg]))
			for si in seg:
				var a := 1 + (rings - 2) * seg + si
				ti.append_array(PackedInt32Array([a, bot, 1 + (rings - 2) * seg + (si + 1) % seg]))
			var sb := [{"v": vv, "t": ti, "name": "sphere", "color": null}]
			pc.call("analyse", sb)
			var tt2: Array = pc.call("tt")
			var n3 := ti.size() / 3
			print("n01: PrintCheck scaling, sphere %d triangles: total %.0f ms (soup %.0f, grid %.0f, walls %.0f, overhangs %.0f, floating %.0f)" % [n3, (tt2[5] - tt2[0]) / 1000.0, (tt2[1] - tt2[0]) / 1000.0, (tt2[2] - tt2[1]) / 1000.0, (tt2[3] - tt2[2]) / 1000.0, (tt2[4] - tt2[3]) / 1000.0, (tt2[5] - tt2[4]) / 1000.0])
	# every template, one call each: how it scales
	var tab := []
	for t in PartTemplates.ORDER:
		var rc: Dictionary = PartTemplates.make(t)
		if rc.is_empty():
			continue
		var b2: Array = MeshExport.bodies_of(rc).get("bodies", [])
		if b2.is_empty() or gs == null:
			continue
		var n2 := 0
		for b in b2:
			n2 += (b["t"] as PackedInt32Array).size() / 3
		var ta := Time.get_ticks_usec()
		pc.call("analyse", b2)
		tab.append("%s %d tris %.0f ms" % [t, n2, (Time.get_ticks_usec() - ta) / 1000.0])
	if not tab.is_empty():
		print("n01: PrintCheck.analyse per template: " + "; ".join(tab))

	# ======================================================= 3 EXPORT STL / 3MF
	cpu_load("export files")
	var dirp := DIRT + "/exports"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dirp))
	var path_stl := ProjectSettings.globalize_path(dirp + "/n01.stl")
	var path_3mf := ProjectSettings.globalize_path(dirp + "/n01.3mf")
	rep("3 STL writer: stl_bytes (GDScript, bytes per triangle)", tm(func(): MeshExport.stl_bytes(bodies)), "%d triangles" % nbt)
	rep("3 STL writer: write_stl (bytes + file)", tm(func(): MeshExport.write_stl(path_stl, bodies)))
	rep("3 3MF writer: model_xml (GDScript string building)", tm(func(): MeshExport.model_xml(bodies, "n01")))
	rep("3 3MF writer: write_3mf (xml + zip + file)", tm(func(): MeshExport.write_3mf(path_3mf, bodies, "n01")))
	rep("3 export_part STL, whole press (bodies_of + report + write)", tm(func(): MeshExport.export_part(rec, "stl", dirp)))
	rep("3 export_part 3MF, whole press (bodies_of + report + write)", tm(func(): MeshExport.export_part(rec, "3mf", dirp)))

	# ======================================================= 8 Easy Part pages (frames over 16 ms) and 7 follow-up
	cpu_load("pages")
	await pick_part("sword")
	await idle(4)
	var acts := {}
	var names := ["Parts library", "Through (Cut a hole)", "Colour", "Repeat it"]
	for run in RUNS:
		for nm in names:
			var btn: BaseButton = null
			var then: BaseButton = null
			match nm:
				"Parts library":
					btn = ep.parts_btn
				"Through (Cut a hole)":
					btn = ep.make_btns["hole"]
					then = ep.hole_btns["through"]
				"Colour":
					btn = ep.make_btns["colour"]
				"Repeat it":
					btn = ep.make_btns["repeat"]
			if btn == null or not btn.is_visible_in_tree():
				continue
			for step in 2:   # open it, then (Through only) press the choice, then close
				var c: Control = btn if step == 0 else then
				if c == null or not c.is_visible_in_tree():
					continue
				var key: String = nm + (" open" if step == 0 else " -> Through")
				var p := c.get_global_rect().get_center()
				await ev_move(p, false)
				await ev_mouse(p, true)
				var tp := Time.get_ticks_usec()
				var e := InputEventMouseButton.new()
				e.button_index = MOUSE_BUTTON_LEFT
				e.pressed = false
				e.position = p
				e.global_position = p
				root.push_input(e, true)
				var handler := (Time.get_ticks_usec() - tp) / 1000.0
				var last := Time.get_ticks_usec()
				var w := 0.0
				var sum := handler
				for i in 6:
					await process_frame
					var now := Time.get_ticks_usec()
					w = maxf(w, (now - last) / 1000.0)
					last = now
				if not acts.has(key):
					acts[key] = {"handler": [], "worst": []}
				acts[key]["handler"].append(handler)
				acts[key]["worst"].append(maxf(w, handler))
			# close it again (a second press toggles it off; Parts too)
			await click_ctl(btn)
			await idle(2)
	for key in acts:
		rep("8 click %s: the press handler" % key, acts[key]["handler"])
		rep("8 click %s: worst frame in the 6 after" % key, acts[key]["worst"], "OVER 16 ms" if med(acts[key]["worst"]) > 16.0 else "")
	# the Parts library category chips
	await click_ctl(ep.parts_btn)
	await idle(3)
	var chips := []
	if ep.lib_box != null:
		for c in ep.lib_box.find_children("*", "Button", true, false):
			if c.is_visible_in_tree() and not (c as Button).disabled:
				chips.append(c)
	var cat_worst := []
	for c in chips.slice(0, 8):
		var p := (c as Control).get_global_rect().get_center()
		await ev_move(p, false)
		await ev_mouse(p, true)
		await ev_mouse(p, false)
		var last := Time.get_ticks_usec()
		var w := 0.0
		for i in 4:
			await process_frame
			var now := Time.get_ticks_usec()
			w = maxf(w, (now - last) / 1000.0)
			last = now
		cat_worst.append(w)
	if not cat_worst.is_empty():
		rep("8 Parts library: a category chip (%d chips), worst frame after" % cat_worst.size(), cat_worst)
	await click_ctl(ep.parts_btn)

	# ======================================================= 5 SCULPT, 6 DECIMATE / REMESH, 4 CLOTH (no app state needed)
	cpu_load("sculpt")
	await sculpt_group()
	cpu_load("decimate / remesh")
	remesh_group()
	cpu_load("cloth")
	cloth_group()
	cpu_load("end")
	print("n01: total %.1f s" % ((Time.get_ticks_msec() - _t0) / 1000.0))
	print("n01: %d fail" % fails)
	quit(1 if fails > 0 else 0)


# ---------------------------------------------------------------- 5 sculpt

static func walk(mesh: KMesh, n: int) -> Dictionary:
	var hits := []
	var ns := []
	var seen := {}
	var v := mesh.verts.size() / 3
	for i in n:
		hits.append(mesh.verts[v])
		ns.append(mesh.vert_normals[v])
		seen[v] = true
		var nxt := -1
		for u in mesh.vert_neighbors(v):
			if not seen.has(u):
				nxt = u
				break
		if nxt < 0:
			nxt = (v + 7) % mesh.verts.size()
		v = nxt
	return {"hits": hits, "ns": ns}


func sculpt_group() -> void:
	var sph := KMeshSculptUI.make_sphere()
	print("n01: sculpt sphere %d verts, %d faces, %d triangles" % [sph.verts.size(), sph.faces.size(), sph.triangle_count()])
	var have := ClassDB.class_exists("KineSculptNative")
	print("n01: KineSculptNative %s" % ("loaded" if have else "MISSING"))
	var w := walk(sph, 30)
	var view := KMeshView.new()
	view.show_wire = false
	view.show_verts = false
	view.smooth_shade = true
	root.add_child(view)
	for native in [true, false]:
		if not native and not have:
			continue
		var tag := "native door ON" if native else "native door OFF (GDScript)"
		var per_dab := []
		var begins := []
		var ends := []
		var strokes := []
		var rebuilds := []
		var undo_b := []
		var undo_c := []
		var verts_in_t := []
		var disp_t := []
		var apply_t := []
		var brush_names := [KMeshSculpt.DRAW, KMeshSculpt.SMOOTH] if native else [KMeshSculpt.DRAW]
		for br in brush_names:
			var pd := []
			for run in RUNS:
				var mesh := KMeshDecimate.copy(sph)
				mesh.rebuild()
				KMeshMask.ensure(mesh)
				var undo := KMeshUndo.new()
				KMeshSculpt.native_on = native
				var sc := KMeshSculpt.new()
				var t0 := Time.get_ticks_usec()
				undo.begin(mesh)
				var t1 := Time.get_ticks_usec()
				sc.begin(mesh, {"brush": br, "radius": 0.08, "strength": 0.001, "sym_x": true})
				var t2 := Time.get_ticks_usec()
				var one := []
				for i in 30:
					var ta := Time.get_ticks_usec()
					sc.dab(w["hits"][i], w["ns"][i], 1.0)
					one.append((Time.get_ticks_usec() - ta) / 1000.0)
					if native and br == KMeshSculpt.DRAW and sc._nb != null and i % 6 == 0:
						var tv := Time.get_ticks_usec()
						var ids := sc.verts_in(w["hits"][i], 0.08)
						verts_in_t.append((Time.get_ticks_usec() - tv) / 1000.0)
						var tdp := Time.get_ticks_usec()
						var nd = sc._nb.displacements(sc._nctx, mesh.verts, mesh.vert_normals, ids, br, "smooth", w["hits"][i], (w["ns"][i] as Vector3).normalized(), 0.08, 0.001, 0.001, 1.0, false, Vector3.ZERO)
						disp_t.append((Time.get_ticks_usec() - tdp) / 1000.0)
						if nd != null:
							var tap := Time.get_ticks_usec()
							sc._nb.apply(sc._nctx, mesh, ids, nd, sc._sym, sc._sax, sc._mask, sc._lock)
							apply_t.append((Time.get_ticks_usec() - tap) / 1000.0)
				var t3 := Time.get_ticks_usec()
				sc.end()
				var st := undo.commit("n01")
				var t4 := Time.get_ticks_usec()
				KMeshSculpt.native_on = true
				view.set_mesh(mesh)
				var t5 := Time.get_ticks_usec()
				view.rebuild()
				var t6 := Time.get_ticks_usec()
				undo_b.append((t1 - t0) / 1000.0)
				begins.append((t2 - t1) / 1000.0)
				pd.append_array(one)
				strokes.append((t3 - t2) / 1000.0)
				ends.append((t4 - t3) / 1000.0)
				rebuilds.append((t6 - t5) / 1000.0)
			rep("5 sculpt %s [%s]: ONE dab (30 per stroke)" % [br, tag], pd)
			per_dab.append_array(pd)
		rep("5 sculpt [%s]: begin (spatial hash / native ctx, symmetry map, mask)" % tag, begins)
		rep("5 sculpt [%s]: 30 dabs, whole stroke" % tag, strokes)
		rep("5 sculpt [%s]: undo.begin (snapshot)" % tag, undo_b)
		rep("5 sculpt [%s]: end + undo.commit (diff)" % tag, ends)
		rep("5 sculpt [%s]: KMeshView.rebuild after the stroke (GDScript; runs every frame while dirty)" % tag, rebuilds)
		if native and not verts_in_t.is_empty():
			rep("5   native part of a dab: verts_in", verts_in_t)
			rep("5   native part of a dab: displacements", disp_t)
			rep("5   native part of a dab: apply (+ renormal)", apply_t)
	view.queue_free()


# ---------------------------------------------------------------- 6 decimate and remesh

func remesh_group() -> void:
	var sph := KMeshSculptUI.make_sphere()
	# make the sphere the size the profile asked for (13.8k): 24 splits give the count printed above
	var tr0 := sph.triangle_count()
	var am := sph.to_array_mesh()
	var dec_budget := []
	var dec_core := []
	var dec_in := []
	var dec_out := []
	var got := 0
	for run in RUNS:
		var t0 := Time.get_ticks_usec()
		var d: Mesh = ExportBudget.decimate_mesh(am, 2000)
		dec_budget.append((Time.get_ticks_usec() - t0) / 1000.0)
		got = ExportBudget.tris_of(d)
		var t1 := Time.get_ticks_usec()
		var km := KMesh.new().from_array_mesh(am)
		var t2 := Time.get_ticks_usec()
		KMeshDecimate.collapse(km, 1.0, 2000)
		var t3 := Time.get_ticks_usec()
		km.to_array_mesh()
		var t4 := Time.get_ticks_usec()
		dec_in.append((t2 - t1) / 1000.0)
		dec_core.append((t3 - t2) / 1000.0)
		dec_out.append((t4 - t3) / 1000.0)
	rep("6 Decimate to 2k, ExportBudget.decimate_mesh whole (%d -> %d triangles)" % [tr0, got], dec_budget)
	rep("6   KMesh.from_array_mesh (weld by position)", dec_in)
	rep("6   KMeshDecimate.collapse (quadric edge collapse, GDScript)", dec_core)
	rep("6   KMesh.to_array_mesh", dec_out)
	var planar := tm(func(): KMeshDecimate.planar(KMeshDecimate.copy(sph)))
	rep("6   KMeshDecimate.planar (no reduction on a sphere; for reference)", planar)
	# remesh lighter: replicate KMeshSculptUI.remesh_by(-1) step by step
	var t_area := []
	var t_tris := []
	var t_field := []
	var t_nets := []
	var t_from := []
	var t_apply := []
	var t_whole := []
	var tris_after := 0
	for run in RUNS:
		var mesh := KMeshDecimate.copy(sph)
		mesh.rebuild()
		KMeshMask.ensure(mesh)
		var undo := KMeshUndo.new()
		var tw := Time.get_ticks_usec()
		var target := maxf(float(mesh.triangle_count()) * 0.5, 12.0)
		var ta := Time.get_ticks_usec()
		var area := 0.0
		for f in mesh.faces:
			var fa := f as PackedInt32Array
			for k in range(1, fa.size() - 1):
				area += (mesh.verts[fa[k]] - mesh.verts[fa[0]]).cross(mesh.verts[fa[k + 1]] - mesh.verts[fa[0]]).length() * 0.5
		var h := sqrt(3.0 * area / target)
		t_area.append((Time.get_ticks_usec() - ta) / 1000.0)
		# the stages of KMeshVoxelRemesh.remesh at this voxel
		var tb := Time.get_ticks_usec()
		var tris := PackedVector3Array()
		for f in mesh.faces:
			var fa := f as PackedInt32Array
			for k in range(1, fa.size() - 1):
				tris.append(mesh.verts[fa[0]])
				tris.append(mesh.verts[fa[k]])
				tris.append(mesh.verts[fa[k + 1]])
		t_tris.append((Time.get_ticks_usec() - tb) / 1000.0)
		var tc := Time.get_ticks_usec()
		var field := AnyGrip.MeshField.build_banded(tris, h)
		t_field.append((Time.get_ticks_usec() - tc) / 1000.0)
		var td := Time.get_ticks_usec()
		var verts := PackedVector3Array()
		var faces: Array = []
		KMeshVoxelRemesh.surface_nets(field, verts, faces)
		t_nets.append((Time.get_ticks_usec() - td) / 1000.0)
		var te := Time.get_ticks_usec()
		KMesh.new().from_arrays(verts, faces)
		t_from.append((Time.get_ticks_usec() - te) / 1000.0)
		# the real call the slider makes: correction loop (up to 2 remeshes) + apply
		var tf := Time.get_ticks_usec()
		var hh := h
		for _i in 2:
			var tt := KMeshVoxelRemesh.remesh(mesh, hh)
			if not tt["ok"]:
				break
			var g := float((tt["mesh"] as KMesh).triangle_count())
			if absf(g / target - 1.0) < 0.03:
				break
			hh *= sqrt(g / target)
		var tg := Time.get_ticks_usec()
		KMeshVoxelRemesh.apply(mesh, hh, undo)
		t_apply.append((Time.get_ticks_usec() - tg) / 1000.0)
		tris_after = mesh.triangle_count()
		t_whole.append((Time.get_ticks_usec() - tw) / 1000.0)
	rep("6 Remesh lighter (remesh_by -0.5.. -1 doubling), WHOLE without the view rebuild (%d -> %d triangles)" % [tr0, tris_after], t_whole, "includes the 2-pass voxel-size correction")
	rep("6   area loop (GDScript)", t_area)
	rep("6   one remesh: triangle list (GDScript)", t_tris)
	rep("6   one remesh: AnyGrip.MeshField.build_banded", t_field)
	rep("6   one remesh: surface_nets (GDScript)", t_nets)
	rep("6   one remesh: KMesh.from_arrays", t_from)
	rep("6   apply (one more remesh + undo + mask)", t_apply)


# ---------------------------------------------------------------- 4 cloth

func cloth_group() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	var S := Scene.new()
	S.fps = 30
	var rest := {}
	for j in Body.ORDER:
		rest[j] = {"bend": 0.0, "side": 0.0, "twist": 0.0}
	S.add("stand", {"joints": rest.duplicate(true), "offset": [0.0, 0.0, 0.0]})
	(S.cards[-1] as Dictionary)["hold"] = 0.5
	var turned := rest.duplicate(true)
	(turned["pelvis"] as Dictionary)["twist"] = 90.0
	S.add("turn", {"joints": turned, "offset": [0.0, 0.0, 0.0]})
	(S.cards[-1] as Dictionary)["move"] = 0.25
	(S.cards[-1] as Dictionary)["hold"] = 0.75
	var nf := maxi(int(ceil(S.length() * float(S.fps) - 1e-6)), 1) + 1
	var keep := B.state()
	var samp := []
	var sim := []
	var per := []
	var pre := int(round(Cloth.PRE_S * float(S.fps)))
	var out_frames := 0
	for run in RUNS:
		var t0 := Time.get_ticks_usec()
		var sm := Cloth.sample_frames(B, nf, S.fps, func(t: float) -> void: S.apply(B, minf(t, S.length())))
		var t1 := Time.get_ticks_usec()
		var res := Cloth.simulate(sm["A"], sm["C"], Cloth.radii(B, sm["names"]), S.fps, null)
		var t2 := Time.get_ticks_usec()
		samp.append((t1 - t0) / 1000.0)
		sim.append((t2 - t1) / 1000.0)
		out_frames = (res.get("frames", []) as Array).size()
		per.append((t2 - t1) / 1000.0 / float(maxi(1, out_frames + pre)))   # the pre-roll is simulated too
	B.set_state(keep)
	B.fk()
	print("n01: cloth cape: %d baked frames at %d fps (+%d pre-roll frames simulated), %d substeps a frame, %d iterations a substep" % [out_frames, S.fps, pre, maxi(1, int(round(float(Cloth.SUB_HZ) / float(S.fps)))), Cloth.ITER])
	rep("4 cloth bake: sample_frames (pins + capsules per frame, Body.fk, GDScript)", samp)
	rep("4 cloth bake: Cloth.simulate, whole (the pure-math half that runs on a worker)", sim)
	rep("4 cloth bake: per simulated frame (pre-roll included); x1000 = ms/frame: SECONDS per baked frame is this / 1000", per)
	var spf := []
	for v in sim:
		spf.append(float(v) / float(maxi(1, out_frames)))
	rep("4 cloth bake: per BAKED frame (all of simulate / baked frames)", spf, "ms; /1000 = s per baked frame")
