## any_key.gd - ANY KEY (ROADMAP_400 L13, L15, L16). Pure helpers: no node.
##
## Scene.anykeys = {"<id>": [{"t": s, "v": Vector3}, ...]}   the same key shape as Scene.part_keys, so PartKeys.put / value_at
## carry them: a property is keyed by the SAME curve a joint angle is (bezier, clamped, no overshoot).
## IDS (the track type is generic: one id = one animatable value):
##   "shape:<mesh>:<key>"     L13 a shape key's weight on the KMesh registered as meshes[<mesh>] (KMeshShapes value, then re-blended)
##   "prop:<target>:<path>"   L15 any property of the Object registered as targets[<target>], by Object.set_indexed(path):
##                            a float (material roughness, light_energy), a Vector3 or a Color (rgb; alpha stays as it is)
## The registries are runtime (main fills them from the open scene's meshes, materials and lights); a key whose target is
## not registered is kept in the file and skipped at playback. Scene.apply plays them LAST (play); nothing keyed = nothing
## touched (an unkeyed property is never written, so it stays byte for byte).
## In the FILE: "anykeys": {"<id>": [{"t", "v": [x, y, z]}]} at full precision, only when there is one.
## BAKE (L16): bake() samples what the scene REALLY plays per frame (constraints, drivers, IK, physics-fed overlays: whatever
## Scene.apply does) and writes it as plain part keys; remove_source drops the sources that moved the baked joints.
## Limit: the hips' world offset is not a part key, so a source that only moves the offset (child_of on the pelvis) is not baked.
class_name AnyKey
extends RefCounted

static var targets := {}   # name -> Object (a Material, a Light3D, any Object with properties)
static var meshes := {}    # name -> KMesh


static func shape_id(mesh: String, key: String) -> String:
	return "shape:%s:%s" % [mesh, key]


static func prop_id(target: String, path: String) -> String:
	return "prop:%s:%s" % [target, path]


## the ids a scene keys, sorted: the dope sheet's extra rows
static func ids(S: Scene) -> Array:
	var out: Array = S.anykeys.keys()
	out.sort()
	return out


## row label for the dope sheet: "<target>.<what>"
static func label(id: String) -> String:
	var p := id.split(":", true, 2)
	return "%s.%s" % [p[1], p[2]] if p.size() == 3 else id


static func _vec(v: Variant) -> Vector3:
	if v is Color:
		return Vector3(v.r, v.g, v.b)
	if v is Vector3:
		return v
	return Vector3(float(v), 0.0, 0.0)


## key id at time t with value v (float, Vector3 or Color); a key within PartKeys.SAME_T is replaced
static func put(S: Scene, id: String, t: float, v: Variant) -> void:
	PartKeys.put(S.anykeys, id, t, _vec(v))


static func remove(S: Scene, id: String) -> bool:
	return S.anykeys.erase(id)


## the curve at t as a Vector3 (floats use .x); no keys = zero
static func vec_at(S: Scene, id: String, t: float) -> Vector3:
	if not S.anykeys.has(id) or (S.anykeys[id] as Array).is_empty():
		return Vector3.ZERO
	return PartKeys.value_at(S.anykeys[id], t)


static func float_at(S: Scene, id: String, t: float) -> float:
	return vec_at(S, id, t).x


## write every keyed value into its target at time t. Unregistered targets are skipped. Returns how many were written
static func play(S: Scene, t: float) -> int:
	var n := 0
	for id in S.anykeys:
		if (S.anykeys[id] as Array).is_empty():
			continue
		var p := String(id).split(":", true, 2)
		if p.size() != 3:
			continue
		var v := PartKeys.value_at(S.anykeys[id], t)
		if p[0] == "shape":
			var mesh = meshes.get(p[1])
			if mesh == null or KMeshShapes.find(mesh, p[2]) < 0:
				continue
			KMeshShapes.set_value(mesh, p[2], v.x)
			KMeshShapes.apply(mesh)
			n += 1
		elif p[0] == "prop":
			var o = targets.get(p[1])
			if o == null or not is_instance_valid(o):
				continue
			var cur = o.get_indexed(NodePath(p[2]))
			if cur is Color:
				o.set_indexed(NodePath(p[2]), Color(v.x, v.y, v.z, (cur as Color).a))
			elif cur is Vector3:
				o.set_indexed(NodePath(p[2]), v)
			elif cur is float or cur is int:
				o.set_indexed(NodePath(p[2]), v.x)
			else:
				continue
			n += 1
	return n


static func to_file(ak: Dictionary) -> Dictionary:
	var out := {}
	for id in ak:
		var ks := []
		for k in ak[id]:
			var v: Vector3 = k["v"]
			ks.append({"t": float(k["t"]), "v": [v.x, v.y, v.z]})
		if not ks.is_empty():
			out[id] = ks
	return out


static func from_file(d: Variant) -> Dictionary:
	var out := {}
	if not d is Dictionary:
		return out
	for id in d:
		if not d[id] is Array:
			continue
		var ks := []
		for k in d[id]:
			if k is Dictionary and k.has("t") and k.get("v") is Array and (k["v"] as Array).size() == 3:
				var a: Array = k["v"]
				ks.append({"t": float(k["t"]), "v": Vector3(float(a[0]), float(a[1]), float(a[2]))})
		ks.sort_custom(func(x, y): return float(x["t"]) < float(y["t"]))
		if not ks.is_empty():
			out[String(id)] = ks
	return out


## L16: the joints a source moves: those whose angle differs by more than 1e-6 between the live play and the play with the
## source switched off, over frames f0..f1
static func _differs(a: Array, b: Array) -> Array:
	var js := {}
	for f in mini(a.size(), b.size()):
		for j in a[f]:
			var x: Vector3 = a[f][j]
			var y: Vector3 = b[f].get(j, x)
			if maxf(absf(x.x - y.x), maxf(absf(x.y - y.y), absf(x.z - y.z))) > 1e-6:
				js[j] = true
	return js.keys()


static func _play(S: Scene, B: Body, f0: int, f1: int) -> Array:
	var out := []
	for f in range(f0, f1 + 1):
		S.apply(B, float(f) / maxf(float(S.fps), 1.0))
		out.append(B.ang.duplicate())
	return out


## BAKE FROM ANYTHING: frames f0..f1 (every `step`-th) of what Scene.apply plays become plain part keys on `joints` ([] = the
## joints the constraints and drivers move). remove_source drops those constraints / drivers in the same call (one undo step in
## main). Returns {"joints", "frames", "removed": ["cons", "drivers"], "keys": n}.
static func bake(S: Scene, B: Body, joints: Array, f0: int, f1: int, remove_source := true, step := 1) -> Dictionary:
	step = maxi(step, 1)
	var live := _play(S, B, f0, f1)
	var movers := []
	var cons_was := S.cons
	var drv_was := S.drivers
	var cons_moves := false
	var drv_moves := false
	if not cons_was.is_empty():
		S.cons = []
		var off := _play(S, B, f0, f1)
		S.cons = cons_was
		var dj := _differs(live, off)
		cons_moves = not dj.is_empty()
		movers.append_array(dj)
	if not drv_was.is_empty():
		S.drivers = []
		var off2 := _play(S, B, f0, f1)
		S.drivers = drv_was
		var dj2 := _differs(live, off2)
		drv_moves = not dj2.is_empty()
		for j in dj2:
			if not movers.has(j):
				movers.append(j)
	var js: Array = joints if not joints.is_empty() else movers
	var keys := 0
	var frames := []
	for f in range(f0, f1 + 1, step):
		frames.append(f)
		for j in js:
			PartKeys.put(S.part_keys, j, float(f) / maxf(float(S.fps), 1.0), live[f - f0][j])
			keys += 1
	var removed := []
	if remove_source:
		if cons_moves or (not joints.is_empty() and not cons_was.is_empty()):
			S.cons = []
			removed.append("cons")
		if drv_moves or (not joints.is_empty() and not drv_was.is_empty()):
			S.drivers = []
			removed.append("drivers")
	return {"joints": js, "frames": frames.size(), "removed": removed, "keys": keys}
