## godot --path . -s tests/ring_edges_test.gd     (GATES BB2, UPGRADES #5; a real window, real right-clicks)
## THE RING AT THE EDGES: the head panned (the camera's target) under each of the 3D view's four corners and four edge
## middles (16 px in from the panels and the top bar; the top right one below the view cube, which owns that corner; one on the nav block under it goes just left of it), at UI size 100, 125 (1600 x 900) and 150 % (the window made
## 1920 x 1080 for it). A real right-click there must pick the head and open the ring; the whole ring and its title are
## inside the window and below the top bar; each wedge's label spot is inside its own wedge, and a real left click on
## each wedge's label runs that wedge (the ring's actions swapped for recorders, so nothing in the scene changes).
extends SceneTree

var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func btn(b: MouseButton, down: bool, p: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = b
	e.pressed = down
	p *= m.get_window().content_scale_factor   # the window's pixels: the UI is drawn scaled by this
	e.position = p
	e.global_position = p
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_RIGHT if b == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)


func spot(j: String) -> Vector2:
	var c: Array = m.B.cap(j)
	return m.cam.unproject_position((c[0] + c[1]) * 0.5)


## pan (the camera's target, as the arrow keys do) until part j's middle is at screen point p
func put(j: String, p: Vector2) -> float:
	for k in 12:
		var vs: Vector2 = m.get_viewport().get_visible_rect().size
		var mpp: float = 2.0 * m.dist * tan(deg_to_rad(m.cam.fov * 0.5)) / vs.y
		var d := p - spot(j)
		m.target -= m.cam.global_basis.x * d.x * mpp - m.cam.global_basis.y * d.y * mpp
		m._cam()
	return spot(j).distance_to(p)


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(4)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m._load_scene("res://scenes/combo3.json")
	m._rebuild_cards()
	m.dist = 2.2
	var ring: RingMenu = m.ui_ring
	var font := ring.get_theme_default_font()
	for setup in [[Vector2i(1600, 900), 100], [Vector2i(1600, 900), 125], [Vector2i(1920, 1080), 150]]:
		m.get_window().size = setup[0]
		await idle(8)
		if not m.scale_fits(setup[1]):
			ok(false, "%d %%: the window would not become %s (it is %s)" % [setup[1], setup[0], m.get_window().size])
			continue
		m._set_scale(setup[1])
		await idle(6)
		var vs: Vector2 = m.get_viewport().get_visible_rect().size
		var view := Rect2(Vector2(m.LEFT_W, m.TOP_H), vs - Vector2(m.LEFT_W + m.RIGHT_W, m.TOP_H + m.bottom_h)).grow(-16.0)
		var spots := {"top left": view.position, "top": Vector2(view.get_center().x, view.position.y),
			"top right": Vector2(view.end.x, view.position.y), "right": Vector2(view.end.x, view.get_center().y),
			"bottom right": view.end, "bottom": Vector2(view.get_center().x, view.end.y),
			"bottom left": Vector2(view.position.x, view.end.y), "left": Vector2(view.position.x, view.get_center().y)}
		# the view cube owns its corner (a click there turns the view): the top right spot goes just below it
		var cube: Rect2 = m.ui_cube.get_global_rect().grow(8.0)
		if cube.has_point(spots["top right"]):
			spots["top right"].y = cube.end.y + 16.0
		# round 27: the nav block (Orbit Pan / - + / Fit Grid) sits under the cube; a spot on it goes just left of it
		var nav: Rect2 = m.ui_nav.get_global_rect().grow(8.0)
		for k in spots:
			if nav.has_point(spots[k]):
				spots[k].x = nav.position.x - 16.0
		var bad := []
		var runs := 0
		for nm in spots:
			var miss := put("head", spots[nm])
			m.sel = "pelvis"
			await idle(2)
			var p: Vector2 = spot("head")
			btn(MOUSE_BUTTON_RIGHT, true, p)
			btn(MOUSE_BUTTON_RIGHT, false, p)
			await idle(2)
			if not ring.visible or m.sel != "head":
				bad.append([nm, "no ring on the head (sel '%s', ring %s, %.0f px from the spot)" % [m.sel, ring.visible, miss]])
				ring.close()
				continue
			var tw := font.get_string_size(ring.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
			var disc := Rect2(ring.at - Vector2(RingMenu.R_OUT, RingMenu.R_OUT), Vector2(2, 2) * RingMenu.R_OUT)
			var head := Rect2(ring.at + Vector2(-tw * 0.5, -RingMenu.R_OUT - 10.0 - 15.0), Vector2(tw, 18.0))
			var win := Rect2(Vector2.ZERO, vs)
			if not win.encloses(disc) or not win.encloses(head) or head.position.y < m.TOP_H:
				bad.append([nm, "off: ring %s title %s window %s top bar %d" % [disc, head, vs, m.TOP_H]])
			# each wedge: its label's spot is its own, and a real click there runs it
			var n: int = ring.items.size()
			var ran := []
			for i in n:
				ring.items[i]["run"] = func(): ran.append(i)
			for i in n:
				if not ring.visible:
					btn(MOUSE_BUTTON_RIGHT, true, p)
					btn(MOUSE_BUTTON_RIGHT, false, p)
					await idle(2)
					for k in n:
						ring.items[k]["run"] = func(): ran.append(k)
				var q: Vector2 = ring.at + ring.dir(i) * RingMenu.R_TXT
				if ring.wedge(q) != i:
					bad.append([nm, "wedge %d's label spot is in wedge %d" % [i, ring.wedge(q)]])
				btn(MOUSE_BUTTON_LEFT, true, q)
				btn(MOUSE_BUTTON_LEFT, false, q)
				await idle(2)
			if ran != range(n):
				bad.append([nm, "clicks ran %s, not %s" % [ran, range(n)]])
			runs += ran.size()
			ring.close()
		ok(bad.is_empty(), "%d %% (UI %s): the head under each of 8 view edges/corners: ring + title inside the window and below the top bar, %d wedge clicks each ran their own (bad: %s)" % [setup[1], vs, runs, bad])
	m._set_scale(100)
	m.get_window().size = Vector2i(1600, 900)
	await idle(4)
	print("RING EDGES: %d failed" % fails)
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
