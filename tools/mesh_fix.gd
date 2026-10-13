extends "res://tools/mesh_truth.gd"
## FIX THE BAD FRAME, NOT THE MOVE (Nick 10-13: "our system is friendly, just need to move this specific frame and we
## are cool, no need to start from zero"). Judge = the VISIBLE skin (mesh_truth.measure). Loop: find the move's worst
## frame where an arm is inside the body; at that moment take the pose the player shows, nudge only that side's arm
## (clavicle, upper arm, elbow; the forearm's turn is never touched, so no fix can add a spin) in small steps until the
## skin is clear, staying as close as it can to where the arm was; put that pose in as a new key at that moment (the
## segment's time is split, the move's length stays the same). Repeat until clean (at most MAX_FIX keys).
##   godot --headless --path . -s tools/mesh_fix.gd -- scenes/<name>.json        (rewrites the scene; git shows the diff)

const MAX_FIX := 8
const CLEAR_MM := 2.0
const NEAR := 0.0004   # cost per degree moved from the arm as it was (a 10 deg move = 4 mm of "inside")


func _initialize() -> void:
	B = Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	man = (load("res://assets/mannequin.glb") as PackedScene).instantiate()
	get_root().add_child(man)
	skel = man.find_children("*", "Skeleton3D", true, false)[0]
	for j in Body.ORDER:
		bone_idx[j] = skel.find_bone("Head" if j == "head" else j)
	_cache()
	var f: String = OS.get_cmdline_user_args()[0]
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://" + f)))
	var fixes := 0
	while fixes < MAX_FIX:
		# the worst frame now
		var n := int(ceil(S.length() * 30.0))
		var wt := -1.0
		var wd := 0.0
		var wwhere := ""
		var nbad := 0
		for fr in n + 1:
			S.apply(B, float(fr) / 30.0)
			var r: Array = measure()
			if r[0] * 1000.0 > INSIDE_MM:
				nbad += 1
				if r[0] > wd:
					wd = r[0]
					wt = float(fr) / 30.0
					wwhere = r[1]
		if wt < 0.0:
			break
		print("worst: t=%.2f %.0f mm %s  (%d bad frames)" % [wt, wd * 1000.0, wwhere, nbad])
		# the side that's inside: the first "_l"/"_r" in "thumb_02_r in thigh_r"
		var sd := "_r" if (wwhere.split(" ")[0] as String).ends_with("_r") else "_l"
		S.apply(B, wt)
		var js := ["clavicle" + sd, "upperarm" + sd, "lowerarm" + sd]
		var start := {}
		for j in js:
			start[j] = B.ang[j]
		var cost := func() -> float:
			var c: float = (measure()[0] as float)
			for j in js:
				c += NEAR * ((B.ang[j] as Vector3) - (start[j] as Vector3)).length()
			return c
		var best: float = cost.call()
		for stp in [8.0, 4.0, 2.0]:
			var moved := true
			var rounds := 0
			while moved and rounds < 6:
				moved = false
				rounds += 1
				for j in js:
					for k in 3:
						if j.begins_with("lowerarm") and k != 0:
							continue   # the elbow only bends
						for sg in [-1.0, 1.0]:
							var v: Vector3 = B.ang[j]
							var nv := v
							nv[k] += sg * stp
							nv = B.clamp_ang(j, nv)
							if nv == v:
								continue
							B.ang[j] = nv
							B.fk()
							B.apply_grip()
							var c: float = cost.call()
							if c < best - 1e-5:
								best = c
								moved = true
							else:
								B.ang[j] = v
								B.fk()
								B.apply_grip()
		var r2: Array = measure()
		print("   fixed to %.0f mm (moved %s)" % [r2[0] * 1000.0, ", ".join(js.map(func(j): return "%s %.0f deg" % [j, ((B.ang[j] as Vector3) - (start[j] as Vector3)).length()]))])
		# into the scene at that moment: in a hold -> the key itself; in a move -> a new key, the segment's time split
		var ts: Array = S.times()
		var put := false
		for i in S.cards.size():
			if wt >= ts[i][1] - 1e-4 and wt <= ts[i][2] + 1e-4:
				S.cards[i]["pose"] = B.to_dict()
				put = true
				break
			if wt > ts[i][0] and wt < ts[i][1]:
				var mv: float = ts[i][1] - ts[i][0]
				var u: float = (wt - ts[i][0]) / mv
				S.cards.insert(i, {"name": "fix (skin)", "pose": B.to_dict(), "move": mv * u, "hold": 0.0})
				S.cards[i + 1]["move"] = mv * (1.0 - u)
				put = true
				break
		if not put:
			S.cards[0]["pose"] = B.to_dict()
		fixes += 1
	var d: Dictionary = S.to_dict(B)
	for key in ["plan", "note"]:
		var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + f))
		if old.has(key):
			d[key] = old[key]
	FileAccess.open("res://" + f, FileAccess.WRITE).store_string(JSON.stringify(d, " "))
	var sp: Array = S.spins()
	print("MESH FIX %s: %d keys fixed, spins %d, length %.2f s" % [f, fixes, sp.size(), S.length()])
	quit()
