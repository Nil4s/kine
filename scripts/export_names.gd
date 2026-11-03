class_name ExportNames
extends RefCounted
## ExportNames (C09, complaint #381): export file names from a template. Tokens {name} (the scene), {part} (the object / fighter
## / part being written), {date} (YYYY-MM-DD), {time} (HHMM). An empty template = the old name, untouched (the default).
## The result is a plain file stem: characters a file name cannot hold become _, unknown {tokens} stay as written, and a template
## that expands to nothing falls back to the old name. Also holds the dialog's other opt-in switches (static, one session).

static var template := ""
static var fbx_camera := false
static var lightmap_uv := false
## C28: the FBX target engine ("default" = the old file; "unity" | "unreal" | "blender" call FbxExport.write_preset)
static var fbx_for := "default"
const FBX_FOR := ["default", "unity", "unreal", "blender"]
const FBX_FOR_NAMES := ["Default (centimetres, Y up)", "Unity (metres)", "Unreal (centimetres, Z up)", "Blender (centimetres, Z up)"]


## the FBX write for the chosen target; the default target is FbxExport.write itself (the same bytes as before)
static func fbx_write(S, B, path: String, root_motion := false, xf := Transform3D.IDENTITY, root_name := "", ascii := false, camera_keys := []) -> Dictionary:
	if fbx_for == "default" or not FbxExport.PRESETS.has(fbx_for):
		return FbxExport.write(S, B, path, root_motion, xf, root_name, ascii, camera_keys)
	return FbxExport.write_preset(fbx_for, S, B, path, root_motion, xf, root_name, ascii, camera_keys)


## the words after an export say which target the numbers are for ("" for the default)
static func fbx_for_words() -> String:
	return "" if fbx_for == "default" or not FbxExport.PRESETS.has(fbx_for) else "; for %s: %s" % [fbx_for.capitalize(), String(FbxExport.PRESETS[fbx_for]["words"])]


static func expand(tpl: String, vars: Dictionary, fallback: String, date := {}) -> String:
	tpl = tpl.strip_edges()
	if tpl == "":
		return fallback
	var d: Dictionary = date if not date.is_empty() else Time.get_datetime_dict_from_system()
	var all := {"name": "", "part": ""}
	all.merge(vars, true)
	all["date"] = "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]
	all["time"] = "%02d%02d" % [d["hour"], d["minute"]]
	var s := tpl
	for k in all:
		s = s.replace("{" + k + "}", String(all[k]))
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		s = s.replace(ch, "_")
	s = s.strip_edges()
	s = s.replace(" ", "_")
	return s if s != "" and s.replace("_", "").replace("-", "").replace(".", "") != "" else fallback


## the dialog block: a template box, the FBX camera switch, the lightmap UV switch
static func controls() -> Control:
	var v := VBoxContainer.new()
	v.name = "export_extras"
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = "File name template (blank = the usual name):"
	row.add_child(l)
	var le := LineEdit.new()
	le.name = "le_name_template"
	le.placeholder_text = "{name}_{part}_{date}"
	le.tooltip_text = "Tokens: {name} the scene, {part} the object or fighter, {date} YYYY-MM-DD, {time} HHMM. Blank keeps the old file names."
	le.custom_minimum_size = Vector2(240, 0)
	le.text = template
	le.text_changed.connect(func(t: String): template = t)
	row.add_child(le)
	v.add_child(row)
	var c1 := CheckBox.new()
	c1.name = "chk_fbx_camera"
	c1.text = "FBX: shot camera (keys)"
	c1.button_pressed = fbx_camera
	c1.toggled.connect(func(on: bool): fbx_camera = on)
	var rf := HBoxContainer.new()   # one row with the camera switch: the dialog gets no taller
	rf.name = "row_fbx_for"
	rf.add_child(c1)
	var lf := Label.new()
	lf.text = "  for:"
	rf.add_child(lf)
	var of := OptionButton.new()
	of.name = "opt_fbx_for"
	for nm in FBX_FOR_NAMES:
		of.add_item(nm)
	of.select(maxi(FBX_FOR.find(fbx_for), 0))
	of.tooltip_text = "Which engine the FBX numbers are for. Default keeps the old file (centimetres, Y up). Unity writes metres; Unreal and Blender write Z up."
	of.item_selected.connect(func(i: int): fbx_for = FBX_FOR[i])
	of.custom_minimum_size = Vector2(190, 0)
	rf.add_child(of)
	v.add_child(rf)
	var c2 := CheckBox.new()
	c2.name = "chk_lightmap_uv"
	c2.text = "Mesh .glb: add a lightmap UV set (UV2, no overlaps)"
	c2.button_pressed = lightmap_uv
	c2.toggled.connect(func(on: bool): lightmap_uv = on)
	v.add_child(c2)
	return v


## the shot camera's keys to write into the FBX: [] unless the switch is on and the scene has a shot with keys
static func cam_keys(sc) -> Array:
	if not fbx_camera or sc == null or sc.shots.is_empty():
		return []
	return (sc.shots[0] as Dictionary).get("keys", [])
