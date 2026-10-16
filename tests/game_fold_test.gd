## godot --headless --path . -s tests/game_fold_test.gd     (GATES LL1, UPGRADES_200 #102, #105)
## THE FOLD ONTO THE GAME'S SLOTS. (0) The game's composition and its inverse agree (random angles, 0.01 degrees).
## (1) Poser's rest: the spine, head and legs export 0 (under 1 degree), the arms raised ~90 degrees (Poser's rest holds
## them out, the game's hang down), the forearms near straight. (2) The game's bones rebuilt from the exported angles
## ALONE (the game's composition, the game's rest directions: the arms DOWN, written here, not taken from the exporter)
## point where Poser's limbs point, within 0.5 degrees, on every card of 3 scenes. (3) SIGN CONTROLS, each read off the
## body, not off the maths: the left thigh turned so the knee goes toward the toes -> ThighL +pitch; the hips turned so
## the left hip goes back -> Hips +yaw; the chest turned so the right shoulder goes down -> Chest +roll; the other two
## angles under 1 degree each time.
extends SceneTree

var fails := 0
var m: Node
## the game's slots by MEANING, written here and not read from the exporter (a map the test borrows cannot catch a
## wrong map): the bone each slot moves, as Poser names the limb it points along
const LIMB := {"Hips": "pelvis", "Chest": "spine_03", "Head": "head", "ArmL": "upperarm_l", "ArmR": "upperarm_r",
	"ForeL": "lowerarm_l", "ForeR": "lowerarm_r", "ThighL": "thigh_l", "ThighR": "thigh_r", "ShinL": "calf_l", "ShinR": "calf_r"}
var B: Body


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func rest() -> void:
	for j in B.ang:
		B.ang[j] = Vector3.ZERO
	B.offset = Vector3.ZERO
	B.fk()


func load_scene(n: String) -> Scene:
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/%s.json" % n)))
	return S


## the game's rest direction of each slot's bone: the arms hang DOWN (SKELETON.md); spine, head and legs stand as Poser's
func game_rest_dir(s: String) -> Vector3:
	if s in ["ArmL", "ArmR", "ForeL", "ForeR"]:
		return Vector3.DOWN
	var j: String = LIMB[s]
	return (B.e0[j] - B.p0[j]).normalized()


## worst angle (degrees) between the rebuilt game bone and Poser's limb, over the slots; and which slot
func rebuild_gap() -> Array:
	var a := GameExport.slot_angles(B)
	var W := {}
	var worst := 0.0
	var at := ""
	if GameExport.ORDER.size() != LIMB.size():
		return [999.0, "slot count %d" % GameExport.ORDER.size()]
	for s in GameExport.ORDER:
		var p: String = GameExport.SLOTS[s][2]
		W[s] = (W[p] if p != "" else Quaternion.IDENTITY) * GameExport.compose(a[s])
		var j: String = LIMB[s]
		var want: Vector3 = (B.E[j] - B.P[j]).normalized()
		var got: Vector3 = (W[s] as Quaternion) * game_rest_dir(s)
		var g := rad_to_deg(want.angle_to(got))
		if g > worst:
			worst = g
			at = s
	return [worst, at]


func _init() -> void:
	m = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	B = m.B
	# (0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var w0 := 0.0
	for i in 200:
		var v := Vector3(rng.randf_range(-170, 170), rng.randf_range(-85, 85), rng.randf_range(-170, 170))
		var back := GameExport.decompose(GameExport.compose(v))
		w0 = maxf(w0, (back - v).abs()[(back - v).abs().max_axis_index()])
	ok(w0 < 0.01, "0 compose -> decompose over 200 random angles: worst %.5f degrees" % w0)
	# (1)
	rest()
	var a := GameExport.slot_angles(B)
	var still := 0.0
	for s in ["Hips", "Chest", "Head", "ThighL", "ThighR", "ShinL", "ShinR"]:
		var v: Vector3 = (a[s] as Vector3).abs()
		still = maxf(still, v[v.max_axis_index()])
	var up_l := GameExport.gap(GameExport.compose(a["ArmL"]), Quaternion.IDENTITY)
	var up_r := GameExport.gap(GameExport.compose(a["ArmR"]), Quaternion.IDENTITY)
	var fore := maxf(GameExport.gap(GameExport.compose(a["ForeL"]), Quaternion.IDENTITY), GameExport.gap(GameExport.compose(a["ForeR"]), Quaternion.IDENTITY))
	ok(still < 1.0 and absf(up_l - 90.0) < 10.0 and absf(up_r - 90.0) < 10.0 and fore < 10.0,
		"1 Poser's rest: spine/head/legs worst %.3f degrees; arms raised %.1f / %.1f (ArmL %s, ArmR %s); forearms %.1f" % [still, up_l, up_r, a["ArmL"], a["ArmR"], fore])
	# (2)
	var worst := 0.0
	var where := ""
	var n := 0
	for sn in ["combo3", "swing_fore", "walk_bat"]:
		var S := load_scene(sn)
		var ts := S.times()
		for i in S.cards.size():
			S.apply(B, float(ts[i][1]))
			var r := rebuild_gap()
			n += 1
			if r[0] > worst:
				worst = r[0]
				where = "%s card %d %s" % [sn, i, r[1]]
	ok(n >= 6 and worst < 0.5, "2 the game's bones rebuilt from the angles alone vs Poser's limbs: worst %.4f degrees over %d cards (%s)" % [worst, n, where])
	# (3) sign controls
	rest()
	var knee0: Vector3 = B.P["calf_l"]
	B.turn_world("thigh_l", Quaternion(Vector3(-1, 0, 0), deg_to_rad(30)))
	var fwd: bool = B.P["calf_l"].z > knee0.z + 0.1
	var t3: Vector3 = GameExport.slot_angles(B)["ThighL"]
	ok(fwd and t3.x > 20.0 and absf(t3.y) < 1.0 and absf(t3.z) < 1.0, "3a the knee toward the toes (%s): ThighL %s (+pitch)" % [fwd, t3])
	rest()
	var hip0: Vector3 = B.P["thigh_l"]
	B.turn_world("pelvis", Quaternion(Vector3.UP, deg_to_rad(20)))
	var back: bool = B.P["thigh_l"].z < hip0.z - 0.02
	var h3: Vector3 = GameExport.slot_angles(B)["Hips"]
	ok(back and h3.y > 15.0 and absf(h3.x) < 1.0 and absf(h3.z) < 1.0, "3b the left hip back, the body turned to its left (%s): Hips %s (+yaw)" % [back, h3])
	rest()
	var sh0: Vector3 = B.P["upperarm_r"]
	B.turn_world("spine_03", Quaternion(Vector3(0, 0, 1), deg_to_rad(8)))
	var down: bool = B.P["upperarm_r"].y < sh0.y - 0.01
	var c3: Vector3 = GameExport.slot_angles(B)["Chest"]
	ok(down and c3.z > 5.0 and absf(c3.x) < 1.0 and absf(c3.y) < 1.0, "3c the right shoulder down (%s): Chest %s (+roll)" % [down, c3])
	print("GAME FOLD: %d failed" % fails)
	quit(1 if fails > 0 else 0)
