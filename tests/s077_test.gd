extends SceneTree
## s077 (Friday plan 77): Electronics boards. Parts > Boards lists Arduino Uno R3 (68.6 x 53.3, four 3.2 mm holes), ESP32 51 x 28 and DevKitC 55 x 28
## (no mounting holes on those boards: four support posts), Raspberry Pi 4B (85 x 56, four 2.7 mm holes on a 58 x 49 grid). One click makes a box with
## standoffs at the datasheet holes and openings for the ports on the right walls; Wall and Gap sliders (each its own undo step). Real clicks at 1280 x 720.
## Every bar is measured from the built mesh with ray casts: holes found and their diameter (bar 0.1 mm), standoff centres (bar 0.05 mm),
## every port opening lets a ray out through the wall, the board outline + gap fits the inside, a slider move changes the wall measured from the mesh.
## shots: C:/Temp/claude/s077/

const SHOT_DIR := "C:/Temp/claude/s077"
const DIRT := "user://s077_test"

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


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(3)


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT_DIR, nm])


func pu():
	return m.bld.part


## the replay volume in mm3
func vol() -> float:
	return float(pu().res.get("volume", 0.0)) / (Part.MM * Part.MM * Part.MM)


## the built bounding box in mm
func bbox() -> AABB:
	var b: AABB = pu().res.get("aabb", AABB())
	return AABB(b.position / Part.MM, b.size / Part.MM)


func build_errors() -> int:
	return (pu().res.get("errors", {}) as Dictionary).size()


## the built mesh's triangles in world metres
var _tc := PackedVector3Array()
var _tc_on := false


func cache() -> void:
	_tc = world_tris_raw()
	_tc_on = true


func world_tris() -> PackedVector3Array:
	return _tc if _tc_on else world_tris_raw()


func world_tris_raw() -> PackedVector3Array:
	var out := PackedVector3Array()
	var mi: MeshInstance3D = pu().part_mesh
	if mi == null or mi.mesh == null:
		return out
	var t := mi.global_transform
	for s in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(s)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix = arr[Mesh.ARRAY_INDEX]
		if ix == null or (ix as PackedInt32Array).is_empty():
			for v in vs:
				out.append(t * v)
		else:
			for i in ix:
				out.append(t * vs[i])
	return out


## every hit distance (mm, sorted, hits closer than 0.05 mm merged) of a ray from o (mm) along unit d through the built mesh (Moller-Trumbore)
func ray_all(o_mm: Vector3, d: Vector3) -> Array:
	var o := o_mm * Part.MM
	var tris := world_tris()
	var hits: Array = []
	for k in range(0, tris.size() - 2, 3):
		var a := tris[k]
		var e1 := tris[k + 1] - a
		var e2 := tris[k + 2] - a
		var p := d.cross(e2)
		var det := e1.dot(p)
		if absf(det) < 1e-12:
			continue
		var s := o - a
		var u := s.dot(p) / det
		if u < 0.0 or u > 1.0:
			continue
		var q := s.cross(e1)
		var v := d.dot(q) / det
		if v < 0.0 or u + v > 1.0:
			continue
		var tt := e2.dot(q) / det
		if tt > 1e-6:
			hits.append(tt / Part.MM)
	hits.sort()
	var out: Array = []
	for h in hits:
		if out.is_empty() or float(h) - float(out[-1]) > 0.05:
			out.append(h)
	return out


## the nearest hit distance (mm) of a ray from o (mm) along d, or NAN when nothing is hit
func ray_first(o_mm: Vector3, d: Vector3) -> float:
	var h := ray_all(o_mm, d)
	return float(h[0]) if not h.is_empty() else NAN




func slider_row(key: String) -> Dictionary:
	for r in pu().ep.rows:
		if String(r.get("key", "")) == key:
			return r
	return {}


## a REAL click on the slider's track at the share f (0..1) of its width: press, release
func click_slider(row: Dictionary, f: float) -> void:
	var s: HSlider = row["slider"]
	var sc := root.find_child("easypart_panel_scroll", true, false) as ScrollContainer
	if sc != null:
		sc.ensure_control_visible(s)   # a user scrolls the panel down to the sliders
		await idle(4)
		sc.ensure_control_visible(s)
		await idle(4)
	var rc := s.get_global_rect()
	var p := Vector2(rc.position.x + rc.size.x * f, rc.position.y + rc.size.y * 0.5)
	await ev_move(p)
	await ev_mouse(p, true)
	await ev_mouse(p, false)
	await idle(6)


## the edge of a hole by bisection: a ray down at c + dir * r (mm) along 'axis' (0 = x, 2 = z) - from the middle (a miss) outwards to a hit
func hole_edge(c: Vector3, axis: int, sgn: float, ytop: float) -> float:
	var lo := 0.0   # a miss
	var hi := 2.9   # a hit (the standoff, r 3)
	for k in 14:
		var mid := 0.5 * (lo + hi)
		var o := c
		o.y = ytop
		if axis == 0:
			o.x += sgn * mid
		else:
			o.z += sgn * mid
		if ray_all(o, Vector3.DOWN).is_empty():
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)


## the box's footprint and the hole centres for a board at the wall w and gap g (mm), from the datasheet numbers
func hole_world(t: String, w: float, g: float) -> Array:
	var out := []
	for h in PartTemplates.BC_BOARDS[t]["holes"]:
		out.append(Vector2(w + g + float(h[0]), w + g + float(h[1])))
	return out


## the first hit of a ray from a point inside the box out through a wall, all hits (empty = escapes)
func escape(o: Vector3, d: Vector3) -> Array:
	return ray_all(o, d)


func check_board(t: String, tag: String, ytop: float) -> void:
	var b: Dictionary = PartTemplates.BC_BOARDS[t]
	var pr: Dictionary = (m.S.part["easy"] as Dictionary)["p"]
	var w: float = pr["wall"]
	var g: float = pr["clear"]
	var dm := PartTemplates.bc_dims(t, pr)
	var stand: float = dm["stand"]
	cache()
	ok(build_errors() == 0 and int(pu().res.get("bodies", 0)) == 2, "%s built: two bodies (box and lid), no build error (bodies %d, errors %d)" % [tag, int(pu().res.get("bodies", 0)), build_errors()])
	var bb := bbox()
	ok(absf(bb.size.y - float(dm["h"])) <= 0.3 and absf(bb.size.z - float(dm["zo"])) <= 0.3 and absf(bb.size.x - (2.0 * float(dm["lo"]) + 10.0)) <= 0.3,
		"%s bbox %.1f x %.1f x %.1f (want %.1f x %.1f x %.1f)" % [tag, bb.size.x, bb.size.y, bb.size.z, 2.0 * float(dm["lo"]) + 10.0, dm["h"], dm["zo"]])
	# standoffs: centre and diameter counted from the mesh by ray casts
	var hw := hole_world(t, w, g)
	var hd: float = b["hd"]
	var found := 0
	var worst_c := 0.0
	var worst_d := 0.0
	var tops_ok := 0
	for hp in hw:
		var c := Vector3(hp.x, 0.0, hp.y)
		if hd > 0.0:
			var miss := ray_all(Vector3(c.x, ytop, c.z), Vector3.DOWN).is_empty()
			if not miss:
				continue
			found += 1
			var ex1 := hole_edge(c, 0, 1.0, ytop)
			var ex0 := hole_edge(c, 0, -1.0, ytop)
			var ez1 := hole_edge(c, 2, 1.0, ytop)
			var ez0 := hole_edge(c, 2, -1.0, ytop)
			worst_d = maxf(worst_d, maxf(absf((ex0 + ex1) - hd), absf((ez0 + ez1) - hd)))
			worst_c = maxf(worst_c, maxf(absf(0.5 * (ex1 - ex0)), absf(0.5 * (ez1 - ez0))))
			var top := ray_first(Vector3(c.x + 2.2, ytop, c.z), Vector3.DOWN)
			if absf((ytop - top) - stand) <= 0.1:
				tops_ok += 1
		else:
			# a post without a hole: its top at 'stand'; its edges found by a ray down stepping out from the centre
			var top := ray_first(Vector3(c.x, ytop, c.z), Vector3.DOWN)
			if absf((ytop - top) - stand) <= 0.1:
				tops_ok += 1
				found += 1
				var lo := 0.0
				var hi := 5.0
				for k in 14:
					var mid := 0.5 * (lo + hi)
					var tt := ray_first(Vector3(c.x + mid, ytop, c.z), Vector3.DOWN)
					if not is_nan(tt) and absf((ytop - tt) - stand) <= 0.1:
						lo = mid
					else:
						hi = mid
				worst_d = maxf(worst_d, absf(2.0 * 0.5 * (lo + hi) - 6.0))
				var l2 := 0.0
				var h2 := 5.0
				for k in 14:
					var mid := 0.5 * (l2 + h2)
					var tt := ray_first(Vector3(c.x - mid, ytop, c.z), Vector3.DOWN)
					if not is_nan(tt) and absf((ytop - tt) - stand) <= 0.1:
						l2 = mid
					else:
						h2 = mid
				worst_c = maxf(worst_c, absf(0.5 * (lo - l2)))
	if hd > 0.0:
		ok(found == 4 and worst_d <= 0.1, "%s holes: %d of 4 found by rays, diameter off the datasheet %.3f mm (bar 0.1, hole %.1f)" % [tag, found, worst_d, hd])
	else:
		ok(found == 4 and worst_d <= 0.1, "%s posts (the board has no mounting holes): %d of 4 found by rays, 6 mm across within %.3f" % [tag, found, worst_d])
	ok(worst_c <= 0.05 and tops_ok == 4, "%s standoff centres within %.3f mm of the datasheet coordinates (bar 0.05); %d of 4 tops at %.1f mm" % [tag, worst_c, tops_ok, stand])
	# ports: a ray from inside through each port centre escapes; a ray at the same wall above the port hits the wall once
	var y0: float = stand + PartTemplates.BC_PCB
	var inset: float = dm["inset"]
	var lo_x: float = dm["lo"]
	var n_ok := 0
	var n_all := 0
	var n_wall_ok := 0
	for pt in b["ports"]:
		n_all += 1
		var ym: float = y0 + 0.5 * (float(pt["y0"]) + float(pt["y1"]))
		var am: float = inset + 0.5 * (float(pt["a"]) + float(pt["b"]))
		var o: Vector3
		var d: Vector3
		var o2: Vector3
		match String(pt["w"]):
			"+x":
				o = Vector3(lo_x - w - 0.5, ym, am)
				d = Vector3.RIGHT
				o2 = Vector3(lo_x - w - 0.5, y0 + float(pt["y1"]) + 0.5 + 0.8, am)
			"-x":
				o = Vector3(w + 0.5, ym, am)
				d = Vector3.LEFT
				o2 = Vector3(w + 0.5, y0 + float(pt["y1"]) + 0.5 + 0.8, am)
			_:
				o = Vector3(am, ym, w + 0.5)
				d = Vector3.FORWARD
				o2 = Vector3(am, y0 + float(pt["y1"]) + 0.5 + 0.8, w + 0.5)
		var esc: Array = escape(o, d)
		var above: Array = escape(o2, d)
		if esc.is_empty():
			n_ok += 1
		if above.size() == 2 and absf((float(above[1]) - float(above[0])) - w) <= 0.1:
			n_wall_ok += 1
		else:
			print("   (wall above %s: %s)" % [String(pt["n"]), str(above)])
	ok(n_ok == n_all and n_all > 0, "%s ports: %d of %d openings let a ray from the inside out through the wall at the port centre" % [tag, n_ok, n_all])
	ok(n_wall_ok == n_all, "%s the wall above each port is solid: %d of %d rays cross a wall of the set thickness" % [tag, n_wall_ok, n_all])
	# the inner box and the board outline with its gap
	var zp: float = 24.0 if t == "bc_pi4" else (9.0 if t != "bc_uno" else 25.0)
	var yp: float = stand + 2.0
	var cx: float = 0.5 * lo_x
	var hr := ray_first(Vector3(cx, yp, zp), Vector3.RIGHT)
	var hl := ray_first(Vector3(cx, yp, zp), Vector3.LEFT)
	var inner_x := hr + hl
	var xp: float = 60.0 if t == "bc_pi4" else 45.0 if t == "bc_uno" else 30.0
	var hb := ray_first(Vector3(xp, yp, 0.5 * float(dm["zo"])), Vector3.BACK)
	var hf := ray_first(Vector3(xp, yp, 0.5 * float(dm["zo"])), Vector3.FORWARD)
	var inner_z := hb + hf
	ok(absf(inner_x - (float(b["L"]) + 2.0 * g)) <= 0.1 and absf(inner_z - (float(b["W"]) + 2.0 * g)) <= 0.1,
		"%s the board outline %.1f x %.1f fits the inside %.2f x %.2f with %.1f mm all round (inside = board + 2 x gap within 0.1)" % [tag, b["L"], b["W"], inner_x, inner_z, g])


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
		print("s077: 1 fail")
		quit(1)
		return
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3.ZERO
	m.pitch = -35.0
	m.yaw = 25.0
	m._cam()
	await idle(60)

	var parts: Button = root.find_child("easypart_chip_parts", true, false) as Button
	if parts != null:
		await click_ctl(parts)
	var boards: Button = root.find_child("easypart_lib_Boards", true, false) as Button
	if boards != null:
		await click_ctl(boards)
	await idle(10)
	var chips := {}
	var all_vis := boards != null
	for t in PartTemplates.BC_ORDER:
		chips[t] = root.find_child("easypart_bcase_" + String(t), true, false) as Button
		if chips[t] == null or not (chips[t] as Button).is_visible_in_tree():
			all_vis = false
	ok(all_vis, "0 Parts > Boards lists Arduino Uno R3, ESP32 51 x 28, ESP32 DevKitC 55 x 28, Raspberry Pi 4B")
	await shot("00_boards_page")
	var vp := root.get_visible_rect()
	var inside := true
	for t in chips:
		var rc := (chips[t] as Button).get_global_rect()
		if rc.position.y < 0.0 or rc.end.y > vp.size.y or rc.end.x > vp.size.x:
			inside = false
	ok(inside, "0b the four chips are inside the 1280 x 720 window (no scrolling needed to click them)")

	# ---- Arduino Uno R3
	var u0: int = m.undo.size()
	await click_ctl(chips["bc_uno"])
	await shot("01_uno_box")
	ok(m.undo.size() == u0 + 1, "1 the Uno pick is one undo step (undo %d -> %d)" % [u0, m.undo.size()])
	var dm: Dictionary = PartTemplates.bc_dims("bc_uno", (m.S.part["easy"] as Dictionary)["p"])
	check_board("bc_uno", "Uno", float(dm["h"]) + 6.0)

	# ---- sliders on the Uno: Wall, then Gap, each its own undo step
	var rw := slider_row("wall")
	var rg := slider_row("clear")
	ok(not rw.is_empty() and not rg.is_empty(), "2 the panel has a Wall slider and a Gap slider")
	var wall_before := wall_at(25.0 if true else 0.0)
	var uw: int = m.undo.size()
	await click_slider(rw, 0.8)
	cache()
	var sv: float = (rw["slider"] as HSlider).value
	var pw: float = float(((m.S.part["easy"] as Dictionary)["p"] as Dictionary)["wall"])
	var wall_after := wall_at(25.0)
	ok(absf(wall_after - pw) <= 0.1 and absf(wall_after - wall_before) >= 0.4 and absf(sv - pw) <= 0.01,
		"3 Wall slider: the wall measured from the mesh went %.2f -> %.2f mm (slider reads %.1f, record %.1f)" % [wall_before, wall_after, sv, pw])
	ok(m.undo.size() == uw + 1, "3b the Wall move is one undo step (undo %d -> %d)" % [uw, m.undo.size()])
	await shot("02_uno_wall")
	var ug: int = m.undo.size()
	var rg2 := slider_row("clear")
	await click_slider(rg2, 0.7)
	cache()
	var pg: float = float(((m.S.part["easy"] as Dictionary)["p"] as Dictionary)["clear"])
	ok(absf(pg - 1.0) >= 0.4 and m.undo.size() == ug + 1, "4 Gap slider: gap %.1f mm (was 1.0), one undo step (undo %d -> %d)" % [pg, ug, m.undo.size()])
	var dm2: Dictionary = PartTemplates.bc_dims("bc_uno", (m.S.part["easy"] as Dictionary)["p"])
	check_board("bc_uno", "Uno after Wall and Gap", float(dm2["h"]) + 6.0)
	await shot("03_uno_gap")
	m._undo()
	await idle(10)
	m._undo()
	await idle(10)
	var pw2: float = float(((m.S.part["easy"] as Dictionary)["p"] as Dictionary)["wall"])
	cache()
	ok(absf(pw2 - 3.0) <= 0.01 and absf(wall_at(25.0) - 3.0) <= 0.1, "5 two undos bring the wall back to %.1f mm (mesh %.2f)" % [pw2, wall_at(25.0)])

	# ---- the other boards
	for t in ["bc_esp51", "bc_esp55", "bc_pi4"]:
		var bu0: int = m.undo.size()
		await click_ctl(chips[t])
		await shot("04_" + String(t))
		var d3 := PartTemplates.bc_dims(t, (m.S.part["easy"] as Dictionary)["p"])
		check_board(t, String(PartTemplates.BC_BOARDS[t]["name"]), float(d3["h"]) + 6.0)
		ok(m.undo.size() == bu0 + 1, "%s pick is one undo step (undo %d -> %d)" % [String(PartTemplates.BC_BOARDS[t]["name"]), bu0, m.undo.size()])

	print("s077: %d fail" % fails)
	quit(fails)


## the wall thickness measured from the mesh: a ray from outside along +z at x = 45 (clear of every port and standoff), height 12 mm: the
## second hit minus the first
func wall_at(xp: float) -> float:
	var h := ray_all(Vector3(xp if xp > 30.0 else 45.0, 12.0, -10.0), Vector3.BACK)
	if h.size() < 2:
		return NAN
	return float(h[1]) - float(h[0])
