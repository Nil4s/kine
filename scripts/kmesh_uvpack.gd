class_name KMeshUVPack
extends RefCounted
## KMeshUVPack: UV island packing (ROADMAP_400 D04) and one-click "game ready UVs" (D15). Pure GDScript, static funcs.
## Works on the corner attribute "uv" (KMeshUV.UV, one Vector2 per face corner = half-edge).
##
## ISLANDS come from the UVs themselves, not from the seams: two faces are in one island when they share an edge whose two
##   ends have the same UV on both sides (so a cube projection or a hand-made layout packs as drawn).
## DENSITY: each island is scaled by sqrt(area_3d / area_uv), so every island has the same texels per metre (its UV area
##   equals its 3D area before the final fit). Off: the islands keep their sizes relative to each other.
## ROTATION: "none"; "90" (the packer may turn an island a quarter turn); "free" (each island first turned to its
##   minimum-area bounding box: the convex hull's edges are the only candidate directions, the rotating-calipers fact of
##   Freeman & Shapira 1975, "Determining the minimum-area encasing rectangle for an arbitrary closed curve"; then 90 as
##   well). Turns are rotations, never mirrors.
## PACKING: MaxRects (Jylanki 2010, "A Thousand Ways to Pack the Bin"): a list of maximal free rectangles; each island's box
##   goes where a heuristic likes it best (best short side fit, best area fit, bottom-left), every free rectangle it
##   touches is split into up to four maximal ones and the ones inside another are dropped. The layout scale s (UV units
##   per metre) is the largest that still fits, found by bisection; each box is grown by the margin g = margin_px / px, so
##   islands are >= g apart and >= g / 2 from the tile's edge (two tiles side by side are then g apart too).
## TILES (D15 "4 x 1k"): islands are split into tiles (by body region = bands of equal 3D area along the mesh's height,
##   or by area = largest first into the emptiest tile), every tile packed at the SAME s (one density across tiles). Tile
##   t's UVs are written UDIM-style, u in [t, t + 1] (1001 + t), and the face attribute "uv_tile" (float) holds t.
## TEXEL DENSITY: px per metre = s * px; reported in px/cm (s * px / 100).

const UV := "uv"
const TILE := "uv_tile"
const EPS := 1e-7
const ITERS := 22             # bisection steps on the scale (2^-22 relative)
const BUDGETS := {
	"1x2k": {"tiles": 1, "px": 2048, "label": "1 x 2k (one 2048 tile)"},
	"4x1k": {"tiles": 4, "px": 1024, "label": "4 x 1k (four 1024 tiles)"},
}
const HEUR := [["bssf", "area"], ["bssf", "side"], ["baf", "area"], ["bl", "height"]]


# ---------------------------------------------------------------- islands

## {"island": per face its island id, "count": n} from the UVs: faces join over an edge whose ends match in UV on both sides
static func islands(m: KMesh, uv := UV) -> Dictionary:
	var nf := m.face_count()
	var d: PackedVector2Array = m.attr_data(uv)
	var p := PackedInt32Array()
	p.resize(nf)
	for f in nf:
		p[f] = f
	var hn := m.he_next
	var ht := m.he_twin
	var hf := m.he_face
	var hv := m.he_vert
	for h in m.half_edge_count():
		var t := ht[h]
		if t == -1 or t < h or hv[h] == hv[hn[h]]:
			continue
		# h: a->b in F, t: b->a in G. a: corner h of F, corner next(t) of G; b: next(h) of F, t of G
		if d[h].distance_squared_to(d[hn[t]]) > EPS * EPS or d[hn[h]].distance_squared_to(d[t]) > EPS * EPS:
			continue
		var x := KMeshUV._find(p, hf[h])
		var y := KMeshUV._find(p, hf[t])
		if x != y:
			p[x] = y
	var isl := PackedInt32Array()
	isl.resize(nf)
	var ids := {}
	for f in nf:
		var r := KMeshUV._find(p, f)
		if not ids.has(r):
			ids[r] = ids.size()
		isl[f] = ids[r]
	return {"island": isl, "count": ids.size()}


## per island: {"faces", "corners" (half-edges), "a3" (m^2), "auv" (|signed UV area|), "c3" (3D area centroid)}
static func island_data(m: KMesh, uv := UV, top := {}) -> Array:
	if top.is_empty():
		top = islands(m, uv)
	var d: PackedVector2Array = m.attr_data(uv)
	var isl: PackedInt32Array = top["island"]
	var out: Array = []
	for i in int(top["count"]):
		out.append({"faces": PackedInt32Array(), "corners": PackedInt32Array(), "a3": 0.0, "auv": 0.0, "c3": Vector3.ZERO})
	var he0 := m.face_he0
	for f in m.face_count():
		var r: Dictionary = out[isl[f]]
		var fp: PackedInt32Array = m.faces[f]
		var h0 := he0[f]
		var fa: PackedInt32Array = r["faces"]
		fa.append(f)
		r["faces"] = fa
		var cs: PackedInt32Array = r["corners"]
		for i in fp.size():
			cs.append(h0 + i)
		r["corners"] = cs
		var a3 := 0.0
		var su := 0.0
		var cc := Vector3.ZERO
		for i in range(1, fp.size() - 1):
			var p0 := m.verts[fp[0]]
			var p1 := m.verts[fp[i]]
			var p2 := m.verts[fp[i + 1]]
			var ta := 0.5 * (p1 - p0).cross(p2 - p0).length()
			a3 += ta
			cc += (p0 + p1 + p2) / 3.0 * ta
			su += 0.5 * (d[h0 + i] - d[h0]).cross(d[h0 + i + 1] - d[h0])
		r["a3"] = float(r["a3"]) + a3
		r["auv"] = float(r["auv"]) + su
		r["c3"] = (r["c3"] as Vector3) + cc
	for r in out:
		r["auv"] = absf(float(r["auv"]))
		r["c3"] = (r["c3"] as Vector3) / float(r["a3"]) if float(r["a3"]) > 1e-20 else Vector3.ZERO
	return out


## per island its texel density in px per metre: sqrt(area_uv / area_3d) * px (islands with no 3D area are skipped)
static func densities(m: KMesh, px := 1024, uv := UV) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for r in island_data(m, uv):
		if float(r["a3"]) > 1e-12 and float(r["auv"]) > 1e-20:
			out.append(sqrt(float(r["auv"]) / float(r["a3"])) * px)
	return out


# ---------------------------------------------------------------- min-area box

## the angle that turns `pts` into their minimum-area bounding box (the box's sides along a hull edge)
static func min_box_angle(pts: PackedVector2Array) -> float:
	if pts.size() < 3:
		return 0.0
	var hull := Geometry2D.convex_hull(pts)
	var best := INF
	var ang := 0.0
	for i in hull.size() - 1:
		var e := hull[i + 1] - hull[i]
		if e.length_squared() < 1e-24:
			continue
		var a := e.angle()
		var c := cos(-a)
		var s := sin(-a)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for q in hull:
			var r := Vector2(q.x * c - q.y * s, q.x * s + q.y * c)
			lo = lo.min(r)
			hi = hi.max(r)
		var area := (hi.x - lo.x) * (hi.y - lo.y)
		if area < best - 1e-15:
			best = area
			ang = a
	return ang


# ---------------------------------------------------------------- MaxRects

## pack boxes (Vector2 sizes, margin already added) into the unit square. Returns per box [pos: Vector2, turned: bool],
## or [] when one does not fit. heur: "bssf" / "baf" / "bl"; order: "area" / "side" / "height"
static func maxrects(sizes: Array, rot: bool, heur := "bssf", order := "area") -> Array:
	var idx := range(sizes.size())
	var key := func(i: int) -> float:
		var s: Vector2 = sizes[i]
		match order:
			"side":
				return maxf(s.x, s.y)
			"height":
				return s.y if not rot else minf(s.x, s.y)
		return s.x * s.y
	idx.sort_custom(func(a, b): return key.call(a) > key.call(b))
	var free: Array = [Rect2(0, 0, 1, 1)]
	var out: Array = []
	out.resize(sizes.size())
	for i in idx:
		var sz: Vector2 = sizes[i]
		var best := [INF, INF]
		var bpos := Vector2.ZERO
		var bturn := false
		var found := false
		for fr in free:
			var r := fr as Rect2
			for turn in ([false, true] if rot and absf(sz.x - sz.y) > 1e-12 else [false]):
				var w := sz.y if turn else sz.x
				var h := sz.x if turn else sz.y
				if w > r.size.x + 1e-12 or h > r.size.y + 1e-12:
					continue
				var lx := r.size.x - w
				var ly := r.size.y - h
				var sc: Array
				match heur:
					"baf":
						sc = [r.size.x * r.size.y - w * h, minf(lx, ly)]
					"bl":
						sc = [r.position.y + h, r.position.x]
					_:
						sc = [minf(lx, ly), maxf(lx, ly)]
				if sc[0] < best[0] - 1e-15 or (absf(sc[0] - best[0]) <= 1e-15 and sc[1] < best[1]):
					best = sc
					bpos = r.position
					bturn = turn
					found = true
		if not found:
			return []
		out[i] = [bpos, bturn]
		var pl := Rect2(bpos, Vector2(sz.y, sz.x) if bturn else sz)
		_split(free, pl)
	return out


## cut the placed rect out of every free rect it overlaps (up to 4 maximal pieces each), then drop pieces inside others
static func _split(free: Array, u: Rect2) -> void:
	var keep: Array = []
	var fresh: Array = []
	for fr in free:
		var r := fr as Rect2
		if u.position.x >= r.end.x - 1e-12 or u.end.x <= r.position.x + 1e-12 or u.position.y >= r.end.y - 1e-12 or u.end.y <= r.position.y + 1e-12:
			keep.append(r)
			continue
		if u.position.x > r.position.x + 1e-12:
			fresh.append(Rect2(r.position, Vector2(u.position.x - r.position.x, r.size.y)))
		if u.end.x < r.end.x - 1e-12:
			fresh.append(Rect2(Vector2(u.end.x, r.position.y), Vector2(r.end.x - u.end.x, r.size.y)))
		if u.position.y > r.position.y + 1e-12:
			fresh.append(Rect2(r.position, Vector2(r.size.x, u.position.y - r.position.y)))
		if u.end.y < r.end.y - 1e-12:
			fresh.append(Rect2(Vector2(r.position.x, u.end.y), Vector2(r.size.x, r.end.y - u.end.y)))
	# the kept rects are maximal among themselves already: only the fresh ones need checking (against all)
	var nf: Array = []
	for i in fresh.size():
		var a: Rect2 = fresh[i]
		var inside := false
		for k in keep:
			if (k as Rect2).encloses(a):
				inside = true
				break
		if not inside:
			for j in fresh.size():
				if j != i and (fresh[j] as Rect2).encloses(a) and (not a.encloses(fresh[j]) or j < i):
					inside = true
					break
		if not inside:
			nf.append(a)
	free.clear()
	free.append_array(keep)
	free.append_array(nf)


# ---------------------------------------------------------------- pack

## Pack the islands of `uv`. opts: "px" (texture side, 1024), "margin" (px between islands, 4), "rotate" ("90" / "free" /
## "none", "90"), "density" (true: equal texels per metre), "tiles" (1), "split" ("region" / "area"), "uv".
## Returns {"ok", "islands", "tiles", "scale" (UV per m), "px_per_m", "px_per_cm", "efficiency" (UV area / tile area, mean
## over the tiles), "tile_eff" (per tile), "spread" (max / min island density - 1), "ms", "why" (when not ok)}.
static func pack(m: KMesh, opts := {}) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var uv: String = opts.get("uv", UV)
	var px := int(opts.get("px", 1024))
	var g := float(opts.get("margin", 4.0)) / float(px)
	var rotm: String = opts.get("rotate", "90")
	var dens: bool = opts.get("density", true)
	var nt := maxi(int(opts.get("tiles", 1)), 1)
	if not m.has_attr(uv) or m.face_count() == 0:
		return {"ok": false, "why": "the mesh has no UVs (unwrap it first)"}
	var d: PackedVector2Array = m.attr_data(uv)
	var isl := island_data(m, uv)
	var n := isl.size()
	# each island: scale k, turn, local points, box
	var boxes: Array = []
	var total_k := 0.0
	for r in isl:
		var k := 1.0
		if dens and float(r["auv"]) > 1e-20 and float(r["a3"]) > 1e-20:
			k = sqrt(float(r["a3"]) / float(r["auv"]))
		r["k"] = k
	if not dens:   # keep relative sizes, but in metres-like units: one k for all (total UV area = total 3D area)
		var a3 := 0.0
		var au := 0.0
		for r in isl:
			a3 += float(r["a3"])
			au += float(r["auv"])
		total_k = sqrt(a3 / au) if au > 1e-20 and a3 > 1e-20 else 1.0
		for r in isl:
			r["k"] = total_k
	for r in isl:
		var pts := PackedVector2Array()
		for c in (r["corners"] as PackedInt32Array):
			pts.append(d[c] * float(r["k"]))
		var ang := min_box_angle(pts) if rotm == "free" else 0.0
		var cs := cos(-ang)
		var sn := sin(-ang)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for i in pts.size():
			var q := pts[i]
			var rq := Vector2(q.x * cs - q.y * sn, q.x * sn + q.y * cs)
			pts[i] = rq
			lo = lo.min(rq)
			hi = hi.max(rq)
		for i in pts.size():
			pts[i] -= lo
		r["pts"] = pts
		r["box"] = hi - lo
		boxes.append(hi - lo)
	# tiles
	var tile := PackedInt32Array()
	tile.resize(n)
	if nt > 1:
		tile = split_tiles(isl, nt, String(opts.get("split", "region")))
	var groups: Array = []
	for t in nt:
		groups.append([])
	for i in n:
		(groups[tile[i]] as Array).append(i)
	# bisection on s: every tile must fit
	var rot := rotm != "none"
	var hi_s := INF   # a box must fit the tile by its long side, and all boxes together by area
	for t in nt:
		var area := 0.0
		for i in groups[t]:
			var b: Vector2 = boxes[i]
			area += b.x * b.y
			if maxf(b.x, b.y) > 1e-20:
				hi_s = minf(hi_s, (1.0 - g) / maxf(b.x, b.y))
		if area > 1e-20:
			hi_s = minf(hi_s, sqrt(1.0 / area))
	if hi_s == INF:
		return {"ok": false, "why": "the islands have no area"}
	var best := _fit_all(groups, boxes, 0.0, g, rot)
	if best.is_empty():
		return {"ok": false, "why": "%d islands do not fit with a %s px margin at %d px" % [n, str(opts.get("margin", 4.0)), px]}
	var lo_s := 0.0
	var top := _fit_all(groups, boxes, hi_s, g, rot)
	if not top.is_empty():
		lo_s = hi_s
		best = top
	else:
		var hs := hi_s
		for it in ITERS:
			var mid := 0.5 * (lo_s + hs)
			var got := _fit_all(groups, boxes, mid, g, rot)
			if got.is_empty():
				hs = mid
			else:
				lo_s = mid
				best = got
	var s := lo_s
	# write
	var out := d.duplicate()
	for t in nt:
		var pl: Array = best[t]
		var grp: Array = groups[t]
		for j in grp.size():
			var r: Dictionary = isl[grp[j]]
			var pos: Vector2 = pl[j][0]
			var turn: bool = pl[j][1]
			var b: Vector2 = (r["box"] as Vector2) * s
			var cs2: PackedInt32Array = r["corners"]
			var pts: PackedVector2Array = r["pts"]
			for c in cs2.size():
				var q := pts[c] * s
				if turn:
					q = Vector2(b.y - q.y, q.x)
				out[cs2[c]] = q + pos + Vector2(g * 0.5, g * 0.5) + Vector2(t, 0)
	m.set_attr_data(uv, out)
	if nt > 1:
		if not m.has_attr(TILE):
			m.add_attr(TILE, KMesh.AD_FACE, TYPE_FLOAT, 0.0)
		var td := PackedFloat32Array()
		td.resize(m.face_count())
		for i in n:
			for f in (isl[i]["faces"] as PackedInt32Array):
				td[f] = tile[i]
		m.set_attr_data(TILE, td)
	elif m.has_attr(TILE):
		m.remove_attr(TILE)
	# report
	var used := PackedFloat64Array()
	used.resize(nt)
	var dmin := INF
	var dmax := 0.0
	for i in n:
		var r: Dictionary = isl[i]
		var au := float(r["auv"]) * pow(float(r["k"]) * s, 2.0)
		used[tile[i]] += au
		if float(r["a3"]) > 1e-12 and au > 1e-20:
			var dd := sqrt(au / float(r["a3"]))
			dmin = minf(dmin, dd)
			dmax = maxf(dmax, dd)
	var eff := 0.0
	for t in nt:
		eff += used[t]
	return {"ok": true, "islands": n, "tiles": nt, "scale": s, "px": px, "px_per_m": s * px, "px_per_cm": s * px / 100.0,
		"efficiency": eff / nt, "tile_eff": used, "spread": dmax / dmin - 1.0 if dmin < INF and dmin > 0.0 else 0.0,
		"margin_px": float(opts.get("margin", 4.0)), "rotate": rotm, "ms": (Time.get_ticks_usec() - t0) / 1000.0}


## every tile's group packed at scale s (boxes * s + g); [] when one tile fails. Tries the heuristics in turn.
static func _fit_all(groups: Array, boxes: Array, s: float, g: float, rot: bool) -> Array:
	var res: Array = []
	for grp in groups:
		var sizes: Array = []
		for i in grp:
			sizes.append((boxes[i] as Vector2) * s + Vector2(g, g))
		var got: Array = []
		for h in HEUR:
			got = maxrects(sizes, rot, h[0], h[1])
			if not got.is_empty():
				break
		if got.is_empty() and not grp.is_empty():
			return []
		res.append(got)
	return res


## islands -> tile ids. "region": sorted by height (3D centroid y, top first), cut into nt bands of equal 3D area (head and
## shoulders, torso, hips, legs on a standing body); "area": largest first, each into the tile with the least area so far
static func split_tiles(isl: Array, nt: int, how := "region") -> PackedInt32Array:
	var n := isl.size()
	var tile := PackedInt32Array()
	tile.resize(n)
	var tot := 0.0
	for r in isl:
		tot += float(r["a3"])
	var order := range(n)
	if how == "area":
		order.sort_custom(func(a, b): return float(isl[a]["a3"]) > float(isl[b]["a3"]))
		var load := PackedFloat64Array()
		load.resize(nt)
		for i in order:
			var t := 0
			for k in nt:
				if load[k] < load[t]:
					t = k
			tile[i] = t
			load[t] += float(isl[i]["a3"])
		return tile
	order.sort_custom(func(a, b): return (isl[a]["c3"] as Vector3).y > (isl[b]["c3"] as Vector3).y)
	var acc := 0.0
	for i in order:
		var a := float(isl[i]["a3"])
		var t := mini(int(floor((acc + a * 0.5) / tot * nt)) if tot > 0.0 else 0, nt - 1)
		tile[i] = t
		acc += a
	return tile


# ---------------------------------------------------------------- D15 game ready

## Seams for a mesh nobody cut: an edge is a seam where its faces meet at over `angle` degrees or where their normals'
## dominant axes differ (+x / -x / +y / -y / +z / -z, the six charts of a box projection), so every chart opens flat
## enough for LSCM and none is a closed surface. Returns how many edges were marked.
static func auto_seams(m: KMesh, angle := 60.0) -> int:
	KMeshUV._ensure_seam(m)
	var d: PackedFloat32Array = m.attr_data(KMeshUV.SEAM)
	var c := cos(deg_to_rad(angle))
	var fn := m.face_normals
	var cls := PackedInt32Array()
	cls.resize(m.face_count())
	for f in m.face_count():
		var nr := fn[f]
		var ax := 0
		for k in 3:
			if absf(nr[k]) > absf(nr[ax]):
				ax = k
		cls[f] = ax * 2 + (0 if nr[ax] >= 0.0 else 1)
	var n := 0
	var i := 0
	for e in m.edges():
		var h := m.find_half_edge(e.x, e.y)
		var t := m.find_half_edge(e.y, e.x)
		if h != -1 and t != -1:
			var a := m.he_face[h]
			var b := m.he_face[t]
			if fn[a].dot(fn[b]) < c or cls[a] != cls[b]:
				d[i] = 1.0
				n += 1
		i += 1
	m.set_attr_data(KMeshUV.SEAM, d)
	return n


static func _has_seams(m: KMesh) -> bool:
	if not m.has_attr(KMeshUV.SEAM):
		return false
	for v in m.attr_data(KMeshUV.SEAM):
		if float(v) > 0.5:
			return true
	return false


## One click: seams (the mesh's own when it has any, else auto_seams), LSCM unwrap (KMeshUV, D03), then pack with equal
## density for a named budget ("1x2k" / "4x1k", BUDGETS). opts as pack() ("margin" default 8 px, "rotate" default
## "free", "split" default "region"). Returns pack()'s dictionary plus "budget", "seams" ("yours" / "auto, N edges"),
## "unwrap_ms".
static func game_ready(m: KMesh, budget := "1x2k", opts := {}) -> Dictionary:
	var b: Dictionary = BUDGETS.get(budget, BUDGETS["1x2k"])
	var t0 := Time.get_ticks_usec()
	var seams := "yours"
	if not _has_seams(m):
		seams = "auto, %d edges" % auto_seams(m, 60.0)
	KMeshUV.unwrap_lscm(m)
	var um := (Time.get_ticks_usec() - t0) / 1000.0
	var o := {"px": b["px"], "tiles": b["tiles"], "margin": 8.0, "rotate": "free", "split": "region"}
	o.merge(opts, true)
	var r := pack(m, o)
	r["budget"] = budget
	r["budget_label"] = b["label"]
	r["seams"] = seams
	r["unwrap_ms"] = um
	return r


## the sentence the app says after a pack / game-ready run
static func words(r: Dictionary) -> String:
	if not r.get("ok", false):
		return "Model: UVs not packed: " + String(r.get("why", "?"))
	var head := "game ready UVs for %s (seams %s): " % [r["budget_label"], r["seams"]] if r.has("budget") else "packed UV islands: "
	return "Model: %s%d islands%s, texel density %.2f px/cm (%d px/m) at %d px, %.0f%% of the %s used, margin %s px, density spread %.1f%%. Ctrl+Z undoes" % [
		head, int(r["islands"]), " in %d tiles" % int(r["tiles"]) if int(r["tiles"]) > 1 else "", float(r["px_per_cm"]),
		roundi(float(r["px_per_m"])), int(r["px"]), float(r["efficiency"]) * 100.0, "tiles" if int(r["tiles"]) > 1 else "tile",
		str(r["margin_px"]), float(r["spread"]) * 100.0]


## the model preview's step (kmesh_edit_ui.gd): "pack" (Ctrl+P: 4 px margin at 1024, free rotation, equal density;
## unwraps first when there are no UVs), "2k" / "4k" (game ready). One mesh undo step; the
## surface switches to the UV checker so the result shows. Returns what was said.
static func run_ui(ui, what: String) -> String:
	var mesh: KMesh = ui.mesh
	ui.undo.begin(mesh)
	var r: Dictionary
	if what == "pack":
		if not mesh.has_attr(UV):
			KMeshUV.seams_by_angle(mesh, 60.0)
			KMeshUV.unwrap_lscm(mesh)
		r = pack(mesh, {"px": 1024, "margin": 4.0, "rotate": "free"})
	else:
		r = game_ready(mesh, "4x1k" if what == "4k" else "1x2k")
	ui.undo.commit("Pack UV islands" if what == "pack" else "Game ready UVs")
	ui.view.shading = "uv_checker"
	ui.view.mark_dirty()
	ui.view.rebuild()
	var said := words(r)
	ui.m._say(said)
	return said
