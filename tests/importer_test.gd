## godot --headless --path . -s tests/importer_test.gd
## THE IMPORTER (scripts/importer.gd): .glb fixtures the test writes itself (a 40 cm box; the same box 100x too big; a
## 0.4 mm box; a skinned mannequin from GltfExport; junk bytes; an empty file; a missing path) read back through
## Importer.inspect, then Importer.accept / library_list against a library the test owns. Everything lives in
## user://zz_import_test_<pid>/ and is removed at the end.
extends SceneTree

const Importer := preload("res://scripts/importer.gd")

var fails := 0
var base := "user://zz_import_test_%d" % OS.get_process_id()


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func abs_of(p: String) -> String:
	return ProjectSettings.globalize_path(p)


## a .glb holding one box of this size, written by GLTFDocument
func write_box(path: String, side: float) -> void:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * side
	mi.mesh = bm
	root.add_child(mi)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_scene(root, st)
	doc.write_to_filesystem(st, abs_of(path))
	root.free()


func write_bytes(path: String, b: PackedByteArray) -> void:
	var f := FileAccess.open(abs_of(path), FileAccess.WRITE)
	f.store_buffer(b)
	f.close()


## every file under a folder, recursively (0 when it does not exist)
func count_files(dir: String) -> int:
	if not DirAccess.dir_exists_absolute(abs_of(dir)):
		return 0
	var n := DirAccess.get_files_at(abs_of(dir)).size()
	for d in DirAccess.get_directories_at(abs_of(dir)):
		n += count_files(dir + "/" + d)
	return n


func remove_tree(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_of(dir)):
		return
	for f in DirAccess.get_files_at(abs_of(dir)):
		DirAccess.remove_absolute(abs_of(dir + "/" + f))
	for d in DirAccess.get_directories_at(abs_of(dir)):
		remove_tree(dir + "/" + d)
	DirAccess.remove_absolute(abs_of(dir))


func is_sentence(s: String) -> bool:
	return s.strip_edges().split(" ", false).size() > 5


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(abs_of(base))
	var fx := base + "/fixtures"
	var lib := base + "/library"
	DirAccess.make_dir_recursive_absolute(abs_of(fx))
	var p_box := fx + "/crate.glb"
	var p_big := fx + "/crate_cm.glb"
	var p_tiny := fx + "/speck.glb"
	var p_man := fx + "/mannequin.glb"
	var p_junk := fx + "/junk.glb"
	var p_empty := fx + "/empty.glb"
	var p_gone := fx + "/not_here.glb"
	write_box(p_box, 0.4)
	write_box(p_big, 40.0)
	write_box(p_tiny, 0.0004)
	write_bytes(p_junk, PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209]))
	write_bytes(p_empty, PackedByteArray())
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var werr := GltfExport.write(S, B, p_man, true)
	ok(werr == OK, "0 fixtures written (mannequin write error %d)" % werr)

	# (1) an ordinary 40 cm box
	var r := Importer.inspect(p_box)
	ok(r["ok"] and r["kind"] == "object" and absf(r["size"].x - 0.4) < 0.005 and absf(r["size"].y - 0.4) < 0.005 and r["scale_note"] == "" and r["scale_factor"] == 1.0,
		"1 40 cm box: kind %s, size %s, scale note '%s', factor %s" % [r.get("kind"), r.get("size"), r.get("scale_note"), r.get("scale_factor")])
	# (2) the same box made in centimetres: 40 m
	r = Importer.inspect(p_big)
	ok(r["ok"] and absf(r["size"].x - 40.0) < 0.05 and r["scale_note"].to_lower().contains("centimetres") and r["scale_note"].contains("40 m") and not r["scale_note"].contains("%") and absf(r["scale_factor"] - 0.01) < 1e-9,
		"2 40 m box: size %s, factor %s, note '%s'" % [r.get("size"), r.get("scale_factor"), r.get("scale_note")])
	# (3) 0.4 mm: 1000x too small
	r = Importer.inspect(p_tiny)
	ok(r["ok"] and r["scale_note"].contains("1000x too small") and r["scale_note"].contains("0.4 mm") and not r["scale_note"].contains("%") and absf(r["scale_factor"] - 1000.0) < 1e-6,
		"3 0.4 mm box: size %s, factor %s, note '%s'" % [r.get("size"), r.get("scale_factor"), r.get("scale_note")])
	# (3b) the verdict itself: millimetres, plausible edges
	var vm := Importer.scale_verdict(4000.0)
	var v1 := Importer.scale_verdict(1.8)
	ok(vm[1] == 0.001 and vm[0].contains("millimetres") and v1[0] == "" and v1[1] == 1.0, "3b scale_verdict: 4000 m -> %s (%s); 1.8 m -> '%s'" % [vm[1], vm[0], v1[0]])
	# (4) the skinned mannequin
	r = Importer.inspect(p_man)
	ok(r["ok"] and r["kind"] == "rigged" and r["bones"] >= 50 and r["size"].y >= 1.7 and r["size"].y <= 1.9,
		"4 mannequin: kind %s, %d bones, height %.3f m, size %s, note '%s'" % [r.get("kind"), r.get("bones"), r["size"].y, r.get("size"), r.get("scale_note")])
	# (5) broken files, said in words
	for bad in [[p_junk, "junk bytes"], [p_empty, "empty file"], [p_gone, "missing file"], [fx + "/notes.txt", "wrong type"]]:
		if bad[1] == "wrong type":
			write_bytes(bad[0], "hello".to_utf8_buffer())
		var rb := Importer.inspect(bad[0])
		ok(not rb["ok"] and is_sentence(rb["why"]), "5 %s: ok %s, why '%s'" % [bad[1], rb["ok"], rb["why"]])
	# a valid glTF with no meshes
	var nomesh := fx + "/nomesh.glb"
	var nr := Node3D.new()
	nr.add_child(Node3D.new())
	var d2 := GLTFDocument.new()
	var s2 := GLTFState.new()
	d2.append_from_scene(nr, s2)
	d2.write_to_filesystem(s2, abs_of(nomesh))
	nr.free()
	var rn := Importer.inspect(nomesh)
	ok(not rn["ok"] and is_sentence(rn["why"]) and rn["why"].contains("no 3D shapes"), "5b no meshes: ok %s, why '%s'" % [rn["ok"], rn["why"]])

	# (6) accept refuses broken files and writes nothing
	var wrote := 0
	for bad in [p_junk, p_empty, p_gone, nomesh]:
		var ra := Importer.accept(bad, "prop", lib)
		wrote += 0 if (not ra["ok"] and is_sentence(ra["why"])) else 1
	ok(wrote == 0 and count_files(lib) == 0 and not DirAccess.dir_exists_absolute(abs_of(lib)), "6 broken files refused: %d slipped through, %d files in the library" % [wrote, count_files(lib)])
	var rk := Importer.accept(p_box, "banana", lib)
	ok(not rk["ok"] and is_sentence(rk["why"]) and count_files(lib) == 0, "6b unknown kind refused: '%s'" % rk["why"])
	var empty_list := Importer.library_list(lib)
	ok(empty_list["props"].is_empty() and empty_list["weapons"].is_empty() and empty_list["animations"].is_empty() and not DirAccess.dir_exists_absolute(abs_of(lib)),
		"6c library_list of a missing library: empty lists, nothing created")

	# (7) accept a good file: copied, licence beside it, the original untouched
	var md5_before := FileAccess.get_md5(abs_of(p_box))
	var size_before := FileAccess.get_file_as_bytes(abs_of(p_box)).size()
	var a1 := Importer.accept(p_box, "prop", lib, "CC0 by the test")
	var copied: bool = a1["ok"] and FileAccess.file_exists(abs_of(a1["path"])) and FileAccess.get_md5(abs_of(a1["path"])) == md5_before
	var lic_text := FileAccess.get_file_as_string(abs_of(a1["licence"])) if a1["licence"] != "" else ""
	ok(copied and lic_text.contains("CC0 by the test") and lic_text.contains("source:") and lic_text.contains("imported:"),
		"7 accept: copied to %s (md5 equal %s), licence note has text %s" % [a1.get("path"), copied, lic_text.contains("CC0 by the test")])
	ok(FileAccess.get_md5(abs_of(p_box)) == md5_before and FileAccess.get_file_as_bytes(abs_of(p_box)).size() == size_before and FileAccess.file_exists(abs_of(p_box)),
		"7b the original is untouched: md5 %s before and after" % md5_before)
	# a second accept of the same name does not overwrite
	var a2 := Importer.accept(p_box, "prop", lib)
	var lic2 := FileAccess.get_file_as_string(abs_of(a2["licence"])) if a2["licence"] != "" else ""
	ok(a2["ok"] and a2["path"] != a1["path"] and a2["path"].ends_with("crate_2.glb") and FileAccess.file_exists(abs_of(a1["path"])) and FileAccess.get_md5(abs_of(a1["path"])) == md5_before
		and lic2.contains("not given"), "8 second accept keeps both: %s and %s, default licence line present %s" % [a1.get("path"), a2.get("path"), lic2.contains("not given")])
	# a rigged file goes where the caller says
	var a3 := Importer.accept(p_man, "animation", lib)
	ok(a3["ok"] and a3["kind"] == "rigged" and a3["path"].contains("/animations/"), "9 rigged file accepted into animations: %s (kind %s)" % [a3.get("path"), a3.get("kind")])
	# (10) library_list sees them
	var L := Importer.library_list(lib)
	var names := []
	for e in L["props"]:
		names.append(e["name"])
	var licensed := true
	for e in L["props"]:
		licensed = licensed and e["licence"] != ""
	ok(names == ["crate", "crate_2"] and licensed and L["weapons"].is_empty() and L["animations"].size() == 1,
		"10 library_list: props %s (licences %s), weapons %d, animations %d" % [names, licensed, L["weapons"].size(), L["animations"].size()])
	# (11) the real library was not touched by this test
	ok(not FileAccess.file_exists(abs_of("user://library/props/crate.glb")), "11 the real user://library was not written")

	remove_tree(base)
	ok(not DirAccess.dir_exists_absolute(abs_of(base)), "12 test folder removed")
	print("IMPORTER TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
