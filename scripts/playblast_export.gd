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
	return _winget_ffmpeg()


## winget's install of Gyan.FFmpeg (found even before a new login puts it on PATH)
static func _winget_ffmpeg() -> String:
	var pk := OS.get_environment("LOCALAPPDATA").replace("\\", "/") + "/Microsoft/WinGet/Packages"
	if OS.get_name() != "Windows" or not DirAccess.dir_exists_absolute(pk):
		return ""
	for d in DirAccess.get_directories_at(pk):
		if d.begins_with("Gyan.FFmpeg"):
			for v in DirAccess.get_directories_at(pk + "/" + d):
				var exe := "%s/%s/%s/bin/ffmpeg.exe" % [pk, d, v]
				if FileAccess.file_exists(exe):
					return exe
	return ""


## the ffmpeg arguments: the PNG sequence in dir -> mp4 (H.264, yuv420p; odd sizes padded to even). audio = the sounding
## tracks (AudioTrack.audible_list: a list of {"path", "offset", "gain_db"}; one such dictionary also does): each is muxed in
## so it starts at its offset on the scene's clock; t0 = the scene time of the first frame (a preview range). A sound that
## starts before t0 is cut with -ss, one after it is delayed with -itsoffset. One sound: the same arguments as before;
## several: each gets its gain, and amix sums them. No usable sound file = the same arguments as without
static func args(dir: String, fps: int, mp4: String, audio: Variant = [], t0 := 0.0) -> PackedStringArray:
	var tracks: Array = audio if audio is Array else [audio]
	var a := PackedStringArray(["-y", "-loglevel", "error", "-framerate", str(fps), "-i", dir + "/frame_%04d.png"])
	var snds := []
	for t in tracks:
		var snd := sound_path(t)
		if snd == "":
			continue
		var d := float(t.get("offset", 0.0)) - t0
		if d > 1e-4:
			a.append_array(["-itsoffset", "%.4f" % d])
		elif d < -1e-4:
			a.append_array(["-ss", "%.4f" % -d])
		a.append_array(["-i", snd])
		snds.append(t)
	a.append_array(["-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-c:v", "libx264", "-pix_fmt", "yuv420p"])
	if snds.size() == 1:
		a.append_array(["-af", "volume=%.2fdB" % float(snds[0].get("gain_db", 0.0)), "-c:a", "aac", "-shortest"])
	elif snds.size() > 1:
		var chain := PackedStringArray()
		var ins := ""
		for k in snds.size():
			chain.append("[%d:a]volume=%.2fdB[a%d]" % [k + 1, float(snds[k].get("gain_db", 0.0)), k])
			ins += "[a%d]" % k
		chain.append("%samix=inputs=%d:duration=longest:normalize=0[aout]" % [ins, snds.size()])
		a.append_array(["-filter_complex", ";".join(chain), "-map", "0:v", "-map", "[aout]", "-c:a", "aac", "-shortest"])
	a.append(mp4)
	return a


## the sound's file on disk ("" = none or missing)
static func sound_path(audio: Dictionary) -> String:
	var p := String(audio.get("path", ""))
	if p == "":
		return ""
	p = ProjectSettings.globalize_path(p) if p.begins_with("res://") or p.begins_with("user://") else p
	return p if FileAccess.file_exists(p) else ""


## encode the PNG sequence in dir to an .mp4. Returns the exit code
static func encode(ffmpeg: String, dir: String, fps: int, mp4: String, audio: Variant = [], t0 := 0.0) -> int:
	var out := []
	return OS.execute(ffmpeg, args(dir, fps, mp4, audio, t0), out, true)
