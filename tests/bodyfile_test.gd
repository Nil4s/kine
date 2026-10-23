## godot --path . -s tests/bodyfile_test.gd     (ROADMAP_400 G07 .kbody; needs a window: the thumbnail is rendered)
## Bodies saved as files, listed in the Browser with a picture, and remembered by the scene that uses them.
## Bars, stated before the run:
##   - the edited body (a forearm triangle extruded in the model preview, applied: the instrument, its vertex count differs
##     from the mannequin's) saved with "Body: save the fighter's body (.kbody)": ONE file; the same command again writes
##     no second file
##   - SAVE / LOAD BIT FOR BIT: the file read back gives the fighter's body's vertex positions as the same bytes, the same
##     faces, and every "skin:<bone>" weight channel as the same bytes (the same channel names); params.proportions is the
##     scene's body
##   - SCENE REMEMBERS: the scene saved with that body names the file (body_mesh.file) and validates against the schema;
##     with the mannequin put back (instrument: the fighter's vertex count is the mannequin's again), opening the scene puts
##     the body back: vertex positions equal (bytes) and weights equal; no undo step is added by the open
##   - a second edit (one vertex moved 1 cm) applied and the scene saved under a new name WITHOUT saving the body: the save
##     writes a NEW .kbody (2 files now), the scene names it, and reopening it gives that body (positions equal)
##   - THUMBNAIL: the picture is non-empty: at least 3 % of its pixels differ from the backdrop by more than 0.1 in a
##     channel, and it is cached as user://thumbs/b_<file sha256>_<size>.png
##   - BROWSER: a "Bodies" folder lists every .kbody (2 rows), each row's icon is its picture; clicking a row (select) puts
##     that body on the fighter as ONE undo step (positions equal to the file's)
extends SceneTree

var fails := 0
var m: Node
const DIR := "user://bodyfile_test"
const SCN := "_wip/zz_bodyfile_scene"
const SCN2 := "_wip/zz_bodyfile_scene2"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func key(k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	root.push_input(e)
	var u := e.duplicate() as InputEventKey
	u.pressed = false
	root.push_input(u)


func cmd(name: String) -> void:
	for c in m._commands():
		if c["name"] == name:
			(c["run"] as Callable).call()
			return
	ok(false, "command '%s' is in the registry" % name)


func idle(n := 2) -> void:
	for i in n:
		await process_frame


func wipe() -> void:
	var g := ProjectSettings.globalize_path(DIR)
	if DirAccess.dir_exists_absolute(g):
		for f in DirAccess.get_files_at(g):
			DirAccess.remove_absolute(g.path_join(f))
	for s in [SCN, SCN2]:
		var p := ProjectSettings.globalize_path("res://scenes/%s.json" % s)
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


## the skin channels of two meshes: [same names, every channel's bytes equal, channels compared]
func same_weights(a: KMesh, b: KMesh) -> Array:
	var na := a.list_attrs().filter(func(x): return String(x).begins_with(BaseBody.W))
	var nb := b.list_attrs().filter(func(x): return String(x).begins_with(BaseBody.W))
	na.sort()
	nb.sort()
	var eq := true
	for nm in na:
		eq = eq and b.has_attr(nm) and (a.attr_data(nm) as PackedFloat32Array).to_byte_array() == (b.attr_data(nm) as PackedFloat32Array).to_byte_array()
	return [na == nb, eq, na.size()]


func scene_file(s: String) -> String:
	return "res://scenes/%s.json" % s


func _init() -> void:
	wipe()
	BodyFile.dir = DIR
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle()
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	var k0 := BaseBody.read(m)
	var skin := BaseBody.skin_of(m)

	# ---- edit the body in the model preview: extrude one forearm triangle, apply
	cmd("Model: edit the body mesh")
	await idle(1)
	var km: KMesh = m.kmed.mesh
	var la := km.attr_data("skin:lowerarm_r") as PackedFloat32Array
	var best := -1
	var bw := -1.0
	for fi in km.faces.size():
		var mn := 1.0
		for v in (km.faces[fi] as PackedInt32Array):
			mn = minf(mn, la[v])
		if mn > bw:
			bw = mn
			best = fi
	key(KEY_3)
	await idle(1)
	m.kmed.sel.faces = {best: true}
	key(KEY_E)
	await idle(1)
	cmd("Model: apply the body mesh to the fighter")
	await idle(1)
	key(KEY_ESCAPE)
	await idle()
	var kf := BaseBody.read(m)
	ok(kf.verts.size() == k0.verts.size() + 3, "INSTRUMENT: the applied body differs from the mannequin (%d verts vs %d)" % [kf.verts.size(), k0.verts.size()])

	# ---- save
	cmd("Body: save the fighter's body (.kbody)")
	var files := BodyFile.list()
	ok(files.size() == 1, "Body: save writes ONE .kbody (%s)" % [files])
	var path: String = files[0] if files.size() > 0 else ""
	cmd("Body: save the fighter's body (.kbody)")
	ok(BodyFile.list().size() == 1, "the same body saved again is the same file (still %d)" % BodyFile.list().size())
	print("info: %s is %.0f kB for %d verts, %d faces, %d weight channels" % [path.get_file(), FileAccess.get_file_as_bytes(path).size() / 1024.0, kf.verts.size(), kf.faces.size(), same_weights(kf, kf)[2]])

	# ---- load: bit for bit
	var b := BodyFile.load_file(path)
	ok(not b.is_empty(), "the .kbody loads (%s)" % BodyFile.last_error)
	var kl: KMesh = b.get("mesh", KMesh.new())
	ok(kl.verts.to_byte_array() == kf.verts.to_byte_array(), "LOAD: the %d vertex positions are the same bytes" % kl.verts.size())
	ok(kl.faces == kf.faces, "LOAD: the same %d faces" % kl.faces.size())
	var sw := same_weights(kf, kl)
	ok(sw[0] and sw[1] and int(sw[2]) > 20, "LOAD: every one of the %d skin:<bone> weight channels is the same bytes" % sw[2])
	var props = (b.get("params", {}) as Dictionary).get("proportions", null)
	ok(props is Dictionary and props == m._hero_scene().body, "the file carries the scene's proportions (%s)" % str(props))

	# ---- the scene remembers it
	m.ui_scene_name.text = SCN
	m._save_scene()
	await idle()
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(scene_file(SCN)))
	ok(d is Dictionary and (d as Dictionary).get("body_mesh", {}).get("file", "") == path, "the saved scene names the body file (body_mesh = %s)" % str((d as Dictionary).get("body_mesh") if d is Dictionary else null))
	ok(Validate.file(scene_file(SCN)).is_empty(), "the scene with body_mesh validates against docs/scene.schema.json (%s)" % str(Validate.file(scene_file(SCN))))
	BaseBody.restore_gen(m, 0)
	await idle(1)
	ok(BaseBody.read(m).verts.size() == k0.verts.size(), "INSTRUMENT: the mannequin is back on the fighter (%d verts)" % BaseBody.read(m).verts.size())
	var steps: int = m.undo.size()
	m._load_scene(scene_file(SCN))
	m._rebuild_cards()
	await idle()
	var kr := BaseBody.read(m)
	ok(kr.verts.to_byte_array() == kf.verts.to_byte_array(), "REOPEN: the scene puts its body back: %d vertex positions equal (bytes)" % kr.verts.size())
	var swr := same_weights(kf, kr)
	ok(swr[0] and swr[1], "REOPEN: every weight channel equal")
	ok(m.undo.size() == steps, "opening the scene adds no undo step (%d -> %d)" % [steps, m.undo.size()])

	# ---- an applied body with no file: the scene save writes one
	var k2 := BaseBody.read(m)
	k2.verts[0] = k2.verts[0] + Vector3(0.01, 0, 0)
	BaseBody.apply(m, k2)
	var k2r := BaseBody.read(m)
	m.ui_scene_name.text = SCN2
	m._save_scene()
	await idle()
	var files2 := BodyFile.list()
	var d2: Variant = JSON.parse_string(FileAccess.get_file_as_string(scene_file(SCN2)))
	var p2 := String((d2 as Dictionary).get("body_mesh", {}).get("file", "")) if d2 is Dictionary else ""
	ok(files2.size() == 2 and p2 != "" and p2 != path and files2.has(p2), "saving the scene saved its unsaved body as a NEW file (%s; %d files)" % [p2.get_file(), files2.size()])
	BaseBody.restore_gen(m, 0)
	m._load_scene(scene_file(SCN2))
	await idle()
	ok(BaseBody.read(m).verts.to_byte_array() == k2r.verts.to_byte_array() and k2r.verts.to_byte_array() != kf.verts.to_byte_array(), "REOPEN scene 2: its own body (the moved vertex) is back, positions equal")

	# ---- the thumbnail
	var th := BodyFile.thumbs(m)
	th.request(path)
	await th.settle()
	var tex := th.picture(path)
	var img: Image = tex.get_image() if tex != null else null
	var lit := 0
	var px := 0
	if img != null and not img.is_empty():
		px = img.get_width() * img.get_height()
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if maxf(absf(c.r - PoseLibrary.BG.r), maxf(absf(c.g - PoseLibrary.BG.g), absf(c.b - PoseLibrary.BG.b))) > 0.1:
					lit += 1
	ok(px > 0 and lit >= 0.03 * px, "THUMBNAIL: %dx%d, %d of %d pixels show the body (%.0f %%, >= 3 %%)" % [img.get_width() if img else 0, img.get_height() if img else 0, lit, px, 100.0 * lit / maxf(1, px)])
	print("info: pictures drawn %d, read from the cache %d" % [th.renders, th.disk_hits])
	ok(FileAccess.file_exists(BodyThumbs.cache_path(FileAccess.get_sha256(path))), "the picture is cached in %s" % BodyThumbs.cache_path(FileAccess.get_sha256(path)))

	# ---- the Browser
	var br: Tree = m.ui_browser
	br.refresh()
	await idle(3)
	await th.settle()
	br.refresh()
	await idle(3)
	var rows := {}
	var folder: TreeItem = null
	var it := br.get_root().get_first_child()
	while it != null:
		var md = it.get_metadata(0)
		if md is Dictionary and (md as Dictionary).has("kbody"):
			rows[md["kbody"]] = it
			folder = it.get_parent()
		it = it.get_next_in_tree()
	ok(rows.size() == 2 and rows.has(path) and rows.has(p2) and folder != null and folder.visible and folder.get_text(0).begins_with("Bodies"), "BROWSER: the Bodies folder lists both .kbody files (%s)" % [rows.keys()])
	ok(rows.has(path) and (rows[path] as TreeItem).get_icon(0) != null, "BROWSER: the row's icon is the body's picture")
	BaseBody.restore_gen(m, 0)
	var s0: int = m.undo.size()
	if rows.has(path):
		folder.collapsed = false
		(rows[path] as TreeItem).select(0)
	await idle()
	ok(BaseBody.read(m).verts.to_byte_array() == kf.verts.to_byte_array() and m.undo.size() == s0 + 1, "BROWSER: a click on the row puts that body on the fighter (positions equal), ONE undo step (%d -> %d)" % [s0, m.undo.size()])

	wipe()
	print("bodyfile: %d failed" % fails)
	quit(1 if fails > 0 else 0)
