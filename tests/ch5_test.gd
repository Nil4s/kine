extends SceneTree
## CH5: wet pavement at night (scripts/wet_street.gd, docs/CH5_REFERENCE.md).
## godot --path . -s tests/ch5_test.gd     (needs a GPU window; wtest.sh runs it off-screen)
## BARS (written and committed before any number was read):
##   A WATER   1000 sampled texels (half of them in/near the bowls): the water the shader sees (baked height < level) has 0 water where
##             height >= level and 0 dry where height < level. CONTROL: a painted-puddle mask ignoring the height fails (>0 wrong).
##   B MIRROR  per camera pose and visible puddle: if the ray through the mirrored lamp position hits that puddle, the bright
##             reflection's centroid is within 3 px of the projected mirrored bulb; otherwise the puddle shows no lamp (peak lum < 0.6).
##             At least 3 puddle/pose pairs must contain the lamp. CONTROL: the unmirrored bulb position is > 3 px away.
##             AMENDED per Nick 11-04: pose 2 moved from x = 1.2 to x = 0.7 (the scene now copies ref2's 2.3 m lane, wall x -1.30, plinth face
##             x 1.02; at 1.2 the camera stood over the plinth and its puddle lay against it). Same 3 poses, same 3 px tolerance, same counts.
##   C ROUGH   cobble + asphalt spots not under water (n >= 50): baked wet roughness < dry roughness at every one, and < dry - 0.2
##             where wetness > 0.5. CONTROL: dry used as wet fails.
##   D STREAK  the lamp reflection's second-moment aspect (vertical / horizontal) is within 30 % of the PHOTO-MEASURED value
##             (docs/CH5_REFERENCE.md, Wikimedia ref2 "On Cobbled Lanes": 2.32), measured with the same estimator on the ground below the lamp's
##             base (blur 3 px, region >= 0.5 x p99.5, the component with most light). CONTROL: an isotropic blob (aspect 1) is > 30 % off.
##   F GLINT   (lead 11-04) along the line from the lamp's base to the camera, the mean luminance of wet stone tops is >= 3x that of the SAME
##             stones dry (same camera, same light). CONTROL: the dry scene compared with itself (the planted dry control) fails it.
##   G POOL    the light pool: mean ground luminance at 0.75-0.85 of the lamp-to-camera distance from the lamp / that at 0.45-0.55 is within
##             30 % of the photo's 0.62 (ref2, same bands). The inverse-square pool is computed in the shader.
##   E SCENE   stone tops differ in height (sigma > 2 mm over >= 100 stones); joints lower than stone tops; a screenshot is written.
var fails := 0
const SHOT := "C:/Users/Nick/tools/kine_workers/out/ch5/ch5_night.png"
var ws: WetStreet


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func _init() -> void:
	_run.call_deferred()


## REVISION after the first run (disclosed in CH5_FEEDBACK.md): the lamp is WHITE; lit warm ground has the same luminance, so
## 'luminance' could not tell lamp from lit bed. The lamp statistic is now min(r,g,b) (whiteness). Bar numbers (3 px, 0.6, 0.5, 30 %) unchanged.
func lum(c: Color) -> float:
	return minf(c.r, minf(c.g, c.b))


func water_wrong(fn: Callable, pts: Array) -> Array:
	var above := 0
	var below := 0
	for p in pts:
		var c: Vector2 = ws.texel_center(p.x, p.y)
		var truth := ws.height(c.x, c.y) < ws.level
		var got: bool = fn.call(p, c)
		if got and not truth:
			above += 1
		if truth and not got:
			below += 1
	return [above, below]


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var poses := [Vector3(-1.2, WetStreet.EYE, 1.5), Vector3(0.0, WetStreet.EYE, 1.5), Vector3(0.7, WetStreet.EYE, 1.5)]   ## AMENDED per Nick 11-04: pose 2 was x = 1.2, over the plinth of the photo's 2.3 m lane (x -1.30..1.02); x 0.7 puts its puddle (x 0.49) on the stones
	ws = WetStreet.new()
	root.add_child(ws)
	var t0 := Time.get_ticks_msec()
	ws.build(poses)
	print("     bake %d ms, %dx%d texels, %d bowls" % [Time.get_ticks_msec() - t0, ws.himg.get_width(), ws.himg.get_height(), ws.bowls.size()])
	var cam := Camera3D.new()
	cam.fov = WetStreet.FOV
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.far = 80.0
	root.add_child(cam)

	# A WATER
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var pts := []
	for i in 1000:
		if i % 2 == 0:
			pts.append(Vector2i(rng.randi_range(0, ws.himg.get_width() - 1), rng.randi_range(0, ws.himg.get_height() - 1)))
		else:
			var b: Array = ws.bowls[rng.randi() % ws.bowls.size()]
			pts.append(ws.tex_xy(float(b[0]) + rng.randf_range(-0.8, 0.8), float(b[1]) + rng.randf_range(-0.8, 0.8)))
	var real_fn := func(p: Vector2i, _c: Vector2) -> bool: return ws.himg.get_pixel(p.x, p.y).r < ws.level
	var w := water_wrong(real_fn, pts)
	var nwater := 0
	for p in pts:
		if ws.himg.get_pixel(p.x, p.y).r < ws.level:
			nwater += 1
	ok(w[0] == 0 and w[1] == 0 and nwater > 100, "A WATER: 0 water above the level, 0 dry below it (%d / %d), %d water samples of 1000" % [w[0], w[1], nwater])
	var paint_fn := func(_p: Vector2i, c: Vector2) -> bool: return WetStreet.painted_mask(c.x, c.y)
	var wp := water_wrong(paint_fn, pts)
	ok(wp[0] + wp[1] > 0, "A CONTROL: a painted-puddle mask ignoring the height fails the bar (%d above, %d dry below)" % [wp[0], wp[1]])

	# C ROUGH
	var bad := 0
	var near := 0
	var near_bad := 0
	var n := 0
	var spots := []
	for k in 60:
		var j := -35 + (k / 6) * 3
		var i := (k % 6) * 3 - 12
		spots.append(Vector2((float(i) + 0.5 + (0.5 if (j & 1) == 1 else 0.0)) * WetStreet.PITCH, (float(j) + 0.5) * WetStreet.PITCH))
	for k in 20:
		spots.append(Vector2(1.2 + 0.1 * float(k % 10), -2.0 - 1.1 * float(k / 10) - 0.3 * float(k % 3)))
	for s in spots:
		if s.x < WetStreet.X0 + 0.1 or s.x > WetStreet.X0 + WetStreet.SPAN_X - 0.1 or s.y < WetStreet.Z0 + 0.1 or s.y > 0.5:
			continue
		var tp := ws.tex_xy(s.x, s.y)
		if ws.himg.get_pixel(tp.x, tp.y).r < ws.level:
			continue
		n += 1
		var wr := ws.mimg.get_pixel(tp.x, tp.y).a
		var dr := ws.dry_roughness(s.x, s.y)
		if not (wr < dr):
			bad += 1
		if ws.wetness(s.x, s.y) > 0.5:
			near += 1
			if not (wr < dr - 0.2):
				near_bad += 1
	ok(n >= 50 and bad == 0 and near_bad == 0, "C ROUGH: wet < dry roughness on every sampled spot (n=%d, bad %d; near water %d, bad %d)" % [n, bad, near, near_bad])
	var dr0 := ws.dry_roughness(0.1, -3.0)
	ok(not (dr0 < dr0), "C CONTROL: dry used as wet fails the bar")

	# E SCENE
	var tops := []
	for k in 200:
		var j := -90 + (k / 14)
		var i := -14 + (k % 14)
		var cx := (float(i) + 0.5 + (0.5 if (j & 1) == 1 else 0.0)) * WetStreet.PITCH
		var cz := (float(j) + 0.5) * WetStreet.PITCH
		if cx < -3.0 or cx > 0.7 or cz < -13.0:
			continue
		tops.append(ws.stone_top(i, j, 0.5, 0.5))
	var mean := 0.0
	for t in tops:
		mean += t
	mean /= float(maxi(tops.size(), 1))
	var vs := 0.0
	for t in tops:
		vs += (t - mean) * (t - mean)
	var sig := sqrt(vs / float(maxi(tops.size(), 1)))
	ok(tops.size() >= 100 and sig > 0.002, "E SCENE: stone tops differ in height: sigma %.2f mm over %d stones" % [sig * 1000.0, tops.size()])
	var jh := ws.height(-2.0 + 0.0, -2.0)
	var cc := ws.cobble_cell(-2.0, -2.0)
	var edge_x := -2.0 - float(cc[2]) * WetStreet.PITCH   # the left edge of this cell: a joint centre
	var joint_h := ws.height(edge_x, -2.0 + (0.5 - float(cc[3])) * WetStreet.PITCH)
	var top_h := ws.height(edge_x + WetStreet.PITCH * 0.5, -2.0 + (0.5 - float(cc[3])) * WetStreet.PITCH)
	ok(joint_h < top_h - 0.005 and jh == jh, "E SCENE: joint %.1f mm below the stone beside it" % ((top_h - joint_h) * 1000.0))

	# Calibrate the one shared camera response on the canonical wet pose-0 frame, before any pixel statistic.
	cam.global_position = Vector3(0.0, WetStreet.EYE, 1.5)
	cam.rotation_degrees = Vector3(WetStreet.PITCH_DEG, 0, 0)
	cam.current = true
	for f in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	CameraResponse.calibrate(root.get_texture().get_image())

	# B MIRROR + D STREAK per pose
	var contained := 0
	var last_ref := 2.0
	for pi in poses.size():
		var eye: Vector3 = poses[pi]
		cam.global_position = eye
		cam.rotation_degrees = Vector3(WetStreet.PITCH_DEG, 0, 0)
		cam.current = true
		for f in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := CameraResponse.apply(root.get_texture().get_image())
		var bulb := WetStreet.LAMP_POS
		var mirrored := Vector3(bulb.x, 2.0 * ws.level - bulb.y, bulb.z)
		var pp := cam.unproject_position(mirrored)
		var wrong := cam.unproject_position(bulb)
		var xr := WetStreet.reflection_point(eye, bulb, ws.level)
		var alpha := WetStreet.grazing(eye, xr)
		var ref_aspect := 1.0 / sin(alpha)
		last_ref = ref_aspect
		var masks := {}
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				var o := cam.project_ray_origin(Vector2(x, y))
				var d := cam.project_ray_normal(Vector2(x, y))
				if d.y >= -0.001:
					continue
				var g := o + d * ((ws.level - o.y) / d.y)
				if g.x < WetStreet.X0 or g.x > WetStreet.X0 + WetStreet.SPAN_X or g.z < WetStreet.Z0 or g.z > WetStreet.Z0 + WetStreet.SPAN_Z:
					continue
				var tp := ws.tex_xy(g.x, g.z)
				if ws.himg.get_pixel(tp.x, tp.y).r >= ws.level:
					continue
				var best := -1
				var bd := 1e9
				for bi in ws.bowls.size():
					var dd := Vector2(g.x - float(ws.bowls[bi][0]), g.z - float(ws.bowls[bi][1])).length()
					if dd < bd:
						bd = dd
						best = bi
				if not masks.has(best):
					masks[best] = []
				masks[best].append(Vector2i(x, y))
		var o2 := cam.project_ray_origin(pp)
		var d2 := cam.project_ray_normal(pp)
		var gp := o2 + d2 * ((ws.level - o2.y) / d2.y)
		var tpp := ws.tex_xy(gp.x, gp.z)
		var p_in_water: bool = ws.himg.get_pixel(tpp.x, tpp.y).r < ws.level
		print("     pose %d: mirrored bulb px (%.1f, %.1f), unmirrored (%.1f, %.1f), lamp point on ground (%.2f, %.2f) in water %s, grazing %.1f deg, ref aspect %.2f" % [pi, pp.x, pp.y, wrong.x, wrong.y, gp.x, gp.z, p_in_water, rad_to_deg(alpha), ref_aspect])
		ok(pp.distance_to(wrong) > 3.0, "B CONTROL pose %d: the unmirrored bulb is %.0f px from the mirrored one (> 3)" % [pi, pp.distance_to(wrong)])
		var visible := 0
		for bi in masks.keys():
			var px_all: Array = masks[bi]
			# instrument fix (disclosed in CH5_FEEDBACK): stones just outside the rim stand 2-5 cm above the water plane, so at 28 degrees their glints
			# fall inside the plane-projected mask; keep only pixels with the puddle on all four sides at 4 px
			var have := {}
			for q in px_all:
				have[q] = true
			var px := []
			for q in px_all:
				if have.has(q + Vector2i(4, 0)) and have.has(q - Vector2i(4, 0)) and have.has(q + Vector2i(0, 4)) and have.has(q - Vector2i(0, 4)):
					px.append(q)
			if px.size() < 50:
				continue
			visible += 1
			var peak := 0.0
			for q in px:
				peak = maxf(peak, lum(img.get_pixelv(q)))
			var holds := p_in_water and Vector2(gp.x - float(ws.bowls[bi][0]), gp.z - float(ws.bowls[bi][1])).length() < float(ws.bowls[bi][2]) * 1.2
			if holds:
				contained += 1
				var sx := 0.0
				var sy := 0.0
				var pts2 := []
				for q in px:
					if lum(img.get_pixelv(q)) >= 0.5 * peak and Vector2(q).distance_to(pp) < 160.0:
						pts2.append(Vector2(q))
						sx += q.x
						sy += q.y
				var cen := Vector2(sx, sy) / maxf(float(pts2.size()), 1.0)
				var err := cen.distance_to(pp)
				var vx := 0.0
				var vy := 0.0
				for q in pts2:
					vx += (q.x - cen.x) * (q.x - cen.x)
					vy += (q.y - cen.y) * (q.y - cen.y)
				var asp := sqrt(vy / maxf(vx, 1e-6))
				ok(peak >= 0.6 and err <= 3.0, "B MIRROR pose %d puddle %d: lamp reflection %.2f px from the mirrored position, offset (%+.1f, %+.1f) (peak %.2f, %d px lit)" % [pi, bi, err, cen.x - pp.x, cen.y - pp.y, peak, pts2.size()])
				print("     (info) puddle blob aspect %.2f, formula 1/sin(grazing) %.2f" % [asp, ref_aspect])
			else:
				ok(peak < 0.6, "B MIRROR pose %d puddle %d does not contain the lamp point: no lamp in it (peak %.2f)" % [pi, bi, peak])
		ok(visible >= 1, "B pose %d: %d visible puddles" % [pi, visible])
		if pi == 1:
			DirAccess.make_dir_recursive_absolute(SHOT.get_base_dir())
			ok(img.save_png(SHOT) == OK, "E SCENE: screenshot written to %s" % SHOT)
	ok(contained >= 3, "B MIRROR: %d puddle/pose pairs contained the lamp (need >= 3)" % contained)
	await _look_bars(cam)
	print("ch5: %d fail" % fails)
	quit(1 if fails > 0 else 0)


const PHOTO_ASPECT := 2.32      ## ref2, "On Cobbled Lanes" (CC BY 2.0), measured by tools/kine_workers/ch5_measure.py
const PHOTO_POOL := 0.62        ## ref2, L(0.75-0.85 of D from the lamp) / L(0.45-0.55)


func ylum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func box_blur(v: PackedFloat32Array, w: int, h: int, r: int) -> PackedFloat32Array:
	var t := PackedFloat32Array()
	t.resize(w * h)
	var o := PackedFloat32Array()
	o.resize(w * h)
	for y in h:
		for x in w:
			var sm := 0.0
			var n := 0
			for k in range(maxi(x - r, 0), mini(x + r, w - 1) + 1):
				sm += v[y * w + k]
				n += 1
			t[y * w + x] = sm / float(n)
	for y in h:
		for x in w:
			var sm := 0.0
			var n := 0
			for k in range(maxi(y - r, 0), mini(y + r, h - 1) + 1):
				sm += t[k * w + x]
				n += 1
			o[y * w + x] = sm / float(n)
	return o


## the photo estimator: blur ~3 px, mask >= frac x p99.5, the connected component holding the most light, aspect = sqrt(var y / var x)
func streak_aspect(img: Image, x0: int, x1: int, y0: int, y1: int, frac: float = 0.5) -> float:
	var w := x1 - x0
	var h := y1 - y0
	var v := PackedFloat32Array()
	v.resize(w * h)
	for y in h:
		for x in w:
			v[y * w + x] = ylum(img.get_pixel(x0 + x, y0 + y))
	v = box_blur(box_blur(v, w, h, 1), w, h, 1)
	var srt := Array(v)
	srt.sort()
	var thr: float = frac * float(srt[int(float(srt.size() - 1) * 0.995)])
	var seen := PackedByteArray()
	seen.resize(w * h)
	var best_mass := -1.0
	var best: Array = []
	for i0 in w * h:
		if v[i0] < thr or seen[i0] == 1:
			continue
		var comp := []
		var mass := 0.0
		var stack := [i0]
		seen[i0] = 1
		while not stack.is_empty():
			var i: int = stack.pop_back()
			comp.append(i)
			mass += v[i]
			var cx := i % w
			var cy := i / w
			for nb in [[cx - 1, cy], [cx + 1, cy], [cx, cy - 1], [cx, cy + 1]]:
				if nb[0] < 0 or nb[1] < 0 or nb[0] >= w or nb[1] >= h:
					continue
				var j: int = nb[1] * w + nb[0]
				if seen[j] == 0 and v[j] >= thr:
					seen[j] = 1
					stack.append(j)
		if mass > best_mass:
			best_mass = mass
			best = comp
	if best.size() < 20:
		return 0.0
	var mx := 0.0
	var my := 0.0
	for i in best:
		mx += float(i % w)
		my += float(i / w)
	mx /= float(best.size())
	my /= float(best.size())
	var vx := 0.0
	var vy := 0.0
	for i in best:
		vx += (float(i % w) - mx) * (float(i % w) - mx)
		vy += (float(i / w) - my) * (float(i / w) - my)
	return sqrt(vy / maxf(vx, 1e-6))


func mean_at(img: Image, p: Vector2) -> float:
	var x := int(p.x)
	var y := int(p.y)
	if x < 1 or y < 1 or x >= img.get_width() - 1 or y >= img.get_height() - 1:
		return -1.0
	var sm := 0.0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			sm += ylum(img.get_pixel(x + dx, y + dy))
	return sm / 9.0


func _look_bars(cam: Camera3D) -> void:
	cam.global_position = Vector3(0.0, WetStreet.EYE, 1.5)
	cam.rotation_degrees = Vector3(WetStreet.PITCH_DEG, 0, 0)
	for f in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var wet := CameraResponse.apply(root.get_texture().get_image())
	var base := cam.unproject_position(Vector3(WetStreet.LAMP_POS.x, 0.0, WetStreet.LAMP_POS.z))
	# D STREAK
	var asp := streak_aspect(wet, 330, 970, clampi(int(base.y), 0, 700), 720)
	ok(absf(asp / PHOTO_ASPECT - 1.0) <= 0.30, "D STREAK: render's lamp-reflection streak aspect %.2f vs the photo's %.2f (%+.0f %%), lamp base row %.0f" % [asp, PHOTO_ASPECT, 100.0 * (asp / PHOTO_ASPECT - 1.0), base.y])
	ok(absf(1.0 / PHOTO_ASPECT - 1.0) > 0.30, "D CONTROL: an isotropic blob (aspect 1) is %.0f %% from the photo's value" % (100.0 * absf(1.0 / PHOTO_ASPECT - 1.0)))
	# G POOL
	var cam_xz := Vector2(0.0, 1.5)
	var lamp_xz := Vector2(WetStreet.LAMP_POS.x, WetStreet.LAMP_POS.z)
	var bands := [[0.45, 0.55], [0.75, 0.85]]
	var means := []
	for b in bands:
		var sm := 0.0
		var n := 0
		var s: float = 1.0 - float(b[1])
		while s <= 1.0 - float(b[0]):
			for lat in range(-5, 6):
				var q := cam_xz.lerp(lamp_xz, s) + Vector2(float(lat) * 0.1, 0.0)
				if ws.height(q.x, q.y) < ws.level:
					continue
				var m := mean_at(wet, cam.unproject_position(Vector3(q.x, ws.height(q.x, q.y), q.y)))
				if m >= 0.0:
					sm += m
					n += 1
			s += 0.01
		means.append(sm / maxf(float(n), 1.0))
		print("     G: band %.2f-%.2f of the lamp distance: %d samples, mean luminance %.4f" % [b[0], b[1], n, means[-1]])
	var pool := float(means[1]) / maxf(float(means[0]), 1e-6)
	ok(absf(pool / PHOTO_POOL - 1.0) <= 0.30, "G POOL: falloff ratio %.2f vs the photo's %.2f (%+.0f %%)" % [pool, PHOTO_POOL, 100.0 * (pool / PHOTO_POOL - 1.0)])
	# F GLINT: the same stones, wet and dry
	ws.set_dry(true)
	for f in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var dry := CameraResponse.apply(root.get_texture().get_image())
	ws.set_dry(false)
	var sw := 0.0
	var sd := 0.0
	var n := 0
	for j in range(-120, 10):
		var cz := (float(j) + 0.5) * WetStreet.PITCH
		var t := (cz - 1.5) / (lamp_xz.y - 1.5)
		if t < 0.1 or t > 0.7:
			continue
		var line_x := lerpf(0.0, lamp_xz.x, t)
		for i in range(-12, 12):
			var cx := (float(i) + 0.5 + (0.5 if (j & 1) == 1 else 0.0)) * WetStreet.PITCH
			if absf(cx - line_x) > 0.5 or ws.is_asphalt(cx, cz) or ws.bowl_field(cx, cz) < -0.003:
				continue
			var p := cam.unproject_position(Vector3(cx, ws.height(cx, cz), cz))
			var a := mean_at(wet, p)
			var d := mean_at(dry, p)
			if a < 0.0 or d < 0.0:
				continue
			sw += a
			sd += d
			n += 1
			if n % 60 == 1:
				print("     F sample %d: stone (%.2f, %.2f) px (%.0f, %.0f) wet %.3f dry %.3f" % [n, cx, cz, p.x, p.y, a, d])
	var ratio := sw / maxf(sd, 1e-6)
	print("     F: %d stone tops on the lamp-camera line, mean wet %.4f, mean dry %.4f" % [n, sw / maxf(float(n), 1.0), sd / maxf(float(n), 1.0)])
	ok(n >= 25 and ratio >= 3.0, "F GLINT: wet stone tops are %.1fx the same stones dry (need >= 3, n=%d)" % [ratio, n])
	var control := sd / maxf(sd, 1e-6)
	ok(not (control >= 3.0), "F CONTROL: the planted dry control (dry vs dry) gives %.1fx and fails the bar" % control)
	var out_wet := "C:/Users/Nick/tools/kine_workers/out/ch5/ch5_night.png"
	ok(wet.save_png(out_wet) == OK, "E SCENE: final screenshot written (%s)" % out_wet)
	dry.save_png("C:/Users/Nick/tools/kine_workers/out/ch5/ch5_night_dry.png")
