## godot --path . -s tests/photomat_test.gd     (ROADMAP_400 E15, windowed: "Surface: material from a photo...")
## A synthetic photo, generated here: a brick pattern (128 x 64 bricks, 6 px mortar, a colour per brick) under a strong
## left-to-right lighting gradient (x 0.15 -> 1.0 of the light). Bars, stated before measuring:
##   1 DE-LIT: the photo's left / right half mean luminance differ by > 50% (input check); the albedo's differ by < 10%
##   2 TILEABLE: the albedo's last column vs its first, mean abs RGB difference < 0.03 (the photo's own is reported)
##   3 NORMAL: a bump picture (a bright square on dark) has its LEFT edge normals with x < 0 (red < 0.5), its right edge
##     x > 0, its top edge y > 0 (green > 0.5: tangent space, +y up), a flat area is (0.5, 0.5, 1)
##   4 ROUGH: a half-flat half-noisy picture: the noisy half's mean roughness > the flat half's + 0.2
##   5 TIME: 1024 x 1024 through make() in < 3 s
##   6 FILES: user://materials/<name>/{albedo,rough,normal}.png + material.tres exist, the PNGs read back to the maps,
##     the .tres names the three PNGs, the loaded material has all three textures; scenes/ is unchanged
##   7 APPLY + UNDO: on a prop and on a body part, applying is ONE undo step, Ctrl+Z restores (prop has no "mat" again,
##     the part's override is gone), redo brings it back; the prop's "mat" round-trips the scene dict form; under matcap shading a redone
##     part material leaves the matcap look on, and back in solid the part wears it
##   8 PLACEMENT: a crate in the whole view: the mean chromaticity of the pixels in its screen box moves toward the
##     albedo's mean chromaticity (distance after < half of the distance before); after Ctrl+Z it is back (< 0.01)
## Shot: C:/Users/Nick/.claude/jobs/9afc22db/tmp/photomat.png
extends SceneTree

const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/photomat.png"
const NAME := "photomat_test"
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 4) -> void:
	for i in n:
		await process_frame


func scenes_listing() -> String:
	var out := []
	for d in ["res://scenes", "res://scenes/_wip"]:
		var da := DirAccess.open(d)
		if da == null:
			continue
		var fs := Array(da.get_files())
		fs.sort()
		for f in fs:
			out.append("%s/%s:%d" % [d, f, FileAccess.get_modified_time(d + "/" + f)])
	return "\n".join(out)


func brick_photo(n: int) -> Image:
	var img := Image.create(n, n, false, Image.FORMAT_RGBF)
	var bw := n / 8
	var bh := n / 16
	var mortar := 6
	for col in n:
		var lit := 0.15 + 0.85 * float(col) / float(n - 1)
		img.fill_rect(Rect2i(col, 0, 1, n), Color(0.62, 0.6, 0.55) * lit)
	for row in 16:
		var off := (bw / 2) if row % 2 == 1 else 0
		for k in 9:
			var x0 := k * bw - off
			var h := (row * 31 + k * 17) % 100 / 100.0
			var c := Color(0.62 + 0.15 * h, 0.27 + 0.1 * h, 0.2)
			for col in range(maxi(0, x0 + mortar / 2), mini(n, x0 + bw - mortar / 2)):
				var lit := 0.15 + 0.85 * float(col) / float(n - 1)
				img.fill_rect(Rect2i(col, row * bh + mortar / 2, 1, bh - mortar), Color(c.r * lit, c.g * lit, c.b * lit))
	return img


func bump_photo() -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.2, 0.2))
	img.fill_rect(Rect2i(16, 16, 32, 32), Color(0.8, 0.8, 0.8))
	return img


func box_chroma(img: Image, r: Rect2i) -> Vector2:
	var c := Vector3.ZERO
	var n := 0
	for y in range(r.position.y, r.end.y, 2):
		for x in range(r.position.x, r.end.x, 2):
			var p := img.get_pixel(x, y)
			c += Vector3(p.r, p.g, p.b)
			n += 1
	c /= float(n)
	var s := c.x + c.y + c.z
	return Vector2(c.x / s, c.y / s)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var before := scenes_listing()
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(3)
	# ---- 1, 2, 5: the brick photo
	var photo := brick_photo(1024)
	var pl := PhotoMaterial.mean_lum(photo, Rect2i(0, 0, 512, 1024))
	var pr := PhotoMaterial.mean_lum(photo, Rect2i(512, 0, 512, 1024))
	var t0 := Time.get_ticks_msec()
	var maps := PhotoMaterial.make(photo)
	var ms := Time.get_ticks_msec() - t0
	var alb: Image = maps["albedo"]
	var al := PhotoMaterial.mean_lum(alb, Rect2i(0, 0, 512, 1024))
	var ar := PhotoMaterial.mean_lum(alb, Rect2i(512, 0, 512, 1024))
	var in_d := absf(pl - pr) / maxf(pl, pr)
	var out_d := absf(al - ar) / maxf(al, ar)
	ok(in_d > 0.5, "the photo's halves differ by %.0f%% (> 50%%): left %.3f right %.3f" % [in_d * 100.0, pl, pr])
	ok(out_d < 0.10, "the de-lit albedo's halves differ by %.1f%% (< 10%%): left %.3f right %.3f" % [out_d * 100.0, al, ar])
	var seam := PhotoMaterial.seam_diff(alb)
	ok(seam < 0.03, "tileable: last column vs first mean abs %.4f (< 0.03); the photo's own %.4f" % [seam, PhotoMaterial.seam_diff(photo)])
	print("     normal seam %.4f" % PhotoMaterial.seam_diff(maps["normal"]))
	ok(ms < 3000, "1024 x 1024 through make(): %d ms (< 3000)" % ms)
	ok(alb.get_width() == 1024 and (maps["rough"] as Image).get_size() == alb.get_size() and (maps["normal"] as Image).get_size() == alb.get_size(), "the three maps are 1024 x 1024")
	# ---- 3: the bump
	var nm := PhotoMaterial.normal_map(bump_photo(), 3.0)
	var le := nm.get_pixel(16, 32)
	var re := nm.get_pixel(47, 32)
	var te := nm.get_pixel(32, 16)
	var be := nm.get_pixel(32, 47)
	var fl := nm.get_pixel(32, 32)
	ok(le.r < 0.45 and re.r > 0.55 and te.g > 0.55 and be.g < 0.45, "bump normals point out: left x %.2f (<0.5), right x %.2f (>0.5), top y %.2f (>0.5), bottom y %.2f (<0.5)" % [le.r, re.r, te.g, be.g])
	ok(absf(fl.r - 0.5) < 0.01 and absf(fl.g - 0.5) < 0.01 and fl.b > 0.99, "flat area is (0.5, 0.5, 1): %s" % fl)
	# ---- 4: the roughness
	var rimg := Image.create(256, 256, false, Image.FORMAT_RGB8)
	rimg.fill(Color(0.5, 0.5, 0.5))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in 256:
		for x in range(128, 256):
			var v := 0.5 + rng.randf_range(-0.25, 0.25)
			rimg.set_pixel(x, y, Color(v, v, v))
	var rr: Image = PhotoMaterial.make(rimg)["rough"]
	var rf := 0.0
	var rn := 0.0
	for y in range(40, 216, 4):
		for x in range(20, 100, 4):
			rf += rr.get_pixel(x, y).r
		for x in range(150, 230, 4):
			rn += rr.get_pixel(x, y).r
	rf /= 44.0 * 20.0
	rn /= 44.0 * 20.0
	ok(rn > rf + 0.2, "roughness: the noisy half %.2f > the flat half %.2f + 0.2" % [rn, rf])
	# ---- 6: files
	var dir := PhotoMaterial.save(NAME, maps)
	ok(dir == "user://materials/" + NAME, "saved to %s" % dir)
	var back := Image.load_from_file(dir + "/albedo.png")
	ok(FileAccess.file_exists(dir + "/rough.png") and FileAccess.file_exists(dir + "/normal.png") and FileAccess.file_exists(dir + "/material.tres") and back.get_size() == alb.get_size() and absf(back.get_pixel(300, 300).g - alb.get_pixel(300, 300).g) < 0.005, "albedo/rough/normal.png and material.tres are there; the albedo reads back")
	var tres := FileAccess.get_file_as_string(dir + "/material.tres")
	ok(tres.contains(dir + "/albedo.png") and tres.contains(dir + "/rough.png") and tres.contains(dir + "/normal.png") and tres.contains("StandardMaterial3D"), "the .tres is a StandardMaterial3D naming the three PNGs")
	var lm := PhotoMaterial.load_material(NAME)
	ok(lm != null and lm.albedo_texture != null and lm.roughness_texture != null and lm.normal_texture != null and lm.normal_enabled, "the loaded material has albedo, roughness and normal textures")
	# ---- 7, 8: apply on a prop, in the view
	var photo_path := ProjectSettings.globalize_path("user://" + NAME + "_in.png")
	photo.save_png(photo_path)
	m.S.props = [Props.make("crate", Props.xf_at(Vector3(0, 0, 0.6), 20.0))]
	m.sel_prop = -1
	m._props_show()
	m.yaw = 0.0
	m.pitch = -10.0
	m.dist = 2.4
	m.target = Vector3(0, 0.3, 0.6)
	m._cam()
	await idle(5)
	var corners := []
	for sx in [-0.3, 0.3]:
		for sy in [0.0, 0.5]:
			for sz in [-0.2, 0.2]:
				corners.append(m.cam.unproject_position((m.S.props[0]["xf"] as Transform3D) * Vector3(sx, sy, sz)))
	var bx := Rect2(corners[0], Vector2.ZERO)
	for c in corners:
		bx = bx.expand(c)
	var box := Rect2i(Vector2i(bx.position + bx.size * 0.25), Vector2i(bx.size * 0.5))
	m.ui_root.visible = false
	await idle(5)
	var img0 := root.get_texture().get_image()
	var ch0 := box_chroma(img0, box)
	m.undo.clear()
	m.redo.clear()
	m.sel_prop = 0
	var n0: int = m.undo.size()
	ok(m.photomat.apply(photo_path, NAME + "_prop", 3.0), "applied to the prop: %s" % [m.photomat.last])
	ok(m.undo.size() == n0 + 1 and String(m.S.props[0].get("mat", "")) == NAME + "_prop", "ONE undo step (%d -> %d) and the prop carries the name" % [n0, m.undo.size()])
	ok(Props.from_dict(Props.to_dict(m.S.props[0])).get("mat", "") == NAME + "_prop", "the prop's material name round-trips the scene dict form")
	m.sel_prop = -1
	m._props_show()
	m.ui_root.visible = false
	await idle(5)
	var img1 := root.get_texture().get_image()
	var ch1 := box_chroma(img1, box)
	var am := Vector3.ZERO
	var sw := alb.get_width()
	for y in range(0, sw, 16):
		for x in range(0, sw, 16):
			var p := alb.get_pixel(x, y)
			am += Vector3(p.r, p.g, p.b)
	am /= float((sw / 16) * (sw / 16))
	var cha := Vector2(am.x / (am.x + am.y + am.z), am.y / (am.x + am.y + am.z))
	var d0 := ch0.distance_to(cha)
	var d1 := ch1.distance_to(cha)
	ok(d1 < d0 * 0.5, "PLACEMENT: the crate's screen box %s moves toward the albedo's chromaticity %s: distance %.3f -> %.3f (grey box was %s, now %s)" % [box, cha, d0, d1, ch0, ch1])
	# the shot
	var maps_row := Image.create(3 * 264, 264, false, Image.FORMAT_RGB8)
	maps_row.fill(Color(0.1, 0.1, 0.1))
	for i in 3:
		var mi: Image = (maps[["albedo", "rough", "normal"][i]] as Image).duplicate()
		mi.convert(Image.FORMAT_RGB8)
		mi.resize(256, 256, Image.INTERPOLATE_BILINEAR)
		maps_row.blit_rect(mi, Rect2i(0, 0, 256, 256), Vector2i(i * 264 + 4, 4))
	img1.convert(Image.FORMAT_RGB8)
	var canvas := Image.create(img1.get_width(), 264 + img1.get_height(), false, Image.FORMAT_RGB8)
	canvas.fill(Color(0.1, 0.1, 0.1))
	canvas.blit_rect(maps_row, Rect2i(0, 0, maps_row.get_width(), 264), Vector2i(0, 0))
	canvas.blit_rect(img1, Rect2i(Vector2i.ZERO, img1.get_size()), Vector2i(0, 264))
	DirAccess.make_dir_recursive_absolute(SHOT.get_base_dir())
	canvas.save_png(SHOT)
	m.ui_root.visible = true
	# undo / redo
	m._undo()
	ok(not m.S.props[0].has("mat"), "Ctrl+Z: the prop has no material again")
	m.sel_prop = -1
	m._props_show()
	m.ui_root.visible = false
	await idle(5)
	var ch2 := box_chroma(root.get_texture().get_image(), box)
	ok(ch2.distance_to(ch0) < 0.01, "after Ctrl+Z the box reads as before: %s vs %s" % [ch2, ch0])
	m.ui_root.visible = true
	m._redo()
	ok(String(m.S.props[0].get("mat", "")) == NAME + "_prop", "redo brings the material back")
	# a body part
	m.sel_prop = -1
	m.sel = "upperarm_r"
	var n1: int = m.undo.size()
	ok(m.photomat.apply(photo_path, NAME + "_part", 3.0), "applied to the body part %s" % m.sel)
	var piece: MeshInstance3D = m.pieces["upperarm_r"]
	ok(m.undo.size() == n1 + 1 and piece.material_override != null and m.body_mats.get("upperarm_r", "") == NAME + "_part", "body part: ONE undo step and the piece wears the material")
	m._undo()
	ok(piece.material_override == null and not m.body_mats.has("upperarm_r"), "Ctrl+Z: the part is back to the mannequin's skin")
	# under a view shading mode: the mode's look stays, and "solid" brings the photo material
	m.shading.set_mode(m, "matcap")
	var mc: Material = piece.material_override
	m._redo()
	ok(piece.material_override == mc and mc != null and m.body_mats.has("upperarm_r"), "under matcap the redone material does not replace the matcap look")
	m.shading.set_mode(m, "solid")
	ok(piece.material_override != null and piece.material_override == PhotoMaterial.load_material(NAME + "_part"), "back to solid shading: the part wears the photo material")
	m._undo()
	ok(piece.material_override == null, "Ctrl+Z in solid: the mannequin's skin again")
	# no target: refuses
	m.sel_prop = -1
	m.sel = Body.WEAPON[0]   # a weapon is no body part with a piece: nothing to dress
	ok(not m.photomat.apply(photo_path, "x", 3.0), "with nothing picked, apply refuses (and says to pick a prop or a part)")
	ok(scenes_listing() == before, "scenes/ is unchanged")
	print("FAILS: %d" % fails if fails > 0 else "photomat ok")
	quit(1 if fails > 0 else 0)
