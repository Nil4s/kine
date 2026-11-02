extends SceneTree
## S263/274/275 the dark product studio (scripts/build/studio_light.gd) and the continuous ring band (scripts/build/ring_glow.gd).
## Bars (written before the numbers):
##   STUDIO   a 30 cm product (silver body + a red glow strip) lit by the preset: no pixel at (>= 0.98, 0.98, 0.98) outside the glow strip's screen box (+ 14 px);
##            mean luminance of the lit pixels (> 25/255) within BLENDER_LO..BLENDER_HI (Blender sbs_0 left half: 83.8, sbs_7: 73.1 -> 65..95).
##            CONTROL: exposure 10x clips white (the clip bar can fail) and leaves the range.
##   FLOOR    the floor under the product: with the reflection ON its red-minus-blue mean is >= 0.02 above the OFF render and >= 3x it; OFF has none (<= 0.01).
##   LINKING  a light with link_floor=false leaves a white floor black (< 0.02); linked it is lit (> 0.10). SHINE: a glossy sphere's peak with spec 1 is
##            >= 0.15 above spec 0 (the control: spec 1 itself must be bright).
##   RINGS    luminance along the ring path: the continuous band has min/median >= 0.5; CONTROL: 12 sectors with 3 deg gaps (the old ring) on the same bloom
##            read min/median < 0.5 at least once in 3 sampled radii/ring sizes, or the control is reported as "not a gap" (fails the test).
##   DEFAULTS NiceRender.look "studio" twice -> identical bytes (hash printed; compared by hand with the base branch's render in the report).
var fails := 0
const BLENDER_LO := 65.0
const BLENDER_HI := 95.0
var host: Node


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func product() -> Dictionary:
	var rec := Part.make("Studio test")
	Part.prim(rec, "box", {"x": -150.0, "y": 0.0, "z": -75.0, "w": 300.0, "h": 40.0, "d": 150.0, "name": "Body"})
	(rec["features"] as Array).append(Part.new_feature(rec, "bname", {"body": 0, "called": "Body"}))
	(rec["features"] as Array).append(Part.new_feature(rec, "appear", {"body": 0, "preset": "Custom", "color": [0.24, 0.25, 0.28], "rough": 0.4, "metal": 0.8, "alpha": 1.0}))
	Part.prim(rec, "box", {"x": -140.0, "y": 40.0, "z": 60.0, "w": 280.0, "h": 4.0, "d": 8.0, "name": "Strip"})
	(rec["features"] as Array).append(Part.new_feature(rec, "bname", {"body": 1, "called": "Strip"}))
	var f := {"body": 1, "preset": "Custom", "color": [0.4, 0.05, 0.05], "rough": 0.5, "metal": 0.0, "alpha": 1.0}
	f.merge(PartGlow.fields(Color(1.0, 0.1, 0.1), 4.0))
	(rec["features"] as Array).append(Part.new_feature(rec, "appear", f))
	return rec


func shot(rec: Dictionary, ov := {}) -> Image:
	var res := Part.replay(rec)
	var mesh: ArrayMesh = res["mesh"]
	Part.paint(mesh, res["looks"])
	return await StudioLight.draw_mesh(host, mesh, res["aabb"], Vector2i(1280, 720), ov)


func proj(p: Vector3, sz := Vector2(1280, 720)) -> Vector2:
	var xf: Transform3D = StudioLight.last_view["xf"]
	var q := xf.affine_inverse() * p
	var f := 1.0 / tan(deg_to_rad(float(StudioLight.last_view["fov"])) * 0.5)
	var ndc := Vector2(q.x / -q.z * f / (sz.x / sz.y), q.y / -q.z * f)
	return Vector2((ndc.x + 1.0) * 0.5 * sz.x, (1.0 - ndc.y) * 0.5 * sz.y)


func rect_of(box: AABB) -> Rect2:
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for i in 8:
		var p := proj(box.get_endpoint(i))
		lo = lo.min(p)
		hi = hi.max(p)
	return Rect2(lo, hi - lo)


func plain_scene(light_link: bool, spec: float, glossy: bool) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 256)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var w := Node3D.new()
	vp.add_child(w)
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var we := WorldEnvironment.new()
	we.environment = e
	w.add_child(we)
	var fl := StudioLight.make_floor(0.0, Vector3.ZERO, 4.0)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.8, 0.8, 0.8)
	fm.roughness = 0.9
	fl.material_override = fm
	if glossy:
		fl.visible = false
		var sp := MeshInstance3D.new()
		sp.mesh = SphereMesh.new()
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.05, 0.05, 0.05)
		sm.roughness = 0.12
		sp.material_override = sm
		sp.position = Vector3(0, 0.5, 0)
		w.add_child(sp)
	w.add_child(fl)
	var l := DirectionalLight3D.new()
	l.light_energy = 2.0
	StudioLight.set_light(l, spec, light_link)
	w.add_child(l)
	l.look_at_from_position(Vector3(0.3, 1.0, 1.0), Vector3(0, 0.3, 0), Vector3.UP)
	var cam := Camera3D.new()
	w.add_child(cam)
	cam.current = true
	host.add_child(vp)
	cam.look_at_from_position(Vector3(0, 1.5, 2.2), Vector3(0, 0.3, 0), Vector3.UP)
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


func peak(img: Image) -> float:
	var m := 0.0
	for y in img.get_height():
		for x in img.get_width():
			m = maxf(m, lum(img.get_pixel(x, y)))
	return m


func peak_in(img: Image, r: Rect2i) -> float:
	var m := 0.0
	for y in range(maxi(r.position.y, 0), mini(r.end.y, img.get_height())):
		for x in range(maxi(r.position.x, 0), mini(r.end.x, img.get_width())):
			m = maxf(m, lum(img.get_pixel(x, y)))
	return m


func peak_color(img: Image, r: Rect2i) -> Color:   # the mean colour of the region's pixels above 0.25 luminance (a white-hot core would hide the hue)
	var sum := Color(0, 0, 0, 1)
	var n := 0
	for y in range(maxi(r.position.y, 0), mini(r.end.y, img.get_height())):
		for x in range(maxi(r.position.x, 0), mini(r.end.x, img.get_width())):
			var c := img.get_pixel(x, y)
			if lum(c) > 0.25:
				sum.r += c.r
				sum.g += c.g
				sum.b += c.b
				n += 1
	return Color(sum.r / maxi(n, 1), sum.g / maxi(n, 1), sum.b / maxi(n, 1))


func mean_of(img: Image, r: Rect2i) -> Color:
	var s := Color(0, 0, 0, 0)
	var n := 0
	for y in range(maxi(r.position.y, 0), mini(r.end.y, img.get_height())):
		for x in range(maxi(r.position.x, 0), mini(r.end.x, img.get_width())):
			var c := img.get_pixel(x, y)
			s.r += c.r
			s.g += c.g
			s.b += c.b
			n += 1
	return Color(s.r / n, s.g / n, s.b / n)


## clipped pixels outside a rect, and the mean 0..255 luminance of lit pixels
func clip_and_mean(img: Image, glow: Rect2) -> Dictionary:
	var g := glow.grow(14.0)
	var clipped := 0
	var sum := 0.0
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.r >= 0.98 and c.g >= 0.98 and c.b >= 0.98 and not g.has_point(Vector2(x, y)):
				clipped += 1
			var l := lum(c) * 255.0
			if l > 25.0:
				sum += l
				n += 1
	return {"clipped": clipped, "mean": sum / maxf(n, 1)}


func ring_scene(band: bool, ri: float, ro: float, bloom := true, fh := 0.5) -> Dictionary:
	var m: ArrayMesh
	var mat: Material
	if band:
		m = RingGlow.band_mesh(ri, ro, 0.0, 0.002, 128)
		mat = RingGlow.material(0.15, 0.0, 3.0, 3.0, false)
	else:
		m = ArrayMesh.new()
		for s in 12:   # the old ring: 12 sectors, 3 degrees between them (one surface each, as the film's Ring glow)
			var a0 := deg_to_rad(30.0 * s + 1.5)
			var a1 := deg_to_rad(30.0 * (s + 1) - 1.5)
			var v := PackedVector3Array()
			var idx := PackedInt32Array()
			for k in 9:
				var a := lerpf(a0, a1, k / 8.0)
				v.append(Vector3(cos(a) * ri, sin(a) * ri, 0.002))
				v.append(Vector3(cos(a) * ro, sin(a) * ro, 0.002))
			for k in 8:
				var b := k * 2
				idx.append_array([b, b + 1, b + 3, b, b + 3, b + 2])
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = v
			arr[Mesh.ARRAY_INDEX] = idx
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.1, 0.4, 0.5)
		sm.emission_enabled = true
		sm.emission = Color(0.2, 0.8, 1.0)
		sm.emission_energy_multiplier = 3.0
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat = sm
	for s in m.get_surface_count():
		m.surface_set_material(s, mat)
	var img: Image = await StudioLight.draw_mesh(host, m, m.get_aabb(), Vector2i(1280, 720), {"reflect": false, "view_dir": Vector3(0, 0.0001, 1), "bloom": bloom, "fill_h": fh})
	var c := proj(Vector3(0, 0, 0.002))
	var r := (proj(Vector3((ri + ro) * 0.5, 0, 0.002)) - c).length()
	return {"img": img, "c": c, "r": r}


func _init() -> void:
	var main := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	for i in 8:
		await process_frame
	host = main
	var rec := product()
	# STUDIO
	var img := await shot(rec)
	var res := Part.replay(rec)
	var bodies_boxes: Array = res.get("body_boxes", [])
	var glow_box := AABB(Vector3(-0.14, 0.04, 0.06), Vector3(0.28, 0.004, 0.008))
	var glow_rect := rect_of(glow_box)
	var st := clip_and_mean(img, glow_rect)
	print("studio: clipped outside glow ", st["clipped"], "  mean lit lum ", st["mean"], "  glow rect ", glow_rect)
	ok(int(st["clipped"]) == 0, "STUDIO no pixel clipped white outside the glow strip (%d)" % int(st["clipped"]))
	ok(float(st["mean"]) >= BLENDER_LO and float(st["mean"]) <= BLENDER_HI, "STUDIO mean lit luminance %.1f in %.0f..%.0f (Blender sbs_0 83.8, sbs_7 73.1)" % [st["mean"], BLENDER_LO, BLENDER_HI])
	var hot := await shot(rec, {"exposure": 10.0})
	var sth := clip_and_mean(hot, glow_rect)
	print("control exposure 10x: clipped ", sth["clipped"], " mean ", sth["mean"])
	ok(int(sth["clipped"]) > 0 or float(sth["mean"]) > BLENDER_HI, "STUDIO CONTROL exposure 10x clips or leaves the range (the bar can fail)")
	# FLOOR
	var off := await shot(rec, {"reflect": false})
	DirAccess.make_dir_recursive_absolute("C:/Users/Nick/tools/kine_workers/out/s263")
	img.save_png("C:/Users/Nick/tools/kine_workers/out/s263/studio_on.png")
	off.save_png("C:/Users/Nick/tools/kine_workers/out/s263/studio_off.png")
	var base := proj(Vector3(0, 0.0, 0.075))
	var under := Rect2i(Vector2i(int(glow_rect.position.x), int(base.y) + 30), Vector2i(int(glow_rect.size.x), 120))
	var mon := mean_of(img, under)
	var moff := mean_of(off, under)
	print("floor region ", under, " on ", mon, " off ", moff)
	var pk_on := peak_in(img, under)
	var pk_off := peak_in(off, under)
	print("floor peak on ", pk_on, " off ", pk_off)
	var pc := peak_color(img, under)
	ok(pk_on >= 0.5 and pc.r >= 1.5 * pc.b, "FLOOR reflection on: the strip's red image is in the floor (peak %.2f, colour %s)" % [pk_on, str(pc)])
	ok(pk_off <= 0.4, "FLOOR reflection off: no image, only the bloom halo (peak %.2f)" % pk_off)
	# LINKING / SHINE
	var li := await plain_scene(true, 1.0, false)
	var lo := await plain_scene(false, 1.0, false)
	ok(lum(mean_of(li, Rect2i(0, 150, 256, 100))) > 0.10 and lum(mean_of(lo, Rect2i(0, 150, 256, 100))) < 0.02, "LINKING linked floor %.3f, unlinked %.3f" % [lum(mean_of(li, Rect2i(0, 150, 256, 100))), lum(mean_of(lo, Rect2i(0, 150, 256, 100)))])
	var sh1 := await plain_scene(true, 1.0, true)
	var sh0 := await plain_scene(true, 0.0, true)
	ok(peak(sh1) >= 0.5 and peak(sh1) - peak(sh0) >= 0.15, "SHINE sphere peak spec 1 %.3f vs spec 0 %.3f" % [peak(sh1), peak(sh0)])
	# RINGS
	var worst_band := 9.0
	var min_old := 9.0
	for sizes in [[0.040, 0.0446, 0.2], [0.100, 0.1115, 0.5], [0.2, 0.223, 0.8]]:
		var b := await ring_scene(true, sizes[0], sizes[1], true, sizes[2])
		var rb := RingGlow.along(b["img"], b["c"], b["r"], 360, 2)
		var mb := RingGlow.min_over_median(rb)
		var o := await ring_scene(false, sizes[0], sizes[1], false, sizes[2])
		var o2 := await ring_scene(false, sizes[0], sizes[1], true, sizes[2])
		print("   (sectors WITH the new bloom: min/median ", RingGlow.min_over_median(RingGlow.along(o2["img"], o2["c"], o2["r"], 360, 2)), ")")
		var ro := RingGlow.along(o["img"], o["c"], o["r"], 360, 2)
		var mo := RingGlow.min_over_median(ro)
		print("ring ri ", sizes[0], ": band min/median ", mb, "  sectors ", mo, "  radius px ", b["r"])
		worst_band = minf(worst_band, mb)
		min_old = minf(min_old, mo)
		if sizes[0] == 0.100:
			(b["img"] as Image).save_png("C:/Users/Nick/tools/kine_workers/out/s263/ring_band.png")
			(o["img"] as Image).save_png("C:/Users/Nick/tools/kine_workers/out/s263/ring_sectors.png")
	ok(worst_band >= 0.5, "RINGS continuous band min/median %.2f >= 0.5" % worst_band)
	ok(min_old < 0.5, "RINGS CONTROL the 12-sector ring, bloom off, reads min/median %.2f < 0.5 (a gap shows)" % min_old)
	# DEFAULTS
	NiceRender.look = "studio"
	var a := await NiceRender.draw_mesh(main, res["mesh"], res["aabb"], res["looks"], Vector2i(640, 360))
	var b2 := await NiceRender.draw_mesh(main, res["mesh"], res["aabb"], res["looks"], Vector2i(640, 360))
	print("DEFAULT studio hash ", hash(a.get_data()), " ", hash(b2.get_data()))
	ok(a.get_data() == b2.get_data(), "DEFAULTS preset off: two renders are byte-identical")
	var da := DirAccess.open("user://")
	NiceRender.look = "studio_dark"
	var sd := await NiceRender.draw_mesh(main, res["mesh"], res["aabb"], res["looks"], Vector2i(640, 360))
	ok(sd != null and sd.get_data() != a.get_data(), "NiceRender.look studio_dark draws the new studio")
	NiceRender.look = "studio"
	print("s263: %d fail" % fails)
	quit(fails)
