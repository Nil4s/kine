class_name FlatPattern
extends RefCounted
## p117flatpatter (Kine's own): the flat pattern of a plain box for sheet material (laser cut). The six faces lie in a cross
## (top over the front, bottom under it, left, front, right and back in a strip). Each box edge that is cut has FINGER JOINTS:
## an odd number of fingers, each about the sheet thickness wide, the first and last one a tab. A tab sticks out by the sheet
## thickness; the matching slot is cut in by the same amount on the panel it goes into. The five fold lines stay straight.
## net() is pure geometry in mm (no nodes): the view draws it and the Easy Part chip asks for it.

const SHEET_MM := 3.0   # the sheet's thickness (mm): a finger is about this wide, a tab sticks out by this much

## the seven cut edges: [tab panel, its side, slot panel, its side, box edge length key]. Sides: N top, E right, S bottom, W left
const JOINTS := [
	["top", "W", "left", "N", "z"],
	["top", "E", "right", "N", "z"],
	["top", "N", "back", "N", "x"],
	["bottom", "W", "left", "S", "z"],
	["bottom", "E", "right", "S", "z"],
	["bottom", "S", "back", "S", "x"],
	["back", "E", "left", "W", "y"],
]
const PANEL_ORDER := ["top", "left", "front", "right", "back", "bottom"]


## the flat pattern of a box sx x sy x sz (mm). Returns {pieces: [{name, pts (mm, outline), rect (mm, the flat face)}], sheet (Vector2 mm
## of the cross without tabs), joints, tabs, slots, finger_mm (the finger width used for each joint, mm)}
static func net(sx: float, sy: float, sz: float, t := SHEET_MM) -> Dictionary:
	var rect := {
		"top": Rect2(sz, 0.0, sx, sz),
		"left": Rect2(0.0, sz, sz, sy),
		"front": Rect2(sz, sz, sx, sy),
		"right": Rect2(sz + sx, sz, sz, sy),
		"back": Rect2(2.0 * sz + sx, sz, sx, sy),
		"bottom": Rect2(sz, sz + sy, sx, sz),
	}
	var edge := {"x": sx, "y": sy, "z": sz}
	var kind := {}   # "panel.side" -> [kind, fingers, finger width mm]
	var finger_mm := []
	for j in JOINTS:
		var len_mm: float = edge[j[4]]
		var n := 2 * int(floor(len_mm / (2.0 * t))) + 1   # odd, so both ends of the joint are tabs
		kind[j[0] + "." + j[1]] = ["tab", n, len_mm / n]
		kind[j[2] + "." + j[3]] = ["slot", n, len_mm / n]
		finger_mm.append(len_mm / n)
	var pieces := []
	var tabs := 0
	var slots := 0
	for nm in PANEL_ORDER:
		var r: Rect2 = rect[nm]
		var sides := [
			["N", r.position, Vector2(1, 0), Vector2(0, -1), r.size.x],
			["E", Vector2(r.end.x, r.position.y), Vector2(0, 1), Vector2(1, 0), r.size.y],
			["S", r.end, Vector2(-1, 0), Vector2(0, 1), r.size.x],
			["W", Vector2(r.position.x, r.end.y), Vector2(0, -1), Vector2(-1, 0), r.size.y],
		]
		var side_pts := []
		var first_o := []
		var last_o := []
		for sd in sides:
			var k: Array = kind.get(nm + "." + sd[0], ["fold", 1, float(sd[4])])
			var n: int = k[1]
			var w: float = k[2]
			var pts := PackedVector2Array()
			var offs := []
			for i in n:
				var o := 0.0
				if k[0] == "tab" and i % 2 == 0:
					o = t
					tabs += 1
				elif k[0] == "slot" and i % 2 == 0:
					o = -t
					slots += 1
				offs.append(o)
				pts.append(sd[1] + sd[2] * (i * w) + sd[3] * o)
				pts.append(sd[1] + sd[2] * ((i + 1) * w) + sd[3] * o)
			side_pts.append(pts)
			first_o.append(offs[0])
			last_o.append(offs[offs.size() - 1])
		# the corner between one side and the next: both offsets at once (a square tab or notch at a corner)
		var outline := PackedVector2Array()
		for si in 4:
			outline.append_array(side_pts[si])
			var nx := (si + 1) % 4
			var sd0: Array = sides[si]
			var sd1: Array = sides[nx]
			var corner: Vector2 = sd0[1] + sd0[2] * float(sd0[4])
			outline.append(corner + sd0[3] * float(last_o[si]) + sd1[3] * float(first_o[nx]))
		pieces.append({"name": nm, "pts": _no_repeats(outline), "rect": r})   # a square corner with no tab repeats its point: Godot cannot draw that
	return {"pieces": pieces, "sheet": Vector2(2.0 * sz + 2.0 * sx, 2.0 * sz + sy), "joints": JOINTS.size(), "tabs": tabs, "slots": slots, "finger_mm": finger_mm, "t": t}


## the outline without a point that repeats the one before it (a corner with no tab gives three points at one spot)
static func _no_repeats(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in pts:
		if out.is_empty() or out[out.size() - 1].distance_to(v) > 1e-6:
			out.append(v)
	while out.size() > 1 and out[0].distance_to(out[out.size() - 1]) <= 1e-6:
		out.remove_at(out.size() - 1)
	return out
