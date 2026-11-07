## godot --path . -s tests/pickers_test.gd     (lane L135: the small UI gaps left by the tablet, weapon-parts and settings2 lanes; boots main.tscn)
## Bars, written BEFORE the implementation and never moved after a run (scripts/pen_picker.gd, scripts/weapon_parts_ui.gd, scripts/access_prefs.gd):
##   1 DEFAULT  a fresh profile (no prefs file): every page's pen_target "strength", sculpt pen_tilt false, main.pie_on false,
##              WeaponParts.model_name "sword"; an untouched grip-book command writes model_sword with the role-default materials
##   2 EXIST    controls by name: sculpt_pen_target + sculpt_pen_tilt, vpaint_pen_target, wpaint_pen_target, sculpt_pie, and the weapon
##              panel wpart_name, wpart_mat_grip/guard/blade/pommel (each offers every KMeshMeasure.MATERIALS name), wpart_book_btn
##   3 LIVE     a real click / selection changes the live value, read from the page: pen_target and its KMeshPen (_pen.target) take
##              radius / both / off / strength on sculpt, vertex+texture paint and weight paint; the tilt check sets pen_tilt and _pen.tilt_on
##   4 WEAPON   name "katana", blade aluminium, grip pine, guard glass, pommel concrete, then "add to grip book": the entry is in
##              model_katana (and model_sword is untouched); each part names the chosen material; every part's mass_kg = its closed-mesh
##              volume x the NEW density (KMeshMeasure.MATERIALS) to 1e-9 relative, and the total mass is the sum of the four
##   5 PIE      sculpt_pie click -> main.pie_on true; the Settings settings_pie shows it; a click on settings_pie off -> sculpt_pie off
##              and main.pie_on false; the choice is in the prefs file after each change
##   6 SAVED    the prefs file (KINE_ACCESS_FILE, isolated) holds every choice made above
##   7 RESTART  main freed, statics reset, a NEW main on the same file: every picker shows its saved choice AND the page's live value
##              equals it, pie_on true, the weapon panel shows name + materials, an untouched "add to grip book" writes the same entry
##   8 PLANT    the same checkers fed a wrong expectation must FAIL: a blade mass computed with steel's density where aluminium was
##              chosen (rel. error > 1e-3), and a pen_target check expecting "radius" while the page holds "both"
## Isolation: wtest gives the run its own APPDATA; KINE_ACCESS_FILE and GripBook.dir name test files; Nick's own files are never touched.
extends SceneTree

const CFG := "user://pickers_access.cfg"
const BOOK := "user://pickers_book"
const ROLES := ["grip", "guard", "blade", "pommel"]
var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func node(nm: String) -> Control:
	return root.find_child(nm, true, false) as Control


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


## a real click when the control is on screen, else the same signal its click raises
func click_ctl(c: Control) -> void:
	if c.is_visible_in_tree() and c.get_global_rect().size.x > 2.0:
		var p := c.get_global_rect().get_center()
		await ev_mouse(p, true)
		await ev_mouse(p, false)
	elif c is BaseButton:
		var b := c as BaseButton
		if b.toggle_mode:
			b.button_pressed = not b.button_pressed
		else:
			b.pressed.emit()
	await idle(3)


func pick(o: OptionButton, idx: int) -> void:
	if o.is_visible_in_tree():
		await click_ctl(o)
		o.get_popup().hide()
	o.select(idx)
	o.item_selected.emit(idx)
	await idle(3)


func pick_text(o: OptionButton, text: String) -> void:
	for i in o.item_count:
		if o.get_item_text(i) == text:
			await pick(o, i)
			return
	ok(false, "option '%s' missing in %s" % [text, o.name])


func fresh() -> void:
	if m != null:
		root.remove_child(m)
		m.free()
		await idle(3)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false


func sword() -> KMesh:
	var vs := PackedVector3Array()
	var fs: Array = []
	var sizes := {"pommel": Vector3(0.04, 0.03, 0.04), "grip": Vector3(0.03, 0.12, 0.03), "guard": Vector3(0.12, 0.02, 0.03), "blade": Vector3(0.05, 0.8, 0.006)}
	var ys := {"pommel": 0.015, "grip": 0.09, "guard": 0.16, "blade": 0.57}
	var tags := {}
	for r in ["pommel", "grip", "guard", "blade"]:
		var pm: KMesh = KMeshPrims.cube(sizes[r], 1)
		var base := vs.size()
		for v in pm.verts:
			vs.append(Vector3(v.x, v.y + float(ys[r]), v.z))
		for f in pm.faces:
			var nf := PackedInt32Array()
			for i in f:
				nf.append(int(i) + base)
			tags[fs.size()] = r
			fs.append(nf)
	var km := KMesh.new().from_arrays(vs, fs)
	WeaponParts.ensure(km)
	for fi in tags:
		WeaponParts.tag(km, PackedInt32Array([fi]), tags[fi])
	return km


## load the tagged sword into the model editor
func model_sword() -> void:
	m._kmesh_edit_start()
	await idle(3)
	var ed = m.kmed
	var sw := sword()
	var km: KMesh = ed.mesh
	km.verts = sw.verts
	km.faces = sw.faces
	km.attrs = sw.attrs
	km.rebuild()
	ed.view.mark_dirty()
	await idle(2)


func pen_ok(page, want: String) -> bool:
	return String(page.get("pen_target")) == want and String(page.get("_pen").target) == want


func targets_cycle(label: String, page, picker_name: String) -> void:
	var o := node(picker_name) as OptionButton
	if o == null:
		ok(false, "%s: %s missing" % [label, picker_name])
		return
	var good := true
	var seen := []
	for t in ["radius", "both", "off", "strength"]:
		await pick_text(o, t)
		good = good and pen_ok(page, t)
		seen.append(String(page.get("pen_target")))
	ok(good, "3 %s: selecting radius / both / off / strength moves pen_target and the page's KMeshPen: %s" % [label, seen])


func book_entry(kind: String) -> Dictionary:
	return GripBook.find(kind, WeaponParts.ENTRY)


## each part's mass = closed-mesh volume x the density of the material the entry names, to 1e-9; the worst relative error, 9 if wrong
func mass_err(e: Dictionary, km: KMesh, want: Dictionary) -> float:
	var worst := 0.0
	var tot := 0.0
	var ps: Dictionary = e.get("parts", {})
	for r in ROLES:
		if not ps.has(r):
			return 9.0
		var p: Dictionary = ps[r]
		if String(p.get("material", "")) != String(want[r]):
			return 9.0
		var vol := float(KMeshMeasure.volume(WeaponParts.cut(km, WeaponParts.faces_of(km, r)))["m3"])
		var kg := vol * float(KMeshMeasure.MATERIALS[want[r]]["kg_m3"])
		worst = maxf(worst, absf(float(p["mass_kg"]) - kg) / kg)
		tot += kg
	return maxf(worst, absf(float(e.get("mass_kg", 0.0)) - tot) / tot)


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	OS.set_environment("KINE_ACCESS_FILE", ProjectSettings.globalize_path(CFG))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	GripBook.dir = BOOK
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BOOK))
	for k in ["model_sword", "model_katana"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(GripBook.path_of(k)))
	await fresh()
	# ---- 1 / 2: defaults and existence
	m._sculpt_start()
	await idle(3)
	var sc: KMeshSculptUI = m.ksc
	var vp := KMeshVPaintUI.of(m)
	var wp := KMeshWPaintUI.of(m)
	ok(sc.pen_target == "strength" and not sc.pen_tilt and vp.pen_target == "strength" and wp.pen_target == "strength" and not m.pie_on and WeaponParts.model_name == "sword",
		"1 defaults: pen_target %s / %s / %s, tilt %s, pie_on %s, model_name %s" % [sc.pen_target, vp.pen_target, wp.pen_target, sc.pen_tilt, m.pie_on, WeaponParts.model_name])
	sc.stop()
	await idle(2)
	await model_sword()
	WeaponPartsUI.panel(m)
	vp.start()
	await idle(3)
	wp.panel.visible = true
	var names := ["sculpt_pen_target", "sculpt_pen_tilt", "vpaint_pen_target", "wpaint_pen_target", "sculpt_pie", "wpart_name", "wpart_book_btn"]
	for r in ROLES:
		names.append("wpart_mat_" + r)
	var missing := []
	for n in names:
		if node(n) == null:
			missing.append(n)
	ok(missing.is_empty(), "2 all controls exist (missing: %s)" % [missing])
	if not missing.is_empty():
		print("pickers: %d fails (controls missing)" % (fails + 1))
		quit(fails + 1)
		return
	var all_mats := true
	for r in ROLES:
		var o := node("wpart_mat_" + r) as OptionButton
		var have := []
		for i in o.item_count:
			have.append(o.get_item_text(i))
		for k in KMeshMeasure.MATERIALS:
			all_mats = all_mats and have.has(k)
		all_mats = all_mats and o.get_item_text(o.selected) == WeaponParts.DEFAULT_MAT[r]
	ok(all_mats, "2 every part picker offers all %d materials and shows the role default" % KMeshMeasure.MATERIALS.size())
	# ---- 1 again: an untouched book command is the old behaviour
	var km: KMesh = m.kmed.mesh
	await click_ctl(node("wpart_book_btn"))
	var e0 := book_entry("model_sword")
	var err0 := mass_err(e0, km, WeaponParts.DEFAULT_MAT) if not e0.is_empty() else 9.0
	ok(err0 < 1e-9, "1 untouched add-to-grip-book: model_sword with the role defaults, mass err %.8f" % err0)
	# ---- 4 weapon choices
	var le := node("wpart_name") as LineEdit
	le.text = "katana"
	le.text_changed.emit("katana")
	le.text_submitted.emit("katana")
	var want := {"blade": "aluminium", "grip": "pine", "guard": "glass", "pommel": "concrete"}
	for r in ROLES:
		await pick_text(node("wpart_mat_" + r) as OptionButton, want[r])
	await click_ctl(node("wpart_book_btn"))
	var e1 := book_entry("model_katana")
	var err1 := mass_err(e1, km, want) if not e1.is_empty() else 9.0
	ok(err1 < 1e-9, "4 katana in the book with blade aluminium / grip pine / guard glass / pommel concrete: mass = volume x new density, worst rel err %.8f" % err1)
	var e0b := book_entry("model_sword")
	ok(not e0b.is_empty() and mass_err(e0b, km, WeaponParts.DEFAULT_MAT) < 1e-9, "4 model_sword is untouched by the katana")
	# ---- 3 live pen pickers
	m.kmed.stop()
	m._sculpt_start()
	await idle(3)
	sc = m.ksc
	await targets_cycle("sculpt", sc, "sculpt_pen_target")
	await pick_text(node("sculpt_pen_target") as OptionButton, "both")
	var tl := node("sculpt_pen_tilt") as CheckBox
	await click_ctl(tl)
	ok(sc.pen_tilt and tl.button_pressed and sc._pen.tilt_on == true, "3 sculpt tilt click -> pen_tilt %s, KMeshPen.tilt_on %s" % [sc.pen_tilt, sc._pen.tilt_on])
	await targets_cycle("vertex/texture paint", vp, "vpaint_pen_target")
	await pick_text(node("vpaint_pen_target") as OptionButton, "radius")
	await targets_cycle("weight paint", wp, "wpaint_pen_target")
	await pick_text(node("wpaint_pen_target") as OptionButton, "off")
	# ---- 5 pie both ways
	var sp := node("sculpt_pie") as CheckBox
	await click_ctl(sp)
	var cf := ConfigFile.new()
	cf.load(CFG)
	ok(m.pie_on and sp.button_pressed and bool(cf.get_value("access", "pie", false)), "5 sculpt_pie click -> pie_on %s, saved %s" % [m.pie_on, cf.get_value("access", "pie", null)])
	m.start_screen.dirs_override = [BOOK]
	m.start_screen.show_screen()
	await idle(4)
	await click_ctl(node("settings_btn"))
	await idle(6)
	var sp2 := node("settings_pie") as CheckBox
	ok(sp2 != null and sp2.button_pressed, "5 Settings shows the pie on that the sculpt page set")
	if sp2 != null:
		await click_ctl(sp2)
	cf.load(CFG)
	ok(not m.pie_on and not sp.button_pressed and not bool(cf.get_value("access", "pie", true)), "5 settings_pie click off -> pie_on %s, sculpt_pie %s, saved %s" % [m.pie_on, sp.button_pressed, cf.get_value("access", "pie", null)])
	if sp2 != null:
		await click_ctl(sp2)   # on again for the save bar
	ok(m.pie_on and sp.button_pressed, "5 settings_pie click on -> sculpt_pie on %s" % sp.button_pressed)
	# ---- 6 SAVED
	cf.load(CFG)
	var keys := cf.get_section_keys("access") if cf.has_section("access") else PackedStringArray()
	ok(bool(cf.get_value("access", "pie", false)) and keys.size() >= 9, "6 prefs file holds the choices: %d keys %s" % [keys.size(), keys])
	var held := String(cf.get_value("access", "wp_name", "")) == "katana"
	for r in ROLES:
		held = held and String(cf.get_value("access", "wp_mat_" + r, "")) == want[r]
	ok(held, "6 weapon name + the four materials are in the file")
	# ---- 7 RESTART
	WeaponParts.model_name = "sword"
	WeaponParts.mats = {}
	await fresh()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(GripBook.path_of("model_katana")))
	m._sculpt_start()
	await idle(3)
	sc = m.ksc
	vp = KMeshVPaintUI.of(m)
	wp = KMeshWPaintUI.of(m)
	vp.start()
	await idle(3)
	wp.panel.visible = true
	ok(sc.pen_target == "both" and sc.pen_tilt and vp.pen_target == "radius" and wp.pen_target == "off" and m.pie_on,
		"7 restart: live pen_target %s / %s / %s, tilt %s, pie_on %s" % [sc.pen_target, vp.pen_target, wp.pen_target, sc.pen_tilt, m.pie_on])
	var o1 := node("sculpt_pen_target") as OptionButton
	var o2 := node("vpaint_pen_target") as OptionButton
	var o3 := node("wpaint_pen_target") as OptionButton
	ok(o1 != null and o2 != null and o3 != null and o1.get_item_text(o1.selected) == "both" and o2.get_item_text(o2.selected) == "radius" and o3.get_item_text(o3.selected) == "off"
		and (node("sculpt_pen_tilt") as CheckBox).button_pressed and (node("sculpt_pie") as CheckBox).button_pressed, "7 restart: the pickers SHOW the saved choices")
	ok(pen_ok(sc, "both") and pen_ok(vp, "radius") and pen_ok(wp, "off") and sc._pen.tilt_on, "7 restart: the pages' KMeshPen state agrees")
	sc.stop()
	await idle(2)
	await model_sword()
	WeaponPartsUI.panel(m)
	await idle(3)
	km = m.kmed.mesh
	var shows := (node("wpart_name") as LineEdit).text == "katana"
	for r in ROLES:
		var o := node("wpart_mat_" + r) as OptionButton
		shows = shows and o.get_item_text(o.selected) == want[r]
	ok(shows, "7 restart: the weapon panel shows katana + the four saved materials")
	await click_ctl(node("wpart_book_btn"))
	var e2 := book_entry("model_katana")
	var err2 := mass_err(e2, km, want) if not e2.is_empty() else 9.0
	ok(err2 < 1e-9, "7 restart: an untouched add-to-grip-book writes the katana entry again, worst rel err %.8f" % err2)
	# ---- 8 PLANT
	var steel_blade := float(KMeshMeasure.volume(WeaponParts.cut(km, WeaponParts.faces_of(km, "blade")))["m3"]) * float(KMeshMeasure.MATERIALS["steel"]["kg_m3"])
	var got_blade := float(((e2.get("parts", {}) as Dictionary).get("blade", {}) as Dictionary).get("mass_kg", 0.0))
	ok(absf(got_blade - steel_blade) / steel_blade > 1e-3, "8 PLANT: the blade mass with steel's density is %.2f%% off the aluminium entry, so the check can fail" % (absf(got_blade - steel_blade) / steel_blade * 100.0))
	ok(not pen_ok(sc, "radius"), "8 PLANT: pen_ok(page 'both', want 'radius') is false")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG))
	print("pickers: %d fails" % fails)
	quit(fails)
