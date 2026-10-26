## godot --path . -s tests/brushpreset_test.gd     (ROADMAP_400 C14; needs a window: thumbnails are rendered, real keys and clicks)
## Brush presets (scripts/brush_presets.gd, the panel scripts/brush_presets_panel.gd, B in sculpt). Bars, stated before measuring:
##   1 SHIPPED: >= 10 presets, the item's 8 by name (Clay buildup, Smooth soft, Crease sharp, Pinch fine, Inflate big, Grab
##     large, Flatten plane, Mask paint) among them, every one already clean (clean(p) == p), no two with the same fields;
##     each one's thumbnail stroke changes the plane (a vert moved > 0.5 mm, or the mask brush painted > 0.5 somewhere)
##   2 APPLY EXACTNESS: a click on each preset's row in the panel makes every field of the sculpt UI == the preset's (brush,
##     radius, strength, falloff, spacing, sym_x / y / z, radial, radial axis), from a UI whose fields were all different
##     first; a real stroke after "Crease sharp" carries those values into the stroke params (KMeshSculpt.p) ==
##   3 USER PRESET ROUND TRIP: a brush of non-round values (radius 0.0737123, strength 0.00311, spacing 0.137, pinch, linear,
##     Y symmetry, radial 5 around Z) saved with "Save current brush as preset" comes back from the file == in every
##     field; the panel lists it; picking another preset and then it gives the UI == again; saving the same name twice
##     keeps one. The user's own files are put back as they were afterwards
##   4 FAVOURITES: a click on Pinch fine's star puts it in user://brush_favourites.json (a fresh read has it) and moves it to
##     the top of the list; a second click takes it out (a fresh read has not)
##   5 THUMBNAILS: Clay buildup's is 64 x 64 and not empty (its pixels' colour standard deviation > 0.03, and the plane
##     covers the centre: centre pixel differs from the background colour by > 0.1); Clay buildup vs Smooth soft differ
##     by a mean colour distance > 0.01; the mask preset's thumbnail is bluer than the clay one's (mean b - r larger by > 0.02);
##     it is cached as user://brush_thumbs/<key>.png; asked again a memory hit, after forget() a disk hit (no new draw)
##   6 PLACEMENT (shot $TMP/brushpreset_ui.png): B (a real key) opens the panel: wholly inside the clear view, not over the
##     matcap strip, not over the sphere's projected outline (seen from the front, 1.6 m), every row's thumbnail filled;
##     B closes it; Shift+B still blurs the mask (a painted mask changes) and leaves the panel shut; leaving sculpt closes it
extends SceneTree

var fails := 0
var m: Node
var ui: KMeshSculptUI
var pan: BrushPresetsPanel
const NEED := ["Clay buildup", "Smooth soft", "Crease sharp", "Pinch fine", "Inflate big", "Grab large", "Flatten plane", "Mask paint"]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func key(k: int, shift := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.shift_pressed = shift
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func click(c: Control) -> void:
	# scroll it into view first: a click lands only on what is shown
	var sc := pan.find_child("presets_scroll", true, false) as ScrollContainer
	if sc != null and c.is_inside_tree() and sc.is_ancestor_of(c):
		sc.ensure_control_visible(c)
		await idle(2)
	var p := c.get_global_rect().get_center()
	await mouse(p, true)
	await mouse(p, false)
	await idle(2)


func shot() -> Image:
	await idle(4)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func dist(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2))


func tmp(f: String) -> String:
	return OS.get_environment("TMP").path_join(f) if OS.get_environment("TMP") != "" else "user://" + f


func fields_eq(p: Dictionary) -> bool:
	return BrushPresets.matches_ui(ui, p)


func diff_words(p: Dictionary) -> String:
	var w := PackedStringArray()
	for k in BrushPresets.FIELDS:
		if ui.get(k) != p[k]:
			w.append("%s %s != %s" % [k, ui.get(k), p[k]])
	return ", ".join(w) if not w.is_empty() else "all =="


func row(nm: String) -> Dictionary:
	return pan.rows.get(nm, {})


func _init() -> void:
	var had := {}
	for f in [BrushPresets.USER, BrushPresets.FAVS]:
		had[f] = FileAccess.get_file_as_string(f) if FileAccess.file_exists(f) else null
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	await _run()
	for f in had:   # the user's own files as they were
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		if had[f] != null:
			var fa := FileAccess.open(f, FileAccess.WRITE)
			fa.store_string(had[f])
			fa.close()
	print("BRUSH PRESETS ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(1 if fails else 0)


func _run() -> void:
	# 1 shipped
	var sh := BrushPresets.shipped()
	var names := []
	var all_clean := true
	var keys := {}
	var still := PackedStringArray()
	for e in sh:
		names.append(e["name"])
		var raw: Dictionary = e.duplicate()
		raw.erase("user")
		all_clean = all_clean and BrushPresets.clean(raw) == raw
		keys[BrushPresets.key_of(e)] = true
		var base := BrushPresets.base_plane()
		var sm := BrushPresets.stroke_mesh(e)
		var most := 0.0
		for v in base.verts.size():
			most = maxf(most, base.verts[v].distance_to(sm.verts[v]))
		var mk := 0.0
		for x in KMeshMask.values(sm):
			mk = maxf(mk, x)
		if most <= 0.0005 and mk <= 0.5:
			still.append("%s (moved %.4f, mask %.2f)" % [e["name"], most, mk])
	var missing := NEED.filter(func(n): return not names.has(n))
	ok(sh.size() >= 10 and missing.is_empty() and all_clean and keys.size() == sh.size() and still.is_empty(),
		"(1) shipped: %d presets, missing %s, all clean %s, distinct %d, strokes that change nothing on the plane %s" % [sh.size(), missing, all_clean, keys.size(), still])
	# the sculpt page
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._sculpt_start()
	await idle(3)
	ui = m.ksc
	pan = ui.presets
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 1.6, wc, false)
	await idle(6)
	var cam: Camera3D = m.cam
	var cs := cam.unproject_position(wc)
	await key(KEY_B)
	var opened := pan.visible
	# 2 apply exactness
	var bad := PackedStringArray()
	for e in sh:
		# every field away from the preset's first
		ui.brush = KMeshSculpt.SNAKE if e["brush"] != KMeshSculpt.SNAKE else KMeshSculpt.DRAW
		ui.radius = float(e["radius"]) + 0.0123
		ui.strength = float(e["strength"]) + 0.00077
		ui.falloff = KMeshSculpt.F_LINEAR if e["falloff"] != KMeshSculpt.F_LINEAR else KMeshSculpt.F_SHARP
		ui.spacing = float(e["spacing"]) + 0.031
		ui.sym_x = not e["sym_x"]
		ui.sym_y = not e["sym_y"]
		ui.sym_z = not e["sym_z"]
		ui.radial = int(e["radial"]) + 1
		ui.radial_axis = (int(e["radial_axis"]) + 1) % 3
		var r := row(e["name"])
		if r.is_empty():
			bad.append("%s: no row" % e["name"])
			continue
		await click(r["btn"])
		if not fields_eq(e):
			bad.append("%s: %s" % [e["name"], diff_words(e)])
	var crease := BrushPresets.find("Crease sharp")
	await click(row("Crease sharp")["btn"])
	pan.close()
	await idle(2)
	await mouse(cs + Vector2(-20, 0), true)
	for k in 4:
		await move(cs + Vector2(-20 + k * 10, 0))
	await mouse(cs + Vector2(20, 0), false)
	await idle(2)
	var carried := true
	for k in BrushPresets.FIELDS:
		carried = carried and ui.sculpt.p.get(k) == crease[k]
	ok(opened and bad.is_empty() and carried and ui.sculpt.dabs > 0,
		"(2) apply: B opened the panel %s; %d presets clicked, mismatches %s; a stroke after Crease sharp carries every field %s (%d dabs, p %s)" % [opened, sh.size(), bad, carried, ui.sculpt.dabs,
		{"brush": ui.sculpt.p.get("brush"), "radius": ui.sculpt.p.get("radius"), "spacing": ui.sculpt.p.get("spacing")}])
	ui.undo.undo()
	# 3 user preset round trip
	pan.open()
	await idle(2)
	ui.brush = KMeshSculpt.PINCH
	ui.radius = 0.0737123
	ui.strength = 0.00311
	ui.falloff = KMeshSculpt.F_LINEAR
	ui.spacing = 0.137
	ui.sym_x = false
	ui.sym_y = true
	ui.sym_z = false
	ui.radial = 5
	ui.radial_axis = 2
	var mine := BrushPresets.of_ui(ui, "Test brush 7f3")
	pan.name_box.text = "Test brush 7f3"
	await click(pan.find_child("btn_presets_save", true, false))
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(BrushPresets.USER))
	var back := {}
	if d is Dictionary:
		for p in d.get("presets", []):
			if p.get("name", "") == "Test brush 7f3":
				back = BrushPresets.clean(p)
	var file_eq := not back.is_empty()
	for k in BrushPresets.FIELDS:
		file_eq = file_eq and back.get(k) == mine[k]
	var listed := not row("Test brush 7f3").is_empty()
	await click(row("Grab large")["btn"])
	var moved_off := not fields_eq(mine)
	if listed:
		await click(row("Test brush 7f3")["btn"])
	var again := fields_eq(mine)
	pan.save_current("Test brush 7f3")
	var count := BrushPresets.user_presets().filter(func(e): return e["name"] == "Test brush 7f3").size()
	ok(file_eq and listed and moved_off and again and count == 1,
		"(3) user preset: from the file == %s (radius %s strength %s spacing %s); listed %s; another preset changed the brush %s, picking it back == %s (%s); saved twice, %d kept" % [
		file_eq, back.get("radius"), back.get("strength"), back.get("spacing"), listed, moved_off, again, diff_words(mine), count])
	# 4 favourites
	await click(row("Pinch fine")["star"])
	var fav_in := BrushPresets.favourites().has("Pinch fine") and FileAccess.get_file_as_string(BrushPresets.FAVS).contains("Pinch fine")
	var top := String(pan.entries[0]["name"]) if not pan.entries.is_empty() else ""
	var first_text := (pan.list.get_child(0).get_child(0) as Button).text
	await click(row("Pinch fine")["star"])
	var fav_out := not BrushPresets.favourites().has("Pinch fine") and FileAccess.file_exists(BrushPresets.FAVS)
	ok(fav_in and top == "Pinch fine" and first_text == "Pinch fine" and fav_out,
		"(4) favourites: starred -> on disk %s, top of the list %s (first row %s); unstarred -> off disk %s" % [fav_in, top, first_text, fav_out])
	# 5 thumbnails
	var lib := pan.lib
	var clay := BrushPresets.find("Clay buildup")
	var smooth := BrushPresets.find("Smooth soft")
	var maskp := BrushPresets.find("Mask paint")
	var t1: Texture2D = await lib.thumb(clay)
	var t2: Texture2D = await lib.thumb(smooth)
	var t3: Texture2D = await lib.thumb(maskp)
	var i1 := t1.get_image() if t1 != null else Image.create(1, 1, false, Image.FORMAT_RGB8)
	var i2 := t2.get_image() if t2 != null else i1
	var i3 := t3.get_image() if t3 != null else i1
	i1.save_png(tmp("brush_clay.png"))
	i3.save_png(tmp("brush_mask.png"))
	var mean := Color(0, 0, 0)
	var n := float(i1.get_width() * i1.get_height())
	for y in i1.get_height():
		for x in i1.get_width():
			var c := i1.get_pixel(x, y)
			mean += Color(c.r / n, c.g / n, c.b / n, 0)
	var var_ := 0.0
	var md := 0.0
	var bias1 := 0.0
	var bias3 := 0.0
	for y in i1.get_height():
		for x in i1.get_width():
			var c := i1.get_pixel(x, y)
			var_ += pow(dist(c, mean), 2) / n
			md += dist(c, i2.get_pixel(x, y)) / n
			bias1 += (c.b - c.r) / n
			bias3 += (i3.get_pixel(x, y).b - i3.get_pixel(x, y).r) / n
	var sd := sqrt(var_)
	var cover := dist(i1.get_pixel(32, 32), Color(0.13, 0.14, 0.16))
	var cached := FileAccess.file_exists(BrushPresets.cache_path(BrushPresets.key_of(clay)))
	var r0 := lib.renders
	var mem := await lib.thumb(clay)
	var mem_hit := mem == t1 and lib.renders == r0
	lib.forget()
	var dh := lib.disk_hits
	var disk := await lib.thumb(clay)
	var disk_hit := disk != null and lib.renders == r0 and lib.disk_hits == dh + 1
	ok(i1.get_size() == Vector2i(64, 64) and sd > 0.03 and cover > 0.1 and md > 0.01 and bias3 - bias1 > 0.02 and cached and mem_hit and disk_hit,
		"(5) thumbnails: %s, colour sd %.3f, centre vs background %.2f; clay vs smooth mean distance %.3f; mask bluer by %.3f; cached %s, memory hit %s, disk hit %s (%s)" % [
		i1.get_size(), sd, cover, md, bias3 - bias1, cached, mem_hit, disk_hit, tmp("brush_clay.png")])
	# 6 placement
	pan.close()
	await idle(2)
	await key(KEY_B)
	await idle(4)
	var all_pics := true
	for k in pan.rows:
		all_pics = all_pics and (pan.rows[k]["btn"] as Button).icon != null
	if not all_pics:   # the thumbnails come in one by one; give them a moment
		for t in 60:
			await idle(2)
			all_pics = true
			for k in pan.rows:
				all_pics = all_pics and (pan.rows[k]["btn"] as Button).icon != null
			if all_pics:
				break
	var pr := pan.get_global_rect()
	var cl: Rect2 = m.nav_clear_rect()
	var sr: Rect2 = ui.matcap.strip.get_global_rect()
	var lo := Vector2(INF, INF)
	var hi := -lo
	for dir in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.FORWARD, Vector3.BACK]:
		var q := cam.unproject_position(wc + dir * KMeshSculptUI.R)
		lo = lo.min(q)
		hi = hi.max(q)
	var sph := Rect2(lo, hi - lo)
	var img := await shot()
	img.save_png(tmp("brushpreset_ui.png"))
	var was_open := pan.visible
	await key(KEY_B)
	var shut := not pan.visible
	var ids := PackedInt32Array()
	var w := PackedFloat32Array()
	for v in 40:
		ids.append(v)
		w.append(1.0)
	KMeshMask.paint(ui.mesh, ids, w, 1.0, 1.0)   # a mask for the blur to spread
	var mk0 := KMeshMask.values(ui.mesh).duplicate()
	await key(KEY_B, true)
	var blurred: bool = KMeshMask.values(ui.mesh) != mk0 and not pan.visible
	await key(KEY_B)
	await key(KEY_ESCAPE)
	await idle(3)
	var gone := not pan.visible
	ok(was_open and cl.encloses(pr) and not pr.intersects(sr) and not pr.intersects(sph) and all_pics and shut and blurred and gone,
		"(6) placement: panel %s inside the clear view %s %s, apart from the strip %s %s and the sphere %s %s; every row has its thumbnail %s; B shuts it %s; Shift+B blurs the mask %s; Esc closes it %s (shot %s)" % [
		pr, cl, cl.encloses(pr), sr, not pr.intersects(sr), sph, not pr.intersects(sph), all_pics, shut, blurred, gone, tmp("brushpreset_ui.png")])
