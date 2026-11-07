class_name SculptMotionUI
extends Node
## C23 (docs/ROADMAP_400.md): the strip under the window that shows the 8 hardest frames of the scene for the region the last
## pose-sculpt stroke moved (metric and choice: scripts/sculpt_motion.gd). refresh(sp, region) starts a job (a newer stroke
## replaces a running one); the job runs in slices of SLICE_MS from _process, then the 8 patches are drawn off screen in
## SubViewports of their own (own world: nothing in the window moves), one patch mesh built per frame, and the pictures go on
## the strip. busy is true from the stroke until the last picture is on the strip.

const SLICE_MS := 6.0
const META := "sculpt_motion_ui"

var m: Node
var sm: SculptMotion
var generation := 0
var busy := false
var max_slice_ms := 0.0
var strip: CanvasLayer
var _row: HBoxContainer
var _vps: Array = []
var _running := false


static func get_ui(main: Node) -> SculptMotionUI:
	var n = main.get_node_or_null("sculpt_motion")
	if n != null:
		return n
	var u := SculptMotionUI.new()
	u.m = main
	u.name = "sculpt_motion"
	main.add_child(u)
	return u


func refresh(sp: SculptPose, region: PackedInt32Array) -> void:
	generation += 1
	busy = true
	max_slice_ms = 0.0
	sm = SculptMotion.new().setup(sp, m)
	sm.begin(region)
	_running = true


func _process(_dt: float) -> void:
	if not _running:
		return
	var more := sm.step(SLICE_MS)
	max_slice_ms = maxf(max_slice_ms, sm.max_slice_ms)
	if more:
		return
	_running = false
	_draw(generation, sm)


func hide_strip() -> void:
	if strip != null:
		strip.visible = false


func _stage(i: int) -> SubViewport:
	while _vps.size() <= i:
		var vp := SubViewport.new()
		vp.size = Vector2i(SculptMotion.SIZE, SculptMotion.SIZE)
		vp.own_world_3d = true
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.12, 0.14, 0.2)
		var we := WorldEnvironment.new()
		we.environment = env
		vp.add_child(we)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.near = 0.05
		cam.far = 5.0
		vp.add_child(cam)
		cam.current = true
		var mi := MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
		vp.add_child(mi)
		_vps.append(vp)
	return _vps[i]


func _draw(gen: int, job: SculptMotion) -> void:
	var n := job.thumbs.size()
	for j in n:
		await get_tree().process_frame
		if gen != generation:
			return
		var t0 := Time.get_ticks_usec()
		var vp := _stage(j)
		var arr := job.patch_arrays(j)
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var th: Dictionary = job.thumbs[j]
		for c in vp.get_children():
			if c is MeshInstance3D:
				c.mesh = am
			elif c is Camera3D:
				c.global_transform = th["cam_xf"]
				c.size = th["cam_size"]
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		max_slice_ms = maxf(max_slice_ms, float(Time.get_ticks_usec() - t0) / 1000.0)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if gen != generation:
		return
	var t1 := Time.get_ticks_usec()
	for j in n:
		job.thumbs[j]["image"] = (_vps[j] as SubViewport).get_texture().get_image()
	_show(job)
	max_slice_ms = maxf(max_slice_ms, float(Time.get_ticks_usec() - t1) / 1000.0)
	busy = false


func _show(job: SculptMotion) -> void:
	if strip == null:
		strip = CanvasLayer.new()
		strip.layer = 20
		var pc := PanelContainer.new()
		pc.anchor_left = 0.0
		pc.anchor_right = 1.0
		pc.anchor_top = 1.0
		pc.anchor_bottom = 1.0
		pc.offset_top = -(SculptMotion.SIZE * 0.6 + 26.0)
		_row = HBoxContainer.new()
		_row.add_theme_constant_override("separation", 4)
		pc.add_child(_row)
		strip.add_child(pc)
		add_child(strip)
	strip.visible = true
	for c in _row.get_children():
		c.queue_free()
	for th in job.thumbs:
		var box := VBoxContainer.new()
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(th["image"])
		tr.custom_minimum_size = Vector2(SculptMotion.SIZE, SculptMotion.SIZE) * 0.6
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var lb := Label.new()
		lb.text = "frame %d (%.2fs)" % [int(th["frame"]), float(th["t"])]
		lb.add_theme_font_size_override("font_size", 11)
		box.add_child(tr)
		box.add_child(lb)
		_row.add_child(box)
