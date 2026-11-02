## godot --path . -s tests/w10_test.gd     (W10: cut / join failure helper; real clicks on the panel)
## BARS (written before the run): two boxes touching at one edge: Join says "line" + offers the nudge, counted bodies 2 before the nudge
## (control: raw union is NOT 1), the nudge click gives 1 counted body; face-touching boxes join to 1; Undo after the nudge is ONE step
## back to the original 2 parts; Cut/Overlap on the edge pair say "line"; New part keeps 2; Overlap of a real overlap is the shared volume.
extends SceneTree
## APP BARS (Easy Part, real clicks, 1280 x 720 and 1920 x 1080): edge-touching boxes, Stick together -> Join: the words say 'only touch along a line',
## no step is made, the nudge button shows; one click on it: 1 solid (counted by the app's own _lumps), ONE undo step, undo gives 2 pieces.
## Face-touching boxes still join to 1 with no nudge button. Control: the same Join on the edge pair WITHOUT the nudge leaves 2 lumps in the raw kernel.

const KCad := preload("res://scripts/kcad.gd")
const JH := preload("res://scripts/build/join_helper.gd")
const UI := preload("res://scripts/build/join_helper_ui.gd")
var fails := 0
const OUT := "C:/Users/Nick/tools/kine_workers/out/w10"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func click(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	for d in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = d
		e.position = p
		e.global_position = p
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if d else 0
		root.push_input(e)
		await idle(2)


func box_at(x: float, y: float) -> int:
	return KCad.translate(KCad.box(0.01, 0.01, 0.01), Vector3(x, y, 0))


func panel(a: int, b: int, size: Vector2i) -> UI:
	root.size = size
	var p := UI.new()
	p.position = Vector2(20, 20)
	root.add_child(p)
	p.setup(a, b)
	return p


func _init() -> void:
	if not KCad.available():
		print("SKIP no KineCAD DLL")
		print("w10: 0 fail")
		quit(0)
		return
	# --- logic ---
	var a := KCad.box(0.01, 0.01, 0.01)
	var e := box_at(0.01, 0.01)
	var f := box_at(0.01, 0.0)
	var raw := KCad.union(a, e)
	ok(JH.lumps(raw) == 2, "control: the raw union of the edge pair counts 2 lumps (the id count says 1 - the check is not vacuous)")
	ok(JH.lumps(a) == 1, "control: one box counts 1")
	ok(JH.contact(a, e)["kind"] == "line", "edge pair is a line contact")
	ok(JH.contact(a, f)["kind"] == "face", "face pair is a face contact")
	var rf := JH.run(a, f, "join")
	ok(rf["ok"] and rf["count"] == 1, "face-touching boxes join to 1 body (counted %s)" % rf["count"])
	var re := JH.run(a, e, "join")
	ok(not re["ok"] and re["nudge"] and "line" in re["message"], "edge Join refuses and says line + offers nudge: " + re["message"])
	ok(is_equal_approx(absf(re["nudge_by"].x), JH.NUDGE) and is_equal_approx(absf(re["nudge_by"].y), JH.NUDGE) and re["nudge_by"].z == 0.0, "nudge is 0.01 mm on the two touching axes only")
	ok(not JH.run(a, e, "cut")["ok"] and "line" in JH.run(a, e, "cut")["message"], "Cut on the edge pair says line")
	ok(not JH.run(a, e, "overlap")["ok"], "Overlap on the edge pair finds nothing")
	var rn := JH.run(a, e, "new")
	ok(rn["ok"] and rn["count"] == 2 and rn["bodies"].size() == 2, "New part keeps 2")
	var ov := box_at(0.005, 0.0)
	var ro := JH.run(a, ov, "overlap")
	ok(ro["ok"] and absf(KCad.volume(ro["bodies"][0]) - 0.5e-6) < 1e-9, "Overlap of a real overlap is the shared half")
	var rc := JH.run(a, ov, "cut")
	ok(rc["ok"] and absf(KCad.volume(rc["bodies"][0]) - 0.5e-6) < 1e-9, "Cut removes the overlapping half")
	# --- the Expert Combine step (replay): the same words, and nudge:true builds it ---
	var edge := box_feats([[-40.0, -10.0], [0.0, 10.0]], [[0.0, 10.0], [40.0, 30.0]])
	for op in ["join", "cut", "intersect"]:
		var rr := Part.make("E")
		rr["features"] = edge.duplicate(true) + [{"t": "combine", "id": "c1", "name": "C1", "target": 0, "tools": [1], "op": op, "keep": false}]
		var er := String(Part.replay(rr)["errors"].get("c1", ""))
		ok(er.contains("only touch along a line") and er.ends_with(JH.NUDGE_ASK), "Expert combine %s on the edge pair says: %s" % [op, er])
	var rj := Part.make("E")
	rj["features"] = edge.duplicate(true) + [{"t": "combine", "id": "c1", "name": "C1", "target": 0, "tools": [1], "op": "join", "keep": false, "nudge": true}]
	var pj := Part.replay(rj)
	ok(int(pj["bodies"]) == 1 and (pj["errors"] as Dictionary).is_empty(), "Expert combine join with nudge:true: 1 body, no error")
	var rf2 := Part.make("F")
	rf2["features"] = box_feats([[-40.0, -10.0], [0.0, 10.0]], [[0.0, -10.0], [40.0, 10.0]]) + [{"t": "combine", "id": "c1", "name": "C1", "target": 0, "tools": [1], "op": "join", "keep": false}]
	ok(int(Part.replay(rf2)["bodies"]) == 1 and (Part.replay(rf2)["errors"] as Dictionary).is_empty(), "Expert combine join of a face pair: 1 body")
	# --- real clicks, two window sizes ---
	for sz in [Vector2i(1024, 600), Vector2i(1920, 1080)]:
		var p := panel(box_at(0, 0), box_at(0.01, 0.01), sz)
		await idle(3)
		ok(p.body_count() == 2, "%s: starts with 2 bodies" % str(sz))
		await click(p.mode_btns["join"])
		ok(not p.nudge_btn.visible == false and "line" in p.status.text, "%s: Join click -> line message + nudge button shown" % str(sz))
		ok(p.history.is_empty(), "failed Join made no history entry")
		root.get_viewport().get_texture().get_image().save_png("%s/before_%d.png" % [OUT, sz.x])
		await click(p.nudge_btn)
		ok(p.parts.size() == 1 and p.body_count() == 1, "%s: nudge click -> 1 body counted (%d)" % [str(sz), p.body_count()])
		ok(p.history.size() == 1, "nudge+join is ONE history entry")
		root.get_viewport().get_texture().get_image().save_png("%s/after_%d.png" % [OUT, sz.x])
		await click(p.undo_btn)
		ok(p.parts.size() == 2 and p.history.is_empty() and p.body_count() == 2, "%s: ONE Undo returns the original 2 parts" % str(sz))
		var v := KCad.volume(p.parts[1])
		ok(absf(v - 1e-6) < 1e-12, "undo gives the un-nudged tool")
		p.queue_free()
		await idle(2)
	await app_bars()
	print("w10: %d fail" % fails)
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
		# A: face-touching: one solid, no nudge button
		await set_part(box_feats([[-40.0, -10.0], [0.0, 10.0]], [[0.0, -10.0], [40.0, 10.0]]), "Face pair")
		await pick_two()
		await click_ctl(ep.stick_btns["join"])
		ok(int(pu.res.get("bodies", 0)) == 1 and int(pu.res.get("bodies", 0)) == 1 and not ep.stick_nudge_btn.visible, "%s A: face-touching boxes: 1 solid (lumps %d), no nudge button" % [tag, int(pu.res.get("bodies", 0))])
		# B: edge-touching (x=0, y=10, along z)
		await set_part(box_feats([[-40.0, -10.0], [0.0, 10.0]], [[0.0, 10.0], [40.0, 30.0]]), "Edge pair")
		var ub: int = m.undo.size()
		ok(int(pu.res.get("bodies", 0)) == 2, "%s B control: the untouched edge pair is 2 pieces (app count %d)" % [tag, int(pu.res.get("bodies", 0))])
		await pick_two()
		await click_ctl(ep.stick_btns["join"])
		ok(ep.msg.contains("only touch along a line"), "%s B Join says where: [%s]" % [tag, ep.msg])
		ok(m.undo.size() == ub and (m.S.part["features"] as Array).size() == 4 and int(pu.res.get("bodies", 0)) == 2, "%s B the failed Join changed nothing (undo %d -> %d, 2 pieces)" % [tag, ub, m.undo.size()])
		ok(ep.stick_nudge_btn.visible and ep.stick_box.visible, "%s B the Nudge 0.01 mm button shows in the box" % tag)
		await shot("before_" + tag)
		await click_ctl(ep.stick_nudge_btn)
		ok(int(pu.res.get("bodies", 0)) == 1 and int(pu.res.get("bodies", 0)) == 1, "%s B nudge click -> 1 solid, counted by the app (bodies %d, lumps %d) [%s]" % [tag, int(pu.res.get("bodies", 0)), int(pu.res.get("bodies", 0)), ep.msg])
		var feats: Array = m.S.part["features"]
		ok(m.undo.size() == ub + 1 and String(feats[-1]["t"]) == "combine" and bool(feats[-1].get("nudge", false)), "%s B ONE undo step, a combine step with nudge:true (undo %d -> %d)" % [tag, ub, m.undo.size()])
		await shot("after_" + tag)
		m._undo()
		await idle(3)
		ok(int(pu.res.get("bodies", 0)) == 2 and int(pu.res.get("bodies", 0)) == 2 and (m.S.part["features"] as Array).size() == 4, "%s B one Undo: the 2 original pieces are back" % tag)
	print("w10: app bars done")


func shot(nm: String) -> void:
	await idle(3)
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, nm])
