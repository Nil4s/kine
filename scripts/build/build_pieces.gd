## build_pieces.gd - PIECES of a building (docs/BUILD_PLAN.md phase 1f): STAIRS and the furniture-blocks of a fight set. Each piece is a
## parametric record in the building's "pieces" list, never a stored mesh:
##   {"id": "p1", "kind": "stairs", "x": 2.0, "z": 1.5, "yaw": 90, "storey": 0, "w": 1.0, "t": 0.28}
## (x, z) is the middle of the piece's footprint (it snaps to the 0.5 m grid), yaw is a multiple of 90 (the round arrow), storey is the
## floor it stands on, and the rest are the kind's NAMED NUMBERS (DEFS): the panel edits them. A piece is ONE closed solid with an exact
## volume: a union of boxes meshed by the building's own rectilinear grid (so the faces between touching boxes vanish and the solid is closed
## and manifold by construction), or a prism (the ramp).
##
## STAIRS: the rise is the building's floor_height; the step count is automatic from a 0.18 m riser (n = ceil(rise / 0.18) risers of
## rise / n each, n - 1 treads of "t" deep; the last riser is the upper floor's edge). "stairs": one straight flight along local +Z. "stairs_l":
## a flight, a w x w landing, a second flight turned 90 degrees (toward +X, "flip" turns it toward -X). Stairs CUT THE UPPER FLOOR SLAB
## (the stairwell: the treads' plan, one floor slab thick) when the house has a floor above.
## COLLISION (BuildStage via Props.register_building): a piece is boxes + their tops as supports; a flight of stairs is a RAMP (a prism the
## fighter walks up) whose slope runs through the treads' front edges (the nosings) and meets the upper floor's top exactly, so a foot is
## never inside a step and at most one riser over a tread; the L's landing is a box.
class_name BuildPieces
extends RefCounted

const RISER := 0.18        # m: the step count is automatic from this riser (the real riser is rise / count, never above it)
const GRID := 0.5
const EPS := 1e-6
## the picker's categories: [name, [kinds]]
const CATS := [["Stairs", ["stairs", "stairs_l"]], ["Furniture", ["table", "bench", "crate"]], ["Fight blocks", ["pillar", "fence", "ramp", "platform"]]]
## kind -> its label, its one-line help and its named numbers {key: [default, min, max, label]} (metres)
const DEFS := {
	"stairs": {"label": "Stairs", "help": "a straight flight up to the floor above; it cuts the stairwell hole",
		"params": {"w": [1.0, 0.6, 3.0, "Width"], "t": [0.28, 0.2, 0.45, "Tread"]}},
	"stairs_l": {"label": "L stairs", "help": "a flight, a landing and a turn; it cuts the stairwell hole",
		"params": {"w": [1.0, 0.6, 3.0, "Width"], "t": [0.28, 0.2, 0.45, "Tread"]}},
	"table": {"label": "Table", "help": "top and four legs, 1.2 x 0.7 m",
		"params": {"w": [1.2, 0.4, 4.0, "Length"], "d": [0.7, 0.4, 3.0, "Depth"], "h": [0.75, 0.3, 1.5, "Height"]}},
	"bench": {"label": "Bench", "help": "seat and four legs, 1.4 m long",
		"params": {"w": [1.4, 0.4, 4.0, "Length"], "d": [0.35, 0.2, 1.0, "Depth"], "h": [0.45, 0.2, 1.0, "Height"]}},
	"crate": {"label": "Crate", "help": "a solid box to hide behind or jump onto",
		"params": {"w": [0.6, 0.2, 3.0, "Width"], "d": [0.4, 0.2, 3.0, "Depth"], "h": [0.5, 0.2, 2.0, "Height"]}},
	"pillar": {"label": "Pillar", "help": "a square column",
		"params": {"w": [0.4, 0.15, 2.0, "Width"], "d": [0.4, 0.15, 2.0, "Depth"], "h": [2.7, 0.5, 8.0, "Height"]}},
	"fence": {"label": "Fence", "help": "posts and two rails, 2 m long",
		"params": {"w": [2.0, 0.5, 8.0, "Length"], "d": [0.1, 0.05, 0.4, "Thickness"], "h": [1.0, 0.4, 2.5, "Height"]}},
	"ramp": {"label": "Ramp", "help": "a wedge, rising toward its front",
		"params": {"w": [1.0, 0.4, 4.0, "Width"], "d": [2.0, 0.5, 8.0, "Length"], "h": [0.5, 0.1, 3.0, "Height"]}},
	"platform": {"label": "Platform", "help": "a stage block to fight on",
		"params": {"w": [2.0, 0.5, 8.0, "Width"], "d": [2.0, 0.5, 8.0, "Depth"], "h": [0.5, 0.1, 3.0, "Height"]}},
}


static func is_stairs(p: Dictionary) -> bool:
	return String(p.get("kind", "")) == "stairs" or String(p.get("kind", "")) == "stairs_l"


## a new piece's record (numbers at their defaults); {} for an unknown kind
static func make(id: String, kind: String, x: float, z: float, yaw := 0.0, storey := 0) -> Dictionary:
	if not DEFS.has(kind):
		return {}
	var p := {"id": id, "kind": kind, "x": x, "z": z, "yaw": yaw, "storey": storey}
	for k in DEFS[kind]["params"]:
		p[k] = DEFS[kind]["params"][k][0]
	return p


static func value(p: Dictionary, key: String) -> float:
	var d: Array = DEFS[String(p["kind"])]["params"][key]
	var v = p.get(key, d[0])
	return clampf(float(v), d[1], d[2]) if (v is float or v is int) and is_finite(float(v)) else float(d[0])


## the stairs' numbers: {"rise", "n" risers, "r" the riser, "t" the tread, "w", "a" treads in the first flight, "b" in the second (L), "len" the plan length of a straight flight}
static func stairs_numbers(b: Dictionary, p: Dictionary) -> Dictionary:
	var rise := Building.num(b, "floor_height", 2.8)
	var n := maxi(int(ceil(rise / RISER - 1e-9)), 2)
	var t := value(p, "t")
	var out := {"rise": rise, "n": n, "r": rise / n, "t": t, "w": value(p, "w"), "a": 0, "b": 0, "len": (n - 1) * t}
	if String(p["kind"]) == "stairs_l":
		var a := int((n - 2) / 2)
		out["a"] = a
		out["b"] = n - 2 - a
	return out


## the piece's boxes in its LOCAL frame (origin = the middle of its footprint, y = 0 on its floor), as [AABB, treadtop?]: a union of boxes;
## [] for the ramp (a prism)
static func local_boxes(b: Dictionary, p: Dictionary) -> Array:
	var out := []
	match String(p["kind"]):
		"stairs":
			var s := stairs_numbers(b, p)
			var ox: float = -float(s["w"]) * 0.5
			var oz: float = -float(s["len"]) * 0.5
			for k in range(1, int(s["n"])):
				out.append(AABB(Vector3(ox, 0, oz + (k - 1) * float(s["t"])), Vector3(s["w"], k * float(s["r"]), s["t"])))
		"stairs_l":
			var s := stairs_numbers(b, p)
			var w: float = s["w"]
			var t: float = s["t"]
			var r: float = s["r"]
			var a: int = s["a"]
			var bb: int = s["b"]
			var ox := -(w + bb * t) * 0.5
			var oz := -(a * t + w) * 0.5
			for k in range(1, a + 1):
				out.append(AABB(Vector3(ox, 0, oz + (k - 1) * t), Vector3(w, k * r, t)))
			out.append(AABB(Vector3(ox, 0, oz + a * t), Vector3(w, (a + 1) * r, w)))   # the landing
			for j in range(1, bb + 1):
				out.append(AABB(Vector3(ox + w + (j - 1) * t, 0, oz + a * t), Vector3(t, (a + 1 + j) * r, w)))
			if bool(p.get("flip", false)):
				out = out.map(func(bx): return AABB(Vector3(-(bx.position.x + bx.size.x), bx.position.y, bx.position.z), bx.size))
		"table":
			var w := value(p, "w")
			var d := value(p, "d")
			var h := value(p, "h")
			var top := 0.04
			var lg := minf(0.06, minf(w, d) * 0.3)
			out.append(AABB(Vector3(-w * 0.5, h - top, -d * 0.5), Vector3(w, top, d)))
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					out.append(AABB(Vector3(sx * (w * 0.5 - lg * 0.5 - 0.04) - lg * 0.5, 0, sz * (d * 0.5 - lg * 0.5 - 0.04) - lg * 0.5), Vector3(lg, h - top, lg)))
		"bench":
			var w := value(p, "w")
			var d := value(p, "d")
			var h := value(p, "h")
			var top := 0.04
			var lg := minf(0.05, d * 0.4)
			out.append(AABB(Vector3(-w * 0.5, h - top, -d * 0.5), Vector3(w, top, d)))
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					out.append(AABB(Vector3(sx * (w * 0.5 - lg * 0.5 - 0.1) - lg * 0.5, 0, sz * (d * 0.5 - lg * 0.5 - 0.04) - lg * 0.5), Vector3(lg, h - top, lg)))
		"crate", "pillar", "platform":
			var sz := Vector3(value(p, "w"), value(p, "h"), value(p, "d"))
			out.append(AABB(Vector3(-sz.x * 0.5, 0, -sz.z * 0.5), sz))
		"fence":
			var w := value(p, "w")
			var d := value(p, "d")
			var h := value(p, "h")
			var post := minf(0.12, w * 0.2)
			out.append(AABB(Vector3(-w * 0.5, 0, -d * 0.5), Vector3(post, h, d)))
			out.append(AABB(Vector3(w * 0.5 - post, 0, -d * 0.5), Vector3(post, h, d)))
			var rail := h * 0.1
			for fy in [0.55, 0.9]:
				out.append(AABB(Vector3(-w * 0.5, h * fy - rail * 0.5, -d * 0.5), Vector3(w, rail, d)))
	return out


## the ramp as a prism's profile in (z, y): a triangle rising toward +Z
static func ramp_profile(p: Dictionary) -> PackedVector2Array:
	var d := value(p, "d")
	var h := value(p, "h")
	return PackedVector2Array([Vector2(-d * 0.5, 0), Vector2(d * 0.5, 0), Vector2(d * 0.5, h)])


## the world transform of a piece's local frame: its middle on its floor, turned by yaw about +Y
static func frame(b: Dictionary, p: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(p.get("yaw", 0.0)))), Vector3(float(p["x"]), float(int(p.get("storey", 0))) * Building.num(b, "floor_height", 2.8), float(p["z"])))


## the piece as ONE closed solid appended to acc ("verts" / "faces", like Building.to_kmesh's): boxes by the rectilinear grid, the ramp as a prism
static func mesh_into(b: Dictionary, p: Dictionary, acc: Dictionary) -> void:
	var xf := frame(b, p)
	var base: int = acc["verts"].size()
	if String(p["kind"]) == "ramp":
		var poly := ramp_profile(p)
		var hw := value(p, "w") * 0.5
		var verts := []
		for sx in [-hw, hw]:
			for q in poly:
				verts.append(Vector3(sx, q.y, q.x))
		var n := poly.size()   # verts: x = -hw (0..n-1), x = +hw (n..2n-1)
		var faces := [PackedInt32Array([0, 1, 2]), PackedInt32Array([n, n + 2, n + 1])]
		for i in n:
			var j := (i + 1) % n
			faces.append(PackedInt32Array([i, j, n + j, n + i]))
		var ctr := Vector3.ZERO
		for v in verts:
			ctr += v
		ctr /= verts.size()
		for fi in faces.size():   # convex: a face whose normal looks toward the middle is turned round
			var f: PackedInt32Array = faces[fi]
			var nrm: Vector3 = (verts[f[1]] - verts[f[0]]).cross(verts[f[2]] - verts[f[0]])
			if nrm.dot(verts[f[0]] - ctr) < 0.0:
				var rev := Array(f)
				rev.reverse()
				faces[fi] = PackedInt32Array(rev)
		for v in verts:
			acc["verts"].append(xf * (v as Vector3))
		for f in faces:
			acc["faces"].append(PackedInt32Array(Array(f).map(func(i): return int(i) + base)))
		return
	var boxes := []
	for bx in local_boxes(b, p):
		boxes.append([bx, "piece", 1])
	if boxes.is_empty():
		return
	Building._mesh_grid(Building._grid(boxes, ["piece"]), xf.basis, acc)
	for i in range(base, acc["verts"].size()):
		acc["verts"][i] = (acc["verts"][i] as Vector3) + xf.origin


## the piece's solid volume (m3): the ramp analytic, the others the union of their boxes
static func volume(b: Dictionary, p: Dictionary) -> float:
	if String(p["kind"]) == "ramp":
		return 0.5 * value(p, "w") * value(p, "d") * value(p, "h")
	var boxes := []
	for bx in local_boxes(b, p):
		boxes.append([bx, "piece", 1])
	var G := Building._grid(boxes, ["piece"])   # the union: boxes that overlap (a fence's rails and posts) count once
	var v := 0.0
	for k in G["nz"]:
		for j in G["ny"]:
			for i in G["nx"]:
				if G["fill"][i + j * G["nx"] + k * G["nx"] * G["ny"]] == 1:
					v += (G["X"][i + 1] - G["X"][i]) * (G["Y"][j + 1] - G["Y"][j]) * (G["Z"][k + 1] - G["Z"][k])
	return v


## the piece's boxes in the world (axis-aligned: yaw is a multiple of 90): [AABB]
static func world_boxes(b: Dictionary, p: Dictionary) -> Array:
	var xf := frame(b, p)
	return local_boxes(b, p).map(func(bx): return _world_aabb(xf, bx))


static func _world_aabb(xf: Transform3D, bx: AABB) -> AABB:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in 8:
		var q: Vector3 = xf * (bx.position + Vector3(bx.size.x * (i & 1), bx.size.y * ((i >> 1) & 1), bx.size.z * ((i >> 2) & 1)))
		lo = Vector3(minf(lo.x, q.x), minf(lo.y, q.y), minf(lo.z, q.z))
		hi = Vector3(maxf(hi.x, q.x), maxf(hi.y, q.y), maxf(hi.z, q.z))
	return AABB(lo, hi - lo)


## the plan of the footprint in the world: Rect2 (x, z) round the piece
static func footprint(b: Dictionary, p: Dictionary) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var boxes := world_boxes(b, p)
	if String(p["kind"]) == "ramp":
		boxes = [_world_aabb(frame(b, p), AABB(Vector3(-value(p, "w") * 0.5, 0, -value(p, "d") * 0.5), Vector3(value(p, "w"), value(p, "h"), value(p, "d"))))]
	for bx in boxes:
		lo = Vector2(minf(lo.x, bx.position.x), minf(lo.y, bx.position.z))
		hi = Vector2(maxf(hi.x, bx.end.x), maxf(hi.y, bx.end.z))
	return Rect2(lo, hi - lo)


## the stairwell's cut boxes in the world: the plan of the treads, one floor slab thick, in the floor above (none for other pieces, or when
## there is no floor above)
static func stairwell(b: Dictionary, p: Dictionary) -> Array:
	if not is_stairs(p):
		return []
	var s := int(p.get("storey", 0))
	if Building.storey_count(b) <= s + 1:
		return []
	var fh := Building.num(b, "floor_height", 2.8)
	var up := fh * float(s + 1)
	var ft := Building.num(b, "floor_thickness", 0.2)
	for r in b.get("rooms", []):
		if int(r.get("storey", 0)) == s + 1:
			ft = maxf(ft, fh - Building.num(b, r.get("height"), 2.7))
			break
	var xf := frame(b, p)
	var out := []
	for bx in local_boxes(b, p):
		var plan := _world_aabb(xf, AABB(Vector3((bx as AABB).position.x, 0, (bx as AABB).position.z), Vector3((bx as AABB).size.x, 1.0, (bx as AABB).size.z)))
		out.append(AABB(Vector3(plan.position.x, up - ft, plan.position.z), Vector3(plan.size.x, ft, plan.size.z)))
	return out


## the cuts of every stairs piece
static func all_stairwells(b: Dictionary) -> Array:
	var out := []
	for p in b.get("pieces", []):
		out.append_array(stairwell(b, p))
	return out


## COLLISION of one piece for the fighter: {"boxes": [{"xf", "half"}], "supports": [[y, Vector2 centre, Vector2 size]], "ramps": [{"origin", "yaw", "poly", "w"}]}
static func collision(b: Dictionary, p: Dictionary) -> Dictionary:
	var boxes := []
	var sups := []
	var ramps := []
	var xf := frame(b, p)
	var yaw := float(p.get("yaw", 0.0))
	if String(p["kind"]) == "ramp":
		ramps.append({"origin": xf.origin, "yaw": yaw, "poly": ramp_profile(p), "w": value(p, "w") * 0.5})
		return {"boxes": boxes, "supports": sups, "ramps": ramps}
	if is_stairs(p):
		var s := stairs_numbers(b, p)
		var n: int = s["n"]
		var r: float = s["r"]
		var t: float = s["t"]
		var w: float = s["w"]
		if String(p["kind"]) == "stairs":
			var len: float = s["len"]   # the slope through the nosings: from r at z = 0 up to the floor above at z = len
			var poly := PackedVector2Array([Vector2(0, 0), Vector2(len, 0), Vector2(len, n * r), Vector2(0, r)])
			ramps.append({"origin": xf * Vector3(0, 0, -len * 0.5), "yaw": yaw, "poly": poly, "w": w * 0.5})
		else:
			var a: int = s["a"]
			var bb: int = s["b"]
			var fl := -1.0 if bool(p.get("flip", false)) else 1.0
			var ox := -(w + bb * t) * 0.5
			var oz := -(a * t + w) * 0.5
			if a > 0:
				var l1 := a * t
				ramps.append({"origin": xf * Vector3(ox * fl + (w * 0.5) * fl, 0, oz), "yaw": yaw, "poly": PackedVector2Array([Vector2(0, 0), Vector2(l1, 0), Vector2(l1, (a + 1) * r), Vector2(0, r)]), "w": w * 0.5})
			var landing := AABB(Vector3(ox, 0, oz + a * t), Vector3(w, (a + 1) * r, w))
			if fl < 0.0:
				landing = AABB(Vector3(-(landing.position.x + landing.size.x), 0, landing.position.z), landing.size)
			var wl := _world_aabb(xf, landing)
			boxes.append({"xf": Transform3D(Basis(), wl.get_center()), "half": wl.size * 0.5})
			sups.append([wl.end.y, Vector2(wl.get_center().x, wl.get_center().z), Vector2(wl.size.x, wl.size.z)])
			if bb > 0:
				var l2 := bb * t
				var start := Vector3((ox + w) * fl, 0, oz + a * t + w * 0.5)
				ramps.append({"origin": xf * start, "yaw": yaw + 90.0 * fl, "poly": PackedVector2Array([Vector2(0, 0), Vector2(l2, 0), Vector2(l2, n * r), Vector2(0, (a + 2) * r)]), "w": w * 0.5})
		return {"boxes": boxes, "supports": sups, "ramps": ramps}
	var wbs := world_boxes(b, p)
	for bx in wbs:
		boxes.append({"xf": Transform3D(Basis(), bx.get_center()), "half": bx.size * 0.5})
		var covered := false
		for o in wbs:
			if o != bx and o.position.y <= bx.end.y + EPS and o.end.y > bx.end.y + EPS and o.position.x < bx.end.x - EPS and o.end.x > bx.position.x + EPS and o.position.z < bx.end.z - EPS and o.end.z > bx.position.z + EPS:
				covered = true
		if not covered:
			sups.append([bx.end.y, Vector2(bx.get_center().x, bx.get_center().z), Vector2(bx.size.x, bx.size.z)])
	return {"boxes": boxes, "supports": sups, "ramps": ramps}


## the collision of every piece together (the same three lists)
static func collision_all(b: Dictionary) -> Dictionary:
	var out := {"boxes": [], "supports": [], "ramps": []}
	for p in b.get("pieces", []):
		var c := collision(b, p)
		for k in out:
			(out[k] as Array).append_array(c[k])
	return out


## where the piece fits: its middle moved (by whole grid steps) so the footprint is inside the interior of the room of its floor that holds
## (x, z); {"ok": false, "why"} when no room holds it or the room is too small
static func fit(b: Dictionary, p: Dictionary) -> Dictionary:
	var fp := footprint(b, p)
	var s := int(p.get("storey", 0))
	for r in b.get("rooms", []):
		if int(r.get("storey", 0)) != s or float(r.get("yaw", 0.0)) != 0.0:
			continue
		var t := clampf(Building.num(b, r.get("thickness"), 0.2), 0.01, minf(float(r["w"]), float(r["d"])) * 0.5 - 0.01)
		var inner := Rect2(float(r["x"]) + t, float(r["z"]) + t, float(r["w"]) - 2.0 * t, float(r["d"]) - 2.0 * t)
		if not inner.has_point(Vector2(float(p["x"]), float(p["z"]))):
			continue
		if fp.size.x > inner.size.x + EPS or fp.size.y > inner.size.y + EPS:
			return {"ok": false, "why": "the %s is %.1f x %.1f m: it does not fit in this room (%.1f x %.1f m inside)" % [DEFS[String(p["kind"])]["label"].to_lower(), fp.size.x, fp.size.y, inner.size.x, inner.size.y]}
		var dx := 0.0
		var dz := 0.0
		if fp.position.x < inner.position.x:
			dx = inner.position.x - fp.position.x
		elif fp.end.x > inner.end.x:
			dx = inner.end.x - fp.end.x
		if fp.position.y < inner.position.y:
			dz = inner.position.y - fp.position.y
		elif fp.end.y > inner.end.y:
			dz = inner.end.y - fp.end.y
		return {"ok": true, "x": float(p["x"]) + dx, "z": float(p["z"]) + dz, "room": String(r["id"])}
	return {"ok": false, "why": "put it inside a room, on its floor"}


## the file's piece list entry, cleaned: {} when it is not a piece
static func clean(d: Variant) -> Dictionary:
	if not (d is Dictionary) or not DEFS.has(String((d as Dictionary).get("kind", ""))):
		return {}
	var num := func(v, def: float) -> float:
		return float(v) if (v is float or v is int) and is_finite(float(v)) else def
	var yaw := snappedf(fposmod(num.call(d.get("yaw", 0.0), 0.0), 360.0), 90.0)
	var p := {"id": String(d.get("id", "p0")), "kind": String(d["kind"]), "x": num.call(d.get("x", 0.0), 0.0), "z": num.call(d.get("z", 0.0), 0.0),
		"yaw": 0.0 if yaw >= 360.0 else yaw, "storey": clampi(int(d.get("storey", 0)), 0, 30)}
	for k in DEFS[String(d["kind"])]["params"]:
		var e: Array = DEFS[String(d["kind"])]["params"][k]
		p[k] = clampf(num.call(d.get(k, e[0]), e[0]), e[1], e[2])
	if bool(d.get("flip", false)) and String(d["kind"]) == "stairs_l":
		p["flip"] = true
	return p
