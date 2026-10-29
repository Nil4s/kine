extends SceneTree
## godot --path . -s tests/abody2_test.gd     (ABODY2: an easy body: a beginner changes the height, the build, the face and the hair, saves, reopens: every change is kept; needs a window)
## Real clicks (root.push_input) at 1280 x 720, from the real start screen: MODELING card, BODY tab, sliders, Face, Hair, the name box, My scenes, the tile.
## BARS (the first run on the old code is the proof; a bar that fails there is written as a dead end in NOTE):
##  1 HEIGHT   a click on the stature track at 95 makes the body tall (>= 1.85 m); at 5 it is short (<= 1.67 m)
##  2 BUILD    a click on the mass track at 95 makes the body heavy (mass >= 90th); at 5 light (<= 10th)
##  3 FACE     the BODY page's Face button opens the face panel with no clips; a jaw click and OK key the face (channels > 0)
##  4 HAIR     the BODY page's Hair button adds a ponytail with no clips (strands > 0)
##  5 SAVE     the name box + Enter writes the file (the body, the face and the hair in it)
##  6 REOPEN   My scenes lists the file as a tile; one click on the tile reopens that file
##  7 KEPT     after reopen: the height, the build, the face and the hair are the same as before the save
##  8 PRESSES  the whole walk takes at most 16 presses
## Only user:// is written (UserPaths.root = user://abody2_test). Shots: C:/Temp/claude/abody2/shots/

const ROOT_DIR := "user://abody2_test"
const SHOT_DIR := "C:/Temp/claude/abody2/shots"
const SCENE_NAME := "abody fighter"

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


func kept_key(d: Variant) -> String:
	return JSON.stringify(d) if d != null else ""


func _init() -> void:
	EasyMode.start_fresh = true
	UserPaths.force = true
	UserPaths.root = gp(ROOT_DIR)
	var sd := gp(ROOT_DIR) + "/scenes"
	for f in (DirAccess.get_files_at(sd) if DirAccess.dir_exists_absolute(sd) else []):
		DirAccess.remove_absolute(sd + "/" + f)
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
	# ---- start: MODELING, then the BODY tab
	await press(ss._card_art["modeling"], "MODELING card")
	await idle(20)
	await press(m.find_child("tab_body", true, false), "BODY tab")
	await idle(12)
	var P: BodyPanel = m.ui_body
	var default_mass: float = P.pr["mass"]
	# ---- 1 height
	await track(P.sliders["stat"], 95.0)
	await idle(10)
	var tall := float(BodyModel.measures(m.B)["stature"])
	ok(tall >= 1.85, "1 HEIGHT: a click at the top of the height track makes the body tall (%.1f cm)" % (tall * 100.0))
	await shot("01_tall")
	await track(P.sliders["stat"], 5.0)
	await idle(10)
	var short := float(BodyModel.measures(m.B)["stature"])
	ok(short <= 1.67, "1 HEIGHT: a click at the bottom makes it short (%.1f cm)" % (short * 100.0))
	await track(P.sliders["stat"], 62.0)
	await idle(10)
	var kept_h := float(BodyModel.measures(m.B)["stature"])
	# ---- 2 build
	await track(P.sliders["mass"], 95.0)
	await idle(10)
	var heavy: float = P.pr["mass"]
	ok(heavy >= 90.0, "2 BUILD: a click at the top of the build track makes the body heavy (%d, default %d)" % [int(heavy), int(default_mass)])
	await track(P.sliders["mass"], 5.0)
	await idle(10)
	var light: float = P.pr["mass"]
	ok(light <= 10.0, "2 BUILD: a click at the bottom makes it light (%d)" % int(light))
	await track(P.sliders["mass"], 60.0)
	await idle(10)
	var kept_mass: float = P.pr["mass"]
	await shot("02_build")
	# ---- 3 face
	var fb := visible_btn("Face: brows, eyes, jaw, mouth...")
	await press(fb, "Face button")
	await idle(8)
	var FU := m.face_ui as FaceUI
	var face_open: bool = FU != null and FU.live()
	ok(face_open and m.S.cards.is_empty(), "3 FACE: the Face button opens the face panel with no clips (open %s)" % face_open)
	if face_open:
		await track(FU._sl["jaw"], 0.8)
		await idle(3)
		await press(FU.dlg.get_ok_button(), "Key at playhead")
		await idle(8)
	var fkeys := 0
	if m.S.face is Dictionary:
		fkeys = m.S.face.size()
	ok(fkeys > 0, "3 FACE: OK keys the face (%d channels)" % fkeys)
	await shot("03_face")
	# ---- 4 hair
	await press(visible_btn("Hair: add a ponytail"), "Hair button")
	await idle(8)
	var strands := 0
	if m.S.hair is Dictionary:
		strands = int(m.S.hair.get("strands", 0))
	ok(strands > 0, "4 HAIR: one click adds a ponytail (%d strands)" % strands)
	await shot("04_hair")
	var before_face := kept_key(m.S.face)
	var before_hair := kept_key(m.S.hair)
	# ---- 5 save: the name box, Enter
	presses += 1
	var nm: LineEdit = m.ui_scene_name
	await clk_at(nm.get_screen_transform() * (nm.size * 0.5))
	nm.text = SCENE_NAME
	var e := InputEventKey.new()
	e.keycode = KEY_ENTER
	e.physical_keycode = KEY_ENTER
	e.pressed = true
	root.push_input(e, true)
	await idle(10)
	var fname := SCENE_NAME.replace(" ", "_") + ".json"
	var f := gp(ROOT_DIR + "/scenes/" + fname)
	var saved := FileAccess.file_exists(f)
	var txt := FileAccess.get_file_as_string(f) if saved else ""
	ok(saved and txt.find("\"hair\"") >= 0 and txt.find("\"face\"") >= 0, "5 SAVE: the name box + Enter writes %s (%d bytes)" % [fname, txt.length()])
	await shot("05_saved")
	# ---- 6 reopen: Home (the start screen), the saved scene's tile, one click
	var S_before: Object = m.S
	var home: Button = null
	for b in m.find_children("home_btn", "Button", true, false):
		if (b as Control).is_visible_in_tree():
			home = b
	await press(home, "Home")
	await idle(12)
	var tile: Control = ss._tiles[f]["tile"] if ss._tiles.has(f) else null
	ok(tile != null and tile.is_visible_in_tree(), "6 REOPEN: the start screen lists %s as a tile" % fname)
	await shot("06_start_screen")
	await press(tile, "tile " + fname)
	var wt := 0
	while wt < 600 and String(m.scene_path) != f:
		await process_frame
		wt += 1
	await idle(20)
	var parsed: Variant = JSON.parse_string(txt) if saved else null
	var fface := 0
	var fhair := 0
	if parsed is Dictionary:
		fface = (parsed.get("face", {}) as Dictionary).size() if parsed.get("face") is Dictionary else 0
		fhair = int((parsed.get("hair", {}) as Dictionary).get("strands", 0)) if parsed.get("hair") is Dictionary else 0
	ok(String(m.scene_path) == f and fface > 0 and fhair > 0, "6 REOPEN: one click opens the file (scene path %s; the file holds %d face channels and %d strands)" % [String(m.scene_path).get_file(), fface, fhair])
	await shot("06_reopened")
	# ---- 7 kept
	var P2: BodyPanel = m.ui_body
	var h2 := float(BodyModel.measures(m.B)["stature"])
	var mass2: float = P2.pr["mass"] if P2 != null else -1.0
	var face2 := kept_key(m.S.face)
	var hair2 := kept_key(m.S.hair)
	var sl_stat: float = P2.sliders["stat"].value if P2 != null and P2.sliders.has("stat") else -1.0
	var sl_mass: float = P2.sliders["mass"].value if P2 != null and P2.sliders.has("mass") else -1.0
	print("NOTE after reopen: page %s, Easy %s, stature slider %.1f, mass slider %.1f (KNOWN: a modeling project opens on MODEL in Expert, pinned by startbugs_test A)" % [m.cur_page, str(m.easy.on), sl_stat, sl_mass])
	ok(absf(sl_stat - 62.0) < 1.0 and absf(sl_mass - 60.0) < 1.0, "7 KEPT: the sliders read where they were left (stature %.1f, build %.1f; want 62 and 60)" % [sl_stat, sl_mass])
	ok(absf(h2 - kept_h) < 0.005,"7 KEPT: height %.1f cm after reopen (before save %.1f)" % [h2 * 100.0, kept_h * 100.0])
	ok(absf(mass2 - kept_mass) < 0.5, "7 KEPT: build %d after reopen (before save %d)" % [int(mass2), int(kept_mass)])
	ok(face2 == before_face and face2 != "", "7 KEPT: the face is the same after reopen")
	ok(hair2 == before_hair and hair2 != "", "7 KEPT: the hair is the same after reopen")
	# ---- KNOWN dead end (prints, does not fail until fixed): the Easy bar has no body button, so a beginner in Easy cannot reach these
	var easy_body := []
	for k in m.easy._btns.keys():
		var kl := String(k).to_lower()
		if kl.contains("body") or kl.contains("face") or kl.contains("hair") or kl.contains("height"):
			easy_body.append(k)
	if easy_body.is_empty():
		print("KNOWN DEAD END: the Easy bar has no Body, Face, Hair or Height button: a beginner in Easy cannot change the body (the MODELING card is Expert: MODEL and BODY)")
	else:
		print("ok   the Easy bar has a body button: %s" % str(easy_body))
	# ---- 8 presses
	ok(presses <= 16, "8 PRESSES: the walk took %d presses (bar <= 16)" % presses)
	for n in notes:
		print("NOTE ", n)
	print("abody2 presses=%d dead_ends=%d fails=%d" % [presses, notes.size(), fails])
	print("abody2 %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(1 if fails > 0 else 0)

