class_name PipeParts
extends RefCounted
## s079 / Friday plan 79: PVC pipe and its fittings by the real outside diameter (Parts > Pipes). Straight pipe (length slider), 90 and 45 degree elbows,
## T-piece, and a connector sleeve that slips over the pipe with the Fit clearance (s202). Sizes in mm.
##
## Every pipe, elbow and tee is a SWEEP of a disc along a path drawn on the Top plane (the path's x is world X, its y is world -Z), with the bore swept out
## of it by a second disc (op cut). Both bends use the SAME explicit arc, so the bore stays concentric with the outside. The sleeve is a revolved rectangle
## (no cut: a cut would take the pipe's wall too, the kernel cuts every body). A piece is built from a POSE [u, v, heading] on the path plane, so the same
## code makes the first piece (pose 0, 0, 0) and the pieces added behind it (the pose the last piece ended in).
## Wall: PVC-U pressure pipe PN16 (SDR 13.6), the usual stock sizes.

const KINDS := ["pipe", "elbow", "elbow45", "tee", "sleeve"]
const KIND_WORDS := {"pipe": "Pipe", "elbow": "Elbow 90", "elbow45": "Elbow 45", "tee": "T-piece", "sleeve": "Sleeve"}
const DS := [20, 25, 32, 40, 50]
const WALL := {20: 1.5, 25: 1.9, 32: 2.4, 40: 3.0, 50: 3.7}   # mm, outside diameter -> wall (PVC-U PN16)
const SLEEVE_LEN := 40.0
const FIT_NAMES := ["Tight", "Snug", "Slides", "Loose"]
const FIT_MM := [0.0, 0.1, 0.2, 0.4]
const FIT_DEFAULT := 0.2
## the number of features each kind takes: fixed per kind, so a size or length change rewrites them in place
const COUNT := {"pipe": 5, "elbow": 5, "elbow45": 5, "tee": 10, "sleeve": 2}


static func wall(d: float) -> float:
	return float(WALL.get(int(roundf(d)), snappedf(d * 0.074, 0.1)))


## the bend's centre-line radius (mm) for pipe size d
static func bend_r(d: float) -> float:
	return 1.5 * d


static func _dir(h: float) -> Vector2:
	return Vector2(sin(h), cos(h))


static func _nrm(a: float) -> Vector2:
	return Vector2(cos(a), -sin(a))


static func _line(a: Vector2, b: Vector2) -> Dictionary:
	return {"k": "line", "a": Part.arr2(a), "b": Part.arr2(b)}


static func _disc(r: float) -> Array:
	return [{"k": "circle", "c": [0.0, 0.0], "r": r}]


static func _sk(fs: Array, plane_name: String, ents: Array) -> String:
	var id := "f%d" % (fs.size() + 1)
	var n := fs.filter(func(f): return f["t"] == "sketch").size() + 1
	fs.append({"t": "sketch", "id": id, "name": "Sketch%d" % n, "plane": plane_name, "ents": ents, "dims": []})
	return id


static func _sweep(fs: Array, prof: String, path: String, op: String) -> void:
	var id := "f%d" % (fs.size() + 1)
	var n := fs.filter(func(f): return f["t"] == "sweep").size() + 1
	fs.append({"t": "sweep", "id": id, "name": "Sweep%d" % n, "profile": prof, "path": path, "op": op})


## a tube: the outside disc swept along the path (op "new"), then the bore swept along the same path (cut). 5 features
static func _tube(fs: Array, path_ents: Array, ro: float, ri: float) -> void:
	var pp := _sk(fs, "top", path_ents)
	_sweep(fs, _sk(fs, "front", _disc(ro)), pp, "new")
	_sweep(fs, _sk(fs, "front", _disc(ri)), pp, "cut")


## the features of one piece appended to fs (the ids go on from fs). Returns the pose the next piece starts from: [u, v, heading]
## u / v on the Top plane (world X, -Z); heading 0 runs along -Z (the way the first pipe runs), a turn of +90 degrees goes toward +X.
static func add_piece(fs: Array, kind: String, d: float, pose: Array, plen := 300.0, fit := FIT_DEFAULT) -> Array:
	var P := Vector2(float(pose[0]), float(pose[1]))
	var h := float(pose[2])
	var ro := d * 0.5
	var ri := ro - wall(d)
	if kind == "pipe":
		var q := P + _dir(h) * plen
		_tube(fs, [_line(P, q)], ro, ri)
		return [q.x, q.y, h]
	if kind == "elbow" or kind == "elbow45":
		var th := deg_to_rad(90.0 if kind == "elbow" else 45.0)
		var rb := bend_r(d)
		var a := P + _dir(h) * d   # a straight socket stub of one diameter on each end of the bend
		var c := a + _nrm(h) * rb
		var b := c - _nrm(h + th) * rb
		var mpt := c - _nrm(h + th * 0.5) * rb
		var q2 := b + _dir(h + th) * d
		_tube(fs, [_line(P, a), {"k": "arc", "a": Part.arr2(a), "m": Part.arr2(mpt), "b": Part.arr2(b)}, _line(b, q2)], ro, ri)
		return [q2.x, q2.y, h + th]
	if kind == "tee":
		var lg := 1.5 * d
		var mid := P + _dir(h) * lg
		var q3 := P + _dir(h) * (2.0 * lg)
		var br := mid + _nrm(h) * lg
		var run := _sk(fs, "top", [_line(P, q3)])
		_sweep(fs, _sk(fs, "front", _disc(ro)), run, "new")
		var branch := _sk(fs, "top", [_line(mid, br)])
		_sweep(fs, _sk(fs, "front", _disc(ro)), branch, "join")
		_sweep(fs, _sk(fs, "front", _disc(ri)), run, "cut")
		_sweep(fs, _sk(fs, "front", _disc(ri)), branch, "cut")
		return [q3.x, q3.y, h]
	# sleeve: a revolved rectangle round the Z axis, the last SLEEVE_LEN of the straight run that ends at the pose (heading 0, on the axis)
	var rin := ro + fit
	var rout := rin + wall(d)
	var v1 := maxf(P.y, SLEEVE_LEN)
	var sid := _sk(fs, "top", [{"k": "rect", "a": [rin, v1 - SLEEVE_LEN], "b": [rout, v1]}])
	var id := "f%d" % (fs.size() + 1)
	var n := fs.filter(func(f): return f["t"] == "revolve").size() + 1
	fs.append({"t": "revolve", "id": id, "name": "Revolve%d" % n, "sketch": sid, "axis": "y", "deg": 360.0, "op": "new"})
	return [P.x, P.y, h]


## the template's own features (the first piece, from pose 0, 0, 0): p holds d (outside mm), len (pipe length mm) and fit (sleeve clearance mm)
static func features_of(kind: String, p: Dictionary) -> Array:
	var fs: Array = []
	add_piece(fs, kind, float(p["d"]), [0.0, 0.0, 0.0], float(p.get("len", 300.0)), float(p.get("fit", FIT_DEFAULT)))
	return fs
