extends SceneTree
## godot --headless --path . -s tests/hinge_test.gd     (C3 HINGE: scripts/build/part.gd hinge + hinge_sweep; needs the CAD DLL, else only bar 7 runs)
## A door: a leaf 800 x 40 x 2000 mm hinged on its z edge at the origin (the hinge's body 0), a stop wall 3200 x 10 x 2000 mm across the
## leaf's path at y = c (mm). The swing is linear, 0 -> 90 deg in 3 s, sampled at 25 fps (frame i = 1.2 i deg). Every number in the record is mm.
## Bars, written before measuring (closed forms, computed in the test from the geometry, never read back from the code):
##   1 REPLAY    the door with its hinge replays with no failed step; volume = leaf 0.064 m3 + stop 0.064 m3 within 1e-5 relative
##   2 STOP      the leaf's far corner (800, 20) reaches the stop face y = 400 at theta_s = asin(c / R) - phi, R = hypot(800, 20),
##               phi = atan2(20, 800): theta_s = 28.56 deg. The first frame at or past it is F = ceil(theta_s / 1.2) = 24
##   3 FRAME     the sweep's first interference frame is within 1 frame of F (at 25 fps), and its time is that frame's time
##   4 CLEAR     a stop at y = 810 (the leaf reaches y = 800 at 90 deg): no interference, first = -1, 0 frames hit
##   5 TIME      100 frames (a 3.96 s swing, the stop at 810): the whole sweep (replay included) runs under 2 s
##   6 ERRORS    a hinge naming body 5 (there are 2): the replay names the hinge, hinge_sweep answers ok false with the reason
##   7 NO DLL    Part.force_off: hinge_sweep answers ok false and says KineCAD (runs with or without the DLL)
##   8 RELEASE   the sweep frees every shape it made: KCad.live_count() is the same after it as before
## MUST NOT TOUCH (C3 collision, bars 9-11), the leaf and a box stop 100 mm apart at rest (stop face at y = 120; the leaf's top face is at y = 20):
##   9 PAIR      the pair (0, 1) on the hinge's list: the first touching frame is F2 +- 1, F2 = ceil(theta_c / 1.2) with
##               theta_c = asin(120 / R) - phi (the far corner (800, 20) reaches y = 120; the same geometry as bar 2): F2 = 6
##   10 GAP0     the distance of the pair at frame 0 is 100 mm +- 0.5 (the closed form: 120 - 20)
##   11 NOPAIR   the same door with no pair chosen: no red frames, no pair reported
## Nothing is written to disk.
const KCad := preload("res://scripts/kcad.gd")
const DOOR_W := 800.0
const DOOR_T := 40.0
const DOOR_H := 2000.0
const FPS := 25.0
var fails := 0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


## the door record: the leaf (body 0), the stop wall (body 1) at y = stop_y, and the hinge (f5) on body `body` with the given track
func door(stop_y: float, track: Array, body := 0, clear: Array = []) -> Dictionary:
	var rec := Part.make("Door")
	rec["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [0, -DOOR_T / 2], "b": [DOOR_W, DOOR_T / 2]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": DOOR_H, "both": false, "op": "new"},
		{"t": "sketch", "id": "f3", "name": "Sketch2", "plane": "front", "ents": [{"k": "rect", "a": [-1600, stop_y], "b": [1600, stop_y + 10]}], "dims": []},
		{"t": "extrude", "id": "f4", "name": "Extrude2", "sketch": "f3", "dist": DOOR_H, "both": false, "op": "new"},
		{"t": "hinge", "id": "f5", "name": "Hinge1", "body": body, "o": [0, 0, 0], "axis": [0, 0, 1], "track": track, "clear": clear},
	]
	return rec


## UI bars (windowed: the Part workspace on a building project, real clicks through root.push_input at 1280 x 720):
##   12 MAKE     Hinge tool, click the lid (Part 1), click one of its straight edges, OK: ONE step; the feature's line is the clicked edge within 1 mm
##   13 PLAY     the slider at 50 % turns the lid by half its range (45 deg +- 1); the view's lid is turned (its box moved)
##   14 PAIR     Add a pair of parts, click the lid, click the block in its path: one step; red frames = hinge_sweep's red; the words say so
##   15 REMOVE   the pair's x: one step, no red frames left, the words say no pair
##   16 WORDS    no key name (Enter, Esc, Ctrl, Shift, Alt, Tab, Backspace, Delete) and no record key (track, clear, axis) in the new texts
const SHOT_UI := "C:/Temp/claude/hingecol"
const DIR_UI := "user://hinge_test"


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


func ev_move(p: Vector2, held := false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_at(p: Vector2) -> void:
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


## a Part tool as a user reaches it: its ribbon button when shown, else through More
func press_tool(m: Node, pu: PartUI, t: String) -> void:
	var b: Button = pu.tool_btns[t]
	if b.is_visible_in_tree() and b.get_viewport().get_visible_rect().encloses(b.get_global_rect()):   # navigation: a ribbon button pushed past the window edge is reached through More
		await click_ctl(b)
		return
	await click_ctl(m.ui_more)
	m.ui_more.get_popup().hide()
	var i: int = m._more_tools.find(b)
	if i >= 0:
		m._more_pick(i)
	await idle(2)


func key_names_in(txt: String) -> Array:
	var bad := []
	for w in ["Enter", "Esc", "Ctrl", "Shift", "Alt", "Tab", "Backspace", "Delete", "track", "clear", "axis"]:
		if txt.contains(w):
			bad.append(w)
	return bad


func ui_bars() -> void:
	if not Part.available():
		print("SKIP 12-16: the CAD kernel is not available")
		return
	var m: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR_UI))
	ss.dirs_override = [DIR_UI]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	# the record: a lid (a box 800 x 40 x 2000 mm, Part 1) and a block (300..500 x 100..120 x 2000 mm, Part 2) in its path
	# Nick 2026-10-28 (free 3D building, #100): the BUILDING card now opens a blank Easy Part itself. Start from the
	# state the card gave before (Part off, no part), so the clicks below drive the same opening they always did
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	m.S.part = Part.make("Lid")
	m.S.part["features"] = [
		{"t": "sketch", "id": "f1", "name": "Sketch1", "plane": "front", "ents": [{"k": "rect", "a": [0, -20], "b": [800, 20]}], "dims": []},
		{"t": "extrude", "id": "f2", "name": "Extrude1", "sketch": "f1", "dist": 2000.0, "both": false, "op": "new"},
		{"t": "sketch", "id": "f3", "name": "Sketch2", "plane": "front", "ents": [{"k": "rect", "a": [300, 100], "b": [500, 120]}], "dims": []},
		{"t": "extrude", "id": "f4", "name": "Extrude2", "sketch": "f3", "dist": 2000.0, "both": false, "op": "new"},
	]
	m.S.part["seq"] = 4
	await click_ctl(pu.part_btn)
	await idle(3)
	bu_sync(m)
	await idle(3)
	pu._view_model()   # the model is framed (what Part does when the model is there)
	await idle(3)
	var rec_before: int = (m.S.part["features"] as Array).size()
	var n0: int = m.undo.size()
	await press_tool(m, pu, "Hinge")
	ok(pu.tool == "Hinge" and pu.dlg.get("t", "") == "hinge", "12 MAKE: the Hinge tool opens its dialog (tool %s)" % pu.tool)
	# click Part 1 (the lid): its face, from the camera, through its middle
	var lid_tris: PackedVector3Array = Part.body_faces(m.S.part, -1)[0]
	var lid_pt: Vector3 = Vector3.ZERO
	for v in lid_tris:
		lid_pt += v / float(lid_tris.size())   # the lid's centre (of its corners): inside it, in front of the camera once framed
	await click_at(m.cam.unproject_position(lid_pt))
	ok(int(pu.hp.get("body", -1)) == 0, "12 MAKE: clicking the lid picks Part 1 (picked %s)" % pu.hp.get("body", -1))
	# click a straight edge of the lid nearest to its corner (0, -20 mm, z 0..2000 mm)
	var best := -1
	var best_d := INF
	for i in pu.edge_cache.size():
		var e: Dictionary = pu.edge_cache[i]
		if int(e["body"]) != 0 or (e["a"] as Vector3).distance_to(e["b"] as Vector3) < 1e-6:
			continue
		var dd := (e["c"] as Vector3).distance_to(Vector3(0.0, -0.02, 1.0))
		if dd < best_d:
			best_d = dd
			best = i
	var pick_e: Dictionary = pu.edge_cache[best] if best >= 0 else {}
	if not pick_e.is_empty():
		await click_at(m.cam.unproject_position(pick_e["c"]))
	ok(pu.hp.has("d") and not pick_e.is_empty(), "12 MAKE: the line is picked by clicking an edge of the lid (%s)" % ("yes" if pu.hp.has("d") else "no"))
	await shot_ui("hinge_make")
	await click_ctl(pu.ok_btn)
	await idle(3)
	var feats: Array = m.S.part["features"]
	var hf: Dictionary = feats[-1] if not feats.is_empty() else {}
	var made := feats.size() == rec_before + 1 and String(hf.get("t", "")) == "hinge"
	var line_ok := false
	if made and not pick_e.is_empty():
		var o := Vector3(float(hf["o"][0]), float(hf["o"][1]), float(hf["o"][2])) * Part.MM
		var ax := Vector3(float(hf["axis"][0]), float(hf["axis"][1]), float(hf["axis"][2])).normalized()
		var ea: Vector3 = pick_e["a"]
		var dv: Vector3 = ea - o
		var off := (dv - ax * dv.dot(ax)).length() / Part.MM
		line_ok = off < 1.0 and absf(absf(ax.dot(((pick_e["b"] as Vector3) - ea).normalized())) - 1.0) < 1e-4
	ok(made and line_ok and m.undo.size() == n0 + 1, "12 MAKE: one hinge step (%d -> %d features, %d undo step), its line is the clicked edge within 1 mm" % [rec_before, feats.size(), m.undo.size() - n0])
	m._undo()
	await idle(2)
	var back: bool = (m.S.part["features"] as Array).size() == rec_before
	m._redo()
	await idle(2)
	ok(back and (m.S.part["features"] as Array).size() == rec_before + 1, "12 MAKE: one undo takes the hinge away, redo gives it back")

	# 13 PLAY: the slider at 50 %
	var rest_box: AABB = pu.part_mesh.mesh.get_aabb() if pu.part_mesh.mesh != null else AABB()
	pu.hinge_slider.value = 50.0
	await idle(3)
	var deg := float(pu.pose.get("deg", -999.0))
	var turned: AABB = pu.part_mesh.mesh.get_aabb() if pu.part_mesh.mesh != null else AABB()
	ok(absf(deg - 45.0) <= 1.0 and not turned.is_equal_approx(rest_box), "13 PLAY: 50 %% turns the lid to %.2f deg (45 within 1); the view moved (%s -> %s)" % [deg, rest_box.size, turned.size])

	# 14 PAIR: the lid and the block
	var n1: int = m.undo.size()
	await click_ctl(pu.hinge_pair_btn)
	await click_at(m.cam.unproject_position(lid_pt))
	await click_at(m.cam.unproject_position(Vector3(0.4, 0.11, 1.0)))
	await idle(3)
	var hid := String(hf.get("id", ""))
	var pairs: Array = Part.clear_pairs(m.S.part, hid)
	var want := Part.hinge_sweep(m.S.part, hid, 25.0)
	var same := bool(want.get("ok", false)) and (pu.hsw.get("red", []) as Array) == (want.get("red", []) as Array)
	ok(pairs == [[0, 1]] and m.undo.size() == n1 + 1, "14 PAIR: one step, the pair Part 1 and Part 2 is on the list (%s)" % str(pairs))
	ok(same and not (want["red"] as Array).is_empty() and pu.hinge_red_l.text == "Touching at " + String(want["red_text"]), "14 PAIR: red frames %s = hinge_sweep's; the words: %s" % [str(want.get("red", [])), pu.hinge_red_l.text])
	await idle(2)
	await shot_ui("hinge_red")

	# 15 REMOVE: the x of the pair
	var n2: int = m.undo.size()
	var x: Button = pu.hinge_pairs_vb.get_child(0).get_child(1) if pu.hinge_pairs_vb.get_child_count() > 0 else null
	var had_x := x != null
	if had_x:
		await click_ctl(x)
	await idle(3)
	var gone: bool = Part.clear_pairs(m.S.part, hid).is_empty() and (pu.hsw.get("red", []) as Array).is_empty()
	ok(had_x and gone and m.undo.size() == n2 + 1, "15 REMOVE: the x takes the pair off in one step; no red frames left")

	# 16 WORDS: every new text
	var texts := [pu.hinge_info.text, pu.hinge_red_l.text, pu.dlg_info.text, pu.status, String(PartUI.TIPS["Hinge"]), "Turning part:  Part 1", "Must not touch: now click the part it must not touch (Part 1 is picked)."]
	var bad := []
	for t in texts:
		bad.append_array(key_names_in(String(t)))
	ok(bad.is_empty(), "16 WORDS: no key name in the new texts (found %s)" % str(bad))

	m.queue_free()
	await idle(3)


func shot_ui(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT_UI)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT_UI, nm])


## the building's Build ribbon refresh after a direct record change (what a file load does)
func bu_sync(m: Node) -> void:
	m.bld.sync()


func _init() -> void:
	var swing := [[0.0, 0.0], [3.0, 90.0]]
	var clear := door(810.0, swing)
	var stop := door(400.0, swing)

	# 7 NO DLL: the Part tools say why, whatever the kernel does
	var was_off := Part.force_off
	Part.force_off = true
	var nd := Part.hinge_sweep(stop, "f5", FPS)
	Part.force_off = was_off
	ok(not bool(nd["ok"]) and "KineCAD" in String(nd["why"]), "7 NO DLL: hinge_sweep ok false, says KineCAD: %s" % nd.get("why", ""))

	if not Part.available():
		print("SKIP 1-6, 8: the CAD kernel is not available (" + KCad.last_error() + ")")
		print("HINGE ", "PASS" if fails == 0 else "FAIL %d" % fails)
		quit(1 if fails > 0 else 0)
		return

	# 1 REPLAY: the timeline with the hinge is the rest pose, no failed step
	var rp := Part.replay(stop)
	var vol_want := DOOR_W * DOOR_T * DOOR_H * 1e-9 + 3200.0 * 10.0 * DOOR_H * 1e-9
	ok((rp["errors"] as Dictionary).is_empty() and absf(float(rp["volume"]) - vol_want) <= 1e-5 * vol_want,
			"1 REPLAY: no failed step, volume %.6f m3 (closed form %.6f)" % [float(rp["volume"]), vol_want])

	# 2 STOP: the analytic contact angle and frame
	var R := sqrt(DOOR_W * DOOR_W + (DOOR_T / 2) * (DOOR_T / 2))
	var phi := atan2(DOOR_T / 2, DOOR_W)
	var theta_s := rad_to_deg(asin(400.0 / R) - phi)
	var F := int(ceil(theta_s / 1.2 - 1e-9))
	ok(absf(theta_s - 28.56) < 0.01 and F == 24, "2 STOP: theta_s %.3f deg, first frame at or past it F = %d" % [theta_s, F])

	# 3 FRAME: the sweep finds the contact frame
	var sw := Part.hinge_sweep(stop, "f5", FPS)
	ok(bool(sw["ok"]) and absi(int(sw["first"]) - F) <= 1, "3 FRAME: first interference frame %d at %.2f s, %.2f deg (F = %d, within 1)" % [int(sw["first"]), float(sw["first_s"]), float(sw["deg_first"]), F])
	ok(absf(float(sw["first_s"]) - float(sw["first"]) / FPS) < 1e-9 and int(sw["frames"]) == 76 and int(sw["hit_frames"]) >= 1,
			"3 FRAME: %d frames sampled, %d overlap, first_s is that frame's time" % [int(sw["frames"]), int(sw["hit_frames"])])

	# 4 CLEAR: a stop the leaf never reaches
	var cl := Part.hinge_sweep(clear, "f5", FPS)
	ok(bool(cl["ok"]) and int(cl["first"]) == -1 and int(cl["hit_frames"]) == 0, "4 CLEAR: stop at 810 mm: first %d, %d frames hit" % [int(cl["first"]), int(cl["hit_frames"])])

	# 5 TIME: 100 frames, no contact
	var live0 := KCad.live_count()
	var long := door(810.0, [[0.0, 0.0], [3.96, 90.0]])
	var tm := Part.hinge_sweep(long, "f5", FPS)
	print("TIME 100 frames: %.3f s (%d frames)" % [float(tm["secs"]), int(tm["frames"])])
	ok(bool(tm["ok"]) and int(tm["frames"]) == 100 and float(tm["secs"]) < 2.0, "5 TIME: %d frames in %.3f s (bar < 2 s)" % [int(tm["frames"]), float(tm["secs"])])

	# 6 ERRORS: a hinge on a body the door does not have
	var bad := door(400.0, swing, 5)
	var be := Part.replay(bad)
	var bs := Part.hinge_sweep(bad, "f5", FPS)
	ok((be["errors"] as Dictionary).has("f5") and not bool(bs["ok"]) and "body 5" in String(bs["why"]),
			"6 ERRORS: replay: %s / sweep: %s" % [be["errors"], bs.get("why", "")])

	# 9-11 MUST NOT TOUCH: a box stop 100 mm off the leaf's rest face; the pair (0, 1) on the list
	var gap := door(120.0, swing, 0, [[0, 1]])
	var gs := Part.hinge_sweep(gap, "f5", FPS)
	var theta_c := rad_to_deg(asin(120.0 / R) - phi)
	var F2 := int(ceil(theta_c / 1.2 - 1e-9))
	var touch: Array = []
	var d0 := -1.0
	if bool(gs["ok"]) and (gs["pairs"] as Array).size() == 1:
		touch = (gs["pairs"][0] as Dictionary)["touch"]
		d0 = float((gs["pairs"][0] as Dictionary)["dist"][0])
	var first_touch := int(touch[0]) if not touch.is_empty() else -1
	ok(first_touch >= 0 and absi(first_touch - F2) <= 1, "9 PAIR: first touching frame %d (hand F2 = %d, theta_c %.3f deg, within 1); red: %s" % [first_touch, F2, theta_c, gs.get("red_text", "")])
	ok(absf(d0 - 100.0) <= 0.5, "10 GAP0: distance at frame 0 = %.3f mm (100 within 0.5)" % d0)
	var np := Part.hinge_sweep(door(120.0, swing), "f5", FPS)
	ok(bool(np["ok"]) and (np["red"] as Array).is_empty() and (np["pairs"] as Array).is_empty() and int(np["hit_frames"]) >= 1,
			"11 NOPAIR: no pair chosen: %d red frames, %d pairs (the stop is still hit: %d frames)" % [(np["red"] as Array).size(), (np["pairs"] as Array).size(), int(np["hit_frames"])])

	# 8 RELEASE: the sweeps freed everything they made
	ok(KCad.live_count() == live0, "8 RELEASE: live shapes %d before, %d after" % [live0, KCad.live_count()])
	KCad.release_all()
	await ui_bars()   # 12-16: the Part workspace's clicks (windowed; the no-DLL run skips them)

	print("HINGE ", "PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
