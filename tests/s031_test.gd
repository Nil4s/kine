extends SceneTree
## s031 (Friday plan 31): Thread look on a hole. Crate, Cut a hole (made 6 mm wide with the Hole size slider), the Thread look chip. A helix is drawn
## in the bore (a visual only); the instruction sheet and the checklist say "M6 thread: tap it or use a heat-set insert". Every number is measured
## from the drawn mesh's vertices and the built solid (mm), never from the code's own variables.
##   0 CHIP    the Thread look chip is on the hole chips row
##   1 SIZE    the bore measured on the solid is 6 mm across (5.5 .. 6.5)
##   2 RADIUS  every drawn vertex lies between bore/2 and bore/2 + 0.6 x pitch from the axis (bore measured on the solid)
##   3 PITCH   the pitch fitted to the helix (axial advance per turn) = the ISO coarse pitch of the nearest M size (M6 = 1.0 mm), within 2 %
##   4 SAME    the exported STL: volume, triangle count AND the file bytes identical with and without the look
##   5 SHEET   the instruction sheet has the line "M6 thread ... tap it or use a heat-set insert"; the Export checklist has it too
##   6 UNDO    each press is one undo step; undo takes the helix away, redo brings it back
const SHOT := "C:/Temp/claude/s031"
const DIRT := "user://s031_test"
const ISO := [[3, 0.5], [4, 0.7], [5, 0.8], [6, 1.0], [8, 1.25], [10, 1.5], [12, 1.75]]
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


func ev_move(p: Vector2, held := false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	if held:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)
	await process_frame


func click_ctl(c: Control) -> void:
	if c == null:
		fails += 1
		print("FAIL a control to click is missing")
		return
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


func ep():
	return pu().ep


func scr(w: Vector3) -> Vector2:
	return m.cam.unproject_position(w)


func drag_pts(pts: Array) -> void:
	await ev_move(pts[0])
	await ev_mouse(pts[0], true)
	for i in range(1, pts.size()):
		await ev_move(pts[i], true)
	await ev_mouse(pts[pts.size() - 1], false)
	await idle(3)


func find_named(n: Node, nm: String) -> Node:
	if n.name == nm:
		return n
	for c in n.get_children():
		var f := find_named(c, nm)
		if f != null:
			return f
	return null


func slide_to(sl: HSlider, v: float) -> void:
	var g := float(sl.get_theme_icon("grabber").get_width()) if sl.get_theme_icon("grabber") != null else 16.0
	var frac := (v - sl.min_value) / (sl.max_value - sl.min_value)
	var lx := g * 0.5 + frac * (sl.size.x - g)
	var p := sl.get_global_rect().position + Vector2(lx, sl.size.y * 0.5)
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_move(p, true)
	await ev_mouse(p, false)
	await idle(12)


## the drawn helix's vertices (engine units), empty when nothing is drawn
func thread_pts() -> PackedVector3Array:
	var tl := pu().part_mesh.get_node_or_null("thread_look") as MeshInstance3D
	if tl == null or not tl.visible or tl.mesh == null:
		return PackedVector3Array()
	return tl.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func solid_pts() -> Array:
	var out := []
	var mesh: ArrayMesh = pu().res.get("mesh")
	if mesh == null:
		return out
	for s in mesh.get_surface_count():
		for v in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			out.append(v * 1000.0)
	return out


func stl_info(rec: Dictionary, tag: String) -> Dictionary:
	var r := MeshExport.export_part(rec, "stl", DIRT + "/" + tag)
	var bytes := FileAccess.get_file_as_bytes(String(r["path"])) if bool(r["ok"]) else PackedByteArray()
	var vol := 0.0
	if bool(r["ok"]):
		var bo := MeshExport.bodies_of(rec)
		for b in bo["bodies"]:
			vol += MeshExport.signed_volume(b)
	return {"ok": r["ok"], "tris": int((r["report"] as Dictionary).get("tris", -1)), "n": (bytes.size() - 84) / 50, "vol": vol, "bytes": bytes}


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
	PartSheet.dir = DIRT + "/sheets"
	if not Part.available():
		print("FAIL: no KineCAD DLL, the test cannot run")
		quit(1)
		return
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3(0.0, 0.01, 0.0)
	m.pitch = 40.0
	m.yaw = 25.0
	m._cam()
	await idle(60)
	await click_ctl(ep().make_btns["draw"])
	await click_ctl(ep().shape_btns["box"])
	await drag_pts([scr(Vector3(-0.02, 0.0, -0.02)), scr(Vector3(0.02, 0.0, 0.02))])
	await click_ctl(ep().make_btns["pull"])
	await idle(10)
	await slide_to(find_named(m, "easypart_slider_last") as HSlider, 3.0)
	await click_ctl(ep().make_btns["hole"])
	await idle(10)
	# the Hole size slider: as small as it goes (6 mm across)
	var sl := find_named(m, "easypart_slider_last") as HSlider
	if sl != null:
		await slide_to(sl, sl.min_value)
	var hole_json := JSON.stringify(m.S.part)

	var chip := ep().hole_box.find_child("easypart_hole_thread", true, false) as Button
	ok(chip != null and chip.is_visible_in_tree(), "0 CHIP the Thread look chip is on the hole chips row (%s)" % ("visible" if chip != null and chip.is_visible_in_tree() else "missing"))
	await shot("hole_chips")

	var vol0 := float(pu().res.get("volume", 0.0))
	var pre := stl_info(m.S.part, "plain")
	var undo0: int = m.undo.size()
	if chip != null and chip.is_visible_in_tree():
		await click_ctl(chip)
	await idle(10)
	var undo1: int = m.undo.size()
	var pts := thread_pts()
	var rec_on := JSON.stringify(m.S.part)

	# axis: the longest side of the drawn points; centre: the middle of the other two
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var ax := 0
	for k in 3:
		if (hi - lo)[k] > (hi - lo)[ax]:
			ax = k
	var a0 := (ax + 1) % 3
	var a1 := (ax + 2) % 3
	var c0 := (lo[a0] + hi[a0]) * 0.5
	var c1 := (lo[a1] + hi[a1]) * 0.5
	var bore_r := INF
	for q in solid_pts():
		var d := Vector2(q[a0] - c0 * 1000.0, q[a1] - c1 * 1000.0).length()
		if d > 0.5:
			bore_r = minf(bore_r, d)
	var bore_d := 2.0 * bore_r
	ok(bore_d >= 5.5 and bore_d <= 6.5, "1 SIZE the bore measured on the solid is %.2f mm across" % bore_d)

	var want_p := -1.0
	var want_m := -1
	var best := INF
	for t in ISO:
		if absf(float(t[0]) - bore_d) < best:
			best = absf(float(t[0]) - bore_d)
			want_p = float(t[1])
			want_m = int(t[0])

	# 2 radius of every drawn vertex
	var rmin := INF
	var rmax := -INF
	for p in pts:
		var d := Vector2(p[a0] - c0, p[a1] - c1).length() * 1000.0
		rmin = minf(rmin, d)
		rmax = maxf(rmax, d)
	ok(pts.size() >= 48 and rmin >= bore_r - 1e-3 and rmax <= bore_r + 0.6 * want_p + 1e-3,
		"2 RADIUS %d vertices, radius %.3f .. %.3f mm; allowed %.3f .. %.3f (bore/2 .. bore/2 + 0.6 x %.2f)" % [pts.size(), rmin, rmax, bore_r, bore_r + 0.6 * want_p, want_p])

	# 3 pitch: a least-squares line of the axis position on the unwrapped angle (axial advance per turn)
	var th: Array = []
	var zz: Array = []
	var prev := 0.0
	var acc := 0.0
	for i in range(0, pts.size(), 2):
		var p := pts[i]
		var a := atan2(p[a1] - c1, p[a0] - c0)
		if i == 0:
			acc = a
		else:
			acc += fposmod(a - prev + PI, TAU) - PI
		prev = a
		th.append(acc)
		zz.append(p[ax] * 1000.0)
	var mt := 0.0
	var mz := 0.0
	for i in th.size():
		mt += th[i]
		mz += zz[i]
	mt /= maxf(th.size(), 1)
	mz /= maxf(th.size(), 1)
	var sxy := 0.0
	var sxx := 0.0
	for i in th.size():
		sxy += (th[i] - mt) * (zz[i] - mz)
		sxx += (th[i] - mt) * (th[i] - mt)
	var pitch := absf(sxy / maxf(sxx, 1e-12)) * TAU
	var turns: float = (float(th[-1]) - float(th[0])) / TAU if th.size() > 1 else 0.0
	ok(want_m == 6 and absf(pitch - 1.0) <= 0.02 and absf(pitch - want_p) <= 0.02 * want_p and absf(turns) >= 10.0,
		"3 PITCH helix pitch %.4f mm over %.1f turns; nearest size M%d, ISO pitch %.2f mm (M6 = 1.0 within 2 pct)" % [pitch, turns, want_m, want_p])

	# 4 the export is the same with and without the look
	var post := stl_info(m.S.part, "threaded")
	var vol1 := float(pu().res.get("volume", 0.0))
	ok(bool(pre["ok"]) and bool(post["ok"]) and int(pre["tris"]) > 0 and int(pre["tris"]) == int(post["tris"]) and int(pre["n"]) == int(post["n"]) and absf(float(pre["vol"]) - float(post["vol"])) <= 1e-9 and pre["bytes"] == post["bytes"] and absf(vol0 - vol1) <= 1e-12,
		"4 SAME STL: %d vs %d triangles, volume %.6f vs %.6f, bytes %s, replay volume %.6f vs %.6f cm3" % [int(pre["tris"]), int(post["tris"]), float(pre["vol"]), float(post["vol"]), "identical" if pre["bytes"] == post["bytes"] else "DIFFER", vol0 * 1e6, vol1 * 1e6])

	# 5 the instruction sheet (a real click on its button) and the checklist
	await shot("threaded")
	var sheet_btn := find_named(m, "easypart_sheet") as Button
	m.last_shell = ""
	if sheet_btn != null:
		await click_ctl(sheet_btn)
		await idle(60)
	var path := String(m.last_shell)
	var html := FileAccess.get_file_as_string(path) if path != "" else ""
	var chk := ""
	for l in MeshExport.check_lines(m.S.part):
		chk += String(l) + "\n"
	ok(html.find("M6 thread") >= 0 and html.find("tap it or use a heat-set insert") >= 0 and chk.find("M6 thread") >= 0 and chk.find("heat-set insert") >= 0,
		"5 SHEET sheet has M6 thread line: %s; checklist has it: %s" % [html.find("M6 thread") >= 0, chk.find("M6 thread") >= 0])

	# 6 undo steps
	ok(undo1 == undo0 + 1 and rec_on != hole_json, "6a ONE STEP the press is one undo step (%d -> %d)" % [undo0, undo1])
	m._undo()
	await idle(10)
	ok(thread_pts().size() == 0 and JSON.stringify(m.S.part) == hole_json, "6b UNDO the helix is gone after one undo (%d vertices)" % thread_pts().size())
	m._redo()
	await idle(10)
	ok(thread_pts().size() == pts.size(), "6c REDO the helix is back (%d vertices, was %d)" % [thread_pts().size(), pts.size()])
	var n2: int = m.undo.size()
	var chip2 := ep().hole_box.find_child("easypart_hole_thread", true, false) as Button
	await click_ctl(chip2)
	await idle(10)
	ok(thread_pts().size() == 0 and m.undo.size() == n2 + 1, "6d OFF the second press takes the helix away in one step")
	await click_ctl(chip2)
	await idle(10)

	# a close look: down the bore
	m.pitch = 75.0
	m.yaw = 20.0
	m._cam()
	await idle(30)
	await shot("down_the_bore")
	print("s031: %d fail" % fails)
	quit(1 if fails > 0 else 0)
