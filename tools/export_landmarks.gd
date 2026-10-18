extends SceneTree
## A poser scene as the SAME 33-landmark skeleton MediaPipe gives for a video (Nick 10-13: identify, then compare):
## real footage is tracked by tools/see/pose.py, our moves are exported EXACTLY by this, and the game repo's
## tools/see/identify.py reads both the same way. Landmarks: nose 0 (head end), shoulders 11/12, elbows 13/14,
## wrists 15/16, hips 23/24, knees 25/26, ankles 27/28, foot tips 31/32; the rest stay 0 (unused by the angles).
## MediaPipe frame: metres, hips' midpoint at 0, y DOWN: ours rotated 180 deg about x (y,z negated: a rotation, so
## left/right and the twist's sign survive).
##   godot --headless --path . -s tools/export_landmarks.gd -- scenes/a.json <out dir> [fps 30]
const MAP := {0: ["head", true], 11: ["upperarm_l", false], 12: ["upperarm_r", false], 13: ["lowerarm_l", false],
	14: ["lowerarm_r", false], 15: ["hand_l", false], 16: ["hand_r", false], 23: ["thigh_l", false],
	24: ["thigh_r", false], 25: ["calf_l", false], 26: ["calf_r", false], 27: ["foot_l", false], 28: ["foot_r", false],
	31: ["ball_l", true], 32: ["ball_r", true]}


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var fps := float(a[2]) if a.size() > 2 else 30.0
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://" + a[0])))
	var frames := []
	for i in int(S.length() * fps) + 1:
		var t := minf(i / fps, S.length())
		S.apply(B, t)
		B.fk()
		# round 45 (AA0): the points are VideoImport.landmarks_of's (the same that reads them back), heels 29 / 30 included
		var w := []
		for p in VideoImport.landmarks_of(B):
			w.append([snappedf(p.x, 0.0001), snappedf(-p.y, 0.0001), snappedf(-p.z, 0.0001)])
		frames.append({"t": snappedf(t, 0.001), "world": w, "tip_ms": 0.0})
	DirAccess.make_dir_recursive_absolute(a[1])
	FileAccess.open(a[1].path_join("pose.json"), FileAccess.WRITE).store_string(JSON.stringify({"fps": fps,
		"video": a[0], "frames": frames, "note": "EXACT from the poser (tools/export_landmarks.gd), MediaPipe layout"}))
	print("LANDMARKS %s: %d frames -> %s" % [a[0], frames.size(), a[1]])
	quit()
