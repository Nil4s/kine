class_name FilmStage
extends RefCounted
## ITEM 269 FILM MODE: the part's film keys (scripts/build/film.gd) played in the dark product studio (StudioLight, items 263/274/275).
## One MeshInstance3D per drawn surface (a surface is one body up to 256 bodies); set_time(t) puts every body's transform and look at film time t.
## Playback (play_step) and export (export) both go through set_time + grab, so a frame written to disk is the frame the viewport showed.
## The camera is fixed for the whole film, framed once on the union of every body's reach (a spinning body: the sphere about its pivot).

var vp: SubViewport
var rec: Dictionary
var items: Array = []   # [{mi, mat, body, base: look, centre}]
var cam: Camera3D
var t := 0.0
var size: Vector2i
var box := AABB()
var ok := false


func _init(host: Node, record: Dictionary, sz := Vector2i(960, 540), ov := {}) -> void:
	rec = record
	size = sz
	var res := Part.replay(rec)
	var mesh: ArrayMesh = res["mesh"]
	if mesh == null:
		return
	var looks: Array = res["looks"]
	var sb: Array = res["surf_body"]
	vp = SubViewport.new()
	vp.size = sz
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.use_debanding = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var world := Node3D.new()
	vp.add_child(world)
	var reach := AABB()
	var first := true
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var one := ArrayMesh.new()
		one.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var bb := one.get_aabb()
		var body := int(sb[s]) if s < sb.size() else s
		var base: Dictionary = looks[mini(s, looks.size() - 1)]
		var mt := StandardMaterial3D.new()
		mt.cull_mode = BaseMaterial3D.CULL_DISABLED
		var mi := MeshInstance3D.new()
		mi.mesh = one
		mi.material_override = mt
		world.add_child(mi)
		var it := {"mi": mi, "mat": mt, "body": body, "base": base, "centre": bb.get_center()}
		items.append(it)
		var r := bb
		if _spins(body):
			var o := bb.get_center()
			var d := Film.data(rec)
			for e in d["spins"]:
				if int(e["body"]) == body and e.get("o") is Array:
					o = Vector3(float(e["o"][0]), float(e["o"][1]), float(e["o"][2])) * Film.MM
			var rad := 0.0
			for i in 8:
				rad = maxf(rad, (bb.get_endpoint(i) - o).length())
			r = AABB(o - Vector3.ONE * rad, Vector3.ONE * rad * 2.0)
		var tn := Film.duration(rec)
		var ext := r
		for i in 17:   # moves: the box at 17 times along the film
			var off := Film.offset_at(rec, body, tn * float(i) / 16.0)
			ext = ext.merge(AABB(r.position + off, r.size))
		reach = ext if first else reach.merge(ext)
		first = false
	box = reach
	var ovv := ov.duplicate()
	ovv["reflect"] = false
	var st := StudioLight.build(world, box, ovv)
	cam = Camera3D.new()
	cam.fov = float(ov.get("fov", 30.0))
	cam.near = 0.01 * maxf(float(st["diag"]), 0.1)
	cam.far = float(st["diag"]) * 120.0
	world.add_child(cam)
	cam.current = true
	host.add_child(vp)
	var dir: Vector3 = (ov.get("view_dir", Vector3(0.6, 0.3, 1.0)) as Vector3).normalized()
	var target := box.get_center()
	var dist := float(st["diag"]) * 2.0
	var fsz := Vector2(sz)
	for i in 6:
		cam.look_at_from_position(target + dir * dist, target, Vector3.UP)
		var r2 := NiceRender._screen_box(cam, box)
		var sc2 := minf(0.6 * fsz.y / maxf(r2.size.y, 1.0), 0.7 * fsz.x / maxf(r2.size.x, 1.0))
		var err := r2.get_center() - fsz * 0.5
		var mpp := 2.0 * dist * tan(deg_to_rad(cam.fov) * 0.5) / fsz.y
		target += cam.global_transform.basis.x * err.x * mpp - cam.global_transform.basis.y * err.y * mpp
		dist /= sc2
	cam.look_at_from_position(target + dir * dist, target, Vector3.UP)
	ok = true
	set_time(0.0)


func _spins(body: int) -> bool:
	for e in Film.data(rec).get("spins", []):
		if int(e["body"]) == body:
			return true
	return false


func close() -> void:
	if vp != null and is_instance_valid(vp):
		vp.queue_free()


## every body at film time `time`: its transform, and its look (colour, emission colour and strength) drawn as the material
func set_time(time: float) -> void:
	t = time
	for it in items:
		var body: int = it["body"]
		(it["mi"] as MeshInstance3D).transform = Film.xform_at(rec, body, time, it["centre"])
		var l := Film.look_at(rec, body, time, it["base"])
		var mt: StandardMaterial3D = it["mat"]
		var c: Color = l["c"]
		var a := float(l.get("alpha", 1.0))
		mt.albedo_color = Color(c.r, c.g, c.b, a)
		mt.roughness = float(l.get("rough", 0.5))
		mt.metallic = float(l.get("metal", 0.15))
		mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
		if PartGlow.has(l):
			mt.emission_enabled = true
			mt.emission = l["glow"]
			mt.emission_energy_multiplier = float(l["glow_k"])
		else:
			mt.emission_enabled = false


## playback: advance the clock by dt (looping at the end of the film when loop) and show it
func play_step(dt: float, loop := true) -> void:
	var flen := Film.duration(rec)
	var nt := t + dt
	if nt > flen:
		nt = fposmod(nt, flen) if loop else flen
	set_time(nt)


## the picture the viewport shows now
func grab() -> Image:
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


func frame(time: float) -> Image:
	set_time(time)
	return await grab()


## PNG sequence dir/frame_0000.png ... at `fps` over the film's length; returns the number written
static func export(host: Node, record: Dictionary, dir: String, fps := 25, sz := Vector2i(960, 540), ov := {}) -> int:
	var stg := FilmStage.new(host, record, sz, ov)
	if not stg.ok:
		return 0
	DirAccess.make_dir_recursive_absolute(dir)
	var n := int(floor(Film.duration(record) * float(fps) + 1e-6))
	for i in n:
		var img := await stg.frame(float(i) / float(fps))
		if img == null:
			stg.close()
			return i
		img.save_png("%s/frame_%04d.png" % [dir, i])
	stg.close()
	return n
