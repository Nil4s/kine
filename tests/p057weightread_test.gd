extends SceneTree
## P057 WEIGHT READOUT (Friday plan item 57: weight from the material, Wood / Metal / Plastic density x volume): a beginner from the
## BUILDING card makes a plate, then opens Colour in the Easy Part. Three chips show how heavy the whole part would be in each material.
## Real clicks and presses at 1280 x 720. Numbers are measured from the built result (m3 from the kernel's volume), never from the code's variables.
##   BUILDING card -> Easy Part (blank) -> Draw shape (box 12 x 8 cm) -> Pull it up -> Colour (the chips)
## The expected weight uses the design densities written here: wood 600, metal (steel) 7850, plastic 1050 kg/m3.
## Bars (written before the code, see the report):
##   W0 after Colour is pressed, three weight chips (easypart_weight_wood / _steel / _plastic) are on the screen, inside the window
##   W1 each chip reads the built volume x its density (within 1 %): wood, metal, plastic
##   W2 a press on a weight chip changes nothing in the Part (the record is the same JSON) and says the weight in plain words
##   W3 Undo takes the solid back: the chips say "no solid yet"; Redo puts the weights back (within 1 %)
##   W4 no jargon on the chips or the words (sketch, extrude, boolean, feature, body, loft, cylinder, plane, kernel)
## shots: C:/Temp/claude/p057weightread/plate.png, colour.png
const SHOT := "C:/Temp/claude/p057weightread"
const DIRT := "user://p057weightread_test"
const DENS := {"wood": 600.0, "steel": 7850.0, "plastic": 1050.0}   # kg/m3, the design numbers (wood, steel for Metal, ABS plastic)
var fails := 0
var m: Node


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


func ev_move(p: Vector2, held := true) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func labels(n: Node, out: Array) -> void:
	if n is Label and (n as Label).is_visible_in_tree():
		out.append((n as Label).text)
	for c in n.get_children():
		labels(c, out)


func solid() -> Dictionary:
	return Part.replay(m.S.part)


## the built solid's volume in m3 (the kernel's unit: Part.MM is 1 mm = 0.001 m)
func vol_m3(s: Dictionary) -> float:
	return float(s.get("volume", 0.0))


## a weight chip's kilograms read from its words: "115 g wood" or "1.51 kg metal"; -1 when it says no solid
func kg_of(t: String) -> float:
	var rx := RegEx.new()
	rx.compile("^(\\d+(\\.\\d+)?) (g|kg) \\w+$")
	var mt := rx.search(t)
	if mt == null:
		return -1.0
	var v := float(mt.get_string(1))
	return v / 1000.0 if mt.get_string(3) == "g" else v


func chip(ep, k: String) -> Button:
	return ep.colour_box.find_child("easypart_weight_" + k, true, false) as Button


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var pu = m.bld.part
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 35.0
	m.yaw = 30.0
	m._cam()
	await idle(60)

	# the plate: a box on the grid (12 cm x 8 cm), Pull it up
	await click_ctl(ep.make_btns["draw"])
	await drag_pts([scr(Vector3(-0.06, 0.0, -0.04)), scr(Vector3(0.06, 0.0, 0.04))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var s1 := solid()
	ok(int(s1["bodies"]) == 1 and vol_m3(s1) > 0.0, "plate: one body, volume %.1f cm3" % (vol_m3(s1) * 1.0e6))

	# W0 Colour shows the three weight chips on the screen
	await click_ctl(ep.make_btns["colour"])
	await idle(10)
	await shot("plate")
	var window := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var on := true
	for k in DENS:
		var b := chip(ep, k)
		on = on and b != null and b.is_visible_in_tree() and window.encloses(b.get_global_rect())
	ok(ep.colour_box.visible and on, "W0 after Colour: the wood, metal and plastic weight chips are on the screen")
	await shot("colour")

	# W1 each chip reads the built volume x its density (within 1 %)
	var v1 := vol_m3(solid())
	var texts := []
	for k in DENS:
		var kg := kg_of(chip(ep, k).text)
		var want: float = v1 * float(DENS[k])
		texts.append("%s '%s'" % [k, chip(ep, k).text])
		ok(kg > 0.0 and absf(kg - want) < 0.01 * want, "W1 %s: chip %.4f kg vs built volume x density %.4f kg" % [k, kg, want])

	# W2 a press reads the weight out and changes nothing in the Part
	var before := JSON.stringify(m.S.part)
	var n0: int = m.undo.size()
	await click_ctl(chip(ep, "steel"))
	await idle(5)
	var words: String = String(ep.msg)
	ok(JSON.stringify(m.S.part) == before and m.undo.size() == n0 and words.find("weigh") >= 0,
		"W2 the press changes nothing (undo count %d -> %d) and says: %s" % [n0, m.undo.size(), words])

	# W3 Undo takes the solid back (the chips say no solid), Redo puts it back
	await click_ctl(ep.undo_btn)
	await idle(10)
	var none := true
	for k in DENS:
		none = none and kg_of(chip(ep, k).text) < 0.0 and chip(ep, k).text.find("no solid") >= 0
	ok(none, "W3 after Undo the chips say no solid: [%s]" % chip(ep, "wood").text)
	await click_ctl(ep.redo_btn)
	await idle(10)
	var back := true
	var v3 := vol_m3(solid())
	for k in DENS:
		var kg := kg_of(chip(ep, k).text)
		back = back and kg > 0.0 and absf(kg - v3 * float(DENS[k])) < 0.01 * v3 * float(DENS[k])
	ok(back and absf(v3 - v1) < 0.001 * v1, "W3 Redo puts the weights back (%.2f cm3, same as before)" % (v3 * 1.0e6))

	# W4 no jargon on the chips or the words
	var lab := []
	labels(ep.colour_box, lab)
	for k in DENS:
		lab.append(chip(ep, k).text)   # the chips are Buttons, not Labels
	var said := " ".join(lab) + " " + String(ep.msg)
	var jargon := []
	for w in ["sketch", "extrude", "boolean", "feature", "body", "loft", "cylinder", "plane", "kernel"]:
		if said.to_lower().find(w) >= 0:
			jargon.append(w)
	ok(jargon.is_empty(), "W4 no jargon %s on the chips and the words" % [jargon])
	print("p057weightread: %d fail" % fails)
	quit(1 if fails > 0 else 0)
