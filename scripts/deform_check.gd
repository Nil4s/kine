## deform_check.gd - "WILL THIS DEFORM?" (ROADMAP_400 F14): one verdict on how the skinned body bends, with the 3 worst spots.
## Each major joint (shoulder, elbow, wrist, hip, knee, spine, neck, both sides) is swept through its range from
## data/body_limits.json (read only) on a scratch Body: 60% and 100% of each end of each axis. The mesh is skinned at every
## step (the same linear-blend skinning as SkinPaint.refresh, on the vertices the joint moves) and every moved vertex is scored:
##   thick    = 1 - r_pose / r_rest, r = the vertex's distance to the axis of its main bone. A pinched crease and a candy-wrapper
##              twist both pull the skin onto the bone axis, so one number reads both (the axis "twist" names the wrapper).
##              Edges that shrink (1 - shortest edge ratio of the one-ring) count the same way ("squeeze").
##   stretch  = (longest one-ring edge ratio - 1) / 1.5: skin torn apart by weights that do not follow the bones.
##   pen      = how far a vertex that moves rigidly with the joint (weight >= 0.9) goes into the PARENT limb's core (0.7 of its
##              median rest radius), as a share of that core: interpenetration of neighbouring parts.
## The result is the 3 worst spots (one per joint family), each with joint, angle and a number. The real body and the scene are
## never edited: the skeleton is posed from a scratch Body and put back by the restore callable.
## Real ranges the sweep ends on: elbow flexion 145 deg, knee 145 deg, hip flexion 120 deg (AAOS "Joint Motion", Soucie 2011
## for the healthy-adult elbow/knee/hip means); these are what body_limits.json holds, so the sweep tests the human range.
class_name DeformCheck
extends RefCounted

const FRACS := [0.6, 1.0]
const MIN_R := 0.012      # m: thickness is read where the skin is at least 1.2 cm off the bone axis at rest
const MIN_EDGE := 0.002   # m: edges shorter than 2 mm at rest are skipped (their ratio is noise)
const OK_BELOW := 0.30    # the verdict is "deforms OK" while the worst spot scores under this (30% thickness lost)
const FAMILY := {"upperarm": "shoulder", "lowerarm": "elbow", "hand": "wrist", "thigh": "hip", "calf": "knee"}
const KINDS := ["thick", "stretch", "pen"]


## the joints swept: {"id", "bones", "fam", "side"}
static func entries() -> Array:
	var out := []
	for sd in ["_l", "_r"]:
		for j in ["upperarm", "lowerarm", "hand", "thigh", "calf"]:
			out.append({"id": j + sd, "bones": [j + sd], "fam": FAMILY[j], "side": "left" if sd == "_l" else "right"})
	out.append({"id": "spine", "bones": ["spine_01", "spine_02", "spine_03"], "fam": "spine", "side": ""})
	out.append({"id": "neck_01", "bones": ["neck_01"], "fam": "neck", "side": ""})
	return out


static func _dseg(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0
	if l2 > 1e-12:
		t = clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _pose(G: Body, skel: Skeleton3D, idx: Dictionary, angs: Dictionary) -> void:
	for j in G.ang:
		G.ang[j] = Vector3.ZERO
	for j in angs:
		G.ang[j] = angs[j]
	G.fk()
	Overlays.pose_skeleton(skel, idx, G)


static func _mats(skin: Skin, sk: Skeleton3D, bob: PackedInt32Array) -> Array:
	var out := []
	for k in skin.get_bind_count():
		out.append(sk.get_bone_global_pose(bob[k]) * skin.get_bind_pose(k))
	return out


static func _origins(sk: Skeleton3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var gt := sk.global_transform
	for b in sk.get_bone_count():
		out.append(gt * sk.get_bone_global_pose(b).origin)
	return out


static func _skin_at(s: Dictionary, i: int, mats: Array, gt: Transform3D) -> Vector3:
	var per: int = s["per"]
	var B: PackedInt32Array = s["bones"]
	var W: PackedFloat32Array = s["w"]
	var v: Vector3 = (s["verts"] as PackedVector3Array)[i]
	var p := Vector3.ZERO
	for q in per:
		var x := W[i * per + q]
		if x > 0.0:
			p += (mats[B[i * per + q]] as Transform3D) * v * x
	return gt * p


## the whole sweep. model = SkinPaint.read(...) (its weights are the ones tested). restore: called once at the end, puts the
## real body's pose back on the skeleton. Returns {"ok", "spots" (3 worst, one per joint family), "all", "poses", "ms", "verts"}
static func run(model: Dictionary, skel: Skeleton3D, idx: Dictionary, restore: Callable) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var skin: Skin = model["skin"]
	var G := Body.new()
	var bob := PackedInt32Array()
	for k in skin.get_bind_count():
		bob.append(SkinPaint.bind_bone(skin, skel, k))
	var nbone := skel.get_bone_count()
	var gt := skel.global_transform
	_pose(G, skel, idx, {})
	var mats := _mats(skin, skel, bob)
	var org0 := _origins(skel)
	# the segment of every bone: its origin to the origin of its child that continues the line from its parent
	var child := PackedInt32Array()
	child.resize(nbone)
	for b in nbone:
		child[b] = -1
		var kids := skel.get_bone_children(b)
		if kids.is_empty():
			continue
		var par := skel.get_bone_parent(b)
		var d0 := (org0[b] - org0[par]) if par >= 0 else Vector3.UP
		if d0.length() < 1e-6:
			d0 = Vector3.UP
		var bdot := -2.0
		for c in kids:
			var d := (org0[c] - org0[b]).normalized()
			var dt := d.dot(d0.normalized())
			if dt > bdot:
				bdot = dt
				child[b] = c
	# per surface at rest: the main bone of each vertex, the rest skin positions, the rest distance to the main bone's axis
	var surf := []
	var radii := {}   # bone -> [rest distances] (for the core radius of a parent limb)
	var nv := 0
	for s in model["surfs"]:
		var n := (s["verts"] as PackedVector3Array).size()
		nv += n
		var per: int = s["per"]
		var dom := PackedInt32Array()
		var domw := PackedFloat32Array()
		var rest := PackedVector3Array()
		var rr := PackedFloat32Array()
		dom.resize(n)
		domw.resize(n)
		rest.resize(n)
		rr.resize(n)
		for i in n:
			var bw := -1.0
			var bb := -1
			for q in per:
				var x: float = (s["w"] as PackedFloat32Array)[i * per + q]
				if x > bw:
					bw = x
					bb = bob[(s["bones"] as PackedInt32Array)[i * per + q]]
			dom[i] = bb
			domw[i] = maxf(bw, 0.0)
			rest[i] = _skin_at(s, i, mats, gt)
			var c := child[bb] if bb >= 0 else -1
			rr[i] = _dseg(rest[i], org0[bb], org0[c]) if c >= 0 else -1.0
			if c >= 0 and bw > 0.5:
				if not radii.has(bb):
					radii[bb] = []
				(radii[bb] as Array).append(rr[i])
		surf.append({"dom": dom, "domw": domw, "rest": rest, "rr": rr, "cur": rest.duplicate()})
	var core := {}
	for bb in radii:
		var a: Array = radii[bb]
		a.sort()
		core[bb] = 0.7 * float(a[a.size() / 2])
	# the sweep
	var poses := []
	var best := {}   # "entry|kind" -> {sev, surf, i, pose, val}
	for e in entries():
		var ids := PackedInt32Array()
		var ok_e := true
		for bn in e["bones"]:
			if not idx.has(bn) or int(idx[bn]) < 0:
				ok_e = false
			else:
				ids.append(idx[bn])
		if not ok_e:
			continue
		# bones the joint moves: its subtree
		var moved := {}
		var stack := Array(ids)
		while not stack.is_empty():
			var b: int = stack.pop_back()
			moved[b] = true
			for c in skel.get_bone_children(b):
				stack.append(c)
		var par := skel.get_bone_parent(ids[0])
		var anc := []
		if par >= 0:
			anc.append(par)
			var pc := child[par]
			if pc >= 0 and org0[par].distance_to(org0[pc]) < 0.15 and skel.get_bone_parent(par) >= 0:
				anc.append(skel.get_bone_parent(par))
		# the vertices the joint moves
		var aff := []
		for si in model["surfs"].size():
			var s: Dictionary = model["surfs"][si]
			var per: int = s["per"]
			var lst := PackedInt32Array()
			for i in (s["verts"] as PackedVector3Array).size():
				for q in per:
					if (s["w"] as PackedFloat32Array)[i * per + q] > 0.001 and moved.has(bob[(s["bones"] as PackedInt32Array)[i * per + q]]):
						lst.append(i)
						break
			aff.append(lst)
		var lim: Dictionary = G.lim[e["bones"][0]]
		for axis in ["bend", "side", "twist"]:
			var r: Vector2 = lim[axis]
			for ext in [r.x, r.y]:
				if absf(ext) < 5.0:
					continue
				for f in FRACS:
					var deg: float = ext * f
					var angs := {}
					for bn in e["bones"]:
						angs[bn] = Vector3(deg if axis == "bend" else 0.0, deg if axis == "side" else 0.0, deg if axis == "twist" else 0.0)
					_pose(G, skel, idx, angs)
					var pi := poses.size()
					poses.append({"entry": e["id"], "fam": e["fam"], "side": e["side"], "axis": axis, "deg": deg, "angs": angs})
					mats = _mats(skin, skel, bob)
					var org := _origins(skel)
					for si in model["surfs"].size():
						var s: Dictionary = model["surfs"][si]
						var sd: Dictionary = surf[si]
						var cur: PackedVector3Array = sd["cur"]
						var rest: PackedVector3Array = sd["rest"]
						var dom: PackedInt32Array = sd["dom"]
						var rr: PackedFloat32Array = sd["rr"]
						var domw: PackedFloat32Array = sd["domw"]
						var lst: PackedInt32Array = aff[si]
						for i in lst:
							cur[i] = _skin_at(s, i, mats, gt)
						var adj: Array = s["adj"]
						for i in lst:
							var d := dom[i]
							var p := cur[i]
							var thick := 0.0
							var stretch := 0.0
							var pen := 0.0
							var penv := 0.0
							var c := child[d] if d >= 0 else -1
							if c >= 0 and rr[i] >= MIN_R:
								thick = 1.0 - _dseg(p, org[d], org[c]) / rr[i]
							var mn := 1.0
							var mx := 1.0
							for j in (adj[i] as PackedInt32Array):
								var l0 := rest[i].distance_to(rest[j])
								if l0 > MIN_EDGE:
									var ratio := p.distance_to(cur[j]) / l0
									mn = minf(mn, ratio)
									mx = maxf(mx, ratio)
							var squeeze := 1.0 - mn
							var tv := maxf(thick, squeeze)
							stretch = (mx - 1.0) / 1.5
							if moved.has(d) and domw[i] >= 0.9:
								for a in anc:
									if not core.has(a) or child[a] < 0:
										continue
									var dr := _dseg(rest[i], org0[a], org0[child[a]])
									if dr >= core[a]:
										var dd: float = core[a] - _dseg(p, org[a], org[child[a]])
										if dd > 0.0 and dd / core[a] > pen:
											pen = dd / core[a]
											penv = dd
							for k in 3:
								var sev: float = [tv, stretch, pen][k]
								var key: String = e["id"] + "|" + KINDS[k]
								if sev > 0.0 and (not best.has(key) or sev > best[key]["sev"]):
									var val: float = [(thick if thick >= squeeze else squeeze), mx, penv][k]
									best[key] = {"sev": sev, "surf": si, "i": i, "pose": pi, "kind": KINDS[k], "val": val, "squeeze": squeeze > thick, "dom": d, "entry": e["id"],
										"fam": e["fam"], "side": e["side"], "axis": axis, "deg": deg, "angs": angs, "region": skel.get_bone_name(d)}
					for si in model["surfs"].size():
						var cur2: PackedVector3Array = surf[si]["cur"]
						var rest2: PackedVector3Array = surf[si]["rest"]
						for i in (aff[si] as PackedInt32Array):
							cur2[i] = rest2[i]
	# the worst per joint family, then the 3 worst families
	var all := best.values()
	all.sort_custom(func(a, b): return a["sev"] > b["sev"])
	var spots := []
	var seen := {}
	for c in all:
		if seen.has(c["fam"]):
			continue
		seen[c["fam"]] = true
		var sp: Dictionary = c.duplicate()
		spots.append(sp)
		if spots.size() >= 3:
			break
	for sp in spots:   # where the vertex is in its worst pose
		_pose(G, skel, idx, sp["angs"])
		mats = _mats(skin, skel, bob)
		sp["pos"] = _skin_at(model["surfs"][sp["surf"]], sp["i"], mats, gt)
		sp["text"] = describe(sp)
	restore.call()
	return {"ok": all.is_empty() or float(all[0]["sev"]) < OK_BELOW, "spots": spots, "all": all, "poses": poses.size(), "ms": Time.get_ticks_msec() - t0, "verts": nv}


## "left elbow at 145 deg: the crease loses 46% of its thickness"
static func describe(sp: Dictionary) -> String:
	var who: String = (str(sp["side"]) + " " if sp["side"] != "" else "") + str(sp["fam"])
	var at := ""
	match sp["axis"]:
		"bend":
			at = "%s at %.0f°" % [who, sp["deg"]]
		"side":
			at = "%s swung sideways to %.0f°" % [who, sp["deg"]]
		_:
			at = "%s twisted %.0f°" % [who, sp["deg"]]
	var reg := nice(str(sp["region"]))
	match sp["kind"]:
		"thick":
			if sp["squeeze"]:
				return "%s: the %s skin squeezes %.0f%% shorter" % [at, reg, 100.0 * float(sp["val"])]
			if sp["axis"] == "twist":
				return "%s: the %s skin twists to a wrapper, %.0f%% of its thickness gone" % [at, reg, 100.0 * float(sp["val"])]
			return "%s: the %s crease loses %.0f%% of its thickness" % [at, reg, 100.0 * float(sp["val"])]
		"stretch":
			return "%s: the %s skin stretches %.1fx (weights do not follow the bones)" % [at, reg, float(sp["val"])]
	return "%s: the %s skin goes %.1f cm into the limb above" % [at, reg, 100.0 * float(sp["val"])]


static func nice(bone: String) -> String:
	var m := {"upperarm": "upper arm", "lowerarm": "forearm", "calf": "shin", "thigh": "thigh", "hand": "hand", "neck": "neck", "spine": "torso", "clavicle": "shoulder", "pelvis": "pelvis", "head": "head", "foot": "foot"}
	var base := bone
	for sfx in ["_l", "_r"]:
		if base.ends_with(sfx):
			base = base.left(base.length() - 2)
	for k in m:
		if base.begins_with(k):
			return m[k]
	return base.replace("_", " ")


## the verdict line
static func verdict(res: Dictionary) -> String:
	if res["ok"]:
		return "deforms OK: every joint bends through its range with the skin holding (worst spot under %.0f%%)" % (OK_BELOW * 100.0)
	return "%d worst spots" % res["spots"].size()
