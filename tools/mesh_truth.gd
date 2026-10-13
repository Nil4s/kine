extends SceneTree
## MESH TRUTH: is an arm inside the body on the VISIBLE mannequin? (Nick 10-13: "arms inside head and body ... simple
## mistake but cost a full animation ... just need to move this specific frame"). The capsule test can't see it all:
## the chest and hips are flat ovals whose skin sits 3-4 cm outside their capsules (tools/mesh_fit.gd). So this poses
## the real skinned mannequin exactly as the poser shows it (the bone rotations main.gd sets), skins every vertex on the
## CPU (bone pose * bind pose * vertex, weights blended) and asks, for each forearm/hand/finger vertex, whether it is
## behind the nearest trunk/head/hip skin (that vertex's normal says which side is inside); and the same for one
## forearm/hand through the other.
##   godot --headless --path . -s tools/mesh_truth.gd -- poses/a.json [...]      judge poses
##   godot --headless --path . -s tools/mesh_truth.gd -- scenes/x.json           judge EVERY frame of a move (30 fps)
##   godot --headless --path . -s tools/mesh_truth.gd -- --selftest              a hand forced into the chest: must be BAD
## > INSIDE_MM deep = visibly inside. A move prints only its bad frames (frame, time, how deep, which parts).

const ARM := ["lowerarm", "hand", "thumb", "index", "middle", "ring", "pinky"]
const TRUNK := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "Head", "thigh_l", "thigh_r"]   # hip sides = thigh skin
const INSIDE_MM := 3.0
const CELL := 0.06   # grid cell for the nearest-skin lookup (m)

var B: Body
var man: Node3D
var skel: Skeleton3D
var bone_idx := {}
var surf := []   # [mesh skin, to_world, V, N, BI, BW, per, class per vertex (0 other, 1 arm, 2 trunk), bone name per vertex]


func _initialize() -> void:
	B = Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	man = (load("res://assets/mannequin.glb") as PackedScene).instantiate()
	get_root().add_child(man)
	skel = man.find_children("*", "Skeleton3D", true, false)[0]
	for j in Body.ORDER:
		bone_idx[j] = skel.find_bone("Head" if j == "head" else j)
	_cache()
	var files: Array = OS.get_cmdline_user_args()
	if files.has("--selftest"):
		B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
		B.ground()
		var r0: Array = measure()
		B.fast = true   # no safety: the hand must really go in
		B.reach("hand_r", (B.P["spine_03"] as Vector3) + Vector3(0, 0, 0.10))
		B.fast = false
		var r1: Array = measure()
		print("selftest stand %.0f mm (must be OK), hand in chest %.0f mm %s (must be BAD): %s" % [r0[0] * 1000, r1[0] * 1000, r1[1],
			"PASS" if r0[0] * 1000 <= INSIDE_MM and r1[0] * 1000 > INSIDE_MM else "FAIL"])
		quit()
		return
	var n_bad := 0
	for f in files:
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://" + f))
		if d.has("cards"):
			var S := Scene.new()
			S.from_dict(d)
			var n := int(ceil(S.length() * 30.0))
			var bad := 0
			var worst := 0.0
			for fr in n + 1:
				S.apply(B, float(fr) / 30.0)
				var r: Array = measure()
				if r[0] * 1000.0 > INSIDE_MM:
					bad += 1
					worst = maxf(worst, r[0])
					print("   frame %3d  t=%.2f  %3.0f mm  %s" % [fr, float(fr) / 30.0, r[0] * 1000.0, r[1]])
			if bad > 0:
				n_bad += 1
			print("%-34s %s  %d of %d frames visibly inside (worst %.0f mm)" % [f, "OK  " if bad == 0 else "BAD ", bad, n + 1, worst * 1000.0])
		else:
			B.from_dict(d)
			B.ground()
			var r: Array = measure()
			var ok: bool = r[0] * 1000.0 <= INSIDE_MM
			if not ok:
				n_bad += 1
			print("%-34s %s  deepest arm vertex inside: %.0f mm %s   (nearest arm-to-body skin %.0f mm)" % [f, "OK  " if ok else "BAD ", r[0] * 1000.0, r[1], r[2] * 1000.0])
	print("MESH TRUTH %d/%d clean" % [files.size() - n_bad, files.size()])
	quit()


## the mesh arrays once (they never change), each vertex tagged arm / trunk / other by its heaviest bone
func _cache() -> void:
	for mi in man.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var sk: Skin = m.skin
		var to_world := Transform3D.IDENTITY   # the node chain (skeleton space -> mannequin root)
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
			var cls := PackedByteArray()
			cls.resize(V.size())
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
				cls[v] = 1 if ARM.any(func(a): return bname.begins_with(a)) else (2 if bname in TRUNK else 0)
			surf.append([sk, to_world, V, arr[Mesh.ARRAY_NORMAL], BI, BW, per, cls, names])


## [deepest arm vertex inside the body or the other arm (m), "which in which", nearest arm-to-body skin distance (m)]
func measure() -> Array:
	for j in Body.ORDER:
		if bone_idx[j] >= 0:
			skel.set_bone_pose_rotation(bone_idx[j], B.gltf_local(j))
	skel.set_bone_pose_position(bone_idx["pelvis"], B.gltf_pelvis_pos())
	# the skeleton isn't in a running tree here, so its global poses never update: compose them from the local poses
	var gp := {}
	for bi in skel.get_bone_count():
		gp[bi] = _global(bi, gp)
	var arm := []     # [pos, bone]
	var limb := []    # forearm + hand skin [pos, normal, bone] (one arm through the other)
	var grid := {}    # cell -> [[pos, normal, bone], ...] trunk skin
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
		var cls: PackedByteArray = sf[7]
		for v in V.size():
			if cls[v] == 0:
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
			var bname: String = sf[8][v]
			if cls[v] == 1:
				arm.append([p, bname])
				if bname.begins_with("lowerarm") or bname.begins_with("hand"):
					limb.append([p, nn.normalized(), bname])
			else:
				var key := Vector3i((p / CELL).floor())
				if not grid.has(key):
					grid[key] = []
				grid[key].append([p, nn.normalized(), bname])
	var worst := 0.0
	var where := ""
	var gap := INF
	for a in arm:
		var ap: Vector3 = a[0]
		var c := Vector3i((ap / CELL).floor())
		var bd := INF
		var bt = null
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for t in grid.get(c + Vector3i(dx, dy, dz), []):
						var d := ap.distance_squared_to(t[0])
						if d < bd:
							bd = d
							bt = t
		if bt == null:
			continue
		gap = minf(gap, sqrt(bd))
		var inside: float = -(ap - (bt[0] as Vector3)).dot(bt[1])
		if inside > worst:
			worst = inside
			where = "%s in %s" % [a[1], bt[2]]
	# one arm through the other: a left forearm/hand vertex behind the right forearm/hand skin, and back
	var lgrid := {}
	for t in limb:
		var key := Vector3i(((t[0] as Vector3) / 0.04).floor())
		if not lgrid.has(key):
			lgrid[key] = []
		lgrid[key].append(t)
	for a in limb:
		var sd: String = (a[2] as String).right(2)
		var c := Vector3i(((a[0] as Vector3) / 0.04).floor())
		var bd2 := INF
		var bt2 = null
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for t in lgrid.get(c + Vector3i(dx, dy, dz), []):
						if (t[2] as String).right(2) == sd:
							continue
						var d2 := (a[0] as Vector3).distance_squared_to(t[0])
						if d2 < bd2:
							bd2 = d2
							bt2 = t
		if bt2 == null:
			continue
		var ins: float = -((a[0] as Vector3) - (bt2[0] as Vector3)).dot(bt2[1])
		if ins > worst:
			worst = ins
			where = "%s in %s" % [a[2], bt2[2]]
	return [worst, where, gap]


func _global(bi: int, gp: Dictionary) -> Transform3D:
	if gp.has(bi):
		return gp[bi]
	var t := skel.get_bone_pose(bi)
	var par := skel.get_bone_parent(bi)
	if par >= 0:
		t = _global(par, gp) * t
	gp[bi] = t
	return t
