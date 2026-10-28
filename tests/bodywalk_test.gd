extends SceneTree
## godot --path . -s tests/bodywalk_test.gd     (BODYWALK: a beginner makes a tall thin fighter and a short heavy one, changes the face and hair, saves; needs a window)
## Real clicks (root.push_input) at 1280 x 720, from the real start screen: MODELING card, BODY tab, the sliders, the buttons, Save.
## BARS (written before the fixes; the first run on the old code is the proof):
##  1 BODY    a click on the stature track at 95 and on the body mass track at 5 makes a tall thin man (>= 1.85 m, mass <= 10th);
##            then stature 5 and mass 95 makes a short heavy man (<= 1.67 m, mass >= 90th)
##  2 FACE    the BODY page has a visible "Face" button (text, not only in search); one click opens the face panel with NO clips
##            in the scene, a jaw click and OK key the face (the scene's face is written, and the panel does not say "cards first")
##  3 HAIR    the BODY page has a visible "Hair: add a ponytail" button; one click adds the hair (scene hair has strands) with NO clips
##  4 SAVE    the body-only fighter (no clips) saves by typing a name and Enter; the file holds the body, the face and the hair
##  5 PRESSES the whole walk (start to saved file) takes at most 14 presses
## Only user:// is written (UserPaths.root = user://bodywalk_test). Screenshots: C:/Temp/claude/bodywalk/<step>.png

const ROOT_DIR := "user://bodywalk_test"
const SHOT_DIR := "C:/Temp/claude/bodywalk"

var m: Node
var fails := 0
var presses := 0
var notes: Array = []


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func gp(p: String) -> String:
	return ProjectSettings.globalize_path(p)


func shot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	m.get_viewport().get_texture().get_image().save_png(SHOT_DIR + "/" + nm + ".png")


## a real click: press and release at a point, through the root viewport
func clk_at(p: Vector2) -> void:
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


func press(c: Control, what: String) -> bool:
	presses += 1
	if c == null or not c.is_visible_in_tree():
		notes.append("DEAD END: %s: nothing clickable there" % what)
		print("NOCLICK ", what)
		return false
	await clk_at(c.get_screen_transform() * (c.size * 0.5))
	return true


## a click on a slider's track at the value v (Godot moves the grabber to the press)
func track(sl: HSlider, v: float) -> void:
	presses += 1
	var g := 0.0
	var gi: Texture2D = sl.get_theme_icon("grabber")
	if gi != null:
		g = gi.get_width() * 0.5
	var t := clampf((v - sl.min_value) / (sl.max_value - sl.min_value), 0.0, 1.0)
	var local := Vector2(lerpf(g, sl.size.x - g, t), sl.size.y * 0.5)
	await clk_at(sl.get_screen_transform() * local)


func visible_btn(text: String) -> Button:
	for b in m.find_children("*", "Button", true, false):
		if (b as Control).is_visible_in_tree() and String(b.text) == text:
			return b
	return null


func _init() -> void:
	EasyMode.start_fresh = true
	UserPaths.force = true
	UserPaths.root = gp(ROOT_DIR)
	for sub in ["scenes"]:
		var d := gp(ROOT_DIR + "/" + sub)
		for f in (DirAccess.get_files_at(d) if DirAccess.dir_exists_absolute(d) else []):
			DirAccess.remove_absolute(d + "/" + f)
	DirAccess.make_dir_recursive_absolute(gp(ROOT_DIR))
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
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
	ss.dirs_override = [gp(ROOT_DIR) + "/scenes"]
	ss.show_screen(true)
	await idle(20)
	# ---- 0: the start screen -> MODELING (the body is made in MODEL's project)
	await press(ss._card_art["modeling"], "MODELING card")
	await idle(20)
	await press(m.find_child("tab_body", true, false), "BODY tab")
	await idle(12)
	var P: BodyPanel = m.ui_body
	ok(P.visible and m.cur_page == "BODY", "0 the BODY page is up after the MODELING card and the BODY tab (page %s)" % m.cur_page)
	# ---- 1 BODY: tall thin, then short heavy, by clicks on the sliders
	await track(P.sliders["stat"], 95.0)
	await track(P.sliders["mass"], 5.0)
	await idle(10)
	var tall := float(BodyModel.measures(m.B)["stature"])
	var tall_mass: float = P.pr["mass"]
	ok(tall >= 1.85 and tall_mass <= 10.0, "1 tall thin: stature %.1f cm, body mass %s (bar >= 185 cm, mass <= 10th)" % [tall * 100.0, int(tall_mass)])
	await shot("10_tall_thin")
	await track(P.sliders["stat"], 5.0)
	await track(P.sliders["mass"], 95.0)
	await idle(10)
	var short := float(BodyModel.measures(m.B)["stature"])
	var heavy_mass: float = P.pr["mass"]
	ok(short <= 1.67 and heavy_mass >= 90.0, "1 short heavy: stature %.1f cm, body mass %s (bar <= 167 cm, mass >= 90th)" % [short * 100.0, int(heavy_mass)])
	await shot("11_short_heavy")
	# ---- 2 FACE: a visible button on BODY, no clips needed
	var fb := visible_btn("Face: brows, eyes, jaw, mouth...")
	ok(fb != null, "2 the BODY page shows a 'Face' button with its words (not only in search)")
	await press(fb, "Face button")
	await idle(8)
	var FU := m.face_ui as FaceUI
	var face_open: bool = FU != null and FU.live()
	ok(face_open and m.S.cards.is_empty(), "2 one click opens the face panel with no clips in the scene (open %s, cards %d)" % [face_open, m.S.cards.size()])
	await shot("12_face_panel")
	if face_open:
		var js: HSlider = FU._sl["jaw"]
		await track(js, 0.8)
		await idle(3)
		var dlg: ConfirmationDialog = FU.dlg
		var okb: Button = dlg.get_ok_button()
		var okr := Rect2(okb.get_screen_transform().origin, okb.size)
		ok(Rect2(Vector2.ZERO, Vector2(1280, 720)).encloses(okr), "2 the panel's own 'Key at playhead' button is inside the 1280 x 720 window (at %s)" % okr)
		await press(okb, "Key at playhead")
		await idle(8)
	var fkeys := 0
	if m.S.face is Dictionary:
		fkeys = m.S.face.size()
	ok(fkeys > 0, "2 OK keys the face in the scene (%d face channels written)" % fkeys)
	# ---- 3 HAIR: a visible button, no clips
	var hb := visible_btn("Hair: add a ponytail")
	ok(hb != null, "3 the BODY page shows a 'Hair: add a ponytail' button with its words")
	await press(hb, "Hair button")
	await idle(8)
	var strands := 0
	if m.S.hair is Dictionary:
		strands = int(m.S.hair.get("strands", 0))
	ok(strands > 0, "3 one click adds the ponytail with no clips (%d strands)" % strands)
	await shot("13_hair_added")
	# ---- 4 SAVE: type a name, Enter
	presses += 1
	var nm: LineEdit = m.ui_scene_name
	await clk_at(nm.get_screen_transform() * (nm.size * 0.5))
	nm.text = "my fighter"
	var e := InputEventKey.new()
	e.keycode = KEY_ENTER
	e.physical_keycode = KEY_ENTER
	e.pressed = true
	root.push_input(e, true)
	await idle(10)
	var f := gp(ROOT_DIR + "/scenes/my_fighter.json")
	var saved := FileAccess.file_exists(f)
	var txt := FileAccess.get_file_as_string(f) if saved else ""
	ok(saved and txt.find("\"hair\"") >= 0 and txt.find("\"face\"") >= 0 and txt.find("\"body\"") >= 0, "4 the body-only fighter saves: file %s, body/face/hair in it (%s, %d bytes)" % [f.get_file(), saved, txt.length()])
	await shot("14_saved")
	# ---- 5 presses
	ok(presses <= 14, "5 the walk took %d presses (bar <= 14)" % presses)
	for n in notes:
		print("NOTE ", n)
	print("bodywalk FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)
