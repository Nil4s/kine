## godot --path . -s tests/packzip_test.gd     (N15 PACK PROJECT; needs a window: it opens the unpacked scene in the app)
## Bars (stated before measuring): (1) a scene in user:// that uses a sound, a prop model (an .obj) and a reference picture packs to a
## zip of 4 entries (scene + 3 files) + manifest.json, every manifest hash equals the sha256 of the bytes in the zip; (2) unpacked into a
## NEW user:// folder the scene opens in the app and every referenced path exists and lies inside that folder; (3) a referenced file that
## does not exist is named in the pack result AND in the manifest, and the zip still has the others; (4) a crafted zip with an entry
## "../x" is refused, nothing is written (no folder, no x); a changed byte is refused by its hash; unpack outside user:// is refused;
## (5) only user:// is written: scenes/ (every file, name + hash) is identical before and after.
extends SceneTree

var fails := 0
var m: Node
const SRC := "user://packtest_src"
const ROOT := "user://packtest_out"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func listing(dir: String) -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(dir):
		out[dir + "/" + f] = FileAccess.get_sha256(dir + "/" + f)
	for sub in DirAccess.get_directories_at(dir):
		out.merge(listing(dir + "/" + sub))
	return out


func files_of(z: ZIPReader) -> Array:
	return Array(z.get_files()).filter(func(n): return not String(n).ends_with("/"))   # folder rows are not entries


func wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + "/" + f))
	for sub in DirAccess.get_directories_at(dir):
		wipe(dir + "/" + sub)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func _init() -> void:
	var before := listing("res://scenes")
	wipe(SRC)
	wipe(ROOT)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://packs/packtest.kinezip"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SRC))
	# the dummy files: a tiny wav (200 bytes of a 3,4,5,... ramp that a zip stores or deflates), a 4-face obj, a 4x4 picture
	var wav := PackedByteArray()
	wav.append_array("RIFF".to_utf8_buffer())
	wav.append_array(PackedByteArray([236, 0, 0, 0]))
	wav.append_array("WAVEfmt ".to_utf8_buffer())
	wav.append_array(PackedByteArray([16, 0, 0, 0, 1, 0, 1, 0, 0x40, 0x1F, 0, 0, 0x80, 0x3E, 0, 0, 2, 0, 16, 0]))
	wav.append_array("data".to_utf8_buffer())
	wav.append_array(PackedByteArray([200, 0, 0, 0]))
	for i in 200:
		wav.append(i % 251)
	var fa := FileAccess.open(SRC + "/hit.wav", FileAccess.WRITE)
	fa.store_buffer(wav)
	fa.close()
	var fo := FileAccess.open(SRC + "/crate.obj", FileAccess.WRITE)
	fo.store_string("v 0 0 0\nv 0.4 0 0\nv 0.4 0.4 0\nv 0 0.4 0.3\nf 1 2 3\nf 1 3 4\nf 1 2 4\nf 2 3 4\n")
	fo.close()
	var im := Image.create(4, 4, false, Image.FORMAT_RGB8)
	im.fill(Color(0.2, 0.5, 0.8))
	im.save_png(SRC + "/ref.png")
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	m._load_scene("res://scenes/combo3.json")
	m.S.name = "packtest"
	m.S.audio_tracks = [{"path": SRC + "/hit.wav", "offset": 0.0, "gain_db": 0.0, "role": "sfx"}]
	Props.register("my testcrate", AABB(Vector3.ZERO, Vector3(0.4, 0.4, 0.3)), SRC + "/crate.obj", 1.0)
	m.S.props = [{"kind": "my testcrate", "xf": Transform3D.IDENTITY}]
	var d: Dictionary = m._scene_dict()
	d["ref_image"] = SRC + "/ref.png"
	# (1)
	var r := PackZip.pack(d, "packtest")
	ok(r["ok"] and r["path"] == "user://packs/packtest.kinezip" and FileAccess.file_exists(r["path"]), "packed to %s (%s)" % [r.get("path"), r.get("why")])
	var zr := ZIPReader.new()
	zr.open(r["path"])
	var names := files_of(zr)
	print("     entries: ", names)
	ok(names.size() == 5 and r["entries"] == 4 and names.has("manifest.json"), "4 entries + manifest.json (zip has %d, result says %d)" % [names.size(), r["entries"]])
	var man: Dictionary = JSON.parse_string(zr.read_file("manifest.json").get_string_from_utf8())
	var good := 0
	for f in man["files"]:
		var h := HashingContext.new()
		h.start(HashingContext.HASH_SHA256)
		h.update(zr.read_file(f["path"]))
		if h.finish().hex_encode() == String(f["sha256"]):
			good += 1
	ok(good == 4 and man["files"].size() == 4 and String(man["kine_version"]) == PackZip.version() and (man["missing"] as Array).is_empty(), "manifest: %d of 4 hashes equal the zip's bytes, Kine %s, nothing missing" % [good, man["kine_version"]])
	var orig_hash := FileAccess.get_sha256(SRC + "/hit.wav")
	var wav_ok := false
	for f in man["files"]:
		if String(f["path"]).ends_with("hit.wav") and f["sha256"] == orig_hash and String(f["path"]).begins_with("files/"):
			wav_ok = true
	ok(wav_ok, "the sound's recorded hash is the source file's own, under a relative path")
	zr.close()
	# (2)
	var u: Dictionary = m._unpack_to(r["path"], ROOT)
	await process_frame
	var dest := String(u.get("scene", "")).get_base_dir().get_base_dir()
	ok(u.get("ok", false) and dest.begins_with(ROOT) and m.scene_path == u["scene"], "unpacked to %s and the app opened %s" % [dest, m.scene_path])
	ok(m.S.name == "packtest" and m.S.cards.size() > 0 and m.S.props.size() == 1 and m.S.audio_tracks.size() == 1, "the opened scene has its %d cards, its prop and its sound" % m.S.cards.size())
	var refs := []
	PackZip._walk(JSON.parse_string(FileAccess.get_file_as_string(u["scene"])), func(s):
		if PackZip._looks_file(s):
			refs.append(s)
		return s)
	var inside := 0
	for p in refs:
		if FileAccess.file_exists(p) and String(p).begins_with(dest + "/"):
			inside += 1
	print("     refs: ", refs)
	ok(refs.size() == 3 and inside == refs.size(), "%d of %d referenced paths exist and lie inside %s" % [inside, refs.size(), dest])
	ok(m.S.audio_tracks.size() == 1 and String(m.S.audio_tracks[0]["path"]).begins_with(dest + "/") and FileAccess.get_sha256(m.S.audio_tracks[0]["path"]) == orig_hash, "the opened sound is the unpacked copy, same hash")
	# (3)
	var d2: Dictionary = d.duplicate(true)
	d2["ref_video"] = SRC + "/gone.mp4"
	var r3 := PackZip.pack(d2, "packtest_miss", "user://packs/packtest_miss.kinezip")
	var z3 := ZIPReader.new()
	z3.open(r3["path"])
	var man3: Dictionary = JSON.parse_string(z3.read_file("manifest.json").get_string_from_utf8())
	var n3 := files_of(z3).size()
	z3.close()
	ok((r3["missing"] as Array) == [SRC + "/gone.mp4"] and (man3["missing"] as Array) == [SRC + "/gone.mp4"] and n3 == 5, "the missing file is named in the result and in the manifest; the other %d entries are still packed" % (n3 - 1))
	# (4)
	var evil := "user://packtest_evil.kinezip"
	var zp := ZIPPacker.new()
	zp.open(evil)
	zp.start_file("manifest.json")
	zp.write_file(JSON.stringify({"files": [], "scene_file": "scene/a.json"}).to_utf8_buffer())
	zp.close_file()
	zp.start_file("../x")
	zp.write_file("evil".to_utf8_buffer())
	zp.close_file()
	zp.close()
	var dest4 := ROOT + "/evil"
	var r4 := PackZip.unpack(evil, dest4)
	ok(not r4["ok"] and String(r4["why"]).contains("..") and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dest4)) and not FileAccess.file_exists(ROOT + "/x"), "zip slip: an entry ../x refuses the zip, nothing written (%s)" % String(r4["why"]).left(60))
	# a changed byte: a copy of the pack with the manifest's recorded hash of the sound altered
	var zc := ZIPReader.new()
	zc.open(r["path"])
	var man5: Dictionary = JSON.parse_string(zc.read_file("manifest.json").get_string_from_utf8())
	for f in man5["files"]:
		if String(f["path"]).ends_with("hit.wav"):
			f["sha256"] = "0".repeat(64)   # the recorded hash no longer matches the bytes
	var zq := ZIPPacker.new()
	zq.open("user://packtest_flip.kinezip")
	for n in files_of(zc):
		zq.start_file(n)
		zq.write_file(JSON.stringify(man5).to_utf8_buffer() if n == "manifest.json" else zc.read_file(n))
		zq.close_file()
	zq.close()
	zc.close()
	var r5 := PackZip.unpack("user://packtest_flip.kinezip", ROOT + "/flip")
	ok(not r5["ok"] and String(r5["why"]).contains("sha256") and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(ROOT + "/flip")), "a hash that does not match its file is refused and nothing is written")
	var r6 := PackZip.unpack(r["path"], "res://scenes/_wip/packtest")
	ok(not r6["ok"] and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://scenes/_wip/packtest")), "unpack into res://scenes is refused")
	# (5)
	var after := listing("res://scenes")
	ok(before == after, "scenes/ unchanged: %d files before, %d after, every hash equal" % [before.size(), after.size()])
	var found := 0
	for b in m.ui_ribbon["EXPORT"].find_children("*", "Button", true, false):
		if b is Button and (m.label_of(b) == "Pack scene (zip)" or m.label_of(b) == "Unpack zip..."):
			found += 1
	ok(found == 2, "the Pack and Unpack buttons are in the EXPORT ribbon")
	for p in ["user://packs/packtest.kinezip", "user://packs/packtest_miss.kinezip", evil, "user://packtest_flip.kinezip"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	wipe(SRC)
	wipe(ROOT)
	print("PACKZIP TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(1 if fails else 0)
