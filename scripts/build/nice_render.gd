class_name NiceRender
extends RefCounted
## NICE PICTURE (Friday plan 105): the part on screen as a 1920 x 1080 PNG for showing it, drawn off-screen (a SubViewport with its own
## world, so the app view never changes): three soft lights (key, fill, rim), a soft contact shadow under the part, a faint floor
## reflection (a mirrored copy under the floor that fades out with depth) and a smooth studio gradient behind. No grid, no gizmos,
## no panels. The 3D layer is drawn on a clear background and laid over the gradient in 2D, so the floor has no edge and no lines.
## Saved next to the part's other exports (the exports folder) as <part>_nice.png; the caller shows the path in words.

static var part_only := false   # the test's switch: draw the part alone (no shadow, no reflection) to measure its own pixel box
const SIZE := Vector2i(1920, 1080)
const FILL_H := 0.70          # the part's height in the frame (a share), so the shadow and the reflection fit under it
const FILL_W := 0.62          # the part's width in the frame (a share) for wide parts
const FRAMES := 2             # frames to let the render settle
const SHADOW_A := 0.74        # the contact shadow's darkest alpha
const MIRROR_A := 0.30        # the reflection's strength at the floor line; it fades to nothing over FADE_OF_HEIGHT x the part height
const FADE_OF_HEIGHT := 0.9
const BG_TOP := Color(0.80, 0.83, 0.88)
const BG_BOTTOM := Color(0.54, 0.57, 0.63)

const MIRROR_SHADER := "shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.7, 0.7, 0.7, 1.0);
uniform float floor_y = 0.0;
uniform float fade_h = 0.1;
uniform float strength = 0.38;
varying float depth;
void vertex() { depth = floor_y - (MODEL_MATRIX * vec4(VERTEX, 1.0)).y; }
void fragment() {
	float f = clamp(1.0 - depth / fade_h, 0.0, 1.0);
	ALBEDO = tint.rgb * 0.6;
	ALPHA = f * f * strength * tint.a;
}
"


## the gradient behind the part: top to bottom, with a soft pool of light in the middle (all smooth, no lines)
static func background(size := SIZE) -> Image:
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		var t := float(y) / float(size.y - 1)
		img.fill_rect(Rect2i(0, y, size.x, 1), BG_TOP.lerp(BG_BOTTOM, t))
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.22))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.45)
	gt.fill_to = Vector2(1.0, 0.45)
	gt.width = 480
	gt.height = 270
	var glow := gt.get_image()
	glow.convert(Image.FORMAT_RGBA8)
	glow.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	img.blend_rect(glow, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	return img


static func _blob(span: Vector2, alpha: float, y: float, prio: int) -> MeshInstance3D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, alpha))
	g.set_color(1, Color(0, 0, 0, 0.0))
	g.add_point(0.45, Color(0, 0, 0, alpha * 0.8))   # holds dark past the part's edge, then falls off softly
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	var q := QuadMesh.new()
	q.size = span
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mt.albedo_color = Color(1, 1, 1, 1)
	mt.albedo_texture = gt
	mt.cull_mode = BaseMaterial3D.CULL_DISABLED
	mt.render_priority = prio
	mt.no_depth_test = false
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mt
	mi.rotation_degrees = Vector3(-90, 0, 0)
	mi.position.y = y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _screen_box(cam: Camera3D, box: AABB) -> Rect2:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for i in 8:
		var p := cam.unproject_position(box.get_endpoint(i))
		lo = lo.min(p)
		hi = hi.max(p)
	return Rect2(lo, hi - lo)


## the 1920 x 1080 picture of a replayed part as an Image (null when there is no solid to draw)
static func draw(host: Node, rec: Dictionary, size := SIZE) -> Image:
	var res := Part.replay(rec)
	var mesh: ArrayMesh = res["mesh"]
	if mesh == null:
		return null
	var box: AABB = res["aabb"]
	var looks: Array = res["looks"]
	Part.paint(mesh, looks)
	var floor_y := box.position.y
	var vp := SubViewport.new()
	vp.size = size
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var world := Node3D.new()
	vp.add_child(world)
	var solid := MeshInstance3D.new()
	solid.mesh = mesh
	world.add_child(solid)
	# the reflection: the same solid mirrored across the floor, fading with depth (one shader, the part's own colours)
	var sh := Shader.new()
	sh.code = MIRROR_SHADER
	var mirror := MeshInstance3D.new()
	mirror.mesh = mesh
	for s in mesh.get_surface_count():
		var l: Dictionary = looks[mini(s, looks.size() - 1)] if not looks.is_empty() else {"c": Color(0.74, 0.77, 0.82), "alpha": 1.0}
		var sm := ShaderMaterial.new()
		sm.shader = sh
		sm.set_shader_parameter("tint", Color((l["c"] as Color).r, (l["c"] as Color).g, (l["c"] as Color).b, float(l["alpha"])))
		sm.set_shader_parameter("floor_y", floor_y)
		sm.set_shader_parameter("fade_h", maxf(box.size.y * FADE_OF_HEIGHT, 0.01))
		sm.set_shader_parameter("strength", MIRROR_A)
		sm.render_priority = -1
		mirror.set_surface_override_material(s, sm)
	mirror.scale = Vector3(1, -1, 1)
	mirror.position = Vector3(0, 2.0 * floor_y, 0)
	mirror.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if not part_only:
		world.add_child(mirror)
	# the soft contact shadow: a wide faint pool and a tight dark one right under the part
	var c := box.get_center()
	var fx := maxf(box.size.x, 0.001)
	var fz := maxf(box.size.z, 0.001)
	var wide := _blob(Vector2(fx * 3.0, fz * 3.0), SHADOW_A * 0.5, 0.0, 1)
	wide.position = Vector3(c.x, floor_y + 0.0004, c.z)
	if not part_only:
		world.add_child(wide)
	var tight := _blob(Vector2(fx * 2.1, fz * 2.1), SHADOW_A, 0.0, 2)
	tight.position = Vector3(c.x, floor_y + 0.0006, c.z)
	if not part_only:
		world.add_child(tight)
	# three soft lights: a key with a soft shadow, a dim fill from the other side, a rim from behind
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -35, 0)
	key.light_energy = 0.8
	key.shadow_enabled = true
	key.light_angular_distance = 3.0
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 130, 0)
	fill.light_energy = 0.3
	world.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-25, 200, 0)
	rim.light_energy = 0.35
	world.add_child(rim)
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.9, 0.93, 1.0)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	# the camera: the three-quarter view, then fitted so the part's box is centred and fills the frame
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.near = 0.01
	cam.far = 200.0
	world.add_child(cam)
	cam.current = true
	host.add_child(vp)
	var dir := Vector3(0.6, 0.42, 1.0).normalized()
	var target := box.get_center()
	var dist := maxf(box.size.length(), 0.05) * 2.0
	var fsz := Vector2(size)
	for it in 6:
		cam.look_at_from_position(target + dir * dist, target, Vector3.UP)
		var r := _screen_box(cam, box)
		var scale_to := minf(FILL_H * fsz.y / maxf(r.size.y, 1.0), FILL_W * fsz.x / maxf(r.size.x, 1.0))
		var err := r.get_center() - fsz * 0.5
		var mpp := 2.0 * dist * tan(deg_to_rad(cam.fov) * 0.5) / fsz.y
		target += cam.global_transform.basis.x * err.x * mpp - cam.global_transform.basis.y * err.y * mpp
		dist /= scale_to
	cam.look_at_from_position(target + dir * dist, target, Vector3.UP)
	for i in FRAMES:
		await RenderingServer.frame_post_draw
	var layer := vp.get_texture().get_image()
	vp.queue_free()
	if layer == null or layer.is_empty():
		return null
	layer.convert(Image.FORMAT_RGBA8)
	var img := background(size)
	img.blend_rect(layer, Rect2i(Vector2i.ZERO, layer.get_size()), Vector2i.ZERO)
	return img


## the picture saved as <part>_nice.png in `dir` (the exports folder, beside the part's other files).
## Returns {"ok", "path", "text"}: the words say where the file is, or why it was not made
static func save(host: Node, rec: Dictionary, dir: String) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var img: Image = await draw(host, rec)
	if img == null or img.is_empty():
		return {"ok": false, "path": "", "text": "NOT DONE: the picture could not be drawn. Try again, or press Pull it up first"}
	var gdir := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(gdir)
	var path := "%s/%s_nice.png" % [gdir, MeshExport.stem(String(rec.get("name", "Part")))]
	if img.save_png(path) != OK:
		return {"ok": false, "path": path, "text": "NOT DONE: the picture could not be saved (check that the folder can be written), then press Nice picture again"}
	return {"ok": true, "path": path, "ms": Time.get_ticks_msec() - t0,
		"text": "Nice picture saved: %s (1920 x 1080)" % path}
