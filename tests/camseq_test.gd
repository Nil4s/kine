## godot --path . -s tests/camseq_test.gd     (ROADMAP 75: multi-shot camera sequencer; needs a window: it renders and drags)
## THE SHOTS (scripts/shot_camera.gd SHOTS, main.gd _shot_*, timeline.gd SHOTS lane). A 3-card scene at 30 fps with three
## shots cut at 0 / 1.2 / 2.5 s, each with its own camera. Nothing is written outside user:// (never scenes/, poses/, data/).
##   1 the shot on at 1.19 s is shot 1 and at 1.21 s is shot 2 (1.2 s = frame 36: frames 35 and 36 are shots 1 and 2; 2.5 s = shot 3)
##   2 look-through: the viewport camera sits on each shot's camera within 1 mm at 1.19 s (shot 1) and 1.21 s (shot 2)
##   3 playblast through the shots: exported frame 35 = shot 1's look-through render and frame 36 = shot 2's, 0 px differ
##   4 an old one-camera file loads and saves byte-identical; it reads as one shot named "Shot 1" at 0 s
##   5 each edit is one undo step and undo puts it back exactly: add a shot, drag a cut (3 moves = 1 step), rename, delete
##   6 mirror: every shot's camera x negated (pos and aim), lens, cut times and names kept; twice = the original
##   7 the SHOTS lane: its segments and cuts drawn; a press-drag-release on the cut at 1.2 s moves it to 1.3 s (whole frames)
##   8 the commands are in the registry: Shots: add / delete / rename
## Screenshot of the lane: env ZZ_CAMSEQ_SHOT (a png path).
extends SceneTree

var fails := 0
var m: Node
var run_id := OS.get_process_id()


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func grab() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_viewport().get_texture().get_image()


func ndiff(a: Image, b: Image) -> int:
	if a.get_size() != b.get_size():
		return -1
	var da := a.get_data()
	var db := b.get_data()
	if da == db:
		return 0
	var n := 0
	for i in range(0, da.size(), 3 if a.get_format() == Image.FORMAT_RGB8 else 4):
		if da[i] != db[i] or da[i + 1] != db[i + 1] or da[i + 2] != db[i + 2]:
			n += 1
	return n


func pose(thigh: float, arm: float) -> Dictionary:
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	R.set_ang("thigh_l", Vector3(thigh, 0, 0))
	R.set_ang("upperarm_r", Vector3(0, 0, arm))
	R.fk()
	return R.to_dict()


func key(t: float, p: Vector3, a: Vector3, f: float) -> Dictionary:
	return {"t": t, "pos": p, "aim": a, "f": f}


func look(t: float) -> void:
	m.playhead = t
	m._ps().apply(m.B, t)
	m._refresh()
	m._shot_apply()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var S := Scene.new()
	S.name = "zz_camseq"
	S.fps = 30
	var poses := [pose(0, 0), pose(70, 80), pose(-25, -40)]
	for i in 3:
		S.add("c%d" % i, poses[i])
		S.cards[i]["move"] = 0.8
		S.cards[i]["hold"] = 0.6 if i < 2 else 0.0
	m.S = S
	m._rebuild_cards()
	m.sel_card = 0
	m.playhead = 0.0
	m._refresh()
	await idle(3)
	var L := S.length()
	var base := "user://zz_camseq_%d" % run_id

	# the three shots, each with its own camera (one key at its cut: a static camera)
	var PA := Vector3(2.8, 1.3, -1.2)
	var PB := Vector3(-2.0, 1.5, 1.8)
	var PC := Vector3(0.5, 1.2, -3.0)
	var AA := Vector3(0, 1.0, 0)
	var AB := Vector3(0.4, 1.1, 0.1)
	var AC := Vector3(0, 1.0, 0.2)
	S.shots = [
		{"t": 0.0, "name": "Wide", "keys": [key(0.0, PA, AA, 50.0)]},
		{"t": 1.2, "name": "Close", "keys": [key(1.2, PB, AB, 35.0)]},
		{"t": 2.5, "name": "Tele", "keys": [key(2.5, PC, AC, 85.0)]},
	]
	ok(L > 2.5, "  the scene is %.2f s long: the third cut at 2.5 s is inside it" % L)

	# 1 which shot is on, frame exact
	var on := func(t: float) -> int:
		m.playhead = t
		return m.shot_now_index() + 1
	var s119: int = on.call(1.19)
	var s121: int = on.call(1.21)
	ok(s119 == 1 and s121 == 2, "1 the active shot at 1.19 s is %d (want 1) and at 1.21 s is %d (want 2)" % [s119, s121])
	ok(on.call(35.0 / 30.0) == 1 and on.call(36.0 / 30.0) == 2 and on.call(37.0 / 30.0) == 2, "  frame exact: frame 35 is shot 1, frame 36 (1.2 s) and 37 are shot 2")
	ok(on.call(2.49) == 2 and on.call(2.5) == 3 and on.call(0.0) == 1, "  2.49 s is shot 2, 2.5 s shot 3, 0 s shot 1")

	# 2 look-through: the view camera sits on the active shot's camera within 1 mm
	m.ui_root.visible = true
	m.clean = false
	m._sides_apply()
	m.playhead = 0.0
	m._shot_toggle()
	look(1.19)
	var o1: Vector3 = m.cam.get_camera_transform().origin
	look(1.21)
	var o2: Vector3 = m.cam.get_camera_transform().origin
	ok(o1.distance_to(PA) < 0.001 and o2.distance_to(PB) < 0.001, "2 look-through: the camera at 1.19 s is shot 1 within 1 mm (%.6f m off), at 1.21 s shot 2 (%.6f m off)" % [o1.distance_to(PA), o2.distance_to(PB)])
	ok(m.ui_shot != null and m.ui_shot.visible, "  the 16:9 frame is drawn while looking through (panels shown)")
	m.clean = true
	m._sides_apply()
	m.ui_root.visible = false
	var crop: Rect2i = m.shot_rect()
	look(35.0 / 30.0)
	var ref1 := (await grab()).get_region(crop)
	look(36.0 / 30.0)
	var ref2 := (await grab()).get_region(crop)

	# 3 the playblast through the shots: the frames before and after the cut are those cameras' renders
	var r1: Dictionary = await m._export_playblast(base + "_cut", "", false)
	var d1: String = r1.get("dir", "")
	var n1: int = r1.get("frames", 0)
	var f35 := Image.load_from_file("%s/frame_0035.png" % d1)
	var f36 := Image.load_from_file("%s/frame_0036.png" % d1)
	var w35 := ndiff(f35, ref1)
	var w36 := ndiff(f36, ref2)
	ok(n1 == roundi(L * S.fps) + 1 and f35.get_size() == crop.size, "3 playblast: %d frames, the frame %s" % [n1, crop.size])
	ok(w35 == 0 and w36 == 0, "  frame 35 = shot 1's render (%d px differ), frame 36 = shot 2's render (%d px differ) (bar 0)" % [w35, w36])
	ok(ndiff(f35, f36) > 1000, "  the cut changes the picture: %d px differ between frames 35 and 36" % ndiff(f35, f36))
	m.ui_root.visible = true
	m.clean = false
	m._sides_apply()
	m._shot_toggle()

	# 4 an old one-camera file: one shot, saved as the old "camera" array, byte-identical
	var old_scene := Scene.new()
	old_scene.fps = 30
	old_scene.add("c0", poses[0])
	old_scene.shots = [{"t": 0.0, "name": "Shot 1", "keys": [key(0.0, PA, AA, 50.0), key(1.5, PB, AB, 35.0)]}]
	var old_file: Dictionary = old_scene.to_dict(m.B)
	var old_text := JSON.stringify(old_file)
	var loaded := Scene.new()
	loaded.from_dict(JSON.parse_string(old_text))
	var resaved := loaded.to_dict(m.B)
	ok(old_file.has("camera") and not old_file.has("shots"), "4 a one-shot scene writes the old \"camera\" array, no \"shots\" key")
	ok(loaded.shots.size() == 1 and float(loaded.shots[0]["t"]) == 0.0 and String(loaded.shots[0]["name"]) == "Shot 1" and loaded.shots[0]["keys"].size() == 2, "  an old file loads as one shot: cut 0 s, named \"Shot 1\", 2 keys")
	ok(JSON.stringify(resaved) == old_text, "  saved again byte-identical (%d chars)" % old_text.length())

	# 5 undo: each edit one step, back exactly
	var before := var_to_str(m.S.shots)
	var scene0 := JSON.stringify(m.S.to_dict(m.B))   # the whole scene as saved, byte for byte
	var u0: int = m.undo.size()
	m.playhead = 1.8
	m._shot_add()   # the new shot's camera is the view as it is now (free view, the camera moved by nothing)
	ok(m.S.shots.size() == 4 and m.undo.size() == u0 + 1, "5 add a shot at 1.8 s: %d shots, %d undo step" % [m.S.shots.size(), m.undo.size() - u0])
	ok(absf(float(m.S.shots[2]["t"]) - 1.8) < 1e-9 and String(m.S.shots[2]["name"]) == "Shot 4", "  the new shot is cut at 1.8 s and named \"%s\"" % String(m.S.shots[2]["name"]))
	m._undo()
	ok(var_to_str(m.S.shots) == before and JSON.stringify(m.S.to_dict(m.B)) == scene0, "  one Ctrl+Z puts the three shots back: the scene is byte-identical to before the add")
	u0 = m.undo.size()
	m._shot_cut_drag(1, 1.25, false)
	m._shot_cut_drag(1, 1.3, false)
	m._shot_cut_drag(1, 1.3, true)
	ok(absf(float(m.S.shots[1]["t"]) - 1.3) < 1e-9 and m.undo.size() == u0 + 1, "  a cut dragged in 3 moves: at %.2f s, %d undo step" % [float(m.S.shots[1]["t"]), m.undo.size() - u0])
	m._undo()
	ok(var_to_str(m.S.shots) == before and JSON.stringify(m.S.to_dict(m.B)) == scene0, "  one Ctrl+Z puts the cut back at 1.2 s: the scene is byte-identical")
	u0 = m.undo.size()
	m._shot_rename_to(0, "Establishing")
	ok(String(m.S.shots[0]["name"]) == "Establishing" and m.undo.size() == u0 + 1, "  rename: \"%s\", %d undo step" % [m.S.shots[0]["name"], m.undo.size() - u0])
	m._undo()
	ok(String(m.S.shots[0]["name"]) == "Wide" and JSON.stringify(m.S.to_dict(m.B)) == scene0, "  one Ctrl+Z gives the name back: the scene is byte-identical")
	u0 = m.undo.size()
	m.playhead = 1.5
	m._shot_delete()
	ok(m.S.shots.size() == 2 and String(m.S.shots[1]["name"]) == "Tele" and m.undo.size() == u0 + 1, "  delete the shot at 1.5 s (Close): %d shots left, %d undo step" % [m.S.shots.size(), m.undo.size() - u0])
	m._undo()
	ok(var_to_str(m.S.shots) == before and JSON.stringify(m.S.to_dict(m.B)) == scene0, "  one Ctrl+Z brings it back: the scene is byte-identical")

	# 6 mirror: every shot's camera x negated, the rest kept
	var M := Body.new()
	M.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var d: Dictionary = JSON.parse_string(JSON.stringify(S.to_dict(m.B)))
	var mi: Dictionary = Scene.mirror_file(d, M)
	var worst := 0.0
	var same := true
	for i in 3:
		var a: Dictionary = d["shots"][i] if d.has("shots") else {}
		var b: Dictionary = mi["shots"][i] if mi.has("shots") else {}
		same = same and a.get("name") == b.get("name") and absf(float(a["t"]) - float(b["t"])) < 1e-9
		var ka: Dictionary = a["camera"][0]
		var kb: Dictionary = b["camera"][0]
		worst = maxf(worst, absf(float(kb["pos"][0]) + float(ka["pos"][0])) + absf(float(kb["aim"][0]) + float(ka["aim"][0])))
		worst = maxf(worst, absf(float(kb["pos"][1]) - float(ka["pos"][1])) + absf(float(kb["f"]) - float(ka["f"])))
	var back: Dictionary = Scene.mirror_file(mi, M)
	ok(d.has("shots") and same and worst < 1e-9 and JSON.stringify(back["shots"]) == JSON.stringify(d["shots"]), "6 mirror: every shot's pos and aim x negated, y, lens, cut times and names kept (error %.9f); twice = the original" % worst)

	# 7 the lane, drawn and dragged
	var tl: Timeline = m.ui_timeline
	m.ui_root.visible = true
	m._sides_apply()
	await idle(4)
	ok(tl.shots_px() > 0.0 and tl.cam_times().size() == 3, "7 the SHOTS lane is on: %.0f px, one camera key per shot on the strip: %d (want 3)" % [tl.shots_px(), tl.cam_times().size()])
	var lane_y: float = tl._shots_y() + Timeline.SHOTS_H * 0.5
	var px := tl.x_of(1.2)
	var u1: int = m.undo.size()   # before the press: the first move takes the step
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(px, lane_y)
	tl._gui_input(press)
	ok(tl.shot_cut_at(Vector2(px, lane_y)) == 1, "  a press on the cut at 1.2 s takes that cut (shot 2)")
	var mv := InputEventMouseMotion.new()
	mv.position = Vector2(tl.x_of(1.3), lane_y)
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	tl._gui_input(mv)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	rel.position = mv.position
	tl._gui_input(rel)
	ok(absf(float(m.S.shots[1]["t"]) - 1.3) < 1e-6 and m.undo.size() == u1 + 1, "  dragged to 1.3 s on the lane: the cut is at %.4f s (whole frame 39), %d undo step" % [float(m.S.shots[1]["t"]), m.undo.size() - u1])
	m._undo()
	ok(absf(float(m.S.shots[1]["t"]) - 1.2) < 1e-9, "  one Ctrl+Z puts it back at 1.2 s")
	await idle(3)
	var shot := OS.get_environment("ZZ_CAMSEQ_SHOT")
	if shot != "":
		var img := await grab()
		var tr: Rect2 = tl.get_global_rect()
		img.get_region(Rect2i(int(tr.position.x), int(tr.position.y), int(tr.size.x), int(tr.size.y))).save_png(shot)
		print("     screenshot: " + shot)

	# 8 the commands are in the registry
	var names := []
	for c in m._commands():
		names.append(String(c["name"]))
	ok("Shots: add a shot from the current view at the playhead" in names and "Shots: delete the shot at the playhead" in names and "Shots: rename the shot at the playhead" in names, "8 the three Shots commands are in the command registry")

	for b in ["_cut"]:
		_rm(ProjectSettings.globalize_path(base + b))
	print("CAMSEQ TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)


func _rm(p: String) -> void:
	if not DirAccess.dir_exists_absolute(p):
		return
	for d in DirAccess.get_directories_at(p):
		_rm(p + "/" + d)
	for f in DirAccess.get_files_at(p):
		DirAccess.remove_absolute(p + "/" + f)
	DirAccess.remove_absolute(p)
