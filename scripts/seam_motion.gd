class_name SeamMotion
extends RefCounted
## D13 (docs/ROADMAP_400.md): SEAMS THAT AVOID MOTION. A UV seam across a high-stretch area of the open scene's animation is
## flagged. Reuses the SculptMotion stretch (|ln(posed edge length / rest edge length)|) and its skinning (DqSkin at the scene's
## dq_skin blend). Pure data in, data out: nothing in the mesh is written.
##   own(e)   = max over the scene's frames (t = min(f / fps, length), f = 0 .. ceil(length * fps)) of |ln(posed / rest)|
##              (edges of rest length <= 1 mm count 0)
##   local(e) = max of own over e and every edge sharing a vertex with e
##   a seam edge is FLAGGED when local(e) >= THRESHOLD; a seam (chain) when any edge is.
## THRESHOLD 0.15: |ln r| = 0.15 is a 16 pct stretch / 14 pct squash; the texture on both sides of the cut moves 15 pct
## against the cut, visibly shearing. A design choice, not a measurement.
## Only the seam's neighbourhood is skinned: the seam vertices, their 1-ring, and every vertex within `pad` (5 cm) of a seam
## vertex (the room the suggested path may use).
## SUGGEST: Dijkstra between the seam's two end vertices over that neighbourhood, edge cost = rest length * (1 + 50 * local).

const THRESHOLD := 0.15
const MIN_EDGE := 0.001
const PAD := 0.05
const PENALTY := 50.0


static func ekey(a: int, b: int) -> int:
	return mini(a, b) * 1000003 + maxi(a, b)


static func run(mesh: KMesh, main: Node, seams: Array, pad := PAD, thr := THRESHOLD) -> Dictionary:
	var skin := BaseBody.skin_of(main)
	var skc := (main.skel as Skeleton3D).duplicate()
	var sp := SculptPose.new().setup(mesh, skin, skc)
	var scene: Scene = main._ps()
	var G := Body.new()
	G.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	var fps := float(scene.fps)
	var length := scene.length()
	var nf := int(ceil(length * fps)) + 1
	var k := float(scene.dq_skin)
	var vs := mesh.verts
	var sv := {}
	for e in seams:
		sv[e.x] = true
		sv[e.y] = true
	var seam_pts: Array = []
	for v in sv:
		seam_pts.append(vs[v])
	var scope := {}
	var pad2 := pad * pad
	for v in vs.size():
		for p in seam_pts:
			if vs[v].distance_squared_to(p) <= pad2:
				scope[v] = true
				break
	for f in mesh.faces:     # the 1-ring of the seam vertices is always in
		var hit := false
		for v in f:
			if sv.has(v):
				hit = true
		if hit:
			for v in f:
				scope[v] = true
	var edges := {}   # key -> Vector2i, both ends in scope
	for f in mesh.faces:
		var n: int = f.size()
		for i in n:
			var a: int = f[i]
			var b: int = f[(i + 1) % n]
			if a != b and scope.has(a) and scope.has(b):
				edges[ekey(a, b)] = Vector2i(mini(a, b), maxi(a, b))
	var keys: Array = edges.keys()
	var rl := {}
	for key in keys:
		var e: Vector2i = edges[key]
		rl[key] = vs[e.x].distance_to(vs[e.y])
	var own := {}
	for key in keys:
		own[key] = 0.0
	var P := PackedVector3Array()
	P.resize(vs.size())
	var sverts: Array = scope.keys()
	for f in nf:
		scene.apply(G, minf(float(f) / fps, length))
		Overlays.pose_skeleton(skc, main.bone_idx, G)
		var mats := DqSkin.bind_mats(skc, skin)
		var dq := DqSkin.dqs_of(mats)
		for v in sverts:
			P[v] = DqSkin.skin_one(vs[v], v, sp.bo, sp.w, 4, mats, dq, k)[0]
		for key in keys:
			if rl[key] <= MIN_EDGE:
				continue
			var e: Vector2i = edges[key]
			var s := absf(log(maxf(P[e.x].distance_to(P[e.y]), 1e-9) / rl[key]))
			if s > own[key]:
				own[key] = s
	var vmax := {}
	for key in keys:
		var e: Vector2i = edges[key]
		vmax[e.x] = maxf(vmax.get(e.x, 0.0), own[key])
		vmax[e.y] = maxf(vmax.get(e.y, 0.0), own[key])
	var rep_edges: Array = []
	var flagged: Array = []
	var any := false
	var mx := 0.0
	for e in seams:
		var key := ekey(e.x, e.y)
		var ed := Vector2i(mini(e.x, e.y), maxi(e.x, e.y))
		var o: float = own.get(key, 0.0)
		var loc := maxf(vmax.get(ed.x, 0.0), vmax.get(ed.y, 0.0))
		var fl := loc >= thr
		rep_edges.append({"edge": ed, "own": o, "local": loc, "flag": fl})
		if fl:
			flagged.append(ed)
			any = true
		mx = maxf(mx, loc)
	return {"thr": thr, "frames": nf, "edges": rep_edges, "flagged": flagged, "flagged_any": any, "max_local": mx,
		"own": own, "vmax": vmax, "scope": scope}


## local stretch of one mesh edge from a report (0 outside its neighbourhood)
static func local_of(rep: Dictionary, a: int, b: int) -> float:
	var vm: Dictionary = rep["vmax"]
	return maxf(vm.get(a, 0.0), vm.get(b, 0.0))


## the two end vertices (degree 1) of a chain of edges, ascending; [] when it is not an open chain
static func chain_ends(seam: Array) -> Array:
	var deg := {}
	for e in seam:
		deg[e.x] = deg.get(e.x, 0) + 1
		deg[e.y] = deg.get(e.y, 0) + 1
	var out := []
	for v in deg:
		if deg[v] == 1:
			out.append(v)
	out.sort()
	return out if out.size() == 2 else []


static func _root(par: Dictionary, x: int) -> int:
	while par[x] != x:
		par[x] = par[par[x]]
		x = par[x]
	return x


## the connected chains of a seam-edge list: Array of Array[Vector2i]
static func chains(seams: Array) -> Array:
	var par := {}
	for e in seams:
		for v in [e.x, e.y]:
			if not par.has(v):
				par[v] = v
	for e in seams:
		var ra := _root(par, e.x)
		var rb := _root(par, e.y)
		if ra != rb:
			par[ra] = rb
	var by := {}
	for e in seams:
		var r := _root(par, e.x)
		if not by.has(r):
			by[r] = []
		by[r].append(Vector2i(mini(e.x, e.y), maxi(e.x, e.y)))
	return by.values()


static func _sift_up(hd: Array, hv: Array, i: int) -> void:
	while i > 0:
		var pr := (i - 1) / 2
		if hd[pr] <= hd[i]:
			break
		var td = hd[i]
		hd[i] = hd[pr]
		hd[pr] = td
		var tv = hv[i]
		hv[i] = hv[pr]
		hv[pr] = tv
		i = pr


static func _sift_down(hd: Array, hv: Array) -> void:
	var i := 0
	while true:
		var l := 2 * i + 1
		var r := l + 1
		var s := i
		if l < hd.size() and hd[l] < hd[s]:
			s = l
		if r < hd.size() and hd[r] < hd[s]:
			s = r
		if s == i:
			break
		var td = hd[i]
		hd[i] = hd[s]
		hd[s] = td
		var tv = hv[i]
		hv[i] = hv[s]
		hv[s] = tv
		i = s


## shortest path a -> b along mesh edges: vertex ids ([] when none). cost: Callable(a, b, rest_len) -> float (default the
## length); allowed: Dictionary of vertex ids the path may use ({} = all)
static func shortest(mesh: KMesh, a: int, b: int, cost := Callable(), allowed := {}) -> Array:
	var adj := {}
	for f in mesh.faces:
		var n: int = f.size()
		for i in n:
			var p: int = f[i]
			var q: int = f[(i + 1) % n]
			if p == q or (not allowed.is_empty() and (not allowed.has(p) or not allowed.has(q))):
				continue
			if not adj.has(p):
				adj[p] = {}
			if not adj.has(q):
				adj[q] = {}
			adj[p][q] = true
			adj[q][p] = true
	var dist := {a: 0.0}
	var prev := {}
	var hd: Array = [0.0]
	var hv: Array = [a]
	var done := {}
	while not hd.is_empty():
		var d: float = hd[0]
		var u: int = hv[0]
		var ld = hd.pop_back()
		var lv = hv.pop_back()
		if not hd.is_empty():
			hd[0] = ld
			hv[0] = lv
			_sift_down(hd, hv)
		if done.has(u):
			continue
		done[u] = true
		if u == b:
			break
		if not adj.has(u):
			continue
		for w in adj[u]:
			if done.has(w):
				continue
			var l0: float = mesh.verts[u].distance_to(mesh.verts[w])
			var c: float = l0 if not cost.is_valid() else float(cost.call(u, w, l0))
			var nd := d + c
			if nd < dist.get(w, 1e30):
				dist[w] = nd
				prev[w] = u
				hd.append(nd)
				hv.append(w)
				_sift_up(hd, hv, hd.size() - 1)
	if not done.has(b):
		return []
	var path: Array = [b]
	while path[0] != a:
		path.push_front(prev[path[0]])
	return path


## a nearby lower-stretch path for one open seam chain: {"ok", "path", "edges", "a", "b", "max_local", "orig_max"}.
## ok = the path's max local stretch is below the seam's. {} when the seam is not an open chain.
static func suggest(mesh: KMesh, rep: Dictionary, seam: Array) -> Dictionary:
	var ends := chain_ends(seam)
	if ends.is_empty():
		return {}
	var a: int = ends[0]
	var b: int = ends[1]
	var orig := 0.0
	for e in seam:
		orig = maxf(orig, local_of(rep, e.x, e.y))
	var cost := func(u: int, w: int, l: float) -> float:
		return l * (1.0 + PENALTY * local_of(rep, u, w))
	var path := shortest(mesh, a, b, cost, rep["scope"])
	if path.size() < 2:
		return {"ok": false, "path": [], "edges": [], "a": a, "b": b, "max_local": INF, "orig_max": orig}
	var es: Array = []
	var mx := 0.0
	for i in range(path.size() - 1):
		es.append(Vector2i(mini(path[i], path[i + 1]), maxi(path[i], path[i + 1])))
		mx = maxf(mx, local_of(rep, path[i], path[i + 1]))
	return {"ok": mx < orig, "path": path, "edges": es, "a": a, "b": b, "max_local": mx, "orig_max": orig}
