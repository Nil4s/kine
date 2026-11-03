## godot --path . -s tests/c14_test.gd     (C14: complaints #520 rig pre-check, #560 footage pre-check, #442 cut-list locale; needs a window + the CAD DLL)
## BARS, written and committed BEFORE the first run (thresholds fixed a priori in the scripts: bones 15..160, side dev 15 %,
## dark < 70 / bright > 200 of 255, subject < 35 % of the height, shake > 0.5 % of the width per frame):
##  RIG (#520): a synthetic source rig built from Kine's own rest (Body.p0, every joint of Body.ORDER, symmetrical)
##   (1) CONTROL clean: RigPrecheck.check has 0 findings and an empty text (a check that always warned would fail here)
##   (2) the neck mapping removed: exactly ["no_neck"]
##   (3) the right hand pushed to 1.5 x the right lower arm: exactly ["asym_arm"], text names "arm" and a percent
##   (4) 200 extra bones: kinds contain "many_bones"; 8 bones: contain "few_bones"
##   (5) the right thigh unmapped: kinds contain "one_sided_leg"
##   (6) END TO END: AnimImport.import_file(mixamo fixture)["checks"] has the key "rig" (origin has none) and import ok
##  FOOTAGE (#560): four clips written by tests/py/c14_make_videos.py (files; a person 80 % / 15 % high, noise background)
##   (7) good: stats ok, findings EMPTY (control), brightness 70..200, subject >= 0.6, shake <= 0.5
##   (8) dark: findings are exactly one, naming "too dark"; (9) small: exactly one, naming "fills only"
##   (10) shaky: exactly one, naming "shakes", shake > 0.5; the shaky clip's shake is > 3 x the good clip's
##   (11) every warning text ends with the filming guide; the good clip says nothing
##   (12) a missing file gives ok false and judge() says nothing; judge() on planted stats {brightness 250} says "washed out"
##   (13) NO CAMERA: tools/footage_precheck.py opens cv2.VideoCapture only with the path variable (no integer index)
##   (14) main._import_video(clip): the status line carries "Footage check" for dark, not for good
##  CUT LIST (#442): the 3 boards of s081 (600x89x38 twice, 900x89x38), painted Wood
##   (15) DEFAULT UNCHANGED: csv_text(bl) and the file the dialog writes by default equal, byte for byte, the literal
##        "name,length_mm,width_mm,thickness_mm,count,board_metres\n2x4 board,600,89,38,2,1.200\n2x4 board,900,89,38,1,0.900\nTOTAL,,,,3,2.100\n"
##   (16) the dialog has an option "opt_export_csv_locale" with 2 entries, default index 0, inside the screen at 1280x720
##   (17) locale 1 through the dialog: the file starts with a UTF-8 BOM, 4 lines each with exactly 5 semicolons and no dot, the total line parses
##        as float(col5.replace(",", ".")) == 2.1 +- 0.001, the 2 data rows' counts are 2 and 1
##   (18) CONTROL: the default file has no semicolon (so (17) cannot pass by accident)
##  Screenshot: out/c14/dialog_cutlist.png (looked at)
extends SceneTree

var fails := 0
const DIR := "user://zz_c14"
const DIRT := "user://zz_c14_scenes"
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c14"
const FIX := "res://tests/fixtures/mixamo_rig.fbx"
const WANT_DEFAULT := "name,length_mm,width_mm,thickness_mm,count,board_metres\n2x4 board,600,89,38,2,1.200\n2x4 board,900,89,38,1,0.900\nTOTAL,,,,3,2.100\n"
var m: Node
var pu: PartUI


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
	await idle(3)


func shot(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	await idle(3)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, name])


func boards3() -> Dictionary:
	var rec := Part.make("Shelf")
	var fs: Array = rec["features"]
	var x := 0.0
	for L in [600.0, 600.0, 900.0]:
		var s1 := PartTemplates._sk(fs, "front", [PartTemplates._rect(Vector2(x, 0), Vector2(x + 89.0, 38.0))])
		PartTemplates._ex(fs, s1, "extrude", L, "new")
		x += 100.0
	rec["seq"] = fs.size()
	rec["kept"] = true
	return rec


func rig_src(B: Body, extra := 0) -> Dictionary:
	var names := []
	var rest := []
	var mp := {}
	for j in Body.ORDER:
		mp[j] = names.size()
		names.append(j)
		rest.append(Transform3D(Basis.IDENTITY, B.p0[j]))
	for i in extra:
		names.append("extra_%d" % i)
		rest.append(Transform3D.IDENTITY)
	return {"names": names, "rest": rest, "map": mp}


func kinds(r: Dictionary) -> Array:
	var k := []
	for f in r["findings"]:
		k.append(f["kind"])
	k.sort()
	return k


func rig_part() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var s := rig_src(B)
	var r := RigPrecheck.check(s, {"map": s["map"]})
	ok(r["findings"].is_empty() and String(r["text"]) == "", "1 clean Kine rig: %d findings, text '%s'" % [r["findings"].size(), r["text"]])
	var mp2: Dictionary = (s["map"] as Dictionary).duplicate()
	mp2.erase("neck_01")
	r = RigPrecheck.check(s, {"map": mp2})
	ok(kinds(r) == ["no_neck"], "2 no neck: %s" % str(kinds(r)))
	var s3 := rig_src(B)
	var rest: Array = s3["rest"]
	var lo: Vector3 = (rest[s3["map"]["lowerarm_r"]] as Transform3D).origin
	var ha: Vector3 = (rest[s3["map"]["hand_r"]] as Transform3D).origin
	rest[s3["map"]["hand_r"]] = Transform3D(Basis.IDENTITY, lo + (ha - lo) * 1.5)
	r = RigPrecheck.check(s3, {"map": s3["map"]})
	ok(kinds(r) == ["asym_arm"] and String(r["text"]).contains("arm") and String(r["text"]).contains("%"), "3 long right forearm: %s | %s" % [str(kinds(r)), r["text"]])
	var s4 := rig_src(B, 200)
	r = RigPrecheck.check(s4, {"map": s4["map"]})
	var few := {"names": ["a", "b", "c", "d", "e", "f", "g", "h"], "rest": [], "map": {"neck_01": 0}}
	var r2 := RigPrecheck.check(few, {"map": few["map"]})
	ok(kinds(r).has("many_bones") and kinds(r2).has("few_bones"), "4 many (%s) / few (%s)" % [str(kinds(r)), str(kinds(r2))])
	var mp5: Dictionary = (s["map"] as Dictionary).duplicate()
	mp5.erase("thigh_r")
	r = RigPrecheck.check(s, {"map": mp5})
	ok(kinds(r).has("one_sided_leg"), "5 right thigh unmapped: %s" % str(kinds(r)))
	var imp := AnimImport.import_file(ProjectSettings.globalize_path(FIX), B, "zz_c14")
	ok(bool(imp["ok"]) and (imp["checks"] as Dictionary).has("rig"), "6 import_file carries checks.rig: %s" % str(((imp["checks"] as Dictionary).get("rig", {}) as Dictionary).get("text", "<none>")))


func footage_part() -> void:
	var dir := ProjectSettings.globalize_path(DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var out := []
	OS.execute("python", PackedStringArray([ProjectSettings.globalize_path("res://tests/py/c14_make_videos.py"), dir]), out, true)
	var st := {}
	var ck := {}
	for n in ["good", "dark", "small", "shaky"]:
		st[n] = FootageCheck.stats_of(dir + "/" + n + ".avi")
		ck[n] = FootageCheck.judge(st[n])
		print("     ", n, " ", st[n], " -> ", ck[n]["findings"])
	var g: Dictionary = st["good"]
	ok(bool(g.get("ok", false)) and (ck["good"]["findings"] as Array).is_empty() and float(g["brightness"]) >= 70 and float(g["brightness"]) <= 200 and float(g["subject"]) >= 0.6 and float(g["shake"]) <= 0.5, "7 good clip: %s" % str(g))
	var fd: Array = ck["dark"]["findings"]
	ok(fd.size() == 1 and String(fd[0]).contains("too dark"), "8 dark: %s" % str(fd))
	var fs: Array = ck["small"]["findings"]
	ok(fs.size() == 1 and String(fs[0]).contains("fills only"), "9 small: %s" % str(fs))
	var fk: Array = ck["shaky"]["findings"]
	ok(fk.size() == 1 and String(fk[0]).contains("shakes") and float(st["shaky"]["shake"]) > 0.5 and float(st["shaky"]["shake"]) > 3.0 * maxf(float(g["shake"]), 0.01), "10 shaky: %s, shake %.3f vs good %.3f" % [str(fk), float(st["shaky"]["shake"]), float(g["shake"])])
	var all_guide := String(ck["good"]["text"]) == ""
	for n in ["dark", "small", "shaky"]:
		all_guide = all_guide and String(ck[n]["text"]).ends_with(FootageCheck.GUIDE)
	ok(all_guide, "11 every warning ends with the filming guide, the good clip says nothing")
	var miss := FootageCheck.stats_of(dir + "/nope.avi")
	var bright := FootageCheck.judge({"ok": true, "brightness": 250.0, "subject": 0.9, "shake": 0.0})
	ok(not bool(miss.get("ok", false)) and FootageCheck.judge(miss)["text"] == "" and String(bright["text"]).contains("washed out"), "12 missing file: %s; planted 250: %s" % [str(miss), str(bright["findings"])])
	var src := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://tools/footage_precheck.py"))
	ok(src.contains("cv2.VideoCapture(path)") and not src.contains("VideoCapture(0") and not src.contains("VideoCapture(1"), "13 the pre-check opens a file path only, never a camera index")


func _init() -> void:
	rig_part()
	await footage_part()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var said := []
	m.video_tool = "res://tests/fixtures/ri_stub.py"
	for n in ["good", "dark"]:
		m._import_video(ProjectSettings.globalize_path(DIR) + "/" + n + ".avi")
		await idle(2)
		said.append(m.ui_status.text)
		m._video_cancel()
		await idle(2)
	ok(not String(said[0]).contains("Footage check") and String(said[1]).contains("Footage check"), "14 status line: good '%s' / dark '%s'" % [str(said[0]).left(60), str(said[1]).left(90)])
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	m.S.part = boards3()
	pu._rec_sig = ""
	pu.sync()
	await idle(8)
	var ep = pu.ep
	await click_ctl(ep.make_btns["colour"])
	await click_ctl(ep.colour_box.find_child("easypart_colour_wood", true, false) as Button)
	await idle(6)
	var bl := CutList.boards(m.S.part)
	ok(CutList.csv_text(bl) == WANT_DEFAULT, "15a csv_text default is byte for byte the old text")
	await click_ctl(root.find_child("easypart_export", true, false) as Button)
	await idle(4)
	var ui: ExportDialog = m.export_ui
	var ci := -1
	for i in ui.ui_target.item_count:
		if ui.ui_target.get_item_text(i).contains("Cut list"):
			ci = i
	ui.ui_target.select(ci)
	ui._on_target(ci)
	await idle(3)
	var lo: OptionButton = ui.ui_csv_locale
	ok(lo != null and lo.item_count == 2 and lo.selected == 0 and lo.is_visible_in_tree() and root.get_visible_rect().encloses(lo.get_global_rect()), "16 locale option: %s" % ("none" if lo == null else "%d items, sel %d, rect %s" % [lo.item_count, lo.selected, str(lo.get_global_rect())]))
	await shot("dialog_cutlist")
	var path := ProjectSettings.globalize_path("res://exports") + "/Shelf_cutlist.csv"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	ui.dlg.get_ok_button().pressed.emit()
	await idle(4)
	var dflt := FileAccess.get_file_as_bytes(path).get_string_from_utf8() if FileAccess.file_exists(path) else "<none>"
	ok(dflt == WANT_DEFAULT, "15b the dialog's default file is byte for byte the old text")
	ok(not dflt.contains(";"), "18 control: the default file has no semicolon")
	lo.select(1)
	DirAccess.remove_absolute(path)
	ui.dlg.get_ok_button().pressed.emit()
	await idle(4)
	var raw := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	var bom := raw.size() > 3 and raw[0] == 0xEF and raw[1] == 0xBB and raw[2] == 0xBF
	var txt := raw.get_string_from_utf8().trim_prefix("\uFEFF")
	var lines := txt.split("\n", false)
	var good := lines.size() == 4
	for ln in lines:
		good = good and ln.count(";") == 5 and not ln.contains(".")
	var tot := lines[lines.size() - 1].split(";") if lines.size() > 0 else PackedStringArray()
	var tv := float(tot[5].replace(",", ".")) if tot.size() == 6 else -1.0
	ok(bom and good and absf(tv - 2.1) <= 0.001 and int(lines[1].split(";")[4]) == 2 and int(lines[2].split(";")[4]) == 1, "17 locale 1 file: bom %s, %d lines, total %.3f; %s" % [str(bom), lines.size(), tv, txt.replace("\n", " | ")])
	print("c14: %d fail" % fails)
	quit(1 if fails > 0 else 0)
