class_name BuildChooseArt
extends Node
## THE CHOOSER'S PICTURES (scripts/build_choose.gd): six real renders, one per card, in the start screen's look
## (scripts/start_art.gd): clay #D8DCE3 on graphite, a soft key and a rim light, an orthographic three-quarter camera.
##   house     a Building record (Building.make + add_room + a door + a window + a gable roof) -> Building.to_array_mesh
##   part      a sword solid built with KCad (blade extruded + filleted, guard and grip revolved); a plain mesh sword without KineCAD
##   vehicle   a car: a rounded-box body, a rounded cabin and four cylinder wheels
##   props     three library props (Props.catalogue: crate, barrel-sized box stack, chair), drawn from their solid boxes
##   template  a sword, an axe and a shield, small
##   step      a "STEP" file sheet and a bracket solid (KCad when present, else two boxes)
## CACHE: user://build_choose_art/<kind>_<key>.png, key = the sha256 of this script, the prop table and whether KineCAD is
## there (the part and the bracket differ), so a changed picture is drawn again and an unchanged one is read from disk.
## ASYNC: request_all() reads or draws ONE picture per frame, after the frame that asked: the chooser never waits for it.
## A draw that gives no picture (headless: no renderer) leaves the card on its drawn placeholder and is not retried.

signal changed(kind: String)   # a picture is ready for this card

const KCad := preload("res://scripts/kcad.gd")
const DIR := "user://build_choose_art"
const SIZE := Vector2i(640, 130)
const VER := "bca2"
const KINDS := ["house", "part", "vehicle", "props", "template", "step"]
const BG := Color(0.105, 0.11, 0.125)
const SKIN := Color(0.847, 0.863, 0.89)     # #D8DCE3
const DARK := Color(0.2, 0.21, 0.24)
const FLOOR := Color(0.165, 0.17, 0.19)
const YEL := Color(1.0, 0.78, 0.22)
const VIEW := Vector3(1.9, 0.9, 3.6)        # the start screen's angle: from the front right, a little above

var textures := {}      # kind -> Texture2D
var renders := 0        # pictures drawn this session
var disk_hits := 0      # pictures read from the cache
var _failed := {}
var _busy := false


static func art_key() -> String:
	var src := FileAccess.get_sha256("res://scripts/build_choose_art.gd") + str(KCad.available()) + str(Props.catalogue().size()) + VER
	return src.sha256_text().substr(0, 16)


static func cache_path(kind: String) -> String:
	return "%s/%s_%s.png" % [DIR, kind, art_key()]


func get_art(kind: String) -> Texture2D:
	return textures.get(kind)


func ready_all() -> bool:
	for k in KINDS:
		if not textures.has(k):
			return false
	return true


func request_all() -> void:
	if _busy:
		return
	_busy = true
	for kind in KINDS:
		if textures.has(kind) or _failed.has(kind):
			continue
		var p := cache_path(kind)
		if FileAccess.file_exists(p):
			var img := Image.load_from_file(ProjectSettings.globalize_path(p))
			if img != null and not img.is_empty():
				textures[kind] = ImageTexture.create_from_image(img)
				disk_hits += 1
				changed.emit(kind)
				continue
		if not is_inside_tree():
			break
		await get_tree().process_frame
		var img2 := await draw(kind)
		if img2 == null or img2.is_empty():
			_failed[kind] = true
			continue
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
		img2.save_png(ProjectSettings.globalize_path(p))
		renders += 1
		textures[kind] = ImageTexture.create_from_image(img2)
		changed.emit(kind)
	_busy = false


## one picture, drawn now (two frames); null when it cannot be drawn
func draw(kind: String) -> Image:
	if not KINDS.has(kind):
		return null
	var vp := SubViewport.new()
	vp.name = "choose_art_" + kind
	vp.size = SIZE
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 32, 0)
	key.light_energy = 1.0
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-22, 158, 0)
	rim.light_energy = 0.9
	vp.add_child(rim)
	var content := Node3D.new()
	vp.add_child(content)
	var grounded := true
	match kind:
		"house":
			_house(content)
		"part":
			_sword(content)
			grounded = false
		"vehicle":
			_car(content)
		"props":
			_props(content)
		"template":
			_template(content)
			grounded = false
		"step":
			_step(content)
	var box := _bounds(content, Transform3D.IDENTITY)
	if grounded:
		var fl := _mi(_box_mesh(Vector3(box.size.x * 1.25 + 0.4, 0.04, box.size.z * 1.25 + 0.4)), _mat(FLOOR, 0.9))
		fl.position = Vector3(box.get_center().x, box.position.y - 0.02, box.get_center().z)
		content.add_child(fl)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.05
	cam.far = 80.0
	vp.add_child(cam)
	_frame(cam, box)
	cam.current = true
	await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(vp):
		return null
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img: Image = null
	if is_inside_tree() and is_instance_valid(vp):
		img = vp.get_texture().get_image()
		vp.queue_free()
	return img


# ---------------------------------------------------------------- framing

## the content's box in the viewport's frame (meshes only, through each node's own transform)
func _bounds(n: Node3D, xf: Transform3D) -> AABB:
	var out := AABB()
	var have := false
	for c in n.get_children():
		if not c is Node3D:
			continue
		var cxf: Transform3D = xf * (c as Node3D).transform
		var bb := AABB()
		var got := false
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			bb = cxf * (c as MeshInstance3D).mesh.get_aabb()
			got = true
		var sub := _bounds(c as Node3D, cxf)
		if sub.size != Vector3.ZERO:
			bb = bb.merge(sub) if got else sub
			got = true
		if got:
			out = out.merge(bb) if have else bb
			have = true
	return out


## the orthographic camera that holds the box with a margin: size by the projected extents
func _frame(cam: Camera3D, box: AABB) -> void:
	var dir := VIEW.normalized()
	var basis := Basis.looking_at(-dir, Vector3.UP)
	var inv := basis.inverse()
	var c := box.get_center()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p: Vector3 = inv * (box.get_endpoint(i) - c)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var mid := (lo + hi) * 0.5
	var ex := hi.x - lo.x
	var ey := hi.y - lo.y
	var aspect := float(SIZE.x) / float(SIZE.y)
	cam.size = maxf(ey / 0.84, ex / aspect / 0.9)
	cam.transform = Transform3D(basis, c + basis * Vector3(mid.x, mid.y, 0.0) + dir * 12.0)


# ---------------------------------------------------------------- the pictures

func _house(root: Node3D) -> void:
	var b := Building.make("card")
	var r := Building.add_room(b, 0.0, 0.0, 5.0, 4.0)
	Building.add_opening(b, r, "front", "door", 0.0)
	Building.add_opening(b, r, "right", "window", 0.0)
	Building.set_roof(b, "gable")
	var walls := Building.to_array_mesh(b, ["wall", "floor", "piece"])
	var roof := Building.to_array_mesh(b, ["roof"])
	if walls != null:
		root.add_child(_mi(walls, _mat(SKIN, 0.7)))
	if roof != null:
		root.add_child(_mi(roof, _mat(Color(0.52, 0.55, 0.62), 0.75)))


func _sword(root: Node3D) -> void:
	var mesh: ArrayMesh = _kcad_sword() if KCad.available() else null
	if mesh == null:
		mesh = _plain_sword_mesh()
	var s := _mi(mesh, _mat(SKIN, 0.4))
	var pivot := Node3D.new()
	pivot.rotation_degrees = Vector3(0, 0, -38)
	pivot.add_child(s)
	root.add_child(pivot)


## blade: a flat polygon extruded both ways, then filleted; guard and grip: profiles revolved about the blade's axis
func _kcad_sword() -> ArrayMesh:
	var blade_face := KCad.sketch_face(KCad.polygon(PackedVector2Array([Vector2(-0.05, 0.0), Vector2(0.05, 0.0), Vector2(0.045, 0.78), Vector2(0.0, 0.95), Vector2(-0.045, 0.78)])))
	var blade := KCad.extrude(blade_face, 0.024, true)
	if blade == 0:
		return null
	var soft := KCad.fillet_all(blade, 0.004)
	if soft != 0:
		blade = soft
	var guard_face := KCad.sketch_face(KCad.polygon(PackedVector2Array([Vector2(0, -0.025), Vector2(0.12, -0.025), Vector2(0.13, 0.0), Vector2(0.12, 0.025), Vector2(0, 0.025)])))
	var guard := KCad.revolve(guard_face, Vector3.ZERO, Vector3.UP)
	var grip_face := KCad.sketch_face(KCad.polygon(PackedVector2Array([Vector2(0, -0.32), Vector2(0.034, -0.32), Vector2(0.04, -0.28), Vector2(0.024, -0.25), Vector2(0.022, -0.03), Vector2(0, -0.03)])))
	var grip := KCad.revolve(grip_face, Vector3.ZERO, Vector3.UP)
	if guard == 0 or grip == 0:
		return null
	var all := KCad.union(KCad.union(blade, guard), grip)
	if all == 0:
		return null
	var mesh := KCad.tessellate(all)
	KCad.release(all)
	return mesh


func _plain_sword_mesh() -> ArrayMesh:
	var parts: Array = [[Vector3(0, 0.5, 0), Vector3(0.1, 0.9, 0.024)], [Vector3(0, 0.0, 0), Vector3(0.28, 0.05, 0.05)], [Vector3(0, -0.16, 0), Vector3(0.05, 0.3, 0.05)]]
	return _boxes_mesh(parts)


func _car(root: Node3D) -> void:
	var body := _mi(_rbox(Vector3(2.2, 0.55, 1.0), 4.0), _mat(SKIN, 0.45))
	body.position = Vector3(0, 0.5, 0)
	root.add_child(body)
	var cab := _mi(_rbox(Vector3(1.15, 0.5, 0.88), 3.0), _mat(Color(0.74, 0.77, 0.83), 0.4))
	cab.position = Vector3(-0.12, 0.98, 0)
	root.add_child(cab)
	var glass := _mi(_rbox(Vector3(1.0, 0.3, 0.9), 3.0), _mat(Color(0.12, 0.14, 0.18), 0.15))
	glass.position = Vector3(-0.1, 1.0, 0)
	root.add_child(glass)
	var tyre := _mat(Color(0.09, 0.09, 0.1), 0.85)
	var hub := _mat(Color(0.7, 0.72, 0.78), 0.35)
	for sx in [-0.7, 0.72]:
		for sz in [-0.52, 0.52]:
			var w := CylinderMesh.new()
			w.top_radius = 0.28
			w.bottom_radius = 0.28
			w.height = 0.22
			var wi := _mi(w, tyre)
			wi.rotation_degrees = Vector3(90, 0, 0)
			wi.position = Vector3(sx, 0.28, sz)
			root.add_child(wi)
			var h := CylinderMesh.new()
			h.top_radius = 0.13
			h.bottom_radius = 0.13
			h.height = 0.235
			var hi := _mi(h, hub)
			hi.rotation_degrees = Vector3(90, 0, 0)
			hi.position = Vector3(sx, 0.28, sz)
			root.add_child(hi)
	var lamp := _mi(_rbox(Vector3(0.08, 0.14, 0.24), 3.0), _mat(YEL, 0.3))
	lamp.position = Vector3(1.1, 0.56, 0.3)
	root.add_child(lamp)
	var lamp2 := lamp.duplicate()
	lamp2.position = Vector3(1.1, 0.56, -0.3)
	root.add_child(lamp2)


## three library props, each from its own solid boxes (Props.kind_of): a crate, a barrel (the library has none: a tall rounded drum
## stands in), and a chair
func _props(root: Node3D) -> void:
	var m := _mat(SKIN, 0.7)
	var crate := _prop_node("crate", m)
	crate.position = Vector3(-0.8, 0, 0.0)
	crate.scale = Vector3.ONE * 1.5
	root.add_child(crate)
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.26
	barrel.bottom_radius = 0.26
	barrel.height = 0.8
	var bi := _mi(barrel, _mat(Color(0.62, 0.45, 0.26), 0.8))
	bi.position = Vector3(0.05, 0.4, 0.1)
	root.add_child(bi)
	for y in [0.18, 0.62]:
		var ring := CylinderMesh.new()
		ring.top_radius = 0.275
		ring.bottom_radius = 0.275
		ring.height = 0.05
		var ri := _mi(ring, _mat(Color(0.3, 0.3, 0.33), 0.5))
		ri.position = Vector3(0.05, y, 0.1)
		root.add_child(ri)
	var chair := _prop_node("chair", m)
	chair.position = Vector3(0.95, 0, 0.05)
	chair.rotation_degrees = Vector3(0, -28, 0)
	chair.scale = Vector3.ONE * 1.5
	root.add_child(chair)


func _prop_node(kind: String, mat: Material) -> Node3D:
	var n := Node3D.new()
	if not Props.has_kind(kind):
		return n
	for s in Props.kind_of(kind)["solids"]:
		var mi := _mi(_box_mesh(s[1]), mat)
		mi.position = s[0]
		n.add_child(mi)
	return n


func _template(root: Node3D) -> void:
	var m := _mat(SKIN, 0.45)
	var sw := _mi(_boxes_mesh([[Vector3(0, 0.5, 0), Vector3(0.1, 0.8, 0.025)], [Vector3(0, 0.08, 0), Vector3(0.3, 0.05, 0.06)], [Vector3(0, -0.08, 0), Vector3(0.05, 0.27, 0.05)]]), m)
	sw.position = Vector3(-1.05, 0.0, 0.0)
	root.add_child(sw)
	var axe := Node3D.new()
	axe.position = Vector3(0.0, 0.0, 0.0)
	var haft := CylinderMesh.new()
	haft.top_radius = 0.035
	haft.bottom_radius = 0.035
	haft.height = 1.1
	var hi := _mi(haft, _mat(Color(0.62, 0.45, 0.26), 0.8))
	hi.position = Vector3(0, 0.45, 0)
	axe.add_child(hi)
	var head := _mi(_wedge_mesh(), m)
	head.position = Vector3(0.0, 0.78, 0)
	axe.add_child(head)
	root.add_child(axe)
	var shield := Node3D.new()
	shield.position = Vector3(1.05, 0.45, 0.0)
	shield.rotation_degrees = Vector3(90, 0, 0)
	var disc := CylinderMesh.new()
	disc.top_radius = 0.36
	disc.bottom_radius = 0.36
	disc.height = 0.06
	var di := _mi(disc, m)
	shield.add_child(di)
	var rimm := CylinderMesh.new()
	rimm.top_radius = 0.38
	rimm.bottom_radius = 0.38
	rimm.height = 0.035
	var rimi := _mi(rimm, _mat(Color(0.52, 0.55, 0.62), 0.5))
	rimi.position = Vector3(0, -0.02, 0)
	shield.add_child(rimi)
	var boss := SphereMesh.new()
	boss.radius = 0.11
	boss.height = 0.16
	var bi := _mi(boss, _mat(YEL, 0.35))
	bi.position = Vector3(0, 0.05, 0)
	shield.add_child(bi)
	root.add_child(shield)


func _step(root: Node3D) -> void:
	var sheet := Node3D.new()
	sheet.position = Vector3(-0.9, 0.0, 0.0)
	var page := _mi(_box_mesh(Vector3(0.62, 0.8, 0.04)), _mat(Color(0.93, 0.93, 0.95), 0.8))
	page.position = Vector3(0, 0.4, 0)
	sheet.add_child(page)
	var band := _mi(_box_mesh(Vector3(0.62, 0.2, 0.045)), _mat(YEL, 0.6))
	band.position = Vector3(0, 0.38, 0)
	sheet.add_child(band)
	var tx := Label3D.new()
	tx.text = "STEP"
	tx.font_size = 96
	tx.pixel_size = 0.0022
	tx.modulate = Color(0.1, 0.1, 0.1)
	tx.outline_size = 0
	tx.position = Vector3(0, 0.38, 0.03)
	sheet.add_child(tx)
	for y in [0.64, 0.12]:
		var ln := _mi(_box_mesh(Vector3(0.4, 0.025, 0.045)), _mat(Color(0.62, 0.64, 0.7), 0.8))
		ln.position = Vector3(0, y, 0)
		sheet.add_child(ln)
	root.add_child(sheet)
	var br: ArrayMesh = _kcad_bracket() if KCad.available() else null
	if br == null:
		br = _boxes_mesh([[Vector3(0.25, 0.04, 0.15), Vector3(0.5, 0.08, 0.3)], [Vector3(0.04, 0.25, 0.15), Vector3(0.08, 0.5, 0.3)]])
	var bi := _mi(br, _mat(SKIN, 0.4))
	bi.position = Vector3(0.2, 0.0, -0.1)
	bi.scale = Vector3.ONE * 1.35
	root.add_child(bi)


## an L bracket: a profile extruded, filleted, with a bolt hole through the foot
func _kcad_bracket() -> ArrayMesh:
	var face := KCad.sketch_face(KCad.polygon(PackedVector2Array([Vector2(0, 0), Vector2(0.5, 0), Vector2(0.5, 0.08), Vector2(0.08, 0.08), Vector2(0.08, 0.5), Vector2(0, 0.5)])))
	var solid := KCad.extrude(face, 0.3)
	if solid == 0:
		return null
	var hole := KCad.translate(KCad.cylinder(0.04, 0.4), Vector3(0.3, -0.1, 0.15))
	var holed := KCad.cut(solid, hole) if hole != 0 else 0
	if holed != 0:
		solid = holed
	var soft := KCad.fillet_all(solid, 0.012)
	if soft != 0:
		solid = soft
	var mesh := KCad.tessellate(solid)
	KCad.release(solid)
	return mesh


# ---------------------------------------------------------------- helpers

func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # the hand-built meshes need not agree on winding
	return m


func _mi(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi


func _box_mesh(size: Vector3) -> BoxMesh:
	var bm := BoxMesh.new()
	bm.size = size
	return bm


## boxes [[centre, size], ...] as one mesh
func _boxes_mesh(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in parts:
		var bm := BoxMesh.new()
		bm.size = p[1]
		var arr := bm.get_mesh_arrays()
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for i in ix:
			st.set_normal(ns[i])
			st.add_vertex(vs[i] + (p[0] as Vector3))
	return st.commit()


## a rounded box: a UV sphere pushed out to a superellipsoid (exponent 2 = ellipsoid, higher = boxier)
func _rbox(size: Vector3, n: float) -> ArrayMesh:
	var rings := 18
	var segs := 28
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := []
	for i in rings + 1:
		var th := PI * float(i) / float(rings)
		var row := []
		for j in segs + 1:
			var ph := TAU * float(j) / float(segs)
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var q := Vector3(signf(d.x) * pow(absf(d.x), 2.0 / n), signf(d.y) * pow(absf(d.y), 2.0 / n), signf(d.z) * pow(absf(d.z), 2.0 / n))
			row.append(q * size * 0.5)
		pts.append(row)
	for i in rings:
		for j in segs:
			var a: Vector3 = pts[i][j]
			var b: Vector3 = pts[i + 1][j]
			var c: Vector3 = pts[i + 1][j + 1]
			var d2: Vector3 = pts[i][j + 1]
			for v in [a, c, b, a, d2, c]:
				st.add_vertex(v)
	st.generate_normals()
	return st.commit()


## an axe head: a flat wedge, thick at the haft, thin at the edge
func _wedge_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z := 0.03
	var poly := [Vector2(0.0, 0.2), Vector2(0.0, -0.2), Vector2(0.3, -0.3), Vector2(0.36, 0.0), Vector2(0.3, 0.3)]
	for s in [1.0, -1.0]:
		for i in range(1, poly.size() - 1):
			var tri := [poly[0], poly[i], poly[i + 1]] if s > 0.0 else [poly[0], poly[i + 1], poly[i]]
			for p in tri:
				st.add_vertex(Vector3(p.x, p.y, z * s))
	for i in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		for v in [Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(b.x, b.y, -z), Vector3(a.x, a.y, z), Vector3(b.x, b.y, -z), Vector3(a.x, a.y, -z)]:
			st.add_vertex(v)
	st.generate_normals()
	return st.commit()
