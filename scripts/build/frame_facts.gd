## s243 FRAMING FACTS FROM THE SILHOUETTE (AI EASE 3). A bounding box projected to the picture is not what the picture shows: lifted roof corners stick out of
## the box's hull, so the AI framed the temple at "74 %" of the width when the picture showed 83 % (and once at 310 %). This file measures the SILHOUETTE.
##
## HOW: the REAL TRIANGLE CORNERS of every piece are taken into the camera's frame and projected (pinhole, vertical fov as Godot's default KEEP_HEIGHT camera;
## the live camera's own keep_aspect is honoured). A triangle projects to a triangle, so the picture bounding box of the pieces' silhouette is EXACTLY the
## min/max of the projected corners: no render pass, no sampling, no mask. (bbox_px is that silhouette box; aabb_bbox_px / bbox_share_* is what projecting the
## piece's 3D box corners would have said, the number the AI used, printed beside it so the gap is visible.)
## Pieces are the part's bodies by NAME (res.body_names; a body merged into another body's surface on a 256+ body part is found by res.surf_ranges).
## LIMIT: a corner behind the near plane is dropped and counted (behind_camera); a piece that crosses the near plane is flagged "crosses_near", its box is of the corners in front.
##
## Calls (scripts/agent_tools.gd, "frame_facts" and "frame_to"):
##   frame_facts {pieces?: ["col*", "Roof"], camera?: {pos, target, fov}, w?, h?}  ->  {ok, w, h, camera, scene: facts, selection?: facts, pieces: {name: facts}, ms}
##   frame_to    {pieces?, width_share | width_pct | height_share | rows: {top, bottom}, keep?: "fov"|"height"|"distance", center?: "x"|"xy"|"none", apply?: bool, camera?, w?, h?}
## The camera is the live one unless a camera {pos, target, fov} is given; w and h default to the main viewport. Nothing moves the user's camera unless apply is true.
class_name FrameFacts
extends RefCounted

const MAX_PIECES := 400


static func _v3(a: Variant) -> Vector3:
	if a is Vector3:
		return a
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3(NAN, NAN, NAN)


static func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.0001), snappedf(v.y, 0.0001), snappedf(v.z, 0.0001)]


## ---------------------------------------------------------------- the pieces
## {names: [String], verts: [PackedVector3Array in WORLD], aabb: [AABB world]} for the part on screen (or, with no part, the visible meshes under m)
static func gather(m: Node) -> Dictionary:
	var pu: Object = null
	if m.get("bld") != null:
		pu = (m.get("bld") as Object).get("part")
	if pu != null and pu.get("part_mesh") != null and (pu.get("part_mesh") as MeshInstance3D).mesh != null and bool((pu.get("part_mesh") as MeshInstance3D).is_inside_tree()):
		return gather_part(pu.get("part_mesh"), pu.get("res"))
	var nodes: Array = []
	_walk(m, nodes)
	return gather_nodes(nodes)


static func _walk(n: Node, out: Array) -> void:
	if out.size() > 1000:
		return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).is_visible_in_tree():
		out.append(n)
	for c in n.get_children():
		_walk(c, out)


## each MeshInstance3D is one piece, named by the node
static func gather_nodes(nodes: Array) -> Dictionary:
	var names: Array = []
	var verts: Array = []
	for n in nodes:
		var mi := n as MeshInstance3D
		var all := PackedVector3Array()
		for s in mi.mesh.get_surface_count():
			all.append_array(mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX])
		names.append(String(mi.name))
		verts.append(mi.global_transform * all)
	return _finish(names, verts)


## the part's bodies: one piece per body, named by res.body_names (or Body<k>)
static func gather_part(pm: MeshInstance3D, res: Dictionary) -> Dictionary:
	var mesh := pm.mesh
	var xf := pm.global_transform
	var bn: Array = res.get("body_names", [])
	var sb: Array = res.get("surf_body", [])
	var rngs: Array = res.get("surf_ranges", [])
	var by_body := {}   # body index -> PackedVector3Array (local)
	var order: Array = []
	var ranged: bool = rngs.size() == mesh.get_surface_count()
	for s in mesh.get_surface_count():
		var vs: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		if ranged:
			for r in rngs[s]:
				var b := int(r[0])
				if not by_body.has(b):
					by_body[b] = PackedVector3Array()
					order.append(b)
				var acc: PackedVector3Array = by_body[b]
				acc.append_array(vs.slice(int(r[1]), int(r[1]) + int(r[2])))
				by_body[b] = acc
		else:
			var b2: int = int(sb[s]) if s < sb.size() else 1000000 + s
			if not by_body.has(b2):
				by_body[b2] = PackedVector3Array()
				order.append(b2)
			var acc2: PackedVector3Array = by_body[b2]
			acc2.append_array(vs)
			by_body[b2] = acc2
	order.sort()
	var names: Array = []
	var verts: Array = []
	var seen := {}
	for b in order:
		var nm := String(bn[b]) if b < bn.size() and String(bn[b]) != "" else "Body%d" % (int(b) + 1)
		if seen.has(nm):
			seen[nm] += 1
			nm = "%s#%d" % [nm, seen[nm]]
		else:
			seen[nm] = 1
		names.append(nm)
		verts.append(xf * (by_body[b] as PackedVector3Array))
	return _finish(names, verts)


static func _finish(names: Array, verts: Array) -> Dictionary:
	var boxes: Array = []
	for vs in verts:
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for v in (vs as PackedVector3Array):
			lo = lo.min(v)
			hi = hi.max(v)
		boxes.append(AABB(lo, hi - lo) if (vs as PackedVector3Array).size() > 0 else AABB())
	return {"names": names, "verts": verts, "aabb": boxes}


## the indexes of the pieces a request names: exact names, or "col*" / "*roof*" patterns (case-insensitive); empty request -> []
static func select(g: Dictionary, pieces: Array) -> Array:
	var out: Array = []
	var names: Array = g["names"]
	for i in names.size():
		for pat in pieces:
			var ps := String(pat)
			if String(names[i]).matchn(ps) or String(names[i]).to_lower() == ps.to_lower():
				out.append(i)
				break
	return out


## ---------------------------------------------------------------- the camera
## {xf, fov, keep_width, w, h, near} from the request, else the live camera
static func camera_of(m: Node, p: Dictionary) -> Dictionary:
	var vs := Vector2(1280, 720)
	var vp: Viewport = m.get_viewport()
	if vp != null:
		vs = vp.get_visible_rect().size
	var W := int(p.get("w", vs.x))
	var H := int(p.get("h", vs.y))
	if W < 16 or H < 16 or W > 16384 or H > 16384:
		return {"ok": false, "error": "w and h must be 16..16384 pixels"}
	var cs: Variant = p.get("camera", null)
	var c3: Camera3D = m.get("cam")
	if cs is Dictionary and (cs as Dictionary).has("pos") and (cs as Dictionary).has("target"):
		var pos := _v3(cs["pos"])
		var tg := _v3(cs["target"])
		if not pos.is_finite() or not tg.is_finite() or pos.is_equal_approx(tg):
			return {"ok": false, "error": "camera needs {\"pos\": [x, y, z], \"target\": [x, y, z], \"fov\": 45} in metres, pos != target"}
		return {"ok": true, "xf": look(pos, tg), "fov": float((cs as Dictionary).get("fov", c3.fov if c3 != null else 45.0)), "keep_width": false, "w": W, "h": H, "near": 0.05}
	if c3 == null:
		return {"ok": false, "error": "no camera"}
	return {"ok": true, "xf": c3.global_transform, "fov": c3.fov, "keep_width": c3.keep_aspect == Camera3D.KEEP_WIDTH, "w": W, "h": H, "near": c3.near}


static func look(pos: Vector3, tg: Vector3) -> Transform3D:
	var d := (tg - pos).normalized()
	var up := Vector3.UP if absf(d.dot(Vector3.UP)) < 0.999 else Vector3.FORWARD
	return Transform3D(Basis.looking_at(d, up), pos)


static func focal(cam: Dictionary) -> float:
	var half := tan(deg_to_rad(float(cam["fov"])) * 0.5)
	return (float(cam["w"] if cam["keep_width"] else cam["h"]) * 0.5) / maxf(half, 1e-6)


## ---------------------------------------------------------------- projecting
## {x0, y0, x1, y1, n, behind} of the projected corners (picture pixels, y down); n = corners in front of the near plane
static func project(vs: PackedVector3Array, inv: Transform3D, f: float, cx: float, cy: float, near: float) -> Dictionary:
	var x0 := INF
	var y0 := INF
	var x1 := -INF
	var y1 := -INF
	var n := 0
	var cv := inv * vs
	for v in cv:
		var z := -v.z
		if z <= near:
			continue
		var k := f / z
		var px := cx + v.x * k
		var py := cy - v.y * k
		n += 1
		if px < x0: x0 = px
		if px > x1: x1 = px
		if py < y0: y0 = py
		if py > y1: y1 = py
	return {"x0": x0, "y0": y0, "x1": x1, "y1": y1, "n": n, "behind": cv.size() - n}


static func _box_corners(b: AABB) -> PackedVector3Array:
	var o := PackedVector3Array()
	for i in 8:
		o.append(b.position + Vector3(b.size.x * (i & 1), b.size.y * ((i >> 1) & 1), b.size.z * ((i >> 2) & 1)))
	return o


## the facts of one projected box r (from project()) in a W x H picture; aabb_r = the same for the 3D box's corners
static func facts_of(r: Dictionary, aabb_r: Dictionary, W: int, H: int) -> Dictionary:
	if int(r["n"]) == 0:
		return {"visible": false, "behind_camera": int(r["behind"]), "text": "nothing of it is in front of the camera"}
	var x0: float = r["x0"]
	var y0: float = r["y0"]
	var x1: float = r["x1"]
	var y1: float = r["y1"]
	var w := x1 - x0
	var h := y1 - y0
	var vx0 := clampf(x0, 0.0, W)
	var vx1 := clampf(x1, 0.0, W)
	var vy0 := clampf(y0, 0.0, H)
	var vy1 := clampf(y1, 0.0, H)
	var vw := maxf(vx1 - vx0, 0.0)
	var vh := maxf(vy1 - vy0, 0.0)
	var area := maxf(w * h, 1e-9)
	var cut_share := 1.0 - (vw * vh) / area if w > 0.0 and h > 0.0 else (1.0 - (vw / maxf(w, 1e-9)) if h <= 0.0 and w > 0.0 else 0.0)
	var d := {
		"visible": vw > 0.0 and vh > 0.0 or (vw > 0.0 and h <= 0.0),
		"bbox_px": [snappedf(x0, 0.01), snappedf(y0, 0.01), snappedf(x1, 0.01), snappedf(y1, 0.01)],
		"share_w": snappedf(w / W, 0.0001), "share_h": snappedf(h / H, 0.0001),
		"visible_px": [snappedf(vx0, 0.01), snappedf(vy0, 0.01), snappedf(vx1, 0.01), snappedf(vy1, 0.01)],
		"visible_share_w": snappedf(vw / W, 0.0001), "visible_share_h": snappedf(vh / H, 0.0001),
		"cut": {"share": snappedf(maxf(cut_share, 0.0), 0.0001), "left_px": snappedf(maxf(-x0, 0.0), 0.01), "right_px": snappedf(maxf(x1 - W, 0.0), 0.01),
			"top_px": snappedf(maxf(-y0, 0.0), 0.01), "bottom_px": snappedf(maxf(y1 - H, 0.0), 0.01)},
		"centre_offset_px": [snappedf((x0 + x1) * 0.5 - W * 0.5, 0.01), snappedf((y0 + y1) * 0.5 - H * 0.5, 0.01)],
		"centre_offset_share": [snappedf(((x0 + x1) * 0.5 - W * 0.5) / W, 0.0001), snappedf(((y0 + y1) * 0.5 - H * 0.5) / H, 0.0001)],
		"top_row": int(round(y0)), "bottom_row": int(round(y1)), "left_col": int(round(x0)), "right_col": int(round(x1)),
		"crosses_near": int(r["behind"]) > 0, "behind_camera": int(r["behind"]),
	}
	if int(aabb_r.get("n", 0)) > 0:
		d["aabb_bbox_px"] = [snappedf(aabb_r["x0"], 0.01), snappedf(aabb_r["y0"], 0.01), snappedf(aabb_r["x1"], 0.01), snappedf(aabb_r["y1"], 0.01)]
		d["bbox_share_w"] = snappedf((float(aabb_r["x1"]) - float(aabb_r["x0"])) / W, 0.0001)
		d["bbox_share_h"] = snappedf((float(aabb_r["y1"]) - float(aabb_r["y0"])) / H, 0.0001)
	return d


## union of project() results
static func _union(rs: Array) -> Dictionary:
	var u := {"x0": INF, "y0": INF, "x1": -INF, "y1": -INF, "n": 0, "behind": 0}
	for r in rs:
		u["n"] += int(r["n"])
		u["behind"] += int(r["behind"])
		if int(r["n"]) == 0:
			continue
		u["x0"] = minf(u["x0"], r["x0"])
		u["y0"] = minf(u["y0"], r["y0"])
		u["x1"] = maxf(u["x1"], r["x1"])
		u["y1"] = maxf(u["y1"], r["y1"])
	return u


## the silhouette box of the pieces `idx` (all when empty) as project() numbers, with the 3D-box number beside it; g from gather()
static func measure(g: Dictionary, idx: Array, cam: Dictionary) -> Dictionary:
	var inv: Transform3D = (cam["xf"] as Transform3D).affine_inverse()
	var f := focal(cam)
	var cx: float = cam["w"] * 0.5
	var cy: float = cam["h"] * 0.5
	var near: float = cam["near"]
	var rs: Array = []
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var list: Array = idx if not idx.is_empty() else range((g["names"] as Array).size())
	for i in list:
		var vs: PackedVector3Array = g["verts"][i]
		if vs.is_empty():
			continue
		rs.append(project(vs, inv, f, cx, cy, near))
		var b: AABB = g["aabb"][i]
		lo = lo.min(b.position)
		hi = hi.max(b.end)
	var u := _union(rs)
	var ar := project(_box_corners(AABB(lo, hi - lo)), inv, f, cx, cy, near) if lo.is_finite() else {"n": 0}
	return {"sil": u, "box": ar}


static func scene_facts(g: Dictionary, idx: Array, cam: Dictionary) -> Dictionary:
	var ms := measure(g, idx, cam)
	return facts_of(ms["sil"], ms["box"], cam["w"], cam["h"])


## ---------------------------------------------------------------- the calls
static func serve(m: Node, p: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var cam := camera_of(m, p)
	if not bool(cam["ok"]):
		return cam
	var g := gather(m)
	if (g["names"] as Array).is_empty():
		return {"ok": false, "error": "nothing to frame: no part is on screen"}
	var out := {"ok": true, "w": cam["w"], "h": cam["h"], "method": "projected real triangle corners (silhouette bbox is exact); aabb_bbox_px is the 3D box's corners for comparison"}
	out["camera"] = camera_dict(cam)
	out["scene"] = scene_facts(g, [], cam)
	out["pieces"] = {}
	var req: Array = p.get("pieces", []) if p.get("pieces") is Array else ([p["pieces"]] if p.has("pieces") else [])
	if not req.is_empty():
		var idx := select(g, req)
		if idx.is_empty():
			return {"ok": false, "error": "no piece matches %s (names look like %s)" % [JSON.stringify(req), JSON.stringify((g["names"] as Array).slice(0, 8))]}
		for i in idx.slice(0, MAX_PIECES):
			out["pieces"][g["names"][i]] = scene_facts(g, [i], cam)
		out["selection"] = scene_facts(g, idx, cam)
		out["selection"]["pieces"] = idx.size()
	out["ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	return out


static func camera_dict(cam: Dictionary) -> Dictionary:
	var xf: Transform3D = cam["xf"]
	var fwd := -xf.basis.z
	return {"pos": _arr(xf.origin), "target": _arr(xf.origin + fwd * 10.0), "fov": snappedf(float(cam["fov"]), 0.0001)}


## the camera that puts the silhouette of the pieces at the asked share. cam in, cam out ({xf, fov, ...}); keep "fov" dollies along the aim line,
## "height" keeps the camera's height and the target's (moves horizontally), "distance" keeps the position and changes the fov.
## Centring is by a lateral offset (ox, oy) in PIXELS of the pieces' 3D middle, applied as metres = px * depth / f at every evaluation, so it does not
## change when the dolly distance does (a shift in metres overshoots as the camera comes closer); the outer loop moves (ox, oy) by the silhouette's residual.
static func solve(g: Dictionary, idx: Array, cam0: Dictionary, axis: String, want: float, keep: String, centre: String, rows: Dictionary) -> Dictionary:
	var xf0: Transform3D = cam0["xf"]
	var pos := xf0.origin
	var cc := _mid_point(g, idx)
	var tgt: Vector3 = pos + (-xf0.basis.z) * maxf(-(xf0.affine_inverse() * cc).z, 1e-3)   # the live camera has no target: the point of its view axis level with the pieces' middle
	if cam0.has("target"):
		tgt = cam0["target"]
	var dist := pos.distance_to(tgt)
	var fov: float = cam0["fov"]
	var dir := (tgt - pos).normalized()
	var h_dir := Vector3(dir.x, 0.0, dir.z).normalized() if Vector2(dir.x, dir.z).length() > 1e-6 else Vector3.FORWARD
	var x := dist
	if keep == "height":
		x = maxf(Vector2(tgt.x - pos.x, tgt.z - pos.z).length(), 1e-3)
	elif keep == "distance":
		x = tan(deg_to_rad(fov) * 0.5)
	var ox := 0.0
	var oy := 0.0
	var info := {}
	var iters := 0
	var use_x := centre == "x" or centre == "xy"
	var use_y := centre == "xy" or not rows.is_empty()
	var x_start := x
	var ox_prev := 0.0
	var oy_prev := 0.0
	var dx_prev := 0.0
	var dy_prev := 0.0
	for round_ in 14:
		# the share is not monotone in the distance near the pieces (a camera inside or beside the roof), so: go FAR first, step in until the share
		# reaches the asked one (the first crossing from far away), then Illinois on that bracket
		var ev := func(xx: float) -> Dictionary:
			var c2 := _cam_at(cam0, pos, tgt, fov, keep, xx, h_dir, cc, ox, oy, use_x, use_y)
			var sil: Dictionary = measure(g, idx, c2)["sil"]
			var sh := 0.0
			if int(sil["n"]) > 0:
				sh = (float(sil["x1"]) - float(sil["x0"])) / float(c2["w"]) if axis == "w" else (float(sil["y1"]) - float(sil["y0"])) / float(c2["h"])
			return {"cam": c2, "sil": sil, "share": sh}
		var xh := x_start * 2.0
		var eh: Dictionary = ev.call(xh)
		iters += 1
		var guard := 0
		while float(eh["share"]) > want and guard < 40:
			xh *= 2.0
			eh = ev.call(xh)
			iters += 1
			guard += 1
		var xl := xh
		var el := eh
		guard = 0
		while float(el["share"]) < want and guard < 400:
			xh = xl
			eh = el
			xl = xl / 1.08
			el = ev.call(xl)
			iters += 1
			guard += 1
		if float(el["share"]) < want:
			return {"ok": false, "error": "no camera distance gives that share (largest tried %.3f, asked %.3f)" % [float(el["share"]), want]}
		if int(el["sil"]["n"]) == 0:
			return {"ok": false, "error": "the pieces are not in front of the camera"}
		# Illinois on log(share/want): el >= 0 (nearer, bigger), eh < 0 (farther)
		var fl_ := log(float(el["share"]) / want)
		var fh_ := log(maxf(float(eh["share"]), 1e-9) / want)
		var side := 0
		info = el
		for it in 40:
			if absf(fl_) < 2e-6:
				info = el
				break
			if absf(fh_) < 2e-6:
				info = eh
				break
			var xm := exp((log(xl) * fh_ - log(xh) * fl_) / (fh_ - fl_))
			var em: Dictionary = ev.call(xm)
			iters += 1
			var fm := log(maxf(float(em["share"]), 1e-9) / want)
			info = em
			if absf(fm) < 2e-6:
				break
			if fm > 0.0:
				xl = xm
				el = em
				fl_ = fm
				if side == 1:
					fh_ *= 0.5
				side = 1
			else:
				xh = xm
				eh = em
				fh_ = fm
				if side == -1:
					fl_ *= 0.5
				side = -1
		x_start = float(xh) * 0.5
		var sil2: Dictionary = info["sil"]
		var c3: Dictionary = info["cam"]
		var dx := 0.0
		var dy := 0.0
		if centre == "x" or centre == "xy":
			dx = (float(sil2["x0"]) + float(sil2["x1"])) * 0.5 - float(c3["w"]) * 0.5
		if not rows.is_empty():
			dy = float(sil2["y0"]) - float(rows["top"])
		elif centre == "xy":
			dy = (float(sil2["y0"]) + float(sil2["y1"])) * 0.5 - float(c3["h"]) * 0.5
		if keep == "height":
			dy = 0.0
		if absf(dx) < 0.05 and absf(dy) < 0.05:
			break
		if round_ == 13:
			break
		# a secant step per axis (the silhouette moves by more than the pixel shift when the camera is close: the plain step of one pixel per pixel overshoots)
		var gx := -1.0
		var gy := -1.0
		if round_ > 0:
			if absf(ox - ox_prev) > 1e-6 and (dx - dx_prev) / (ox - ox_prev) < -0.2:
				gx = (dx - dx_prev) / (ox - ox_prev)
			if absf(oy - oy_prev) > 1e-6 and (dy - dy_prev) / (oy - oy_prev) < -0.2:
				gy = (dy - dy_prev) / (oy - oy_prev)
		ox_prev = ox
		oy_prev = oy
		dx_prev = dx
		dy_prev = dy
		ox -= dx / gx * (0.8 if round_ == 0 else 1.0)
		oy -= dy / gy * (0.8 if round_ == 0 else 1.0)
	var cf: Dictionary = info["cam"]
	return {"ok": true, "cam": cf, "share": info["share"], "iterations": iters, "pos": (cf["xf"] as Transform3D).origin, "target": cf["target"], "fov": cf["fov"]}


## the middle of the pieces' 3D box
static func _mid_point(g: Dictionary, idx: Array) -> Vector3:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in (idx if not idx.is_empty() else range((g["names"] as Array).size())):
		var b: AABB = g["aabb"][i]
		if (g["verts"][i] as PackedVector3Array).is_empty():
			continue
		lo = lo.min(b.position)
		hi = hi.max(b.end)
	return (lo + hi) * 0.5


static func _cam_at(base: Dictionary, pos: Vector3, tgt0: Vector3, fov: float, keep: String, x: float, h_dir: Vector3, cc: Vector3, ox: float, oy: float, use_x := false, use_y := false) -> Dictionary:
	var c := base.duplicate()
	var p2 := pos
	var f2 := fov
	var dir := (tgt0 - pos).normalized()
	if keep == "fov":
		p2 = tgt0 - dir * x
	elif keep == "height":
		p2 = Vector3(tgt0.x, pos.y, tgt0.z) - h_dir * x
	else:
		f2 = clampf(rad_to_deg(2.0 * atan(x)), 1.0, 170.0)
	var xf := look(p2, tgt0)
	c["fov"] = f2
	var fl := focal(c)
	var dc := maxf(-(xf.affine_inverse() * cc).z, 1e-3)
	# the pieces' middle is put ON the view axis first (so its pixel is fixed whatever the distance), then offset by (ox, oy) pixels
	var cl: Vector3 = xf.affine_inverse() * cc
	var sh := Vector3.ZERO
	if use_x:
		sh += xf.basis.x * (cl.x + ox * dc / fl)
	if use_y and keep != "height":
		sh += xf.basis.y * (cl.y - oy * dc / fl)
	c["xf"] = look(p2 + sh, tgt0 + sh)
	c["target"] = tgt0 + sh
	return c


## the call: frame_to
static func serve_to(m: Node, p: Dictionary) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var cam := camera_of(m, p)
	if not bool(cam["ok"]):
		return cam
	var g := gather(m)
	if (g["names"] as Array).is_empty():
		return {"ok": false, "error": "nothing to frame: no part is on screen"}
	var idx: Array = []
	var req: Array = p.get("pieces", []) if p.get("pieces") is Array else ([p["pieces"]] if p.has("pieces") else [])
	if not req.is_empty():
		idx = select(g, req)
		if idx.is_empty():
			return {"ok": false, "error": "no piece matches %s" % JSON.stringify(req)}
	var axis := "w"
	var want := 0.0
	var rows: Dictionary = {}
	if p.has("width_share"):
		want = float(p["width_share"])
	elif p.has("width_pct"):
		want = float(p["width_pct"]) / 100.0
	elif p.has("height_share"):
		axis = "h"
		want = float(p["height_share"])
	elif p.get("rows") is Dictionary and (p["rows"] as Dictionary).has("top") and (p["rows"] as Dictionary).has("bottom"):
		rows = p["rows"]
		axis = "h"
		want = (float(rows["bottom"]) - float(rows["top"])) / float(cam["h"])
	if want <= 0.001 or want > 50.0:
		return {"ok": false, "error": "ask for width_share (0.835), width_pct (83.5), height_share or rows {top, bottom} in picture rows"}
	var keep := String(p.get("keep", "fov"))
	if keep not in ["fov", "height", "distance"]:
		return {"ok": false, "error": "keep is \"fov\" (move along the aim line), \"height\" (keep the camera's height and target) or \"distance\" (keep the position, change the fov)"}
	if not rows.is_empty() and keep == "height":
		return {"ok": false, "error": "rows places the pieces vertically, which moves the camera's height: use keep \"fov\" or \"distance\""}
	var centre := "x"
	if p.has("center"):
		centre = "x" if (p["center"] is bool and p["center"]) else String(p["center"]) if not (p["center"] is bool) else "none"
	if not rows.is_empty() and centre == "x":
		centre = "x"
	var r := solve(g, idx, cam, axis, want, keep, centre, rows)
	if not bool(r["ok"]):
		return r
	var c2: Dictionary = r["cam"]
	var out := {"ok": true, "asked": snappedf(want, 0.0001), "got": snappedf(float(r["share"]), 0.0001), "axis": "width" if axis == "w" else "height", "keep": keep,
		"camera": {"pos": _arr(r["pos"]), "target": _arr(r["target"]), "fov": snappedf(float(r["fov"]), 0.0001)},
		"facts": scene_facts(g, idx, c2), "iterations": r["iterations"], "applied": false}
	if bool(p.get("apply", false)):
		var sr: Dictionary = TempleLight.set_camera(m, r["pos"], r["target"], float(r["fov"]))
		out["applied"] = bool(sr.get("ok", false))
	out["ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	return out
