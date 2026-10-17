## godot --headless --path . -s tools/blender_expect.gd     (GATES OO3, step 1 of 2; then tools/blender_check.py)
## Every scene in scenes/ exported as .glb into C:/Temp/oo3 (or $OO3_DIR) with check.json: where every bone of the
## mannequin the app shows stands (glTF Y-up) at 4 frames of each scene. Blender reads both and compares.
extends SceneTree
static func rel(n: Node3D, top: Node) -> Transform3D:
	var x := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != top:
		if c is Node3D:
			x = (c as Node3D).transform * x
		c = c.get_parent()
	return x
static func bone_pose(sk: Skeleton3D, b: int) -> Transform3D:
	var x := Transform3D.IDENTITY
	while b >= 0:
		x = Transform3D(Basis(sk.get_bone_pose_rotation(b)).scaled(sk.get_bone_pose_scale(b)), sk.get_bone_pose_position(b)) * x
		b = sk.get_bone_parent(b)
	return x
func _init() -> void:
	var D := OS.get_environment("OO3_DIR") if OS.get_environment("OO3_DIR") != "" else "C:/Temp/oo3"
	DirAccess.make_dir_recursive_absolute(D)
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var holder := Node3D.new()
	root.add_child(holder)
	var mq := Overlays.mannequin(holder, StandardMaterial3D.new())
	var sk0: Skeleton3D = mq[1]
	var idx0: Dictionary = mq[2]
	var all := {}
	for f in DirAccess.get_files_at("res://scenes"):
		if not f.ends_with(".json"):
			continue
		var sn := f.get_basename()
		var S := Scene.new()
		S.from_dict(JSON.parse_string(FileAccess.get_file_as_string("res://scenes/" + f)))
		GltfExport.write(S, B, D + "/%s.glb" % sn)
		var n := int(ceil(S.length() * S.fps - 1e-6)) + 1
		var fr := {}
		for i in [0, n / 3, (2 * n) / 3, n - 2]:
			S.apply(B, minf(i / float(S.fps), S.length()))
			Overlays.pose_skeleton(sk0, idx0, B)
			var js := {}
			for j in Body.ORDER:
				if idx0[j] >= 0:
					var p: Vector3 = (rel(sk0, holder) * bone_pose(sk0, idx0[j])).origin
					js["head" if j == "head" else j] = [p.x, p.y, p.z]
			fr[str(i)] = js
		all[sn] = {"fps": S.fps, "frames": n, "check": fr}
	var fa := FileAccess.open(D + "/check.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify(all))
	fa.close()
	print("OO3 wrote %d scenes" % all.size())
	quit()
