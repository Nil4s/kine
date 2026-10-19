class_name PlayblastExport
## PLAYBLAST EXPORT (the command "Export playblast (video)"): the helpers; the render loop is main.gd's _export_playblast.
## What the viewport shows at time t is _ps().apply(B, t) then _refresh(): the loop calls exactly that, once per frame.

const ROOT := "res://exports/playblast"


## the span [a, b] in seconds that is rendered: the preview range if one is set, else the whole scene
static func span(pv_in: float, pv_out: float, length: float) -> Array:
	var sp := PreviewRange.span(pv_in, pv_out, length)
	return sp if not sp.is_empty() else [0.0, length]


## FRAME COUNT: round((b - a) * fps) + 1  (frame k is at t = min(a + k / fps, b); the first and the last both count)
static func frame_count(a: float, b: float, fps: int) -> int:
	return roundi((b - a) * fps) + 1


static func time_of(k: int, a: float, b: float, fps: int) -> float:
	return minf(a + float(k) / fps, b)


## the ffmpeg to use: the one named (a setting or POSER_FFMPEG), else the one on PATH; "" = none
static func find_ffmpeg(configured := "") -> String:
	for c in [configured, OS.get_environment("POSER_FFMPEG")]:
		if c != "" and FileAccess.file_exists(c):
			return c
	var out := []
	var rc := OS.execute("where" if OS.get_name() == "Windows" else "which", ["ffmpeg"], out)
	if rc == 0 and not out.is_empty():
		var line: String = String(out[0]).strip_edges().split("\n")[0].strip_edges()
		if line != "":
			return line
	return ""


## encode the PNG sequence in dir to an .mp4 (H.264, yuv420p; odd sizes padded to even). Returns the exit code
static func encode(ffmpeg: String, dir: String, fps: int, mp4: String) -> int:
	var out := []
	return OS.execute(ffmpeg, ["-y", "-loglevel", "error", "-framerate", str(fps), "-i", dir + "/frame_%04d.png",
		"-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-c:v", "libx264", "-pix_fmt", "yuv420p", mp4], out, true)
