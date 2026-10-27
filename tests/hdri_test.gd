## godot --path . -s tests/hdri_test.gd     (CG2 HDRI background and light; needs a window: the frames are read back from the screen)
## HDRI: a Radiance .hdr picture (written here: flat, one colour) is the sky behind the figure and the light on it.
## Bars, all on the pixels the user sees:
##   the background's mean colour is the picture's colour through sRGB: linear 0.5 -> 187.5 of 255, 1/16 -> 70.7
##   a white matte sphere lit only by the picture (lights: flat) reads the same as the background (albedo 1)
##   no picture: the gradient sky still works (blue at the top), sky off is the flat world colour
##   a file that is not a picture is refused and the view does not change
##   the picture comes back after a restart (the settings file), and goes away with Remove the picture
## Set HDRI_SHOT_DIR to write the frames there as PNG.
extends SceneTree

var fails := 0
var m: Node
const DIR := "user://hdri_test"


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> Image:
	await idle(3)
	await RenderingServer.frame_post_draw
	var img := m.get_viewport().get_texture().get_image()
	var dir := OS.get_environment("HDRI_SHOT_DIR")
	if dir != "":
		img.save_png(dir + "/" + name + ".png")
	return img


## the mean colour of a square of pixels around (cx, cy), 0-255 per channel
func patch(img: Image, cx: int, cy: int, r: int) -> Vector3:
	var s := Vector3.ZERO
	var n := 0
	for x in range(cx - r, cx + r + 1):
		for y in range(cy - r, cy + r + 1):
			var c := img.get_pixel(x, y)
			s += Vector3(c.r, c.g, c.b) * 255.0
			n += 1
	return s / n


## the background: a patch in the top-left corner, clear of the figure
func corner(img: Image) -> Vector3:
	return patch(img, 40, 40, 10)


## a Radiance .hdr (flat RGBE, uniform colour v): v = f * 2^e with f in [0.5, 1), each byte = f * 256
func write_hdr(path: String, w: int, h: int, v: float) -> void:
	var e := int(floor(log(v) / log(2.0))) + 1
	var b := int(floor(v / pow(2.0, e) * 256.0))
	var px := PackedByteArray()
	for i in w * h:
		px.append_array([b, b, b, e + 128])
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % [h, w])
	f.store_buffer(px)
	f.close()


func _item(pm: PopupMenu, text: String) -> int:
	for i in pm.item_count:
		if pm.get_item_text(i) == text:
			return i
	return -1


func srgb(lin: float) -> float:
	return 255.0 * (1.055 * pow(lin, 1.0 / 2.4) - 0.055)


func near(a: Vector3, want: float, tol: float) -> bool:
	return absf(a.x - want) <= tol and absf(a.y - want) <= tol and absf(a.z - want) <= tol


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	m.settings = DIR + "/settings.cfg"   # the test's own settings, never the user's
	for p in m.ui_side:
		p.visible = false
	m.ui_root.visible = false
	m.clean = true
	m.big_view = true
	m.dist = 4.6
	m.target = Vector3(0, 1.05, 0.2)
	m._cam()
	if m.dummy_on:
		m._dummy_toggle()
	m._refresh()

	# a matte white sphere to the right of the figure, in front of the camera: its colour is the light alone
	var sph := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.25
	sm.height = 0.5
	sph.mesh = sm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color.WHITE
	wm.roughness = 1.0
	sph.material_override = wm
	m.add_child(sph)
	var cam: Camera3D = m.cam
	sph.global_position = cam.global_position - cam.global_transform.basis.z * 2.5 + cam.global_transform.basis.x * 0.9
	var sp := cam.unproject_position(sph.global_position)
	var scx := int(sp.x)
	var scy := int(sp.y)

	# 1. sky off: the flat world colour
	m.shading.sky = false
	m.shading.apply_sky(m)
	var flat := await shot("flat")
	var want_world := Tok.c("world")
	var cf := corner(flat)
	ok(absf(cf.x - want_world.r * 255.0) <= 2 and absf(cf.y - want_world.g * 255.0) <= 2 and absf(cf.z - want_world.b * 255.0) <= 2,
		"sky off: the corner is the flat world colour %s (bar: within 2 of %s)" % [cf, want_world])

	# 2. the gradient sky, as the user turns it on (View: sky background)
	m._sky_toggle()
	var grad := await shot("gradient")
	var cg := corner(grad)
	ok(cg.z - cg.x > 30.0, "no picture: the gradient sky is blue at the top: r %.0f, b %.0f (bar: blue - red > 30)" % [cg.x, cg.z])

	# 3. a picture at linear 0.5 (sRGB 187.5): the background and the sphere it lights
	write_hdr(DIR + "/half.hdr", 64, 32, 0.5)
	ok(m.shading.load_hdri(m, DIR + "/half.hdr"), "a .hdr picture loads (bar: true)")
	m._lights_set("flat")   # the sphere is lit by the sky alone
	var half := await shot("half")
	var lp: PopupMenu = m.ui_light_btn.get_popup()
	var pick := _item(lp, "Picture background (.hdr / .exr)...")
	ok(pick >= 0 and not lp.is_item_disabled(pick), "the Studio lights menu offers the picture (bar: an enabled item)")
	var clr := _item(lp, "Remove the picture")
	ok(clr >= 0 and not lp.is_item_disabled(clr), "with a picture on, Remove the picture is enabled (bar: enabled)")
	var ch := corner(half)
	var want_half := srgb(0.5)
	ok(near(ch, want_half, 3.0), "picture 0.5: the background mean %s, expected %.1f each channel (bar: within 3)" % [ch, want_half])
	var sh := patch(half, scx, scy, 3)
	ok(near(sh, want_half, 4.0), "picture 0.5: the lit sphere mean %s, expected %.1f (albedo 1 under sky light: bar within 4)" % [sh, want_half])

	# 4. a picture at linear 1/16 (sRGB 70.7): the change is the picture's, not the gradient's
	write_hdr(DIR + "/dark.hdr", 64, 32, 0.0625)
	ok(m.shading.load_hdri(m, DIR + "/dark.hdr"), "a second picture at 1/16 loads (bar: true)")
	var dark := await shot("dark")
	var cd := corner(dark)
	var want_dark := srgb(0.0625)
	ok(near(cd, want_dark, 3.0), "picture 1/16: the background mean %s, expected %.1f (bar: within 3)" % [cd, want_dark])
	var sd := patch(dark, scx, scy, 3)
	ok(near(sd, want_dark, 4.0), "picture 1/16: the lit sphere mean %s, expected %.1f (bar: within 4)" % [sd, want_dark])
	ok(cd.x < ch.x - 100.0, "the darker picture darkens the background by the expected 117 levels: %.0f -> %.0f" % [ch.x, cd.x])

	# 5. a file that is not a picture is refused and the view stays the same
	var bad := DIR + "/broken.hdr"
	var fb := FileAccess.open(bad, FileAccess.WRITE)
	fb.store_string("this is not a picture")
	fb.close()
	ok(not m.shading.load_hdri(m, bad), "a text file named .hdr is refused (bar: false)")
	ok(m.shading.hdri == DIR + "/dark.hdr", "the picture on the view is still the last good one: %s" % m.shading.hdri.get_file())
	var after_bad := corner(await shot("after_bad"))
	ok(near(after_bad, want_dark, 3.0), "after the refused file the background is unchanged: %s (bar: within 3 of %.1f)" % [after_bad, want_dark])

	# 6. the picture comes back after a restart (the settings file)
	m.shading.save_cfg(m)
	var s2 := Shading.new()
	s2.load_cfg(m)
	ok(s2.hdri == DIR + "/dark.hdr" and s2.sky, "after a restart the picture and the sky are back: %s, sky %s" % [s2.hdri.get_file(), s2.sky])
	var back := corner(await shot("restart"))
	ok(near(back, want_dark, 3.0), "after a restart the background is the picture again: %s (bar: within 3 of %.1f)" % [back, want_dark])

	# 7. Remove the picture: the gradient again, and the sphere is no longer lit by it
	m._hdri_clear()
	var gone := await shot("removed")
	var cr := corner(gone)
	ok(cr.z - cr.x > 30.0, "remove the picture: the gradient is back: r %.0f, b %.0f (bar: blue - red > 30)" % [cr.x, cr.z])
	var sr := patch(gone, scx, scy, 3)
	ok(absf(sr.x - want_dark) > 50.0, "remove the picture: the sphere is no longer lit by it: %s (bar: more than 50 away from %.1f)" % [sr, want_dark])
	ok(lp.is_item_disabled(_item(lp, "Remove the picture")), "with no picture, Remove the picture is greyed out (bar: disabled)")

	sph.queue_free()
	print("FAILS %d" % fails)
	quit(fails)
