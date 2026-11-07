class_name FistCheck
extends RefCounted
## FIST TEST (N057, L104): the modeled hand (the mannequin's skin, weighted to the hand and finger bones) is posed to a closing sweep open -> fist
## (5 frames) and to every right-hand grip of the grip book (data/grips/book/*.json); for each pose: does each digit's tip reach its target, and does the
## skin cross itself. Definitions (tests/fistmat_test.gd header): tip = mean of the 8 digit vertices farthest from the wrist at rest; the target of a
## finger is the palm (triangles whose corners are all heaviest on the hand bone), the thumb's is the palm plus the other digits; closes = every tip within
## CLOSE_MM (15 mm: MINE, about one finger pad); self-intersection = pairs of hand triangles that cross (not sharing a vertex, not crossing at rest), depth =
## min(farthest vertex of A from B's plane, farthest of B from A's plane). Read only: the skeleton pose is put back, the body is not touched.

const CLOSE_MM := 15.0
const DIGITS := ["thumb", "index", "middle", "ring", "pinky"]
const FRAMES := 5
const CELL := 0.015   # m: the broad-phase grid of the self-intersection test


# ---------------------------------------------------------------- self-intersection (pure geometry)

## where the segment p-q pierces the triangle: its parameter t in [0, 1], or -1
static func _seg_tri(p: Vector3, q: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var d := q - p
	var e1 := b - a
	var e2 := c - a
	var h := d.cross(e2)
	var det := e1.dot(h)
	if absf(det) < 1e-14:
		return -1.0
	var f := 1.0 / det
	var s := p - a
	var u := f * s.dot(h)
	if u < 0.0 or u > 1.0:
		return -1.0
	var qv := s.cross(e1)
	var v := f * d.dot(qv)
	if v < 0.0 or u + v > 1.0:
		return -1.0
	var t := f * e2.dot(qv)
	return t if t >= 0.0 and t <= 1.0 else -1.0


## the chord of a crossing: the longest distance between the points where the edges of one triangle pierce the other; -1 when they do not cross
static func _tri_chord(a0: Vector3, a1: Vector3, a2: Vector3, b0: Vector3, b1: Vector3, b2: Vector3) -> float:
	var pts := []
	var ea := [[a0, a1], [a1, a2], [a2, a0]]
	var eb := [[b0, b1], [b1, b2], [b2, b0]]
	for e in ea:
		var t := _seg_tri(e[0], e[1], b0, b1, b2)
		if t >= 0.0:
			pts.append((e[0] as Vector3).lerp(e[1], t))
	for e in eb:
		var t := _seg_tri(e[0], e[1], a0, a1, a2)
		if t >= 0.0:
			pts.append((e[0] as Vector3).lerp(e[1], t))
	if pts.is_empty():
		return -1.0
	var m := 0.0
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			m = maxf(m, (pts[i] as Vector3).distance_to(pts[j]))
	return m


## every crossing pair of triangles. faces: Array of PackedInt32Array triangles. skip: Dictionary of pair keys (a * n + b, a < b) not to count (the rest baseline).
## -> {"count", "tris", "depth_mm", "pairs" (first 8, [fa, fb]), "keys" (Dictionary of every pair key)}
static func self_intersections(verts: PackedVector3Array, faces: Array, skip := {}) -> Dictionary:
	var n := faces.size()
	var lo := PackedVector3Array()
	var hi := PackedVector3Array()
	var grid := {}
	for i in n:
		var t: PackedInt32Array = faces[i]
		var a := verts[t[0]]
		var mn := a.min(verts[t[1]]).min(verts[t[2]])
		var mx := a.max(verts[t[1]]).max(verts[t[2]])
		lo.append(mn)
		hi.append(mx)
		var x0 := int(floor(mn.x / CELL))
		var x1 := int(floor(mx.x / CELL))
		var y0 := int(floor(mn.y / CELL))
		var y1 := int(floor(mx.y / CELL))
		var z0 := int(floor(mn.z / CELL))
		var z1 := int(floor(mx.z / CELL))
		for x in range(x0, x1 + 1):
			for y in range(y0, y1 + 1):
				for z in range(z0, z1 + 1):
					var key := Vector3i(x, y, z)
					if grid.has(key):
						var cl: PackedInt32Array = grid[key]
						cl.append(i)
						grid[key] = cl
					else:
						grid[key] = PackedInt32Array([i])
	var seen := {}
	var keys := {}
	var pairs := []
	var inv := {}
	var depth := 0.0
	for key in grid:
		var cell: PackedInt32Array = grid[key]
		for ii in cell.size():
			for jj in range(ii + 1, cell.size()):
				var a := mini(cell[ii], cell[jj])
				var b := maxi(cell[ii], cell[jj])
				var pk := a * n + b
				if seen.has(pk):
					continue
				seen[pk] = true
				if skip.has(pk):
					continue
				var ta: PackedInt32Array = faces[a]
				var tb: PackedInt32Array = faces[b]
				if ta[0] == tb[0] or ta[0] == tb[1] or ta[0] == tb[2] or ta[1] == tb[0] or ta[1] == tb[1] or ta[1] == tb[2] \
						or ta[2] == tb[0] or ta[2] == tb[1] or ta[2] == tb[2]:
					continue
				if lo[a].x > hi[b].x or lo[b].x > hi[a].x or lo[a].y > hi[b].y or lo[b].y > hi[a].y or lo[a].z > hi[b].z or lo[b].z > hi[a].z:
					continue
				var chord := _tri_chord(verts[ta[0]], verts[ta[1]], verts[ta[2]], verts[tb[0]], verts[tb[1]], verts[tb[2]])
				if chord < 0.0:
					continue
				keys[pk] = true
				inv[a] = true
				inv[b] = true
				if pairs.size() < 8:
					pairs.append([a, b])
				depth = maxf(depth, chord)
	return {"count": keys.size(), "tris": inv.size(), "depth_mm": depth * 1000.0, "pairs": pairs, "keys": keys}


# ---------------------------------------------------------------- the hand

static func _closest(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var w := KMeshAnatomy._closest_bary(p, a, b, c)
	return p.distance_to(a * w.x + b * w.y + c * w.z)


## the hand's skin out of the live body. {} without a fighter skin
static func make(m: Node, side := "r") -> Dictionary:
	if m == null or m.get("skel") == null or m.get("pieces") == null or m.pieces.is_empty():
		return {}
	var skin := BaseBody.skin_of(m)
	if skin == null:
		return {}
	var rest := BaseBody.read(m)
	var ws: Array = BaseBody.weights_of(rest, skin)
	var sk: Skeleton3D = m.skel
	var sd := "_" + side
	var bname := PackedStringArray()
	for k in skin.get_bind_count():
		bname.append(sk.get_bone_name(SkinPaint.bind_bone(skin, sk, k)))
	# the heaviest bone of every vertex -> digit ("hand" for the hand bone, "" elsewhere)
	var dig := {}   # vertex -> digit
	for v in rest.verts.size():
		var d: Dictionary = ws[v]
		var bb := -1
		var bw := 0.0
		for b in d:
			if float(d[b]) > bw:
				bw = float(d[b])
				bb = int(b)
		if bb < 0:
			continue
		var nm := bname[bb]
		if nm == "hand" + sd:
			dig[v] = "hand"
		else:
			for f in DIGITS:
				if nm.begins_with(f + "_0") and nm.ends_with(sd):
					dig[v] = f
	# the wrist at rest: the origin of the hand bone (bind pose inverse)
	var wrist := Vector3.ZERO
	for k in skin.get_bind_count():
		if bname[k] == "hand" + sd:
			wrist = skin.get_bind_pose(k).affine_inverse().origin
	var hv := PackedInt32Array()
	for v in dig:
		hv.append(v)
	hv.sort()
	var local := {}
	for i in hv.size():
		local[hv[i]] = i
	var tris := []
	var palm := []
	var other := {}   # digit -> triangles (local indices) of the digit
	for f in rest.faces:
		var ok := true
		for v in f:
			if not local.has(v):
				ok = false
		if not ok:
			continue
		var t := PackedInt32Array([local[f[0]], local[f[1]], local[f[2]]])
		tris.append(t)
		var d0: String = dig[f[0]]
		if d0 == "hand" and dig[f[1]] == "hand" and dig[f[2]] == "hand":
			palm.append(t)
		for dd in [dig[f[0]], dig[f[1]], dig[f[2]]]:
			if dd != "hand":
				if not other.has(dd):
					other[dd] = []
				if not (other[dd] as Array).has(t):
					(other[dd] as Array).append(t)
	var rv := PackedVector3Array()
	var wl := []
	for v in hv:
		rv.append(rest.verts[v])
		wl.append(ws[v])
	# rest-pose tips: the 8 digit vertices farthest from the wrist
	var tipv := {}
	for f in DIGITS:
		var cand := []
		for i in hv.size():
			if dig[hv[i]] == f:
				cand.append([rv[i].distance_to(wrist), i])
		cand.sort_custom(func(a, b): return a[0] > b[0])
		var lst := PackedInt32Array()
		for q in mini(8, cand.size()):
			lst.append(cand[q][1])
		tipv[f] = lst
	return {"m": m, "skin": skin, "side": side, "rest": rv, "w": wl, "tris": tris, "palm": palm, "other": other, "digit": dig, "tipv": tipv,
		"hand_verts": hv.size(), "hand_tris": tris.size(), "hv": hv}


static func _pose_verts(ctx: Dictionary, G: Body) -> PackedVector3Array:
	var m: Node = ctx["m"]
	Overlays.pose_skeleton(m.skel, m.bone_idx, G)
	var mats := DqSkin.bind_mats(m.skel, ctx["skin"])
	var rv: PackedVector3Array = ctx["rest"]
	var wl: Array = ctx["w"]
	var out := PackedVector3Array()
	out.resize(rv.size())
	for i in rv.size():
		var acc := Vector3.ZERO
		var tw := 0.0
		for b in (wl[i] as Dictionary):
			var wb: float = wl[i][b]
			acc += ((mats[b] as Transform3D) * rv[i]) * wb
			tw += wb
		out[i] = acc / tw if tw > 0.0 else rv[i]
	return out


## the tips of the five digits against their targets, mm
static func _tips(ctx: Dictionary, pv: PackedVector3Array) -> Dictionary:
	var out := {}
	for f in DIGITS:
		var lst: PackedInt32Array = ctx["tipv"][f]
		if lst.is_empty():
			continue
		var p := Vector3.ZERO
		for i in lst:
			p += pv[i]
		p /= lst.size()
		var tgt: Array = (ctx["palm"] as Array).duplicate()
		if f == "thumb":
			for o in DIGITS:
				if o != "thumb":
					tgt.append_array(ctx["other"].get(o, []))
		var best := INF
		for t in tgt:
			best = minf(best, _closest(p, pv[t[0]], pv[t[1]], pv[t[2]]))
		out[f] = best * 1000.0
	return out


static func _angles(ctx: Dictionary, kind: String, curl: float, g: Dictionary, limits: Dictionary) -> Body:
	var m: Node = ctx["m"]
	var G := Body.new()
	G.load_files("res://data/skeleton.json", "res://data/body_limits.json")
	G.set_proportions(m.B.body)
	for j in G.ang:
		G.ang[j] = Vector3.ZERO
	var sd: String = ctx["side"]
	if kind == "sweep":
		var op := Body.new()
		op.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		op.set_proportions(m.B.body)
		for j in op.ang:
			op.ang[j] = Vector3.ZERO
		var fi := Body.new()
		fi.load_files("res://data/skeleton.json", "res://data/body_limits.json")
		fi.set_proportions(m.B.body)
		for j in fi.ang:
			fi.ang[j] = Vector3.ZERO
		fi.hand_shape(sd, "fist")
		for f in DIGITS:
			for k in 3:
				var j := "%s_0%d_%s" % [f, k + 1, sd]
				G.ang[j] = (fi.ang[j] as Vector3) * curl
	else:
		for j in (g.get("fingers", {}) as Dictionary):
			var a: Array = g["fingers"][j]
			G.ang[String(j)] = Vector3(float(a[0]), float(a[1]), float(a[2]))
	for f in limits:
		for k in 3:
			var j := "%s_0%d_%s" % [f, k + 1, sd]
			if G.ang.has(j):
				var a: Vector3 = G.ang[j]
				a.x = minf(a.x, float(limits[f]))
				G.ang[j] = a
	G.fk()
	return G


## poses: "fist" (the sweep only) | "all" (sweep + every right-hand grip). limits: {finger: max flexion deg}
## -> {"closes", "fist" {tips_mm, inter, closes}, "poses" [{name, kind, frame, tips_mm, closes, inter}], "fails" [{finger, pose, frame, tip_mm}]}
static func run(ctx: Dictionary, opts := {}) -> Dictionary:
	if ctx.is_empty():
		return {"closes": false, "error": "no hand skin", "poses": [], "fails": []}
	var m: Node = ctx["m"]
	var limits: Dictionary = opts.get("limits", {})
	var faces: Array = ctx["tris"]
	# the baseline: the pairs that already cross at rest
	var G0 := _angles(ctx, "sweep", 0.0, {}, {})
	var base := self_intersections(_pose_verts(ctx, G0), faces)
	var skip: Dictionary = base["keys"]
	var poses := []
	var fails := []
	var fist := {}
	for fr in FRAMES:
		var curl := float(fr) / float(FRAMES - 1)
		var G := _angles(ctx, "sweep", curl, {}, limits)
		var pv := _pose_verts(ctx, G)
		var e := _entry("fist", "sweep", fr, pv, ctx, skip)
		poses.append(e)
		if fr == FRAMES - 1:
			fist = e
			for f in e["tips_mm"]:
				if float(e["tips_mm"][f]) > CLOSE_MM:
					fails.append({"finger": f, "pose": "fist", "frame": fr, "tip_mm": e["tips_mm"][f]})
	if String(opts.get("poses", "fist")) == "all":
		var d := DirAccess.open("res://data/grips/book")
		for fn in d.get_files():
			if not fn.ends_with(".json"):
				continue
			var gj: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/grips/book/" + fn))
			for g in (gj as Dictionary).get("grips", []):
				for h in g.get("hands", []):
					if String(h.get("side", "_r")) != "_" + String(ctx["side"]):
						continue
					var G := _angles(ctx, "grip", 1.0, h, limits)
					var e := _entry("%s/%s" % [fn.get_basename(), g.get("name", "?")], "grip", poses.size(), _pose_verts(ctx, G), ctx, skip)
					poses.append(e)
	# put the live pose back
	Overlays.pose_skeleton(m.skel, m.bone_idx, m.B)
	return {"closes": fails.is_empty(), "fist": fist, "poses": poses, "fails": fails}


static func _entry(name: String, kind: String, frame: int, pv: PackedVector3Array, ctx: Dictionary, skip: Dictionary) -> Dictionary:
	var tips := _tips(ctx, pv)
	var worst := 0.0
	for f in tips:
		worst = maxf(worst, float(tips[f]))
	var inter := self_intersections(pv, ctx["tris"], skip)
	inter.erase("keys")
	return {"name": name, "kind": kind, "frame": frame, "tips_mm": tips, "worst_mm": worst, "closes": worst <= CLOSE_MM, "inter": inter}


static func serve(m: Node, p: Dictionary) -> Dictionary:
	var ctx := make(m, String(p.get("side", "r")))
	if ctx.is_empty():
		return {"ok": false, "error": "no fighter skin"}
	var lim: Dictionary = p.get("limits", {})
	var r := run(ctx, {"poses": String(p.get("poses", "all")), "limits": lim})
	var worst_inter := {}
	for e in r["poses"]:
		if int(e["inter"]["count"]) > int(worst_inter.get("inter", {}).get("count", 0)):
			worst_inter = {"pose": e["name"], "frame": e["frame"], "inter": e["inter"]}
	return {"ok": true, "result": {"closes": r["closes"], "fails": r["fails"], "fist_tips_mm": r["fist"].get("tips_mm", {}), "fist_self_intersection": r["fist"].get("inter", {}),
		"worst_self_intersection": worst_inter, "poses": r["poses"].size(),
		"summary": "fist %s%s" % ["closes" if r["closes"] else "does NOT close", "" if r["closes"] else (": " + ", ".join(PackedStringArray(r["fails"].map(func(f): return "%s %.0f mm (%s, frame %d)" % [f["finger"], f["tip_mm"], f["pose"], f["frame"]]))))]}}
