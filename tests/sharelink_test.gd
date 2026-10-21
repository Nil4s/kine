## godot --headless --path . -s tests/sharelink_test.gd     (ROADMAP N23: share as a viewer page)
## combo3 -> the app's own command _share_viewer into user://zz_share. BARS (stated before measuring):
## (1) index.html and <scene>_one_file.html exist; the folder holds the .glb;
## (2) the base64 in the one-file page decodes to bytes whose sha256 equals the exported .glb's;
## (3) the .glb has exactly 1 animation and its key count equals the scene's frame count ceil(length*fps)+1;
## (4) the file size is reported (message names KB); (5) every http(s) address in both pages is the one pinned CDN script;
## (6) the page has the scene name, the Kine credit, a play/pause button and a range scrubber; (7) a scene with 1 card is refused with a next step.
extends SceneTree

var fails := 0
const ROOT := "user://zz_share"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func urls(s: String) -> Array:
	var r := RegEx.new()
	r.compile("https?://[^\\s\"'<>)]+")
	return r.search_all(s).map(func(m): return m.get_string())


func _init() -> void:
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	m._load_scene("res://scenes/combo3.json")
	var r: Dictionary = m._share_viewer(ROOT, false)
	ok(not r.is_empty(), "command returned the paths")
	var said: String = m.ui_status.text if m.ui_status != null else ""
	print("     said: ", said)
	ok(said.contains(" KB") and said.contains("Nothing was uploaded"), "the message reports the size in KB and that nothing was uploaded")
	var idx := FileAccess.get_file_as_string(r["index"])
	var one := FileAccess.get_file_as_string(r["one"])
	ok(idx.length() > 1000 and one.length() > 1000 and FileAccess.file_exists(r["glb"]), "index.html, one-file page and the .glb exist")
	var glb := FileAccess.get_file_as_bytes(r["glb"])
	var rx := RegEx.new()
	rx.compile("const b64 = \"([A-Za-z0-9+/=]+)\"")
	var mt := rx.search(one)
	ok(mt != null, "the one-file page embeds a base64 string")
	var dec := Marshalls.base64_to_raw(mt.get_string(1)) if mt != null else PackedByteArray()
	ok(dec.size() == glb.size() and hash_eq(dec, r["glb"]), "decoded bytes sha256 == exported .glb (%d bytes)" % glb.size())
	var info := ShareLink.glb_info(glb)
	var want := int(ceil(m.S.length() * m.S.fps - 1e-6)) + 1
	ok(info["anims"] == 1, "the .glb has %d animation" % info["anims"])
	ok(info["frames"] == want, "animation keys %d == scene frames %d (%.3f s at %d fps)" % [info["frames"], want, m.S.length(), m.S.fps])
	print("     sizes: .glb %.1f KB, one-file page %.1f KB, index.html %.1f KB" % [glb.size() / 1024.0, r["one_bytes"] / 1024.0, idx.length() / 1024.0])
	ok(r["one_bytes"] > glb.size() * 1.33 and r["one_bytes"] < glb.size() * 1.4 + 6000, "one-file size is the base64 of the .glb plus the page (~4/3)")
	for pg in [idx, one]:
		var u := urls(pg)
		ok(u.size() == 1 and u[0] == ShareLink.CDN, "only address in a page: %s" % [u])
	ok(one.contains("combo3") and one.contains("Teschima Studios") and one.contains("id=\"pp\"") and one.contains("type=\"range\"") and one.contains("camera-controls"), "page has the name, the credit, play/pause, scrubber, orbit")
	ok(idx.contains("mv.src = \"combo3.glb\""), "index.html loads the .glb beside it")
	ok(one.contains("customElements.whenDefined(\"model-viewer\")") and one.contains("const num = ") and one.contains("\"loadfailure\""), "page waits for <model-viewer> before reading its clock; error banner only on a real load failure (seen false in the browser 10-20)")
	var keep: Array = m.S.cards.duplicate()
	m.S.cards = [keep[0]]
	var none: Dictionary = m._share_viewer(ROOT, false)
	m.S.cards = keep
	var said1: String = m.ui_status.text if m.ui_status != null else ""
	ok(none.is_empty() and said1.begins_with("NOT NOW") and said1.contains("press Enter"), "one card: refused with a next step (%s)" % said1)
	if OS.get_environment("SHARELINK_KEEP") != "":
		print("kept: ", ProjectSettings.globalize_path(ROOT))
		quit(fails)
		return
	var g := ProjectSettings.globalize_path(ROOT + "/combo3")
	for f in DirAccess.get_files_at(g):
		DirAccess.remove_absolute(g + "/" + f)
	DirAccess.remove_absolute(g)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ROOT))
	print("SHARELINK %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


func hash_eq(dec: PackedByteArray, path: String) -> bool:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(dec)
	return h.finish().hex_encode() == FileAccess.get_sha256(path)
