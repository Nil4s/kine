## godot --path . -s tests/kwpaint_test.gd     (ROADMAP_400 H02: weight paint on a KMesh's skin weights; needs a window)
## scripts/kmesh_wpaint.gd (the brush) + scripts/kmesh_wpaint_ui.gd (the mode, MeshTools "op:wpaint"). Bars, written
## before the first run:
##  BRUSH (a closed cylinder along X, r 5 cm, 0.9 m, 24 sides x 30 rings, made exactly X-symmetric; five bones
##  spine / upperarm_l / upperarm_r / hand_l / hand_r, start weights hand-made and exactly mirror-symmetric)
##   (1) SET: a set-to-1.0 dab (strength 1) centred on a vertex for bone B: B = 1 there (1e-6) and every other bone 0
##   (2) ADD: an add dab of strength 0.2: every vertex inside the radius has B raised by 0.2 x falloff(d / r) within 1e-5,
##       sums 1 within 1e-5; every vertex outside keeps its weights bit-for-bit. CONTROL: >= 5 vertices with falloff > 0.5
##   (3) LOCK: spine locked; add, subtract, set and smooth strokes over it: spine's weight bit-for-bit unchanged on every
##       vertex. CONTROL: the same strokes without the lock move spine by > 0.05 somewhere
##   (4) SMOOTH: after a sharp set spike, a smooth stroke lowers the largest neighbour difference of that bone (bar:
##       to <= 0.7 x before); sums still 1 within 1e-5, <= 4 influences
##   (5) MIRROR: X mirror on, an add dab on upperarm_l at x = +0.25: every touched vertex v and its mirror u agree,
##       w(u, mirror(k)) = w(v, k) within 1e-5 for every bone k. CONTROL: upperarm_r at the mirrored vertices rose by
##       > 0.05, and the same dab with mirror off leaves the -x side bit-for-bit
##   (6) LIMIT: a vertex with 4 influences painted with a 5th bone keeps <= 4, the painted bone at its target, sum 1;
##       the rule with a locked bone keeps it exactly
##   (7) UNDO: a stroke bracketed by KMeshUndo is ONE step; undo restores both channels bit-for-bit
##  APP (main.tscn, the model preview's cube bound by H01's command)
##   (8) the MeshTools line "op:wpaint" turns the mode on (panel shown, heat layer on the mesh)
##   (9) a click near a bone (off the mesh) makes it the active bone; picking a row of the bone list does too
##   (10) a real mouse set stroke (value 1, strength 1) on the front face's centre vertex: that vertex's bone = 1
##        (>= 0.999), one undo step; a dragged add stroke is one more step; Ctrl+Z restores the channels bit-for-bit,
##        Ctrl+Shift+Z redoes them bit-for-bit
##   (11) PLACEMENT: on screen, the pixel at the painted vertex is the heat colour of its weight (red, each channel
##        within 0.15); CONTROL: a vertex of the same face with a weight < 0.5 shows its own colour, > 0.5 away from red
##   (12) the line again turns the mode off: the wire and the vertex points come back
## shot -> /tmp/claude-0/sp/kwpaint.png when that folder exists
extends SceneTree

var fails := 0
var m: Node
const SPINE := 0
const UA_L := 1
const UA_R := 2
const H_L := 3
const H_R := 4
const BONES := [{"name": "spine", "id": 0}, {"name": "upperarm_l", "id": 1}, {"name": "upperarm_r", "id": 2},
	{"name": "hand_l", "id": 3}, {"name": "hand_r", "id": 4}]


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


## the cylinder along X centred on x = 0, exactly mirror-symmetric, with the hand-made symmetric weights
func arm() -> KMesh:
	var prof := [[0.0, 0.0]]
	for k in 31:
		prof.append([0.05, 0.9 * float(k) / 30.0])
	prof.append([0.0, 0.9])
	var c := KMeshPrims._lathe(24, prof)
	for v in c.verts.size():
		var p := c.verts[v]
		c.verts[v] = Vector3(p.y - 0.45, -p.x, p.z)   # a rotation: the winding stays
	c.rebuild()
	var sym := c.symmetry_map(0, 1e-4)
	for v in c.verts.size():   # exact: the -x partner is the +x vertex mirrored, bit for bit
		var u := sym[v]
		if u >= 0 and c.verts[v].x > 0.0:
			c.verts[u] = Vector3(-c.verts[v].x, c.verts[v].y, c.verts[v].z)
		elif u == v:
			c.verts[v].x = 0.0
	c.rebuild()
	KMeshWPaint.ensure_channels(c)
	var cb := PackedColorArray()
	var cw := PackedColorArray()
	for v in c.verts.size():
		var x := c.verts[v].x
		var t := clampf(absf(x) / 0.45, 0.0, 1.0)
		var ua := UA_L if x > 0.0 else UA_R
		var hd := H_L if x > 0.0 else H_R
		cb.append(Color(SPINE, ua, hd, -1))
		cw.append(Color(1.0 - t, t * 0.7, t * 0.3, 0.0))
	c.set_attr_data(KMeshWPaint.CH_BONES, cb)
	c.set_attr_data(KMeshWPaint.CH_WEIGHTS, cw)
	return c


func w(mesh: KMesh, v: int, b: int) -> float:
	return KMeshWPaint.weight_of(mesh, v, b)


func nearest(mesh: KMesh, p: Vector3) -> int:
	var best := -1
	var bd := INF
	for v in mesh.verts.size():
		var d := mesh.verts[v].distance_to(p)
		if d < bd:
			bd = d
			best = v
	return best


## {worst |sum - 1|, most influences}
func sums(mesh: KMesh) -> Dictionary:
	var cb: PackedColorArray = mesh.attr_data(KMeshWPaint.CH_BONES)
	var cw: PackedColorArray = mesh.attr_data(KMeshWPaint.CH_WEIGHTS)
	var worst := 0.0
	var most := 0
	for v in cb.size():
		var s := 0.0
		var n := 0
		for q in 4:
			if roundi(cb[v][q]) >= 0 and cw[v][q] > 0.0:
				s += cw[v][q]
				n += 1
		worst = maxf(worst, absf(s - 1.0))
		most = maxi(most, n)
	return {"worst": worst, "most": most}


func stroke(mesh: KMesh, params: Dictionary, pts: Array) -> KMeshWPaint:
	var b := KMeshWPaint.new()
	b.begin(mesh, params)
	for pt in pts:
		b.to(pt, Vector3.UP, 1.0)
	b.end()
	return b


## the largest |w_b(v) - w_b(u)| over the edges with both ends within r of c
func max_edge(mesh: KMesh, b: int, c: Vector3, r: float) -> float:
	var out := 0.0
	for e in mesh.edges():
		if mesh.verts[e.x].distance_to(c) < r and mesh.verts[e.y].distance_to(c) < r:
			out = maxf(out, absf(w(mesh, e.x, b) - w(mesh, e.y, b)))
	return out


func brush_part() -> void:
	var mo := KMeshWPaint.mirror_map(BONES)
	ok(mo.get(UA_L) == UA_R and mo.get(H_R) == H_L and not mo.has(SPINE), "mirror map: upperarm_l <-> upperarm_r, hand_r <-> hand_l, spine has none")
	# (1) SET
	var a := arm()
	var v0 := nearest(a, Vector3(0.2, 0.0, 0.05))
	stroke(a, {"brush": KMeshWPaint.SET, "bone": H_L, "value": 1.0, "strength": 1.0, "radius": 0.005}, [a.verts[v0]])
	var others := 0.0
	for b in [SPINE, UA_L, UA_R, H_R]:
		others += w(a, v0, b)
	ok(absf(w(a, v0, H_L) - 1.0) <= 1e-6 and others == 0.0, "(1) set 1.0 on hand_l at vertex %d: hand_l = %.7f, every other bone %.7f" % [v0, w(a, v0, H_L), others])

	# (2) ADD
	a = arm()
	var c := a.verts[nearest(a, Vector3(0.25, 0.0, 0.05))]
	var w0: PackedColorArray = a.attr_data(KMeshWPaint.CH_WEIGHTS).duplicate()
	var b0: PackedColorArray = a.attr_data(KMeshWPaint.CH_BONES).duplicate()
	var before := []
	for v in a.verts.size():
		before.append(w(a, v, UA_L))
	var r := 0.06
	stroke(a, {"brush": KMeshWPaint.ADD, "bone": UA_L, "strength": 0.2, "radius": r}, [c])
	var worst := 0.0
	var strong := 0
	var out_changed := 0
	var inside := 0
	for v in a.verts.size():
		var d := a.verts[v].distance_to(c)
		if d < r:
			inside += 1
			var f := KMeshSculpt.falloff(KMeshSculpt.F_SMOOTH, d / r)
			if f > 0.5:
				strong += 1
			worst = maxf(worst, absf((w(a, v, UA_L) - float(before[v])) - 0.2 * f))
		elif (a.attr_data(KMeshWPaint.CH_WEIGHTS) as PackedColorArray)[v] != w0[v] or (a.attr_data(KMeshWPaint.CH_BONES) as PackedColorArray)[v] != b0[v]:
			out_changed += 1
	var su := sums(a)
	ok(worst <= 1e-5 and su["worst"] <= 1e-5, "(2) add 0.2: upperarm_l rose by 0.2 x falloff within %s (bar 1e-5) on %d vertices; sums within %s (bar 1e-5)" % [String.num_scientific(worst), inside, String.num_scientific(su["worst"])])
	ok(strong >= 5 and out_changed == 0, "(2) %d vertices had falloff > 0.5 (control: >= 5); %d outside the radius changed (bar 0)" % [strong, out_changed])

	# (3) LOCK
	var lock_moves := []
	for locked in [true, false]:
		a = arm()
		var s0 := []
		for v in a.verts.size():
			s0.append(w(a, v, SPINE))
		var lk := {SPINE: true} if locked else {}
		var path := [Vector3(0.1, 0.0, 0.05), Vector3(0.15, 0.0, 0.05), Vector3(0.2, 0.0, 0.05)]
		for br in [[KMeshWPaint.ADD, UA_L], [KMeshWPaint.SUB, H_L], [KMeshWPaint.SET, UA_L], [KMeshWPaint.SMOOTH_W, UA_L], [KMeshWPaint.ADD, SPINE]]:
			stroke(a, {"brush": br[0], "bone": br[1], "strength": 0.5, "value": 0.9, "radius": 0.08, "locks": lk}, path)
		var mv := 0.0
		for v in a.verts.size():
			mv = maxf(mv, absf(w(a, v, SPINE) - float(s0[v])))
		lock_moves.append(mv)
	ok(lock_moves[0] == 0.0, "(3) spine locked: add, subtract, set, smooth (and an add on spine itself) moved it by %s (bar 0, bit-for-bit)" % String.num_scientific(lock_moves[0]))
	ok(lock_moves[1] > 0.05, "(3) control: the same strokes unlocked move spine by %.3f (bar > 0.05)" % lock_moves[1])

	# (4) SMOOTH
	a = arm()
	var cs := a.verts[nearest(a, Vector3(0.2, 0.0, 0.05))]
	stroke(a, {"brush": KMeshWPaint.SET, "bone": H_L, "value": 1.0, "strength": 1.0, "radius": 0.02}, [cs])
	var e0 := max_edge(a, H_L, cs, 0.08)
	stroke(a, {"brush": KMeshWPaint.SMOOTH_W, "bone": H_L, "strength": 0.5, "radius": 0.08}, [cs, cs + Vector3(0.01, 0, 0), cs - Vector3(0.01, 0, 0)])
	var e1 := max_edge(a, H_L, cs, 0.08)
	su = sums(a)
	ok(e1 <= 0.7 * e0 and e0 > 0.3, "(4) smooth: the largest neighbour difference of hand_l %.3f -> %.3f (bar <= 0.7 x)" % [e0, e1])
	ok(su["worst"] <= 1e-5 and su["most"] <= 4, "(4) after smoothing: sums within %s, at most %d influences" % [String.num_scientific(su["worst"]), su["most"]])

	# (5) MIRROR
	for mir in [true, false]:
		a = arm()
		var sym := a.symmetry_map(0, 1e-6)
		var hc := a.verts[nearest(a, Vector3(0.25, 0.0, 0.05))]
		var neg0: PackedColorArray = a.attr_data(KMeshWPaint.CH_WEIGHTS).duplicate()
		var ur0 := []
		for v in a.verts.size():
			ur0.append(w(a, v, UA_R))
		var bb := stroke(a, {"brush": KMeshWPaint.ADD, "bone": UA_L, "strength": 0.2, "radius": 0.06, "mirror": mir, "mirror_of": mo}, [hc])
		if mir:
			var dif := 0.0
			var rose := 0.0
			var pairs := 0
			for v in bb.touched:
				if a.verts[v].x <= 0.0:
					continue
				var u := sym[v]
				if u < 0:
					continue
				pairs += 1
				for k in [SPINE, UA_L, UA_R, H_L, H_R]:
					dif = maxf(dif, absf(w(a, u, int(mo.get(k, k))) - w(a, v, k)))
				rose = maxf(rose, w(a, u, UA_R) - float(ur0[u]))
			ok(pairs >= 5 and dif <= 1e-5, "(5) mirror: %d touched vertices and their mirrors agree on every mirrored bone within %s (bar 1e-5)" % [pairs, String.num_scientific(dif)])
			ok(rose > 0.05, "(5) control: upperarm_r rose by %.3f at the mirrored vertices (bar > 0.05)" % rose)
		else:
			var neg_changed := 0
			var cw1: PackedColorArray = a.attr_data(KMeshWPaint.CH_WEIGHTS)
			for v in a.verts.size():
				if a.verts[v].x < 0.0 and cw1[v] != neg0[v]:
					neg_changed += 1
			ok(neg_changed == 0, "(5) control: mirror off leaves the -x side bit-for-bit (%d changed)" % neg_changed)

	# (6) LIMIT
	var r6 := KMeshWPaint.paint_rule({0: 0.4, 1: 0.3, 2: 0.2, 3: 0.1}, 5, 0.15, {})
	var s6 := 0.0
	for k in r6:
		s6 += float(r6[k])
	ok(r6.size() <= 4 and absf(float(r6.get(5, 0.0)) - 0.15) < 1e-9 and absf(s6 - 1.0) < 1e-9, "(6) a 5th bone at 0.15: %d influences, it is %.3f, sum %.9f" % [r6.size(), float(r6.get(5, 0.0)), s6])
	var r6l := KMeshWPaint.paint_rule({0: 0.4, 1: 0.3, 2: 0.2, 3: 0.1}, 1, 0.9, {0: true})
	var s6l := 0.0
	for k in r6l:
		s6l += float(r6l[k])
	ok(float(r6l.get(0, 0.0)) == 0.4 and absf(float(r6l.get(1, 0.0)) - 0.6) < 1e-9 and absf(s6l - 1.0) < 1e-9, "(6) bone 0 locked at 0.4, bone 1 asked 0.9: gets the 0.6 left (%.3f), bone 0 stays %.3f, sum %.9f" % [float(r6l.get(1, 0.0)), float(r6l.get(0, 0.0)), s6l])

	# (7) UNDO (pure)
	a = arm()
	var un := KMeshUndo.new()
	var cb7: PackedColorArray = a.attr_data(KMeshWPaint.CH_BONES).duplicate()
	var cw7: PackedColorArray = a.attr_data(KMeshWPaint.CH_WEIGHTS).duplicate()
	un.begin(a)
	stroke(a, {"brush": KMeshWPaint.ADD, "bone": H_L, "strength": 0.3, "radius": 0.06}, [Vector3(0.1, 0, 0.05), Vector3(0.2, 0, 0.05), Vector3(0.3, 0, 0.05)])
	un.commit("weight paint")
	var moved: bool = a.attr_data(KMeshWPaint.CH_WEIGHTS) != cw7
	un.undo()
	ok(moved and un.steps.size() == 0 and un.redos.size() == 1 and a.attr_data(KMeshWPaint.CH_BONES) == cb7 and a.attr_data(KMeshWPaint.CH_WEIGHTS) == cw7,
		"(7) one stroke = one undo step; undo restores both channels bit-for-bit")


func click(p: Vector2, alt := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = p
	e.alt_pressed = alt
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame
	e = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = p
	root.push_input(e)
	await idle(2)


func drag(pts: Array) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = pts[0]
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	for k in range(1, pts.size()):
		var mv := InputEventMouseMotion.new()
		mv.position = pts[k]
		mv.relative = pts[k] - pts[k - 1]
		mv.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(mv)
		await process_frame
	e = InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = false
	e.position = pts[pts.size() - 1]
	root.push_input(e)
	await idle(2)


func key(k: int, ctrl := false, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	e.pressed = true
	root.push_input(e)
	await process_frame
	e = e.duplicate()
	e.pressed = false
	root.push_input(e)
	await idle(2)


func shot() -> Image:
	await idle(4)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


## the median colour of the 3 x 3 pixels around p
func px(img: Image, p: Vector2) -> Color:
	var rs := []
	var gs := []
	var bs := []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var c := img.get_pixel(clampi(int(p.x) + dx, 0, img.get_width() - 1), clampi(int(p.y) + dy, 0, img.get_height() - 1))
			rs.append(c.r)
			gs.append(c.g)
			bs.append(c.b)
	rs.sort()
	gs.sort()
	bs.sort()
	return Color(rs[4], gs[4], bs[4])


func cdist(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))


func app_part() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.wp_key = "kwpaint_test"
	m._kmesh_edit_start()
	await idle(2)
	var ed = m.kmed
	KMeshAutoWeights.preview_bind(m)
	var wc: Vector3 = ed.view.global_position
	m._turn_to(0.0, 0.0, 2.4, wc + Vector3(0, 0.12, 0), false)
	await idle(4)
	# (8)
	var line = null
	for t in MeshTools.TOOLS:
		if t["do"] == "op:wpaint":
			line = t
	ok(line != null, "(8) MeshTools has the line 'op:wpaint'")
	if line == null:
		return
	MeshTools.run(line, m)
	await idle(3)
	var ui := KMeshWPaintUI.of(m)
	ok(ui.on and ui.panel.visible and ui.heat_mi != null and ui.heat_mi.mesh != null, "(8) weight paint is on: the panel shows, the heat layer is on the mesh (%s)" % m.ui_status.text)
	var cam: Camera3D = m.cam
	# (9) a click near a bone: a bone whose line's middle is on screen, off the mesh, > 22 px from every other bone's line
	var vs := root.get_visible_rect().size
	var pick := -1
	var pick_p := Vector2.ZERO
	for b in ui.bones:
		var id := int(b["id"])
		for s in ui.bone_segments(id):
			if cam.is_position_behind(s[0]) or cam.is_position_behind(s[1]):
				continue
			var mp := (cam.unproject_position(s[0]) + cam.unproject_position(s[1])) * 0.5
			if mp.x < 300 or mp.y < 80 or mp.x > vs.x - 300 or mp.y > vs.y - 120 or not ed.view.ray_face(cam.project_ray_origin(mp), cam.project_ray_normal(mp)).is_empty():
				continue
			var clear := true
			for b2 in ui.bones:
				if int(b2["id"]) == id:
					continue
				for s2 in ui.bone_segments(int(b2["id"])):
					if KMeshWPaintUI._seg2(mp, cam.unproject_position(s2[0]), cam.unproject_position(s2[1])) < 22.0:
						clear = false
			if clear and id != ui.bone:
				pick = id
				pick_p = mp + Vector2(0, 4)
				break
		if pick >= 0:
			break
	ok(pick >= 0, "(9) found a bone to click on screen ('%s')" % ui.bone_name(pick))
	await click(pick_p)
	ok(ui.bone == pick, "(9) a click 4 px from '%s' made it the active bone (active: '%s')" % [ui.bone_name(pick), ui.bone_name(ui.bone)])
	# the list: the row of the bone with the most weight on the cube
	var target := ui._strongest()
	var row := -1
	for i in ui._list.item_count:
		if int(ui._list.get_item_metadata(i)) == target:
			row = i
	ui._list.select(row)
	ui._list.item_selected.emit(row)
	ok(ui.bone == target, "(9) the list row '%s' made it the active bone" % ui.bone_name(target))
	# (10) the set stroke through the panel's own fields
	ui._brush_opt.select(KMeshWPaint.MODES.find(KMeshWPaint.SET))
	ui._brush_opt.item_selected.emit(KMeshWPaint.MODES.find(KMeshWPaint.SET))
	ui._val_spin.value = 1.0
	ui._str_spin.value = 1.0
	ui._radius_spin.value = 4.0
	ok(ui.brush == KMeshWPaint.SET and ui.value == 1.0 and ui.strength == 1.0 and absf(ui.radius - 0.04) < 1e-9, "(10) the panel set brush %s, value %.2f, strength %.2f, radius %.0f mm" % [ui.brush, ui.value, ui.strength, ui.radius * 1000.0])
	var mesh: KMesh = ed.mesh
	var v := nearest(mesh, Vector3(0, 0, 0.3))
	var wv: Vector3 = ed.view.global_transform * mesh.verts[v]
	var sp := cam.unproject_position(wv)
	var B := ui.bone
	var cb0: PackedColorArray = mesh.attr_data(KMeshWPaint.CH_BONES).duplicate()
	var cw0: PackedColorArray = mesh.attr_data(KMeshWPaint.CH_WEIGHTS).duplicate()
	var n0: int = ed.undo.steps.size()
	var before_v := w(mesh, v, B)
	await click(sp)
	var after_v := w(mesh, v, B)
	ok(after_v >= 0.999 and ed.undo.steps.size() == n0 + 1, "(10) the set stroke at the front centre vertex: '%s' %.4f -> %.4f (bar >= 0.999), %d undo step(s) (bar 1)" % [ui.bone_name(B), before_v, after_v, ed.undo.steps.size() - n0])
	# (11) placement
	m.ui_root.visible = false
	var img := await shot()
	m.ui_root.visible = true
	if DirAccess.dir_exists_absolute("/tmp/claude-0/sp"):
		img.save_png("/tmp/claude-0/sp/kwpaint.png")
	var got := px(img, sp)
	var want := KMeshWPaint.heat_color(after_v)
	ok(cdist(got, want) <= 0.15, "(11) the pixel at the painted vertex is %s, the heat of %.3f is %s (bar: each channel within 0.15)" % [got.to_html(false), after_v, want.to_html(false)])
	var ctl := -1
	for u in mesh.verts.size():
		var q := mesh.verts[u]
		if absf(q.z - 0.3) < 1e-6 and absf(q.x) < 0.29 and absf(q.y) < 0.29 and u != v and w(mesh, u, B) < 0.5:
			ctl = u
			break
	if ctl < 0:
		ok(false, "(11) control: no vertex of the front face has '%s' under 0.5" % ui.bone_name(B))
	else:
		var su := cam.unproject_position(ed.view.global_transform * mesh.verts[ctl])
		var gc := px(img, su)
		var wc_ := KMeshWPaint.heat_color(w(mesh, ctl, B))
		ok(cdist(gc, wc_) <= 0.15 and cdist(gc, Color(1, 0, 0)) > 0.5, "(11) control: vertex %d (weight %.3f) shows %s, its heat %s; %.2f from red (bar > 0.5)" % [ctl, w(mesh, ctl, B), gc.to_html(false), wc_.to_html(false), cdist(gc, Color(1, 0, 0))])
	# a dragged add stroke = one more step
	ui._brush_opt.select(0)
	ui._brush_opt.item_selected.emit(0)
	ui._str_spin.value = 0.3
	ui._radius_spin.value = 6.0
	var pts := []
	for k in 6:
		pts.append(cam.unproject_position(ed.view.global_transform * Vector3(-0.2 + 0.08 * k, -0.15, 0.3)))
	var cw1: PackedColorArray = mesh.attr_data(KMeshWPaint.CH_WEIGHTS).duplicate()
	var cb1: PackedColorArray = mesh.attr_data(KMeshWPaint.CH_BONES).duplicate()
	await drag(pts)
	var cw2: PackedColorArray = mesh.attr_data(KMeshWPaint.CH_WEIGHTS).duplicate()
	var cb2: PackedColorArray = mesh.attr_data(KMeshWPaint.CH_BONES).duplicate()
	ok(ed.undo.steps.size() == n0 + 2 and cw2 != cw1 and ui.wp.dabs >= 4, "(10) a dragged add stroke (%d dabs) is one more undo step (%d after both, bar %d)" % [ui.wp.dabs, ed.undo.steps.size(), n0 + 2])
	await key(KEY_Z, true)
	ok(mesh.attr_data(KMeshWPaint.CH_WEIGHTS) == cw1 and mesh.attr_data(KMeshWPaint.CH_BONES) == cb1, "(10) Ctrl+Z restores the weights before the drag bit-for-bit")
	await key(KEY_Z, true)
	ok(mesh.attr_data(KMeshWPaint.CH_WEIGHTS) == cw0 and mesh.attr_data(KMeshWPaint.CH_BONES) == cb0 and ed.undo.steps.size() == n0, "(10) Ctrl+Z again restores the weights before the set stroke bit-for-bit")
	await key(KEY_Z, true, true)
	await key(KEY_Z, true, true)
	ok(mesh.attr_data(KMeshWPaint.CH_WEIGHTS) == cw2 and mesh.attr_data(KMeshWPaint.CH_BONES) == cb2, "(10) Ctrl+Shift+Z twice redoes both strokes bit-for-bit")
	var su2 := sums(mesh)
	ok(su2["worst"] <= 1e-5 and su2["most"] <= 4, "(10) the cube after painting: sums within %s, at most %d influences" % [String.num_scientific(su2["worst"]), su2["most"]])
	# (12)
	MeshTools.run(line, m)
	await idle(2)
	ok(not ui.on and not ui.panel.visible and ed.view.show_wire and ed.view.show_verts, "(12) the line again turns weight paint off; wire and points are back")


func _init() -> void:
	brush_part()
	await app_part()
	print("KWPAINT TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(1 if fails > 0 else 0)
