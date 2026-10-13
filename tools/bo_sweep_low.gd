extends SceneTree
## LOW SWEEP with the staff (Nick 10-13: "an undertaker move when the char kind of crouches and sweeps the bo at the
## opponent's legs, making them fall"). The traditional shin strike (sune uchi / ashi barai): drop into a deep wide
## stance, the hips coil to the right with the staff low behind, then the HIPS pivot left and carry the staff level at
## shin height through the opponent's legs, follow through to the left, rise to the guard. Nick's guard grip is kept
## (no regrip mid-move): the staff turns about the hands like a lever, the RIGHT-hand end (0.9 m past the right hand)
## drops to the floor and is the striking end, the far end rises behind the left shoulder; the right hand pushes the
## low end through while the left pulls the high end back.
## Feet: one step out into the wide stance, then both stay planted while the hips turn (the knees follow the feet).
## Target: the tip passes the opponent's shins (~0.15-0.30 m high) at 1.2-1.7 m in front at the CONTACT key.
##   godot --headless --path . -s tools/bo_sweep_low.gd        -> scenes/bo_sweep_low.json
const LEGS := ["thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]
const L_AT := Vector3(0.30, 0.0, 0.26)    # the wide stance: the left (lead) toe base forward-left
const R_AT := Vector3(-0.33, 0.0, -0.14)  # the right toe base back-right
const L_HEAD := 0.35                      # where the feet point (rad about up, 0 = forward)
const R_HEAD := -0.25

var B: Body
var start: Dictionary
var staff2: Dictionary
var g2: Dictionary


func _v(x: Dictionary) -> Vector3:
	return Vector3(x["bend"], x["side"], x["twist"])


## a low key: hips turned `turn` deg (+ = to his left) and dropped `drop` m, chest leaning `lean` deg forward, both feet
## planted on the wide stance, the right hand at `at` (from the hips, in the hips' facing), the striking (butt) end
## pointing `low_dir` from the hands (in the world)
func low(turn: float, drop: float, lean: float, at: Vector3, low_dir: Vector3, lane: float) -> Array:
	B.from_dict(start)
	var pv: Vector3 = B.ang["pelvis"]
	B.ang["pelvis"] = Vector3(pv.x, pv.y, turn)
	B.ang["spine_01"] = B.clamp_ang("spine_01", Vector3(lean * 0.5, 0, 0))
	B.ang["spine_02"] = B.clamp_ang("spine_02", Vector3(lean * 0.5, 0, 0))
	B.offset.y -= drop
	B.fk()
	var mL := B.plant("_l", Vector3(L_AT.x, (B.p0["ball_l"] as Vector3).y, L_AT.z), L_HEAD, true)
	var mR := B.plant("_r", Vector3(R_AT.x, (B.p0["ball_r"] as Vector3).y, R_AT.z), R_HEAD, true)
	B.grip2 = g2
	B.grip = true
	var R := Basis(Vector3.UP, deg_to_rad(turn))
	var r: Array = B.hold_bat((B.P["pelvis"] as Vector3) + R * at, -low_dir, true, true, lane, 30.0)
	return [B.to_dict(), r, mL, mR]


func _init() -> void:
	B = Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	staff2 = JSON.parse_string(FileAccess.get_file_as_string("res://data/grips/staff.json"))["second"]
	# START: Nick's two-hand guard (bo_guard) on standing legs (his guard stands on one leg, a crane), both hands on
	var gd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://moves/bo_guard.json"))
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
	var S := Scene.new()
	S.name = "bo_sweep_low"
	S.cards.append({"name": "guard", "pose": start, "move": 0.0, "hold": 0.2})
	# the keys: [name, hip turn, drop, lean, right hand from the hips, low end's direction, move s, hold s]
	var keys := [
		["DROP + COIL", -35.0, 0.30, 14.0, Vector3(-0.28, 0.12, 0.15), Vector3(-0.6, -0.45, -0.5), 0.26, 0.05],
		["SWEEP (shins)", 5.0, 0.32, 20.0, Vector3(-0.18, 0.05, 0.35), Vector3(0.1, -0.38, 1.0), 0.13, 0.0],
		["follow through", 40.0, 0.30, 16.0, Vector3(-0.02, 0.06, 0.35), Vector3(0.9, -0.35, 0.35), 0.15, 0.12],
	]
	for k in keys:
		var r: Array = low(k[1], k[2], k[3], k[4], k[5], lane)
		lane = (B.ang["hand_r"] as Vector3).z
		var tip: Vector3 = B.wep_point(0.0)   # the striking end = the butt
		print("%-16s hand miss %.3f  staff off %.0f deg  2nd hand %.3f  feet miss %.3f/%.3f  tip (%.2f, %.2f, %.2f)  contacts %s" % [
			k[0], r[1][0], r[1][1], r[1][2], r[2], r[3], tip.x, tip.y, tip.z, B.contacts()])
		S.cards.append({"name": k[0], "pose": r[0], "move": k[6], "hold": k[7], "lift": 0.05})
	S.cards.append({"name": "rise to guard", "pose": start, "move": 0.36, "hold": 0.3, "lift": 0.05})
	var d := S.to_dict(B)
	d["note"] = "Low staff sweep at the shins (tools/bo_sweep_low.gd): drop + coil, hips pivot the staff through, rise"
	FileAccess.open("res://scenes/bo_sweep_low.json", FileAccess.WRITE).store_string(JSON.stringify(d, " "))
	print("BO SWEEP LOW %.2f s, %d keys, spins %s" % [S.length(), S.cards.size(), S.spins()])
	quit()
