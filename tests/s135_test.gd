extends SceneTree
## godot --path . -s tests/s135_test.gd   (Friday plan 135 + 136: scripts/scene_script.gd + scene_script_ui.gd; needs a window)
## Real presses: Scene lines on the CHECK row, a typed line, Do it. Bars are measured from the built cards (times() starts) and the
## built shot keys projected through the pinhole camera.
var fails := 0
var m: Node
const FRM := Rect2i(0, 0, 1280, 720)
const SHOT := "C:/Temp/claude/s135/"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func state() -> String:
	var H: Scene = m._hero_scene()
	var s := JSON.stringify(H.to_dict(m.B, false)) + "|" + JSON.stringify(H.shots)
	for a in m.actors_rt:
		s += "|" + JSON.stringify((a["S"] as Scene).cards)
	return s


func ribbon_button(text: String) -> Button:
	for c in m.ui_ribbon["CHECK"].get_children():
		if c is Button and (c as Button).text == text:
			return c
	return null


func line(txt: String) -> void:
	m.ssl_ui.line.text = txt
	m.ssl_ui.panel.find_child("scl_go", true, false).pressed.emit()
	await idle()


func scene_of(k: int) -> Scene:
	return m.actors_rt[k]["S"]


## the start (s) of a character's first moving card (card 1: card 0 is the lead card that waits)
func start_of(k: int) -> float:
	return float(scene_of(k).times()[1][0])


func people(t: float) -> Array:
	return AutoCam.fighters(m._hero_scene(), AutoCam.bodies_for(m._hero_scene()), t)


func proj(key: Dictionary, p: Vector3) -> Vector2:
	return ShotCam.project(key["pos"], key["aim"], float(key["f"]), FRM, p)


func inside(key: Dictionary, pts: Array) -> bool:
	for p in pts:
		var q := proj(key, p as Vector3)
		var cam := ShotCam.xf(key["pos"], key["aim"]).affine_inverse() * (p as Vector3)
		if cam.z > -0.05 or q.x < 0 or q.x > 1280 or q.y < 0 or q.y > 720:
			return false
	return true


func middle_third(q: Vector2) -> bool:
	return q.x >= 1280.0 / 3.0 and q.x <= 2560.0 / 3.0 and q.y >= 240.0 and q.y <= 480.0


func shot_png(n: String) -> void:
	DirAccess.make_dir_recursive_absolute(SHOT)
	m.get_viewport().get_texture().get_image().save_png(SHOT + n + ".png")


func _flat_d(key: Dictionary, c: Vector3) -> float:
	var p: Vector3 = key["pos"]
	return Vector2(p.x - c.x, p.z - c.z).length()


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	await idle()
	m._actor_add()
	await idle()
	ok(m.actors_rt.size() == 2, "setup: two characters")
	var fps: int = m._hero_scene().fps
	var fr := 1.0 / float(fps)
	var btn := ribbon_button("Scene lines")
	ok(btn != null, "(1) a Scene lines button on the CHECK row")
	if btn != null:
		btn.pressed.emit()
	await idle()
	var pn: PanelContainer = m.ssl_ui.panel
	var vp: Rect2 = m.get_viewport().get_visible_rect()
	ok(pn != null and pn.visible and vp.encloses(pn.get_global_rect()) and pn.find_child("scl_line", true, false) != null,
		"(1) the box is open inside the window %s" % [str(pn.get_global_rect()) if pn != null else "none"])
	# (2) then
	var s0 := state()
	var u0: int = m.undo.size()
	await line("A punches, then B falls")
	var aend := scene_of(0).length()
	var bst := start_of(1)
	ok(m.undo.size() == u0 + 1, "(2) one undo step for the line (%d -> %d)" % [u0, m.undo.size()])
	ok(aend > 0.5 and absf(bst - aend) <= fr, "(2) A's punch ends at %.3f s, B's first card starts at %.3f s (within 1 frame = %.3f)" % [aend, bst, fr])
	ok(absf(start_of(0)) <= fr and String(scene_of(1).cards[0]["name"]) == "waits", "(2) A starts at %.3f s; B's lead card waits" % start_of(0))
	m._undo()
	await idle()
	ok(state() == s0, "(2) Undo takes the whole line back (both characters)")
	# (3) while
	u0 = m.undo.size()
	await line("while A waves, B jumps")
	var sa := start_of(0)
	var sb := start_of(1)
	ok(m.undo.size() == u0 + 1 and roundi(sa * fps) == roundi(sb * fps), "(3) both start on frame %d and %d; one undo step" % [roundi(sa * fps), roundi(sb * fps)])
	ok(scene_of(0).cards.size() > 2 and scene_of(1).cards.size() > 2, "(3) both characters have cards (%d, %d)" % [scene_of(0).cards.size(), scene_of(1).cards.size()])
	m._undo()
	await idle()
	ok(state() == s0, "(3) Undo exact")
	# (4) after N seconds
	u0 = m.undo.size()
	await line("after 2 seconds, B sits")
	var sb2 := start_of(1)
	ok(m.undo.size() == u0 + 1 and absf(sb2 - 2.0) <= fr, "(4) B starts at %.3f s (2.00 within 1 frame)" % sb2)
	m._undo()
	await idle()
	ok(state() == s0, "(4) Undo exact")
	# keep a built scene for the camera
	await line("A punches, then B falls")
	var sc_built := state()
	# (5) close up on A
	u0 = m.undo.size()
	var sh_n: int = m._shot_shots().size()
	await line("close up on A")
	var shots: Array = m._shot_shots()
	ok(m.undo.size() == u0 + 1 and shots.size() >= 1, "(5) one undo step; shots %d -> %d" % [sh_n, shots.size()])
	var key: Dictionary = shots[0]["keys"][0]
	var hd: Vector3 = (people(float(shots[0]["t"]))[0]["head"] as Vector3) - Vector3(0, 0.13, 0)
	var dist := (key["pos"] as Vector3).distance_to(hd)
	var q := proj(key, hd)
	ok(dist < 1.2, "(5) close up: camera is %.2f m from A's head (< 1.2)" % dist)
	ok(middle_third(q), "(5) A's head lands at %s px, inside the middle third (427..853 x 240..480)" % str(q.round()))
	await idle(2)
	shot_png("closeup")
	m._undo()
	await idle()
	ok(state() == sc_built, "(5) Undo exact")
	# (6) wide
	u0 = m.undo.size()
	await line("wide shot")
	shots = m._shot_shots()
	key = shots[0]["keys"][0]
	var allin := true
	for t in [0.0, 0.5, 1.0, scene_of(0).length() * 0.5, scene_of(1).length()]:
		var pts := []
		for p in people(float(t)):
			pts.append_array(p["all"])
		if not inside(key, pts):
			allin = false
	ok(m.undo.size() == u0 + 1 and allin, "(6) wide: both characters inside the frame at 5 times; one undo step")
	await idle(2)
	shot_png("wide")
	m._undo()
	await idle()
	# (7) follow B
	await line("follow B")
	shots = m._shot_shots()
	var n_ok := 0
	for t in [0.0, 0.7, 1.4, scene_of(1).length() * 0.9]:
		var kk := ShotCam.sample(shots[0]["keys"], float(t))
		var c := AutoCam._bbox_centre(people(float(t))[1]["all"])
		if middle_third(proj(kk, c)):
			n_ok += 1
	ok(n_ok == 4, "(7) follow B: B's body is in the middle third at %d of 4 times; %d keys" % [n_ok, shots[0]["keys"].size()])
	m._undo()
	await idle()
	# (8) orbit slowly
	await line("orbit slowly")
	shots = m._shot_shots()
	var ks: Array = shots[0]["keys"]
	var c0 := AutoCam._bbox_centre((people(0.0)[0]["all"] as Array) + (people(0.0)[1]["all"] as Array))
	var d0 := _flat_d(ks[0], c0)
	var d1 := _flat_d(ks[ks.size() - 1], c0)
	var moved := (ks[0]["pos"] as Vector3).distance_to(ks[ks.size() - 1]["pos"] as Vector3)
	var kin := true
	for t in [0.0, 1.0, 2.0]:
		var pts2 := []
		for p in people(float(t)):
			pts2.append_array(p["all"])
		if not inside(ShotCam.sample(ks, float(t)), pts2):
			kin = false
	ok(absf(d0 - d1) < 0.1 and moved > 0.3 and kin, "(8) orbit: radius %.2f -> %.2f m, camera moved %.2f m, both in frame at 3 times" % [d0, d1, moved])
	m._undo()
	await idle()
	ok(state() == sc_built, "(8) Undo exact")
	# (9) unknown words
	u0 = m.undo.size()
	var s1 := state()
	for bad in ["make a cake", "A flurbs, then B falls", "C punches", "zoom out hugely"]:
		await line(bad)
		ok(m.undo.size() == u0 and state() == s1 and m.ui_status.text.length() > 10, "(9) '%s': nothing changed, no undo step; says: %s" % [bad, m.ui_status.text])
	await line("A punches, then B falls")
	await line("wide shot")
	shot_png("panel")
	print("s135: %d fail" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
