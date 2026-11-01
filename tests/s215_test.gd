extends SceneTree
## godot --position 4000,4000 -s tests/s215_test.gd   (Friday plan 215: Parts > Pipes > Pipe through points: a tube swept along points placed in 3D, smooth bends; scripts/easy_pipes.gd, scripts/build/part_pipe3d.gd; needs the CAD DLL v5)
## Bars (real clicks at 1280 x 720; the points are typed into the X Y Z box and added with the button, or picked with a click on the part). Measured from the BUILT result.
##   1 PAGE    the point box, Add point, Pick on the part, Make the pipe, Clear points are on the 1280 x 720 screen
##   2 POINTS  four non-coplanar points typed: the list shows 4 points (the points really are not coplanar: triple product measured)
##   3 PIPE    Make the pipe (solid rod 25 mm): ONE undo step, ONE solid, volume within 2 pct of pi r^2 L (L = legs + bend arcs, from the points)
##   4 ENDS    both ends are flat caps of radius r standing square to the first / last leg at the first / last point (mesh measured)
##   5 SMOOTH  the pipe is longer than a chord-less cut: its volume is above pi r^2 x (the chord length minus the bend savings - 2 pct), and one body
##   6 WALL    a hollow pipe (wall 1.9 mm) through the same points: one solid, volume within 2 pct of pi (ro^2 - ri^2) L
##   7 PICK    Pick on the part: a click on a corner of the pipe adds the point of that corner (within 0.5 mm of the mesh vertex)
##   8 UNDO    one Undo takes the wall pipe away (bodies back to 1 and the volume back to the rod's)
##   9 TOOSHORT legs too short for the bend: no step added, the words say why
## Shots: C:/Temp/claude/s215/page.png (the page with 4 points), pipe.png (the rod), wall.png
var fails := 0
var m: Node
const SHOT := "C:/Temp/claude/s215"
const DIRT := "user://s215_test"
var pu: PartUI
var ep
const PTS := [[0.0, 30.0, 0.0], [150.0, 30.0, 0.0], [150.0, 130.0, 100.0], [0.0, 180.0, 200.0]]


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
	await idle(3)


func click_ctl(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func ctl(nm: String) -> Button:
	return root.find_child(nm, true, false) as Button


## all mesh vertices of the part, in mm
func verts() -> PackedVector3Array:
	var out := PackedVector3Array()
	for f in Part.body_faces(m.S.part):
		for v in (f as PackedVector3Array):
			out.append(v * 1000.0)
	return out


func vol_mm3() -> float:
	return float(pu.res.get("volume", 0.0)) * 1e9


func bodies() -> int:
	return int(pu.res.get("bodies", 0))


## the centre line length (mm) from the points and the bend radius rb: the legs between the arcs plus the arcs (worked out here, not read from the code)
func centre_len(pts: Array, rb: float) -> float:
	var P: Array = []
	for q in pts:
		P.append(Vector3(q[0], q[1], q[2]))
	var L := 0.0
	for i in range(1, P.size()):
		L += (P[i] - P[i - 1]).length()
	for i in range(1, P.size() - 1):
		var u: Vector3 = (P[i] - P[i - 1]).normalized()
		var w: Vector3 = (P[i + 1] - P[i]).normalized()
		var th := acos(u.dot(w))
		L -= 2.0 * rb * tan(th * 0.5) - rb * th
	return L


## "" when the cap at p (mm) square to dir is a flat disc of radius r that reaches nothing past p; else what it measured
func cap_check(vs: PackedVector3Array, p: Vector3, dir: Vector3, r: float) -> String:
	var n_rim := 0
	var worst_plane := 0.0
	var nearest := 1e9
	for v in vs:
		var d := v.distance_to(p)
		nearest = minf(nearest, d)
		if absf(d - r) <= 0.1:
			n_rim += 1
			worst_plane = maxf(worst_plane, absf((v - p).dot(dir)))
	if n_rim >= 8 and worst_plane <= 0.1 and nearest >= r - 0.1:
		return ""
	return "%d rim vertices, off the cap plane by %.3f mm, nearest vertex %.3f (radius %.2f)" % [n_rim, worst_plane, nearest, r]


func type_point(q: Array) -> void:
	var le := root.find_child("easypart_p3_xyz", true, false) as LineEdit
	le.text = "%s %s %s" % [str(q[0]), str(q[1]), str(q[2])]
	await click_ctl(ctl("easypart_p3_add"))


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
		print("FAIL: no KineCAD DLL, the pipe cannot run")
		quit(1)
		return
	pu = m.bld.part
	await click_ctl(pu.part_btn)
	await click_ctl(pu.easy_open_btn)
	await idle(4)
	ep = pu.ep
	await click_ctl(ctl("easypart_chip_parts"))
	await click_ctl(ctl("easypart_lib_Pipes"))
	await idle(3)
	var vp := Rect2(Vector2.ZERO, Vector2(1280, 720))
	var names := ["easypart_p3_xyz", "easypart_p3_add", "easypart_p3_pick", "easypart_p3_make", "easypart_p3_clear", "easypart_p3_width", "easypart_p3_wall", "easypart_p3_bend"]
	for nm in names:
		var c := root.find_child(nm, true, false) as Control
		if c != null:
			ep._scroll_into_view(c)
	await idle(4)
	var off := []
	for nm in names:
		var c2 := root.find_child(nm, true, false) as Control
		if c2 == null or not c2.is_visible_in_tree() or not vp.encloses(c2.get_global_rect()):
			off.append(nm)
	ok(off.is_empty(), "1 the Pipe through points controls are on the 1280 x 720 screen (off or missing: %s)" % str(off))
	# 2 POINTS
	for q in PTS:
		await type_point(q)
	var lst := root.find_child("easypart_p3_list", true, false) as Label
	var a := Vector3(PTS[1][0] - PTS[0][0], PTS[1][1] - PTS[0][1], PTS[1][2] - PTS[0][2])
	var b := Vector3(PTS[2][0] - PTS[0][0], PTS[2][1] - PTS[0][1], PTS[2][2] - PTS[0][2])
	var c3 := Vector3(PTS[3][0] - PTS[0][0], PTS[3][1] - PTS[0][1], PTS[3][2] - PTS[0][2])
	var trip := absf(a.cross(b).dot(c3))
	ok(lst.text.contains("4:") and not lst.text.contains("5:") and trip > 100000.0, "2 four typed points listed (triple product %.0f mm3, so not in one plane): %s" % [trip, lst.text])
	await shot("page")
	# 3 PIPE: solid rod, width 25 (r 12.5), bend 1.5 x width = 37.5
	await click_ctl(ctl("easypart_p3_wall"))   # 1.9 mm wall -> double
	await click_ctl(ctl("easypart_p3_wall"))   # -> Solid
	ok(ctl("easypart_p3_wall").text == "Solid", "3 the Wall chip reads Solid after two presses (%s)" % ctl("easypart_p3_wall").text)
	var r := 12.5
	var rb := 37.5
	var ub0: int = m.undo.size()
	await click_ctl(ctl("easypart_p3_make"))
	await idle(4)
	var L := centre_len(PTS, rb)
	var want := PI * r * r * L
	var have := vol_mm3()
	ok(m.undo.size() == ub0 + 1 and bodies() == 1 and absf(have - want) <= 0.02 * want, "3 the rod: one undo step (%d -> %d), %d solid, volume %.0f vs pi r^2 L %.0f mm3 (L %.1f mm), off %.2f pct" % [ub0, m.undo.size(), bodies(), have, want, L, 100.0 * (have - want) / want])
	var vs := verts()
	var d0 := Vector3(PTS[1][0] - PTS[0][0], PTS[1][1] - PTS[0][1], PTS[1][2] - PTS[0][2]).normalized()
	var d3 := Vector3(PTS[3][0] - PTS[2][0], PTS[3][1] - PTS[2][1], PTS[3][2] - PTS[2][2]).normalized()
	var cap0 := cap_check(vs, Vector3(PTS[0][0], PTS[0][1], PTS[0][2]), d0, r)
	var cap1 := cap_check(vs, Vector3(PTS[3][0], PTS[3][1], PTS[3][2]), d3, r)
	ok(cap0 == "" and cap1 == "", "4 the pipe ends at the first and the last point as flat caps [%s] [%s]" % [cap0, cap1])
	var chord := 0.0
	for i in range(1, PTS.size()):
		chord += (Vector3(PTS[i][0], PTS[i][1], PTS[i][2]) - Vector3(PTS[i - 1][0], PTS[i - 1][1], PTS[i - 1][2])).length()
	ok(have < PI * r * r * chord and have > PI * r * r * (chord - 40.0), "5 the bends cut the corners: volume %.0f is under the sharp-corner pipe %.0f and over it minus 40 mm of pipe %.0f" % [have, PI * r * r * chord, PI * r * r * (chord - 40.0)])
	await shot("pipe")
	# 7 PICK (before the wall pipe so the rod is the only body): click a pipe vertex that is on screen, away from the panel
	var best := Vector3.ZERO
	var best_d := 1e9
	var cen := Vector2(500, 360)
	for v in vs:
		var w := v * 0.001
		if m.cam.is_position_behind(w):
			continue
		var sp: Vector2 = m.cam.unproject_position(w)
		if not vp.grow(-40.0).has_point(sp) or ep._over_ui(sp):
			continue
		var dd := sp.distance_to(cen)
		if dd < best_d:
			best_d = dd
			best = v
	await click_ctl(ctl("easypart_p3_clear"))
	await click_ctl(ctl("easypart_p3_pick"))
	var sp2: Vector2 = m.cam.unproject_position(best * 0.001)
	await click_at(sp2)
	var pp: Array = root.find_child("easypart_p3_list", true, false).get_parent().get_children()
	var got_pts: Array = ep.pipes_box.p3_pts
	var near := 1e9
	if got_pts.size() == 1:
		near = (got_pts[0] as Vector3).distance_to(best)
	ok(got_pts.size() == 1 and near <= 0.5, "7 Pick on the part: a click on a pipe corner adds that point (%d points, %.3f mm from the mesh vertex %s)" % [got_pts.size(), near, str(best)])
	# 6 WALL: the hollow pipe through the same points (typed again)
	await click_ctl(ctl("easypart_p3_clear"))
	for q in PTS:
		await type_point(q)
	await click_ctl(ctl("easypart_p3_wall"))   # Solid -> the PVC wall (1.9 mm)
	var ub1: int = m.undo.size()
	var vol_rod := have
	await click_ctl(ctl("easypart_p3_make"))
	await idle(4)
	var ri := r - 1.9
	var wantw := PI * (r * r - ri * ri) * L
	var vol_all := vol_mm3()
	# the second pipe sits exactly on the first one, so the part's volume stays the rod's; measure the wall pipe alone
	ok(m.undo.size() == ub1 + 1, "6 the hollow pipe is one undo step (%d -> %d)" % [ub1, m.undo.size()])
	var fs: Array = m.S.part["features"]
	var solo := {"features": [fs[0].duplicate(true)], "seq": 1}
	var f2: Dictionary = (fs[1] as Dictionary).duplicate(true)
	f2["op"] = "new"
	var res2 := Part.replay({"features": [f2], "seq": 1, "name": "w"})
	var vw := float(res2["volume"]) * 1e9
	ok(int(res2["bodies"]) == 1 and absf(vw - wantw) <= 0.02 * wantw, "6 the hollow pipe alone: %d solid, volume %.0f vs pi (ro^2 - ri^2) L %.0f mm3, off %.2f pct (wall 1.9 mm)" % [int(res2["bodies"]), vw, wantw, 100.0 * (vw - wantw) / wantw])
	await shot("wall")
	# 8 UNDO
	m._undo()
	await idle(4)
	ok(bodies() == 1 and absf(vol_mm3() - vol_rod) <= 0.001 * vol_rod and (m.S.part["features"] as Array).size() == 1, "8 one Undo takes the second pipe away: %d step(s) left, volume %.0f (the rod %.0f)" % [(m.S.part["features"] as Array).size(), vol_mm3(), vol_rod])
	# 9 TOOSHORT: legs of 20 mm cannot bend a 25 mm pipe
	await click_ctl(ctl("easypart_p3_clear"))
	for q in [[0.0, 300.0, 0.0], [20.0, 300.0, 0.0], [20.0, 320.0, 0.0], [40.0, 320.0, 20.0]]:
		await type_point(q)
	var n_f: int = (m.S.part["features"] as Array).size()
	var ub2: int = m.undo.size()
	await click_ctl(ctl("easypart_p3_make"))
	var said := String(ep.msg)
	ok((m.S.part["features"] as Array).size() == n_f and m.undo.size() == ub2 and said.contains("too short"), "9 legs too short for the bend: no step added, the words say: %s" % said)
	print("s215: %d fail" % fails)
	quit(1 if fails > 0 else 0)
