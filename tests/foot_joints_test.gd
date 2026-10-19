## godot --headless --path . -s tests/foot_joints_test.gd     (ROADMAP item 7: better foot, the subtalar)
## THE FOOT TWIST = THE SUBTALAR ROLL. The twist of foot_l/r turns the sole about the subtalar axis (Inman 1969/1976), not
## about the foot's bone: an axis 42 deg up from the sole plane and 23 deg medial to the long axis (docs/research/FOOT_JOINTS.md).
## Bars:
##   1 the roll turns about that axis within 0.5 deg (angle and axis), and the axis is not the old bone axis
##   2 inversion stops at +25 and eversion at -8 (right foot; the left is the mirror), the ranges cited in FOOT_JOINTS.md
##   3 a positive roll on the right foot moves the heel medially (+X), and on the left foot laterally (+X): the mirror
##   4 compose then decompose gives the angles back (1e-3 deg), including a roll
##   5 every scene that never twists the foot plays bit for bit the same: sha256 of 60 frames (1/30 s steps) = the table
##     below, captured on the code before this change (scenes/*.json read only; bo_spin twists the foot and is reported only)
extends SceneTree

const LIMITS := "res://data/body_limits.json"
const SKEL := "res://data/skeleton.json"
const INCL := 42.0   # deg, the subtalar axis up from the sole plane (Inman 1976, as cited in docs/research/FOOT_JOINTS.md)
const DEV := 23.0    # deg, the subtalar axis medial to the foot's long axis (Inman 1969, as cited)
const INV_MAX := 25.0   # deg of roll on the right foot (positive = inversion, the sole turns medial); cited 20-30
const EV_MAX := 8.0     # deg of eversion; cited 5-10

## the sha256 of 60 frames for each scene that never twists the foot, captured on the code before the subtalar change
const GOLDEN := {
	"bo_sweep.json": "b59a1042b579ff3e9f1faaeea14504c61ae1f10f4109681ffbb193efc252e462",
	"combo3.json": "6a9cf84b56bb7b13559452d11e2f86f870ad2baa397186db71adb0e1f75eb5c5",
	"dodge_side.json": "d17889eea43dab7d16f1d51db4c00a4b22f18fe75e8134c7fbb8598aea66b6c0",
	"hit_react.json": "7bdb76210da9e7c91dd98a4863b4cbfd9bf3787375f10290a2394e77cf7184b0",
	"idle_bat.json": "a688135edef576f1c2ba66ec0063858d27d5753e868c0a5d0447f031cc7b8c41",
	"strike_legs.json": "231369294d6d55da390cff3bd2183ab779b8c0c7b858251452e7942285817de3",
	"swing_back.json": "b00e9916f76ed5b06880af561c002432b7b56d4c8601b0173a1f1c07f9b24a6c",
	"swing_fore.json": "911e7227184f1542c62112b46fbd534a7a3baacdc35a04026d52b3fff79a4d1d",
	"thrust.json": "6bd2a753dae9ee740eb7ec13ea29e2d6b6134cb126dd88954b1dfa553c40d20d",
	"walk_bat.json": "54f7edcf70241eecf4e3a114b6885ea1215ad1e1518fe3ec9538fde04b7cc031",   # re-baselined: the toe guard (f8a3023) moved ball_l/ball_r only; the subtalar change adds no difference (frames at 5dcebcf = HEAD)
}

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files(SKEL, LIMITS)
	B.fk()
	return B


## the subtalar axis in the rest character frame, from the angles above (right foot; medial = +X)
func expected_axis(B: Body, sd: String) -> Vector3:
	var t: Vector3 = B.t_ax["foot" + sd]
	var L := Vector3(t.x, 0.0, t.z).normalized()
	var M := Vector3(1, 0, 0) if sd == "_r" else Vector3(-1, 0, 0)
	var ci := cos(deg_to_rad(INCL))
	return (ci * cos(deg_to_rad(DEV)) * L + ci * sin(deg_to_rad(DEV)) * M + sin(deg_to_rad(INCL)) * Vector3.UP).normalized()


func scene_hash(name: String) -> String:
	var B := body()
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/" + name)))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for k in 60:
		S.apply(B, k / 30.0)
		var arr := PackedFloat64Array()
		for j in Body.ORDER:
			var p: Vector3 = B.P[j]
			var g: Quaternion = B.G[j]
			var a: Vector3 = B.ang[j]
			arr.append_array([p.x, p.y, p.z, g.x, g.y, g.z, g.w, a.x, a.y, a.z])
		ctx.update(arr.to_byte_array())
	return ctx.finish().hex_encode()


func _init() -> void:
	var B := body()
	var t: Vector3 = B.t_ax["foot_r"]
	var want := expected_axis(B, "_r")

	# 1 the roll about the subtalar axis
	var q: Quaternion = B.compose("foot_r", Vector3(0, 0, 10))
	var ax := q.get_axis()
	var ang_err := absf(rad_to_deg(q.get_angle()) - 10.0)
	var axis_err := rad_to_deg(acos(clampf(ax.dot(want), -1.0, 1.0)))
	print("AXIS: roll 10 deg -> turns about %s (subtalar %s), angle error %.4f deg, axis error %.4f deg" % [ax, want, ang_err, axis_err])
	ok(axis_err < 0.5 and ang_err < 0.5, "1 the sole roll turns 10 deg about the subtalar axis within 0.5 deg (axis %.3f deg off, angle %.3f deg off)" % [axis_err, ang_err])
	var elev := rad_to_deg(asin(clampf(ax.y, -1.0, 1.0)))
	var Lh := Vector3(t.x, 0, t.z).normalized()
	var dev := rad_to_deg(atan2(ax.x, ax.dot(Lh)))   # medial (+X on the right) against the long axis
	ok(absf(elev - INCL) < 0.5 and absf(dev - DEV) < 0.5, "1b the axis sits %.2f deg up (cited %.0f) and %.2f deg medial (cited %.0f) from the foot's long axis" % [elev, INCL, dev, DEV])
	ok(rad_to_deg(acos(clampf(ax.dot(t), -1.0, 1.0))) > 30.0, "1c the axis is not the old one (the foot's bone, %.1f deg away)" % rad_to_deg(acos(clampf(ax.dot(t), -1.0, 1.0))))
	B.set_ang("foot_r", Vector3(0, 0, 10))
	B.fk()
	var rel: Quaternion = B.G["foot_r"]
	ok(absf(rad_to_deg(rel.get_angle()) - 10.0) < 0.5 and rad_to_deg(acos(clampf(rel.get_axis().dot(want), -1.0, 1.0))) < 0.5,
		"1d in the world (calf at rest, FK): the same 10 deg about the same axis")

	# 2 inversion and eversion stop at the cited limits (right foot; left is mirrored)
	var lo := 0.0
	var hi := 0.0
	B.set_ang("foot_r", Vector3(0, 0, 60))
	hi = (B.ang["foot_r"] as Vector3).z
	B.set_ang("foot_r", Vector3(0, 0, -60))
	lo = (B.ang["foot_r"] as Vector3).z
	ok(absf(hi - INV_MAX) < 0.01 and absf(lo + EV_MAX) < 0.01, "2 right foot: roll clamps to +%.0f (inversion) and %.0f (eversion), got %.2f / %.2f" % [INV_MAX, -EV_MAX, hi, lo])
	B.set_ang("foot_l", Vector3(0, 0, 60))
	var hl := (B.ang["foot_l"] as Vector3).z
	B.set_ang("foot_l", Vector3(0, 0, -60))
	var ll := (B.ang["foot_l"] as Vector3).z
	ok(absf(hl - EV_MAX) < 0.01 and absf(ll + INV_MAX) < 0.01, "2b left foot is the mirror: +%.0f eversion, %.0f inversion, got %.2f / %.2f" % [EV_MAX, -INV_MAX, hl, ll])

	# 3 the direction: the heel moves medially on inversion (positive on the right, negative on the left)
	var Br := body()
	var hr0 := FootRoll.heel_point(Br, "_r")
	Br.set_ang("foot_r", Vector3(0, 0, 15))
	Br.fk()
	var hr1 := FootRoll.heel_point(Br, "_r")
	var Bl := body()
	var hl0 := FootRoll.heel_point(Bl, "_l")
	Bl.set_ang("foot_l", Vector3(0, 0, 15))
	Bl.fk()
	var hl1 := FootRoll.heel_point(Bl, "_l")
	ok(hr1.x > hr0.x + 0.001, "3 right foot, inversion (+15): the heel moves medially (+X) by %.1f mm" % ((hr1.x - hr0.x) * 1000.0))
	ok(hl1.x > hl0.x + 0.001, "3b left foot, +15 (eversion, the mirror of the right's inversion): the heel moves laterally (+X) by %.1f mm" % ((hl1.x - hl0.x) * 1000.0))

	# 4 compose then decompose gives the angles back
	var worst := 0.0
	for v in [Vector3(10, 5, -6), Vector3(-20, 8, 20), Vector3(0, -7, 25), Vector3(15, 0, -8), Vector3(-45, 25, 3)]:
		var qq: Quaternion = B.compose("foot_r", v)
		var back: Vector3 = B.decompose("foot_r", qq)
		worst = maxf(worst, (back - v).length())
	print("ROUND TRIP: worst compose -> decompose error %.6f deg over 5 foot angles" % worst)
	ok(worst < 1e-3, "4 compose -> decompose returns the bend, side and roll (worst %.6f deg)" % worst)

	# 5 the scenes that never twist the foot play the same, bit for bit
	var files := []
	for f in DirAccess.get_files_at("res://scenes"):
		if f.ends_with(".json"):
			files.append(f)
	files.sort()
	var n_same := 0
	var skipped := []
	for g in GOLDEN:
		if not files.has(g):
			skipped.append(g)
	if not skipped.is_empty():
		print("     golden scenes not on disk (skipped): %s" % ", ".join(skipped))
	for f in files:
		var h := scene_hash(f)
		print("HASH %s %s" % [f, h])
		if GOLDEN.has(f):
			ok(h == GOLDEN[f], "5 %s: 60 frames bit-identical to before (sha256 %s)" % [f, h.substr(0, 12)])
			n_same += 1
	print("     bo_spin twists the foot (-12 deg); it is reported, not held to the old result")
	ok(n_same >= 9 and n_same + skipped.size() == GOLDEN.size(), "5b the golden scenes present all hashed: %d of %d (%d skipped; bar: at least 9)" % [n_same, GOLDEN.size(), skipped.size()])

	print("FOOT JOINTS: %d FAIL" % fails)
	quit(1 if fails > 0 else 0)
