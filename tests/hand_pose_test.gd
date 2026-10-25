## godot --headless --path . -s tests/hand_pose_test.gd     (ROADMAP 73: finger pose library + per-finger curl)
## Body only (the numbers; the undo step and the screenshot are in hand_pose_ui_test.gd). Bars, stated before measuring:
##   1 LIMITS: every library pose (POSE_NAMES) on both hands: each finger and thumb joint within body_limits (clamp_ang
##     changes nothing, 1e-6 deg).
##   2 CURL 0 = REST: finger_curl(0) on all five fingers of both hands leaves every finger joint exactly Vector3.ZERO.
##   3 FIST: curl 1 on the index, each joint within 10 deg of the cited fist: MCP 85 / PIP 97.2 / DIP 74 (the curl model,
##     body.gd CURL_*; Indian J Plast Surg 2024 PMC11436331, Hahn 1995 PMC9541616) and of hand_shape("fist") (90 / 105 / 70).
##   4 GRIP: the grip pose's index joints are Gulke 2010's 28 / 43 / 26 deg exactly (1e-6).
##   5 MIRROR: each pose on the right hand, then mirror_side to the left: every joint of the left matches the right within
##     0.05 deg; and the same pose applied to the left hand is the right's reflected (twist negated) within 0.05 deg.
##   6 READBACK: finger_curl_of reads back the curl set for every finger at 0.3 and 0.8 (1e-4), and a finger's curl leaves
##     its neighbours alone.
##   7 THUMB: the thumb follows its own curl (thumb_02 at curl 1 = 60 deg, the table's value) and no spread.
##   8 PINCH / OK: the thumb tip and the index tip within 1 cm (world, default skeleton), both hands, printed in mm.
##   9 FIST ON THE DRAWN PALM: the skinned mannequin (assets/mannequin.glb, posed and skinned as tools/mesh_truth.gd does).
##     Each fingertip's distance to the palm-side triangles of the hand's skin, signed: + = outside the palm, - = through
##     it. Bar: every fingertip, both hands, from 0 to +1.5 cm. Printed in cm.
extends SceneTree

var fails := 0
var man: Node3D
var skel: Skeleton3D
var bone_idx := {}
var surf := []


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


func fresh() -> Body:
	var b := Body.new()
	b.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	b.fk()
	return b


## ---- the drawn palm (the fist bar): the skinned mannequin, posed and skinned as tools/mesh_truth.gd does ----
func setup_mesh() -> void:
	man = (load("res://assets/mannequin.glb") as PackedScene).instantiate()
	get_root().add_child(man)
	skel = man.find_children("*", "Skeleton3D", true, false)[0]
	for j in Body.ORDER:
		bone_idx[j] = skel.find_bone("Head" if j == "head" else j)
	for mi in man.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var sk: Skin = m.skin
		var to_world := Transform3D.IDENTITY
		var nd: Node = skel
		while nd != null and nd != man.get_parent():
			if nd is Node3D:
				to_world = (nd as Node3D).transform * to_world
			nd = nd.get_parent()
		for s in m.mesh.get_surface_count():
			var arr: Array = m.mesh.surface_get_arrays(s)
			var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var BI: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var BW: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := BI.size() / V.size()
			var names := []
			for v in V.size():
				var best := 0
				for k in per:
					if BW[v * per + k] > BW[v * per + best]:
						best = k
				var bname: String = sk.get_bind_name(BI[v * per + best])
				if bname == "":
					bname = skel.get_bone_name(sk.get_bind_bone(BI[v * per + best]))
				names.append(bname)
			surf.append([sk, to_world, V, arr[Mesh.ARRAY_NORMAL], BI, BW, per, names, arr[Mesh.ARRAY_INDEX]])


func _global(bi: int, gp: Dictionary) -> Transform3D:
	if gp.has(bi):
		return gp[bi]
	var t := skel.get_bone_pose(bi)
	var par := skel.get_bone_parent(bi)
	if par >= 0:
		t = _global(par, gp) * t
	gp[bi] = t
	return t


## the closest point on triangle (a, b, c) to p (Ericson, Real-Time Collision Detection 5.1.5)
func closest_on_tri(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		var w := (d4 - d3) / ((d4 - d3) + (d5 - d6))
		return b + (c - b) * w
	var denom := 1.0 / (va + vb + vc)
	return a + ab * (vb * denom) + ac * (vc * denom)


## each fingertip's signed distance (m) to the palm-side triangles of the posed hand skin (+ = outside the palm).
## The tip is the distal skin point of the finger's last bone farthest from its root (the fingertip's end).
func tips_signed(Bm: Body, side: String) -> Dictionary:
	for j in Body.ORDER:
		if bone_idx[j] >= 0:
			skel.set_bone_pose_rotation(bone_idx[j], Bm.gltf_local(j))
	skel.set_bone_pose_position(bone_idx["pelvis"], Bm.gltf_pelvis_pos())
	var gp := {}
	for bi in skel.get_bone_count():
		gp[bi] = _global(bi, gp)
	var c_dir: Vector3 = AnyGrip.curl_dir(fresh(), "hand_" + side)   # the side the palm faces (the fingers curl toward it)
	var sfx := "_" + side
	var palm_tri := []
	var fin := {}
	for sf in surf:
		var sk: Skin = sf[0]
		var xf := {}
		for b in sk.get_bind_count():
			var bn := sk.get_bind_bone(b)
			if bn < 0:
				bn = skel.find_bone(sk.get_bind_name(b))
			xf[b] = (sf[1] as Transform3D) * (gp[bn] as Transform3D) * sk.get_bind_pose(b)
		var V: PackedVector3Array = sf[2]
		var N: PackedVector3Array = sf[3]
		var BI: PackedInt32Array = sf[4]
		var BW: PackedFloat32Array = sf[5]
		var per: int = sf[6]
		var names: Array = sf[7]
		var IX: PackedInt32Array = sf[8]
		var posed := PackedVector3Array()
		var pnorm := PackedVector3Array()
		posed.resize(V.size())
		pnorm.resize(V.size())
		for v in V.size():
			var nm: String = names[v]
			if not nm.ends_with(sfx) and nm != "hand" + sfx:
				continue
			var p := Vector3.ZERO
			var nn := Vector3.ZERO
			for k in per:
				var w: float = BW[v * per + k]
				if w <= 0.0:
					continue
				var t: Transform3D = xf[BI[v * per + k]]
				p += (t * V[v]) * w
				nn += (t.basis * N[v]) * w
			posed[v] = p
			pnorm[v] = nn.normalized()
			for f in ["index", "middle", "ring", "pinky", "thumb"]:
				if nm == f + "_03" + sfx:   # the last bone's skin: the fingertip
					if not fin.has(f):
						fin[f] = []
					fin[f].append(p)
		for tri in range(0, IX.size(), 3):
			var a: int = IX[tri]
			var b2: int = IX[tri + 1]
			var d2: int = IX[tri + 2]
			if names[a] == "hand" + sfx and names[b2] == "hand" + sfx and names[d2] == "hand" + sfx:
				var fn: Vector3 = ((posed[b2] - posed[a]).cross(posed[d2] - posed[a])).normalized()
				var nv: Vector3 = (pnorm[a] + pnorm[b2] + pnorm[d2]).normalized()
				if fn.dot(nv) < 0.0:
					fn = -fn
				if fn.dot(c_dir) > 0.2:
					palm_tri.append([posed[a], posed[b2], posed[d2], fn])
	var out := {}
	for f in ["index", "middle", "ring", "pinky", "thumb"]:
		var pts: Array = fin.get(f, [])
		var root: Vector3 = (gp[skel.find_bone(f + ("_01" if f != "thumb" else "_02") + sfx)] as Transform3D).origin
		var tip := Vector3.ZERO
		var far := -1.0
		for q in pts:
			var dd: float = (q as Vector3).distance_to(root)
			if dd > far:
				far = dd
				tip = q
		var best := INF
		var sdv := 0.0
		for tr in palm_tri:
			var qq: Vector3 = closest_on_tri(tip, tr[0], tr[1], tr[2])
			var dq: float = tip.distance_to(qq)
			if dq < best:
				best = dq
				sdv = (tip - qq).dot(tr[3])
		out[f] = sdv
	return out


func _initialize() -> void:
	var B := fresh()
	# 1 limits, both hands, every pose
	var worst_out := 0.0
	for side in ["r", "l"]:
		for pn in Body.POSE_NAMES:
			B.hand_pose(side, pn)
			for j in B.hand_joints(side):
				var v: Vector3 = B.ang[j]
				var c: Vector3 = B.clamp_ang(j, v)
				worst_out = maxf(worst_out, maxf(absf(c.x - v.x), maxf(absf(c.y - v.y), absf(c.z - v.z))))
	ok(worst_out < 1e-6, "1 LIMITS: %d poses x 2 hands x 15 joints, worst clip %.6f deg (every value inside body_limits)" % [Body.POSE_NAMES.size(), worst_out])

	# 2 curl 0 = rest, exactly
	var R := fresh()
	for side in ["r", "l"]:
		R.hand_curl(side, 0.0, 0.0)
		for f in ["index", "middle", "ring", "pinky", "thumb"]:
			R.finger_curl(side, f, 0.0, 0.0)
	R.fk()
	var nz := 0
	for side in ["r", "l"]:
		for j in R.hand_joints(side):
			if R.ang[j] != Vector3.ZERO:
				nz += 1
	ok(nz == 0, "2 CURL 0 = REST: %d of 30 finger / thumb joints not exactly zero after curl 0 on both hands" % nz)

	# 3 fist: index curl 1 vs the cited fist, per joint
	var F := fresh()
	F.finger_curl("r", "index", 1.0, 0.0)
	F.fk()
	var cited_curl := [85.0, 97.2, 74.0]   # body.gd: CURL_MCP, CURL_PIP, DIP_PER_PIP x CURL_PIP
	var cited_shape := [90.0, 105.0, 70.0]   # body.gd hand_shape("fist"), the index's three joints
	var worst_c := 0.0
	var worst_s := 0.0
	var got := []
	for k in 3:
		var a: float = (F.ang["index_0%d_r" % (k + 1)] as Vector3).x
		got.append(snappedf(a, 0.01))
		worst_c = maxf(worst_c, absf(a - cited_curl[k]))
		worst_s = maxf(worst_s, absf(a - cited_shape[k]))
	ok(worst_c <= 10.0, "3a FIST (curl model): index at curl 1 = %s deg, cited 85 / 97.2 / 74: worst %.2f deg (bar 10)" % [str(got), worst_c])
	ok(worst_s <= 10.0, "3b FIST (hand_shape fist 90 / 105 / 70): worst %.2f deg (bar 10)" % worst_s)

	# 4 grip = Gulke
	var G := fresh()
	G.hand_pose("r", "grip")
	var gg := [(G.ang["index_01_r"] as Vector3).x, (G.ang["index_02_r"] as Vector3).x, (G.ang["index_03_r"] as Vector3).x]
	ok(absf(gg[0] - 28.0) < 1e-6 and absf(gg[1] - 43.0) < 1e-6 and absf(gg[2] - 26.0) < 1e-6,
		"4 GRIP (Gulke 2010 mean: MCP 28 / PIP 43 / DIP 26): index = %.4f / %.4f / %.4f" % gg)

	# 5 mirror, and the same pose on the other hand
	var worst_m := 0.0
	var worst_o := 0.0
	for pn in Body.POSE_NAMES:
		var M := fresh()
		M.hand_pose("r", pn)
		M.mirror_side("_r")
		M.fk()
		for j in M.hand_joints("r"):
			var jl: String = j.substr(0, j.length() - 2) + "_l"
			var rv: Vector3 = M.ang[j]
			var d: Vector3 = ((M.ang[jl] as Vector3) - Vector3(rv.x, rv.y, -rv.z)).abs()   # mirror_side negates twist
			worst_m = maxf(worst_m, maxf(d.x, maxf(d.y, d.z)))
		var O := fresh()
		O.hand_pose("l", pn)
		var Lh := fresh()
		Lh.hand_pose("r", pn)
		for j in Lh.hand_joints("r"):
			var jl2: String = j.substr(0, j.length() - 2) + "_l"
			var rv: Vector3 = Lh.ang[j]
			var mirrored := Vector3(rv.x, rv.y, -rv.z)   # the left hand's twist is the right's, negated
			var d2: Vector3 = ((O.ang[jl2] as Vector3) - mirrored).abs()
			worst_o = maxf(worst_o, maxf(d2.x, maxf(d2.y, d2.z)))
	ok(worst_m < 0.05, "5a MIRROR: each pose on the right, mirrored to the left: worst joint difference %.4f deg (bar 0.05)" % worst_m)
	ok(worst_o < 0.05, "5b the same pose on the left hand as on the right: worst difference %.4f deg (bar 0.05)" % worst_o)

	# 6 readback, neighbours untouched
	var Q := fresh()
	var worst_r := 0.0
	var neighbour_ok := true
	for f in ["index", "middle", "ring", "pinky", "thumb"]:
		for cu in [0.3, 0.8]:
			Q.finger_curl("r", f, cu, 0.0)
			Q.fk()
			worst_r = maxf(worst_r, absf(Q.finger_curl_of("r", f) - cu))
	Q.hand_pose("r", "open")
	Q.finger_curl("r", "middle", 1.0, 0.0)
	Q.fk()
	for j in ["index_01_r", "index_02_r", "ring_01_r", "pinky_02_r", "thumb_01_r"]:
		if (Q.ang[j] as Vector3) != Vector3.ZERO:
			neighbour_ok = false
	ok(worst_r < 1e-4, "6a READBACK: finger_curl_of reads back the curl set, every finger, 0.3 and 0.8 (worst %.6f)" % worst_r)
	ok(neighbour_ok, "6b the middle finger's curl leaves index, ring, pinky and thumb at rest")

	# 7 thumb: curl 1 = the table's 30 / 60 / 48 with no spread
	var T := fresh()
	T.finger_curl("r", "thumb", 1.0, 1.0)
	T.fk()
	var th := [(T.ang["thumb_01_r"] as Vector3), (T.ang["thumb_02_r"] as Vector3), (T.ang["thumb_03_r"] as Vector3)]
	ok(absf(th[1].x - 60.0) < 1e-6 and absf(th[2].x - 48.0) < 1e-6 and absf(th[0].x - 30.0) < 1e-6 and absf(th[0].y + 10.0) < 1e-6,
		"7 THUMB at curl 1: %.1f / %.1f / %.1f deg (table 30 / 60 / 48); thumb_01 side %.1f (table -10, the spread-free thumb)" % [th[0].x, th[1].x, th[2].x, th[0].y])

	# 8 pinch / ok: thumb tip to index tip, both hands
	var worst_p := 0.0
	var line := []
	for pn in ["pinch", "ok"]:
		for side in ["r", "l"]:
			var P := fresh()
			P.hand_pose(side, pn)
			var d: float = ((P.cap("thumb_03_" + side) as Array)[1] - (P.cap("index_03_" + side) as Array)[1]).length()
			worst_p = maxf(worst_p, d)
			line.append("%s %s %.2f mm" % [pn, side, d * 1000.0])
	ok(worst_p < 0.01, "8 PINCH / OK tip gap (world): %s (bar 10 mm)" % ", ".join(line))

	# 9 fist on the drawn palm, both hands: each fingertip's signed distance to the palm skin (+ = outside)
	setup_mesh()
	var lo := INF
	var hi := -INF
	var rows := []
	for side in ["r", "l"]:
		var Fm := fresh()
		Fm.hand_pose(side, "fist")
		var rep := tips_signed(Fm, side)
		var parts := []
		for f in ["index", "middle", "ring", "pinky", "thumb"]:
			var x: float = rep[f]
			lo = minf(lo, x)
			hi = maxf(hi, x)
			parts.append("%s %+.2f" % [f, x * 100.0])
		rows.append("%s: %s" % ["right" if side == "r" else "left", ", ".join(parts)])
	ok(lo >= 0.0 and hi <= 0.015, "9 FIST ON THE DRAWN PALM (cm, + = outside): %s; range %+.2f to %+.2f (bar 0 to +1.5)" % [" | ".join(rows), lo * 100.0, hi * 100.0])

	print("hand_pose_test: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	TestFiles.cleanup()
	quit(fails)
