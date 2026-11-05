extends SceneTree
## THE DRAWN HAND vs the hand's bone line (lane HAND, gaps G23 / G38): where the mannequin's palm skin sits in the hand's
## own frame (along the hand, across the knuckles, through the palm), at rest (mesh vertices = bind pose; every vertex
## belongs to the bone with its biggest skin weight).   godot --headless --path . -s tools/hand_mesh.gd
## Prints, per hand, the palm vertices' (hand_*) extents and the knuckle section, and the thumb base's place.


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var man: Node3D = (load("res://assets/mannequin.glb") as PackedScene).instantiate()
	var root := Node3D.new()
	get_root().add_child(root)
	root.add_child(man)
	var pts := {"hand_r": [], "hand_l": []}
	var fpts := {"_r": [], "_l": []}
	for mi in man.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var sk: Skin = m.skin
		var xf := Transform3D.IDENTITY
		var nd: Node = m
		while nd != null and nd != root:
			if nd is Node3D:
				xf = (nd as Node3D).transform * xf
			nd = nd.get_parent()
		for s in m.mesh.get_surface_count():
			var arr: Array = m.mesh.surface_get_arrays(s)
			var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var BI: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var BW: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := BI.size() / V.size()
			for v in V.size():
				var best := 0
				for k in per:
					if BW[v * per + k] > BW[v * per + best]:
						best = k
				var bone: String = sk.get_bind_name(BI[v * per + best]) if sk else ""
				var p: Vector3 = xf * V[v]
				if pts.has(bone):
					pts[bone].append(p)
				for sd in ["_r", "_l"]:
					if bone.ends_with(sd) and (bone.begins_with("index") or bone.begins_with("middle") or bone.begins_with("ring") or bone.begins_with("pinky") or bone.begins_with("thumb")):
						fpts[sd].append([bone, p])
	for h: String in ["hand_r", "hand_l"]:
		var f := HandShape.frame0(B, h)
		var w: Vector3 = B.p0[h]
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		var nlo := INF
		var nhi := -INF
		var blo := INF
		var bhi := -INF
		for p in pts[h]:
			var d: Vector3 = p - w
			var q := Vector3(d.dot(f["ax"]), d.dot(f["br"]), d.dot(f["nr"]))
			lo = lo.min(q)
			hi = hi.max(q)
			if q.x > 0.06 and q.x < 0.11:   # the knuckle section (a band behind the knuckles)
				nlo = minf(nlo, q.z)
				nhi = maxf(nhi, q.z)
				blo = minf(blo, q.y)
				bhi = maxf(bhi, q.y)
		print("%s: %d palm verts; along %.1f..%.1f cm, across %.1f..%.1f cm, palm normal %.1f (back) .. %.1f (palm) cm" % [h, pts[h].size(), lo.x * 100, hi.x * 100, lo.y * 100, hi.y * 100, lo.z * 100, hi.z * 100])
		print("   knuckle band 6-11 cm: breadth %.1f cm (%.1f..%.1f), thickness %.1f cm (%.1f..%.1f); model centre across %.1f cm" % [(bhi - blo) * 100, blo * 100, bhi * 100, (nhi - nlo) * 100, nlo * 100, nhi * 100, float(f["c"]) * 100])
		var sd := h.substr(4)
		var t1: Vector3 = (B.p0["thumb_01" + sd] as Vector3) - w
		print("   thumb_01 joint: along %.1f, across %.1f, normal %.1f cm" % [t1.dot(f["ax"]) * 100, t1.dot(f["br"]) * 100, t1.dot(f["nr"]) * 100])
		var tip := -INF
		for e in fpts[sd]:
			if String(e[0]).begins_with("middle"):
				tip = maxf(tip, ((e[1] as Vector3) - w).dot(f["ax"]))
		print("   middle finger skin tip: %.1f cm from the wrist joint along the hand" % (tip * 100))
	quit(0)
