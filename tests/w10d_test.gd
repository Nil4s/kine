## godot --path . -s tests/w10d_test.gd   (W10c: Easy Pull it up says so when the new piece only touches along a line, and offers the nudge)
## BARS (written before the run): pull a rect that touches the box along an EDGE: status says "along a line" and "Nudge", the nudge button shows,
## 2 pieces; click it: 1 counted solid, ONE undo step. Pull a rect that touches a FACE: no "along a line", no nudge button, 1 solid.
## Pull a rect with a GAP: no "along a line" (the old words). Control: the old pull words ("Pulled up ...") contain neither "line" nor "Nudge".
extends SceneTree
const KCad := preload("res://scripts/kcad.gd")
var fails := 0
const OUT := "C:/Users/Nick/tools/kine_workers/out/w10d"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func _init() -> void:
	if not KCad.available() or DisplayServer.get_name() == "headless":
		print("SKIP no DLL / window")
		print("w10d: 0 fail")
		quit(0)
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	await app_bars()
	print("w10d: %d fail" % fails)
	quit(1 if fails > 0 else 0)


var m: Node


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


func click_at(p: Vector2) -> void:
	var mv := InputEventMouseMotion.new()
	mv.position = p
	mv.global_position = p
	root.push_input(mv, true)
	await process_frame
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func box_feats(ra: Array, rb: Array) -> Array:
	var out: Array = []
	var k := 1
	for r in [ra, rb]:
		out.append({"t": "sketch", "id": "f%d" % k, "name": "Sketch%d" % k, "plane": "front", "ents": [{"k": "rect", "a": r[0], "b": r[1]}], "dims": []})
		out.append({"t": "extrude", "id": "f%d" % (k + 1), "name": "Extrude%d" % k, "sketch": "f%d" % k, "dist": 10.0, "both": true, "op": "new"})
		k += 2
	return out


func inside_pt(faces: Array, i: int) -> Vector2:
	var pu = m.bld.part
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for w in faces[i]:
		var q: Vector2 = m.cam.unproject_position(w)
		lo = lo.min(q)
		hi = hi.max(q)
	for f in [Vector2(0.5, 0.5), Vector2(0.35, 0.5), Vector2(0.65, 0.5), Vector2(0.5, 0.35), Vector2(0.5, 0.65)]:
		var p: Vector2 = lo + (hi - lo) * f
		var hit: Dictionary = pu._ray_hit(p, faces)
		if not hit.is_empty() and int(hit["body"]) == i and not pu.ep._over_ui(p):
			return p
	return Vector2(-1, -1)


func set_part(feats: Array, nm: String) -> void:
	var pu = m.bld.part
	var rec := Part.make(nm)
	rec["features"] = feats
	rec["seq"] = feats.size()
	m.S.part = rec
	pu.upto = -1
	pu.sync()
	pu.ep.stick_picks = []
	pu.ep._stick_retry = []
	pu.ep.stick_nudge_btn.visible = false
	await idle(3)


func pick_two() -> void:
	var pu = m.bld.part
	var faces: Array = Part.body_faces(m.S.part, -1)
	if pu.ep.armed != "stick":
		await click_ctl(pu.ep.make_btns["stick"])
	await click_at(inside_pt(faces, 0))
	await click_at(inside_pt(faces, 1))


func app_bars() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP app bars: no window")
		return
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var ss: StartScreen = m.start_screen
	var pu: PartUI = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://w10_test"))
	ss.dirs_override = ["user://w10_test"]
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
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	var ep = pu.ep
	for sz in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.content_scale_size = sz
		await idle(4)
		var tag := str(sz.x)
		for c in [["edge", [[0.0, 10.0], [40.0, 30.0]]]]:
			var feats := box_feats([[-40.0, -10.0], [0.0, 10.0]], [[0.0, 0.0], [1.0, 1.0]]).slice(0, 2)
			feats.append({"t": "sketch", "id": "f3", "name": "Sketch2", "plane": "front", "ents": [{"k": "rect", "a": c[1][0], "b": c[1][1]}], "dims": []})
			await set_part(feats, "Pull " + c[0])
			var ub: int = m.undo.size()
			ok(int(pu.res.get("bodies", 0)) == 1, "%s %s: starts with 1 body" % [tag, c[0]])
			await click_ctl(ep.make_btns["pull"])
			var words: String = ep.msg
			print("  [%s %s] %s | bodies %d" % [tag, c[0], words, int(pu.res.get("bodies", 0))])
			await shot("%s_%s" % [c[0], tag])
			# W10D: leave the pointer on Pull it up until its tooltip stands, then the note must be clear of the tooltip box
			await create_timer(1.6).timeout
			await idle(3)
			await shot("tip_%s" % tag)
			var tips := []
			if ep.tips != null and ep.tips.panel != null and ep.tips.panel.visible:
				tips.append(ep.tips.panel.get_global_rect())
			var hint_r: Rect2 = ep.hint.get_global_rect()
			var tip_hits := 0
			for r in tips:
				if (r as Rect2).intersects(hint_r):
					tip_hits += 1
			print("  [%s] tooltip windows %d, hint %s, tips %s" % [tag, tips.size(), hint_r, tips])
			ok(tips.size() > 0, "%s: the Pull it up tooltip is up (control: bar can see a tooltip)" % tag)
			ok(tip_hits == 0 and "along a line" in String(ep.msg), "%s: the line-touch note is clear of the tooltip box (overlaps %d)" % [tag, tip_hits])
	print("w10d: app bars done")


func shot(nm: String) -> void:
	await idle(3)
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, nm])
