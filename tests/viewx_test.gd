## godot --path . -s tests/viewx_test.gd     (ROADMAP_400 K13-K16, scripts/viewx.gd; needs a window: the frames are read back)
## Bars, stated before measuring:
##   1  QUAD VIEW (K14): on -> 4 panes (3 SubViewport ortho cameras + the main perspective camera), front looks -Z, side (his right)
##      looks +X, top looks -Y, the main camera is perspective; the pelvis projects INSIDE every pane; a click on a pane makes it the
##      active one and a drag turns only that pane; the perspective pane still picks a part (m._pick > "") ; off -> no panes, the main
##      camera's fov and the pelvis's screen position are what they were
##   2  ISOLATE (K15): the right forearm picked -> every other body mesh, the prop and the weapon pieces are hidden, the forearm shows;
##      again -> exactly the earlier visible set (also with the head hidden before: it stays hidden) and the same hidden_parts
##   3  FRAME (K15): the forearm's projected box fills 30-80 % of the limiting side of the free view (aimed at 60 %), centred
##   4  SECTION (K16): a Y plane at the pelvis height, side view: the body column above the plane is BACKGROUND (<= 2 % body pixels),
##      below it is body (>= 35 %), and with the section off the same box above the plane is body (>= 50 %: the control)
##   5  PLACEMENT: a screenshot of the quad view: in every pane the box round the pelvis holds body pixels (>= 25 % differ from the
##      pane's background) and the pelvis projects into it
##   6  OVERLAYS (K13): normals lines are NORMAL_LEN long (+-0.1 mm) and there are > 100 of them; stats count > 10000 triangles and
##      the label shows them
extends SceneTree

var fails := 0
var m: Node
const OUT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/viewx.png"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func shot() -> Image:
	await idle(4)
	await RenderingServer.frame_post_draw
	return m.get_viewport().get_texture().get_image()


func differs(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.06


## share of the pixels in r (window px) that differ from bg
func body_share(img: Image, r: Rect2i, bg: Color) -> float:
	r = r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	var n := 0
	var d := 0
	for y in range(r.position.y, r.end.y, 2):
		for x in range(r.position.x, r.end.x, 2):
			n += 1
			if differs(img.get_pixel(x, y), bg):
				d += 1
	return float(d) / maxf(n, 1)


func visible_set() -> Dictionary:
	var out := {}
	for mi in Shading.bodies(m):
		out[mi] = mi.visible
	for n in m.vx._iso_nodes():
		out[n] = n.visible
	return out


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var vx: ViewX = m.vx
	ok(vx != null and m.settings != "user://poser.cfg", "ViewX exists; the test uses its own settings file (%s)" % m.settings)
	for id in ["view_quad_view_on_off", "view_isolate_the_selected_part", "view_frame_the_selected_part", "view_section_plane", "view_show_normals", "view_stats"]:
		var found := false
		for c in m.ui_cmd.commands:
			if c["id"] == id:
				found = true
		ok(found, "command %s is in the registry" % id)
	var quad_cmd: Dictionary = {}
	for c in m.ui_cmd.commands:
		if c["id"] == "view_quad_view_on_off":
			quad_cmd = c
	ok(String(quad_cmd.get("keys", "")) == "Ctrl+Alt+Q", "the quad view's key is Ctrl+Alt+Q (%s)" % quad_cmd.get("keys", ""))
	if m.dummy_on:
		m._dummy_toggle()
	m.yaw = 0.0
	m.pitch = 0.0
	m.dist = 4.6
	m.target = Vector3(0, 0.95, 0)
	m._cam()
	m._refresh()
	await idle(3)
	var pelvis: Vector3 = vx.part_aabb("pelvis").get_center()
	var p0: Vector2 = m.cam.unproject_position(pelvis)
	var fov0: float = m.cam.fov

	# ---- bar 1: quad view
	vx.quad_set(true)
	await idle(5)
	var rects: Dictionary = vx.quad_rects()
	ok(vx.quad_on and vx.panes.size() == 3, "quad view on: %d ortho SubViewport panes + the main perspective camera" % vx.panes.size())
	var dirs := {"front": Vector3(0, 0, -1), "side": Vector3(1, 0, 0), "top": Vector3(0, -1, 0)}
	for k in ["front", "side", "top"]:
		var c: Camera3D = vx.panes[k]["cam"]
		var d: Vector3 = -c.global_transform.basis.z
		var sv: SubViewport = vx.panes[k]["vp"]
		var inside: Vector2 = c.unproject_position(pelvis)
		ok(c.projection == Camera3D.PROJECTION_ORTHOGONAL and d.dot(dirs[k]) > 0.999 and Rect2(Vector2.ZERO, Vector2(sv.size)).has_point(inside) and sv.world_3d == m.get_viewport().world_3d,
			"%s pane: ortho, looks %s (want %s), shares the world, the pelvis at %s of %s" % [k, d.snapped(Vector3.ONE * 0.001), dirs[k], inside.round(), sv.size])
	var pq: Vector2 = m.cam.unproject_position(pelvis)
	ok(m.cam.projection == Camera3D.PROJECTION_PERSPECTIVE and (rects["persp"] as Rect2).has_point(pq), "perspective pane: the main camera, the pelvis at %s inside %s" % [pq.round(), rects["persp"]])
	# the click picks the active pane, a drag turns only that one
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	vx._pane_input(ev, "side")
	var yaw_f: float = vx.panes["front"]["yaw"]
	var yaw_s: float = vx.panes["side"]["yaw"]
	vx.orbit_pane("side", Vector2(50, 0))
	ok(vx.active == "side" and is_equal_approx(float(vx.panes["front"]["yaw"]), yaw_f) and absf(float(vx.panes["side"]["yaw"]) - yaw_s) > 5.0,
		"a click made SIDE the active pane; orbiting it turned its yaw %.0f -> %.0f and left FRONT at %.0f" % [yaw_s, vx.panes["side"]["yaw"], vx.panes["front"]["yaw"]])
	vx.orbit_pane("side", Vector2(-50, 0))
	vx.press((rects["persp"] as Rect2).get_center())
	ok(vx.active == "persp", "a press on the perspective pane makes it the active one")
	var hit: String = m._pick(pq)
	ok(hit != "", "the perspective pane still picks: a ray through the pelvis's screen point hits '%s'" % hit)
	# the screenshot (bar 5) while the quad view is on
	var img := await shot()
	for k in PackedStringArray(["top", "persp", "front", "side"]):
		var r: Rect2 = rects[k]
		var bg := img.get_pixelv(Vector2i(r.position + Vector2(6, 6)))
		var c: Vector2
		if k == "persp":
			c = m.cam.unproject_position(pelvis)
		else:
			c = r.position + (vx.panes[k]["cam"] as Camera3D).unproject_position(pelvis)
		var half := minf(r.size.x, r.size.y) * 0.12
		var box := Rect2i(Vector2i(c - Vector2(half, half)), Vector2i(Vector2(half, half) * 2.0))
		var share := body_share(img, box, bg)
		ok(r.has_point(c) and share >= 0.25, "PLACEMENT %s: the pelvis at %s inside the pane, %.0f %% of the box round it is body (bar >= 25 %%)" % [k, c.round(), share * 100.0])
	DirAccess.make_dir_recursive_absolute(OUT.get_base_dir())
	img.save_png(OUT)
	print("screenshot saved: ", OUT)
	vx.quad_set(false)
	await idle(4)
	var p1: Vector2 = m.cam.unproject_position(pelvis)
	ok(not vx.quad_on and vx.panes.is_empty() and vx.quad_root == null and is_equal_approx(m.cam.fov, fov0) and p1.distance_to(p0) < 0.5,
		"quad off: no panes, fov %.1f (was %.1f), the pelvis back at %s (was %s)" % [m.cam.fov, fov0, p1.round(), p0.round()])

	# ---- bar 2: isolate the right forearm
	m._prop_add("box")
	await idle(2)
	m.sel_prop = -1
	m._props_show()
	m._set_hidden(["head"], true)
	m.sel = "lowerarm_r"
	m.sel_more = []
	await idle(2)
	var before := visible_set()
	var hid0: Dictionary = m.hidden_parts.duplicate()
	vx.isolate_toggle()
	await idle(3)
	var others_hidden := true
	for j in m.pieces:
		if j != "lowerarm_r" and m.pieces[j].visible:
			others_hidden = false
	var props_hidden := true
	for c in m.ui_props_root.get_children():
		props_hidden = props_hidden and not c.visible
	ok(vx.iso_on and others_hidden and m.pieces["lowerarm_r"].visible and props_hidden and m.ui_props_root.get_child_count() >= 1,
		"isolate: only the right forearm is visible (%d pieces, %d props, weapon pieces %s)" % [m.pieces.size(), m.ui_props_root.get_child_count(), m.bat_barrel.visible])
	# bar 3 on the isolated forearm
	var bb: AABB = vx.part_aabb("lowerarm_r")
	var sh: Vector2 = vx.projected_share(bb)
	var clear: Rect2 = m.nav_clear_rect()
	var cen: Vector2 = m.cam.unproject_position(bb.get_center())
	var lim := maxf(sh.x, sh.y)
	ok(lim >= 0.30 and lim <= 0.80 and clear.grow(-clear.size.x * 0.1).has_point(cen),
		"FRAME: the forearm's box fills %.0f %% x %.0f %% of the free view (limiting side %.0f %%, bar 30-80 %%), its centre at %s inside the middle of %s; dist %.2f" % [sh.x * 100.0, sh.y * 100.0, lim * 100.0, cen.round(), clear, m.dist])
	vx.isolate_toggle()
	await idle(3)
	var after := visible_set()
	var same := before.size() == after.size()
	var diffn := 0
	for n in before:
		if not after.has(n) or after[n] != before[n]:
			diffn += 1
	ok(same and diffn == 0 and m.hidden_parts == hid0 and not m.pieces["head"].visible and not vx.iso_on,
		"restore: the visible set is exactly the earlier one (%d nodes, %d differ), hidden_parts %s the same, the head stays hidden" % [before.size(), diffn, "is" if m.hidden_parts == hid0 else "is NOT"])
	m._set_hidden(["head"], false)
	m.sel_prop = -1
	# a frame command from the normal view moves the camera to the part and back out with Fit
	m.dist = 4.6
	m.target = Vector3(0, 0.95, 0)
	m._cam()
	vx.frame()
	var sh2: Vector2 = vx.projected_share(vx.sel_aabb())
	ok(maxf(sh2.x, sh2.y) >= 0.30 and maxf(sh2.x, sh2.y) <= 0.80 and m.dist < 2.0, "frame selected from the full view: limiting side %.0f %%, distance %.2f m (was 4.6)" % [maxf(sh2.x, sh2.y) * 100.0, m.dist])

	# ---- bar 4: the section plane, side view of the whole body, bare picture
	for p in m.ui_side:
		p.visible = false
	m.ui_root.visible = false
	m.clean = true
	m.big_view = true
	m.yaw = 0.0
	m.pitch = 0.0
	m.dist = 4.6
	m.target = Vector3(0, 0.95, 0.0)
	var ax = m.stage_root.get_node_or_null("axis_Y")
	if ax != null:
		ax.visible = false
	m._cam()
	m._refresh()
	await idle(3)
	var base := await shot()
	var bgc := base.get_pixel(6, 6)
	var py: float = pelvis.y
	var up_box := _world_box(Vector3(-0.15, py + 0.06, 0.0), Vector3(0.15, py + 0.40, 0.0))
	var dn_box := _world_box(Vector3(-0.15, py - 0.40, 0.0), Vector3(0.15, py - 0.06, 0.0))
	var control := body_share(base, up_box, bgc)
	vx.section_axis(1)
	vx.section_offset(py)
	await idle(3)
	var cut := await shot()
	var up_cut := body_share(cut, up_box, bgc)
	var dn_cut := body_share(cut, dn_box, bgc)
	ok(control >= 0.5 and up_cut <= 0.02 and dn_cut >= 0.35,
		"SECTION Y = %.2f m: above the plane %.1f %% body (with the section off %.0f %%; bars <= 2 %% and >= 50 %%), below %.0f %% body (bar >= 35 %%)" % [py, up_cut * 100.0, control * 100.0, dn_cut * 100.0])
	var gv: Vector4 = vx.section_vec()
	ok(absf(gv.w - py) < 1e-4 and gv.y == 1.0 and gv.x == 0.0, "the plane is one global uniform (xyz normal, w offset): %s" % gv)
	vx.section_set(false)
	await idle(3)
	var back := await shot()
	ok(body_share(back, up_box, bgc) >= 0.5 and m.pieces["pelvis"].material_override != null, "section off: the body above the plane is back (%.0f %% body)" % (body_share(back, up_box, bgc) * 100.0))

	# ---- bar 6: overlays
	vx.normals_toggle()
	var im: ImmediateMesh = vx.normals_node.mesh
	var arr: Array = im.surface_get_arrays(0)
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var good := 0
	for i in range(0, vs.size() - 1, 2):
		if absf(vs[i].distance_to(vs[i + 1]) - ViewX.NORMAL_LEN) < 1e-4:
			good += 1
	ok(vx.normal_lines > 100 and good == vx.normal_lines, "normals: %d lines, %d of them %.0f mm long" % [vx.normal_lines, good, ViewX.NORMAL_LEN * 1000.0])
	vx.normals_toggle()
	vx.stats_toggle()
	var st: Dictionary = vx.scene_stats()
	ok(int(st["tris"]) > 10000 and int(st["verts"]) > 5000 and vx.stats_lbl.text.contains("tris"), "stats: %s -> label '%s'" % [st, vx.stats_lbl.text])
	vx.stats_toggle()

	print("RESULT: ", "FAIL (%d)" % fails if fails > 0 else "PASS")
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)


## the window rectangle round two world corners (z = 0 plane)
func _world_box(a: Vector3, b: Vector3) -> Rect2i:
	var p: Vector2 = m.cam.unproject_position(a)
	var q: Vector2 = m.cam.unproject_position(b)
	var r := Rect2(p, Vector2.ZERO).expand(q)
	return Rect2i(r)
