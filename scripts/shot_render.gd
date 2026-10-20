class_name ShotRender
## RENDER SHOTS TO VIDEO (ROADMAP round 2, R5; the command "Render shots to video (mp4)"): the helpers; the render loop is
## main.gd's _render_shots. The scene's shots (shot_camera.gd) are walked IN ORDER; each shot's frames are its own camera's
## view, so the cut falls on the first frame at or after the shot's cut time. FRAME COUNT = round(duration * fps) (frame k is
## at t = k / fps, k = 0 .. N-1: N frames last N / fps seconds, so the clip's length is the scene's length, not one frame more).
## Files: exports/shots/<scene>_<stamp>/frame_0000.png ... and <scene>.mp4 (the export folder; never scenes/, poses/, data/).

const ROOT := "res://exports/shots"
const EPS := 1e-6


static func frame_count(length: float, fps: int) -> int:
	return maxi(1, roundi(length * fps))


## the first frame of a shot cut at time t: the first k with k / fps >= t
static func first_frame(t: float, fps: int) -> int:
	return ceili(t * fps - EPS)


## the shots' frame ranges in order: [{"shot": i, "first": k0, "count": n}], covering frames 0 .. N-1 exactly once. A cut past the
## end, or two cuts on the same frame, leave their shot with 0 frames (it is skipped, not an error)
static func ranges(shots: Array, length: float, fps: int) -> Array:
	var total := frame_count(length, fps)
	var out := []
	for i in shots.size():
		var a := 0 if i == 0 else mini(first_frame(float(shots[i]["t"]), fps), total)
		var b := total if i == shots.size() - 1 else mini(first_frame(float(shots[i + 1]["t"]), fps), total)
		if b > a:
			out.append({"shot": i, "first": a, "count": b - a})
	return out


## the ffprobe that sits beside an ffmpeg ("" = none)
static func ffprobe_of(ffmpeg: String) -> String:
	var p := ffmpeg.get_base_dir() + "/ffprobe" + (".exe" if OS.get_name() == "Windows" else "")
	return p if FileAccess.file_exists(p) else ""
