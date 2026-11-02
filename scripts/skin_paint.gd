## WEIGHT PAINT (ROADMAP 72): the skin weights of a skinned character, painted by a brush on the mesh.
## Pure model + brush + heat colours + sidecar file; main.gd does the mouse, the undo step and the ribbon.
##   SkinPaint.read(meshes, skeleton)     -> model: the weights of every surface, each vertex fitted (sum 1, at most 4)
##   SkinPaint.refresh(model)             -> the skinned positions of the current pose (where the brush lands)
##   SkinPaint.pick(model, mouse, cam)    -> the point of the skin under the mouse (or null)
##   SkinPaint.paint(s, pos, c, r, bind, strength, mode) -> the vertices the brush changed (add / subtract / smooth)
##   SkinPaint.apply(model, heat_bind)    -> the meshes get the weights; heat_bind >= 0 colours them by that bone (Tok colours)
##   SkinPaint.save / load_into           -> user://weights/<key>.weights.json: the painted weights, float bits in base64
## The model holds packed arrays copy-on-write: a paint writes new arrays, so an undo snapshot keeps the old ones.
class_name SkinPaint
extends RefCounted

const DIR := "user://weights"
const FORMAT := "kine-skin-weights"
const MAX_INFL := 4   # at most four bones move one vertex (the GPU's skinning limit the mannequin already uses)


## the sidecar file of a character key ("mannequin"): one per character, never the user's source file
static func path(key: String) -> String:
	return "%s/%s.weights.json" % [DIR, key.replace("/", "_").replace("\\", "_").replace(":", "_")]


## every surface of the given meshes, as one list (pieces that share a surface share its entry). Weights are fitted on
## the way in: sum 1 and at most MAX_INFL per vertex. model: {"sk", "skin", "surfs": [...], "pieces": [{"mi", "map"}], "heat"}
static func read(meshes: Array, sk: Skeleton3D) -> Dictionary:
	var model := {"sk": sk, "skin": null, "surfs": [], "pieces": [], "heat": -1, "heat_mat": null}
	for mi in meshes:
		var m := mi as MeshInstance3D
		if model["skin"] == null:
			model["skin"] = m.skin
		var map := PackedInt32Array()
		for si in m.mesh.get_surface_count():
			var arr: Array = m.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var k := _find(model["surfs"], verts)
			if k < 0:
				var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
				var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
				var per := bones.size() / maxi(verts.size(), 1)
				var s := {"verts": verts, "per": per, "bones": bones.duplicate(), "w": w.duplicate(), "tris": PackedInt32Array(), "adj": [], "pos": PackedVector3Array()}
				var nb: PackedInt32Array = s["bones"]
				var nw: PackedFloat32Array = s["w"]
				for i in verts.size():
					var fit := _fit(s, i, _infl(s, i), -1)
					for q in per:
						nb[i * per + q] = fit["b"][q]
						nw[i * per + q] = fit["w"][q]
				s["bones"] = nb
				s["w"] = nw
				model["surfs"].append(s)
				k = model["surfs"].size() - 1
			var ix = arr[Mesh.ARRAY_INDEX]
			if ix != null:
				var sk_s: Dictionary = model["surfs"][k]
				var tt: PackedInt32Array = sk_s["tris"]
				tt.append_array(ix)
				sk_s["tris"] = tt   # written back: a nested append would change a copy
			map.append(k)
		model["pieces"].append({"mi": m, "map": map})
	for s in model["surfs"]:
		s["adj"] = _adjacency(s)
	return model


static func _find(surfs: Array, verts: PackedVector3Array) -> int:
	for k in surfs.size():
		if (surfs[k]["verts"] as PackedVector3Array) == verts:
			return k
	return -1


## the vertex's influences as bone -> weight (only the ones above zero)
static func _infl(s: Dictionary, i: int) -> Dictionary:
	var out := {}
	var per: int = s["per"]
	var b: PackedInt32Array = s["bones"]
	var w: PackedFloat32Array = s["w"]
	for q in per:
		var x := w[i * per + q]
		if x > 0.0:
			out[b[i * per + q]] = float(out.get(b[i * per + q], 0.0)) + x
	return out


## the weight one bone has on vertex i, read from the arrays given
static func _w_of(b: PackedInt32Array, w: PackedFloat32Array, per: int, i: int, bone: int) -> float:
	var out := 0.0
	for q in per:
		if b[i * per + q] == bone:
			out += w[i * per + q]
	return out


## the influences cut to MAX_INFL (the bone named in keep stays if it is there), scaled to sum 1.
## Returns {"b": PackedInt32Array, "w": PackedFloat32Array} of length per, zero-padded
static func _fit(s: Dictionary, _i: int, infl: Dictionary, keep: int) -> Dictionary:
	var keys := infl.keys()
	keys.sort_custom(func(a, c): return infl[a] > infl[c] or (infl[a] == infl[c] and a < c))
	if keys.size() > MAX_INFL:
		var kept := []
		if keep >= 0 and infl.has(keep):
			kept.append(keep)
		for k in keys:
			if kept.size() >= MAX_INFL:
				break
			if not kept.has(k):
				kept.append(k)
		keys = kept
		keys.sort_custom(func(a, c): return infl[a] > infl[c] or (infl[a] == infl[c] and a < c))
	var total := 0.0
	for k in keys:
		total += float(infl[k])
	var per: int = s["per"]
	var out := {"b": PackedInt32Array(), "w": PackedFloat32Array()}
	out["b"].resize(per)
	out["w"].resize(per)
	for q in per:
		if q < keys.size() and total > 0.0:
			out["b"][q] = keys[q]
			out["w"][q] = float(float(infl[keys[q]]) / total)
	return out


## the neighbours of every vertex (through the triangles), for the smooth brush
static func _adjacency(s: Dictionary) -> Array:
	var sets := []
	for i in s["verts"].size():
		sets.append({})
	var ix: PackedInt32Array = s["tris"]
	for t in range(0, ix.size() - 2, 3):
		var a := ix[t]
		var c := ix[t + 1]
		var d := ix[t + 2]
		for pr in [[a, c], [c, d], [d, a], [c, a], [d, c], [a, d]]:
			sets[pr[0]][pr[1]] = true
	var out := []
	for st in sets:
		out.append(PackedInt32Array(st.keys()))
	return out


## the skeleton bone a skin bind drives. An imported skin often leaves the bone index at -1 and names the bone instead
static func bind_bone(skin: Skin, sk: Skeleton3D, k: int) -> int:
	var b := skin.get_bind_bone(k)
	return b if b >= 0 else sk.find_bone(skin.get_bind_name(k))


## where every vertex of the pose is now: the skin's bind poses through the skeleton, in world space
static func refresh(model: Dictionary) -> void:
	var sk: Skeleton3D = model["sk"]
	var skin: Skin = model["skin"]
	if sk == null or skin == null:
		return
	var mats := []
	for k in skin.get_bind_count():
		mats.append(sk.get_bone_global_pose(bind_bone(skin, sk, k)) * skin.get_bind_pose(k))
	for s in model["surfs"]:
		var per: int = s["per"]
		var b: PackedInt32Array = s["bones"]
		var w: PackedFloat32Array = s["w"]
		var v: PackedVector3Array = s["verts"]
		var out := PackedVector3Array()
		out.resize(v.size())
		for i in v.size():
			var p := Vector3.ZERO
			for q in per:
				var x := w[i * per + q]
				if x > 0.0:
					p += (mats[b[i * per + q]] as Transform3D) * v[i] * x
			out[i] = sk.global_transform * p
		s["pos"] = out


## the skin point under the mouse (nearest hit over every surface), or null when the mouse is off the body
static func pick(model: Dictionary, mouse: Vector2, cam: Camera3D):
	var o := cam.project_ray_origin(mouse)
	var to := o + cam.project_ray_normal(mouse) * 1000.0
	var best := INF
	var hit = null
	for s in model["surfs"]:
		var pos: PackedVector3Array = s["pos"]
		var ix: PackedInt32Array = s["tris"]
		if pos.size() == 0:
			continue
		for t in range(0, ix.size() - 2, 3):
			var r = Geometry3D.segment_intersects_triangle(o, to, pos[ix[t]], pos[ix[t + 1]], pos[ix[t + 2]])
			if r != null and o.distance_to(r) < best:
				best = o.distance_to(r)
				hit = r
	return hit


## ONE brush dab at centre c on the skin positions pos (of surface s). The brush is round: the weight it moves falls
## off as (1 - d/radius)^2, so the centre gets the full strength and the rim none. Only vertices inside the radius
## are touched; the rest keep their bits. add: the bone gains; subtract: it loses; smooth: it moves toward the mean of
## its neighbours. Every touched vertex is fitted again (sum 1, at most MAX_INFL). Returns the changed vertex indices.
static func paint(s: Dictionary, pos: PackedVector3Array, c: Vector3, radius: float, bind: int, strength: float, mode: String) -> PackedInt32Array:
	var changed := PackedInt32Array()
	var per: int = s["per"]
	var sb: PackedInt32Array = s["bones"]
	var sw: PackedFloat32Array = s["w"]
	var nb: PackedInt32Array = sb.duplicate()
	var nw: PackedFloat32Array = sw.duplicate()
	for i in pos.size():
		var d := pos[i].distance_to(c)
		if d >= radius:
			continue
		var f := pow(1.0 - d / radius, 2.0)
		if f <= 0.0:
			continue
		var infl := _infl(s, i)
		var cur := float(infl.get(bind, 0.0))
		var step := strength * f
		var target := cur
		if mode == "add":
			target = cur + step
		elif mode == "subtract":
			target = maxf(0.0, cur - step)
		else:
			var adj: PackedInt32Array = s["adj"][i]
			var mean := 0.0
			for j in adj:
				mean += _w_of(sb, sw, per, j, bind)
			if adj.size() > 0:
				mean /= adj.size()
			target = lerpf(cur, mean, clampf(step, 0.0, 1.0))
		if target == cur:
			continue
		if target > 0.0:
			infl[bind] = target
		else:
			infl.erase(bind)
		if infl.is_empty():
			continue   # subtract took everything: the vertex keeps what it had
		var fit := _fit(s, i, infl, bind if target > cur else -1)
		for q in per:
			nb[i * per + q] = fit["b"][q]
			nw[i * per + q] = fit["w"][q]
		changed.append(i)
	s["bones"] = nb
	s["w"] = nw
	return changed


## the Tok colour of a weight: grid (none) -> accent (half) -> focus (all)
static func heat(v: float) -> Color:
	var t := clampf(v, 0.0, 1.0)
	var lo := Tok.c("grid")
	var mid := Tok.c("accent")
	var hi := Tok.c("focus")
	return lo.lerp(mid, t * 2.0) if t < 0.5 else mid.lerp(hi, (t - 0.5) * 2.0)


## the meshes show the model's weights. heat_bind >= 0: each vertex is coloured by that bone's weight (Tok colours) and
## the meshes are drawn with vertex colour; -1: the character as it was (its own material)
static func apply(model: Dictionary, heat_bind := -1) -> void:
	model["heat"] = heat_bind
	if heat_bind >= 0 and model["heat_mat"] == null:
		var hm := StandardMaterial3D.new()
		hm.vertex_color_use_as_albedo = true
		hm.roughness = 0.7
		model["heat_mat"] = hm
	for p in model["pieces"]:
		var mi: MeshInstance3D = p["mi"]
		var old := mi.mesh as ArrayMesh
		if heat_bind >= 0 and not p.has("mat"):
			p["mat"] = mi.material_override
		var am := ArrayMesh.new()
		for si in old.get_surface_count():
			var arr: Array = old.surface_get_arrays(si)
			var s: Dictionary = model["surfs"][p["map"][si]]
			arr[Mesh.ARRAY_BONES] = s["bones"]
			arr[Mesh.ARRAY_WEIGHTS] = s["w"]
			arr[Mesh.ARRAY_COLOR] = null
			if heat_bind >= 0:
				var cols := PackedColorArray()
				cols.resize((s["verts"] as PackedVector3Array).size())
				for i in cols.size():
					cols[i] = heat(_w_of(s["bones"], s["w"], s["per"], i, heat_bind))
				arr[Mesh.ARRAY_COLOR] = cols
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, old.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
			am.surface_set_material(si, model["heat_mat"] if heat_bind >= 0 else old.surface_get_material(si))
		mi.mesh = am
		mi.material_override = model["heat_mat"] if heat_bind >= 0 else p.get("mat", mi.material_override)   # never heat: keeps its own (the body's skin)


## the undo copy: the packed arrays of every surface (copy-on-write, so holding them is a snapshot)
static func snapshot(model: Dictionary) -> Array:
	var out := []
	for s in model.get("surfs", []):
		out.append([s["bones"], s["w"]])
	return out


static func restore(model: Dictionary, snap: Array) -> bool:
	if snap.size() != model["surfs"].size():
		return false
	# an undo step that never touched the weights (every drag, key, add and remove carries the snapshot) must leave the
	# meshes alone: apply() rebuilds every piece from its own arrays, which re-packs the normals (1 LSB of the drawn skin
	# off) and throws away the corrective shapes' meshes. Only a real change is applied.
	var changed := false
	for k in snap.size():
		if model["surfs"][k]["bones"] != snap[k][0] or model["surfs"][k]["w"] != snap[k][1]:
			changed = true
		model["surfs"][k]["bones"] = snap[k][0]
		model["surfs"][k]["w"] = snap[k][1]
	if changed:
		apply(model, model["heat"])
	return changed


## the painted weights as the sidecar file: every float and int as its raw bytes in base64, so a load is bit-for-bit
static func save(model: Dictionary, key: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var surfs := []
	for s in model["surfs"]:
		surfs.append({"verts": (s["verts"] as PackedVector3Array).size(), "per": s["per"],
			"bones": Marshalls.raw_to_base64((s["bones"] as PackedInt32Array).to_byte_array()),
			"w": Marshalls.raw_to_base64((s["w"] as PackedFloat32Array).to_byte_array())})
	var f := FileAccess.open(path(key), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"format": FORMAT, "version": 1, "key": key, "surfaces": surfs}))
	f.close()
	return true


## SBUG2 (Nick: "the body starts dissolving while moving and leaving parts behind, stretched"). The sidecar was applied
## unchecked: a user's weights.json with the right forearm's weight added over the whole body (1498 + 3765 vertices,
## feet included, 840 + 1875 influences more than 0.35 m from their bone) looks right in the stand pose and tears the
## body apart the moment that forearm moves (edge stretch x28-x40 in the walk). A real skin never gives a bone a share
## of a vertex far from it: the mannequin's farthest influence (weight >= REACH_MIN_W) is 0.27 m from its bone's rest
## segment (spine_01 on a shoulder vertex). A set with an influence past MAX_REACH (0.5 m, about twice that on a 1.8 m
## figure) is not a painted skin, it is a broken file: it is refused (and set aside by quarantine()), not applied.
const MAX_REACH := 0.5
const REACH_MIN_W := 0.05


## the rest segment of every bind in mesh space: its head to its first child bone's head (a leaf: a point)
static func bind_segments(skin: Skin, sk: Skeleton3D) -> Array:
	var head := []
	var bone := []
	for q in skin.get_bind_count():
		head.append(skin.get_bind_pose(q).affine_inverse().origin)
		bone.append(bind_bone(skin, sk, q))
	var out := []
	for q in head.size():
		var tail: Vector3 = head[q]
		for r in head.size():
			if bone[q] >= 0 and sk.get_bone_parent(bone[r]) == bone[q]:
				tail = head[r]
				break
		out.append([head[q], tail])
	return out


## the farthest influence (weight >= REACH_MIN_W) of the given weights from its bone's rest segment:
## {"worst": metres, "bind": its bind, "far": influences past MAX_REACH}. got: [[bones, w]] per surface of the model
static func reach(model: Dictionary, got: Array) -> Dictionary:
	var out := {"worst": 0.0, "bind": -1, "far": 0}
	var skin: Skin = model["skin"]
	if skin == null or model["sk"] == null:
		return out
	var segs := bind_segments(skin, model["sk"])
	for k in got.size():
		var s: Dictionary = model["surfs"][k]
		var v: PackedVector3Array = s["verts"]
		var per: int = s["per"]
		var b: PackedInt32Array = got[k][0]
		var w: PackedFloat32Array = got[k][1]
		for i in v.size():
			for q in per:
				if w[i * per + q] < REACH_MIN_W:
					continue
				var bi: int = b[i * per + q]
				if bi < 0 or bi >= segs.size():
					out["far"] += 1
					continue
				var sg: Array = segs[bi]
				var d: float = v[i].distance_to(Geometry3D.get_closest_point_to_segment(v[i], sg[0], sg[1]))
				if d > out["worst"]:
					out["worst"] = d
					out["bind"] = bi
				if d > MAX_REACH:
					out["far"] += 1
	return out


## a refused sidecar is set aside, not deleted: <file>.rejected. Returns where it went ("" when there was no file)
static func quarantine(key: String) -> String:
	var src := ProjectSettings.globalize_path(path(key))
	if not FileAccess.file_exists(src):
		return ""
	var dst := src + ".rejected"
	if FileAccess.file_exists(dst):
		DirAccess.remove_absolute(dst)
	return dst if DirAccess.rename_absolute(src, dst) == OK else ""


## the sidecar's weights onto a model read from the same character. False (model untouched) when there is no file,
## or the file is for another character (surface count, vertex count or influence count differ), or its weights give a
## bone a share of a vertex farther than MAX_REACH from it (model["rejected"] then says so)
static func load_into(model: Dictionary, key: String) -> bool:
	if not FileAccess.file_exists(path(key)):
		return false
	var d = JSON.parse_string(FileAccess.get_file_as_string(path(key)))
	if typeof(d) != TYPE_DICTIONARY or d.get("format", "") != FORMAT or not d.has("surfaces"):
		return false
	var surfs: Array = d["surfaces"]
	if surfs.size() != model["surfs"].size():
		return false
	var got := []
	for k in surfs.size():
		var s: Dictionary = model["surfs"][k]
		var e: Dictionary = surfs[k]
		var b := Marshalls.base64_to_raw(String(e.get("bones", ""))).to_int32_array()
		var w := Marshalls.base64_to_raw(String(e.get("w", ""))).to_float32_array()
		var n: int = (s["verts"] as PackedVector3Array).size() * int(s["per"])
		if int(e.get("verts", -1)) != (s["verts"] as PackedVector3Array).size() or int(e.get("per", -1)) != int(s["per"]) or b.size() != n or w.size() != n:
			return false
		got.append([b, w])
	model.erase("rejected")
	var rc := reach(model, got)
	if int(rc["far"]) > 0:
		model["rejected"] = "%d influences farther than %.2f m from their bone (worst %.2f m, on %s)" % [int(rc["far"]), MAX_REACH, float(rc["worst"]), (model["skin"] as Skin).get_bind_name(int(rc["bind"]))]
		return false
	for k in got.size():
		model["surfs"][k]["bones"] = got[k][0]
		model["surfs"][k]["w"] = got[k][1]
	return true
