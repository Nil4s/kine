extends SceneTree
## MESH vs CAPSULES (Nick 10-13: poses passed the checker with a hand flat on the chest and a forearm in the belly).
## The contact test uses capsules; this measures how far the VISIBLE mannequin's skin sits from each part's capsule
## axis, at rest (mesh vertices = bind pose). Every vertex belongs to the bone with its biggest skin weight.
##   godot --headless --path . -s tools/mesh_fit.gd [-- --write]
## Prints, per part: the capsule radius now and the skin distance at the 50 / 80 / 95 % marks.
## Found: the limbs' capsules match their skin; the CHEST and HIPS don't (a flat oval a capsule can't follow: the chest
## skin sits 3-4 cm outside its capsule). --write stores the trunk + head skin points in data/skin_points.json, which
## Body tests the forearms, hands and bat against (Body.skin_contacts).

const SKIN_PARTS := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head", "thigh_l", "thigh_r"]
const SKIN_STEP := 0.025   # keep one skin point per 2.5 cm cell (the test is then ~1 cm true, and cheap)


func _init() -> void:
	var B := Body.new()
	B.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var man: Node3D = (load("res://assets/mannequin.glb") as PackedScene).instantiate()
	var root := Node3D.new()
	get_root().add_child(root)
	root.add_child(man)
	var dist := {}   # part -> [distances]
	var pts := {}    # trunk/head part -> its skin points (rest, m)
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for mi in man.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		var sk: Skin = m.skin
		var xf := Transform3D.IDENTITY   # the node chain's own transforms (not in the tree yet: no global_transform)
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
				var bi: int = BI[v * per + best]
				var bone: String = sk.get_bind_name(bi) if sk and sk.get_bind_name(bi) != "" else str(bi)
				var part := "head" if bone == "Head" else bone
				var p: Vector3 = xf * V[v]
				lo = lo.min(p)
				hi = hi.max(p)
				if not B.cap0.has(part):
					continue
				var c: Array = B.cap0[part]
				var a: Vector3 = c[0]
				var b: Vector3 = c[1]
				var ab := b - a
				var t := clampf((p - a).dot(ab) / maxf(1e-9, ab.length_squared()), 0.0, 1.0)
				if not dist.has(part):
					dist[part] = []
				dist[part].append((p - (a + ab * t)).length())
				if part in SKIN_PARTS:
					if not pts.has(part):
						pts[part] = []
					pts[part].append(p)
	print("mesh bbox ", lo, " .. ", hi)
	var out := {}
	for part in Body.BODY:
		if not dist.has(part):
			continue
		var d: Array = dist[part]
		d.sort()
		var q := func(f: float) -> float: return d[int(f * (d.size() - 1))]
		print("%-12s cap r %.3f   skin 50%% %.3f  80%% %.3f  95%% %.3f   (%d verts)" % [part, B.rad[part], q.call(0.5), q.call(0.8), q.call(0.95), d.size()])
		out[part] = snappedf(q.call(0.8), 0.001)
	if OS.get_cmdline_user_args().has("--write"):
		# the trunk + head SKIN points, thinned to one per cell, for Body's skin contact test
		var skin := {}
		var n := 0
		for part in SKIN_PARTS:
			var seen := {}
			var keep := []
			for p in pts.get(part, []):
				var key := Vector3i((p / SKIN_STEP).floor())
				if seen.has(key):
					continue
				seen[key] = true
				keep.append([snappedf(p.x, 0.0001), snappedf(p.y, 0.0001), snappedf(p.z, 0.0001)])
			skin[part] = keep
			n += keep.size()
		FileAccess.open("res://data/skin_points.json", FileAccess.WRITE).store_string(JSON.stringify(skin))
		print("wrote data/skin_points.json (%d points)" % n)
	quit()
