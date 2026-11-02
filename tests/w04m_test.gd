extends SceneTree
## w04m: the REAL path. main._import_anim_picked (what the Import animation file dialog's file_selected calls) with the Mixamo
## fixture opens the bone-map screen (nothing imported yet); a click on Import imports it; a second pick of the same rig imports with no screen.
## Shot 1024x600: C:/Users/Nick/tools/kine_workers/out/w04/main_1024x600.png
var fails := 0
var m: Node
const FIX := "res://tests/fixtures/mixamo_rig.fbx"
const SHOT := "C:/Users/Nick/tools/kine_workers/out/w04"


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click_at(p: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv, true)
	await process_frame
	for d in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = d
		e.position = p
		e.global_position = p
		if d:
			e.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(e, true)
		await process_frame
	await idle(4)


func layer() -> Node:
	for c in m.get_children():
		if c.name.begins_with("BoneMapLayer") and not c.is_queued_for_deletion():
			return c
	return null


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	root.content_scale_size = Vector2i(1024, 600)
	await idle(14)
	var path := ProjectSettings.globalize_path(FIX)
	var src := AnimImport.load_source(path)
	ok(not RetargetMap.has_saved(src), "control: rig not saved yet (fresh user dir)")
	m._import_anim_picked(path)
	await idle(8)
	var L := layer()
	ok(L != null, "1 pick opens the bone-map screen")
	if L == null:
		quit(1)
		return
	var sc: RetargetMap.Screen = L.find_children("*", "PanelContainer", true, false).filter(func(n): return n is RetargetMap.Screen)[0]
	ok(sc.shown_pairs().size() == 22, "1 screen lists %d pairs" % sc.shown_pairs().size())
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png(SHOT + "/main_1024x600.png")
	var r := sc.get_global_rect()
	ok(root.get_visible_rect().grow(1.0).encloses(r), "1 screen inside the 1024x600 window: %s" % r)
	var ib := sc.import_btn.get_global_rect()
	ok(root.get_visible_rect().grow(1.0).encloses(ib), "1 Import button on screen %s" % ib)
	await click_at(ib.get_center())
	await idle(10)
	ok(layer() == null, "2 screen closed after Import")
	ok(RetargetMap.has_saved(src), "2 map saved")
	var st: String = m.ui_status.text
	ok(st.begins_with("imported"), "2 imported: '%s'" % st.substr(0, 70))
	m.ui_status.text = ""
	m._import_anim_picked(path)
	await idle(10)
	ok(layer() == null, "3 second pick of the same rig: no screen")
	ok(m.ui_status.text.begins_with("imported"), "3 and it imported: '%s'" % m.ui_status.text.substr(0, 70))
	print("w04m: %d fail" % fails)
	quit(1 if fails > 0 else 0)
