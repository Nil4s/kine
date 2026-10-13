extends "res://tools/bo_sweep_low.gd"
## THE LOW STAFF SWEEP, struck with the TIP (Nick 10-13: "an undertaker move ... char kinda crunch position and sweeps
## bo on opponents legs"; "you can keep going, all seems good since the engine was made").
## Nick's standard grip (data/grips/staff.json): right hand 0.30 m from the butt, left 1.01 m, so the long end (0.8 m
## past the left hand) is the one that sweeps. Each key is set by WHERE THE TIP MUST BE, not by an arm guess:
##   for each hip turn and each right-hand spot on a grid round the hips, aim the staff from the hand at the tip target
##   (dir = (tip - hand) / |tip - hand|) and solve both arms (hold_bat). Score = |tip - target| + 2 x 2nd-hand miss
##   + 0.3 x contacts + a hand miss; the best wins. hold_bat's aim is only a tie-break, so a far hand spot shows as a
##   tip miss, never as a staff pointing elsewhere.
## Keys: COIL (tip low out on his right, in front: with Nick's grip the long end can't wind behind), STRIKE (tip through the dummy's shins, in front), FOLLOW (tip out low on
## his left). Writes scenes/_wip/bo_sweep_low.json (not in the poser's list till Nick sees it done); check with tools/hit_report.gd (the dummy's SHINS) and pose_check.
##   godot --headless --path . -s tools/bo_sweep_tip.gd -- [dummy dist, default 1.5]

const TURNS := [-55.0, -35.0, -15.0, 10.0]
const HAND_X := [-0.25, -0.05, 0.12]
const HAND_Y := [-0.04, 0.14]
const HAND_Z := [0.05, 0.30]


## the legs and the hips of a low key (low() without the arms): returns the feet misses
func legs(turn: float, drop: float, lean: float) -> Array:
	B.from_dict(start)
	var pv: Vector3 = B.ang["pelvis"]
	B.ang["pelvis"] = Vector3(PELVIS_TILT, pv.y, turn)
	B.ang["spine_01"] = B.clamp_ang("spine_01", Vector3((lean - PELVIS_TILT) * 0.5, 0, 0))
	B.ang["spine_02"] = B.clamp_ang("spine_02", Vector3((lean - PELVIS_TILT) * 0.5, 0, 0))
	B.offset.y -= drop
	B.offset.z -= HIPS_BACK * drop
	B.fk()
	var mL := B.plant("_l", Vector3(L_AT.x, (B.p0["ball_l"] as Vector3).y, L_AT.z), L_HEAD, true)
	var rat := Vector3(R_AT.x, (B.p0["ball_r"] as Vector3).y, R_AT.z)
	B.plant("_r", rat, R_HEAD, true)
	B.set_ang("foot_r", B.ang["foot_r"] + Vector3(-heel_lift, 0, 0))
	B.toes_flat("_r")
	B.reach("foot_r", rat - ((B.P["ball_r"] - B.P["foot_r"]) as Vector3))
	return [mL, ((B.P["ball_r"] - rat) as Vector3).length()]


## the best pose with the staff's tip at `tip` (world): [pose, score, tip miss, 2nd-hand miss, contacts, turn]
func key(tip: Vector3, drop: float, lean: float, lane: float) -> Array:
	var best := []
	for turn in TURNS:
		legs(turn, drop, lean)
		var base := B.to_dict()
		var R := Basis(Vector3.UP, deg_to_rad(turn))
		for x in HAND_X:
			for y in HAND_Y:
				for z in HAND_Z:
					B.from_dict(base)
					B.grip2 = g2
					B.grip = true
					var at: Vector3 = (B.P["pelvis"] as Vector3) + R * Vector3(x, y, z)
					var r: Array = B.hold_bat(at, tip - at, true, true, lane, 30.0)
					var tm: float = (B.wep_point(B.wep_len) - tip).length()
					var nc: int = B.contacts().size()
					var s: float = tm + 2.0 * float(r[2]) + 0.3 * nc + float(r[0])
					if best.is_empty() or s < float(best[1]):
						var d := B.to_dict()
						d["heel_up"] = ["_r"]
						best = [d, s, tm, r[2], nc, turn]
	return best


func _init() -> void:
	B = Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	# START: Nick's two-hand catch (his standard grip) on standing legs
	var gd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://moves/bo_two_hand_nick.json"))
	var st: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json"))
	for j in LEGS:
		gd["joints"][j] = st["joints"][j]
	B.from_dict(gd)
	B.ground()
	B.capture_second()
	B.apply_grip()
	g2 = B.grip2
	start = B.to_dict()
	var lane: float = (B.ang["hand_r"] as Vector3).z
	var a := OS.get_cmdline_user_args()
	var D := float(a[0]) if a.size() > 0 else 1.5
	# the tip targets (world, the hero faces +z; + x = his left): the dummy's shins are 0.1-0.45 m up at z = D
	var keys := [
		["COIL (tip low out right)", Vector3(-1.2, 0.30, 0.60), 0.28, 14.0, 0.30, 0.06],
		["STRIKE (shins)", Vector3(0.05, 0.28, D), 0.30, 20.0, 0.14, 0.0],
		["FOLLOW (tip out left)", Vector3(1.15, 0.32, 0.75), 0.28, 16.0, 0.14, 0.14],
	]
	var S := Scene.new()
	S.name = "bo_sweep_low"
	S.cards.append({"name": "guard (Nick's grip)", "pose": start, "move": 0.0, "hold": 0.2})
	for k in keys:
		var r: Array = key(k[1], k[2], k[3], lane)
		B.from_dict(r[0])
		lane = (B.ang["hand_r"] as Vector3).z
		var t: Vector3 = B.wep_point(B.wep_len)
		print("%-30s turn %+.0f  tip miss %.3f m  2nd hand %.3f m  contacts %d  tip (%.2f, %.2f, %.2f)" % [k[0], r[5], r[2], r[3], r[4], t.x, t.y, t.z])
		S.cards.append({"name": k[0], "pose": r[0], "move": k[4], "hold": k[5], "lift": 0.05})
	S.cards.append({"name": "rise to guard", "pose": start, "move": 0.40, "hold": 0.3, "lift": 0.05})
	var d := S.to_dict(B)
	d["note"] = "Low staff sweep, the tip through the shins (tools/bo_sweep_tip.gd, Nick's grip): coil, strike, follow, rise"
	FileAccess.open("res://scenes/_wip/bo_sweep_low.json", FileAccess.WRITE).store_string(JSON.stringify(d, " "))
	print("BO SWEEP LOW %.2f s, %d keys, spins %s" % [S.length(), S.cards.size(), S.spins()])
	quit()
