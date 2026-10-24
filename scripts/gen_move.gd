## gen_move.gd - A MOVE FROM WORDS (Nick 2026-10-20: "we can gen infinity animations on comfyui, then use them as videos to
## track... hit w hammers, sprint, other stuff will be more natural than hand made, and we just do our thing").
## The words -> tools/gen_video.py (a short clip from the LOCAL ComfyUI, Wan 2.1 text-to-video: a separate program on this
## machine, talked to over 127.0.0.1 only) -> the video import exactly as a dropped video (main._import_video: MediaPipe,
## VideoIQ, a NEW scene in scenes/_wip). A weapon in the mannequin's hand goes into the import as it does for any video.
## One clip at a time; the window keeps working while it is made (a few minutes on an 8 GB card).
class_name GenMove
extends RefCounted

var tool := "res://tools/gen_video.py"   # a test points it at a stand-in
var python := "python"
var out_dir := ""          # "" = user://gen_moves (a test points it elsewhere)
var pid := -1
var words := ""
var out := ""
var log_path := ""
var t := 0.0
var seconds := 5.0
var seed := 1


## starts making the clip. "" when started, else the reason
func start(w: String, secs := 5.0, sd := -1) -> String:
	if pid >= 0 and OS.is_process_running(pid):
		return "a move is still being made (%s): one at a time" % words
	w = w.strip_edges()
	if w.length() < 4:
		return "say the move in a few words, e.g. \"swings a sledgehammer down onto the ground\""
	words = w
	seconds = clampf(secs, 2.0, 8.0)
	seed = sd if sd >= 0 else randi_range(1, 99999)
	var dir := out_dir if out_dir != "" else OS.get_user_data_dir().path_join("gen_moves")
	DirAccess.make_dir_recursive_absolute(dir)
	var base := _slug(w)
	out = dir.path_join("%s_%d.webm" % [base, seed])
	log_path = dir.path_join("%s_%d.log" % [base, seed])
	var args := PackedStringArray([ProjectSettings.globalize_path(tool), w, out, "--seconds", str(seconds), "--seed", str(seed)])
	pid = OS.create_process(python, args)
	Children.add(pid)
	if pid < 0:
		return "\"%s\" did not start (gen_video.py needs Python 3)" % python
	t = 0.0
	return ""


## one frame: "" while running (or idle); "done" when the clip is there (out); else the reason it failed
func poll(dt: float) -> String:
	if pid < 0:
		return ""
	t += dt
	if OS.is_process_running(pid):
		return ""
	Children.done(pid)
	pid = -1
	if FileAccess.file_exists(out) and FileAccess.get_file_as_bytes(out).size() > 1000:
		return "done"
	return "the clip was not made (is ComfyUI running? start it: D:/ComfyUI/venv/Scripts/python D:/ComfyUI/main.py)"


func busy() -> bool:
	return pid >= 0 and OS.is_process_running(pid)


static func _slug(w: String) -> String:
	var s := ""
	for c in w.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			s += c
		elif s != "" and not s.ends_with("_"):
			s += "_"
	return s.substr(0, 40).trim_suffix("_")
