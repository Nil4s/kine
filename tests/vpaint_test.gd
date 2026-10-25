## godot --path . -s tests/vpaint_test.gd     (ROADMAP_400 E04; needs a window: real mouse / key events, pixels read back)
## Vertex paint (scripts/kmesh_vpaint.gd core, kmesh_vpaint_ui.gd mode). Bars:
##   1 DAB: on a 0.6 m cube (4 x 4 quads a side), one strength-1 mix dab of radius 0.2 m at a vertex: that vertex's every
##     corner == the colour EXACTLY; every vertex within the radius == white * (1 - w) + c * w with w = 1 - (3t^2 - 2t^3),
##     t = d / r (the smooth curve, written out here, not read from the code) within 1e-6, at least 2 of them partial
##     (0 < w < 1); every vertex outside the radius still exactly white. The same with the linear curve (w = 1 - t).
##   2 BLEND: on known values (exact in float32): add (0.25, 0.5, 0.75) + (0.5, 0.25, 0.125) = (0.75, 0.75, 0.875) and
##     multiply by 0.5 = (0.125, 0.25, 0.375) at the dabbed vertex, exactly; blend() at w = 0.5: add d + c / 2, subtract,
##     lighten, darken exact; add clamps at 1
##   3 X SYMMETRY: a dab at a vertex with x > 0: its mirror partner (x < 0) gets the same colour exactly, every vertex
##     equals its partner, and the partner side was painted (not white)
##   4 UNDO: a 5-point stroke inside KMeshUndo.begin / commit is ONE step; undo restores the channel exactly, redo re-paints
##   5 SAVE / LOAD: .kmesh round trip keeps the channel (corner domain, every value exactly)
##   6 GLB: export_glb writes COLOR_0 on the primitive (read from the file's JSON chunk), and read back through
##     GLTFDocument every vertex's colour equals the painted vertex colour at its position within ONE 8-bit step (1/255):
##     Godot's ArrayMesh stores vertex colours as RGBA8, so the exporter writes them quantised (every value read back is
##     checked to sit on the n/255 grid, so the error is that format and nothing else)
##   8 pen pressure 0.5 at the centre = a half mix exactly; FILL of one selected face writes its 4 corners only (a hard edge:
##     every other corner, the neighbours' corners at the shared verts included, stays white); a BLUR dab at w = 1 takes
##     the vertex to its edge neighbours' mean colour (within 1e-6), which differed from it by > 0.05 before
##   7 APP: the S box line "Model: vertex paint on / off" opens the model preview and paint mode (panel shown); a real click
##     on the front face's centre vertex is one undo step and paints it green; PLACEMENT: the pixel at that vertex (9, 5 px
##     off it, inside the face: the vertex's own point and the wire are drawn on it) is green
##     (g > r + 0.25, g > b + 0.25; it was not before) and a vertex 0.3 m away keeps its pixel (< 0.03); Ctrl+click is the
##     eyedropper (picks the green back); Ctrl+Z (real key) restores the vertex to white exactly; Esc leaves paint mode
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


func mouse(p: Vector2, down: bool, ctrl := false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = p
	e.global_position = p
	e.ctrl_pressed = ctrl
	if down:
		e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
	await process_frame


func key(k: int, ctrl := false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k
		e.physical_keycode = k
		e.ctrl_pressed = ctrl
		e.pressed = down
		root.push_input(e)
		await process_frame
	await idle(2)


func shot() -> Image:
	await idle(4)
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func dist(a: Color, b: Color) -> float:
	return sqrt(pow(a.r - b.r, 2) + pow(a.g - b.g, 2) + pow(a.b - b.b, 2))


static func cdiff(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), maxf(absf(a.b - b.b), absf(a.a - b.a)))


func cube() -> KMesh:
	var k := KMeshView.make_cube(0.6, 4)
	KMeshVPaint.ensure(k)
	return k


## the vertex nearest p
func near(k: KMesh, p: Vector3) -> int:
	var best := -1
	var bd := INF
	for v in k.verts.size():
		var d := k.verts[v].distance_squared_to(p)
		if d < bd:
			bd = d
			best = v
	return best


## every corner of v equals c exactly
func corners_are(k: KMesh, v: int, c: Color) -> bool:
	var cm := KMeshVPaint.corner_map(k)
	var d: PackedColorArray = k.attr_data(KMeshVPaint.CH)
	for i in range(cm[0][v], cm[0][v + 1]):
		if d[cm[1][i]] != c:
			return false
	return cm[0][v + 1] > cm[0][v]


func dab_bar(curve: String) -> void:
	var k := cube()
	var c := Color(0.2, 0.6, 0.9, 1.0)
	var r := 0.2
	var v0 := near(k, Vector3(0.0, 0.0, 0.3))   # the front face's centre vertex
	var vp := KMeshVPaint.new()
	vp.begin(k, {"color": c, "mode": KMeshVPaint.MIX, "strength": 1.0, "radius": r, "falloff": curve})
	vp.dab(k.verts[v0], 1.0)
	var exact := corners_are(k, v0, c)
	var worst := 0.0
	var partial := 0
	var outside_white := true
	var outside := 0
	var cm := KMeshVPaint.corner_map(k)
	for v in k.verts.size():
		var t := k.verts[v].distance_to(k.verts[v0]) / r
		var col := KMeshVPaint.vert_color(k, v, cm)
		if t >= 1.0:
			outside += 1
			outside_white = outside_white and corners_are(k, v, Color.WHITE)
			continue
		var w := 1.0 - (3.0 * t * t - 2.0 * t * t * t) if curve == KMeshSculpt.F_SMOOTH else 1.0 - t
		var want := Color(1.0 - w + c.r * w, 1.0 - w + c.g * w, 1.0 - w + c.b * w, 1.0)
		worst = maxf(worst, cdiff(col, want))
		if w > 0.0 and w < 1.0:
			partial += 1
	ok(exact and worst < 1e-6 and partial >= 2 and outside_white and outside > 50,
		"(1) %s dab: centre vertex exactly the colour %s; %d partial verts follow the curve (worst %s); %d verts outside the radius all still white %s" % [curve, exact, partial, str(worst), outside, outside_white])


func _init() -> void:
	# 1 dab
	dab_bar(KMeshSculpt.F_SMOOTH)
	dab_bar(KMeshSculpt.F_LINEAR)
	# 2 blend modes on known values
	var k := cube()
	var v0 := near(k, Vector3(0.0, 0.0, 0.3))
	var base := Color(0.25, 0.5, 0.75, 1.0)
	var d: PackedColorArray = k.attr_data(KMeshVPaint.CH)
	d.fill(base)
	k.set_attr_data(KMeshVPaint.CH, d)
	var vp := KMeshVPaint.new()
	vp.begin(k, {"color": Color(0.5, 0.25, 0.125, 1.0), "mode": KMeshVPaint.ADD, "strength": 1.0, "radius": 0.05})
	vp.dab(k.verts[v0])
	var add_ok := corners_are(k, v0, Color(0.75, 0.75, 0.875, 1.0))
	d = k.attr_data(KMeshVPaint.CH)
	d.fill(base)
	k.set_attr_data(KMeshVPaint.CH, d)
	vp.begin(k, {"color": Color(0.5, 0.5, 0.5, 1.0), "mode": KMeshVPaint.MUL, "strength": 1.0, "radius": 0.05})
	vp.dab(k.verts[v0])
	var mul_ok := corners_are(k, v0, Color(0.125, 0.25, 0.375, 1.0))
	var cc := Color(0.5, 0.25, 0.125, 1.0)
	var half := [KMeshVPaint.blend(KMeshVPaint.ADD, base, cc, 0.5) == Color(0.5, 0.625, 0.8125, 1.0),
		KMeshVPaint.blend(KMeshVPaint.SUB, base, cc, 1.0) == Color(0.0, 0.25, 0.625, 1.0),
		KMeshVPaint.blend(KMeshVPaint.LIGHTEN, base, cc, 1.0) == Color(0.5, 0.5, 0.75, 1.0),
		KMeshVPaint.blend(KMeshVPaint.DARKEN, base, cc, 1.0) == Color(0.25, 0.25, 0.125, 1.0),
		KMeshVPaint.blend(KMeshVPaint.ADD, Color(0.75, 0.75, 0.75), Color(0.5, 0.5, 0.5), 1.0) == Color(1, 1, 1, 1)]
	ok(add_ok and mul_ok and not half.has(false), "(2) blend: add exact %s, multiply exact %s; half add / subtract / lighten / darken / add clamp %s" % [add_ok, mul_ok, half])
	# 3 X symmetry
	k = cube()
	var vs := near(k, Vector3(0.15, 0.15, 0.3))
	var sym := k.symmetry_map(0, 1e-4)
	vp.begin(k, {"color": Color(1.0, 0.0, 0.5, 1.0), "strength": 1.0, "radius": 0.2, "sym_x": true})
	vp.dab(k.verts[vs])
	var cm := KMeshVPaint.corner_map(k)
	var pv := sym[vs]
	var same := pv >= 0 and pv != vs and KMeshVPaint.vert_color(k, vs, cm) == KMeshVPaint.vert_color(k, pv, cm) and corners_are(k, pv, Color(1.0, 0.0, 0.5, 1.0))
	var all_match := true
	for v in k.verts.size():
		if sym[v] >= 0 and KMeshVPaint.vert_color(k, v, cm) != KMeshVPaint.vert_color(k, sym[v], cm):
			all_match = false
	ok(same and all_match and k.verts[pv].x < 0.0, "(3) X symmetry: vertex %d (x %.2f) and its partner %d (x %.2f) the same colour exactly %s; every vertex equals its partner %s" % [vs, k.verts[vs].x, pv, k.verts[pv].x, same, all_match])
	# 4 undo
	k = cube()
	var un := KMeshUndo.new()
	var before: PackedColorArray = k.attr_data(KMeshVPaint.CH).duplicate()
	un.begin(k)
	vp.begin(k, {"color": Color(0.1, 0.8, 0.2, 1.0), "strength": 0.7, "radius": 0.15})
	for i in 5:
		vp.to(Vector3(-0.2 + 0.1 * i, 0.05, 0.3), 0.6 + 0.1 * i)
	vp.end()
	un.commit("vertex paint mix")
	var after: PackedColorArray = k.attr_data(KMeshVPaint.CH).duplicate()
	var steps := un.steps.size()
	un.undo()
	var back: bool = k.attr_data(KMeshVPaint.CH) == before
	un.redo()
	var again: bool = k.attr_data(KMeshVPaint.CH) == after
	ok(steps == 1 and after != before and back and again and vp.dabs > 5, "(4) undo: a %d-dab stroke is %d step; undo exact %s, redo exact %s" % [vp.dabs, steps, back, again])
	# 5 save / load
	var path := "user://vpaint_test.kmesh"
	var err := k.save(path)
	var k2 := KMesh.load_file(path)
	var rt: bool = err == OK and k2 != null and k2.has_attr(KMeshVPaint.CH) and k2.attr_info(KMeshVPaint.CH)["domain"] == KMesh.AD_CORNER and k2.attr_data(KMeshVPaint.CH) == after
	ok(rt, "(5) save / load: %d corner colours back exactly %s (%s)" % [after.size(), rt, KMesh.last_error])
	# 6 glb
	var gp := "user://vpaint_test.glb"
	var ge := KMeshVPaint.export_glb(k, gp)
	var has_c0 := false
	var raw := FileAccess.get_file_as_bytes(gp)
	if raw.size() > 20:
		var jl := raw.decode_u32(12)
		var js = JSON.parse_string(raw.slice(20, 20 + jl).get_string_from_utf8())
		if js is Dictionary:
			for me in js.get("meshes", []):
				for pr in me.get("primitives", []):
					has_c0 = has_c0 or (pr.get("attributes", {}) as Dictionary).has("COLOR_0")
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var worst := INF
	var nread := 0
	var painted := 0
	var on_grid := true
	if doc.append_from_file(ProjectSettings.globalize_path(gp), st) == OK:
		var sc := doc.generate_scene(st)
		var mis := sc.find_children("*", "MeshInstance3D", true, false)
		if not mis.is_empty():
			var arr := ((mis[0] as MeshInstance3D).mesh as Mesh).surface_get_arrays(0)
			var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var col = arr[Mesh.ARRAY_COLOR]
			if col is PackedColorArray and (col as PackedColorArray).size() == pos.size():
				worst = 0.0
				var cm2 := KMeshVPaint.corner_map(k)
				for i in pos.size():
					var kv := near(k, pos[i])
					var want := KMeshVPaint.vert_color(k, kv, cm2)
					worst = maxf(worst, cdiff(col[i], want))
					for ch in 4:   # Godot's ArrayMesh keeps COLOR as RGBA8: every value read back sits on the n / 255 grid
						on_grid = on_grid and absf(col[i][ch] * 255.0 - roundf(col[i][ch] * 255.0)) < 1e-3
					if want != Color.WHITE:
						painted += 1
				nread = pos.size()
		sc.free()
	ok(ge == OK and has_c0 and nread > 0 and worst <= 1.0 / 255.0 + 1e-6 and on_grid and painted > 0,
		"(6) glb: written %s, COLOR_0 in the file %s; read back %d verts (%d painted), worst colour error %s (one 8-bit step = %s: the engine's mesh colour format, every value on the n/255 grid %s)" % [ge == OK, has_c0, nread, painted, str(worst), str(1.0 / 255.0), on_grid])
	# 8 pressure, fill, blur
	k = cube()
	v0 = near(k, Vector3(0.0, 0.0, 0.3))
	vp.begin(k, {"color": Color(0.0, 0.0, 0.0, 1.0), "strength": 1.0, "radius": 0.05})
	vp.dab(k.verts[v0], 0.5)
	var press_ok := corners_are(k, v0, Color(0.5, 0.5, 0.5, 1.0))
	var sel := KMeshSelect.new(k, KMeshSelect.FACE)
	var f0: int = k.vert_faces(v0)[0]
	sel.faces[f0] = true
	d = k.attr_data(KMeshVPaint.CH)
	d.fill(Color.WHITE)
	k.set_attr_data(KMeshVPaint.CH, d)
	var nfill := KMeshVPaint.fill(k, sel, Color(0.0, 0.0, 1.0, 1.0))
	d = k.attr_data(KMeshVPaint.CH)
	var hard := true
	for fi in k.face_count():
		var fp: PackedInt32Array = k.faces[fi]
		for i in fp.size():
			var want := Color(0.0, 0.0, 1.0, 1.0) if fi == f0 else Color.WHITE
			hard = hard and d[k.face_he0[fi] + i] == want
	cm = KMeshVPaint.corner_map(k)
	var nb := k.vert_neighbors(v0)
	var mean := Color(0, 0, 0, 0)
	for u in nb:
		var cu := KMeshVPaint.vert_color(k, u, cm)
		mean = Color(mean.r + cu.r / nb.size(), mean.g + cu.g / nb.size(), mean.b + cu.b / nb.size(), mean.a + cu.a / nb.size())
	var c_before := KMeshVPaint.vert_color(k, v0, cm)
	vp.begin(k, {"blur": true, "strength": 1.0, "radius": 0.05})
	vp.dab(k.verts[v0])
	var blurred := KMeshVPaint.vert_color(k, v0, KMeshVPaint.corner_map(k))
	ok(press_ok and nfill == 4 and hard and cdiff(blurred, mean) < 1e-6 and cdiff(c_before, mean) > 0.05,
		"(8) pen pressure 0.5 = a half mix exactly %s; fill of 1 selected face wrote its %d corners only, a hard edge (every other corner white) %s; a blur dab takes the vertex from %s to its neighbours' mean %s (got %s)" % [press_ok, nfill, hard, c_before, mean, blurred])
	await app_bars()
	print("VPAINT ", "PASS" if fails == 0 else "FAIL %d" % fails)
	TestFiles.cleanup()
	quit(1 if fails else 0)


func app_bars() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var line: Dictionary = {}
	for t in MeshTools.TOOLS:
		if t["id"] == "mesh_vpaint":
			line = t
	MeshTools.run(line, m)
	await idle(4)
	var pu := KMeshVPaintUI.of(m)
	var ui = m.kmed
	ok(ui != null and ui.on and pu.on and pu.panel.visible and pu.mesh == ui.mesh and ui.mesh.has_attr(KMeshVPaint.CH),
		"(7a) the S box line opens the model preview and paint mode (panel shown %s): %s" % [pu.panel.visible, String(m.ui_status.text).left(160)])
	var wc: Vector3 = ui.view.global_position
	m._turn_to(0.0, 0.0, 1.6, wc, false)
	await idle(6)
	var cam: Camera3D = m.cam
	# the visible vertex nearest the cube's projected centre: the centre of the face toward the camera
	var cs := cam.unproject_position(wc)
	var v0 := -1
	var bd := INF
	for v in ui.mesh.verts.size():
		var wp: Vector3 = ui.view.global_transform * ui.mesh.verts[v]
		if not ui.view.point_visible(cam, wp):
			continue
		var dd := cam.unproject_position(wp).distance_to(cs)
		if dd < bd:
			bd = dd
			v0 = v
	var w0: Vector3 = ui.view.global_transform * ui.mesh.verts[v0]
	var s0 := cam.unproject_position(w0)
	# a far vertex on the same face: 0.3 m away (two grid steps), its pixel must not change
	var vf := -1
	for v in ui.mesh.verts.size():
		var wp: Vector3 = ui.view.global_transform * ui.mesh.verts[v]
		if absf(wp.distance_to(w0) - 0.3) < 1e-4 and ui.view.point_visible(cam, wp):
			vf = v
			break
	var sf := cam.unproject_position(ui.view.global_transform * ui.mesh.verts[vf])
	pu.color = Color(0.0, 1.0, 0.0, 1.0)
	pu.radius = 0.06
	pu.strength = 1.0
	pu.mode = KMeshVPaint.MIX
	pu.falloff = KMeshSculpt.F_SMOOTH
	m.ui_root.visible = false
	var img0 := await shot()
	var off := Vector2(9, 5)   # inside the face beside the vertex: off its drawn point (5 px) and the wire lines through it
	var p0 := img0.get_pixelv(Vector2i((s0 + off).round()))
	var pf0 := img0.get_pixelv(Vector2i((sf + off).round()))
	m.ui_root.visible = true
	var n_steps: int = ui.undo.steps.size()
	await mouse(s0, true)
	await mouse(s0, false)
	await idle(3)
	var cm := KMeshVPaint.corner_map(ui.mesh)
	var vc := KMeshVPaint.vert_color(ui.mesh, v0, cm)
	var one_step: bool = ui.undo.steps.size() == n_steps + 1
	m.ui_root.visible = false
	var img1 := await shot()
	img1.save_png("user://vpaint.png")
	var p1 := img1.get_pixelv(Vector2i((s0 + off).round()))
	var pf1 := img1.get_pixelv(Vector2i((sf + off).round()))
	m.ui_root.visible = true
	var green := p1.g > p1.r + 0.25 and p1.g > p1.b + 0.25
	var was := p0.g > p0.r + 0.25 and p0.g > p0.b + 0.25
	ok(one_step and vc.g > 0.95 and vc.r < 0.05 and vc.b < 0.05,
		"(7b) a real click on vertex %d painted it %s, one undo step %s" % [v0, vc, one_step])
	ok(green and not was and dist(pf0, pf1) < 0.03,
		"(7c) PLACEMENT: pixel at the dab %s: before %s, after %s (green %s), a vertex 0.3 m away keeps its pixel (diff %.3f) (shot %s)" % [Vector2i((s0 + off).round()), p0, p1, green, dist(pf0, pf1), ProjectSettings.globalize_path("user://vpaint.png")])
	# eyedropper
	pu.color = Color(0.3, 0.3, 0.3, 1.0)
	await mouse(s0, true, true)
	await mouse(s0, false, true)
	await idle(2)
	var picked := pu.color
	ok(picked.g > 0.95 and picked.r < 0.05 and ui.undo.steps.size() == n_steps + 1, "(7d) Ctrl+click eyedropper picked %s (no undo step added)" % picked)
	await key(KEY_Z, true)
	await idle(2)
	var undone := corners_are(ui.mesh, v0, Color.WHITE)
	ok(undone, "(7e) Ctrl+Z restores the vertex to white exactly %s" % undone)
	await key(KEY_ESCAPE)
	ok(not pu.on and not pu.panel.visible and ui.on, "(7f) Esc leaves paint mode (model preview still open %s)" % ui.on)
