extends SceneTree
## godot --path . --position 4000,4000 -s tests/s194_test.gd   (Friday plan 194: Parametric families; scripts/build/part_family.gd; needs the CAD DLL)
## A stool (4 legs pulled up 400 mm, a seat plane on top of the legs, a 300 x 300 x 30 seat, a 6 mm hole through it) saved in My parts, then
## right-click its card > Make a family... > Overall height, "30 / 45 / 60 cm", Save the family (real clicks). Everything is measured from the files
## re-read from disk and replayed (kernel mesh), never from the code's own variables.
##   F1 three new entries on disk (Stool 30 cm, 45 cm, 60 cm) plus the original, each with a picture
##   F2 their heights replay to 300.0 / 450.0 / 600.0 mm within 0.05
##   F3 the seat is 30.00 mm thick in all three (the hole wall's height), not scaled
##   F4 the hole is 6.00 mm across in all three (vertex radius around the hole axis)
##   F5 the original is unchanged (byte-identical file)
##   F6 no undo step was pushed
##   F7 a step-distance family (the legs' distance, Small 0.5, Large 1.5 as factors) gives 200 / 600 mm legs, the seat plane follows
##   F8 a bad size line says why and saves nothing
## shots: C:/Temp/claude/s194/*.png
const SHOT := "C:/Temp/claude/s194"
const DIRT := "user://s194_test"
var fails := 0
var m: Node
var lib: ObjectLibrary
const PF := preload("res://scripts/build/part_family.gd")


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func ev_mouse(p: Vector2, down: bool, btn := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = down
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if btn == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	root.push_input(e, true)
	await process_frame


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func reveal(c: Control) -> void:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			(p as ScrollContainer).ensure_control_visible(c)
		p = p.get_parent()
	await idle(2)


func click_ctl(c: Control, btn := MOUSE_BUTTON_LEFT) -> void:
	await reveal(c)
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true, btn)
	await ev_mouse(p, false, btn)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func tile(id: String) -> Button:
	return lib.find_child("tile_" + id.replace(":", "_"), true, false) as Button


func cat_btn(c: String) -> Button:
	for b in lib._cat_btns:
		if String((b as Button).get_meta("cat")) == c:
			return b
	return null


func stool() -> Dictionary:
	var rec := Part.make("Stool")
	var legs := []
	for c in [[-140, -140], [110, -140], [-140, 110], [110, 110]]:
		legs.append({"k": "rect", "a": [c[0], c[1]], "b": [c[0] + 30, c[1] + 30]})
	var s1 := Part.new_feature(rec, "sketch", {"plane": "top", "ents": legs, "dims": []})
	rec["features"].append(s1)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": s1["id"], "dist": 400.0, "both": false, "op": "new"}))
	var pl := Part.new_feature(rec, "plane", {"from": "top", "mm": 400.0})
	rec["features"].append(pl)
	var s2 := Part.new_feature(rec, "sketch", {"plane": pl["id"], "ents": [{"k": "rect", "a": [-150, -150], "b": [150, 150]}], "dims": []})
	rec["features"].append(s2)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": s2["id"], "dist": 30.0, "both": false, "op": "join"}))
	var s3 := Part.new_feature(rec, "sketch", {"plane": pl["id"], "ents": [{"k": "circle", "c": [0, 0], "r": 3.0}], "dims": []})
	rec["features"].append(s3)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": s3["id"], "dist": 40.0, "both": false, "op": "cut"}))
	return rec


## height mm, the hole wall's height (= seat thickness) and the hole's diameter, from the replayed kernel mesh
func measure(rec: Dictionary) -> Dictionary:
	var r := Part.replay(rec)
	if r["mesh"] == null:
		return {}
	var rmin := 1e9
	var rmax := 0.0
	var ylo := 1e9
	var yhi := -1e9
	var mesh: ArrayMesh = r["mesh"]
	for s in mesh.get_surface_count():
		for v in (mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			var rad := Vector2(v.x, v.z).length() * 1000.0
			if rad < 4.0:
				rmin = minf(rmin, rad)
				rmax = maxf(rmax, rad)
				ylo = minf(ylo, v.y * 1000.0)
				yhi = maxf(yhi, v.y * 1000.0)
	return {"h": (r["aabb"] as AABB).size.y * 1000.0, "seat": yhi - ylo, "hole": rmin + rmax, "bodies": int(r["bodies"])}


func disk(nm: String) -> Dictionary:
	return MyParts.load_part(nm)


func menu_ctl(nm: String) -> Control:
	var menu := root.find_child("library_collection_menu", true, false)
	if menu == null:
		menu = root.find_child("library_family_dialog", true, false)
	return menu.find_child(nm, true, false) as Control if menu != null else null


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	MyParts.dir = DIRT
	var ad := ProjectSettings.globalize_path(DIRT)
	for d in [ad + "/versions", ad]:
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d + "/" + f)
	DirAccess.make_dir_recursive_absolute(ad)
	m.easy.set_on(true, false)
	m._new_scene()
	await idle(4)
	var rec := stool()
	await m.bld._save_part(rec)
	await idle(4)
	var m0 := measure(disk("Stool"))
	print("diag original ", m0)
	ok(not m0.is_empty() and absf(float(m0["h"]) - 430.0) < 0.05, "0 the stool replays: height %.2f (want 430 = 400 legs + 30 seat), %s bodies" % [float(m0.get("h", -1)), str(m0.get("bodies"))])
	var orig_text := FileAccess.get_file_as_string(MyParts.path_of("Stool"))

	m._library_toggle()
	await idle(3)
	lib = m.ui_library
	lib.recent_file = "user://s194_recent.json"
	lib.clear_recent()
	lib.more = lib.extra_items()
	lib.open()
	await idle(3)
	await click_ctl(cat_btn("My parts"))
	await idle(3)
	await lib.thumbs.settle()
	var ub: int = m.undo.size()

	await click_ctl(tile("mypart:saved:Stool"), MOUSE_BUTTON_RIGHT)
	await shot("1_menu")
	await click_ctl(menu_ctl("menu_family"))
	await idle(3)
	await shot("2_dialog")
	var vary := menu_ctl("family_vary") as OptionButton
	var le := menu_ctl("family_sizes") as LineEdit
	var sv := menu_ctl("family_save") as Button
	var note := menu_ctl("family_note") as Label
	ok(vary != null and le != null and sv != null and vary.item_count >= 3 and vary.get_item_text(0) == "Overall height", "0 dialog has the vary list (%d items, first %s), sizes box and save button" % [vary.item_count if vary else -1, vary.get_item_text(0) if vary else "-"])
	le.text = "tall please"
	await click_ctl(sv)
	await idle(3)
	ok(note.text.begins_with("I could not read") and MyParts.list().size() == 1, "F8 bad line says: \"%s\"; entries on disk %d (want 1)" % [note.text, MyParts.list().size()])
	le.text = "30 / 45 / 60 cm"
	await click_ctl(sv)
	for i in 120:
		if note.text.begins_with("Saved") or note.text.contains("could not") or note.text.contains("lower"):
			break
		await idle(5)
	await idle(10)
	await lib.thumbs.settle()
	await shot("3_saved")
	var note_text := note.text
	await click_ctl(menu_ctl("family_close"))
	await idle(3)
	await lib.thumbs.settle()
	await shot("4_cards")
	print("diag note: ", note_text)
	var names := []
	for pt in MyParts.list():
		names.append(String(pt["name"]))
	names.sort()
	var pics := 0
	for nm in names:
		if FileAccess.file_exists(ProjectSettings.globalize_path(MyParts.thumb_of(nm))):
			pics += 1
	ok(names == ["Stool", "Stool 30 cm", "Stool 45 cm", "Stool 60 cm"] and pics == 4, "F1 on disk: %s, %d pictures (want the original + 3, 4 pictures)" % [str(names), pics])
	for pair in [["Stool 30 cm", 300.0], ["Stool 45 cm", 450.0], ["Stool 60 cm", 600.0]]:
		var mm := measure(disk(pair[0]))
		print("diag ", pair[0], " ", mm)
		ok(not mm.is_empty() and absf(float(mm["h"]) - float(pair[1])) <= 0.05, "F2 %s is %.3f mm tall (want %.1f)" % [pair[0], float(mm.get("h", -1)), float(pair[1])])
		ok(not mm.is_empty() and absf(float(mm["seat"]) - 30.0) <= 0.05, "F3 %s seat (hole wall) %.3f mm (want 30.00, not scaled)" % [pair[0], float(mm.get("seat", -1))])
		ok(not mm.is_empty() and absf(float(mm["hole"]) - 6.0) <= 0.01, "F4 %s hole %.3f mm across (want 6.00)" % [pair[0], float(mm.get("hole", -1))])
	ok(FileAccess.get_file_as_string(MyParts.path_of("Stool")) == orig_text, "F5 the original file is byte-identical")
	ok(m.undo.size() == ub, "F6 undo steps %d -> %d (saving files: none)" % [ub, m.undo.size()])

	var legs_key := ""
	for x in PF.options(rec):
		if String(x["label"]).ends_with("distance"):
			legs_key = String(x["key"])
			break
	var res: Dictionary = await PF.make(m, "Stool", legs_key, "Small 0.5, Large 1.5", "cm")
	ok(String(res["err"]) == "" and res["saved"] == ["Stool Small", "Stool Large"], "F7 saved %s err \"%s\"" % [str(res["saved"]), res["err"]])
	var hs := measure(disk("Stool Small"))
	var hl := measure(disk("Stool Large"))
	ok(not hs.is_empty() and not hl.is_empty() and absf(float(hs["h"]) - 230.0) <= 0.05 and absf(float(hl["h"]) - 630.0) <= 0.05 and absf(float(hs["seat"]) - 30.0) <= 0.05 and absf(float(hl["hole"]) - 6.0) <= 0.01,
		"F7 legs 200 / 600: heights %s / %s (want 230 / 630, the seat plane followed), seat %s, hole %s" % [str(hs.get("h")), str(hl.get("h")), str(hs.get("seat")), str(hl.get("hole"))])

	for d in [ad + "/versions", ad]:
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d + "/" + f)
	print("s194: %d fail" % fails)
	quit(1 if fails > 0 else 0)
