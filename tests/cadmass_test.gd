extends SceneTree
## godot --path . --position 4000,4000 -s tests/cadmass_test.gd     (PART -> WEAPON: scripts/build/part_weapon.gd; needs a window and the CAD DLL)
## A Part becomes a weapon kind "part:<name>": its mesh, its mass (volume x density), its centre of mass and radius of gyration from the
## kernel's inertia, its grip point (the template's handle centre). Bars, written before measuring:
##   1 MASS      a 40 x 3 x 1 cm steel bar: mass 0.942 kg within 1 %, centre of mass at its centre within 1 mm
##   2 SWORD     the Easy sword made into a weapon: its mass and centre of mass differ from the built-in sword (1.10 kg, com 0.30 L); the grip 7 cm from the butt (+-0.5 cm)
##   3 TORQUE    the same sword with a blade of 600 mm and of 1200 mm (named apart): the 1200 one is heavier and the torque judge's wrist peak (WeaponTorque.analyze) grows
##   4 SHAPE     the drawn mesh is the Part's tessellation, placed in the weapon's frame: its tip lies at the weapon's length (within 1 cm)
##   5 GRIP      the fighter takes it (weapon_to_hand): the hand's palm is on the grip point within 1 cm
##   6 BUTTONS   Easy Part's "Give it to the fighter" (real clicks) and Expert's (the timeline's button): the fighter holds the sword, ONE undo step each
##   7 CHANGE    the blade made 44 cm longer in Easy: the held kind is registered again (length + 0.44 m, rev up) and the fighter still holds it at the grip
##   8 SHOT      the fighter holding the Part sword: C:/Temp/claude/cadmass/sword_held.png
## Only user:// is written (and the shots).

const SHOT := "C:/Temp/claude/cadmass"
const DIRT := "user://cadmass_test"
var fails := 0
var m: Node
var t_mark := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func ev_move(p: Vector2, _held: bool) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e)
	await idle(2)


func ev_mouse(p: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = p
	e.global_position = p
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	root.push_input(e)
	await idle(2)


func shot(path: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png(path)


## a steel bar 400 x 30 mm, 10 mm thick, on the front plane (the sketch's x along the bar's length)
func bar_rec(name: String, length := 400.0) -> Dictionary:
	var fs: Array = []
	var sk := PartTemplates._sk(fs, "front", [PartTemplates._rect(Vector2(0, 0), Vector2(length, 30))])
	PartTemplates._ex(fs, sk, "extrude", 10.0, "new")
	var rec := Part.make(name)
	rec["features"] = fs
	rec["seq"] = fs.size()
	return rec


## one swing of scenes/combo3.json: ready, wind-up, CONTACT, follow-through, an overshoot (as the i30 test)
func swing() -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/combo3.json")))
	var B := DistanceKeeper.new_body()
	S.cards = S.cards.slice(0, 4)
	S.cards[1]["move"] = 0.6
	S.cards[1]["hold"] = 0.1
	S.cards[2]["move"] = 0.35
	S.cards[2]["hold"] = 0.1
	S.cards[3]["move"] = 0.6
	S.cards[3]["hold"] = 0.2
	var over := WeaponTorque._extrapolate(B, S.cards[2]["pose"], S.cards[1]["pose"], 0.35)
	S.cards.insert(3, {"name": "overshoot", "pose": over, "move": 0.5, "hold": 0.0})
	S.markers = []
	return S


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	if not Part.available():
		print("CADMASS ", "SKIP: no KineCAD DLL")
		quit(1)
		return

	# 1 MASS
	var bar := bar_rec("Steel bar")
	var kb := PartWeapon.register(bar)
	var kd: Dictionary = Body.KINDS.get(kb, {})
	var box := (Part.replay(bar)["aabb"] as AABB)
	var mass_bar := float(kd.get("mass", 0.0))
	var com_err := ((kd.get("com_part", Vector3(9, 9, 9)) as Vector3) - box.get_center()).length()
	ok(absf(mass_bar - 0.942) / 0.942 < 0.01, "1 MASS: the 40 x 3 x 1 cm steel bar weighs %.4f kg (0.942 within 1 %%)" % mass_bar)
	ok(com_err < 0.001, "1 MASS: its centre of mass is %.2f mm from its centre (under 1 mm)" % (com_err * 1000.0))

	# 2 SWORD
	var sw := PartTemplates.make("sword")
	var ks := PartWeapon.register(sw)
	var ksd: Dictionary = Body.KINDS.get(ks, {})
	var built: Dictionary = Body.KINDS["sword"]
	var dm := absf(float(ksd["mass"]) - float(built["mass"]))
	var dcom := absf(float(ksd["com"]) - float(built["com"]))
	ok(ks == "part:sword" and dm > 0.05 and dcom > 0.02,
		"2 SWORD: the Part sword %.2f kg, centre of mass %.0f%% along it (built-in: %.2f kg, %.0f%%)" % [float(ksd["mass"]), float(ksd["com"]) * 100.0, float(built["mass"]), float(built["com"]) * 100.0])
	ok(absf(float(ksd["grip_u"]) - 0.070) < 0.005, "2 SWORD: the grip sits %.1f cm from the butt (the handle's centre, 7 cm)" % (float(ksd["grip_u"]) * 100.0))

	# 3 TORQUE
	var short := PartTemplates.make("sword", {"blade_length": 600})
	short["name"] = "Short blade"
	var long := PartTemplates.make("sword", {"blade_length": 1200})
	long["name"] = "Long blade"
	var k_short := PartWeapon.register(short)
	var p_short := WeaponTorque.profile(k_short)
	var k_long := PartWeapon.register(long)
	var p_long := WeaponTorque.profile(k_long)
	var S := swing()
	var B := DistanceKeeper.new_body()
	var r_short := WeaponTorque.analyze(S, B, 2, p_short)
	var r_long := WeaponTorque.analyze(S, B, 2, p_long)
	var w_short := float(r_short["wrist"][0])
	var w_long := float(r_long["wrist"][0])
	print("       600 mm: %.2f kg, wrist %.2f N m | 1200 mm: %.2f kg, wrist %.2f N m | built-in sword 1.10 kg, wrist %.2f N m" % [float(p_short["mass"]), w_short, float(p_long["mass"]), w_long, float(WeaponTorque.analyze(S, B, 2, WeaponTorque.profile("sword"))["wrist"][0])])
	ok(float(p_long["mass"]) > float(p_short["mass"]) * 1.5 and w_long > w_short * 1.2,
		"3 TORQUE: doubling the blade makes the weapon heavier (%.2f -> %.2f kg) and the wrist torque grow (%.2f -> %.2f N m)" % [float(p_short["mass"]), float(p_long["mass"]), w_short, w_long])

	# 4 SHAPE
	var node := WeaponMesh.build(ks)
	var mi := node.get_node_or_null("part") as MeshInstance3D
	var tip_y := 0.0
	if mi != null and mi.mesh != null:
		tip_y = (mi.transform * mi.mesh.get_aabb()).end.y
	ok(mi != null and mi.mesh != null and mi.mesh.get_surface_count() > 0 and absf(tip_y - float(ksd["len"])) < 0.01,
		"4 SHAPE: the drawn sword's tip is %.1f cm from the butt (length %.1f cm)" % [tip_y * 100.0, float(ksd["len"]) * 100.0])
	node.free()

	# 5 GRIP (the fighter, no window needed for the numbers)
	var B2 := DistanceKeeper.new_body()
	B2.set_kind(ks)
	B2.weapon_to_hand("hand_r")
	var hu := B2.hold_u()
	ok(B2.wep_hand == "hand_r" and absf(hu - float(ksd["grip_u"])) < 0.01,
		"5 GRIP: the palm holds the sword %.1f cm from the butt (the grip point %.1f cm)" % [hu * 100.0, float(ksd["grip_u"]) * 100.0])

	# 6-7 BUTTONS and CHANGE: the building project, real clicks
	var ss: StartScreen
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	await idle(4)
	ss = m.start_screen
	var pu: PartUI = m.bld.part
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep: EasyPart = pu.ep
	var n_undo: int = m.undo.size()
	await click_ctl(ep.give_btn)
	await idle(3)
	var held: bool = m.B.wep_kind == ks
	ok(held and m.undo.size() == n_undo + 1, "6 BUTTONS: Easy's \"Give it to the fighter\" (a click): he holds %s, ONE undo step (%d -> %d)" % [m.B.wep_kind, n_undo, m.undo.size()])
	ok(m.B.wep_hand != "" and absf(m.B.hold_u() - float(ksd["grip_u"])) < 0.01, "6 BUTTONS: his palm is on the grip (%.1f cm, within 1 cm of %.1f)" % [m.B.hold_u() * 100.0, float(ksd["grip_u"]) * 100.0])
	await click_ctl(ep.use_btn)
	await idle(4)
	m._do(m._kind.bind("metal_bat"))   # the bat again, so Expert's button has to bring the sword back
	await idle(2)
	n_undo = m.undo.size()
	await click_ctl(pu.part_give)
	await idle(3)
	ok(pu.part_give.is_visible_in_tree() and m.B.wep_kind == ks and m.undo.size() == n_undo + 1,
		"6 BUTTONS: Expert's \"Give it to the fighter\" (a click, the timeline's button): the sword again, one undo step")

	# 7 CHANGE: the blade 44 cm longer, in the record; the held kind follows it
	var len0 := float(Body.KINDS[ks]["len"])
	var rev0 := int(Body.KINDS[ks]["rev"])
	PartTemplates.retemplate(m.S.part, {"blade_length": 1200})
	m.part_weapon_changed(m.S.part)
	await idle(3)
	var len1 := float(Body.KINDS[ks]["len"])
	ok(absf((len1 - len0) - 0.44) < 0.01 and int(Body.KINDS[ks]["rev"]) > rev0 and m.B.wep_kind == ks and absf(m.B.hold_u() - float(Body.KINDS[ks]["grip_u"])) < 0.01,
		"7 CHANGE: the blade 44 cm longer: the sword %.1f -> %.1f cm, registered again, still held at the grip" % [len0 * 100.0, len1 * 100.0])
	m.queue_free()
	await idle(4)

	# 8 SHOT: a fresh scene, the fighter holds the Part sword
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	await idle(4)
	var shot_rec := PartTemplates.make("sword")
	m.give_part_weapon(shot_rec)
	await idle(2)
	m.yaw = 35.0
	m.dist = 3.2
	m.pitch = -6.0
	m.target = Vector3(m.B.P["pelvis"].x, 1.0, m.B.P["pelvis"].z)
	m._cam()
	m._refresh()
	await shot(SHOT + "/sword_held.png")
	ok(m.B.wep_kind == "part:sword" and m.B.wep_hand != "", "8 SHOT: the fighter holds the Part sword (%s) -> %s/sword_held.png" % [m.B.wep_kind, SHOT])

	print("CADMASS ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
