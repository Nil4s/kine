extends SceneTree
## s165 (Friday plan 165): Build-along challenges. Parts page > Challenges opens a card with five challenges (target picture, key sizes in words,
## How close am I?). Score = 100 x IoU x size fit, IoU from the kernel's intersect volume. Real clicks at 1280 x 720; every number is measured.
## Bars: 1 five challenges, picture drawn, target sizes as authored; 2 each target record scores >= 98 (shared / both volumes printed);
## 3 phone stand with no slot scores < 90 and the hint names the slot; 4 twice as tall scores < 60 and says too tall with 40 mm;
## 5 no undo step, record untouched; 6 the card is on screen and covers no button; 7 nothing built is said in words.
## Shots: C:/Temp/claude/s165/stand.png, gears.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s165"
const DIRT := "user://s165_test"
var pu: PartUI
var ep


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


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func load_rec(rec: Dictionary) -> void:
	m.S.part = rec.duplicate(true)
	pu.sync()
	await idle(6)


func press_check(id: String) -> Dictionary:
	await click_ctl(root.find_child("easypart_challenge_" + id, true, false))
	await click_ctl(root.find_child("easypart_challenge_check", true, false))
	return ep.challenge_card.last


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
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	m.bld.part.set_on(false)
	m.S.part = {}
	await idle(8)
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	# 1 OPEN
	var pb := root.find_child("easypart_chip_parts", true, false) as Button
	await click_ctl(pb)
	var cb := root.find_child("easypart_challenges", true, false) as Button
	ok(cb != null and cb.is_visible_in_tree(), "1 the Challenges chip is on the Parts page")
	await click_ctl(cb)
	await idle(4)
	var card := root.find_child("easypart_challenge_card", true, false) as Control
	ok(card != null and card.visible, "1 the card opens")
	var ids := ["stand", "bracket", "hook", "lidbox", "gears"]
	var nchips := 0
	for id in ids:
		if root.find_child("easypart_challenge_" + id, true, false) != null:
			nchips += 1
	ok(nchips == 5, "1 five challenge chips (%d)" % nchips)
	var want := {"stand": Vector3(80, 40, 60), "bracket": Vector3(50, 50, 30), "hook": Vector3(40, 60, 12), "lidbox": Vector3(64, 30, 40), "gears": Vector3(64, 44, 10)}
	for id in ids:
		var inf := EasyChallenge.target_info(id)
		var sz: Vector3 = inf["size"]
		var d := (sz - (want[id] as Vector3)).abs()
		var tol := 3.0 if id == "gears" else 0.3
		ok(d.x <= tol and d.y <= tol and d.z <= tol and float(inf["vol"]) > 100.0, "1 %s target measures %.1f x %.1f x %.1f mm, %.0f mm3 (authored %s)" % [id, sz.x, sz.y, sz.z, float(inf["vol"]), str(want[id])])
		ok(EasyChallenge.picture(id).get_image().get_used_rect().size.x > 30, "1 %s picture is drawn" % id)
	# 2 exact target scores >= 98
	for id in ids:
		await load_rec(EasyChallenge.target_record(id))
		var undo0: int = m.undo.size()
		var feats0 := JSON.stringify(m.S.part)
		var r := await press_check(id)
		ok(int(r.get("score", 0)) >= 98 and float(r.get("shared", 0.0)) > 0.0, "2 %s exact target: score %d, shared %.1f mm3, yours %.1f, target %.1f, IoU %.4f" % [id, int(r.get("score", 0)), float(r.get("shared", 0.0)), float(r.get("built", 0.0)), float(r.get("target", 0.0)), float(r.get("iou", 0.0))])
		ok(m.undo.size() == undo0 and JSON.stringify(m.S.part) == feats0, "5 %s: How close am I? left the record and the undo stack alone" % id)
		if id == "stand":
			await shot("stand")
			var cr := Rect2(card.global_position, card.size)
			var bad := []
			for c in root.find_children("*", "Button", true, false):
				var b := c as Button
				if b.is_visible_in_tree() and not card.is_ancestor_of(b) and cr.intersects(Rect2(b.global_position, b.size)):
					bad.append("%s %s vis %s a %.2f" % [b.name, str(Rect2(b.global_position, b.size)), str(b.is_visible_in_tree()), b.get_combined_minimum_size().x])
			var vr := Rect2(Vector2.ZERO, Vector2(1280, 720))
			ok(vr.encloses(cr) and bad.is_empty() and not ep.panel.get_global_rect().intersects(cr), "6 the card %s is on screen and covers no button/panel %s" % [str(cr), str(bad)])
			ok(root.find_child("easypart_challenge_pic", true, false).is_visible_in_tree(), "6 the challenge picture is visible")
	# 3 stand without the slot
	var rec: Dictionary = EasyChallenge.target_record("stand")
	var fs: Array = rec["features"]
	fs.resize(fs.size() - 2)
	await load_rec(rec)
	var r3 := await press_check("stand")
	ok(int(r3["score"]) < 90 and String(r3["hint"]).to_lower().contains("slot") and (r3["missing"] as Array).has("slot"), "3 box with no slot: score %d, shared %.1f of yours %.1f / target %.1f, hint [%s]" % [int(r3["score"]), float(r3["shared"]), float(r3["built"]), float(r3["target"]), r3["hint"]])
	# 4 twice as tall
	var rec4: Dictionary = EasyChallenge.target_record("stand")
	rec4["features"][0]["ents"][0]["b"] = [80, 80]
	await load_rec(rec4)
	var r4 := await press_check("stand")
	ok(int(r4["score"]) < 60 and String(r4["hint"]).contains("too tall") and String(r4["hint"]).contains("40 mm"), "4 twice as tall: score %d, IoU %.3f, fit %.3f, hint [%s]" % [int(r4["score"]), float(r4["iou"]), float(r4["fit"]), r4["hint"]])
	# 4b other hints
	var rec5: Dictionary = EasyChallenge.target_record("hook")
	rec5["features"][1]["dist"] = 6.0
	await load_rec(rec5)
	var r5 := await press_check("hook")
	ok(String(r5["hint"]).contains("too shallow") and String(r5["hint"]).contains("6 mm"), "4 hook half as deep: score %d, hint [%s]" % [int(r5["score"]), r5["hint"]])
	var rec6: Dictionary = EasyChallenge.target_record("lidbox")
	rec6["features"].resize(4)
	await load_rec(rec6)
	var r6 := await press_check("lidbox")
	ok(int(r6["score"]) < 98 and String(r6["hint"]).contains("too short") and String(r6["hint"]).contains("6 mm"), "4 box with lid, no knob (6 mm shorter): score %d, hint [%s]" % [int(r6["score"]), r6["hint"]])
	# 7 nothing built
	await load_rec(Part.make("Part"))
	var r7 := await press_check("stand")
	ok(bool(r7["nothing"]) and String(r7["hint"]).contains("Nothing built"), "7 nothing built says so [%s]" % r7["hint"])
	await load_rec(EasyChallenge.target_record("gears"))
	await click_ctl(root.find_child("easypart_challenge_gears", true, false))
	await click_ctl(root.find_child("easypart_challenge_check", true, false))
	await shot("gears")
	print("s165: %d fail" % fails)
	quit(1 if fails > 0 else 0)
