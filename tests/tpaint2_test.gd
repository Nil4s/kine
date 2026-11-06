extends SceneTree
## godot --path . -s tests/tpaint2_test.gd     (L55 TPAINT2, follows L53 tpaint: the painted texture is saved with the scene and comes back;
## the auto-unwrap that Texture mode runs is one undo step). The app bar needs a window; the rest is data.
## BARS WRITTEN AND COMMITTED BEFORE THE IMPLEMENTATION (scripts/kmesh_tpaint_file.gd, KMeshVPaintUI.unwrap_undoable and tex_pending, the scene hooks in main.gd).
##   a SAVE / RELOAD: a 2-stamp stroke on a UV sphere (1024 tex). The texture is recorded in the scene dict, its PNG written beside the scene, the dict
##     round-tripped through JSON, the PNG read back into a fresh KMeshTPaint on the same UVs: SHA-256 equal to the texture before the save and to the record
##   b PNG MISSING: the same scene with the PNG deleted: load_for gives a warning that names the file, no crash, the fresh texture stays blank (SHA = blank)
##   c UNWRAP UNDO: a UV-less sphere: the auto-unwrap (60 deg seams + LSCM) through a KMeshUndo gives a UV hash != "none"; undo() restores the EXACT UV hash
##     "none" and removes the seam flags; redo() gives the unwrap hash back. The unwrap is deterministic (a second sphere gives the same UV hash)
##   d PLANTED FAILS: (1) the same unwrap WITHOUT an undo step: undo() leaves the UV hash set (the gap is real, bar c would catch it); (2) one byte of the
##     saved PNG changed: the reload refuses it (its SHA-256 differs from the record), so a corrupt file never paints
##   e APP: Texture mode on the model preview, a texture edit, the record and PNG, then a fresh tp in Texture mode again: the SHA-256 comes back equal
## Numbers are printed. The app PNG is written to C:/Temp/claude/L55/tpaint2.png (512 px).

var fails := 0
const SCENE_DIR := "user://tpaint2_scene"
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	call_deferred("run")


func mvp() -> Projection:
	return Projection.create_perspective(50.0, 1.0, 0.05, 50.0) * Projection(Transform3D(Basis(), Vector3(0, 0, 3)).affine_inverse())


func sphere_uv() -> KMesh:
	var k: KMesh = KMeshPrims.uv_sphere(1.0, 32, 16)
	KMeshUV.project_sphere(k)
	return k


func stroke(tp: KMeshTPaint) -> int:
	tp.begin_stroke()
	var n := tp.stamp(mvp(), Vector3(0, 0, 3), Vector2i(512, 512), Vector2(256, 256), 120.0, Color(0.1, 0.8, 0.1), 1.0, 0.5, 2)
	n += tp.stamp(mvp(), Vector3(0, 0, 3), Vector2i(512, 512), Vector2(330, 250), 90.0, Color(0.9, 0.1, 0.1), 1.0, 0.5, 2)
	tp.end_stroke()
	return n


func uvh(k: KMesh) -> String:
	return KMeshTPaintFile.uv_hash(k)


func run() -> void:
	var dir_abs := ProjectSettings.globalize_path(SCENE_DIR)
	DirAccess.make_dir_recursive_absolute(dir_abs)
	var png_abs := dir_abs.path_join("t_tpaint.png")

	# a SAVE / RELOAD
	var k := sphere_uv()
	var uv0 := uvh(k)
	var tp := KMeshTPaint.new(k, 1024)
	var blank := tp.hash()
	var n := stroke(tp)
	var sha_before := tp.hash()
	ok(n > 100 and sha_before != blank, "a1 the stroke painted the texture (%d texels, hash changed %s)" % [n, sha_before != blank])
	var src := {"data": tp.data(), "size": tp.size, "uv": uv0}
	var d := {"name": "t"}
	KMeshTPaintFile.record(d, src, "t_tpaint.png")
	var wrote := KMeshTPaintFile.write_png(src, png_abs)
	var d2: Dictionary = JSON.parse_string(JSON.stringify(d))
	ok(wrote and FileAccess.file_exists(png_abs) and d2.has(KMeshTPaintFile.KEY), "a2 saved: the PNG sits beside the scene and the scene dict records it (png %s)" % str(d2.get(KMeshTPaintFile.KEY, {}).get("png", "")))
	var k2 := sphere_uv()
	var got := KMeshTPaintFile.load_for(dir_abs, d2)
	var tp2 := KMeshTPaint.new(k2, 1024)
	var applied := KMeshTPaintFile.apply(tp2, got, uvh(k2))
	var sha_back := tp2.hash()
	ok(got.has("data") and applied and sha_back == sha_before and sha_back == String(d2[KMeshTPaintFile.KEY]["sha"]),
		"a3 reload: SHA-256 equal (saved %s, reloaded %s, record %s)" % [sha_before.left(12), sha_back.left(12), String(d2[KMeshTPaintFile.KEY]["sha"]).left(12)])

	# b PNG MISSING
	DirAccess.remove_absolute(png_abs)
	var gone := KMeshTPaintFile.load_for(dir_abs, d2)
	var tp3 := KMeshTPaint.new(sphere_uv(), 1024)
	var applied3 := KMeshTPaintFile.apply(tp3, gone, uv0)
	var warn := String(gone.get("warn", ""))
	ok(warn.find("t_tpaint.png") >= 0 and not gone.has("data") and not applied3 and tp3.hash() == blank,
		"b1 PNG missing: a warning names it (\"%s\"), no crash, the texture stays blank (%s)" % [warn.left(60), tp3.hash() == blank])

	# c UNWRAP UNDO
	var raw := KMeshPrims.uv_sphere(1.0, 32, 16)
	var h_none := uvh(raw)
	ok(h_none == "none" and not raw.has_attr("uv"), "c0 a UV-less sphere has no uv attribute (hash \"%s\")" % h_none)
	var u := KMeshUndo.new()
	KMeshVPaintUI.unwrap_undoable(u, raw)
	var h_un := uvh(raw)
	var seams_on := raw.has_attr(KMeshUV.SEAM)
	u.undo()
	var h_back := uvh(raw)
	var seams_back := raw.has_attr(KMeshUV.SEAM)
	u.redo()
	var h_redo := uvh(raw)
	ok(h_un != "none" and seams_on and h_back == "none" and not seams_back and h_redo == h_un,
		"c1 unwrap = 1 undo step: UV hash %s after, %s after undo (exact \"none\": %s), seams back %s, redo restores %s" % [h_un.left(12), h_back, h_back == "none", seams_back, h_redo == h_un])
	var again := KMeshPrims.uv_sphere(1.0, 32, 16)
	KMeshVPaintUI.unwrap_undoable(KMeshUndo.new(), again)
	ok(uvh(again) == h_un, "c2 the unwrap is deterministic: a second sphere gives the same UV hash (%s)" % (uvh(again) == h_un))

	# d PLANTED FAILS
	var rawc := KMeshPrims.uv_sphere(1.0, 32, 16)
	KMeshUV.seams_by_angle(rawc, 60.0)
	KMeshUV.unwrap_lscm(rawc)
	var uc := KMeshUndo.new()
	uc.undo()
	ok(uvh(rawc) != "none", "d1 PLANTED: an unwrap with no undo step is NOT taken back (UV hash still set, %s): the gap c guards is real" % (uvh(rawc) != "none"))
	var bad := tp.data()
	bad[1000] = 255 - bad[1000]
	KMeshTPaintFile.write_png({"data": bad, "size": 1024, "uv": uv0}, png_abs)
	var altered := KMeshTPaintFile.load_for(dir_abs, d2)
	ok(not altered.has("data") and String(altered.get("warn", "")) != "", "d2 PLANTED: one byte changed in the saved PNG: the reload refuses it (\"%s\")" % String(altered.get("warn", "")).left(70))

	# e APP
	await app_bars(dir_abs)

	print("tpaint2: %d fail, %d ok" % [fails, 0])
	quit(1 if fails > 0 else 0)


func app_bars(dir_abs: String) -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var line: Dictionary = {}
	for t in MeshTools.TOOLS:
		if t["id"] == "mesh_tpaint":
			line = t
	if line.is_empty():
		ok(false, "e0 the S box has a \"Model: texture paint on / off\" line")
		return
	MeshTools.run(line, m)
	await idle(4)
	var pu := KMeshVPaintUI.of(m)
	var ui = m.kmed
	var mesh: KMesh = ui.mesh
	var uv_app := uvh(mesh)
	var tpa: KMeshTPaint = pu.tp
	var blank_app := tpa.hash() if tpa != null else ""
	ok(pu.tex_mode and tpa != null and uv_app != "none", "e1 Texture mode on the model preview (engine %s, UV hash %s)" % [tpa.engine if tpa != null else "-", uv_app.left(12)])
	var px := tpa.data()
	for i in 4000:
		px[i * 7] = 0
	tpa.set_data(px)
	var sha_app := tpa.hash()
	var src := pu.texture_source()
	var dd := {}
	KMeshTPaintFile.record(dd, src, "app_tpaint.png")
	KMeshTPaintFile.write_png(src, dir_abs.path_join("app_tpaint.png"))
	var dd2: Dictionary = JSON.parse_string(JSON.stringify(dd))
	DirAccess.make_dir_recursive_absolute("C:/Temp/claude/L55")
	var img := tpa.image()
	img.resize(512, 512, Image.INTERPOLATE_BILINEAR)
	img.save_png("C:/Temp/claude/L55/tpaint2.png")
	pu.set_tex_mode(false)
	pu.tp = null
	KMeshTPaintFile.from_scene(m, dd2, dir_abs.path_join("app.json"))
	await idle(2)
	pu.set_tex_mode(true)
	await idle(2)
	var back: String = pu.tp.hash() if pu.tp != null else ""
	ok(back == sha_app and sha_app != blank_app, "e2 app: the stroke's SHA-256 comes back through the scene (edit %s, reloaded %s, changed from blank %s)" % [sha_app.left(12), back.left(12), sha_app != blank_app])
	pu.set_tex_mode(false)
	await idle(2)
