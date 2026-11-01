extends SceneTree
## godot --path . --position 4000,4000 -s tests/s230_test.gd     (Friday plan 230: GPU TIERS, scripts/gpu_tier.gd; needs a window, ffmpeg with NVENC, an NVIDIA card)
## Bars, written before the run (Kine's own paths, measured; synthetic loads are printed as "info:" only):
##  1 TIER      this PC (RTX 3070) reads as tier "rtx30" with the adapter name; fake names map to their tiers; the View > "Graphics card" menu shows them
##  2 EXPORT    the app's REAL Save video (raw frames piped to ffmpeg) and Export playblast (PNG frames, then encode) on combo3 at 60 fps, at 1920x1080,
##              and Save video at 3840x2160, each with libx264 and with h264_nvenc: every file is H.264, has the frames the export reported, has the
##              window's size, and decodes to the end. The whole-export milliseconds of each are printed (info) with the gain.
##              HEVC NVENC makes a playable hevc file; av1_nvenc is not offered on RTX 30; Auto falls back to libx264 without NVENC / ffmpeg.
##  3 FAST VIEW the engine record (219 steps, 49 bodies) open in the Part workspace, live view: fps with Fast view off and on at 1280x720 and
##              1920x1080 (info). Bars: the menu item sets FSR2 at 0.67 and back; a video save holds it off; it is OFF by default.
##  4 SETTINGS  the choice is written to the settings file and read back
## Shots: C:/Users/Nick/tools/kine_workers/out/230/menu.png, engine_off.png, engine_on.png
var fails := 0
var m: Node
const OUT := "C:/Users/Nick/tools/kine_workers/out/230"
const CLIP := "user://s230clip"
const N := 240


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT, name])


func probe(ff: String, f: String) -> Array:
	var out := []
	OS.execute(ShotRender.ffprobe_of(ff), ["-v", "error", "-count_frames", "-select_streams", "v:0", "-show_entries",
		"stream=codec_name,width,height,nb_read_frames", "-of", "csv=p=0", f], out, true)
	return String(out[0] if out.size() > 0 else "").strip_edges().split(",")


func decodes(ff: String, f: String) -> bool:
	var out := []
	return OS.execute(ff, ["-v", "error", "-i", f, "-f", "null", "-"], out, true) == 0 and String(out[0] if out.size() > 0 else "").strip_edges() == ""


func fps_now(frames := 120) -> float:
	await idle(30)
	var t0 := Time.get_ticks_usec()
	for i in frames:
		await process_frame
	return frames / ((Time.get_ticks_usec() - t0) / 1e6)


func click_ctl(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	for d in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = d
		e.position = p
		e.global_position = p
		root.push_input(e, true)
		await process_frame


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle()
	# ---- 1 tier
	var inf: Dictionary = GpuTier.info()
	var ad := RenderingServer.get_video_adapter_name()
	print("adapter: ", ad, "  vram_mb: ", inf["vram_mb"], "  tier: ", inf["tier"])
	ok(inf["tier"] == "rtx30" and String(inf["adapter"]) == ad and ad.contains("3070"), "1 this PC: \"%s\" -> tier %s" % [ad, inf["tier"]])
	var fakes := {"NVIDIA GeForce RTX 3090": "rtx30", "NVIDIA GeForce RTX 2060": "rtx30", "NVIDIA RTX A4000": "rtx30", "NVIDIA GeForce RTX 4090 Laptop GPU": "rtx40",
		"NVIDIA GeForce RTX 5080": "rtx50", "AMD Radeon RX 7800 XT": "amd", "Intel(R) Arc(TM) A770 Graphics": "intel", "Intel(R) UHD Graphics 620": "intel",
		"NVIDIA GeForce GTX 1660 Ti": "basic", "Mystery": "basic"}
	var bad := []
	for k in fakes:
		if GpuTier.tier_of(k) != fakes[k]:
			bad.append("%s -> %s" % [k, GpuTier.tier_of(k)])
	ok(bad.is_empty(), "1 fake adapter names map to their tiers (%d names)%s" % [fakes.size(), "" if bad.is_empty() else ": " + str(bad)])
	m.easy.set_on(false)
	await idle(3)
	var gp: MenuButton = m.find_child("gpu_tier", true, false)
	var pm: PopupMenu = gp.get_popup() if gp != null else null
	if gp != null:
		gp.about_to_popup.emit()
	var txt := []
	if pm != null:
		for k in pm.item_count:
			txt.append(pm.get_item_text(k))
	ok(pm != null and str(txt).contains("3070") and str(txt).contains("RTX 20/30"), "1 menu: " + str(txt))
	if gp != null:
		gp.show_popup()
		await idle(3)
		await shot("menu")
		pm.hide()
		await idle(2)
	# ---- 2 export, the app's real paths
	var ff: String = PlayblastExport.find_ffmpeg()
	ok(ff != "", "2 ffmpeg found: " + ff)
	m._load_scene("res://scenes/combo3.json")
	await idle(3)
	m.S.fps = 60
	var runs := {}
	for sz in [Vector2i(1920, 1080), Vector2i(3840, 2160)]:
		DisplayServer.window_set_size(sz)
		root.size = sz
		await idle(6)
		for enc in ["libx264", "h264_nvenc"]:
			GpuTier.pref = enc
			GpuTier._resolved.clear()
			var paths := ["save_video"] if sz.x > 2000 else ["save_video", "export_playblast"]
			for path in paths:
				var t0 := Time.get_ticks_msec()
				var r: Dictionary
				if path == "save_video":
					r = await m._save_video_playblast("user://s230vid")
				else:
					r = await m._export_playblast("user://s230vid", "", true)
				var ms := Time.get_ticks_msec() - t0
				var mp := String(r.get("mp4", ""))
				var pr := probe(ff, mp) if mp != "" else []
				var dec := mp != "" and decodes(ff, mp)
				var key := "%s %dx%d %s" % [path, sz.x, sz.y, enc]
				runs[key] = {"ms": ms, "probe": pr, "frames": int(r.get("frames", -1)), "dec": dec}
				print("export %s: %d ms, frames %s, ffprobe %s, decodes %s" % [key, ms, r.get("frames", -1), str(pr), dec])
				if String(r.get("dir", "")) != "":
					PlayblastExport.rm_tree(String(r["dir"]))
	var bad_files := []
	for k in runs:
		var rr: Dictionary = runs[k]
		var pr3: Array = rr["probe"]
		var good: bool = pr3.size() >= 4 and pr3[0] == "h264" and pr3[3] == str(rr["frames"]) and int(rr["frames"]) >= 100 and rr["dec"] \
			and ("%sx%s" % [pr3[1], pr3[2]]) == String(k).split(" ")[1]
		if not good:
			bad_files.append("%s: %s frames %s" % [k, str(pr3), rr["frames"]])
	ok(bad_files.is_empty() and runs.size() == 6, "2 all %d real exports are H.264, window-sized, frame-exact and decode to the end%s" % [runs.size(), "" if bad_files.is_empty() else " " + str(bad_files)])
	for k in ["save_video 1920x1080", "export_playblast 1920x1080", "save_video 3840x2160"]:
		if runs.has(k + " libx264") and runs.has(k + " h264_nvenc"):
			var a: int = runs[k + " libx264"]["ms"]
			var b: int = runs[k + " h264_nvenc"]["ms"]
			print("info: whole export %s: CPU x264 %d ms, NVENC %d ms (x%.2f)" % [k, a, b, float(a) / maxf(1.0, float(b))])
	# the synthetic clip, for reference only
	var cl2 := ProjectSettings.globalize_path("user://s230clip_detail")
	DirAccess.make_dir_recursive_absolute(cl2)
	var gout := []
	OS.execute(ff, ["-y", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=1600x900:rate=30", "-frames:v", "240", "-start_number", "0", cl2 + "/frame_%04d.png"], gout, true)
	for enc in ["libx264", "h264_nvenc", "hevc_nvenc"]:
		GpuTier.pref = enc
		GpuTier._resolved.clear()
		var f2 := "%s/detail_%s.mp4" % [cl2, enc]
		var t1 := Time.get_ticks_msec()
		PlayblastExport.encode(ff, cl2, 30, f2)
		var ms2 := Time.get_ticks_msec() - t1
		var pr2 := probe(ff, f2)
		print("info: synthetic testsrc2 240 PNG frames 1600x900, %s: %d ms (%s)" % [enc, ms2, str(pr2)])
		if enc == "hevc_nvenc":
			ok(pr2.size() >= 4 and pr2[0] == "hevc" and pr2[3] == "240" and decodes(ff, f2), "2 HEVC NVENC file: %s, %s frames, decodes" % [pr2[0], pr2[3]])
	ok(not GpuTier.encoders_for("rtx30").has("av1_nvenc") and GpuTier.encoders_for("rtx40").has("av1_nvenc") and GpuTier.encoders_for("rtx50").has("av1_nvenc")
		and GpuTier.resolve("av1_nvenc", "rtx30", ff) == "libx264", "2 av1_nvenc is offered on RTX 40 and 50 only; asked for on RTX 30 it falls back")
	ok(GpuTier.resolve("auto", "rtx30", ff) == "libx264" and GpuTier.resolve("h264_nvenc", "rtx30", ff) == "h264_nvenc" and GpuTier.resolve("auto", "amd", ff) == "libx264" and GpuTier.resolve("auto", "intel", ff) == "libx264"
		and GpuTier.resolve("auto", "rtx30", "") == "libx264" and GpuTier.resolve("h264_nvenc", "basic", ff) == "libx264"
		and GpuTier.resolve("auto", "rtx30", "C:/nope/ffmpeg.exe") == "libx264", "2 Auto = libx264 (no measured gain from NVENC); NVENC chosen by hand works on RTX 30, falls back on basic / no ffmpeg / a broken ffmpeg")
	GpuTier.pref = "libx264"
	GpuTier._resolved.clear()
	ok("libx264" in PlayblastExport.args_pipe(64, 64, 30, "x.mp4") and "veryfast" in PlayblastExport.args_pipe(64, 64, 30, "x.mp4"), "2 the default pipe arguments are unchanged (libx264 veryfast)")
	# ---- 3 fast view on the real heavy part: the engine record in the Part workspace, live view
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	await idle(6)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	ok(Part.available(), "3 the CAD DLL is there")
	var pu = m.bld.part
	var ss: StartScreen = m.start_screen
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://s230_start"))
	ss.dirs_override = ["user://s230_start"]
	ss.show_screen()
	await idle(3)
	m.build_choose.auto = true
	await click_ctl(ss._cards["building"])
	if m.ui_save_ask != null and m.ui_save_ask.visible:
		m._save_ask_choose("discard")
	await idle(10)
	pu.set_on(false)
	m.S.part = {}
	await idle(2)
	await click_ctl(pu.part_btn)
	await idle(4)
	if not pu.on:
		pu.set_on(true)
		await idle(4)
	ok(pu.on, "3 the Part workspace is open")
	var ed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/s230_engine_part.json"))
	var t_b := Time.get_ticks_msec()
	var rec_e := Part.from_file(ed)
	var kept := []
	var dropped := 0
	for f in rec_e["features"]:   # a step kind with no timeline icon on this branch (a "move") would only raise icon errors: left out of the load scene
		if Icons.DRAW.has(pu._step_icon(f)):
			kept.append(f)
		else:
			dropped += 1
	rec_e["features"] = kept
	print("info: engine record: %d steps kept, %d without a timeline icon left out" % [kept.size(), dropped])
	m.S.part = rec_e
	m.bld.sync()
	await idle(10)
	print("info: engine part opened in %d ms; features %d" % [Time.get_ticks_msec() - t_b, (m.S.part["features"] as Array).size()])
	GpuTier.fast_view = false
	Quality.apply(root, m.gfx_tier, m.light_key)
	var fps := {}
	gp.about_to_popup.emit()
	for sz in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		DisplayServer.window_set_size(sz)
		root.size = sz
		await idle(10)
		for on in [false, true]:
			if on != GpuTier.fast_view:
				pm.id_pressed.emit(101)   # the menu item
				await idle(4)
			fps["%dx%d %s" % [sz.x, sz.y, on]] = await fps_now()
			if sz.x == 1280:
				await shot("engine_on" if on else "engine_off")
		var f_off: float = fps["%dx%d false" % [sz.x, sz.y]]
		var f_on: float = fps["%dx%d true" % [sz.x, sz.y]]
		print("info: engine part live view %s: Fast view off %.1f fps, on %.1f fps (x%.2f)" % [str(sz), f_off, f_on, f_on / maxf(0.01, f_off)])
	ok(root.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2 and absf(root.scaling_3d_scale - 0.67) < 1e-4 and GpuTier.fast_view and pm.is_item_checked(pm.get_item_index(101)), "3 menu item: FSR2 at 0.67, item checked")
	var hd := GpuTier.hold(root)
	var held_ok := root.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR and absf(root.scaling_3d_scale - 1.0) < 1e-4
	GpuTier.release(root, hd)
	ok(held_ok and root.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2, "3 a video save holds Fast view off (bilinear 1.0) and gives it back")
	pm.id_pressed.emit(101)
	await idle(3)
	ok(root.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR and absf(root.scaling_3d_scale - 1.0) < 1e-4 and not GpuTier.fast_view, "3 the menu item again: bilinear 1.0, Fast view off")
	var fresh := "user://zz_s230_fresh_%d.cfg" % OS.get_process_id()
	GpuTier.load_settings(fresh, false)
	ok(not GpuTier.fast_view and GpuTier.pref == "auto", "3 a fresh settings file: Fast view OFF by default, encoder Auto")
	GpuTier.pref = "libx264"
	# ---- 4 settings
	var cfgp := "user://zz_s230_%d.cfg" % OS.get_process_id()
	GpuTier.pref = "hevc_nvenc"
	GpuTier.fast_view = true
	GpuTier.save_settings(cfgp)
	GpuTier.pref = "libx264"
	GpuTier.fast_view = false
	GpuTier.load_settings(cfgp, false)
	ok(GpuTier.pref == "hevc_nvenc" and GpuTier.fast_view, "4 settings read back: %s, fast_view %s" % [GpuTier.pref, GpuTier.fast_view])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cfgp))
	GpuTier.fast_view = false
	GpuTier.pref = "libx264"
	print("s230: %d fail" % fails)
	quit()
