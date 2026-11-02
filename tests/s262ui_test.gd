extends SceneTree
## godot --path . --position 4000,4000 -s tests/s262ui_test.gd   (s262 EXPLODED VIEW in the app: scripts/easy_explode.gd, row in scripts/easy_search.gd; needs the CAD DLL)
## Bars (real clicks; 1280x720, 1024x600, 1920x1080; backplate, plate and 2 screws through both, made as records):
##   1 PALETTE   the Ctrl+K row "Easy Part: Exploded view" exists and its press opens the panel (go button visible)
##   2 CLICK     a real click on the button plans: the words put both screws before the plate; 0 clashes; the naive order reports >= 1
##   3 VIEW      record and undo count unchanged; a screw moved >= 10 mm at the end of out; Put back restores the bodies
##   4 CAMERA    camera on: >= 3 frames, the silhouette share of every frame <= 0.9 (width and height)
##   5 STRIP     8 frames over a 1.6 - 2.4 s run saved as one png strip to C:/Users/Nick/tools/kine_workers/out/s262/strip.png (look at it)
var fails := 0
var m: Node
const SHOT := "C:/Users/Nick/tools/kine_workers/out/s262"
const DIRT := "user://s262ui_test"


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


func click_at(p: Vector2) -> void:
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func box1(id0: int, a: Array, b: Array, d: float) -> Array:
	return [
		{"t": "sketch", "id": "f%d" % id0, "name": "Sketch%d" % id0, "plane": "front", "ents": [{"k": "rect", "a": a, "b": b}], "dims": []},
		{"t": "extrude", "id": "f%d" % (id0 + 1), "name": "Extrude%d" % id0, "sketch": "f%d" % id0, "dist": d, "both": true, "op": "new"}]


func set_part2(feats: Array, nm: String) -> void:
	var pu = m.bld.part
	var rec := Part.make(nm)
	rec["features"] = feats
	rec["seq"] = feats.size()
	m.S.part = rec
	pu.upto = -1
	pu.sync()
	await idle(3)


func boxes_of(mesh: Mesh) -> Array:
	var out: Array = []
	for s in mesh.get_surface_count():
		var vs: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		var box := AABB(vs[0], Vector3.ZERO)
		for v in vs:
			box = box.expand(v)
		out.append(box)
	return out


func run_at(size: Vector2i, tag: String) -> void:
	root.content_scale_size = size
	root.size = size
	await idle(4)
	var pu: PartUI = m.bld.part
	var ep = pu.ep
	var feats: Array = []
	feats.append_array(box1(1, [-30.0, 0.0], [30.0, 2.0], 10.0))     # backplate (surface 0)
	feats.append_array(box1(3, [-30.0, 2.0], [30.0, 4.0], 10.0))     # plate (1)
	feats.append_array(box1(5, [-24.0, -2.0], [-20.0, 5.0], 2.0))    # screw (2)
	feats.append_array(box1(7, [20.0, -2.0], [24.0, 5.0], 2.0))      # screw (3)
	await set_part2(feats, "Stack")
	await idle(40)   # the part's own frame-the-view move has finished
	ok(int(pu.res.get("bodies", 0)) == 4, tag + " the stack has 4 bodies (%d)" % int(pu.res.get("bodies", 0)))
	var ub: int = m.undo.size()
	var nf: int = (m.S.part["features"] as Array).size()
	var before := boxes_of(pu.part_mesh.mesh)
	var row: Dictionary = {}
	for r in EasySearch.rows(m):
		if String(r["name"]) == "Easy Part: Exploded view":
			row = r
	ok(not row.is_empty(), tag + " 1 PALETTE row exists")
	if row.is_empty():
		return
	await (row["run"] as Callable).call()
	await idle(4)
	var xb = ep.xview_box
	ok(xb.visible and xb.go_btn.is_visible_in_tree(), tag + " 1 PALETTE the row opens the panel and starts the run")
	await shot(tag + "_panel")
	xb.cam_check.button_pressed = true
	await click_ctl(xb.go_btn)
	var words: String = xb.last_words
	print(tag, " words: ", words)
	var i3 := words.find("Body3")
	var i4 := words.find("Body4")
	var i2 := words.find("Body2")
	var scr_first := i3 >= 0 and i4 >= 0 and i2 >= 0 and i3 < i2 and i4 < i2
	var ck := ExplodeView.check(xb.plan, xb.sched)
	var nk := ExplodeView.check(xb.plan, ExplodeView.naive_schedule(xb.plan))
	ok(scr_first and (ck["collisions"] as Array).is_empty(), tag + " 2 CLICK screws before the plate, 0 clashes: " + words)
	ok((nk["collisions"] as Array).size() >= 1, tag + " 2 CONTROL naive order has %d clashes" % (nk["collisions"] as Array).size())
	ok(m.undo.size() == ub and (m.S.part["features"] as Array).size() == nf, tag + " 3 VIEW no undo step, record unchanged")
	xb.playing = false
	xb.set_process(false)
	xb.show_at(float(xb.sched["out_total"]))
	await idle(3)
	var after := boxes_of(pu.part_mesh.mesh)
	var moved: float = absf((after[2] as AABB).position.y - (before[2] as AABB).position.y)
	ok(moved >= 10.0 * Part.MM, tag + " 3 VIEW screw moved %.1f mm at the end of out" % (moved / Part.MM))
	var cam_ok: bool = xb.cam_frames.size() >= 3
	var mw := 0.0
	var mh := 0.0
	for f in xb.cam_frames:
		mw = maxf(mw, float(f["share_w"]))
		mh = maxf(mh, float(f["share_h"]))
	cam_ok = cam_ok and mw <= 0.9 and mh <= 0.9
	await idle(3)
	var live: Dictionary = FrameFacts.serve(m, {})
	var lw := float(live["scene"].get("share_w", -1.0))
	var lh := float(live["scene"].get("share_h", -1.0))
	var last: Dictionary = xb.cam_frames[-1]
	ok(absf(lw - float(last["share_w"])) <= 0.02 and absf(lh - float(last["share_h"])) <= 0.02, tag + " 4 CAMERA the live camera shows what the solver said at the end of out: live %.3f x %.3f, solver %.3f x %.3f" % [lw, lh, float(last["share_w"]), float(last["share_h"])])
	ok(cam_ok, tag + " 4 CAMERA %d frames, widest share %.2f tallest %.2f" % [xb.cam_frames.size(), mw, mh])
	if tag == "w1280":
		xb.cam_share = 0.22
		xb.make(Vector3.UP, 10.0, false, true, 0.4, 0.15)
		var total: float = xb.sched["total"]
		var imgs: Array = []
		for i in 8:
			xb.show_at(total * float(i) / 7.0)
			await idle(3)
			imgs.append(root.get_texture().get_image())
		var w := 260
		var h := 260
		var strip := Image.create(w * 4, h * 2, false, Image.FORMAT_RGBA8)
		for i in 8:
			var im: Image = imgs[i]
			im.convert(Image.FORMAT_RGBA8)
			im = im.get_region(Rect2i(500, 220, 280, 280))
			im.resize(w, h, Image.INTERPOLATE_BILINEAR)
			strip.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((i % 4) * w, int(i / 4) * h))
		DirAccess.make_dir_recursive_absolute(SHOT)
		strip.save_png(SHOT + "/strip.png")
		ok(FileAccess.file_exists(SHOT + "/strip.png") and total >= 1.6 and total <= 2.4, tag + " 5 STRIP saved, run %.2f s" % total)
	xb.show_at(float(xb.sched["out_total"]))
	await shot(tag + "_exploded")
	xb.put_back()
	await idle(3)
	var back := boxes_of(pu.part_mesh.mesh)
	var same := back.size() == before.size()
	for i in back.size():
		same = same and (back[i] as AABB).is_equal_approx(before[i])
	ok(same, tag + " 3 VIEW Put back restores the bodies")


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
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRT))
	ss.dirs_override = [DIRT]
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(6)
	if not Part.available():
		print("FAIL: no KineCAD DLL")
		quit(1)
		return
	pu.set_on(false)
	pu.m.S.part = {}
	await process_frame
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	await run_at(Vector2i(1280, 720), "w1280")
	await run_at(Vector2i(1024, 600), "w1024")
	await run_at(Vector2i(1920, 1080), "w1920")
	print("FAILS ", fails)
	quit(1 if fails > 0 else 0)
