## BVH EXPORT (round 34, GATES OO2; the writer of tools/export_bvh.gd moved here so the app calls it). A scene -> BVH
## (Blender, Maya, MotionBuilder, Cascadeur, every retargeter reads it), one frame per frame at the scene's fps.
## The poser's FK IS the BVH form: G[j] = G[parent] * A[j], P[j] = P[parent] + G[parent] * (p0[j] - p0[parent]) (body.gd
## fk), so a joint's OFFSET is its rest bone p0[j] - p0[parent] and its channels are compose(j, ang[j]) as Euler angles.
## Channels: Zrotation Xrotation Yrotation, i.e. M = Rz * Rx * Ry (the common mocap order). Metres, Y up, as the poser.
## The root has OFFSET 0 and its world position in its channels.
## THE WEAPONS (round 34): a joint "weapon" (and "weapon2") under the hand that holds it, OFFSET 0, SIX channels (its
## position and rotation in that hand's frame, every frame: a grip slides along a staff and turns in a re-grip, 0.20 m
## and 141 degrees in scenes/), an End Site at the tip (knob at the joint, the shaft along +Y). A weapon put away sits in
## the hand (BVH has no "hidden"). A scene that never holds one has no weapon joint.
class_name BvhExport
extends RefCounted


## M = Rz(z) Rx(x) Ry(y) -> (z, x, y) degrees.  Row 2 of Rz Rx Ry is (-cx sy, sx, cx cy); M01 = -sz cx; M11 = cz cx.
static func zxy(q: Quaternion) -> Vector3:
	var b := Basis(q)
	var m := func(r: int, c: int) -> float: return b[c][r]
	var x := asin(clampf(m.call(2, 1), -1.0, 1.0))
	var y := atan2(-m.call(2, 0), m.call(2, 2))
	var z := atan2(-m.call(0, 1), m.call(1, 1))
	return Vector3(rad_to_deg(z), rad_to_deg(x), rad_to_deg(y))


static func from_zxy(e: Vector3) -> Quaternion:
	return Quaternion(Vector3.BACK, deg_to_rad(e.x)) * Quaternion(Vector3.RIGHT, deg_to_rad(e.y)) * Quaternion(Vector3.UP, deg_to_rad(e.z))


## two rotations' difference in degrees, by how far they carry each axis (float32 acos near 1 floors angle_to at ~0.04 deg)
static func rt_err(q: Quaternion, r: Quaternion) -> float:
	var w := 0.0
	for v in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		w = maxf(w, (q * v - r * v).length())
	return rad_to_deg(2.0 * asin(clampf(w * 0.5, 0.0, 1.0)))


## the weapons the scene ever holds: [["weapon", hand, length], ...] (the hand and length of its first card that has it)
static func weapons_of(S: Scene) -> Array:
	var out := []
	for w in ["weapon", "weapon2"]:
		for c in S.cards:
			var d: Dictionary = c["pose"].get(w, {})
			if d.is_empty():
				continue
			var kind := String(d.get("kind", "metal_bat" if w == "weapon" else "dagger"))
			var L := float(d.get("length", Body.KINDS.get(kind, {"len": 0.84})["len"]))
			out.append([w, String(d.get("hand", "hand_r" if w == "weapon" else "hand_l")), L])
			break
	return out


## the scene as BVH text: [text, {"frames", "joints", "worst_rt" (the Euler round trip, deg), "at" -> {frame: {joint:
## [x, y, z]}} at 4 frames}]. B is posed through the scene; its state is put back.
## TWO CHARACTERS (round 50, GATES TC6): xf places the actor (the root's position and rotation channels carry it, the
## rest of the hierarchy follows); L / fps_in > 0 sample 0..L at fps_in (the scene shared by every actor) instead of the
## scene's own length and fps. The defaults write exactly what a one-actor export always wrote.
static func text(S: Scene, B: Body, xf := Transform3D.IDENTITY, L := -1.0, fps_in := -1, clean := true) -> Array:
	var placed := xf != Transform3D.IDENTITY
	var xq := xf.basis.get_rotation_quaternion()
	var keep := B.state()
	if B.body != S.body:
		B.set_proportions(S.body)   # PR2: the OFFSETs are the scene's own body's bones (put back at the end)
	var kids := {}
	for j in Body.ORDER:
		kids[j] = []
	for j in Body.ORDER:
		if B.parent[j] != "":
			kids[B.parent[j]].append(j)
	var keep_st := B.stretch.duplicate()
	var keep_cr := B.stretch_cross.duplicate()
	# L33: a scene that may stretch (a limb key with a stretch, a body spline chain) gives the stretched joint position channels (the OFFSET's
	# growth, so a plain BVH reader lands the joint exactly) and its parent bone Xscale Yscale Zscale (the bone's own stretch on the world axes)
	var st_pos := {}
	var st_scl := {}
	for k in StretchSkin.scene_joints(S, B):
		st_pos[k] = true
		st_scl[B.parent[k]] = true
	var weps := weapons_of(S)
	var wep_of := {}   # hand -> [weapon rows]
	for w in weps:
		if not B.parent.has(w[1]):
			w[1] = "pelvis"   # a weapon set down (no hand): it hangs from the hips, still six channels
		if not wep_of.has(w[1]):
			wep_of[w[1]] = []
		wep_of[w[1]].append(w)
	var order := []   # joints in the order their channels appear (depth first, as written)
	var h := PackedStringArray(["HIERARCHY"])
	var write := func(self_fn: Callable, j: String, depth: int) -> void:
		var pad := "\t".repeat(depth)
		var off: Vector3 = Vector3.ZERO if B.parent[j] == "" else (B.p0[j] as Vector3) - (B.p0[B.parent[j]] as Vector3)
		h.append(pad + ("ROOT " if depth == 0 else "JOINT ") + j)
		h.append(pad + "{")
		h.append(pad + "\tOFFSET %.6f %.6f %.6f" % [off.x, off.y, off.z])
		var nm := ("Xposition Yposition Zposition " if depth == 0 or st_pos.has(j) else "") + ("Xscale Yscale Zscale " if st_scl.has(j) else "") + "Zrotation Xrotation Yrotation"
		h.append(pad + "\tCHANNELS %d %s" % [nm.count(" ") + 1, nm])
		order.append(j)
		var held: Array = wep_of.get(j, [])
		if kids[j].is_empty() and held.is_empty():
			var e: Vector3 = (B.e0[j] as Vector3) - (B.p0[j] as Vector3)
			h.append(pad + "\tEnd Site")
			h.append(pad + "\t{")
			h.append(pad + "\t\tOFFSET %.6f %.6f %.6f" % [e.x, e.y, e.z])
			h.append(pad + "\t}")
		for k in kids[j]:
			self_fn.call(self_fn, k, depth + 1)
		for w in held:
			h.append(pad + "\tJOINT " + w[0])
			h.append(pad + "\t{")
			h.append(pad + "\t\tOFFSET 0.000000 0.000000 0.000000")
			h.append(pad + "\t\tCHANNELS 6 Xposition Yposition Zposition Zrotation Xrotation Yrotation")
			h.append(pad + "\t\tEnd Site")
			h.append(pad + "\t\t{")
			h.append(pad + "\t\t\tOFFSET 0.000000 %.6f 0.000000" % w[2])
			h.append(pad + "\t\t}")
			h.append(pad + "\t}")
			order.append(w[0] + "|" + j)
		h.append(pad + "}")
	write.call(write, "pelvis", 0)

	var fps := float(maxi(1, S.fps if fps_in <= 0 else fps_in))
	var span := S.length() if L < 0.0 else L
	var n := int(ceil(span * fps - 1e-6)) + 1
	h.append("MOTION")
	h.append("Frames: %d" % n)
	h.append("Frame Time: %.9f" % (1.0 / fps))
	var worst_rt := 0.0
	var checks := {}
	var at := [0, n / 3, (2 * n) / 3, n - 1]
	# pass 1: every frame's rotation and position per channel group (the rotations are unrolled per joint in pass 2)
	var qs := []   # per group: its frames' rotations
	var ps := []   # per group: its frames' position text ("" when the group has none)
	for _k in order.size():
		qs.append([])
		ps.append([])
	for i in n:
		S.apply(B, minf(i / fps, span))
		B.fk()
		var ow := StretchSkin.own_world(B) if B.has_stretch() else {}
		for k in order.size():
			var oj: String = order[k]
			var j: String = oj
			var q: Quaternion
			var pt := ""
			if "|" in oj:
				# a weapon: its knob and rotation in its hand's frame (at the hand when put away)
				var w: String = oj.get_slice("|", 0)
				var hand: String = oj.get_slice("|", 1)
				var on: bool = B.wep_on if w == "weapon" else B.wep2_on
				var Gh: Quaternion = B.G[hand]
				var lp := Vector3.ZERO
				q = Quaternion.IDENTITY
				if on:
					var x: Array = B.wep_xform() if w == "weapon" else B.wep2_xform()
					lp = Gh.inverse() * ((x[0] as Vector3) - (B.P[hand] as Vector3))
					q = (Gh.inverse() * (x[1] as Quaternion)).normalized()
				pt = "%.6f %.6f %.6f" % [lp.x, lp.y, lp.z]
			else:
				if B.parent[j] == "":
					var p: Vector3 = xf * (B.P[j] as Vector3) if placed else B.P[j]
					pt = "%.6f %.6f %.6f" % [p.x, p.y, p.z]
				if st_pos.has(j) and B.parent[j] != "":
					var dl := ((B.p0[j] as Vector3) - (B.p0[B.parent[j]] as Vector3)) * (float(B.stretch.get(j, 1.0)) - 1.0)
					pt = "%.6f %.6f %.6f" % [dl.x, dl.y, dl.z]
				if st_scl.has(j):
					var sw: Vector3 = ow.get(j, Vector3.ONE)
					pt = (pt + " " if pt != "" else "") + "%.6f %.6f %.6f" % [sw.x, sw.y, sw.z]
				q = B.compose(j, B.ang[j]).normalized()
				if placed and B.parent[j] == "":
					q = (xq * q).normalized()
			qs[k].append(q)
			ps[k].append(pt)
		if i in at:
			var f := {}
			for oj in order:
				if not "|" in oj:
					var p: Vector3 = xf * (B.P[oj] as Vector3) if placed else B.P[oj]
					f[oj] = [p.x, p.y, p.z]
			checks[str(i)] = f
	if B.stretch != keep_st:
		B.set_stretch(keep_st, keep_cr)
	B.set_state(keep)
	# pass 2: the Euler channels, unrolled per joint (RotClean) unless clean is off
	var tracks := []
	for k in order.size():
		tracks.append(RotClean.euler_track(qs[k], clean))
	var rows := PackedStringArray()
	for i in n:
		var row := PackedStringArray()
		for k in order.size():
			if ps[k][i] != "":
				row.append(ps[k][i])
			var e: Vector3 = tracks[k][i]
			worst_rt = maxf(worst_rt, rt_err(qs[k][i], from_zxy(e)))
			row.append("%.5f %.5f %.5f" % [e.x, e.y, e.z])
		rows.append(" ".join(row))
	h.append_array(rows)
	return ["\n".join(h) + "\n", {"frames": n, "joints": order.size(), "worst_rt": worst_rt, "at": checks, "fps": S.fps}]


## write the scene as BVH at path (res:// or absolute): [OK or the error, info]
static func write(S: Scene, B: Body, path: String, xf := Transform3D.IDENTITY, L := -1.0, fps_in := -1, clean := true) -> Array:
	var r := text(S, B, xf, L, fps_in, clean)
	var abs := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
	var fa := FileAccess.open(abs, FileAccess.WRITE)
	if fa == null:
		return [FileAccess.get_open_error(), r[1]]
	fa.store_string(r[0])
	fa.close()
	return [OK, r[1]]


## TWO CHARACTERS (TC6): one .bvh per actor (a BVH holds one skeleton): <dir>/<base>_<actor>.bvh, each placed at its xf,
## all over the same time range (0 .. the longest scene, the hero's fps). actors = [{"name", "S", "B", "xf"}].
## -> [[path, OK or the error, info], ...]
static func write_actors(actors: Array, dir: String, base: String, clean := true) -> Array:
	var L := 0.0
	for a in actors:
		L = maxf(L, (a["S"] as Scene).length())
	var fps: int = maxi(1, (actors[0]["S"] as Scene).fps)
	var out := []
	var used := {}
	for a in actors:
		var nm := "%s_%s" % [base, String(a["name"]).validate_filename().replace(" ", "_")]
		while used.has(nm):
			nm += "_"
		used[nm] = true
		var path := "%s/%s.bvh" % [dir, nm]
		var r := write(a["S"], a["B"], path, a["xf"], L, fps, clean)
		out.append([path, r[0], r[1]])
	return out
