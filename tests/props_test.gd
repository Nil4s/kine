## godot --headless --path . -s tests/props_test.gd     (GATES: starter props at real sizes)
## Real sizes are MEASURED on the built mesh (the MeshInstance3D boxes the app would show), not read from the data.
## Then the queries: depth into a solid, resting on a support, a turned prop, the dict round trip, snapping onto a prop.
extends SceneTree

const P = preload("res://scripts/props.gd")
var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func near(a: float, b: float, tol := 0.001) -> bool:
	return absf(a - b) <= tol


## every mesh box of a built prop as a world AABB (the prop at the origin, so its own frame)
func boxes(n: Node3D) -> Array:
	var out := []
	for c in n.get_children():
		var mi := c as MeshInstance3D
		out.append(mi.transform * mi.mesh.get_aabb())
	return out


func total(n: Node3D) -> AABB:
	var bs := boxes(n)
	var u: AABB = bs[0]
	for b in bs:
		u = u.merge(b)
	return u


## is there a mesh box whose top is at `top` (within 1 mm) and at least `w` wide and deep?
func has_top(n: Node3D, top: float, w: float) -> bool:
	for b in boxes(n):
		var bb: AABB = b
		if near(bb.end.y, top) and bb.size.x >= w and bb.size.z >= w:
			return true
	return false


func _init() -> void:
	var m := {}
	for k in P.KINDS:
		m[k] = P.mesh(P.make(k))
	# --- real sizes, from the built mesh
	var bx := total(m["box"])
	ok(near(bx.size.x, 0.4) and near(bx.size.y, 0.4) and near(bx.size.z, 0.4), "box is a 40 cm cube, mesh %s" % bx.size)
	var cr := total(m["crate"])
	ok(near(cr.size.x, 0.6) and near(cr.size.y, 0.5) and near(cr.size.z, 0.4), "crate 60 x 50 x 40 cm, mesh %s" % cr.size)
	var tb := total(m["table"])
	ok(near(tb.end.y, 0.75) and has_top(m["table"], 0.75, 0.6), "table top at 75 cm, mesh height %.4f" % tb.end.y)
	ok(has_top(m["chair"], 0.45, 0.4), "chair seat top at 45 cm, mesh")
	ok(near(total(m["chair"]).end.y, 0.9), "chair back to 90 cm, mesh %.4f" % total(m["chair"]).end.y)
	ok(has_top(m["stool"], 0.5, 0.3), "stool seat top at 50 cm, mesh")
	ok(has_top(m["bench"], 0.45, 0.3), "bench seat top at 45 cm, mesh")
	ok(near(total(m["step"]).size.y, 0.18), "step riser 18 cm, mesh %.4f" % total(m["step"]).size.y)
	var tops := []
	for b in boxes(m["stairs"]):
		tops.append(snappedf((b as AABB).end.y, 0.0001))
	tops.sort()
	var rise_ok := tops.size() == 5
	var rises := []
	for i in tops.size():
		var r: float = tops[i] - (tops[i - 1] if i > 0 else 0.0)
		rises.append(snappedf(r, 0.001))
		rise_ok = rise_ok and near(r, 0.18)
	ok(rise_ok, "stairs: 5 risers of 18 cm each, measured %s" % str(rises))
	var rp := total(m["ramp"])
	ok(near(rp.size.y, 0.5, 0.02) and near(rp.position.y, 0.0, 0.002) and rp.size.z > 1.8,
		"ramp about 50 cm high from the floor, over %.2f m, mesh %s" % [rp.size.z, rp.size])
	var wl := total(m["wall"])
	ok(near(wl.size.y, 2.4) and near(wl.size.x, 3.0), "wall 3 x 2.4 m, mesh %s" % wl.size)
	var df := total(m["door_frame"])
	var bs: Array = boxes(m["door_frame"])
	var gap: float = (bs[0] as AABB).position.x - (bs[1] as AABB).end.x   # inner face to inner face
	ok(near(df.size.y, 2.1) and near(gap, 0.9) and near((bs[2] as AABB).position.y, 2.0), "door frame 2.1 m high, opening %.3f m wide, 2.0 m under the lintel" % gap)
	ok(near(total(m["railing"]).end.y, 0.9), "railing handrail at 90 cm, mesh %.4f" % total(m["railing"]).end.y)
	ok(has_top(m["bed"], 0.5, 0.8) and near(total(m["bed"]).size.z, 2.05), "bed mattress top at 50 cm, %.2f m long" % total(m["bed"]).size.z)
	# every kind stands on the floor; every support matches a mesh top that covers it
	for k in P.KINDS:
		var p := P.make(k)
		var t := total(m[k])
		ok(near(t.position.y, 0.0, 0.002), "%s stands on the floor, lowest point %.4f" % [k, t.position.y])
		for sup in P.supports(p):
			var found := false
			for b in boxes(m[k]):
				var bb: AABB = b
				var c: Vector2 = sup["c"]
				var h: Vector2 = sup["half"]
				if near(bb.end.y, sup["y"]) and bb.position.x <= c.x - h.x + 0.001 and bb.end.x >= c.x + h.x - 0.001 \
						and bb.position.z <= c.y - h.y + 0.001 and bb.end.z >= c.y + h.y - 0.001:
					found = true
			ok(found, "%s support at %.2f m is a real mesh top" % [k, sup["y"]])
	# --- depth
	var table := P.make("table")
	var d_through := P.depth(table, Vector3(0, 0.5, 0), Vector3(0, 1.0, 0), 0.05)
	ok(d_through > 0.05, "capsule through the table top: depth %.4f" % d_through)
	var d_clear := P.depth(table, Vector3(0, 0.9, 0), Vector3(0, 1.4, 0), 0.05)
	ok(d_clear == 0.0, "capsule 10 cm over the table top: depth %.4f" % d_clear)
	var d_under := P.depth(table, Vector3(-0.3, 0.3, 0), Vector3(0.3, 0.3, 0), 0.05)
	ok(d_under == 0.0, "capsule under the table, between the legs: depth %.4f" % d_under)
	var d_leg := P.depth(table, Vector3(0.54, 0.3, 0.29), Vector3(0.54, 0.4, 0.29), 0.05)
	ok(d_leg > 0.05, "capsule on a table leg: depth %.4f" % d_leg)
	var d_edge := P.depth(table, Vector3(0, 0.74, 0), Vector3(0, 0.74, 0), 0.01)
	ok(near(d_edge, 0.01 + 0.01, 0.002), "a 1 cm ball centred 1 cm under the table top: depth %.4f (expect 0.020)" % d_edge)
	# --- resting on the chair seat
	var chair := P.make("chair")
	var r := 0.05
	var lie_a := Vector3(-0.1, 0.45 + 0.01 + r, 0.0)
	var lie_b := Vector3(0.1, 0.45 + 0.01 + r, 0.0)
	ok(P.rests(chair, lie_a, lie_b, r), "capsule 1 cm above the chair seat rests")
	ok(P.depth(chair, lie_a, lie_b, r) == 0.0, "...and is not inside it: depth %.4f" % P.depth(chair, lie_a, lie_b, r))
	ok(not P.rests(chair, lie_a + Vector3(0, 0.09, 0), lie_b + Vector3(0, 0.09, 0), r), "capsule 10 cm above the seat does not rest")
	ok(not P.rests(chair, lie_a - Vector3(0, 0.03, 0), lie_b - Vector3(0, 0.03, 0), r), "capsule 2 cm inside the seat does not rest (it is in it)")
	ok(P.depth(chair, lie_a - Vector3(0, 0.03, 0), lie_b - Vector3(0, 0.03, 0), r) > 0.02, "...depth %.4f" % P.depth(chair, lie_a - Vector3(0, 0.03, 0), lie_b - Vector3(0, 0.03, 0), r))
	ok(not P.rests(chair, lie_a + Vector3(1.0, 0, 0), lie_b + Vector3(1.0, 0, 0), r), "capsule 1 cm above the seat height but beside the chair does not rest")
	# --- a turned prop answers the same, in its own place
	var st := P.make("stairs", P.xf_at(Vector3(2.0, 0.0, -1.0), 90.0))
	var top4 := Vector3(2.0 + 0.56, 0.9 + 0.01 + r, -1.0)     # local +Z of the stairs points to world +X after yaw 90
	ok(P.rests(st, top4, top4 + Vector3(0, 0, 0.2), r), "yaw 90 stairs: capsule 1 cm over the 5th tread rests")
	ok(not P.rests(st, top4 + Vector3(0, 0.1, 0), top4 + Vector3(0, 0.1, 0.2), r), "yaw 90 stairs: 11 cm above the 5th tread does not rest")
	var wrong := Vector3(2.0, 0.9 + 0.01 + r, -1.0 + 0.56)    # where an unturned stairs would have its 5th tread
	ok(not P.rests(st, wrong, wrong + Vector3(0.2, 0, 0), r), "yaw 90 stairs: the unturned tread position holds nothing")
	var into := P.depth(st, Vector3(2.0 + 0.56, 0.7, -1.0), Vector3(2.0 + 0.56, 1.2, -1.0), r)
	ok(into > 0.05, "yaw 90 stairs: capsule through the 5th step: depth %.4f" % into)
	var low := P.xf_at(Vector3(0, 0.0, 0), 90.0)
	var t90 := P.make("table", low)
	ok(P.depth(t90, Vector3(0.0, 0.5, 0.5), Vector3(0.0, 1.0, 0.5), 0.05) > 0.05, "yaw 90 table: its 1.2 m length now runs along Z, capsule at z = 0.5 is in the top")
	ok(P.depth(t90, Vector3(0.5, 0.5, 0.0), Vector3(0.5, 1.0, 0.0), 0.05) == 0.0, "...and the same capsule at x = 0.5 misses it")
	# --- the dict round trip, through JSON text
	var list := [P.make("table", P.xf_at(Vector3(0.3, 0.0, -1.25), 37.5)), P.make("box", P.xf_at(Vector3(0, 0.75, 0), -90.0)),
		P.make("stairs", P.xf_at(Vector3(-2.1, 0.0, 0.7), 180.0))]
	var dl := []
	for p in list:
		dl.append(P.to_dict(p))
	var back = JSON.parse_string(JSON.stringify(dl))
	var same: bool = back is Array and back.size() == list.size()
	var worst := 0.0
	if same:
		for i in list.size():
			var q := P.from_dict(back[i])
			var xa: Transform3D = list[i]["xf"]
			var xb: Transform3D = q["xf"]
			same = same and q["kind"] == list[i]["kind"]
			worst = maxf(worst, maxf(xa.origin.distance_to(xb.origin), (xa.basis.x - xb.basis.x).length()))
	ok(same and worst < 1e-4, "to_dict -> JSON -> from_dict: 3 props equal, worst difference %.6f" % worst)
	# --- snapping onto each other
	var bxp := P.make("box", P.xf_at(Vector3(0.1, 0.0, 0.1)))
	ok(near(P.snap_y(bxp, [table]), 0.75, 1e-6), "box over the table snaps to %.3f (0.75)" % P.snap_y(bxp, [table]))
	ok(P.snap_y(P.make("box", P.xf_at(Vector3(2, 0, 2))), [table]) == 0.0, "box away from the table stays on the floor")
	ok(near(P.snap_y(P.make("box", P.xf_at(Vector3(0.0, 0.0, 0.0))), [table, P.make("box")]), 0.75, 1e-6), "over the table and a box: the higher one wins")
	ok(near(P.snap_y(P.make("box", P.xf_at(Vector3(2.0 + 0.56, 0, -1.0))), [st]), 0.9, 1e-6), "box over the 5th tread of the turned stairs: %.3f (0.90)" % P.snap_y(P.make("box", P.xf_at(Vector3(2.0 + 0.56, 0, -1.0))), [st]))
	ok(P.snap_y(P.make("box", P.xf_at(Vector3(5, 0, 5))), [P.make("wall")]) == 0.0, "a wall has no support: stays on the floor")
	for k in m:
		m[k].free()
	print("PROPS TEST %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
	quit(fails)
