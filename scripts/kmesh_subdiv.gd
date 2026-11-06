class_name KMeshSubdiv
extends RefCounted
## A12 (docs/ROADMAP_400.md): Catmull-Clark subdivision, written from the paper (E. Catmull, J. Clark, "Recursively
## generated B-spline surfaces on arbitrary topological meshes", CAD 10(6), 1978) with semi-sharp creases after
## T. DeRose, M. Kass, T. Truong, "Subdivision surfaces in character animation", SIGGRAPH 1998.
## One level: every face gets a face point (its centroid), every edge an edge point, every vertex a new position; each
## n-gon becomes n quads (vertex, edge point, face point, edge point), so the result is all quads from level 1 on.
##   edge point:   smooth (a + b + f0 + f1) / 4;  sharp / boundary: the midpoint (a + b) / 2
##   vertex point: smooth (Q + 2R + (n - 3) S) / n  (Q = mean of the face points around it, R = mean of the edge
##                 midpoints, S = the old position, n = its valence);  2 sharp edges: crease (a + 6 S + b) / 8;
##                 3 or more sharp edges, or a boundary vertex on one face (a plane's corner): stays put
## Sharpness s per edge (DeRose): s >= 1 is sharp at this level, 0 < s < 1 blends smooth and sharp by s, and the children
## of a creased edge get s - 1, so s = 2 is sharp for two levels then smooth. INF = sharp forever. A vertex blends by the
## mean sharpness of its sharp edges. Boundary edges and edges with more than two faces are always sharp (the boundary rule).
## Attributes (A09) follow linearly: vert channels (vertex keeps, edge point = mean of the ends, face point = mean of the
## face), corner channels the same inside each face (UVs stay put on their face), face channels go to the 4 children,
## edge channels to the two halves (interior new edges get the default); the "crease" edge channel is the sharpness
## and goes down by 1 per level.

const CREASE := "crease"


## A new KMesh, `levels` times subdivided (`mesh` is not touched). `creases`: null = the mesh's "crease" edge channel when
## it has one (else all smooth); a float = that sharpness on every edge; a PackedFloat32Array = one per edge in
## mesh.edges() order; a Dictionary {Vector2i(a, b): sharpness} (either order).
static func subdivide(mesh: KMesh, levels := 1, creases = null) -> KMesh:
	# L60: no attribute channels and a uniform (or no) crease: the whole thing in C++ (KineKMeshNative), same result
	if KMeshNatDoor.on() and mesh.attrs.is_empty() and (creases == null or creases is float or creases is int):
		var nr: Dictionary = KMeshNatDoor.door().subdivide(mesh.verts, mesh.faces, maxi(levels, 0), -1.0 if creases == null else float(creases))
		var nout := KMesh.new()
		nout.normal_mode = mesh.normal_mode
		nout.auto_angle = mesh.auto_angle
		nout.verts = nr["verts"]
		nout.faces = nr["faces"]
		nout._apply_topo(nr)
		return nout
	var V := mesh.verts.duplicate()
	var nf := mesh.faces.size()
	var fs := PackedInt32Array()   # face starts into fv (size nf + 1)
	var fv := PackedInt32Array()   # the corners, face after face (= the KMesh corner order)
	fs.resize(nf + 1)
	for f in nf:
		fs[f] = fv.size()
		fv.append_array(mesh.faces[f])
	fs[nf] = fv.size()
	# the mesh's edges() order, to read and write the edge domain
	var src_edges := mesh.edges()
	var top := _edges(V.size(), fs, fv)
	var n_src := src_edges.size()
	var src_to_top := PackedInt32Array()   # mesh edge index -> our edge id
	src_to_top.resize(n_src)
	var nv0 := V.size()
	for i in n_src:
		var e: Vector2i = src_edges[i]
		src_to_top[i] = int(top["key"].get(e.x * nv0 + e.y, -1))
	var ne: int = (top["a"] as PackedInt32Array).size()
	var sharp := PackedFloat32Array()
	sharp.resize(ne)
	var cin = creases
	if cin == null and mesh.has_attr(CREASE) and mesh.attr_info(CREASE)["domain"] == KMesh.AD_EDGE and mesh.attr_info(CREASE)["type"] == TYPE_FLOAT:
		cin = mesh.attr_data(CREASE)
	if cin is float or cin is int:
		sharp.fill(float(cin))
	elif cin is PackedFloat32Array or cin is Array:
		for i in mini(n_src, cin.size()):
			if src_to_top[i] >= 0:
				sharp[src_to_top[i]] = float(cin[i])
	elif cin is Dictionary:
		for k in cin:
			var lo := mini(k.x, k.y)
			var hi := maxi(k.x, k.y)
			var id: int = top["key"].get(lo * nv0 + hi, -1)
			if id >= 0:
				sharp[id] = float(cin[k])
	# attribute channels, re-laid in our orders (edge domain in our edge ids)
	var ch := {}
	for k in mesh.attrs:
		var r: Dictionary = mesh.attrs[k]
		var d = r["data"].duplicate()
		if r["domain"] == KMesh.AD_EDGE:
			var nd = KMesh._attr_make(r["type"], ne, r["default"])
			for i in mini(n_src, d.size()):
				if src_to_top[i] >= 0:
					nd[src_to_top[i]] = d[i]
			d = nd
		ch[k] = {"domain": r["domain"], "type": r["type"], "default": r["default"], "data": d}
	if ch.has(CREASE) and ch[CREASE]["domain"] == KMesh.AD_EDGE and ch[CREASE]["type"] == TYPE_FLOAT:
		ch[CREASE]["data"] = sharp
	for lv in maxi(levels, 0):
		var r := _level(V, fs, fv, top, sharp, ch)
		V = r["V"]
		fs = r["fs"]
		fv = r["fv"]
		top = r["top"]
		sharp = r["sharp"]
		if ch.has(CREASE) and ch[CREASE]["domain"] == KMesh.AD_EDGE and ch[CREASE]["type"] == TYPE_FLOAT:
			ch[CREASE]["data"] = sharp
	var faces: Array = []
	faces.resize(fs.size() - 1)
	for f in fs.size() - 1:
		faces[f] = fv.slice(fs[f], fs[f + 1])
	var out := KMesh.new()
	out.normal_mode = mesh.normal_mode
	out.auto_angle = mesh.auto_angle
	out.from_arrays(V, faces)
	if not ch.is_empty():
		var oe := out.edges()
		var nvn := V.size()
		if not top.has("key"):
			var key := {}
			for i in (top["a"] as PackedInt32Array).size():
				key[top["a"][i] * nvn + top["b"][i]] = i
			top["key"] = key
		for k in ch:
			var r: Dictionary = ch[k]
			if r["domain"] == KMesh.AD_EDGE:   # our edge ids -> the result's edges() order
				var d = KMesh._attr_make(r["type"], oe.size(), r["default"])
				for i in oe.size():
					var e: Vector2i = oe[i]
					var id: int = top["key"].get(e.x * nvn + e.y, -1)
					if id >= 0:
						d[i] = r["data"][id]
				r["data"] = d
			out.attrs[k] = r
	return out


## unique undirected edges of a face list: {"a", "b" (a < b), "f0", "f1" (the first two faces, -1 = none), "nf" (how many
## faces use it), "ce" (edge id of corner c = the edge from corner c to the next), "key" (a * nv + b -> id)}
static func _edges(nv: int, fs: PackedInt32Array, fv: PackedInt32Array) -> Dictionary:
	var key := {}
	var a := PackedInt32Array()
	var b := PackedInt32Array()
	var f0 := PackedInt32Array()
	var f1 := PackedInt32Array()
	var cnt := PackedInt32Array()
	var ce := PackedInt32Array()
	ce.resize(fv.size())
	for f in fs.size() - 1:
		var s := fs[f]
		var n := fs[f + 1] - s
		for i in n:
			var p := fv[s + i]
			var q := fv[s + (i + 1) % n]
			var lo := mini(p, q)
			var hi := maxi(p, q)
			var k := lo * nv + hi
			var id: int = key.get(k, -1)
			if id == -1:
				id = a.size()
				key[k] = id
				a.append(lo)
				b.append(hi)
				f0.append(f)
				f1.append(-1)
				cnt.append(1)
			else:
				if cnt[id] == 1:
					f1[id] = f
				cnt[id] += 1
			ce[s + i] = id
	return {"key": key, "a": a, "b": b, "f0": f0, "f1": f1, "nf": cnt, "ce": ce}


## one Catmull-Clark level. New vertex ids: old vertices 0..nv-1, then edge points nv..nv+ne-1, then face points.
static func _level(V: PackedVector3Array, fs: PackedInt32Array, fv: PackedInt32Array, top: Dictionary, sharp: PackedFloat32Array, ch: Dictionary) -> Dictionary:
	var nv := V.size()
	var nf := fs.size() - 1
	var ea: PackedInt32Array = top["a"]
	var eb: PackedInt32Array = top["b"]
	var ef0: PackedInt32Array = top["f0"]
	var ef1: PackedInt32Array = top["f1"]
	var enf: PackedInt32Array = top["nf"]
	var ce: PackedInt32Array = top["ce"]
	var ne := ea.size()
	# face points
	var FP := PackedVector3Array()
	FP.resize(nf)
	for f in nf:
		var s := Vector3.ZERO
		for c in range(fs[f], fs[f + 1]):
			s += V[fv[c]]
		FP[f] = s / float(fs[f + 1] - fs[f])
	# per vertex sums: face points (Q), edge midpoints (R), valence, sharp edges (count, sharpness, other ends)
	var q_sum := PackedVector3Array()
	q_sum.resize(nv)
	var k_cnt := PackedInt32Array()
	k_cnt.resize(nv)
	for f in nf:
		for c in range(fs[f], fs[f + 1]):
			q_sum[fv[c]] += FP[f]
			k_cnt[fv[c]] += 1
	var r_sum := PackedVector3Array()
	r_sum.resize(nv)
	var val := PackedInt32Array()
	val.resize(nv)
	var s_cnt := PackedInt32Array()
	s_cnt.resize(nv)
	var s_sum := PackedFloat32Array()
	s_sum.resize(nv)
	var s_oth := PackedVector3Array()
	s_oth.resize(nv)
	var bnd := PackedInt32Array()   # boundary edges at the vertex
	bnd.resize(nv)
	var EP := PackedVector3Array()
	EP.resize(ne)
	for e in ne:
		var a := ea[e]
		var b := eb[e]
		var mid := (V[a] + V[b]) * 0.5
		r_sum[a] += mid
		r_sum[b] += mid
		val[a] += 1
		val[b] += 1
		var s := sharp[e] if enf[e] == 2 else INF
		if enf[e] != 2:
			bnd[a] += 1
			bnd[b] += 1
		if s > 0.0:
			s_cnt[a] += 1
			s_cnt[b] += 1
			s_sum[a] += s
			s_sum[b] += s
			s_oth[a] += V[b]
			s_oth[b] += V[a]
		if enf[e] != 2 or s >= 1.0:
			EP[e] = mid
		else:
			var sm := (V[a] + V[b] + FP[ef0[e]] + FP[ef1[e]]) * 0.25
			EP[e] = sm.lerp(mid, s) if s > 0.0 else sm
	# vertex points
	var NV := PackedVector3Array()
	NV.resize(nv + ne + nf)
	for v in nv:
		var p := V[v]
		var k := k_cnt[v]
		if k == 0:
			NV[v] = p
			continue
		var n := val[v]
		var sm := (q_sum[v] / float(k) + 2.0 * r_sum[v] / float(n) + float(n - 3) * p) / float(n)
		var ns := s_cnt[v]
		if ns < 2:
			NV[v] = sm
			continue
		var hard := p   # a corner
		if ns == 2 and not (k == 1 and bnd[v] >= 2):
			hard = (s_oth[v] + 6.0 * p) / 8.0   # a crease (also a straight run of boundary)
		var vs := s_sum[v] / float(ns)
		NV[v] = hard if vs >= 1.0 else sm.lerp(hard, vs)
	for e in ne:
		NV[nv + e] = EP[e]
	for f in nf:
		NV[nv + ne + f] = FP[f]
	# topology: corner i of face f -> quad (v_i, edge point of i -> i+1, face point, edge point of i-1 -> i)
	var nc := fv.size()
	var nfs := PackedInt32Array()
	nfs.resize(nc + 1)
	var nfv := PackedInt32Array()
	nfv.resize(nc * 4)
	var par_c := PackedInt32Array()   # parent corner of each new face (for corner and face channels)
	par_c.resize(nc)
	var par_f := PackedInt32Array()
	par_f.resize(nc)
	for f in nf:
		var s0 := fs[f]
		var n := fs[f + 1] - s0
		for i in n:
			var c := s0 + i
			var o := c * 4
			nfs[c] = o
			nfv[o] = fv[c]
			nfv[o + 1] = nv + ce[c]
			nfv[o + 2] = nv + ne + f
			nfv[o + 3] = nv + ce[s0 + (i + n - 1) % n]
			par_c[c] = c
			par_f[c] = f
	nfs[nc] = nc * 4
	# the new edges, by construction (no lookup): halves 2e (a - edge point) and 2e + 1 (b - edge point) of edge e, then
	# 2 ne + c (edge point of corner c - face point) inside the faces. The halves get sharp[e] - 1, the inside edges 0.
	var nne := 2 * ne + nc
	var na := PackedInt32Array()
	var nb := PackedInt32Array()
	na.resize(nne)
	nb.resize(nne)
	var nsh := PackedFloat32Array()
	nsh.resize(nne)
	var half := PackedInt32Array()   # new edge -> parent edge (-1 = inside a face)
	half.resize(nne)
	half.fill(-1)
	for e in ne:
		na[2 * e] = ea[e]
		nb[2 * e] = nv + e
		na[2 * e + 1] = eb[e]
		nb[2 * e + 1] = nv + e
		var cs := maxf(sharp[e] - 1.0, 0.0)
		nsh[2 * e] = cs
		nsh[2 * e + 1] = cs
		half[2 * e] = e
		half[2 * e + 1] = e
	var nce := PackedInt32Array()
	nce.resize(nc * 4)
	for f in nf:
		var s0 := fs[f]
		var n := fs[f + 1] - s0
		for i in n:
			var c := s0 + i
			var pc := s0 + (i + n - 1) % n
			var v := fv[c]
			na[2 * ne + c] = nv + ce[c]
			nb[2 * ne + c] = nv + ne + f
			var o := c * 4
			nce[o] = 2 * ce[c] + (0 if ea[ce[c]] == v else 1)
			nce[o + 1] = 2 * ne + c
			nce[o + 2] = 2 * ne + pc
			nce[o + 3] = 2 * ce[pc] + (0 if ea[ce[pc]] == v else 1)
	var nf0 := PackedInt32Array()
	var nf1 := PackedInt32Array()
	var ncnt := PackedInt32Array()
	nf0.resize(nne)
	nf1.resize(nne)
	ncnt.resize(nne)
	nf0.fill(-1)
	nf1.fill(-1)
	for o in nc * 4:
		var e := nce[o]
		var f := o >> 2
		if ncnt[e] == 0:
			nf0[e] = f
		elif ncnt[e] == 1:
			nf1[e] = f
		ncnt[e] += 1
	var ntop := {"a": na, "b": nb, "f0": nf0, "f1": nf1, "nf": ncnt, "ce": nce}
	var nnv := NV.size()
	# attributes
	for k in ch:
		var r: Dictionary = ch[k]
		var d = r["data"]
		var nd = KMesh._attr_make(r["type"], 0, r["default"])
		match r["domain"]:
			KMesh.AD_VERT:
				nd.resize(nnv)
				for v in nv:
					nd[v] = d[v]
				if KMesh.is_label(k) and r["type"] == TYPE_FLOAT:   # A19: an index, not an amount: an end's / the corners' most common
					for e in ne:
						nd[nv + e] = d[ea[e]]   # both ends' when they agree, else the first end's
					for f in nf:
						nd[nv + ne + f] = KMesh.label_pick(d, fv.slice(fs[f], fs[f + 1]))
					r["data"] = nd
					continue
				for e in ne:
					nd[nv + e] = (d[ea[e]] + d[eb[e]]) * 0.5
				for f in nf:
					var acc = KMesh._attr_zero(r["type"])
					for c in range(fs[f], fs[f + 1]):
						acc += d[fv[c]]
					nd[nv + ne + f] = acc / float(fs[f + 1] - fs[f])
			KMesh.AD_CORNER:
				nd.resize(nc * 4)
				for f in nf:
					var s0 := fs[f]
					var n := fs[f + 1] - s0
					var acc = KMesh._attr_zero(r["type"])
					for c in range(s0, s0 + n):
						acc += d[c]
					var mean = acc / float(n)
					for i in n:
						var c := s0 + i
						var o := c * 4
						nd[o] = d[c]
						nd[o + 1] = (d[c] + d[s0 + (i + 1) % n]) * 0.5
						nd[o + 2] = mean
						nd[o + 3] = (d[c] + d[s0 + (i + n - 1) % n]) * 0.5
			KMesh.AD_FACE:
				nd.resize(nc)
				for c in nc:
					nd[c] = d[par_f[c]]
			KMesh.AD_EDGE:
				nd.resize(nsh.size())
				for h in nsh.size():
					nd[h] = d[half[h]] if half[h] >= 0 else r["default"]
		r["data"] = nd
	return {"V": NV, "fs": nfs, "fv": nfv, "top": ntop, "sharp": nsh}
