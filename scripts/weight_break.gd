## "Check: weights broke here" (ROADMAP_400 H24): over the whole animation, the vertex with the worst weight problem and the frame
## where it is worst. Reads the SkinPaint model (the weights as they are in memory, painted or not) and the skeleton at each frame.
## Four problems, each scored so that 1.0 means "visibly broken" (the vertex's score is the largest, at its worst frame):
##   stretch: an edge of the vertex is longer (or shorter) than at rest. 1.5x or 1/1.5 = 1.0 (a spike pulled by a wrong bone)
##   pop:     the vertex's offset from its own bone jumps between two frames. 3 cm in one frame = 1.0
##   far:     the vertex takes weight from a bone far from it: weight x rest distance to that bone. 12 cm = 1.0
##            (a shoulder vertex 30% on the upper arm 4 cm away is 0.1; a forearm vertex 60% on the spine is over 1)
##   sum:     the weights do not add to 1 (1e-3 off = 1.0) or more than 4 bones move it
## Rigid vertices (all weight on one bone, every neighbour on the same bone) cannot stretch or pop, so only the others are
## skinned each frame: a 140-frame scene of the 8546-vertex mannequin stays far inside 10 s.
class_name WeightBreak
extends RefCounted

const STRETCH_AT := 0.5     # edge ratio 1.5 = score 1
const POP_AT := 0.03        # metres per frame
const FAR_AT := 0.12        # weight x metres
const TOP := 10
const EDGE_FLOOR := 0.02   # metres: shorter rest edges are measured against 2 cm


## where the rest vertex v is from the bone's segment (its origin to its children's origins), in the skin's rest space
static func _seg_dist(v: Vector3, a: Vector3, ends: Array) -> float:
	var best := v.distance_to(a)
	for b in ends:
		var ab: Vector3 = b - a
		var l2 := ab.length_squared()
		var t := clampf((v - a).dot(ab) / l2, 0.0, 1.0) if l2 > 1e-10 else 0.0
		best = minf(best, v.distance_to(a + ab * t))
	return best


## "lowerarm_l" -> "left forearm"
static func words(bone_name: String) -> String:
	var n := bone_name
	var side := ""
	if n.ends_with("_l") or n.ends_with("_r"):
		side = "left " if n.ends_with("_l") else "right "
		n = n.substr(0, n.length() - 2)
	n = n.replace("lowerarm", "forearm").replace("upperarm", "upper arm").replace("calf", "shin").replace("thigh", "thigh")
	n = n.replace("_0", " ").replace("_", " ").strip_edges()
	return side + n


## Scan `frames` frames. pose_fn.call(f) must put the skeleton in frame f. Returns {"top": [...], "frames", "ms", "active", "verts"}.
## Each entry: {"id", "surf", "vi", "frame", "score", "kind", "stretch", "pop", "far", "sum", "bone", "bone_name", "pull_bone", "pull_name",
## "pull_w", "pos"} - sorted worst first.
static func scan(model: Dictionary, frames: int, pose_fn: Callable) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var sk: Skeleton3D = model["sk"]
	var skin: Skin = model["skin"]
	var nb := skin.get_bind_count()
	# ---- rest geometry of the bones: origin and the origins of the children (as the skin binds them)
	var bone_of := PackedInt32Array()
	var bind_of := {}
	for k in nb:
		var bi := SkinPaint.bind_bone(skin, sk, k)
		bone_of.append(bi)
		bind_of[bi] = k
	var org := []
	var ends := []
	for k in nb:
		org.append((skin.get_bind_pose(k) as Transform3D).affine_inverse().origin)
		ends.append([])
	for k in nb:
		var par := sk.get_bone_parent(bone_of[k]) if bone_of[k] >= 0 else -1
		while par >= 0 and not bind_of.has(par):
			par = sk.get_bone_parent(par)
		if par >= 0:
			ends[int(bind_of[par])].append(org[k])
	# ---- the active vertices, edges and static scores, per surface
	var act_s := PackedInt32Array()   # surface of each active vertex
	var act_v := PackedInt32Array()   # vertex index in its surface
	var act_id := PackedInt32Array()  # the vertex number across all surfaces
	var lab := PackedInt32Array()     # the bind of its own bone (nearest influence)
	var stat := PackedFloat32Array()  # far / sum score
	var stat_kind := PackedStringArray()
	var far_bind := PackedInt32Array()
	var far_w := PackedFloat32Array()
	var sum_off := PackedFloat32Array()
	var rest: Array = []   # the rest position of each active vertex
	var wb: Array = []     # [bind0..3], flat per active vertex
	var ww: Array = []
	var ea := PackedInt32Array()
	var eb := PackedInt32Array()
	var el := PackedFloat32Array()
	var offset := 0
	var total := 0
	var wper := 1
	for s0 in model["surfs"]:
		wper = maxi(wper, int(s0["per"]))
	for si in model["surfs"].size():
		var s: Dictionary = model["surfs"][si]
		var per: int = s["per"]
		var verts: PackedVector3Array = s["verts"]
		var b: PackedInt32Array = s["bones"]
		var w: PackedFloat32Array = s["w"]
		var adj: Array = s["adj"]
		var n := verts.size()
		total += n
		var rigid := PackedInt32Array()
		rigid.resize(n)
		for i in n:
			rigid[i] = -1
			var one := -1
			for q in per:
				if w[i * per + q] > 0.0:
					if w[i * per + q] >= 0.999:
						one = b[i * per + q]
					break
			rigid[i] = one
		var remap := PackedInt32Array()
		remap.resize(n)
		remap.fill(-1)
		var want := PackedByteArray()
		want.resize(n)
		for i in n:
			if rigid[i] < 0:
				want[i] = 1
			for j in adj[i]:
				if rigid[i] < 0 or rigid[j] < 0 or rigid[i] != rigid[j]:
					want[i] = 1
					want[j] = 1
		for i in n:
			if want[i] == 0:
				continue
			remap[i] = act_s.size()
			act_s.append(si)
			act_v.append(i)
			act_id.append(offset + i)
			rest.append(verts[i])
			var tot := 0.0
			var cnt := 0
			var best_d := INF
			var best_k := -1
			var best_w := 0.0
			var far_pull := 0.0
			var far_k := -1
			var far_ww := 0.0
			for q in per:
				var x := w[i * per + q]
				wb.append(b[i * per + q] if x > 0.0 else 0)
				ww.append(x)
				if x > 0.0:
					tot += x
					cnt += 1
					var d := _seg_dist(verts[i], org[b[i * per + q]], ends[b[i * per + q]])
					if d < best_d - 1e-6 or (absf(d - best_d) <= 1e-6 and x > best_w):
						best_d = d
						best_k = b[i * per + q]
						best_w = x
			for q in range(per, wper):
				wb.append(0)
				ww.append(0.0)
			for q in per:
				var x := w[i * per + q]
				if x > 0.0 and b[i * per + q] != best_k:
					var pull := x * _seg_dist(verts[i], org[b[i * per + q]], ends[b[i * per + q]])
					if pull > far_pull:
						far_pull = pull
						far_k = b[i * per + q]
						far_ww = x
			lab.append(best_k if best_k >= 0 else 0)
			far_bind.append(far_k)
			far_w.append(far_ww)
			var sc_far := far_pull / FAR_AT
			var off := absf(tot - 1.0)
			var sc_sum := 0.0
			if off > 1e-3:
				sc_sum = off / 1e-3
			if cnt > SkinPaint.MAX_INFL:
				sc_sum = maxf(sc_sum, 1.0 + cnt - SkinPaint.MAX_INFL)
			sum_off.append(off)
			if sc_sum > sc_far:
				stat.append(sc_sum)
				stat_kind.append("sum")
			else:
				stat.append(sc_far)
				stat_kind.append("far")
		for i in n:
			if remap[i] < 0:
				continue
			for j in adj[i]:
				if j > i and remap[j] >= 0 and not (rigid[i] >= 0 and rigid[i] == rigid[j]):
					ea.append(remap[i])
					eb.append(remap[j])
					el.append(verts[i].distance_to(verts[j]))
		offset += n
	var na := act_s.size()
	var ne := ea.size()
	var best := PackedFloat32Array()
	best.resize(na)
	var best_f := PackedInt32Array()
	best_f.resize(na)
	var best_st := PackedFloat32Array()
	best_st.resize(na)
	var best_pop := PackedFloat32Array()
	best_pop.resize(na)
	var best_pos := PackedVector3Array()
	best_pos.resize(na)
	var pos := PackedVector3Array()
	pos.resize(na)
	var res_prev := PackedVector3Array()
	res_prev.resize(na)
	var st := PackedFloat32Array()
	st.resize(na)
	var mats: Array[Transform3D] = []
	mats.resize(nb)
	for f in frames:
		pose_fn.call(f)
		var gt := sk.global_transform
		for k in nb:
			mats[k] = gt * (sk.get_bone_global_pose(bone_of[k]) * skin.get_bind_pose(k))
		st.fill(0.0)
		for a in na:
			var v: Vector3 = rest[a]
			var p := Vector3.ZERO
			for q in wper:
				var x: float = ww[a * wper + q]
				if x > 0.0:
					p += mats[wb[a * wper + q]] * v * x
			pos[a] = p
		for e in ne:
			var l := (pos[ea[e]] - pos[eb[e]]).length()
			var rl: float = el[e]
			var r := 1.0
			if l > rl:
				r = maxf(1.0, l / maxf(rl, EDGE_FLOOR))   # a seam edge of 1 mm opening 2 cm is a seam, not a 20x stretch
			elif rl >= EDGE_FLOOR:
				r = rl / maxf(l, 0.005)
			var sc := (r - 1.0) / STRETCH_AT
			if sc > st[ea[e]]:
				st[ea[e]] = sc
			if sc > st[eb[e]]:
				st[eb[e]] = sc
		for a in na:
			var res: Vector3 = pos[a] - mats[lab[a]] * (rest[a] as Vector3)
			var pop := 0.0
			if f > 0:
				pop = (res - res_prev[a]).length() / POP_AT
			res_prev[a] = res
			var dyn := maxf(st[a], pop)
			var score := maxf(dyn, stat[a]) + 0.001 * (st[a] + pop)
			if score > best[a]:
				best[a] = score
				best_f[a] = f
				best_st[a] = st[a]
				best_pop[a] = pop
				best_pos[a] = pos[a]
	var order := range(na)
	order.sort_custom(func(x, y): return best[x] > best[y])
	var top := []
	for n in mini(TOP, na):
		var a: int = order[n]
		var kind := "stretch"
		var dyn_max := maxf(best_st[a], best_pop[a])
		if stat[a] >= dyn_max:
			kind = stat_kind[a]
		elif best_pop[a] > best_st[a]:
			kind = "pop"
		var ratio := 1.0 + best_st[a] * STRETCH_AT
		top.append({"id": act_id[a], "surf": act_s[a], "vi": act_v[a], "frame": best_f[a], "score": best[a], "kind": kind,
			"stretch": ratio, "pop_cm": best_pop[a] * POP_AT * 100.0, "far": stat[a] if stat_kind[a] == "far" else 0.0,
			"sum_off": sum_off[a], "bone": lab[a], "bone_name": skin.get_bind_name(lab[a]),
			"pull_bone": far_bind[a], "pull_name": skin.get_bind_name(far_bind[a]) if far_bind[a] >= 0 else "",
			"pull_w": far_w[a], "pos": best_pos[a]})
	return {"top": top, "frames": frames, "ms": Time.get_ticks_msec() - t0, "active": na, "edges": ne, "verts": total}


## the report sentence: "frame 37 (1.23 s), vertex 1402 on the left forearm: its edges stretch 3.1x; it takes 40% from the spine."
static func report(e: Dictionary, fps: float) -> String:
	var why := ""
	match e["kind"]:
		"stretch":
			why = "its edges stretch %.1fx" % e["stretch"]
		"pop":
			why = "it jumps %.1f cm from its bone in one frame" % e["pop_cm"]
		"far":
			why = "it is pulled by a bone far from it"
		"sum":
			why = "its weights add to %.3f (should be 1) or use more than 4 bones" % (1.0 + e["sum_off"])
	var s := "frame %d (%.2f s), vertex %d on the %s: %s" % [e["frame"], float(e["frame"]) / fps, e["id"], words(e["bone_name"]), why]
	if e["pull_bone"] >= 0 and e["pull_w"] >= 0.02:
		s += "; it takes %d%% from the %s" % [roundi(e["pull_w"] * 100.0), words(e["pull_name"])]
	return s + "."
