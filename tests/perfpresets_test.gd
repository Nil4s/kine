extends SceneTree
## godot --path . --position 4000,4000 -s tests/perfpresets_test.gd     (GRAPHICS QUALITY: Auto / Low / Medium / High, scripts/quality.gd; needs a window)
## BARS (stated before measuring):
##  1 EACH PRESET APPLIES ITS VALUES: Low / Medium / High set the root viewport's 3D scale, MSAA and positional shadow atlas, and the sun's shadow
##    distance exactly as the table says (Low 0.67 / off / 1024 / 20 m, Medium 0.85 / 2x / 2048 / 40 m, High 1.0 / 4x / 4096 / 100 m); Quality.applied
##    names the tier; the thumbnail MSAA follows the tier (Low none). (The directional atlas size has no getter in Godot: only the call is checked.)
##  2 AUTO ON A WEAK MACHINE: a fake "Intel(R) UHD Graphics 620" with 1 GB of VRAM picks Low, a benchmark of 5 ms does not lift it (an iGPU stays
##    Low); a fake "GeForce GTX 1050" picks Low; an unknown 4-core 8 GB machine picks Medium; an "RTX 3070", 20 cores, 32 GB picks High; a slow
##    benchmark (30 ms) drops a tier, a fast one (5 ms) lifts a Medium one; a 2-core machine is Low.
##  3 AUTO'S SAVED PICK: tier_for(auto) returns the pick saved for THIS adapter, and recomputes when the adapter changed.
##  4 THE RENDERER NEEDS A RESTART ONLY WHEN IT DIFFERS: Low on forward_plus asks, Medium on mobile does not, High on forward_plus does not, any tier with
##    --rendering-method on the command line does not.
##  5 override.cfg: write_override for mobile reads back "mobile" under [rendering]; for the default renderer the file is removed.
##  6 THE APP: the View menu has Graphics quality with Auto, Low, Medium, High (the picked mode checked); _set_gfx("low") applies Low and, when
##    the renderer differs, shows the restart question and writes the test's own override.cfg (never the project's); _set_gfx("high") on forward_plus
##    asks nothing.
##  7 SURVIVES A RESTART: a mode chosen in one app instance is read from the settings file by a NEW instance, which applies it at start; the file
##    holds it; a test's first start with nothing saved is High (the picture the older tests measure).
##  8 THE BENCHMARK: Quality.benchmark returns a plausible median (0 < ms < 1000), and the vsync mode is put back.
var fails := 0
var m: Node


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func idle(n := 3) -> void:
	for i in n:
		await process_frame


func boot() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await idle(6)
	m.tour_step = -1
	if m.ui_tour != null:
		m.ui_tour.visible = false


func _init() -> void:
	await boot()
	# 1 each preset applies its values
	var want := {"low": [0.67, 0, 1024, 20.0], "medium": [0.85, 1, 2048, 40.0], "high": [1.0, 2, 4096, 100.0]}
	for t in ["low", "medium", "high"]:
		Quality.apply(root, t, m.light_key)
		var w: Array = want[t]
		ok(absf(root.scaling_3d_scale - float(w[0])) < 1e-4 and int(root.msaa_3d) == int(w[1]) and root.positional_shadow_atlas_size == int(w[2])
			and absf(m.light_key.directional_shadow_max_distance - float(w[3])) < 1e-4 and Quality.applied["tier"] == t and Quality.thumb_msaa() == int(w[1]),
			"1 %s: scale %.2f, MSAA %d, positional atlas %d, sun shadow %.0f m, thumbs MSAA %d" % [t, root.scaling_3d_scale, int(root.msaa_3d), root.positional_shadow_atlas_size, m.light_key.directional_shadow_max_distance, Quality.thumb_msaa()])
	# 2 auto on fake machines
	var d1 := Quality.detect("Intel(R) UHD Graphics 620", 1024, 4, 8192)
	var d1b := Quality.detect("Intel(R) UHD Graphics 620", 1024, 8, 16384, 5.0)
	var d2 := Quality.detect("NVIDIA GeForce GTX 1050", 2048, 4, 8192)
	var d3 := Quality.detect("Mystery GPU 9000", -1, 4, 8192)
	var d4 := Quality.detect("NVIDIA GeForce RTX 3070", 8192, 20, 32768)
	var d5 := Quality.detect("Mystery GPU 9000", -1, 4, 8192, 30.0)
	var d6 := Quality.detect("Mystery GPU 9000", -1, 4, 8192, 5.0)
	var d7 := Quality.detect("NVIDIA GeForce RTX 3070", 8192, 2, 32768)
	ok(d1 == "low" and d1b == "low" and d2 == "low" and d3 == "medium" and d4 == "high" and d5 == "low" and d6 == "high" and d7 == "low",
		"2 auto: Intel UHD 1 GB -> %s (benchmark 5 ms: %s), GTX 1050 -> %s, unknown 4-core 8 GB -> %s, RTX 3070 20 cores -> %s, slow bench -> %s, fast bench -> %s, 2 cores -> %s" % [d1, d1b, d2, d3, d4, d5, d6, d7])
	# 3 the saved pick
	var cfg := "user://zz_perfpresets_%d.cfg" % OS.get_process_id()
	var mach := {"adapter": "Fake GPU A", "vram_mb": -1, "cores": 4, "ram_mb": 8192}
	var before := Quality.tier_for("auto", cfg, mach)
	Quality.pick_save(cfg, mach, "low", 31.0)
	var after := Quality.tier_for("auto", cfg, mach)
	var other := Quality.tier_for("auto", cfg, {"adapter": "Fake GPU B", "vram_mb": -1, "cores": 4, "ram_mb": 8192})
	ok(before == "medium" and after == "low" and other == "medium" and Quality.benched(cfg, mach) and not Quality.benched(cfg, {"adapter": "Fake GPU B"}),
		"3 saved pick: %s -> %s for the same adapter, %s for another adapter; benched %s" % [before, after, other, Quality.benched(cfg, mach)])
	# 4 the restart only when the renderer differs
	var a0 := PackedStringArray()
	var a1 := PackedStringArray(["--rendering-method", "mobile"])
	var a2 := PackedStringArray(["--rendering-method=gl_compatibility"])
	ok(Quality.needs_relaunch("low", "forward_plus", a0) and not Quality.needs_relaunch("medium", "mobile", a0) and not Quality.needs_relaunch("high", "forward_plus", a0)
		and Quality.needs_relaunch("high", "gl_compatibility", a0) and not Quality.needs_relaunch("low", "forward_plus", a1) and not Quality.needs_relaunch("low", "forward_plus", a2),
		"4 restart only when the renderer differs (and never over a --rendering-method flag)")
	# 5 override.cfg
	var ov := "user://zz_override_unit_%d.cfg" % OS.get_process_id()
	var wrote := Quality.write_override(ov, "mobile")
	var cf := ConfigFile.new()
	cf.load(ov)
	var read := String(cf.get_value("rendering", "renderer/rendering_method", ""))
	var removed := Quality.write_override(ov, "forward_plus")
	ok(wrote and read == "mobile" and removed and not FileAccess.file_exists(ov), "5 override.cfg: wrote mobile (read back \"%s\"); the default renderer removes it" % read)
	# 6 the app: menu and restart question
	var gq: MenuButton = m.find_child("gfx_quality", true, false)
	var items := []
	if gq != null:
		gq.about_to_popup.emit()
		for k in gq.get_popup().item_count:
			items.append(gq.get_popup().get_item_text(k) + ("*" if gq.get_popup().is_item_checked(k) else ""))
	ok(gq != null and items.size() == 4 and items[0].begins_with("Auto") and items[1].begins_with("Low") and items[2].begins_with("Medium") and items[3].begins_with("High*"),
		"6 menu: %s (a test starts on High)" % str(items))
	var run := Quality.current_renderer()
	var ovp: String = m.gfx_override
	var asks_low := Quality.needs_relaunch("low", run, OS.get_cmdline_args())
	m._set_gfx("low")
	await idle(2)
	var dlg_low: bool = m.ui_gfx_dlg != null and m.ui_gfx_dlg.visible
	var ov_low := ""
	if FileAccess.file_exists(ovp):
		var c2 := ConfigFile.new()
		c2.load(ovp)
		ov_low = String(c2.get_value("rendering", "renderer/rendering_method", ""))
	ok(m.gfx_mode == "low" and m.gfx_tier == "low" and absf(root.scaling_3d_scale - 0.67) < 1e-4 and dlg_low == asks_low
		and (ov_low == "gl_compatibility") == asks_low and ovp.begins_with("user://"),
		"6 Low in the app (running %s): applied, restart question %s (needed %s), test's override.cfg \"%s\"" % [run, dlg_low, asks_low, ov_low])
	if m.ui_gfx_dlg != null:
		m.ui_gfx_dlg.hide()
	if FileAccess.file_exists(ovp):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ovp))
	m._set_gfx("high")
	await idle(2)
	var asks_high := Quality.needs_relaunch("high", run, OS.get_cmdline_args())
	var dlg_high: bool = m.ui_gfx_dlg != null and m.ui_gfx_dlg.visible
	ok(m.gfx_mode == "high" and dlg_high == asks_high and (run != "forward_plus" or not dlg_high), "6 High in the app: restart question %s (needed %s)" % [dlg_high, asks_high])
	if m.ui_gfx_dlg != null:
		m.ui_gfx_dlg.hide()
	if FileAccess.file_exists(ovp):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ovp))
	# 7 survives a restart: choose Medium here, a new instance reads it
	var settings_path: String = m.settings
	m._set_gfx("medium")
	if m.ui_gfx_dlg != null:
		m.ui_gfx_dlg.hide()
	var file_mode := Quality.mode_load(settings_path)
	var kept := FileAccess.get_file_as_string(settings_path)   # a test instance deletes its settings file on exit; a real app leaves it: put it back
	m.queue_free()
	await idle(4)
	var fw := FileAccess.open(settings_path, FileAccess.WRITE)
	fw.store_string(kept)
	fw.close()
	await boot()
	var same_file: bool = m.settings == settings_path
	ok(file_mode == "medium" and same_file and m.gfx_mode == "medium" and m.gfx_tier == "medium" and absf(root.scaling_3d_scale - 0.85) < 1e-4
		and int(root.msaa_3d) == 1 and absf(m.light_key.directional_shadow_max_distance - 40.0) < 1e-4,
		"7 restart: the file holds \"%s\"; the new instance (same settings file %s) starts on %s, scale %.2f, MSAA %d, sun %.0f m" % [file_mode, same_file, m.gfx_mode, root.scaling_3d_scale, int(root.msaa_3d), m.light_key.directional_shadow_max_distance])
	# 8 the benchmark
	var vs := DisplayServer.window_get_vsync_mode()
	var ms: float = await Quality.benchmark(self)
	ok(ms > 0.0 and ms < 1000.0 and DisplayServer.window_get_vsync_mode() == vs, "8 benchmark: median %.2f ms a frame, vsync mode put back" % ms)
	# leave the app as it started
	Quality.apply(root, "high", m.light_key)
	for p in [cfg, ovp, settings_path]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("perfpresets: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)
