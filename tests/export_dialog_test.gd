## godot --headless --path . -s tests/export_dialog_test.gd     (ROADMAP 57: "Export..." picks a target and says what it needs)
## (1) every target (ue5, unity, godot, blender, maya, web, raw) lists its format, its needs, and at least one checklist line
##     for combo3, each line tagged OK, WARN or WRONG;
## (2) Export with Unreal 5 picked writes the SAME BYTES as the existing "Export for Unreal 5..." command (sha256 of the
##     <scene>_ue5.glb, both into user:// folders);
## (3) the other formats the dialog runs write the same bytes as the old commands: web .glb, raw .bvh, .usda, PoseTable .json and .cs;
## (4) the checklist names what is left out: a prop, a sound and secondary motion, set on the scene in memory, each gets a WARN line.
## Files go to user://zz_export_dialog and user://zz_export_dialog_ref (removed after).
extends SceneTree

var fails := 0
const DIR := "user://zz_export_dialog"
const REF := "user://zz_export_dialog_ref"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func clean(d: String) -> void:
	var g := ProjectSettings.globalize_path(d)
	if DirAccess.dir_exists_absolute(g):
		for f in DirAccess.get_files_at(g):
			DirAccess.remove_absolute(g + "/" + f)
		DirAccess.remove_absolute(g)


func fresh(path: String) -> void:
	var g := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(g)


func tagged(lines: Array) -> bool:
	for l in lines:
		var s := String(l)
		if not (s.begins_with("OK") or s.begins_with("WARN") or s.begins_with("WRONG") or s.begins_with("NOT NOW")):
			return false
	return not lines.is_empty()


func _init() -> void:
	clean(DIR)
	clean(REF)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REF))
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	m._load_scene("res://scenes/combo3.json")
	m._export_dialog_open()
	var ui: ExportDialog = m.export_ui
	ok(ui != null and ui.dlg != null and ui.ui_target.item_count == 7, "Export... builds the dialog with the target picker (%d targets)" % (ui.ui_target.item_count if ui != null and ui.ui_target != null else -1))

	# (1) every target: format, needs, and checklist lines
	var ids := []
	for t in ExportDialog.targets():
		ids.append((t as Dictionary)["id"])
	ok(ids == ["ue5", "unity", "godot", "blender", "maya", "web", "raw"], "targets: %s" % [ids])
	for t in ExportDialog.targets():
		var id := String((t as Dictionary)["id"])
		var n: int = ((t as Dictionary)["formats"] as Array).size()
		for fi in n:
			var d := ui.text_of(id, fi)
			ok(String(d["format"]) != "" and String(d["needs"]) != "" and tagged(d["checks"]),
				"%s [%s]: format, needs and %d checklist lines, each OK/WARN/WRONG" % [id, d["format"], (d["checks"] as Array).size()])
			print("       needs: %s" % String(d["needs"]).left(160))
		var first := ui.text_of(id, 0)
		print("       checks: %s" % [first["checks"]])

	# (2) UE5 through the dialog = the existing Unreal 5 command, byte for byte
	var ref_ue5: String = m._export_engine("ue5", REF)
	var got_ue5: String = ui.export_now("ue5", 0, DIR)
	var h_ref := FileAccess.get_sha256(ref_ue5)
	var h_got := FileAccess.get_sha256(got_ue5)
	ok(ref_ue5 != "" and got_ue5 != "" and h_ref != "" and h_ref == h_got,
		"UE5 via Export... == the old command: %s, sha256 %s" % [got_ue5.get_file(), h_got.left(16)])

	# (3) the other formats: the dialog's writer = the old command's writer
	var ref_glb: String = m._export_glb(REF)
	fresh(DIR + "/combo3.glb")
	ui.export_now("web", 0, DIR)
	ok(FileAccess.get_sha256(ref_glb) != "" and FileAccess.get_sha256(ref_glb) == FileAccess.get_sha256(DIR + "/combo3.glb"), "web .glb == the old Export .glb command")
	m._export_bvh(REF)
	fresh(DIR + "/combo3.bvh")
	ui.export_now("raw", 0, DIR)
	ok(FileAccess.get_sha256(REF + "/combo3.bvh") != "" and FileAccess.get_sha256(REF + "/combo3.bvh") == FileAccess.get_sha256(DIR + "/combo3.bvh"), "raw .bvh == the old Export .bvh command")
	m._export_usd(REF)
	fresh(DIR + "/combo3.usda")
	ui.export_now("raw", 1, DIR)
	ok(FileAccess.get_sha256(REF + "/combo3.usda") != "" and FileAccess.get_sha256(REF + "/combo3.usda") == FileAccess.get_sha256(DIR + "/combo3.usda"), "raw .usda == the old Export animation (.usda) command")
	m._export_game(REF)
	fresh(DIR + "/combo3.json")
	fresh(DIR + "/combo3.cs")
	ui.export_now("raw", 2, DIR)
	var gj := FileAccess.get_sha256(REF + "/combo3.json")
	var gc := FileAccess.get_sha256(REF + "/combo3.cs")
	ok(gj != "" and gj == FileAccess.get_sha256(DIR + "/combo3.json") and gc != "" and gc == FileAccess.get_sha256(DIR + "/combo3.cs"),
		"raw PoseTable .json and .cs == the old Export to game command")

	# (4) what is left out is named: a prop, a sound, secondary motion (set in memory on the open scene, then taken back)
	var S = m.S
	var keep_props: Array = S.props.duplicate(true)
	var keep_audio: Array = S.audio_tracks.duplicate(true)
	var keep_sec: Dictionary = S.secondary.duplicate(true)
	S.props = [{"kind": "chair", "xf": Transform3D.IDENTITY}]
	S.audio_tracks = [{"path": "res://x.wav", "offset": 0.0, "gain_db": 0.0}]
	S.secondary = {"items": [{"name": "ponytail_1"}], "keys": {}, "fps": S.fps}
	var lines: Array = ui.checks("raw", "bvh")
	var txt := "\n".join(lines)
	ok(txt.contains("WARN  1 prop not in any export") and txt.contains("WARN  the sound track") and txt.contains("WARN  secondary motion (1 item)"),
		"checklist names the prop, the sound and the secondary motion as left out")
	S.props = keep_props
	S.audio_tracks = keep_audio
	S.secondary = keep_sec

	m.export_ui.dlg.hide()
	clean(DIR)
	clean(REF)
	quit(1 if fails > 0 else 0)
