## building.gd - A BUILDING as a PARAMETRIC RECORD (BUILD mode, docs/BUILD_PLAN.md phase 1). The record is plain JSON-able
## data (the scene file's "building" key, the undo snapshot, the words plan all hold the same dictionary); the mesh is
## never stored, it is REGENERATED from the record (to_kmesh / to_array_mesh), so "change one number and the house
## follows" is the only way the house changes.
##
## THE RECORD (VERSION 1; metres, Y up, the floor at y = 0):
##   {"version": 1, "name": "Bay house",
##    "params":   {"wall_height": 2.7, "wall_thickness": 0.2, ...}           the NAMED NUMBERS (PARAMS below)
##    "rooms":    [{"id": "r1", "x": 0, "z": 0, "w": 4, "d": 3, "yaw": 0,
##                  "height": "wall_height", "thickness": "wall_thickness", "floor": true}]
##    "openings": [{"id": "o1", "room": "r1", "wall": "front", "kind": "door", "at": 0,
##                  "w": "door_width", "h": "door_height", "sill": 0}]}
## A number field holds a number OR the name of a param: "height": "wall_height" follows the param, "height": 3.0 is this
## room's own. (x, z) is the room's corner with the smallest coordinates, w along +X, d along +Z, both OUTER sizes (the
## rectangle the user drags is the outside of the walls); yaw turns the room about that corner (degrees, about +Y).
## Walls: "front" z = 0 (faces -Z), "back" z = d, "left" x = 0, "right" x = w. An opening's "at" is metres from its wall's
## centre, positive toward +X (front / back) or +Z (left / right); it is clamped so it stays between the corner walls.
##
## THE SOLID: each room is boxes (4 wall slabs, a floor slab under y = 0) minus the openings' boxes. The boxes cut space
## into a rectilinear grid (every box face is a grid plane); a cell is solid when its centre is in a solid box and in no
## cut box, and a face is written wherever a solid cell meets an empty one. So the result is CLOSED and manifold by
## construction (every grid edge has exactly its two faces, no T-junctions), its volume is exact, and an opening removes
## exactly its own volume. Rooms with the same yaw are meshed in ONE grid, so two rooms drawn wall to wall share one wall.
## 1d: FLOORS: a room's "storey" (0 = the ground floor, absent = 0) lifts it by storey x floor_height (its own floor slab sits
## under it, overlapping the walls below: the union stays one solid). INTERIOR WALLS: "walls": [{"id": "i1", "room": "r1",
## "axis": "z" (runs along Z, at x = pos) | "x" (runs along X, at z = pos), "pos": metres from the room's corner, "thickness":
## "inner_wall_thickness"}], between the outer walls, as high as the room; an opening's "wall" may be such an id (its "at" is
## metres from that wall's middle, toward +X / +Z). THE ROOF: "roof": {"kind": "gable"|"flat"|"shed", "pitch": degrees,
## "overhang": number or param name ("roof_overhang")}: ONE more closed convex solid on the top storey's footprint (its own
## vertices, added to the mesh when roles has "roof"; the fighter's collision has no roof).
## 1f: PIECES: "pieces": [{"id", "kind", "x", "z" (the middle of its footprint), "yaw" (0 / 90 / 180 / 270), "storey", + the kind's named
## numbers}] (scripts/build/build_pieces.gd): STAIRS (the rise follows floor_height; they cut the floor above, the stairwell) and the
## furniture-blocks of a fight set; each is ONE more closed solid (role "piece") with an exact volume.
## Faces are grid-cell quads (coplanar neighbours not merged: phase 2 swaps this mesher for KineCAD, see the plan).
class_name Building
extends RefCounted

const VERSION := 1
const WALLS := ["front", "right", "back", "left"]
const KINDS := ["door", "window", "arch"]
## the named numbers every new building starts with (the Door panel of build_openings.png): name -> [default, min, max]
const PARAMS := {
	"wall_height": [2.7, 1.0, 12.0], "wall_thickness": [0.2, 0.05, 1.0], "floor_thickness": [0.2, 0.05, 1.0],
	"door_width": [0.9, 0.4, 4.0], "door_height": [2.1, 1.0, 5.0],
	"window_width": [1.2, 0.2, 6.0], "window_height": [1.2, 0.2, 4.0], "window_sill": [0.9, 0.0, 4.0],
	"grid": [0.5, 0.05, 5.0],
	"floor_height": [2.8, 1.0, 15.0], "roof_overhang": [0.45, 0.0, 3.0], "inner_wall_thickness": [0.1, 0.05, 0.5],
}
const ROOFS := ["gable", "flat", "shed"]
const ROOF_PITCH := 25.0        # degrees: gable and shed
const SHED_LOW := 0.1           # m: a shed roof's low edge is this thick (a flat roof is floor_thickness thick)
const MIN_SIZE := 0.5   # a room smaller than this across is not a room (the drag's dead zone)
const EPS := 1e-6


## a new, empty building
static func make(nm := "Untitled") -> Dictionary:
	var p := {}
	for k in PARAMS:
		p[k] = PARAMS[k][0]
	return {"version": VERSION, "name": nm, "params": p, "rooms": [], "openings": []}


## a room by its outer corner and size; its numbers follow the params unless given. Returns its id
static func add_room(b: Dictionary, x: float, z: float, w: float, d: float, yaw := 0.0) -> String:
	var id := _new_id(b["rooms"], "r")
	b["rooms"].append({"id": id, "x": x, "z": z, "w": maxf(w, MIN_SIZE), "d": maxf(d, MIN_SIZE), "yaw": yaw,
		"height": "wall_height", "thickness": "wall_thickness", "floor": true})
	return id


## how many floors the house has (1 when there are rooms, 0 when empty)
static func storey_count(b: Dictionary) -> int:
	var n := 0
	for r in b.get("rooms", []):
		n = maxi(n, int(r.get("storey", 0)) + 1)
	return n


## + Floor: every room of the top floor is copied one floor up (same footprint, its interior walls too, no openings).
## Returns the new floor's index, -1 when there is nothing to copy
static func add_floor(b: Dictionary) -> int:
	var top := storey_count(b) - 1
	if top < 0:
		return -1
	for r in b["rooms"].duplicate():
		if int(r.get("storey", 0)) != top:
			continue
		var e: Dictionary = r.duplicate(true)
		e["id"] = _new_id(b["rooms"], "r")
		e["storey"] = top + 1
		b["rooms"].append(e)
		for w in b.get("walls", []).duplicate():
			if String(w["room"]) == String(r["id"]):
				var we: Dictionary = w.duplicate(true)
				we["id"] = _new_id(b["walls"], "i")
				we["room"] = e["id"]
				b["walls"].append(we)
	return top + 1


## Delete: the top floor goes (its rooms, their interior walls and openings). false when it is the only floor
static func remove_top_floor(b: Dictionary) -> bool:
	var top := storey_count(b) - 1
	if top < 1:
		return false
	var gone := []
	for r in b["rooms"].duplicate():
		if int(r.get("storey", 0)) == top:
			gone.append(String(r["id"]))
			b["rooms"].erase(r)
	for p in b.get("pieces", []).duplicate():
		if int(p.get("storey", 0)) >= top:
			b["pieces"].erase(p)
	if b.has("pieces") and b["pieces"].is_empty():
		b.erase("pieces")
	for list in ["walls", "openings"]:
		for e in b.get(list, []).duplicate():
			if gone.has(String(e["room"])):
				b[list].erase(e)
	return true


## the y of a room's floor
static func base_y(b: Dictionary, r: Dictionary) -> float:
	return float(int(r.get("storey", 0))) * num(b, "floor_height", 2.8)


## an interior wall in a room (axis "z" runs along Z at x = pos from the corner; "x" along X at z = pos). Returns its id
## ("" when the room is unknown)
static func add_wall(b: Dictionary, room: String, axis: String, pos: float) -> String:
	if room_of(b, room).is_empty() or not (axis == "x" or axis == "z"):
		return ""
	if not b.has("walls"):
		b["walls"] = []
	var id := _new_id(b["walls"], "i")
	b["walls"].append({"id": id, "room": room, "axis": axis, "pos": pos, "thickness": "inner_wall_thickness"})
	return id


## a piece (BuildPieces.DEFS kind) with its middle at (x, z) on a floor; its numbers at their defaults. Returns its id ("" for an unknown kind)
static func add_piece(b: Dictionary, kind: String, x: float, z: float, yaw := 0.0, storey := 0) -> String:
	if not BuildPieces.DEFS.has(kind):
		return ""
	if not b.has("pieces"):
		b["pieces"] = []
	var id := _new_id(b["pieces"], "p")
	b["pieces"].append(BuildPieces.make(id, kind, x, z, yaw, storey))
	return id


static func piece_of(b: Dictionary, id: String) -> Dictionary:
	for p in b.get("pieces", []):
		if String(p["id"]) == id:
			return p
	return {}


static func remove_piece(b: Dictionary, id: String) -> bool:
	var p := piece_of(b, id)
	if p.is_empty():
		return false
	b["pieces"].erase(p)
	if b["pieces"].is_empty():
		b.erase("pieces")
	return true


static func wall_of(b: Dictionary, id: String) -> Dictionary:
	for w in b.get("walls", []):
		if String(w["id"]) == id:
			return w
	return {}


## the roof: kind gable / flat / shed (a number or a param name for the overhang follows roof_overhang)
static func set_roof(b: Dictionary, kind: String) -> void:
	var old: Dictionary = b.get("roof", {})
	b["roof"] = {"kind": kind, "pitch": float(old.get("pitch", ROOF_PITCH)), "overhang": old.get("overhang", "roof_overhang")}


## an opening on a room's wall; its sizes follow the kind's params. Returns its id ("" when the room or wall is unknown)
static func add_opening(b: Dictionary, room: String, wall: String, kind := "door", at := 0.0) -> String:
	var inner := not WALLS.has(wall) and not wall_of(b, wall).is_empty() and String(wall_of(b, wall)["room"]) == room
	if room_of(b, room).is_empty() or not (WALLS.has(wall) or inner) or not KINDS.has(kind):
		return ""
	var id := _new_id(b["openings"], "o")
	var o := {"id": id, "room": room, "wall": wall, "kind": kind, "at": at}
	if kind == "window":
		o.merge({"w": "window_width", "h": "window_height", "sill": "window_sill"})
	else:
		o.merge({"w": "door_width", "h": "door_height", "sill": 0.0})
	b["openings"].append(o)
	return id


static func _new_id(list: Array, prefix: String) -> String:
	var n := 1
	var used := list.map(func(e): return String(e.get("id", "")))
	while used.has("%s%d" % [prefix, n]):
		n += 1
	return "%s%d" % [prefix, n]


static func room_of(b: Dictionary, id: String) -> Dictionary:
	for r in b.get("rooms", []):
		if String(r["id"]) == id:
			return r
	return {}


## a field's value: a number, or the named param it points to (an unknown name = def)
static func num(b: Dictionary, v: Variant, def := 0.0) -> float:
	if v is String:
		return float(b.get("params", {}).get(v, def))
	if v is float or v is int:
		return float(v)
	return def


# ---------------------------------------------------------------- the solid

## the room's boxes in its group frame (turned by -yaw about the world origin, so the room is axis-aligned; lifted by its
## floor's base): [[AABB, role, +1 solid / -1 cut]]
static func _room_boxes(b: Dictionary, r: Dictionary) -> Array:
	var yaw := deg_to_rad(float(r.get("yaw", 0.0)))
	var c := Vector3(float(r["x"]), 0, float(r["z"])).rotated(Vector3.UP, -yaw)
	c.y = base_y(b, r)
	var w := float(r["w"])
	var d := float(r["d"])
	var h := num(b, r.get("height"), 2.7)
	var t := clampf(num(b, r.get("thickness"), 0.2), 0.01, minf(w, d) * 0.5 - 0.01)
	var out := [
		[AABB(c, Vector3(w, h, t)), "wall", 1], [AABB(c + Vector3(0, 0, d - t), Vector3(w, h, t)), "wall", 1],
		[AABB(c + Vector3(0, 0, t), Vector3(t, h, d - 2 * t)), "wall", 1], [AABB(c + Vector3(w - t, 0, t), Vector3(t, h, d - 2 * t)), "wall", 1]]
	if bool(r.get("floor", true)):
		var ft := num(b, b["params"].get("floor_thickness"), 0.2)
		if int(r.get("storey", 0)) > 0:   # an upper floor's slab reaches down to the walls below, so a tall floor_height leaves no gap
			ft = maxf(ft, num(b, "floor_height", 2.8) - h)
		out.append([AABB(c + Vector3(0, -ft, 0), Vector3(w, ft, d)), "floor", 1])
	for iw in b.get("walls", []):
		if String(iw.get("room", "")) == String(r["id"]):
			var bx := inner_box(b, r, iw, c)
			if bx.size != Vector3.ZERO:
				out.append([bx, "wall", 1])
	for o in b.get("openings", []):
		if String(o.get("room", "")) == String(r["id"]):
			out.append([opening_box(b, r, o, c), "opening", -1])
	return out


## an interior wall's box (group frame, corner c); a zero box when the room is too small to hold it
static func inner_box(b: Dictionary, r: Dictionary, iw: Dictionary, c := Vector3.INF) -> AABB:
	if c == Vector3.INF:
		c = Vector3(float(r["x"]), 0, float(r["z"])).rotated(Vector3.UP, -deg_to_rad(float(r.get("yaw", 0.0))))
		c.y = base_y(b, r)
	var w := float(r["w"])
	var d := float(r["d"])
	var h := num(b, r.get("height"), 2.7)
	var t := clampf(num(b, r.get("thickness"), 0.2), 0.01, minf(w, d) * 0.5 - 0.01)
	var ti := clampf(num(b, iw.get("thickness"), 0.1), 0.01, 1.0)
	var along_z := String(iw.get("axis", "z")) == "z"
	var across := w if along_z else d
	var lo := t + ti * 0.5
	var hi := across - t - ti * 0.5
	if hi < lo:
		return AABB()
	var pos := clampf(float(iw.get("pos", across * 0.5)), lo, hi)
	if along_z:
		return AABB(c + Vector3(pos - ti * 0.5, 0, t), Vector3(ti, h, d - 2 * t))
	return AABB(c + Vector3(t, 0, pos - ti * 0.5), Vector3(w - 2 * t, h, ti))


## an opening's cut box (group frame, corner c), clamped onto its wall between the corner walls and under the wall top
static func opening_box(b: Dictionary, r: Dictionary, o: Dictionary, c := Vector3.INF) -> AABB:
	if c == Vector3.INF:
		c = Vector3(float(r["x"]), 0, float(r["z"])).rotated(Vector3.UP, -deg_to_rad(float(r.get("yaw", 0.0))))
		c.y = base_y(b, r)
	var w := float(r["w"])
	var d := float(r["d"])
	var h := num(b, r.get("height"), 2.7)
	var t := clampf(num(b, r.get("thickness"), 0.2), 0.01, minf(w, d) * 0.5 - 0.01)
	var wall := String(o.get("wall", "front"))
	var iw := wall_of(b, wall) if not WALLS.has(wall) else {}
	var along_x := wall == "front" or wall == "back"
	if not iw.is_empty():
		along_x = String(iw.get("axis", "z")) == "x"
	var span := (w if along_x else d) - 2 * t
	var ow := clampf(num(b, o.get("w"), 0.9), 0.05, maxf(span, 0.05))
	var sill := clampf(num(b, o.get("sill"), 0.0), 0.0, h - 0.05)
	var oh := clampf(num(b, o.get("h"), 2.1), 0.05, h - sill)
	var mid := (w if along_x else d) * 0.5 + clampf(num(b, o.get("at"), 0.0), -(span - ow) * 0.5, (span - ow) * 0.5)
	var lo := mid - ow * 0.5
	if not iw.is_empty():
		var ib := inner_box(b, r, iw, c)
		if along_x:
			return AABB(Vector3(c.x + lo, c.y + sill, ib.position.z), Vector3(ow, oh, ib.size.z))
		return AABB(Vector3(ib.position.x, c.y + sill, c.z + lo), Vector3(ib.size.x, oh, ow))
	match wall:
		"front":
			return AABB(c + Vector3(lo, sill, 0), Vector3(ow, oh, t))
		"back":
			return AABB(c + Vector3(lo, sill, d - t), Vector3(ow, oh, t))
		"left":
			return AABB(c + Vector3(0, sill, lo), Vector3(t, oh, ow))
		_:
			return AABB(c + Vector3(w - t, sill, lo), Vector3(t, oh, ow))


## the solid cells of one yaw group: {"X", "Y", "Z" (the grid planes), "fill" (PackedByteArray, i + j*nx + k*nx*ny)}
static func _grid(boxes: Array, roles: Array) -> Dictionary:
	var use := boxes.filter(func(e): return int(e[2]) < 0 or roles.has(String(e[1])))
	var sx := {}
	var sy := {}
	var sz := {}
	for e in use:
		var a: AABB = e[0]
		for s in [[sx, a.position.x, a.end.x], [sy, a.position.y, a.end.y], [sz, a.position.z, a.end.z]]:
			s[0][snappedf(s[1], EPS)] = true
			s[0][snappedf(s[2], EPS)] = true
	var X := sx.keys()
	var Y := sy.keys()
	var Z := sz.keys()
	X.sort()
	Y.sort()
	Z.sort()
	var nx := maxi(X.size() - 1, 0)
	var ny := maxi(Y.size() - 1, 0)
	var nz := maxi(Z.size() - 1, 0)
	var fill := PackedByteArray()
	fill.resize(nx * ny * nz)
	for k in nz:
		for j in ny:
			for i in nx:
				var p := Vector3((X[i] + X[i + 1]) * 0.5, (Y[j] + Y[j + 1]) * 0.5, (Z[k] + Z[k + 1]) * 0.5)
				var solid := false
				for e in use:
					if (e[0] as AABB).has_point(p):
						if int(e[2]) < 0:
							solid = false
							break
						solid = true
				fill[i + j * nx + k * nx * ny] = 1 if solid else 0
	return {"X": X, "Y": Y, "Z": Z, "nx": nx, "ny": ny, "nz": nz, "fill": fill}


## rooms by yaw (snapped to 0.01 deg): {yaw_deg: [room]}
static func _groups(b: Dictionary) -> Dictionary:
	var g := {}
	for r in b.get("rooms", []):
		var y := snappedf(fposmod(float(r.get("yaw", 0.0)), 360.0), 0.01)
		if not g.has(y):
			g[y] = []
		g[y].append(r)
	return g


## the building as ONE closed KMesh (every room, every yaw group); roles picks the parts ("wall", "floor")
static func to_kmesh(b: Dictionary, roles := ["wall", "floor", "roof", "piece"]) -> KMesh:
	var acc := {"verts": [], "faces": []}   # a Dictionary: the mesher's lambdas share it (a captured packed array is a copy)
	var g := _groups(b)
	for yaw in g:
		var boxes := []
		for r in g[yaw]:
			boxes.append_array(_room_boxes(b, r))
		if yaw == 0.0:
			for cut in BuildPieces.all_stairwells(b):   # the stairwell: the floor above is open over the stairs
				boxes.append([cut, "stairwell", -1])
		_mesh_grid(_grid(boxes, roles), Basis(Vector3.UP, deg_to_rad(yaw)), acc)
	if roles.has("piece"):
		for p in b.get("pieces", []):
			BuildPieces.mesh_into(b, p, acc)
	if roles.has("roof"):
		var rf := roof_solid(b)
		if not rf.is_empty():
			var base: int = acc["verts"].size()
			acc["verts"].append_array(rf["verts"])
			for f in rf["faces"]:
				acc["faces"].append(PackedInt32Array(Array(f).map(func(i): return int(i) + base)))
	return KMesh.new().from_arrays(PackedVector3Array(acc["verts"]), acc["faces"])


## the top floor's outline: the rectangle round every room of the top floor (rooms turned by their yaw about their corner), as
## Rect2 (x, z), and the y the roof stands on (the top of the tallest wall of that floor). {} when there is no room
static func roof_base(b: Dictionary) -> Dictionary:
	var top := storey_count(b) - 1
	if top < 0:
		return {}
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var yb := 0.0
	for r in b["rooms"]:
		if int(r.get("storey", 0)) != top:
			continue
		yb = maxf(yb, base_y(b, r) + num(b, r.get("height"), 2.7))
		var yaw := deg_to_rad(float(r.get("yaw", 0.0)))
		var o := Vector3(float(r["x"]), 0, float(r["z"]))
		for cn in [Vector3.ZERO, Vector3(float(r["w"]), 0, 0), Vector3(0, 0, float(r["d"])), Vector3(float(r["w"]), 0, float(r["d"]))]:
			var q: Vector3 = o + (cn as Vector3).rotated(Vector3.UP, yaw)
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.z))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.z))
	return {"rect": Rect2(lo, hi - lo), "y": yb}


## the roof as one closed convex solid: {"verts": [Vector3], "faces": [PackedInt32Array]} ({} = none). Over the top floor's outline
## grown by the overhang; the ridge (gable) / the slope's run (shed) is across the SHORTER side. gable: a triangle prism
## (volume = span x rise / 2 x length); shed: a trapezoid prism, low edge SHED_LOW thick, rising pitch over the span;
## flat: a slab floor_thickness thick
static func roof_solid(b: Dictionary) -> Dictionary:
	var rf: Dictionary = b.get("roof", {})
	var base := roof_base(b)
	if rf.is_empty() or base.is_empty():
		return {}
	var ov := maxf(num(b, rf.get("overhang"), 0.45), 0.0)
	var rect: Rect2 = (base["rect"] as Rect2).grow(ov)
	var yb: float = base["y"]
	var ridge_x := rect.size.x >= rect.size.y   # the ridge runs along X: the span is across Z
	var span := rect.size.y if ridge_x else rect.size.x
	var length := rect.size.x if ridge_x else rect.size.y
	var rise := tan(deg_to_rad(clampf(float(rf.get("pitch", ROOF_PITCH)), 1.0, 70.0))) * span
	var poly: Array
	match String(rf.get("kind", "gable")):
		"flat":
			var ft := num(b, "floor_thickness", 0.2)
			poly = [Vector2(0, 0), Vector2(span, 0), Vector2(span, ft), Vector2(0, ft)]
		"shed":
			poly = [Vector2(0, 0), Vector2(span, 0), Vector2(span, SHED_LOW + rise), Vector2(0, SHED_LOW)]
		_:
			poly = [Vector2(0, 0), Vector2(span, 0), Vector2(span * 0.5, rise * 0.5)]
	var at := func(u: float, y: float, l: float) -> Vector3:
		return Vector3(rect.position.x + l, yb + y, rect.position.y + u) if ridge_x else Vector3(rect.position.x + u, yb + y, rect.position.y + l)
	var n := poly.size()
	var verts := []
	for p in poly:
		verts.append(at.call(p.x, p.y, 0.0))
	for p in poly:
		verts.append(at.call(p.x, p.y, length))
	var faces := []
	faces.append(PackedInt32Array(range(n)))
	faces.append(PackedInt32Array(range(2 * n - 1, n - 1, -1)))
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
	return {"verts": verts, "faces": faces}


## the grid's boundary faces, outward and counter-clockwise, turned back by basis into the world, appended to acc's
## "verts" / "faces"
static func _mesh_grid(G: Dictionary, basis: Basis, acc: Dictionary) -> void:
	var verts: Array = acc["verts"]
	var faces: Array = acc["faces"]
	var nx: int = G["nx"]
	var ny: int = G["ny"]
	var nz: int = G["nz"]
	var fill: PackedByteArray = G["fill"]
	var vid := {}
	var at := func(i: int, j: int, k: int) -> int:
		var key := i + j * (nx + 1) + k * (nx + 1) * (ny + 1)
		if not vid.has(key):
			vid[key] = verts.size()
			verts.append(basis * Vector3(G["X"][i], G["Y"][j], G["Z"][k]))
		return vid[key]
	var solid := func(i: int, j: int, k: int) -> bool:
		return i >= 0 and j >= 0 and k >= 0 and i < nx and j < ny and k < nz and fill[i + j * nx + k * nx * ny] == 1
	for k in nz:
		for j in ny:
			for i in nx:
				if not solid.call(i, j, k):
					continue
				# each side: the neighbour, and its 4 corners counter-clockwise seen from outside
				if not solid.call(i + 1, j, k):
					faces.append(PackedInt32Array([at.call(i + 1, j, k), at.call(i + 1, j + 1, k), at.call(i + 1, j + 1, k + 1), at.call(i + 1, j, k + 1)]))
				if not solid.call(i - 1, j, k):
					faces.append(PackedInt32Array([at.call(i, j, k), at.call(i, j, k + 1), at.call(i, j + 1, k + 1), at.call(i, j + 1, k)]))
				if not solid.call(i, j + 1, k):
					faces.append(PackedInt32Array([at.call(i, j + 1, k), at.call(i, j + 1, k + 1), at.call(i + 1, j + 1, k + 1), at.call(i + 1, j + 1, k)]))
				if not solid.call(i, j - 1, k):
					faces.append(PackedInt32Array([at.call(i, j, k), at.call(i + 1, j, k), at.call(i + 1, j, k + 1), at.call(i, j, k + 1)]))
				if not solid.call(i, j, k + 1):
					faces.append(PackedInt32Array([at.call(i, j, k + 1), at.call(i + 1, j, k + 1), at.call(i + 1, j + 1, k + 1), at.call(i, j + 1, k + 1)]))
				if not solid.call(i, j, k - 1):
					faces.append(PackedInt32Array([at.call(i, j, k), at.call(i, j + 1, k), at.call(i + 1, j + 1, k), at.call(i + 1, j, k)]))


## the drawable mesh (flat-shaded: a building's faces are planes)
static func to_array_mesh(b: Dictionary, roles := ["wall", "floor", "roof", "piece"]) -> ArrayMesh:
	return to_kmesh(b, roles).to_array_mesh(false)


## COLLISION for the fighter (Props' solid format: [{"xf": Transform3D at the box centre, "half": Vector3}]): the solid
## cells, merged along X into runs, so a wall with a door is a few boxes and the doorway is open
static func collision_boxes(b: Dictionary, roles := ["wall", "floor"]) -> Array:
	var out := []
	var g := _groups(b)
	for yaw in g:
		var boxes := []
		for r in g[yaw]:
			boxes.append_array(_room_boxes(b, r))
		if yaw == 0.0:
			for cut in BuildPieces.all_stairwells(b):   # the stairwell is open for the fighter too
				boxes.append([cut, "stairwell", -1])
		var G := _grid(boxes, roles)
		var basis := Basis(Vector3.UP, deg_to_rad(yaw))
		var nx: int = G["nx"]
		var ny: int = G["ny"]
		for k in G["nz"]:
			for j in ny:
				var i := 0
				while i < nx:
					if G["fill"][i + j * nx + k * nx * ny] == 0:
						i += 1
						continue
					var i0 := i
					while i < nx and G["fill"][i + j * nx + k * nx * ny] == 1:
						i += 1
					var lo := Vector3(G["X"][i0], G["Y"][j], G["Z"][k])
					var hi := Vector3(G["X"][i], G["Y"][j + 1], G["Z"][k + 1])
					out.append({"xf": Transform3D(basis, basis * ((lo + hi) * 0.5)), "half": (hi - lo) * 0.5})
	return out


## the floor slabs' tops for the fighter's feet: Props' support format [[y, Vector2 centre (x, z), Vector2 size]], one per room
static func supports(b: Dictionary) -> Array:
	var out := []
	for r in b.get("rooms", []):
		if bool(r.get("floor", true)):
			out.append([base_y(b, r), Vector2(float(r["x"]) + float(r["w"]) * 0.5, float(r["z"]) + float(r["d"]) * 0.5), Vector2(float(r["w"]), float(r["d"]))])
	return out


## NAMED POINTS: one per door / arch ("front door", "back door", "left door", "right door", "inner door"; a second one of a name
## is numbered "front door 2"). {"name", "pos" (the opening's middle at floor level), "out" (the unit vector pointing out of the
## room through it, floor plane), "room", "clear" (the opening's height above the floor, m: sill + height, what a body must fit under)}.
## The walk card goes in from pos + out x d to pos - out x d
static func anchors(b: Dictionary) -> Array:
	var out := []
	var seen := {}
	for o in b.get("openings", []):
		if String(o.get("kind", "")) == "window":
			continue
		var r := room_of(b, String(o.get("room", "")))
		if r.is_empty():
			continue
		var wall := String(o.get("wall", "front"))
		var bx := opening_box(b, r, o)
		var yaw := deg_to_rad(float(r.get("yaw", 0.0)))
		var mid := Vector3(bx.get_center().x, 0, bx.get_center().z).rotated(Vector3.UP, yaw)
		mid.y = base_y(b, r)
		var nrm := Vector3.ZERO
		var nm := "inner door"
		match wall:
			"front": nrm = Vector3(0, 0, -1); nm = "front door"
			"back": nrm = Vector3(0, 0, 1); nm = "back door"
			"left": nrm = Vector3(-1, 0, 0); nm = "left door"
			"right": nrm = Vector3(1, 0, 0); nm = "right door"
			_:
				var iw := wall_of(b, wall)
				nrm = Vector3(0, 0, -1) if String(iw.get("axis", "z")) == "x" else Vector3(-1, 0, 0)
		var n := int(seen.get(nm, 0)) + 1
		seen[nm] = n
		out.append({"name": nm if n == 1 else "%s %d" % [nm, n], "pos": mid, "out": nrm.rotated(Vector3.UP, yaw), "room": String(r["id"]),
			"clear": bx.end.y - base_y(b, r)})
	return out


## the anchor called name ({} when there is none)
static func anchor(b: Dictionary, name: String) -> Dictionary:
	for a in anchors(b):
		if String(a["name"]) == name:
			return a
	return {}


# ---------------------------------------------------------------- the file

## the scene file's "building" entry: the record, numbers snapped to 0.1 mm
static func to_file(b: Dictionary) -> Dictionary:
	if bool(b.get("readonly", false)):
		return (b["raw"] as Dictionary).duplicate(true)   # a newer version's record: written back exactly as it was read
	var snap := func(v):
		return snappedf(float(v), 0.0001) if (v is float or v is int) else v
	var out := {"version": VERSION, "name": String(b.get("name", "Untitled")), "params": {}, "rooms": [], "openings": []}
	for k in b.get("params", {}):
		out["params"][k] = snap.call(b["params"][k])
	for r in b.get("rooms", []):
		var e := {}
		for f in r:
			e[f] = snap.call(r[f])
		out["rooms"].append(e)
	for o in b.get("openings", []):
		var e := {}
		for f in o:
			e[f] = snap.call(o[f])
		out["openings"].append(e)
	if not b.get("walls", []).is_empty():
		out["walls"] = b["walls"].map(func(w): return _snapped_copy(w))
	if not b.get("roof", {}).is_empty():
		out["roof"] = _snapped_copy(b["roof"])
	if not b.get("pieces", []).is_empty():
		out["pieces"] = b["pieces"].map(func(p): return _snapped_copy(p))
	if not b.get("nature", []).is_empty():
		out["nature"] = b["nature"].map(func(n): return Nature.snap_item(n))   # FRIDAY 225: trees, hedges, grass, scatter (scripts/build/nature.gd)
	return out


static func _snapped_copy(d: Dictionary) -> Dictionary:
	var e := {}
	for f in d:
		e[f] = snappedf(float(d[f]), 0.0001) if (d[f] is float or d[f] is int) else d[f]
	return e


## the other way. Absent / not a dictionary = {} (no building). A param out of its range is clamped, an unknown wall or
## kind drops that opening, an opening on a room that is not there is dropped. A record from a NEWER Kine (version above
## VERSION) is kept whole and read only: {"version", "readonly": true, "raw"} (saving writes it back untouched)
static func from_file(d: Variant) -> Dictionary:
	if not (d is Dictionary) or (d as Dictionary).is_empty():
		return {}
	if int(d.get("version", 1)) > VERSION:
		return {"version": int(d["version"]), "readonly": true, "raw": (d as Dictionary).duplicate(true), "name": String(d.get("name", "Untitled"))}
	var b := make(String(d.get("name", "Untitled")))
	var fp: Dictionary = d.get("params", {}) if d.get("params") is Dictionary else {}
	for k in fp:
		var v = fp[k]
		if not (v is float or v is int) or not is_finite(float(v)):
			continue
		b["params"][k] = clampf(float(v), PARAMS[k][1], PARAMS[k][2]) if PARAMS.has(k) else float(v)
	var ok_num := func(v) -> bool:
		return v is String or ((v is float or v is int) and is_finite(float(v)))
	for r in d.get("rooms", []):
		if not (r is Dictionary) or not r.has("id"):
			continue
		var e := {"id": String(r["id"]), "x": float(r.get("x", 0.0)), "z": float(r.get("z", 0.0)),
			"w": maxf(float(r.get("w", 4.0)), MIN_SIZE), "d": maxf(float(r.get("d", 3.0)), MIN_SIZE), "yaw": float(r.get("yaw", 0.0)),
			"height": r.get("height", "wall_height") if ok_num.call(r.get("height", "wall_height")) else "wall_height",
			"thickness": r.get("thickness", "wall_thickness") if ok_num.call(r.get("thickness", "wall_thickness")) else "wall_thickness",
			"floor": bool(r.get("floor", true))}
		if int(r.get("storey", 0)) > 0:
			e["storey"] = mini(int(r["storey"]), 30)
		b["rooms"].append(e)
	for iw in d.get("walls", []):
		if not (iw is Dictionary) or room_of(b, String(iw.get("room", ""))).is_empty() or not ["x", "z"].has(String(iw.get("axis", ""))):
			continue
		var pos = iw.get("pos", 0.0)
		if not (pos is float or pos is int) or not is_finite(float(pos)):
			continue
		var th = iw.get("thickness", "inner_wall_thickness")
		if not b.has("walls"):
			b["walls"] = []
		b["walls"].append({"id": String(iw.get("id", _new_id(b["walls"], "i"))), "room": String(iw["room"]), "axis": String(iw["axis"]), "pos": float(pos),
			"thickness": th if ok_num.call(th) else "inner_wall_thickness"})
	for pd in d.get("pieces", []):
		var pc := BuildPieces.clean(pd)
		if pc.is_empty():
			continue
		if not b.has("pieces"):
			b["pieces"] = []
		if not (pd as Dictionary).has("id") or not piece_of(b, String(pc["id"])).is_empty():
			pc["id"] = _new_id(b["pieces"], "p")
		b["pieces"].append(pc)
	var nat := Nature.from_file(d.get("nature", []))
	if not nat.is_empty():
		b["nature"] = nat
	var rf = d.get("roof", {})
	if rf is Dictionary and ROOFS.has(String(rf.get("kind", ""))):
		var pitch = rf.get("pitch", ROOF_PITCH)
		var ovh = rf.get("overhang", "roof_overhang")
		b["roof"] = {"kind": String(rf["kind"]), "pitch": clampf(float(pitch), 1.0, 70.0) if (pitch is float or pitch is int) and is_finite(float(pitch)) else ROOF_PITCH,
			"overhang": ovh if ok_num.call(ovh) else "roof_overhang"}
	for o in d.get("openings", []):
		if not (o is Dictionary) or not KINDS.has(String(o.get("kind", ""))):
			continue
		var ow := String(o.get("wall", ""))
		if not WALLS.has(ow) and (wall_of(b, ow).is_empty() or String(wall_of(b, ow)["room"]) != String(o.get("room", ""))):
			continue
		if room_of(b, String(o.get("room", ""))).is_empty():
			continue
		var e := {"id": String(o.get("id", _new_id(b["openings"], "o"))), "room": String(o["room"]), "wall": String(o["wall"]),
			"kind": String(o["kind"]), "at": float(o.get("at", 0.0))}
		for f in ["w", "h", "sill"]:
			if o.has(f) and ok_num.call(o[f]):
				e[f] = o[f]
		b["openings"].append(e)
	return b


## the record mirrored across x = 0 (Scene.mirror_file): each room's far corner becomes its near one, its yaw negated;
## left <-> right walls, an opening's "at" on the front / back walls negated. Twice = the original
static func mirror_file(d: Dictionary) -> Dictionary:
	if int(d.get("version", 1)) > VERSION:
		return d.duplicate(true)   # a newer record: not ours to change
	var out: Dictionary = d.duplicate(true)
	for r in out.get("rooms", []):
		var yaw := deg_to_rad(float(r.get("yaw", 0.0)))
		var far := Vector3(float(r["x"]), 0, float(r["z"])) + Vector3(float(r["w"]), 0, 0).rotated(Vector3.UP, yaw)
		r["x"] = -far.x
		r["z"] = far.z
		r["yaw"] = -float(r.get("yaw", 0.0))
	for pc in out.get("pieces", []):
		pc["x"] = -float(pc["x"])
		pc["yaw"] = fposmod(-float(pc.get("yaw", 0.0)), 360.0)
		if String(pc.get("kind", "")) == "stairs_l":
			if bool(pc.get("flip", false)):
				pc.erase("flip")
			else:
				pc["flip"] = true
	if out.has("nature"):
		out["nature"] = Nature.mirror_list(out["nature"])
	var inner := {}
	for iw in out.get("walls", []):
		var rm := {}
		for r in out.get("rooms", []):
			if String(r["id"]) == String(iw["room"]):
				rm = r
		inner[String(iw["id"])] = String(iw.get("axis", "z"))
		if String(iw.get("axis", "z")) == "z" and not rm.is_empty():
			iw["pos"] = float(rm["w"]) - float(iw["pos"])   # x runs the other way: from the new corner
	for o in out.get("openings", []):
		var wl := String(o.get("wall", ""))
		match wl:
			"left":
				o["wall"] = "right"
			"right":
				o["wall"] = "left"
			"front", "back":
				o["at"] = -float(o.get("at", 0.0))
			_:
				if inner.get(wl, "z") == "x":
					o["at"] = -float(o.get("at", 0.0))
	return out
