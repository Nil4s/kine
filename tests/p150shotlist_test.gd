## godot --path . -s tests/p150shotlist_test.gd     (Friday plan 150, SHOT LIST: scripts/shot_list.gd + shot_list_ui.gd; needs a window)
## A beginner's walk with real button presses (Shot list on the CHECK row, the story box, Make the cards, Keep all, Keep again, Undo).
## Bars (measured from the built scene and its shot list: shot times, lens keys, body points projected through the built cameras):
##  (1) the panel opens from the CHECK row, inside the window, its story box and Make / Keep buttons present
##  (2) Make the cards on an EMPTY box: no card, the scene JSON is byte-identical, no undo step
##  (3) a 3-line story makes 3 card labels, and each names its camera and move: "Wide 28 mm: walk", "Close-up 85 mm: raise",
##      "Medium low angle 50 mm: strike" (counted on the panel, not from the parser's list)
##  (4) Keep all: exactly ONE undo step; the scene's shot list grows by 3
##  (5) the 3 shots start at 0, 2 and 4 s (frame-exact at the scene's fps)
##  (6) the lenses in the built shot keys are 28, 85 and 50 mm (+- 0.01)
##  (7) WIDE (shot 1): every hero body point (22 joints, head, both balls) inside the frame at the shot's start, >= 0 px margin
##  (8) CLOSE-UP (shot 2): the head top inside the frame, and the hero is >= 1.5 x taller on screen than in the wide
##  (9) LOW ANGLE (shot 3): the camera stands below the hero's middle (y < 0.9 m) and looks up (aim above the camera)
## (10) Keep all again (the same three frames are taken): nothing written, no undo step, the panel says why
## (11) Undo: the scene JSON is byte-identical to the start, the shot list is empty again
## Screenshot: user://p150shotlist.png (the panel and the three cards)
extends SceneTree

var fails := 0
var m: Node
const FRM := Rect2i(0, 0, 1280, 720)


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the hero's body points at time t in the scene's space: {"all": joints + head top + balls, "top", "hl", "hr"}
func hero_at(S: Scene, t: float) -> Dictionary:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	S.apply(B, t)
	B.fk()
	var all := []
	for j in Body.ORDER.slice(0, 22):
		all.append(B.P[j] as Vector3)
	all.append((B.P["head"] as Vector3) + Vector3(0, 0.13, 0))
	all.append((B.P["ball_l"] as Vector3) + Vector3(0, -0.03, 0))
	all.append((B.P["ball_r"] as Vector3) + Vector3(0, -0.03, 0))
	return {"all": all, "top": (B.P["head"] as Vector3) + Vector3(0, 0.13, 0), "hl": B.P["hand_l"] as Vector3, "hr": B.P["hand_r"] as Vector3}


## the smallest distance (px) from the frame edge over the points, as seen through the camera key (< 0: a point is outside)
func margin(key: Dictionary, pts: Array) -> float:
	var worst := 1e9
	for p in pts:
		var q := ShotCam.project(key["pos"], key["aim"], float(key["f"]), FRM, p as Vector3)
		worst = minf(worst, minf(minf(q.x, 1280.0 - q.x), minf(q.y, 720.0 - q.y)))
	return worst


## the hero's height on screen (px): top to the lowest body point, through the key
func height_px(key: Dictionary, pts: Array, top: Vector3) -> float:
	var lo := 1e9
	for p in pts:
		lo = minf(lo, (p as Vector3).y)
	var a := ShotCam.project(key["pos"], key["aim"], float(key["f"]), FRM, top)
	var b := ShotCam.project(key["pos"], key["aim"], float(key["f"]), FRM, Vector3(top.x, lo, top.z))
	return absf(b.y - a.y)


func ribbon_button(text: String) -> Button:
	for c in m.ui_ribbon["CHECK"].get_children():
		if c is Button and (c as Button).text == text:
			return c
	return null


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
	var S: Scene = m.S
	var before := JSON.stringify(m._hero_scene().to_dict(m.B, false))
	var u0: int = m.undo.size()
	# (1) open from the CHECK row, a real press
	var btn := ribbon_button("Shot list")
	ok(btn != null, "(1) a Shot list button on the CHECK row")
	if btn != null:
		btn.pressed.emit()
	await idle()
	var pn: PanelContainer = m.sl_ui.panel
	var vp := m.get_viewport().get_visible_rect()
	ok(pn != null and pn.visible and vp.encloses(pn.get_global_rect()) and pn.find_child("sl_story", true, false) != null
		and pn.find_child("sl_make", true, false) != null and pn.find_child("sl_keep", true, false) != null,
		"(1) the panel is open inside the window %s: story box, Make the cards, Keep all" % [pn.get_global_rect() if pn != null else "none"])
	# (2) Make on an empty box
	m.sl_ui.make_cards()
	await idle()
	ok(m.sl_ui.cards.is_empty() and m.sl_ui.card_box.get_child_count() == 0 and m.undo.size() == u0 and JSON.stringify(m._hero_scene().to_dict(m.B, false)) == before,
		"(2) Make on an empty box: %d cards, undo steps %d -> %d, scene JSON identical" % [m.sl_ui.card_box.get_child_count(), u0, m.undo.size()])
	# (3) the story, typed, then Make
	m.sl_ui.story.text = "Wide: hero walks in. Close-up: hero raises a fist. Low angle: hero strikes."
	m.sl_ui.make_cards()
	await idle()
	var texts := []
	for k in 4:
		var l = pn.find_child("sl_card_%d" % (k + 1), true, false)
		if l != null:
			texts.append(String(l.text))
	var names_ok := texts.size() == 3 and String(texts[0]).contains("Wide 28 mm: walk") and String(texts[1]).contains("Close-up 85 mm: raise") \
		and String(texts[2]).contains("Medium low angle 50 mm: strike")
	ok(names_ok, "(3) %d cards on the panel: %s" % [texts.size(), " | ".join(texts)])
	# (4) Keep all: one undo step
	var u1: int = m.undo.size()
	var n0: int = m._shot_shots().size()
	pn.find_child("sl_keep", true, false).pressed.emit()
	await idle()
	var sh: Array = m._shot_shots()
	ok(m.undo.size() == u1 + 1 and sh.size() == n0 + 3, "(4) Keep all: one undo step (%d -> %d), shots %d -> %d" % [u1, m.undo.size(), n0, sh.size()])
	# (5) start times, frame-exact
	var fps: int = m.S.fps
	var starts := []
	for x in sh:
		starts.append(roundi(float(x["t"]) * fps))
	ok(starts == [0, 2 * fps, 4 * fps], "(5) shot starts in frames %s at %d fps: 0, 2 s, 4 s" % [str(starts), fps])
	# (6) lenses from the built keys
	var lens := []
	for x in sh:
		lens.append(snappedf(float(x["keys"][0]["f"]), 0.01))
	ok(lens == [28.0, 85.0, 50.0], "(6) built lenses %s mm: wide 28, close-up 85, medium 50" % str(lens))
	# (7)-(9) the frames, from the built scene at each shot's start
	var wide_key: Dictionary = sh[0]["keys"][0]
	var hw := hero_at(S, float(sh[0]["t"]))
	var mw := margin(wide_key, hw["all"] as Array)
	ok(mw >= 0.0, "(7) WIDE: every body point in frame, the closest %.0f px from an edge" % mw)
	var close_key: Dictionary = sh[1]["keys"][0]
	var hc := hero_at(S, float(sh[1]["t"]))
	var mc := margin(close_key, [hc["top"]])
	var mh := margin(close_key, [hc["hl"], hc["hr"]])
	ok(mc >= 0.0, "(8) CLOSE-UP: the head top in frame, %.0f px from an edge (the hands hang low in the start pose: %.0f px, not a bar)" % [mc, mh])
	var hp_c := height_px(close_key, hc["all"] as Array, hc["top"])
	var hp_w := height_px(wide_key, hw["all"] as Array, hw["top"])
	ok(hp_w > 0.0 and hp_c >= 1.5 * hp_w, "(8) the hero on screen: close-up %.0f px tall, wide %.0f px (x%.2f, need 1.5)" % [hp_c, hp_w, hp_c / maxf(hp_w, 1.0)])
	var low_key: Dictionary = sh[2]["keys"][0]
	var pos: Vector3 = low_key["pos"]
	var aim: Vector3 = low_key["aim"]
	ok(pos.y < 0.9 and aim.y > pos.y, "(9) LOW ANGLE: camera %.2f m high, aim %.2f m: below the hero's middle, looking up" % [pos.y, aim.y])
	# (10) Keep all again: the same frames are taken
	var u2: int = m.undo.size()
	pn.find_child("sl_keep", true, false).pressed.emit()
	await idle()
	ok(m.undo.size() == u2 and m._shot_shots().size() == 3, "(10) Keep all again: nothing written, undo steps %d -> %d, shots %d" % [u2, m.undo.size(), m._shot_shots().size()])
	# (11) undo
	m._undo()
	await idle()
	ok(JSON.stringify(m._hero_scene().to_dict(m.B, false)) == before and m._shot_shots().is_empty(), "(11) Undo: the scene JSON is exact again, no shots")
	m.get_viewport().get_texture().get_image().save_png("user://p150shotlist.png")
	print("     screenshot: %s" % ProjectSettings.globalize_path("user://p150shotlist.png"))
	print("P150SHOTLIST %s" % ("FAIL" if fails > 0 else "PASS") + (" (%d failed)" % fails if fails > 0 else ""))
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
