extends SceneTree
## NGEAR (Nick 2026-10-29: Parts library, a Gear): a beginner from the BUILDING card picks Gear from the Easy Part chips and sets it with
## real mouse drags on its two sliders. A spur gear with a centre hole: Teeth 8 to 60, and Small / Medium / Big teeth (module 1 / 2 / 3).
## Real pitch diameter = teeth x module, so the tip circle is module x (teeth + 2) and the root circle is module x (teeth - 2.5).
## Every size below is measured from the BUILT geometry (the replayed mesh vertices, mm), not from the record.
## Bars (a bar that FAILS on the old code is marked there; the old code has no Gear chip, so every bar after 0 fails there):
##   0 the Gear chip is on the chips row (one click from the Easy Part chips)
##   1 Gear: one solid; the default 20 teeth, Medium: tip radius = 2 x 22 / 2 = 22 mm (+- 0.3)
##   2 Teeth slider: drag it to about 12 teeth: range 8..60 and the record holds the drag teeth; tip radius matches those teeth (+- 0.3)
##   3 Size: drag to the right end = Big teeth (module 3), the pill says Big; tip radius = 3 x (teeth + 2) / 2 (+- 0.3)
##   4 Size: drag to the left end = Small teeth (module 1); tip radius = (teeth + 2) / 2 (+- 0.3)
##   5 centre hole: the mesh has a ring of vertices at hole radius 0.12 x teeth x module, and none inside it
##   6 root circle: the outline smallest radius (outside the hole) = module x (teeth - 2.5) / 2 (+- 0.3)
##   7 pitch: the tooth flank crosses the pitch circle at half the tooth pitch (+- 0.3 degree), i.e. tooth width = space at pitch
##   8 the words: every press says a line
## shots: C:/Temp/claude/ngear/
const SHOT := "C:/Temp/claude/ngear"
const DIRT := "user://ngear_test"
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


## the built outline: the thickness axis is the mesh thinnest box side; the vertices as [radius, angle] in mm about the box centre
func outline(res: Dictionary) -> Array:
	var mesh: ArrayMesh = res.get("mesh")
	if mesh == null:
		return []
	var bb: AABB = mesh.get_aabb()
	var ax := 0
	if bb.size.y < bb.size.x and bb.size.y <= bb.size.z:
		ax = 1
	elif bb.size.z < bb.size.x and bb.size.z < bb.size.y:
		ax = 2
	var c := bb.get_center()
	var pa := [0, 1, 2]
	pa.erase(ax)
	var out := []
	for s in mesh.get_surface_count():
		for v in mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
			var x: float = (float(v[pa[0]]) - float(c[pa[0]])) * 1000.0
			var y: float = (float(v[pa[1]]) - float(c[pa[1]])) * 1000.0
			out.append([Vector2(x, y).length(), atan2(y, x)])
	return out


func tip_of(res: Dictionary) -> float:
	var t := 0.0
	for p in outline(res):
		t = maxf(t, float(p[0]))
	return t


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
	var gear_chip: Button = ep.chips.get("gear") if ep.chips.has("gear") else null
	ok(gear_chip != null and gear_chip.is_visible_in_tree(), "0 the Gear chip is on the Easy Part chips row (chips: %s)" % str(ep.chips.keys()))

	# 1 Gear: one click on the chip makes the default gear (20 teeth, Medium = module 2)
	if gear_chip != null:
		await click_ctl(gear_chip)
	await idle(10)
	await shot("00_gear")
	note("gear chip")
	var n := int(pu()._rec().get("easy", {}).get("p", {}).get("teeth", 0))
	var mod := int(pu()._rec().get("easy", {}).get("p", {}).get("module", 0))
	var tip := tip_of(pu().res)
	ok(int(pu().res.get("bodies", 0)) == 1 and n == 20 and mod == 2 and absf(tip - mod * (n + 2) / 2.0) < 0.3,
		"1 Gear: one solid, 20 teeth, Medium: tip radius %.2f mm (want %.2f) [%s]" % [tip, mod * (n + 2) / 2.0, ep.msg])

	# 2 Teeth: a real drag on the Teeth slider to about 12 teeth
	var st: HSlider = row_of(ep, "teeth").get("slider")
	var range_ok := st != null and absf(st.min_value - 8.0) < 0.01 and absf(st.max_value - 60.0) < 0.01
	if st != null:
		await slide_to(st, 12.0)
	await idle(10)
	await shot("01_teeth")
	note("teeth")
	n = int(pu()._rec().get("easy", {}).get("p", {}).get("teeth", 0))
	tip = tip_of(pu().res)
	ok(range_ok and absi(n - 12) <= 1 and absf(tip - mod * (n + 2) / 2.0) < 0.3,
		"2 Teeth slider 8..60, dragged to %d teeth: tip radius %.2f mm (want %.2f) [%s]" % [n, tip, mod * (n + 2) / 2.0, ep.msg])

	# 3 Size: the right end = Big teeth (module 3)
	var rm := row_of(ep, "module")
	var sm: HSlider = rm.get("slider")
	if sm != null:
		await slide_to(sm, sm.max_value)
	await idle(10)
	await shot("02_big")
	note("big")
	mod = int(pu()._rec().get("easy", {}).get("p", {}).get("module", 0))
	var pill := String((rm.get("pill") as Label).text) if rm.has("pill") else ""
	tip = tip_of(pu().res)
	ok(mod == 3 and pill.find("Big") >= 0 and absf(tip - 3.0 * (n + 2) / 2.0) < 0.3,
		"3 Size: right end = Big teeth (module %d, shows %s): tip radius %.2f mm (want %.2f)" % [mod, pill, tip, 3.0 * (n + 2) / 2.0])

	# 4 Size: the left end = Small teeth (module 1)
	if sm != null:
		await slide_to(sm, sm.min_value)
	await idle(10)
	await shot("03_small")
	note("small")
	mod = int(pu()._rec().get("easy", {}).get("p", {}).get("module", 0))
	pill = String((rm.get("pill") as Label).text) if rm.has("pill") else ""
	tip = tip_of(pu().res)
	ok(mod == 1 and pill.find("Small") >= 0 and absf(tip - (n + 2) / 2.0) < 0.3,
		"4 Size: left end = Small teeth (module %d, shows %s): tip radius %.2f mm (want %.2f)" % [mod, pill, tip, (n + 2) / 2.0])

	# 5 the centre hole: a ring of outline vertices at 0.12 x teeth x module, and nothing inside it
	var hr := 0.12 * n * mod
	var ring := 0
	var inside := 0
	for p in outline(pu().res):
		var r := float(p[0])
		if absf(r - hr) < 0.1:
			ring += 1
		elif r < hr - 0.1:
			inside += 1
	ok(ring >= 6 and inside == 0, "5 centre hole: ring of %d vertices at %.2f mm, %d vertices inside it" % [ring, hr, inside])

	# 6 the root circle: the smallest outline radius outside the hole = module x (teeth - 2.5) / 2
	var root_r := 1e9
	for p in outline(pu().res):
		var r := float(p[0])
		if r > hr + 0.5:
			root_r = minf(root_r, r)
	ok(absf(root_r - mod * (n - 2.5) / 2.0) < 0.3, "6 root circle: %.2f mm (want %.2f = module x (teeth - 2.5) / 2)" % [root_r, mod * (n - 2.5) / 2.0])

	# 7 pitch: the flank at the pitch circle is half the tooth pitch from the tooth middle line (tooth width = space)
	var ra := mod * (n + 2) / 2.0
	var rf := mod * (n - 2.5) / 2.0
	var rp := mod * n / 2.0
	var tip_a := 1e9   # smallest positive angle of a tip vertex, and of a root vertex
	var root_a := 1e9
	for p in outline(pu().res):
		var r := float(p[0])
		var a := float(p[1])
		if a <= 0.0:
			continue
		if absf(r - ra) < 0.1:
			tip_a = minf(tip_a, a)
		if absf(r - rf) < 0.1:
			root_a = minf(root_a, a)
	var half_at_pitch := tip_a + (root_a - tip_a) * (ra - rp) / (ra - rf)
	var want := PI / (2.0 * n)
	ok(tip_a < 1e8 and root_a < 1e8 and absf(half_at_pitch - want) * 180.0 / PI < 0.3,
		"7 pitch: the flank crosses the pitch circle at %.2f deg (want %.2f = half of 360/%d)" % [half_at_pitch * 180.0 / PI, want * 180.0 / PI, n])
	await shot("04_done")

	# 8 the words: every press says a line
	var empty := []
	for w in words:
		if String(w[1]).strip_edges() == "":
			empty.append(String(w[0]))
	ok(not words.is_empty() and empty.is_empty(), "8 every press says a line (%d presses, empty after: %s)" % [words.size(), str(empty)])

	print("ngear: %d fail" % fails)
	quit(1 if fails > 0 else 0)
