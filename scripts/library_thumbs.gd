class_name LibraryThumbs
extends Node
## LIBRARY PICTURES (the object library's tiles, scripts/object_library.gd). Each object is drawn from its REAL mesh, the one the
## app places: a weapon's cylinders (the same shapes main.gd draws on the hand, Body.KINDS), a prop's own mesh (Props.mesh of
## Props.make), an armour plate built on the fighter's body (ArmourFromBody.build), a user model's imported scene (Props.mesh).
## The picture is 128 x 128, the theme's dark background, a three-quarter view from the front right and above, the object
## framed so its projected extent fills FILL (80 %) of the longer side, one key light and a fill light.
##
## THE OLD SCHEMATIC FIRST: a tile shows the schematic bar (the shapes of Props.kind_of / Body.KINDS, 64 px) until the real
## picture is ready; a real picture on disk shows at once and no schematic is drawn.
##
## CACHE: user://thumbs/lib/<id with ":" as "_">_<hash16>_128.png for a real picture, where the hash is of VERSION + the
## object's spec (the data its mesh is built from: Body.KINDS entry, Props.kind_of entry, the armour's words and constants).
## A changed spec or a new VERSION is a new name; the old file is left alone. The schematic keeps its old name
## user://thumbs/lib/<sha256 of the shapes>_64.png. A draw that gives no picture (headless: no renderer) is not retried this session.
##
## DRAWING: one SubViewport with its own world, one object per frame, after the frame that asked, so the panel never waits.
## A shape is one of: ["box", centre, size], ["ball", centre, radius], ["cyl", centre, height, radius] (Vector3 / float).

signal made(id: String)   # a picture is ready for this object (memory, disk or drawn); the real one replaces the schematic

const SIZE := Vector2i(128, 128)     # the real picture
const SCHEM := Vector2i(64, 64)      # the schematic bar (the old picture)
const DIR := "user://thumbs/lib"
const VERSION := "1"                 # bump when the drawing changes: every real picture is drawn again
const FILL := 0.8                    # the object's projected extent is this share of the picture's longer side
const DIR_TO_CAMERA := Vector3(0.45, 0.25, 1.0)   # from the front, right and above: the three-quarter view

var renders := 0        # pictures drawn this session, schematic and real (the test counts them)
var real_renders := 0   # the real pictures among them
var disk_hits := 0      # pictures read from the cache without a draw
var build_ms_max := 0.0 # the longest real mesh build (main thread), ms
var draw_ms_max := 0.0  # the longest real draw (build excluded), ms
var failed_real: Array = []  # the real pictures that came out empty (their paths)
var _tex := {}          # id -> ImageTexture (the real one once it is ready)
var _asked := {}        # id -> true: asked once; a picture is drawn or read once per session, however many tiles ask
var _failed := {}       # cache path -> true: no picture came out of a draw (headless: no renderer)
var _queue: Array = []  # [{"id", "src"}]
var _busy := false
var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _mat: StandardMaterial3D


## the cache name of a schematic picture (its shapes' hash)
static func cache_path(sha: String) -> String:
	return "%s/%s_%d.png" % [DIR, sha, SCHEM.x]


static func key_of(shapes: Array) -> String:
	return JSON.stringify(shapes).sha256_text()


## the cache name of a real picture: the id (":" is not a file name character) and the hash of VERSION + spec
static func real_path(id: String, spec: String) -> String:
	return "%s/%s_%s_%d.png" % [DIR, id.replace(":", "_"), (VERSION + spec).sha256_text().left(16), SIZE.x]


static func abs_path(p: String) -> String:
	return ProjectSettings.globalize_path(p)


## the picture of an object if it is at hand, else null
func picture(id: String) -> Texture2D:
	return _tex.get(id)


## ask for an object's picture; made(id) says when it is there. src: {"shapes": schematic shapes, "spec": String ("" = no real
## mesh), "build": Callable -> Node3D (the real mesh, built on the main thread; null when it cannot be built)}.
## An object already asked for is not asked twice.
func request(id: String, src: Dictionary) -> void:
	if _asked.has(id):
		return
	_asked[id] = true
	_queue.append({"id": id, "src": src})
	_pump()


func _frame() -> Signal:
	return (Engine.get_main_loop() as SceneTree).process_frame


func _pump() -> void:
	if _busy:
		return
	_busy = true
	await _frame()   # never on the frame that asked
	while not _queue.is_empty():
		var q: Dictionary = _queue.pop_front()
		var id: String = q["id"]
		var src: Dictionary = q["src"]
		var spec := String(src.get("spec", ""))
		var real := real_path(id, spec) if spec != "" else ""
		if real != "" and FileAccess.file_exists(abs_path(real)):
			var disk := Image.load_from_file(abs_path(real))
			if disk != null and not disk.is_empty():
				disk_hits += 1
				_show_picture(id, disk)
				await _frame()
				continue
		if not _tex.has(id):   # the schematic first, until the real one is ready
			var sch := await _schematic(src.get("shapes", []))
			if not is_instance_valid(self):
				return
			if sch != null and not sch.is_empty():
				_show_picture(id, sch)
		if real != "" and not _failed.has(real) and src.get("build") is Callable and (src["build"] as Callable).is_valid():
			var t0 := Time.get_ticks_usec()
			var node: Node3D = (src["build"] as Callable).call()
			build_ms_max = maxf(build_ms_max, (Time.get_ticks_usec() - t0) / 1000.0)
			var img: Image = null
			if node != null:
				t0 = Time.get_ticks_usec()
				img = await draw_node(node, SIZE)
				draw_ms_max = maxf(draw_ms_max, (Time.get_ticks_usec() - t0) / 1000.0)
				if not is_instance_valid(self):
					return
			if img != null and not img.is_empty():
				_write(img, real)
				renders += 1
				real_renders += 1
				_show_picture(id, img)
			else:
				_failed[real] = true
				failed_real.append(real)
		await _frame()
	_busy = false


## the one writer of this file: a picture under user://thumbs/lib (the folder made first)
func _write(img: Image, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(abs_path(DIR))
	img.save_png(abs_path(path))


func _show_picture(id: String, img: Image) -> void:
	_tex[id] = ImageTexture.create_from_image(img)
	made.emit(id)


## wait until every asked picture is done (tests)
func settle() -> void:
	while _busy or not _queue.is_empty():
		await _frame()


## the schematic bar of some shapes: from its cache, else drawn (null when it cannot be)
func _schematic(shapes: Array) -> Image:
	if shapes.is_empty():
		return null
	var path := cache_path(key_of(shapes))
	if FileAccess.file_exists(abs_path(path)):
		var img := Image.load_from_file(abs_path(path))
		if img != null and not img.is_empty():
			disk_hits += 1
			return img
	if _failed.has(path):
		return null
	var img2 := await draw_node(shapes_node(shapes), SCHEM)
	if img2 == null or img2.is_empty():
		_failed[path] = true
		return null
	_write(img2, path)
	renders += 1
	return img2


## a schematic: one mesh per shape (the old bar of the object)
func shapes_node(shapes: Array) -> Node3D:
	_stage()
	var root := Node3D.new()
	for s in shapes:
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh(s)
		mi.material_override = _mat
		mi.position = s[1]
		root.add_child(mi)
	return root


## the real mesh of a weapon: the cylinders main.gd draws on the hand (knob, tape handle, metal barrel; a hammer or axe head
## across the tip; a staff with no knob; two daggers side by side), from Body.KINDS
static func weapon_node(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = kind
	if kind == "two_daggers":
		var a := weapon_node("dagger")
		a.position = Vector3(-0.05, 0.0, 0.0)
		var b := weapon_node("dagger")
		b.position = Vector3(0.05, 0.0, 0.0)
		root.add_child(a)
		root.add_child(b)
		return root
	var k: Dictionary = Body.KINDS[kind]
	var L := float(k["len"])
	var rh := float(k["r_handle"])
	var rb := float(k["r_barrel"])
	var hd := float(k["handle"])
	var wh := (L + hd) if hd < 0.0 else hd      # main's wep_handle: where the handle ends and the barrel starts
	var head: Array = k["head"]
	var tape := _mat_of(Color(0.08, 0.08, 0.09), 0.0, 0.9)
	var metal := _mat_of(Color(0.62, 0.64, 0.68), 0.85, 0.3)
	if kind != "staff":
		_cyl(root, 0.0, 0.012, rh * 1.6, rh * 1.6, tape)   # the knob
	if kind == "staff":
		_cyl(root, 0.0, wh, rh, rh, tape)
		_cyl(root, wh, L, rb, rh, metal)
	elif not head.is_empty():
		_cyl(root, 0.012, L - 0.02, rh, rh, tape)
		var hw := float(head[0])
		var hr := float(head[1])
		var mi := MeshInstance3D.new()   # the head: across the shaft at the tip, along X
		var cy := CylinderMesh.new()
		cy.height = 2.0 * hw
		cy.top_radius = hr
		cy.bottom_radius = hr
		mi.mesh = cy
		mi.material_override = metal
		mi.rotation = Vector3(0.0, 0.0, PI * 0.5)
		mi.position = Vector3(0.0, L - hr, 0.0)
		root.add_child(mi)
	else:
		_cyl(root, 0.012, wh, rh, rh, tape)
		_cyl(root, wh, L, rh, rb, metal)   # the barrel swells from the handle's radius to its own (top = the tip)
	return root


static func _mat_of(c: Color, metallic: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metallic
	m.roughness = rough
	return m


## a cylinder along Y from y0 to y1 (bottom radius at y0, top radius at y1)
static func _cyl(parent: Node3D, y0: float, y1: float, r0: float, r1: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.height = maxf(y1 - y0, 0.001)
	c.bottom_radius = r0
	c.top_radius = r1
	mi.mesh = c
	mi.material_override = mat
	mi.position = Vector3(0.0, (y0 + y1) * 0.5, 0.0)
	parent.add_child(mi)


## the picture of a built node, drawn now at px; the node is freed after. Null when there is nothing to draw or no renderer.
## The camera looks from DIR_TO_CAMERA, and its orthographic size is set from the projected corners of every mesh's box,
## so the longer side of the object is FILL of the picture and the object is centred.
func draw_node(node: Node3D, px: Vector2i) -> Image:
	_stage()
	_vp.size = px
	for c in _world.get_children():
		_world.remove_child(c)
		c.free()
	_world.add_child(node)
	var pts := PackedVector3Array()
	for mi in _meshes(node):
		var box: AABB = mi.global_transform * (mi as MeshInstance3D).mesh.get_aabb()
		for i in 8:
			pts.append(box.position + box.size * Vector3(i & 1, (i >> 1) & 1, (i >> 2) & 1))
	if pts.is_empty():
		_world.remove_child(node)
		node.free()
		return null
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var mid := (lo + hi) * 0.5
	_cam.look_at_from_position(mid + DIR_TO_CAMERA.normalized() * 10.0, mid, Vector3.UP)
	var inv := _cam.global_transform.affine_inverse()
	var lo2 := Vector2(INF, INF)
	var hi2 := -lo2
	for p in pts:
		var q: Vector3 = inv * p
		lo2 = lo2.min(Vector2(q.x, q.y))
		hi2 = hi2.max(Vector2(q.x, q.y))
	var c2 := (lo2 + hi2) * 0.5
	_cam.global_position += _cam.global_basis * Vector3(c2.x, c2.y, 0.0)
	_cam.size = maxf(hi2.x - lo2.x, hi2.y - lo2.y) / FILL
	await _frame()
	if not is_inside_tree() or _vp == null or not is_instance_valid(_vp):
		return null
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img: Image = null
	if is_inside_tree() and _vp != null and is_instance_valid(_vp):
		img = _vp.get_texture().get_image()
	if is_instance_valid(node):
		_world.remove_child(node)
		node.free()
	return img


static func _meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out


static func _mesh(s: Array) -> Mesh:
	match String(s[0]):
		"box":
			var b := BoxMesh.new()
			b.size = s[2]
			return b
		"ball":
			var sp := SphereMesh.new()
			sp.radius = float(s[2])
			sp.height = float(s[2]) * 2.0
			return sp
		_:
			var cy := CylinderMesh.new()
			cy.height = float(s[2])
			cy.top_radius = float(s[3])
			cy.bottom_radius = float(s[3])
			return cy


func _stage() -> void:
	if _vp != null:
		return
	_vp = SubViewport.new()
	_vp.name = "library_thumb_stage"
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Tok.c("world")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE   # a light, not a surface: white is the light's own colour in both themes
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()   # the soft key: from the front right, above
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 1.0
	key.shadow_enabled = false
	_vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -140, 0)
	fill.light_energy = 0.4
	_vp.add_child(fill)
	_world = Node3D.new()
	_world.name = "objects"
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Tok.c("cube")
	_mat.roughness = 0.6
	_vp.add_child(_world)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.05
	_cam.far = 100.0
	_cam.current = true
	_vp.add_child(_cam)
