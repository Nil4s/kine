class_name ArmourFromBody
extends RefCounted
## B23 (docs/ROADMAP_400.md): ARMOUR FROM THE BODY. Pick A19 anatomy tags (forearm_extensors_r, deltoid_l, pectoral ...)
## or A18 regions (forearm_r, shin_l ...) and get a plate shell as a new KMesh, skinned, on the fighter as its own part.
##   PATCH: the body's faces whose corners are mostly (more than half) in the picked tags / regions, copied. A stem with
##     no side ("pectoral") picks both sides. The patch is cleaned to a surface the solidify and bevel can work on: faces on
##     an edge used three times or twice the same way are dropped, a vertex whose faces form two fans keeps the larger fan,
##     pieces under MIN_FACES faces are dropped (each removal is counted in the result).
##   OUTWARD, CHECKED: the welded mannequin KMesh winds its faces the other way (A19's note: its KMesh normals point in),
##     so the winding is not trusted. Each patch vertex's normal is compared with the way out from its nearest REST bone
##     segment (the vertex minus the closest point of that segment); the patch is turned over when most point in, and the
##     verts still pointing in after that are counted ("inward", 0 on a clean plate).
##   GAP: each vertex goes out along its (outward) normal by `gap` (4 mm), then the step is corrected (GAP_ITERS times,
##     factor clamped to 0.5 .. 2) so its distance to the nearest body triangle IS the gap: on a convex patch the vertex
##     itself is the nearest point and the step stays the gap; in a hollow the nearest point is a face, the step grows.
##   THICKNESS: KMeshModifiers.solidify (A11) with offset +1: the gapped surface is the inside of the shell, the outside
##     `thickness` (3 mm) further out, a rim quad on every border edge.
##   BEVEL: KMeshBevel.bevel_edges (B03) on both border loops (outer and inner), `bevel` wide (1 mm; at most half the
##     thickness, the rim is 2 x the bevel tall), `segments` 1 = a chamfer.
##   SKINNED: every shell vertex takes the "skin:<bone>" weights (G01's channel names) of the NEAREST BODY VERTEX (fitted
##     to 4 bones summing to 1, as the GPU holds them), and its anatomy tag by A19's transfer (nearest surface point).
##   PARTS: "armour_part" (face channel): 0 outside, 1 inside, 2 rim, 3 bevel; "armour_src" (vert): the body vertex the
##     weights came from.
## ON THE FIGHTER (attach): a skinned MeshInstance3D beside the body pieces (same parent, skeleton and skin), named
##   armour_<n>, ONE step of main's undo: main's snapshot carries the list of attached parts (snap) and _restore puts
##   that list back (restore). Shown in the body preview as an unskinned copy under the preview's view (ArmourUI keeps
##   them in step). THE SCENE KEEPS THEM: the scene's "armour" key (to_file / from_scene, the KMesh exact), written by
##   main._scene_dict, so the save, the autosave and the journal hold them; a scene file without the key has none.
## Tests: tests/armour_test.gd.

const GAP := 0.004
const THICK := 0.003
const BEVEL := 0.001
const SEGMENTS := 1
const BUILDER := "1"           # the plate builder's version: bump when build() changes what a plate looks like (keys the shipped pictures)
const MIN_FACES := 4
const GAP_ITERS := 3
const KEEP := 0.875           # a plate point nearer other skin than this x the gap is cut back (KEEP CLEAR)
const TRIM_ROUNDS := 8
const CELL := 0.01            # m: the triangle / vertex grids
const CH_PART := "armour_part"
const CH_SRC := "armour_src"
const META_PARTS := "armour_parts"   # on main: the parts attached now (Array of MeshInstance3D)
const META_ALL := "armour_all"       # on main: every part ever made (kept so undo / redo can put one back)
const COLOR := Color(0.63, 0.66, 0.70)


# ---------------------------------------------------------------- words

## the words ("forearm_extensors_r, deltoid_l pectoral forearm_r") -> {"tags": {tag index: true}, "regions": {region index:
## true}, "unknown": [words], "names": [the tags / regions picked]}
static func parse(words: String) -> Dictionary:
	var out := {"tags": {}, "regions": {}, "unknown": [], "names": []}
	for w in words.replace(",", " ").replace(";", " ").split(" ", false):
		var s := String(w).strip_edges().to_lower()
		if s == "":
			continue
		if KMeshAnatomy.TAGS.has(s):
			out["tags"][KMeshAnatomy.TAGS.find(s)] = true
			out["names"].append(s)
		elif KMeshBody.REGIONS.has(s):
			out["regions"][KMeshBody.REGIONS.find(s)] = true
			out["names"].append(s)
		elif KMeshAnatomy.PAIRED.has(s):
			for sd in ["_l", "_r"]:
				out["tags"][KMeshAnatomy.TAGS.find(s + sd)] = true
				out["names"].append(s + sd)
		else:
			out["unknown"].append(s)
	return out


# ---------------------------------------------------------------- grids (nearest triangle / vertex)

## triangles bucketed in CELL cells; nearest() = the closest surface point (Ericson's closest point, KMeshAnatomy)
class TriGrid:
	var P: PackedVector3Array
	var T: PackedInt32Array
	var g := {}
	var stamp := PackedInt32Array()
	var q := 0

	func _init(pts: PackedVector3Array, tris: PackedInt32Array, lo: Vector3, hi: Vector3) -> void:
		P = pts
		var inv := 1.0 / CELL
		for k in tris.size() / 3:
			var a := pts[tris[k * 3]]
			var b := pts[tris[k * 3 + 1]]
			var c := pts[tris[k * 3 + 2]]
			var l := a.min(b).min(c)
			var h := a.max(b).max(c)
			if h.x < lo.x or h.y < lo.y or h.z < lo.z or l.x > hi.x or l.y > hi.y or l.z > hi.z:
				continue
			var kk := T.size() / 3
			T.append_array([tris[k * 3], tris[k * 3 + 1], tris[k * 3 + 2]])
			for x in range(floori(l.x * inv), floori(h.x * inv) + 1):
				for y in range(floori(l.y * inv), floori(h.y * inv) + 1):
					for z in range(floori(l.z * inv), floori(h.z * inv) + 1):
						var key := Vector3i(x, y, z)
						if g.has(key):
							(g[key] as Array).append(kk)
						else:
							g[key] = [kk]
		stamp.resize(T.size() / 3)
		stamp.fill(-1)

	## -> [distance, closest point, triangle (index into T / 3)]; [INF, p, -1] when nothing within max_r
	func nearest(p: Vector3, max_r := 0.06) -> Array:
		q += 1
		var inv := 1.0 / CELL
		var c := Vector3i(floori(p.x * inv), floori(p.y * inv), floori(p.z * inv))
		var bd := INF
		var bp := p
		var bt := -1
		for r in ceili(max_r * inv) + 1:
			for x in range(-r, r + 1):
				for y in range(-r, r + 1):
					for z in range(-r, r + 1):
						if maxi(absi(x), maxi(absi(y), absi(z))) != r:
							continue
						var cell = g.get(c + Vector3i(x, y, z))
						if cell == null:
							continue
						for k in (cell as Array):
							if stamp[k] == q:
								continue
							stamp[k] = q
							var a := P[T[k * 3]]
							var b := P[T[k * 3 + 1]]
							var cc := P[T[k * 3 + 2]]
							var w := KMeshAnatomy._closest_bary(p, a, b, cc)
							var s := a * w.x + b * w.y + cc * w.z
							var d := p.distance_squared_to(s)
							if d < bd:
								bd = d
								bp = s
								bt = k
			if bt >= 0 and sqrt(bd) <= r * CELL:   # every cell not looked in yet is further than that
				break
		return [sqrt(bd) if bt >= 0 else INF, bp, bt]


## the nearest of a set of points (bucketed the same way) -> its index, -1 when none within max_r
static func nearest_point(pts: PackedVector3Array, grid: Dictionary, p: Vector3, max_r := 0.08) -> int:
	var inv := 1.0 / CELL
	var c := Vector3i(floori(p.x * inv), floori(p.y * inv), floori(p.z * inv))
	var bd := INF
	var bi := -1
	for r in ceili(max_r * inv) + 1:
		for x in range(-r, r + 1):
			for y in range(-r, r + 1):
				for z in range(-r, r + 1):
					if maxi(absi(x), maxi(absi(y), absi(z))) != r:
						continue
					var cell = grid.get(c + Vector3i(x, y, z))
					if cell == null:
						continue
					for i in (cell as Array):
						var d := p.distance_squared_to(pts[i])
						if d < bd or (d == bd and i < bi):
							bd = d
							bi = i
		if bi >= 0 and sqrt(bd) <= r * CELL:
			break
	return bi


static func point_grid(pts: PackedVector3Array, lo: Vector3, hi: Vector3) -> Dictionary:
	var inv := 1.0 / CELL
	var g := {}
	for i in pts.size():
		var p := pts[i]
		if p.x < lo.x or p.y < lo.y or p.z < lo.z or p.x > hi.x or p.y > hi.y or p.z > hi.z:
			continue
		var key := Vector3i(floori(p.x * inv), floori(p.y * inv), floori(p.z * inv))
		if g.has(key):
			(g[key] as Array).append(i)
		else:
			g[key] = [i]
	return g


static func triangles(k: KMesh) -> PackedInt32Array:
	var t := PackedInt32Array()
	for f in k.faces:
		var fp: PackedInt32Array = f
		for i in range(1, fp.size() - 1):
			t.append_array([fp[0], fp[i], fp[i + 1]])
	return t


# ---------------------------------------------------------------- the patch

## the faces of `body` in the picked tags / regions (more than half their corners)
static func pick_faces(body: KMesh, pk: Dictionary) -> PackedInt32Array:
	var tg = body.attr_data(KMeshAnatomy.CH) if body.has_attr(KMeshAnatomy.CH) else null
	var rg = body.attr_data(KMeshBody.CH_REGION) if body.has_attr(KMeshBody.CH_REGION) else null
	var out := PackedInt32Array()
	for fi in body.faces.size():
		var f: PackedInt32Array = body.faces[fi]
		var n := 0
		for v in f:
			if (tg != null and pk["tags"].has(int(tg[v]))) or (rg != null and pk["regions"].has(int(rg[v]))):
				n += 1
		if n * 2 > f.size():
			out.append(fi)
	return out


## the faces copied into a new KMesh (compact verts) -> [KMesh, body vertex of each patch vertex]
static func copy_faces(body: KMesh, fs: PackedInt32Array) -> Array:
	var map := {}
	var src := PackedInt32Array()
	var pv := PackedVector3Array()
	var pf: Array = []
	for fi in fs:
		var g := PackedInt32Array()
		for v in (body.faces[fi] as PackedInt32Array):
			if not map.has(v):
				map[v] = pv.size()
				pv.append(body.verts[v])
				src.append(v)
			g.append(map[v])
		pf.append(g)
	return [KMesh.new().from_arrays(pv, pf), src]


## the faces of fs to drop so the rest is a clean surface: -> {"drop": {face: true}, "edges", "fans"} (one pass)
static func _bad_faces(k: KMesh) -> Dictionary:
	var nv := k.verts.size()
	var drop := {}
	var und := {}
	var dir := {}
	for fi in k.faces.size():
		var f: PackedInt32Array = k.faces[fi]
		for i in f.size():
			var a := f[i]
			var b := f[(i + 1) % f.size()]
			var key := mini(a, b) * nv + maxi(a, b)
			if not und.has(key):
				und[key] = []
			(und[key] as Array).append(fi)
			dir[a * nv + b] = int(dir.get(a * nv + b, 0)) + 1
	var ne := 0
	for key in und:
		var fl: Array = und[key]
		var a: int = key / nv
		var b: int = key % nv
		if fl.size() > 2 or int(dir.get(a * nv + b, 0)) > 1 or int(dir.get(b * nv + a, 0)) > 1:
			for fi in fl:
				drop[fi] = true
			ne += 1
	if not drop.is_empty():
		return {"drop": drop, "edges": ne, "fans": 0}
	# a vertex whose faces form more than one fan: keep the largest (faces joined through an edge at the vertex)
	var nfan := 0
	for v in nv:
		var vf := k.vert_faces(v)
		if vf.size() < 2:
			continue
		var par := {}
		for fi in vf:
			par[fi] = fi
		var find := func(x: int) -> int:
			while par[x] != x:
				x = par[x]
			return x
		for fi in vf:
			var f: PackedInt32Array = k.faces[fi]
			var i := f.find(v)
			for w in [f[(i + 1) % f.size()], f[(i + f.size() - 1) % f.size()]]:
				for gi in vf:
					if gi != fi and (k.faces[gi] as PackedInt32Array).has(w):
						var ra: int = find.call(fi)
						var rb: int = find.call(gi)
						if ra != rb:
							par[maxi(ra, rb)] = mini(ra, rb)
		var groups := {}
		for fi in vf:
			var r: int = find.call(fi)
			if not groups.has(r):
				groups[r] = []
			(groups[r] as Array).append(fi)
		if groups.size() > 1:
			nfan += 1
			var best = null
			for r in groups:
				if best == null or (groups[r] as Array).size() > (groups[best] as Array).size():
					best = r
			for r in groups:
				if r != best:
					for fi in groups[r]:
						drop[fi] = true
	return {"drop": drop, "edges": 0, "fans": nfan}


## clean the patch (see the header) -> [KMesh, src, {"edges", "fans", "small"} removals]
static func clean(k: KMesh, src: PackedInt32Array) -> Array:
	var stat := {"edges": 0, "fans": 0, "small": 0}
	for it in 30:
		var bad := _bad_faces(k)
		# pieces under MIN_FACES faces
		var comp := PackedInt32Array()
		comp.resize(k.faces.size())
		comp.fill(-1)
		var sizes := []
		for f0 in k.faces.size():
			if comp[f0] >= 0:
				continue
			var cid := sizes.size()
			var st := [f0]
			comp[f0] = cid
			var n := 0
			while not st.is_empty():
				var fi: int = st.pop_back()
				n += 1
				for v in (k.faces[fi] as PackedInt32Array):
					for g in k.vert_faces(v):
						if comp[g] < 0:
							comp[g] = cid
							st.append(g)
			sizes.append(n)
		var drop: Dictionary = bad["drop"]
		for fi in k.faces.size():
			if int(sizes[comp[fi]]) < MIN_FACES and not drop.has(fi):
				drop[fi] = true
				stat["small"] += 1
		stat["edges"] += int(bad["edges"])
		stat["fans"] += int(bad["fans"])
		if drop.is_empty():
			break
		var keep := PackedInt32Array()
		for fi in k.faces.size():
			if not drop.has(fi):
				keep.append(fi)
		var r := copy_faces(k, keep)
		var ns := PackedInt32Array()
		for v in (r[1] as PackedInt32Array):
			ns.append(src[v])
		k = r[0]
		src = ns
	return [k, src, stat]


# ---------------------------------------------------------------- the shell

## the skeleton's REST bone segments in the mesh's space: {UE5 bone name: [a, b]}
static func rest_segments(sk: Skeleton3D, xf: Transform3D) -> Dictionary:
	var xi := xf.affine_inverse()
	var out := {}
	if sk == null:
		return out
	for s in KMeshBody.segments_from_skeleton(sk, false):
		out[s["bone"]] = [xi * (s["a"] as Vector3), xi * (s["b"] as Vector3)]
	return out


## the way out (unit) at p from the segment of `bone` (the bone that carries that flesh: the heaviest skin weight), or
## from the nearest segment when that bone has none; ZERO when there are no segments
static func way_out(segs: Dictionary, p: Vector3, bone := "") -> Vector3:
	if segs.has(bone):
		var q := Geometry3D.get_closest_point_to_segment(p, segs[bone][0], segs[bone][1])
		if p.distance_to(q) > 1e-6:
			return (p - q).normalized()
	var bd := INF
	var bq := p
	for b in segs:
		var q := Geometry3D.get_closest_point_to_segment(p, segs[b][0], segs[b][1])
		var d := p.distance_squared_to(q)
		if d < bd:
			bd = d
			bq = q
	return (p - bq).normalized() if bd < INF else Vector3.ZERO


## the heaviest "skin:" bone of body vertex v ("" when it has none)
static func heaviest(body: KMesh, chans: Array, v: int) -> String:
	var best := ""
	var bw := 0.0
	for nm in chans:
		var w: float = (body.attr_data(nm) as PackedFloat32Array)[v]
		if w > bw:
			bw = w
			best = String(nm).substr(BaseBody.W.length())
	return best


## normals that point out: n, or where n points into the body (n . out < 0), n turned square to `out` plus half of
## `out` (so the offset never goes in). -> [normals, how many were turned]
static func outward(vn: PackedVector3Array, outs: PackedVector3Array) -> Array:
	var out := vn.duplicate()
	var n := 0
	for v in vn.size():
		var o := outs[v]
		if o != Vector3.ZERO and vn[v].dot(o) < 0.0:
			out[v] = (vn[v] - o * vn[v].dot(o) + o * 0.5).normalized()
			n += 1
	return [out, n]


## THE OP: a plate shell over the picked part of `body` (see the header). body: the fighter's skin as a KMesh in its mesh
## space (BaseBody.read, or the body open in the preview), tags seeded when it has none; sk: the fighter's skeleton; xf:
## the mesh's space -> world. opts: gap, thickness, bevel, segments (m / count).
## -> {"ok", "error", "mesh", "names", "patch_faces", "inward", "flipped", "removed", "bevel_width", "bevel_error", "ms"}
static func build(body: KMesh, sk: Skeleton3D, xf: Transform3D, words: String, opts := {}) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var gap: float = float(opts.get("gap", GAP))
	var thick: float = float(opts.get("thickness", THICK))
	var bw: float = minf(float(opts.get("bevel", BEVEL)), thick * 0.5)
	var segn: int = int(opts.get("segments", SEGMENTS))
	var pk := parse(words)
	if not (pk["unknown"] as Array).is_empty():
		return _fail("no tag or region called %s. Tags: Alt+H shows them on the body (forearm_extensors_r, deltoid_l, pectoral ...); regions: Shift+H (forearm_r, shin_l ...)" % ", ".join(pk["unknown"]))
	if (pk["names"] as Array).is_empty():
		return _fail("name one or more anatomy tags or regions first (e.g. forearm_extensors_r, deltoid_l)")
	if (not body.has_attr(KMeshAnatomy.CH) or not body.has_attr(KMeshBody.CH_REGION)) and sk != null:
		KMeshAnatomy.seed_tags(body, sk, xf)
	var fs := pick_faces(body, pk)
	if fs.is_empty():
		return _fail("no face of the body is tagged %s (paint the tag first: Alt+H, Alt+drag)" % ", ".join(pk["names"]))
	var cp := copy_faces(body, fs)
	var cl := clean(cp[0], cp[1])
	var patch: KMesh = cl[0]
	var psrc: PackedInt32Array = cl[1]
	if patch.faces.is_empty():
		return _fail("the faces tagged %s do not make a surface a plate can be made from (only scraps): paint a larger area" % ", ".join(pk["names"]))
	# outward, checked against the bones
	var segs := rest_segments(sk, xf)
	var chans := []
	for nm in body.list_attrs():
		if String(nm).begins_with(BaseBody.W):
			chans.append(nm)
	var vote := 0
	var vn := patch.vert_normals
	var outs := PackedVector3Array()
	outs.resize(patch.verts.size())
	for v in patch.verts.size():
		outs[v] = way_out(segs, patch.verts[v], heaviest(body, chans, psrc[v]))
		vote += 1 if vn[v].dot(outs[v]) >= 0.0 else -1
	var flipped := false
	if vote < 0 and not segs.is_empty():
		var nf: Array = []
		for f in patch.faces:
			var g := PackedInt32Array(f)
			g.reverse()
			nf.append(g)
		patch.from_arrays(patch.verts, nf)
		vn = patch.vert_normals
		flipped = true
	# the gap: out along the normal, the step corrected to the measured distance
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for p in patch.verts:
		lo = lo.min(p)
		hi = hi.max(p)
	var pad := Vector3.ONE * 0.08
	var tg := TriGrid.new(body.verts, triangles(body), lo - pad, hi + pad)
	# KEEP CLEAR: where other skin rises beside the plate (the hand past a wrist edge) the plate is cut back
	var trimmed := 0
	for round in TRIM_ROUNDS:
		for v in patch.verts.size():
			outs[v] = way_out(segs, patch.verts[v], heaviest(body, chans, psrc[v]))
		var ow := outward(patch.vert_normals, outs)
		var bad := {}
		for v in patch.verts.size():
			for s in [gap, gap + thick * 0.5, gap + thick]:
				if tg.nearest(patch.verts[v] + (ow[0] as PackedVector3Array)[v] * s)[0] < gap * KEEP:
					bad[v] = true
					break
		if bad.is_empty():
			break
		var keep := PackedInt32Array()
		for fi in patch.faces.size():
			var hit := false
			for v in (patch.faces[fi] as PackedInt32Array):
				hit = hit or bad.has(v)
			if not hit:
				keep.append(fi)
		trimmed += patch.faces.size() - keep.size()
		var r := copy_faces(patch, keep)
		var ns := PackedInt32Array()
		for v in (r[1] as PackedInt32Array):
			ns.append(psrc[v])
		var c2 := clean(r[0], ns)
		patch = c2[0]
		psrc = c2[1]
		outs.resize(patch.verts.size())
		if patch.faces.is_empty():
			return _fail("no part of %s is clear of the skin around it by %s: a plate there would touch other skin" % [", ".join(pk["names"]), Units.len(gap * KEEP)])
	for v in patch.verts.size():   # (again: the last round may have cut)
		outs[v] = way_out(segs, patch.verts[v], heaviest(body, chans, psrc[v]))
	var ow := outward(patch.vert_normals, outs)
	vn = ow[0]
	var inward: int = ow[1]
	var iv := PackedVector3Array()
	iv.resize(patch.verts.size())
	for v in patch.verts.size():
		iv[v] = patch.verts[v] + vn[v] * _step(tg, patch.verts[v], vn[v], gap)
	var inner := KMesh.new().from_arrays(iv, patch.faces)
	# boundary edges of the inner surface, before solidify (a -> b as its face runs)
	var bnd: Array = []
	var hv := inner.he_vert
	for h in hv.size():
		if inner.he_twin[h] == -1:
			bnd.append(Vector2i(hv[h], hv[inner.he_next[h]]))
	var nf0 := inner.faces.size()
	var nv0 := inner.verts.size()
	var shell := KMeshModifiers.solidify(inner, thick, 1.0, false, true)
	# the outside: solidify's step along the inside's (outward) normals, corrected to the measured thickness as the gap was
	var ivn: PackedVector3Array = outward(inner.vert_normals, outs)[0]
	var ig := TriGrid.new(iv, triangles(inner), lo - pad, hi + pad)
	var sv := shell.verts
	for v in nv0:
		sv[v] = iv[v] + ivn[v] * _step(ig, iv[v], ivn[v], thick)
	shell.from_arrays(sv, shell.faces)
	var nrim := shell.faces.size() - 2 * nf0
	var es: Array = []
	for e in bnd:
		es.append(Vector2i(e.x, e.y))
		es.append(Vector2i(e.x + nv0, e.y + nv0))
	var bev_err := ""
	var bev_w := 0.0
	if bw > 0.0 and not es.is_empty():
		var br := KMeshBevel.bevel_edges(shell, es, bw, segn, KMeshBevel.PROFILE)
		bev_err = String(br["error"])
		bev_w = float(br.get("width", 0.0)) if bev_err == "" else 0.0
	# the parts: outside / inside / rim keep their face order through the bevel (it appends its own faces)
	shell.add_attr(CH_PART, KMesh.AD_FACE, TYPE_FLOAT, 3.0)
	var part := PackedFloat32Array()
	part.resize(shell.faces.size())
	for fi in shell.faces.size():
		part[fi] = 0.0 if fi < nf0 else (1.0 if fi < 2 * nf0 else (2.0 if fi < 2 * nf0 + nrim else 3.0))
	shell.set_attr_data(CH_PART, part)
	# the weights of the nearest body vertex
	var slo := Vector3.INF
	var shi := -Vector3.INF
	for p in shell.verts:
		slo = slo.min(p)
		shi = shi.max(p)
	var pg := point_grid(body.verts, slo - pad, shi + pad)
	var src := PackedInt32Array()
	src.resize(shell.verts.size())
	for v in shell.verts.size():
		src[v] = nearest_point(body.verts, pg, shell.verts[v])
	copy_weights(body, shell, src)
	shell.add_attr(CH_SRC, KMesh.AD_VERT, TYPE_FLOAT, -1.0)
	var sf := PackedFloat32Array()
	for v in src:
		sf.append(float(v))
	shell.set_attr_data(CH_SRC, sf)
	if body.has_attr(KMeshAnatomy.CH):
		KMeshAnatomy.transfer(body, shell, Transform3D.IDENTITY, Transform3D.IDENTITY, 0.05, false)
	return {"ok": true, "error": "", "mesh": shell, "names": pk["names"], "patch_faces": patch.faces.size(), "picked_faces": fs.size(),
		"inward": inward, "flipped": flipped, "trimmed": trimmed, "removed": cl[2], "bevel_width": bev_w, "bevel_error": bev_err,
		"patch_src": psrc, "ms": (Time.get_ticks_usec() - t0) / 1000.0}


## every "skin:" channel of body onto shell, vertex v from body vertex src[v], fitted to 4 bones summing to 1 (canon)
## how far along n from p so the point is `want` from the surface of grid g: want, corrected GAP_ITERS times by the
## measured distance (factor clamped to 0.5 .. 2)
static func _step(g: TriGrid, p: Vector3, n: Vector3, want: float) -> float:
	var s := want
	for it in GAP_ITERS:
		var d: float = g.nearest(p + n * s)[0]
		if d == INF or d < 1e-7:
			break
		s = clampf(s * want / d, want * 0.5, want * 2.0)
	return s


static func copy_weights(body: KMesh, shell: KMesh, src: PackedInt32Array) -> void:
	var names := []
	for nm in body.list_attrs():
		if String(nm).begins_with(BaseBody.W) and body.attr_info(nm)["domain"] == KMesh.AD_VERT:
			names.append(String(nm))
	names.sort()
	var bd: Dictionary = {}
	for nm in names:
		bd[nm] = body.attr_data(nm)
	var fits := []   # per shell vertex: {channel: weight}
	fits.resize(shell.verts.size())
	for v in shell.verts.size():
		var d := {}
		if src[v] >= 0:
			for nm in names:
				var w: float = (bd[nm] as PackedFloat32Array)[src[v]]
				if w > 0.0:
					d[nm] = w
		fits[v] = _fit_named(d)
	for nm in names:   # (filled here, not through a Dictionary: a packed array in one is a copy)
		var c := PackedFloat32Array()
		c.resize(shell.verts.size())
		var any := false
		for v in shell.verts.size():
			c[v] = float((fits[v] as Dictionary).get(nm, 0.0))
			any = any or c[v] > 0.0
		if any:
			shell.add_attr(nm, KMesh.AD_VERT, TYPE_FLOAT, 0.0)
			shell.set_attr_data(nm, c)


## BaseBody.fit4 + canon on {channel name: weight} (they key on ints: the names go through an index)
static func _fit_named(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return d
	var ks := d.keys()
	ks.sort()
	var byi := {}
	for i in ks.size():
		byi[i] = d[ks[i]]
	var f := BaseBody.canon(BaseBody.fit4(byi))
	var out := {}
	for i in f:
		out[ks[i]] = f[i]
	return out


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


# ---------------------------------------------------------------- Godot meshes

## the shell as Godot surface arrays: one vertex per (vertex, corner normal; 30 deg auto smooth), Godot's winding
## (clockwise front). skin != null: ARRAY_BONES / ARRAY_WEIGHTS from the "skin:" channels (4 per vertex, binds of skin)
static func arrays(k: KMesh, skin: Skin = null, sk: Skeleton3D = null) -> Array:
	var cn := k.corner_normals(KMesh.NM_AUTO, 30.0)
	var ws: Array = BaseBody.weights_of(k, skin) if skin != null else []
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var bones := PackedInt32Array()
	var wts := PackedFloat32Array()
	var idx := PackedInt32Array()
	var seen := {}
	for fi in k.faces.size():
		var f: PackedInt32Array = k.faces[fi]
		var loc := PackedInt32Array()
		for i in f.size():
			var n: Vector3 = (cn[fi] as PackedVector3Array)[i]
			var key := [f[i], roundi(n.x * 1e5), roundi(n.y * 1e5), roundi(n.z * 1e5)]
			var got: int = seen.get(key, -1)
			if got == -1:
				got = pos.size()
				seen[key] = got
				pos.append(k.verts[f[i]])
				nor.append(n)
				if skin != null:
					var d: Dictionary = BaseBody.canon(BaseBody.fit4(ws[f[i]]))
					if d.is_empty():
						d = {BaseBody.nearest_bind(skin, sk, k.verts[f[i]]) if sk != null else 0: 1.0}
					var bk := d.keys()
					bk.sort()
					for q in BaseBody.MAX_INFL:
						bones.append(int(bk[q]) if q < bk.size() else 0)
						wts.append(float(d[bk[q]]) if q < bk.size() else 0.0)
			loc.append(got)
		for i in range(1, f.size() - 1):
			idx.append_array([loc[0], loc[i + 1], loc[i]])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nor
	arr[Mesh.ARRAY_INDEX] = idx
	if skin != null:
		arr[Mesh.ARRAY_BONES] = bones
		arr[Mesh.ARRAY_WEIGHTS] = wts
	return arr


static func material() -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.albedo_color = COLOR
	mt.metallic = 0.75
	mt.roughness = 0.38
	return mt


static func array_mesh(k: KMesh, skin: Skin = null, sk: Skeleton3D = null) -> ArrayMesh:
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays(k, skin, sk))
	am.surface_set_material(0, material())
	return am


# ---------------------------------------------------------------- on the fighter

static func parts(m: Node) -> Array:
	return m.get_meta(META_PARTS, [])


## main's snapshot: the parts attached now (the same nodes: an undo puts the list back)
static func snap(m: Node) -> Array:
	return parts(m).duplicate()


## main._restore: exactly the parts of `list` attached, the rest taken off (kept for a redo)
static func restore(m: Node, list: Array) -> void:
	if not m.has_meta(META_ALL):
		return
	for mi in m.get_meta(META_ALL):
		if not is_instance_valid(mi):
			continue
		var on := list.has(mi)
		var par: Node = (mi as Node).get_meta("armour_parent", null)
		if par == null or not is_instance_valid(par):
			continue
		if on and (mi as Node).get_parent() == null:
			par.add_child(mi)
		elif not on and (mi as Node).get_parent() != null:
			(mi as Node).get_parent().remove_child(mi)
	m.set_meta(META_PARTS, list.filter(func(x): return is_instance_valid(x)))
	ArmourUI.of(m).sync()


## the scene's key: every plate on the fighter now, as the scene file holds them (absent when there are none)
const KEY := "armour"

## the scene's "armour" list: {"label", "name", "kmesh": KMesh.to_dict()} per plate, in attach order (KMesh.to_dict is exact)
static func to_file(m: Node) -> Array:
	var out := []
	for mi in parts(m):
		if not is_instance_valid(mi):
			continue
		var n := mi as Node
		out.append({"label": String(n.get_meta("armour_label", "")), "name": String(n.name), "kmesh": (n.get_meta("armour_kmesh") as KMesh).to_dict()})
	return out


## main._load_scene / _restore_work: the fighter's plates are the scene's (the list it holds; none when the key is absent).
## Plates already there leave the fighter and are dropped; no undo step (opening a file is not an edit)
static func from_scene(m: Node, d: Dictionary) -> void:
	for mi in m.get_meta(META_ALL, []):
		if is_instance_valid(mi):
			var par0: Node = (mi as Node).get_parent()
			if par0 != null:
				par0.remove_child(mi)
			(mi as Node).queue_free()
	m.set_meta(META_ALL, [])
	m.set_meta(META_PARTS, [])
	var list = d.get(KEY, [])
	if list is Array:
		for e in list:
			if not (e is Dictionary and e.get("kmesh") is Dictionary):
				continue
			var k := KMesh.new().from_dict(e["kmesh"])
			if k == null:
				continue
			var mi := attach(m, k, String(e.get("label", "")), false)
			if mi != null and String(e.get("name", "")) != "":
				mi.name = String(e["name"])
	ArmourUI.of(m).sync()


## the shell onto the fighter as a separate skinned part: ONE step of main's undo (none when undo is false: a restore). -> the MeshInstance3D (null: no body)
static func attach(m: Node, k: KMesh, label: String, undo := true) -> MeshInstance3D:
	if m.pieces.is_empty():
		return null
	var p0: MeshInstance3D = m.pieces.values()[0]
	var skin := BaseBody.skin_of(m)
	if skin == null:
		return null
	var all: Array = m.get_meta(META_ALL, [])
	var mi := MeshInstance3D.new()
	mi.name = "armour_%d" % (all.size() + 1)
	mi.mesh = array_mesh(k, skin, m.skel)
	mi.skin = skin
	mi.transform = p0.transform
	mi.set_meta("armour_kmesh", k)
	mi.set_meta("armour_label", label)
	var par := p0.get_parent()
	mi.set_meta("armour_parent", par)
	m._step_hint = "Armour from the body (%s)" % label
	if undo:
		m._push_undo()
	par.add_child(mi)
	mi.skeleton = p0.skeleton   # the same parent: the same path to the skeleton
	all.append(mi)
	m.set_meta(META_ALL, all)
	var now := parts(m).duplicate()
	now.append(mi)
	m.set_meta(META_PARTS, now)
	return mi


## the body the plate is made from, in the fighter's mesh space: the one open in the preview (its painted tags), else the
## fighter's skin read now. -> [KMesh, mesh space -> world]
static func body_source(m: Node) -> Array:
	if BaseBody.is_open(m):
		return [m.kmed.mesh, (m.kmed.view as Node3D).global_transform]
	var p0: MeshInstance3D = m.pieces.values()[0]
	return [BaseBody.read(m), p0.global_transform]


## make a plate from `words` and put it on the fighter (one undo step). -> {"ok", "said", "part", + build()'s keys}
static func make(m: Node, words: String, opts := {}) -> Dictionary:
	if m.pieces.is_empty() or BaseBody.skin_of(m) == null:
		return {"ok": false, "said": "Model: the fighter has no skinned body to make armour from"}
	var src := body_source(m)
	var r := build(src[0], m.skel, src[1], words, opts)
	if not r["ok"]:
		r["said"] = "Model: armour: " + String(r["error"])
		return r
	var label := ", ".join(r["names"])
	var mi := attach(m, r["mesh"], label)
	r["part"] = mi
	ArmourUI.of(m).sync()
	var k: KMesh = r["mesh"]
	r["said"] = "Model: armour plate over %s: %d verts, %d faces, %s out from the skin, %s thick, edges bevelled %s%s; skinned like the skin under it, on the fighter as %s (Ctrl+Z takes it off in one step)%s" % [
		label, k.verts.size(), k.faces.size(), Units.len(float(opts.get("gap", GAP))), Units.len(float(opts.get("thickness", THICK))),
		Units.len(float(r["bevel_width"])) if String(r["bevel_error"]) == "" else "(no: " + String(r["bevel_error"]) + ")",
		"" if int(r["inward"]) == 0 else " (%d verts point into the body: check that patch)" % int(r["inward"]),
		mi.name if mi != null else "(not attached)", "" if BaseBody.is_open(m) else ". Open the body (Model: edit the body mesh) to see it in the preview"]
	return r
