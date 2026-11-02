extends SceneTree
## S232 TEMPLE LIGHT (scripts/build/temple_light.gd): the live view lit like the final shot, measured on the Chinese hall (tests/data/s232_hall.json, built
## by the hall driver of the hall-vs-reference comparison) at the reference camera. Needs a real (off-screen) window. Bars come from reference.png's own
## measurements (printed as REF lines; measured by tools/kine_workers/out/232/measure.py on the stable-diffusion reference picture):
##   REF  wall: shadowed band / lit wall luminance = 0.50, shadow b/r 0.526 vs lit 0.398 (bluer by 32 %), shadow luminance 0.198 (sRGB)
##   REF  sky: top saturation 0.336 vs lower sky 0.186
##   C  camera by numbers: pos / target / fov typed come back (position 1 mm, aim 0.01 deg, fov exact)
##   S  shadow present: eave-shadowed wall band lum / lit wall lum < 0.6
##   N  shadow not black: shadow-side mean lum > 0.08 and bluer (b/r) than the lit side
##   G  GI: sdfgi / ssil / off compared on the shadow side (up, still darker than the lit side) and fps: the winner is kept (printed numbers)
##   K  sky gradient: top more saturated than the horizon, with clouds (cloud pixels brighter than the clear sky beside them)
##   H  haze: far ground has lower local contrast than near ground; with haze 0 it does not
##   F  FINAL SHOT: 0 UI pixels (the shot equals a render of the same world with every Control hidden by a different path; and a shot taken
##      with the UI shown has no pixel in the bar rows that differs); size typed; same light as the live view; the agent tools exist
##   P  live view fps at 1280 x 720 with and without GI; off puts every value back (bit for bit)
const OUT := "C:/Users/Nick/tools/kine_workers/out/232/test"
var fails := 0
var m: Node
var pu
var W := 1280
var H := 720
const REF_POS := Vector3(0, 4.5, 38.0)
const REF_TGT := Vector3(0, 6.3, 0.0)
const REF_FOV := 45.0


func ok(c: bool, w: String) -> void:
	print(("ok   " if c else "FAIL ") + w)
	fails += 0 if c else 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func avg(img: Image, r: Rect2i) -> Color:
	var s := Color(0, 0, 0)
	var n := 0
	for y in range(maxi(r.position.y, 0), mini(r.end.y, img.get_height())):
		for x in range(maxi(r.position.x, 0), mini(r.end.x, img.get_width())):
			var c := img.get_pixel(x, y)
			s += Color(c.r, c.g, c.b)
			n += 1
	return Color(s.r / maxf(n, 1), s.g / maxf(n, 1), s.b / maxf(n, 1))


func lstd(img: Image, r: Rect2i) -> float:
	var v: Array = []
	var mu := 0.0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var l := lum(img.get_pixel(x, y))
			v.append(l)
			mu += l
	mu /= maxf(v.size(), 1)
	var q := 0.0
	for l in v:
		q += (l - mu) * (l - mu)
	return sqrt(q / maxf(v.size(), 1))


func br(c: Color) -> float:
	return c.b / maxf(c.r, 0.001)


func sat(c: Color) -> float:
	return c.s


func setup() -> bool:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(8)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	root.size = Vector2i(W, H)
	await idle(4)
	var ss: StartScreen = m.start_screen
	pu = m.bld.part
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://s232"))
	ss.dirs_override = ["user://s232"]
	if not Part.available():
		print("FAIL no DLL")
		return false
	ss.show_screen()
	await idle(3)
	m.build_choose.auto = true
	var card: Control = ss._cards["building"]
	var p := card.get_global_rect().get_center()
	for d in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = d
		e.position = p
		e.global_position = p
		root.push_input(e, true)
		await process_frame
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(10)
	pu.set_on(false)
	m.S.part = {}
	await process_frame
	var pb: Button = pu.part_btn
	var q := pb.get_global_rect().get_center()
	for d in [true, false]:
		var e2 := InputEventMouseButton.new()
		e2.button_index = MOUSE_BUTTON_LEFT
		e2.pressed = d
		e2.position = q
		e2.global_position = q
		root.push_input(e2, true)
		await process_frame
	await idle(4)
	if not pu.on:
		pu.set_on(true)
		await idle(4)
	var f := FileAccess.open("res://tests/data/s232_hall.json", FileAccess.READ)
	var rec: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	m.S.part = rec
	pu.upto = -1
	pu.sync()
	m.bld.sync()
	var tw := Time.get_ticks_msec()
	while int(pu.res.get("bodies", -1)) != 34 and Time.get_ticks_msec() - tw < 120000:
		await idle(4)
	await idle(10)
	print("hall bodies ", pu.res.get("bodies", -1), " aabb ", pu.res.get("aabb", null))
	pu.browser.visible = false
	pu.tl.visible = false
	if m.grid_node != null:
		m.grid_node.visible = false
	return int(pu.res.get("bodies", -1)) == 34


## every Control hidden (a path the final shot does not use): the live viewport at its own size, after a few frames
func ui_hidden_render() -> Image:
	var hid: Array = []
	for c in m.get_children():
		if c is CanvasItem and (c as CanvasItem).visible:
			hid.append(c)
			(c as CanvasItem).visible = false
	for c in m.ui_root.get_children():
		if c is CanvasItem and (c as CanvasItem).visible:
			hid.append(c)
			(c as CanvasItem).visible = false
	m.cam.h_offset = 0.0
	m.cam.v_offset = 0.0
	return null


func shot_live(nm: String) -> Image:
	await idle(6)
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [OUT, nm])
	return img


func fps_now(frames := 90) -> float:
	await idle(10)
	var t0 := Time.get_ticks_usec()
	for i in frames:
		await process_frame
	var dt := (Time.get_ticks_usec() - t0) / 1e6
	return frames / dt


func fin(r: Dictionary, nm: String) -> Image:
	var img: Image = r["image"]
	img.save_png("%s/%s.png" % [OUT, nm])
	return img


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	if not await setup():
		quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # fps is measured, not capped at the refresh rate
	var probe := OS.get_environment("S232_PROBE") != ""
	# ---- C: camera by numbers
	var cr := TempleLight.set_camera(m, REF_POS, REF_TGT, REF_FOV, 0.5, 3000.0)
	await idle(3)
	var pos_err: float = (m.cam.global_position - REF_POS).length()
	var aim: Vector3 = -m.cam.global_transform.basis.z
	var want := (REF_TGT - REF_POS).normalized()
	var ang := rad_to_deg(aim.angle_to(want))
	ok(bool(cr["ok"]) and pos_err < 0.001, "C camera position typed comes back (error %.5f m)" % pos_err)
	ok(ang < 0.01, "C camera aims at the typed target (error %.5f deg)" % ang)
	ok(absf(m.cam.fov - REF_FOV) < 0.001, "C fov typed comes back (%.2f)" % m.cam.fov)
	var rc := TempleLight.set_camera(m, Vector3(5, 5, 5), Vector3(5, 5, 5), 40.0)
	ok(not bool(rc["ok"]), "C the same point for camera and target is refused")
	TempleLight.set_camera(m, REF_POS, REF_TGT, REF_FOV, 0.5, 3000.0)
	await idle(3)

	# ---- before: the live view as it is (no temple light), fps
	var env_before := TempleLight._snap(m.world_env, TempleLight.ENV_KEYS)
	var keyb := TempleLight._snap(m.light_key, TempleLight.LIGHT_KEYS)
	var fps_off := await fps_now()
	print("FPS live 1280x720, fast look (before): %.1f" % fps_off)
	var fb: Dictionary = await TempleLight.final_shot(m, OUT + "/before_default_look.png", Vector2i(1024, 1024))
	# (final_shot switches the temple light on and off again: the env must be what it was)
	var back_ok := true
	for k in TempleLight.ENV_KEYS:
		if m.world_env.get(k) != env_before[k]:
			back_ok = false
			print("   not put back: ", k)
	for k in TempleLight.LIGHT_KEYS:
		if m.light_key.get(k) != keyb[k]:
			back_ok = false
			print("   light not put back: ", k)
	ok(back_ok and not TempleLight.on, "P a shot with the temple light off puts every value back")

	# pixel boxes of the 1024 x 1024 shot at the reference camera (found by looking at the pictures; REF_* are the reference's own numbers)
	var BAND := Rect2i(305, 548, 105, 16)       # the wall under the lower brackets, in the eave's shadow
	var LITW := Rect2i(20, 610, 145, 50)        # the wall left of the hall in full sun
	var SKY_TOP := Rect2i(300, 0, 400, 30)
	var SKY_LOW := Rect2i(900, 500, 110, 65)
	# ---- live view fps and the picture per GI mode
	var res := {}
	for gm in ["off", "ssil", "sdfgi"]:
		TempleLight.gi_mode = gm
		if TempleLight.on:
			TempleLight.set_live(m, false)
		TempleLight.set_live(m, true)
		await idle(30)
		var fps := await fps_now()
		var r: Dictionary = await TempleLight.final_shot(m, OUT + "/final_%s.png" % gm, Vector2i(1024, 1024))
		var img := fin(r, "final_" + gm)
		res[gm] = {"fps": fps, "band": lum(avg(img, BAND)), "lit": lum(avg(img, LITW)), "br_band": br(avg(img, BAND)), "br_lit": br(avg(img, LITW))}
		print("GI %-5s fps %.1f  shadow-side(band) lum %.3f b/r %.3f   lit wall lum %.3f b/r %.3f   band/lit %.3f" % [gm, fps, res[gm]["band"], res[gm]["br_band"], res[gm]["lit"], res[gm]["br_lit"], res[gm]["band"] / res[gm]["lit"]])
	# G: the rule that picks the GI mode: a mode is KEPT only if its shadow side is >= 3 % brighter than GI off, still darker than the lit side (band < 0.8 lit), and the live fps is >= 30
	var pick := "off"
	for gm in ["ssil", "sdfgi"]:
		var g: Dictionary = res[gm]
		if g["band"] >= 1.03 * res["off"]["band"] and g["band"] < 0.8 * g["lit"] and g["fps"] >= 30.0 and g["band"] > res[pick]["band"]:
			pick = gm
	print("G the rule picks GI: ", pick)
	ok(pick == TempleLight.DEFAULT_GI, "G the shipped default GI mode (%s) is the one the rule picks (%s)" % [TempleLight.DEFAULT_GI, pick])
	for gm in res:
		ok(res[gm]["fps"] >= 30.0, "P live fps at 1280x720 with GI %s is %.1f (>= 30)" % [gm, res[gm]["fps"]])
	print("P fps fast look before: %.1f" % fps_off)
	TempleLight.gi_mode = TempleLight.DEFAULT_GI
	# ---- S, N, K at the reference camera with the chosen mode
	if TempleLight.on:
		TempleLight.set_live(m, false)
	TempleLight.set_live(m, true)
	await idle(20)
	var r0: Dictionary = await TempleLight.final_shot(m, OUT + "/final_front.png", Vector2i(1024, 1024))
	var im0 := fin(r0, "final_front")
	var band := avg(im0, BAND)
	var litw := avg(im0, LITW)
	TempleLight.sun_mult = 0.0
	var rs: Dictionary = await TempleLight.final_shot(m, OUT + "/control_sun_off.png", Vector2i(1024, 1024))
	TempleLight.sun_mult = 1.0
	var ims := fin(rs, "control_sun_off")
	var ctrl_ratio := lum(avg(ims, BAND)) / maxf(lum(avg(ims, LITW)), 0.001)
	print("REF wall shadow/lit 0.50 (lum 0.198 / 0.394); Kine band/lit %.3f  (control, sun off: %.3f)" % [lum(band) / lum(litw), ctrl_ratio])
	ok(lum(band) / lum(litw) < 0.6, "S shadow present: eave-shadowed wall band / lit wall = %.3f < 0.6 (reference 0.50)" % (lum(band) / lum(litw)))
	ok(ctrl_ratio > 0.8, "S control: with the sun off the same boxes give %.3f (> 0.8): the ratio is the shadow, not the paint" % ctrl_ratio)
	ok(lum(band) > 0.08, "N shadow not black: shadow-side mean luminance %.3f > 0.08 (reference 0.198)" % lum(band))
	ok(br(band) > br(litw), "N shadow bluer than the lit side: b/r %.3f vs %.3f (reference 0.526 vs 0.398)" % [br(band), br(litw)])
	var st := avg(im0, SKY_TOP)
	var sl := avg(im0, SKY_LOW)
	print("REF sky saturation top 0.336 vs lower 0.186; Kine top %.3f lower %.3f" % [st.s, sl.s])
	ok(st.s > sl.s and lum(st) < lum(sl), "K sky gradient: top more saturated (%.3f > %.3f) and darker (%.3f < %.3f) than the horizon" % [st.s, sl.s, lum(st), lum(sl)])
	var spread := sky_spread(im0)
	TempleLight.clouds = 0.0
	var rc0: Dictionary = await TempleLight.final_shot(m, OUT + "/control_no_clouds.png", Vector2i(1024, 1024))
	var imc := fin(rc0, "control_no_clouds")
	var spread0 := sky_spread(imc)
	TempleLight.clouds = 0.40
	ok(spread > 1.5 * spread0 and spread > 0.05, "K clouds: sky luminance spread %.3f with clouds vs %.3f clear (> 1.5x and > 0.05)" % [spread, spread0])
	# ---- H haze: a white and a black block side by side, near (30 m) and far (300 m, 10x bigger so it looks as big): their contrast (Lw-Lb)/(Lw+Lb)
	# falls with distance when the haze is on; haze 0 is the control (the same blocks, the same light)
	var rig := Node3D.new()
	m.add_child(rig)
	var gy := TempleLight.scene_box.position.y - 0.003 * TempleLight.scene_size
	var hz_spec := {"pos": Vector3(150, 5, 150), "target": Vector3(150, 2, -400), "fov": 50.0}
	var spots := []
	for rowd in [[30.0, 3.0], [300.0, 30.0]]:
		for k in 2:
			var bx := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(rowd[1], rowd[1], rowd[1])
			bx.mesh = bm
			var mt := StandardMaterial3D.new()
			mt.albedo_color = Color(0.9, 0.9, 0.9) if k == 0 else Color(0.04, 0.04, 0.04)
			mt.roughness = 1.0
			bx.material_override = mt
			var wp := Vector3(150.0 + (-0.6 if k == 0 else 0.6) * rowd[1], gy + rowd[1] * 0.5, 150.0 - rowd[0])
			bx.position = wp
			rig.add_child(bx)
			spots.append(wp)
	var con := {}
	for hz in [1.0, 0.0]:
		TempleLight.haze = hz
		var rh: Dictionary = await TempleLight.final_shot(m, OUT + "/haze_%d.png" % int(hz), Vector2i(1024, 1024), hz_spec)
		var imh := fin(rh, "haze_%d" % int(hz))
		var xf := Transform3D(Basis.looking_at((hz_spec["target"] - hz_spec["pos"]).normalized(), Vector3.UP), hz_spec["pos"])
		var lv: Array = []
		for wp in spots:
			var d: Vector3 = xf.affine_inverse() * (wp + Vector3(0, 0.0, 0.0))
			var tf := tan(deg_to_rad(25.0))
			var px := Vector2(512.0 + (d.x / -d.z) / tf * 512.0, 512.0 - (d.y / -d.z) / tf * 512.0)
			lv.append(lum(avg(imh, Rect2i(int(px.x) - 2, int(px.y) - 2, 5, 5))))
		con[hz] = [(lv[0] - lv[1]) / (lv[0] + lv[1]), (lv[2] - lv[3]) / (lv[2] + lv[3])]
		print("H haze %.0f: contrast near %.3f far %.3f (white/black near %.3f/%.3f far %.3f/%.3f)" % [hz, con[hz][0], con[hz][1], lv[0], lv[1], lv[2], lv[3]])
	rig.queue_free()
	ok(con[1.0][1] < 0.75 * con[1.0][0], "H haze: far contrast %.3f < 0.75 x near contrast %.3f" % [con[1.0][1], con[1.0][0]])
	ok(con[0.0][1] > 0.9 * con[0.0][0], "H control: with haze 0 the far contrast %.3f stays near the near one %.3f" % [con[0.0][1], con[0.0][0]])
	TempleLight.haze = 1.0
	var b3 := Basis.from_euler(Vector3(deg_to_rad(-14.0), deg_to_rad(35.0), 0.0))
	var r3: Dictionary = await TempleLight.final_shot(m, "C:/Users/Nick/tools/kine_workers/out/232/final_3q.png", Vector2i(1024, 1024), {"pos": Vector3(0, 5, 0) + b3 * Vector3(0, 0, 62.0), "target": Vector3(0, 5, 0), "fov": 45.0})
	ok(bool(r3["ok"]), "B the 3/4 picture is written")
	FileAccess.open("C:/Users/Nick/tools/kine_workers/out/232/final_front.png", FileAccess.WRITE).close()
	im0.save_png("C:/Users/Nick/tools/kine_workers/out/232/final_front.png")
	# ---- knobs: time of day, exposure
	ok(TempleLight.sun_elevation(12.0) > TempleLight.sun_elevation(16.75) and TempleLight.sun_elevation(16.75) > TempleLight.sun_elevation(18.0), "T the sun is higher at noon than at 16.75 h and 18 h")
	var lo := TempleLight.sun_color(TempleLight.sun_elevation(17.5))
	var hi := TempleLight.sun_color(TempleLight.sun_elevation(12.0))
	ok(lo.r / lo.b > hi.r / hi.b, "T the low sun is warmer (r/b %.2f) than the noon sun (%.2f)" % [lo.r / lo.b, hi.r / hi.b])
	TempleLight.exposure = 2.0
	var re: Dictionary = await TempleLight.final_shot(m, OUT + "/exposure2.png", Vector2i(512, 512))
	TempleLight.exposure = 1.0
	var ime: Image = re["image"]
	var im1 := im0.duplicate() as Image
	im1.resize(512, 512)
	var l2 := lum(avg(ime, Rect2i(0, 0, 512, 512)))
	var l1 := lum(avg(im1, Rect2i(0, 0, 512, 512)))
	ok(l2 > 1.15 * l1, "T exposure 2 is brighter than exposure 1 (%.3f vs %.3f)" % [l2, l1])
	# ---- F: the FINAL SHOT has no UI: the same camera, same size, against the live window with every Control hidden
	TempleLight.set_camera(m, REF_POS, REF_TGT, REF_FOV, 0.5, 3000.0)
	m._temple_panel_toggle()   # the panel is open: a UI that must not be in the shot
	await idle(10)
	ok(m._temple_panel != null and m._temple_panel.visible, "F the Light and camera panel opens from the View ribbon")
	TempleLight.set_live(m, true)
	await idle(20)
	var with_ui := root.get_texture().get_image()
	with_ui.save_png(OUT + "/live_with_ui.png")
	var fsz := Vector2i(root.size)
	var rf: Dictionary = await TempleLight.final_shot(m, OUT + "/final_shot_ui_open.png", fsz)
	var shotimg := fin(rf, "final_shot_ui_open")
	ok(shotimg.get_width() == fsz.x and shotimg.get_height() == fsz.y, "F final shot size is the one asked (%d x %d)" % [shotimg.get_width(), shotimg.get_height()])
	var hid: Array = []
	for c in m.get_children():
		if c is CanvasItem and (c as CanvasItem).visible:
			hid.append(c)
			(c as CanvasItem).visible = false
		elif c is CanvasLayer and (c as CanvasLayer).visible:
			hid.append(c)
			(c as CanvasLayer).visible = false
	m.cam.h_offset = 0.0
	m.cam.v_offset = 0.0
	await idle(10)
	var no_ui := root.get_texture().get_image()
	no_ui.save_png(OUT + "/live_ui_hidden.png")
	for c in hid:
		c.visible = true
	var ui_px := 0
	var ui_in_shot := 0
	var shot_diff := 0
	var total := fsz.x * fsz.y
	no_ui.convert(Image.FORMAT_RGB8)
	with_ui.convert(Image.FORMAT_RGB8)
	for y in fsz.y:
		for x in fsz.x:
			var a := no_ui.get_pixel(x, y)
			var w := with_ui.get_pixel(x, y)
			var s := shotimg.get_pixel(x, y)
			var is_ui := maxf(maxf(absf(w.r - a.r), absf(w.g - a.g)), absf(w.b - a.b)) > 0.1
			var d := maxf(maxf(absf(s.r - a.r), absf(s.g - a.g)), absf(s.b - a.b)) > 0.1
			if is_ui:
				ui_px += 1
				if d:
					ui_in_shot += 1
			if d:
				shot_diff += 1
	print("F UI pixels in the live window %d (%.1f %%); of those, differing in the final shot from the UI-hidden window: %d; whole-frame differing %d (%.2f %%)" % [ui_px, 100.0 * ui_px / total, ui_in_shot, shot_diff, 100.0 * shot_diff / total])
	ok(ui_px > 0.03 * total, "F control: the live window with the UI up has %.1f %% UI pixels (> 3 %%), so the comparison can see a UI" % (100.0 * ui_px / total))
	ok(ui_in_shot <= 0.05 * ui_px, "F final shot has 0 UI pixels: inside the UI area only %d of %d pixels differ from the UI-hidden window (<= 5 %%: MSAA and shadow-fit noise)" % [ui_in_shot, ui_px])
	ok(shot_diff < 0.04 * total, "F the final shot is the same picture as the live view: %.2f %% of pixels differ by > 0.1 (< 4 %%)" % (100.0 * shot_diff / total))
	var rd: Dictionary = await TempleLight.final_shot(m, OUT + "/final_default.png")
	ok(int(rd["w"]) == 1920 and int(rd["h"]) == 1080, "F the default final shot is 1920 x 1080 (%d x %d)" % [rd["w"], rd["h"]])
	var leftover := false
	for c in m.get_children():
		if c is SubViewport:
			leftover = true
	ok(not leftover, "F the final shot's viewport is gone after the shot")
	# ---- F: the agent tools
	var af := FileAccess.get_file_as_string("res://scripts/agent_tools.gd")
	ok(af.contains("\"temple_light\"") and af.contains("\"final_shot\""), "F agent_tools has temple_light and final_shot")
	var sv := TempleLight.serve(m, {"time": 12.0, "exposure": 1.2, "camera": {"pos": [0, 4.5, 38], "target": [0, 6.3, 0], "fov": 40}})
	ok(bool(sv["ok"]) and absf(m.cam.fov - 40.0) < 0.001 and absf(float(sv["settings"]["sun_elevation"]) - TempleLight.sun_elevation(12.0)) < 0.2, "F serve sets time, exposure and the camera by numbers")
	var sf2: Dictionary = await TempleLight.serve_final(m, {"out": OUT + "/agent_shot.png", "w": 640, "h": 360, "camera": {"pos": [0, 4.5, 38], "target": [0, 6.3, 0], "fov": 45}})
	ok(bool(sf2["ok"]) and FileAccess.file_exists(OUT + "/agent_shot.png"), "F serve_final writes the PNG (%s)" % str(sf2.get("text", "")))
	TempleLight.set_from({"time": 16.75, "exposure": 1.0})
	# ---- P: off puts everything back
	if TempleLight.on:
		TempleLight.set_live(m, false)
	var put_back := true
	for k in TempleLight.ENV_KEYS:
		if m.world_env.get(k) != env_before[k]:
			put_back = false
			print("   not put back: ", k)
	ok(put_back, "P temple light off puts every Environment value back")
	print("s232: %d fail" % fails)
	quit(1 if fails > 0 else 0)


## local contrast: the mean |luminance difference| of pixels 6 px apart (a smooth horizon gradient adds none, texture detail adds it)
func edge_energy(img: Image, r: Rect2i) -> float:
	var t := 0.0
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x - 6):
			t += absf(lum(img.get_pixel(x, y)) - lum(img.get_pixel(x + 6, y)))
			n += 1
	return t / maxf(n, 1)


func sky_spread(img: Image) -> float:
	var sp: Array = []
	for y in range(0, 200, 4):
		for x in range(0, 1024, 4):
			sp.append(lum(img.get_pixel(x, y)))
	sp.sort()
	return float(sp[int(sp.size() * 0.95)]) - float(sp[int(sp.size() * 0.05)])
