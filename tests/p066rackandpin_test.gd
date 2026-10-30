extends SceneTree
## p066rackandpin (Friday plan 66: Rack and pinion; the bevel pair and worm gear come later): a beginner from the BUILDING card picks Rack
## from the Easy Part chips and sets it with real mouse drags on its sliders. A straight rack: a row of teeth along a bar. Its pinion is the
## Gear chip (a spur gear); a rack and a gear with the same Teeth size (module) mesh, because the rack's tooth pitch is pi x module, the
## same pitch a gear of that module has along its pitch circle.
## Every size below is measured from the BUILT geometry (the replayed mesh vertices, mm), not from the record or the code's variables.
## Bars (run on the old code first: the old code has no Rack chip, so bars 1 to 5 FAIL there):
##   0 the Rack chip is on the chips row
##   1 Rack: one solid; the default 12 teeth, Medium (module 2): 12 tooth tips, length = 12 x pi x 2 = 75.40 mm (+- 0.5), height 4 x module = 8 mm (+- 0.3)
##   2 Length slider: drag to about 20 teeth; the built rack has the teeth the record says (+- 1) and length = teeth x pi x 2 (+- 0.6)
##   3 Size: drag to the right end = Big teeth (module 3), pill says Big: tooth pitch = 3 pi = 9.42 mm (+- 0.05)
##   4 Size: drag to the left end = Small teeth (module 1), pill says Small: tooth pitch = pi = 3.14 mm (+- 0.05)
##   5 Thickness: drag to about 20 mm; the built solid is that thick (+- 0.3)
##   6 the words: every press says a line
## shots: C:/Temp/claude/p066rackandpin/shots/
const SHOT := "C:/Temp/claude/p066rackandpin/shots"
const DIRT := "user://p066rackandpin_test"
var fails := 0
var m: Node
var words: Array = []


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


func drag_screen(a: Vector2, b: Vector2) -> void:
	await ev_move(a, false)
	await ev_mouse(a, true)
	for i in range(1, 13):
		await ev_move(a.lerp(b, i / 12.0))
	await ev_mouse(b, false)
	await idle(3)


## a slider knob position (screen px) for a value: the track runs between the centres of the two end grabbers
func knob_x(s: HSlider, v: float) -> Vector2:
	var r := s.get_global_rect()
	var t := (v - s.min_value) / maxf(s.max_value - s.min_value, 1e-6)
	return Vector2(r.position.x + 12.0 + t * (r.size.x - 24.0), r.get_center().y)


## a real drag of a template slider from its knob to value v
func slide_to(s: HSlider, v: float) -> void:
	var a := knob_x(s, s.value)
	await drag_screen(a, knob_x(s, v))


func shot(nm: String) -> void:
	await idle(3)
	DirAccess.make_dir_recursive_absolute(SHOT)
	root.get_texture().get_image().save_png("%s/%s.png" % [SHOT, nm])


func pu():
	return m.bld.part


func note(press: String) -> void:
	words.append([press, pu().ep.msg])


func row_of(ep, key: String) -> Dictionary:
	for r in ep.rows:
		if String(r.get("key", "")) == key:
			return r
	return {}


## the built solid's vertices in mm as [along the length, across the height, through the thickness]: the thickness axis is the
## mesh's thinnest box side; the length is the longer of the other two (the rack's teeth run along it)
func built_mm(res: Dictionary) -> Array:
	var mesh: ArrayMesh = res.get("mesh")
	if mesh == null:
		return []
	var bb: AABB = mesh.get_aabb()
	var verts: Array = []
	for s in mesh.get_surface_count():
		verts.append_array(mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
	# the thickness axis is the one with only two faces' coordinates (an extrusion's front and back); the teeth make many along the others
	var ax := 0
	var best := 1 << 30
	for a in 3:
		var seen := {}
		for v in verts:
			seen[roundi(float(v[a]) * 1000.0)] = true
		if seen.size() < best:
			best = seen.size()
			ax = a
	var pa := [0, 1, 2]
	pa.erase(ax)
	var along: int = pa[0] if bb.size[pa[0]] >= bb.size[pa[1]] else pa[1]
	var across: int = pa[1] if along == pa[0] else pa[0]
	var c := bb.get_center()
	var out := []
	for v in verts:
		out.append([(float(v[along]) - float(c[along])) * 1000.0, (float(v[across]) - float(c[across])) * 1000.0, (float(v[ax]) - float(c[ax])) * 1000.0])
	return out


## the length (mm) of the built solid along the teeth
func length_of(pts: Array) -> float:
	var lo := 1e9
	var hi := -1e9
	for p in pts:
		lo = minf(lo, float(p[0]))
		hi = maxf(hi, float(p[0]))
	return hi - lo if pts.size() > 0 else 0.0


## the height (mm) of the built solid across the teeth (tip to bottom)
func height_of(pts: Array) -> float:
	var lo := 1e9
	var hi := -1e9
	for p in pts:
		lo = minf(lo, float(p[1]))
		hi = maxf(hi, float(p[1]))
	return hi - lo if pts.size() > 0 else 0.0


## the tooth tips: the teeth side of the height is the extreme with more vertices (the body's bottom has only its corners).
## Returns the tip vertices' along-positions (mm), one per distinct vertex, sorted
func tip_xs(pts: Array) -> Array:
	if pts.is_empty():
		return []
	var hi := -1e9
	var lo := 1e9
	for p in pts:
		hi = maxf(hi, float(p[1]))
		lo = minf(lo, float(p[1]))
	var n_hi := 0
	var n_lo := 0
	for p in pts:
		if absf(float(p[1]) - hi) < 0.05:
			n_hi += 1
		if absf(float(p[1]) - lo) < 0.05:
			n_lo += 1
	var side := hi if n_hi >= n_lo else lo
	var seen := {}
	for p in pts:
		if absf(float(p[1]) - side) < 0.05:
			seen[roundi(float(p[0]) * 100.0)] = float(p[0])
	var xs := seen.values()
	xs.sort()
	return xs


## the teeth count the mesh shows: two tip vertices per tooth (the tip's two corners)
func teeth_of(pts: Array) -> int:
	return tip_xs(pts).size() / 2


## the tooth pitch (mm) the mesh shows: from the first tooth's left tip to the last tooth's left tip, over the gaps between them
func pitch_of(pts: Array) -> float:
	var xs := tip_xs(pts)
	var n := teeth_of(pts)
	if n < 2:
		return 0.0
	return (float(xs[2 * (n - 1)]) - float(xs[0])) / float(n - 1)


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

	# 0 the BUILDING card, one click: an empty Easy Part
	m.build_choose.auto = true
	ss.show_screen()
	await idle(3)
	await click_ctl(ss._easy_btn["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(30)
	m.target = Vector3.ZERO
	m.pitch = -25.0
	m.yaw = 20.0
	m._cam()
	await idle(60)
	var ep = pu().ep
	var rack_chip: Button = ep.chips.get("rack") if ep.chips.has("rack") else null
	ok(rack_chip != null and rack_chip.is_visible_in_tree(), "0 the Rack chip is on the Easy Part chips row (chips: %s)" % str(ep.chips.keys()))

	# 1 Rack: one click on the chip makes the default rack (12 teeth, Medium = module 2)
	if rack_chip != null:
		await click_ctl(rack_chip)
	await idle(10)
	await shot("00_rack")
	note("rack chip")
	var pts := built_mm(pu().res)
	var n := teeth_of(pts)
	var L := length_of(pts)
	var H := height_of(pts)
	ok(int(pu().res.get("bodies", 0)) == 1 and n == 12 and absf(L - 12.0 * PI * 2.0) < 0.5 and absf(H - 8.0) < 0.3,
		"1 Rack: one solid, %d tooth tips (want 12), length %.2f mm (want %.2f), height %.2f mm (want 8.00) [%s]" % [n, L, 12.0 * PI * 2.0, H, ep.msg])

	# 2 Length: a real drag on the Teeth slider to about 20 teeth
	var st: HSlider = row_of(ep, "teeth").get("slider")
	if st != null:
		await slide_to(st, 20.0)
	await idle(10)
	await shot("01_teeth")
	note("teeth")
	n = int(pu()._rec().get("easy", {}).get("p", {}).get("teeth", 0))
	pts = built_mm(pu().res)
	var n_mesh := teeth_of(pts)
	L = length_of(pts)
	ok(st != null and absi(n - 20) <= 1 and absi(n_mesh - n) == 0 and absf(L - float(n_mesh) * PI * 2.0) < 0.6,
		"2 Teeth dragged to %d (record), %d tooth tips in the mesh, length %.2f mm (want %.2f) [%s]" % [n, n_mesh, L, float(n_mesh) * PI * 2.0, ep.msg])

	# 3 Size: the right end = Big teeth (module 3); the tooth pitch is 3 pi
	var rm := row_of(ep, "module")
	var sm: HSlider = rm.get("slider")
	if sm != null:
		await slide_to(sm, sm.max_value)
	await idle(10)
	await shot("02_big")
	note("big")
	var pill := String((rm.get("pill") as Label).text) if rm.has("pill") else ""
	pts = built_mm(pu().res)
	var pitch := pitch_of(pts)
	ok(sm != null and pill.find("Big") >= 0 and absf(pitch - 3.0 * PI) < 0.05,
		"3 Size: right end = Big teeth (pill says %s): tooth pitch %.3f mm (want %.3f)" % [pill, pitch, 3.0 * PI])

	# 4 Size: the left end = Small teeth (module 1); the tooth pitch is pi
	if sm != null:
		await slide_to(sm, sm.min_value)
	await idle(10)
	await shot("03_small")
	note("small")
	pill = String((rm.get("pill") as Label).text) if rm.has("pill") else ""
	pts = built_mm(pu().res)
	pitch = pitch_of(pts)
	ok(sm != null and pill.find("Small") >= 0 and absf(pitch - PI) < 0.05,
		"4 Size: left end = Small teeth (pill says %s): tooth pitch %.3f mm (want %.3f)" % [pill, pitch, PI])

	# 5 Thickness: a real drag on the Thickness slider to about 20 mm; the built solid is that thick
	var rt := row_of(ep, "thickness")
	var stk: HSlider = rt.get("slider")
	if stk != null:
		await slide_to(stk, 20.0)
	await idle(10)
	await shot("04_thick")
	note("thickness")
	var t_rec := float(pu()._rec().get("easy", {}).get("p", {}).get("thickness", 0.0))
	pts = built_mm(pu().res)
	var T := 0.0
	var tlo := 1e9
	var thi := -1e9
	for p in pts:
		tlo = minf(tlo, float(p[2]))
		thi = maxf(thi, float(p[2]))
	T = thi - tlo if pts.size() > 0 else 0.0
	ok(stk != null and absf(t_rec - 20.0) <= 1.0 and absf(T - t_rec) < 0.3,
		"5 Thickness dragged to %.1f mm (record), the built solid is %.2f mm thick (want %.2f)" % [t_rec, T, t_rec])

	# 6 the words: every press says a line
	var empty := []
	for w in words:
		if String(w[1]).strip_edges() == "":
			empty.append(String(w[0]))
	ok(not words.is_empty() and empty.is_empty(), "6 every press says a line (%d presses, empty after: %s)" % [words.size(), str(empty)])

	print("p066rackandpin: %d fail" % fails)
	quit(1 if fails > 0 else 0)
