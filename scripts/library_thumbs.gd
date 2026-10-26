class_name LibraryThumbs
extends Node
## LIBRARY PICTURES (the object library's tiles, scripts/object_library.gd). Each object is drawn from its REAL mesh, the one the
## app places: a weapon's cylinders (the same shapes main.gd draws on the hand, Body.KINDS), a prop's own mesh (Props.mesh of
## Props.make), an armour plate built on the fighter's body (ArmourFromBody.build), a user model's imported scene (Props.mesh).
## The picture is 128 x 128, the theme's dark background, a three-quarter view from the front right and above, the object
## framed so its projected extent fills FILL (80 %) of the longer side, one key light and a fill light.
##
## THE OLD SCHEMATIC FIRST: a tile shows the schematic bar (the shapes of Props.kind_of / Body.KINDS, 64 px) until the real
## picture is ready; a real picture on disk or shipped shows at once and no schematic is drawn. Until a picture is ready the
## tile shows a placeholder label (the category and the name; scripts/object_library.gd), never an empty box.
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
const VERSION := "2"                 # bump when the drawing changes: every real picture is drawn again (2: weapons are WeaponMesh shapes)
const FILL := 0.8                    # the object's projected extent is this share of the picture's longer side
const DIR_TO_CAMERA := Vector3(0.45, 0.25, 1.0)   # from the front, right and above: the three-quarter view
const FILL_THIN := 0.94              # a rolled (thin) object fills more: its diagonal reaches nearly the corners
const THIN_ASPECT := 2.0            # a picture whose object runs at least this many times longer than it is wide rolls its long axis to the diagonal

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


## the shipped (pre-rendered) picture of an object: res://data/thumbs/lib/<id>_<hash16>_128.png, where the hash is of VERSION +
## the spec (a weapon's or prop's data, an armour plate's builder version, constants and the default body's rest vertices): a changed
## spec is a new name, so the live render takes over until tools/make_lib_thumbs.gd is run again
static func shipped_path(id: String, spec: String) -> String:
	return "res://data/thumbs/lib/%s_%s_%d.png" % [id.replace(":", "_"), (VERSION + spec).sha256_text().left(16), SIZE.x]


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
		var shipped := String(src.get("shipped", ""))
		if real != "" and shipped != "" and FileAccess.file_exists(shipped):
			var sh := Image.load_from_file(abs_path(shipped))
			if sh != null and not sh.is_empty():
				disk_hits += 1
				_write(sh, real)   # a copy in the user cache, so the next open reads it there
				_show_picture(id, sh)
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


## the real mesh of a weapon: its shape from WeaponMesh (the same pieces the hand draws, scripts/weapon_mesh.gd)
## the thumbnails' girth: a long thin shaft drawn thicker in its picture only (the hand is drawn at 1.0, the hit radii are data).
## Staff and spear would reach 3-4 % of the square at true thickness (a diagonal rod fills ~2W/L of it); the bar is 5 %.
const THUMB_GIRTH := {"staff": 2.0, "spear": 2.0}

## ONE SCALE FOR THE SWORDS: each picture is fitted to its tile, so a 0.92 m sword and a 1.20 m longsword came out the
## same size (the monkey test could not tell them apart). These kinds are drawn at their length's share of the longest
## one's (draw_node reads the node's "thumb_shrink"): the longsword fills the tile, the sword is 77 % of it.
const SAME_SCALE := ["sword", "longsword"]   # the katana reads as itself (its curve); shrunk it fell under B7's 5 % of the tile

static func weapon_node(kind: String) -> Node3D:
	var n := WeaponMesh.build(kind, float(THUMB_GIRTH.get(kind, 1.0)), true)
	if n != null and kind in SAME_SCALE:
		var longest := 0.0
		for k in SAME_SCALE:
			longest = maxf(longest, float(Body.KINDS[k]["len"]))
		n.set_meta("thumb_shrink", float(Body.KINDS[kind]["len"]) / longest)
	return n


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
	# A THIN OBJECT ON ITS DIAGONAL: a long thin object (a blade, a pole) fills a square picture only along its length, and
	# its length is the square's diagonal at most. Rolling the camera so the long axis runs corner to corner gives it ~40 %
	# more length in the picture (a rod upright is 1-3 % of the square; the roll is what makes it readable)
	var la := _long_axis(pts)
	var thin := la.y >= THIN_ASPECT
	if thin:
		var delta := wrapf(PI * 0.25 - la.x, -PI * 0.5, PI * 0.5)
		var eps := 0.1
		_cam.rotate_object_local(Vector3.BACK, eps)   # a small test roll: which way the picture turns
		var turn := wrapf(_long_axis(pts).x - la.x, -PI * 0.5, PI * 0.5)
		_cam.rotate_object_local(Vector3.BACK, -eps)
		_cam.rotate_object_local(Vector3.BACK, (1.0 if turn >= 0.0 else -1.0) * delta)
	var inv := _cam.global_transform.affine_inverse()
	var lo2 := Vector2(INF, INF)
	var hi2 := -lo2
	for p in pts:
		var q: Vector3 = inv * p
		lo2 = lo2.min(Vector2(q.x, q.y))
		hi2 = hi2.max(Vector2(q.x, q.y))
	var c2 := (lo2 + hi2) * 0.5
	_cam.global_position += _cam.global_basis * Vector3(c2.x, c2.y, 0.0)
	_cam.size = maxf(hi2.x - lo2.x, hi2.y - lo2.y) / (FILL_THIN if thin else FILL) / float(node.get_meta("thumb_shrink", 1.0))
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


## the long axis of the points as the camera sees them: x = its angle in the picture (radians, mod PI), y = the long-to-short ratio
func _long_axis(pts: PackedVector3Array) -> Vector2:
	var inv := _cam.global_transform.affine_inverse()
	var q := PackedVector2Array()
	var mean := Vector2.ZERO
	for p in pts:
		var v: Vector3 = inv * p
		q.append(Vector2(v.x, v.y))
		mean += Vector2(v.x, v.y)
	mean /= float(q.size())
	var cxx := 0.0
	var cyy := 0.0
	var cxy := 0.0
	for v in q:
		var d := v - mean
		cxx += d.x * d.x
		cyy += d.y * d.y
		cxy += d.x * d.y
	var tr := cxx + cyy
	var disc := sqrt((cxx - cyy) * (cxx - cyy) + 4.0 * cxy * cxy)
	var l1 := (tr + disc) * 0.5
	var l2 := maxf((tr - disc) * 0.5, 1e-12)
	return Vector2(0.5 * atan2(2.0 * cxy, cxx - cyy), sqrt(l1 / l2))


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
	_vp.msaa_3d = Quality.thumb_msaa() as Viewport.MSAA
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
