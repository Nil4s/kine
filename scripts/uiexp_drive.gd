class_name UiExpDrive
extends RefCounted
## UIEXP DRIVER (lane L2): puts a live Main on one of the Expert screens at one window size, for the audit and the bars.
## Screens: "part" (the Part workspace, a sketch open and the Extrude dialog), "assembly" (two library parts placed),
## "engineering" (the Assembly screen with the Fits panel open: tolerances, stack-up).
const SIZES := [Vector2i(1920, 1080), Vector2i(1600, 900), Vector2i(1366, 768), Vector2i(1280, 720)]
const SCREENS := ["part", "assembly", "engineering"]

var t: SceneTree
var m: Node


func idle(n := 3) -> void:
	for i in n:
		await t.process_frame


func boot(tree: SceneTree, dirt := "user://uiexp_dirs") -> void:
	t = tree
	m = (load("res://main.tscn") as PackedScene).instantiate()
	t.root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	t.root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dirt))
	m.start_screen.dirs_override = [dirt]
	await idle(3)


func set_size(sz: Vector2i) -> void:
	t.root.size = sz
	t.root.content_scale_size = sz
	await idle(10)


func click(c: Control) -> void:
	var p: Vector2 = t.root.get_final_transform() * c.get_global_rect().get_center()
	for step in 3:
		if step == 0:
			var mv := InputEventMouseMotion.new()
			mv.position = p
			mv.global_position = p
			t.root.push_input(mv, true)
		else:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = step == 1
			e.position = p
			e.global_position = p
			if step == 1:
				e.button_mask = MOUSE_BUTTON_MASK_LEFT
			t.root.push_input(e, true)
		await t.process_frame
	await idle(2)


func start_building() -> void:
	var ss: StartScreen = m.start_screen
	ss.show_screen()
	await idle(3)
	await click(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(6)


func screen(name: String) -> void:
	var pu: PartUI = m.bld.part
	var A: AssemblyUI = m.bld.asm
	if A.on:
		A.close()
		await idle(4)
	if pu.on:
		pu.set_on(false)
		await idle(3)
	match name:
		"part":
			pu.set_on(true)
			await idle(4)
			pu.begin_sketch("front")
			await idle(3)
			pu._pick("Extrude")
			await idle(5)
		"assembly", "engineering":
			m.build_choose.show_chooser()
			await idle(3)
			m.build_choose.new_assembly()
			await idle(4)
			var ids := PartCatalog.ids()
			A.add_library("screw_m4" if ids.has("screw_m4") else String(ids[0]))
			A.add_library("bracket_l" if ids.has("bracket_l") else String(ids[1]))
			await idle(4)
			if name == "engineering":
				A.fits.open()
				await idle(4)
	await idle(4)
