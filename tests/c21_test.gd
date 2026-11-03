extends SceneTree
## godot --headless --path . -s tests/c21_test.gd     (C21: errors and sketches. #29 how-to-fix on every failed step, #61 which shapes are free, #40 a tiny or huge character)
## Bars, written before any number was read:
##   1 FIXLINE   a record of failing steps (extrude of a missing sketch, a fillet far too big, a shell / mirror / split / pattern of a body that is not there):
##               EVERY message in the replay's errors ends with a "How to fix:" sentence of 6+ words, the sentence appears once
##               (a second FixHint pass changes nothing), and the message's own start is still there (4+ chars before the mark)
##   2 AUDIT     every step type the replay's match handles (read from scripts/build/part.gd) has its own sentence in FixHint.DEFAULTS,
##               and at least one real message carries its own step type's sentence
##   3 CONTROL   a clean part has no errors and no mark; FixHint.add("") stays ""; the generic sentence differs from every typed one
##   4 FREE      a rectangle of four lines by real clicks: with "Show what is free" ON the status line names the free shapes ("free to move: line 1 ...")
##               and the pixel under the bottom line is orange (red - blue >= 25); OFF: no "free to move" and the pixel is blue (blue > red)
##   5 DEFINED   dimensioned until fully defined: ON still shows no "free to move" (nothing is free)
##   6 CHAR      a 0.12 m and an 8 m tall character: verdict off, factor = 1.75/height; a 1.8 m one is not off (factor 1.0, no panel);
##               the panel's real button click puts a prop 1.75 m tall (+-1 cm) in Props; Keep it closes the panel and adds nothing
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c21"
const DIRT := "user://c21_test"
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


func ev_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e, true)
	await process_frame


func key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	root.push_input(e, true)
	await idle(2)


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func click_at(p: Vector2) -> void:
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(2)


func press_tool(pu: PartUI, t: String) -> void:
	var b: Button = pu.tool_btns[t]
	if b.is_visible_in_tree():
		await click_ctl(b)
		return
	await click_ctl(m.ui_more)
	m.ui_more.get_popup().hide()
	var i: int = m._more_tools.find(b)
	if i >= 0:
		m._more_pick(i)
	await idle(2)


func sp2(x: float, y: float) -> Vector2:
	return m.cam.unproject_position(Part.to_world(Part.plane("front"), Vector2(x, y)))


func shot(nm: String) -> Image:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	var img: Image = root.get_texture().get_image() if root.get_texture() != null else null
	if img != null:
		img.save_png("%s/%s.png" % [SHOT, nm])
	return img


## the most orange / most blue pixel near p: [max(red - blue), max(blue - red)]
func tint_near(img: Image, p: Vector2) -> Array:
	var rb := -999.0
	var br := -999.0
	if img == null:
		return [rb, br]
	var sx := float(img.get_width()) / float(root.size.x)
	var sy := float(img.get_height()) / float(root.size.y)
	for dx in range(-4, 5):
		for dy in range(-4, 5):
			var x := clampi(int(p.x * sx) + dx, 0, img.get_width() - 1)
			var y := clampi(int(p.y * sy) + dy, 0, img.get_height() - 1)
			var c := img.get_pixel(x, y)
			rb = maxf(rb, (c.r - c.b) * 255.0)
			br = maxf(br, (c.b - c.r) * 255.0)
	return [rb, br]


func add_f(rec: Dictionary, t: String, f: Dictionary, nm: String) -> String:
	var fields := f.duplicate()
	fields["name"] = nm
	var nf := Part.new_feature(rec, t, fields)
	(rec["features"] as Array).append(nf)
	return String(nf["id"])


func write_tall(path: String, h: float) -> void:
	var r := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(h * 0.3, h, h * 0.2)
	mi.mesh = bm
	r.add_child(mi)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_scene(r, st)
	doc.write_to_filesystem(st, ProjectSettings.globalize_path(path))
	r.free()


func part1_fixlines() -> void:
	var rec := Part.make("c21 failing")
	add_f(rec, "prim", {"kind": "box", "op": "new", "w": 40, "h": 40, "d": 40}, "Block")
	var ids := {}
	ids["extrude"] = add_f(rec, "extrude", {"sketch": "nosuchsketch", "dist": 5, "both": false, "op": "join"}, "Broken pull")
	ids["fillet"] = add_f(rec, "fillet", {"body": 0, "r": 900.0, "edges": [{"p": [0, 0, 20], "q": [0, 0, 0.5], "d": [0, 0, 1]}]}, "Huge round")
	ids["shell"] = add_f(rec, "shell", {"body": 9, "t": 2.0, "faces": []}, "Shell of nothing")
	ids["mirror"] = add_f(rec, "mirror", {"body": 9, "plane": "yz"}, "Mirror of nothing")
	ids["split"] = add_f(rec, "split", {"body": 9, "plane": "xy", "at": 0.0}, "Split of nothing")
	ids["pattern"] = add_f(rec, "pattern", {"body": 9, "count": 3, "dx": 50.0}, "Pattern of nothing")
	var res := Part.replay(rec)
	var errs: Dictionary = res["errors"]
	ok(errs.size() >= 4, "1 the failing record fails in %d steps: %s" % [errs.size(), str(errs.keys())])
	var all_marked := true
	var once := true
	var typed_n := 0
	for k in errs:
		var msg := String(errs[k])
		var i := msg.find(FixHint.MARK)
		var sentence := msg.substr(i + FixHint.MARK.length()) if i >= 0 else ""
		if i < 4 or sentence.split(" ", false).size() < 6:
			all_marked = false
			print("   not marked: ", k, " = ", msg)
		if FixHint.add(msg) != msg or msg.count(FixHint.MARK) != 1:
			once = false
		for t in ids:
			if ids[t] == k and sentence.begins_with(String(FixHint.DEFAULTS[t])):
				typed_n += 1
	ok(all_marked, "1 every message ends with a How to fix sentence of 6+ words and keeps its own start")
	ok(once, "1 the sentence appears once")
	ok(typed_n >= 1, "2 at least one real message carries its own step type's sentence (%d)" % typed_n)
	var src := FileAccess.get_file_as_string("res://scripts/build/part.gd")
	var re := RegEx.new()
	re.compile("(?m)^\\t\\t\\t((?:\"[a-z_0-9]+\"(?:, )?)+):")
	var types := {}
	var a0 := src.find("static func replay(")
	var a1 := src.find("\nstatic func ", a0 + 10)
	for mt in re.search_all(src.substr(a0, a1 - a0)):
		for q in String(mt.get_string(1)).split(", "):
			types[q.trim_prefix("\"").trim_suffix("\"")] = true
	var missing := []
	for t in types:
		if not FixHint.DEFAULTS.has(t):
			missing.append(t)
	ok(types.size() >= 20 and missing.is_empty(), "2 AUDIT %d step types in the replay, missing a sentence: %s" % [types.size(), str(missing)])
	var clean := Part.make("c21 clean")
	add_f(clean, "prim", {"kind": "box", "op": "new", "w": 40, "h": 40, "d": 40}, "Block")
	var cr := Part.replay(clean)
	ok((cr["errors"] as Dictionary).is_empty(), "3 CONTROL a clean part has no errors, so no mark")
	ok(FixHint.add("") == "", "3 CONTROL an empty message stays empty")
	var distinct := true
	for t in FixHint.DEFAULTS:
		if FixHint.DEFAULTS[t] == FixHint.GENERIC:
			distinct = false
	ok(distinct, "3 CONTROL the generic sentence is not any typed one")
	ok(FixHint.add("something odd", "nonsense").ends_with(FixHint.GENERIC + "."), "3 an unknown step type gets the generic sentence")


func part2_free() -> void:
	var ss: StartScreen = m.start_screen
	var bld: BuildUI = m.bld
	var pu: PartUI = bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await idle(3)
	await click_ctl(pu.browser.find_child("part_plane_front", true, false))
	ok(pu.sk != "", "4 the Front plane starts a sketch")
	await press_tool(pu, "Line")
	for q in [[0, 0], [100, 0], [100, 60], [0, 60], [0, 0]]:
		await click_at(sp2(q[0], q[1]))
	await key(KEY_ESCAPE)
	var sk: Dictionary = pu._sk()
	for c in [{"k": "coin", "a": 0, "ap": 1, "b": 1, "bp": 0}, {"k": "coin", "a": 1, "ap": 1, "b": 2, "bp": 0}, {"k": "coin", "a": 2, "ap": 1, "b": 3, "bp": 0}, {"k": "coin", "a": 3, "ap": 1, "b": 0, "bp": 0},
			{"k": "h", "a": 0}, {"k": "h", "a": 2}, {"k": "v", "a": 1}, {"k": "v", "a": 3}]:
		Part.con_put(sk, c)
	pu._after_sketch_edit()
	await idle(3)
	var chk: CheckBox = pu.find_child("part_show_free", true, false)
	ok(chk != null and chk.is_visible_in_tree(), "4 the Show what is free box is on the sketch palette")
	var mid := sp2(50, 0)
	var off_img := await shot("c21_free_off_1280")
	var off_t := tint_near(off_img, mid)
	ok(not String(pu._profile_ok).contains("free to move"), "4 OFF the status line is unchanged: '%s'" % pu._profile_ok)
	ok(off_t[1] > off_t[0], "4 OFF the bottom line is blue (blue-red %.0f, red-blue %.0f)" % [off_t[1], off_t[0]])
	await click_ctl(chk)
	await idle(3)
	ok(pu.show_free, "4 the click turned it on")
	ok(String(pu._profile_ok).contains("free to move: line 1"), "4 ON the status line names the free lines: '%s'" % pu._profile_ok)
	var on_img := await shot("c21_free_on_1280")
	var on_t := tint_near(on_img, mid)
	ok(on_t[0] >= 25.0, "4 ON the bottom line carries the orange ring (red-blue %.0f)" % on_t[0])
	var h: Dictionary = PartHealth.analyze(sk)
	var fs := PartHealth.free_shapes(sk, h)
	ok(fs.size() >= 1 and int(h["free"]) == 2, "4 free_shapes lists %d shapes, free count %d" % [fs.size(), int(h["free"])])
	Part.set_dim(sk, 0, "len", 100.0)
	Part.set_dim(sk, 1, "len", 60.0)
	Part.solve(sk)
	pu._after_sketch_edit()
	await idle(3)
	h = PartHealth.analyze(sk)
	ok(h["state"] == "defined" and PartHealth.free_shapes(sk, h).is_empty(), "5 fully defined: nothing free")
	ok(not String(pu._profile_ok).contains("free to move") and String(pu._profile_ok).contains("fully defined"), "5 status with the box still ON: '%s'" % pu._profile_ok)
	await shot("c21_defined_1280")
	pu.set_on(false)
	await idle(3)


func part3_char() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	var small := DIRT + "/tiny.glb"
	var huge := DIRT + "/giant.glb"
	var fine := DIRT + "/fine.glb"
	write_tall(small, 0.12)
	write_tall(huge, 8.0)
	write_tall(fine, 1.8)
	var is_ := Importer.inspect(small)
	var ih := Importer.inspect(huge)
	var if_ := Importer.inspect(fine)
	var vs := CharScale.verdict(is_)
	var vh := CharScale.verdict(ih)
	var vf := CharScale.verdict(if_)
	ok(bool(vs["off"]) and absf(float(vs["factor"]) - 1.75 / 0.12) < 0.01, "6 0.12 m: off, factor %.3f (want %.3f)" % [float(vs["factor"]), 1.75 / 0.12])
	ok(bool(vh["off"]) and absf(float(vh["factor"]) - 1.75 / 8.0) < 0.001, "6 8 m: off, factor %.4f" % float(vh["factor"]))
	ok(not bool(vf["off"]) and float(vf["factor"]) == 1.0, "6 CONTROL 1.8 m is not off")
	ok(CharScale.offer(m, fine, if_) == null, "6 CONTROL a believable height gets no panel")
	var panel := CharScale.offer(m, small, is_)
	await idle(3)
	ok(panel != null and panel.is_inside_tree(), "6 the panel shows for the 0.12 m character")
	await shot("c21_char_panel_1280")
	var go: Button = m.find_child("char_scale_fix", true, false)
	var before := Props.EXTRA.size()
	await click_ctl(go)
	await idle(3)
	var added := ""
	for k in Props.EXTRA:
		if String(k).begins_with("my tiny"):
			added = String(k)
	var hgt := 0.0
	if added != "":
		var e: Dictionary = Props.EXTRA[added]
		hgt = (e["aabb"] as AABB).size.y * float(e["factor"])
	ok(added != "" and absf(hgt - 1.75) < 0.01, "6 the click put '%s' in the set, %.3f m tall" % [added, hgt])
	ok(panel.is_queued_for_deletion(), "6 the panel closed after the click")
	var p2 := CharScale.offer(m, huge, ih)
	await idle(2)
	var n2 := Props.EXTRA.size()
	await click_ctl(m.find_child("char_scale_keep", true, false))
	await idle(2)
	ok(Props.EXTRA.size() == n2 and n2 >= before, "6 Keep it adds nothing (%d props)" % Props.EXTRA.size())
	ok(p2 != null and p2.is_queued_for_deletion(), "6 Keep it closes the panel")


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1280, 720)
	root.size = Vector2i(1280, 720)
	await idle(4)
	if not Part.available():
		print("SKIP: no KineCAD DLL")
		quit(0)
		return
	part1_fixlines()
	await part2_free()
	await part3_char()
	print("c21: %d fail%s" % [fails, "" if fails == 1 else "s"])
	quit(1 if fails > 0 else 0)
