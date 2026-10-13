extends SceneTree
## NICK'S RIGHT SWING, WITH THE SPIN HE WANTED (Nick 10-13: "I did one scene but you can improve, it's the right swing,
## I wanted it to spin to do it but I wasn't that capable"). From scenes/bo_swing_test.json (his 5 keys, kept as he
## posed them): his wind-up (keys 1-4, faster), then ONE FULL TURN of the body to the left in three thirds while the
## arm opens out from his load (key 4) to his strike (key 5), so the staff whirls at its full length and lands on his
## key 5; then the left hand, which only followed, catches the shaft (his fitted staff grip). Feet: the right foot
## pivots on its ball in place (the body is shifted so it stays put), the left steps round it each third.
##   godot --headless --path . -s tools/bo_spin.gd        -> scenes/bo_spin.json (his file is not touched)
const SRC := "res://scenes/_archive/bo_swing_test.json"
const RARM := ["clavicle_r", "upperarm_r", "lowerarm_r", "hand_r", "spine_01", "spine_02", "spine_03", "neck_01", "head"]

var B: Body


func _v(x: Dictionary) -> Vector3:
	return Vector3(x["bend"], x["side"], x["twist"])


## a pose dict with some joints replaced, the hips turned to `turn`, the body shifted so the right foot's ball is at
## `pivot` (null = where it falls)
func make(base: Dictionary, set: Dictionary, turn: float, pivot) -> Dictionary:
	B.from_dict(base)
	for j in set:
		B.ang[j] = B.clamp_ang(j, set[j])
	var pv: Vector3 = B.ang["pelvis"]
	B.ang["pelvis"] = Vector3(pv.x, pv.y, wrapf(turn, -180.0, 180.0))
	B.fk()
	B.ground()
	if pivot != null:
		var now: Vector3 = B.foot_state("_r")[0]
		var d: Vector3 = (pivot as Vector3) - now
		B.offset += Vector3(d.x, 0, d.z)
		B.fk()
		B.ground()
	return B.to_dict()


func feet(d: Dictionary) -> Dictionary:
	B.from_dict(d)
	B.ground()
	return {"_l": B.foot_state("_l"), "_r": B.foot_state("_r")}


func _init() -> void:
	B = Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var src: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SRC))
	var N := []
	for c in src["cards"]:
		N.append(c["pose"])
	var S := Scene.new()
	S.name = "bo_spin"
	# his wind-up, timed: start, then load low -> high (slower), a breath at the top
	# his key 1's upper-arm roll brought within 40 deg of key 2's (it rolled +70 between them: a spin; Nick 10-13
	# "they were just tests, all good to update")
	var r1: float = _v(N[1]["joints"]["upperarm_r"]).z
	var u0: Vector3 = _v(N[0]["joints"]["upperarm_r"])
	var k1 := make(N[0], {"upperarm_r": Vector3(u0.x, u0.y, clampf(u0.z, r1 - 40.0, r1 + 40.0))}, _v(N[0]["joints"]["pelvis"]).z, null)
	S.cards.append({"name": "start (Nick 1)", "pose": k1, "move": 0.0, "hold": 0.15})
	S.cards.append({"name": "wind (Nick 2)", "pose": N[1], "move": 0.32, "hold": 0.0})
	S.cards.append({"name": "rise (Nick 3)", "pose": N[2], "move": 0.30, "hold": 0.0})
	S.cards.append({"name": "LOAD (Nick 4)", "pose": N[3], "move": 0.30, "hold": 0.06})
	var a4: Dictionary = N[3]["joints"]
	var a5: Dictionary = N[4]["joints"]
	var t4: float = _v(a4["pelvis"]).z
	var t5: float = _v(a5["pelvis"]).z
	var pivot: Vector3 = feet(N[3])["_r"][0]
	var prev := feet(N[3])
	var lane: float = _v(a4["hand_r"]).z   # the forearm's turn travels from his load, <= 40 deg a key (spin rule 45)
	# the spin: the hips turn +120 per third (to his left); the arm and chest open from his load to his strike
	for k in [[1, 0.4, 0.20], [2, 0.8, 0.18]]:
		var set := {}
		for j in RARM:
			set[j] = _v(a4.get(j, {"bend": 0, "side": 0, "twist": 0})).lerp(_v(a5.get(j, {"bend": 0, "side": 0, "twist": 0})), k[1])
		var d := make(N[3], set, t4 + 120.0 * k[0], pivot)
		# LEVEL + WIDE (Nick: "this swing you're not damaging a leaf ... let the bo go to its edge on the hand"): the hand out at
		# the staff's end, the arm out at shoulder height on his right, the staff trailing level behind the turn
		B.from_dict(d)
		B.grip = false
		B.slide_in_hand(0.10 - B.hold_u())
		var R := Basis(Vector3.UP, deg_to_rad(t4 + 120.0 * k[0]))
		var ch: Vector3 = B.P["spine_03"]
		# the forearm's turn walks from his load's toward his strike's, a third per key (no spin into the strike)
		lane = lerpf(_v(a4["hand_r"]).z, _v(a5["hand_r"]).z, k[0] / 3.0)
		var r: Array = B.hold_bat(ch + R * Vector3(-0.50, 0.0, 0.22), R * Vector3(-0.85, -0.03, -0.5).normalized(), true, true, lane, 20.0)
		lane = (B.ang["hand_r"] as Vector3).z
		print("spin %d/3: wrist miss %.3f m, staff aim off %.0f deg, contacts %d" % [k[0], r[0], r[1], B.contacts().size()])
		d = B.to_dict()
		var now := feet(d)
		var stl: Vector3 = (now["_l"][0] as Vector3) - (prev["_l"][0] as Vector3)
		S.cards.append({"name": "SPIN %d/3" % k[0], "pose": d, "move": k[2], "hold": 0.0, "lift": 0.04,
			"steps": {"_l": [stl.x, 0.0, stl.z], "_r": [0.0, 0.0, 0.0]}})
		prev = now
	# the strike lands on his key 5, the turn completed (t5 + 360 = t5), the right foot still on its pivot
	var d5 := make(N[4], {}, t5, pivot)
	var n5 := feet(d5)
	var st5: Vector3 = (n5["_l"][0] as Vector3) - (prev["_l"][0] as Vector3)
	S.cards.append({"name": "STRIKE (Nick 5)", "pose": d5, "move": 0.16, "hold": 0.08, "lift": 0.04,
		"steps": {"_l": [st5.x, 0.0, st5.z], "_r": [0.0, 0.0, 0.0]}})
	# the catch: the right arm draws the staff halfway back toward Nick's two-hand guard and the left hand, which only
	# followed, takes the shaft with his fitted staff grip
	var gd: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://moves/bo_guard.json"))["joints"]
	var draw := {}
	for j in ["clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]:
		draw[j] = _v(a5[j]).lerp(_v(gd[j]), 0.5)
	d5 = make(d5, draw, t5, pivot)
	var g: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/grips/staff.json"))
	# the spin rule for the catching arm: its roll + forearm turn stay within 40 deg of how it followed
	var keep_lim := {}
	for j in ["upperarm_l", "hand_l"]:
		keep_lim[j] = B.lim[j].duplicate()
		var tw: float = (B.ang[j] as Vector3).z
		B.lim[j]["twist"] = Vector2(maxf(keep_lim[j]["twist"].x, tw - 40.0), minf(keep_lim[j]["twist"].y, tw + 40.0))
	if g.has("second") and B.wep_hand == "hand_r":
		B.grip2 = g["second"]
		B.grip = true
		# the closest spot on the shaft the left hand can take from where it followed (every 10 cm along it)
		var best := INF
		var best_u := 0.0
		var u := 0.15
		while u < B.wep_len - 0.1:
			B.from_dict(d5)
			B.grip2 = g["second"]
			B.grip = true
			B.grip_u = u
			var m: float = B.apply_grip()
			var bad := B.contacts().size()
			if m + 0.05 * bad < best and absf(u - B.hold_u()) > 0.25:
				best = m + 0.05 * bad
				best_u = u
			u += 0.1
		B.from_dict(d5)
		B.grip2 = g["second"]
		B.grip = true
		B.grip_u = best_u
		var miss: float = B.apply_grip()
		print("catch: left wrist miss %.3f m at %.2f m up the shaft, contacts %s" % [miss, B.grip_u, B.contacts()])
		if miss < 0.03:
			S.cards.append({"name": "CATCH (two hands)", "pose": B.to_dict(), "move": 0.28, "hold": 0.4})
	var d := S.to_dict(B)
	d["note"] = "Nick's right swing (bo_swing_test) with a full spin + the left-hand catch (tools/bo_spin.gd)"
	FileAccess.open("res://scenes/bo_spin.json", FileAccess.WRITE).store_string(JSON.stringify(d, " "))
	print("BO SPIN %.2f s, %d keys, spins %s" % [S.length(), S.cards.size(), S.spins()])
	quit()
