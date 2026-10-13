extends SceneTree
## STANDARD POSE CHECK (Nick 10-13: "the engine gives us full safety and limits of body, think before calling anything
## good"). Every pose in poses/ (or the files given) is loaded, put on the floor, and judged; a pose goes in the library
## only if every check passes.
##   godot --headless --path . -s tools/pose_check.gd [-- [--settle] poses/a.json poses/b.json ...]
##   --settle: a joint ON a limit is moved 5 deg back inside its range, the pose re-grounded and judged again; the file
##   is rewritten only if it then passes every check (never for poses/ itself: only poses/lib/)
##
## The checks (numbers in metres / degrees):
##   LIMITS    no joint sits on the end of its range (Body.at_limit; a straight knee/elbow is not a warning)
##   CONTACTS  no pair of parts deeper than its neutral-pose allowance + 1 mm (Body.contacts)
##   FEET      both toe bases on the floor (within 2 cm); heels down unless the pose lists the foot in "heel_up"
##   KNEES     a bent leg's knee points within 25 deg of its foot (the knee tracks over the toes)
##   BALANCE   the hips (pelvis, seen from above) within 12 cm of the line between the two ankles, and not past
##             either ankle by more than 15 % of the stance
##   WRIST     the bat hand straight with the forearm: bend within +-15, side within +-20 (twist = the forearm turn, free)
##   AIM       the bat never points back into its owner (Nick 10-13: "we as humans don't spin our arms to the inside
##             pointing a weapon at ourselves, it's a nonsense position"): from the knob, the tip may not point within
##             50 deg of the own chest, hips or head while its line passes within 30 cm of them
## The VISIBLE skin is judged too, by tools/mesh_truth.gd (the capsules can't see the chest/hip front): a library pose
## passes both.

const LIMITS_SKIP := ["root", "ik_foot_root", "ik_hand_root"]
const FINGERS := ["thumb", "index", "middle", "ring", "pinky"]   # a fist IS the fingers at full curl: not strain


func _init() -> void:
	var files: Array = OS.get_cmdline_user_args()
	var settle := files.has("--settle")
	files.erase("--settle")
	if files.is_empty():
		for f in DirAccess.get_files_at("res://poses"):
			if f.ends_with(".json"):
				files.append("poses/" + f)
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var n_ok := 0
	for f in files:
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://" + f))
		if not d is Dictionary:
			print("%-34s  NOT A POSE" % f)
			continue
		B.from_dict(d)
		B.ground()
		var fails := check(B, d)
		if settle and not fails.is_empty() and (f as String).begins_with("poses/lib/"):
			var moved := []
			for j in B.ang:
				if j in LIMITS_SKIP or not B.lim.has(j) or FINGERS.any(func(x): return (j as String).begins_with(x)):
					continue
				var v: Vector3 = B.ang[j]
				var L: Dictionary = B.lim[j]
				var nv := v
				for k in 3:
					var r: Vector2 = L[["bend", "side", "twist"][k]]
					if r.y - r.x < 0.5:
						continue
					if r.x != 0.0 and v[k] <= r.x + 0.5:
						nv[k] = r.x + 5.0
					elif r.y != 0.0 and v[k] >= r.y - 0.5:
						nv[k] = r.y - 5.0
				if nv != v:
					B.ang[j] = nv
					moved.append(j)
			B.fk()
			B.apply_grip()
			B.ground()
			# a foot floating mid-step: set it straight down where it is (the leg alone moves)
			var heel_up: Array = d.get("heel_up", [])
			for sd in ["_l", "_r"]:
				var fs: Array = B.foot_state(sd)
				if not fs[2]:
					var at: Vector3 = fs[0]
					at.y = (B.p0["ball" + sd] as Vector3).y
					B.plant(sd, at, fs[1], not sd in heel_up)
					moved.append("foot" + sd + " down")
			# still floating: the stance is wider than the legs reach at this hip height -> lower the hips 1 cm at a time
			# and re-plant both feet where they stand, until both are down (at most 10 cm)
			var spots := {}
			for sd in ["_l", "_r"]:
				var fs0: Array = B.foot_state(sd)
				var at0: Vector3 = fs0[0]
				at0.y = (B.p0["ball" + sd] as Vector3).y
				spots[sd] = [at0, fs0[1]]
			var dropped := 0
			while dropped < 10 and (not B.foot_state("_l")[2] or not B.foot_state("_r")[2]):
				B.offset.y -= 0.01
				dropped += 1
				B.fk()
				for sd in ["_l", "_r"]:
					B.plant(sd, spots[sd][0], spots[sd][1], not sd in heel_up)
			if dropped > 0:
				moved.append("hips down %d cm" % dropped)
			# the belly in the thighs (a deep hip hinge): take the hinge back 2 deg at a time (at most 10)
			for k in 5:
				var trunk := B.contacts().filter(func(c): return (c[0] as String).begins_with("spine") and (c[1] as String).begins_with("thigh"))
				if trunk.is_empty():
					break
				for j in ["pelvis", "spine_01"]:
					var v: Vector3 = B.ang[j]
					B.ang[j] = B.clamp_ang(j, v - Vector3(1.0, 0, 0))
				B.fk()
				for sd in ["_l", "_r"]:
					B.plant(sd, spots[sd][0], spots[sd][1], not sd in heel_up)
				if k == 0:
					moved.append("hip hinge back")
			# a heel-up foot pivots on its ball: its knee turns over that foot (the leg turns about hip -> ankle)
			for sd in heel_up:
				B.knee_over_toes(sd, B.foot_heading(sd))
			# a graze: search the arm(s) involved out of it, staying closest to the pose
			var con: Array = B.contacts()
			if not con.is_empty():
				var js := []
				for c in con:
					for part in [c[0], c[1]]:
						var s: String = part
						if s in Body.WEAPON and B.wep_hand != "":
							s = B.wep_hand
						for sd in ["_r", "_l"]:
							if s.ends_with(sd) and (s.begins_with("upperarm") or s.begins_with("lowerarm") or s.begins_with("hand") or s.begins_with("clavicle")):
								for j in ["clavicle" + sd, "upperarm" + sd, "lowerarm" + sd]:
									if not j in js:
										js.append(j)
				if not js.is_empty():
					var want := {}
					for j in js:
						want[j] = B.ang[j]
					var near := func() -> float:
						var c := 0.0
						for j in js:
							c += ((B.ang[j] as Vector3) - (want[j] as Vector3)).length() / 400.0
						return c
					B.search(js, near, 0.0)
					B.apply_grip()
					moved.append("arms out of " + str(con.size()) + " grazes")
			var f2 := check(B, d)
			if f2.is_empty():
				var out: Dictionary = B.to_dict()
				for key in ["note", "from", "heel_up"]:
					if d.has(key):
						out[key] = d[key]
				out["settled"] = moved
				FileAccess.open("res://" + f, FileAccess.WRITE).store_string(JSON.stringify(out, " "))
				print("%-34s  settled (%s moved 5 deg off the limit)" % [f, ", ".join(moved)])
			fails = f2
		if fails.is_empty():
			n_ok += 1
			print("%-34s  PASS" % f)
		else:
			print("%-34s  FAIL  %s" % [f, "; ".join(fails)])
	print("POSES %d/%d pass" % [n_ok, files.size()])
	quit()


static func check(B: Body, d: Dictionary) -> Array:
	var fails := []
	# LIMITS
	var lim_hit := []
	for j in B.ang:
		if j in LIMITS_SKIP or not B.lim.has(j) or FINGERS.any(func(f): return (j as String).begins_with(f)):
			continue
		var al: Array = B.at_limit(j)
		if not al.is_empty():
			lim_hit.append("%s %s" % [j, "/".join(al)])
	if not lim_hit.is_empty():
		fails.append("at limit: " + ", ".join(lim_hit))
	# CONTACTS
	var con: Array = B.contacts()
	if not con.is_empty():
		fails.append("inside: " + ", ".join(con.map(func(c): return "%s/%s %.0f mm" % [c[0], c[1], c[2] * 1000.0])))
	# FEET
	var heel_up: Array = d.get("heel_up", [])
	var fs := {}
	for sd in ["_l", "_r"]:
		fs[sd] = B.foot_state(sd)
		if not fs[sd][2]:
			fails.append("foot%s off the floor" % sd)
		elif not fs[sd][3] and not sd in heel_up:
			fails.append("heel%s up (not listed in heel_up)" % sd)
	# KNEES over the toes
	for sd in ["_l", "_r"]:
		var H: Vector3 = B.P["thigh" + sd]
		var A: Vector3 = B.P["foot" + sd]
		var u := (A - H).normalized()
		var k: Vector3 = (B.P["calf" + sd] as Vector3) - H
		k -= u * u.dot(k)
		if k.length() < 0.02:
			continue   # straight leg: no knee direction
		var hd: float = fs[sd][1]
		var w := Vector3(sin(hd), 0.0, cos(hd))
		w -= u * u.dot(w)
		var a := rad_to_deg(k.normalized().angle_to(w.normalized()))
		if a > 25.0:
			fails.append("knee%s points %.0f deg off its foot" % [sd, a])
	# BALANCE
	var al := B.P["foot_l"] as Vector3
	var ar := B.P["foot_r"] as Vector3
	var pv := B.P["pelvis"] as Vector3
	var a2 := Vector2(al.x, al.z)
	var b2 := Vector2(ar.x, ar.z)
	var p2 := Vector2(pv.x, pv.z)
	var ab := b2 - a2
	var tt := clampf((p2 - a2).dot(ab) / maxf(1e-6, ab.length_squared()), -1.0, 2.0)
	var off := (p2 - (a2 + ab * clampf(tt, 0.0, 1.0))).length()
	if off > 0.12 or tt < -0.15 or tt > 1.15:
		fails.append("off balance (hips %.0f cm from the line between the ankles)" % (off * 100.0))
	# WRIST
	if B.wep_on and B.wep_hand != "":
		var v: Vector3 = B.ang[B.wep_hand]
		if absf(v.x) > 15.5 or absf(v.y) > 20.5:
			fails.append("bat wrist bent (bend %.0f, side %.0f)" % [v.x, v.y])
		# AIM: not at yourself
		var k: Vector3 = B.cap("bat_handle")[0]
		var t: Vector3 = B.wep_point(B.wep_len)   # the tip (a hammer's head capsule lies across it)
		var dv := (t - k).normalized()
		# a staff is held in the middle and strikes with both ends: one end back past you is how it's carried
		for part in (["spine_03", "pelvis", "head"] if Body.KINDS[B.wep_kind]["aim"] else []):
			var c: Vector3 = (B.P[part] as Vector3) + (Vector3(0, 0.08, 0) if part == "head" else Vector3.ZERO)
			var ang := rad_to_deg(dv.angle_to(c - k))
			var near := (c - (k + dv * clampf((c - k).dot(dv), 0.0, (t - k).length()))).length()
			if ang < 50.0 and near < 0.30:
				fails.append("bat points at its owner's %s (%.0f deg, passes %.0f cm off)" % [part, ang, near * 100.0])
	return fails
