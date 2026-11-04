extends SceneTree
## godot --path . -s tests/c50_test.gd   (C50: #209 reference geometry picked from inside a sketch, #197 unique item labels; needs the CAD DLL and a window)
## Bars, written BEFORE the first run. Fixture: a 40 x 20 mm rectangle on Front extruded 30 mm; a second sketch on Front.
##  1 DEFAULT  the "Pick body edges as reference" box exists and is OFF; with it off, a Line-tool click on a solid corner starts a line and adds no ref.
##             (control: the same click with the box ON adds one, bar 2)
##  2 CORNER   box on, a real click on the solid corner (40,20): one ref P1 kind point, pa within 0.01 mm of (40,20)
##  3 EDGE     a real click on the middle of the solid top edge: ref E1 kind edge, its two ends are (0,20) and (40,20) within 0.01 mm
##  4 REMOVE   a second click on E1 removes it (refs back to 1); undo of that click brings it back
##  5 SNAP     Line tool, box off, click 5 px from P1 screen point, then a free point: the line first end IS P1 (< 1e-6 mm) and a "refpt" rule pins it.
##             CONTROL: with no refs there is no snap target and no pin
##  6 FOLLOW   with the sketch open, the fixture rectangle is changed to 60 wide and the model rebuilt: P1 reads (60,20) within 0.01 and the pinned line end
##             follows to (60,20) within 0.01.  CONTROL: refresh() with no edges leaves P1 at (40,20)
##  7 LABELS   every item label is unique over a sketch of 2 lines + rect + circle + arc + 2 refs; CONTROL: the duplicate checker flags a planted repeat.
##             Hover on a line with the pointer: the status line reads that line label ("L1")
##  8 SHOT     1280x720 screenshots in out/c50, looked at by hand
var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c50"


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


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


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func click_at(p: Vector2) -> void:
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	var img: Image = root.get_texture().get_image() if root.get_texture() != null else null
	if img != null:
		img.save_png("%s/%s.png" % [SHOT, nm])


func sp(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("front"), Vector2(x, y)))


func refs() -> Array:
	return (m.bld.part._sk().get("refs", []) as Array)


func near(a: Array, x: float, y: float) -> bool:
	return Vector2(float(a[0]), float(a[1])).distance_to(Vector2(x, y)) < 0.01


func dups(labels: Array) -> int:
	var seen := {}
	var d := 0
	for l in labels:
		if seen.has(l):
			d += 1
		seen[l] = true
	return d


func _init() -> void:
	var watch := Timer.new()   # watchdog
	watch.wait_time = 400.0
	watch.one_shot = true
	root.add_child(watch)
	watch.timeout.connect(func(): print("FAIL watchdog"); quit(1))
	watch.start()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	if not Part.available():
		print("SKIP: no KineCAD DLL")
		quit(0)
		return
	var ss: StartScreen = m.start_screen
	var pu: PartUI = m.bld.part
	var dirt := "user://c50_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dirt))
	ss.dirs_override = [dirt]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(3)
	var rec: Dictionary = pu._ensure()
	var sk1 := Part.new_feature(rec, "sketch", {"plane": "front", "ents": [{"k": "rect", "a": [0, 0], "b": [40, 20]}], "dims": []})
	rec["features"].append(sk1)
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": sk1["id"], "dist": 30.0, "both": false, "op": "new"}))
	pu._rec_sig = ""
	pu._rebuild(true)
	await idle(3)
	pu.begin_sketch("front")
	await idle(4)
	ok(pu.sk != "", "0 a second sketch on Front is open")
	ok(pu.edge_cache.size() >= 8, "0 the solid edges are known in the sketch (%d)" % pu.edge_cache.size())
	var c50: PartC50 = pu.c50
	ok(c50 != null and c50.chk != null and not c50.chk.button_pressed and not c50.on, "1 the box exists and is off")
	pu.tool = "Line"
	await click_at(sp(40, 20))
	ok(refs().is_empty() and not pu._sk().has("refs"), "1 box off: a click on the corner adds no ref")
	ok(not pu.draft.is_empty(), "1 box off: the click started a line as before")
	pu.draft = {}
	pu.tool = ""
	await click_ctl(c50.chk)
	ok(c50.on, "1 clicking the box turns it on")
	await click_at(sp(40, 20))
	ok(refs().size() == 1 and String(refs()[0]["id"]) == "P1" and String(refs()[0]["kind"]) == "point" and near(refs()[0]["pa"], 40, 20), "2 corner click: P1 at (40,20): %s" % [refs()])
	await click_at(sp(20, 20))
	var e1: Dictionary = refs()[1] if refs().size() > 1 else {}
	var okE := not e1.is_empty() and String(e1["id"]) == "E1" and String(e1["kind"]) == "edge"
	if okE:
		var ea := Vector2(float(e1["pa"][0]), float(e1["pa"][1]))
		var eb := Vector2(float(e1["pb"][0]), float(e1["pb"][1]))
		okE = (ea.distance_to(Vector2(0, 20)) < 0.01 and eb.distance_to(Vector2(40, 20)) < 0.01) or (eb.distance_to(Vector2(0, 20)) < 0.01 and ea.distance_to(Vector2(40, 20)) < 0.01)
	ok(okE, "3 edge click: E1 from (0,20) to (40,20): %s" % [refs()])
	await shot("refs_shown")
	await click_at(sp(20, 20))
	ok(refs().size() == 1, "4 a second click on E1 removes it (%d refs)" % refs().size())
	m._undo()
	await idle(3)
	ok(pu.sk != "" and refs().size() == 2, "4 undo brings it back (%d refs, sk %s)" % [refs().size(), pu.sk])
	await click_ctl(c50.chk)
	ok(not c50.on, "4 box off again")
	pu.tool = "Line"
	await click_at(sp(40, 20) + Vector2(5, 3))
	await click_at(sp(100, 50))
	var ents: Array = pu._sk()["ents"]
	var pinned := 0
	for c in pu._sk().get("cons", []):
		if String(c.get("k", "")) == "refpt":
			pinned += 1
	ok(ents.size() == 1 and Part.v2(ents[0]["a"]).distance_to(Vector2(40, 20)) < 1e-6, "5 line start lands exactly on P1: %s" % [ents])
	ok(pinned == 1, "5 one refpt rule pins it (%d)" % pinned)
	var f1 := Part.feature(pu._rec(), String(sk1["id"]))
	f1["ents"][0]["b"] = [60, 20]
	pu._rec_sig = ""
	pu._rebuild(true)
	await idle(3)
	c50.sync()
	var p1 := Part.v2(refs()[0]["pa"])
	ok(p1.distance_to(Vector2(60, 20)) < 0.01, "6 P1 follows the solid to (60,20): %s" % [p1])
	ok(Part.v2(pu._sk()["ents"][0]["a"]).distance_to(Vector2(60, 20)) < 0.01, "6 the pinned line end followed: %s" % [pu._sk()["ents"][0]["a"]])
	var stale := (pu._sk() as Dictionary).duplicate(true)
	stale["refs"][0]["pa"] = [40, 20]
	PartC50.refresh(stale, [], pu._plane())
	ok(Part.v2(stale["refs"][0]["pa"]).distance_to(Vector2(40, 20)) < 0.01, "6 control: no edges, no refresh (stays at 40,20)")
	ok(PartC50.targets({"ents": [], "refs": []}).is_empty() and PartC50.pin_new_line({"ents": [{"k": "line", "a": [40, 20], "b": [1, 1]}]}, 0) == 0, "5 control: no refs, no snap target and no pin")
	var lab := {"ents": [{"k": "line", "a": [0, 0], "b": [10, 0]}, {"k": "line", "a": [0, 0], "b": [0, 10]}, {"k": "rect", "a": [0, 0], "b": [5, 5]}, {"k": "circle", "c": [0, 0], "r": 3}, {"k": "arc", "a": [0, 0], "m": [1, 1], "b": [2, 0]}], "refs": [{"id": "E1"}, {"id": "P1"}]}
	var labs := PartC50.all_labels(lab)
	ok(labs.size() == 7 and dups(labs) == 0 and labs[0] == "L1" and labs[2] == "R3" and labs[4] == "A5", "7 labels unique: %s" % [labs])
	ok(dups(["L1", "L1"]) == 1, "7 control: the checker flags a repeat")
	pu.tool = ""
	var mid := (sp(60, 20) + sp(100, 50)) * 0.5
	await ev_move(mid + Vector2(150, 150))
	await ev_move(mid)
	await ev_move(mid + Vector2(1, 0))
	ok(String(pu.status).begins_with("L1"), "7 hover on the line: status reads its label (%s)" % pu.status)
	await shot("labels_hover")
	# 9 ANGLE (lead fix round 1): box off, an angle-rule sketch solves to the numbers w4-b04 gives (measured there with the same script, tests/c50ang)
	var ask := {"plane": "front", "ents": [{"k": "line", "a": [0, 0], "b": [100, 0]}, {"k": "line", "a": [10, 10], "b": [80, 60]}, {"k": "line", "a": [0, 0], "b": [30, 40]}], "dims": [], "cons": [{"k": "ang", "a": 0, "b": 1, "deg": 30.0}, {"k": "h", "a": 0}, {"k": "eq", "a": 1, "b": 2}, {"k": "coin", "a": 0, "ap": 0, "b": 1, "bp": 0}]}
	Part.solve(ask)
	var want := [[7.85694429153596, 6.0480522656849, 100.000104674186, 6.04805226568492], [7.85694429153595, 6.04805226568492, 73.9514963074969, 44.2077596647895], [-8.85062383490247, -9.78776613687165, 38.8506238349922, 49.7877661369671]]
	var worst := 0.0
	for i in 3:
		for j in 2:
			worst = maxf(worst, Part.v2(ask["ents"][i]["a" if j == 0 else "b"]).distance_to(Vector2(want[i][2 * j], want[i][2 * j + 1])))
	ok(worst < 1e-6, "9 angle-rule sketch solves to the w4-b04 numbers (worst %s mm)" % worst)
	var wrong := want.duplicate(true)
	wrong[1][3] += 0.01
	ok(Part.v2(ask["ents"][1]["b"]).distance_to(Vector2(wrong[1][2], wrong[1][3])) > 1e-6, "9 control: a planted 0.01 mm error is seen")
	await shot("labels_hover_1280x720")
	root.content_scale_size = Vector2i(1024, 600)
	pu.tool = ""
	await idle(4)
	await click_ctl(c50.chk)
	await click_at(sp(40, 20))
	await shot("refs_1024x600")
	var cr: Rect2 = c50.chk.get_global_rect()
	ok(c50.chk.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(root.content_scale_size)).encloses(cr), "8 1024x600: the box is laid out (%s)" % cr)
	print("c50: %d fail%s" % [fails, "" if fails == 1 else "s"])
	quit(1 if fails > 0 else 0)
