class_name Quality
extends RefCounted
## GRAPHICS QUALITY (potato PCs: GTX 1050 2 GB / Intel UHD, 8 GB RAM, i3): Auto / Low / Medium / High, one setting.
## A preset is a renderer plus the numbers that cost the most on a weak GPU: render scale, MSAA, shadow map size and filter.
## The renderer is fixed when the process starts, so it is the ONE value that needs a relaunch: Quality writes override.cfg
## (next to the .exe, or in the project folder when run from the editor build) and the app asks "Restart now?".
## Nothing else asks. Auto picks a tier once at start from the adapter's name and VRAM, the cores and the RAM, plus a 3 s
## first-run benchmark; it never switches the picture by itself in a session (a better pick is saved and used at the next start).
## Numbers are the research's proposal (C:/Temp/claude/research/potato/report.md) as measured by tools/perfprobe.py.

const MODES := ["auto", "low", "medium", "high"]
const TIERS := ["low", "medium", "high"]
const DEFAULT_RENDERER := "forward_plus"   # project.godot has no rendering_method: Forward+
const PRESETS := {
	"low": {"renderer": "gl_compatibility", "msaa": 0, "scale": 0.67, "dir_shadow": 1024, "dir_filter": 0, "pos_shadow": 1024,
		"pos_filter": 0, "shadow_dist": 20.0},
	"medium": {"renderer": "mobile", "msaa": 1, "scale": 0.85, "dir_shadow": 2048, "dir_filter": 1, "pos_shadow": 2048,
		"pos_filter": 1, "shadow_dist": 40.0},
	"high": {"renderer": "forward_plus", "msaa": 2, "scale": 1.0, "dir_shadow": 4096, "dir_filter": 2, "pos_shadow": 4096,
		"pos_filter": 2, "shadow_dist": 100.0},
}
## an adapter that is an integrated or old part: always Low, whatever else is measured
const WEAK_GPU := "intel|uhd|hd graphics|iris|radeon\\(tm\\) graphics|vega|\\bgt ?7\\d\\d|\\bgt ?10\\d\\d|\\bmx ?\\d{3}|gtx ?9\\d\\d|gtx ?10[345]0\\b"
const STRONG_GPU := "gtx ?10[6-8]0|gtx ?16\\d\\d|rtx|rx ?[5-7]\\d\\d\\d|arc ?a[5-7]"
const CFG := "graphics"

## what the running app applied last (the Perf HUD, the probe and the tests read it)
static var applied := {"tier": "high", "renderer": "", "scale": 1.0, "msaa": 2}


static func preset(tier: String) -> Dictionary:
	return PRESETS[tier if PRESETS.has(tier) else "high"]


## the MSAA of a thumbnail SubViewport: the preset's, so Low makes no 4x buffers for a thumbnail
static func thumb_msaa() -> int:
	return int(preset(String(applied["tier"]))["msaa"])


static func _matches(rx: String, s: String) -> bool:
	var r := RegEx.new()
	r.compile(rx)
	return r.search(s.to_lower()) != null


## the tier Auto picks. adapter: RenderingServer.get_video_adapter_name(); vram_mb: -1 when unknown; bench_ms: the first-run
## benchmark's median frame time at 1600 x 900 (-1 = not run). Pure: the tests feed it fake machines.
static func detect(adapter: String, vram_mb: int, cores: int, ram_mb: int, bench_ms := -1.0) -> String:
	var tier := 1
	var hard_low := _matches(WEAK_GPU, adapter) or (vram_mb > 0 and vram_mb < 2048)
	if hard_low:
		tier = 0
	elif cores <= 2 or (ram_mb > 0 and ram_mb < 6144):
		tier = 0
	elif cores <= 4 or (ram_mb > 0 and ram_mb < 10240):
		tier = 1
	elif _matches(STRONG_GPU, adapter) and (ram_mb <= 0 or ram_mb >= 12288) and cores >= 6:
		tier = 2
	if bench_ms > 0.0 and not hard_low:
		if bench_ms <= 8.0:
			tier += 1
		elif bench_ms >= 25.0:
			tier -= 1
	return TIERS[clampi(tier, 0, 2)]


## total VRAM in MB, or -1 when Godot cannot say (Compatibility has no RenderingDevice; no API gives it elsewhere)
static func vram_mb() -> int:
	var rd := RenderingServer.get_rendering_device()
	if rd != null and rd.has_method("get_device_total_memory"):
		return int(int(rd.call("get_device_total_memory")) / 1048576)
	return -1


static func machine() -> Dictionary:
	return {"adapter": RenderingServer.get_video_adapter_name(), "vram_mb": vram_mb(), "cores": OS.get_processor_count(),
		"ram_mb": int(int(OS.get_memory_info().get("physical", -1)) / 1048576)}


static func mode_load(cfg: String) -> String:
	var cf := ConfigFile.new()
	if cf.load(cfg) == OK:
		var m := String(cf.get_value(CFG, "mode", "auto"))
		if MODES.has(m):
			return m
	return "auto"


static func mode_save(cfg: String, mode: String) -> void:
	var cf := ConfigFile.new()
	cf.load(cfg)
	cf.set_value(CFG, "mode", mode if MODES.has(mode) else "auto")
	cf.save(cfg)


## the tier a mode means on this machine. Auto: the saved pick for this adapter, else the pick from the machine alone
static func tier_for(mode: String, cfg: String, mach: Dictionary) -> String:
	if TIERS.has(mode):
		return mode
	var cf := ConfigFile.new()
	if cf.load(cfg) == OK and String(cf.get_value(CFG, "auto_adapter", "")) == String(mach["adapter"]) and TIERS.has(String(cf.get_value(CFG, "auto_pick", ""))):
		return String(cf.get_value(CFG, "auto_pick"))
	return detect(String(mach["adapter"]), int(mach["vram_mb"]), int(mach["cores"]), int(mach["ram_mb"]))


static func pick_save(cfg: String, mach: Dictionary, tier: String, bench_ms: float) -> void:
	var cf := ConfigFile.new()
	cf.load(cfg)
	cf.set_value(CFG, "auto_pick", tier)
	cf.set_value(CFG, "auto_adapter", String(mach["adapter"]))
	cf.set_value(CFG, "bench_ms", snappedf(bench_ms, 0.01))
	cf.save(cfg)


## Auto has benchmarked this adapter already?
static func benched(cfg: String, mach: Dictionary) -> bool:
	var cf := ConfigFile.new()
	return cf.load(cfg) == OK and cf.has_section_key(CFG, "auto_pick") and String(cf.get_value(CFG, "auto_adapter", "")) == String(mach["adapter"])


## Apply a tier to the running app: render scale, MSAA, shadow sizes and filters, the sun's shadow distance. The renderer is
## NOT touched (it cannot change in a session). main may be null (a test with no app): the viewport and server parts still apply.
static func apply(vp: Viewport, tier: String, sun: DirectionalLight3D = null) -> Dictionary:
	var p := preset(tier)
	GpuTier.apply_fast(vp, float(p["scale"]))   # bilinear at the preset's scale, or FSR 2 when Fast view is on
	vp.msaa_3d = int(p["msaa"]) as Viewport.MSAA
	RenderingServer.directional_shadow_atlas_set_size(int(p["dir_shadow"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(p["dir_filter"]) as RenderingServer.ShadowQuality)
	vp.positional_shadow_atlas_size = int(p["pos_shadow"])
	RenderingServer.positional_soft_shadow_filter_set_quality(int(p["pos_filter"]) as RenderingServer.ShadowQuality)
	if sun != null and is_instance_valid(sun):
		sun.directional_shadow_max_distance = float(p["shadow_dist"])
	applied = {"tier": tier, "renderer": current_renderer(), "scale": float(p["scale"]), "msaa": int(p["msaa"])}
	return applied


static func current_renderer() -> String:
	return RenderingServer.get_current_rendering_method()


## does the renderer of this tier differ from the running one, with no --rendering-method on the command line (that wins)?
static func needs_relaunch(tier: String, running: String, args: PackedStringArray) -> bool:
	for a in args:
		if a.begins_with("--rendering-method") or a == "--rendering-driver":
			return false
	return String(preset(tier)["renderer"]) != running


static func override_path() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://override.cfg")
	return OS.get_executable_path().get_base_dir().path_join("override.cfg")


## write (or, for the project's own default, remove) override.cfg so the next start uses this tier's renderer
static func write_override(path: String, renderer: String) -> bool:
	if renderer == DEFAULT_RENDERER:
		return not FileAccess.file_exists(path) or DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK
	var cf := ConfigFile.new()
	cf.load(path)   # keep what someone else put there
	cf.set_value("rendering", "renderer/rendering_method", renderer)
	return cf.save(path) == OK


static func relaunch(tree: SceneTree) -> void:
	OS.create_process(OS.get_executable_path(), OS.get_cmdline_args())
	tree.quit()


## the first-run benchmark: the real scene for 120 frames at the window's size, vsync off, the first 30 skipped (pipelines
## compile). Returns the median frame time in ms. Takes ~3 s at 40 fps.
static func benchmark(tree: SceneTree) -> float:
	var vs := DisplayServer.window_get_vsync_mode()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var ts := []
	var last := Time.get_ticks_usec()
	for i in 150:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		if i >= 30:
			ts.append((now - last) / 1000.0)
		last = now
	DisplayServer.window_set_vsync_mode(vs)
	ts.sort()
	return float(ts[ts.size() / 2])
