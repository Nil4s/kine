extends SceneTree
## godot --path . --position 4000,4000 -s tests/s033_test.gd     (FRIDAY 33: TEXT ON A FACE, Easy Part > Parts > Type it; needs the CAD DLL)
## A 60 x 30 x 10 mm box (a sketch and a pull in the record), then REAL clicks on the Text rows: type KINE, Cut in / Stand out, depth, On the top / Pick a face.
## Measured from the BUILT result (kernel volume, mesh, bounding box), never from the code's own variables:
##   1 ENGRAVE   KINE cut 1 mm into the top: volume drops by > 0, by less than 30 pct of face area x depth, and by the letters' area (read back from the
##               sketch lines in the record) x depth within 3 pct; ONE solid, a closed mesh; ONE undo step; the box is not taller
##   2 UNDO      one Undo brings back the plain box (volume to 0.01 pct)
##   3 EMBOSS    Stand out 1 mm: the top of the box rises by the depth within 0.05 mm, volume rises by the letters' area x depth within 3 pct, one solid, closed, ONE undo step
##   4 PICK      Pick a face + a real click on the top: the same engraving as bar 1 (one undo step); on the front face: embossed toward +Z by the depth
##   5 REFUSE    empty words: nothing changes, no undo step
## Shots: C:/Temp/claude/s033/engrave.png, emboss.png, front.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s033"
const DIRT := "user://s033_test"
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


func click_at(p: Vector2) -> void:
	await ev_move(p, false)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(4)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


## the camera straight above the part, close: the letters fill the shot
func close_top() -> void:
	var bb: AABB = pu.res["aabb"]
	var ang: Array = ep.VIEW_ANGLES["top"]
	m._turn_to(float(ang[0]), float(ang[1]), 0.1, bb.get_center(), false)
	await idle(30)


func find(nm: String) -> Control:
	return root.find_child(nm, true, false) as Control


## volume mm3, solids, bounding box (mm), from the last replay
func meas() -> Dictionary:
	var bb: AABB = pu.res.get("aabb", AABB())
	return {"vol": float(pu.res.get("volume", 0.0)) * 1e9, "bodies": int(pu.res.get("bodies", 0)), "top": bb.end.y * 1000.0, "zmax": bb.end.z * 1000.0, "zmin": bb.position.z * 1000.0}


## the area (mm2) of the letters in a sketch: the polygon the line entities make (shoelace over each closed loop of the record)
func ink_area(sk: Dictionary) -> float:
	var total := 0.0
	for g in Part.loops_of(sk["ents"]):
		var s := 0.0
		for e in g:
			var a := Part.v2(e["a"])
			var b := Part.v2(e["b"])
			s += a.x * b.y - b.x * a.y
		total += absf(s) * 0.5
	return total


func newest(t: String) -> Dictionary:
	var out := {}
	for f in m.S.part.get("features", []):
		if String(f["t"]) == t:
			out = f
	return out


## true when the mesh is closed: every edge (welded to 1 nm) is used by exactly two triangles
func closed_mesh() -> bool:
	var edges := {}
	for fa in Part.body_faces(m.S.part):
		var t: PackedVector3Array = fa
		for k in range(0, t.size() - 2, 3):
			var ids := []
			for j in 3:
				ids.append("%d,%d,%d" % [roundi(t[k + j].x * 1e6), roundi(t[k + j].y * 1e6), roundi(t[k + j].z * 1e6)])
			for j in 3:
				var a: String = ids[j]
				var b: String = ids[(j + 1) % 3]
				if a == b:
					continue
				var key := a + "|" + b if a < b else b + "|" + a
				edges[key] = int(edges.get(key, 0)) + 1
	var odd := 0
	for k in edges:
		if int(edges[k]) != 2:
			odd += 1
	if odd > 0:
		print("     (open or non-manifold mesh edges: %d of %d)" % [odd, edges.size()])
	return odd == 0


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
		print("FAIL: no KineCAD DLL, the text cannot run")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	# the box: 60 x 30 x 10 mm on the floor (a sketch on the top plane and a pull up), set up in the record
	var rec: Dictionary = pu._ensure()
	rec["features"].append(Part.new_feature(rec, "sketch", {"plane": "top", "ents": [{"k": "rect", "a": [-30.0, -15.0], "b": [30.0, 15.0]}], "dims": []}))
	rec["features"].append(Part.new_feature(rec, "extrude", {"sketch": "f1", "dist": 10.0, "both": false, "op": "new"}))
	pu.upto = -1
	pu.sync()
	ep.frame()
	await idle(6)
	var box := meas()
	ok(absf(float(box["vol"]) - 18000.0) < 1.0 and int(box["bodies"]) == 1 and absf(float(box["top"]) - 10.0) < 0.05, "0 the starting box is 60 x 30 x 10 mm: %.1f mm3, top %.2f mm" % [float(box["vol"]), float(box["top"])])
	# the Text rows: Parts > Type it
	await click_ctl(find("easypart_chip_parts"))
	await click_ctl(find("easypart_lib_Type it"))
	await idle(3)
	var tb := find("easypart_text_box")
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var onscreen := tb != null and tb.is_visible_in_tree() and vp.encloses(tb.get_global_rect())
	for nm in ["easypart_text_edit", "easypart_text_cut", "easypart_text_out", "easypart_text_depth", "easypart_text_top", "easypart_text_face"]:
		var c := find(nm)
		onscreen = onscreen and c != null and c.is_visible_in_tree() and vp.encloses(c.get_global_rect())
	ok(onscreen, "0 the Text on a face rows are on the 1280 x 720 screen (Parts > Type it)")
	ep.text_edit.text = "KINE"
	ep.text_depth.value = 1.0
	var top_btn := find("easypart_text_top") as Button
	var face_area := 60.0 * 30.0
	# 1 ENGRAVE
	await click_ctl(find("easypart_text_cut"))
	var u0: int = m.undo.size()
	await click_ctl(top_btn)
	await idle(4)
	var eg := meas()
	var drop := float(box["vol"]) - float(eg["vol"])
	var ink := ink_area(newest("sketch"))
	var cl := closed_mesh()
	print("     msg: ", ep.msg); print("     engrave: drop %.2f mm3, letters %.2f mm2 x 1 mm, face %.0f mm2, bodies %d" % [drop, ink, face_area, int(eg["bodies"])])
	ok(drop > 0.0 and drop < 0.3 * face_area * 1.0, "1 engraving KINE 1 mm: volume drops by %.2f mm3 (> 0 and < 30 pct of face area x depth = %.0f)" % [drop, 0.3 * face_area])
	ok(ink > 20.0 and absf(drop - ink * 1.0) <= 0.03 * ink, "1 the drop matches the letters' area x depth: %.2f vs %.2f mm3 (3 pct)" % [drop, ink])
	ok(int(eg["bodies"]) == 1 and cl, "1 still ONE closed solid (%d solids, closed mesh %s)" % [int(eg["bodies"]), str(cl)])
	ok(m.undo.size() == u0 + 1 and absf(float(eg["top"]) - 10.0) < 0.05, "1 ONE undo step (%d -> %d), the box is not taller (top %.2f mm)" % [u0, m.undo.size(), float(eg["top"])])
	await close_top()
	await shot("engrave")
	# 2 UNDO
	m._undo()
	await idle(4)
	var ub := meas()
	ok(absf(float(ub["vol"]) - float(box["vol"])) <= 1e-4 * float(box["vol"]) and m.undo.size() == u0 and (m.S.part["features"] as Array).size() == 2, "2 one Undo brings back the plain box (%.2f mm3, %d steps)" % [float(ub["vol"]), (m.S.part["features"] as Array).size()])
	# 3 EMBOSS
	await click_ctl(find("easypart_text_out"))
	var u1: int = m.undo.size()
	await click_ctl(top_btn)
	await idle(4)
	var eb := meas()
	var gain := float(eb["vol"]) - float(box["vol"])
	var ink2 := ink_area(newest("sketch"))
	var cl2 := closed_mesh()
	print("     emboss: gain %.2f mm3, letters %.2f mm2, top %.3f mm" % [gain, ink2, float(eb["top"])])
	ok(absf(float(eb["top"]) - 11.0) <= 0.05, "3 embossing 1 mm raises the top of the box to %.3f mm (11.00 +- 0.05)" % float(eb["top"]))
	ok(ink2 > 20.0 and absf(gain - ink2) <= 0.03 * ink2, "3 the volume gain matches the letters' area x depth: %.2f vs %.2f mm3" % [gain, ink2])
	ok(int(eb["bodies"]) == 1 and cl2 and m.undo.size() == u1 + 1, "3 still ONE closed solid (%d), ONE undo step (%d -> %d)" % [int(eb["bodies"]), u1, m.undo.size()])
	await close_top()
	await shot("emboss")
	m._undo()
	await idle(4)
	ep._view_press("iso")   # back to the corner view (the front face is seen again)
	await idle(30)
	# 4 PICK a face: arm, then a REAL click on the top face
	ep.text_depth.value = 1.0
	await click_ctl(find("easypart_text_cut"))
	await click_ctl(find("easypart_text_face"))
	var bb: AABB = pu.res["aabb"]
	var topc: Vector2 = m.cam.unproject_position(Vector3(bb.get_center().x, bb.end.y, bb.get_center().z))
	var u2: int = m.undo.size()
	await click_at(topc)
	await idle(4)
	var pk := meas()
	var drop2 := float(box["vol"]) - float(pk["vol"])
	ok(absf(drop2 - drop) <= 0.01 * drop and m.undo.size() == u2 + 1 and int(pk["bodies"]) == 1, "4 Pick a face + a click on the top engraves the same: drop %.2f vs %.2f mm3, one undo step (%d -> %d)" % [drop2, drop, u2, m.undo.size()])
	m._undo()
	await idle(4)
	# the front face (+Z): stand out toward +Z
	await click_ctl(find("easypart_text_out"))
	await click_ctl(find("easypart_text_face"))
	bb = pu.res["aabb"]
	var fr := Vector3(bb.get_center().x, bb.get_center().y, bb.end.z)
	var frc: Vector2 = m.cam.unproject_position(fr)
	var u3: int = m.undo.size()
	var z0 := float(meas()["zmax"])
	await click_at(frc)
	await idle(4)
	var fm := meas()
	ok(absf(float(fm["zmax"]) - z0 - 1.0) <= 0.05 and int(fm["bodies"]) == 1 and m.undo.size() == u3 + 1, "4 on the front face the words stand out toward +Z by 1 mm: %.3f -> %.3f, one undo step" % [z0, float(fm["zmax"])])
	await shot("front")
	m._undo()
	await idle(4)
	# 5 REFUSE
	ep.text_edit.text = "   "
	var u4: int = m.undo.size()
	var v4 := float(meas()["vol"])
	await click_ctl(top_btn)
	ok(m.undo.size() == u4 and absf(float(meas()["vol"]) - v4) < 1e-6, "5 empty words: nothing changes, no undo step [%s]" % String(ep.msg))
	print("s033: %d fail" % fails)
	quit(1 if fails > 0 else 0)
