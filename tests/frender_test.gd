## godot --path . -s tests/frender_test.gd     (GAP_AUDIT_1106 top-10 #3: "Final render", client-ready output from the shot camera; needs a window)
## BARS (stated before the first implementation run):
##   1 PRESET: FinalRender.apply("final") changes the Environment and the Viewport and the lights, read back with FinalRender.read:
##     SSAO on, SSR on, glow off, SDFGI on, MSAA >= 4x, key light shadows on, soft-shadow filter above the draft's. CONTROL: "draft"
##     differs from "final" in every one of those fields; restore() puts the original back exactly. IN THE APP: while the
##     real _render_shots runs with preset final, world_env really has SSR and SSAO on; afterwards it is as before.
##   2 MEASURABLE: a fixed scene (a mannequin on a floor, one key light), draft vs final at 640x360: the mean luminance of a 20 px band
##     under the feet is >= 8% lower in final. CONTROL: the same two renders of the scene WITH NO FLOOR: the band must NOT change by 8%
##     (the darkening comes from the floor contact, not from the preset dimming everything).
##   3 SEQUENCE: an N-frame range gives N PNGs named 0000..N-1, all at the requested size, and an mp4 whose ffprobe frame count = N and
##     size = WxH. Run at 640x360 (12 frames across the shot cut) and 1920x1080 (3 frames). CONTROL: the same checker, given a folder
##     with one frame deleted / one frame at the wrong size, must report the mismatch.
##   4 NO DATA TOUCHED: output goes under the path given (a temp folder); no png/mp4 appear in the user data dir (a fresh APPDATA
##     under wtest), and none in res://exports. CONTROL: the scan must see a png planted in user://.
##   7 GRAIN (L15, from #228 LOOK: fine SSAO hatch on shaded surfaces): on the test scene's 1080p final frame, high-frequency noise in a torso-shadow
##     patch (std of luminance minus its 5x5 box blur) falls by >= 40% against the previous final preset (SSAO half-size, 2 blur passes) measured on
##     the same frame/patch. CONTROL: the new frame with 2% noise planted in the patch must fail that 40% bar.
##   5 TIME (report only): seconds per frame, draft and final, at 1080p.
extends SceneTree

var fails := 0
var m: Node
var look_dir := ""
var _last_band := Rect2i()
var _last_cam: Camera3D = null


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func pose(thigh: float, arm: float) -> Dictionary:
	var R := Body.new()
	R.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	R.set_ang("thigh_l", Vector3(thigh, 0, 0))
	R.set_ang("upperarm_r", Vector3(0, 0, arm))
	R.fk()
	return R.to_dict()


func key(t: float, p: Vector3, a: Vector3, f: float) -> Dictionary:
	return {"t": t, "pos": p, "aim": a, "f": f}


func lum(img: Image, r: Rect2i) -> float:
	var tot := 0.0
	var n := 0
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			var c := img.get_pixel(clampi(x, 0, img.get_width() - 1), clampi(y, 0, img.get_height() - 1))
			tot += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			n += 1
	return tot / float(maxi(n, 1))


## the fixed scene: a mannequin (capsule legs, box feet, torso, head) standing on a floor, one key light. Returns the nodes
func build_scene(svp: SubViewport, with_floor: bool) -> Dictionary:
	svp.own_world_3d = true
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.47, 0.5)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	svp.add_child(we)
	var key_l := DirectionalLight3D.new()
	key_l.rotation_degrees = Vector3(-55, 160, 0)
	key_l.light_energy = 1.2
	svp.add_child(key_l)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.78, 0.74)
	if with_floor:
		var fl := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(12, 0.1, 12)
		fl.mesh = pm
		fl.position = Vector3(0, -0.05, 0)
		fl.material_override = mat
		svp.add_child(fl)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.55, 0.6, 0.7)
	for sx in [-0.12, 0.12]:
		var leg := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.07
		cm.height = 0.95
		leg.mesh = cm
		leg.position = Vector3(sx, 0.5, 0)
		leg.material_override = bm
		svp.add_child(leg)
		var foot := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(0.12, 0.06, 0.28)
		foot.mesh = fm
		foot.position = Vector3(sx, 0.03, 0.06)
		foot.material_override = bm
		svp.add_child(foot)
	var torso := MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 0.17
	tm.height = 0.7
	torso.mesh = tm
	torso.position = Vector3(0, 1.2, 0)
	torso.material_override = bm
	svp.add_child(torso)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.11
	hm.height = 0.22
	head.mesh = hm
	head.position = Vector3(0, 1.72, 0)
	head.material_override = bm
	svp.add_child(head)
	var cam := Camera3D.new()
	svp.add_child(cam)
	cam.look_at_from_position(Vector3(0.6, 1.1, 2.6), Vector3(0, 0.35, 0.05))
	cam.fov = 40.0
	cam.current = true
	return {"env": env, "key": key_l, "cam": cam}


func render_scene(with_floor: bool, preset: String, w: int, h: int, tag: String, post := Callable()) -> Image:
	var svp := SubViewport.new()
	svp.size = Vector2i(w, h)
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(svp)
	var sc := build_scene(svp, with_floor)
	var saved := FinalRender.apply(preset, sc["env"], svp, [sc["key"]])
	if post.is_valid():
		post.call(sc["env"])
	await idle(8)
	var img: Image = await FinalRender.grab(self, svp)
	_last_cam = sc["cam"]
	if look_dir != "":
		img.save_png("%s/look_%s_%s.png" % [look_dir, preset, tag])
	# the band: 20 px under the lowest foot point, as the camera sees it
	var cam: Camera3D = sc["cam"]
	var p := cam.unproject_position(Vector3(0, 0.0, 0.06))
	_last_band = Rect2i(int(p.x) - 60, int(p.y) + 1, 120, 20)
	FinalRender.restore(saved, sc["env"], svp, [sc["key"]])
	svp.queue_free()
	await idle(2)
	return img


## the sequence checker: returns "" when dir holds exactly n frames 0000..n-1 of w x h, else the first problem
func check_seq(dir: String, n: int, w: int, h: int) -> String:
	var l := Array(DirAccess.get_files_at(dir)).filter(func(f): return String(f).ends_with(".png"))
	l.sort()
	if l.size() != n:
		return "%d PNGs, want %d" % [l.size(), n]
	for i in n:
		if l[i] != "frame_%04d.png" % i:
			return "file %d is %s" % [i, l[i]]
		var img := Image.load_from_file(dir + "/" + l[i])
		if img == null or img.get_width() != w or img.get_height() != h:
			return "frame %d is %s, want %dx%d" % [i, "unreadable" if img == null else "%dx%d" % [img.get_width(), img.get_height()], w, h]
	return ""


## the fraction of pixels within tol (every channel) of any of the colours
func near_frac(img: Image, cols: Array, tol: float) -> float:
	var n := 0
	var w := img.get_width()
	var h := img.get_height()
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			for k in cols:
				if absf(c.r - k.r) <= tol and absf(c.g - k.g) <= tol and absf(c.b - k.b) <= tol:
					n += 1
					break
	return float(n) / float(maxi(w * h, 1))


## the fraction of pixels where any channel differs by more than tol
func diff_frac(a: Image, b: Image, tol: float) -> float:
	if a.get_size() != b.get_size():
		return 1.0
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			var c := a.get_pixel(x, y)
			var d := b.get_pixel(x, y)
			if absf(c.r - d.r) > tol or absf(c.g - d.g) > tol or absf(c.b - d.b) > tol:
				n += 1
	return float(n) / float(maxi(a.get_width() * a.get_height(), 1))


func probe(fp: String, mp4: String) -> Dictionary:
	var out := []
	OS.execute(fp, ["-v", "error", "-count_frames", "-select_streams", "v:0", "-show_entries", "stream=nb_read_frames,width,height", "-of", "csv=p=0", mp4], out, true)
	var parts: PackedStringArray = String(out[0]).strip_edges().split(",") if not out.is_empty() else PackedStringArray()
	if parts.size() < 3:
		return {"w": -1, "h": -1, "n": -1}
	return {"w": int(parts[0]), "h": int(parts[1]), "n": int(parts[2])}


func scan_media(path: String) -> Array:
	var found := []
	if not DirAccess.dir_exists_absolute(path):
		return found
	for f in DirAccess.get_files_at(path):
		if String(f).ends_with(".png") or String(f).ends_with(".mp4"):
			found.append(path + "/" + f)
	for d in DirAccess.get_directories_at(path):
		if d in ["shader_cache", "logs"]:
			continue
		found.append_array(scan_media(path + "/" + d))
	return found


func _init() -> void:
	look_dir = OS.get_environment("ZZ_FR_LOOK")
	if look_dir != "":
		DirAccess.make_dir_recursive_absolute(look_dir)

	# ---------------------------------------------------------------- bar 1: the preset, read back
	var svp0 := SubViewport.new()
	svp0.size = Vector2i(64, 64)
	root.add_child(svp0)
	var sc0 := build_scene(svp0, true)
	var env0: Environment = sc0["env"]
	var lights0 := [sc0["key"]]
	var r_orig := FinalRender.read(env0, svp0, lights0)
	var saved := FinalRender.apply("final", env0, svp0, lights0)
	var r_fin := FinalRender.read(env0, svp0, lights0)
	FinalRender.restore(saved, env0, svp0, lights0)
	var r_back := FinalRender.read(env0, svp0, lights0)
	var saved_d := FinalRender.apply("draft", env0, svp0, lights0)
	var r_dr := FinalRender.read(env0, svp0, lights0)
	FinalRender.restore(saved_d, env0, svp0, lights0)
	print("     final: %s" % [r_fin])
	print("     draft: %s" % [r_dr])
	ok(bool(r_fin["ssao"]) and bool(r_fin["ssr"]) and not bool(r_fin["glow"]) and bool(r_fin["sdfgi"]) and int(r_fin["msaa"]) >= Viewport.MSAA_4X and bool(r_fin["shadows"]) and int(r_fin["soft_q"]) > int(r_dr["soft_q"]),
		"1 the final preset reads back: SSAO, SSR, SDFGI on, glow off, MSAA >= 4x, key shadows on, soft-shadow filter %d (draft %d)" % [r_fin["soft_q"], r_dr["soft_q"]])
	var differs := true
	var which := []
	for k in ["ssao", "ssr", "sdfgi", "msaa", "shadows", "soft_q"]:
		if r_fin[k] == r_dr[k]:
			differs = false
			which.append(k)
	ok(differs and not bool(r_dr["glow"]), "  CONTROL: draft differs from final in every field (same: %s)" % [which])
	ok(r_back == r_orig, "  restore() puts the original back exactly")
	svp0.queue_free()

	# ---------------------------------------------------------------- bar 2: measurable quality
	var fl_d: Image = await render_scene(true, "draft", 640, 360, "640")
	var band: Rect2i = _last_band
	var fl_f: Image = await render_scene(true, "final", 640, 360, "640")
	var nf_d: Image = await render_scene(false, "draft", 640, 360, "640nofloor")
	var band_nf: Rect2i = _last_band
	var nf_f: Image = await render_scene(false, "final", 640, 360, "640nofloor")
	var ld := lum(fl_d, band)
	var lf := lum(fl_f, band)
	var nd := lum(nf_d, band_nf)
	var nfl := lum(nf_f, band_nf)
	var drop := 1.0 - lf / maxf(ld, 1e-6)
	var drop_nf := 1.0 - nfl / maxf(nd, 1e-6)
	print("     band %s: floor draft %.4f final %.4f (drop %.1f%%); no floor draft %.4f final %.4f (drop %.1f%%)" % [band, ld, lf, drop * 100.0, nd, nfl, drop_nf * 100.0])
	ok(ld > 0.05 and drop >= 0.08, "2 contact darkening: the 20 px band under the feet is %.1f%% darker in final (want >= 8%%)" % (drop * 100.0))
	ok(drop_nf < 0.08, "  CONTROL: with no floor the same band changes by %.1f%% (< 8%%): the preset alone does not dim it" % (drop_nf * 100.0))

	# ---------------------------------------------------------------- bar 7: grain in the final frame
	var old_ssao := func(env: Environment): RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH, true, 0.5, 2.0, 50.0, 300.0)
	var g_old: Image = await render_scene(true, "final", 1920, 1080, "grain_old", old_ssao)
	var cam7: Camera3D = _last_cam
	var g_new: Image = await render_scene(true, "final", 1920, 1080, "grain_new")
	var t0 := Time.get_ticks_msec()
	await render_scene(true, "final", 1920, 1080, "grain_time")
	print("     TIME: final 1080p test-scene frame (incl. 8 settle frames + setup) %d ms" % (Time.get_ticks_msec() - t0))
	var W := g_old.get_width()
	var H := g_old.get_height()
	var Lo := lum_img(g_old)
	var Ln := lum_img(g_new)
	# the patch: the darkest 24 px window on the torso (the shadow side), found on the OLD frame and used for both
	var tc := cam7.unproject_position(Vector3(0, 1.2, 0))
	var pxm := float(H) / (2.0 * 2.7 * tan(deg_to_rad(20.0)))
	var best := Rect2i()
	var best_l := 9.0
	for y in range(int(tc.y - 0.2 * pxm), int(tc.y + 0.2 * pxm), 6):
		for x in range(int(tc.x - 0.1 * pxm), int(tc.x + 0.1 * pxm) - 24, 6):
			var tl := 0.0
			for yy in 24:
				for xx in 24:
					tl += Lo[(y + yy) * W + x + xx]
			if tl / 576.0 < best_l:
				best_l = tl / 576.0
				best = Rect2i(x, y, 24, 24)
	var n_old := hf_noise(Lo, W, H, best)
	var n_new := hf_noise(Ln, W, H, best)
	var red := 1.0 - n_new / maxf(n_old, 1e-9)
	var Lp := Ln.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in range(best.position.y, best.position.y + best.size.y):
		for x in range(best.position.x, best.position.x + best.size.x):
			Lp[y * W + x] += rng.randf_range(-0.02, 0.02)
	var n_pl := hf_noise(Lp, W, H, best)
	var red_pl := 1.0 - n_pl / maxf(n_old, 1e-9)
	print("     grain patch %s (mean lum %.3f): noise old %.5f, new %.5f (reduction %.1f%%); planted 2%% on new %.5f (reduction %.1f%%)" % [best, best_l, n_old, n_new, red * 100.0, n_pl, red_pl * 100.0])
	if look_dir != "":
		var z := Rect2i(best.position.x - 60, best.position.y - 60, 144, 144)
		for pair in [["old", g_old], ["new", g_new]]:
			var cr: Image = (pair[1] as Image).get_region(z)
			cr.resize(576, 576, Image.INTERPOLATE_NEAREST)
			cr.save_png("%s/look_grain_%s_zoom.png" % [look_dir, pair[0]])
	ok(n_old > 0.0 and red >= 0.40, "7 grain: torso-shadow high-frequency noise %.5f -> %.5f, down %.1f%% (want >= 40%%)" % [n_old, n_new, red * 100.0])
	ok(red_pl < 0.40, "  CONTROL: 2%% noise planted in the new frame's patch is caught (reduction %.1f%% < 40%%)" % (red_pl * 100.0))

	# ---------------------------------------------------------------- the app: a scene with two shots
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false
	var S := Scene.new()
	S.name = "zz_frender"
	S.fps = 30
	var poses := [pose(0, 0), pose(70, 80), pose(-25, -40)]
	for i in 3:
		S.add("c%d" % i, poses[i])
		S.cards[i]["move"] = 0.8
		S.cards[i]["hold"] = 0.6 if i < 2 else 0.0
	m.S = S
	m._rebuild_cards()
	m.sel_card = 0
	m.playhead = 0.5
	m._refresh()
	await idle(3)
	S.shots = [
		{"t": 0.0, "name": "Wide", "keys": [key(0.0, Vector3(2.8, 1.3, -1.2), Vector3(0, 1.0, 0), 50.0)]},
		{"t": 1.2, "name": "Close", "keys": [key(1.2, Vector3(-2.0, 1.5, 1.8), Vector3(0.4, 1.1, 0.1), 35.0)]},
	]
	var tmp := OS.get_environment("TEMP").replace("\\", "/")
	if tmp == "":
		tmp = "/tmp"
	var out_root := "%s/frender_%d" % [tmp, OS.get_process_id()]
	DirAccess.make_dir_recursive_absolute(out_root)
	var ff := PlayblastExport.find_ffmpeg("")
	var fp := ShotRender.ffprobe_of(ff)
	ok(ff != "" and fp != "", "  ffmpeg and ffprobe found: %s" % ff.get_file())
	var ud := OS.get_user_data_dir()
	var media_before := scan_media(ud).size()
	var exp_before := DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://exports/shots"))

	# bar 3 at 640x360: 12 frames from 30 across the cut at 36; bar 1 in the app: the env while it runs
	var env_before := FinalRender.read(m.world_env, m.get_viewport(), [m.light_key])
	var seen_ssr := false
	var got := []
	m.shots_render_done.connect(func(r): got.append(r))
	m._render_shots(out_root, "", {"preset": "final", "w": 640, "h": 360, "first": 30, "count": 12})
	var guard := 0
	await process_frame
	while m._sr_busy and guard < 6000:
		await process_frame
		guard += 1
		if m.world_env.ssr_enabled and m.world_env.ssao_enabled:
			seen_ssr = true
	await idle(2)
	var res_a: Dictionary = got[0] if not got.is_empty() else {}
	ok(seen_ssr, "1 in the app: while the final render runs, world_env has SSR and SSAO on")
	ok(FinalRender.read(m.world_env, m.get_viewport(), [m.light_key]) == env_before, "  afterwards the app's environment, viewport and key light are as before")
	var dir_a := String(res_a.get("dir", ""))
	var mp4_a := String(res_a.get("mp4", ""))
	ok(dir_a != "" and dir_a.begins_with(out_root), "4 output went under the path given: %s" % dir_a)
	var bad := check_seq(dir_a, 12, 640, 360)
	ok(bad == "" and int(res_a.get("frames", -1)) == 12, "3 sequence 640x360: 12 frames named 0000..0011, all 640x360 (%s)" % ["ok" if bad == "" else bad])
	var pa := probe(fp, mp4_a) if mp4_a != "" and FileAccess.file_exists(mp4_a) else {"w": -1, "h": -1, "n": -1}
	ok(pa["n"] == 12 and pa["w"] == 640 and pa["h"] == 360, "  the mp4 exists; ffprobe: %d frames, %dx%d" % [pa["n"], pa["w"], pa["h"]])
	# the controls: the checker must catch a missing frame and a wrong-size frame
	var cdir := out_root + "/control"
	DirAccess.make_dir_recursive_absolute(cdir)
	for i in 12:
		if i != 5:
			Image.load_from_file(dir_a + "/frame_%04d.png" % i).save_png("%s/frame_%04d.png" % [cdir, i])
	ok(check_seq(cdir, 12, 640, 360) != "", "  CONTROL: a folder with frame 0005 missing is reported: '%s'" % check_seq(cdir, 12, 640, 360))
	Image.create(320, 180, false, Image.FORMAT_RGB8).save_png(cdir + "/frame_0005.png")
	ok(check_seq(cdir, 12, 640, 360) != "", "  CONTROL: a 320x180 frame is reported: '%s'" % check_seq(cdir, 12, 640, 360))

	# bar 5 + 3 at 1080p: 3 frames, draft then final
	var secs := {}
	var res_hd := {}
	for pr in ["draft", "final"]:
		var t0 := Time.get_ticks_usec()
		got.clear()
		m._render_shots(out_root, "", {"preset": pr, "w": 1920, "h": 1080, "first": 34, "count": 3})
		await process_frame
		while m._sr_busy:
			await process_frame
		secs[pr] = float(Time.get_ticks_usec() - t0) / 1000000.0 / 3.0
		res_hd[pr] = got[0] if not got.is_empty() else {}
		await idle(2)
	for pr in ["draft", "final"]:
		var rr: Dictionary = res_hd[pr]
		var bd := check_seq(String(rr.get("dir", "")), 3, 1920, 1080)
		var pp := probe(fp, String(rr.get("mp4", ""))) if String(rr.get("mp4", "")) != "" else {"w": -1, "h": -1, "n": -1}
		ok(bd == "" and pp["n"] == 3 and pp["w"] == 1920 and pp["h"] == 1080, "3 1080p %s: 3 frames 0000..0002 at 1920x1080 (%s); mp4 %d frames %dx%d" % [pr, "ok" if bd == "" else bd, pp["n"], pp["w"], pp["h"]])
		if look_dir != "" and FileAccess.file_exists(String(rr.get("dir", "")) + "/frame_0001.png"):
			Image.load_from_file(String(rr["dir"]) + "/frame_0001.png").save_png("%s/look_app_%s_1080.png" % [look_dir, pr])
	print("     TIME at 1080p (3 frames each, whole call incl. encode): draft %.2f s/frame, final %.2f s/frame" % [secs["draft"], secs["final"]])

	# bar 4: nothing in the user data dir, nothing in res://exports
	var media_after := scan_media(ud)
	ok(media_after.size() == media_before, "4 no png/mp4 appeared in the user data dir (%d before, %d after)" % [media_before, media_after.size()])
	ok(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("res://exports/shots")) == exp_before, "  res://exports/shots was not created or touched")
	var plant := "user://zz_frender_plant.png"
	Image.create(4, 4, false, Image.FORMAT_RGB8).save_png(plant)
	var planted := scan_media(ud).size()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(plant))
	ok(planted == media_before + 1, "  CONTROL: the scan sees a png planted in user:// (%d -> %d)" % [media_before, planted])

	# ---------------------------------------------------------------- bar 6: no editor overlays in the final frame
	m.grid_node.visible = true
	var grow0: float = m._body_outline.get_shader_parameter("grow")
	var axis0: bool = m._axis_node() != null and m._axis_node().visible
	m.sel_card = 0
	m._refresh()
	await idle(2)
	got.clear()
	m._render_shots(out_root, "", {"preset": "final", "w": 1280, "h": 720, "first": 34, "count": 1})
	await process_frame
	while m._sr_busy:
		await process_frame
	await idle(2)
	var r6: Dictionary = got[0] if not got.is_empty() else {}
	var f6 := Image.load_from_file(String(r6.get("dir", "")) + "/frame_0000.png") if not r6.is_empty() else null
	# the editor's own picture of the same frame (look-through, UI hidden): the control
	var grab_editor := func() -> Image:
		m.clean = true
		m._sides_apply()
		m.ui_root.visible = false
		await process_frame
		var sb: Dictionary = m._shot_blast_begin()
		m.playhead = 34.0 / S.fps
		m._ps().apply(m.B, m.playhead)
		m._refresh()
		m._shot_blast_frame(sb)
		await process_frame
		await RenderingServer.frame_post_draw
		var im: Image = m._shot_blast_image(sb, root.get_viewport().get_texture().get_image())
		m._shot_blast_end(sb)
		m.ui_root.visible = true
		m.clean = false
		m._sides_apply()
		return im
	var ed6: Image = await grab_editor.call()
	# the grid, by difference: the same final frame rendered with the grid already off must equal the one rendered with it on
	m.grid_node.visible = false
	var ed6_nogrid: Image = await grab_editor.call()
	got.clear()
	m._render_shots(out_root, "", {"preset": "final", "w": 1280, "h": 720, "first": 34, "count": 1})
	await process_frame
	while m._sr_busy:
		await process_frame
	await idle(2)
	var r6b: Dictionary = got[0] if not got.is_empty() else {}
	var f6b := Image.load_from_file(String(r6b.get("dir", "")) + "/frame_0000.png") if not r6b.is_empty() else null
	m.grid_node.visible = true
	var oc: Color = Tok.c("body_outline")
	var fo := near_frac(f6, [oc], 0.03) if f6 != null else 1.0
	var fg := diff_frac(f6, f6b, 0.02) if f6 != null and f6b != null else 1.0
	var eo := near_frac(ed6, [oc], 0.03)
	var eg := diff_frac(ed6, ed6_nogrid, 0.02)
	print("     outline-coloured pixels: final %.4f%%, editor grab %.4f%%; pixels changed by the grid: final %.4f%%, editor grab %.4f%%" % [fo * 100.0, eo * 100.0, fg * 100.0, eg * 100.0])
	if look_dir != "" and f6 != null:
		f6.save_png(look_dir + "/look_bar6_final.png")
		ed6.save_png(look_dir + "/look_bar6_editor.png")
	ok(f6 != null and f6.get_width() == 1280 and fo < 0.0005, "6 the final frame has no outline pixels: %.4f%% (< 0.05%%)" % (fo * 100.0))
	ok(f6 != null and fg < 0.0005, "  and the grid changes %.4f%% of its pixels (< 0.05%%; the frame with the grid already off is the reference)" % (fg * 100.0))
	ok(eo >= 0.0005, "  CONTROL: the editor's own picture of the same frame is caught for the outline: %.4f%% (>= 0.05%%)" % (eo * 100.0))
	ok(eg >= 0.0005, "  CONTROL: ... and for the grid: %.4f%% (>= 0.05%%)" % (eg * 100.0))
	ok(m.grid_node.visible and m._axis_node() != null and m._axis_node().visible == axis0 and is_equal_approx(float(m._body_outline.get_shader_parameter("grow")), grow0) and grow0 > 0.0,
		"  after the render the grid, the axes and the outline are back in the editor (outline grow %.4f)" % grow0)

	_rm(out_root)
	print("frender: %d fail" % fails)
	TestFiles.cleanup()
	quit(fails)


func lum_img(img: Image) -> PackedFloat32Array:
	var w := img.get_width()
	var out := PackedFloat32Array()
	out.resize(w * img.get_height())
	for y in img.get_height():
		for x in w:
			var c := img.get_pixel(x, y)
			out[y * w + x] = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	return out


## std of (luminance - its 5x5 box blur) over rect r (the blur reads the whole image)
func hf_noise(L: PackedFloat32Array, w: int, h: int, r: Rect2i) -> float:
	var s := 0.0
	var s2 := 0.0
	var n := 0
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			var t := 0.0
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					t += L[clampi(y + dy, 0, h - 1) * w + clampi(x + dx, 0, w - 1)]
			var d := L[y * w + x] - t / 25.0
			s += d
			s2 += d * d
			n += 1
	return sqrt(maxf(s2 / n - (s / n) * (s / n), 0.0))


func _rm(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + "/" + f)
	for d in DirAccess.get_directories_at(path):
		_rm(path + "/" + d)
	DirAccess.remove_absolute(path)
