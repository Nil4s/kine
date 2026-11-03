extends SceneTree
## C10 PRINT HONESTY (complaints #371, #365, #296). Bars written BEFORE any number was read:
##   K1 the metric table M2..M10 (C10Print.SCREW_FIT): every size has close < normal < loose; normal M3..M6 = 3.4 / 4.5 / 5.5 / 6.6 (typed here from ISO 273),
##      M8 normal 9.0, M2 close 2.2, M10 loose 12.0
##   K2 Cut a hole, real clicks at 1280 x 720: usual M4 = the 4.5 mm hole it always cut (control: the default did not change); Fit close 4.3, normal 4.5,
##      loose 4.8 (volume taken from the plate within 3 % of a cylinder + counterbore ring computed here); the Fit chip alone adds no undo step; a Fit press with
##      the hole on screen replaces it in ONE undo step; M8 (head 13 x 8) loose 10.0 and close 8.4; Fit back to usual = M8 normal 9.0; M2 hole 2.4 normal (head 3.8 x 2)
##   K3 minimum layer time: a 10 x 10 x 100 mm tower (vol 1e-5 m3, skin 4.2e-3 m2) is slowed by 30..70 min; a 100 mm cube by 0 (the note is "" and the
##      size label of the 18 x 6 x 2 cm plate has no such note); the note names "minimum layer time"
##   K4 export read-back: a part exported to STL and to 3MF re-reads with volume and box within 0.01 % (not off); the same STL with every coordinate scaled
##      1.001 (volume +0.3 %, size +0.1 %) is NOT off, scaled 1.003 (volume +0.9 %) IS off with "not the part" in its words; a 3-byte file reads ok=false;
##      MeshExport.export_part returns "verify"
##   K5 the Fit chip and its panel are inside 1280 x 720
const SHOT := "C:/Users/Nick/tools/kine_workers/out/c10"
const DIRT := "user://c10_test"
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


func drag_pts(pts: Array) -> void:
	await ev_move(pts[0], false)
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i])
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func labels(n: Node, out: Array) -> void:
	if n is Label and (n as Label).is_visible_in_tree():
		out.append((n as Label).text)
	for c in n.get_children():
		labels(c, out)


func solid() -> Dictionary:
	return Part.replay(m.S.part)


func vol_mm3(s: Dictionary) -> float:
	return float(s.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


## the volume a screw hole takes out of a plate T mm deep: a clearance cylinder through it + the counterbore ring for the head
func want_mm3(clear_mm: float, head_mm: float, head_h: float, T: float) -> float:
	var r := clear_mm / 2.0
	var R := head_mm / 2.0
	return PI * r * r * T + PI * (R * R - r * r) * head_h


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
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	var pu = m.bld.part
	await click_ctl(pu.easy_open_btn)
	await idle(10)
	var ep = pu.ep
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 35.0
	m.yaw = 30.0
	m._cam()
	await idle(60)

	# the plate: a box on the grid (18 cm x 6 cm), Pull it up (2 cm)
	await click_ctl(ep.make_btns["draw"])
	await drag_pts([scr(Vector3(-0.09, 0.0, -0.03)), scr(Vector3(0.09, 0.0, 0.03))])
	await click_ctl(ep.make_btns["draw"])
	await click_ctl(ep.make_btns["pull"])
	await idle(10)
	var s1 := solid()
	var v1 := vol_mm3(s1)
	var bb1: AABB = s1["aabb"]
	var T := bb1.size.z / Part.MM   # the plate's depth in mm, from the built result
	ok(int(s1["bodies"]) == 1 and v1 > 1000.0, "plate: one body, volume %.0f mm3, depth %.1f mm" % [v1, T])

	# K2: Cut a hole
	await click_ctl(ep.make_btns["hole"])
	await idle(10)
	var fb: Button = ep.hole_box.find_child("easypart_hole_fit", true, false) as Button
	ok(fb != null and fb.is_visible_in_tree() and fb.text.find("usual") >= 0, "K2a the Fit chip is on the panel and says usual [%s]" % ("none" if fb == null else fb.text))
	var n0: int = m.undo.size()
	await click_ctl(fb)
	ok(m.undo.size() == n0, "K2b the Fit chip alone adds no undo step")
	await click_ctl(fb)
	await click_ctl(fb)
	await click_ctl(fb)   # close, normal, loose, usual
	ok(fb.text.find("usual") >= 0, "K2c four presses in all are back at usual [%s]" % fb.text)
	await click_ctl(ep.hole_btns["screw4"])
	var u1: int = m.undo.size()
	var rem := v1 - vol_mm3(solid())
	var w45 := want_mm3(4.5, 7.0, 4.0, T)
	ok(absf(rem - w45) < 0.03 * w45, "K2d usual M4 is still the 4.5 mm hole: lost %.1f mm3, want %.1f" % [rem, w45])
	for pair in [["close", 4.3], ["normal", 4.5], ["loose", 4.8]]:
		await click_ctl(fb)
		var r2 := v1 - vol_mm3(solid())
		var w2 := want_mm3(float(pair[1]), 7.0, 4.0, T)
		ok(fb.text.find(String(pair[0])) >= 0 and absf(r2 - w2) < 0.03 * w2 and int(solid()["bodies"]) == 1, "K2e M4 %s: lost %.1f mm3, want %.1f (%s mm)" % [pair[0], r2, w2, pair[1]])
	ok(m.undo.size() == u1 + 3, "K2f each Fit press replaced the hole in one undo step (%d -> %d)" % [u1, m.undo.size()])
	await shot("fit_loose_m4")
	ok(ep.hole_btns.has("screw8") and ep.hole_btns.has("screw2") and ep.hole_btns.has("screw10"), "K2g M2, M8 and M10 chips exist")
	if T > 9.0 and ep.hole_btns.has("screw8"):
		await click_ctl(ep.hole_btns["screw8"])
		var r8 := v1 - vol_mm3(solid())
		var w8 := want_mm3(10.0, 13.0, 8.0, T)
		ok(absf(r8 - w8) < 0.03 * w8, "K2h M8 loose: lost %.1f mm3, want %.1f (10.0 mm, head 13 x 8)" % [r8, w8])
		await click_ctl(fb)   # usual
		await click_ctl(fb)   # close
		var r8c := v1 - vol_mm3(solid())
		var w8c := want_mm3(8.4, 13.0, 8.0, T)
		ok(absf(r8c - w8c) < 0.03 * w8c, "K2i M8 close: lost %.1f mm3, want %.1f (8.4 mm)" % [r8c, w8c])
		await click_ctl(fb)
		await click_ctl(fb)
		await click_ctl(fb)   # normal, loose, usual
		var r8n := v1 - vol_mm3(solid())
		var w8n := want_mm3(9.0, 13.0, 8.0, T)
		ok(fb.text.find("usual") >= 0 and absf(r8n - w8n) < 0.03 * w8n, "K2j M8 usual: lost %.1f mm3, want %.1f (9.0 mm)" % [r8n, w8n])
		await click_ctl(ep.hole_btns["screw2"])
		var r2n := v1 - vol_mm3(solid())
		var w2n := want_mm3(2.4, 3.8, 2.0, T)
		ok(absf(r2n - w2n) < 0.03 * w2n, "K2k M2 usual: lost %.1f mm3, want %.1f (2.4 mm, head 3.8 x 2)" % [r2n, w2n])
	else:
		ok(false, "K2h plate too thin for M8 (%.1f mm)" % T)
	var lab := []
	labels(ep.size_l.get_parent(), lab)
	var sl := " ".join(lab)
	ok(sl.find("to print") >= 0 and sl.find("minimum layer time") < 0, "K3c the plate (18 x 6 x 2 cm) label has no layer-time note: [%s]" % sl)
	var win := Rect2(Vector2.ZERO, Vector2(1280, 720))
	ok(win.encloses(fb.get_global_rect()) and win.encloses(ep.hole_box.get_global_rect()), "K5 Fit chip %s and panel %s inside 1280 x 720" % [fb.get_global_rect(), ep.hole_box.get_global_rect()])
	await shot("panel")

	# K1 table
	var tb: Dictionary = C10Print.SCREW_FIT
	var allx := true
	for d in [2, 3, 4, 5, 6, 8, 10]:
		var a: Array = tb.get(d, [])
		allx = allx and a.size() == 3 and a[0] < a[1] and a[1] < a[2]
	ok(allx, "K1a M2 M3 M4 M5 M6 M8 M10 each have close < normal < loose")
	ok(tb[3][1] == 3.4 and tb[4][1] == 4.5 and tb[5][1] == 5.5 and tb[6][1] == 6.6 and tb[8][1] == 9.0 and tb[2][0] == 2.2 and tb[10][2] == 12.0, "K1b the ISO 273 anchors")
	ok(C10Print.clear(8, "loose") == 10.0, "K1c clear(8, loose) = 10.0")

	# K3 layer time
	var tw := C10Print.slow_minutes(1.0e-5, 4.2e-3, 0.1)
	var cu := C10Print.slow_minutes(1.0e-3, 0.06, 0.1)
	ok(tw >= 30 and tw <= 70, "K3a a 10 x 10 x 100 mm tower is slowed by %d min (want 30..70)" % tw)
	ok(cu == 0 and C10Print.layer_note(1.0e-3, 0.06, 0.1) == "", "K3b a 100 mm cube is not slowed (%d min)" % cu)
	ok(C10Print.layer_note(1.0e-5, 4.2e-3, 0.1).find("minimum layer time") >= 0, "K3d the tower's words name the minimum layer time")

	# K4 read-back
	var rec: Dictionary = m.S.part
	var dir := ProjectSettings.globalize_path(DIRT)
	var bo := MeshExport.bodies_of(rec)
	var bodies: Array = bo["bodies"]
	var rs := MeshExport.export_part(rec, "stl", DIRT, 0)
	var r3 := MeshExport.export_part(rec, "3mf", DIRT, 0)
	var vs: Dictionary = rs.get("verify", {})
	var v3: Dictionary = r3.get("verify", {})
	ok(bool(rs["ok"]) and not vs.is_empty() and bool(vs["ok"]) and not bool(vs["off"]) and float(vs["vol_pct"]) < 0.01 and float(vs["size_pct"]) < 0.01, "K4a STL read back matches (vol %s %%, size %s %%)" % [vs.get("vol_pct"), vs.get("size_pct")])
	ok(bool(r3["ok"]) and not v3.is_empty() and bool(v3["ok"]) and not bool(v3["off"]) and float(v3["vol_pct"]) < 0.01 and float(v3["size_pct"]) < 0.01, "K4b 3MF read back matches (vol %s %%, size %s %%)" % [v3.get("vol_pct"), v3.get("size_pct")])
	ok(String(rs["text"]).find("not the part") < 0, "K4c a matching export says nothing about it")
	for pair in [[1.001, false], [1.003, true]]:
		var f := FileAccess.open(String(rs["path"]), FileAccess.READ)
		var buf := f.get_buffer(f.get_length())
		f.close()
		var n := buf.decode_u32(80)
		for k in n:
			for jv in 9:
				var o := 84 + k * 50 + 12 + jv * 4
				buf.encode_float(o, buf.decode_float(o) * float(pair[0]))
		var bad := dir + "/bad.stl"
		var fw := FileAccess.open(bad, FileAccess.WRITE)
		fw.store_buffer(buf)
		fw.close()
		var vr := C10Print.verify_file(bad, "stl", bodies)
		ok(bool(vr["ok"]) and bool(vr["off"]) == bool(pair[1]) and (not bool(pair[1]) or String(vr["text"]).find("not the part") >= 0), "K4d every coordinate scaled %s: off=%s, vol %.2f %%, size %.2f %%" % [pair[0], vr["off"], vr["vol_pct"], vr["size_pct"]])
	var tiny := dir + "/tiny.stl"
	var ft := FileAccess.open(tiny, FileAccess.WRITE)
	ft.store_buffer(PackedByteArray([1, 2, 3]))
	ft.close()
	ok(not bool(C10Print.verify_file(tiny, "stl", bodies)["ok"]), "K4e a 3-byte file reads ok=false")
	print("c10: %d fail" % fails)
	quit(1 if fails > 0 else 0)
