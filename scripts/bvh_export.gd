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
static func text(S: Scene, B: Body) -> Array:
	var keep := B.state()
	var kids := {}
	for j in Body.ORDER:
		kids[j] = []
	for j in Body.ORDER:
		if B.parent[j] != "":
			kids[B.parent[j]].append(j)
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
		h.append(pad + "\tCHANNELS " + ("6 Xposition Yposition Zposition " if depth == 0 else "3 ") + "Zrotation Xrotation Yrotation")
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

	var fps := float(maxi(1, S.fps))
	var n := int(ceil(S.length() * fps - 1e-6)) + 1
	h.append("MOTION")
	h.append("Frames: %d" % n)
	h.append("Frame Time: %.9f" % (1.0 / fps))
	var worst_rt := 0.0
	var checks := {}
	var at := [0, n / 3, (2 * n) / 3, n - 1]
	for i in n:
		S.apply(B, minf(i / fps, S.length()))
		B.fk()
		var row := PackedStringArray()
		for oj in order:
			var j: String = oj
			var q: Quaternion
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
				row.append("%.6f %.6f %.6f" % [lp.x, lp.y, lp.z])
			else:
				if B.parent[j] == "":
					var p: Vector3 = B.P[j]
					row.append("%.6f %.6f %.6f" % [p.x, p.y, p.z])
				q = B.compose(j, B.ang[j]).normalized()
			var e := zxy(q)
			worst_rt = maxf(worst_rt, rt_err(q, from_zxy(e)))
			row.append("%.5f %.5f %.5f" % [e.x, e.y, e.z])
		h.append(" ".join(row))
		if i in at:
			var f := {}
			for oj in order:
				if not "|" in oj:
					var p: Vector3 = B.P[oj]
					f[oj] = [p.x, p.y, p.z]
			checks[str(i)] = f
	B.set_state(keep)
	return ["\n".join(h) + "\n", {"frames": n, "joints": order.size(), "worst_rt": worst_rt, "at": checks, "fps": S.fps}]


## write the scene as BVH at path (res:// or absolute): [OK or the error, info]
static func write(S: Scene, B: Body, path: String) -> Array:
	var r := text(S, B)
	var abs := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
	var fa := FileAccess.open(abs, FileAccess.WRITE)
	if fa == null:
		return [FileAccess.get_open_error(), r[1]]
	fa.store_string(r[0])
	fa.close()
	return [OK, r[1]]
