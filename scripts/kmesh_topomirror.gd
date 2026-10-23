class_name KMeshTopoMirror
extends RefCounted
## B22 (docs/ROADMAP_400.md): MIRROR AXIS CHOICE + TOPOLOGICAL MIRROR FOR ASYMMETRIC MESHES.
## SETTINGS (one shared object, get_shared(): the model preview's G / R / S and the sculpt preview read the same one):
##   on        edits mirror to the partner (G / R / S with Blender keys on, bl_keys.gd; a sculpt stroke, kmesh_sculpt.gd)
##   axis      0 X, 1 Y, 2 Z: the mirror plane's normal
##   space     "local": the plane through the mesh's own origin (KMesh.origin when the mesh has one, B17; else its local
##             zero); "world": the plane through the world origin, put into the mesh's frame by the view's transform (the
##             previews place a mesh, they do not turn it: only the translation and scale along the axis count)
##   topo      partners by connectivity (true, the default) or by position only (false: KMesh.symmetry_map)
## THE TOPOLOGICAL MAP (build): a BFS over PAIRS OF HALF-EDGES. A reflection reverses orientation, so the image of the
##   half-edge a->b of a face is the half-edge b'->a' of the image face: if (h, g) is a pair, so are (next h, prev g),
##   (prev h, next g) and (twin h, twin g); the pair (h, g) gives a -> a' (= the end of g) and b -> b' (= g's start).
##   SEED: a half-edge h = a->b whose ends both have POSITIONAL partners and whose image b'->a' exists. On the centre line
##   that is an edge with both ends on the plane (its image is its own twin) or an edge straddling it (its own image).
##   Centre seeds are tried first; per connected piece up to SEEDS candidates run and the one that pairs the most verts
##   (with the fewest clashes) is kept. A piece whose mirror is another piece (two eyes) is seeded the same way and both
##   pieces are paired by the one BFS; a BFS with more than 1 clash per CLASH_DIV verts is thrown away (it found a
##   lookalike, not a mirror). A pair whose faces differ in size, or one side a boundary and the other not, is a
##   clash: it is not followed. A vert given two partners is dropped; only mutual pairs are kept.
##   Seeds need SOME of the mesh still symmetric by position (the centre line, usually); the tolerance is widened x10 up to
##   1 % of the mesh's size until a seed is found. A piece with no positional seed at all tries the edges that cross the
##   plane (each its own image). A piece no seed reached (an arm that is its own piece, turned) is paired BY SHAPE with a
##   piece on the other side (_shape_pass: same counts, length, where it sits among the pieces already paired). What is
##   still left is paired BY POSITION (the fallback); the rest are reported as unpaired. So a posed / drifted / one-side-sculpted mesh still pairs every vert with the
##   partner it had when it was symmetric.
## OPS (scripts/mesh_tools.gd "op:mirror_*", "op:symmetrize*"): edit mirror on / off, next axis, local / world, build the
##   map (says the % partnered and selects the unpaired verts), symmetrize (+ side onto - side, or - onto +; one undo
##   step), find asymmetry (selects the + side vert of every pair whose partner is not at its mirror image, says the
##   largest deviation in mm).
## EDITS with the mirror on are ONE undo step with the partner moves: follow() runs inside the edit's KMeshUndo bracket.
## Tests: tests/topomirror_test.gd.

const LOCAL := "local"
const WORLD := "world"
const SEEDS := 4
const SHAPE_TOL := 0.25   # pieces paired by shape: total edge length within 25 % (a posed joint stretches), closest first
const CLASH_DIV := 20   # a piece's BFS is kept only with at most 1 clash per 20 verts paired (or 2)
const ASYM_TOL := 1e-4   # 0.1 mm: under this a pair counts as symmetric

static var _shared: KMeshTopoMirror

var on := false
var axis := 0
var space := LOCAL
var topo := true
var tol := 1e-4
var last := {}          # the last map built: see build()
var _key := ""
var _idx := {}          # follow(): the verts the edit itself writes (never overwritten by a partner)
var _mirrored := PackedInt32Array()


static func get_shared() -> KMeshTopoMirror:
	if _shared == null:
		_shared = KMeshTopoMirror.new()
	return _shared


static func axis_name(a: int) -> String:
	return "XYZ"[clampi(a, 0, 2)]


## B17's origin when this mesh has one, else its local zero
static func mesh_origin(m: KMesh) -> Vector3:
	var o = m.get("origin")
	return o if o is Vector3 else Vector3.ZERO


## the plane's coordinate on `ax` in the mesh's own frame
static func plane_for(m: KMesh, ax: int, sp: String, xf := Transform3D.IDENTITY) -> float:
	if sp == WORLD:
		return (xf.affine_inverse() * Vector3.ZERO)[ax]
	return mesh_origin(m)[ax]


static func reflect(p: Vector3, ax: int, plane: float) -> Vector3:
	p[ax] = 2.0 * plane - p[ax]
	return p


static func flip(d: Vector3, ax: int) -> Vector3:
	d[ax] = -d[ax]
	return d


func words() -> String:
	return "%s mirror %s (%s, %s)" % [axis_name(axis), "on" if on else "off", space, "topological" if topo else "by position"]


# ---------------------------------------------------------------- the map

## The partner map. Returns {"map": PackedInt32Array (partner per vert, itself on the plane, -1 none), "topo_pairs",
## "pos_pairs" (verts paired by connectivity / by the positional fallback), "centre", "paired", "pct", "unpaired":
## PackedInt32Array, "clashes", "seeds" (pieces seeded), "seed_tol", "axis", "plane"}
static func build(m: KMesh, ax := 0, plane := 0.0, p_tol := 1e-4, use_topo := true) -> Dictionary:
	var nv := m.verts.size()
	var pos := m.symmetry_map(ax, p_tol, plane)
	var map := PackedInt32Array()
	map.resize(nv)
	map.fill(-1)
	var info := {"topo_pairs": 0, "pos_pairs": 0, "clashes": 0, "seeds": 0, "shape_pairs": 0, "cross_seeds": 0, "seed_tol": p_tol, "axis": ax, "plane": plane}
	if use_topo and nv > 0 and m.faces.size() > 0:
		_topo(m, ax, plane, p_tol, pos, map, info)
	var tp := 0
	for v in nv:
		if map[v] >= 0:
			tp += 1
	info["topo_pairs"] = tp
	var pp := 0
	for v in nv:   # the fallback: by position, among the verts the connectivity left alone
		var u := pos[v]
		if map[v] == -1 and u >= 0 and map[u] == -1:
			map[v] = u
			map[u] = v
			pp += 2 if u != v else 1
	info["pos_pairs"] = pp
	var un := PackedInt32Array()
	var centre := 0
	for v in nv:
		if map[v] == -1:
			un.append(v)
		elif map[v] == v:
			centre += 1
	info["map"] = map
	info["unpaired"] = un
	info["centre"] = centre
	info["paired"] = nv - un.size()
	info["pct"] = 100.0 * float(nv - un.size()) / float(maxi(nv, 1))
	return info


static func _topo(m: KMesh, ax: int, plane: float, p_tol: float, pos: PackedInt32Array, map: PackedInt32Array, info: Dictionary) -> void:
	var hv := m.he_vert
	var hn := m.he_next
	var ht := m.he_twin
	var hf := m.he_face
	var nh := hv.size()
	var hp := PackedInt32Array()   # prev, from next
	hp.resize(nh)
	for h in nh:
		hp[hn[h]] = h
	# the pieces (faces joined through twins), as a piece id per half-edge
	var comp := PackedInt32Array()
	comp.resize(nh)
	comp.fill(-1)
	var ncomp := 0
	for h0 in nh:
		if comp[h0] != -1:
			continue
		var st := [h0]
		comp[h0] = ncomp
		while not st.is_empty():
			var h: int = st.pop_back()
			for k in [hn[h], ht[h]]:
				if k >= 0 and comp[k] == -1:
					comp[k] = ncomp
					st.append(k)
		ncomp += 1
	# seed candidates per piece, centre-line ones first; widen the tolerance until some piece has one
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for p in m.verts:
		lo = lo.min(p)
		hi = hi.max(p)
	var size := maxf((hi - lo).length(), 1e-6)
	var t := p_tol
	var spos := pos
	var cands := _seeds(m, spos, comp, ncomp, hp)
	while _none(cands) and t * 10.0 <= size * 0.01:
		t *= 10.0
		spos = m.symmetry_map(ax, t, plane)
		cands = _seeds(m, spos, comp, ncomp, hp)
	info["seed_tol"] = t
	var done := PackedByteArray()
	done.resize(ncomp)
	var vm := PackedInt32Array()
	vm.resize(map.size())
	vm.fill(-1)
	var cross := 0
	for c in ncomp:
		if done[c]:
			continue
		var list: Array = cands[c]
		if list.is_empty():
			list = _cross_seeds(m, ax, plane, comp, c)   # no positional evidence: an edge across the plane is its own image
			cross += 1 if not list.is_empty() else 0
		if list.is_empty():
			continue
		var best := {}
		var step := maxi(1, list.size() / SEEDS)
		var k := 0
		while k < list.size() and k / step < SEEDS:
			var r := _bfs(list[k][0], list[k][1], hv, hn, hp, ht, hf, m, vm)
			if best.is_empty() or int(r["n"]) - int(r["clash"]) > int(best["n"]) - int(best["clash"]):
				best = r
			k += step
		_take(best, info, vm, done, comp)
	info["cross_seeds"] = cross
	_shape_pass(m, ax, plane, comp, ncomp, done, vm, hv, hn, hp, ht, hf, info)
	for v in vm.size():   # only mutual pairs
		var u := vm[v]
		if u >= 0 and vm[u] == v and map[v] == -1:
			map[v] = u


## keep a BFS's pairs unless it clashed too much (it found a lookalike, not a mirror: Y on a body, 32 pairs, 144 clashes)
static func _take(best: Dictionary, info: Dictionary, vm: PackedInt32Array, done: PackedByteArray, comp: PackedInt32Array) -> bool:
	if best.is_empty() or int(best["clash"]) > maxi(2, int(best["n"]) / CLASH_DIV):
		return false
	info["seeds"] = int(info.get("seeds", 0)) + 1
	info["clashes"] = int(info.get("clashes", 0)) + int(best["clash"])
	var bv: Dictionary = best["v"]
	for v in bv:
		var u: int = bv[v]
		if u >= 0 and vm[v] == -1:
			vm[v] = u
	for h in (best["h"] as PackedInt32Array):
		done[comp[h]] = 1
	return true


## piece c's half-edges a->b with a on the - side and b on the + side: each is its own mirror image when the piece is
## symmetric with no vert on the plane (a 20-column grid)
static func _cross_seeds(m: KMesh, ax: int, plane: float, comp: PackedInt32Array, c: int) -> Array:
	var hv := m.he_vert
	var hn := m.he_next
	var out: Array = []
	for h in hv.size():
		if comp[h] == c and m.verts[hv[h]][ax] < plane and m.verts[hv[hn[h]]][ax] > plane:
			out.append([h, h])
	return out


## THE PIECES NO SEED REACHED (a mannequin's arm is its own piece, and turned it has no positional partner left): a
## piece is paired with a piece on the other side (by centroid) with the same vert and face counts and a total edge
## length within SHAPE_TOL (a reflection and a rigid turn keep every length, a posed joint stretches some). Cheapest pair
## first: a piece with a single candidate, else the length difference + the context (_context: where it sits against
## the pieces already paired). Then seeded by _seed_pair.
static func _shape_pass(m: KMesh, ax: int, plane: float, comp: PackedInt32Array, ncomp: int, done: PackedByteArray,
		vm: PackedInt32Array, hv: PackedInt32Array, hn: PackedInt32Array, hp: PackedInt32Array, ht: PackedInt32Array,
		hf: PackedInt32Array, info: Dictionary) -> void:
	var nh := hv.size()
	var nv := m.verts.size()
	var deg := PackedInt32Array()
	deg.resize(nv)
	var hl := PackedFloat32Array()
	hl.resize(nh)
	var stats := {}   # piece -> [verts {}, faces {}, length, centroid offset sum, half-edges []]
	for h in nh:
		var c := comp[h]
		if done[c]:
			continue
		var a := hv[h]
		var b := hv[hn[h]]
		deg[a] += 1
		hl[h] = m.verts[a].distance_to(m.verts[b])
		if not stats.has(c):
			stats[c] = [{}, {}, 0.0, 0.0, []]
		var st: Array = stats[c]
		if not (st[0] as Dictionary).has(a):
			st[0][a] = true
			st[3] = float(st[3]) + m.verts[a][ax] - plane
		st[1][hf[h]] = true
		st[2] = float(st[2]) + hl[h]
		(st[4] as Array).append(h)
	# the pieces' centres, and which piece is already the mirror of which (from the pairs found so far): the anchors
	var vc := PackedInt32Array()
	vc.resize(nv)
	vc.fill(-1)
	for h in nh:
		vc[hv[h]] = comp[h]
	var csum := {}
	var cn := {}
	for v in nv:
		if vc[v] >= 0:
			csum[vc[v]] = csum.get(vc[v], Vector3.ZERO) + m.verts[v]
			cn[vc[v]] = int(cn.get(vc[v], 0)) + 1
	var cen := {}
	for c in csum:
		cen[c] = csum[c] / float(cn[c])
	var mate := {}
	for v in nv:
		if vm[v] >= 0 and vc[v] >= 0 and vc[vm[v]] >= 0 and not mate.has(vc[v]):
			mate[vc[v]] = vc[vm[v]]
	var pairs: Array = []
	var keys := stats.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var s1: Array = stats[keys[i]]
			var s2: Array = stats[keys[j]]
			if (s1[0] as Dictionary).size() != (s2[0] as Dictionary).size() or (s1[1] as Dictionary).size() != (s2[1] as Dictionary).size():
				continue
			if float(s1[3]) * float(s2[3]) >= 0.0:
				continue   # not on opposite sides
			var dl := absf(float(s1[2]) - float(s2[2])) / maxf(float(s1[2]), 1e-9)
			if dl < SHAPE_TOL:
				pairs.append([keys[i], keys[j], dl])
	var matched := 0
	while not pairs.is_empty():
		# the cheapest pair now: a piece with one candidate left goes first; else the shape plus the CONTEXT (its
		# distances to the 3 nearest pieces already paired against its candidate's distances to their mirrors: a rigid
		# turn and a reflection keep them, so identical finger segments are told apart by where they sit)
		var live := {}
		for pr in pairs:
			live[pr[0]] = int(live.get(pr[0], 0)) + 1
			live[pr[1]] = int(live.get(pr[1], 0)) + 1
		var bi := -1
		var bc := INF
		for i in pairs.size():
			var pr: Array = pairs[i]
			var cost := -1.0 if int(live[pr[0]]) == 1 and int(live[pr[1]]) == 1 else float(pr[2]) + _context(pr[0], pr[1], cen, mate)
			if cost < bc:
				bc = cost
				bi = i
		var c1: int = pairs[bi][0]
		var c2: int = pairs[bi][1]
		pairs.remove_at(bi)
		var best := _seed_pair(m, stats[c1][4], stats[c2][4], deg, hl, vm, hv, hn, hp, ht, hf)
		if _take(best, info, vm, done, comp):
			matched += 1
			mate[c1] = c2
			mate[c2] = c1
			pairs = pairs.filter(func(q): return not (q[0] in [c1, c2] or q[1] in [c1, c2]))
	info["shape_pairs"] = matched


## how far piece c2 sits from the mirrors of c1's 3 nearest paired pieces, against c1's own distances (relative)
static func _context(c1: int, c2: int, cen: Dictionary, mate: Dictionary) -> float:
	var near: Array = []
	for a in mate:
		if a != c1 and a != c2 and cen.has(a) and cen.has(mate[a]):
			near.append([(cen[c1] as Vector3).distance_to(cen[a]), a])
	if near.is_empty():
		return 0.0
	near.sort_custom(func(x, y): return x[0] < y[0])
	var num := 0.0
	var den := 0.0
	for k in mini(3, near.size()):
		var a: int = near[k][1]
		num += absf(float(near[k][0]) - (cen[c2] as Vector3).distance_to(cen[mate[a]]))
		den += float(near[k][0])
	return num / maxf(den, 1e-9)


## the seed of two pieces paired by shape: the rarest half-edge of the first against the second's half-edges that match
## it (face size, the two valences), the 64 closest in length; the BFS with no clash and the least edge-length error
static func _seed_pair(m: KMesh, hs1: Array, hs2: Array, deg: PackedInt32Array, hl: PackedFloat32Array, vm: PackedInt32Array,
		hv: PackedInt32Array, hn: PackedInt32Array, hp: PackedInt32Array, ht: PackedInt32Array, hf: PackedInt32Array) -> Dictionary:
	var h1 := _rarest(hs1, hv, hn, hf, deg, hl, m)
	var fs := (m.faces[hf[h1]] as PackedInt32Array).size()
	var gs: Array = []
	for g in hs2:
		if (m.faces[hf[g]] as PackedInt32Array).size() == fs and deg[hv[g]] == deg[hv[hn[h1]]] and deg[hv[hn[g]]] == deg[hv[h1]]:
			gs.append([absf(hl[g] - hl[h1]), g])
	gs.sort_custom(func(x, y): return x[0] < y[0])
	var best := {}
	var berr := INF
	for q0 in mini(gs.size(), 64):
		var r := _bfs(h1, gs[q0][1], hv, hn, hp, ht, hf, m, vm)
		if int(r["clash"]) > 0:
			continue
		var err := 0.0
		var rh: PackedInt32Array = r["h"]
		for q in range(0, rh.size(), 2):
			err += absf(hl[rh[q]] - hl[rh[q + 1]])
		if err < berr:
			berr = err
			best = r
	return best


## the half-edge of a piece whose (face size, valences, length to 0.1 mm) signature is the rarest in it
static func _rarest(hs: Array, hv: PackedInt32Array, hn: PackedInt32Array, hf: PackedInt32Array, deg: PackedInt32Array,
		hl: PackedFloat32Array, m: KMesh) -> int:
	var count := {}
	var sig := {}
	for h in hs:
		var k := "%d|%d|%d|%d" % [(m.faces[hf[h]] as PackedInt32Array).size(), deg[hv[h]], deg[hv[hn[h]]], roundi(hl[h] * 1e4)]
		sig[h] = k
		count[k] = int(count.get(k, 0)) + 1
	var best: int = hs[0]
	var bn := 1 << 30
	for h in hs:
		var n: int = count[sig[h]]
		if n < bn:
			bn = n
			best = h
	return best


static func _none(cands: Array) -> bool:
	for c in cands:
		if not (c as Array).is_empty():
			return false
	return true


## per piece: [[h, g], ...], the centre-line seeds (both ends on the plane, or straddling it) first
static func _seeds(m: KMesh, pos: PackedInt32Array, comp: PackedInt32Array, ncomp: int, hp: PackedInt32Array) -> Array:
	var hv := m.he_vert
	var hn := m.he_next
	var centre: Array = []
	var other: Array = []
	for c in ncomp:
		centre.append([])
		other.append([])
	for h in hv.size():
		var a := hv[h]
		var b := hv[hn[h]]
		var a2 := pos[a]
		var b2 := pos[b]
		if a2 < 0 or b2 < 0:
			continue
		var g := m.find_half_edge(b2, a2)
		if g < 0:
			continue
		if (a2 == a and b2 == b) or (a2 == b and b2 == a):
			(centre[comp[h]] as Array).append([h, g])
		else:
			(other[comp[h]] as Array).append([h, g])
	var out: Array = []
	for c in ncomp:
		out.append((centre[c] as Array) + (other[c] as Array) if not (centre[c] as Array).is_empty() else other[c])
	return out


## one BFS from the pair (h0, g0): {"v": vert -> partner (-2 = given two), "h": the half-edges reached, "n", "clash"}
static func _bfs(h0: int, g0: int, hv: PackedInt32Array, hn: PackedInt32Array, hp: PackedInt32Array, ht: PackedInt32Array,
		hf: PackedInt32Array, m: KMesh, taken: PackedInt32Array) -> Dictionary:
	var hm := {}
	var vmap := {}
	var clash := 0
	var reached := PackedInt32Array()
	var q := PackedInt32Array([h0, g0])
	var qi := 0
	while qi < q.size():
		var h := q[qi]
		var g := q[qi + 1]
		qi += 2
		if hm.has(h):
			if hm[h] != g:
				clash += 1
			continue
		if hm.has(g) and hm[g] != h:
			clash += 1
			continue
		if (m.faces[hf[h]] as PackedInt32Array).size() != (m.faces[hf[g]] as PackedInt32Array).size():
			clash += 1
			continue
		hm[h] = g
		hm[g] = h
		reached.append(h)
		reached.append(g)
		var a := hv[h]
		var b := hv[hn[h]]
		var b2 := hv[g]
		var a2 := hv[hn[g]]
		for pr in [[a, a2], [b, b2], [a2, a], [b2, b]]:
			var x: int = pr[0]
			var y: int = pr[1]
			if taken[x] >= 0:
				continue
			var cur: int = vmap.get(x, -1)
			if cur == -1:
				vmap[x] = y
			elif cur != y and cur != -2:
				vmap[x] = -2
				clash += 1
		q.append_array([hn[h], hp[g], hp[h], hn[g]])
		var th := ht[h]
		var tg := ht[g]
		if th >= 0 and tg >= 0:
			q.append_array([th, tg])
		elif (th >= 0) != (tg >= 0):
			clash += 1
	var n := 0
	for v in vmap:
		if vmap[v] >= 0:
			n += 1
	return {"v": vmap, "h": reached, "n": n, "clash": clash}


## the map for these settings, cached until the topology, the axis, the plane or the mode change
func map_for(m: KMesh, xf := Transform3D.IDENTITY) -> Dictionary:
	var plane := plane_for(m, axis, space, xf)
	var k := "%d|%d|%s|%s|%s|%d|%d" % [m.get_instance_id(), axis, str(plane), str(topo), str(tol), m.verts.size(), m.faces.hash()]
	if k != _key or last.is_empty():
		last = build(m, axis, plane, tol, topo)
		_key = k
	return last


# ---------------------------------------------------------------- edits

## an edit with the mirror on begins: the map now (cached), the verts the edit writes itself
func prepare(m: KMesh, xf: Transform3D, idx: PackedInt32Array) -> void:
	_idx = {}
	for i in idx:
		_idx[i] = true
	_mirrored = PackedInt32Array()
	if on:
		map_for(m, xf)


## after the edit wrote its verts (from `before`, the positions at its start): every vert it moved gives its partner the
## mirrored move (before + the move with the axis part negated); a vert on the plane keeps its coordinate on the axis.
## A partner the edit moved itself, or one of the selection, is left as the edit put it. Returns the partners moved.
func follow(m: KMesh, before: PackedVector3Array) -> int:
	if not on or last.is_empty() or before.size() != m.verts.size():
		return 0
	var map: PackedInt32Array = last["map"]
	if map.size() != m.verts.size():
		return 0
	var ax := int(last["axis"])
	var vs := m.verts
	m.verts = PackedVector3Array()   # one owner while writing
	for j in _mirrored:   # the partners set by the last call go back first: this call decides them again
		vs[j] = before[j]
	var moved := PackedInt32Array()
	for i in vs.size():
		if vs[i] != before[i]:
			moved.append(i)
	var mv := {}
	for i in moved:
		mv[i] = true
	var out := PackedInt32Array()
	for i in moved:
		var j := map[i]
		if j < 0:
			continue
		if j == i:
			var c := vs[i]
			c[ax] = before[i][ax]
			vs[i] = c
			continue
		if mv.has(j) or _idx.has(j):
			continue
		vs[j] = before[j] + flip(vs[i] - before[i], ax)
		out.append(j)
	m.verts = vs
	_mirrored = out
	return out.size()


## the sculpt stroke's params with the mirror on: the partner map and its axis (KMeshSculpt's vertex-pair path)
func sculpt_params(m: KMesh, xf: Transform3D, p: Dictionary) -> Dictionary:
	if not on:
		return p
	var r := map_for(m, xf)
	p["sym_x"] = true
	p["sym_map"] = r["map"]
	p["sym_axis"] = int(r["axis"])
	return p


# ---------------------------------------------------------------- symmetrize, asymmetry

## the signed offset of a vert from the plane
static func _off(m: KMesh, v: int, ax: int, plane: float) -> float:
	return m.verts[v][ax] - plane


## copy one side onto the other through the map (positive: the + side is kept, the - side becomes its image).
## Verts on the plane are put on it. Unpaired verts are left. Returns the verts written.
static func symmetrize(m: KMesh, map: PackedInt32Array, ax: int, plane: float, positive := true) -> int:
	var vs := m.verts
	m.verts = PackedVector3Array()
	var n := 0
	for v in map.size():
		var u := map[v]
		if u < 0 or u < v:
			continue
		if u == v:
			if vs[v][ax] != plane:
				var c := vs[v]
				c[ax] = plane
				vs[v] = c
				n += 1
			continue
		var ov := vs[v][ax] - plane
		var ou := vs[u][ax] - plane
		var src := v if (ov >= ou) == positive else u
		var dst := u if src == v else v
		var want := reflect(vs[src], ax, plane)
		if vs[dst] != want:
			vs[dst] = want
			n += 1
	m.verts = vs
	m._compute_normals()
	return n


## how far each pair is from mirror images: {"plus": the + side vert of each pair off by more than `thr` (a centre
## vert off the plane counts as its own), "minus": their partners, "max" (m), "max_mm", "dev": per vert (m)}
static func asymmetry(m: KMesh, map: PackedInt32Array, ax: int, plane: float, thr := ASYM_TOL) -> Dictionary:
	var dev := PackedFloat32Array()
	dev.resize(map.size())
	var plus := PackedInt32Array()
	var minus := PackedInt32Array()
	var mx := 0.0
	for v in map.size():
		var u := map[v]
		if u < 0 or u < v:
			continue
		var d := absf(m.verts[v][ax] - plane) if u == v else m.verts[u].distance_to(reflect(m.verts[v], ax, plane))
		dev[v] = d
		dev[u] = d
		mx = maxf(mx, d)
		if d > thr:
			if u == v:
				plus.append(v)
			elif m.verts[v][ax] - plane >= m.verts[u][ax] - plane:
				plus.append(v)
				minus.append(u)
			else:
				plus.append(u)
				minus.append(v)
	plus.sort()
	minus.sort()
	return {"plus": plus, "minus": minus, "max": mx, "max_mm": mx * 1000.0, "dev": dev}


# ---------------------------------------------------------------- the ops (scripts/mesh_tools.gd)

static func _select(ui, vs: PackedInt32Array) -> void:
	ui.sel.set_mode(KMeshSelect.VERT)
	ui.sel.clear()
	for v in vs:
		ui.sel.verts[v] = true
	ui.view.mark_dirty()


static func op(name: String, main) -> String:
	var s := get_shared()
	var ui = main.kmed
	var xf: Transform3D = ui.view.global_transform if ui.view != null else Transform3D.IDENTITY
	match name:
		"mirror_edit":
			s.on = not s.on
			if s.on:
				var r := s.map_for(ui.mesh, xf)
				return "Model: %s. G / R / S and sculpt strokes move the partner too; %.1f %% of the verts have one" % [s.words(), r["pct"]]
			return "Model: %s" % s.words()
		"mirror_axis":
			s.axis = (s.axis + 1) % 3
			return "Model: %s" % s.words()
		"mirror_space":
			s.space = WORLD if s.space == LOCAL else LOCAL
			return "Model: %s, the plane at %s = %s" % [s.words(), axis_name(s.axis), Units.len(plane_for(ui.mesh, s.axis, s.space, xf))]
		"mirror_topo":
			s.topo = not s.topo
			return "Model: %s" % s.words()
		"mirror_map":
			var r := s.map_for(ui.mesh, xf)
			_select(ui, r["unpaired"])
			return "Model: %s map: %.1f %% of %d verts partnered (%d by connectivity, %d by position, %d on the plane); %d without a partner%s" % [
				axis_name(s.axis), r["pct"], ui.mesh.verts.size(), r["topo_pairs"], r["pos_pairs"], r["centre"], (r["unpaired"] as PackedInt32Array).size(),
				" (selected)" if not (r["unpaired"] as PackedInt32Array).is_empty() else ""]
		"symmetrize", "symmetrize_minus":
			var r := s.map_for(ui.mesh, xf)
			ui.undo.begin(ui.mesh)
			var n := symmetrize(ui.mesh, r["map"], int(r["axis"]), float(r["plane"]), name == "symmetrize")
			ui.undo.commit("Symmetrize")
			ui.view.mark_dirty()
			var sd := "+" if name == "symmetrize" else "-"
			return "Model: symmetrized %s%s onto the other side: %d verts moved (one undo step)%s" % [sd, axis_name(s.axis), n,
				"; %d verts have no partner and were left" % (r["unpaired"] as PackedInt32Array).size() if not (r["unpaired"] as PackedInt32Array).is_empty() else ""]
		"mirror_asym":
			var r := s.map_for(ui.mesh, xf)
			var a := asymmetry(ui.mesh, r["map"], int(r["axis"]), float(r["plane"]))
			_select(ui, a["plus"])
			if (a["plus"] as PackedInt32Array).is_empty():
				return "Model: symmetric in %s: every partner is at its mirror image (largest deviation %.3f mm)" % [axis_name(s.axis), a["max_mm"]]
			return "Model: %d verts are not mirrored by their partner (selected, + side); the largest deviation is %.1f mm" % [(a["plus"] as PackedInt32Array).size(), a["max_mm"]]
	return ""
