class_name Lighter
extends RefCounted
## MAKE IT LIGHTER (Friday plan 195). A RULE OF THUMB, NOT A STRESS SIMULATION: nothing here computes a stress. The part is a flat plate seen from the
## front (x, y in mm; the holes go through the thin way). The user says where it is HELD and where it is PUSHED (a side each); the straight line
## between the two faces' middles is the load path. A grid of round holes is laid over the plate; a hole is bigger the further its cell is from that
## line and the further from the held and pushed ends, and every hole is kept MARGIN mm from every edge (held face, pushed face, outer edges) and RIB mm
## from the next hole, so the plate stays ONE solid. The slider "How much lighter" (0..1) grows the holes; no hole is bigger than its cell allows.
const MARGIN := 3.5      # mm: solid left between any hole and any edge (the held face, the pushed face and the outer edges)
const RIB := 3.0         # mm: the least rib between two holes
const RMIN := 1.5        # mm: a hole smaller than this (3 mm across) is not worth printing: it is left out
const END_SHARE := 0.15  # the share of the load path, at each end, where the holes are made smaller (the ends carry the load in)
const SIDES := ["bottom", "top", "left", "right"]


## the middle of one side of the plate: lt = {"x0", "y0", "w", "h"} (mm)
static func side_point(lt: Dictionary, side: String) -> Vector2:
	var x0 := float(lt["x0"])
	var y0 := float(lt["y0"])
	var w := float(lt["w"])
	var h := float(lt["h"])
	match side:
		"left":
			return Vector2(x0, y0 + h * 0.5)
		"right":
			return Vector2(x0 + w, y0 + h * 0.5)
		"bottom":
			return Vector2(x0 + w * 0.5, y0)
	return Vector2(x0 + w * 0.5, y0 + h)


## how far a point is from a side's face (mm, along the plate)
static func side_dist(lt: Dictionary, side: String, p: Vector2) -> float:
	match side:
		"left":
			return p.x - float(lt["x0"])
		"right":
			return float(lt["x0"]) + float(lt["w"]) - p.x
		"bottom":
			return p.y - float(lt["y0"])
	return float(lt["y0"]) + float(lt["h"]) - p.y


static func side_word(side: String) -> String:
	return {"left": "left end", "right": "right end", "bottom": "bottom", "top": "top"}[side]


## the holes for a plate lt = {"x0", "y0", "w", "h", "held", "push"} at lightness s (0..1): {"ents": circles for a sketch, "n": count, "r_max": mm}
static func plan(lt: Dictionary, s: float) -> Dictionary:
	var x0 := float(lt["x0"])
	var y0 := float(lt["y0"])
	var w := float(lt["w"])
	var h := float(lt["h"])
	var held := String(lt["held"])
	var push := String(lt["push"])
	var out := {"ents": [], "n": 0, "r_max": 0.0}
	var inset := MARGIN - RIB * 0.5   # the grid's edge: a hole at its cell's limit is then MARGIN from the plate's edge
	var iw := w - 2.0 * inset
	var ih := h - 2.0 * inset
	if iw < 4.0 or ih < 4.0 or held == push:
		return out
	var pitch := clampf(0.4 * minf(w, h), 10.0, 30.0)
	var nx := maxi(1, roundi(iw / pitch))
	var ny := maxi(1, roundi(ih / pitch))
	var cw := iw / float(nx)
	var ch := ih / float(ny)
	var rmax := (minf(cw, ch) - RIB) * 0.5
	if rmax < RMIN:
		return out
	out["r_max"] = rmax
	var a := side_point(lt, held)
	var b := side_point(lt, push)
	var path_len := a.distance_to(b)
	var zone := maxf(END_SHARE * path_len, 8.0)
	var cells: Array = []
	var dmax := 0.0
	for i in nx:
		for j in ny:
			var c := Vector2(x0 + inset + (float(i) + 0.5) * cw, y0 + inset + (float(j) + 0.5) * ch)
			var d := _dist_to_segment(c, a, b)
			dmax = maxf(dmax, d)
			cells.append([c, d])
	var ents: Array = []
	for cd in cells:
		var c: Vector2 = cd[0]
		var wt := float(cd[1]) / dmax if dmax > 1e-6 else 1.0   # 0 on the load path .. 1 furthest from it
		var e := minf(side_dist(lt, held, c), side_dist(lt, push, c))
		var we := clampf(e / zone, 0.0, 1.0)
		var t := 0.4 * (1.0 - wt)   # the lightness at which this cell's hole first shows: furthest cells first
		var grow := clampf((s - t) / (1.0 - t), 0.0, 1.0)
		var r := rmax * (0.4 + 0.6 * wt) * (0.5 + 0.5 * we) * sqrt(grow)
		if r >= RMIN:
			ents.append({"k": "circle", "c": [snappedf(c.x, 0.001), snappedf(c.y, 0.001)], "r": snappedf(r, 0.001)})
	out["ents"] = ents
	out["n"] = ents.size()
	return out


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-9:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))
