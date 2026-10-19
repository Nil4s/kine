## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/assetstore_test.gd     (ROADMAP 96; a window)
## THE ASSET STORE (scripts/pose_pack.gd): a pose shared as one .kinepack file and imported back. Bars:
##   round trip  share, read, import: the imported pose file is byte-identical to the shared one; its picture too
##   refusals    a tampered pack (hash), a joint at 400 deg, an extra script key (in the pose and at the top), a 6 MB pack:
##               each refused with its reason named, nothing imported
##   clash       the same pack imported again is "Guard bat (2)", then "(3)": the first file is not overwritten
##   undo        one undo step per import; Ctrl+Z moves the file to the library's trash, redo brings it back
##   retarget    a pack of another skeleton: its bones kept by name, the dropped bone named, said on the status line
##   no writes   poses/ and moves/ untouched (md5 before and after)
##   picture     the import dialog for the shared pack: its thumbnail, name, author and licence, inside the window;
##               saved to $ASSETSTORE_SHOT (default C:/Users/Nick/.claude/jobs/9afc22db/tmp/assetstore.png) and read
extends SceneTree

var fails := 0
var m: Node
var tmp := ""


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func nick_files() -> Dictionary:
	var out := {}
	for d in ["res://poses", "res://poses/lib", "res://moves"]:
		var da := DirAccess.open(d)
		if da == null:
			continue
		for f in da.get_files():
			out[d + "/" + f] = FileAccess.get_md5(d + "/" + f)
	return out


func _put(p: String, b: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(p.get_base_dir()))
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_buffer(b)
	f.close()


func _rm(p: String) -> void:
	var d := DirAccess.open(p)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p.path_join(f)))
	for s in d.get_directories():
		_rm(p.path_join(s))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	var before := nick_files()
	tmp = "user://zz_assetstore_%d" % OS.get_process_id()
	m.library = tmp.path_join("lib")   # the library of this test only
	# the source pose: the library's own guard, copied into the test's folder (the library's file is only read)
	var src := tmp.path_join("src/guard_bat.json")
	var raw := FileAccess.get_file_as_bytes("res://poses/lib/guard_bat.json")
	_put(src, raw)
	var lib := PoseLibrary.new()
	lib.m = m
	lib.dirs = [tmp.path_join("src")]
	m.ui_root.add_child(lib)
	await process_frame
	await lib.settle()
	var thumb: PackedByteArray = lib.thumb_png(src)
	ok(thumb.size() > 1000, "the pose's picture is there (%d bytes)" % thumb.size())
	var out := tmp.path_join("out")

	# ---- round trip
	var shared := out.path_join("guard.kinepack")
	var s := PosePack.share(src, shared, "Guard bat", "Nick", "CC-BY", thumb, "9.9.9")
	ok(s["ok"], "share writes the pack: %s" % s["why"])
	var rd := PosePack.read(shared)
	ok(rd["ok"], "the pack reads back and checks out: %s" % rd["why"])
	var pk: Dictionary = rd["pack"]
	ok(pk["name"] == "Guard bat" and pk["author"] == "Nick" and pk["licence"] == "CC-BY", "name, author and licence come back as typed")
	ok(String(pk["pose_text"]).to_utf8_buffer() == raw, "the pack carries the pose file's bytes")
	var u0: int = m.undo.size()
	var c1 := PosePack.commit(m, pk)
	ok(c1["ok"] and c1["name"] == "Guard bat" and not c1["renamed"], "import: 'Guard bat' into Library > Imported")
	ok(FileAccess.get_file_as_bytes(c1["path"]) == raw, "the imported pose file is byte-identical to the shared one")
	ok(FileAccess.get_file_as_bytes(c1["files"][1]) == thumb, "the imported picture is the one shared")
	ok(m.undo.size() == u0 + 1, "one import = one undo step (%d -> %d)" % [u0, m.undo.size()])

	# ---- clash: no overwrite, rename
	var first := FileAccess.get_file_as_bytes(c1["path"])
	var c2 := PosePack.commit(m, pk)
	ok(c2["ok"] and c2["name"] == "Guard bat (2)" and c2["renamed"], "importing it again gives 'Guard bat (2)', not an overwrite")
	ok(FileAccess.get_file_as_bytes(c1["path"]) == first, "the first 'Guard bat' is untouched")
	var c3 := PosePack.commit(m, pk)
	ok(c3["ok"] and c3["name"] == "Guard bat (3)", "a third import is 'Guard bat (3)'")
	ok(m.undo.size() == u0 + 3, "each import is one undo step (%d steps for 3 imports)" % (m.undo.size() - u0))

	# ---- undo: the file to the trash, redo back
	m._undo()
	ok(not FileAccess.file_exists(c3["path"]) and FileAccess.file_exists(tmp.path_join("lib/trash/Guard bat (3).json")),
		"Ctrl+Z moves 'Guard bat (3)' to the library's trash")
	m._redo()
	ok(FileAccess.file_exists(c3["path"]), "redo brings it back into Library > Imported")

	# ---- refusals, each named
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(shared))
	d["pose"] = String(d["pose"]) + " "
	var tp := out.path_join("tampered.kinepack")
	_put(tp, JSON.stringify(d, " ").to_utf8_buffer())
	var tr := PosePack.read(tp)
	ok(not tr["ok"] and String(tr["why"]).contains("content hash mismatch"), "tampered pack refused: '%s'" % tr["why"])

	var hot: Dictionary = JSON.parse_string(raw.get_string_from_utf8())
	hot["joints"]["lowerarm_r"] = {"bend": 400.0, "side": 0.0, "twist": 0.0}
	var hp := out.path_join("hot.kinepack")
	PosePack.write(PosePack.build(JSON.stringify(hot, " "), "Too far", "", "CC0", thumb), hp)
	var hr := PosePack.read(hp)
	ok(not hr["ok"] and String(hr["why"]).contains("lowerarm_r") and String(hr["why"]).contains("out of its range"),
		"a joint at 400 deg refused: '%s'" % hr["why"])

	var sc: Dictionary = JSON.parse_string(raw.get_string_from_utf8())
	sc["script"] = "print('run me')"
	var scp := out.path_join("script_pose.kinepack")
	PosePack.write(PosePack.build(JSON.stringify(sc, " "), "Scripted", "", "CC0", thumb), scp)
	var scr := PosePack.read(scp)
	ok(not scr["ok"] and String(scr["why"]).contains("unknown key 'script'"), "an extra script key in the pose refused: '%s'" % scr["why"])
	var top := PosePack.build(raw.get_string_from_utf8(), "Scripted top", "", "CC0", thumb)
	top["script"] = "print('run me')"
	var tpp := out.path_join("script_top.kinepack")
	PosePack.write(top, tpp)
	var tpr := PosePack.read(tpp)
	ok(not tpr["ok"] and String(tpr["why"]).contains("unknown key 'script' at the top"), "an extra script key in the pack refused: '%s'" % tpr["why"])

	var big := PackedByteArray()
	big.resize(6 * 1024 * 1024)
	big.fill(32)
	var bp := out.path_join("big.kinepack")
	_put(bp, big)
	var br := PosePack.read(bp)
	ok(not br["ok"] and String(br["why"]).contains("6.0 MB") and String(br["why"]).contains("limit is 5 MB"), "a 6 MB pack refused unread: '%s'" % br["why"])

	# ---- retarget: another skeleton keeps the bones it shares and names the rest
	var pd: Dictionary = JSON.parse_string(raw.get_string_from_utf8())
	pd["joints"]["tail_01"] = {"bend": 10.0, "side": 0.0, "twist": 0.0}
	var foreign := PosePack.build(JSON.stringify(pd, " "), "Tailed", "", "CC0", thumb)
	foreign["skeleton"] = "other-rig"
	var fp := out.path_join("tailed.kinepack")
	PosePack.write(foreign, fp)
	var fr := PosePack.read(fp)
	ok(fr["ok"] and fr["pack"]["retargeted"] and fr["pack"]["dropped"] == ["tail_01"], "another skeleton: retargeted by bone name, tail_01 dropped: '%s'" % fr["why"])
	ok(String(fr["pack"]["note"]).contains("retargeted by bone name") and String(fr["pack"]["note"]).contains("tail_01"),
		"and the status says so: '%s'" % fr["pack"]["note"])
	var fc := PosePack.commit(m, fr["pack"])
	ok(fc["ok"] and not JSON.parse_string(FileAccess.get_file_as_string(fc["path"]))["joints"].has("tail_01"),
		"the retargeted pose is imported without the dropped bone")

	# ---- nothing written under poses/ or moves/
	var after := nick_files()
	ok(after == before, "poses/ and moves/ untouched (%d files compared)" % before.size())

	# ---- the import dialog with the shared pack: picture, name, author, licence
	var dlg := PosePack.pack_dialog(m, pk, Callable())
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var shot := OS.get_environment("ASSETSTORE_SHOT")
	if shot == "":
		shot = "C:/Users/Nick/.claude/jobs/9afc22db/tmp/assetstore.png"
	var img := m.get_viewport().get_texture().get_image()
	img.save_png(shot)
	var tex := dlg.find_child("pack_thumb", true, false) as TextureRect
	ok(tex != null and tex.texture != null and tex.texture.get_width() == 160, "the dialog shows the pack's picture (%s px)" % (tex.texture.get_size() if tex and tex.texture else "none"))
	var nl := dlg.find_child("pack_name", true, false) as Label
	var al := dlg.find_child("pack_author", true, false) as Label
	var ll := dlg.find_child("pack_licence", true, false) as Label
	ok(nl != null and nl.text.contains("Guard bat") and al != null and al.text.contains("Nick") and ll != null and ll.text.contains("CC-BY"),
		"the dialog names it: '%s' / '%s' / '%s'" % [nl.text if nl else "", al.text if al else "", ll.text if ll else ""])
	var vp := m.get_viewport().get_visible_rect().size
	ok(dlg.visible and dlg.position.x >= 0 and dlg.position.y >= 0 and dlg.position.x + dlg.size.x <= vp.x and dlg.position.y + dlg.size.y <= vp.y,
		"the dialog sits inside the window (%s at %s, window %s)" % [dlg.size, dlg.position, vp])
	print("shot: %s" % shot)
	dlg.hide()
	dlg.queue_free()
	await process_frame
	_rm(tmp)
	print("%s" % ("ALL OK" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)
