extends SceneTree
## godot --headless --path . -s tests/c32_test.gd     (C32: the support gap and interface reach the slicers' own settings files; needs the CAD DLL)
## Bars (written before the first run). Every number is read back from the WRITTEN .3mf.
##   1 DEFAULT  no support choice: the zip has no Metadata/ entry and 3D/3dmodel.model is byte-identical to model_xml(bodies, title)
##   2 BAMBU    Easy writes Metadata/project_settings.config with support_top_z_distance = support_bottom_z_distance = 0.3 and
##              support_interface_top_layers = support_interface_bottom_layers = 3 ; Strong 0.1 and 0
##   3 PRUSA    the same numbers in Metadata/Slic3r_PE.config as support_material_contact_distance / support_material_interface_layers
##   4 TRADE    Easy gap > Strong gap and Easy layers > Strong layers, in both files
##   5 SPLIT    the split-to-fit road (a 12 x 8 x 4 mm bed, so the 20 x 10 x 5 box must split) writes both files with Easy's numbers
##   6 KEYS     every key in our project_settings.config exists in the installed Bambu Studio's own process profile (fdm_process_common.json)
##   7 SLICER   the installed Bambu Studio, run headless on our Easy file, opens it and slices it (a plate_1.gcode appears) and its gcode header lists
##              the same four keys. Whether it APPLIED our values is printed as INFO, not barred (see the report: it does not for a non-Bambu 3mf)
##   8 CONTROL  the readers return {} on the default file (what origin writes), so 2/3 can fail
const DIR := "user://zz_c32"
const BBS := "C:/Program Files/Bambu Studio"
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func entries(path: String) -> PackedStringArray:
	var z := ZIPReader.new()
	if z.open(path) != OK:
		return PackedStringArray()
	var f := z.get_files()
	z.close()
	return f


func model_text(path: String) -> String:
	var z := ZIPReader.new()
	if z.open(path) != OK:
		return ""
	var t := z.read_file("3D/3dmodel.model").get_string_from_utf8()
	z.close()
	return t


func _init() -> void:
	var wd = create_timer(300.0)   # watchdog
	wd.timeout.connect(func():
		print("FAIL watchdog: c32 timed out")
		quit(1))
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	var gd := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(gd)
	var rec := Part.make("C32 box")
	var fs: Array = rec["features"]
	var sid := PartTemplates._sk(fs, "top", [PartTemplates._rect(Vector2(0, 0), Vector2(20, 10))])
	PartTemplates._ex(fs, sid, "extrude", 5.0, "new")
	rec["seq"] = fs.size()
	rec["kept"] = true
	var p0: String = MeshExport.export_part(rec, "3mf", gd + "/d", 0, {}, {})["path"]
	var pe: String = MeshExport.export_part(rec, "3mf", gd + "/e", 0, {}, SupportPref.of(1))["path"]
	var ps: String = MeshExport.export_part(rec, "3mf", gd + "/s", 0, {}, SupportPref.of(2))["path"]
	# 1
	var bodies: Array = MeshExport.bodies_of(rec)["bodies"]
	var meta := 0
	for n in entries(p0):
		if n.begins_with("Metadata"):
			meta += 1
	ok(meta == 0 and model_text(p0) == MeshExport.model_xml(bodies, "C32 box"), "1 default: %d Metadata entries, model xml equals the no-support one" % meta)
	# 8
	ok(SupportPref.read_slicer_files(p0).is_empty(), "8 control: the default file reads back {}")
	# 2 3 4
	var be := SupportPref.read_slicer_files(pe)
	var bs := SupportPref.read_slicer_files(ps)
	ok(str(be.get("support_top_z_distance")) == "0.3" and str(be.get("support_bottom_z_distance")) == "0.3" and str(be.get("support_interface_top_layers")) == "3" and str(be.get("support_interface_bottom_layers")) == "3", "2 Bambu Easy %s" % [be])
	ok(str(bs.get("support_top_z_distance")) == "0.1" and str(bs.get("support_bottom_z_distance")) == "0.1" and str(bs.get("support_interface_top_layers")) == "0" and str(bs.get("support_interface_bottom_layers")) == "0", "2b Bambu Strong %s" % [bs])
	ok(str(be.get("support_material_contact_distance")) == "0.3" and str(be.get("support_material_interface_layers")) == "3" and str(bs.get("support_material_contact_distance")) == "0.1" and str(bs.get("support_material_interface_layers")) == "0", "3 Prusa Easy/Strong numbers")
	ok(float(be.get("support_top_z_distance", "0")) > float(bs.get("support_top_z_distance", "9")) and int(be.get("support_interface_top_layers", "0")) > int(bs.get("support_interface_top_layers", "9")) and float(be.get("support_material_contact_distance", "0")) > float(bs.get("support_material_contact_distance", "9")), "4 Easy gap/layers exceed Strong's in both files")
	# 5 split
	var r := PrintSplit.export_part(rec, "3mf", gd + "/sp", Vector3(12, 8, 4), {}, SupportPref.of(1))
	var sp: Dictionary = SupportPref.read_slicer_files(String(r.get("path", r.get("paths", [""])[0] if r.has("paths") and (r["paths"] as Array).size() > 0 else "")))
	ok(bool(r.get("ok", false)) and sp.get("support_top_z_distance", "") == "0.3" and sp.get("support_material_interface_layers", "") == "3", "5 split road: ok=%s %s" % [r.get("ok"), sp])
	# 6 keys against the installed profile
	var prof := FileAccess.get_file_as_string(BBS + "/resources/profiles/BBL/process/fdm_process_common.json")
	var allk := true
	var zr := ZIPReader.new()
	zr.open(pe)
	var pj = JSON.parse_string(zr.read_file("Metadata/project_settings.config").get_string_from_utf8())
	zr.close()
	for k in (pj as Dictionary).keys():
		if not (k in ["from", "name"]) and not prof.contains("\"%s\"" % k):
			allk = false
			print("  key not in Bambu profile: " + k)
	ok(prof != "" and allk, "6 every settings key exists in the installed Bambu Studio's process profile")
	# 7 slicer
	var exe := BBS + "/bambu-studio.exe"
	if FileAccess.file_exists(exe):
		var od := gd + "/bbs"
		DirAccess.make_dir_recursive_absolute(od)
		DirAccess.remove_absolute(od + "/plate_1.gcode")
		var pid := OS.create_process(exe, ["--slice", "0", "--outputdir", od.replace("/", "\\"), pe.replace("/", "\\")])
		var t0 := Time.get_ticks_msec()
		while not FileAccess.file_exists(od + "/plate_1.gcode") and Time.get_ticks_msec() - t0 < 150000:
			await process_frame
		await create_timer(3.0).timeout
		if OS.is_process_running(pid):
			OS.kill(pid)
		var g := FileAccess.get_file_as_string(od + "/plate_1.gcode")
		var hdr := g.contains("; support_top_z_distance = ") and g.contains("; support_interface_top_layers = ") and g.contains("; support_bottom_z_distance = ") and g.contains("; support_interface_bottom_layers = ")
		ok(g.length() > 1000 and hdr, "7 Bambu Studio sliced our Easy file (%d bytes gcode) and its header names the four keys" % g.length())
		var rx := RegEx.create_from_string("; support_top_z_distance = ([0-9.]+)")
		var mt := rx.search(g)
		print("INFO slicer header support_top_z_distance = %s (Easy wrote 0.3): %s" % [mt.get_string(1) if mt else "?", "APPLIED" if mt and mt.get_string(1) == "0.3" else "NOT applied"])
	else:
		print("INFO no Bambu Studio installed: bar 7 skipped")
	print("c32: %d fail" % fails)
	quit(1 if fails > 0 else 0)
