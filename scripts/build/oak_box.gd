class_name OakBox
extends RefCounted
## CH4 THE OAK BOX (docs/CH4_REFERENCE.md): four 12 mm boards joined with through dovetails (slope 1:8, three tails, two pins and two half-pins across
## 70 mm) and a lid with a 3 mm chamfer, as ONE Part record (prims, offset planes, sketches, extrude CUTS, a chamfer, solid-wood looks). Every board
## carries its own tree (pith + axis) in its look, so its grain is a 3D field and the dovetail flanks, the end grain and the chamfer show cut grain.
## Millimetres. X along the box (160), Y up (70), Z across (100). Body order: 0 Front, 1 Back, 2 Left, 3 Right, 4 Lid.

const NAMES := ["Front", "Back", "Left", "Right", "Lid"]
const L := 160.0   # outside length (X)
const W := 100.0   # outside width (Z)
const H := 70.0    # board height (Y)
const T := 12.0    # board thickness = tail depth
const HP := 8.0    # half-pin width on the outside
const TW := 14.0   # tail width on the outside
const PW := 6.0    # pin width on the outside
const NT := 3      # tails
const LID_T := 10.0
const LID_OVER := 4.0


## the trees: [pith, axis, seed, ring mm]
static func spec_of(i: int) -> Dictionary:
	match i:
		0: return {"kind": WoodSolid.KIND, "seed": 11, "pith": [80.0, 35.0, 75.0], "dir": [1.0, 0.0, -0.03], "ring": 2.0, "oval_ang": 20.0}
		1: return {"kind": WoodSolid.KIND, "seed": 12, "pith": [75.0, 30.0, 25.0], "dir": [1.0, 0.0, 0.03], "ring": 2.2, "oval_ang": 70.0}
		2: return {"kind": WoodSolid.KIND, "seed": 13, "pith": [76.0, 35.0, 50.0], "dir": [-0.03, 0.0, 1.0], "ring": 1.9, "oval_ang": 40.0}
		3: return {"kind": WoodSolid.KIND, "seed": 14, "pith": [84.0, 38.0, 50.0], "dir": [0.03, 0.0, 1.0], "ring": 2.1, "oval_ang": 110.0}
	return {"kind": WoodSolid.KIND, "seed": 15, "pith": [80.0, 25.0, 54.0], "dir": [1.0, -0.08, 0.0], "ring": 2.4, "oval_ang": 10.0}


static func _poly(pts: Array) -> Array:
	var out := []
	for k in pts.size():
		var a: Vector2 = pts[k]
		var b: Vector2 = pts[(k + 1) % pts.size()]
		out.append({"k": "line", "a": [a.x, a.y], "b": [b.x, b.y]})
	return out


## the loops of one corner as sketch entities. mirror: the corner at the far end (x -> L - x). sockets: the tails grown by gap (cut from the pin board); else the pins (cut from the tail board)
static func corner_loops(mirror: bool, sockets: bool, slope: float, gap: float) -> Array:
	var s := 1.0 / slope
	var loops := []
	var fx := func(x: float) -> float: return (L - x) if mirror else x
	var mk := func(pts: Array) -> Array:
		var q := []
		for p in pts:
			q.append(Vector2(fx.call(p.x), p.y))
		return _poly(q)
	if sockets:
		for k in NT:
			var y0 := HP + k * (TW + PW)
			var yl := func(x: float) -> float: return y0 + x * s - gap
			var yr := func(x: float) -> float: return y0 + TW - x * s + gap
			loops.append_array(mk.call([Vector2(-1, yl.call(-1.0)), Vector2(-1, yr.call(-1.0)), Vector2(T + 1, yr.call(T + 1.0)), Vector2(T + 1, yl.call(T + 1.0))]))
	else:
		loops.append_array(mk.call([Vector2(-1, -1), Vector2(-1, HP - s), Vector2(T, HP + T * s), Vector2(T, -1)]))
		for j in NT - 1:
			var ya := HP + j * (TW + PW) + TW   # the pin between tail j and tail j+1 on the outside: ya .. ya + PW
			loops.append_array(mk.call([Vector2(-1, ya + s), Vector2(-1, ya + PW - s), Vector2(T, ya + PW + T * s), Vector2(T, ya - T * s)]))
		var ye := HP + (NT - 1) * (TW + PW) + TW
		loops.append_array(mk.call([Vector2(-1, ye + s), Vector2(-1, H + 1), Vector2(T, H + 1), Vector2(T, ye - T * s)]))
	return loops


static func record(slope := 8.0, gap := 0.05, chamfer := 3.0) -> Dictionary:
	var rec := Part.make("Oak dovetail box (CH4)")
	var fs: Array = rec["features"]
	fs.append(Part.new_feature(rec, "prim", {"kind": "box", "op": "new", "name": "Front", "x": 0, "y": 0, "z": 0, "w": L, "h": H, "d": T}))
	fs.append(Part.new_feature(rec, "prim", {"kind": "box", "op": "new", "name": "Back", "x": 0, "y": 0, "z": W - T, "w": L, "h": H, "d": T}))
	fs.append(Part.new_feature(rec, "prim", {"kind": "box", "op": "new", "name": "Left", "x": 0, "y": 0, "z": 0, "w": T, "h": H, "d": W}))
	fs.append(Part.new_feature(rec, "prim", {"kind": "box", "op": "new", "name": "Right", "x": L - T, "y": 0, "z": 0, "w": T, "h": H, "d": W}))
	fs.append(Part.new_feature(rec, "prim", {"kind": "box", "op": "new", "name": "Lid", "x": -LID_OVER, "y": H, "z": -LID_OVER, "w": L + 2 * LID_OVER, "h": LID_T, "d": W + 2 * LID_OVER}))
	var planes := {}
	for z in [0.0, W - T]:
		var pf := Part.new_feature(rec, "plane", {"from": "front", "mm": z})
		fs.append(pf)
		planes[z] = String(pf["id"])
	# the tail boards lose the pin spaces (both ends), the pin boards lose the tail sockets (both ends, one cut per end of the board)
	for k in 2:
		var z: float = [0.0, W - T][k]
		var ents := corner_loops(false, false, slope, gap)
		ents.append_array(corner_loops(true, false, slope, gap))
		var sk := Part.new_feature(rec, "sketch", {"plane": planes[z], "ents": ents, "dims": []})
		fs.append(sk)
		fs.append(Part.new_feature(rec, "extrude", {"sketch": sk["id"], "dist": T, "both": false, "op": "cut", "into": k}))
		for m in 2:
			var sk2 := Part.new_feature(rec, "sketch", {"plane": planes[z], "ents": corner_loops(m == 1, true, slope, gap), "dims": []})
			fs.append(sk2)
			fs.append(Part.new_feature(rec, "extrude", {"sketch": sk2["id"], "dist": T, "both": false, "op": "cut", "into": 2 + m}))
	if chamfer > 0.0:
		var yt := H + LID_T
		var x0 := -LID_OVER
		var x1 := L + LID_OVER
		var z0 := -LID_OVER
		var z1 := W + LID_OVER
		var edges := [
			{"p": [(x0 + x1) / 2, yt, z0], "q": [0.5, 1.0, 0.0], "d": [1, 0, 0]}, {"p": [(x0 + x1) / 2, yt, z1], "q": [0.5, 1.0, 1.0], "d": [1, 0, 0]},
			{"p": [x0, yt, (z0 + z1) / 2], "q": [0.0, 1.0, 0.5], "d": [0, 0, 1]}, {"p": [x1, yt, (z0 + z1) / 2], "q": [1.0, 1.0, 0.5], "d": [0, 0, 1]}]
		fs.append(Part.new_feature(rec, "chamfer", {"body": 4, "dist": chamfer, "edges": edges}))
	for i in 5:
		fs.append(Part.new_feature(rec, "appear", {"body": i, "color": [0.8, 0.63, 0.48], "rough": 0.6, "metal": 0.0, "preset": "Custom", "mat": spec_of(i)}))
	return rec
