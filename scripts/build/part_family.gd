## part_family.gd - PARAMETRIC FAMILIES (Friday plan 194): one saved part -> a small / medium / tall family. The maker picks which size to vary
## (the overall height, or one named step's distance), types the sizes ("30 / 45 / 60 cm", or "Small 0.7, Medium 1, Large 1.4" as factors of
## the size now) and each size is saved as its own My parts entry. Every version is a REPLAY of the record with the changed number, never a
## scaled mesh: the steps that depend on the varied size follow it (a plane standing on top of the varied extrude moves up with it), the
## others keep their numbers, so wall thickness and holes keep their size. Nothing in the scene changes, so there is no undo step.
## Opened from the right-click menu of a card in the library's My parts (a "Make a family" button, scripts/object_library.gd).
## Sizes: a number with cm / mm / m (or a bare number: the unit chosen in the dialog) is the size itself; a word with a bare number
## ("Small 0.7", "Large=1.4", "Tall x1.4") is a factor of the size now.
extends RefCounted

const MyPartsS := preload("res://scripts/build/myparts.gd")
const MeshExportS := preload("res://scripts/build/mesh_export.gd")
const HEIGHT := "height"
const MAX_SIZES := 12


## the sizes the dialog can vary: [{"key", "label"}] - the overall height (when some extrude moves it) and every extrude / plane step by name
static func options(rec: Dictionary) -> Array:
	var out: Array = []
	if not height_step(rec).is_empty():
		out.append({"key": HEIGHT, "label": "Overall height"})
	for f in rec.get("features", []):
		var t := String((f as Dictionary).get("t", ""))
		if t == "extrude":
			out.append({"key": String(f["id"]), "label": "%s distance" % String(f.get("name", f["id"]))})
		elif t == "plane":
			out.append({"key": String(f["id"]), "label": "%s height" % String(f.get("name", f["id"]))})
	return out


## the part's height in mm (the kernel's own bounding box, Y up); -1 when nothing is built
static func height_mm(rec: Dictionary) -> float:
	var r := Part.replay(rec)
	if r["mesh"] == null:
		return -1.0
	return (r["aabb"] as AABB).size.y / Part.MM


## the number a key stands for now (mm)
static func value_of(rec: Dictionary, key: String) -> float:
	if key == HEIGHT:
		return height_mm(rec)
	var f := Part.feature(rec, key)
	if String(f.get("t", "")) == "plane":
		return float(f.get("mm", 0.0))
	return float(f.get("dist", 0.0))


## the id of the step whose distance moves the overall height one for one (the first extrude that adds material and does), or ""
static func height_step(rec: Dictionary) -> String:
	var h0 := height_mm(rec)
	if h0 <= 0.0:
		return ""
	for f in rec.get("features", []):
		if String((f as Dictionary).get("t", "")) != "extrude" or String(f.get("op", "new")) == "cut":
			continue
		var tryr := _with_step(rec, String(f["id"]), float(f["dist"]) + 10.0)
		var h1 := height_mm(tryr)
		if h1 > 0.0 and absf((h1 - h0) / 10.0 - 1.0) < 0.05:
			return String(f["id"])
	return ""


## a copy of the record with step `id` at `val` mm; every plane that stood on top of the varied extrude (same base plane, at or above its top) moves by the change
static func _with_step(rec: Dictionary, id: String, val: float) -> Dictionary:
	var r := rec.duplicate(true)
	var feats: Array = r["features"]
	var i := Part.index_of(r, id)
	if i < 0:
		return r
	var f: Dictionary = feats[i]
	if String(f["t"]) == "plane":
		var old := float(f.get("mm", 0.0))
		f["mm"] = val
		_follow(feats, i, String(f.get("from", "front")), old, val - old)
	elif String(f["t"]) == "extrude":
		var old := float(f.get("dist", 0.0))
		var sk := Part.feature(r, String(f.get("sketch", "")))
		var base := 0.0
		var from := String(sk.get("plane", "front"))
		var pf := Part.feature(r, from)
		if String(pf.get("t", "")) == "plane":
			base = float(pf.get("mm", 0.0))
			from = String(pf.get("from", "front"))
		f["dist"] = val
		_follow(feats, i, from, base + old, val - old)
	return r


static func _follow(feats: Array, after: int, from: String, top: float, delta: float) -> void:
	for k in range(after + 1, feats.size()):
		var g: Dictionary = feats[k]
		if String(g.get("t", "")) == "plane" and String(g.get("from", "front")) == from and float(g.get("mm", 0.0)) >= top - 0.01:
			g["mm"] = float(g["mm"]) + delta


## the record at `target` mm for `key`: {"rec", "err"}. The overall height is solved on the step that moves it one for one (the measured result
## is checked: within 0.01 mm of the target, else err)
static func with_value(rec: Dictionary, key: String, target: float) -> Dictionary:
	if target <= 0.0:
		return {"rec": {}, "err": "a size must be above zero"}
	if key != HEIGHT:
		var r := _with_step(rec, key, target)
		return {"rec": r, "err": ""}
	var sid := height_step(rec)
	if sid == "":
		return {"rec": {}, "err": "no step of this part sets its height"}
	var d := float(Part.feature(rec, sid)["dist"])
	var r := rec
	for _i in 4:
		var h := height_mm(r)
		if absf(h - target) <= 0.005:
			return {"rec": r, "err": ""}
		d += target - h   # slope is 1 on this step
		if d <= 0.0:
			return {"rec": {}, "err": "%.1f mm is lower than the part can be built (the step would be below zero)" % target}
		r = _with_step(rec, sid, d)
	if absf(height_mm(r) - target) > 0.01:
		return {"rec": {}, "err": "could not reach %.1f mm" % target}
	return {"rec": r, "err": ""}


## "30 / 45 / 60 cm" -> [{"label": "30 cm", "mm": 300.0}, ...]; "Small 0.7, Medium 1, Large 1.4" -> factors of `now` mm.
## bare_unit: "cm" | "mm" | "m" for a number with no unit. {"sizes": [...], "err": ""}
static func parse_sizes(text: String, now: float, bare_unit: String) -> Dictionary:
	var out: Array = []
	var rx := RegEx.new()
	rx.compile("^(?:(.*?)\\s*[=:]?\\s+)?[x×]?\\s*(\\d+(?:[.,]\\d+)?)\\s*(mm|cm|m)?$")
	for tok in text.replace(";", ",").replace("/", ",").split(","):
		var t := String(tok).strip_edges()
		if t == "":
			continue
		var s := t.replace(" =", "=").replace("= ", "=")
		var m := rx.search(s)
		if m == null:
			var rx2 := RegEx.new()   # "Small=0.7", "x1.5" and "45" (no space) forms
			rx2.compile("^(.*?)[=:]?\\s*[x×]?(\\d+(?:[.,]\\d+)?)\\s*(mm|cm|m)?$")
			m = rx2.search(s)
		if m == null:
			return {"sizes": [], "err": "I could not read \"%s\". Type sizes like 30 / 45 / 60 cm, or Small 0.7, Medium 1, Large 1.4" % t}
		var nm := m.get_string(1).strip_edges().rstrip("=: ")
		var num := float(m.get_string(2).replace(",", "."))
		var unit := m.get_string(3)
		var mm := 0.0
		var label := ""
		if unit == "" and nm != "":
			mm = now * num
			label = nm
		else:
			var u := unit if unit != "" else bare_unit
			mm = num * (10.0 if u == "cm" else (1000.0 if u == "m" else 1.0))
			label = nm if nm != "" else "%s %s" % [m.get_string(2), u]
		if mm <= 0.0:
			return {"sizes": [], "err": "\"%s\" is zero or less. A size must be above zero" % t}
		out.append({"label": label, "mm": mm})
	if out.is_empty():
		return {"sizes": [], "err": "Type the sizes first: 30 / 45 / 60 cm, or Small 0.7, Medium 1, Large 1.4"}
	if out.size() > MAX_SIZES:
		return {"sizes": [], "err": "At most %d sizes at once" % MAX_SIZES}
	var seen := {}
	for s in out:
		if seen.has(s["label"]):
			return {"sizes": [], "err": "Two sizes are called \"%s\". Give each its own name" % s["label"]}
		seen[s["label"]] = true
	return {"sizes": out, "err": ""}


## make the family of the saved part `base` and save every size as its own My parts entry (named "<base> <size label>", with its picture).
## m = main (the picture is drawn by m.bld). export_dir != "": each size also written there as an STL file.
## {"saved": [names], "files": [stl paths], "err": ""}; nothing is saved when any size cannot be built
static func make(m: Node, base: String, key: String, text: String, bare_unit: String, export_dir := "") -> Dictionary:
	var rec := MyPartsS.load_part(base)
	if rec.is_empty():
		return {"saved": [], "files": [], "err": "%s is not in My parts. Save it with Use in a scene first" % base}
	var ps := parse_sizes(text, value_of(rec, key), bare_unit)
	if String(ps["err"]) != "":
		return {"saved": [], "files": [], "err": ps["err"]}
	var made: Array = []
	for s in ps["sizes"]:
		var w := with_value(rec, key, float(s["mm"]))
		if String(w["err"]) != "":
			return {"saved": [], "files": [], "err": "%s: %s" % [String(s["label"]), w["err"]]}
		var r: Dictionary = w["rec"]
		r["name"] = "%s %s" % [base, String(s["label"])]
		r.erase("collection")
		made.append(r)
	var saved: Array = []
	var files: Array = []
	for r in made:
		var pic := ProjectSettings.globalize_path(MyPartsS.thumb_of(String(r["name"])))   # the picture is drawn after _save_part returns: wait for its file
		var before := FileAccess.get_modified_time(pic) if FileAccess.file_exists(pic) else 0
		await m.bld._save_part(r)
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 5000 and (not FileAccess.file_exists(pic) or FileAccess.get_modified_time(pic) == before):
			await (Engine.get_main_loop() as SceneTree).process_frame
		if FileAccess.file_exists(pic):
			await (Engine.get_main_loop() as SceneTree).process_frame
		saved.append(String(r["name"]))
		if export_dir != "":
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(export_dir))
			var bs := MeshExportS.bodies_of(r)
			if (bs["bodies"] as Array).size() > 0:
				var p := "%s/%s.stl" % [export_dir, MyPartsS.file_stem(String(r["name"]))]
				if MeshExportS.write_stl(ProjectSettings.globalize_path(p), bs["bodies"]) == OK:
					files.append(p)
	return {"saved": saved, "files": files, "err": ""}


## the dialog: a panel the caller adds to its UI layer. lib = the ObjectLibrary (lib.m is main). Controls by name:
## family_vary (OptionButton), family_sizes (LineEdit), family_now, family_unit (OptionButton), family_export (CheckBox),
## family_save (Button), family_close (Button), family_note (Label)
static func dialog(lib: Node, base: String, on_close: Callable) -> PanelContainer:
	var rec := MyPartsS.load_part(base)
	var opts := options(rec)
	var pc := PanelContainer.new()
	pc.name = "library_family_dialog"
	var sb := StyleBoxFlat.new()
	sb.bg_color = Tok.c("float")
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	pc.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	pc.add_child(col)
	var hd := Label.new()
	hd.text = "Make a family of \"%s\"" % base
	col.add_child(hd)
	var vary := OptionButton.new()
	vary.name = "family_vary"
	vary.custom_minimum_size = Vector2(260, 30)
	for o in opts:
		vary.add_item(String(o["label"]))
		vary.set_item_metadata(vary.item_count - 1, String(o["key"]))
	col.add_child(vary)
	var now := Label.new()
	now.name = "family_now"
	now.add_theme_font_size_override("font_size", 13)
	now.add_theme_color_override("font_color", Tok.of("text:0.6"))
	col.add_child(now)
	var le := LineEdit.new()
	le.name = "family_sizes"
	le.placeholder_text = "30 / 45 / 60 cm  or  Small 0.7, Large 1.4"
	le.custom_minimum_size = Vector2(260, 30)
	col.add_child(le)
	var un := OptionButton.new()
	un.name = "family_unit"
	for u in ["cm", "mm"]:
		un.add_item("A bare number is in " + u)
	un.custom_minimum_size = Vector2(260, 28)
	col.add_child(un)
	var ex := CheckBox.new()
	ex.name = "family_export"
	ex.text = "Also export every size as an STL file"
	ex.focus_mode = Control.FOCUS_NONE
	col.add_child(ex)
	var note := Label.new()
	note.name = "family_note"
	note.custom_minimum_size = Vector2(260, 0)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 13)
	note.text = "Each size is a new My parts entry. The steps are replayed with the new size: holes and wall thickness keep theirs."
	col.add_child(note)
	var sv := Button.new()
	sv.name = "family_save"
	sv.text = "Save the family"
	sv.focus_mode = Control.FOCUS_NONE
	sv.custom_minimum_size = Vector2(260, 34)
	col.add_child(sv)
	var cl := Button.new()
	cl.name = "family_close"
	cl.text = "Close"
	cl.focus_mode = Control.FOCUS_NONE
	cl.custom_minimum_size = Vector2(260, 30)
	cl.pressed.connect(on_close)
	col.add_child(cl)
	var upd := func(_i := 0) -> void:
		if vary.item_count == 0:
			now.text = "This part has no extrude step to vary"
			sv.disabled = true
			return
		var k := String(vary.get_item_metadata(vary.selected))
		now.text = "Now: %.1f mm (%.1f cm)" % [value_of(rec, k), value_of(rec, k) / 10.0]
	vary.item_selected.connect(upd)
	upd.call()
	sv.pressed.connect(func():
		if vary.item_count == 0:
			return
		sv.disabled = true
		note.text = "Saving..."
		var k := String(vary.get_item_metadata(vary.selected))
		var dir := ""
		if ex.button_pressed:
			dir = "user://family_exports"
		var r: Dictionary = await make(lib.m, base, k, le.text, "cm" if un.selected == 0 else "mm", dir)
		if not is_instance_valid(note):
			return
		sv.disabled = false
		if String(r["err"]) != "":
			note.text = String(r["err"])
			return
		note.text = "Saved %d parts: %s%s" % [(r["saved"] as Array).size(), ", ".join(r["saved"]), (" (STL files in " + ProjectSettings.globalize_path(dir) + ")") if not (r["files"] as Array).is_empty() else ""]
		for nm in r["saved"]:   # a card drawn while the picture was still being written would keep its schematic cube: forget it, the saved picture is read
			lib.thumbs._tex.erase("mypart:saved:" + String(nm))
			lib.thumbs._asked.erase("mypart:saved:" + String(nm))
		lib.more = lib.extra_items()
		lib._rebuild())
	return pc
