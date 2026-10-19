## godot --headless --path . -s tests/corrective_test.gd     (ROADMAP 71: corrective shapes on the mesh, elbow and knee)
## Bars, stated before measuring:
##   1 at 0 deg (straight) the corrective on and off give byte-identical mesh surfaces (vertices, normals, indices)
##   2 at 120 deg elbow flexion the cross-section of the upper arm 2 cm from the elbow (the plane across the upper arm)
##     loses X % of its area without the correction (X measured; X must be > 5 so the test means something)
##   3 with the correction on, the same plane loses at most X / 3 % (the same skinned mesh, the same plane)
##   4 the drive is 0 at 0 deg, 0.5 at 70 deg, 1 at 140 deg and beyond (smoothstep 0..140)
##   5 the knee gets the same treatment: the correction on at 120 deg moves the calf's vertices (a count > 0)
##   6 the correction is not a rebuild per frame: the same pose twice rebuilds nothing the second time
## Run with a window (no --headless) it also saves the picture: the left arm at 120 deg without the corrective (left
## figure) and with it (right figure), to C:/Users/Nick/.claude/jobs/9afc22db/tmp/corrective.png.
## The section is the upper arm's own skin (triangles weighing >= 0.5 on the upper arm: own_tris), cut by the plane.
## Its area is the convex hull of the cut points, measured the same way with and without the correction (the arm's cut
## is near convex; both sides of the comparison use the same measure). The forearm is left out: it folds back through
## the plane at 120 deg and would add area that has nothing to do with the upper arm's pinch.
## Skinning here is the CPU form of what Godot does: v' = sum_q w_q (bone global pose * bind pose) v (rest is identity,
## checked in bar 0). The bone global poses are composed here (parent global * pose, parents first), not read from
## Skeleton3D.get_bone_global_pose: in this headless run the engine's cache did not follow set_bone_pose_rotation.
## Bar 0: the file's vertices are the skin at the file's own rest (max deviation printed).
extends SceneTree

var fails := 0


func ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		fails += 1


## every bone's global pose in the skeleton's space: parent global * the bone's pose (parents come first in the list)
static func globals(sk: Skeleton3D) -> Array:
	var g := []
	for i in sk.get_bone_count():
		var p := sk.get_bone_parent(i)
		var local := Transform3D(sk.get_bone_pose_rotation(i), sk.get_bone_pose_position(i))
		g.append(local if p < 0 else (g[p] as Transform3D) * local)
	return g


## the skinned positions of a mesh in the skeleton's space, from the bone globals g
static func skinned(m: ArrayMesh, sk: Skeleton3D, skin: Skin, g: Array) -> PackedVector3Array:
	var binds := []
	for k in skin.get_bind_count():
		var bb := skin.get_bind_bone(k)
		if bb < 0:
			bb = sk.find_bone(skin.get_bind_name(k))
		binds.append(bb)
	var mats := []
	for k in skin.get_bind_count():
		mats.append((g[binds[k]] as Transform3D) * skin.get_bind_pose(k))
	var out := PackedVector3Array()   # the surfaces' vertices, one after another (see _all_idx)
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(1, vs.size())
		for v in vs.size():
			var p := Vector3.ZERO
			for q in per:
				var w: float = wts[v * per + q]
				if w > 0.0:
					p += ((mats[bones[v * per + q]] as Transform3D) * vs[v]) * w
			out.append(p)
	return out


## the triangles of a mesh whose three corners all weigh >= 0.5 on bone `bone` (the limb's own skin: the mannequin's
## forearm folds back through the upper arm's plane, so the plane is cut through the upper arm's triangles only).
## Indices into skinned()'s concatenated vertices.
static func own_tris(m: ArrayMesh, sk: Skeleton3D, skin: Skin, bone: int) -> PackedInt32Array:
	var binds := []
	for k in skin.get_bind_count():
		binds.append(sk.find_bone(skin.get_bind_name(k)))
	var w := PackedFloat32Array()
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var n := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var per := bones.size() / maxi(1, n)
		for v in n:
			var sw := 0.0
			for q in per:
				if binds[bones[v * per + q]] == bone:
					sw += wts[v * per + q]
			w.append(sw)
	var out := PackedInt32Array()
	var ix := _all_idx(m)
	for t in range(0, ix.size(), 3):
		if w[ix[t]] >= 0.5 and w[ix[t + 1]] >= 0.5 and w[ix[t + 2]] >= 0.5:
			out.append_array([ix[t], ix[t + 1], ix[t + 2]])
	return out


## the cross-section area (m^2) of a set of triangles (index list over pos) cut by the plane (P, n): the convex hull of
## the cut points, in the plane's own 2D frame
static func section_area(pos: PackedVector3Array, idx: PackedInt32Array, P: Vector3, n: Vector3) -> float:
	var pts := []
	for t in range(0, idx.size(), 3):
		var a := pos[idx[t]]
		var b := pos[idx[t + 1]]
		var c := pos[idx[t + 2]]
		var da := n.dot(a - P)
		var db := n.dot(b - P)
		var dc := n.dot(c - P)
		for e in [[a, b, da, db], [b, c, db, dc], [c, a, dc, da]]:
			var d0: float = e[2]
			var d1: float = e[3]
			if (d0 > 0.0) != (d1 > 0.0):
				var s := d0 / (d0 - d1)
				pts.append((e[0] as Vector3).lerp(e[1], s))
	if pts.size() < 3:
		return 0.0
	var u := n.cross(Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := n.cross(u)
	var p2 := []
	for p in pts:
		var q: Vector3 = p - P
		p2.append(Vector2(q.dot(u), q.dot(v)))
	return hull_area(p2)


## the area of the convex hull of 2D points (monotone chain)
static func hull_area(p: Array) -> float:
	p.sort_custom(func(x, y): return x.x < y.x if x.x != y.x else x.y < y.y)
	var lo := []
	for q in p:
		while lo.size() >= 2 and _cross2(lo[-2], lo[-1], q) <= 0.0:
			lo.pop_back()
		lo.append(q)
	var up := []
	for i in range(p.size() - 1, -1, -1):
		var q: Vector2 = p[i]
		while up.size() >= 2 and _cross2(up[-2], up[-1], q) <= 0.0:
			up.pop_back()
		up.append(q)
	lo.pop_back()
	up.pop_back()
	var h := lo + up
	var a := 0.0
	for i in h.size():
		var x: Vector2 = h[i]
		var y: Vector2 = h[(i + 1) % h.size()]
		a += x.x * y.y - y.x * x.y
	return absf(a) * 0.5


static func _cross2(o: Vector2, a: Vector2, b: Vector2) -> float:
	return (a - o).x * (b - o).y - (a - o).y * (b - o).x


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	B.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
	B.ground()
	var rest_ang := B.ang.duplicate(true)
	var mq := Overlays.mannequin(root, StandardMaterial3D.new())
	var man: Node3D = mq[0]
	var sk: Skeleton3D = mq[1]
	var idx: Dictionary = mq[2]
	var mi: MeshInstance3D = man.find_children("*", "MeshInstance3D", true, false)[0]
	leftover = man
	var skin: Skin = mi.skin
	var src: ArrayMesh = mi.mesh
	# bar 0: the file's vertices are the skin at the file's own rest (no pose applied yet)
	var pos0 := skinned(src, sk, skin, globals(sk))
	var dev := 0.0
	var fi := 0
	for si in src.get_surface_count():
		var vs0: PackedVector3Array = src.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		for v in vs0.size():
			dev = maxf(dev, pos0[fi].distance_to(vs0[v]))
			fi += 1
	print("rest skinning deviation from the file's vertices: %.6f m (%d vertices)" % [dev, pos0.size()])
	ok(dev < 0.001, "bar 0: the file's vertices are the rest skin (deviation under 1 mm)")

	# the straight reference: every elbow and knee at bend 0 (the stand pose's elbows are 10 deg: not straight)
	_straight_limbs(B)
	Overlays.pose_skeleton(sk, idx, B)
	var gS := globals(sk)
	# the plane: 2 cm from the elbow across the upper arm (toward the shoulder), normal along the upper arm
	var elbow: Vector3 = (gS[idx["lowerarm_l"]] as Transform3D).origin
	var shoulder: Vector3 = (gS[idx["upperarm_l"]] as Transform3D).origin
	var nrm := (shoulder - elbow).normalized()
	var P := elbow + nrm * 0.02
	var own := own_tris(src, sk, skin, idx["upperarm_l"])
	var A0 := section_area(skinned(src, sk, skin, gS), own, P, nrm)

	# 120 deg elbow: the corrective off, then on (the same skin, the same plane)
	var c := Corrective.new()
	c.attach([mi], sk)
	c.on = false
	_straight_limbs(B)
	B.ang["lowerarm_l"] = Vector3(120.0, 0.0, 0.0)
	c.update(B)
	Overlays.pose_skeleton(sk, idx, B)
	var g120 := globals(sk)
	var A_off := section_area(skinned(mi.mesh as ArrayMesh, sk, skin, g120), own, P, nrm)
	var X := (A0 - A_off) / A0 * 100.0
	print("upper arm section 2 cm from the elbow: straight %.6f m2, 120 deg uncorrected %.6f m2 -> drop X = %.1f %%" % [A0, A_off, X])

	c.on = true
	var t0 := Time.get_ticks_usec()
	c.update(B)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("corrective rebuild at 120 deg: %.1f ms, %d meshes rebuilt" % [ms, c.rebuilds])
	var A_on := section_area(skinned(mi.mesh as ArrayMesh, sk, skin, g120), own, P, nrm)
	var drop_on := (A0 - A_on) / A0 * 100.0
	print("with the corrective: section %.6f m2, drop %.1f %% (X/3 = %.1f %%)" % [A_on, drop_on, X / 3.0])
	ok(X > 5.0, "bar 2: uncorrected, the 120 deg elbow loses X > 5 %% of the section (X = %.1f %%)" % X)
	ok(drop_on <= X / 3.0, "bar 3: with the corrective, the drop is at most X/3 (%.1f %% <= %.1f %%)" % [drop_on, X / 3.0])

	# bar 6: the same pose again rebuilds nothing
	c.update(B)
	ok(c.rebuilds == 0, "bar 6: the same pose twice rebuilds nothing (%d rebuilds)" % c.rebuilds)

	# bar 4: the drive curve
	var d0 := Corrective.drive_of(0.0)
	var d70 := Corrective.drive_of(70.0)
	var d140 := Corrective.drive_of(140.0)
	print("drive: 0 deg %.3f, 70 deg %.3f, 140 deg %.3f" % [d0, d70, d140])
	ok(d0 == 0.0 and absf(d70 - 0.5) < 1e-6 and d140 == 1.0 and Corrective.drive_of(200.0) == 1.0, "bar 4: drive 0 / 0.5 / 1 at 0 / 70 / 140 deg")

	# bar 1: at 0 deg the mesh is byte-identical with the corrective on and off
	var on_bytes := _bytes(_straight(c, B, rest_ang, idx, sk, mi, true))
	var off_bytes := _bytes(_straight(c, B, rest_ang, idx, sk, mi, false))
	ok(on_bytes == off_bytes, "bar 1: at 0 deg the mesh is byte-identical with the corrective on and off")

	# bar 5: the knee moves at 120 deg (the corrective's own effect: on against off, the same pose)
	mi.mesh = src
	var kc := Corrective.new()
	kc.attach([mi], sk)
	_straight_limbs(B)
	B.ang["calf_l"] = Vector3(120.0, 0.0, 0.0)
	kc.on = false
	kc.update(B)
	Overlays.pose_skeleton(sk, idx, B)
	var gk := globals(sk)
	var pk_off := skinned(mi.mesh as ArrayMesh, sk, skin, gk)
	kc.on = true
	kc.update(B)
	var knee_rebuilt := kc.rebuilds
	var pk := skinned(mi.mesh as ArrayMesh, sk, skin, gk)
	var knee_moved := 0
	for i in pk.size():
		if pk[i].distance_to(pk_off[i]) > 0.0005:
			knee_moved += 1
	print("knee at 120 deg: %d meshes rebuilt, %d vertices moved more than 0.5 mm by the corrective" % [knee_rebuilt, knee_moved])
	ok(knee_moved > 0, "bar 5: at 120 deg the knee's corrective moves vertices")

	print("RESULT %s (%d fail)" % ["PASS" if fails == 0 else "FAIL", fails])
	# with a window (not --headless): the picture, two mannequins with the left elbow at 120 deg, left without the
	# corrective and right with it, saved for the record
	if DisplayServer.get_name() != "headless":
		_setup_shot()
	else:
		quit(1 if fails > 0 else 0)


const SHOT := "C:/Users/Nick/.claude/jobs/9afc22db/tmp/corrective.png"
var shot_frames := -1
var leftover: Node3D


func _setup_shot() -> void:
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.fov = 40.0
	cam.position = Vector3(0.0, 1.2, 2.6)
	cam.current = true
	cam.look_at_from_position(cam.position, Vector3(0.0, 1.1, 0.0), Vector3.UP)
	root.remove_child(leftover)   # the one the numbers were made on, not in the picture
	leftover.free()
	var light := DirectionalLight3D.new()
	root.add_child(light)
	light.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	for side in [-0.5, 0.5]:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.78, 0.72, 0.64)
		var mq := Overlays.mannequin(root, mat)
		var man: Node3D = mq[0]
		man.position = Vector3(side, 0.0, 0.0)
		var sk: Skeleton3D = mq[1]
		var idx: Dictionary = mq[2]
		var mi: MeshInstance3D = man.find_children("*", "MeshInstance3D", true, false)[0]
		var SB := Body.new()
		SB.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		SB.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://poses/stand.json")))
		SB.ground()
		_straight_limbs(SB)
		SB.ang["lowerarm_l"] = Vector3(120.0, 0.0, 0.0)
		var c := Corrective.new()
		c.on = side > 0.0
		c.attach([mi], sk)
		c.update(SB)
		Overlays.pose_skeleton(sk, idx, SB)
		var lab := Label3D.new()
		lab.text = "with the corrective" if side > 0.0 else "without"
		lab.position = Vector3(side, 1.93, 0.0)
		lab.pixel_size = 0.002
		lab.font_size = 48
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		root.add_child(lab)
	shot_frames = 0


func _process(_delta: float) -> bool:
	if shot_frames < 0:
		return false
	shot_frames += 1
	if shot_frames == 6:
		var img := root.get_texture().get_image()
		img.save_png(SHOT)
		print("screenshot saved: %s (%d x %d)" % [SHOT, img.get_width(), img.get_height()])
		quit(1 if fails > 0 else 0)
	return false


static func _all_idx(m: ArrayMesh) -> PackedInt32Array:
	var out := PackedInt32Array()   # every triangle of every surface, indices into skinned()'s concatenated vertices
	var base := 0
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		var n: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		var ix = arr[Mesh.ARRAY_INDEX]
		if ix == null:
			for i in n:
				out.append(base + i)
		else:
			for k in (ix as PackedInt32Array).size():
				out.append(base + ix[k])
		base += n
	return out


## every elbow and knee straight (bend 0), the rest of the body as the body has it
static func _straight_limbs(B: Body) -> void:
	for j in ["lowerarm_l", "lowerarm_r", "calf_l", "calf_r"]:
		B.ang[j] = Vector3(0.0, B.ang[j].y, B.ang[j].z)


## the straight pose with the corrective on or off: the mesh's arrays after one update
func _straight(c: Corrective, B: Body, rest_ang: Dictionary, idx: Dictionary, sk: Skeleton3D, mi: MeshInstance3D, on: bool) -> Array:
	B.ang = rest_ang.duplicate(true)
	_straight_limbs(B)
	c.on = on
	c._last = {}
	c.update(B)
	Overlays.pose_skeleton(sk, idx, B)
	var out := []
	for si in (mi.mesh as ArrayMesh).get_surface_count():
		out.append((mi.mesh as ArrayMesh).surface_get_arrays(si))
	return out


func _bytes(arrs: Array) -> PackedByteArray:
	return var_to_bytes(arrs)
