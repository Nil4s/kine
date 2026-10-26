extends SceneTree
## godot --path . --position 4000,4000 -s tests/starters_test.gd     (BUILD B1: starter buildings in the Template card; scripts/build/build_starters.gd,
## scripts/build_choose.gd). Bars written before measuring. Logic bars run on the three sentences through BuildWords (no window needed);
## UI bars click the real chooser (main.tscn at 1280 x 720).
##   S1 each starter's sentence parses with no ignored words and builds the exact summary: cottage "6 x 4 m, 1 floor, 1 door, 2 windows,
##      gable roof" (1 room), flat "8 x 6 m, 2 floors, 1 door, 2 windows, flat roof" (2 rooms), shop "8 x 5 m, 1 floor, 1 door, 2 windows,
##      flat roof" (1 room)
##   S2 each starter has exactly one doorway, "front door", 2.10 m high (the words default)
##   S3 a 1.80 m body under each front door: fits, gap 30.0 cm (the words say 5 cm is the margin)
##   S4 the doorway is open: at chest height (0.9 m), the outside point (1.8 m out), the door's middle and the inside point (1.6 m in) are
##      inside no collision box (a 1 cm skin), for all three starters
##   S5 a walk through "front door" is accepted for a 1.80 m body (walk_scene ok, more than 6 cards)
##   S6 SAVE: a starter saved as a house reloads to the same record (Building.to_file of both)
##   U1 the Template card is live (why_not "" ) and Vehicle is still "Coming soon"; a real click on the Template card's Easy button opens
##      the list of three starters (PopupMenu, three items named Cottage, Two-floor flat, Shop front); the chooser stays open
##   U2 picking "Two-floor flat" (Easy): the chooser closes, Easy on, page BUILD, the building is the starter's record (to_file equal),
##      2 rooms, one undo step (Undo restores the record from before)
##   U3 Use in a scene: BuildStage.use puts "building:Two-floor flat" in the set (props +1, the prop index found)
##   U4 Template Expert, then "Shop front": Easy off, page BUILD, the building is the shop front (1 room, 2 windows)
## Screenshots: C:/Temp/claude/starters/{template_list,flat_build,shop_build}.png. Writes only user://starters_test (Houses.dir).
const SHOT := "C:/Temp/claude/starters"
const SAVE_DIR := "user://starters_test"
const BuildStarters := preload("res://scripts/build/build_starters.gd")

var fails := 0
var m: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click(c: Control) -> void:
	var p: Vector2 = c.get_global_rect().get_center()
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = p
		e.global_position = p
		if down:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e, true)
		await process_frame
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func body(v: float) -> Body:
	var B := Body.new()
	B.body = {"stature": v}
	return B


## true when a point (metres, world) is inside a collision box by more than the 1 cm skin
func inside_any(boxes: Array, p: Vector3) -> bool:
	for bx in boxes:
		var local: Vector3 = (bx["xf"] as Transform3D).affine_inverse() * p
		var h: Vector3 = bx["half"]
		if absf(local.x) < h.x - 0.01 and absf(local.y) < h.y - 0.01 and absf(local.z) < h.z - 0.01:
			return true
	return false


func _init() -> void:
	# ---- logic bars
	var want := {"cottage": ["6 x 4 m, 1 floor, 1 door, 2 windows, gable roof", 1],
		"flat": ["8 x 6 m, 2 floors, 1 door, 2 windows, flat roof", 2],
		"shop": ["8 x 5 m, 1 floor, 1 door, 2 windows, flat roof", 1]}
	var s1 := true
	var s2 := true
	var s3 := true
	var s4 := true
	var s5 := true
	var s6 := true
	for id in want:
		var s := BuildStarters.by_id(id)
		var P := BuildWords.parse(String(s["text"]))
		var sm := BuildWords.summary(P["plan"]) if bool(P.get("ok", false)) else "(no plan)"
		var b := BuildStarters.build(id)
		var rooms := (b["rooms"] as Array).size() if not b.is_empty() else -1
		var got_ok: bool = bool(P.get("ok", false)) and (P.get("ignored", []) as Array).is_empty() and sm == String(want[id][0]) and rooms == int(want[id][1])
		print("     %s: \"%s\" rooms %d" % [id, sm, rooms])
		s1 = s1 and got_ok
		var a := Building.anchors(b)
		s2 = s2 and a.size() == 1 and String(a[0]["name"]) == "front door" and absf(float(a[0]["clear"]) - 2.10) < 1e-4
		var c := BuildStage.clearance(b, "front door", 1.80)
		s3 = s3 and bool(c["ok"]) and absf(float(c["gap_cm"]) - 30.0) < 0.01
		var boxes: Array = Building.collision_boxes(b)
		boxes.append_array(BuildPieces.collision_all(b)["boxes"])
		var pts := BuildStage.walk_points(b, "front door")
		var open := true
		for p in pts:
			open = open and not inside_any(boxes, Vector3(p.x, 0.9, p.z))
		s4 = s4 and open and pts.size() == 3
		var sc := BuildStage.walk_scene(_scene_of(b), body(1.80), "front door")
		s5 = s5 and bool(sc["ok"]) and (sc["scene"]["cards"] as Array).size() > 6
		var dir := SAVE_DIR
		Houses.dir = dir
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var pth := Houses.save(b, String(s["name"]))
		var back := Houses.load_house(String(s["name"]))
		s6 = s6 and pth != "" and JSON.stringify(Building.to_file(back)) == JSON.stringify(Building.to_file(b))
		print("     %s: open %s, walk ok %s, reload same %s" % [id, open, bool(sc["ok"]), JSON.stringify(Building.to_file(back)) == JSON.stringify(Building.to_file(b))])
	ok(s1, "S1 the three sentences parse with no ignored words and build the summaries and room counts: cottage, flat, shop")
	ok(s2, "S2 each starter has one doorway, \"front door\", 2.10 m high")
	ok(s3, "S3 a 1.80 m body fits under each front door: gap 30.0 cm")
	ok(s4, "S4 the doorway is open at chest height: outside, door middle, inside are free of collision boxes (all three)")
	ok(s5, "S5 walk_scene through the front door is accepted for a 1.80 m body (more than 6 cards)")
	ok(s6, "S6 saved as a house, each starter reloads to the same record")

	# ---- UI bars
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	m._new_scene()
	m.S.kind = "building"
	m._page_set("BUILD")
	await idle(4)
	var bc: BuildChoose = m.build_choose
	m.easy.set_on(false)
	bc.show_chooser()
	await idle(4)

	var u1a := bc.why_not("template") == "" and bc.why_not("vehicle") != ""
	var tb: Button = bc.btns["template"]["easy"]
	await click(tb)
	var pm: PopupMenu = bc._starters
	var items := []
	if pm != null:
		for i in pm.item_count:
			items.append(pm.get_item_text(i))
	var u1b := pm != null and pm.visible and pm.item_count == 3 and bc.open
	ok(u1a and u1b, "U1 Template is live (Vehicle still says Coming soon); its Easy button opens the list, the chooser stays open: %s" % str(items))
	await shot("template_list")

	# U2 pick "Two-floor flat" (the list's second item) in Easy
	var before := JSON.stringify(Building.to_file(m.S.building)) if not m.S.building.is_empty() else ""
	pm.id_pressed.emit(1)
	await idle(6)
	var want_rec := JSON.stringify(Building.to_file(BuildStarters.build("flat")))
	var got := JSON.stringify(Building.to_file(m.S.building))
	var u2: bool = not bc.open and m.easy.on and m.cur_page == "BUILD" and got == want_rec and (m.S.building["rooms"] as Array).size() == 2
	ok(u2, "U2 Easy pick \"Two-floor flat\": chooser closed, Easy on, page BUILD, the starter's record, 2 rooms (%s)" % m.cur_page)
	await shot("flat_build")
	m._undo()
	await idle(4)
	var u2u: bool = JSON.stringify(Building.to_file(m.S.building)) == before if before != "" else m.S.building.is_empty() or (m.S.building["rooms"] as Array).is_empty()
	ok(u2u, "U2 one undo step: Undo restores the record from before the pick")

	pm.id_pressed.emit(1)   # the flat again (the undo above took it away)
	await idle(4)

	# U3 Use in a scene
	var props0: int = m.S.props.size()
	var kind := BuildStage.use(m.S)
	ok(kind == "building:Two-floor flat" and m.S.props.size() == props0 + 1 and BuildStage.prop_index(m.S) >= 0,
		"U3 Use in a scene: kind \"%s\", props %d -> %d" % [kind, props0, m.S.props.size()])

	# U4 Template in Expert, the shop front
	bc.show_chooser()
	await idle(4)
	await click(bc.btns["template"]["expert"])
	var pm2: PopupMenu = bc._starters
	pm2.id_pressed.emit(2)
	await idle(6)
	var sb: Dictionary = m.S.building
	var u4: bool = not bc.open and not m.easy.on and m.cur_page == "BUILD" and String(sb.get("name", "")) == "Shop front" and (sb["rooms"] as Array).size() == 1 and (sb["openings"] as Array).size() == 3
	ok(u4, "U4 Expert pick \"Shop front\": Easy off, page BUILD, shop front record (1 room, 1 door + 2 windows = 3 openings)")
	await shot("shop_build")

	print("STARTERS: %s (%d FAIL)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)


## a scene that carries the house (walk_scene reads S.building)
func _scene_of(b: Dictionary) -> Scene:
	var S := Scene.new()
	S.building = b
	return S
