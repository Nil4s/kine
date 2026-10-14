extends SceneTree
## LEAP SLAM with the long hammer: a PROPOSAL traced from the poleaxe short Nick sent 10-13 (docs/refs/POLEAXE_LEAP_SLAM.md,
## "will work for long warhammer and glaives"). The beats: drop into a deep wide crouch, the hammer upright at the right
## side (LOAD, held 0.23 s), the hammer windmills back behind the head, the legs straighten and he leaves the floor,
## knees tucked in the air as the hammer comes over the top, it crashes down in front AS the feet land, the wide low
## landing is held 0.5 s, then he rises to the guard. Times are the reference's, frame for frame.
## Starts from Nick's overhead_load arms on standing legs; the long hammer held at the butt by the right hand, the left
## 40 cm up (the sledge hold). Writes scenes/_wip/ only: Nick poses the real one.
##   godot --headless --path . -s tools/leap_slam.gd        -> scenes/_wip/leap_slam.json
const LEGS := ["thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]
const L_AT := Vector3(0.22, 0.0, 0.44)    # the lunge: the left (front) toe base forward
const R_AT := Vector3(-0.24, 0.0, -0.46)  # the right (back) toe base back, heel up
const PELVIS_TILT := 18.0

var B: Body
var start: Dictionary


## a key: hips turned `turn` deg, dropped `drop` m (negative = up, off the floor), chest leaning `lean` deg forward;
## feet "plant" (the wide stance) or "tuck" (in the air: thighs `tuck` deg up, knees folded); the bat hand's wrist at
## `at` from the hips (in the hips' facing), the hammer pointing `dir` (butt -> head, world)
func key(turn: float, drop: float, lean: float, feet: String, tuck: float, at: Vector3, dir: Vector3) -> Array:
	B.from_dict(start)
	var pv: Vector3 = B.ang["pelvis"]
	B.ang["pelvis"] = Vector3(PELVIS_TILT if feet == "plant" else 0.0, pv.y, turn)
	var sp := lean - (PELVIS_TILT if feet == "plant" else 0.0)
	B.ang["spine_01"] = B.clamp_ang("spine_01", Vector3(sp * 0.5, 0, 0))
	B.ang["spine_02"] = B.clamp_ang("spine_02", Vector3(sp * 0.5, 0, 0))
	B.offset.y -= drop
	B.fk()
	var mL := 0.0
	var mR := 0.0
	var heel := []
	if feet == "plant":
		mL = B.plant("_l", Vector3(L_AT.x, (B.p0["ball_l"] as Vector3).y, L_AT.z), 0.15, true)
		var rat := Vector3(R_AT.x, (B.p0["ball_r"] as Vector3).y, R_AT.z)
		B.plant("_r", rat, -0.26, true)
		B.set_ang("foot_r", B.ang["foot_r"] + Vector3(-10, 0, 0))
		B.toes_flat("_r")
		B.reach("foot_r", rat - ((B.P["ball_r"] - B.P["foot_r"]) as Vector3))
		mR = ((B.P["ball_r"] - rat) as Vector3).length()
		heel = ["_r"]
	else:
		# in the air: both thighs up, the knees folded under (the reference tucks at the top of the jump)
		for sd in ["_l", "_r"]:
			B.set_ang("thigh" + sd, Vector3(tuck, 0, 0))
			B.set_ang("calf" + sd, Vector3(tuck * 1.4, 0, 0))
			B.set_ang("foot" + sd, Vector3(-15, 0, 0))
	B.grip = true
	var R := Basis(Vector3.UP, deg_to_rad(turn))
	var r: Array = B.hold_bat((B.P["pelvis"] as Vector3) + R * at, dir.normalized(), true, true, NAN, 15.0, false, 0.5)
	var d: Dictionary = B.to_dict()
	if not heel.is_empty():
		d["heel_up"] = heel
	return [d, r, mL, mR]


func _init() -> void:
	B = Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var gd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://poses/lib/overhead_load.json"))
	var st: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json"))
	for j in LEGS:
		gd["joints"][j] = st["joints"][j]
	gd.erase("heel_up")
	B.from_dict(gd)
	B.set_kind("long_hammer")
	B.grip = true
	B.grip_u = 0.55
	B.ground()
	start = B.to_dict()
	var S := Scene.new()
	S.name = "leap_slam"
	var guard: Array = key(0.0, 0.03, 4.0, "plant", 0.0, Vector3(-0.24, 0.42, 0.18), Vector3(0.0, 1.0, 0.15))
	S.cards.append({"name": "guard", "pose": guard[0], "move": 0.0, "hold": 0.3})
	# [name, hip turn, drop m, lean, feet, tuck, wrist from the hips, hammer dir, move s, hold s]
	var keys := [
		["LOAD (crouch)", -30.0, 0.28, 12.0, "plant", 0.0, Vector3(-0.28, 0.50, 0.08), Vector3(-0.1, 1.0, -0.15), 0.10, 0.23],
		["windmill back", -40.0, 0.24, 6.0, "plant", 0.0, Vector3(-0.15, 0.72, -0.02), Vector3(-0.25, 0.25, -1.0), 0.13, 0.0],
		["take-off", -15.0, -0.15, 0.0, "tuck", 15.0, Vector3(-0.06, 0.80, -0.02), Vector3(0.0, 0.55, -1.0), 0.10, 0.0],
		["airborne: over the top", 0.0, -0.62, 12.0, "tuck", 60.0, Vector3(-0.04, 0.85, 0.10), Vector3(0.0, 1.0, -0.15), 0.13, 0.0],
		["STRIKE (lands)", 0.0, 0.34, 32.0, "plant", 0.0, Vector3(-0.05, 0.20, 0.48), Vector3(0.0, -0.45, 1.0), 0.10, 0.0],
		["landing hold", 0.0, 0.36, 34.0, "plant", 0.0, Vector3(-0.04, 0.14, 0.46), Vector3(0.0, -0.75, 1.0), 0.06, 0.5],
	]
	for k in keys:
		var r: Array = key(k[1], k[2], k[3], k[4], k[5], k[6], k[7])
		var head: Vector3 = B.wep_point(B.wep_len)
		print("%-24s wrist miss %.3f  aim off %4.0f deg  2nd hand %.3f  feet %.3f/%.3f  head (%.2f, %.2f, %.2f)  contacts %s" % [
			k[0], r[1][0], r[1][1], r[1][2], r[2], r[3], head.x, head.y, head.z, B.contacts()])
		S.cards.append({"name": k[0], "pose": r[0], "move": k[8], "hold": k[9], "lift": 0.05})
	S.cards.append({"name": "recover to guard", "pose": guard[0], "move": 0.30, "hold": 0.3, "lift": 0.05})
	var d := S.to_dict(B)
	d["note"] = "Leap slam proposal, long hammer (tools/leap_slam.gd), traced from docs/refs/POLEAXE_LEAP_SLAM.md"
	DirAccess.make_dir_recursive_absolute("res://scenes/_wip")
	FileAccess.open("res://scenes/_wip/leap_slam.json", FileAccess.WRITE).store_string(JSON.stringify(d, " "))
	print("LEAP SLAM %.2f s, %d keys, spins %s, bad frames %s" % [S.length(), S.cards.size(), S.spins(), d.get("bad_frames")])
	quit()
