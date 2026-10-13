extends "res://tools/bo_sweep_low.gd"
## THE LOW STAFF SWEEP, struck with the TIP (Nick 10-13: "an undertaker move ... char kinda crunch position and sweeps
## bo on opponents legs"; "you can keep going, all seems good since the engine was made").
## Nick's standard grip (data/grips/staff.json): right hand 0.30 m from the butt, left 1.01 m, so the long end (0.8 m
## past the left hand) is the one that sweeps. Each key is set by WHERE THE TIP MUST BE, not by an arm guess:
##   for each hip turn and each right-hand spot on a grid round the hips, aim the staff from the hand at the tip target
##   (dir = (tip - hand) / |tip - hand|) and solve both arms (hold_bat). Score = |tip - target| + 2 x 2nd-hand miss
##   + 0.3 x contacts + a hand miss; the best wins. hold_bat's aim is only a tie-break, so a far hand spot shows as a
##   tip miss, never as a staff pointing elsewhere.
## Keys: COIL (tip low out on his LEFT: with Nick's grip, the right hand at the butt, the long end can't reach his right
## without crossing the arms, so the sweep runs left to right), STRIKE (tip through the dummy's shins, in front), FOLLOW (tip out low on
## his right front).
## STATUS 10-13 (5 runs, none usable): the tip never got under ~0.35 m in the crouch with Nick's grip (hits the thighs),
## the grid search flips the left arm between keys (spins), the walk from the strike keeps the arms but misses the coil
## and follow targets by 0.4-1.0 m, and sliding the hands to the butt went the wrong way along the shaft (hold_u is
## measured from the other end). Next: Nick poses the strike key's arms, this tool does the legs + the walk. Writes scenes/_wip/bo_sweep_low.json (not in the poser's list till Nick sees it done); check with tools/hit_report.gd (the dummy's SHINS) and pose_check.
##   godot --headless --path . -s tools/bo_sweep_tip.gd -- [dummy dist, default 1.5]

const TURNS := [-55.0, -35.0, -15.0, 10.0]
const HAND_X := [-0.25, -0.05, 0.12]
const HAND_Y := [-0.04, 0.14]
const HAND_Z := [0.05, 0.30]
## the left upper arm's roll may not jump between keys (the spin rule, 45 deg/key): each deg off the key before costs
## ROLL_W m in the score (45 deg = 0.36 m, more than a near tip miss)
var ROLL_W := 0.0   # 0 for the strike search; the continuation keeps the roll by construction
var prev_roll := 0.0


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
	var roll0: float = prev_roll
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
					var s: float = tm + 2.0 * float(r[2]) + 0.3 * nc + float(r[0]) + ROLL_W * absf((B.ang["upperarm_l"] as Vector3).z - roll0)
					if best.is_empty() or s < float(best[1]):
						var d := B.to_dict()
						d["heel_up"] = ["_r"]
						best = [d, s, tm, r[2], nc, turn]
	# REFINE: the winner's hand spot nudged 6 cm at a time along x, y, z (two rounds), same hip turn
	var bt: float = best[5]
	legs(bt, drop, lean)
	var base2 := B.to_dict()
	var R2 := Basis(Vector3.UP, deg_to_rad(bt))
	var inv := R2.inverse()
	B.from_dict(best[0])
	var hp: Vector3 = inv * ((B.P["hand_r"] as Vector3) - (B.P["pelvis"] as Vector3))
	for round in 2:
		for dv in [Vector3(0.06, 0, 0), Vector3(-0.06, 0, 0), Vector3(0, 0.06, 0), Vector3(0, -0.06, 0), Vector3(0, 0, 0.06), Vector3(0, 0, -0.06)]:
			B.from_dict(base2)
			B.grip2 = g2
			B.grip = true
			var at2: Vector3 = (B.P["pelvis"] as Vector3) + R2 * (hp + dv)
			var r2: Array = B.hold_bat(at2, tip - at2, true, true, lane, 30.0)
			var tm2: float = (B.wep_point(B.wep_len) - tip).length()
			var nc2: int = B.contacts().size()
			var s2: float = tm2 + 2.0 * float(r2[2]) + 0.3 * nc2 + float(r2[0]) + ROLL_W * absf((B.ang["upperarm_l"] as Vector3).z - prev_roll)
			if s2 < float(best[1]):
				var d2 := B.to_dict()
				d2["heel_up"] = ["_r"]
				best = [d2, s2, tm2, r2[2], nc2, bt]
				hp += dv
	return best


const ARMS := ["clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]


## CONTINUATION (after 3 failed grid runs: each key searched alone flipped the arms between keys). From a solved key,
## the tip walks an arc to `to` in `n` steps: its angle round the hips' vertical, its distance and its height all
## lerped; the hip turn lerps to `turn1`. Each step: the legs for that turn, the ARMS COPIED from the step before, the
## right hand carried round the same arc, then hold_bat from there only (one_start): small steps, no flip.
## Returns the poses, the last one = the key; prints the last tip miss.
func walk(from: Dictionary, turn0: float, to: Vector3, turn1: float, n: int, drop: float, lean: float, lane: float) -> Array:
	B.from_dict(from)
	var piv: Vector3 = B.P["pelvis"]
	var t0: Vector3 = B.wep_point(B.wep_len) - piv
	var t1: Vector3 = to - piv
	var a0 := atan2(t0.x, t0.z)
	var a1 := atan2(t1.x, t1.z)
	var r0 := Vector2(t0.x, t0.z).length()
	var r1 := Vector2(t1.x, t1.z).length()
	var h: Vector3 = (B.P["hand_r"] as Vector3) - piv
	var ha0 := atan2(h.x, h.z)
	var hr := Vector2(h.x, h.z).length()
	var out := []
	var prev := from
	for i in range(1, n + 1):
		var u := float(i) / n
		var a := lerp_angle(a0, a1, u)
		var tip := piv + Vector3(sin(a) * lerpf(r0, r1, u), lerpf(t0.y, t1.y, u), cos(a) * lerpf(r0, r1, u))
		var turn := lerpf(turn0, turn1, u)
		legs(turn, drop, lean)
		var pd: Dictionary = prev["joints"]
		for j in ARMS:
			B.ang[j] = Vector3(pd[j]["bend"], pd[j]["side"], pd[j]["twist"])
		B.fk()
		B.grip2 = g2
		B.grip = true
		var ha := ha0 + (a - a0)
		var at: Vector3 = (B.P["pelvis"] as Vector3) + Vector3(sin(ha) * hr, h.y, cos(ha) * hr)
		B.hold_bat(at, tip - at, true, true, lane, 30.0, true)
		var d := B.to_dict()
		d["heel_up"] = ["_r"]
		out.append(d)
		prev = d
		if i == n:
			print("   walk end: tip miss %.3f m, 2nd hand %.3f m, contacts %d, tip %s" % [(B.wep_point(B.wep_len) - to).length(), ((B.P["hand_l"] - B.grip_wrist()) as Vector3).length(), B.contacts().size(), B.wep_point(B.wep_len)])
	return out


func _init() -> void:
	B = Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
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
	# 1. the STRIKE alone, the full search: the tip through the dummy's shins (0.1-0.45 m up at z = D)
	var sk: Array = key(Vector3(0.05, 0.22, D), 0.30, 20.0, lane)
	print("STRIKE: turn %+.0f tip miss %.3f m, 2nd hand %.3f m, contacts %d" % [sk[5], sk[2], sk[3], sk[4]])
	# 2. from the strike, walk the tip BACK to the coil (low out on his left) and ON to the follow (low, right front)
	var back: Array = walk(sk[0], sk[5], Vector3(1.10, 0.25, 0.60), sk[5] + 30.0, 4, 0.30, 16.0, lane)
	var on: Array = walk(sk[0], sk[5], Vector3(-0.50, 0.25, 1.20), sk[5] - 25.0, 3, 0.30, 18.0, lane)
	var S := Scene.new()
	S.name = "bo_sweep_low"
	S.cards.append({"name": "guard (Nick's grip)", "pose": start, "move": 0.0, "hold": 0.2})
	S.cards.append({"name": "COIL (tip low, left)", "pose": back[-1], "move": 0.32, "hold": 0.06, "lift": 0.05})
	S.cards.append({"name": "sweep in", "pose": back[1], "move": 0.08, "hold": 0.0, "lift": 0.05})
	S.cards.append({"name": "STRIKE (shins)", "pose": sk[0], "move": 0.07, "hold": 0.0, "lift": 0.05})
	S.cards.append({"name": "FOLLOW (right front)", "pose": on[-1], "move": 0.14, "hold": 0.14, "lift": 0.05})
	S.cards.append({"name": "rise to guard", "pose": start, "move": 0.42, "hold": 0.3, "lift": 0.05})
	var d := S.to_dict(B)
	d["note"] = "Low staff sweep, the tip through the shins (tools/bo_sweep_tip.gd, Nick's grip): strike searched, coil and follow walked from it"
	FileAccess.open("res://scenes/_wip/bo_sweep_low.json", FileAccess.WRITE).store_string(JSON.stringify(d, " "))
	print("BO SWEEP LOW %.2f s, %d keys, spins %s" % [S.length(), S.cards.size(), S.spins()])
	quit()
