## godot --headless --path . -s tests/groundspeed_test.gd     (GROUNDSPEED: Body.ground() cost with props near the body)
## BARS (written before the change, after the sanity run):
##   1 EQUAL: 300 random poses near each prop (chair, bench, table, box; seeded RNG), each grounded by the legacy path
##     (Body.legacy_ground = true) and by the new path: Body.offset and every joint's G / P / E equal within 1e-6.
##     ANTI-VACUITY: ground() moves the body in a good share of the poses (offset.y changes by more than 0.1 mm).
##   2 SPEED: legacy and new alternated in one process, 5 rounds x 300 ground() calls with a chair beside the body:
##     the median of the 5 ratios new/legacy is at most 0.6.
extends SceneTree

var fails := 0
const EPS := 1e-6


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func body() -> Body:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.fk()
	return B


func joints_leg() -> Array:
	var out := []
	for j in Body.ORDER:
		if j.contains("thigh") or j.contains("calf") or j.contains("foot") or j.contains("pelvis") or j.contains("spine"):
			out.append(j)
	return out


## the same random pose and offset on a body: a prop at the origin, the body placed around it
func pose(B: Body, rng: RandomNumberGenerator, prop_kind: String, yaw: float, x: float, z: float, lift: float, angs: Dictionary) -> void:
	for j in angs:
		B.set_ang(j, angs[j])
	B.offset = Vector3(x, lift, z)
	B.fk()


func differs(a, b) -> bool:
	if typeof(a) == TYPE_VECTOR3:
		return (a as Vector3).distance_to(b as Vector3) > EPS
	if typeof(a) == TYPE_QUATERNION:
		return absf(absf((a as Quaternion).dot(b as Quaternion)) - 1.0) > EPS
	return a != b


func same(A: Body, B: Body) -> String:
	if A.offset.distance_to(B.offset) > EPS:
		return "offset %s vs %s" % [A.offset, B.offset]
	for nm in ["G", "P", "E"]:
		var da: Dictionary = A.get(nm)
		var db: Dictionary = B.get(nm)
		for j in Body.ORDER:
			if not da.has(j) or not db.has(j) or differs(da[j], db[j]):
				return "%s[%s] differs or missing" % [nm, j]
	return ""


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260
	var jl := joints_leg()
	# 1 EQUAL
	var moved := 0
	var total := 0
	var bad := ""
	var A := body()
	var B := body()
	for kind in ["chair", "bench", "table", "box"]:
		for i in 300:
			var yaw := rng.randf_range(0.0, 360.0)
			var prop := Props.make(kind, Props.xf_at(Vector3.ZERO, yaw))
			var angs := {}
			for j in jl:
				angs[j] = Vector3(rng.randf_range(-40.0, 40.0), rng.randf_range(-10.0, 10.0), rng.randf_range(-10.0, 10.0))
			var x := rng.randf_range(-0.7, 0.7)
			var z := rng.randf_range(-0.7, 0.7)
			var lift := rng.randf_range(0.0, 0.3)
			A.props = [prop]
			B.props = [prop]
			pose(A, rng, kind, yaw, x, z, lift, angs)
			pose(B, rng, kind, yaw, x, z, lift, angs)
			var y0 := A.offset.y
			Body.legacy_ground = true
			A.ground()
			Body.legacy_ground = false
			B.ground()
			total += 1
			if absf(A.offset.y - y0) > 1e-4:
				moved += 1
			var d := same(A, B)
			if d != "" and bad == "":
				bad = "%s #%d: %s" % [kind, i, d]
	Body.legacy_ground = false
	ok(bad == "", "%d random poses near prop kinds: offset and every joint equal within 1e-6 (%s)" % [total, bad if bad != "" else "all equal"])
	ok(moved > total / 4, "anti-vacuity: ground() moved the body in %d of %d poses" % [moved, total])
	# 2 SPEED: a chair beside the body, legacy and new alternated in one process
	var C := body()
	var mid := ((C.P["ball_l"] as Vector3) + (C.P["ball_r"] as Vector3) + (C.P["foot_l"] as Vector3) + (C.P["foot_r"] as Vector3)) / 4.0
	C.props = [Props.make("chair", Props.xf_at(Vector3(mid.x, 0, mid.z + 0.35), 0.0))]
	var D := body()
	D.props = C.props
	var start := C.offset
	var ratios := []
	for r in 5:
		var tl := 0
		var tn := 0
		for side in [0, 1]:
			C.offset = start
			D.offset = start
			C.fk()
			D.fk()
			var t0 := Time.get_ticks_usec()
			if side == 0:
				Body.legacy_ground = true
				for i in 300:
					C.ground()
				Body.legacy_ground = false
				tl = Time.get_ticks_usec() - t0
			else:
				for i in 300:
					D.ground()
				tn = Time.get_ticks_usec() - t0
		ratios.append(float(tn) / float(maxi(tl, 1)))
		print("     round %d: legacy %.1f ms, new %.1f ms per 300 calls, ratio %.3f" % [r, tl / 1000.0, tn / 1000.0, ratios[-1]])
	ratios.sort()
	var med: float = ratios[2]
	ok(med <= 0.6, "median ratio new/legacy %.3f <= 0.6" % med)
	Body.legacy_ground = false
	print("GROUNDSPEED %s" % ("FAIL" if fails > 0 else "ok"))
	TestFiles.cleanup()
	quit(1 if fails > 0 else 0)
