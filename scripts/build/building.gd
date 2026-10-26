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
}
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


## an opening on a room's wall; its sizes follow the kind's params. Returns its id ("" when the room or wall is unknown)
static func add_opening(b: Dictionary, room: String, wall: String, kind := "door", at := 0.0) -> String:
	if room_of(b, room).is_empty() or not WALLS.has(wall) or not KINDS.has(kind):
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

## the room's boxes in its group frame (turned by -yaw about the world origin, so the room is axis-aligned):
## [[AABB, role, +1 solid / -1 cut]]
static func _room_boxes(b: Dictionary, r: Dictionary) -> Array:
	var yaw := deg_to_rad(float(r.get("yaw", 0.0)))
	var c := Vector3(float(r["x"]), 0, float(r["z"])).rotated(Vector3.UP, -yaw)
	var w := float(r["w"])
	var d := float(r["d"])
	var h := num(b, r.get("height"), 2.7)
	var t := clampf(num(b, r.get("thickness"), 0.2), 0.01, minf(w, d) * 0.5 - 0.01)
	var out := [
		[AABB(c, Vector3(w, h, t)), "wall", 1], [AABB(c + Vector3(0, 0, d - t), Vector3(w, h, t)), "wall", 1],
		[AABB(c + Vector3(0, 0, t), Vector3(t, h, d - 2 * t)), "wall", 1], [AABB(c + Vector3(w - t, 0, t), Vector3(t, h, d - 2 * t)), "wall", 1]]
	if bool(r.get("floor", true)):
		var ft := num(b, b["params"].get("floor_thickness"), 0.2)
		out.append([AABB(c + Vector3(0, -ft, 0), Vector3(w, ft, d)), "floor", 1])
	for o in b.get("openings", []):
		if String(o.get("room", "")) == String(r["id"]):
			out.append([opening_box(b, r, o, c), "opening", -1])
	return out


## an opening's cut box (group frame, corner c), clamped onto its wall between the corner walls and under the wall top
static func opening_box(b: Dictionary, r: Dictionary, o: Dictionary, c := Vector3.INF) -> AABB:
	if c == Vector3.INF:
		c = Vector3(float(r["x"]), 0, float(r["z"])).rotated(Vector3.UP, -deg_to_rad(float(r.get("yaw", 0.0))))
	var w := float(r["w"])
	var d := float(r["d"])
	var h := num(b, r.get("height"), 2.7)
	var t := clampf(num(b, r.get("thickness"), 0.2), 0.01, minf(w, d) * 0.5 - 0.01)
	var wall := String(o.get("wall", "front"))
	var along_x := wall == "front" or wall == "back"
	var span := (w if along_x else d) - 2 * t
	var ow := clampf(num(b, o.get("w"), 0.9), 0.05, span)
	var sill := clampf(num(b, o.get("sill"), 0.0), 0.0, h - 0.05)
	var oh := clampf(num(b, o.get("h"), 2.1), 0.05, h - sill)
	var mid := (w if along_x else d) * 0.5 + clampf(num(b, o.get("at"), 0.0), -(span - ow) * 0.5, (span - ow) * 0.5)
	var lo := mid - ow * 0.5
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
static func to_kmesh(b: Dictionary, roles := ["wall", "floor"]) -> KMesh:
	var acc := {"verts": [], "faces": []}   # a Dictionary: the mesher's lambdas share it (a captured packed array is a copy)
	var g := _groups(b)
	for yaw in g:
		var boxes := []
		for r in g[yaw]:
			boxes.append_array(_room_boxes(b, r))
		_mesh_grid(_grid(boxes, roles), Basis(Vector3.UP, deg_to_rad(yaw)), acc)
	return KMesh.new().from_arrays(PackedVector3Array(acc["verts"]), acc["faces"])


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
static func to_array_mesh(b: Dictionary, roles := ["wall", "floor"]) -> ArrayMesh:
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
	return out


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
		b["rooms"].append(e)
	for o in d.get("openings", []):
		if not (o is Dictionary) or not WALLS.has(String(o.get("wall", ""))) or not KINDS.has(String(o.get("kind", ""))):
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
	for o in out.get("openings", []):
		match String(o.get("wall", "")):
			"left":
				o["wall"] = "right"
			"right":
				o["wall"] = "left"
			_:
				o["at"] = -float(o.get("at", 0.0))
	return out
