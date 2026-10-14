## godot --headless --path . -s tools/export_bvh.gd -- scenes/<name>.json [out.bvh] [--check out.json]   (GATES G)
## A scene -> BVH (Blender, Maya, MotionBuilder, Cascadeur, every retargeter reads it), sampled at the scene's fps.
## The poser's FK IS the BVH form: G[j] = G[parent] * A[j], P[j] = P[parent] + G[parent] * (p0[j] - p0[parent]) (body.gd
## fk), so a joint's OFFSET is its rest bone p0[j] - p0[parent] and its channels are compose(j, ang[j]) as Euler angles.
## Channels: Zrotation Xrotation Yrotation, i.e. M = Rz * Rx * Ry (the common mocap order). Metres, Y up, as the poser.
## The root has OFFSET 0 and its world position in its channels. The weapon is not a bone: it is not exported.
## --check writes every joint's world position at 4 frames, for the import test (Blender must land within 1 cm).
extends SceneTree


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


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- scenes/<name>.json [out.bvh] [--check out.json]")
		quit(1)
		return
	var src: String = args[0]
	var S := Scene.new()
	S.from_dict(JSON.parse_string(FileAccess.get_file_as_string(src)))
	var out := "res://moves/bvh/%s.bvh" % src.get_file().get_basename()
	if args.size() > 1 and not args[1].begins_with("--"):
		out = args[1]
	var ci := args.find("--check")
	var check_path: String = args[ci + 1] if ci >= 0 and ci + 1 < args.size() else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()) if out.begins_with("res://") else out.get_base_dir())
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")

	var kids := {}
	for j in Body.ORDER:
		kids[j] = []
	for j in Body.ORDER:
		if B.parent[j] != "":
			kids[B.parent[j]].append(j)
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
		if kids[j].is_empty():
			var e: Vector3 = (B.e0[j] as Vector3) - (B.p0[j] as Vector3)
			h.append(pad + "\tEnd Site")
			h.append(pad + "\t{")
			h.append(pad + "\t\tOFFSET %.6f %.6f %.6f" % [e.x, e.y, e.z])
			h.append(pad + "\t}")
		for k in kids[j]:
			self_fn.call(self_fn, k, depth + 1)
		h.append(pad + "}")
	write.call(write, "pelvis", 0)

	var fps := float(S.fps)
	var n := int(ceil(S.length() * fps)) + 1
	h.append("MOTION")
	h.append("Frames: %d" % n)
	h.append("Frame Time: %.9f" % (1.0 / fps))
	var worst_rt := 0.0   # the Euler round trip, every joint every frame (deg of rotation)
	var checks := {}
	var at := [0, n / 3, (2 * n) / 3, n - 1]
	for i in n:
		S.apply(B, minf(i / fps, S.length()))
		B.fk()
		var row := PackedStringArray()
		for j in order:
			if B.parent[j] == "":
				var p: Vector3 = B.P[j]
				row.append("%.6f %.6f %.6f" % [p.x, p.y, p.z])
			var q := B.compose(j, B.ang[j]).normalized()
			var e := zxy(q)
			worst_rt = maxf(worst_rt, rt_err(q, from_zxy(e)))
			row.append("%.5f %.5f %.5f" % [e.x, e.y, e.z])
		h.append(" ".join(row))
		if i in at:
			var f := {}
			for j in order:
				var p: Vector3 = B.P[j]
				f[j] = [p.x, p.y, p.z]
			checks[str(i)] = f
	var fa := FileAccess.open(out, FileAccess.WRITE)
	fa.store_string("\n".join(h) + "\n")
	fa.close()
	print("%s -> %s: %d joints, %d frames at %d fps (%.2f s); Euler round trip worst %.6f deg" % [src, out, order.size(), n, S.fps, S.length(), worst_rt])
	if check_path != "":
		var fc := FileAccess.open(check_path, FileAccess.WRITE)
		fc.store_string(JSON.stringify({"fps": S.fps, "frames": checks}))
		fc.close()
		print("check positions -> %s (frames %s)" % [check_path, str(at)])
	quit(0 if worst_rt < 1e-3 else 1)
