## godot --headless --path . -s tests/stand_set_test.gd     (GATES TT2; headless is fine)
## STANDING ON THE SET, by numbers. A box under both feet: the soles on its top (40 cm). A box under one foot: that
## foot on the top, the other above the floor, neither sinks. Feet under a table: on the floor, the body exactly where
## it stands with no props. A set 10 m away: the same numbers as no set at all. Seated (thighs level, shins down) over
## a chair: the hips and thighs sit ON the seat (not in it); a foot on the box counts as "on the ground" (foot_state).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


## the lowest sole point above the world floor, per side
func sole(B: Body, sd: String) -> float:
	return minf((B.P["ball" + sd] as Vector3).y - (B.p0["ball" + sd] as Vector3).y, (B.P["foot" + sd] as Vector3).y - (B.p0["foot" + sd] as Vector3).y)


func at(kind: String, x: float, z: float, yaw := 0.0) -> Dictionary:
	return Props.make(kind, Props.xf_at(Vector3(x, 0, z), yaw))


func _init() -> void:
	var B0 := body()
	B0.ground()
	var y0 := B0.offset.y
	# a set far away: the floor path
	var B := body()
	B.props = [at("box", 10, 10), at("table", -10, 4)]
	B.ground()
	ok(B.offset.y == y0 and B.P == B0.P, "a set 10 m away: the same body as no set (offset.y %.6f vs %.6f)" % [B.offset.y, y0])
	# both feet on a box (40 cm cube centred between the feet, a little forward: the balls and heels both over it)
	B = body()
	var mid := ((B.P["ball_l"] as Vector3) + (B.P["ball_r"] as Vector3) + (B.P["foot_l"] as Vector3) + (B.P["foot_r"] as Vector3)) / 4.0
	B.props = [at("box", mid.x, mid.z)]
	B.ground()
	ok(absf(sole(B, "_l") - 0.40) < 0.005 and absf(sole(B, "_r") - 0.40) < 0.005, "both feet over a box: the soles on its top (%.3f, %.3f m; top 0.40)" % [sole(B, "_l"), sole(B, "_r")])
	ok(B.foot_state("_l")[2] and B.foot_state("_r")[2], "  and both count as on the ground (foot_state)")
	# one foot on a box (box outside the left foot: its inner edge between the feet)
	B = body()
	var bl: Vector3 = ((B.P["ball_l"] as Vector3) + (B.P["foot_l"] as Vector3)) / 2.0
	B.props = [at("box", bl.x + 0.12, bl.z)]
	B.ground()
	ok(absf(sole(B, "_l") - 0.40) < 0.005 and sole(B, "_r") > 0.30, "one foot over the box: it stands on the top (%.3f m), the other is above the floor (%.3f m), neither sinks" % [sole(B, "_l"), sole(B, "_r")])
	ok(B.foot_state("_l")[2] and not B.foot_state("_r")[2], "  the foot on the box is on the ground, the hanging one is not")
	# under a table
	B = body()
	B.props = [at("table", mid.x, mid.z)]
	B.ground()
	ok(is_equal_approx(B.offset.y, y0) and sole(B, "_l") < 0.001, "feet under a table: on the floor, where they stand with no set (offset.y %.4f vs %.4f)" % [B.offset.y, y0])
	# toes touching the face of a 1 m stack (two crates): the body stays on the floor (round 39: it was lifted onto it)
	B = body()
	var toe: float = maxf((B.E["ball_l"] as Vector3).z, (B.E["ball_r"] as Vector3).z)
	B.props = [at("crate", 0.0, toe + 0.2 - 0.02), Props.make("crate", Props.xf_at(Vector3(0, 0.5, toe + 0.2 - 0.02), 0.0))]
	B.ground()
	ok(is_equal_approx(B.offset.y, y0), "toes 2 cm into the face of a 1 m crate stack: the body stays on the floor (offset.y %.4f vs %.4f)" % [B.offset.y, y0])
	# seated over a chair: the hips on the seat, not in it
	for kind in ["chair", "stool"]:
		B = body()
		for sd in ["_l", "_r"]:
			B.set_ang("thigh" + sd, Vector3(90, 0, 0))
			B.set_ang("calf" + sd, Vector3(90, 0, 0))
		B.fk()
		B.props = [at(kind, 0.0, 0.03)]
		B.ground()
		var top: float = Props.supports(B.props[0])[0]["y"]
		var deep := 0.0
		var lo := INF
		for part in Body.SEAT_PARTS:
			var c := B.cap(part)
			deep = maxf(deep, Props.depth(B.props[0], c[0], c[1], B.rad[part]))
			lo = minf(lo, minf((c[0] as Vector3).y, (c[1] as Vector3).y) - float(B.rad[part]))
		ok(deep < Props.REST_SINK and absf(lo - top) < 0.01 and minf(sole(B, "_l"), sole(B, "_r")) > -0.001,
			"seated over a %s: the hips and thighs on the seat (lowest %.3f m, seat %.2f, %.1f mm in), the feet not in the floor (%.3f m)" % [kind, lo, top, deep * 1000.0, minf(sole(B, "_l"), sole(B, "_r"))])
	# a card run standing on the box: the feet stay planted on its top while the arms move
	B = body()
	var S := Scene.new()
	S.props = [at("box", mid.x, mid.z)]
	B.props = S.props
	B.ground()
	var fa := B.foot_state("_r")   # card a's right foot: card b keeps it there (a planted foot, as the app's cards do)
	S.add("a", B.to_dict())
	B.set_ang("upperarm_r", Vector3(60, 30, 0))
	B.set_ang("spine_02", Vector3(10, 0, 8))
	B.set_ang("thigh_l", Vector3(15, 0, 0))
	B.set_ang("calf_l", Vector3(25, 0, 0))
	B.set_ang("pelvis", Vector3(0, 0, 20))   # the hips turn and shift: an unpinned right foot would swing with them
	B.offset.x += 0.05
	B.fk()
	B.ground()
	B.plant("_r", fa[0], fa[1], true)
	var miss: float = ((B.P["ball_r"] as Vector3) - (fa[0] as Vector3)).length()
	S.add("b", B.to_dict())
	S.add("c", body().to_dict())
	S.apply(B, 0.0)
	var b0: Vector3 = B.P["ball_r"]
	var far := 0.0
	var low := INF
	var t := 0.0
	while t <= S.length():
		S.apply(B, t)
		var d: Vector3 = (B.P["ball_r"] as Vector3) - b0
		far = maxf(far, Vector2(d.x, d.z).length())
		low = minf(low, minf(sole(B, "_l"), sole(B, "_r")))
		t += 1.0 / 30.0
	ok(miss < 0.005 and far < 0.01 and low > 0.395, "three cards on the box, the hips turning 20 deg over a planted right foot (card b re-planted %.1f mm off): it slides %.1f mm between the cards, no sole below the top (lowest %.3f m)" % [miss * 1000.0, far * 1000.0, low])
	print("STAND SET TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	TestFiles.cleanup()
	quit(fails)
