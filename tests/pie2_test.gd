## godot --path . -s tests/pie2_test.gd     (ROADMAP_400 P04 follow-up; needs a window: real InputEvents through the viewport)
## The brush PIE on the PAINT pages (vertex paint, texture paint, weight paint) and the Q collision. The option is m.pie_on
## (off by default; a sibling lane adds the settings toggle, this suite sets the variable). tests/pie_test.gd is NOT edited:
## the sculpt section here repeats its key + release path so a regression shows in both.
## KEY DECISION (stated in the report): Q stays the pie key on every mesh page (sculpt, vertex / texture / weight paint) because
## P04's suite and docs say Q and Q is free on those pages. The snap-90 it shadows stays reachable: (a) Q itself on every page that
## is not a mesh page, and (b) on the mesh pages the S search line "Snap the part to 90" now runs the snap directly instead of
## replaying the Q key (the key replay was swallowed by the pie, so it was unreachable there).
## Bars, per page P in {sculpt, vertex paint, texture paint, weight paint} (N = that page's brush count; sculpt 10, vertex and
## texture 7 = the 6 blend modes [mix, add, subtract, multiply, lighten, darken] + blur, weight 4 [add, subtract, set, smooth]):
##   a option OFF: Q opens no ring, the brush is unchanged, and Q still snaps the picked part to 90 (the old key behaviour)
##   b option ON: Q opens the ring (visible) with the page's N brushes in order, centre within 1 px of the mouse; the Q did not snap
##   c for every k in 0..N-1: a release at ring.at + 70 px at angle k*360/N (clockwise from up) picks brush k exactly (sentinel
##     first), and the ring closes
##   d a release 10 px from the centre cancels (ring closed, brush unchanged); a release 160 px out cancels too
##   e snap-90 with pie_on on this page: the S search line "Snap the part to 90" snaps the picked part (bend 80 -> 90)
##   f PLANTED FAKE: the k=1 release checked against brush 2 MUST be false
## and on a POSE page with pie_on: Q opens no ring and snaps 80 -> 90 (the documented key is untouched there).
extends SceneTree

var fails := 0
var m: Node
var part := ""


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	root.push_input(e)
	await process_frame


func release(p: Vector2) -> void:
	await move(p)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = p
	e.global_position = p
	root.push_input(e)
	await idle(2)


func key(k: int) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = true
	root.push_input(e)
	await idle(2)
	var u := InputEventKey.new()
	u.keycode = k
	u.physical_keycode = k
	u.pressed = false
	root.push_input(u)
	await idle(2)


func boot() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false


func leave() -> void:
	m.queue_free()
	await idle(4)


## a part whose bend range holds 80 and 90 and is not a weapon; picked and set to bend 80
func arm() -> void:
	part = ""
	for p in m.B.ang.keys():
		if p in Body.WEAPON:
			continue
		var lim: Vector2 = m.B.lim[p]["bend"]
		if lim.x <= 0.0 and lim.y >= 100.0:
			part = p
			break
	if part != "":
		m.sel = part
		m.B.set_ang_safe(part, Vector3(80, 0, 0))


func bend() -> float:
	return (m.B.ang[part] as Vector3).x if part != "" else -999.0


func cmd_snap90() -> bool:
	for c in m.ui_cmd.commands:
		if c["id"] == "snap_the_part_to_90":
			c["run"].call()
			return true
	return false


func page(label: String, names: Array, get_brush: Callable, set_sentinel: Callable) -> void:
	var pie = m.get("ui_pie")
	var c := Vector2(root.size) * 0.5
	var n := names.size()
	arm()
	ok(part != "" and m.get("pie_on") == false and is_equal_approx(bend(), 80.0), "[%s] armed: part '%s' bend %.1f, pie_on %s" % [label, part, bend(), str(m.get("pie_on"))])
	# a option off
	await move(c)
	var b0 = get_brush.call()
	await key(KEY_Q)
	ok(not pie.visible and get_brush.call() == b0, "[%s a] option off: no ring (visible %s), brush '%s' unchanged" % [label, pie.visible, str(get_brush.call())])
	ok(absf(bend() - 90.0) < 0.01, "[%s a] option off: Q still snaps the part to 90 (bend now %.2f)" % [label, bend()])
	# b option on
	m.pie_on = true
	arm()
	await move(c)
	await key(KEY_Q)
	var got: Array = []
	for it in pie.items:
		got.append(String(it["name"]))
	ok(pie.visible and got == names, "[%s b] option on: Q opens the ring with %d brushes %s" % [label, got.size(), str(got)])
	ok(pie.at.distance_to(c) < 1.0, "[%s b] ring centre %.2f px from the mouse" % [label, pie.at.distance_to(c)])
	ok(absf(bend() - 80.0) < 0.01, "[%s b] the Q opened the ring and did not snap (bend %.2f)" % [label, bend()])
	# c every wedge
	var wrong := 0
	var closed := 0
	for k in n:
		if not pie.visible:
			await move(c)
			await key(KEY_Q)
		var a := deg_to_rad(k * 360.0 / n)
		var p: Vector2 = pie.at + Vector2(sin(a), -cos(a)) * 70.0
		set_sentinel.call()
		await release(p)
		if get_brush.call() != names[k]:
			wrong += 1
			print("     k=%d at %.0f deg gave '%s', wanted '%s'" % [k, k * 360.0 / n, str(get_brush.call()), names[k]])
		if not pie.visible:
			closed += 1
		if k == 1:
			ok(not (get_brush.call() == names[2]), "[%s f] PLANTED: the k=1 release checked against brush 2 is false, as it must be" % label)
	ok(wrong == 0 and closed == n, "[%s c] release at k*360/%d picks brush k for every k: %d wrong, ring closed after %d / %d" % [label, n, wrong, closed, n])
	# d dead zone and outside
	await move(c)
	await key(KEY_Q)
	set_sentinel.call()
	var s0 = get_brush.call()
	await release(pie.at + Vector2(0, -10))
	ok(not pie.visible and get_brush.call() == s0, "[%s d] release 10 px from the centre cancels: ring open %s, brush '%s'" % [label, pie.visible, str(get_brush.call())])
	await move(c)
	await key(KEY_Q)
	await release(pie.at + Vector2(160, 0))
	ok(not pie.visible and get_brush.call() == s0, "[%s d] release 160 px out cancels: ring open %s, brush '%s'" % [label, pie.visible, str(get_brush.call())])
	# e snap-90 reachable with pie_on
	arm()
	var found := cmd_snap90()
	await idle(2)
	ok(found and absf(bend() - 90.0) < 0.01, "[%s e] pie_on: the search line 'Snap the part to 90' snaps the part (found %s, bend %.2f)" % [label, found, bend()])


func _init() -> void:
	var line: Dictionary
	# pose page
	await boot()
	m.pie_on = true
	arm()
	var c := Vector2(root.size) * 0.5
	await move(c)
	await key(KEY_Q)
	ok(not m.ui_pie.visible and absf(bend() - 90.0) < 0.01, "[pose] pie_on: Q opens no ring (%s) and snaps 80 -> 90 (bend %.2f)" % [m.ui_pie.visible, bend()])
	await leave()
	# sculpt
	await boot()
	m._sculpt_start()
	await idle(3)
	var ksc = m.ksc
	await page("sculpt", ["draw", "clay strips", "inflate", "smooth", "flatten", "pinch", "crease", "grab", "snake hook", "mask"],
		func(): return ksc.brush, func(): ksc.brush = "sentinel")
	await leave()
	# vertex paint
	var vnames := ["mix", "add", "subtract", "multiply", "lighten", "darken", "blur"]
	await boot()
	for t in MeshTools.TOOLS:
		if t["id"] == "mesh_vpaint":
			line = t
	MeshTools.run(line, m)
	await idle(4)
	var pu := KMeshVPaintUI.of(m)
	ok(pu.on and not pu.tex_mode, "vertex paint is on")
	await page("vpaint", vnames, func(): return "blur" if pu.blur else pu.mode, func():
		pu.blur = false
		pu.mode = "sentinel")
	await leave()
	# texture paint
	await boot()
	for t in MeshTools.TOOLS:
		if t["do"] == "op:tpaint":
			line = t
	MeshTools.run(line, m)
	await idle(4)
	pu = KMeshVPaintUI.of(m)
	ok(pu.on and pu.tex_mode, "texture paint is on")
	await page("tpaint", vnames, func(): return "blur" if pu.blur else pu.mode, func():
		pu.blur = false
		pu.mode = "sentinel")
	await leave()
	# weight paint
	await boot()
	m.wp_key = "pie2_test"
	m._kmesh_edit_start()
	await idle(2)
	KMeshAutoWeights.preview_bind(m)
	for t in MeshTools.TOOLS:
		if t["do"] == "op:wpaint":
			line = t
	MeshTools.run(line, m)
	await idle(3)
	var wu := KMeshWPaintUI.of(m)
	ok(wu.on, "weight paint is on")
	await page("wpaint", ["add", "subtract", "set", "smooth"], func(): return wu.brush, func(): wu.brush = "sentinel")
	await leave()
	print("pie2_test: %d FAIL" % fails if fails > 0 else "pie2_test: all ok")
	quit(1 if fails > 0 else 0)
