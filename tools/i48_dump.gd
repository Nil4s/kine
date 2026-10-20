## ROADMAP I48 builder step 1 (offline, not shipped data): retarget each converted CMU .bvh onto Kine's skeleton with the app's own
## AnimImport path and write one CSV row per frame: the bend/side/twist of the 22 main joints. The CSV stays in the job's tmp
## folder (raw-derived data is never committed); tools/i48_build.py reduces it to the small statistic in data_gen/.
##   godot --headless --path . -s tools/i48_dump.gd -- <out.csv> <a.bvh> <b.bvh> ...
extends SceneTree

const JOINTS := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head", "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r", "thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]   # = MocapCheck.JOINTS


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var f := FileAccess.open(args[0], FileAccess.WRITE)
	f.store_line("file," + ",".join(PackedStringArray(JOINTS.map(func(j): return "%s_b,%s_s,%s_t" % [j, j, j]))))
	for k in range(1, args.size()):
		var src := AnimImport.load_source(args[k])
		if not src["ok"]:
			print("SKIP ", args[k], " ", src["why"])
			continue
		var m := AnimImport.map_bones(src)
		var rt := AnimImport.retarget(src, m, B, "i48")
		if not rt["ok"]:
			print("SKIP ", args[k], " ", rt["why"])
			continue
		var S: Scene = rt["scene"]
		for c in S.cards:
			var jd: Dictionary = c["pose"]["joints"]
			var row := [String(args[k]).get_file()]
			for j in JOINTS:
				var d: Dictionary = jd.get(j, {})
				row.append_array([snappedf(float(d.get("bend", 0.0)), 0.1), snappedf(float(d.get("side", 0.0)), 0.1), snappedf(float(d.get("twist", 0.0)), 0.1)])
			f.store_line(",".join(PackedStringArray(row.map(func(x): return str(x)))))
		print("ok ", args[k].get_file(), " main ", m["main"], " cards ", S.cards.size())
	f.close()
	quit()
