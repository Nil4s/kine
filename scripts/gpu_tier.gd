class_name GpuTier
extends RefCounted
## GPU TIERS (Friday plan 230; research: tools/kine_workers/GPU_TIERS.md). Three things that need no native DLL:
##  1. DETECT   the adapter's name -> a tier: basic / rtx30 (RTX 20 and 30, "Turing/Ampere") / rtx40 / rtx50 / amd / intel
##  2. ENCODER  the video encoder ffmpeg is told to use: NVENC (h264_nvenc, hevc_nvenc; av1_nvenc only on RTX 40+) when this
##              PC has it AND a 0.3 s test encode works, else libx264 (the CPU). One choice, remembered, in View > Graphics quality
##  3. FAST VIEW Godot's own FSR 2 (scaling_3d_mode) at 0.67 for a heavy scene in the live view. Off by default. Forward+ only.
##              Never applied while a video or picture is rendered (the file must be full quality).
## Nothing here touches the environment or lights (item 224 owns those).

const TIERS := ["basic", "rtx30", "rtx40", "rtx50", "amd", "intel"]
const TIER_NAMES := {"basic": "Basic", "rtx30": "RTX 20/30", "rtx40": "RTX 40", "rtx50": "RTX 50", "amd": "AMD", "intel": "Intel"}
const ENCODERS := ["auto", "h264_nvenc", "hevc_nvenc", "av1_nvenc", "libx264"]
const ENCODER_NAMES := {"auto": "Auto (the processor: the card was no faster in tests)", "h264_nvenc": "H.264 on the GPU (NVENC)",
	"hevc_nvenc": "HEVC on the GPU (NVENC)", "av1_nvenc": "AV1 on the GPU (RTX 40 and 50)", "libx264": "H.264 on the CPU"}
const FAST_SCALE := 0.67   # FSR 2 "Quality" is 1.5x per axis = 0.667
const CFG := "gpu"

## the choice this session (tests keep libx264 + Fast view off unless they set it; the app loads the saved one at start)
static var pref := "libx264"
static var fast_view := false
static var _probe_cache := {}
static var _resolved := {}


## the tier of an adapter name. Pure: the tests feed it fake names.
static func tier_of(adapter: String) -> String:
	var s := adapter.to_lower()
	if s.contains("nvidia") or s.contains("geforce") or s.contains("rtx") or s.contains("gtx") or s.contains("quadro") or s.contains("titan"):
		var rx := RegEx.new()
		rx.compile("rtx\\s*(\\d)(\\d)\\d\\d")
		var m := rx.search(s)
		if m != null:
			match int(m.get_string(1)):
				2, 3:
					return "rtx30"
				4:
					return "rtx40"
				5:
					return "rtx50"
			return "basic"
		if s.contains("blackwell") or s.contains("rtx pro"):
			return "rtx50"
		if s.contains(" ada") or s.contains("rtx 6000 ada") or s.contains("l40"):
			return "rtx40"
		rx.compile("rtx\\s*a\\d{3,4}")   # RTX A2000 ... A6000: Ampere workstation
		if rx.search(s) != null:
			return "rtx30"
		if s.contains("titan rtx") or s.contains("quadro rtx"):
			return "rtx30"
		return "basic"
	if s.contains("amd") or s.contains("radeon"):
		return "amd"
	if s.contains("intel") or s.contains("arc"):
		return "intel"
	return "basic"


static func nvidia(tier: String) -> bool:
	return tier == "rtx30" or tier == "rtx40" or tier == "rtx50"


## the machine now: {adapter, vendor, vram_mb, tier}
static func info() -> Dictionary:
	var ad := RenderingServer.get_video_adapter_name()
	return {"adapter": ad, "vendor": RenderingServer.get_video_adapter_vendor(), "vram_mb": Quality.vram_mb(), "tier": tier_of(ad)}


## the encoders this tier may offer, best-known order
static func encoders_for(tier: String) -> Array:
	var a := ["libx264"]
	if nvidia(tier):
		a = ["h264_nvenc", "hevc_nvenc"] + (["av1_nvenc"] if tier != "rtx30" else []) + a
	return a


## one line for the menu / the status line
static func summary(i: Dictionary) -> String:
	var v := int(i.get("vram_mb", -1))
	return "%s  =  %s tier%s" % [String(i["adapter"]), TIER_NAMES[String(i["tier"])], "" if v <= 0 else ", %.0f GB" % (v / 1024.0)]


## does this ffmpeg really encode with that encoder here (a 0.3 s black clip to nowhere)? Cached per ffmpeg + encoder
static func probe(ffmpeg: String, enc: String) -> bool:
	if enc == "libx264":
		return true
	if (ffmpeg.contains("/") or ffmpeg.contains("\\")) and not FileAccess.file_exists(ffmpeg):
		return false   # a path that is not there: no process is started
	var k := ffmpeg + "|" + enc
	if _probe_cache.has(k):
		return _probe_cache[k]
	var out := []
	var rc := OS.execute(ffmpeg, ["-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "color=c=black:s=256x256:r=10:d=0.3",
		"-c:v", enc, "-f", "null", "-"], out, true)
	_probe_cache[k] = rc == 0
	return rc == 0


## the encoder a save really uses: the preference ("auto" = libx264), on this PC, if ffmpeg proves it works; else libx264
static func resolve(p: String, tier: String, ffmpeg: String) -> String:
	if p == "libx264" or ffmpeg == "":
		return "libx264"
	# Auto = the CPU: measured on Kine's own exports (tests/s230_test.gd, RTX 3070, 3 runs) NVENC was x0.86 - x1.32 whole-export, inside the
	# noise, because the render + frame read-back + PNG/pipe step dominates. The card is opt-in (it frees the CPU), never the silent default.
	var e: String = "libx264" if p == "auto" else p
	if e != "libx264" and (not encoders_for(tier).has(e) or not probe(ffmpeg, e)):
		return "libx264"
	return e


## the encoder for ffmpeg-args building (PlayblastExport): resolved once per preference
static func encoder() -> String:
	if pref == "libx264":
		return "libx264"
	if _resolved.has(pref):
		return _resolved[pref]
	var e := resolve(pref, String(info()["tier"]), PlayblastExport.find_ffmpeg())
	_resolved[pref] = e
	return e


## "-c:v ..." for the picture. libx264 = what it always was (plus the preset when one is given). NVENC: constant quality 23,
## yuv420p comes from the caller; HEVC in mp4 is tagged hvc1 so Windows and Apple players open it
static func codec_args(preset: String, enc := "") -> PackedStringArray:
	if enc == "":
		enc = encoder()
	if enc == "libx264":
		var a := PackedStringArray(["-c:v", "libx264"])
		if preset != "":
			a.append_array(["-preset", preset])
		return a
	var n := PackedStringArray(["-c:v", enc, "-preset", "p4", "-rc", "vbr", "-cq", "23", "-b:v", "0"])
	if enc == "hevc_nvenc":
		n.append_array(["-tag:v", "hvc1"])
	return n


static func load_settings(cfg: String, testing: bool) -> void:
	var cf := ConfigFile.new()
	var has := cf.load(cfg) == OK
	var p := String(cf.get_value(CFG, "encoder", "auto" if not testing else "libx264")) if has else ("libx264" if testing else "auto")
	pref = p if ENCODERS.has(p) else "libx264"
	fast_view = bool(cf.get_value(CFG, "fast_view", false)) if has else false
	_resolved.clear()


static func save_settings(cfg: String) -> void:
	var cf := ConfigFile.new()
	cf.load(cfg)
	cf.set_value(CFG, "encoder", pref)
	cf.set_value(CFG, "fast_view", fast_view)
	cf.save(cfg)


## Fast view onto a viewport: FSR 2 at 0.67 (Forward+ only; the other renderers keep what Quality set). Off: Quality's own picture.
static func apply_fast(vp: Viewport, preset_scale: float) -> void:
	if fast_view and Quality.current_renderer() == "forward_plus":
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		vp.scaling_3d_scale = FAST_SCALE
	else:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = preset_scale


## a file/picture is being rendered: full quality for it. Returns what to give back to release()
static func hold(vp: Viewport) -> Dictionary:
	var h := {"mode": vp.scaling_3d_mode, "scale": vp.scaling_3d_scale}
	if fast_view:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = 1.0
	return h


static func release(vp: Viewport, h: Dictionary) -> void:
	vp.scaling_3d_mode = int(h["mode"]) as Viewport.Scaling3DMode
	vp.scaling_3d_scale = float(h["scale"])
