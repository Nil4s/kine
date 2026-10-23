## godot --position -30000,-30000 --audio-driver Dummy --path . -s tests/meshwords_test.gd    (ROADMAP_400 B29, MODELING FROM WORDS;
## scripts/mesh_words.gd through the words box: command_search.gd -> main._pose_words)
## The test cube is KMeshEditUI's: 0.6 m a side, 4x4 quads a side = 96 faces, top at y = +0.30 (mesh space). Each bar starts
## from a fresh cube. Bars, written before measuring:
##   1 EXTRUDE: "extrude the top 5 cm" -> the highest vert y = 0.30 + 0.05 within 0.1 mm, the 16 new top faces (selected) all
##     at y 0.35 within 0.1 mm, 96 -> 112 faces (16 side quads), ONE KMeshUndo step, the reply says "5.00 cm"
##   2 THICKER: "make it 2 cm thicker" (the whole closed cube) -> 0.62 m on every axis within 0.1 mm, every face still flat
##     (max vert distance from its face plane < 0.01 mm); "make the top 2 cm thicker" -> top y +0.02 within 0.1 mm, bottom
##     unmoved within 0.01 mm; each one step, the replies say "2.00 cm"
##   3 SUBDIVIDE: "subdivide it twice" -> 96 x 16 = 1536 faces, one step, the reply says "96 -> 1536 faces"
##   4 CYLINDER: "add a cylinder 30 cm tall" -> the new verts span 0.30 m in y within 0.1 mm, one step, the reply says "30.0 tall"
##   5 TRIANGULATE: "triangulate" -> 192 faces, every one a triangle, one step
##   6 MEASURE: "how big is it" and "measure it" -> the reply says "60.0 wide x 60.0 tall x 60.0 deep cm" and the volume
##     216000 cm³; ZERO steps, the verts unchanged
##   7 DELETE: the 16 top faces selected, "delete the selected faces" -> 80 faces, none of them facing up at y 0.30, one step
##   8 SCALE: "scale it up 20%" -> 0.72 m on every axis within 0.1 mm, the centre unmoved within 0.01 mm, one step
##   9 UNITS: parse gives "extrude the top 5 mm" 0.005, "two centimetres" 0.02, "0.1 m" 0.1, "3" 0.03 (said as cm), "1 inch"
##     0.0254; "subdivide it three times" 3 levels; "scale it down 10%" 0.9; "make it twice as big" 2.0; live: "extrude the
##     bottom two cm" moves the lowest y from -0.30 to -0.32 within 0.1 mm
##  10 UNDO: after every edit above, one Ctrl+Z (the preview's undo) gives back the verts and faces exactly
##  11 UNKNOWN / NOT BUILT: "extrdue the top 5 cm" changes nothing and the reply lists "extrude the top 5 cm" as a close match;
##     "bevel the edges 1 cm" parses, changes nothing and says "bevel isn't built yet"
##  12 NO STEALING: with the model preview open, "add a tail with 8 bones" adds a tail (S.rigx) and leaves the mesh alone,
##     "tired and angry" keys the face (the mesh alone), "raise the right arm 90" poses the arm; MeshWords.claims is false
##     for each, open or not. The words box's first row is "Model: ..." for "extrude the top 5 cm", "Rig: ..." for the tail,
##     "Face: ..." for "tired and angry"; Enter on the Model row extrudes (one step); a lone
##     word ("extrude") still finds the tool's own row first, not a words row. Off the model page, command words
##     ("delete all keys", "add a marker", "scale") are not claimed; surely-modeling phrases ("extrude the top 5 cm") are
extends SceneTree

var fails := 0
var m: Node
var ui: KMeshEditUI


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func fresh() -> void:
	if ui != null and ui.on:
		ui.stop()
	m._kmesh_edit_start()
	ui = m.kmed


func say(t: String) -> Dictionary:
	var n0 := ui.undo.steps.size()
	var r: Dictionary = m._pose_words(t)
	r["n"] = ui.undo.steps.size() - n0
	r["status"] = String(m.ui_status.text)
	print("   \"%s\" -> %s" % [t, r["status"]])
	return r


func ylo() -> float:
	var y := INF
	for v in ui.mesh.verts:
		y = minf(y, v.y)
	return y


func yhi() -> float:
	var y := -INF
	for v in ui.mesh.verts:
		y = maxf(y, v.y)
	return y


func box() -> AABB:
	return MeshWords.bbox(ui.mesh)


## one Ctrl+Z gives back exactly what was there
func undo_back(v0: PackedVector3Array, f0: Array, what: String) -> void:
	ui.undo.undo()
	ui.sel.clear()   # the preview's Ctrl+Z clears the selection too (kmesh_edit_ui._edit_key)
	ok(ui.mesh.verts == v0 and KMeshUndo._same_faces(ui.mesh.faces, f0), "10 one Ctrl+Z after %s gives the cube back exactly (%d verts, %d faces)" % [what, ui.mesh.vert_count(), ui.mesh.face_count()])


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	m._commands()
	fresh()
	await idle(2)
	ok(ui.mesh.face_count() == 96 and absf(yhi() - 0.30) < 1e-6, "0 the test cube: %d faces, top y %.4f m" % [ui.mesh.face_count(), yhi()])

	# 1 EXTRUDE
	var v0 := ui.mesh.verts.duplicate()
	var f0 := ui.mesh.faces.duplicate()
	var r := say("extrude the top 5 cm")
	var worst := 0.0
	for fi in ui.sel.faces:
		worst = maxf(worst, absf(ui.mesh.face_center(fi).y - 0.35))
	ok(absf(yhi() - 0.35) < 1e-4, "1 extrude the top 5 cm: top y %.5f m (bar 0.35000 within 0.1 mm)" % yhi())
	ok(ui.sel.faces.size() == 16 and worst < 1e-4, "1 the 16 new top faces selected, worst %.4f mm off y 0.35 (bar 0.1 mm); %d selected" % [worst * 1000.0, ui.sel.faces.size()])
	ok(ui.mesh.face_count() == 112 and r["n"] == 1 and "5.00 cm" in r["status"], "1 96 -> %d faces (bar 112), %d undo step (bar 1), reply says 5.00 cm" % [ui.mesh.face_count(), r["n"]])
	undo_back(v0, f0, "extrude")

	# 2 THICKER
	r = say("make it 2 cm thicker")
	var b := box()
	var flat := 0.0
	for fi in ui.mesh.face_count():
		var n: Vector3 = ui.mesh.face_normals[fi]
		var c := ui.mesh.face_center(fi)
		for vi in (ui.mesh.faces[fi] as PackedInt32Array):
			flat = maxf(flat, absf((ui.mesh.verts[vi] - c).dot(n)))
	ok(absf(b.size.x - 0.62) < 1e-4 and absf(b.size.y - 0.62) < 1e-4 and absf(b.size.z - 0.62) < 1e-4, "2 2 cm thicker: %.5f x %.5f x %.5f m (bar 0.62 within 0.1 mm)" % [b.size.x, b.size.y, b.size.z])
	ok(flat < 1e-5 and r["n"] == 1 and "2.00 cm" in r["status"], "2 every face still flat (worst %.6f mm, bar 0.01 mm), %d step, reply says 2.00 cm" % [flat * 1000.0, r["n"]])
	undo_back(v0, f0, "thicker")
	r = say("make the top 2 cm thicker")
	ok(absf(yhi() - 0.32) < 1e-4 and absf(ylo() + 0.30) < 1e-5 and r["n"] == 1 and "2.00 cm" in r["status"], "2 the top 2 cm thicker: top y %.5f (bar 0.32), bottom y %.5f (bar -0.30), %d step" % [yhi(), ylo(), r["n"]])
	undo_back(v0, f0, "top thicker")

	# 3 SUBDIVIDE
	r = say("subdivide it twice")
	ok(ui.mesh.face_count() == 1536 and r["n"] == 1 and "96 -> 1536 faces" in r["status"], "3 subdivide it twice: %d faces (bar 96 x 16 = 1536), %d step" % [ui.mesh.face_count(), r["n"]])
	undo_back(v0, f0, "subdivide")

	# 4 CYLINDER
	var nv0 := ui.mesh.vert_count()
	r = say("add a cylinder 30 cm tall")
	var cb := MeshWords.bbox(ui.mesh, range(nv0, ui.mesh.vert_count()))
	ok(ui.mesh.vert_count() > nv0 and absf(cb.size.y - 0.30) < 1e-4 and r["n"] == 1 and "30.0 tall" in r["status"], "4 add a cylinder 30 cm tall: %d new verts span %.5f m in y (bar 0.30 within 0.1 mm), %d step" % [ui.mesh.vert_count() - nv0, cb.size.y, r["n"]])
	undo_back(v0, f0, "add a cylinder")

	# 5 TRIANGULATE
	r = say("triangulate")
	var tris := ui.mesh.faces.all(func(f): return (f as PackedInt32Array).size() == 3)
	ok(ui.mesh.face_count() == 192 and tris and r["n"] == 1, "5 triangulate: %d faces (bar 192), all triangles %s, %d step" % [ui.mesh.face_count(), tris, r["n"]])
	undo_back(v0, f0, "triangulate")

	# 6 MEASURE
	for t in ["how big is it", "measure it"]:
		r = say(t)
		ok("60.0 wide x 60.0 tall x 60.0 deep cm" in r["status"] and "216000 cm³" in r["status"] and r["n"] == 0 and ui.mesh.verts == v0, "6 '%s': 60.0 x 60.0 x 60.0 cm and 216000 cm³ said, %d steps (bar 0), nothing moved" % [t, r["n"]])

	# 7 DELETE
	var top := MeshWords.faces_of(ui, "top")
	ui.sel.clear()
	ui.sel.mode = KMeshSelect.FACE
	for fi in top:
		ui.sel.faces[fi] = true
	r = say("delete the selected faces")
	var up := 0
	for fi in ui.mesh.face_count():
		if (ui.mesh.face_normals[fi] as Vector3).y > 0.9 and absf(ui.mesh.face_center(fi).y - 0.30) < 1e-4:
			up += 1
	ok(top.size() == 16 and ui.mesh.face_count() == 80 and up == 0 and r["n"] == 1, "7 delete the selected faces (%d top faces): %d faces (bar 80), %d still facing up at the top (bar 0), %d step" % [top.size(), ui.mesh.face_count(), up, r["n"]])
	undo_back(v0, f0, "delete")

	# 8 SCALE
	var c0 := box().get_center()
	r = say("scale it up 20%")
	b = box()
	ok(absf(b.size.x - 0.72) < 1e-4 and absf(b.size.y - 0.72) < 1e-4 and absf(b.size.z - 0.72) < 1e-4 and b.get_center().distance_to(c0) < 1e-5 and r["n"] == 1,
		"8 scale it up 20%%: %.5f x %.5f x %.5f m (bar 0.72 within 0.1 mm), centre moved %.4f mm, %d step" % [b.size.x, b.size.y, b.size.z, b.get_center().distance_to(c0) * 1000.0, r["n"]])
	undo_back(v0, f0, "scale")

	# 9 UNITS
	var want := {"extrude the top 5 mm": 0.005, "extrude the top two centimetres": 0.02, "extrude the top 0.1 m": 0.1, "extrude the top 3": 0.03, "extrude the top 1 inch": 0.0254, "make it 4mm thicker": 0.004}
	for t in want:
		var p := MeshWords.parse(t)
		ok(p["ok"] and absf(float(p["d"]) - float(want[t])) < 1e-9, "9 '%s' -> %s m (bar %s)%s" % [t, str(p.get("d", "?")), str(want[t]), p.get("note", "")])
	ok("cm" in String(MeshWords.parse("extrude the top 3").get("note", "")), "9 a bare number says it was taken as cm")
	ok(MeshWords.parse("subdivide it three times")["levels"] == 3 and is_equal_approx(MeshWords.parse("scale it down 10%")["f"], 0.9) and is_equal_approx(MeshWords.parse("make it twice as big")["f"], 2.0),
		"9 'three times' -> 3 levels, 'down 10%' -> x0.9, 'twice as big' -> x2")
	r = say("extrude the bottom two cm")
	ok(absf(ylo() + 0.32) < 1e-4 and r["n"] == 1, "9 extrude the bottom two cm: lowest y %.5f (bar -0.32 within 0.1 mm), %d step" % [ylo(), r["n"]])
	undo_back(v0, f0, "extrude the bottom")

	# 11 UNKNOWN / NOT BUILT
	ok(MeshWords.claims("extrdue the top 5 cm", true), "11 a typo of an op word is the mesh words' in the model preview")
	r = say("extrdue the top 5 cm")
	ok(r["n"] == 0 and ui.mesh.verts == v0 and "\"extrude the top 5 cm\"" in r["status"] and "Nothing was changed" in r["status"], "11 'extrdue the top 5 cm': nothing changed, the reply lists \"extrude the top 5 cm\"")
	r = say("bevel the edges 1 cm")
	ok(r["n"] == 0 and ui.mesh.verts == v0 and "bevel isn't built yet" in r["status"], "11 'bevel the edges 1 cm': nothing changed, says bevel isn't built yet")

	# 12 NO STEALING
	for t in ["add a tail with 8 bones", "tired and angry", "raise the right arm 90", "raise the right arm 90 and look angry", "curl the tail 40", "add 2 ears", "remove the tail"]:
		ok(not MeshWords.claims(t, true) and not MeshWords.claims(t, false), "12 '%s' is not the mesh words' (open or not)" % t)
	for t in ["extrude the top 5 cm", "make it 2 cm thicker", "subdivide it twice", "add a cylinder 30 cm tall", "triangulate", "how big is it", "measure it", "delete the selected faces", "scale it up 20%"]:
		ok(MeshWords.claims(t, true) and not RigWords.is_rig(t) and FaceWords.route(t)["face"] == "" and not PoseWords.parse(t)["ok"], "12 '%s' is the mesh words' and no one else's" % t)
	for t in ["delete all keys", "add a marker", "scale", "how big", "new scene", "remove the prop"]:
		ok(not MeshWords.claims(t, false), "12 off the model page '%s' stays the S box's (not the mesh words')" % t)
	for t in ["extrude the top 5 cm", "subdivide it twice", "add a cylinder 30 cm tall", "triangulate", "delete the selected faces"]:
		ok(MeshWords.claims(t, false), "12 off the model page '%s' is still surely modeling (opens the preview)" % t)
	var rig0: int = m.S.rigx.size()
	r = say("add a tail with 8 bones")
	ok(m.S.rigx.size() == rig0 + 1 and r["n"] == 0 and ui.mesh.verts == v0, "12 with the cube open, 'add a tail with 8 bones' adds a tail (%d -> %d chains), the mesh untouched" % [rig0, m.S.rigx.size()])
	r = say("tired and angry")
	ok(r.get("ok", false) and not (r.get("face", {}) as Dictionary).is_empty() and r["n"] == 0 and ui.mesh.verts == v0, "12 'tired and angry' keys the face, the mesh untouched")
	var a0: float = m.B.ang["upperarm_r"].y
	r = say("raise the right arm 90")
	ok(r.get("ok", false) and absf(m.B.ang["upperarm_r"].y - a0) > 1.0 and r["n"] == 0 and ui.mesh.verts == v0, "12 'raise the right arm 90' poses the arm (side %.0f -> %.0f), the mesh untouched" % [a0, m.B.ang["upperarm_r"].y])
	var cs: CommandSearch = m.ui_cmd
	for q in [["extrude the top 5 cm", "Model: "], ["add a tail with 8 bones", "Rig: "], ["tired and angry", "Face: "], ["raise the right arm 90", "Pose: "]]:
		cs.open()
		cs.box.text = q[0]
		cs._filter()
		var nm := String(cs.shown[0]["name"]) if not cs.shown.is_empty() else ""
		ok(nm == q[1] + q[0], "12 the words box's first row for '%s' is '%s' (bar '%s...')" % [q[0], nm, q[1]])
		cs.close()
	for q in ["extrude", "subdivide"]:   # one word is a search for the tool's own row (meshsearch), not a words row
		cs.open()
		cs.box.text = q
		cs._filter()
		ok(not cs.shown.is_empty() and not cs.shown[0].get("words", false), "12 the S box's first row for the lone word '%s' is a tool row ('%s'), not a words row" % [q, cs.shown[0]["name"] if not cs.shown.is_empty() else ""])
		cs.close()
	cs.open()
	cs.box.text = "extrude the top 5 cm"
	cs._filter()
	var n0 := ui.undo.steps.size()
	cs._run(0)
	await idle(2)
	ok(ui.undo.steps.size() == n0 + 1 and absf(yhi() - 0.35) < 1e-4, "12 Enter on the Model row extrudes the top: top y %.5f, %d step" % [yhi(), ui.undo.steps.size() - n0])

	print("meshwords_test: %s (%d failing)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)
