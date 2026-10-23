## godot --path . -s tests/matlib_test.gd     (ROADMAP_400 E02; needs a window: the pictures are rendered)
## The material library (scripts/material_library.gd, data/materials/library.json) and its picker
## (scripts/material_library_ui.gd, "Library..." on the Materials panel). Bars, stated before measuring:
##   1 PRESETS: the shipped file parses to >= 19 presets, every one named in the item is there (4 skins, cotton, denim,
##     canvas gi, brown + black leather, polished / brushed / blackened steel, rusted iron, oak, dark wood, bronze, gold,
##     rubber, plastic); every preset passes implausible(): metals metallic == 1 and linear F0 luminance in [0.5, 1.0]
##     with the base colour == f0 in sRGB within 1/255; dielectrics metallic == 0 and every albedo channel in 30..240 sRGB;
##     skin sss > 0. The check can fail: a metal with F0 0.2, a dielectric with a channel of 10 and skin without SSS are
##     each flagged
##   2 PICTURES: the steel sphere's picture is 64 x 64, its centre pixel differs from its corner (background) by > 0.1;
##     the steel and cotton pictures differ by a mean colour distance > 0.05 over the centre 24 x 24; the picture is cached
##     as user://matlib_thumbs/<key>.png; asked again it is a memory hit (no draw), after forget() a disk hit (no draw)
##   3 APPLY: "Polished steel" applied to the picked slot of the cube makes the slot == the preset's slot exactly (every
##     field), is ONE undo step, Ctrl+Z (a real key) gives the old slot back ==, redo the steel again ==
##   4 USER LIBRARY: "Save current slot to library" with a slot of non-round values: user_presets() gives it back == ;
##     the shipped file's hash is unchanged; the grid shows it under the search "mine"; a second save of the same name
##     replaces it (count stays 1). The user's own library file is put back as it was afterwards
##   5 PLACEMENT: the picker is visible, wholly inside the window and the clear view, and its rect does not intersect the
##     Materials panel's nor the Add primitive panel's; the grid shows every preset with a picture; the search "steel"
##     leaves exactly the 3 steels; leaving the cube closes it
extends SceneTree

var fails := 0
var m: Node
var ui: KMeshEditUI
var pan: KMeshMaterialPanel
const NEED := ["Skin (light)", "Skin (medium)", "Skin (brown)", "Skin (deep)", "Cotton", "Denim", "Canvas gi", "Leather (brown)",
	"Leather (black)", "Polished steel", "Brushed steel", "Blackened steel", "Rusted iron", "Oak", "Dark wood", "Bronze", "Gold",
	"Rubber", "Plastic"]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func dist(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2))


func key(k: int, ctrl := false, shift := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.pressed = down
		e.ctrl_pressed = ctrl
		e.shift_pressed = shift
		root.push_input(e)
		await process_frame
	await idle(2)


func mean_dist(a: Image, b: Image, half: int) -> float:
	var c := a.get_size() / 2
	var s := 0.0
	var n := 0
	for y in range(c.y - half, c.y + half):
		for x in range(c.x - half, c.x + half):
			s += dist(a.get_pixel(x, y), b.get_pixel(x, y))
			n += 1
	return s / n


func _init() -> void:
	# keep the user's own library: the test writes to it
	var had_user := FileAccess.file_exists(MaterialLibrary.USER)
	var user_was := FileAccess.get_file_as_string(MaterialLibrary.USER) if had_user else ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MaterialLibrary.USER))

	# 1 PRESETS
	var ps := MaterialLibrary.shipped()
	var names := []
	for e in ps:
		names.append(e["name"])
	var missing := NEED.filter(func(n): return not names.has(n))
	ok(ps.size() >= 19 and missing.is_empty(), "1a %d shipped presets parse; missing from the item's list: %s" % [ps.size(), missing])
	var bad := []
	var nmetal := 0
	var f0_ok := true
	for e in ps:
		var why := MaterialLibrary.implausible(e)
		if why != "":
			bad.append("%s: %s" % [e["name"], why])
		if e["f0"] != null:
			nmetal += 1
			var want := Color(e["f0"][0], e["f0"][1], e["f0"][2]).linear_to_srgb()
			var got: Color = e["slot"]["albedo"]
			f0_ok = f0_ok and absf(want.r - got.r) <= 1.0 / 255 and absf(want.g - got.g) <= 1.0 / 255 and absf(want.b - got.b) <= 1.0 / 255 and e["slot"]["metallic"] == 1.0
	ok(bad.is_empty(), "1b every preset is plausible (metals metallic 1, F0 luminance 0.5..1; dielectrics metallic 0, albedo 30..240 sRGB; skin SSS on): %s" % (bad if not bad.is_empty() else "all %d" % ps.size()))
	ok(nmetal == 4 and f0_ok, "1c %d metals (bar 4: two steels, bronze, gold), base colour = chart F0 in sRGB within 1/255" % nmetal)
	var skins := ps.filter(func(e): return e["group"] == "skin")
	ok(skins.size() == 4 and skins.all(func(e): return e["slot"]["sss"] > 0.0), "1d 4 skin tones, subsurface on: %s" % [skins.map(func(e): return "%s sss %.2f" % [e["name"], e["slot"]["sss"]])])
	var fake_metal := MaterialLibrary.preset({"name": "x", "f0": [0.2, 0.2, 0.2]})
	var fake_diel := MaterialLibrary.preset({"name": "y", "albedo": [10, 120, 120]})
	var fake_skin := MaterialLibrary.preset({"name": "z", "group": "skin", "albedo": [200, 150, 120]})
	var w1 := MaterialLibrary.implausible(fake_metal)
	var w2 := MaterialLibrary.implausible(fake_diel)
	var w3 := MaterialLibrary.implausible(fake_skin)
	ok(w1 != "" and w2 != "" and w3 != "", "1e the check can fail: F0 0.2 metal '%s'; channel 10 '%s'; skin without SSS '%s'" % [w1, w2, w3])

	# the app, the cube
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._kmesh_edit_start()
	await idle(3)
	ui = m.kmed
	pan = ui.mat_panel
	pan.add_slot({"name": "Before", "albedo": Color(0.3, 0.6, 0.2), "roughness": 0.77, "metallic": 0.0, "sss": 0.13})
	await idle(3)
	var lp := pan.open_library()
	await idle(3)

	# 2 PICTURES
	var steel := MaterialLibrary.find("Polished steel")
	var cotton := MaterialLibrary.find("Cotton")
	var lib := lp.lib
	var k_steel := MaterialLibrary.key_of(steel["slot"])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MaterialLibrary.cache_path(k_steel)))
	lib.forget()
	var r0 := lib.renders
	var ts := await lib.thumb(steel["slot"])
	var tc := await lib.thumb(cotton["slot"])
	var is_ := ts.get_image() if ts != null else null
	var ic := tc.get_image() if tc != null else null
	ok(is_ != null and is_.get_size() == Vector2i(64, 64) and lib.renders > r0, "2a the steel picture was drawn: %s (%d draws)" % [is_.get_size() if is_ != null else "null", lib.renders - r0])
	var cen: Color = is_.get_pixel(32, 32) if is_ != null else Color.BLACK
	var cor: Color = is_.get_pixel(1, 1) if is_ != null else Color.BLACK
	ok(is_ != null and dist(cen, cor) > 0.1, "2b a sphere is in it: centre %s vs corner %s, distance %.3f > 0.1" % [cen, cor, dist(cen, cor)])
	var md := mean_dist(is_, ic, 12) if is_ != null and ic != null else 0.0
	ok(md > 0.05, "2c steel and cotton spheres differ: mean colour distance %.3f over the centre 24 x 24 (bar > 0.05)" % md)
	ok(FileAccess.file_exists(MaterialLibrary.cache_path(k_steel)), "2d cached as %s" % MaterialLibrary.cache_path(k_steel))
	var r1 := lib.renders
	var ts2 := await lib.thumb(steel["slot"])
	ok(ts2 == ts and lib.renders == r1, "2e asked again: the same texture from memory, no draw (%d)" % (lib.renders - r1))
	lib.forget()
	var d0 := lib.disk_hits
	var ts3 := await lib.thumb(steel["slot"])
	ok(ts3 != null and lib.renders == r1 and lib.disk_hits == d0 + 1, "2f after forget(): read from the disk cache (%d disk hit, %d draws)" % [lib.disk_hits - d0, lib.renders - r1])
	is_.save_png(OS.get_environment("TMP").path_join("matlib_steel.png") if OS.get_environment("TMP") != "" else "user://matlib_steel.png")

	# 3 APPLY
	var mesh: KMesh = ui.mesh
	pan.cur = 0
	var old: Dictionary = mesh.materials[0].duplicate()
	var n0: int = ui.undo.steps.size()
	lp.apply(steel)
	await idle(2)
	ok(mesh.materials[0] == steel["slot"] and ui.undo.steps.size() == n0 + 1,
		"3a 'Polished steel' applied: slot == preset (metallic %.2f, roughness %.2f, albedo %s), %d undo step" % [mesh.materials[0]["metallic"], mesh.materials[0]["roughness"], mesh.materials[0]["albedo"], ui.undo.steps.size() - n0])
	await key(KEY_Z, true)
	ok(mesh.materials[0] == old and ui.undo.steps.size() == n0, "3b Ctrl+Z gives the old slot back exactly ('%s')" % mesh.materials[0]["name"])
	await key(KEY_Z, true, true)
	ok(mesh.materials[0] == steel["slot"], "3c redo: steel again")
	var sm: Mesh = (ui.view.get_node("surf") as MeshInstance3D).mesh
	var mt := sm.surface_get_material(0) as StandardMaterial3D if sm != null and sm.get_surface_count() > 0 else null
	ok(mt != null and mt.metallic == 1.0 and is_equal_approx(mt.roughness, steel["slot"]["roughness"]), "3d the view's surface wears it (metallic %s)" % (mt.metallic if mt != null else "-"))

	# 4 USER LIBRARY
	var sha0 := FileAccess.get_sha256(MaterialLibrary.SHIPPED)
	pan.set_field(0, "name", "My test bronze")
	pan.set_field(0, "albedo", Color(0.613, 0.4271, 0.2219, 1.0))
	pan.set_field(0, "roughness", 0.3731)
	pan.set_field(0, "sss", 0.0917)
	var mine: Dictionary = mesh.materials[0].duplicate()
	ok(lp.save_current(), "4a Save current slot to library")
	var up := MaterialLibrary.user_presets()
	ok(up.size() == 1 and up[0]["slot"] == mine and up[0]["user"], "4b user_presets() gives it back == (%s)" % ("same" if up.size() == 1 and up[0]["slot"] == mine else str(up)))
	ok(FileAccess.get_sha256(MaterialLibrary.SHIPPED) == sha0 and MaterialLibrary.shipped().size() == ps.size(), "4c the shipped file is untouched (hash, %d presets)" % ps.size())
	lp.search.text = "mine"
	lp.fill()
	await idle(2)
	ok(lp.grid.item_count == 1 and lp.grid.get_item_text(0).begins_with("My test bronze"), "4d the grid under 'mine': %s" % [range(lp.grid.item_count).map(func(i): return lp.grid.get_item_text(i))])
	pan.set_field(0, "roughness", 0.5)
	lp.save_current()
	up = MaterialLibrary.user_presets()
	ok(up.size() == 1 and is_equal_approx(up[0]["slot"]["roughness"], 0.5), "4e a second save of the same name replaces it (%d entry, roughness %.2f)" % [up.size(), up[0]["slot"]["roughness"] if up.size() > 0 else -1.0])

	# 5 PLACEMENT
	lp.search.text = ""
	lp.fill()
	for i in 600:
		await process_frame
		var all_icons := true
		for j in lp.grid.item_count:
			all_icons = all_icons and lp.grid.get_item_icon(j) != null
		if all_icons:
			break
	await idle(4)
	var nic := 0
	for j in lp.grid.item_count:
		nic += 1 if lp.grid.get_item_icon(j) != null else 0
	ok(lp.grid.item_count == ps.size() + 1 and nic == lp.grid.item_count, "5a the grid shows %d presets (%d shipped + 1 mine), %d with a picture" % [lp.grid.item_count, ps.size(), nic])
	var vr := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var lr := lp.get_global_rect()
	var mr := pan.get_global_rect()
	var pr := ui.prim_panel.get_global_rect()
	var cl: Rect2 = m.nav_clear_rect()
	ok(lp.is_visible_in_tree() and vr.encloses(lr) and cl.grow(1.0).encloses(lr) and lr.size.x > 200 and lr.size.y > 150,
		"5b the picker is on screen %s, inside the window %s and the clear view %s" % [lr, vr, cl])
	ok(pan.is_visible_in_tree() and not lr.intersects(mr) and not (ui.prim_panel.visible and lr.intersects(pr)),
		"5c it does not cover the Materials panel %s nor the Add primitive panel %s" % [mr, pr])
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("TMP").path_join("matlib_ui.png") if OS.get_environment("TMP") != "" else "user://matlib_ui.png")
	lp.search.text = "steel"
	lp.fill()
	await idle(2)
	var shown := range(lp.grid.item_count).map(func(i): return lp.grid.get_item_text(i))
	ok(shown.size() == 3 and shown.has("Polished steel") and shown.has("Brushed steel") and shown.has("Blackened steel"), "5d search 'steel': %s" % [shown])
	ui.stop()
	await idle(3)
	ok(not lp.visible, "5e leaving the cube closes the picker")

	# the user's own library back as it was
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MaterialLibrary.USER))
	if had_user:
		var f := FileAccess.open(MaterialLibrary.USER, FileAccess.WRITE)
		f.store_string(user_was)
		f.close()

	print("MATLIB: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
