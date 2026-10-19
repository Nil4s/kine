## godot --headless --path . -s tests/euler_test.gd     (ROADMAP 64, "Clean rotation curves")
## EULER UNROLL AND QUATERNION SIGN CONTINUITY (RotClean). Synthetic joints first, then combo3 and walk_bat written
## both ways (clean on and off) and read back by readers written here, from the file format.
## (1) a joint spinning 720 degrees about Z, and one about Y: the unrolled ZXY curve has no frame-to-frame step of 30
##     degrees or more where the true rotation step is under 10 degrees; the canonical curve (clean off) does (the teeth).
## (2) a joint through gimbal lock: its middle angle X runs 90 -> -90 -> 90 with X = +90 and -90 exactly at frames
##     0 and 120; the same bound on every frame, and the decoded matrix equals the source within 1e-4 degrees.
## (3) quaternion sign continuity: every 3rd quaternion negated; hemisphere() gives every dot >= 0 and the same rotation.
## (4) combo3 and walk_bat: BVH channels with clean on have no such step, and the decoded rotations equal the clean-off
##     file's within 1e-4 degrees; the USDA quaternions with clean on have every dot >= 0.
## The numbers of the changed values (wraps: a shift of 360 k; the rest: re-solves at a flip or in the gimbal's free
## direction) are printed for the byte-hash re-baseline.
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## the frame-to-frame steps of an unrolled curve against the true rotation steps:
## [steps of 30 deg or more where the true step is under 10 deg, the largest step (deg) where the true step is under 10,
##  the worst decoded error (deg) of the curve against the source rotations]
static func audit(qs: Array, eu: Array) -> Array:
	var bad := 0
	var worst_step := 0.0
	var worst_rt := 0.0
	for i in qs.size():
		worst_rt = maxf(worst_rt, err64(qs[i], eu[i]))
		if i == 0:
			continue
		var true_step := BvhExport.rt_err(qs[i - 1], qs[i])
		var d: Vector3 = (eu[i] - eu[i - 1]).abs()
		var st := maxf(d.x, maxf(d.y, d.z))
		if true_step < 10.0:
			worst_step = maxf(worst_step, st)
			if st >= 30.0:
				bad += 1
	return [bad, worst_step, worst_rt]


## the largest entry difference (deg) between a source rotation and an Euler triple's matrix, in float64 (the float32
## rt_err has a floor of ~1e-4 deg near gimbal lock)
static func err64(q: Quaternion, e: Vector3) -> float:
	var A := RotClean.mat_of(q)
	var B := RotClean.mat(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))
	var m := 0.0
	for k in 9:
		m = maxf(m, absf(A[k] - B[k]))
	return rad_to_deg(m)


## the BVH text -> the rotation track of each joint in HIERARCHY order: Array of Vector3 (Z, X, Y degrees) per frame
static func bvh_rot_tracks(txt: String) -> Array:
	var names := []
	var rows := []
	var in_motion := false
	for line in txt.split("\n"):
		var t := line.strip_edges().split(" ", false)
		if t.is_empty():
			continue
		if in_motion:
			if not t[0].is_valid_float():
				continue   # Frames: / Frame Time:
			var r := []
			for v in t:
				r.append(v.to_float())
			rows.append(r)
		elif t[0] == "MOTION":
			in_motion = true
		elif t[0] == "CHANNELS":
			for k in t[1].to_int():
				names.append(t[2 + k])
	var out := []
	for zi in names.size():
		if names[zi] != "Zrotation":
			continue
		var tr := []
		for r in rows:
			tr.append(Vector3(r[zi], r[zi + 1], r[zi + 2]))
		out.append(tr)
	return out


## the USDA rotations.timeSamples -> per frame, per joint (ORDER) the quaternion as written (w, x, y, z)
static func usd_rot_track(txt: String, nj: int) -> Array:
	var out := []
	var in_rot := false
	for line in txt.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("quatf[] rotations.timeSamples"):
			in_rot = true
			continue
		if in_rot and s == "}":
			break
		if in_rot and ":" in s and "[" in s:
			var nums := s.get_slice(":", 1).replace("[", " ").replace("]", " ").replace("(", " ").replace(")", " ").replace(",", " ").split(" ", false)
			var fr := []
			for j in nj:
				var k := j * 4
				fr.append(Quaternion(nums[k + 1].to_float(), nums[k + 2].to_float(), nums[k + 3].to_float(), nums[k].to_float()))
			out.append(fr)
	return out


## the values that differ between two curves: [changed, whole turns (a difference of 1 deg or more that is a multiple of
## 360 deg), the other differences of 1 deg or more, the largest difference below 1 deg (deg)]
static func diff_stats(a: Array, b: Array) -> Array:
	var changed := 0
	var wraps := 0
	var other := 0
	var small := 0.0
	for j in a.size():
		for i in (a[j] as Array).size():
			var d: Vector3 = (a[j][i] as Vector3) - (b[j][i] as Vector3)
			for c in 3:
				var v := absf(d[c])
				if v > 1e-6:
					changed += 1
					if v < 1.0:
						small = maxf(small, v)
						continue
					var turns := v / 360.0
					if absf(turns - roundf(turns)) * 360.0 < 1e-3:
						wraps += 1
					else:
						other += 1
	return [changed, wraps, other, small]


func _init() -> void:
	var nj := 0
	# (1) a joint spinning 720 degrees about one axis (Z, then Y): 5 degrees a frame, 145 frames
	var spins := {"Z": [], "Y": []}
	for i in 145:
		spins["Z"].append(Quaternion(Vector3.BACK, deg_to_rad(5.0 * i)))
		spins["Y"].append(Quaternion(Vector3.UP, deg_to_rad(5.0 * i)))
	for ax in ["Z", "Y"]:
		var qs: Array = spins[ax]
		var on := RotClean.euler_track(qs, true)
		var off := RotClean.euler_track(qs, false)
		var a_on := audit(qs, on)
		var a_off := audit(qs, off)
		ok(a_on[0] == 0 and a_on[2] < 1e-4, "1 spin 720 about %s: unrolled, %d steps of 30 deg+ where the true step is under 10 deg (off: %d), worst step %.3f deg, decoded matrix error %.7f deg" % [ax, a_on[0], a_off[0], a_on[1], a_on[2]])
		var last_on: Vector3 = on[on.size() - 1]
		ok(absf(last_on[0 if ax == "Z" else 2] - 720.0) < 1e-3, "1s spin 720 about %s: the unrolled curve ends at %.4f deg (720 is the true total)" % [ax, last_on[0 if ax == "Z" else 2]])

	# (2) a joint through gimbal lock: Z = 3 deg a frame, X = 90 cos(t), Y = 40 sin(t) over 240 frames
	var gq := []
	var ge := []
	for i in 240:
		var e := Vector3(3.0 * i, 90.0 * cos(TAU * i / 240.0), 40.0 * sin(TAU * i / 240.0))
		ge.append(e)
		gq.append(BvhExport.from_zxy(e))
	var gon := RotClean.euler_track(gq, true)
	var goff := RotClean.euler_track(gq, false)
	var g_on := audit(gq, gon)
	var g_off := audit(gq, goff)
	ok(g_on[0] == 0 and g_on[2] < 1e-4, "2 gimbal (X = +-90 exactly at frames 0, 120): unrolled, %d steps of 30 deg+ where the true step is under 10 deg (off: %d), worst step %.3f deg, decoded matrix error %.7f deg" % [g_on[0], g_off[0], g_on[1], g_on[2]])
	var gcount := 0
	for i in 240:
		if absf(absf(goff[i].y) - 90.0) < 1e-3:
			gcount += 1
	print("     gimbal frames with the canonical X at +-90 (within 1e-3): %d; the true X at frame 0 and 120: %.1f, %.1f" % [gcount, ge[0].y, ge[120].y])

	# (3) quaternion sign continuity on the gimbal joint: every 3rd quaternion negated
	var neg := []
	var neg_bad := 0
	for i in gq.size():
		var q: Quaternion = gq[i]
		if i % 3 == 1:
			q = Quaternion(-q.x, -q.y, -q.z, -q.w)
		neg.append(q)
		if i > 0 and (neg[i] as Quaternion).dot(neg[i - 1]) < 0.0:
			neg_bad += 1
	var hem := RotClean.hemisphere(neg, true)
	var hem_bad := 0
	var hem_rt := 0.0
	for i in hem.size():
		if i > 0 and (hem[i] as Quaternion).dot(hem[i - 1]) < 0.0:
			hem_bad += 1
		hem_rt = maxf(hem_rt, BvhExport.rt_err(hem[i], gq[i]))
	ok(hem_bad == 0 and hem_rt < 1e-4, "3 quaternion track, every 3rd negated: %d negative dots before, %d after; decoded rotation error %.7f deg" % [neg_bad, hem_bad, hem_rt])

	# (4) the shipped scenes, both ways
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	nj = Body.ORDER.size()
	for sn in ["combo3", "walk_bat"]:
		var S := Scene.new()
		S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/%s.json" % sn)))
		var bon: String = BvhExport.text(S, B, Transform3D.IDENTITY, -1.0, -1, true)[0]
		var boff_r: Array = BvhExport.text(S, B, Transform3D.IDENTITY, -1.0, -1, false)
		var ton := bvh_rot_tracks(bon)
		var toff := bvh_rot_tracks(boff_r[0])
		var bad_on := 0
		var bad_off := 0
		var rt_on := 0.0
		for j in ton.size():
			var qs := []
			for i in (toff[j] as Array).size():
				qs.append(BvhExport.from_zxy(toff[j][i]))
			bad_on += audit(qs, ton[j])[0]
			bad_off += audit(qs, toff[j])[0]
			for i in qs.size():
				rt_on = maxf(rt_on, BvhExport.rt_err(BvhExport.from_zxy(ton[j][i]), qs[i]))
		var ds := diff_stats(ton, toff)
		ok(bad_on == 0 and rt_on < 1e-4, "4 %s BVH: %d joints, %d steps of 30 deg+ where the true step is under 10 deg (off: %d); decoded vs clean-off worst %.7f deg. Values changed: %d = whole-turn wraps %d + other 1-deg-plus %d + sub-degree (largest %.7f deg). Writer worst_rt %.7f" % [sn, ton.size(), bad_on, bad_off, rt_on, ds[0], ds[1], ds[2], ds[3], boff_r[1]["worst_rt"]])

		var uon: String = UsdExport.text(S, B, true)[0]
		var uoff: String = UsdExport.text(S, B, false)[0]
		var qon := usd_rot_track(uon, nj)
		var qoff := usd_rot_track(uoff, nj)
		var neg_on := 0
		var neg_off := 0
		var urt := 0.0
		for i in qon.size():
			for j in nj:
				urt = maxf(urt, BvhExport.rt_err(qon[i][j], qoff[i][j]))
				if i > 0:
					if (qon[i][j] as Quaternion).dot(qon[i - 1][j]) < 0.0:
						neg_on += 1
					if (qoff[i][j] as Quaternion).dot(qoff[i - 1][j]) < 0.0:
						neg_off += 1
		ok(neg_on == 0 and urt < 1e-4 and qon.size() == int(ceil(S.length() * S.fps - 1e-6)) + 1, "4u %s USDA: %d frames x %d joints, quaternion dots < 0: %d (off: %d); decoded vs clean-off worst %.7f deg" % [sn, qon.size(), nj, neg_on, neg_off, urt])

	print("EULER: %d failed" % fails)
	quit(1 if fails > 0 else 0)
